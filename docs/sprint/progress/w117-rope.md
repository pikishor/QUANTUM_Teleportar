# w117-rope progress log
GOAL: braided rope of several snakes for swing + zip (one draw), zip that never ends hanging, no-anchor cue + anchor marker, flight energy warning, MED rain in flight under 4 %.
DONE (all uncommitted, paths under godot/):
- BRAID: scripts/quantum/snake_tendril.gd (opt "braid": 3; braid_open / braid_radius / braid_pitch, _braid_step; static braided_rope = old-look switch; a braid retracts in >= 0.3 s),
  snake_tendril_pool.gd (each strand = one more INSTANCE of the same MultiMesh, BRAID_TIERS rings/sides, BRAID_EXTRA 6 instances, `instances` counter; plait data in the alpha of
  texels 0..4 of the row), assets/shaders/snake_tendril.gdshader (strand = INSTANCE_CUSTOM.x / 16; plait(), plait_r(): spread before the anchor, heads close on the bite; 3 skins).
  Hook lines "braid": 3 in snake_swing.gd (fire line) and snake_zip.gd (2 fire lines).
- ZIP END: snake_zip.gd: wall end -> edge_above() -> phase `haul` (up the facade, over the edge, stands; end_reason hauled) or _drop() (end_reason drop, line "NO LEDGE ABOVE  DROPPED");
  JUMP in a haul leaps off. static SnakeZip.wall_end = false is the old hang. Probe (W116_PROBE=zip dev_w116_air_touch): 8 of 8 wall zips end standing on a roof (was: hang in CLIMB).
- CUES: snake_fx.gd (SnakeFx.current, cues_on switch, zip_mark, cue_text/cue_t "NO ANCHOR", energy_warn 1/2 + beeps + toast, static hud_cues() draws into TouchControls' lists);
  hooks: snake_traversal.gd (var zip_target + 1 line in _preview, 3 lines in button_label), ui/touch_controls.gd (1 line before the glows are drawn).
- RAIN: fx/atmosphere.gd (_air_step: lens rain fades out in the air, static air_clear switch), fx/atmosphere_rain.gd (AIR_SHARE streak share MED 0.4 HIGH 0.25, var air).
- tests/bot_w117_rope.gd (look bot, real fingers; W117_OUT, W117_PARTS=rope,zip,cue,energy, W117_OLD=1).
- POSE: snake_pose.gd: haul pose (upright, hand on the rope); the pull pose turned him HEAD DOWN in the haul (seen in my own frames). Switch SnakePose.haul_upright.
- HUD cost: hud_cues() adds rows to TouchControls' `sprites` (the &"button" sprite: rings and plates) and `labels` (sizes 32 and 22 the buttons already use): no draw call more;
  on the ground the old 3D marker billboard is NOT shown any more when zip_mark is up (one draw less on MED / HIGH there).
- Zip reach: SnakeZip.haul_max 140 m (static), HAUL_TIME_MAX 3.2 s; edge_above() about 20 rays per facade, cached per target in SnakeFx (_mark_key).
- tests/test_rope_w117.gd: 25 checks PASS (69 s), every part has an OLD trial that fails with its switch off. tests/dev_w117_spots.gd = probe (why a wall has no ledge).
- LOW frames looked at (scratch r1): braid reads as 3 snakes (cyan, green, violet), unwinds on release; marker, NO ANCHOR and energy cues readable after plates were added.
- Shader trap fixed: pow(negative, 2.0) = NaN glued the three heads into one (seen in the still fixture, W117_PARTS=still). Heads now three, necks apart, tips on the anchor.
- Haul costs energy by the metre (SnakeZip.HAUL_COST_M 0.3): keeps test_snake_traversal "a zip costs a little snake energy" true. test_flight_cost_w116: its OLD trial now also
  sets SnakeZip.wall_end = false (the old code = straight pull + hang), the check itself is unchanged.
- Frames: docs/shots/round7/rope_w117/{low,med} (33 each), sheet docs/shots/round7/rope_w117.jpg, looked at.
- ARCHITECTURE.md section "Wave 117 rope" and HANDOFF.md section "Wave 117 rope" written.
- flight_view.sh (FV_SCENES=swing,zip,rain, out scratch w117rope_fv): LOW 7 of 7 PASS (rope 1.6 to 2.2 % of the centre, rain 0.3 to 0.4 %); MED running.
- Atmosphere._air_step sets the lens rain every frame (the flight bot's capture restored it to full and MED rain_boost read 13.8 % again).
- flight_view.sh FV_SCENES=swing,zip,rain: LOW 7 of 7 PASS, MED 7 of 7 PASS (rope 1.6 to 2.2 % of the centre; MED rain 0.14 / 0.18 %, was 13 to 14 %).
- Frames converted to jpg. TASK DONE; nothing committed.
NEXT: nothing (integrator: tools/import.sh not needed, no new class_name).
DECISIONS: switches (all static, default new): SnakeTendril.braided_rope, SnakeZip.wall_end, SnakeZip.haul_max, SnakePose.haul_upright, SnakeFx.cues_on, Atmosphere.air_clear.
 SnakeTraversal.zip_target (set in _preview) is read by SnakeFx; SnakeTraversal.button_label asks SnakeFx.label_cue() first. Zip phases: pull, haul, land; end_reason hauled / drop / leap.
 The scratchpad dir is shared with other agents: use names with w117rope_ in them.
TESTS AND PERF: perf gate (one run, clean user dir): LOW draws=70 total=92 death=107 OK; MED draws=97 total=129 death=150 OK; HIGH draws=113 total=149 death=169 OK.
 PASS (one clean user dir each): test_rope_w117 (25), test_snake_traversal, test_flight_view_w116, test_flight_cost_w116, test_critic_w116, test_play_critic_w115,
 test_snake_swing_run, test_snake_combat, test_atmosphere, test_touch_audit, test_hud, test_world_hud, test_touch_buttons_r7.
 RED, not mine: test_critic_look_w115 "the trial reproduces the old fling: a rope debt ..." (swing physics, snake_swing.gd is being edited by w117-swing).
OPEN PROBLEMS: roof zips still cover 25 to 40 m in 0.3 s (flight log #3); one roof zip of 10 in the w116 probe ended on the street; cues are touch HUD only.
