extends RefCounted
## Director review round 2, part C (docs/SLICE_REVIEW.md defects 8, 9, 10: cars are toys, a small cluttered driving view, a crash is a cliff) in the REAL game scene:
##   10  the hull damage grows smoothly with the impact energy (no step anywhere in the curve): a 25 km/h bump costs a few percent, 90 km/h into a wall hurts a lot but the car
##       drives away, the stages come one after the other (dents, a thin wisp, smoke, fire), the driver loses little except at extreme speed, the mechanic repairs everything
##   8   the car models: longer, lower and wider than the first set, real wheel size, flush track, a sane wheelbase, never a black paint
##   9   the driving view: the chase camera frames the whole car large (a third of the width of a phone frame) and the HUD in a car is the speed, the hull and the objective plus
##       four buttons (DRIFT, EXIT, VIEW, MORE; FIRE only on an armed car), engine sound with a wind bed that rises with the speed and a rough note when the engine is hurt
## Waits on game time, positions and counters, never on frame counts; user:// state is reset first. Frames of the same things: tests/bot_vehicle_realism.gd (BOT_SET=chase|damage|drive,
## BOT_CLEAN=1) and tools/vehicle_view.sh; sheets in docs/shots/slice/round2_c_*.
## Run: tools/test.sh tests/test_director_round2_c.gd

const K := 4
const DT := 1.0 / 60.0
const AVE_Z := 5.0
const KINDS: Array[StringName] = [&"sedan", &"sport", &"suv", &"taxi", &"wagon"]

var host: Node
var city: City
var p: Player
var mgr: VehicleManager
var hud: Hud
var walls: Array[StaticBody3D] = []


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_curve()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	city = Game.world as City
	p = Game.player as Player
	mgr = Game.vehicles as VehicleManager
	hud = host.get_tree().get_first_node_in_group(&"hud") as Hud
	TestLib.check(city != null and p != null and mgr != null and hud != null, "the real scene has a city, a player, a vehicle manager and a HUD")
	if city == null or p == null or mgr == null or hud == null:
		_restore()
		return
	p.set_physics_process(true)
	p.max_hp = 100.0
	p.hp = 100.0
	mgr.stream_every = 1.0e9
	mgr._stream_t = 1.0e9
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	for k: StringName in KINDS:                                       # make every body used below now: a body made this frame is not in the physics space yet
		mgr.spawn_parked(k, Vector3(-700.0 + float(mgr.list.size()) * 10.0, 0.0, 400.0), 0.0)
		await TestLib.frames(host, 2)
		for v in mgr.list.duplicate():
			if v != mgr.starter:
				mgr._release(v)
	await TestLib.frames(host, 4)
	_models()
	await _crashes()
	_stages_and_repair()
	await _hud_in_car()
	await _camera_frame()
	await _engine_sound()
	_restore()
	for w in walls:
		w.queue_free()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


func _restore() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Input.action_release(&"move_forward")
	Sfx.muted = true


# --- helpers -------------------------------------------------------------------------------------------------------------------------------------------

func _clear() -> void:
	if mgr.driven != null:
		mgr.exit_vehicle()
	for v in mgr.list.duplicate():
		mgr._release(v)
	mgr.starter = null
	if NearTraffic.instance != null:
		NearTraffic.instance.count = 0
		NearTraffic.instance.reset()


func _car(kind: StringName, x: float, z := AVE_Z, heading := -PI * 0.5, collide := false) -> Vehicle:
	while mgr.list.size() >= mgr.cap():
		mgr._release(mgr.list[0])
	var v := mgr.spawn_parked(kind, Vector3(x, 0.0, z), heading)
	v.global_position = Vector3(x, 0.0, z)
	v.heading = heading
	v.rotation = Vector3(0.0, heading, 0.0)
	v._heading_set = heading
	v.vel = Vector3.ZERO
	v.speed = 0.0
	v.yaw_rate = 0.0
	v._dist = 0.0
	v.collision_mask = Game.L_WORLD if collide else 0
	return v


func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Game.L_WORLD
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	host.add_child(b)
	b.global_position = center
	walls.append(b)
	return b


