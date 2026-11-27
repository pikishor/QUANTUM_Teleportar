# w127-critic progress log
GOAL: independent review of wave 127 (tanks + tank arms) with a finger-only bot in main.tscn; list 8 worst defects; fix most severe first, each with a failing-then-passing check.
DONE:
- (start) read ROUND7, PLAN line 127, ROUND6 rules, HANDOFF tail, both builder logs and their tests.
- review probe godot/tests/probe_w127_critic.gd (headless, fingers; PARTS=kinds|fight|crash|bridge, KINDS=...; runner caps at 140 s so run in batches) and look bot godot/tests/bot_w127_critic.gd (CR_ONLY=drive|perf)
- kinds part run on all 20 new kinds: board/drive/turret/fire/arms/smoke all work by finger; findings so far:
  * builders' mission tests TELEPORT the tank to the goal and aim with meta aim_at (not fingers) -> missions not proven by finger
  * t_halftrack (FOREST ROAD checkpoint) drives 4.8 m into a tree trunk (Vegetation/Trunk1) and stops
  * wheeled kinds (apc8, mrap, jeep, scout) model AABB 1.5-2x spec width in game (Run multimesh) -> check in frames
  * t_mine model bottom 0.33 m under ground (flail?)
NEXT:
- look at frames (bot1), fight + missions by finger, crash, bridge, perf
DECISIONS:
TESTS AND PERF:
OPEN PROBLEMS:
