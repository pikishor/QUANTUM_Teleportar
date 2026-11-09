extends Node3D
## Look-dev stage for the vegetation kit (tools/shot.sh OUT res://tests/veg_viewer.tscn 20). QT_VIEW = "kit" (every piece in rows, default) or "lod" (the three LODs of pines and broadleafs side by side).
## QT_SCALE multiplies the pieces' size (1 = as modelled).
func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.68, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.72)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.22, 0.26, 0.15)
	ground.material_override = gm
	add_child(ground)
	var view := OS.get_environment("QT_VIEW")
	var sc := float(OS.get_environment("QT_SCALE")) if OS.get_environment("QT_SCALE") != "" else 1.0
	var rows: Array = []
	if view == "lod":
		rows = [["pine_a", "pine_l1", "pine_l2", "broad_a", "broad_l1", "broad_l2"]]
	else:
		rows = [["pine_a", "pine_b", "pine_c", "broad_a", "broad_b", "broad_c", "dead_a", "dead_b"], ["bush", "fern", "grass", "tuft", "rock_a", "rock_b", "rock_c", "pebble"]]
	var z := 0.0
	var tot := 0
	for row in rows:
		var x := -float(row.size() - 1) * 2.5
		for nm in row:
			var mi := MeshInstance3D.new()
			mi.mesh = VegKit.mesh(nm)
			mi.material_override = VegKit.material(nm)
			mi.position = Vector3(x, 0, z)
			mi.scale = Vector3.ONE * sc * (4.0 if nm == "pebble" else 1.0)
			add_child(mi)
			tot += VegKit.tris(nm)
			x += 5.0
		z -= 9.0
	print("KIT tris ", tot)
	var cam := Camera3D.new()
	cam.fov = 75
	cam.far = 500
	add_child(cam)
	cam.position = Vector3(0, 8.0, 28) if view != "lod" else Vector3(0, 5, 26)
	cam.look_at(Vector3(0, 3.5, -3 if view != "lod" else 0), Vector3.UP)
	cam.make_current()
