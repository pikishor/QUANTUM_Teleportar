# w128-critic progress log
GOAL: independent review of wave 128 (anim, airlook, arsenal, open) with a finger-only bot in main.tscn; list 8 worst defects; fix most severe first, each with a failing-then-passing check.
DONE:
- (start) read ROUND7, PLAN line 128, ROUND6 rules, HANDOFF tail, builder reports.
- viewer renders of all 23 heli kinds (side/rear) MED: tail rotors at the back, fins at the tail, tiltrotor/tandem/coax correct (scratch v/)
- new look bot godot/tests/bot_w128_critic.gd (every heli + plane kind parked, daylight, game camera f3q/r3q; CR_KINDS=...)
- blast frames: bot_blast_arsenal 10 ids x 6/14/28 m MED (scratch bx/)
- DEFECT fire (FIXED): fx_flipbook.png was VRAM block-compressed (DXT1/ETC2): near fireballs show 20 px staircase squares -> import compress/mode=0 (lossless, +~4.7 MB VRAM); check tests/test_w128_critic.gd part fire: old FAIL (format 17), new PASS
- DEFECT thermo (FIXED): la_thermo drew a crisp see-through orange sphere (dome) with real_on -> blast_fx.gd `&"dome"` recipe skips the dome when real_on; check part thermo: old FAIL (domes 1), new PASS
NEXT:
- look at frames; read builder tests/bots; write review bot (aircraft close-up MED, 36 weapons by touch, 10 blasts x 3 distances, hero poses, demo tabs, perf)
DECISIONS:
TESTS AND PERF:
OPEN PROBLEMS:
