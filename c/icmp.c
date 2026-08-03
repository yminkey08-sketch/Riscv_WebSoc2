// icmp.c
#include "lcpu_general.h"
#include "icmp.h"
#include "ip.h"
#include "eth.h"
#include <string.h>

int icmp_process(uint8_t *frame, uint16_t len)
{
    // 最小长度校验 ETH14 + IP20 + ICMP8 = 42
    if (len < (ETH_HEADER_LEN + IP_HEADER_LEN + ICMP_HEADER_LEN)) {
        return 0;
    }

    uint8_t icmp_type = frame[OFF_ICMP_TYPE];
    if (icmp_type != ICMP_ECHO_REQ) {
        return 0;
    }

    uint16_t icmp_total_len = len - OFF_ICMP_TYPE;
    uint16_t orig_cs = (frame[OFF_ICMP_CHECKSUM] << 8) | frame[OFF_ICMP_CHECKSUM + 1];

    // 临时清零计算校验和
    frame[OFF_ICMP_CHECKSUM] = 0;
    frame[OFF_ICMP_CHECKSUM + 1] = 0;
    uint16_t calc_cs = ip_calc_checksum(&frame[OFF_ICMP_TYPE], icmp_total_len);

    // 进位回卷后验证：合法校验和应满足 orig + calc = 0xFFFF
    {
        uint32_t cs_sum = (uint32_t)orig_cs + (uint32_t)calc_cs;
        while (cs_sum >> 16)
            cs_sum = (cs_sum & 0xFFFF) + (cs_sum >> 16);
        if ((uint16_t)cs_sum != 0xFFFF)
        {
            // 恢复原始校验和再退出，避免缓冲区污染
            frame[OFF_ICMP_CHECKSUM] = (orig_cs >> 8) & 0xFF;
            frame[OFF_ICMP_CHECKSUM + 1] = orig_cs & 0xFF;
            return 0;
        }
    }

    // ---------- 构造ICMP应答 ----------
    // 二层MAC: 发送方(src)→目的(dst), 本机MAC→源(src)
    memcpy(&frame[OFF_ETH_DST_MAC], &frame[OFF_ETH_SRC_MAC], 6);

    uint8_t my_mac[6];
    eth_get_mac(my_mac);
    memcpy(&frame[OFF_ETH_SRC_MAC], my_mac, 6);

    // 交换IP源目地址 + 自动重算IP校验和
    ip_swap_src_dst(frame);

    // 修改为ping应答
    frame[OFF_ICMP_TYPE] = ICMP_ECHO_REPLY;
    frame[OFF_ICMP_CODE] = 0;

    // 重新计算ICMP校验
    uint16_t new_icmp_cs = ip_calc_checksum(&frame[OFF_ICMP_TYPE], icmp_total_len);
    frame[OFF_ICMP_CHECKSUM]     = (new_icmp_cs >> 8) & 0xFF;
    frame[OFF_ICMP_CHECKSUM + 1] = new_icmp_cs & 0xFF;

    // 填充以太网最小帧60字节
    uint16_t tx_len = len;
    if (tx_len < 60)
    {
        for(uint16_t i = tx_len; i < 60; i++)
            frame[i] = 0x00;
        tx_len = 60;
    }

    eth_tx_frame(frame, tx_len);
    return 1;
}