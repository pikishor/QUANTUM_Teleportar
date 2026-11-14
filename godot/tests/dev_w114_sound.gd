extends RefCounted
## DEV PROBE of the wave 114 play critic (not a regression test): which sound files really start when the hero fires, swings, throws, charges, reloads, equips or dry-fires each of the 229 weapons.
## Prints PROBE lines. Run: tools/test.sh tests/dev_w114_sound.gd (headless, the real scene, Sfx unmuted).

const TIMEOUT_SECONDS := 140.0
const DT := 1.0 / 60.0

var _host: Node
var _p: Player
var _w: PlayerWeapon


func _players() -> Array:
	var out: Array = []
	out.append_array(Sfx._players)
	out.append_array(Sfx._players3d)
	out.append_array(WeaponAudio._tail_players)
	return out


func _stop_all() -> void:
	for p in _players():
		(p as Node).call(&"stop")


## Names (no number suffix, no extension) of everything that is playing now.
func _playing() -> Array[String]:
	var out: Array[String] = []
	for p in _players():
		if p.playing and p.stream != null:
			var nm := String(p.stream.resource_path.get_file().get_basename())
			var us := nm.rfind("_")
			if us > 0 and nm.substr(us + 1).is_valid_int():
				nm = nm.substr(0, us)
			if not out.has(nm):
				out.append(nm)
	return out


func _equip(id: StringName) -> void:
	_w.switch_to(id, true)
	_w.ammo = _w.mag
	_w.fire_t = 0.0
	_w.swap_t = 0.0
	_w.reload_t = 0.0
	if _w.reserve >= 0:
		_w.reserve = maxi(_w.reserve, 40)


func run(host: Node) -> void:
	_host = host
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = false
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
	if Encounters.current != null:
		Encounters.current.enabled = false
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	Sfx.director_on = false
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	await TestLib.frames(host, 4)
	var cls_total := {}
	var cls_bad := {}
	var lines: Array[String] = []
	for id: StringName in WeaponDefs.all_ids():
		var d := WeaponDefs.def(id)
		var kind := String(d["kind"])
		var cls := WeaponDefs.class_of(id)
		var sid := WeaponAudio.set_of(id)
		var sd := WeaponAudio.data(sid)
		_stop_all()
		await TestLib.frames(host, 2)
		_equip(id)
		await TestLib.frames(host, 1)
		var eq := _playing()
		# fire
		_stop_all()
		await TestLib.frames(host, 1)
		var s0 := _w.shots_fired
		var c0 := _w.combo_hits
		var wa0 := WeaponAudio.shots
		var held := 0
		var limit := 90
		if d.has("charge_time"):
			limit = int((float(d["charge_time"]) + 0.4) / DT)
		for i in limit:
			_w.tick(DT, true, false, false, false)
			_w.mech.tick(DT)
			held += 1
			if (_w.shots_fired > s0 and kind != "charge") or (kind == "melee" and _w.combo_hits > c0):
				break
		if kind == "charge":
			_w.tick(DT, false, false, false, false)
			_w.tick(DT, false, false, false, false)
		var fired := _w.combo_hits > c0 if kind == "melee" else _w.shots_fired > s0
		var via_set := WeaponAudio.shots - wa0
		var lastp := String(Sfx.last_played)
		await TestLib.frames(host, 8)                                     # the tail starts a few tens of ms late
		await _host.get_tree().create_timer(0.12, true, false, true).timeout
		var fp := _playing()
		# reload
		_stop_all()
		await TestLib.frames(host, 1)
		_w.cancel_reload()
		_w.ammo = 0
		var rl_ok := _w.start_reload()
		await TestLib.frames(host, 2)
		var rl := _playing()
		_w.cancel_reload()
		# dry fire
		_stop_all()
		await TestLib.frames(host, 1)
		_w.ammo = 0
		_w.reload_t = 0.0
		_w.fire_t = 0.0
		var rsv := _w.reserve
		_w.reserve = 0
		_w.tick(DT, true, false, false, false)
		await TestLib.frames(host, 2)
		var dry := _playing()
		_w.reserve = rsv
		var body := String(sd.get("body", ""))
		var has_body := false
		for nm in fp:
			if nm == body or nm.begins_with(body):
				has_body = true
		var line := "PROBE %-14s %-8s %-9s set=%-14s body=%-16s fired=%s via_set=%d last=%s ok_body=%s | fire=%s | equip=%s | reload=%s(%s) | dry=%s" % [id, cls, kind, sid, body, fired, via_set, lastp, has_body, ",".join(fp), ",".join(eq), ",".join(rl), rl_ok, ",".join(dry)]
		lines.append(line)
		cls_total[cls] = int(cls_total.get(cls, 0)) + 1
		if via_set == 0 and fired:
			cls_bad[cls] = int(cls_bad.get(cls, 0)) + 1
		_w.tick(6.0, false, false, false, false)
	for l in lines:
		print(l)
	for cls in cls_total:
		print("PROBE_SUM %s total %d fire_not_through_set %d" % [cls, cls_total[cls], int(cls_bad.get(cls, 0))])
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
	WeaponDefs.hero_mode = false
