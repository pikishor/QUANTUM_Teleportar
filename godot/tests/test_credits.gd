extends RefCounted
## The ending: the "credits" CinePlan (timing, camera, blocks, subtitles), and the flow after the final chapter: end card -> ending cards (CampaignData.ENDING) over the win screen ->
## NEXT SECTOR -> the credits cinematic (skippable by a tap, restores camera / state / grade / time scale, plays only after the last chapter and only when cutscenes are on).
## Run: tools/test.sh tests/test_credits.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const TMP := "user://credits_test.cfg"

var e := Env.new()
var p: Player
var rig: CameraRig
var atmo: Atmosphere
var hud: Hud
var story: Story
var cine: Cinematics


func _frames(n: int) -> void:
	await e.frames(n)


func _plan() -> void:
	var plan := CinePlan.credits_scene({"hero": Vector3(-30, 0, 4), "face": Vector3.RIGHT})
	var blocks := CampaignData.CREDITS.size()
	TestLib.check(plan.id == &"credits" and plan.skippable and not plan.slowmo, "the credits plan is a skippable scene")
	TestLib.check(is_equal_approx(plan.duration, CampaignData.CREDITS_BLOCK_SECONDS * blocks), "it lasts one slot per credits block (%.1f s for %d blocks)" % [plan.duration, blocks])
	TestLib.check(plan.duration >= 15.0 and plan.duration <= 40.0, "a credits scene of a sensible length (%.1f s)" % plan.duration)
	TestLib.check(plan.shots.size() >= 3 and plan.shots[0].t0 == 0.0 and is_equal_approx(plan.shots[plan.shots.size() - 1].t1, plan.duration), "the shots cover the scene from 0 to its end")
	var contiguous := true
	for i in range(1, plan.shots.size()):
		contiguous = contiguous and is_equal_approx(plan.shots[i].t0, plan.shots[i - 1].t1)
	TestLib.check(contiguous, "the shots follow each other without a gap")
	var finite := true
	var max_step := 0.0
	var last := Vector3.ZERO
	var last_shot := -1
	var t := 0.0
	while t < plan.duration:
		plan.sample(t)
		finite = finite and plan.cam_pos.is_finite() and plan.cam_look.is_finite() and plan.cam_fov > 20.0 and plan.cam_fov < 120.0 and plan.cam_transform().basis.is_finite()
		if plan.shot_index == last_shot:                       # a cut between two shots is a cut, not a jump
			max_step = maxf(max_step, plan.cam_pos.distance_to(last))
		last = plan.cam_pos
		last_shot = plan.shot_index
		t += 0.05
	TestLib.check(finite, "every sampled camera pose is finite")
	TestLib.check(max_step < 3.0, "the orbits move smoothly (largest 50 ms step %.2f m)" % max_step)
	# the hero is the subject of the first shot and never behind the camera by accident
	plan.sample(0.5)
	TestLib.check(plan.cam_pos.distance_to(Vector3(-30, 0, 4)) < 8.0 and plan.cam_pos.y > 0.5, "the first shot is a close portrait of Kestrel")
	# the credit blocks: one at a time, each fades in and out inside its slot, none outside the scene
	var each_seen := true
	for i in blocks:
		var mid := (float(i) + 0.5) * plan.credit_seconds
		each_seen = each_seen and plan.credit_index(mid) == i and plan.credit_alpha(mid) > 0.95
	TestLib.check(each_seen, "every block is shown, fully visible in the middle of its slot")
	var edges := true
	for i in blocks:
		edges = edges and plan.credit_alpha(float(i) * plan.credit_seconds) < 0.01 and plan.credit_alpha(float(i + 1) * plan.credit_seconds - 0.001) < 0.05
	TestLib.check(edges, "blocks are dark at their slot edges, so two never overlap")
	TestLib.check(plan.credit_index(plan.duration + 0.5) == -1 and plan.credit_alpha(plan.duration + 0.5) == 0.0 and plan.credit_index(-1.0) == -1, "nothing is shown outside the scene")
	TestLib.check(CinePlan.chapter({"hero": Vector3.ZERO, "face": Vector3.RIGHT}).credit_index(1.0) == -1, "the other scenes have no credits blocks")
	var subs_ok := plan.subs.size() >= 2
	for s: Dictionary in plan.subs:
		subs_ok = subs_ok and float(s["t0"]) < float(s["t1"]) and float(s["t1"]) <= plan.duration and StoryData.SPEAKERS.has(str(s["s"])) and str(s["t"]).length() <= StoryData.LINE_MAX
	TestLib.check(subs_ok, "the credits subtitles are inside the scene, known speakers, within the line limit")
	TestLib.check(plan.drones.size() >= 1 and plan.drone_pos(0, 3.0).is_finite(), "silent Observers hang over the avenue")
	TestLib.check("credits" in Cinematics.ENDING_SCENES and "credits" in CampaignData.KNOWN_CUTSCENES, "'credits' is a known ending scene of the campaign data")


