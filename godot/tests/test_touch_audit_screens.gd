extends RefCounted
## THE TOUCH AUDIT, part 3 of 3: THE OTHER SCREENS (wave 116). The real main scene as a phone (844x390, touch forced, reward cards on), a REAL finger (tests/touch_audit_lib.gd):
##   the first minute: PLAY on the title by a finger reaches a game whose FIRE button shoots (no card, hint or cutscene keeps the touch);
##   the MAP from the pause menu: every button and filter chip once (one press each), a tap sets a waypoint, a drag pans, two fingers zoom, CLOSE and the BACK key leave it;
##   EXTRAS with ALL EXTRAS on (SKILLS, CRAFT, SIDE JOBS, HEISTS, SAFEHOUSE, ACHIEVEMENTS, ARENA, CHAPTERS, SUIT): the crawler of part 2;
##   PHOTO MODE; the TEST menu; DEMO MODE (enter, pick a weapon in the LOADOUT with no reward card in the way, the DEMO menu's tabs, QUIT DEMO);
##   the vendor window, the fast-travel list, the mission result card, the death screen.
## Every screen is left again by a finger and by the phone's BACK key.
## Run: tools/test.sh tests/test_touch_audit_screens.gd

const TIMEOUT_SECONDS := 140
const Audit := preload("res://tests/touch_audit_lib.gd")
const SCRIPTED := ["deploy", "continue", "demo", "menu", "resume", "opt_reset", "opt_reset_demo", "opt_bench", "photo_open", "pause_map", "board_story", "options", "loadout", "board_open"]
var a: Audit
var p: Player
var prog: Progress


func run(h: Node) -> void:
	a = Audit.new()
	a.quiet = true
	var ok := await a.boot(h, "screens")
	TestLib.check(ok, "main.tscn boots as a phone")
	if not ok:
		return
	prog = Game.progress as Progress
	p = Game.player as Player
	var only := OS.get_environment("TA_ONLY")
	for step: Array in [["first", _first_minute], ["map", _map], ["extras", _extras], ["photo", _photo], ["test", _test_menu], ["demo", _demo], ["vendor", _vendor], ["travel", _travel], ["result", _result_dead]]:
		if only == "" or only.split(",").has(step[0]):
			await (step[1] as Callable).call()
	for c: Array in a.checks:
		TestLib.check(c[0], c[1])
	for f in a.findings:
		print("FINDING: ", f)
	print("TOUCH AUDIT SCREENS: ", a.summary())
	print(a.table())
	await a.shutdown()


func _play() -> void:
	await a.to_root(&"play")
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false


