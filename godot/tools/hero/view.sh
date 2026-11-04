#!/usr/bin/env bash
# Look-dev viewer of the superhero on a plain floor (software Vulkan). From godot/:  tools/hero/view.sh /tmp/prefix views=front,side body=female ...
set -euo pipefail
cd "$(dirname "$0")/../.."
BIN="$(tools/get_godot.sh)"
OUT="$1"; shift
timeout 240 xvfb-run -a -s "-screen 0 1280x720x24" "$BIN" --rendering-driver vulkan --rendering-method mobile --resolution 1280x720 --path . res://tests/hero_viewer.tscn -- out="$OUT" "$@" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver\|leak\|^WARNING\|^   at\|backtrace" || true
