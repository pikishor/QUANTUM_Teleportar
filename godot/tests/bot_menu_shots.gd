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
		["title_options", &"menu", [&"options"]],
		["pause", &"paused", []],
		["pause_more", &"paused", [&"menu_gear"]],
		["hero_upgrades", &"paused", [&"menu_gear", &"hero_open"]],
		["hero_weapons", &"paused", [&"menu_gear", &"hero_open", &"hero_tab_weapons"]],
		["hero_skills", &"paused", [&"menu_gear", &"hero_open", &"hero_tab_skills"]],
		["hero_craft", &"paused", [&"menu_gear", &"hero_open", &"hero_tab_craft"]],
		["loadout", &"paused", [&"loadout"]],
		["gear", &"paused", [&"loadout", &"loadout_gear"]],
		["options", &"paused", [&"options"]],
		["options2", &"paused", [&"options", &"opt_page"]],
		["look", &"paused", [&"menu_gear", &"look_open"]],
		["safehouse", &"paused", [&"menu_gear", &"sh_open"]],
		["missions", &"paused", [&"menu_gear", &"side_open"]],
		["heists", &"paused", [&"menu_gear", &"heist_open"]],
		["achievements", &"paused", [&"menu_gear", &"ach"]],
		["arena", &"paused", [&"menu_gear", &"arena_open"]],
		["map", &"paused", [], &"map"],
		["map_waypoint", &"paused", [], &"map_wp"],
		["map_zoom", &"paused", [], &"map_zoom"],
		["map_danger", &"paused", [], &"map_danger"],
		["dead", &"dead", []],
	]
	var only := OS.get_environment("MENU_ONLY")                  # comma list of step names: render just those
	if only != "":
		var keep := only.split(",", false)
		_steps = _steps.filter(func(st: Array) -> bool: return keep.has(String(st[0])))


func step(_t: float, _dt: float) -> bool:
	if _hud == null:
		var n := Engine.get_main_loop() as SceneTree
		_hud = n.get_first_node_in_group(&"hud") as Hud
		if _hud == null or Game.player == null:
			return false
		for a in n.root.find_children("*", "AutoQuality", true, false):
			(a as AutoQuality).enabled = false
		DirAccess.make_dir_recursive_absolute(_out)
		if _hud.touch != null:
			_hud.touch.controls_on = true             # the phone: no desktop key footer
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
		_i = _steps.size() - 1
		_wait = 1 << 20
		_hud.get_tree().quit()
		return true
	_begin()
	return false


func _ids() -> Array:
	return _hud.buttons.map(func(b: Dictionary) -> StringName: return b["id"])


func _begin() -> void:
	var st: Array = _steps[_i]
	var mo := _hud.touch.get_node_or_null("MapScreen") as MapScreen if _hud.touch != null else null
	if mo != null and mo.is_open():
		mo.close_screen()
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
	if st.size() > 3 and String(st[3]).begins_with("map"):
		var ms := _hud.touch.get_node_or_null("MapScreen") as MapScreen
		if ms != null:
			ms.discover(Game.player.global_position)
			ms.open()
			if st[3] == &"map_wp":
				ms.set_waypoint(Vector3(-280.0, 0.0, 330.0))
			if st[3] == &"map_danger":
				Factions.add_rep(Game.progress, Factions.primary(0), -60.0)
				Game.heat = 0.7
				ms.zoom_by(1.7, ms._rect.get_center())
			if st[3] == &"map_zoom":
				ms.locate()
				ms.zoom_by(3.2, ms._rect.get_center())
				ms.locate()
			_hud._screen.visible = false
	_wait = 8 if st.size() > 3 else 6
