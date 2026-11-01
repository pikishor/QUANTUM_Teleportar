extends RefCounted
## Cinematics: scene plans (data, timing, subtitles), sequencing of the intro / chapter / boss scenes, skip, restore of camera / hero / grade / time scale / state after
## a skip, an interruption and a pause, the settings toggle, the title and shop camera, the dead / win bars, the watchdog rules, and no node growth over repeated scenes.
## Run: tools/test.sh tests/test_cinematic.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const TMP := "user://cinematic_test.cfg"

class StubWorld extends Node3D:
	func ground_height(x: float, z: float, _from_y := 1.0e9) -> float:
		return 32.0 if (x > 40.0 and x < 90.0 and z > -40.0 and z < 40.0) else 0.0

var e := Env.new()
var p: Player
var rig: CameraRig
var atmo: Atmosphere
var hud: Hud
var stab: Stability
var story: Story
var cine: Cinematics


func _frames(n: int) -> void:
	await e.frames(n)


func _grade_ok(orig: Dictionary) -> bool:
	for k: StringName in orig:
		if atmo.post.get_param(k) != orig[k]:
			return false
	return true


func _plans() -> void:
	var intro := CinePlan.intro({"roof": Vector3(60, 30, 0), "roof_face": Vector3.LEFT, "spawn": Vector3(-30, 0, 4), "spawn_face": Vector3.RIGHT})
	TestLib.check(intro.duration >= 22.0 and intro.duration <= 28.0, "the intro lasts about 25 s (%.1f)" % intro.duration)
	TestLib.check(intro.shots.size() >= 4 and intro.drones.size() >= 3, "the intro has several shots and drone props")
	var finite := true
	var t := 0.0
	var last := Vector3.ZERO
	var max_step := 0.0
	while t < intro.duration:
		intro.sample(t)
		finite = finite and intro.cam_pos.is_finite() and intro.cam_look.is_finite() and intro.cam_fov > 20.0 and intro.cam_fov < 120.0 and intro.cam_transform().basis.is_finite()
		if t > 0.0 and intro.shot_index == 0:
			max_step = maxf(max_step, intro.cam_pos.distance_to(last))
		last = intro.cam_pos
		t += 0.05
	TestLib.check(finite, "every sampled camera pose of the intro is finite")
	TestLib.check(max_step < 6.0, "the skyline fly-through moves smoothly (largest 50 ms step %.2f m)" % max_step)
	TestLib.check(intro.flash_at(19.8) > 0.99 and intro.flash_at(0.0) == 0.0 and intro.flash_at(24.9) < 0.01, "the rift flash peaks at 19.8 s and is gone by the title")
	TestLib.check(intro.title_alpha(22.5) > 0.9 and intro.title_alpha(5.0) == 0.0, "the title card shows after the flash")
	TestLib.check(intro.events.size() == 1 and float(intro.events[0]["t"]) < intro.duration, "the teleport event sits inside the scene")
	for s: Dictionary in CineData.all_subs():
		TestLib.check(str(s["t"]).length() <= StoryData.LINE_MAX and StoryData.SPEAKERS.has(str(s["s"])), "subtitle fits and has a known speaker: %s" % str(s["t"]).substr(0, 24))
	for s: Dictionary in CineData.INTRO_SUBS:
		TestLib.check(float(s["t1"]) <= intro.duration and float(s["t0"]) < float(s["t1"]), "intro subtitle timing is inside the scene")
	var ch := CinePlan.chapter({"hero": Vector3.ZERO, "face": Vector3.RIGHT, "label": "CHAPTER 2", "title": "X", "sub": "Y", "obj": "Z"})
	TestLib.check(ch.duration >= 5.0 and ch.duration <= 8.0, "the chapter scene lasts 5-8 s (%.1f)" % ch.duration)
	var bi := CinePlan.boss_in({"boss": Vector3(50, 0, 0), "hero": Vector3.ZERO, "face": Vector3.RIGHT})
	var bo := CinePlan.boss_out({"boss": Vector3(50, 0, 0), "hero": Vector3.ZERO})
	TestLib.check(bi.duration < 6.0 and bo.duration < 6.0 and bo.slowmo and not bi.slowmo, "the boss beats are short; only the defeat uses slow motion")
	var fov := PackedFloat32Array([0.0])
	var tp := CinePlan.title_pose(12.0, Vector3(-30, 0, 4), Vector3.RIGHT, fov)
	TestLib.check(tp.origin.is_finite() and fov[0] > 40.0, "the title pose is finite")
	var cp := CinePlan.closeup_pose(3.0, Vector3.ZERO, Vector3.RIGHT, fov)
	TestLib.check(cp.origin.is_finite() and cp.origin.distance_to(Vector3(0, 1.2, 0)) < 3.5, "the shop close-up sits near the hero")
	var sp0 := CinePlan.spline(PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(2, 0, 0)]), 0.0)
	var sp1 := CinePlan.spline(PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(2, 0, 0)]), 1.0)
	TestLib.check(sp0.is_equal_approx(Vector3.ZERO) and sp1.is_equal_approx(Vector3(2, 0, 0)), "a spline starts and ends on its control points")


