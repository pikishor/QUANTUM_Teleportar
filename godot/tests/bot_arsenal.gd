extends RefCounted
## Look-dev bot of the ARSENAL screens (wave 114): the LOADOUT and the catalogue with 200+ weapons, every tab and filter, one frame per step.
##   ARS_OUT=<dir> [ARS_STEPS=parts,ammo] [MENU_NO3D=1] BOT_RES=2400x1080 BOT_USER_ARGS="--touch" tools/bot.sh res://tests/bot_arsenal.gd /tmp/x 100000 1
## Presses go through Hud.press_button (the path of a tap). The shots are numbered in the order of the steps. ARS_OWN=0 keeps the hero's own few weapons (locked ones in the list).
## Steps (ARS_STEPS, comma separated): the screens loadout, stats_blast, parts, parts_fitted, ammo, catalogue_locked, filter_new, filter_fav_empty, sort_damage, scrolled, view3d, gear, slots; the play
## layer reveal_flash / reveal_mid / reveal_late (CrateReveal frozen at one moment), hud_plate (pop card + kill feed lines dated into the future: the software renderer needs seconds per frame),
## wheel_classes, wheel_ring, crate_pics (the hero looks at the market crate). MENU_NO3D=1 turns the 3D world off behind the menus (faster). BOT_RES=1688x780 is the 844x390 phone aspect.
var _i := 0
var _wait := 0
var _out := ""
var _hud: Hud
var _steps: Array[String] = []
const ALL := ["loadout", "stats_blast", "parts", "parts_fitted", "ammo", "catalogue_locked", "filter_new", "filter_fav_empty", "sort_damage", "scrolled", "view3d", "gear", "slots",
		"reveal_flash", "reveal_mid", "reveal_late", "hud_plate", "wheel_classes", "wheel_ring", "crate_pics"]


func _init() -> void:
	_out = OS.get_environment("ARS_OUT")
	var only := OS.get_environment("ARS_STEPS")
	_steps.assign(ALL if only == "" else Array(only.split(",", false)))


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
		if _steps[_i] == "crate_pics" and _wait <= 3:                 # the camera of a teleported hero finds its own heading first: look at the crate once the street is there
			var cp := WeaponLadder.crate_pos(0)
			(Game.player as Player).camera_rig.aim_at(cp + Vector3(0.0, 2.2, 0.0))
		return false
	_hud.get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [_out, _i, _steps[_i]])
	print("ARSSHOT ", _steps[_i])
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
		_hud._layout_key = ""
		_hud._ensure_layout()


func _menu(ids: Array, own_all := true) -> void:
	if _hud.touch != null and _hud.touch.wheel.is_open:
		_hud.touch.wheel.close()
	WeaponDefs.hero_mode = own_all
	if not own_all:
		for id: StringName in [&"a_pillar", &"s_rivet", &"p_hush", &"m_arcsabre", &"gr_frag"]:
			WeaponDefs.unlock(id)
	Game.state = &"play"
	Game.state = &"paused"
	_hud._on_state(&"paused")
	_hud.screen_age = 5.0
	_hud._sub_t = 5.0
	if Game.progress != null:
		Game.progress.credits = 4200
	_hud._layout_key = ""
	_hud._ensure_layout()
	_press(ids)


func _play() -> void:
	if _hud.touch != null and _hud.touch.wheel.is_open:
		_hud.touch.wheel.close()
	Game.state = &"play"
	_hud._on_state(&"play")
	_hud._shop_open = false
	_hud._loadout_open = false


