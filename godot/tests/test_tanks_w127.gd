extends RefCounted
## WAVE 127 TANKS AND MILITARY GROUND VEHICLES, driven by REAL FINGERS in the real main scene (InputEventScreenTouch / ScreenDrag through tests/w116_fingers.gd, Game.force_touch,
## phone-only layers on: CrateReveal._quiet = 0). Nothing here calls a game function to act; set-up only puts the hero in front of a vehicle's parking place.
##  * data (this file): 20+ military ground vehicle kinds, each new kind with its own model (Body, Turret, Gun, moving running gear, shared meshes), its own driving numbers
##    (max, acc, steer, mass, plate), engine sound, icon, name; the running gear drops out with distance (LOD)
##  * every new kind: it waits at its place (ARMY BASE / VEHICLE DEPOT / a road CHECKPOINT) as a FIXED vehicle outside the live car cap; the hero walks up by the stick and boards it
##    with a finger on ENTER; the stick drives it a short route forward (its tracks / tyres / legs move) and turns it; a swipe of the right thumb turns its turret; EXIT leaves it
## W127_TANKS_OLD=1 is the wave 126 state (no new kind stands anywhere, nothing animates): the checks marked [old fails] fail.
## Split over two files (140 s runner cap): this one holds the data and the even kinds (0, 2, 4 ...), test_tanks_w127_b.gd the odd ones. TANKS_KINDS=t_heavy,t_jeep drives only those.
## Run: tools/test.sh tests/test_tanks_w127.gd
const TIMEOUT_SECONDS := 600
const Fingers := preload("res://tests/w116_fingers.gd")

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
	var old := OS.get_environment("W127_TANKS_OLD") == "1"
	TankRoster.on = not old
	TankModels.on = not old
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
	TankRoster._points.clear()                              # (the roads exist now: the checkpoints join the list)
	var pick := OS.get_environment("TANKS_KINDS")
	for i in TankRoster.NEW.size():
		var k: StringName = TankRoster.NEW[i]
		if pick != "" and not k in pick.split(","):
			continue
		if pick == "" and i % 2 != part:
			continue
		var rt := Time.get_ticks_msec()
		await _kind(k)
		if vm.driven != null:
			await _tap(&"interact")
		print("%s took %.1f s real" % [k, (Time.get_ticks_msec() - rt) / 1000.0])
	fg.up_all()
	TankRoster.on = true
	TankModels.on = true
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
		if VehicleSpecs.cls_of(k) == &"tank":
			kinds += 1
	TestLib.check(kinds >= 20 and TankRoster.KINDS.size() >= 20, "20+ military ground vehicle kinds (%d on the tracked physics, %d in the roster)" % [kinds, TankRoster.KINDS.size()])
	var nums := {}
	var roles := {}
	for k: StringName in TankRoster.NEW:
		var sp: Dictionary = VehicleSpecs.SPECS.get(k, {})
		var m := VehicleCraftModels.build(String(sp.get("procedural", "")), sp) if not sp.is_empty() else null
		var ok := m != null and m.get_node_or_null("Body") != null and m.get_node_or_null("Turret") != null and m.get_node_or_null("Turret/Gun") != null
		var run := String(TankRoster.DEFS[k]["run"])
		var gear := m != null and (run == "hover" or m.get_node_or_null("Run") is MultiMeshInstance3D)
		var tri := TankModels.tri_count(k)
		ok = ok and gear and tri > 300 and tri < 6000 and AudioDirector.ENGINES.has(k) and ResourceLoader.exists(ItemIcons.path("v", k)) and VehicleSpecs.name_of(k) != String(k)
		ok = ok and VehicleSpecs.TANK_KINDS.has(k) and VehicleSpecs.ROSTER.has(k) and sp.has("plate")
		var key := "%s/%s/%s/%s/%s" % [sp.get("max"), sp.get("acc"), sp.get("steer"), sp.get("mass"), sp.get("plate")]
		ok = ok and not nums.has(key)
		nums[key] = true
		roles[TankRoster.DEFS[k]["role"]] = true
		TestLib.check(ok, "%s %s (%s, %s): own model with turret, gun and moving gear (%d triangles), own numbers max/acc/steer/mass/plate %s, engine sound, icon" % [k, VehicleSpecs.name_of(k), TankRoster.DEFS[k]["role"], run, tri, key])
		if m != null:
			m.free()
	TestLib.check(roles.size() >= 20, "the roster covers %d roles (heavy tank, tank destroyer, SPG, rockets, carriers, IFV, scout, MRAP, jeep, trucks, engineers, AA, sci-fi ...)" % roles.size())
	var m1 := VehicleCraftModels.build("t_heavy", VehicleSpecs.SPECS[&"t_heavy"])
	var m2 := VehicleCraftModels.build("t_heavy", VehicleSpecs.SPECS[&"t_heavy"])
	TestLib.check((m1.get_node("Body") as MeshInstance3D).mesh == (m2.get_node("Body") as MeshInstance3D).mesh and (m1.get_node("Run") as MultiMeshInstance3D).multimesh.mesh == (m2.get_node("Run") as MultiMeshInstance3D).multimesh.mesh,
		"two vehicles of a kind share their meshes")
	TestLib.check((m1.get_node("Run") as GeometryInstance3D).visibility_range_end > 0.0 and (m1.get_node("Run2") as GeometryInstance3D).visibility_range_end > 0.0, "the moving track cleats and road wheels drop out with distance (LOD)")
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
	p.teleport_to(stand + Vector3(0.0, 0.4, 0.0))
	p.camera_rig.reset_view(yaw, -0.1)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await _f(20)
	vm._spawn_t = 0.0
	var v: Vehicle = null
	var t0 := _t
	while _t - t0 < 14.0:                                    # the fixed points near the hero appear one a second
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


