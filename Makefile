# Convenience targets. CI runs the same scripts (see docs/DEPLOY.md).
.PHONY: setup test shot assets ios-project android-apk android-aab web

setup:            ## Godot binary (checksum verified) + export templates + project import
	godot/tools/bootstrap.sh --templates

test:             ## every headless Godot test
	@set -e; for t in godot/tests/test_*.gd; do godot/tools/test.sh tests/$$(basename $$t); done

shot:             ## software-rendered screenshot of the main scene
	godot/tools/shot.sh /tmp/qt-shot.png res://scenes/main.tscn 20

assets:           ## Python env + regenerate generated assets
	godot/tools/bootstrap.sh --assets

ios-project:      ## Xcode project (Linux or macOS)
	godot/tools/export_ios.sh

android-apk:      ## debug APK (needs ANDROID_HOME)
	godot/tools/export_android.sh apk

android-aab:      ## signed release AAB (needs ANDROID_HOME + keystore env, see docs/DEPLOY.md)
	godot/tools/export_android.sh aab

web:              ## Three.js prototype bundle
	npm ci && npm run build
