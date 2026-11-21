extends RefCounted
## WAVE 116 CRITIC: defects found by playing the real main scene with fingers only (tests/bot_w116_critic.gd), each pinned here with REAL finger events (InputEventScreenTouch through
## Input.parse_input_event, window coordinates), Game.force_touch on and the phone-only layers on. CRITIC_OLD=<name> switches ONE fix off: the test must then fail.
##  1 shove: NEW GAME, nobody touches the screen: the traffic must not push the standing hero (old: 10 m in 14 s, a car every 2 s, the picture lost him each time).
##  3 feed:  the pickup feed never lies on a touch button (old: three lines across GRAB / FLY).
##  2 land:  a double tap on LAND still lands (old: the second press called the landing off and the label still read LAND); a later press, labelled FLY, flies on.
## Run: tools/test.sh tests/test_critic_w116.gd
const TIMEOUT_SECONDS := 145
var host: Node
var root: Window
var tc: TouchControls


func _touch(pos: Vector2, down: bool, idx := 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = root.get_final_transform() * pos
	e.pressed = down
	Input.parse_input_event(e)


func _ticks(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame


func _tap(pos: Vector2) -> void:
	_touch(pos, true)
	await _ticks(3)
	_touch(pos, false)
	await _ticks(3)


func _btn(action: StringName) -> Vector2:
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == action and tc.button_visible(b):
			return tc._button_center(b)
	return Vector2.INF


func _label(action: StringName) -> String:
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == action and tc.button_visible(b):
			return tc._label_of(b)
	return ""


func run(h: Node) -> void:
	host = h
	root = h.get_tree().root
	var old := OS.get_environment("CRITIC_OLD")
	Vehicle.hero_pass = old != "shove"
	SnakeFlight.land_guard = 0.0 if old == "land" else 0.8
	Hud.feed_clear = old != "feed"
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 20)
	var size0 := root.size
	root.size = Vector2i(1200, 540)                              # the phone's aspect (2400 x 1080)
	await TestLib.frames(host, 4)
	CrateReveal._quiet = 0
	tc = root.find_children("*", "TouchControls", true, false)[0] as TouchControls
	var hud := host.get_tree().get_first_node_in_group(&"hud")
	# --- 1: NEW GAME by a finger on PLAY, then hands off
	Game.state = &"menu"                                         # set-up: the test runner boots into play, a phone boots into the title
	await TestLib.frames(host, 10)
	hud.call(&"_ensure_layout")
	var play := Vector2.INF
	for b: Dictionary in hud.get("buttons"):
		if b["id"] == &"deploy":
			play = (b["rect"] as Rect2).get_center()
	TestLib.check(play != Vector2.INF, "the title of a fresh install offers PLAY")
	await _tap(play)
	await _ticks(20)
	TestLib.check(Game.state == &"play", "a finger on PLAY starts the game (state %s)" % Game.state)
	var p := Game.player as Player
	var start := p.global_position
	var far := 0.0
	var low := 0.0
	var cars := 0
	var seen := {}
	for i in 840:                                              # 14 s
		await host.get_tree().physics_frame
		far = maxf(far, Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length())
		low = minf(low, p.global_position.y - start.y)
		if i % 6 == 0:
			for v: Vehicle in (Game.vehicles as VehicleManager).list:
				if v.active and not seen.has(v) and v.global_position.distance_to(p.global_position) < 4.5 and absf(v.speed) > 1.0:
					seen[v] = true
					cars += 1
	TestLib.check(far < 0.4, "nobody touches the screen for 14 s: the traffic does not move the hero (pushed %.2f m, %d real cars drove within 4.5 m)" % [far, cars])
	TestLib.check(low > -0.1, "and it does not press him into the road (lowest %.2f m)" % low)
	# --- 2: a flight, LAND twice
	p.global_position = start + Vector3(0.0, 70.0, 0.0)          # set-up only: high over the street, falling
	p.velocity = Vector3.ZERO
	var sn := p.snake as SnakeTraversal
	var g := 0
	while _btn(&"fly") == Vector2.INF and g < 180:
		g += 1
		await host.get_tree().physics_frame
	TestLib.check(_btn(&"fly") != Vector2.INF, "FLY is on screen in a fall")
	# --- 3: four pickups while FLY is on screen: the feed must not lie on a button
	for line in ["+30 INTEGRITY", "NEW MOD  RED DOT  (LOADOUT TO EQUIP)", "+60 FLUX SMG", "+1 SCRAP"]:
		Game.say(line, 2.0)
	var feed := (hud.get("feed") as HudFeed).last_rects
	g = 0
	while feed.size() < 4 and g < 40:                            # the HUD redraws 12 to 20 times a second
		g += 1
		await host.get_tree().process_frame
	var s := tc._scale()
	var over: Array[String] = []
	for b: Dictionary in TouchControls.BUTTONS:
		if not tc.button_visible(b) and not (b["action"] == &"grab" or b["action"] == &"fly"):       # GRAB and FLY appear by themselves (a person in reach, a jump)
			continue
		var c := tc._button_center(b)
		var r := float(b["r"]) * s * UiSettings.s_button_size
		for fr: Rect2 in feed:
			var near := Vector2(clampf(c.x, fr.position.x, fr.end.x), clampf(c.y, fr.position.y, fr.end.y))
			if near.distance_to(c) < r and not over.has(tc._label_of(b)):
				over.append(tc._label_of(b))
	TestLib.check(feed.size() >= 3, "set-up: the pickup feed shows %d lines" % feed.size())
	TestLib.check(over.is_empty(), "no line of the pickup feed lies on a touch button or on the spot of GRAB / FLY (on: %s)" % ", ".join(over))
	await _tap(_btn(&"fly"))
	await _ticks(60)
	TestLib.check(sn.mode == SnakeTraversal.Mode.FLY, "a finger on FLY takes off")
	TestLib.check(_label(&"fly") == "LAND", "the button reads LAND in flight (%s)" % _label(&"fly"))
	await _tap(_btn(&"fly"))
	await _ticks(18)                                             # 0.4 s: the second tap of a double tap
	var lab := _label(&"fly")
	await _tap(_btn(&"fly"))
	await _ticks(20)
	TestLib.check(sn.flight.phase == &"landing", "LAND tapped twice within half a second is still a landing (phase %s, the button read %s at the second tap)" % [sn.flight.phase, lab])
	g = 0
	while not (p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE) and g < 600:
		g += 1
		await host.get_tree().physics_frame
	TestLib.check(p.is_on_floor() and sn.mode == SnakeTraversal.Mode.NONE, "and the hero stands on the ground %.1f s later (mode %s, height %.1f)" % [g / 60.0, SnakeTraversal.Mode.keys()[sn.mode], p.global_position.y])
	# a later press, when the button says FLY, calls the landing off: the control still answers
	p.global_position = start + Vector3(0.0, 140.0, 0.0)
	p.velocity = Vector3.ZERO
	sn.energy = 100.0
	g = 0
	while _btn(&"fly") == Vector2.INF and g < 180:
		g += 1
		await host.get_tree().physics_frame
	await _tap(_btn(&"fly"))
	await _ticks(60)
	await _tap(_btn(&"fly"))
	await _ticks(60)
	var lab2 := _label(&"fly")
	if sn.mode == SnakeTraversal.Mode.FLY and sn.flight.phase == &"landing":
		TestLib.check(lab2 == "FLY" or old == "land", "one second into a landing the button reads FLY (%s)" % lab2)
		await _tap(_btn(&"fly"))
		await _ticks(10)
		TestLib.check(sn.mode == SnakeTraversal.Mode.FLY and sn.flight.phase != &"landing", "and a finger on it flies on (phase %s)" % sn.flight.phase)
	else:
		TestLib.check(false, "set-up: still landing one second after LAND from 140 m (mode %s phase %s)" % [SnakeTraversal.Mode.keys()[sn.mode], sn.flight.phase])
	Vehicle.hero_pass = true
	SnakeFlight.land_guard = 0.8
	Hud.feed_clear = true
	root.size = size0
