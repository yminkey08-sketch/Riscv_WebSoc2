#ifndef _LCPU_GEN_H_
#define _LCPU_GEN_H_

#include <stdint.h>
#include <stdbool.h>

// ============================================================
// 1. 基础类型别名
// ============================================================
typedef uint8_t   uint8;
typedef uint16_t  uint16;
typedef uint32_t  uint32;
typedef int8_t    int8;
typedef int16_t   int16;
typedef int32_t   int32;

// ============================================================
// 2. 硬件总线基地址 + 底层单字节访问
// ============================================================
#define HW_BASE  0x80000000u
// LCPU 总线只支持 32 位访问，HW_REG8 读写 32 位寄存器，取/设低 8 位
#define HW_REG8(offset)  (*(volatile uint32_t *)(HW_BASE + (uint32_t)(offset) * 4))

static inline uint32_t reg32_read(uint32_t offset) {
    return HW_REG8(offset);                    // 一次读 32 位
}
static inline void reg32_write(uint32_t offset, uint32_t val) {
    HW_REG8(offset) = val;                     // 一次写 32 位
}

// ============================================================
// 3. 硬件寄存器字节偏移
// ============================================================
// 系统控制
#define REG_FPGA_DATE      0x0000  // RO
#define REG_FPGA_TIME      0x0001  // RO
#define REG_SW_DATE        0x0002  // RW
#define REG_SW_TIME        0x0003  // RW
#define REG_SCRATCH0       0x0004  // RW
#define REG_SCRATCH1       0x0005  // RW
#define REG_SCRATCH2       0x0006  // RW
#define REG_SCRATCH3       0x0007  // RW
#define REG_SCRATCH4       0x0008  // RW
#define REG_SCRATCH5       0x0009  // RW
#define REG_SCRATCH6       0x000A  // RW
#define REG_SCRATCH7       0x000B  // RW
#define REG_SCRATCH8       0x000C  // RW
#define REG_SCRATCH9       0x000D  // RW
#define REG_SCRATCH10      0x000E  // RW
#define REG_SCRATCH11      0x000F  // RW
#define REG_LED            0x0010  // RW 低4位
#define REG_PLL_LOCKED     0x0011  // RO bit0
#define REG_RISCV_RST      0x0100  // RW bit0

// RX FIFO
#define REG_RX_EMPTY       0x6000  // RO bit0
#define REG_RX_PKT_POP     0x6001  // WC 写1弹出
#define REG_RX_PKT_LEN     0x6002  // RO 32bit
#define REG_RX_PKT_PARA    0x6003  // RO 32bit
#define REG_RX_REN         0x6004  // RW bit0
#define REG_RX_RADDR       0x6005  // RW 32bit
#define REG_RX_RDATA       0x6006  // RO 低8bit
#define REG_RX_REOP_PRE    0x6007  // RO bit0

// TX FIFO
#define REG_TX_FULL        0x6100  // RO bit0
#define REG_TX_WEN         0x6101  // WC
#define REG_TX_WADDR       0x6102  // RW
#define REG_TX_WDATA       0x6103  // RW
#define REG_TX_PKT_LEN     0x6104  // RW
#define REG_TX_PKT_PUSH    0x6106  // WC

#define LCPU_DBG_BASE  0x10000

// ============================================================
// 4. FIFO 高层操作宏（必须保留，底层收发依赖）
// ============================================================
#define LCPU_RD_EMPTY()         (HW_REG8(REG_RX_EMPTY) != 0)
#define LCPU_RD_START_PACKET()  do { HW_REG8(REG_RX_PKT_POP) = 1; HW_REG8(REG_RX_REN) = 1; } while(0)
#define LCPU_RD_STOP()          do { HW_REG8(REG_RX_REN) = 0; } while(0)
#define LCPU_RD_PKT_LEN()       ((uint16_t)(reg32_read(REG_RX_PKT_LEN) & 0xFFFFu))
#define LCPU_RD_PKT_PARA()      (reg32_read(REG_RX_PKT_PARA))

static inline uint32_t rd_get_addr(void) { return reg32_read(REG_RX_RADDR); }
static inline void rd_set_addr(uint32_t addr) { reg32_write(REG_RX_RADDR, addr); }
#define LCPU_RD_SET_ADDR(addr)  rd_set_addr(addr)
#define LCPU_RD_INC_ADDR()      do { uint32_t a = rd_get_addr(); rd_set_addr(a + 1); } while(0)
#define LCPU_RD_DATA8()         ((uint8_t)(reg32_read(REG_RX_RDATA) & 0xFFu))
#define LCPU_RD_REOP_PRE()      ((HW_REG8(REG_RX_REOP_PRE) & 0x01) != 0)

#define LCPU_WR_FULL()          ((HW_REG8(REG_TX_FULL) & 0x01) != 0)
static inline void wr_set_addr(uint32_t addr) { reg32_write(REG_TX_WADDR, addr); }
static inline void wr_set_data(uint8_t data) { reg32_write(REG_TX_WDATA, (uint32_t)data); }
#define LCPU_WR_SET_ADDR(addr)  wr_set_addr(addr)
#define LCPU_WR_SET_DATA(data)  wr_set_data(data)
#define LCPU_WR_PULSE_WEN()     do { HW_REG8(REG_TX_WEN) = 1; } while(0)
#define LCPU_WR_BYTE(addr, data) do { LCPU_WR_SET_ADDR(addr); LCPU_WR_SET_DATA(data); LCPU_WR_PULSE_WEN(); } while(0)
#define LCPU_WR_PUSH_PACKET(pkt_len) do { reg32_write(REG_TX_PKT_LEN, (uint32_t)(pkt_len)); HW_REG8(REG_TX_PKT_PUSH) = 1; } while(0)

