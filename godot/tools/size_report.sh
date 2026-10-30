#!/usr/bin/env bash
# Report content size against the install budget in BUDGETS.md; exits 1 when over budget.
#   tools/size_report.sh [budget_mb]        (default 5120)
set -euo pipefail
cd "$(dirname "$0")/.."
BUDGET_MB="${1:-5120}"
echo "Largest asset files:"
find assets -type f ! -name '*.import' -printf '%s %p\n' 2>/dev/null | sort -rn | head -15 | awk '{printf "%9.2f MB  %s\n", $1/1048576, $2}'
echo
echo "By folder:"
for d in assets/*/; do
  [ -d "$d" ] && printf "%9.2f MB  %s\n" "$(du -sk "$d" | awk '{print $1/1024}')" "$d"
done
TOTAL_MB="$(du -sk assets 2>/dev/null | awk '{print int($1/1024)}')"
echo
echo "assets total: ${TOTAL_MB:-0} MB (budget ${BUDGET_MB} MB; engine runtime adds roughly 60-100 MB)"
if [ "${TOTAL_MB:-0}" -gt "$BUDGET_MB" ]; then echo "OVER BUDGET"; exit 1; fi
