`timescale 1ns / 1ps
// ==========================================================================
// soft_ila_top — 面向用户的单核顶层（独立 probe 端口，风格同旧 ila_wrapper）
//
// 用法：只改参数即可适配不同场景。例：
//   soft_ila_top #(
//       .DATA_DEPTH(2048), .MAX_WINDOWS(4), .SAMPLE_HZ(125_000_000),
//       .NUM_PROBES(6),
//       .PROBE0_WIDTH(1), .PROBE1_WIDTH(48), .PROBE2_WIDTH(1),
//       .PROBE3_WIDTH(1), .PROBE4_WIDTH(1), .PROBE5_WIDTH(2)
//   ) u_ila (
//       .sample_clk(clk_125mhz), .rst_in(reset_l),
//       .probe0(wl_lookup_req), .probe1(wl_lookup_mac), .probe2(wl_lookup_match),
//       .probe3(wl_lookup_done),.probe4(wl_lookup_busy),.probe5(wl_ctrl),
//       ... 寄存器/回读总线接 Hub ...
//   );
//
// probe0 位于采样总线低位，probe1 接其上，依次拼接。DATA_WIDTH 自动求和。
// 纯 Verilog-2001（仅 $clog2 为 2005 常量函数，主流工具均支持；不支持时可显式覆盖 ADDR_W）。
// ==========================================================================
module soft_ila_top #(
    parameter CORE_EN        = 1,     // 1=正常工作  0=完全优化(不消耗资源)
    parameter DATA_DEPTH     = 1024,
    parameter MAX_WINDOWS    = 4,
    parameter SAMPLE_HZ      = 32'd125000000,
    parameter RST_ACTIVE_LOW = 1,
    parameter NUM_PROBES     = 32,

    parameter PROBE0_WIDTH=1,  PROBE1_WIDTH=1,  PROBE2_WIDTH=1,  PROBE3_WIDTH=1,
    parameter PROBE4_WIDTH=1,  PROBE5_WIDTH=1,  PROBE6_WIDTH=1,  PROBE7_WIDTH=1,
    parameter PROBE8_WIDTH=1,  PROBE9_WIDTH=1,  PROBE10_WIDTH=1, PROBE11_WIDTH=1,
    parameter PROBE12_WIDTH=1, PROBE13_WIDTH=1, PROBE14_WIDTH=1, PROBE15_WIDTH=1,
    parameter PROBE16_WIDTH=1, PROBE17_WIDTH=1, PROBE18_WIDTH=1, PROBE19_WIDTH=1,
    parameter PROBE20_WIDTH=1, PROBE21_WIDTH=1, PROBE22_WIDTH=1, PROBE23_WIDTH=1,
    parameter PROBE24_WIDTH=1, PROBE25_WIDTH=1, PROBE26_WIDTH=1, PROBE27_WIDTH=1,
    parameter PROBE28_WIDTH=1, PROBE29_WIDTH=1, PROBE30_WIDTH=1, PROBE31_WIDTH=1,

    // ---- 以下为派生参数，正常勿手工覆盖 ----
    parameter DATA_WIDTH =
        (NUM_PROBES> 0?PROBE0_WIDTH :0)+(NUM_PROBES> 1?PROBE1_WIDTH :0)+
        (NUM_PROBES> 2?PROBE2_WIDTH :0)+(NUM_PROBES> 3?PROBE3_WIDTH :0)+
        (NUM_PROBES> 4?PROBE4_WIDTH :0)+(NUM_PROBES> 5?PROBE5_WIDTH :0)+
        (NUM_PROBES> 6?PROBE6_WIDTH :0)+(NUM_PROBES> 7?PROBE7_WIDTH :0)+
        (NUM_PROBES> 8?PROBE8_WIDTH :0)+(NUM_PROBES> 9?PROBE9_WIDTH :0)+
        (NUM_PROBES>10?PROBE10_WIDTH:0)+(NUM_PROBES>11?PROBE11_WIDTH:0)+
        (NUM_PROBES>12?PROBE12_WIDTH:0)+(NUM_PROBES>13?PROBE13_WIDTH:0)+
        (NUM_PROBES>14?PROBE14_WIDTH:0)+(NUM_PROBES>15?PROBE15_WIDTH:0)+
        (NUM_PROBES>16?PROBE16_WIDTH:0)+(NUM_PROBES>17?PROBE17_WIDTH:0)+
        (NUM_PROBES>18?PROBE18_WIDTH:0)+(NUM_PROBES>19?PROBE19_WIDTH:0)+
        (NUM_PROBES>20?PROBE20_WIDTH:0)+(NUM_PROBES>21?PROBE21_WIDTH:0)+
        (NUM_PROBES>22?PROBE22_WIDTH:0)+(NUM_PROBES>23?PROBE23_WIDTH:0)+
        (NUM_PROBES>24?PROBE24_WIDTH:0)+(NUM_PROBES>25?PROBE25_WIDTH:0)+
        (NUM_PROBES>26?PROBE26_WIDTH:0)+(NUM_PROBES>27?PROBE27_WIDTH:0)+
        (NUM_PROBES>28?PROBE28_WIDTH:0)+(NUM_PROBES>29?PROBE29_WIDTH:0)+
        (NUM_PROBES>30?PROBE30_WIDTH:0)+(NUM_PROBES>31?PROBE31_WIDTH:0),
    parameter ADDR_W = $clog2(DATA_DEPTH),
    parameter NWORDS = (DATA_WIDTH + 31) / 32
) (
    // 采样 + 控制域
    input  wire                  sample_clk,
    input  wire                  rst_in,        // 极性由 RST_ACTIVE_LOW 决定

    input  wire [PROBE0_WIDTH -1:0] probe0,
    input  wire [PROBE1_WIDTH -1:0] probe1,
    input  wire [PROBE2_WIDTH -1:0] probe2,
    input  wire [PROBE3_WIDTH -1:0] probe3,
    input  wire [PROBE4_WIDTH -1:0] probe4,
    input  wire [PROBE5_WIDTH -1:0] probe5,
    input  wire [PROBE6_WIDTH -1:0] probe6,
    input  wire [PROBE7_WIDTH -1:0] probe7,
    input  wire [PROBE8_WIDTH -1:0] probe8,
    input  wire [PROBE9_WIDTH -1:0] probe9,
    input  wire [PROBE10_WIDTH-1:0] probe10,
    input  wire [PROBE11_WIDTH-1:0] probe11,
    input  wire [PROBE12_WIDTH-1:0] probe12,
    input  wire [PROBE13_WIDTH-1:0] probe13,
    input  wire [PROBE14_WIDTH-1:0] probe14,
    input  wire [PROBE15_WIDTH-1:0] probe15,
    input  wire [PROBE16_WIDTH-1:0] probe16,
    input  wire [PROBE17_WIDTH-1:0] probe17,
    input  wire [PROBE18_WIDTH-1:0] probe18,
    input  wire [PROBE19_WIDTH-1:0] probe19,
    input  wire [PROBE20_WIDTH-1:0] probe20,
    input  wire [PROBE21_WIDTH-1:0] probe21,
    input  wire [PROBE22_WIDTH-1:0] probe22,
    input  wire [PROBE23_WIDTH-1:0] probe23,
    input  wire [PROBE24_WIDTH-1:0] probe24,
    input  wire [PROBE25_WIDTH-1:0] probe25,
    input  wire [PROBE26_WIDTH-1:0] probe26,
    input  wire [PROBE27_WIDTH-1:0] probe27,
    input  wire [PROBE28_WIDTH-1:0] probe28,
    input  wire [PROBE29_WIDTH-1:0] probe29,
    input  wire [PROBE30_WIDTH-1:0] probe30,
    input  wire [PROBE31_WIDTH-1:0] probe31,

    // 寄存器总线（sample_clk 域，接 Hub）
    input  wire                  reg_we,
    input  wire                  reg_re,
    input  wire [15:0]           reg_addr,
    input  wire [31:0]           reg_wdata,
    output wire [31:0]           reg_rdata
);

    // ------------------------------------------------------------
    // 结构签名（host 端可由 signals.json 复算比对）
    //   SIGN_L = {NUM_PROBES[7:0], MAX_WINDOWS[7:0], DATA_WIDTH[15:0]}
    //   SIGN_H = DATA_DEPTH
    // ------------------------------------------------------------
    localparam [31:0] SIGN_L = {NUM_PROBES[7:0], MAX_WINDOWS[7:0], DATA_WIDTH[15:0]};
    localparam [31:0] SIGN_H = DATA_DEPTH[31:0];

    // ------------------------------------------------------------
    // 复位：极性归一化 + 异步置位 / 同步释放（每域一套）
    // ------------------------------------------------------------
    wire rst_raw = RST_ACTIVE_LOW ? ~rst_in : rst_in;

    reg [1:0] rst_s_clk;
    always @(posedge sample_clk or posedge rst_raw)
        if (rst_raw) rst_s_clk <= 2'b11;
        else         rst_s_clk <= {rst_s_clk[0], 1'b0};
    wire rst_clk = rst_s_clk[1];

    // ------------------------------------------------------------
    // 探针拼接：probe0 在最低位，依次向高位堆叠（仅拼接前 NUM_PROBES 个）
    // 段偏移 O(i) = 前 i 个有效探针位宽之和
    // ------------------------------------------------------------
    localparam O0  = 0;
    localparam O1  = O0  + (NUM_PROBES> 0?PROBE0_WIDTH :0);
    localparam O2  = O1  + (NUM_PROBES> 1?PROBE1_WIDTH :0);
    localparam O3  = O2  + (NUM_PROBES> 2?PROBE2_WIDTH :0);
    localparam O4  = O3  + (NUM_PROBES> 3?PROBE3_WIDTH :0);
    localparam O5  = O4  + (NUM_PROBES> 4?PROBE4_WIDTH :0);
    localparam O6  = O5  + (NUM_PROBES> 5?PROBE5_WIDTH :0);
    localparam O7  = O6  + (NUM_PROBES> 6?PROBE6_WIDTH :0);
    localparam O8  = O7  + (NUM_PROBES> 7?PROBE7_WIDTH :0);
    localparam O9  = O8  + (NUM_PROBES> 8?PROBE8_WIDTH :0);
    localparam O10 = O9  + (NUM_PROBES> 9?PROBE9_WIDTH :0);
    localparam O11 = O10 + (NUM_PROBES>10?PROBE10_WIDTH:0);
    localparam O12 = O11 + (NUM_PROBES>11?PROBE11_WIDTH:0);
    localparam O13 = O12 + (NUM_PROBES>12?PROBE12_WIDTH:0);
    localparam O14 = O13 + (NUM_PROBES>13?PROBE13_WIDTH:0);
    localparam O15 = O14 + (NUM_PROBES>14?PROBE14_WIDTH:0);
    localparam O16 = O15 + (NUM_PROBES>15?PROBE15_WIDTH:0);
    localparam O17 = O16 + (NUM_PROBES>16?PROBE16_WIDTH:0);
    localparam O18 = O17 + (NUM_PROBES>17?PROBE17_WIDTH:0);
    localparam O19 = O18 + (NUM_PROBES>18?PROBE18_WIDTH:0);
    localparam O20 = O19 + (NUM_PROBES>19?PROBE19_WIDTH:0);
    localparam O21 = O20 + (NUM_PROBES>20?PROBE20_WIDTH:0);
    localparam O22 = O21 + (NUM_PROBES>21?PROBE21_WIDTH:0);
    localparam O23 = O22 + (NUM_PROBES>22?PROBE22_WIDTH:0);
    localparam O24 = O23 + (NUM_PROBES>23?PROBE23_WIDTH:0);
    localparam O25 = O24 + (NUM_PROBES>24?PROBE24_WIDTH:0);
    localparam O26 = O25 + (NUM_PROBES>25?PROBE25_WIDTH:0);
    localparam O27 = O26 + (NUM_PROBES>26?PROBE26_WIDTH:0);
    localparam O28 = O27 + (NUM_PROBES>27?PROBE27_WIDTH:0);
    localparam O29 = O28 + (NUM_PROBES>28?PROBE28_WIDTH:0);
    localparam O30 = O29 + (NUM_PROBES>29?PROBE29_WIDTH:0);
    localparam O31 = O30 + (NUM_PROBES>30?PROBE30_WIDTH:0);

    wire [DATA_WIDTH-1:0] sample_bus;

    generate
        if (NUM_PROBES> 0) assign sample_bus[O0  +: PROBE0_WIDTH ] = probe0;
        if (NUM_PROBES> 1) assign sample_bus[O1  +: PROBE1_WIDTH ] = probe1;
        if (NUM_PROBES> 2) assign sample_bus[O2  +: PROBE2_WIDTH ] = probe2;
        if (NUM_PROBES> 3) assign sample_bus[O3  +: PROBE3_WIDTH ] = probe3;
        if (NUM_PROBES> 4) assign sample_bus[O4  +: PROBE4_WIDTH ] = probe4;
        if (NUM_PROBES> 5) assign sample_bus[O5  +: PROBE5_WIDTH ] = probe5;
        if (NUM_PROBES> 6) assign sample_bus[O6  +: PROBE6_WIDTH ] = probe6;
        if (NUM_PROBES> 7) assign sample_bus[O7  +: PROBE7_WIDTH ] = probe7;
        if (NUM_PROBES> 8) assign sample_bus[O8  +: PROBE8_WIDTH ] = probe8;
        if (NUM_PROBES> 9) assign sample_bus[O9  +: PROBE9_WIDTH ] = probe9;
        if (NUM_PROBES>10) assign sample_bus[O10 +: PROBE10_WIDTH] = probe10;
        if (NUM_PROBES>11) assign sample_bus[O11 +: PROBE11_WIDTH] = probe11;
        if (NUM_PROBES>12) assign sample_bus[O12 +: PROBE12_WIDTH] = probe12;
        if (NUM_PROBES>13) assign sample_bus[O13 +: PROBE13_WIDTH] = probe13;
        if (NUM_PROBES>14) assign sample_bus[O14 +: PROBE14_WIDTH] = probe14;
        if (NUM_PROBES>15) assign sample_bus[O15 +: PROBE15_WIDTH] = probe15;
        if (NUM_PROBES>16) assign sample_bus[O16 +: PROBE16_WIDTH] = probe16;
        if (NUM_PROBES>17) assign sample_bus[O17 +: PROBE17_WIDTH] = probe17;
        if (NUM_PROBES>18) assign sample_bus[O18 +: PROBE18_WIDTH] = probe18;
        if (NUM_PROBES>19) assign sample_bus[O19 +: PROBE19_WIDTH] = probe19;
        if (NUM_PROBES>20) assign sample_bus[O20 +: PROBE20_WIDTH] = probe20;
        if (NUM_PROBES>21) assign sample_bus[O21 +: PROBE21_WIDTH] = probe21;
        if (NUM_PROBES>22) assign sample_bus[O22 +: PROBE22_WIDTH] = probe22;
        if (NUM_PROBES>23) assign sample_bus[O23 +: PROBE23_WIDTH] = probe23;
        if (NUM_PROBES>24) assign sample_bus[O24 +: PROBE24_WIDTH] = probe24;
        if (NUM_PROBES>25) assign sample_bus[O25 +: PROBE25_WIDTH] = probe25;
        if (NUM_PROBES>26) assign sample_bus[O26 +: PROBE26_WIDTH] = probe26;
        if (NUM_PROBES>27) assign sample_bus[O27 +: PROBE27_WIDTH] = probe27;
        if (NUM_PROBES>28) assign sample_bus[O28 +: PROBE28_WIDTH] = probe28;
        if (NUM_PROBES>29) assign sample_bus[O29 +: PROBE29_WIDTH] = probe29;
        if (NUM_PROBES>30) assign sample_bus[O30 +: PROBE30_WIDTH] = probe30;
        if (NUM_PROBES>31) assign sample_bus[O31 +: PROBE31_WIDTH] = probe31;
    endgenerate

    // ------------------------------------------------------------
    // CORE_EN=1: 正常例化  |  CORE_EN=0: 输出全 0，综合完全优化
    // ------------------------------------------------------------
    generate
        if (CORE_EN) begin : g_core
            soft_ila_core #(
                .DATA_W(DATA_WIDTH), .DEPTH(DATA_DEPTH),
                .ADDR_W(ADDR_W), .MAX_WINDOWS(MAX_WINDOWS), .NWORDS(NWORDS),
                .NUM_PROBES(NUM_PROBES), .SAMPLE_HZ(SAMPLE_HZ),
                .SIGN_L(SIGN_L), .SIGN_H(SIGN_H),
                .PW0(PROBE0_WIDTH),.PW1(PROBE1_WIDTH),.PW2(PROBE2_WIDTH),
                .PW3(PROBE3_WIDTH),.PW4(PROBE4_WIDTH),.PW5(PROBE5_WIDTH),
                .PW6(PROBE6_WIDTH),.PW7(PROBE7_WIDTH),.PW8(PROBE8_WIDTH),
                .PW9(PROBE9_WIDTH),.PW10(PROBE10_WIDTH),.PW11(PROBE11_WIDTH),
                .PW12(PROBE12_WIDTH),.PW13(PROBE13_WIDTH),.PW14(PROBE14_WIDTH),
                .PW15(PROBE15_WIDTH),.PW16(PROBE16_WIDTH),.PW17(PROBE17_WIDTH),
                .PW18(PROBE18_WIDTH),.PW19(PROBE19_WIDTH),.PW20(PROBE20_WIDTH),
                .PW21(PROBE21_WIDTH),.PW22(PROBE22_WIDTH),.PW23(PROBE23_WIDTH),
                .PW24(PROBE24_WIDTH),.PW25(PROBE25_WIDTH),.PW26(PROBE26_WIDTH),
                .PW27(PROBE27_WIDTH),.PW28(PROBE28_WIDTH),.PW29(PROBE29_WIDTH),
                .PW30(PROBE30_WIDTH),.PW31(PROBE31_WIDTH)
            ) u_core (
                .clk(sample_clk), .rst(rst_clk), .sample(sample_bus),
                .reg_we(reg_we), .reg_re(reg_re), .reg_addr(reg_addr),
                .reg_wdata(reg_wdata), .reg_rdata(reg_rdata)
            );
        end else begin : g_disabled
            assign reg_rdata      = 32'h0;
        end
    endgenerate

endmodule
