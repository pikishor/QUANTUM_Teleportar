class_name PerfOverlay
extends Node
## Phone profiling hooks (composed by main.gd, group "perf_overlay"). Records real frame times while playing (ring buffer, no draws, no nodes), and builds a device report:
## frame time percentiles, draws, triangles, nodes, memory, tier, GPU / renderer, battery. The touch controls show it under the FPS box when the debug panel is open
## (long-press the FPS box) with a COPY REPORT button (clipboard). Everything is also appended to user://perf_log.txt (session header, a sample line every LOG_EVERY seconds,
## governor drops, copies), so the owner can send real device numbers. Thermal state: Godot has no API for it, the report says so.

const LOG_FILE := "user://perf_log.txt"
const LOG_MAX_BYTES := 200000
const SAMPLES := 600
const LOG_EVERY := 30.0
const TIER_NAMES := ["LOW", "MED", "HIGH"]

var log_path := LOG_FILE
var samples := PackedFloat32Array()      ## frame times in ms, newest last (ring)
var frames_total := 0
var copies := 0
var governor_events := 0

var _head := 0
var _last_us := 0
var _log_t := 0.0
var _session_logged := false


func _ready() -> void:
	add_to_group(&"perf_overlay")
	process_mode = Node.PROCESS_MODE_ALWAYS
	samples.resize(SAMPLES)
	var aq := get_parent().get_node_or_null(^"AutoQuality") if get_parent() != null else null
	if aq == null and get_parent() != null:
		for c in get_parent().get_children():
			if c is AutoQuality:
				aq = c
	if aq != null:
		(aq as AutoQuality).lowered.connect(on_governor_lowered)
	_last_us = Time.get_ticks_usec()


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt_ms := float(now - _last_us) / 1000.0
	_last_us = now
	if Game.state != &"play":
		return
	if dt_ms > 1000.0:                          # a load or a pause hitch is not a frame time
		return
	record(dt_ms)
	_log_t += delta / maxf(Engine.time_scale, 0.05)
	if _log_t >= LOG_EVERY:
		_log_t = 0.0
		log_line("SAMPLE " + summary())


## One frame time in ms (tests feed it directly).
func record(ms: float) -> void:
	samples[_head] = ms
	_head = (_head + 1) % SAMPLES
	frames_total += 1


func count() -> int:
	return mini(frames_total, SAMPLES)


## Percentile (0..100) of the recorded frame times in ms; 0 with no samples.
func percentile(p: float) -> float:
	var n := count()
	if n == 0:
		return 0.0
	var a := samples.slice(0, n) if frames_total < SAMPLES else samples.duplicate()
	a.sort()
	return a[clampi(int(ceil(p / 100.0 * n)) - 1, 0, n - 1)]


func worst_ms() -> float:
	var n := count()
	var w := 0.0
	for i in n:
		w = maxf(w, samples[i])
	return w


func summary() -> String:
	var s := PerfProbe.snapshot(get_viewport())
	return "t=%d fps=%d p50=%.1f p95=%.1f p99=%.1f worst=%.1fms draws=%d tris=%dk nodes=%d mem=%dMB tier=%s" % [Time.get_ticks_msec() / 1000, roundi(Engine.get_frames_per_second()),
		percentile(50), percentile(95), percentile(99), worst_ms(), s["total_draws"], int(s["total_prims"]) / 1000, s["nodes"], mem_mb(), tier_name()]


func tier_name() -> String:
	return TIER_NAMES[clampi(Game.quality, 0, 2)]


func mem_mb() -> int:
	return int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)


func battery_text() -> String:
	return "n/a (no engine API)"


## The full text report: what the owner sends.
func report() -> String:
	var s := PerfProbe.snapshot(get_viewport())
	var out := PackedStringArray()
	out.append("QUANTUM TELEPORT perf report")
	out.append("Device: %s | OS %s %s" % [OS.get_model_name(), OS.get_name(), OS.get_version()])
	out.append("GPU: %s (%s) | renderer %s / %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()])
	out.append("Viewport %s | tier %s | quality drops by governor %d" % [str(Vector2i(get_viewport().get_visible_rect().size)), tier_name(), governor_events])
	out.append("Frame ms (last %d): p50 %.1f  p95 %.1f  p99 %.1f  worst %.1f | FPS now %d" % [count(), percentile(50), percentile(95), percentile(99), worst_ms(), roundi(Engine.get_frames_per_second())])
	out.append("Draws %d  Tris %dk  Nodes %d  Objects %d" % [s["total_draws"], int(s["total_prims"]) / 1000, s["nodes"], s["objects"]])
	out.append("Memory: static %d MB, textures %d MB, buffers %d MB" % [mem_mb(), roundi(s["tex_mb"]), roundi(s["buf_mb"])])
	out.append("Battery: %s | Thermal: n/a (no engine API)" % battery_text())
	return "\n".join(out) + "\n"


## COPY REPORT: clipboard plus the log. Returns the text.
func copy_report() -> String:
	var r := report()
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(r)
	copies += 1
	log_line("COPY\n" + r)
	return r


func on_governor_lowered(level: int) -> void:
	governor_events += 1
	log_line("GOVERNOR lowered to %s | %s" % [TIER_NAMES[clampi(level, 0, 2)], summary()])


## Appends a timestamped line; the file is cut to its newest half past LOG_MAX_BYTES.
func log_line(text: String) -> void:
	if not _session_logged:
		_session_logged = true
		_append("SESSION START %s | %s | %s %s | tier %s" % [Time.get_datetime_string_from_system(), OS.get_model_name(), RenderingServer.get_video_adapter_name(),
			RenderingServer.get_current_rendering_method(), tier_name()])
	_append(text)


func _append(text: String) -> void:
	if FileAccess.file_exists(log_path) and FileAccess.get_file_as_bytes(log_path).size() > LOG_MAX_BYTES:
		var old := FileAccess.get_file_as_string(log_path)
		var w := FileAccess.open(log_path, FileAccess.WRITE)
		if w != null:
			w.store_string(old.substr(old.length() / 2))
	var f := FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("[%s] %s" % [Time.get_time_string_from_system(), text])
