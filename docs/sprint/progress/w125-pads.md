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
OPEN PROBLEMS:
