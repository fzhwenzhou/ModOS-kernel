# Makefile -- Build Modula-2 kernel modules in src/
#
# ARCH and TOOLS are inherited from the top-level Makefile.
# Delegates to architecture-specific and libc sub-makes.

ARCH     ?= x86_64
TOOLS    ?= /home/naonao/$(ARCH)-elf-tools

AS       := $(TOOLS)/bin/$(ARCH)-elf-as
M2       := gm2

M2FLAGS  := -fno-exceptions -fno-wideset -flibs=min -O2

# Architecture-specific flags
ifeq ($(ARCH),x86_64)
M2FLAGS += -mcmodel=large -mno-red-zone -mno-mmx -mno-sse
endif

.PHONY: all clean arch-submake libc-submake

all: stub.o Main.o arch-submake libc-submake

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
	$(MAKE) -C libc M2=$(M2) M2FLAGS='$(M2FLAGS)'

# ---- Clean ----
clean:
	rm -f *.o
	$(MAKE) -C arch/$(ARCH) clean ARCH=$(ARCH)
	$(MAKE) -C libc clean