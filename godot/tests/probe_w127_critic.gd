extends RefCounted
## w127-critic REVIEW PROBE (not a suite test: prints measurements). Real fingers only (tests/w116_fingers.gd), main.tscn, Game.force_touch, CrateReveal._quiet = 0.
## PARTS=kinds,fight,crash,bridge  (env) picks the sections.
##   godot --headless --path . res://tests/runner.tscn -- --test=res://tests/probe_w127_critic.gd
const TIMEOUT_SECONDS := 1500
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


func _wait(secs: float) -> void:
	await _until(func() -> bool: return false, secs)


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _f(4)
	fg.up(6)
	await _f(3)
	return true


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _ground_at(p0: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p0.x, p0.y + 30.0, p0.z), Vector3(p0.x, p0.y - 60.0, p0.z), Game.L_WORLD)
	var r := host.get_tree().root.get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		return r["position"]
	return Vector3(p0.x, TerrainHeight.height_at(p0.x, p0.z), p0.z)


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
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 2.0
	Engine.max_physics_steps_per_frame = 4
	TankRoster._points.clear()
	var parts := OS.get_environment("PARTS")
	if parts == "":
		parts = "kinds"
	for part in parts.split(","):
		print("=== PART %s" % part)
		match part:
			"kinds": await _kinds()
			"fight": await _fight()
			"crash": await _crash()
			"bridge": await _bridge()
	fg.up_all()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


func _place_hero(stand: Vector3, at: Vector3) -> void:
	if p.vehicle != null:
		await _tap(&"interact")
		await _f(10)
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


func _walk_board(v: Vehicle) -> bool:
	fg.stick(Vector2(0.0, -1.0))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 14.0)
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle != null, 1.0)
	return p.vehicle == v


## World AABB of every visible mesh of the vehicle model.
func _aabb(v: Vehicle) -> AABB:
	var box := AABB()
	var first := true
	for n in v.visual.model.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var a := gi.global_transform * gi.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box


func _report_geom(v: Vehicle, tag: String) -> void:
	var box := _aabb(v)
	var g := _ground_at(v.global_position)
	var sp := v.spec
	var gun := v.visual.model.get_node_or_null("Turret/Gun") as Node3D
	var mz := VehicleCraft.muzzle_origin(v)
	var gy := gun.global_position.y if gun != null else -999.0
	print("GEOM %s %s: model %.1fx%.1fx%.1f (spec len %.1f wid %.1f hgt %.1f) bottom-ground %.2f  vehicle y-ground %.2f  muzzle y %.2f gun pivot y %.2f (d %.2f)" % [tag, v.kind,
		box.size.z, box.size.x, box.size.y, float(sp["len"]), float(sp["wid"]), float(sp["hgt"]), box.position.y - g.y, v.global_position.y - g.y, mz.y - g.y, gy - g.y, mz.y - gy])


