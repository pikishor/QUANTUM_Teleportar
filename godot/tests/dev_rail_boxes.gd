extends RefCounted
## Dev helper (not a test): the collision boxes of the rail chunks near a point, with the distance of each to the nearest road centre line. tools/test.sh tests/dev_rail_boxes.gd (RB_X, RB_Z, RB_R)
const TIMEOUT_SECONDS := 100


func run(host: Node) -> void:
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	var x := float(OS.get_environment("RB_X")) if OS.get_environment("RB_X") != "" else 282.0
	var z := float(OS.get_environment("RB_Z")) if OS.get_environment("RB_Z") != "" else -1336.0
	var r := float(OS.get_environment("RB_R")) if OS.get_environment("RB_R") != "" else 25.0
	var p := Game.player as Player
	var pos := Vector3(x, TerrainHeight.height_at(x, z) + 1.0, z)
	p.global_position = pos
	var city := Game.world as City
	city.terrain.settle(pos)
	p.teleport_to(pos)
	await TestLib.frames(host, 30)
	var rw := city.get_node_or_null("RailWorld")
	print("RAILBOX railworld %s" % str(rw))
	for n in city.find_children("Collision_*", "StaticBody3D", true, false):
		for c in n.get_children():
			var cs := c as CollisionShape3D
			if cs == null or not (cs.shape is BoxShape3D):
				continue
			var gp := cs.global_position
			if Vector2(gp.x - x, gp.z - z).length() < r:
				var nr := TerrainRoads.nearest(gp.x, gp.z)
				print("RAILBOX %s box at (%.1f, %.1f, %.1f) size %s road %s dist %.1f (road y %.1f)" % [n.name, gp.x, gp.y, gp.z, str((cs.shape as BoxShape3D).size), str(nr[1]), float(nr[0]), float(nr[2])])
	Game.state = &"menu"
	main.queue_free()