# --- the first minute ---------------------------------------------------------------------------------------------------------------
func _first_minute() -> void:
	await a.to_root(&"menu")
	var play := a.find(a.controls(), "deploy")
	TestLib.check(not play.is_empty() and play["label"] == "PLAY", "the title shows PLAY")
	if play.is_empty():
		return
	await a.tap(a.centre_of(play))
	TestLib.check(Game.state != &"menu", "a finger on PLAY leaves the title (state %s)" % Game.state)
	# story cards come up in the first seconds: PAUSE answers through them (old behaviour first: the card eats the tap)
	await a.until(func() -> bool: return Game.state == &"play" and not a.hud_button("pause").is_empty() and is_instance_valid(Game.story) and (Game.story.get("cards") as Array).size() >= 2, 600)
	var cards := (Game.story.get("cards") as Array).size() if is_instance_valid(Game.story) else 0
	TestLib.check(Game.state == &"play" and cards >= 2, "a new game starts with story cards over the running game (%d cards, state %s)" % [cards, Game.state])
	if Game.state == &"play" and cards >= 2:
		Story.pause_passes = false
		await a.tap_hud("pause")
		print("OLD BEHAVIOUR (Story.pause_passes off): %d story cards up, state after a tap on PAUSE: %s" % [cards, Game.state])
		TestLib.check(Game.state == &"play", "old behaviour: a story card swallows the tap on PAUSE (state %s)" % Game.state)
		Story.pause_passes = true
		if Game.state == &"play" and (Game.story.get("cards") as Array).size() >= 1:
			await a.tap_hud("pause")
			TestLib.check(Game.state == &"paused", "PAUSE answers while a story card is up (state %s)" % Game.state)
			await a.tap(a.centre_of(a.find(a.controls(), "resume")))
	# whatever comes first (a cutscene, story cards, the tutorial's cards): taps in the middle of the screen walk through it, as a player's thumb would
	var taps := 0
	while taps < 40 and (Game.state != &"play" or a.hud_button("fire").is_empty() or (is_instance_valid(Game.story) and not (Game.story.get("cards") as Array).is_empty())):
		await a.tap(a.vp() * Vector2(0.5, 0.45), 0, 3)
		await a.pframes(20)
		taps += 1
	TestLib.check(Game.state == &"play" and not a.hud_button("fire").is_empty(), "after PLAY, %d taps reach a running game with its HUD (state %s)" % [taps, Game.state])
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	await a.pframes(30)
	var shots := 0
	for k in 3:                                                       # the first press may fall on the weapon being raised
		Sfx.last_played = &""
		a.finger_down(a.centre_of(a.hud_button("fire")))
		await a.pframes(25)
		a.finger_up()
		if String(Sfx.last_played).begins_with("shot"):
			shots += 1
		await a.pframes(10)
	TestLib.check(shots >= 1, "in the first seconds of a new game a finger on FIRE shoots: no card or hint keeps the touch (%d of 3 presses fired)" % shots)
	var y0 := p.global_position.y
	a.fast_tap(a.centre_of(a.hud_button("jump")))
	var jumped := await a.until(func() -> bool: return p.global_position.y > y0 + 0.25, 90)
	TestLib.check(jumped, "a quick tap on JUMP lifts the hero")
	var paused := await a.tap_hud("pause")
	TestLib.check(paused and Game.state == &"paused", "PAUSE answers in the first seconds too (state %s)" % Game.state)


