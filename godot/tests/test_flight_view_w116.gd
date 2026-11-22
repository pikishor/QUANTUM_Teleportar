extends RefCounted
## OWNER ROUND 7: "fly is working but sometimes there are many rays obscuring the view" and "small silly errors". Real scene, REAL FINGERS (InputEventScreenTouch / Drag through
## Input.parse_input_event, tests/w116_fingers.gd), touch HUD on, reward cards ON (CrateReveal._quiet = 0). Every check has an old-behaviour trial that must FAIL the same measure.
##   controls   FLY is on screen long enough after a JUMP tap; FLY pressed low over the street takes off (it used to stand on the street again); UP climbs, BOOST speeds up, LAND lands;
##              a take-off closes the MORE tray that sat over the hero
##   the view   through the real chase camera: the wing snakes stay off the crosshair disc and under the crosshair row, a wing is short; the speed streaks start in the outer band
##              and are faint; a reward card in the air is the small card at the left edge; rain is not stretched into rays at flight speed
## The picture itself is measured on rendered frames by tools/flight_view.sh (tests/bot_w116_flight_view.gd). Run: tools/test.sh tests/test_flight_view_w116.gd

const TIMEOUT_SECONDS := 140
const Fingers := preload("res://tests/w116_fingers.gd")
const SPOT := Vector3(-30.0, 0.0, 4.0)
var host: Node
var fg: Fingers
var p: Player
var sn: SnakeTraversal


func _f(n: int) -> void:
	await TestLib.frames(host, n)


func _until(cond: Callable, seconds: float) -> bool:
	var n := int(seconds * 60.0)
	for i in n:
		if cond.call():
			return true
		await _f(1)
	return cond.call()


func _tp(pos: Vector3, yaw := -PI * 0.5, pitch := 0.05) -> void:
	fg.up_all()
	await _f(2)
	sn.cancel()
	sn.reset()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await _f(20)


func _tap(finger: int, action: StringName, ticks := 4) -> bool:
	if not fg.press(finger, action):
		return false
	await _f(ticks)
	fg.up(finger)
	return true


## JUMP, then FLY as soon as the button shows, by fingers. True when the hero flies.
func _takeoff(at := SPOT) -> bool:
	await _tp(at)
	await _tap(1, &"jump")
	if not await _until(func() -> bool: return fg.button(&"fly") != Vector2.INF, 1.0):
		return false
	await _tap(1, &"fly")
	return await _until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 0.5)


## The wings through the real camera: [nearest a wing comes to the crosshair (share of the screen height), highest wing point (0 top .. 1 bottom), farthest from the middle column
## (share of the width), longest wing (m)], the worst over `ticks` ticks.
func _wing_view(ticks: int) -> Array[float]:
	var cam := p.camera_rig.camera
	var vp := host.get_tree().root.get_visible_rect().size
	var near := 9.0
	var top := 9.0
	var side := 0.0
	var longest := 0.0
	for t in ticks:
		await _f(1)
		for w in sn.flight.wings:
			if w == null or not w.is_alive() or not w.is_attached():
				continue
			longest = maxf(longest, w.length())
			for k in 9:
				var u := float(k) / 8.0
				var wp := w.origin_pos.lerp(w.head_pos, u) + w.bow * (4.0 * u * (1.0 - u))
				if cam.is_position_behind(wp):
					near = 0.0
					continue
				var sp := cam.unproject_position(wp)
				near = minf(near, sp.distance_to(vp * 0.5) / vp.y)
				top = minf(top, sp.y / vp.y)
				side = maxf(side, absf(sp.x / vp.x - 0.5))
	return [near, top, side, longest]


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	var win_size := host.get_window().size
	host.get_window().size = Vector2i(1200, 540)                # a 20:9 phone
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	CrateReveal._quiet = 0                                   # as on a phone: reward cards are allowed
	p = Game.player as Player
	sn = p.snake
	fg = Fingers.new(host)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	p.max_hp = 1.0e6
	p.hp = 1.0e6
	var at := Game.atmosphere as Atmosphere
	if at != null and at.weather != null:
		at.weather.set_process(false)
		at.set_weather(0.0, 0.3, true)
	TestLib.check(fg.tc != null and fg.tc.controls_on and SnakePower.flight_unlocked(), "the touch HUD is on and the hero can fly")
	await _controls()
	await _view(at)
	fg.up_all()
	FlightView.old_look = false
	SnakeFlight.low_start = true
	SnakeTraversal.fly_show_air = 0.15
	if at != null:
		at.rainfield.long_streaks = false
	CrateReveal.clear()
	CrateReveal._quiet = -1
	host.get_window().size = win_size
	Game.force_touch = false
	main.queue_free()
	await _f(2)


