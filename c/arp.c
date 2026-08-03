// arp.c
#include "lcpu_general.h"
#include "arp.h"
#include "eth.h"
#include <string.h>

// 1. ARP 缓存（静态全局变量，只缓存一台 PC）
static arp_cache_t arp_cache = { .valid = false, .ip = 0, .mac = {0} };

// 2. 初始化（清空缓存）
void arp_init(void) {
    arp_cache.valid = false;
    arp_cache.ip = 0;
    memset(arp_cache.mac, 0, 6);
}

// 3. 获取缓存 MAC（供上层调用）
int arp_get_mac(uint32_t ip, uint8_t *mac) {
    if (arp_cache.valid && arp_cache.ip == ip) {
        memcpy(mac, arp_cache.mac, 6);
        return 1;
    }
    return 0;
}

// 4. 核心：ARP 处理函数
int arp_process(uint8_t *frame, uint16_t len) {
    // 最小ARP帧校验
    if(len < 42) return 0;

    // 4.1 检查以太网类型是否为 ARP (0x0806)
    uint16_t eth_type = (frame[OFF_ETH_TYPE] << 8) | frame[OFF_ETH_TYPE + 1];
    if (eth_type != ETH_TYPE_ARP) {
        return 0;
    }

    // 4.2 校验ARP硬件/协议类型、地址长度
    if (frame[OFF_ARP_HTYPE] != 0x00 || frame[OFF_ARP_HTYPE+1] != 0x01) return 0;
    if (frame[OFF_ARP_PTYPE] != 0x08 || frame[OFF_ARP_PTYPE+1] != 0x00) return 0;
    if (frame[OFF_ARP_HLEN] != 6 || frame[OFF_ARP_PLEN] != 4) return 0;

    // 4.3 读取操作码
    uint16_t opcode = (frame[OFF_ARP_OPCODE] << 8) | frame[OFF_ARP_OPCODE + 1];
    if (opcode != ARP_REQUEST) {
        return 0;
    }

    // 4.4 对比目标IP是否为本机
    uint32_t target_ip = 
        ((uint32_t)frame[OFF_ARP_TARGET_IP] << 24) |
        ((uint32_t)frame[OFF_ARP_TARGET_IP + 1] << 16) |
        ((uint32_t)frame[OFF_ARP_TARGET_IP + 2] << 8) |
        (uint32_t)frame[OFF_ARP_TARGET_IP + 3];
    if (target_ip != LOCAL_IP_ADDR) {
        return 0;
    }

    // 4.5 提取请求方MAC、IP，更新ARP缓存
    uint8_t *sender_mac = &frame[OFF_ARP_SENDER_MAC];
    uint32_t sender_ip = 
        ((uint32_t)frame[OFF_ARP_SENDER_IP] << 24) |
        ((uint32_t)frame[OFF_ARP_SENDER_IP + 1] << 16) |
        ((uint32_t)frame[OFF_ARP_SENDER_IP + 2] << 8) |
        (uint32_t)frame[OFF_ARP_SENDER_IP + 3];

    arp_cache.valid = true;
    arp_cache.ip = sender_ip;
    memcpy(arp_cache.mac, sender_mac, 6);

    // 4.6 二层MAC: 发送方(src)变为新目的(dst)，本机MAC成为新源(src)
    memcpy(&frame[OFF_ETH_DST_MAC], &frame[OFF_ETH_SRC_MAC], 6);

    // 4.7 写入本机MAC作为回复源MAC
    uint8_t my_mac[6];
    eth_get_mac(my_mac);
    memcpy(&frame[OFF_ETH_SRC_MAC], my_mac, 6);

    // 4.8 修改ARP操作码为ARP应答 00 02
    frame[OFF_ARP_OPCODE] = 0x00;
    frame[OFF_ARP_OPCODE + 1] = 0x02;

    // 4.9 ARP载荷：发送端为本机，目标端为请求主机
    memcpy(&frame[OFF_ARP_TARGET_MAC], sender_mac, 6);
    frame[OFF_ARP_TARGET_IP]     = (sender_ip >> 24) & 0xFF;
    frame[OFF_ARP_TARGET_IP + 1] = (sender_ip >> 16) & 0xFF;
    frame[OFF_ARP_TARGET_IP + 2] = (sender_ip >> 8)  & 0xFF;
    frame[OFF_ARP_TARGET_IP + 3] = sender_ip         & 0xFF;

    memcpy(&frame[OFF_ARP_SENDER_MAC], my_mac, 6);
    frame[OFF_ARP_SENDER_IP]     = (LOCAL_IP_ADDR >> 24) & 0xFF;
    frame[OFF_ARP_SENDER_IP + 1] = (LOCAL_IP_ADDR >> 16) & 0xFF;
    frame[OFF_ARP_SENDER_IP + 2] = (LOCAL_IP_ADDR >> 8)  & 0xFF;
    frame[OFF_ARP_SENDER_IP + 3] = LOCAL_IP_ADDR         & 0xFF;

    // 4.10 填充至60字节最小以太网帧
    uint16_t tx_len = 42;
    for(uint16_t i = tx_len; i < 60; i++) {
        frame[i] = 0x00;
    }
    tx_len = 60;
    eth_tx_frame(frame, tx_len);
    return 1;
}