// Verilator C++ testbench — uses --timing #delay clocks (MMCM stub generates 125MHz)
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vvtop.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>

static const uint8_t BC_MAC[6]   = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
static const uint8_t PC_MAC[6]   = {0x00,0x11,0x22,0x33,0x44,0x55};
static const uint8_t FPGA_MAC[6] = {0x00,0x00,0x01,0x02,0x04,0x05};
static const uint8_t PC_IP[4]    = {0xA9,0xFE,0x23,0xBA};
static const uint8_t FPGA_IP[4]  = {0xA9,0xFE,0x01,0x01};

// Internet checksum (1's complement sum of 16-bit big-endian words)
static uint16_t checksum(const uint8_t *buf, int len) {
    uint32_t sum = 0;
    for (int i = 0; i < len; i += 2) {
        uint16_t word = (uint16_t)(buf[i] << 8);
        if (i + 1 < len) word |= buf[i + 1];
        sum += word;
    }
    while (sum >> 16) sum = (sum & 0xFFFF) + (sum >> 16);
    return (uint16_t)(~sum & 0xFFFF);
}

// TCP checksum (IP pseudo-header + TCP header + payload)
static uint16_t tcp_checksum(const uint8_t *tcp, int tcp_len,
                             const uint8_t *sip, const uint8_t *dip,
                             const uint8_t *data, int data_len) {
    uint32_t sum = 0;
    sum += ((uint16_t)sip[0] << 8) | sip[1];
    sum += ((uint16_t)sip[2] << 8) | sip[3];
    sum += ((uint16_t)dip[0] << 8) | dip[1];
    sum += ((uint16_t)dip[2] << 8) | dip[3];
    sum += 6;  // protocol TCP
    sum += tcp_len + data_len;
    for (int i = 0; i < tcp_len; i += 2)
        sum += ((uint16_t)tcp[i] << 8) | tcp[i + 1];
    for (int i = 0; i < data_len; i += 2) {
        uint16_t w = (uint16_t)data[i] << 8;
        if (i + 1 < data_len) w |= data[i + 1];
        sum += w;
    }
    while (sum >> 16) sum = (sum & 0xFFFF) + (sum >> 16);
    return (uint16_t)(~sum & 0xFFFF);
}

