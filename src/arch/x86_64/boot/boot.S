# boot.asm - Multiboot2 x86_64 kernel entry point
# Assembles with: x86_64-elf-as (GNU assembler)

.intel_syntax noprefix

.section .multiboot_header, "a"
.align 8

# Multiboot2 header
mb2_header:
    .long 0xE85250D6
    .long 0
    .long mb2_end - mb2_header
    .long -(0xE85250D6 + 0 + (mb2_end - mb2_header))

# Information request tag (type 1) - ask for framebuffer info
# size = 12 (8 header + 4 for one requested tag)
.align 8
    .word 1
    .word 0
    .long 12
    .long 8

# Framebuffer request tag (type 5)
.align 8
    .word 5
    .word 0
    .long 20
    .long 1024
    .long 768
    .long 32

# End tag (type 0)
.align 8
    .word 0
    .word 0
    .long 8
mb2_end:

#=============================================================================
# 32-bit entry point
#=============================================================================
.section .text, "ax"
.global _start
.code32

_start:
    # Save multiboot registers to memory (zero_page clobbers edi!)
    lea    edi, [mboot_saved]
    mov    [edi], eax          # mboot_magic = EAX (0x36d76289)
    mov    [edi + 4], ebx      # mboot_ebx = EBX (mbi address)

    # Set up temporary stack
    lea    esp, [stack_top]

    # Zero out page table pages
    lea    eax, [pml4]
    call   zero_page

    lea    eax, [pdpt]
    call   zero_page

    lea    eax, [pd0]
    call   zero_page

    lea    eax, [pd1]
    call   zero_page

    lea    eax, [pd2]
    call   zero_page

    lea    eax, [pd3]
    call   zero_page

    # PML4[0] = pdpt (Present | RW)
    lea    eax, [pdpt]
    or     eax, 0x3
    lea    ebx, [pml4]
    mov    [ebx], eax

    # PDPT[0..3] = pd0..pd3 (Present | RW)
    lea    eax, [pd0]
    or     eax, 0x3
    lea    ebx, [pdpt]
    mov    [ebx], eax

    lea    eax, [pd1]
    or     eax, 0x3
    mov    [ebx + 8], eax

    lea    eax, [pd2]
    or     eax, 0x3
    mov    [ebx + 16], eax

    lea    eax, [pd3]
    or     eax, 0x3
    mov    [ebx + 24], eax

    # Fill PD0: identity map 0 - 1 GB with 2MB pages
    lea    eax, [pd0]
    xor    edx, edx
    mov    ecx, 512
1:  mov    ebx, edx
    shl    ebx, 21
    or     ebx, 0x83
    mov    [eax + edx * 8], ebx
    inc    edx
    loop   1b

    # Fill PD1: identity map 1 GB - 2 GB
    lea    eax, [pd1]
    xor    ecx, ecx
2:  mov    ebx, edx
    shl    ebx, 21
    or     ebx, 0x83
    mov    [eax + ecx * 8], ebx
    inc    ecx
    inc    edx
    cmp    ecx, 512
    jb     2b

    # Fill PD2: identity map 2 GB - 3 GB
    lea    eax, [pd2]
    xor    ecx, ecx
3:  mov    ebx, edx
    shl    ebx, 21
    or     ebx, 0x83
    mov    [eax + ecx * 8], ebx
    inc    ecx
    inc    edx
    cmp    ecx, 512
    jb     3b

    # Fill PD3: identity map 3 GB - 4 GB
    lea    eax, [pd3]
    xor    ecx, ecx
4:  mov    ebx, edx
    shl    ebx, 21
    or     ebx, 0x83
    mov    [eax + ecx * 8], ebx
    inc    ecx
    inc    edx
    cmp    ecx, 512
    jb     4b

    # Enable PAE (CR4.PAE = 1)
    mov    eax, cr4
    or     eax, (1 << 5)
    mov    cr4, eax

    # Set CR3 = PML4 physical address
    lea    eax, [pml4]
    mov    cr3, eax

    # Enable long mode (EFER.LME = 1)
    mov    ecx, 0xC0000080
    rdmsr
    or     eax, (1 << 8)
    wrmsr

    # Enable paging (CR0.PG = 1)
    mov    eax, cr0
    or     eax, (1 << 31)
    mov    cr0, eax

    # Load GDT with 64-bit code segment
    lgdt   [gdt64_ptr]

    # Transition to 64-bit mode via push + retf
    # (more reliable than a far jump in some emulators)
    push   0x08                    # 64-bit code segment selector
    lea    eax, [long_mode_entry]
    push   eax                     # target address
    retf

# Helper: zero a page (uses rep stosd)
# eax = start address
zero_page:
    mov    edi, eax
    xor    eax, eax
    mov    ecx, 1024                  # 4096 / 4
    cld
    rep stosd
    ret

#=============================================================================
# 64-bit entry point
#=============================================================================
.code64
long_mode_entry:
    # Set up data segments
    mov    ax, 0x10
    mov    ds, ax
    mov    es, ax
    mov    fs, ax
    mov    gs, ax
    mov    ss, ax

    # Set up stack
    lea    rsp, [stack_top]
    and    rsp, ~15

    # Restore multiboot registers from saved memory
    lea    rax, [mboot_saved]
    mov    edi, [rax]          # rdi = magic (zero-extended from 32-bit)
    mov    esi, [rax + 4]      # rsi = mbi addr (zero-extended from 32-bit)

    # Call ArchMain_KernelMain(magic, mbi_addr)
    call   ArchMain_KernelMain

.halt:
    hlt
    jmp    .halt

#=============================================================================
# GDT (must be 8-byte aligned!)
#=============================================================================
.section .data
.align 8
gdt64_start:
    .quad 0x0000000000000000        # null descriptor (0x00)

    # 64-bit code segment (0x08)
    .word 0xFFFF                    # limit 0-15
    .word 0x0000                    # base 0-15
    .byte 0x00                      # base 16-23
    .byte 0x9A                      # access byte: P=1, DPL=0, S=1, code, exec/read
    .byte 0xAF                      # flags: G=1, L=1, D=0, limit 16-19=0xF
    .byte 0x00                      # base 24-31

    # 64-bit data segment (0x10)
    .word 0x0000                    # limit 0-15
    .word 0x0000                    # base 0-15
    .byte 0x00                      # base 16-23
    .byte 0x92                      # access byte: P=1, DPL=0, S=1, data, read/write
    .byte 0xAF                      # flags: G=1, L=0, D=0, limit 16-19=0xF
    .byte 0x00                      # base 24-31
gdt64_end:

gdt64_ptr:
    .word gdt64_end - gdt64_start - 1   # limit
    .long gdt64_start                   # base (32-bit pointer for 32-bit mode)

#=============================================================================
# BSS
#=============================================================================
.section .bss
.align 4096
pml4:
    .skip 4096
pdpt:
    .skip 4096
pd0:
    .skip 4096
pd1:
    .skip 4096
pd2:
    .skip 4096
pd3:
    .skip 4096

.align 16
stack_bottom:
    .skip 32768
stack_top:

# Saved multiboot registers
.section .data
.align 8
mboot_saved:
    .skip 8                     # [0..3] = magic (EAX), [4..7] = mbi_addr (EBX)