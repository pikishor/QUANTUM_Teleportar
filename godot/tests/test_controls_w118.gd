extends RefCounted
## WAVE 118 (owner, 2026-11-21: "make sure all controls come as options on screen like gta. It should not be cluttered but like 5 circle for driving etc."):
## ONE SMALL SET OF ROUND BUTTONS PER MODE. The real main scene as an 844x390 phone, REAL FINGERS (tests/touch_audit_lib.gd: InputEventScreenTouch / Drag through
## Input.parse_input_event), touch HUD on, reward cards on. Per mode (on foot, snake flight, car, armed car, tank, helicopter, plane, interior):
##   every listed action is a visible round button (MORE stays closed for the whole test) and the finger on it does the thing;
##   a main action is at least 56 px across, a secondary one 44 px; nothing overlaps, leaves the screen, sits on the crosshair or on the hero;
##   the right cluster holds at most 7 circles (6 actions and the door); the door (ENTER / EXIT / LAND / LEAVE) is in ONE place in every mode.
## The wave 116 / 117 findings: FLY on the ground, DOWN in snake flight, SWING and ZIP as two buttons (SWING on the street swings), ability discs of at least 44 px.
## Run: tools/test.sh tests/test_controls_w118.gd      Pictures: tests/bot_controls_w118.gd

const TIMEOUT_SECONDS := 148
const Audit := preload("res://tests/touch_audit_lib.gd")
const STREET := Vector3(-30.0, 0.0, 4.0)             ## a street with facades to both sides (wave 117 spots); yaw -PI/2 looks along it
const WALL_SPOT := Vector3(240.1, 0.0, -305.0)       ## yaw PI/2 looks at a facade 12 m away whose roof is 28 m up
const MAIN_PX := 56.0
const SECOND_PX := 44.0
const MAIN: Array[String] = ["fire", "aim", "jump", "snake", "snake_zip", "interact", "snake_blast", "leave_building", "move_forward", "move_back"]       # wave 119: FLY is an edge chip
## WAVE 119 (owner: "like 5 circle"; w119-hud5): on foot EXACTLY 5 round action buttons in the right cluster: FIRE, JUMP, SWING, ZIP and the context slot (ENTER / USE beside a
## vehicle, door or ride, SNAKE BLAST otherwise). AIM is auto-aim there (AimAssist while FIRE is held; the task's fallback when one SNAKE button cannot do swing and zip cleanly); CROUCH, RELOAD, FLY, ABILITY are edge chips.
const FOOT_CIRCLES := 5
const CHIPS: Array[String] = ["crouch", "reload", "fly", "ability"]
const CONTEXT: Array[String] = ["grab", "takedown", "detonate", "skip_piece"]       ## appear for a moment over a target: not part of a mode's set
const WIDTH := {&"tank": 3.3, &"gunship": 5.2, &"plane": 3.0}
var a: Audit
var p: Player
var sn: SnakeTraversal
var door := Vector2.INF                              ## where the door button was first seen: it must be there in every mode


func _ck(ok: bool, text: String) -> bool:
	TestLib.check(ok, text)
	return ok


func _tp(pos: Vector3, yaw: float) -> void:
	a.release_all_fingers()
	await a.frames(2)
	sn.cancel()
	sn.reset()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, 0.05)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await a.pframes(30)


func _btn(id: String) -> Dictionary:
	return a.hud_button(id)


func _label(id: String) -> String:
	return str(_btn(id).get("label", "-"))


## Holds a finger on button `id` until `cond` or `ticks` physics ticks; false when the button is not on screen.
func _hold(id: String, cond: Callable, ticks := 90) -> bool:
	var c := _btn(id)
	if c.is_empty():
		return false
	a.finger_down(a.centre_of(c))
	await a.frames(2)
	var ok := false
	for i in ticks:
		await a.tree.physics_frame
		if cond.call():
			ok = true
			break
	a.finger_up()
	await a.frames(3)
	return ok


## The layout rules for what is on screen now.
func _layout(mode: String, hero_on_screen: bool) -> void:
	_ck(not a.tc.more_open, "%s: MORE is closed while the set is read" % mode)
	var list := a.touch_controls()
	var bad := a.geometry(mode, list)
	_ck(bad.is_empty(), "%s: no button overlaps another, leaves the screen or answers on less than 44 px (%s)" % [mode, str(bad)])
	var vp := a.vp()
	var small: Array[String] = []
	var cluster: Array[String] = []
	var centre: Array[String] = []
	var hero := Rect2()
	if hero_on_screen:
		var cam := a.root.get_camera_3d()
		var feet := cam.unproject_position(p.global_position)
		var head := cam.unproject_position(p.global_position + Vector3.UP * 1.85)
		var half := absf(feet.y - head.y) * 0.24
		hero = Rect2(Vector2(minf(feet.x, head.x) - half, minf(head.y, feet.y)), Vector2(absf(feet.x - head.x) + 2.0 * half, absf(feet.y - head.y)))
	for c: Dictionary in list:
		var id: String = c["id"]
		if id == "minimap":
			continue
		var d := a.px(float(c["r"]) * 2.0)
		var need := MAIN_PX if MAIN.has(id) and not bool((c.get("b", {}) as Dictionary).get("chip", false)) else SECOND_PX       # wave 119: an edge chip is a secondary target
		if d < need - 0.5:
			small.append("%s '%s' %.0f px (needs %d)" % [id, c["label"], d, int(need)])
		var cc: Vector2 = c["centre"]
		if cc.x > vp.x * 0.5 and cc.y > vp.y * 0.25 and not CONTEXT.has(id):
			cluster.append(id)
		if cc.distance_to(vp * 0.5) < float(c["r"]) + a.vp().y * 0.09:
			centre.append("%s on the crosshair" % id)
		if hero_on_screen and hero.grow(float(c["r"]) * 0.6).has_point(cc):
			centre.append("%s on the hero" % id)
	_ck(small.is_empty(), "%s: a main action is at least 56 px across and a secondary one 44 px (%s)" % [mode, str(small)])
	_ck(cluster.size() <= 7, "%s: the right cluster holds at most 7 circles: %d %s" % [mode, cluster.size(), str(cluster)])
	if mode.begins_with("foot"):
		_ck(cluster.size() == FOOT_CIRCLES, "%s: on foot the right cluster holds exactly %d round action buttons: %d %s" % [mode, FOOT_CIRCLES, cluster.size(), str(cluster)])
	else:
		_ck(cluster.size() <= 6, "%s: the right cluster holds at most 6 circles (wave 119): %d %s" % [mode, cluster.size(), str(cluster)])
	for c: Dictionary in list:
		if CHIPS.has(String(c["id"])) and mode.begins_with("foot"):
			_ck(bool((c.get("b", {}) as Dictionary).get("chip", false)) and (c["centre"] as Vector2).x < vp.x * 0.5, "%s: %s is a small edge chip on the left, not a circle of the cluster" % [mode, c["id"]])
	_ck(centre.is_empty(), "%s: nothing sits on the crosshair or on the hero (%s)" % [mode, str(centre)])
	print("SET %s: %s | right cluster %d" % [mode, str(a.hud_ids()), cluster.size()])


func _door(mode: String, id: String, label: String) -> void:
	var c := _btn(id)
	if not _ck(not c.is_empty() and str(c["label"]).begins_with(label), "%s: the door button says %s (%s)" % [mode, label, _label(id)]):
		return
	if door == Vector2.INF:
		door = c["centre"]
	_ck((c["centre"] as Vector2).distance_to(door) < 2.0, "%s: %s is where the door button is in every mode (%s, first seen at %s)" % [mode, label, str(c["centre"]), str(door)])


## Every pair of rows of the table that can be on screen together (TouchControls.NEED_MODES: MORE open, every contextual button up) on three screens.
func _table() -> void:
	var worst := 1.0e9
	var pair := ""
	var small := ""
	var off := ""
	for vp: Vector2 in [Vector2(844, 390), Vector2(2400, 1080), Vector2(1280, 720)]:
		var s := UiUtil.ui_scale(vp)
		for i in TouchControls.BUTTONS.size():
			var bi: Dictionary = TouchControls.BUTTONS[i]
			var ci := TouchControls.centre_at(bi, vp)
			var ri := float(bi["r"]) * s
			if float(bi["r"]) < (TouchControls.R_MAIN if MAIN.has(String(bi["action"])) and not bi.get("chip", false) else TouchControls.R_SMALL):
				small += " %s" % bi["label"]
			if not Rect2(Vector2.ZERO, vp).grow(-ri + 1.0).has_point(ci):
				off += " %s@%d" % [bi["label"], int(vp.x)]
			if ci.distance_to(TouchControls.pause_at(vp)) - ri - TouchControls.PAUSE_R * s < worst:
				worst = ci.distance_to(TouchControls.pause_at(vp)) - ri - TouchControls.PAUSE_R * s
				pair = "%s / PAUSE at %d" % [bi["label"], int(vp.x)]
			for j in range(i + 1, TouchControls.BUTTONS.size()):
				var bj: Dictionary = TouchControls.BUTTONS[j]
				if TouchControls.exclusive(bi, bj):
					continue
				var gap := (ci.distance_to(TouchControls.centre_at(bj, vp)) - ri - float(bj["r"]) * s) / s
				if gap < worst:
					worst = gap
					pair = "%s / %s at %d" % [bi["label"], bj["label"], int(vp.x)]
	_ck(worst >= 7.5, "the table: no two buttons that can be on screen together touch, MORE open and every contextual button up (closest %s, %.1f px)" % [pair, worst])
	_ck(small == "" and off == "", "the table: every main action has a radius of 52 (56 px on the phone), every other 41 (44 px), all on screen (small:%s off:%s)" % [small, off])


