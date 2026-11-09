extends RefCounted
## Visual bot of the wave-108 weapons (ENERGY family and BLAST heavies, copy of bot_roster_fire.gd with per-weapon timing for slow projectiles and the orbital strike): the real game, an open lane with three standing enemies (9, 18 and 32 m) and one in melee reach, and the hero firing each weapon of RF_WEAPONS in turn through the
## input action (the way a thumb does), one PNG per weapon taken while it fires: muzzle flash, tracer or fire spray, the hit, the recoil, the HUD plate. Melee weapons swing at the close one,
## the BLINK PISTOL blinks. Saves <RF_OUT>/<id>_fire.png.
##   RF_OUT=/tmp/x RF_WEAPONS=epod,orbital BOT_RES=1200x540 QUALITY=0 ENGINE_ARGS="--fixed-fps 12" tools/bot.sh res://tests/bot_energy_fire.gd /tmp/x/seq 100000 1
## RF_ALT=1 presses the second fire mode instead of the trigger (the alt-fire of each weapon).

const FIRE_T := 1.0                  ## game seconds each weapon fires (SLOW lists the weapons that need longer)
const SHOT_AT := 0.5                 ## the frame is saved this long after the trigger went down
## id -> [shot at, total time]: projectiles need their flight, the orbital strike its delay, the napalm field a moment to burn, the singularity its well
const SLOW := {&"epod": [0.95, 1.6], &"cmissile": [1.15, 1.8], &"napalm": [1.5, 2.2], &"sing": [2.9, 3.4], &"orbital": [3.3, 4.2], &"seeker": [1.3, 1.9], &"emaul": [0.55, 1.2], &"ebeam": [1.9, 2.4], &"railgun": [1.7, 2.3]}

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
		for id: StringName in [&"eplasma", &"erepeat", &"espike", &"ebeam", &"eblade", &"emaul", &"epod", &"railgun", &"chaingun", &"cmissile", &"napalm", &"sing", &"orbital", &"seeker", &"tknife"]:
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
	var timing: Array = SLOW.get(id, [SHOT_AT, FIRE_T])
	var alt := OS.get_environment("RF_ALT") == "1"
	if alt:
		if _t > 0.15 and not _alt_done:
			_alt_done = true
			_p.weapon.alt_fire(false)
	elif String(WeaponDefs.def(id)["kind"]) == "charge":                                   # the beam rifle and the railgun charge while the trigger is held, then fire on release
		if _t > 0.15 and _t < 1.55:
			Input.action_press(&"fire")
		else:
			Input.action_release(&"fire")
	elif _t > 0.15 and (_t < 0.4 or not SLOW.has(id)):
		Input.action_press(&"fire")
	elif SLOW.has(id):
		Input.action_release(&"fire")
	if not _saved and _t >= float(timing[0]):
		_saved = true
		var img := _p.get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [_out, id, "alt" if alt else "fire"])
		print("BOTROSTER ", id, " saved")
	if _t >= float(timing[1]):
		_i += 1
		if _i >= _weapons.size():
			Input.action_release(&"fire")
			TestMode.god = false
			return true
		_begin(_weapons[_i])
	return false
