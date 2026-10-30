# Scope ladder: from today's slice to a "GTA / Call of Duty–class" game

GTA V and the latest Call of Duty are the output of studios of hundreds of people over several years. Nobody ships that in one
step. This ladder splits the ambition into rungs that each ship, get tested and (from v1.0) sell before the next one starts.
Engineering (code, tooling, tests, builds) can be done by this repo's workflow; **content** (art, animation, voice, music, level and
story design) needs people or licensed assets, and is the main lever on "AAA look and feel".

## Rungs
| Rung | Goal | What it contains |
|---|---|---|
| **0. Vertical slice** (in progress) | Prove the loop and the tech | One neon city district (640 m), third-person shooter, 3 drone types, quantum powers (blink / entangle / superposition), driving and traffic, core-recovery objective, HUD + touch controls, generated models and audio |
| **1. v1.0 premium mobile release** | First store launch | 3–4 districts (~2 km), 8–12 story missions with scripted beats and a boss, 5 weapons + upgrades, 5–6 enemy types, day/night + weather, pedestrians/crowds, 3–4 vehicle classes, save/load, settings, localisation-ready UI, **final art pass**, voice-over + music, crash/analytics, store assets |
| **2. v1.5 retention** | Keep players | Progression and loadouts, daily/weekly challenges, leaderboards, optional co-op PvE, seasonal events |
| **3. v2.0 online** | The "Call of Duty" half | Matchmaking, dedicated servers, anti-cheat, ranked/casual modes, battle pass, live-ops tooling |
| **4. Engine migration (optional)** | Highest fidelity | Re-evaluate Unreal Engine 5 once an art team and a GPU build machine exist; design, tuning and tests carry over |

## Feature areas: GTA / CoD reference vs. where we are
| Area | Reference games | Today | v1.0 target |
|---|---|---|---|
| World | Huge streamed open world, interiors, day/night | 1 grid district | several districts, day/night, landmarks |
| Population | Pedestrians, traffic, factions | ambient traffic | pedestrians, crowds, ambient events |
| Missions / story | Authored campaign, cutscenes, VO | one collect-the-cores loop | 8–12 authored missions, cutscenes, VO |
| Combat | Many weapons, attachments, cover, enemy variety | 1 rifle, 3 drones | 5 weapons + upgrades, cover, 5–6 enemies, boss |
| Movement | Vaulting, sprint-slide, mounts | walk, sprint, jump | + vault/climb, slide |
| Vehicles | Cars, bikes, boats, aircraft | 2 cars | 3–4 classes with damage models |
| Progression | Economy, shops, unlocks | credits counter | upgrades, shops, unlock tree |
| Online | Persistent online world / multiplayer | none | none (v2.0) |
| Presentation | Mocap, facial animation, cinematic audio | generated low-poly models | hired art + animation + audio |

## Roles by rung (see ROADMAP.md for the full list)
- **0–1:** game director/producer, art director, 2–3 environment/prop artists, 1–2 character + vehicle artists, animator (+ mocap vendor), VFX/tech artist, sound designer + composer, narrative/mission designers, QA. Engineering can stay AI-assisted.
- **2–3:** add online/backend engineers, live-ops and analytics, community/support, anti-cheat.
