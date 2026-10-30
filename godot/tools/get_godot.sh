#!/usr/bin/env bash
# Prints the path to a Godot 4.6.x editor binary, downloading the official GitHub release on first use.
set -euo pipefail
VER="${GODOT_VERSION:-4.6.1-stable}"
DIR="${GODOT_CACHE:-$HOME/.cache/godot-$VER}"
BIN="$DIR/Godot_v${VER}_linux.x86_64"
if [ ! -x "$BIN" ]; then
  mkdir -p "$DIR"
  curl -sSL -o "$DIR/godot.zip" "https://github.com/godotengine/godot/releases/download/${VER}/Godot_v${VER}_linux.x86_64.zip"
  python3 -I -c "import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$DIR/godot.zip" "$DIR"
  chmod +x "$BIN"
fi
echo "$BIN"
