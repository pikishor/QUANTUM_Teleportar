extends RefCounted
## HUD additions of the gameplay-depth wave: the title's CONTINUE button, the pause menu's upgrade shop (rows, buy buttons, back), the wallet in the HUD, the contract plate and boss
## bar in the top stack, the tutorial prompt with its SKIP plate, and the minimap's contract markers and courier route line. Real Missions / Progress / Contracts / Story / EnemyManager.
## Run: tools/test.sh tests/test_hud_gameplay.gd

const SETTINGS := "user://test_hud_gameplay_settings.cfg"
const SAVE := "user://test_hud_gameplay_save.cfg"


class StubPlayer extends Node3D:
	var hp := 100.0
	var max_hp := 100.0
	var energy := 100.0
	var max_energy := 100.0
	var ammo := 30
	var mag := 30
	var reloading := false
	var vehicle: Node3D
	var quantum: Node
	var camera_rig: Node
	var last_hurt_time := -100.0
	var last_hurt_from := Vector3.ZERO

	func heal(v: float) -> void:
		hp = minf(max_hp, hp + v)

	func add_energy(v: float) -> void:
		energy = minf(max_energy, energy + v)


class World extends Node3D:
	var intersections: Array[Vector3] = []
	var building_rects: Array[Rect2] = [Rect2(-30, -30, 26, 26), Rect2(10, 10, 18, 18)]


var root: Node3D
var hud: Hud
var m: Missions
var prog: Progress
var c: Contracts
var story: Story
var pl: StubPlayer
var em: EnemyManager


