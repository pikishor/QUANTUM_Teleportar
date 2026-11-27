# w127-ci-apk: CI watch and phone APK for wave 127

## Round 1 (CI 45986429383 on bdab8a8)
- Green: Three.js, Unreal, visual QA, shards 0, 1, 2, 3, 4. Red: shard 5.
- Shard 5 FAIL (both attempts): `test_w127_critic` "[old fails] the stick drives the heavy tank across MOUNTAIN TRACK BRIDGE (mountain_track_4, 68 m, curved / steep): 25 m of 68,
  never more than 0.54 m under the deck" (HIGHLINE BRIDGE passed, 66 of 70).
- FLAKY (passed on the retry, not touched): `test_device_fixes` "a solid world wall still shortens the arm (3.37 m)" (shard 1), `test_damage_everywhere` "a Cars v2 sedan stands
  in the arena" (shard 1).
