#!/usr/bin/env bash
# Generate the iOS Xcode project from the Godot project. Works on Linux and macOS; building/signing needs macOS + Xcode (tools/ios_build.sh).
#   godot/tools/export_ios.sh            -> build/ios/QuantumTeleportar.xcodeproj
# Optional environment overrides (written into the workspace copy of export_presets.cfg only):
#   IOS_TEAM_ID  IOS_BUNDLE_ID  VERSION_NAME  VERSION_CODE
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(tools/get_godot.sh)"
tools/install_templates.sh
P=export_presets.cfg
[ -z "${IOS_TEAM_ID:-}" ]   || sed -i.bak "s|^application/app_store_team_id=.*|application/app_store_team_id=\"$IOS_TEAM_ID\"|" $P
[ -z "${IOS_BUNDLE_ID:-}" ] || sed -i.bak "s|^application/bundle_identifier=.*|application/bundle_identifier=\"$IOS_BUNDLE_ID\"|" $P
[ -z "${VERSION_NAME:-}" ]  || sed -i.bak "s|^application/short_version=.*|application/short_version=\"$VERSION_NAME\"|" $P
[ -z "${VERSION_CODE:-}" ]  || sed -i.bak "s|^application/version=.*|application/version=\"$VERSION_CODE\"|" $P
rm -f $P.bak
rm -rf build/ios; mkdir -p build/ios
"$BIN" --headless --path . --export-debug iOS build/ios/QuantumTeleportar.ipa 2>&1 | grep -v "^ALSA\|audio driver\|dummy driver" | tail -6 || true
test -d build/ios/QuantumTeleportar.xcodeproj || { echo "error: no Xcode project produced" >&2; exit 1; }
echo "Xcode project: $(pwd)/build/ios/QuantumTeleportar.xcodeproj"
