#!/usr/bin/env bash
# Converts the Quaternius Ultimate Monsters rigs into assets/models/aliens/*.scn (see convert_monsters.gd; sources in art_sources/quaternius_ultimate_monsters).
#   tools/open_models/convert_monsters.sh [id,id,...]
set -euo pipefail
cd "$(dirname "$0")/../.."
BIN="$(tools/get_godot.sh)"
SRC="$(realpath ../art_sources/quaternius_ultimate_monsters)"
SCRATCH="$(mktemp -d)"
mkdir -p "$SCRATCH/raw" "$SCRATCH/out"
# group_name.gltf from Big/ Blob/ Flying/ (the same names exist in two groups)
for f in "$SRC"/Big/*.gltf "$SRC"/Blob/*.gltf "$SRC"/Flying/*.gltf; do
  g="$(basename "$(dirname "$f")" | tr 'A-Z' 'a-z')"
  n="$(basename "$f" .gltf | tr 'A-Z' 'a-z')"
  cp "$f" "$SCRATCH/raw/${g}_${n}.gltf"
done
cp "$SRC/Atlas_Monsters.png" "$SCRATCH/raw/atlas.png"
printf 'config_version=5\n[application]\nconfig/name="monsters"\n' > "$SCRATCH/project.godot"
cp tools/open_models/convert_monsters.gd "$SCRATCH/"
"$BIN" --headless --path "$SCRATCH" --import >/dev/null 2>&1 || true
"$BIN" --headless --path "$SCRATCH" -s convert_monsters.gd -- "$SCRATCH/out" ${1:+"$1"} 2>&1 | grep -v "ALSA\|audio driver\|leaked\|RID allocations\|PagedAllocator\|ObjectDB\|resources still\|instance_notify\|at: "
mkdir -p assets/models/aliens
cp "$SCRATCH"/out/*.scn assets/models/aliens/
rm -rf "$SCRATCH"
