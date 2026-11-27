extends RefCounted
## WAVE 128 (plan line 128, agent w128-anim): HUMAN AND CREATURE ANIMATION, driven by REAL FINGERS on the real main scene (InputEventScreenTouch / Drag through Input.parse_input_event,
## Game.force_touch, the phone-only layers on). The set-up places the hero and parks the vehicle by code; every action is a finger on the touch HUD.
##   seats   a finger on ENTER boards a helicopter, a glider, a heavy tank and a quad: the hero is SEEN in the seat (before: hidden in every vehicle), the pelvis is on the seat, the head is
##           under the canopy (cockpit) or out of the hatch (tank), both wrists are on the controls, the feet stay on the pedals while the stick flies it (no sliding), the stick under the
##           thumb tilts the cyclic in the hand, the glass is see-through while he is aboard; EXIT by finger: on foot again, the dark glass and the weapon are back
##   casts   a finger on QUANTUM (the teleport marker) plays a cast: the left hand winds up to the chest, then is thrown at the aim, then goes back to the weapon; every verb has its gesture
##   snake   a crawling snake rears back into an S and strikes as it reaches its prey (before: it slid in straight)
## W128_OLD=1 = the code before this wave (the checks marked [old fails] fail). ANIM_PARTS=seats,casts,snake (default all).
## Run: tools/test.sh tests/test_anim_w128.gd
const Fingers := preload("res://tests/w116_fingers.gd")
const TIMEOUT_SECONDS := 140
var host: Node
var p: Player
var vm: VehicleManager
var fg: Fingers


