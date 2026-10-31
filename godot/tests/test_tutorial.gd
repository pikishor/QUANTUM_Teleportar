extends RefCounted
## Tutorial: data limits, the five steps (move, look, shoot, blink, enter a car) detected on the real Player, prompts that adapt to touch and keyboard, radio lines, skipping
## (Tab, the SKIP plate, skip()), the saved flag, first-launch rules and the Story integration (prologue -> tutorial, CONTINUE has none). Steps are ticked by hand.
## Run: tools/test.sh tests/test_tutorial.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

var e := Env.new()
var p: Player
var story: Story
var t: Tutorial
var prog: Progress
var finished: Array = []


func run(host: Node) -> void:
	seed(4)
	await e.setup(host)
	p = e.p
	Fixture.add_floor(e.root, 300.0)
	story = (load("res://scenes/story.tscn") as PackedScene).instantiate() as Story
	e.root.add_child(story)
	prog = Progress.new()
	e.root.add_child(prog)
	prog.autosave_enabled = false
	await e.frames(3)
	t = story.tutorial
	t.finished.connect(func(s: bool) -> void: finished.append(s))
	t.set_physics_process(false)            # the test ticks by hand (the physics process would also count camera snaps and teleports)

	_data()
	await _flow()
	await _skipping()
	_first_launch()
	await _story_integration()

	story.tutorial.stop()
	Game.progress = null
	await e.teardown()


func _data() -> void:
	TestLib.check(t != null and Game.story == story and story.tutorial == t, "the story layer owns the tutorial")
	var ids := ["move", "look", "shoot", "blink", "car"]
	var ok := t.step_count() == 5
	var limits := true
	for i in 5:
		var d: Dictionary = StoryData.TUTORIAL[i]
		ok = ok and str(d["id"]) == ids[i]
		for key in ["kb", "touch"] + (["kb2", "touch2"] if ids[i] == "blink" else []):
			limits = limits and str(d[key]).length() >= 8 and str(d[key]).length() <= StoryData.PROMPT_MAX and str(d[key]) == str(d[key]).to_upper()
		var l: Dictionary = d["done"]
		limits = limits and StoryData.SPEAKERS.has(str(l["s"])) and str(l["t"]).length() <= StoryData.LINE_MAX
	TestLib.check(ok, "five steps: move, look, shoot, blink, car")
	TestLib.check(limits, "every prompt fits %d characters (a phone plate) and every radio line the story limits" % StoryData.PROMPT_MAX)
	TestLib.check(not t.active and t.prompt() == "" and t.counter_text() == "", "idle: no prompt")
	t.tick(0.1)
	TestLib.check(not t.active, "an idle tutorial ignores ticks")


func _flow() -> void:
	await e.prep(Vector3(-30.0, 0.0, 4.0), PI * 0.5, 0.0)
	prog.tutorial_done = false
	Game.progress = prog
	t.touch_override = 0
	var steps: Array = []
	t.step_changed.connect(func(i: int) -> void: steps.append(i))
	t.begin()
	t.tick(0.1)
	TestLib.check(t.active and t.step == 0 and t.step_id() == "move" and t.prompt() == StoryData.TUTORIAL[0]["kb"], "begin: step 1, the keyboard prompt")
	TestLib.check(t.counter_text() == "TRAINING  1 / 5" and t.skip_hint() == StoryData.TUTORIAL_SKIP_KB, "counter and skip hint")
	t.touch_override = 1
	TestLib.check(t.prompt() == StoryData.TUTORIAL[0]["touch"] and t.skip_hint() == StoryData.TUTORIAL_SKIP_TOUCH, "the prompt follows touch mode")
	t.touch_override = 0
	# move: 5 m of walking; a teleport does not count
	t.tick(0.1)
	p.teleport_to(Vector3(-30.0, 0.05, 80.0))
	t.tick(0.1)
	TestLib.check(t.step == 0, "a 76 m jump (a teleport) does not count as walking")
	var z := 80.0
	for i in 2:
		z += 2.0
		p.teleport_to(Vector3(-30.0, 0.05, z))
		t.tick(0.1)
	TestLib.check(t.step == 0, "4 m walked: not enough yet")
	z += 2.0
	p.teleport_to(Vector3(-30.0, 0.05, z))
	t.tick(0.1)
	TestLib.check(t.step == 1 and t.step_id() == "look", "6 m walked: on to LOOK")
	var heard := false
	for l: Dictionary in story.queue:
		heard = heard or str(l["id"]) == "tutorial.move"
	for _i in 1:
		heard = heard or str(story.current.get("id", "")) == "tutorial.move"
	TestLib.check(heard, "ORACLE says the step's line")
	# look: 0.9 rad of camera turn
	p.camera_rig.reset_view(0.0, 0.0)
	await e.frames(2)
	t._reset_trackers()
	t.tick(0.1)
	p.camera_rig.reset_view(0.5, 0.0)
	await e.frames(2)
	t.tick(0.1)
	TestLib.check(t.step == 1, "0.5 rad of turning is not enough")
	p.camera_rig.reset_view(-0.1, 0.0)
	await e.frames(2)
	t.tick(0.1)
	TestLib.check(t.step == 2 and t.step_id() == "shoot", "turning about a radian in total moves on to SHOOT")
	# shoot: 3 shots
	p.weapon.reset()
	t.tick(0.1)
	Input.action_press(&"fire")
	await e.secs(0.1)
	t.tick(0.1)
	var shots := p.weapon.shots_fired
	TestLib.check(t.step == 2 or shots >= 3, "shooting starts counting")
	await e.secs(0.4)
	Input.action_release(&"fire")
	t.tick(0.1)
	TestLib.check(t.step == 3 and t.step_id() == "blink", "three shots move on to BLINK (%d fired)" % p.weapon.shots_fired)
	# blink: beacon first (the prompt changes), then the jump
	await e.prep(Vector3(-30.0, 0.0, 4.0), PI * 0.5, 0.0)
	p.energy = p.max_energy
	t.tick(0.1)
	TestLib.check(t.prompt() == StoryData.TUTORIAL[3]["kb"], "blink prompt, first half")
	var q := p.quantum as Quantum
	q.blink()
	t.tick(0.1)
	TestLib.check(t.step == 3 and t.prompt() == StoryData.TUTORIAL[3]["kb2"], "after the beacon the prompt asks for the jump")
	t.touch_override = 1
	TestLib.check(t.prompt() == StoryData.TUTORIAL[3]["touch2"], "...in touch words on a phone")
	t.touch_override = 0
	await e.secs(0.5)
	q.blink()
	t.tick(0.1)
	TestLib.check(t.step == 4 and t.step_id() == "car", "the teleport moves on to the CAR")
	# car: distance shown when a starter car exists; entering finishes
	var car := Fixture.add_vehicle(e.root, Vector3(-20.0, 0.0, 4.0))
	TestLib.check(t.prompt() == StoryData.TUTORIAL[4]["kb"], "car prompt (no vehicle manager: no distance)")
	t.tick(0.1)
	TestLib.check(t.active and t.step == 4, "walking around does not finish the car step")
	p.set(&"vehicle", car)
	t.tick(0.1)
	TestLib.check(not t.active and not t.skipped and finished == [false], "entering a vehicle finishes the training")
	TestLib.check(prog.tutorial_done, "and the save flag is set")
	TestLib.check(steps == [0, 1, 2, 3, 4], "step_changed fired for every step (%s)" % str(steps))
	TestLib.check(t.flash > 2.0 and t.prompt() == "", "the TRAINING COMPLETE flash runs, the prompt is gone")
	p.set(&"vehicle", null)
	car.queue_free()


