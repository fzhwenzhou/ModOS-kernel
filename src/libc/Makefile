# Makefile -- Build Modula-2 libc modules in libc/
#
# Each sub-module of libc (string, stdlib, stdio, ...) compiles
# to its own .o file.  Add new modules here as they are created.

ARCH     ?= x86_64

M2      := $(ARCH)-linux-gnu-gm2
M2FLAGS := -fno-exceptions -fno-wideset -mcmodel=large -flibs=min \
           -mno-red-zone -mno-mmx -mno-sse -O2

.PHONY: all clean

all: string.o

# ---- Modula-2 compilation ----
string.o: string.mod string.def
	$(M2) $(M2FLAGS) -c -o $@ $<

# ---- Clean ----
clean:
	rm -f *.o