extends RefCounted
## WAVE 129 (plan line 129, agent w129-machanim): MACHINE AND AIRCRAFT ANIMATION AND EFFECTS, driven by REAL FINGERS on the real main scene (InputEventScreenTouch / Drag through
## Input.parse_input_event in window coordinates, Game.force_touch, the phone-only layers on: CrateReveal._quiet = 0). The set-up parks a vehicle and puts the hero beside it by code;
## everything a player does is a finger on the touch HUD (ENTER, the stick, UP, DOWN, GAS, FIRE, EXIT).
##   heli    ENTER, UP: the rotor spools into a streaked blur disc that cones up under lift, the TAIL ROTOR stays drawn at full spin (before: its blades were hidden and no disc
##           drawn: no tail rotor in flight), the downwash throws dust out from under the disc, the stick forward tilts the rotor head, DOWN to the ground: the skids flex
##   plane   (night) ENTER: the nav lights come on with the engine; stick right + UP: the right aileron goes up and the left down, the elevators lift, the rudder swings; stick
##           forward + UP: it takes off and the gear folds away with its doors shut; a hard pull at speed draws wingtip vortices; the jet's exhaust glows
##   tank    ENTER, stick forward: track dust and diesel exhaust; FIRE: the barrel recoils into the turret and runs out, muzzle flash and blast smoke
##   car     ENTER, GAS: tail-pipe exhaust
##   world   a burning husk (flames and a smoke column), the parked AWACS drawn whole at every distance (its Body / LOD1 pair has no gap), the old art jet and cargo plane on a
##           nose leg without the tail wheel, the smoke puffs without the fogged square round them
## W129_OLD=1 = the code before this wave: every check marked [old fails] fails. M129_PARTS=world,heli,plane,tank,car (default all).
## Run: tools/test.sh tests/test_machanim_w129.gd
const Fingers := preload("res://tests/w116_fingers.gd")
const TIMEOUT_SECONDS := 145
var host: Node
var p: Player
var vm: VehicleManager
var fg: Fingers
var at := Vector3.ZERO


