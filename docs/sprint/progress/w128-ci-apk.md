# w128-ci-apk: CI watch and phone APK for wave 128

## Round 1 (CI 46059341693 on 62c54a0)
- Green: Three.js, Unreal, visual QA, shards 2, 3, 4, 5. Red: shard 0 and shard 1.
- Shard 1 FAIL (both attempts): `test_hud_camera_final` "walking off the wall changes the arm smoothly (worst step 0.81 m per 0.4 m of walking)" (also FLAKY with 0.80 m in wave 126).
- Shard 0 FAIL (both attempts): `test_controls_w118` "a tap on HORN sounds the horn (radio_close)".
- FLAKY (passed on the retry, not touched): `test_snake_blasts_w119` "SWARM: the BLAST button is on screen and names the species and count" (shard 5), `test_ai_tactics2` "no enemy stood stuck (1)" (shard 1),
  `test_vehicle_overlap` "market street: no two hulls overlap for longer than 0.3 s (longest 0.32 s)" (shard 0).

### test_hud_camera_final: REAL GAME BUG (camera vs tower shells)
- Local (DejaVu fonts.conf) it passed with worst step 0.43 m. A per-step probe (arm hit, ray hit and collider name) showed the cause: the weapons shop of the check is in a tower lot.
  Near a tower, TowerFloors opens its walk-in shell: it switches the lot's city box off and builds its own wall boxes in a StaticBody "TowerShell". CameraRig only lets the lens sit behind a
  BUILDING wall (THROUGH_ARM; `_is_facade`: shapes named Building*, chunk bodies). The shell's walls had plain names, so when the shell opened `through_wall` went false and the arm fell from
  1.90 m to the real wall distance in one frame. Here the shell opened at step 2 of the walk-off (1.90 -> 1.53 m, under the limit); on the runner it opened at step 1 (1.9 -> about 1.1 m).
  In play: a hero with his back to any tower got the lens snapped into his shoulder the moment the shell opened.
- FIX: `TowerFloors._box(..., facade)`: the six OUTER wall boxes of the shell are named BuildingTowerWall (readable unique names, `add_child(cs, true)`; a plain add_child renames a duplicate to
  "@BuildingTowerWall@n", which the first try hit: only 1 of 6 named). Inner boxes (stairwell, slabs, roof house) stay plain. Switch `TowerFloors.shell_facade` / `W128CI_OLD=1` = old.
- Check `tests/test_w128_ci.gd`: back to a closed tower (lens behind the facade, 1.91 m), the shell opens: new 1.90 m through=true, worst frame 0.01 m; OLD 0.87 m through=false, worst frame 0.99 m
  (2 [old fails] checks FAIL with W128CI_OLD=1, PASS new). After the fix the hud check reads 1.90, 1.90, 1.94, 2.35 ... (worst 0.42 m).
- Also PASS: test_hud_camera_final, test_critic_w121, test_doors_w122c, test_floors_w121, test_life_w123, test_lifts_w121, test_rooms_w122, test_shop_look_w122c, test_street_w124, test_weapon_roster.

### test_controls_w118: TEST RACE
- The check cleared `Sfx.last_played`, tapped HORN for 4 frames and required the LAST sound of any kind to be "horn". The story layer is on in that test; on the runner a story line that was typing
  ended inside those 4 frames and `Sfx.radio_end` played "radio_close" after the horn. The horn family (1 slot) and the radio family are separate, so the horn is not blocked by the radio.
- FIX (the meaning kept: the tap must start the horn): the check now requires the horn family's start time (`Sfx._last_start["horn"]`) to move during the tap, and prints whether the radio was active.
  If the tap was swallowed (a plate over HORN), the horn does not start and it still fails. Passed 3 of 3 (old check, 3-way load) and 1 of 1 (new) here; the runner failure itself did not reproduce.
- Local, under a 3-way load only, once: "w119-hud5: ENTER by finger beside a spawned plane boards the plane (in interceptor ...)": the hero boarded a parked interceptor standing 0.1 m away.
  Passed alone and on the runner; not touched (open).

