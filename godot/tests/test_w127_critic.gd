extends RefCounted
## WAVE 127 CRITIC (w127-critic): the defects of the tank wave found by a finger-only review, each check driving the real main scene with REAL fingers (tests/w116_fingers.gd:
## InputEventScreenTouch / ScreenDrag through Input.parse_input_event), Game.force_touch, phone-only layers on (CrateReveal._quiet = 0). Set-up only places the hero and a vehicle.
##  1 KERB CARS: a battle tank driven by the stick into a parked kerb car shoves or crushes it and drives on (it used to stop dead at it, as at a wall)
##  2 BRIDGES: the heavy tank crosses the curved PASS ROAD bridge (the deck had gaps on the outer side of every bend: the tank sank into the deck and stuck, a car fell through into the
##    river) and the steep MOUNTAIN TRACK bridge (the flat hull box met the 14 % ramp and stopped), steered by the stick only
##  3 CHECKPOINTS: every vehicle waiting at a road checkpoint can be driven straight out by the stick (the FOREST ROAD half-track stood nose against a tree trunk 4.8 m ahead)
##  4 DRAW CALLS: a wave 127 vehicle draws its hull, turret, gun and flail as one surface each (it was up to four each: 7 to 11 draw calls a vehicle, nine tanks in view put LOW at
##    149-161 draws against 100); the parked vehicle still wears its own paint, its tracks and trim stay dark (vertex colours under the paint)
## W127C_OLD=1 is the code before the fixes: the checks marked [old fails] fail.
## Run: tools/test.sh tests/test_w127_critic.gd
const TIMEOUT_SECONDS := 140
const Fingers := preload("res://tests/w116_fingers.gd")

var host: Node
var fg: Fingers
var p: Player
var vm: VehicleManager
var _t := 0.0


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
	var old := OS.get_environment("W127C_OLD") == "1"
	ParkedCars.tank_crush_on = not old
	Bridges.wedge_on = not old
	TankRoster.clear_on = not old
	TankModels.merge_on = not old
	TankModels._cache.clear()
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
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 2.0
	Engine.max_physics_steps_per_frame = 4
	var parts := OS.get_environment("CRITIC_PARTS")
	if parts == "" or parts.contains("kerb"):
		await _kerb()
	if parts == "" or parts.contains("bridge"):
		await _bridges()
	if parts == "" or parts.contains("checkpoint"):
		await _checkpoints()
	if parts == "" or parts.contains("draws"):
		await _draws()
	fg.up_all()
	ParkedCars.tank_crush_on = true
	Bridges.wedge_on = true
	TankRoster.clear_on = true
	TankModels.merge_on = true
	TankModels._cache.clear()
	TankRoster._points.clear()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


## Puts the hero `back` metres behind vehicle `v` and boards it with the stick and a finger on ENTER.
func _board(v: Vehicle, back := 7.0) -> bool:
	fg.up_all()
	var at := v.global_position - v.forward() * (float(v.spec["len"]) * 0.5 + back)
	p.teleport_to(at + Vector3(0.0, 0.4, 0.0))
	var d := v.global_position - at
	p.yaw = atan2(-d.x, -d.z)
	p.camera_rig.reset_view(p.yaw, -0.1)
	p.velocity = Vector3.ZERO
	await _f(10)
	fg.stick(Vector2(0.0, -0.7))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 8.0)
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == v, 1.5)
	return p.vehicle == v


func _leave() -> void:
	if p.vehicle != null:
		fg.up_all()
		await _tap(&"interact")
		await _until(func() -> bool: return p.vehicle == null, 1.5)


# --- 1 KERB CARS -----------------------------------------------------------------------------------------------------------------------

