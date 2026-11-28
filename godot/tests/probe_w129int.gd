extends RefCounted
## w129-integrator scratch probe (deleted before commit): nodes left after freeing the game
func _all(n: Node, out: Dictionary) -> void:
	for c in n.get_children():
		out[str(c.get_path())] = c.get_class()
		_all(c, out)

func run(h: Node) -> void:
	var before := {}
	_all(h.get_tree().root, before)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	h.add_child(main)
	await TestLib.frames(h, 30)
	Game.state = &"play"
	Game.explode(Game.player.global_position + Vector3(8.0, 0.5, 0.0), 4.0, {"player_dmg": 0.0})
	await TestLib.frames(h, 200)
	main.queue_free()
	await TestLib.frames(h, 10)
	var after := {}
	_all(h.get_tree().root, after)
	for k in after:
		if not before.has(k):
			print("LEFT %s %s" % [k, after[k]])
	print("ORPH ", Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	TestLib.check(true, "probe")
