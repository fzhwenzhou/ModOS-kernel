# isr.S - CPU exception stubs (Interrupt Service Routines) for x86_64
# Assembles with: x86_64-elf-as (GNU assembler, Intel syntax)
#
# Each stub saves all general-purpose registers, calls the Modula-2
# exception handler (Exceptions_ExceptionHandler), restores registers,
# and returns via iretq.  Stubs for exceptions that don't push an error
# code push a fake 0 so the stack layout is uniform.
#
# Stack layout after PUSHAQ (for both stub variants):
#
#   higher addresses
#     SS                          <- CPU-pushed
#     RSP                         <- CPU-pushed
#     RFLAGS                      <- CPU-pushed
#     CS                          <- CPU-pushed
#     RIP                         <- CPU-pushed
#     error code (real or fake)   <- stub / CPU
#     RAX                         <- PUSHAQ (1st)
#     RBX
#     RCX
#     RDX
#     RSI
#     RDI
#     RBP
#     R8
#     R9
#     R10
#     R11
#     R12
#     R13
#     R14
#     R15                         <- PUSHAQ (last)  == RSP
#   lower addresses
#
# The handler receives:
#   rdi = vector number
#   rsi = error code
#   rdx = pointer to the saved-register frame (RSP)

.intel_syntax noprefix

.text

# ------------------------------------------------------------------
# PUSHAQ / POPAQ: save/restore all 16 general-purpose registers.
# x86_64 has no pusha/popa equivalent.
# ------------------------------------------------------------------

.macro PUSHAQ
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
.endm

.macro POPAQ
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
.endm

# ------------------------------------------------------------------
# Exception stub macros
# ------------------------------------------------------------------

# STUB_NO_ERR: for exceptions that don't push an error code.
# Pushes a fake 0 so the stack layout matches STUB_ERR.
.macro STUB_NO_ERR name, num
.global __exc_\name
.align 16
__exc_\name:
    cli
    push 0                     # fake error code
    PUSHAQ
    mov rdi, \num              # vector number
    xor rsi, rsi               # error code = 0
    mov rdx, rsp               # frame pointer
    cld
    call Exceptions_ExceptionHandler
    POPAQ
    add rsp, 8                 # pop fake error code
    iretq
.endm

# STUB_ERR: for exceptions where the CPU pushes an error code.
.macro STUB_ERR name, num
.global __exc_\name
.align 16
__exc_\name:
    cli
    PUSHAQ
    mov rdi, \num              # vector number
    mov rsi, [rsp+120]         # error code (above 15 saved regs)
    mov rdx, rsp               # frame pointer
    cld
    call Exceptions_ExceptionHandler
    POPAQ
    add rsp, 8                 # pop CPU-pushed error code
    iretq
.endm

# ------------------------------------------------------------------
# 20 CPU exception stubs (vectors 0-21, excluding reserved 9 and 15)
# ------------------------------------------------------------------

STUB_NO_ERR divide_error,     0
STUB_NO_ERR debug,            1
STUB_NO_ERR nmi,              2
STUB_NO_ERR breakpoint,       3
STUB_NO_ERR overflow,         4
STUB_NO_ERR bound_range,      5
STUB_NO_ERR invalid_opcode,   6
STUB_NO_ERR device_na,        7
STUB_ERR     double_fault,    8
STUB_ERR     invalid_tss,     10
STUB_ERR     segment_np,      11
STUB_ERR     stack_fault,     12
STUB_ERR     gpf,             13
STUB_ERR     page_fault,      14
STUB_NO_ERR x87_fpu,          16
STUB_ERR     alignment,       17
STUB_NO_ERR machine_check,    18
STUB_NO_ERR simd,             19
STUB_NO_ERR virtualization,   20
STUB_ERR     security,        21

# ------------------------------------------------------------------
# Stub table: 32 entries indexed by vector number.
# 0 = unused (reserved vectors 9, 15, and 22-31).
# Read by Exceptions.mod via leaq ExceptionStubs(%rip).
# ------------------------------------------------------------------

.section .rodata
.global ExceptionStubs
.align 8
ExceptionStubs:
    .quad __exc_divide_error       # 0
    .quad __exc_debug              # 1
    .quad __exc_nmi                # 2
    .quad __exc_breakpoint         # 3
    .quad __exc_overflow           # 4
    .quad __exc_bound_range        # 5
    .quad __exc_invalid_opcode     # 6
    .quad __exc_device_na          # 7
    .quad __exc_double_fault       # 8
    .quad 0                        # 9  (reserved)
    .quad __exc_invalid_tss        # 10
    .quad __exc_segment_np         # 11
    .quad __exc_stack_fault        # 12
    .quad __exc_gpf                # 13
    .quad __exc_page_fault         # 14
    .quad 0                        # 15 (reserved)
    .quad __exc_x87_fpu            # 16
    .quad __exc_alignment          # 17
    .quad __exc_machine_check      # 18
    .quad __exc_simd               # 19
    .quad __exc_virtualization     # 20
    .quad __exc_security           # 21
    .quad 0, 0, 0, 0, 0, 0, 0, 0, 0, 0  # 22-31 (reserved)

.section .note.GNU-stack, "", @progbits
