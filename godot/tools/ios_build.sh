#!/usr/bin/env bash
# macOS only. Build the exported Xcode project (run tools/export_ios.sh first).
#   godot/tools/ios_build.sh compile     unsigned build for real iPhones (arm64); proves the project compiles and links (no secrets needed)
#                                         (no simulator mode: Godot 4.6.1's official iOS simulator library is x86_64-only, so it cannot link on Apple-silicon runners)
#   godot/tools/ios_build.sh ipa         signed App Store .ipa -> build/ios/ipa/ (needs the secrets below, see docs/DEPLOY.md)
# ipa mode environment: IOS_TEAM_ID, IOS_BUNDLE_ID, IOS_CERT_P12_BASE64, IOS_CERT_PASSWORD, IOS_PROVISION_PROFILE_BASE64
set -euo pipefail
MODE="${1:-compile}"
cd "$(dirname "$0")/.."
PROJ="build/ios/QuantumTeleportar.xcodeproj"; SCHEME="QuantumTeleportar"
[ -d "$PROJ" ] || { echo "error: $PROJ missing; run tools/export_ios.sh" >&2; exit 1; }
case "$MODE" in
  compile)
    xcodebuild -project "$PROJ" -scheme "$SCHEME" -sdk iphoneos -configuration Release \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build ;;
  ipa)
    : "${IOS_TEAM_ID:?}" "${IOS_BUNDLE_ID:?}" "${IOS_CERT_P12_BASE64:?}" "${IOS_CERT_PASSWORD:?}" "${IOS_PROVISION_PROFILE_BASE64:?}"
    TMPD="$(mktemp -d)"; KC="$TMPD/build.keychain"; KCPW="$(uuidgen)"
    echo "$IOS_CERT_P12_BASE64" | base64 --decode > "$TMPD/cert.p12"
    security create-keychain -p "$KCPW" "$KC"
    security set-keychain-settings -lut 21600 "$KC"
    security unlock-keychain -p "$KCPW" "$KC"
    security import "$TMPD/cert.p12" -k "$KC" -P "$IOS_CERT_PASSWORD" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC" >/dev/null
    security list-keychains -d user -s "$KC" login.keychain
    echo "$IOS_PROVISION_PROFILE_BASE64" | base64 --decode > "$TMPD/profile.mobileprovision"
    security cms -D -i "$TMPD/profile.mobileprovision" > "$TMPD/profile.plist"
    PUUID="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$TMPD/profile.plist")"
    PNAME="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$TMPD/profile.plist")"
    mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
    cp "$TMPD/profile.mobileprovision" "$HOME/Library/MobileDevice/Provisioning Profiles/$PUUID.mobileprovision"
    ARCHIVE="build/ios/QuantumTeleportar.xcarchive"
    xcodebuild archive -project "$PROJ" -scheme "$SCHEME" -configuration Release -sdk iphoneos -archivePath "$ARCHIVE" \
      CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$IOS_TEAM_ID" PROVISIONING_PROFILE_SPECIFIER="$PNAME" \
      CODE_SIGN_IDENTITY="Apple Distribution" PRODUCT_BUNDLE_IDENTIFIER="$IOS_BUNDLE_ID"
    cat > "$TMPD/ExportOptions.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$IOS_TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>provisioningProfiles</key><dict><key>$IOS_BUNDLE_ID</key><string>$PNAME</string></dict>
  <key>uploadSymbols</key><true/>
</dict></plist>
P
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$TMPD/ExportOptions.plist" -exportPath build/ios/ipa
    security delete-keychain "$KC" || true
    ls -la build/ios/ipa ;;
  *) echo "usage: $0 compile|ipa" >&2; exit 2 ;;
esac
