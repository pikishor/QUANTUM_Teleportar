#!/usr/bin/env bash
# Create godot/.venv-tools with the pinned Python packages the asset generators need, and print the interpreter path.
#   BLENDER_PY="$(godot/tools/setup_python.sh)"
set -euo pipefail
cd "$(dirname "$0")/.."
PY="${PYTHON:-python3.13}"
command -v "$PY" >/dev/null 2>&1 || PY=python3
"$PY" -c 'import sys; sys.exit(0 if sys.version_info[:2] == (3, 13) else 1)' || { echo "error: bpy 5.2.3 needs Python 3.13 (found $("$PY" --version 2>&1)); set PYTHON=/path/to/python3.13" >&2; exit 1; }
if [ ! -x .venv-tools/bin/python ]; then "$PY" -m venv .venv-tools >&2; fi
.venv-tools/bin/pip install -q -r tools/requirements.txt >&2
echo "$(pwd)/.venv-tools/bin/python"
