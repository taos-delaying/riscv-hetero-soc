# Run from the project root with: make -C sw FFT_IMPL=sw (or FFT_IMPL=hw).
# Build a complete RAM-resident firmware image for the current soc_top.
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:

FFT_IMPL ?= sw
TOOLCHAIN_PREFIX ?= riscv64-unknown-elf-
RISCV_CC = $(TOOLCHAIN_PREFIX)gcc
RISCV_AR = $(TOOLCHAIN_PREFIX)ar
RISCV_OBJCOPY = $(TOOLCHAIN_PREFIX)objcopy
PYTHON ?= python3

PROJECT_ROOT := $(abspath ..)
SW_DIR := $(PROJECT_ROOT)/sw
NMSIS_DIR := $(PROJECT_ROOT)/ip/picorv32/third_party/nmsis/NMSIS
MAKEHEX := $(PROJECT_ROOT)/ip/picorv32/firmware/makehex.py
LINKER_SCRIPT := $(SW_DIR)/soc.ld

ifneq ($(FFT_IMPL),sw)
ifneq ($(FFT_IMPL),hw)
$(error FFT_IMPL must be sw or hw)
endif
endif

# Separate directories prevent a backend switch from reusing the other backend.
BUILD_DIR := $(PROJECT_ROOT)/build/fft32/$(FFT_IMPL)
LIBRARY := $(BUILD_DIR)/libfft32_q15.a
EXAMPLE_OBJECT := $(BUILD_DIR)/example_main.o
STARTUP_OBJECT := $(BUILD_DIR)/start.o
RUNTIME_OBJECT := $(BUILD_DIR)/runtime.o
ELF := $(BUILD_DIR)/firmware.elf
BINARY := $(BUILD_DIR)/firmware.bin
HEX := $(BUILD_DIR)/firmware.hex
MAP := $(BUILD_DIR)/firmware.map

# Both variants target the same current soc_top CPU configuration.
ARCH_FLAGS := -march=rv32i -mabi=ilp32 -mno-relax
CFLAGS ?= -O2 -std=c99 -Wall -Wextra
FFT_CFLAGS := -ffreestanding -ffunction-sections -fdata-sections -fno-strict-aliasing
BAREMETAL_CFLAGS := -fno-pic -fno-pie -fno-stack-protector \
	-fno-unwind-tables -fno-asynchronous-unwind-tables
PUBLIC_INCLUDES := -I$(SW_DIR)
NMSIS_INCLUDES := -isystem $(NMSIS_DIR)/DSP/Include -isystem $(NMSIS_DIR)/Core/Include

ifeq ($(FFT_IMPL),sw)
BACKEND_SOURCE := $(SW_DIR)/fft32_sw.c
BACKEND_INCLUDES := $(PUBLIC_INCLUDES) $(NMSIS_INCLUDES)
# Reuse the existing, licensed scalar NMSIS source subset without copying it.
NMSIS_SOURCES := \
	TransformFunctions/riscv_cfft_q15.c \
	TransformFunctions/riscv_cfft_radix4_q15.c \
	TransformFunctions/riscv_bitreversal2.c \
	TransformFunctions/riscv_bitreversal.c \
	CommonTables/riscv_const_structs.c \
	CommonTables/riscv_common_tables.c
NMSIS_OBJECTS := $(addprefix $(BUILD_DIR)/nmsis/,$(NMSIS_SOURCES:.c=.o))
else
BACKEND_SOURCE := $(SW_DIR)/fft32_hw.c
BACKEND_INCLUDES := $(PUBLIC_INCLUDES)
NMSIS_OBJECTS :=
endif

LIBRARY_OBJECTS := $(BUILD_DIR)/fft32_backend.o $(NMSIS_OBJECTS)
FIRMWARE_OBJECTS := $(STARTUP_OBJECT) $(EXAMPLE_OBJECT) $(RUNTIME_OBJECT)
DEPENDENCIES := $(LIBRARY_OBJECTS:.o=.d) $(FIRMWARE_OBJECTS:.o=.d)

.PHONY: all library elf hex
all: $(ELF) $(HEX)
library: $(LIBRARY)
elf: $(ELF)
hex: $(HEX)

$(BUILD_DIR)/fft32_backend.o: $(BACKEND_SOURCE) $(SW_DIR)/fft32_q15.h Makefile
	mkdir -p $(dir $@)
	$(RISCV_CC) $(CPPFLAGS) $(BACKEND_INCLUDES) $(CFLAGS) $(FFT_CFLAGS) $(BAREMETAL_CFLAGS) $(ARCH_FLAGS) -MD -MP -c $< -o $@

$(BUILD_DIR)/nmsis/%.o: $(NMSIS_DIR)/DSP/Source/%.c Makefile
	mkdir -p $(dir $@)
	$(RISCV_CC) $(CPPFLAGS) $(NMSIS_INCLUDES) $(CFLAGS) $(FFT_CFLAGS) $(BAREMETAL_CFLAGS) $(ARCH_FLAGS) -MD -MP -c $< -o $@

$(EXAMPLE_OBJECT): $(SW_DIR)/example_main.c $(SW_DIR)/fft32_q15.h Makefile
	mkdir -p $(dir $@)
	$(RISCV_CC) $(CPPFLAGS) $(PUBLIC_INCLUDES) $(CFLAGS) $(FFT_CFLAGS) $(BAREMETAL_CFLAGS) $(ARCH_FLAGS) -MD -MP -c $< -o $@

$(STARTUP_OBJECT): $(SW_DIR)/start.S Makefile
	mkdir -p $(dir $@)
	$(RISCV_CC) $(CPPFLAGS) $(ARCH_FLAGS) -fno-pic -fno-pie -MD -MP -c $< -o $@

$(RUNTIME_OBJECT): $(SW_DIR)/runtime.c Makefile
	mkdir -p $(dir $@)
	$(RISCV_CC) $(CPPFLAGS) $(CFLAGS) $(FFT_CFLAGS) $(BAREMETAL_CFLAGS) $(ARCH_FLAGS) -fno-builtin -fno-tree-loop-distribute-patterns -MD -MP -c $< -o $@

$(LIBRARY): $(LIBRARY_OBJECTS) Makefile
	$(RISCV_AR) rcs $@ $(LIBRARY_OBJECTS)

# Own startup/runtime, no host OS, newlib startup, or old testbench MMIO.
# -lgcc must be the matching RV32I/ILP32 multilib (e.g. software integer multiply).
$(ELF): $(FIRMWARE_OBJECTS) $(LIBRARY) $(LINKER_SCRIPT) Makefile
	$(RISCV_CC) $(LDFLAGS) $(ARCH_FLAGS) -static -nostdlib -no-pie \
		-Wl,--gc-sections,--build-id=none,--no-relax \
		-Wl,-T,$(LINKER_SCRIPT),-Map,$(MAP) -o $@ \
		$(FIRMWARE_OBJECTS) $(LIBRARY) -lgcc

$(BINARY): $(ELF) Makefile
	$(RISCV_OBJCOPY) -O binary --gap-fill=0 $< $@

# A RAM word is 32 bits: 16384 words = 65536 bytes.
# The linker aligns file-backed sections to 4 bytes and reserves the top 4 KiB
# for the NOLOAD stack, satisfying makehex.py's size/alignment requirements.
$(HEX): $(BINARY) $(MAKEHEX) Makefile
	$(PYTHON) $(MAKEHEX) $< 16384 > $@.tmp
	mv $@.tmp $@

-include $(DEPENDENCIES)
