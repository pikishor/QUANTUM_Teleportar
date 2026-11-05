extends RefCounted
## UI debt wave (real scene, main.tscn): (1) the gameplay HUD and minimap are hidden behind every full-screen pause panel, (2) GEAR / LOOK captions clear their rows,
## (3) the contract banner / toast wraps instead of clipping, (4) the boss name clears its bar, (5) every button of every screen is at least 64 base px (scan at 1280x720 and 844x390;
## the few documented exceptions are listed in EXCEPTIONS), (6) the title buttons (DEMO, ARENA, TEST, OPTIONS) overlap neither each other nor the title.
## "Base px": a button's rect divided by UiUtil.ui_scale(viewport); the game draws on a 720 px high canvas (canvas_items stretch), so 64 base px is 64 px at 1280x720 and the same
## fraction of the screen height on a phone.
## Run: tools/test.sh tests/test_ui_debt.gd

## Buttons under 64 base px that stay, with the reason. A key is a screen; the ids match by prefix.
const EXCEPTIONS := {
	"title": ["q0", "q1", "q2", "post", "mute", "cine", "vol_music", "vol_sfx"],       # the quick settings strip duplicates the OPTIONS screen (all 64 px there); no room for 64 px rows next to DEPLOY
	"pause": ["q0", "q1", "q2", "post", "mute", "cine", "vol_music", "vol_sfx"],
	"pause_shop": ["buy_"],                                                             # the 7 upgrade rows and 8 weapon cells share one 720 px page (50 px rows); the shop's navigation row is 64 px
}
const MIN_EXCEPTION := 40.0                    ## an exception is never smaller than this (base px)

var host: Node
var main: Node
var hud: Hud
var report: Array[String] = []
var unexcused: Array[String] = []

const SCREENS := {
	"title": [&"menu", ""], "title_options": [&"menu", "_options_open"], "title_arena": [&"menu", "_arena_open"], "title_chapters": [&"menu", "_chapters_open"],
	"pause": [&"paused", ""], "pause_options": [&"paused", "_options_open"], "pause_chapters": [&"paused", "_chapters_open"], "pause_ach": [&"paused", "_ach_open"],
	"pause_arena": [&"paused", "_arena_open"], "pause_skills": [&"paused", "_skills_open"], "pause_heist": [&"paused", "_heist_open"], "pause_side": [&"paused", "_side_open"],
	"pause_look": [&"paused", "_look_open"], "pause_loadout": [&"paused", "_loadout_open"], "pause_gear": [&"paused", "gear"], "pause_shop": [&"paused", "_shop_open"],
	"dead": [&"dead", ""], "win": [&"win", ""],
}


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	var huds := main.find_children("*", "Hud", true, false)
	if Game.player == null or huds.is_empty():
		TestLib.check(false, "main.tscn has the player and the Hud")
		return
	hud = huds[0] as Hud
	await _hud_hidden_behind_panels()
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		win.size = size
		await frames(4)
		_scan_hud(size)
		_scan_other(size)
		_captions(size)
		_title(size)
		_banner(size)
		_boss(size)
	win.size = old
	await frames(3)
	await _banner_live()
	await _boss_live()
	TestLib.check(unexcused.is_empty(), "every button is at least 64 base px except the documented exceptions; offenders: %s" % ", ".join(unexcused))
	print("UI_DEBT excepted (documented, >= %d base px): %d buttons, e.g. %s" % [int(MIN_EXCEPTION), report.size(), ", ".join(report.slice(0, 6))])
	_reset_flags()
	main.queue_free()
	await frames(5)
	Game.state = &"menu"
	Sfx.muted = false


func _reset_flags() -> void:
	hud._shop_open = false
	hud._ach_open = false
	hud._skills_open = false
	hud._side_open = false
	hud._heist_open = false
	hud._arena_open = false
	hud._loadout_open = false
	hud._loadout_page = 0
	hud._look_open = false
	hud._chapters_open = false
	hud._options_open = false


