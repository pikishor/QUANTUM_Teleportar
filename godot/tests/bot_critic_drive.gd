extends RefCounted
## Look-dev bot of the wave 112 LOOK critic: the first minute of driving OUT of the city in the real game (real camera, real HUD, real traffic and streaming), the starter car on autopilot
## (pure pursuit along a highway of TerrainRoads, the safe-distance rule of the traffic audit). Pictures every EVERY frames; with ENGINE_ARGS="--fixed-fps 10" one frame is 0.1 s of game time.
##   ENGINE_ARGS="--fixed-fps 10" BOT_USER_ARGS="--touch" QUALITY=0 tools/bot.sh res://tests/bot_critic_drive.gd /tmp/out 60 8
## env: CRIT_ROAD  index of the road (TerrainRoads: 0 PASS ROAD, 1 DESERT ROAD, 2 COAST ROAD, 3 FOREST ROAD ...), default 1
##      CRIT_S0    metres from the start of the road where the car starts, default 0 (the city gate)
##      CRIT_SPEED cruise speed in m/s, default 22
##      CRIT_HOUR  hour of the day (default 12), CRIT_WEATHER clear | rain | ... (default clear)
const Audit := preload("res://tests/traffic_audit.gd")

var _f := 0
var _p: Player
var _vm: VehicleManager
var _car: Vehicle
var _pilot: RefCounted
var _log_t := 0.0
var _worst := 0.0                     ## the longest script frame (TIME_PROCESS + TIME_PHYSICS_PROCESS, ms) since the last log line: streaming and wake spikes, not GPU time
var _spikes := 0


func step(_t: float, d: float) -> bool:
	_p = Game.player as Player
	if _p == null:
		return false
	_f += 1
	if _f == 2:
		_setup()
	elif _f > 2 and _pilot != null:
		if not Game.is_playing():
			Game.state = &"play"
		_p.hp = _p.max_hp
		if is_instance_valid(_car) and _car.hp < _car.max_hp * 0.5:
			_car.hp = _car.max_hp
		_pilot.step(d)
		_log_t += d
		var ms := (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		_worst = maxf(_worst, ms)
		if ms > 45.0:
			_spikes += 1
			print("CRITDRIVE SPIKE %.0f ms at (%.0f, %.0f) speed %.1f" % [ms, _car.global_position.x, _car.global_position.z, _car.speed])
		if _log_t >= 5.0:
			_log_t = 0.0
			print("CRITDRIVE car (%.0f, %.0f) speed %.1f road %s worst script frame %.0f ms spikes>45ms %d draws %d" % [_car.global_position.x, _car.global_position.z, _car.speed,
					TerrainRoads.name_at(_car.global_position.x, _car.global_position.z, 14.0), _worst, _spikes, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
			_worst = 0.0
	return false


func _setup() -> void:
	Game.state = &"play"
	_vm = Game.vehicles as VehicleManager
	_p.max_hp = 1.0e6
	_p.hp = _p.max_hp
	if Game.enemies != null:
		(Game.enemies as EnemyManager).clear()
		(Game.enemies as EnemyManager).patrol_groups().clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	var city := Game.world as City
	var hour := float(OS.get_environment("CRIT_HOUR")) if OS.get_environment("CRIT_HOUR") != "" else 12.0
	if city != null and city.day_night != null:
		city.day_night.frozen = true
		city.day_night.set_hour(hour)
	for n in Game.get_tree().root.find_children("*", "Weather", true, false):
		var wx := OS.get_environment("CRIT_WEATHER")
		(n as Weather).set_state(StringName(wx) if wx != "" else &"clear", true)
	var ri := int(OS.get_environment("CRIT_ROAD")) if OS.get_environment("CRIT_ROAD") != "" else 1
	var s0 := float(OS.get_environment("CRIT_S0")) if OS.get_environment("CRIT_S0") != "" else 0.0
	var speed := float(OS.get_environment("CRIT_SPEED")) if OS.get_environment("CRIT_SPEED") != "" else 22.0
	var route: PackedVector2Array = Audit.road_route(ri, s0, 6000.0, true)
	if route.size() < 4:
		push_error("CRITDRIVE: no route")
		return
	_car = _vm.starter
	if _car == null:
		_car = _vm.spawn_parked(&"sedan", Vector3(route[0].x, 0.0, route[0].y), 0.0)
	var start := route[0]
	var dir := route[1] - route[0]
	var gy := TerrainHeight.drive_height_at(start.x, start.y, 0.0) if (absf(start.x) > TerrainHeight.CITY_HALF or absf(start.y) > TerrainHeight.CITY_HALF) else 0.0
	_car.global_position = Vector3(start.x, gy, start.y)
	_car.heading = atan2(-dir.x, -dir.y)
	_car.rotation = Vector3(0.0, _car.heading, 0.0)
	_car._heading_set = _car.heading
	_car.speed = 0.0
	_car.vel = Vector3.ZERO
	_p.teleport_to(_car.global_position + Vector3(0.0, 1.0, 0.0))
	_vm.enter(_car)
	var pilot = Audit.Pilot.new()
	pilot.start(_car, route, speed)
	pilot.loop = false
	_pilot = pilot
	print("CRITDRIVE start road %d at (%.0f, %.0f) heading %.2f cruise %.0f" % [ri, start.x, start.y, _car.heading, speed])
