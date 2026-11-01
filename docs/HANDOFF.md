# Handoff: where the project stands and how to continue (written at the end of the cloud sessions)

Read this first, then `godot/ARCHITECTURE.md` (the binding module contracts and the "as implemented" sections) and `godot/BUDGETS.md`.
Everything described here is committed on `main` of https://github.com/pikishor/QUANTUM_Teleportar. Nothing important lives only in a cloud session.

## What the game is
**Quantum Teleportar**: a mature-rated (17+) open-world alien sci-fi third-person shooter for Android and iOS. Neo-Meridian, 2091: the Vael (a hive species from a collapsed quantum rift)
farm human "coherence" with bio-mechanical Observer drones. The player is **Kestrel**, a quantum-alien hybrid who teleports using the real teleportation protocol
(Bell pair, Alice's two classical bits, Bob's X and Z corrections). **ORACLE** is a half-corrupted AI voice in Kestrel's head. Goal: recover the quantum cores (rift anchors) in six escalating
sectors. Story data: `godot/scripts/story/story_data.gd` (82 radio lines, chapters, prologue/epilogue, death quotes); engine: `scripts/story/story.gd`.
Production build = **Godot 4.6.1 (GDScript)** in `godot/`. `src/` (Three.js) is the old tested design reference, `unreal/` a parked UE5 scaffold, `prototypes/` archive.

## Built and verified (commit history on main; last verified state = see `git log`)
World (8x8 neon city, wet reflections, streaming, pooled prop colliders), atmosphere (post-process, rain, weather), player (third person, camera rig, weapon, alien hero rig), enemies (3 bio-drones + Vael troopers,
EnemyManager, caps per tier, threat marks, telegraphs), missions (cores, pickups, win/next sector), HUD (bars, minimap, menus, pause/dead/win screens, phone layout), touch controls, quantum powers
(blink, entangle, superposition), vehicles and traffic, story layer, combat VFX, stability layer (watchdog, adaptive quality, error log, loading overlay), 19 headless test files, bots and screenshot tools.
**All 19 test files pass in a fresh clone** (`godot/tools/verify_clean_clone.sh`). GitHub CI (tests + screenshot + Unreal syntax + web build), the Android debug APK and the iOS unsigned device build were green.

## Resume locally (Mac or Linux)
```bash
git clone https://github.com/pikishor/QUANTUM_Teleportar && cd QUANTUM_Teleportar
make setup            # pinned Godot 4.6.1 (SHA-512 verified) + export templates + project import
make test             # all headless tests (about 5 minutes)
godot/tools/verify_clean_clone.sh   # clean-clone proof
cd godot && tools/import.sh         # after adding class_name scripts or assets
```
Open `godot/` in the Godot 4.6.1 editor to run the game (F5). On a real GPU (your Mac) the Mobile renderer runs natively, so you can finally profile for real.
Tools (all in `godot/tools/`): `test.sh tests/test_x.gd`, `bot.sh res://tests/bot_x.gd prefix every count` (scripted playthrough + screenshots; `QUALITY=0|1|2`, `RENDERER=compat`),
`shot.sh`, `vfx_check.sh` (deterministic explosion frames at fixed game time with `--fixed-fps 30`), `size_report.sh`, `pck_list.py`, `build_assets.sh` (Blender/numpy asset regeneration, needs `setup_python.sh`).
Useful flags after `--`: `--quality=N`, `--touch` (draw touch controls on desktop), `--perf` (FPS box), `--governor` (re-enable the auto quality governor in tools).
Build and deploy: `docs/DEPLOY.md` (GitHub Actions for Android/iOS, secrets list, phone install steps, signing setup). Store checklist: `docs/RELEASE.md`. Scope ladder: `docs/SCOPE.md`, `docs/ROADMAP.md`.

