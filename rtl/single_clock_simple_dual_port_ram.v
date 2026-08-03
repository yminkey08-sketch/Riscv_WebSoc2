// sclk_sdpram.v — 同步简单双口RAM（Simple Dual-Port RAM，同一时钟域）
//
// 端口A：只写（wren_a, data_a, address_a）
// 端口B：只读（address_b, q_b）
// 读写模式：READ_FIRST（读写同地址时，端口B输出写入前的旧数据）
//
// 参数说明：
//   data_width      : 数据位宽（bit）
//   depth      : 实际需要的RAM字数（非2的幂亦可，例如 8193 只分配 9 个Block RAM）
//   addr_width      : 地址端口位宽，需满足 2^addr_width >= depth，推荐设为 $clog2(depth)
//   block_ram_size : 每块Block RAM的数据位大小（单位：Kbit，不含奇偶校验位）
//                   intel Cyclone IV M4K=4, Cyclone V M20K=20(实际数据18Kbit)
//                   Xilinx 7系列 RAMB36 数据位=32Kbit（36Kbit含4Kbit校验）
//                   默认 32 对应 RAMB36/M20K 32位宽模式下各 1024 字/块
//   ram_type       : 综合实现方式，"block"/"distributed"/"M4K"/"MLAB"
//
// Block RAM 粒度分配原理：
//   WORDS_PER_BRAM = block_ram_size × 1024 / data_width  （每块可存的字数）
//   NUM_BRAMS      = ceil(depth / WORDS_PER_BRAM)   （需要的最少块数）
//   ALLOC_DEPTH    = NUM_BRAMS × WORDS_PER_BRAM        （对齐到整块边界的分配深度）
//   综合工具据 ALLOC_DEPTH 推断 Block RAM 数量，以 1 块为粒度增长，
//   不再强制对齐到 2 的幂次，避免浪费。
//
// 综合属性兼容性：
//   intel Quartus  : (* ramstyle = ram_type *)   [Verilog属性语法]
//   Xilinx Vivado  : (* ram_style = ram_type *)  [Verilog属性语法]
//   Synplify Pro   : /* synthesis syn_ramstyle = ram_type */  [注释属性语法]

