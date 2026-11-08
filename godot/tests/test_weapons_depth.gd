extends RefCounted
## Weapons depth (wave 61): six more weapons (Plasma Minigun, Twin Pistols, Arc Caster, Spike Revolver, Arc Whip, Quantum Blade) in the composed game: data (alt-fire, hit sound,
## icon, price, synthesised sounds), spin-up and overheat, akimbo alternation, arc chain, revolver fan, the 3-step melee combo with PULL and LUNGE, shop entries, the paged weapon wheel on
## the pause screen (touch targets >= 64 px, every owned weapon reachable) and the TEST / DEMO menu entries. State-based waits only (no frame-count assumptions).
## Run: tools/test.sh tests/test_weapons_depth.gd

const DT := 1.0 / 60.0
const NEW: Array[StringName] = [&"minigun", &"akimbo", &"arc", &"revolver", &"whip", &"blade"]

var host: Node
var w: PlayerWeapon
var p: Player


func _wipe_user_state() -> void:
	for f: String in [Progress.DEFAULT_PATH, "user://map.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	WeaponDefs.reset_unlocked()
	Attachments.reset()
	LoadoutScreen.reset_page()
	LoadoutScreen.page = 0
	ShopScreen.weapon_page = 0


## An idle tick of `sec` seconds (nothing pressed).
func _idle(sec: float) -> void:
	var t := 0.0
	while t < sec:
		w.tick(DT, false, false, false, false)
		t += DT


## A fresh target `dist` m in front of the player on the camera line, frozen, hard to kill.
func _target(dist: float, side := 0.0) -> Drone:
	var fwd := -p.camera_rig.camera.global_basis.z
	var right := p.camera_rig.camera.global_basis.x
	var at := p.camera_rig.camera.global_position + fwd * dist + right * side
	var d := (Game.enemies as EnemyManager).spawn(&"heavy", at, true)
	TestLib.check(d != null, "an enemy could be spawned")
	d.global_position = at - Vector3(0.0, d.center_y, 0.0)
	d.max_hp = 100000.0
	d.hp = d.max_hp
	return d


func _clear_enemies() -> void:
	(Game.enemies as EnemyManager).clear()


func _flat_fwd() -> Vector3:
	var f := -p.camera_rig.camera.global_basis.z
	f.y = 0.0
	return f.normalized()


func run(hst: Node) -> void:
	host = hst
	seed(61)
	Sfx.muted = true
	TestMode.reset_toggles()
	_wipe_user_state()

	# --- data -------------------------------------------------------------------------------------------------------------
	TestLib.check(WeaponDefs.IDS.size() >= 14, "14 or more weapon classes (%d)" % WeaponDefs.IDS.size())
	var kinds := {}
	for id: StringName in NEW:
		var d := WeaponDefs.def(id)
		TestLib.check(WeaponDefs.DEFS.has(id) and d.has("pattern") and d.has("tracer") and int(d["mag"]) > 0, "%s has a full definition" % id)
		TestLib.check(WeaponDefs.ALTS.has(id) and WeaponDefs.HIT_SND.has(id) and WeaponDefs.TILT.has(id), "%s has alt-fire, hit sound and tilt" % id)
		TestLib.check((Economy.weapon_price(id) > 0 and WeaponDefs.price(id) > 0) or WeaponDefs.STARTERS.has(id), "%s is priced through Economy (or a free starter)" % id)
		TestLib.check(WeaponIcons.has_icon(id), "%s has a HUD icon" % id)
		TestLib.check(ShopScreen.SHOP_WEAPONS.has(id) or WeaponDefs.STARTERS.has(id), "%s is in the shop (or a free starter)" % id)
		TestLib.check(Attachments.effective(id).has("damage"), "attachments apply to %s" % id)
		var snd := StringName(d.get("snd", &"shot"))
		TestLib.check(ResourceLoader.exists("res://assets/audio/%s.wav" % snd), "%s: synthesised sound %s exists" % [id, snd])
		kinds[String(d["kind"])] = true
	TestLib.check(ResourceLoader.exists("res://assets/audio/overheat.wav"), "overheat sound exists")
	for id: StringName in WeaponDefs.IDS:
		TestLib.check(WeaponIcons.has_icon(id), "every weapon has an icon (%s)" % id)
	TestLib.check(kinds.has("melee") and kinds.has("hit"), "melee and hitscan classes")

	# --- the composed game ---------------------------------------------------------------------------------------------------
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	Game.state = &"play"
	p = Game.player as Player
	w = p.weapon
	TestMode.god = true
	TestMode.freeze = true
	TestMode.infinite_ammo = true
	await TestLib.frames(host, 5)
	TestLib.check(p != null and w != null and Game.enemies is EnemyManager, "the game is up")
	for id: StringName in NEW:
		TestMode.give_weapon(id)
		TestLib.check(WeaponDefs.is_unlocked(id) and w.current == id, "TEST MENU gives %s" % id)
	TestMode.give_all_weapons()
	for id: StringName in WeaponDefs.IDS:
		TestLib.check(WeaponDefs.is_unlocked(id), "%s unlocked" % id)
	_idle(2.0)

	# --- plasma minigun: spin-up and overheat ------------------------------------------------------------------------------------
	w.switch_to(&"minigun", true)
	_idle(1.0)
	var s0 := w.shots_fired
	w.tick(DT, true, false, false, false)
	TestLib.check(w.shots_fired == s0 and w.spin > 0.0 and w.spin < 0.2, "minigun does not fire on the first tick (spin %.2f)" % w.spin)
	var slow := w._spin_mult()
	var guard := 0
	while w.spin < 1.0 and guard < 600:
		w.tick(DT, true, false, false, false)
		guard += 1
	TestLib.check(w.spin >= 0.999 and w.shots_fired > s0, "minigun spins up and starts firing")
	TestLib.check(w._spin_mult() < slow and is_equal_approx(w._spin_mult(), 1.0), "the fire rate follows the spin")
	var t1 := w.shots_fired
	var secs := 0.0
	while secs < 0.5 and not w.overheated:
		w.tick(DT, true, false, false, false)
		secs += DT
	TestLib.check(float(w.shots_fired - t1) >= 7.0 or w.overheated, "minigun fires at least 14 rounds per second at full spin (%d in %.2f s)" % [w.shots_fired - t1, secs])
	guard = 0
	while not w.overheated and guard < 900:
		w.tick(DT, true, false, false, false)
		guard += 1
	TestLib.check(w.overheated and w.overheats >= 1 and w.heat >= 0.99, "sustained fire overheats the minigun")
	var locked := w.shots_fired
	for _i in 30:
		w.tick(DT, true, false, false, false)
	TestLib.check(w.shots_fired == locked, "no rounds while overheated")
	_idle(1.0)
	w.fire_t = 0.0
	TestLib.check(w.alt_fire(false) and w.heat == 0.0 and not w.overheated, "VENT clears the heat at once")
	w.heat = 0.8
	_idle(0.1)
	var heat0 := w.heat
	_idle(1.0)
	TestLib.check(w.heat < heat0, "heat cools down when the trigger is released")
	w.overheated = true
	w._lock_t = float(WeaponDefs.def(&"minigun")["heat_lock"])
	_idle(float(WeaponDefs.def(&"minigun")["heat_lock"]) + 0.3)
	TestLib.check(not w.overheated, "the lock ends by itself")

	# --- twin pistols: hands alternate -------------------------------------------------------------------------------------------
	w.switch_to(&"akimbo", true)
	_idle(0.5)
	var side0 := w._side
	w.tick(DT, true, false, false, false)
	TestLib.check(w._side == -side0, "akimbo: the other hand fires next")
	_idle(0.3)
	w.tick(DT, true, false, false, false)
	TestLib.check(w._side == side0, "akimbo: and back")
	TestLib.check(is_equal_approx(WeaponDefs.pattern_at(&"akimbo", 0).x, -WeaponDefs.pattern_at(&"akimbo", 1).x), "akimbo recoil alternates left and right")
	_idle(1.5)
	var s1 := w.shots_fired
	var a1 := w.alt_fired
	TestLib.check(w.alt_fire(false) and w.alt_fired == a1 + 1, "akimbo FAN starts")
	_idle(1.5)
	TestLib.check(w.shots_fired - s1 == 8, "akimbo FAN fires 8 rounds (%d)" % (w.shots_fired - s1))

	# --- arc caster: the hit chains ----------------------------------------------------------------------------------------------------
	_clear_enemies()
	w.switch_to(&"arc", true)
	_idle(1.0)
	var t_a := _target(14.0)
	var t_b := _target(14.0, 4.0)
	var t_c := _target(14.0, -4.5)
	var far := _target(14.0, 40.0)
	var ch0 := w.chain_hits
	var hp_a := t_a.hp
	var tries := 0
	while t_a.hp >= hp_a and tries < 8:
		_idle(0.5)
		w.tick(DT, true, false, true, false)
		tries += 1
	TestLib.check(t_a.hp < hp_a, "arc caster hits the aimed target")
	TestLib.check(w.chain_hits > ch0 and (t_b.hp < t_b.max_hp or t_c.hp < t_c.max_hp), "the arc chains to a neighbour (%d jumps)" % (w.chain_hits - ch0))
	TestLib.check(is_equal_approx(far.hp, far.max_hp), "an enemy out of chain range is untouched")
	_idle(1.0)
	var overload_hp := t_a.hp
	_idle(0.5)
	TestLib.check(w.alt_fire(true), "arc OVERLOAD fires")
	TestLib.check(t_a.hp < overload_hp, "OVERLOAD hits")

	# --- spike revolver ------------------------------------------------------------------------------------------------------------------
	_clear_enemies()
	w.switch_to(&"revolver", true)
	_idle(1.0)
	var rv := _target(12.0)
	var rhp := rv.hp
	tries = 0
	while rv.hp >= rhp and tries < 8:
		_idle(0.7)
		w.tick(DT, true, false, true, false)
		tries += 1
	TestLib.check(rhp - rv.hp >= 30.0, "revolver rounds hit hard (%.0f)" % (rhp - rv.hp))
	_idle(1.0)
	var rs := w.shots_fired
	TestLib.check(w.alt_fire(false), "FAN HAMMER starts")
	_idle(1.5)
	TestLib.check(w.shots_fired - rs >= 5, "FAN HAMMER empties the cylinder (%d)" % (w.shots_fired - rs))

	# --- arc whip and quantum blade: melee combo, PULL, LUNGE ---------------------------------------------------------------------------------
	for id: StringName in [&"whip", &"blade"]:
		_clear_enemies()
		w.switch_to(id, true)
		_idle(1.5)
		TestLib.check(w.combo == 0 and w.ammo == w.mag, "%s starts at combo step 0 with no ammo cost" % id)
		var reach := float(WeaponDefs.def(id)["reach"])
		var tgt := _target(2.2)
		tgt.global_position = p.global_position + _flat_fwd() * 2.2
		var hp0 := tgt.hp
		var drops: Array[float] = []
		var f0 := w.finishers
		for step in 3:
			var before := tgt.hp
			tgt.global_position = p.global_position + _flat_fwd() * 2.2
			var swings := w.combo_hits
			w.fire_t = 0.0
			w.tick(DT, true, false, false, false)
			TestLib.check(w.combo_hits == swings + 1, "%s swing %d lands in the combo" % [id, step + 1])
			drops.append(before - tgt.hp)
			_idle(float(WeaponDefs.def(id)["interval"]) * 2.0)
		TestLib.check(drops[0] > 0.0 and drops[1] > 0.0, "%s: swings 1 and 2 hit (%.0f, %.0f)" % [id, drops[0], drops[1]])
		TestLib.check(drops[2] > drops[0] * 1.5 and w.finishers == f0 + 1, "%s: the third swing is a bigger finisher (%.0f vs %.0f)" % [id, drops[2], drops[0]])
		TestLib.check(w.combo == 0, "%s: the combo wraps" % id)
		TestLib.check(w.ammo == w.mag, "%s never uses ammo" % id)
		tgt.global_position = p.global_position + _flat_fwd() * (reach + 6.0)
		var hp1 := tgt.hp
		w.fire_t = 0.0
		w.tick(DT, true, false, false, false)
		TestLib.check(is_equal_approx(tgt.hp, hp1), "%s misses a target beyond its reach" % id)
		w.tick(DT, false, false, false, false)
		_idle(float(WeaponDefs.def(id)["combo_window"]) + 0.5)
		TestLib.check(w.combo == 0, "%s: the combo resets after the window" % id)
		TestLib.check(hp0 > tgt.hp, "%s damaged the dummy overall" % id)

	_clear_enemies()
	w.switch_to(&"whip", true)
	_idle(1.5)
	var pulled := _target(8.0)
	pulled.global_position = p.global_position + _flat_fwd() * 8.0
	var d_before := pulled.global_position.distance_to(p.global_position)
	TestLib.check(w.alt_fire(false), "whip PULL fires")
	var d_after := Vector2(pulled.global_position.x - p.global_position.x, pulled.global_position.z - p.global_position.z).length()
	TestLib.check(d_after < d_before - 3.0, "whip PULL yanks the enemy in (%.1f -> %.1f m)" % [d_before, d_after])
	_idle(2.0)
	_clear_enemies()
	var empty_ok := not w.alt_fire(false)
	TestLib.check(empty_ok, "PULL with nothing in front does nothing")

	w.switch_to(&"blade", true)
	_idle(2.0)
	var lt := _target(4.0)
	lt.global_position = p.global_position + _flat_fwd() * 4.0
	var p0 := p.global_position
	var lhp := lt.hp
	var lunged := w.alt_fire(false)
	TestLib.check(lunged, "blade LUNGE fires")
	TestLib.check(p.global_position.distance_to(p0) > 0.5, "LUNGE moves the hero (%.1f m)" % p.global_position.distance_to(p0))
	TestLib.check(lhp - lt.hp >= float(WeaponDefs.def(&"blade")["damage"]) * 1.5, "LUNGE strikes for a multiple (%.0f)" % (lhp - lt.hp))
	_clear_enemies()

	# --- shop paging and purchase -------------------------------------------------------------------------------------------------------
	var hud := host.get_tree().root.find_child("Hud", true, false) as Hud
	TestLib.check(hud != null, "the HUD exists")
	var prog := Game.progress as Progress
	TestMode.infinite_ammo = false
	prog.credits = 100000
	WeaponDefs.reset_unlocked()
	Game.state = &"paused"
	TestLib.check(hud.press_button(&"shop"), "the shop opens")
	var seen := {}
	for _pg in ShopScreen.pages():
		hud._ensure_layout()
		var sels: Array[StringName] = [&""]
		if ShopScreen.weapon_page > 0:                                  # the catalogue shows the BUY button of the selected weapon: select each tile in turn
			sels.clear()
			for it in WeaponsScreen.page_items(ShopScreen.weapon_page - 1):
				sels.append(it["id"])
		for sel_id in sels:
			if sel_id != &"":
				WeaponsScreen.sel = sel_id
				hud._layout_key = ""
				hud._ensure_layout()
			for b: Dictionary in hud.buttons:
				var sid := String(b["id"])
				if sid.begins_with("buy_") and WeaponDefs.DEFS.has(StringName(sid.substr(4))):
					seen[StringName(sid.substr(4))] = true
					TestLib.check((b["rect"] as Rect2).size.y >= 40.0 * UiUtil.ui_scale(host.get_viewport().get_visible_rect().size) - 0.5, "shop button %s is tall enough" % sid)
		TestLib.check(hud.press_button(&"shop_wpage"), "the shop page flips")
	for id: StringName in ShopScreen.SHOP_WEAPONS:
		TestLib.check(seen.has(id), "the shop offers %s on some page" % id)
	for id: StringName in NEW:
		if WeaponDefs.STARTERS.has(id):
			continue                                       # a free starter: nothing to buy
		var price := prog.weapon_price(id)
		var before := prog.credits
		TestLib.check(hud.press_button(StringName("buy_%s" % id)) or ShopScreen.page_weapons().has(id) == false, "buy %s (or on the other page)" % id)
		if not WeaponDefs.is_unlocked(id):
			hud.press_button(&"shop_wpage")
			TestLib.check(hud.press_button(StringName("buy_%s" % id)), "buy %s on its page" % id)
		TestLib.check(WeaponDefs.is_unlocked(id) and prog.credits == before - price, "%s bought for its Economy price %d" % [id, price])
	hud.press_button(&"shop_back")

	# --- the paged weapon wheel ---------------------------------------------------------------------------------------------------------------
	TestMode.give_all_weapons()
	Game.state = &"play"
	await TestLib.frames(host, 3)
	hud.open_wheel()
	TestLib.check(Game.state == &"paused" and hud.loadout_open(), "the wheel opens (pause through Game.state)")
	hud._ensure_layout()
	var pages := LoadoutScreen.page_count()
	TestLib.check(pages == WeaponDefs.CLASS_ORDER.size(), "the loadout has one tab per weapon class (%d)" % pages)
	var reached := {}
	for pg in pages:
		hud._ensure_layout()
		var n_on_page := 0
		for b: Dictionary in hud.buttons:
			var sid := String(b["id"])
			var r: Rect2 = b["rect"]
			var sc := UiUtil.ui_scale(host.get_viewport().get_visible_rect().size)
			if sid.begins_with("wheel_") or sid.begins_with("wheelpg_"):
				TestLib.check(r.size.y >= 64.0 * sc - 0.5 and r.size.x >= 64.0 * sc - 0.5, "wheel button %s is at least 64 px (%.0f x %.0f)" % [sid, r.size.x, r.size.y])
			if sid.begins_with("wheel_"):
				reached[StringName(sid.substr(6))] = true
				n_on_page += 1
		TestLib.check(n_on_page <= WeaponDefs.PAGE_SIZE and n_on_page > 0, "page %d shows 1..%d weapons (%d)" % [pg, WeaponDefs.PAGE_SIZE, n_on_page])
		# no two wheel buttons overlap
		var rects: Array[Rect2] = []
		for b: Dictionary in hud.buttons:
			if String(b["id"]).begins_with("wheel"):
				rects.append(b["rect"])
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				TestLib.check(not rects[i].grow(-1.0).intersects(rects[j].grow(-1.0)), "wheel buttons do not overlap on page %d" % pg)
		TestLib.check(hud.press_button(&"wheelpg_next"), "the wheel flips to the next page")
	for id: StringName in WeaponDefs.IDS:
		TestLib.check(reached.has(id), "%s is reachable on the wheel" % id)
	# pick a weapon from the far page: it swaps and resumes the game
	LoadoutScreen.page = pages - 1
	hud._layout_key = ""
	hud._ensure_layout()
	var pick: StringName = LoadoutScreen.page_items(WeaponDefs.last_used)[0] if false else &"blade"
	LoadoutScreen.page = LoadoutScreen.owned_classes().find(WeaponDefs.class_of(pick))
	hud._layout_key = ""
	hud._ensure_layout()
	var ids: Array[String] = []
	for b: Dictionary in hud.buttons:
		ids.append(String(b["id"]))
	TestLib.check(ids.has("wheel_blade"), "the blade button is on its page")
	TestLib.check(hud.press_button(&"wheel_blade") and w.current == &"blade" and Game.state == &"play", "picking from the wheel swaps and resumes")
	# the keyboard / SWAP cycle visits all of them
	var visited := {}
	for _i in WeaponDefs.IDS.size() + 1:
		visited[w.current] = true
		w.cycle(1)
		w.swap_t = 0.0
	TestLib.check(visited.size() == WeaponDefs.IDS.size(), "cycling visits all %d weapons (%d)" % [WeaponDefs.IDS.size(), visited.size()])

	# --- TEST and DEMO menu entries --------------------------------------------------------------------------------------------------------------------
	var labels: Array[String] = []
	for e in DemoMenu.entries():
		labels.append(String(e["label"]))
	for id: StringName in NEW:
		TestLib.check(labels.has(WeaponDefs.title(id)), "DEMO menu lists %s" % id)
	var menu: TestMenu = host.get_tree().get_first_node_in_group(&"test_menu") as TestMenu
	TestLib.check(menu != null, "the TEST MENU exists")
	menu.set_page(TestMenu.TABS.find("LOOT"))
	menu.layout()
	var loot := menu.labels()
	for id: StringName in NEW:
		TestLib.check(loot.has(WeaponDefs.title(id)), "TEST MENU LOOT lists %s" % id)

	# --- save round trip of the extended set ----------------------------------------------------------------------------------------------------------------
	var names: Array = []
	for id: StringName in NEW:
		names.append(String(id))
	WeaponDefs.reset_unlocked()
	WeaponDefs.set_unlocked(names)
	for id: StringName in NEW:
		TestLib.check(WeaponDefs.is_unlocked(id), "%s survives set_unlocked" % id)

	TestMode.reset_toggles()
	Game.state = &"play"
	_wipe_user_state()
	main.queue_free()
	await TestLib.frames(host, 2)
