extends RefCounted
## Visual drive bot of the car model on the real city (real main scene, phone camera): parked car, acceleration, cornering, handbrake drift, a glancing wall hit, a head-on
## crash, a car-to-car crash, then the damaged car (smoke, fire). Pictures at fixed game times (the game runs in slow motion so a software frame is about 20-30 ms of game time).
##   BOT_OUT=/tmp/vr/run tools/vehicle_bot.sh [phases]     (writes BOT_OUT_<nn>_<name>.png)
## BOT_SET=drive|crash|damage picks the sequence (default all).

const Fixture := preload("res://tests/player_fixture.gd")
const TIME_SCALE := 0.3

var _t := 0.0
var _setup_done := false
var _p: Player
var _vm: VehicleManager
var _em: EnemyManager
var _car: Vehicle
var _out := ""
var _events: Array = []         ## [time, name, snap?]
var _next := 0
var _snap_busy := false
var _snaps := 0
var _held := {}
var _set := "all"
var _log: Array[String] = []
var _cam := ""                  ## scripted beauty camera round the car (front3q | side | rear3q | hood), "" = the game camera


## The scripted camera: a pose round the car, refreshed every frame while set.
func _cam_pose() -> void:
	if _cam == "" or _p == null or _car == null:
		return
	var c := _car.global_position
	var f := _car.forward()
	var r := _car.right()
	var pos := c
	var fov := 62.0
	match _cam:
		"front3q": pos = c + f * 5.2 - r * 3.6 + Vector3(0.0, 1.5, 0.0)
		"rear3q": pos = c - f * 5.6 + r * 3.2 + Vector3(0.0, 1.6, 0.0)
		"side": pos = c - r * 6.5 + Vector3(0.0, 1.2, 0.0)
		"low_front": pos = c + f * 4.4 + r * 1.2 + Vector3(0.0, 0.7, 0.0)
	var target := c + Vector3(0.0, 0.7, 0.0)
	var xf := Transform3D(Basis.looking_at((target - pos).normalized(), Vector3.UP), pos)
	_p.camera_rig.cine_set(xf, fov)


func _init() -> void:
	_out = OS.get_environment("BOT_OUT") if OS.get_environment("BOT_OUT") != "" else "/tmp/vr/run"
	_set = OS.get_environment("BOT_SET") if OS.get_environment("BOT_SET") != "" else "all"


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	_vm = Game.vehicles as VehicleManager
	_em = Game.enemies as EnemyManager
	Engine.time_scale = TIME_SCALE
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	_em.patrol_groups().clear()
	_em.clear()
	_vm.stream_every = 1.0e9
	_vm._stream_t = 1.0e9
	for v in _vm.list.duplicate():
		if v != _vm.starter:
			_vm._release(v)
	_car = _vm.starter
	Game.heat = 0.0
	if _set in ["all", "drive"]:
		_events += [[0.8, "park", true], [1.0, "enter"], [1.4, "go"], [3.2, "accel1", true], [5.2, "accel2", true], [5.4, "right"], [6.6, "corner", true], [6.9, "drift"], [7.6, "drift1", true],
			[8.3, "drift2", true], [8.6, "straight"], [10.0, "end_drive"]]
	if _set == "cam2":
		_events += [[0.3, "enter"], [0.5, "go"], [2.2, "chase", true], [2.3, "view"], [3.4, "far", true], [3.5, "view"], [4.6, "hood", true], [5.0, "done"]]
	if _set == "cam":
		_events += [[0.3, "enter"], [0.5, "go"], [3.0, "chase", true], [3.1, "view"], [4.4, "far", true], [4.5, "view"], [5.8, "hood", true], [5.9, "view"], [7.0, "back_on"], [8.3, "back", true],
			[8.4, "back_off"], [8.6, "right"], [9.2, "turn", true], [9.3, "drift"], [10.0, "drift_cam", true], [10.4, "straight"], [10.5, "end_drive"], [11.5, "done"]]
	if _set in ["all", "crash"]:
		var t0 := 0.0 if _set == "crash" else 11.0
		_events += [[t0 + 0.2, "glance_setup"], [t0 + 1.8, "glance", true], [t0 + 2.6, "glance_after", true], [t0 + 3.0, "headon_setup"], [t0 + 4.6, "headon_pre", true], [t0 + 5.1, "headon", true],
			[t0 + 5.7, "headon_after", true], [t0 + 7.0, "cars_setup"], [t0 + 8.6, "cars_pre", true], [t0 + 9.1, "cars", true], [t0 + 9.8, "cars_after", true]]
	if _set in ["all", "damage"]:
		var t1 := 0.0 if _set == "damage" else 22.0
		_events += [[t1 + 0.2, "dmg_setup"], [t1 + 1.5, "dmg40", true], [t1 + 2.0, "dmg70_set"], [t1 + 3.5, "dmg70", true], [t1 + 4.0, "dmg90_set"], [t1 + 5.5, "dmg90", true], [t1 + 9.0, "done"]]
	_events.append([0.0, "cam_off"])
	_events.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))


func _hold(a: StringName, on: bool) -> void:
	if on and not _held.get(a, false):
		Input.action_press(a)
		_held[a] = true
	elif not on and _held.get(a, false):
		Input.action_release(a)
		_held[a] = false


func _reset_player(pos: Vector3, yaw: float) -> void:
	Fixture.release_inputs()
	Game.state = &"play"
	if _vm.driven != null:
		_vm.exit_vehicle()
	_p.invuln = 0.0
	_p.teleport_to(pos)
	_p.camera_rig.reset_view(yaw, -0.12)
	_p.yaw = yaw


