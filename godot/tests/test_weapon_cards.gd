extends RefCounted
## Weapons with pictures and numbers (owner round 4): a picture for every weapon, throwable, gadget, vehicle and enemy; the info card numbers and bars; damage falloff by range and blast falloff with
## cover; the launcher's landing ring and lock; the WEAPONS catalogue in the real HUD (every weapon with where to get it, BUY / EQUIP, 64 px targets); the loadout INFO button; the crates on the map;
## the damage numbers option. Run: tools/test.sh tests/test_weapon_cards.gd   (real scene, about 25 s)

var host: Node


func run(h: Node) -> void:
	host = h
	_data()
	_icons()
	_numbers()
	await _live()


func _data() -> void:
	TestLib.check(WeaponDefs.IDS.size() >= 43, "forty-three or more weapons (%d)" % WeaponDefs.IDS.size())
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		var n := WeaponDefs.in_class(cls).size()
		TestLib.check(n >= 3, "class %s has at least three variants (%d; the loadout pages a long class eight at a time, wave 113 grew the roster to 180+)" % [cls, n])
	TestLib.check(Gear.THROW_IDS.size() >= 3, "three or more throwables")
	for id: StringName in WeaponDefs.IDS:
		TestLib.check(ResourceLoader.exists("res://assets/models/ow_%s.glb" % id) or WeaponModels.mesh(id) != null, "%s has a model" % id)
		TestLib.check(WeaponDefs.DEFS.has(id) and Economy.weapon_price(id) >= 0 and WeaponLadder.route_text(id) != "", "%s has a price and a route" % id)
		var seen := WeaponStats.where(id)
		TestLib.check(not seen.is_empty(), "%s says where to get it (%s)" % [id, " / ".join(seen)])
	var starters := 0
	for id: StringName in WeaponDefs.STARTERS:
		starters += 1
	TestLib.check(starters >= 6 and WeaponDefs.unlocked.size() >= 6, "the starters are owned from the first minute")


func _icons() -> void:
	ItemIcons.clear_cache()
	for id: StringName in WeaponDefs.IDS:
		TestLib.check(ItemIcons.weapon(id) != null, "picture of weapon %s" % id)
	for id: StringName in Gear.THROW_IDS:
		TestLib.check(ItemIcons.gear(id) != null, "picture of throwable %s" % id)
	for id: StringName in Gear.GADGET_IDS:
		TestLib.check(ItemIcons.gear(id) != null, "picture of gadget %s" % id)
	for id: StringName in VehicleSpecs.STREAM_KINDS:
		TestLib.check(ItemIcons.vehicle(id) != null, "picture of vehicle %s" % id)
	for id: StringName in EnemyTypes.TYPES:
		TestLib.check(ItemIcons.enemy(id) != null, "picture of enemy %s" % id)
	TestLib.check(ItemIcons.any(&"carbine") != null and ItemIcons.any(&"mine") != null and ItemIcons.any(&"sedan") != null and ItemIcons.any(&"brute") != null, "a picture is found by name alone (kill feed, pickups)")
	TestLib.check(ItemIcons.weapon(&"not_a_weapon") == null, "an unknown id has no picture and no crash")
	var t := ItemIcons.weapon(&"carbine")
	TestLib.check(t != null and t.get_width() <= 256 and t.get_height() <= 256, "pictures are small (%s)" % t.get_size())


