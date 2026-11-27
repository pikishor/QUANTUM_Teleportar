GOAL: w128-airlook: every helicopter and plane kind looks like a believable real-world type (layout/proportions), plus hangar light, wingtip clearance, parked sink, cockpit panel, traffic, hangar picker, parachute; test_airlook_w128.gd.
DONE:
- read ROUND7, PLAN_116_150, ROUND6 rules, HANDOFF tail
- before frames: viewer side/front3q of all 23 helis + 33 planes (scratchpad before/), game frames bot tests/bot_w128_air.gd (HELI/PLANE LINE, hangar A, shelter)
- ROOT CAUSE FOUND: VehicleCraftModels._tri winds triangles CCW seen from outside; Godot fronts are CW -> every procedural craft (helis, planes, tanks, quad, scooter, jetski, patrol, gunship, hauler) drawn INSIDE OUT
  (near skin culled, inner far wall shown: flat look, glass invisible, fins seen through the body = "fins in the middle"). Fix in VehicleCraftModels._finish (reverse order); W128_OLD=1 = old.
- aircraft_models.gd: smooth loft normals (`smooth`), `_patch` (skin patches: windscreens, windows, seams), `_grid`, `_tri_n`, `ring_point`, `_panel` moved here from PlaneModels; glass_material()/air_glass() (tinted canopy glass)
- heli_models.gd: _geom2 (pod stations, framed windscreen + chin + door windows, seams, engine cowling + intakes + exhausts, mast/swashplate, swept fin at boom END, tail rotor on left of fin, stabiliser, bumper, skids with toes); _rotor2 (tapered blades, grips), _tail2 (2-5 blades); Body_LOD1 (far body) beyond LOD_AT 42 m; tri_count skips LOD1
- vehicle_visual.gd: aircraft glass hook (one line in _bind_craft)
- plane_models.gd: smooth skin, Body_LOD1, params() + W128_FIX (wing area narrow/wide/jumbo), _glass2 (airliner cockpit band + posts + passenger windows + doors; light-plane windscreen + side windows), bubble canopy as top patch + frame, glazed nose patch, jet pods clear the ground
- heli: params() + W128_FIX (h_ultra boom 4.1), fin clamp under the disc, cowling under the hub
- air_traffic.gd: more_on (6 crossers, pad helis cycle APRON_A/B/C new kinds)
- hangars.gd: OmniLight lamps per hangar (2) / shelter (1), on within LAMP_NEAR 90 m (lights_on)
- tests/test_airlook_w128.gd: NEW PASS 51/51 (75 s); W128_OLD=1 FAIL 50/51 (the parked-on-ground guard passes on both: sink NOT reproduced, 47-48 parked aircraft on the field)
- classic "heli" now HeliModels.CLASSIC build (vehicle_visual + aircraft_scenery hook; its glb was an open frame without glass)
- air_rockets.gd: parachute canopy + cords over falling cargo crates (chute_on)
- docs/shots/aircraft_w128.jpg: before/after front3q of all 56 kinds (MED viewer); game frames MED 1200x540 looked at (lines no longer glow inside-out)
- tests PASS after changes: helis_w125, planes_w126, air_w126, airport_aircraft, tanks_w127, airlook_w128 (52 checks)
- perf (PERF_CHECK=1, run once, no limit touched): LOW draws=75 total=97 death=107 OK; MED draws=99 total=131 prims=274k death=146 OK; HIGH draws=118 total=154 death=164 OK
- final: test_airlook_w128 PASS 52/52; W128_OLD=1 FAIL 51/52 (the parked guard passes on both); w126_critic PASS
NEXT:
- done (report sent)
- NOT DONE: wingtip clearance (no room between runway edge 1284 and heli line 1334: needs a re-layout), cockpit panel / duplicate readouts, hangar plane picker
DECISIONS:
- switch W128_OLD=1 (winding + heli/plane builds)
TESTS AND PERF:
OPEN PROBLEMS:
- tanks/quad/etc also change look with the winding fix (they were inside out too): check frames
