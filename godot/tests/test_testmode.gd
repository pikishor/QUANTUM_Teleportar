extends RefCounted
## HACK / TEST MODE tests (headless, the composed game): the toggles' effects, every picker action (weapons, ammo, credits, upgrades, chapters, contracts, the boss,
## enemies, vehicles, teleports, weather, heat, kill all, skip), and the menu itself (open / close pauses and resumes, pointer taps on the drawn rectangles, the 1-4 quick buttons).
## Run: tools/test.sh tests/test_testmode.gd

const Fixture := preload("res://tests/player_fixture.gd")

var host: Node
var main: Node
var p: Player
var menu: TestMenu


## Opens (or closes) the MORE page of the title / pause screen: the TEST button is one of its cells.
func _more(on: bool) -> void:
	var h := main.find_children("*", "Hud", true, false)[0] as Hud
	h._gear_open = on
	h._layout_key = ""
	h._ensure_layout()


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	menu = get_menu()
	TestLib.check(TestMode.available(), "test mode is available in a debug / editor run")
	TestLib.check(menu != null, "main.tscn composes the TestMenu (group test_menu)")
	Game.state = &"play"
	p.max_hp = 100.0
	await frames(10)
	await _toggles()
	await _weapons_and_loot()
	await _spawns()
	await _teleports()
	await _mission()
	_world_and_heat()
	await _menu_input()
	TestMode.reset_toggles()
	main.queue_free()
	await frames(5)
	Game.state = &"menu"
	Sfx.muted = false


func get_menu() -> TestMenu:
	return host.get_tree().get_first_node_in_group(&"test_menu") as TestMenu


func _toggles() -> void:
	p.invuln = 0.0
	p.hp = p.max_hp
	TestMode.toggle(&"god")
	p.damage(40.0)
	TestLib.check(p.hp == p.max_hp and TestMode.is_on(&"god"), "god mode: damage does nothing")
	TestMode.toggle(&"god")
	p.damage(10.0)
	TestLib.check(p.hp < p.max_hp, "god mode off: damage works again")
	p.hp = p.max_hp

	TestMode.toggle(&"ammo")
	p.weapon.ammo = 2
	await frames(3)
	TestLib.check(p.weapon.ammo == p.weapon.mag, "infinite ammo refills the magazine every tick")
	TestMode.toggle(&"ammo")

	TestMode.toggle(&"noheat")
	Game.heat = 3.0
	TestLib.check(Game.heat == 0.0, "no heat: the heat stays at 0")
	TestMode.toggle(&"noheat")
	Game.heat = 2.0
	TestLib.check(Game.heat == 2.0, "no heat off: heat works again")
	Game.heat = 0.0

	var mgr := Game.enemies as EnemyManager
	mgr.clear()
	var d := mgr.spawn(&"heavy", p.global_position + Vector3(12.0, 0.0, 0.0), true)
	TestLib.check(d != null, "a heavy drone spawns for the one-hit test")
	TestMode.toggle(&"onehit")
	p.weapon._hit_target(d, d.center(), Vector3.UP)
	TestLib.check(d.dead, "one-hit kills: one rifle hit kills a 230 hp heavy")
	TestMode.toggle(&"onehit")

	mgr.clear()
	var f := mgr.spawn(&"sentinel", p.global_position + Vector3(14.0, 0.0, 0.0), true)
	TestMode.toggle(&"freeze")
	var at := f.global_position
	await frames(30)
	TestLib.check(f.global_position.distance_to(at) < 0.01, "freeze enemies: an aware sentinel does not move")
	TestMode.toggle(&"freeze")
	mgr.clear()
	TestLib.check(not TestMode.toggle(&"nonsense"), "an unknown toggle id is refused")


func _weapons_and_loot() -> void:
	WeaponDefs.reset_unlocked()
	for id: StringName in WeaponDefs.IDS:
		TestMode.give_weapon(id)
		TestLib.check(WeaponDefs.is_unlocked(id) and p.weapon.current == id and p.weapon.ammo == p.weapon.mag, "give %s: owned, in hand, magazine full" % id)
	WeaponDefs.reset_unlocked()
	p.weapon.reset()
	TestMode.give_all_weapons()
	var all_owned := true
	for id: StringName in WeaponDefs.IDS:
		all_owned = all_owned and WeaponDefs.is_unlocked(id)
	TestLib.check(all_owned, "all four alien weapons can be given")
	TestLib.check(TestMode.select_weapon(&"grenade") and p.weapon.current == &"grenade", "select_weapon picks any weapon")
	p.weapon.ammo = 0
	p.weapon.reserve = 0
	TestMode.fill_ammo()
	TestLib.check(p.weapon.ammo == p.weapon.mag and p.weapon.reserve > 0, "fill ammo: magazine and reserve")
	var c0 := int(Game.progress.get(&"credits"))
	TestMode.add_credits(1000)
	TestLib.check(int(Game.progress.get(&"credits")) == c0 + 1000, "+1000 credits")
	TestMode.max_upgrades()
	TestLib.check(Upgrades.total_levels() == Upgrades.IDS.size() * Upgrades.MAX_LEVEL, "max all upgrades")
	Upgrades.reset()
	TestMode.select_weapon(&"carbine")