func _kinds() -> void:
	var pts := TankRoster.spawn_points()
	var n := 0
	var pick := OS.get_environment("KINDS")
	for pt: Dictionary in pts:
		var k: StringName = pt["kind"]
		if pick != "" and not String(k) in pick.split(","):
			continue
		var pos: Vector3 = pt["pos"]
		var hh := float(pt["h"])
		var fwd := Vector3(-sin(hh), 0.0, -cos(hh))
		var stand := pos + fwd * (float(VehicleSpecs.SPECS[k]["len"]) * 0.5 + 3.5)
		await _place_hero(stand, pos)
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
			print("KIND %s: no vehicle at its place" % k)
			continue
		await _f(5)
		_report_geom(v, "parked")
		if not await _walk_board(v):
			print("KIND %s: could not board (label %s)" % [k, fg.button_label(&"interact")])
			continue
		n += 1
		# buttons in tank mode: overlaps
		var shown: Array = []
		for b: Dictionary in TouchControls.BUTTONS:
			if fg.tc.button_visible(b):
				shown.append([String(b["action"]), fg.tc._label_of(b), fg.tc._button_center(b), float(b["r"]) * fg.tc._scale()])
		var ov := ""
		for i in shown.size():
			for j in range(i + 1, shown.size()):
				var dd := (shown[i][2] as Vector2).distance_to(shown[j][2])
				if dd < float(shown[i][3]) + float(shown[j][3]) - 2.0:
					ov += " %s/%s(%.0f)" % [shown[i][1], shown[j][1], dd]
		var labels := []
		for s in shown:
			labels.append(s[1])
		print("BUTTONS %s: %s  overlaps:%s" % [k, labels, ov])
		# drive forward 25 m
		var from := v.global_position
		fg.stick(Vector2(0.0, -1.0))
		var minc := 99.0
		var maxc := -99.0
		var tt := _t
		while _t - tt < 8.0 and _flat(v.global_position, from) < 25.0:
			await _step()
			var g := _ground_at(v.global_position)
			minc = minf(minc, v.global_position.y - g.y)
			maxc = maxf(maxc, v.global_position.y - g.y)
		var spd := v.speed
		if _flat(v.global_position, from) < 20.0:
			var sp3 := host.get_tree().root.get_world_3d().direct_space_state
			for hh2 in [0.5, 1.2, 2.0]:
				var o := v.global_position + Vector3(0.0, hh2, 0.0)
				var q := PhysicsRayQueryParameters3D.create(o, o + v.forward() * (float(v.spec["len"]) * 0.5 + 3.0), Game.L_WORLD | Game.L_VEHICLE)
				q.exclude = [v.get_rid()]
				var r := sp3.intersect_ray(q)
				print("STUCK %s at %s h %.1f: ray %.1f m: %s" % [k, v.global_position, hh2, (r["position"] - o).length() if not r.is_empty() else -1.0, (r["collider"] as Node).get_path() if not r.is_empty() else "nothing"])
		fg.stick(Vector2.ZERO)
		print("DRIVE %s: %.1f m in %.1f s, speed %.1f (max %.1f) height over ground %.2f..%.2f" % [k, _flat(v.global_position, from), _t - tt, spd, float(v.spec["max"]), minc, maxc])
		_report_geom(v, "driving")
		await _until(func() -> bool: return absf(v.speed) < 0.5, 4.0)
		# turret follows the look drag: swipe right, then measure the turret against the camera
		for sw in [0.30, -0.6]:
			fg.look(fg.vp().x * sw, 0.0)
			await _wait(3.0)
			var cam := p.camera_rig.camera
			var cf := -cam.global_basis.z
			var cam_yaw := atan2(-cf.x, -cf.z)
			var tur := v.visual.parts.get("Turret") as Node3D
			var tw := tur.global_basis if tur != null else v.global_basis
			var tf := -tw.z
			var tur_yaw := atan2(-tf.x, -tf.z)
			var ad := v.aim_dir() if v.has_method(&"aim_dir") else Vector3.ZERO
			print("TURRET %s swipe %.2f: camera yaw %.2f turret node yaw %.2f craft yaw %.2f aim_dir yaw %.2f  err %.2f rad" % [k, sw, cam_yaw, tur_yaw, v.craft.turret_yaw, atan2(-ad.x, -ad.z), absf(wrapf(tur_yaw - cam_yaw, -PI, PI))])
		# fire the main gun, then every arm, then smoke
		var s0: int = v.weapons.shots if v.weapons != null else -1
		if v.weapons != null and fg.press(2, &"fire"):
			await _wait(1.0)
			fg.up(2)
		print("FIRE %s: label %s shots %d -> %d" % [k, fg.button_label(&"fire"), s0, v.weapons.shots if v.weapons != null else -1])
		var ta := v.weapons.get("tarms") as TankArms if v.weapons != null else null
		if ta != null:
			var seen := {}
			for i in ta.list.size():
				var lab := fg.button_label(&"aim")
				var cur := ta.current()
				if seen.has(cur):
					break
				seen[cur] = true
				var a0: int = int(ta.ammo.get(cur, -1))
				if fg.press(2, &"aim"):
					await _wait(1.2)
					fg.up(2)
				await _wait(0.4)
				var a1: int = int(ta.ammo.get(cur, -1))
				print("ARM %s: %s (label %s) ammo %s -> %s" % [k, cur, lab, a0, a1])
				await _tap(&"arms_next")
			print("SMOKE %s: label %s  tap -> %s" % [k, fg.button_label(&"flare"), await _tap(&"flare")])
		else:
			print("ARM %s: no TankArms" % k)
		await _tap(&"interact")
		await _until(func() -> bool: return p.vehicle == null, 1.0)
	print("KINDS driven: %d" % n)


var hud: Hud
var board: MissionBoard
var _k := 0.0                 ## look px per radian of yaw (calibrated)


func _tap_at(pos: Vector2) -> void:
	fg.down(7, pos)
	await _f(2)
	fg.up(7)
	await _f(3)


func _hud_rect(id: StringName) -> Rect2:
	hud._ensure_layout()
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b["rect"]
	return Rect2()


func _cam_yp() -> Vector2:
	var cf := -p.camera_rig.camera.global_basis.z
	return Vector2(atan2(-cf.x, -cf.z), asin(clampf(cf.y, -1.0, 1.0)))


