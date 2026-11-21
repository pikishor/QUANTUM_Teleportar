# w116-ci-apk (done)

agent id a57029d44f1c5372e, 118 events, first activity 2026-11-21T01:03:16.841Z, last activity 2026-11-21T02:26:09.175Z

## Final report

GREEN 26edc1146ff03512abc622ea40d5965cd87373d6 APK https://github.com/pikishor/QUANTUM_Teleportar/actions/runs/44854893947 ARTIFACT 14687796109 319831503 CI is green on 26edc11 (run 44852161502, all 7 jobs) and the APK was built from that commit (artifact `android-debug-apk`). A later notes-only commit, 8dd3fd8, is on main; its CI run was not watched and the APK does not include it (docs only). **What was red** (CI 44847781823 on 643a3b2: shards 1 and 3, one test each, both attempts). Both were test races, not game bugs, and both fixes are test-only with no check weakened: - **`test_touch_audit_screens`, "a finger dragged over the map pans it" (shard 3).** The map ignores pointer input for its first 0.25 s after opening (`MapScreen.INPUT_QUIET`). The test waited ten frames, which is shorter than that on the fast runner, so the finger-down was dropped. Reproduced here by zeroing `_open_age` before the drag (the same single FAIL of 124). The test now waits until `_open_age >= INPUT_QUIET` before dragging. - **`test_shooting_accuracy`, "a grenade or launcher round lands where the crosshair is: worst 27.8 / 30.1 m off" (shard 1, only the gravity launcher at 25 m).** The launcher locks on to an enemy or vehicle within 7.5 degrees of the crosshair, and `_throw` used a lock left over from an earlier frame. That the locked object was a passing traffic car is inferred from the code and the numbers; the log does not print the lock. Reproduced here by planting a `vehicle` node down the lane (FAIL, 17.8 m off); with the fix the same setup passes at 1.5 m. The test now clears `_launch.target` before the throw; the 2.5 m limit is unchanged. **Passed only on a retry** in the green run, not touched: - `test_flight_view_w116`: 5 checks failed on the first attempt (wing length, speed streaks, rain streaks). - `test_interior_gameplay`: "repeated enter / exit does not leak nodes (4110 -> 4127)", the known far-tile load flake. The first (red) run had no flaky annotations. Notes are in `/home/user/QUANTUM_Teleportar/docs/sprint/progress/w116-ci-apk.md` and in the section "Wave 116 CI fixes" at the end of `/home/user/QUANTUM_Teleportar/docs/HANDOFF.md`. Job logs can now be downloaded with `gh api repos/<owner>/<repo>/actions/jobs/<id>/logs`.

## Last notes of the agent

- 02:15:35 CI is green. Collecting flaky annotations and starting the APK build.

## Recent steps (last 40)

- 01:03:18 Show last commit and recent CI runs
- 01:03:21 Wait for the CI run to complete
- 01:03:25 Block until the CI watcher reports a result
- 01:13:27 Block until the CI watcher reports a result
- 01:23:29 Block until the CI watcher reports a result
- 01:33:32 Block until the CI watcher reports a result
- 01:40:04 List CI job results and read the CI-fix notes
- 01:40:07 Read the annotations of the two failed shards
- 01:40:10 Read the two failing checks in the tests
- 01:40:14 Run the two failing tests locally in parallel
- 01:41:54 Find the font trick, shard script and drag helper
- 01:41:58 Inspect the map screen's pan handling and the test finger helpers
- 01:42:02 Read the map pan, clamp and input code
- 01:42:07 Check the map's input quiet time and the test frame helpers
- 01:42:20 Try downloading the shard 1 job log
- 01:42:25 Read the failing test's CI output and find the gravity launcher code
- 01:42:29 Locate the grenade throw and flight functions
- 01:42:31 Read the throw and grenade flight code
- 01:42:38 Inspect the launcher lock-on and the test's stand helper
- 01:42:40 Read the launcher aim and lock-on code
- 01:42:42 Read the lock target picker and recent history
- 01:43:05 Run temporary reproduction variants of both tests
- 01:44:53 Apply both test fixes and verify them
- 01:46:40 Write notes, commit the two test fixes and push
- 01:46:54 Wait for the new CI run to complete
- 01:46:57 Block until the CI watcher reports a result
- 01:46:59 Block until the CI watcher reports a result
- 01:47:01 Block until the CI watcher reports a result
- 01:47:03 Block until the CI watcher reports a result
- 02:15:37 List flaky annotations and trigger the Android build
- 02:15:57 Wait for the Android build and list its artifact
- 02:25:58 Record the result in the progress notes and push
- 02:26:09 

## Files this agent edited or wrote (last 80, via Edit/Write; shell edits are not listed: use git status)

- (none)
