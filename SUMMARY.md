# RiscV WebSoC 项目总结

**日期**: 2026-08-03 | **FPGA**: XC7A35T-FGG484-2 | **PHY**: RTL8211F | **开发板**: ALINX ACX750

---

## 一、项目目标

在 Artix-7 FPGA 上实现 RISC-V + 千兆以太网 Web 服务器。PC 通过网线连 FPGA，能 ping 通、浏览器能打开网页。

---

## 二、代码仓库

| 仓库 | 内容 |
|------|------|
| `HuanghmBuck/ip_common` | 通用 IP 库 (70+ RTL模块, 含 MDIO/CDC/FIFO/MAC) |
| `HuanghmBuck/ip_riscv` | PicoRV32 RISC-V CPU 核 |
| `HuanghmBuck/ip_lcpu` | LCPU JTAG/UART 调试 IP |
| `HuanghmBuck/fpga_cpu` | RISC-V SoC 基础平台 |
| `yminkey08-sketch/RiscV_WebSoC_orig` | 作者原始 v2 |
| `yminkey08-sketch/RiscV_WebSoC_dev` | 开发版 (MDIO + TCP/IP + JTAG模式) |

### 压缩包版本

| 文件 | 内容 |
|------|------|
| `RiscV_WebSoC(1).7z` | 作者 v1 (预构建 Vivado 工程, lcpu_type=uart) |
| `RiscV_WebSoC(2).7z` | 作者 v2 (Git 追踪版, lcpu_type=uart) |
| `RiscV_WebSoC(3).7z` | **作者最终版** (完整 TCP/HTTP 固件, 板上验证通过) |
| `RiscV_WebSoC2.7z` | 你的新代码 (ping 专用精简版) |

---

## 三、系统架构

```
FPGA (XC7A35T)
├── mmcm_50_125          ← 5路时钟 (50/100/125/200/125_90°)
├── rgmii_gmii_bridge    ← RGMII ↔ GMII (IDELAYE2 + IDDR + ODDR)
├── gmii2mac             ← MAC层 (CDC + CRC + 前导码)
├── cpu_channel           ← 包FIFO通道 (125M ↔ 50M CDC)
├── lcpu_riscv_wrapper   ← PicoRV32 RV32IC + UART LCPU + 总线仲裁
└── lcpu_fpga_test       ← 寄存器 (LED, CPU_FIFO, 指令RAM接口)
```

数据流: `PC → PHY → RGMII RX → MAC → cpu_channel → RISC-V → cpu_channel → MAC → RGMII TX → PHY → PC`

---

## 四、调试过程

### 1. RTL 构建问题

| 问题 | 修复 |
|------|------|
| `always_comb` 语法报错 | `build_fpga.sh` 里所有 `.v` 标记为 SystemVerilog |
| `jtag_axi_0` IP 不兼容 (Virtex-7 vs Artix-7) | 改用 `lcpu_type="uart"` |
| `cpu_channel.v` 缺 `rx_byte_cnt` 声明 | 补上 wire 声明 |
| `timing.xdc` 缺 RGMII DDR 约束 | 补全 `set_input_delay`/`set_output_delay` |

### 2. 固件加载方式

| 尝试 | 结果 |
|------|------|
| UART (`/dev/ttyACM0`) | ❌ CH340 没连到 FPGA 的 UART 引脚 |
| UART (`/dev/ttyUSB0`) | ❌ FTDI 仅 JTAG 模式，无 UART 通道 |
| JTAG `jwrite` | ❌ Vivado 2024.1 不支持旧版 ISSP/VIO 命令 |
| **`updatemem` 嵌入** | ✅ 固件直接写进 .bit 的 BRAM 初始值 |

### 3. TX 通路验证

- 加透传回环 (`fix_delay + MUX`) → PC RX 从 0 变 9 → TX 硬件通路确认正常
- CPU 注入 TX 路径有 WR_PUSH 脉冲问题 → 硬件自动生成 `_ind` 脉冲，固件不需要手动清 0

### 4. FIFO 读写协议

```
✅ 正确: LCPU_RD_START_PACKET() → 读 LEN → 逐字节 ren/raddr → 读 data
❌ 错误: 读 LEN → 读 data → POP (我们的版本)
```

### 5. 链接脚本 (linker.ld)

```ld
/DISCARD/ : { *(.note*) *(.comment*) }
```

必须加这行，否则 `.note.gnu.build-id` 占 0x00-0x23，`reset_entry` 被挤到 0x24，RISC-V 上电取指拿到垃圾数据立即崩溃。

### 6. 栈指针初始化

PicoRV32 上电 sp=0，调用函数就会把栈写到指令区摧毁固件：

```c
__attribute__((naked, used, section(".text.bootloader")))
void reset_entry() {
    asm volatile(
        "la sp, _end + 16384\n"  // sp = _end + 16KB
        "j main\n"
    );
}
```

### 7. 工具链

| 工具链 | 结果 |
|--------|------|
| Xilinx Vitis `riscv64-unknown-elf-gcc 12.2.0` | ❌ 编译的固件 ping 不通 |
| xPack `riscv-none-elf-gcc 14.2.0` | ❌ 同上（机器码寄存器地址均正确） |
| 另一台电脑的未知工具链 | ✅ 能通 |

### 8. IP 地址

- PC: `169.254.35.186/16` (自动分配)
- FPGA (v3 作者): `169.254.1.1`
- FPGA (你的代码): `169.254.1.1` 或 `169.254.35.100` 均可，同 /16 子网

---

## 五、当前状态

| 项目 | 状态 |
|------|------|
| RISC-V 执行 | ✅ LED 可控，流水灯正常 |
| 以太网收包 (RX) | ✅ `eth_rx_frame()` 正常返回 |
| 以太网发包 (TX) | ⚠️ 寄存器写正确，PC 收不到 |
| Ping (ICMP) | ❌ |
| HTTP 网页 | ❌ |
| 作者 v3 预编译 | ✅ ping 通，HTTP 可访问 |

### 已验证可用的比特流

```
/home/minkey/work/RiscV_WebSoC_fw.bit   ← 烧这个就能 ping 通 169.254.1.1
```

---

## 六、关键文件

```
FPGA_prj/RiscV_WebSoC2/
├── c/
│   ├── main.c               ← 主循环 + 复位入口 + LED 状态机
│   ├── eth.c/h              ← 以太网帧收发
│   ├── arp.c/h              ← ARP 请求/回复
│   ├── ip.c/h               ← IPv4 处理 + 校验和
│   ├── icmp.c/h             ← ICMP Echo Reply (ping)
│   └── inc/lcpu_general.h  ← 硬件寄存器宏 + 网络常量 + FIFO 操作
├── c_build/
│   ├── Makefile             ← 编译脚本
│   └── linker.ld           ← 链接脚本 (DISCARD .note 段)
├── rtl/                     ← Verilog RTL (43文件, 从 v3 复制)
└── build_xilinx/
    ├── RiscV_WebSoC.xpr    ← Vivado 工程
    ├── pins.xdc            ← 引脚约束
    └── timing.xdc          ← 时序约束
```

---

## 七、RISC-V 编译原理（简要）

```
C 源码 (.c) → [gcc -c] → .o (机器码+符号表)
             → [ld + linker.ld] → .elf (链接, 分配最终地址)
             → [objcopy -O binary] → .bin (纯指令流)
             → [updatemem] → .bit (嵌入 BRAM 初始值)
```

- **RV32IC**: RV32I (40条基本指令) + C (压缩指令, 16位编码)
- **Load-Store 架构**: 只有 load/store 访存, 运算全在 32 个通用寄存器
- **栈**: x2(sp) 指向栈顶, 向下增长, 存返回地址和局部变量
- **入口**: 上电 PC=0, `reset_entry` 必须在此地址 (链接脚本保证)

---

## 八、待解决

你的代码逻辑和机器码均正确，但 TX 发包 PC 收不到。同一 v3 硬件上作者固件能通。下一步把另一台能通的电脑上编译的 `firmware.elf` 发来做二进制对比。
