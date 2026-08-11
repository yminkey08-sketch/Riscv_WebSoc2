#!/bin/bash
set -e
PROJ=/home/minkey/work/FPGA_prj/RiscV_WebSoC2

# 1. Compile firmware
cd $PROJ/c_build
make elf bin 2>&1 | tail -3
riscv64-unknown-elf-size out/firmware.elf

# 2. Generate bank mem files
python3 -c "
import struct, shutil, os, glob
fw = open('out/firmware.bin','rb').read()
print(f'Firmware: {len(fw)} bytes')
padded = fw + b'\x00' * (4096 * 4 - len(fw))
for bank in range(16):
    start = bank * 256
    with open(f'bank{bank}.mem','w') as f:
        for i in range(256):
            w = struct.unpack('<I', padded[(start+i)*4:(start+i)*4+4])[0]
            f.write(f'@{i:03X} {w:08X}\n')
for f in glob.glob('bank*.mem'):
    shutil.copy(f, os.path.join('../build_xilinx', f))
print('Banks done')
"

# 3. updatemem + program
cd $PROJ/build_xilinx
source /home/xilinx/Vivado/2024.1/settings64.sh
updatemem -meminfo RiscV_WebSoC.mmi -bit RiscV_WebSoC_v3base.bit -out RiscV_WebSoC_fw.bit -force \
  -data bank0.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[0].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank1.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[1].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank2.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[2].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank3.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[3].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank4.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[4].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank5.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[5].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank6.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[6].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank7.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[7].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank8.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[8].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank9.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[9].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank10.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[10].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank11.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[11].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank12.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[12].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank13.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[13].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank14.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[14].u_xpm_memory_tdpram_bank/xpm_memory_base_inst" \
  -data bank15.mem -proc "u_riscv/riscv_cpu_generation.u_riscv_cpu/u_instru_ram/gen_xilinx_xpm_tdpram.xpm_bank[15].u_xpm_memory_tdpram_bank/xpm_memory_base_inst"
echo "updatemem done"

vivado -mode batch -nojournal -nolog -source program.tcl
echo "DONE"
