# Wave 117 CI watch and APK (w117-ci-apk)

- CI run 44882303665 on 652ab43 (wave 117): GREEN on the first run, nothing fixed. Three.js, Unreal, visual checks and the four Godot shards all passed.
- Passed only on a retry on the runner: `tests/test_mission_board.gd` (shard 2, first attempt "the bot hit at most two stuck findings (4)"). Not investigated; no code changed.
- The integrator's local notes (not seen on the runner): `test_hero_locomotion2` flaky once ("pelvis moves at most 11.4 cm per frame"), `test_critic_look_w115` stale check moved by the integrator.
- APK: android.yml run 44884758327 on 052b73e (652ab43 plus the docs-only QA sheet commit), success, artifact `android-debug-apk` id 14699304575, 319864581 bytes.
