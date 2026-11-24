GOAL: independent review + fix of wave 121 (walk-in towers TowerFloors, lifts TowerLift). Label w121-critic. No commits.
DONE:
- probes (prints only): godot/tests/dev_w121_critic.gd (5 towers, fingers: in, stairs, floor walk, lift, roof, down, leave; ONLY=<lot>), dev_w121_critic2.gd (ZIP inside)
- look bot godot/tests/bot_w121_critic.gd (CRIT_LOTS=77,42,44 W121_OUT=dir); frames looked at (scratch)
- FIX 1 enemies in an open tower: drone.gd activate keeps a tower floor y, _step checks walls at own floor; city.gd ground_height/is_inside_building use
  TowerFloors.floor_under/blocks (new static funcs in tower_floors.gd, switch TowerFloors.critic_on; W121_CRITIC_OLD=1 = old)
- check godot/tests/test_critic_w121.gd: PASS; OLD fails 3 (enemy floor y, FIRE hit, walls)
NEXT: 2 prop blocks door lot77; 3 camera inside hero head in stairwell; 4 ZIP/SWING dead inside; 5 wall-run wedges under ceiling; frames again; perf at end
DEFECT LIST (evidence in probe output): see report
- FIX 2 door props: tower_floors.gd door_u()/_free_door_u(): door moves along the face off street props (9 of 40 were blocked). check doors in test_critic_w121
- FIX 3 stairwell camera: camera_rig.gd _indoor() (tower = interior camera), TOWER_FADE_MORE; player_body.gd fade_all_on: the skinned Body mesh + gun fade/hide too
- test_critic_w121: PASS 9/9; W121_CRITIC_OLD=1 fails 5
NEXT: ZIP/SWING/FLY dead inside tower; wall-run wedge; perf at end
- FIX 4 dead snake buttons in tower: snake_traversal.gd button_shown() off inside open tower (roof keeps them), snake_fx.gd no ZIP mark then
- FIX 5 wall-run under ceiling: hero_verbs.gd ceiling_stop
- test_critic_w121: PASS 12/12; W121_CRITIC_OLD=1 fails 7
NEXT: lot41 door entry stuck (after door move?), perf at end, report
TESTS AND PERF: test_critic_w121 PASS 12/12, OLD fails 7; test_lifts_w121 PASS; test_touch_buttons_r7 PASS; test_floors_w121 flaky (down / leak) with AND without my fixes (fix switches off) -> not caused here.
 perf (once): LOW draws=76 death=109 OK; MED draws=101 death=149 OK; HIGH draws=112 death=169 OK.
OPEN: stairwell window holes onto street (visual only), no parapet colliders on any roof (pre-existing), gun mesh stays visible at partial fade, parked cars may stand at the kerb in front of a door.
STATUS: done, report handed back.
