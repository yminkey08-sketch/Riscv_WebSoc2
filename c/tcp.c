// tcp.c — TCP 协议栈（原地 FIFO 风格）
#include "inc/lcpu_general.h"
#include "inc/comlib.h"
#include "inc/ip.h"
#include "inc/tcp.h"

uint8_t  connection_states[MAX_CONNECTIONS];
uint32_t connection_seq_nums[MAX_CONNECTIONS];
uint32_t connection_ack_nums[MAX_CONNECTIONS];
uint16_t connection_src_ports[MAX_CONNECTIONS];
uint16_t connection_dst_ports[MAX_CONNECTIONS];
uint32_t connection_src_ips[MAX_CONNECTIONS];
uint32_t connection_dst_ips[MAX_CONNECTIONS];
uint32_t available_connections = MAX_CONNECTIONS;
uint32_t connection_time_wait_start[MAX_CONNECTIONS];
uint32_t connection_last_activity[MAX_CONNECTIONS];
uint32_t connection_last_tx_time[MAX_CONNECTIONS];
uint8_t  connection_syn_retries[MAX_CONNECTIONS];

void tcp_connection_init(void)
{
    uint32_t i;
    for (i = 0; i < MAX_CONNECTIONS; i++) {
        connection_states[i] = TCP_STATE_CLOSED;
        connection_syn_retries[i] = 0;
    }
    available_connections = MAX_CONNECTIONS;
}

static int find_free_connection(void) {
    uint32_t i;
    for (i = 0; i < MAX_CONNECTIONS; i++)
        if (connection_states[i] == TCP_STATE_CLOSED) return (int)i;
    return -1;
}

static int find_connection(uint16_t sp, uint16_t dp, uint32_t sip, uint32_t dip) {
    uint32_t i;
    for (i = 0; i < MAX_CONNECTIONS; i++)
        if (connection_states[i] != TCP_STATE_CLOSED &&
            connection_src_ports[i] == sp && connection_dst_ports[i] == dp &&
            connection_src_ips[i] == sip && connection_dst_ips[i] == dip)
            return (int)i;
    return -1;
}

static void close_connection(int idx) {
    if (idx < 0 || idx >= MAX_CONNECTIONS) return;
    if (connection_states[idx] != TCP_STATE_CLOSED) {
        connection_states[idx] = TCP_STATE_CLOSED;
        connection_syn_retries[idx] = 0;
        available_connections++;
    }
}

static void fill_tcp_header(int idx, uint8_t flags, uint8_t *hdr) {
    uint32_t i;
    for (i = 0; i < tcp_header_len; i++) hdr[i] = 0;
    // Response: swap ports — SRC=FPGA(dst_port), DST=PC(src_port)
    uint16_t dp = connection_dst_ports[idx];  // FPGA port (80)
    uint16_t sp = connection_src_ports[idx];  // PC port
    uint32_t sq = connection_seq_nums[idx];
    uint32_t ak = connection_ack_nums[idx];
    hdr[0] = (dp >> 8) & 0xFF;  hdr[1] = dp & 0xFF;  // SRC = FPGA port
    hdr[2] = (sp >> 8) & 0xFF;  hdr[3] = sp & 0xFF;  // DST = PC port
    hdr[4] = (sq >> 24) & 0xFF; hdr[5] = (sq >> 16) & 0xFF;
    hdr[6] = (sq >> 8) & 0xFF;  hdr[7] = sq & 0xFF;
    hdr[8] = (ak >> 24) & 0xFF; hdr[9] = (ak >> 16) & 0xFF;
    hdr[10]= (ak >> 8) & 0xFF;  hdr[11]= ak & 0xFF;
    hdr[12]= 0x50; hdr[13]= flags; hdr[14]= 0xFF; hdr[15]= 0xFF;
}

static uint16_t tcp_checksum(const uint8_t *hdr, uint32_t sip, uint32_t dip,
                             const uint8_t *pay, uint16_t plen) {
    uint32_t sum = 0;
    uint16_t i, tlen = tcp_header_len + plen;
    sum += (uint16_t)((sip >> 16) & 0xFFFF);
    sum += (uint16_t)(sip & 0xFFFF);
    sum += (uint16_t)((dip >> 16) & 0xFFFF);
    sum += (uint16_t)(dip & 0xFFFF);
    sum += (uint16_t)IP_PROTOCOL_TCP;
    sum += tlen;
    for (i = 0; i + 1 < tcp_header_len; i += 2)
        sum += ((uint16_t)hdr[i] << 8) | hdr[i + 1];
    if (pay && plen > 0) {
        for (i = 0; i + 1 < plen; i += 2)
            sum += ((uint16_t)pay[i] << 8) | pay[i + 1];
        if (plen & 1) sum += (uint16_t)pay[plen - 1] << 8;
    }
    while (sum >> 16) sum = (sum & 0xFFFF) + (sum >> 16);
    return (uint16_t)(~sum);
}

