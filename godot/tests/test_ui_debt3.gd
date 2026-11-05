extends RefCounted
## UI and visual debt 3 (real scene, main.tscn): (1) the shop pages every BUY cell at 64 base px, (2) the title block sits on a backing plate and clears the DEMO / ARENA tabs,
## (3) the radio subtitle wraps whole on a plate that is never see-through, (4) the boss bar does not repeat the name the priority line already shows, (5) a small neutral
## faction state shows on neutral ground, (6) interiors and cars keep their light in check (shader cap / paint glow constants).
## Base px = rect / UiUtil.ui_scale(viewport). Run: tools/test.sh tests/test_ui_debt3.gd

var host: Node
var main: Node
var hud: Hud


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
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(844, 390)]:
		win.size = size
		await frames(4)
		_shop(size)
		_title(size)
		_subtitle(size)
	win.size = old
	await frames(3)
	await _shop_buy_live()
	await _boss_live()
	await _neutral_live()
	_look_constants()
	hud._shop_open = false
	hud._layout_key = ""
	main.queue_free()
	await frames(5)
	Game.state = &"menu"
	Sfx.muted = false


func _vp() -> Vector2:
	return hud.get_viewport().get_visible_rect().size


## 1. Every page of the shop: all buttons at least 64 base px, on screen, none over another; the buy cells of the weapon pages cover every shop weapon.
func _shop(size: Vector2i) -> void:
	var vp := _vp()
	var s := UiUtil.ui_scale(vp)
	var tag := "%dx%d" % [size.x, size.y]
	Game.state = &"paused"
	hud._shop_open = true
	var seen := {}
	var bought_rows := 0
	for pg in ShopScreen.pages():
		ShopScreen.weapon_page = pg
		hud._layout_key = ""
		hud._ensure_layout()
		var rects: Array[Rect2] = []
		for b: Dictionary in hud.buttons:
			var r: Rect2 = b["rect"]
			var id := String(b["id"])
			TestLib.check(minf(r.size.x, r.size.y) / s >= 63.9, "%s shop page %d: %s is %.0fx%.0f base px (needs 64)" % [tag, pg, id, r.size.x / s, r.size.y / s])
			TestLib.check(Rect2(Vector2.ZERO, vp).grow(1.0).encloses(r), "%s shop page %d: %s is on screen" % [tag, pg, id])
			if id.begins_with("buy_"):
				if WeaponDefs.DEFS.has(StringName(id.substr(4))):
					seen[StringName(id.substr(4))] = true
				else:
					bought_rows += 1
			for o in rects:
				TestLib.check(not o.grow(-1.0).intersects(r.grow(-1.0)), "%s shop page %d: %s overlaps another button" % [tag, pg, id])
			rects.append(r)
	TestLib.check(bought_rows == Upgrades.IDS.size(), "%s: page 0 has a BUY row per upgrade (%d)" % [tag, bought_rows])
	for id: StringName in ShopScreen.SHOP_WEAPONS:
		TestLib.check(seen.has(id), "%s: the shop offers %s on some page" % [tag, id])
	ShopScreen.weapon_page = 0
	hud._shop_open = false
	hud._layout_key = ""


## 1 (live). A weapon bought from the 64 px cell on its page: pressing the cell spends the price and unlocks it.
func _shop_buy_live() -> void:
	var prog := Game.progress as Progress
	WeaponDefs.reset_unlocked()
	prog.credits = 100000
	Game.state = &"paused"
	TestLib.check(hud.press_button(&"shop") and hud._shop_open and ShopScreen.weapon_page == 0, "UPGRADES opens the shop on the upgrades page")
	await frames(3)                                # the real draw of the upgrades page
	TestLib.check(hud.press_button(&"shop_wpage") and ShopScreen.weapon_page == 1, "WEAPONS flips to the weapon page")
	await frames(3)                                # the real draw of the weapon page
	hud._ensure_layout()
	var id: StringName = &"minigun"
	var price := prog.weapon_price(id)
	var before := prog.credits
	var rect := Rect2()
	for b: Dictionary in hud.buttons:
		if b["id"] == StringName("buy_%s" % id):
			rect = b["rect"]
	TestLib.check(rect.size.y / UiUtil.ui_scale(_vp()) >= 63.9, "the live minigun cell is 64 base px tall")
	TestLib.check(hud.tap(rect.get_center()) and WeaponDefs.is_unlocked(id) and prog.credits == before - price, "a tap on the 64 px cell buys the minigun for %d" % price)
	hud.press_button(&"shop_back")
	TestLib.check(not hud._shop_open, "BACK leaves the shop")
	Game.state = &"play"


