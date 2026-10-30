#!/usr/bin/env bash
# Regenerate the Blender models (assets/models/*.glb). Needs a Python with the `bpy` module: set BLENDER_PY, or run
# tools/blender/ensure_bpy.sh once (creates ~/.cache/qt-bpyenv, takes about 10 minutes).
#   tools/blender/build_all.sh                 every model
#   tools/blender/build_all.sh player car_sport  only these (names are the model_<name>.py scripts; "pickups" makes 3 glb files)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="${BLENDER_PY:-}"
if [ -z "$PY" ]; then
  for c in "$HOME/.cache/qt-bpyenv/bin/python" "$HERE/../../.venv-bpy/bin/python"; do
    if [ -x "$c" ]; then PY="$c"; break; fi
  done
fi
if [ -z "$PY" ]; then echo "No bpy interpreter found. Set BLENDER_PY=/path/to/python or run tools/blender/ensure_bpy.sh" >&2; exit 1; fi
ALL=(player operative drone_sentinel drone_striker drone_heavy car_sedan car_sport car_suv pickups)
LIST=("$@")
if [ ${#LIST[@]} -eq 0 ]; then LIST=("${ALL[@]}"); fi
for n in "${LIST[@]}"; do
  echo "== model_$n.py"
  if ! out="$("$PY" "$HERE/model_$n.py" 2>&1)"; then echo "$out" | tail -25 >&2; echo "FAILED: model_$n.py" >&2; exit 1; fi
  echo "$out" | grep -E "^MODEL|WARNING: images" || true
done
