class_name PerfTimers
extends RefCounted
## Per-system CPU timers (script time in ms per frame). Where the frame time of a phone really goes: the draw count and the triangle count say nothing about the script work of the HUD,
## the crowd, the enemy AI, the minimap or the effects. Every hot system wraps its tick in
##     var t0 := PerfTimers.start()
##     ... work ...
##     PerfTimers.stop(PerfTimers.HUD, t0)
## The cost of a pair is two clock reads and one array add (no allocation). A system that is called several times per frame (physics ticks, many enemies) adds up inside the frame.
## `roll()` (SceneTree.process_frame, installed by `install()`) moves the finished frame into a smoothed average (`avg_ms`) and a worst value (`peak_ms`).
## Custom Performance monitors `quantum/<id>_ms` expose the averages to the engine's monitor panel; `table()` is the text table the PerfOverlay report, the touch debug panel and
## tools/perf_report.sh print. Everything can be switched off with `enabled = false` (the pair then costs one branch).

const HUD := 0                  ## hud.gd play layer redraw (the whole HUD _draw)
const SCREEN := 1               ## hud.gd menu / screen layer redraw
const MINIMAP := 2              ## minimap.gd _draw
const TOUCH := 3                ## touch_controls.gd _draw_ui
const CROWD := 4                ## ambient crowd (MultiMesh people) step
const NPC := 5                  ## citizen schedules / reactions
const CITIZENS := 6             ## promoted citizen actors
const FAUNA := 7                ## flocks and crawlers
const SKY := 8                  ## airship / patrol sky traffic
const ENEMY_AI := 9             ## every enemy's own tick (drone.gd / operative.gd physics)
const ENEMY_MGR := 10           ## EnemyManager (marks, LOD, sweep, heat, bolts)
const VEHICLES := 11            ## VehicleManager + traffic cars
const PLAYER := 12              ## Player tick + body update
const EFFECTS := 13             ## explosion pool, quantum VFX, atmosphere, breakables debris, FX autoload
const WORLD := 14               ## city streaming, prop colliders, day / night
const MISSIONS := 15            ## missions, events, wanted, story, quantum verbs
const AUDIO := 16               ## Sfx / music director work
const COUNT := 17

const NAMES: PackedStringArray = ["HUD", "SCREEN", "MINIMAP", "TOUCH", "CROWD", "NPC", "CITIZENS", "FAUNA", "SKY", "ENEMY AI", "ENEMY MGR", "VEHICLES", "PLAYER", "EFFECTS", "WORLD", "MISSIONS", "AUDIO"]
const KEYS: PackedStringArray = ["hud", "screen", "minimap", "touch", "crowd", "npc", "citizens", "fauna", "sky", "enemy_ai", "enemy_mgr", "vehicles", "player", "effects", "world", "missions", "audio"]
const SMOOTH := 0.1             ## weight of the newest frame in the average

static var enabled := true
static var frames := 0
static var _acc := PackedFloat64Array()       ## microseconds of the running frame
static var _avg := PackedFloat64Array()       ## smoothed ms of one frame
static var _peak := PackedFloat64Array()      ## worst frame in ms since `reset_peaks`
static var _calls := PackedInt32Array()       ## number of timed spans per system since `reset` (a HUD that redraws 20 times a second shows 20 per second here)
static var _installed := false
static var _tree_id := 0


static func _ensure() -> void:
	if _acc.size() != COUNT:
		_acc.resize(COUNT)
		_avg.resize(COUNT)
		_peak.resize(COUNT)
		_calls.resize(COUNT)


## The start stamp (microseconds); 0 when the timers are off, so `stop` skips the work.
static func start() -> int:
	return Time.get_ticks_usec() if enabled else 0


static func stop(id: int, t0: int) -> void:
	if t0 == 0:
		return
	if _acc.size() != COUNT:
		_ensure()
	_acc[id] += float(Time.get_ticks_usec() - t0)
	_calls[id] += 1


## Add a measured span directly (a system that times itself).
static func add_us(id: int, us: float) -> void:
	if _acc.size() != COUNT:
		_ensure()
	_acc[id] += us
	_calls[id] += 1


## Close the running frame into the averages. Called once per rendered frame (process_frame).
static func roll() -> void:
	_ensure()
	frames += 1
	for i in COUNT:
		var ms := _acc[i] / 1000.0
		_avg[i] = ms if frames <= 2 else lerpf(_avg[i], ms, SMOOTH)
		if ms > _peak[i]:
			_peak[i] = ms
		_acc[i] = 0.0


static func avg_ms(id: int) -> float:
	_ensure()
	return _avg[id]


static func peak_ms(id: int) -> float:
	_ensure()
	return _peak[id]


## Total of the timed systems (they do not overlap, except where a comment says so).
static func total_ms() -> float:
	_ensure()
	var t := 0.0
	for i in COUNT:
		t += _avg[i]
	return t


static func reset() -> void:
	_ensure()
	frames = 0
	for i in COUNT:
		_acc[i] = 0.0
		_avg[i] = 0.0
		_peak[i] = 0.0
		_calls[i] = 0


## Timed spans of a system since the last `reset` (tests: how often the HUD really redrew).
static func calls(id: int) -> int:
	_ensure()
	return _calls[id]


static func reset_peaks() -> void:
	_ensure()
	for i in COUNT:
		_peak[i] = 0.0


## The ids ordered by their smoothed cost, worst first.
static func ranked() -> Array[int]:
	_ensure()
	var ids: Array[int] = []
	for i in COUNT:
		ids.append(i)
	ids.sort_custom(func(a: int, b: int) -> bool: return _avg[a] > _avg[b])
	return ids


## The text table: the `top` most expensive systems (avg and worst ms) and the engine's own process / physics times.
static func table(top: int = COUNT) -> String:
	_ensure()
	var out := PackedStringArray()
	out.append("CPU ms per frame (avg / worst), timed total %.2f" % total_ms())
	var n := 0
	for id in ranked():
		if n >= top:
			break
		if _avg[id] < 0.005 and _peak[id] < 0.05:
			continue
		out.append("  %-10s %6.2f / %6.2f" % [NAMES[id], _avg[id], _peak[id]])
		n += 1
	return "\n".join(out)


## One line for the logs: the top three systems.
static func top_line(top: int = 3) -> String:
	_ensure()
	var parts := PackedStringArray()
	for id in ranked():
		if parts.size() >= top:
			break
		parts.append("%s %.2f" % [NAMES[id], _avg[id]])
	return "cpu %.1fms [%s]" % [total_ms(), ", ".join(parts)]


static func _monitor(id: int) -> float:
	return avg_ms(id)


## Hook the timers to a tree: rolls the frame on `process_frame` and registers the custom Performance monitors (once per process).
static func install(tree: SceneTree) -> void:
	_ensure()
	if tree == null:
		return
	if _tree_id != tree.get_instance_id():
		_tree_id = tree.get_instance_id()
		if not tree.process_frame.is_connected(roll):
			tree.process_frame.connect(roll)
	if _installed:
		return
	_installed = true
	for i in COUNT:
		var mon := "quantum/%s_ms" % KEYS[i]
		if not Performance.has_custom_monitor(mon):
			Performance.add_custom_monitor(mon, PerfTimers._monitor.bind(i))
