# w127-critic progress log
GOAL: independent review of wave 127 (tanks + tank arms) with a finger-only bot in main.tscn; list 8 worst defects; fix most severe first, each with a failing-then-passing check.
DONE:
- (start) read ROUND7, PLAN line 127, ROUND6 rules, HANDOFF tail, both builder logs and their tests.
- review probe godot/tests/probe_w127_critic.gd (headless, fingers; PARTS=kinds|fight|crash|bridge, KINDS=...; runner caps at 140 s so run in batches) and look bot godot/tests/bot_w127_critic.gd (CR_ONLY=drive|perf)
- kinds part run on all 20 new kinds: board/drive/turret/fire/arms/smoke all work by finger; findings so far:
  * builders' mission tests TELEPORT the tank to the goal and aim with meta aim_at (not fingers) -> missions not proven by finger
  * t_halftrack (FOREST ROAD checkpoint) drives 4.8 m into a tree trunk (Vegetation/Trunk1) and stops
  * wheeled kinds (apc8, mrap, jeep, scout) model AABB 1.5-2x spec width in game (Run multimesh) -> check in frames
  * t_mine model bottom 0.33 m under ground (flail?)
  * MISSIONS by finger (probe PARTS=fight, GPS route WorldRoute + stick autopilot, --timeout=950 on the runner): TANK BATTLE drive leg is 1.3-2.2 km straight / 1.7-3.5 km of route through the city, 7:00 clock
  * DEFECT 1 (FIXED): a tank stops dead at every kerb parked car it touches (static ParkedBody; promote_around needs 2.5 m/s, promote_touching was cars only) -> ParkedCars.crush_touching (parked_cars.gd) + hook in vehicle_manager.gd parked pass; check tests/test_w127_critic.gd part kerb: W127C_OLD=1 FAIL (1.3 m driven), new PASS
  * tank also blocked by PropColliders (lamps, hydrants, benches) in the city
  * walker: chase camera at turret height, the turret covers the crosshair (frame turret_t_walker)
  * DEFECT 2 (FIXED): bridge decks had GAPS on the outer side of every bend (Bridges.deck_y: no segment owned the wedge): heavy tank sank 7 m into PASS ROAD bridge and stuck; a sedan fell through and sank. Fix bridges.gd deck_y (inner joints own the wedge, Bridges.wedge_on)
  * DEFECT 3 (FIXED): flat hull box of a long tank meets the 14 % ramp of MOUNTAIN TRACK bridge and stops: vehicle.gd _terrain_step lifts the tank hull collider by the slope under its nose (cls tank only)
  * check test_w127_critic part bridge: W127C_OLD=1 FAIL 2 of 2 (34 m of 70 / 23 m of 68), new PASS
  * probe bridge sweep after fix: pass/desert/forest/mountain 3/4 all crossed by t_heavy
  * missions: with old code TANK BATTLE reached the fight only by MissionGuide auto-recover (stuck skip); city props (PropColliders) still stop tanks
  * DEFECT 4 (FIXED): FOREST ROAD checkpoint half-track parked nose to a tree trunk (4.8 m, could not drive out forwards): TankRoster.clear_spot/_blocked (generated from tools/gen_tank_roster.py; VegScatter data) moves a checkpoint spot along the road until no trunk/rock is in the box + 16 m ahead; check part checkpoint: OLD FAIL (4.8 m of 16), new PASS (6 of 6)
  * PERF (bot_w127_critic CR_ONLY=perf, 9 tanks in view on the airfield, boarded): OLD LOW 149-161 draws (budget 100), MED 182-192 (budget 140); new kinds cost 7-11 draw surfaces each
  * DEFECT 5 (fixing): TankModels._finish_one (merge_on): body/turret/gun/flail one vertex-coloured surface named Body (paint multiplies) -> 4-6 surfaces per kind. Frames + perf re-run pending
  * duel by finger (probe PARTS=duel): 7 shots, 6 hits, enemy tank down in 12 s, works
NEXT:
- perf2 + lineup frames (running), mission rerun, props, props, checkpoint trees; baseline TANK BATTLE by finger (old code) log scratch c/fight_battle_old.log; then mission distance; perf bot; bridge; crash
DECISIONS:
- switch W127C_OLD=1 = code before the critic fixes (ParkedCars.tank_crush_on ...)
TESTS AND PERF:
OPEN PROBLEMS:
