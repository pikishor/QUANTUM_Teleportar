extends RefCounted
## Shared helpers of the QA soak and monkey bots (tests/bot_soak.gd, tests/bot_monkey.gd, tests/test_soak_quick.gd; docs/QA.md).
## Not a test itself (no test_ prefix): CI only runs tests/test_*.gd.
##   const Lib := preload("res://tests/soak_lib.gd")

## Growth allowed by the soak (judged in bot_soak.gd). "abs" / "pct": a checkpoint may exceed the baseline checkpoint (the first one, taken after the warm-up pass) by this much; it is
## over the limit only when it exceeds BOTH (so a small baseline gets the absolute slack and a big one the relative one, pct 0 = absolute only). "slope": the least-squares trend over
## the later half of the checkpoints, per simulated minute; a leak that stays under the absolute limit in a short run still shows as a steady slope. Calibrated on real runs:
## 10-minute headless soaks of the fixed game sit at about nodes +3..10 / objects +10..16 / static +0 per minute late in the run (pools still filling); the leaks this soak found (docs/QA.md) were static +13 / objects +127 per minute.
const LIMITS := {
	"nodes": {"abs": 150, "pct": 8.0, "slope": 25.0},
	"orphans": {"abs": 12, "pct": 0.0, "slope": 1.0},
	"objects": {"abs": 1500, "pct": 8.0, "slope": 50.0},
	"resources": {"abs": 400, "pct": 10.0, "slope": 25.0},
	"static_mb": {"abs": 64.0, "pct": 20.0, "slope": 3.0},
	"tex_mb": {"abs": 24.0, "pct": 10.0, "slope": 2.0},
	"video_mb": {"abs": 48.0, "pct": 12.0, "slope": 4.0},
}
const STATES: Array[StringName] = [&"menu", &"play", &"paused", &"dead", &"win", &"cutscene"]


## The Performance monitors the soak samples. tex_mb / video_mb read 0 under --headless (dummy renderer): the soak then reports them as n/a and never gates on them.
static func monitors() -> Dictionary:
	return {
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": maxi(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - FoeHuman.cached_node_count(), 0),       # the roster bodies' prototype cache is out of the tree on purpose (wave 113)
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"tex_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"video_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	}


static func line(m: Dictionary) -> String:
	return "nodes=%d orphans=%d objects=%d resources=%d static=%.1fMB tex=%.1fMB video=%.1fMB" % [m["nodes"], m["orphans"], m["objects"], m["resources"], m["static_mb"], m["tex_mb"], m["video_mb"]]


## True when the renderer reports texture / video memory at all (false under --headless).
static func renders() -> bool:
	return DisplayServer.get_name() != "headless"


## Node census of the whole tree: {"class": {name: n}, "path": {bucket: n}}; a path bucket is the first `depth` names below the root (for example Main/World/Mirror).
static func census(tree: SceneTree, depth := 3) -> Dictionary:
	var by_class := {}
	var by_path := {}
	var stack: Array[Node] = [tree.root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var cn := n.get_class()
		by_class[cn] = int(by_class.get(cn, 0)) + 1
		var rel := String(tree.root.get_path_to(n))
		var parts := rel.split("/", false)
		var bucket := "/".join(parts.slice(0, mini(depth, parts.size())))
		by_path[bucket] = int(by_path.get(bucket, 0)) + 1
		for c in n.get_children():
			stack.append(c)
	return {"class": by_class, "path": by_path}


## The `top` biggest growers between two census dictionaries, as lines "+N  name (a -> b)".
static func census_diff(a: Dictionary, b: Dictionary, top := 8) -> PackedStringArray:
	var rows: Array = []
	for kind: String in ["class", "path"]:
		var ca: Dictionary = a.get(kind, {})
		var cb: Dictionary = b.get(kind, {})
		for k: String in cb:
			var d := int(cb[k]) - int(ca.get(k, 0))
			if d > 0:
				rows.append([d, "%s %s (%d -> %d)" % [kind, k, int(ca.get(k, 0)), int(cb[k])]])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) > int(y[0]))
	var out := PackedStringArray()
	for i in mini(top, rows.size()):
		out.append("+%d  %s" % [rows[i][0], rows[i][1]])
	return out


