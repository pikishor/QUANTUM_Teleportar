@tool
extends EditorScenePostImport
## Import script for assets/models/*.glb (set by tools/blender/patch_imports.py through `import_script/path` in the committed
## .import files). It turns what the Blender model scripts mark up into real nodes and settings glTF cannot carry. Blender custom
## properties arrive as the node meta "extras".
##
##  * An empty with the property `qt_light` (a JSON string, see helpers.light() in tools/blender) becomes an OmniLight3D or a
##    SpotLight3D at the empty's transform. Lights get no shadows, fade out with the camera distance, and join the group
##    `qt_model_lights` (hide that group on the LOW graphics tier). A light with mask "own" lights only its own model: it uses
##    light layer FILL_LAYER and the model's meshes join that layer, so a fill light can lift a character at night without
##    lighting the street.
##  * A node with `qt_vis_end` fades out beyond that distance (rotors, wheels: a few pixels at 50 m but a draw call each);
##    `qt_no_shadow` stops a mesh from casting shadows (no shadow draw for rotors and wheels).

## Visual layer (1..20) used by "own" lights. Layer 20 belongs to the player's character lights (PlayerBody.CHARACTER_LAYER).
const FILL_LAYER := 19
const GROUP := &"qt_model_lights"


func _post_import(scene: Node) -> Object:
	var found: Array[Node] = []
	_collect(scene, found)
	var fill_used := false
	for node in found:
		var extras: Dictionary = node.get_meta("extras", {}) if node.has_meta("extras") else {}
		if extras.has("qt_light") and node is Node3D:
			if _make_light(scene, node as Node3D, str(extras["qt_light"])):
				fill_used = fill_used or str(extras["qt_light"]).contains("\"own\"")
		elif node is GeometryInstance3D:
			var gi := node as GeometryInstance3D
			if extras.has("qt_vis_end"):
				gi.visibility_range_end = float(extras["qt_vis_end"])
				gi.visibility_range_end_margin = maxf(2.0, float(extras["qt_vis_end"]) * 0.08)
				gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if extras.has("qt_no_shadow"):
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if fill_used:
		for node in found:
			if is_instance_valid(node) and node is GeometryInstance3D:
				(node as GeometryInstance3D).layers |= 1 << (FILL_LAYER - 1)
	return scene


func _collect(n: Node, out: Array[Node]) -> void:
	for c in n.get_children():
		out.append(c)
		_collect(c, out)


func _make_light(scene: Node, marker: Node3D, json: String) -> bool:
	var spec: Variant = JSON.parse_string(json)
	if typeof(spec) != TYPE_DICTIONARY:
		push_warning("post_import: bad qt_light on %s" % marker.name)
		return false
	var d: Dictionary = spec
	var light: Light3D
	var col_a: Array = d.get("color", [1.0, 1.0, 1.0])
	var color := Color(float(col_a[0]), float(col_a[1]), float(col_a[2]))
	if str(d.get("type", "omni")) == "spot":
		var s := SpotLight3D.new()
		s.spot_range = float(d.get("range", 10.0))
		s.spot_angle = float(d.get("angle", 40.0))
		s.spot_attenuation = float(d.get("attenuation", 1.4))
		s.spot_angle_attenuation = float(d.get("spot_attenuation", 1.0))
		light = s
	else:
		var o := OmniLight3D.new()
		o.omni_range = float(d.get("range", 6.0))
		o.omni_attenuation = float(d.get("attenuation", 1.4))
		light = o
	light.light_color = color
	light.light_energy = float(d.get("energy", 1.0))
	light.shadow_enabled = false
	var fade: Array = d.get("fade", [35.0, 15.0])
	if fade.size() >= 2 and float(fade[1]) > 0.0:
		light.distance_fade_enabled = true
		light.distance_fade_begin = float(fade[0])
		light.distance_fade_length = float(fade[1])
		light.distance_fade_shadow = float(fade[0])
	if str(d.get("mask", "world")) == "own":
		light.light_cull_mask = 1 << (FILL_LAYER - 1)
	var parent := marker.get_parent()
	var idx := marker.get_index()
	var xf := marker.transform
	var marker_name := marker.name
	parent.remove_child(marker)
	marker.free()
	light.name = marker_name              # after the marker is gone, or Godot would rename the light to avoid the clash
	parent.add_child(light)
	parent.move_child(light, idx)
	light.owner = scene
	light.transform = xf
	light.add_to_group(GROUP, true)
	return true