## 1. Every full-screen panel owns the picture: the gameplay HUD layer and the minimap are hidden while it is open and come back with the pause menu / play.
func _hud_hidden_behind_panels() -> void:
	Game.state = &"play"
	await frames(3)
	TestLib.check(hud._hud.visible and hud.minimap.visible and not hud.panel_cover(), "while playing the HUD and minimap show")
	Game.state = &"paused"
	await frames(3)
	TestLib.check(hud._hud.visible and not hud.panel_cover(), "the plain pause menu keeps the HUD layer (it has no panel)")
	var steps := [
		["shop", "shop"], ["skills_open", "skills"], ["sk_back", "shop"], ["look_open", "suit"], ["look_back", "shop"], ["loadout", "loadout"], ["loadout_gear", "gear"],
		["gear_weapons", "loadout"], ["loadout_back", "shop"], ["side_open", "side"], ["side_back", "shop"], ["heist_open", "heist"], ["heist_back", "shop"], ["shop_back", "pause"],
		["ach", "achievements"], ["ach_back", "pause"], ["arena_open", "arena"], ["arena_back", "pause"], ["options", "options"], ["options_back", "pause"],
	]
	for st: Array in steps:
		var ok := hud.press_button(StringName(st[0]))
		var covered := String(st[1]) != "pause"
		for i in 90:        # wait on the state (the layer follows in the next rendered frame), not on a frame count
			if hud._hud.visible == (not covered):
				break
			await frames(1)
		TestLib.check(ok or not covered, "button %s is handled" % st[0])
		TestLib.check(hud._hud.visible == (not covered) and hud.minimap.visible == hud._hud.visible, "after %s (%s) the HUD is %s" % [st[0], st[1], "hidden" if covered else "back"])
		TestLib.check(hud.layers_consistent(), "layers consistent after %s" % st[0])
		if covered and not hud.panel_cover():
			TestLib.check(false, "panel_cover() is true for the %s panel" % st[1])
	_reset_flags()
	Game.state = &"play"
	await frames(3)
	TestLib.check(hud._hud.visible and hud.minimap.visible, "back in play the HUD shows again")
	TestLib.check(Hud.SUBSCREEN_DIM >= 0.8, "the panels also dim what is behind them (%.2f)" % Hud.SUBSCREEN_DIM)


func _open(name: String) -> void:
	var spec: Array = SCREENS[name]
	_reset_flags()
	Game.state = spec[0]
	var flag := String(spec[1])
	if flag == "gear":
		hud._loadout_open = true
		hud._loadout_page = 1
	elif flag != "":
		hud.set(flag, true)
	hud._layout_key = ""
	hud._ensure_layout()


func _excused(screen: String, id: String) -> bool:
	for pre: String in EXCEPTIONS.get(screen, []):
		if id.begins_with(pre):
			return true
	return false


func _judge(tag: String, screen: String, id: String, r: Rect2, s: float) -> void:
	var m := minf(r.size.x, r.size.y) / s
	if m >= 63.9:
		return
	if _excused(screen, id) and m >= MIN_EXCEPTION - 0.1:
		report.append("%s %s %s %.0fx%.0f" % [tag, screen, id, r.size.x / s, r.size.y / s])
	else:
		unexcused.append("%s %s %s %.0fx%.0f" % [tag, screen, id, r.size.x / s, r.size.y / s])


## 5a. Every Hud screen (title, pause and all its panels, death, win, photo).
func _scan_hud(size: Vector2i) -> void:
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var tag := "%dx%d" % [size.x, size.y]
	for name: String in SCREENS:
		_open(name)
		TestLib.check(not hud.buttons.is_empty(), "%s %s has buttons" % [tag, name])
		for b: Dictionary in hud.buttons:
			_judge(tag, name, String(b["id"]), b["rect"], s)
			TestLib.check(Rect2(Vector2.ZERO, vp).grow(1.0).encloses(b["rect"]), "%s %s: button %s is on screen" % [tag, name, b["id"]])
	for hide in [false, true]:
		hud.buttons.clear()
		hud.photo.hide_ui = hide
		PhotoScreen.layout(hud, hud.photo, vp, s)
		for b: Dictionary in hud.buttons:
			_judge(tag, "photo", String(b["id"]), b["rect"], s)
	hud.photo.hide_ui = false
	_reset_flags()


## 5b. The other panels: DEMO, TEST, the touch buttons (a round button's diameter is its hit area).
func _scan_other(size: Vector2i) -> void:
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var tag := "%dx%d" % [size.x, size.y]
	Game.state = &"menu"
	var dp := host.get_tree().get_first_node_in_group(&"demo_panel") as DemoPanel
	if dp != null:
		for pg in DemoPanel.TABS.size():
			dp.set_page(pg)
			for i in dp.hit_rects().size():
				_judge(tag, "demo", "rect%d_p%d" % [i, pg], dp.hit_rects()[i], s)
		dp.set_page(0)
	var tms := main.find_children("*", "TestMenu", true, false)
	if not tms.is_empty():
		var tm: TestMenu = tms[0]
		_judge(tag, "test", "entry", tm.entry_rect(), s)
		_judge(tag, "test", "close", tm._close_rect(), s)
		_judge(tag, "test", "play", tm._play_rect(), s)
		for i in tm._tab_rects().size():
			_judge(tag, "test", "tab%d" % i, tm._tab_rects()[i], s)
		for pg in TestMenu.TABS.size():
			tm.page = pg
			tm._layout_key = ""
			tm.layout()
			for it: Dictionary in tm.items:
				if not it.get("head", false):
					_judge(tag, "test", "item_%s" % it["label"], it["rect"], s)
		tm.page = 0
		tm._layout_key = ""
	for b: Dictionary in TouchControls.BUTTONS:
		TestLib.check(2.0 * float(b["r"]) >= UiUtil.TOUCH_MIN, "touch button %s is at least 64 base px across" % b["action"])