## 2. The title: the block has a plate over the name, rule, subtitle and tagline; the tabs sit above it with a clear gap and a gap between them.
func _title(size: Vector2i) -> void:
	var vp := _vp()
	var s := UiUtil.ui_scale(vp)
	var tag := "%dx%d" % [size.x, size.y]
	Game.state = &"menu"
	hud._shop_open = false
	hud._gear_open = false
	hud._layout_key = ""
	hud._ensure_layout()
	var tp := hud.title_plate(vp, s)
	var dy := hud._title_shift()
	TestLib.check(Rect2(Vector2.ZERO, vp).grow(1.0).encloses(tp), "%s: the title plate is on screen" % tag)
	for base_y in [196.0 + dy - Hud.TITLE_SIZE * 0.7, 258.0 + dy, 294.0 + dy]:       # the name's cap line, the subtitle and the tagline baselines
		TestLib.check(tp.position.y <= base_y * s and tp.end.y >= base_y * s, "%s: the plate covers the line at %.0f base px" % [tag, base_y])
	for b: Dictionary in hud.buttons:
		TestLib.check((b["rect"] as Rect2).position.y >= tp.end.y - 0.5, "%s: button %s starts under the plate" % [tag, b["id"]])
	hud._gear_open = true                                          # DEMO and ARENA are cells of the MORE page
	hud._layout_key = ""
	hud._ensure_layout()
	var demo := Rect2()
	var arena := Rect2()
	for b: Dictionary in hud.buttons:
		if b["id"] == &"demo":
			demo = b["rect"]
		elif b["id"] == &"arena_open":
			arena = b["rect"]
	hud._gear_open = false
	TestLib.check(demo.size != Vector2.ZERO and arena.size != Vector2.ZERO, "%s: DEMO and ARENA tabs exist on the title" % tag)
	TestLib.check(minf(demo.size.y, arena.size.y) / s >= 63.9 and minf(demo.size.x, arena.size.x) / s >= 63.9, "%s: the tabs are 64 base px" % tag)
	Game.state = &"play"


## 3. The radio subtitle: a long line wraps whole (no word lost), within its plate; the plate is never lighter than 0.55.
func _subtitle(size: Vector2i) -> void:
	var tag := "%dx%d" % [size.x, size.y]
	var st := Game.story
	if st == null or st.view == null:
		TestLib.check(false, "the story layer exists")
		return
	var vp := _vp()
	var s := UiUtil.ui_scale(vp)
	for a: float in StoryView.SUB_PLATE:
		TestLib.check(a >= 0.55, "the subtitle plate opacity %.2f is at least 0.55" % a)
	var text := "Arms dealer. Every barrel in here was pulled from a Vael wreck. Pay in credits, not questions. Do not touch the crates on the left."
	var old: Dictionary = st.current
	var chat := UiSettings.s_chatter
	UiSettings.s_chatter = 2                                  # FULL chatter: the long wrapped form
	st.current = {"s": "ORACLE", "t": text}
	var lay: Dictionary = st.view._sub_layout(vp, s, UiUtil.insets(vp))
	var lines: PackedStringArray = lay["lines"]
	var box: Rect2 = lay["box"]
	var font := UiUtil.font()
	TestLib.check(" ".join(lines) == text, "%s: the wrapped subtitle holds the whole sentence (%d lines)" % [tag, lines.size()])
	var widest := 0.0
	for ln: String in lines:
		widest = maxf(widest, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, int(lay["fsize"])).x)
	TestLib.check(widest <= box.size.x - 14.0 * s, "%s: every wrapped line is inside the plate (%.0f of %.0f px)" % [tag, widest, box.size.x])
	TestLib.check(box.size.y >= float(lines.size()) * float(lay["lh"]), "%s: the plate is tall enough for all lines" % tag)
	st.current = old
	UiSettings.s_chatter = chat


