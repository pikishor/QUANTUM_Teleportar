extends RefCounted
## Visual bot for the atmosphere module: shows the fixture street (tests/atmosphere_fixture.gd) with the atmosphere OFF versus ON, at
## the three quality tiers, in light and heavy rain, from several camera poses. One shot per `every` frames:
##   tools/bot.sh res://tests/bot_atmosphere.gd /tmp/atmo 20 14
## Shots (default plan, "pose:mode" pairs):
##   street:off  street:post  street:full  street:heavy  street:med  street:low  low:off  low:full  hero:off  hero:full  lamp:full  speed:full  wide:off  wide:full
## modes: off = post-process and rain hidden (the raw render), post = grade/grain/vignette/CA only, full = everything at HIGH,
##        heavy = full with rain 1.0, med / low = the other quality tiers. The pose `speed` drives the camera down the street at 30 m/s.
## Optional user args (after --):
##   --plan="street:off;street:full"   own plan; poses of the real city (needs scenes/world.tscn) are w_street w_wet w_junction w_third w_crane w_steam
##   --rain=0.75 --wet=0.85            weather of the full shots
##   --keep                            do not remove the other modules from the main scene (default: only atmosphere + the world stay)

const Fixture := preload("res://tests/atmosphere_fixture.gd")
const DEFAULT_PLAN := "street:off;street:post;street:full;street:heavy;street:med;street:low;low:off;low:full;hero:off;hero:full;lamp:full;speed:full;wide:off;wide:full"
## Poses over the real city (same as tests/bot_world.gd): [position, look target, fov]
const WORLD_POSES := {
	&"w_street": [Vector3(-46.0, 1.75, 3.5), Vector3(120.0, 5.0, 2.0), 72.0],
	&"w_wet": [Vector3(-30.0, 0.55, 5.5), Vector3(150.0, 3.0, 0.0), 70.0],
	&"w_junction": [Vector3(-9.5, 1.7, -12.5), Vector3(70.0, 7.0, -70.0), 74.0],
	&"w_third": [Vector3(-38.0, 2.8, 6.0), Vector3(14.0, 1.6, 1.0), 68.0],
	&"w_crane": [Vector3(-150.0, 14.0, 6.0), Vector3(100.0, 8.0, 0.0), 62.0],
	&"w_steam": [Vector3(190.0, 1.8, -2.5), Vector3(207.0, 1.2, -6.4), 56.0],
}

var _args := {}
var _every := 30
var _plan: Array = []
var _frame := 0
var _setup_done := false
var _fixture: Fixture
var _atmosphere: Atmosphere
var _cam: Camera3D
var _rain := 0.75
var _wet := 0.85
var _moving := false
var _applied := -1


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_every = maxi(1, int(_args.get("every", "30")))
	_rain = float(_args.get("rain", "0.75"))
	_wet = float(_args.get("wet", "0.85"))
	for item: String in String(_args.get("plan", DEFAULT_PLAN)).split(";"):
		var kv := item.split(":")
		if kv.size() == 2:
			_plan.append([StringName(kv[0]), kv[1]])


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _setup() -> void:
	_setup_done = true
	var tree := _tree()
	var scene := tree.current_scene
	var needs_world := false
	for entry: Array in _plan:
		if WORLD_POSES.has(entry[0]):
			needs_world = true
	if not _args.has("keep"):
		for c in scene.get_children():
			if c.is_in_group(&"atmosphere") or (needs_world and c is City):
				continue
			scene.remove_child(c)
			c.queue_free()
	for n in tree.get_nodes_in_group(&"atmosphere"):
		_atmosphere = n as Atmosphere
	if _atmosphere == null:
		_atmosphere = (load("res://scenes/atmosphere.tscn") as PackedScene).instantiate() as Atmosphere
		scene.add_child(_atmosphere)
	if needs_world:
		_cam = Camera3D.new()
		_cam.name = "AtmosphereBotCamera"
		_cam.far = 4000.0
		_cam.near = 0.1
		scene.add_child(_cam)
		_cam.make_current()
	else:
		_fixture = Fixture.new()
		_fixture.build(scene)
		_cam = _fixture.camera


func step(_t: float, delta: float) -> bool:
	if not _setup_done:
		_setup()
	_frame += 1
	var idx := (_frame - 1) / _every
	if idx >= _plan.size():
		return true
	if idx != _applied:
		_applied = idx
		_apply(_plan[idx])
	Game.camera = _cam
	if _args.has("verbose") and (_frame % _every == 0):
		print("BOT shot ", idx, " ", _plan[idx], " particles=", _atmosphere.particle_count(), " post=", _atmosphere.post.visible,
				" rain=", snappedf(_atmosphere.rain_now, 0.01), " tier=", _atmosphere.quality)
	if _moving:
		# the "speed" shot: drive down the street so the rain streaks stretch along the relative velocity
		_cam.global_position += Vector3(0.0, 0.0, -30.0) * delta
		if _cam.global_position.z < -85.0:
			_cam.global_position.z = 14.0
	return false


func _set_pose(pose: StringName) -> void:
	_moving = false
	var a: Array
	if WORLD_POSES.has(pose):
		a = WORLD_POSES[pose]
	elif pose == &"speed":
		_moving = true
		a = [Vector3(1.5, 1.6, 12.0), Vector3(1.5, 2.0, -60.0), 66.0]
	else:
		a = Fixture.POSES[pose]
	_cam.fov = a[2]
	_cam.global_position = a[0]
	_cam.look_at(a[1], Vector3.UP)


func _apply(entry: Array) -> void:
	var pose: StringName = entry[0]
	var mode: String = entry[1]
	_set_pose(pose)
	match mode:
		"off":
			_atmosphere.enabled = false
			_atmosphere.rain_enabled = false
			_atmosphere.set_quality(2)
			_atmosphere.set_weather(_rain, _wet, true)
		"post":
			_atmosphere.enabled = true
			_atmosphere.rain_enabled = false
			_atmosphere.set_quality(2)
			_atmosphere.set_weather(_rain, _wet, true)
		"heavy":
			_atmosphere.enabled = true
			_atmosphere.rain_enabled = true
			_atmosphere.set_quality(2)
			_atmosphere.set_weather(1.0, 1.0, true)
		_:
			_atmosphere.enabled = true
			_atmosphere.rain_enabled = true
			_atmosphere.set_quality({"low": 0, "med": 1}.get(mode, 2))
			_atmosphere.set_weather(_rain, _wet, true)
