extends RefCounted
## WAVE 125 HELICOPTER ROSTER: every one of the twenty new helicopter kinds (HeliRoster.NEW) stands on the HELI LINE of EASTFIELD AIRPORT and is flown by REAL FINGERS in the real main
## scene (InputEventScreenTouch / ScreenDrag through tests/w116_fingers.gd, Game.force_touch, phone-only layers on): walk to it (stick), ENTER, hold UP (lift off above 10 m), stick
## forward (a short route, 14 m), hold DOWN (land), EXIT. Plus the data: 22+ helicopter kinds, own model (Body + Rotor), own flight numbers, rotor pitch, icon file.
## HELIS_OLD=1 switches the HELI LINE off (the wave 124 state, the kinds cannot be found): the checks marked [old fails] fail. HELIS_KINDS=h_scout,h_tilt picks kinds.
## Run: tools/test.sh tests/test_helis_w125.gd
const TIMEOUT_SECONDS := 600
const Fingers := preload("res://tests/w116_fingers.gd")

var host: Node
var fg: Fingers
var p: Player
var vm: VehicleManager


func _f(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame


func _until(cond: Callable, secs: float) -> bool:
	for i in int(secs * 60.0):
		if cond.call():
			return true
		await host.get_tree().physics_frame
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
	var old := OS.get_environment("HELIS_OLD") == "1"
	HeliRoster.line_on = not old
	# --- the data
	var kinds := 0
	for k: StringName in VehicleSpecs.SPECS:
		if VehicleSpecs.cls_of(k) == &"heli":
			kinds += 1
	TestLib.check(kinds >= 22 and HeliRoster.KINDS.size() >= 22, "22+ helicopter kinds (%d)" % kinds)
	var nums := {}
	for k: StringName in HeliRoster.NEW:
		var sp: Dictionary = VehicleSpecs.SPECS.get(k, {})
		var m := VehicleCraftModels.build(String(sp.get("procedural", "")), sp) if not sp.is_empty() else null
		var ok := m != null and m.get_node_or_null("Body") != null and m.get_node_or_null("Rotor") != null
		var tri := HeliModels.tri_count(k)
		ok = ok and tri > 300 and tri < 6000 and AudioDirector.ENGINES.has(k) and ResourceLoader.exists(ItemIcons.path("v", k)) and VehicleSpecs.name_of(k) != String(k)
		var key := "%s/%s/%s/%s" % [sp.get("max"), sp.get("climb"), sp.get("agile"), sp.get("mass")]
		ok = ok and not nums.has(key)
		nums[key] = true
		TestLib.check(ok, "%s %s: own model (%d triangles), own flight numbers %s, rotor sound, icon" % [k, VehicleSpecs.name_of(k), tri, key])
		if m != null:
			m.free()
	var m1 := VehicleCraftModels.build("h_scout", VehicleSpecs.SPECS[&"h_scout"])
	var m2 := VehicleCraftModels.build("h_scout", VehicleSpecs.SPECS[&"h_scout"])
	TestLib.check((m1.get_node("Body") as MeshInstance3D).mesh == (m2.get_node("Body") as MeshInstance3D).mesh, "two helicopters of a kind share one mesh")
	m1.free()
	m2.free()
	# --- the real scene
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
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0
	Engine.max_physics_steps_per_frame = 3
	var pick := OS.get_environment("HELIS_KINDS")
	for i in HeliRoster.NEW.size():
		var k: StringName = HeliRoster.NEW[i]
		if pick != "" and not k in pick.split(","):
			continue
		await _fly(k, Airport.to_world(Vector3(HeliRoster.LINE_X, 0.0, HeliRoster.LINE_Z0 + HeliRoster.LINE_STEP * float(i))))
	fg.up_all()
	HeliRoster.line_on = true
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


func _fly(k: StringName, at: Vector3) -> void:
	if vm.driven != null:
		await _tap(&"interact")
	# the hero 12 m west of the pad (on the runway side), facing it
	var g := TerrainHeight.height_at(at.x, at.z)
	var dir := Vector3(-1.0, 0.0, 0.0)
	var stand := Vector3(at.x, g + 0.3, at.z) + Airport.FRAME.basis * Vector3(-12.0, 0.0, 0.0)
	var d := (at - stand)
	var yaw := atan2(-d.x, -d.z)
	fg.up_all()
	p.snake.cancel()
	p.snake.reset()
	p.teleport_to(stand)
	p.camera_rig.reset_view(yaw, -0.1)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await _f(20)                                                    # the prompt of the last place (the helicopter just left) clears first
	vm._spawn_t = 0.0
	var heli: Vehicle = null
	for t in 240:
		await host.get_tree().physics_frame
		var v: Variant = vm._spawned.get(StringName("hl_" + String(k)))
		if is_instance_valid(v) and (v as Vehicle).active:
			heli = v
			break
	TestLib.check(heli != null and heli.kind == k, "[old fails] %s stands on the HELI LINE" % k)
	if heli == null:
		return
	fg.stick(Vector2(0.0, -1.0))
	var reached := await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 12.0)
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle != null, 1.0)
	TestLib.check(reached and p.vehicle == heli, "%s: walk up by the stick, a finger on ENTER boards it (reached %s, %.1f m, edge %.1f, dy %.1f, label %s)" % [k, reached, _flat(p.global_position, heli.global_position), heli.edge_distance(p.global_position), p.global_position.y - heli.global_position.y, fg.button_label(&"interact")])
	if p.vehicle != heli:
		return
	var from := heli.global_position
	fg.press(1, &"jump")
	var up := await _until(func() -> bool: return VehicleCraft.altitude(heli) > 10.0, 12.0)
	fg.up(1)
	fg.stick(Vector2(0.0, -1.0))
	var flew := await _until(func() -> bool: return _flat(heli.global_position, from) > 14.0, 10.0)
	fg.stick(Vector2.ZERO)
	fg.press(1, &"crouch")
	var landed := await _until(func() -> bool: return not heli.craft.airborne and absf(heli.speed) < 6.0, 25.0)
	fg.up(1)
	TestLib.check(up and flew and landed, "%s: UP lifts it off (%s), the stick flies a route (%.0f m), DOWN lands it (%s)" % [k, up, _flat(heli.global_position, from), landed])
	await _until(func() -> bool: return true, 0.5)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == null, 1.0)
	TestLib.check(p.vehicle == null, "%s: a finger on EXIT leaves it" % k)
