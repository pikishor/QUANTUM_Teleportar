#!/usr/bin/env bash
# Prints the path to the pinned Godot editor binary. Downloads the official release (SHA-512 verified) on first use. Linux and macOS.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
VER="${GODOT_VERSION:-4.6.1-stable}"
case "$(uname -s)" in
  Linux)  FILE="Godot_v${VER}_linux.x86_64.zip"; REL="Godot_v${VER}_linux.x86_64" ;;
  Darwin) FILE="Godot_v${VER}_macos.universal.zip"; REL="Godot.app/Contents/MacOS/Godot" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
DIR="${GODOT_CACHE:-$HOME/.cache/godot-$VER}"
BIN="$DIR/$REL"
if [ ! -x "$BIN" ]; then
  mkdir -p "$DIR"
  curl -sSL --retry 3 -o "$DIR/$FILE" "https://github.com/godotengine/godot/releases/download/${VER}/${FILE}" >&2
  "$HERE/verify_sha512.sh" "$DIR/$FILE" "$FILE"
  if command -v unzip >/dev/null 2>&1; then unzip -q -o "$DIR/$FILE" -d "$DIR" >&2
  else python3 -I -c "import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$DIR/$FILE" "$DIR" >&2; fi
  chmod +x "$BIN"
fi
echo "$BIN"