## The running gear's first instance transforms (to see them move).
func _gear(v: Vehicle) -> Array:
	var out: Array = []
	for rn: String in ["Run", "Run2"]:
		var mmi := v.visual.model.get_node_or_null(rn) as MultiMeshInstance3D
		if mmi == null:
			continue
		var pose := TankModels.pose_of(v.visual.model, rn)                   # (what the game last drew: a MultiMesh cannot be read back without a renderer)
		for i in mini(mmi.multimesh.instance_count, 6):
			out.append(pose[i] if i < pose.size() else null)
	return out


func _kind(k: StringName) -> void:
	var pt: Dictionary = {}
	for q: Dictionary in TankRoster.spawn_points():
		if q["kind"] == k:
			pt = q
	var spec: Dictionary = VehicleSpecs.SPECS[k]
	var place := String(TankRoster.DEFS[k]["place"]).to_upper().replace("_", " ")
	if pt.is_empty():
		TestLib.check(false, "[old fails] %s %s waits at its place (%s): no place in the list" % [k, VehicleSpecs.name_of(k), place])
		return
	var pos: Vector3 = pt["pos"]
	var hh := float(pt["h"])
	var fwd := Vector3(-sin(hh), 0.0, -cos(hh))
	var stand := pos + fwd * (float(spec["len"]) * 0.5 + 3.5)
	var v := await _place_hero(stand, pos, pt["id"])
	TestLib.check(v != null and v.kind == k and ArmourSites.is_fixed(pt["id"]), "[old fails] %s %s waits at its place (%s), a FIXED vehicle outside the live car cap" % [k, VehicleSpecs.name_of(k), pt["label"]])
	if v == null:
		return
	var boarded := await _walk_board(v)
	TestLib.check(boarded, "%s: walk up by the stick, a finger on ENTER boards it (label %s, %.1f m)" % [k, fg.button_label(&"interact"), _flat(p.global_position, v.global_position)])
	if not boarded:
		return
	# a short route: the stick forward drives it out of its bay (the running gear moves), the stick to the right turns it
	var from := v.global_position
	var g0 := _gear(v)
	var h0 := v.heading
	fg.stick(Vector2(0.0, -1.0))
	var drove := await _until(func() -> bool: return _flat(v.global_position, from) >= 9.0, 12.0)
	var g1 := _gear(v)
	var moved_gear := 0
	for i in mini(g0.size(), g1.size()):
		if g0[i] != null and g1[i] != null and not (g0[i] as Transform3D).is_equal_approx(g1[i]):
			moved_gear += 1
	TestLib.check(drove and absf(wrapf(v.heading - h0, -PI, PI)) < 0.6, "%s: the stick drives it forward out of its place (%.1f m)" % [k, _flat(v.global_position, from)])
	if String(TankRoster.DEFS[k]["run"]) == "hover":
		var lift := v.visual.model.position.y
		TestLib.check(lift > 0.3, "[old fails] %s: it floats on its thrusters (%.2f m)" % [k, lift])
	else:
		TestLib.check(moved_gear >= 2, "[old fails] %s: its %s move as it drives (%d of %d parts moved)" % [k, {"track": "tracks", "wheel": "wheels", "half": "tracks and wheels", "legs": "legs"}[String(TankRoster.DEFS[k]["run"])], moved_gear, g0.size()])
	var h1 := v.heading
	fg.stick(Vector2(1.0, -0.6))
	var turned := await _until(func() -> bool: return absf(wrapf(v.heading - h1, -PI, PI)) >= 0.6, 8.0)
	fg.stick(Vector2(0.0, 1.0))
	await _until(func() -> bool: return absf(v.speed) < 1.0, 6.0)
	fg.stick(Vector2.ZERO)
	TestLib.check(turned, "%s: the stick turns it (%.2f rad, %.1f m from its place)" % [k, absf(wrapf(v.heading - h1, -PI, PI)), _flat(v.global_position, from)])
	# the turret: a swipe of the right thumb turns the view, the turret follows the crosshair
	var tur := v.visual.parts.get("Turret") as Node3D
	var ty0 := tur.rotation.y if tur != null else 0.0
	fg.look(fg.vp().x * 0.45, 0.0)
	var slewed := await _until(func() -> bool: return tur != null and absf(wrapf(tur.rotation.y - ty0, -PI, PI)) > 0.35, 6.0)
	TestLib.check(slewed, "%s: a swipe of the right thumb turns the turret (%.2f rad)" % [k, absf(wrapf((tur.rotation.y if tur != null else 0.0) - ty0, -PI, PI))])
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == null, 1.0)
	TestLib.check(p.vehicle == null, "%s: a finger on EXIT leaves it" % k)
