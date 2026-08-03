#!/bin/bash
cd /home/haitaoz/work/FPGA_Prj/RiscV_WebSoC2/build_xilinx
source ~/Xilinx/2024.1/Vivado/2024.1/settings64.sh

updatemem -meminfo RiscV_WebSoC.mmi \
  -data bank0.mem  -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[0].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank1.mem  -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[1].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank2.mem  -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[2].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank3.mem  -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[3].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank4.mem  -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[4].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank5.mem  -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[5].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank6.mem  -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[6].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank7.mem  -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[7].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank8.mem  -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[8].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank9.mem  -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[9].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank10.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[10].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank11.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[11].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank12.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[12].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank13.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[13].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank14.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[14].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank15.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[15].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -bit RiscV_WebSoC.bit -out RiscV_WebSoC_fw.bit -force

echo "updatemem done"
vivado -mode batch -nojournal -nolog -source program.tcl
echo "Program done"
