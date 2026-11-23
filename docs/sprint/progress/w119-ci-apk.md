# w119-ci-apk (CI watch of wave 119 and the phone APK)

- CI 45070818207 on cae4b52: RED. Shard annotations (check-run API):
  - FAIL both attempts: test_vehicles_city "parked cars stand on the parking bays" (ambulance off bay), test_hud_declutter "a parked car can be placed next to the hero", test_critic_look_w115 "a parked sedan stands beside the hero", test_critic_w118 "a finger on ENTER: in the tank" (+ the dial check that follows it).
  - FLAKY (passed on the retry, not touched): test_shooting_accuracy "zero-spread hitscan 99.4 %", test_w119_critic "the weapon wheel opens to reach the BOMBS wedge", test_interior_tasks_ui "copy: the stealth job is on" (known since wave 115).
- Reproduced locally (DejaVu fonts.conf), causes and fixes: see docs/HANDOFF.md "Wave 119 CI fixes".
- Local side note: test_real_fight "no trooper ... behind a car or a wall for more than 12 s (14.8 s)" failed once in a sequential shard-0 replay here; green on the runner, not touched.
- Round 2: see HANDOFF (test_w119_critic bomb aim premise + diagnostics).
