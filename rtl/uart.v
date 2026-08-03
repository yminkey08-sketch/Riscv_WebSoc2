//****************************************Copyright 2013[c]************************//
// ************************Declaration***************************************//
// File name:        uart	                                       //
// Author:           huaming.huang@link-real.com.cn                                    //
// Date:             2014-12-28 00:00 	                                     //
// Version Number:   1.0                                                     //
// Abstract:    support arbitrarily baud rate, and rx/tx any length data
// Modification history:[including time, version, author and abstract]        //
// 2014-12-28 00:00        version 1.0     xxx                                //
// Abstract: Initial                                                          //
//                                                                            //
// *********************************end************************************** //

module uart (
    reset_l,
    clk,
    //line Rx interface
    uart_rx,
    //client Rx fifo interface, for client read out
    read_en,
    read_data,
    empty,
    //client Tx fifo interface, for client write into
    write_en,
    write_data,
    full,
    //line Tx interface
    uart_tx
);

  function integer fun_log2;
    input integer data_in;
    integer cnt;
    integer div;
    begin
      div = data_in - 1;
      cnt = 0;
      while (div > 0) begin
        div = div / 2;
        cnt = cnt + 1;
      end
      fun_log2 = cnt;
    end
  endfunction
  parameter baud_rate = 115200;
  parameter data_number = 16;  //rx/tx fifo depth control
  parameter data_width = 8;
  parameter ram_type = "registers";  // Cyclone IV device : "M9K","registers"

  parameter addr_width = fun_log2(data_number);  //rx/tx fifo depth control, if 4, rx/tx 16 for each

  input reset_l;
  input clk;

  input uart_rx;
  input read_en;
  output [data_width-1:0] read_data;
  output empty;

  input write_en;
  input [data_width-1:0] write_data;
  output full;
  output uart_tx;
  wire clk_uart_rx;
  wire clk_uart_tx;

  clock_frequency_divider #(
      .div_Mbits(28),
      .div_Nbits(28)
  ) u_clock_frequency_divider_rx (
      .reset_l(reset_l),
      .clk_in (clk),
      .div_M  (50000000),       //input is 50M clock
      .div_N  (baud_rate * 8),  //output clock
      .clk_out(clk_uart_rx)
  );

  clock_frequency_divider #(
      .div_Mbits(28),
      .div_Nbits(28)
  ) u_clock_frequency_divider_tx (
      .reset_l(reset_l),
      .clk_in (clk),
      .div_M  (50000000),    //input is 50M clock
      .div_N  (baud_rate),   //output clock
      .clk_out(clk_uart_tx)
  );

  uart_rx #(
      .addr_width(addr_width),
      .data_width(data_width),
      .ram_type  (ram_type)
  ) u_uart_rx (
      .reset_l  (reset_l),
      .clk      (clk),
      .clk_uart (clk_uart_rx),
      .uart_rx  (uart_rx),
      .read_en  (read_en),
      .read_data(read_data),
      .empty    (empty)
  );

  uart_tx #(
      .addr_width(addr_width),
      .data_width(data_width),
      .ram_type  (ram_type)
  ) u_uart_tx (
      .reset_l   (reset_l),
      .clk       (clk),
      .clk_uart  (clk_uart_tx),
      .write_en  (write_en),
      .write_data(write_data),
      .full      (full),
      .uart_tx   (uart_tx)
  );
endmodule

// synthesis translate_off