func _skipping() -> void:
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	prog.tutorial_done = false
	finished.clear()
	t.begin()
	t.skip()
	TestLib.check(not t.active and t.skipped and finished == [true] and prog.tutorial_done, "skip() ends it and stores the flag")
	var q0 := story.queue.size()
	t.skip()
	TestLib.check(finished.size() == 1 and story.queue.size() == q0, "skipping twice does nothing")
	# Tab
	prog.tutorial_done = false
	finished.clear()
	t.begin()
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	t._input(key)
	TestLib.check(not t.active and finished == [true], "Tab skips")
	# tap on the SKIP plate
	t.begin()
	t.skip_rect = Rect2(200.0, 300.0, 90.0, 60.0)
	var miss := InputEventMouseButton.new()
	miss.button_index = MOUSE_BUTTON_LEFT
	miss.pressed = true
	miss.position = Vector2(600.0, 100.0)
	t._input(miss)
	TestLib.check(t.active, "a click elsewhere does not skip")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(230.0, 330.0)
	t._input(touch)
	TestLib.check(not t.active and t.skipped, "a tap on the SKIP plate skips")
	# not while paused
	t.begin()
	t.skip_rect = Rect2(200.0, 300.0, 90.0, 60.0)
	Game.state = &"paused"
	t._input(touch)
	TestLib.check(t.active, "a paused game does not take the tap")
	var moved := t.step
	p.teleport_to(Vector3(0.0, 0.05, 0.0))
	t._physics_process(0.1)
	p.teleport_to(Vector3(3.0, 0.05, 0.0))
	t._physics_process(0.1)
	TestLib.check(t.step == moved, "nothing is detected while paused")
	Game.state = &"play"
	t.skip()
	finished.clear()


func _first_launch() -> void:
	prog.tutorial_done = false
	TestLib.check(not t.maybe_start() and not t.active, "under tools, tests and bots (autostart) it never starts by itself")
	t.force = true
	prog.tutorial_done = true
	TestLib.check(not t.maybe_start() and not t.active, "a finished tutorial is never shown again")
	prog.tutorial_done = false
	TestLib.check(t.maybe_start() and t.active and t.step == 0, "a first launch starts it")
	t.stop()
	TestLib.check(not t.active, "stop() hides it without saving")
	TestLib.check(not prog.tutorial_done, "...and without storing the flag")
	t.force = false


func _story_integration() -> void:
	t.force = true
	prog.tutorial_done = false
	Game.state = &"menu"
	Game.start_new_game()
	TestLib.check(story.cards_active() and story.card_kind == &"prologue" and not t.active, "a new run plays the prologue first, not the tutorial")
	story.skip_cards()
	TestLib.check(t.active and t.step == 0, "when the prologue ends the tutorial starts")
	Game.new_game.emit()
	TestLib.check(not t.active, "a new game stops a running tutorial")
	story.skip_cards()
	t.stop()
	# continue: no prologue, no tutorial
	Game.state = &"menu"
	Game.start_new_game()
	story.set_chapter(2)
	TestLib.check(story.chapter == 2 and not story.cards_active() and not t.active, "set_chapter (CONTINUE) skips the prologue and the tutorial")
	TestLib.check(story.banner_visible() and story.shown.has("c3.intro"), "the chapter banner and intro still play")
	t.force = false
	# the real process polls on its own while playing
	Game.state = &"play"
	t.set_physics_process(true)
	t.begin()
	p.teleport_to(Vector3(0.0, 0.05, 0.0))
	await e.frames(3)
	for i in 5:
		p.teleport_to(Vector3(0.0, 0.05, 2.0 * (i + 1)))
		await e.frames(2)
	TestLib.check(t.step >= 1, "the physics process detects walking by itself (step %d)" % t.step)
	t.stop()
	t.set_physics_process(false)
