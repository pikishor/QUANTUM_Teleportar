# Roadmap: from vertical slice to a premium mobile release

This repo today is a **playable vertical slice** that proves the design (quantum powers, heat system, driving,
objectives) in Three.js. GTA-/CoD-class visual quality needs content and a native pipeline, not only code.

## What code can and cannot deliver
| Code and tooling (engineering) | Content (needs artists/vendors) |
|---|---|
| shooting, driving, AI, abilities, missions, UI | hero characters, weapons, vehicles, environments |
| netcode, backend, anti-cheat, live-ops | mocap/animation sets, facial animation |
| build/CI, tests, performance tuning | voice acting, music, sound design |
| store packaging and release tooling | VFX, UI art, trailers, key art |

## Engine decision (the biggest fork)
- **Current: Three.js in a WebView (Capacitor).** Fastest to iterate and test in a browser/CI, one codebase for both stores.
  Lower ceiling for fidelity, draw distance and physics on phones.
- **Native engine (Unity or Unreal).** Needed for console-adjacent fidelity: PBR materials, skinned/mocap characters,
  baked lighting, streaming worlds, mobile GPU profilers. Unity is the usual mobile choice; Unreal gives a higher visual ceiling at a
  larger build size and device floor. Requires the editor and (for iOS) macOS/Xcode.
- **Design carries over:** the mechanics, tuning values, level logic and test plans in this repo are the blueprint either way.

## Phases
1. **Pre-production** – lock engine, art direction, rating target, platform floor (min devices), monetization, single- vs multiplayer.
2. **Vertical slice (native engine)** – one district, one mission chain, final-quality character + weapon + vehicle, 60 fps on the target device.
3. **Production** – content pipeline, open-world streaming, mission/story content, audio, localization.
4. **Alpha/Beta** – device-farm QA, soft launch in a few regions, telemetry-driven balance.
5. **Launch and live-ops** – store featuring, seasonal content, support.

## Team roles to fill (typical for this scope)
Game director, technical director, gameplay/engine/online engineers, technical artist, art director, character/environment/vehicle artists,
animators (+ mocap vendor), VFX artist, level and mission designers, audio lead + composer, QA lead, producer, live-ops/analytics.
