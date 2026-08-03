//****************************************Copyright 2013[c]************************//
// ************************Declaration***************************************//
// File name:        uart_rx	                                       //
// Author:           huaming.huang@link-real.com.cn                                    //
// Date:             2014-12-28 00:00 	                                     //
// Version Number:   1.0                                                     //
// Abstract:    support arbitrarily baud rate, and rx/tx any length data
// Modification history:[including time, version, author and abstract]        //
// 2014-12-28 00:00        version 1.0     xxx                                //
// Abstract: Initial                                                          //
//                                                                            //
// *********************************end************************************** //

module uart_rx (
    reset_l,
    clk,
    clk_uart,

    uart_rx,
    read_en,
    read_data,
    empty
);
  parameter addr_width = 4;  //rx/tx fifo depth control, if 4, rx/tx 16 for each
  parameter data_width = 8;
  parameter ram_type = "registers";  // Cyclone IV device : "M9K","registers"

  input reset_l;
  input clk;
  input clk_uart;

  input uart_rx;
  input read_en;
  output [data_width-1:0] read_data;
  output empty;

  reg                   uart_rx_d0;
  reg                   uart_rx_wen;
  reg  [data_width-1:0] uart_rx_wdata;
  reg                   uart_rxing;
  reg  [data_width-1:0] uart_rxing_d;
  reg                   uart_rxing_d0;
  reg  [           6:0] uart_rx_cnt;
  wire                  full;  // dual_clock_fifo write-side full, unused in RX path

  always @(negedge reset_l or posedge clk_uart)
    if (reset_l == 1'b0) begin
      uart_rx_d0 <= 1'b0;
      uart_rxing <= 1'b0;
      uart_rxing_d0 <= 1'b0;
      uart_rx_cnt <= 7'b0;
      uart_rxing_d <= {data_width{1'b0}};
    end else begin
      uart_rx_d0 <= uart_rx;
      if (uart_rx == 1'b0 && uart_rx_d0 == 1'b1) begin
        uart_rxing <= 1'b1;
      end
      if (uart_rx_cnt == 8 * 9) begin
        uart_rxing <= 1'b0;
      end
      uart_rxing_d0 <= uart_rxing;
      if (uart_rxing == 1'b1) begin
        if (uart_rx_cnt == 8 * 9) begin
          uart_rx_cnt <= 7'b0;
        end else begin
          uart_rx_cnt <= uart_rx_cnt + 1;
        end
        if (uart_rx_cnt / 8 > 0) begin
          if (uart_rx_cnt % 8 == 3) begin
            uart_rxing_d[(uart_rx_cnt/8)-1] <= uart_rx;
          end
        end
      end
    end

  always @(negedge reset_l or posedge clk_uart)
    if (reset_l == 1'b0) begin
      uart_rx_wen   <= 1'b0;
      uart_rx_wdata <= {data_width{1'b0}};
    end else begin
      uart_rx_wen <= 1'b0;
      if (uart_rxing == 1'b0 && uart_rxing_d0 == 1'b1) begin
        uart_rx_wen   <= 1'b1;
        uart_rx_wdata <= uart_rxing_d;
      end
    end

  dual_clock_fifo #(
      .addr_width(addr_width),
      .data_width(data_width),
      .ram_type  (ram_type)
  ) u_uart_rx_data (
      .wclk      (clk_uart),
      .reset_l   (reset_l),
      .write_en  (uart_rx_wen),
      .write_data(uart_rx_wdata),
      .full      (full),
      .rclk      (clk),
      .read_en   (read_en),
      .read_data (read_data),
      .empty     (empty)
  );
endmodule
