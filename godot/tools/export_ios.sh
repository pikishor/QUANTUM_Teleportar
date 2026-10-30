#!/usr/bin/env bash
# Generate the iOS Xcode project from the Godot project. Works on Linux; building and signing the .ipa needs macOS + Xcode.
#   tools/export_ios.sh            -> build/ios/QuantumTeleportar.xcodeproj
# Before shipping: set application/app_store_team_id (placeholder ABCDE12345 in export_presets.cfg) and signing in Xcode/CI.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
tools/install_templates.sh
mkdir -p build/ios
"$BIN" --headless --path . --export-debug iOS build/ios/QuantumTeleportar.ipa 2>&1 | grep -v "^ALSA\|audio driver\|dummy driver" | tail -5 || true
test -d build/ios/QuantumTeleportar.xcodeproj
echo "Xcode project: $(pwd)/build/ios/QuantumTeleportar.xcodeproj"
