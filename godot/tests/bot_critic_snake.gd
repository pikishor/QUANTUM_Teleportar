extends RefCounted
## Critic look-dev bot of wave 115 (QUANTUM SNAKES, lens LOOK): the real game, the real camera, the phone HUD (BOT_USER_ARGS="--touch"), frames saved by the bot itself.
## The renderer only runs for the frames that are saved (RenderingServer.render_loop_enabled), so a 60 s run at 5 frames a second takes minutes, not an hour.
##   CS_MODE=run    : a thumb policy plays a swing run from the street (SNAKE tapped on the ground, held in the air, the camera turned toward waypoints by add_look) for CS_SECS game seconds,
##                    one frame every 1 / CS_FPS s (saved as <CS_OUT>/run_NNN.png) and a telemetry line every 0.5 s (mode, speed, camera and occlusion numbers).
##   CS_MODE=scenes : the focus-list scenes of CS_SCENES (comma list of the PLANS below), frames at the plan's `shot` actions, <CS_OUT>/<scene>_<label>.png
## Common: CS_OUT=/dir  CS_START="x,y,z,yaw" (run start)  CS_HOUR=hour  BOT_RES=1200x540 ENGINE_ARGS="--fixed-fps 30" QUALITY=0|1 tools/bot.sh res://tests/bot_critic_snake.gd /tmp/x/seq 100000 1

var _setup_done := false
var _warm := 0.0
var _p: Player
var _mode := "run"
var _out := ""
var _secs := 60.0
var _fps := 5.0
var _t := 0.0
var _cap := 0
var _next_cap := 0.0
var _render_on := true
var _hold_snake := false
var _tap_until := -1.0
var _goal := Vector3.ZERO
var _goals: Array[Vector3] = []
var _gi := 0
var _start := Vector3(-30.0, 0.0, 4.0)
var _start_yaw := -PI * 0.5
var _tele := {}
var _prev_rel := Vector3.ZERO
var _prev_cam := Vector3.ZERO
var _stats := {"frames": 0, "occluded": 0, "inside": 0, "pops": 0, "max_pop": 0.0, "obstructed": 0, "min_cam": 99.0, "max_cam": 0.0, "stuck": 0, "grounded": 0}
var _mode_time := {}
var _last_mode := -1
var _stuck_t := 0.0
var _scenes: Array[String] = []
var _si := 0
var _plan: Array = []
var _pi := 0
var _begun := false
var _tap_release: Array = []
var _log_t := 0.0
var _scene_t := 0.0
var _hold_keys := {}
var _fly_t := 0.0
var _hero_cam: Array = []
var _slab: Node3D
var _landed_t := 0.0
var _fly_tapped := false
var _fly_rel := -1.0


