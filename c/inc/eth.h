#ifndef _ETH_H_
#define _ETH_H_
#include "lcpu_general.h"

// 收包：返回0成功，-1无包，-2超长包丢弃
int eth_rx_frame(uint8_t *buf, uint16_t *len);
// 发包：内存缓冲区整帧写入TX FIFO推送发送
void eth_tx_frame(const uint8_t *buf, uint16_t len);
// 拷贝本机MAC到外部数组
void eth_get_mac(uint8_t *mac);

#endif