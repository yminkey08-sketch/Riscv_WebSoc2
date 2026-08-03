//****************************************Copyright 2013[c]************************//
// ************************Declaration***************************************//
// File name:        single_clock_fifo					                                       //
// Author:           huaming.huang@link-real.com.cn                                    //
// Date:             2010-12-23 00:00 	                                     //
// Version Number:   1.0                                                     //
// Abstract:         synchronizing fifo design
//                                                                            //
// Modification history:[including time, version, author and abstract]        //
// 2010-12-23 00:00        version 1.0     xxx                                //
// Abstract: Initial                                                          //
//                                                                     //
// *********************************end************************************** //

`include "define.sv"

module single_clock_fifo (
    clk,
    reset_l,
    //write
    write_en,
    write_data,
    full,
    //read
    read_en,
    read_data,
    empty
);
  parameter addr_width = 4;
  parameter data_width = 8;
  parameter ram_type = "registers";
  localparam mem_depth = 2 ** addr_width;  // Cyclone IV device : "M9K","registers"

  input clk;
  input reset_l;

  input write_en;
  input [data_width-1:0] write_data;
  output full;
  input read_en;
  output [data_width-1:0] read_data;
  output empty;

  //reg define
  reg  [addr_width-1:0] write_no_i;
  wire [addr_width-1:0] next_write_no;
  reg  [addr_width-1:0] read_no_i;
  wire                  wr_en;
  wire                  rd_en;
  reg                   full;
  reg  [data_width-1:0] read_data;
  reg                   empty;
`ifdef IS_XILINX
  (* ram_style = `SMALL_RAM *)
`endif
`ifdef IS_INTEL
  (* ramstyle = `SMALL_RAM *)
