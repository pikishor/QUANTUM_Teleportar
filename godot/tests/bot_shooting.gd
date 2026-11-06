extends RefCounted
## Visual bot of the shooting-accuracy wave: the real game, three standing enemies down an open lane (7, 16 and 30 m), and a scripted player who aims at them the way a thumb would
## (the crosshair is on the target, the weapon fires through the input action) so the frames show the whole fire path: the crosshair and its cone, the target brackets, the hit marker,
## tracers, the muzzle, recoil and the view settling. Phases (frames at 60 per second of game time): aim at the near one, a burst pistol burst, a carbine hold, an aimed carbine head
## shot, the scatter, a long SMG burst at the far one.
##   BOT_RES=1200x540 QUALITY=0 tools/bot.sh res://tests/bot_shooting.gd /tmp/out/s 6 28
## BOT_LANE=n picks the n-th open lane found (a different street), BOT_FREEZE=1 keeps the enemies still (default: still).

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
	# phases by game time
	var ph := 0
	if _t < 1.2:
		ph = 0                       # aim at the near one with the carbine: brackets and the red cone
	elif _t < 2.4:
		ph = 1                       # burst pistol bursts at the near one
	elif _t < 3.6:
		ph = 2                       # carbine hold at the middle one
	elif _t < 4.8:
		ph = 3                       # aimed head shot
	elif _t < 6.0:
		ph = 4                       # scatter at the near one
	else:
		ph = 5                       # long SMG burst at the far shield trooper
	if ph != _phase:
		_phase = ph
		Input.action_release(&"fire")
		Input.action_release(&"aim")
		match ph:
			0:
				_weapon(&"carbine")
			1:
				_weapon(&"burst")
			2:
				_weapon(&"carbine")
			3:
				_weapon(&"carbine")
				Input.action_press(&"aim")
			4:
				_weapon(&"scatter")
			5:
				_weapon(&"flux")
	match ph:
		0:
			_aim(0, 1.1)
		1:
			_aim(0, 1.15)
			Input.action_press(&"fire") if fmod(_t, 0.55) < 0.12 else Input.action_release(&"fire")
		2:
			_aim(1, 1.15)
			Input.action_press(&"fire")
		3:
			_aim(1, 1.62)
			Input.action_press(&"fire") if fmod(_t, 0.5) < 0.1 else Input.action_release(&"fire")
		4:
			_aim(0, 1.0)
			Input.action_press(&"fire") if fmod(_t, 0.9) < 0.1 else Input.action_release(&"fire")
		5:
			_aim(2, 1.1)
			Input.action_press(&"fire")
	if _t > 8.0:
		Input.action_release(&"fire")
		Input.action_release(&"aim")
		TestMode.god = false
		return true
	return false
