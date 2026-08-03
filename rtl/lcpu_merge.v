//****************************************Copyright 2013[c]************************//
// ************************Declaration***************************************//
// File name:        lcpu_nm21s_lcpu.v                                     //
// Author:           huaming.huang@link-real.com.cn                                    //
// Date:             2015-01-06 00:00 	                                     //
// Version Number:   1.0                                                     //
// Abstract:         2 lcpu bus slave map to 1 lcpu bus master
// Modification history:[including time, version, author and abstract]        //
// 22015-01-06 00:00        version 1.0     xxx                                //
// Abstract: Initial                                                         //
//                                                                     //
//          v1: support lcpu priority from high 	to 		low
//																				No 0 ------No n-1
// *********************************end************************************** //
// 20161015: change op_req_1 and op_req_2
module lcpu_merge (
    reset_l,
    clk,

    op_req_1,
    wrl_rdh_1,  //'0': write, '1': read
    wrdata_1,
    address_1,
    op_ack_1,
    rddata_1,

    op_req_2,
    wrl_rdh_2,  //'0': write, '1': read
    wrdata_2,
    address_2,
    op_ack_2,
    rddata_2,

    op_req,
    wrl_rdh,  //'0': write, '1': read
    wrdata,
    address,
    op_ack,
    rddata
);
  parameter addr_width = 32;
  parameter data_width = 32;

  parameter [2:0] idle = 3'b001, sta_lcpu_1 = 3'b010, sta_lcpu_2 = 3'b100;

  input reset_l;
  input clk;

  input op_req_1;
  input wrl_rdh_1;
  input [data_width-1:0] wrdata_1;
  input [addr_width-1:0] address_1;
  output op_ack_1;
  output [data_width-1:0] rddata_1;

  input op_req_2;
  input wrl_rdh_2;
  input [data_width-1:0] wrdata_2;
  input [addr_width-1:0] address_2;
  output op_ack_2;
  output [data_width-1:0] rddata_2;

  output op_req;
  output wrl_rdh;
  output [data_width-1:0] wrdata;
  output [addr_width-1:0] address;
  input op_ack;
  input [data_width-1:0] rddata;



  reg                  op_ack_1;
  reg [data_width-1:0] rddata_1;
  reg                  op_ack_2;
  reg [data_width-1:0] rddata_2;
  reg                  op_req;
  reg                  wrl_rdh;
  reg [data_width-1:0] wrdata;
  reg [addr_width-1:0] address;

  reg                  op_req_1_ind;
  reg                  op_req_2_ind;
  reg                  wrl_rdh_1_r;
  reg [data_width-1:0] wrdata_1_r;
  reg [addr_width-1:0] address_1_r;
  reg                  wrl_rdh_2_r;
  reg [data_width-1:0] wrdata_2_r;
  reg [addr_width-1:0] address_2_r;

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
        if (op_req_1_ind == 1'b1) begin
          next_state = sta_lcpu_1;
        end else if (op_req_2_ind == 1'b1) begin
          next_state = sta_lcpu_2;
        end else begin
          next_state = idle;
        end
      end
      sta_lcpu_1: begin
        if (op_ack == 1'b1) begin
          next_state = idle;
        end else begin
          next_state = sta_lcpu_1;
        end
      end
      sta_lcpu_2: begin
        if (op_ack == 1'b1) begin
          next_state = idle;
        end else begin
          next_state = sta_lcpu_2;
        end
      end
      default: next_state = idle;
    endcase
  end

  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      op_req_1_ind <= 1'b0;
      op_req_2_ind <= 1'b0;
      wrl_rdh_1_r <= 1'b1;
      wrdata_1_r <= {data_width{1'b0}};
      address_1_r <= {addr_width{1'b0}};
      wrl_rdh_2_r <= 1'b1;
      wrdata_2_r <= {data_width{1'b0}};
      address_2_r <= {addr_width{1'b0}};
      op_ack_1 <= 1'b0;
      rddata_1 <= {data_width{1'b0}};
      op_ack_2 <= 1'b0;
      rddata_2 <= {data_width{1'b0}};
      op_req <= 1'b0;
      wrl_rdh <= 1'b1;
      wrdata <= {data_width{1'b0}};
      address <= {addr_width{1'b0}};
    end else begin
      if (op_req_1 == 1'b1) begin
        op_req_1_ind <= 1'b1;
        wrl_rdh_1_r  <= wrl_rdh_1;
        wrdata_1_r   <= wrdata_1;
        address_1_r  <= address_1;
      end
      if (op_req_2 == 1'b1) begin
        op_req_2_ind <= 1'b1;
        wrl_rdh_2_r  <= wrl_rdh_2;
        wrdata_2_r   <= wrdata_2;
        address_2_r  <= address_2;
      end
      case (cur_state)
        idle: begin
          op_req   <= 1'b0;
          op_ack_1 <= 1'b0;
          op_ack_2 <= 1'b0;
          if (op_req_1_ind == 1'b1) begin
            op_req  <= 1'b1;
            wrl_rdh <= wrl_rdh_1_r;
            wrdata  <= wrdata_1_r;
            address <= address_1_r;
          end else if (op_req_2_ind == 1'b1) begin
            op_req  <= 1'b1;
            wrl_rdh <= wrl_rdh_2_r;
            wrdata  <= wrdata_2_r;
            address <= address_2_r;
          end
        end
        sta_lcpu_1: begin
          op_req   <= 1'b0;
          op_ack_1 <= op_ack;
          if (op_ack == 1'b1) begin
            op_req_1_ind <= 1'b0;
            rddata_1 <= rddata;
          end
        end
        sta_lcpu_2: begin
          op_req   <= 1'b0;
          op_ack_2 <= op_ack;
          if (op_ack == 1'b1) begin
            op_req_2_ind <= 1'b0;
            rddata_2 <= rddata;
          end
        end
        default: begin
          op_req   <= 1'b0;
          op_ack_1 <= 1'b0;
          op_ack_2 <= 1'b0;
        end
      endcase
    end
  end
endmodule