## Decisions made with the owner (do not re-litigate without asking)
- Engine: Godot 4 now, Unreal later (when an art team and a GPU build machine exist). Single branch: `main` (an old branch `claude/determined-bardeen-mvwr5u` can be deleted on GitHub).
- Install size ceiling 5 GB (BUDGETS.md): a ceiling, not a target. Today about 40 MB because everything is generated; gigabytes need real art, audio, voice and video.
- Direction: adult, gritty cyber-noir, alien cast; gore behind `Game.graphic_violence` (default off, aliens bleed green ichor); store rating undecided (Teen vs Mature).
- Quality bar: GTA 5 / Call of Duty feel on a phone. Honest state: independent art review scored the pre-wave-5 build 5.5/10 (atmosphere 8, lighting 7.5, composition 7, readability 5.5, VFX 4.5, characters 4, materials 4).
  Code-generated art has a ceiling; the next jump needs authored or licensed characters, textures (2K-4K), animation and audio. Node contracts let those drop in (see ARCHITECTURE.md assets section).
- Repo is public and MIT-licensed today; make it private and pick a proprietary license before a commercial release (docs/DEPLOY.md).
- Never paste keystores, certificates, passwords or API keys into chat or commits: GitHub encrypted secrets only.

## Owner's last phone test (Android debug build) and open bugs
The app installed. Reported: the screen got stuck on the main menu and after death, enemy attacks and car crashes (the world "lost the plot"). The stability wave fixed the causes found in the sandbox
(camera flung away by an integration step at low fps, 82% dark death overlay, explosion sprites at the lens, held input, chase camera on a destroyed car) and added a watchdog, adaptive quality, a loading
overlay and an on-device error log (long-press the FPS box). **Unverified on a device**: ask for the FPS box reading, whether DEPLOY responds and how the aliens and explosions look. Software rendering
in the sandbox cannot reproduce phone GPU behaviour.

## Prioritised backlog (from the independent reviews and integrators)
1. **Real-device profiling** (frame time, fill rate, shader hitches on first use). Fragment-heavy shaders: building (interior mapping), ground (screen-copy reflection), post. MED whole frame about 133-150 draws, 215-241k visible triangles (about 325k with shadow passes); killing 4 enemies at once spikes to 174-189 draws for about 0.8 s; Compat + touch peaks at 178 total.
2. **Character and enemy art**: hero is still a dark silhouette from the chase camera with thin tube limbs and jagged cloak hem; enemies smallish. Replace with authored/licensed rigged models (node contract in ARCHITECTURE.md) or keep improving `tools/blender/*`.
3. **Asset pipeline reproducibility**: `tools/build_assets.sh` from a clean clone with an empty HOME was never verified end to end; Blender env scripts (`ensure_bpy.sh` vs `setup_python.sh`) were not reconciled. Textures are 512 px; raise to 1K-2K ASTC where it shows. Baked-atlas path partly built (`atlas.py`, `shade.py`).
4. **Environment**: facades still boxy, repetitive signage, low roofs flat, near field dark, LOW tier looks dry; steam, haze and light shafts; far traffic/pedestrian impostors so the city is alive (nothing moves except rain and enemies).
5. **Combat feel**: real cover behaviour for enemies (prop colliders now exist), hit reactions/death animations for aliens, directional audio, reload/hit/death sounds (audio is synthesised; no recorded SFX, music or voice).
6. **Gameplay depth for "GTA"**: more mission types (not only cores), side activities, NPC pedestrians, police-style heat response, weapons/upgrades, save/load progress, tutorial.
7. **Release engineering**: signed Android AAB + Play upload and iOS signing/TestFlight need your secrets (docs/DEPLOY.md); store art, privacy policy, age rating, localisation, analytics, crash reporting.
8. Minor: HUD collisions with touch buttons on some aspect ratios, compat renderer darker than Mobile, test flake `test_stability` ("hurt effect recovers completely") seen once, headless dummy-renderer error noise.

