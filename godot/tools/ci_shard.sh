#!/usr/bin/env bash
# Run one shard of the headless test suite (used by the CI matrix).
#   tools/ci_shard.sh <index> <count>     index is 0-based; every tests/test_*.gd lands in exactly one shard
#   CI_SHARD_LIST=1 tools/ci_shard.sh 1 4 only print this shard's files
# Files are dealt out round-robin after sorting by size (largest first), which spreads the heavy tests evenly.
# A failure is retried once (FLAKY if the retry passes); the shard exits 1 if any test still fails.
# What failed is easy to find: the check lines of a failed attempt (FAIL / SCRIPT ERROR) are printed again after the last test, written to the job summary and raised as annotations of the run
# (::error for a test that failed twice, ::warning for a flaky one). A shard log is 200 000 lines long and the log API shows only its last 5000, so without this the name of the failed test is lost.
set -uo pipefail
cd "$(dirname "$0")/.."
IDX="${1:?usage: ci_shard.sh <index> <count>}"; CNT="${2:?usage: ci_shard.sh <index> <count>}"
if ! [[ "$IDX" =~ ^[0-9]+$ && "$CNT" =~ ^[1-9][0-9]*$ ]] || [ "$IDX" -ge "$CNT" ]; then echo "bad shard $IDX/$CNT" >&2; exit 2; fi
FILES=$(ls -S tests/test_*.gd | LC_ALL=C awk -v i="$IDX" -v c="$CNT" '(NR - 1) % c == i')
if [ -n "${CI_SHARD_LIST:-}" ]; then echo "$FILES"; exit 0; fi

# attempt <test> <log>: one run of a test; its output goes to the job log and to <log>; returns the test's exit code
attempt() {
  tools/test.sh "$1" 2>&1 | tee "$2"
  return "${PIPESTATUS[0]}"
}
# fail_lines <log>: the lines that say what failed (the first eight, cut to 300 characters)
fail_lines() { grep -a -E '^(FAIL|SCRIPT ERROR|Parse Error|handle_crash)' "$1" | cut -c1-300 | head -8; }
# annotate <error|warning> <title> <log>: a workflow command with the failed lines as its message (%, CR and LF escaped the way the runner wants them; a title must not hold a comma or a colon: the runner cuts it there)
annotate() {
  local msg
  msg=$(fail_lines "$3" | sed -e 's/%/%25/g' -e 's/\r//g' | awk 'BEGIN { ORS = "%0A" } { print }')
  echo "::$1 title=$2::${msg:-no FAIL line in the output (a crash, a timeout or an exit code only)}"
}

total=$(echo "$FILES" | grep -c .); pass=0; flaky=0; fail=0; n=0
LOG1=$(mktemp); LOG2=$(mktemp); RECAP=""
START=$(date +%s)
for t in $FILES; do
  n=$((n + 1)); echo "::group::[$n/$total] $t"
  attempt "$t" "$LOG1"; rc1=$?
  if [ "$rc1" -eq 0 ]; then pass=$((pass + 1))
  else
    echo "retrying $t once (exit code $rc1)"
    attempt "$t" "$LOG2"; rc2=$?
    if [ "$rc2" -eq 0 ]; then
      flaky=$((flaky + 1)); echo "FLAKY $t (passed on retry)"
      annotate warning "FLAKY $t (first attempt exit $rc1)" "$LOG1"
      RECAP+=$'\n'"FLAKY $t (first attempt exit $rc1, the retry passed)"$'\n'"$(fail_lines "$LOG1" | sed 's/^/    /')"
    else
      fail=$((fail + 1)); echo "FAIL $t"
      annotate error "FAIL $t (exit $rc2)" "$LOG2"
      RECAP+=$'\n'"FAILED $t (exit $rc1, then $rc2 on the retry)"$'\n'"$(fail_lines "$LOG2" | sed 's/^/    /')"
    fi
  fi
  echo "::endgroup::"
done
rm -f "$LOG1" "$LOG2"
if [ -n "$RECAP" ]; then
  echo "---- shard $IDX/$CNT: what failed (the whole output of a test is in its group above)$RECAP"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then { echo "### Godot tests, shard $IDX of $CNT"; echo '```'; printf '%s\n' "$RECAP"; echo '```'; } >> "$GITHUB_STEP_SUMMARY"; fi
fi
echo "shard $IDX/$CNT: $total test(s), pass $pass, flaky $flaky, fail $fail, $(( $(date +%s) - START )) s"
[ "$fail" -eq 0 ]
