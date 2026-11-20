extends RefCounted
## THE TOUCH AUDIT, part 1 of 3: THE PLAY HUD (wave 116, owner round 7: "small silly errors. Are you even checking."). The real main scene as a phone (844x390, touch forced,
## reward cards and hints on), every control pressed by a REAL finger (InputEventScreenTouch / InputEventScreenDrag through Input.parse_input_event, window coordinates; never
## a mouse, never a direct call: tests/touch_audit_lib.gd). On foot, MORE, a car, a helicopter, a plane, a gunship, a tank, snake flight and an interior:
##   every button's action goes down under the finger and up when it lifts; a QUICK tap (down and up in one frame, what a thumb does at 20 FPS) still reaches the game;
##   FLY / LAND, MORE, the car door, RADIO, VIEW, the vehicle guns, LEAVE, pause and the minimap do what their label says; the weapon wheel (both levels) and the ability
##   wheel open, pick and close; the phone's BACK key pauses instead of closing the game.
## Each fix of this wave is shown failing first with its old behaviour (TouchControls.hold_fast_taps = false, BackKey.enabled = false).
## Parts 2 and 3: tests/test_touch_audit_menus.gd, tests/test_touch_audit_screens.gd. Bot with frames: tests/bot_touch_audit.gd.
## Run: tools/test.sh tests/test_touch_audit.gd

const TIMEOUT_SECONDS := 140
const Audit := preload("res://tests/touch_audit_lib.gd")
var a: Audit
var p: Player


## A quick tap on a HUD button: true when at least one physics tick saw its action down, and the action was let go again afterwards.
func _fast_tap_seen(id: String) -> bool:
	var c := a.hud_button(id)
	if c.is_empty():
		return false
	var action: StringName = (c["b"] as Dictionary)["action"]
	var box := [false]
	var watch := func() -> void:
		if Input.is_action_pressed(action):
			box[0] = true
	a.tree.physics_frame.connect(watch)
	a.fast_tap(a.centre_of(c))
	await a.frames(3)
	await a.pframes(3)
	var let_go := await a.until(func() -> bool: return not Input.is_action_pressed(action), 120)
	a.tree.physics_frame.disconnect(watch)
	return box[0] and let_go


## A quick tap on ABILITY (down and up in one frame: a tap held longer than 0.25 s is a hold, and two frames of a loaded machine are longer than that).
func _tap_ability() -> void:
	var c := a.hud_button("ability")
	if c.is_empty():
		return
	a.fast_tap(a.centre_of(c))
	await a.frames(3)


func run(h: Node) -> void:
	a = Audit.new()
	a.quiet = true
	if not await _boot(h):
		return
	await _foot()
	await _wheels()
	await _pause_map_back()
	await _car()
	await _aircraft()
	await _snake_flight()
	await _interior()
	for c: Array in a.checks:
		TestLib.check(c[0], c[1])
	for f in a.findings:
		print("FINDING: ", f)
	print("TOUCH AUDIT HUD: ", a.summary())
	print(a.table())
	await a.shutdown()


func _boot(h: Node) -> bool:
	var ok := await a.boot(h, "hud")
	TestLib.check(ok, "main.tscn boots as a phone: touch controls, HUD, player, progress")
	if not ok:
		return false
	(Game.progress as Progress).new_campaign()
	Game.state = &"play"
	await a.frames(30)
	p = Game.player as Player
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestLib.check(a.root.get_node_or_null("BackKey") != null and a.root.get_node_or_null("TouchButtons") != null, "the BACK key node and the touch-button node are in the tree")
	return true


