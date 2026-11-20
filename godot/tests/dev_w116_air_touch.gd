extends RefCounted
## Wave 116 probe (not a test): what SNAKE, ZIP, FLY / LAND, BOOST and UP do under REAL FINGERS in the real main scene, printed as facts for the defect list of
## docs/sprint/progress/w116-flight-view.md. Run: tools/test.sh tests/dev_w116_air_touch.gd   (W116_PROBE=fly,land,zip,swing,hold picks parts)

const TIMEOUT_SECONDS := 140
const Fingers := preload("res://tests/w116_fingers.gd")
var host: Node
var fg: Fingers
var p: Player
var sn: SnakeTraversal


func _f(n: int) -> void:
	await TestLib.frames(host, n)


func _tp(pos: Vector3, yaw: float, pitch: float) -> void:
	fg.up_all()
	await _f(2)
	sn.cancel()
	sn.reset()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await _f(20)


func _tap(finger: int, action: StringName, frames := 4) -> bool:
	if not fg.press(finger, action):
		return false
	await _f(frames)
	fg.up(finger)
	return true


func _wait_button(action: StringName, max_frames: int) -> int:
	for i in max_frames:
		if fg.button(action) != Vector2.INF:
			return i
		await _f(1)
	return -1


func _state() -> String:
	return "mode %s phase %s pos %s v %.1f floor %s e %.0f label %s" % [sn.mode_name(), sn.flight.phase, p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), p.velocity.length(), p.is_on_floor(), sn.energy, sn.button_label()]


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	Engine.time_scale = 3.0
	CrateReveal._quiet = 0
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
	var parts := (OS.get_environment("W116_PROBE") if OS.get_environment("W116_PROBE") != "" else "fly,land,zip,swing,hold").split(",")
	print("PROBE controls ", fg.tc != null and fg.tc.controls_on, " flight unlocked ", SnakePower.flight_unlocked(), " cruise ", SnakePower.fly_cruise(), " boost ", SnakePower.fly_boost(), " range ", SnakePower.range_m())
	if "fly" in parts:
		await _probe_fly()
	if "land" in parts:
		await _probe_land()
	if "zip" in parts:
		await _probe_zip()
	if "swing" in parts:
		await _probe_swing()
	if "hold" in parts:
		await _probe_hold()
	fg.up_all()
	Engine.time_scale = 1.0
	Game.force_touch = false
	CrateReveal._quiet = -1
	main.queue_free()
	await _f(2)


## FLY from the street: is the button there, how long is the window after a jump, does the flight last, what do UP, the stick and BOOST do.
func _probe_fly() -> void:
	await _tp(Vector3(-30.0, 0.0, 4.0), -PI * 0.5, 0.1)
	print("PROBE FLY on the ground: FLY button on screen ", fg.button(&"fly") != Vector2.INF, "  SNAKE label ", fg.button_label(&"snake"))
	await _tap(1, &"jump")
	var w := await _wait_button(&"fly", 60)
	var win := 0
	if w >= 0:
		while fg.button(&"fly") != Vector2.INF and win < 200:
			win += 1
			await _f(1)
	print("PROBE FLY after a JUMP tap the FLY button shows after %d ticks and stays %d ticks (%.2f s), then the hero is back on the floor" % [w, win, win / 60.0])
	# take off: JUMP, FLY as soon as it shows
	for trial in 3:
		await _tp(Vector3(-30.0, 0.0, 4.0), -PI * 0.5, 0.1)
		await _tap(1, &"jump")
		var w2 := await _wait_button(&"fly", 60)
		await _f(trial * 6)                                    # a slower thumb each trial
		var ok := await _tap(1, &"fly")
		var y0 := p.global_position.y
		var t_fly := 0
		for i in 180:
			await _f(1)
			if sn.mode == SnakeTraversal.Mode.FLY:
				t_fly += 1
		print("PROBE FLY trial %d: FLY pressed %s at height %.2f (button after %d ticks, thumb delay %d): flew %d of 180 ticks, now %s" % [trial, ok, y0, w2, trial * 6, t_fly, _state()])
	# a flight that holds: take off, UP, forward, BOOST
	await _tp(Vector3(-30.0, 0.0, 4.0), -PI * 0.5, 0.1)
	await _tap(1, &"jump")
	await _wait_button(&"fly", 60)
	await _tap(1, &"fly")
	fg.press(1, &"jump")                                       # UP held
	await _f(90)
	fg.up(1)
	print("PROBE FLY after UP held 1.5 s: ", _state(), "  JUMP label ", fg.button_label(&"jump"))
	if sn.mode != SnakeTraversal.Mode.FLY:
		return
	fg.stick(Vector2(0.0, -1.0))
	await _f(120)
	print("PROBE FLY forward 2 s: ", _state())
	fg.press(1, &"snake")
	await _f(90)
	print("PROBE FLY BOOST 1.5 s: ", _state(), " boosting ", sn.flight.boosting)
	fg.up(1)
	fg.stick(Vector2.ZERO)
	await _f(120)
	print("PROBE FLY thumb off 2 s (hover): ", _state())
	var y1 := p.global_position.y
	await _f(180)
	print("PROBE FLY hover 3 s more: height %.1f -> %.1f  %s" % [y1, p.global_position.y, _state()])


func _probe_land() -> void:
	for hgt in [12.0, 60.0, 160.0]:
		await _tp(Vector3(-30.0, hgt, 4.0), -PI * 0.5, 0.0)
		var w := await _wait_button(&"fly", 60)
		await _tap(1, &"fly")
		await _f(40)
		var was_fly := sn.mode == SnakeTraversal.Mode.FLY
		var y0 := p.global_position.y
		var ok := await _tap(1, &"fly")                          # LAND
		var n := 0
		while sn.mode == SnakeTraversal.Mode.FLY and n < 1500:
			n += 1
			await _f(1)
		print("PROBE LAND from %.0f m: flying %s (FLY after %d ticks), LAND pressed %s (label was LAND), on the ground after %.1f s: %s" % [y0, was_fly, w, ok, n / 60.0, _state()])
	# LAND, then change your mind: FLY again cancels?
	await _tp(Vector3(-30.0, 80.0, 4.0), -PI * 0.5, 0.0)
	await _wait_button(&"fly", 60)
	await _tap(1, &"fly")
	await _f(40)
	await _tap(1, &"fly")
	await _f(30)
	var ph := sn.flight.phase
	var lab := fg.button_label(&"fly")
	fg.press(1, &"jump")
	fg.stick(Vector2(0.0, -1.0))
	await _f(60)
	print("PROBE LAND landing phase %s, FLY button reads %s; UP + forward held 1 s while landing: vy %.1f speed %.1f (UP and thrust are ignored in a landing)" % [ph, lab, p.velocity.y, p.velocity.length()])
	fg.up(1)
	await _tap(1, &"fly")
	await _f(20)
	print("PROBE LAND a second press: phase ", sn.flight.phase, " ", _state())
	fg.stick(Vector2.ZERO)


## ZIP: at many street spots, look at the building across the street at three pitches, tap SNAKE when it reads ZIP. Where does the hero end up?
func _probe_zip() -> void:
	var city := Game.world as City
	var stats := {}
	var lines: PackedStringArray = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var tried := 0
	for k in 10:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for pitch in [0.2, 0.55]:
			var yaw := rng.randf_range(-PI, PI)
			await _tp(rp, yaw, pitch)
			var label := fg.button_label(&"snake")
			if label != "ZIP":
				stats["label " + label] = int(stats.get("label " + label, 0)) + 1
				continue
			tried += 1
			var from := p.global_position
			await _tap(1, &"snake")
			var kind := sn.zip.kind if sn.mode == SnakeTraversal.Mode.ZIP else &"none"
			var dist := sn.zip.last_dist
			var dest := sn.zip.dest
			var started := sn.mode_name()
			var max_step := 0.0
			var prev := p.global_position
			var n := 0
			while n < 240:
				n += 1
				await _f(1)
				max_step = maxf(max_step, p.global_position.distance_to(prev))
				prev = p.global_position
				if sn.mode == SnakeTraversal.Mode.NONE and p.is_on_floor():
					break
			var res := "?"
			if started != "zip":
				res = "no zip (%s)" % started
			elif sn.mode == SnakeTraversal.Mode.CLIMB:
				res = "hangs on a wall (climb)"
			elif p.is_on_floor() and p.global_position.y > from.y + 2.5:
				res = "stands on a roof or ledge"
			elif p.is_on_floor():
				res = "on the street"
			else:
				res = "in the air"
			var key := "%s -> %s" % [kind, res]
			stats[key] = int(stats.get(key, 0)) + 1
			print("    end %s blocked_by %s  from %s dest %s anchor %s" % [sn.zip.end_reason, sn.zip.blocked_by.right(60), from.snapped(Vector3(0.1, 0.1, 0.1)), dest.snapped(Vector3(0.1, 0.1, 0.1)), sn.zip.anchor.snapped(Vector3(0.1, 0.1, 0.1))])
			print("  zip %s pitch %.2f dist %.0f dest dy %+.1f -> %s after %.1f s at dy %+.1f, miss %.1f m, biggest step %.2f m" % [kind, pitch, dist, dest.y - from.y, res, n / 60.0, p.global_position.y - from.y, p.global_position.distance_to(dest), max_step])
	print("PROBE ZIP ", tried, " zips: ", stats)


