/* linker.ld — Linker script for the multiboot2 x86_64 kernel */
OUTPUT_FORMAT(elf64-x86-64)
ENTRY(_start)

SECTIONS
{
    /* Load at 1 MB physical address */
    . = 0x100000;

    .multiboot_header : {
        *(.multiboot_header)
    }

    .text : {
        *(.text)
        *(.text.*)
    }

    .data : {
        *(.data)
        *(.data.*)
    }

    .bss : {
        *(COMMON)
        *(.bss)
        *(.bss.*)
    }

    /DISCARD/ : {
        *(.comment)
        *(.note.*)
        *(.eh_frame)
        *(.debug_*)
    }
}