//-----------------------------------------------------------------
// webserver_cpu_top.v — RiscV WebSoC 顶层模块
// 集成: PLL + RGMII Bridge + gmii2mac + cpu_channel + RISC-V + 寄存器
// 目标: XC7A35T-FGG484-2
//-----------------------------------------------------------------
`include "define.sv"

module webserver_cpu_top #(
    parameter sim_mod = 0           // 0=真实硬件, 1=仿真 (PLL bypass + LCPU BFM)
) (
    // 系统
    input  wire       clk_50m_in,
    input  wire       reset_l,

    // RGMII
    output wire       rgmii_txc,
    output wire [3:0] rgmii_txd,
    output wire       rgmii_tx_ctl,
    input  wire       rgmii_rxc,
    input  wire [3:0] rgmii_rxd,
    input  wire       rgmii_rx_ctl,

    // MDIO
    output wire       Eth0_MDC,
    inout  wire       Eth0_MDIO,

    // PHY 控制
    output wire       rgmii_reset_l,

    // UART
    input  wire       uart_rx,
    output wire       uart_tx,

    // LED
    output wire [3:0] led_o
);

  //============================================================================
  // 参数
  //============================================================================
  localparam lcpu_type       = "uart";
  localparam uart_baud_rate  = 115200;
  localparam riscv_inst_en   = 1;
  localparam instr_databits  = 32;
  localparam init_addr_width = 13;
  localparam init_addr_depth = 1024 * 4;  // 4096 words (16KB), was 2048
  localparam device_vendor   = `DEVICE_VENDOR;
  localparam instr_ram_type  = `LARGER_RAM;
  localparam init_blockram_size = 8;

  // cpu_channel 参数
  localparam CPU_BUF_ADDR_WIDTH = 12;
  localparam CPU_BUF_DATA_WIDTH = 8;
  localparam CPU_BUF_PARA_WIDTH = 1;

  //============================================================================
  // 时钟 & 复位
  //============================================================================
  wire clk_50m;        // CPU 域
  wire clk_125m;       // MAC 域
  wire clk_200m;       // IDELAYCTRL
  wire clk_125m_tx;    // RGMII TX
  wire pll_locked;
  wire sys_rst_n;      // reset_l & pll_locked

  // 统一时钟: 仿真用 vendor_stubs MMCM stub, 上板用真实 MMCM
  mmcm_50_125 u_pll (
      .clk_50m      (clk_50m_in),
      .clk_125m     (clk_125m),
      .clk_200m     (clk_200m),
      .clk_125m_tx  (clk_125m_tx),
      .clk_50m_cpu  (clk_50m),
      .locked       (pll_locked),
      .rst_n        (reset_l)
  );

  assign sys_rst_n = reset_l & pll_locked;

  //============================================================================
  // PHY 复位 (~16ms 延时释放)
  //============================================================================
  reg  [20:0] phy_rst_cnt;
  reg         phy_rst_n_r;

  always @(posedge clk_125m or negedge sys_rst_n)
    if (!sys_rst_n) {phy_rst_cnt, phy_rst_n_r} <= 0;
    else if (!phy_rst_n_r) begin
      phy_rst_cnt <= phy_rst_cnt + 1;
      if (phy_rst_cnt == 21'h1F_FFFF) phy_rst_n_r <= 1'b1;
    end

  assign rgmii_reset_l = phy_rst_n_r;

  //============================================================================
  // RGMII ↔ GMII 信号
  //============================================================================
  wire        gmii_rx_clk, gmii_rx_dv, gmii_rx_er;
  wire [7:0]  gmii_rxd;
  wire [7:0]  gmii_txd;
  wire        gmii_tx_en, gmii_tx_er;

  //============================================================================
  // gmii2mac ↔ cpu_channel 信号 (MAC 包流)
  //============================================================================
  wire        mac_rx_sop, mac_rx_en, mac_rx_eop, mac_rx_err;
  wire [7:0]  mac_rx_data;
  wire        mac_tx_sop, mac_tx_en, mac_tx_eop, mac_tx_err;
  wire [7:0]  mac_tx_data;

  //============================================================================
  // cpu_channel ↔ lcpu_fpga_test 信号 (CPU FIFO)
  //============================================================================
  wire        cpu_rd_empty;
  wire        cpu_rd_rpkt_pop;
  wire        cpu_rd_rpkt_pop_ind;
  wire [CPU_BUF_ADDR_WIDTH:0] cpu_rd_rpkt_len;
  wire [CPU_BUF_PARA_WIDTH-1:0] cpu_rd_rpkt_para;
  wire        cpu_rd_ren;
  wire [CPU_BUF_ADDR_WIDTH-1:0] cpu_rd_raddr;
  wire [CPU_BUF_DATA_WIDTH-1:0] cpu_rd_rdata;
  wire        cpu_rd_reop_pre;

  wire        cpu_wr_full;
  wire        cpu_wr_wen;
  wire        cpu_wr_wen_ind;
  wire [CPU_BUF_ADDR_WIDTH-1:0] cpu_wr_waddr;
  wire [CPU_BUF_DATA_WIDTH-1:0] cpu_wr_wdata;
  wire [CPU_BUF_ADDR_WIDTH:0] cpu_wr_wpkt_len;
  wire        cpu_wr_wpkt_push;
  wire        cpu_wr_wpkt_push_ind;

  // lcpu_fpga_test 输出的 32-bit 信号截断到 cpu_channel 位宽
  wire [31:0] fpga_cpu_rd_raddr, fpga_cpu_wr_waddr, fpga_cpu_wr_wdata, fpga_cpu_wr_wpkt_len;
  wire [31:0] fpga_cpu_rd_rpkt_len, fpga_cpu_rd_rdata;
  wire [0:0]  fpga_cpu_rd_empty,   fpga_cpu_rd_reop_pre, fpga_cpu_wr_full;
  wire [0:0]  fpga_cpu_rd_rpkt_pop, fpga_cpu_rd_ren;
  wire [0:0]  fpga_cpu_wr_wen,     fpga_cpu_wr_wpkt_push;

  // cpu_channel OUTPUT → lcpu_fpga_test INPUT (CPU读)
  assign fpga_cpu_rd_empty   = cpu_rd_empty;
  assign fpga_cpu_rd_reop_pre = cpu_rd_reop_pre;
  assign fpga_cpu_rd_rpkt_len = { {(32-(CPU_BUF_ADDR_WIDTH+1)){1'b0}}, cpu_rd_rpkt_len };
  assign fpga_cpu_rd_rdata    = { {(32-CPU_BUF_DATA_WIDTH){1'b0}}, cpu_rd_rdata };
  // lcpu_fpga_test OUTPUT → cpu_channel INPUT (CPU写)
  assign cpu_rd_raddr    = fpga_cpu_rd_raddr[CPU_BUF_ADDR_WIDTH-1:0];
  assign cpu_rd_ren      = fpga_cpu_rd_ren[0];
  // cpu_channel OUTPUT → lcpu_fpga_test INPUT (CPU写)
  assign fpga_cpu_wr_full = cpu_wr_full;
  // lcpu_fpga_test OUTPUT → cpu_channel INPUT (CPU写)
  assign cpu_wr_waddr    = fpga_cpu_wr_waddr[CPU_BUF_ADDR_WIDTH-1:0];
  assign cpu_wr_wdata    = fpga_cpu_wr_wdata[CPU_BUF_DATA_WIDTH-1:0];
  assign cpu_wr_wpkt_len = fpga_cpu_wr_wpkt_len[CPU_BUF_ADDR_WIDTH:0];

  //============================================================================
  // LCPU 总线 (lcpu_riscv_wrapper → lcpu_fpga_test)
  //============================================================================
  wire        bus_req, bus_rhwl;
  wire [31:0] bus_wdata, bus_address;
  wire        bus_ack;
  wire [31:0] bus_rdata;

  // 指令 RAM 接口 (共享: lcpu_fpga_test ↔ lcpu_riscv_wrapper)
  wire        pram_wr;
  wire [15:0] pram_addr;
  wire [31:0] pram_wdata;
  wire [31:0] pram_rdata;

  // RISC-V 复位
  wire [0:0]  riscv_reset_l;

  // LED / FPGA 版本
  wire [31:0] fpga_build_date, fpga_build_time;
  wire [3:0]  led_val;
  assign led_o = led_val;

  //============================================================================
  // 1. fpga_build_time — 版本时间戳
  //============================================================================
  fpga_build_time u_build_time (
      .build_date (fpga_build_date),
      .build_time (fpga_build_time)
  );

  //============================================================================
  // 2. rgmii_gmii_bridge — RGMII ↔ GMII
  //============================================================================
  rgmii_gmii_bridge u_bridge (
      .gmii_tx_clk   (clk_125m_tx),
      .gmii_txd      (gmii_txd),
      .gmii_tx_en    (gmii_tx_en),
      .gmii_tx_er    (gmii_tx_er),
      .gmii_rx_clk   (gmii_rx_clk),
      .gmii_rxd      (gmii_rxd),
      .gmii_rx_dv    (gmii_rx_dv),
      .gmii_rx_er    (gmii_rx_er),
      .rgmii_txc     (rgmii_txc),
      .rgmii_txd     (rgmii_txd),
      .rgmii_tx_ctl  (rgmii_tx_ctl),
      .rgmii_rxc     (rgmii_rxc),
      .rgmii_rxd     (rgmii_rxd),
      .rgmii_rx_ctl  (rgmii_rx_ctl),
      .idelay_refclk (clk_200m),
      .rst_n         (sys_rst_n)
  );

  //============================================================================
  // 3. gmii2mac — MAC 层
  //============================================================================
  gmii2mac u_gmii2mac (
      .clk        (clk_125m),
      .reset_l    (sys_rst_n),
      .Eth_RXC    (gmii_rx_clk),
      .Eth_RXDV   (gmii_rx_dv),
      .Eth_RXER   (gmii_rx_er),
      .Eth_RXD    (gmii_rxd),
      .Eth_TXD    (gmii_txd),
      .Eth_TXEN   (gmii_tx_en),
      .Eth_TXER   (gmii_tx_er),
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
      .rx_afifo_full_cnt (),
      .rx_afifo_empty_cnt(),
      .rx_data_err_line  (),
      .rx_correct_pkt_cnt(),
      .rx_crc_err_pkt_cnt(),
      .tx_correct_pkt_cnt(),
      .tx_error_pkt_cnt  ()
  );

  //============================================================================
  // 4. cpu_channel — CPU-FIFO 通道
  //============================================================================
  cpu_channel #(
      .cpu_buf_addr_width      (CPU_BUF_ADDR_WIDTH),
      .cpu_buf_data_width      (CPU_BUF_DATA_WIDTH),
      .cpu_buf_para_width      (CPU_BUF_PARA_WIDTH),
      .cpu_buf_block_mode      ("false"),
      .cpu_buf_block_addr_width(3)
  ) u_cpu_channel (
      .clk             (clk_125m),
      .reset_l         (sys_rst_n),
      .cpu_clk         (clk_50m),
      // MAC RX
      .mac_rx_sop      (mac_rx_sop),
      .mac_rx_en       (mac_rx_en),
      .mac_rx_data     (mac_rx_data),
      .mac_rx_eop      (mac_rx_eop),
      // MAC TX
      .mac_tx_sop      (mac_tx_sop),
      .mac_tx_en       (mac_tx_en),
      .mac_tx_data     (mac_tx_data),
      .mac_tx_eop      (mac_tx_eop),
      .mac_tx_err      (mac_tx_err),
      // CPU 读 (50MHz)
      .cpu_rd_empty    (cpu_rd_empty),
      .cpu_rd_rpkt_pop (cpu_rd_rpkt_pop_ind),
      .cpu_rd_rpkt_len (cpu_rd_rpkt_len),
      .cpu_rd_rpkt_para(cpu_rd_rpkt_para),
      .cpu_rd_ren      (cpu_rd_ren),
      .cpu_rd_raddr    (cpu_rd_raddr),
      .cpu_rd_rdata    (cpu_rd_rdata),
      .cpu_rd_reop_pre (cpu_rd_reop_pre),
      // CPU 写 (50MHz)
      .cpu_wr_full     (cpu_wr_full),
      .cpu_wr_wen      (cpu_wr_wen_ind),
      .cpu_wr_waddr    (cpu_wr_waddr),
      .cpu_wr_wdata    (cpu_wr_wdata),
      .cpu_wr_wpkt_push(cpu_wr_wpkt_push_ind),
      .cpu_wr_wpkt_len (cpu_wr_wpkt_len),
      .cpu_wr_wpkt_para(),
      // 调试
      .recv_pkt_drop_cnt(),
      .dbg_fifo_wdata  (),
      .dbg_fifo_wen    (),
      .dbg_fifo_push   ()
  );

  //============================================================================
  // 5. lcpu_riscv_wrapper — RISC-V 子系统
  //============================================================================
  lcpu_riscv_wrapper #(
      .sim_mod           (sim_mod),
      .lcpu_type         (lcpu_type),
      .uart_baud_rate    (uart_baud_rate),
      .riscv_inst_en     (riscv_inst_en),
      .instr_databits    (instr_databits),
      .init_addr_width   (init_addr_width),
      .init_addr_depth   (init_addr_depth),
      .device_vendor     (device_vendor),
      .instr_ram_type    (instr_ram_type),
      .init_blockram_size(init_blockram_size),
      .enable_irq        (0),
      .enable_irq_qregs  (1),
      .progaddr_irq      (16)
  ) u_riscv (
      .clk            (clk_50m),
      .reset_l        (reset_l),
      .uart_rx        (uart_rx),
      .uart_tx        (uart_tx),
      .riscv_reset_l  (riscv_reset_l),
      // 指令 RAM 接口
      .pram_wr        (pram_wr),
      .pram_addr      (pram_addr),
      .pram_wdata     (pram_wdata),
      .pram_rdata     (pram_rdata),
      // 合并总线
      .req            (bus_req),
      .rhwl           (bus_rhwl),
      .wdata          (bus_wdata),
      .address        (bus_address),
      .ack            (bus_ack),
      .rdata          (bus_rdata)
  );

  //============================================================================
  // 6. lcpu_fpga_test — 寄存器 + 指令 RAM 接口
  //============================================================================
  lcpu_fpga_test u_reg (
      .clk                          (clk_50m),
      .rst_n                        (reset_l),
      // LCPU 总线
      .req                          (bus_req),
      .rhwl                         (bus_rhwl),
      .wdata                        (bus_wdata),
      .address                      (bus_address),
      .rdata                        (bus_rdata),
      .ack                          (bus_ack),
      // 指令 RAM
      .RAMIF_program_ram_Ram_RlWh   (pram_wr),
      .RAMIF_program_ram_Ram_Addr   (pram_addr),
      .RAMIF_program_ram_Ram_WrData (pram_wdata),
      .RAMIF_program_ram_Ram_RdData (pram_rdata),
      // FPGA 版本
      .fpga_build_date              (fpga_build_date),
      .fpga_build_time              (fpga_build_time),
      // LED & PLL
      .led                          (led_val),
      .pll_locked                   (pll_locked),
      .riscv_reset_l                (riscv_reset_l),
      // CPU FIFO (RX)
      .cpu_rd_empty                 (fpga_cpu_rd_empty),
      .cpu_rd_rpkt_pop              (fpga_cpu_rd_rpkt_pop),
      .cpu_rd_rpkt_pop_ind          (cpu_rd_rpkt_pop_ind),
      .cpu_rd_rpkt_len              (fpga_cpu_rd_rpkt_len),
      .cpu_rd_ren                   (fpga_cpu_rd_ren),
      .cpu_rd_raddr                 (fpga_cpu_rd_raddr),
      .cpu_rd_rdata                 (fpga_cpu_rd_rdata),
      .cpu_rd_reop_pre              (fpga_cpu_rd_reop_pre),
      // CPU FIFO (TX)
      .cpu_wr_full                  (fpga_cpu_wr_full),
      .cpu_wr_wen                   (fpga_cpu_wr_wen),
      .cpu_wr_wen_ind               (cpu_wr_wen_ind),
      .cpu_wr_waddr                 (fpga_cpu_wr_waddr),
      .cpu_wr_wdata                 (fpga_cpu_wr_wdata),
      .cpu_wr_wpkt_len              (fpga_cpu_wr_wpkt_len),
      .cpu_wr_wpkt_push             (fpga_cpu_wr_wpkt_push),
      .cpu_wr_wpkt_push_ind         (cpu_wr_wpkt_push_ind)
  );

  //============================================================================
  // MDIO — 暂不连接 (后续扩展)
  //============================================================================
  assign Eth0_MDC  = 1'b0;
  assign Eth0_MDIO = 1'bz;

endmodule
