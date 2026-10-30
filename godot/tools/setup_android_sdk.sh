#!/usr/bin/env bash
# Ensure the Android SDK packages Godot 4.6.1 needs are installed (versions from the engine's own Android build template).
# GitHub's ubuntu runners already ship the SDK; on a fresh machine install the "Android command-line tools" first.
#   ANDROID_HOME=/path/to/sdk godot/tools/setup_android_sdk.sh
set -euo pipefail
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[ -n "$SDK" ] || { echo "error: set ANDROID_HOME to the Android SDK directory" >&2; exit 1; }
SDKM="$SDK/cmdline-tools/latest/bin/sdkmanager"
[ -x "$SDKM" ] || SDKM="$(command -v sdkmanager || true)"
[ -x "$SDKM" ] || { echo "error: sdkmanager not found (install the Android command-line tools)" >&2; exit 1; }
yes | "$SDKM" --licenses >/dev/null 2>&1 || true
"$SDKM" "platform-tools" "platforms;android-35" "build-tools;35.0.1" "ndk;28.1.13356709" "cmake;3.10.2.4988404"
echo "android sdk ready: $SDK"
