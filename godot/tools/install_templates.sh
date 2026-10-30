#!/usr/bin/env bash
# Download and install the official Godot export templates (needed to export Android/iOS builds).
#   tools/install_templates.sh
set -euo pipefail
VER="${GODOT_VERSION:-4.6.1-stable}"
NAME="${VER/-/.}"                                    # 4.6.1-stable -> 4.6.1.stable
DEST="$HOME/.local/share/godot/export_templates/$NAME"
if [ -d "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then echo "templates present: $DEST"; exit 0; fi
TPZ="$HOME/.cache/godot-templates/templates.tpz"
mkdir -p "$(dirname "$TPZ")" "$DEST"
[ -s "$TPZ" ] || curl -sSL -C - -o "$TPZ" "https://github.com/godotengine/godot/releases/download/${VER}/Godot_v${VER}_export_templates.tpz"
TMP="$(mktemp -d)"
python3 -I -c "import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$TPZ" "$TMP"
mv "$TMP"/templates/* "$DEST"/
rm -rf "$TMP"
echo "installed to $DEST"