func run(host: Node) -> void:
	seed(5)
	await _plans()
	await e.setup(host)
	p = e.p
	rig = p.camera_rig
	Fixture.add_floor(e.root, 400.0)
	atmo = (load("res://scenes/atmosphere.tscn") as PackedScene).instantiate() as Atmosphere
	e.root.add_child(atmo)
	hud = (load("res://scenes/hud.tscn") as PackedScene).instantiate() as Hud
	hud.settings_path = TMP
	e.root.add_child(hud)
	story = (load("res://scenes/story.tscn") as PackedScene).instantiate() as Story
	e.root.add_child(story)
	stab = Stability.new()
	e.root.add_child(stab)
	cine = Cinematics.new()
	e.root.add_child(cine)
	cine.enabled = true
	await _frames(6)
	TestLib.check(Engine.time_scale == 1.0, "the run starts at time scale 1")
	var orig := {}
	for k in Cinematics.GRADE_KEYS:
		orig[k] = atmo.post.get_param(k)
	var spawn := Vector3(-30.0, 0.0, 4.0)

	# --- the intro, played through the sequence --------------------------------------------------------------------------------
	e.prep(spawn)
	await _frames(4)
	TestLib.check(cine.play(&"intro"), "the intro starts from play")
	TestLib.check(Game.state == Cinematics.STATE and cine.active and cine.active_id == &"intro", "state cutscene while it runs")
	TestLib.check(not cine.play(&"chapter"), "a second scene cannot start on top of the first")
	await _frames(3)
	TestLib.check(rig.is_cinematic(), "the camera is driven by the scene")
	TestLib.check(p.global_position.y > 5.0, "Kestrel is up on the roof (%.1f)" % p.global_position.y)
	TestLib.check(not hud._hud.visible and not hud._screen.visible and hud.layers_consistent(), "the HUD hides both layers during a scene")
	TestLib.check(cine.prop_count() >= 3, "the drone props exist (%d)" % cine.prop_count())
	TestLib.check(atmo.post.get_param(&"vignette_amount") != orig[&"vignette_amount"] or cine.t < 0.1, "the grade shifts during the scene")
	cine.t = 19.7
	await _frames(12)
	TestLib.check(p.global_position.distance_to(spawn) < 0.5, "after the rift flash Kestrel is back in the street (%s)" % p.global_position)
	cine.t = 24.6
	await _frames(40)
	TestLib.check(not cine.active and Game.state == &"play", "the intro ends by itself and returns to play")
	await _frames(20)
	TestLib.check(not rig.is_cinematic(), "the camera is the gameplay camera again")
	TestLib.check(_grade_ok(orig), "the grade is back to its saved values")
	TestLib.check(hud.settings.intro_seen, "the intro is remembered as seen")
	TestLib.check(Engine.time_scale == 1.0 and hud._hud.visible, "time scale and HUD restored")

	# --- skip --------------------------------------------------------------------------------------------------------------------
	e.prep(spawn)
	var yaw0 := rig.yaw
	cine.play(&"intro")
	await _frames(3)
	cine.skip()
	TestLib.check(cine.active, "a tap before 0.45 s is ignored")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	cine.t = 3.0
	cine._input(ev)
	TestLib.check(not cine.active and Game.state == &"play" and cine.skipped, "a tap skips the intro")
	TestLib.check(p.global_position.distance_to(spawn) < 0.5, "a skipped intro puts Kestrel back in the street")
	TestLib.check(absf(rig.yaw - yaw0) < 0.05, "the look angles are restored (%.2f vs %.2f)" % [rig.yaw, yaw0])
	await _frames(20)
	TestLib.check(not rig.is_cinematic() and _grade_ok(orig), "camera and grade restored after a skip")

	# --- interruption: pause, death, menu in the middle of a scene -----------------------------------------------------------
	for st: StringName in [&"paused", &"dead", &"menu"]:
		e.prep(spawn)
		cine.play(&"chapter")
		await _frames(3)
		Game.state = st
		await _frames(3)
		TestLib.check(not cine.active, "a state change to %s ends the scene" % st)
		Game.state = &"play"
		await _frames(20)
		TestLib.check(not rig.is_cinematic() and _grade_ok(orig) and Engine.time_scale == 1.0, "after an interruption by %s everything is restored" % st)
	e.prep(spawn)
	cine.play(&"intro")
	await _frames(3)
	Game.state = &"paused"
	await _frames(3)
	TestLib.check(p.global_position.distance_to(spawn) < 0.5, "an intro interrupted by a pause puts Kestrel back in the street")
	Game.state = &"play"
	await _frames(20)

	# --- watchdog: the camera pose lapses, a stuck cutscene state is repaired ----------------------------------------------
	rig.cine_set(Transform3D(Basis.IDENTITY, Vector3(0, 500, 0)), 70.0)
	await _frames(40)
	TestLib.check(not rig.is_cinematic(), "a scripted camera pose lapses by itself")
	cine.active = false
	Game.state = &"cutscene"
	var fixed := stab.audit()
	TestLib.check(Game.state == &"play" and fixed.size() > 0, "a cutscene state with no running scene is repaired")

	# --- chapter scene and banner ---------------------------------------------------------------------------------------------
	e.prep(spawn)
	story.banner_t = 0.0
	TestLib.check(cine.play(&"chapter"), "the chapter scene starts")
	cine.t = cine.plan.duration - 0.2
	await _frames(30)
	TestLib.check(not cine.active and Game.state == &"play" and story.banner_t < 0.0, "the chapter scene ends and hands over without a second title banner")

	# --- boss beats: slow motion restored -------------------------------------------------------------------------------------
	e.prep(spawn)
	TestLib.check(cine.play(&"boss_in", {"boss": Vector3(60, 0, 4)}), "the boss intro starts")
	await _frames(3)
	cine.t = 1.0
	cine.skip()
	await _frames(10)
	TestLib.check(Game.state == &"play" and Engine.time_scale == 1.0, "the boss intro skips cleanly")
	TestLib.check(cine.play(&"boss_out", {"boss": Vector3(60, 0, 4)}), "the boss defeat starts")
	await _frames(4)
	TestLib.check(Engine.time_scale < 0.6, "slow motion during the defeat beat (%.2f)" % Engine.time_scale)
	cine.t = 1.0
	cine.skip()
	await _frames(6)
	TestLib.check(Engine.time_scale == 1.0 and Game.state == &"play", "the slow motion ends with the scene")
	TestLib.check(cine.play(&"boss_out", {"boss": Vector3(60, 0, 4)}), "the defeat beat again")
	await _frames(3)
	Game.state = &"dead"
	await _frames(3)
	Game.state = &"play"
	await _frames(12)
	TestLib.check(Engine.time_scale > 0.99, "an interrupted slow-motion scene leaves no slowed time (%.2f)" % Engine.time_scale)

	# --- settings toggle and the DEPLOY path -----------------------------------------------------------------------------------
	hud.settings.cutscenes = false
	hud.settings.intro_seen = false
	TestLib.check(not cine.scenes_allowed(), "the settings toggle disables scenes")
	Game.state = &"menu"
	await _frames(4)
	Game.start_new_game()
	await _frames(3)
	TestLib.check(Game.state == &"play" and not cine.active, "DEPLOY goes straight to play with cutscenes off")
	TestLib.check(hud.press_button(&"deploy") == false, "(deploy only works from the menu)")
	hud.settings.cutscenes = true
	Game.state = &"menu"
	await _frames(4)
	Game.start_new_game()
	await _frames(3)
	TestLib.check(cine.active and cine.active_id == &"intro" and Game.state == Cinematics.STATE, "the first DEPLOY plays the intro")
	cine.t = 2.0
	cine.skip()
	await _frames(20)
	TestLib.check(Game.state == &"play" and hud.settings.intro_seen, "the skipped intro hands over to play")
	Game.state = &"menu"
	await _frames(4)
	Game.start_new_game()
	await _frames(3)
	TestLib.check(not cine.active and Game.state == &"play", "the intro plays only once")
	var before_toggle := hud.settings.cutscenes
	Game.state = &"menu"
	await _frames(4)
	hud._layout_key = ""
	hud._ensure_layout()
	TestLib.check(hud.press_button(&"cine") and hud.settings.cutscenes != before_toggle, "the CINE button toggles cutscenes")
	hud.settings.cutscenes = true
	Game.state = &"play"
	await _frames(4)

	# --- title screen, shop close-up, dead / win bars ---------------------------------------------------------------------------
	e.prep(spawn)
	Game.state = &"menu"
	await _frames(8)
	TestLib.check(rig.is_cinematic(), "the title screen has its own camera")
	var dist := rig.camera.global_position.distance_to(p.global_position)
	TestLib.check(dist > 1.0 and dist < 9.0, "the title camera sits close behind Kestrel (%.1f m)" % dist)
	TestLib.check(cine._title_props and cine._used.size() == Cinematics.TITLE_DRONES, "drones cross the title sky")
	Game.state = &"play"
	await _frames(4)
	TestLib.check(not rig.is_cinematic() and not cine._title_props, "leaving the title returns the camera and hides the props")
	Game.state = &"paused"
	hud._shop_open = true
	await _frames(6)
	TestLib.check(rig.is_cinematic() and hud.shop_open(), "the shop screen frames a hero close-up")
	TestLib.check(rig.camera.global_position.distance_to(p.global_position + Vector3(0, 1.2, 0)) < 5.0, "the close-up camera is near the hero")
	hud._shop_open = false
	await _frames(40)
	TestLib.check(not rig.is_cinematic(), "closing the shop releases the camera")
	Game.state = &"play"
	await _frames(4)
	Game.state = &"dead"
	await _frames(30)
	TestLib.check(cine._bars > 0.01, "the dead screen gets letterbox bars (%.3f)" % cine._bars)
	Game.state = &"play"
	await _frames(3)
	TestLib.check(cine._fade > 0.3, "respawning fades in from black")
	await _frames(70)
	TestLib.check(cine._fade < 0.01, "the fade is gone")

	# --- no node growth -------------------------------------------------------------------------------------------------------------
	e.prep(spawn)
	for i in 2:
		cine.play(&"intro")
		await _frames(3)
		cine.t = 1.0
		cine.skip()
		cine.play(&"chapter")
		await _frames(3)
		cine.t = 1.0
		cine.skip()
		await _frames(6)
	var nodes0 := host.get_tree().get_node_count()
	var props0 := cine.prop_count()
	for i in 3:
		cine.play(&"intro")
		await _frames(3)
		cine.t = 1.0
		cine.skip()
		cine.play(&"boss_in", {"boss": Vector3(60, 0, 4)})
		await _frames(3)
		cine.t = 1.0
		cine.skip()
		await _frames(6)
	TestLib.check(host.get_tree().get_node_count() == nodes0 and cine.prop_count() == props0, "no node growth over repeated scenes (%d -> %d nodes, %d props)" % [nodes0, host.get_tree().get_node_count(), cine.prop_count()])
	TestLib.check(Engine.time_scale == 1.0 and Game.state == &"play" and not rig.is_cinematic(), "everything is restored at the end")

	# --- roof search ---------------------------------------------------------------------------------------------------------------
	var sw := StubWorld.new()
	e.root.add_child(sw)
	var old_world := Game.world
	Game.world = sw
	var roof := cine._find_roof(spawn, Vector3.RIGHT)
	TestLib.check(roof.y == 32.0 and roof.x > 40.0 and roof.x < 90.0, "the roof search finds the flat high roof (%s)" % roof)
	Game.world = old_world

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	Game.state = &"play"
	e.root.queue_free()
	await _frames(2)
	Fixture.release_inputs()
	Game.state = &"menu"
	Game.atmosphere = null
	Sfx.muted = false
