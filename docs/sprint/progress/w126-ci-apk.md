# w126-ci-apk: CI watch and phone APK for wave 126

## Round 1 (CI 45899942892 on f25c3a6)
- Green: Three.js, Unreal, visual QA, shards 0, 1, 2, 3, 5. Red: shard 4.
- Shard 4 FAIL (both attempts): `test_air_w126_b` "CARGO PLANE waits; a finger on ENTER boards it and the mission goes on (1/2 GET IN THE CARGO PLANE 287 M ...)".
  The bot's own debug line: `DBG enter cargo: label '' shown false dist 266.2 edge 246.6 dy 0.0` (attempt 2: 268.7 / 249.2): after the 8 s walk the hero stood 266 m from the
  cargo plane and the DOOR slot never said ENTER. The three jet boardings before it (same strip, same code) passed.
- FLAKY (passed on the retry, not touched): `test_director_round2_c` "a hurt engine runs rough: the note wobbles (0.009 against 0.000)" (shard 4), `test_superhero_hero`
  "the female body stands on the floor too (0.235)" (shard 1, the long-known pose timing flake), `test_hud_camera_final` "walking off the wall changes the arm smoothly
  (worst step 0.80 m per 0.4 m of walking)" (shard 5).
- Local (DejaVu fonts.conf, fresh XDG_DATA_HOME): `test_air_w126_b` PASSES alone (1 of 1) and 3 of 3 in parallel; a probe (`tests/dev_w126ci_cargo.gd`, not committed) that runs
  only the cargo boarding, or all four missions before it, with the physics allowed to keep up with the frame clock (`max_physics_steps_per_frame` 16), passes too: ENTER shows at
  the wing tip (edge 0.6 to 1.5 m) 13 m into the walk. Not reproduced here.
- Next: the test now logs the walk when a boarding fails (hero, aircraft, active / ai / hold, the DOOR slot state, reach_car, held fingers, fps every 20 physics ticks) so the
  runner tells what happened; pushed as a diagnostic round.

## Round 2 (CI 45905071385 on f8d68e6, the diagnostic commit)
- All green, no FLAKY annotation; `test_air_w126_b` passed on its first attempt (the cargo flew to SOUTH FARM), so the diagnostic trace did not print. The round 1 failure stays
  unexplained (intermittent); see HANDOFF "Wave 126 CI fixes" for what was ruled out and the ideas left.
- APK: android.yml on main (run 45908117393).
