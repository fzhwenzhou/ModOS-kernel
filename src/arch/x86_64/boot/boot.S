# boot.S — Multiboot2 x86_64 higher-half kernel entry point
# Assembles with: x86_64-elf-as (GNU assembler)
#
# Boot flow:
#   1. 32-bit entry (_start) — save multiboot info, set up page tables
#      (identity map first 4 GB + higher-half map kernel at 0xFFFFFFFF80000000)
#   2. Enable PAE → long mode → paging
#   3. retf to trampoline64 (identity-mapped, 64-bit)
#   4. trampoline64 → absolute jmp to higher_half_entry (at 0xFFFFFFFF80xxxxxx)
#   5. higher_half_entry → set up stack, call ArchMain_KernelMain

.intel_syntax noprefix

# =============================================================================
# Multiboot2 header — must be in the first 32 KB of the image
# =============================================================================
.section .multiboot_header, "a"
.align 8

mb2_header:
    .long 0xE85250D6              # magic
    .long 0                        # architecture (0 = protected mode i386)
    .long mb2_end - mb2_header     # header length
    .long -(0xE85250D6 + 0 + (mb2_end - mb2_header))  # checksum

# End tag (type 0)
.align 8
    .word 0                        # type
    .word 0                        # flags
    .long 8                        # size
mb2_end:

# =============================================================================
# 32-bit entry point — runs identity-mapped at physical address
# =============================================================================
.section .boot.text, "ax"
.global _start
.code32

_start:
    # Save multiboot registers to memory (zero_page clobbers edi!)
    lea    edi, [mboot_saved]
    mov    [edi], eax              # mboot_magic = EAX (0x36d76289)
    mov    [edi + 4], ebx          # mboot_ebx = EBX (mbi address)

    # Set up temporary stack (identity-mapped)
    lea    esp, [stack_top]

    # =========================================================================
    # Build identity-mapping page tables (PML4[0], PDPT[0..3], PD0..PD3)
    # Maps first 4 GB with 2 MB pages — used for framebuffer, multiboot info,
    # and the boot transition.
    # =========================================================================

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
    or     ebx, 0x83               # Present | RW | Huge
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

    # =========================================================================
    # Build higher-half page tables
    #
    # Virtual 0xFFFFFFFF80000000 maps to physical 0x0.
    #   PML4 index:   (0xFFFFFFFF80000000 >> 39) & 0x1FF = 511
    #   PDPT index:   (0xFFFFFFFF80000000 >> 30) & 0x1FF = 510
    #   PD index:     (0xFFFFFFFF80000000 >> 21) & 0x1FF = 0
    #
    # We map the first 2 MB (physical 0x0 – 0x200000) to cover the kernel
    # image which is loaded at physical 1 MB.
    # =========================================================================

    # PML4[511] = pdpt_high (Present | RW)
    lea    eax, [pdpt_high]
    or     eax, 0x3
    mov    [pml4 + 511 * 8], eax

    # PDPT_high[510] = pd_high (Present | RW)
    lea    eax, [pd_high]
    or     eax, 0x3
    mov    [pdpt_high + 510 * 8], eax

    # PD_high[0] = 2 MB page at physical 0x0 (Present | RW | Huge)
    mov    dword ptr [pd_high], 0x83
    mov    dword ptr [pd_high + 4], 0

    # =========================================================================
    # Enable PAE (CR4.PAE = 1)
    # =========================================================================
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

    # =========================================================================
    # Transition to 64-bit mode via push + retf
    # The target (trampoline64) is in .boot.text — identity-mapped, fits in 32 bits.
    # =========================================================================
    lgdt   [gdt64_ptr]

    push   0x08                    # 64-bit code segment selector
    lea    eax, [trampoline64]
    push   eax                     # target address (identity-mapped)
    retf

# =============================================================================
# 64-bit trampoline — still identity-mapped; jumps to higher-half
# =============================================================================
.code64
trampoline64:
    # Set up data segments
    mov    ax, 0x10
    mov    ds, ax
    mov    es, ax
    mov    fs, ax
    mov    gs, ax
    mov    ss, ax

    # Set up temporary 64-bit stack (identity-mapped, still accessible)
    lea    rsp, [stack_top]
    and    rsp, ~15

    # Absolute jump to the higher-half entry point
    mov    rax, offset higher_half_entry
    jmp    rax

# =============================================================================
# Higher-half 64-bit entry point — kernel runs at 0xFFFFFFFF80xxxxxx
# =============================================================================
.section .text, "ax"
.code64
higher_half_entry:
    # Reload segment registers (still using the same GDT, which is fine
    # because 64-bit mode ignores segment bases for CS/DS/ES/SS)
    mov    ax, 0x10
    mov    ds, ax
    mov    es, ax
    mov    fs, ax
    mov    gs, ax
    mov    ss, ax

    # Set up higher-half stack.  We use the boot stack area via its
    # identity-mapped physical address.  The identity mapping is still
    # active so this is safe.
    mov    rsp, offset stack_top
    and    rsp, ~15

    # Restore multiboot registers from saved memory.
    # mboot_saved is in .boot.data (low address).  Use absolute
    # addressing since RIP-relative displacement would overflow.
    mov    rax, offset mboot_saved
    mov    edi, [rax]              # rdi = magic
    mov    esi, [rax + 4]          # rsi = mbi addr

    # Call ArchMain_KernelMain(magic, mbi_addr)
    call   ArchMain_KernelMain

.halt:
    hlt
    jmp    .halt

# =============================================================================
# GDT (must be 8-byte aligned!)
# =============================================================================
.section .boot.data, "aw"
.align 8
gdt64_start:
    .quad 0x0000000000000000        # null descriptor (0x00)

    # 64-bit code segment (0x08)
    .word 0xFFFF                    # limit 0-15
    .word 0x0000                    # base 0-15
    .byte 0x00                      # base 16-23
    .byte 0x9A                      # access: P=1, DPL=0, S=1, code, exec/read
    .byte 0xAF                      # flags: G=1, L=1, D=0, limit 16-19=0xF
    .byte 0x00                      # base 24-31

    # 64-bit data segment (0x10)
    .word 0x0000                    # limit 0-15
    .word 0x0000                    # base 0-15
    .byte 0x00                      # base 16-23
    .byte 0x92                      # access: P=1, DPL=0, S=1, data, read/write
    .byte 0xAF                      # flags: G=1, L=0, D=0, limit 16-19=0xF
    .byte 0x00                      # base 24-31
gdt64_end:

gdt64_ptr:
    .word gdt64_end - gdt64_start - 1   # limit
    .long gdt64_start                   # base (32-bit pointer for 32-bit mode)

# Saved multiboot registers
.align 8
mboot_saved:
    .skip 8                       # [0..3] = magic (EAX), [4..7] = mbi_addr (EBX)

# =============================================================================
# Boot BSS — page tables and early stack
# =============================================================================
.section .boot.bss, "aw"
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

# Higher-half page tables
.align 4096
pdpt_high:
    .skip 4096
pd_high:
    .skip 4096

.align 16
stack_bottom:
    .skip 32768                   # 32 KB stack
stack_top: