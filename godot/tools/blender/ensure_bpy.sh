#!/usr/bin/env bash
# Create (once) a virtualenv with Blender as a Python module (`pip install bpy`, a ~300 MB wheel, about 10 minutes) and print
# the interpreter path:   export BLENDER_PY="$(tools/blender/ensure_bpy.sh)"
set -euo pipefail
VENV="${QT_BPY_VENV:-$HOME/.cache/qt-bpyenv}"
if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c "import bpy" 2>/dev/null; then echo "$VENV/bin/python"; exit 0; fi
python3 -m venv "$VENV" >&2
"$VENV/bin/pip" install --quiet bpy numpy >&2
echo "$VENV/bin/python"
