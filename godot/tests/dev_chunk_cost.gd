extends RefCounted
## Dev helper (not a test): milliseconds of one LOD0 / LOD1 terrain chunk (mesh build, mesh upload, collider shape) at a few places. tools/test.sh tests/dev_chunk_cost.gd
const TIMEOUT_SECONDS := 120


func run(host: Node) -> void:
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	TerrainHeight.warm()
	for c: Vector2 in [Vector2(1573, 1200), Vector2(-2851, -451), Vector2(-567, -2240), Vector2(2000, -3000)]:
		var box := Rect2(floorf(c.x / 250.0) * 250.0, floorf(c.y / 250.0) * 250.0, 250.0, 250.0)
		var t0 := Time.get_ticks_usec()
		var d0 := TerrainMesher.build(box.position.x, box.position.y, 250.0, 32, 6.0, 0.0, true)
		var t_build0 := float(Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		var m := TerrainMesher.to_mesh(d0)
		var t_up := float(Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(d0["faces"])
		var t_shape := float(Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		var d1 := TerrainMesher.build(box.position.x, box.position.y, 250.0, 16, 14.0, 0.0, false)
		var t_build1 := float(Time.get_ticks_usec() - t0) / 1000.0
		print("CHUNKCOST at (%.0f, %.0f): LOD0 build %.0f ms, upload %.0f ms, collider shape %.0f ms (%d faces); LOD1 build %.0f ms" % [c.x, c.y, t_build0, t_up, t_shape, (d0["faces"] as PackedVector3Array).size() / 3, t_build1])
	Game.state = &"menu"
	main.queue_free()
