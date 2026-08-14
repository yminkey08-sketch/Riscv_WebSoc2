// ila_wrapper.v — Soft ILA for TX path + bus debug
// Focused on: why CPU isn't sending ARP reply
`include "ila_rtl/ila_pkg.vh"

module ila_wrapper (
    input  wire         clk, reset_l,
    // GMII
    input  wire         gmii_rx_dv,
    input  wire [7:0]   gmii_rxd,
    input  wire         gmii_tx_en,
    input  wire [7:0]   gmii_txd,
    // CPU status
    input  wire         cpu_rd_empty,
    input  wire [3:0]   led_o,
    // gmii2mac FIFO
    input  wire         rx_afifo_empty,
    input  wire         rx_presemble_valid,
    // MAC TX
    input  wire         mac_tx_sop,
    input  wire         mac_tx_en,
    input  wire [7:0]   mac_tx_data,
    input  wire         mac_tx_eop,
    // CPU bus
    input  wire         bus_req,
    input  wire [11:0]  bus_addr_lo,    // lower 12 bits of bus address
    input  wire         bus_rhwl,       // 1=read 0=write

    input  wire         reg_we,
    input  wire [15:0]  reg_addr,
    input  wire [31:0]  reg_wdata,
    output wire [31:0]  reg_rdata
);

    // Layout (LSB first):
    // 0:  gmii_rxd[7:0]      (8)
    // 1:  gmii_rx_dv          (1)
    // 2:  gmii_txd[7:0]      (8)
    // 3:  gmii_tx_en          (1)
    // 4:  cpu_rd_empty        (1)
    // 5:  led_o[3:0]         (4)
    // 6:  rx_afifo_empty      (1)
    // 7:  rx_presemble_valid  (1)
    // 8:  mac_tx_sop          (1)
    // 9:  mac_tx_en           (1)
    // 10: mac_tx_data[7:0]   (8)
    // 11: mac_tx_eop          (1)
    // 12: bus_req             (1)
    // 13: bus_addr_lo[11:0]  (12)
    // 14: bus_rhwl            (1)
    // Total: 50 bits → NWORDS=2

    soft_ila_top #(
        .CORE_EN(1), .DATA_DEPTH(2048), .MAX_WINDOWS(1),
        .SAMPLE_HZ(32'd50000000), .RST_ACTIVE_LOW(1),
        .NUM_PROBES(15),
        .PROBE0_WIDTH(8),  .PROBE1_WIDTH(1),
        .PROBE2_WIDTH(8),  .PROBE3_WIDTH(1),
        .PROBE4_WIDTH(1),  .PROBE5_WIDTH(4),
        .PROBE6_WIDTH(1),  .PROBE7_WIDTH(1),
        .PROBE8_WIDTH(1),  .PROBE9_WIDTH(1),
        .PROBE10_WIDTH(8), .PROBE11_WIDTH(1),
        .PROBE12_WIDTH(1), .PROBE13_WIDTH(12),
        .PROBE14_WIDTH(1)
    ) u_ila (
        .sample_clk(clk), .rst_in(reset_l),
        .probe0(gmii_rxd), .probe1(gmii_rx_dv),
        .probe2(gmii_txd), .probe3(gmii_tx_en),
        .probe4(cpu_rd_empty), .probe5(led_o),
        .probe6(rx_afifo_empty), .probe7(rx_presemble_valid),
        .probe8(mac_tx_sop), .probe9(mac_tx_en),
        .probe10(mac_tx_data), .probe11(mac_tx_eop),
        .probe12(bus_req), .probe13(bus_addr_lo),
        .probe14(bus_rhwl),
        .probe15(1'b0),.probe16(1'b0),.probe17(1'b0),.probe18(1'b0),
        .probe19(1'b0),.probe20(1'b0),.probe21(1'b0),.probe22(1'b0),
        .probe23(1'b0),.probe24(1'b0),.probe25(1'b0),.probe26(1'b0),
        .probe27(1'b0),.probe28(1'b0),.probe29(1'b0),.probe30(1'b0),
        .probe31(1'b0),
        .reg_we(reg_we), .reg_re(1'b1),
        .reg_addr(reg_addr), .reg_wdata(reg_wdata), .reg_rdata(reg_rdata)
    );
endmodule
