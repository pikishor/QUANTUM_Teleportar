extends RefCounted
## DEV BOT of the wave 114 play critic: texture memory while the weapon screens are used, at the tier given by QUALITY (tools/bot.sh). Opens the LOADOUT with every weapon owned, scrolls the whole list of 229, looks at the
## card of one weapon of every class, opens the weapon wheel and a class ring, closes it all and prints W114MEM lines (RenderingServer texture memory in MB, the page cache of WeaponPics).
##   QUALITY=0 BOT_RES=1688x780 tools/bot.sh res://tests/bot_w114_mem.gd /tmp/x 100000 1
## The limits are LOW 200 / MED 260 / HIGH 360 MB (scripts/common/perf_probe.gd BUDGETS; the street itself is 112 / 143 / 209 after wave 114).

var _hud: Hud
var _i := 0
var _wait := 0
var _steps: Array[Callable] = []
var _names: Array[String] = []
var _peak := 0.0
var _cards: Array[StringName] = []


func _mb() -> float:
	return float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576.0


func _note(tag: String) -> void:
	var m := _mb()
	_peak = maxf(_peak, m)
	print("W114MEM %-28s tex %.1f MB  peak %.1f  page loads %d  pages now %s" % [tag, m, _peak, WeaponPics.page_loads, str(WeaponPics.pages_loaded())])


func _open_loadout() -> void:
	WeaponDefs.hero_mode = true
	Game.state = &"play"
	Game.state = &"paused"
	_hud._on_state(&"paused")
	_hud.screen_age = 5.0
	_hud._sub_t = 5.0
	_hud._layout_key = ""
	_hud._ensure_layout()
	_hud.press_button(&"loadout")
	_hud._layout_key = ""
	_hud._ensure_layout()


func _build() -> void:
	_steps.clear()
	_names.clear()
	_add("street", func() -> void: pass)
	_add("loadout opened", func() -> void: _open_loadout())
	_add("scroll rows", func() -> void:
		var rows := Arsenal._rows(&"loadout")
		for r in rows:
			Arsenal.scroll_by(&"loadout", Arsenal.ROW)
			_hud._layout_key = ""
			_hud._ensure_layout()
			_hud._screen.queue_redraw())
	_add("scrolled", func() -> void: pass)
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		var ids := WeaponDefs.ids_in_class(cls)
		if not ids.is_empty():
			_cards.append(ids[ids.size() / 2])
	for id: StringName in _cards:
		_add("card %s" % id, func() -> void:
			_hud.press_button(StringName("wheel_%s" % id))
			_hud._layout_key = ""
			_hud._ensure_layout())
	_add("back to the street", func() -> void:
		_hud.press_button(&"loadout_back")
		Game.state = &"play"
		_hud._on_state(&"play"))
	_add("street again", func() -> void: pass)
	_add("wheel opened", func() -> void:
		if _hud.touch != null:
			_hud.touch.controls_on = true
			_hud.touch._open_wheel(&"weapon", -1, Vector2.ZERO))
	_add("wheel ring rifle", func() -> void:
		if _hud.touch != null:
			for i in _hud.touch.wheel.items.size():
				if _hud.touch.wheel.item_id(i) == &"rifle":
					_hud.touch._wheel_pick(i)
					break)
	_add("wheel closed", func() -> void:
		if _hud.touch != null:
			_hud.touch.wheel.close())


func _add(name: String, f: Callable) -> void:
	_names.append(name)
	_steps.append(f)


func step(_t: float, _dt: float) -> bool:
	if _hud == null:
		var n := Engine.get_main_loop() as SceneTree
		_hud = n.get_first_node_in_group(&"hud") as Hud
		if _hud == null or Game.player == null:
			return false
		for a in n.root.find_children("*", "AutoQuality", true, false):
			(a as AutoQuality).enabled = false
		_build()
		_wait = 20
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _i > 0:
		_note(_names[_i - 1])
	if _i >= _steps.size():
		print("W114MEM RESULT peak %.1f MB at quality %d" % [_peak, Game.quality])
		_hud.get_tree().quit()
		return true
	_steps[_i].call()
	_i += 1
	_wait = 10
	return false
