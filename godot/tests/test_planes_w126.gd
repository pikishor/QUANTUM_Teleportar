extends RefCounted
## WAVE 126 AEROPLANE ROSTER AND HANGARS, driven by REAL FINGERS in the real main scene (InputEventScreenTouch / ScreenDrag through tests/w116_fingers.gd, Game.force_touch, phone-only
## layers on: CrateReveal._quiet = 0). Nothing here calls a game function to act; set-up only puts the hero (and, for the flight, the boarded plane) on a start point.
##  * data: 30+ aeroplane kinds, each new kind with its own model (Body, shared meshes), own flight numbers (stall, max, roll, pitch, run), engine sound, icon, name
##  * hangars (this file only): the hero walks by the stick up to HANGAR A and to ARMY SHELTER 1, the door slides open, he walks in, boards the plane parked inside with
##    a finger on ENTER and rolls it out through the door with the stick (throttle)
##  * every new kind: it waits at its place (PLANE LINE / hangar / shelter), the hero walks up by the stick and boards it with ENTER; on runway 09 the stick (throttle) and UP
##    take it off inside the runway, UP climbs, the stick banks and turns it and brings it back on the axis, stick back + DOWN put it down on the same runway, the stick
##    back brakes it to a stop, EXIT leaves it
## W126_PLANES_OLD=1 is the wave 125 state (no new kind stands anywhere, the hangars are solid boxes): the checks marked [old fails] fail.
## Split over four files (140 s runner cap): this one holds the data and the hangars, _b flies kinds 0, 3, 6 ..., _c 1, 4, 7 ..., _d 2, 5, 8 ...
## PLANES_KINDS=p_cub,p_sst PLANES_FLY=1 flies only those kinds (in this file).
## Run: tools/test.sh tests/test_planes_w126.gd
const TIMEOUT_SECONDS := 600
const Fingers := preload("res://tests/w116_fingers.gd")
const FILES := 3

var host: Node
var fg: Fingers
var p: Player
var vm: VehicleManager
var part := 0
var _t := 0.0                               ## game seconds counted by the physics frames of the test


