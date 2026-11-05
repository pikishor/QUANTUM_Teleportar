class_name BenchmarkRun
extends Node
## RUN BENCHMARK (Options): a 30 second automatic run for the owner's phone (composed by main.gd, group "benchmark"). The hero is carried along ONE fixed route through the city
## (TIER_SECONDS per graphics tier: LOW+, LOW, MED, HIGH, always the same 400 m of road, the camera follows from behind like in play, the HUD and the world run as in a real game),
## every frame time is recorded, and at the end the result is one block of text: per tier min / avg / p95 FPS, draws, triangles, render CPU / GPU ms, plus device, GPU, renderer,
## resolution and temperature. It is written to user://benchmark.txt, put on the clipboard, appended to user://perf_log.txt and shown on a result panel with SEND REPORT and CLOSE.
##   min = 1000 / worst frame, avg = frames / seconds, p95 = FPS of the slowest 5 % of frames (1000 / the 95th percentile frame time).
## The first SETTLE seconds of every tier are not counted (the tier switch loads and releases textures; that hitch is one-off). The player's tier, resolution choice, state, hero position,
## god mode and the governor are restored afterwards. Any tap during the run cancels it. Pause rule: the run uses Game.state only (play while running, the previous state after).

signal finished(results: Dictionary)

const TIER_SECONDS := 7.5                    ## 4 tiers x 7.5 s = the 30 second run
const SETTLE := 1.5
const SPEED := 40.0                          ## metres per second along the route
const CAM_BACK := 5.5
const CAM_UP := 2.5
const RESULT_FILE := "user://benchmark.txt"
## Waypoints (x, z) on the road centre lines (x = 0 and x = 80 and z = 0 are roads of the grid), 400 m in all.
const ROUTE: Array[Vector2] = [Vector2(0.0, -200.0), Vector2(0.0, 0.0), Vector2(80.0, 0.0), Vector2(80.0, 120.0)]

static var last_text := ""                   ## the newest result (the perf report appends it)
static var active := false                   ## a run is in progress

var seconds_per_tier := TIER_SECONDS
var settle := SETTLE
var result_path := RESULT_FILE
var tiers: Array[int] = [0, 1, 2, 3]        ## Game.tier_index(): 0 LOW+, 1 LOW, 2 MED, 3 HIGH
var running := false
var panel_open := false
var results := {}                            ## tier -> {frames, min, avg, p95, draws, tris_k, gpu_ms, cpu_ms}
var copied := 0

var _tier_i := 0
var _t := 0.0
var _last_us := 0
var _frames := PackedFloat32Array()
var _draws := 0.0
var _tris := 0.0
var _cpu := 0.0
var _gpu := 0.0
var _samples := 0
var _snap_t := 0.0
var _saved := {}
var _layer: CanvasLayer
var _canvas: Control
var _po: PerfOverlay
var _temp_start := "n/a"
var _copied_t := 0.0


func _ready() -> void:
	add_to_group(&"benchmark")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_layer = CanvasLayer.new()
	_layer.layer = 90
	_layer.visible = false
	add_child(_layer)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_canvas)
	_canvas.draw.connect(_draw_ui)


# ---------------------------------------------------------------------------------------------------------------------
# route and statistics (pure)
# ---------------------------------------------------------------------------------------------------------------------

static func route_length() -> float:
	var n := 0.0
	for i in ROUTE.size() - 1:
		n += ROUTE[i].distance_to(ROUTE[i + 1])
	return n


## Position (y = 0) and unit heading at `dist` metres along the route (clamped to its ends).
static func route_point(dist: float) -> Dictionary:
	var d := clampf(dist, 0.0, route_length())
	for i in ROUTE.size() - 1:
		var seg := ROUTE[i].distance_to(ROUTE[i + 1])
		if d <= seg or i == ROUTE.size() - 2:
			var dir := (ROUTE[i + 1] - ROUTE[i]).normalized()
			var p := ROUTE[i] + dir * minf(d, seg)
			return {"pos": Vector3(p.x, 0.0, p.y), "dir": Vector3(dir.x, 0.0, dir.y)}
		d -= seg
	return {"pos": Vector3.ZERO, "dir": Vector3.FORWARD}


