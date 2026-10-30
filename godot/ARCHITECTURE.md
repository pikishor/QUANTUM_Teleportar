# Quantum Teleportar — Godot 4 architecture and module contracts

Open-world sci-fi action game for iOS/Android. Third-person shooter + drivable neon city + quantum powers.
Engine: **Godot 4.6, Mobile renderer (Compatibility fallback)**, GDScript. This is the production build; the Three.js game in `../src/` is the
**tested behaviour reference** (numbers, rules, feel) and `../unreal/` is a later option.

## Direction (binding for every module)
- **Ambition and tone:** "not a small game": the scale, depth and polish of GTA 5 / Call of Duty, delivered on mobile. A grounded, cinematic sci-fi thriller, not
  cartoonish or toy-like. Enemies are human Observer Corp operatives (tactical gear, helmets, visors) plus industrial drones. **The store rating is not decided yet**
  (Teen vs Mature): hit reactions and impact effects are always on, but blood/gore-style effects sit behind `Game.graphic_violence` (default false until the rating is chosen)
  so the same build can ship in either rating or per region. No real-world brands, weapon licences or other IP.
- **Look, "cyber-noir realism":** night, rain, wet asphalt reflecting neon, haze and steam, grime and wear, subtle film grain + vignette + chromatic aberration,
  a graded palette (cool teal shadows, warm highlights, magenta/cyan neon used as *practical light sources*, not toy colour). Real scale (human about 1.8 m, car about 4.5 m),
  believable proportions, PBR-style materials (albedo/roughness/normal/AO from procedural textures), bevelled meshes with normal maps.
  Avoid flat saturated colours, chunky toy proportions and emoji-like UI. HUD: thin-line military/cyberpunk, condensed typography.
- **Renderer:** the Godot **Mobile renderer** (Vulkan on Android, Metal via MoltenVK on iOS) is the primary target, with automatic fallback to Compatibility.
  `tools/shot.sh` and `tools/bot.sh` use the Mobile renderer on software Vulkan (`RENDERER=compat` selects the OpenGL Compatibility renderer instead).
  Do not depend on Forward+-only features (SDFGI, volumetric fog, SSAO, SSR); fake them (fog layers, additive light shafts, shader tricks, baked probes).
  Verify in a screenshot that an effect really renders before relying on it.
- **Install budget up to 5 GB** (see `BUDGETS.md`): base package at most 200 MB plus store asset packs / in-game CDN downloads. Quality tiers LOW/MED/HIGH scale texture
  resolution, shadows, MSAA, particle counts and render scale, so mid-range phones still run well.
- **Asset repo policy:** commit the *scripts* that generate assets plus compact outputs (at most about 25 MB per module). Large outputs (4K PBR sets, audio libraries)
  are produced by `tools/build_assets.sh` into the git-ignored `assets/generated/` (or Git LFS once the team decides). Never commit multi-hundred-MB binaries.

## Reproducibility (binding): a clean clone must build everything
The owner deploys Android/iOS builds straight from GitHub (see `docs/DEPLOY.md`), so nothing may depend on one machine's hidden state.
- **No absolute or machine-specific paths** in any committed file (no `/tmp/...`, no home directories, no session scratch folders).
- **Committed outputs are what the game loads.** Models (`.glb`), compact textures and audio live in `assets/**` and the game runs from a clean clone *without* regenerating anything.
  Large intermediates go to the git-ignored `assets/generated/`, produced by `tools/build_assets.sh`.
- **Generators are reproducible:** fixed random seeds, pinned Python packages in `tools/requirements.txt` (Python 3.13, `bpy==5.2.3`), and the interpreter is found through
  `$BLENDER_PY` or `tools/setup_python.sh`, never a hard-coded path. Any new dependency is added to the requirements file and mentioned in `docs/DEPLOY.md`.
- **Tests run in CI:** every `tests/test_*.gd` is executed by `.github/workflows/ci.yml` through `tools/test.sh`, so each module ships at least one such test and keeps it green.
- Pinned engine and templates: `tools/get_godot.sh` and `tools/install_templates.sh` (SHA-512 verified). Bump versions only together with the checksums in `tools/verify_sha512.sh`.

