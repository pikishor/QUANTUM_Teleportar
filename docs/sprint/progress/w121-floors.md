GOAL: w121-floors multi-floor walk-in interiors for tall city buildings (street door, real stairs, 3+ upper floors, roof door), test_floors_w121.
PROBE (godot/tests/dev_w121_probe.gd, real fingers, old code):
- every lot has ONE USE door (scripts/world/city_doors.gd); tall block lot 77 (-105,135) 26x26x28 m -> door type med_bay.
- ENTER by finger: 0.26 s fade out + teleport to a room built at InteriorGameplay.ORIGIN (x ~1040, outside the city), black frames, 2.5 s until active.
- room 15.5 x 8.5 m for a 26 x 26 m lot: inside does NOT match outside size; ONE floor (InteriorSpace max_y 5.3), no stairs, no upper floors, roof only by zip/swing.
- the stick against the facade: blocked by collider Building77_0 (one box per building part in city.gd _build_collision).
DESIGN (new): scripts/interiors/tower_floors.gd (TowerFloors, Node under main): for class "block" core lots h>=24, a WALK-IN street door on the street face the USE door does not use.
 Within 30 m: the building's Building<idx>_* colliders are switched off and an in-place shell is built (walls inset 0.3 m with window holes on the facade shader grid:
 ground 5.0 m (4.6 if h<20), floors fh=body/nfl, columns by style), floor slabs, a switchback stairwell (ramp colliders, step mesh), rooms per kind (office/apartment/tower)
 built only for the hero's floor +-1 and freed after; roof stair house with a door at roof y = lot.h. Left > 40 m: everything freed, colliders back.
DONE:
- probe written + run
NEXT: tower_floors.gd, hook in main.gd, test_floors_w121.gd, frames.
- scripts/interiors/tower_floors.gd (TowerFloors) + assets/shaders/tower_floors.gdshader; hooks: main.gd add_child(TowerFloors.new()), city.gd is_inside_building false for TowerFloors.open_lot
- tests/test_floors_w121.gd PASS 14/14 (new); FLOORS_OLD=1: 8+ FAIL (facade blocks, no stairs, no roof, no entries)
DECISIONS: TowerFloors.current() {lot, kind, name, levels, floor, landing[], lift_bay[2 corners], door, frame}; LIFT_BAY (u 7.8..10.2, v 0..2.6) left free on every floor for w121-lifts; TowerFloors.at(tw,u,v,y); open_lot; enabled.
 kinds: office (ribbon/curtain), hotel (fins, half punched), apartment (brick, half punched): 40 towers (14/10/16), all h 28 m: 6 floors + roof.
NEXT: frames bot (street door, stairwell, upper floor, roof door) LOW + MED at 1200x540; perf once at end.
- frames bot godot/tests/bot_w121_floors.gd (W121_OUT); first LOW frames: interior glared white -> shader albedo *0.42, emission 0.02 base (re-rendering)
- w121-lifts hooked TowerLift into my _minus_hole (LIFT_BAY hole) and uses current(); keep names.
- LOOK FIX: Color() alpha defaults to 1 -> every face was a light panel (white rooms). Now GLOW_A=2 marks panels; shader unshaded + fog_disabled with own soft shading. LOW frames now read (stairs, panels, windows).
- atmosphere.gd: no rain inside a walk-in tower (rainfield.update rain 0 when TowerFloors.inside(camera)).
- test_floors_w121 PASS again after the look fix. Frames: docs/shots/round7/floors_w121/floors_w121_low.jpg (6 views LOW), floors_w121_med_partial.jpg (MED street door + lobby; MED bot OOM-killed 3x by parallel renders, rest not rendered)
- perf gate running (once, end)
TESTS AND PERF: test_floors_w121 PASS 14/14; FLOORS_OLD=1 fails 8 (facade, lobby, floor 3, rooms, roof x2, down, 10 entries) + 3 more after tightening.
 perf (once, shared tree): LOW draws=75 death=108 OK; MED draws=101 death=147 OK; HIGH draws=112 death=169 OK (tower adds 1 draw only when open, not in the perf scene).
OPEN PROBLEMS: no enemies/NPCs placed on tower floors yet; MED screen-space rain still visible in the lobby (post rain, not the rainfield); stairwell has facade windows (open to view);
 MED stairwell/floor/roof frames not rendered (OOM kills by parallel renders); only class "block" core lots h>=24 (40 towers, all 28 m: 6 floors + roof).
STATUS: done, report handed back.
