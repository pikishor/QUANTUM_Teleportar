extends RefCounted
## Dev helper (not a test): which collision shape (box) of which body a car box at a road point overlaps. tools/test.sh tests/dev_deck_probe.gd (DP_ROAD, DP_S0, DP_S1)
const TIMEOUT_SECONDS := 100


func run(host: Node) -> void:
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	var p := Game.player as Player
	var city := Game.world as City
	var rn := OS.get_environment("DP_ROAD") if OS.get_environment("DP_ROAD") != "" else "SUMMIT ROAD"
	var s0 := float(OS.get_environment("DP_S0")) if OS.get_environment("DP_S0") != "" else 0.0
	var s1 := float(OS.get_environment("DP_S1")) if OS.get_environment("DP_S1") != "" else 90.0
	for road: Dictionary in TerrainRoads.roads():
		if String(road["name"]) != rn:
			continue
		var pos: PackedVector2Array = road["pos"]
		var prof: PackedFloat32Array = road["prof"]
		var mid := clampi(int((s0 + s1) * 0.5 / TerrainRoads.STEP), 0, pos.size() - 2)
		var hp3 := Vector3(pos[mid].x, prof[mid] + 1.0, pos[mid].y)
		p.global_position = hp3
		city.terrain.settle(hp3)
		p.teleport_to(hp3)
		await TestLib.frames(host, 6)
		var space := p.get_world_3d().direct_space_state
		var shape := BoxShape3D.new()
		shape.size = Vector3(2.0, 1.4, 4.4)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.collision_mask = 1
		var t := s0
		while t < s1:
			var ti := clampi(int(t / TerrainRoads.STEP), 0, pos.size() - 2)
			var a := pos[ti]
			var b := pos[ti + 1]
			var f := (t - float(ti) * TerrainRoads.STEP) / TerrainRoads.STEP
			var dir := (b - a).normalized()
			var pt := a.lerp(b, f)
			var py := lerpf(prof[ti], prof[ti + 1], f)
			var grade := (prof[ti + 1] - prof[ti]) / TerrainRoads.STEP
			q.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)) * Basis(Vector3.RIGHT, atan(grade)), Vector3(pt.x, py + 1.15, pt.y))
			for hit in space.intersect_shape(q, 8):
				var col := hit["collider"] as Node
				var owner_id: int = (col as CollisionObject3D).shape_find_owner(int(hit["shape"]))
				var cs := (col as CollisionObject3D).shape_owner_get_owner(owner_id) as CollisionShape3D
				var sz := ((cs.shape as BoxShape3D).size) if cs != null and cs.shape is BoxShape3D else Vector3.ZERO
				print("DECKPROBE s=%d at (%.1f, %.1f) road y %.2f hits %s/%s box at (%.1f, %.1f, %.1f) size %s" % [int(t), pt.x, pt.y, py, str(col.get_parent().name), str(col.name), cs.global_position.x if cs != null else 0.0, cs.global_position.y if cs != null else 0.0, cs.global_position.z if cs != null else 0.0, str(sz)])
			t += 6.0
	Game.state = &"menu"
	main.queue_free()
