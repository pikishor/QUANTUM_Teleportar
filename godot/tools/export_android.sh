#!/usr/bin/env bash
# UNTESTED in the cloud sandbox (it cannot download the Android SDK from dl.google.com). Needs ANDROID_HOME (SDK with
# build-tools and platform-tools) and a JDK 17+. Writes the Godot editor settings the exporter needs, creates a debug keystore,
# then exports a debug APK.   ANDROID_HOME=/path/to/sdk tools/export_android.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ANDROID_HOME:?set ANDROID_HOME to your Android SDK}"
JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")}"
BIN="$(tools/get_godot.sh)"
tools/install_templates.sh
KS="$HOME/.local/share/godot/debug.keystore"
if [ ! -f "$KS" ]; then
  keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore "$KS" -storepass android \
    -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
fi
CFG="$HOME/.config/godot"; mkdir -p "$CFG"
cat > "$CFG/editor_settings-4.6.tres" <<E
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_HOME"
export/android/java_sdk_path = "$JAVA_HOME"
export/android/debug_keystore = "$KS"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
E
mkdir -p build/android
"$BIN" --headless --path . --export-debug Android build/android/quantum-teleportar.apk
ls -la build/android/quantum-teleportar.apk
