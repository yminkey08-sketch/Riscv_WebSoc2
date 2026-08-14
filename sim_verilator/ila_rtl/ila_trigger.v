`timescale 1ns / 1ps
// ==========================================================================
// ila_trigger — 触发比较器（v1 基础版：值 + 掩码，按位电平匹配）
//
// 触发条件： (sample & mask) == (value & mask)
// 预留 trig_mode（边沿/变化/序列）钩子，v1 仅实现电平匹配（mode==0）。
// 全部工作在采样时钟域。value/mask 由寄存器按 32 位字提供，低 DATA_W 位有效。
// ==========================================================================
module ila_trigger #(
    parameter DATA_W = 32,
    parameter NWORDS = 1                 // = ceil(DATA_W/32)
) (
    input  wire                 clk,
    input  wire                 rst,     // 高有效同步复位
    input  wire [DATA_W-1:0]    sample,  // 当前采样拼接总线

    // 运行期配置（采样域）
    input  wire [32*NWORDS-1:0] trig_value,
    input  wire [32*NWORDS-1:0] trig_mask,
    input  wire [1:0]           trig_mode,   // 0=电平 1=边沿(v2) 2=变化(v2)
    input  wire                 force_trig,  // 强制/外部触发（单拍脉冲）

    output wire                 trig
);

    // 取低 DATA_W 位参与比较（高位补齐字被忽略）
    wire [DATA_W-1:0] value_w = trig_value[DATA_W-1:0];
    wire [DATA_W-1:0] mask_w  = trig_mask [DATA_W-1:0];

    // ---- 电平匹配 ----
    wire level_match = ((sample & mask_w) == (value_w & mask_w));

    // ---- 变化检测钩子（v2 用，当前仅打拍占位，不参与输出）----
    reg [DATA_W-1:0] sample_d;
    always @(posedge clk) begin
        if (rst) sample_d <= {DATA_W{1'b0}};
        else     sample_d <= sample;
    end
    // wire change_match = |((sample ^ sample_d) & mask_w);  // v2: mode==2
    // wire edge_match   = ...;                              // v2: mode==1

    // v1：仅电平匹配 + 强制触发
    assign trig = force_trig | (level_match & (trig_mode == 2'd0));

endmodule