func _kerb() -> void:
	var pc := ParkedCars.instance
	if pc == null:
		TestLib.check(false, "the city has kerb cars")
		return
	# a kerb car near the start, in a row of the street: the tank comes at it from behind along its own axis
	var best := -1
	var space := host.get_tree().root.get_world_3d().direct_space_state
	for i in pc._n:
		if not pc.car_alive(i):
			continue
		var c := pc.car_position(i)
		if _flat(c, p.global_position) > 70.0:
			continue
		var f := Vector3(-sin(pc.car_yaw(i)), 0.0, -cos(pc.car_yaw(i)))
		var from := c - f * 17.0 + Vector3(0.0, 1.2, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, c - f * 3.5 + Vector3(0.0, 1.2, 0.0), Game.L_WORLD)       # a clear run-up behind it (no building, prop or other kerb car)
		if space.intersect_ray(q).is_empty() and pc.car_near(c - f * 10.0, 1.5) < 0:
			best = i
			break
	TestLib.check(best >= 0, "a kerb car with a clear run-up behind it near the start (%d kerb cars)" % pc.alive_count())
	if best < 0:
		return
	var car := pc.car_position(best)
	var fwd := Vector3(-sin(pc.car_yaw(best)), 0.0, -cos(pc.car_yaw(best)))
	vm._fixed_n += 1
	var tk := vm.spawn_parked(&"tank", car - fwd * 13.0, pc.car_yaw(best))
	tk.set_meta(&"hold", true)
	vm._count_fixed()
	await _f(6)
	var boarded := await _board(tk)
	TestLib.check(boarded, "a finger on ENTER boards the battle tank behind the kerb car")
	if not boarded:
		return
	var start := tk.global_position
	var hp0 := tk.hp
	fg.stick(Vector2(0.0, -1.0))
	var through := await _until(func() -> bool: return (tk.global_position - start).dot(fwd) > 20.0, 10.0)
	fg.stick(Vector2.ZERO)
	var gone := not pc.car_alive(best)
	TestLib.check(through and gone, "[old fails] the stick drives the tank into the kerb car and on past its spot: it shoves or crushes it (%.1f m driven of 20, kerb car %s, tank hull %d -> %d)" % [
		(tk.global_position - start).dot(fwd), "taken off the kerb" if gone else "still a wall", roundi(hp0), roundi(tk.hp)])
	await _leave()
	tk.remove_meta(&"hold")
	if tk.active:
		vm._release(tk)
	vm._count_fixed()


# --- 2 BRIDGES -------------------------------------------------------------------------------------------------------------------------

func _bridges() -> void:
	Bridges.ensure()
	for id: StringName in [&"pass_road_0", &"mountain_track_4"]:
		var b := Bridges.by_id(id)
		if b.is_empty():
			TestLib.check(false, "bridge %s exists" % id)
			continue
		var L := float(b["len"])
		var a0: Array = Bridges.point_at(b, 0.0)
		var dir: Vector3 = a0[1]
		var start: Vector3 = (a0[0] as Vector3) - dir * 22.0
		start.y = TerrainHeight.height_at(start.x, start.z)
		vm._fixed_n += 1
		var tk := vm.spawn_parked(&"t_heavy", start, atan2(-dir.x, -dir.z))
		tk.set_meta(&"hold", true)
		vm._count_fixed()
		tk.global_position = start
		await _f(6)
		if not await _board(tk, 5.0):
			TestLib.check(false, "a finger on ENTER boards the heavy tank before %s" % b["name"])
			continue
		var u_best := -22.0
		var under := 0.0
		var t0 := _t
		while _t - t0 < L / 5.0 + 14.0 and u_best < L - 4.0:
			var u := (tk.global_position - (a0[0] as Vector3)).dot(dir)
			u_best = maxf(u_best, u)
			var e: Array = Bridges.point_at(b, clampf(u, 0.0, L))
			var want: Vector3 = (e[0] as Vector3) + (e[1] as Vector3) * 12.0
			var d := want - tk.global_position
			var err := wrapf(atan2(-d.x, -d.z) - tk.heading, -PI, PI)
			fg.stick(Vector2(clampf(-err * 2.0, -1.0, 1.0), -1.0))                 # the thumb keeps the tank on the deck's centre line
			await _step()
			if u > 3.0 and u < L - 3.0:
				var dy := Bridges.deck_y(tk.global_position.x, tk.global_position.z, tk.global_position.y + 2.0)
				var deck := dy if dy != Bridges.NONE else (e[0] as Vector3).y
				under = maxf(under, deck - tk.global_position.y)
		fg.stick(Vector2.ZERO)
		TestLib.check(u_best >= L - 4.0 and under < 0.6, "[old fails] the stick drives the heavy tank across %s (%s, %d m, curved / steep): %d m of %d, never more than %.2f m under the deck" % [
			b["name"], id, roundi(L), roundi(u_best), roundi(L), under])
		await _leave()
		tk.remove_meta(&"hold")
		if tk.active:
			vm._release(tk)
		vm._count_fixed()


# --- 3 CHECKPOINTS ---------------------------------------------------------------------------------------------------------------------

