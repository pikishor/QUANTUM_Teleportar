extends RefCounted
## Dev probe (wave 115 PLAY critic): where does `Parameter "material" is null (material_get_instance_shader_parameters)` come from? A logger prints the script backtrace of the first few.
const TIMEOUT_SECONDS := 100.0
var host: Node


class BT extends Logger:
	var seen := 0
	var out: Array[String] = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		seen += 1
		if out.size() < 4:
			var s := "%s | %s:%d %s" % [rationale.strip_edges(), file.get_file(), line, function]
			for b in script_backtraces:
				s += "\n      " + b.format().replace("\n", "\n      ")
			out.append(s)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	var lg := BT.new()
	OS.add_logger(lg)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 40)
	var p := Game.player as Player
	Game.state = &"play"
	TestMode.god = true
	var war := SnakeWar.of(p)
	var em := Game.enemies as EnemyManager
	em.clear()
	for i in 3:
		em.spawn(&"operative", p.global_position + Vector3(0, 0, -10.0 - 2.0 * i), true)
	await TestLib.frames(host, 20)
	print("MW after spawning three operatives: %d errors" % lg.seen)
	war.arm(&"sv_pull")
	p.camera_rig.aim_at(SnakeAim.center_of(em.get_child(0) as Node3D)) if em.get_child_count() > 0 else null
	Input.action_press(&"fire")
	await TestLib.frames(host, 8)
	Input.action_release(&"fire")
	await TestLib.frames(host, 90)
	print("MW after a pull: %d errors" % lg.seen)
	war.arm(&"sb_coil")
	Input.action_press(&"fire")
	await TestLib.frames(host, 8)
	Input.action_release(&"fire")
	await TestLib.frames(host, 180)
	print("MW after a bomb: %d errors" % lg.seen)
	for s in lg.out:
		print("MW ERR ", s)
	OS.remove_logger(lg)
	main.queue_free()
	await TestLib.frames(host, 3)
