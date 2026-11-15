extends RefCounted
## SNAKE first-use probe of the wave 115 PLAY critic (copied from tests/bot_warm.gd, same method): how many pipelines compile and how long is the longest frame the first time a swing, a zip, a climb, a flight, a boost, each verb and a bomb is drawn?
## First-use frame-time probe (tools/warm_probe.sh): how much longer than a steady frame is the frame that first draws a shot, an enemy, a blast, a quantum effect, the pause screen?
## Run with `--fixed-fps 30` (the game advances 1/30 s per rendered frame whatever the renderer's speed) and compare wall-clock frame times: software Vulkan (llvmpipe) compiles
## every new pipeline with LLVM, so a first use shows as tens to hundreds of milliseconds there, just like it stalls a phone GPU driver.
##   env WARM=1  run ShaderWarmup.run() first (what main.gd does behind the loading overlay);  WARM=0 (default) does not.
## Prints `WARM probe <label> max_ms=.. ratio=.. compiles=N` per trigger and `WARM RESULT warm=.. steady_ms=.. worst_ms=.. worst=<label> sum_excess_ms=.. total_first_use_ms=.. compiles=N`.
## `compiles` is the number of pipelines the renderer compiled in that window (RenderingServer pipeline-compilation counters): the deterministic version of a hitch, and what the
## pre-warm drives to (almost) zero. Wall-clock milliseconds are noisy on a shared software renderer; the compile counts are not.

const Fixture := preload("res://tests/player_fixture.gd")
const STEADY_FROM := 45
const STEADY_TO := 75
const WINDOW := 9                 ## frames watched after a trigger
const GAP := 4                    ## quiet frames between two triggers

var _warm := false
var _f := 0
var _last_us := 0
var _setup_done := false
var _steady: Array[float] = []
var _p: Player
var _drones: Array = []
var _steps: Array = []            ## [label, Callable, window]
var _idx := -1
var _next_at := 0
var _win_start := -1
var _win_max := 0.0
var _win_len := 0
var _results: Array = []
var _steady_ms := 1.0
var _compiles_start := 0
var _compiles_total := 0
var _compiles_boot := 0


func _init() -> void:
	_warm = OS.get_environment("WARM") == "1"


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	Game.enemies.patrol_groups().clear()
	Game.enemies.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TrafficField.bare_street()
	_p.invuln = 1.0e6
	_p.hp = _p.max_hp
	TestMode.god = true
	WeaponDefs.hero_mode = true
	_p.teleport_to(Game.SPAWN)
	_p.camera_rig.reset_view(-PI * 0.5, -0.1)
	_p.yaw = -PI * 0.5
	if _warm:
		ShaderWarmup.run(Dev, true)                # runs on across frames (awaits process_frame); finished is set when everything is back
	var sn := _p.snake
	var war := SnakeWar.of(_p)
	var spawn_foes := func() -> void:
		Game.enemies.clear()
		_drones.clear()
		for i in 3:
			_drones.append(Game.enemies.spawn(&"operative", _p.global_position + Vector3(-8.0 - 2.0 * i, 0.0, 0.0), true))
	var aim_foe := func() -> void:
		if not _drones.is_empty() and is_instance_valid(_drones[0]):
			_p.camera_rig.aim_at(SnakeAim.center_of(_drones[0] as Node3D))
	var fx := _p.get_node("SnakeFx") as SnakeFx
	var cam := Game.camera
	var ahead := func(d: float, up := 0.0) -> Vector3:
		return cam.global_position - cam.global_basis.z * d + Vector3(0.0, up, 0.0)
	_steps = [
		["idle", func() -> void: pass, 12],
		["tendril", func() -> void:
			var t := SnakeTendril.fire(ahead.call(3.0, -1.0), ahead.call(9.0, 2.0), {"travel": 0.05, "host": _p, "life": 2.0})
			t.user["keep"] = true, 20],
		["tendril2", func() -> void:
			SnakeTendril.fire(ahead.call(3.0, -1.0), ahead.call(11.0, 3.0), {"travel": 0.05, "host": _p, "life": 2.0, "head": false, "thickness": 0.05, "color": Color(1.0, 0.4, 0.8)}), 12],
		["swarm_coil", func() -> void:
			var sw := SnakeSwarm.get_swarm(_p)
			sw.spawn(&"coil", ahead.call(6.0, -1.0), {"radius": 0.7, "life": 2.0, "len": 6.0, "y0": 0.1, "y1": 2.0, "turns": 2.0}), 20],
		["swarm_ball", func() -> void:
			var sw := SnakeSwarm.get_swarm(_p)
			sw.spawn(&"ball", ahead.call(6.0, 1.0), {"radius": 0.5, "life": 2.0, "len": 3.0}), 12],
		["swarm_orbit", func() -> void:
			var sw := SnakeSwarm.get_swarm(_p)
			sw.spawn(&"orbit", _p.global_position, {"anchor": _p, "radius": 1.2, "life": 2.0, "len": 3.0}), 12],
		["lines", func() -> void:
			_p.snake.cam.speed_lines = 1.0
			fx._ensure_lines()
			fx._rect.visible = true
			fx._lmat.set_shader_parameter("amount", 1.0), 12],
		["lines_off", func() -> void:
			fx._rect.visible = false
			_p.snake.cam.speed_lines = 0.0, 6],
		["marker", func() -> void:
			fx._ensure_marker()
			fx._marker.global_position = ahead.call(8.0, 1.0)
			fx._mmat.set_shader_parameter("alpha", 0.75)
			fx._marker.visible = true, 12],
		["marker_off", func() -> void: fx._marker.visible = false, 6],
		["armed_net", func() -> void:
			war.arm(&"sv_net"), 20],
		["armed_bomb", func() -> void:
			war.arm(&"sb_coil"), 20],
		["hands_glow", func() -> void:
			war.disarm()
			HeroLook.pulse_glow(Color(0.5, 1.0, 1.0), 1.0, 0.4), 12],
		["done", func() -> void: war.disarm(), 6],
	]


