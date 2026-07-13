# Makefile -- Build Modula-2 kernel modules in src/ and libs/

M2      := gm2
M2FLAGS := -fno-exceptions -fno-wideset -mcmodel=large -flibs=min \
           -mno-red-zone -mno-mmx -mno-sse -O2 -Ilibs

.PHONY: all clean libs-submake

all: Kernel.o libs-submake

# ---- Modula-2 compilation ----
Kernel.o: Kernel.mod Kernel.def Multiboot2.def
	$(M2) $(M2FLAGS) -c -o $@ $<

# ---- Delegate to libs/ ----
libs-submake:
	$(MAKE) -C libs

# ---- Clean ----
clean:
	rm -f *.o
	$(MAKE) -C libs clean