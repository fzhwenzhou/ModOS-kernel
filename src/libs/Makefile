# Makefile -- Build Modula-2 library modules in libs/

M2      := gm2
M2FLAGS := -fno-exceptions -fno-wideset -mcmodel=large -flibs=min \
           -mno-red-zone -mno-mmx -mno-sse -O2

.PHONY: all clean

all: BitByteOps.o libc.o

# ---- Modula-2 compilation ----
libc.o: libc.mod libc.def
	$(M2) $(M2FLAGS) -c -o $@ $<

BitByteOps.o: BitByteOps.mod BitByteOps.def
	$(M2) $(M2FLAGS) -c -o $@ $<

# ---- Clean ----
clean:
	rm -f *.o