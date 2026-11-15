extends RefCounted
## Dev probe (wave 115 PLAY critic): a SNAKE ZIP to a parked car: does `Basis must be normalized` (snake_pose.gd) print, and from which pose?
const TIMEOUT_SECONDS := 100.0
var host: Node

class BT extends Logger:
	var seen := 0
	var out: Array[String] = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		seen += 1
		if out.size() < 3:
			var s := "%s | %s:%d %s" % [rationale.strip_edges(), file.get_file(), line, function]
			for b in script_backtraces:
				s += "\n      " + b.format().replace("\n", "\n      ")
			out.append(s)

func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 40)
	var p := Game.player as Player
	var sn := p.snake
	Game.state = &"play"
	TestMode.god = true
	(Game.enemies as EnemyManager).clear()
	TrafficField.bare_street()
	var lg := BT.new()
	OS.add_logger(lg)
	var vm := Game.vehicles as VehicleManager
	vm._reset_all()
	var spot := Vector3(-30.0, 0.0, 4.0)
	p.teleport_to(spot)
	p.camera_rig.reset_view(-PI * 0.5, 0.0)
	p.yaw = -PI * 0.5
	var car := vm.spawn_parked(&"sedan", spot + Vector3(-22.0, 0.0, 0.0), 0.0)
	await TestLib.frames(host, 30)
	var base_err := lg.seen
	p.camera_rig.aim_at(car.global_position + Vector3(0, 0.8, 0))
	await TestLib.frames(host, 2)
	var z0 := sn.zips
	Input.action_press(&"snake")
	await TestLib.frames(host, 6)
	Input.action_release(&"snake")
	var seen_modes: Array[String] = []
	for i in 180:
		await TestLib.frames(host, 1)
		var m := sn.mode_name() + ("/" + String(sn.zip.phase) if sn.mode == SnakeTraversal.Mode.ZIP else "")
		if seen_modes.is_empty() or seen_modes[seen_modes.size() - 1] != m:
			seen_modes.append(m)
	print("ZC zips %d, kind %s, modes %s, errors during the zip %d" % [sn.zips - z0, str(sn.zip.kind), str(seen_modes), lg.seen - base_err])
	for s in lg.out:
		print("ZC ERR ", s)
	OS.remove_logger(lg)
	main.queue_free()
	await TestLib.frames(host, 3)