## Working rules (read first)
- **Own only your module's files** (listed per module below). Never edit another module's files; if you need a change there, report it.
  Shared files (`autoload/*`, `scripts/main.gd`, `project.godot`, this document) are changed only by the orchestrator.
- **Everything must run without other modules and without art.** Use primitive meshes when `Game.load_model("x")` returns null,
  and guard references to other modules with `is_instance_valid(Game.player)` etc.
- **Every module ships tests** (`tests/test_<module>.gd`) that pass via `tools/test.sh`, and a bot (`tests/bot_<module>.gd`)
  that can be watched via `tools/bot.sh` screenshots. "Done" = tests pass AND you looked at screenshots and fixed what looked wrong.
- No per-frame allocations in hot paths (pool nodes, reuse vectors), no `print` spam. Typed GDScript where practical.
- Frame budget target: 60 fps on a mid-range phone → keep draw calls low (MultiMesh/instancing, merged meshes), no per-frame node creation.

## Tooling (run from `godot/`)
| Command | Purpose |
|---|---|
| `tools/import.sh` | **Run after adding any `class_name` script, `.glb`, `.png`, `.wav`** (rebuilds class cache + imports). Without it new `class_name`s fail to resolve. |
| `tools/test.sh tests/test_x.gd` | Headless test. The script `extends RefCounted` and defines `func run(host: Node)` (may `await`). Use `TestLib.check(cond, msg)` and `await TestLib.frames(host, n)`. Exit code 0 = pass. 60 s watchdog; a SCRIPT ERROR inside the test shows above the timeout message. |
| `tools/shot.sh out.png [scene] [frames]` | Render a screenshot (Mobile renderer on software Vulkan under xvfb; `RENDERER=compat` for OpenGL). `--headless` cannot render. |
| `tools/bot.sh res://tests/bot_x.gd /tmp/prefix [every] [count]` | Run a bot (`func step(t: float, delta: float) -> bool`; drive the game with `Input.action_press(&"move_forward")` etc.) and save `prefix_000.png…` every N frames. Look at the PNGs. |
- Autoloads are not visible to `-s` scripts, which is why tests run as a scene; inside tests/bots/modules use `Game`, `FX`, `Sfx` directly.
- `--headless` has a dummy renderer: logic/physics tests only. Visual checks need `tools/shot.sh` / `tools/bot.sh` (software GL, slow: expect ~5–15 fps).

## Conventions
- **Units:** metres, Y up, forward is **−Z** (so `Camera3D`/`Basis.looking_at` work naturally). City: `Game.PITCH=80`, `ROAD=20`, `N=8`, `HALF=320`, `LANE=5`, `Game.SPAWN=(-30,0,4)`.
- **Physics layers** (`collision_layer` values): world 1, player 2, enemy 4, vehicle 8, projectile 16, trigger 32 (`Game.L_*`).
- **Groups:** `player`, `enemy`, `vehicle`, `pickup`, `core`. Anything damageable joins its group and implements `damage(...)`:
  - Player: `damage(amount: float, from_pos := Vector3.ZERO)`
  - Drone: `damage(amount: float, crit := false, mirrored := false)`
  - Vehicle: `damage(amount: float)`
- **Services:** `FX.burst/tracer/blast/shake/make_beam/place_beam`, `Sfx.play(&"name")` / `Sfx.play_at(&"name", pos)`, `Game.say(text, seconds)`,
  `Game.add_heat(v)`, `Game.add_score(v)`, `Game.explode(pos, radius, opts)`, `Game.load_model(name)`.
  Sound names used by gameplay: `shot enemy_shot hit hurt boom blink link superpos pickup reload core` (files `assets/audio/<name>.wav`, optional).
- **State machine:** `Game.state` ∈ `menu play paused dead win`. Modules simulate **only while `Game.is_playing()`**.
  Lifecycle signals `Game.new_game / respawn / next_sector` tell every module to reset (see each module).
  `Game.autostart` is true under tests/bots/shots so the menu is skipped.