## SWING: JUMP, then SNAKE held 10 s (the auto chain), per-swing facts from SnakeSwing.log; a tap in the air; a press on the ground; a release and a new press.
func _probe_swing() -> void:
	for spot in [Vector3(-30.0, 0.0, 4.0), Vector3(40.0, 0.0, 4.0)]:
		await _tp(spot, -PI * 0.5, 0.2)
		await _tap(1, &"jump")
		await _f(8)
		var ok := fg.press(1, &"snake")
		var s0 := sn.swings
		var l0 := sn.swing.log.size()
		var from := p.global_position
		var floor_ticks := 0
		var max_step := 0.0
		var prev := p.global_position
		var modes := {}
		var min_y := 99.0
		var max_y := 0.0
		var wait_attach := -1
		var sp_sum := 0.0
		for i in 200:
			await _f(1)
			if wait_attach < 0 and sn.swing.phase == &"hang":
				wait_attach = i
			max_step = maxf(max_step, p.global_position.distance_to(prev))
			prev = p.global_position
			modes[sn.mode_name()] = int(modes.get(sn.mode_name(), 0)) + 1
			if p.is_on_floor():
				floor_ticks += 1
			if i > 20:
				min_y = minf(min_y, p.global_position.y)
				max_y = maxf(max_y, p.global_position.y)
			sp_sum += p.velocity.length()
		fg.up(1)
		print("PROBE SWING hold 10 s from %s: pressed %s, bite after %d ticks, swings %d, travelled %.0f m (mean speed %.1f m/s), height %.1f..%.1f m, ticks on the floor %d, biggest step %.2f m, time in %s, now %s" % [spot, ok, wait_attach, sn.swings - s0, Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length(), sp_sum / 200.0 / 3.0 * 3.0, min_y, max_y, floor_ticks, max_step, modes, _state()])
		for k in range(l0, sn.swing.log.size()):
			print("    swing ", sn.swing.log[k])
		await _f(40)
		print("    2 s after letting go: ", _state())
	# a TAP in the air
	await _tp(Vector3(-30.0, 0.0, 4.0), -PI * 0.5, 0.2)
	await _tap(1, &"jump")
	await _f(8)
	var s1 := sn.swings
	await _tap(1, &"snake", 3)
	var t_sw := 0
	for i in 100:
		await _f(1)
		if sn.mode == SnakeTraversal.Mode.SWING:
			t_sw += 1
	print("PROBE SWING a tap in the air: swings +%d, swinging for %d ticks, then %s" % [sn.swings - s1, t_sw, _state()])
	# SNAKE on the ground where the label reads SWING
	var city := Game.world as City
	var seen := {}
	for k in 12:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		await _tp(rp, float(k) * 0.9, -0.05)
		var label := fg.button_label(&"snake")
		await _tap(1, &"snake")
		await _f(20)
		var key := "label %s -> %s (floor %s)" % [label, sn.mode_name(), p.is_on_floor()]
		seen[key] = int(seen.get(key, 0)) + 1
	print("PROBE SNAKE tapped on the ground, looking level: ", seen)
	# let go, then press again at once
	await _tp(Vector3(-30.0, 0.0, 4.0), -PI * 0.5, 0.2)
	await _tap(1, &"jump")
	await _f(8)
	fg.press(1, &"snake")
	await _f(50)
	var v_hang := p.velocity.length()
	fg.up(1)
	await _f(3)
	var v_rel := p.velocity.length()
	var s2 := sn.swings
	fg.press(1, &"snake")
	var again := -1
	for i in 60:
		await _f(1)
		if sn.swings > s2:
			again = i
			break
	fg.up(1)
	print("PROBE SWING let go at %.1f m/s -> %.1f m/s after the release; a new press swings again after %d ticks (-1: not within 3 s), %s" % [v_hang, v_rel, again, _state()])


## SNAKE held on the ground: what does a held button do in the city.
func _probe_hold() -> void:
	var city := Game.world as City
	var out := {}
	for k in 10:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		await _tp(rp, float(k) * 0.7, 0.25)
		var label := fg.button_label(&"snake")
		fg.press(1, &"snake")
		await _f(80)
		var m := sn.mode_name()
		fg.up(1)
		await _f(60)
		var key := "label %s, held 1.3 s -> %s, released -> %s" % [label, m, sn.mode_name()]
		out[key] = int(out.get(key, 0)) + 1
	print("PROBE HOLD on the ground:")
	for k2 in out:
		print("  ", out[k2], " x ", k2)
