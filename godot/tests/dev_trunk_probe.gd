extends RefCounted
## Dev helper (not a test): which trunk colliders stand within 12 m of a point, and which road sample is nearest. tools/test.sh tests/dev_trunk_probe.gd   (TR_X, TR_Z)
const TIMEOUT_SECONDS := 100


func run(host: Node) -> void:
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	var p := Game.player as Player
	var city := Game.world as City
	var x := float(OS.get_environment("TR_X")) if OS.get_environment("TR_X") != "" else 1754.0
	var z := float(OS.get_environment("TR_Z")) if OS.get_environment("TR_Z") != "" else 573.0
	var pos := Vector3(x, TerrainHeight.height_at(x, z) + 1.0, z)
	p.global_position = pos
	city.terrain.settle(pos)
	city.vegetation.settle(pos)
	p.teleport_to(pos)
	await TestLib.frames(host, 4)
	var nr := TerrainRoads.nearest(x, z)
	print("TRUNK nearest road at the point: dist %.1f road %s y %.1f" % [float(nr[0]), str(nr[1]), float(nr[2])])
	for n in city.vegetation.find_children("Trunk*", "", true, false):
		var b := n as Node3D
		if Vector2(b.global_position.x - x, b.global_position.z - z).length() < 14.0:
			var d := TerrainRoads.nearest(b.global_position.x, b.global_position.z)
			var cs: Node = n.get_child(0) if n.get_child_count() > 0 else null
			var sh := "?"
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape is CylinderShape3D:
				var cy := (cs as CollisionShape3D).shape as CylinderShape3D
				sh = "cyl r %.2f h %.1f" % [cy.radius, cy.height]
			print("TRUNK %s at (%.1f, %.1f, %.1f) road dist %.1f (road %s) %s parent %s" % [n.name, b.global_position.x, b.global_position.y, b.global_position.z, float(d[0]), str(d[1]), sh, str(n.get_parent().name)])
	Game.state = &"menu"
	main.queue_free()
