#!/usr/bin/env bash
# Look-dev viewer of the humanoid roster enemies (FoeHuman) on a slab (software Vulkan). From godot/:
#   tools/foe_view.sh /tmp/prefix ids=merc_rifle,auth_riot views=front3q,side,back [variants=0,1,2] [pose=aim] [lod=mid] [per=7] [dist=4]
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
OUT="$1"; shift
mkdir -p "$(dirname "$OUT")"
timeout "${VIEW_TIMEOUT:-280}" xvfb-run -a -s "-screen 0 ${VIEW_RES:-1280x720}x24" "$BIN" --rendering-driver vulkan --rendering-method mobile --resolution ${VIEW_RES:-1280x720} --path . res://tests/foe_viewer.tscn -- out="$OUT" "$@" 2>&1 | grep -v "^ALSA\|audio driver\|AudioDriver\|dummy driver\|leak\|^WARNING\|^   at\|backtrace\|^ERROR: .*RID" || true
