/* linker.ld — Linker script for higher-half x86_64 kernel
 *
 * Boot sections (multiboot header, 32-bit entry, trampoline, GDT,
 * page tables, early stack) are linked and loaded at 1 MB physical.
 *
 * Kernel sections (.text, .data, .bss) are linked at the higher-half
 * virtual address (0xFFFFFFFF80100000) but loaded right after the
 * boot sections in the physical image.
 */
OUTPUT_FORMAT(elf64-x86-64)
ENTRY(_start)

VIRT_BASE = 0xFFFFFFFF80000000;

SECTIONS
{
    /* ================================================================
     * Boot sections — low-address (physical = virtual)
     * ================================================================ */
    . = 1M;

    .multiboot_header : {
        *(.multiboot_header)
    }

    .boot.text : {
        *(.boot.text)
    }

    .boot.data : {
        *(.boot.data)
    }

    .boot.bss : {
        *(.boot.bss)
    }

    /* Record where the boot image ends in physical memory */
    . = ALIGN(4K);
    boot_end_phys = .;

    /* ================================================================
     * Higher-half kernel sections
     * ================================================================ */
    . = VIRT_BASE + boot_end_phys;

    .text : AT(boot_end_phys) {
        *(.text)
        *(.text.*)
    }

    .data : AT(ADDR(.data) - VIRT_BASE) {
        *(.data)
        *(.data.*)
    }

    .bss : AT(ADDR(.bss) - VIRT_BASE) {
        *(COMMON)
        *(.bss)
        *(.bss.*)
    }

    kernel_end_virt = .;

    /DISCARD/ : {
        *(.comment)
        *(.note.*)
        *(.eh_frame)
        *(.debug_*)
    }
}