# Makefile -- Build x86_64 architecture-specific modules
#
# ARCH, TOOLS, AS, M2, M2FLAGS are inherited from src/Makefile.

ARCH     ?= x86_64

AS       := $(ARCH)-elf-as
M2       := $(ARCH)-linux-gnu-gm2

M2FLAGS  := -fno-exceptions -fno-wideset -flibs=min -O2 \
            -mcmodel=large -mno-red-zone -mno-mmx -mno-sse

# Include paths:
#   .            — GDT and other arch-local modules
#   ../../boot/  — architecture-independent Limine def
#   ../../       — Main module
#   ../../libm2/ — arch-independent utilities (MemUtils)
#   libm2/       — arch-specific Modula-2 helpers (BitByteOps)
M2INCLUDES := -I. -I../../boot -I../../ -I../../libm2 -Ilibm2

.PHONY: all clean libm2-submake

all: boot/boot.o ArchMain.o GDT.o libm2-submake

# ---- Assembly ----
boot/boot.o: boot/boot.S
	$(AS) -o $@ $<

# ---- Modula-2 compilation ----
# GDT.mod imports from libm2/ (BitByteOps) and ../../libm2/ (MemUtils).
GDT.o: GDT.mod GDT.def libm2-submake
	$(M2) $(M2FLAGS) $(M2INCLUDES) -c -o $@ $<

# ArchMain.mod imports from ../../boot/ (Limine),
# ../../ (Main), libm2/ (BitByteOps), ../../libm2/ (MemUtils),
# and ./ (GDT).
ArchMain.o: ArchMain.mod ArchMain.def ../../boot/Limine.def GDT.def
	$(M2) $(M2FLAGS) $(M2INCLUDES) -c -o $@ $<

# ---- Delegate to libm2/ (arch-specific helpers) ----
libm2-submake:
	$(MAKE) -C libm2 M2=$(M2) M2FLAGS='$(M2FLAGS)'

# ---- Clean ----
clean:
	rm -f *.o boot/*.o
	$(MAKE) -C libm2 clean
