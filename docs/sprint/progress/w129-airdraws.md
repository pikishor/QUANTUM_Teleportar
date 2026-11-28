GOAL: airfield / army base / outskirts flight views (in vehicle + on foot) under per-tier draw budgets; MED prims <= 260k; airfield fixes (cockpit panel, wingtips, hangar doors, animals on apron, hangar picker).
DONE:
- read ROUND7, PLAN, ROUND6 rules, HANDOFF.
- NEW tests/test_airfield_perf_w129.gd (needs xvfb renderer) + tools/air_perf.sh [tiers]: 9 views (foot_heli, foot_plane, foot_gates, foot_hangar, foot_base, jet, heli, tank9, flight), boarding by finger, worst of 4 headings.
- NEW tests/dev_w129_airscan.gd: draw cost per subtree (hide/measure) at a view.
- BASELINE MED (old code): foot_heli 220-224 draws, foot_plane 213, foot_gates 215 (budget 140!). Scan foot_heli MED: World/Geometry 46, Wildlife 25, Terrain 17, AirportWorld 13, Mirror 8, ShipWorld 7.
- NEW scripts/world/air_draws.gd (class AirDraws: old = W129A_OLD=1; keep_out(x,z)).
- wildlife_world.gd: no land animals spawn/walk on the airport pad + 30 m (hooks _ring_point, _land_ok, _ground_step).
- hangars.gd: telescopic door panels (panels_of/panel_w/leaf_extent) stacked inside the wall ends (old: 2 leaves sliding 16 m past the walls).
- test_airfield_w129.gd (headless): doors + animals PASS new, W129A_OLD=1 FAIL 4 (the [old fails] checks).
- dev_w129_airscan.gd rewritten: static census + measured toggles (SUN_SHADOW, AirTraffic, Terrain, Vehicles, Geometry, Mirror, ..., CANVAS) + SCAN_SPLIT=<node> per-child cost.
- MED foot_heli toggles (old): CANVAS 41, Geometry 49 (45 EMPTY city MultiMesh families: one draw each, the city-wide custom_aabb), Terrain 18, Airport 17, Mirror 13, AirTraffic 10-12, SUN 10, ShipWorld 8.
- AirDraws.city_cull (hook city.gd _process_body): empty families + the far mirror (camera > 120 m outside the city) leave the layers -> MED foot_heli 198 -> 150, flight 199 -> 154.
- AirDraws.far_merge: aircraft / tank beyond FAR_AT [34,46,60] m = ONE vertex-colour surface (+ turret own far mesh, Run capped); hooks vehicle_visual.gd build/set_paint (var far), aircraft_scenery.gd make; AirDraws.own(visual,on) from vehicle_manager enter/exit (own machine keeps full model).
NEXT:
1. LOW scan (running), canvas per-layer cost, terrain LOD1 2x2 grouping?, tank9 vehicles
2. functional test tests/test_airfield_w129.gd (headless): doors by finger walk, animals, cockpit panel vs pad, readouts, wingtips, hangar picker
3. tools/import.sh (new class AirDraws) before running
DECISIONS: switch W129A_OLD=1 (AirDraws.old) = whole wave 128 airfield.
TESTS AND PERF:
OPEN PROBLEMS: software Vulkan ~1-2 fps under load: air_perf.sh is slow (keep frames low).
