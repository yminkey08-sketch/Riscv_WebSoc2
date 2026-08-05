// main.c — RISC-V WebSoC Ping+TCP 固件入口
#include "inc/lcpu_general.h"
#include "inc/eth.h"
#include "inc/arp.h"
#include "inc/ip.h"
#include "inc/icmp.h"
#include "inc/tcp.h"

__attribute__((naked, used, section(".text.bootloader")))
void reset_entry(void)
{
    __asm__ volatile("j program_main\n");
}

void program_main(void)
{
    LCPU_SET_LED(0x0F);
    volatile uint32_t dly = 5000000;
    while (dly--) { __asm__ volatile("nop"); }
    LCPU_SET_LED(0x00);

    tcp_connection_init();

    uint32_t led_val = 0x01;

    while (1) {
        {
            static uint32_t last_toggle = 0;
            uint32_t now = LCPU_LOCAL_TIME_L();
            if ((now - last_toggle) >= 50000000UL) {
                last_toggle = now;
                LCPU_SET_LED(led_val);
                led_val = (led_val == 0x08) ? 0x01 : (led_val << 1);
            }
        }

        if (LCPU_RD_EMPTY())
            continue;

        LCPU_RD_START_PACKET();
        uint32_t len = LCPU_RD_PKT_LEN();
        if (len == 0 || len > 2048) {
            LCPU_RD_START_PACKET();
            continue;
        }

        uint16_t ptype = eth_proc();

        if (ptype == ARP_PROC) {
            arp_reply();
        } else if (ptype == IP_PROC) {
            uint16_t iptype = ip_proc();
            if (iptype == ICMP_PROC) {
                icmp_reply();
            } else if (iptype == TCP_PROC) {
                tcp_packet_handler();
            }
        }

        _RD(1) = 1;
    }
}
