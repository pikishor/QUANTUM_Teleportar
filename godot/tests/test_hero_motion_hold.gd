extends RefCounted
## Hero motion and weapon hold (round 4): the captured gait (Quaternius Universal Animation Library, CC0, retargeted onto the hero: HeroClips) and the weapon hold (grips, aim solver).
##   clips      the baked clip resource is present and sane (idle, ready, walk, jog, sprint, crouch, jump, aim: strides and speeds)
##   gait       the REAL Player on a floor: the clip carries the legs at a walk, a run and a sprint, no foot slides (< 6 cm per cycle, measured from the soles' height), the feet touch
##              down at a plausible cadence, the pelvis never snaps; the IK gait still carries the speeds between the clips and strafing
##   states     jumping shows the air pose and counts a landing; a dead body lets the clip go
##   hold       every weapon class: both hands reach their grips at hip-ready and at every aim pitch; the barrel points at the crosshair (aim solver) while aiming, while moving,
##              at pitches from -0.4 to +0.5 rad; a sprint carries the weapon lowered
## Waits on counters / state, not frame counts; the headless loop is capped at 60 fps like a device.
## Run: tools/test.sh tests/test_hero_motion_hold.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

const SLIDE_MAX := 0.06
const POP_MAX := 0.05
const AIM_TOL := 0.035            ## radians (2 degrees)
const GRIP_TOL := 0.12            ## metres between a wrist and its grip

var e := Env.new()
var p: Player


func run(host: Node) -> void:
	var fps_was := Engine.max_fps
	Engine.max_fps = 60
	DirAccess.remove_absolute("user://save.cfg")
	WeaponDefs.reset_unlocked()
	_data()
	await e.setup(host)
	p = e.p
	var b := p.body
	TestLib.check(b.clips != null and b.rig != null and b.loco != null, "the superhero has the captured-gait layer")
	if b.clips == null:
		Engine.max_fps = fps_was
		await e.teardown()
		return
	await _gaits()
	await _bands()
	await _states()
	await _hold()
	WeaponDefs.reset_unlocked()
	Engine.max_fps = fps_was
	await e.teardown()


func _data() -> void:
	TestLib.check(HeroClips.available(), "assets/anim/hero_clips.res loads")
	var d := HeroClips.data()
	var clips: Dictionary = d.get("clips", {})
	for k: String in ["idle", "ready", "walk", "jog", "sprint", "crouch_idle", "crouch_walk", "jump_start", "jump_loop", "jump_land", "aim_neutral", "aim_up", "aim_down"]:
		TestLib.check(clips.has(k), "clip %s is baked" % k)
	TestLib.check((d.get("bones", []) as Array).size() == 11, "11 bones per frame")
	var ws := HeroClips.speed_of(&"walk")
	var js := HeroClips.speed_of(&"jog")
	var ss := HeroClips.speed_of(&"sprint")
	TestLib.check(ws > 0.7 and ws < 1.8 and js > 4.0 and js < 8.0 and ss > 7.5 and ss < 11.5 and ws < js and js < ss, "gait speeds from the foot contacts: walk %.2f jog %.2f sprint %.2f m/s" % [ws, js, ss])
	for k: String in ["walk", "jog", "sprint"]:
		var c: Dictionary = clips[k]
		TestLib.check(float(c["stride"]) > 0.8 and float(c["stride"]) < 8.0, "%s stride %.2f m per cycle" % [k, float(c["stride"])])
		TestLib.check((c["q"] as PackedFloat32Array).size() == int(c["n"]) * 11 * 4, "%s has a quaternion per bone and frame" % k)
	# the pose of a clip frame is a valid pose (unit quaternions, a hip height of a human)
	var q: Array = []
	for i in 11:
		q.append(Quaternion.IDENTITY)
	var h := HeroClips.sample(&"walk", 0.4, q)
	var unit := true
	for i in 11:
		unit = unit and absf((q[i] as Quaternion).length() - 1.0) < 0.01
	TestLib.check(unit, "a sampled pose has unit quaternions")
	TestLib.check(absf(h.y) < 0.15 and absf(h.x) < 0.1, "the sampled pelvis stays near the standing pelvis (%.2f, %.2f)" % [h.x, h.y])


