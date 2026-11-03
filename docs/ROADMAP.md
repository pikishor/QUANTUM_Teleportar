# Roadmap to a AAA-feeling game (iteration plan, low-effort agents)

Honest limit: code-generated (procedural) art tops out around 5-6/10 next to GTA/CoD. Gameplay, feel, systems, audio and
polish can improve a lot with code alone. Real character/vehicle art (licensed packs or an artist) is the one thing code cannot replace.

Rules for every iteration (small, 1-2 agents, low effort): one focused change, a headless test, perf gate green, commit + push, no secrets.
Quantum theme rule: effects and names are plain (QUANTUM TELEPORT, SUPERPOSITION, ENTANGLE, COLLAPSE); no lessons, no
physics dialogue. Quantum is a gameplay verb set, not a lecture.

## Tracks (each wave = one small iteration; run tracks in rotation)
A Gameplay feel: A1 aim assist/hit feedback/recoil, A2 cover + vaulting + climbing, A3 melee/takedowns, A4 dodge/slide/sprint stamina,
  A5 hero abilities upgrade tree, A6 stealth + alert states, A7 combo/score multiplier, A8 difficulty options, A9 checkpoint/retry flow, A10 camera tuning.
B Quantum verbs (core identity): B1 QUANTUM TELEPORT (aim-targeted, trail, slow-mo), B2 SUPERPOSITION decoy clone, B3 ENTANGLE swap places
  with enemy/car/object, B4 COLLAPSE shockwave, B5 phase-through thin walls, B6 time-ghost rewind (short), B7 quantum grenade variants,
  B8 puzzle doors/terminals using verbs, B9 enemy counters (suppressor fields), B10 boss fights built around verbs.
C Weapons: C1 weapon feel (recoil patterns, sounds, muzzle), C2 8+ weapon classes, C3 attachments/mods, C4 alt-fire, C5 reload animations, C6 loot/shop/crafting, C7 weapon wheel UI.
D Enemies/AI: D1 squad tactics, D2 cover use + flanking, D3 12+ enemy types, D4 elites/minibosses, D5 aerial/drone enemies, D6 faction patrols in districts, D7 enemy readability.
E Vehicles: E1 handling tuning + drift, E2 vehicle weapons, E3 car customisation, E4 chases, E5 bikes/hover polish, E6 garage, E7 destruction.
F World: F1 enter ALL buildings (every door), F2 more interior variety (30+ layouts), F3 rooftops traversal, F4 districts landmarks, F5 day/night cycle, F6 weather states, F7 city events, F8 side activities.
G Player image: G1 hero silhouette/armour pass, G2 hero customisation (suits, colours), G3 first-person-ish aim camera polish, G4 animation set (cover, vault, takedown), G5 hero VFX (quantum glow).
H UI/options: H1 settings (controls, sensitivity, layout editor), H2 HUD redesign, H3 map + waypoints, H4 inventory, H5 accessibility, H6 localisation scaffolding.
I Content: I1 side missions x20, I2 collectibles, I3 achievements, I4 boss set pieces, I5 cutscene polish.
J Tech: J1 LOD + batching, J2 streaming, J3 Play Asset Delivery split, J4 PNG icon, J5 phone profiling from owner reports, J6 crash/ANR safety.

## Order
Wave 21 F1+B1, 22 G1+C1, 23 A1+D2, 24 B2+B3, 25 H1+H2, 26 E1+E2, 27 F2+F3, 28 C2+C3, then rotate tracks by owner feedback. Revisit after every owner test.

## Wave process (revised after the CI-red lesson; supersedes the earlier 'affected tests only' rule)
- Builders: 2 low-effort agents, one narrow task each, each with a headless test.
- Integrator (low effort): tools/import.sh, then the FULL suite in parallel: `godot/tools/test_all.sh` (3 jobs, retries a failure once and reports FLAKY vs FAIL). Never push with a FAIL. UI/text/layout waves also run test_hud*, test_touch*, test_options at 844x390 and 1280x720.
- Perf gate (PERF_CHECK=1 tools/perf_report.sh 0 1 2) only when a wave changes rendering (shaders, materials, models, lights, draw counts).
- Visual QA after the integrator: tools/visual_qa.sh, contact sheet docs/shots/latest.png; fix defects or list follow-ups.
- CI gate: after pushing, wait for the GitHub CI run of that exact commit to finish green BEFORE the next wave starts (never push two waves inside one CI run; pushes cancel earlier runs). If it is red, fix it first.
- Android build every few waves; fresh-clone check every ~6 waves.
- Owner feedback after each build: FPS reading, 1-2 screenshots, one line on feel.

## Plan for waves 53-100 (draft for owner review; revised after every owner test)
Done through wave 52 (in progress): abilities, weapons, enemies, vehicles, interiors, campaign, activities, events, accessibility, balance, sky/lighting.
Phase A, Look and phone fit (53-60)
- 53 Render resolution option (Balanced/High/Native + FSR upscaling), full-res maps on HIGH, restore 2K ORM where visible.
- 54 Character art integration #1: owner-supplied rigged hero/citizens via CharacterImport, quantum material pass.
- 55 Character art integration #2: enemies from owner packs, LODs, animation retarget polish, hit reactions.
- 56 Vehicle art integration: owner-supplied cars/bikes, wheel setups, damage states, paint.
- 57 Environment art integration: scanned PBR textures + HDR skies from owner packs, kit pieces for facades.
- 58 Visual consistency pass: palette, exposure, tone mapping, per-district look, QA contact sheets vs references.
- 59 Animation polish: locomotion blends, cover/vault, takedowns, facial/eye-lite, weapon handling.
- 60 First owner-device tuning round: use perf overlay reports to set tier defaults, fix hotspots.
Phase B, Content depth (61-75)
- 61-62 Campaign chapters 9-12 (sequel arc) with set pieces. 63 New district + 6 interiors. 64-65 20 more side missions with variety. 66 Heist missions. 67 Co-op-free companion AI ally. 68 Vehicle chase scenarios x6. 69 Stealth missions x4. 70 Boss rush + arena. 71 Collectible lore (text, no lectures). 72 Photo mode. 73 Replays/ghosts for races. 74 New Game+. 75 Content balance pass.
Phase C, Systems depth (76-88)
- 76 Skill tree (ability upgrades per verb). 77 Weapon crafting/mods. 78 Cover AI v2. 79 Squad tactics v2 and enemy factions. 80 Wanted/heat system v2 with patrol responses. 81 Dynamic economy events. 82 Property/safehouses. 83 NPC schedules v2 and dialogue barks. 84 Weather gameplay v2. 85 Day/night missions. 86 Radio shows (synth) and music director v2. 87 Haptics (vibration) and controller support. 88 Tutorial/onboarding v2 from playtest.
Phase D, Release hardening (89-100)
- 89 Play Asset Delivery split + AAB under limits. 90 Signed release pipeline dry run (owner secrets). 91 iOS build/TestFlight dry run (owner accounts). 92 Crash/ANR audit, soak 60 min. 93 Memory/thermal tuning, battery mode. 94 Accessibility audit + localisation QA. 95 Store assets: icon, screenshots, trailer capture mode. 96 Privacy/age-rating docs finalised with owner. 97 Fresh-clone + CI hardening, flaky test purge. 98 Beta build, owner feedback round. 99 Fix list from beta. 100 Release candidate.
Owner dependencies: character/vehicle/texture packs (54-57), device reports (60+), store accounts and secrets (90-91), legal review of privacy text (96).
