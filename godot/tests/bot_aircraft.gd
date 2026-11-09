extends RefCounted
## Look-dev bot of the aircraft IN FLIGHT in the real game (real main scene, the game's own chase camera and flight HUD). Phases come from BOT_SHOTS, a ';' list of
##   "kind@x,z,heading,alt,speed,bank,pitch,throttle"
## kind = a roster aircraft, (x, z) = where it is (WORLD metres), heading in radians (0 = north, -1.5708 = east), alt = height above the ground (0 = stands on it), speed = m/s along the nose (planes; a
## helicopter ignores it), bank / pitch = the stick held (-1..1: bank + = right, pitch + = UP) and throttle 0..1 (planes). One picture per phase after the aircraft has flown `every` frames.
##   BOT_SHOTS="jet@880,1255,-1.5708,120,100,0.5,0,1" tools/bot.sh res://tests/bot_aircraft.gd /tmp/out 40 1      (BOT_USER_ARGS="--touch" draws the phone HUD)
const Fixture := preload("res://tests/player_fixture.gd")

var _every := 40
var _count := 1
var _phase := -1
var _setup_done := false
var _shots: PackedStringArray
var _p: Player
var _vm: VehicleManager
var _car: Vehicle
var _bank := 0.0
var _pitch := 0.0
var _thr := 1.0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			if kv[0] == "every":
				_every = maxi(20, int(kv[1]))
			elif kv[0] == "count":
				_count = maxi(1, int(kv[1]))
	_shots = OS.get_environment("BOT_SHOTS").split(";", false)


func _enter(i: int) -> void:
	Fixture.release_inputs()
	if _vm.driven != null:
		_vm.exit_vehicle()
	if is_instance_valid(_car) and _car != _vm.starter:
		_vm._release(_car)
	_car = null
	var e := _shots[i % _shots.size()]
	var kind := StringName(e.split("@")[0])
	var n := e.split("@")[1].split(",")
	var x := float(n[0])
	var z := float(n[1])
	var hd := float(n[2])
	var alt := float(n[3]) if n.size() > 3 else 0.0
	var spd := float(n[4]) if n.size() > 4 else 0.0
	_bank = float(n[5]) if n.size() > 5 else 0.0
	_pitch = float(n[6]) if n.size() > 6 else 0.0
	_thr = float(n[7]) if n.size() > 7 else 1.0
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	Game.state = &"play"
	var city := Game.world as City
	var g := TerrainHeight.height_at(x, z) if (absf(x) > TerrainHeight.CITY_HALF or absf(z) > TerrainHeight.CITY_HALF) else 0.0
	var pos := Vector3(x, g, z)
	_p.teleport_to(pos + Vector3(3.0, 0.5, 0.0))
	if city != null and city.terrain != null:
		city.terrain.settle(pos)
	_car = _vm.spawn_parked(kind, pos, hd)
	if _car == null:
		_vm._release_farthest(pos)
		_car = _vm.spawn_parked(kind, pos, hd)
	if _car == null:
		return
	_car.global_position.y = g + alt
	_vm.enter(_car)
	_car.set_meta(&"hold", true)
	_car.craft.spool = 1.0
	if alt > 1.0:
		_car.craft.airborne = true
		var fwd := _car.forward()
		_car.vel = fwd * spd
		_car.speed = spd
		_car.craft.lever = _thr
		_car.craft.vy = 0.0
	_p.camera_rig.reset_view(hd, -0.15)
	_p.yaw = hd


func _run(_i: int, k: int) -> void:
	if _car == null or not is_instance_valid(_car):
		return
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	Input.action_release(&"jump")
	Input.action_release(&"crouch")
	if _car.cls == &"plane":
		Input.action_press(&"move_forward") if _thr > 0.4 else Input.action_release(&"move_forward")
	if k > 8:
		if _bank > 0.1:
			Input.action_press(&"move_right")
		elif _bank < -0.1:
			Input.action_press(&"move_left")
		if _pitch > 0.1:
			Input.action_press(&"jump")
		elif _pitch < -0.1:
			Input.action_press(&"crouch")


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.vehicles == null or _shots.is_empty():
		return false
	if not _setup_done:
		_setup_done = true
		_p = Game.player as Player
		_vm = Game.vehicles as VehicleManager
		(Game.enemies as EnemyManager).clear()
		if Encounters.current != null:
			Encounters.current.enabled = false
		_p.max_hp = 1.0e6
		_vm.stream_every = 1.0e9
		_vm._stream_t = 1.0e9
		var city := Game.world as City
		if city != null and city.day_night != null:
			city.day_night.frozen = true
			city.day_night.set_hour(float(OS.get_environment("OUT_HOUR")) if OS.get_environment("OUT_HOUR") != "" else 11.0)
	var f: int = Dev.get(&"_frame")
	var slot := (f - 1) / _every
	var k := ((f - 1) % _every) + 1
	if slot != _phase:
		_phase = slot
		_enter(slot)
		print("BOT phase %d %s (frame %d)" % [slot, _shots[slot % _shots.size()], f])
	_run(slot, k)
	if f >= _every * _count:
		Fixture.release_inputs()
		return true
	return false
