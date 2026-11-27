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
			"duel": await _duel()
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
				print("DRIVE stuck at %s (%d m to goal) speed %.1f: %s | hp %.0f dead %s wreck %s trk %s/%s spdf %.2f active %s hero_in %s thr? stick %s" % [v.global_position, roundi(_flat(v.global_position, goal)), v.speed, _blocker(v), v.hp, v.dead, v.wreck, v.get_meta(&"trk_l", "-"), v.get_meta(&"trk_r", "-"), TankArmour.speed_factor(v, 0.0), v.active, p.vehicle == v, fg.held.get(0, "up")])
				fg.stick(Vector2(clampf(e, -1.0, 1.0), 1.0))
				await _wait(2.0)
			last_pos = v.global_position
			last_t = _t
	fg.stick(Vector2.ZERO)
	if stuck > 0 or _flat(v.global_position, goal) > rad + 5.0:
		print("DRIVE to %s: %d m left after %.0f s, %d stucks" % [goal, roundi(_flat(v.global_position, goal)), _t - t0, stuck])
	return _flat(v.global_position, goal)


## Follows the GPS route (WorldRoute, as the map draws it) to `goal` with the stick.
func _drive_route(v: Vehicle, goal: Vector3, rad: float, secs: float) -> float:
	var out0 := v.global_position + v.forward() * 22.0
	await _drive_to(v, out0, 4.0, 8.0)                         # out of the bay, nose first (the yard faces its road)
	var poly := WorldRoute.route(v.global_position, goal, &"car")
	print("ROUTE %d points, %d m" % [poly.size(), roundi(WorldRoute.length(poly))])
	var t0 := _t
	var i := 1
	while i < poly.size() and _t - t0 < secs and p.vehicle == v:
		var wp := poly[i]
		if i == poly.size() - 1:
			break
		var left := secs - (_t - t0)
		await _drive_to(v, wp, 10.0, minf(left, 60.0))
		if _flat(v.global_position, wp) > 14.0:
			print("ROUTE: waypoint %d of %d not reached (%d m off) at %s" % [i, poly.size(), roundi(_flat(v.global_position, wp)), v.global_position])
		i += 1
	return await _drive_to(v, goal, rad, maxf(secs - (_t - t0), 5.0))


func _blocker(v: Vehicle) -> String:
	var sp3 := host.get_tree().root.get_world_3d().direct_space_state
	var out := ""
	for side in [-0.4, 0.0, 0.4]:
		var o: Vector3 = v.global_position + Vector3(0.0, 1.0, 0.0) + v.right() * float(v.spec["wid"]) * float(side)
		var q := PhysicsRayQueryParameters3D.create(o, o + v.forward() * (float(v.spec["len"]) * 0.5 + 2.5), Game.L_WORLD | Game.L_VEHICLE | Game.L_ENEMY)
		q.exclude = [v.get_rid()]
		var r := sp3.intersect_ray(q)
		if not r.is_empty():
			var c := r["collider"] as Node
			var fam := ""
			if c != null and String(c.name).begins_with("PropCollider"):
				for cn2 in host.get_tree().root.find_children("*", "", true, false):
					if cn2.has_method(&"prop_colliders"):
						fam = (cn2.call(&"prop_colliders")).family_of(int(String(c.name).substr(12)))
						break
			out += " %s%s(%.1f m)" % [str(c.get_path()).replace("/root/Runner/Main/", "") if c != null else "?", "[" + fam + "]" if fam != "" else "", (r["position"] - o).length()]
	var kc := v.move_and_collide(v.forward() * 0.4, true)
	if kc != null:
		var cn := kc.get_collider() as Node
		out += " | test-move hits %s (%s) at local y %.2f normal %s" % [str(cn.get_path()).replace("/root/Runner/Main/", "") if cn != null else "?", (cn.get_parent().name if cn != null and cn.get_parent() != null else ""), kc.get_position().y - v.global_position.y, kc.get_normal().snapped(Vector3.ONE * 0.01)]
	return out if out != "" else "nothing ahead"


func _camp() -> CampaignRunner:
	return board._campaign()


func _fight() -> void:
	hud = host.get_tree().root.find_children("*", "Hud", true, false)[0] as Hud
	board = MissionBoardScreen.board()
	board.take_over = false
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
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
		await _until(func() -> bool: return k.state == &"active" or not board.is_running(), 8.0)
		if not board.is_running():
			break
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
			await _drive_route(v, k.pos, float(st.get("radius", 14.0)) * 0.7, 400.0)
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