func _f(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame


## After everything of the frame ran (the seated body is placed at the end of the frame, after the vehicles' visual sync).
signal _flushed


func _late() -> void:
	await host.get_tree().process_frame
	_flushed.emit.call_deferred()                          # the deferred queue is flushed after every node's _process of the frame
	await _flushed


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _f(3)
	fg.up(6)
	await _f(3)
	return true


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	var old := OS.get_environment("W128_OLD") == "1"
	SeatPose.on = not old
	SeatPose._cache.clear()
	HeroCast.on = not old
	SnakeSwarm.strike_on = not old
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
	var parts := OS.get_environment("ANIM_PARTS")
	if parts == "" or parts.contains("seats"):
		await _seats()
	if parts == "" or parts.contains("casts"):
		await _casts()
	if parts == "" or parts.contains("snake"):
		await _snake()
	fg.up_all()
	SeatPose.on = true
	HeroCast.on = true
	SnakeSwarm.strike_on = true
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


# --- seats ----------------------------------------------------------------------------------------------------------------------------------

## Park `kind` at `at`, put the hero beside it, and board it with a finger on ENTER. Returns the vehicle or null.
func _board(kind: StringName, at: Vector3) -> Vehicle:
	vm._release_farthest(at)
	vm._release_farthest(at)
	var v := vm.spawn_parked(kind, at, 0.0)
	if v == null:
		TestLib.check(false, "%s parks for the check" % kind)
		return null
	await _f(4)
	var side := float(v.spec["wid"]) * 0.5 + 1.2
	if VehicleSpecs.cls_of(kind) == &"plane":
		side = minf(side, 3.0)
	p.teleport_to(v.global_position + v.right() * side + Vector3(0.0, 0.3, 0.0))
	await _f(20)
	var ok := false
	for i in 40:
		if fg.button_label(&"interact") == "ENTER":
			ok = true
			break
		fg.stick(Vector2(-1.0, 0.0))                        # a step toward it (the hero faces the camera's way)
		await _f(2)
	fg.stick(Vector2.ZERO)
	await _f(2)
	if ok:
		await _tap(&"interact")
		await _f(30)
	TestLib.check(p.vehicle == v, "a finger on ENTER boards the %s" % VehicleSpecs.name_of(kind))
	return v if p.vehicle == v else null


func _seats() -> void:
	var base := Airport.to_world(Vector3(1250.0, 0.0, -640.0))
	var spots := {&"h_scout": base, &"p_glider": base + Vector3(0.0, 0.0, 30.0), &"t_heavy": base + Vector3(30.0, 0.0, 0.0), &"quad": base + Vector3(30.0, 0.0, 30.0)}
	for kind: StringName in spots:
		var v := await _board(kind, spots[kind])
		if v == null:
			continue
		var b := p.body
		var rig := b.rig
		var s: Dictionary = b.seat_info
		TestLib.check(b.visible and not s.is_empty(), "%s: the hero is seen in the seat [old fails] (visible %s, seat %s)" % [kind, b.visible, s.get("style", "none")])
		if s.is_empty():
			await _tap(&"interact")
			await _f(10)
			continue
		var node: Node3D = v.visual.model if String(s["node"]) == "" else v.visual.model.get_node(String(s["node"]))
		var inv := node.global_transform.affine_inverse()
		var mx := rig.model.global_transform
		var hip := inv * (mx * rig.hips_now())
		var head := inv * (mx * rig.head_now())
		TestLib.check(Vector2(hip.x - (s["hip"] as Vector3).x, hip.z - (s["hip"] as Vector3).z).length() < 0.1 and absf(hip.y - (s["hip"] as Vector3).y) < 0.1,
			"%s: the pelvis sits on the seat (%.2f m off)" % [kind, hip.distance_to(s["hip"])])
		if s["style"] == &"cockpit":
			TestLib.check(head.y + 0.22 < float(s["top"]) + 0.03, "%s: the head stays under the canopy (skull top %.2f, glass top %.2f)" % [kind, head.y + 0.22, float(s["top"])])
		elif s["style"] == &"hatch":
			TestLib.check(head.y > float(s["top"]) + 0.3 and hip.y < float(s["top"]), "%s: the commander stands in the hatch: waist under the roof, head %.2f m out" % [kind, head.y - float(s["top"])])
		var hands: Array = s["hands"]
		var e0 := (mx * rig.wrist_position(0)).distance_to(node.global_transform * (hands[0] as Vector3))
		var e1 := (mx * rig.wrist_position(1)).distance_to(node.global_transform * (hands[1] as Vector3))
		TestLib.check(e0 < 0.09 and e1 < 0.09, "%s: both hands on the %s (%.3f / %.3f m)" % [kind, s["controls"], e0, e1])
		if s["style"] == &"cockpit":
			TestLib.check(SeatPose.canopy_material() in [v.visual.body.get_surface_override_material(1), v.visual.body.get_surface_override_material(0), v.visual.body.get_surface_override_material(2)],
				"%s: the canopy is see-through while he is aboard" % kind)
		# the stick under the thumb: the right hand follows; the feet stay on the pedals
		await _late()
		inv = node.global_transform.affine_inverse()
		mx = rig.model.global_transform
		var w0 := inv * (mx * rig.wrist_position(1))
		var f0 := inv * (mx * rig.sole_now(0))
		var drift := 0.0
		fg.stick(Vector2(1.0, 0.0))
		for i in 30:
			await _late()
			var inv2 := node.global_transform.affine_inverse()
			drift = maxf(drift, (inv2 * (rig.model.global_transform * rig.sole_now(0))).distance_to(f0))
			if OS.get_environment("ANIM_DBG") == "1" and i % 6 == 0:
				print("DBG %s ax %.2f steer %.2f hand %s sole %s hip %s seat %.2f" % [kind, Input.get_axis(&"move_left", &"move_right"), v.steer_in, inv2 * (rig.model.global_transform * rig.wrist_position(1)), inv2 * (rig.model.global_transform * rig.sole_now(0)), inv2 * (rig.model.global_transform * rig.hips_now()), rig.seat])
		var w1 := node.global_transform.affine_inverse() * (rig.model.global_transform * rig.wrist_position(1))
		fg.stick(Vector2.ZERO)
		await _f(4)
		if s["controls"] != &"rim":
			TestLib.check(w1.distance_to(w0) > 0.025, "%s: the stick under the thumb moves the hand on the %s (%.3f m)" % [kind, s["controls"], w1.distance_to(w0)])
		TestLib.check(drift < 0.05, "%s: the feet stay on the pedals / pegs while it moves (%.3f m)" % [kind, drift])
		# EXIT by finger
		await _tap(&"interact")
		await _f(30)
		TestLib.check(p.vehicle == null and b.visible and rig.seat == 0.0, "%s: a finger on EXIT: on foot, standing (seat %.2f)" % [kind, rig.seat])
		if s["style"] == &"cockpit":
			var still := false
			for si in v.visual.body.mesh.get_surface_count():
				still = still or v.visual.body.get_surface_override_material(si) == SeatPose.canopy_material()
			TestLib.check(not still, "%s: the dark glass is back after he left" % kind)
		if VehicleSpecs.cls_of(kind) != &"tank":           # (a released tank left TankCrews holding a freed vehicle: tank_crews.gd casts before it checks)
			vm._release(v)
		await _f(4)


# --- casts ----------------------------------------------------------------------------------------------------------------------------------

## The left wrist in the hero's model frame.
func _lw() -> Vector3:
	return p.body.rig.wrist_position(0)


func _casts() -> void:
	p.teleport_to(Airport.to_world(Vector3(1250.0, 0.0, -560.0)) + Vector3(0.0, 0.3, 0.0))
	await _f(40)
	p.energy = p.max_energy if "max_energy" in p else 100.0
	var rig := p.body.rig
	var rest := _lw()
	var c0 := p.body.cast.casts
	var ok := await _tap(&"ability")                         # a tap opens the ability ring (it stays), a tap on a disc casts it
	var wh = fg.tc.wheel
	TestLib.check(ok and wh.is_open, "a finger on ABILITY opens the ring of verbs")
	var pick := -1
	if wh.is_open:
		for i in wh.items.size():
			if StringName((wh.items[i] as Dictionary)["id"]) in [&"superpose", &"shield", &"slip"] and pick < 0:
				pick = i
		pick = maxi(pick, 0)
		print("W128 cast pick %s" % (wh.items[pick] as Dictionary)["id"])
		fg.down(6, wh.item_centre(pick))
		await _f(2)
		fg.up(6)
	var closest := INF
	var farthest := 0.0
	var t_far := -1.0
	var t_close := -1.0
	for i in 50:
		await _f(1)
		var w := _lw()
		var fwd := w.distance_to(rest)
		if fwd > farthest:
			farthest = fwd
			t_far = float(i)
		var chest := w.distance_to(Vector3(0.0, 1.25, -0.15))
		if chest < closest:
			closest = chest
			t_close = float(i)
	TestLib.check(p.body.cast.casts > c0, "a finger on a verb of the ring starts a cast gesture [old fails] (%d, %s)" % [p.body.cast.casts - c0, p.body.cast.kind])
	TestLib.check(farthest > 0.3, "the release throws the left hand out, off the weapon [old fails] (%.2f m)" % farthest)
	TestLib.check(t_close >= 0.0 and t_close < t_far, "the wind-up (hand to the chest) comes before the release (frames %d / %d)" % [t_close, t_far])
	for i in 90:                                             # w128-critic: wait for the gesture to end by its own clock (a loaded runner steps many physics ticks per frame), then a few frames more
		if p.body.cast.phase == &"":
			break
		await _f(1)
	await _f(6)
	TestLib.check(_lw().distance_to(rest) < 0.08 and rig.hand_w.x < 0.05, "the hand is back on the weapon after the cast (%.3f m)" % _lw().distance_to(rest))
	# every verb has its own gesture (the game's signals; the gestures differ)
	var outs := {}
	for id: StringName in HeroCast.KINDS:
		p.body.cast.start(id)
		var best := _lw()
		for i in 90:                                         # w128-critic: the pose at the height of the gesture (its own clock: HIT to HOLD), not after a fixed frame count (flaky under load)
			await _f(1)
			var c := p.body.cast
			if c.t >= HeroCast.HIT and c.t <= HeroCast.HOLD:
				best = _lw()
				break
			if c.phase == &"" and i > 2:
				best = _lw()
				break
		outs[id] = best
		for i in 90:
			if p.body.cast.phase == &"":
				break
			await _f(1)
		await _f(4)
	var distinct := {}
	for id: StringName in outs:
		distinct["%.1f,%.1f,%.1f" % [outs[id].x, outs[id].y, outs[id].z]] = true
		TestLib.check((outs[id] as Vector3).distance_to(rest) > 0.15, "%s: the left hand leaves the weapon in its gesture (%.2f m) [old fails]" % [id, (outs[id] as Vector3).distance_to(rest)])
	TestLib.check(distinct.size() >= 4, "the verbs have different gestures (%d poses for %d verbs) [old fails]" % [distinct.size(), outs.size()])


# --- snake ----------------------------------------------------------------------------------------------------------------------------------

func _snake() -> void:
	var sw := SnakeSwarm.get_swarm(host)
	var from := p.global_position + Vector3(4.0, 0.0, 0.0)
	from.y = sw.ground_y(from, p.global_position.y)
	var to := from + Vector3(0.0, 0.0, -7.0)
	var b := sw.spawn(&"crawl", from, {"len": 1.6, "speed": 4.0, "target_pos": to, "mode": &"hunt"})
	TestLib.check(b != null, "a crawling snake spawns")
	if b == null:
		return
	b.target_pos = to
	b.mode = &"hunt"
	var back := 0.0
	var lunge := -INF
	for i in 120:
		await _f(1)
		if b.dead or b.arrived or b.pts.size() < 2:
			break
		var head: Vector3 = b.pts[b.pts.size() - 1]
		var drawn := (b.pos - head).dot(b.heading)
		back = maxf(back, drawn)
		lunge = maxf(lunge, -drawn)
	TestLib.check(back > 0.12, "the snake rears its head back into an S before it strikes [old fails] (%.2f m)" % back)
	TestLib.check(lunge > 0.02, "and lunges at the prey (%.2f m)" % lunge)
