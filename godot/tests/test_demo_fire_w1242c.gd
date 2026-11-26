extends RefCounted
## w1242-critic: in DEMO mode the very first FIRE taps did nothing. The campaign's prologue cards started with the demo's sandbox run and every finger anywhere
## (FIRE included) only flipped a card: two FIRE holds of 1.5 s fired 0 shots. Real main scene, real finger events, phone layers on (CrateReveal._quiet = 0).
## Checks: no prologue card is up after DEMO starts, and the first FIRE hold (finger on the FIRE circle) fires the gun.
## Run: tools/test.sh tests/test_demo_fire_w1242c.gd   (W1242C_OLD=1: the old behaviour, both checks fail)
const TIMEOUT_SECONDS := 200
const Fingers := preload("res://tests/w116_fingers.gd")
func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	CrateReveal._quiet = 0
	TestMode.reset_toggles()
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 20)
	Game.state = &"menu"
	TestLib.check(DemoMode.enter(), "demo mode is on")
	await TestLib.frames(host, 10)
	Game.state = &"play"
	await TestLib.frames(host, 4)
	var story := host.get_tree().root.find_children("*", "Story", true, false)
	var cards := 0 if story.is_empty() else (story[0] as Story).cards.size()
	TestLib.check(cards == 0, "no campaign prologue card is up in the demo sandbox (%d cards)" % cards)
	var fg := Fingers.new(host)
	var p := Game.player as Player
	var s0 := p.weapon.shots_fired
	var ok := fg.press(3, &"fire")
	await TestLib.frames(host, 40)
	fg.up(3)
	await TestLib.frames(host, 4)
	TestLib.check(ok and p.weapon.shots_fired > s0, "the first FIRE hold by a finger fires the gun (%d shots)" % (p.weapon.shots_fired - s0))
	DemoMode.quit()
	TestMode.reset_toggles()
	CrateReveal._quiet = -1
	Game.force_touch = false
	main.queue_free()
	await TestLib.frames(host, 2)
