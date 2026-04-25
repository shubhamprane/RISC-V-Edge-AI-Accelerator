# ==============================================================================
# Windows Makefile for NeuroCore Systolic System
# ==============================================================================

# --- Toolchain Configuration ---
CC       = riscv-none-elf-gcc
OBJCOPY  = riscv-none-elf-objcopy
PYTHON   = python
VIVADO   = vivado

# --- Project Paths ---
SW_DIR   = sw
C_DIR    = $(SW_DIR)/c
ASM_DIR  = $(SW_DIR)/asm
RTL_DIR  = rtl
DATA_DIR = data

# --- Files ---
# To compile different workloads: make sw WORKLOAD=bench_dot
WORKLOAD ?= speedup_bench
MAIN_C   = $(C_DIR)/$(WORKLOAD).c
CRT0     = $(SW_DIR)/crt0.s
LINKER   = $(SW_DIR)/linker.ld
TCL_SCRIPT = vivado_build.tcl

# Memory targets required by RTL
MEM_DATA = weights.mem input.mem bias.mem
MEM_SW   = imem.hex dmem.hex
BITSTREAM = neurocore.bit

# --- Rules ---

.PHONY: all clean sw data bitstream asm_test

# Default target: Generates everything
all: bitstream

# 1. Generate Data (Weights/Inputs) from Python
data: $(MEM_DATA)

weights.mem: python/train_mnist.py
	@echo [BUILD] Generating data memory files...
	$(PYTHON) python/train_mnist.py

input.mem: weights.mem
bias.mem: weights.mem
	@# No-op, just to satisfy dependencies

# 2. Generate Hex Files (Instruction/Data Memory)
sw: $(MEM_SW)

# Compile software to ELF then to Hex
software.elf: $(MAIN_C) $(CRT0) $(LINKER)
	@echo [BUILD] Compiling $(WORKLOAD) with $(CC)...
	$(CC) -O2 -march=rv32i -mabi=ilp32 -I$(C_DIR) -T $(LINKER) -nostdlib $(CRT0) $(MAIN_C) -lgcc -o software.elf

# Alternative target for assembly-only test
asm_test: $(ASM_DIR)/mmio_test.s $(LINKER)
	@echo [BUILD] Compiling Assembly Test...
	$(CC) -O2 -march=rv32i -mabi=ilp32 -T $(LINKER) -nostdlib $(ASM_DIR)/mmio_test.s -lgcc -o software.elf
	@$(MAKE) imem.hex dmem.hex

imem.bin: software.elf
	@echo [BUILD] Extracting instruction memory...
	$(OBJCOPY) -O binary -j .text -j .text.init software.elf imem.bin

dmem.bin: software.elf
	@echo [BUILD] Extracting data memory...
	$(OBJCOPY) -O binary -j .data -j .bss -j .rodata software.elf dmem.bin

imem.hex: imem.bin elf2hex.py
	@echo [BUILD] Generating imem.hex...
	$(PYTHON) elf2hex.py imem.bin imem.hex

dmem.hex: dmem.bin elf2hex.py
	@echo [BUILD] Generating dmem.hex...
	$(PYTHON) elf2hex.py dmem.bin dmem.hex

$(MEM_SW): imem.hex dmem.hex

# 3. Generate Bitstream
bitstream: $(MEM_DATA) $(MEM_SW) $(TCL_SCRIPT)
	@echo [BUILD] Starting Vivado bitstream generation...
	$(VIVADO) -mode batch -source $(TCL_SCRIPT)

# --- Utility Targets ---

clean:
	@echo [CLEAN] Removing temporary build files...
	@if exist software.elf del /Q software.elf
	@if exist imem.bin del /Q imem.bin
	@if exist dmem.bin del /Q dmem.bin
	@if exist imem.hex del /Q imem.hex
	@if exist dmem.hex del /Q dmem.hex
	@if exist weights.mem del /Q weights.mem
	@if exist input.mem del /Q input.mem
	@if exist bias.mem del /Q bias.mem
	@if exist $(BITSTREAM) del /Q $(BITSTREAM)
	@if exist vivado*.log del /Q vivado*.log
	@if exist vivado*.jou del /Q vivado*.jou
	@if exist .Xil rmdir /S /Q .Xil
