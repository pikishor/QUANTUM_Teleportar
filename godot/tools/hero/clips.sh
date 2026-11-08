#!/usr/bin/env bash
# Rebuild assets/anim/hero_clips.res from the Quaternius Universal Animation Library (CC0): fetches the two Standard zips from OpenGameArt when absent.
#   tools/hero/clips.sh            (needs python3 + numpy, curl, unzip, and the imported project: tools/import.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
W="${CLIPS_WORK:-/tmp/hero_clips_work}"
mkdir -p "$W"
UA="QuantumTeleportar-assetfetch/1.0 (CC0 asset research)"
[ -f "$W/ual1.zip" ] || curl -sS -A "$UA" -o "$W/ual1.zip" https://opengameart.org/sites/default/files/universal_animation_librarystandard.zip
[ -f "$W/ual2.zip" ] || curl -sS -A "$UA" -o "$W/ual2.zip" https://opengameart.org/sites/default/files/universal_animation_library_2standard.zip
mkdir -p "$W/u1" "$W/u2"
unzip -q -o "$W/ual1.zip" -d "$W/u1"
unzip -q -o "$W/ual2.zip" -d "$W/u2"
python3 -I tools/hero/build_clips.py "$W/u1/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb" "$W/u2/Universal Animation Library 2 [Standard]/Unreal-Godot/UAL2_Standard.glb" \
  ../art_sources/quaternius_universal_base_characters/Superhero_Male_FullBody.gltf "$W/hero_clips.json"
BIN="$(tools/get_godot.sh)"
"$BIN" --headless --path . --script tools/hero/bake_clips.gd -- "$W/hero_clips.json" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver"
