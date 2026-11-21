extends RefCounted
## THE TOUCH AUDIT as a bot with pictures (wave 116): the same engine as tests/test_touch_audit*.gd (tests/touch_audit_lib.gd), in the rendered game at phone aspect. It walks the
## title and the pause menu by finger, holds every HUD button on foot and with MORE open, opens both wheels, and saves one PNG per screen with the table of controls on stdout.
##   TA_OUT=<dir> BOT_RES=1200x540 BOT_USER_ARGS="--touch" BOT_TIMEOUT=600 tools/bot.sh res://tests/bot_touch_audit.gd /tmp/x 100000 1
## TA_PARTS (comma list, default all): title, pause, hud, wheels, map. TA_EXTRAS=1 turns ALL EXTRAS on for the pause walk.
const Audit := preload("res://tests/touch_audit_lib.gd")
const SCRIPTED := ["deploy", "continue", "demo", "menu", "resume", "opt_reset", "opt_reset_demo", "opt_bench", "photo_open", "pause_map", "board_story"]
var _started := false
var _done := false


func step(_t: float, _dt: float) -> bool:
	if _started:
		return _done
	var tree := Engine.get_main_loop() as SceneTree
	if tree.get_first_node_in_group(&"hud") == null or not is_instance_valid(Game.player):
		return false
	_started = true
	_run(tree)
	return false


func _run(tree: SceneTree) -> void:
	var a := Audit.new()
	a.shot_dir = OS.get_environment("TA_OUT")
	if a.shot_dir != "":
		DirAccess.make_dir_recursive_absolute(a.shot_dir)
	for q in tree.root.find_children("*", "AutoQuality", true, false):
		(q as AutoQuality).enabled = false
	if not await a.boot(tree.root, "bot", false):
		print("TOUCH AUDIT BOT: no HUD")
		tree.quit()
		return
	var parts := OS.get_environment("TA_PARTS").split(",", false)
	var prog := Game.progress as Progress
	prog.autosave_enabled = false
	var snap := a.settings_snapshot()
	var restore := func() -> void:
		a.settings_restore(snap)
		prog.credits = 50000
		Arsenal._st.clear()
	if parts.is_empty() or parts.has("title"):
		await a.crawl(&"menu", "title", SCRIPTED, 3, restore)
	prog.new_campaign()
	Game.state = &"play"
	await a.frames(30)
	var p := Game.player as Player
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	(Game.enemies as EnemyManager).clear()
	if parts.is_empty() or parts.has("hud"):
		await a.press_hud_frame("hud_foot")
		await a.tap_hud("more")
		await a.press_hud_frame("hud_foot_more")
		await a.tap_hud("more")
	if parts.is_empty() or parts.has("wheels"):
		a.fast_tap(a.centre_of(a.hud_button("ability")))              # a quick tap leaves the wheel open (a software-rendered frame is longer than the tap limit)
		await a.frames(3)
		for g in a.geometry("wheel_ability", a.touch_controls()):
			a.finding(g)
		await a.shot("wheel_ability")
		a.tc.release_all()
		a.finger_down(a.centre_of(a.hud_button("swap")))
		await a.until(func() -> bool: return a.tc.wheel.is_open, 600)
		await a.shot("wheel_weapon")
		a.finger_up()
		a.tc.release_all()
	if parts.is_empty() or parts.has("map"):
		await a.tap_hud("minimap")
		await a.frames(10)
		for g in a.geometry("map", a.node_controls()):
			a.finding(g)
		await a.shot("map")
		await a.back_key()
	if parts.is_empty() or parts.has("pause"):
		MenuFlags.all_extras = OS.get_environment("TA_EXTRAS") == "1"
		prog.credits = 50000
		await a.crawl(&"paused", "pause", SCRIPTED, 3, restore)
	print(a.table())
	for f in a.findings:
		print("FINDING: ", f)
	print("TOUCH AUDIT BOT: ", a.summary(), ", ", a.findings.size(), " findings")
	_done = true
	tree.quit()