func run(host: Node) -> void:
	seed(7)
	_plan()
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
	var stab := Stability.new()
	e.root.add_child(stab)
	cine = Cinematics.new()
	e.root.add_child(cine)
	cine.enabled = true
	await _frames(6)
	var orig := {}
	for k in Cinematics.GRADE_KEYS:
		orig[k] = atmo.post.get_param(k)
	var spawn := Vector3(-30.0, 0.0, 4.0)
	hud.settings.cutscenes = true

	# --- the scene itself, from play ------------------------------------------------------------------------------------------------
	e.prep(spawn)
	await _frames(4)
	TestLib.check(cine.play(&"credits"), "the credits start from play")
	TestLib.check(Game.state == Cinematics.STATE and cine.active_id == &"credits" and cine.plan.id == &"credits", "state cutscene while they run")
	await _frames(4)
	TestLib.check(rig.is_cinematic(), "the camera is driven by the scene")
	TestLib.check(not hud._hud.visible and not hud._screen.visible, "the HUD hides during the credits")
	TestLib.check(cine.prop_count() >= 1, "the drone props exist (%d)" % cine.prop_count())
	for t in [1.0, 5.0, 9.5, 14.0, 19.0, 21.0]:
		cine.t = t
		await _frames(3)
		TestLib.check(cine.active and rig.is_cinematic(), "the scene is still running at %.1f s" % t)
	cine.t = cine.plan.duration - 0.1
	await _frames(40)
	TestLib.check(not cine.active and Game.state == &"play", "the credits end by themselves and return to play")
	await _frames(20)
	TestLib.check(not rig.is_cinematic() and Engine.time_scale == 1.0 and hud._hud.visible, "camera, time scale and HUD are back")
	var back := true
	for k: StringName in orig:
		back = back and atmo.post.get_param(k) == orig[k]
	TestLib.check(back, "the grade is back to its saved values")
	TestLib.check(cine.prop_count() >= 1 and cine._used.is_empty(), "the props are hidden again (pooled, not freed)")

	# --- skip by tap ------------------------------------------------------------------------------------------------------------------
	e.prep(spawn)
	cine.play(&"credits")
	await _frames(3)
	cine.skip()
	TestLib.check(cine.active, "a tap before 0.45 s is ignored")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	cine.t = 6.0
	cine._input(ev)
	TestLib.check(not cine.active and cine.skipped and Game.state == &"play", "a tap skips the credits")
	await _frames(20)
	TestLib.check(not rig.is_cinematic() and Engine.time_scale == 1.0, "camera restored after the skip")
	var tev := InputEventScreenTouch.new()
	tev.pressed = true
	e.prep(spawn)
	cine.play(&"credits")
	await _frames(3)
	cine.t = 2.0
	cine._input(tev)
	TestLib.check(not cine.active and cine.skipped, "a touch skips the credits as well")
	await _frames(20)

	# --- interruption: pause in the middle -------------------------------------------------------------------------------------------
	e.prep(spawn)
	cine.play(&"credits")
	await _frames(3)
	Game.state = &"paused"
	await _frames(3)
	TestLib.check(not cine.active, "a pause ends the credits")
	Game.state = &"play"
	await _frames(20)
	TestLib.check(not rig.is_cinematic() and Engine.time_scale == 1.0, "everything is restored after the interruption")

	# --- the flow after the final chapter ---------------------------------------------------------------------------------------------
	cine.plays = 0
	story.enabled = true
	story.chapter = StoryData.FINAL
	e.prep(spawn)
	Game.state = &"win"
	Game.sector_cleared.emit()
	TestLib.check(cine._ending_id == &"credits", "clearing the final chapter remembers the ending scene")
	story.advance(Story.EPILOGUE_DELAY + 0.1)
	TestLib.check(story.cards_active() and story.card_kind == &"epilogue", "the ending cards follow the final end card")
	var heads: Array[String] = []
	for c: Dictionary in story.cards:
		heads.append(str(c["head"]))
	var want: Array[String] = []
	for c: Dictionary in CampaignData.ENDING:
		want.append(str(c["head"]))
	TestLib.check(heads == want, "the cards are the campaign's ending cards (%s)" % ", ".join(heads))
	TestLib.check(not cine.active, "no scene runs over the win screen")
	story.skip_cards()
	TestLib.check(story.epilogue_seen and not story.cards_active(), "the ending cards finish")
	await _frames(4)
	TestLib.check(not cine.active and Game.state == &"win", "the credits wait for NEXT SECTOR")
	Game.do_next_sector()
	await _frames(4)
	TestLib.check(cine.active and cine.active_id == &"credits" and Game.state == Cinematics.STATE, "NEXT SECTOR after the last chapter plays the credits")
	TestLib.check(cine._ending_id == &"", "the ending is consumed")
	cine.t = 5.0
	cine._input(ev)
	await _frames(20)
	TestLib.check(not cine.active and Game.state == &"play" and not rig.is_cinematic(), "the credits end in the aftermath sector, in play")
	TestLib.check(story.chapter == StoryData.FINAL + 1, "the story moved on to the aftermath chapter")
	TestLib.check(cine.plays == 1, "exactly one scene played")

	# the next sector after the aftermath is the plain chapter scene, never the credits again
	story.chapter = StoryData.FINAL + 1
	Game.state = &"win"
	Game.sector_cleared.emit()
	TestLib.check(cine._ending_id == &"", "an endless sector has no ending scene")
	Game.do_next_sector()
	await _frames(4)
	TestLib.check(cine.active and cine.active_id == &"chapter", "the next sector plays the chapter scene (%s)" % cine.active_id)
	cine.t = 2.0
	cine.skip()
	await _frames(20)

	# an earlier chapter ends with the chapter scene as before
	story.chapter = 2
	Game.state = &"win"
	Game.sector_cleared.emit()
	TestLib.check(cine._ending_id == &"", "a middle chapter has no ending scene")
	Game.do_next_sector()
	await _frames(4)
	TestLib.check(cine.active and cine.active_id == &"chapter", "a middle chapter is followed by the chapter scene")
	cine.t = 2.0
	cine.skip()
	await _frames(20)

	# cutscenes off: the cards play, the credits do not
	hud.settings.cutscenes = false
	story.chapter = StoryData.FINAL
	Game.state = &"win"
	Game.sector_cleared.emit()
	Game.do_next_sector()
	await _frames(6)
	TestLib.check(not cine.active and Game.state == &"play" and cine._ending_id == &"", "with CINE OFF the credits are skipped and the game just goes on")
	hud.settings.cutscenes = true

	# a new run forgets a pending ending
	story.chapter = StoryData.FINAL
	Game.state = &"win"
	Game.sector_cleared.emit()
	TestLib.check(cine._ending_id == &"credits", "(ending armed again)")
	Game.state = &"menu"
	await _frames(2)
	Game.start_new_game()
	await _frames(3)
	TestLib.check(cine._ending_id == &"", "a new game clears the pending ending")
	if cine.active:
		cine.t = 3.0
		cine.skip()
		await _frames(20)

	# no node growth over repeated scenes
	var props := cine.prop_count()
	for i in 3:
		e.prep(spawn)
		cine.play(&"credits")
		await _frames(3)
		cine.t = 3.0
		cine.skip()
		await _frames(10)
	TestLib.check(cine.prop_count() == props and Game.state == &"play" and Engine.time_scale == 1.0, "repeated credits add no props (%d)" % cine.prop_count())

	# teardown
	hud.settings.cutscenes = true
	Game.state = &"menu"
	await _frames(2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	await e.teardown()