func _spawns() -> void:
	var mgr := Game.enemies as EnemyManager
	var vm := Game.vehicles as VehicleManager
	for t: StringName in TestMode.ENEMIES:
		mgr.clear()
		var s := TestMode.spawn_enemy(t)
		var found := false
		for e: Drone in mgr.list:
			found = found or e.type == t
		TestLib.check(s != "" and found, "spawn enemy %s at the crosshair" % t)
	var n0 := vm.list.size()
	for k: StringName in TestMode.VEHICLES:
		var s := TestMode.spawn_vehicle(k)
		TestLib.check(s != "", "spawn vehicle %s" % k)
	TestLib.check(vm.list.size() >= mini(n0 + 1, vm.cap()), "vehicles were added to the manager")
	mgr.clear()
	TestMode.spawn_enemy(&"operative")
	TestMode.spawn_enemy(&"striker")
	TestLib.check(mgr.alive_count() >= 2, "two enemies are alive before kill all")
	TestMode.kill_all_enemies()
	await frames(4)
	var alive := 0
	for e: Drone in mgr.list:
		alive += 0 if e.dead else 1
	TestLib.check(alive == 0, "kill all enemies leaves nobody alive")
	mgr.clear()


func _teleports() -> void:
	p.teleport_to(Game.SPAWN)
	await frames(5)
	for w: String in ["ne", "nw", "se", "sw"]:
		TestMode.teleport(w)
		await frames(3)
		var q := p.global_position
		TestLib.check(absf(q.x) > 250.0 and absf(q.z) > 250.0 and absf(q.x) < CityLayout.WALK and absf(q.z) < CityLayout.WALK and q.y > -0.5, "corner %s: a valid street point near the map corner %s" % [w, str(q)])
	TestMode.teleport("spawn")
	await frames(3)
	TestLib.check(p.global_position.distance_to(Game.SPAWN) < 3.0, "teleport to the spawn")
	TestMode.teleport("core")
	await frames(3)
	var core: Dictionary = Game.missions.call(&"nearest_core", p.global_position)
	TestLib.check(not core.is_empty() and float(core["dist"]) < 12.0, "teleport to the nearest core puts the hero beside it")
	TestMode.teleport("roof")
	await frames(10)
	var city := Game.world as City
	TestLib.check(p.global_position.y > 8.0 and not city.is_inside_building(p.global_position + Vector3(0.0, 0.4, 0.0)), "teleport to a rooftop: high and not inside the building (y %.1f)" % p.global_position.y)
	TestMode.teleport("spawn")
	await frames(5)


func _mission() -> void:
	TestMode.jump_to_chapter(3)
	await frames(3)
	TestLib.check(int(Game.story.get(&"chapter")) == 3 and int(Game.missions.get(&"total")) == 9, "jump to sector 4: the chapter and 9 cores")
	TestMode.jump_to_chapter(0)
	await frames(3)
	var k: Contracts = Game.missions.contracts
	var started := 0
	for kind: StringName in TestMode.CONTRACTS:
		var s := TestMode.start_contract(kind)
		if s != "" and k.is_active() and k.kind == kind:
			started += 1
		else:
			print("  (contract %s did not start headless: '%s')" % [kind, s])
		TestMode.skip_contract()
		await frames(3)
		TestLib.check(not k.is_active() or kind == &"boss", "skip contract ends %s" % kind)
		k.abandon()
		TestMode.kill_all_enemies()
		(Game.enemies as EnemyManager).clear()
	TestLib.check(started >= 5, "at least five contract kinds start on demand (%d of %d)" % [started, TestMode.CONTRACTS.size()])
	TestMode.start_contract(&"officer")
	TestMode.teleport("contract")
	await frames(3)
	k.abandon()
	(Game.enemies as EnemyManager).clear()
	TestMode.start_contract(&"boss")
	var boss := false
	for e: Drone in (Game.enemies as EnemyManager).list:
		boss = boss or e.type == &"overseer"
	TestLib.check(boss, "the boss contract spawns the Vael Overseer")
	k.abandon()
	(Game.enemies as EnemyManager).clear()
	await frames(5)