## The right thumb puts the crosshair on `pt` (closed loop of swipes). True when within `tol` rad.
func _aim_finger(pt: Vector3, tol := 0.02, tries := 12) -> bool:
	if _k == 0.0:
		var a := _cam_yp()
		fg.look(200.0, 0.0)
		await _f(4)
		var b := _cam_yp()
		var d := wrapf(b.x - a.x, -PI, PI)
		_k = -200.0 / d if absf(d) > 0.01 else -500.0
		print("AIM calibration: %.0f px per rad (yaw change %.3f)" % [_k, d])
	for i in tries:
		var cam := p.camera_rig.camera.global_position
		var d3 := pt - cam
		var want := Vector2(atan2(-d3.x, -d3.z), atan2(d3.y, Vector2(d3.x, d3.z).length()))
		var now := _cam_yp()
		var e := Vector2(wrapf(want.x - now.x, -PI, PI), want.y - now.y)
		if absf(e.x) < tol and absf(e.y) < tol * 2.0:
			return true
		fg.look(clampf(-e.x * _k, -500.0, 500.0), clampf(-e.y * absf(_k), -300.0, 300.0), 4)
		await _f(3)
	return false


func _board_start(t: StringName) -> bool:
	if board.is_running():
		board.abandon("TEST")
		await _f(4)
	await _place_hero(ArmourSites.YARD + Vector3(0.0, 0.0, 12.0), ArmourSites.YARD)
	board.world_offers = true
	board.offers.clear()
	await _tap_at(fg.tc._pause_center())
	await _until(func() -> bool: return Game.state == &"paused", 1.0)
	var r := _hud_rect(&"board_open")
	if r.has_area():
		await _tap_at(r.get_center())
	await _until(func() -> bool: return hud._board_open, 1.0)
	if not hud._board_open:
		print("MISSION %s: board did not open" % t)
		return false
	var idx := -1
	for tries in 10:
		for i in board.offers.size():
			if StringName(board.offers[i]["type"]) == t:
				idx = i
		if idx >= 0:
			break
		var nr := _hud_rect(&"board_new")
		if not nr.has_area():
			break
		await _tap_at(nr.get_center())
		await _f(2)
	if idx < 0:
		print("MISSION %s: not offered" % t)
		return false
	await _tap_at(_hud_rect(StringName("board_pick_%d" % idx)).get_center())
	await _until(func() -> bool: return board.is_running() and Game.state == &"play", 2.0)
	print("MISSION %s started: %s" % [t, board.is_running()])
	return board.is_running()


## The stick drives vehicle v to `goal` (within `rad`), steering by the heading error; backs off when stuck. Returns the metres left.
func _drive_to(v: Vehicle, goal: Vector3, rad: float, secs: float) -> float:
	var t0 := _t
	var last_pos := v.global_position
	var last_t := _t
	var stuck := 0
	while _t - t0 < secs and _flat(v.global_position, goal) > rad and p.vehicle == v:
		var d := goal - v.global_position
		var want := atan2(-d.x, -d.z)
		var e := wrapf(want - v.heading, -PI, PI)
		fg.stick(Vector2(clampf(-e * 1.5, -1.0, 1.0), -1.0 if absf(e) < 1.2 else -0.4))
		await _step()
		if _t - last_t > 3.0:
			if _flat(v.global_position, last_pos) < 3.0:
				stuck += 1
				print("DRIVE stuck at %s (%d m to goal) speed %.1f" % [v.global_position, roundi(_flat(v.global_position, goal)), v.speed])
				fg.stick(Vector2(clampf(e, -1.0, 1.0), 1.0))
				await _wait(2.0)
			last_pos = v.global_position
			last_t = _t
	fg.stick(Vector2.ZERO)
	print("DRIVE to goal: %d m left after %.0f s, %d stucks" % [roundi(_flat(v.global_position, goal)), _t - t0, stuck])
	return _flat(v.global_position, goal)


func _camp() -> CampaignRunner:
	return board._campaign()


func _fight() -> void:
	hud = host.get_tree().root.find_children("*", "Hud", true, false)[0] as Hud
	board = MissionBoardScreen.board()
	board.take_over = false
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0
	var which := OS.get_environment("MISSIONS")
	if which == "":
		which = "tank_battle"
	for t in which.split(","):
		await _mission(StringName(t))