func _init() -> void:
	_out = OS.get_environment("CS_OUT")
	if OS.get_environment("CS_MODE") != "":
		_mode = OS.get_environment("CS_MODE")
	if OS.get_environment("CS_SECS") != "":
		_secs = float(OS.get_environment("CS_SECS"))
	if OS.get_environment("CS_FPS") != "":
		_fps = float(OS.get_environment("CS_FPS"))
	for n in (OS.get_environment("CS_SCENES") if OS.get_environment("CS_SCENES") != "" else "zip").split(",", false):
		_scenes.append(n)
	if OS.get_environment("CS_GOALS") != "":
		for g in OS.get_environment("CS_GOALS").split(";", false):
			var gp := g.split(",")
			_goals.append(Vector3(float(gp[0]), 0.0, float(gp[1])))
	if OS.get_environment("CS_GI") != "":
		_gi = int(OS.get_environment("CS_GI"))
	if OS.get_environment("CS_START") != "":
		var sp := OS.get_environment("CS_START").split(",")
		_start = Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
		_start_yaw = float(sp[3])


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	var mgr := Game.enemies as EnemyManager
	for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	mgr.patrol_groups().clear()
	mgr.clear()
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	TestMode.god = true
	SnakeTraversal.assist = true
	SnakeFlight.clip_wings = OS.get_environment("CS_NOCLIP") != "1"
	SnakeTraversal.suit_glow = OS.get_environment("CS_NOGLOW") != "1"
	var city := Game.world as City
	if OS.get_environment("CS_HOUR") != "" and city != null and city.day_night != null:
		city.day_night.frozen = true
		city.day_night.set_hour(float(OS.get_environment("CS_HOUR")))
	DirAccess.make_dir_recursive_absolute(_out)
	if _mode == "run" and city != null and _goals.is_empty():
		var pts: Array[Vector3] = []
		for i in 40:
			var rp: Vector3 = city.random_core_road_point()
			if rp.is_finite():
				pts.append(rp)
		var cur := _start
		while not pts.is_empty() and _goals.size() < 6:
			var best := 0
			for k in pts.size():
				var d := Vector2(pts[k].x - cur.x, pts[k].z - cur.z).length()
				var bd := Vector2(pts[best].x - cur.x, pts[best].z - cur.z).length()
				var ahead := Vector2(pts[k].x - cur.x, pts[k].z - cur.z).normalized().dot(Vector2(-sin(_start_yaw), -cos(_start_yaw)))
				if d > 90.0 and d < 420.0 and ahead > -0.2 and (bd <= 90.0 or d < bd):
					best = k
			cur = pts[best]
			pts.remove_at(best)
			_goals.append(cur)
		if _goals.is_empty():
			_goals.append(_start + Vector3(-sin(_start_yaw), 0.0, -cos(_start_yaw)) * 400.0)
	if _mode == "run":
		_gi = _gi % maxi(_goals.size(), 1)
		_goal = _goals[_gi]
		var gs: PackedStringArray = []
		for g in _goals:
			gs.append("%.0f,%.0f" % [g.x, g.z])
		print("BOTCS GOALS ", ";".join(gs))
	print("BOTCS setup mode ", _mode, " start ", _start, " goals ", _goals)


func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


func _render(on: bool) -> void:
	if on != _render_on:
		RenderingServer.render_loop_enabled = on
		_render_on = on


func step(_tt: float, delta: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.missions == null or Game.world == null:
		return false
	if not _setup_done:
		if _tt < 2.0:
			return false
		_setup()
		return false
	Game.state = &"play"
	_p.invuln = 5.0
	if _warm < 3.0:
		if _warm == 0.0:
			_p.teleport_to(_start)
			_p.camera_rig.reset_view(_start_yaw, 0.1)
			_p.yaw = _start_yaw
		_warm += delta
		_render(false)
		return false
	if _mode == "run":
		return _step_run(delta)
	return _step_scenes(delta)


# --- the 60 s swing run ----------------------------------------------------------------------------------------------------------------------

func _tele_probe(delta: float) -> void:
	var sn := _p.snake
	var cam := _p.camera_rig.camera
	if cam == null:
		return
	var rel := cam.global_position - _p.global_position
	_stats["frames"] = int(_stats["frames"]) + 1
	var dist := (cam.global_position - (_p.global_position + Vector3(0, 1.0, 0))).length()
	_stats["min_cam"] = minf(float(_stats["min_cam"]), dist)
	_stats["max_cam"] = maxf(float(_stats["max_cam"]), dist)
	if _prev_cam != Vector3.ZERO:
		var pop := ((cam.global_position - _prev_cam) - (_p.global_position - (_prev_cam - _prev_rel))).length()
		if pop > 0.9 and delta > 0.0:
			_stats["pops"] = int(_stats["pops"]) + 1
		_stats["max_pop"] = maxf(float(_stats["max_pop"]), pop)
	_prev_cam = cam.global_position
	_prev_rel = rel
	var space := _p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, _p.global_position + Vector3(0, 1.0, 0), Game.L_WORLD)
	if not space.intersect_ray(q).is_empty():
		_stats["occluded"] = int(_stats["occluded"]) + 1
	var pq := PhysicsPointQueryParameters3D.new()
	pq.position = cam.global_position
	pq.collision_mask = Game.L_WORLD
	if not space.intersect_point(pq, 1).is_empty():
		_stats["inside"] = int(_stats["inside"]) + 1
	if _p.camera_rig.is_obstructed():
		_stats["obstructed"] = int(_stats["obstructed"]) + 1
	var m: int = sn.mode
	_mode_time[m] = float(_mode_time.get(m, 0.0)) + delta
	if m == SnakeTraversal.Mode.SWING and _p.velocity.length() < 4.0:
		_stuck_t += delta
		if _stuck_t > 1.0:
			_stats["stuck"] = int(_stats["stuck"]) + 1
	else:
		_stuck_t = 0.0