`include "define.sv"

module single_clock_simple_dual_port_ram #(
    parameter data_width = 32,
    parameter addr_width = 12,  // 地址端口位宽（外部传入，仅决定端口宽度）
    parameter depth = 4096,  // 实际需要的RAM字数（非2的幂亦可）
    // 注意：内部实际分配深度ALLOC_DEPTH由block_ram_size计算，
    // 可能大于2^addr_width；请确保addr_bits >= $clog2(depth)
    parameter block_ram_size = 32,  // 每块Block RAM数据位大小（Kbit，不含校验）
    parameter ram_type = "block",  /*"block" ; "distributed" ; "M4K" ; "MLAB"*/
    parameter vendor = ""  // "xilinx"(Xilinx) ; "intel"
) (
    input                   clk,
    // 端口A：写端口
    input                   wren_a,
    input  [data_width-1:0] data_a,
    input  [addr_width-1:0] address_a,
    // 端口B：读端口
    input  [addr_width-1:0] address_b,
    output [data_width-1:0] q_b
);
  localparam BYTE_EN_BITS = data_width / 8;

  // 每块Block RAM能存储的字数
  localparam WORDS_PER_BRAM = (block_ram_size * 1024) / data_width;

  // 向上取整，计算所需最少Block RAM块数
  localparam NUM_BRAMS = (depth + WORDS_PER_BRAM - 1) / WORDS_PER_BRAM;

  // 对齐到整数块边界的实际分配深度
  localparam ALLOC_DEPTH = NUM_BRAMS * WORDS_PER_BRAM;

  // 内部地址线位宽：由ALLOC_DEPTH精确计算
  localparam ALLOC_ADDR_BITS = $clog2(ALLOC_DEPTH);

  // 分布式RAM/寄存器实现不受Block RAM粒度约束，直接按 depth 分配
  localparam EFF_DEPTH     = (ram_type == "registers" || ram_type == "distributed") ? depth : ALLOC_DEPTH;
  localparam EFF_ADDR_BITS = $clog2(EFF_DEPTH);

  localparam BANK_DEPTH = WORDS_PER_BRAM;
  localparam BANK_ADDR_BITS = $clog2(BANK_DEPTH);
  localparam BANK_SEL_BITS = (NUM_BRAMS <= 1) ? 1 : $clog2(NUM_BRAMS);

  // intel(Cyclone IV M9K) simple dual-port 宽深比：
  //   宽度 > 9bit 时采用 512 深度 bank，可避免 13bit 地址被扩到 8192 深度后
  //   退化为 32 个 1-bit 宽 RAM 块的问题。
  localparam INTEL_BANK_DEPTH =
	(data_width > 9) ? 512 :
	(data_width > 4) ? 1024 :
	(data_width > 2) ? 2048 :
	(data_width > 1) ? 4096 : 8192;
  localparam INTEL_NUM_BANKS = (depth + INTEL_BANK_DEPTH - 1) / INTEL_BANK_DEPTH;
  localparam INTEL_ALLOC_DEPTH = INTEL_NUM_BANKS * INTEL_BANK_DEPTH;
  localparam INTEL_ALLOC_ADDR_BITS = $clog2(INTEL_ALLOC_DEPTH);
  localparam INTEL_BANK_ADDR_BITS = $clog2(INTEL_BANK_DEPTH);
  localparam INTEL_BANK_SEL_BITS = (INTEL_NUM_BANKS <= 1) ? 1 : $clog2(INTEL_NUM_BANKS);

  // Zero-extend: allow addr_width < EFF_ADDR_BITS (upper BRAM addr pins tied to 0)
  wire [EFF_ADDR_BITS-1:0] eff_addr_a = address_a;
  wire [EFF_ADDR_BITS-1:0] eff_addr_b = address_b;

  wire [data_width-1:0] q_b_int;

  // ── 参数约束 ──────────────────────────────────────────
  //   addr_width 必须足够覆盖 ALLOC_DEPTH 的地址空间
  //   若不满足，仿真时 $fatal 报错退出；综合时未定义模块导致工具报错。
  generate
    if (addr_width < EFF_ADDR_BITS) begin : gen_addr_width_check
      // synthesis translate_off
      initial begin
        $fatal(
            1,
            "\n  FATAL: addr_width (%0d) must be >= EFF_ADDR_BITS ($clog2(EFF_DEPTH) = %0d).\n         EFF_DEPTH = %0d\n",
            addr_width, EFF_ADDR_BITS, EFF_DEPTH);
      end
      // synthesis translate_on
    end
  endgenerate

  generate
    // xilinx(Xilinx)原语：xpm_memory_sdpram（Simple Dual-Port RAM）
    if (vendor == "xilinx") begin : gen_xilinx_xpm_sdpr
      localparam XPM_BYTE_WRITE_WIDTH = (data_width % 8 == 0) ? 8 : data_width;
      localparam XPM_WE_WIDTH = data_width / XPM_BYTE_WRITE_WIDTH;

      wire [ALLOC_ADDR_BITS-1:0] addr_a_idx = address_a;
      wire [ALLOC_ADDR_BITS-1:0] addr_b_idx = address_b;
      wire addr_a_valid = (addr_a_idx < ALLOC_DEPTH);
      wire addr_b_valid = (addr_b_idx < ALLOC_DEPTH);

      wire [BANK_SEL_BITS-1:0] bank_sel_a = addr_a_idx / BANK_DEPTH;
      wire [BANK_SEL_BITS-1:0] bank_sel_b = addr_b_idx / BANK_DEPTH;
      wire [BANK_ADDR_BITS-1:0] bank_addr_a = addr_a_idx % BANK_DEPTH;
      wire [BANK_ADDR_BITS-1:0] bank_addr_b = addr_b_idx % BANK_DEPTH;

      reg [BANK_SEL_BITS-1:0] bank_sel_b_r;
      reg bank_sel_b_valid_r;

      wire [data_width-1:0] q_b_bank[0:NUM_BRAMS-1];

      integer xb;
      reg [data_width-1:0] q_b_mux;

      always @(posedge clk) begin
        bank_sel_b_r <= bank_sel_b;
        bank_sel_b_valid_r <= addr_b_valid;
      end

      always_comb begin
        q_b_mux = {data_width{1'b0}};
        for (xb = 0; xb < NUM_BRAMS; xb = xb + 1) begin
          if (bank_sel_b_r == xb[BANK_SEL_BITS-1:0]) q_b_mux = q_b_bank[xb];
        end
      end

      assign q_b_int = bank_sel_b_valid_r ? q_b_mux : {data_width{1'b0}};

      genvar bi;
      for (bi = 0; bi < NUM_BRAMS; bi = bi + 1) begin : xpm_bank
        wire [XPM_WE_WIDTH-1:0] wea_b = {XPM_WE_WIDTH{wren_a && addr_a_valid && (bank_sel_a == bi[BANK_SEL_BITS-1:0])}};

        xpm_memory_sdpram #(
            .ADDR_WIDTH_A           (BANK_ADDR_BITS),
            .ADDR_WIDTH_B           (BANK_ADDR_BITS),
            .AUTO_SLEEP_TIME        (0),
            .BYTE_WRITE_WIDTH_A     (XPM_BYTE_WRITE_WIDTH),
            .CASCADE_HEIGHT         (0),
            .CLOCKING_MODE          ("common_clock"),
            .ECC_MODE               ("no_ecc"),
            .MEMORY_INIT_FILE       ("none"),
            .MEMORY_INIT_PARAM      ("0"),
            .MEMORY_OPTIMIZATION    ("true"),
            .MEMORY_PRIMITIVE       ("block"),
            .MEMORY_SIZE            (BANK_DEPTH * data_width),
            .MESSAGE_CONTROL        (0),
            .READ_DATA_WIDTH_B      (data_width),
            .READ_LATENCY_B         (1),
            .READ_RESET_VALUE_B     ("0"),
            .RST_MODE_B             ("SYNC"),
            .SIM_ASSERT_CHK         (0),
            .USE_EMBEDDED_CONSTRAINT(0),
            .USE_MEM_INIT           (0),
            .WAKEUP_TIME            ("disable_sleep"),
            .WRITE_DATA_WIDTH_A     (data_width)
        ) u_xpm_memory_sdpram_bank (
            .sleep         (1'b0),
            .clka          (clk),
            .ena           (1'b1),
            .wea           (wea_b),
            .addra         (bank_addr_a),
            .dina          (data_a),
            .injectsbiterra(1'b0),
            .injectdbiterra(1'b0),
            .clkb          (clk),
            .enb           (1'b1),
            .addrb         (bank_addr_b),
            .doutb         (q_b_bank[bi]),
            .regceb        (1'b1),
            .rstb          (1'b0)
        );
      end


    end else if (vendor == "intel") begin : gen_intel_altsyncram

      wire [INTEL_ALLOC_ADDR_BITS-1:0] addr_a_idx = address_a;
      wire [INTEL_ALLOC_ADDR_BITS-1:0] addr_b_idx = address_b;
      wire addr_a_valid = (addr_a_idx < INTEL_ALLOC_DEPTH);
      wire addr_b_valid = (addr_b_idx < INTEL_ALLOC_DEPTH);

      wire [INTEL_BANK_SEL_BITS-1:0] bank_sel_a = addr_a_idx / INTEL_BANK_DEPTH;
      wire [INTEL_BANK_SEL_BITS-1:0] bank_sel_b = addr_b_idx / INTEL_BANK_DEPTH;
      wire [INTEL_BANK_ADDR_BITS-1:0] bank_addr_a = addr_a_idx % INTEL_BANK_DEPTH;
      wire [INTEL_BANK_ADDR_BITS-1:0] bank_addr_b = addr_b_idx % INTEL_BANK_DEPTH;

      reg [INTEL_BANK_SEL_BITS-1:0] bank_sel_b_r;
      reg bank_sel_b_valid_r;

      wire [data_width-1:0] q_b_bank[0:INTEL_NUM_BANKS-1];

      integer ib;
      reg [data_width-1:0] q_b_mux_i;

      always @(posedge clk) begin
        bank_sel_b_r <= bank_sel_b;
        bank_sel_b_valid_r <= addr_b_valid;
      end

      always_comb begin
        q_b_mux_i = {data_width{1'b0}};
        for (ib = 0; ib < INTEL_NUM_BANKS; ib = ib + 1) begin
          if (bank_sel_b_r == ib[INTEL_BANK_SEL_BITS-1:0]) q_b_mux_i = q_b_bank[ib];
        end
      end

      assign q_b_int = bank_sel_b_valid_r ? q_b_mux_i : {data_width{1'b0}};

      genvar ii;
      for (ii = 0; ii < INTEL_NUM_BANKS; ii = ii + 1) begin : altsyncram_bank
        wire wren_a_i = wren_a && addr_a_valid && (bank_sel_a == ii[INTEL_BANK_SEL_BITS-1:0]);

        altsyncram #(
            .operation_mode                    ("DUAL_PORT"),
            .width_a                           (data_width),
            .widthad_a                         (INTEL_BANK_ADDR_BITS),
            .width_byteena_a                   (BYTE_EN_BITS),
            .numwords_a                        (INTEL_BANK_DEPTH),
            .width_b                           (data_width),
            .widthad_b                         (INTEL_BANK_ADDR_BITS),
            .numwords_b                        (INTEL_BANK_DEPTH),
            .outdata_reg_b                     ("CLOCK0"),
            .read_during_write_mode_mixed_ports("OLD_DATA"),
            .power_up_uninitialized            ("FALSE"),
            .ram_block_type                    ("M9K"),
            .clock_enable_input_a              ("NORMAL"),
            .clock_enable_input_b              ("NORMAL"),
            .clock_enable_output_a             ("NORMAL"),
            .clock_enable_output_b             ("NORMAL")
        ) u_altsyncram_bank (
            .clock0        (clk),
            .clock1        (clk),
            .clocken0      (1'b1),
            .clocken1      (1'b1),
            .clocken2      (1'b1),
            .clocken3      (1'b1),
            .aclr0         (1'b0),
            .aclr1         (1'b0),
            .address_a     (bank_addr_a),
            .address_b     (bank_addr_b),
            .addressstall_a(1'b0),
            .addressstall_b(1'b0),
            .byteena_a     ({BYTE_EN_BITS{1'b1}}),
            .wren_a        (wren_a_i),
            .rden_a        (1'b1),
            .data_a        (data_a),
            .rden_b        (1'b1),
            .q_b           (q_b_bank[ii]),
            .eccstatus     ()
        );
      end

    end else begin : gen_inferred_ram

      // 综合属性：Synplify(syn_ramstyle); Vivado/Quartus use default inference
      reg [data_width-1:0] ram[0:EFF_DEPTH-1]  /* synthesis syn_ramstyle = ram_type */;
      reg [data_width-1:0] q_b_r;
      localparam REM_BITS = data_width % 8;
      integer byte_idx_a;

      // 端口A：写
      // 注意：BYTE_EN_BITS = data_width / 8（整数除法），仅覆盖完整字节。
      // 当 data_width 非 8 的整数倍时，剩余高位需单独写入，否则在仿真中
      // 会保持为 X，导致数据通路卡死（如 fix_delay 用 9-bit {en,data} 时
      // 最高位 enable 始终为 X，整条 TX 路径不通）。
      // 使用 generate-if 替代运行时 if：当 REM_BITS=0 时，含非零宽度位选择
      // 的分支在编译期被消除，避免 Verilator 语法报错。
      if (REM_BITS > 0) begin : gen_port_a_nonbyte
        always @(posedge clk) begin
          if (wren_a) begin
            for (byte_idx_a = 0; byte_idx_a < BYTE_EN_BITS; byte_idx_a = byte_idx_a + 1) begin
              ram[eff_addr_a][byte_idx_a*8+:8] <= data_a[byte_idx_a*8+:8];
            end
            // 写入非 8 整数倍宽度的剩余高位（当 data_width<8 时写入全部位）
            ram[eff_addr_a][data_width-1-:REM_BITS] <= data_a[data_width-1-:REM_BITS];
          end
        end
      end else begin : gen_port_a_aligned
        always @(posedge clk) begin
          if (wren_a) begin
            for (byte_idx_a = 0; byte_idx_a < BYTE_EN_BITS; byte_idx_a = byte_idx_a + 1) begin
              ram[eff_addr_a][byte_idx_a*8+:8] <= data_a[byte_idx_a*8+:8];
            end
          end
        end
      end

      // 端口B：读（READ_FIRST 模式，非阻塞赋值保证读旧数据）
      always @(posedge clk) begin
        q_b_r <= ram[eff_addr_b];
      end

      assign q_b_int = q_b_r;
    end
  endgenerate

  assign q_b = q_b_int;
endmodule


// Dummy placeholder for tools (e.g. Verilator) that may mis-evaluate the
// generate condition due to cross-hierarchy parameter propagation.
// When parameters are legal, the condition is FALSE and this module is unused.
// NOTE: synthesis translate_off removed — allow synthesis when addr_width < EFF_ADDR_BITS
// (upper BRAM address pins float to zero, only lower portion of RAM is used).
module ERROR__addr_width_must_be_gte_alloc_addr_bits__single_clock_simple_dpram ();
endmodule

// synthesis translate_off
module tb_single_clock_simple_dual_port_ram;

  parameter data_width = 8;
  parameter depth = 20;  // 非2的幂，验证粒度分配
  parameter addr_width = 5;  // $clog2(20) = 5
  parameter block_ram_size = 32;

  reg clk;
  reg wren_a;
  reg [data_width-1:0] data_a;
  reg [addr_width-1:0] address_a, address_b;
  wire [data_width-1:0] q_b;

  single_clock_simple_dual_port_ram #(
      .data_width(data_width),
      .depth(depth),
      .addr_width(addr_width),
      .block_ram_size(block_ram_size),
      .ram_type("registers"),
      .vendor("")
  ) dut (
      .clk(clk),
      .wren_a(wren_a),
      .data_a(data_a),
      .address_a(address_a),
      .address_b(address_b),
      .q_b(q_b)
  );

  initial clk = 0;
  always #10 clk = ~clk;

  initial begin
    $dumpfile("tb_single_clock_simple_dual_port_ram.vcd");
    $dumpvars(0, tb_single_clock_simple_dual_port_ram);
    wren_a = 0;
    data_a = 0;
    address_a = 0;
    address_b = 0;
    #25;

    // 端口A写入地址0，值0xAB
    wren_a = 1;
    address_a = 5'h00;
    data_a = 8'hAB;
    @(posedge clk);
    #1;
    // 端口A写入地址1，值0xCD
    address_a = 5'h01;
    data_a = 8'hCD;
    @(posedge clk);
    #1;
    wren_a = 0;

    // 端口B读地址0
    address_b = 5'h00;
    @(posedge clk);
    #1;
    if (q_b !== 8'hAB) $display("FAIL: q_b=%h, expect AB", q_b);
    else $display("PASS: q_b=AB");

    // 端口B读地址1
    address_b = 5'h01;
    @(posedge clk);
    #1;
    if (q_b !== 8'hCD) $display("FAIL: q_b=%h, expect CD", q_b);
    else $display("PASS: q_b=CD");

    #100;
    // // $finish; (stripped) (stripped for sim)
  end
endmodule
// synthesis translate_on
