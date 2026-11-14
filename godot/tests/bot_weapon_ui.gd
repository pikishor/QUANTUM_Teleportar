extends RefCounted
## Look-dev bot of the weapon screens with the whole roster owned (wave 113): the LOADOUT pages (class tabs, FAVOURITES, RECENT, attachments), the CATALOGUE pages and the two-level WEAPON wheel.
##   WUI_OUT=<dir> [WUI_STEPS=loadout_rifle,wheel] [MENU_NO3D=1] BOT_RES=2400x1080 BOT_USER_ARGS="--touch" tools/bot.sh res://tests/bot_weapon_ui.gd /tmp/x 100000 1
## Presses go through Hud.press_button (the path of a tap). The shots are numbered in the order of the steps.
var _i := 0
var _wait := 0
var _out := ""
var _hud: Hud
var _steps: Array[String] = []
const ALL := ["loadout_rifle", "loadout_fav", "loadout_recent", "loadout_melee", "loadout_blast", "loadout_quantum_att", "loadout_muzzle", "loadout_shotgun", "loadout_pistol", "cat_rifle", "cat_melee", "cat_energy", "cat_explosives",
		"wheel", "wheel_ring_rifle", "wheel_ring_recent", "wheel_ring_fav", "wheel_ring_melee", "hud_pop_long", "hud_more_ammo"]


func _init() -> void:
	_out = OS.get_environment("WUI_OUT")
	var only := OS.get_environment("WUI_STEPS")
	_steps.assign(ALL if only == "" else Array(only.split(",", false)))
	WeaponDefs.hero_mode = true                                   # every weapon owned: the point of the 200+ layouts
	WeaponBrowser.reset()
	for id: StringName in [&"a_pillar", &"m_phaseblade", &"q_ppistol", &"s_rivet", &"x_frost"]:
		WeaponBrowser.toggle_favourite(id)
	for id: StringName in [&"e_pulse", &"g_bulwark", &"c_scout", &"b_anvil", &"p_hush", &"carbine"]:
		WeaponBrowser.note_used(id)                               # the last one is the newest


func step(_t: float, _dt: float) -> bool:
	if _hud == null:
		var n := Engine.get_main_loop() as SceneTree
		_hud = n.get_first_node_in_group(&"hud") as Hud
		if _hud == null or Game.player == null:
			return false
		for a in n.root.find_children("*", "AutoQuality", true, false):
			(a as AutoQuality).enabled = false
		DirAccess.make_dir_recursive_absolute(_out)
		WeaponPreview.freeze = true
		if OS.get_environment("MENU_NO3D") == "1":
			_hud.get_viewport().disable_3d = true
		if _hud.touch != null:
			_hud.touch.controls_on = true
		_begin()
		return false
	if _wait > 0:
		_wait -= 1
		return false
	_hud.get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [_out, _i, _steps[_i]])
	print("WUISHOT ", _steps[_i])
	_i += 1
	if _i >= _steps.size():
		_wait = 1 << 20
		_hud.get_tree().quit()
		return true
	_begin()
	return false


func _press(ids: Array) -> void:
	for id: StringName in ids:
		_hud.press_button(id)
		_hud._ensure_layout()


func _menu(ids: Array) -> void:
	if _hud.touch != null and _hud.touch.wheel.is_open:
		_hud.touch.wheel.close()
	Game.state = &"play"
	Game.state = &"paused"
	_hud._on_state(&"paused")
	_hud.screen_age = 5.0
	if Game.progress != null:
		Game.progress.credits = 4200
	_hud._ensure_layout()
	_press(ids)


func _wedge(id: StringName) -> int:
	var tc := _hud.touch
	for k in tc.wheel.items.size():
		if tc.wheel.item_id(k) == id:
			return k
	return -1


func _wheel_open() -> void:
	Game.state = &"play"
	_hud._on_state(&"play")
	var tc := _hud.touch
	tc.controls_on = true
	tc.wheel.close()
	tc._open_wheel(&"weapon", -1, Vector2.ZERO)


func _begin() -> void:
	var name := _steps[_i]
	MenuFlags.all_extras = false
	ShopScreen.weapon_page = 0
	match name:
		"loadout_rifle":
			_menu([&"loadout", &"wheel_a_pillar"])
		"loadout_fav":
			_menu([&"loadout"])
			LoadoutScreen.page = 0
			_hud._layout_key = ""
			_hud._ensure_layout()
		"loadout_recent":
			_menu([&"loadout"])
			_press([&"wheelcls_next"])
		"loadout_melee":
			_menu([&"loadout", &"wheel_m_arcsabre"])
		"loadout_blast":
			_menu([&"loadout", &"wheel_railgun"])
		"loadout_quantum_att":
			for part: StringName in Attachments.IDS:
				Attachments.give(part)
			_menu([&"loadout", &"wheel_q_ppistol"])
		"loadout_muzzle":
			for part: StringName in [&"reddot", &"suppressor", &"foregrip", &"extended", &"laser"]:
				Attachments.give(part)
				Attachments.equip(&"a_pillar", part)
			_menu([&"loadout", &"wheel_a_pillar", &"slot_barrel"])
		"loadout_shotgun":
			_menu([&"loadout", &"wheel_g_bulwark", &"slot_barrel"])
		"loadout_pistol":
			_menu([&"loadout", &"wheel_p_spark", &"slot_grip"])
		"cat_rifle":
			_menu([&"hero_open", &"hero_tab_weapons", &"wcls_next", &"wcls_next", &"wsel_a_pillar"])
		"cat_melee":
			_menu([&"hero_open", &"hero_tab_weapons"])
			WeaponsScreen.select(&"m_arcsabre")
			_press([&"wsel_m_arcsabre"])
		"cat_energy":
			_menu([&"hero_open", &"hero_tab_weapons"])
			WeaponsScreen.select(&"e_ioncan")
			_press([&"wsel_e_ioncan"])
		"cat_explosives":
			_menu([&"hero_open", &"hero_tab_weapons"])
			WeaponsScreen.select(&"c4")
			_press([&"wsel_c4"])
		"wheel":
			_wheel_open()
		"wheel_ring_rifle":
			_wheel_open()
			_hud.touch._wheel_pick(_wedge(&"rifle"))
		"wheel_ring_recent":
			_wheel_open()
			_hud.touch._wheel_pick(_wedge(&"recent"))
		"wheel_ring_fav":
			_wheel_open()
			_hud.touch._wheel_pick(_wedge(&"fav"))
		"wheel_ring_melee":
			_wheel_open()
			_hud.touch._wheel_pick(_wedge(&"melee"))
		"hud_pop_long":                                              # the pop plate of a weapon with a long name, a moment after the switch
			Game.state = &"play"
			_hud._on_state(&"play")
			_hud.touch.controls_on = true
			_hud.touch.wheel.close()
			(Game.player as Player).weapon.switch_to(&"n_breaker", true)
			(Game.player as Player).weapon.switch_to(&"n_horizon", true)
		"hud_more_ammo":                                             # the MORE cluster with the AMMO button of a weapon that carries several ammo types
			Game.state = &"play"
			_hud._on_state(&"play")
			_hud.touch.controls_on = true
			_hud.touch.wheel.close()
			(Game.player as Player).weapon.switch_to(&"a_pillar", true)
			_hud.touch.more_open = true
	_wait = 8
