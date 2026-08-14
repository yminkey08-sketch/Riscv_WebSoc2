`timescale 1ns / 1ps
// ==========================================================================
// ila_capture — 采样 + BRAM 环形缓冲 + 多窗口分段 + 前/后触发位置
//
// 工作在采样时钟域。每次 arm 启动一轮采集：
//   - 缓冲被等分为 windows_num 段，每段 capture_len 个样本；
//   - 每段独立等待一次触发，段内环形写入实现"预触发"数据保留；
//   - 触发点前保留 pretrig_len 个样本，其余为触发后样本，写满该段后切下一段；
//   - 所有窗口采完 → full。
//
// 段内环形：写满 capture_len 后 win_start 指向"最老样本"，供 host 线性化。
// 约束：调用方需保证 capture_len * windows_num <= DEPTH，pretrig_len <= capture_len-1。
// ==========================================================================
module ila_capture #(
    parameter DATA_W      = 32,
    parameter ADDR_W      = 10,
    parameter MAX_WINDOWS = 4
) (
    input  wire                clk,       // 采样时钟
    input  wire                rst,       // 高有效同步复位
    input  wire [DATA_W-1:0]   sample,
    input  wire                trig,      // 来自 ila_trigger（含强制触发）
    input  wire                force_trig,// force_any（=force_pulse，GUI 强制触发），诊断触发源用

    // 控制（采样域，单拍脉冲）
    input  wire                arm,
    input  wire                disarm,
    input  wire [15:0]         windows_num,   // 1..MAX_WINDOWS
    input  wire [ADDR_W:0]     capture_len,   // 每窗样本数
    input  wire [ADDR_W:0]     pretrig_len,   // 触发点前样本数

    // 状态
    output reg                 armed,
    output reg                 triggered,
    output reg                 full,
    output reg  [15:0]         cur_window,
    output reg  [ADDR_W:0]     fill_level,
    output reg                 trig_pulse,    // 触发发生脉冲（供跨核/trig_out）
    output reg  [ADDR_W:0]     trig_filled,   // 触发样本物理 BRAM 地址（供 host 定位光标）
    output reg                 trig_was_force,// 触发源：1=force, 0=level 匹配
    output reg                 trig_req_val,  // 触发时刻 probe[0]（req）的值
    output reg  [31:0]         trig_wr_data,  // 触发时刻 sample[31:0]（写入确认）
    output reg                  trig_wr_we,    // 触发时刻 ram_we 值（应为 1）
    output reg  [ADDR_W-1:0]    trig_wr_addr,  // 触发时刻 ram_waddr 值
    output reg  [31:0]         trig_wr_data_d1,// 周期 N+1 ram_wdata[31:0]（BRAM 实际写入值，诊断用）

    // 写端口 trace（诊断: 触发前后各 4 拍）
    output reg  [7:0]          trace_we,
    output reg  [7:0]          trace_req,
    output reg  [8*10-1:0]     trace_addr,
    output reg  [2:0]          trace_ptr,  // 触发那一拍在 trace 中的位置 (0..7)
    output reg                 trace_done, // trace 已冻结

    // RAM 写口
    output reg                 ram_we,
    output reg  [ADDR_W-1:0]   ram_waddr,
    output wire [DATA_W-1:0]   ram_wdata,

    // 每窗起始物理偏移（段内，扁平输出，供 readout/host 线性化）
    output wire [MAX_WINDOWS*ADDR_W-1:0] win_start_flat
);

    localparam ST_IDLE = 2'd0;
    localparam ST_WAIT = 2'd1;   // 段内环形写 + 等触发
    localparam ST_POST = 2'd2;   // 触发后写满剩余样本
    localparam ST_DONE = 2'd3;

    localparam CW = (MAX_WINDOWS <= 1) ? 1 : $clog2(MAX_WINDOWS);  // 窗口索引位宽

    reg [1:0]        state;
    reg [ADDR_W-1:0] wr_off;      // 段内写偏移
    reg [ADDR_W:0]   filled;      // 段内已写样本数（饱和于 capture_len）
    reg [ADDR_W:0]   post_cnt;    // 触发后剩余样本数
    reg [15:0]       w;           // 当前窗口号
    reg               trig_d1;     // 触发延迟 1 拍（标记 BRAM 实际写入周期）

    reg [ADDR_W-1:0] win_start_r [0:MAX_WINDOWS-1];

    integer i;
    genvar gi;
    generate
        for (gi = 0; gi < MAX_WINDOWS; gi = gi + 1) begin : g_ws
            assign win_start_flat[gi*ADDR_W +: ADDR_W] = win_start_r[gi];
        end
    endgenerate

    // ram_wdata 加一级寄存器，与 ram_we/ram_waddr 对齐（同为 NBA 寄存器）。
    // 修复 WRITE_LOST：原连续赋值 ram_wdata=sample 导致 BRAM 写入比 ram_we/addr 晚一拍的数据。
    // 现在三者均在周期 N 由 NBA 调度，周期 N+1 同时生效，写入同一样本。
    reg [DATA_W-1:0] ram_wdata_r;
    always @(posedge clk) begin
        if (rst) ram_wdata_r <= {DATA_W{1'b0}};
        else     ram_wdata_r <= sample;
    end
    assign ram_wdata = ram_wdata_r;

    // trig_wr_data 诊断用：宽度安全提取 sample[31:0]
    wire [31:0] sample_lo;
    generate
        if (DATA_W >= 32) assign sample_lo = sample[31:0];
        else             assign sample_lo = {{(32-DATA_W){1'b0}}, sample};
    endgenerate

    // ------------------------------------------------------------
    // 准静态配置的本地打拍派生值（时序收敛）。
    // capture_len/pretrig_len/windows_num 仅在 disarm 期间经寄存器总线写入，
    // 且 ARM 脉冲至少晚于最后一次配置写 2 拍 → 1 拍滞后功能不可见。
    // 每拍无条件重寄存：恒等于原组合值延迟 1 拍，X-free，无需复位分支。
    // ------------------------------------------------------------
    reg  [ADDR_W-1:0] len_m1_q;     // capture_len-1（段内环回比较点）
    reg  [ADDR_W:0]   post_init_q;  // capture_len-1-pretrig_len（触发后样本数初值）
    reg               post_zero_q;  // 上式 == 0（无触发后样本）
    reg  [15:0]       wn_m1_q;      // windows_num-1（末窗判定）
    wire [ADDR_W:0]   post_init_c = capture_len - 1'b1 - pretrig_len;
    always @(posedge clk) begin
        len_m1_q    <= capture_len[ADDR_W-1:0] - 1'b1;
        post_init_q <= post_init_c;
        post_zero_q <= (post_init_c == {(ADDR_W+1){1'b0}});
        wn_m1_q     <= windows_num[15:0] - 16'd1;
    end

    // 段基址累加器：恒等于 w * capture_len (mod 2^ADDR_W)，消除逐拍乘法器。
    // arm 时清零；窗口推进时 +capture_len（与 w<=w+1 同拍生效，见任务内）。
    reg [ADDR_W-1:0] base_q;

    // 下一写偏移（段内环回）
    wire [ADDR_W-1:0] next_off = (wr_off == len_m1_q) ? {ADDR_W{1'b0}}
                                                      : (wr_off + 1'b1);

    // 本拍写入后、"最老样本"的物理偏移（= 下一写位置）
    wire [ADDR_W-1:0] oldest_off = next_off;

    task next_window_or_done;
        begin
            win_start_r[w[CW-1:0]] <= oldest_off;
`ifdef ILA_DBG
            $display("[cap] window %0d done: last_waddr=%0d win_start=%0d", w, base_q+wr_off, oldest_off);
