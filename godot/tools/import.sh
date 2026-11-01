#!/usr/bin/env bash
# Re-import assets and rebuild the global class cache. Run after adding class_name scripts, .glb, .png or .wav files.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
timeout "${IMPORT_TIMEOUT:-1800}" "$BIN" --headless --path . --import 2>&1 | grep -v "^ALSA\|audio driver" || true
