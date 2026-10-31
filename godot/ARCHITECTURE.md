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
- **Scratch files** (screenshots, helper scripts, notes) go only under `<scratchpad>/<your-module>/`. Several builders run at the same time and share the scratchpad root,
  where a helper script of the same name gets silently overwritten. Keep your own copy of anything you need there, never write to the root.
- **Check what `Write` says**: "updated" instead of "created" means the file already existed (someone else may own it). Stop and look before continuing.
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
- `--headless` has a dummy renderer: logic/physics tests only. Visual checks need `tools/shot.sh` / `tools/bot.sh` (software GL, slow: expect ~2–5 fps in the real city).
- **Integration:** `tests/test_integration.gd` boots `scenes/main.tscn` (world + atmosphere + player) headless and checks what no single-module test can: the controller against the
  real colliders (streets, walls, roofs, stepped ledges, the border), registry and quality fan-out, the hero's reflection, the FX pool, audio buses, respawn and node leaks.
  `tests/bot_integration.gd` is its visual twin: `tools/bot.sh res://tests/bot_integration.gd <prefix> 30 22` walks, sprints, jumps, aims, fires, climbs roofs, dies, switches
  tiers and explodes in the real city and prints draw calls, primitives, nodes, texture memory and the player's collider state per phase (`BOT_PHASES=0,9 BOT_QUALITY=2` select;
  `RENDERER=compat` works). Run it after any change that touches how modules meet.
- **Test and bot gotchas:** `Engine.time_scale` also multiplies the physics step (delta = `time_scale / physics_ticks_per_second`), so on its own it makes each tick coarser instead of the test faster; to
  run a headless test k times faster raise both, `time_scale = k` and `physics_ticks_per_second = 60 k` (the integration test uses k = 4), and keep waits in ticks of 1/60 s.
  `RenderingServer.frame_post_draw` never fires headless. To sample the camera where the renderer sees it, read it from a node with a late `process_priority` (the rig runs at 100): right after a
  physics tick the `SpringArm3D` has re-placed its child camera at the raw arm length. A bot run that quits within ~30 frames (one screenshot) can hang at exit while software Vulkan finishes
  queued shader compiles: take at least two.

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
- **Registry:** each module sets itself in `_ready()` (and clears the entry in `_exit_tree()` if it is still itself): `Game.world`, `Game.atmosphere`, `Game.player`, `Game.enemies`, `Game.vehicles`, `Game.missions`, `Game.camera`.
- **Graphics tier:** `Game.quality` (0 low, 1 medium, 2 high) is changed only through `Game.set_quality(level)`, which fans out to `Game.world.set_quality` and `Game.atmosphere.set_quality`
  and emits `Game.quality_changed`. `main.gd` applies it after composing the modules; tools take `--quality=N`. Modules that scale with the tier must be reachable from that one call.
- **Audio:** `assets/audio/default_bus_layout.tres` (registered in `project.godot`) defines Master (with a limiter), SFX and Music. `Sfx` plays every effect on SFX (16 voices + 8 positional)
  and the ambient loop on its own Music player 9 dB lower; `Sfx.play_music()` / `stop_music()`, `Sfx.muted` silences everything. `main.gd` starts the music for a real run, never under
  `Game.autostart` (tools, tests, bots). Positional sounds use `Sfx.play_at` (explosions do).