## One head-on hit of `v` into the wall at x = -300 at `speed` m/s (the car coasts the last metres); returns the hull share lost (0..1).
func _hit(v: Vehicle, speed: float) -> float:
	v.global_position = Vector3(-304.6, 0.0, AVE_Z)
	v.heading = -PI * 0.5
	v.rotation = Vector3(0.0, v.heading, 0.0)
	v._heading_set = v.heading
	v.vel = v.forward() * speed
	v.speed = speed
	var hp0 := v.hp
	var c0 := v.crashes
	var t := 0.0
	while v.crashes == c0 and t < 2.0:
		v.step_drive(DT, 0.0, 0.0, false)
		v._sync(DT)
		t += DT
	for i in 30:                                                      # let the car settle so the next hit is a new crash, not the same grind
		v.step_drive(DT, 0.0, 0.0, false)
		v._sync(DT)
	return (hp0 - v.hp) / v.max_hp


# --- 10: the curve -------------------------------------------------------------------------------------------------------------------------------------

func _curve() -> void:
	var prev := 0.0
	var worst_step := 0.0
	var mono := true
	var v := 0.0
	while v <= 34.0:
		var f := Vehicle.crash_fraction(v)
		mono = mono and f >= prev - 1e-6
		worst_step = maxf(worst_step, f - prev)
		prev = f
		v += 0.25
	TestLib.check(mono and worst_step < 0.025, "the damage curve never steps: monotone, at most %.3f per 0.25 m/s (a cliff would be a jump)" % worst_step)
	var f7 := Vehicle.crash_fraction(25.0 / 3.6)
	var f11 := Vehicle.crash_fraction(40.0 / 3.6)
	var f17 := Vehicle.crash_fraction(60.0 / 3.6)
	var f25 := Vehicle.crash_fraction(90.0 / 3.6)
	TestLib.check(f7 < 0.04 and f11 < 0.18 and f17 > 0.2 and f17 < 0.5 and f25 > 0.6 and f25 < 0.92, "25 km/h %.0f %%, 40 km/h %.0f %%, 60 km/h %.0f %%, 90 km/h %.0f %% of a hull" % [f7 * 100.0, f11 * 100.0, f17 * 100.0, f25 * 100.0])
	TestLib.check(f25 > f7 * 15.0, "a fender bender is nothing next to a wall at 90 km/h")
	var d1 := VehicleSpecs.HERO_HURT_MAX * pow(clampf((25.0 - VehicleSpecs.HERO_HURT_SPEED) / (VehicleSpecs.CRASH_WRECK - VehicleSpecs.HERO_HURT_SPEED), 0.0, 1.5), 2.0)
	var d2 := VehicleSpecs.HERO_HURT_MAX * pow(clampf((29.0 - VehicleSpecs.HERO_HURT_SPEED) / (VehicleSpecs.CRASH_WRECK - VehicleSpecs.HERO_HURT_SPEED), 0.0, 1.5), 2.0)
	TestLib.check(d1 <= 15.0 and d2 > d1 * 1.8 and VehicleSpecs.HERO_HURT_CAP <= 0.3, "the driver at 90 km/h loses %.0f of 100, only an extreme impact (104 km/h) takes %.0f" % [d1, d2])
	TestLib.check(Vehicle.stage_for(80.0, 100.0) == 0 and Vehicle.stage_for(60.0, 100.0) == 1 and Vehicle.stage_for(30.0, 100.0) == 2 and Vehicle.stage_for(10.0, 100.0) == 3, "four stages by hull: clean, wisp, smoke, fire")


# --- 8: the models -------------------------------------------------------------------------------------------------------------------------------------