# --- the map -------------------------------------------------------------------------------------------------------------------------
func _map() -> void:
	await a.to_root(&"paused")
	var ms := a.map_screen()
	var card := a.find(a.controls(), "pause_map")
	TestLib.check(not card.is_empty(), "the pause menu shows MAP")
	await a.tap(a.centre_of(card))
	await a.frames(8)
	TestLib.check(MapScreen.up and ms.get("selected") == null or MapScreen.up, "a finger on MAP opens the map")
	TestLib.check(a.hud_controls().is_empty(), "no pause button is live under the open map")
	var mr0: Rect2 = ms.get("_rect")
	# YOU, GOAL and CLEAR need something to do: a panned view, a waypoint
	var c0 := str(ms.get("view_center"))
	await a.drag(mr0.position + mr0.size * Vector2(0.6, 0.6), mr0.position + mr0.size * Vector2(0.35, 0.4), 8)
	TestLib.check(str(ms.get("view_center")) != c0, "a finger dragged over the map pans it")
	var c1 := str(ms.get("view_center"))
	var you := a.find(a.node_controls(), "Locate")
	await a.tap(a.centre_of(you))
	TestLib.check(str(ms.get("view_center")) != c1, "a finger on YOU brings the view back to the hero")
	a.row("map", you, "state" if str(ms.get("view_center")) != c1 else "dead")
	var res := await a.press_nodes("map", func() -> String: return "%s%s%s%s" % [ms.get("world_mode"), ms.get("zoom_f"), ms.get("waypoint"), ms.get("view_center")], ["Close", "Missions", "Locate", "Goal", "Clear"], func() -> bool: return MapScreen.up)
	await a.tap(mr0.position + mr0.size * Vector2(0.62, 0.4), 0, 3)
	await a.frames(3)
	var had_wp := (ms.get("waypoint") as Vector3).is_finite()
	var goal := a.find(a.node_controls(), "Goal")
	if not goal.is_empty() and not goal["disabled"]:
		var n0 := TouchButtons.presses
		await a.tap(a.centre_of(goal))
		TestLib.check(TouchButtons.presses - n0 == 1, "a finger on GOAL is one press (%d)" % (TouchButtons.presses - n0))
		a.row("map", goal, "state")
	var clr := a.find(a.node_controls(), "Clear")
	await a.tap(a.centre_of(clr))
	TestLib.check(had_wp and not (ms.get("waypoint") as Vector3).is_finite(), "a finger on CLEAR removes the waypoint a tap set (had one: %s)" % had_wp)
	a.row("map", clr, "state" if not (ms.get("waypoint") as Vector3).is_finite() else "dead")
	TestLib.check(res["pressed"] >= 5, "the map: %d buttons and chips pressed by the finger" % res["pressed"])
	TestLib.check((res["dead"] as Array).is_empty(), "the map: no button is dead (%s)" % str(res["dead"]))
	TestLib.check((res["double"] as Array).is_empty(), "the map: one tap is one press (%s)" % str(res["double"]))
	if not MapScreen.up:
		ms.open()
		await a.frames(6)
	# the map itself: a tap sets a waypoint, a drag pans, two fingers zoom
	var mr: Rect2 = ms.get("_rect")
	var spot := mr.position + mr.size * Vector2(0.62, 0.4)
	var sel0 := str(ms.get("waypoint")) + str(ms.get("selected"))
	await a.tap(spot, 0, 3)
	await a.frames(3)
	TestLib.check(str(ms.get("waypoint")) + str(ms.get("selected")) != sel0, "a tap on the map sets a waypoint or picks a place")
	var z0 := float(ms.get("zoom_f"))
	var m := mr.get_center()
	a.finger_down(m + Vector2(-40, 0), 0)
	a.finger_down(m + Vector2(40, 0), 1)
	await a.frames(2)
	for i in 8:
		a.finger_move(m + Vector2(-40.0 - 14.0 * (i + 1), 0), 0)
		a.finger_move(m + Vector2(40.0 + 14.0 * (i + 1), 0), 1)
		await a.frames(1)
	a.finger_up(0)
	a.finger_up(1)
	await a.frames(3)
	TestLib.check(absf(float(ms.get("zoom_f")) - z0) > 0.01, "two fingers spread on the map zoom it (%.2f -> %.2f)" % [z0, float(ms.get("zoom_f"))])
	# out again: CLOSE goes back to the pause menu it came from, the BACK key too
	var cl := a.find(a.node_controls(), "Close")
	await a.tap(a.centre_of(cl))
	TestLib.check(not MapScreen.up and Game.state == &"paused" and not a.hud_controls().is_empty(), "CLOSE on a map opened from the pause menu returns to the pause menu (state %s)" % Game.state)
	await a.tap(a.centre_of(a.find(a.controls(), "pause_map")))
	await a.frames(6)
	await a.back_key()
	TestLib.check(not MapScreen.up and Game.state == &"paused", "the BACK key closes the map and returns to the pause menu (state %s)" % Game.state)
	# MISSIONS on the map opens the mission board
	await a.tap(a.centre_of(a.find(a.controls(), "pause_map")))
	await a.frames(6)
	var mb := a.find(a.node_controls(), "Missions")
	if not mb.is_empty() and not mb["disabled"]:
		await a.tap(a.centre_of(mb))
		await a.frames(4)
		TestLib.check(not MapScreen.up and a.hud._board_open, "MISSIONS on the map opens the mission board")
	if MapScreen.up:
		ms.close_screen()