func run(h: Node) -> void:
	FlightHud.flight_fix = OS.get_environment("HUD5_OLD") != "1"         # HUD5_OLD=1: the wave 118 flight layout (the radio plate check fails)
	WorldRoute.route_fix = FlightHud.flight_fix
	AircraftFlight.settle_fix = FlightHud.flight_fix
	_table()
	_gps_walk()
	a = Audit.new()
	a.quiet = true
	var ok := await a.boot(h, "w118")
	TestLib.check(ok, "main.tscn boots as an 844x390 phone with the touch controls")
	if not ok:
		return
	(Game.progress as Progress).new_campaign()
	Game.state = &"play"
	await a.frames(30)
	p = Game.player as Player
	sn = p.snake
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	await _foot()
	await _flight()
	await _car()
	await _armour()
	await _interior()
	await _wheel()
	for c: Array in a.checks:
		TestLib.check(c[0], c[1])
	await a.shutdown()


func _foot() -> void:
	await _tp(STREET, -PI * 0.5)
	var ids := a.hud_ids()
	for need in ["fire", "jump", "snake", "snake_zip", "snake_blast", "fly", "swap", "crouch", "reload", "ability", "pause", "minimap", "more"]:
		_ck(ids.has(need), "on foot, MORE closed, %s is a button or chip on screen (%s)" % [need, str(ids)])
	_ck(_label("snake") != "ZIP" and _label("snake_zip") == "ZIP" and _label("fly") == "FLY" and _label("snake_blast") not in ["-", "", "USE", "ENTER"], "on the street the snake buttons read SWING / ZIP / FLY / BLAST (%s / %s / %s / %s)" % [_label("snake"), _label("snake_zip"), _label("fly"), _label("snake_blast")])
	var bl := _btn("snake_blast")
	if not bl.is_empty():
		_door("foot", "snake_blast", "")                              # the label is the species and its charges (w119-blasts: SnakeBlasts.button_label)
	await _layout("foot", true)
	# FIRE, AIM, JUMP, RELOAD, CROUCH, WEAPON
	for k in 6:                                                      # the first-minute story cards take a tap each (by design): a thumb on open screen closes them
		if Game.story == null or (Game.story.get(&"cards") as Array).is_empty():
			break
		await a.tap(a.vp() * Vector2(0.5, 0.3))
		await a.pframes(6)
	var mag0 := p.weapon.mag
	var sf0 := p.weapon.shots_fired
	_ck(await _hold("fire", func() -> bool: return p.weapon.shots_fired > sf0, 90), "FIRE shoots (magazine %d -> %d)" % [mag0, p.weapon.mag])
	await a.pframes(10)
	_ck(await _hold("reload", func() -> bool: return p.reloading or p.weapon.ammo == p.weapon.mag, 30), "the RELOAD chip reloads (reloading %s, %d of %d)" % [p.reloading, p.weapon.ammo, p.weapon.mag])
	var seenb := [false]
	_ck(await _hold("snake_blast", func() -> bool:
		seenb[0] = seenb[0] or Input.is_action_pressed(&"snake_blast")
		return seenb[0], 20) and not Input.is_action_pressed(&"snake_blast"), "a finger on BLAST (the context slot) presses SNAKE BLAST and lets go")
	_ck(not a.hud_ids().has("aim") and AimAssist.enabled, "on the street there is no AIM button: FIRE aims by itself (AimAssist on)")
	_ck(await _hold("crouch", func() -> bool: return p.cover.crouching, 30), "CROUCH crouches")
	await a.pframes(20)
	var y0 := p.global_position.y
	_ck(await _hold("jump", func() -> bool: return p.global_position.y > y0 + 0.4, 40), "JUMP jumps (%.2f -> %.2f m)" % [y0, p.global_position.y])
	await a.until(func() -> bool: return p.is_on_floor(), 200)
	var w0 := p.weapon.current
	await a.tap_hud("swap", 3)
	await a.pframes(20)
	_ck(p.weapon.current != w0, "a tap on WEAPON takes the next weapon (%s -> %s)" % [w0, p.weapon.current])
	# SWING on the street swings (wave 117 critic: it zipped), ZIP zips, FLY takes off from the ground (wave 116 list: it was not on screen)
	await _tp(STREET, -PI * 0.5)
	var z0 := sn.zips
	var s0 := sn.swings
	var swung := await _hold("snake", func() -> bool: return sn.mode == SnakeTraversal.Mode.SWING, 60)
	_ck(swung and sn.zips == z0 and sn.swings == s0 + 1, "a finger on SWING, standing on the street, starts a SWING and not a zip (swings %d -> %d, zips %d -> %d, mode %d)" % [s0, sn.swings, z0, sn.zips, sn.mode])
	await _tp(WALL_SPOT, PI * 0.5)
	z0 = sn.zips
	_ck(await _hold("snake_zip", func() -> bool: return sn.zips > z0, 30), "a finger on ZIP, a facade under the crosshair, starts a ZIP (zips %d -> %d)" % [z0, sn.zips])
	await a.until(func() -> bool: return sn.mode == SnakeTraversal.Mode.NONE and p.is_on_floor(), 400)
	await _tp(STREET, -PI * 0.5)
	_ck(p.is_on_floor() and not _btn("fly").is_empty(), "standing on the ground the FLY chip is on screen")
	# ENTER: the door button beside a car
	var car := _spawn(&"sedan")
	if _ck(car != null, "a sedan stands by the hero"):
		p.global_position = car.global_position + car.global_transform.basis.x * 2.2 + Vector3(0, 0.3, 0)
		await a.until(func() -> bool: return not _btn("interact").is_empty(), 300)
		_door("foot", "interact", "ENTER")
		await _layout("foot beside a car", false)
		(Game.vehicles as VehicleManager)._release(car)
	await a.pframes(10)


