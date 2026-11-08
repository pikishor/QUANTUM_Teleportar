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
	TestLib.check(WeaponDefs.IDS.size() >= 26, "twenty-six or more weapons (%d)" % WeaponDefs.IDS.size())
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		var n := WeaponDefs.in_class(cls).size()
		TestLib.check(n >= 3 and n <= 4, "class %s has three or four variants (%d)" % [cls, n])
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
	TestLib.check(held == 6, "six weapon crates on the map")
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
	# --- the WEAPONS catalogue in the HUD
	WeaponDefs.reset_unlocked()
	prog.credits = 100000
	Game.state = &"paused"
	TestLib.check(hud.press_button(&"shop") and hud.press_button(&"hero_tab_weapons") and ShopScreen.weapon_page == 1, "the HERO hub opens on the WEAPONS tab")
	await TestLib.frames(host, 3)
	var vp := host.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var all_ids := {}
	for pg in WeaponsScreen.PAGES:
		ShopScreen.weapon_page = 1 + pg
		hud._layout_key = ""
		hud._ensure_layout()
		var items := WeaponsScreen.page_items(pg)
		TestLib.check(items.size() >= 3 and items.size() <= 12, "page %d lists %d tiles" % [pg + 1, items.size()])
		var rects: Array[Rect2] = []
		var tiles := 0
		for b: Dictionary in hud.buttons:
			var r: Rect2 = b["rect"]
			var id := String(b["id"])
			TestLib.check(minf(r.size.x, r.size.y) / s >= 63.9, "page %d: %s is 64 px or more (%.0fx%.0f)" % [pg + 1, id, r.size.x / s, r.size.y / s])
			TestLib.check(Rect2(Vector2.ZERO, vp).grow(1.0).encloses(r), "page %d: %s is on screen" % [pg + 1, id])
			for o in rects:
				TestLib.check(not o.grow(-1.0).intersects(r.grow(-1.0)), "page %d: %s overlaps another button" % [pg + 1, id])
			rects.append(r)
			if id.begins_with("wsel_"):
				tiles += 1
				all_ids[StringName(id.substr(5))] = true
				TestLib.check(b.has("pic"), "tile %s carries its picture" % id)
		TestLib.check(tiles == items.size(), "page %d: a tile per item" % [pg + 1])
	for id: StringName in WeaponDefs.IDS:
		TestLib.check(all_ids.has(id), "the catalogue lists %s" % id)
	for id: StringName in Gear.THROW_IDS + Gear.GADGET_IDS:
		TestLib.check(all_ids.has(id), "the catalogue lists the %s" % id)
	# select, buy, equip
	ShopScreen.weapon_page = 1
	WeaponsScreen.sel = &""
	hud._layout_key = ""
	hud._ensure_layout()
	var target: StringName = &"marksman"
	TestLib.check(hud.press_button(StringName("wsel_%s" % target)) and WeaponsScreen.sel == target, "tapping a tile selects the weapon")
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
	TestLib.check(hud.press_button(&"wpg_next") and ShopScreen.weapon_page == 2 and hud.press_button(&"wpg_prev") and ShopScreen.weapon_page == 1, "the page buttons flip")
	hud.press_button(&"wpg_prev")
	TestLib.check(ShopScreen.weapon_page == 3, "the pages wrap")
	# a gear item: select the mine, buy it from its card
	WeaponsScreen.select(&"mine")
	hud._layout_key = ""
	hud._ensure_layout()
	var gear_btn := false
	for b: Dictionary in hud.buttons:
		gear_btn = gear_btn or b["id"] == &"wgear_mine"
	TestLib.check(gear_btn and hud.press_button(&"wgear_mine") and Gear.is_owned(&"mine"), "a throwable is bought from its card")
	await TestLib.frames(host, 3)                                    # the real draw of the card
	# the loadout INFO button opens the card of the weapon in the loadout
	hud.press_button(&"shop_back")
	hud._shop_open = false
	Game.state = &"paused"
	TestLib.check(hud.press_button(&"loadout"), "the loadout opens")
	hud._loadout_w = &"scatter"
	hud._layout_key = ""
	hud._ensure_layout()
	var info := false
	for b: Dictionary in hud.buttons:
		info = info or b["id"] == &"loadout_info"
	TestLib.check(info and hud.press_button(&"loadout_info") and hud._shop_open and not hud._loadout_open and WeaponsScreen.sel == &"scatter" and ShopScreen.weapon_page == 1 + WeaponsScreen.page_of(&"scatter"), "INFO shows the card of the loadout weapon")
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
