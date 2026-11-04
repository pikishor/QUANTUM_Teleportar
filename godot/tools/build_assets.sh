#!/usr/bin/env bash
# Regenerate every procedural asset: PBR texture sets -> audio -> Blender models (with their baked atlases) -> Godot import.
#   tools/build_assets.sh                 compact set (the committed sizes) + models + audio + import
#   tools/build_assets.sh --hires         additionally writes the 1K tiling texture sets to assets/generated (git-ignored)
#   tools/build_assets.sh --skip-models   textures + audio only (needs numpy, not bpy)
#   tools/build_assets.sh --no-import     do not run the Godot import afterwards
#   tools/build_assets.sh --atlas-scale 1  bake the model atlases at the old compact size (1K; default 2 = 2K hero / trooper / drones / cars, 1K pickups)
#
# One interpreter runs every Python step: the pinned toolchain of tools/requirements.txt (Python 3.13, bpy 5.2.3, numpy 2.5.4).
# It is found in this order: $BLENDER_PY (what `make assets` / tools/bootstrap.sh --assets export), godot/.venv-tools (created by
# tools/setup_python.sh), otherwise this script creates that venv. With --skip-models any python that can import numpy is accepted
# ($PYTHON, default python3), because the textures and the audio do not need bpy.
set -euo pipefail
cd "$(dirname "$0")/.."
HIRES=0; MODELS=1; IMPORT=1
while [ $# -gt 0 ]; do
  a="$1"; shift
  case "$a" in
    --atlas-scale) export QT_ATLAS_SCALE="${1:?--atlas-scale needs a number}"; shift ;;
    --hires) HIRES=1 ;;
    --skip-models) MODELS=0 ;;
    --no-import) IMPORT=0 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done

pick_python() {
  if [ -n "${BLENDER_PY:-}" ]; then echo "$BLENDER_PY"; return; fi
  if [ -x .venv-tools/bin/python ]; then echo "$(pwd)/.venv-tools/bin/python"; return; fi
  if [ "$MODELS" = 0 ]; then
    local p="${PYTHON:-python3}"
    if "$p" -c 'import numpy' 2>/dev/null; then echo "$p"; return; fi
  fi
  tools/setup_python.sh
}
PY="$(pick_python)"
export BLENDER_PY="$PY"
"$PY" -c 'import numpy' 2>/dev/null || { echo "error: $PY cannot import numpy; run tools/setup_python.sh or set BLENDER_PY" >&2; exit 1; }
if [ "$MODELS" = 1 ]; then
  "$PY" -c 'import bpy' 2>/dev/null || { echo "error: $PY cannot import bpy (needed for the models); run tools/setup_python.sh or set BLENDER_PY, or use --skip-models" >&2; exit 1; }
fi
echo "python: $PY"

mkdir -p assets/generated && touch assets/generated/.gdignore      # big intermediates: git-ignored, and Godot must not import/export them
echo "== tiling PBR texture sets (committed size)"
"$PY" tools/blender/make_textures.py --size 512 --out assets/textures
if [ "$HIRES" = 1 ]; then
  echo "== tiling PBR texture sets (1024 px, assets/generated)"
  "$PY" tools/blender/make_textures.py --size 1024 --out assets/generated/textures
fi
echo "== audio"
"$PY" tools/audio/make_audio.py
"$PY" tools/audio/make_depth.py
"$PY" tools/audio/make_weapons.py
if [ "$MODELS" = 1 ]; then
  echo "== models + atlases"
  tools/blender/build_all.sh
fi
if [ "$IMPORT" = 1 ]; then
  echo "== godot import"
  tools/import.sh
  "$PY" tools/blender/patch_imports.py
  tools/import.sh
fi
tools/size_report.sh 2>/dev/null | tail -12 || true
