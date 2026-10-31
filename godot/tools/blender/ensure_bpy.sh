#!/usr/bin/env bash
# Kept for old habits: the pinned toolchain (Python 3.13, bpy 5.2.3, numpy 2.5.4 from tools/requirements.txt) is created by
# tools/setup_python.sh, which prints the interpreter path:   export BLENDER_PY="$(tools/blender/ensure_bpy.sh)"
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/../setup_python.sh"