func _gaits() -> void:
	var res := {}
	for c in [["walk", 0.3, false, "move_forward", 0.85], ["run", 1.0, false, "move_forward", 0.9], ["sprint", 1.0, true, "move_forward", 0.9]]:
		var q := await _gait(c[1], c[2], c[3], 1.2, 2.2)
		res[c[0]] = q
		var w: float = p.body.clips.weight
		TestLib.check(w > float(c[4]), "%s: the captured gait carries the legs (weight %.2f)" % [c[0], w])
		TestLib.check(q.footfalls_seen() >= 3, "%s: %d footfalls measured" % [c[0], q.footfalls_seen()])
		TestLib.check(q.slide_per_cycle() < SLIDE_MAX, "%s: foot slide %.1f cm per cycle (< %.0f cm); %s" % [c[0], q.slide_per_cycle() * 100.0, SLIDE_MAX * 100.0, q.summary()])
		TestLib.check(q.slide_worst < SLIDE_MAX * 1.25, "%s: the worst single contact slides %.1f cm (%s)" % [c[0], q.slide_worst * 100.0, q.worst_info])
		TestLib.check(q.pelvis_pop_max < POP_MAX, "%s: the pelvis moves at most %.1f cm between two frames" % [c[0], q.pelvis_pop_max * 100.0])
		TestLib.check(q.bob() < 0.3, "%s: the pelvis bobs %.1f cm" % [c[0], q.bob() * 100.0])
	var st: Array = [res["walk"].step_length(), res["run"].step_length(), res["sprint"].step_length()]
	TestLib.check(st[0] < st[1] and st[1] < st[2], "the step lengthens with the speed: %.2f < %.2f < %.2f m" % [st[0], st[1], st[2]])
	TestLib.check(res["run"].cadence() > 2.0 and res["run"].cadence() < 6.5, "a run has a plausible cadence (%.2f steps/s)" % res["run"].cadence())
	TestLib.check(res["walk"].cadence() > 1.2 and res["walk"].cadence() < 4.0, "a walk has a plausible cadence (%.2f steps/s)" % res["walk"].cadence())


## Speeds between the captured gaits and the other directions keep the planted-foot IK gait: no slide there either, and the clip fades out instead of mixing legs of two gaits.
func _bands() -> void:
	var q := await _gait(0.6, false, "move_forward", 1.4, 2.0)
	TestLib.check(p.body.clips.weight < 0.6, "between the clips (%.1f m/s) the IK gait carries the legs (clip weight %.2f)" % [p.body.loco.speed, p.body.clips.weight])
	TestLib.check(q.slide_per_cycle() < SLIDE_MAX * 1.3, "mid speed: foot slide %.1f cm per cycle; %s" % [q.slide_per_cycle() * 100.0, q.summary()])
	var qs := await _gait(1.0, false, "move_right", 1.2, 2.0)
	TestLib.check(p.body.clips.weight < 0.5, "strafing is the IK gait's (clip weight %.2f)" % p.body.clips.weight)
	TestLib.check(qs.slide_per_cycle() < SLIDE_MAX * 1.3, "strafe: foot slide %.1f cm per cycle" % (qs.slide_per_cycle() * 100.0))
	var qb := await _gait(1.0, false, "move_back", 1.2, 2.0)
	TestLib.check(qb.slide_per_cycle() < SLIDE_MAX * 1.5, "back-pedal: foot slide %.1f cm per cycle; %s" % [qb.slide_per_cycle() * 100.0, qb.summary()])
	Fixture.release_inputs()


