#!/usr/bin/env bash
# One look-dev iteration of the hero suit kit: bake (tools/blender/model_hero_suit.py) -> import -> render views at phone aspect. From godot/:
#   tools/hero/loop.sh OUT_PREFIX [views] [extra stage args...]      env  QUICK=1 (no atlas bake)  SKIP_BAKE=1  STAGE_RES=2400x1080
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT="$1"; VIEWS="${2:-back,three,front,bust}"; shift; shift || true
if [ -z "${SKIP_BAKE:-}" ]; then
  if [ -n "${QUICK:-}" ]; then export QT_HERO_QUICK=1; fi
  .venv-tools/bin/python tools/blender/model_hero_suit.py 2>&1 | grep -E "^KIT parts|^  atlas|^MODEL|Error|Traceback|error:" | head -8
  tools/import.sh 2>&1 | grep -iE "error" | head -3
fi
mkdir -p "$(dirname "$OUT")"
tools/hero/stage.sh "$OUT" views="$VIEWS" "$@" 2>&1 | grep -E "STAGE hero|STAGE DONE|SCRIPT ERROR|ERROR:" | sed 's/info {.*//' | head -6
