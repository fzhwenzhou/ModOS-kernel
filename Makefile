# Makefile -- Build and run a multiboot2 x86_64 kernel with Limine + OVMF

TOOLS   := /home/naonao/x86_64-elf-tools
LIMINE  := /home/naonao/limine-binary
OVMF    := /home/naonao/edk2-ovmf

AS      := $(TOOLS)/bin/x86_64-elf-as
LD      := $(TOOLS)/bin/x86_64-elf-ld
M2      := gm2

M2FLAGS  := -fno-exceptions -fno-wideset -mcmodel=large -flibs=min \
           -mno-red-zone -mno-mmx -mno-sse -O2 -Isrc/libs
LDFLAGS := -T src/linker.ld -nostdlib

KERNEL  := kernel.elf
ISO     := limine.iso
ISO_DIR := iso_root

# All object files that go into the kernel
OBJS    := src/boot.o src/stub.o src/Kernel.o src/libs/BitByteOps.o src/libs/libc.o

.PHONY: all clean run run-quiet src-submake

all: $(ISO)

# ---- Assembly ----
src/boot.o: src/boot.S
	$(AS) -o $@ $<

src/stub.o: src/stub.S
	$(AS) -o $@ $<

# ---- Modula-2 compilation (delegated to sub-makefiles) ----
src-submake:
	$(MAKE) -C src

# ---- Link (depends on sub-make for Modula-2 .o files) ----
$(KERNEL): src/boot.o src/stub.o src-submake src/linker.ld
	$(LD) $(LDFLAGS) -o $@ src/boot.o src/stub.o src/Kernel.o src/libs/BitByteOps.o src/libs/libc.o

# ---- ISO ----
$(ISO): $(KERNEL) limine.conf
	rm -rf $(ISO_DIR)
	mkdir -p $(ISO_DIR)
	cp $(KERNEL) $(ISO_DIR)/
	cp limine.conf $(ISO_DIR)/
	cp $(LIMINE)/limine-bios-cd.bin $(ISO_DIR)/
	cp $(LIMINE)/limine-uefi-cd.bin $(ISO_DIR)/
	xorriso -as mkisofs \
		-b limine-bios-cd.bin \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
		--efi-boot limine-uefi-cd.bin \
		-efi-boot-part \
		--efi-boot-image \
		--protective-msdos-label \
		$(ISO_DIR) -o $@
	@echo
	@echo "=== ISO created: $(ISO) ==="

# ---- QEMU ----
run: $(ISO)
	qemu-system-x86_64 \
		-M q35 \
		-m 256M \
		-cdrom $(ISO) \
		-bios $(OVMF)/ovmf-code-x86_64.fd \
		-vga std \
		-no-reboot \
		-no-shutdown \
		-d int,cpu_reset \
		-serial stdio

run-quiet: $(ISO)
	qemu-system-x86_64 \
		-M q35 \
		-m 256M \
		-cdrom $(ISO) \
		-bios $(OVMF)/ovmf-code-x86_64.fd \
		-vga std \
		-no-reboot \
		-serial stdio

# ---- Clean ----
clean:
	rm -f $(OBJS) $(KERNEL) $(ISO)
	rm -rf $(ISO_DIR)
	$(MAKE) -C src clean