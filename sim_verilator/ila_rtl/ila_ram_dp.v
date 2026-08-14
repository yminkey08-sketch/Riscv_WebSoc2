`timescale 1ns / 1ps
// ==========================================================================
// ila_ram_dp — 简单双口 RAM（inferred，Vivado 自动映射为 BRAM）
//
// 直接 inferred reg array + (* ram_style = "block" *) 综合属性，
// 让 Vivado 根据 data_width/depth 自动选择 BRAM 配置。
// ==========================================================================
module ila_ram_dp #(
    parameter DATA_W = 8,
    parameter DEPTH  = 1024,
    parameter ADDR_W = 10
) (
    input  wire              wr_clk,
    input  wire              wr_en,
    input  wire [ADDR_W-1:0] wr_addr,
    input  wire [DATA_W-1:0] wr_data,
    input  wire              rd_clk,
    input  wire              rd_en,
    input  wire [ADDR_W-1:0] rd_addr,
    output wire [DATA_W-1:0] rd_data
);

    // inferred RAM — Vivado 根据 ram_style = "block" 自动映射到 BRAM36
    (* ram_style = "block" *) reg [DATA_W-1:0] ram [0:DEPTH-1];

    // 写口
    always @(posedge wr_clk) begin
        if (wr_en) ram[wr_addr] <= wr_data;
    end

    // 读口：1 拍延迟（hub.REG_HOLD 依赖此延迟值）
    reg [DATA_W-1:0] rd_data_r;
    always @(posedge rd_clk) begin
        rd_data_r <= ram[rd_addr];
    end

    assign rd_data = rd_data_r;

endmodule