func _models() -> void:
	for k: StringName in KINDS:
		_clear()
		var v := _car(k, -560.0 + float(KINDS.find(k)) * 12.0, 300.0, 0.0)
		var spec := v.spec
		var ln := float(spec["len"])
		var wd := float(spec["wid"])
		var hg := float(spec["hgt"])
		var wr := float(spec["wheel"])
		var vis := v.visual
		TestLib.check(vis.uses_model and vis.wheels.size() == 4, "%s is the Blender model with four wheels" % k)
		if vis.wheels.size() < 4:
			continue
		TestLib.check(ln / hg >= 2.7 and wd / ln >= 0.38 and wd / ln <= 0.45, "%s: long and low, not a box (length %.2f, width %.2f, height %.2f: %.1f : 1)" % [k, ln, wd, hg, ln / hg])
		TestLib.check(wr >= 0.345 and wr / hg >= 0.21, "%s has real wheels (radius %.2f m, %.0f %% of its height)" % [k, wr, wr / hg * 100.0])
		var track := (vis.wheels[0].position - vis.wheels[1].position).length()
		var base := absf(vis.wheels[0].position.z - vis.wheels[2].position.z)
		TestLib.check(track >= wd * 0.82 and track <= wd * 0.95, "%s: the wheels stand out at the corners (track %.2f of width %.2f)" % [k, track, wd])
		TestLib.check(base >= ln * 0.57 and base <= ln * 0.68, "%s: wheelbase %.2f of length %.2f" % [k, base, ln])
		var hmax := 0.0
		var tyres: Array = vis.wheels[0].find_children("*", "MeshInstance3D", true, false)
		if vis.wheels[0] is MeshInstance3D:
			tyres.append(vis.wheels[0])
		for mi in tyres:
			hmax = maxf(hmax, ((mi as MeshInstance3D).get_aabb()).size.y)
		TestLib.check(hmax >= wr * 1.9 and hmax <= wr * 2.2, "%s: the tyre mesh is %.2f m tall for a %.2f m wheel" % [k, hmax, wr])
	var lum_ok := true
	var worst := 1.0
	for c: Color in VehicleSpecs.COLORS:
		worst = minf(worst, c.get_luminance())
		lum_ok = lum_ok and c.get_luminance() > 0.14
	TestLib.check(lum_ok and VehicleSpecs.WRECK_COLOR.get_luminance() > 0.1, "no black paint in the palette (darkest %.2f)" % worst)
	var painted := true
	for k: StringName in KINDS:
		_clear()
		var v := _car(k, -560.0, 300.0, 0.0)
		for c: Color in VehicleSpecs.COLORS:
			v.visual.set_paint(c)
			painted = painted and v.visual.get_paint().get_luminance() > 0.1
	TestLib.check(painted, "every paint on every model stays lit (no black car)")


# --- 10: live crashes ----------------------------------------------------------------------------------------------------------------------------------

func _crashes() -> void:
	_clear()
	mgr.set_physics_process(false)
	_wall(Vector3(-299.5, 3.0, AVE_Z), Vector3(1.0, 6.0, 160.0))
	await TestLib.frames(host, 4)
	var bump := _car(&"sedan", -304.6, AVE_Z, -PI * 0.5, true)
	var lost_bump := _hit(bump, 7.0)
	TestLib.check(lost_bump <= 0.05 and bump.dmg_state == 0 and bump.damage_stage() == 0, "a 25 km/h bump costs %.0f %% of the hull and leaves the car clean" % (lost_bump * 100.0))
	_clear()
	var big := _car(&"sedan", -304.6, AVE_Z, -PI * 0.5, true)
	mgr.enter(big)
	p.hp = 100.0
	p.invuln = 0.0
	var lost_big := _hit(big, 25.0)
	TestLib.check(lost_big > 0.55 and lost_big < 0.93 and not big.dead and big.hp > 0.0, "90 km/h into a wall hurts a lot (%.0f %% of the hull) and the car is still there (hp %.0f)" % [lost_big * 100.0, big.hp])
	TestLib.check(big.damage_stage() >= 2 and big.visual.dents.size() >= 1 and big.visual.cracks > 0.0, "it smokes, it is dented and the glass is cracked (stage %d, %d dents)" % [big.damage_stage(), big.visual.dents.size()])
	TestLib.check(p.hp >= 85.0, "the driver walks away from it (integrity %.0f of 100)" % p.hp)
	mgr.exit_vehicle()
	_clear()
	# a run of normal crashes goes through the stages one at a time
	var seq := _car(&"sedan", -304.6, AVE_Z, -PI * 0.5, true)
	var stages: Array[int] = [seq.damage_stage()]
	var steps_ok := true
	for i in 5:
		_hit(seq, 12.0)
		stages.append(seq.damage_stage())
		steps_ok = steps_ok and stages[i + 1] >= stages[i] and stages[i + 1] - stages[i] <= 1
	TestLib.check(steps_ok and stages[stages.size() - 1] >= 2 and not seq.dead, "five 43 km/h crashes walk the car through the stages %s, never a jump" % str(stages))
	_clear()


