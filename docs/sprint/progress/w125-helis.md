GOAL: helicopter roster 22+ kinds (own model, flight numbers, icon), test_helis_w125.gd by real touch.
DONE:
- counted existing heli kinds: 3 (heli = xv_heli glb, gunship + hauler = procedural, VehicleSpecs cls "heli").
NEXT: 1 tools/gen_heli_roster.py writes scripts/vehicles/heli_roster.gd (DEFS) + spec/palette/name/roster/weapon/engine lines
 2 scripts/vehicles/heli_models.gd (HeliModels: parametric builder, mesh cache per kind) + hook in VehicleCraftModels.build
 3 Rotor2 hook (tandem/coax/tilt) in vehicle_visual._bind_craft + vehicle_craft sync + aircraft_scenery
 4 HELI LINE spawn points at the airport east of the runway (local x 1330, z -940..-180, 40 m apart)
 5 icons (tools/icons/build_icons.sh only=v_...), FlightHud name+icon line
 6 tests/test_helis_w125.gd (touch: walk, ENTER, UP, route, DOWN, EXIT per kind), HELIS_OLD=1 shows old fail
 7 lineup renders LOW+MED, perf at end
DECISIONS:
- new kind ids start with h_ (h_scout ...); data table in godot/tools/gen_heli_roster.py (source of truth), HeliRoster.KINDS lists all heli kinds for w125-pads.
TESTS AND PERF:
OPEN PROBLEMS:
