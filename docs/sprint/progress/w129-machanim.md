GOAL: w129-machanim: machine and aircraft animation and effects (plan line 129), test_machanim_w129.gd by real touch.
DONE (all switches: W129_OLD=1 = old code, MachAnim.old):
- LOD gap (AWACS wheels-only): MachAnim.lod_margin -> margin 0 on Body/LOD1 pairs (heli_models, plane_models, vehicle_visual._link_lod1, car_v2); frames aw_old/aw_new (44 m: fixed)
- scripts/vehicles/mach_anim.gd (class MachAnim): heli() rotor blur discs (shader rotor_disc), TAIL ROTOR disc (was invisible at speed), blade cone/flap (shader rotor_blade),
  cyclic tilt, skid flex on landing; wash() radial pooled puffs; plane(): rig pose, flame (jet_flame shader), nav lights (nav_lights shader), trails (contrail shader, Trail class);
  gun_fired()/tank(): recoil, rock, muzzle flash + smoke + ground dust, track dust, exhaust; car(): tail-pipe exhaust; on_wreck()/wrecks(): burning husks; GLB_GEAR nose legs (xv_jet, xv_cargo)
- scripts/vehicles/plane_rig.gd (PlaneRig): skinned Detail (bone per part), skeleton "Rig"; plane_models.gd rig mode (_subpanel/_panel_rig/_wings_rig/_gear_rig, retracts(), nozzles, navl)
- BlastFx.machine_puff (low priority in the one cloud MultiMesh, blasts take their slots first)
- hooks: vehicle_craft (State.mach/thr_in/lift_in, sync heli/plane/tank), vehicle_visual._bind_craft (MachAnim.bind), aircraft_flight._wash, vehicle_weapons (_shoot/_shell gun_fired),
  vehicle.gd (_sync car exhaust, become_wreck on_wreck), vehicle_manager (_physics_process_body wrecks)
- frames looked at: AWACS 30-50 m, helis spool/hover/forward (police, heavy, attack), fighter/narrowbody parked/gear/surfaces/retract/exhaust
- blast_cloud.gdshader fog_disabled + distance fade (ROOT CAUSE of the pale squares round every smoke puff, blasts too: fog colour added over premultiplied rgb 0); W129_OLD rebuilds the fogged shader
- jet_flame (heat glow + afterburner with shock diamonds, nozzles from PlaneModels) replaces the opaque-looking Burner cone; parts["Burner"] = the flame (old tests look it up)
- tests/test_machanim_w129.gd: NEW PASS 36/36 (~30 s); W129_OLD=1 FAIL 25/36 = every [old fails] check fails, the 11 others pass
- frames looked at: tank drive/fire, car exhaust, GLB jet/cargo nose legs, burning sedan + heli husks, night lights (made bigger after)
- other tests run: airlook_w128 PASS, airport_aircraft PASS, blastfx_w128 PASS, tanks_w127 PASS, helis_w125 (load 11: one timeout + one walk-up flake; h_fire,h_trainer PASS new and old)
- frames after the fixes: heli wash (soft round dust now), night nav lights (bigger), fighter afterburner / retract / gear up
- parked cars and tanks do not smoke (engine off: also kept the perf view's draw count at its baseline)
- perf run 2 (final): LOW draws=76 death=107 OK; MED draws=99 total=131 prims=275k (274889) death=146 OK; HIGH draws=118 death=164 OK (run 1: 108 / 147 / 165, before the parked-smoke fix)
- final: test_machanim_w129 PASS 36/36
NEXT:
- done (report sent)
DECISIONS: tests read MachAnim.st(v.craft) (pose, flex_min, gear_cycles), MachAnim.part_angle, lights_on, trail_points, recoil_of, counters gun_shots/dust_puffs/exhaust_puffs/wash_puffs/wreck_puffs
TESTS AND PERF:
OPEN PROBLEMS:
- w129-tankmis edits vehicle.gd, vehicle_weapons.gd, tank_arms.gd, camera_rig.gd at the same time (only one-line hooks of mine there)
