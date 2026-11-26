GOAL: aeroplane roster 30+ kinds (model, flight numbers, icon), hangars (airport + army airbase) enterable on foot with boardable parked planes, test_planes_w126.gd by real touch.
DONE:
- counted before: 5 plane kinds (plane, jet, cargo, airliner, bizjet; cls "plane" in VehicleSpecs). Now 33 (28 new, ids p_*).
- tools/gen_plane_roster.py -> scripts/vehicles/plane_roster.gd + marker blocks (w126-planes BEGIN/END) in vehicle_specs.gd (SPECS/PALETTES/NAMES/WEAPONS, ROSTER/AIRCRAFT_KINDS arrays) and audio_director.gd ENGINES
- scripts/vehicles/plane_models.gd (PlaneModels, 356-1328 tris per kind, cached meshes, Detail < 70 m, Glow)
- hooks: vehicle_craft_models.build, vehicle_visual._bind_craft (PropB..D + discs), vehicle_craft.sync (spin PropB..D), aircraft_flight (spec "roll"/"pitch"), armour_sites.is_fixed (PlaneRoster.owns), vehicle_spawns.all_points
- scripts/world/hangars.gd (Hangars + Hangars.Doors): shells in AirportKit.kit, boxes in AirportWorld._collision, doors MultiMesh + AnimatableBody leaves
- lineup render front3q looked at (scratchpad sheet1.png): all 28 read as distinct planes
NEXT:
DONE (report sent). Bot frames looked at (tests/bot_w126_planes.gd, LOW + MED). Icons assets/icons/v_p_*.png. (tools/icons/build_icons.sh only=v_p_...), test, renders, perf
DECISIONS (other agents may use):
- PlaneRoster.NEW (28 new ids p_*), PlaneRoster.KINDS (all 33 plane kinds), PlaneRoster.DEFS[kind] = {name, role, m}; role strings: light, trainer, aerobatic, crop duster,
  seaplane, bush, light twin, regional, narrow-body, wide-body, jumbo, freighter, fighter, interceptor, ground attack, bomber, stealth bomber, stealth fighter, tanker, AWACS,
  recon drone, combat drone, glider, racer, flying boat, supersonic, sci-fi
- spec keys new (optional, AircraftFlight reads them, old kinds unchanged): "roll" (1/s bank response), "pitch" (rad/s pitch rate), "run" (m takeoff run, info only)
- PLANE LINE: airport local x 1307, nose north (local h 0), along z from -935 southward (between runway and w125 HELI LINE x 1334); point ids "pl_<kind>", FIXED (outside the car cap)
- hangar_a: p_cub + p_biplane, hangar_b: p_trainer + p_racer (ids "hg_<kind>"); ARMY shelters at local (1360, -760) and (1360, -560), doors south: p_fighter, p_stealthf
- w126-air owns traffic/missions/weapons: armed new kinds get a basic gun line in VehicleSpecs.WEAPONS only; replace freely.
TESTS AND PERF:
- tests/test_planes_w126.gd (data + hangar A + army shelter 1 by fingers) + _b/_c/_d (flights: walk, ENTER, take-off, bank, land on runway 09, brake, EXIT), all PASS 32/89/83/81 s
- W126_PLANES_OLD=1: main 4 [old fails] FAIL, _d 9 of 9 FAIL (kinds not found)
- fixes found by the test: parked jets ap_jet_a/b + ap_gunship moved off the hangar door lanes (airport.gd SPAWN_LOCAL); takeoff start past ap_runway plane
- test_airport_aircraft, test_armour_w118, test_vehicle_roster PASS (vehicle_roster prints an old NearTraffic process_mode SCRIPT ERROR, not mine)
- PERF_CHECK=1 perf_report 0 1 2: LOW draws=76 death=107 OK; MED draws=99 prims=243k (total 275k) death=146 OK; HIGH draws=118 death=163 OK
OPEN PROBLEMS:
- flight check is a runway hop (take-off, bank/turn, land on the same runway), not a full circuit: the 140 s runner cap; a circuit of the slow kinds took 100+ s real each
- rain falls inside the hangars (engine-wide rain ignores roofs); hangar interior dark; open door leaves stick out past the side walls
- PLANE LINE wingtips 4-12 m from the runway edge: a plane drifting off the axis on the roll can hit them
- the pilot figure sits on top of the glider / small open models (seat position is generic)