func _mission(t: StringName) -> void:
	var done0 := board.done_count
	var t_start := _t
	if not await _board_start(t):
		return
	var k := _camp()
	var v: Vehicle = null
	var guard := 0
	while board.is_running() and _t - t_start < 900.0 and guard < 40:
		guard += 1
		var st: Dictionary = k.step
		print("STEP %d %s: %s  (hud %s) state %s running %s kind %s pos %s hero in %s" % [k.step_index, st.get("kind"), st.get("text"), k.hud_line(), k.state, board.is_running(), k.kind, k.pos, p.vehicle.kind if p.vehicle != null else "-"])
		var idx := k.step_index
		if st.get("kind") == "reach" and st.has("provide"):
			await _until(func() -> bool: return not k.ws.provided.is_empty(), 4.0)
			v = k.ws.provided[0] if not k.ws.provided.is_empty() else null
			if v == null:
				print("MISSION %s: no vehicle provided" % t)
				break
			var at := v.global_position + v.forward() * (float(v.spec["len"]) * 0.5 + 6.0)
			await _place_hero(at, v.global_position)
			if not await _walk_board(v):
				# the nose may be blocked: try the side
				await _place_hero(v.global_position + v.right() * (float(v.spec["wid"]) * 0.5 + 6.0), v.global_position)
				if not await _walk_board(v):
					print("MISSION %s: could not board the provided %s (label %s)" % [t, v.kind, fg.button_label(&"interact")])
					break
			await _until(func() -> bool: return k.step_index > idx, 3.0)
		elif st.get("kind") == "reach":
			await _drive_to(v, k.pos, float(st.get("radius", 14.0)) * 0.7, 400.0)
			await _until(func() -> bool: return k.step_index > idx or not board.is_running(), 3.0)
		elif st.get("kind") == "tank_task":
			await _task(v, k)
		else:
			print("MISSION %s: unknown step" % t)
			break
		if k.step_index == idx and board.is_running() and k.step == st:
			print("MISSION %s: step %d did not advance (%s)" % [t, idx, k.hud_line()])
			if guard > 4:
				break
	print("MISSION %s: finished %s (done %d -> %d) in %.0f game s, hero hp %.0f, tank hp %s, state %s" % [t, board.done_count > done0, done0, board.done_count, _t - t_start, p.hp, str(v.hp) if is_instance_valid(v) else "?", k.state])
	if board.is_running():
		board.abandon("TEST")
	await _f(4)


func _task(v: Vehicle, k: CampaignRunner) -> void:
	var tk := k.tank
	var t0 := _t
	var shots := 0
	var hits := 0
	while k.kind == &"tank_task" and k.state == &"active" and _t - t0 < 400.0 and p.vehicle == v:
		var tgt: Vehicle = null
		if not tk.enemies.is_empty():
			tgt = tk.enemies[0]
		elif not tk.targets.is_empty():
			tgt = tk.targets[0]
		if tgt == null:
			if not tk.trucks.is_empty():                           # convoy: keep up with the lead truck
				var lead := tk.trucks[0]
				if _flat(v.global_position, lead.global_position) > 30.0:
					await _drive_to(v, lead.global_position + lead.right() * 12.0, 15.0, 10.0)
				else:
					await _wait(0.5)
				continue
			await _wait(0.5)
			continue
		var dist := _flat(v.global_position, tgt.global_position)
		if tk.task == &"battle" and dist > 70.0:
			await _drive_to(v, tgt.global_position, 55.0, 20.0)
			continue
		var aimed := await _aim_finger(tgt.global_position + Vector3(0.0, 1.2, 0.0), 0.015)
		await _until(func() -> bool: return v.weapons.can_fire(), 6.0)
		var hp0 := tgt.hp
		var s0 := v.weapons.shots
		if fg.press(2, &"fire"):
			await _until(func() -> bool: return v.weapons.shots > s0, 1.5)
			fg.up(2)
		await _wait(2.5 if tk.task == &"artillery" else 0.6)
		shots += 1
		if not is_instance_valid(tgt) or tgt.dead or tgt.hp < hp0 - 1.0:
			hits += 1
		print("SHOT %d at %s %d m: aimed %s, cam err, hp %.0f -> %s  turret err %.3f  (%s)" % [shots, tgt.kind, roundi(dist), aimed, hp0, str(roundi(tgt.hp)) if is_instance_valid(tgt) else "gone", (tgt.global_position - VehicleCraft.muzzle_origin(v)).normalized().angle_to(v.aim_dir()) if is_instance_valid(tgt) else -1.0, k.hud_line()])
	print("TASK %s: %d shots %d hits in %.0f s, hero hp %.0f tank hp %.0f/%.0f" % [tk.task, shots, hits, _t - t0, p.hp, v.hp, v.max_hp])


func _crash() -> void:
	pass


func _bridge() -> void:
	pass
