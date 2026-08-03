//Code Generate at: 2026-06-19 10:19:42
module riscv_reg (
    output reg SUBBUS_riscv_ctrl_Req,
    output reg SUBBUS_riscv_ctrl_RhWl,
    output reg [30:0] SUBBUS_riscv_ctrl_ReqAddr,
    output reg [31:0] SUBBUS_riscv_ctrl_DataWr,
    input [31:0] SUBBUS_riscv_ctrl_DataRd,
    input SUBBUS_riscv_ctrl_Ack,
    output RAMIF_instuct_ram_Ram_RlWh,
    output [30:0] RAMIF_instuct_ram_Ram_Addr,
    output [31:0] RAMIF_instuct_ram_Ram_WrData,
    input [31:0] RAMIF_instuct_ram_Ram_RdData,

    input clk,
    input rst_n,
    input req,
    input rhwl,
    input [31:0] wdata,
    input [31:0] address,
    output reg [31:0] rdata,
    output reg ack
);

  reg timeout_ack;
  reg is_req;
  reg [15:0] is_req_cnt;
  reg [31:0] reg_rdata;
  reg reg_ack;
  reg [31:0] riscv_ctrl_sb_rdata;
  reg riscv_ctrl_sb_ack;

  reg SUBBUS_instuct_ram_Req;
  reg SUBBUS_instuct_ram_RhWl;
  reg [30:0] SUBBUS_instuct_ram_ReqAddr;
  reg [31:0] SUBBUS_instuct_ram_DataWr;
  wire [31:0] instuct_ram_sb_rdata;
  wire instuct_ram_sb_ack;


  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      is_req <= 1'b0;
      is_req_cnt <= 16'b0;
      timeout_ack <= 1'b0;
    end else begin
      timeout_ack <= 1'b0;
      if (req == 1'b1) begin
        is_req <= req;
      end
      if (is_req == 1'b1) begin
        is_req_cnt <= is_req_cnt + 1;
      end else begin
        is_req_cnt <= 16'b0;
      end
      if (is_req_cnt >= 16'hf000 || ack == 1'b1) begin
        is_req <= 1'b0;
      end
      if (is_req_cnt == 16'hf000) begin
        timeout_ack <= 1'b1;
      end
    end
  end



  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reg_rdata <= 32'b0;
      reg_ack   <= 1'b0;
    end else begin
      reg_ack <= 1'b0;
      if (req == 1'b1 && rhwl == 1'b1) reg_rdata <= 32'b0;

    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      SUBBUS_riscv_ctrl_Req <= 1'b0;
      SUBBUS_riscv_ctrl_RhWl <= 1'b1;
      SUBBUS_riscv_ctrl_ReqAddr <= 31'b0;
      SUBBUS_riscv_ctrl_DataWr <= 32'b0;
    end else begin
      if (address >= 32'h80000000 && address <= 32'hffffffff) begin
        SUBBUS_riscv_ctrl_Req <= req;
      end
      SUBBUS_riscv_ctrl_RhWl <= rhwl;
      SUBBUS_riscv_ctrl_ReqAddr <= address[30:0];
      SUBBUS_riscv_ctrl_DataWr <= wdata;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      SUBBUS_instuct_ram_Req <= 1'b0;
      SUBBUS_instuct_ram_RhWl <= 1'b1;
      SUBBUS_instuct_ram_ReqAddr <= 31'b0;
      SUBBUS_instuct_ram_DataWr <= 32'b0;
    end else begin
      if (address >= 32'h0 && address <= 32'h7fffffff) begin
        SUBBUS_instuct_ram_Req <= req;
      end
      SUBBUS_instuct_ram_RhWl <= rhwl;
      SUBBUS_instuct_ram_ReqAddr <= address[30:0];
      SUBBUS_instuct_ram_DataWr <= wdata;
    end
  end


  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      riscv_ctrl_sb_ack   <= 1'b0;
      riscv_ctrl_sb_rdata <= 32'b0;
    end else begin
      riscv_ctrl_sb_ack   <= SUBBUS_riscv_ctrl_Ack;
      riscv_ctrl_sb_rdata <= SUBBUS_riscv_ctrl_DataRd;
    end
  end


  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ack   <= 1'b0;
      rdata <= 32'b0;
    end else begin
      if (riscv_ctrl_sb_ack) rdata <= riscv_ctrl_sb_rdata;
      if (instuct_ram_sb_ack) rdata <= instuct_ram_sb_rdata;
      ack <= timeout_ack | reg_ack | riscv_ctrl_sb_ack | instuct_ram_sb_ack;
      if (timeout_ack) rdata <= 32'hdeaddead;
      if (reg_ack) rdata <= reg_rdata;
    end
  end


  ramintf #(
      .DataBits(32),
      .AddrBits(31)
  ) RAMIF_instuct_ram (
      .Ram_RdData(RAMIF_instuct_ram_Ram_RdData),
      .Ram_RlWh(RAMIF_instuct_ram_Ram_RlWh),
      .Ram_Addr(RAMIF_instuct_ram_Ram_Addr),
      .Ram_WrData(RAMIF_instuct_ram_Ram_WrData),
      .clk(clk),
      .rst_n(rst_n),
      .req(SUBBUS_instuct_ram_Req),
      .rhwl(SUBBUS_instuct_ram_RhWl),
      .wdata(SUBBUS_instuct_ram_DataWr),
      .address(SUBBUS_instuct_ram_ReqAddr),
      .rdata(instuct_ram_sb_rdata),
      .ack(instuct_ram_sb_ack)
  );
endmodule


