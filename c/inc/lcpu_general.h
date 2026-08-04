#ifndef _LCPU_GEN_H_
#define _LCPU_GEN_H_

#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>

typedef unsigned char   uint8;
typedef unsigned short  uint16;
typedef unsigned int    uint32;
typedef char            int8;
typedef short           int16;
typedef int             int32;

// ===== RiscV_WebSoC 寄存器映射 =====
#define FIFO_BASE   0x80000000
#define _RD(n)      (*(volatile uint32*)(FIFO_BASE + (0x6000+(n)) * 4))
#define _WR(n)      (*(volatile uint32*)(FIFO_BASE + (0x6100+(n)) * 4))

// RX FIFO
#define LCPU_RD_EMPTY()         (_RD(0) != 0)
#define LCPU_RD_START_PACKET()  do { _RD(1) = 1; _RD(4) = 1; } while (0)
#define LCPU_RD_PKT_LEN()       ((uint16)(_RD(2) & 0xFFFFu))
#define LCPU_RD_SET_ADDR(addr)  do { _RD(5) = (uint32)(addr); } while (0)
#define LCPU_RD_INC_ADDR()      do { _RD(5)++; } while (0)
#define LCPU_RD_DATA8()         ((uint8)(_RD(6) & 0xFFu))

// TX FIFO
#define LCPU_WR_SET_ADDR(addr)  do { _WR(2) = (uint32)(addr); } while (0)
#define LCPU_WR_SET_DATA(data)  do { _WR(3) = (uint32)(data); } while (0)
#define LCPU_WR_PULSE_WEN()     do { _WR(1) = 1u; } while (0)
#define LCPU_WR_BYTE(addr, data) do { LCPU_WR_SET_ADDR(addr); LCPU_WR_SET_DATA(data); LCPU_WR_PULSE_WEN(); } while (0)
#define LCPU_WR_PUSH_PACKET(pkt_len) do { _WR(4)=(uint32)(pkt_len); _WR(6)=1u; } while (0)
#define LCPU_WR_TEST_ENABLE()   (0)  // disabled

// LED (硬件地址0x10, struct偏移0x40)
#define LCPU_BASE  0x80000000
typedef struct { uint32 _pad[16]; uint32 led; } str_my_reg;
#define LCPU_SET_LED(v)  do { ((volatile str_my_reg*)LCPU_BASE)->led = (uint32)(v); } while (0)

// ===== 网络配置 =====
#define Local_MAC_HIGH   0x00000102
#define Local_MAC_LOW    0x0405
#define Local_IP_ADDR    0xA9FE0101  // 169.254.1.1

// ===== 协议常量 =====
#define eth_header_len   14
#define ip_header_len    20
#define tcp_header_len   20

#define OFF_ETH_DST_MAC   0
#define OFF_ETH_SRC_MAC   6
#define OFF_ETH_TYPE      12
#define OFF_IP_VER_IHL    (eth_header_len+0)
#define OFF_IP_TOTAL_LEN  (eth_header_len+2)
#define OFF_IP_TTL        (eth_header_len+8)
#define OFF_IP_PROTO      (eth_header_len+9)
#define OFF_IP_CHECKSUM   (eth_header_len+10)
#define OFF_IP_SRC_IP     (eth_header_len+12)
#define OFF_IP_DST_IP     (eth_header_len+16)
#define OFF_TCP_SRC_PORT  (eth_header_len+ip_header_len+0)
#define OFF_TCP_DST_PORT  (eth_header_len+ip_header_len+2)
#define OFF_TCP_SEQ_NUM   (eth_header_len+ip_header_len+4)
#define OFF_TCP_ACK_NUM   (eth_header_len+ip_header_len+8)
#define OFF_TCP_DATA_OFS  (eth_header_len+ip_header_len+12)
#define OFF_TCP_FLAGS     (eth_header_len+ip_header_len+13)
#define OFF_TCP_WINDOW    (eth_header_len+ip_header_len+14)
#define OFF_TCP_CHECKSUM  (eth_header_len+ip_header_len+16)
#define OFF_TCP_PAYLOAD   (eth_header_len+ip_header_len+tcp_header_len)

#define IP_OFS_TOTAL_LEN  2
#define IP_OFS_PROTO      9
#define IP_OFS_CHECKSUM   10
#define IP_OFS_SRC_IP     12
#define IP_OFS_DST_IP     16

#define OFF_ARP_HTYPE      14
#define OFF_ARP_PTYPE      16
#define OFF_ARP_HLEN       18
#define OFF_ARP_PLEN       19
#define OFF_ARP_OPCODE     20
#define OFF_ARP_SENDER_MAC 22
#define OFF_ARP_SENDER_IP  28
#define OFF_ARP_TARGET_MAC 32
#define OFF_ARP_TARGET_IP  38

#define ETH_TYPE_IP   0x0800
#define ETH_TYPE_ARP  0x0806
#define IP_PROTOCOL_ICMP  0x01
#define IP_PROTOCOL_UDP   0x11
#define IP_PROTOCOL_TCP   0x06
#define ARP_REQUEST     0x0001
#define ICMP_REQUEST    0x08
#define HTTP_PORT  80

#define NO_PROC     0x0000
#define ARP_PROC    0x0001
#define IP_PROC     0x1000
#define ICMP_PROC   0x1100
#define TCP_PROC    0x1200
#define HTTP_PROC   0x1201
#define UDP_PROC    0x1300

#define TCP_TIMEWAIT_TICKS      100000000u
#define TCP_IDLE_TIMEOUT_TICKS  2000000000u
#define TCP_SYN_RETRY_TICKS     150000000u
#define TCP_SYN_MAX_RETRIES     3

// 系统寄存器访问 (用于 HTTP POST 读写寄存器)
#define LCPU_REG32_WRITE(word_addr, data)  do { *((volatile uint32*)(LCPU_BASE + (word_addr)*4)) = (uint32)(data); } while (0)
#define LCPU_REG32_READ(word_addr)         (*((volatile uint32*)(LCPU_BASE + (word_addr)*4)))

// 软件定时器 (用 RISC-V cycle 计数替代硬件定时器)
static inline uint32 LCPU_LOCAL_TIME_L(void) {
    uint32 t;
    asm volatile("rdcycle %0" : "=r"(t));
    return t;
}
#define LCPU_SECOND_EVENT()  ((LCPU_LOCAL_TIME_L() & 0x2000000) != 0)  // ~1Hz toggle

// 调试 (禁用)
#define LCPU_DBG_READ(idx)      0
#define LCPU_DBG_WRITE(idx, v)  do {} while(0)

extern uint32 src_ip;
extern uint16 src_port;
extern uint16 ip_total_len;

#endif /* _LCPU_GEN_H_ */
