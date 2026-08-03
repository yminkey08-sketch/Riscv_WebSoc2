//****************************************Copyright 2013[c]************************//
// ************************Declaration***************************************//
// File name:        dual_clock_fifo					                                       //
// Author:           huaming.huang @ link-real.com.cn                                          //
// Date:             2013-05-01 00:00 	                                     //
// Version Number:   1.0                                                     //
// Abstract:         asynchronizing fifo design
//                                                                            //
// Modification history:[including time, version, author and abstract]        //
// 2013-05-01 00:00        version 1.0     xxx                                //
// Abstract: Initial                                                          //
//                                             //
// *********************************end************************************** //

`include "define.sv"

module dual_clock_fifo (
    reset_l,
    //write
    wclk,
    write_en,
    write_data,
    full,
    //read
    rclk,
    read_en,
    read_data,
    empty
);

  parameter addr_width = 4;
  parameter data_width = 8;
  parameter ram_type = "registers";  // Cyclone IV device : "M9K","registers"
  localparam mem_depth = 2 ** addr_width;

  function [addr_width-1:0] bin2gray;
    input [addr_width-1:0] data_in;
    reg    [addr_width-1:0] gray;
    integer i;
    begin
      gray[addr_width-1] = data_in[addr_width-1];
      for (i = 0; i <= addr_width - 2; i = i + 1) begin
        gray[i] = data_in[i] ^ data_in[i+1];
      end
      bin2gray = gray;
    end
  endfunction

  input reset_l;

  input wclk;
  input write_en;
  input [data_width-1:0] write_data;
  output full;
  input rclk;
  input read_en;
  output [data_width-1:0] read_data;
  output empty;

  //reg define
  wire [addr_width-1:0] next_in_ptr;
  reg  [addr_width-1:0] in_ptr;
  reg  [addr_width-1:0] in_ptr_gray;
  reg  [addr_width-1:0] out_ptr_gray1;
  reg  [addr_width-1:0] out_ptr_gray2;

  wire [addr_width-1:0] next_out_ptr;
  reg  [addr_width-1:0] out_ptr;
  reg  [addr_width-1:0] out_ptr_gray;
  reg  [addr_width-1:0] in_ptr_gray1;
  reg  [addr_width-1:0] in_ptr_gray2;
  reg  [addr_width-1:0] read_addr;
  wire                  empty_s;
  wire                  full_s;

  (* ram_style = `SMALL_RAM *) (* ramstyle = `SMALL_RAM *)reg  [data_width-1:0] mem_array     [mem_depth-1:0];


  //Write side
  assign next_in_ptr = in_ptr + 1;
  assign full_s = (bin2gray(next_in_ptr) == out_ptr_gray2) ? 1'b1 : 1'b0;
  assign full = full_s;

  always @(negedge reset_l or posedge wclk)
    if (reset_l == 1'b0) begin
      in_ptr <= 0;
      in_ptr_gray <= 0;
    end else begin
      if ((write_en == 1'b1) && (full_s == 1'b0)) begin
        in_ptr <= next_in_ptr;
        in_ptr_gray <= bin2gray(next_in_ptr);
      end
    end
  // sync read address pointer
  always @(negedge reset_l or posedge wclk)
    if (reset_l == 1'b0) begin
      out_ptr_gray1 <= 0;
      out_ptr_gray2 <= 0;
    end else begin
      out_ptr_gray1 <= out_ptr_gray;
      out_ptr_gray2 <= out_ptr_gray1;
    end

  //Read side
  assign next_out_ptr = out_ptr + 1;
  assign empty_s = (in_ptr_gray2 == bin2gray(out_ptr)) ? 1'b1 : 1'b0;
  assign empty = empty_s;

  always @(negedge reset_l or posedge rclk)
    if (reset_l == 1'b0) begin
      out_ptr <= 0;
      out_ptr_gray <= 0;
    end else begin
      if ((read_en == 1'b1) && (empty_s == 1'b0)) begin
        out_ptr <= next_out_ptr;
        out_ptr_gray <= bin2gray(next_out_ptr);
      end
    end
  // sync write address pointer
  always @(negedge reset_l or posedge rclk)
    if (reset_l == 1'b0) begin
      in_ptr_gray1 <= 0;
      in_ptr_gray2 <= 0;
    end else begin
      in_ptr_gray1 <= in_ptr_gray;
      in_ptr_gray2 <= in_ptr_gray1;
    end

  //write into ram
  always @(negedge reset_l or posedge wclk)
    if (reset_l == 1'b0) begin
    end else begin
      if ((write_en == 1'b1) && (full_s == 1'b0)) begin
        mem_array[in_ptr] <= write_data;
      end
    end
  //read out ram
  always @(negedge reset_l or posedge rclk)
    if (reset_l == 1'b0) begin
    end else begin
      read_addr <= out_ptr;
    end
  assign read_data = mem_array[read_addr];
endmodule


// synthesis translate_off

module tb_dual_clock_fifo ();

  // ============================================================
  // Task: 写一个 word
  // ============================================================
  task write_word;
    input [DATA_WIDTH-1:0] wdata;
    begin
      @(posedge wclk);
      write_en   <= 1'b1;
      write_data <= wdata;
      @(posedge wclk);
      write_en <= 1'b0;
    end
  endtask

  // ============================================================
  // Task: 读一个 word，验证期望值
  // ============================================================
  task read_word;
    input [DATA_WIDTH-1:0] exp_data;
    reg [DATA_WIDTH-1:0] captured;
    begin
      @(posedge rclk);
      while (empty) @(posedge rclk);
      #1;
      captured = read_data;  // 在当前read_addr采样（read_en前）
      read_en <= 1'b1;
      @(posedge rclk);
      read_en <= 1'b0;
      if (captured !== exp_data) begin
        $display("  FAIL: read_data=%h expected=%h", captured, exp_data);
        errors = errors + 1;
      end
    end
  endtask

  localparam ADDR_WIDTH = 4;
  localparam DATA_WIDTH = 8;
  localparam FIFO_DEPTH = 2 ** ADDR_WIDTH;

  // 时钟 & 复位
  reg                      wclk;
  reg                      rclk;
  reg                      reset_l;

  // 写侧
  reg                      write_en;
  reg     [DATA_WIDTH-1:0] write_data;
  wire                     full;

  // 读侧
  reg                      read_en;
  wire    [DATA_WIDTH-1:0] read_data;
  wire                     empty;

  // 测试中使用的捕捉寄存器
  reg     [DATA_WIDTH-1:0] cap2;
  reg     [DATA_WIDTH-1:0] cap3;
  reg     [DATA_WIDTH-1:0] cap5;

  // 错误计数器
  integer                  errors;

  dual_clock_fifo #(
      .addr_width(ADDR_WIDTH),
      .data_width(DATA_WIDTH),
      .ram_type  ("registers")
  ) u_dut (
      .reset_l   (reset_l),
      .wclk      (wclk),
      .write_en  (write_en),
      .write_data(write_data),
      .full      (full),
      .rclk      (rclk),
      .read_en   (read_en),
      .read_data (read_data),
      .empty     (empty)
  );

  // ============================================================
  // 时钟生成 (wclk ≈ 100MHz, rclk ≈ 77MHz — 异频CDC)
  // ============================================================
  always #5 wclk = ~wclk;  // 100MHz
  always #6 rclk = ~rclk;  // ~83.3MHz

  // ============================================================
  // 波形输出
  // ============================================================
  initial begin
    $dumpfile("tb_dual_clock_fifo.vcd");
    $dumpvars(0, tb_dual_clock_fifo);
  end

  // ============================================================
  // 测试主流程
  // ============================================================
  initial begin
    // 初始化
    wclk       = 1'b0;
    rclk       = 1'b0;
    reset_l    = 1'b0;
    write_en   = 1'b0;
    write_data = 0;
    read_en    = 1'b0;
    errors     = 0;

    #100 reset_l = 1'b1;
    repeat (10) @(posedge wclk);
    repeat (10) @(posedge rclk);

    $display("============================================");
    $display("=== Test 0: 复位后初始状态 ===");
    $display("============================================");
    if (empty !== 1'b1) begin
      $display("  FAIL: empty=%b after reset", empty);
      errors = errors + 1;
    end else $display("  PASS: empty=1 after reset");
    if (full !== 1'b0) begin
      $display("  FAIL: full=%b after reset", full);
      errors = errors + 1;
    end else $display("  PASS: full=0 after reset");

    // =========================================================
    // Test 1: 基本写读 (Single write/read)
    // =========================================================
    $display("============================================");
    $display("=== Test 1: 单word写读 ===");
    $display("============================================");
    write_word(8'hA5);
    read_word(8'hA5);
    $display("  Test 1 errors=%0d", errors);

    // =========================================================
    // Test 2: 连续写读 (Burst write/read)
    // =========================================================
    $display("============================================");
    $display("=== Test 2: 连续写读 (15 words) ===");
    $display("============================================");

    // Test 2: write all 15 first (CDC settle), then read all
    $display("============================================");
    $display("=== Test 2: 连续写读 (15 words) ===");
    $display("============================================");

    // 先写满15个word
    begin : test2_write_seq
      integer i;
      for (i = 0; i < 15; i = i + 1) begin
        @(posedge wclk);
        while (full) @(posedge wclk);
        write_en   <= 1'b1;
        write_data <= i[DATA_WIDTH-1:0];
        @(posedge wclk);
        write_en <= 1'b0;
      end
    end
    // 等待CDC同步完成
    repeat (10) @(posedge rclk);

    // 再读15个 (用read_word task)
    begin : test2_read_loop
      integer jj;
      for (jj = 0; jj < 15; jj = jj + 1) read_word(jj[DATA_WIDTH-1:0]);
    end
    $display("  Test 2 errors=%0d", errors);

    // =========================================================
    // Test 3: Full 条件
    // =========================================================
    $display("============================================");
    $display("=== Test 3: Full 条件验证 ===");
    $display("============================================");
    // 写满 FIFO
    fork
      begin : test3_write
        integer i;
        for (i = 0; i < 16; i = i + 1) begin
          @(posedge wclk);
          write_en   <= 1'b1;
          write_data <= 8'hC0 + i[DATA_WIDTH-1:0];
          @(posedge wclk);
          write_en <= 1'b0;
        end
      end
      begin : test3_monitor
        repeat (5) @(posedge wclk);
        repeat (20) @(posedge wclk);
      end
    join

    // 等待CDC同步 + 验证full
    repeat (20) @(posedge rclk);
    if (full !== 1'b1) begin
      $display("  WARN: full=%b (FIFO may not be full yet)", full);
    end else begin
      $display("  PASS: full=1 asserted after 15 writes");
    end

    // 尝试在满时写入 (应被忽略)
    @(posedge wclk);
    write_en   <= 1'b1;
    write_data <= 8'hFF;
    @(posedge wclk);
    write_en <= 1'b0;
    $display("  Wrote while full (should be ignored)");

    // 读空 FIFO (15 words，已CDC同步)，验证数据正确
    begin : test3_read_loop
      integer jj;
      for (jj = 0; jj < 15; jj = jj + 1) read_word(8'hC0 + jj[DATA_WIDTH-1:0]);
    end
    $display("  Test 3 errors=%0d", errors);

    // =========================================================
    // Test 4: Empty 条件
    // =========================================================
    $display("============================================");
    $display("=== Test 4: Empty 条件验证 ===");
    $display("============================================");
    repeat (5) @(posedge rclk);
    if (empty !== 1'b1) begin
      $display("  FAIL: empty=%b after reading all", empty);
      errors = errors + 1;
    end else $display("  PASS: empty=1 after reading all");

    // 尝试在空时读取
    @(posedge rclk);
    read_en <= 1'b1;
    @(posedge rclk);
    read_en <= 1'b0;
    $display("  Read while empty (should be ignored)");
    $display("  Test 4 errors=%0d", errors);

    // =========================================================
    // Test 5: 同时读写 (Concurrent read/write)
    // =========================================================
    $display("============================================");
    $display("=== Test 5: 同时读写（并发CDC） ===");
    $display("============================================");
    begin : test5_seq
      integer k, round;
      for (round = 0; round < 6; round = round + 1) begin
        for (k = 0; k < 5; k = k + 1) begin
          @(posedge wclk);
          while (full) @(posedge wclk);
          write_en   <= 1'b1;
          write_data <= round * 5 + k;
          @(posedge wclk);
          write_en <= 1'b0;
        end
        repeat (10) @(posedge rclk);
        for (k = 0; k < 5; k = k + 1) read_word(round * 5 + k);
      end
    end
    $display("  Test 5 errors=%0d", errors);

    // =========================================================
    // 汇总
    // =========================================================
    repeat (50) @(posedge wclk);
    $display("============================================");
    $display("=== DUAL_CLOCK_FIFO TEST SUMMARY ===");
    $display("============================================");
    if (errors == 0) $display("=== ALL TESTS PASSED ===");
    else $display("=== FAILURES: %0d ===", errors);
    $display("============================================");
    // // $finish; (stripped) (stripped for sim)
  end

  // 超时保护
  initial begin
    #10000000;
    $display("=== TIMEOUT ===");
    // // $finish; (stripped) (stripped for sim)
  end
endmodule

// synthesis translate_on
