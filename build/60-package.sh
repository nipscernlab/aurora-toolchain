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

rm -f "$OUT"
say "Zipping $ROOT → $OUT"
if command -v 7z >/dev/null 2>&1; then
  ( cd "$parent" && 7z a -tzip -mx=5 "$(cygpath -w "$OUT" 2>/dev/null || echo "$OUT")" msys )
else
  ( cd "$parent" && powershell -NoProfile -Command \
      "Compress-Archive -Path 'msys' -DestinationPath '$(cygpath -w "$OUT" 2>/dev/null || echo "$OUT")' -Force" )
fi
say "Done: $OUT ($(du -m "$OUT" | cut -f1) MB)"
echo "  Publish:  gh release create <tag> '$OUT' --repo nipscernlab/aurora-toolchain --prerelease"
echo "  (or --clobber upload to an existing tag). Match the tag in manifest.txt + Aurora's download-toolchain.js."
