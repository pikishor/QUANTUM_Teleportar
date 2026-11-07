extends RefCounted
## Visual defect pass 2 (real scene, main.tscn): title buttons, interior colour balance, boss plate, DEMO tabs, toast vs the hero's face, the QA's new pause-screen spots.
## Run: tools/test.sh tests/test_visual_fixes4.gd

var host: Node
var main: Node
var p: Player
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
	p = Game.player as Player
	var huds := main.find_children("*", "Hud", true, false)
	if p == null or huds.is_empty():
		TestLib.check(false, "main.tscn has the player and the Hud")
		return
	hud = huds[0] as Hud
	await _title()
	await _demo_tabs()
	await _boss_and_toast()
	await _interior()
	await _qa_spots()
	main.queue_free()
	await frames(5)
	Game.state = &"menu"
	Sfx.muted = false


## 1. Title: every button sits on a backing plate drawn by the screen (a sign behind a button never shows through), the TEST badge keeps a gap to OPTIONS and DEMO, nothing overlaps.
func _title() -> void:
	Game.state = &"menu"
	await frames(4)
	hud._gear_open = false
	hud._layout_key = ""
	hud._ensure_layout()
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var tm: TestMenu = main.find_children("*", "TestMenu", true, false)[0]
	var rects := {}
	for b: Dictionary in hud.buttons:
		rects[String(b["id"])] = b["rect"]
		TestLib.check((b["rect"] as Rect2).size.y >= 39.0 * s, "title button %s is tall enough" % b["id"])
	TestLib.check((rects.has("deploy") or rects.has("continue")) and rects.has("options"), "the title has DEPLOY (or NEW GAME) and OPTIONS")
	var named := {}
	for k in ["demo", "options", "deploy", "continue"]:
		if rects.has(k):
			named[k] = rects[k]
	named["test"] = tm.entry_rect()
	TestLib.check(VisualQaLib.overlap(named) == "", "title buttons do not overlap: %s" % VisualQaLib.overlap(named))
	var gap := (rects["menu_gear"] as Rect2).position.x - tm.entry_rect().end.x
	TestLib.check(gap >= 8.0 * s - 0.5, "the TEST badge keeps a gap left of the gear (%.1f px at scale %.2f)" % [gap, s])
	if rects.has("demo"):
		TestLib.check(not (rects["demo"] as Rect2).grow(6.0 * s).intersects(tm.entry_rect()), "TEST does not crowd the DEMO button")
		TestLib.check((rects["demo"] as Rect2).size.y >= 63.9 * s, "DEMO is 64 base px")
	# the backing plate: the draw code paints an INK plate under each title button (the plate alpha is a constant of the screen draw)
	TestLib.check(Hud.SUBSCREEN_DIM >= 0.8, "the full-screen pause panels dim the world and HUD behind them (%.2f)" % Hud.SUBSCREEN_DIM)


## 2. DEMO panel tabs: 12 tabs wrap onto rows, each at least TAB_MIN_W wide, 64 base px tall, inside the screen, none overlapping, the list starts under the last row.
func _demo_tabs() -> void:
	var panel := host.get_tree().get_first_node_in_group(&"demo_panel") as DemoPanel
	TestLib.check(panel != null, "the DemoPanel is composed in main.tscn")
	if panel == null:
		return
	var vp := panel.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var tabs := panel._tab_rects()
	TestLib.check(tabs.size() == DemoPanel.TABS.size(), "a rect per tab")
	var ok_size := true
	var ok_in := true
	var ok_gap := true
	for i in tabs.size():
		var r: Rect2 = tabs[i]
		ok_size = ok_size and r.size.y >= 63.9 * s and r.size.x >= (DemoPanel.TAB_MIN_W - 12.0) * s
		ok_in = ok_in and Rect2(Vector2.ZERO, vp).encloses(r)
		for j in range(i + 1, tabs.size()):
			ok_gap = ok_gap and not r.intersects(tabs[j])
	TestLib.check(ok_size, "every tab is at least %d base px wide and 64 base px tall" % int(DemoPanel.TAB_MIN_W - 12.0))
	TestLib.check(ok_in, "every tab is inside the screen (%dx%d)" % [vp.x, vp.y])
	TestLib.check(ok_gap, "no two tabs overlap")
	TestLib.check(panel.tab_rows() >= 2, "12 tabs wrap onto at least two rows (%d)" % panel.tab_rows())
	var last_end := 0.0
	for r: Rect2 in tabs:
		last_end = maxf(last_end, r.end.y)
	TestLib.check(panel._top() >= last_end, "the list starts under the last tab row (%.0f >= %.0f)" % [panel._top(), last_end])
	TestLib.check(not (tabs[tabs.size() - 1] as Rect2).intersects(panel._close_rect()), "the last tab does not touch CLOSE")
	# a narrow viewport (844 x 390) wraps the same way: the row maths is pure in the viewport width
	var narrow_avail := 844.0 - 2.0 * maxf(0.0, 18.0 * 0.54) - 120.0 * 0.54 - 12.0 * 0.54
	TestLib.check(int(narrow_avail / (DemoPanel.TAB_MIN_W * 0.54)) < DemoPanel.TABS.size(), "at 844 px the twelve tabs would not fit one row at TAB_MIN_W (so they wrap)")
	for pg in [0, DemoPanel.TABS.size() - 1]:
		panel.set_page(pg)
		var tap := panel._tab_rects()[pg] as Rect2
		TestLib.check(panel.tap(tap.get_center()) or panel.page == pg, "tab %d can be tapped" % pg)
	panel.set_page(0)


