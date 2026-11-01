class_name DynamicFill
extends RefCounted
## Shared readability rig for dynamic characters (enemies, and any later module that needs it: pickups, vehicles, civilians).
##
## The legacy models (operative, drones, cars, pickups) are vertex-coloured almost black (about 0.04) and the night city has no real lights besides
## the moon, so unlit they vanish into the wet asphalt. DynamicFill.apply(model, tint) makes them readable without turning them into toys:
##   1. every mesh goes on visual layer 19 as well as layer 1 (layer 20 is the player's), so ONE shared directional light with a cull mask of
##      layer 19 only lights characters and never the world;
##   2. every surface gets a per-instance override material (GLB instances share meshes and materials, the imported resources are never touched):
##      the albedo multiplier is chosen from the mesh's own vertex colours so the result is at least about 0.10, plus a faint fresnel rim and a
##      faint emissive floor in the tint, so the silhouette survives the shadows;
##   3. the Eye / Glow / Visor surfaces are colour-coded with emission in the tint (at most 2: the filmic tonemap whitens more).
## The light is created once (ensure_light), is a low-energy cool fill, follows the camera yaw (aim_light) so faces turned to the player are lit,
## and is off on the LOW tier (set_quality).
## Compatibility renderer: it lights everything much brighter, so the boosts are scaled down there (same idea as PlayerBody).

const FILL_LAYER := 19                       ## visual layer number (1..20)
const FILL_BIT := 1 << (FILL_LAYER - 1)
const TARGET_ALBEDO := 0.10                  ## the darkest surface should reach about this albedo
const MAX_LIFT := 4.0
const GLOW_ENERGY := 2.0                     ## emission of colour-coded eyes and visors (ACES whitens above this)
const COMPAT_SCALE := 1.0
const LIGHT_NAME := "DynamicFillLight"
const FILL_COLOR := Color(0.62, 0.78, 1.0)   ## cool fill
const FILL_ENERGY := 0.6
const FILL_PITCH := -32.0                    ## degrees: the light shines down a little, from behind the camera

static var _light: DirectionalLight3D
static var _tex_cache := {}
static var _lift_cache := {}                 ## mesh key (resource_path + "#" + surface, else instance id * 16 + surface) -> albedo multiplier


## Put `model` on the fill layer and give every surface its own readable material. Call once per model instance (it is idempotent only
## for the layer: a second call would lift the already lifted copies again).
static func apply(model: Node3D, tint: Color) -> void:
	var compat := _is_compat()
	var k := COMPAT_SCALE if compat else 1.0
	for mi: MeshInstance3D in _meshes(model):
		mi.layers = mi.layers | FILL_BIT
		var mesh := mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			var m := src.duplicate() as BaseMaterial3D
			var mname := String(src.resource_name)
			if mname.contains("Glow") or mi.name == &"Eye":
				m.emission_enabled = true
				m.emission = tint
				m.emission_energy_multiplier = GLOW_ENERGY * (0.6 if mname.contains("Hover") else 1.0)
			elif mname == "Visor":
				m.emission_enabled = true
				m.emission = tint
				m.emission_energy_multiplier = 0.9
			else:
				var lift := lerpf(1.0, _lift_for(mesh, s, m), k)
				m.albedo_color = Color(m.albedo_color.r * lift, m.albedo_color.g * lift, m.albedo_color.b * lift, m.albedo_color.a)
				m.rim_enabled = true
				m.rim = 0.35 * k
				m.rim_tint = 0.55
				m.emission_enabled = true
				m.emission = tint.lerp(Color(0.5, 0.7, 1.0), 0.5)
				m.emission_energy_multiplier = 0.07 if not compat else 0.2
			mi.set_surface_override_material(s, m)


## The real lights an imported model carries (post_import.gd turns the marker empties `qt_light` into OmniLight3D / SpotLight3D, group `qt_model_lights`). They are part of
## the look (a trooper without its fill and rim lights is a black cut-out, a car loses its underglow pool) but they are per-object lights, so they are budgeted: `keep` lists the
## node names that stay (empty = keep all), the others are freed (a car's headlight SPOT and its own fill duplicate the shared fill light and the emissive lamps), and the kept ones are
## returned so the owner can switch them off beyond PerfTiers.light_range() (Drone.update_lod, Vehicle.update_lod). The lights fade with distance by themselves as well.
static func trim_lights(model: Node, keep: PackedStringArray = PackedStringArray()) -> Array[Light3D]:
	var kept: Array[Light3D] = []
	for n in model.find_children("*", "Light3D", true, false):
		var l := n as Light3D
		if keep.is_empty() or String(l.name) in keep:
			kept.append(l)
		else:
			l.get_parent().remove_child(l)
			l.free()
	return kept


