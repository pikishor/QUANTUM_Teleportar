extends RefCounted
## Stability and feedback: every "the screen got stuck / the world disappeared" scenario of the owner's phone test, driven headless.
## Hurt spam, explosion spam, death (slow motion, kill camera, respawn button), time-scale restore, held-input release, rapid state changes in every order,
## a crash and an explosion with the player driving, dying inside a vehicle, respawn while the vehicle exists, the wreck husk, the camera watchdog, the adaptive
## quality tier, the on-device error log, the FPS-box long press, the loading overlay and the light menu.
## Run: tools/test.sh tests/test_stability.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const TMP := "user://stability_test.cfg"

class StubTier extends Node3D:
	var q := -1
	func set_quality(level: int) -> void:
		q = level

var e := Env.new()
var p: Player
var root: Node3D
var atmo: Atmosphere
var hud: Hud
var stab: Stability
var mgr: VehicleManager


func run(host: Node) -> void:
	seed(11)
	await e.setup(host)
	p = e.p
	root = e.root
	Fixture.add_floor(root, 400.0)
	atmo = (load("res://scenes/atmosphere.tscn") as PackedScene).instantiate() as Atmosphere
	root.add_child(atmo)
	mgr = (load("res://scenes/vehicle_manager.tscn") as PackedScene).instantiate() as VehicleManager
	root.add_child(mgr)
	hud = (load("res://scenes/hud.tscn") as PackedScene).instantiate() as Hud
	hud.settings_path = TMP
	root.add_child(hud)
	stab = Stability.new()
	root.add_child(stab)
	await e.frames(4)
	mgr.respawn_time = 1.5
	TestLib.check(Engine.time_scale == 1.0, "the run starts at time scale 1")

	await _vignette_and_hurt()
	await _low_fps_camera()
	await _explosion_spam()
	await _death_and_respawn()
	await _time_scale()
	await _held_input()
	await _rapid_states()
	await _vehicle_crash()
	await _vehicle_explosion_and_death()
	await _respawn_with_vehicle()
	await _camera_watchdog()
	await _pause_in_blast()
	await _auto_quality()
	await _error_log()
	await _touch_long_press(host)
	await _loading_and_menu(host)

	TestLib.check(Engine.time_scale == 1.0, "the run ends at time scale 1 (%.2f)" % Engine.time_scale)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	Game.state = &"play"
	root.queue_free()
	await e.frames(2)
	Fixture.release_inputs()
	Game.state = &"menu"
	Game.atmosphere = null
	Sfx.muted = false


func _alive_state() -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	Game.heat = 0.0
	Engine.time_scale = 1.0
	FX.shake_amount = 0.0
	p.reset()
	p.invuln = 0.0


func _vignette_and_hurt() -> void:
	# the one damage vignette is capped in every situation
	var worst := 0.0
	for since in [0.0, 0.05, 0.2, 0.5, 2.0]:
		for hp_f in [0.0, 0.05, 0.15, 0.3, 1.0]:
			for t in [0.0, 0.3, 0.6, 1.0]:
				worst = maxf(worst, Hud.vignette_alpha(since, hp_f, true, t))
	TestLib.check(worst <= 0.35 and worst > 0.2, "the damage vignette never exceeds alpha 0.35 (worst %.2f) and is still visible" % worst)
	TestLib.check(Hud.DEAD_DIM <= 0.35 and Hud.VIGNETTE_MAX <= 0.35, "the dead dimming is capped at 35 percent")
	_alive_state()
	await e.prep(Vector3(0.0, 0.0, 0.0), 0.0)
	var from := Vector3(20.0, 1.0, -30.0)
	for i in 120:
		p.invuln = 0.0
		p.hp = 100.0
		p.damage(2.0, from)
	TestLib.check(FX.shake_amount <= 1.0, "hurt spam: the shake amount stays within 0..1 (%.2f)" % FX.shake_amount)
	await e.frames(2)
	TestLib.check(atmo.hurt_level <= 1.0 and atmo.hurt_level > 0.0, "hurt spam: the chromatic kick is capped at 1 (%.2f)" % atmo.hurt_level)
	TestLib.check(atmo.post.feedback().x <= atmo.post.FB_CA_MAX + 1e-6, "hurt spam: the post chromatic aberration add-on stays under its cap (%.4f)" % atmo.post.feedback().x)
	var cam := p.camera_rig.camera
	TestLib.check(cam.global_position.is_finite() and cam.global_position.distance_to(p.global_position) < 6.0, "hurt spam: the camera stays with the player (%.1f m)" % cam.global_position.distance_to(p.global_position))
	await e.secs(0.8)
	var guard := 0
	while (atmo.hurt_level != 0.0 or atmo.post.feedback() != Vector2(0.0, 1.0)) and guard < 20:
		guard += 1
		await e.secs(0.5)
	TestLib.check(atmo.hurt_level == 0.0 and atmo.post.feedback() == Vector2(0.0, 1.0), "the hurt effect recovers completely (hurt %.4f fb %s dead %.3f scale %.2f)" % [atmo.hurt_level, atmo.post.feedback(), atmo.dead_level, Engine.time_scale])
	TestLib.check(FX.shake_amount == 0.0, "the shake decays to zero")