## min / avg / p95 FPS (and counts) of frame times in milliseconds.
static func stats(frame_ms: PackedFloat32Array) -> Dictionary:
	var n := frame_ms.size()
	if n == 0:
		return {"frames": 0, "min": 0.0, "avg": 0.0, "p95": 0.0}
	var a := frame_ms.duplicate()
	a.sort()
	var total := 0.0
	for v in a:
		total += v
	var p95 := a[clampi(int(ceil(0.95 * n)) - 1, 0, n - 1)]
	return {"frames": n, "min": 1000.0 / maxf(a[n - 1], 0.001), "avg": 1000.0 * n / maxf(total, 0.001), "p95": 1000.0 / maxf(p95, 0.001)}


# ---------------------------------------------------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------------------------------------------------

## Starts the run. False when one is already running or there is no hero to carry.
func start() -> bool:
	if running or not is_instance_valid(Game.player):
		return false
	var p := Game.player as Player
	if p == null or not is_instance_valid(p.camera_rig):
		return false
	_po = get_tree().get_first_node_in_group(&"perf_overlay") as PerfOverlay
	_saved = {"state": Game.state, "tier": Game.tier_index(), "pos": p.global_position, "god": TestMode.god, "heat": TestMode.no_heat, "aq": null, "aq_on": true}
	for n in get_parent().get_children():
		if n is AutoQuality:
			_saved["aq"] = n
			_saved["aq_on"] = (n as AutoQuality).enabled
			(n as AutoQuality).enabled = false           # the governor must not drop a tier in the middle of a measurement
	TestMode.god = true
	TestMode.no_heat = true
	running = true
	active = true
	panel_open = false
	results.clear()
	_tier_i = 0
	_temp_start = _po.thermal_text() if _po != null else "n/a"
	if _po != null:
		_po.set_measure(true)
	_begin_tier()
	Game.state = &"play"
	_layer.visible = true
	set_process(true)
	_canvas.queue_redraw()
	return true


func _begin_tier() -> void:
	_t = 0.0
	_frames.clear()
	_draws = 0.0
	_tris = 0.0
	_cpu = 0.0
	_gpu = 0.0
	_samples = 0
	_snap_t = 0.0
	Game.set_tier_index(tiers[_tier_i])         # loads / releases the tier's textures: a one-off hitch that must not count as route time
	_last_us = Time.get_ticks_usec()


func _process(delta: float) -> void:
	if _copied_t > 0.0:
		_copied_t -= delta
		_canvas.queue_redraw()
	if not running:
		if not panel_open and _copied_t <= 0.0:
			set_process(false)
		return
	var now := Time.get_ticks_usec()
	var dt := float(now - _last_us) / 1e6
	_last_us = now
	_t += dt
	_carry(minf(_t, seconds_per_tier))
	if _t >= settle:
		if dt < 1.0:
			_frames.append(dt * 1000.0)
		_snap_t -= dt
		if _snap_t <= 0.0:
			_snap_t = 0.25
			_sample_render()
	if _t >= seconds_per_tier:
		_end_tier()
	_canvas.queue_redraw()


## The hero and the camera at `t` seconds into the tier's slice of the route.
func _carry(t: float) -> void:
	var p := Game.player as Player
	if not is_instance_valid(p):
		return
	var rp := route_point(t * SPEED)
	var pos: Vector3 = rp["pos"]
	var dir: Vector3 = rp["dir"]
	p.global_position = pos + Vector3(0.0, 0.1, 0.0)
	p.velocity = Vector3.ZERO
	if is_instance_valid(p.camera_rig):
		var cam := pos - dir * CAM_BACK + Vector3(0.0, CAM_UP, 0.0)
		p.camera_rig.cine_set(Transform3D(Basis.looking_at(pos + dir * 12.0 + Vector3(0.0, 1.2, 0.0) - cam, Vector3.UP), cam), 92.0)


func _sample_render() -> void:
	var s := PerfProbe.snapshot(get_viewport())
	_draws += float(s["total_draws"])
	_tris += float(s["total_prims"])
	if _po != null:
		var m := _po.systems()
		_cpu += float(m["render_cpu"])
		_gpu += float(m["render_gpu"])
	_samples += 1


