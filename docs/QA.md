# QA: soak and monkey bots

Long-running, automated play of the REAL composed game (`godot/scenes/main.tscn`, every autoload and module) that finds what short tests cannot: slow leaks, errors that only show
after minutes of mixed play, and screens that cannot be left. Everything runs from `godot/`.

| What | Command | Real time | Use |
|---|---|---|---|
| Quick soak + monkey + regressions | `tools/test.sh tests/test_soak_quick.gd` | about 30 s | CI runs it with every other `tests/test_*.gd` (`.github/workflows/ci.yml`) |
| Soak, 10 simulated minutes | `tools/soak.sh` | about 2.5 min | before a release, after touching pools, streaming, lifecycle or UI flow |
| Monkey, 5 simulated minutes | `tools/soak.sh --monkey --minutes=5` | about 1 min | after touching screens, input, menus, state changes |
| Same on the software renderer | `tools/soak.sh --render --minutes=1.5 --scale=0.4` | about 4 min | judges texture and video memory too |

Exit code 0 = PASS, 1 = FAIL, 124 = timed out. Options (both bots, after the script flags): `--minutes=N --seed=N --speed=N --quality=N --real --quiet`;
soak only: `--scale=F` (length of every activity), `--cycles=N`, `--only=walk,combat,drive,interior,tiers,pause,tour,die,sector,newgame`, `--no-reset`;
monkey only: `--rate=N` (events per game second), `--no-chaos`, `--no-resize`, `--events=N`. Env: `SOAK_TIMEOUT` (real seconds), `RENDER_RES`, `SOAK_FPS`.

Files: `tools/soak.sh` (launcher), `tests/bot_soak.gd`, `tests/bot_monkey.gd`, `tests/soak_lib.gd` (monitors, limits, error tap, event helpers), `tests/test_soak_quick.gd`.
The bots use the same hook as the other bots (`--bot=`, autoload `Dev`), so they also run as `tools/bot.sh`-style scripts; nothing in the game knows about them.

## How the runs are made fast and reproducible

* **Headless by default.** The dummy renderer is fast (a 10 minute soak in 2.5 real minutes). It reports 0 for texture and video memory, so those two are judged only with `--render`.
* **Time scale.** `Engine.time_scale = k` and `physics_ticks_per_second = 60 k` (k = `--speed`, default 4), so one physics tick is still 1/60 s of game time (see the test gotchas in
  `godot/ARCHITECTURE.md`). `--render` runs `--fixed-fps 12` at speed 1 instead: every rendered frame is exactly 1/12 s of game time however slow software Vulkan is.
* **Seeded.** One `RandomNumberGenerator` per bot, seeded by `--seed`; the input stream depends only on the seed and the game clock. The game itself (threads, frame pacing) is not
  deterministic, so a failure is reproduced by the same seed most of the time, not always. The failing activity, time and last action are printed with every error.