func _low_fps_camera() -> void:
	# a phone at 8-10 fps (frame time 0.1 s) in a firefight: hits kick the landing spring, which must never fly the camera away
	_alive_state()
	await e.prep(Vector3(0.0, 0.0, 0.0), 0.0)
	var rig := p.camera_rig
	for i in 60:
		rig.bump(1.0)
		rig.kick(0.05)
		FX.shake(1.0)
		rig._update_view(0.1)
	var d := rig.camera.global_position.distance_to(p.global_position)
	TestLib.check(rig.camera.global_position.is_finite() and d < 6.0, "10 fps with a hit on every frame: the camera stays with the player (%.1f m)" % d)
	rig._update_view(0.5)
	TestLib.check(rig.camera.global_position.distance_to(p.global_position) < 6.0, "a 0.5 s hitch does not fling the camera either")
	_alive_state()


func _explosion_spam() -> void:
	_alive_state()
	await e.prep(Vector3(0.0, 0.0, 0.0), 0.0)
	for i in 30:
		Game.explode(Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0)), 6.0, {"player_dmg": 0.0, "enemy_dmg": 0.0, "car_dmg": 0.0})
	TestLib.check(FX.shake_amount <= 1.0, "explosion spam: shake stays within 0..1 (%.2f)" % FX.shake_amount)
	await e.frames(3)
	var cam := p.camera_rig.camera
	var rest := p.camera_rig.get_pivot_position().distance_to(cam.global_position)
	TestLib.check(cam.global_position.is_finite() and rest < 6.0, "explosion spam: the camera stays within reach of its pivot (%.1f m)" % rest)
	await e.secs(0.5)
	TestLib.check(FX.shake_amount == 0.0, "explosion spam: shake is gone after half a second")


func _death_and_respawn() -> void:
	_alive_state()
	await e.prep(Vector3(0.0, 0.0, 0.0), 0.0)
	var attacker := Vector3(0.0, 1.5, -25.0)
	e.died_count = 0
	p.damage(999.0, attacker)
	await e.frames(3)
	TestLib.check(Game.state == &"dead" and e.died_count == 1, "the player dies once")
	TestLib.check(stab.slowmo_active and Engine.time_scale < 0.5, "death starts a slow motion (%.2f)" % Engine.time_scale)
	hud._ensure_layout()
	var respawn_ok := false
	for b: Dictionary in hud.buttons:
		if b["id"] == &"respawn":
			var r: Rect2 = b["rect"]
			var vp := hud.get_viewport().get_visible_rect()
			respawn_ok = vp.encloses(r) and r.size.x > 100.0
	TestLib.check(respawn_ok, "a clear RESPAWN button is on screen")
	await e.secs(2.0)
	TestLib.check(Engine.time_scale == 1.0 and not stab.slowmo_active, "the slow motion ends by itself (%.2f)" % Engine.time_scale)
	TestLib.check(hud.screen_age >= Hud.LOCK, "the respawn button is live after the real-time lock (%.1f s)" % hud.screen_age)
	var cam := p.camera_rig.camera
	var look := -cam.global_basis.z
	look.y = 0.0
	var to_killer := attacker - p.global_position
	to_killer.y = 0.0
	TestLib.check(look.normalized().dot(to_killer.normalized()) > 0.6, "the kill camera keeps the attacker in view (dot %.2f)" % look.normalized().dot(to_killer.normalized()))
	TestLib.check(cam.global_position.is_finite() and cam.global_position.distance_to(p.global_position) < 9.0, "the death camera stays near the body")
	TestLib.check(p.body.visible and Game.camera == cam and cam.current, "the player stays visible and the gameplay camera stays current")
	TestLib.check(hud.press_button(&"respawn") and Game.state == &"play", "RESPAWN works")
	await e.secs(1.0)
	TestLib.check(not p.is_dead() and p.hp > 99.0 and p.camera_rig.mode == &"foot" and Engine.time_scale == 1.0, "after the respawn: alive, camera on foot, time normal")
	TestLib.check(atmo.dead_level == 0.0 and atmo.post.feedback() == Vector2(0.0, 1.0), "the death grade is gone after the respawn")
	TestLib.check(hud.layers_consistent() and FX.shake_amount < 0.01, "the HUD layers match the state and nothing shakes")
	var rig := p.camera_rig
	TestLib.check(rig.get_pivot_position().distance_to(p.global_position + Vector3(0.0, 1.55, 0.0)) < 0.3, "the camera pivot is back on the player")


func _time_scale() -> void:
	# a death that is left at once (respawn, menu, win) must not leave a slow motion behind
	for next_state in [&"play", &"menu", &"win", &"paused"]:
		_alive_state()
		p.damage(999.0)
		await e.frames(2)
		TestLib.check(Engine.time_scale < 0.5, "slow motion on (%s case)" % next_state)
		Game.state = next_state
		TestLib.check(Engine.time_scale == 1.0, "leaving the dead state for %s restores time at once" % next_state)
	# it gives back the value it found
	_alive_state()
	Engine.time_scale = 2.0
	p.damage(999.0)
	await e.frames(2)
	Game.state = &"play"
	TestLib.check(Engine.time_scale == 2.0, "a harness running at 2x gets its 2x back")
	Engine.time_scale = 1.0
	# dying twice in a row
	_alive_state()
	p.damage(999.0)
	await e.frames(2)
	Game.do_respawn()
	p.damage(999.0)
	await e.frames(2)
	p.reset()
	Game.do_respawn()
	await e.frames(2)
	TestLib.check(Engine.time_scale == 1.0 and not stab.slowmo_active, "two deaths in a row end at time scale 1")


func _held_input() -> void:
	for st in [&"paused", &"dead", &"win", &"menu"]:
		_alive_state()
		for a in [&"move_forward", &"fire", &"sprint", &"jump", &"interact", &"aim"]:
			Input.action_press(a)
		Game.state = st
		await e.frames(1)
		var held := false
		for a in Stability.INPUT_ACTIONS:
			held = held or Input.is_action_pressed(a)
		TestLib.check(not held, "no action stays held when the state becomes %s" % st)
		Input.action_press(&"move_forward")
		await e.frames(6)
		TestLib.check(not Input.is_action_pressed(&"move_forward"), "an action pressed during %s is released by the watchdog" % st)
	_alive_state()


func _rapid_states() -> void:
	_alive_state()
	var ops := ["new", "respawn", "next", "die", "win", "pause", "resume", "menu", "dead", "state_play"]
	for i in 80:
		match ops[randi() % ops.size()]:
			"new": Game.start_new_game()
			"respawn": Game.do_respawn()
			"next": Game.do_next_sector()
			"die": p.damage(999.0)
			"win": Game.win()
			"pause": Game.state = &"paused"
			"resume": Game.state = &"play"
			"menu": Game.state = &"menu"
			"dead": Game.state = &"dead"
			"state_play": Game.state = &"play"
		if randf() < 0.5:
			Input.action_press(&"move_forward")
		if i % 3 == 0:
			await e.frames(1)
	Game.start_new_game()
	await e.secs(0.4)
	stab.audit()
	TestLib.check(stab.audit().is_empty(), "after rapid state changes the audit finds nothing to repair")
	TestLib.check(Engine.time_scale == 1.0 and not stab.slowmo_active, "rapid changes: time scale is 1")
	TestLib.check(not p.is_dead() and p.body.visible and p.collision_layer == Game.L_PLAYER, "rapid changes: the player is alive, visible and solid")
	TestLib.check(p.camera_rig.mode == &"foot" and p.camera_rig.follow_target == p and p.camera_rig.camera.current, "rapid changes: camera on foot, following the player, current")
	TestLib.check(not Input.is_action_pressed(&"move_forward") or Game.state == &"play", "rapid changes: no stuck input outside play")
	TestLib.check(hud.layers_consistent() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "rapid changes: HUD layers fine, mouse free in tools")
	TestLib.check(atmo.dead_level == 0.0 and atmo.hurt_level == 0.0, "rapid changes: no post feedback left")
	Fixture.release_inputs()


