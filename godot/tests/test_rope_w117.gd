extends RefCounted
## WAVE 117 (owner round 7: "snake zip line does not work properly", "small silly errors. Are you even checking."): THE ROPE OF SNAKES, THE ZIP AND THE CUES.
## The real main scene as a 1200x540 phone, REAL FINGERS (InputEventScreenTouch through Input.parse_input_event, tests/w116_fingers.gd), touch HUD on, reward cards on.
## Every part runs twice: the game as it is, and once more with the wave 116 behaviour switched back on (static switches): the same checks must FAIL there.
##   rope     the swing rope is three snakes braided together, all in the ONE draw of the tendril pool; the braid pulls tight under load and unwinds when it is let go
##   zip      a ZIP at a wall never leaves the hero hanging: the snakes haul him over the roof edge and he stands (or, with no ledge in reach, he is dropped cleanly and told why)
##   cues     a marker sits on the anchor a ZIP would take and says what will happen; a press with nothing in reach says NO ANCHOR on the button and at the crosshair;
##            SNAKE FLIGHT warns before the energy ends; rain leaves the lens and thins while the hero is in the air
## The pictures: tests/bot_w117_rope.gd and tools/flight_view.sh. Run: tools/test.sh tests/test_rope_w117.gd

const TIMEOUT_SECONDS := 148
const Fingers := preload("res://tests/w116_fingers.gd")
const SPOT := Vector3(-30.0, 0.0, 4.0)
const WALL_SPOT := Vector3(240.1, 0.0, -305.0)       ## a street; yaw WALL_YAW looks at a facade 12 m away whose roof is 28 m up (tests/dev_w117_spots.gd)
const WALL_YAW := PI * 0.5
const OPEN_SPOT := Vector3(1200.0, 0.0, 0.0)         ## nothing to bite within reach
var host: Node
var fg: Fingers
var p: Player
var sn: SnakeTraversal
var fx: SnakeFx
var said: Array[String] = []


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


## What the touch HUD would draw for the cues now: [centres of the rings and plates, lines of text].
func _hud() -> Array:
	var sprites: Array = []
	var labels: Array = []
	SnakeFx.hud_cues(fg.tc, fg.tc._scale(), sprites, labels)
	var centres: Array = []
	for sp: Array in sprites:
		centres.append([(sp[0] as Rect2).get_center()])
	var texts: Array[String] = []
	for l: Array in labels:
		texts.append(str(l[1]))
	return [centres, texts]


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
	fx = SnakeFx.current
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
	var on_say := func(text: String, _s: float) -> void: said.append(text)
	Game.message.connect(on_say)
	TestLib.check(fg.tc != null and fg.tc.controls_on and fx != null and SnakePower.flight_unlocked(), "the touch HUD is on, the hero has his snakes and can fly")
	await _rope()
	await _zip()
	await _no_anchor()
	await _energy_and_rain(at)
	fg.up_all()
	Game.message.disconnect(on_say)
	SnakeTendril.braided_rope = true
	SnakeZip.wall_end = true
	SnakeZip.haul_max = 140.0
	SnakePose.haul_upright = true
	SnakeFx.cues_on = true
	Atmosphere.air_clear = true
	Game.force_touch = false
	CrateReveal._quiet = -1
	host.get_window().size = win_size
	main.queue_free()
	await _f(2)


# --- the rope ----------------------------------------------------------------------------------------------------------------------------

