# Quantum Teleportar — Godot 4 architecture and module contracts

Open-world sci-fi action game for iOS/Android. Third-person shooter + drivable neon city + quantum powers.
Engine: **Godot 4.6, Mobile renderer (Compatibility fallback)**, GDScript. This is the production build; the Three.js game in `../src/` is the
**tested behaviour reference** (numbers, rules, feel) and `../unreal/` is a later option.

## Direction (binding for every module)
- **Ambition and tone:** "not a small game": the scale, depth and polish of GTA 5 / Call of Duty, delivered on mobile. A grounded, cinematic sci-fi thriller, not
  cartoonish or toy-like. The hero ("Kestrel") is a tall, lean quantum-phased alien-human hybrid and the enemies are the alien Vael: chitinous insectoid troopers (game type `operative`) plus bio-mechanical drones (sentinel jelly, striker living bomb, heavy beetle gunship). **The store rating is not decided yet**
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
- **Effects pool (as implemented, VFX):** `FX` emitters, tracers, muzzle flashes and explosions are pooled, hidden while idle and cast no shadows (an idle pool costs no draw call).
  `FX.burst(pos, color, count, speed, life, gravity, size)` draws soft round sprites (counts scale with `Game.quality`: x0.5 / 0.8 / 1); `FX.blast(pos, radius, color, duration, style := -1, burn := 0.0)` plays one
  slot of `scripts/fx/explosion_pool.gd` (4 slots, LOW 2 / MED 3 / HIGH 4): a flipbook fireball billboard (`assets/textures/fx_flipbook.png`, 8x8 frames, made by `tools/make_fx_flipbook.py`, R fire / G smoke / B shading),
  1-3 rising smoke puffs, a flat ground flash with a shock ring (never a sphere), velocity-stretched spark streaks, falling debris, embers, ONE shared OmniLight3D pulse (not on LOW) and a heat-haze ripple
  (global shader uniform `fx_heat`, read by `post_film.gdshader`, MED and HIGH). Style is picked by colour and radius: cyan/magenta = quantum collapse (ripple ring, no smoke), radius >= 8 = car wreck that burns 6 s
  (`Game.explode` opts `burn`, `style` override). Fire and smoke fade with the camera distance relative to their size and towards the street, so a blast next to the player never whites the screen out; effects keep
  animating when the player is dead (nothing freezes on screen) and `FX.reset()` (also on new game / respawn / next sector) hides everything. `FX.tracer` has a bright-head shader and draws a star-and-cone muzzle flash
  at the shot origin (`FX.muzzle_flash`); `ImpactSparks.impact_world(pos, normal, surface := &"")` picks asphalt / glass / concrete / metal effects (`surface_at` guesses from the hit position). Tests: `tests/test_vfx.gd`,
  bot: `tests/bot_vfx.gd`.
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
`class_name Drone` (hovering Observer drone, group `enemy`, layer `enemy`) and `class_name EnemyManager` (`Node`, `Game.enemies = self`). Port `../src/enemies.js` and its `ENEMY` table (`sentinel`, `striker` kamikaze, `heavy` 3-round burst) and add the Vael infantry type **`operative`** (alien chitinous trooper, a Vael hive rifleman, hp 80: takes cover behind building corners/cars found by raycasts, peeks and fires short bursts with tracers, flanks, calls for help, ragdoll/hit-react death with `Game.graphic_violence`-gated blood, alien biped model `Game.load_model("operative")` with primitive fallback). Sentinels/strikers/heavies are industrial drones, not toys.
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
`player` ("Kestrel", alien-human hybrid, 6.6k triangles, limit 16k, ONE skinned mesh on a skeleton of rigid bones, see "Characters as implemented"), `drone_sentinel`, `drone_striker`, `drone_heavy` (living drones: `Body`, `Fins`, emissive `Eye`), `car_sedan`, `car_sport` (body, cabin, wheels as separate nodes `WheelFL…`, headlight/taillight/underglow emissive),
`operative` ("Vael trooper", chitinous insectoid biped, same rig conventions as `player`), `pickup_health`, `pickup_energy`, `core_gem`, plus generated PBR texture sets for the city and props. Generated audio `assets/audio/*.wav` (numpy synthesis, 44.1 kHz mono 16-bit): the 11 SFX names above plus a looping `music_ambient.wav`.
Scripts live in `tools/blender/` and `tools/audio/` so everything is reproducible; commit the small outputs.

