#!/usr/bin/env bash
# =============================================================================
# 45-trim-bundle.sh — slim the assembled bundle to what Aurora actually loads.
#
# Removes ~40% (1077 → ~660 MB uncompressed) by dropping pieces no Aurora flow
# touches. Every block here was validated empirically: after each removal the
# 4-flow smoke (50-smoke.sh) must still pass. If you change a block, re-run the
# smoke and confirm 4/4.
#
#   bash build/45-trim-bundle.sh <bundle-root>     # e.g. dist/msys
#
# UNTOUCHABLE (the floor): g++/cc1plus (runs at RUNTIME to compile the Verilator
# model), python stdlib core + cocotb, verilator/yosys/iverilog, the iverilog
# backends (lib/ivl), share/verilator + share/yosys, bash+coreutils for
# verilated.mk, and the DLLs those exes load.
# =============================================================================
set -euo pipefail
ROOT="${1:?usage: 45-trim-bundle.sh <bundle-root>}"
M="$ROOT/mingw64"
say() { printf '\n==> %s\n' "$*"; }
[ -d "$M/bin" ] || { echo "ERROR: $M/bin not found — is <bundle-root> the msys dir?" >&2; exit 1; }

# --- Block 1: Python test suite (132 MB) + GUI data + python extras ---
say "Block 1: python/test + share GUI data + python extras"
rm -rf "$M"/lib/python3.12/{test,idlelib,tkinter,lib2to3,turtledemo,ensurepip}
rm -rf "$M"/share/{gir-1.0,cmake,terminfo,mime,gtk-3.0,gtk-4.0,icons,glib-2.0}

# --- Block 2: 3rd-party static libs (Aurora never static-links these) ---
# KEEP: libstdc++.a, libgcc*, libucrt.a, libmsvcrt.a/-os.a, libmingw*, libkernel32,
# libntdll, libuuid, libpython3.12.dll.a, libpthread*, libwinpthread*, libatomic*,
# and the hundreds of <1MB Windows system import libs.
say "Block 2: 3rd-party static .a libraries"
cd "$M/lib"
for n in gnutls epoxy unistring cppdap glib-2.0 gio-2.0 gobject-2.0 gmodule-2.0 \
         archive turbojpeg zstd textstyle gettextlib gettextsrc gettextpo iconv \
         isl gmp gmpxx mpfr mpc bfd opcodes ctf sframe \
         netui1 netui2 ntoskrnl fastprox; do
  rm -f "lib${n}.a" "lib${n}.dll.a"
done
rm -f libmsvcr*d.a libmsvcp*d.a libmsvcr*_app.a libmsvcp*_app.a libucrtapp.a libucrtbased.a
cd - >/dev/null

# --- Block 3: library headers (g++ on Verilator output only needs c++ + C runtime) ---
say "Block 3: library include/ headers"
cd "$M/include"
for d in isl gtk-2.0 gtk-3.0 gtk-4.0 glib-2.0 gio-unix-2.0 gobject-introspection-1.0 \
         epoxy cairo pango-1.0 pixman-1 freetype2 harfbuzz gdk-pixbuf-2.0 atk-1.0 \
         atk-bridge-2.0 librsvg-2.0 webp thai tre textstyle unistring uv \
         tcl8.6 tk8.6 readline graphene-1.0 gsk fribidi cloudproviders libxml2 ncursesw; do
  rm -rf "$d"
done
cd - >/dev/null

# --- Block 4: GTK/GUI/font DLL stack (no headless EDA tool loads these) ---
say "Block 4: GTK/GUI DLLs"
cd "$M/bin"
for p in libgtk libgdk libcairo libpango libatk libepoxy librsvg libharfbuzz \
         libfribidi libthai libdatrie libpixman libgraphene libgdk_pixbuf \
         libglib-2.0 libgio-2.0 libgobject-2.0 libgmodule-2.0 libgirepository \
         libgthread libfontconfig libfreetype libgailutil libwebp libcairo-gobject \
         libpangocairo libpangoft2 libpangowin32 librsvg-2 libcroco; do
  rm -f ${p}*.dll
done
cd - >/dev/null

# --- Block 5: duplicate MSYS perl (verilator uses the mingw64 perl) ---
say "Block 5: duplicate usr/ perl"
rm -rf "$ROOT"/usr/lib/perl5 "$ROOT"/usr/share/perl5 "$ROOT"/usr/bin/perl.exe \
       "$ROOT"/usr/bin/perl5* "$ROOT"/usr/bin/core_perl 2>/dev/null || true

# --- leftover docs/man/locale ---
find "$ROOT" -maxdepth 4 -type d \( -name doc -o -name man -o -name locale -o -name gtk-doc \) \
  -exec rm -rf {} + 2>/dev/null || true

say "Trim done. Size:"
du -sm "$ROOT" | cut -f1 | xargs echo "  bundle MB:"
echo "  -> now run 50-smoke.sh and confirm 4/4 PASS before publishing."
