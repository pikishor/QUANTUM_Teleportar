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
const REPORT_FILE := "user://perf_report.txt"      ## SEND REPORT writes the compact report here (and puts the same text on the clipboard)

var log_path := LOG_FILE
var report_path := REPORT_FILE
var measuring := false                   ## the renderer is timing the CPU / GPU side of the frame (costs a little, so only while the readout or a benchmark needs it)
var samples := PackedFloat32Array()      ## frame times in ms, newest last (ring)
var frames_total := 0
var copies := 0
var governor_events := 0

var _aq: AutoQuality
var _head := 0
var _last_us := 0
var _log_t := 0.0
var _session_logged := false
var _scale_seen := -1.0


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
		_aq = aq as AutoQuality
		_aq.lowered.connect(on_governor_lowered)
		_aq.res_lowered.connect(on_governor_res)
	Game.quality_changed.connect(_on_tier)
	PerfTimers.install(get_tree())
	_last_us = Time.get_ticks_usec()
	startup_check()


## Tier the startup self-check recommends: touchscreens and the Compatibility renderer LOW, software renderers LOW, other desktops HIGH.
static func recommended_tier() -> int:
	if DisplayServer.is_touchscreen_available() or Game.force_touch:
		return 0
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	if adapter.contains("llvmpipe") or adapter.contains("swiftshader") or adapter.contains("software"):
		return 0
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return 1
	return 2


## One line with everything the owner needs to know about the device; logged once per session into the perf log.
func startup_line() -> String:
	var vp := get_viewport()
	return "STARTUP CHECK device=%s os=%s %s gpu=%s vendor=%s renderer=%s/%s touch=%s window=%s first_launch=%s recommended=%s current=%s" % [OS.get_model_name(), OS.get_name(),
		OS.get_version(), RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(), str(DisplayServer.is_touchscreen_available() or Game.force_touch), str(Vector2i(vp.get_visible_rect().size)),
		str(UiSettings.new().quality < 0), TIER_NAMES[recommended_tier()], tier_name()]


func startup_check() -> void:
	log_line(startup_line())


## What the governor settled on, in one line: tier, render resolution, FPS, how many steps it took.
func governor_text() -> String:
	var vp := get_viewport()
	return "Governor: tier %s | render %s (scale %.2f, %s) | FPS %d (sample %.0f) | tier drops %d, resolution steps %d" % [tier_name(), str(Vector2i(vp.get_visible_rect().size * vp.scaling_3d_scale)),
		vp.scaling_3d_scale, RenderRes.mode_name(RenderRes.mode()), roundi(Engine.get_frames_per_second()), _aq.last_fps if _aq != null else 0.0, governor_events,
		_aq.res_steps if _aq != null else 0]


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt_ms := float(now - _last_us) / 1000.0
	_last_us = now
	if Game.state != &"play":
		return
	if dt_ms > 1000.0:                          # a load or a pause hitch is not a frame time
		return
	record(dt_ms)
	var sc := get_viewport().scaling_3d_scale
	if _scale_seen >= 0.0 and not is_equal_approx(sc, _scale_seen):
		log_line("RES %.2f -> %.2f | %s" % [_scale_seen, sc, governor_text()])
	_scale_seen = sc
	_log_t += delta / maxf(Engine.time_scale, 0.05)
	if _log_t >= LOG_EVERY:
		_log_t = 0.0
		log_line("SAMPLE " + summary() + " | " + PerfTimers.top_line(4))


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
	return "t=%d fps=%d p50=%.1f p95=%.1f p99=%.1f worst=%.1fms draws=%d tris=%dk nodes=%d mem=%dMB tex=%dMB tier=%s res=%.2f sys[%s] temp=%s" % [Time.get_ticks_msec() / 1000, roundi(Engine.get_frames_per_second()),
		percentile(50), percentile(95), percentile(99), worst_ms(), s["total_draws"], int(s["total_prims"]) / 1000, s["nodes"], mem_mb(), roundi(s["tex_mb"]), tier_name(), get_viewport().scaling_3d_scale,
		systems_text(), thermal_text()]


var _logged_tier := -1


## A tier switch (the player's choice or the governor) goes into the log with the texture memory, so a phone log shows whether the switch released what the old tier loaded.
func _on_tier(level: int) -> void:
	var key := Game.tier_index()
	if _logged_tier >= 0 and key != _logged_tier:
		log_line("TIER %s -> %s | %s" % [Game.TIER_LABELS[_logged_tier], Game.TIER_LABELS[key], summary()])
	_logged_tier = key


func tier_name() -> String:
	return tier_label()


## "LOW+", "LOW", "MED" or "HIGH": the tier the player sees.
static func tier_label() -> String:
	return Game.tier_label()


func mem_mb() -> int:
	return int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)


## Per-system milliseconds of the last frame: script (_process), physics, and the renderer's CPU and GPU time (the last two only while `measuring`; a headless or software renderer reports 0).
func systems() -> Dictionary:
	var rid := get_viewport().get_viewport_rid()
	return {
		"script": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"render_cpu": RenderingServer.viewport_get_measured_render_time_cpu(rid) if measuring else 0.0,
		"render_gpu": RenderingServer.viewport_get_measured_render_time_gpu(rid) if measuring else 0.0,
	}


