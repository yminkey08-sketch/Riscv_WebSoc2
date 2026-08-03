// main.c
#define SIM_FAST  // 仿真加速：跳过上电自检延时 (上板时注释此行)
#include "lcpu_general.h"
#include "eth.h"
#include "arp.h"
#include "ip.h"
#include <stdint.h>

// ==========================================================
// 复位入口 — CPU上电后PC=0, 从这里开始执行
// ==========================================================
__attribute__((naked, used, section(".text.bootloader")))
void reset_entry() {
    asm volatile("j main\n");      // 无条件跳转到 main()
}

// 缓冲区（静态分配，防止栈溢出）
static uint8_t rx_buffer[ETH_MAX_FRAME_LEN];

// ===================== 时序宏定义 50MHz =====================
#define CPU_FREQ_HZ              50000000UL
#define LED_FLOW_INTERVAL_TICKS 6250000UL   // 125ms
#define LED_BLINK_STEP_TICKS     2500000UL   // 50ms

// ==========================================================
// 软件延时（仅初始化使用）
// ==========================================================
static inline void delay_us(uint32_t n)
{
#ifdef SIM_FAST
    (void)n;  // 仿真加速：跳过延时
#else
    volatile uint32_t cnt = n * 12;
    while (cnt--) {
        __asm__ volatile ("nop");
    }
#endif
}

// ==========================================================
// LED状态变量
// ==========================================================
static uint32_t last_flow_ticks = 0;
static uint8_t  current_led     = 0;           // 0~3

static uint8_t  led_blink_pending = 0;
static uint32_t blink_start_ticks = 0;
static uint8_t  blink_phase       = 0;         // 0~4

// lcpu_local_time_l() 在 lcpu_general.h 中定义 (static inline)

// ==========================================================
// LED状态机更新（非阻塞，主循环持续调用）
// ==========================================================
static inline void led_flow_update(void)
{
    uint32_t now = lcpu_local_time_l();

    // 网络活动闪烁 优先执行
    if (led_blink_pending)
    {
        switch (blink_phase)
        {
            case 0:
                LCPU_SET_LED(0x00);
                blink_start_ticks = now;
                blink_phase = 1;
                break;
            case 1: //亮
                if (now - blink_start_ticks >= LED_BLINK_STEP_TICKS)
                {
                    LCPU_SET_LED(1u << current_led);
                    blink_start_ticks = now;
                    blink_phase = 2;
                }
                break;
            case 2: //灭
                if (now - blink_start_ticks >= LED_BLINK_STEP_TICKS)
                {
                    LCPU_SET_LED(0x00);
                    blink_start_ticks = now;
                    blink_phase = 3;
                }
                break;
            case 3: //亮
                if (now - blink_start_ticks >= LED_BLINK_STEP_TICKS)
                {
                    LCPU_SET_LED(1u << current_led);
                    blink_start_ticks = now;
                    blink_phase = 4;
                }
                break;
            case 4: //灭，恢复流水灯
                if (now - blink_start_ticks >= LED_BLINK_STEP_TICKS)
                {
                    LCPU_SET_LED(0x00);
                    led_blink_pending = 0;
                    blink_phase = 0;
                    last_flow_ticks = now;
                }
                break;
            default:
                led_blink_pending = 0;
                blink_phase = 0;
                break;
        }
        return;
    }

    // 常规流水灯
    if (now - last_flow_ticks >= LED_FLOW_INTERVAL_TICKS)
    {
        LCPU_SET_LED(0x00);
        current_led = (current_led + 1) & 0x03;
        LCPU_SET_LED(1u << current_led);
        last_flow_ticks = now;
    }
}

// 触发网络闪烁
static inline void trigger_network_blink(void)
{
    if (!led_blink_pending)
    {
        led_blink_pending = 1;
        blink_phase = 0;
    }
}

// ==========================================================
// 主入口
// ==========================================================
int main(void)
{
    uint16_t len;

    arp_init();

    // 上电自检：全亮100ms
    LCPU_SET_LED(0x0F);
    delay_us(100000);
    LCPU_SET_LED(0x00);
    delay_us(100000);

    uint8_t my_mac[6];
    eth_get_mac(my_mac);

    last_flow_ticks = lcpu_local_time_l();

    while (1)
    {
        led_flow_update();

        if (eth_rx_frame(rx_buffer, &len) == 0)
        {
            if (len > ETH_MAX_FRAME_LEN)
                continue;

            uint16_t eth_type = (rx_buffer[OFF_ETH_TYPE] << 8) | rx_buffer[OFF_ETH_TYPE + 1];

            if (eth_type == ETH_TYPE_ARP)
            {
                if (arp_process(rx_buffer, len) == 1)
                {
                    trigger_network_blink();
                }
            }
            else if (eth_type == ETH_TYPE_IP)
            {
                if (ip_process(rx_buffer, len) == 1)
                {
                    trigger_network_blink();
                }
            }
        }
    }

    return 0;
}