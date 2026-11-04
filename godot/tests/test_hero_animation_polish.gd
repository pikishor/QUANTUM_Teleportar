extends RefCounted
## Hero animation polish in the REAL game scene (HeroAnimPolish + HeroAnimTuning on the live superhero): pose assertions on the rig and skeleton for breathing, start / stop / turn
## blends, landing impact, reload and swap per weapon class, cover and peek, takedown, slam, glide, wall-run, vault and mantle hand placement, head look-at / blink / saccades, and
## foot IK on a slope. The polish is stepped directly with synthetic state (no frame counts); margins are wide.
## Run: tools/test.sh tests/test_hero_animation_polish.gd

var _p: Player
var _b: PlayerBody
var _pol: HeroAnimPolish


## One polish step with the inputs given (the rig fields it adds to are reset first, like a Locomotion frame does).
func _step(n: int, grounded := true, wid: StringName = &"carbine", rk := -1.0, swap := false, target: Variant = null, dt := 0.05) -> void:
	for i in n:
		_b.rig.extra_torso = Vector3.ZERO
		_pol.update(dt, _p, _b, _b.loco, grounded, wid, rk, swap, target)


func _torso_angle() -> float:
	_b.rig.apply()
	var sk := _b.rig.skeleton
	var i := sk.find_bone("Torso")
	return (sk.get_bone_rest(i).basis.inverse() * sk.get_bone_pose(i).basis).get_rotation_quaternion().get_angle()


