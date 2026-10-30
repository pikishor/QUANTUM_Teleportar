#!/usr/bin/env bash
# Export Android builds with the pinned Godot.
#   godot/tools/export_android.sh apk   debug-signed APK you can install on a phone  -> build/android/quantum-teleportar.apk
#   godot/tools/export_android.sh aab   signed release AAB for Google Play            -> build/android/quantum-teleportar.aab
# Needs ANDROID_HOME (see tools/setup_android_sdk.sh) and JDK 17. The AAB also needs, from the environment (CI secrets, see docs/DEPLOY.md):
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH, GODOT_ANDROID_KEYSTORE_RELEASE_USER, GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
# Optional: VERSION_NAME (e.g. 1.2.0) and VERSION_CODE (integer, must increase for every Play upload).
set -euo pipefail
MODE="${1:-apk}"
cd "$(dirname "$0")/.."
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[ -n "$ANDROID_HOME" ] || { echo "error: set ANDROID_HOME" >&2; exit 1; }
JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")}"
BIN="$(tools/get_godot.sh)"
tools/install_templates.sh

# Godot reads the SDK/JDK/debug keystore from its editor settings.
KS="${HOME}/.local/share/godot/debug.keystore"
if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")"
  keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore "$KS" -storepass android \
    -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12 >/dev/null
fi
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/godot"; mkdir -p "$CFG"
cat > "$CFG/editor_settings-4.6.tres" <<S
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_HOME"
export/android/java_sdk_path = "$JAVA_HOME"
export/android/debug_keystore = "$KS"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
S

# Optional version overrides (edit the workspace copy of the presets only).
if [ -n "${VERSION_NAME:-}" ]; then sed -i.bak "s|^version/name=.*|version/name=\"$VERSION_NAME\"|" export_presets.cfg; fi
if [ -n "${VERSION_CODE:-}" ]; then sed -i.bak "s|^version/code=.*|version/code=$VERSION_CODE|" export_presets.cfg; fi
rm -f export_presets.cfg.bak

mkdir -p build/android
case "$MODE" in
  apk)
    OUT="build/android/quantum-teleportar.apk"
    "$BIN" --headless --path . --export-debug "Android" "$OUT" ;;
  aab)
    : "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?set GODOT_ANDROID_KEYSTORE_RELEASE_PATH}"
    : "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:?set GODOT_ANDROID_KEYSTORE_RELEASE_USER}"
    : "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:?set GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD}"
    tools/install_android_template.sh
    OUT="build/android/quantum-teleportar.aab"
    "$BIN" --headless --path . --export-release "Android AAB" "$OUT" ;;
  *) echo "usage: $0 apk|aab" >&2; exit 2 ;;
esac
test -s "$OUT" || { echo "error: export produced no $OUT" >&2; exit 1; }
ls -la "$OUT"
