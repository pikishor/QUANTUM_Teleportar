GOAL: w125-pads: helicopter cockpit view (touch VIEW toggle, working gauges) + helipads (city roofs, hospital, police, news, airport, army, outskirts) with map icons, parking on landing.
DONE:
- read code: ArmourSites (pad_east/pad_south ground pads), Airport.pads() (apron, CITY ROOF PAD, mountain, site pads), SettlementData.helipads(), camera veh_view 2 = hood.
- godot/scripts/vehicles/helipads.gd (Helipads: all pads registry, 10 new pads, pad node build near hero, parking), heli_cockpit.gd (HeliCockpit layer 8)
- hooks done: vehicle_spawns.gd all_points, armour_sites.gd (is_fixed, map_markers), vehicle_manager.gd attach, minimap.gd helipad rects, camera_rig.gd view 2 eye
- tests/test_helipads_w125.gd, tests/bot_w125_pads.gd (frames), tests/dev_w125_pads.gd (print list); first day LOW frames looked at: pads OK, cockpit panel overlapped DOWN/UP + plate -> panel moved up (panel_rect)
NEXT:
1 run test_helipads_w125 until green, then W125_PADS_OLD=1 fail-first
2 frames day/night LOW/MED (bot_w125_pads.gd), look
3 perf gate at end (max twice)
DECISIONS:
- Cockpit = heli VIEW button 3rd state (veh_view 2). Family per kind: spec "cockpit" (&"light"/&"military"/&"heavy") if w125-helis sets it, else heuristic (arms2 -> military, len >= 16 -> heavy, else light).
- Pad heli kinds by preference list, first existing in VehicleSpecs.SPECS: hospital [medevac, heli], police [police_heli, heli], news [news_heli, heli], army [gunship], roof [heli]. w125-helis: tell me your ids.
- No fuel system exists: gauge 5 = HULL (hp %).
- Switch W125_PADS_OLD=1 = old behaviour (no new pads/cockpit/parking) for fail-first.
TESTS AND PERF:
- test_helipads_w125: 34/34 PASS (82 s); W125_PADS_OLD=1: 12 FAIL + timeout (cockpit, markers, hospital/police/news/army pads, apron d/e helis, lamps, landings)
- neighbours PASS: armour_w118, flight_view_w116, airport_aircraft, world, touch_buttons_r7, outskirts_settlements, art_library, controls_w118 (1 known flake first run: plane ENTER boarded an SUV; PASS alone)
- PERF_CHECK=1 (once): LOW draws=73 total=95 prims=132k death=108 OK; MED 99/131 prims 242k total 274k death=146 OK; HIGH 118/154 death=164 OK
DONE (final): all steps; NEXT: none (integrator: full suite).
OPEN PROBLEMS:
- no fuel system: 5th gauge is HULL. City roof pads all on 44 m lots (no taller non-walk-in lot 460+ m from the start).
- 'military' family covers gunship + h_attack/h_stealth/h_naval by HeliRoster role; w125-helis may set spec "cockpit" to override.
- 2026-11-26 step: test_helipads_w125 33/33 PASS (new); W125_PADS_OLD=1: 12 FAIL + timeout (old). Fixed: roof clutter pierced raised pads (CityRoofs keeps Helipads.roof_reserve radius clear, also the old CITY ROOF PAD lot).
- pad kinds now w125-helis ids (h_medic, h_police, h_news, h_attack, h_vip); army pads moved to local x 1365 (HELI LINE is at x 1334). Cockpit family by HeliRoster role.
- cockpit panel_rect fixed (button circles read from TouchControls.BUTTONS; earlier list was empty -> panel on DOWN/UP); frames f3 looked at 1200x540 + 2400x1080 day/night: clear of buttons.
- roof billboards skipped on pad lots (rng draws kept). test_helipads_w125 34/34 PASS (82 s).
- NOW: neighbour tests (armour_w118 controls_w118 flight_view_w116 airport_aircraft world touch_buttons_r7 outskirts_settlements art_library), then perf gate once at end.