func _crash_scene(spot: Vector3) -> Vehicle:
	await e.prep(spot + Vector3(3.0, 0.0, 0.0), 0.0)
	var car := mgr.spawn_parked(&"sedan", spot, 0.0)
	mgr.toggle_enter_exit()
	await e.frames(3)
	return car


func _assert_on_foot(what: String) -> void:
	var rig := p.camera_rig
	TestLib.check(p.vehicle == null and mgr.driven == null, "%s: the player is on foot" % what)
	TestLib.check(p.body.visible and p.collision_layer == Game.L_PLAYER, "%s: body visible and collider back" % what)
	TestLib.check(rig.mode == &"foot" and rig.follow_target == p and Game.camera.current, "%s: camera back in foot mode on the player" % what)
	TestLib.check(rig.camera.global_position.is_finite() and rig.camera.global_position.distance_to(p.global_position) < 8.0, "%s: the camera is with the player (%.1f m)" % [what, rig.camera.global_position.distance_to(p.global_position)])
	TestLib.check(Engine.time_scale == 1.0 or Game.state == &"dead", "%s: time scale sane" % what)


func _vehicle_crash() -> void:
	_alive_state()
	# a hard wall hit with the player inside wrecks the car and ejects him
	var car := await _crash_scene(Vector3(0.0, 0.0, 4.0))
	TestLib.check(p.vehicle == car and p.camera_rig.mode == &"vehicle", "the crash scene: the player drives")
	car.global_position = Vector3(-2.0, 0.0, 4.0)
	car.heading = PI * 0.5                   # forward = -X, the wall face is at x = -9.5
	car.rotation.y = PI * 0.5
	car.vel = Vector3(-30.0, 0.0, 0.0)
	car.speed = 30.0
	car.hp = 20.0
	Input.action_press(&"move_forward")
	await e.secs(1.0)
	Input.action_release(&"move_forward")
	TestLib.check(car.dead and car.wreck, "the crash wrecked the car")
	TestLib.check(car.visible and not car.is_in_group(&"vehicle") and not mgr.list.has(car), "the wreck stays as a visible husk outside the vehicle group")
	TestLib.check(mgr.wreck_count() >= 1 and car.visual.get_paint().get_luminance() < 0.12, "the husk is charred (%d wrecks)" % mgr.wreck_count())
	_assert_on_foot("crash")
	TestLib.check(p.global_position.y < 1.0 and not p.is_dead(), "the player stands on the ground, alive (hp %.0f)" % p.hp)
	p.teleport_to(Vector3(0.0, 0.0, 200.0))        # the replacement never appears within 25 m of the player
	await e.secs(2.2)
	TestLib.check(not car.wreck and not car.visible and mgr.wreck_count() == 0, "the husk is cleared when the replacement is due")
	TestLib.check(mgr.pending_respawns() == 0, "the replacement car came back")
	_alive_state()


func _vehicle_explosion_and_death() -> void:
	_alive_state()
	var car := await _crash_scene(Vector3(40.0, 0.0, 40.0))
	car.damage(9999.0)
	await e.frames(3)
	_assert_on_foot("explosion while driving")
	TestLib.check(p.hp < 100.0 and p.hp > 40.0, "the blast hurts but does not kill a healthy player (hp %.0f)" % p.hp)
	await e.secs(0.4)
	# dying inside a vehicle: the blast of the car kills the weakened driver after the eject
	_alive_state()
	e.died_count = 0
	var car2 := await _crash_scene(Vector3(40.0, 0.0, 40.0))
	p.hp = 8.0
	car2.damage(9999.0)
	await e.frames(3)
	TestLib.check(Game.state == &"dead" and e.died_count == 1, "the blast killed the weakened driver (state %s)" % Game.state)
	TestLib.check(p.vehicle == null and mgr.driven == null and p.body.visible, "dead after the eject: not tied to the wreck, body visible")
	await e.secs(1.5)
	var cam := p.camera_rig.camera
	TestLib.check(p.camera_rig.mode == &"foot" and cam.global_position.is_finite() and cam.global_position.distance_to(p.global_position) < 9.0, "the death camera works after a vehicle death")
	hud.screen_age = 5.0
	TestLib.check(hud.press_button(&"respawn"), "and the respawn button works")
	await e.secs(0.5)
	_assert_on_foot("respawn after dying in a car")
	_alive_state()


