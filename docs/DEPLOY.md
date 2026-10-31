# Build and deploy: Android and iOS straight from GitHub

Everything needed to build the game lives in this repository. A fresh clone (or a fork) plus a few GitHub secrets is enough to produce
Android and iOS builds with GitHub Actions. Nothing depends on a particular machine.

## What runs where
| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | every push to `main`, pull requests, manual | Godot headless tests, screenshot smoke test, Unreal scaffold syntax check, Three.js prototype build |
| `android.yml` | tag `v*`, manual | debug **APK** (no secrets); with keystore secrets a signed **AAB**; optional upload to the Google Play internal track |
| `ios.yml` | tag `v*`, manual | Xcode project, unsigned device build (no secrets); with signing secrets a signed **.ipa**; optional TestFlight upload |

Release flow: `git tag v0.1.0 && git push origin v0.1.0`, or *Actions → Android / iOS → Run workflow*. Version numbers come from the tag
(`VERSION_NAME`) and the run number (`VERSION_CODE`, which must increase for every store upload).

## Reproduce everything from a clean clone
```bash
git clone https://github.com/pikishor/QUANTUM_Teleportar && cd QUANTUM_Teleportar
make setup          # pinned Godot 4.6.1 (SHA-512 verified) + export templates + project import
make test           # all headless tests
make shot           # software-rendered screenshot of the main scene
make assets         # optional: Python 3.13 venv (bpy 5.2.3, numpy) + regenerate generated assets
make ios-project    # Xcode project (Linux or macOS)
make android-apk    # needs ANDROID_HOME and JDK 17 (godot/tools/setup_android_sdk.sh installs the SDK packages)
```
Pinned toolchain: Godot `4.6.1-stable` (checksums in `godot/tools/verify_sha512.sh`), Android SDK 35 / build-tools 35.0.1 / NDK 28.1.13356709 / JDK 17
(taken from the engine's own Android template), Python 3.13 with `bpy==5.2.3` and `numpy==2.5.4` (`godot/tools/requirements.txt`).
Large generated texture sets are not committed; they are rebuilt by `make assets` (see `godot/BUDGETS.md` for the asset policy).

## One-time setup (yours; nothing here can be done from the repository)
### GitHub
Repository → *Settings → Secrets and variables → Actions → New repository secret*. Add only what you need; steps skip themselves when a secret is missing.

### Android (Google Play)
1. Create a Google Play Console developer account and an app whose package name matches `package/unique_name` in `godot/export_presets.cfg`
   (default `com.quantumteleportar.app`; change it to your own **before** the first upload, it cannot change later).
2. Create an upload key and keep the file safe (losing it is painful):
   ```bash
   keytool -genkeypair -v -keystore upload.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000
   base64 -w0 upload.keystore        # macOS: base64 -i upload.keystore
   ```
3. Upload the first AAB by hand in the Play Console (Google requires one manual release before the API works) and enrol in Play App Signing.
4. For automatic uploads: Google Cloud → create a service account, enable the Google Play Android Developer API, grant the account access to the app in *Play Console → Users and permissions*, and create a JSON key.

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | base64 of `upload.keystore` |
| `ANDROID_KEY_ALIAS` | `upload` (the alias you chose) |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore/key password |
| `PLAY_SERVICE_ACCOUNT_JSON` | the service account JSON (full text) |

### iOS (App Store / TestFlight)
You need the Apple Developer Program membership. A Mac is **not** required for these steps:
1. Register an App ID (bundle id, e.g. `com.yourcompany.quantumteleportar`) and create the app record in App Store Connect.
2. Create a Distribution certificate without a Mac:
   ```bash
   openssl genrsa -out ios_dist.key 2048
   openssl req -new -key ios_dist.key -out ios_dist.csr -subj "/emailAddress=you@example.com/CN=Your Name/C=US"
   # Apple Developer portal -> Certificates -> "Apple Distribution": upload ios_dist.csr, download distribution.cer
   openssl x509 -in distribution.cer -inform DER -out distribution.pem
   openssl pkcs12 -export -inkey ios_dist.key -in distribution.pem -out ios_dist.p12 -passout pass:YOUR_PASSWORD
   base64 -w0 ios_dist.p12
   ```
3. Create an *App Store* provisioning profile for the App ID, download it, and `base64 -w0 profile.mobileprovision`.
4. App Store Connect → *Users and Access → Integrations → App Store Connect API*: create a key; note the Issuer ID and Key ID and download the `.p8`.

| Secret | Value |
|---|---|
| `IOS_TEAM_ID` | your 10-character Apple Team ID (not secret, but kept here for one place to edit) |
| `IOS_BUNDLE_ID` | the bundle id from step 1 |
| `IOS_CERT_P12_BASE64` / `IOS_CERT_PASSWORD` | the base64 `.p12` and its password |
| `IOS_PROVISION_PROFILE_BASE64` | base64 of the `.mobileprovision` |
| `APPSTORE_ISSUER_ID` / `APPSTORE_API_KEY_ID` / `APPSTORE_API_PRIVATE_KEY` | from the API key (private key = full text of the `.p8`) |

Never paste any of these into chat, issues or commits. Only GitHub's encrypted secrets store holds them.

## Try a build on an Android phone (no store account needed)
1. GitHub -> *Actions* -> **Android** -> the latest green run -> *Artifacts* -> `android-debug-apk` (sign in to GitHub; it downloads as a zip).
2. Unzip it on the phone (or on a computer and copy it over) to get `quantum-teleportar.apk`.
3. Open the apk; Android asks once to allow *Install unknown apps* for the app you opened it from. Accept, install, open **Quantum Teleportar**.
4. Controls: left thumb = move (push to the rim to sprint), right thumb = look, FIRE / AIM / JUMP / R buttons.
   The box at the top left shows FPS (current, average, worst over the last second), draw calls, triangles and texture memory.
   **Tap that box to switch the graphics tier LOW / MED / HIGH.** Draw calls include about 35 for the on-screen controls.
5. What to send back: phone model, the three tiers' average and worst FPS while walking down a street and while sprinting, and anything that looks broken.

## Public or private repository? (decide before a commercial release)
This repository is currently **public and MIT-licensed** (see `LICENSE`). Anyone can read, copy and sell the code and the committed assets.
For a game you intend to sell, you will probably want a **private** repository and a proprietary license before release. Consequences to know about:
- GitHub Actions minutes are free for public repositories; for private ones the free plan includes a monthly allowance, and macOS runners count ten times
  (iOS runs only on tags and manual dispatch for that reason).
- Artifacts of public repositories are downloadable by any signed-in GitHub user, so the workflows upload **signed release builds as artifacts only when the repository is private**
  (they still go straight to Google Play / TestFlight when you enable publishing). Debug builds are always uploaded.
- Secrets are never exposed to pull requests from forks; only `ci.yml` runs on pull requests, and it uses no secrets.
Changing visibility or the license is your decision (repository *Settings → General → Danger Zone*); I will not change either.

## What is verified and what is not
The pipeline was built in a sandbox that cannot run the Android SDK or a Mac; GitHub's own runners were used to verify the Android and iOS builds.

| Part | Status |
|---|---|
| Pinned Godot download + SHA-512 verification (accepts the real file, rejects a tampered one) | verified |
| Project import, headless tests, software-rendered screenshots (sandbox and GitHub runner) | verified |
| Fresh-clone reproduction with an empty home directory | verified for the committed state at the time of testing |
| `ci.yml` on GitHub (Godot tests + screenshot, Unreal syntax check, web build) | verified (green) |
| **Android debug APK built on a GitHub runner** (`android.yml`, about 37 MB artifact) | **verified** |
| **iOS: Xcode project + unsigned arm64 device build on a macOS runner** (`ios.yml`) | **verified** |
| Android signed AAB (Gradle build), Play upload | **untested** (needs your keystore + Play secrets) |
| iOS signed .ipa, TestFlight upload | **untested** (needs your Apple certificate, profile and API key) |
| Workflow YAML linted with `actionlint` | not done (could not be installed in the build sandbox) |
| Installing and running the builds on a phone | **untested** (no device available to the build sandbox) |

Note on the iOS simulator: Godot 4.6.1's official iOS *simulator* library is Intel (x86_64) only, so the workflow checks an unsigned *device* build instead.

If a run fails, open the failed step's log; the scripts print what is missing (`ANDROID_HOME`, a secret, a template).

## Troubleshooting
- *"export templates missing"*: run `godot/tools/install_templates.sh` (the workflows cache them).
- *"Unable to open Android build-tools directory"*: `ANDROID_HOME` is wrong or `godot/tools/setup_android_sdk.sh` has not run.
- *Play rejects the upload*: `VERSION_CODE` must be higher than any previous upload; the package name must match the Play app.
- *iOS signing errors*: the bundle id, team id, certificate and provisioning profile must all belong to the same App ID and team.
- *macOS minutes are expensive on private repositories*: iOS runs only on tags and manual dispatch on purpose.
