GOAL: w121-lifts: lifts in tall buildings (USE/LIFT context, floor panel, ride <3 s, HUD floor, map floor), wave 120 leftovers.
DONE:
- edge walls: city.gd EDGE_WALL_LO/HI -300..1600 m (were 0..400); switch W121_EDGE_OLD=1
- boat/aircraft edge damping per second: AircraftFlight.edge_dt_fix (pow(1-k, dt*60)); switch W121_EDGE_OLD=1
- probe tests/dev_w121_crystal.gd (lists geometry near 4300,600): only DRIFT RAY gliders (alien fauna, mech float, 4-5 m over sea) + gulls/dolphins: no stray crystal found at LOW
- scripts/world/tower_lift.gd (TowerLift, attached in city.gd after RailWorld; QT_NO_LIFTS=1 off): INSIDE mode in TowerFloors towers (LIFT_BAY, every level), OUTSIDE glass facade lift
  for other tall lots (h>=24, street+roof). Hooks: RideUse.prompt (LIFT first), VehicleManager.reach_car (null at a lift spot), ParkedCars (TowerLift.no_parking),
  MapScreen (outline + floor, var tower_floor), TowerFloors._minus_hole (LIFT_BAY cut from slabs, only when TowerLift exists)
- tests/test_lifts_w121.gd parts edge,boatdt,tower,lift: all PASS (44 checks)
- map: MapScreen._hero_outside / outskirts_fix (W121_MAP_OLD=1): open() and YOU in the outskirts go to the REGION picture (old: view clamped to the city, hero off map)
- test parts gps, zip, roofs added (gps old-fail shown; zip/roofs coverage PASS); bot tests/bot_lifts_w121.gd frames looked at (1200x540)
- old-code fail runs done: QT_NO_LIFTS=1 (tower,lift fail), W121_EDGE_OLD=1 (edge 0..400 fail, boat 6.93 vs 0.29 fail), W121_MAP_OLD=1 (gps fail)
- neighbours PASS: test_lifts_w121 (all parts), controls_w118, critic_w120, sky_w120, touch_buttons_r7, world_hud (after moving the YOU fix to _on_locate), map_no_freeze, floors_w121, touch_audit
- 2400x1080 bot render killed (memory/time on this machine); 1200x540 frames looked at
NEXT:
- perf gate (running), report
OLD2:
- run neighbours (controls_w118, touch_buttons_r7, critic_w120, sky_w120, floors_w121), 2400x1080 frames, perf at end
OLD NEXT:
- old-code fail run (QT_NO_LIFTS=1 W121_EDGE_OLD=1), frames (bot), GPS mountain / zip roof / rooftops outskirts-airport-yard checks, perf at end
DECISIONS (UPDATED: I use TowerFloors.current() as it is: levels, frame, LIFT_BAY, SW_T, at(); keep those names please)
OLD PROPOSAL (superseded):
- TowerLift (mine) reads from TowerFloors (yours) if these exist, duck-typed with has_method:
  TowerFloors.instance (static var) ; instance.active_lot() -> int (-1 none: lot whose shell is built)
  instance.floor_levels(lot_idx) -> PackedFloat32Array  slab-top y of every walkable floor, ground first, ROOF last (y = lot.h)
  instance.lift_spot(lot_idx) -> Dictionary {pos: Vector3 (shaft centre on the ground slab), yaw: float (cabin door faces -Z rotated by yaw), size: 2.4}
     a 2.4 x 2.4 m column through every floor kept FREE of walls/props/slab colliders (I build shaft, cabin, doors, colliders)
  If lift_spot is missing I place the shaft myself 1.6 m inside the walk-in door wall corner.
- Context slot (wave 119 DOOR/USE slot, action interact): reads LIFT at the lift call spot; tap opens the floor panel (TowerLift panel, CanvasLayer).
- HUD floor: TowerLift.hud_floor() -> String ("FLOOR 3", "" outside) ; map: MapScreen draws lot outline + "FLOOR n".
TESTS AND PERF:
- PERF_CHECK=1: LOW total 94 death 111 OK; MED total 133 death 148 OK (2nd run, 1st NO_RESULT: bot did not finish under load); HIGH total 147 death 170 OK (at limit, unchanged)
DONE - report sent.
OPEN PROBLEMS:
