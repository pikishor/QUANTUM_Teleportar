extends RefCounted
## First-use frame-time probe (tools/warm_probe.sh): how much longer than a steady frame is the frame that first draws a shot, an enemy, a blast, a quantum effect, the pause screen?
## Run with `--fixed-fps 30` (the game advances 1/30 s per rendered frame whatever the renderer's speed) and compare wall-clock frame times: software Vulkan (llvmpipe) compiles
## every new pipeline with LLVM, so a first use shows as tens to hundreds of milliseconds there, just like it stalls a phone GPU driver.
##   env WARM=1  run ShaderWarmup.run() first (what main.gd does behind the loading overlay);  WARM=0 (default) does not.
## Prints `WARM probe <label> max_ms=.. ratio=..` per trigger and `WARM RESULT warm=.. steady_ms=.. worst_ms=.. worst=<label> sum_excess_ms=.. total_first_use_ms=..`.

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


func _init() -> void:
	_warm = OS.get_environment("WARM") == "1"


func _setup() -> void:
	_setup_done = true
	_p = Game.player as Player
	Game.enemies.patrol_groups().clear()
	Game.enemies.clear()
	_p.invuln = 1.0e6
	_p.hp = _p.max_hp
	_p.energy = _p.max_energy
	_p.teleport_to(Game.SPAWN)
	_p.camera_rig.reset_view(-PI * 0.5, -0.1)
	_p.yaw = -PI * 0.5
	if _warm:
		ShaderWarmup.run(Dev, true)                # runs on across frames (awaits process_frame); finished is set when everything is back
	var q: Node = _p.quantum
	_steps = [
		["shot", func() -> void: Input.action_press(&"fire"), 6],
		["enemies", func() -> void:
			Input.action_release(&"fire")
			var types: Array = [&"sentinel", &"operative", &"operative", &"sentinel"]
			for i in 4:
				_drones.append(Game.enemies.spawn(types[i], Game.SPAWN + Vector3(14.0 + 3.0 * i, 0.0, -6.0 + 4.0 * i), true)), 16],
		["hit", func() -> void: (_drones[0] as Drone).damage(5.0), 8],
		["kill4", func() -> void:
			for d in _drones:
				if is_instance_valid(d):
					(d as Drone).damage(9999.0), 18],
		["wreck", func() -> void: Game.explode(Game.SPAWN + Vector3(12.0, 0.0, -3.0), 9.0, {"enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0}), 18],
		["beacon", func() -> void: q.blink(), 8],
		["teleport", func() -> void: q.blink(), 8],
		["link", func() -> void:
			Game.enemies.clear()
			for i in 2:
				_drones.append(Game.enemies.spawn(&"sentinel", Game.SPAWN + Vector3(14.0 + 3.0 * i, 0.0, -3.0 + 3.0 * i), true))
			_p.energy = _p.max_energy
			q.entangle(), 10],
		["superpose", func() -> void:
			_p.energy = _p.max_energy
			q.superpose(), 10],
		["collapse", func() -> void: q.collapse(), 12],
		["pause_screen", func() -> void: Game.state = &"paused", 8],
		["resume", func() -> void: Game.state = &"play", 6],
	]


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
		print("WARM steady frame %.1f ms (median of %d), warm-up %s" % [_steady_ms, _steady.size(), "ran" if _warm else "off"])
		_next_at = _f + 2
	if _f < STEADY_TO:
		return false
	if _f > STEADY_TO and _win_start >= 0:
		_win_max = maxf(_win_max, ms)
		if _f - _win_start >= _win_len:
			var label: String = _steps[_idx][0]
			_results.append([label, _win_max])
			print("WARM probe %-12s max_ms=%7.1f ratio=%5.1f" % [label, _win_max, _win_max / _steady_ms])
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
			print("WARM RESULT warm=%d steady_ms=%.1f worst_ms=%.1f worst=%s sum_excess_ms=%.0f total_first_use_ms=%.0f" % [1 if _warm else 0, _steady_ms, worst, worst_label, excess, first])
			return true
		(_steps[_idx][1] as Callable).call()
		_win_start = _f
		_win_len = int(_steps[_idx][2])
		_win_max = 0.0
	return false