- **Registry:** each module sets itself in `_ready()`: `Game.world`, `Game.player`, `Game.enemies`, `Game.vehicles`, `Game.missions`, `Game.camera`.
- **Input:** gameplay reads only InputMap actions: `move_forward move_back move_left move_right jump sprint fire aim reload blink entangle superpose interact pause`.
  Touch controls and bots drive them via `Input.action_press/release`. Camera look is pushed through `Game.player.camera_rig.add_look(yaw, pitch)` (radians).
- Scenes composed by `scripts/main.gd` if they exist: `scenes/world.tscn, atmosphere.tscn, player.tscn, enemy_manager.tscn, vehicle_manager.tscn, missions.tscn, hud.tscn`.

## Module contracts

### world — owns `scripts/world/**`, `scenes/world.tscn`, `assets/shaders/**`, `tests/*world*`
`class_name City` (root `Node3D` of world.tscn). Neon grid city: 8×8 blocks, 4 lots per block (footprints 18/26 m, heights 16/28/44/62/88 m, taller toward the centre,
10 % plazas), roads with dashes and neon curb strips, street lamps, ground, sky (procedural sky/stars/moon), `WorldEnvironment` (fog, glow/bloom, filmic tonemap) and a sun.
Port the layout rules from `../src/world.js`. Windows are drawn by a **spatial shader** (procedural lit/unlit window grid + emission), not textures, so thousands of windows cost nothing.
Static colliders on layer `world`; **rooftops must be walkable**. Draw calls must stay low (MultiMesh per building class; budget ≤ ~40 for the whole city).
API: `intersections: Array[Vector3]` (inner junctions, y=0) · `random_road_point() -> Vector3` · `road_point_near(center: Vector3, rmin: float, rmax: float) -> Vector3` (`Vector3.INF` if none) ·
`building_rects: Array[Rect2]` (x,z footprints, for the minimap) · `is_inside_building(p: Vector3) -> bool` · `sun: DirectionalLight3D` · `set_quality(level: int)` (0 low … 2 high: shadows/MSAA/render detail).
Sets `Game.world = self`.

### atmosphere — owns `scripts/fx/atmosphere*.gd`, `scenes/atmosphere.tscn`, `assets/shaders/post_*.gdshader`, `tests/*atmosphere*`
`class_name Atmosphere` (root of atmosphere.tscn). The cinematic layer on top of the world: a full-screen **post-process** `CanvasLayer` (film grain, vignette, subtle chromatic aberration, colour grade
with lift/gamma/gain, optional light heat-haze; reads `hint_screen_texture`; must work in the Mobile renderer and degrade in Compatibility), **rain** (particles following `Game.camera`: streaks and ground splashes,
cheap enough for mid-range phones, density by quality tier), and the global shader parameters `wetness` and `rain` (see `Game._ready`; materials read them as `global uniform float wetness;`).
API: `set_quality(level: int)` (0 low … 2 high) · `set_weather(rain: float, wetness: float)` (0..1) · `enabled: bool` (post-process toggle for the settings screen). It never touches gameplay state and works without a world or player present.

