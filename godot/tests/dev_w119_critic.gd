extends RefCounted
## w119-critic probe (dev, not in the suite): the real main scene, REAL FINGERS, traffic and live foes ON. Each snake species thrown at foes, a sedan and a tank; then the
## five on-foot circles. Prints PROBE lines, saves frames to CR_OUT.
##   CR_OUT=<dir> QUALITY=1 BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=600 tools/bot.sh res://tests/dev_w119_critic.gd /tmp/x 100000 1
const Audit := preload("res://tests/touch_audit_lib.gd")
const STREET := Vector3(-30.0, 0.0, 4.0)
const YAW := -PI * 0.5
var _started := false
var _done := false
var a: Audit
var p: Player
var sb: SnakeBlasts


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	var tree := Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run(tree)
	return false


func _fwd() -> Vector3:
	return Vector3(-sin(YAW), 0.0, -cos(YAW))


func _street() -> void:
	a.release_all_fingers()
	(Game.enemies as EnemyManager).clear()
	p.snake.cancel()
	p.teleport_to(STREET)
	p.yaw = YAW
	p.camera_rig.reset_view(YAW, 0.05)
	p.velocity = Vector3.ZERO
	await a.pframes(30)


func _pick(id: StringName) -> bool:
	var ab := a.hud_button("ability")
	if ab.is_empty():
		print("PROBE no ability chip")
		return false
	await a.tap(a.centre_of(ab))
	await a.frames(4)
	var d := a.find(a.touch_controls(), "snake_kind")
	if d.is_empty():
		print("PROBE no snake_kind disc; wheel open=", a.tc.wheel.is_open)
		a.tc.wheel.close()
		return false
	await a.tap(d["centre"])
	await a.frames(3)
	var s := a.find(a.touch_controls(), String(id))
	if s.is_empty():
		a.tc.wheel.close()
		return false
	await a.tap(s["centre"])
	await a.frames(3)
	return sb.species == id and not a.tc.wheel.is_open


func _blasts() -> void:
	var vm := Game.vehicles as VehicleManager
	var only := OS.get_environment("CR_ONLY")
	for id: StringName in SnakeBlasts.SPECIES:
		if only != "" and not only.contains(String(id)):
			continue
		await _street()
		vm._reset_all()
		var c := STREET + _fwd() * 14.0
		var foes: Array = []
		for k in 3:
			var f := (Game.enemies as EnemyManager).spawn(&"operative", c + Vector3(0, 0, (k - 1) * 1.8), false)
			if f != null:
				f.max_hp = 3000.0
				f.hp = 3000.0
				foes.append(f)
		var car := vm.spawn_parked(&"sedan", c + Vector3(0, 0, 3.5), 0.0)
		var tank := vm.spawn_parked(&"tank", c + Vector3(3.0, 0, -4.0), 0.0)
		await a.pframes(6)
		p.camera_rig.aim_at(c + Vector3(0, 0.9, 0))
		await a.pframes(3)
		var picked := await _pick(id)
		sb.charges = SnakeBlasts.CHARGES
		var blast := a.hud_button("snake_blast")
		var hp0 := []
		for f in foes:
			hp0.append(float(f.hp) if is_instance_valid(f) else -1.0)
		var car0 := car.hp if car else -1.0
		var tank0 := tank.hp if tank else -1.0
		var ids := a.hud_ids()
		print("PROBE %s picked=%s blast=%s label=%s ids=%s" % [id, picked, not blast.is_empty(), str(blast.get("label", "-")), ids])
		if blast.is_empty():
			continue
		a.finger_down(a.centre_of(blast))
		await a.pframes(14)
		print("PROBE %s ring=%s r=%.1f at=%s c=%s" % [id, sb._ring != null and sb._ring.visible, sb.ring_radius, sb.aim_pt, c])
		await a.shot("blast_%s_aim" % id)
		var b0 := sb.bursts
		a.finger_up()
		await a.until(func() -> bool: return sb.bursts > b0, 120)
		await a.pframes(4)
		await a.shot("blast_%s_burst" % id)
		await a.pframes(30)
		await a.shot("blast_%s_after" % id)
		await a.pframes(60)
		_scan(c)
		await a.shot("blast_%s_late" % id)
		var hp1 := []
		for f in foes:
			hp1.append(float(f.hp) if is_instance_valid(f) else -1.0)
		print("PROBE %s burst=%s foes %s -> %s car %.0f -> %.0f tank %.0f -> %.0f label_after=%s cd=%.2f" % [id, sb.bursts > b0, hp0, hp1, car0,
				car.hp if is_instance_valid(car) else -1.0, tank0, tank.hp if is_instance_valid(tank) else -1.0, str(a.hud_button("snake_blast").get("label", "-")), sb.cd_fraction()])
		await a.shot("blast_%s_cd" % id)