func _foot() -> void:
	var ids := a.hud_ids()
	for need in ["fire", "aim", "jump", "reload", "snake", "ability", "swap", "more", "pause", "minimap"]:
		TestLib.check(ids.has(need), "on foot the HUD shows %s" % need)
	var pressed := await a.press_hud_frame("foot")
	TestLib.check(pressed.size() >= 5, "on foot: %d action buttons held by the finger (%s)" % [pressed.size(), str(pressed)])
	# FIRE shoots, JUMP lifts the hero
	var mag0 := p.weapon.mag
	var c := a.hud_button("fire")
	a.finger_down(a.centre_of(c))
	await a.pframes(20)
	a.finger_up()
	TestLib.check(p.weapon.mag < mag0 or p.reloading, "a finger held on FIRE shoots (magazine %d -> %d)" % [mag0, p.weapon.mag])
	await a.pframes(30)
	# --- the quick tap: old behaviour first
	TouchControls.hold_fast_taps = false
	var old_seen := 0
	for id in ["fire", "jump", "snake"]:
		if await _fast_tap_seen(id):
			old_seen += 1
		await a.pframes(20)
	print("OLD BEHAVIOUR (hold_fast_taps off): %d of 3 quick taps reached the game" % old_seen)
	TestLib.check(old_seen == 0, "old behaviour: a tap that is down and up inside one frame never reaches the game (%d of 3 seen)" % old_seen)
	TouchControls.hold_fast_taps = true
	for id in ["fire", "aim", "jump", "reload", "snake"]:
		TestLib.check(await _fast_tap_seen(id), "a quick tap (down and up in one frame) on %s reaches the game and lets go again" % id)
		await a.pframes(20)
	# MORE
	TestLib.check(await a.tap_hud("more") and a.tc.more_open, "a finger on MORE opens the second cluster")
	var more_ids := a.hud_ids()
	for need in ["altfire", "melee", "throw_item", "crouch"]:
		TestLib.check(more_ids.has(need), "MORE shows %s" % need)
	var mp := await a.press_hud_frame("foot+more")
	TestLib.check(mp.size() >= 9, "MORE open: %d action buttons held by the finger" % mp.size())
	if a.hud_ids().has("garage_call"):
		var n0 := (Game.vehicles as VehicleManager).list.size()
		Sfx.last_played = &""
		await a.tap_hud("garage_call")
		await a.pframes(10)
		TestLib.check(Sfx.last_played != &"" or (Game.vehicles as VehicleManager).list.size() != n0, "a finger on CALL CAR answers (sound %s)" % Sfx.last_played)
	TestLib.check(await a.tap_hud("more") and not a.tc.more_open, "a second tap on MORE closes the cluster")


func _wheels() -> void:
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	await a.pframes(4)
	# WEAPON: a tap cycles
	var w0 := p.weapon.current
	await a.tap_hud("swap", 4)
	await a.pframes(12)
	TestLib.check(p.weapon.current != w0, "a tap on WEAPON takes the next weapon (%s -> %s)" % [w0, p.weapon.current])
	# WEAPON: a hold opens the class wheel (level 1), a drag to a class and a lift opens its ring (level 2), a tap on a disc takes that weapon
	var c := a.hud_button("swap")
	a.finger_down(a.centre_of(c))
	var opened := await a.until(func() -> bool: return a.tc.wheel.is_open and a.tc.wheel.kind == &"weapon", 240)
	TestLib.check(opened, "a finger held on WEAPON opens the weapon wheel")
	if opened:
		var discs := a.touch_controls()
		for g in a.geometry("wheel_weapon", discs):
			a.finding(g)
		await a.shot("wheel_weapon")
		TestLib.check(discs.size() >= 6, "the weapon wheel shows its classes (%d discs)" % discs.size())
		var target: Dictionary = discs[1]
		a.finger_move(a.centre_of(target))
		await a.frames(3)
		a.finger_up()
		await a.frames(4)
		TestLib.check(a.tc.wheel.is_open and a.tc.wheel.sticky, "lifting the finger on a class opens that class's ring (%s)" % target["label"])
		var ring := a.touch_controls()
		for g in a.geometry("wheel_ring", ring):
			a.finding(g)
		await a.shot("wheel_ring")
		var before := p.weapon.current
		var picked := false
		for d: Dictionary in ring:
			if WeaponDefs.DEFS.has(StringName(d["id"])) and StringName(d["id"]) != before:
				await a.tap(a.centre_of(d), 0, 3)
				await a.pframes(10)
				TestLib.check(p.weapon.current == StringName(d["id"]) and not a.tc.wheel.is_open, "a tap on a disc of the ring takes that weapon and closes the wheel (%s, now %s)" % [d["id"], p.weapon.current])
				a.row("wheel_ring", d, "state" if p.weapon.current == StringName(d["id"]) else "dead")
				picked = true
				break
		TestLib.check(picked, "the ring holds a weapon to pick (%d discs)" % ring.size())
	a.finger_up()
	a.tc.release_all()
	await a.pframes(6)
	# the weapon wheel again: a tap beside the discs closes it
	a.finger_down(a.centre_of(a.hud_button("swap")))
	await a.until(func() -> bool: return a.tc.wheel.is_open, 240)
	a.finger_move(a.centre_of(a.touch_controls()[0]))
	await a.frames(2)
	a.finger_up()
	await a.frames(4)
	if a.tc.wheel.is_open:
		await a.tap(Vector2(a.vp().x * 0.3, a.vp().y * 0.5), 0, 3)
	TestLib.check(not a.tc.wheel.is_open, "a tap beside the discs closes the weapon wheel")
	await a.pframes(6)
	# ABILITY: a tap leaves the wheel open, a tap on a disc casts, a tap beside closes
	await _tap_ability()
	TestLib.check(a.tc.wheel.is_open and a.tc.wheel.kind == &"ability" and a.tc.wheel.sticky, "a tap on ABILITY opens the ability wheel and it stays")
	if a.tc.wheel.is_open:
		var discs := a.touch_controls()
		for g in a.geometry("wheel_ability", discs):
			a.finding(g)
		await a.shot("wheel_ability")
		TestLib.check(discs.size() >= 7, "the ability wheel shows the verbs (%d discs)" % discs.size())
		var first: Dictionary = discs[0]
		a.finger_down(a.centre_of(first))
		await a.tree.physics_frame
		var cast := Input.is_action_pressed(StringName(first["id"]))
		a.finger_up()
		await a.pframes(14)
		TestLib.check(cast and not a.tc.wheel.is_open and not Input.is_action_pressed(StringName(first["id"])), "a tap on %s casts it (the action goes down, the wheel closes, the action lets go)" % first["label"])
		a.row("wheel_ability", first, "state" if cast else "dead")
		await _tap_ability()
		if a.tc.wheel.is_open:
			await a.tap(Vector2(a.vp().x * 0.3, a.vp().y * 0.45), 0, 3)
		TestLib.check(not a.tc.wheel.is_open, "a tap beside the discs closes the ability wheel")
	a.tc.release_all()
	await a.pframes(10)


func _pause_map_back() -> void:
	Game.state = &"play"
	await a.pframes(4)
	TestLib.check(await a.tap_hud("pause") and Game.state == &"paused", "a finger on PAUSE pauses (state %s)" % Game.state)
	var res := a.find(a.controls(), "resume")
	TestLib.check(not res.is_empty(), "the pause menu shows RESUME")
	if not res.is_empty():
		await a.tap(a.centre_of(res))
	TestLib.check(Game.state == &"play", "a finger on RESUME goes back to the game (state %s)" % Game.state)
	await a.pframes(6)
	TestLib.check(await a.tap_hud("minimap") and MapScreen.up, "a finger on the minimap opens the map")
	var close := a.find(a.controls(), "Close")
	if not close.is_empty():
		await a.tap(a.centre_of(close))
	TestLib.check(not MapScreen.up and Game.state == &"play", "a finger on the map's CLOSE goes back to the game (state %s)" % Game.state)
	if MapScreen.up:
		a.map_screen().close_screen()
	await a.pframes(6)
	# --- the phone's BACK key: old behaviour first
	BackKey.enabled = false
	a.tree.quit_on_go_back = true
	await a.back_key()
	print("OLD BEHAVIOUR (BackKey off): state after BACK %s, the engine would quit: %s" % [Game.state, a.tree.quit_on_go_back])
	TestLib.check(Game.state == &"play" and a.tree.quit_on_go_back, "old behaviour: the BACK key does nothing in play and the engine closes the game")
	BackKey.enabled = true
	a.tree.quit_on_go_back = false
	TestLib.check(not a.tree.quit_on_go_back, "the engine no longer closes the game on the BACK key")
	await a.back_key()
	TestLib.check(Game.state == &"paused" and BackKey.last == &"pause", "the BACK key pauses a running game (state %s, did %s)" % [Game.state, BackKey.last])
	await a.back_key()
	TestLib.check(Game.state == &"play" and BackKey.last == &"resume", "the BACK key on the plain pause menu resumes (state %s, did %s)" % [Game.state, BackKey.last])
	await a.tap_hud("more")
	await a.back_key()
	TestLib.check(Game.state == &"play" and not a.tc.more_open and BackKey.last == &"more", "the BACK key closes the MORE cluster first (did %s)" % BackKey.last)
	await _tap_ability()
	await a.back_key()
	TestLib.check(Game.state == &"play" and not a.tc.wheel.is_open, "the BACK key closes an open wheel first (did %s)" % BackKey.last)
	await a.tap_hud("minimap")
	await a.back_key()
	TestLib.check(not MapScreen.up and Game.state == &"play" and BackKey.last == &"map", "the BACK key closes the map and the game runs (state %s, did %s)" % [Game.state, BackKey.last])
	await a.pframes(6)