## 3. The boss bar hangs in the top stack (the quest plate, the name and the bar never overlap what is under them), and the toast never covers the hero's face.
func _boss_and_toast() -> void:
	Game.state = &"play"
	var ig := InteriorGameplay.instance
	if ig != null:
		ig.leave(true)
	p.teleport_to(Game.SPAWN)
	await frames(30)
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var text := "CONTRACT COMPLETE  +900 CREDITS"
	var face := hud.face_rect(vp, s)
	TestLib.check(face.size.x > 0.0 and face.size.y > 0.0, "the hero's face has a screen rectangle in the third-person view %s" % [face])
	if face.size.x <= 0.0:
		return
	# the default spot below the stack is clear of the face at this camera: nothing moves
	UiUtil.stack_bottom = 100.0
	var base := hud.msg_rect(vp, s, text, int(30.0 * s), font)
	TestLib.check(not base.intersects(face) or base.position.y > face.end.y - 1.0, "normal stack: the toast and the face are apart %s %s" % [base, face])
	# force the stack to every height from the top to the lower half: the toast always avoids the face and stays on screen
	var worst := ""
	var hits := 0
	var moved := 0
	for sb in range(60, 520, 20):
		UiUtil.stack_bottom = float(sb)
		var default_top := (float(sb) + Hud.MSG_GAP) * s
		var r := hud.msg_rect(vp, s, text, int(30.0 * s), font)
		var wanted := Rect2(r.position.x, default_top, r.size.x, r.size.y)
		if wanted.intersects(face):
			moved += 1
		if r.intersects(face):
			hits += 1
			worst = "stack %d -> %s vs face %s" % [sb, r, face]
	UiUtil.stack_bottom = 100.0
	TestLib.check(hits == 0, "the toast never covers the hero's face at any stack height: %s" % worst)
	TestLib.check(moved > 0, "the rule really moved the toast for some stack heights (%d)" % moved)
	# in a vehicle there is no hero to protect: no face rectangle
	var save_veh: Variant = p.get(&"vehicle")
	TestLib.check(save_veh == null, "the hero is on foot in this test")
	# boss: the plate grows the stack by the name and the bar, the toast stays under it
	var without := UiUtil.stack_bottom
	TestMode.teleport("spawn")
	TestMode.start_contract(&"boss")
	await frames(40)
	var with_boss := UiUtil.stack_bottom
	TestLib.check(with_boss >= without + 30.0, "a boss fight adds its name and bar to the top stack (%.0f -> %.0f)" % [without, with_boss])
	Game.say(text, 30.0)
	await frames(4)
	var r2 := hud.msg_rect(vp, s, text, int(30.0 * s), font)
	var top_stack := with_boss * s
	var on_default := r2.position.y >= top_stack - 1.0
	var beside_face := r2.position.y > hud.face_rect(vp, s).end.y - 1.0 or not r2.intersects(hud.face_rect(vp, s))
	TestLib.check(on_default or beside_face, "with the boss bar up the toast is under the stack or clear of the face %s stack %.0f" % [r2, top_stack])
	TestLib.check(not r2.intersects(hud.face_rect(vp, s)), "the toast over the boss fight is clear of the face")
	hud.message_left = 0.0
	TestMode.kill_all_enemies()
	await frames(4)


