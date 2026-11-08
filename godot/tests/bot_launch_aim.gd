extends RefCounted
## Visual bot: the launcher aim indicator (landing ring as wide as the blast, dotted arc, LOCK bracket) in the real game. 0-1.5 s the rocket launcher aimed at the street (ring and arc), 1.5-3 s
## on the middle enemy (lock bracket), 3-4 s the shot, 4-6 s the singularity grenade held aimed. Frames show the indicators and the blast.
##   BOT_RES=2400x1080 QUALITY=0 tools/bot.sh res://tests/bot_launch_aim.gd /tmp/out/l 14 8

var _setup_done := false
var _p: Player
var _mgr: EnemyManager
var _t := 0.0
var _foes: Array[Drone] = []
var _spot := Vector3.ZERO
var _yaw := 0.0
var _phase := -1


func _lane() -> bool:
	var city := Game.world as City
	if city == null:
		return false
	var want := int(OS.get_environment("BOT_LANE")) if OS.get_environment("BOT_LANE") != "" else 0
	var found := 0
	var space := _p.get_world_3d().direct_space_state
	for tries in 400:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for k in 8:
			var yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var a := rp + Vector3(0, 1.5, 0)
			var q := PhysicsRayQueryParameters3D.create(a, a + dir * 40.0, Game.L_WORLD | Game.L_VEHICLE)
			var q2 := PhysicsRayQueryParameters3D.create(a + Vector3(0, -0.5, 0) + dir.cross(Vector3.UP) * 1.5, a + Vector3(0, -0.5, 0) + dir.cross(Vector3.UP) * 1.5 + dir * 40.0, Game.L_WORLD | Game.L_VEHICLE)
			if space.intersect_ray(q).is_empty() and space.intersect_ray(q2).is_empty():
				if found == want:
					_spot = rp
					_yaw = yaw
					return true
				found += 1
				break
	return false


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_mgr = Game.enemies as EnemyManager
	if OS.get_environment("BOT_TOUCH") == "1":                              # the phone layout: touch buttons, no key hints
		var hud := Game.get_tree().root.find_child("Hud", true, false) as Hud
		if hud != null:
			hud.touch.controls_on = true
			hud.touch.set_process(true)
	_mgr.patrol_groups().clear()
	_mgr.clear()
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	TestMode.god = true
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	if not _lane():
		print("BOTSHOOT no open lane found")
		return
	_p.teleport_to(_spot)
	_p.camera_rig.reset_view(_yaw, -0.05)
	var dir := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var types: Array[StringName] = [&"operative", &"operative", &"shield"]
	var spots := [[7.0, -1.2], [16.0, 1.6], [30.0, -0.5]]
	for i in 3:
		var pos: Vector3 = _spot + dir * float(spots[i][0]) + right * float(spots[i][1])
		pos.y = _spot.y
		var d := _mgr.spawn(types[i], pos, false)
		if d != null:
			d.set_physics_process(false)
			d.global_position = pos
			d.max_hp = 1.0e6
			d.hp = 1.0e6
			d.rotation.y = _yaw                                            # facing away from the hero is the default look, turn them towards him
			_foes.append(d)
	print("BOTSHOOT lane at ", _spot, " yaw ", _yaw, " foes ", _foes.size())


func _aim(i: int, y: float) -> void:
	if i < _foes.size() and is_instance_valid(_foes[i]):
		_p.camera_rig.aim_at(_foes[i].global_position + Vector3(0.0, y, 0.0))


func _weapon(id: StringName) -> void:
	if _p.weapon.current != id:
		_p.weapon.switch_to(id, true)
		_p.weapon.ammo = _p.weapon.mag
		_p.weapon.reserve = 99


func step(_t_unused: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	if not _setup_done:
		_setup()
	if _foes.is_empty():
		return _t > 3.0
	_t += delta
	Game.state = &"play"
	_p.invuln = 5.0
	var ph := 0
	if _t < 1.5:
		ph = 0
	elif _t < 3.0:
		ph = 1
	elif _t < 4.0:
		ph = 2
	else:
		ph = 3
	if ph != _phase:
		_phase = ph
		_weapon(&"rocket" if ph < 3 else &"grenade")
	var dir := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	match ph:
		0:
			_p.camera_rig.aim_at(_spot + dir * 20.0 + Vector3(2.5, 0.0, 0.0))
		1:
			_aim(1, 1.1)
		2:
			_aim(1, 1.1)
			Input.action_press(&"fire") if fmod(_t, 2.0) < 0.2 else Input.action_release(&"fire")
		3:
			_p.camera_rig.aim_at(_spot + dir * 22.0 + Vector3(-1.5, 0.0, 0.0))
	if _t > 6.5:
		Input.action_release(&"fire")
		TestMode.god = false
		return true
	return false