func _respawn_with_vehicle() -> void:
	_alive_state()
	var car := await _crash_scene(Vector3(40.0, 0.0, 40.0))
	TestLib.check(p.vehicle == car, "driving before the respawn")
	Game.state = &"dead"
	Game.do_respawn()
	await e.frames(3)
	_assert_on_foot("respawn while the vehicle exists")
	TestLib.check(mgr.starter != null, "the starter car exists again after the respawn")
	# next sector while driving
	var car3 := await _crash_scene(Vector3(40.0, 0.0, 40.0))
	TestLib.check(p.vehicle != null and car3 != null, "driving before the next sector")
	Game.state = &"win"
	await e.frames(2)
	Game.do_next_sector()
	await e.frames(3)
	_assert_on_foot("next sector while driving")
	_alive_state()


func _camera_watchdog() -> void:
	_alive_state()
	# the car under the player is pooled away (hidden, inactive): the camera must not keep chasing it
	var car := await _crash_scene(Vector3(40.0, 0.0, 40.0))
	car.visible = false
	car.active = false
	await e.frames(3)
	_assert_on_foot("a driven car that vanished")
	# the car is freed while driven
	_alive_state()
	var car2 := await _crash_scene(Vector3(40.0, 0.0, 40.0))
	mgr.list.erase(car2)
	car2.queue_free()
	await e.frames(4)
	_assert_on_foot("a driven car that was freed")
	# the audit repairs a hidden body and a switched-off collider
	_alive_state()
	p.body.visible = false
	p.collision_layer = 0
	var fixed := stab.audit()
	TestLib.check(fixed.size() >= 2 and p.body.visible and p.collision_layer == Game.L_PLAYER, "the audit shows the body and restores the collider (%s)" % str(fixed))
	# shake caps
	FX.shake_amount = 50.0
	stab.audit()
	TestLib.check(FX.shake_amount <= 1.0, "an out-of-range shake is clamped by the audit")
	FX.shake_amount = 0.0
	# a broken camera position never blanks the picture
	p.camera_rig.global_position = Vector3(NAN, NAN, NAN)
	await e.frames(3)
	TestLib.check(p.camera_rig.camera.global_position.is_finite(), "a NaN pivot does not leave a NaN camera")
	p.camera_rig.snap()
	_alive_state()


func _pause_in_blast() -> void:
	_alive_state()
	await e.prep(Vector3(0.0, 0.0, 0.0), 0.0)
	Game.explode(Vector3(3.0, 0.0, 0.0), 9.0, {"player_dmg": 0.0})
	Game.state = &"paused"
	await e.secs(0.3)
	Game.state = &"play"
	await e.frames(3)
	TestLib.check(p.camera_rig.camera.global_position.is_finite() and Engine.time_scale == 1.0, "pause and resume during an explosion leave camera and time fine")
	await e.secs(0.5)
	TestLib.check(FX.shake_amount == 0.0, "the shake is gone after the pause")


func _auto_quality() -> void:
	var aq := AutoQuality.new()
	root.add_child(aq)
	await e.frames(2)
	_alive_state()
	Game.quality = 2
	var lowered: Array[int] = []
	aq.lowered.connect(func(l: int) -> void: lowered.append(l))
	aq._warm = 0.0
	aq._since_drop = 99.0
	RenderRes.user_mode = 0             # already at BALANCED: the governor has no resolution step left, it drops the tier (test_render_resolution covers the step)
	var dropped := false
	for i in 7:                               # 3.5 s of slow frames: not yet
		dropped = aq.tick(20.0, 0.5) or dropped
	TestLib.check(not dropped and Game.quality == 2, "3.5 s under 30 fps does not drop the tier")
	TestLib.check(aq.tick(20.0, 0.5) and Game.quality == 1 and lowered == [1], "4 s under 30 fps drops one tier (HIGH -> MED)")
	TestLib.check(aq.notice_left > 0.0, "a notice is shown")
	for i in 20:
		aq.tick(15.0, 0.5)
	TestLib.check(Game.quality == 1, "never twice within 10 s")
	aq._since_drop = 99.0
	for i in 8:
		aq.tick(15.0, 0.5)
	TestLib.check(Game.quality == 0, "after the gap another slow stretch drops to LOW")
	aq._since_drop = 99.0
	for i in 20:
		aq.tick(5.0, 0.5)
	TestLib.check(Game.quality == 0 and aq.drops == 2, "never below LOW")
	aq._since_drop = 99.0
	Game.quality = 2
	aq.tick(20.0, 3.0)
	aq.tick(60.0, 0.5)
	aq.tick(20.0, 3.0)
	TestLib.check(Game.quality == 2, "a good sample resets the slow timer")
	# touchscreen default
	var was_auto := Game.autostart
	var was_touch := Game.force_touch
	Game.autostart = false
	Game.force_touch = true
	TestLib.check(AutoQuality.wants_low_default(TMP), "touchscreen without a saved choice starts on LOW")
	var cfg := UiSettings.new(TMP)
	cfg.quality = 2
	cfg.save()
	TestLib.check(not AutoQuality.wants_low_default(TMP), "a saved tier choice wins over the LOW default")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	Game.force_touch = false
	TestLib.check(not AutoQuality.wants_low_default(TMP) or DisplayServer.is_touchscreen_available(), "a desktop keeps its tier")
	Game.autostart = was_auto
	Game.force_touch = was_touch
	Game.quality = 1
	aq.queue_free()
	RenderRes.user_mode = -1
	RenderRes.gov_mode = -1


func _error_log() -> void:
	Dev.errors.clear()
	push_error("stability-test-error-A")
	push_error("stability-test-error-A")
	await e.frames(2)
	var lines := Dev.error_lines()
	TestLib.check(lines.size() >= 1 and "stability-test-error-A" in lines[lines.size() - 1], "push_error lands in the on-device log (%s)" % str(lines))
	TestLib.check(lines.size() == 1 and lines[0].ends_with("x2"), "identical consecutive errors are merged")
	for i in 45:
		push_error("stability-test-flood %d" % i)
	await e.frames(2)
	TestLib.check(Dev.error_lines().size() == Dev.ERROR_LINES, "only the last %d lines are kept" % Dev.ERROR_LINES)
	Dev.flush_errors()
	var f := FileAccess.open(Dev.ERROR_FILE, FileAccess.READ)
	TestLib.check(f != null and "stability-test-flood 44" in f.get_as_text(), "the log is written to user://last_errors.txt")
	Dev.errors.clear()
	Dev.flush_errors()


func _touch_long_press(host: Node) -> void:
	_alive_state()
	var was_touch := Game.force_touch
	Game.force_touch = true
	var tc := (load("res://scenes/touch_controls.tscn") as PackedScene).instantiate() as TouchControls
	host.add_child(tc)
	await e.frames(2)
	var box := tc._perf_box()
	var q0 := Game.quality
	tc.touch_down(5, box.get_center())
	await e.secs(0.9)
	TestLib.check(tc.errors_on, "holding the FPS box opens the error panel")
	tc.touch_up(5)
	TestLib.check(Game.quality == q0 and tc.errors_on, "releasing a long press does not change the tier")
	tc.touch_down(5, box.get_center())
	await e.secs(0.9)
	tc.touch_up(5)
	TestLib.check(not tc.errors_on, "a second long press closes the panel")
	tc.touch_down(5, box.get_center())
	tc.touch_up(5)
	TestLib.check(Game.quality == (q0 + 1) % 3 and not tc.errors_on, "a short tap still cycles the tier")
	Game.set_quality(q0)
	tc.touch_down(1, Vector2(200.0, 600.0))
	tc.touch_move(1, Vector2(200.0, 500.0), Vector2(0.0, -100.0))
	TestLib.check(Input.is_action_pressed(&"move_forward"), "the stick drives while playing")
	Game.state = &"dead"
	TestLib.check(not Input.is_action_pressed(&"move_forward"), "dying lets the stick go")
	Game.state = &"play"
	tc.queue_free()
	Game.force_touch = was_touch
	await e.frames(2)


func _loading_and_menu(host: Node) -> void:
	var ov := LoadingOverlay.new()
	host.add_child(ov)
	await e.frames(3)
	TestLib.check(is_instance_valid(ov) and not ov.is_finishing(), "the loading overlay stays up while loading")
	ov.finish()
	await e.secs(0.7)
	TestLib.check(not is_instance_valid(ov), "the loading overlay removes itself after finish()")
	# the menu is light: world and atmosphere render at LOW and come back
	var w := StubTier.new()
	var a := StubTier.new()
	root.add_child(w)
	root.add_child(a)
	var old_w := Game.world
	var old_a := Game.atmosphere
	Game.world = w
	Game.atmosphere = a
	Game.quality = 2
	Game.state = &"menu"
	TestLib.check(w.q == 0 and a.q == 0, "the title screen renders at the LOW tier")
	Game.state = &"play"
	TestLib.check(w.q == 2 and a.q == 2, "playing restores the chosen tier")
	Game.world = old_w
	Game.atmosphere = old_a
	Game.quality = 1
	w.queue_free()
	a.queue_free()
	Game.set_quality(1)
	await e.frames(2)