* **Tools conditions** (`Game.autostart`) switch cutscenes, the scripted campaign, the tutorial and autosave off, like every other tool. `--real` turns the first three on (the HUD
  settings file is moved to `user://soak_settings.cfg` and deleted afterwards; autosave stays off, so a run never touches a player's saves).

## The soak (`tests/bot_soak.gd`)

A **warm-up pass** first makes every pooled thing once (every enemy type, every car kind, every interior type, all three tiers) and takes the **baseline checkpoint**. Then CYCLES
(about 85 game seconds each) until the minutes are used up:

1. street walk (sprint, jump, aim, fire, reload, random look), 2. combat (4 to 6 enemies of mixed types, heat 2.5 so reinforcements and Vael patrol cars come, weapon swaps,
blink / entangle / superpose, grenade-size explosions), 3. a drive (find or spawn a car, enter with USE, steer, brake, handbrake, wreck it half of the time, exit),
4. two interiors (every door type over the run; with and without the fade; the vendor window opened and closed; walking and shooting inside), 5. the three graphics tiers,
6. pause with ESC and resume (every third cycle: ABORT TO MENU and DEPLOY), 7. a tour of ten random spots of the city (streaming churn), 8. death and RESPAWN through the
button (on foot, driving, inside an interior in turn), 9. clearing the sector (teleport onto every core, win screen, NEXT SECTOR) on even cycles and a new game (directly or
through the title screen) on odd ones, 10. a short walk, then the **checkpoint**: interior left, car left, enemies cleared, base tier, heat 0, player at the spawn, 3 s to let queued
frees run, then the Performance monitors are sampled.

Monitors: node count, orphan nodes, object count, resource count, static memory, texture memory, video memory. A progress line is printed every 20 game seconds.

**It fails on:** (a) growth. Any checkpoint above the baseline by more than `LIMITS` in `tests/soak_lib.gd` (the absolute AND the relative slack must both be exceeded), or a steady trend
over the later half of the checkpoints (6 or more) above the `slope` limit; (b) any new `push_error`, script error or engine error (own `OS.add_logger` tap, with the first 30 lines and the
script backtrace printed); (c) a soft lock: a state that is not play for 25 game seconds without the bot having asked for it, a screen the bot cannot leave by clicking its button
for 40 game seconds, ESC that does not pause, lethal damage that does not end in `dead`, an interior door that never opens or lets the player out, no game time passing for 90 real
seconds. Every failure line says what, where and with which state; the biggest node growers (by class and by scene path) are listed after the result.

| Monitor | abs | % | late slope per game minute | Healthy 10 minute run (headless, three seeds) |
|---|---|---|---|---|
| nodes | 150 | 8 | 25 | 1390 to 1520, late slope +2 to +11 (pools still filling to their caps) |
| orphans | 12 | n/a | 1 | 54 flat (see "Known gaps") |
| objects | 1500 | 8 | 50 | 5670 to 5960, late slope -0.3 to +20 |
| resources | 400 | 10 | 25 | 370 to 400 flat |
| static MB | 64 | 20 | 3 | 328 to 367, late slope 0 (the first 2 cycles still load lazily) |
| texture MB (render) | 24 | 10 | 2 | 332 to 357 (render run, 2 cycles) |
| video MB (render) | 48 | 12 | 4 | 410 to 442 (render run, 2 cycles) |

## The monkey (`tests/bot_monkey.gd`)

N events per game second (default 14, mode changes every 4 to 9 s between WILD, PLAY (drags and held fingers), UI (taps and clicks on screen buttons), KEYS and CHAOS). Events: touch
down / drag / up with 5 fingers (random places, the stick zone, every touch button, the pause button, the FPS box, every button of the current screen, the TEST button and test
menu items, vendor rows, a violent flick, spots outside the screen), mouse clicks and moves, key presses (ESC, ENTER, SPACE, TAB, F10, WASD, arrows, weapons, powers, random keys),
raw action presses, window resizes to phone portrait / landscape / tablet sizes (headless only), focus loss, and chaos: damage, lethal damage, enemies, a win, quality tier, heat,
doors, leaving an interior, cars, teleports, explosions, weather, and "pause then ABORT TO MENU" / "DEPLOY or CONTINUE from the title".

**Soft-lock probe, every 20 game seconds and at the end.** The monkey lets go of every finger, key and action, then plays like a person who wants out, with legitimate taps only
(RESPAWN, NEXT SECTOR, RESUME, DEPLOY / CONTINUE, CLOSE of the test menu or the vendor window, taps through story cards and cutscenes, shop / chapter BACK). The game must be in `play`
within 30 game seconds (the title screen counts as alive only if DEPLOY leads out of it), no interior transition may hang, the time scale must be back to normal (the death slow
motion), the HUD layers must match the state, the player and camera must exist and be finite, and ESC must pause and resume. A failed probe prints the whole UI state (buttons and
their positions, test menu, vendor, interior, story cards, screen age).

Output: events by kind, seconds per state (a healthy 5 minute run visits play, paused, dead, menu, win; with `--real` also cutscene), recovery counts.

## The quick test (`tests/test_soak_quick.gd`, about 30 s, CI)

One composed game: the soak for one cycle at 1/4 length (warm-up, every activity once, 2 checkpoints, wide absolute limits because a trend needs more points), the monkey for 36
game seconds (about 470 events, 2 probes), and four regression checks of the bugs below (minimap polygon test, car mesh cache hits after a model reload, DEPLOY after ABORT TO MENU
during the prologue). Mutation-checked for the cache and prologue checks: with the old code of those two fixes the test fails on exactly those checks (the minimap one tests a new function). CI machines are slower than this one: the runner's watchdog is 60 real
seconds (`tests/runner.gd`; its timer counts real seconds in the working tree, which the quick test relies on because it runs at time scale 4), the test takes about half of that here.

## Found and fixed by these bots (first runs)

1. **Memory leak in the car meshes** (`scripts/common/shadow_proxy.gd`, `scripts/vehicles/vehicle_visual.gd`, `scripts/common/dynamic_fill.gd`). Caches of merged lamp meshes, shadow
   meshes, albedo lifts and texture luminances were keyed by `get_instance_id()` of the model's mesh. A model that is instantiated again after its PackedScene was dropped gets NEW
   mesh objects, so the key never hit and each car that the manager built (it frees and rebuilds pooled cars of other kinds once the node budget is full, so constantly while driving
   around) added a mesh to a static dictionary for ever: 0.33 MB and 3 to 5 objects per car. Before: 10 minute soak static memory 332 -> 449 MB (+13 MB/min), objects +1100;
   400 teleports through the city +70 MB. After: flat. Fix: key by `resource_path` (stable: `res://assets/models/car_sedan.glb::ArrayMesh_x`), instance id only for code-made meshes.
2. **Soft lock on the title screen** (`scripts/story/story.gd`, `_input`). NEW GAME starts the prologue cards; ABORT TO MENU left them queued, frozen (`advance()` only runs in
   play / dead / win) and invisible, and `_input` still swallowed taps (`Game.state != paused`) while a card was younger than `CARD_MIN`: DEPLOY and CONTINUE could not be tapped any more
   (Enter was eaten as well) until the app was restarted. Fix: cards take input only in the states in which they are drawn. Found by the soak, confirmed by the monkey on the old code.
3. **Error flood in interiors** (`scripts/interiors_gameplay/interior_minimap.gd`, `_quad`). Pulling every corner of a wall rectangle into the minimap circle can collapse it to a line or
   fold it; `draw_colored_polygon` then logs "Invalid polygon data, triangulation failed" every frame (hundreds a minute along some walls, 76 in one 4 minute run). Fix: skip a quad that
   is no longer a proper convex quad (`_drawable`).

## Known gaps

* **Headless dummy-renderer errors.** `Parameter "material" is null` in `material_get_instance_shader_parameters` (dummy renderer) appears about 2 times a minute in headless runs, at
  random moments, never under software Vulkan (`--render`, several runs). The dummy storage does not notify instances when a material is freed, so a stale RID is looked up later; no
  game code that frees a material still in use was found, and no script backtrace exists (the call comes from the rendering server). `HEADLESS_NOISE` in `tests/soak_lib.gd` counts it
  apart, only when headless; `--render` runs are the judge for it. If it ever appears with `--render`, it is a game bug.
* **48 to 54 orphan `MeshInstance3D` nodes** exist from the first frame on (not growing, listed by `ObjectDB` at exit as "Stray Node"): some module creates meshes it never adds or frees.
  The soak limits growth, not the baseline; finding the owner needs an editor with the remote tree or `--verbose`.
* **Render mode is slow** (about 0.3 to 0.5 game seconds per real second at 480x270 to 640x360) and window resizes hang Godot at exit under xvfb, so the monkey resizes the window only headless (the phone
  layouts are therefore exercised headless only). Texture / video memory come from the render soak, which is short (1.5 to 3 minutes of game time, 3 checkpoints, no slope judged).
* **Not covered:** audio (muted), saves (autosave is off under `Game.autostart`, so CONTINUE, `save_state` and `Progress.save_file` are not soaked: a leak or error there would not show),
  suspend / resume of a real phone, GPU time and frame rate (the perf gate `tools/perf_report.sh` is separate and stays green), real touch hardware, the Compatibility renderer.
* **Speed 4 changes timing.** Anything on wall-clock time (fades count real seconds, the death slow motion, the loading overlay) runs relatively slower than the game. Run `--speed=1` for a
  slow, closer-to-real pass.
* A soak finds growth inside a run; a leak that only grows with the number of full application sessions (static state across scene reloads) is out of reach.

## Using them

* After a failure: re-run with the same `--seed`, narrow with `--only=<activity> --cycles=8`, read the `! error #n at t=... during '<activity>' (<note>)` line, and the "census growth"
  list for what grew (`class` = node class, `path` = scene path below the root).
* A new pool, cache or screen: run `tools/soak.sh` and `tools/soak.sh --monkey --real` once; add the new thing to an activity (soak) or the hot spots / chaos list (monkey) if it is not
  reached yet. A new leak limit is a decision: change `LIMITS` in `tests/soak_lib.gd` with the numbers of a healthy run in the table above.
* Nightly job (optional; not added to `.github/workflows` because workflows are owned elsewhere): a `schedule` + `workflow_dispatch` job on `ubuntu-24.04` with the same packages as
  `ci.yml`, running `godot/tools/bootstrap.sh`, `godot/tools/soak.sh --minutes=10` and `godot/tools/soak.sh --monkey --real --minutes=5 --seed=$GITHUB_RUN_NUMBER`. It needs no secrets.
