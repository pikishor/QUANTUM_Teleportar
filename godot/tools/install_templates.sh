#!/usr/bin/env bash
# Download (SHA-512 verified) and install the official Godot export templates, needed for Android/iOS exports. Linux and macOS.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
VER="${GODOT_VERSION:-4.6.1-stable}"
NAME="${VER/-/.}"                                   # 4.6.1-stable -> 4.6.1.stable
case "$(uname -s)" in
  Linux)  DEST="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$NAME" ;;
  Darwin) DEST="$HOME/Library/Application Support/Godot/export_templates/$NAME" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
if [ -f "$DEST/version.txt" ]; then echo "templates present: $DEST"; exit 0; fi
FILE="Godot_v${VER}_export_templates.tpz"
TPZ="$HOME/.cache/godot-templates/$FILE"
mkdir -p "$(dirname "$TPZ")" "$DEST"
[ -s "$TPZ" ] || curl -sSL --retry 3 -o "$TPZ" "https://github.com/godotengine/godot/releases/download/${VER}/${FILE}"
"$HERE/verify_sha512.sh" "$TPZ" "$FILE"
TMP="$(mktemp -d)"
if command -v unzip >/dev/null 2>&1; then unzip -q -o "$TPZ" -d "$TMP"
else python3 -I -c "import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$TPZ" "$TMP"; fi
mv "$TMP"/templates/* "$DEST"/
rm -rf "$TMP"
echo "installed to $DEST"