## Engine errors that only the headless dummy renderer raises (its material storage does not notify instances when a material is freed, so a stale RID is looked up later:
## "Parameter material is null" in material_get_instance_shader_parameters). They are counted as noise in --headless runs and never ignored under a real renderer.
const HEADLESS_NOISE: Array[String] = ["material_get_instance_shader_parameters"]


## Counts every push_error / script / engine error (warnings excluded) from the moment it is added with OS.add_logger(); thread-safe. Own logger instead of Dev's error log: it
## keeps counting past Dev's 40-line window and can tell the headless renderer noise from real errors.
class ErrorTap extends Logger:
	var total := 0                       ## errors that count
	var noise := 0                       ## dummy-renderer noise (headless only), counted apart
	var lines: PackedStringArray = PackedStringArray()
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var text := (rationale if rationale != "" else code).strip_edges().replace("\n", " ")
		var entry := "[%s] %s  (%s:%d %s)" % ["SCRIPT" if error_type == Logger.ERROR_TYPE_SCRIPT else ("SHADER" if error_type == Logger.ERROR_TYPE_SHADER else "ERROR"), text, file.get_file(), line, function]
		for bt in backtraces:
			var f := bt.format().strip_edges().replace("\n", " <- ")
			if f != "":
				entry += "  BT: " + f
				break
		_mutex.lock()
		if DisplayServer.get_name() == "headless" and HEADLESS_NOISE.any(func(n: String) -> bool: return entry.contains(n)):
			noise += 1
		else:
			total += 1
			if lines.size() < 30:
				lines.append(entry)
		_mutex.unlock()

	func snapshot() -> PackedStringArray:
		_mutex.lock()
		var c := lines.duplicate()
		_mutex.unlock()
		return c


## The HUD of the running game (a sibling of the player under Main), or null.
static func find_hud() -> Hud:
	var anchor: Node = Game.player if is_instance_valid(Game.player) else Game.vehicles
	if not is_instance_valid(anchor):
		return null
	for c in anchor.get_parent().get_children():
		if c is Hud:
			return c as Hud
	return null


static func find_node_of(script_class: String) -> Node:
	var anchor: Node = Game.player if is_instance_valid(Game.player) else null
	if anchor == null:
		return null
	for c in anchor.get_parent().get_children():
		if c.get_class() == script_class or (c.get_script() != null and (c.get_script() as Script).get_global_name() == script_class):
			return c
	return null


## Sends an event to the game the way the engine would: the matching InputMap actions change state (what Input.parse_input_event does) and the event runs through every
## _input / _unhandled_input of the root viewport. Positions are VIEWPORT coordinates (what the HUD rectangles are in), so the headless window (64 px, stretched) and a real
## window behave the same. (Input.parse_input_event is not used: headless buffers it and flushes it a few frames later, with window coordinates.)
static func send(e: InputEvent) -> void:
	for a in InputMap.get_actions():
		if InputMap.event_is_action(e, a):
			if e.is_pressed():
				Input.action_press(a)
			else:
				Input.action_release(a)
	(Engine.get_main_loop() as SceneTree).root.push_input(e, true)


## One left mouse button event at a screen position; call it twice (pressed, then released) for a click.
static func mouse_event(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	if pressed:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	send(e)


static func touch_event(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	send(e)


static func drag_event(index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = rel
	send(e)


static func key_event(keycode: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	e.keycode = keycode
	e.pressed = pressed
	send(e)


## "Real" conditions for a bot: tools, tests and bots run with Game.autostart, which switches the cutscenes, the scripted campaign and the tutorial off. This turns them on, and moves
## the settings file of the HUD (the monkey presses the settings buttons) to a throw-away path, so a run never touches the player's own settings or saves (autosave is off under
## autostart as well). Returns the temp path (delete it when done).
static func enable_real(hud: Hud) -> String:
	var path := "user://soak_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if hud != null:
		hud.settings.path = path
	var cin := Cinematics.instance
	if cin != null:
		cin.enabled = true
	var m := Game.missions as Missions
	if m != null and m.campaign != null:
		m.campaign.enabled = true
	if Game.story != null and Game.story.get("tutorial") != null:
		Game.story.tutorial.force = true
	return path


static func release_everything() -> void:
	for a in InputMap.get_actions():
		if not String(a).begins_with("ui_"):
			Input.action_release(a)