## Wave 7 (integrated): living city, gameplay depth, audio, performance
- **Added:** far traffic (one MultiMesh, shader-driven) and a 100-person pooled crowd with flee-on-gunfire, airship searchlight patrol, dying signs and steam, facade depth and a lifted near field; six procedural contract kinds (officer, hack, chase, courier, survive, drones), pause-menu upgrade shop with reputation, ConfigFile save with Continue, skippable tutorial; about 190 synthesised audio files, a rewritten `Sfx` (pools, priorities, ducking, per-bus volume), adaptive 5-stem music, ambience; per-tier mesh LOD, shadow proxies, merged car lamps, shader pre-warm.
- **Integrator verification (software Vulkan, not a phone):** all 27 `tests/test_*.gd` pass; `PERF_CHECK=1 tools/perf_report.sh 0 1 2` OK (LOW 85 draws / 120k tris, MED 119 / 265k, HIGH 133 / 379k whole frame; 4-enemy death peak 99 / 141 / 153). `bot_full` at LOW/MED/HIGH: MED peaks 131 draws, 291k tris (desktop), 137 draws (touch). Compat MED 135 draws, death peak 151 (budget gate allows +15 there).
- **Fixed in integration:** `Sfx._step_quantum` / `_step_hero` threw about 1,100 script errors per test run when the hero or quantum node lacked `links`, `max_hp` or `hp` (stubs); now tolerant.
- **Open:** nothing was heard or run on a phone (audio levels, mix, frame times all unverified); no `siren.wav` (sirens silent); no HUD volume sliders and UI sounds unwired; Compat renders darker and sits near the 150-draw limit with touch; pedestrians and traffic do not interact with cars; LOW tier wet look only modestly better; car LOD generation at runtime may not work in export templates (check `ImporterMesh.generate_lods`); hero and enemy art is still procedural; `perf_report` is not in CI (needs xvfb); `fx_hpbar.gdshader` unreferenced.

## Working rules that paid off (keep them when using Claude Code locally)
- Contracts first: `ARCHITECTURE.md` is binding; modules own their files; shared files (`autoload/*`, `scripts/main.gd`, `project.godot`) are changed by one person at a time.
- Every module ships a headless test (`tests/test_*.gd`) and a bot; "done" = tests pass AND screenshots looked at. Run all tests before every commit.
- Software-rendered screenshots are slow (2-5 fps): capture time-sensitive effects with `--fixed-fps` (see `tools/vfx_check.sh`) and keep the auto quality governor off in tools (it is, under `Game.autostart`).
- Scratch files go in a per-module scratch dir, never the shared root; check that a `Write` says "created", not "updated".
- Multi-agent builds (if you use Claude Code workflows again): never message an agent that a workflow runs (it forks a duplicate that edits the same files); use small scoped agents, effort high for builders and medium for reviewers, at most about 20 screenshots each, no re-check rounds; measure token use after every wave.
- Cost reference: wave 1 used about 5.7M generated tokens; later waves were much leaner. The reasoning share of generated tokens was about 82% at maximum effort.

## Last-minute state (end of the cloud budget)
- Fixed: the hero showed as two bodies (one stationary) on the phone because the wet-street reflection copied the skinned model's rest-pose mesh. Skinned characters (hero, Vael troopers) are no longer reflected (`player_body.gd`, `operative.gd`; test updated). Re-adding a reflection that follows the animation is open.
- **Unfinished, stopped at the budget ceiling:** a movement-detail animation pass (foot planting, pelvis sway, spine counter-rotation, jump/land, aim, hit and death variants, secondary motion). The agent's partial work is committed (`scripts/characters/character_rig.gd`, `scripts/player/player_body.gd`, `scripts/enemies/operative.gd`, `tests/test_character_motion.gd`, `tests/bot_animation.gd`, `tools/anim_check.sh`) and all 19+ test files pass, but it was never reviewed visually and its foot-slide target (under 3 cm per stride) was not confirmed. Continue from `tools/anim_check.sh` and `tests/bot_animation.gd`.
- Known flaky check: `tests/test_stability.gd` "the hurt effect recovers completely" fails now and then (passes on rerun); make it frame-count based.

