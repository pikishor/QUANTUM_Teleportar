#!/usr/bin/env bash
# Verify a downloaded Godot artifact against the official SHA-512 (pinned below for 4.6.1-stable; copied from the release's SHA512-SUMS.txt).
#   tools/verify_sha512.sh <file> <release-asset-name>
# Bumping GODOT_VERSION means adding the new hashes here.
set -euo pipefail
FILE="$1"; NAME="$2"; VER="${GODOT_VERSION:-4.6.1-stable}"
expected=""
case "$VER:$NAME" in
  4.6.1-stable:Godot_v4.6.1-stable_linux.x86_64.zip)
    expected="a76fd0fe1d44a2dd6c065b6f7b434ad75f5593c07bda3d3017f8304f2d069acbcf0f39cb5d0976f0434b56e9ea852032ddbcbdb7e0ce1c75a47e1dacb6794bd7" ;;
  4.6.1-stable:Godot_v4.6.1-stable_macos.universal.zip)
    expected="59c7fc792c9a7a9b3c877b43fc6bdedfa3618e90f0d7d5fa77edb8d3bd64568af19bdfa6ecc8ec3eeaa17ad9cb65f7c93760de83b485ae4a33a679e730f7ffd9" ;;
  4.6.1-stable:Godot_v4.6.1-stable_export_templates.tpz)
    expected="d80001711c07973b1fd3e88077ba99644e19db7c9e52627e16f38a2937879f809f94dbd8493936fb8204908bbc57a521d41173dce5208061fe4c99772490c541" ;;
esac
if [ -z "$expected" ]; then
  if [ "${GODOT_SKIP_VERIFY:-0}" = "1" ]; then echo "warning: no pinned checksum for $VER:$NAME; skipping verification" >&2; exit 0; fi
  echo "error: no pinned SHA-512 for $VER:$NAME (add it to tools/verify_sha512.sh or set GODOT_SKIP_VERIFY=1)" >&2; exit 1
fi
if command -v sha512sum >/dev/null 2>&1; then actual="$(sha512sum "$FILE" | cut -d' ' -f1)"; else actual="$(shasum -a 512 "$FILE" | cut -d' ' -f1)"; fi
if [ "$actual" != "$expected" ]; then echo "error: checksum mismatch for $NAME" >&2; exit 1; fi
echo "checksum ok: $NAME" >&2
