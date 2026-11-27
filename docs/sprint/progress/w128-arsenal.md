# w128-arsenal progress
GOAL: 36 carried switchable weapons (wheel, quick-swap, favourites, save, demo) + realistic BlastFx; tests test_arsenal_w128.gd, test_blastfx_w128.gd.
DONE:
- ARSENAL (done, tested): scripts/player/loadout_slots.gd COUNT 36 (first 4 named + PREF; slots 5-36 carry every non-starter owned weapon, round-robin by class when more wait;
  ensure() cached by signature; PAGE 4 + page/flip_page; W128A_OLD=1 = old 4 slots). scripts/ui/arsenal.gd bar: 4 slots of the page + page chip `ars_slotpage`, opens on active page.
  weapon_browser.gd FAV_MAX 36. player_weapon.gd / progress.gd comments. Wheel unchanged (class rings + FAV already reach every owned weapon; a CARRIED wedge would break 5 older count tests).
- tests/test_arsenal_w128.gd PASS 20/20; W128A_OLD=1 FAIL 12 of 18. test_weapon_ui_v3 slot-count line now compares a PAGE on screen (spec change, noted).
- Related PASS: weapon_ui_v3, weapons_v3, weapons_depth, play_critic_w114, director_round4_b, weapons, melee_gadgets, touch_buttons_r7, weapon_roster.
- BLASTS: before renders done (scratchpad bx/before q0,q1; 12 ids x 6/14/28 m x 3 moments). Before look: pale orange additive haze, pink translucent smoke, neon ring, glass dome.
- assets/shaders/fx_fire.gdshader premul + `soot`; fx_ground.gdshader premul + `dust`/`dust_col` skirt (0 = old exactly).
  scripts/fx/explosion_pool.gd: real look for fire/toxic (soot, dust by ground, dark smoke, wind drift, longer smoke/skirt).
  scripts/combat/blast_fx.gd: real_on (W128B_OLD), WIND, ground_kind/ground_y/dust_color/smoke_tint, _real() (column, skirt, dirt plume, concrete sparks, water splash no scorch), _sound_layers (debris/distant_boom/splash), thermobaric dome toned.
- tests/test_blastfx_w128.gd PASS 12/12; W128B_OLD=1 FAIL 8 of 12.
- Iteration renders looked at (bx/it2): soot crown on the fireball, grey dust skirt, dark drifting column (was pale pink haze). Tuned: column 3/4/5 puffs, concrete dust darker, _real before _extras, pale old column off when real, pool smoke glow fades with the fire.
- legacy Game.explode callers (deaths, cars) get the pool soot/dust only, no cloud puffs (death spike; test_vfx PASS).
- Arsenal look: scratchpad ars/01_slots36.png (2400x1080) OK. bot_arsenal.gd opt-in step slots36; bot_blast_arsenal.gd BX_GROUND=soil|water.
- Full after renders looked at: LOW+MED 12 ids x 6/14/28 m, soil and water variants. Sheets docs/shots/blasts_w128_low_a/low_b/med/ground.jpg (before | after).
NEXT: done (integrator: full suite).
DECISIONS: LoadoutSlots.COUNT=36, PAGE=4, NAMED=4, used(), carried(), OLD (W128A_OLD); Arsenal id ars_slotpage; BlastFx.real_on (W128B_OLD), WIND, ground_kind(), last_ground, last_layers.
TESTS AND PERF: test_arsenal_w128 PASS (OLD 12 FAIL), test_blastfx_w128 PASS (OLD 8 FAIL); related weapon/blast/vfx tests PASS.
  PERF (1 run): LOW draws=72 total=94 death=109 OK; MED draws=99 total=131 prims=274k death=146 OK; HIGH draws=118 total=154 death=164 OK.
OPEN PROBLEMS: Arsenal bar hit height 43.3 px at 844x390 (BACK too, older); Gear.SLOTS (4 gear presets) left at 4; no CARRIED wedge on the wheel (would break 5 older wedge-count tests; class rings + FAVS reach every weapon); depth charge on a street still shows its neon ring (water recipe).