## Phone polish pass 2 (HUD density, Compat brightness, UI audio) - software renderer, nothing heard or run on a phone
- HUD: one priority line (contract else cores) under compact bars, minimap 148 px, radio subtitles in a narrow top-left plate that wraps/shrinks and shows whole words; checked 1280x720 and 1600x720 touch (hero, crosshair, buttons clear). `siren.wav` did exist (3 s one-shot); added a seamless `siren_loop.wav` on a follow emitter.
- Compat: `CityEnv.COMPAT_*` lifts ambient/exposure/glow; MED frame mean luma Mobile 0.205 vs Compat 0.202 (was 0.131; median 0.149 vs 0.121). Compat touch MED 139 draws, death 155 (gate +15), Mobile touch MED 124 draws / 266k tris, death 146.
- Audio: 8 new WAVs (UI cues + `siren_loop`), wired into HUD buttons, shop (deny/purchase/upgrade), contracts and touch USE; MUSIC/SFX sliders on the pause and title screens persist in `settings.cfg`. Levels are measured (peaks -15..-21 dBFS), not listened to.
- Open: slider feel and cue loudness on a real phone; the subtitle plate width on very narrow (< 16:9) screens; the tutorial prompt and quantum readout were not moved.
- Tests updated: test_hud_gameplay (contract replaces the objective line), test_hud/test_audio/test_ambient/test_story extended (sliders, cues, siren follow, subtitle wrap).


## Combat depth wave (four weapons, specialist enemies, cover, Overseer boss) - software renderer, nothing played on a phone
- **Added:** Rift Carbine / Shard Scatter / Pulse Lance (charged, piercing, sniper zoom) / Singularity Grenade (gravity well + collapse) with per-weapon ammo, keys 1-4, wheel, touch SWAP, shop purchase, pickups, saved unlock set and HUD weapon plate; shield trooper, flanker, sniper (0.8 s laser), brute (charge + slam) on the operative rig, cover behind pooled prop colliders, squad callouts with flank sides, the Vael Overseer contract at the end of sectors 3 and 6 (3 phases, boss bar, ORACLE lines, boss music state, unique drop). Details: ARCHITECTURE.md "Combat depth as implemented".
- **Verified (software Vulkan / GL compat, headless):** all 30 `tests/test_*.gd` pass including the new `test_weapons`, `test_enemy_types`, `test_boss`; `bot_combat2` (Mobile 6 phases, Compat 2) ran without script errors, MED peaks 102-128 draws / 237-288k primitives in the staged fights (budget 150 / 300k).
- **Not verified:** feel and balance on a phone (weapon numbers, charge time, boss HP, pulse timing are first guesses), audio (the new weapons reuse existing sounds with pitch changes, no new samples), the Overseer in a real street fight (the bot pictures show the boss bar and the ORACLE line but the body is lost in the marker beam), cover choice among the real city's props (tested on a stub world with boxes, the real `Colliders` pool only by its interface).
- **Known limits:** boss contract is offered but the sector can still be won without it (cores win as before); weapon pickups reuse a fallback pickup model; the lance does not damage cars much and the grenade ignores cover; no per-weapon upgrade levels (the six shop upgrades scale every weapon); snipers and brutes appear only from chapters 3 and 4.
- **Next:** tune on a device, give the boss a real model (spikes are a one-draw stand-in), add weapon sounds and a SWAP animation with a distinct hold pose, gate the sector win behind the boss if the owner wants it.

## Cinematics and presentation pass (intro, chapter and boss scenes, title backdrop) - software renderer, nothing run on a phone
- **Added:** `scripts/cinematics/` (`Cinematics` node, `CinePlan` shot data, `CineData` subtitles), `CameraRig.cine_set/cine_clear` (self-lapsing scripted pose), game state `cutscene`, 25 s skippable intro at the first DEPLOY, 6.5 s chapter orbit, Overseer intro and slow-motion defeat, animated title camera with drones, shop hero close-up, dead/win bars and fades, "CINE ON/OFF" setting.
- **Safety:** every scene ends through one `_end()` (camera, grade, hero, props, slow motion, state); Stability repairs a stuck `cutscene` state; tests `test_cinematic` (sequence, skip, interrupt by pause/death/menu, slow-motion restore, toggle, no node growth).
- **Open:** tune timings and the roof fly-through on a device (the camera may pass through taller buildings), the boss intro freezes the fight for 4.8 s by design, no voice or music cue per scene yet.

