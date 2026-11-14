extends RefCounted
## DEV PROBE of the wave 113 play critic (not a regression test): sweeps every entry of the blast table at 0.5, 1.0 and 1.5 x radius against enemies, a parked car and the hero.
## Prints PROBE lines; the real regressions go to tests/test_play_critic_w113.gd. Run: tools/test.sh tests/dev_w113_sweep.gd

const TIMEOUT_SECONDS := 140.0
const DT := 1.0 / 60.0

var _host: Node
var _p: Player
var _mgr: EnemyManager
var _ops: BlastOps
var _spot := Vector3.ZERO
var _yaw := 0.0
var _foes: Array[Drone] = []


func _lane() -> bool:
	var city := Game.world as City
	if city == null:
		return false
	var space := _p.get_world_3d().direct_space_state
	for tries in 400:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for k in 8:
			var yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var a := rp + Vector3(0, 1.5, 0)
			var q := PhysicsRayQueryParameters3D.create(a, a + dir * 60.0, Game.L_WORLD | Game.L_VEHICLE)
			var side := dir.cross(Vector3.UP) * 6.0
			var q2 := PhysicsRayQueryParameters3D.create(a + Vector3(0, -0.5, 0) + side, a + Vector3(0, -0.5, 0) + side + dir * 60.0, Game.L_WORLD | Game.L_VEHICLE)
			var q3 := PhysicsRayQueryParameters3D.create(a + Vector3(0, -0.5, 0) - side, a + Vector3(0, -0.5, 0) - side + dir * 60.0, Game.L_WORLD | Game.L_VEHICLE)
			if space.intersect_ray(q).is_empty() and space.intersect_ray(q2).is_empty() and space.intersect_ray(q3).is_empty():
				_spot = rp
				_yaw = yaw
				return true
	return false


func _dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _foe(pos: Vector3, hp := 1.0e6) -> Drone:
	var d := _mgr.spawn(&"operative", pos, false)
	if d != null:
		d.set_physics_process(false)
		d.global_position = pos
		d.max_hp = hp
		d.hp = hp
		d.rotation.y = _yaw
		_foes.append(d)
	return d


func _clear_foes() -> void:
	_foes.clear()
	_mgr.clear()


func run(host: Node) -> void:
	_host = host
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	_p = Game.player as Player
	if not is_instance_valid(_p):
		return
	_mgr = Game.enemies as EnemyManager
	_mgr.patrol_groups().clear()
	_mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	_p.set_physics_process(false)
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	print("PROBE lane ", _lane(), " spot ", _spot)
	_ops = BlastOps.shared(host.get_tree())
	Game.set_quality(1)
	_p.teleport_to(_spot)
	await TestLib.frames(host, 3)
	await _sweep_enemies()
	await _sweep_hero()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


func _sweep_enemies() -> void:
	TestMode.god = true
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	var base := _spot + _dir() * 24.0
	base.y = _spot.y
	var bad := 0
	var n := 0
	for id: StringName in BlastTable.ids():
		var e := BlastTable.entry(id)
		var r := float(e["radius"])
		var dm: Dictionary = e["dmg"]
		var cone := float(e.get("cone", 0.0))
		var dists := [r * 0.5, r * 0.999, r * 1.5]
		var angs := [0.0, 0.18, -0.18]
		var feet: Array[Drone] = []
		for k in 3:
			var off: Vector3 = _dir().rotated(Vector3.UP, float(angs[k])) * float(dists[k])
			feet.append(_foe(base + off))
		var opts := {"dmg_mult": 1.0, "quiet": true, "final": true, "dir": _dir()}
		var res := BlastTable.apply(id, base, null, opts)
		var line := "PROBE %-16s r=%5.1f cat=%-9s en=%5.0f " % [id, r, e["cat"], float(dm["enemy"])]
		var worst := 0.0
		for k in 3:
			var lost := 1.0e6 - feet[k].hp
			var cov := 1.0
			if bool(e["cover"]):
				cov = Game.blast_cover(base + Vector3(0.0, 0.3, 0.0), feet[k].global_position + Vector3(0.0, 1.0, 0.0))
			var d := feet[k].global_position.distance_to(base)
			var want := BlastTable.damage_at(id, &"enemy", d) * cov
			var tol := maxf(0.6, want * 0.02)
			if absf(lost - want) > tol:
				worst = maxf(worst, absf(lost - want))
				bad += 1
			line += "| %.2fR lost %6.1f want %6.1f " % [dists[k] / r, lost, want]
		n += 1
		if worst > 0.0 or res.is_empty():
			print(line, " MISMATCH worst ", worst)
		else:
			print(line)
		_ops.reset()
		_clear_foes()
		await TestLib.frames(_host, 2)
	print("PROBE enemy sweep: ", n, " entries, mismatches ", bad)


func _sweep_hero() -> void:
	TestMode.god = false
	_p.max_hp = 100.0
	var base := _p.global_position + _dir() * 0.0
	for diff: int in [0, 1, 2]:
		Difficulty.current = diff
		var line := "PROBE hero diff=%d: " % diff
		var worst_loss := 0.0
		var worst_id := &""
		var lethal: Array[String] = []
		for id: StringName in BlastTable.ids():
			var e := BlastTable.entry(id)
			if float((e["dmg"] as Dictionary)["hero"]) <= 0.0:
				continue
			var r := float(e["radius"])
			_p._dead = false
			_p.hp = 100.0
			_p.invuln = 0.0
			var pos := _p.global_position + Vector3(r * 0.2, 0.0, 0.0)
			var before := _p.hp
			BlastTable.apply(id, pos, null, {"quiet": true, "final": true})
			var loss := before - _p.hp
			if loss > worst_loss:
				worst_loss = loss
				worst_id = id
			if _p._dead or _p.hp <= 0.0:
				lethal.append(String(id))
			_ops.reset()
			_p.velocity = Vector3.ZERO
		print(line, "worst loss ", worst_loss, " by ", worst_id, " lethal ", lethal)
		_p._dead = false
		_p.hp = 100.0
	Difficulty.current = Difficulty.EASY