func _step_run(delta: float) -> bool:
	var sn := _p.snake
	_t += delta
	var on_floor := _p.is_on_floor()
	var pos := _p.global_position
	# waypoint
	if Vector2(pos.x - _goal.x, pos.z - _goal.z).length() < 45.0:
		_gi = (_gi + 1) % _goals.size()
		_goal = _goals[_gi]
	# the right thumb: turn the camera toward the goal (at most 1.7 rad/s), a little up while swinging
	var want := _yaw_to(pos, _goal)
	var d := wrapf(want - _p.camera_rig.yaw, -PI, PI)
	var turn := clampf(d, -1.7 * delta, 1.7 * delta)
	var want_pitch := 0.2 if not on_floor else 0.05
	var dp := clampf(want_pitch - _p.camera_rig.pitch, -0.8 * delta, 0.8 * delta)
	if sn.mode != SnakeTraversal.Mode.CLIMB and sn.mode != SnakeTraversal.Mode.ZIP:           # the thumb leaves the look zone while a wall is climbed or a zip pulls (the camera turns by itself then)
		_p.camera_rig.add_look(-turn, -dp)                                   # add_look takes radians, yaw > 0 turns right, pitch > 0 looks down (the rig's own yaw is Node3D: positive = left)
	# the left thumb and the SNAKE button the way a player uses them: forward on the ground and up a wall, SNAKE tapped on the ground and held in the air, boost for the first seconds of a flight
	match int(sn.mode):
		SnakeTraversal.Mode.NONE:
			_fly_t = 0.0
			_fly_tapped = false
			if on_floor:
				Input.action_press(&"move_forward")
				if _t >= _tap_until + 0.7:
					Input.action_press(&"snake")
					_tap_until = _t + 0.12
				elif _t >= _tap_until:
					Input.action_release(&"snake")
			else:
				Input.action_release(&"move_forward")
				Input.action_press(&"snake")
				_tap_until = _t
		SnakeTraversal.Mode.SWING:
			_fly_t = 0.0
			Input.action_release(&"move_forward")
			Input.action_press(&"snake")
			_tap_until = _t
		SnakeTraversal.Mode.CLIMB:
			Input.action_press(&"move_forward")
			Input.action_release(&"snake")
			_tap_until = _t + 0.5
		SnakeTraversal.Mode.ZIP:
			Input.action_release(&"snake")
			_tap_until = _t + 0.5
		SnakeTraversal.Mode.FLY:
			_fly_t += delta
			Input.action_press(&"move_forward")
			if _fly_t < 1.5:
				Input.action_press(&"snake")
			else:
				Input.action_release(&"snake")
			if _fly_t > 4.0 and not _fly_tapped:
				_fly_tapped = true
				Input.action_press(&"fly")
				_fly_rel = _t + 0.12
	if _fly_rel > 0.0 and _t >= _fly_rel:
		Input.action_release(&"fly")
		_fly_rel = -1.0
	if int(sn.mode) != _last_mode:
		print("BOTCS %.1f mode %s -> %s at %s v %.1f" % [_t, _last_mode, sn.mode, pos.snapped(Vector3(0.1, 0.1, 0.1)), _p.velocity.length()])
		_last_mode = sn.mode
	_tele_probe(delta)
	if _t >= _log_t:
		_log_t += 0.5
		print("BOTCS t %.1f mode %d pos %s v %.1f e %.0f swings %d chain %d" % [_t, sn.mode, pos.snapped(Vector3(0.1, 0.1, 0.1)), _p.velocity.length(), sn.energy, sn.swings, sn.chain])
	# frames: the renderer runs two frames before a capture
	var period := 1.0 / _fps
	if _t >= _next_cap - delta * 2.5 and not _render_on:
		_render(true)
	if _t >= _next_cap and _render_on:
		var img := _p.get_viewport().get_texture().get_image()
		img.save_png("%s/run_%03d.png" % [_out, _cap])
		_cap += 1
		_next_cap += period
		if _next_cap - delta * 2.5 > _t:
			_render(false)
	if on_floor and sn.mode == SnakeTraversal.Mode.NONE:
		_landed_t += delta
	else:
		_landed_t = 0.0
	if _t >= _secs and (_landed_t > 0.5 or _t >= _secs + 25.0):                  # a segment ends on the ground (the next process starts there): CS_START="END" below
		_render(true)
		_finish_run()
		return true
	return false