- **Visual layers:** layer 1 is everything; **layer 20 is reserved for the player's meshes** (the hero's key and rim lights use it as their cull mask so they never light the world).
- **Reflections of moving things:** the wet street reflects the city through geometry (the world's mirrored copy, node `Mirror`), and that copy contains only the static city. Anything dynamic
  that stands on the street (player, enemies, vehicles, pickups) must get its reflection with `MirrorProxy` (`scripts/world/mirror_proxy.gd`): `add_child(MirrorProxy.new())`, then
  `proxy.track(meshes)`. It shares the meshes, builds unshaded stand-in materials, follows the originals, hides with them and costs nothing on LOW. Never add colliders or lights to `Mirror`.
- **Effects pool:** `FX` emitters, tracers and blast lights are pooled, hidden while idle and cast no shadows (an idle pool costs no draw call). `FX.burst(pos, color, count, speed, life, gravity, size)`
  draws soft round sprites (`size` 1 = sparks, about 9 = fireball puffs); `FX.blast` is a hot core, a thin shock shell and a real light pulse; `Game.explode` combines them.
- **Pause:** pausing sets `Game.state = &"paused"` only. Never use `get_tree().paused`: rain, post-process and menu animation keep running behind the pause screen, and gameplay modules stop themselves by checking `Game.is_playing()`.
- **Input:** gameplay reads only InputMap actions: `move_forward move_back move_left move_right jump sprint fire aim reload blink entangle superpose interact pause`.
  Touch controls and bots drive them via `Input.action_press/release`. Camera look is pushed through `Game.player.camera_rig.add_look(yaw, pitch)` (radians).
- Scenes composed by `scripts/main.gd` if they exist: `scenes/world.tscn, atmosphere.tscn, player.tscn, enemy_manager.tscn, vehicle_manager.tscn, missions.tscn, hud.tscn`.

## Module contracts

### world — owns `scripts/world/**`, `scenes/world.tscn`, `assets/shaders/**`, `tests/*world*`
`class_name City` (root `Node3D` of world.tscn). Neon grid city: 8×8 blocks, 4 lots per block (footprints 18/26 m, heights 16/28/44/62/88 m, taller toward the centre,
10 % plazas), roads with dashes and neon curb strips, street lamps, ground, sky (procedural sky/stars/moon), `WorldEnvironment` (fog, glow/bloom, filmic tonemap) and a sun.
Port the layout rules from `../src/world.js`. Windows are drawn by a **spatial shader** (procedural lit/unlit window grid + emission), not textures, so thousands of windows cost nothing.
Static colliders on layer `world`; **rooftops must be walkable**. Draw calls must stay low (MultiMesh per building class). Measured on software Vulkan: LOW 29 / MED 48 / HIGH 52 draw calls
(the wet-reflection mirror pass is included; the MED budget in `BUDGETS.md` is 150).
API: `intersections: Array[Vector3]` (inner junctions, y=0) · `random_road_point() -> Vector3` · `road_point_near(center: Vector3, rmin: float, rmax: float) -> Vector3` (`Vector3.INF` if none) ·
`building_rects: Array[Rect2]` (x,z footprints, for the minimap) · `is_inside_building(p: Vector3) -> bool` · `sun: DirectionalLight3D` · `set_quality(level: int)` (0 low … 2 high: shadows/MSAA/render detail).
Extras: `ground_height(x, z, from_y) -> float` (roof/ledge/ground height under a point, matches the colliders) · `building_data` · `layout` · `stats() -> Dictionary` (instance and primitive counts per family).
Sets `Game.world = self`.
Facts other modules rely on:
- Buildings are stacks of parts with one `BoxShape3D` per part (410 shapes): roofs and setback ledges are walkable, and `is_inside_building` follows the crowns. Street props have **no colliders** by design;
  vehicles and the player collide with buildings, the ground and the border walls (x = ±350, z = ±350) only.
- Ground, roads and sidewalks are flat at y = 0; kerbs, manholes and markings are shader-only (no step geometry).
- Lanes: centres at ±5 m from the road centre, painted travel lanes 3.1–7.0 m from the centre, parking bays 7.0–9.4 m, stop lines 15 m from the junction centre. Use `intersections` / `road_point_near` for valid road positions.
- The city owns the viewport's `msaa_3d` and `scaling_3d_scale` (LOW renders at 0.7). **No other module may set those two properties**; scale your own effects by tier instead.
- The wet look reads the global shader parameters `wetness` and `rain` (defaults 0.8 / 1.0; below ~0.15 the city looks dry). Nothing may hide or reparent the world's `Mirror` node (the mirrored copy under the ground that makes reflections).
- The mirror reflects only the static city: dynamic objects get their reflection through `MirrorProxy` (see Conventions); `City.get_mirror_root() -> Node3D` is the node it uses.
  Dynamic objects (player, cars, drones) are also **not** lit by the baked lamp and neon pools; they need their own lights or an emissive trim to sit in the scene.
- Street props carry a faint cool night fill (`prop_core.gdshaderinc`), so near-black furniture keeps its form; there are no real lights in the world besides the moon.
- Sky and fog colours are sRGB on both sides (`Environment` colours and `source_color` uniforms); a module that tints either must use the same convention.
- The gameplay `Camera3D` far plane must be ≥ 1500 m (the far skyline reaches about 720 m, the ground fades out around 3 km).
- Glyphs on signs, screens and holograms are pseudo-script by design (no real lettering, no brands).

### atmosphere — owns `scripts/fx/atmosphere*.gd`, `scenes/atmosphere.tscn`, `assets/shaders/post_*.gdshader`, `tests/*atmosphere*`
`class_name Atmosphere` (root of atmosphere.tscn). The cinematic layer on top of the world: a full-screen **post-process** `CanvasLayer` (film grain, vignette, subtle chromatic aberration, colour grade
with lift/gamma/gain, optional light heat-haze; reads `hint_screen_texture`; must work in the Mobile renderer and degrade in Compatibility), **rain** (particles following `Game.camera`: streaks and ground splashes,
cheap enough for mid-range phones, density by quality tier), and the global shader parameters `wetness` and `rain` (see `Game._ready`; materials read them as `global uniform float wetness;`).
API: `set_quality(level: int)` (0 low … 2 high) · `set_weather(rain: float, wetness: float)` (0..1) · `enabled: bool` (post-process toggle for the settings screen). It never touches gameplay state and works without a world or player present.
`set_quality` scales rain and post-process cost only: the world owns the viewport's `msaa_3d` and `scaling_3d_scale`, so Atmosphere must not set them. The world's mirrored copy of the city (node `Mirror`) must not be hidden or reparented.
Registers itself as `Game.atmosphere` (and joins the group `atmosphere`); it receives its quality tier from `Game.set_quality(level)`, so no other module calls it for that.
LOW draws no ground splashes and no lens effects (its ground is matte); the splashes need `Game.world` (override: `rainfield.splashes_need_world = false`) and share the world's MED/HIGH
screen-texture copy, so they cost almost nothing extra. The world's ground shader draws its own slow ripples; the atmosphere's are small quick glints, the two do not compete.
Camera-facing rain follows `Game.camera`; the global shader parameters `wetness` / `rain` are registered by `Game._ready` and eased by `set_weather()`.

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
**As implemented (binding for HUD, vehicles, quantum and enemies):**
- Properties: `hp max_hp energy max_energy ammo mag reloading aiming sprinting spread vehicle camera_rig quantum speed_boost invuln since_hurt air_time yaw last_hit_time last_hit_kill last_hit_crit
  last_hurt_time last_hurt_from body weapon decals sparks`; methods `damage heal add_energy teleport_to get_aim chest_position reset is_dead spread_in_pixels(viewport_h)`;
  signals `hurt(amount) fired hit_confirmed(kill, crit)`. `CameraRig`: `add_look kick punch punch_fov bump reset_view snap look_at_point aim_at get_aim_forward get_aim_yaw get_ads_amount
  follow_target mode yaw pitch recoil_pitch mouse_sensitivity`.
- **Look input:** `CameraRig.add_look(yaw, pitch)` takes screen-space deltas in radians like `takeLook()` in the prototype: positive yaw turns the view RIGHT, positive pitch looks DOWN
  (finger or mouse moved right / down). The touch look zone passes raw drag deltas times its sensitivity (prototype: 0.0055 rad/px); mouse look (0.0022 rad/px, captured mouse) is handled
  inside the rig, so the HUD must not forward mouse motion. The gameplay camera keeps far = 2500 m (world contract: at least 1500 m).
- **HUD data:** `last_hit_time` / `last_hurt_time` use `PlayerUtil.now()` = `Time.get_ticks_msec() / 1000` (use the same call for "seconds since"). `Player.spread` is the CURRENT TOTAL half angle in
  radians (base + bloom + movement); `spread_in_pixels(viewport_height)` converts it for the crosshair. `last_hit_kill` is only true for enemies; a vehicle hit is never a kill.
- **Vehicles:** the player does NOT forward `interact`; `VehicleManager` polls it. To enter: `player.vehicle = vehicle` (the player hides, switches its collider off, follows the node every tick and
  the rig chases it; the vehicle root must rotate with the car, forward = -Z, and may expose a float `speed`). To exit: `teleport_to(pos)` then `player.vehicle = null`.
- **Quantum:** blink target from `player.get_aim()` (`hit` = first WORLD point, vehicles and enemies are ignored, 220 m far point if none), move with `player.teleport_to(pos)` (clears velocity, snaps
  body and camera, 9 degree FOV kick), `player.speed_boost = 1.3` while the clone lives (values below 1 are read as an additive bonus), `Player.rotation.y` is the body yaw.
- **Enemies:** a target implements `damage(amount, crit := false, mirrored := false)`, `center()`, a numeric `radius`, group `enemy`, and exposes `dead` (or hp <= 0, or frees itself) so kills and
  corpse pass-through work; `type == &"operative"` switches impacts to dust and armour chips (blood only behind `Game.graphic_violence`). A collider on the enemy layer (4) is optional: the
  rifle also ray-tests every `enemy` node's `center()` / `radius`. Damage to the player: `damage(amount, from_pos)` (`last_hurt_from` feeds a directional indicator).
- The player reacts to `Game.quality_changed` (LOW drops the rim light and the muzzle-flash light pulses) and owns a `MirrorProxy` for his reflection.
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
**Stop-gap already in place (orchestrator-owned, `scripts/ui/touch_controls.gd`, scene `touch_controls.tscn`, composed by `main.gd`):** on touchscreens (or with `--touch`) it draws a floating move stick (full push = sprint), a look drag (also from the FIRE finger), FIRE / AIM / JUMP / RELOAD buttons, crosshair with the weapon spread, hit marker, health bar, ammo and a perf readout (FPS, draws, triangles, texture memory; tap it to cycle the graphics tier). It only presses the input actions the keyboard drives and calls `CameraRig.add_look`. `tests/test_touch.gd` covers it. The HUD module replaces the look of it, keeps that input mapping, and may absorb the file. `project.godot` sets `emulate_mouse_from_touch=false`, so touches never fire the mouse-bound `fire` action.
**Camera field of view is horizontal** (`keep_aspect = KEEP_WIDTH`: hip 92, sprint 100, ADS 62 degrees), so 16:9 tablets and 20:9 phones see the same width. The `SpringArm3D` physics processing is off; the rig solves the arm once per rendered frame, so the weapon never aims from the raw arm end at 30 fps.
`scenes/hud.tscn` root `CanvasLayer`. Reads `Game.*` and `Game.player` only (no hard node paths). Contains: HUD (integrity/vehicle bar, coherence bar, ammo or km/h, heat stars, credits, objective + nearest core distance, centre message from `Game.message`, context hint when a vehicle is within reach (`interact`), hit marker, damage vignette, crosshair that tracks spread),
**minimap** (`Control` drawing roads/buildings from `Game.world.building_rects`, rotated so forward is up; drones, cars, pickups, beacon/clone, cores clamped to the rim), ability key hints with ready/active state,
**touch controls** (auto on touchscreens or `Game.force_touch`: floating left stick → `move_*` actions + sprint when fully pushed; right-half drag → `camera_rig.add_look`; buttons FIRE hold, JUMP, BLINK, LINK, SUPER, reload, AIM toggle, USE only near a vehicle; safe-area aware; multi-touch),
**screens**: title/menu (DEPLOY, graphics quality LOW/MED/HIGH → `Game.set_quality(level)`, which reaches the world and the atmosphere; persist the choice in `user://` and re-apply it at startup, plus a post-process toggle → `Game.atmosphere.enabled`, mute), pause (pause action / app focus loss), dead (DECOHERED → `Game.do_respawn()`), win (SECTOR STABILIZED → `Game.do_next_sector()`), best score persisted with `ConfigFile` in `user://`.
Menu → `Game.start_new_game()`. Pausing sets `Game.state = &"paused"` only (see the Pause rule in Conventions; modules already stop when not playing).
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
- **Status:** the committed models are still the first generation (tiling PBR textures, materials `Fabric Armor Gunmetal Glow Visor`, `Wheel Glass Trim`, ...). `tools/blender/README.md` documents the
  next generation (one baked atlas material per model: `Gear` / `Hull` / `Details` / `Glow`, real lights in the model, LOD tags), which `tools/build_assets.sh` produces once it has been run and
  reviewed. Consumers must therefore rely only on the node names and on `Body`, `Glow`, `Eye`, `Headlights`, `Taillights`, `Underglow`, never on the other material names (`PlayerBody` lifts `Fabric` only
  when it exists). Re-run `tests/bot_integration.gd` and `tests/test_integration.gd` after the rebuild.

## Behaviour numbers
Port from `../src/*.js` (they were play-tested): speeds, damages, costs, cooldowns, ranges, timings. When the JS and this document differ, this document wins.

## Wave 2A APIs as implemented (enemies, missions, HUD)
- **EnemyManager** (`Game.enemies`): `spawn(type, pos, aware=false, reinforce=false) -> Drone` returns null at the tier cap (`cap()`: LOW 5, MED 8, HIGH 12). `list` holds active enemies; dead ones leave group `enemy` immediately but stay in `list` with `dead = true` until released. Patrol groups beyond the cap stream in as dormant spots (`init_patrols()`, `patrol_groups()`) when the player is within 150 m and there is room. Types: `sentinel`, `striker`, `heavy` (Drone) and `operative` (rifleman). Bolts: one 48-slot MultiMesh. Enemies change state with `Game.heat += x; Game.quiet = 0.0`, `Game.score += n`, and drop via `Game.missions.drop(&"health"|&"energy", ground_pos)`.
- **Quantum hooks used by enemies**: `Game.player.quantum.clone` (Node3D) and `.collapse()`; `Game.enemies.get_clone()` is the cached lookup; `Drone.linked` marks quantum-linked drones. The quantum module is not built yet.
- **DynamicFill** (`scripts/common/dynamic_fill.gd`): `DynamicFill.apply(model, tint)` lifts dark legacy models (vehicles, pickups, cores); the single shared fill light comes from `DynamicFill.ensure_light(parent)` (EnemyManager creates it; off on LOW). A scene without an EnemyManager must call `ensure_light` itself.
- **Missions** (`Game.missions`): `cores` (dicts with `pos`, `node`, `got`), `pickups` (`pos`, `kind`, `t`), `got`, `total`, `nearest_core(pos) -> {pos, dist}` (`{}` if none), `drop(kind, pos)`, `new_round(n)`. Core within 4 m collects (+250, full energy); last core calls `Game.win()`. `next_sector` builds min(9, 6 + rounds) cores; `respawn` keeps cores.
- **HUD** (`scenes/hud.tscn`, instances touch controls; do not list `touch_controls.tscn` in `main.gd` MODULES). Reads `Game.missions`, `Game.enemies.list`, `player.quantum` (`has_beacon`, `beacon_pos`, `clone`, `links`, `cd_blink`, `cd_link`, `cd_super`, remaining seconds), and vehicles via `nearest(pos, r)` (null if none), `speed`, `hp`, `max_hp`. Pause sets `Game.state = &"paused"` only.
- Open: operatives/drones have colliders on layer 4 which the player's mask includes (they can block the player).
