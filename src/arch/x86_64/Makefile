# Makefile -- Build x86_64 architecture-specific modules
#
# ARCH, TOOLS, AS, M2, M2FLAGS are inherited from src/Makefile.

ARCH     ?= x86_64

AS       := $(ARCH)-elf-as
M2       := $(ARCH)-linux-gnu-gm2

M2FLAGS  := -fno-exceptions -fno-wideset -flibs=min -O2 \
            -mcmodel=large -mno-red-zone -mno-mmx -mno-sse

# Include paths:
#   ../../boot/  — architecture-independent Limine def
#   ../../       — Main module
#   libm2/       — BitByteOps module
M2INCLUDES := -I../../boot -I../../ -Ilibm2

.PHONY: all clean libm2-submake

all: boot/boot.o ArchMain.o libm2-submake

# ---- Assembly ----
boot/boot.o: boot/boot.S
	$(AS) -o $@ $<

# ---- Modula-2 compilation ----
# ArchMain.mod imports from ../../boot/ (Limine),
# ../../ (Main), and libm2/ (BitByteOps).
ArchMain.o: ArchMain.mod ArchMain.def ../../boot/Limine.def
	$(M2) $(M2FLAGS) $(M2INCLUDES) -c -o $@ $<

# ---- Delegate to libm2/ ----
libm2-submake:
	$(MAKE) -C libm2 M2=$(M2) M2FLAGS='$(M2FLAGS)'

# ---- Clean ----
clean:
	rm -f *.o boot/*.o
	$(MAKE) -C libm2 clean