# --- EXTRAS, every screen the cut list hides -----------------------------------------------------------------------------------------
func _extras() -> void:
	prog.new_campaign() if not prog.has_save() and Game.state == &"menu" else null
	await _play()
	a.hud.settings.set("all_extras", true)
	a.hud.settings.publish(false)
	MenuFlags.all_extras = true
	prog.credits = 50000
	var snap := a.settings_snapshot()
	var restore := func() -> void:
		a.settings_restore(snap)
		prog.credits = 50000
		Arsenal._st.clear()
	var n0 := a.rows.size()
	var q := await a.crawl(&"paused", "extras", SCRIPTED + ["hero_tab_up", "hero_tab_weapons"], 3, restore)
	a.hud.settings.set("all_extras", false)
	a.hud.settings.publish(false)
	MenuFlags.all_extras = false
	var seen := ""
	for k: String in (q["seen"] as Dictionary):
		seen += k + " "
	for need in ["skills", "craft", "side", "heist", "safe", "ach", "arena", "look"]:
		TestLib.check(seen.contains("+" + need), "ALL EXTRAS: the %s screen was reached by the finger" % need)
	TestLib.check(q["pressed"] >= 60, "ALL EXTRAS: %d screens walked, %d controls pressed" % [q["screens"], q["pressed"]])
	TestLib.check((q["dead"] as Array).is_empty(), "ALL EXTRAS: no control is dead (%s)" % str(q["dead"]))
	TestLib.check((q["trapped"] as Array).is_empty(), "ALL EXTRAS: every screen has a control that leaves it (%s)" % str(q["trapped"]))
	TestLib.check((q["back_dead"] as Array).is_empty(), "ALL EXTRAS: the BACK key leaves every screen (%s)" % str(q["back_dead"]))


# --- photo mode ----------------------------------------------------------------------------------------------------------------------
func _photo() -> void:
	await _play()
	TestLib.check(await a.goto(&"paused", ["menu_gear", "photo_open"]) and a.hud.photo_open(), "EXTRAS > PHOTO opens photo mode by the finger")
	if not a.hud.photo_open():
		return
	var list := a.hud_controls()
	for g in a.geometry("photo", list):
		a.finding(g)
	await a.shot("photo")
	var dead: Array[String] = []
	var ids: Array[String] = []
	for c: Dictionary in list:
		ids.append(c["id"])
	TestLib.check(ids.size() >= 6, "photo mode shows its controls (%s)" % str(ids))
	for id in ids:
		if id in ["photo_back", "photo_exit", "photo_shot", "photo_hide"] or not a.hud.photo_open():
			continue
		var c := a.find(a.hud_controls(), id)
		if c.is_empty():
			continue
		var before := a.signature()
		Sfx.last_played = &""
		if a.is_slider(id):
			var sr: Rect2 = c["rect"]
			await a.drag(sr.position + sr.size * Vector2(0.75, 0.5), sr.position + sr.size * Vector2(0.4, 0.5))
		else:
			await a.tap(a.centre_of(c))
		var eff := "state" if a.signature() != before else ("sound" if Sfx.last_played != &"" else "dead")
		a.row("photo", c, eff)
		if eff == "dead":
			dead.append(id)
	TestLib.check(dead.is_empty(), "photo mode: every control answers the finger (%s)" % str(dead))
	TestLib.check(a.hud.photo_open(), "photo mode is still up after its controls were pressed")
	await a.back_key()
	TestLib.check(not a.hud.photo_open() and Game.state == &"paused", "the BACK key leaves photo mode for the pause menu (did %s)" % BackKey.last)
	await a.goto(&"paused", ["menu_gear", "photo_open"])
	var out: Dictionary = {}
	for c: Dictionary in a.hud_controls():
		if c["id"] in ["photo_back", "photo_exit"]:
			out = c
	TestLib.check(not out.is_empty(), "photo mode has a BACK button")
	if not out.is_empty():
		await a.tap(a.centre_of(out))
		TestLib.check(not a.hud.photo_open(), "a finger on photo mode's BACK leaves it")


