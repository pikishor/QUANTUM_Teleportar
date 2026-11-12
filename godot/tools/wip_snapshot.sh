#!/usr/bin/env bash
# Backs up ALL uncommitted work of the shared working tree (agents' work in progress included) to a side branch on GitHub.
#
#   godot/tools/wip_snapshot.sh            one snapshot now
#   godot/tools/wip_snapshot.sh loop 1500  a snapshot every 1500 s until stopped
#
# It never touches HEAD, the real index or any file: the commit is built with a private index file, so it is safe while agents are working.
# The branch (default claude/determined-bardeen-mvwr5u, the session branch) is a safety net and holds UNTESTED work: tested work goes to main through the
# wave integrators (full suite, perf gate on all three tiers, visual QA). To get work back: see docs/sprint/RESUME.md.
set -euo pipefail

if [ "${1:-}" = "loop" ]; then
	every="${2:-1500}"
	while true; do
		"$0" || echo "snapshot failed (will retry in ${every} s)"
		sleep "$every"
	done
fi

cd "$(git rev-parse --show-toplevel)"
# a small text digest of what every running agent has done goes into the snapshot too (docs/sprint/progress/auto_*.md), so a new session can resume mid-wave
python3 godot/tools/sprint_digest.py >/dev/null 2>&1 || echo "digest skipped"
BR="${WIP_BRANCH:-claude/determined-bardeen-mvwr5u}"
MAXKB="${WIP_MAX_FILE_KB:-40000}"     # files above this stay out of the snapshot (GitHub refuses 100 MB files)
GD="$(git rev-parse --git-dir)"
export GIT_INDEX_FILE="$GD/wip_snapshot_index"
trap 'rm -f "$GIT_INDEX_FILE" "$GIT_INDEX_FILE.lock"' EXIT
rm -f "$GIT_INDEX_FILE" "$GIT_INDEX_FILE.lock"
# start from a copy of the real index (its stat cache makes `git add -A` fast), or from HEAD
if [ -f "$GD/index" ]; then cp "$GD/index" "$GIT_INDEX_FILE"; else git read-tree HEAD; fi
git add -A -- . >/dev/null 2>&1 || true

# keep oversized files out
git diff --cached --name-only --diff-filter=AM -z | while IFS= read -r -d '' f; do
	kb=$(( ($(stat -c %s -- "$f" 2>/dev/null || echo 0) + 1023) / 1024 ))
	if [ "$kb" -gt "$MAXKB" ]; then echo "skipping big file ($kb KB): $f"; git rm -q --cached -- "$f"; fi
done

TREE="$(git write-tree)"
HEADC="$(git rev-parse HEAD)"
git fetch -q origin "$BR" 2>/dev/null || true
PARENT="$(git rev-parse -q --verify "refs/heads/$BR" || git rev-parse -q --verify "refs/remotes/origin/$BR" || true)"

if [ -z "$PARENT" ]; then
	PARGS=(-p "$HEADC")
elif git merge-base --is-ancestor "$PARENT" "$HEADC"; then
	PARGS=(-p "$HEADC")                      # the branch is behind main: continue on top of main
elif git merge-base --is-ancestor "$HEADC" "$PARENT"; then
	PARGS=(-p "$PARENT")                     # the branch already contains main
else
	PARGS=(-p "$PARENT" -p "$HEADC")         # both moved: a merge-shaped snapshot keeps both histories
fi

# nothing new since the last snapshot (or nothing uncommitted at all)?
if [ -n "$PARENT" ] && [ "$(git rev-parse "$PARENT^{tree}")" = "$TREE" ]; then echo "no change since the last snapshot ($(git rev-parse --short "$PARENT"))"; exit 0; fi
if [ "$(git rev-parse "$HEADC^{tree}")" = "$TREE" ]; then echo "working tree equals HEAD: nothing uncommitted to back up"; exit 0; fi

FILES="$(git diff --cached --name-only "$HEADC" | wc -l)"
MSG="WIP snapshot $(date -u '+%Y-%m-%d %H:%MZ'): $FILES uncommitted files of the round 6 sprint on top of $(git rev-parse --short "$HEADC"). Untested safety copy, not for main."
COMMIT="$(printf '%s\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01WbKrgUpExX7TuSc4cdY35F\n' "$MSG" | git commit-tree "$TREE" "${PARGS[@]}")"
git update-ref "refs/heads/$BR" "$COMMIT"
for try in 1 2 3 4; do
	if git push -q origin "$COMMIT:refs/heads/$BR"; then echo "snapshot $(git rev-parse --short "$COMMIT") pushed to $BR ($FILES files)"; exit 0; fi
	sleep $((try * 5))
done
echo "push failed after 4 tries (the commit $COMMIT is kept locally on $BR)"; exit 1
