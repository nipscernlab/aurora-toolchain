#!/usr/bin/env bash
# =============================================================================
# 60-package.sh — zip the trimmed+smoke-tested bundle for release.
#
#   bash build/60-package.sh <bundle-root> <out-zip>
#     e.g. bash build/60-package.sh dist/msys dist/aurora-msys-v1.zip
#
# The zip must contain `msys/...` at its ROOT so it extracts to
# components/Packages/msys/ on the Aurora side. Run AFTER 45-trim + 50-smoke.
# =============================================================================
set -euo pipefail
ROOT="${1:?usage: 60-package.sh <bundle-root> <out-zip>}"
OUT="${2:?usage: 60-package.sh <bundle-root> <out-zip>}"
say() { printf '\n==> %s\n' "$*"; }

# the bundle dir must be named `msys` so the zip root is msys/...
parent="$(dirname "$ROOT")"; name="$(basename "$ROOT")"
[ "$name" = "msys" ] || { echo "ERROR: bundle dir must be named 'msys' (got '$name')" >&2; exit 1; }

# absolute OUT — we cd into $parent below, so a relative OUT would resolve wrong.
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

rm -f "$OUT"
OUTW="$(cygpath -w "$OUT" 2>/dev/null || echo "$OUT")"
say "Zipping $ROOT → $OUT"

# Prefer a real compressor (Compress-Archive is ~1.8:1; 7z/zip give ~3:1).
SEVENZ=""
for c in 7z 7zz 7za; do command -v "$c" >/dev/null 2>&1 && { SEVENZ="$c"; break; }; done
if [ -n "$SEVENZ" ]; then
  say "compressor: $SEVENZ (zip, mx=9)"
  ( cd "$parent" && "$SEVENZ" a -tzip -mx=9 "$OUTW" msys )
elif command -v zip >/dev/null 2>&1; then
  say "compressor: zip -9"
  ( cd "$parent" && zip -r -q -9 "$OUTW" msys )
else
  say "compressor: PowerShell Compress-Archive (poor ratio — install 7zip/zip)"
  ( cd "$parent" && powershell -NoProfile -Command \
      "Compress-Archive -Path 'msys' -DestinationPath '$OUTW' -Force" )
fi
say "Done: $OUT ($(du -m "$OUT" | cut -f1) MB)"
echo "  Publish:  gh release create <tag> '$OUT' --repo nipscernlab/aurora-toolchain --prerelease"
echo "  (or --clobber upload to an existing tag). Match the tag in manifest.txt + Aurora's download-toolchain.js."