# --- a menu that draws itself: tabs, rows, CLOSE -------------------------------------------------------------------------------------
func _walk_panel(ctx: String, n: Node, press_rows: Array) -> void:
	for g in a.geometry(ctx, a.panel_controls(n)):
		a.finding(g)
	await a.shot(ctx)
	var tabs := 0
	for c: Dictionary in a.panel_controls(n):
		if not c.has("tab"):
			continue
		await a.tap(a.centre_of(c))
		a.row(ctx, c, "nav" if int(n.get("page")) == int(c["tab"]) else "dead")
		TestLib.check(int(n.get("page")) == int(c["tab"]) and bool(n.get("is_open")), "%s: a finger on the tab %s shows that page" % [ctx, c["label"]])
		tabs += 1
		for r: Dictionary in a.panel_controls(n):
			if r.has("item") and press_rows.has(r["label"]):
				var before := a.signature() + str(n.get("status"))
				Sfx.last_played = &""
				await a.tap(a.centre_of(r))
				var eff := "state" if a.signature() + str(n.get("status")) != before else ("sound" if Sfx.last_played != &"" else "dead")
				a.row(ctx, r, eff)
				TestLib.check(eff != "dead", "%s: a finger on the row %s answers (%s)" % [ctx, r["label"], eff])
	TestLib.check(tabs >= 5, "%s: %d tabs pressed" % [ctx, tabs])
	# a drag scrolls a long page
	var long_tab: Dictionary = {}
	for c: Dictionary in a.panel_controls(n):
		if c.has("tab"):
			await a.tap(a.centre_of(c))
			if float(n.call(&"_max_scroll")) > 40.0:
				long_tab = c
				break
	if not long_tab.is_empty():
		var s0 := float(n.get("scroll"))
		await a.drag(a.vp() * Vector2(0.5, 0.8), a.vp() * Vector2(0.5, 0.45), 8)
		TestLib.check(float(n.get("scroll")) > s0 + 20.0 and bool(n.get("is_open")), "%s: a finger dragged up scrolls the page %s (%.0f -> %.0f)" % [ctx, long_tab["label"], s0, float(n.get("scroll"))])


func _test_menu() -> void:
	var tm := a.node_of("TestMenu") as TestMenu
	TestLib.check(tm != null and TestMode.available(), "the TEST menu exists in this build")
	if tm == null or not TestMode.available():
		return
	await _play()
	MenuFlags.all_extras = true                                        # the TEST card shows with ALL EXTRAS (a player never sees it otherwise)
	await a.goto(&"paused", ["menu_gear"])
	var er := tm.entry_rect()
	TestLib.check(er.size.x > 0.0 and a.px(er.size.y) >= 43.5, "EXTRAS shows the TEST button (%d x %d px)" % [int(a.px(er.size.x)), int(a.px(er.size.y))])
	await a.tap(er.get_center())
	TestLib.check(tm.is_open, "a finger on TEST opens the TEST menu")
	if not tm.is_open:
		return
	await _walk_panel("test_menu", tm, ["GOD MODE", "INFINITE AMMO"])
	await a.back_key()
	TestLib.check(not tm.is_open and BackKey.last == &"test", "the BACK key closes the TEST menu (did %s)" % BackKey.last)
	await a.goto(&"paused", ["menu_gear"])
	await a.tap(tm.entry_rect().get_center())
	var cl := a.find(a.panel_controls(tm), "close")
	TestLib.check(not cl.is_empty(), "the TEST menu has a CLOSE button")
	if not cl.is_empty():
		await a.tap(a.centre_of(cl))
	TestLib.check(not tm.is_open, "a finger on CLOSE closes the TEST menu")
	if tm.is_open:
		tm.close()
	MenuFlags.all_extras = false
	TestMode.reset_toggles()