func _flight() -> void:
	await _tp(STREET, -PI * 0.5)
	_ck(await _hold("fly", func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 120), "a finger on FLY, standing on the ground, takes off (mode %d)" % sn.mode)
	if sn.mode != SnakeTraversal.Mode.FLY:
		return
	await a.pframes(50)
	var ids := a.hud_ids()
	_ck(ids.has("jump") and _label("jump") == "UP" and ids.has("crouch") and _label("crouch") == "DOWN" and ids.has("snake") and _label("snake") == "BOOST" and ids.has("fire"),
		"snake flight shows UP, DOWN, BOOST and FIRE (%s)" % str(ids))
	_door("snake flight", "fly", "LAND")
	_ck(not ids.has("snake_zip"), "snake flight has no ZIP button (%s)" % str(ids))
	await _layout("snake flight", true)
	var y0 := p.global_position.y
	_ck(await _hold("jump", func() -> bool: return p.global_position.y > y0 + 2.0, 120), "UP climbs (%.1f -> %.1f m)" % [y0, p.global_position.y])
	var y1 := p.global_position.y
	_ck(await _hold("crouch", func() -> bool: return p.global_position.y < y1 - 2.0, 150), "DOWN descends (%.1f -> %.1f m)" % [y1, p.global_position.y])
	_ck(sn.mode == SnakeTraversal.Mode.FLY, "after UP and DOWN the hero still flies")
	var seen := [false]
	_ck(await _hold("snake", func() -> bool:
		seen[0] = seen[0] or Input.is_action_pressed(&"snake")
		return false, 20) == false and seen[0] and sn.mode == SnakeTraversal.Mode.FLY, "BOOST holds its action and the hero flies on")
	var sf0 := p.weapon.shots_fired
	_ck(await _hold("fire", func() -> bool: return p.weapon.shots_fired > sf0, 90), "FIRE shoots in flight (%d -> %d shots, weapon %s)" % [sf0, p.weapon.shots_fired, p.weapon.current])
	await a.tap_hud("fly", 3)
	_ck(await a.until(func() -> bool: return sn.flight.phase == &"landing" or sn.mode != SnakeTraversal.Mode.FLY, 120), "a tap on LAND starts the landing (phase %s)" % sn.flight.phase)
	sn.cancel()
	await _tp(STREET, -PI * 0.5)


