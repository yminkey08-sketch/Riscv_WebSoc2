// ==========================================================================
// ila_pkg.vh — fpga_ila 全局宏定义（命令码 / 寄存器地址 / 默认参数 / 魔数）
// 纯 Verilog-2001，`include 到需要的模块。跨厂商可综合，无厂商专用构造。
// ==========================================================================
`ifndef ILA_PKG_VH
`define ILA_PKG_VH

// ---- 身份 ----
`define ILA_IDCODE   32'h5346_494C   // "SFIL" — soft ila 标识魔数
`define ILA_VERSION  32'h0001_0000   // v1.0

// ---- 协议命令码（见 docs/protocol.md）----
`define CMD_PING          8'h01
`define CMD_GET_INFO      8'h02
`define CMD_GET_CORE_CFG  8'h03
`define CMD_REG_WRITE     8'h10
`define CMD_REG_READ      8'h11
`define CMD_ARM           8'h20
`define CMD_DISARM        8'h21
`define CMD_FORCE_TRIG    8'h22
`define CMD_GET_STATUS    8'h23
`define CMD_READ_BUF      8'h30
`define CMD_SET_NET       8'h40
`define CMD_EVENT_TRIG    8'h7E
`define CMD_RESP_FLAG     8'h80   // 响应帧 CMD 最高位置 1

// ---- 帧同步字 ----
`define ILA_SYNC0    8'h55
`define ILA_SYNC1    8'hAA
`define ILA_BCAST    8'hFF   // CORE_ID 广播 / Hub 自身

// ---- 只读寄存器地址（身份/结构）----
`define REG_IDCODE       16'h0000
`define REG_VERSION      16'h0001
`define REG_SIGN_L       16'h0002
`define REG_SIGN_H       16'h0003
`define REG_NUM_PROBES   16'h0004
`define REG_TOTAL_WIDTH  16'h0005
`define REG_DATA_DEPTH   16'h0006
`define REG_MAX_WINDOWS  16'h0007
`define REG_SAMPLE_HZ    16'h0008

// ---- 读写寄存器（运行期行为）----
`define REG_CTRL         16'h0100   // bit0=ARM bit1=DISARM bit2=FORCE bit3=CROSS_TRIG_EN
`define REG_STATUS       16'h0101   // bit0=IDLE 1=ARMED 2=TRIGGERED 3=FULL [31:16]=cur_window
`define REG_FILL_LEVEL   16'h0102
`define REG_WINDOWS_NUM  16'h0110
`define REG_TRIG_POS     16'h0111   // 0=前触发 1=居中 2=后触发
`define REG_CAPTURE_LEN  16'h0112
`define REG_TRIG_FILLED  16'h0113   // 触发样本物理 BRAM 地址（只读，精确光标定位）
`define REG_TRIG_SRC     16'h0114   // 触发源：bit0=1 force, 0=level 匹配（只读）
`define REG_TRIG_REQ_VAL 16'h0115   // 触发时刻 probe[0] 的值（诊断: 比对 SCAN）
`define REG_TRIG_WR_DATA 16'h0116   // 触发时刻 sample[31:0]（写入确认诊断）
`define REG_TRIG_WR_WE   16'h0117   // 触发时刻 ram_we（应为 1）
`define REG_TRIG_WR_ADDR 16'h0118   // 触发时刻 ram_waddr（应 = trig_filled-1）
`define REG_TRACE_CTL   16'h0119   // trace: {27b0, trace_done, trace_ptr[2:0]}
`define REG_TRIG_WR_DATA_D1 16'h011A // 周期 N+1 ram_wdata[31:0]（BRAM 实际写入值，诊断用）
`define REG_TRACE_DATA  16'h0180   // 0x0180+N: trace entry N[7:0]（we,req,addr[9:0] 低位）
`define REG_TRACE_DATA2 16'h0122   // 0x0122+N: trace entry N addr[9:0]（高位填充到 32bit）
`define REG_WIN_START    16'h0120   // 0x0120+w : 第 w 窗起始物理偏移（只读）
`define REG_BUF_ADDR     16'h0130   // 写：设置回读样本物理地址
`define REG_BUF_DATA     16'h0138   // 0x0138+i : 读当前样本第 i 个 32bit 字

// ---- 触发比较器寄存器基址 ----
`define REG_PROBE_WIDTH  16'h0040   // 0x0040+i : PROBEi_WIDTH (只读)
`define REG_TRIG_VALUE0  16'h0200   // +i
`define REG_TRIG_MASK0   16'h0240   // +i

// ---- CTRL 位 ----
`define CTRL_ARM_BIT     0
`define CTRL_DISARM_BIT  1
`define CTRL_FORCE_BIT   2
`define CTRL_XTRIG_BIT   3

// ---- STATUS 位 ----
`define ST_IDLE_BIT      0
`define ST_ARMED_BIT     1
`define ST_TRIG_BIT      2
`define ST_FULL_BIT      3

// ---- 默认结构参数（可被例化覆盖）----
`define DEF_DATA_DEPTH    1024
`define DEF_MAX_WINDOWS   4
`define DEF_NUM_PROBES    32
`define DEF_TOTAL_WIDTH   256

// ---- 触发位置预设 ----
`define TRIGPOS_FRONT    2'd0
`define TRIGPOS_CENTER   2'd1
`define TRIGPOS_BACK     2'd2

