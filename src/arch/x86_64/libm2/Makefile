# Makefile -- Build Modula-2 runtime library modules (libm2)
#
# M2, M2FLAGS are inherited from arch/x86_64/Makefile.

M2      := gm2
M2FLAGS := -fno-exceptions -fno-wideset -flibs=min -O2 \
           -mcmodel=large -mno-red-zone -mno-mmx -mno-sse

.PHONY: all clean

all: BitByteOps.o

# ---- Modula-2 compilation ----
BitByteOps.o: BitByteOps.mod BitByteOps.def
	$(M2) $(M2FLAGS) -c -o $@ $<

# ---- Clean ----
clean:
	rm -f *.o