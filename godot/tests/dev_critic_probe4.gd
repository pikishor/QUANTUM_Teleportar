extends RefCounted
## Dev helper (LOOK critic, not a test): which long additive / transparent meshes hang near the west beach at dusk? tools/test.sh tests/dev_critic_probe4.gd


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	var p := Game.player as Player
	var city := Game.world as City
	city.day_night.frozen = true
	city.day_night.set_hour(19.0)
	var sx := -(TerrainHeight.WORLD_HALF - 120.0)
	while sx < -1000.0 and TerrainHeight.height_at(sx, -300.0) < TerrainHeight.SEA_LEVEL + 1.2:
		sx += 3.0
	var pos := Vector3(sx + 14.0, TerrainHeight.height_at(sx + 14.0, -300.0) + 0.8, -300.0)
	p.teleport_to(pos)
	if city.terrain != null:
		city.terrain.settle(pos)
	await TestLib.frames(host, 90)
	print("PROBE hero at ", pos)
	var n := 0
	for mi: Node in main.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var mat: Material = m.material_override
		var add := false
		if mat is StandardMaterial3D and (mat as StandardMaterial3D).blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
			add = true
		elif mat is ShaderMaterial and (mat as ShaderMaterial).shader != null and (mat as ShaderMaterial).shader.code.contains("blend_add"):
			add = true
		if not add:
			continue
		var bb := m.get_aabb()
		if bb.size.length() < 40.0:
			continue
		var d := m.global_position.distance_to(pos)
		print("PROBE additive %s at %s dist %.0f aabb %s shader %s" % [m.get_path(), str(m.global_position), d, str(bb.size), (mat as ShaderMaterial).shader.resource_path if mat is ShaderMaterial else "std"])
		n += 1
	print("PROBE additive big meshes: ", n)
	for nd: Node in main.find_children("*", "Node3D", true, false):
		var nm := String(nd.name).to_lower()
		if nm.contains("beam") or nm.contains("light") or nm.contains("sweep") or nm.contains("cone") or nm.contains("shaft"):
			var n3 := nd as Node3D
			print("PROBE named %s vis=%s at %s dist %.0f" % [nd.get_path(), str(n3.is_visible_in_tree()), str(n3.global_position), n3.global_position.distance_to(pos)])
	for mi2: Node in main.find_children("*", "GeometryInstance3D", true, false):
		var g := mi2 as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var d2 := g.global_position.distance_to(pos)
		if d2 > 260.0:
			continue
		var path := String(g.get_path())
		if path.contains("Terrain") or path.contains("Vegetation") or path.contains("Landscape/Veg"):
			continue
		print("PROBE near %s dist %.0f class %s" % [path, d2, g.get_class()])
	main.queue_free()