func _states() -> void:
	var b := p.body
	await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, -0.1, 20)
	TestLib.check(b.clips.weight > 0.9, "standing: the captured idle holds the stance (weight %.2f)" % b.clips.weight)
	var land0: int = b.clips.landings
	Input.action_press(&"jump")
	var t := 0
	while p.air_time < 0.3 and t < 120:
		await e.frames(1)
		t += 1
	Input.action_release(&"jump")
	await e.frames(8)
	TestLib.check(float(b.clips.weights.get(&"air", 0.0)) > 0.4, "in the air: the jump pose (weight %.2f)" % float(b.clips.weights.get(&"air", 0.0)))
	t = 0
	while b.clips.landings == land0 and t < 240:
		await e.frames(1)
		t += 1
	TestLib.check(b.clips.landings > land0, "a landing is counted")
	await e.secs(0.8)
	TestLib.check(float(b.clips.weights.get(&"air", 0.0)) < 0.05, "back on the ground the air pose is gone")
	# a crouched stand is the captured crouch (in cover the polish layer poses the body instead: lean, peek)
	Input.action_press(&"crouch")
	t = 0
	while float(b.clips.weights.get(&"crouch_idle", 0.0)) < 0.9 and t < 240:
		await e.frames(1)
		t += 1
	await e.secs(0.4)
	TestLib.check(float(b.clips.weights.get(&"crouch_idle", 0.0)) > 0.85, "crouching: the captured crouch is chosen (weight %.2f)" % float(b.clips.weights.get(&"crouch_idle", 0.0)))
	var cq: Array = []
	for i in 11:
		cq.append(Quaternion.IDENTITY)
	var ch := HeroClips.sample(&"crouch_idle", 0.5, cq)
	TestLib.check(ch.y < -0.3, "and it sits the pelvis %.0f cm below the standing one" % (-ch.y * 100.0))
	Input.action_release(&"crouch")
	await e.secs(0.6)
	TestLib.check(float(b.clips.weights.get(&"crouch_idle", 0.0)) < 0.1, "standing up lets the crouch go")
	# a dead body lets the clip go
	b.set_dead(true)
	await e.secs(0.4)
	TestLib.check(b.rig.clip_w == 0.0, "a dead body is posed by the fall, not the clip (clip weight %.2f)" % b.rig.clip_w)
	b.set_dead(false)
	b.reset_pose()
	await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, -0.1, 20)


func _hold() -> void:
	var b := p.body
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	var picks: Array[StringName] = [&"carbine", &"pistol", &"scatter", &"rail", &"flux", &"rocket", &"revolver", &"akimbo"]
	var worst_aim := 0.0
	var worst_grip := 0.0
	for id in picks:
		if not WeaponDefs.DEFS.has(id):
			continue
		await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, -0.1, 12)
		p.weapon.switch_to(id, true)
		await e.secs(0.4)
		for pitch in [-0.4, 0.0, 0.5]:
			p.camera_rig.reset_view(-PI * 0.5, pitch)
			Input.action_press(&"aim")
			var err := await _settle_aim()
			worst_aim = maxf(worst_aim, err)
			TestLib.check(err < AIM_TOL, "%s, aiming at pitch %.1f: the barrel is %.1f degrees off the crosshair (< %.1f)" % [id, pitch, rad_to_deg(err), rad_to_deg(AIM_TOL)])
			var g := _grip_error()
			worst_grip = maxf(worst_grip, g)
			TestLib.check(g < GRIP_TOL, "%s, aiming at pitch %.1f: the hands sit on the grips (%.1f cm off, left %.1f right %.1f)" % [id, pitch, g * 100.0, _grip(0) * 100.0, _grip(1) * 100.0])
		Input.action_release(&"aim")
	TestLib.check(true, "weapon hold: worst barrel error %.2f degrees, worst grip error %.1f cm" % [rad_to_deg(worst_aim), worst_grip * 100.0])
	# a hip shot raises the weapon to the crosshair too
	await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, -0.1, 12)
	p.weapon.switch_to(&"carbine", true)
	p.camera_rig.reset_view(-PI * 0.5, 0.2)
	Input.action_press(&"fire")
	await e.frames(3)
	Input.action_release(&"fire")
	var hip := await _settle_aim()
	TestLib.check(hip < AIM_TOL * 1.3, "just fired from the hip: the barrel is %.1f degrees off the crosshair" % rad_to_deg(hip))
	# moving while aiming (strafe) keeps the barrel on the target
	await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, -0.1, 12)
	p.weapon.switch_to(&"carbine", true)
	Input.action_press(&"aim")
	Input.action_press(&"move_right", 1.0)
	await e.secs(1.0)
	var worst_move := 0.0
	for i in 40:
		await e.frames(1)
		worst_move = maxf(worst_move, _barrel_error())
	TestLib.check(worst_move < AIM_TOL * 2.0, "strafing while aiming: the barrel stays within %.1f degrees of the crosshair" % rad_to_deg(worst_move))
	Fixture.release_inputs()
	# the solver is what keeps the barrel on the crosshair: without it a raised barrel is several degrees off (the camera pitch reaches the rifle at 60 %)
	await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, 0.5, 12)
	p.weapon.switch_to(&"carbine", true)
	b.aim_solve = false
	Input.action_press(&"aim")
	await e.secs(0.8)
	var off_err := _barrel_error()
	b.aim_solve = true
	await e.secs(0.8)
	var on_err := _barrel_error()
	TestLib.check(off_err > AIM_TOL * 1.5 and on_err < AIM_TOL, "aim solver: %.1f degrees off without it, %.1f with it (looking up 0.5 rad)" % [rad_to_deg(off_err), rad_to_deg(on_err)])
	Input.action_release(&"aim")
	# a sprint carries the weapon lowered: the barrel points well below the horizon
	await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, -0.05, 12)
	p.weapon.switch_to(&"carbine", true)
	Input.action_press(&"move_forward", 1.0)
	Input.action_press(&"sprint")
	await e.secs(1.6)
	var fwd := -b.muzzle.global_basis.z
	TestLib.check(fwd.y < -0.2, "sprinting carries the weapon lowered (barrel slope %.2f)" % fwd.y)
	TestLib.check(b.rig.aim_trim.length() < 0.05, "and the aim solver lets go of it (trim %.2f)" % b.rig.aim_trim.length())
	Fixture.release_inputs()


