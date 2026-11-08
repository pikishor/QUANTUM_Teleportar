extends Node3D
## Look-dev of the flood water on a plain street floor: tools/vehicle_view-style screenshot. `godot --path . res://tests/flood_view.tscn -- out=/tmp/x.png`
var _frames := 0
var _out := "/tmp/flood.png"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv.size() > 1 and kv[0] == "out":
			_out = kv[1]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.42, 0.55)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300.0, 300.0)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.21, 0.24)
	fl.material_override = fm
	add_child(fl)
	for i in 6:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(20.0, 30.0, 20.0)
		b.mesh = bm
		b.position = Vector3(-60.0 + i * 24.0, 15.0, -30.0)
		add_child(b)
	var w := FloodZone.attach(self)
	w.position = Vector3(0.0, FloodZone.LEVEL, 0.0)
	var m := (w.mesh as PlaneMesh).material as ShaderMaterial
	m.set_shader_parameter(&"rect", Vector4(-140.0, -140.0, 140.0, 140.0))
	(w.mesh as PlaneMesh).size = Vector2(300.0, 300.0)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 8.0, 40.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.0, 0.0))
	cam.make_current()


func _process(_dt: float) -> void:
	_frames += 1
	if _frames == 8:
		get_viewport().get_texture().get_image().save_png(_out)
		get_tree().quit()