func _stages_and_repair() -> void:
	_clear()
	var v := _car(&"sedan", -560.0, AVE_Z, -PI * 0.5, false)
	v.activate(v.global_position, v.heading)
	v.visual.add_dent(Vector3(0.3, 0.6, -2.0), Vector3(0.0, 0.0, 1.0), 0.3)
	v.visual.crack_glass(0.6)
	v.hp = v.max_hp * 0.6
	v._hurt(0.0)
	TestLib.check(v.damage_stage() == 1 and v.dmg_state == 0, "at 60 %% hull the engine shows a thin wisp, not smoke (stage %d)" % v.damage_stage())
	var fx0 := FX._pi
	v._fx_t = 0.0
	v._dist = 5.0
	v._damage_fx(0.5)
	TestLib.check(FX._pi != fx0, "the wisp is drawn from the pooled FX bursts")
	v.hp = v.max_hp * 0.3
	v._hurt(0.0)
	TestLib.check(v.damage_stage() == 2 and v.dmg_state == 1, "at 30 %% hull it smokes (stage %d)" % v.damage_stage())
	v.repair()
	TestLib.check(v.hp == v.max_hp and v.damage_stage() == 0 and v.visual.dents.is_empty() and v.visual.cracks == 0.0 and v.dmg_state == 0, "the mechanic gives back the whole hull: no dents, no cracks, no smoke")
	_clear()


# --- 9: the HUD and the camera in a car ----------------------------------------------------------------------------------------------------------------

func _visible_buttons(tc: TouchControls) -> Array[String]:
	var out: Array[String] = []
	for b: Dictionary in TouchControls.BUTTONS:
		if tc.button_visible(b):
			out.append(String(b["action"]))
	return out


func _hud_in_car() -> void:
	_clear()
	mgr.set_physics_process(true)
	var tc := hud.touch
	tc.controls_on = true
	tc.more_open = false
	var foot := _visible_buttons(tc)
	TestLib.check(foot.has("aim") and foot.has("reload") and foot.has("fire"), "on foot the frame is unchanged (%d buttons)" % foot.size())
	var v := _car(&"sedan", -560.0, AVE_Z, -PI * 0.5, false)
	p.teleport_to(v.global_position + Vector3(0.0, 0.0, -3.0))
	await TestLib.frames(host, 4)
	mgr.enter(v)
	await TestLib.frames(host, 4)
	var drv := _visible_buttons(tc)
	var want := ["jump", "interact", "veh_view", "more"]
	var same := true
	for a in want:
		same = same and drv.has(a)
	TestLib.check(same and drv.size() <= 5, "in a sedan the frame is DRIFT, EXIT, VIEW and MORE (%s)" % str(drv))
	TestLib.check(not drv.has("aim") and not drv.has("reload") and not drv.has("fire") and not drv.has("look_back") and not drv.has("radio_next") and not drv.has("garage_open"), "no AIM, RELOAD, FIRE, BACK, RADIO or GARAGE circle while driving")
	tc.more_open = true
	var more := _visible_buttons(tc)
	TestLib.check(more.has("look_back") and (more.has("radio_next") or Game.vehicles.get("radio") == null), "MORE brings BACK and the RADIO back")
	tc.more_open = false
	var tc_label := ""
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"jump":
			tc_label = tc._label_of(b)
	TestLib.check(tc_label == "DRIFT", "the handbrake is called DRIFT in a car (%s)" % tc_label)
	v.speed = 20.0
	hud._ammo_key = -1
	TestLib.check(hud.ammo_text() == "%d KM/H" % roundi(20.0 * 3.6), "the speedometer reads km/h (%s)" % hud.ammo_text())
	mgr.exit_vehicle()
	_clear()
	var sp := _car(&"sport", -560.0, AVE_Z, -PI * 0.5, false)
	p.teleport_to(sp.global_position + Vector3(0.0, 0.0, -3.0))
	await TestLib.frames(host, 4)
	mgr.enter(sp)
	await TestLib.frames(host, 4)
	TestLib.check(_visible_buttons(tc).has("fire"), "an armed car (the sport car's rail gun) keeps its FIRE circle")
	mgr.exit_vehicle()
	_clear()


