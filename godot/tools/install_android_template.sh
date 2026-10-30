#!/usr/bin/env bash
# Install Godot's Android gradle build template into the project (needed for AAB / Play Store builds). Generated; git-ignored.
set -euo pipefail
cd "$(dirname "$0")/.."
VER="${GODOT_VERSION:-4.6.1-stable}"; NAME="${VER/-/.}"
case "$(uname -s)" in
  Linux)  SRC="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$NAME/android_source.zip" ;;
  Darwin) SRC="$HOME/Library/Application Support/Godot/export_templates/$NAME/android_source.zip" ;;
esac
[ -f "$SRC" ] || { echo "error: export templates missing; run tools/install_templates.sh" >&2; exit 1; }
rm -rf android/build
mkdir -p android/build
if command -v unzip >/dev/null 2>&1; then unzip -q -o "$SRC" -d android/build; else python3 -I -c "import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$SRC" android/build; fi
printf '%s' "$NAME" > android/.build_version
touch android/build/.gdignore
echo "android build template installed (res://android/build, $NAME)"
