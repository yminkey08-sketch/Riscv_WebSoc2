// eth.c
#include "lcpu_general.h"
#include "eth.h"
#include <string.h>

static const uint8_t my_mac[6] = {
    LOCAL_MAC_BYTE0,
    LOCAL_MAC_BYTE1,
    LOCAL_MAC_BYTE2,
    LOCAL_MAC_BYTE3,
    LOCAL_MAC_BYTE4,
    LOCAL_MAC_BYTE5
};

// 从硬件RX FIFO读取一整帧到内存buf
int eth_rx_frame(uint8_t *buf, uint16_t *len)
{
    if (LCPU_RD_EMPTY()) {
        return -1;
    }
    LCPU_RD_START_PACKET();
    *len = LCPU_RD_PKT_LEN();
    if (*len > ETH_MAX_FRAME_LEN) {
        *len = 0;
        LCPU_RD_STOP();
        HW_REG8(REG_RX_PKT_POP) = 1; // 丢弃畸形包
        return -2;
    }
    for (uint16_t i = 0; i < *len; i++) {
        LCPU_RD_SET_ADDR(i);
        buf[i] = LCPU_RD_DATA8();
    }
    LCPU_RD_STOP();
    HW_REG8(REG_RX_PKT_POP) = 1; // 关键：弹出当前包，不会重复接收
    return 0;
}

// 将内存缓冲区整帧写入TX FIFO并推送发送
void eth_tx_frame(const uint8_t *buf, uint16_t len)
{
    if (len == 0) return; // 禁止发送空包

    uint32_t timeout = 1000000; // 加入超时保护
    while (LCPU_WR_FULL() && timeout--) ;
    if (timeout == 0) return;    // 超时放弃发送

    // 先写数据
    for (uint16_t i = 0; i < len; i++) {
        timeout = 1000000;
        while (LCPU_WR_FULL() && timeout--) ;
        if (timeout == 0) return;

        reg32_write(REG_TX_WADDR, (uint32_t)i);
        reg32_write(REG_TX_WDATA, (uint32_t)buf[i]);
        LCPU_WR_PULSE_WEN();
    }
    // 写长度 → 推送发送
    reg32_write(REG_TX_PKT_LEN, (uint32_t)len);
    HW_REG8(REG_TX_PKT_PUSH) = 1;
}

// 拷贝本机MAC
void eth_get_mac(uint8_t *mac)
{
    memcpy(mac, my_mac, 6);
}