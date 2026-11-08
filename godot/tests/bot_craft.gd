extends RefCounted
## Visual bot of the roster vehicles in the real city (real main scene). Phases come from BOT_SHOTS, a ';' list of "kind@x,z,yaw,alt,dist" entries (kind = a roster kind to spawn and enter, or "foot"
## to stand there, or "drive:kind" to fly or drive it forward for a few seconds); the camera is the game's own. One picture per phase.
##   BOT_SHOTS="heli@0,40,0,0;foot@0,1050,3.14,0" tools/bot.sh res://tests/bot_craft.gd /tmp/out 40 2
const Fixture := preload("res://tests/player_fixture.gd")

var _every := 40
var _count := 2
var _phase := -1
var _setup_done := false
var _shots: PackedStringArray
var _p: Player
var _vm: VehicleManager
var _car: Vehicle


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1:
			if kv[0] == "every":
				_every = maxi(30, int(kv[1]))
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
	var head := e.split("@")[0]
	var nums := e.split("@")[1].split(",")
	var pos := Vector3(float(nums[0]), float(nums[3]) if nums.size() > 3 else 0.0, float(nums[1]))
	var yaw := float(nums[2])
	_p.invuln = 0.0
	_p.hp = _p.max_hp
	Game.state = &"play"
	if head == "foot":
		_p.teleport_to(pos)
		_p.camera_rig.reset_view(yaw, -0.1)
		_p.yaw = yaw
		return
	if head.begins_with("park:"):                                # the vehicle stands there, the hero looks at it from 9 m
		var pk := StringName(head.trim_prefix("park:"))
		_car = _vm.spawn_parked(pk, Vector3(pos.x, 0.0, pos.z), yaw)
		if _car == null:
			_vm._release_farthest(pos)
			_car = _vm.spawn_parked(pk, Vector3(pos.x, 0.0, pos.z), yaw)
		_car.global_position.y = _car.base_y + pos.y
		_p.teleport_to(Vector3(pos.x + 9.0, 0.1, pos.z + 3.0))
		_p.camera_rig.reset_view(PI * 0.5 - 0.3, -0.12)
		_p.yaw = PI * 0.5 - 0.3
		return
	var kind := StringName(head.trim_prefix("drive:"))
	_p.teleport_to(Vector3(pos.x, 0.0, pos.z + 3.0))
	_car = _vm.spawn_parked(kind, Vector3(pos.x, 0.0, pos.z), yaw)
	if _car == null:
		_vm._release_farthest(pos)
		_car = _vm.spawn_parked(kind, Vector3(pos.x, 0.0, pos.z), yaw)
	if _car != null:
		_car.global_position.y = pos.y
		_vm.enter(_car)
		_p.camera_rig.reset_view(yaw, -0.15)
		_p.yaw = yaw


func _run(i: int, k: int) -> void:
	var head := _shots[i % _shots.size()].split("@")[0]
	if head.begins_with("drive:") and _car != null:
		Input.action_press(&"move_forward")
		var air := _car.cls == &"heli" or _car.cls == &"plane"
		if k > 6 and air and k < 40:
			Input.action_press(&"jump")
		if k > 40:
			Input.action_release(&"jump")
		if k > 50:
			Input.action_press(&"move_right")
		if k > 56:
			Input.action_release(&"move_right")


func step(_t: float, _delta: float) -> bool:
	if Game.player == null or Game.vehicles == null or _shots.is_empty():
		return false
	if not _setup_done:
		_setup_done = true
		_p = Game.player as Player
		_vm = Game.vehicles as VehicleManager
		(Game.enemies as EnemyManager).clear()
		_p.max_hp = 1.0e6
		_vm.stream_every = 1.0e9
		_vm._stream_t = 1.0e9
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