func _camera_frame() -> void:
	var win := host.get_window()
	var old := win.size
	win.size = Vector2i(1200, 540)                                   # the phone's 2.2 : 1
	await TestLib.frames(host, 4)
	var rig := p.camera_rig
	for k: StringName in [&"sedan", &"sport"]:
		_clear()
		mgr.set_physics_process(true)
		var v := _car(k, -560.0, AVE_Z, -PI * 0.5, false)
		p.teleport_to(v.global_position + Vector3(0.0, 0.0, -3.0))
		await TestLib.frames(host, 8)
		mgr.enter(v)
		rig.veh_view = 0
		var t := 0.0
		while (rig.mode != &"vehicle" or absf(rig.camera.fov - CameraRig.VEH_FOV_REST) > 2.0 or rig._veh_dist_now < 4.0) and t < 8.0:
			await TestLib.frames(host, 4)
			t += 4.0 * DT
		await TestLib.frames(host, 40)
		var cam := rig.camera
		var vp := cam.get_viewport().get_visible_rect().size
		var wd := float(v.spec["wid"])
		var ln := float(v.spec["len"])
		var hg := float(v.spec["hgt"])
		var rl := v.global_position - v.forward() * ln * 0.5 - v.right() * wd * 0.5
		var rr := v.global_position - v.forward() * ln * 0.5 + v.right() * wd * 0.5
		var top := v.global_position - v.forward() * ln * 0.35 + Vector3(0.0, hg, 0.0)
		var a := cam.unproject_position(rl)
		var b := cam.unproject_position(rr)
		var c := cam.unproject_position(top)
		var frac := absf(b.x - a.x) / vp.x
		TestLib.check(frac >= 0.22 and frac <= 0.5, "%s fills %.0f %% of the width of the frame at rest (the first build: 24 %%, tiny from far)" % [k, frac * 100.0])
		TestLib.check(a.y < vp.y - 2.0 and b.y < vp.y - 2.0 and c.y > 0.0 and a.x > 0.0 and b.x < vp.x, "%s is wholly in the frame, the bumper included (rear corners at y %.0f / %.0f of %.0f)" % [k, a.y, b.y, vp.y])
		TestLib.check(not cam.is_position_behind(rl) and rig.camera.fov > 68.0 and rig.camera.fov < 90.0, "a wide, calm lens at rest (%.0f degrees)" % rig.camera.fov)
		mgr.exit_vehicle()
	win.size = old
	await TestLib.frames(host, 4)
	_clear()


# --- 9: sound ------------------------------------------------------------------------------------------------------------------------------------------

func _engine_sound() -> void:
	_clear()
	mgr.set_physics_process(false)
	var v := _car(&"sedan", -560.0, AVE_Z, -PI * 0.5, false)
	p.teleport_to(v.global_position + Vector3(0.0, 0.0, -3.0))
	await TestLib.frames(host, 4)
	mgr.enter(v)
	await TestLib.frames(host, 2)
	Sfx.muted = false
	Game.state = &"play"
	var wind: AudioStreamPlayer = Sfx._loops.get(&"drive_wind")
	TestLib.check(wind != null, "the engine sound has a wind bed")
	v.speed = 0.0
	for i in 20:
		Sfx._step_vehicle(0.05)
	var quiet_db := wind.volume_db if wind != null and wind.playing else -80.0
	v.speed = 26.0
	v.rpm = 0.8
	for i in 40:
		Sfx._step_vehicle(0.05)
	TestLib.check(wind != null and wind.playing and wind.volume_db > quiet_db + 12.0 and wind.pitch_scale > 1.1, "the wind rises with the speed (%.0f dB at rest, %.0f dB at 94 km/h, pitch %.2f)" % [quiet_db, wind.volume_db if wind != null else 0.0, wind.pitch_scale if wind != null else 0.0])
	var low: AudioStreamPlayer = Sfx._loops[AudioDirector.engine_loops(Sfx._engine_variant)[1]]      # the high loop of the engine variant in use (it carries the note at 0.8 rpm)
	var spread := func() -> float:
		var lo := 99.0
		var hi := -99.0
		for i in 40:
			await TestLib.frames(host, 1)
			Sfx._step_vehicle(0.05)
			lo = minf(lo, low.pitch_scale)
			hi = maxf(hi, low.pitch_scale)
		return hi - lo
	v.hp = v.max_hp
	var healthy: float = await spread.call()
	v.hp = v.max_hp * 0.2
	var rough: float = await spread.call()
	TestLib.check(rough > healthy + 0.012, "a hurt engine runs rough: the note wobbles (%.3f against %.3f)" % [rough, healthy])
	v.hp = v.max_hp
	v.speed = 0.0
	for i in 60:
		Sfx._step_vehicle(0.05)
	mgr.exit_vehicle()
	Sfx._step_vehicle(0.05)
	Sfx.muted = true
	_clear()