func _f(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _f(3)
	fg.up(6)
	await _f(3)
	return true


## Hold the button of `action` with finger `finger` until `cond` holds (or `frames` pass). True when cond held.
func _hold(finger: int, action: StringName, cond: Callable, frames: int) -> bool:
	var on := fg.press(finger, action)
	var ok := false
	for i in frames:
		if cond.call():
			ok = true
			break
		await _f(1)
	if on:
		fg.up(finger)
	await _f(1)
	return ok or cond.call()


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	host.get_tree().root.size = Vector2i(1200, 540)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	fg = Fingers.new(host)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	at = Airport.to_world(Vector3(1250.0, 0.0, -640.0))
	at.y = TerrainHeight.height_at(at.x, at.z)
	p.teleport_to(at + Vector3(-40.0, 0.5, 0.0))
	await _f(30)
	var parts := OS.get_environment("M129_PARTS")
	for part in ["world", "heli", "plane", "tank", "car"]:
		if parts == "" or parts.contains(part):
			var t0 := Time.get_ticks_msec()
			await call("_" + part)
			fg.up_all()
			if vm.driven != null:
				vm.exit_vehicle()
			await _f(4)
			print("part %s %.1f s" % [part, (Time.get_ticks_msec() - t0) / 1000.0])
	fg.up_all()
	Engine.time_scale = 1.0
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


## Park `kind` at `where` (heading h), put the hero beside it, and board it with a finger on ENTER. Returns the vehicle or null.
func _board(kind: StringName, where: Vector3, h := 0.0) -> Vehicle:
	vm._release_farthest(where)
	vm._release_farthest(where)
	var v := vm.spawn_parked(kind, where, h)
	if v == null:
		TestLib.check(false, "%s parks for the check" % kind)
		return null
	await _f(4)
	var side := minf(float(v.spec["wid"]) * 0.5 + 1.2, 3.0 if VehicleSpecs.cls_of(kind) == &"plane" else 9.0)
	p.teleport_to(v.global_position + v.right() * side + Vector3(0.0, 0.3, 0.0))
	await _f(20)
	var ok := false
	for i in 40:
		if fg.button_label(&"interact") == "ENTER":
			ok = true
			break
		fg.stick(Vector2(-1.0, 0.0))
		await _f(2)
	fg.stick(Vector2.ZERO)
	await _f(2)
	if ok:
		await _tap(&"interact")
		await _f(20)
	TestLib.check(p.vehicle == v, "a finger on ENTER boards the %s" % VehicleSpecs.name_of(kind))
	return v if p.vehicle == v else null


# --- world -----------------------------------------------------------------------------------------------------------------------------------

func _world() -> void:
	# the near / far body pair of every vehicle model: a fresh instance with the camera between the two ranges must draw one of them
	for k: StringName in [&"p_awacs", &"h_police", &"sedan"]:
		vm._release_farthest(at)
		var v := vm.spawn_parked(k, at + Vector3(0.0, 0.0, 40.0), 0.0)
		await _f(3)
		if v == null:
			TestLib.check(false, "%s parks" % k)
			continue
		var b := v.visual.model.get_node_or_null("Body") as GeometryInstance3D
		var l1 := v.visual.model.get_node_or_null("Body_LOD1") as GeometryInstance3D
		if v.visual.v2 != null:
			b = v.visual.v2.body
			l1 = v.visual.v2.lod1
		var gap := 0.0
		if b != null and l1 != null:
			gap = (l1.visibility_range_begin + l1.visibility_range_begin_margin) - (b.visibility_range_end - b.visibility_range_end_margin)
		TestLib.check(b != null and l1 != null and gap <= 0.001, "[old fails] %s: a new one is drawn at every distance (near body ends %.1f m, far body starts %.1f m for a fresh instance: gap %.1f m)" %
			[k, b.visibility_range_end - b.visibility_range_end_margin if b else -1.0, l1.visibility_range_begin + l1.visibility_range_begin_margin if l1 else -1.0, gap])
		vm._release(v)
	# the old art jet and cargo plane: a nose leg down to the ground, no tail wheel
	for k: StringName in [&"jet", &"cargo"]:
		vm._release_farthest(at)
		var v := vm.spawn_parked(k, at + Vector3(0.0, 0.0, 40.0), 0.0)
		await _f(3)
		if v == null:
			continue
		var ng := v.visual.model.get_node_or_null("NoseGear") as MeshInstance3D
		var low := 99.0
		var nose_z := 0.0
		if ng != null:
			var a := ng.get_aabb()
			low = a.position.y
			nose_z = a.get_center().z
		var tail := 0
		var body := v.visual.body
		for s in body.mesh.get_surface_count():
			var arr := body.mesh.surface_get_arrays(s)
			var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in range(0, idx.size(), 3):
				var c := (vv[idx[t]] + vv[idx[t + 1]] + vv[idx[t + 2]]) / 3.0
				if c.y < 0.6 and c.z > float(v.spec["len"]) * 0.25 and absf(c.x) < 0.4:
					tail += 1
		TestLib.check(ng != null and absf(low) < 0.08 and nose_z < -float(v.spec["len"]) * 0.3 and tail == 0, "[old fails] the %s stands on a nose leg (wheel bottom %.2f m at z %.1f) and has no tail wheel (%d faces)" % [k, low, nose_z, tail])
		vm._release(v)
	# smoke puffs: the cloud material takes no fog (the fog colour was added over the whole quad of every puff: pale squares)
	var fx := BlastFx.shared()
	var mm := fx.find_children("*", "MultiMeshInstance3D", true, false)
	var code := ""
	for n in mm:
		var mat := (n as MultiMeshInstance3D).material_override as ShaderMaterial
		if mat != null and mat.shader != null and mat.shader.code.contains("blend_premul_alpha"):
			code = mat.shader.code
	TestLib.check(code != "" and code.contains("fog_disabled"), "[old fails] the smoke puffs are not fogged into pale squares (fog_disabled in the cloud shader)")
	# a husk burns: flames and a smoke column near the camera
	vm._release_farthest(at)
	var car := vm.spawn_parked(&"sedan", at + Vector3(0.0, 0.0, 18.0), 0.0)
	await _f(3)
	if car != null:
		var w0 := MachAnim.wreck_puffs
		car.explode()
		await _f(90)
		TestLib.check(car.wreck and MachAnim.wreck_puffs - w0 >= 4, "[old fails] the wreck of a blown-up car burns (%d flame / smoke puffs in 1.5 s)" % (MachAnim.wreck_puffs - w0))


# --- helicopter ---------------------------------------------------------------------------------------------------------------------------------

func _heli() -> void:
	var v := await _board(&"h_police", at + Vector3(0.0, 0.0, -30.0))
	if v == null:
		return
	var c := v.craft
	var vis := v.visual
	var w0 := MachAnim.wash_puffs
	var seen := {"tail": true, "cone": 0.0, "n": 0}                      # (a lambda copies plain locals: the samples go into a dictionary)
	var up := await _hold(1, &"jump", func() -> bool:
		var tr := vis.parts.get("TailRotor") as Node3D
		var td := vis.parts.get("TailRotorDisc") as Node3D
		if c.spool > 0.95:
			seen["n"] = int(seen["n"]) + 1
			if not ((tr != null and tr.is_visible_in_tree()) or (td != null and td.is_visible_in_tree())):
				seen["tail"] = false
			seen["cone"] = maxf(float(seen["cone"]), float(MachAnim.st(c).cone) if c.mach != null else 0.0)
		return c.airborne and VehicleCraft.altitude(v) > 4.0 and c.spool > 0.97, 300)
	var tail_seen: bool = seen["tail"] and int(seen["n"]) > 0
	var cone: float = seen["cone"]
	TestLib.check(up, "UP by finger spools the rotor and lifts the %s (altitude %.1f m, spool %.2f)" % [VehicleSpecs.name_of(v.kind), VehicleCraft.altitude(v), c.spool])
	var tr2 := vis.parts.get("TailRotor") as Node3D
	var td2 := vis.parts.get("TailRotorDisc") as Node3D
	var tail_now := (tr2 != null and tr2.is_visible_in_tree()) or (td2 != null and td2.is_visible_in_tree())
	TestLib.check(tail_seen and tail_now, "[old fails] the tail rotor is still drawn at full spin (blades %s, disc %s)" % [tr2.is_visible_in_tree() if tr2 else false, td2.is_visible_in_tree() if td2 else false])
	var rd := vis.parts.get("RotorDisc") as GeometryInstance3D
	var rot := vis.parts.get("Rotor") as Node3D
	TestLib.check(rd != null and rd.is_visible_in_tree() and rot != null and not rot.is_visible_in_tree(), "the main blades have become the blur disc at full spin")
	TestLib.check(cone > 0.02, "[old fails] the blades cone up under lift (%.3f rad)" % cone)
	TestLib.check(MachAnim.wash_puffs - w0 >= 3, "[old fails] the downwash throws dust out from under the disc near the ground (%d puffs)" % (MachAnim.wash_puffs - w0))
	# the stick forward tilts the rotor head (the tip path leans ahead of the body)
	fg.stick(Vector2(0.0, -1.0))
	await _f(30)
	var tilt := rot.transform.basis.y.z if rot != null else 0.0
	var dtilt := (rd.transform.basis.y.normalized().z) if rd != null else 0.0
	fg.stick(Vector2.ZERO)
	TestLib.check(tilt < -0.03 and dtilt < -0.03, "[old fails] the stick forward tilts the rotor head forward (blades %.3f, disc %.3f)" % [tilt, dtilt])
	# DOWN to the ground: the skids flex on the touch-down
	if c.mach != null:
		MachAnim.st(c).flex_min = 0.0
	var landed := await _hold(2, &"crouch", func() -> bool: return not c.airborne, 420)
	await _f(20)
	var flex := float(MachAnim.st(c).flex_min) if c.mach != null else 0.0
	TestLib.check(landed, "DOWN by finger lands it (altitude %.1f m)" % VehicleCraft.altitude(v))
	TestLib.check(flex < -0.02, "[old fails] the skids flex on the touch-down (the body sank %.3f m onto them)" % flex)
	await _tap(&"interact")
	await _f(10)
	var s1 := c.spool
	await _f(150)
	var rot_back := rot != null and rot.is_visible_in_tree()
	TestLib.check(p.vehicle == null and c.spool < s1 - 0.3 and rot_back, "EXIT by finger: the rotor winds down and the blades show again (spool %.2f -> %.2f)" % [s1, c.spool])


# --- aeroplane -------------------------------------------------------------------------------------------------------------------------------------

func _plane() -> void:
	var dn: DayNight = (Game.world as City).day_night
	var hour0 := dn.hour
	dn.frozen = true
	dn.set_hour(22.5)
	await _f(10)
	var th := Airport.thresholds()
	var t09: Vector3 = th[0]["pos"]
	var t27: Vector3 = th[1]["pos"]
	var dir := (t27 - t09).normalized()
	var where := Vector3(t09.x, TerrainHeight.height_at(t09.x, t09.z), t09.z) + dir * 60.0
	var v := await _board(&"p_fighter", where + Vector3(-dir.z, 0.0, dir.x) * 40.0, float(th[0]["heading"]))
	if v == null:
		dn.set_hour(hour0)
		return
	v.global_position = Vector3(where.x, v.base_y, where.z)              # set-up: the boarded fighter on runway 09
	v.heading = float(th[0]["heading"])
	v.vel = Vector3.ZERO
	v.speed = 0.0
	await _f(4)
	var c := v.craft
	# the engine: lights at night and the exhaust glow
	fg.stick(Vector2(0.0, -0.4))
	await _f(40)
	TestLib.check(MachAnim.lights_on(v), "[old fails] at night the navigation lights come on with the engine (spool %.2f)" % c.spool)
	var fl := v.visual.parts.get("Flame") as Node3D
	TestLib.check(fl != null and fl.is_visible_in_tree(), "[old fails] the jet's exhaust glows while the engine runs")
	fg.stick(Vector2.ZERO)
	await _f(20)
	# stick right + UP on the ground: the control surfaces follow
	fg.stick(Vector2(1.0, 0.0))
	fg.press(1, &"jump")
	await _f(30)
	var ar := MachAnim.part_angle(v, "AileronR")
	var al := MachAnim.part_angle(v, "AileronL")
	var el := MachAnim.part_angle(v, "ElevatorR")
	var ru := MachAnim.part_angle(v, "Rudder")
	fg.up(1)
	fg.stick(Vector2.ZERO)
	TestLib.check(not is_nan(ar) and ar < -0.1 and al > 0.1, "[old fails] stick right: the right aileron rises and the left one drops (%.2f / %.2f rad)" % [ar, al])
	TestLib.check(not is_nan(el) and el < -0.1, "[old fails] UP lifts the elevators' trailing edge (%.2f rad)" % el)
	TestLib.check(not is_nan(ru) and ru < -0.05, "[old fails] the rudder swings to the turn (%.2f rad)" % ru)
	var gear0 := MachAnim.part_angle(v, "MainGearL")
	TestLib.check(not is_nan(gear0) and absf(gear0) < 0.05 and absf(MachAnim.part_angle(v, "NoseDoorL")) > 1.2, "[old fails] on the ground the gear is down and its doors stand open (leg %.2f, door %.2f)" % [gear0, MachAnim.part_angle(v, "NoseDoorL")])
	# the take-off: stick forward + UP; the gear folds away, the doors shut
	Engine.time_scale = 2.0
	fg.stick(Vector2(0.0, -1.0))
	fg.press(1, &"jump")
	var flown := false
	for i in 900:
		if c.airborne and VehicleCraft.altitude(v) > 40.0:
			flown = true
			break
		await _f(1)
	await _f(150)
	var leg := MachAnim.part_angle(v, "MainGearL")
	var door := MachAnim.part_angle(v, "MainGearLDoor")
	TestLib.check(flown, "stick forward + UP: the fighter takes off (altitude %.0f m)" % VehicleCraft.altitude(v))
	TestLib.check(not is_nan(leg) and absf(leg) > 1.4 and absf(door) < 0.1 and MachAnim.st(c).gear_cycles >= 1, "[old fails] after the take-off the gear folds away and its doors shut (leg %.2f rad, door %.2f rad)" % [leg, door])
	# a hard pull at speed: wingtip vortices
	var pts := 0
	fg.stick(Vector2(-1.0, 0.0))
	for i in 60:
		await _f(1)
		pts = maxi(pts, MachAnim.trail_points(v))
	fg.up(1)
	fg.stick(Vector2.ZERO)
	Engine.time_scale = 1.0
	TestLib.check(pts > 4, "[old fails] a hard turn at speed draws wingtip vortices (%d trail segments)" % pts)
	dn.set_hour(hour0)
	dn.frozen = false
	await _tap(&"interact")
	vm._reset_all()
	await _f(4)


# --- tank ------------------------------------------------------------------------------------------------------------------------------------------

func _tank() -> void:
	var v := await _board(&"t_heavy", at + Vector3(30.0, 0.0, 60.0))
	if v == null:
		return
	var d0 := MachAnim.dust_puffs
	var e0 := MachAnim.exhaust_puffs
	fg.stick(Vector2(0.0, -1.0))
	await _f(100)
	fg.stick(Vector2.ZERO)
	TestLib.check(absf(v.speed) > 2.0 or MachAnim.dust_puffs > d0, "the stick drives the tank (%.1f m/s)" % v.speed)
	TestLib.check(MachAnim.dust_puffs - d0 >= 3 and MachAnim.exhaust_puffs - e0 >= 2, "[old fails] the tracks raise dust and the engine smokes (%d dust, %d exhaust)" % [MachAnim.dust_puffs - d0, MachAnim.exhaust_puffs - e0])
	await _f(40)
	v.set_meta(&"aim_at", v.global_position + v.forward() * 150.0 + Vector3(0.0, 3.0, 0.0))
	await _f(60)
	var turret := v.visual.parts.get("Turret") as Node3D
	var gun := turret.get_node_or_null("Gun") as Node3D if turret != null else null
	var g0 := gun.position if gun != null else Vector3.ZERO
	var s0 := MachAnim.gun_shots
	var m0 := MachAnim.muzzle_puffs
	var back := 0.0
	var rec := 0.0
	fg.press(1, &"fire")
	for i in 10:
		await _f(1)
		rec = maxf(rec, MachAnim.recoil_of(v))
		if gun != null:
			back = maxf(back, gun.position.distance_to(g0))
	fg.up(1)
	await _f(60)
	var rest := gun.position.distance_to(g0) if gun != null else 99.0
	TestLib.check(MachAnim.gun_shots > s0, "[old fails] FIRE by finger: the main gun shot starts the gun animation (%d shots)" % (MachAnim.gun_shots - s0))
	TestLib.check(back > 0.12 and rest < 0.02, "[old fails] the barrel recoils into the turret and runs out again (%.2f m back, %.3f m after)" % [back, rest])
	TestLib.check(MachAnim.muzzle_puffs - m0 >= 3, "[old fails] the shot leaves blast smoke at the muzzle and dust beside the tank (%d puffs)" % (MachAnim.muzzle_puffs - m0))
	await _tap(&"interact")
	await _f(4)


# --- car ---------------------------------------------------------------------------------------------------------------------------------------------

func _car() -> void:
	var v := await _board(&"sedan", at + Vector3(-20.0, 0.0, 70.0))
	if v == null:
		return
	var e0 := MachAnim.exhaust_puffs
	var gas := fg.press(1, &"move_forward")
	await _f(60)
	fg.up(1)
	TestLib.check(gas and v.speed > 1.0, "a finger on GAS drives the car (%.1f m/s)" % v.speed)
	TestLib.check(MachAnim.exhaust_puffs - e0 >= 2, "[old fails] the tail pipe smokes as it pulls away (%d puffs)" % (MachAnim.exhaust_puffs - e0))
	await _tap(&"interact")
	await _f(4)
