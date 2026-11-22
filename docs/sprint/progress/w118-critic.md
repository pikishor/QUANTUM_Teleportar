# w118-critic (independent review of wave 118, then fixes)
GOAL: finger-only review of tanks/helicopters findability + per-mode round-button HUD; list 8 worst defects; fix with failing-first checks.
DONE:
- (session 2 start) read docs; no earlier work existed (session 1 hit the limit before any step).
NEXT:
- own finger bot godot/tests/bot_w118_critic.gd (fresh save, map icon -> GPS -> walk -> tank; helipad; modes HUD at 844x390)
- list defects, fix, test godot/tests/test_critic_w118.gd
DECISIONS:
TESTS AND PERF:
OPEN PROBLEMS:
STATE (session 3, 11:55): bot tests/bot_w118_critic.gd written (finger journey map->GPS->walk->tank, heli pad, MORE>CALL). Frames of bot_controls_w118 at 844 looked at (scratch f1/).
 Defects so far: D-a map GPS line on foot said CAR + car ETA (214 m in 0:11) -> fixed in map_screen.gd (_route_foot, static foot_fix), check TODO;
 D-b ZIP ROOF world tag drawn over the ABILITY disc (foot); D-c foot set = 12 circles; D-d walking the GPS to the yard, a kerb sedan by the yard takes ENTER (frame 04).
FIXED 1 (D-a GPS on foot): map_screen.gd _route_foot/foot_fix (both ETA sites). FIXED 2 (D-b zip tag over buttons): snake_fx.gd tag_at()/tag_dodge/last_tag.
 Check tests/test_critic_w118.gd (parts gps, tag): new PASS; CRITIC_OLD=1 both FAIL (shown).
FIXED 3 (D-g door says EXIT 243 m up, press does nothing visible): touch_controls.gd _label_of -> LAND FIRST while VehicleCraft.can_exit false (static door_air_fix). test part air: new PASS, old FAIL.
REVERTED: a map label dodge (HELICOPTER over GLASS TOWERS, frame c2/02) - could not make a check reproduce it headless: reported as open.
FIXED 4 (tank turret dial inside the stick ring, under the thumb): vehicle_hud.gd dial_fix/last_dial. test part dial: new PASS, old FAIL.
PROBE: MORE>CALL>PLANE delivers at spawn (part plane, a probe, not old-failing). Walk from spawn to yard by GPS: bot failed twice in 5 min (25-53 m short); from 50 m fine (16 s, tank, drive 35 m, fire, COAX/SHELL/VIEW/BRAKE/MORE pressed, exit). Route ends via the open front.
NEXT: frames f2 (foot,tank) c5 (heli air door) at 844; then more defects (foot clutter = design conflict, report), related tests, perf once.
STATE: related 17 tests PASS (critic re-run PASS after clean-up fix). Perf gate running.
PERF: see report
DONE (final): perf LOW draws 72 OK, MED 97 OK, HIGH 113 OK. airport_aircraft PASS. Report sent. Nothing committed.
OPEN: foot set 11 circles (design conflict with test_controls_w118), map HELICOPTER/GLASS TOWERS label overlap (no reproducing check), long GPS walks by bot stalled (cause unproven), ORACLE card cut at 2400 in aircraft.
