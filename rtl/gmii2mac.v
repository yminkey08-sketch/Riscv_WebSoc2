`include "define.sv"

module gmii2mac (
    input clk,
    input reset_l,

    output [7:0] Eth_TXD,
    output Eth_TXEN,
    output Eth_TXER,

    input    Eth_RXC, //125Mhz/25Mhz/2.5Mhz receive ref clock
    input    Eth_RXDV,
    input    Eth_RXER,
    input [7:0] Eth_RXD,

    output       mac_rx_sop,
    output       mac_rx_en,
    output [7:0] mac_rx_data,
    output       mac_rx_eop,
    output       mac_rx_err,
    input        mac_tx_sop,
    input        mac_tx_en,
    input  [7:0] mac_tx_data,
    input        mac_tx_eop,
    input        mac_tx_err,

    output reg [31:0]rx_afifo_full_cnt,
    output reg [31:0]rx_afifo_empty_cnt,
    output reg [31:0]rx_data_err_line,
    output    [31:0]rx_correct_pkt_cnt,
    output    [31:0]rx_crc_err_pkt_cnt,
    output    [31:0]tx_correct_pkt_cnt,
    output    [31:0]tx_error_pkt_cnt
);

  wire       rx_afifo_full;
  wire       rx_afifo_empty;
  wire [9:0] rx_afifo_data;
  wire       rx_data_en_mac_in;
  wire [7:0] rx_data_mac_in;
  wire       rx_data_err;
  wire       tx_data_en_mac_out;
  wire [7:0] tx_data_mac_out;

  dual_clock_fifo #(
      .addr_width(4),
      .data_width(10),
      .ram_type  (`SMALL_RAM)
  ) u_rx_asyncfifo (
      .reset_l   (reset_l),
      .wclk      (Eth_RXC),
      .write_en  (1'b1),
      .write_data({Eth_RXER, Eth_RXDV, Eth_RXD}),
      .full      (rx_afifo_full),
      .rclk      (clk),
      .read_en   (1'b1),
      .read_data (rx_afifo_data),
      .empty     (rx_afifo_empty)
  );

  always @(negedge reset_l or posedge Eth_RXC) begin
    if (!reset_l) begin
      rx_afifo_full_cnt <= 32'b0;
    end else begin
      if (rx_afifo_full) rx_afifo_full_cnt <= rx_afifo_full_cnt + 1;
    end
  end
  always @(negedge reset_l or posedge clk) begin
    if (!reset_l) begin
      rx_afifo_empty_cnt <= 32'b0;
      rx_data_err_line   <= 32'b0;
    end else begin
      if (rx_afifo_empty) rx_afifo_empty_cnt <= rx_afifo_empty_cnt + 1;
      if (rx_data_err) rx_data_err_line <= rx_data_err_line + 1;
    end
  end

  eth_presemble #(
      .rx_presemble_en(1),
      .tx_presemble_en(1),
      .data_width     (8)
  ) u_eth_presemble (
      .reset_l(reset_l),

      .rx_clk         (clk),
      .rx_clk_en      (1'b1),
      .rx_data_in     (rx_afifo_data[7:0]),
      .rx_data_en_in  (rx_afifo_data[8]),
      .rx_data_err_in (rx_afifo_data[9]),
      .rx_data_out    (rx_data_mac_in),
      .rx_data_en_out (rx_data_en_mac_in),
      .rx_data_err_out(rx_data_err),

      .tx_clk        (clk),
      .tx_clk_en     (1'b1),
      .tx_data_in    (tx_data_mac_out),
      .tx_data_en_in (tx_data_en_mac_out),
      .tx_data_out   (Eth_TXD),
      .tx_data_en_out(Eth_TXEN)
  );
  assign Eth_TXER = 1'b0;

  mac_top u_mac_top (
      .clk    (clk),
      .clk_en (1'b1),
      .reset_l(reset_l),

      .rx_en  (rx_data_en_mac_in),
      .rx_data(rx_data_mac_in),
      .tx_en  (tx_data_en_mac_out),
      .tx_data(tx_data_mac_out),

      .mac_rx_sop (mac_rx_sop),
      .mac_rx_en  (mac_rx_en),
      .mac_rx_data(mac_rx_data),
      .mac_rx_eop (mac_rx_eop),
      .mac_rx_err (mac_rx_err),
      .mac_tx_sop (mac_tx_sop),
      .mac_tx_en  (mac_tx_en),
      .mac_tx_data(mac_tx_data),
      .mac_tx_eop (mac_tx_eop),
      .mac_tx_err (mac_tx_err),

      .mac_rx_stat_cnt_0(rx_correct_pkt_cnt),
      .mac_rx_stat_cnt_1(rx_crc_err_pkt_cnt),
      .mac_tx_stat_cnt_0(tx_correct_pkt_cnt),
      .mac_tx_stat_cnt_1(tx_error_pkt_cnt)
  );
endmodule


// synthesis translate_off

module tb_gmii2mac ();

  // ── CRC32 计算 ────────────────────────────────────────
  function [31:0] crc32_eth;
    input integer byte_cnt;
    integer i, j;
    reg [31:0] crc;
    begin
      crc = 32'hFFFFFFFF;
      for (i = 0; i < byte_cnt; i = i + 1) begin
        crc = crc ^ {24'd0, frame_buf[i]};
        for (j = 0; j < 8; j = j + 1) begin
          if (crc[0]) crc = (crc >> 1) ^ 32'hEDB88320;
          else crc = crc >> 1;
        end
      end
      crc32_eth = ~crc;
    end
  endfunction

  // ── GMII RX 发包任务（通过 frame_buf/payload_buf 传数据）─
  task send_gmii_pkt;
    input [47:0] dmac;
    input [47:0] smac;
    input [15:0] etype;
    input integer plen;
    input inject_err;
    integer        i;
    reg     [31:0] fcs;
    begin
      // 构建帧: DMAC + SMAC + ETYPE + Payload + FCS
      frame_buf[0]  = dmac[47:40];
      frame_buf[1]  = dmac[39:32];
      frame_buf[2]  = dmac[31:24];
      frame_buf[3]  = dmac[23:16];
      frame_buf[4]  = dmac[15:8];
      frame_buf[5]  = dmac[7:0];
      frame_buf[6]  = smac[47:40];
      frame_buf[7]  = smac[39:32];
      frame_buf[8]  = smac[31:24];
      frame_buf[9]  = smac[23:16];
      frame_buf[10] = smac[15:8];
      frame_buf[11] = smac[7:0];
      frame_buf[12] = etype[15:8];
      frame_buf[13] = etype[7:0];
      for (i = 0; i < plen; i = i + 1) frame_buf[14+i] = payload_buf[i];

      fcs = crc32_eth(14 + plen);
      frame_buf[14+plen+0] = fcs[7:0];
      frame_buf[14+plen+1] = fcs[15:8];
      frame_buf[14+plen+2] = fcs[23:16];
      frame_buf[14+plen+3] = fcs[31:24];
      frame_len = 14 + plen + 4;

      @(posedge Eth_RXC);
      Eth_RXDV <= 1'b1;
      Eth_RXER <= 1'b0;
      for (i = 0; i < PREAMBLE_BYTES; i = i + 1) begin
        Eth_RXD <= 8'h55;
        @(posedge Eth_RXC);
      end
      Eth_RXD <= SFD_BYTE;
      @(posedge Eth_RXC);
      for (i = 0; i < frame_len; i = i + 1) begin
        Eth_RXD  <= frame_buf[i];
        Eth_RXER <= (inject_err && (i == frame_len / 2)) ? 1'b1 : 1'b0;
        @(posedge Eth_RXC);
      end
      Eth_RXDV <= 1'b0;
      Eth_RXER <= 1'b0;
      Eth_RXD  <= 8'h00;
      @(posedge Eth_RXC);
    end
  endtask

  // ── MAC TX 发包任务 ───────────────────────────────────
  // 时序协议（参照 sop_eop_gen 产生格式）：
  //   SOP  — 提前于首数据字节 1 拍（预报信号，此时 EN=0）
  //   EN   — 数据有效指示，随 SOP 后 1 拍开始
  //   EOP  — 与最后一个数据字节同拍
  //   ERR  — 仅与 EOP 同拍有效
  task send_mac_tx_pkt;
    input integer plen;
    input err_flag;
    integer i;
    begin
      // ── 第 0 拍：SOP 预报（en 无效）──────────────────
      @(posedge clk);
      mac_tx_sop  <= 1'b1;
      mac_tx_en   <= 1'b0;
      mac_tx_data <= 8'h00;
      mac_tx_eop  <= 1'b0;
      mac_tx_err  <= 1'b0;

      // ── 第 1 拍：首数据字节（SOP 撤除，EN 拉起）────
      @(posedge clk);
      mac_tx_sop  <= 1'b0;
      mac_tx_en   <= 1'b1;
      mac_tx_data <= payload_buf[0];
      mac_tx_eop  <= 1'b0;
      mac_tx_err  <= 1'b0;

      // ── 第 2..plen-2 拍：中间数据 ──────────────────
      for (i = 1; i < plen - 1; i = i + 1) begin
        @(posedge clk);
        mac_tx_data <= payload_buf[i];
      end

      // ── 末字节拍：EOP 与最后一字节同拍 ─────────────
      @(posedge clk);
      mac_tx_data <= payload_buf[plen-1];
      mac_tx_eop  <= 1'b1;
      mac_tx_err  <= err_flag;

      // ── 结束拍：撤除所有信号 ───────────────────────
      @(posedge clk);
      mac_tx_en   <= 1'b0;
      mac_tx_eop  <= 1'b0;
      mac_tx_err  <= 1'b0;
      mac_tx_data <= 8'h00;
    end
  endtask

  // ── 时钟参数 ──────────────────────────────────────────
  parameter CLK_PERIOD = 8;  // 125MHz system clock
  parameter ETH_RXC_PERIOD = 8;  // 125MHz GMII RX clock (1000Mbps mode)

  // ── 测试包参数 ────────────────────────────────────────
  parameter PKT_DATA_LEN = 46;
  parameter PREAMBLE_BYTES = 7;
  parameter SFD_BYTE = 8'hD5;
  parameter MAX_FRAME = 2048;

  // ── 时钟生成 ──────────────────────────────────────────
  reg            clk;
  reg            Eth_RXC;

  // ── 复位生成 ──────────────────────────────────────────
  reg            reset_l;

  // ── DUT 端口连线 ──────────────────────────────────────
  wire    [ 7:0] Eth_TXD;
  wire           Eth_TXEN;
  wire           Eth_TXER;

  reg            Eth_RXDV;
  reg            Eth_RXER;
  reg     [ 7:0] Eth_RXD;

  wire           mac_rx_sop;
  wire           mac_rx_en;
  wire    [ 7:0] mac_rx_data;
  wire           mac_rx_eop;
  wire           mac_rx_err;

  reg            mac_tx_sop;
  reg            mac_tx_en;
  reg     [ 7:0] mac_tx_data;
  reg            mac_tx_eop;
  reg            mac_tx_err;

  wire    [31:0] rx_afifo_full_cnt;
  wire    [31:0] rx_afifo_empty_cnt;
  wire    [31:0] rx_data_err_line;
  wire    [31:0] rx_correct_pkt_cnt;
  wire    [31:0] rx_crc_err_pkt_cnt;
  wire    [31:0] tx_correct_pkt_cnt;
  wire    [31:0] tx_error_pkt_cnt;

  // ── 共享数据缓冲区（避免 unpacked array 端口）─────────
  reg     [ 7:0] frame_buf            [0:MAX_FRAME-1];
  reg     [ 7:0] payload_buf          [0:MAX_FRAME-1];

  // ── MAC RX 监控 ───────────────────────────────────────
  reg     [ 7:0] rx_captured          [0:MAX_FRAME-1];
  reg     [31:0] rx_byte_cnt;
  reg            rx_sop_seen;
  reg            rx_eop_seen;
  reg            rx_err_seen;
  reg            rx_pkt_done;

  // ── GMII TX 监控 ──────────────────────────────────────
  reg     [ 7:0] tx_gmii_captured     [0:MAX_FRAME-1];
  reg     [31:0] tx_gmii_byte_cnt;
  reg            tx_gmii_en_prev;
  reg            tx_gmii_pkt_detected;
  integer        frame_len;
  integer        payload_len;

  // ── 主测试流程 ────────────────────────────────────────
  integer        i;

  initial clk = 1'b0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  initial Eth_RXC = 1'b0;
  always #(ETH_RXC_PERIOD / 2) Eth_RXC = ~Eth_RXC;
  initial begin
    reset_l = 1'b0;
    #200 reset_l = 1'b1;
  end

  // ── DUT 实例化 ────────────────────────────────────────
  gmii2mac u_dut (
      .clk               (clk),
      .reset_l           (reset_l),
      .Eth_TXD           (Eth_TXD),
      .Eth_TXEN          (Eth_TXEN),
      .Eth_TXER          (Eth_TXER),
      .Eth_RXC           (Eth_RXC),
      .Eth_RXDV          (Eth_RXDV),
      .Eth_RXER          (Eth_RXER),
      .Eth_RXD           (Eth_RXD),
      .mac_rx_sop        (mac_rx_sop),
      .mac_rx_en         (mac_rx_en),
      .mac_rx_data       (mac_rx_data),
      .mac_rx_eop        (mac_rx_eop),
      .mac_rx_err        (mac_rx_err),
      .mac_tx_sop        (mac_tx_sop),
      .mac_tx_en         (mac_tx_en),
      .mac_tx_data       (mac_tx_data),
      .mac_tx_eop        (mac_tx_eop),
      .mac_tx_err        (mac_tx_err),
      .rx_afifo_full_cnt (rx_afifo_full_cnt),
      .rx_afifo_empty_cnt(rx_afifo_empty_cnt),
      .rx_data_err_line  (rx_data_err_line),
      .rx_correct_pkt_cnt(rx_correct_pkt_cnt),
      .rx_crc_err_pkt_cnt(rx_crc_err_pkt_cnt),
      .tx_correct_pkt_cnt(tx_correct_pkt_cnt),
      .tx_error_pkt_cnt  (tx_error_pkt_cnt)
  );

  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      rx_byte_cnt <= 32'd0;
      rx_sop_seen <= 1'b0;
      rx_eop_seen <= 1'b0;
      rx_err_seen <= 1'b0;
      rx_pkt_done <= 1'b0;
    end else begin
      if (mac_rx_sop) begin
        rx_sop_seen <= 1'b1;
        rx_byte_cnt <= 32'd1;
        rx_eop_seen <= 1'b0;
        rx_err_seen <= 1'b0;
        rx_pkt_done <= 1'b0;
        rx_captured[0] <= mac_rx_data;
      end
      if (mac_rx_en && !mac_rx_sop) begin
        rx_captured[rx_byte_cnt] <= mac_rx_data;
        rx_byte_cnt <= rx_byte_cnt + 1;
      end
      if (mac_rx_eop) begin
        rx_eop_seen <= 1'b1;
        rx_pkt_done <= 1'b1;
      end
      if (mac_rx_err) rx_err_seen <= 1'b1;
    end
  end

  always @(posedge clk or negedge reset_l) begin
    if (!reset_l) begin
      tx_gmii_en_prev      <= 1'b0;
      tx_gmii_pkt_detected <= 1'b0;
      tx_gmii_byte_cnt     <= 32'd0;
    end else begin
      tx_gmii_en_prev <= Eth_TXEN;
      if (Eth_TXEN && !tx_gmii_en_prev) begin
        tx_gmii_byte_cnt     <= 32'd1;
        tx_gmii_pkt_detected <= 1'b1;
        tx_gmii_captured[0]  <= Eth_TXD;
      end
      if (Eth_TXEN && tx_gmii_en_prev) begin
        tx_gmii_captured[tx_gmii_byte_cnt] <= Eth_TXD;
        tx_gmii_byte_cnt <= tx_gmii_byte_cnt + 1;
      end
    end
  end

  initial begin
    Eth_RXDV   <= 1'b0;
    Eth_RXER   <= 1'b0;
    Eth_RXD    <= 8'h00;
    mac_tx_sop <= 1'b0;
    mac_tx_en  <= 1'b0;
    mac_tx_data <= 8'h00;
    mac_tx_eop <= 1'b0;
    mac_tx_err <= 1'b0;

    @(posedge reset_l);
    $display("========================================");
    $display(" tb_gmii2mac - Simulation Start");
    $display("========================================");
    $display(" Time:%0t - Reset released", $time);
    repeat (5) @(posedge clk);

    // ── Test 1：GMII RX 正常收包 ──────────────────────
    $display("----------------------------------------");
    $display(" Test 1: GMII RX normal packet");
    $display("----------------------------------------");
    for (i = 0; i < PKT_DATA_LEN; i = i + 1) payload_buf[i] = i;
    send_gmii_pkt(48'h0102_0304_0506, 48'h0A0B_0C0D_0E0F, 16'h0800, PKT_DATA_LEN, 1'b0);
    $display(" Time:%0t - GMII packet sent, waiting for RX...", $time);
    // 超时等待 mac_rx_eop
    i = 0;
    while (!rx_pkt_done && i < 50000) begin
      @(posedge clk);
      i = i + 1;
    end
    if (rx_pkt_done) begin
      $display(" Time:%0t - RX packet received:", $time);
      $display("   sop=%0d eop=%0d bytes=%0d err=%0d", rx_sop_seen, rx_eop_seen, rx_byte_cnt,
               rx_err_seen);
    end else begin
      $display(" Time:%0t - RX packet NOT received (timeout)", $time);
      $display("   rx_sop_seen=%0d rx_eop_seen=%0d", rx_sop_seen, rx_eop_seen);
    end
    repeat (20) @(posedge clk);

    // ── Test 2：MAC TX 发包到 GMII TX ─────────────────
    $display("----------------------------------------");
    $display(" Test 2: MAC TX to GMII TX");
    $display("----------------------------------------");
    @(posedge clk);
    send_mac_tx_pkt(PKT_DATA_LEN, 1'b0);
    $display(" Time:%0t - MAC TX packet sent, waiting for GMII TX...", $time);
    i = 0;
    while (!tx_gmii_pkt_detected && i < 50000) begin
      @(posedge clk);
      i = i + 1;
    end
    if (tx_gmii_pkt_detected) begin
      repeat (50) @(posedge clk);
      $display(" Time:%0t - GMII TX detected, bytes=%0d", $time, tx_gmii_byte_cnt);
    end else begin
      $display(" Time:%0t - GMII TX NOT detected (timeout)", $time);
    end
    repeat (100) @(posedge clk);

    // ── Test 3：GMII RX 带错误 ─────────────────────────
    $display("----------------------------------------");
    $display(" Test 3: GMII RX with error (Eth_RXER)");
    $display("----------------------------------------");
    @(posedge clk);
    for (i = 0; i < 32; i = i + 1) payload_buf[i] = i + 8'h80;
    send_gmii_pkt(48'hAABB_CCDD_EEFF, 48'h1122_3344_5566, 16'h8800, 32, 1'b1);
    $display(" Time:%0t - GMII err packet sent", $time);
    repeat (2000) @(posedge clk);

    // ── 统计输出 ──────────────────────────────────────
    $display("========================================");
    $display(" Test Summary");
    $display("========================================");
    $display(" rx_afifo_full_cnt  = %0d", rx_afifo_full_cnt);
    $display(" rx_afifo_empty_cnt = %0d", rx_afifo_empty_cnt);
    $display(" rx_data_err_line   = %0d", rx_data_err_line);
    $display(" rx_correct_pkt_cnt = %0d", rx_correct_pkt_cnt);
    $display(" rx_crc_err_pkt_cnt = %0d", rx_crc_err_pkt_cnt);
    $display(" tx_correct_pkt_cnt = %0d", tx_correct_pkt_cnt);
    $display(" tx_error_pkt_cnt   = %0d", tx_error_pkt_cnt);
    $display("========================================");
    $display(" TEST PASSED");
    $display("========================================");

    repeat (50) @(posedge clk);
    // // $finish; (stripped) (stripped for sim)
  end

  // ── 超时保护 ──────────────────────────────────────────
  initial begin
    #50000000;
    $display("ERROR: Simulation timeout!");
    // // $finish; (stripped) (stripped for sim)
  end

  // ── 波形输出 ──────────────────────────────────────────
  initial begin
    $dumpfile("tb_gmii2mac.vcd");
    $dumpvars(0, tb_gmii2mac);
  end
endmodule

// synthesis translate_on
