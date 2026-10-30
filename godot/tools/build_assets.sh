#!/usr/bin/env bash
# Regenerate every procedural asset: PBR textures -> Blender models -> audio, then import into Godot.
#   tools/build_assets.sh                 compact set (512 px textures that are committed) + models + audio + import
#   tools/build_assets.sh --hires         additionally writes the 1K texture sets to assets/generated/textures (git-ignored)
#   tools/build_assets.sh --skip-models   textures + audio only (no bpy needed)
# Needs python3 with numpy; the models need BLENDER_PY (see tools/blender/ensure_bpy.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
HIRES=0; MODELS=1; IMPORT=1
for a in "$@"; do
  case "$a" in
    --hires) HIRES=1 ;;
    --skip-models) MODELS=0 ;;
    --no-import) IMPORT=0 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done
PYTHON="${PYTHON:-python3}"
mkdir -p assets/generated && touch assets/generated/.gdignore      # big intermediates: git-ignored, and Godot must not import/export them
echo "== textures (512 px, committed)"
"$PYTHON" tools/blender/make_textures.py --size 512 --out assets/textures
if [ "$HIRES" = 1 ]; then
  echo "== textures (1024 px, assets/generated)"
  "$PYTHON" tools/blender/make_textures.py --size 1024 --out assets/generated/textures
fi
echo "== audio"
"$PYTHON" tools/audio/make_audio.py
if [ "$MODELS" = 1 ]; then
  echo "== models"
  tools/blender/build_all.sh
fi
if [ "$IMPORT" = 1 ]; then
  echo "== godot import"
  tools/import.sh
  "$PYTHON" tools/blender/patch_imports.py
  tools/import.sh
fi
tools/size_report.sh 2>/dev/null | tail -12 || true
