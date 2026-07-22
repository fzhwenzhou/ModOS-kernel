# Makefile -- Top-level build for ModOS-kernel
#
# Builds the kernel ELF.  ISO packaging and QEMU launching are
# handled by build.sh and run.sh respectively.
#
# Usage:
#   make                # build kernel.elf
#   make clean          # remove all build artifacts
#   make ARCH=arch      # override architecture (default: x86_64)

ARCH    ?= x86_64

export ARCH

AS      := $(ARCH)-elf-as
LD      := $(ARCH)-elf-ld
M2      := $(ARCH)-linux-gnu-gm2

export AS M2

# ------------------------------------------------------------------
# Architecture-independent compiler flags
# ------------------------------------------------------------------
M2FLAGS := -fno-exceptions -fno-wideset -flibs=min -O2

# ------------------------------------------------------------------
# Architecture-specific compiler flags
# ------------------------------------------------------------------
ifeq ($(ARCH),x86_64)
M2FLAGS += -mcmodel=large -mno-red-zone -mno-mmx -mno-sse
endif

export M2FLAGS

KERNEL := kernel.elf

# ------------------------------------------------------------------
# Object file list — extend by adding new subdirectories here
# ------------------------------------------------------------------
ARCH_OBJS := \
    src/arch/$(ARCH)/boot/boot.o \
    src/arch/$(ARCH)/ArchMain.o \
    src/arch/$(ARCH)/libm2/BitByteOps.o

KERNEL_OBJS := \
    src/stub.o \
    src/Main.o \
    $(ARCH_OBJS) \
    src/libc/string.o

# Linker script (architecture-specific)
LDSCRIPT := src/arch/$(ARCH)/linker.ld

.PHONY: all clean src-submake

all: $(KERNEL)

# ---- Delegate to src/ sub-make ----
src-submake:
	$(MAKE) -C src

# ---- Link ----
$(KERNEL): src-submake $(LDSCRIPT)
	$(LD) -T $(LDSCRIPT) -nostdlib -o $@ $(KERNEL_OBJS)

# ---- Clean ----
clean:
	rm -rf $(KERNEL)
	$(MAKE) -C src clean