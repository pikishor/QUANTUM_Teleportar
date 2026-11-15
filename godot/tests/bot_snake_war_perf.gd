extends RefCounted
## What the SNAKE COMBAT costs on screen (wave 115): draw calls, triangles and texture memory of the real game view with the powers running, next to the same view with the free snakes hidden.
## Prints `SWPERF <state> visible draws=.. total draws=.. prims=..` and `SWPERF SUMMARY`. The numbers of a phone are the same as under software Vulkan (frame times are not).
##   QUALITY=0 ENGINE_ARGS="--fixed-fps 30" BOT_RES=1280x720 BOT_USER_ARGS="--touch" tools/bot.sh res://tests/bot_snake_war_perf.gd /tmp/x/perf 100000 1
## States: base (hero and three enemies), armed (a bomb in hand: ring, wall, arc), shield, net, guard, swarm (swarm bomb), worst (shield + guard + net + swarm + coil + storm together), marks (flare), mega.

var _p: Player
var _war: SnakeWar
var _setup_done := false
var _t := 0.0
var _plan: Array = []
var _pi := 0
var _rows: Dictionary = {}
var _cur := ""
var _samples: Array = []
var _foes: Array[Drone] = []
var _spot := Vector3(-30.0, 0.0, 4.0)
var _yaw := -PI * 0.5
var _peak_bodies := 0


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
	WeaponDefs.hero_mode = true
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	_war = SnakeWar.of(_p)
	_plan = [
		{"t": 0.2, "act": "stage"},
		{"t": 1.6, "act": "sample", "state": "base", "n": 4},
		{"t": 2.0, "act": "arm", "id": &"sb_gravity"},
		{"t": 2.6, "act": "sample", "state": "armed", "n": 4},
		{"t": 3.0, "act": "disarm"},
		{"t": 3.1, "act": "cast", "id": &"sv_shield"},
		{"t": 3.8, "act": "sample", "state": "shield", "n": 4},
		{"t": 4.0, "act": "hide"},
		{"t": 4.1, "act": "sample", "state": "shield_off", "n": 4},
		{"t": 4.3, "act": "show"},
		{"t": 4.4, "act": "stage"},
		{"t": 5.0, "act": "cast", "id": &"sv_net"},
		{"t": 5.5, "act": "sample", "state": "net", "n": 4},
		{"t": 5.7, "act": "hide"},
		{"t": 5.8, "act": "sample", "state": "net_off", "n": 4},
		{"t": 6.0, "act": "show"},
		{"t": 6.1, "act": "stage"},
		{"t": 6.6, "act": "cast", "id": &"sv_guard"},
		{"t": 7.4, "act": "sample", "state": "guard", "n": 4},
		{"t": 7.6, "act": "hide"},
		{"t": 7.7, "act": "sample", "state": "guard_off", "n": 4},
		{"t": 7.9, "act": "show"},
		{"t": 8.0, "act": "stage"},
		{"t": 8.5, "act": "cast", "id": &"sb_swarm"},
		{"t": 10.0, "act": "sample", "state": "swarm", "n": 5},
		{"t": 10.2, "act": "hide"},
		{"t": 10.3, "act": "sample", "state": "swarm_off", "n": 5},
		{"t": 10.5, "act": "show"},
		{"t": 10.6, "act": "stage"},
		{"t": 11.2, "act": "cast", "id": &"sv_shield"},
		{"t": 11.3, "act": "cast", "id": &"sv_guard"},
		{"t": 11.4, "act": "cast", "id": &"sv_net"},
		{"t": 11.5, "act": "cast", "id": &"sb_swarm"},
		{"t": 11.6, "act": "cast", "id": &"sb_coil"},
		{"t": 11.7, "act": "cast", "id": &"sb_storm"},
		{"t": 13.2, "act": "sample", "state": "worst", "n": 5},
		{"t": 13.4, "act": "hide"},
		{"t": 13.5, "act": "sample", "state": "worst_off", "n": 5},
		{"t": 13.7, "act": "show"},
		{"t": 13.8, "act": "stage"},
		{"t": 14.4, "act": "cast", "id": &"sb_flare"},
		{"t": 15.0, "act": "sample", "state": "marks", "n": 4},
		{"t": 15.2, "act": "stage"},
		{"t": 15.8, "act": "cast", "id": &"sb_mega"},
		{"t": 17.4, "act": "sample", "state": "mega", "n": 4},
		{"t": 18.4, "act": "end"},
	]
	print("SWPERF quality=", Game.quality, " res=", _p.get_viewport().get_visible_rect().size)