func _place(pos: Vector3, heading: float, speed := 0.0) -> void:
	_car.global_position = Vector3(pos.x, 0.0, pos.z)
	_car.heading = heading
	_car.rotation = Vector3(0.0, heading, 0.0)
	_car._heading_set = heading
	_car.speed = speed
	_car.vel = _car.forward() * speed
	_car.yaw_rate = 0.0
	_car.visual.repair()
	_car.hp = _car.max_hp
	_car.dmg_state = 0
	_car._warned = 0


func _event(name: String) -> void:
	match name:
		"cam_off":
			_cam = ""
		"park":
			_reset_player(_car.global_position + Vector3(-5.5, 0.0, 2.2), -PI * 0.5 + 0.55)
			_cam = "front3q"
		"enter":
			_cam = ""
			if _set != "all" or _t > 0.5:
				_place(Vector3(-330.0, 0.0, 5.0), -PI * 0.5, 0.0)       # a long straight lane: no wall for 600 m
			_reset_player(_car.global_position + Vector3(0.0, 0.0, -3.0), 0.0)
			_vm.enter(_car)
			_p.camera_rig.reset_view(_car.heading, -0.15)
		"go":
			_hold(&"move_forward", true)
		"right":
			_hold(&"move_right", true)
		"view":
			_p.camera_rig.cycle_vehicle_view()
		"back_on":
			_hold(&"look_back", true)
		"back_off":
			_hold(&"look_back", false)
		"drift":
			_hold(&"move_right", false)
			_hold(&"move_left", true)
			_hold(&"jump", true)
		"straight":
			_hold(&"move_left", false)
			_hold(&"jump", false)
		"end_drive":
			_hold(&"move_forward", false)
		"glance_setup":
			Fixture.release_inputs()
			_held.clear()
			_vm.exit_vehicle()
			_place(Vector3(-60.0, 0.0, 0.0), -PI * 0.5 - 0.42, 22.0)
			_vm.enter(_car)
			_car.vel = _car.forward() * 22.0
			_car.speed = 22.0
			_p.camera_rig.reset_view(_car.heading, -0.15)
			_hold(&"move_forward", true)
		"glance_after":
			_hold(&"move_forward", false)
		"headon_setup":
			Fixture.release_inputs()
			_held.clear()
			_place(Vector3(-60.0, 0.0, 0.0), PI, 24.0)           # facing +Z, the building front across the avenue
			_car.vel = _car.forward() * 24.0
			_p.camera_rig.reset_view(_car.heading, -0.15)
			_hold(&"move_forward", true)
		"headon_after":
			_hold(&"move_forward", false)
		"cars_setup":
			Fixture.release_inputs()
			_held.clear()
			_place(Vector3(-110.0, 0.0, 0.0), -PI * 0.5, 22.0)
			_vm.stream_every = 1.0e9
			var o := _vm.spawn_parked(&"suv", Vector3(-86.0, 0.0, 1.0), -PI * 0.5 + 0.2)
			if o != null:
				o.update_lod(0.0)
			_car.vel = _car.forward() * 22.0
			_p.camera_rig.reset_view(_car.heading, -0.15)
			_hold(&"move_forward", true)
		"cars_after":
			_hold(&"move_forward", false)
		"dmg_setup":
			Fixture.release_inputs()
			_held.clear()
			if _vm.driven != null:
				_vm.exit_vehicle()
			_place(Vector3(-70.0, 0.0, -9.0), -PI * 0.5 + 0.2, 0.0)
			var hp_ := _car.global_position + Vector3(-5.2, 0.0, -2.6)
			_reset_player(hp_, PlayerUtil.yaw_of(_car.global_position - hp_))
			_car.debug_damage(0.42)
			_cam = "front3q"
		"dmg70_set":
			_car.debug_damage(0.7)
			_cam = "rear3q"
		"dmg90_set":
			_car.debug_damage(0.88)
			_cam = "low_front"
	_log.append("%.1f %s speed %.1f hp %.0f/%.0f gear %d rpm %.2f crashes %d impact %.1f view %d cam %.1f m behind %.1f up, arm %.1f fov %.0f" % [_t, name, _car.speed, _car.hp, _car.max_hp, _car.gear, _car.rpm, _car.crashes, _car.last_impact, _p.camera_rig.veh_view, (_p.camera_rig.camera.global_position - _car.global_position).dot(-_car.forward()), _p.camera_rig.camera.global_position.y, _p.camera_rig._veh_dist_now, _p.camera_rig.camera.fov])


func _snap(name: String) -> void:
	if _snap_busy:
		return
	_snap_busy = true
	await RenderingServer.frame_post_draw
	var img := Game.get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		var path := "%s_%02d_%s.png" % [_out, _snaps, name]
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		img.save_png(path)
		_snaps += 1
	_snap_busy = false


func step(_tt: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.vehicles == null:
		return false
	if not _setup_done:
		_setup()
	_t += delta
	_cam_pose()
	while _next < _events.size() and _t >= float(_events[_next][0]):
		var ev: Array = _events[_next]
		_next += 1
		_event(String(ev[1]))
		if ev.size() > 2:
			_snap(String(ev[1]))
	if _next > 0 and (_next >= _events.size() or String(_events[_next - 1][1]) == "done"):
		if not _snap_busy:
			Fixture.release_inputs()
			for l in _log:
				print("VBOT ", l)
			return true
	return false
