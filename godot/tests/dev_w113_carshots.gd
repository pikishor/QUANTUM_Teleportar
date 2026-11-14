extends RefCounted
## DEV PROBE 8: real rounds from five weapon classes into a parked sedan 12 m ahead: rounds to wreck it and the damage stages in order. Run: tools/test.sh tests/dev_w113_carshots.gd
const TIMEOUT_SECONDS := 140.0
const DT := 1.0 / 60.0
var _spot := Vector3.ZERO
var _yaw := 0.0

func _dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))

func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	var p := Game.player as Player
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Game.missions.contracts.enabled = false
	p.max_hp = 1.0e6
	p.hp = 1.0e6
	TestMode.god = true
	p.set_physics_process(false)
	var city := Game.world as City
	city.ambient.set_process(false)
	var vm := Game.vehicles as VehicleManager
	vm.set_physics_process(false)
	# an open lane
	var space := p.get_world_3d().direct_space_state
	var found := false
	for tries in 400:
		var rp: Vector3 = city.random_core_road_point()
		for k in 8:
			var yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var a := rp + Vector3(0, 1.4, 0)
			var q := PhysicsRayQueryParameters3D.create(a, a + dir * 40.0, Game.L_WORLD | Game.L_VEHICLE)
			if space.intersect_ray(q).is_empty():
				_spot = rp
				_yaw = yaw
				found = true
				break
		if found:
			break
	WeaponDefs.hero_mode = true
	var w := p.weapon
	var cfx := DamageWorld.current.cars
	for id: StringName in [&"amr", &"bw_hunter"]:
		if not WeaponDefs.DEFS.has(id):
			print("PROBE no weapon ", id)
			continue
		vm._reset_all()
		var car := vm.spawn_parked(&"sedan", _spot + _dir() * 12.0, _yaw + PI * 0.5)
		await TestLib.frames(host, 3)
		p.teleport_to(_spot)
		p.camera_rig.reset_view(_yaw, -0.03)
		WeaponDefs.unlock(id)
		w.switch_to(id, true)
		w.fire_t = 0.0
		w.swap_t = 0.0
		var stages: Array[String] = []
		var rounds := 0
		var last_state := -1
		var hood0 := cfx.hoods_popped
		var holes0 := cfx.holes_made
		var tyres0 := cfx.tyres_shot
		var shat0 := cfx.shatters
		var t := 0.0
		var out := "PROBE %-8s" % id
		var shots0 := int(w.get("shots_fired")) if w.get("shots_fired") != null else -1
		while t < (6.0 if id == &"amr" else 40.0) and is_instance_valid(car) and not car.dead:
			w.ammo = w.mag
			w.reserve = 999
			p.camera_rig.aim_at(car.global_position + Vector3(0.0, 0.7, 0.0))
			w.tick(DT, true, false, true, false)
			rounds += 1
			await TestLib.frames(host, 1)
			t += DT
			if car.dmg_state != last_state:
				last_state = car.dmg_state
				stages.append("state%d@%.1fs hp%d" % [last_state, t, int(car.hp)])
			if cfx.hoods_popped > hood0 and not stages.has("hood"):
				stages.append("hood")
			if cfx.shatters > shat0 and not stages.has("glass"):
				stages.append("glass")
			if cfx.tyres_shot > tyres0 and not stages.has("tyre"):
				stages.append("tyre")
		out += " wreck after %d trigger frames, %.1f s, hp %d | holes +%d hoods +%d tyres +%d glass +%d | %s" % [rounds, t, int(car.hp) if is_instance_valid(car) else -1, cfx.holes_made - holes0, cfx.hoods_popped - hood0, cfx.tyres_shot - tyres0, cfx.shatters - shat0, ", ".join(stages)]
		print(out)
		print("PROBE debug ", id, " current ", w.current, " ammo ", w.ammo, " mag ", w.mag, " fire_t ", w.fire_t, " reload_t ", w.reload_t, " last_shot target ", w.last_shot.get("target"), " zone ", w.last_shot.get("zone"), " blocked ", w.last_shot.get("blocked"), " dist ", w.last_shot.get("dist"), " shots ", shots0)
	WeaponDefs.hero_mode = false
	vm.set_physics_process(true)
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
