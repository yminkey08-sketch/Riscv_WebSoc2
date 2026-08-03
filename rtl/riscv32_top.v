module riscv32_top #(
    parameter instr_databits = 32,
    parameter init_addr_width = 13,
    parameter init_addr_depth = 8192,
    parameter vendor = "",  //"intel";	"xilinx"; “”
    parameter instr_ram_type = "M4K",  /* "registers" ; "M4K" */
    parameter init_blockram_size = 32,
    parameter enable_irq = 0,
    parameter enable_irq_qregs = 1,
    parameter progaddr_irq = 16
) (
    clk,
    reset_l,

    req,
    rhwl,
    wr_byte_en,
    wdata,
    address,
    rdata,
    ack,

    program_wr,
    program_waddr,
    program_wdata,
    program_rdata,

    irq
);
  localparam [31:0] stackaddr = init_addr_depth * (instr_databits / 8);

  input clk;
  input reset_l;
  output req;
  output rhwl;
  output [3:0] wr_byte_en;
  output [31:0] wdata;
  output [31:0] address;
  input [31:0] rdata;
  input ack;
  input program_wr;
  input [init_addr_width-1:0] program_waddr;
  input [instr_databits-1:0] program_wdata;
  output [instr_databits-1:0] program_rdata;
  input [31:0] irq;

  wire        req_m;
  wire        rhwl_m;
  wire [ 3:0] wr_byte_en_m;
  wire [31:0] wdata_m;
  wire [31:0] address_m;
  wire [31:0] rdata_m;
  wire        ack_m;

  reg         reset_l_s;

  wire        SUBBUS_RiscV_Ctrl_Req;
  wire        SUBBUS_RiscV_Ctrl_RhWl;
  wire [30:0] SUBBUS_RiscV_Ctrl_ReqAddr;
  wire [31:0] SUBBUS_RiscV_Ctrl_DataWr;
  wire [31:0] SUBBUS_RiscV_Ctrl_DataRd;
  wire        SUBBUS_RiscV_Ctrl_Ack;
  wire        RAMIF_Instuct_Ram_Ram_RlWh;
  wire [ 3:0] RAMIF_Instuct_Ram_Ram_ByteEn;
  wire [30:0] RAMIF_Instuct_Ram_Ram_Addr;
  wire [31:0] RAMIF_Instuct_Ram_Ram_WrData;
  wire [31:0] RAMIF_Instuct_Ram_Ram_RdData;

  // Pipeline wr_byte_en by 1 cycle to align with ramintf's Ram_RlWh timing
  reg  [ 3:0] wr_byte_en_d;

  assign req = SUBBUS_RiscV_Ctrl_Req;
  assign rhwl = SUBBUS_RiscV_Ctrl_RhWl;
  assign wr_byte_en = wr_byte_en_m;
  assign wdata = SUBBUS_RiscV_Ctrl_DataWr;
  assign address = {3'b0, SUBBUS_RiscV_Ctrl_ReqAddr[30:2]};
  assign SUBBUS_RiscV_Ctrl_DataRd = rdata;
  assign SUBBUS_RiscV_Ctrl_Ack = ack;

  always @(posedge clk) begin
    reset_l_s <= reset_l;
  end

  riscv32_localbus #(
      .enable_irq(enable_irq),
      .enable_irq_qregs(enable_irq_qregs),
      .progaddr_irq(progaddr_irq),
      .stackaddr(stackaddr)
  ) u_RiscV32_LocalBus (
      .clk(clk),
      .reset_l(reset_l_s),
      .req(req_m),
      .rhwl(rhwl_m),
      .wr_byte_en(wr_byte_en_m),
      .wdata(wdata_m),
      .address(address_m),
      .rdata(rdata_m),
      .ack(ack_m),
      .irq(irq)
  );

  //0x80000000 is external address, below is boot and app address
  riscv_reg u_riscv_reg (
      .SUBBUS_riscv_ctrl_Req(SUBBUS_RiscV_Ctrl_Req),
      .SUBBUS_riscv_ctrl_RhWl(SUBBUS_RiscV_Ctrl_RhWl),
      .SUBBUS_riscv_ctrl_ReqAddr(SUBBUS_RiscV_Ctrl_ReqAddr),
      .SUBBUS_riscv_ctrl_DataWr(SUBBUS_RiscV_Ctrl_DataWr),
      .SUBBUS_riscv_ctrl_DataRd(SUBBUS_RiscV_Ctrl_DataRd),
      .SUBBUS_riscv_ctrl_Ack(SUBBUS_RiscV_Ctrl_Ack),
      .RAMIF_instuct_ram_Ram_RlWh(RAMIF_Instuct_Ram_Ram_RlWh),
      .RAMIF_instuct_ram_Ram_Addr(RAMIF_Instuct_Ram_Ram_Addr),
      .RAMIF_instuct_ram_Ram_WrData(RAMIF_Instuct_Ram_Ram_WrData),
      .RAMIF_instuct_ram_Ram_RdData(RAMIF_Instuct_Ram_Ram_RdData),
      .clk(clk),
      .rst_n(reset_l_s),
      .req(req_m),
      .rhwl(rhwl_m),
      .wdata(wdata_m),
      .address(address_m),
      .rdata(rdata_m),
      .ack(ack_m)
  );
  always @(posedge clk or negedge reset_l_s) begin
    if (!reset_l_s) wr_byte_en_d <= 4'b0000;
    else if (req_m) wr_byte_en_d <= wr_byte_en_m;
  end
  assign RAMIF_Instuct_Ram_Ram_ByteEn = wr_byte_en_d;

  single_clock_true_dual_port_ram #(
      .data_width(instr_databits),
      .depth(init_addr_depth),
      .addr_width(init_addr_width),
      .block_ram_size(init_blockram_size),
      .ram_type(instr_ram_type),
      .vendor(vendor)
  ) u_instru_ram (
      .clk(clk),
      .wren_a(program_wr),
      .data_a(program_wdata),
      .address_a(program_waddr[init_addr_width-1:0]),
      .q_a(program_rdata),
      .wren_b(RAMIF_Instuct_Ram_Ram_RlWh),
      .data_b(RAMIF_Instuct_Ram_Ram_WrData),
      .address_b(RAMIF_Instuct_Ram_Ram_Addr[init_addr_width+2-1:2]),
      .q_b(RAMIF_Instuct_Ram_Ram_RdData),
      .wren_byte_b(RAMIF_Instuct_Ram_Ram_ByteEn)
  );
