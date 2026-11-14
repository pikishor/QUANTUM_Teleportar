#!/usr/bin/env bash
# Renders the weapon pictures (every id of WeaponDefs.all_ids(), 3/4 view, class-coloured rim light) and packs them into the atlas pages of assets/icons/wp/ (scripts/ui/weapon_pics.gd).
#   tools/icons/weapon_pics.sh [--all] [only=a_pillar,m_arcsabre] [class=rifle,melee] [view=yaw,pitch]
# Without arguments only the weapons whose model (or whose renderer VERSION) changed since the last run are rendered: assets/icons/wp/manifest.json holds the md5 of every model file and of the
# renderer; --all renders everything. Needs software Vulkan (xvfb), python3 with numpy and PIL. Afterwards run tools/import.sh once (the atlas pages are textures) and commit assets/icons/wp/.
# tests/test_weapon_pics.gd fails when a model changed and its picture was not rebuilt (`python3 tools/icons/weapon_atlas.py --check`).
set -euo pipefail
cd "$(dirname "$0")/../.."
BIN="$(tools/get_godot.sh)"
ALL=0; PASS=()
for a in "$@"; do if [ "$a" = "--all" ]; then ALL=1; else PASS+=("$a"); fi; done
RAW="${WPIC_RAW:-$(mktemp -d)}"
mkdir -p "$RAW"
STALE=""
if [ "$ALL" = 0 ] && [ ${#PASS[@]} -eq 0 ]; then
  STALE="$(python3 tools/icons/weapon_atlas.py --stale)"
  if [ -z "$STALE" ]; then echo "weapon pictures are up to date"; exit 0; fi
  PASS=("only=$STALE")
fi
timeout 1500 xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" --rendering-driver vulkan --rendering-method mobile --resolution 1280x720 --path . res://tools/icons/weapon_pics.tscn -- out="$RAW" "${PASS[@]}" 2>&1 \
  | grep -E "WEAPON PICS|SCRIPT ERROR|SHADER ERROR|Parse Error|no model" || true
python3 tools/icons/weapon_atlas.py --raw "$RAW" --pack