static void send_tcp_seg(const uint8_t *hdr, const uint8_t *pay, uint16_t plen) {
    uint16_t i, ts = eth_header_len + ip_header_len;
    uint16_t rpl = ts + tcp_header_len + plen + 4;
    for (i = 0; i < tcp_header_len; i++) LCPU_WR_BYTE(ts + i, hdr[i]);
    if (pay) for (i = 0; i < plen; i++) LCPU_WR_BYTE(ts + tcp_header_len + i, pay[i]);
    if (rpl < 64) rpl = 64;
    LCPU_WR_PUSH_PACKET(rpl);
}

static void send_syn_ack(int idx) {
    uint8_t hdr[tcp_header_len];
    if (connection_states[idx] == TCP_STATE_CLOSED) return;
    fill_tcp_header(idx, TCP_FLAG_SYN | TCP_FLAG_ACK, hdr);
    uint16_t cs = tcp_checksum(hdr, connection_dst_ips[idx], connection_src_ips[idx], NULL, 0);
    hdr[16] = (cs >> 8) & 0xFF; hdr[17] = cs & 0xFF;
    ip_header_update(connection_src_ips[idx], ip_header_len + tcp_header_len);
    send_tcp_seg(hdr, NULL, 0);
    connection_last_tx_time[idx] = LCPU_LOCAL_TIME_L();
    if (connection_syn_retries[idx] == 0) connection_syn_retries[idx] = 1;
}

static void send_ack(int idx) {
    uint8_t hdr[tcp_header_len];
    if (connection_states[idx] == TCP_STATE_CLOSED) return;
    fill_tcp_header(idx, TCP_FLAG_ACK, hdr);
    uint16_t cs = tcp_checksum(hdr, connection_dst_ips[idx], connection_src_ips[idx], NULL, 0);
    hdr[16] = (cs >> 8) & 0xFF; hdr[17] = cs & 0xFF;
    ip_header_update(connection_src_ips[idx], ip_header_len + tcp_header_len);
    send_tcp_seg(hdr, NULL, 0);
}

static void send_rst(int idx) {
    uint8_t hdr[tcp_header_len];
    if (connection_states[idx] == TCP_STATE_CLOSED) return;
    fill_tcp_header(idx, TCP_FLAG_RST | TCP_FLAG_ACK, hdr);
    uint16_t cs = tcp_checksum(hdr, connection_dst_ips[idx], connection_src_ips[idx], NULL, 0);
    hdr[16] = (cs >> 8) & 0xFF; hdr[17] = cs & 0xFF;
    ip_header_update(connection_src_ips[idx], ip_header_len + tcp_header_len);
    send_tcp_seg(hdr, NULL, 0);
}

static void tcp_handle_syn(uint16_t sp, uint16_t dp, uint32_t sip, uint32_t sn) {
    if (dp != HTTP_PORT) return;
    int idx = find_free_connection();
    if (idx < 0) return;
    connection_states[idx]        = TCP_STATE_SYN_RECEIVED;
    connection_src_ports[idx]     = sp;
    connection_dst_ports[idx]     = dp;
    connection_src_ips[idx]       = sip;
    connection_dst_ips[idx]       = Local_IP_ADDR;
    connection_seq_nums[idx]      = LCPU_LOCAL_TIME_L();
    connection_ack_nums[idx]      = sn + 1;
    connection_last_activity[idx] = LCPU_LOCAL_TIME_L();
    connection_last_tx_time[idx]  = 0;
    connection_syn_retries[idx]   = 0;
    available_connections--;
    send_syn_ack(idx);
}

// Minimal HTTP response page
static const char http_header[] =
    "HTTP/1.1 200 OK\r\n"
    "Content-Type: text/html\r\n"
    "Connection: close\r\n"
    "\r\n";