## JUMP, then SNAKE held in the air, by fingers: the facts of the rope from the bite to the release.
func _swing_facts() -> Dictionary:
	var out := {"swing": false, "braid": 0, "instances": 0, "nodes": 0, "ropes": 0, "r_fly": 0.0, "r_taut": 9.0, "pitch_fly": 0.0, "pitch_taut": 9.0, "open_max": 0.0, "r_open": 0.0, "retract_s": 0.0}
	await _tp(SPOT)
	await _tap(1, &"jump")
	await _until(func() -> bool: return p.air_time > 0.25, 1.0)
	fg.press(2, &"snake")
	out["swing"] = await _until(func() -> bool: return sn.mode == SnakeTraversal.Mode.SWING and sn.swing.tendril != null, 1.0)
	if not out["swing"]:
		fg.up_all()
		return out
	var t := sn.swing.tendril
	await _f(2)
	var pool := SnakeTendrilPool.current
	out["braid"] = t.braid
	out["instances"] = pool.instances
	out["ropes"] = pool.count()
	out["nodes"] = pool.find_children("*", "GeometryInstance3D", true, false).size()
	out["r_fly"] = t.braid_radius
	out["pitch_fly"] = t.braid_pitch
	for i in 150:                                            # 2.5 s on the rope: the tightest it gets under load
		await _f(1)
		if sn.mode != SnakeTraversal.Mode.SWING or sn.swing.tendril != t:
			break
		if t.is_attached() and t.braid_radius > 0.0:
			out["r_taut"] = minf(float(out["r_taut"]), t.braid_radius)
			out["pitch_taut"] = minf(float(out["pitch_taut"]), t.braid_pitch)
		if t.is_attached() and t.tension > 0.85 and t.braid_open < 0.05:
			break
	fg.up(2)                                                 # let go
	var n := 0
	for i in 90:
		await _f(1)
		if t.state == SnakeTendril.State.RETRACT:
			n += 1
			out["open_max"] = maxf(float(out["open_max"]), t.braid_open)
			out["r_open"] = maxf(float(out["r_open"]), t.braid_radius)
		elif not t.is_alive():
			break
	out["retract_s"] = float(n) / 60.0
	return out


func _rope_ok(f: Dictionary) -> Array[bool]:
	return [
		bool(f["swing"]) and int(f["braid"]) >= 3,
		int(f["ropes"]) == 1 and int(f["instances"]) == int(f["braid"]) and int(f["instances"]) >= 3 and int(f["nodes"]) == 1,
		float(f["r_taut"]) < float(f["r_fly"]) * 0.75 and float(f["pitch_taut"]) < float(f["pitch_fly"]) * 0.85 and float(f["r_fly"]) > 0.0,
		float(f["open_max"]) > 0.6 and float(f["r_open"]) > float(f["r_taut"]) * 1.5 and float(f["retract_s"]) >= 0.2,
	]


func _rope() -> void:
	var f := await _swing_facts()
	var ok := _rope_ok(f)
	TestLib.check(ok[0], "JUMP then SNAKE held by a finger: the swing rope is %d snakes braided together" % int(f["braid"]))
	TestLib.check(ok[1], "the whole rope is in the one draw of the tendril pool: %d rope, %d bodies as instances of %d drawing node" % [int(f["ropes"]), int(f["instances"]), int(f["nodes"])])
	TestLib.check(ok[2], "the braid pulls tight under load: strands %.3f m from the axis flying out, %.3f m taut; one turn every %.2f m, then %.2f m" % [float(f["r_fly"]), float(f["r_taut"]), float(f["pitch_fly"]), float(f["pitch_taut"])])
	TestLib.check(ok[3], "let go: the braid unwinds while it slides back (open %.2f, strands out to %.3f m, %.2f s)" % [float(f["open_max"]), float(f["r_open"]), float(f["retract_s"])])
	SnakeTendril.braided_rope = false
	var o := await _swing_facts()
	var bad := _rope_ok(o)
	SnakeTendril.braided_rope = true
	TestLib.check(bool(o["swing"]) and not bad[0] and not bad[1] and not bad[2] and not bad[3], "OLD (the single snake of wave 115, SnakeTendril.braided_rope off): the same four checks fail (braid %d, instances %d)" % [int(o["braid"]), int(o["instances"])])


# --- the zip -----------------------------------------------------------------------------------------------------------------------------