func _f(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame


func _step() -> void:
	await host.get_tree().physics_frame
	_t += 1.0 / float(Engine.physics_ticks_per_second) * Engine.time_scale


func _until(cond: Callable, secs: float) -> bool:
	var t0 := _t
	while _t - t0 < secs:
		if cond.call():
			return true
		await _step()
	return cond.call()


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _f(4)
	fg.up(6)
	await _f(3)
	return true


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	var old := OS.get_environment("W126_PLANES_OLD") == "1"
	PlaneRoster.line_on = not old
	Hangars.on = not old
	if part == 0:
		_data()
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
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	Engine.max_physics_steps_per_frame = 4
	if part == 0 and OS.get_environment("PLANES_FLY") != "1":
		await _hangar(&"hangar_a", &"p_cub")
		await _hangar(&"shelter_1", &"p_fighter")
	var pick := OS.get_environment("PLANES_KINDS")
	for i in PlaneRoster.NEW.size():
		var k: StringName = PlaneRoster.NEW[i]
		if pick != "" and not k in pick.split(","):
			continue
		if pick == "" and (part == 0 or i % FILES != part - 1):
			continue
		if pick != "" and part == 0 and OS.get_environment("PLANES_FLY") != "1":
			continue
		var rt := Time.get_ticks_msec()
		await _kind(k)
		if vm.driven != null:
			await _tap(&"interact")
		vm._reset_all()                                         # clean-up between kinds: the last plane must not stand on the runway of the next take-off
		await _f(2)
		print("%s took %.1f s real" % [k, (Time.get_ticks_msec() - rt) / 1000.0])
	fg.up_all()
	PlaneRoster.line_on = true
	Hangars.on = true
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


func _data() -> void:
	var kinds := 0
	for k: StringName in VehicleSpecs.SPECS:
		if VehicleSpecs.cls_of(k) == &"plane":
			kinds += 1
	TestLib.check(kinds >= 30 and PlaneRoster.KINDS.size() >= 30, "30+ aeroplane kinds (%d)" % kinds)
	var nums := {}
	var roles := {}
	for k: StringName in PlaneRoster.NEW:
		var sp: Dictionary = VehicleSpecs.SPECS.get(k, {})
		var m := VehicleCraftModels.build(String(sp.get("procedural", "")), sp) if not sp.is_empty() else null
		var ok := m != null and m.get_node_or_null("Body") != null
		var tri := PlaneModels.tri_count(k)
		ok = ok and tri > 300 and tri < 6000 and AudioDirector.ENGINES.has(k) and ResourceLoader.exists(ItemIcons.path("v", k)) and VehicleSpecs.name_of(k) != String(k)
		ok = ok and float(sp.get("stall", 0.0)) < float(sp.get("max", 0.0)) and sp.has("roll") and sp.has("pitch") and float(sp.get("run", 9999.0)) < Airport.RUNWAY_LEN - 150.0
		if sp.has("prop_r"):
			ok = ok and m.get_node_or_null("Prop") != null
		var key := "%s/%s/%s/%s/%s" % [sp.get("max"), sp.get("stall"), sp.get("roll"), sp.get("pitch"), sp.get("mass")]
		ok = ok and not nums.has(key)
		nums[key] = true
		roles[PlaneRoster.DEFS[k]["role"]] = true
		TestLib.check(ok, "%s %s (%s): own model (%d triangles), own flight numbers max/stall/roll/pitch/mass %s, run %s m, engine sound, icon" % [k, VehicleSpecs.name_of(k), PlaneRoster.DEFS[k]["role"], tri, key, sp.get("run")])
		if m != null:
			m.free()
	TestLib.check(roles.size() >= 20, "the roster covers %d roles (light, trainer, airliners, fighters, bomber, tanker, AWACS, drones, glider, sci-fi ...)" % roles.size())
	var m1 := VehicleCraftModels.build("p_narrow", VehicleSpecs.SPECS[&"p_narrow"])
	var m2 := VehicleCraftModels.build("p_narrow", VehicleSpecs.SPECS[&"p_narrow"])
	TestLib.check((m1.get_node("Body") as MeshInstance3D).mesh == (m2.get_node("Body") as MeshInstance3D).mesh, "two planes of a kind share one mesh")
	TestLib.check((m1.get_node("Detail") as GeometryInstance3D).visibility_range_end > 0.0, "the landing gear and small parts drop out with distance (LOD)")
	m1.free()
	m2.free()


## Put the hero at `stand` facing `at` and wait for the fixed spawn point `id` to stand its vehicle.
func _place_hero(stand: Vector3, at: Vector3, id: StringName) -> Vehicle:
	if vm.driven != null:
		await _tap(&"interact")
	fg.up_all()
	var d := at - stand
	var yaw := atan2(-d.x, -d.z)
	p.snake.cancel()
	p.snake.reset()
	p.teleport_to(stand + Vector3(0.0, 0.3, 0.0))
	p.camera_rig.reset_view(yaw, -0.1)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await _f(20)
	vm._spawn_t = 0.0
	var v: Vehicle = null
	var t0 := _t
	while _t - t0 < 14.0:                                    # the fixed points near the hero appear one a second (several planes of the line stand within 112 m)
		await _step()
		var x: Variant = vm._spawned.get(id)
		if is_instance_valid(x) and (x as Vehicle).active:
			v = x
			break
	return v


## Walk forward by the stick until the context button says ENTER, then a finger on it.
func _walk_board(v: Vehicle) -> bool:
	fg.stick(Vector2(0.0, -1.0))
	var reached := await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 14.0)
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle != null, 1.0)
	return reached and p.vehicle == v


