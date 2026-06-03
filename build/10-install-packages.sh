#!/usr/bin/env bash
# =============================================================================
# 10-install-packages.sh — install the pinned MSYS2 toolchain into the build
# environment (run in an MSYS2 MINGW64 shell, as the FIRST build step).
#
# Reads the versions from ../manifest.txt. Pins gcc/gcc-libs/python in
# /etc/pacman.conf IgnorePkg so a later -Syu can't float them off the
# known-good versions. yosys is installed WITHOUT ghdl (we only do Verilog;
# ghdl would drag gcc-ada → gcc16, which breaks the cocotb VPI link).
#
# Idempotent. After this, run 20-build-cocotb-vpi.sh.
# =============================================================================
set -euo pipefail
say() { printf '\n==> %s\n' "$*"; }

# --- pin gcc/gcc-libs/python so pacman -Syu won't upgrade them ---
PINS="mingw-w64-x86_64-gcc mingw-w64-x86_64-gcc-libs mingw-w64-x86_64-python"
if ! grep -q "mingw-w64-x86_64-gcc-libs" /etc/pacman.conf; then
  say "Pinning gcc/gcc-libs/python in /etc/pacman.conf IgnorePkg"
  # Append to the existing IgnorePkg line, or add one under [options].
  if grep -qE '^IgnorePkg' /etc/pacman.conf; then
    sed -i "s|^IgnorePkg.*|& $PINS|" /etc/pacman.conf
  else
    sed -i "/^\[options\]/a IgnorePkg   = $PINS" /etc/pacman.conf
  fi
fi
grep -E '^IgnorePkg' /etc/pacman.conf || true

# --- install the toolchain (exact pins live in manifest.txt; here we install
#     the package names — CI should assert versions against the manifest) ---
say "Installing pinned toolchain packages"
pacman -S --needed --noconfirm \
  mingw-w64-x86_64-gcc \
  mingw-w64-x86_64-verilator \
  mingw-w64-x86_64-iverilog \
  mingw-w64-x86_64-ccache \
  mingw-w64-x86_64-perl \
  mingw-w64-x86_64-make

# yosys: skip the ghdl dependency (VHDL frontend → gcc-ada → gcc16). Aurora only
# synthesizes Verilog; yosys.exe runs fine against gcc-libs 15 even though it was
# built with g++16 (proven — backward-compatible libstdc++).
say "Installing yosys WITHOUT ghdl"
pacman -S --noconfirm --assume-installed mingw-w64-x86_64-ghdl mingw-w64-x86_64-yosys

say "Installed versions (compare against manifest.txt):"
for p in gcc gcc-libs python verilator iverilog yosys ccache perl make; do
  pacman -Q "mingw-w64-x86_64-$p" 2>/dev/null || echo "  (missing: $p)"
done
