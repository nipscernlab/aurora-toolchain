#!/usr/bin/env bash
# =============================================================================
# 40-assemble-bundle.sh — assemble the bundle from the installed MSYS2 prefix.
#
#   bash build/40-assemble-bundle.sh <out-dir> [venv-dir]
#     out-dir   where to build the bundle  (e.g. dist/msys)
#     venv-dir  the cocotb venv from 20-build-cocotb-vpi.sh
#               (default: $HOME/aurora-cocotb-venv)
#
# Produces <out-dir>/{mingw64,usr} and bakes cocotb (+ both VPIs) into the
# bundle Python's site-packages. Then run 45-trim-bundle.sh and 50-smoke.sh.
#
# NOTE: this formalizes the from-scratch path. The shipped msys-v1 was built
# incrementally (verilator bundle + iverilog/yosys added + cocotb packaged);
# always validate a fresh assembly with 50-smoke.sh before publishing.
# =============================================================================
set -euo pipefail
OUT="${1:?usage: 40-assemble-bundle.sh <out-dir> [venv-dir]}"
VENV="${2:-$HOME/aurora-cocotb-venv}"
MROOT="/mingw64"
say() { printf '\n==> %s\n' "$*"; }

say "Copying $MROOT → $OUT/mingw64 (full prefix; 45-trim slims it after)"
mkdir -p "$OUT"
cp -a "$MROOT" "$OUT/mingw64"

say "Copying MSYS shell utils (bash + coreutils for verilated.mk) → $OUT/usr"
# Only usr/bin: the proven lean bundle ships no usr/lib or usr/share and works,
# so copying them just bloats the bundle (~34 MB uncompressed).
mkdir -p "$OUT/usr"
cp -a /usr/bin "$OUT/usr/bin"

# --- bake cocotb (+ VPIs) into the bundle Python ---
PYV="$("$OUT/mingw64/bin/python.exe" -c 'import sys;print("%d.%d"%sys.version_info[:2])')"
SP="$OUT/mingw64/lib/python$PYV/site-packages"
VENV_SP="$("$VENV/bin/python" -c 'import sysconfig;print(sysconfig.get_path("purelib"))' 2>/dev/null \
          || "$VENV/Scripts/python.exe" -c 'import sysconfig;print(sysconfig.get_path("purelib"))')"
say "Copying cocotb from venv site-packages → bundle ($SP)"
mkdir -p "$SP"
for pkg in cocotb cocotb_tools pygpi; do
  rm -rf "$SP/$pkg"; cp -r "$VENV_SP/$pkg" "$SP/"
done
for fl in "$VENV_SP"/find_libpython* "$VENV_SP"/cocotb-*.dist-info; do
  [ -e "$fl" ] && cp -rf "$fl" "$SP/"
done

# the static Verilator VPI lives in cocotb/libs (copied above). Sanity:
VPI="$SP/cocotb/libs/libcocotbvpi_verilator.a"
[ -f "$VPI" ] || { echo "ERROR: $VPI missing — run 20-build-cocotb-vpi.sh first." >&2; exit 1; }
say "cocotb in place. VPIs:"; ls "$SP/cocotb/libs/" | grep -iE 'icarus|verilator'

say "Assembled. Size:"; du -sm "$OUT" | cut -f1 | xargs echo "  MB:"
echo "  -> next: bash build/45-trim-bundle.sh $OUT   then   bash build/50-smoke.sh $OUT"