func _finish_run() -> void:
	var sn := _p.snake
	Input.action_release(&"snake")
	Input.action_release(&"move_forward")
	var names := {0: "NONE", 1: "SWING", 2: "ZIP", 3: "CLIMB", 4: "FLY"}
	var parts: PackedStringArray = []
	for k in _mode_time:
		parts.append("%s %.1f s" % [names.get(k, str(k)), float(_mode_time[k])])
	print("BOTCS END ", "%.2f,%.2f,%.2f,%.3f GI %d" % [_p.global_position.x, _p.global_position.y, _p.global_position.z, _p.camera_rig.yaw, _gi])
	print("BOTCS RUN DONE frames saved ", _cap, " swings ", sn.swings, " zips ", sn.zips, " climbs ", sn.climbs, " flights ", sn.flights, " best chain ", sn.swing.best_chain, " time in ", ", ".join(parts))
	var f := int(_stats["frames"])
	print("BOTCS CAMERA frames %d  occluded %d (%.1f %%)  inside geometry %d  obstructed %d  pops(>0.9 m) %d  max pop %.2f m  cam dist %.2f .. %.2f  stuck-swing frames %d" % [f, int(_stats["occluded"]), 100.0 * float(_stats["occluded"]) / maxf(f, 1), int(_stats["inside"]), int(_stats["obstructed"]), int(_stats["pops"]), float(_stats["max_pop"]), float(_stats["min_cam"]), float(_stats["max_cam"]), int(_stats["stuck"])])
	_p.get_tree().quit()


# --- scripted focus-list scenes --------------------------------------------------------------------------------------------------------------

