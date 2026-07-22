# Makefile -- Build aarch64 architecture-specific modules
#
# ARCH, TOOLS, AS, M2, M2FLAGS are inherited from src/Makefile.
# Stub — add aarch64 boot code, modules, and linker script here.

ARCH    ?= aarch64

AS      := $(ARCH)-elf-as
M2      := $(ARCH)-linux-gnu-gm2

M2FLAGS := -fno-exceptions -fno-wideset -flibs=min -O2

.PHONY: all clean

all:

# ---- Clean ----
clean:
	rm -f *.o