`endif
            if (w == wn_m1_q) begin
                full  <= 1'b1;
                armed <= 1'b0;
                state <= ST_DONE;
            end else begin
                w          <= w + 16'd1;
                cur_window <= w + 16'd1;
                base_q     <= base_q + capture_len[ADDR_W-1:0];  // 与 w+1 同拍推进
                wr_off     <= {ADDR_W{1'b0}};
                filled     <= {(ADDR_W+1){1'b0}};
                state      <= ST_WAIT;
            end
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            state      <= ST_IDLE;
            armed      <= 1'b0;
            triggered  <= 1'b0;
            full       <= 1'b0;
            cur_window <= 16'd0;
            fill_level <= {(ADDR_W+1){1'b0}};
            trig_pulse  <= 1'b0;
            trig_filled <= {(ADDR_W+1){1'b0}};
            trig_was_force <= 1'b0;
            trig_req_val <= 1'b0;
            trig_wr_data <= 32'h0;
            trig_wr_we   <= 1'b0;
            trig_wr_addr <= {ADDR_W{1'b0}};
            trig_wr_data_d1 <= 32'h0;
            trig_d1     <= 1'b0;
            ram_we      <= 1'b0;
            ram_waddr   <= {ADDR_W{1'b0}};
            wr_off     <= {ADDR_W{1'b0}};
            base_q     <= {ADDR_W{1'b0}};
            filled     <= {(ADDR_W+1){1'b0}};
            post_cnt   <= {(ADDR_W+1){1'b0}};
            w          <= 16'd0;
            trace_ptr  <= 3'd0;
            trace_done <= 1'b0;
            for (i = 0; i < MAX_WINDOWS; i = i + 1) win_start_r[i] <= {ADDR_W{1'b0}};
        end else begin
            trig_pulse <= 1'b0;
            ram_we     <= 1'b0;
            // ---- trace: 每拍录 we/addr/req, 触发时冻结 ----
            if (!trace_done) begin
                trace_we[trace_ptr]   <= ram_we;
                trace_req[trace_ptr]  <= sample[0];
                trace_addr[trace_ptr*10 +: 10] <= ram_waddr;
                if (state == ST_WAIT && trig && (1'b1 /* was: filled >= pretrig_len */)) begin
                    // 触发拍: 冻结 trace, ptr 指向当前拍（刚写入的）
                    trace_done <= 1'b1;
                end else begin
                    trace_ptr <= trace_ptr + 3'd1;
                end
            end

            // ---- trig_d1: 延迟 1 拍的触发标记，标记 BRAM 实际写入周期 ----
            //   周期 N: trig_accept=1 → 周期 N+1: trig_d1=1, 此时 ram_wdata 正在写入 BRAM
            trig_d1 <= (state == ST_WAIT) && trig && (1'b1 /* was: filled >= pretrig_len */);
            if (trig_d1) begin
                trig_wr_data_d1 <= ram_wdata[31:0];
            end

            case (state)
                // ------------------------------------------------------------
                ST_IDLE: begin
                    if (arm) begin
                        w          <= 16'd0;
                        cur_window <= 16'd0;
                        wr_off     <= {ADDR_W{1'b0}};
                        base_q     <= {ADDR_W{1'b0}};
                        filled     <= {(ADDR_W+1){1'b0}};
                        armed      <= 1'b1;
                        full       <= 1'b0;
                        triggered  <= 1'b0;
                        state      <= ST_WAIT;
                    end
                end
                // ------------------------------------------------------------
                ST_WAIT: begin
                    // 每拍写入当前样本（段内环形）
                    ram_we     <= 1'b1;
                    ram_waddr  <= base_q + wr_off;
                    wr_off     <= next_off;
                    if (filled < capture_len) filled <= filled + 1'b1;
                    fill_level <= filled;

                    if (disarm) begin
                        armed <= 1'b0;
                        state <= ST_IDLE;
                    end else if (trig && (1'b1 /* was: filled >= pretrig_len */)) begin
                        // 触发被接受：记录物理写入地址供 host 精确定位
                        // （不能记录 filled——buffer 满后 filled 饱和在 capture_len，无法反映环内位置）
                        triggered   <= 1'b1;
                        trig_pulse  <= 1'b1;
                        trig_filled <= base_q + wr_off;   // 触发样本物理 BRAM 地址
                        trig_was_force <= force_trig;     // 记录触发源（1=force, 0=level）
                        trig_req_val <= sample[0];        // 触发时刻 probe[0]（req）的值
                        trig_wr_data <= sample_lo;        // 触发时刻低 32 位
                        trig_wr_we   <= ram_we;           // 触发时刻写使能（应为 1）
                        trig_wr_addr <= ram_waddr;        // 触发时刻写地址（应为 trig_filled-1）
`ifdef ILA_DBG
                        $display("[cap] TRIG accept: waddr=%0d sample_lo=%02x filled=%0d pretrig=%0d post=%0d",
                                 base_q+wr_off, sample[7:0], filled, pretrig_len, post_init_q);
