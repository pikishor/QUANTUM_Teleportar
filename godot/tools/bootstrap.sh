#!/usr/bin/env bash
# One command from a fresh clone to a working project.
#   godot/tools/bootstrap.sh                 Godot binary (checksum verified) + project import
#   godot/tools/bootstrap.sh --templates     ... plus the export templates (Android/iOS exports)
#   godot/tools/bootstrap.sh --assets        ... plus the Python env and regeneration of generated assets
set -euo pipefail
cd "$(dirname "$0")/.."
WANT_TEMPLATES=0; WANT_ASSETS=0
for a in "$@"; do case "$a" in --templates) WANT_TEMPLATES=1;; --assets) WANT_ASSETS=1;; *) echo "unknown option $a" >&2; exit 2;; esac; done
echo "== Godot binary"; tools/get_godot.sh
if [ "$WANT_TEMPLATES" = 1 ]; then echo "== export templates"; tools/install_templates.sh; fi
if [ "$WANT_ASSETS" = 1 ]; then
  echo "== asset tooling"; export BLENDER_PY; BLENDER_PY="$(tools/setup_python.sh)"; echo "BLENDER_PY=$BLENDER_PY"
  if [ -x tools/build_assets.sh ]; then tools/build_assets.sh; else echo "(no tools/build_assets.sh yet)"; fi
fi
echo "== import project"; tools/import.sh
echo "bootstrap complete"
