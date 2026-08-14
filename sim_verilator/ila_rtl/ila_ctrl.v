`timescale 1ns / 1ps
`include "ila_pkg.vh"
// ==========================================================================
// ila_ctrl — 运行期寄存器组 + 控制信号生成
//
// 提供协议侧的寄存器读写总线（由 Hub 驱动），产生 arm/disarm/force 脉冲、
// 触发值/掩码、窗口数、采样长度、触发位置等运行期配置，并回读身份/结构/状态。
//
// Phase 1：寄存器总线与采样链路同处 clk 域（单时钟 TB 可直测）。
// TODO(Phase 3)：Hub 接异步传输时，在此加入 reg 总线 CDC 握手。
// ==========================================================================
module ila_ctrl #(
    parameter DATA_W      = 32,
    parameter DEPTH       = 1024,
    parameter ADDR_W      = 10,
    parameter MAX_WINDOWS = 4,
    parameter NWORDS      = 1,
    parameter NUM_PROBES  = 1,
    parameter SAMPLE_HZ   = 32'd125000000,
    parameter [31:0] SIGN_L = 32'h0,
    parameter [31:0] SIGN_H = 32'h0,
    // per-probe widths (PROBE_WIDTH_BASE + i → 该探针位宽)
    parameter PW0=1,PW1=1,PW2=1,PW3=1,PW4=1,PW5=1,PW6=1,PW7=1,
    parameter PW8=1,PW9=1,PW10=1,PW11=1,PW12=1,PW13=1,PW14=1,PW15=1,
    parameter PW16=1,PW17=1,PW18=1,PW19=1,PW20=1,PW21=1,PW22=1,PW23=1,
    parameter PW24=1,PW25=1,PW26=1,PW27=1,PW28=1,PW29=1,PW30=1,PW31=1
) (
    input  wire                 clk,
    input  wire                 rst,     // 高有效同步复位

    // 寄存器总线（来自 Hub / TB）
    input  wire                 reg_we,
    input  wire                 reg_re,  // 预留（组合读，暂未使用时序）
    input  wire [15:0]          reg_addr,
    input  wire [31:0]          reg_wdata,
    output reg  [31:0]          reg_rdata,

    // → ila_trigger
    output wire [32*NWORDS-1:0] trig_value,
    output wire [32*NWORDS-1:0] trig_mask,
    output wire [1:0]           trig_mode,

    // → ila_capture（控制脉冲 + 配置）
    output reg                  arm_pulse,
    output reg                  disarm_pulse,
    output reg                  force_pulse,
    output wire [15:0]          windows_num,
    output wire [ADDR_W:0]      capture_len,
    output reg  [ADDR_W:0]      pretrig_len,

    // ← ila_capture（状态）
    input  wire                 armed,
    input  wire                 triggered,
    input  wire                 full,
    input  wire [15:0]          cur_window,
    input  wire [ADDR_W:0]      fill_level,
    input  wire [MAX_WINDOWS*ADDR_W-1:0] win_start_flat,
    input  wire [ADDR_W:0]     trig_filled,    // 触发时刻 fill_level（REG_TRIG_FILLED）
    input  wire                 trig_was_force,// 触发源：1=force, 0=level（REG_TRIG_SRC）
    input  wire                 trig_req_val,  // 触发时刻 probe[0] 的值（REG_TRIG_REQ_VAL）
    input  wire [31:0]          trig_wr_data, // 触发时刻 sample[31:0]（REG_TRIG_WR_DATA）
    input  wire [31:0]          trig_wr_data_d1,// 周期 N+1 ram_wdata[31:0]（REG_TRIG_WR_DATA_D1）
    input  wire                 trig_wr_we,   // 触发时刻 ram_we（REG_TRIG_WR_WE）
    input  wire [ADDR_W-1:0]    trig_wr_addr, // 触发时刻 ram_waddr（REG_TRIG_WR_ADDR）
    // trace buffer
    input  wire [7:0]           trace_we,
    input  wire [7:0]           trace_req,
    input  wire [8*10-1:0]      trace_addr,
    input  wire [2:0]           trace_ptr,
    input  wire                 trace_done,

    // ↔ RAM 读口（寄存器式缓冲回读）
    output wire                 ram_rd_en,
    output wire [ADDR_W-1:0]    ram_rd_addr,
    input  wire [DATA_W-1:0]    ram_rd_data
);

    // ------------------------------------------------------------
    // 寄存器存储
    // ------------------------------------------------------------
    reg [31:0]      trig_value_r [0:NWORDS-1];
    reg [31:0]      trig_mask_r  [0:NWORDS-1];
    reg [15:0]      windows_num_r;
    reg [ADDR_W:0]  capture_len_r;
    reg [ADDR_W:0]   trig_pos_r;  // 直接存储 pretrig_len 值 (0 ~ capture_len-1)
    reg [1:0]       trig_mode_r;

    // 缓冲回读：连续读 mem[buf_addr_r]，2 拍后 buf_word 稳定
    reg [ADDR_W-1:0]     buf_addr_r;
    reg [DATA_W-1:0]     buf_word;
    wire [32*NWORDS-1:0] buf_word_pad = {{(32*NWORDS-DATA_W){1'b0}}, buf_word};
    assign ram_rd_en   = 1'b1;
    assign ram_rd_addr = buf_addr_r;

    integer j;

    // 扁平化触发值/掩码输出
    genvar gi;
    generate
        for (gi = 0; gi < NWORDS; gi = gi + 1) begin : g_tv
            assign trig_value[gi*32 +: 32] = trig_value_r[gi];
            assign trig_mask [gi*32 +: 32] = trig_mask_r [gi];
        end
    endgenerate

    assign trig_mode   = trig_mode_r;
    assign windows_num = windows_num_r;
    assign capture_len = capture_len_r;

    // trig_pos_r 直接存储 pretrig_len 值 (0 ~ capture_len-1)，不再用模式转换
    wire [ADDR_W:0] len   = capture_len_r;
    wire [ADDR_W:0] pretrig_c =
          (trig_pos_r > (len - 1'b1)) ? (len - 1'b1) : trig_pos_r;

    // 时序收敛：pretrig_len 打一拍输出，切断 capture_len_r → 采样域 FSM 的长组合链。
    // 复位值 = 复位默认配置（len=DEPTH, TRIGPOS_CENTER）的组合结果 DEPTH>>1，逐位一致。
    // 配置为准静态（仅 disarm 期间写，ARM 至少晚 2 拍到达），1 拍滞后功能不可见。
    always @(posedge clk) begin
        if (rst) pretrig_len <= (DEPTH[ADDR_W:0] >> 1);
        else     pretrig_len <= pretrig_c;
    end

    wire idle = (~armed) & (~full);

    // ------------------------------------------------------------
    // 地址译码辅助：统一到 32 位比较，数组索引用切片，规避跨工具位宽告警
    // ------------------------------------------------------------
    localparam [31:0] TV_LO = {16'b0, `REG_TRIG_VALUE0};
    localparam [31:0] TV_HI = TV_LO + NWORDS;
    localparam [31:0] TM_LO = {16'b0, `REG_TRIG_MASK0};
    localparam [31:0] TM_HI = TM_LO + NWORDS;
    localparam [31:0] WS_LO = {16'b0, `REG_WIN_START};
    localparam [31:0] WS_HI = WS_LO + MAX_WINDOWS;
    localparam [31:0] BD_LO = {16'b0, `REG_BUF_DATA};
    localparam [31:0] BD_HI = BD_LO + NWORDS;
    localparam IDXW  = (NWORDS      <= 1) ? 1 : $clog2(NWORDS);
    localparam WIDXW = (MAX_WINDOWS <= 1) ? 1 : $clog2(MAX_WINDOWS);

    wire [31:0]      addr32 = {16'b0, reg_addr};
    wire [31:0]      vdiff  = addr32 - TV_LO;
    wire [31:0]      mdiff  = addr32 - TM_LO;
    wire [31:0]      wdiff  = addr32 - WS_LO;
    wire [31:0]      bdiff  = addr32 - BD_LO;
    wire [IDXW-1:0]  vidx   = vdiff[IDXW-1:0];
    wire [IDXW-1:0]  midx   = mdiff[IDXW-1:0];
    wire [WIDXW-1:0] widx   = wdiff[WIDXW-1:0];
    wire [IDXW-1:0]  bidx   = bdiff[IDXW-1:0];

    // 缓冲字连续锁存（mem[buf_addr_r] 经 RAM 1 拍 + 此处 1 拍）
    always @(posedge clk) begin
        if (rst) buf_word <= {DATA_W{1'b0}};
        else     buf_word <= ram_rd_data;
    end

    // ------------------------------------------------------------
    // 写寄存器 + 控制脉冲
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            arm_pulse     <= 1'b0;
            disarm_pulse  <= 1'b0;
            force_pulse   <= 1'b0;
            windows_num_r <= 16'd1;
            capture_len_r <= DEPTH[ADDR_W:0];
            trig_pos_r    <= DEPTH[ADDR_W:0] >> 1;  // 默认居中
            trig_mode_r   <= 2'd0;
            buf_addr_r    <= {ADDR_W{1'b0}};
            for (j = 0; j < NWORDS; j = j + 1) begin
                trig_value_r[j] <= 32'h0;
                trig_mask_r [j] <= 32'hFFFF_FFFF;   // 掩码全 1 = 精确匹配（arm-without-apply 安全，不意外触发）
            end
        end else begin
            arm_pulse    <= 1'b0;
            disarm_pulse <= 1'b0;
            force_pulse  <= 1'b0;

            if (reg_we) begin
`ifdef ILA_DBG
                // 契约守卫（仅仿真）：armed 期间不允许改采集配置——
                // 派生值（pretrig_len 等）已打拍，armed 期间热改配置行为未定义
                if (armed && ((reg_addr == `REG_CAPTURE_LEN) ||
                              (reg_addr == `REG_TRIG_POS)    ||
                              (reg_addr == `REG_WINDOWS_NUM)))
                    $display("[ctrl] WARNING: config write addr=%04x while armed (contract violation)", reg_addr);
`endif
                case (reg_addr)
                    `REG_CTRL: begin
                        if (reg_wdata[`CTRL_ARM_BIT])    arm_pulse    <= 1'b1;
                        if (reg_wdata[`CTRL_DISARM_BIT]) disarm_pulse <= 1'b1;
                        if (reg_wdata[`CTRL_FORCE_BIT])  force_pulse  <= 1'b1;
                        // CTRL_XTRIG_BIT 已忽略（跨核触发接口移除）
                    end
                    `REG_WINDOWS_NUM: windows_num_r <= reg_wdata[15:0];
                    `REG_TRIG_POS:    trig_pos_r    <= reg_wdata[ADDR_W:0];
                    `REG_CAPTURE_LEN: capture_len_r <= reg_wdata[ADDR_W:0];
                    `REG_BUF_ADDR:    buf_addr_r    <= reg_wdata[ADDR_W-1:0];
                    default: begin
                        if ((addr32 >= TV_LO) && (addr32 < TV_HI))
                            trig_value_r[vidx] <= reg_wdata;
                        else if ((addr32 >= TM_LO) && (addr32 < TM_HI))
                            trig_mask_r[midx] <= reg_wdata;
                    end
                endcase
            end
        end
    end

    // ------------------------------------------------------------
    // 读寄存器（组合）
    // ------------------------------------------------------------
    always @(*) begin
        reg_rdata = 32'h0;
        case (reg_addr)
            `REG_IDCODE:      reg_rdata = `ILA_IDCODE;
            `REG_VERSION:     reg_rdata = `ILA_VERSION;
            `REG_SIGN_L:      reg_rdata = SIGN_L;
            `REG_SIGN_H:      reg_rdata = SIGN_H;
            `REG_NUM_PROBES:  reg_rdata = NUM_PROBES[31:0];
            `REG_TOTAL_WIDTH: reg_rdata = DATA_W[31:0];
            `REG_DATA_DEPTH:  reg_rdata = DEPTH[31:0];
            `REG_MAX_WINDOWS: reg_rdata = MAX_WINDOWS[31:0];
            `REG_SAMPLE_HZ:   reg_rdata = SAMPLE_HZ;
            `REG_STATUS:      reg_rdata = {cur_window, 12'b0, full, triggered, armed, idle};
            `REG_FILL_LEVEL:  reg_rdata = {{(31-ADDR_W){1'b0}}, fill_level};
            `REG_WINDOWS_NUM: reg_rdata = {16'b0, windows_num_r};
            `REG_TRIG_POS:    reg_rdata = {{(31-ADDR_W){1'b0}}, trig_pos_r};
            `REG_CAPTURE_LEN: reg_rdata = {{(31-ADDR_W){1'b0}}, capture_len_r};
            `REG_TRIG_FILLED: reg_rdata = {{(31-ADDR_W){1'b0}}, trig_filled};
            `REG_TRIG_SRC:   reg_rdata = {31'b0, trig_was_force};
            `REG_TRIG_REQ_VAL: reg_rdata = {31'b0, trig_req_val};
            `REG_TRIG_WR_DATA: reg_rdata = trig_wr_data;
            `REG_TRIG_WR_DATA_D1: reg_rdata = trig_wr_data_d1;
            `REG_TRIG_WR_WE:   reg_rdata = {31'b0, trig_wr_we};
            `REG_TRIG_WR_ADDR: reg_rdata = {{(32-ADDR_W){1'b0}}, trig_wr_addr};
            `REG_TRACE_CTL:   reg_rdata = {28'b0, trace_done, trace_ptr};
            `REG_TRACE_DATA, `REG_TRACE_DATA+1, `REG_TRACE_DATA+2, `REG_TRACE_DATA+3,
            `REG_TRACE_DATA+4, `REG_TRACE_DATA+5, `REG_TRACE_DATA+6, `REG_TRACE_DATA+7: begin
                reg_rdata = {20'b0, trace_addr[reg_addr[2:0]*10 +: 10],
                                    trace_req[reg_addr[2:0]], trace_we[reg_addr[2:0]]};
            end
            `REG_PROBE_WIDTH, `REG_PROBE_WIDTH+1, `REG_PROBE_WIDTH+2,
            `REG_PROBE_WIDTH+3,`REG_PROBE_WIDTH+4,`REG_PROBE_WIDTH+5,
            `REG_PROBE_WIDTH+6,`REG_PROBE_WIDTH+7,`REG_PROBE_WIDTH+8,
            `REG_PROBE_WIDTH+9,`REG_PROBE_WIDTH+10,`REG_PROBE_WIDTH+11,
            `REG_PROBE_WIDTH+12,`REG_PROBE_WIDTH+13,`REG_PROBE_WIDTH+14,
            `REG_PROBE_WIDTH+15,`REG_PROBE_WIDTH+16,`REG_PROBE_WIDTH+17,
            `REG_PROBE_WIDTH+18,`REG_PROBE_WIDTH+19,`REG_PROBE_WIDTH+20,
            `REG_PROBE_WIDTH+21,`REG_PROBE_WIDTH+22,`REG_PROBE_WIDTH+23,
            `REG_PROBE_WIDTH+24,`REG_PROBE_WIDTH+25,`REG_PROBE_WIDTH+26,
            `REG_PROBE_WIDTH+27,`REG_PROBE_WIDTH+28,`REG_PROBE_WIDTH+29,
            `REG_PROBE_WIDTH+30,`REG_PROBE_WIDTH+31:
                case (reg_addr)
                    `REG_PROBE_WIDTH+0:  reg_rdata = PW0[31:0];
                    `REG_PROBE_WIDTH+1:  reg_rdata = PW1[31:0];
                    `REG_PROBE_WIDTH+2:  reg_rdata = PW2[31:0];
                    `REG_PROBE_WIDTH+3:  reg_rdata = PW3[31:0];
                    `REG_PROBE_WIDTH+4:  reg_rdata = PW4[31:0];
                    `REG_PROBE_WIDTH+5:  reg_rdata = PW5[31:0];
                    `REG_PROBE_WIDTH+6:  reg_rdata = PW6[31:0];
                    `REG_PROBE_WIDTH+7:  reg_rdata = PW7[31:0];
                    `REG_PROBE_WIDTH+8:  reg_rdata = PW8[31:0];
                    `REG_PROBE_WIDTH+9:  reg_rdata = PW9[31:0];
                    `REG_PROBE_WIDTH+10: reg_rdata = PW10[31:0];
                    `REG_PROBE_WIDTH+11: reg_rdata = PW11[31:0];
                    `REG_PROBE_WIDTH+12: reg_rdata = PW12[31:0];
                    `REG_PROBE_WIDTH+13: reg_rdata = PW13[31:0];
                    `REG_PROBE_WIDTH+14: reg_rdata = PW14[31:0];
                    `REG_PROBE_WIDTH+15: reg_rdata = PW15[31:0];
                    `REG_PROBE_WIDTH+16: reg_rdata = PW16[31:0];
                    `REG_PROBE_WIDTH+17: reg_rdata = PW17[31:0];
                    `REG_PROBE_WIDTH+18: reg_rdata = PW18[31:0];
                    `REG_PROBE_WIDTH+19: reg_rdata = PW19[31:0];
                    `REG_PROBE_WIDTH+20: reg_rdata = PW20[31:0];
                    `REG_PROBE_WIDTH+21: reg_rdata = PW21[31:0];
                    `REG_PROBE_WIDTH+22: reg_rdata = PW22[31:0];
                    `REG_PROBE_WIDTH+23: reg_rdata = PW23[31:0];
                    `REG_PROBE_WIDTH+24: reg_rdata = PW24[31:0];
                    `REG_PROBE_WIDTH+25: reg_rdata = PW25[31:0];
                    `REG_PROBE_WIDTH+26: reg_rdata = PW26[31:0];
                    `REG_PROBE_WIDTH+27: reg_rdata = PW27[31:0];
                    `REG_PROBE_WIDTH+28: reg_rdata = PW28[31:0];
                    `REG_PROBE_WIDTH+29: reg_rdata = PW29[31:0];
                    `REG_PROBE_WIDTH+30: reg_rdata = PW30[31:0];
                    default:              reg_rdata = PW31[31:0];
                endcase
            default: begin
                if ((addr32 >= TV_LO) && (addr32 < TV_HI))
                    reg_rdata = trig_value_r[vidx];
                else if ((addr32 >= TM_LO) && (addr32 < TM_HI))
                    reg_rdata = trig_mask_r[midx];
                else if ((addr32 >= WS_LO) && (addr32 < WS_HI))
                    reg_rdata = {{(32-ADDR_W){1'b0}},
                                 win_start_flat[widx*ADDR_W +: ADDR_W]};
                else if ((addr32 >= BD_LO) && (addr32 < BD_HI))
                    reg_rdata = buf_word_pad[bidx*32 +: 32];
                else
                    reg_rdata = 32'h0;
            end
        endcase
    end

endmodule
