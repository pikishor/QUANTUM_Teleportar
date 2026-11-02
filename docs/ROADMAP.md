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

## Wave process (from wave 27, owner-approved)
- Builders: 2 low-effort agents, one narrow task each, each with a headless test.
- Integrator (low effort): tools/import.sh; run only the tests touching changed code plus the quick smoke set (test_smoke, test_integration, test_hud, test_touch, test_soak_quick); full suite runs in GitHub CI on push.
- Perf gate (PERF_CHECK=1 tools/perf_report.sh 0 1 2) only when a wave changes rendering (shaders, materials, models, lights, draw counts).
- Visual QA step after the integrator: tools/visual_qa.sh shoots ~12 fixed spots, numeric checks, contact sheet to docs/shots/latest.png; fix defects or list follow-ups.
- If CI turns red after a push, fix it before starting the next wave. Fresh-clone check + Android build every few waves.
- Owner feedback after each build: FPS reading, 1-2 screenshots, one line on feel.
