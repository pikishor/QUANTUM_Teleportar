# w119-blasts progress log
GOAL: snake species bursts (6), one SNAKE BLAST round button, species on ability wheel, aim ring, cooldown/count; test_snake_blasts_w119.gd by real fingers.
FOUND (real finger probe godot/tests/dev_w119_probe.gd, 844x390, force_touch, cards on):
- ABILITY wheel SNAKE BOMB disc (quick cast of the armed bomb): no ring at all while casting; it aims at SnakeAim.point(30 m) which is the end of the camera ray 3 m UP in the
  air when the crosshair is on the street ahead; the grenade arc went there and the fuse fired it 9 m above the street (det at y 8.95): 3 foes 14 m ahead untouched.
- weapon wheel by a held finger on WEAPON did not open in the probe (not chased: w119-hud5 owns the buttons). FIRE with nothing armed casts nothing.
DONE:
- godot/scripts/quantum/snake_blasts.gd (class SnakeBlasts, Node under SnakeWar): 6 species sp_fire sp_frost sp_shock sp_acid sp_swarm sp_gravity, BlastTable cat snake_species;
  hold BLAST = ring (radius = table radius x war.radius_mult) on the ground under the crosshair (clamped 4..30 m, grounded by a long ray); release/tap = throw along an arc,
  burst exactly at the ring; 3 charges, 5 s recharge; reuses SnakeBombs._freeze/_chain/_swarm_burst/_gravity/_burst_snakes; acid corrosion own tick; OFF switch SNAKE_BLASTS_OFF=1.
- hooks: snake_war.gd _ready (attach, 1 line); snake_swarm.gd Body.pattern + custom z = tension + 2*pattern; snake_tendril.gdshader 6 skin patterns (decode floor(z/2));
  snake_ui.gd ability_state/label for snake_kind; touch_controls.gd: SNAKE_ABILITIES snake_bomb -> snake_kind, _wheel_pick hook, _label_of hook, arcs hook (4 lines).
- godot/tests/test_snake_blasts_w119.gd: PASS 72 checks; SNAKE_BLASTS_OFF=1: FAIL 9 of 10.
DECISIONS: action snake_blast (w119-hud5 context slot, label from SnakeBlasts.button_label()); ability disc id snake_kind; species ids above.
- tests/bot_snake_war.gd: sp_* ids (hold BLAST ring frame, then 3 frames after the burst) and sp_lineup (the six skins); kind_label is SNAKE <TYPE> (test_snake_combat counts SNAKE discs).
- test_snake_combat PASS 137, test_controls_w118 PASS. LOW sheet 1: fire/frost read well; shock weak -> fx shock + sparks.
- looks (LOW+MED 1200x540, looked at): fire flames+burning ground, frost dome, gravity pull dome, swarm biters read; shock got fx shock + a blink dome; acid got a low haze + faint
  green shell (was tiny blobs floating 2 m up); shock body yellow (was white like frost). Sheets docs/shots/round7/w119_snake_blasts_low.jpg, _med.jpg, w119_snake_species_lineup.jpg
TESTS AND PERF: test_snake_blasts_w119 PASS (72), OFF=1 FAIL 9/10; test_snake_combat PASS 137; test_controls_w118 PASS.
PERF (once): LOW draws 73 OK; MED 97 OK; HIGH 113 but death spike 173 > 170 OVER. SnakeBlasts draws nothing outside aiming (ring built lazily on first hold);
  the HIGH death spike is not traced to this work (hud_draws 29 on HIGH; other agent edits the HUD at the same time) -> integrator to bisect.
OPEN: weapon wheel did not open from a held WEAPON finger in the probe (w119-hud5 area); SnakeSwarm rows >= 16 decode as rope strands in the shader (MED/HIGH); old BOMBS-wedge throws still aim at the raw camera point.
STATUS: DONE, nothing committed.
