#!/usr/bin/env bash
# Run every tests/test_*.gd in parallel (default 3 jobs; 4 CPUs) and print PASS/FAIL per file. Exit 1 if any fail.
#   tools/test_all.sh            # all tests
#   JOBS=4 tools/test_all.sh     # more parallelism
#   tools/test_all.sh hud touch  # only files whose name contains one of the words
# Failures are retried once (known timing-sensitive tests) and reported as FLAKY if the retry passes.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
FILES=$(ls tests/test_*.gd | sort)
if [ "$#" -gt 0 ]; then
  SEL=""
  for w in "$@"; do SEL="$SEL $(echo "$FILES" | grep "$w" || true)"; done
  FILES=$(echo "$SEL" | tr ' ' '\n' | sort -u | grep . || true)
fi
run_one() {
  f="$1"; out="$2/$(basename "$f").log"
  if tools/test.sh "$f" >"$out" 2>&1; then echo "PASS $f"; return 0; fi
  if tools/test.sh "$f" >"$out.retry" 2>&1; then echo "FLAKY $f (passed on retry)"; return 0; fi
  echo "FAIL $f (log: $out)"; return 1
}
export -f run_one
RES=$(echo "$FILES" | xargs -P "${JOBS:-3}" -I{} bash -c 'run_one {} '"$OUT")
echo "$RES" | sort
echo "---"; echo "pass: $(echo "$RES" | grep -c '^PASS') flaky: $(echo "$RES" | grep -c '^FLAKY') fail: $(echo "$RES" | grep -c '^FAIL')"
! echo "$RES" | grep -q '^FAIL'
