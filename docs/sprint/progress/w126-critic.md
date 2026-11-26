# w126-critic log (independent review + fixes of wave 126: plane roster, hangars, air traffic, air missions, aircraft weapons)
GOAL: finger-only bot in real main scene; list 8 worst defects; fix most severe first with fail-first checks. STATUS: DONE (report sent).
DONE
- godot/tests/bot_w126_critic.gd: headless finger probe (CRP_PARTS line,fly,missions,traffic,terrain,ff; CRP_KINDS; CRP_MISSIONS). Runner caps 140 s: one kind per process.
- godot/tests/bot_w126_critic_look.gd: frames + flight draws (CL_PARTS rain,views,board,fly) via tools/bot.sh 1200x540.
- flown by finger (taxi from own place, take-off, circuit, landing, brake): p_duster p_jumbo p_fighter p_twin p_regional p_attack p_bomber p_glider p_sst p_cub: all land on the runway.
- missions finished by the finger bot: SKY RINGS, DOGFIGHT, BOMB RUN, AIRLINER ESCORT.
- FIX 1 shelters boxed in by PLANE LINE + HELI LINE: tools/gen_plane_roster.py LANES + first-fit + RUNWAY_GAP 6 -> plane_roster.gd PLACES regenerated (only PLACES changed).
- FIX 2 airport traffic collisions: air_traffic.gd separate/_must_wait/runway_busy/blocked_ahead/runway_vehicle/_landing_conflict/stand_taken/go_arounds.
- FIX 3 nearest fixed spawn first: vehicle_manager.gd _tick_spawn_points + _spawn_point (fixes test_helis_w125).
- FIX 4 radio portrait over the landing guide in flight: story_view.gd badge_rect (no portrait while FlightHud shows), flight_hud.gd guide_rect.
- FIX 5 rain inside hangars: hangars.gd under_roof + atmosphere.gd hook.
- FIX 6 crossers flew past local x 3000 (test_airport_aircraft failed by chance): air_traffic.gd _new_line clamp 2900.
TESTS AND PERF
- tests/test_w126_critic.gd PASS (~60 s); W126C_OLD=1 + old PLACES: 8 FAIL; hud part 3 FAIL old; rain part 1 FAIL old.
- PASS: helis_w125, helis_w125_b, planes_w126 (+_b,_c,_d), airport_aircraft, air_w126, air_w126_b, armour_w118, world_roam, radio_ui, w125_critic, floors_w121, helipads_w125.
- perf (PERF_CHECK=1, once): LOW draws=73 total=95 death=108 OK; MED 99/131 prims 275k death=146 OK; HIGH 118/154 death=164 OK.
- flight draws (look bot, 1200x540): LOW 109-118, MED 137-145.
DECISIONS
- W126C_OLD=1 turns off fixes 2-5 (VehicleManager.W126C_OLD, AirTraffic.separate, StoryView.badge_fix, Hangars.rain_fix).
OPEN PROBLEMS (not fixed)
- mountains 600 m north of the runway: heavy planes taking off north fly into them (no terrain warning).
- glider: dark pilot figure sits on top of the canopy.
- big-heli rotor discs reach into the shelter taxi lanes (1 m wing clearance in the check).
- traffic flow lower (6-9 take-offs per 15 min instead of 10) because of go-arounds and holds.