### player — owns `scripts/player/**`, `scenes/player.tscn`, `tests/*player*`
`class_name Player` (`CharacterBody3D`, group `player`, layer `player`). Third-person over-the-shoulder shooter, strafe-style (body faces aim).
Child `CameraRig` (`class_name CameraRig`, `Node3D` with `SpringArm3D` + `Camera3D`; sets `Game.camera`): shoulder offset, ADS zoom, sprint FOV, recoil kick, shake from `FX.shake_amount`,
collision pull-in; `add_look(yaw: float, pitch: float)`; mouse look when the mouse is captured; `follow_target: Node3D` + `mode` (`&"foot"` / `&"vehicle"`) so a driven vehicle can be followed (chase camera that eases toward the vehicle heading unless the player is looking).
Hitscan rifle (30 rounds, reload 1.3 s, 0.11 s fire interval, 14 dmg / 30 on crit, spread grows with fire/movement, recoil). Ray from the **camera** through the crosshair (mask: world+enemy+vehicle); the muzzle tracer is drawn with `FX.tracer`.
Crit if the hit point is in the upper part of the target (`target.center()` + `target.radius`; targets expose them). Calls `target.damage(...)` per the damage contract.
Health 100, regen 14/s after 5 s without damage; energy 0–100 regenerating 8/s (3/s while driving).
API (properties): `hp max_hp energy max_energy ammo mag reloading aiming sprinting vehicle: Node3D (null on foot) camera_rig spread` ·
(methods) `damage(amount, from_pos := Vector3.ZERO)` · `chest_position() -> Vector3` · `heal(v)` · `add_energy(v)` · `teleport_to(pos: Vector3)` · `get_aim() -> Dictionary {origin: Vector3, dir: Vector3, hit: Vector3}` (camera ray result, `hit` = world point or far point) ·
signals `hurt(amount: float)`, `fired`.
Optional child: if `res://scripts/quantum/quantum.gd` exists, `Player._ready()` adds it as a child (`add_child(load(path).new())`) and exposes it as `player.quantum`.
Dies → `Game.die()`. Resets on `Game.new_game/respawn/next_sector` (position `Game.SPAWN`, full hp/energy/ammo, 1.5 s invulnerability).
When `vehicle != null` the player node is hidden, follows the vehicle position, does not move itself, and the camera uses vehicle mode. Visuals: model `Game.load_model("player")` else primitive body (legs swing while moving).
Sets `Game.player = self`.

### quantum — owns `scripts/quantum/**`, `tests/*quantum*`
`class_name Quantum` (`Node`, child of Player created by Player; talks to `get_parent() as Player`). Port `../src/quantum.js` exactly:
- **Blink** (`blink`, 15 energy, 0.3 s cd): first press throws a Bell-pair beacon at the aimed point (≤48 m, dropped to the floor/roof, 8 s life, visible pillar+rings); second press teleports there. Teleport shows
  `TELEPORTED · ALICE BITS m0m1 → BOB APPLIES …` (rule: m1→X, then m0→Z; no correction for 00). Not usable in a vehicle.
- **Entangle** (`entangle`, 25 energy, 0.8 s cd): aimed drone A (generous aim assist) + nearest unlinked drone B within 45 m get linked for 9 s: damage to one is mirrored to the other (`Drone.linked`); beam between them; both become aware.
- **Superpose** (`superpose`, 35 energy): leaves a hologram clone (6 s, `clone: Node3D`, in group `clone` so drones can target it); player gets +30 % speed (`player.speed_boost`) while it exists; pressing again, expiry, or the clone being hit collapses it:
  `Game.explode(clone_pos, 9, {enemy_dmg: 70, car_dmg: 40, player_dmg: 0, color: cyan})`, 1.5 s cd.
Props: `has_beacon`, `beacon_pos`, `clone`, `cd_blink cd_link cd_super`, `links`. Reads actions only while `Game.is_playing()`. Reset on lifecycle signals.

### enemies — owns `scripts/enemies/**`, `scenes/enemy_manager.tscn`, `tests/*enemies*`
`class_name Drone` (hovering Observer drone, group `enemy`, layer `enemy`) and `class_name EnemyManager` (`Node`, `Game.enemies = self`). Port `../src/enemies.js` and its `ENEMY` table (`sentinel`, `striker` kamikaze, `heavy` 3-round burst) and add the human type **`operative`** (Observer Corp rifleman, hp 80: takes cover behind building corners/cars found by raycasts, peeks and fires short bursts with tracers, flanks, calls for help, ragdoll/hit-react death with `Game.graphic_violence`-gated blood, humanoid model `Game.load_model("operative")` with primitive fallback). Sentinels/strikers/heavies are industrial drones, not toys.
Drone API: `damage(amount, crit := false, mirrored := false)` · `center() -> Vector3` · `radius: float` · `type: StringName` · `hp max_hp` · `aware: bool` · `linked: Drone` · `alert()`.
Behaviour: idle wander near home → aware (player within 32 m, or heat>0 within 80 m, or damaged; alerts neighbours within 35 m) → chase / back off / strafe at range, line-of-sight raycasts (throttled), target the player or the player's `clone` (50 %), dodgeable energy bolts
(pooled, 28–30 m/s), strikers explode on contact via `Game.explode`. Hit effects via `FX`; floating health bar when damaged. Death: score, `Game.add_heat`, energy refund to player, 30 % health / 30 % energy pickup via `Game.missions.drop(kind, pos)` if available.
Manager API: `spawn(type: StringName, pos: Vector3, aware := false, reinforce := false) -> Drone` · `clear(reinforcements_only := false)` · `init_patrols()` (7 groups of 2–3 sentinels, heavy for far groups, ≥110 m from spawn) ·
reinforcements while `Game.heat >= 1` (`floor(2 + heat*2.6)` alive within 110 m, spawn 38–75 m away on roads via `Game.world.road_point_near`, heavy from heat≥3, strikers 10 %) · heat decay (`Game.quiet` > 7 s → −0.12/s) · despawn reinforcements > 170 m away.
Resets on lifecycle signals. Visuals: `Game.load_model("drone_sentinel")` etc., else primitives.

