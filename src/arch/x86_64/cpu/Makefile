# Makefile -- Build x86_64 CPU-specific modules (GDT, IDT, Exceptions, ...)
#
# This directory holds per-CPU structures and setup code that run early
# in kernel startup: the Global Descriptor Table / Task State Segment,
# the Interrupt Descriptor Table, and CPU exception handlers.
#
# ARCH, AS, M2, M2FLAGS are inherited from arch/x86_64/Makefile.

ARCH     ?= x86_64
AS       := $(ARCH)-elf-as
M2       := $(ARCH)-linux-gnu-gm2

M2FLAGS  := -fno-exceptions -fno-wideset -flibs=min -O2 \
           -mcmodel=large -mno-red-zone -mno-mmx -mno-sse

# Include paths (relative to this directory, src/arch/x86_64/cpu/):
#   .               - CPU-local modules (GDT, IDT, Exceptions)
#   ../../../libm2  - arch-independent utilities (MemUtils)
#   ../libm2        - arch-specific helpers (BitByteOps)
M2INCLUDES := -I. -I../../../libm2 -I../libm2

.PHONY: all clean

all: GDT.o IDT.o Exceptions.o isr.o

# ---- Assembly ----
isr.o: isr.S
	$(AS) -o $@ $<

# ---- Modula-2 compilation ----
# GDT.mod imports MemUtils from ../../../libm2/.
GDT.o: GDT.mod GDT.def
	$(M2) $(M2FLAGS) $(M2INCLUDES) -c -o $@ $<

# IDT.mod imports MemUtils from ../../../libm2/.
IDT.o: IDT.mod IDT.def
	$(M2) $(M2FLAGS) $(M2INCLUDES) -c -o $@ $<

# Exceptions.mod imports InstallInterrupt from IDT, and ByteAnd
# from ../libm2/BitByteOps.
Exceptions.o: Exceptions.mod Exceptions.def IDT.def
	$(M2) $(M2FLAGS) $(M2INCLUDES) -c -o $@ $<

# ---- Clean ----
clean:
	rm -f *.o
