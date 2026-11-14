extends RefCounted
## DEV PROBE of the wave 114 play critic (not a regression test): do the numbers the weapon card SHOWS (fire rate in RPM, damage per shot, damage per second) match what the weapon DOES? Every hitscan weapon fires
## for 3 s of game time at an immortal dummy 4 m away (the hero aims at its chest); the shots counted and the hit points taken are compared with WeaponStats.card. Prints PROBE lines.
## Run: tools/test.sh tests/dev_w114_rate.gd

const TIMEOUT_SECONDS := 140.0
const DT := 1.0 / 60.0
const SECS := 3.0

var _p: Player
var _w: PlayerWeapon


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	WeaponDefs.reset_unlocked()
	WeaponDefs.hero_mode = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 8)
	Game.state = &"play"
	_p = Game.player as Player
	_w = _p.weapon
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	TestMode.god = true
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	TestMode.infinite_ammo = true
	if Encounters.current != null:
		Encounters.current.enabled = false
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	var fwd := -_p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var spot := _p.global_position
	var dummy := mgr.spawn(&"heavy", spot + fwd * 4.0, false)
	dummy.set_physics_process(false)
	await TestLib.frames(host, 2)
	var rows: Array = []
	for id: StringName in WeaponDefs.all_ids():
		var d := WeaponDefs.def(id)
		if String(d["kind"]) != "hit":
			continue
		if OS.get_environment("W114_IDS") != "" and not (OS.get_environment("W114_IDS").split(",") as PackedStringArray).has(String(id)):
			continue
		_p.teleport_to(spot)
		_w.switch_to(id, true)
		_w.ammo = _w.mag
		_w.fire_t = 0.0
		_w.swap_t = 0.0
		_w.reload_t = 0.0
		_w.spread_override = 0.0
		dummy.max_hp = 1.0e7
		dummy.hp = 1.0e7
		dummy.global_position = spot + fwd * 4.0
		await TestLib.frames(host, 1)
		_p.camera_rig.aim_at(dummy.center())
		var hp0 := dummy.hp
		var s0 := _w.shots_fired
		for i in int(SECS / DT):
			_p.camera_rig.aim_at(dummy.center())
			_w.tick(DT, true, false, true, false)
			_w.mech.tick(DT)
			_w.ammo = _w.mag
		var shots := _w.shots_fired - s0
		var lost := hp0 - dummy.hp
		_w.tick(5.0, false, false, false, false)
		var card := WeaponStats.card(id, _w.def)
		var rpm_shown := float(card["rpm"])
		var rpm_real := float(shots) / SECS * 60.0
		var dps_shown := float(card["dps"])
		var dps_real := lost / SECS
		rows.append([id, rpm_shown, rpm_real, dps_shown, dps_real, int(d.get("burst", 1)), d.has("spin_up") or d.has("ramp")])
	var rr: Array[float] = []
	var dr: Array[float] = []
	for r: Array in rows:
		rr.append(float(r[2]) / maxf(float(r[1]), 1.0))
		dr.append(float(r[4]) / maxf(float(r[3]), 1.0))
	var rs := rr.duplicate()
	rs.sort()
	var ds := dr.duplicate()
	ds.sort()
	var rmed: float = rs[rs.size() / 2]
	var dmed: float = ds[ds.size() / 2]
	print("PROBE %d hitscan weapons, median measured / shown RPM %.2f, median measured / shown DPS %.2f (the hero's damage multiplier is in the second)" % [rows.size(), rmed, dmed])
	var bad_rate := 0
	var bad_dps := 0
	for k in rows.size():
		var r: Array = rows[k]
		var rrat: float = rr[k] / rmed
		var drat: float = dr[k] / dmed
		var flag := ""
		if rrat < 0.8 or rrat > 1.25:
			flag += " RATE"
			bad_rate += 1
		if drat < 0.7 or drat > 1.4:
			flag += " DPS"
			bad_dps += 1
		if flag != "":
			print("PROBE %-14s shown %5.0f rpm real %5.0f (x%.2f) | shown dps %6.1f real %6.1f (x%.2f) burst %d ramp %s%s" % [r[0], r[1], r[2], rrat, r[3], r[4], drat, r[5], r[6], flag])
	print("PROBE outliers: rate %d, dps %d of %d" % [bad_rate, bad_dps, rows.size()])
	_w.spread_override = -1.0
	TestMode.infinite_ammo = false
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
	WeaponDefs.hero_mode = false