### vehicles — owns `scripts/vehicles/**`, `scenes/vehicle_manager.tscn`, `tests/*vehicle*`
`class_name Vehicle` (group `vehicle`, layer `vehicle`) and `class_name VehicleManager` (`Node`, `Game.vehicles = self`). Port `../src/vehicles.js`: arcade physics (sedan/sport specs), parked cars + grid traffic AI (right-hand lanes, turns at junctions, stops for obstacles), carjacking (`+0.2` heat), enter/exit with `interact`,
collisions with buildings (bounce + damage + shake), ramming drones, explosion (`Game.explode`, 25 s respawn as parked).
API: `Vehicle.damage(amount)` · `speed: float` (signed m/s) · `hp max_hp` · `driver_is_player: bool` · `heading` · manager `toggle_enter_exit()` (called on `interact`, uses `Game.player`) · `nearest(pos: Vector3, r := 4.2) -> Vehicle` · `list: Array[Vehicle]`.
While driven: input actions `move_forward/back` throttle/brake, `move_left/right` steer, `jump` handbrake; sets `player.vehicle`; the Player's camera follows. Starter sport car near spawn. Resets on lifecycle signals. Visuals: `Game.load_model("car_sedan"/"car_sport")` else primitives.

### missions — owns `scripts/missions/**`, `scenes/missions.tscn`, `tests/*missions*`
`class_name Missions` (`Node`, `Game.missions = self`). Quantum cores on distinct inner junctions (≥140 m from spawn, ≥110 m apart; tall magenta beam visible from anywhere + gem + trigger radius 4 m, also triggered by a driven vehicle), pickups (`drop(kind: StringName, pos: Vector3)` kinds `health` +30 / `energy` +35, 40 s life, bobbing).
API: `cores: Array` · `got: int` · `total: int` · `rounds: int` · `new_round(total := 6)` · `drop(kind, pos)` · `nearest_core(pos: Vector3) -> Dictionary {pos: Vector3, dist: float}` (empty if none) · `pickups: Array`. Collecting a core: +250 score, full energy, `Game.say`, `Sfx.play(&"core")`. All cores → `Game.win()`.
Next sector: `min(9, 6 + rounds)` cores. Resets on lifecycle signals.

### hud / ui — owns `scripts/ui/**`, `scenes/hud.tscn`, `tests/*hud*`, `tests/*ui*`
`scenes/hud.tscn` root `CanvasLayer`. Reads `Game.*` and `Game.player` only (no hard node paths). Contains: HUD (integrity/vehicle bar, coherence bar, ammo or km/h, heat stars, credits, objective + nearest core distance, centre message from `Game.message`, context hint when a vehicle is within reach (`interact`), hit marker, damage vignette, crosshair that tracks spread),
**minimap** (`Control` drawing roads/buildings from `Game.world.building_rects`, rotated so forward is up; drones, cars, pickups, beacon/clone, cores clamped to the rim), ability key hints with ready/active state,
**touch controls** (auto on touchscreens or `Game.force_touch`: floating left stick → `move_*` actions + sprint when fully pushed; right-half drag → `camera_rig.add_look`; buttons FIRE hold, JUMP, BLINK, LINK, SUPER, reload, AIM toggle, USE only near a vehicle; safe-area aware; multi-touch),
**screens**: title/menu (DEPLOY, graphics quality LOW/MED/HIGH → `Game.world.set_quality`, mute), pause (pause action / app focus loss), dead (DECOHERED → `Game.do_respawn()`), win (SECTOR STABILIZED → `Game.do_next_sector()`), best score persisted with `ConfigFile` in `user://`.
Menu → `Game.start_new_game()`. Pausing sets `Game.state = &"paused"` and `get_tree().paused`-safe behaviour (modules already stop when not playing).
It also owns mouse capture: captured while playing on desktop, released in menu/pause/dead/win.