func step(t: float, delta: float) -> bool:
	if not _setup_done:
		if t > 2.0 and Game.player != null and Game.world != null:
			_setup()
		return false
	_t += delta
	Game.state = &"play"
	if SnakeSwarm.current != null:
		_peak_bodies = maxi(_peak_bodies, SnakeSwarm.current.count())
	if not _cur.is_empty():
		_samples.append(PerfProbe.snapshot(_p.get_viewport()))
		if _samples.size() >= int((_rows[_cur] as Dictionary)["n"]):
			var best := {"total_draws": 0, "total_prims": 0, "tex_mb": 0.0, "draws": 0, "prims": 0}
			for s: Dictionary in _samples:
				for k in best.keys():
					best[k] = maxf(float(best[k]), float(s.get(k, 0)))
			(_rows[_cur] as Dictionary)["snap"] = best
			(_rows[_cur] as Dictionary)["bodies"] = SnakeSwarm.current.count() if SnakeSwarm.current != null else 0
			(_rows[_cur] as Dictionary)["peak"] = _peak_bodies
			_cur = ""
			_samples.clear()
	while _pi < _plan.size() and float((_plan[_pi] as Dictionary)["t"]) <= _t:
		if _run(_plan[_pi] as Dictionary):
			return true
		_pi += 1
	return false


func _stage() -> void:
	if SnakeSwarm.current != null:
		SnakeSwarm.current.clear()
		SnakeSwarm.current.reset_stats()
	_peak_bodies = 0
	_war.reset()
	_war.cd.clear()
	_p.snake.energy = 100.0
	var mgr := Game.enemies as EnemyManager
	mgr.clear()
	_foes.clear()
	BlastOps.shared(_p.get_tree()).reset()
	_p.teleport_to(_spot)
	_p.camera_rig.reset_view(_yaw, -0.06)
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	for k in 3:
		var pos := _spot + fwd * 11.0 + right * (float(k - 1) * 2.4)
		var f := mgr.spawn(&"operative", pos, false)
		if f != null:
			f.set_physics_process(false)
			f.global_position = pos
			f.max_hp = 1.0e6
			f.hp = 1.0e6
			_foes.append(f)
	_p.camera_rig.aim_at(_spot + fwd * 11.0 + Vector3(0.0, 1.0, 0.0))


func _run(a: Dictionary) -> bool:
	match a["act"]:
		"stage":
			_stage()
		"arm":
			_war.arm(a["id"])
		"disarm":
			_war.disarm()
		"cast":
			_war.cd.clear()
			_war._gcd = 0.0
			_war.cast(a["id"], true)
		"hide":
			SnakeSwarm.current.visible = false
		"show":
			SnakeSwarm.current.visible = true
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
	for st: String in ["base", "armed", "shield", "net", "guard", "swarm", "worst", "marks", "mega"]:
		if not _rows.has(st) or not (_rows[st] as Dictionary).has("snap"):
			print("SWPERF %s no sample" % st)
			continue
		var r: Dictionary = _rows[st]
		var s: Dictionary = r["snap"]
		var line := "SWPERF %-6s bodies=%2d (peak %2d) visible draws=%d total draws=%d prims=%d tex=%.1f MB" % [st, int(r.get("bodies", 0)), int(r.get("peak", 0)), int(s["draws"]), int(s["total_draws"]), int(s["total_prims"]), float(s["tex_mb"])]
		if not base.is_empty():
			line += "   | vs base: %+d draws, %+d prims" % [int(s["total_draws"]) - int(base["total_draws"]), int(s["total_prims"]) - int(base["total_prims"])]
		var off := st + "_off"
		if _rows.has(off) and (_rows[off] as Dictionary).has("snap"):
			var o: Dictionary = (_rows[off] as Dictionary)["snap"]
			line += "   | free snakes cost: %+d draws, %+d prims (same view, SnakeSwarm hidden)" % [int(s["total_draws"]) - int(o["total_draws"]), int(s["total_prims"]) - int(o["total_prims"])]
		print(line)
	print("SWPERF SUMMARY done")
