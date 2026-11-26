GOAL: helicopter roster 22+ kinds (own model, flight numbers, icon), test_helis_w125.gd by real touch.
DONE:
- counted before: 3 heli kinds (heli glb, gunship + hauler procedural). Now 23 (20 new, ids h_*).
- godot/tools/gen_heli_roster.py (source table) -> godot/scripts/vehicles/heli_roster.gd (HeliRoster: NEW, KINDS, DEFS, spawn_points, draw_badge)
- godot/scripts/vehicles/heli_models.gd (HeliModels: parametric builder, meshes cached per kind = shared; Detail node hidden beyond 70 m, Glow beyond 160 m)
- lines in vehicle_specs.gd (SPECS/PALETTES/NAMES/ROSTER/AIRCRAFT_KINDS/WEAPONS), audio_director.gd ENGINES (rotor pitch per kind)
- hooks: vehicle_craft_models.build (HeliRoster dispatch), vehicle_visual._bind_craft + vehicle_craft sync (Rotor2), vehicle_spawns.all_points (HELI LINE), flight_hud (badge)
- icons assets/icons/v_h_*.png (tools/icons/build_icons.sh only=...)
- tests/test_helis_w125.gd; lineup renders looked at (front3q LOW + MED)
NEXT: done (report sent)
DECISIONS:
- HELI LINE: airport local x 1334, z -930 + 38*i, not "fixed" (live car cap applies, so a parked line costs at most cap vehicles)
- w125-pads may use HeliRoster.KINDS / NEW to choose kinds for its pads
TESTS AND PERF:
- test_helis_w125 PASS 86 checks; HELIS_OLD=1 fails the [old fails] checks; test_airport_aircraft PASS; test_vehicle_roster PASS
- perf OK: LOW death 107 (limit 108), MED death 146 prims 272k, HIGH death 164
OPEN PROBLEMS: AircraftScenery (air traffic) does not spin Rotor2 (no new kind flies in air traffic yet)