// ============================================================
// 5. LED / 定时器（调试心跳灯，建议保留）
// ============================================================
#define LCPU_SET_LED(value)     do { HW_REG8(REG_LED) = (uint8_t)(value); } while(0)
#define LED_ON(bit)     do { uint8_t v = HW_REG8(REG_LED); v &= ~(1u << (bit)); HW_REG8(REG_LED) = v; } while(0)
#define LED_OFF(bit)    do { uint8_t v = HW_REG8(REG_LED); v |=  (1u << (bit)); HW_REG8(REG_LED) = v; } while(0)
#define LED_TOGGLE(bit) do { uint8_t v = HW_REG8(REG_LED); v ^=  (1u << (bit)); HW_REG8(REG_LED) = v; } while(0)

static inline uint32_t lcpu_local_time_l(void) {
    uint32_t t;
    __asm__ volatile ("rdcycle %0" : "=r"(t));
    return t;
}
#define LCPU_SECOND_EVENT()  ((lcpu_local_time_l() & 0x00400000) != 0)

// ============================================================
// 6. 调试RAM（可选，可删除）
// ============================================================
#define LCPU_DBG_WRITE(index, value)  do { reg32_write(LCPU_DBG_BASE + (index)*4, (uint32_t)(value)); } while(0)
#define LCPU_DBG_READ(index)          ((uint8_t)(reg32_read(LCPU_DBG_BASE + (index)*4) & 0xFFu))
// ============================================================
// 7. 通用32位寄存器读写
// ============================================================
#define LCPU_REG32_WRITE(offset, val)  reg32_write((uint32_t)(offset), (uint32_t)(val))
#define LCPU_REG32_READ(offset)        reg32_read((uint32_t)(offset))

// ============================================================
// 8. Ping必需网络常量
// ============================================================
// 本机MAC
#define LOCAL_MAC_BYTE0 0x02
#define LOCAL_MAC_BYTE1 0x00
#define LOCAL_MAC_BYTE2 0x00
#define LOCAL_MAC_BYTE3 0x12
#define LOCAL_MAC_BYTE4 0x34
#define LOCAL_MAC_BYTE5 0x56

// 本机IP 192.168.1.88
#define LOCAL_IP_ADDR   0xA9FE0101u  // 169.254.1.1

// 以太网类型
#define ETH_TYPE_IP     0x0800
#define ETH_TYPE_ARP    0x0806
#define ETH_MAX_FRAME_LEN 1518

// IPv4协议号（只留ICMP）
#define IP_PROTO_ICMP   0x01

// ARP操作码
#define ARP_REQUEST     0x0001
#define ARP_REPLY       0x0002

// ICMP类型(Ping专用)
#define ICMP_ECHO_REQ   0x08
#define ICMP_ECHO_REPLY 0x00

// 帧固定长度偏移
#define ETH_HEADER_LEN  14
#define IP_HEADER_LEN   20
#define ICMP_HEADER_LEN 8

// 以太网头偏移
#define OFF_ETH_DST_MAC 0
#define OFF_ETH_SRC_MAC 6
#define OFF_ETH_TYPE    12

// IP头偏移
#define OFF_IP_VER_IHL    (ETH_HEADER_LEN + 0)
#define OFF_IP_TOTAL_LEN  (ETH_HEADER_LEN + 2)
#define OFF_IP_TTL        (ETH_HEADER_LEN + 8)
#define OFF_IP_PROTO      (ETH_HEADER_LEN + 9)
#define OFF_IP_CHECKSUM   (ETH_HEADER_LEN + 10)
#define OFF_IP_SRC_IP     (ETH_HEADER_LEN + 12)
#define OFF_IP_DST_IP     (ETH_HEADER_LEN + 16)

// ICMP头偏移(Ping核心)
#define OFF_ICMP_TYPE     (ETH_HEADER_LEN + IP_HEADER_LEN + 0)
#define OFF_ICMP_CODE     (ETH_HEADER_LEN + IP_HEADER_LEN + 1)
#define OFF_ICMP_CHECKSUM (ETH_HEADER_LEN + IP_HEADER_LEN + 2)
#define OFF_ICMP_ID       (ETH_HEADER_LEN + IP_HEADER_LEN + 4)
#define OFF_ICMP_SEQ      (ETH_HEADER_LEN + IP_HEADER_LEN + 6)

// ARP帧偏移
#define OFF_ARP_HTYPE      14
#define OFF_ARP_PTYPE      16
#define OFF_ARP_HLEN       18
#define OFF_ARP_PLEN       19
#define OFF_ARP_OPCODE     20
#define OFF_ARP_SENDER_MAC 22
#define OFF_ARP_SENDER_IP  28
#define OFF_ARP_TARGET_MAC 32
#define OFF_ARP_TARGET_IP  38

// 包处理标记
#define NO_PROC     0
#define ARP_PROC    1
#define IP_PROC     2

// 全局协议变量（ip.c使用）
extern uint32 src_ip;
extern uint16 ip_total_len;

#endif /* _LCPU_GEN_H_ */