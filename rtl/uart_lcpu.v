//****************************************Copyright 2013[c]************************//
// ************************Declaration***************************************//
// File name:        uart_lcpu	                                       //
// Author:           huaming.huang@link-real.com.cn                                    //
// Date:             2014-12-29 00:00 	                                     //
// Version Number:   1.0                                                     //
// Abstract:    uart port with lcpu bridge
// Modification history:[including time, version, author and abstract]        //
// 2014-12-29 00:00        version 1.0     xxx                                //
// Abstract: Initial                                                          //
//                                                                            //
// *********************************end************************************** //

module uart_lcpu (
    reset_l,
    clk,
    //client Rx fifo interface, for client read out
    read_en,
    read_data,
    empty,
    //client Tx fifo interface, for client write into
    write_en,
    write_data,
    full,

    op_req,
    wrl_rdh,  //'0': write, '1': read
    wrdata,
    address,
    op_ack,
    rddata
);
  parameter addr_width = 3,  //indicate each data block have 256 data
  block_addr_width = 3,  //indicate there have 16 data block
  data_width = 8,  //each data bits
  para_width = 1,
					para_ram_type = "registers",
					data_ram_type = "M9K"; // Cyclone IV device : "M9K","registers"

  input reset_l;
  input clk;

  output read_en;
  input [7:0] read_data;
  input empty;

  output write_en;
  output [7:0] write_data;
  input full;

  output op_req;
  output wrl_rdh;
  output [31:0] wrdata;
  output [31:0] address;
  input op_ack;
  input [31:0] rddata;

  wire                  wpkt_full;
  wire                  wpkt_wen;
  wire [addr_width-1:0] wpkt_waddr;
  wire [data_width-1:0] wpkt_wdata;
  wire                  wpkt_push;
  wire [  addr_width:0] wpkt_len;
  wire [para_width-1:0] wpkt_para;

  wire                  rpkt_empty;
  wire                  rpkt_ren;
  wire [addr_width-1:0] rpkt_raddr;
  wire [data_width-1:0] rpkt_rdata;
  wire                  rpkt_pop;
  wire [  addr_width:0] rpkt_len;
  wire [para_width-1:0] rpkt_para;

  uart_in_pktfifo #(
      .addr_width(addr_width),
      .data_width(data_width),
      .para_width(para_width)
  ) u_uart_pktfifo (
      .reset_l  (reset_l),
      .clk      (clk),
      .read_en  (read_en),
      .read_data(read_data),
      .empty    (empty),
      .full     (wpkt_full),
      .wen      (wpkt_wen),
      .waddr    (wpkt_waddr),
      .wdata    (wpkt_wdata),
      .wpkt_push(wpkt_push),
      .wpkt_len (wpkt_len),
      .wpkt_para(wpkt_para)
  );

  package_fifo_v2 #(
      .dual_clock(0),
      .addr_width(addr_width),
      .block_addr_width(block_addr_width),
      .data_width(data_width),
      .para_width(para_width),
      .para_ram_type(para_ram_type),
      .data_ram_type(data_ram_type),
      .block_mode("true")
  ) u_pkt_fifo (
      .reset_l  (reset_l),
      .wclk     (clk),
      .wclk_en  (1'b1),
      .full     (wpkt_full),
      .wen      (wpkt_wen),
      .waddr    (wpkt_waddr),
      .wdata    (wpkt_wdata),
      .wpkt_push(wpkt_push),
      .wpkt_len (wpkt_len),
      .wpkt_para(wpkt_para),
      .rclk     (clk),
      .rclk_en  (1'b1),
      .empty    (rpkt_empty),
      .rpkt_pop (rpkt_pop),
      .rpkt_len (rpkt_len),
      .rpkt_para(rpkt_para),
      .ren      (rpkt_ren),
      .raddr    (rpkt_raddr),
      .rdata    (rpkt_rdata)
  );

  pktfifo_out_lcpu #(
      .addr_width(addr_width),
      .data_width(data_width),
      .para_width(para_width)
  ) u_pktfifo_lcpu (
      .reset_l   (reset_l),
      .clk       (clk),
      .empty     (rpkt_empty),
      .rpkt_pop  (rpkt_pop),
      .rpkt_len  (rpkt_len),
      .rpkt_para (rpkt_para),
      .rpkt_ren  (rpkt_ren),
      .rpkt_raddr(rpkt_raddr),
      .rpkt_rdata(rpkt_rdata),
      .op_req    (op_req),
      .wrl_rdh   (wrl_rdh),     //'0': write, '1': read
      .wrdata    (wrdata),
      .address   (address),
      .op_ack    (op_ack),
      .rddata    (rddata)
  );

  lcpu_out_uart u_lcpu2uart (
      .reset_l   (reset_l),
      .clk       (clk),
      .op_req    (op_req),
      .wrl_rdh   (wrl_rdh),
      .op_ack    (op_ack),
      .rddata    (rddata),
      .write_en  (write_en),
      .write_data(write_data),
      .full      (full)
  );
endmodule



module uart_in_pktfifo (
    reset_l,
    clk,
    //client Rx fifo interface, for client read out
    read_en,
    read_data,
    empty,

    full,
    wen,
    waddr,
    wdata,
    wpkt_push,
    wpkt_len,
    wpkt_para
);
  parameter addr_width = 3,  //indicate each data block have 256 data
  data_width = 8,  //each data bits
  para_width = 2;

  parameter start_op = "s";
  parameter write_op = "w";
  parameter read_op = "r";
  parameter [7:0] over_op = 8'h0D;

  parameter [1:0] search_start = 2'b01, move_op_data = 2'b10;
  input reset_l;
  input clk;

  output read_en;
  input [7:0] read_data;
  input empty;

  input full;
  output wen;
  output [addr_width-1:0] waddr;
  output [data_width-1:0] wdata;
  output wpkt_push;
  output [addr_width:0] wpkt_len;
  output [para_width-1:0] wpkt_para;

  reg                  read_en;
  reg                  wen;
  reg [addr_width-1:0] waddr;
  reg [data_width-1:0] wdata;
  reg                  wpkt_push;
  reg [  addr_width:0] wpkt_len;
  reg [para_width-1:0] wpkt_para;

  reg                  start_found;
  reg [           2:0] sta_cnt;
  reg                  move_op_done;
  reg                  read_en_d0;

  reg [           1:0] cur_state;
  reg [           1:0] next_state;

  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      cur_state <= search_start;
    end else begin
      cur_state <= next_state;
    end
  end

  always_comb begin
    case (cur_state)
      search_start: begin
        if (start_found == 1'b1) begin
          next_state <= move_op_data;
        end else begin
          next_state <= search_start;
        end
      end
      move_op_data: begin
        if (move_op_done == 1'b1) begin
          next_state <= search_start;
        end else begin
          next_state <= move_op_data;
        end
      end
      default: next_state <= search_start;
    endcase
  end

  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      start_found <= 1'b0;
      sta_cnt <= 3'b0;
      read_en <= 1'b0;
      wen <= 1'b0;
      waddr <= {addr_width{1'b0}};
      wdata <= {data_width{1'b0}};
      wpkt_push <= 1'b0;
      wpkt_len <= {(addr_width + 1) {1'b0}};
      wpkt_para <= {para_width{1'b1}};
      move_op_done <= 1'b0;
      read_en_d0 <= 1'b0;
    end else begin
      read_en_d0 <= read_en;
      case (cur_state)
        search_start: begin
          move_op_done <= 1'b0;
          waddr <= {addr_width{1'b0}};
          wpkt_push <= 1'b0;
          if (sta_cnt > 2) begin
            sta_cnt <= 3'b0;
          end else begin
            sta_cnt <= sta_cnt + 1;
          end
          read_en <= 1'b0;
          if (sta_cnt == 0) begin
            if (empty == 1'b0) begin
              read_en <= 1'b1;
            end
          end
          start_found <= 1'b0;
          if (sta_cnt == 2 && read_en_d0 == 1'b1) begin
            if (read_data == start_op) begin
              start_found <= 1'b1;
              sta_cnt <= 3'b0;
            end
          end
        end
        move_op_data: begin
          start_found <= 1'b0;
          if (sta_cnt > 2) begin
            sta_cnt <= 3'b0;
          end else begin
            sta_cnt <= sta_cnt + 1;
          end
          read_en <= 1'b0;
          if (sta_cnt == 1) begin
            if (empty == 1'b0) begin
              read_en <= 1'b1;
            end
          end
          move_op_done <= 1'b0;
          wen <= read_en_d0;
          wdata <= read_data;
          if (wen == 1'b1) begin
            waddr <= waddr + 1;
          end
          wpkt_push <= 1'b0;
          if (sta_cnt == 3) begin
            if (read_data == over_op && read_en_d0 == 1'b1) begin
              move_op_done <= 1'b1;
              wen <= 1'b0;
              sta_cnt <= 4'b0;
              wpkt_push <= 1'b1;
              wpkt_len <= waddr + 1;
            end
            if (read_data == write_op) begin
              wpkt_para <= {para_width{1'b0}};
              wen <= 1'b0;
            end
            if (read_data == read_op) begin
              wpkt_para <= {para_width{1'b1}};
              wen <= 1'b0;
            end
          end
        end
        default: begin
          start_found <= 1'b0;
          move_op_done <= 1'b0;
          waddr <= {addr_width{1'b0}};
          wpkt_push <= 1'b0;
        end
      endcase
    end
  end
endmodule





module pktfifo_out_lcpu (
    reset_l,
    clk,

    empty,
    rpkt_pop,
    rpkt_len,
    rpkt_para,
    rpkt_ren,
    rpkt_raddr,
    rpkt_rdata,

    op_req,
    wrl_rdh,  //'0': write, '1': read
    wrdata,
    address,
    op_ack,
    rddata
);

  function [3:0] fun_ascii2hex;
    input [7:0] data_in;
    reg [3:0] hex_s;
    begin
      case (data_in)
        48: hex_s = 4'h0;
        49: hex_s = 4'h1;
        50: hex_s = 4'h2;
        51: hex_s = 4'h3;
        52: hex_s = 4'h4;
        53: hex_s = 4'h5;
        54: hex_s = 4'h6;
        55: hex_s = 4'h7;
        56: hex_s = 4'h8;
        57: hex_s = 4'h9;
        65, 97: hex_s = 4'hA;
        66, 98: hex_s = 4'hB;
        67, 99: hex_s = 4'hC;
        68, 100: hex_s = 4'hD;
        69, 101: hex_s = 4'hE;
        70, 102: hex_s = 4'hF;
        default: hex_s = 4'h0;
      endcase
      fun_ascii2hex = hex_s;
    end
  endfunction
  parameter addr_width = 3,  //indicate each data block have 256 data
  data_width = 8,  //each data bits
  para_width = 2;

  parameter [2:0] idle = 3'b001, pop_pkt = 3'b010, launch_op = 3'b100;
  input reset_l;
  input clk;

  input empty;
  output rpkt_pop;
  input [addr_width:0] rpkt_len;
  input [para_width-1:0] rpkt_para;
  output rpkt_ren;
  output [addr_width-1:0] rpkt_raddr;
  input [data_width-1:0] rpkt_rdata;

  output op_req;
  output wrl_rdh;
  output [31:0] wrdata;
  output [31:0] address;
  input op_ack;
  input [31:0] rddata;

  reg                  rpkt_pop;
  reg                  rpkt_ren;
  reg [addr_width-1:0] rpkt_raddr;
  reg                  op_req;
  reg                  wrl_rdh;
  reg [          31:0] wrdata;
  reg [          31:0] address;

  reg                  pop_pkt_done;
  reg [           4:0] sta_cnt;

  reg [           2:0] cur_state;
  reg [           2:0] next_state;

  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      cur_state <= idle;
    end else begin
      cur_state <= next_state;
    end
  end

  always_comb begin
    case (cur_state)
      idle: begin
        if (reset_l == 1'b1 && empty == 1'b0) begin
          next_state <= pop_pkt;
        end else begin
          next_state <= idle;
        end
      end
      pop_pkt: begin
        if (pop_pkt_done == 1'b1) begin
          next_state <= launch_op;
        end else begin
          next_state <= pop_pkt;
        end
      end
      launch_op: begin
        if (op_req == 1'b1) begin
          next_state <= idle;
        end else begin
          next_state <= launch_op;
        end
      end
      default: next_state <= idle;
    endcase
  end

  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      sta_cnt <= 5'b0;
      rpkt_pop <= 1'b0;
      pop_pkt_done <= 1'b0;
      rpkt_ren <= 1'b0;
      rpkt_raddr <= {addr_width{1'b0}};
      op_req <= 1'b0;
      wrl_rdh <= 1'b1;
      wrdata <= 32'b0;
      address <= 32'b0;
    end else begin
      case (cur_state)
        pop_pkt: begin
          op_req <= 1'b0;
          pop_pkt_done <= 1'b0;
          if (sta_cnt > 3) begin
            sta_cnt <= 5'b0;
            pop_pkt_done <= 1'b1;
          end else begin
            sta_cnt <= sta_cnt + 1;
          end
          rpkt_pop <= 1'b0;
          if (sta_cnt == 1) begin
            rpkt_pop <= 1'b1;
          end
          if (sta_cnt == 4) begin
            if (rpkt_para == {para_width{1'b0}}) begin
              wrl_rdh <= 1'b0;
            end else begin
              wrl_rdh <= 1'b1;
            end
          end
          if (pop_pkt_done == 1'b1) begin
            sta_cnt <= 5'b0;
          end
        end
        launch_op: begin
          pop_pkt_done <= 1'b0;
          op_req <= 1'b0;
          if (sta_cnt >= 19) begin
            sta_cnt <= 5'b0;
          end else begin
            sta_cnt <= sta_cnt + 1;
          end
          if (sta_cnt == 0 && op_req == 1'b0) begin
            rpkt_ren <= 1'b1;
          end
          if (sta_cnt == 16) begin
            rpkt_ren <= 1'b0;
          end
          if (rpkt_ren == 1'b1) begin
            rpkt_raddr <= rpkt_raddr + 1;
          end else begin
            rpkt_raddr <= {addr_width{1'b0}};
          end
          if (sta_cnt >= 2 && sta_cnt < 10) begin
            address[32-(sta_cnt-2)*4-1-:4] <= fun_ascii2hex(rpkt_rdata);
          end
          if (sta_cnt >= 10 && sta_cnt < 18) begin
            wrdata[32-(sta_cnt-10)*4-1-:4] <= fun_ascii2hex(rpkt_rdata);
          end
          op_req <= 1'b0;
          if (sta_cnt == 19) begin
            op_req <= 1'b1;
          end
        end
        default: begin
          pop_pkt_done <= 1'b0;
          sta_cnt <= 5'b0;
          op_req <= 1'b0;
        end
      endcase
    end
  end
endmodule  // pktfifo_lcpu


module lcpu_out_uart (
    reset_l,
    clk,

    op_req,
    wrl_rdh,  //'0': write, '1': read
    op_ack,
    rddata,

    write_en,
    write_data,
    full
);

  function [7:0] fun_hex2ascii;
    input [3:0] data_in;
    reg [7:0] ascii_s;
    begin
      case (data_in)
        0: ascii_s = "0";
        1: ascii_s = "1";
        2: ascii_s = "2";
        3: ascii_s = "3";
        4: ascii_s = "4";
        5: ascii_s = "5";
        6: ascii_s = "6";
        7: ascii_s = "7";
        8: ascii_s = "8";
        9: ascii_s = "9";
        10: ascii_s = "a";
        11: ascii_s = "b";
        12: ascii_s = "c";
        13: ascii_s = "d";
        14: ascii_s = "e";
        15: ascii_s = "f";
        default: ascii_s = "0";
      endcase
      fun_hex2ascii = ascii_s;
    end
  endfunction

  input reset_l;
  input clk;

  input op_req;
  input wrl_rdh;
  input op_ack;
  input [31:0] rddata;

  output write_en;
  output [7:0] write_data;
  input full;

  reg        read_data_op_ind;
  reg        read_data_op_ind_d0;
  reg [31:0] rddata_r;
  reg        start_return_rdata;
  reg        returnning_rdata;
  reg [ 2:0] return_rdata_cnt;
  reg        write_en;
  reg [ 7:0] write_data;
  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      read_data_op_ind <= 1'b0;
      read_data_op_ind_d0 <= 1'b0;
      rddata_r <= 32'b0;
      start_return_rdata <= 1'b0;
    end else begin
      if (op_req == 1'b1 && wrl_rdh == 1'b1) begin
        read_data_op_ind <= 1'b1;
      end
      if (op_ack == 1'b1) begin
        read_data_op_ind <= 1'b0;
        rddata_r <= rddata;
      end
      read_data_op_ind_d0 <= read_data_op_ind;
      start_return_rdata  <= ~read_data_op_ind & read_data_op_ind_d0;
    end
  end

  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      returnning_rdata <= 1'b0;
      return_rdata_cnt <= 3'b0;
    end else begin
      if (start_return_rdata == 1'b1) begin
        returnning_rdata <= 1'b1;
      end
      if (return_rdata_cnt == 3'd7) begin
        returnning_rdata <= 1'b0;
      end
      if (returnning_rdata == 1'b1) begin
        return_rdata_cnt <= return_rdata_cnt + 1;
      end else begin
        return_rdata_cnt <= 3'b0;
      end
    end
  end

  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      write_en   <= 1'b0;
      write_data <= 8'b0;
    end else begin
      write_en <= 1'b0;
      if (returnning_rdata == 1'b1) begin
        write_en   <= 1'b1;
        write_data <= fun_hex2ascii(rddata_r[32-(return_rdata_cnt)*4-1-:4]);
      end
    end
  end
endmodule  // lcpu2uart