func run(host: Node) -> void:
	TestLib.check(HeroCharacter.available(&"male"), "the hero kit is imported")
	if not HeroCharacter.available(&"male"):
		return
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	_p = Game.player
	var prog := Game.progress as Progress
	if _p == null or _p.body == null or prog == null:
		TestLib.check(false, "the real game has a player body and progress")
		return
	prog.autosave_enabled = false
	prog.hero.reset()
	Game.state = &"play"
	for n in host.find_children("*", "Stability", true, false):
		n.set_process(false)
	_b = _p.body
	for i in 80:
		if _b.rig != null and _b.polish != null:
			break
		await TestLib.frames(host, 1)
	TestLib.check(_b.rig != null and _b.polish != null and _b.loco != null, "the live hero owns the polish layer")
	if _b.polish == null:
		return
	_pol = _b.polish
	var T := HeroAnimTuning
	TestLib.check(T.class_of(&"scatter") == "shotgun" and T.class_of(&"flux") == "heavy" and T.class_of(&"carbine") == "rifle", "weapon classes come from the table")

	# --- the live loop runs the polish (state changes with real frames)
	var t0 := _pol._t
	await TestLib.frames(host, 6)
	TestLib.check(_pol._t > t0, "the polish runs in the live frame")
	_pol.reset()
	_b.loco.speed = 0.0
	_b.loco.acc = Vector2.ZERO
	_b.loco.yaw_rate = 0.0

	# --- breathing idle: the pelvis and chest move over a few seconds at rest
	var lo := 9.0
	var hi := -9.0
	var tlo := 9.0
	var thi := -9.0
	for i in 80:
		_step(1)
		lo = minf(lo, _b.rig.pose_hips.y)
		hi = maxf(hi, _b.rig.pose_hips.y)
		tlo = minf(tlo, _b.rig.extra_torso.x)
		thi = maxf(thi, _b.rig.extra_torso.x)
	TestLib.check(hi - lo > 0.002 and thi - tlo > 0.008, "breathing idle moves the pelvis (%.4f) and chest (%.4f)" % [hi - lo, thi - tlo])
	TestLib.check(_pol.state == &"idle", "idle state")

	# --- blink and saccades
	_pol.reset()
	var blink_max := 0.0
	var gz_lo := Vector2(9, 9)
	var gz_hi := Vector2(-9, -9)
	for i in 160:
		_step(1)
		blink_max = maxf(blink_max, _pol.blink)
		gz_lo = gz_lo.min(_pol.gaze)
		gz_hi = gz_hi.max(_pol.gaze)
	TestLib.check(blink_max > 0.6, "the hero blinks within 8 s (%.2f)" % blink_max)
	TestLib.check(gz_hi.x - gz_lo.x > 0.01 and gz_hi.x - gz_lo.x < 0.2, "eye saccades are small gaze jumps (%.3f)" % (gz_hi.x - gz_lo.x))

	# --- start, stop, turn in place
	_pol.reset()
	_b.loco.acc = Vector2(0.0, 30.0)
	_step(30)
	var start_x := _b.rig.extra_torso.x
	_b.loco.acc = Vector2(0.0, -30.0)
	_step(30)
	var stop_x := _b.rig.extra_torso.x
	_b.loco.acc = Vector2.ZERO
	TestLib.check(start_x < -0.02 and stop_x > 0.02, "leans into a start (%.3f) and rocks back on a stop (%.3f)" % [start_x, stop_x])
	_pol.reset()
	_b.loco.yaw_rate = 4.0
	_b.rig.extra_torso = Vector3.ZERO
	for i in 30:
		_b.rig.extra_torso = Vector3.ZERO
		_pol.update(0.05, _p, _b, _b.loco, true, &"carbine", -1.0, false, null)
	var turn_y := _b.rig.extra_torso.y
	_b.loco.yaw_rate = 0.0
	TestLib.check(absf(turn_y) > 0.05, "turning in place twists the torso (%.3f)" % turn_y)
	_pol.reset()
	_step(40)

	# --- landing impact
	var l0 := _pol.landings
	_p.velocity.y = -14.0
	_step(8, false)
	_p.velocity.y = 0.0
	_b.rig.extra_torso = Vector3.ZERO
	_pol.update(0.05, _p, _b, _b.loco, true, &"carbine", -1.0, false, null)
	TestLib.check(_pol.landings == l0 + 1 and _b.rig.extra_torso.x > 0.02 and _b.rig.pose_hips.y < -0.003, "a hard landing dips the pelvis and pitches the chest (%.3f, %.3f)" % [_b.rig.extra_torso.x, _b.rig.pose_hips.y])

	# --- reload and swap per weapon class
	var mids := {}
	for wid: StringName in [&"carbine", &"scatter", &"flux"]:
		_pol.reset()
		_step(20, true, wid, 0.5, false)
		mids[wid] = _b.rig.extra_torso.x
		TestLib.check(_pol.state == &"reload", "%s: reload state" % wid)
	TestLib.check(mids[&"flux"] > mids[&"scatter"] and mids[&"scatter"] > mids[&"carbine"] and mids[&"carbine"] > 0.03, "the reload bend grows by class: rifle %.3f shotgun %.3f heavy %.3f" % [mids[&"carbine"], mids[&"scatter"], mids[&"flux"]])
	_pol.reset()
	_step(20, true, &"flux", 0.5, true)
	TestLib.check(_pol.state == &"swap" and _b.rig.extra_torso.x > 0.05, "a weapon swap dips the torso (%.3f)" % _b.rig.extra_torso.x)
	_pol.reset()
	_step(40)
	var calm_angle := _torso_angle()
	_step(20, true, &"flux", 0.5, false)
	TestLib.check(_torso_angle() > calm_angle + 0.05, "the Torso bone itself bends in a heavy reload (%.3f -> %.3f)" % [calm_angle, _torso_angle()])

	# --- cover, peek, takedown
	var c := _p.cover
	TestLib.check(c != null, "the player has a cover state")
	if c != null:
		var save := [c.in_cover, c.peeking, c.height, c.cover_normal, c.strike]
		_pol.reset()
		c.in_cover = true
		c.height = PlayerCover.CROUCH_HEIGHT
		c.cover_normal = _b.global_basis.x
		_step(50)
		TestLib.check(_pol.state == &"cover" and _b.rig.extra_torso.x > 0.05 and _b.rig.pose_hips.y < -0.03, "cover: crouch and lean into the wall (%.3f, %.3f)" % [_b.rig.extra_torso.x, _b.rig.pose_hips.y])
		c.peeking = true
		_step(50)
		TestLib.check(_pol.state == &"peek" and absf(_b.rig.extra_torso.z) > 0.08, "peek: the torso rolls out (%.3f)" % _b.rig.extra_torso.z)
		c.in_cover = false
		c.peeking = false
		c.height = PlayerCover.STAND_HEIGHT
		_step(50)
		TestLib.check(_b.rig.pose_hips.y > -0.02 and absf(_b.rig.extra_torso.z) < 0.03, "leaving cover stands up again (%.3f)" % _b.rig.pose_hips.y)
		c.strike = 1.0
		_step(10)
		TestLib.check(_pol.state == &"takedown" and _b.rig.extra_torso.x > 0.2 and absf(_b.rig.extra_torso.y) > 0.2, "takedown pose lunges and twists (%.3f)" % _b.rig.extra_torso.x)
		c.in_cover = save[0]
		c.peeking = save[1]
		c.height = save[2]
		c.cover_normal = save[3]
		c.strike = save[4]

	# --- slam, glide, wall-run
	var v = _p.verbs
	TestLib.check(v != null, "the player has hero verbs")
	if v != null:
		var vs := [v.slamming, v.wall_running, v.wall_side]
		_pol.reset()
		v.slamming = true
		_step(10)
		TestLib.check(_pol.state == &"slam" and _b.rig.extra_torso.x > 0.25 and _b.rig.pose_hips.y < -0.05, "slam: chest down, pelvis low (%.3f)" % _b.rig.extra_torso.x)
		v.slamming = false
		_p.gliding = true
		_step(40, false)
		TestLib.check(_pol.state == &"glide" and _b.rig.extra_torso.x < -0.15, "glide: body stretched flat (%.3f)" % _b.rig.extra_torso.x)
		_p.gliding = false
		v.wall_running = true
		v.wall_side = 1.0
		_step(40, false)
		TestLib.check(_pol.state == &"wall" and _b.rig.extra_torso.z > 0.07, "wall-run: rolled toward the wall (%.3f)" % _b.rig.extra_torso.z)
		v.slamming = vs[0]
		v.wall_running = vs[1]
		v.wall_side = vs[2]

	# --- vault and mantle: hands placed on the obstacle
	var tr = _p.traversal
	if tr != null:
		_pol.reset()
		_step(30)
		_b.rig.apply()
		var w_idle: Vector3 = _b.rig.wrist_position(0)
		tr.kind = Traversal.Kind.VAULT
		tr._dur = 0.4
		tr._t = 0.2
		_step(40)
		_b.rig.apply()
		var w_vault: Vector3 = _b.rig.wrist_position(0)
		TestLib.check(_pol.state == &"vault" and _b.rig.hand_w.x > 0.5, "vault state with the hands placed (%.2f)" % _b.rig.hand_w.x)
		TestLib.check(w_vault.distance_to(w_idle) > 0.08, "the hand really moves onto the obstacle (%.2f m)" % w_vault.distance_to(w_idle))
		tr.kind = Traversal.Kind.MANTLE
		_step(40)
		TestLib.check(_pol.state == &"mantle", "mantle state")
		tr.kind = Traversal.Kind.NONE
		tr._t = 0.0
		_step(80)
		TestLib.check(_b.rig.hand_w.x < 0.05, "the hands come back to the weapon")

	# --- head look-at toward a target
	_pol.reset()
	var tgt := Node3D.new()
	host.add_child(tgt)
	var right := _b.global_basis.x
	var fwd := -_b.global_basis.z
	tgt.global_position = _b.global_position + right * 4.0 + fwd * 4.0
	_b.rig.head_look = Vector2.ZERO
	for i in 30:
		_b.rig.head_look = Vector2.ZERO
		_b.rig.extra_torso = Vector3.ZERO
		_pol.update(0.05, _p, _b, _b.loco, true, &"carbine", -1.0, false, tgt)
	var look_x := _b.rig.head_look.x
	TestLib.check(absf(look_x) > 0.3, "the head turns toward the target (%.2f rad)" % look_x)
	tgt.queue_free()

	# --- foot IK on a slope
	var plate := StaticBody3D.new()
	plate.collision_layer = Game.L_WORLD
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(30.0, 1.0, 30.0)
	cs.shape = bx
	plate.add_child(cs)
	host.add_child(plate)
	var ang := 0.35
	var ax := _b.global_basis.x.normalized()
	var origin := Vector3(0.0, 600.0, 0.0)
	plate.global_transform = Transform3D(Basis(ax, ang), origin - Basis(ax, ang) * Vector3(0.0, 0.5, 0.0))
	var back_pos := _p.global_position
	_p.global_position = origin + Vector3(0.0, 1.2, 0.0)
	_p.velocity = Vector3.ZERO
	for i in 120:
		await TestLib.frames(host, 1)
		if _p.is_on_floor():
			break
	if _p.is_on_floor():
		_pol.reset()
		_b.loco.speed = 0.0
		for i in 60:
			_b.rig.extra_torso = Vector3.ZERO
			_pol.update(0.05, _p, _b, _b.loco, true, &"carbine", -1.0, false, null)
		var pitch_before := _b.rig.pitch_l
		TestLib.check(_pol.slope > 0.15, "the ground slope under the hero is read (%.2f rad)" % _pol.slope)
		TestLib.check(absf(pitch_before) > 0.1, "the soles pitch with the slope (%.2f)" % pitch_before)
	else:
		TestLib.check(false, "the hero stands on the test slope")
	plate.queue_free()
	_p.global_position = back_pos
	_p.velocity = Vector3.ZERO
