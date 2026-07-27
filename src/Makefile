# Makefile -- Build Modula-2 kernel modules in src/
#
# ARCH and TOOLS are inherited from the top-level Makefile.
# Delegates to the architecture-specific sub-make, the libc
# sub-make, and the architecture-independent libm2 sub-make.

ARCH     ?= x86_64

AS       := $(ARCH)-elf-as
M2       := $(ARCH)-linux-gnu-gm2

M2FLAGS  := -fno-exceptions -fno-wideset -flibs=min -O2

# Architecture-specific flags
ifeq ($(ARCH),x86_64)
M2FLAGS += -mcmodel=large -mno-red-zone -mno-mmx -mno-sse
endif

.PHONY: all clean arch-submake libc-submake libm2-submake

all: stub.o Main.o libc-submake libm2-submake arch-submake

# ---- Assembly ----
stub.o: stub.S
	$(AS) -o $@ $<

# ---- Modula-2 compilation ----
Main.o: Main.mod Main.def
	$(M2) $(M2FLAGS) -c -o $@ $<

# ---- Delegate to architecture-specific code ----
arch-submake:
	$(MAKE) -C arch/$(ARCH) ARCH=$(ARCH) TOOLS=$(TOOLS) AS=$(AS) M2=$(M2) M2FLAGS='$(M2FLAGS)'

# ---- Delegate to libc/ ----
libc-submake:
	$(MAKE) -C libc ARCH=$(ARCH) M2=$(M2) M2FLAGS='$(M2FLAGS)'

# ---- Delegate to libm2/ (arch-independent Modula-2 utilities) ----
libm2-submake: libc-submake
	$(MAKE) -C libm2 ARCH=$(ARCH) M2=$(M2) M2FLAGS='$(M2FLAGS)'

# ---- Clean ----
clean:
	rm -f *.o
	$(MAKE) -C arch/$(ARCH) clean ARCH=$(ARCH)
	$(MAKE) -C libc clean
	$(MAKE) -C libm2 clean
