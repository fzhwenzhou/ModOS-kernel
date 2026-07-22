#!/usr/bin/env bash
# run.sh — Launch the kernel ISO in QEMU.
#
# Usage:
#   ./run.sh              # run with serial + debug interrupts
#   ./run.sh --quiet      # run without debug interrupt noise
#   ARCH=x86_64 ./run.sh  # override architecture
#   ISO=path ./run.sh     # override ISO path

set -euo pipefail

# ------------------------------------------------------------------
# Configuration — override via environment variables
# ------------------------------------------------------------------
ARCH="${ARCH:-x86_64}"
ISO="${ISO:-limine.iso}"
OVMF="${OVMF:-../edk2-ovmf}"

# ------------------------------------------------------------------
# QEMU flags common to all architectures
# ------------------------------------------------------------------
QEMU_FLAGS=(
    -M q35
    -m 256M
    -cdrom "${ISO}"
    -vga std
    -no-reboot
    -serial stdio
)

# ------------------------------------------------------------------
# Architecture-specific flags
# ------------------------------------------------------------------
case "${ARCH}" in
    x86_64)
        QEMU_FLAGS+=(-bios "${OVMF}/ovmf-code-x86_64.fd")
        ;;
    *)
        echo "Warning: unknown architecture '${ARCH}', no UEFI firmware set"
        ;;
esac

# ------------------------------------------------------------------
# Optional debug flags
# ------------------------------------------------------------------
if [ "${1:-}" != "--quiet" ]; then
    QEMU_FLAGS+=(-d int,cpu_reset)
fi

# ------------------------------------------------------------------
# Launch QEMU
# ------------------------------------------------------------------
echo "=== Launching QEMU (${ARCH}) ==="
exec qemu-system-${ARCH} "${QEMU_FLAGS[@]}"