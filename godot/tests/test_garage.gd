extends RefCounted
## Garage tests (headless): save a car, paint, upgrades (speed / armour / grip / weapon) charged through a wallet, CALL CAR (summon outdoors, refused in
## play-less / driving states), the tuned spec is a copy and resets in the pool, the touch buttons, the screen, and save compatibility (round trip, an old
## save without [garage], damaged data). Run: tools/test.sh tests/test_garage.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

var e := Env.new()
var p: Player
var mgr: VehicleManager
var root: Node3D


func run(host: Node) -> void:
	seed(5)
	await e.setup(host)
	p = e.p
	root = e.root
	Fixture.add_floor(root, 400.0)
	mgr = (load("res://scenes/vehicle_manager.tscn") as PackedScene).instantiate() as VehicleManager
	root.add_child(mgr)
	await e.frames(3)
	_pure()
	_save_and_summon()
	await _screen_and_touch(host)
	_save_compat()
	mgr.queue_free()
	await e.teardown()


func _pure() -> void:
	var g := Garage.new()
	var wallet := Progress.new()
	TestLib.check(not g.has_car() and not g.upgrade(&"speed", wallet), "an empty garage has no car and sells no upgrade")
	g.kind = &"sedan"
	TestLib.check(g.has_car(), "a kept kind is a car")
	TestLib.check(not g.upgrade(&"speed", wallet) and g.level(&"speed") == 0, "too poor: nothing is bought")
	wallet.credits = 10000
	var before := wallet.credits
	var p1 := g.price(&"speed")
	TestLib.check(g.upgrade(&"speed", wallet) and g.level(&"speed") == 1 and wallet.credits == before - p1, "an upgrade costs its price and raises the level")
	TestLib.check(g.price(&"speed") > p1, "the next level costs more")
	for i in 5:
		g.upgrade(&"speed", wallet)
	TestLib.check(g.level(&"speed") == Garage.MAX_LEVEL and g.price(&"speed") == 0 and not g.can_upgrade(&"speed", wallet), "levels stop at the maximum")
	g.upgrade(&"armour", wallet)
	g.upgrade(&"grip", wallet)
	var base: Dictionary = VehicleSpecs.SPECS[&"sedan"]
	var t := g.tuned_spec()
	TestLib.check(float(t["max"]) > float(base["max"]) * 1.1 and float(t["hp"]) > float(base["hp"]) * 1.1 and float(t["grip"]) > float(base["grip"]), "tuned spec is faster, tougher and grippier")
	TestLib.check(is_equal_approx(float(VehicleSpecs.SPECS[&"sedan"]["max"]), float(base["max"])) and float(base["max"]) == 28.0, "the shared spec stays untouched")
	TestLib.check(g.weapon_def().is_empty(), "a sedan has no weapon at level 0")
	g.upgrade(&"weapon", wallet)
	TestLib.check(not g.weapon_def().is_empty(), "weapon level 1 gives any car a gun slot")
	TestLib.check(g.set_paint(3) and g.paint == 3 and not g.set_paint(99), "paint takes a palette index only")
	wallet.free()


func _save_and_summon() -> void:
	var g := mgr.get_garage()
	TestLib.check(not g.has_car() and mgr.summon_garage() == null, "no car kept: CALL CAR does nothing")
	var starter := mgr.starter
	TestLib.check(starter != null, "the starter car exists")
	p.global_position = starter.global_position + Vector3(0, 0, 3)
	mgr.enter(starter)
	TestLib.check(mgr.save_driven() and g.has_car() and g.kind == &"sport", "the driven car is saved to the garage")
	var wallet := Progress.new()
	wallet.credits = 5000
	g.upgrade(&"armour", wallet)
	g.upgrade(&"weapon", wallet)
	g.set_paint(2)
	TestLib.check(mgr.summon_garage() == null, "CALL CAR is refused while driving")
	mgr.exit_vehicle()
	p.teleport_to(Vector3(120, 0, 120))
	p.vehicle = null
	var gc := mgr.garage_car()
	if gc != null:
		mgr._release(gc)                         # the saved starter wore the tuning: send it back to the pool first
	mgr._summon_ready = 0.0
	var car := mgr.summon_garage()
	TestLib.check(car != null and car.garage_car and car.kind == &"sport" and car.active, "CALL CAR brings the garage car")
	if car == null:
		return
	TestLib.check(car.max_hp > float((VehicleSpecs.SPECS[&"sport"] as Dictionary)["hp"]) * 1.1, "it has the armour upgrade")
	TestLib.check(car.weapons != null and car.weapons.mounted() and car.paint_i == 2, "it has the weapon slot and the saved paint")
	TestLib.check(car.global_position.distance_to(p.global_position) < 15.0, "it arrives close to the player")
	TestLib.check(mgr.summon_garage() == null, "the call has a cooldown")
	mgr._summon_ready = 0.0
	p.global_position = Vector3(-60, 0, 60)
	var again := mgr.summon_garage()
	TestLib.check(again == car and mgr.list.count(car) == 1, "a second call moves the same car")
	TestLib.check(car.global_position.distance_to(p.global_position) < 15.0, "and brings it to the new place")
	mgr._release(car)
	TestLib.check(not car.garage_car and is_equal_approx(car.max_hp, float((VehicleSpecs.SPECS[&"sport"] as Dictionary)["hp"])), "back in the pool the car is stock again")
	mgr._summon_ready = 0.0
	Game.state = &"paused"
	TestLib.check(mgr.summon_garage() == null, "no call while paused")
	Game.state = &"play"
	wallet.free()


