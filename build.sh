#!/usr/bin/env bash
# build.sh — Build the kernel ELF and package it into a bootable ISO.
#
# Usage:
#   ./build.sh                    # build kernel.elf + limine.iso
#   ./build.sh clean              # clean
#   ARCH=x86_64 ./build.sh        # override architecture
#   TOOLS=/path ./build.sh        # override toolchain prefix

set -euo pipefail

# ------------------------------------------------------------------
# Configuration — override via environment variables
# ------------------------------------------------------------------
ARCH="${ARCH:-x86_64}"
LIMINE="${LIMINE:-../limine-binary}"

KERNEL="kernel.elf"
ISO="limine.iso"
ISO_DIR="iso_root"

# ------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------
if [ "${1:-}" = "clean" ]; then
    echo "=== Clean ==="
    make clean
    rm -rf "${ISO_DIR}" "${ISO}"
    exit 0
fi

# ------------------------------------------------------------------
# Step 1: Build the kernel ELF
# ------------------------------------------------------------------
echo "=== Building kernel (${ARCH}) ==="
make ARCH="${ARCH}"

# ------------------------------------------------------------------
# Step 2: Package into bootable ISO
# ------------------------------------------------------------------
echo "=== Creating ISO ==="
rm -rf "${ISO_DIR}"
mkdir -p "${ISO_DIR}"

cp "${KERNEL}" "${ISO_DIR}/"
cp limine.conf "${ISO_DIR}/"
cp "${LIMINE}/limine-bios-cd.bin" "${ISO_DIR}/"
cp "${LIMINE}/limine-uefi-cd.bin" "${ISO_DIR}/"

xorriso -as mkisofs \
    -b limine-bios-cd.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --efi-boot limine-uefi-cd.bin \
    -efi-boot-part \
    --efi-boot-image \
    --protective-msdos-label \
    "${ISO_DIR}" -o "${ISO}"

echo ""
echo "=== ISO created: ${ISO} ==="