## Stand in front of the facade, read the marker, tap ZIP with a finger, and follow the hero until he stands or hangs.
func _zip_facts() -> Dictionary:
	var out := {"label": "", "mark": {}, "ring_on_anchor": false, "text": "", "zipped": false, "mark_miss": 99.0, "climb_ticks": 0, "end": &"", "floor": false, "rise": 0.0, "step_max": 0.0, "hang": false, "time": 0.0, "said": "", "up_min": 9.0, "haul_ticks": 0}
	await _tp(WALL_SPOT, WALL_YAW, 0.2)
	await _f(40)                                             # the anchor scan runs a few times a second
	out["label"] = fg.button_label(&"snake")
	var mark: Dictionary = fx.zip_mark.duplicate()
	out["mark"] = mark
	var hud := _hud()
	if not mark.is_empty():
		var sp := p.camera_rig.camera.unproject_position(mark["pos"])
		for a: Array in hud[0]:
			if (a[0] as Vector2).distance_to(sp) < 4.0 and Rect2(Vector2.ZERO, fg.vp()).has_point(a[0]):
				out["ring_on_anchor"] = true
	for tx: String in hud[1]:
		if tx.begins_with("ZIP") or tx.begins_with("WALL"):
			out["text"] = tx
	said.clear()
	var from := p.global_position
	await _tap(2, &"snake")
	out["zipped"] = await _until(func() -> bool: return sn.mode == SnakeTraversal.Mode.ZIP, 1.0)
	if not out["zipped"]:
		return out
	if not mark.is_empty():
		out["mark_miss"] = (mark["pos"] as Vector3).distance_to(sn.zip.anchor)
	var prev := p.global_position
	var n := 0
	var free_ticks := 0
	for i in 480:
		await _f(1)
		n += 1
		free_ticks = free_ticks + 1 if sn.mode == SnakeTraversal.Mode.NONE else 0
		out["step_max"] = maxf(float(out["step_max"]), p.global_position.distance_to(prev) if sn.zip.phase == &"haul" else 0.0)
		prev = p.global_position
		if sn.mode == SnakeTraversal.Mode.ZIP and sn.zip.phase == &"haul":
			out["haul_ticks"] = int(out["haul_ticks"]) + 1
			if int(out["haul_ticks"]) > 20:                  # the body has turned into the pose
				out["up_min"] = minf(float(out["up_min"]), sn.pose.basis.y.y)
		if sn.mode == SnakeTraversal.Mode.CLIMB:
			out["climb_ticks"] = int(out["climb_ticks"]) + 1
			if int(out["climb_ticks"]) > 150:                # 2.5 s on the wall with no finger on the screen: he hangs
				out["hang"] = true
				break
		if free_ticks > 12 and p.is_on_floor():              # the body is his own again and it stands
			break
	out["time"] = float(n) / 60.0
	out["end"] = sn.zip.end_reason
	out["floor"] = sn.mode == SnakeTraversal.Mode.NONE and p.is_on_floor()
	out["rise"] = p.global_position.y - from.y
	out["said"] = " | ".join(said)
	return out


func _zip() -> void:
	# 1. the haul over the roof edge
	var f := await _zip_facts()
	var mark: Dictionary = f["mark"]
	TestLib.check(f["label"] == "ZIP" and not mark.is_empty() and bool(f["ring_on_anchor"]) and mark.get("end") == &"roof" and String(f["text"]).begins_with("ZIP"),
			"before the press: the button reads %s, a ring sits on the anchor the zip would take and says '%s'" % [f["label"], f["text"]])
	TestLib.check(bool(f["zipped"]) and float(f["mark_miss"]) < 1.0, "a finger on ZIP: the snakes bite where the marker was (%.2f m off)" % float(f["mark_miss"]))
	TestLib.check(bool(f["zipped"]) and not bool(f["hang"]) and int(f["climb_ticks"]) == 0 and f["end"] == &"hauled" and bool(f["floor"]) and float(f["rise"]) > 20.0,
			"the zip at a wall ends with the hero STANDING on the roof (hauled %.1f m up in %.1f s, end '%s', never hanging)" % [float(f["rise"]), float(f["time"]), f["end"]])
	TestLib.check(float(f["step_max"]) > 0.05 and float(f["step_max"]) < 1.0, "the haul is a ride, not a jump cut: at most %.2f m a tick" % float(f["step_max"]))
	TestLib.check(int(f["haul_ticks"]) > 30 and float(f["up_min"]) > 0.7, "he rides up the facade upright, head up (the body's up axis never under %.2f of vertical)" % float(f["up_min"]))
	SnakePose.haul_upright = false
	var hp := await _zip_facts()
	SnakePose.haul_upright = true
	TestLib.check(int(hp["haul_ticks"]) > 30 and float(hp["up_min"]) < 0.0, "OLD (SnakePose.haul_upright off, the pull pose): he rides up HEAD DOWN (up axis %.2f)" % float(hp["up_min"]))
	# 2. no ledge in reach: a clean drop, and the marker says so before the press
	SnakeZip.haul_max = 3.0
	var d := await _zip_facts()
	SnakeZip.haul_max = 140.0
	var dm: Dictionary = d["mark"]
	TestLib.check(dm.get("end") == &"drop" and String(d["text"]).begins_with("WALL"), "a wall with no ledge in reach is marked as one ('%s')" % d["text"])
	TestLib.check(bool(d["zipped"]) and d["end"] == &"drop" and int(d["climb_ticks"]) == 0 and bool(d["floor"]) and float(d["rise"]) < 1.0 and String(d["said"]).contains("NO LEDGE"),
			"... and the zip there drops him cleanly back to the street and says why (end '%s', %.1f s, said '%s')" % [d["end"], float(d["time"]), d["said"]])
	# 3. the old behaviour
	SnakeZip.wall_end = false
	SnakeFx.cues_on = false
	var o := await _zip_facts()
	SnakeZip.wall_end = true
	SnakeFx.cues_on = true
	TestLib.check(bool(o["zipped"]) and bool(o["hang"]) and not bool(o["floor"]) and (o["mark"] as Dictionary).is_empty() and not bool(o["ring_on_anchor"]),
			"OLD (SnakeZip.wall_end and SnakeFx.cues_on off): the same press leaves him hanging on the wall in CLIMB (%d ticks) and nothing marks the anchor" % int(o["climb_ticks"]))