// Build a full Ethernet+IPv4+TCP frame. Returns total length (14 + 20 + 20 + data).
static int build_tcp(uint8_t *pkt,
                     const uint8_t *dmac, const uint8_t *smac,
                     const uint8_t *sip, const uint8_t *dip,
                     uint16_t sport, uint16_t dport,
                     uint32_t seq, uint32_t ack, uint8_t flags,
                     const uint8_t *data, int data_len) {
    int ip_total = 20 + 20 + data_len;
    int total = 14 + ip_total;
    memset(pkt, 0, total);
    memcpy(pkt, dmac, 6); memcpy(pkt + 6, smac, 6);
    pkt[12] = 0x08; pkt[13] = 0x00;                 // ethertype IPv4
    pkt[14] = 0x45; pkt[15] = 0x00;                 // ver 4, IHL 5, TOS 0
    pkt[16] = (ip_total >> 8) & 0xFF; pkt[17] = ip_total & 0xFF;
    pkt[18] = 0x00; pkt[19] = 0x01;                 // identification
    pkt[20] = 0x00; pkt[21] = 0x00;                 // flags/frag
    pkt[22] = 0x40;                                 // TTL
    pkt[23] = 6;                                    // protocol TCP
    memcpy(pkt + 26, sip, 4); memcpy(pkt + 30, dip, 4);
    uint8_t *t = pkt + 34;                          // TCP header
    t[0] = (sport >> 8) & 0xFF; t[1] = sport & 0xFF;
    t[2] = (dport >> 8) & 0xFF; t[3] = dport & 0xFF;
    t[4] = (seq >> 24) & 0xFF; t[5] = (seq >> 16) & 0xFF;
    t[6] = (seq >> 8) & 0xFF;  t[7] = seq & 0xFF;
    t[8] = (ack >> 24) & 0xFF; t[9] = (ack >> 16) & 0xFF;
    t[10] = (ack >> 8) & 0xFF; t[11] = ack & 0xFF;
    t[12] = 0x50; t[13] = flags;
    t[14] = 0xFF; t[15] = 0xFF;                     // window
    if (data && data_len > 0) memcpy(pkt + 54, data, data_len);
    uint16_t ip_cs = checksum(pkt + 14, 20);
    pkt[24] = (ip_cs >> 8) & 0xFF; pkt[25] = ip_cs & 0xFF;
    uint16_t tc_cs = tcp_checksum(t, 20, sip, dip, data, data_len);
    t[16] = (tc_cs >> 8) & 0xFF; t[17] = tc_cs & 0xFF;
    return total;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    VerilatedContext *contextp = new VerilatedContext;
    Vvtop *top = new Vvtop{contextp};

    Verilated::traceEverOn(true);
    VerilatedVcdC *tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("sim_verilator.vcd");

    // Init inputs (clocks are #delay-generated inside MMCM stub)
    top->clk_50m_in = 0;      // crystal — unused (MMCM free-runs)
    top->reset_l = 0;
    top->sim_gmii_rx_dv = 0;
    top->sim_gmii_rx_clk = 0;
    top->sim_gmii_rxd = 0;

    // ARP request (42 bytes)
    uint8_t arp[42] = {0};
    memcpy(arp, BC_MAC, 6); memcpy(arp+6, PC_MAC, 6);
    arp[12]=0x08; arp[13]=0x06;
    arp[14]=0x00; arp[15]=0x01; arp[16]=0x08; arp[17]=0x00;
    arp[18]=0x06; arp[19]=0x04; arp[20]=0x00; arp[21]=0x01;
    memcpy(arp+22, PC_MAC, 6); memcpy(arp+28, PC_IP, 4);
    memset(arp+32, 0, 6); memcpy(arp+38, FPGA_IP, 4);

    // ICMP echo request (ping) — 14 eth + 20 IP + 8 ICMP + 32 data = 74 bytes
    uint8_t icmp[74] = {0};
    memcpy(icmp+0,  FPGA_MAC, 6);   // dst = FPGA
    memcpy(icmp+6,  PC_MAC, 6);     // src = PC
    icmp[12]=0x08; icmp[13]=0x00;   // ethertype = IPv4
    icmp[14]=0x45;                  // ver 4, IHL 5
    icmp[15]=0x00;                  // TOS
    icmp[16]=0x00; icmp[17]=60;     // total len = 20 + 8 + 32 = 60
    icmp[18]=0x00; icmp[19]=0x01;   // identification
    icmp[20]=0x00; icmp[21]=0x00;   // flags/fragment
    icmp[22]=0x40;                  // TTL = 64
    icmp[23]=0x01;                  // protocol = ICMP
    icmp[24]=0x00; icmp[25]=0x00;   // header checksum (filled below)
    memcpy(icmp+26, PC_IP, 4);      // src IP
    memcpy(icmp+30, FPGA_IP, 4);    // dst IP
    icmp[34]=0x08;                  // ICMP type = echo request
    icmp[35]=0x00;                  // code
    icmp[36]=0x00; icmp[37]=0x00;   // checksum (filled below)
    icmp[38]=0x00; icmp[39]=0x01;   // identifier
    icmp[40]=0x00; icmp[41]=0x01;   // sequence
    for (int i = 0; i < 32; i++) icmp[42+i] = (uint8_t)i;  // payload 0x00..0x1F
    uint16_t ip_cs = checksum(icmp+14, 20);
    icmp[24] = (uint8_t)(ip_cs >> 8); icmp[25] = (uint8_t)(ip_cs & 0xFF);
    uint16_t icmp_cs = checksum(icmp+34, 40);
    icmp[36] = (uint8_t)(icmp_cs >> 8); icmp[37] = (uint8_t)(icmp_cs & 0xFF);

    // TCP SYN (PC -> FPGA port 80)
    const uint16_t PC_TCP_PORT = 12345;
    const uint16_t FPGA_TCP_PORT = 80;
    const uint32_t PC_SEQ = 0x1000;
    uint8_t syn_pkt[64];
    int syn_len = build_tcp(syn_pkt, FPGA_MAC, PC_MAC, PC_IP, FPGA_IP,
                            PC_TCP_PORT, FPGA_TCP_PORT, PC_SEQ, 0, 0x02 /*SYN*/, NULL, 0);
    // ACK + HTTP GET — built dynamically after parsing SYN+ACK's FPGA seq number
    uint8_t ack_pkt[64];   int ack_len = 0;
    uint8_t http_pkt[512]; int http_len = 0;
    const char http_get[] = "GET / HTTP/1.1\r\nHost: 169.254.1.1\r\nConnection: close\r\n\r\n";
    int http_get_len = (int)strlen(http_get);

    // Timing constants (ps): 50MHz=20000ps, 125MHz=8000ps
    const vluint64_t RESET_END = 20000;                     // 1 cycle reset
    const vluint64_t ARP_START = RESET_END + 1000*20000;    // wait for firmware init
    const vluint64_t ARP_END   = ARP_START + (8+42)*8000;
    const vluint64_t ICMP_START = 300000ULL * 1000;         // 300us — after ARP reply
    const vluint64_t ICMP_END   = ICMP_START + (8+74)*8000;
    const vluint64_t TCP_SYN_START  = 1500000ULL * 1000;    // 1.5ms
    const vluint64_t TCP_SYN_END    = TCP_SYN_START + (8+syn_len)*8000;
    const vluint64_t TCP_ACK_START  = 2500000ULL * 1000;    // 2.5ms — after SYN+ACK parsed
    const vluint64_t TCP_ACK_END    = TCP_ACK_START + (8+54)*8000;
    const vluint64_t TCP_HTTP_START = 2700000ULL * 1000;    // 2.7ms — after ACK processed
    const vluint64_t TCP_HTTP_END   = TCP_HTTP_START + (8+54+http_get_len)*8000;
    const vluint64_t SIM_END        = TCP_HTTP_START + 10000000ULL*1000;  // +10ms for HTTP page TX

    printf("=== RiscV WebSoC2 + #delay 125MHz clock ===\n\n");

    int prev_rd_empty = 1, prev_tx_en = 0, prev_mtx_en = 0, prev_bus_req = 0;
    int tx_started = -1, mtx_started = -1;
    int bus_activity = 0;
    int prev_mac_sop = 0, prev_mac_en = 0, prev_mac_eop = 0, prev_pres = 0;
    int mac_en_count = 0, pres_count = 0;
    int prev_wpkt_push = 0, prev_wpkt_len = -1;
    int prev_para_wen = 0, prev_rpkt_pop = 0;
    int pending_read = 0;
    unsigned pending_read_addr = 0;
    unsigned char txbuf[2048];
    int txbuf_len = 0;
    vluint64_t last_tx_cap = 0;
    int tx_pkt_idx = 0;

    while (!contextp->gotFinish()) {
        top->eval();
        if (top->eventsPending()) {
            vluint64_t now = top->nextTimeSlot();
            contextp->timeInc(now - contextp->time());
            vluint64_t t = contextp->time();

            // Drive GMII RX clock at 125MHz. Rising edges MUST land on data byte
            // midpoints (t = ARP_START + 8000*m + 4000 = 8000*k), which are all
            // multiples of 4000 so the #delay eval loop always visits them.
            // Old formula (((t+2000)/4000)%2) put rising edges at t=2000+8000k,
            // which the loop skipped -> 0x00 byte was dropped (1-byte shift).
            top->sim_gmii_rx_clk = ((t / 4000) % 2 == 0) ? 1 : 0;

            // Reset
            top->reset_l = (t < RESET_END) ? 0 : 1;

            // GMII RX: ARP -> ICMP -> TCP SYN -> ACK -> HTTP GET, byte per 125MHz cycle
            const uint8_t *pkt = 0;
            int pkt_len = 0;
            vluint64_t pkt_start = 0;
            if (t >= ARP_START && t < ARP_END) {
                pkt = arp; pkt_len = 42; pkt_start = ARP_START;
            } else if (t >= ICMP_START && t < ICMP_END) {
                pkt = icmp; pkt_len = 74; pkt_start = ICMP_START;
            } else if (t >= TCP_SYN_START && t < TCP_SYN_END) {
                pkt = syn_pkt; pkt_len = syn_len; pkt_start = TCP_SYN_START;
            } else if (t >= TCP_ACK_START && t < TCP_ACK_END && ack_len > 0) {
                pkt = ack_pkt; pkt_len = ack_len; pkt_start = TCP_ACK_START;
            } else if (t >= TCP_HTTP_START && t < TCP_HTTP_END && http_len > 0) {
                pkt = http_pkt; pkt_len = http_len; pkt_start = TCP_HTTP_START;
            }
            if (pkt) {
                vluint64_t byte_idx = (t - pkt_start) / 8000;
                top->sim_gmii_rx_dv = 1;
                if (byte_idx < 7) {
                    top->sim_gmii_rxd = 0x55;        // preamble
                } else if (byte_idx == 7) {
                    top->sim_gmii_rxd = 0xD5;        // SFD
                } else {
                    top->sim_gmii_rxd = pkt[byte_idx - 8];
                }
            } else {
                top->sim_gmii_rx_dv = 0;
                top->sim_gmii_rxd = 0;
            }

            // Monitor
            int rd = top->sim_cpu_rd_empty;
            int tx = top->sim_gmii_tx_en;
            int mtx = top->dbg_mac_tx_en;
            int bus = top->dbg_bus_req;
            if (rd != prev_rd_empty) {
                printf("[%llu ns] cpu_rd_empty %d->%d\n", (unsigned long long)(t/1000), prev_rd_empty, rd);
                prev_rd_empty = rd;
            }
            if (tx != prev_tx_en) {
                printf("[%llu ns] gmii_tx_en %d->%d\n", (unsigned long long)(t/1000), prev_tx_en, tx);
                if (tx && tx_started < 0) tx_started = (int)(t/1000);
                if (!tx && txbuf_len > 0) {  // packet just completed
                    printf("  GMII TX pkt%d (%d bytes):", tx_pkt_idx, txbuf_len);
                    for (int i = 0; i < txbuf_len; i++) printf(" %02x", txbuf[i]);
                    printf("\n");
                    // Parse TCP SYN+ACK (ethertype=0800 @20, IP proto=6 @31, flags SYN|ACK @55)
                    if (txbuf_len > 55 && txbuf[20] == 0x08 && txbuf[21] == 0x00 &&
                        txbuf[31] == 6 && (txbuf[55] & 0x12) == 0x12 && ack_len == 0) {
                        uint32_t fpga_seq = ((uint32_t)txbuf[46] << 24) | ((uint32_t)txbuf[47] << 16) |
                                            ((uint32_t)txbuf[48] << 8) | txbuf[49];
                        printf("  [parsed SYN+ACK: fpga_seq=0x%08x]\n", fpga_seq);
                        ack_len = build_tcp(ack_pkt, FPGA_MAC, PC_MAC, PC_IP, FPGA_IP,
                                            PC_TCP_PORT, FPGA_TCP_PORT, PC_SEQ + 1, fpga_seq + 1,
                                            0x10 /*ACK*/, NULL, 0);
                        http_len = build_tcp(http_pkt, FPGA_MAC, PC_MAC, PC_IP, FPGA_IP,
                                             PC_TCP_PORT, FPGA_TCP_PORT, PC_SEQ + 1, fpga_seq + 1,
                                             0x18 /*ACK|PSH*/, (const uint8_t*)http_get, http_get_len);
                    }
                    txbuf_len = 0;
                    tx_pkt_idx++;
                }
                prev_tx_en = tx;
            }
            if (top->sim_gmii_tx_en) {
                if (txbuf_len < 1500 && (txbuf_len == 0 || (t - last_tx_cap) >= 8000)) {
                    txbuf[txbuf_len++] = (unsigned char)(top->sim_gmii_txd & 0xFF);
                    last_tx_cap = t;
                }
            }
            if (mtx != prev_mtx_en) {
                printf("[%llu ns] mac_tx_en %d->%d\n", (unsigned long long)(t/1000), prev_mtx_en, mtx);
                if (mtx && mtx_started < 0) mtx_started = (int)(t/1000);
                prev_mtx_en = mtx;
            }
            if (bus && !prev_bus_req) {
                bus_activity++;
                unsigned addr = (unsigned)(top->dbg_bus_address & 0xFFF);
                if (top->dbg_bus_rhwl) {
                    // read — rdata valid only at bus_req FALLING edge (reg_ack→rdata is 2 cycles)
                    pending_read = 1;
                    pending_read_addr = (unsigned)(top->dbg_bus_address);
                } else {
                    printf("[%llu ns] bus WRITE addr=0x%03x wdata=0x%02x\n",
                           (unsigned long long)(t/1000), addr,
                           (unsigned)(top->dbg_bus_wdata & 0xFF));
                }
            } else if (!bus && prev_bus_req && pending_read) {
                printf("[%llu ns] bus READ addr=0x%08x rdata=0x%08x\n",
                       (unsigned long long)(t/1000),
                       pending_read_addr,
                       (unsigned)(top->dbg_bus_rdata));
                pending_read = 0;
            }
            prev_bus_req = bus;

            // Track MAC RX frame timing + presemble_valid
            int mac_sop = top->dbg_mac_rx_sop;
            int mac_en = top->dbg_mac_rx_en;
            int mac_eop = top->dbg_mac_rx_eop;
            int pres = top->dbg_rx_presemble_valid;
            if (mac_sop != prev_mac_sop) {
                printf("[%llu ns] mac_rx_sop %d->%d\n", (unsigned long long)(t/1000), prev_mac_sop, mac_sop);
                prev_mac_sop = mac_sop;
            }
            if (mac_en != prev_mac_en) {
                printf("[%llu ns] mac_rx_en %d->%d (byte=%02x)\n", (unsigned long long)(t/1000), prev_mac_en, mac_en, (unsigned)(top->dbg_mac_rx_data & 0xFF));
                prev_mac_en = mac_en;
            }
            if (mac_eop != prev_mac_eop) {
                printf("[%llu ns] mac_rx_eop %d->%d\n", (unsigned long long)(t/1000), prev_mac_eop, mac_eop);
                prev_mac_eop = mac_eop;
            }
            if (mac_en) mac_en_count++;
            if (pres) pres_count++;

            // Track packet length counter
            int wpkt_push = top->dbg_mac_in_wpkt_push;
            int wpkt_len = top->dbg_mac_in_wpkt_len;
            if (wpkt_push != prev_wpkt_push) {
                printf("[%llu ns] wpkt_push %d->%d (wpkt_len=%d)\n",
                       (unsigned long long)(t/1000), prev_wpkt_push, wpkt_push, wpkt_len);
                prev_wpkt_push = wpkt_push;
            }
            if (wpkt_len != prev_wpkt_len) {
                prev_wpkt_len = wpkt_len;
            }

            // Track para_fifo write/read
            int para_wen = top->dbg_para_wen;
            int rpkt_pop = top->dbg_rpkt_pop;
            if (para_wen != prev_para_wen) {
                printf("[%llu ns] para_wen %d->%d (para_len=%d full_reg=%d)\n",
                       (unsigned long long)(t/1000), prev_para_wen, para_wen,
                       (unsigned)top->dbg_para_len, (int)top->dbg_para_full_reg);
                prev_para_wen = para_wen;
            }
            if (rpkt_pop != prev_rpkt_pop) {
                printf("[%llu ns] rpkt_pop %d->%d (rpkt_para_len=%d rpkt_para_data_r_len=%d)\n",
                       (unsigned long long)(t/1000), prev_rpkt_pop, rpkt_pop,
                       (unsigned)top->dbg_rpkt_para_len,
                       (unsigned)top->dbg_rpkt_para_data_r_len);
                prev_rpkt_pop = rpkt_pop;
            }

            if (tfp) tfp->dump(t);

            // Stop after both packets + margin
            if (t > SIM_END) break;
        } else {
            break;
        }
    }

    printf("\nFinal: tx_en=%d mac_tx_en=%d cpu_rd_empty=%d LED=%x\n",
           (int)top->sim_gmii_tx_en, (int)top->dbg_mac_tx_en,
           (int)top->sim_cpu_rd_empty, (int)(top->led_o&0xF));
    printf("TX started: gmii=%d ns, mac=%d ns, bus_activity=%d\n",
           tx_started, mtx_started, bus_activity);
    printf("MAC RX: en_count=%d, presemble_valid_count=%d\n",
           mac_en_count, pres_count);

    top->final();
    delete top;
    delete contextp;
    return 0;
}
