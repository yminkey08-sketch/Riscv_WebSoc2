// ip.c
#include "lcpu_general.h"
#include "ip.h"
#include "icmp.h"
#include <string.h>

// ==========================================================
// 1. 全局变量：缓存发送方IP（供 ICMP 回复使用，可选）
// ==========================================================
uint32 g_ip_sender = 0;   // 在 ip.h 中声明为 extern 供 icmp.c 使用

// ==========================================================
// 2. 安全 IP 校验和计算（逐字节累加，无对齐问题）
// ==========================================================
uint16_t ip_calc_checksum(const uint8_t *data, uint16_t byte_len)
{
    // 【修复点 1】防止 byte_len 为 0 时访问 data[-1] 导致越界
    if (byte_len == 0) return 0xFFFF;

    uint32 sum = 0;
    uint16_t word_cnt = byte_len / 2;

    // 按 16 位累加
    for (uint16_t i = 0; i < word_cnt; i++) {
        uint16_t w = (data[i*2] << 8) | data[i*2 + 1];
        sum += w;
        // 进位回卷（可能多次进位，用 while 保证）
        while (sum >> 16)
            sum = (sum & 0xFFFF) + (sum >> 16);
    }

    // 处理奇数长度的最后一个字节（当作高字节）
    if (byte_len & 1) {
        sum += (uint16_t)(data[byte_len - 1] << 8);
        while (sum >> 16)
            sum = (sum & 0xFFFF) + (sum >> 16);
    }

    // 返回反码
    return (uint16_t)(~sum);
}

// ==========================================================
// 3. 交换 IP 源/目的地址，并自动重算 IP 校验和
// ==========================================================
void ip_swap_src_dst(uint8_t *frame)
{
    uint8_t tmp_ip[4];

    // 交换源IP和目的IP
    memcpy(tmp_ip, &frame[OFF_IP_SRC_IP], 4);
    memcpy(&frame[OFF_IP_SRC_IP], &frame[OFF_IP_DST_IP], 4);
    memcpy(&frame[OFF_IP_DST_IP], tmp_ip, 4);

    // 清空原校验和，重新计算
    frame[OFF_IP_CHECKSUM] = 0;
    frame[OFF_IP_CHECKSUM + 1] = 0;
    uint16_t new_cs = ip_calc_checksum(&frame[OFF_IP_VER_IHL], IP_HEADER_LEN);
    frame[OFF_IP_CHECKSUM]     = (new_cs >> 8) & 0xFF;
    frame[OFF_IP_CHECKSUM + 1] = new_cs & 0xFF;
}

// ==========================================================
// 4. IP 包主处理函数
// ==========================================================
int ip_process(uint8_t *frame, uint16_t len)
{
    // 4.1 最小长度检查：ETH(14) + IP头(20) = 34
    if (len < (ETH_HEADER_LEN + IP_HEADER_LEN))
        return 0;

    // 4.2 检查版本和头长度：只支持 IPv4，头长 20 字节（无选项）
    uint8_t ver_ihl = frame[OFF_IP_VER_IHL];
    if (((ver_ihl >> 4) != 4) || ((ver_ihl & 0x0F) != 5))
        return 0;

    // 4.3 验证 IP 头校验和（使用临时副本，不污染原始帧）
    uint8_t ip_hdr_tmp[IP_HEADER_LEN];
    memcpy(ip_hdr_tmp, &frame[OFF_IP_VER_IHL], IP_HEADER_LEN);

    // 备份原校验和
    uint16_t orig_csum = (ip_hdr_tmp[OFF_IP_CHECKSUM - OFF_IP_VER_IHL] << 8)
                       | ip_hdr_tmp[OFF_IP_CHECKSUM - OFF_IP_VER_IHL + 1];
    // 清零后计算
    ip_hdr_tmp[OFF_IP_CHECKSUM - OFF_IP_VER_IHL] = 0;
    ip_hdr_tmp[OFF_IP_CHECKSUM - OFF_IP_VER_IHL + 1] = 0;
    uint16_t calc_csum = ip_calc_checksum(ip_hdr_tmp, IP_HEADER_LEN);

    // 进位回卷后验证：合法头校验和应满足 orig + calc = 0xFFFF
    uint32_t sum = (uint32_t)orig_csum + (uint32_t)calc_csum;
    while (sum >> 16)
        sum = (sum & 0xFFFF) + (sum >> 16);
    if ((uint16_t)sum != 0xFFFF)
        return 0;   // 校验失败，丢弃

    // 4.4 检查目的 IP 是否为本机
    uint32_t dst_ip = ((uint32_t)frame[OFF_IP_DST_IP] << 24)
                    | ((uint32_t)frame[OFF_IP_DST_IP + 1] << 16)
                    | ((uint32_t)frame[OFF_IP_DST_IP + 2] << 8)
                    | (uint32_t)frame[OFF_IP_DST_IP + 3];
    if (dst_ip != LOCAL_IP_ADDR)
        return 0;   // 不是发给本机的，丢弃

    // 4.5 缓存源 IP（供 ICMP 回复使用）
    g_ip_sender = ((uint32_t)frame[OFF_IP_SRC_IP] << 24)
                | ((uint32_t)frame[OFF_IP_SRC_IP + 1] << 16)
                | ((uint32_t)frame[OFF_IP_SRC_IP + 2] << 8)
                | (uint32_t)frame[OFF_IP_SRC_IP + 3];

    // 4.6 根据协议号分发
    uint8_t protocol = frame[OFF_IP_PROTO];
    if (protocol == IP_PROTO_ICMP) {
        // 交给 ICMP 处理，它会调用 ip_swap_src_dst 并重算校验和
        return icmp_process(frame, len);
    }

    // 其它协议（UDP/TCP）暂不支持
    return 0;
}