func _spawn(kind: StringName) -> Vehicle:
	var vm := Game.vehicles as VehicleManager
	DemoMenu.spawn_vehicle(kind)
	var best: Vehicle = null
	for v: Vehicle in vm.list:
		if is_instance_valid(v) and v.kind == kind and (best == null or v.global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position)):
			best = v
	return best


## Walks up to `v` and gets in by the ENTER button (three tries, then the direct call with a note).
func _board(v: Vehicle) -> void:
	var vm := Game.vehicles as VehicleManager
	p.global_position = v.global_position + v.global_transform.basis.x * (float(WIDTH.get(v.kind, 2.0)) * 0.5 + 1.2) + Vector3(0, 0.3, 0)
	await a.until(func() -> bool: return not _btn("interact").is_empty(), 200)
	for k in 3:
		if p.vehicle == null and not _btn("interact").is_empty():
			await a.tap_hud("interact", 6)
			await a.until(func() -> bool: return p.vehicle != null, 120)
	if v.kind == &"plane":
		_ck(p.vehicle == v, "w119-hud5: ENTER by finger beside a spawned plane boards the plane (in %s; %s)" % [str(p.vehicle.kind) if p.vehicle != null else "nothing", _reach_note(v)])
	if p.vehicle != v:
		print("NOTE: ENTER did not board the %s (in %s, label %s): boarded by the direct call" % [v.kind, str(p.vehicle.kind) if p.vehicle != null else "nothing", _label("interact")])
		if p.vehicle != null:
			vm.exit_vehicle()
			await a.pframes(6)
		vm.enter(v)
		await a.pframes(10)
	await a.pframes(20)


func _reach_note(v: Vehicle) -> String:
	var out := ""
	for c: Vehicle in (Game.vehicles as VehicleManager).list:
		if is_instance_valid(c) and c.global_position.distance_to(v.global_position) < 14.0:
			out += "%s edge %.1f flat %.1f meta %s; " % [c.kind, c.edge_distance(p.global_position), Vector2(c.global_position.x - p.global_position.x, c.global_position.z - p.global_position.z).length(), str(c.get_meta_list())]
	return out


func _leave(v: Vehicle) -> void:
	var vm := Game.vehicles as VehicleManager
	Game.state = &"play"
	if p.vehicle != null:
		vm.exit_vehicle()
	await a.pframes(10)
	if is_instance_valid(v):
		vm._release(v)
	await a.pframes(4)


func _car() -> void:
	await _tp(STREET, -PI * 0.5)
	var car := _spawn(&"sedan")
	if not _ck(car != null, "a sedan to drive"):
		return
	await _board(car)
	_ck(p.vehicle == car, "the hero sits in the sedan")
	var ids := a.hud_ids()
	for need in ["move_forward", "move_back", "jump", "interact", "horn", "veh_view", "pause", "more"]:
		_ck(ids.has(need), "driving, MORE closed, %s is a button on screen (%s)" % [need, str(ids)])
	_ck(_label("move_forward") == "GAS" and _label("move_back").begins_with("BRAKE"), "the pedals read GAS and BRAKE (%s, %s)" % [_label("move_forward"), _label("move_back")])
	for gone in ["reload", "snake", "snake_zip", "fly", "swap", "aim", "ability", "crouch", "fire"]:
		_ck(not ids.has(gone), "driving an unarmed car there is no %s button" % gone)
	_door("car", "interact", "EXIT")
	await _layout("car", false)
	_ck(await _hold("move_forward", func() -> bool: return car.speed > 3.0, 240), "a finger on GAS alone drives the car forward (%.1f m/s)" % car.speed)
	var v1 := car.speed
	_ck(await _hold("move_back", func() -> bool: return car.speed < -0.5, 420), "a finger on BRAKE stops the car and then reverses (%.1f -> %.1f m/s)" % [v1, car.speed])
	var seen := [false]
	await _hold("jump", func() -> bool:
		seen[0] = seen[0] or Input.is_action_pressed(&"jump")
		return false, 12)
	_ck(seen[0] and not Input.is_action_pressed(&"jump"), "the HAND BRAKE button (%s) holds the handbrake and lets go" % _label("jump"))
	Sfx.last_played = &""
	await a.tap_hud("horn", 4)
	_ck(Sfx.last_played == &"horn", "a tap on HORN sounds the horn (%s)" % Sfx.last_played)
	var c0 := p.camera_rig.veh_view
	await a.tap_hud("veh_view", 4)
	await a.pframes(6)
	_ck(p.camera_rig.veh_view != c0, "a tap on VIEW changes the driving camera")
	await a.until(func() -> bool: return absf(car.speed) < 1.0, 300)
	await a.tap_hud("interact", 6)
	_ck(await a.until(func() -> bool: return p.vehicle == null, 300), "a finger on EXIT leaves the car")
	await _leave(car)
	# an armed car: FIRE joins the set
	var sport := _spawn(&"sport")
	if _ck(sport != null, "an armed sports car to drive"):
		await _board(sport)
		ids = a.hud_ids()
		_ck(ids.has("fire") and ids.has("move_forward") and ids.has("move_back") and ids.has("interact"), "an armed car shows FIRE beside GAS, BRAKE and EXIT (%s)" % str(ids))
		await _layout("armed car", false)
		var vw: Object = sport.get("weapons")
		var n0 := int(vw.get("shots")) if vw != null else 0
		_ck(vw != null and await _hold("fire", func() -> bool: return int(vw.get("shots")) > n0, 60), "FIRE fires the car's gun")
		await _leave(sport)


