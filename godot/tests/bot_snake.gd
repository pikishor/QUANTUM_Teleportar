extends RefCounted
## Look-dev bot of the QUANTUM SNAKES (wave 115): the real game, the real camera behind the hero, one scene at a time, frames saved at chosen moments.
##   SNK_OUT=/tmp/x SNK_SCENES=tendril,swing,zip,climb,fly BOT_RES=1200x540 QUALITY=0 ENGINE_ARGS="--fixed-fps 30" tools/bot.sh res://tests/bot_snake.gd /tmp/x/seq 100000 1
## Scenes: tendril (the shared snake visual alone: leaving the hand, in flight, attached taut and slack, retracting), later swing / zip / climb / fly (set up below).
## SNK_SPOT="x,z,yaw" forces the street. A frame is saved at every `shot` action of the plan, <SNK_OUT>/<scene>_<label>.png.

var _setup_done := false
var _p: Player
var _mgr: EnemyManager
var _spot := Vector3.ZERO
var _yaw := 0.0
var _scenes: Array[StringName] = []
var _si := 0
var _t := 0.0
var _out := ""
var _plan: Array = []
var _pi := 0
var _saved := 0
var _tend: Array = []
var _begun := false
var _hud: CanvasLayer


func _init() -> void:
	_out = OS.get_environment("SNK_OUT")
	var s := OS.get_environment("SNK_SCENES")
	for n in (s if s != "" else "tendril").split(",", false):
		_scenes.append(StringName(n))


func _dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _lane() -> bool:
	var city := Game.world as City
	if city == null:
		return false
	var space := _p.get_world_3d().direct_space_state
	for tries in 600:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for k in 8:
			var yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var a := rp + Vector3(0, 1.5, 0)
			var ok := true
			for off in [-5.0, 0.0, 5.0]:
				var side := dir.cross(Vector3.UP) * float(off)
				var q := PhysicsRayQueryParameters3D.create(a + side, a + side + dir * 64.0, Game.L_WORLD | Game.L_VEHICLE)
				if not space.intersect_ray(q).is_empty():
					ok = false
					break
			if ok:
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
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	TestMode.god = true
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	var forced := OS.get_environment("SNK_SPOT")
	if forced != "":
		var fp := forced.split(",")
		_spot = Vector3(float(fp[0]), 0.0, float(fp[1]))
		_yaw = float(fp[2])
	elif not _lane():
		print("BOTSNK no open lane found")
		return
	if OS.get_environment("SNK_HUD") != "1":
		_hud = Game.get_tree().root.find_child("Hud", true, false) as CanvasLayer
	DirAccess.make_dir_recursive_absolute(_out)
	print("BOTSNK lane at ", _spot, " yaw ", _yaw, " scenes ", _scenes)


func _hand() -> Vector3:
	return _p.global_position + Vector3(0.0, 1.35, 0.0) + _right() * 0.3 + _dir() * 0.2


