# w128-anim progress log
GOAL: plan line 128: human and creature animation (seated pilots/drivers with hands on controls, cast animations, snake strike, flight poses, gaps); permanent test godot/tests/test_anim_w128.gd by real touch.
SURVEY (what existed / missing):
- hero: CharacterRig (procedural IK, hand_w targets, pose_hips), Locomotion, HeroClips, HeroAnimPolish (vault/mantle/glide/wall/slam/cover), HeroFingers (grip/aim/relaxed), SnakePose (swing/zip/climb/fly/roll poses)
- MISSING: hero HIDDEN in every vehicle (Player._apply_vehicle_state body.visible=false); aircraft/tanks had no pilot at all; canopy glass opaque dark; no cast animation for any quantum verb (blink, teleport, link, entangle, superposition, collapse, shield, slip, arc); combat snakes (SnakeSwarm) crawl with a body wave but have no strike (they arrive and vanish / coil)
DONE:
- scripts/characters/seat_pose.gd (NEW class SeatPose): seat measured on the built model (cockpit glass front cluster + hull floor; turret roof for hatch; hand-made astride for quad/scooter/jetski); see-through canopy while aboard; W128_OLD=1 = old (hidden)
- character_rig.gd: seat, seat_hips, seat_recline, seat_feet, seat_hands, seat_hand_w; _seat_legs(); sole_now/hips_now/head_now helpers
- player_body.gd: _seated_view / _leave_seat (body on seat, controls follow stick/steer/lever, gun hidden, cockpit view hides body)
- probe tests/probe_w128.gd (direct calls, numbers only), look bot tests/bot_w128_anim.gd (AN_KINDS, AN_OUT)
- scripts/characters/hero_cast.gd (NEW class HeroCast): cast gestures (point/spread/pull/slam/push), wind-up -> release -> hold -> return, right hand keeps the weapon; hooked in player_body.gd update_view
- snake_swarm.gd: crawl STRIKE (neck coils back into an S, then lunges), SnakeSwarm.strike_on
- player_body.gd: seated body re-placed in its own _process (priority 1000) after the vehicles' visual sync (no one-frame lag = no foot sliding)
- canopy: double-sided tinted transparent glass (Body + Body_LOD1) while aboard
- tests/test_anim_w128.gd: PASS 52 checks ~40 s; W128_OLD=1 FAIL 9+ (seen in seat x4, cast x3, snake x2)
NEXT:
- done (report sent)
DECISIONS:
- cars keep the painted CarV2 driver; drones (p_drone, p_ucav) no pilot
TESTS AND PERF:
- PERF_CHECK=1 perf_report 0 1 2: LOW draws=74 total=96 death=108 OK; MED draws=99 total=131 prims=274k death=144 OK; HIGH draws=118 total=154 death=164 OK
- related PASS: test_hero_animation_polish, test_quantum, test_quantum_teleport, test_snake_combat, test_snake_traversal, test_helis_w125, test_tanks_w127, test_planes_w126_b; test_superhero_hero flaky "female body stands on the floor" once, then PASS 2/2 (old and new)
OPEN PROBLEMS:
- tank_crews.gd:246 casts c["v"] as Vehicle before is_instance_valid: SCRIPT ERROR spam after a tank is released (not mine; test avoids releasing tanks)
- cars keep the painted dummy driver; legacy art bikes (bike, qbike, hoverbike) ride without a visible rider; hero glide/take-off/land flight poses not reworked (SnakePose FLY + polish glide exist)
- another agent (w128-airlook) edits heli/plane models at the same time: seats are measured, so they follow
