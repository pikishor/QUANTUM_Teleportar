extends RefCounted
## THE TOUCH AUDIT, part 2 of 3: THE MENUS (wave 116). The real main scene as a phone (844x390, touch forced), a REAL finger (tests/touch_audit_lib.gd). A crawler walks every
## screen that can be reached from the title and from the pause menu by pressing buttons (it knows no screen by name: a new screen is found and pressed too): the title, OPTIONS
## and its five tabs, the CONTROLS page, EXTRAS, the pause menu, MISSIONS, LOADOUT / the Arsenal with its weapon tiles, GEAR, UPGRADES, WEAPONS, SUIT. For every screen:
##   every control answers the finger (a screen change, a value, at least a sound: never nothing); a slider follows a drag; no plain Button fires twice for one tap;
##   a control on the screen leaves it (BACK / RESUME ...), and so does the phone's BACK key;
##   the area that answers around every menu button is at least 44 px at 844x390 where the layout has the room (Hud.finger_targets; shown failing with the old 4 px margin).
## What still sits under 44 px is counted and pinned (KNOWN_SMALL): the count may only go down.
## Run: tools/test.sh tests/test_touch_audit_menus.gd

const TIMEOUT_SECONDS := 140
const Audit := preload("res://tests/touch_audit_lib.gd")
## Pressed by scripted checks (here or in part 3): they leave the menus or change the save in a way the walk cannot undo.
const SCRIPTED := ["deploy", "continue", "demo", "menu", "resume", "opt_reset", "opt_reset_demo", "opt_bench", "photo_open", "pause_map", "board_story"]
## Targets still under 44 px at 844x390 after the finger margins (rows packed tighter than 82 base px; wave 137 owns the small-screen layout). Never raise these.
const KNOWN_SMALL := {"title": 38, "pause": 82}
var a: Audit


func _small(prefix: String) -> int:
	var n := 0
	for f in a.findings:
		if f.begins_with(prefix) and f.contains("(under"):
			n += 1
	return n


func run(h: Node) -> void:
	a = Audit.new()
	a.quiet = true
	var ok := await a.boot(h, "menus")
	TestLib.check(ok, "main.tscn boots as a phone")
	if not ok:
		return
	var prog := Game.progress as Progress
	var snap := a.settings_snapshot()
	var restore := func() -> void:
		a.settings_restore(snap)
		prog.credits = 50000
		Arsenal._st.clear()
	# --- the hit areas: the old 4 px margin first
	Hud.finger_targets = false
	await a.goto(&"menu", ["options"])
	var old_bad := a.geometry("old", a.controls()).size()
	Hud.finger_targets = true
	a.hud._layout_key = ""
	a.findings.clear()
	var new_bad := a.geometry("new", a.controls()).size()
	a.findings.clear()
	print("OLD BEHAVIOUR (Hud.finger_targets off): %d targets of the OPTIONS screen under 44 px; with the finger margins: %d" % [old_bad, new_bad])
	TestLib.check(old_bad >= 7, "old behaviour: the first OPTIONS tab has seven targets under 44 px at 844x390, the tabs, RESET PAGE and BACK (%d)" % old_bad)
	TestLib.check(new_bad == 0, "OPTIONS (first tab): every target is at least 44 px at 844x390 with the finger margins (%d under)" % new_bad)
	var back := a.find(a.controls(), "options_back")
	var tgt := a.hud_target(back)
	TestLib.check(a.px(tgt.size.y) >= 43.5 and a.px(tgt.size.x) >= 43.5, "the BACK button of OPTIONS answers in an area of %d x %d px" % [int(a.px(tgt.size.x)), int(a.px(tgt.size.y))])
	await a.tap(Vector2(a.centre_of(back).x, (back["rect"] as Rect2).position.y - 7.0))            # a thumb that lands a little above the plate
	TestLib.check(not a.hud._options_open, "a finger 7 px above the BACK plate still presses BACK")
	# --- the title
	var t := await a.crawl(&"menu", "title", SCRIPTED, 4, restore)
	TestLib.check(t["screens"] >= 8 and t["pressed"] >= 80, "the title: %d screens walked, %d controls pressed by the finger" % [t["screens"], t["pressed"]])
	TestLib.check((t["dead"] as Array).is_empty(), "the title: no control is dead (%s)" % str(t["dead"]))
	TestLib.check((t["trapped"] as Array).is_empty(), "the title: every screen has a control that leaves it (%s)" % str(t["trapped"]))
	TestLib.check((t["back_dead"] as Array).is_empty(), "the title: the BACK key leaves every screen (%s)" % str(t["back_dead"]))
	# --- the pause menu
	prog.new_campaign()
	Game.state = &"play"
	await a.frames(20)
	prog.credits = 50000
	var q := await a.crawl(&"paused", "pause", SCRIPTED, 3, restore)
	TestLib.check(q["screens"] >= 13 and q["pressed"] >= 200, "the pause menu: %d screens walked, %d controls pressed by the finger" % [q["screens"], q["pressed"]])
	TestLib.check((q["dead"] as Array).is_empty(), "the pause menu: no control is dead (%s)" % str(q["dead"]))
	TestLib.check((q["trapped"] as Array).is_empty(), "the pause menu: every screen has a control that leaves it (%s)" % str(q["trapped"]))
	TestLib.check((q["back_dead"] as Array).is_empty(), "the pause menu: the BACK key leaves every screen (%s)" % str(q["back_dead"]))
	var tiles := 0
	for r: Dictionary in a.rows:
		if String(r["id"]).begins_with("wheel_") or String(r["id"]).begins_with("wsel_"):
			tiles += 1
			TestLib.check(r["effect"] != "dead" and r["effect"] != "gone", "the weapon tile %s answers the finger in %s (%s)" % [r["id"], r["ctx"], r["effect"]])
	TestLib.check(tiles >= 12, "the weapon tiles of LOADOUT and WEAPONS were pressed (%d)" % tiles)
	var overlaps := 0
	for f in a.findings:
		if f.contains("overlap") or f.contains("leaves the screen") or f.contains("fired"):
			overlaps += 1
			TestLib.check(false, f)
	TestLib.check(overlaps == 0, "no two controls overlap, none leaves the screen, no Button fires twice")
	for k: String in KNOWN_SMALL:
		TestLib.check(_small(k) <= int(KNOWN_SMALL[k]), "%s: targets still under 44 px: %d (pinned at %d, may only go down)" % [k, _small(k), int(KNOWN_SMALL[k])])
	for f in a.findings:
		print("FINDING: ", f)
	print("TOUCH AUDIT MENUS: ", a.summary())
	print(a.table())
	await a.shutdown()
