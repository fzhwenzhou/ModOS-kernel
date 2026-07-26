/* linker.ld — Linker script for Limine-booted x86_64 higher-half kernel
 *
 * With Limine there is no need for a separate 32-bit boot trampoline
 * or manually-constructed page tables — the bootloader enters the
 * kernel directly in 64-bit long mode with paging enabled and the
 * kernel mapped at its linked higher-half address.
 *
 * Limine request structures are placed in a dedicated, retained
 * section in the required order: start marker, requests, end marker.
 */
OUTPUT_FORMAT(elf64-x86-64)
ENTRY(ArchMain_KernelMain)

VIRT_BASE = 0xFFFFFFFF80000000;

SECTIONS
{
    . = VIRT_BASE + 1M;

    .text ALIGN(4K) : {
        *(.text .text.*)
    }

    .rodata ALIGN(4K) : {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        *(.sdata2 .sdata2.*)
    }

    .data ALIGN(4K) : {
        /* Limine request markers and structures — must be kept,
           and must appear in this exact order. */
        KEEP(*(.limine_requests_start_marker))
        KEEP(*(.limine_requests))
        KEEP(*(.limine_requests_end_marker))

        *(.data .data.*)
        *(.sdata .sdata.*)
    }

    .bss ALIGN(4K) : {
        *(COMMON)
        *(.bss .bss.*)
        *(.sbss .sbss.*)
    }

    kernel_end = .;

    /DISCARD/ : {
        *(.comment)
        *(.note.GNU-stack)
        *(.eh_frame)
        *(.debug_*)
    }
}
