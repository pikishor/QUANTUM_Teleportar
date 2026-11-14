extends RefCounted
## TEMP diagnostic (deleted by the integrator): which nodes are orphans after the heist round of the soak test?
const TIMEOUT_SECONDS := 140.0
const Soak := preload("res://tests/bot_soak.gd")
const Lib := preload("res://tests/soak_lib.gd")

var host: Node
var main: Node


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	var prog := Game.progress as Progress
	var bot := Soak.new()
	bot.speed = 4
	bot.scale = 0.25
	bot.seed_value = 5
	bot.verbose = false
	var ok: bool = await bot.begin(host)
	print("begin ", ok)
	await bot.warm_pools()
	print("ORPHANS before heist: ", Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	host.get_tree().root.print_orphan_nodes()
	var g: Dictionary = await bot.probe_system("heist", 2)
	print("ORPHANS after heist (probe says +%d): " % int(g["orphans"]), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	host.get_tree().root.print_orphan_nodes()
	bot.close()
	for f in ["user://soak_progress.cfg", "user://soak_progress.cfg.bak", "user://soak_settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
