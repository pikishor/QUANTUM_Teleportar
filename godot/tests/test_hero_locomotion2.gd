extends RefCounted
## Hero locomotion QA bot (wave 83): the REAL Player on a floor, driven by input actions at several stick strengths and gaits, measured by LocoQA from the posed skeleton.
##   foot slide      metres a sole in contact moves over the ground per gait cycle, at walk, jog, run, sprint, strafe, back-pedal, turning in place and uphill (under a few cm)
##   stride          the step length grows with the speed (no foot sliding by a fixed cycle) and stays inside what the legs reach
##   pelvis          the pelvis never snaps from one frame to the next (blend between speeds, stops and starts), the bob stays a few centimetres
##   lean, shoulders the torso leans into a run, more in a sprint; the shoulders turn against the pelvis
##   camera          the camera bob follows the gait phase (one continuous phase), and is gone again when the hero stands
## The numbers of the gait are in scripts/characters/hero_anim_tuning.gd; the frame sequences are made by tools/loco_view.sh.
## Run: tools/test.sh tests/test_hero_locomotion2.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

const SLIDE_MAX := 0.06            ## metres per gait cycle
const POP_MAX := 0.05              ## metres of hip height between two frames

var e := Env.new()
var p: Player


func run(host: Node) -> void:
	var fps_was := Engine.max_fps
	Engine.max_fps = 60                      # the headless loop otherwise renders as fast as it can (sub-millisecond frames): the gait needs frames like a device's
	await e.setup(host)
	p = e.p
	TestLib.check(p.body.loco != null and p.body.rig != null and p.body.polish != null, "the superhero has a Locomotion and a polish layer")
	TestLib.check(HeroAnimTuning.f("gait_cyc_max") > 0.0 and p.body.loco.g_comp == HeroAnimTuning.f("stance_comp"), "the hero's gait numbers come from hero_anim_tuning.gd")
	var res := {}
	for c in [["walk", 0.3, false, "move_forward"], ["jog", 0.6, false, "move_forward"], ["run", 1.0, false, "move_forward"], ["sprint", 1.0, true, "move_forward"],
			["strafe", 1.0, false, "move_right"], ["back", 1.0, false, "move_back"]]:
		var q := await _gait(c[1], c[2], c[3], 1.0, 2.0)
		res[c[0]] = q
		TestLib.check(q.footfalls_seen() >= 3, "%s: %d footfalls measured" % [c[0], q.footfalls_seen()])
		TestLib.check(q.slide_per_cycle() < SLIDE_MAX, "%s: foot slide %.1f cm per cycle (< %.0f cm); %s" % [c[0], q.slide_per_cycle() * 100.0, SLIDE_MAX * 100.0, q.summary()])
		TestLib.check(q.slide_worst < SLIDE_MAX * 0.75, "%s: worst single contact slides %.1f cm" % [c[0], q.slide_worst * 100.0])
		TestLib.check(q.pelvis_pop_max < POP_MAX, "%s: the pelvis moves at most %.1f cm between two frames (no snap)" % [c[0], q.pelvis_pop_max * 100.0])
		TestLib.check(q.bob() < 0.16, "%s: the pelvis bobs %.1f cm (< 16 cm)" % [c[0], q.bob() * 100.0])
		TestLib.check(q.knee_max < 1.75, "%s: the knee bends %.2f rad at most" % [c[0], q.knee_max])
	# stride matched to speed: the step grows with the speed, and a step is never longer than a human leg can span in a run
	var st: Array = [res["walk"].step_length(), res["jog"].step_length(), res["run"].step_length(), res["sprint"].step_length()]
	TestLib.check(st[0] < st[1] - 0.08 and st[1] < st[2] - 0.1 and st[2] < st[3] - 0.05, "the step lengthens with the speed: %.2f < %.2f < %.2f < %.2f m" % [st[0], st[1], st[2], st[3]])
	TestLib.check(st[3] < 3.0 and st[0] > 0.45, "the steps stay human: walk %.2f m, sprint %.2f m" % [st[0], st[3]])
	var cad: float = res["run"].cadence()
	TestLib.check(cad > 2.2 and cad < 4.4, "a run has a plausible cadence (%.2f steps/s)" % cad)
	# lean and shoulders
	TestLib.check(res["run"].torso_hi < -0.1, "the torso leans into a run (pitch %.2f rad)" % res["run"].torso_hi)
	TestLib.check(res["sprint"].torso_hi < res["run"].torso_hi - 0.05, "and more in a sprint (%.2f vs %.2f rad)" % [res["sprint"].torso_hi, res["run"].torso_hi])
	await _turn()
	await _stop_and_start()
	await _slope()
	await _camera_bob()
	Engine.max_fps = fps_was
	await e.teardown()


func _gait(stick: float, sprint: bool, action: String, settle: float, secs: float) -> LocoQA:
	await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, -0.1, 12)
	Input.action_press(StringName(action), stick)
	if sprint:
		Input.action_press(&"sprint")
	return await _measure(settle, secs, 0.0)