func run(host: Node) -> void:
	seed(21)
	var was_muted := Sfx.muted
	Sfx.muted = true
	root = Node3D.new()
	host.add_child(root)
	var w := World.new()
	w.intersections = CityLayout.make_intersections()
	root.add_child(w)
	Game.world = w
	pl = StubPlayer.new()
	root.add_child(pl)
	Game.player = pl
	em = (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	root.add_child(em)
	m = (load("res://scenes/missions.tscn") as PackedScene).instantiate() as Missions
	root.add_child(m)
	story = (load("res://scenes/story.tscn") as PackedScene).instantiate() as Story
	root.add_child(story)
	await TestLib.frames(host, 3)
	prog = m.progress
	c = m.contracts
	c.set_physics_process(false)
	prog.path = SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	Game.state = &"menu"
	var scene := load("res://scenes/hud.tscn") as PackedScene
	hud = scene.instantiate() as Hud
	hud.settings_path = SETTINGS
	root.add_child(hud)
	await TestLib.frames(host, 3)

	await _title(host)
	await _shop(host)
	await _wallet_and_contract(host)
	await _tutorial(host)
	await _minimap(host)
	await _layouts(host)

	root.queue_free()
	await TestLib.frames(host, 2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	Game.world = null
	Game.player = null
	Game.state = &"play"
	Sfx.muted = was_muted


func _ids() -> Array:
	return hud.buttons.map(func(b: Dictionary) -> StringName: return b["id"])


func _button(id: StringName) -> Dictionary:
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b
	return {}


func _title(host: Node) -> void:
	prog.autosave_enabled = false
	Game.state = &"play"
	Game.state = &"menu"
	hud._ensure_layout()
	TestLib.check(_ids().has(&"deploy") and not _ids().has(&"continue") and _button(&"deploy")["label"] == "DEPLOY", "no save: the title offers DEPLOY only")
	TestLib.check(not hud.press_button(&"continue"), "CONTINUE does nothing without a save")
	# a save with progress
	prog.credits = 640
	prog.sector = 2
	prog.levels = Upgrades.set_levels({&"armour": 2})
	prog.reputation = 12
	prog.save_file()
	Game.state = &"play"
	Game.state = &"menu"
	hud._ensure_layout()
	TestLib.check(_ids()[0] == &"continue" and _ids().has(&"deploy") and _button(&"deploy")["label"] == "NEW GAME" and _button(&"continue")["label"] == "CONTINUE", "with a save the title offers CONTINUE first and NEW GAME")
	var cr: Rect2 = _button(&"continue")["rect"]
	var nr: Rect2 = _button(&"deploy")["rect"]
	var ui_s := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
	TestLib.check(cr.size.y >= nr.size.y and cr.end.y < nr.position.y, "CONTINUE is the primary button above NEW GAME (as tall, first)")
	TestLib.check(nr.size.y >= UiUtil.TOUCH_MIN * ui_s - 0.01, "NEW GAME meets the touch minimum (%.0f base px)" % (nr.size.y / ui_s))
	prog.autosave_enabled = true
	prog.credits = 0
	prog.levels = Upgrades.set_levels({})
	story.tutorial.force = true
	prog.tutorial_done = false
	TestLib.check(hud.press_button(&"continue") and Game.state == &"play", "CONTINUE starts the saved run")
	TestLib.check(prog.credits == 640 and Upgrades.level(&"armour") == 2 and story.chapter == 2 and m.cores.size() == 8, "credits, upgrades, chapter 3 and its 8 cores are restored (%d cores)" % m.cores.size())
	TestLib.check(not story.tutorial.active and not story.cards_active(), "no prologue and no tutorial after CONTINUE")
	story.tutorial.force = false
	prog.autosave_enabled = false
	# NEW GAME from the title
	Game.state = &"menu"
	hud._ensure_layout()
	TestLib.check(hud.press_button(&"deploy") and prog.credits == 0 and Upgrades.total_levels() == 0 and story.chapter == 0, "NEW GAME starts from scratch")
	Game.state = &"menu"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	Game.state = &"play"
	await TestLib.frames(host, 1)


func _shop(host: Node) -> void:
	Game.state = &"play"
	prog.new_campaign()
	hud.pause_game()
	hud._ensure_layout()
	TestLib.check(_ids().has(&"shop") and _ids().has(&"resume") and _ids().has(&"menu") and _ids().has(&"q0"), "the pause screen has RESUME, UPGRADES, the graphics rows and ABORT")
	TestLib.check(not hud.press_button(&"buy_damage"), "buy buttons do nothing outside the shop")
	TestLib.check(hud.press_button(&"shop") and hud._shop_open, "UPGRADES opens the shop")
	hud._ensure_layout()
	var ids := _ids()
	var buys := 0
	for id: StringName in Upgrades.IDS:
		buys += 1 if ids.has(StringName("buy_%s" % id)) else 0
	TestLib.check(buys == Upgrades.IDS.size() and ids.has(&"shop_back") and not ids.has(&"resume") and not ids.has(&"q0"), "the shop has a buy button per upgrade and BACK (%s)" % str(ids))
	TestLib.check(_button(&"buy_damage")["label"] == "BUY  %d" % Upgrades.price(&"damage", 0) and not _button(&"buy_damage")["on"], "a row shows its price and is dim without credits")
	var cue_muted := Sfx.muted
	Sfx.muted = false
	OS.delay_msec(60)
	Sfx.last_played = &""
	TestLib.check(not hud.press_button(&"buy_damage") and prog.level(&"damage") == 0, "a purchase without credits is refused")
	TestLib.check(Sfx.last_played == &"ui_deny", "a refused purchase plays ui_deny (%s)" % Sfx.last_played)
	var bank := Upgrades.price(&"damage", 0) + Upgrades.price(&"mag", 0) + 100
	prog.add_credits(bank)
	hud._layout_key = ""
	hud._ensure_layout()
	TestLib.check(_button(&"buy_damage")["on"] and _button(&"buy_armour")["label"] == "BUY  %d" % Upgrades.price(&"armour", 0), "with credits the row lights up")
	OS.delay_msec(60)
	TestLib.check(hud.press_button(&"buy_damage") and prog.credits == bank - Upgrades.price(&"damage", 0) and prog.level(&"damage") == 1, "pressing BUY spends and levels up")
	TestLib.check(Sfx.last_played == &"ui_purchase", "a purchase plays ui_purchase (%s)" % Sfx.last_played)
	Sfx.muted = cue_muted
	hud._ensure_layout()
	TestLib.check(_button(&"buy_damage")["label"] == "BUY  %d" % Upgrades.price(&"damage", 1), "the row now shows the next price")
	TestLib.check(hud.tap(_button(&"buy_mag")["rect"].get_center()) and prog.level(&"mag") == 1, "a tap on a buy button works")
	for i in 5:
		prog.grant_upgrade(&"reload")
	hud._layout_key = ""
	hud._ensure_layout()
	TestLib.check(_button(&"buy_reload")["label"] == "MAX" and not hud.press_button(&"buy_reload"), "a maxed upgrade says MAX and cannot be bought")
	hud._draw_screen()                 # exercises every shop draw path (the headless renderer ignores the drawing)
	TestLib.check(hud.press_button(&"shop_back") and not hud._shop_open, "BACK returns to the pause screen")
	hud._ensure_layout()
	TestLib.check(_ids().has(&"resume"), "the pause screen is back")
	hud.press_button(&"shop")
	Game.state = &"play"
	TestLib.check(not hud._shop_open, "resuming closes the shop")
	hud.pause_game()
	TestLib.check(not hud._shop_open, "pausing again opens the pause screen, not the shop")
	hud.press_button(&"resume")
	await TestLib.frames(host, 1)


func _wallet_and_contract(host: Node) -> void:
	Game.state = &"play"
	prog.new_campaign()
	prog.add_credits(1234)
	c._on_new_sector()
	hud._process(0.3)
	TestLib.check(hud._cred_text == "CREDITS  1234", "the HUD shows the wallet, not the score (%s)" % hud._cred_text)
	TestLib.check(hud._contract_text == "", "no contract plate while idle")
	hud._draw_hud()
	var base := UiUtil.stack_bottom
	c.offer(&"hack", Vector3(60.0, 0.0, 60.0))
	hud._process(0.3)
	TestLib.check(hud._contract_text.begins_with("CONTRACT  HACK NODE"), "an offer is on the HUD (%s)" % hud._contract_text)
	hud._draw_hud()
	TestLib.check(absf(UiUtil.stack_bottom - base) < 8.0, "the contract REPLACES the core objective line: one priority line, the stack does not grow (%.0f vs %.0f)" % [UiUtil.stack_bottom, base])
	# an active hack shows the thin progress bar
	pl.global_position = Vector3(61.0, 0.0, 61.0)
	c.tick(0.1)
	c.tick(3.0)
	hud._process(0.3)
	TestLib.check(c.state == &"active" and "HACK NODE" in hud._contract_text and "%" in hud._contract_text, "the hack line shows its percentage (%s)" % hud._contract_text)
	hud._draw_hud()
	TestLib.check(c.progress_fraction() > 0.0, "the plate has a progress bar (%.2f)" % c.progress_fraction())
	var with_bar := UiUtil.stack_bottom
	TestLib.check(with_bar > base + 2.0 and with_bar < base + 20.0, "the thin progress bar is the only thing the active contract adds under the line (%.0f vs %.0f)" % [with_bar, base])
	# the officer's boss bar
	c.abandon()
	c._on_new_sector()
	c.offer(&"officer", Vector3(60.0, 0.0, -60.0))
	pl.global_position = Vector3(61.0, 0.0, -59.0)
	c.tick(0.1)
	hud._process(0.3)
	TestLib.check(c.state == &"active" and not c.boss().is_empty(), "the officer contract exposes a boss bar")
	hud._draw_hud()
	TestLib.check(UiUtil.stack_bottom > with_bar - 1.0, "the boss bar sits under the contract plate (%.0f)" % UiUtil.stack_bottom)
	var o := c.target as Drone
	o.damage(o.max_hp * 0.4)
	c.tick(0.1)
	TestLib.check(absf(float(c.boss()["frac"]) - 0.6) < 0.02, "the bar follows his health (%.2f)" % float(c.boss()["frac"]))
	c.abandon()
	em.clear()
	c._on_new_sector()
	hud._process(0.3)
	TestLib.check(hud._contract_text == "", "the plate is gone when the contract ends")
	# end screens show score and credits
	Game.score = 321
	Game.state = &"dead"
	hud._ensure_layout()
	hud._draw_screen()
	Game.state = &"play"
	Game.score = 0


func _tutorial(host: Node) -> void:
	Game.state = &"play"
	var t := story.tutorial
	t.force = true
	prog.tutorial_done = false
	t.set_physics_process(false)
	t.touch_override = 1
	t.begin()
	hud._draw_hud()
	TestLib.check(t.skip_rect.size.x > 40.0 and t.skip_rect.size.y > 30.0, "the HUD places the SKIP plate (%s)" % str(t.skip_rect))
	var vp := hud.get_viewport().get_visible_rect().size
	TestLib.check(Rect2(Vector2.ZERO, vp).encloses(t.skip_rect), "the SKIP plate is on screen")
	var s := UiUtil.ui_scale(vp)
	TestLib.check(t.skip_rect.size.y >= 40.0 * s, "and big enough for a finger (%.0f px)" % t.skip_rect.size.y)
	# the prompt plate must clear the touch buttons zone on the right
	TestLib.check(t.skip_rect.end.x <= vp.x - StoryView.TOUCH_BUTTONS_W * s + 1.0 or not hud.touch_ui_on(), "the plate stays left of the touch buttons on phones")
	t.touch_override = 0
	hud._draw_hud()
	TestLib.check(t.skip_rect.size.x > 0.0, "the keyboard variant is drawn too")
	t.skip()
	hud._draw_hud()
	TestLib.check(t.skip_rect.size.x == 0.0, "the plate disappears with the tutorial")
	t.force = false
	t.touch_override = -1
	await TestLib.frames(host, 1)


func _minimap(host: Node) -> void:
	Game.state = &"play"
	c._on_new_sector()
	var mm := hud.minimap
	mm.size = Vector2(176, 176)
	pl.global_position = Vector3.ZERO
	c.offer(&"courier", Vector3(40.0, 0.0, 30.0))
	await TestLib.frames(host, 8)
	TestLib.check(mm.contract_markers == 1 and not mm.route_drawn, "an offer is one minimap marker, no route")
	pl.global_position = Vector3(41.0, 0.0, 31.0)
	c.tick(0.1)
	TestLib.check(c.state == &"active" and c.kind == &"courier", "the courier run starts")
	await TestLib.frames(host, 8)
	TestLib.check(mm.route_drawn and mm.contract_markers == 1, "the route line and the destination flag are drawn")
	c.abandon()
	c._on_new_sector()
	c.offer(&"hack", Vector3(30.0, 0.0, 30.0))
	pl.global_position = Vector3(31.0, 0.0, 31.0)
	c.tick(0.1)
	await TestLib.frames(host, 8)
	TestLib.check(mm.contract_markers == 1 and not mm.route_drawn, "a hack zone is a ring marker")
	c.abandon()
	em.clear()
	c._on_new_sector()
	await TestLib.frames(host, 8)
	TestLib.check(mm.contract_markers == 0, "no contract, no markers")


func _layouts(host: Node) -> void:
	var win := host.get_window()
	var old := win.size
	prog.add_credits(500)
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(960, 540)]:
		win.size = size
		await TestLib.frames(host, 3)
		var vp := host.get_viewport().get_visible_rect().size
		for st: StringName in [&"menu", &"paused", &"shop"]:
			Game.state = &"menu" if st == &"menu" else &"paused"
			hud._shop_open = st == &"shop"
			hud._has_save = st == &"menu"
			hud._layout_key = ""
			hud._ensure_layout()
			var ok := not hud.buttons.is_empty()
			var min_h := 9999.0
			for b: Dictionary in hud.buttons:
				var r: Rect2 = b["rect"]
				ok = ok and Rect2(Vector2.ZERO, vp).encloses(r)
				min_h = minf(min_h, r.size.y)
			TestLib.check(ok and min_h >= 40.0 * vp.y / 720.0 - 0.01, "%s buttons fit a %dx%d screen (min height %.0f px)" % [st, size.x, size.y, min_h])
	win.size = old
	hud._shop_open = false
	Game.state = &"play"