func _spawn(kind: StringName) -> Vehicle:
	var vm := Game.vehicles as VehicleManager
	DemoMenu.spawn_vehicle(kind)
	var best: Vehicle = null
	for v: Vehicle in vm.list:
		if is_instance_valid(v) and v.kind == kind and (best == null or v.global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position)):
			best = v
	return best


func _car() -> void:
	var vm := Game.vehicles as VehicleManager
	var car := _spawn(&"sedan")
	TestLib.check(car != null, "a sedan stands in front of the hero")
	if car == null:
		return
	p.global_position = car.global_position + car.global_transform.basis.x * 2.2 + Vector3(0, 0.3, 0)
	var shown := await a.until(func() -> bool: return not a.hud_button("interact").is_empty(), 300)
	TestLib.check(shown and a.hud_button("interact")["label"] == "ENTER", "beside a car the HUD shows ENTER (%s)" % str(a.hud_button("interact").get("label", "-")))
	for k in 3:                                                       # a loaded machine: the door answers the first tap, the test allows three
		if p.vehicle == null and not a.hud_button("interact").is_empty():
			await a.tap_hud("interact", 6)
			await a.until(func() -> bool: return p.vehicle != null, 150)
	TestLib.check(p.vehicle != null, "a finger on ENTER puts the hero in the car")
	if p.vehicle == null:
		vm.enter(car)
		await a.pframes(10)
	var ids := a.hud_ids()
	TestLib.check(ids.has("jump") and ids.has("interact") and ids.has("veh_view") and ids.has("more") and not ids.has("reload"), "in a car: DRIFT, EXIT, VIEW and MORE (%s)" % str(ids))
	await a.press_hud_frame("car")
	var v0 := p.camera_rig.veh_view
	await a.tap_hud("veh_view", 4)
	await a.pframes(6)
	TestLib.check(p.camera_rig.veh_view != v0, "a finger on VIEW changes the driving camera (%d -> %d)" % [v0, p.camera_rig.veh_view])
	await a.tap_hud("more")
	TestLib.check(a.hud_ids().has("radio_next") and a.hud_ids().has("garage_open") and a.hud_ids().has("look_back"), "MORE in a car: RADIO, GARAGE, BACK (%s)" % str(a.hud_ids()))
	await a.press_hud_frame("car+more")
	var radio: Object = vm.get("radio")
	if radio != null and not a.hud_button("radio_next").is_empty():
		var st0 := str(radio.get("station"))
		await a.tap_hud("radio_next", 4)
		TestLib.check(str(radio.get("station")) != st0, "a finger on RADIO changes the station ONCE (%s -> %s)" % [st0, str(radio.get("station"))])
	# GARAGE: the screen of plain Buttons; each answers one tap, CLOSE and the BACK key leave it
	await a.tap_hud("garage_open", 4)
	var gs := a.tc.get_node_or_null("GarageScreen") as GarageScreen
	TestLib.check(gs != null and gs.is_open(), "a finger on GARAGE opens the garage")
	if gs != null and gs.is_open():
		await a.frames(4)
		(Game.progress as Progress).credits = 50000
		gs.refresh()
		var list := a.node_controls()
		for g in a.geometry("garage", list):
			a.finding(g)
		await a.shot("garage")
		var dead := 0
		var done := {}
		while gs.is_open():                                            # SAVE first enables PAINT and the upgrades: the list is read again after every press
			var c: Dictionary = {}
			for k: Dictionary in a.node_controls():
				if not done.has(k["id"]) and not k["disabled"] and not String(k["id"]).to_lower().contains("close"):
					c = k
					break
			if c.is_empty():
				break
			done[c["id"]] = true
			var before := a.signature() + str((gs._garage().levels if gs._garage() != null else {})) + str(gs._garage().get("paint") if gs._garage() != null else "")
			Sfx.last_played = &""
			var n0 := TouchButtons.presses
			await a.tap(a.centre_of(c))
			var after := a.signature() + str((gs._garage().levels if gs._garage() != null else {})) + str(gs._garage().get("paint") if gs._garage() != null else "")
			var eff := "state" if after != before else ("sound" if Sfx.last_played != &"" else "dead")
			a.row("garage", c, eff, "", "presses %d" % (TouchButtons.presses - n0))
			TestLib.check(TouchButtons.presses - n0 == 1, "garage: one tap on %s '%s' is one press (%d)" % [c["id"], c["label"], TouchButtons.presses - n0])
			if eff == "dead":
				dead += 1
				a.finding("garage: %s '%s' did nothing" % [c["id"], c["label"]])
		for k: Dictionary in a.node_controls():
			if k["disabled"] and not done.has(k["id"]):
				a.row("garage", k, "disabled")
		TestLib.check(dead == 0 and done.size() >= 10, "garage: every button answers the finger (%d dead of %d pressed, %d on screen)" % [dead, done.size(), list.size()])
		await a.back_key()
		TestLib.check(not gs.is_open() and BackKey.last == &"garage", "the BACK key closes the garage (did %s)" % BackKey.last)
		await a.tap_hud("garage_open", 4)
		await a.frames(4)
		var cl: Dictionary = {}
		for c: Dictionary in a.node_controls():
			if String(c["id"]).to_lower().contains("close") or String(c["label"]).to_upper() in ["CLOSE", "BACK", "X"]:
				cl = c
		TestLib.check(not cl.is_empty(), "the garage has a CLOSE button")
		if not cl.is_empty():
			await a.tap(a.centre_of(cl))
		TestLib.check(not gs.is_open(), "a finger on the garage's CLOSE closes it")
		if gs.is_open():
			gs.close_screen()
	Game.state = &"play"
	await a.pframes(4)
	if a.tc.more_open:
		await a.tap_hud("more")
	TestLib.check(a.hud_button("interact").get("label", "") == "EXIT", "in the car the door button says EXIT")
	await a.tap_hud("interact", 4)
	TestLib.check(await a.until(func() -> bool: return p.vehicle == null, 300), "a finger on EXIT leaves the car")
	if p.vehicle != null:
		vm.exit_vehicle()
	await a.pframes(10)