## 4 (live). A real boss contract: the priority line names the boss, so the bar under it carries no second name.
func _boss_live() -> void:
	TestLib.check(Hud.boss_name_shown("VAEL OVERSEER  PHASE 1 / 3  6:58  106 M", "VAEL OVERSEER  PHASE 1 / 3"), "a priority line with the name counts as showing it")
	TestLib.check(not Hud.boss_name_shown("QUANTUM CORES  0 / 6", "VAEL OVERSEER  PHASE 1 / 3"), "a line without the name does not")
	var vp := _vp()
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var named := hud.boss_plate(vp, s, font, 100.0 * s, "VAEL OVERSEER  PHASE 1 / 3", true)
	var bare := hud.boss_plate(vp, s, font, 100.0 * s, "VAEL OVERSEER  PHASE 1 / 3", false)
	TestLib.check((bare["bar"] as Rect2).position.y < (named["bar"] as Rect2).position.y and (bare["bar"] as Rect2).position.y > 100.0 * s, "without a name the bar sits closer under the priority line")
	Game.state = &"play"
	TestMode.start_contract(&"boss")
	var boss := {}
	for i in 300:
		await frames(1)
		var k = Game.missions.get(&"contracts")
		if k != null:
			boss = k.call(&"boss")
			if not boss.is_empty():
				break
	TestLib.check(not boss.is_empty(), "a boss contract in the real scene reports a boss")
	if boss.is_empty():
		return
	for i in 120:                                  # the priority line is set by the Hud on its own tick
		if hud._contract_text != "":
			break
		await frames(1)
	var base := str(boss["name"]).split("  PHASE")[0]
	hud._q.clear()
	hud._fills.clear()
	hud._draw_priority(hud._hud, vp, s, UiUtil.font(), 100.0 * s)
	var n := 0
	for q: Array in hud._q:
		if String(q[3]).contains(Tr.t(base)):
			n += 1
	hud._q.clear()
	hud._fills.clear()
	TestLib.check(n == 1, "the boss name '%s' is drawn once in the live HUD (found %d)" % [base, n])
	var k2 = Game.missions.get(&"contracts")
	if k2 != null and bool(k2.call(&"is_active")):
		k2.call(&"abandon")
	await frames(3)


## 5 (live). Neutral ground and no heat: the faction plate still shows, small (one line).
func _neutral_live() -> void:
	Game.state = &"play"
	await frames(3)
	var prog := Game.progress as Progress
	prog.faction_rep.clear()
	Game.heat = 0.0
	var vp := _vp()
	var s := UiUtil.ui_scale(vp)
	var tag := hud.wanted_tag()
	TestLib.check(not tag.is_empty() and String(tag["faction"]).ends_with("NEUTRAL") and String(tag["wanted"]) == "", "the player stands on neutral ground (%s)" % str(tag.get("faction", "")))
	hud._q.clear()
	hud._fills.clear()
	var fills_before := hud._fills.size()
	hud._draw_wanted_tag(hud._hud, s, UiUtil.font(), vp, 6.0 * s)
	var shown := 0
	for q: Array in hud._q:
		if String(q[3]).contains("NEUTRAL"):
			shown += 1
	TestLib.check(shown == 1, "the neutral state is drawn (%d text)" % shown)
	TestLib.check(hud._fills.size() - fills_before == 1, "as one plain fill (no accent rule): a small draw footprint")
	var r: Rect2 = hud._fills[hud._fills.size() - 1][1] if not hud._fills.is_empty() else Rect2()
	TestLib.check(r.size.y > 0.0 and r.size.y <= hud.wanted_rect(vp, s, 6.0 * s).size.y * 0.7, "the neutral plate is shorter than the full one")
	hud._q.clear()
	hud._fills.clear()
	Game.heat = 1.5
	hud._draw_wanted_tag(hud._hud, s, UiUtil.font(), vp, 6.0 * s)
	TestLib.check(hud._fills.size() == 2, "with heat the full plate (fill and accent) draws")
	hud._q.clear()
	hud._fills.clear()
	Game.heat = 0.0


## 6. The light of interiors and cars: strips and panes are capped below the bloom threshold, the car paint carries a real glow.
func _look_constants() -> void:
	var surf := load("res://assets/shaders/interior_surface.gdshader") as Shader
	var win := load("res://assets/shaders/interior_window.gdshader") as Shader
	TestLib.check(surf != null and surf.code.contains("STRIP_CAP"), "the interior strip emission is capped")
	TestLib.check(win != null and win.code.contains("min(glass"), "the window pane is capped")
	var glow := load("res://assets/shaders/interior_glow.gdshader") as Shader
	TestLib.check(glow != null and glow.code.contains("vec3(0.6)") and glow.code.contains("length(VERTEX)"), "halos and beams are capped and fade at the lens")
	TestLib.check(VehicleVisual.paint_glow() >= 0.3, "the car paint glow lifts the night car (%.2f)" % VehicleVisual.paint_glow())
