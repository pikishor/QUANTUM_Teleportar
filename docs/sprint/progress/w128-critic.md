# w128-critic progress log
GOAL: independent review of wave 128 (anim, airlook, arsenal, open) with a finger-only bot in main.tscn; list 8 worst defects; fix most severe first, each with a failing-then-passing check.
DONE:
- (start) read ROUND7, PLAN line 128, ROUND6 rules, HANDOFF tail, builder reports.
- viewer renders of all 23 heli kinds (side/rear) MED: tail rotors at the back, fins at the tail, tiltrotor/tandem/coax correct (scratch v/)
- new look bot godot/tests/bot_w128_critic.gd (every heli + plane kind parked, daylight, game camera f3q/r3q; CR_KINDS=...)
- blast frames: bot_blast_arsenal 10 ids x 6/14/28 m MED (scratch bx/)
- DEFECT fire (FIXED): fx_flipbook.png was VRAM block-compressed (DXT1/ETC2): near fireballs show 20 px staircase squares -> import compress/mode=0 (lossless, +~4.7 MB VRAM); check tests/test_w128_critic.gd part fire: old FAIL (format 17), new PASS
- DEFECT thermo (FIXED): la_thermo drew a crisp see-through orange sphere (dome) with real_on -> blast_fx.gd `&"dome"` recipe skips the dome when real_on; check part thermo: old FAIL (domes 1), new PASS
- DEFECT anim-flaky (FIXED test): test_anim_w128 cast checks sampled after fixed frame counts: under load FAIL 2/52 (teleport 0.02 m, hand back 0.091 m); now sampled on the gesture's own clock (HeroCast.t / phase). W128_OLD=1 still fails. Also seen once under load: "ENTER boards the SPARROW SCOUT" (not changed)
- helis in game (bot_w128_critic, MED, daylight): 23 kinds look like real helicopters (tail rotor at the back on the fin, stabilisers, skids/wheels); OK
- planes: legacy GLB jet/cargo (xv_*.glb, one mesh 'Body') have a tail-wheel strut under the tail and no nose leg (fighter/airliner should be tricycle): NOT fixed (needs GLB geometry)
- fauna (zebras, big cats) wander on the airport apron among the aircraft (frames ac/*)
- after fixes, blast frames (bx2/, MED): fireballs smooth, no dome on thermo, dark soot cloud on air strike; OK
- DEFECT (NOT fixed, cause unknown): a parked p_awacs drew only its wheels (Body + Body_LOD1 invisible, Detail visible) in 2 of 4 runs (after p_tanker in the same pooled Vehicle; frames ac/p_awacs_*, aw2.jpg); node state is fine headless (probe tests/probe_w128_critic.gd)
- demo VEHICLES/AIRCRAFT tabs + god mode by finger: test_w128_open OPEN_PARTS=demo PASS
- running: in-vehicle perf CR_ONLY=perf (q0,q1) -> scratch pf/log; tank mission probe PARTS=fight -> scratch fight.log
- in-vehicle draws LOW (CR_ONLY=perf, airfield, chase cam): heli 116/117, fighter 122/131, tank 124/122 (hidden/seated pilot)
- DEFECT seat (FIXED): the seated pilot's ShadowProxy kept casting under the canopy -> player_body.gd _seat_shadows (SEAT_SHADOW_OLD=1 old); check part seat: old FAIL (["ShadowProxy"]), new PASS
- tank mission by finger (probe_w127_critic PARTS=fight): STEP 1 drive leg 1584 m; step 2 began with the tank 1509 m from the fight (stuck skip) and the hero OUT of the tank ("GET IN THE TANK"), not finished in 423 game s: NOT fixed
- tests PASS: test_w128_critic (all), test_blastfx_w128, test_blast_table, test_anim_w128, test_blast_arsenal, test_vfx, test_arsenal_w128, test_w128_open demo
- MED in-vehicle (with the shadow fix): heli 156/155, fighter 169/171, tank 168/167 draws (airfield views over the 140 staged budget: known open)
- PERF gate (once): LOW draws=72 total=94 death=109 tex 117 OK; MED draws=99 total=131 prims=274k death=146 OK; HIGH draws=118 total=154 death=164 OK
NEXT:
- done (report sent)
- look at frames; read builder tests/bots; write review bot (aircraft close-up MED, 36 weapons by touch, 10 blasts x 3 distances, hero poses, demo tabs, perf)
DECISIONS:
TESTS AND PERF:
OPEN PROBLEMS:
