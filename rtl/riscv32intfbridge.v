module riscv32intfbridge (
    input clk,
    input reset_l,

    input         rv_valid,
    input         rv_instr,
    output        rv_ready,
    input  [31:0] rv_addr,
    input  [31:0] rv_wdata,
    input  [ 3:0] rv_wstrb,
    output [31:0] rv_rdata,

    output reg        req,
    output reg        rhwl,
    output reg [ 3:0] wr_byte_en,
    output reg [31:0] wdata,
    output reg [31:0] address,
    input      [31:0] rdata,
    input             ack
);

  reg        cur_state;
  reg        rv_opdone_s;
  reg [31:0] rv_rdata_s;

  always @(posedge clk) begin
    rv_opdone_s <= ack;
    if (ack == 1'b1) begin
      rv_rdata_s <= rdata;
    end
  end

  assign rv_ready = rv_opdone_s;
  assign rv_rdata = rv_rdata_s;

  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      cur_state <= 1'b0;
      rhwl <= 1'b1;
      req <= 1'b0;
      address <= 32'b0;
      wdata <= 32'b0;
      wr_byte_en <= 4'b0;
    end else begin
      req <= 1'b0;
      if (cur_state == 1'b0) begin
        if (rv_valid == 1'b1) begin
          req <= 1'b1;
          if (rv_wstrb != 0) begin
            rhwl <= 1'b0;
          end else begin
            rhwl <= 1'b1;
          end
          address <= rv_addr;
          wdata <= rv_wdata;
          wr_byte_en <= rv_wstrb;
          cur_state <= 1'b1;
        end
      end

      if (cur_state == 1'b1) begin
        if (rv_opdone_s == 1'b1) begin
          cur_state <= 1'b0;
        end
      end
    end
  end
endmodule
