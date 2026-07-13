# ModOS-kernel — A Microkernel Written in Modula-2

**ModOS-kernel** is a bare-metal x86_64 kernel written in GNU Modula-2 (gm2), demonstrating that Modula-2 can be used effectively in kernel-space, with full access to inline assembly, hardware I/O, and raw memory.

## Features

- **Multiboot2-compliant** — boots via the [Limine](https://github.com/limine-bootloader/limine) bootloader
- **x86_64 long mode** — 64-bit with 4-level paging (identity-mapped first 4 GB)
- **Serial I/O** — COM1 UART at 38400 baud for debug output
- **Framebuffer** — reads the Multiboot2 framebuffer tag and fills the display
- **100% Modula-2** — no C code anywhere in the kernel; all runtime functions (`memcpy`, `memset`, `memmove`, `memcmp`) are implemented in pure Modula-2
- **Modula-2 kernel modules** — clean separation of concerns via `DEFINITION` / `IMPLEMENTATION` modules

## Project Structure

```
├── Makefile                 # Top-level build: ISO, QEMU run, clean
├── limine.conf              # Limine bootloader config
├── src/
│   ├── Makefile             # Modula-2 compilation rules
│   ├── boot.S               # 32-bit → 64-bit assembly entry (GAS, Intel syntax)
│   ├── stub.S               # Assembly stubs for gm2 runtime
│   ├── linker.ld            # Linker script (load address 0x100000)
│   ├── Kernel.def           # Kernel definition module
│   ├── Kernel.mod           # Kernel implementation (serial I/O, framebuffer)
│   ├── Multiboot2.def       # Multiboot2 constants and types (definition-only)
│   └── libs/
│       ├── Makefile
│       ├── BitByteOps.def   # Bit manipulation library
│       ├── BitByteOps.mod   # Bit manipulation implementation
│       ├── libc.def         # Minimal C library interface (pure Modula-2)
│       └── libc.mod         # memcpy, memset, memmove, memcmp + stubs
├── agent-reference/
│   └── multiboot2.h         # Reference C header (multiboot2 spec)
├── .gitignore
└── README.md
```

## Prerequisites

| Tool | Path |
|------|------|
| x86_64-elf binutils | `/home/naonao/x86_64-elf-tools` |
| GNU Modula-2 (gm2) | part of GCC 16.1.0 |
| Limine binaries | `/home/naonao/limine-binary` |
| OVMF (UEFI) | `/home/naonao/edk2-ovmf` |
| xorriso | system package |
| QEMU | system package |

## Building

```bash
make          # Build kernel.elf and limine.iso
make clean    # Remove all build artifacts
```

## Running

```bash
make run       # Launch in QEMU with OVMF (UEFI), serial on stdio, debug interrupts
make run-quiet # Same but without the -d int,cpu_reset noise
```

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
3. `Kernel.mod` parses the tag list, extracts the framebuffer address/pitch/width/height/bpp
4. Each pixel is written as a 4-byte BGRA record (blue byte first in little-endian)

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
2. The [Limine](https://github.com/limine-bootloader/limine) binary distribution
3. OVMF (UEFI firmware) from edk2
4. QEMU and xorriso

## Acknowledgements

- [GNU Modula-2](https://www.nongnu.org/gm2/) — compiler and runtime libraries
- [Limine](https://github.com/limine-bootloader/limine) — bootloader
- [Multiboot2 Specification](https://www.gnu.org/software/grub/manual/multiboot2/multiboot.html) — boot protocol
- **Claude Code (Anthropic)** — AI-assisted development of the Multiboot2 module, serial I/O procedures, framebuffer initialization, and the pure-Modula-2 libc replacement