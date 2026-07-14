# Makefile -- Build x86_64 architecture-specific modules
#
# ARCH, TOOLS, AS, M2, M2FLAGS are inherited from src/Makefile.

ARCH     ?= x86_64
TOOLS    ?= /home/naonao/$(ARCH)-elf-tools

AS       := $(TOOLS)/bin/$(ARCH)-elf-as
M2       := gm2

M2FLAGS  := -fno-exceptions -fno-wideset -flibs=min -O2 \
            -mcmodel=large -mno-red-zone -mno-mmx -mno-sse

.PHONY: all clean libm2-submake

all: boot/boot.o ArchMain.o libm2-submake

# ---- Assembly ----
boot/boot.o: boot/boot.S
	$(AS) -o $@ $<

# ---- Modula-2 compilation ----
# ArchMain.mod imports from boot/ (Multiboot2) and ../../ (Main)
ArchMain.o: ArchMain.mod ArchMain.def boot/Multiboot2.def
	$(M2) $(M2FLAGS) -Iboot -I../../ -c -o $@ $<

# ---- Delegate to libm2/ ----
libm2-submake:
	$(MAKE) -C libm2 M2=$(M2) M2FLAGS='$(M2FLAGS)'

# ---- Clean ----
clean:
	rm -f *.o boot/*.o
	$(MAKE) -C libm2 clean