func _checkpoints() -> void:
	TankRoster._points.clear()
	TankRoster._sites.clear()
	var n := 0
	for pt: Dictionary in TankRoster.spawn_points():
		if not String(pt["label"]).contains("CHECKPOINT"):
			continue
		n += 1
		var k: StringName = pt["kind"]
		var pos: Vector3 = pt["pos"]
		var hh := float(pt["h"])
		var fwd := Vector3(-sin(hh), 0.0, -cos(hh))
		var side := Vector3(cos(hh), 0.0, -sin(hh))
		await _leave()
		fg.up_all()
		var stand := pos - side * (float(VehicleSpecs.SPECS[k]["wid"]) * 0.5 + 4.0)
		p.teleport_to(Vector3(stand.x, TerrainHeight.height_at(stand.x, stand.z) + 0.5, stand.z))
		var d := pos - stand
		p.yaw = atan2(-d.x, -d.z)
		p.camera_rig.reset_view(p.yaw, -0.1)
		p.velocity = Vector3.ZERO
		await _f(10)
		vm._spawn_t = 0.0
		var v: Vehicle = null
		var t0 := _t
		while _t - t0 < 14.0:
			await _step()
			var x: Variant = vm._spawned.get(pt["id"])
			if is_instance_valid(x) and (x as Vehicle).active:
				v = x
				break
		if v == null:
			TestLib.check(false, "%s waits at %s" % [k, pt["label"]])
			continue
		fg.stick(Vector2(0.0, -0.7))
		await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 8.0)
		fg.stick(Vector2.ZERO)
		await _f(3)
		await _tap(&"interact")
		await _until(func() -> bool: return p.vehicle == v, 1.5)
		if p.vehicle != v:
			TestLib.check(false, "%s at %s: a finger on ENTER boards it" % [k, pt["label"]])
			continue
		if VegetationWorld.instance != null:
			VegetationWorld.instance.settle(v.global_position)                 # the trunk colliders around the place are built (a teleport leaves them to the worker)
		await _f(4)
		var from := v.global_position
		fg.stick(Vector2(0.0, -1.0))
		await _until(func() -> bool: return _flat(v.global_position, from) >= 16.0, 7.0)
		fg.stick(Vector2.ZERO)
		TestLib.check(_flat(v.global_position, from) >= 16.0, "[old fails] %s at %s: the stick drives it straight out of its place (%.1f m of 16)" % [k, pt["label"], _flat(v.global_position, from)])
	TestLib.check(n >= 6, "six vehicles wait at the three road checkpoints (%d)" % n)
	await _leave()


# --- 4 DRAW CALLS ----------------------------------------------------------------------------------------------------------------------

func _draws() -> void:
	var worst := 0
	var worst_k := &""
	for k: StringName in TankRoster.NEW:
		var sp: Dictionary = VehicleSpecs.SPECS[k]
		var m := VehicleCraftModels.build(String(sp.get("procedural", "")), sp)
		var n := 0
		for g in m.find_children("*", "GeometryInstance3D", true, false):
			if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
				n += (g as MeshInstance3D).mesh.get_surface_count()
			elif g is MultiMeshInstance3D:
				n += (g as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
		m.free()
		if n > worst:
			worst = n
			worst_k = k
	TestLib.check(worst <= 6, "[old fails] every wave 127 vehicle costs at most 6 draw calls (the worst, %s, %d)" % [worst_k, worst])
	# a parked one in the street: its own paint on the hull and the turret, dark tracks under it
	var at := p.global_position + Vector3(12.0, 0.0, 0.0)
	vm._fixed_n += 1
	var v := vm.spawn_parked(&"t_ifv", at, 0.0)
	vm._count_fixed()
	if v == null:
		TestLib.check(false, "an IFV parks beside the hero")
		return
	v.visual.set_paint(Color(0.2, 0.5, 0.25))
	await _f(3)
	var body := v.visual.model.get_node("Body") as MeshInstance3D
	var tur := v.visual.model.get_node("Turret") as MeshInstance3D
	var bm := body.get_surface_override_material(0) as BaseMaterial3D
	var tm := tur.get_surface_override_material(0) as BaseMaterial3D
	var cols: PackedColorArray = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] if body.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var dark := 0
	for c in cols:
		if c.v < 0.15:
			dark += 1
	TestLib.check(bm != null and tm == bm and bm.vertex_color_use_as_albedo and bm.albedo_color.g > bm.albedo_color.r and dark > cols.size() / 10,
		"the IFV wears its own paint on hull and turret (%s), its tracks and trim stay dark under it (%d of %d vertices dark)" % [bm.albedo_color if bm != null else "none", dark, cols.size()])
	if v.active:
		vm._release(v)
	vm._count_fixed()