`endif
                        if (post_zero_q) begin
                            // 无触发后样本，本段立即完成
                            next_window_or_done;
                        end else begin
                            post_cnt <= post_init_q;
                            state    <= ST_POST;
                        end
                    end
                end
                // ------------------------------------------------------------
                ST_POST: begin
                    ram_we     <= 1'b1;
                    ram_waddr  <= base_q + wr_off;
                    wr_off     <= next_off;
                    if (filled < capture_len) filled <= filled + 1'b1;
                    fill_level <= filled;

                    if (post_cnt == {{ADDR_W{1'b0}}, 1'b1}) begin
                        next_window_or_done;
                    end else begin
                        post_cnt <= post_cnt - 1'b1;
                    end
                end
                // ------------------------------------------------------------
                ST_DONE: begin
                    // 保持 full，等待下一次 arm（IDLE 才响应）；disarm 回 IDLE
                    if (arm) begin
                        w          <= 16'd0;
                        cur_window <= 16'd0;
                        wr_off     <= {ADDR_W{1'b0}};
                        base_q     <= {ADDR_W{1'b0}};
                        filled     <= {(ADDR_W+1){1'b0}};
                        armed      <= 1'b1;
                        full       <= 1'b0;
                        triggered  <= 1'b0;
                        state      <= ST_WAIT;
                    end else if (disarm) begin
                        state <= ST_IDLE;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