static const char html_page[] =
    "<!DOCTYPE html><html><head><title>FPGA LED Control</title>"
    "<meta name='viewport' content='width=device-width,initial-scale=1'>"
    "<meta charset='UTF-8'>"
    "<style>body{font-family:Arial;text-align:center;margin:20px;background:#1a1a2e;color:#eee}"
    "h1{color:#e94560;margin-bottom:10px}a{text-decoration:none}"
    "button{width:130px;height:50px;margin:6px;font-size:18px;border:none;"
    "border-radius:8px;cursor:pointer;color:#fff;font-weight:bold}"
    ".on{background:#2ecc71}.off{background:#e74c3c}"
    ".led{background:#3498db}</style></head>"
    "<body><h1>RiscV WebSoC</h1>"
    "<p>FPGA LED Control - TCP/IP on Artix-7</p>"
    "<a href='/led/0F'><button class=on>ALL ON</button></a>"
    "<a href='/led/00'><button class=off>ALL OFF</button></a><br>"
    "<a href='/led/01'><button class=led>LED 0</button></a>"
    "<a href='/led/02'><button class=led>LED 1</button></a>"
    "<a href='/led/04'><button class=led>LED 2</button></a>"
    "<a href='/led/08'><button class=led>LED 3</button></a>"
    "</body></html>";

// close_after: piggyback FIN on last segment (avoids back-to-back TX issue)
static void send_http_response(int ci, int close_after) {
    uint32_t hlen = sizeof(http_header) - 1;  // exclude null terminator
    uint32_t plen = sizeof(html_page) - 1;
    uint32_t total = hlen + plen;
    uint32_t i;

    // Build and send HTTP header
    uint8_t buf[hlen + plen];
    for (i = 0; i < hlen; i++) buf[i] = http_header[i];
    for (i = 0; i < plen; i++) buf[hlen + i] = html_page[i];

    // Send in TCP segments
    uint16_t mss = 1024;  // conservative MSS
    uint32_t offset = 0;
    while (offset < total) {
        uint16_t chunk = (total - offset > mss) ? mss : (total - offset);
        uint8_t hdr[tcp_header_len];
        uint8_t flags = TCP_FLAG_ACK;
        if (close_after && (offset + chunk >= total))
            flags |= TCP_FLAG_FIN;  // piggyback FIN on last segment
        fill_tcp_header(ci, flags, hdr);
        uint16_t cs = tcp_checksum(hdr, connection_dst_ips[ci],
                                   connection_src_ips[ci], &buf[offset], chunk);
        hdr[16] = (cs >> 8) & 0xFF; hdr[17] = cs & 0xFF;
        ip_header_update(connection_src_ips[ci], ip_header_len + tcp_header_len + chunk);
        send_tcp_seg(hdr, &buf[offset], chunk);
        connection_seq_nums[ci] += chunk;
        if (flags & TCP_FLAG_FIN) connection_seq_nums[ci]++;  // FIN consumes a seq num
        offset += chunk;
    }
    connection_last_activity[ci] = LCPU_LOCAL_TIME_L();
}

