#!/usr/bin/env bash
# Converts the Quaternius animal packs into assets/models/animals/*.scn (see art_sources/open_animals/SOURCE.md for the three zips).
#   tools/open_models/convert_animals.sh <dir holding the unzipped FBX files, lower-case names: horse.fbx cow.fbx sheep.fbx llama.fbx pig.fbx zebra.fbx wolf.fbx red_fox.fbx bird.fbx fish.fbx whale.fbx>
set -euo pipefail
cd "$(dirname "$0")/../.."
BIN="$(tools/get_godot.sh)"
RAW="$(realpath "$1")"
SCRATCH="$(mktemp -d)"
mkdir -p "$SCRATCH/raw" "$SCRATCH/out"
cp "$RAW"/*.fbx "$SCRATCH/raw/"
printf 'config_version=5\n[application]\nconfig/name="animals"\n' > "$SCRATCH/project.godot"
cp tools/open_models/convert_animals.gd "$SCRATCH/"
"$BIN" --headless --path "$SCRATCH" --import >/dev/null 2>&1 || true
"$BIN" --headless --path "$SCRATCH" -s convert_animals.gd -- res://out 2>&1 | grep -v "ALSA\|audio driver"
mkdir -p assets/models/animals
cp "$SCRATCH"/out/*.scn assets/models/animals/
rm -rf "$SCRATCH"