# --- demo mode -----------------------------------------------------------------------------------------------------------------------
func _demo() -> void:
	var dp := a.node_of("DemoPanel") as DemoPanel
	await a.to_root(&"menu")
	TestLib.check(await a.goto(&"menu", ["menu_gear", "demo"]) and DemoMode.active, "title > EXTRAS > DEMO enters demo mode by the finger (state %s)" % Game.state)
	if not DemoMode.active:
		return
	var n := 0
	while n < 30 and Game.state != &"play":
		await a.tap(a.vp() * Vector2(0.5, 0.45), 0, 3)
		await a.pframes(15)
		n += 1
	TestLib.check(Game.state == &"play", "the demo runs (state %s after %d taps)" % [Game.state, n])
	await a.pframes(60)
	TestLib.check(not CrateReveal.is_showing() and CrateReveal._queue.is_empty(), "demo mode: no reward card is on screen or queued after every weapon was unlocked")
	# the owner's words: "I just keep on seeing weapons but can't choose any"
	await a.tap_hud("pause")
	var lo := a.find(a.controls(), "loadout")
	TestLib.check(Game.state == &"paused" and not lo.is_empty(), "demo mode: PAUSE and the LOADOUT card answer")
	if not lo.is_empty():
		await a.tap(a.centre_of(lo))
		var tiles: Array[Dictionary] = []
		for c: Dictionary in a.hud_controls():
			if String(c["id"]).begins_with("wheel_"):
				tiles.append(c)
		TestLib.check(tiles.size() >= 6, "demo mode: the LOADOUT shows weapon tiles (%d in view)" % tiles.size())
		if tiles.size() >= 2:
			var pick: Dictionary = tiles[tiles.size() - 1]
			var want := StringName(String(pick["id"]).substr(6))
			await a.tap(a.centre_of(pick))
			TestLib.check(a.hud._loadout_w == want, "demo mode: a finger on a weapon tile picks it (%s, loadout shows %s)" % [want, a.hud._loadout_w])
			var s0 := float(Arsenal.st(&"loadout")["scroll"])
			await a.drag(Arsenal.list_rect.get_center() + Vector2(0, 120), Arsenal.list_rect.get_center() + Vector2(0, -140), 8)
			TestLib.check(float(Arsenal.st(&"loadout")["scroll"]) > s0 + 30.0, "demo mode: a finger dragged over the weapon list scrolls it (%.0f -> %.0f)" % [s0, float(Arsenal.st(&"loadout")["scroll"])])
			var eq := a.find(a.controls(), "ars_equip")                  # a tile selects; the action button under the card puts it in the hand
			TestLib.check(not eq.is_empty(), "demo mode: the LOADOUT has an action button for the picked weapon (%s)" % str(eq.get("label", "-")))
			if not eq.is_empty():
				await a.tap(a.centre_of(eq))
			var back := a.find(a.controls(), "loadout_back")
			await a.tap(a.centre_of(back))
			var res := a.find(a.controls(), "resume")
			if not res.is_empty():
				await a.tap(a.centre_of(res))
			await a.pframes(20)
			TestLib.check(Game.state == &"play" and p.weapon.current == want, "demo mode: back in the game the picked weapon is in the hand (%s, state %s)" % [p.weapon.current, Game.state])
	Game.state = &"play"
	await a.pframes(10)
	# the DEMO badge and its menu
	var er := dp.entry_rect()
	TestLib.check(dp._entry_visible() and a.px(er.size.y) >= 34.0, "the DEMO badge is on the play HUD")
	await a.tap(er.get_center(), 0, 3)
	TestLib.check(dp.is_open, "a finger on the DEMO badge opens the DEMO menu")
	if dp.is_open:
		await _walk_panel("demo_menu", dp, ["GOD MODE", "INFINITE AMMO", "HEAL AND FILL AMMO"])
		await a.back_key()
		TestLib.check(not dp.is_open and BackKey.last == &"demo", "the BACK key closes the DEMO menu (did %s)" % BackKey.last)
		Game.state = &"play"
		await a.pframes(6)
		await a.tap(dp.entry_rect().get_center(), 0, 3)
		var cl := a.find(a.panel_controls(dp), "close")
		if not cl.is_empty():
			await a.tap(a.centre_of(cl))
		TestLib.check(not dp.is_open, "a finger on CLOSE closes the DEMO menu")
		# QUIT DEMO: the last row of the last tab
		Game.state = &"play"
		await a.pframes(6)
		await a.tap(dp.entry_rect().get_center(), 0, 3)
		var tabs: Array[Dictionary] = []
		for c: Dictionary in a.panel_controls(dp):
			if c.has("tab"):
				tabs.append(c)
		if not tabs.is_empty():
			await a.tap(a.centre_of(tabs[tabs.size() - 1]))
			for k in 6:
				var q := {}
				for r: Dictionary in a.panel_controls(dp):
					if r["label"] == "QUIT DEMO":
						q = r
				if not q.is_empty():
					await a.tap(a.centre_of(q))
					break
				await a.drag(a.vp() * Vector2(0.5, 0.8), a.vp() * Vector2(0.5, 0.4), 8)
		await a.frames(6)
		TestLib.check(not DemoMode.active and Game.state == &"menu", "QUIT DEMO by the finger leaves the demo for the title (state %s)" % Game.state)
	if DemoMode.active:
		DemoMode.quit()
	TestMode.reset_toggles()


