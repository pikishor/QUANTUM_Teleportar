# Quantum Teleportar — Unreal Engine 5 project

> **Status: uncompiled scaffold.** Written without access to Unreal Engine (it cannot run in the cloud sandbox this was authored in),
> so it has **never been compiled or run**. Expect a handful of small compile fixes on the first build.
> The gameplay it ports *was* tested in the Three.js prototype at the repo root.

## What is here
A UE5 C++ module that rebuilds the prototype's gameplay with **no authored assets** (engine primitives only), so it runs in an empty level:

| Class | Role |
|---|---|
| `AQTGameMode` | spawns the city, patrols and cores; Observation level (heat); score; respawn |
| `AQTCharacter` | third-person shooter pawn, hitscan rifle, headshots, recoil, reload |
| `UQTQuantumComponent` | Blink (Bell-pair beacon + teleport), Entangle (shared damage), Superposition (decoy → collapse blast) |
| `AQTDrone` | Observer drones: Sentinel / Striker / Heavy AI (patrol, chase, strafe, kamikaze) |
| `AQTProjectile`, `AQTCore` | drone bolts; the sector objective |
| `AQTCity` | procedural graybox city (instanced primitives) |
| `AQTPlayerController`, `AQTHUD` | keyboard/mouse + code-drawn touch overlay; canvas HUD and radar |

Not ported yet: vehicles and traffic, pickups, audio, real materials/VFX, UMG UI.

## Open it
1. Install Unreal Engine 5.5 (or edit `EngineAssociation` in `QuantumTeleportar.uproject`) plus Visual Studio (Windows) or Xcode (Mac).
2. Right-click `QuantumTeleportar.uproject` → *Generate project files*, open the solution/workspace, build the `QuantumTeleportarEditor` target.
3. Open the project, create an empty level (`File → New Level → Basic`), save it as `Content/Maps/QTSlice`, press **Play**.
   The game mode is already set as the project default (`Config/DefaultEngine.ini`); uncomment the two map lines there to make `QTSlice` the default.
4. Controls: WASD move, mouse aim, LMB fire, RMB zoom, Shift sprint, Space jump, **Q** blink, **E** entangle, **G** superposition, R reload.
   To preview the phone overlay in the editor, open the console and run `QTTouchUI 1`.

## Check the code without Unreal
`python3 unreal/tools/check_syntax.py` compiles every `.cpp` against a declaration-only stand-in for the engine API
(`unreal/tools/ue-stubs/UEStub.h`) using clang/g++ `-fsyntax-only`. It catches typos, missing members, wrong signatures and
float/double template mismatches, and was verified to fail on deliberately injected bugs. It runs anywhere with a C++ compiler.
**It does not prove the code builds against the real engine** — treat a pass as "no cheap mistakes", not "compiles".
Extend the stub when you use new engine APIs.

## Get a real compile without a local machine
Unreal can't be installed on a small CPU-only box, but Epic publishes official container images for CI.
See [docs/ci/unreal-compile.yml.example](../docs/ci/unreal-compile.yml.example). Prerequisites (all on your side):
link your GitHub account to an Epic Games account and accept the Unreal EULA (grants access to `ghcr.io/epicgames`),
and use a runner with a large disk (the image is tens of GB; standard hosted runners are too small).
That gives automated *compile* feedback. Seeing the game render needs a GPU machine (local or a rented cloud workstation).

## Package for phones
Needs the platform SDKs (Android Studio + NDK; Xcode on macOS for iOS). Verify the bundle id, orientation and signing in *Project Settings → Platforms*.

```bash
# Android (adjust the engine path)
RunUAT.sh BuildCookRun -project=QuantumTeleportar.uproject -platform=Android -clientconfig=Development \
  -cook -stage -pak -archive -archivedirectory=Build/Out -build
```

## Conventions for the team
- Keep gameplay in C++; keep tunable numbers in `FQTDroneSpec` etc. until they move to data assets.
- Binary assets (`.uasset`, `.umap`) need Git LFS or Perforce; decide before the first art check-in.
- Mobile budget first: set a target device, frame rate and memory ceiling, then profile on real hardware.
