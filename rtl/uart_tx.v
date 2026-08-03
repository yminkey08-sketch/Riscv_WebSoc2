//****************************************Copyright 2013[c]************************//
// ************************Declaration***************************************//
// File name:        uart_tx	                                       //
// Author:           huaming.huang@link-real.com.cn                                    //
// Date:             2014-12-29 00:00 	                                     //
// Version Number:   1.0                                                     //
// Abstract:    support arbitrarily baud rate, and rx/tx any length data
// Modification history:[including time, version, author and abstract]        //
// 2014-12-29 00:00        version 1.0     xxx                                //
// Abstract: Initial                                                          //
//                                                                            //
// *********************************end************************************** //

module uart_tx (
    reset_l,
    clk,
    clk_uart,

    write_en,
    write_data,
    full,
    uart_tx
);
  parameter addr_width = 4;  //rx/tx fifo depth control, if 4, rx/tx 16 for each
  parameter data_width = 8;
  parameter ram_type = "registers";  // Cyclone IV device : "M9K","registers"

  input reset_l;
  input clk;
  input clk_uart;

  input write_en;
  input [data_width-1:0] write_data;
  output full;
  output uart_tx;

  reg                   uart_tx;
  reg                   uart_tx_ren;
  wire [data_width-1:0] uart_tx_rdata;
  wire                  uart_tx_empty;
  reg  [           3:0] uart_tx_cnt;
  reg                   uart_tx_ren_d0;
  reg  [data_width-1:0] uart_tx_rdata_r;

  reg                   uart_txing;

  always @(negedge reset_l or posedge clk_uart)
    if (reset_l == 1'b0) begin
      uart_tx_cnt <= 4'b0;
      uart_tx_ren <= 1'b0;
      uart_txing <= 1'b0;
      uart_tx <= 1'b0;
      uart_tx_ren_d0 <= 1'b0;
      uart_tx_rdata_r <= {data_width{1'b0}};
    end else begin
      uart_tx <= 1'b1;
      uart_tx_cnt <= uart_tx_cnt + 1;
      uart_tx_ren <= 1'b0;
      uart_tx_ren_d0 <= uart_tx_ren;
      if (uart_tx_cnt == 4'd0) begin
        if (uart_tx_empty == 1'b0) begin
          uart_tx_ren <= 1'b1;
        end
      end
      if (uart_tx_ren == 1'b1) begin
        uart_txing <= 1'b1;
      end
      if (uart_tx_ren_d0 == 1'b1) begin
        uart_tx_rdata_r <= uart_tx_rdata;
      end
      if (uart_tx_cnt == 4'd11) begin
        uart_txing <= 1'b0;
      end
      if (uart_txing == 1'b1) begin
        case (uart_tx_cnt)
          2: uart_tx <= 1'b0;  //start
          3: uart_tx <= uart_tx_rdata_r[0];
          4: uart_tx <= uart_tx_rdata_r[1];
          5: uart_tx <= uart_tx_rdata_r[2];
          6: uart_tx <= uart_tx_rdata_r[3];
          7: uart_tx <= uart_tx_rdata_r[4];
          8: uart_tx <= uart_tx_rdata_r[5];
          9: uart_tx <= uart_tx_rdata_r[6];
          10: uart_tx <= uart_tx_rdata_r[7];
          default: uart_tx <= 1'b1;
        endcase
      end
    end

  dual_clock_fifo #(
      .addr_width(addr_width),
      .data_width(data_width),
      .ram_type  (ram_type)
  ) u_uart_tx_data (
      .wclk      (clk),
      .reset_l   (reset_l),
      .write_en  (write_en),
      .write_data(write_data),
      .full      (full),
      .rclk      (clk_uart),
      .read_en   (uart_tx_ren),
      .read_data (uart_tx_rdata),
      .empty     (uart_tx_empty)
  );
endmodule
