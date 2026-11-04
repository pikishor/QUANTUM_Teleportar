extends RefCounted
## DEMO menu (scripts/ui/demo_menu.gd, the DEMO tab of the TEST MENU) in the composed game: every vehicle kind, enemy type and boss, every weapon, weather, time of day,
## heat level and the full hero kit are launched through the entries the menu draws. Run: tools/test.sh tests/test_demo_menu.gd

var host: Node


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	Game.state = &"play"
	var p := Game.player as Player
	await TestLib.frames(host, 10)
	var menu: TestMenu = host.get_tree().get_first_node_in_group(&"test_menu") as TestMenu
	TestLib.check(menu != null and TestMenu.TABS.has("DEMO"), "the TEST MENU has a DEMO tab")
	menu.set_page(TestMenu.TABS.find("DEMO"))
	var ents := DemoMenu.entries()
	var labels: Array[String] = []
	for e in ents:
		labels.append(e["label"])
	for k in DemoMenu.vehicle_kinds():
		TestLib.check(labels.has(String(k).to_upper()), "entry for vehicle %s" % k)
	for t in DemoMenu.enemy_types() + DemoMenu.boss_types():
		TestLib.check(labels.has(String(t).to_upper()), "entry for enemy %s" % t)
	TestLib.check(DemoMenu.boss_types().size() >= 3 and DemoMenu.vehicle_kinds().size() >= 14, "bosses and vehicles are listed")
	for id: StringName in WeaponDefs.IDS:
		TestLib.check(labels.has(WeaponDefs.title(id)), "entry for weapon %s" % id)
	# run every launch action against the live game
	for e in ents:
		if e.has("head"):
			continue
		if Game.state != &"play":
			Game.state = &"play"
		var r := str((e["fn"] as Callable).call())
		TestLib.check(r != "", "action '%s' did something" % e["label"])
		await TestLib.frames(host, 2)
		(Game.enemies as EnemyManager).list.duplicate().map(func(d: Drone) -> void: if is_instance_valid(d): d.damage(TestMode.KILL, true))
	TestLib.check(Weather.current == &"fog", "weather was set (last entry wins: fog)")
	TestLib.check(is_equal_approx(Game.heat, 5.0), "heat level set")
	DemoMenu.full_hero_kit()
	for id: StringName in WeaponDefs.IDS:
		TestLib.check(WeaponDefs.is_unlocked(id), "full kit unlocks %s" % id)
	TestLib.check(p.hp >= p.max_hp - 0.01, "full kit heals")
	TestLib.check(Game.state == &"play" and p.global_position.is_finite(), "game still playing")
	main.queue_free()