# --- no anchor ---------------------------------------------------------------------------------------------------------------------------

func _no_anchor_facts() -> Dictionary:
	var out := {"before": "", "after": "", "line": false, "ring": false, "whiff": false, "later": ""}
	await _tp(OPEN_SPOT, 0.0, 0.05)
	await _f(40)
	out["before"] = fg.button_label(&"snake")
	var w0 := sn.whiffs
	await _tap(2, &"snake")
	await _f(6)
	out["whiff"] = sn.whiffs == w0 + 1
	out["after"] = fg.button_label(&"snake")
	var hud := _hud()
	out["line"] = (hud[1] as Array).has("NO ANCHOR IN REACH")
	for a: Array in hud[0]:
		if (a[0] as Vector2).distance_to(fg.button(&"snake")) < 2.0:
			out["ring"] = true
	await _f(100)
	out["later"] = fg.button_label(&"snake")
	return out


func _no_anchor() -> void:
	var f := await _no_anchor_facts()
	TestLib.check(f["before"] == "SNAKE" and bool(f["whiff"]), "far from every building the button reads SNAKE and a finger on it finds nothing to bite")
	TestLib.check(f["after"] == "NO ANCHOR" and bool(f["line"]) and bool(f["ring"]), "... and says so at once: the button reads '%s', a ring flashes round it, NO ANCHOR IN REACH stands at the crosshair" % f["after"])
	TestLib.check(f["later"] == "SNAKE", "the cue is short: 1.8 s later the button reads %s again" % f["later"])
	SnakeFx.cues_on = false
	var o := await _no_anchor_facts()
	SnakeFx.cues_on = true
	TestLib.check(bool(o["whiff"]) and o["after"] == "SNAKE" and not bool(o["line"]) and not bool(o["ring"]), "OLD (SnakeFx.cues_on off): the same press changes nothing on the button or at the crosshair")


# --- flight energy and the rain ----------------------------------------------------------------------------------------------------------

