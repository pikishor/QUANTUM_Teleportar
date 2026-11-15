extends RefCounted
## Dev probe (wave 115 PLAY critic, not a test): what does ShaderWarmup.run (with SnakeWarm in it) leave visible? The perf gate never runs the warm-up (tools skip it under Game.autostart), so a leftover would show
## on a phone only. Compares the visible 3D instances, MultiMesh visible counts and visible canvas items of the whole tree before and after a forced run; prints the differences.
## Run: scratchpad/run_probe.sh tests/dev_w115p_leftover.gd 120 "^LO"

const TIMEOUT_SECONDS := 120.0

var host: Node


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _snap(root: Node) -> Dictionary:
	var out := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var key := str(n.get_path())
		if n is VisualInstance3D and (n as VisualInstance3D).is_visible_in_tree():
			var extra := n.get_class()
			if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
				extra += " mm=%d" % (n as MultiMeshInstance3D).multimesh.visible_instance_count
			if n is GeometryInstance3D and (n as GeometryInstance3D).transparency >= 0.99:
				extra += " (transparent)"
			out[key] = extra
		elif n is CanvasItem and (n as CanvasItem).is_visible_in_tree() and not (n is Control and (n as Control).size == Vector2.ZERO):
			out[key] = n.get_class()
	return out


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	var p := Game.player as Player
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Game.state = &"play"
	TestMode.god = true
	p.teleport_to(Game.SPAWN)
	await frames(30)
	var before := _snap(main)
	var res: Dictionary = await ShaderWarmup.run(host, true)
	await frames(30)
	var after := _snap(main)
	var added := 0
	var changed := 0
	var gone := 0
	for k: String in after:
		if not before.has(k):
			added += 1
			print("LO +%s %s" % [k, str(after[k])])
		elif before[k] != after[k]:
			changed += 1
			print("LO ~%s %s -> %s" % [k, str(before[k]), str(after[k])])
	for k: String in before:
		if not after.has(k):
			gone += 1
			print("LO -%s %s" % [k, str(before[k])])
	print("LO SUMMARY items %d: visible before %d, after %d, added %d, changed %d, gone %d" % [int(res.get("items", 0)), before.size(), after.size(), added, changed, gone])
	TestMode.god = false
	main.queue_free()
	await frames(3)
