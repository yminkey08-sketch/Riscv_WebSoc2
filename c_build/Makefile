CROSS     = riscv64-unknown-elf
CC        = $(CROSS)-gcc
OBJCOPY   = $(CROSS)-objcopy
OBJDUMP   = $(CROSS)-objdump
PYTHON    = python3

ARCH      = rv32ic
ABI       = ilp32

SYSROOT   = /usr/lib/picolibc/riscv64-unknown-elf
SYS_INC   = -isystem $(SYSROOT)/include
SYS_LIB   = -L$(SYSROOT)/lib/rv32iac/ilp32

CFLAGS    = -march=$(ARCH) -mabi=$(ABI) -msmall-data-limit=0 -mno-save-restore \
            -O2 -ffunction-sections -fdata-sections -Wall -Wextra $(SYS_INC)
LDFLAGS   = -march=$(ARCH) -mabi=$(ABI) -nostdlib -Wl,--gc-sections $(SYS_LIB)

C_DIR     = ../c
INC_DIR   = $(C_DIR)/inc
OUT_DIR   = out
TCL_DIR   = ../tcl
LINKER    = linker.ld
SCRIPTS   = ../c_build

TCL_BASE      ?= 0x10000
riscv_reset_addr ?= 0x100
INSTR_ADDR_DEPTH ?= 5120
BIN_SIZE := $(shell echo $$(($(INSTR_ADDR_DEPTH) * 4)))

C_SRCS    = $(wildcard $(C_DIR)/*.c)
C_OBJS    = $(patsubst $(C_DIR)/%.c, $(OUT_DIR)/%.o, $(C_SRCS))

ELF       = $(OUT_DIR)/firmware.elf
BIN       = $(OUT_DIR)/firmware.bin
PADS      = $(OUT_DIR)/firmware_pads.bin
TCL_OUT   = $(TCL_DIR)/InstructRAM.tcl

.DEFAULT_GOAL := all
.PHONY: all elf bin pads tcl clean disasm

all: tcl
	@echo ""
	@echo "============================================"
	@echo "  Build Summary"
	@echo "============================================"
	@$(PYTHON) -c "import pathlib; \
sz=pathlib.Path('$(BIN)').stat().st_size; \
w=(sz+3)//4; d=int('$(INSTR_ADDR_DEPTH)'); \
print(f'  Firmware: {sz} bytes, {w} words ({w*100.0/d:.1f}%)')"
	@echo "  ELF : $(ELF)"
	@echo "  TCL : $(TCL_OUT)"

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

$(OUT_DIR)/%.o: $(C_DIR)/%.c | $(OUT_DIR)
	@echo "  CC   $<"
	$(CC) -c $< -I$(INC_DIR) $(CFLAGS) -o $@

elf: $(ELF)
$(ELF): $(C_OBJS) $(LINKER) | $(OUT_DIR)
	@echo "  LD   $@"
	$(CC) $(C_OBJS) -T $(LINKER) $(LDFLAGS) -lc -lgcc -o $@

bin: $(BIN)
$(BIN): $(ELF)
	@echo "  OBJCOPY $@"
	$(OBJCOPY) -O binary $< $@

pads: $(PADS)
$(PADS): $(BIN)
	@echo "  PAD  $@ ($(BIN_SIZE) bytes)"
	$(PYTHON) -c "\
import pathlib; BIN_SIZE=$(BIN_SIZE); \
src=pathlib.Path('$<').read_bytes(); \
assert len(src) <= BIN_SIZE, f'Firmware too large: {len(src)} > {BIN_SIZE}'; \
pathlib.Path('$@').write_bytes(src + b'\x00' * (BIN_SIZE - len(src)));"

tcl: $(TCL_OUT)
$(TCL_OUT): $(PADS) $(SCRIPTS)/bin_to_tcl.py
	@echo "  TCL  $@"
	mkdir -p $(TCL_DIR)
	$(PYTHON) $(SCRIPTS)/bin_to_tcl.py $< $@ $(TCL_BASE) $(riscv_reset_addr)

disasm: $(ELF)
	@echo "  OBJDUMP $@"
	$(OBJDUMP) -d -M no-aliases $< > $(OUT_DIR)/firmware.disasm
	@echo "  -> $(OUT_DIR)/firmware.disasm"

clean:
	rm -rf $(OUT_DIR) $(TCL_OUT)
