extends RefCounted
## The four extra weapons (burst pistol, rail rifle, flux SMG, gravity launcher) and the attachment system (optic / barrel / core): data, modifiers, burst fire, save round trip.
## Run: tools/test.sh tests/test_weapon_attachments.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

const DT := 1.0 / 60.0
const NEW: Array[StringName] = [&"burst", &"rail", &"flux", &"gravity"]

var e := Env.new()


func run(host: Node) -> void:
	await e.setup(host)
	var p: Player = e.p
	var w: PlayerWeapon = p.weapon
	Fixture.release_inputs()
	Game.state = &"play"
	Attachments.reset()
	WeaponDefs.reset_unlocked()

	TestLib.check(WeaponDefs.IDS.size() == 8, "eight weapon classes")
	for id: StringName in NEW:
		var d := WeaponDefs.def(id)
		TestLib.check(WeaponDefs.DEFS.has(id) and d.has("pattern") and d.has("tracer") and int(d["mag"]) > 0 and WeaponDefs.price(id) > 0, "%s has a full definition" % id)
	TestLib.check(float(WeaponDefs.def(&"flux")["interval"]) < 0.08 and float(WeaponDefs.def(&"rail")["damage"]) > 60.0 and int(WeaponDefs.def(&"burst")["burst"]) == 3, "distinct feel: fast SMG, heavy rail, 3-round burst")

	# attachments: modifiers on a copy, base untouched
	var base_dmg := float(WeaponDefs.def(&"carbine")["damage"])
	TestLib.check(not Attachments.equip(&"carbine", &"scope"), "an unowned part cannot be equipped")
	Attachments.give(&"overcharge")
	Attachments.give(&"scope")
	Attachments.give(&"compensator")
	TestLib.check(Attachments.equip(&"carbine", &"overcharge") and Attachments.equip(&"carbine", &"scope") and Attachments.equip(&"carbine", &"compensator"), "three slots equip")
	var eff := Attachments.effective(&"carbine")
	TestLib.check(is_equal_approx(float(eff["damage"]), base_dmg * 1.2) and float(eff["zoom"]) <= 36.0 and float(eff["kick"]) < float(WeaponDefs.def(&"carbine")["kick"]), "stat modifiers apply")
	TestLib.check(is_equal_approx(float(WeaponDefs.def(&"carbine")["damage"]), base_dmg), "base definition unchanged")
	TestLib.check(WeaponDefs.mag_size(&"carbine", 0) == 27, "overcharge core trades magazine (%d)" % WeaponDefs.mag_size(&"carbine", 0))
	Attachments.equip(&"carbine", &"overcharge")
	Attachments.toggle(&"carbine", &"overcharge")
	TestLib.check(Attachments.part_in(&"carbine", &"core") == &"" and is_equal_approx(float(Attachments.effective(&"carbine")["damage"]), base_dmg), "toggle takes a part off")

	# the weapon node loads the effective numbers
	Attachments.equip(&"carbine", &"overcharge")
	w.reset()
	TestLib.check(is_equal_approx(float(w.def["damage"]), base_dmg * 1.2), "PlayerWeapon uses the attachment numbers")

	# save round trip
	var saved := Attachments.to_save()
	Attachments.reset()
	Attachments.from_save(saved)
	TestLib.check(Attachments.is_owned(&"scope") and Attachments.part_in(&"carbine", &"core") == &"overcharge", "save / load keeps owned and equipped parts")
	Attachments.from_save({})
	TestLib.check(Attachments.owned.is_empty(), "an old save without attachments loads empty")
	Attachments.from_save({"owned": ["bogus", "rapid"], "equipped": {"carbine": {"core": "rapid", "optic": "rapid"}, "nope": {"core": "rapid"}}})
	TestLib.check(Attachments.owned == [&"rapid"] and Attachments.part_in(&"carbine", &"core") == &"rapid" and Attachments.part_in(&"carbine", &"optic") == &"", "unknown or mismatched entries are dropped")
	Attachments.reset()

	# burst pistol fires three rounds per trigger pull
	for id: StringName in NEW:
		WeaponDefs.unlock(id)
	w.reset()
	await e.prep(Vector3(0.0, 0.05, 0.0))
	w.switch_to(&"burst", true)
	w.fire_t = 0.0
	var before := w.shots_fired
	for i in 40:
		w.tick(DT, i == 0, false, false, false)
	TestLib.check(w.shots_fired - before == 3, "burst pistol fires 3 rounds per pull (%d)" % (w.shots_fired - before))
	w.switch_to(&"flux", true)
	w.fire_t = 0.0
	before = w.shots_fired
	for i in 30:
		w.tick(DT, true, false, false, false)
	TestLib.check(w.shots_fired - before >= 6, "flux SMG sprays (%d)" % (w.shots_fired - before))
	TestLib.check(w.cycle(1) and w.cycle(-1), "the wheel cycle walks all eight weapons")

	Attachments.reset()
	WeaponDefs.reset_unlocked()
	await e.teardown()
