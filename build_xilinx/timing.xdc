#===== 输入时钟 50MHz =====
create_clock -period 20.000 -name clk_50m_in [get_ports clk_50m_in]

#===== RGMII RXC (来自 PHY, 125MHz, 异步) =====
create_clock -period 8.000 -name rgmii_rxc [get_ports rgmii_rxc]
set_false_path -from [get_clocks rgmii_rxc] -to [all_clocks]
set_false_path -to   [get_clocks rgmii_rxc] -from [all_clocks]

#===== MMCM 相移时钟组 (同源, ODDR/IDDR内部处理时序) =====
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated clk_125m_unbuf] \
    -group [get_clocks -include_generated clk_125m_tx_unbuf]
