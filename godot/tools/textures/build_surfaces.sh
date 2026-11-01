#!/usr/bin/env bash
# Regenerate the tier-scaled PBR surface sets (numpy + Pillow, about 80 s) and import them as VRAM-compressed textures with mipmaps.
#   tools/textures/build_surfaces.sh [--only asphalt,brick] [--no-gen]
set -euo pipefail
cd "$(dirname "$0")/../.."
PY="${PYTHON:-python3}"
if [[ "${1:-}" != "--no-gen" ]]; then "$PY" -I tools/textures/gen_surfaces.py "$@"; fi
tools/import.sh                                              # writes the default .import files for new PNGs
"$PY" -I tools/textures/gen_surfaces.py --patch-imports       # ASTC / BPTC high quality, mipmaps, packed data stays a colour texture
tools/import.sh                                              # re-imports with the patched settings