// ---- fcapz ELA 寄存器地址（从 fpgacapZero，供 ila_hub_fcapz 适配层使用）----
// fcapz_ela 的 jtag_clk 域寄存器映射。对于 UART/ETH 模式，ila_hub 通过这些地址
// 读写 fcapz_ela 核。地址空间 0x0000-0x00FF（控制/状态）+ 0x0100+（DATA window）。
`define FCAPZ_ADDR_VERSION     16'h0000   // RO: {major[7:0], minor[7:0], core_id[15:0]}
`define FCAPZ_ADDR_CTRL        16'h0004   // RW: bit0=arm_toggle bit1=reset_toggle
`define FCAPZ_ADDR_STATUS      16'h0008   // RO: bit0=armed bit1=triggered bit2=done bit3=overflow
`define FCAPZ_ADDR_SAMPLE_W    16'h000C   // RO: SAMPLE_W
`define FCAPZ_ADDR_DEPTH       16'h0010   // RO: DEPTH
`define FCAPZ_ADDR_PRETRIG     16'h0014   // RW: pre-trigger sample count
`define FCAPZ_ADDR_POSTTRIG    16'h0018   // RW: post-trigger sample count
`define FCAPZ_ADDR_CAPTURE_LEN 16'h001C   // RO: actual capture_len after arm
`define FCAPZ_ADDR_TRIG_MODE   16'h0020   // RW: legacy trig_mode (bit0=value_match bit1=edge_detect)
`define FCAPZ_ADDR_TRIG_VALUE  16'h0024   // RW: comparator A value (stage 0, legacy)
`define FCAPZ_ADDR_TRIG_MASK   16'h0028   // RW: comparator A mask (stage 0, legacy)
`define FCAPZ_ADDR_BURST_PTR   16'h002C   // RW: burst read start pointer (USER2 burst trigger)
`define FCAPZ_ADDR_SQ_MODE     16'h0030   // RW: storage qualifier mode (STOR_QUAL=1 only)
`define FCAPZ_ADDR_SQ_VALUE    16'h0034   // RW: storage qualifier value
`define FCAPZ_ADDR_SQ_MASK     16'h0038   // RW: storage qualifier mask
`define FCAPZ_ADDR_FEATURES    16'h003C   // RO: feature flags
`define FCAPZ_ADDR_SEQ_BASE    16'h0040   // RW: sequencer stage config base (5 regs/stage)
`define FCAPZ_ADDR_CHAN_SEL    16'h00A0   // RW: active channel select (NUM_CHANNELS>1)
`define FCAPZ_ADDR_NUM_CHAN    16'h00A4   // RO: NUM_CHANNELS
`define FCAPZ_ADDR_PROBE_SEL   16'h00AC   // RW: runtime probe mux slice (PROBE_MUX_W>0)
`define FCAPZ_ADDR_DECIM       16'h00B0   // RW: decimation ratio (DECIM_EN=1)
`define FCAPZ_ADDR_TRIG_EXT    16'h00B4   // RW: external trigger mode [1:0]
`define FCAPZ_ADDR_NUM_SEGMENTS 16'h00B8  // RO: NUM_SEGMENTS
`define FCAPZ_ADDR_SEG_STATUS  16'h00BC   // RO: segment status
`define FCAPZ_ADDR_SEG_SEL     16'h00C0   // RW: segment select for readback
`define FCAPZ_ADDR_SEG_NUM_RT  16'h00E4   // RW: runtime segment count (1/2/4, power of 2 <= NUM_SEGMENTS)
`define FCAPZ_ADDR_TIMESTAMP_W 16'h00C4   // RO: TIMESTAMP_W
`define FCAPZ_ADDR_SEG_START   16'h00C8   // RO: seg_start_ptr for selected segment
`define FCAPZ_ADDR_PROBE_MUX_W 16'h00D0   // RO: PROBE_MUX_W
`define FCAPZ_ADDR_TRIG_DELAY  16'h00D4   // RW: post-trigger delay (sample clocks)
`define FCAPZ_ADDR_STARTUP_ARM 16'h00D8   // RW: auto-arm after reset
`define FCAPZ_ADDR_TRIG_HOLDOFF 16'h00DC  // RW: trigger holdoff (sample clocks)
`define FCAPZ_ADDR_COMPARE_CAPS 16'h00E0  // RO: compare mode capabilities
`define FCAPZ_ADDR_DATA_BASE   16'h0100   // RO: USER1 data window (DEPTH * words_per_sample * 4 bytes)
// Sequencer per-stage register offsets (stage N at BASE + N*0x14):
//   +0x0: CFG   [3:0]=mode_a [7:4]=mode_b [9:8]=combine [10+]=next_state [12]=is_final [31:16]=count_target
//   +0x4: VALUE_A
//   +0x8: MASK_A
//   +0xC: VALUE_B
//   +0x10: MASK_B

`endif // ILA_PKG_VH
