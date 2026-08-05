#ifndef _TCP_H_
#define _TCP_H_

#include <stdint.h>

#define MAX_CONNECTIONS   4

#define TCP_STATE_CLOSED       0
#define TCP_STATE_LISTEN       1
#define TCP_STATE_SYN_RECEIVED 2
#define TCP_STATE_ESTABLISHED  3
#define TCP_STATE_FIN_WAIT_1   4
#define TCP_STATE_FIN_WAIT_2   5
#define TCP_STATE_TIME_WAIT    6
#define TCP_STATE_LAST_ACK     7

#define TCP_FLAG_FIN  0x01u
#define TCP_FLAG_SYN  0x02u
#define TCP_FLAG_RST  0x04u
#define TCP_FLAG_PSH  0x08u
#define TCP_FLAG_ACK  0x10u
#define TCP_FLAG_URG  0x20u

extern uint8_t  connection_states[MAX_CONNECTIONS];
extern uint32_t connection_seq_nums[MAX_CONNECTIONS];
extern uint32_t connection_ack_nums[MAX_CONNECTIONS];
extern uint16_t connection_src_ports[MAX_CONNECTIONS];
extern uint16_t connection_dst_ports[MAX_CONNECTIONS];
extern uint32_t connection_src_ips[MAX_CONNECTIONS];
extern uint32_t connection_dst_ips[MAX_CONNECTIONS];
extern uint32_t available_connections;

extern uint32_t connection_time_wait_start[MAX_CONNECTIONS];
extern uint32_t connection_last_activity[MAX_CONNECTIONS];
extern uint32_t connection_last_tx_time[MAX_CONNECTIONS];
extern uint8_t  connection_syn_retries[MAX_CONNECTIONS];

void tcp_connection_init(void);
void tcp_periodic_check(void);
void tcp_packet_handler(void);

#endif