## every plan is a list of {t, act, ...} (seconds of game time from the scene's start); acts: tp (pos, yaw, pitch), look (yaw, pitch), press / release / tap (a), shot (label), end,
## fly_at (pos, yaw: teleport into the air and start flight by FLY), cam_yaw (yaw: the right thumb turns the view)
func _plan_for(name: String) -> Array:
	match name:
		"zip":
			return [{"t": 0.1, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": PI, "pitch": 0.38}, {"t": 0.8, "act": "shot", "label": "a_aim"}, {"t": 0.9, "act": "tap", "a": &"snake"},
				{"t": 1.1, "act": "shot", "label": "b"}, {"t": 1.3, "act": "shot", "label": "c"}, {"t": 1.5, "act": "shot", "label": "d"}, {"t": 1.8, "act": "shot", "label": "e"},
				{"t": 2.1, "act": "shot", "label": "f"}, {"t": 2.5, "act": "shot", "label": "g_land"}, {"t": 3.2, "act": "shot", "label": "h"}, {"t": 4.0, "act": "end"}]
		"climb":
			return [{"t": 0.1, "act": "tp", "pos": Vector3(-13.2, 0.0, 15.0), "yaw": PI, "pitch": 0.1}, {"t": 0.7, "act": "tap", "a": &"snake"}, {"t": 1.0, "act": "press", "a": &"move_forward"},
				{"t": 1.5, "act": "shot", "label": "a_wall"}, {"t": 2.5, "act": "shot", "label": "b"}, {"t": 4.0, "act": "shot", "label": "c"}, {"t": 5.5, "act": "shot", "label": "d"},
				{"t": 7.0, "act": "shot", "label": "e"}, {"t": 8.5, "act": "shot", "label": "f_mantle"}, {"t": 9.5, "act": "shot", "label": "g_roof"}, {"t": 10.5, "act": "release", "a": &"move_forward"}, {"t": 11.0, "act": "end"}]
		"fly":
			return [{"t": 0.1, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.12}, {"t": 0.7, "act": "shot", "label": "a_ground"}, {"t": 0.8, "act": "tap", "a": &"fly"},
				{"t": 1.0, "act": "shot", "label": "b_takeoff"}, {"t": 1.4, "act": "shot", "label": "c_takeoff"}, {"t": 1.9, "act": "press", "a": &"move_forward"}, {"t": 2.4, "act": "shot", "label": "d_cruise"},
				{"t": 3.4, "act": "shot", "label": "e_cruise"}, {"t": 4.0, "act": "press", "a": &"snake"}, {"t": 4.5, "act": "shot", "label": "f_boost"}, {"t": 5.2, "act": "shot", "label": "g_boost"},
				{"t": 6.0, "act": "release", "a": &"snake"}, {"t": 6.1, "act": "release", "a": &"move_forward"}, {"t": 6.8, "act": "shot", "label": "h_glide"}, {"t": 7.6, "act": "shot", "label": "i_hover"}, {"t": 8.0, "act": "end"}]
		"fly_wall":
			return [{"t": 0.1, "act": "tp", "pos": Vector3(-45.0, 35.0, 12.2), "yaw": -PI * 0.5, "pitch": 0.05}, {"t": 0.5, "act": "tap", "a": &"fly"}, {"t": 1.2, "act": "press", "a": &"move_forward"},
				{"t": 1.8, "act": "shot", "label": "a"}, {"t": 2.2, "act": "shot", "label": "b"}, {"t": 2.6, "act": "shot", "label": "c"}, {"t": 3.0, "act": "shot", "label": "d"}, {"t": 3.4, "act": "shot", "label": "e"},
				{"t": 3.8, "act": "shot", "label": "f"}, {"t": 4.2, "act": "release", "a": &"move_forward"}, {"t": 4.4, "act": "end"}]
		"dive_roll":
			return [{"t": 0.1, "act": "tp", "pos": Vector3(-30.0, 160.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.1}, {"t": 0.5, "act": "tap", "a": &"fly"}, {"t": 1.2, "act": "press", "a": &"move_forward"},
				{"t": 2.4, "act": "shot", "label": "a_level"}, {"t": 2.5, "act": "look", "yaw": -PI * 0.5, "pitch": -0.7}, {"t": 3.0, "act": "shot", "label": "b_dive"}, {"t": 3.5, "act": "shot", "label": "c_dive"},
				{"t": 4.0, "act": "shot", "label": "d_dive"}, {"t": 4.1, "act": "look", "yaw": -PI * 0.5, "pitch": 0.05},
				{"t": 4.7, "act": "shot", "label": "e_pullout"}, {"t": 4.9, "act": "release", "a": &"move_forward"}, {"t": 5.0, "act": "press", "a": &"move_right"}, {"t": 5.05, "act": "release", "a": &"move_right"},
				{"t": 5.18, "act": "press", "a": &"move_right"}, {"t": 5.23, "act": "release", "a": &"move_right"}, {"t": 5.3, "act": "shot", "label": "f_roll"}, {"t": 5.5, "act": "shot", "label": "g_roll"},
				{"t": 5.7, "act": "shot", "label": "h_roll"}, {"t": 5.9, "act": "shot", "label": "i_roll"}, {"t": 6.1, "act": "press", "a": &"move_forward"}, {"t": 6.8, "act": "shot", "label": "j_after"},
				{"t": 7.0, "act": "release", "a": &"move_forward"}, {"t": 7.2, "act": "end"}]
		"landing":
			return [{"t": 0.1, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.12}, {"t": 0.8, "act": "tap", "a": &"fly"}, {"t": 1.9, "act": "press", "a": &"move_forward"},
				{"t": 3.5, "act": "release", "a": &"move_forward"}, {"t": 3.6, "act": "tap", "a": &"fly"}, {"t": 4.0, "act": "shot", "label": "a_request"}, {"t": 4.5, "act": "look", "yaw": -PI * 0.5, "pitch": -0.3},
				{"t": 5.0, "act": "shot", "label": "b"}, {"t": 5.6, "act": "shot", "label": "c"}, {"t": 6.2, "act": "shot", "label": "d"}, {"t": 6.9, "act": "shot", "label": "e_land"}, {"t": 7.6, "act": "shot", "label": "f"}, {"t": 8.2, "act": "end"}]
		"hop_swing":
			return [{"t": 0.1, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.25}, {"t": 0.6, "act": "shot", "label": "a_ground"}, {"t": 0.7, "act": "tap", "a": &"snake"},
				{"t": 0.95, "act": "press", "a": &"snake"}, {"t": 1.0, "act": "shot", "label": "b_hop"}, {"t": 1.3, "act": "shot", "label": "c"}, {"t": 1.7, "act": "shot", "label": "d"}, {"t": 2.1, "act": "shot", "label": "e"},
				{"t": 2.6, "act": "shot", "label": "f"}, {"t": 3.2, "act": "shot", "label": "g"}, {"t": 3.8, "act": "shot", "label": "h"}, {"t": 4.5, "act": "release", "a": &"snake"}, {"t": 4.7, "act": "shot", "label": "i_release"}, {"t": 5.2, "act": "end"}]
		"ceiling":
			return [{"t": 0.1, "act": "tp", "pos": Vector3(-30.0, 0.6, 4.0), "yaw": -PI * 0.5, "pitch": 0.0}, {"t": 0.15, "act": "slab", "pos": Vector3(-30.0, 3.6, 4.0)},
				{"t": 0.5, "act": "vel", "v": Vector3(0.0, 6.0, 0.0)}, {"t": 0.7, "act": "press", "a": &"snake"}, {"t": 1.3, "act": "shot", "label": "a_stick"}, {"t": 1.4, "act": "release", "a": &"snake"},
				{"t": 1.5, "act": "press", "a": &"move_forward"}, {"t": 2.2, "act": "shot", "label": "b_crawl"}, {"t": 3.0, "act": "shot", "label": "c_crawl"}, {"t": 3.6, "act": "release", "a": &"move_forward"},
				{"t": 3.7, "act": "press", "a": &"move_right"}, {"t": 4.3, "act": "shot", "label": "d_side"}, {"t": 4.8, "act": "release", "a": &"move_right"}, {"t": 4.9, "act": "tap", "a": &"snake"},
				{"t": 5.3, "act": "shot", "label": "e_drop"}, {"t": 6.0, "act": "shot", "label": "f_land"}, {"t": 6.5, "act": "end"}]
		"glow":
			return [{"t": 0.1, "act": "tp", "pos": Vector3(-30.0, 38.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.2}, {"t": 0.35, "act": "press", "a": &"snake"},
				{"t": 1.5, "act": "cam_hero", "off": Vector3(3.0, 0.3, 1.0), "fov": 50.0}, {"t": 1.8, "act": "shot", "label": "a_swing_side"},
				{"t": 1.9, "act": "cam_hero", "off": Vector3(-0.8, 0.5, -3.0), "fov": 50.0}, {"t": 2.2, "act": "shot", "label": "b_swing_front"},
				{"t": 2.3, "act": "release", "a": &"snake"}, {"t": 2.4, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.12}, {"t": 2.9, "act": "tap", "a": &"fly"},
				{"t": 3.8, "act": "press", "a": &"move_forward"}, {"t": 4.9, "act": "cam_hero", "off": Vector3(0.0, 0.7, 3.2), "fov": 50.0}, {"t": 5.2, "act": "shot", "label": "c_fly_back"},
				{"t": 5.3, "act": "cam_hero", "off": Vector3(0.0, 0.7, -3.4), "fov": 50.0}, {"t": 5.6, "act": "shot", "label": "d_fly_front"}, {"t": 5.8, "act": "release", "a": &"move_forward"}, {"t": 6.0, "act": "end"}]
		"hud2":
			return [{"t": 0.1, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.1}, {"t": 1.2, "act": "shot", "label": "a_ground"},
				{"t": 1.3, "act": "tp", "pos": Vector3(-30.0, 30.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.15}, {"t": 1.9, "act": "shot", "label": "b_air"},
				{"t": 2.0, "act": "press", "a": &"snake"}, {"t": 2.9, "act": "shot", "label": "c_swing"}, {"t": 3.1, "act": "release", "a": &"snake"},
				{"t": 3.3, "act": "tp", "pos": Vector3(-30.0, 40.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.1}, {"t": 3.6, "act": "tap", "a": &"fly"}, {"t": 4.6, "act": "press", "a": &"move_forward"},
				{"t": 5.2, "act": "shot", "label": "d_fly"}, {"t": 5.5, "act": "press", "a": &"snake"}, {"t": 6.0, "act": "shot", "label": "e_boost"}, {"t": 6.2, "act": "release", "a": &"snake"}, {"t": 6.25, "act": "release", "a": &"move_forward"},
				{"t": 6.5, "act": "tp", "pos": Vector3(-13.2, 0.0, 15.0), "yaw": PI, "pitch": 0.1}, {"t": 7.2, "act": "tap", "a": &"snake"}, {"t": 7.6, "act": "press", "a": &"move_forward"},
				{"t": 8.6, "act": "shot", "label": "f_climb"}, {"t": 8.8, "act": "release", "a": &"move_forward"}, {"t": 9.0, "act": "end"}]
		"hud":
			return [{"t": 0.1, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.1}, {"t": 1.2, "act": "shot", "label": "a_ground"},
				{"t": 1.3, "act": "tp", "pos": Vector3(-30.0, 30.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.15}, {"t": 1.9, "act": "shot", "label": "b_air"},
				{"t": 2.0, "act": "press", "a": &"snake"}, {"t": 2.9, "act": "shot", "label": "c_swing"}, {"t": 3.1, "act": "release", "a": &"snake"}, {"t": 3.5, "act": "end"}]
	return [{"t": 0.2, "act": "end"}]


func _free_slab() -> void:
	if _slab != null and is_instance_valid(_slab):
		_slab.queue_free()
	_slab = null


func _begin_scene(name: String) -> void:
	_free_slab()
	_scene_t = 0.0
	_pi = 0
	_plan = _plan_for(name)
	_p.snake.cancel()
	var pool := SnakeTendrilPool.get_pool()
	if pool != null:
		pool.clear()
	for k in _hold_keys.keys():
		Input.action_release(k)
	_hold_keys.clear()
	Input.action_release(&"snake")
	Input.action_release(&"fly")
	print("BOTCS scene ", name)


func _next_shot_t() -> float:
	for i in range(_pi, _plan.size()):
		if (_plan[i] as Dictionary)["act"] == "shot":
			return float((_plan[i] as Dictionary)["t"])
	return 1.0e9


func _step_scenes(delta: float) -> bool:
	if _si >= _scenes.size():
		_render(true)
		_p.get_tree().quit()
		return true
	if not _begun:
		_begun = true
		_begin_scene(_scenes[_si])
	_scene_t += delta
	if not _tap_release.is_empty() and _scene_t >= float(_tap_release[1]):
		Input.action_release(_tap_release[0])
		_tap_release = []
	_apply_hero_cam()
	var ns := _next_shot_t()
	_render(ns - _scene_t <= delta * 2.5)
	while _pi < _plan.size() and float((_plan[_pi] as Dictionary)["t"]) <= _scene_t:
		_act(_plan[_pi] as Dictionary)
		_pi += 1
		if _begun == false:
			break
	return false


func _act(a: Dictionary) -> void:
	match a["act"]:
		"tp":
			_hero_cam = []
			var sp: Vector3 = a["pos"]
			_p.teleport_to(sp)
			_p.camera_rig.reset_view(float(a["yaw"]), float(a["pitch"]))
			_p.yaw = float(a["yaw"])
		"look":
			_p.camera_rig.yaw = float(a["yaw"])
			_p.camera_rig.pitch = float(a["pitch"])
		"vel":
			_p.velocity = a["v"]
		"cam_hero":
			_hero_cam = [a["off"], float(a["fov"])]
		"slab":
			_free_slab()
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(30.0, 1.0, 30.0)
			cs.shape = box
			body.add_child(cs)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = box.size
			mi.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.34, 0.32, 0.30)
			mat.roughness = 0.9
			mi.material_override = mat
			body.add_child(mi)
			body.collision_layer = Game.L_WORLD
			_p.get_tree().root.add_child(body)
			body.global_position = a["pos"]
			_slab = body
		"press":
			Input.action_press(a["a"])
			_hold_keys[a["a"]] = true
		"release":
			Input.action_release(a["a"])
			_hold_keys.erase(a["a"])
		"tap":
			Input.action_press(a["a"])
			_tap_release = [a["a"], _scene_t + 0.12]
		"shot":
			if not _render_on:
				print("BOTCS warning: shot without render ", a["label"])
			var img := _p.get_viewport().get_texture().get_image()
			var path := "%s/%s_%s.png" % [_out, _scenes[_si], String(a["label"])]
			img.save_png(path)
			var sn := _p.snake
			print("BOTCS shot %s mode %d pos %s v %.1f" % [path.get_file(), sn.mode, _p.global_position.snapped(Vector3(0.1, 0.1, 0.1)), _p.velocity.length()])
		"end":
			print("BOTCS scene done ", _scenes[_si])
			_si += 1
			_begun = false


## A free camera that follows the hero: offset in his own heading frame (x right, y up, z behind; negative = in front of him), looking at his centre (CameraRig.cine_set lapses after 0.25 s: every step renews it).
func _apply_hero_cam() -> void:
	if _hero_cam.is_empty() or _p == null:
		return
	var yawh := _p.snake.facing_yaw()
	if is_nan(yawh):
		yawh = _p.yaw
	var fwd := Vector3(-sin(yawh), 0.0, -cos(yawh))
	var rgt := Vector3(cos(yawh), 0.0, -sin(yawh))
	var ctr := _p.global_position + Vector3(0.0, 1.0, 0.0)
	var off: Vector3 = _hero_cam[0]
	var cpos := ctr + rgt * off.x + Vector3.UP * off.y - fwd * off.z
	_p.camera_rig.cine_set(Transform3D(Basis.looking_at((ctr - cpos).normalized(), Vector3.UP), cpos), float(_hero_cam[1]))