func _hangar(sid: StringName, k: StringName) -> void:
	var s := Hangars.site(sid)
	var df := Hangars.door_frame(s)
	var c: Vector3 = df["c"]
	var out: Vector3 = df["out"]
	var door_w := Airport.to_world(c)
	var far := Airport.to_world(c + out * 42.0)
	var pl: Array = PlaneRoster.PLACES[k]
	var plane_w := Airport.to_world(pl[0])
	var v := await _place_hero(far, door_w, StringName("hg_" + String(k)))
	TestLib.check(v != null and v.kind == k, "[old fails] %s waits inside %s" % [k, s["name"]])
	TestLib.check(Hangars.Doors.open_of(sid) < 0.05, "%s: the door is shut while nobody is near (%.2f)" % [s["name"], Hangars.Doors.open_of(sid)])
	# walk to the door by the stick: it slides open; keep walking: the hero is inside
	fg.stick(Vector2(0.0, -1.0))
	var opened := await _until(func() -> bool: return Hangars.Doors.open_of(sid) > 0.95, 14.0)
	var inside := await _until(func() -> bool: return Hangars.inside(s, Airport.to_local(p.global_position)), 10.0)
	fg.stick(Vector2.ZERO)
	TestLib.check(opened and inside, "[old fails] %s: walking up by the stick opens the door (%.2f) and the hero walks in (%s, %.1f m from the door)" % [s["name"], Hangars.Doors.open_of(sid), inside, _flat(p.global_position, door_w)])
	if v == null:
		return
	# board the plane inside: stand in front of its nose (between it and the door), walk to it
	var stand := v.global_position + v.forward() * (float(v.spec["len"]) * 0.5 + 3.5)
	p.teleport_to(stand + Vector3(0.0, 0.3, 0.0))
	var d := v.global_position - stand
	p.yaw = atan2(-d.x, -d.z)
	p.camera_rig.reset_view(p.yaw, -0.1)
	await _f(10)
	var boarded := await _walk_board(v)
	TestLib.check(boarded, "%s: inside %s a finger on ENTER boards it" % [k, s["name"]])
	if not boarded:
		return
	# roll it out through the door: stick forward (throttle), the stick steers it straight
	var from := v.global_position
	fg.stick(Vector2(0.0, -1.0))
	var outside := await _until(func() -> bool:
		var lp := Airport.to_local(v.global_position)
		if OS.get_environment("PLANES_DEBUG") == "1" and Engine.get_physics_frames() % 20 == 0:
			print("roll ", lp, " hp ", v.hp, " v ", v.speed, " air ", v.craft.airborne, " hits ", v.hits)
		return (lp - c).dot(out) > float(v.spec["len"]) * 0.5 + 2.0, 30.0)
	fg.stick(Vector2(0.0, 1.0))
	await _until(func() -> bool: return v.speed < 2.0, 15.0)
	fg.stick(Vector2.ZERO)
	TestLib.check(outside and v.hp > v.max_hp * 0.8, "%s: the stick rolls it out through the open door (%.0f m, hp %.0f of %.0f)" % [k, _flat(v.global_position, from), v.hp, v.max_hp])
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == null, 1.0)
	TestLib.check(p.vehicle == null, "%s: EXIT on the apron" % k)
	# walk away: the door closes behind
	p.teleport_to(Airport.to_world(c + out * 80.0) + Vector3(0.0, 0.3, 0.0))
	var shut := await _until(func() -> bool: return Hangars.Doors.open_of(sid) < 0.05, 10.0)
	TestLib.check(shut, "%s: the door slides shut when the hero is gone" % s["name"])


func _kind(k: StringName) -> void:
	var pl: Array = PlaneRoster.PLACES[k]
	var line: bool = PlaneRoster.DEFS[k]["place"] == &"line"
	var id := StringName(("pl_" if line else "hg_") + String(k))
	var pos := Airport.to_world(pl[0])
	var spec: Dictionary = VehicleSpecs.SPECS[k]
	var fwd := Vector3(-sin(Airport.heading_world(float(pl[1]))), 0.0, -cos(Airport.heading_world(float(pl[1]))))
	var stand := pos + fwd * (float(spec["len"]) * 0.5 + 3.5)
	var v := await _place_hero(stand, pos, id)
	if v == null and OS.get_environment("PLANES_DEBUG") == "1":
		print("spawn debug ", k, " free ", vm._spot_free(pos, 7.0), " hull ", vm._hull_ok(k, pos, Airport.heading_world(float(pl[1])), true), " fixed ", ArmourSites.is_fixed(id))
		for o in vm.list:
			if _flat(o.global_position, pos) < 40.0:
				print("  near ", o.kind, " ", _flat(o.global_position, pos))
	TestLib.check(v != null and v.kind == k, "[old fails] %s %s waits at its place (%s)" % [k, VehicleSpecs.name_of(k), "PLANE LINE" if line else String(PlaneRoster.DEFS[k]["place"])])
	if v == null:
		return
	var boarded := await _walk_board(v)
	TestLib.check(boarded, "%s: walk up by the stick, a finger on ENTER boards it (label %s, %.1f m)" % [k, fg.button_label(&"interact"), _flat(p.global_position, v.global_position)])
	if not boarded:
		return
	await _flight(v)


