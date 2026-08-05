# iverilog simulation Makefile for RiscV WebSoC2
IVERILOG = iverilog
VVP = vvp

RTL_DIR = ../rtl
SIM_DIR = .
C_BUILD = ../c_build

# RTL files (Verilog + SystemVerilog)
RTL_V = $(wildcard $(RTL_DIR)/*.v)
RTL_SV = $(RTL_DIR)/define.sv $(RTL_DIR)/riscv32intfbridge.v

# Simulation files
SIM_FILES = $(SIM_DIR)/vendor_stubs.v \
            $(SIM_DIR)/xpm_memory_tdpram_sim.v \
            $(SIM_DIR)/lcpu_bfm.sv \
            $(SIM_DIR)/tb.v

# Firmware TCL script
FW_TCL = $(SIM_DIR)/fw_script.tcl

all: tb.vvp
	$(VVP) tb.vvp

tb.vvp: $(RTL_V) $(SIM_FILES) $(FW_TCL)
	$(IVERILOG) -g2012 -o tb.vvp \
	  -I$(RTL_DIR) \
	  -I$(SIM_DIR) \
	  $(RTL_V) \
	  $(SIM_FILES)

$(FW_TCL): $(C_BUILD)/out/firmware.bin
	python3 $(C_BUILD)/bin_to_tcl.py $< $@ 0x10000 0x100

clean:
	rm -f tb.vvp $(FW_TCL) *.vcd
