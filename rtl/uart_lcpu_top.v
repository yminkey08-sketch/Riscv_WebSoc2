module uart_lcpu_top (
    input reset_l,
    input clk,

    input  uart_rx,  // --> usb_uart Tx
    output uart_tx,  // --> usb_uart Rx

    output        op_req,
    output        wrl_rdh,
    output [31:0] wrdata,
    output [31:0] address,
    input         op_ack,
    input  [31:0] rddata
);

  parameter uart_baud_rate = 115200;
  parameter uart_buf_size = 16;
  parameter para_ram_type = "registers";  //"registers"; // Cyclone IV device : "M9K","registers"
  parameter data_ram_type = "M9K";  //"registers"; // Cyclone IV device : "M9K","registers"
  parameter jtag_wait_cnt_bit = 16;

  wire       read_en;
  wire [7:0] read_data;
  wire       empty;
  wire       write_en;
  wire [7:0] write_data;
  wire       full;
  uart #(
      .baud_rate  (uart_baud_rate),
      .data_number(uart_buf_size),
      .data_width (8),
      .ram_type   (data_ram_type)
  ) u_uart (
      .reset_l   (reset_l),
      .clk       (clk),
      .uart_rx   (uart_rx),
      .read_en   (read_en),
      .read_data (read_data),
      .empty     (empty),
      .write_en  (write_en),
      .write_data(write_data),
      .full      (full),
      .uart_tx   (uart_tx)
  );

  uart_lcpu #(
      .addr_width      (5),              // 2^5=32 words/block, fits 17-byte write cmd
      .block_addr_width(2),
      .data_width      (8),
      .para_width      (2),
      .para_ram_type   (para_ram_type),
      .data_ram_type   (data_ram_type)
  ) u_uart_lcpu (
      .reset_l   (reset_l),
      .clk       (clk),
      .read_en   (read_en),
      .read_data (read_data),
      .empty     (empty),
      .write_en  (write_en),
      .write_data(write_data),
      .full      (full),
      .op_req    (op_req),
      .wrl_rdh   (wrl_rdh),     //'0': write, '1': read
      .wrdata    (wrdata),
      .address   (address),
      .op_ack    (op_ack),
      .rddata    (rddata)
  );
endmodule



