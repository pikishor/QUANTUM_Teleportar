class_name AircraftScenery
extends RefCounted
## A parked or flying aircraft that is only a picture (no physics, no Vehicle node): the airliners at the gates and every plane and helicopter of the AIR TRAFFIC. Built from the same model as the flyable
## kind (the open-source glb, or the procedural helicopter), the "Body" surface painted from the kind's palette, the glass dark, rotor blades and the blur disc added for helicopters. No shadows, no lights.
##   make(kind, paint) -> Node3D with the nose at -Z and the wheels on y = 0, or null when the kind has no model
##   spin(node, dt, rate)   turns the rotor / propeller of a made aircraft (helicopters: Rotor and TailRotor; the blur disc takes over above the same spin speed as in flight)

static var _glass: StandardMaterial3D


static func make(kind: StringName, paint := 0) -> Node3D:
	var spec: Dictionary = VehicleSpecs.SPECS.get(kind, {})
	if spec.is_empty():
		return null
	var model: Node3D = null
	if spec.has("procedural"):
		model = VehicleCraftModels.build(String(spec["procedural"]), spec)
	else:
		model = Game.load_model(String(spec["model"]))
	if model == null:
		return null
	var root := Node3D.new()
	root.name = "Scenery_" + String(kind)
	root.add_child(model)
	var pal: Array = VehicleSpecs.PALETTES.get(kind, [Color(0.86, 0.87, 0.9)])
	var col: Color = pal[paint % pal.size()]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			var mat := src.duplicate() as BaseMaterial3D
			match String(src.resource_name):
				"Body":
					mat.albedo_color = col
					mat.metallic = 0.04                                   # (a metal paint mirrors the dark ground and the blue sky: purple planes)
					mat.roughness = 0.5
				"Glass":
					mat.albedo_color = Color(0.05, 0.08, 0.12)
					mat.metallic = 0.5
					mat.roughness = 0.12
			m.set_surface_override_material(s, mat)
	if spec.has("rotor_r") and model.get_node_or_null("Rotor") != null:
		var d := VehicleCraftModels.disc(float(spec["rotor_r"]), 0.08)
		d.name = "RotorDisc"
		d.position = (model.get_node("Rotor") as Node3D).position
		model.add_child(d)
	return root


## Spin the rotors of a made helicopter: `rate` 0..1 of full speed (a parked one is 0: the blades stand still, drooping a little).
static func spin(root: Node3D, rate: float, ang: float) -> void:
	var model := root.get_child(0) as Node3D
	if model == null:
		return
	var rotor := model.get_node_or_null("Rotor") as Node3D
	if rotor == null:
		return
	var disc := model.get_node_or_null("RotorDisc") as Node3D
	var blur := rate * 38.0 >= VehicleCraft.BLUR_SPIN
	rotor.visible = not blur
	if disc != null:
		disc.visible = blur
	rotor.rotation = Vector3.UP * ang
	var tail := model.get_node_or_null("TailRotor") as Node3D
	if tail != null:
		tail.rotation = Vector3.RIGHT * ang * 1.6