func _screen_and_touch(host: Node) -> void:
	var g := mgr.get_garage()
	TestLib.check(g.has_car(), "the garage still has the car")
	var gs := GarageScreen.new()
	host.add_child(gs)
	await e.frames(2)
	Game.state = &"play"
	gs.open()
	TestLib.check(gs.is_open() and Game.state == &"paused", "the garage screen pauses through Game.state")
	for nm in ["Save", "Close", "Paint0", "Paint7", "Up_speed", "Up_armour", "Up_grip", "Up_weapon"]:
		var b := gs.find_child(nm, true, false) as Button
		TestLib.check(b != null and b.custom_minimum_size.y >= 64.0, "screen button %s exists and is touch sized" % nm)
	var pb := gs.find_child("Paint4", true, false) as Button
	pb.pressed.emit()
	TestLib.check(g.paint == 4, "a swatch repaints the kept car")
	gs.close_screen()
	TestLib.check(not gs.is_open() and Game.state == &"play", "closing resumes play")
	gs.queue_free()
	# touch buttons
	var tc := (load("res://scenes/touch_controls.tscn") as PackedScene).instantiate() as TouchControls
	host.add_child(tc)
	await e.frames(2)
	var call_b := {}
	var gar_b := {}
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"garage_call":
			call_b = b
		if b["action"] == &"garage_open":
			gar_b = b
	TestLib.check(not call_b.is_empty() and not gar_b.is_empty(), "CALL CAR and GARAGE buttons are defined")
	Game.vehicles = mgr
	Game.player = p
	p.vehicle = null
	tc.more_open = true                                  # CALL CAR lives in the collapsed MORE cluster
	TestLib.check(tc.button_visible(call_b) and not tc.button_visible(gar_b), "on foot CALL CAR shows, GARAGE does not")
	var empty := Garage.new()
	var kept := g.to_save()
	g.clear()
	TestLib.check(tc.button_visible(call_b), "CALL CAR stays with an empty garage (it brings the quantum hover-bike)")
	g.from_save(kept)
	var dummy := Node3D.new()
	host.add_child(dummy)
	p.vehicle = dummy
	TestLib.check(tc.button_visible(gar_b) and not tc.button_visible(call_b), "while driving GARAGE shows, CALL CAR does not")
	p.vehicle = null
	dummy.queue_free()
	empty = null
	tc.queue_free()


func _save_compat() -> void:
	var pr := Progress.new()
	pr.path = "user://test_garage_save.cfg"
	pr.garage.kind = &"suv"
	pr.garage.paint = 6
	pr.garage.levels = {&"speed": 2, &"weapon": 1}
	TestLib.check(pr.save_file(), "saves with a garage")
	var pr2 := Progress.new()
	pr2.path = pr.path
	TestLib.check(pr2.load_file() and pr2.garage.kind == &"suv" and pr2.garage.paint == 6, "kind and paint survive a round trip")
	TestLib.check(pr2.garage.level(&"speed") == 2 and pr2.garage.level(&"weapon") == 1 and pr2.garage.level(&"grip") == 0, "upgrade levels survive")
	# an old save (no [garage]) loads with an empty garage
	var cf := ConfigFile.new()
	cf.load(pr.path)
	cf.erase_section("garage")
	cf.save(pr.path)
	var pr3 := Progress.new()
	pr3.garage.kind = &"sedan"
	TestLib.check(pr3.path != "" and _load_from(pr3, pr.path) and not pr3.garage.has_car(), "a save without [garage] loads with an empty garage")
	# damaged data
	var g := Garage.new()
	g.from_save({"kind": "no_such_car", "paint": 3, "levels": {"speed": 3}})
	TestLib.check(not g.has_car(), "an unknown kind gives an empty garage")
	g.from_save({"kind": "vael_patrol"})
	TestLib.check(not g.has_car(), "a patrol vehicle cannot be kept")
	g.from_save({"kind": "sedan", "paint": 999, "levels": {"speed": 77, "grip": "x"}})
	TestLib.check(g.has_car() and g.paint < VehicleSpecs.COLORS.size() and g.level(&"speed") == Garage.MAX_LEVEL and g.level(&"grip") == 0, "paint and levels are clamped")
	pr.new_campaign()
	TestLib.check(not pr.garage.has_car(), "a new campaign empties the garage")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pr.path))
	pr.free()
	pr2.free()
	pr3.free()


func _load_from(pr: Progress, f: String) -> bool:
	pr.path = f
	return pr.load_file()