## A hop on runway 09 (the 140 s runner cap leaves no time for a full circuit for 28 kinds): only the stick and the UP / DOWN / EXIT buttons. Stick forward + UP: the
## take-off run; UP to a safe height; the stick banks it (it turns) and brings it back on the runway axis; stick back + DOWN: it comes down on the same runway; stick back brakes.
func _flight(v: Vehicle) -> void:
	var k := v.kind
	var th := Airport.thresholds()
	var t09: Vector3 = th[0]["pos"]
	var t27: Vector3 = th[1]["pos"]
	var dir := (t27 - t09).normalized()
	var side := Vector3(-dir.z, 0.0, dir.x)
	v.global_position = Vector3(t09.x, v.base_y, t09.z) + dir * (40.0 + float(v.spec["len"]) * 0.5)    # set-up: the boarded plane is put on runway 09, ahead of the SMALL PLANE that waits 24 m in (ap_runway)
	v.heading = float(th[0]["heading"])
	v.vel = Vector3.ZERO
	v.speed = 0.0
	v.craft.lever = 0.0
	await _f(4)
	var A := AircraftFlight.air(v.craft)
	var hp0 := v.hp
	var stall := float(v.spec["stall"])
	var start := v.global_position
	fg.stick(Vector2(0.0, -1.0))
	fg.press(1, &"jump")
	var off := await _until(func() -> bool: return v.craft.airborne, 30.0)
	var run := _flat(v.global_position, start)
	TestLib.check(off and run < Airport.RUNWAY_LEN - 40.0, "%s: stick forward and UP take it off inside the runway (%.0f m of %.0f, stall %.0f m/s)" % [k, run, Airport.RUNWAY_LEN, stall])
	if not off:
		fg.up_all()
		return
	var up := await _until(func() -> bool: return VehicleCraft.altitude(v) > 9.0, 8.0)
	# the stick banks it right: the wings roll and the heading follows
	var h0 := v.heading
	var max_roll := 0.0
	var t1 := _t
	while _t - t1 < 0.8:
		fg.stick(Vector2(0.7, 0.0))
		max_roll = maxf(max_roll, absf(A.roll))
		await _step()
	var turned := absf(wrapf(v.heading - h0, -PI, PI))
	fg.up(1)
	# back to the runway axis and down: stick back (throttle off) and DOWN, the stick steers toward a point ahead on the axis
	var held := &""
	var landed := false
	var t2 := _t
	while _t - t2 < 40.0:
		await _step()
		var gp := v.global_position
		var along := (gp - t09).dot(dir)
		var target := t09 + dir * (along + 90.0)
		var want := atan2(-(target.x - gp.x), -(target.z - gp.z))
		var err := wrapf(want - v.heading, -PI, PI)
		var sx := clampf(-2.0 * err + 0.6 * v.yaw_rate, -1.0, 1.0)
		var sy := 1.0 if v.speed > stall * 1.05 else 0.0
		fg.stick(Vector2(sx, sy) if absf(sx) + sy > 0.02 else Vector2(0.0, 0.01))
		var lift := &"crouch" if absf(err) < 0.25 else &""
		if lift != held:
			fg.up(1)
			if lift != &"":
				fg.press(1, lift)
			held = lift
		if not v.craft.airborne:
			landed = true
			break
	fg.up(1)
	TestLib.check(up and max_roll > 0.15 and turned > 0.03, "%s: UP climbs it (%s), the stick banks it (roll %.2f rad) and turns it (%.2f rad)" % [k, up, max_roll, turned])
	var gp2 := v.global_position
	var lat := absf((gp2 - t09).dot(side))
	var al := (gp2 - t09).dot(dir)
	TestLib.check(landed and lat < Airport.RUNWAY_W * 0.5 and al < Airport.RUNWAY_LEN - 20.0 and A.crashes == 0 and A.wing_strikes == 0,
		"%s: stick back and DOWN put it down on the runway (%.0f m along, %.0f m off the axis, crashes %d, wing strikes %d)" % [k, al, lat, A.crashes, A.wing_strikes])
	var stopped := await _until(func() -> bool:                 # stick back brakes; its sideways part keeps the nose wheel on the runway axis
		var g := v.global_position
		var tg := t09 + dir * ((g - t09).dot(dir) + 40.0)
		var e2 := wrapf(atan2(-(tg.x - g.x), -(tg.z - g.z)) - v.heading, -PI, PI)
		fg.stick(Vector2(clampf(-2.5 * e2, -0.7, 0.7), 1.0))
		if OS.get_environment("PLANES_DEBUG") == "1" and Engine.get_physics_frames() % 15 == 0:
			print("brake ", Airport.to_local(v.global_position), " hp ", v.hp, " v ", v.speed, " air ", v.craft.airborne, " hits ", v.hits, " pitch ", A.pitch)
		return v.speed < 3.0, 30.0)
	fg.stick(Vector2.ZERO)
	var al3 := (v.global_position - t09).dot(dir)
	TestLib.check(stopped and al3 < Airport.RUNWAY_LEN + 10.0 and v.hp > hp0 * 0.9, "%s: the stick back brakes it to a stop on the runway (%.0f m along, hp %.0f of %.0f)" % [k, al3, v.hp, hp0])
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == null, 1.0)
	TestLib.check(p.vehicle == null, "%s: a finger on EXIT leaves it" % k)