func systems_text() -> String:
	var m := systems()
	return "script %.1f physics %.1f render-cpu %.1f render-gpu %.1f ms" % [m["script"], m["physics"], m["render_cpu"], m["render_gpu"]]


## Turns the renderer's CPU / GPU frame timing on or off (the readout and the benchmark switch it on).
func set_measure(on: bool) -> void:
	measuring = on
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), on)


## Battery level (and charging) from /sys/class/power_supply/battery where the OS allows the read (Godot 4 has no battery API); "n/a" otherwise.
func battery_text() -> String:
	var base := "/sys/class/power_supply/battery/"
	if not FileAccess.file_exists(base + "capacity"):
		return "n/a"
	var f := FileAccess.open(base + "capacity", FileAccess.READ)
	if f == null:
		return "n/a"
	var out := "%d%%" % int(f.get_line().strip_edges())
	if FileAccess.file_exists(base + "status"):
		var g := FileAccess.open(base + "status", FileAccess.READ)
		if g != null:
			var st := g.get_line().strip_edges().to_lower()
			if st == "charging":
				out += " charging"
	return out


## Hottest thermal zone in Celsius, read from /sys/class/thermal where the OS allows it (many phones do, Godot itself has no thermal API); "n/a" otherwise.
func thermal_text() -> String:
	var hottest := -1.0
	for i in 12:
		var path := "/sys/class/thermal/thermal_zone%d/temp" % i
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var v := float(f.get_line().strip_edges())
		if v > 1000.0:
			v /= 1000.0                         # millidegrees on most kernels
		if v > 0.0 and v < 150.0:
			hottest = maxf(hottest, v)
	return "n/a" if hottest < 0.0 else "%.0fC" % hottest


## The render settings that matter on a phone GPU, in one line (so a report shows whether a device ran the safe defaults).
func settings_text() -> String:
	var vp := get_viewport()
	return "MSAA %d | aniso %d | LOD %.1fpx | mip bias %.2f | dir shadow %d | pos atlas %d | debanding %s" % [vp.msaa_3d, vp.anisotropic_filtering_level, vp.mesh_lod_threshold,
		vp.texture_mipmap_bias, int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 0)), vp.positional_shadow_atlas_size, str(vp.use_debanding)]


## The full text report: what the owner sends.
func report() -> String:
	var s := PerfProbe.snapshot(get_viewport())
	var out := PackedStringArray()
	out.append("QUANTUM TELEPORT perf report")
	out.append("Device: %s | OS %s %s" % [OS.get_model_name(), OS.get_name(), OS.get_version()])
	out.append("GPU: %s (%s) | renderer %s / %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()])
	out.append("Render %s scale %.2f (%s, %s) of window %s" % [str(Vector2i(get_viewport().get_visible_rect().size * get_viewport().scaling_3d_scale)), get_viewport().scaling_3d_scale, RenderRes.mode_name(RenderRes.mode()), "FSR" if get_viewport().scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR else "bilinear/native", str(Vector2i(get_viewport().get_visible_rect().size))])
	out.append("Viewport %s | tier %s | quality drops by governor %d" % [str(Vector2i(get_viewport().get_visible_rect().size)), tier_name(), governor_events])
	out.append(governor_text())
	out.append("Frame ms (last %d): p50 %.1f  p95 %.1f  p99 %.1f  worst %.1f | FPS now %d" % [count(), percentile(50), percentile(95), percentile(99), worst_ms(), roundi(Engine.get_frames_per_second())])
	out.append("Draws %d  Tris %dk  Nodes %d  Objects %d" % [s["total_draws"], int(s["total_prims"]) / 1000, s["nodes"], s["objects"]])
	out.append("Memory: static %d MB, textures %d MB, buffers %d MB" % [mem_mb(), roundi(s["tex_mb"]), roundi(s["buf_mb"])])
	out.append("Systems: " + systems_text())
	out.append("Settings: " + settings_text())
	out.append("Battery: %s | Thermal: %s" % [battery_text(), thermal_text()])
	out.append(PerfTimers.table(8))
	return "\n".join(out) + "\n"


## SEND REPORT: the compact report goes to the clipboard, to user://perf_report.txt (with the last benchmark result when there is one) and into the log. Returns the text.
func copy_report() -> String:
	var r := report()
	if BenchmarkRun.last_text != "":
		r += "\n" + BenchmarkRun.last_text
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(r)
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	if f != null:
		f.store_string(r)
	copies += 1
	log_line("COPY\n" + r)
	return r


func on_governor_lowered(level: int) -> void:
	governor_events += 1
	log_line("GOVERNOR lowered tier to %s | %s | %s" % ["LOW+" if (level == 0 and LowPlus.on()) else TIER_NAMES[clampi(level, 0, 2)], governor_text(), summary()])


func on_governor_res(mode_name: String) -> void:
	log_line("GOVERNOR lowered resolution to %s | %s | %s" % [mode_name, governor_text(), summary()])


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
