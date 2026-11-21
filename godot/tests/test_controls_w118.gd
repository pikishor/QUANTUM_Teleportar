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
const MAIN: Array[String] = ["fire", "aim", "jump", "snake", "snake_zip", "fly", "interact", "leave_building", "move_forward", "move_back"]
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
		var need := MAIN_PX if MAIN.has(id) else SECOND_PX
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
			if float(bi["r"]) < (TouchControls.R_MAIN if MAIN.has(String(bi["action"])) else TouchControls.R_SMALL):
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
	_table()
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
	for need in ["fire", "aim", "jump", "snake", "snake_zip", "fly", "swap", "reload", "crouch", "ability", "pause", "minimap", "more"]:
		_ck(ids.has(need), "on foot, MORE closed, %s is a button on screen" % need)
	_ck(_label("snake") != "ZIP" and _label("snake_zip") == "ZIP" and _label("fly") == "FLY", "on the street the three snake buttons read SWING / ZIP / FLY (%s / %s / %s)" % [_label("snake"), _label("snake_zip"), _label("fly")])
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
	_ck(await _hold("reload", func() -> bool: return p.reloading or p.weapon.mag == mag0, 30), "RELOAD reloads (reloading %s, magazine %d)" % [p.reloading, p.weapon.mag])
	_ck(await _hold("aim", func() -> bool: return p.aiming, 30), "AIM aims")
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
	_ck(p.is_on_floor() and not _btn("fly").is_empty(), "standing on the ground the FLY button is on screen")
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
	if p.vehicle != v:
		print("NOTE: ENTER did not board the %s (in %s, label %s): boarded by the direct call" % [v.kind, str(p.vehicle.kind) if p.vehicle != null else "nothing", _label("interact")])
		if p.vehicle != null:
			vm.exit_vehicle()
			await a.pframes(6)
		vm.enter(v)
		await a.pframes(10)
	await a.pframes(20)


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
		await _leave(v)


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
