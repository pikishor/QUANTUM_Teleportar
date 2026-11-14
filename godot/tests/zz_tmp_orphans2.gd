extends RefCounted
## TEMP diagnostic (deleted by the integrator): which action creates stray (orphan) MeshInstance3D nodes?
const TIMEOUT_SECONDS := 140.0

var host: Node
var main: Node


func _orph() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _step(label: String, before: int) -> int:
	var now := _orph()
	print("ORPH %-34s %+d (now %d)" % [label, now - before, now])
	return now


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.god = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 60)
	var em := Game.enemies as EnemyManager
	var p := Game.player as Player
	var o := _orph()
	print("ORPH base ", o)
	var o2 := _orph()
	var m := Game.missions as Missions
	DemoMode.active = true
	for rep in 6:
		var hid: StringName = HeistScripts.IDS[0]
		var ap: StringName = HeistScripts.APPROACHES[1]
		var started: bool = m.heists.start(hid, ap, true)
		await TestLib.frames(host, 120)
		o2 = _step("heist rep %d started=%s +2 s" % [rep, str(started)], o2)
		m.heists.abort("ABANDONED")
		await TestLib.frames(host, 60)
		(Game.enemies as EnemyManager).clear()
		await TestLib.frames(host, 120)
		o2 = _step("heist rep %d aborted + settle" % rep, o2)
	for rep in 3:
		var hid2: StringName = HeistScripts.IDS[(rep + 1) % HeistScripts.IDS.size()]
		var ap2: StringName = HeistScripts.APPROACHES[(rep + 2) % HeistScripts.APPROACHES.size()]
		var st2: bool = m.heists.start(hid2, ap2, rep % 2 == 0)
		await TestLib.frames(host, 120)
		o2 = _step("other heist %s/%s started=%s" % [hid2, ap2, str(st2)], o2)
		m.heists.abort("ABANDONED")
		await TestLib.frames(host, 60)
		(Game.enemies as EnemyManager).clear()
		await TestLib.frames(host, 120)
		o2 = _step("other heist aborted + settle", o2)
	DemoMode.active = false


func get_tree_cars() -> Array:
	var out: Array = []
	for n in host.get_tree().get_nodes_in_group(&"vehicle"):
		out.append(n)
	return out