static func _compiles() -> int:
	var rs := RenderingServer
	return rs.get_rendering_info(rs.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS) + rs.get_rendering_info(rs.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH) \
			+ rs.get_rendering_info(rs.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE) + rs.get_rendering_info(rs.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW) \
			+ rs.get_rendering_info(rs.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION)


func _median(a: Array[float]) -> float:
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2] if b.size() > 0 else 1.0


func step(_t: float, _d: float) -> bool:
	if Game.player == null or Game.enemies == null or Game.vehicles == null:
		return false
	if not _setup_done:
		_setup()
	_f += 1
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0 if _last_us > 0 else 0.0
	_last_us = now
	if _f >= STEADY_FROM and _f < STEADY_TO:
		_steady.append(ms)
	if _f == STEADY_TO:
		_steady_ms = maxf(_median(_steady), 1.0)
		_compiles_boot = _compiles()
		print("WARM steady frame %.1f ms (median of %d), warm-up %s, %d pipelines compiled until now" % [_steady_ms, _steady.size(), "ran" if _warm else "off", _compiles_boot])
		_next_at = _f + 2
	if _f < STEADY_TO:
		return false
	if _f > STEADY_TO and _win_start >= 0:
		_win_max = maxf(_win_max, ms)
		if _f - _win_start >= _win_len:
			var label: String = _steps[_idx][0]
			var comp := _compiles() - _compiles_start
			_compiles_total += comp
			_results.append([label, _win_max])
			print("WARM probe %-12s max_ms=%7.1f ratio=%5.1f compiles=%d" % [label, _win_max, _win_max / _steady_ms, comp])
			_win_start = -1
			_next_at = _f + GAP
	if _win_start < 0 and _f >= _next_at:
		_idx += 1
		if _idx >= _steps.size():
			Fixture.release_inputs()
			var worst := 0.0
			var worst_label := ""
			var excess := 0.0
			var first := 0.0
			for r in _results:
				if float(r[1]) > worst:
					worst = float(r[1])
					worst_label = r[0]
				excess += maxf(0.0, float(r[1]) - _steady_ms)
				first += float(r[1])
			print("WARM RESULT warm=%d steady_ms=%.1f worst_ms=%.1f worst=%s sum_excess_ms=%.0f total_first_use_ms=%.0f compiles=%d" % [1 if _warm else 0, _steady_ms, worst, worst_label, excess, first, _compiles_total])
			return true
		_compiles_start = _compiles()
		(_steps[_idx][1] as Callable).call()
		_win_start = _f
		_win_len = int(_steps[_idx][2])
		_win_max = 0.0
	return false
