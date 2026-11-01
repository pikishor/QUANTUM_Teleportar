#!/usr/bin/env bash
# Regenerate the Blender models (assets/models/*.glb) and their baked atlases (assets/textures/<model>_*.png).
# Needs the pinned toolchain (Python 3.13 with bpy 5.2.3 + numpy 2.5.4, tools/requirements.txt): set BLENDER_PY, or run
# tools/setup_python.sh once, which creates godot/.venv-tools and prints the interpreter path (this script then finds it).
#   tools/blender/build_all.sh                 every model
#   tools/blender/build_all.sh player car_sport  only these (names are the model_<name>.py scripts; "pickups" makes 3 glb files)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="${BLENDER_PY:-}"
if [ -z "$PY" ] && [ -x "$HERE/../../.venv-tools/bin/python" ]; then PY="$HERE/../../.venv-tools/bin/python"; fi
if [ -z "$PY" ]; then echo "No bpy interpreter found. Run tools/setup_python.sh (creates godot/.venv-tools) or set BLENDER_PY=/path/to/python" >&2; exit 1; fi
"$PY" -c 'import bpy, numpy' 2>/dev/null || { echo "error: $PY cannot import bpy and numpy (see tools/requirements.txt)" >&2; exit 1; }
ALL=(player operative citizen drone_sentinel drone_striker drone_heavy car_sedan car_sport car_suv car_taxi car_wagon car_van car_truck bike_street car_hover car_vael_patrol pickups)
LIST=("$@")
if [ ${#LIST[@]} -eq 0 ]; then LIST=("${ALL[@]}"); fi
for n in "${LIST[@]}"; do
  echo "== model_$n.py"
  if ! out="$("$PY" "$HERE/model_$n.py" 2>&1)"; then echo "$out" | tail -25 >&2; echo "FAILED: model_$n.py" >&2; exit 1; fi
  echo "$out" | grep -E "^MODEL|WARNING: images" || true
done