## Wait until the barrel is on the crosshair (or 2 s of game time have passed); returns the remaining angle (radians).
func _settle_aim() -> float:
	var err := 9.0
	var t := 0
	while t < 120:
		await e.frames(1)
		t += 1
		err = _barrel_error()
		if err < AIM_TOL * 0.5 and t > 18:
			break
	return err


## Angle between the barrel and the direction from the muzzle to what the crosshair sees (the camera's ray).
func _barrel_error() -> float:
	var b := p.body
	var aim := p.get_aim()
	var want: Vector3 = (aim["hit"] as Vector3) - b.muzzle.global_position
	if want.length() < 5.0:
		want = want.normalized().lerp(aim["dir"], 1.0 - want.length() / 5.0)
	var fwd := -b.muzzle.global_basis.z
	return fwd.normalized().angle_to(want.normalized())


func _grip(k: int) -> float:
	var rig := p.body.rig
	var off: Vector3 = rig.grip_off_l if k == 0 else rig.grip_off_r
	var target: Vector3 = rig.bone_move(CharacterRig.RIFLE) * ((rig._wrist_rest[k] as Vector3) + off)
	return (rig.wrist_position(k) - target).length()


func _grip_error() -> float:
	var left := _grip(0)
	var right := _grip(1)
	return maxf(left, right)


## Run at a stick strength for `secs` of game time after `settle`, measured from the soles (the clip gait reads contacts from the soles' height).
func _gait(stick: float, sprint: bool, action: String, settle: float, secs: float) -> LocoQA:
	await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, -0.1, 12)
	Input.action_press(StringName(action), stick)
	if sprint:
		Input.action_press(&"sprint")
	var lc := p.body.loco
	var q := LocoQA.new(p.body.rig, lc)
	q.clips = p.body.clips
	var t := 0.0
	var began := false
	var tm := 0.0
	while tm < secs:
		await e.frames(1)
		var dt := 1.0 / 60.0
		t += dt
		if t < settle:
			continue
		if not began:
			began = true
			q.begin()
		tm += dt
		q.sample(dt, lc.speed > 0.45, 0.0)
	q.end()
	return q
