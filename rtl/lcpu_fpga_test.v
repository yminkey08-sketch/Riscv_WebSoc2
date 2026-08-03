//Code Generate at: 2026-07-27 21:57:23
module lcpu_fpga_test(
  input [31:0] fpga_build_date,
  input [31:0] fpga_build_time,
  output reg [31:0] sw_build_date,
  output reg [31:0] sw_build_time,
  output reg [31:0] Scrach_RW_0,
  output reg [31:0] Scrach_RW_1,
  output reg [31:0] Scrach_RW_2,
  output reg [31:0] Scrach_RW_3,
  output reg [31:0] Scrach_RW_4,
  output reg [31:0] Scrach_RW_5,
  output reg [31:0] Scrach_RW_6,
  output reg [31:0] Scrach_RW_7,
  output reg [31:0] Scrach_RW_8,
  output reg [31:0] Scrach_RW_9,
  output reg [31:0] Scrach_RW_10,
  output reg [31:0] Scrach_RW_11,
  output reg [3:0] led,
  input [0:0] pll_locked,
  input [0:0] cpu_rd_empty,
  output reg [0:0] cpu_rd_rpkt_pop,
  output reg cpu_rd_rpkt_pop_ind,
  input [31:0] cpu_rd_rpkt_len,
  input [31:0] cpu_rd_rpkt_para,
  output reg [0:0] cpu_rd_ren,
  output reg [31:0] cpu_rd_raddr,
  input [31:0] cpu_rd_rdata,
  input [0:0] cpu_rd_reop_pre,
  input [0:0] cpu_wr_full,
  output reg [0:0] cpu_wr_wen,
  output reg cpu_wr_wen_ind,
  output reg [31:0] cpu_wr_waddr,
  output reg [31:0] cpu_wr_wdata,
  output reg [31:0] cpu_wr_wpkt_len,
  output reg [0:0] cpu_wr_wpkt_push,
  output reg cpu_wr_wpkt_push_ind,
  output reg [0:0] riscv_reset_l,
  output RAMIF_program_ram_Ram_RlWh,
  output [15:0] RAMIF_program_ram_Ram_Addr,
  output [31:0] RAMIF_program_ram_Ram_WrData,
  input [31:0] RAMIF_program_ram_Ram_RdData,
  
  input clk,
  input rst_n,
  input req,
  input rhwl,
  input [31:0] wdata,
  input [31:0] address,
  output reg[31:0] rdata,
  output reg ack
  );
  
  reg timeout_ack;
  reg is_req;
  reg [15:0] is_req_cnt;
  reg [31:0] reg_rdata;
  reg reg_ack;
  
  reg SUBBUS_program_ram_Req;
  reg SUBBUS_program_ram_RhWl;
  reg [15:0] SUBBUS_program_ram_ReqAddr;
  reg [31:0] SUBBUS_program_ram_DataWr;
  wire [31:0]program_ram_sb_rdata;
  wire program_ram_sb_ack;
  
  
  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      is_req <= 1'b0;
      is_req_cnt <= 16'b0;
      timeout_ack <= 1'b0;
    end
    else begin 
      timeout_ack <= 1'b0;
      if(req == 1'b1)begin 
        is_req <= req;
      end
      if(is_req == 1'b1)begin 
        is_req_cnt <= is_req_cnt + 1;
      end
      else begin 
        is_req_cnt <= 16'b0;
      end
      if(is_req_cnt >= 16'hf000 || ack == 1'b1)begin 
        is_req <= 1'b0;
      end
      if(is_req_cnt == 16'hf000)begin 
        timeout_ack <= 1'b1;
      end
    end
  end

  
  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      sw_build_date <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h2)begin
        sw_build_date <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      sw_build_time <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h3)begin
        sw_build_time <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      Scrach_RW_0 <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h4)begin
        Scrach_RW_0 <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      Scrach_RW_1 <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h5)begin
        Scrach_RW_1 <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      Scrach_RW_2 <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h6)begin
        Scrach_RW_2 <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      Scrach_RW_3 <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h7)begin
        Scrach_RW_3 <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      Scrach_RW_4 <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h8)begin
        Scrach_RW_4 <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      Scrach_RW_5 <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h9)begin
        Scrach_RW_5 <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      Scrach_RW_6 <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'hA)begin
        Scrach_RW_6 <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      Scrach_RW_7 <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'hB)begin
        Scrach_RW_7 <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      Scrach_RW_8 <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'hC)begin
        Scrach_RW_8 <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      Scrach_RW_9 <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'hD)begin
        Scrach_RW_9 <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      Scrach_RW_10 <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'hE)begin
        Scrach_RW_10 <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      Scrach_RW_11 <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'hF)begin
        Scrach_RW_11 <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      led <= 4'hf;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h10)begin
        led <= wdata[3:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      cpu_rd_rpkt_pop <= 1'h0;
    cpu_rd_rpkt_pop_ind <= 1'b0;
    end
    else begin 
      cpu_rd_rpkt_pop_ind <= 1'b0;
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h6001)begin
        cpu_rd_rpkt_pop_ind <= 1'b1;
        cpu_rd_rpkt_pop <= wdata[0:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      cpu_rd_ren <= 1'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h6004)begin
        cpu_rd_ren <= wdata[0:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      cpu_rd_raddr <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h6005)begin
        cpu_rd_raddr <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      cpu_wr_wen <= 1'h0;
    cpu_wr_wen_ind <= 1'b0;
    end
    else begin 
      cpu_wr_wen_ind <= 1'b0;
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h6101)begin
        cpu_wr_wen_ind <= 1'b1;
        cpu_wr_wen <= wdata[0:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      cpu_wr_waddr <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h6102)begin
        cpu_wr_waddr <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      cpu_wr_wdata <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h6103)begin
        cpu_wr_wdata <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      cpu_wr_wpkt_len <= 32'h0;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h6104)begin
        cpu_wr_wpkt_len <= wdata[31:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      cpu_wr_wpkt_push <= 1'h0;
    cpu_wr_wpkt_push_ind <= 1'b0;
    end
    else begin 
      cpu_wr_wpkt_push_ind <= 1'b0;
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h6106)begin
        cpu_wr_wpkt_push_ind <= 1'b1;
        cpu_wr_wpkt_push <= wdata[0:0];
      end
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      riscv_reset_l <= 1'h1;
    end
    else begin 
      if(req == 1'b1 && rhwl == 1'b0 && address == 32'h100)begin
        riscv_reset_l <= wdata[0:0];
      end
    end
  end

  
  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      reg_rdata <= 32'b0;
      reg_ack <= 1'b0;
    end
    else begin 
      reg_ack <= 1'b0;
      if(req == 1'b1 && rhwl == 1'b1)reg_rdata <= 32'b0;
      if(req == 1'b1 && address == 32'h0)begin 
        reg_rdata[31:0]<=fpga_build_date;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h1)begin 
        reg_rdata[31:0]<=fpga_build_time;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h2)begin 
        reg_rdata[31:0]<=sw_build_date;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h3)begin 
        reg_rdata[31:0]<=sw_build_time;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h4)begin 
        reg_rdata[31:0]<=Scrach_RW_0;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h5)begin 
        reg_rdata[31:0]<=Scrach_RW_1;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6)begin 
        reg_rdata[31:0]<=Scrach_RW_2;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h7)begin 
        reg_rdata[31:0]<=Scrach_RW_3;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h8)begin 
        reg_rdata[31:0]<=Scrach_RW_4;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h9)begin 
        reg_rdata[31:0]<=Scrach_RW_5;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'hA)begin 
        reg_rdata[31:0]<=Scrach_RW_6;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'hB)begin 
        reg_rdata[31:0]<=Scrach_RW_7;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'hC)begin 
        reg_rdata[31:0]<=Scrach_RW_8;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'hD)begin 
        reg_rdata[31:0]<=Scrach_RW_9;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'hE)begin 
        reg_rdata[31:0]<=Scrach_RW_10;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'hF)begin 
        reg_rdata[31:0]<=Scrach_RW_11;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h10)begin 
        reg_rdata[3:0]<=led;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h11)begin 
        reg_rdata[0:0]<=pll_locked;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6000)begin 
        reg_rdata[0:0]<=cpu_rd_empty;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6001)begin 
        reg_rdata[0:0]<=cpu_rd_rpkt_pop;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6002)begin 
        reg_rdata[31:0]<=cpu_rd_rpkt_len;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6003)begin 
        reg_rdata[31:0]<=cpu_rd_rpkt_para;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6004)begin 
        reg_rdata[0:0]<=cpu_rd_ren;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6005)begin 
        reg_rdata[31:0]<=cpu_rd_raddr;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6006)begin 
        reg_rdata[31:0]<=cpu_rd_rdata;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6007)begin 
        reg_rdata[0:0]<=cpu_rd_reop_pre;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6100)begin 
        reg_rdata[0:0]<=cpu_wr_full;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6101)begin 
        reg_rdata[0:0]<=cpu_wr_wen;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6102)begin 
        reg_rdata[31:0]<=cpu_wr_waddr;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6103)begin 
        reg_rdata[31:0]<=cpu_wr_wdata;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6104)begin 
        reg_rdata[31:0]<=cpu_wr_wpkt_len;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h6106)begin 
        reg_rdata[0:0]<=cpu_wr_wpkt_push;
        reg_ack <= 1'b1;
      end
      if(req == 1'b1 && address == 32'h100)begin 
        reg_rdata[0:0]<=riscv_reset_l;
        reg_ack <= 1'b1;
      end
      
    end
  end

  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      SUBBUS_program_ram_Req <= 1'b0;
      SUBBUS_program_ram_RhWl <= 1'b1;
      SUBBUS_program_ram_ReqAddr <= 16'b0;
      SUBBUS_program_ram_DataWr <= 32'b0;
    end
    else begin 
      if(address >= 32'h10000 && address <= 32'h1ffff)begin 
        SUBBUS_program_ram_Req <= req;
      end
      SUBBUS_program_ram_RhWl <= rhwl;
      SUBBUS_program_ram_ReqAddr <= address[15:0];
      SUBBUS_program_ram_DataWr <= wdata;
    end
  end

  
  
  always @ (posedge clk or negedge rst_n) begin 
    if(!rst_n) begin 
      ack <= 1'b0;
      rdata <= 32'b0;
    end
    else begin 
      if(program_ram_sb_ack)rdata <= program_ram_sb_rdata;
      ack <=timeout_ack | reg_ack |program_ram_sb_ack;
      if(timeout_ack)rdata <= 32'hdeaddead;
      if(reg_ack)rdata <= reg_rdata;
    end
  end

  
  ramintf 
    #( 
    .DataBits(32),
    .AddrBits(16)
    ) RAMIF_program_ram(
    .Ram_RdData(RAMIF_program_ram_Ram_RdData), 
    .Ram_RlWh(RAMIF_program_ram_Ram_RlWh), 
    .Ram_Addr(RAMIF_program_ram_Ram_Addr), 
    .Ram_WrData(RAMIF_program_ram_Ram_WrData), 
    .clk(clk), 
    .rst_n(rst_n), 
    .req(SUBBUS_program_ram_Req), 
    .rhwl(SUBBUS_program_ram_RhWl), 
    .wdata(SUBBUS_program_ram_DataWr), 
    .address(SUBBUS_program_ram_ReqAddr), 
    .rdata(program_ram_sb_rdata), 
    .ack(program_ram_sb_ack) 
    ); 
      
  
endmodule 