## 2. GEAR / LOOK captions: none reaches a button, none reaches another caption.
func _captions(size: Vector2i) -> void:
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var tag := "%dx%d" % [size.x, size.y]
	var fs := int(UiUtil.BAR_LABEL * s)
	for screen in ["pause_gear", "pause_look"]:
		_open(screen)
		var caps: Array[Dictionary] = GearScreen.captions(hud, vp.x * 0.5, s) if screen == "pause_gear" else LookScreen.captions(vp.x * 0.5, s)
		TestLib.check(caps.size() >= 5, "%s %s has captions" % [tag, screen])
		var rects: Array[Rect2] = []
		for cp: Dictionary in caps:
			var w := minf(font.get_string_size(String(cp["t"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x, float(cp["w"]))
			var x := float(cp["x"]) + ((float(cp["w"]) - w) * 0.5 if cp.get("center", false) else 0.0)
			var top := float(cp["y"]) - font.get_ascent(fs)
			rects.append(Rect2(x, top, w, font.get_ascent(fs) + font.get_descent(fs) * 0.5))      # glyph body: ascent plus half the descent (descenders are 1 px strokes)
		var clash := ""
		for i in rects.size():
			for b: Dictionary in hud.buttons:
				if rects[i].intersects(b["rect"]):
					clash = "%s over %s" % [caps[i]["t"], b["id"]]
			for j in range(i + 1, rects.size()):
				if rects[i].intersects(rects[j]):
					clash = "%s over %s" % [caps[i]["t"], caps[j]["t"]]
		TestLib.check(clash == "", "%s %s: no caption overlaps a button or another caption (%s)" % [tag, screen, clash])


## 6. Title: DEMO, ARENA, OPTIONS, TEST overlap neither each other nor the title text (the QA / TEST badge used to crowd DEMO and the last letter).
func _title(size: Vector2i) -> void:
	_open("title")
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var tag := "%dx%d" % [size.x, size.y]
	var font := UiUtil.font()
	var tm: TestMenu = main.find_children("*", "TestMenu", true, false)[0]
	var named := {}
	for b: Dictionary in hud.buttons:
		if String(b["id"]) in ["demo", "arena_open", "options", "deploy", "continue"]:
			named[String(b["id"])] = (b["rect"] as Rect2).grow(4.0 * s)
	named["test"] = tm.entry_rect()
	TestLib.check(named.has("demo") and named.has("arena_open") and named.has("options"), "%s title has DEMO, ARENA and OPTIONS" % tag)
	TestLib.check(VisualQaLib.overlap(named) == "", "%s title buttons keep a gap: %s" % [tag, VisualQaLib.overlap(named)])
	var sz := int(Hud.TITLE_SIZE * s)
	var tw := font.get_string_size("QUANTUM TELEPORTAR", HORIZONTAL_ALIGNMENT_LEFT, -1.0, sz).x
	var base := (196.0 + hud._title_shift()) * s
	var title := Rect2(vp.x * 0.5 - tw * 0.5, base - font.get_ascent(sz), tw, font.get_ascent(sz) + font.get_descent(sz))
	for k: String in named:
		TestLib.check(not title.intersects(named[k]), "%s title text does not touch %s" % [tag, k])


## 3. The toast / contract banner: long lines wrap to two lines (or shrink), never wider than the lane, inside the screen.
func _banner(size: Vector2i) -> void:
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var tag := "%dx%d" % [size.x, size.y]
	var texts: Array[String] = ["CONTRACT COMPLETE  +1815 CREDITS", "CONTRACT AVAILABLE  COURIER RUN"]
	for k in ContractTypes.KINDS if "KINDS" in ContractTypes else []:
		texts.append("CONTRACT AVAILABLE  %s" % ContractTypes.title(k))
	texts.append("CONTRACT AVAILABLE  AN EXTREMELY LONG CONTRACT TITLE THAT NEEDS TWO LINES AT ANY SIZE")
	var size30 := int(30.0 * s)
	var all_ok := true
	var why := ""
	for text in texts:
		var r := hud.msg_rect(vp, s, text, size30, font)
		var lines := hud.msg_wrap(vp, s, text, size30, font)
		var ok := lines.size() <= 2 and r.size.x <= hud.msg_max_width(vp, s) + 0.5 and Rect2(Vector2.ZERO, vp).encloses(r)
		for ln in lines:
			var fit := UiUtil.fit_size(font, Tr.t(ln), r.size.x - 16.0 * s, size30)
			ok = ok and fit >= int(16.0 * s) - 1 and font.get_string_size(Tr.t(ln), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fit).x <= r.size.x - 16.0 * s + 0.5
		if not ok:
			all_ok = false
			why = text
	TestLib.check(all_ok, "%s: every toast fits its plate on at most two lines (%s)" % [tag, why])
	var wide := "CONTRACT AVAILABLE  AN EXTREMELY LONG CONTRACT TITLE THAT NEEDS TWO LINES AT ANY SIZE"
	TestLib.check(hud.msg_wrap(vp, s, wide, size30, font).size() == 2, "%s: a toast wider than the lane wraps" % tag)
	TestLib.check(hud.msg_rect(vp, s, wide, size30, font).size.y > hud.msg_rect(vp, s, "OK", size30, font).size.y, "%s: the wrapped plate is taller" % tag)
	TestLib.check(hud.msg_wrap(vp, s, "OK", size30, font).size() == 1, "%s: a short toast stays one line" % tag)


## 4. The boss plate: the name (baseline plus descent) ends above the bar; the bar is under the name.
func _boss(size: Vector2i) -> void:
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var tag := "%dx%d" % [size.x, size.y]
	for nm in ["VAEL OVERSEER  PHASE 1 / 3", "BULWARK PRIME  PHASE 3 / 3", "A VERY LONG BOSS NAME WITH ITS PHASE  PHASE 2 / 3"]:
		var bp := hud.boss_plate(vp, s, font, 100.0 * s, nm)
		var sz: int = bp["size"]
		var bottom := float(bp["baseline"]) + font.get_descent(sz)
		var bar: Rect2 = bp["bar"]
		TestLib.check(bottom + 2.0 * s <= bar.position.y, "%s: boss name '%s' ends %.1f px above its bar" % [tag, nm, (bar.position.y - bottom) / s * s])
		TestLib.check(float(bp["text_w"]) <= (bp["name_rect"] as Rect2).size.x + 0.5, "%s: the boss name is not clipped" % tag)


## 3 (live). A real toast through Game.say in the running scene shows the whole line: the plate the Hud draws holds it on at most two lines.
func _banner_live() -> void:
	Game.state = &"play"
	await frames(3)
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	Game.say("CONTRACT AVAILABLE  COURIER RUN FOR THE HARBOUR DISTRICT", 3.0)
	await frames(3)
	TestLib.check(hud.message_text.begins_with("CONTRACT AVAILABLE") and hud.message_left > 0.0, "the live toast is on screen")
	var r := hud.msg_rect(vp, s, hud.message_text, int(30.0 * s), font)
	var lines := hud.msg_wrap(vp, s, hud.message_text, int(30.0 * s), font)
	TestLib.check(lines.size() <= 2 and r.size.x <= hud.msg_max_width(vp, s) + 0.5, "the live toast fits its plate (%d lines)" % lines.size())


## 4 (live). A real boss contract: the Hud's own boss data gives a plate whose name clears the bar.
func _boss_live() -> void:
	Game.state = &"play"
	TestMode.start_contract(&"boss")
	var boss := {}
	for i in 240:
		await frames(1)
		var k = Game.missions.get(&"contracts")
		if k != null:
			boss = k.call(&"boss")
			if not boss.is_empty():
				break
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	TestLib.check(not boss.is_empty(), "a boss contract in the real scene reports a boss")
	var nm := str(boss.get("name", "BOSS"))
	var bp := hud.boss_plate(vp, s, font, 100.0 * s, nm)
	TestLib.check(float(bp["baseline"]) + font.get_descent(int(bp["size"])) + 2.0 * s <= (bp["bar"] as Rect2).position.y, "the live boss name '%s' clears its bar" % nm)
	var k2 = Game.missions.get(&"contracts")
	if k2 != null and bool(k2.call(&"is_active")):
		k2.call(&"abandon")