## A parked vehicle of `kind` at `at` facing `h`, the hero boards it by finger from behind.
func _ride(kind: StringName, at: Vector3, h: float) -> Vehicle:
	vm._fixed_n += 1
	var v := vm.spawn_parked(kind, at, h)
	vm._count_fixed()
	if v == null:
		return null
	v.set_meta(&"hold", true)
	v.global_position = at
	await _f(4)
	await _place_hero(at - v.forward() * (float(v.spec["len"]) * 0.5 + 4.0), at)
	if not await _walk_board(v):
		await _place_hero(at + v.right() * (float(v.spec["wid"]) * 0.5 + 4.0), at)
	if p.vehicle != v and not await _walk_board(v):
		print("RIDE %s: could not board" % kind)
		return null
	return v


func _drop(v: Vehicle) -> void:
	if p.vehicle != null:
		await _tap(&"interact")
		await _f(10)
	if is_instance_valid(v):
		v.remove_meta(&"hold")
		if v.active:
			vm._release(v)
	vm._count_fixed()


func _bridge() -> void:
	Bridges.ensure()
	var n := 0
	var kinds := [&"t_heavy", &"t_apc8", &"t_walker", &"t_hover", &"t_jeep"]
	if OS.get_environment("BKINDS") != "":
		kinds.clear()
		for x in OS.get_environment("BKINDS").split(","):
			kinds.append(StringName(x))
	for b: Dictionary in Bridges.list:
		if b["kind"] == &"rail" or b["kind"] == &"foot":
			continue
		if n >= int(OS.get_environment("NBRIDGE") if OS.get_environment("NBRIDGE") != "" else "5"):
			break
		var k: StringName = kinds[n % kinds.size()]
		n += 1
		var L := float(b["len"])
		var a0: Array = Bridges.point_at(b, 0.0)
		var dir: Vector3 = a0[1]
		var start: Vector3 = (a0[0] as Vector3) - dir * 25.0
		start.y = TerrainHeight.height_at(start.x, start.z)
		var v := await _ride(k, start, atan2(-dir.x, -dir.z))
		if v == null:
			continue
		var minoff := 99.0
		var maxoff := -99.0
		var fell := false
		var u_best := -25.0
		var t0 := _t
		while _t - t0 < L / 6.0 + 20.0:
			var proj := (v.global_position - (a0[0] as Vector3)).dot(dir)
			var e: Array = Bridges.point_at(b, clampf(proj, 0.0, L))
			var want: Vector3 = (e[0] as Vector3) + (e[1] as Vector3) * 12.0
			var d := want - v.global_position
			var err := wrapf(atan2(-d.x, -d.z) - v.heading, -PI, PI)
			fg.stick(Vector2(clampf(-err * 2.0, -1.0, 1.0), -1.0))
			await _step()
			u_best = maxf(u_best, proj)
			if proj > 2.0 and proj < L - 2.0:
				var dy := Bridges.deck_y(v.global_position.x, v.global_position.z, v.global_position.y)
				if dy == Bridges.NONE:
					fell = true
				else:
					minoff = minf(minoff, v.global_position.y - dy)
					maxoff = maxf(maxoff, v.global_position.y - dy)
			if proj > L + 10.0 or v.sunk:
				break
			if OS.get_environment("BTRACE") != "" and Engine.get_physics_frames() % 60 == 0:
				var lat2 := (v.global_position - (e[0] as Vector3)).cross(e[1] as Vector3).y
				var kc := v.move_and_collide(v.forward() * 0.3, true)
				var kcs := "free"
				if kc != null:
					var shp := kc.get_collider_shape() as CollisionShape3D
					kcs = "%s shape %s at %s normal %s (local hit y %.2f)" % [(kc.get_collider() as Node).name, shp.name if shp != null else "?", kc.get_position(), kc.get_normal(), kc.get_position().y - v.global_position.y]
				print("  trace u %.1f lat %.2f y %.2f deck %.2f speed %.1f w %.1f test-move: %s" % [proj, lat2, v.global_position.y, (e[0] as Vector3).y, v.speed, float(b["w"]), kcs])
		fg.stick(Vector2.ZERO)
		print("BRIDGE %s (%s, %d m) with %s: reached %d m of %d, off the deck %s, height over deck %.2f..%.2f, sunk %s, hp %.0f" % [b.get("id"), b["kind"], roundi(L), k, roundi(u_best), roundi(L), fell, minoff, maxoff, v.sunk, v.hp])
		await _drop(v)


