#include "inc/lcpu_general.h"
#include "inc/comlib.h"

/*
 * cks_sum_cal — 16位校验和累加
 * 用于 IP/ICMP 校验和计算
 */
uint16 cks_sum_cal(uint32 a, uint32 b, uint16 c) {
    uint32 sum = (a << 8 | b) + c;
    while (sum >> 16) {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }
    return sum & 0xFFFF;
}