func _begin() -> void:
	var name := _steps[_i]
	if is_instance_valid(CrateReveal.current):                      # a frozen reveal of the step before is not part of this frame
		CrateReveal.current.free()
		CrateReveal.current = null
	CrateReveal._queue.clear()
	_hud.feed.clear()                                               # the dated lines of hud_plate are not part of the other frames
	MenuFlags.all_extras = false
	ShopScreen.weapon_page = 0
	Attachments.reset()
	match name:
		"loadout":
			_menu([&"loadout", &"wheel_a_pillar"])
		"stats_blast":
			_menu([&"loadout", &"ars_filter_all", &"ars_cls_next", &"ars_cls_next", &"ars_cls_next", &"ars_cls_next", &"ars_cls_next", &"ars_cls_next", &"ars_cls_next", &"ars_cls_next", &"ars_cls_next", &"ars_cls_next"])
			_press([&"wheel_la_rocket"] if WeaponDefs.DEFS.has(&"la_rocket") else [])
		"parts":
			for part: StringName in [&"reddot", &"scope", &"suppressor", &"foregrip", &"laser"]:
				Attachments.give(part)
			_menu([&"loadout", &"wheel_a_pillar", &"ars_tab_parts", &"ars_part_scope"])
		"parts_fitted":
			for part: StringName in [&"reddot", &"scope", &"suppressor", &"foregrip", &"laser"]:
				Attachments.give(part)
			Attachments.equip(&"a_pillar", &"suppressor")
			Attachments.equip(&"a_pillar", &"laser")
			_menu([&"loadout", &"wheel_a_pillar", &"ars_tab_parts", &"ars_slottab_barrel", &"ars_part_suppressor"])
		"ammo":
			_menu([&"loadout", &"wheel_a_pillar", &"ars_tab_ammo"])
		"catalogue_locked":
			_menu([&"hero_open", &"hero_tab_weapons", &"ars_filter_locked", &"wsel_a_flint"], false)
		"filter_new":
			_menu([&"hero_open", &"hero_tab_weapons", &"ars_filter_new"], false)
		"filter_fav_empty":
			WeaponBrowser.reset()
			_menu([&"loadout", &"ars_filter_fav"])
		"sort_damage":
			_menu([&"loadout", &"ars_filter_all", &"ars_sort", &"ars_sort", &"ars_sort"])
		"scrolled":
			_menu([&"loadout", &"ars_filter_all"])
			Arsenal.scroll_by(&"loadout", Arsenal.ROW * 4.0)
			_hud._layout_key = ""
			_hud._ensure_layout()
		"view3d":
			_menu([&"loadout", &"wheel_a_pillar", &"ars_view3d"])
		"gear":
			_menu([&"hero_open", &"hero_tab_weapons", &"ars_cls_prev", &"wsel_frag"], true)
		"slots":
			_menu([&"loadout", &"wheel_p_spark", &"ars_slot_1"])
		"reveal_flash", "reveal_mid", "reveal_late":
			_play()
			CrateReveal._quiet = 0
			CrateReveal.request(&"railgun", "CRATE OPENED", true)
			if CrateReveal.current != null:
				var v := CrateReveal.current
				v.age = 0.1 if name == "reveal_flash" else (1.1 if name == "reveal_mid" else 2.6)
				v.set_process(false)                                            # the shot is of one moment of the reveal
				v.queue_redraw()
		"hud_plate":
			CrateReveal.next_source = ""
			_play()
			WeaponDefs.hero_mode = true
			(Game.player as Player).weapon.switch_to(&"scatter", true)
			var later := PlayerUtil.now() + 40.0                            # the software renderer needs seconds per frame: the lines and the pop are dated into the future
			_hud.feed.push(HudFeed.KILL, "OPERATIVE", later, &"railgun")
			_hud.feed.push(HudFeed.KILL, "BRUTE", later, &"a_pillar")
			_hud.feed.push(HudFeed.PICKUP, "NEW WEAPON  FLINT RIFLE", later, HudFeed.weapon_of_line("NEW WEAPON  FLINT RIFLE"))
			_hud._wpop_id = &"scatter"
			_hud._wpop_until = Time.get_ticks_msec() + 40000
			_wait = 3
			return
		"wheel_classes", "wheel_ring":
			_play()
			WeaponDefs.hero_mode = true
			var tc := _hud.touch
			tc.controls_on = true
			tc.wheel.close()
			tc._open_wheel(&"weapon", -1, Vector2.ZERO)
			if name == "wheel_ring":
				for i in tc.wheel.items.size():
					if tc.wheel.item_id(i) == &"rifle":
						tc._wheel_pick(i)
		"crate_pics":
			_play()
			WeaponDefs.hero_mode = false
			WeaponDefs.reset_unlocked()
			var cp := WeaponLadder.crate_pos(0)
			var p := Game.player as Player
			p.teleport_to(cp + Vector3(7.0, 0.6, 9.0))
			p.camera_rig.aim_at(cp + Vector3(0.0, 2.2, 0.0))
			_wait = 40
			return
	_wait = 8
