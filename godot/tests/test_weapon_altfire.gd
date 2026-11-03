extends RefCounted
## Weapons depth (C4/C5): alt-fire per class, ammo types, reload tilt data, idle inspect, weapon-specific hit sounds, the ALT touch button.
## Run: tools/test.sh tests/test_weapon_altfire.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

var e := Env.new()


func run(host: Node) -> void:
	await e.setup(host)
	var p: Player = e.p
	var w: PlayerWeapon = p.weapon
	Fixture.release_inputs()
	Game.state = &"play"
	WeaponDefs.reset_unlocked()

	# data: every class has an alt, a hit sound and a tilt
	for id: StringName in WeaponDefs.IDS:
		TestLib.check(WeaponDefs.ALTS.has(id) and WeaponDefs.HIT_SND.has(id) and WeaponDefs.TILT.has(id), "%s has alt / hit sound / tilt" % id)
	var snds := {}
	for id: StringName in WeaponDefs.IDS:
		snds[str(WeaponDefs.hit_snd(id)[0])] = true
	TestLib.check(snds.size() >= 5, "hit sounds differ between weapons")

	# carbine overcharge: one shot, costs 4 rounds
	w.reset()
	w.ammo = w.mag
	var a0 := w.ammo
	var s0 := w.shots_fired
	TestLib.check(w.alt_fire(false), "carbine overcharge fires")
	TestLib.check(w.ammo == a0 - 4 and w.shots_fired == s0 + 1 and w.alt_fired == 1, "overcharge costs 4 rounds, one shot (ammo %d)" % w.ammo)
	TestLib.check(not w.alt_fire(false), "alt-fire is on cooldown")
	TestLib.check(is_equal_approx(w._alt_k, 1.0) and not w._alt_single, "alt modifiers reset after the shot")
	w.tick(5.0, false, false, false, false)
	w.ammo = 2
	TestLib.check(not w.alt_fire(false) and w.ammo == 2, "too few rounds: no alt-fire, no cost")

	# scatter slug: one pellet
	WeaponDefs.unlock(&"scatter")
	w.switch_to(&"scatter", true)
	w.ammo = w.mag
	w.tick(5.0, false, false, false, false)
	var s1 := w.shots_fired
	TestLib.check(w.alt_fire(false) and w.shots_fired == s1 + 1 and w.ammo == w.mag - 1, "scatter slug costs one round")

	# lance full pierce: instant, costs 2
	WeaponDefs.unlock(&"lance")
	w.switch_to(&"lance", true)
	w.ammo = w.mag
	w.tick(5.0, false, false, false, false)
	TestLib.check(w.alt_fire(false) and w.ammo == w.mag - 2, "lance full pierce is instant and costs 2")

	# grenade cluster: two grenades for one round
	WeaponDefs.unlock(&"grenade")
	w.switch_to(&"grenade", true)
	w.ammo = w.mag
	w.tick(5.0, false, false, false, false)
	TestLib.check(w.alt_fire(false) and w.ammo == w.mag - 1 and w.grenades_active() == 2, "cluster throws two grenades for one round")

	# volley: rounds ride the burst machinery
	WeaponDefs.unlock(&"burst")
	w.switch_to(&"burst", true)
	w.ammo = w.mag
	w.tick(5.0, false, false, false, false)
	var v0 := w.ammo
	TestLib.check(w.alt_fire(false), "burst pistol volley starts")
	for _i in 120:
		w.tick(1.0 / 60.0, false, false, false, false)
		if w.ammo <= v0 - 6:
			break
	TestLib.check(w.ammo == v0 - 6, "volley spends 6 rounds (%d)" % (v0 - w.ammo))

	# alt-fire blocked while reloading
	w.switch_to(&"carbine", true)
	w.ammo = 10
	w.tick(5.0, false, false, false, false)
	w.start_reload()
	TestLib.check(not w.alt_fire(false), "no alt-fire during reload")
	w.cancel_reload()

	# ammo types
	w.switch_to(&"carbine", true)
	TestLib.check(w.ammo_type == 0 and is_equal_approx(float(w.ammo_info()["dmg"]), 1.0), "starts on standard ammo")
	TestLib.check(w.cycle_ammo_type() and str(w.ammo_info()["id"]) == "heavy" and float(w.ammo_info()["dmg"]) > 1.0, "heavy ammo hits harder")
	TestLib.check(w.cycle_ammo_type() and bool(w.ammo_info()["pierce"]), "piercing ammo breaks shields")
	TestLib.check(w.cycle_ammo_type() and w.ammo_type == 0, "ammo types cycle")
	WeaponDefs.unlock(&"gravity")
	w.switch_to(&"gravity", true)
	TestLib.check(not w.cycle_ammo_type() and is_equal_approx(float(w.ammo_info()["dmg"]), 1.0), "throwables have one ammo type")
	w.switch_to(&"carbine", true)

	# idle inspect: starts after the idle time, cancels on activity, no ammo change
	w.reset()
	w.tick(5.0, false, false, false, false)
	var am := w.ammo
	TestLib.check(w.inspect_t <= 0.0, "no inspect right away")
	for _i in 20:
		w.tick(1.0, false, false, false, false)
		if w.inspect_t > 0.0:
			break
	TestLib.check(w.inspect_t > 0.0 and w.ammo == am, "idle inspect starts without touching ammo")
	w.tick(0.1, false, false, true, false)
	TestLib.check(w.inspect_t <= 0.0, "aiming cancels the inspect")
	TestLib.check(w.start_inspect() and w.inspect_t > 0.0, "inspect on demand")
	w.tick(PlayerWeapon.INSPECT_TIME + 0.5, false, false, false, false)
	TestLib.check(w.inspect_t <= 0.0, "inspect ends")

	# rig reload tilt is per weapon
	TestLib.check(float(WeaponDefs.TILT[&"flux"]) != float(WeaponDefs.TILT[&"lance"]), "reload tilt differs per weapon")

	# touch: an ALT button bound to the altfire action
	var has_alt := false
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"altfire":
			has_alt = true
	TestLib.check(has_alt and InputMap.has_action(&"altfire"), "touch ALT button and altfire action exist")
	WeaponDefs.reset_unlocked()
