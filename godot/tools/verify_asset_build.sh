#!/usr/bin/env bash
# Proves the asset pipeline from a clean tree with an EMPTY HOME: copies what a commit of this checkout would contain (tracked + untracked files that are not git-ignored, or a
# fresh clone when $1 is a repository URL / path with --clone) to a temp directory, runs tools/build_assets.sh there with a scrubbed environment (empty HOME, no BLENDER_PY, no
# cached Godot, no venv: it downloads the pinned Godot, creates godot/.venv-tools, pip-installs bpy 5.2.3 + numpy, bakes textures, audio and models, imports, pins the import settings)
# and compares every generated file byte for byte with this checkout. Exit 0 = the clean build reproduces the committed assets exactly.
#   tools/verify_asset_build.sh                  this checkout (committable files)
#   tools/verify_asset_build.sh --clone URL      a fresh git clone of URL instead
#   env KEEP=1 keeps the temp directory; PYTHON=/path/to/python3.13 picks the interpreter; GODOT_CACHE=dir reuses a downloaded Godot instead of downloading again
#   (takes 15 to 20 minutes: the 2K atlases are baked with numpy and a BVH ray tracer)
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() { if [ -z "${KEEP:-}" ]; then rm -rf "$TMP"; else echo "kept: $TMP"; fi; }
trap cleanup EXIT
mkdir -p "$TMP/home" "$TMP/tree"
if [ "${1:-}" = "--clone" ]; then
  git clone -q "${2:?repository URL}" "$TMP/tree" || exit 1
else
  (cd "$REPO" && git ls-files -z --cached --others --exclude-standard | tar --null --ignore-failed-read -T - -cf - 2>/dev/null) | tar -xf - -C "$TMP/tree" || exit 1
fi
echo "tree: $(find "$TMP/tree" -type f | wc -l) files in $TMP/tree, HOME=$TMP/home (empty)"
cd "$TMP/tree/godot" || exit 1
mkdir -p "$TMP/ref"
# the checkout's generated files are the reference; a build must overwrite them with identical bytes
for d in assets/models assets/textures assets/audio; do mkdir -p "$TMP/ref/$d"; cp -a "$HERE/$d/." "$TMP/ref/$d/"; done
start=$(date +%s)
# only the network settings of the machine are passed through (proxy, CA bundle); nothing about the project: no HOME, no cached Godot, no venv, no BLENDER_PY
pass=()
for v in HTTPS_PROXY https_proxy HTTP_PROXY http_proxy NO_PROXY no_proxy SSL_CERT_FILE REQUESTS_CA_BUNDLE CURL_CA_BUNDLE PIP_CERT PYTHON GODOT_CACHE; do
  [ -n "${!v:-}" ] && pass+=("$v=${!v}")
done
env -i HOME="$TMP/home" PATH="/usr/local/bin:/usr/bin:/bin" "${pass[@]}" tools/build_assets.sh > "$TMP/build.log" 2>&1
status=$?
tail -15 "$TMP/build.log"
echo "build_assets.sh exit $status after $(( $(date +%s) - start )) s"
[ $status -eq 0 ] || { echo "FAIL: the clean build did not finish (log: $TMP/build.log)"; KEEP=1; exit 1; }
same=0; diff=0; missing=0
while IFS= read -r f; do
  rel="${f#"$TMP/ref/"}"
  if [ ! -e "$rel" ]; then echo "missing after build: $rel"; missing=$((missing+1)); elif cmp -s "$f" "$rel"; then same=$((same+1)); else echo "differs: $rel"; diff=$((diff+1)); fi
done < <(find "$TMP/ref" -type f ! -name '*.import' ! -name '*.uid' | sort)
echo "reproducible files: $same identical, $diff different, $missing missing (models, textures, audio; .import files excluded)"
[ $diff -eq 0 ] && [ $missing -eq 0 ]