func _aircraft() -> void:
	var vm := Game.vehicles as VehicleManager
	for kind: StringName in [&"heli", &"plane", &"gunship", &"tank"]:
		var hv := _spawn(kind)
		TestLib.check(hv != null, "a %s is there to board" % kind)
		if hv == null:
			continue
		await a.pframes(20)
		vm.enter(hv)
		await a.pframes(15)
		var ids := a.hud_ids()
		var air: bool = VehicleSpecs.cls_of(kind) in [&"heli", &"plane"]
		if air:
			TestLib.check(ids.has("crouch") and a.hud_button("crouch")["label"] == "DOWN" and a.hud_button("jump")["label"] == "UP", "%s: UP and DOWN are on the HUD (%s)" % [kind, str(ids)])
		TestLib.check(ids.has("interact") and ids.has("veh_view") and ids.has("more"), "%s: EXIT, VIEW and MORE are on the HUD (%s)" % [kind, str(ids)])
		await a.press_hud_frame(String(kind))
		var vw: Object = hv.get("weapons")
		if ids.has("fire") and vw != null:
			var s0 := int(vw.get("shots"))
			a.finger_down(a.centre_of(a.hud_button("fire")))
			for k in 60:                                                # until the first shot, not longer: a parked gunship that keeps firing into the street hurts itself
				await a.tree.physics_frame
				if int(vw.get("shots")) > s0:
					break
			a.finger_up()
			await a.pframes(4)
			TestLib.check(int(vw.get("shots")) > s0, "%s: a finger held on FIRE fires the mounted gun (%d -> %d shots)" % [kind, s0, int(vw.get("shots"))])
		if ids.has("aim") and vw != null and bool(vw.call(&"has_alt")):
			var a0 := int(vw.get("alt_shots"))
			a.finger_down(a.centre_of(a.hud_button("aim")))
			for k in 60:
				await a.tree.physics_frame
				if int(vw.get("alt_shots")) > a0:
					break
			a.finger_up()
			await a.pframes(4)
			TestLib.check(int(vw.get("alt_shots")) > a0, "%s: a finger held on %s fires the second weapon (%d -> %d)" % [kind, a.hud_button("aim").get("label", "?"), a0, int(vw.get("alt_shots"))])
		Game.state = &"play"
		if air and not VehicleCraft.can_exit(hv) and not a.hud_button("crouch").is_empty():      # the UP presses lifted it: land with DOWN first, as the game asks ("LAND TO GET OUT")
			a.finger_down(a.centre_of(a.hud_button("crouch")))
			await a.until(func() -> bool: return VehicleCraft.can_exit(hv), 600)
			a.finger_up()
			await a.pframes(6)
			if not VehicleCraft.can_exit(hv):
				print("NOTE %s: DOWN held 600 frames did not land it (height %.1f, speed %.1f): it rests on something that is not ground" % [kind, hv.global_position.y, hv.speed])
		for k in 3:
			if p.vehicle != null and not a.hud_button("interact").is_empty():
				await a.tap_hud("interact", 6)
				await a.until(func() -> bool: return p.vehicle == null, 150)
		var told: bool = p.vehicle != null and air and not VehicleCraft.can_exit(hv) and a.hud.message_text.contains("LAND")      # a craft that is not down answers EXIT with LAND TO GET OUT (the game's rule)
		TestLib.check(p.vehicle == null or told, "%s: a finger on EXIT leaves it, or says LAND TO GET OUT while it is not down (state %s, height %.1f, message '%s')" % [kind, Game.state, hv.global_position.y if is_instance_valid(hv) else 0.0, a.hud.message_text])
		if p.vehicle != null:
			vm.exit_vehicle()
		await a.pframes(10)
		if is_instance_valid(hv):
			vm._release(hv)
		await a.pframes(4)