static func set_lights_visible(lights: Array[Light3D], on: bool) -> void:
	for l in lights:
		if is_instance_valid(l):
			l.visible = on


## All MeshInstance3D nodes under (and including) `root`.
static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n as MeshInstance3D)
		stack.append_array(n.get_children())
	return out


## Albedo multiplier that brings the surface (its albedo colour times the mean vertex colour) to about TARGET_ALBEDO.
static func _lift_for(mesh: Mesh, surface: int, m: BaseMaterial3D) -> float:
	var key: Variant = (mesh.resource_path + "#" + str(surface)) if mesh.resource_path != "" else mesh.get_instance_id() * 16 + surface     # path first: a reloaded model has new mesh objects
	if _lift_cache.has(key):
		return _lift_cache[key]
	var lum := _lum(m.albedo_color)
	if m.albedo_texture != null:
		lum *= _texture_lum(m.albedo_texture)
	if m.vertex_color_use_as_albedo or m.albedo_texture == null:
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.size() > Mesh.ARRAY_COLOR and arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
			var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			if cols.size() > 0:
				var sum := 0.0
				var step := maxi(1, cols.size() / 256)
				var n := 0
				for i in range(0, cols.size(), step):
					sum += _lum(cols[i])
					n += 1
				lum *= sum / maxf(1.0, float(n))
	var lift := clampf(TARGET_ALBEDO / maxf(lum, 0.001), 1.0, MAX_LIFT)
	_lift_cache[key] = lift
	return lift


## Mean luminance of an albedo texture (read once per texture; 0.3 when the pixels cannot be read, e.g. a GPU-only format).
static func _texture_lum(tex: Texture2D) -> float:
	var key: Variant = tex.resource_path if tex.resource_path != "" else tex.get_instance_id()     # path first: a reloaded model has new texture objects, and each miss decompresses the image
	if _tex_cache.has(key):
		return _tex_cache[key]
	var lum := 0.3
	var img := tex.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			if img.decompress() != OK:
				img = null
		if img != null:
			img.resize(4, 4, Image.INTERPOLATE_BILINEAR)
			var sum := 0.0
			for y in 4:
				for x in 4:
					sum += _lum(img.get_pixel(x, y))
			lum = clampf(sum / 16.0, 0.02, 1.0)
	_tex_cache[key] = lum
	return lum


static func _lum(c: Color) -> float:
	return c.r * 0.3 + c.g * 0.5 + c.b * 0.2


static func _is_compat() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## The one shared fill light. Created on first use under `parent` (the enemy manager, or the world) and reused afterwards; nothing for LOW.
static func ensure_light(parent: Node) -> DirectionalLight3D:
	if is_instance_valid(_light) and _light.is_inside_tree():
		return _light
	var l := DirectionalLight3D.new()
	l.name = LIGHT_NAME
	l.light_cull_mask = FILL_BIT
	l.shadow_enabled = false
	l.light_color = FILL_COLOR
	l.light_energy = FILL_ENERGY * (2.4 if _is_compat() else 1.0)
	l.light_specular = 0.35
	l.rotation_degrees = Vector3(FILL_PITCH, 0.0, 0.0)
	l.visible = Game.quality >= 1
	parent.add_child(l)
	_light = l
	return l


static func get_light() -> DirectionalLight3D:
	return _light if is_instance_valid(_light) else null


static func set_quality(level: int) -> void:
	if is_instance_valid(_light):
		_light.visible = level >= 1


## Make the light shine along the camera's yaw (from behind the camera over the player toward the enemies), so faces turned to the player are lit.
static func aim_light(cam_yaw: float) -> void:
	if is_instance_valid(_light):
		_light.rotation = Vector3(deg_to_rad(FILL_PITCH), cam_yaw, 0.0)