# --- FLY, UP, BOOST, LAND and the MORE tray under real fingers --------------------------------------------------------------------------------

func _fly_window() -> float:
	await _tp(SPOT)
	await _tap(1, &"jump")
	if not await _until(func() -> bool: return fg.button(&"fly") != Vector2.INF, 1.0):
		return 0.0
	var n := 0
	while fg.button(&"fly") != Vector2.INF and n < 200:
		n += 1
		await _f(1)
	return float(n) / 60.0


## FLY pressed late in a jump: falling, less than a metre over the street. Returns [pressed, flying 1.2 s later, height then].
func _low_fly() -> Array:
	await _tp(SPOT)
	await _tap(1, &"jump")
	await _until(func() -> bool: return p.velocity.y < -1.0 and p.global_position.y < 0.95 and not p.is_on_floor(), 1.5)
	var pressed := fg.button(&"fly") != Vector2.INF and not p.is_on_floor()
	await _tap(1, &"fly", 3)
	await _f(72)
	return [pressed, sn.mode == SnakeTraversal.Mode.FLY, p.global_position.y]


func _controls() -> void:
	# the FLY button after a JUMP tap
	# wave 118 (w118-controls): FLY is a button on the ground too (the two-button snake layout); the wave 116 window is measured with the one-button layout it was written for
	TestLib.check(fg.button(&"fly") != Vector2.INF and fg.button(&"snake") != Vector2.INF, "on the street SWING and FLY are both on screen (wave 118: FLY was absent on the ground)")
	var win118 := await _fly_window()
	TestLib.check(win118 >= 3.0, "after a JUMP tap the FLY button never leaves the screen (%.2f s of the 3.33 s measured)" % win118)
	SnakeTraversal.split_buttons = false
	TestLib.check(fg.button(&"fly") == Vector2.INF, "one-button layout (wave 116): on the street FLY is not on screen")
	var win := await _fly_window()
	TestLib.check(win >= 0.45, "one-button layout: after a JUMP tap the FLY button is on screen for %.2f s (at least 0.45)" % win)
	SnakeTraversal.fly_show_air = 0.3
	var win_old := await _fly_window()
	SnakeTraversal.fly_show_air = 0.15
	SnakeTraversal.split_buttons = true
	TestLib.check(win_old < 0.45, "OLD (shown after 0.3 s in the air): %.2f s, too short for a thumb" % win_old)
	# FLY pressed low over the street
	var low := await _low_fly()
	TestLib.check(low[0] and low[1] and float(low[2]) > 2.0, "FLY pressed while falling under a metre over the street takes off (pressed %s, flying %s, %.1f m up after 1.2 s)" % [low[0], low[1], low[2]])
	SnakeFlight.low_start = false
	var low_old := await _low_fly()
	SnakeFlight.low_start = true
	TestLib.check(low_old[0] and not (low_old[1] and float(low_old[2]) > 2.0), "OLD: the same press left him on the street (flying %s, %.1f m)" % [low_old[1], low_old[2]])
	# the MORE tray closes at take-off
	await _tp(SPOT)
	await _tap(2, &"more")
	TestLib.check(fg.tc.more_open and fg.button(&"melee") != Vector2.INF, "a finger on MORE opens the tray")
	var mid := fg.button(&"melee")
	TestLib.check(mid.x / fg.vp().x > 0.6 and mid.y / fg.vp().y < 0.5, "wave 118: the tray is two short rows under the top-right row, clear of the hero and the crosshair (MELEE at %.2f, %.2f)" % [mid.x / fg.vp().x, mid.y / fg.vp().y])
	await _tap(1, &"jump")
	await _until(func() -> bool: return fg.button(&"fly") != Vector2.INF, 1.0)
	await _tap(1, &"fly")
	await _until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 0.5)
	TestLib.check(sn.mode == SnakeTraversal.Mode.FLY and not fg.tc.more_open and fg.button(&"melee") == Vector2.INF, "a take-off closes the MORE tray (nothing over the flying hero)")
	await _tap(2, &"more")
	TestLib.check(fg.tc.more_open, "MORE opens it again in flight")
	await _tap(2, &"more")
	FlightView.old_look = true
	await _tp(SPOT)
	await _tap(2, &"more")
	await _tap(1, &"jump")
	await _until(func() -> bool: return fg.button(&"fly") != Vector2.INF, 1.0)
	await _tap(1, &"fly")
	await _until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 0.5)
	TestLib.check(sn.mode == SnakeTraversal.Mode.FLY and fg.tc.more_open, "OLD: the tray stayed open over the flying hero")
	FlightView.old_look = false
	fg.tc.more_open = false
	# UP, the stick, BOOST, LAND
	TestLib.check(await _takeoff(), "JUMP then FLY by fingers: the hero flies")
	TestLib.check(fg.button_label(&"jump") == "UP" and fg.button_label(&"snake") == "BOOST" and fg.button_label(&"fly") == "LAND", "in flight the buttons read UP, BOOST and LAND (%s, %s, %s)" % [fg.button_label(&"jump"), fg.button_label(&"snake"), fg.button_label(&"fly")])
	var y0 := p.global_position.y
	fg.press(1, &"jump")
	await _f(80)
	fg.up(1)
	TestLib.check(sn.mode == SnakeTraversal.Mode.FLY and p.global_position.y > y0 + 7.0, "UP held climbs (%.1f m in 1.3 s)" % (p.global_position.y - y0))
	fg.stick(Vector2(0.0, -1.0))
	await _f(100)
	var cruise_v := p.velocity.length()
	fg.press(1, &"snake")
	await _f(90)
	var boost_v := p.velocity.length()
	TestLib.check(sn.flight.boosting and boost_v > cruise_v + 8.0 and cruise_v > 15.0, "the stick gives thrust (%.0f m/s) and BOOST held speeds up (%.0f m/s)" % [cruise_v, boost_v])
	fg.up(1)
	fg.stick(Vector2.ZERO)
	var hov := await _until(func() -> bool: return sn.flight.phase == &"hover", 6.0)
	TestLib.check(hov and sn.mode == SnakeTraversal.Mode.FLY, "thumbs off: he slows down and hovers")
	await _tap(1, &"fly")
	var landed := await _until(func() -> bool: return sn.mode == SnakeTraversal.Mode.NONE and p.is_on_floor(), 14.0)
	TestLib.check(landed, "a finger on LAND brings him down and the flight ends on the ground (%s, floor %s, %.1f m)" % [sn.mode_name(), p.is_on_floor(), p.global_position.y])