func _snake_flight() -> void:
	Game.state = &"play"
	p.hp = p.max_hp
	p.global_position += Vector3(0.0, 70.0, 0.0)
	p.velocity = Vector3.ZERO
	var shown := await a.until(func() -> bool: return not a.hud_button("fly").is_empty(), 300)
	TestLib.check(shown and a.hud_button("fly")["label"] == "FLY", "in the air the HUD shows FLY")
	if not shown:
		return
	a.fast_tap(a.centre_of(a.hud_button("fly")))                       # the quick thumb
	TestLib.check(await a.until(func() -> bool: return p.snake.mode == SnakeTraversal.Mode.FLY, 120), "a quick tap on FLY starts the snake flight (mode %d)" % p.snake.mode)
	await a.pframes(20)
	TestLib.check(a.hud_button("fly").get("label", "") == "LAND" and a.hud_button("jump").get("label", "") == "UP", "while flying the buttons read LAND and UP")
	await a.press_hud_frame("snake_flight", ["fly"])
	TestLib.check(p.snake.mode == SnakeTraversal.Mode.FLY, "the hero still flies after every button was held (mode %d)" % p.snake.mode)
	if p.snake.mode == SnakeTraversal.Mode.FLY:
		a.fast_tap(a.centre_of(a.hud_button("fly")))
		TestLib.check(await a.until(func() -> bool: return p.snake.flight.phase == &"landing" or p.snake.mode != SnakeTraversal.Mode.FLY, 120), "a quick tap on LAND starts the landing (phase %s)" % p.snake.flight.phase)
	p.snake.cancel()
	p.global_position.y = 2.0
	p.velocity = Vector3.ZERO
	await a.pframes(40)


func _interior() -> void:
	Game.state = &"play"
	InteriorTestActions.enter(&"shop")
	TestLib.check(await a.until(func() -> bool: return InteriorGameplay.active, 300), "the hero is inside a shop")
	if not InteriorGameplay.active:
		return
	await a.pframes(40)
	var ids := a.hud_ids()
	TestLib.check(not ids.has("snake") and not ids.has("fly"), "inside a room there is no SNAKE or FLY button (%s)" % str(ids))
	TestLib.check(ids.has("leave_building") or str(a.hud_button("interact").get("label", "")) == "LEAVE", "inside a room a LEAVE button is on the HUD (%s)" % str(ids))
	await a.press_hud_frame("interior")
	var id := "leave_building" if a.hud_ids().has("leave_building") else "interact"
	await a.tap_hud(id, 4)
	var out := await a.until(func() -> bool: return not InteriorGameplay.active, 200)
	if not out and not a.hud_button(id).is_empty():                    # a job in progress asks to tap twice
		await a.tap_hud(id, 4)
		out = await a.until(func() -> bool: return not InteriorGameplay.active, 200)
	TestLib.check(out, "a finger on LEAVE takes the hero out of the building")
	if InteriorGameplay.active:
		InteriorTestActions.leave()
	await a.pframes(10)
