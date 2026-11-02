extends RefCounted
## Weapon feel (C1/A1): per-weapon recoil patterns, shake, sound variation, ADS spread, tuned rates, damage numbers, shell eject. Run: tools/test.sh tests/test_weapon_feel.gd


func run(host: Node) -> void:
	var seen := {}
	for id: StringName in WeaponDefs.IDS:
		var d := WeaponDefs.def(id)
		for k in ["pattern", "shake", "vol", "pitch_lo", "pitch_hi", "eject", "flash", "ads_kick", "ads_spread"]:
			TestLib.check(d.has(k), "%s has %s" % [id, k])
		TestLib.check(float(d["pitch_lo"]) < float(d["pitch_hi"]), "%s sound pitch varies" % id)
		TestLib.check(float(d["ads_spread"]) <= 1.0 and float(d["ads_kick"]) <= 1.0, "%s ADS never worse than hip" % id)
		seen[str(d["pattern"])] = true
	TestLib.check(seen.size() >= 3, "recoil patterns differ between weapons")
	var c0 := WeaponDefs.pattern_at(&"carbine", 0)
	TestLib.check(c0 == WeaponDefs.pattern_at(&"carbine", 6), "pattern repeats each burst")
	TestLib.check(WeaponDefs.pattern_at(&"carbine", 2).x < 0.0 and WeaponDefs.pattern_at(&"carbine", 3).x > 0.0, "carbine pattern wanders left then right")
	TestLib.check(float(WeaponDefs.def(&"carbine")["interval"]) < 0.12 and float(WeaponDefs.def(&"scatter")["interval"]) > 0.7, "fire rates tuned: carbine fast, scatter slow")
	TestLib.check(float(WeaponDefs.def(&"lance")["shake"]) > float(WeaponDefs.def(&"carbine")["shake"]), "lance shakes harder than carbine")

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 3)
	var p: Player = Game.player
	if p == null or p.weapon == null:
		TestLib.check(false, "player with weapon present")
		return
	var w: PlayerWeapon = p.weapon
	w.reset()
	var before := w.shells_ejected
	w._burst = 1
	w._shoot(0.016, false)
	TestLib.check(w.shells_ejected == before + 1, "carbine ejects a shell")
	w._damage_number(p.global_position + Vector3(0, 1, -5), 14.0, true, false)
	TestLib.check(w.numbers_spawned == 1 and w._numbers[0].visible, "damage number spawns")
	w.tick(1.0, false, false, false, false)
	TestLib.check(not w._numbers[0].visible, "damage number expires")
	w.tick(0.5, false, false, true, false)
	var ads := w.spread
	w.bloom = 0.02
	w.tick(0.01, false, false, true, false)
	var ads_b := w.spread
	w.tick(0.01, false, false, false, false)
	TestLib.check(ads_b < w.spread, "ADS spread tighter than hip")
	TestLib.check(ads > 0.0, "spread positive")
