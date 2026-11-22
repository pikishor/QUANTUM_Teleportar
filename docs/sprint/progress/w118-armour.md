w118-armour
GOAL: tanks, helicopters, planes findable (fixed places, map icons, demo spawn, call-in, touch enter/drive/fly/shoot/leave).
FOUND (real finger probe tests/dev_w118_armour.gd, frames tests/bot_w118_armour.gd):
- nearest fixed vehicle point was 137 m from the start, a vehicle only existed within 100 m: nothing to meet in the first minutes
- map: the points were fogged and wore the GARAGE car glyph: a fresh player saw no tank / helicopter / plane icon
- the 5 tanks stood in the traffic lanes of the west ring road (x -320), 300 m out; on LOW+ (2 live cars) each new point released the farthest vehicle (another tank)
- the helipad heli stood among plaza statues, no pad; a tank leaving a kerb lot was stopped after 11 m by kerb props (shelter, lantern pole, bollards)
- no call-in for armour; the demo/test SPAWN list had the vehicles after ~25 enemies, placed at the crosshair point (can be inside a wall)
DONE (files):
- godot/scripts/vehicles/armour_sites.gd (class ArmourSites): SITES army_yard (-135,-55), pad_east (105,25), pad_south (-25,185); decor built within 112 m, freed beyond 135 m;
  is_fixed(id), claims(x,z), keeps_clear(x,z), map_markers(), call_in(kind), spawn_beside(kind), drop_point(); switches fixed_on / icons_on / demo_on (old-behaviour trial)
- godot/scripts/ui/call_in.gd (class CallIn): the CALL-IN list (CAR, TANK, HELICOPTER, PLANE, CLOSE), Buttons named Call_Car / Call_Tank / Call_Helicopter / Call_Plane / Call_Close
- hooks (keep them): vehicle_spawns.gd (depot, depot_light, depot_apc moved into the yard; ArmourSites.vehicle_points), vehicle_manager.gd (cap() + _fixed_n, _unfix, _count_fixed,
  fixed rules in _tick_spawn_points, ArmourSites.attach in _ready), city_props.gd _place_plazas (claims), city_kit.gd (_place_flora claims, _clear_armour_lanes), city_landmarks.gd (claims),
  map_icons.gd (glyphs tank / heli / plane, kind armour), map_screen.gd (kind armour "TANKS + AIR", ArmourSites.map_markers, armour_pins edge pins, marker_at), minimap.gd (_draw_armour),
  test_menu.gd + demo_panel.gd (SPAWN: first section TANKS, HELICOPTERS, PLANES: NEXT TO YOU), touch_controls.gd (ONE line: fn summon -> CallIn.toggle())
- tests: godot/tests/test_armour_w118.gd (41 checks, real fingers; ARMOUR_OLD=1: 8 FAIL), probes dev_w118_armour.gd / dev_w118_plazas.gd, look bot bot_w118_armour.gd
DECISIONS (for other agents):
- FOR w118-controls: the button with fn "summon" (action garage_call, label CALL CAR) now opens the CALL-IN list: please keep `CallIn.toggle()` on it; a shorter label "CALL" would fit better.
  ACTIONS A TANK NEEDS on screen: stick (move_*), fire (cannon), aim (coax gun when weapons.has_alt()), interact (EXIT), veh_view; the turret follows the look drag.
  ACTIONS A HELICOPTER / PLANE NEEDS: stick, jump (UP), crouch (DOWN), fire, aim (rockets when has_alt), interact (EXIT, only on the ground: "LAND TO GET OUT"), veh_view.
  All are existing input actions; test_armour_w118 finds the buttons by action (fire, jump, crouch, interact, more, garage_call), not by position.
- a fixed vehicle wears metas `fixed` + `hold`, a called / demo one `called` + `hold`; VehicleManager.cap() = tier cap + those; entering one makes it an ordinary car.
- map marker kind `armour` is in MapScreen.KINDS / ALWAYS_KINDS (never capped, never fogged).
TESTS AND PERF: test_armour_w118 PASS (41); old trial 8 FAIL. Related old tests: running (batch). Perf gate: not yet run.
NEXT: check related tests, frames of the yard / pads / call-in / map, perf gate (once), HANDOFF + ARCHITECTURE notes.
OPEN PROBLEMS: see the end of the work.
RESTART 2 (22 Nov): test_armour_w118 PASS again (42), ARMOUR_OLD=1 12 FAIL; frames re-rendered and looked at (yard, map, call-in, tank fire, heli): fine.
- found in frame call_2_tank: beside the delivered tank the prompt read HIJACK SEDAN (reach_car took the nearest). Fix: vehicle_manager.reach_car prefers metas called / fixed
  (switch ArmourSites.pick_on); new check at the end of part `call` (ARMOUR_PICK_OLD=1 ARMOUR_PARTS=call shows it failing). STATE: check being run.
- related tests batch running (scratch rel.txt). NEXT: perf gate once, shots into docs/shots/round7/armour_w118/, HANDOFF line.
RESTART 2: pick fix check PASS (ARMOUR_PICK_OLD=1 fails); related batch 26 pass, 3 flaky, 4 timeouts under load that pass alone. Perf gate started (scratch perf.txt).
FINAL (restart 2): test_armour_w118 PASS (43 checks); ARMOUR_OLD=1: 12 FAIL; ARMOUR_PICK_OLD=1 ARMOUR_PARTS=call: the pick check FAILS (hero in the sedan).
Related: airport_aircraft, tanks, vehicle_roster, vehicle_overlap, vehicles_city, vehicle_realism, map_screen, menus_map_quality, demo_menu, demo_mode, testmode, garage, traffic,
  open_world_freedom, controls_w118, touch_buttons_r7, touch_audit*: PASS; big_city, map_no_freeze, outskirts_sites, flight_view_w116 time out in a 3-job batch, PASS alone.
PERF GATE (run once, after all edits): LOW draws=74 total=96 death=107 OK; MED draws=97 total=129 death=149 OK; HIGH draws=113 total=149 death=170 OK.
Frames: docs/shots/round7/armour_w118/armour_w118_sheet2.jpg (map, yard, tank fire, helicopter, call-in list, delivery). HANDOFF + ARCHITECTURE updated. Nothing committed.
OPEN PROBLEMS: city plane still on the avenue (340, 0, 0), no airstrip; planes not in the finger test (take-off, landing); a vehicle the hero has driven loses the ENTER preference;
  CALL label is w118-controls'; yard has no guards / mission; tank models read flat pale lilac / green at noon on LOW.