func _end_tier() -> void:
	var st := stats(_frames)
	var k := float(maxi(_samples, 1))
	st["draws"] = roundi(_draws / k)
	st["tris_k"] = roundi(_tris / k / 1000.0)
	st["cpu_ms"] = _cpu / k
	st["gpu_ms"] = _gpu / k
	results[tiers[_tier_i]] = st
	_tier_i += 1
	if _tier_i >= tiers.size():
		_finish(true)
	else:
		_begin_tier()


## Cancels a run (a tap): what was measured so far is dropped, everything is restored.
func cancel() -> void:
	if running:
		_finish(false)


func _finish(completed: bool) -> void:
	running = false
	active = false
	var p := Game.player as Player
	if is_instance_valid(p):
		p.global_position = _saved.get("pos", p.global_position)
		p.velocity = Vector3.ZERO
		if is_instance_valid(p.camera_rig):
			p.camera_rig.cine_clear()
			p.camera_rig.snap()
	TestMode.god = bool(_saved.get("god", false))
	TestMode.no_heat = bool(_saved.get("heat", false))
	var aq: Variant = _saved.get("aq")
	if aq != null and is_instance_valid(aq):
		(aq as AutoQuality).enabled = bool(_saved.get("aq_on", true))
	Game.set_tier_index(int(_saved.get("tier", Game.tier_index())))
	if _po != null:
		_po.set_measure(false)
	var prev: StringName = _saved.get("state", &"menu")
	Game.state = prev
	if not completed:
		_layer.visible = false
		_canvas.queue_redraw()
		return
	last_text = result_text()
	_write_result()
	panel_open = true
	_layer.visible = true
	set_process(true)
	_canvas.queue_redraw()
	finished.emit(results)


