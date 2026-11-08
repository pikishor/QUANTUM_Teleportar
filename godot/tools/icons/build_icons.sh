#!/usr/bin/env bash
# Renders the item pictures (weapons, throwables, gadgets, vehicles, enemies) from the real 3D models and writes them as small palette PNGs into assets/icons/.
#   tools/icons/build_icons.sh [only=w_pistol,v_sedan,...]       (software Vulkan under xvfb, about 2-3 minutes for all of them; python3 + PIL)
# Then run tools/import.sh once. The icons are committed: the game does not need a renderer to show them (scripts/ui/item_icons.gd).
set -euo pipefail
cd "$(dirname "$0")/../.."
BIN="$(tools/get_godot.sh)"
RAW="${ICON_RAW:-$(mktemp -d)}"
timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" --rendering-driver vulkan --rendering-method mobile --resolution 1280x720 --path . res://tools/icons/icon_maker.tscn -- out="$RAW" "$@" 2>&1 \
  | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver\|leak\|^WARNING\|^   at\|backtrace\|^ERROR: .*RID" || true
mkdir -p assets/icons
python3 tools/icons/post.py "$RAW" assets/icons