void tcp_packet_handler(void) {
    uint16_t sp = 0, dp = 0;
    uint32_t sn = 0, an = 0, sip = 0, dip = 0;
    uint8_t  fl;
    uint16_t dlen = 0;

    LCPU_RD_SET_ADDR(OFF_IP_VER_IHL);
    uint8_t vih = LCPU_RD_DATA8();
    if ((vih & 0xF0) != 0x40) return;
    uint8_t ihl = (vih & 0x0F) * 4;
    if (ihl < 20) return;

    LCPU_RD_SET_ADDR(OFF_IP_SRC_IP);
    sip  = (uint32_t)LCPU_RD_DATA8() << 24; LCPU_RD_INC_ADDR();
    sip |= (uint32_t)LCPU_RD_DATA8() << 16; LCPU_RD_INC_ADDR();
    sip |= (uint32_t)LCPU_RD_DATA8() << 8;  LCPU_RD_INC_ADDR();
    sip |= LCPU_RD_DATA8();                  LCPU_RD_INC_ADDR();
    dip  = (uint32_t)LCPU_RD_DATA8() << 24; LCPU_RD_INC_ADDR();
    dip |= (uint32_t)LCPU_RD_DATA8() << 16; LCPU_RD_INC_ADDR();
    dip |= (uint32_t)LCPU_RD_DATA8() << 8;  LCPU_RD_INC_ADDR();
    dip |= LCPU_RD_DATA8();

    LCPU_RD_SET_ADDR(OFF_IP_TOTAL_LEN);
    ip_total_len  = (uint16_t)LCPU_RD_DATA8() << 8; LCPU_RD_INC_ADDR();
    ip_total_len |= LCPU_RD_DATA8();

    uint32_t to = eth_header_len + ihl;
    LCPU_RD_SET_ADDR(to + 0);
    sp  = (uint16_t)LCPU_RD_DATA8() << 8; LCPU_RD_INC_ADDR();
    sp |= LCPU_RD_DATA8();                 LCPU_RD_INC_ADDR();
    dp  = (uint16_t)LCPU_RD_DATA8() << 8; LCPU_RD_INC_ADDR();
    dp |= LCPU_RD_DATA8();                 LCPU_RD_INC_ADDR();
    sn  = (uint32_t)LCPU_RD_DATA8() << 24; LCPU_RD_INC_ADDR();
    sn |= (uint32_t)LCPU_RD_DATA8() << 16; LCPU_RD_INC_ADDR();
    sn |= (uint32_t)LCPU_RD_DATA8() << 8;  LCPU_RD_INC_ADDR();
    sn |= LCPU_RD_DATA8();                  LCPU_RD_INC_ADDR();
    an  = (uint32_t)LCPU_RD_DATA8() << 24; LCPU_RD_INC_ADDR();
    an |= (uint32_t)LCPU_RD_DATA8() << 16; LCPU_RD_INC_ADDR();
    an |= (uint32_t)LCPU_RD_DATA8() << 8;  LCPU_RD_INC_ADDR();
    an |= LCPU_RD_DATA8();

    LCPU_RD_SET_ADDR(to + 12);
    uint8_t tofs = (LCPU_RD_DATA8() >> 4) * 4;
    if (tofs < 20) tofs = 20;
    LCPU_RD_SET_ADDR(to + 13);
    fl = LCPU_RD_DATA8();
    if (ip_total_len >= (ihl + tofs)) dlen = ip_total_len - ihl - tofs;

    int ci = find_connection(sp, dp, sip, Local_IP_ADDR);
    if (fl & TCP_FLAG_RST) { if (ci >= 0) close_connection(ci); return; }
    if (ci < 0) {
        if ((fl & TCP_FLAG_SYN) && !(fl & TCP_FLAG_ACK) && !(fl & TCP_FLAG_RST) && !(fl & TCP_FLAG_FIN))
            tcp_handle_syn(sp, dp, sip, sn);
        return;
    }
    connection_last_activity[ci] = LCPU_LOCAL_TIME_L();
    uint8_t st = connection_states[ci];
    switch (st) {
    case TCP_STATE_SYN_RECEIVED:
        if ((fl & TCP_FLAG_ACK) && an == connection_seq_nums[ci] + 1) {
            connection_states[ci] = TCP_STATE_ESTABLISHED;
            connection_seq_nums[ci]++; connection_syn_retries[ci] = 0;
            if (dlen > 0) { connection_ack_nums[ci] = sn + dlen; send_ack(ci); }
        } else if (fl & TCP_FLAG_SYN) {
            connection_last_tx_time[ci] = 0; connection_syn_retries[ci] = 1; send_syn_ack(ci);
        }
        break;
    case TCP_STATE_ESTABLISHED:
        if (fl & TCP_FLAG_FIN) {
            connection_ack_nums[ci] = sn + 1; send_ack(ci);
            uint8_t h[tcp_header_len];
            fill_tcp_header(ci, TCP_FLAG_FIN | TCP_FLAG_ACK, h);
            uint16_t cs = tcp_checksum(h, connection_dst_ips[ci], connection_src_ips[ci], NULL, 0);
            h[16] = (cs >> 8) & 0xFF; h[17] = cs & 0xFF;
            ip_header_update(connection_src_ips[ci], ip_header_len + tcp_header_len);
            send_tcp_seg(h, NULL, 0);
            connection_seq_nums[ci]++; connection_states[ci] = TCP_STATE_LAST_ACK;
        } else if ((fl & TCP_FLAG_ACK) && dlen > 0) {
            if (sn == connection_ack_nums[ci]) {
                connection_ack_nums[ci] = sn + dlen;
                uint32_t poff = eth_header_len + ihl + tofs;

                // Check for HTTP GET request
                LCPU_RD_SET_ADDR(poff);
                uint8_t c0 = LCPU_RD_DATA8();
                LCPU_RD_INC_ADDR();
                uint8_t c1 = LCPU_RD_DATA8();
                LCPU_RD_INC_ADDR();
                uint8_t c2 = LCPU_RD_DATA8();
                LCPU_RD_INC_ADDR();
                uint8_t c3 = LCPU_RD_DATA8();

                if (c0 == 'G' && c1 == 'E' && c2 == 'T' && c3 == ' ') {
                    // Read URL path byte 5 (after "GET /")
                    LCPU_RD_SET_ADDR(poff + 5);
                    uint8_t p0 = LCPU_RD_DATA8();
                    // Check for /led/XX path
                    if (p0 == 'l') {
                        LCPU_RD_SET_ADDR(poff + 9); // after "GET /led/"
                        uint8_t h0 = LCPU_RD_DATA8();
                        LCPU_RD_INC_ADDR();
                        uint8_t h1 = LCPU_RD_DATA8();
                        // Parse hex: h0,h1 are ASCII hex chars
                        uint8_t lv = 0;
                        if (h0 >= '0' && h0 <= '9') lv = (h0 - '0') << 4;
                        else if (h0 >= 'A' && h0 <= 'F') lv = (h0 - 'A' + 10) << 4;
                        else if (h0 >= 'a' && h0 <= 'f') lv = (h0 - 'a' + 10) << 4;
                        if (h1 >= '0' && h1 <= '9') lv |= (h1 - '0');
                        else if (h1 >= 'A' && h1 <= 'F') lv |= (h1 - 'A' + 10);
                        else if (h1 >= 'a' && h1 <= 'f') lv |= (h1 - 'a' + 10);
                        *((volatile uint32_t*)(LCPU_BASE + 0x10 * 4)) = (uint32_t)(lv & 0x0F);
                    }
                    // Send HTTP response with piggybacked FIN, enter FIN_WAIT_1
                    send_http_response(ci, 1);
                    connection_states[ci] = TCP_STATE_FIN_WAIT_1;
                } else {
                    // LED control: first byte = LED value
                    *((volatile uint32_t*)(LCPU_BASE + 0x10 * 4)) = (uint32_t)(c0 & 0x0F);
                    send_ack(ci);
                }
            }
            else send_ack(ci);
        }
        break;
    case TCP_STATE_LAST_ACK:
        if ((fl & TCP_FLAG_ACK) && an == connection_seq_nums[ci]) close_connection(ci);
        break;
    case TCP_STATE_FIN_WAIT_1:
        if (fl & TCP_FLAG_FIN) {
            connection_ack_nums[ci] = sn + 1; send_ack(ci);
            connection_states[ci] = TCP_STATE_TIME_WAIT;
            connection_time_wait_start[ci] = LCPU_LOCAL_TIME_L();
        } else if (fl & TCP_FLAG_ACK) connection_states[ci] = TCP_STATE_FIN_WAIT_2;
        break;
    case TCP_STATE_FIN_WAIT_2:
        if (fl & TCP_FLAG_FIN) {
            connection_ack_nums[ci] = sn + 1; send_ack(ci);
            connection_states[ci] = TCP_STATE_TIME_WAIT;
            connection_time_wait_start[ci] = LCPU_LOCAL_TIME_L();
        }
        break;
    case TCP_STATE_TIME_WAIT:
        if (fl & TCP_FLAG_FIN) { connection_ack_nums[ci] = sn + 1; send_ack(ci); }
        break;
    default: close_connection(ci); break;
    }
}

void tcp_periodic_check(void) {
    uint32_t now = LCPU_LOCAL_TIME_L();
    uint32_t i;
    for (i = 0; i < MAX_CONNECTIONS; i++) {
        uint8_t st = connection_states[i];
        if (st == TCP_STATE_CLOSED) continue;
        if (st == TCP_STATE_TIME_WAIT &&
            (now - connection_time_wait_start[i]) >= TCP_TIMEWAIT_TICKS)
            { close_connection(i); continue; }
        if (st != TCP_STATE_TIME_WAIT &&
            (now - connection_last_activity[i]) >= TCP_IDLE_TIMEOUT_TICKS)
            { send_rst(i); close_connection(i); continue; }
        if (st == TCP_STATE_SYN_RECEIVED && connection_syn_retries[i] > 0 &&
            (now - connection_last_tx_time[i]) >= TCP_SYN_RETRY_TICKS) {
            if (connection_syn_retries[i] < TCP_SYN_MAX_RETRIES) {
                connection_syn_retries[i]++; connection_last_tx_time[i] = now; send_syn_ack(i);
            } else close_connection(i);
        }
    }
}