# --- the vendor window ---------------------------------------------------------------------------------------------------------------
func _vendor() -> void:
	await _play()
	var ig := InteriorGameplay.instance
	TestLib.check(ig != null and ig.vendor_screen != null, "the interiors have a vendor window")
	if ig == null or ig.vendor_screen == null:
		return
	prog.credits = 50000
	var vs := ig.vendor_screen
	TestLib.check(vs.open(&"bodega") and InteriorGameplay.vendor_open, "the bodega's vendor window opens")
	await a.frames(6)
	vs.layout()
	var bought := 0
	for i in vs.rects.size():
		var c0 := prog.credits
		Sfx.last_played = &""
		var r := vs.rects[i]
		await a.tap(r.get_center())
		var eff := "state" if prog.credits != c0 else ("sound" if Sfx.last_played != &"" else "dead")
		a.row("vendor", {"src": "panel", "id": "buy_%d" % i, "label": str((vs.rows[i] as Dictionary).get("name", "")), "rect": r}, eff)
		TestLib.check(eff != "dead", "vendor: a finger on BUY of row %d answers (%s)" % [i, eff])
		if eff == "state":
			bought += 1
		vs.layout()
	TestLib.check(bought >= 1 and vs.is_open, "vendor: at least one row was bought by the finger and the window stays (%d of %d)" % [bought, vs.rects.size()])
	TestLib.check(vs.close_rect.has_area(), "vendor: a CLOSE button is drawn (%d x %d px plate)" % [int(a.px(vs.close_rect.size.x)), int(a.px(vs.close_rect.size.y))])
	var below := Vector2(vs.close_rect.get_center().x, vs.close_rect.end.y + 12.0)       # a thumb that lands 6 px under the 27 px plate
	Hud.finger_targets = false
	await a.tap(below)
	print("OLD BEHAVIOUR (finger targets off): vendor window open after a tap 6 px under CLOSE: %s" % vs.is_open)
	TestLib.check(vs.is_open, "old behaviour: a tap 6 px under the vendor's CLOSE plate misses it")
	Hud.finger_targets = true
	if not vs.is_open:
		vs.open(&"bodega")
		await a.frames(4)
	await a.tap(below)
	TestLib.check(not vs.is_open and not InteriorGameplay.vendor_open and Game.state == &"play", "a finger on CLOSE closes the vendor window and the game runs (state %s)" % Game.state)
	vs.open(&"bodega")
	await a.frames(4)
	await a.back_key()
	TestLib.check(not vs.is_open and BackKey.last == &"vendor" and Game.state == &"play", "the BACK key closes the vendor window (did %s, state %s)" % [BackKey.last, Game.state])
	if vs.is_open:
		vs.close()


