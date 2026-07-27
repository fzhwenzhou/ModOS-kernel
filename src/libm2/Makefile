# Makefile -- Build architecture-independent Modula-2 utility modules (libm2)
#
# This directory holds small, architecture-independent Modula-2 helpers
# used throughout the kernel (memory utilities, etc.).  Modules here may
# depend on the libc/ directory (e.g. MemUtils wraps memcpy/memset from
# string.mod).
#
# M2, M2FLAGS are inherited from src/Makefile.  The -I. and -I../libc
# flags let modules import each other and the libc wrappers.

ARCH     ?= x86_64

M2       := $(ARCH)-linux-gnu-gm2
M2FLAGS  := -fno-exceptions -fno-wideset -flibs=min -O2

# Architecture-specific flags
ifeq ($(ARCH),x86_64)
M2FLAGS += -mcmodel=large -mno-red-zone -mno-mmx -mno-sse
endif

M2INCLUDES := -I. -I../libc

.PHONY: all clean

all: MemUtils.o

# ---- Modula-2 compilation ----
# MemUtils wraps memcpy/memset from ../libc/string.mod.
MemUtils.o: MemUtils.mod MemUtils.def ../libc/string.def
	$(M2) $(M2FLAGS) $(M2INCLUDES) -c -o $@ $<

# ---- Clean ----
clean:
	rm -f *.o
