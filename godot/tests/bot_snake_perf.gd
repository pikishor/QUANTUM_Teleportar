extends RefCounted
## What the QUANTUM SNAKES cost on screen (wave 115): draw calls, triangles and texture memory of the real game view in each snake state, next to the same view without one. The numbers of a phone are
## the same as under software Vulkan (frame times are not). Prints `SNKPERF <state> draws=<total> prims=<total> (+draws, +prims)` and a closing `SNKPERF SUMMARY`.
##   QUALITY=0 ENGINE_ARGS="--fixed-fps 30" BOT_RES=1280x720 BOT_USER_ARGS="--touch" tools/bot.sh res://tests/bot_snake_perf.gd /tmp/x/perf 100000 1
## States: base (hero on the street), air (hero in the air with the anchor marker up), swing (hanging from a snake, speed lines on), zip (mid pull), climb (on a wall), fly (wings, boost).

var _p: Player
var _setup_done := false
var _t := 0.0
var _plan: Array = []
var _pi := 0
var _rows: Dictionary = {}
var _cur := ""
var _samples: Array = []
var _tap_release: Array = []
var _hidden := false


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	for n in _p.get_tree().root.find_children("*", "AutoQuality", true, false):
		(n as AutoQuality).enabled = false
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	_plan = [
		{"t": 0.2, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.1},
		{"t": 1.8, "act": "sample", "state": "base", "n": 4},
		{"t": 2.4, "act": "tp", "pos": Vector3(-30.0, 40.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.2},
		{"t": 2.9, "act": "sample", "state": "air", "n": 3},
		{"t": 3.1, "act": "press", "a": &"snake"},
		{"t": 4.0, "act": "sample", "state": "swing", "n": 4},
		{"t": 4.5, "act": "hide"},
		{"t": 4.6, "act": "sample", "state": "swing_off", "n": 4},
		{"t": 5.1, "act": "show"},
		{"t": 5.3, "act": "release", "a": &"snake"},
		{"t": 5.4, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": PI, "pitch": 0.38},
		{"t": 6.2, "act": "tap", "a": &"snake"},
		{"t": 6.55, "act": "sample", "state": "zip", "n": 2},
		{"t": 6.75, "act": "hide"},
		{"t": 6.8, "act": "sample", "state": "zip_off", "n": 2},
		{"t": 7.0, "act": "show"},
		{"t": 7.4, "act": "tp", "pos": Vector3(-13.2, 0.0, 15.0), "yaw": PI, "pitch": 0.1},
		{"t": 8.0, "act": "tap", "a": &"snake"},
		{"t": 8.4, "act": "press", "a": &"move_forward"},
		{"t": 9.2, "act": "sample", "state": "climb", "n": 3},
		{"t": 9.5, "act": "hide"},
		{"t": 9.6, "act": "sample", "state": "climb_off", "n": 3},
		{"t": 9.9, "act": "show"},
		{"t": 10.0, "act": "release", "a": &"move_forward"},
		{"t": 10.1, "act": "tp", "pos": Vector3(-30.0, 0.0, 4.0), "yaw": -PI * 0.5, "pitch": 0.12},
		{"t": 10.7, "act": "tap", "a": &"fly"},
		{"t": 11.6, "act": "press", "a": &"move_forward"},
		{"t": 12.2, "act": "press", "a": &"snake"},
		{"t": 13.0, "act": "sample", "state": "fly", "n": 4},
		{"t": 13.4, "act": "hide"},
		{"t": 13.5, "act": "sample", "state": "fly_off", "n": 4},
		{"t": 13.9, "act": "show"},
		{"t": 14.2, "act": "end"},
	]
	print("SNKPERF quality=", Game.quality, " res=", _p.get_viewport().get_visible_rect().size)


func step(t: float, delta: float) -> bool:
	if not _setup_done:
		if t > 2.0 and Game.player != null and Game.world != null:
			_setup()
		return false
	_t += delta
	if not _tap_release.is_empty() and _t >= float(_tap_release[1]):
		Input.action_release(_tap_release[0])
		_tap_release = []
	if not _cur.is_empty():
		_samples.append(PerfProbe.snapshot(_p.get_viewport()))
		var need: int = (_rows[_cur] as Dictionary)["n"]
		if _samples.size() >= need:
			var best := {"total_draws": 0, "total_prims": 0, "tex_mb": 0.0, "draws": 0, "prims": 0}
			for s: Dictionary in _samples:
				for k in best.keys():
					best[k] = maxf(float(best[k]), float(s.get(k, 0)))
			(_rows[_cur] as Dictionary)["snap"] = best
			(_rows[_cur] as Dictionary)["mode"] = _p.snake.mode_name()
			_cur = ""
			_samples.clear()
	while _pi < _plan.size() and float((_plan[_pi] as Dictionary)["t"]) <= _t:
		if _run(_plan[_pi] as Dictionary):
			return true
		_pi += 1
	return false


func _run(a: Dictionary) -> bool:
	match a["act"]:
		"tp":
			_p.snake.cancel()
			_p.teleport_to(a["pos"])
			_p.camera_rig.reset_view(float(a["yaw"]), float(a["pitch"]))
			_p.yaw = float(a["yaw"])
		"press":
			Input.action_press(a["a"])
		"release":
			Input.action_release(a["a"])
		"tap":
			Input.action_press(a["a"])
			_tap_release = [a["a"], _t + 0.12]
		"hide":
			SnakeTendrilPool.get_pool(_p).visible = false
			_hidden = true
		"show":
			SnakeTendrilPool.get_pool(_p).visible = true
			_hidden = false
		"sample":
			_cur = String(a["state"])
			_samples.clear()
			_rows[_cur] = {"n": int(a["n"])}
		"end":
			_report()
			_p.get_tree().quit()
			return true
	return false


func _report() -> void:
	var base: Dictionary = (_rows.get("base", {}) as Dictionary).get("snap", {})
	for st: String in ["base", "air", "swing", "zip", "climb", "fly"]:
		if not _rows.has(st) or not (_rows[st] as Dictionary).has("snap"):
			print("SNKPERF %s no sample" % st)
			continue
		var s: Dictionary = (_rows[st] as Dictionary)["snap"]
		var line := "SNKPERF %-6s mode=%-5s visible draws=%d total draws=%d prims=%d tex=%.1f MB" % [st, (_rows[st] as Dictionary).get("mode", "?"), int(s["draws"]), int(s["total_draws"]), int(s["total_prims"]), float(s["tex_mb"])]
		var off := st + "_off"
		if _rows.has(off) and (_rows[off] as Dictionary).has("snap"):
			var o: Dictionary = (_rows[off] as Dictionary)["snap"]
			line += "   | snake visuals cost: %+d visible draws, %+d total draws, %+d prims (same view, tendrils and marker hidden)" % [int(s["draws"]) - int(o["draws"]), int(s["total_draws"]) - int(o["total_draws"]), int(s["total_prims"]) - int(o["total_prims"])]
		print(line)
	print("SNKPERF SUMMARY done")
