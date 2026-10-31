#!/usr/bin/env bash
# Clone origin/main (or the repo given as $1) into a temp dir, import, and run every headless test. Proves a clean clone builds and passes.
#   godot/tools/verify_clean_clone.sh [repo-url-or-path]      (takes about 5 minutes)
set -uo pipefail
SRC="${1:-https://github.com/pikishor/QUANTUM_Teleportar}"
DIR="$(mktemp -d)"; trap 'rm -rf "$DIR"' EXIT
git clone -q "$SRC" "$DIR/clone" && cd "$DIR/clone/godot" || exit 1
echo "clone HEAD: $(git log --oneline | head -1)"
tools/import.sh > /dev/null 2>&1
fail=0
for t in tests/test_*.gd; do
  out="$(tools/test.sh "$t" 2>&1)"
  if echo "$out" | grep -q "RESULT: PASS"; then echo "PASS $t"; else echo "FAIL $t"; echo "$out" | grep -E "FAIL|SCRIPT ERROR|Parse" | head -5; fail=1; fi
done
exit $fail
