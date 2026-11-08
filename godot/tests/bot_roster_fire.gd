extends RefCounted
## Visual bot of the weapon roster: the real game, an open lane with three standing enemies (9, 18 and 32 m) and one in melee reach, and the hero firing each weapon of RF_WEAPONS in turn through the
## input action (the way a thumb does), one PNG per weapon taken while it fires: muzzle flash, tracer or fire spray, the hit, the recoil, the HUD plate. Melee weapons swing at the close one,
## the BLINK PISTOL blinks. Saves <RF_OUT>/<id>_fire.png.
##   RF_OUT=/tmp/x RF_WEAPONS=xbow,flame BOT_RES=1200x540 QUALITY=0 tools/bot.sh res://tests/bot_roster_fire.gd /tmp/x/seq 100000 1

const FIRE_T := 1.0                  ## game seconds each weapon fires
const SHOT_AT := 0.5                 ## the frame is saved this long after the trigger went down

var _setup_done := false
var _p: Player
var _mgr: EnemyManager
var _foes: Array[Drone] = []
var _spot := Vector3.ZERO
var _yaw := 0.0
var _weapons: Array[StringName] = []
var _i := 0
var _t := 0.0
var _saved := false
var _out := ""
var _alt_done := false


func _init() -> void:
	_out = OS.get_environment("RF_OUT")
	var s := OS.get_environment("RF_WEAPONS")
	for n in (s.split(",", false) if s != "" else PackedStringArray()):
		_weapons.append(StringName(n))
	if _weapons.is_empty():
		for id: StringName in [&"magnum", &"mpistol", &"ranger", &"bullpup", &"lmg", &"amr", &"xbow", &"flame", &"stun", &"katana", &"bat", &"qsuper", &"qlink", &"qcollapse", &"qblink", &"qphase", &"qstasis"]:
			_weapons.append(id)


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
			var q := PhysicsRayQueryParameters3D.create(a, a + dir * 40.0, Game.L_WORLD | Game.L_VEHICLE)
			var side := dir.cross(Vector3.UP) * 1.5
			var q2 := PhysicsRayQueryParameters3D.create(a + Vector3(0, -0.5, 0) + side, a + Vector3(0, -0.5, 0) + side + dir * 40.0, Game.L_WORLD | Game.L_VEHICLE)
			if space.intersect_ray(q).is_empty() and space.intersect_ray(q2).is_empty():
				_spot = rp
				_yaw = yaw
				return true
	return false


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_mgr = Game.enemies as EnemyManager
	for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
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
		print("BOTROSTER no open lane found")
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_p.teleport_to(_spot)
	_p.camera_rig.reset_view(_yaw, -0.05)
	var dir := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var types: Array[StringName] = [&"operative", &"operative", &"shield", &"operative"]
	var spots := [[9.0, -1.0], [18.0, 1.6], [32.0, -0.5], [2.3, 0.3]]
	for i in 4:
		var pos: Vector3 = _spot + dir * float(spots[i][0]) + right * float(spots[i][1])
		pos.y = _spot.y
		var d := _mgr.spawn(types[i], pos, false)
		if d != null:
			d.set_physics_process(false)
			d.global_position = pos
			d.max_hp = 1.0e6
			d.hp = 1.0e6
			d.rotation.y = _yaw
			_foes.append(d)
	print("BOTROSTER lane at ", _spot, " yaw ", _yaw, " foes ", _foes.size())


func _begin(id: StringName) -> void:
	Input.action_release(&"fire")
	Input.action_release(&"aim")
	_p.weapon.switch_to(id, true)
	_p.weapon.ammo = _p.weapon.mag
	_p.weapon.reserve = 99
	_p.weapon.fire_t = 0.0
	_t = 0.0
	_saved = false
	_alt_done = false
	_p.teleport_to(_spot)
	_p.camera_rig.reset_view(_yaw, -0.05)


func step(_t_unused: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null:
		return false
	if not _setup_done:
		_setup()
		if _foes.is_empty():
			return true
		_begin(_weapons[0])
	if _i >= _weapons.size():
		return true
	_t += delta
	Game.state = &"play"
	_p.invuln = 5.0
	var id := _weapons[_i]
	var melee := String(WeaponDefs.def(id)["kind"]) == "melee"
	var foe := _foes[3] if melee else _foes[0]
	if is_instance_valid(foe):
		foe.hp = foe.max_hp
		_p.camera_rig.aim_at(foe.global_position + Vector3(0.0, 1.05, 0.0))
	if _t > 0.15:
		Input.action_press(&"fire")
	if id == &"qblink" and _t > 0.2 and not _alt_done:
		_alt_done = true
		_p.weapon.alt_fire(false)
	if not _saved and _t >= SHOT_AT:
		_saved = true
		var img := _p.get_viewport().get_texture().get_image()
		img.save_png("%s/%s_fire.png" % [_out, id])
		print("BOTROSTER ", id, " saved")
	if _t >= FIRE_T:
		_i += 1
		if _i >= _weapons.size():
			Input.action_release(&"fire")
			TestMode.god = false
			return true
		_begin(_weapons[_i])
	return false
