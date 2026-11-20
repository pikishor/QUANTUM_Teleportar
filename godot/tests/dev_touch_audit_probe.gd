extends RefCounted
## Probe of the touch audit engine (tests/touch_audit_lib.gd): crawls the title and the pause menu and prints the table.
const TIMEOUT_SECONDS := 140
const Audit := preload("res://tests/touch_audit_lib.gd")


func run(h: Node) -> void:
	var a := Audit.new()
	if not await a.boot(h, "probe"):
		TestLib.check(false, "boot")
		return
	var which := OS.get_environment("TA_ROOT")
	var t0 := Time.get_ticks_msec()
	var skip := ["deploy", "continue", "demo", "menu", "resume", "opt_reset", "opt_reset_demo", "photo_open", "pause_map"]
	var res := {}
	var snap := a.settings_snapshot()
	var prog := Game.progress as Progress
	var restore := func() -> void:
		a.settings_restore(snap)
		prog.credits = 50000
	if which == "menu" or which == "":
		res = await a.crawl(&"menu", "title", skip, 4, restore)
	else:
		(Game.progress as Progress).new_campaign()
		Game.state = &"play"
		await a.frames(20)
		prog.credits = 50000
		res = await a.crawl(&"paused", "pause", skip, int(OS.get_environment("TA_DEPTH")) if OS.has_environment("TA_DEPTH") else 3, restore)
	print(a.table())
	print("SUMMARY ", a.summary(), " screens ", res["screens"], " pressed ", res["pressed"], " ms ", Time.get_ticks_msec() - t0)
	print("DEAD ", res["dead"])
	for k in res["seen"]:
		print("SCREEN ", k, " <- ", res["seen"][k])
	await a.shutdown()