## Drive a tank flat out into a building wall and into a traffic car.
func _crash() -> void:
	# a wall: from the start, the nearest building face found by rays
	var sp3 := host.get_tree().root.get_world_3d().direct_space_state
	var at := p.global_position + Vector3(0.0, -p.global_position.y, 0.0)
	var best_dir := Vector3.ZERO
	var best_d := 0.0
	for k in 16:
		var a := TAU * float(k) / 16.0
		var dir := Vector3(-sin(a), 0.0, -cos(a))
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 1.5, 0.0), at + Vector3(0.0, 1.5, 0.0) + dir * 120.0, Game.L_WORLD)
		var r := sp3.intersect_ray(q)
		if not r.is_empty():
			var d: float = ((r["position"] as Vector3) - at).length()
			if d > best_d and d > 50.0 and str((r["collider"] as Node).get_path()).contains("World/Collision"):
				best_d = d
				best_dir = dir
	if best_dir == Vector3.ZERO:
		print("CRASH: no wall found")
		return
	for k: StringName in [&"t_heavy", &"t_scout"]:
		var v := await _ride(k, at, atan2(-best_dir.x, -best_dir.z))
		if v == null:
			continue
		var hp0 := v.hp
		fg.stick(Vector2(0.0, -1.0))
		var vmax := 0.0
		var t0 := _t
		var deepest := 0.0
		while _t - t0 < 14.0:
			await _step()
			vmax = maxf(vmax, v.speed)
			var travelled := (v.global_position - at).dot(best_dir)
			deepest = maxf(deepest, travelled + float(v.spec["len"]) * 0.5 - best_d)
		fg.stick(Vector2.ZERO)
		print("CRASH wall %s: top speed %.1f, nose past the wall face %.2f m, hull %d -> %d, still in %s" % [k, vmax, deepest, roundi(hp0), roundi(v.hp), p.vehicle == v])
		await _drop(v)
	# traffic: a sedan parked across the tank's path 30 m ahead
	var tv := await _ride(&"t_heavy", at, atan2(-best_dir.x, -best_dir.z))
	if tv != null:
		vm._fixed_n += 1
		var car := vm.spawn_parked(&"sedan", at + best_dir * 22.0, atan2(-best_dir.x, -best_dir.z) + PI * 0.5)
		vm._count_fixed()
		var c0 := car.global_position
		var hp0 := car.hp
		fg.stick(Vector2(0.0, -1.0))
		await _wait(6.0)
		fg.stick(Vector2.ZERO)
		print("CRASH car: sedan moved %.1f m, hp %d -> %d dead %s; tank went %.1f m (hull %d)" % [_flat(car.global_position, c0), roundi(hp0), roundi(car.hp), car.dead, (tv.global_position - at).dot(best_dir), roundi(tv.hp)])
		await _drop(tv)


## A duel on the open airfield east strip: the hero in a heavy tank, an enemy crew tank 70 m ahead; the right thumb aims (look swipes), a finger on FIRE shoots.
func _duel() -> void:
	var at := Airport.to_world(TankRoster.BASE_LOCAL + Vector3(60.0, 0.0, -60.0))
	at.y = TerrainHeight.height_at(at.x, at.z)
	var h := Airport.heading_world(PI * 0.5)
	var fwd := Vector3(-sin(h), 0.0, -cos(h))
	var mine := await _ride(OS.get_environment("DUEL_KIND") if OS.get_environment("DUEL_KIND") != "" else &"t_heavy", at, h)
	if mine == null:
		return
	var ep := at + fwd * 70.0
	ep.y = TerrainHeight.height_at(ep.x, ep.z)
	var tc := TankCrews.current
	var e: Vehicle = tc.spawn(&"tank", ep, h + PI, &"mission", {"hp": 650.0}) if tc != null else null
	if e == null:
		print("DUEL: no enemy tank")
		return
	var hp_me := mine.hp
	var t0 := _t
	var shots := 0
	var hits := 0
	var misses_far := 0
	while is_instance_valid(e) and not e.dead and e.active and _t - t0 < 90.0:
		var aimed := await _aim_finger(e.global_position + Vector3(0.0, 1.3, 0.0), 0.012)
		await _until(func() -> bool: return mine.weapons.can_fire(), 6.0)
		var hp0 := e.hp
		var s0 := mine.weapons.shots
		if fg.press(2, &"fire"):
			await _until(func() -> bool: return mine.weapons.shots > s0, 1.5)
			fg.up(2)
		await _wait(1.0)
		shots += 1
		var hit := not is_instance_valid(e) or e.dead or e.hp < hp0 - 1.0
		if hit:
			hits += 1
		print("DUEL shot %d: aimed %s hit %s enemy hp %s  zone %s  my hull %.0f  enemy %d m" % [shots, aimed, hit, str(roundi(e.hp)) if is_instance_valid(e) else "gone", TankArmour.last_zone, mine.hp, roundi(_flat(e.global_position, mine.global_position)) if is_instance_valid(e) else -1])
	print("DUEL done: %d shots, %d hits, enemy down %s in %.0f s, my hull %.0f -> %.0f" % [shots, hits, not is_instance_valid(e) or e.dead, _t - t0, hp_me, mine.hp])
	await _drop(mine)