func _armour() -> void:
	# TANK: the stick drives, a drag on the open screen turns the turret, FIRE and the second gun, the door
	await _tp(STREET, -PI * 0.5)
	var tank := _spawn(&"tank")
	if _ck(tank != null, "a tank to drive"):
		await _board(tank)
		var ids := a.hud_ids()
		_ck(ids.has("fire") and ids.has("interact") and ids.has("veh_view") and not ids.has("snake") and not ids.has("reload"), "a tank shows FIRE, EXIT and VIEW (%s)" % str(ids))
		_door("tank", "interact", "EXIT")
		await _layout("tank", false)
		var vp := a.vp()
		var s := a.tc._scale()
		var stick := Vector2(190.0 * s + a.tc._insets().x, vp.y - 170.0 * s)
		a.finger_down(stick, 1)
		await a.frames(2)
		a.finger_move(stick + Vector2(0.0, -95.0 * s), 1)
		var moved := await a.until(func() -> bool: return tank.speed > 1.0, 300)
		a.finger_up(1)
		_ck(moved, "the stick pushed forward drives the tank (%.1f m/s)" % tank.speed)
		var ty0: float = tank.craft.turret_yaw
		var from := Vector2(vp.x * 0.62, vp.y * 0.16)
		a.finger_down(from, 2)
		await a.frames(2)
		for k in 8:
			a.finger_move(from + Vector2(-22.0 * float(k + 1) * s, 0.0), 2)
			await a.frames(1)
		var turned := await a.until(func() -> bool: return absf(wrapf(tank.craft.turret_yaw - ty0, -PI, PI)) > 0.15, 200)
		a.finger_up(2)
		_ck(turned, "a drag on the open screen turns the turret (%.2f -> %.2f rad)" % [ty0, tank.craft.turret_yaw])
		var vw: Object = tank.get("weapons")
		var n0 := int(vw.get("shots"))
		_ck(await _hold("fire", func() -> bool: return int(vw.get("shots")) > n0, 120), "FIRE fires the tank's main gun")
		if bool(vw.call(&"has_alt")):
			var a0 := int(vw.get("alt_shots"))
			_ck(await _hold("aim", func() -> bool: return int(vw.get("alt_shots")) > a0, 120), "the second gun button (%s) fires" % _label("aim"))
		await _leave(tank)
	# HELICOPTER (the gunship: gun and rockets) and PLANE
	for kind: StringName in [&"gunship", &"plane"]:
		await _tp(STREET, -PI * 0.5)
		var v := _spawn(kind)
		if not _ck(v != null, "a %s to fly" % kind):
			continue
		await _board(v)
		var ids := a.hud_ids()
		_ck(ids.has("jump") and _label("jump") == "UP" and ids.has("crouch") and _label("crouch") == "DOWN" and ids.has("fire") and ids.has("interact"), "%s: UP, DOWN, FIRE and the door are on screen (%s)" % [kind, str(ids)])
		_door(String(kind), "interact", "EXIT")
		await _layout(String(kind), false)
		await _radio_clear(String(kind))
		var vw: Object = v.get("weapons")
		var n0 := int(vw.get("shots"))
		_ck(await _hold("fire", func() -> bool: return int(vw.get("shots")) > n0, 60), "%s: FIRE fires" % kind)
		if kind == &"gunship":
			_ck(ids.has("aim"), "the gunship shows its rocket button (%s)" % str(ids))
			var a0 := int(vw.get("alt_shots"))
			_ck(await _hold("aim", func() -> bool: return int(vw.get("alt_shots")) > a0, 90), "the gunship's %s button fires" % _label("aim"))
			var y0 := v.global_position.y
			_ck(await _hold("jump", func() -> bool: return v.global_position.y > y0 + 1.5, 400), "UP lifts the helicopter (%.1f -> %.1f m)" % [y0, v.global_position.y])
			var y1 := v.global_position.y
			_ck(await _hold("crouch", func() -> bool: return v.global_position.y < y1 - 0.8, 400), "DOWN brings it down (%.1f -> %.1f m)" % [y1, v.global_position.y])
		if kind == &"plane":
			await _plane_flight(v)
		await _leave(v)