func _foot() -> void:
	await _street()
	(Game.vehicles as VehicleManager)._reset_all()
	await a.pframes(10)
	var ids := a.hud_ids()
	print("PROBE foot ids=", ids)
	for c: Dictionary in a.touch_controls():
		print("PROBE btn %s '%s' at %s" % [c["id"], c.get("label", ""), a.centre_of(c)])
	await a.shot("foot_hud")
	# FIRE
	var pw := p.weapon as PlayerWeapon
	var s0 := pw.shots_fired if "shots_fired" in pw else -1
	var fire := a.hud_button("fire")
	if not fire.is_empty():
		a.finger_down(a.centre_of(fire))
		await a.pframes(20)
		a.finger_up()
	print("PROBE fire shots ", s0, " -> ", pw.shots_fired if "shots_fired" in pw else -1, " ammo=", pw.ammo if "ammo" in pw else -1)
	# JUMP
	var y0 := p.global_position.y
	var maxy := y0
	var jb := a.hud_button("jump")
	if not jb.is_empty():
		a.finger_down(a.centre_of(jb))
		for k in 20:
			await a.pframes(1)
			maxy = maxf(maxy, p.global_position.y)
		a.finger_up()
	print("PROBE jump rise %.2f" % (maxy - y0))
	await a.pframes(40)
	# SWING
	var sw := a.hud_button("snake")
	print("PROBE swing button ", str(sw.get("label", "-")))
	if not sw.is_empty():
		a.finger_down(a.centre_of(sw))
		await a.pframes(30)
		print("PROBE swing mode ", p.snake.mode, " y=%.1f" % p.global_position.y)
		await a.shot("foot_swing")
		a.finger_up()
	await a.pframes(90)
	await _street()
	var zb := a.hud_button("snake_zip")
	print("PROBE zip button ", str(zb.get("label", "-")))
	if not zb.is_empty():
		var p0 := p.global_position
		await a.tap(a.centre_of(zb))
		await a.pframes(40)
		print("PROBE zip moved %.1f mode %s" % [p.global_position.distance_to(p0), p.snake.mode])
	await a.pframes(60)
	await _street()
	var fb := a.hud_button("fly")
	print("PROBE fly chip ", str(fb.get("label", "-")))
	if not fb.is_empty():
		await a.tap(a.centre_of(fb))
		await a.pframes(40)
		print("PROBE fly mode ", p.snake.mode, " y=%.1f ids=%s" % [p.global_position.y, a.hud_ids()])
		await a.shot("foot_fly")
		var lb := a.hud_button("fly")
		for c: Dictionary in a.touch_controls():
			if str(c.get("label", "")) == "LAND":
				lb = c
		if not lb.is_empty():
			await a.tap(a.centre_of(lb))
	await a.pframes(120)
	# ENTER a car
	await _street()
	var vm := Game.vehicles as VehicleManager
	var car := vm.spawn_parked(&"sedan", p.global_position + _fwd() * 3.0, 0.0)
	await a.pframes(20)
	var eb := a.hud_button("interact")
	print("PROBE enter button ", str(eb.get("label", "-")), " blast still=", not a.hud_button("snake_blast").is_empty())
	await a.shot("foot_enter")
	if not eb.is_empty():
		await a.tap(a.centre_of(eb))
		await a.pframes(60)
		print("PROBE entered=", p.vehicle == car, " vehicle=", p.vehicle)
		await a.shot("car_hud")
		var xb := a.hud_button("interact")
		if not xb.is_empty():
			await a.tap(a.centre_of(xb))
		await a.pframes(60)
	print("PROBE after exit vehicle=", p.vehicle)
	# BLAST with a moving car passing by (traffic): does the slot flicker
	await _street()
	vm._reset_all()
	var seen := {}
	for k in 60:
		await a.pframes(3)
		var lbl := ""
		for c: Dictionary in a.touch_controls():
			if c["id"] in ["snake_blast", "interact"]:
				lbl = str(c.get("label", ""))
		seen[lbl] = int(seen.get(lbl, 0)) + 1
	print("PROBE context slot over 180 frames on a live street: ", seen)


func _run(tree: SceneTree) -> void:
	a = Audit.new()
	a.shot_dir = OS.get_environment("CR_OUT")
	DirAccess.make_dir_recursive_absolute(a.shot_dir)
	for q in tree.root.find_children("*", "AutoQuality", true, false):
		(q as AutoQuality).enabled = false
	if not await a.boot(tree.root, "bot", false):
		print("PROBE no HUD")
		_done = true
		return
	(Game.progress as Progress).new_campaign()
	Game.state = &"play"
	await a.frames(30)
	p = Game.player as Player
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	sb = SnakeBlasts.instance
	print("PROBE sb=", sb != null)
	var parts := OS.get_environment("CR_PARTS")
	if parts == "" or parts.contains("blast"):
		await _blasts()
	if parts == "" or parts.contains("foot"):
		await _foot()
	print("PROBE END")
	_done = true


func _scan(c: Vector3) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for n in tree.root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree() or g is MultiMeshInstance3D:
			continue
		var gp := g.global_position
		if gp.y > 3.5 and gp.y < 14.0 and Vector2(gp.x - c.x, gp.z - c.z).length() < 30.0:
			print("PROBE scan ", g.get_path(), " y=%.1f" % gp.y, " ", g.get_class())
