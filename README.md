# Quantum Teleportar

Open-world sci-fi action game for iOS and Android: third-person shooter combat, a neon city to drive through,
and quantum powers built on real physics ideas.

**Status:** the production build is the **Godot 4** project in [`godot/`](godot/) (under construction — see
[godot/ARCHITECTURE.md](godot/ARCHITECTURE.md)). The Three.js game in `src/` is the playable, tested design reference.
See [docs/ROADMAP.md](docs/ROADMAP.md) for the path to a production-quality release and
[docs/RELEASE.md](docs/RELEASE.md) for the store-submission checklist.

## Build and deploy

Android and iOS builds run from GitHub Actions and everything is reproducible from a clean clone: see **[docs/DEPLOY.md](docs/DEPLOY.md)**
(secrets, one-time store setup, release flow, and what has been verified vs not). Quick start: `make setup && make test`.

## What is in this repo

| Folder | What | Status |
|---|---|---|
| `godot/` | **Production build**: Godot 4.6 (Mobile renderer, Compatibility fallback), GDScript, native Android/iOS export. Headless tests + screenshot/bot tooling. | in progress |
| `src/`, `android/`, `ios/` | Three.js prototype wrapped for mobile with Capacitor | playable, tested reference |
| `unreal/` | Unreal Engine 5 C++ scaffold ([details](unreal/README.md)) | uncompiled; parked until a GPU machine or Epic-linked CI exists |
| `prototypes/runner` | the original endless-runner prototype | archive |

### Godot quick start
```bash
cd godot
tools/import.sh                       # first run / after adding class_name scripts or assets
tools/test.sh tests/test_smoke.gd     # headless tests (exit code 0 = pass)
tools/shot.sh /tmp/out.png            # screenshot with software GL under xvfb
tools/bot.sh res://tests/bot_x.gd /tmp/seq 30 6   # scripted playthrough, screenshot sequence
```
The engine binary is downloaded from the official GitHub release on first use (`tools/get_godot.sh`).

## Gameplay

- **Third-person shooter:** hitscan rifle, headshots, reload, recoil/spread, zoom.
- **Open city:** 8×8 block neon grid, walkable rooftops, parked and moving traffic you can steal and drive.
- **Observation level (heat):** fight Observer drones and the level (★) rises, bringing sentinels, strikers and heavies.
- **Quantum powers**
  - **Blink (Q)** – throw a Bell-pair beacon, press again to teleport. The HUD shows Alice's two classical bits and
    the correction Bob applies (m1→X, m0→Z), as in the real teleportation protocol.
  - **Entangle (E)** – link two drones; damage to one is mirrored to the other.
  - **Superposition (G)** – leave a decoy that splits enemy fire, then collapse it into a damaging blast.
- **Objective:** recover the quantum cores marked by magenta beams.

## Controls

| | Desktop | Touch |
|---|---|---|
| Move / look | WASD / mouse | left stick / right-side swipe |
| Fire / zoom | LMB / RMB | FIRE / AIM |
| Jump / sprint | Space / Shift | JUMP / push stick fully |
| Blink / Entangle / Superpose | Q / E / G | BLINK / LINK / SUPER |
| Enter-exit car / reload | F / R | USE / ↻ |

## Develop

```bash
npm install
npm run dev        # desktop browser; add #debug to the URL to expose window.__qt
npm run build      # production bundle in dist/
```

## Ship to devices

```bash
npm run build && npx cap sync
npx cap open android   # Android Studio
npx cap open ios       # Xcode (macOS only)
```

Change `appId` in `capacitor.config.json` to your own reverse-DNS id before the first store upload.

## Layout

```
src/world.js      city generation, collision, raycasts
src/player.js     on-foot movement, shooting, third-person camera
src/enemies.js    Observer drone AI, bolts, reinforcements
src/vehicles.js   driving physics, traffic AI, enter/exit
src/quantum.js    blink / entangle / superposition
src/missions.js   cores and pickups
src/hud.js        HUD and minimap
src/input.js      keyboard, mouse and touch controls
prototypes/runner the original endless-runner prototype
```