func _begin_scene(name: StringName) -> void:
	_plan.clear()
	_pi = 0
	_t = 0.0
	_tend.clear()
	var sn: Variant = _p.get("snake")
	if sn != null:
		sn.call(&"cancel")
	_hold_cam = []
	var pool := SnakeTendrilPool.get_pool()
	if pool != null:
		pool.clear()
	_p.teleport_to(_spot)
	_p.camera_rig.reset_view(_yaw, -0.05)
	match name:
		&"tendril":
			_plan = [
				{"t": 0.3, "act": "cam", "rel": Vector3(1.8, 1.9, 3.4), "look": Vector3(0.0, 4.0, -9.0), "fov": 70.0},
				{"t": 0.5, "act": "fire", "to": Vector3(3.0, 9.0, -14.0), "tension": 0.9},
				{"t": 0.57, "act": "shot", "label": "t_flight"},
				{"t": 0.9, "act": "shot", "label": "t_taut"},
				{"t": 1.2, "act": "fire", "to": Vector3(-5.0, 5.0, -9.0), "tension": 0.15},
				{"t": 1.6, "act": "shot", "label": "t_slack"},
				{"t": 1.7, "act": "cam", "rel": Vector3(1.0, 1.6, 1.4), "look": Vector3(-1.0, 3.0, -8.0), "fov": 60.0},
				{"t": 1.9, "act": "shot", "label": "t_close"},
				{"t": 1.95, "act": "cam_head", "off": Vector3(0.9, 0.35, 1.5), "fov": 50.0},
				{"t": 2.05, "act": "shot", "label": "t_head"},
				{"t": 2.1, "act": "cam_head", "off": Vector3(-0.6, 0.2, 2.6), "fov": 50.0},
				{"t": 2.2, "act": "shot", "label": "t_head2"},
				{"t": 2.3, "act": "retract"},
				{"t": 2.4, "act": "shot", "label": "t_retract"},
				{"t": 2.9, "act": "end"},
			]
		&"swing":
			_plan = [{"t": 0.1, "act": "tp", "pos": Vector3(-30.0, 38.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.2},
				{"t": 0.35, "act": "press", "a": &"snake"}]
			for i in 16:
				_plan.append({"t": 0.6 + float(i) * 0.4, "act": "shot", "label": "sw_%02d" % i})
			_plan.append({"t": 7.4, "act": "release", "a": &"snake"})
			_plan.append({"t": 7.5, "act": "end"})
		&"pose":
			# the hero in each state from a free camera: swing (side, front), climb (side, back), flight (side, front, back)
			_plan = [{"t": 0.1, "act": "tp", "pos": Vector3(-30.0, 38.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.2},
				{"t": 0.3, "act": "press", "a": &"snake"},
				{"t": 1.4, "act": "cam_hero", "off": Vector3(4.2, 0.4, 1.0), "fov": 55.0},
				{"t": 1.6, "act": "shot", "label": "swing_side"},
				{"t": 1.7, "act": "cam_hero", "off": Vector3(-1.0, 0.8, -4.2), "fov": 55.0},
				{"t": 1.9, "act": "shot", "label": "swing_front"},
				{"t": 2.0, "act": "cam_hero", "off": Vector3(0.0, 1.0, 4.4), "fov": 55.0},
				{"t": 2.2, "act": "shot", "label": "swing_back"},
				{"t": 2.3, "act": "release", "a": &"snake"},
				{"t": 2.4, "act": "tp", "pos": Vector3(-13.2, 0.0, 15.0), "yaw": PI, "pitch": 0.1},
				{"t": 2.9, "act": "tap", "a": &"snake"},
				{"t": 3.1, "act": "press", "a": &"move_forward"},
				{"t": 3.9, "act": "cam_hero", "off": Vector3(3.6, 0.3, 1.2), "fov": 55.0},
				{"t": 4.1, "act": "shot", "label": "climb_side"},
				{"t": 4.2, "act": "cam_hero", "off": Vector3(0.6, 0.5, 4.0), "fov": 55.0},
				{"t": 4.4, "act": "shot", "label": "climb_back"},
				{"t": 4.5, "act": "release", "a": &"move_forward"},
				{"t": 4.6, "act": "tap", "a": &"snake"},
				{"t": 5.2, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.12},
				{"t": 5.7, "act": "tap", "a": &"fly"},
				{"t": 6.6, "act": "press", "a": &"move_forward"},
				{"t": 7.6, "act": "cam_hero", "off": Vector3(5.0, 0.6, 0.0), "fov": 55.0},
				{"t": 7.8, "act": "shot", "label": "fly_side"},
				{"t": 7.9, "act": "cam_hero", "off": Vector3(0.0, 0.7, -5.0), "fov": 55.0},
				{"t": 8.1, "act": "shot", "label": "fly_front"},
				{"t": 8.2, "act": "cam_hero", "off": Vector3(0.0, 1.0, 5.2), "fov": 55.0},
				{"t": 8.4, "act": "shot", "label": "fly_back"},
				{"t": 8.6, "act": "end"}]
		&"hud":
			_plan = [{"t": 0.1, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.1},
				{"t": 1.2, "act": "shot", "label": "hud_ground"},
				{"t": 1.3, "act": "tp", "pos": Vector3(-30.0, 30.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.1},
				{"t": 1.9, "act": "shot", "label": "hud_air"},
				{"t": 2.0, "act": "end"}]
		&"zip":
			_plan = [{"t": 0.1, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": PI, "pitch": 0.38},
				{"t": 0.8, "act": "shot", "label": "zp_00"},
				{"t": 0.9, "act": "tap", "a": &"snake"}]
			for i in 10:
				_plan.append({"t": 1.1 + float(i) * 0.22, "act": "shot", "label": "zp_%02d" % (i + 1)})
			_plan.append({"t": 4.2, "act": "end"})
		&"climb":
			_plan = [{"t": 0.1, "act": "tp", "pos": Vector3(-13.2, 0.0, 15.0), "yaw": PI, "pitch": 0.1},
				{"t": 0.7, "act": "tap", "a": &"snake"},
				{"t": 1.0, "act": "press", "a": &"move_forward"}]
			for i in 14:
				_plan.append({"t": 1.2 + float(i) * 0.45, "act": "shot", "label": "cl_%02d" % i})
			_plan.append({"t": 8.0, "act": "end"})
		&"fly":
			_plan = [{"t": 0.1, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.12},
				{"t": 0.7, "act": "tap", "a": &"fly"},
				{"t": 1.5, "act": "press", "a": &"move_forward"}]
			for i in 14:
				_plan.append({"t": 0.9 + float(i) * 0.4, "act": "shot", "label": "fl_%02d" % i})
			_plan.append({"t": 4.0, "act": "press", "a": &"snake"})
			_plan.append({"t": 6.2, "act": "release", "a": &"snake"})
			_plan.append({"t": 7.0, "act": "end"})
		_:
			_plan = [{"t": 0.2, "act": "end"}]


func step(t: float, delta: float) -> bool:
	if not _setup_done:
		if t > 2.0 and Game.player != null and Game.world != null:
			_setup()
		return false
	if _scenes.is_empty() or _si >= _scenes.size():
		return true
	if not _begun:
		_begun = true
		_begin_scene(_scenes[_si])
	_t += delta
	if _hud != null:
		_hud.visible = false
	if not _tap_release.is_empty() and _t >= float(_tap_release[1]):
		Input.action_release(_tap_release[0])
		_tap_release = []
	if not _hold_cam.is_empty():
		_p.camera_rig.cine_set(_hold_cam[0], float(_hold_cam[1]))
	_apply_hero_cam()
	while _pi < _plan.size() and float((_plan[_pi] as Dictionary)["t"]) <= _t:
		_run(_plan[_pi] as Dictionary)
		_pi += 1
	return false


func _local(v: Vector3) -> Vector3:
	return _spot + _right() * v.x + Vector3.UP * v.y + _dir() * (-v.z)


func _run(a: Dictionary) -> void:
	match a["act"]:
		"cam":
			var pos := _local(a["rel"])
			var look := _local(a["look"])
			var xf := Transform3D(Basis.looking_at((look - pos).normalized(), Vector3.UP), pos)
			_p.camera_rig.cine_set(xf, float(a["fov"]))
			_hold_cam = [xf, float(a["fov"])]
		"fire":
			var tg := _local(a["to"])
			var tt := SnakeTendril.fire(func() -> Vector3: return _hand(), tg, {"tension": float(a.get("tension", 0.5))})
			_tend.append(tt)
		"cam_head":
			var tl := _tend[_tend.size() - 1] as SnakeTendril
			var hp := tl.head_pos
			var pos2 := hp + _right() * float(a["off"].x) + Vector3.UP * float(a["off"].y) + _dir() * (-float(a["off"].z))
			var xf2 := Transform3D(Basis.looking_at((hp - pos2).normalized(), Vector3.UP), pos2)
			_p.camera_rig.cine_set(xf2, float(a["fov"]))
			_hold_cam = [xf2, float(a["fov"])]
		"tp":
			_hold_cam = []
			_hero_cam = []
			_p.camera_rig.cine_clear()
			var sp: Vector3 = a["pos"]
			_p.teleport_to(sp)
			_p.camera_rig.reset_view(float(a["yaw"]), float(a["pitch"]))
			_p.yaw = float(a["yaw"])
		"press":
			Input.action_press(a["a"])
		"release":
			Input.action_release(a["a"])
		"tap":
			Input.action_press(a["a"])
			_tap_release = [a["a"], _t + 0.12]
		"cam_hero":
			_hero_cam = [a["off"], float(a["fov"])]
			_hold_cam = []
			_apply_hero_cam()
		"retract":
			for tt in _tend:
				(tt as SnakeTendril).retract(0.4)
		"shot":
			_save(String(a["label"]))
		"end":
			print("BOTSNK scene done ", _scenes[_si], " frames ", _saved)
			_si += 1
			_begun = false
			if _si >= _scenes.size():
				_p.get_tree().quit()


var _hold_cam: Array = []
var _tap_release: Array = []
var _hero_cam: Array = []


## A free camera that follows the hero: offset in his own heading frame (x right, y up, z behind; negative = in front of him), looking at his centre.
func _apply_hero_cam() -> void:
	if _hero_cam.is_empty():
		return
	var yawh := _p.snake.facing_yaw()
	if is_nan(yawh):
		yawh = _p.yaw
	var fwd := Vector3(-sin(yawh), 0.0, -cos(yawh))
	var rgt := Vector3(cos(yawh), 0.0, -sin(yawh))
	var ctr := _p.global_position + Vector3(0.0, 1.0, 0.0)
	var off: Vector3 = _hero_cam[0]
	var cpos := ctr + rgt * off.x + Vector3.UP * off.y - fwd * off.z
	var cx := Transform3D(Basis.looking_at((ctr - cpos).normalized(), Vector3.UP), cpos)
	_p.camera_rig.cine_set(cx, float(_hero_cam[1]))


func _save(label: String) -> void:
	var img := _p.get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [_out, String(_scenes[_si]), label]
	img.save_png(path)
	_saved += 1
