GOAL: airfield / army base / outskirts flight views (in vehicle + on foot) under per-tier draw budgets; MED prims <= 260k; airfield fixes (cockpit panel, wingtips, hangar doors, animals on apron, hangar picker).
DONE (switch W129A_OLD=1 = AirDraws.old = every fix off):
- scripts/world/air_draws.gd (class AirDraws): keep_out (animals), city_cull (empty city MultiMesh families + far mirror out of the layers; hook city.gd _process_body),
  far_merge/own (aircraft + tanks one vertex-colour mesh beyond FAR_AT [34,46,60] m, turret own far mesh, Run capped; hooks vehicle_visual.gd build/set_paint var far,
  aircraft_scenery.gd make, vehicle_manager.gd enter/exit), terrain_groups/_far_groups (LOD1 chunks + far tiles joined 2x2; hook terrain_world.gd _process),
  ground_traffic_far (air_traffic.gd), readout/cockpit_on/speedo_drawn/last_rows (hud.gd, flight_hud.gd), SHIP_PART_FAR/GANGWAY_FAR (ships/ship.gd)
- wildlife_world.gd: no land animals / songbirds on the airport pad + 30 m
- hangars.gd: telescopic door panels inside the wall ends (panels_of, panel_w, leaf_extent, Doors.leaf_xf) + makes HangarPicker
- NEW scripts/world/hangar_picker.gd (HangarPicker): PLANES chip (top left beside the minimap) inside a hangar/shelter, list of planes that fit, pick rolls it out in front of the door
- heli_cockpit.gd: stick_zone, frame_shapes, pad_overlaps, _clear_pillar: no cockpit shape over the move pad (16:9 and 20:9)
- flight_hud.gd: batched pen (one triangle list + words), labels record, enabled flag (probes); no ALT/HDG labels in the cockpit
- shadow_proxy.gd: coarse_skinned: hero shadow 16393 -> 3875 tris (MED triangle headroom)
- tests: NEW test_airfield_w129.gd (headless; parts shadow doors animals picker cockpit) PASS, W129A_OLD=1 FAIL 11 (every [old fails]);
  NEW test_airfield_perf_w129.gd + tools/air_perf.sh (xvfb), run by tools/perf_report.sh with PERF_CHECK=1 (PERF_AIR=0 leaves it out)
  test_perf_budget.gd: proxy check accepts the coarse copy with the same vertices (still skin + skeleton)
- dev: tests/dev_w129_airscan.gd (draw census/toggles/canvas), dev_w129_lines.gd (wingtip/rotor clearance probe, SOLVE=2), bot_w129_air.gd (frames)
- WINGTIP layout tried and REVERTED: shifting the big line planes east (runway gap 12 m) put their wings over the walk-up path to the heli line (hero boards the plane: test_helis_w125 h_heavy/h_fire) and the helis cannot move east in front of the shelter lanes. Needs a re-layout (big planes outside the shelter-lane bands z -759..-650 / -559..-450).
TESTS AND PERF: see report. Other tests run after the changes: airlook_w128, helis_w125, planes_w126, w126_critic, airport_aircraft, perf_budget, terrain_world, machanim_w129, world_hud, vehicle_roster, air_w126, tanks_w127, flight_view_w116: PASS
NEXT: final frames (picker, cockpit, doors), final air_perf 0 1 2 + PERF_CHECK gate, report
OPEN PROBLEMS: LOW airfield views still over 100 (+touch allowance) in vehicles: the HUD canvas is 40 (foot) to 70 (jet) draws; jet hood view shows a blue canopy dome mid-screen.
