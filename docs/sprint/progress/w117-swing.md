# w117-swing
GOAL: rebuild the snake swing motion + input (pendulum, release, chain, jump boost, no walls, no stuck), test godot/tests/test_swing_w117.gd by real fingers.
DONE:
- read docs.
- godot/scripts/quantum/swing_motion.gd (NEW, class SwingMotion; tools/import.sh run): planar pendulum (pivot = anchor moved into the travel plane), rope only gets shorter
  (slack take-up + reel 16 m/s to keep the arc off the street), assist toward bottom_speed() (no multipliers), release rules (finger up / JUMP / auto at 0.62 rad / tap = whole swing),
  wall + floor + still-rope ends, lowering, planar arc check + anchor score.
- snake_swing.gd: hooks (old_motion, pivot, lowering, last_why, wraps, JUMP in the travel phase); snake_anchor.gd: new score, PITCHES_NEW, no search beside/behind, a chain turns
  45 / 85 degrees only near the ground with nothing ahead, hit["dir"]; snake_traversal.gd: _heading (look + stick), chain re-fire at the top of the throw, no double move in the
  release tick (was 0.95 m in one tick), a press between two swings waits for an anchor (CHAIN_WAIT 3 s) instead of starting FLIGHT, no flight out of a held chain, air brake +
  landing roll after a swing (_post_swing).
- tests/test_swing_w117.gd: NEW motion PASS 38/38; SWING_OLD=1: 13 FAIL (even release speed 18.9-38.0, direction, fling 1.17 m/tick, rhythm 0.0-2.0 s, tap = 0.55 s twitch,
  jump re-fires a rope, 10.9 m sideways pull, stick steers the wrong way, braked rope never comes down, ...). tests/dev_w117_anchors.gd = probe (old/new picks along the avenue).
- old tests: test_snake_swing_run PASS (9 / 11 swings, 520 m); test_snake_traversal 132 of 133 (FAIL "a zip costs a little snake energy": zip is the rope agent's file, not touched here).
- strip of one swing rendered and looked at (LOW 1200x540, tests/bot_w117_swing.gd): docs/shots/round7/swing/swing_w117_strip_low.jpg. Seen and fixed from it: a rope capped at
  28 m lifted the hero 12 m per swing (ROPE_MAX 36, score likes <= 28); thumbs off after a release the hero stopped dead in the air (air_k_scale in _post_swing).
- HANDOFF section "Wave 117 swing" written.
- final: test_swing_w117 PASS 38/38 (3 runs), SWING_OLD=1 FAIL 13; old tests PASS: test_snake_swing_run, test_play_critic_w115, test_flight_view_w116, test_critic_w116, test_snake_combat.
TESTS AND PERF (gate run once, clean XDG_DATA_HOME): LOW draws=73 death=107 OK; MED draws=97 death=148 OK; HIGH draws=113 lights=7 death=169 OK.
OPEN PROBLEMS:
- test_snake_traversal "a zip costs a little snake energy" FAILS (1 of 133) in the shared tree: the zip is the rope agent's file (snake_zip.gd), not touched here; integrator to check.
- defects 1-5 (zip) left to w117-rope; 11-15 (FLY on the ground, LAND, energy warning, DOWN button, BOOST beside RELOAD) not touched: flight / layout.
- a chain still climbs toward the roofline on long holds (then waits in free fall for an anchor); swings on ropes under 10 m are quick (0.5 s).
TASK ENDED. Nothing committed.
NEXT: (none)
DECISIONS (other agents read this):
- New motion lives in a NEW file godot/scripts/quantum/swing_motion.gd (class SwingMotion, static functions on a SnakeSwing); snake_swing.gd only gets hook lines + a few vars
  (static SnakeSwing.old_motion = wave 116 motion; `pivot` = the point the pendulum turns about; `anchor` stays the point on the building the ROPE IS DRAWN TO).
- I do NOT touch snake_zip.gd, snake_tendril*.gd, snake_fx.gd, the cue texts: the rope agent owns them (zip that never ends hanging, zip speed, NO ANCHOR cue).
- Engine.time_scale N makes the physics dt N/60 (not more ticks): tests that want real 1/60 ticks at speed set Engine.physics_ticks_per_second = 60 * N too.
