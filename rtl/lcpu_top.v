`include "define.sv"

module lcpu_top #(
    parameter lcpu_vendor = "xilinx",  //"intel";	"xilinx"; "uart"
    parameter device_vendor = "xilinx",  //"intel";	"xilinx";
    parameter uart_baud_rate = 115200
) (
    input clk,
    input reset_l,

    input  uart_rx,
    output uart_tx,

    output        jtag_req,
    output        jtag_rhwl,
    output [31:0] jtag_wdata,
    output [31:0] jtag_address,
    input  [31:0] jtag_rdata,
    input         jtag_ack
);

  localparam para_ram_type = `SMALL_RAM;
  localparam data_ram_type = `LARGER_RAM;

  generate
    if (lcpu_vendor == "intel") begin : gen_intel
      jtag_lcpu_intel u_cpu (
          .clk(clk),
          .reset_l(reset_l),
          .wrl_rdh(jtag_rhwl),
          .op_req(jtag_req),
          .op_ack(jtag_ack),
          .address(jtag_address),
          .wrdata(jtag_wdata),
          .rddata(jtag_rdata)
      );
    end else if (lcpu_vendor == "xilinx") begin : gen_xilinx
      jtag_cpu_xilinx #(
          .data_width(32),
          .addr_width(32)
      ) u_jtag_cpu_xilinx (
          .rst_n(reset_l),
          .clk  (clk),

          .lcpu_rh_wl  (jtag_rhwl),
          .lcpu_req   (jtag_req),
          .lcpu_ack   (jtag_ack),
          .lcpu_address (jtag_address),
          .lcpu_wdata  (jtag_wdata),
          .lcpu_rdata  (jtag_rdata)
      );
    end else if (lcpu_vendor == "uart") begin : gen_uart
      uart_lcpu_top #(
          .uart_baud_rate(uart_baud_rate),
          .para_ram_type (para_ram_type),
          .data_ram_type (data_ram_type)
      ) u_uart_lcpu_top (
          .reset_l(reset_l),
          .clk(clk),

          .uart_rx(uart_rx),
          .uart_tx(uart_tx),

          .op_req (jtag_req),
          .wrl_rdh(jtag_rhwl),
          .wrdata (jtag_wdata),
          .address(jtag_address),
          .op_ack (jtag_ack),
          .rddata (jtag_rdata)
      );
    end
  endgenerate
endmodule
