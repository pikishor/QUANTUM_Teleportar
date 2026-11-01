#!/usr/bin/env bash
# Release-readiness checklist. Read-only: validates export presets, version, icon, and (optionally) the size of built packages.
#   godot/tools/release/check_release_ready.sh                      checks the repo files
#   godot/tools/release/check_release_ready.sh --built DIR          also reports/validates *.apk and *.aab in DIR
#   SOFT_LIMIT_MB=1024 (APK soft target, default 1024)  STRICT=1 (warnings fail too)
# Exit 1 on any FAIL; warnings (WARN) exit 0 unless STRICT=1. Never prints secrets.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILT=""
if [ "${1:-}" = "--built" ]; then BUILT="${2:-}"; fi
P="$ROOT/export_presets.cfg"; G="$ROOT/project.godot"
LIMIT="${SOFT_LIMIT_MB:-1024}"
fails=0; warns=0
ok()   { printf '  [ OK ] %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; warns=$((warns+1)); }
fail() { printf '  [FAIL] %s\n' "$*"; fails=$((fails+1)); }
opt()  { # opt <preset-name> <key>: value of a key inside that preset's options section
  python3 -I - "$P" "$1" "$2" <<'PY'
import re,sys
path,name,key=sys.argv[1:4]
cur=None; opts={}; names={}
for line in open(path,encoding="utf-8"):
    line=line.rstrip("\n")
    m=re.match(r'\[(preset\.\d+)(\.options)?\]',line)
    if m: cur=(m.group(1),bool(m.group(2))); continue
    if cur and '=' in line:
        k,v=line.split('=',1)
        if not cur[1] and k=='name': names[v.strip('"')]=cur[0]
        if cur[1]: opts[(cur[0],k)]=v.strip('"')
pid=names.get(name)
print(opts.get((pid,key),"") if pid else "")
PY
}
echo "Quantum Teleportar release readiness"
echo
echo "Presets"
[ -f "$P" ] || { fail "export_presets.cfg missing"; exit 1; }
for n in "Android" "Android AAB" "iOS"; do
  [ -n "$(grep -F "name=\"$n\"" "$P")" ] && ok "preset '$n' present" || fail "preset '$n' missing"
done
AID="$(opt Android package/unique_name)"; BID="$(opt iOS application/bundle_identifier)"
[ "$AID" = "$(opt 'Android AAB' package/unique_name)" ] && ok "APK and AAB share package id $AID" || fail "APK and AAB package ids differ"
[ "$AID" = "$BID" ] && ok "Android and iOS ids match ($AID)" || warn "Android id '$AID' and iOS id '$BID' differ (allowed, but check it is intended)"
[[ "$AID" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]] && ok "package id format valid" || fail "package id '$AID' is not a valid Android id"
case "$AID" in com.example*|*godotengine*) fail "package id is a placeholder";; esac
echo
echo "Android architectures and permissions"
for pr in "Android" "Android AAB"; do
  [ "$(opt "$pr" architectures/arm64-v8a)" = "true" ] || fail "$pr: arm64-v8a must be on"
  for a in armeabi-v7a x86 x86_64; do [ "$(opt "$pr" "architectures/$a")" = "false" ] || fail "$pr: architectures/$a must be off (64-bit arm only)"; done
  [ "$(opt "$pr" permissions/internet)" = "false" ] || warn "$pr: INTERNET permission is on (the game collects no data and needs none; disclose it if you keep it)"
  for perm in camera record_audio read_external_storage write_external_storage vibrate; do
    [ "$(opt "$pr" "permissions/$perm")" != "true" ] || fail "$pr: unneeded permission $perm is on"
  done