`endif
  reg [data_width-1:0] mem_array[mem_depth-1:0];

  /*******************************************************************************************************
**                              Main Program
**
********************************************************************************************************/
  assign wr_en = ((write_en == 1'b1) && (full == 1'b0)) ? 1'b1 : 1'b0;
  assign rd_en = ((read_en == 1'b1) && (empty == 1'b0)) ? 1'b1 : 1'b0;

  always_comb
    if (write_no_i == read_no_i) begin
      empty = 1'b1;
    end else begin
      empty = 1'b0;
    end
  assign next_write_no = write_no_i + 1;
  always_comb
    if (next_write_no == read_no_i) begin
      full = 1'b1;
    end else begin
      full = 1'b0;
    end

  always @(negedge reset_l or posedge clk)
    if (reset_l == 1'b0) begin
      write_no_i <= 0;
      read_no_i  <= 0;
    end else begin
      if (wr_en == 1'b1) begin
        write_no_i <= write_no_i + 1;
        mem_array[write_no_i] <= write_data;
      end
      if (rd_en == 1'b1) begin
        read_no_i <= read_no_i + 1;
        read_data <= mem_array[read_no_i];
      end
    end
endmodule


// synthesis translate_off

module tb_single_clock_fifo ();

  // ============================================================
  // Tasks
  // ============================================================
  task write_word;
    input [DATA_WIDTH-1:0] wdata;
    begin
      @(posedge clk);
      while (full) @(posedge clk);
      write_en   <= 1'b1;
      write_data <= wdata;
      @(posedge clk);
      write_en <= 1'b0;
    end
  endtask

  task read_word;
    input [DATA_WIDTH-1:0] exp_data;
    begin
      @(posedge clk);
      while (empty) @(posedge clk);
      read_en <= 1'b1;
      @(posedge clk);  // DUT sees read_en, read_data captured in register
      read_en <= 1'b0;
      #1;
      if (read_data !== exp_data) begin
        $display("  FAIL: read_data=%h expected=%h", read_data, exp_data);
        errors = errors + 1;
      end
    end
  endtask

  localparam ADDR_WIDTH = 4;
  localparam DATA_WIDTH = 8;

  reg                      clk;
  reg                      reset_l;
  reg                      write_en;
  reg     [DATA_WIDTH-1:0] write_data;
  wire                     full;
  reg                      read_en;
  wire    [DATA_WIDTH-1:0] read_data;
  wire                     empty;

  integer                  errors;

  single_clock_fifo #(
      .addr_width(ADDR_WIDTH),
      .data_width(DATA_WIDTH),
      .ram_type  ("registers")
  ) u_dut (
      .clk       (clk),
      .reset_l   (reset_l),
      .write_en  (write_en),
      .write_data(write_data),
      .full      (full),
      .read_en   (read_en),
      .read_data (read_data),
      .empty     (empty)
  );

  // ============================================================
  // 时钟 (50MHz)
  // ============================================================
  always #10 clk = ~clk;

  // ============================================================
  // 波形
  // ============================================================
  initial begin
    $dumpfile("tb_single_clock_fifo.vcd");
    $dumpvars(0, tb_single_clock_fifo);
  end

  // ============================================================
  // Test main
  // ============================================================
  initial begin
    clk        = 1'b0;
    reset_l    = 1'b0;
    write_en   = 1'b0;
    write_data = 0;
    read_en    = 1'b0;
    errors     = 0;

    #100 reset_l = 1'b1;
    repeat (10) @(posedge clk);

    // Test 0: 初始状态
    $display("============================================");
    $display("=== Test 0: 复位后初始状态 ===");
    $display("============================================");
    if (empty !== 1'b1) begin
      $display("  FAIL: empty=%b after reset", empty);
      errors = errors + 1;
    end else $display("  PASS: empty=1");
    if (full !== 1'b0) begin
      $display("  FAIL: full=%b after reset", full);
      errors = errors + 1;
    end else $display("  PASS: full=0");

    // Test 1: 单word写读
    $display("============================================");
    $display("=== Test 1: 单word写读 ===");
    $display("============================================");
    write_word(8'hA5);
    read_word(8'hA5);
    $display("  Test 1 errors=%0d", errors);

    // Test 2: 连续写读 (15 words)
    $display("============================================");
    $display("=== Test 2: 连续写读 (15 words) ===");
    $display("============================================");
    begin : test2_loop
      integer i;
      for (i = 0; i < 15; i = i + 1) write_word(i[DATA_WIDTH-1:0]);
      for (i = 0; i < 15; i = i + 1) read_word(i[DATA_WIDTH-1:0]);
    end
    $display("  Test 2 errors=%0d", errors);

    // Test 3: Full 条件
    $display("============================================");
    $display("=== Test 3: Full 条件 ===");
    $display("============================================");
    begin : test3_write_loop
      integer i;
      for (i = 0; i < 15; i = i + 1) write_word(8'hC0 + i[DATA_WIDTH-1:0]);
    end
    repeat (5) @(posedge clk);
    if (full !== 1'b1) begin
      $display("  WARN: full=%b", full);
    end else $display("  PASS: full=1 after 15 writes");

    // 写满后再写 (应忽略)
    @(posedge clk);
    write_en   <= 1'b1;
    write_data <= 8'hFF;
    @(posedge clk);
    write_en <= 1'b0;
    $display("  Write-while-full done");

    // 读空
    begin : test3_read_loop
      integer i;
      for (i = 0; i < 15; i = i + 1) read_word(8'hC0 + i[DATA_WIDTH-1:0]);
    end
    $display("  Test 3 errors=%0d", errors);

    // Test 4: Empty 条件
    $display("============================================");
    $display("=== Test 4: Empty 条件 ===");
    $display("============================================");
    repeat (3) @(posedge clk);
    if (empty !== 1'b1) begin
      $display("  FAIL: empty=%b", empty);
      errors = errors + 1;
    end else $display("  PASS: empty=1");

    @(posedge clk);
    read_en <= 1'b1;
    @(posedge clk);
    read_en <= 1'b0;
    $display("  Read-while-empty done");
    $display("  Test 4 errors=%0d", errors);

    // Test 5: 环形缓冲 (write/read交替)
    $display("============================================");
    $display("=== Test 5: 环形缓冲 ===");
    $display("============================================");
    begin : test5_loop
      integer i;
      for (i = 0; i < 5; i = i + 1) write_word(i[DATA_WIDTH-1:0]);
      for (i = 0; i < 3; i = i + 1) read_word(i[DATA_WIDTH-1:0]);
      for (i = 5; i < 10; i = i + 1) write_word(i[DATA_WIDTH-1:0]);
      for (i = 3; i < 10; i = i + 1) read_word(i[DATA_WIDTH-1:0]);
    end
    $display("  Test 5 errors=%0d", errors);

    // Summary
    repeat (20) @(posedge clk);
    $display("============================================");
    $display("=== SUMMARY ===");
    $display("============================================");
    if (errors == 0) $display("=== ALL TESTS PASSED ===");
    else $display("=== FAILURES: %0d ===", errors);
    // // $finish; (stripped) (stripped for sim)
  end

  initial begin
    #10000000;
    $display("=== TIMEOUT ===");
    // // $finish; (stripped) (stripped for sim)
  end
endmodule

// synthesis translate_on
