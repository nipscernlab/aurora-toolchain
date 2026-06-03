#!/usr/bin/env bash
# =============================================================================
# 10-install-packages.sh — install the pinned MSYS2 toolchain (run in MINGW64).
#
# The pinned packages (gcc/gcc-libs 15.1.0-5, python 3.12.11-1) are NO LONGER in
# the live MSYS2 repo (it serves gcc16/py3.14 now, which break our cocotb flow).
# So we install those EXACT versions from the `pins-v1` Release via `pacman -U`,
# pin them in IgnorePkg, then pull the floating tools from the live repo.
#
# Env overrides: PINS_TAG (default pins-v1), PINS_REPO (default this repo).
# Idempotent. Next: 20-build-cocotb-vpi.sh.
# =============================================================================
set -euo pipefail
say() { printf '\n==> %s\n' "$*"; }

PINS_REPO="${PINS_REPO:-nipscernlab/aurora-toolchain}"
PINS_TAG="${PINS_TAG:-pins-v1}"
PINS_BASE="https://github.com/${PINS_REPO}/releases/download/${PINS_TAG}"
PINNED=(
  "mingw-w64-x86_64-gcc-15.1.0-5-any.pkg.tar.zst"
  "mingw-w64-x86_64-gcc-libs-15.1.0-5-any.pkg.tar.zst"
  "mingw-w64-x86_64-python-3.12.11-1-any.pkg.tar.zst"
)

# --- 1. fetch + install the EXACT pinned packages (gcc15 / python3.12) -------
say "Fetching pinned packages from ${PINS_TAG}"
TMP="$(mktemp -d)"
for f in "${PINNED[@]}"; do
  curl -fL --retry 3 -o "$TMP/$f"     "$PINS_BASE/$f"
  curl -fL --retry 3 -o "$TMP/$f.sig" "$PINS_BASE/$f.sig" 2>/dev/null || true
done
say "Installing pinned packages with pacman -U"
pacman -U --noconfirm "${PINNED[@]/#/$TMP/}"

# --- 2. pin them so a later -S/-Syu can't float them off 15/3.12 ------------
PINS="mingw-w64-x86_64-gcc mingw-w64-x86_64-gcc-libs mingw-w64-x86_64-python"
if ! grep -qE '^IgnorePkg.*mingw-w64-x86_64-gcc-libs' /etc/pacman.conf; then
  say "Pinning gcc/gcc-libs/python in /etc/pacman.conf IgnorePkg"
  if grep -qE '^IgnorePkg' /etc/pacman.conf; then
    sed -i "s|^IgnorePkg.*|& $PINS|" /etc/pacman.conf
  else
    sed -i "/^\[options\]/a IgnorePkg   = $PINS" /etc/pacman.conf
  fi
fi
grep -E '^IgnorePkg' /etc/pacman.conf || true

# --- 3. floating tools from the live repo (need only gcc-libs, which is pinned) -
say "Installing floating tools (verilator/iverilog/ccache/perl/make)"
pacman -S --needed --noconfirm \
  mingw-w64-x86_64-verilator \
  mingw-w64-x86_64-iverilog \
  mingw-w64-x86_64-ccache \
  mingw-w64-x86_64-perl \
  mingw-w64-x86_64-make

# yosys WITHOUT ghdl (VHDL frontend → gcc-ada → gcc16). yosys.exe runs fine
# against gcc-libs 15 even though built with g++16 (backward-compatible libstdc++).
say "Installing yosys WITHOUT ghdl"
pacman -S --noconfirm --assume-installed mingw-w64-x86_64-ghdl mingw-w64-x86_64-yosys

rm -rf "$TMP"
say "Installed versions (compare against manifest.txt):"
for p in gcc gcc-libs python verilator iverilog yosys ccache perl make; do
  pacman -Q "mingw-w64-x86_64-$p" 2>/dev/null || echo "  (missing: $p)"
done