endmodule

/* verilator lint_off STMTDLY */
/* verilator lint_off ASSIGNDLY */
/* verilator lint_off WIDTH */
/* synthesis translate_off */
module tb_riscv32_top;

  localparam instr_databits = 32;
  localparam init_addr_width = 13;
  localparam init_addr_depth = 8192;

  reg                        clk;
  reg                        reset_l;
  wire                       req;
  wire                       rhwl;
  wire [                3:0] wr_byte_en;
  wire [               31:0] wdata;
  wire [               31:0] address;
  reg  [               31:0] rdata;
  reg                        ack;
  reg                        program_wr;
  reg  [init_addr_width-1:0] program_waddr;
  reg  [ instr_databits-1:0] program_wdata;
  wire [ instr_databits-1:0] program_rdata;
  reg  [               31:0] irq;

  riscv32_top #(
      .instr_databits    (instr_databits),
      .init_addr_width   (init_addr_width),
      .init_addr_depth   (init_addr_depth),
      .vendor            (""),
      .instr_ram_type    ("registers"),
      .init_blockram_size(32),
      .enable_irq        (0),
      .enable_irq_qregs  (1),
      .progaddr_irq      (16)
  ) dut (
      .clk          (clk),
      .reset_l      (reset_l),
      .req          (req),
      .rhwl         (rhwl),
      .wr_byte_en   (wr_byte_en),
      .wdata        (wdata),
      .address      (address),
      .rdata        (rdata),
      .ack          (ack),
      .program_wr   (program_wr),
      .program_waddr(program_waddr),
      .program_wdata(program_wdata),
      .program_rdata(program_rdata),
      .irq          (irq)
  );

  // ── jwrite task: RAM 接口写操作 ─────────────────────────
  //    jwrite(addr, data):
  //      addr == 32'h100 → 控制 reset_l (data[0]=0 复位, data[0]=1 释放)
  //      addr != 32'h100 → 通过 program_wr/program_waddr/program_wdata 写指令 RAM
  task jwrite;
    input [31:0] addr;
    input [31:0] data;
    begin
      if (addr == 32'h100) begin
        reset_l = data[0];
        $display("[TB] jwrite(0x100, 0x%h) → reset_l = %b @ %t", data, reset_l, $time);
      end else begin
        @(posedge clk);
        program_wr    = 1'b1;
        program_waddr = addr[init_addr_width-1:0];
        program_wdata = data;
        @(posedge clk);
        program_wr = 1'b0;
        $display("[TB] jwrite(0x%0h, 0x%08h) @ %t", addr, data, $time);
      end
    end
  endtask

  // ── 50MHz clock: period = 20ns ──────────────────────────
  initial clk = 0;
  always #10 clk = ~clk;

  // ── VCD dump ────────────────────────────────────────────
  initial begin
    $dumpfile("riscv32_top_verilator.vcd");
    $dumpvars(0, tb_riscv32_top);
  end

  // ── 简单总线应答模型 ────────────────────────────────────
  //    DUT 发出 req 后，下一拍返回 ack=1, rdata=0
  always @(posedge clk) begin
    if (req) begin
      ack   <= 1'b1;
      rdata <= 32'h0;
    end else begin
      ack <= 1'b0;
    end
  end

  // ── 主测试流程 ──────────────────────────────────────────
  initial begin
    // 初始化
    reset_l       = 1'b0;
    program_wr    = 1'b0;
    program_waddr = {init_addr_width{1'b0}};
    program_wdata = 32'h0;
    irq           = 32'h0;
    ack           = 1'b0;
    rdata         = 32'h0;

    $display("========================================");
    $display("  riscv32_top Unit Simulation");
    $display("  clk = 50 MHz, period = 20 ns");
    $display("========================================");

    // reset_l = 0 持续 100ns (复位)
    $display("[TB] Phase 1: Initial reset (reset_l=0 for 100ns)");
    #100;

    // 100ns 后拉高解除复位
    $display("[TB] Phase 2: De-assert reset (reset_l=1) @ %t", $time);
    reset_l = 1'b1;

    // 再过 100ns 开始配置
    #100;
    $display("[TB] Phase 3: Start configuration @ %t", $time);

    // ── 第一步：拉低 reset_l 进入配置复位 ──
    jwrite(32'h100, 32'h0);

    // ── 第二步：写入指令 RAM（InstructRAM.tcl, 36 words）──
    jwrite(32'h0, 32'h00800793);
    jwrite(32'h1, 32'h80828782);
    jwrite(32'h2, 32'hC6061141);
    jwrite(32'h3, 32'h28152831);
    jwrite(32'h4, 32'h8502BFFD);
    jwrite(32'h5, 32'h11418082);
    jwrite(32'h6, 32'h47B2C62A);
    jwrite(32'h7, 32'hFFF78713);
    jwrite(32'h8, 32'hFFE5C63A);
    jwrite(32'h9, 32'h80820141);
    jwrite(32'hA, 32'h20260737);
    jwrite(32'hB, 32'h800006B7);
    jwrite(32'hC, 32'h61970713);
    jwrite(32'hD, 32'h101947B7);
    jwrite(32'hE, 32'h8793C698);
    jwrite(32'hF, 32'hC6DC7007);
    jwrite(32'h10, 32'h07378082);
    jwrite(32'h11, 32'h46858000);
    jwrite(32'h12, 32'h2223C334);
    jwrite(32'h13, 32'h24230407);
    jwrite(32'h14, 32'hC7B70407);
    jwrite(32'h15, 32'hC774002D);
    jwrite(32'h16, 32'h6C078793);
    jwrite(32'h17, 32'h17FD873E);
    jwrite(32'h18, 32'h0737FF75);
    jwrite(32'h19, 32'h20238000);
    jwrite(32'h1A, 32'h47850407);
    jwrite(32'h1B, 32'hC73CC37C);
    jwrite(32'h1C, 32'h002DC7B7);
    jwrite(32'h1D, 32'h04072623);
    jwrite(32'h1E, 32'h6C078793);
    jwrite(32'h1F, 32'h17FD873E);
    jwrite(32'h20, 32'h8082FF75);
    jwrite(32'h21, 32'h00800793);
    jwrite(32'h22, 32'h45018782);
    jwrite(32'h23, 32'h00008082);

    // ── 最后一步：释放复位，CPU 开始执行 ──
    jwrite(32'h100, 32'h1);

    $display("========================================");
    $display("[TB] Phase 4: Configuration complete, CPU running @ %t", $time);
    $display("[TB] Running for 10us...");
    $display("========================================");

    // ── 仿真运行 ──
    #10_000;  // 10us

    $display("========================================");
    $display("[TB] Simulation finished @ %t", $time);
    $display("========================================");
    // // $finish; (stripped) (stripped for sim)
  end
endmodule
/* synthesis translate_on */