**Tested asset contract** (exact numbers and rebuild instructions: `tools/blender/README.md`; enforced by `tests/test_assets.gd`, 270 checks):
- All models: 1 unit = 1 m, origin at ground contact, front = -Z, no collision, **authored at final size: never scale them** (do not apply the prototype's `ENEMY.scale`).
  Textures are shared files in `assets/textures`, referenced by relative path; `.import` files are committed next to the assets.
- `player` (Kestrel, 1.97 m with the crest) / `operative` (Vael trooper, 1.74 m hunched, tail and rifle reach 2.5 m front to back): an articulated model, ONE skinned `Body` mesh (1 draw call, one atlas material `Gear`, 6.6k / 4.8k triangles) under `Rig/Skeleton3D`, plus root empties `Muzzle` (rifle tip, about (0.12, 1.43, -1.05) hero, (0.14, 1.33, -1.2) trooper), `WristL`/`WristR`, `MagWell`, `MagPouch` and the `Fill`/`Rim` lights. Bones (rest rotation identity, model axes, origin = pivot): `Hips > Torso > Head, UpperArmL/R > ForeArmL/R, Rifle`, `Hips > ThighL/R > ShinL/R > FootL/R`, plus the optional secondary chain `Sec1 > Sec2 > Sec3` (hero: phase cloak on the Torso; trooper: tail on the Hips). The model faces -Z; `scripts/characters/character_rig.gd` poses it. See "Characters as implemented".
- Drones (3 surfaces: `Body` and `Fins` share one baked `Hull` atlas, `Eye` is a flat emissive material the game recolours): `Body`, `Fins` (origin on the body axis; the sentinel's frill of tendrils turns about Y and pulses like a jelly, the striker's ring of thorns spins about its long Z axis and flares before it bursts, the heavy's skirt of hover cilia turns about Y; `Drone._animate`, table `Drone.FIN_ANIM`), `Eye`, and `Muzzle` (sentinel proboscis and heavy bio-cannon). The primitive stand-in keeps `RotorXX` nodes and `Drone` still spins any it finds. Body centres at y = 0.95 / 0.82 / 1.40 m (sentinel / striker / heavy);
  hit radii 0.95 / 0.8 / 1.35 m.
- Cars: `Body` and `WheelFL/FR/RL/RR` (origin at the axle centre; steer by Y rotation, roll about X). Sizes: sedan 4.75 x 1.86 x 1.48 m, sport 4.45 x 1.92 x 1.20 m, SUV 4.85 x 1.98 x 1.83 m; wheel radius 0.335 / 0.335 / 0.385 m.
  Recolour by duplicating the surface material whose `resource_name == "Body"` and setting `albedo_color`. Emissive parts: `Headlights`, `Taillights`, `Underglow`, `Glow`.
- `pickup_health`, `pickup_energy`, `core_gem`: origin at ground level (pickups include a thin emissive ground ring); `core_gem` is 1.62 m tall with the crystal centred at 0.95 m. Bob or hover them by moving the root node.
- Emissive materials use `emission_energy_multiplier` above 1 so glow/bloom picks them up. Audio: `Sfx.play()` works as is; `music_ambient.wav` loops by itself, so give it its own player about 8-10 dB below the effects.
- Known limits: wet reflections are sky/light highlights because screen-space reflections do not exist in the Mobile renderer.
- **Status:** the committed models are still the first generation (tiling PBR textures, materials `Fabric Armor Gunmetal Glow Visor`, `Wheel Glass Trim`, ...). `tools/blender/README.md` documents the
  next generation (one baked atlas material per model: `Gear` / `Hull` / `Details` / `Glow`, real lights in the model, LOD tags), which `tools/build_assets.sh` produces once it has been run and
  reviewed. Consumers must therefore rely only on the node names and on `Body`, `Glow`, `Eye`, `Headlights`, `Taillights`, `Underglow`, never on the other material names (`PlayerBody` lifts `Fabric` and, for the articulated model, `Gear` only
  when it exists). Re-run `tests/bot_integration.gd` and `tests/test_integration.gd` after the rebuild.

## Behaviour numbers
Port from `../src/*.js` (they were play-tested): speeds, damages, costs, cooldowns, ranges, timings. When the JS and this document differ, this document wins.

## Wave 2A APIs as implemented (enemies, missions, HUD)
- **EnemyManager** (`Game.enemies`): `spawn(type, pos, aware=false, reinforce=false) -> Drone` returns null at the tier cap (`cap()`: LOW 5, MED 8, HIGH 12). `list` holds active enemies; dead ones leave group `enemy` immediately but stay in `list` with `dead = true` until released. Patrol groups beyond the cap stream in as dormant spots (`init_patrols()`, `patrol_groups()`) when the player is within 150 m and there is room. Types: `sentinel`, `striker`, `heavy` (Drone) and `operative` (rifleman). Bolts: one 48-slot MultiMesh. Enemies change state with `Game.heat += x; Game.quiet = 0.0`, `Game.score += n`, and drop via `Game.missions.drop(&"health"|&"energy", ground_pos)`.
- **Quantum hooks used by enemies**: `Game.player.quantum.clone` (Node3D) and `.collapse()`; `Game.enemies.get_clone()` is the cached lookup; `Drone.linked` marks quantum-linked drones. The quantum module is built, see "Quantum as implemented".
- **DynamicFill** (`scripts/common/dynamic_fill.gd`): `DynamicFill.apply(model, tint)` lifts dark legacy models (vehicles, pickups, cores); the single shared fill light comes from `DynamicFill.ensure_light(parent)` (EnemyManager creates it; off on LOW). A scene without an EnemyManager must call `ensure_light` itself.
- **Missions** (`Game.missions`): `cores` (dicts with `pos`, `node`, `got`), `pickups` (`pos`, `kind`, `t`), `got`, `total`, `nearest_core(pos) -> {pos, dist}` (`{}` if none), `drop(kind, pos)`, `new_round(n)`. Core within 4 m collects (+250, full energy); last core calls `Game.win()`. `next_sector` builds min(9, 6 + rounds) cores; `respawn` keeps cores.
- **HUD** (`scenes/hud.tscn`, instances touch controls; do not list `touch_controls.tscn` in `main.gd` MODULES). Reads `Game.missions`, `Game.enemies.list`, `player.quantum` (`has_beacon`, `beacon_pos`, `clone`, `links`, `cd_blink`, `cd_link`, `cd_super`, remaining seconds), and vehicles via `nearest(pos, r)` (null if none), `speed`, `hp`, `max_hp`. Pause sets `Game.state = &"paused"` only.
- Open: operatives/drones have colliders on layer 4 which the player's mask includes (they can block the player).

## Quantum as implemented (`scripts/quantum/quantum.gd`, tests `tests/test_quantum.gd`, visual bot `tests/bot_quantum.gd`)
- `class_name Quantum` (`Node`), created by `Player._attach_quantum()` as child `Quantum` and exposed as `player.quantum`. Reads the actions `blink` / `entangle` / `superpose` by polling
  (`Input.is_action_just_pressed` in `_physics_process`) **only while `Game.is_playing()`**; timers, cooldowns and visuals stand still when paused or dead. Resets (no explosion) on `Game.new_game / respawn / next_sector`
  and when it leaves the tree; the `Player` also resets `speed_boost`.
- **Methods** (all return `bool` = "something happened", and are gated on playing / alive): `blink()` (throws the beacon, or teleports if one is out), `teleport()`, `entangle()`, `superpose()` (casts the clone, or collapses it),
  `collapse()` (not gated: enemies call it when a bolt hits the clone), `reset()`; `static fix_for(m0, m1) -> String`.
- **State for HUD / enemies / minimap:** `has_beacon beacon_pos beacon_left` · `clone: Node3D` (null when none; the pooled ghost, group `clone`, origin at the feet) `clone_left` · `cd_blink cd_link cd_super` (seconds) ·
  `links: Array` of `{a, b, t, slot}` (`t` = seconds left) · `last_m0 last_m1 last_fix bits_left` (Alice's bits, Bob's correction, seconds the readout stays up) · `fx_root` (top-level parent of all visuals).
- **Numbers (src/quantum.js):** blink 15 energy, 0.3 s cd after the throw, 0.4 s after the teleport (the teleport itself is free), range 48 m (stops 0.6 m before a wall, then dropped with a world-layer ray onto floor / roof / ledge), beacon 8 s.
  Entangle 25 energy, 0.8 s cd, aimed drone with 1.7x radius aim assist (ray capped by the world hit, <= 70 m) + nearest free drone <= 45 m, 9 s; mirrored damage goes through the existing `Drone.damage(..., mirrored = true)`.
  Superpose 35 energy, clone 6 s, `player.speed_boost = 1.3` while it exists (reset to 1.0 when it ends), collapse = `Game.explode(clone + 1 m, 9, {enemy_dmg 70, car_dmg 40, player_dmg 0, cyan})`, 1.5 s cd. Blink and superpose are offline in a vehicle ("... OFFLINE IN VEHICLE").
  Messages: `Game.say` with the prototype's texts; the teleport reads `TELEPORTED · ALICE BITS m0m1 → BOB APPLIES X | Z | X THEN Z | NOTHING` (m1 -> X first, then m0 -> Z).
- **Visuals (cheap, pooled, no lights, no per-frame allocation):** everything lives under one top-level `Node3D` (`fx_root`) and is only shown / hidden. Beacon: thin pillar + pulsing ring + a ring that climbs the pillar + octahedron core + a billboard glow sprite (additive unshaded,
  shared materials). Ghost: the player's own meshes (`PlayerBody._parts`, in the pose of the cast) under ONE shared `ShaderMaterial` (inline tiny shader: fresnel rim + scan lines, additive, unshaded, works in Mobile and Compatibility), plus a ring on the floor;
  it flickers in its last second. Link: two pooled `FX.make_beam` meshes per link slot placed with `FX.place_beam`, flickering in the last 1.5 s. Particles use `FX.burst` scaled by tier. Colours cyan (0.3, 0.94, 1) / magenta (1, 0.24, 0.94).
- **Tiers (`Game.quality`):** simultaneous links LOW 1 / MED 2 / HIGH 3 (a new link replaces the oldest at the cap; switching tier down trims at once); particle counts x0.5 / 0.8 / 1; LOW draws no glow sprite, no second ring, no ghost floor ring, one beam per link, and no teleport blast light.
- **HUD (small edits in `scripts/ui`):** `UiUtil.ability_state` also returns `left` (seconds of the active effect); the ability hints show it (`Q BLINK 7`); `HUD.quantum_readout() -> {visible, m0, m1, fix, alpha}` and a thin-line panel under the centre message show Alice's two bits as boxes
  with the gates `m1 > X` and `m0 > Z` lit when Bob has to apply them (5 s). Touch buttons and key hints appear because `player.quantum` exists.
- **Enemies:** drones pick the clone for half of their shots (`EnemyManager.get_clone()`), and a bolt that crosses the clone's column calls `collapse()`; verified against the real module in `tests/test_quantum.gd`.

## Vehicles as implemented (`scripts/vehicles/**`, `scenes/vehicle_manager.tscn`, tests `tests/test_vehicles.gd`, `tests/test_vehicles_city.gd`, visual bot `tests/bot_vehicles.gd`)
- **Files:** `VehicleSpecs` (every number: specs, caps, distances, colours, driving and traffic constants), `Vehicle` (`CharacterBody3D`, layer 8, mask world; kinematic physics, damage, traffic AI), `VehicleVisual`
  (model or primitive fallback, paint, emissive lights, wheels), `VehicleManager` (`Node`, `Game.vehicles`; pool, streaming, `interact` poll, ramming, lifecycle).
- **API:** `Vehicle.damage(amount)` · `speed` (signed m/s) · `hp max_hp` · `heading` (= `rotation.y`, forward -Z) · `driver_is_player` · `kind` (`sedan sport suv`) · `is_starter` · `ai` · `dead` · `active`;
  `VehicleManager.list` (live cars only) · `nearest(pos, r = 4.2) -> Vehicle` · `toggle_enter_exit() -> bool` · `enter(car)` · `exit_vehicle()` · `driven` · `starter` · `cap()` · `stats()` ·
  `spawn_parked(kind, pos, heading)` / `spawn_traffic(kind, axis, road_i, dir, along)` (null at the cap) · `respawn_time` · `stream_every`.
- **Enter / exit:** the manager polls `interact` while playing (the Player does not forward it). Enter: nearest car within 4.2 m, `player.vehicle = car` (a traffic car is a carjacking, heat +0.2 and `VEHICLE COMMANDEERED`).
  Exit: the first free side (right, left, behind, ahead; never inside a building), `player.teleport_to(pos)` then `player.vehicle = null`. The manager also adopts a `player.vehicle` set from outside and releases one the player left.
- **Driving (src/vehicles.js numbers):** throttle / brake = `move_forward` / `move_back`, steer = `move_left` / `move_right`, handbrake = `jump`. Sedan max 34 m/s, acc 18, brake 40, grip 6.5, hp 120; sport 50 / 28 / 48 / 5.2 / 100;
  SUV (new) 30 / 15 / 36 / 6.8 / 150. Reverse is capped at 35 % of max. Wall hits: bounce (`vel -= 1.4 * vn * n`), hp loss `2.2 x impact` above 5 m/s, `FX.shake`, sparks. The driven car shoves other cars (they lose their AI) and runs over
  drones / operatives above 8 m/s (within 2.4 m: `speed x 3.5` as a crit, 0.6 s per enemy, heat +0.05; it reads `Game.enemies.list`, or the group `enemy` without an EnemyManager).
- **Damage:** hp 0 = the driver is put on foot first, then `Game.explode(pos + 1 m, 9, {enemy 80, car 70, player 35})`, heat +0.2, the car leaves play; after 25 s (`respawn_time`) a parked car appears on a bay near the player
  (the starter car returns to its own place; without a world the car returns where it stood).
- **Traffic:** right-hand lanes on `Game.LANE`. NOTE: `src/vehicles.js` used `c + LANE * dir` on both axes, which is left-hand traffic on the Z roads; here `VehicleSpecs.lane_offset(axis, dir, d)` is `+d * dir` on X roads and `-d * dir` on Z roads.
  Junction turns (55 % straight, always a turn at the map edge, 14 m cool-down), cruise 9-14 m/s, stop for the player on foot and for any car within 11 m ahead and 2.6 m to the side. Parked cars stand on the bays (8.3 m from the road centre), never on junctions.
- **Budget rules:** live cars (starter and driven car included) LOW 3 / MED 5 / HIGH 8; every 0.4 s far cars (> 124 m) go back to the pool, the tier cap is enforced (also at once on `quality_changed`, keeping the starter and the driven car) and at most one car is placed 40-105 m away
  through `Game.world.road_point_near` (55 % parked / 45 % traffic). Cars are pooled per kind (node count stays <= 10), the starter sport car always exists (hidden beyond 140 m). Wheels are hidden beyond 50 m, the Body shadow only within 60 m on MED/HIGH,
  `MirrorProxy` (Body mesh only) only within 25 m (released beyond 33 m, nothing on LOW). No real light per car and no `VehicleBody3D`; simulation only while `Game.is_playing()`; lifecycle signals reset everything and rebuild the starter car; `_exit_tree` clears `Game.vehicles`.
- **Look (surface pass):** the lamp surfaces (`Headlights`, `Taillights`, `Underglow`, same node and material contract and still 5 body surfaces + 4 wheels) now also hold SOFT GLOW GEOMETRY added after the bake (`carlib.add_glow`: lamp halos, headlight and brake-light pools on the road, an underglow pool; vertex colours fall off to black, exported as COLOR_0 for these materials only via `export_model(keep_vcol=...)` + `glbtool.strip_vertex_colors`). `VehicleVisual._make_lamp` draws them unshaded, additive, double sided with vertex colour as albedo, and the state (parked / driving / braking) scales `albedo_color` (not emission): no real lights, no textures, no extra draw calls. The glow reaches past the body, so `test_assets` measures car size without these surfaces. Paint: desaturated lacquer palette (`VehicleSpecs.COLORS`), clear coat 0.85-1.0, metallic / roughness factors split per colour over a baked ORM (`shade_paint`: metal 0.5, rough 0.3).
- **Look (older text):** `Game.load_model(car_sedan | car_sport | car_suv)` (primitive fallback with the same node and material names), never scaled. `DynamicFill.apply` lifts the near-black legacy surfaces (the manager also calls `ensure_light`), then the surface named `Body` is recoloured per instance
  through its override material (colour x the DynamicFill lift, metallic 0.45 / roughness 0.32, a faint 0.15 emission in the paint colour so a car keeps its colour at night). Headlights, taillights (brighter when braking) and underglow are the models' emissive surfaces, scaled per state
  (parked: dim, driven or traffic: on); no per-frame allocation.
- **Measured (software Vulkan, Mobile renderer, MED, whole `main.tscn` view at the spawn):** baseline with no cars and no enemies 108 draw calls; + 4 enemies 156; + starter car 160; the worst case, the starter car and 4 more cars all in view within 30 m (no enemies), 133 (about 5 draw calls per car
  including its reflection). So the car module costs about 4-5 draw calls per visible car, and the MED total is over 150 in the staged view because of the baseline (HUD, post-process, rain, city) plus the enemies, not because of the cars; see the report.


## Characters as implemented (`scripts/characters/character_rig.gd`, `scripts/player/player_body.gd`, `scripts/enemies/operative.gd`, `tools/blender/humanoid.py`, tests `tests/test_assets.gd`, visual bot `tests/bot_characters.gd`)
- **Model (alien redesign):** `alienlib.py` (rig finalizer with the optional `Sec1-3` bones, torso-loft helpers) + `model_player.py` + `model_operative.py` build one `RigPart` per bone (`humanoid.RigPart` / `two_bone` are reused, the old human builder `humanoid.build` is no longer used), join them into ONE mesh weighted 100 % to its bone and bake ONE 1K atlas (`Gear`) with the new `chitin` surface kind (`shade.py`: glossy mottled shell, lighter ridges, dark grooves) plus `glass` (obsidian faceplate), `glow` (veins, eyes, seams; emission strength 2.0) and a faceplate sheen decal. Min albedo is kept near 0.10 by the tint brightening (`BRIGHT`).
  **Kestrel (hero, cyan/teal with amber accents):** elongated cranium with a swept crest and cheek blades, smooth obsidian faceplate with one thin cyan slit, lean four-fingered long hands, digitigrade legs (knee forward, high hock, three clawed toes), layered pearl chitin shoulder plates with spikes, pectoral shell, glowing quantum core in the chest, cyan veins (also a glowing spine line seen from behind), a floating phase halo ring behind the shoulders, a tattered tapering phase-cloak on `Sec1-3` and an alien fork-prong rifle (`Muzzle` between the prongs).
  **Vael trooper (dark bone-grey shell, pale bone plates, orange seams, red glow):** hunched thorax, wide insect skull with four small red eyes, mandibles and a mandible guard plate, swept horns, asymmetric bulk (large left shoulder carapace with spikes, small right one), a second small arm pair folded on the chest, stacked dorsal carapace bands and spines, heavy digitigrade legs with hock spurs, a spined tail with a stinger on `Sec1-3`, a chunky carapace carbine with a petal-prong bio-maw. Rebuild: `tools/blender/build_all.sh player operative drone_sentinel drone_striker drone_heavy` then `tools/import.sh`; builds are byte-identical.
- **Posing (`CharacterRig`, stateless):** the owner keeps the state and writes `phase amp run fw lw air aim_pitch lean twist roll breathe recoil flinch ready sprint reload dead knee_buckle` into the rig, then calls `apply()` once per frame. Legs: hip swing, knee flexion in the swing phase, flat feet, the pelvis sinks to the lowest sole (feet stay on the floor);
  strafing splays the thighs sideways. Torso: aim pitch, lean, counter-twist, breathing, recoil, flinch; the head takes the rest of the aim pitch. The rifle pivots at the shoulder pocket (shouldered / low ready / sprint carry, kick, reload tilt); BOTH GLOVES are solved with two-bone IK onto it (the left one goes to the magazine well and the vest pouch while reloading);
  `dead` = limp arms, legs and rifle; `knee_buckle` = the operative collapsing. The leg heights (thigh, shin, hock) are read from the model's rest pose, so digitigrade legs and any hock height work. The secondary chain `Sec1-3` (cloak or tail, found by name, optional) trails the motion statelessly: it bends back with speed, lags strafing and turning, ripples with the stride, streams up in the air, whips with a flinch or recoil, keeps a slow idle sway and a tail droops when `dead`. `muzzle_transform()` follows the rifle bone, `lowest_world_y()` / `world_points()` use per-bone convex hulls (corpse resting height), `rest_mesh` is an invisible unskinned twin of the mesh for what copies meshes by transform (the street reflection and the quantum ghost show the rest pose).
- **Consumers:** `PlayerBody` keeps `upper` (the model root), `leg_l` / `leg_r` (hip pivot nodes that mirror the thigh swing), `muzzle`, `rig`; the primitive fallback is unchanged. `Operative` keeps `leg_l` / `leg_r` and adds `rig`; it also restores the baked glow that `DynamicFill` would dim. Compatibility renderer: both darken the Gear albedo (that renderer lights the scene much brighter).
- **Surface quality pass (round silhouettes):** `helpers.set_detail(d)` (hero 1.4, trooper 1.1) scales segments, rings, tube rings and bevel steps of every round primitive and Catmull-refines lofts (cars keep d = 1), `shade.py` has two new kinds: `shell` (lacquered chitin, metal 0: at night there is nothing to reflect, metal rendered black) and `silk` (grain-free satin for the phase cloak: the cloak is now overlapping solid elliptic ribbons, no strips, no grain that shimmered like dither). `PlayerBody` fresnel rim 0.6 / tint 0.75, albedo lift 2.4 and a brighter emissive floor give the hero a strong cool rim-lit read from the chase camera.
- **Budgets:** 1 draw call per character, 14.8k / 5.6k triangles (limits 18k / 12k), 14 core bones + 3 secondary; drones 3 surfaces (`Body`, `Fins`, `Eye`) and 2.5k-3.9k triangles (limit 8k). Hit radii and body centres of the drones are unchanged (0.95 / 0.8 / 1.35 m at y 0.95 / 0.82 / 1.40 m). Skinned meshes are posed on the CPU side (14 bone transforms per frame) and skinned on the GPU.


## Character motion as implemented (`scripts/characters/locomotion.gd`, `character_rig.gd`; tests `tests/test_character_motion.gd`, bot `tools/anim_check.sh`)
- **One body mesh:** a skinned character draws exactly ONE mesh (`Rig/Skeleton3D/Body`). The rig's unskinned rest-pose twin `RestBody` (for the quantum ghost's mesh source) is on NO render layer; `PlayerBody._set_layer` (the hero's character light layer) must skip meshes whose `layers == 0`, otherwise it turned that twin into a second, stationary, dim body (the "two bodies" bug). Skinned characters have no `MirrorProxy` reflection. Tested: hero and trooper draw 1 mesh at rest (+3 flash cards only while a shot flashes).
- **`Locomotion`** (RefCounted, one per character, owned by `PlayerBody` / `Operative`, built from the rig): `update(dt, disp, yaw, grounded, vy, want, sprint_on, aim_on, look_off)` with the REAL displacement of the body origin since the last frame. Foot planting: the gait phase advances with distance
  (cycle length 0.9 + 0.55 v metres, contact length of a foot capped at 1.02 m), a planted sole is a world-fixed point (moved by minus the displacement and rotated by minus the yaw change every frame, so walk, strafe, back-pedal, turn-in-place and mixes do not slide), a swing foot flies on a lifted arc to a landing point predicted from the velocity,
  heel strike / flat / heel lift / toe-off pitch about the sole (the digitigrade metatarsal foot rolls over its sole), stops and re-steps (aim stance) run by time. Pelvis sway over the support foot, roll toward the swing side, yaw with the stride, the shoulders counter-rotate, the head stays level and leads turns and the aim, lean from acceleration (start / stop),
  a short backward anticipation when the stick is pushed, landing squash with recovery, takeoff stretch, rising / apex / falling leg poses, aim-down-sights blading (torso turned, rifle counter-rotated, feet re-stepped), idle breathing, weight shift and a slow glance, and a cloak / tail chain of critically damped springs fed by acceleration and turn rate.
- **`CharacterRig` planted-feet mode** (`rig.ik = true`, set by Locomotion; the older phase / amplitude leg model stays for tests and other owners): inputs `sole_l/r` (model-space sole contact points), `pitch_l/r`, `yaw_l/r`, `support_l/r`, `sway`, `pelvis_yaw/roll`, `squash`, `ads`, `head_look`, `flinch_dir` (a hit's direction in body space: front hits rock the chest back, side hits roll and twist it away),
  `death_kind` (0 side, 1 forward, 2 backward: different arm and leg slack poses), `sec_pitch/sec_side`. The pelvis is lowered to what the planted legs reach (a two-bone solve per leg, knee forward, hock back, metatarsus about the sole), so it bobs by itself. Outputs `hip_l/hip_r` as before.
- **Owners:** `PlayerBody` passes `Player.input_move` (new, the stick this tick), `velocity.y`, sprint / aim and the aim yaw offset; `flinch(strength, from_pos)` takes the hit position. `Operative` feeds the same call from its movement, picks its death kind from where the player stands (shot from the front: falls backward, from behind: forward, from the side: away from the shot; 25 % random) and rests the corpse on its bone hulls.
- **Measured** (`tools/anim_check.sh`, 30 fps fixed step, real city): see the report numbers in the commit message / task report; planted foot slide per ground contact is printed as `BOT slide`.

## Quality push as implemented (integrator summary)
- **Stability (`scripts/common/stability.gd`, `AutoQuality`, `LoadingOverlay`):** a watchdog, adaptive quality, an on-device error log and a loading overlay are composed nodes. The camera landing-dip spring is sub-stepped (8 ms) and clamped; `CameraRig.recover_to_player()` snaps it back when it is flung away or its vehicle is gone.
  Atmosphere API: `hurt_pulse`, `set_dead`, `clear_feedback`. Damage feedback is one red edge vignette (alpha <= 0.35, 0.45 s) plus an attacker arc (0.7 s); DECOHERED is a 30 % dim, never a blackout. A destroyed car leaves a dark husk (`Vehicle.wreck`, `VehicleManager.wreck_count()`).
  `Player.damage` while driving now also sets `last_hurt_time` / `last_hurt_from`. Rule: nothing near the camera without a distance fade (`FX._near_fade` for blast cores and fireball puffs).
- **VFX (`scripts/fx/explosion_pool.gd`, `tools/make_fx_flipbook.py`, `assets/textures/fx_flipbook.png`):** 4 pooled explosion slots (LOW 2, MED 3, HIGH 4): flipbook fireball, 1-3 smoke puffs, ground flash + ring, spark streaks, debris; one shared light (none on LOW); heat haze via the global `fx_heat`. Cyan / magenta blasts are the quantum collapse. At most 7 draws per explosion.
- **Characters:** see the section above (one skinned mesh and 14 rigid bones per character, `CharacterRig`).
- **Story (`scripts/story/story.gd`, `Game.story`):** data-driven: 6 chapters, radio lines (typed subtitles with a speaker name), prologue / epilogue cards, death quotes, objective line. It reads `got`, `total`, `hp`, `max_hp`, `vehicle`, `quantum.*` and the Game.message texts COMMANDEERED / OFFLINE IN VEHICLE; renaming those silently stops lines.
- **Environment:** rewritten shopfronts (fresnel glass, mullions, riser, recessed door, shutters), lifted near-field ambient and contact light pools, analytic ground detail (litter, grates, patches, wet halos), brighter roofs, prop colliders (`city_colliders.gd`).
- **Integration changes:** the player no longer collides with `L_ENEMY` (shots use ray / sphere tests). MED sun shadow distance 90 -> 55 m; drone rotors and eye cast no shadow; car body shadow only within 35 m (shadow-cast surfaces cost a draw call per cascade).
- **Measured (Mobile renderer, software Vulkan, `tests/bot_full.gd`, MED, 4 enemies + starter car in view):** total draws (camera + shadow) 142-147 on foot (was 151-160), 82-88 visible; total triangles about 300-315 k (visible 220-229 k). With `--touch` the touch buttons add about 30 canvas draws (178 at the staged view). Other phases 88-118 draws, 91-135 k triangles.

## Aliens and integrated budgets (final integration)
- Story: Neo-Meridian 2091, the Vael hive farms coherence with Observer drones; speakers ORACLE, KESTREL, VAEL BROADCAST (`scripts/story/story_data.gd`). Hero and enemies are aliens (see "Characters as implemented").
- Touch/HUD canvas drawing: antialiased `draw_arc`/`draw_line` cost a draw call each, so the touch controls, crosshair and minimap ring draw non-antialiased, and button labels are drawn after all shapes. Touch mode now costs about 12 draws (was about 35). The touch layer redraws once after leaving `play`, so the dead screen no longer shows stale dimmed buttons under RESPAWN.
- Staged full-game view (`tests/bot_full.gd`, Mobile, whole frame): 105-150 draws (touch) / 97-140 (desktop HUD), 90-268k triangles. Compatibility fallback renders more draws (about 190 with touch at the busiest view): it is the fallback tier, not the budget target.

## HUD phone readability and facade depth (art-review pass)
- **HUD layout (`scripts/ui`):** gameplay text is at least 22 px at 720 p (`UiUtil.TEXT_MIN`; bar captions 18 px), every line sits on a dark backing plate (`UiUtil.PLATE`) with a shadow. One top-centre stack: bars plate, then the objective plate; the HUD publishes its bottom as `UiUtil.stack_bottom` (base px) and the story layer places the chapter objective, banner and radio subtitle BELOW it (top lane, never over the hero or crosshair). While the chapter banner owns the top lane the subtitle drops to the bottom lane. The centre message sits at `Hud.MSG_Y` (below that lane, above the crosshair), the quantum readout under it, the vehicle hint above the ammo plate, the ammo plate left of the touch buttons on phones. Touch buttons are bigger (FIRE r 88, ability buttons r 52-56, labels 22 px); all of them stay inside `StoryView.TOUCH_BUTTONS_W`. Safe area: `UiUtil.insets` (left/right) and the new `UiUtil.insets_v` (top/bottom) are applied to the stack, minimap, ammo, buttons and the bottom subtitle lane. Checked at 1280x720 and 1600x720 (20:9).
- **Canvas batching:** draw_circle / draw_arc / draw_colored_polygon cost one draw each, rectangles of one texture batch. The HUD queues rectangles, sprites, outlines and text and flushes them in that order, text grouped by font size (`Hud._text/_rect/_frame/_sprite`, `StoryView._shadow_text`); round shapes (touch buttons, stars, minimap markers, crosshair dot) are cached procedural sprites (`UiUtil.sprite(kind)`); the crosshair arms are rectangles. The whole HUD layer (touch + minimap + story) costs about 18 draw calls (was about 38).
- **Facades (`building_core.gdshaderinc`):** windows are recessed 0.30 m behind the wall face with a fake parallax (the glass plane is looked up shifted by the view ray; the reveal shows as a shadowed wall, mullions and the interior room slide with it); relief height field gains a rounded pilaster profile, inset spandrel panels and a bevelled ledge, and the bump strength fades with distance. Both are `detail`-gated (LOW tier and the far / mirror copies skip them). Window variety (all tiers, a few hashes): per-building brightness mood, a mono-hue building minority, a "dark floors" habit with three-floor dark or bright bands, per-floor brightness. No new noise loops.
- **Roofs (`city_roofs.gd`):** more rooftop props on more roofs (stair houses/penthouses 0.85, tanks up to 70 m, more AC / HVAC / pipes / masts), taller wall blade signs on towers, and tall vertical roof signs (the blade mesh scaled, same family and draw call). Every crown keeps a clear landing circle at its centre (r 3.4 m, helipad r 6.2 m) because the pooled prop colliders must not occupy the spot the world reports as the roof.
- `tests/bot_hud_phone.gd` is the visual bot of the phone HUD (touch + subtitle + message) and prints the HUD layer's draw-call cost.
- **Art/VFX pass (integrator):** `EnemyMarks` (`scripts/enemies/enemy_marks.gd`) draws enemy threat marks/hp bars with new shaders `fx_aimline`, `fx_bolt`, `fx_threat`, `fx_hpbar` (plus reworked `fx_smoke`, `fx_tracer`, `fx_ground`). Smoke is brighter and lit from below; blasts are visible at 0.1/0.4/1.0 s.
- **Auto-quality governor** is OFF whenever `Game.autostart` is set (tools, tests, bots); pass `--governor` to opt in. `tools/shot.sh` and `tools/bot.sh` take `QUALITY=0|1|2`, so pictures show the real tier.
- **Deterministic VFX bot:** `tools/vfx_check.sh OUT [WxH] [quality]` (`tests/bot_vfx_check.gd`, `--fixed-fps 30`, so frames are exact game time; env `BOT_SET=vfx|enemies|all`, `BOT_ONLY=phase,..`, `BOT_STATS=1`). Slow software rendering makes the wall-clock `bot_full` sampler miss 0.5-1.3 s blasts; use this bot to judge VFX.
- **Detail/budget (bot_full, governor off, 1280x720):** visible draws/prims LOW 53-76 / 88-144k, MED 73-89 / 170-241k, HIGH 83-93 / 240-317k (totals incl. shadows MED up to 125 draws / 325k). Compat+touch MED peaks at 148 visible / 178 total draws (above 150, fallback renderer only). Hero 14.8k tris, trooper 5.6k.

## Wave 5 polish as implemented (orchestrator note)
- **Combat VFX:** `scripts/fx/explosion_pool.gd` and `autoload/fx.gd` (flipbook fireball, smoke lit from below, ground flash and shock ring, sparks, debris, collapse variant with a second magenta ripple), shaders `fx_ground`, `fx_smoke`, `fx_tracer`, `fx_bolt`. Verify with `tools/vfx_check.sh` (runs Godot with `--fixed-fps 30`, so frames are captured at exact game-time ages 0.1 / 0.4 / 1.0 s; software rendering is too slow for wall-clock sampling).
- **Enemy readability:** `scripts/enemies/enemy_marks.gd` (`EnemyMarks`, owned by `EnemyManager`): hostile rim rings, attack telegraph (muzzle flare and aim line 0.45 s before shots), damage-only health bars, all in at most 3 MultiMesh draws and no lights. Bolts use `fx_bolt.gdshader` (one draw for the pool). Sentinel model scale is 1.35 (radius and centre height 1.25). With `Game.graphic_violence` hits spray green Vael ichor.
- **Auto quality** is off whenever `Game.autostart` is set (tools, tests, bots); `--governor` turns it back on. `tools/shot.sh` and `tools/bot.sh` accept `QUALITY=0|1|2`.
- **Known budget facts:** MED whole frame about 133-150 draws, visible triangles 215-241k (about 325k with shadow passes); killing 4 enemies at once spikes to 174-189 draws for about 0.8 s; the Compatibility renderer with touch controls peaks at 178 total draws.