# --- the fast-travel list ------------------------------------------------------------------------------------------------------------
func _travel() -> void:
	await _play()
	var rt := a.node_of("RoamTravel") as RoamTravel
	TestLib.check(rt != null, "the world has fast-travel pads")
	if rt == null:
		return
	var pads: Array = RoamData.pads()
	var pad: Dictionary = pads[0] if not pads.is_empty() else {}
	if rt.world != null:
		for q: Dictionary in pads:
			rt.world.found_pad(q["id"])                                  # every pad found, so the list has rows
	TestLib.check(not pad.is_empty(), "a fast-travel pad exists")
	if pad.is_empty():
		return
	p.global_position = (pad["pos"] as Vector3) + Vector3(0.0, 0.4, 0.0)       # the hero walks onto the pad: the list opens by itself
	p.velocity = Vector3.ZERO
	await a.until(func() -> bool: return rt.panel_open, 400)
	await a.frames(6)
	TestLib.check(rt.panel_open and a.node_controls().size() >= 2, "the fast-travel list is up with its buttons (%d)" % a.node_controls().size())
	for g in a.geometry("travel", a.node_controls()):
		a.finding(g)
	await a.shot("travel")
	await a.back_key()
	TestLib.check(not rt.panel_open and BackKey.last == &"travel", "the BACK key closes the fast-travel list (did %s)" % BackKey.last)
	rt.set("_quiet", &"")
	rt.set("_cool", 0.0)
	p.global_position = (pad["pos"] as Vector3) + Vector3(0.0, 0.4, 0.0)
	await a.until(func() -> bool: return rt.panel_open, 400)
	await a.frames(6)
	var list := a.node_controls()
	var pos0 := p.global_position
	var n0 := TouchButtons.presses
	if not list.is_empty():
		await a.tap(a.centre_of(list[0]))
		await a.pframes(30)
	TestLib.check(TouchButtons.presses - n0 == 1, "fast travel: one tap on a destination is one press (%d)" % (TouchButtons.presses - n0))
	TestLib.check(not rt.panel_open or p.global_position.distance_to(pos0) > 5.0, "fast travel: a finger on the first row travels or closes the list (moved %.0f m, open %s)" % [p.global_position.distance_to(pos0), rt.panel_open])
	a.row("travel", list[0], "state" if (not rt.panel_open or p.global_position.distance_to(pos0) > 5.0) else "dead") if not list.is_empty() else null
	if rt.panel_open:
		rt.stay()
	Game.state = &"play"


# --- the result card and the death screen --------------------------------------------------------------------------------------------
func _result_dead() -> void:
	await _play()
	var rc := a.node_of("ResultCard") as ResultCard
	TestLib.check(rc != null, "the result card exists")
	if rc != null:
		rc.open({"title": "TOUCH AUDIT", "ok": true, "credits": 100, "name": "TOUCH AUDIT", "success": true})
		await a.frames(10)
		if rc.is_open:
			for g in a.geometry("result", [{"src": "panel", "id": "next", "label": "NEXT", "rect": rc.next_rect(), "layer": rc.layer, "kind": "rect"}]):
				a.finding(g)
			await a.shot("result")
			await a.tap(a.vp() * Vector2(0.2, 0.3))
			TestLib.check(rc.is_open, "a tap beside the buttons of the result card does not close it and does not reach the game")
			await a.tap(rc.next_rect().get_center())
			TestLib.check(not rc.is_open, "a finger on the result card's NEXT closes it")
			a.row("result", {"src": "panel", "id": "next", "label": "NEXT", "rect": rc.next_rect()}, "nav" if not rc.is_open else "dead")
			await _play()
			rc.open({"title": "TOUCH AUDIT", "ok": true, "credits": 100, "name": "TOUCH AUDIT", "success": true})
			await a.frames(10)
			await a.back_key()
			TestLib.check(not rc.is_open and BackKey.last == &"result", "the BACK key closes the result card (did %s)" % BackKey.last)
		else:
			TestLib.check(false, "the result card opens for a finished mission")
	await _play()
	await a.pframes(10)
	Game.die()
	await a.frames(10)
	TestLib.check(Game.state == &"dead", "the hero is dead (state %s)" % Game.state)
	a.hud.screen_age = 10.0
	var rs := a.find(a.controls(), "respawn")
	TestLib.check(not rs.is_empty(), "the death screen shows RESPAWN")
	if not rs.is_empty():
		for g in a.geometry("dead", a.hud_controls()):
			a.finding(g)
		await a.shot("dead")
		await a.tap(a.centre_of(rs))
		await a.frames(10)
		TestLib.check(Game.state == &"play", "a finger on RESPAWN puts the hero back in the game (state %s)" % Game.state)
		a.row("dead", rs, "nav" if Game.state == &"play" else "dead")