## The block the owner sends.
func result_text() -> String:
	var vp := get_viewport()
	var out := PackedStringArray()
	out.append("QUANTUM TELEPORT benchmark (%d s fixed route, %d m)" % [roundi(seconds_per_tier * tiers.size()), roundi(route_length())])
	out.append("Device: %s | OS %s %s" % [OS.get_model_name(), OS.get_name(), OS.get_version()])
	out.append("GPU: %s | renderer %s / %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()])
	out.append("Window %s | render scale %.2f (%s) | temperature %s -> %s" % [str(Vector2i(vp.get_visible_rect().size)), vp.scaling_3d_scale, RenderRes.mode_name(RenderRes.mode()), _temp_start,
		_po.thermal_text() if _po != null else "n/a"])
	for t in tiers:
		if not results.has(t):
			continue
		var r: Dictionary = results[t]
		out.append("%-5s min %d  avg %d  p95 %d FPS | draws %d  tris %dk | render cpu %.1f gpu %.1f ms | %d frames" % [Game.TIER_LABELS[t], roundi(r["min"]), roundi(r["avg"]), roundi(r["p95"]),
			r["draws"], r["tris_k"], r["cpu_ms"], r["gpu_ms"], r["frames"]])
	return "\n".join(out) + "\n"


func _write_result() -> void:
	var f := FileAccess.open(result_path, FileAccess.WRITE)
	if f != null:
		f.store_string(last_text)
	if _po != null:
		_po.log_line("BENCHMARK\n" + last_text)


## SEND REPORT on the result panel: the benchmark block plus the device report, on the clipboard and in user://perf_report.txt.
func send() -> String:
	copied += 1
	_copied_t = 2.0
	var r := last_text
	if _po != null:
		r = _po.copy_report()                    # includes last_text
	elif DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(r)
	_canvas.queue_redraw()
	return r


func close_panel() -> void:
	panel_open = false
	_layer.visible = running
	_canvas.queue_redraw()


# ---------------------------------------------------------------------------------------------------------------------
# input and drawing (the run and the result panel own every touch while they show: this node is added after the HUD, so it sees input first)
# ---------------------------------------------------------------------------------------------------------------------

func _scale() -> float:
	return UiUtil.ui_scale(get_viewport().get_visible_rect().size)


func panel_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var s := _scale()
	var w := minf(vp.x - 40.0 * s, 700.0 * s)
	var h := minf(vp.y - 30.0 * s, 330.0 * s)
	return Rect2((vp - Vector2(w, h)) * 0.5, Vector2(w, h))


func send_rect() -> Rect2:
	var r := panel_rect()
	var s := _scale()
	return Rect2(r.position + Vector2(r.size.x * 0.5 - 250.0 * s, r.size.y - 82.0 * s), Vector2(240.0, 68.0) * s)


func close_rect() -> Rect2:
	var s := _scale()
	return Rect2(send_rect().position + Vector2(260.0 * s, 0.0), Vector2(240.0, 68.0) * s)


## A press at `pos`: cancels a run, or presses a result button. Returns true when it was taken.
func press_at(pos: Vector2) -> bool:
	if running:
		cancel()
		return true
	if not panel_open:
		return false
	if send_rect().has_point(pos):
		send()
	elif close_rect().has_point(pos):
		close_panel()
	return true


func _input(event: InputEvent) -> void:
	if not running and not panel_open:
		return
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		pos = (event as InputEventScreenTouch).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		pos = (event as InputEventMouseButton).position
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		pos = Vector2(-1.0, -1.0)                       # a key cancels a run and closes the panel
	else:
		if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton or event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	if pos.x < 0.0:
		if running:
			cancel()
		elif panel_open:
			close_panel()
		return
	press_at(pos)


func _draw_ui() -> void:
	if not running and not panel_open:
		return
	var c := _canvas
	var vp := get_viewport().get_visible_rect().size
	var s := _scale()
	var font := UiUtil.font()
	if running:
		var tier_name: String = Game.TIER_LABELS[tiers[clampi(_tier_i, 0, tiers.size() - 1)]]
		var done := (float(_tier_i) * seconds_per_tier + minf(_t, seconds_per_tier)) / (seconds_per_tier * tiers.size())
		var bar := Rect2(Vector2(vp.x * 0.5 - 220.0 * s, 28.0 * s), Vector2(440.0, 64.0) * s)
		c.draw_rect(bar, Color(0.0, 0.03, 0.06, 0.72))
		c.draw_rect(Rect2(bar.position, Vector2(bar.size.x * done, 6.0 * s)), Color(0.4, 0.95, 1.0, 0.95))
		c.draw_string(font, bar.position + Vector2(0.0, 34.0 * s), "BENCHMARK  %s  %d%%" % [tier_name, roundi(done * 100.0)], HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, int(24.0 * s), Color(1, 1, 1, 0.97))
		c.draw_string(font, bar.position + Vector2(0.0, 56.0 * s), "TAP TO CANCEL", HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, int(14.0 * s), Color(0.8, 0.95, 1.0, 0.8))
		return
	var r := panel_rect()
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.62))
	c.draw_rect(r, Color(0.02, 0.05, 0.09, 0.96))
	c.draw_rect(r, Color(0.4, 0.9, 1.0, 0.7), false, 2.0 * s)
	c.draw_string(font, r.position + Vector2(0.0, 40.0 * s), "BENCHMARK RESULT", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(28.0 * s), Color(1, 1, 1, 0.97))
	var lines := last_text.split("\n")
	var y := 74.0
	for i in range(lines.size()):
		if lines[i] == "" or (i > 0 and i < 4):
			continue                                      # the title and the device lines are in the file, the panel shows the numbers
		c.draw_string(font, r.position + Vector2(18.0, y) * s, lines[i], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 36.0 * s, int(16.0 * s), Color(0.85, 1.0, 0.92, 0.97))
		y += 30.0
	for pair in [[send_rect(), "COPIED" if _copied_t > 0.0 else "SEND REPORT", Color(0.1, 0.4, 0.5, 0.95)], [close_rect(), "CLOSE", Color(0.18, 0.2, 0.26, 0.95)]]:
		var br: Rect2 = pair[0]
		c.draw_rect(br, pair[2])
		c.draw_rect(br, Color(1, 1, 1, 0.5), false, 1.5 * s)
		c.draw_string(font, br.position + Vector2(0.0, br.size.y * 0.62), pair[1], HORIZONTAL_ALIGNMENT_CENTER, br.size.x, int(24.0 * s), Color(1, 1, 1, 0.97))