done
ok "checked arm64-only and permission flags on both Android presets"
[ "$(opt 'Android AAB' gradle_build/use_gradle_build)" = "true" ] && ok "AAB uses the Gradle build (required for .aab)" || fail "AAB preset must set gradle_build/use_gradle_build=true"
[ "$(opt 'Android AAB' gradle_build/export_format)" = "1" ] && ok "AAB export_format=1" || fail "AAB preset export_format must be 1"
echo
echo "Version"
VN="$(opt Android version/name)"; VC="$(opt Android version/code)"
[[ "$VN" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]] && ok "version/name $VN" || fail "version/name '$VN' is not semver"
[[ "$VC" =~ ^[0-9]+$ ]] && [ "$VC" -ge 1 ] && ok "version/code $VC (CI overrides it with github.run_number; it must rise with every Play upload)" || fail "version/code '$VC' invalid"
[ "$VN" = "$(opt 'Android AAB' version/name)" ] && [ "$VC" = "$(opt 'Android AAB' version/code)" ] && ok "APK and AAB versions agree" || fail "APK and AAB versions differ"
IV="$(opt iOS application/short_version)"
[ "$IV" = "${VN%%-*}" ] && ok "iOS short version $IV matches" || warn "iOS short_version '$IV' differs from Android '$VN'"
echo
echo "iOS"
[ "$(opt iOS architectures/arm64)" = "true" ] && ok "arm64" || fail "iOS arm64 must be on"
MIN="$(opt iOS application/min_ios_version)"; ok "min iOS $MIN"
TEAM="$(opt iOS application/app_store_team_id)"
[ "$TEAM" = "ABCDE12345" ] && warn "iOS team id is the placeholder (CI overrides it from the IOS_TEAM_ID secret)" || ok "iOS team id set"
echo
echo "Display and textures"
ORI="$(grep -E '^window/handheld/orientation=' "$G" | cut -d= -f2)"
[ -n "$ORI" ] && ok "orientation=$ORI (4 = sensor landscape)" || warn "no orientation set in project.godot"
grep -q '^textures/vram_compression/import_etc2_astc=true' "$G" && ok "ETC2/ASTC texture import on" || fail "textures/vram_compression/import_etc2_astc must be true"
echo
echo "Icon"
ICON="$(grep -E '^config/icon=' "$G" | sed 's/.*"res:\/\/\(.*\)"/\1/')"
if [ -n "$ICON" ] && [ -f "$ROOT/$ICON" ]; then ok "project icon $ICON"; else fail "project icon '$ICON' not found"; fi
case "$ICON" in *.svg) warn "icon is an SVG; Godot rasterises it for Android/iOS, but a hand-made 1024x1024 PNG (no transparency for iOS) is recommended for the stores";; esac
echo
echo "Secrets (names only; values are never read here)"
for s in ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD; do
  if [ -n "${!s:-}" ]; then ok "$s present in this shell"; else printf '  [ -- ] %s not set in this shell (set it as a GitHub secret; see docs/RELEASE.md)\n' "$s"; fi
done
echo
echo "Package size (soft target: APK < ${LIMIT} MB)"
if [ -n "$BUILT" ]; then
  found=0
  for f in "$BUILT"/*.apk "$BUILT"/*.aab; do
    [ -f "$f" ] || continue; found=1
    mb=$(( ($(stat -c %s "$f" 2>/dev/null || stat -f %z "$f") + 1048575) / 1048576 ))
    case "$f" in
      *.apk) [ "$mb" -lt "$LIMIT" ] && ok "$(basename "$f"): ${mb} MB" || warn "$(basename "$f"): ${mb} MB is over the ${LIMIT} MB soft target";;
      *) ok "$(basename "$f"): ${mb} MB (Play AAB base-module download limit is 200 MB; larger games need Play Asset Delivery, see docs/RELEASE.md)";;
    esac
  done
  [ "$found" = 1 ] || warn "no .apk/.aab in $BUILT"
else
  echo "  (no --built DIR given; reporting source asset size instead)"
  if [ -d "$ROOT/assets" ]; then
    mb=$(( $(du -sk "$ROOT/assets" | awk '{print $1}') / 1024 ))
    [ "$mb" -lt "$LIMIT" ] && ok "assets folder: ${mb} MB (pack is usually smaller after VRAM compression)" || warn "assets folder ${mb} MB exceeds ${LIMIT} MB"
  fi
fi
echo
echo "Store documents"
REPO="$(cd "$ROOT/.." && pwd)"
[ -f "$REPO/docs/RELEASE.md" ] && ok "docs/RELEASE.md" || fail "docs/RELEASE.md missing"
[ -f "$REPO/docs/PRIVACY_POLICY_DRAFT.md" ] && ok "privacy policy draft present (needs the owner's legal review and a public URL)" || fail "privacy policy draft missing"
echo
echo "Summary: $fails failure(s), $warns warning(s)"
[ "$fails" -eq 0 ] && { [ "${STRICT:-0}" = 1 ] && [ "$warns" -gt 0 ] && exit 1; exit 0; }
exit 1