## Round 2 (CI 46064628802 on c792a9e)
- Green: Three.js, Unreal, visual QA, shards 0, 1, 3, 4, 5 (test_hud_camera_final, test_controls_w118 and the new test_w128_ci pass on the runner). Red: shard 2.
- Shard 2 FAIL (both attempts): `test_mission_audit` "no step gets stuck" (attempt 1: 2 findings, ch3 escort TIMEOUT at progress 0.97 + the guide recovery after it; attempt 2: 6 findings, kill_target
  TIMEOUT / GUIDE_RECOVERED in ch2 step7 (PHASEWRIGHT) and ch3 step5 (OVERSEER) with the hero standing still, aiming, foes alive).
- FLAKY (passed on the retry, not touched): `test_vehicle_overlap` "market street ... longest 0.32 s" (shard 0, again), `test_full_quick` "SCRIPT ERROR: Invalid type in function 'enter' in base
  'Node (VehicleManager)' ... (previously freed)" (shard 5), `test_combat_feel` "a kill plays its confirm sound (hit_armor)" (shard 4, the long-known one). Shard 0 also logged two git connection
  errors in its post-job step (runner network; the job passed).
- REPRODUCED locally: 1 of 3 normal runs (DejaVu, 3 in parallel) failed the same way: "ch2 step7 kill_target TIMEOUT ... progress 0.89" and two guide recoveries. A BOSS log line every 10 s showed
  `ammo=0 reloading=false` from t=40 s to the end (200 s) while the PHASEWRIGHT stood 1 to 12 m away in sight.
- CAUSE (the bot, the same family as the wave 114 note): the hero had a weapon with a LIMITED reserve (a weapon crate on the way equips its weapon). When both the magazine and the reserve were empty,
  the audit bot's `shoot()` released FIRE and tapped RELOAD. With no reserve `start_reload()` does nothing, and the game's swap to a weapon that still shoots (`PlayerWeapon._auto_swap`) only runs on a dry
  trigger pull, so the bot stood there until the step timed out. `keep_carbine()` (wave 114) is only called in the sandbox loops, not in `play_chapters`.
  Proof on demand: `FORCE_WEAPON=d_rook AUDIT_FROM=2:7` (new dev switch): old bot (`AUDIT_DRY_OLD=1`) ammo 0 reserve 0 for the rest of the step, TIMEOUT + GUIDE_RECOVERED (the runner's pattern);
  new bot: the trigger pull swaps to the carbine ("OUT OF AMMO  CARBINE"), the boss falls in 60 s, no finding.
- FIX (tests/mission_audit.gd, the bot only): `shoot()` pulls the trigger of a dry gun with no reserve, like a player, instead of tapping RELOAD (`dry_swap`, `AUDIT_DRY_OLD=1` = old).
- After it: test_mission_audit 3 of 3 PASS (3 in parallel, no TIMEOUT or recovery), test_mission_audit_kinds PASS.
- Open (game, not changed): RELOAD on a dry weapon with no reserve does nothing; a player who taps RELOAD there gets no answer until he pulls the trigger. It could swap like the dry trigger does.

## Round 3 (CI 46070207750 on ecda5ce, the bot fix)
- All green. FLAKY (passed on the retry, not touched): `test_interior_tasks_ui` "copy: the stealth job is on ()", `test_mission_audit` (2 findings: ch3 escort TIMEOUT at progress 0.97,
  hero at (-158.5, 103.8), goal (-160, 80), and the guide recovery after it; the same escort ending as round 2 attempt 1, a different cause from the dry gun: open), `test_soak_quick` "orphans grew from
  57 to 70 (limit 69)", `test_life_w123` "a bus brakes at the bus stop and stands there (0.0 s)".
- APK: android.yml on main (run 46073514957, ecda5ce): success, artifact 15234342793 android-debug-apk, 321124785 bytes.
