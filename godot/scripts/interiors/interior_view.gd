extends Node3D
## Visual twin of the interior tests: builds one generated interior with the city's tonemap and bloom and flies a camera through a set of poses, one per screenshot.
##   godot ... res://scenes/interiors/interior_view.tscn -- --interior=club --seed=3 --quality=1 [--hero] [--shot-seq=PREFIX --every=8 --count=6]
## Poses (free camera): 0 from the door, 1 high corner, 2 back wall, 3 through the first inner door, 4 inside the second room, 5 dollhouse view from above.
## With --hero the real Player (camera rig, body, weapon) stands at six spots (door, middle, vendor, cover, flush against a wall, in a doorway) so the third-person camera can be judged.
## tools/interior_shots.sh wraps this. Nothing here ships in the game.

const ORIGIN := Vector3(900.0, 600.0, 900.0)

var interior: Interior
var cam: Camera3D
var hero: Node3D
var _args := {}
var _frame := 0
var _every := 8
var _poses: Array = []
var _last_pose := -1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_every = maxi(1, int(_args.get("every", "8")))
	Game.autostart = true
	if _args.has("quality"):
		Game.quality = clampi(int(_args["quality"]), 0, 2)
	_environment()
	interior = InteriorGen.build(StringName(_args.get("interior", "club")), int(_args.get("seed", "1")), ORIGIN, Game.quality) as Interior
	add_child(interior)
	if _args.has("hero"):
		Game.state = &"play"
		var ps := load("res://scenes/player.tscn") as PackedScene
		hero = ps.instantiate() as Node3D
		add_child(hero)
		cam = null
	else:
		cam = Camera3D.new()
		cam.fov = 78.0
		cam.far = 400.0
		add_child(cam)
		cam.make_current()
	_build_poses()
	_apply(0)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.25, 0.35)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 12.0
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":      # the city's Compatibility lift (CityEnv.COMPAT_*): the game's WorldEnvironment applies it inside interiors too
		env.tonemap_exposure = preload("res://scripts/world/city_env.gd").COMPAT_EXPOSURE
		env.glow_strength = preload("res://scripts/world/city_env.gd").COMPAT_GLOW_STRENGTH
	var levels := [0.35, 0.55, 0.8, 0.65, 0.4, 0.2, 0.0]
	for i in levels.size():
		env.set_glow_level(i, levels[i])
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# the city's moon, to prove the interior shader ignores it
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.58, 0.72, 1.0)
	sun.light_energy = 0.9
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)


func _build_poses() -> void:
	var p := interior.plan
	var o := ORIGIN
	var r0: Rect2 = p.rooms[0]["rect"]
	var h0: float = p.rooms[0]["h"]
	var c0 := r0.get_center()
	var entry := o + p.entry
	_poses.clear()
	if hero != null:
		var spots: Array = [[entry, 0.0], [o + Vector3(c0.x, 0.0, c0.y), PI * 0.5], [o + Vector3(r0.position.x + 0.5, 0.0, c0.y), PI * 0.5], [o + Vector3(c0.x, 0.0, r0.position.y + 0.5), PI],
			[o + Vector3(c0.x + 1.0, 0.0, r0.end.y - 0.45), 0.0], [o + Vector3(r0.end.x - 0.5, 0.0, c0.y - 1.0), -PI * 0.5]]
		var vend: Array = interior.anchors(&"vendor")
		if not vend.is_empty():
			spots[2] = [(vend[0]["pos"] as Vector3) + Vector3(0, 0, 0.0), float(vend[0]["yaw"])]
		var cov: Array = interior.anchors(&"cover")
		if not cov.is_empty():
			spots[3] = [(cov[0]["pos"] as Vector3), float(cov[0]["yaw"])]
		if p.doors.size() > 1:
			var dd: Dictionary = p.doors[1]
			var line := float(dd["line"])
			var c := float(dd["c"])
			spots[5] = [o + (Vector3(c, 0.0, line) if int(dd["axis"]) == 0 else Vector3(line, 0.0, c)), PI]
		_poses = spots
		return
	_poses.append([entry + Vector3(0.0, 1.65, 1.1), o + Vector3(c0.x, 1.3, c0.y - 2.0)])
	_poses.append([o + Vector3(r0.end.x - 0.7, h0 - 0.6, r0.end.y - 0.7), o + Vector3(c0.x, 0.8, c0.y)])
	_poses.append([o + Vector3(c0.x, 1.7, r0.end.y - 1.5), o + Vector3(c0.x, 1.6, r0.position.y)])
	if p.doors.size() > 1:
		var dd: Dictionary = p.doors[1]
		var line := float(dd["line"])
		var c := float(dd["c"])
		var a := o + (Vector3(c, 1.65, line) if int(dd["axis"]) == 0 else Vector3(line, 1.65, c))
		var parent_i := int(dd["a"])
		var pc := (p.rooms[parent_i]["rect"] as Rect2).get_center()
		var from := Vector3(pc.x, 1.65, pc.y) + o
		var dirv := (a - from)
		dirv.y = 0.0
		_poses.append([a - dirv.normalized() * 2.6, a + dirv.normalized() * 3.0 + Vector3(0, -0.3, 0)])
		var rc := (p.rooms[int(dd["b"])]["rect"] as Rect2).get_center()
		_poses.append([a + dirv.normalized() * 1.5, o + Vector3(rc.x, 1.1, rc.y)])
	else:
		_poses.append([o + Vector3(c0.x + 1.0, 1.7, c0.y + 1.0), o + Vector3(c0.x - 2.0, 1.0, c0.y - 1.0)])
		_poses.append([o + Vector3(r0.position.x + 0.7, 1.7, r0.position.y + 0.7), o + Vector3(c0.x, 1.0, c0.y)])
	var bd := p.bounds
	_poses.append([o + Vector3(bd.get_center().x, 15.0, bd.get_center().y + 0.5), o + Vector3(bd.get_center().x, 0.0, bd.get_center().y)])


func _apply(k: int) -> void:
	k = clampi(k, 0, _poses.size() - 1)
	if k == _last_pose:
		return
	_last_pose = k
	var pose: Array = _poses[k]
	if hero != null:
		var pl := hero as Player
		pl.teleport_to(pose[0])
		pl.yaw = float(pose[1])
		pl.rotation.y = float(pose[1])
		pl.camera_rig.reset_view(float(pose[1]), -0.12)
		pl.camera_rig.snap()
	else:
		cam.global_position = pose[0]
		var up := Vector3.UP if absf((pose[1] as Vector3).x - (pose[0] as Vector3).x) + absf((pose[1] as Vector3).z - (pose[0] as Vector3).z) > 0.5 else Vector3(0, 0, -1)
		cam.look_at(pose[1], up)


func _process(_delta: float) -> void:
	_frame += 1
	_apply((_frame - 1) / _every)
	if _args.has("stats") and _frame % _every == _every - 1:
		print("STATS ", _args.get("interior", "club"), " q", Game.quality, " pose ", (_frame - 1) / _every, " ", PerfProbe.line("frame", PerfProbe.snapshot(get_viewport())))
