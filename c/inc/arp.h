#ifndef _ARP_H_
#define _ARP_H_
#include "lcpu_general.h"

// ARP单条缓存结构体，只存一台主机
typedef struct {
    bool valid;
    uint32_t ip;
    uint8_t mac[6];
} arp_cache_t;

// 初始化ARP缓存
void arp_init(void);
// 根据IP查询缓存MAC，成功返回1，无缓存返回0
int arp_get_mac(uint32_t ip, uint8_t *mac);
// 处理ARP帧，收到请求自动回复应答，返回1处理成功，0忽略
int arp_process(uint8_t *frame, uint16_t len);

#endif