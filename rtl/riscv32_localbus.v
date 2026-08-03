module riscv32_localbus #(
    parameter enable_irq = 0,
    parameter enable_irq_qregs = 1,
    parameter progaddr_irq = 16,
    parameter stackaddr = 32'h00008000
) (
    input clk,
    input reset_l,

    output        req,
    output        rhwl,
    output [ 3:0] wr_byte_en,
    output [31:0] wdata,
    output [31:0] address,
    input  [31:0] rdata,
    input         ack,

    input [31:0] irq
);

  wire        rv_valid;
  wire        rv_instr;
  wire        rv_ready;
  wire [31:0] rv_addr;
  wire [31:0] rv_wdata;
  wire [ 3:0] rv_wstrb;
  wire [31:0] rv_rdata;

  picorv32 #(
      .ENABLE_COUNTERS(1),
      .ENABLE_COUNTERS64(1),
      .ENABLE_REGS_16_31(1),
      .ENABLE_REGS_DUALPORT(1),
      .LATCHED_MEM_RDATA(0),
      .TWO_STAGE_SHIFT(1),
      .BARREL_SHIFTER(0),
      .TWO_CYCLE_COMPARE(0),
      .TWO_CYCLE_ALU(0),
      .COMPRESSED_ISA(1),
      .CATCH_MISALIGN(0),
      .CATCH_ILLINSN(1),
      .ENABLE_PCPI(0),
      .ENABLE_MUL(0),
      .ENABLE_FAST_MUL(0),
      .ENABLE_DIV(0),
      .ENABLE_IRQ(enable_irq),
      .ENABLE_IRQ_QREGS(enable_irq_qregs),
      .ENABLE_IRQ_TIMER(1),
      .ENABLE_TRACE(0),
      .REGS_INIT_ZERO(1),
      .MASKED_IRQ(32'h00000000),
      .LATCHED_IRQ(32'hffffffff),
      .PROGADDR_RESET(32'h00000000),
      .PROGADDR_IRQ(progaddr_irq),
      // Place the stack at the first byte above valid local RAM so downward growth
      // stays inside the implemented RAM depth.
      .STACKADDR(stackaddr)
  ) u_picorv32 (
      .clk(clk),
      .resetn(reset_l),
      .mem_valid(rv_valid),
      .mem_instr(rv_instr),
      .mem_ready(rv_ready),
      .mem_addr(rv_addr),
      .mem_wdata(rv_wdata),
      .mem_wstrb(rv_wstrb),
      .mem_rdata(rv_rdata),
      .irq(irq)
  );

  riscv32intfbridge u_RiscV32IntfBridge (
      .clk(clk),
      .reset_l(reset_l),
      .rv_valid(rv_valid),
      .rv_instr(rv_instr),
      .rv_ready(rv_ready),
      .rv_addr(rv_addr),
      .rv_wdata(rv_wdata),
      .rv_wstrb(rv_wstrb),
      .rv_rdata(rv_rdata),

      .req(req),
      .rhwl(rhwl),
      .wr_byte_en(wr_byte_en),
      .wdata(wdata),
      .address(address),
      .rdata(rdata),
      .ack(ack)
  );
endmodule
