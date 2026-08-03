// ip.h
#ifndef _IP_H_
#define _IP_H_

#include <stdint.h>
#include <stdbool.h>

// 计算 IP/ICMP 校验和（16位反码求和，可处理奇数长度）
uint16_t ip_calc_checksum(const uint8_t *data, uint16_t byte_len);

// 交换 IP 头中的源 IP 和目的 IP，并自动重算 IP 头校验和
// 参数：指向以太网帧（含14字节头）的指针
void ip_swap_src_dst(uint8_t *frame);

// IP 包主处理函数（由 main.c 调用）
int ip_process(uint8_t *frame, uint16_t len);

#endif