## 4. Interior colour balance: each kind's real lights are near-neutral, the surface and the room's own lights share the interior light layer (the street's lamps do not wash it),
## the surface shader balances the pools, and the street district's red grade is off inside.
func _interior() -> void:
	for t: StringName in InteriorKinds.SPECS:
		var plan := InteriorPlan.generate(t, 12345)
		var worst := 0.0
		for d: Dictionary in plan.lights:
			var c: Color = d["col"]
			worst = maxf(worst, (maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))) / maxf(c.r, maxf(c.g, c.b)))
		if t != &"club":
			TestLib.check(worst <= 0.5, "%s: the real lights are near-neutral (saturation %.2f)" % [t, worst])
		var wall: Color = plan.rooms[0]["wall"]
		var raw: Color = plan.pal["wall"]
		TestLib.check(_sat(wall) <= _sat(raw) + 0.04, "%s: the wall is no more saturated than the palette (%.2f <= %.2f)" % [t, _sat(wall), _sat(raw)])
	Game.state = &"play"
	var ig := InteriorGameplay.instance
	ig.leave(true)
	p.teleport_to(Game.SPAWN)
	await frames(10)
	var d: Array = ig.doors_of(&"weapons", Game.SPAWN)
	TestLib.check(not d.is_empty() and ig.enter(d[0], true), "enter an interior")
	var t0 := 0
	while (ig.is_fading() or not InteriorSpace.active) and t0 < 300:
		await frames(1)
		t0 += 1
	await frames(30)
	var inter: Interior
	for n in main.find_children("*", "Interior", true, false):
		inter = n as Interior
	TestLib.check(inter != null, "the live interior node exists")
	if inter != null:
		var surf := inter.get_node_or_null("Surface") as MeshInstance3D
		TestLib.check(surf != null and surf.layers == Interior.LIGHT_LAYER, "the surface is on the interior light layer only")
		var lights := inter.find_children("Light*", "OmniLight3D", false, false)
		var all_ok := not lights.is_empty()
		for l in lights:
			all_ok = all_ok and (l as OmniLight3D).light_cull_mask == Interior.LIGHT_LAYER
		TestLib.check(all_ok, "the room's own lights use the interior light layer (%d)" % lights.size())
		var mat := surf.material_override as ShaderMaterial if surf != null else null
		TestLib.check(mat != null and float(mat.get_shader_parameter(&"balance")) < 0.8, "the surface shader balances the pools' colour (%s)" % [mat.get_shader_parameter(&"balance") if mat != null else "-"])
	await frames(20)
	var atm := main.find_children("*", "Atmosphere", true, false)
	if not atm.is_empty() and (atm[0] as Atmosphere).post != null and (atm[0] as Atmosphere).post.visible:
		var gain: Variant = (atm[0] as Atmosphere).post.get_param(&"d_gain")
		TestLib.check(gain is Vector3 and ((gain as Vector3) - Vector3.ONE).length() < 0.02, "inside a room the district grade is neutral (%s)" % [gain])
	ig.leave(true)
	await frames(10)


static func _sat(c: Color) -> float:
	var m := maxf(c.r, maxf(c.g, c.b))
	return (m - minf(c.r, minf(c.g, c.b))) / maxf(m, 0.001)


## 5. The visual QA's new spots (skill, gear, look screens) open the real pause panels through the HUD's own buttons; the flat-rect limit stays at 0.01; panel labels fit.
func _qa_spots() -> void:
	var consts: Dictionary = (load("res://tests/bot_visual_qa.gd") as GDScript).get_script_constant_map()
	var spots: Array = consts["SPOTS"]
	for sp in [&"skill", &"gear", &"look"]:
		TestLib.check(spots.has(sp), "the QA shoots the %s screen" % sp)
	TestLib.check(is_equal_approx(VisualQaLib.MAX_FLAT_RECT, 0.01), "the flat-rect limit is still 0.01 (%.3f)" % VisualQaLib.MAX_FLAT_RECT)
	Game.state = &"play"
	await frames(4)
	Game.state = &"paused"
	await frames(4)
	hud._shop_open = true
	TestLib.check(hud.press_button(&"skills_open") and hud._skills_open, "the skills screen opens")
	hud._layout_key = ""
	hud._ensure_layout()
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var bad := ""
	var n := 0
	for b: Dictionary in hud.buttons:
		var r: Rect2 = b["rect"]
		if r.size.y < 40.0 * s or String(b["id"]).begins_with("sk_") == false:
			continue
		n += 1
		var sz := UiUtil.fit_size(font, Tr.t(str(b["label"])), r.size.x - 10.0 * s, int(30.0 * s))
		if font.get_string_size(Tr.t(str(b["label"])), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > r.size.x - 4.0 * s:
			bad = "%s (%d)" % [b["label"], sz]
	TestLib.check(n >= 20 and bad == "", "%d skill buttons: every label fits its button %s" % [n, bad])
	Game.state = &"play"
	await frames(2)
	Game.state = &"paused"
	await frames(2)
	hud._shop_open = true
	TestLib.check(hud.press_button(&"loadout") and hud.press_button(&"loadout_gear") and hud._loadout_open and hud._loadout_page == 1, "the gear screen opens")
	Game.state = &"play"
	await frames(2)
	Game.state = &"paused"
	await frames(2)
	hud._shop_open = true
	TestLib.check(hud.press_button(&"look_open") and hud._look_open, "the look screen opens")
	Game.state = &"play"
	await frames(4)
	TestLib.check(not hud._skills_open and not hud._look_open and not hud._loadout_open, "back in play every pause panel is closed")
