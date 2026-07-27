# boot.S — Limine x86_64 entry point
# Assembles with: x86_64-elf-as (GNU assembler)
#
# Limine boots us directly in 64-bit long mode with paging enabled,
# a valid GDT, and a 64 KiB+ stack already set up.  We do not need
# to set up paging or transition from 32-bit mode.

.intel_syntax noprefix

# gm2 emits "ModuleName_VarName" for imported Modula-2 global variables.
# Since our Limine.def module is not "FOR C" linkage, it expects these
# mangled names.  We provide them as aliases for the actual labels.
.global Limine_limineBaseRevision
.set    Limine_limineBaseRevision, limineBaseRevision
.global Limine_limineEntryPointRequest
.set    Limine_limineEntryPointRequest, limineEntryPointRequest
.global Limine_limineFramebufferRequest
.set    Limine_limineFramebufferRequest, limineFramebufferRequest
.global Limine_limineMemmapRequest
.set    Limine_limineMemmapRequest, limineMemmapRequest
.global Limine_limineHhdmRequest
.set    Limine_limineHhdmRequest, limineHhdmRequest
.global Limine_limineExecutableAddressRequest
.set    Limine_limineExecutableAddressRequest, limineExecutableAddressRequest
.global Limine_limineBootloaderInfoRequest
.set    Limine_limineBootloaderInfoRequest, limineBootloaderInfoRequest

# =============================================================================
# Limine requests start marker — must be 8-byte aligned
# =============================================================================
.section .limine_requests_start_marker, "a"
.align 8
.global limine_requests_start_marker
limine_requests_start_marker:
    .quad 0xf6b8f4b39de7d1ae
    .quad 0xfab91a6940fcb9cf
    .quad 0x785c6ed015d3e316
    .quad 0x181e920a7852b9d9

# =============================================================================
# Limine base revision tag — request base revision 6
# The bootloader sets element [2] to 0 if it supports the requested revision.
# =============================================================================
.section .limine_requests, "a"
.align 8
.global limineBaseRevision
limineBaseRevision:
    .quad 0xf9562b2d5c95a6c8
    .quad 0x6a7b384944536bdc
    .quad 6

# =============================================================================
# Entry point request — tells Limine where to jump to start the kernel
# =============================================================================
.section .limine_requests, "a"
.align 8
.global limineEntryPointRequest
limineEntryPointRequest:
    .quad 0xc7b1dd30df4c8b88      # LIMINE_COMMON_MAGIC
    .quad 0x0a82e883a194f07b
    .quad 0x13d86c035a1cd3e1      # LIMINE_ENTRY_POINT_REQUEST_ID
    .quad 0x2b0caa89d8f3026a
    .quad 0                        # revision
    .quad 0                        # response (filled by bootloader)
    .quad ArchMain_KernelMain                   # entry point function pointer

# =============================================================================
# Framebuffer request — ask the bootloader to set up a framebuffer
# =============================================================================
.section .limine_requests, "a"
.align 8
.global limineFramebufferRequest
limineFramebufferRequest:
    .quad 0xc7b1dd30df4c8b88      # LIMINE_COMMON_MAGIC
    .quad 0x0a82e883a194f07b
    .quad 0x9d5827dcd881dd75      # LIMINE_FRAMEBUFFER_REQUEST_ID
    .quad 0xa3148604f6fab11b
    .quad 0                        # revision
    .quad 0                        # response (filled by bootloader)

# =============================================================================
# Memory map request
# =============================================================================
.section .limine_requests, "a"
.align 8
.global limineMemmapRequest
limineMemmapRequest:
    .quad 0xc7b1dd30df4c8b88
    .quad 0x0a82e883a194f07b
    .quad 0x67cf3d9d378a806f      # LIMINE_MEMMAP_REQUEST_ID
    .quad 0xe304acdfc50c3c62
    .quad 0                        # revision
    .quad 0                        # response

# =============================================================================
# HHDM (Higher Half Direct Map) request
# =============================================================================
.section .limine_requests, "a"
.align 8
.global limineHhdmRequest
limineHhdmRequest:
    .quad 0xc7b1dd30df4c8b88
    .quad 0x0a82e883a194f07b
    .quad 0x48dcf1cb8ad2b852      # LIMINE_HHDM_REQUEST_ID
    .quad 0x63984e959a98244b
    .quad 0                        # revision
    .quad 0                        # response

# =============================================================================
# Executable address request — tells us physical/virtual base of kernel
# =============================================================================
.section .limine_requests, "a"
.align 8
.global limineExecutableAddressRequest
limineExecutableAddressRequest:
    .quad 0xc7b1dd30df4c8b88
    .quad 0x0a82e883a194f07b
    .quad 0x71ba76863cc55f63      # LIMINE_EXECUTABLE_ADDRESS_REQUEST_ID
    .quad 0xb2644a48c516a487
    .quad 0                        # revision
    .quad 0                        # response

# =============================================================================
# Bootloader info request
# =============================================================================
.section .limine_requests, "a"
.align 8
.global limineBootloaderInfoRequest
limineBootloaderInfoRequest:
    .quad 0xc7b1dd30df4c8b88
    .quad 0x0a82e883a194f07b
    .quad 0xf55038d8e2a1202f      # LIMINE_BOOTLOADER_INFO_REQUEST_ID
    .quad 0x279426fcf5f59740
    .quad 0                        # revision
    .quad 0                        # response

# =============================================================================
# Limine requests end marker
# =============================================================================
.section .limine_requests_end_marker, "a"
.align 8
.global limine_requests_end_marker
limine_requests_end_marker:
    .quad 0xadc0e0531bb10d03
    .quad 0x9572709f31764c62

/* Mark stack as non-executable to silence linker warning */
.section .note.GNU-stack, "", @progbits
