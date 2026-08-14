`timescale 1ns / 1ps
// ==========================================================================
// soft_ila_core — 单核引擎（总线级）。采样、寄存器、缓冲回读统一在 clk 域。
//   对外只暴露：采样总线 + 触发 IO + 16位地址/32位数据寄存器总线。
//   缓冲回读经寄存器：写 REG_BUF_ADDR → 读 REG_BUF_DATA0..n。
// ==========================================================================
module soft_ila_core #(
    parameter DATA_W      = 32,
    parameter DEPTH       = 1024,
    parameter ADDR_W      = 10,
    parameter MAX_WINDOWS = 4,
    parameter NWORDS      = 1,
    parameter NUM_PROBES  = 1,
    parameter SAMPLE_HZ   = 32'd125000000,
    parameter [31:0] SIGN_L = 32'h0,
    parameter [31:0] SIGN_H = 32'h0,
    // per-probe widths
    parameter PW0=1,PW1=1,PW2=1,PW3=1,PW4=1,PW5=1,PW6=1,PW7=1,
    parameter PW8=1,PW9=1,PW10=1,PW11=1,PW12=1,PW13=1,PW14=1,PW15=1,
    parameter PW16=1,PW17=1,PW18=1,PW19=1,PW20=1,PW21=1,PW22=1,PW23=1,
    parameter PW24=1,PW25=1,PW26=1,PW27=1,PW28=1,PW29=1,PW30=1,PW31=1
) (
    input  wire              clk,
    input  wire              rst,        // 高有效同步复位
    input  wire [DATA_W-1:0] sample,

    // 寄存器总线（clk 域）
    input  wire              reg_we,
    input  wire              reg_re,
    input  wire [15:0]       reg_addr,
    input  wire [31:0]       reg_wdata,
    output wire [31:0]       reg_rdata
);
    // -------- ctrl ↔ 其它 --------
    wire [32*NWORDS-1:0] trig_value, trig_mask;
    wire [1:0]           trig_mode;
    wire                 arm_pulse, disarm_pulse, force_pulse;
    wire [15:0]          windows_num, cur_window;
    wire [ADDR_W:0]      capture_len, pretrig_len, fill_level, trig_filled;
    wire                 armed, triggered, full, trig_pulse, trig, trig_was_force, trig_req_val;
    wire [31:0]          trig_wr_data;
    wire [31:0]          trig_wr_data_d1;
    wire                 trig_wr_we;
    wire [ADDR_W-1:0]    trig_wr_addr;
    wire [7:0] trace_we, trace_req;
    wire [8*10-1:0] trace_addr;
    wire [2:0] trace_ptr;
    wire trace_done;

    wire                 ram_we;
    wire [ADDR_W-1:0]    ram_waddr;
    wire [DATA_W-1:0]    ram_wdata;
    wire [MAX_WINDOWS*ADDR_W-1:0] win_start_flat;

    wire                 ram_rd_en;
    wire [ADDR_W-1:0]    ram_rd_addr;
    wire [DATA_W-1:0]    ram_rd_data;

    // force_any 仅来自 force_pulse（GUI 强制触发）。ext/cross 触发接口已移除。
    wire force_any = force_pulse;

    // 对 probe 拼接总线打一拍，消除毛刺，保证 ila_trigger 和 ila_capture 一致。
    reg [DATA_W-1:0] sample_synced;
    always @(posedge clk) begin
        if (rst) sample_synced <= {DATA_W{1'b0}};
        else     sample_synced <= sample;
    end

    ila_ctrl #(
        .DATA_W(DATA_W), .DEPTH(DEPTH), .ADDR_W(ADDR_W), .MAX_WINDOWS(MAX_WINDOWS),
        .NWORDS(NWORDS), .NUM_PROBES(NUM_PROBES), .SAMPLE_HZ(SAMPLE_HZ),
        .SIGN_L(SIGN_L), .SIGN_H(SIGN_H),
        .PW0(PW0),.PW1(PW1),.PW2(PW2),.PW3(PW3),.PW4(PW4),.PW5(PW5),.PW6(PW6),.PW7(PW7),
        .PW8(PW8),.PW9(PW9),.PW10(PW10),.PW11(PW11),.PW12(PW12),.PW13(PW13),
        .PW14(PW14),.PW15(PW15),.PW16(PW16),.PW17(PW17),.PW18(PW18),.PW19(PW19),
        .PW20(PW20),.PW21(PW21),.PW22(PW22),.PW23(PW23),.PW24(PW24),.PW25(PW25),
        .PW26(PW26),.PW27(PW27),.PW28(PW28),.PW29(PW29),.PW30(PW30),.PW31(PW31)
    ) u_ctrl (
        .clk(clk), .rst(rst),
        .reg_we(reg_we), .reg_re(reg_re), .reg_addr(reg_addr),
        .reg_wdata(reg_wdata), .reg_rdata(reg_rdata),
        .trig_value(trig_value), .trig_mask(trig_mask), .trig_mode(trig_mode),
        .arm_pulse(arm_pulse), .disarm_pulse(disarm_pulse), .force_pulse(force_pulse),
        .windows_num(windows_num), .capture_len(capture_len), .pretrig_len(pretrig_len),
        .armed(armed), .triggered(triggered), .full(full),
        .cur_window(cur_window), .fill_level(fill_level), .trig_filled(trig_filled),
        .trig_was_force(trig_was_force),
        .trig_req_val(trig_req_val),
        .trig_wr_data(trig_wr_data),
        .trig_wr_data_d1(trig_wr_data_d1),
        .trig_wr_we(trig_wr_we),
        .trig_wr_addr(trig_wr_addr),
        .trace_we(trace_we), .trace_req(trace_req), .trace_addr(trace_addr),
        .trace_ptr(trace_ptr), .trace_done(trace_done),
        .win_start_flat(win_start_flat),
        .ram_rd_en(ram_rd_en), .ram_rd_addr(ram_rd_addr), .ram_rd_data(ram_rd_data)
    );

    ila_trigger #(
        .DATA_W(DATA_W), .NWORDS(NWORDS)
    ) u_trig (
        .clk(clk), .rst(rst), .sample(sample_synced),
        .trig_value(trig_value), .trig_mask(trig_mask), .trig_mode(trig_mode),
        .force_trig(force_any), .trig(trig)
    );

    ila_capture #(
        .DATA_W(DATA_W), .ADDR_W(ADDR_W), .MAX_WINDOWS(MAX_WINDOWS)
    ) u_cap (
        .clk(clk), .rst(rst), .sample(sample_synced), .trig(trig),
        .force_trig(force_any),
        .arm(arm_pulse), .disarm(disarm_pulse),
        .windows_num(windows_num), .capture_len(capture_len), .pretrig_len(pretrig_len),
        .armed(armed), .triggered(triggered), .full(full),
        .cur_window(cur_window), .fill_level(fill_level), .trig_pulse(trig_pulse),
        .trig_filled(trig_filled), .trig_was_force(trig_was_force),
        .trig_req_val(trig_req_val),
        .trig_wr_data(trig_wr_data),
        .trig_wr_data_d1(trig_wr_data_d1),
        .trig_wr_we(trig_wr_we),
        .trig_wr_addr(trig_wr_addr),
        .trace_we(trace_we), .trace_req(trace_req), .trace_addr(trace_addr),
        .trace_ptr(trace_ptr), .trace_done(trace_done),
        .ram_we(ram_we), .ram_waddr(ram_waddr), .ram_wdata(ram_wdata),
        .win_start_flat(win_start_flat)
    );

    ila_ram_dp #(
        .DATA_W(DATA_W), .DEPTH(DEPTH), .ADDR_W(ADDR_W)
    ) u_ram (
        .wr_clk(clk), .wr_en(ram_we),    .wr_addr(ram_waddr),   .wr_data(ram_wdata),
        .rd_clk(clk), .rd_en(ram_rd_en), .rd_addr(ram_rd_addr), .rd_data(ram_rd_data)
    );

endmodule