func _world_and_heat() -> void:
	TestMode.set_weather("STORM")
	TestLib.check(absf(float(Game.atmosphere.get(&"rain_target")) - 1.0) < 0.01, "weather STORM sets the rain target")
	TestMode.set_weather("CLEAR")
	TestLib.check(float(Game.atmosphere.get(&"rain_target")) < 0.1, "weather CLEAR stops the rain")
	TestMode.set_heat(4.0)
	TestLib.check(is_equal_approx(Game.heat, 4.0), "set heat 4")
	TestMode.set_heat(0.0)
	TestLib.check(TestMode.stats_text().contains("FPS"), "the stats text has the perf line")


func _menu_input() -> void:
	Game.state = &"play"
	TestMode.quick_weapons = true
	TestLib.check(menu.open() and Game.state == &"paused" and menu.is_open, "opening the menu in play pauses the game")
	menu.layout()
	TestLib.check(menu.labels().has("GOD MODE") and menu.labels().has("ONE-HIT KILLS"), "the CHEATS page lists the toggles")
	var vp := menu.get_viewport().get_visible_rect().size
	# a real tap on the drawn GOD MODE rectangle
	var god_rect := Rect2()
	for it in menu.items:
		if String(it.get("label", "")) == "GOD MODE":
			god_rect = it["rect"]
	var pos := Vector2(god_rect.get_center().x, menu._top() + god_rect.get_center().y)
	TestLib.check(menu.handle_pointer(1, pos, 1) and menu.handle_pointer(3, pos, 1) and TestMode.god, "a touch tap on the GOD MODE button switches god mode on")
	TestMode.toggle(&"god")
	for i in TestMenu.TABS.size():
		menu.set_page(i)
		menu.layout()
		var n := menu.labels().size()
		TestLib.check(n >= 3, "page %s has buttons (%d)" % [TestMenu.TABS[i], n])
	menu.set_page(3)
	menu.layout()
	var y0 := menu.scroll
	menu.handle_pointer(1, Vector2(vp.x * 0.5, vp.y * 0.8), 2)
	menu.handle_pointer(2, Vector2(vp.x * 0.5, vp.y * 0.3), 2)
	menu.handle_pointer(3, Vector2(vp.x * 0.5, vp.y * 0.3), 2)
	TestLib.check(menu.scroll >= y0, "a drag scrolls the page without pressing a button")
	menu.set_page(0)
	TestLib.check(menu.press_label("KILL ALL ENEMIES") and menu.press_label("FILL AMMO") and menu.press_label("HEAL AND ENERGY"), "buttons run their actions by label")
	menu.close()
	TestLib.check(not menu.is_open and Game.state == &"play", "closing the menu resumes the game")
	# weapon quick buttons: closed, in play
	WeaponDefs.reset_unlocked()
	p.weapon.reset()
	var q2 := menu.quick_rect(2).get_center()
	TestLib.check(menu.handle_pointer(1, q2, 3) and menu.handle_pointer(3, q2, 3), "the quick button 3 takes the touch")
	TestLib.check(p.weapon.current == &"lance" and WeaponDefs.is_unlocked(&"lance"), "quick button 3 selects (and unlocks) the Pulse Lance")
	var q4 := menu.quick_rect(3).get_center()
	menu.handle_pointer(1, q4, 3)
	menu.handle_pointer(3, q4, 3)
	TestLib.check(p.weapon.current == &"grenade", "quick button 4 selects the Singularity Grenade")
	var q1 := menu.quick_rect(0).get_center()
	menu.handle_pointer(1, q1, 3)
	menu.handle_pointer(3, q1, 3)
	TestLib.check(p.weapon.current == &"carbine", "quick button 1 selects the carbine")
	TestMode.quick_weapons = false
	TestLib.check(not menu.handle_pointer(1, q2, 3), "quick buttons off: the touch passes through")
	TestMode.quick_weapons = true
	Game.state = &"paused"
	_more(true)
	TestLib.check(menu.handle_pointer(1, menu.entry_rect().get_center(), 4) and menu.handle_pointer(3, menu.entry_rect().get_center(), 4) and menu.is_open, "the TEST button of the pause screen opens the menu")
	menu.close()
	TestLib.check(Game.state == &"paused", "closing a menu opened from the pause screen stays paused")
	Game.state = &"menu"
	_more(true)
	TestLib.check(menu.handle_pointer(1, menu.entry_rect().get_center(), 4) and menu.handle_pointer(3, menu.entry_rect().get_center(), 4) and menu.is_open, "the TEST button of the title screen opens the menu")
	menu.close()
	WeaponDefs.reset_unlocked()
	Game.state = &"play"