## w119-hud5 (wave 118 open item: the ORACLE card was cut off and stood on the altimeter at 2400x1080 in the helicopter and the plane): a long radio line in flight keeps
## clear of the flight instruments, at the phone's own size and at 2400x1080, and its plate holds every line it shows.
func _radio_clear(mode: String) -> void:
	var st: Object = Game.story
	if not _ck(st != null and st.get(&"view") != null, "%s: the story layer is up" % mode):
		return
	st.set(&"enabled", true)
	st.call(&"say", "ORACLE", "Command chitin, one body, a lot of rank. They will not wait for you to land, so keep your eyes on the towers and your hands on the stick.", "w119", 0.0, 2)
	var ch0 := UiSettings.s_chatter
	UiSettings.s_chatter = 2                                        # FULL story chatter: the longest plate there is
	if not (st.get(&"current") as Dictionary).is_empty() and str((st.get(&"current") as Dictionary).get("id", "")) != "w119":
		st.call(&"skip_line")
	await a.until(func() -> bool: return str((st.get(&"current") as Dictionary).get("id", "")) == "w119", 400)
	await a.pframes(30)
	var view: Object = st.get(&"view")
	for vp: Vector2 in [a.vp(), Vector2(2400, 1080)]:
		var sub: Rect2 = view.call(&"subtitle_rect", vp)
		var ins := FlightHud.instruments_rect(vp, UiUtil.ui_scale(vp), UiUtil.insets(vp))
		_ck(sub.has_area() and not sub.grow(10.0 * UiUtil.ui_scale(vp)).intersects(ins), "%s at %dx%d: the radio plate %s keeps clear of the flight instruments %s by 10 base px (the plate backing is 5)" % [mode, int(vp.x), int(vp.y), str(sub), str(ins)])
		_ck(ins.end.y < vp.y * 0.72, "%s at %dx%d: the instruments stay above the speed plate (%.0f)" % [mode, int(vp.x), int(vp.y), ins.end.y])
	st.call(&"skip_line")
	UiSettings.s_chatter = ch0


## w119-hud5 (wave 118 open item: the GPS walk from the spawn to the ARMY YARD stopped 25 to 53 m short): the walk route was cached by 24 m cells WITH its start
## point, so a walker 20 m on was sent back to where he had been; and on foot beside the goal the route went back to the road first (the finger bot paced between them).
func _gps_walk() -> void:
	WorldRoute.clear_cache()
	var yard := ArmourSites.YARD
	var r1 := WorldRoute.route(Vector3(-131.0, 0.0, -96.0), yard, &"walk")
	var here := Vector3(-128.0, 0.0, -88.0)                        # the same 24 m cell, 8.5 m on
	var r2 := WorldRoute.route(here, yard, &"walk")
	_ck(r1.size() >= 2 and r2.size() >= 2 and r2[0].distance_to(here) < 0.5, "a GPS walk route starts where the hero IS, not at the cached start (%s, hero at %s)" % [str(r2[0]) if r2.size() > 0 else "-", str(here)])
	var near := Vector3(-131.0, 0.0, -74.0)
	var r3 := WorldRoute.route(near, yard, &"walk")
	var back := false
	for i in range(1, r3.size()):
		back = back or r3[i].distance_to(yard) > near.distance_to(yard) + 1.0
	_ck(not back, "on foot 19 m from the yard the route never leads away from it (%s)" % str(r3))


