#include "inc/lcpu_general.h"
#include "inc/system.h"
#include "inc/eth.h"
#include "inc/arp.h"
#include "inc/ip.h"
#include "inc/icmp.h"

__attribute__((naked, used, section(".text.bootloader")))
void reset_entry() {
    asm volatile("j program_main\n");
}

int main() {
    program_main();
    return 0;
}

void program_main() {
    /* LED 上电自检：全亮 → 延时 → 全灭 */
    LCPU_SET_LED(0x0F);
    volatile uint32 dly = 5000000;
    while (dly--) { asm volatile("nop"); }
    LCPU_SET_LED(0x00);

    uint32 led_val = 0x01;

    while (1) {
        /* LED 心跳：每 ~1s 切换（基于硬件 rdcycle）*/
        {
            static uint32 last_toggle = 0;
            uint32 now = LCPU_LOCAL_TIME_L();
            if ((now - last_toggle) >= 50000000UL) {
                last_toggle = now;
                LCPU_SET_LED(led_val);
                led_val = (led_val == 0x08) ? 0x01 : (led_val << 1);
            }
        }

        /* 无包则继续 */
        if (LCPU_RD_EMPTY())
            continue;

        /* 弹出当前包 + 使能读 */
        LCPU_RD_START_PACKET();
        uint32 len = LCPU_RD_PKT_LEN();
        if (len == 0 || len > 2048) {
            /* 无效包：再弹一次，丢弃 */
            LCPU_RD_START_PACKET();
            continue;
        }

        /* 解析以太类型，同时预写 MAC 头到 TX FIFO */
        uint16 ptype = eth_proc();

        if (ptype == ARP_PROC) {
            arp_reply();
        } else if (ptype == IP_PROC) {
            uint16 iptype = ip_proc();
            if (iptype == ICMP_PROC) {
                icmp_reply();
            }
        }

        /* 弹到下一个包 */
        _RD(1) = 1;
    }
}