## Take off by fingers, burn the energy down (BOOST first, then the stick), and time the warnings against the moment the wings fail.
func _flight_facts(at: Atmosphere, cruise: bool) -> Dictionary:
	var out := {"flew": false, "warn1_s": -1.0, "warn1_frac": 0.0, "warn2_s": -1.0, "end_s": -1.0, "line1": "", "line2": "", "ring": false, "lens_ground": 0.0, "lens_air": 9.0, "streaks_ground": 0, "streaks_air": 0}
	await _tp(SPOT, -PI * 0.5, 0.6)
	at.set_weather(1.0, 0.9, true)
	at.rainfield.set_quality(1)
	await _f(30)
	out["lens_ground"] = at.post._rain
	out["streaks_ground"] = at.rainfield.streak_count()
	await _tap(1, &"jump")
	if not await _until(func() -> bool: return fg.button(&"fly") != Vector2.INF, 1.0):
		return out
	await _tap(1, &"fly")
	out["flew"] = await _until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 0.5)
	if not out["flew"]:
		return out
	fg.stick(Vector2(0.0, -1.0))
	fg.press(2, &"snake")                                   # BOOST
	var boosting := true
	var w0 := fx.energy_warns
	var t := 0.0
	for i in 1500:
		await _f(1)
		t += 1.0 / 60.0
		if sn.mode != SnakeTraversal.Mode.FLY or sn.flight.phase == &"glide":
			out["end_s"] = t
			break
		if boosting and cruise and sn.energy_fraction() < 0.62:
			fg.up(2)
			boosting = false
		if t > 1.0 and t < 1.1:
			out["lens_air"] = at.post._rain
			out["streaks_air"] = at.rainfield.streak_count()
		if fx.energy_warn >= 1 and float(out["warn1_s"]) < 0.0:
			out["warn1_s"] = t
			out["warn1_frac"] = sn.energy_fraction()
			var hud := _hud()
			out["line1"] = " | ".join(hud[1])
			for a: Array in hud[0]:
				if (a[0] as Vector2).distance_to(fg.button(&"fly")) < 2.0:
					out["ring"] = true
		if fx.energy_warn >= 2 and float(out["warn2_s"]) < 0.0:
			out["warn2_s"] = t
			out["line2"] = " | ".join(_hud()[1])
	out["warns"] = fx.energy_warns - w0
	fg.up_all()
	at.set_weather(0.0, 0.3, true)
	return out


func _energy_and_rain(at: Atmosphere) -> void:
	var f := await _flight_facts(at, true)
	var lead1 := float(f["end_s"]) - float(f["warn1_s"])
	var lead2 := float(f["end_s"]) - float(f["warn2_s"])
	TestLib.check(bool(f["flew"]) and float(f["end_s"]) > 0.0, "JUMP, FLY, BOOST and the stick by fingers: the hero flies until the energy is gone (%.1f s)" % float(f["end_s"]))
	TestLib.check(float(f["warn1_s"]) > 0.0 and lead1 >= 4.0 and lead1 <= 9.0 and float(f["warn1_frac"]) > 0.15 and String(f["line1"]).contains("ENERGY LOW") and bool(f["ring"]),
			"the flight warns BEFORE the energy ends: '%s' and a ring on LAND %.1f s before the wings fail (%.0f %% left)" % [f["line1"], lead1, float(f["warn1_frac"]) * 100.0])
	TestLib.check(float(f["warn2_s"]) > float(f["warn1_s"]) and lead2 >= 1.5 and lead2 <= 3.6 and String(f["line2"]).contains("WINGS FAIL IN"), "then a countdown for the last seconds: '%s' %.1f s before the end" % [f["line2"], lead2])
	var thin := float(int(f["streaks_air"])) / maxf(float(int(f["streaks_ground"])), 1.0)
	TestLib.check(float(f["lens_ground"]) > 0.9 and float(f["lens_air"]) < 0.1 and int(f["streaks_ground"]) > 1000 and thin < 0.5,
			"MED rain in flight: the rain on the lens is gone in the air (%.2f on the ground, %.2f flying) and the streak field thins to %.0f %% (%d -> %d)" % [float(f["lens_ground"]), float(f["lens_air"]), thin * 100.0, int(f["streaks_ground"]), int(f["streaks_air"])])
	SnakeFx.cues_on = false
	Atmosphere.air_clear = false
	var o := await _flight_facts(at, false)
	SnakeFx.cues_on = true
	Atmosphere.air_clear = true
	TestLib.check(bool(o["flew"]) and float(o["end_s"]) > 0.0 and float(o["warn1_s"]) < 0.0 and float(o["warn2_s"]) < 0.0 and int(o["warns"]) == 0,
			"OLD (SnakeFx.cues_on off): the wings fail after %.1f s with no warning at all" % float(o["end_s"]))
	TestLib.check(float(o["lens_air"]) > 0.9 and int(o["streaks_air"]) >= int(o["streaks_ground"]) - 10, "OLD (Atmosphere.air_clear off): the lens rain and every streak stay in the air (%.2f, %d of %d)" % [float(o["lens_air"]), int(o["streaks_air"]), int(o["streaks_ground"])])