### assets — owns `assets/**` (except shaders), `tools/blender/**`
Blender-generated models (`bpy` runs headless: `$BLENDER_PY script.py`), exported **glb**, origin at ground contact, forward −Z, 1 unit = 1 m, emissive materials for glowing parts, realistic proportions and PBR-style materials (see Direction; normal-mapped, bevelled, weighted normals), each a visual only (no collision):
`player` (tactical operative, about 8-12k triangles, with separate `LegL`, `LegR` nodes pivoted at the hips and a `Muzzle` empty at the rifle tip), `drone_sentinel`, `drone_striker`, `drone_heavy` (hover rings/eyes emissive, `Eye` node), `car_sedan`, `car_sport` (body, cabin, wheels as separate nodes `WheelFL…`, headlight/taillight/underglow emissive),
`operative` (enemy human, same rig conventions as `player`), `pickup_health`, `pickup_energy`, `core_gem`, plus generated PBR texture sets for the city and props. Generated audio `assets/audio/*.wav` (numpy synthesis, 44.1 kHz mono 16-bit): the 11 SFX names above plus a looping `music_ambient.wav`.
Scripts live in `tools/blender/` and `tools/audio/` so everything is reproducible; commit the small outputs.

**Tested asset contract** (exact numbers and rebuild instructions: `tools/blender/README.md`; enforced by `tests/test_assets.gd`, 270 checks):
- All models: 1 unit = 1 m, origin at ground contact, front = -Z, no collision, **authored at final size: never scale them** (do not apply the prototype's `ENEMY.scale`).
  Textures are shared files in `assets/textures`, referenced by relative path; `.import` files are committed next to the assets.
- `player` / `operative` (1.82 m): children `Body`, `LegL` / `LegR` (origin at the hip joint, y = 0.93 m, swing about X) and `Muzzle` (Node3D at the rifle tip, about (0.12, 1.37, -0.92)). The model already faces -Z.
- Drones: `Body`, `RotorFL/FR/RL/RR` (origin at the hub, spin about local Y), an emissive `Eye`, and `Muzzle` (sentinel and heavy). Body centres at y = 0.95 / 0.82 / 1.40 m (sentinel / striker / heavy);
  hit radii 0.95 / 0.8 / 1.35 m.
- Cars: `Body` and `WheelFL/FR/RL/RR` (origin at the axle centre; steer by Y rotation, roll about X). Sizes: sedan 4.75 x 1.86 x 1.48 m, sport 4.45 x 1.92 x 1.20 m, SUV 4.85 x 1.98 x 1.83 m; wheel radius 0.335 / 0.335 / 0.385 m.
  Recolour by duplicating the surface material whose `resource_name == "Body"` and setting `albedo_color`. Emissive parts: `Headlights`, `Taillights`, `Underglow`, `Glow`.
- `pickup_health`, `pickup_energy`, `core_gem`: origin at ground level (pickups include a thin emissive ground ring); `core_gem` is 1.62 m tall with the crystal centred at 0.95 m. Bob or hover them by moving the root node.
- Emissive materials use `emission_energy_multiplier` above 1 so glow/bloom picks them up. Audio: `Sfx.play()` works as is; `music_ambient.wav` loops by itself, so give it its own player about 8-10 dB below the effects.
- Known limits: characters are procedural hard-surface models without a skeleton (animation is node-based); wet reflections are sky/light highlights because screen-space reflections do not exist in the Mobile renderer.

## Behaviour numbers
Port from `../src/*.js` (they were play-tested): speeds, damages, costs, cooldowns, ranges, timings. When the JS and this document differ, this document wins.