## Settle, then measure for `secs` of game time, counted in physics ticks (1/60 s each; the headless runner renders as fast as it can, so frame deltas mean nothing).
func _measure(settle: float, secs: float, look_rate: float, ground := Callable()) -> LocoQA:
	var lc := p.body.loco
	var q := LocoQA.new(p.body.rig, lc)
	q.ground = ground
	var t := 0.0
	var began := false
	var tm := 0.0
	while tm < secs:
		await e.frames(1)
		var dt := 1.0 / 60.0
		t += dt
		if look_rate != 0.0:
			p.camera_rig.add_look(look_rate * dt, 0.0)
		if t < settle:
			continue
		if not began:
			began = true
			q.begin()
		tm += dt
		q.sample(dt, lc.speed > 0.45 or absf(lc.yaw_rate) > 0.7, 0.0)
	Fixture.release_inputs()
	q.end()
	return q


func _turn() -> void:
	await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, -0.1, 12)
	var q := await _measure(0.5, 1.6, 3.4)
	TestLib.check(q.slide_per_cycle() < SLIDE_MAX * 1.4, "turning in place: foot slide %.1f cm per cycle; %s" % [q.slide_per_cycle() * 100.0, q.summary()])
	TestLib.check(q.footfalls_seen() >= 2, "turning in place steps the feet (%d)" % q.footfalls_seen())


## Run, stop, run again: the pelvis and the stride blend without a snap.
func _stop_and_start() -> void:
	await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, -0.1, 12)
	var lc := p.body.loco
	var q := LocoQA.new(p.body.rig, lc)
	q.begin()
	var t := 0.0
	var pops := 0.0
	var phase_jump := 0.0
	var prev_phase := lc._phase
	while t < 3.6:
		await e.frames(1)
		var dt := 1.0 / 60.0
		t += dt
		if t < 1.2 or t > 2.4:
			Input.action_press(&"move_forward", 1.0)
		else:
			Fixture.release_inputs()
		q.sample(dt, lc.speed > 0.45, 0.0)
		phase_jump = maxf(phase_jump, absf(fposmod(lc._phase - prev_phase + 0.5, 1.0) - 0.5))
		prev_phase = lc._phase
	Fixture.release_inputs()
	q.end()
	TestLib.check(q.pelvis_pop_max < POP_MAX, "start, stop and restart: the pelvis moves at most %.1f cm per frame (at %.2f s)" % [q.pelvis_pop_max * 100.0, q.pelvis_pop_at])
	TestLib.check(q.slide_per_cycle() < SLIDE_MAX * 1.5, "start, stop and restart: foot slide %.1f cm per cycle" % (q.slide_per_cycle() * 100.0))
	TestLib.check(phase_jump < 0.2, "the gait phase never jumps (largest step %.2f cycle)" % phase_jump)


## A 10 degree ramp: the soles follow the ground (planted soles do not slide, none sinks into it).
func _slope() -> void:
	var a := deg_to_rad(10.0)
	var ramp := Fixture.add_box(e.root, Vector3(3.0 + 15.0 * cos(a) + 0.2 * sin(a), 15.0 * sin(a) - 0.2 * cos(a), -30.0), Vector3(30.0, 0.4, 8.0))
	ramp.rotation.z = a
	await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, -0.1, 12)
	Input.action_press(&"move_forward", 0.6)
	var gnd := func(w: Vector3) -> float: return clampf(tan(a) * (w.x - 3.0), 0.0, 5.0)
	var q := await _measure(2.4, 1.8, 0.0, gnd)
	var onslope: bool = p.global_position.x > 6.0
	TestLib.check(onslope, "the hero climbs the ramp (x = %.1f m)" % p.global_position.x)
	TestLib.check(q.slide_per_cycle() < SLIDE_MAX * 1.5, "uphill: foot slide %.1f cm per cycle; %s" % [q.slide_per_cycle() * 100.0, q.summary()])
	var sink := 0.0
	for k in 2:
		var s := q.sole_world(k)
		sink = maxf(sink, gnd.call(s) - s.y)
	TestLib.check(sink < 0.08, "no sole sinks into the ramp (%.1f cm)" % (sink * 100.0))
	ramp.queue_free()


func _camera_bob() -> void:
	await e.prep(Vector3(0.0, 0.0, -30.0), -PI * 0.5, -0.1, 30)
	var cam := p.camera_rig
	TestLib.check(absf(cam._bob_gain) < 0.05, "standing: no camera bob (gain %.2f)" % cam._bob_gain)
	Input.action_press(&"move_forward", 1.0)
	await e.secs(1.2)
	TestLib.check(cam._bob_gain > 0.8, "running: the camera bob is on (gain %.2f)" % cam._bob_gain)
	TestLib.check(is_equal_approx(cam._bob_t, p.body.rig.phase * 2.0), "the bob follows the gait phase")
	Fixture.release_inputs()
	await e.secs(1.0)
	TestLib.check(cam._bob_gain < 0.1, "stopped: the camera bob fades out (gain %.2f)" % cam._bob_gain)
