VERILATOR = verilator
RTL_DIR = ../rtl
SIM_DIR = .
TCL_DIR = ../tcl

# All RTL .v and .sv files
RTL_SRC = $(wildcard $(RTL_DIR)/*.v) $(RTL_DIR)/define.sv
# Simulation stubs (replace Xilinx primitives)
STUBS = $(SIM_DIR)/vendor_stubs.v $(SIM_DIR)/xpm_memory_tdpram_sim.v $(SIM_DIR)/xpm_memory_sdpram_sim.v $(SIM_DIR)/lcpu_bfm.v
# Soft ILA probe RTL
ILA_SRC = $(SIM_DIR)/ila_wrapper.v $(SIM_DIR)/ila_rtl/soft_ila_top.v $(SIM_DIR)/ila_rtl/soft_ila_core.v \
          $(SIM_DIR)/ila_rtl/ila_capture.v $(SIM_DIR)/ila_rtl/ila_trigger.v $(SIM_DIR)/ila_rtl/ila_ctrl.v \
          $(SIM_DIR)/ila_rtl/ila_ram_dp.v
# Firmware TCL (must exist before build)
FW_TCL = $(TCL_DIR)/InstructRAM.tcl

all: $(FW_TCL) obj_dir/Vvtop
	obj_dir/Vvtop

obj_dir/Vvtop: vtop.v sim_main.cpp $(RTL_SRC) $(STUBS) $(ILA_SRC)
	$(VERILATOR) --cc --trace --exe --build -j 8 \
	  --public-flat-rw --timing --top-module vtop \
	  --x-assign 0 \
	  -I$(RTL_DIR) -I$(SIM_DIR) -I$(SIM_DIR)/ila_rtl \
	  -Wno-fatal -Wno-PINMISSING -Wno-WIDTH -Wno-LITENDIAN \
	  -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-UNOPTFLAT \
	  $(RTL_SRC) $(STUBS) $(ILA_SRC) \
	  vtop.v sim_main.cpp \
	  -o Vvtop

$(FW_TCL):
	@echo "=== Generating firmware TCL ==="
	cd ../c_build && make tcl

clean:
	rm -rf obj_dir *.vcd
