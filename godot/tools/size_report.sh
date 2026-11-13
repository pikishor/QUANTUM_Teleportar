#!/usr/bin/env bash
# Report content size against the install budget in BUDGETS.md; exits 1 when over budget.
#   tools/size_report.sh [budget_mb]        (default 5120)
set -euo pipefail
cd "$(dirname "$0")/.."
BUDGET_MB="${1:-5120}"
echo "Largest asset files:"
find assets -type f ! -name '*.import' -printf '%s %p\n' 2>/dev/null | sort -rn | head -15 | awk '{printf "%9.2f MB  %s\n", $1/1048576, $2}' || true   # head closes the pipe early: under pipefail that is exit 141, not an error
echo
echo "By folder:"
for d in assets/*/; do
  [ -d "$d" ] && printf "%9.2f MB  %s\n" "$(du -sk "$d" | awk '{print $1/1024}')" "$d"
done
if [ -d .godot/imported ]; then      # after tools/import.sh: what the exported pack really holds (textures are VRAM-compressed: BPTC/S3TC on desktop, ASTC / ETC2 on phones)
  echo
  echo "Imported (this platform's texture format; the Android/iOS pack is about the same, ASTC 4x4 = BPTC = 8 bit per pixel):"
  for ext in ctex scn res sample oggvorbisstr mp3str; do
    n="$(find .godot/imported -name "*.$ext" -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {printf "%.1f", s/1048576}')"
    [ "${n:-0}" != "0.0" ] && [ -n "$n" ] && printf "%9.2f MB  .%s\n" "$n" "$ext"
  done
fi
TOTAL_MB="$(du -sk assets 2>/dev/null | awk '{print int($1/1024)}')"
echo
echo "assets total: ${TOTAL_MB:-0} MB (budget ${BUDGET_MB} MB; engine runtime adds roughly 60-100 MB)"
if [ "${TOTAL_MB:-0}" -gt "$BUDGET_MB" ]; then echo "OVER BUDGET"; exit 1; fi
