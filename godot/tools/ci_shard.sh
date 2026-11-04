#!/usr/bin/env bash
# Run one shard of the headless test suite (used by the CI matrix).
#   tools/ci_shard.sh <index> <count>     index is 0-based; every tests/test_*.gd lands in exactly one shard
#   CI_SHARD_LIST=1 tools/ci_shard.sh 1 4 only print this shard's files
# Files are dealt out round-robin after sorting by size (largest first), which spreads the heavy tests evenly.
# A failure is retried once (FLAKY if the retry passes); the shard exits 1 if any test still fails.
set -uo pipefail
cd "$(dirname "$0")/.."
IDX="${1:?usage: ci_shard.sh <index> <count>}"; CNT="${2:?usage: ci_shard.sh <index> <count>}"
if ! [[ "$IDX" =~ ^[0-9]+$ && "$CNT" =~ ^[1-9][0-9]*$ ]] || [ "$IDX" -ge "$CNT" ]; then echo "bad shard $IDX/$CNT" >&2; exit 2; fi
FILES=$(ls -S tests/test_*.gd | LC_ALL=C awk -v i="$IDX" -v c="$CNT" '(NR - 1) % c == i')
if [ -n "${CI_SHARD_LIST:-}" ]; then echo "$FILES"; exit 0; fi
total=$(echo "$FILES" | grep -c .); pass=0; flaky=0; fail=0; n=0
START=$(date +%s)
for t in $FILES; do
  n=$((n + 1)); echo "::group::[$n/$total] $t"
  if tools/test.sh "$t"; then pass=$((pass + 1))
  else
    echo "retrying $t once"
    if tools/test.sh "$t"; then flaky=$((flaky + 1)); echo "FLAKY $t (passed on retry)"
    else fail=$((fail + 1)); echo "FAIL $t"; fi
  fi
  echo "::endgroup::"
done
echo "shard $IDX/$CNT: $total test(s), pass $pass, flaky $flaky, fail $fail, $(( $(date +%s) - START )) s"
[ "$fail" -eq 0 ]
