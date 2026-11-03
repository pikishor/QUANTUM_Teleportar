extends RefCounted
## First-use prompts: data, once-only display, saved marks, replay from OPTIONS, labels for keyboard and touch, no stale LINK wording. Ticked by hand.
## Run: tools/test.sh tests/test_onboarding.gd

const Env := preload("res://tests/player_env.gd")

var e := Env.new()


func run(host: Node) -> void:
	await e.setup(host)
	var story := (load("res://scenes/story.tscn") as PackedScene).instantiate() as Story
	e.root.add_child(story)
	var prog := Progress.new()
	e.root.add_child(prog)
	prog.autosave_enabled = false
	prog.cine_seen.clear()
	await e.frames(3)
	var fu: FirstUse = story.first_use
	fu.set_physics_process(false)
	story.tutorial.stop()
	fu.force = true
	TestLib.check(FirstUse.HINTS.size() == 10, "ten hints")
	for h in FirstUse.HINTS:
		TestLib.check(str(h["kb"]).length() <= 32 and str(h["touch"]).length() <= 32, "short label " + str(h["id"]))
	fu.touch_override = 0
	for i in 6:
		fu.tick(1.0)
	TestLib.check(fu.cur == 0 and fu.label() == "MOVE WITH W A S D", "move hint shown first")
	fu.touch_override = 1
	TestLib.check(fu.label() == "DRAG TO MOVE", "touch label")
	for i in 8:
		fu.tick(1.0)                     # timeout, quiet gap, next hint
	TestLib.check(fu.is_seen(&"move") and prog.cine_seen.has(&"hint_move"), "move marked seen")
	TestLib.check(fu.cur != 0, "move not shown twice")
	fu.replay()
	TestLib.check(not fu.is_seen(&"move") and fu.cur == -1, "replay clears the marks")
	var st := UiSettings.new()
	TestLib.check(OptionsScreen.is_option(&"opt_hints") and OptionsScreen.label(st, &"opt_hints") == "REPLAY HINTS", "options row")
	var bad := false
	for h in FirstUse.HINTS:
		bad = bad or str(h["kb"]).contains("LINK") or str(h["touch"]).contains("LINK")
	for d in StoryData.TUTORIAL:
		bad = bad or str(d["kb"]).contains("BLINK") or str(d["touch"]).contains("BLINK")
	TestLib.check(not bad, "no stale LINK wording")
	Game.progress = null
	await e.teardown()
