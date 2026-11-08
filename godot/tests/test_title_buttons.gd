extends RefCounted
## The title and pause screens keep every primary button at least UiUtil.TOUCH_MIN (64 base px) tall (NEW GAME, CHAPTERS, UPGRADES were 44), inside the screen, without overlap and
## clear of the BEST / controls footer, at 1280x720, 1600x720, 960x540, 1024x768 and the phone shape 844x390, in every layout the screens have (save and / or unlocked chapters).
## Run: tools/test.sh tests/test_title_buttons.gd

const Env := preload("res://tests/player_env.gd")
const SETTINGS := "user://test_title_buttons_settings.cfg"

class StubProgress extends Node:
	var credits := 0
	var reputation := 0
	var chapters := false
	var save := false

	func can_select_chapter() -> bool:
		return chapters

	func has_save() -> bool:
		return save


var e := Env.new()
var hud: Hud
var stub: StubProgress


func _rect(id: StringName) -> Rect2:
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b["rect"]
	return Rect2()


func _layout(state: StringName, save: bool, chapters: bool, more := false) -> void:
	stub.save = save
	stub.chapters = chapters
	Game.state = state
	hud._has_save = save
	hud._chapters_open = false
	hud._shop_open = false
	hud._gear_open = more
	hud._layout_key = ""
	hud._ensure_layout()


func _check_screen(label: String, vp: Vector2, s: float, primary: Array[StringName], bottom_limit: float) -> void:
	var inside := true
	var overlap := false
	var lowest := 0.0
	for b: Dictionary in hud.buttons:
		var r: Rect2 = b["rect"]
		inside = inside and Rect2(Vector2.ZERO, vp).encloses(r)
		lowest = maxf(lowest, r.end.y)
		for b2: Dictionary in hud.buttons:
			overlap = overlap or (b != b2 and r.intersects(b2["rect"]))
	TestLib.check(inside and not overlap, "%s: every button is on screen and none overlaps" % label)
	TestLib.check(lowest <= bottom_limit, "%s: the lowest button ends at %.0f, above the footer (%.0f)" % [label, lowest, bottom_limit])
	for id in primary:
		var r := _rect(id)
		TestLib.check(r.size.y >= UiUtil.TOUCH_MIN * s - 0.01, "%s: %s is %.1f base px tall (>= %.0f)" % [label, id, r.size.y / s, UiUtil.TOUCH_MIN])
		var hit := true
		for q: Vector2 in [r.get_center(), r.position + Vector2(2, 2), r.end - Vector2(2, 2)]:
			hit = hit and hud._button_at(q) == id
		TestLib.check(hit, "%s: a touch anywhere in %s hits it" % [label, id])


func run(host: Node) -> void:
	await e.setup(host)
	stub = StubProgress.new()
	e.root.add_child(stub)
	var old_progress := Game.progress
	Game.progress = stub
	hud = (load("res://scenes/hud.tscn") as PackedScene).instantiate() as Hud
	hud.settings_path = SETTINGS
	e.root.add_child(hud)
	await e.frames(3)
	TestLib.check(UiUtil.TOUCH_MIN == 64.0, "the touch minimum is 64 base px")
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 540), Vector2i(1024, 768), Vector2i(844, 390)]:
		win.size = size
		await e.frames(3)
		var vp := hud.get_viewport().get_visible_rect().size
		var s := UiUtil.ui_scale(vp)
		var tag := "%dx%d" % [size.x, size.y]
		# the title: PLAY / CONTINUE, OPTIONS and MORE, whatever the save or chapter state is
		_layout(&"menu", true, true)
		_check_screen(tag + " title (save, chapters)", vp, s, [&"continue", &"options", &"menu_gear"], vp.y - 90.0 * s - 18.0 * s)
		TestLib.check(_rect(&"options").end.x < _rect(&"menu_gear").position.x and is_equal_approx(_rect(&"options").position.y, _rect(&"menu_gear").position.y), "%s: OPTIONS and MORE share one row" % tag)
		_layout(&"menu", false, false)
		_check_screen(tag + " title (first run)", vp, s, [&"deploy", &"options", &"menu_gear"], vp.y - 90.0 * s - 18.0 * s)
		TestLib.check(hud.buttons.size() == 3, "%s: the title shows three buttons" % tag)
		# the title's MORE page: NEW GAME, CHAPTERS, DEMO, ARENA, BACK
		_layout(&"menu", true, true, true)
		_check_screen(tag + " title MORE", vp, s, [&"deploy", &"chapters", &"more_back"], vp.y - 90.0 * s - 18.0 * s)
		# pause with progress: RESUME, MAP, LOADOUT, OPTIONS, MORE
		_layout(&"paused", true, true)
		_check_screen(tag + " pause", vp, s, [&"resume", &"pause_map", &"loadout", &"hero_open", &"options", &"menu_gear"], vp.y - 40.0 * s - 18.0 * s)
		TestLib.check(hud.buttons.size() == 6, "%s: the pause menu shows six buttons (RESUME, MAP, LOADOUT, UPGRADES, OPTIONS, EXTRAS)" % tag)
		# the pause MORE page: HERO, MISSIONS, HEISTS, SUIT, SAFEHOUSE, ACHIEVEMENTS, PHOTO, ARENA, CHAPTERS, ABORT, BACK
		MenuFlags.all_extras = true                                      # the cut screens are listed only with the flag
		_layout(&"paused", true, true, true)
		_check_screen(tag + " pause EXTRAS (all)", vp, s, [&"side_open", &"heist_open", &"look_open", &"sh_open", &"ach", &"photo_open", &"arena_open", &"chapters", &"menu", &"more_back"], vp.y - 40.0 * s - 18.0 * s)
		MenuFlags.all_extras = false
		_layout(&"paused", true, true, true)
		_check_screen(tag + " pause EXTRAS", vp, s, [&"look_open", &"photo_open", &"chapters", &"menu", &"more_back"], vp.y - 40.0 * s - 18.0 * s)
	win.size = old
	await e.frames(3)
	Game.state = &"play"
	hud.queue_free()
	stub.queue_free()
	Game.progress = old_progress
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	await e.frames(2)
	await e.teardown()
