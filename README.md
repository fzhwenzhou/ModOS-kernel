# ModOS-kernel — A Microkernel Written in Modula-2

> **WARNING: In Refactorization**: This project is under refactorization. It might not be able to compile or run sometimes. Make sure to understand the directory structure before performing any operations.

**ModOS-kernel** is a bare-metal x86_64 kernel written in GNU Modula-2 (gm2), demonstrating that Modula-2 can be used effectively in kernel-space, with full access to inline assembly, hardware I/O, and raw memory.

## Features

- **Limine boot protocol** — native [Limine](https://github.com/limine-bootloader/limine) protocol support (no Multiboot2 compatibility shim needed; portable beyond x86)
- **x86_64 long mode** — entered directly by Limine in 64-bit mode with paging enabled (higher-half kernel at 0xFFFFFFFF80000000)
- **Serial I/O** — COM1 UART at 38400 baud for debug output
- **Framebuffer** — reads the Limine framebuffer response and fills the display with RGB stripes
- **100% Modula-2** — no C code anywhere in the kernel; all runtime functions (`memcpy`, `memset`, `memmove`, `memcmp`) are implemented in pure Modula-2
- **Modula-2 kernel modules** — clean separation of concerns via `DEFINITION` / `IMPLEMENTATION` modules
- **Hierarchical build system** — architecture-aware Makefile hierarchy with `ARCH` and `TOOLS` inheritance

## Project Structure

```
├── Makefile                 # Top-level build: kernel.elf only
├── build.sh                 # ISO packaging with xorriso
├── run.sh                   # QEMU launcher with UEFI/OVMF
├── limine.conf              # Limine bootloader config (protocol: limine)
├── src/
│   ├── Makefile             # Compiles Main.o, stub.S, delegates to arch/ and libc/
│   ├── Main.def             # Application-level main definition
│   ├── Main.mod             # Application-level main (HLT loop)
│   ├── stub.S               # Assembly stubs for gm2 runtime
│   ├── boot/                # Architecture-independent boot protocol defs
│   │   └── Limine.def       # Limine protocol — types, constants, externed request vars
│   ├── arch/
│   │   └── x86_64/
│   │       ├── Makefile     # Compiles ArchMain.o, boot/boot.S, delegates to libm2/
│   │       ├── ArchMain.def # x86_64 arch entry point definition
│   │       ├── ArchMain.mod # x86_64 arch entry point (serial, framebuffer)
│   │       ├── linker.ld    # Linker script (higher-half at 0xFFFFFFFF80000000)
│   │       ├── boot/
│   │       │   ├── boot.S   # Limine request structures + 64-bit entry (GAS, Intel syntax)
│   │       └── libm2/
│   │           ├── Makefile
│   │           ├── BitByteOps.def  # Bit manipulation library
│   │           └── BitByteOps.mod  # Bit manipulation via inline assembly
│   └── libc/
│       ├── Makefile
│       ├── string.def       # string module — memcpy, memset, memmove, memcmp
│       └── string.mod       # Pure Modula-2 implementation (FOR "C" linkage)
├── .gitignore
└── README.md
```

## Boot Flow

```
Limine (UEFI / BIOS)
  │  - Boots the ELF directly in 64-bit long mode
  │  - Sets up paging, maps kernel in higher-half (0xFFFFFFFF80000000+)
  │  - Sets up a ≥64 KiB stack, fills in Limine response structures
  │  - CS=0x28, DS/ES/SS/FS/GS=0x30, interrupts disabled, RAX–R15 = 0
  │
  └── Call ArchMain_KernelMain()
      └── ArchMain.mod
          ├── SerialInit (COM1)
          ├── Verify Limine base revision == 6
          ├── Read framebuffer response from limineFramebufferRequest
          ├── Fill framebuffer with RGB stripes
          └── Call Main.Main(0, emptyArgs)
                └── Main.mod (HLT loop)
```

## Prerequisites

| Tool | Path |
|------|------|
| GNU Modula-2 (gm2) | part of GCC 16.1.0 |
| Limine binaries | `../limine-binary` |
| OVMF (UEFI) | `../edk2-ovmf` |
| xorriso | system package |
| QEMU | system package |

## Building

```bash
make          # Build kernel.elf only
make clean    # Remove all build artifacts

./build.sh            # Build kernel.elf + package limine.iso
./build.sh clean      # Clean + build

# Override architecture or toolchain
ARCH=aarch64 ./build.sh
```

## Running

```bash
./run.sh              # Launch in QEMU with OVMF (UEFI), serial on stdio, debug interrupts
./run.sh --quiet      # Same but without the -d int,cpu_reset noise

# Override architecture or ISO
ARCH=aarch64 ./run.sh
ISO=mykernel.iso ./run.sh
```

## Makefile Hierarchy

The build system is designed for extensibility across architectures:

```
Makefile (top-level)
  ARCH, TOOLS, AS, LD, M2, M2FLAGS — exported to sub-makes
  |
  └── src/Makefile
      ├── stub.o        (from stub.S)
      ├── Main.o        (from Main.mod)
      ├── arch/$(ARCH)/Makefile   ← architecture-specific
      │   ├── boot/boot.o         (from boot.S — Limine requests + entry)
      │   ├── ArchMain.o          (from ArchMain.mod)
      │   └── libm2/Makefile
      │       └── BitByteOps.o
      └── libc/Makefile
          └── string.o            (+ future stdlib.o, stdio.o, ...)
```

To add a new architecture:
1. Create `src/arch/<arch>/` with its own `Makefile`, linker script, and boot code
2. Add any arch-specific Limine request declarations to `boot.S`
3. Add the object files to `ARCH_OBJS` in the top-level `Makefile`
4. Add architecture-specific `M2FLAGS` in the top-level `Makefile`

## Toolchain Notes

The kernel uses **no C code** — every line is either Modula-2 or x86 assembly. The minimal gm2 runtime (`-flibs=min`) provides only `SYSTEM`, `M2RTS`, and a bare-bones interface. Heap, file I/O, exceptions, and the C standard library are all absent — just bare-metal Modula-2.

Key compiler flags:
- `-mcmodel=large` — required for kernel-space code
- `-mno-red-zone` — interrupts would corrupt the red zone
- `-mno-mmx -mno-sse` — no floating-point/vector in kernel
- `-fno-exceptions` — no Modula-2 exception handling

## How the Limine Protocol Works

Unlike Multiboot2 (which requires a 32-bit entry stub, manual page-table construction, and a long-mode transition trampoline), the Limine protocol hands off directly in 64-bit mode:

1. `boot.S` places a **start marker**, a **base-revision tag**, a set of **request structures**, and an **end marker** into the `.limine_requests*` sections
2. Each request is a 64-byte (or larger) struct identified by a 4×`uint64` ID; the entry-point request points to `_start`
3. Limine scans the loaded ELF between the markers, collects the requests, fills in `response` pointers, and jumps to the entry point
4. The kernel reads `limineFramebufferRequest.response->framebuffers[0]` directly — no tag-walking required

Request/response variables are declared in `boot.S` and externed in `src/boot/Limine.def` so that Modula-2 code can read them without needing C `__attribute__((section(...)))`.

## Module Naming Convention

The `libc/` directory follows a modular naming scheme — each sub-module is a separate Modula-2 definition/implementation pair:

| File | Module Name | Provides |
|------|-------------|----------|
| `string.def` / `string.mod` | `string` | `memcpy`, `memset`, `memmove`, `memcmp` |
| `stdlib.def` / `stdlib.mod` | (future) | Standard library functions |
| `stdio.def` / `stdio.mod` | (future) | I/O functions |

All modules use `FOR "C"` linkage and `EXPORT UNQUALIFIED` so their symbols are callable with C calling convention — satisfying compiler-generated references to `memcpy`, `memset`, etc.

## Memory Layout

| Region | Virtual Address | Notes |
|--------|-----------------|-------|
| Kernel load | `0xFFFFFFFF80100000` | Loaded and mapped by Limine |
| Framebuffer | HHDM address (e.g. `0xFFFF800080000000`) | Mapped in the Higher Half Direct Map |
| Boot stack | bootloader-reclaimable | ≥64 KiB, provided by Limine |

The kernel is a **higher-half kernel**. Limine maps all usable/bootloader/framebuffer memory through the Higher Half Direct Map (HHDM); the offset is available via `limineHhdmRequest.response->offset` if needed.

## Building from Scratch

If you're setting up a fresh environment, you'll need:
1. [GNU Modula-2 (gm2)](https://www.nongnu.org/gm2/) — part of GCC 16.1.0
2. The [Limine](https://github.com/limine-bootloader/limine) binary distribution
3. OVMF (UEFI firmware) from edk2
4. QEMU and xorriso

## Acknowledgements

- [GNU Modula-2](https://www.nongnu.org/gm2/) — compiler and runtime libraries
- [Limine](https://github.com/limine-bootloader/limine) — bootloader and boot protocol
- **Claude Code (Anthropic)** — AI-assisted development for boilerplate codes, directory reorganization, testing, and debugging.