## w119-hud5 (wave 118 open item: planes were not finger-tested for take-off and landing): the stick pushed forward opens the throttle down the street, UP lifts the
## plane off, DOWN with the stick pulled back brings it onto the ground again, EXIT (LAND FIRST in the air) gets the hero out.
func _plane_flight(v: Vehicle) -> void:
	var vp := a.vp()
	var s := a.tc._scale()
	var stick := Vector2(190.0 * s + a.tc._insets().x, vp.y - 170.0 * s)
	a.finger_down(stick, 1)
	await a.frames(2)
	a.finger_move(stick + Vector2(0.0, -95.0 * s), 1)
	var fast := await a.until(func() -> bool: return v.speed > 20.0, 900)
	_ck(fast, "plane: the stick forward runs it up the street (%.1f m/s, throttle %.2f)" % [v.speed, float(AircraftFlight.info(v)["throttle"])])
	var c := _btn("jump")
	a.finger_down(a.centre_of(c), 2)
	var up := await a.until(func() -> bool: return float(AircraftFlight.info(v)["agl"]) > 6.0, 900)
	a.finger_up(2)
	_ck(up, "plane: UP lifts it off the street (%.1f m above the ground, %.1f m/s)" % [float(AircraftFlight.info(v)["agl"]), v.speed])
	await a.pframes(60)
	_ck(_label("interact") == "LAND FIRST", "plane: in the air the door button says LAND FIRST (%s)" % _label("interact"))
	a.finger_move(stick + Vector2(0.0, 95.0 * s), 1)                # throttle back
	var d := _btn("crouch")
	a.finger_down(a.centre_of(d), 2)
	var down := await a.until(func() -> bool: return float(AircraftFlight.info(v)["agl"]) < 1.0, 1500)
	a.finger_up(2)
	_ck(down, "plane: DOWN with the stick back puts it on the ground (%.1f m, %.1f m/s)" % [float(AircraftFlight.info(v)["agl"]), v.speed])
	var stopped := await a.until(func() -> bool: return absf(v.speed) < 2.0, 900)
	_ck(stopped, "plane: on the ground the stick held back brakes it to a stop (%.1f m/s, lever %.2f, airborne %s, agl %.1f, stick %s)" % [v.speed, v.craft.lever, str(v.craft.airborne), float(AircraftFlight.info(v)["agl"]), str(Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back"))])
	a.finger_up(1)
	await a.tap_hud("interact", 6)
	_ck(await a.until(func() -> bool: return p.vehicle == null, 300), "plane: after the landing EXIT gets the hero out (%.1f m/s, label %s)" % [v.speed, _label("interact")])


func _interior() -> void:
	Game.state = &"play"
	InteriorTestActions.enter(&"shop")
	if not _ck(await a.until(func() -> bool: return InteriorGameplay.active, 300), "the hero is inside a shop"):
		return
	await a.pframes(40)
	var ids := a.hud_ids()
	_ck(ids.has("fire") and ids.has("aim") and ids.has("jump") and ids.has("swap") and not ids.has("snake") and not ids.has("snake_zip") and not ids.has("fly"), "indoors: FIRE, AIM, JUMP, WEAPON and no snake buttons (%s)" % str(ids))
	var lid := "leave_building" if ids.has("leave_building") else "interact"       # at the door itself the USE button stands in the same slot and says LEAVE
	_door("interior", lid, "LEAVE")
	await _layout("interior", false)
	await a.tap_hud(lid, 4)
	var out := await a.until(func() -> bool: return not InteriorGameplay.active, 200)
	if not out and not _btn(lid).is_empty():
		await a.tap_hud(lid, 4)
		out = await a.until(func() -> bool: return not InteriorGameplay.active, 200)
	_ck(out, "a finger on LEAVE takes the hero out of the building")
	if InteriorGameplay.active:
		InteriorTestActions.leave()
	await a.pframes(10)


## The ABILITY wheel (wave 116 list: eleven discs of 38 px).
func _wheel() -> void:
	Game.state = &"play"
	await _tp(STREET, -PI * 0.5)
	a.fast_tap(a.centre_of(_btn("ability")))
	await a.frames(4)
	if not _ck(a.tc.wheel.is_open, "a tap on ABILITY opens the wheel"):
		return
	var least := 1.0e9
	var list := a.touch_controls()
	for c: Dictionary in list:
		least = minf(least, a.px(float(c["r"]) * 2.0))
	var bad := a.geometry("ability wheel", list)
	_ck(least >= SECOND_PX - 0.5 and bad.is_empty(), "the %d ability discs are at least 44 px across and none overlaps or leaves the screen (least %.0f px, %s)" % [list.size(), least, str(bad)])
	var cd := a.find(list, "blink")
	if not cd.is_empty():
		var seen := [false]
		var watch := func() -> void:
			seen[0] = seen[0] or Input.is_action_pressed(&"blink")
		a.tree.physics_frame.connect(watch)
		await a.tap(cd["centre"])
		await a.pframes(12)
		a.tree.physics_frame.disconnect(watch)
		_ck(seen[0] and not a.tc.wheel.is_open, "a tap on a disc casts the ability and closes the wheel")
	a.tc.wheel.close()
