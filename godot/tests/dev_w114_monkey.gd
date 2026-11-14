extends RefCounted
## DEV PROBE of the wave 114 play critic (not a regression test): a monkey plays the real game with ALL 229 weapons: random weapon switches, trigger holds, aiming, reloads, alt-fires, ammo types, melee, throws,
## inspects, jumps, with enemies spawned in front of the hero all the time. Counts script errors, stuck states (a weapon that cannot fire for ever, a reload that never ends) and node growth.
## Prints PROBE lines; the engine's own error lines (SCRIPT ERROR, ERROR) are what to look for in the output. Run: W114_SECONDS=90 tools/test.sh tests/dev_w114_monkey.gd

const TIMEOUT_SECONDS := 140.0
const K := 4

var _p: Player
var _w: PlayerWeapon
var _mgr: EnemyManager
var _rng := RandomNumberGenerator.new()


func _spawn_wave() -> void:
	var fwd := -_p.camera_rig.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var types: Array[StringName] = [&"operative", &"brute", &"operative", &"drone"]
	for i in 3:
		var pos := _p.global_position + fwd.rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5)) * _rng.randf_range(7.0, 22.0)
		pos.y = _p.global_position.y
		var d := _mgr.spawn(types[_rng.randi() % types.size()], pos, true)
		if d != null:
			d.global_position = pos


func run(host: Node) -> void:
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
	_mgr = Game.enemies as EnemyManager
	_mgr.patrol_groups().clear()
	_mgr.clear()
	TestMode.god = true
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	_rng.seed = int(OS.get_environment("W114_SEED")) if OS.get_environment("W114_SEED") != "" else 114
	var secs := float(OS.get_environment("W114_SECONDS")) if OS.get_environment("W114_SECONDS") != "" else 60.0
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	var ids := WeaponDefs.all_ids()
	var held := 0.0
	var next_switch := 0.0
	var next_wave := 0.0
	var t := 0.0
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var worst_frame := 0.0
	var cant_fire := {}
	var shots_by_id := {}
	var last_shots := _w.shots_fired
	var switches := 0
	var actions := {}
	var f := 0
	var t_real0 := Time.get_ticks_msec()
	var stuck_reload := 0.0
	var seen_ids := {}
	while t < secs:
		var t0 := Time.get_ticks_usec()
		await TestLib.frames(host, 1)
		var dt := 1.0 / 60.0                                      # a physics step of game time (the tick rate follows K)
		t += dt * float(K) / float(K)
		f += 1
		worst_frame = maxf(worst_frame, float(Time.get_ticks_usec() - t0) / 1000.0)
		if t >= next_switch:
			next_switch = t + _rng.randf_range(0.6, 1.6)
			var id := ids[_rng.randi() % ids.size()]
			if _w.switch_to(id, _rng.randf() < 0.5):
				switches += 1
				seen_ids[id] = true
				_w.ammo = maxi(_w.ammo, 1) if _rng.randf() < 0.7 else _w.ammo
				if _w.reserve >= 0 and _w.reserve < 6 and _rng.randf() < 0.7:
					_w.reserve = 30
		if t >= next_wave:
			next_wave = t + 5.0
			_spawn_wave()
		# aim at the nearest enemy now and then (the camera finds its target)
		if f % 20 == 0:
			var best: Node3D = null
			var bd := 1.0e9
			for e: Node in host.get_tree().get_nodes_in_group(&"enemy"):
				if e is Node3D and is_instance_valid(e):
					var dd := (e as Node3D).global_position.distance_to(_p.global_position)
					if dd < bd and not PlayerWeapon._is_dead(e):
						bd = dd
						best = e as Node3D
			if best != null:
				_p.camera_rig.look_at_point(best.global_position + Vector3(0.0, 1.2, 0.0))
		var r := _rng.randf()
		if f % 6 == 0:
			if r < 0.35:
				Input.action_press(&"fire")
				actions["fire"] = int(actions.get("fire", 0)) + 1
			elif r < 0.55:
				Input.action_release(&"fire")
			elif r < 0.62:
				Input.action_press(&"reload")
				actions["reload"] = int(actions.get("reload", 0)) + 1
			elif r < 0.68:
				Input.action_release(&"reload")
			elif r < 0.74:
				Input.action_press(&"aim")
			elif r < 0.80:
				Input.action_release(&"aim")
			elif r < 0.84:
				Input.action_press(&"altfire")
				actions["alt"] = int(actions.get("alt", 0)) + 1
			elif r < 0.86:
				Input.action_release(&"altfire")
			elif r < 0.89 and InputMap.has_action(&"melee"):
				Input.action_press(&"melee")
			elif r < 0.91 and InputMap.has_action(&"melee"):
				Input.action_release(&"melee")
			elif r < 0.93 and InputMap.has_action(&"throw_item"):
				Input.action_press(&"throw_item")
			elif r < 0.94 and InputMap.has_action(&"throw_item"):
				Input.action_release(&"throw_item")
			elif r < 0.96 and InputMap.has_action(&"ammo_type"):
				Input.action_press(&"ammo_type")
			elif r < 0.97 and InputMap.has_action(&"ammo_type"):
				Input.action_release(&"ammo_type")
			elif r < 0.98 and InputMap.has_action(&"inspect"):
				Input.action_press(&"inspect")
			elif r < 0.985:
				Input.action_press(&"swap")
			else:
				Input.action_release(&"swap")
				Input.action_release(&"inspect")
				Input.action_release(&"melee")
				Input.action_release(&"throw_item")
				Input.action_release(&"ammo_type")
		# stuck states
		if _w.reload_t > 0.0:
			stuck_reload += dt
			if stuck_reload > 20.0:
				cant_fire["reload never ends: %s" % _w.current] = true
		else:
			stuck_reload = 0.0
		if _w.shots_fired != last_shots:
			shots_by_id[_w.current] = int(shots_by_id.get(_w.current, 0)) + (_w.shots_fired - last_shots)
			last_shots = _w.shots_fired
	for a in [&"fire", &"reload", &"aim", &"altfire", &"melee", &"throw_item", &"ammo_type", &"inspect", &"swap"]:
		if InputMap.has_action(a):
			Input.action_release(a)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	var nodes1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("PROBE monkey %.0f s of play in %.0f s real, %d frames, %d weapon switches over %d different weapons, shots %d, kills credited %s, worst frame %.0f ms" % [secs, (Time.get_ticks_msec() - t_real0) / 1000.0, f, switches, seen_ids.size(), _w.shots_fired, str(actions), worst_frame])
	print("PROBE nodes %d -> %d, stuck states %s, weapons that fired %d" % [nodes0, nodes1, str(cant_fire.keys()), shots_by_id.size()])
	var silent: Array[String] = []
	for id in seen_ids:
		if not shots_by_id.has(id):
			silent.append(String(id))
	print("PROBE equipped but never fired: %d %s" % [silent.size(), ", ".join(silent.slice(0, 40))])
	_mgr.clear()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
	WeaponDefs.hero_mode = false
