GOAL: whole map reachable on the ground (w120-reach): probe bot, fix invisible walls / climb / swim / edge, test_reach_w120.
DONE:
- survey godot/tests/dev_w120_survey.gd: world edge (PLAY_HALF 4460) is sea on all 4 sides; 898/19179 land samples steeper than 50 deg (floor_max_angle).
- probe godot/tests/dev_w120_probe.gd + godot/tests/w120_reach_lib.gd (real fingers). Run 1 (old code) findings:
  * STUCK at foot of steep faces: peak q0 (2506,0), EASTWATER valley side (2029,79), NORTH CREEK bank (713,-1587)
  * swimming out to sea: hard wall at 4460 then thrown back to a city street (LOST SIGNAL)
  * drops: hero sank ~3.4-3.9 m into ground (199/200) before TerrainWorld._rescue_player popped him up (collider not built yet)
  * cars: Vehicle stops hard at deep water (invisible wall for cars); ENTER showed but did nothing anywhere above y 2 (VehicleManager.toggle_enter_exit compared hero y to 2.0, not to the car)
  * BLOCKs in city/sites were building / site collision boxes (Building68_0, Chunk0/1, observatory, iron_hollow house): walls of visible things, left
- FIXES (switch PlayerSwim.reach_on, REACH_OLD=1 in tests):
  * scramble: player.gd _reach_after_slide + _foot_tick (terrain "Collider_*" face steeper than floor angle, stick into it -> 2.4 m/s up, 1.8 m/s along; buildings stay walls)
  * fall-through guard: player.gd (only where the chunk collider is not built: keeps feet on TerrainHeight)
  * open sea: player_swim.gd swell from PLAY_HALF-200 pushes back (equilibrium ~4314), note "OPEN SEA · THE SWELL CARRIES YOU BACK"
  * cars sink: vehicle.gd _sink (player's car only; traffic keeps the shore stop), hero exits and swims
  * ENTER height: vehicle_manager.gd toggle_enter_exit measures from the car
- test godot/tests/test_reach_w120.gd: new PASS 17/17 (110 s alone); REACH_OLD=1 fails steep(2), ENTER, sink(cascade), edge(2), drops.
- look bot godot/tests/bot_w120_reach.gd (W120_OUT, W120_PARTS)
NEXT: done (report handed back). Frames docs/shots/round7/reach_w120 (swim/climb MED, edge LOW; LOW swim/climb looked at, MED edge timed out on software render).
TESTS AND PERF: test_reach_w120 PASS 17/17; perf (one run, shared tree): LOW draws=71 death=108 OK; MED draws=100 death=147 OK; HIGH draws=112 death=175 OVER (>170). w120-reach adds no nodes/meshes (logic only); spike likely from parallel edits, not re-run (2-run limit).
DECISIONS: PlayerSwim.reach_on, PlayerSwim.OPEN_SEA 200, Player.scrambling, Vehicle.sunk.
OPEN PROBLEMS: big pale cyan crystal mesh floats in the sea near (4300, 600) (edge frames); swim pose upright at low speed; scramble has no own animation (run/fall pose); hard WallE/W/N/S boxes still exist out in the sea for boats; swim across river passed on old code too.
