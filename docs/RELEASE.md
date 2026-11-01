# Release guide (Android Google Play + iOS App Store/TestFlight)

For the owner. Everything here is done by you in a store console or a terminal; the repository only holds workflows. **Never paste keystores, passwords, API keys or certificates into chat, issues, commits or files. They go only into GitHub encrypted secrets.** Nothing below is triggered automatically except by a `v*` tag or a manual workflow run.

Quick self-check any time: `godot/tools/release/check_release_ready.sh` (add `--built godot/build/android` after a build).
Related: `docs/DEPLOY.md` (secret reference), `docs/PRIVACY_POLICY_DRAFT.md`.

Identity used everywhere: package/bundle id `com.quantumteleportar.app` (cannot change after first publish; edit `godot/export_presets.cfg` before the first upload if you want another), name "Quantum Teleportar".

## 1. Accounts (one-time)
1. **Google Play Console**: https://play.google.com/console, one-time registration fee. Personal accounts created after Nov 2023 must run a closed test (12+ testers, 14 days) before requesting production access; plan for it.
2. **Apple Developer Program**: https://developer.apple.com/programs/ (annual fee). Create the app record in App Store Connect with the bundle id above.
3. Decide the publisher name and a support email; both show publicly.

## 2. Android signing (create the keystore locally)
Run on your own machine, in a folder outside the repository:
```bash
keytool -genkeypair -v -storetype PKCS12 -keystore upload.keystore -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
```
- When asked, use **the same password for keystore and key** (Godot accepts one password).
- **Back up `upload.keystore` and the password in a password manager plus an offline copy.** Never commit it.
- Use Play App Signing (default for new apps): this key is only the *upload* key; Google holds the real signing key, so a lost upload key can be reset via Play support.

Add the four secrets (web UI: repo *Settings, Secrets and variables, Actions, New repository secret*), or with the `gh` CLI (it prompts, so nothing lands in shell history):
```bash
base64 -w0 upload.keystore | gh secret set ANDROID_KEYSTORE_BASE64      # macOS: base64 -i upload.keystore
gh secret set ANDROID_KEYSTORE_PASSWORD     # paste when prompted
gh secret set ANDROID_KEY_ALIAS             # the alias, "upload" above
gh secret set ANDROID_KEY_PASSWORD          # same value as the keystore password
```
Optional, for automatic upload to the Play internal track: create a service account in Google Cloud, grant it access in Play Console (*Users and permissions*), and store its JSON as `PLAY_SERVICE_ACCOUNT_JSON`.

## 3. Versioning
- `versionName` (what users see) comes from the tag: tag `v1.0.0` gives `1.0.0`. Manual runs use `0.1.0-rc.<run>`.
- `versionCode` (integer, must rise on every Play upload) is the workflow's `github.run_number`; nothing to edit.
- Keep `godot/export_presets.cfg` `version/name` roughly in step for local builds. iOS: `short_version` = versionName, build number = run number.
- Release: `git tag v1.0.0 && git push origin v1.0.0` (or Actions, Android, Run workflow, tick *release*).

## 4. Building
- **Android** (`.github/workflows/android.yml`): the `android` job always builds the debug APK. The `release` job runs on tags or when *release* is ticked; it **skips cleanly when the four secrets are missing**, otherwise produces a signed `.aab` (upload to Play) and a signed release `.apk` (sideload/testers). Artifacts are kept only in private repositories (public-repo artifacts are world-downloadable); the keystore password and alias reach only the two export steps (step-level `env:`), never `GITHUB_ENV`, and the decoded keystore is deleted at the end of the job; `tests/test_release_workflows.gd` lints all workflows and release scripts for this; in a public repo, do the release build locally: export the four `GODOT_ANDROID_KEYSTORE_RELEASE_*` variables (see `godot/tools/export_android.sh`) and run it.
- **iOS** (`.github/workflows/ios.yml`, manual or tag): always exports the Xcode project and a compile check. The Xcode project artifact (`ios-xcode-project`) is kept while no signing secrets exist or the repository is private: with the signing secrets set the team and bundle ids are written into the project, and artifacts of a public repository are downloadable by anyone. With signing secrets and *release* it archives a signed `.ipa`; with App Store Connect secrets and *testflight* it uploads to TestFlight. Secret names are in `docs/DEPLOY.md` (`IOS_CERT_P12_BASE64`, `IOS_CERT_PASSWORD`, `IOS_PROVISION_PROFILE_BASE64`, `IOS_TEAM_ID`, `IOS_BUNDLE_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_API_KEY_ID`, `APPSTORE_API_PRIVATE_KEY`).
  Apple setup: create an *Apple Distribution* certificate (export as .p12 with a password), an *App Store* provisioning profile for the bundle id, and an App Store Connect API key (Users and Access, Integrations). Encode files with `base64 -i file | gh secret set NAME`.
- Known untested: signed AAB/APK and the signed iOS/TestFlight path have never run (no secrets existed). Expect to fix small things on the first real run; do a manual run before relying on a tag.

## 5. First upload
- Play: Console, Create app, Production later; first do **Internal testing**: upload the `.aab` (or let CI), add yourself as tester, install from the Play link, play 10 minutes.
- Apple: TestFlight build appears after processing; answer the export-compliance question (the game uses no non-exempt encryption: "No", or set `ITSAppUsesNonExemptEncryption` false).
- Check the size on the check script; the Play base module limit is 200 MB of download for the AAB, larger content needs Play Asset Delivery (not set up). If the AAB is rejected for size, that is the cause.

## 6. Store listing checklist
- [ ] App name (30 chars max on Play), short description (80), full description (4000), keywords (Apple, 100)
- [ ] Category: Games, Action
- [ ] Privacy policy URL (from `docs/PRIVACY_POLICY_DRAFT.md` after legal review)
- [ ] Support email, optional website
- [ ] Contact details, target audience (adults, not children), "does not contain ads" = yes
- [ ] Screenshots, icon, feature graphic, optional trailer (sizes below)
- [ ] Release notes, countries, price (Free or paid; no in-app purchases are wired up)
- [ ] Content rating questionnaire, data safety / privacy label, app access (no login needed)

## 7. Content rating answers (be honest; answer for the build you ship)
The game is a sci-fi third-person shooter against alien insectoid and robotic enemies, with a mature tone (docs/HANDOFF.md targets 17+/Mature).
- **Violence**: yes. Frequent shooting of alien creatures and bio-mechanical drones; some human characters exist in the story. Gore/blood effects are **off by default** (`Game.graphic_violence=false`); if the shipped build has no setting that turns them on, answer "no realistic blood/gore". If it can be enabled, say "mild/optional blood" and rate for that.
- Violence against human-like characters: answer per what the shipped build allows (enemies are aliens; if the player can shoot human NPCs, say yes).
- Sexual content/nudity: none. Profanity: answer per the radio/story lines (review `scripts/story/story_data.gd`). Drugs/alcohol/tobacco: none unless the story text mentions them. Gambling: none. User-generated content, chat, location sharing: none. Digital purchases: none.
- Expected outcomes: IARC roughly ESRB Teen/Mature 17+ and PEGI 16, Apple 12+/17+ depending on answers (Apple's questionnaire has "frequent or intense realistic violence" and "cartoon or fantasy violence" levels: choose "frequent/intense" cartoon-or-fantasy for this game and "none" for realistic if true). Do not under-answer; stores check and can pull the app.

## 8. Data safety (Google) and App Privacy (Apple)
The game collects no data and has no third-party SDKs that do (confirm before each release):
- Google Data safety: "No data collected", "No data shared", data not encrypted-in-transit question is not applicable (no network). Delete-data URL not needed.
- Apple App Privacy: "Data Not Collected". The generated Xcode project includes `PrivacyInfo.xcprivacy` (required-reason APIs); leave it, and review it if you add SDKs.
- If you later add crash reporting, analytics, ads or purchases, update both forms **and** the privacy policy before shipping.

## 9. Store asset sizes
Google Play: app icon 512x512 PNG (32-bit, <1 MB); feature graphic 1024x500 JPG/PNG; phone screenshots 2-8, 16:9 or 9:16, each side 320-3840 px (landscape 1920x1080 is fine); 7-inch/10-inch tablet screenshots optional (recommended for tablet visibility); optional YouTube trailer.
Apple App Store: icon 1024x1024 PNG, no transparency, no rounded corners; screenshots required at 6.9-inch iPhone (1320x2868 portrait or 2868x1320 landscape) and 13-inch iPad (2064x2752 / 2752x2064) when iPad is supported; 6.5-inch accepted as fallback (1284x2778 / 2778x1284); 1 to 10 each; optional app preview video 15-30 s.
(Sizes change; confirm in the consoles.) The project icon is `godot/icon.svg`; replace it with a designed 1024x1024 PNG before launch.

## 10. Before production
- [ ] Real-device test on a low/mid Android and an iPhone (perf gate `godot/tools/perf_report.sh` is only a desktop proxy)
- [ ] Privacy policy reviewed and live; forms match
- [ ] `check_release_ready.sh` shows no FAIL
- [ ] Play: closed testing requirement met if applicable; staged rollout (start 10-20%)
- [ ] Back up the keystore and all secrets elsewhere