# --- the view --------------------------------------------------------------------------------------------------------------------------------

func _view(at: Atmosphere) -> void:
	TestLib.check(await _takeoff(), "airborne again for the view checks")
	fg.press(1, &"jump")
	await _f(70)
	fg.up(1)
	fg.stick(Vector2(0.0, -1.0))
	await _f(150)
	# cruise
	var v := await _wing_view(30)
	TestLib.check(v[0] > 0.085 and v[1] > 0.5, "cruise: no wing in the crosshair disc (nearest %.3f of the height, disc 0.08) and none above the crosshair row (top at %.2f)" % [v[0], v[1]])
	TestLib.check(v[3] < 2.4 and v[2] < 0.2, "cruise: a wing is %.1f m long and stays within %.2f of the width beside the hero" % [v[3], v[2]])
	FlightView.old_look = true
	await _f(90)
	var o := await _wing_view(30)
	FlightView.old_look = false
	TestLib.check(o[0] < 0.085 or o[1] < 0.5 or o[2] > 0.3 or o[3] > 2.4, "OLD wings fail it: nearest to the crosshair %.3f, top %.2f, reach %.2f of the width, %.1f m long" % [o[0], o[1], o[2], o[3]])
	await _f(90)
	# boost: wings and streaks
	fg.press(1, &"snake")
	await _f(110)
	v = await _wing_view(20)
	TestLib.check(v[0] > 0.085 and v[1] > 0.5 and v[3] < 2.4, "boost: wings off the crosshair (%.3f), under its row (%.2f), %.1f m long" % [v[0], v[1], v[3]])
	var fx := p.get_node_or_null("SnakeFx") as SnakeFx
	var prm := fx.lines_params_now()
	TestLib.check(fx.lines_on and prm.size() == 10 and prm[0] == 1.0 and FlightView.lines_inner_min(prm) >= 0.75 and prm[5] <= 0.25,
		"boost: the speed streaks are on, start %.2f of the way to the screen edge (box distance) and peak at alpha %.2f" % [FlightView.lines_inner_min(prm) if prm.size() == 10 else -1.0, prm[5] if prm.size() == 10 else -1.0])
	FlightView.old_look = true
	await _f(4)
	var prm_old := fx.lines_params_now()
	FlightView.old_look = false
	TestLib.check(prm_old.size() == 10 and (FlightView.lines_inner_min(prm_old) < 0.6 or prm_old[5] > 0.25), "OLD streaks fail it: they start at %.2f (inside the middle 60 %%) with alpha %.2f" % [FlightView.lines_inner_min(prm_old) if prm_old.size() == 10 else -1.0, prm_old[5] if prm_old.size() == 10 else -1.0])
	await _f(4)
	# rain at boost speed
	if at != null:
		at.set_weather(1.0, 0.9, true)
		await _f(60)
		var cv: float = (at.rainfield.get("_cam_vel") as Vector3).length()
		TestLib.check(p.velocity.length() > 40.0 and cv <= Atmosphere.RainField.STREAK_CAM_SPEED + 0.5 and at.rainfield.speed_dim < 0.8,
			"rain at %.0f m/s: the streaks stretch as for %.0f m/s and dim to %.2f" % [p.velocity.length(), cv, at.rainfield.speed_dim])
		at.rainfield.long_streaks = true
		await _f(60)
		var cv_old: float = (at.rainfield.get("_cam_vel") as Vector3).length()
		at.rainfield.long_streaks = false
		TestLib.check(cv_old > 35.0, "OLD rain fails it: stretched for %.0f m/s (2 m rays out of the middle of the screen)" % cv_old)
		at.set_weather(0.0, 0.3, true)
	fg.up(1)
	fg.stick(Vector2.ZERO)
	# hover: the widest wings, and a reward card
	await _until(func() -> bool: return sn.flight.phase == &"hover", 6.0)
	await _f(90)
	v = await _wing_view(30)
	TestLib.check(sn.flight.wing_spread > 0.9 and v[0] > 0.085 and v[1] > 0.5 and v[3] < 2.4 and v[2] < 0.25, "hover (wings spread %.2f): off the crosshair (%.3f), under its row (%.2f), %.1f m long, %.2f of the width" % [sn.flight.wing_spread, v[0], v[1], v[3], v[2]])
	var vp := fg.vp()
	var centre := Rect2(vp * 0.2, vp * 0.6)
	CrateReveal.request(WeaponDefs.IDS[5], "MISSION REWARD", true)
	await _f(20)
	var card := CrateReveal.current
	TestLib.check(card != null and card.air and card.compact and not card.card_rect().intersects(centre), "a reward card in flight is the small card at the left edge, outside the middle 60 %% (%s)" % (str(card.card_rect()) if card != null else "none"))
	await _f(12)
	await _tap(4, &"more", 2)
	await _f(3)
	TestLib.check(not CrateReveal.is_showing(), "and a finger anywhere closes it")
	if fg.tc.more_open:
		await _tap(4, &"more", 2)
	FlightView.old_look = true
	CrateReveal.request(WeaponDefs.IDS[6], "MISSION REWARD", true)
	await _f(20)
	card = CrateReveal.current
	TestLib.check(card != null and not card.compact and card.card_rect().intersects(centre), "OLD: the full card with its dim and rays over the middle of the view")
	FlightView.old_look = false
	CrateReveal.clear()
	# a full card on the ground shrinks when the hero takes off under it
	await _tp(SPOT)
	CrateReveal.request(WeaponDefs.IDS[7], "MISSION REWARD", true)
	await _f(30)
	card = CrateReveal.current
	TestLib.check(card != null and not card.air and not card.compact, "standing on the street the card is the full one")
	await _tap(1, &"jump", 6)
	if not CrateReveal.is_showing():                                  # (the JUMP tap closed it: a tap closes a card) show one again, already in the air
		CrateReveal.request(WeaponDefs.IDS[7], "MISSION REWARD", true)
	await _f(24)
	card = CrateReveal.current
	TestLib.check(card != null and card.air, "in the air it is the small one")
	CrateReveal.clear()
