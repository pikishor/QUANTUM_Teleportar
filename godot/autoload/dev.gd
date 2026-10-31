extends Node
## Command-line dev hooks. Inert unless flags are passed after `--` (see tools/shot.sh and tools/bot.sh):
##   --shot=PATH           save one screenshot after --frames frames (default 20), then quit
##   --shot-seq=PREFIX     save PREFIX_000.png, PREFIX_001.png ... every --every frames (default 30), --count shots (default 5), then quit
##   --bot=res://x.gd      run a bot: the script needs `func step(t: float, delta: float) -> bool` (return true when finished)
## Screenshots need a real renderer (xvfb + software GL); --headless renders nothing.

## On-device error log: every engine and script error (also push_error) lands in the last ERROR_LINES lines, which are written to user://last_errors.txt about once a
## second while something new arrived, and shown in the small panel of the touch controls (long-press the FPS box). Thread-safe: errors can come from any thread.
const ERROR_LINES := 40
const ERROR_FILE := "user://last_errors.txt"


class ErrorLog extends Logger:
	var lines: PackedStringArray = PackedStringArray()
	var dirty := false
	var total := 0
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var kind := "SCRIPT" if error_type == Logger.ERROR_TYPE_SCRIPT else ("SHADER" if error_type == Logger.ERROR_TYPE_SHADER else "ERROR")
		var text := rationale if rationale != "" else code
		var entry := "[%s] %s  (%s:%d %s)" % [kind, text.strip_edges().replace("\n", " "), file.get_file(), line, function]
		_mutex.lock()
		total += 1
		if not lines.is_empty() and lines[lines.size() - 1].begins_with(entry):
			var last := lines[lines.size() - 1]
			var n := 1
			var at := last.rfind(" x")
			if at > 0 and last.substr(at + 2).is_valid_int():
				n = last.substr(at + 2).to_int()
				last = last.substr(0, at)
			lines[lines.size() - 1] = "%s x%d" % [last, n + 1]
		else:
			lines.append(entry)
			while lines.size() > ERROR_LINES:
				lines.remove_at(0)
		dirty = true
		_mutex.unlock()

	func snapshot() -> PackedStringArray:
		_mutex.lock()
		var copy := lines.duplicate()
		_mutex.unlock()
		return copy

	func take_dirty() -> bool:
		_mutex.lock()
		var d := dirty
		dirty = false
		_mutex.unlock()
		return d

	func clear() -> void:
		_mutex.lock()
		lines = PackedStringArray()
		total = 0
		dirty = true
		_mutex.unlock()


var errors := ErrorLog.new()

var _args := {}
var _frame := 0
var _shots := 0
var _bot: RefCounted
var _t := 0.0


func _ready() -> void:
	OS.add_logger(errors)
	var flush := Timer.new()
	flush.wait_time = 1.0
	flush.autostart = true
	flush.process_mode = Node.PROCESS_MODE_ALWAYS
	flush.timeout.connect(flush_errors)
	add_child(flush)
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	set_process(not _args.is_empty())
	if _args.has("bot"):
		var script := load(_args["bot"]) as GDScript
		if script:
			_bot = script.new()
		else:
			push_error("Dev: cannot load bot %s" % _args["bot"])


func _exit_tree() -> void:
	flush_errors()
	OS.remove_logger(errors)


## The last ERROR_LINES error lines, oldest first (a copy).
func error_lines() -> PackedStringArray:
	return errors.snapshot()


## Writes the log to user://last_errors.txt when something new arrived since the last write (also called once a second).
func flush_errors() -> void:
	if not errors.take_dirty():
		return
	var f := FileAccess.open(ERROR_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(errors.snapshot()) + "\n")


func _process(delta: float) -> void:
	_frame += 1
	_t += delta
	var finished := false
	if _bot and _bot.has_method("step"):
		finished = _bot.step(_t, delta)
	if _args.has("shot") and _frame >= int(_args.get("frames", "20")):
		await _save(_args["shot"])
		get_tree().quit()
		set_process(false)
		return
	if _args.has("shot-seq"):
		var every := int(_args.get("every", "30"))
		if _frame % every == 0:
			await _save("%s_%03d.png" % [_args["shot-seq"], _shots])
			_shots += 1
			if _shots >= int(_args.get("count", "5")):
				get_tree().quit()
				set_process(false)
				return
	if finished and not _args.has("shot-seq"):
		get_tree().quit()
		set_process(false)


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("Dev: no image (use xvfb + software GL, not --headless)")
		return
	img.save_png(path)
	print("SHOT_SAVED ", path, " ", img.get_size())
