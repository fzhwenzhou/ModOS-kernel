# ModOS-kernel — A Microkernel Written in Modula-2

> **WARNING: In Refactorization**: This project is under refactorization. It might not be able to compile or run sometimes. Make sure to understand the directory structure before performing any operations.

**ModOS-kernel** is a bare-metal x86_64 kernel written in GNU Modula-2 (gm2), demonstrating that Modula-2 can be used effectively in kernel-space, with full access to inline assembly, hardware I/O, and raw memory.

## Features

- **Multiboot2-compliant** — boots via the [Limine](https://github.com/limine-bootloader/limine) bootloader
- **x86_64 long mode** — 64-bit with 4-level paging (identity-mapped first 4 GB)
- **Serial I/O** — COM1 UART at 38400 baud for debug output
- **Framebuffer** — reads the Multiboot2 framebuffer tag and fills the display with an RGB gradient
- **100% Modula-2** — no C code anywhere in the kernel; all runtime functions (`memcpy`, `memset`, `memmove`, `memcmp`) are implemented in pure Modula-2
- **Modula-2 kernel modules** — clean separation of concerns via `DEFINITION` / `IMPLEMENTATION` modules
- **Hierarchical build system** — architecture-aware Makefile hierarchy with `ARCH` and `TOOLS` inheritance

## Project Structure

```
├── Makefile                 # Top-level build: kernel.elf only
├── build.sh                 # ISO packaging with xorriso
├── run.sh                   # QEMU launcher with UEFI/OVMF
├── limine.conf              # Limine bootloader config
├── src/
│   ├── Makefile             # Compiles Main.o, stub.S, delegates to arch/ and libc/
│   ├── Main.def             # Application-level main definition
│   ├── Main.mod             # Application-level main (HLT loop)
│   ├── stub.S               # Assembly stubs for gm2 runtime
│   ├── arch/
│   │   ├── aarch64/
│   │   │   └── Makefile     # Stub — ready for ARM64 port
│   │   └── x86_64/
│   │       ├── Makefile     # Compiles ArchMain.o, boot/boot.S, delegates to libm2/
│   │       ├── ArchMain.def # x86_64 arch entry point definition
│   │       ├── ArchMain.mod # x86_64 arch entry point (serial, framebuffer)
│   │       ├── linker.ld    # Linker script (load address 0x100000)
│   │       ├── boot/
│   │       │   ├── boot.S   # 32-bit → 64-bit assembly entry (GAS, Intel syntax)
│   │       │   └── Multiboot2.def  # Multiboot2 constants and types (definition-only)
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
Limine (firmware)
  └── boot.S (32-bit entry)
      ├── Set up page tables (PML4, PDPT, PD0-3)
      ├── Enable PAE + long mode + paging
      ├── Load GDT, transition to 64-bit
      └── Call ArchMain_KernelMain(magic, mbi_addr)
            └── ArchMain.mod
                ├── SerialInit (COM1)
                ├── Parse Multiboot2 info → find framebuffer tag
                ├── Fill framebuffer with RGB gradient
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
      │   ├── boot/boot.o         (from boot.S)
      │   ├── ArchMain.o          (from ArchMain.mod)
      │   └── libm2/Makefile
      │       └── BitByteOps.o
      └── libc/Makefile
          └── string.o            (+ future stdlib.o, stdio.o, ...)
```

To add a new architecture:
1. Create `src/arch/<arch>/` with its own `Makefile`, linker script, and boot code
2. Add the object files to `ARCH_OBJS` in the top-level `Makefile`
3. Add architecture-specific `M2FLAGS` in the top-level `Makefile`

## Toolchain Notes

The kernel uses **no C code** — every line is either Modula-2 or x86 assembly. The minimal gm2 runtime (`-flibs=min`) provides only `SYSTEM`, `M2RTS`, and a bare-bones interface. Heap, file I/O, exceptions, and the C standard library are all absent — just bare-metal Modula-2.

Key compiler flags:
- `-mcmodel=large` — required for kernel-space code
- `-mno-red-zone` — interrupts would corrupt the red zone
- `-mno-mmx -mno-sse` — no floating-point/vector in kernel
- `-fno-exceptions` — no Modula-2 exception handling

## How the Framebuffer Works

1. `boot.S` requests a 1024×768×32 framebuffer in the Multiboot2 header
2. The bootloader populates the Multiboot2 info structure with a framebuffer tag (type 8)
3. `ArchMain.mod` parses the tag list, extracts the framebuffer address/pitch/width/height/bpp
4. Each pixel is written as a 4-byte BGRA record (blue byte first in little-endian)
5. The screen is divided into three vertical stripes: red, green, and blue

## Module Naming Convention

The `libc/` directory follows a modular naming scheme — each sub-module is a separate Modula-2 definition/implementation pair:

| File | Module Name | Provides |
|------|-------------|----------|
| `string.def` / `string.mod` | `string` | `memcpy`, `memset`, `memmove`, `memcmp` |
| `stdlib.def` / `stdlib.mod` | (future) | Standard library functions |
| `stdio.def` / `stdio.mod` | (future) | I/O functions |

All modules use `FOR "C"` linkage and `EXPORT UNQUALIFIED` so their symbols are callable with C calling convention — satisfying compiler-generated references to `memcpy`, `memset`, etc.

## Memory Layout

| Region | Address |
|--------|---------|
| Kernel load | `0x100000` |
| Framebuffer | `0x80000000` (set by firmware) |
| Stack | ~`0x8000` (in BSS) |
| Page tables | BSS (6 × 4 KB pages) |

## Building from Scratch

If you're setting up a fresh environment, you'll need:
1. [GNU Modula-2 (gm2)](https://www.nongnu.org/gm2/) — part of GCC 16.1.0
2. The [Limine](https://github.com/limine-bootloader/limine) binary distribution, or other Multiboot2-compatible bootloaders
3. OVMF (UEFI firmware) from edk2
4. QEMU and xorriso

## Acknowledgements

- [GNU Modula-2](https://www.nongnu.org/gm2/) — compiler and runtime libraries
- [Limine](https://github.com/limine-bootloader/limine) — bootloader
- [Multiboot2 Specification](https://www.gnu.org/software/grub/manual/multiboot2/multiboot.html) — boot protocol
- **Claude Code (Anthropic)** — AI-assisted development for boilerplate codes, directory reorganization, testing, and debugging.