func _numbers() -> void:
	for id: StringName in WeaponDefs.IDS:
		var c := WeaponStats.card(id)
		var bars: Dictionary = c["bars"]
		var ok := true
		for k: StringName in WeaponStats.BARS:
			ok = ok and float(bars[k]) >= 0.0 and float(bars[k]) <= 1.0
		TestLib.check(ok, "%s: every bar is 0..1" % id)
		TestLib.check(float(c["damage_shot"]) > 0.0 and float(c["range_eff"]) <= float(c["range_max"]) + 0.01 and float(c["rpm"]) > 0.0, "%s: sane numbers (dmg %.0f, range %.0f..%.0f, %.0f rpm)" % [id, c["damage_shot"], c["range_eff"], c["range_max"], c["rpm"]])
		TestLib.check(WeaponStats.lines(c).size() >= 3, "%s: the card has its text lines" % id)
	# class feel: a sniper outranges a pistol, a shotgun spreads wide and falls off, a launcher has a blast, a minigun fires faster than a revolver
	TestLib.check(float(WeaponStats.card(&"bolt")["range_eff"]) > 3.0 * float(WeaponStats.card(&"pistol")["range_eff"]), "the bolt rifle outranges the pistol")
	TestLib.check(float(WeaponStats.card(&"sawn")["spread_hip"]) > 4.0 * float(WeaponStats.card(&"battle")["spread_hip"]) and bool(WeaponStats.card(&"sawn")["falloff"]), "the sawn-off spreads wide and fades with range")
	TestLib.check(float(WeaponStats.card(&"rocket")["blast"]) >= 6.0 and float(WeaponStats.card(&"carbine")["blast"]) == 0.0, "launchers have a blast radius, rifles none")
	TestLib.check(float(WeaponStats.card(&"minigun")["rpm"]) > 3.0 * float(WeaponStats.card(&"revolver")["rpm"]), "the minigun fires much faster than the revolver")
	TestLib.check(WeaponStats.lock_on(&"rocket") and WeaponStats.lock_on(&"gravity") and not WeaponStats.lock_on(&"carbine"), "launchers lock on, rifles do not")
	# the damage fall-off by range (what PlayerWeapon applies) and the blast fall-off
	var near := WeaponStats.damage_at(&"pistol", 5.0)
	var mid := WeaponStats.damage_at(&"pistol", 80.0)
	var far := WeaponStats.damage_at(&"pistol", 120.0)
	TestLib.check(near == 22.0 and mid < near and far < mid and is_equal_approx(far, 22.0 * WeaponStats.FAR_DAMAGE), "pistol damage: full to 45 m, then down to a quarter at 120 m (%.1f %.1f %.1f)" % [near, mid, far])
	TestLib.check(WeaponStats.damage_at(&"bolt", 400.0) == 105.0, "a bolt rifle keeps full damage at range")
	TestLib.check(WeaponStats.blast_share(0.0, 7.0) == 1.0 and WeaponStats.blast_share(3.5, 7.0) < 1.0 and WeaponStats.blast_share(3.5, 7.0) > WeaponStats.blast_share(7.0, 7.0) and WeaponStats.blast_share(9.0, 7.0) == 0.0, "blast damage falls from the centre to the edge and is zero outside")
	# the crates of the map: six hold a weapon, each weapon of them is findable
	var held := 0
	for i in WeaponLadder.CRATES.size():
		if StringName(WeaponLadder.CRATES[i]["weapon"]) != &"":
			held += 1
	TestLib.check(held >= 6, "six or more weapon crates on the map (%d)" % held)
	for id: StringName in [&"marksman", &"breacher", &"rocket", &"battle", &"sawn", &"dmr"]:
		TestLib.check(WeaponStats.crates_of(id).size() == 1 and WeaponStats.where(id)[0].begins_with("CRATE"), "%s sits in a crate and the card says so" % id)


func _live() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg.bak"))
	WeaponDefs.reset_unlocked()
	Sfx.muted = true
	TestMode.reset_toggles()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	var huds := main.find_children("*", "Hud", true, false)
	var p := Game.player as Player
	if p == null or huds.is_empty():
		TestLib.check(false, "the game is up")
		return
	var hud := huds[0] as Hud
	var prog := Game.progress as Progress
	Game.state = &"play"
	TestMode.god = true
	# --- blast cover: a wall between the blast and the target takes most of it
	var wall := StaticBody3D.new()
	wall.collision_layer = Game.L_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(6.0, 6.0, 0.5)
	cs.shape = bs
	wall.add_child(cs)
	host.add_child(wall)
	wall.global_position = Vector3(500.0, 3.0, 500.0)
	await TestLib.frames(host, 3)
	var c0 := Vector3(500.0, 1.0, 497.0)
	TestLib.check(is_equal_approx(Game.blast_cover(c0, Vector3(500.0, 1.0, 495.0)), 1.0), "a blast with a clear line hurts in full")
	TestLib.check(is_equal_approx(Game.blast_cover(c0, Vector3(500.0, 1.0, 503.0)), Game.BLAST_COVER), "a target behind a wall takes %d %%" % int(Game.BLAST_COVER * 100.0))
	wall.queue_free()
	# --- the launcher aim indicator and lock, in the live game
	var w := p.weapon
	WeaponDefs.unlock(&"rocket")
	w.switch_to(&"rocket", true)
	await TestLib.frames(host, 6)
	var la: LaunchAim = w._launch
	TestLib.check(la != null and la.active and la.landing.is_finite(), "holding a launcher shows where it will land")
	TestLib.check(la != null and la._ring != null and la._ring.visible and la._dots.visible and is_equal_approx(la._ring.scale.x, float(WeaponDefs.def(&"rocket")["blast_radius"]) * 2.0), "the landing ring is as wide as the blast (%.1f m)" % float(WeaponDefs.def(&"rocket")["blast_radius"]))
	var mgr := Game.enemies as EnemyManager
	var fwd := -p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var foe := mgr.spawn(&"operative", p.global_position + fwd * 22.0, false)
	if foe != null:
		foe.set_physics_process(false)
		foe.global_position = p.global_position + fwd * 22.0
		p.camera_rig.aim_at(foe.global_position + Vector3(0.0, 1.0, 0.0))
		await TestLib.frames(host, 6)
		TestLib.check(la.target == foe and la._lock.visible, "the launcher locks on to the enemy under the crosshair")
		TestLib.check(la.landing.distance_to(foe.center()) < 0.5, "the landing point follows the locked target")
		w.switch_to(&"carbine", true)
		await TestLib.frames(host, 4)
		TestLib.check(not la.active and not la._ring.visible and la.target == null, "the indicator is gone with the carbine in hand")
		mgr.release(foe)
	else:
		TestLib.check(false, "an enemy could spawn")
	# --- damage numbers option
	var n0 := w.numbers_spawned
	Game.damage_numbers = true
	w._damage_number(p.global_position + Vector3(0, 1, -5), 20.0, false, false)
	var on_ok := w.numbers_spawned == n0 + 1
	Game.damage_numbers = false
	w._damage_number(p.global_position + Vector3(0, 1, -5), 20.0, false, false)
	TestLib.check(on_ok and w.numbers_spawned == n0 + 1, "damage numbers follow the option")
	Game.damage_numbers = true
	TestLib.check(OptionsScreen.TOGGLES.has(&"opt_dmg") and UiSettings.new("user://wc_test.cfg").dmg_numbers, "DAMAGE NUMBERS is an option, on by default")
	# --- the WEAPONS catalogue in the HUD (wave 114: the Arsenal, a scrolling grid of picture tiles; the layout is judged at a real phone screen)
	var win := host.get_window()
	var win_old := win.size
	win.size = Vector2i(1280, 720)
	await TestLib.frames(host, 3)
	WeaponDefs.reset_unlocked()
	prog.credits = 100000
	Game.state = &"paused"
	TestLib.check(hud.press_button(&"shop") and hud.press_button(&"hero_tab_weapons") and ShopScreen.weapon_page == 1, "the HERO hub opens on the WEAPONS tab")
	await TestLib.frames(host, 3)
	var vp := host.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var all_ids := {}
	var rows_view := int(floor((Arsenal.BOTTOM - Arsenal.LIST_Y + Arsenal.TILE_GAP) / Arsenal.ROW))
	var ring := Arsenal.class_ring(&"catalogue")
	for ci in ring.size():
		var cls: StringName = ring[ci]
		Arsenal.st(&"catalogue")["cls"] = cls
		Arsenal.st(&"catalogue")["filter"] = &"all"
		Arsenal.st(&"catalogue")["scroll"] = 0.0
		Arsenal._list_cache_key = ""
		var listed := Arsenal.list(&"catalogue")
		TestLib.check(cls == &"" or listed.size() >= 3, "class %s lists %d items" % [cls, listed.size()])
		var seen_here := {}
		var guard := 0
		while guard < 60:
			guard += 1
			hud._layout_key = ""
			hud._ensure_layout()
			var rects: Array[Rect2] = []
			for b: Dictionary in hud.buttons:
				var r: Rect2 = b["rect"]
				var id := String(b["id"])
				TestLib.check(minf(r.size.x, r.size.y) / s >= 63.9, "%s view %d: %s is 64 px or more (%.0fx%.0f)" % [cls, guard, id, r.size.x / s, r.size.y / s])
				TestLib.check(Rect2(Vector2.ZERO, vp).grow(1.0).encloses(r), "%s view %d: %s is on screen" % [cls, guard, id])
				for o in rects:
					TestLib.check(not o.grow(-1.0).intersects(r.grow(-1.0)), "%s view %d: %s overlaps another button" % [cls, guard, id])
				rects.append(r)
				if id.begins_with("wsel_"):
					all_ids[StringName(id.substr(5))] = true
					seen_here[StringName(id.substr(5))] = true
					TestLib.check(b.has("tile") and WeaponPics.has(b["tile"]) or WeaponsScreen.is_gear(b["tile"]), "tile %s carries its picture" % id)
			if float(Arsenal.st(&"catalogue")["scroll"]) >= Arsenal.max_scroll(&"catalogue") - 0.5:
				break
			Arsenal.scroll_by(&"catalogue", Arsenal.ROW * float(maxi(rows_view - 1, 1)))
		TestLib.check(seen_here.size() == listed.size(), "class %s: every one of its %d items shows on some view of the list (%d)" % [cls, listed.size(), seen_here.size()])
	for id: StringName in WeaponDefs.IDS:
		TestLib.check(all_ids.has(id), "the catalogue lists %s" % id)
	for id: StringName in Gear.THROW_IDS + Gear.CHARGE_IDS + Gear.GADGET_IDS:
		TestLib.check(all_ids.has(id), "the catalogue lists the %s" % id)
	# select, buy, equip (the marksman is a RIFLE)
	Arsenal.st(&"catalogue")["cls"] = &""
	Arsenal._list_cache_key = ""
	WeaponsScreen.sel = &""
	hud._layout_key = ""
	hud._ensure_layout()
	var target: StringName = &"marksman"
	Arsenal.select(hud, &"catalogue", &"a_pillar")
	hud._layout_key = ""
	hud._ensure_layout()
	var in_view := false
	Arsenal.select(hud, &"catalogue", target)
	hud._layout_key = ""
	hud._ensure_layout()
	for b: Dictionary in hud.buttons:
		in_view = in_view or b["id"] == StringName("wsel_%s" % target)
	TestLib.check(in_view and hud.press_button(StringName("wsel_%s" % target)) and WeaponsScreen.sel == target, "tapping a tile selects the weapon")
	hud._ensure_layout()
	var has_buy := false
	var buy_rect := Rect2()
	for b: Dictionary in hud.buttons:
		if b["id"] == StringName("buy_%s" % target):
			has_buy = true
			buy_rect = b["rect"]
	TestLib.check(has_buy, "an unowned weapon shows its BUY button")
	var before := prog.credits
	var price := prog.weapon_price(target)
	TestLib.check(hud.tap(buy_rect.get_center()) and WeaponDefs.is_unlocked(target) and prog.credits == before - price, "a tap on BUY buys it for %d" % price)
	hud._ensure_layout()
	var has_equip := false
	for b: Dictionary in hud.buttons:
		has_equip = has_equip or b["id"] == StringName("wequip_%s" % target)
	TestLib.check(has_equip, "an owned weapon shows EQUIP")
	TestLib.check(hud.press_button(StringName("wequip_%s" % target)) and p.weapon.current == target and WeaponDefs.last_used == target, "EQUIP puts it in the hero's hand")
	# the class chips flip through the classes and wrap
	Arsenal.st(&"catalogue")["cls"] = &""
	var c_first := Arsenal.next_class(&"catalogue", 1)
	TestLib.check(hud.press_button(&"ars_cls_next") and Arsenal.st(&"catalogue")["cls"] == c_first and c_first != &"" and hud.press_button(&"ars_cls_prev") and Arsenal.st(&"catalogue")["cls"] == &"", "the class chips flip to the next class and back")
	hud.press_button(&"ars_cls_prev")
	TestLib.check(Arsenal.st(&"catalogue")["cls"] == ring[ring.size() - 1], "the class chips wrap around the ring")
	Arsenal.st(&"catalogue")["cls"] = &""
	# a gear item: select the mine, buy it from its card
	WeaponsScreen.select(&"mine")
	hud._layout_key = ""
	hud._ensure_layout()
	var gear_btn := false
	for b: Dictionary in hud.buttons:
		gear_btn = gear_btn or b["id"] == &"wgear_mine"
	TestLib.check(gear_btn and hud.press_button(&"wgear_mine") and Gear.is_owned(&"mine"), "a throwable is bought from its card")
	await TestLib.frames(host, 3)                                    # the real draw of the card
	# the loadout shows the card of the selected weapon itself (the picture, the seven bars, where to get it): it needs no INFO button any more
	hud.press_button(&"shop_back")
	hud._shop_open = false
	Game.state = &"paused"
	TestLib.check(hud.press_button(&"loadout"), "the loadout opens")
	hud._loadout_w = &"scatter"
	hud._layout_key = ""
	hud._ensure_layout()
	hud.scan_log.clear()
	hud.scan_text = true
	hud._screen.queue_redraw()
	for i in 90:
		await TestLib.frames(host, 1)
		if not hud.scan_log.is_empty():
			break
	await TestLib.frames(host, 1)
	hud.scan_text = false
	var words: Array[String] = []
	for e: Dictionary in hud.scan_log:
		words.append(String(e["text"]))
	var joined := "|".join(words)
	var miss: Array[String] = []
	for key: StringName in WeaponStats.BARS7:
		if not joined.contains(String(WeaponStats.BAR_NAMES[key])):
			miss.append(String(key))
	TestLib.check(joined.contains(WeaponDefs.title(&"scatter")) and miss.is_empty(), "the loadout card names the weapon and draws its seven bars (missing: %s)" % str(miss))
	win.size = win_old
	await TestLib.frames(host, 3)
	# the full map labels the crates (weapon crates with the weapon, the others AMMO)
	var labels := {}
	var fr := Freedom.current
	if fr != null and fr.crates != null:
		for i in int(fr.crates.call(&"count")):
			var cw := StringName(WeaponLadder.CRATES[i]["weapon"])
			labels[cw] = true
	TestLib.check(labels.has(&"battle") and labels.has(&"sawn") and labels.has(&"dmr") and labels.has(&""), "the map crates carry weapons and ammo")
	hud.press_button(&"shop_back")
	Game.state = &"play"
	TestMode.god = false
	WeaponDefs.reset_unlocked()
