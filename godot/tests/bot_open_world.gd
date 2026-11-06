extends RefCounted
## Visual bot of the open world freedom wave: a stunt ramp with its landing ring, a traffic hijack (the driver is thrown out), the jump itself, a row of cars, two quantum charges
## and the chain reaction after DETONATE. Look at the frames (the test only counts).
##   BOT_RES=844x390 QUALITY=0 tools/bot.sh res://tests/bot_open_world.gd /tmp/out/ow 3 70
## BOT_PHASE=jobs shows the job markers and the minimap instead (hero in the middle of the core, a car on a taxi marker).

var _p: Player
var _vm: VehicleManager
var _fr: Freedom
var _setup_done := false
var _car: Vehicle
var _row: Array[Vehicle] = []
var _ramp := {}
var _phase := ""


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_vm = Game.vehicles as VehicleManager
	_fr = Freedom.current
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	var m := Game.missions
	if m != null:
		m.contracts.enabled = false
	Game.set_quality(Game.quality)
	_phase = OS.get_environment("BOT_PHASE")
	_ramp = FreedomData.ramp(0)
	var dir: Vector3 = _ramp["dir"]
	if _phase == "jobs":
		var tm := FreedomData.marker_pos(FreedomData.TAXI, 0)
		_p.teleport_to(tm - Vector3(14.0, -0.1, 0.0))
		_p.camera_rig.yaw = -PI * 0.5
		_p.yaw = -PI * 0.5
		return
	if _phase == "boom":
		_p.teleport_to(Vector3(120.0, 0.1, -9.0))
		_p.camera_rig.yaw = -PI * 0.5
		_p.yaw = -PI * 0.5
		return
	_p.teleport_to((_ramp["pos"] as Vector3) - dir * 16.0 + Vector3(0.0, 0.1, 0.0))
	_p.camera_rig.yaw = atan2(-dir.x, -dir.z)
	_p.yaw = _p.camera_rig.yaw


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.vehicles == null or Freedom.current == null:
		return false
	if not _setup_done:
		_setup()
	var f: int = Dev.get(&"_frame")
	Game.state = &"play"
	var dir: Vector3 = _ramp["dir"]
	var heading := atan2(-dir.x, -dir.z)
	if _phase == "jobs":
		if f == 20:
			var tm := FreedomData.marker_pos(FreedomData.TAXI, 0)
			_car = _vm.spawn_parked(&"taxi", tm + Vector3(0.0, 0.0, 1.5), -PI * 0.5)
			_vm.enter(_car)
		return f > 90
	if _phase == "boom":
		if f == 4:
			for i in 3:
				var c := _vm.spawn_parked(&"sedan", Vector3(133.0, 0.0, -9.0 + 3.4 * float(i)), -PI * 0.5)
				if c != null:
					_row.append(c)
		if f == 14 and not _row.is_empty():
			_p.camera_rig.aim_at(_row[1].global_position + Vector3(0.0, 0.8, 0.0))
		if f == 18:
			_fr.charges.place()
		if f == 26:
			_fr.charges.detonate()
		return f > 60
	if f == 6:
		_car = _vm.spawn_traffic(&"taxi", 0, 7, 1, (_ramp["pos"] as Vector3).x - 12.0)
		if _car != null:
			_p.teleport_to(_car.global_position + _car.right() * 3.0)
			_vm.toggle_enter_exit()
	if f == 40 and _car != null:
		_car.global_position = (_ramp["pos"] as Vector3) - dir * 7.0
		_car.heading = heading
		_car.speed = 21.0
		_car.vel = _car.forward() * 21.0
	if f >= 40 and f < 110:
		Input.action_press(&"move_forward")
	if f == 110:
		Input.action_release(&"move_forward")
		_vm.exit_vehicle()
		var base: Vector3 = _ramp["land"]
		base += Vector3(40.0, 0.0, 0.0)
		_p.teleport_to(base + Vector3(-14.0, 0.1, 0.0))
		_p.camera_rig.yaw = -PI * 0.5
		for i in 3:
			var c := _vm.spawn_parked(&"sedan", base + Vector3(2.0, 0.0, 3.2 * float(i) - 3.2), -PI * 0.5)
			if c != null:
				_row.append(c)
	if f == 124 and not _row.is_empty():
		_p.camera_rig.aim_at(_row[1].global_position + Vector3(0.0, 0.8, 0.0))
	if f == 130:
		_fr.charges.place()
	if f == 140:
		_fr.charges.detonate()
	if f > 190:
		return true
	return false
