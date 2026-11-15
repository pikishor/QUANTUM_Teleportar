# w115-critic-play (independent critic and fixer, lens PLAY = function, feel, measured behaviour)

Started 2026-11-15 07:50Z. Reviews the work of w115-snake-traversal and w115-snake-combat (both DONE, nothing committed yet; the integrator comes after the critics).
A second critic (LOOK lens) works in the same tree at the same time: read each file again right before editing, small edits, never revert others.
STATUS 11:03Z, FINISHED: the 8 defects below are fixed (D8 partly), each with checks in tests/test_play_critic_w115.gd (76 checks, mutation-checked); perf gate LOW / MED / HIGH all OK; 42 related tests pass.
Probes godot/tests/dev_w115p_*.gd and bots bot_w115p_*.gd (a scratchpad helper runs a probe with its own timeout: direct godot call with --timeout=N; tools/test.sh stops at 150 s).

DEFECTS (measured) AND STATUS, worst first
D4 FIXED  FUNCTION  arming a snake power from the weapon wheel put the gun away and NOTHING brought it back: swap, number keys and the wheel left holding() true, every new gun was holstered and silent
          (measured: ammo 15 -> 15 with FIRE held). SnakeWar.holster() from PlayerWeapon.poll_switch, WeaponWheel.activate and the weapon_changed signal; one-time hint TAP WEAPON  YOUR GUN COMES BACK (ES, HI).
D1 FIXED  FEEL      a TAP of SNAKE in the air (0.05 - 0.20 s, a thumb) fired the snake and cancelled it before it bit (0 of 5 taps bit, no feedback): the shot is committed, every swing hangs TAP_HANG 0.55 s.
D3 FIXED  MISSION   the tutorial SWING ACROSS THE CITY ends with FLY and LAND, impossible on HARD and QUANTUM without a WING POWER rank (5 skill points): flight is open while it runs (SnakeMissions.tutorial_running).
D2 FIXED  MISSION   SnakeWarMissions.inject replaced a world mission on the lodge board (test_world_missions failed "a world mission every time"): it skips world and snake picks now.
D7 FIXED  FUNCTION  the snake hunter was put at a random spot 30 m away: 10 % inside a building, 8 % behind a wall (it could never fire): up to ten tries at 22-34 m, level, outside colliders, clear line.
D6 FIXED  FEEL      the first swing, verb and bomb compiled 15 pipelines on the spot (a phone driver stalls 10-50 ms each): SnakeWarm (called by ShaderWarmup.run) draws every snake visual once and puts it back: 6 left;
          the first swing still compiles about 8 (the view from 40 m up and light-count variants, not snake materials): open. The perf gate does not run the warm-up: dev_w115p_leftover.gd diffs the tree around it.
D5 FIXED  ROBUSTNESS snake_pose.gd printed `Basis must be normalized` (the builder's open item, a zip to a car): the pose basis is checked, orthonormalized, falls back to the yaw basis.
D8 PARTLY FEEL      the tutorial's swing legs: in 7 of 12 roof legs nothing is above the roof edge, the held button turned into a flight (step done, but not the thing it teaches): SnakeMissions.swing_possible runs the
          SNAKE fan from 2.5 m past the edge, _pick_swingable picks level roofs (<= 8 m higher) with an anchor: 18 of 33 first legs have one (11 before); none in ~45 % of the boards: the old pick stays.
          Legs probe (30 s per leg, a crude pilot): swing legs 10 of 18 reach the ring, flight legs 12 of 15; uphill swing legs 2 of 15, which is why uphill roofs are not picked.
NOT FIXED / OPEN: mega bomb ring 20 m, damage ends near 14-16 m (the ring over-promises); fx_threat.gdshader stealth pips drawn as white plates (not wave 115 code); first-swing view compiles (D6).
The LOOK critic fixed two items of my first open list: the camera lens jumps (real, not a harness artifact) and the glow that only the combat powers drove.

(measured OK) 427 roof rings of 122 built missions lie on standable roofs; wall climb 45 of 45 buildings; NORMAL flight take-off / cruise 34 m/s / LAND 2.1 s, no damage; boosted flight 60 m/s over
  the outskirts (3500 m, no fall through); death and respawn in swing, climb, flight, shield, grab leave nothing behind; tier switches mid swing / flight / snakes are clean; 64 verb x enemy trials against
  LIVE enemies: no error, no stuck hold, no sunk enemy; twelve bomb rings = table radii, hero outside the ring unhurt; anchor search 0.5 ms (full), 0.29 (preview); street start: 7-13 swings and
  900-1500 m in 40 s, no position jump, no reversal; 59 of 60 street taps on SNAKE zip; monkey 34 episodes x 20-25 s with combat and traffic: no stuck state, no non-finite value, no script error of ours.

DONE (files)
- EDITED scripts/quantum/{snake_swing,snake_war,snake_war_missions,snake_power,snake_missions,snake_mission_director,snake_pose,snake_fx,snake_react}.gd, scripts/player/player_weapon.gd (poll_switch),
  scripts/ui/weapon_wheel.gd (activate), scripts/common/{strings_snake_war,shader_warmup}.gd (one hint ES + HI; two hook lines), NEW scripts/quantum/snake_warm.gd
- NEW tests/test_play_critic_w115.gd; probes tests/dev_w115p_{rings,legs,input,clock,monkey,chain,verbs,bombs,arm,death,tier,zipcar,matwarn,terrain_fly,scancost,groundtap,lowwall,hunter,climb,water,load,
  swingpick,leftover}.gd, bots tests/bot_w115p_{run,firstuse,firstuse2,firstuse3}.gd; ARCHITECTURE.md and HANDOFF.md sections "Wave 115 critic, PLAY lens"

DECISIONS (other agents depend on)
- SnakeWar.holster() is the way to put a snake power away for a gun; anything that equips a gun should call it (or switch_to, which signals).
- SnakeSwing.TAP_HANG (0.55 s) is the minimum hang of every swing; a swing always bites once the head is out.
- SnakePower.flight_unlocked() is true while SnakeMissions.tutorial_running.
- A snake visual that is made lazily or draws nothing while idle must be added to SnakeWarm.begin (and put back in end()).

TESTS AND PERF
- tests/test_play_critic_w115.gd PASS (76 checks, ~60 s); mutation runs: removing each fix fails its checks (last one: _pick_swingable off -> 2 checks fail).
- PASS after the last edit: test_snake_traversal, test_snake_combat, test_snake_swing_run, test_world_missions, test_hero_polish, test_perf_budget, test_critic_look_w115, test_localisation_complete / depth, 11 weapon and
  wheel tests (ui_v3, v3, roster, weapons, feel, altfire, director_round4_b / 5_b, available_display, energy_destructive_weapons, play_critic_w114); 22 more that touch the weapon switch, the
  mission board, the HUD or the skills (mission_board, menu_cut, director_round5_a, story_acts, world_roam, activities x2, audio x2, blast_arsenal, energy_destructive_scene, rewards_progression,
  shooting_accuracy, weapon_attachments / cards / crafting, weapons_depth, wiring_followups, hud_camera_final, hud_declutter, new_verbs, skill_tree): 42 related tests, all PASS.
- perf gate (PERF_CHECK=1 tools/perf_report.sh 0 1 2, once, 10:07-10:16Z; the later edits draw nothing):
  PERF RESULT tier=0 LOW  draws=71 total_draws=93 tex_mb=112 death_draws=107 verdict=OK
  PERF RESULT tier=1 MED  draws=97 total_draws=129 tex_mb=143 death_draws=149 verdict=OK
  PERF RESULT tier=2 HIGH draws=113 total_draws=149 tex_mb=209 death_draws=169 verdict=OK