## Master plan after the owner added $400 (waves 12+; each wave: lean high-effort agents, integrate, verify in a fresh clone, push, Android build)
12 enterable interiors (shops, bars, lobbies, apartments, club, checkpoint; doors, transitions, vendors, interior missions) - 13 open-world scale (more districts with distinct palettes and props, bigger streaming map, landmarks, rooftop traversal, day/night and weather states) - 14 vehicles (8+ car models, bikes, hover cars, Vael patrol vehicles, denser LOD traffic, damage, chases, radio) - 15 humans and NPC life (10+ citizen models, schedules, vendors, dialogue, reactions, wanted system) - 16 art library (props, trim sheets, signage, 2K surfaces, baked high-poly detail) - 17 audio and music - 18 full campaign (8 chapters, scripted missions, cutscenes) - 19 device performance and release engineering (signed AAB, TestFlight pipeline) - 20 QA bots and soak tests. Real authored or licensed art remains the way past the procedural ceiling for characters.

## Phone-screenshot fixes + TEST MENU (device-fix pass, software renderer only, nothing run on a phone)
- Fixed from the screenshots: hero blown out to white (LOW bloom cap, darker LOW / Compat gear), world vanished (teleports and blinks clamped to valid ground, rescue of a lost hero, streaming refresh), camera inside hero and car (arm ignores cars / props, hero fades under 1.2 m), pedestrians in a straight file (lateral offsets, speed mix, idle groups). LOW perf: no post pass, no MSAA default, 111 model textures halved (204 -> 150 MB sandbox); the 30 FPS pin was never a cap (no max_fps / vsync override exists), it is vsync quantisation of a slow frame.
- TEST MENU (debug builds / `--test-mode` / saved setting): TEST button on title and pause, long-press the FPS box or F10; god, infinite ammo, one-hit, no heat, freeze, any weapon, credits, upgrades, sectors, contracts, boss, any enemy or car at the crosshair, teleports, weather, heat, kill all, skip, stats; 1-4 weapon buttons on screen. Code: `scripts/common/test_mode.gd`, `scripts/ui/test_menu.gd`.
- Tests: `test_device_fixes`, `test_testmode`; bots `bot_hero_luma` (hero luma gate per tier / renderer), `bot_testmenu`, `bot_texmem`. All numbers are sandbox numbers: please send an FPS box reading and a photo of the hero at LOW from the next debug build.
- Not done / open: time of day (none exists), the hero's armour still reads mid-blue rather than near-black in some lights, 60 FPS at LOW is a target that only a device can confirm (GPU-bound frame costs: building interior shader, bloom, 1400x630 render), enterable buildings and many more cars/people are the next art waves.

## Character depth pass (hero, trooper, citizens) - software renderer, nothing run on a phone
- **Models:** hero 17.8k / trooper 8.3k triangles (limits 18k / 12k), new silhouettes (layered pauldrons, gorget, collar, mantle, wider cloak, armour, joint rings, hands and grip; heavy plating and mandibles) with a sculpt-style high-poly bake (`tools/blender/hipoly.py`: subdivided and displaced source, per-texel ray bake of normal and cavity into the 2K atlases); `citizen.glb` (near 734 / far 251 triangles, six archetypes by vertex shader, vertex colours, one draw each) replaces the box crowd. Rebuild: `tools/blender/build_all.sh player operative citizen`, then `tools/import.sh`, `patch_imports.py`, `tools/import.sh`; byte-identical.
- **Verified:** test_assets, test_ambient, test_character_motion pass; `perf_report` MED staged 85 draws / 237k visible, 295k with shadow passes (the gate says 280k: the hero +3k and four troopers +11k with their shadow copies are the growth; crowd cost is small); looked at hero idle / game camera, trooper close-up and the citizen archetypes in a look-dev row.
- **Open:** hero legs and cloak still read thin from the chase camera at night; the trooper left pauldron was shrunk to pass the 1.1 m breadth test; the pose-following reflection exists (`SkinnedMirror`) and was not changed; no phone run.
