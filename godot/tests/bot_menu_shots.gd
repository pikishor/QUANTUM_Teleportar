extends RefCounted
## Menu screenshot bot: title, pause, MORE, HERO tabs, map, loadout at the bot resolution. Use:
##   MENU_OUT=<dir> BOT_RES=844x390 tools/bot.sh res://tests/bot_menu_shots.gd /tmp/x 100000 1
## Presses go through Hud.press_button (the same path as a tap); ids that do not exist in this build are skipped.
var _i := 0
var _wait := 0
var _out := ""
var _hud: Hud
var _steps: Array = []


func _init() -> void:
	_out = OS.get_environment("MENU_OUT")
	_steps = [
		["title", &"menu", []],
		["title_more", &"menu", [&"menu_gear"]],
		["pause", &"paused", []],
		["pause_more", &"paused", [&"menu_gear"]],
		["hero_upgrades", &"paused", [&"menu_gear", &"hero_open"]],
		["hero_skills", &"paused", [&"menu_gear", &"hero_open", &"hero_tab_skills"]],
		["hero_craft", &"paused", [&"menu_gear", &"hero_open", &"hero_tab_craft"]],
		["hero_weapons", &"paused", [&"menu_gear", &"hero_open", &"hero_tab_weapons"]],
		["loadout", &"paused", [&"loadout"]],
		["options", &"paused", [&"options"]],
		["title_more", &"menu", [&"menu_gear"]],
	]


func step(_t: float, _dt: float) -> bool:
	if _hud == null:
		var n := Engine.get_main_loop() as SceneTree
		_hud = n.get_first_node_in_group(&"hud") as Hud
		if _hud == null or Game.player == null:
			return false
		for a in n.root.find_children("*", "AutoQuality", true, false):
			(a as AutoQuality).enabled = false
		DirAccess.make_dir_recursive_absolute(_out)
		_begin()
		return false
	if _wait > 0:
		_wait -= 1
		return false
	var vp := _hud.get_viewport()
	vp.get_texture().get_image().save_png("%s/%02d_%s.png" % [_out, _i, _steps[_i][0]])
	print("MENUSHOT ", _steps[_i][0], " ", _ids())
	_i += 1
	if _i >= _steps.size():
		return true
	_begin()
	return false


func _ids() -> Array:
	return _hud.buttons.map(func(b: Dictionary) -> StringName: return b["id"])


func _begin() -> void:
	var st: Array = _steps[_i]
	Game.state = &"play"
	Game.state = st[1]
	_hud._on_state(st[1])
	_hud.screen_age = 5.0
	if Game.progress != null:
		Game.progress.credits = 700 if String(st[0]).begins_with("hero") else 0
	_hud._ensure_layout()
	for id: StringName in st[2]:
		_hud.press_button(id)
		_hud._ensure_layout()
	_wait = 6