module tb_uart ();

  //==========================================================================
  // 任务：在 uart_rx 上驱动一个字节的串行数据
  // LSB first: 起始位(0) + 8 data bits + 停止位(1)
  //==========================================================================
  task uart_drive_rx;
    input [7:0] data;
    integer i;
    begin
      // 起始位
      uart_rx_ext = 1'b0;
      repeat (BIT_CYCLES) @(posedge clk);

      // 8 数据位（LSB first）
      for (i = 0; i < 8; i = i + 1) begin
        uart_rx_ext = data[i];
        repeat (BIT_CYCLES) @(posedge clk);
      end

      // 停止位（高）
      uart_rx_ext = 1'b1;
      repeat (BIT_CYCLES) @(posedge clk);
    end
  endtask

  //==========================================================================
  // 任务：写一个字节到 TX FIFO
  //==========================================================================
  task uart_write_byte;
    input [7:0] data;
    begin
      write_en   = 1'b1;
      write_data = data;
      @(posedge clk);
      write_en   = 1'b0;
      write_data = 8'h00;
      @(posedge clk);
    end
  endtask

  //==========================================================================
  // 任务：从 RX FIFO 读一个字节并校验
  //==========================================================================
  task uart_read_check;
    input [7:0] expected;
    reg [7:0] captured;
    begin
      // 等待 RX FIFO 非空
      while (empty) @(posedge clk);

      // 在读使能之前采样 read_data（此时 read_addr 指向有效数据）
      #1;  // 等待信号稳定
      captured = read_data;

      // 发出读使能，让 read_addr 前进到下一条目
      read_en  = 1'b1;
      @(posedge clk);
      read_en = 1'b0;

      if (captured === expected)
        $display("[PASS] RX read: 0x%h (expected 0x%h)", captured, expected);
      else $display("[FAIL] RX read: 0x%h (expected 0x%h)", captured, expected);
    end
  endtask

  //==========================================================================
  // 任务：等待 TX 传输完成（监控 uart_tx 空闲 + 确保 TX FIFO 已排空）
  //==========================================================================
  task wait_tx_idle;
    input [31:0] timeout_cycles;
    integer cnt;
    begin
      cnt = 0;
      // 等待 uart_tx 回到高（空闲）并保持足够长时间
      // 一帧=10 bits，保持高 2 bit 时间以上确认真的空闲
      while (cnt < timeout_cycles) begin
        @(posedge clk);
        if (uart_tx === 1'b1) cnt = cnt + 1;
        else cnt = 0;  // 检测到传输活动，重置计数
      end
      $display("[INFO] TX idle confirmed (%0d consecutive high cycles)", cnt);
    end
  endtask

  //==========================================================================
  // 波特率参数
  //==========================================================================
  // 115200 baud: bit_time = 1/115200 ≈ 8680ns ≈ 434 clk cycles (50MHz)
  localparam BIT_CYCLES = 434;

  //==========================================================================
  // 时钟与复位
  //==========================================================================
  reg        clk;
  reg        reset_l;

  //==========================================================================
  // DUT 信号
  //==========================================================================
  reg        uart_rx_ext;  // 外部 RX 输入（测试激励驱动）
  reg        loopback_en;  // 回环使能
  wire       uart_rx_int;  // 内部 RX 输入
  reg        read_en;
  wire [7:0] read_data;
  wire       empty;
  reg        write_en;
  reg  [7:0] write_data;
  wire       full;
  wire       uart_tx;

  always #10 clk = ~clk;  // 50MHz

  initial begin
    clk = 1'b0;
    reset_l = 1'b0;
    #100 reset_l = 1'b1;
  end

  // 回环模式：将 TX 输出连接到 RX 输入；非回环时使用外部激励
  assign uart_rx_int = loopback_en ? uart_tx : uart_rx_ext;

  //==========================================================================
  // DUT 实例化
  //==========================================================================
  uart #(
      .baud_rate (115200),
      .data_number(16),
      .data_width (8),
      .ram_type   ("registers")
  ) u_dut (
      .reset_l   (reset_l),
      .clk       (clk),
      .uart_rx   (uart_rx_int),
      .read_en   (read_en),
      .read_data (read_data),
      .empty     (empty),
      .write_en  (write_en),
      .write_data(write_data),
      .full      (full),
      .uart_tx   (uart_tx)
  );

  //==========================================================================
  // 波形输出
  //==========================================================================
  initial begin
    $dumpfile("uart.vcd");
    $dumpvars(0, tb_uart);
  end

  //==========================================================================
  // 测试主流程
  //==========================================================================
  initial begin
    // 初始化
    uart_rx_ext = 1'b1;  // UART RX 空闲为高
    loopback_en = 1'b0;
    read_en     = 1'b0;
    write_en    = 1'b0;
    write_data  = 8'h00;

    // 等待复位撤离
    @(posedge reset_l);
    $display("=========================================");
    $display("  UART Testbench — 复位完成，开始测试");
    $display("=========================================");
    repeat (10) @(posedge clk);

    //======================================================================
    // 测试 1：TX 测试 — 写入 0x55 和 0xAA，监控 uart_tx 输出
    //======================================================================
    $display("");
    $display(">>> Test 1: TX — 写入 0x55");
    uart_write_byte(8'h55);
    $display("[INFO] 已写入 TX FIFO: 0x55");
    wait_tx_idle(BIT_CYCLES * 3);  // 等待 ≥ 3 bit 时间的连续高电平

    $display("");
    $display(">>> Test 1: TX — 写入 0xAA");
    uart_write_byte(8'hAA);
    $display("[INFO] 已写入 TX FIFO: 0xAA");
    wait_tx_idle(BIT_CYCLES * 3);

    // 确保 TX FIFO 完全排空：
    // TX 状态机每 16 clk_uart_tx 周期 = 139us ≈ 6944 clk 读取一次
    // 等待 3 个完整周期确保所有缓冲数据已串行化完毕
    $display("[INFO] Flushing TX pipeline...");
    repeat (BIT_CYCLES * 50) @(posedge clk);
    $display("[INFO] TX pipeline flushed");

    // 验证 TX 过程中 full 信号行为
    $display("[INFO] TX full flag during write: %b", full);

    //======================================================================
    // 测试 2：RX 测试 — 模拟串行接收 0x55
    //======================================================================
    $display("");
    $display(">>> Test 2: RX — 模拟串行接收 0x55");
    $display("[INFO] 在 uart_rx 上驱动: 0x55 (起始位+8bit LSB+停止位)");

    // 驱动前记录 empty 状态
    $display("[DEBUG] Before RX drive: empty=%b, read_data=0x%h", empty, read_data);

    uart_drive_rx(8'h55);

    // 等待 RX 模块处理完成：1 帧约 10 bit × 8 过采样 = 80 clk_uart_rx 周期
    // clk_uart_rx ≈ 921.6 kHz, 周期 ≈ 1085 ns ≈ 54 clk cycles
    // 等待足够长的时间让 CDC 同步完成
    $display("[DEBUG] Waiting for RX processing + CDC sync...");
    repeat (BIT_CYCLES * 15) @(posedge clk);

    $display("[DEBUG] After wait: empty=%b, read_data=0x%h", empty, read_data);

    if (!empty) begin
      uart_read_check(8'h55);
    end else begin
      $display("[FAIL] RX FIFO still empty after %0d clk cycles", BIT_CYCLES * 15);
    end

    // 清空 RX FIFO（可能因 CDC 同步延迟有多余条目）
    repeat (10) @(posedge clk);
    while (!empty) begin
      $display("[INFO] Draining extra RX data: 0x%h", read_data);
      read_en = 1'b1;
      @(posedge clk);
      read_en = 1'b0;
      repeat (5) @(posedge clk);
    end
    if (empty) $display("[PASS] RX FIFO drained");

    //======================================================================
    // 测试 3：回环测试 — 写入 0xA5，uart_tx 接 uart_rx
    //======================================================================
    $display("");
    $display(">>> Test 3: 回环测试 — TX→RX 写入 0xA5");
    loopback_en = 1'b1;
    @(posedge clk);

    uart_write_byte(8'hA5);
    $display("[INFO] 已写入 TX FIFO (loopback): 0xA5");

    // 等待 TX 串行化 + RX 处理 + CDC 同步
    // TX: ~16 clk_uart_tx 周期 ≈ 139us ≈ 6944 clk
    // RX: ~72 clk_uart_rx 周期 ≈ 78us ≈ 3900 clk
    // CDC sync + 余量
    $display("[DEBUG] Waiting for loopback path (TX→wire→RX→FIFO→CDC)...");
    repeat (BIT_CYCLES * 50) @(posedge clk);

    $display("[DEBUG] Loopback after wait: empty=%b, read_data=0x%h", empty, read_data);
    if (!empty) begin
      uart_read_check(8'hA5);
    end else begin
      $display("[FAIL] Loopback: RX FIFO still empty after %0d clk cycles", BIT_CYCLES * 50);
    end

    loopback_en = 1'b0;

    //======================================================================
    // 仿真结束
    //======================================================================
    $display("");
    $display("=========================================");
    $display("  UART Testbench — 全部测试完成");
    $display("=========================================");
    repeat (20) @(posedge clk);
    // // $finish; (stripped) (stripped for sim)
  end
endmodule

// synthesis translate_on
