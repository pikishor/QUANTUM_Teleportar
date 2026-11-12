class_name MirrorProxy
extends Node
## The wet-street reflection of a dynamic object.
##
## The world draws its reflections as geometry: a mirrored copy of the city lives under the alpha-blended ground (City, node "Mirror", see
## City.get_mirror_root()), and the ground shader reads that copy back from the screen. Things that move (the player, enemies, vehicles) are not part
## of that copy, so on wet asphalt they would stand there without a reflection while every building has one. A MirrorProxy gives one object its
## reflection: it keeps one cheap unshaded copy of each tracked mesh under the Mirror node and puts it, every frame, at the mirrored transform of the
## original. Meshes are shared with the originals (no extra memory); only the materials are new (unshaded, brightened to stand in for the light the original receives, glowing parts kept bright).
##
## Cost: one draw call per surface of the tracked meshes, on the MED and HIGH tiers only (the Mirror node is hidden on LOW, and the proxy then does nothing).
## It never touches the originals. No world, no Mirror node (unit tests, arenas): nothing is built and nothing runs but a cheap lookup per frame.
##
## Use:
##   var reflection := MirrorProxy.new()
##   add_child(reflection)                  # lives and dies with its owner
##   reflection.track(meshes)               # Array[MeshInstance3D]: the owner's visible meshes (not flashes, sprites or shadows)
## A tracked mesh that is hidden (or whose owner is hidden: a player inside a vehicle) hides its reflection as well.

const PRIORITY := 90                     ## after the owners (0) have placed their meshes for this frame, before the camera rig (100)
## Gain on the original albedo. The proxy is unshaded, so this stands in for the light the real surface receives (key, rim and a few lamps):
## the real hero reads about 2.5x brighter than his raw albedo, and the ground shader then dims the reflection by Fresnel and smear.
const ALBEDO_GAIN := 2.4
## A faint cool floor, so dark parts still separate from the black asphalt reflections around them.
const FLOOR_TINT := Color(0.025, 0.045, 0.06)
const GLOW_KEEP := 1.0

var _sources: Array[MeshInstance3D] = []
var _copies: Array[MeshInstance3D] = []
var _root: Node3D
var _flip := Transform3D(Basis.from_scale(Vector3(1.0, -1.0, 1.0)), Vector3.ZERO)


func _ready() -> void:
	process_priority = PRIORITY
	set_process(not _sources.is_empty())


func _exit_tree() -> void:
	_free_copies()


## Reflect these meshes (replaces any earlier list). The copies are built as soon as the world's Mirror node exists.
func track(meshes: Array[MeshInstance3D]) -> void:
	_free_copies()
	_sources.clear()
	for m in meshes:
		if m != null and m.mesh != null:
			_sources.append(m)
	_root = null
	set_process(is_inside_tree() and not _sources.is_empty())


## Number of reflection meshes currently built (0 until the world's Mirror node exists), for tests and the budget report.
func copy_count() -> int:
	var n := 0
	for c in _copies:
		if is_instance_valid(c):
			n += 1
	return n


func _process(_delta: float) -> void:
	if _root == null or not is_instance_valid(_root):
		_root = _find_root()
		if _root == null:
			return
		_build_copies()
	if not _root.is_visible_in_tree():
		return                                         # the LOW tier hides the whole mirrored city: nothing to keep in sync
	var to_local := _root.global_transform.affine_inverse() * _flip
	for i in _sources.size():
		var copy := _copies[i]
		var src := _sources[i]
		if not is_instance_valid(copy):
			continue
		var show := is_instance_valid(src) and src.is_visible_in_tree()
		copy.visible = show
		if show:
			copy.transform = to_local * src.global_transform


func _find_root() -> Node3D:
	if is_instance_valid(Game.world) and Game.world.has_method(&"get_mirror_root"):
		return Game.world.call(&"get_mirror_root") as Node3D
	return null


func _build_copies() -> void:
	_copies.clear()
	for src in _sources:
		var copy := MeshInstance3D.new()
		copy.name = "Reflection_%s" % src.name
		copy.mesh = src.mesh
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		copy.visible = false
		for s in src.mesh.get_surface_count():
			copy.set_surface_override_material(s, make_material(src.get_active_material(s)))
		_root.add_child(copy)
		_copies.append(copy)


func _free_copies() -> void:
	for c in _copies:
		if is_instance_valid(c):
			c.queue_free()
	_copies.clear()


## The unshaded stand-in of a material: the same texture and tiling, albedo brightened; an emissive material becomes a bright flat colour.
static func make_material(source: Material) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sm := source as ShaderMaterial
	if sm != null:                                          # a Cars v2 shader material: its paint colour stands in (car_paint / car_lod keep it in the `paint` uniform)
		var pc: Variant = sm.get_shader_parameter(&"paint")
		if pc is Color:
			var c := pc as Color
			m.albedo_color = Color(c.r * ALBEDO_GAIN + FLOOR_TINT.r, c.g * ALBEDO_GAIN + FLOOR_TINT.g, c.b * ALBEDO_GAIN + FLOOR_TINT.b, 1.0)
			return m
	var b := source as BaseMaterial3D
	if b == null:
		m.albedo_color = FLOOR_TINT
		return m
	if b.emission_enabled:
		var e := b.emission * b.emission_energy_multiplier * GLOW_KEEP
		m.albedo_color = Color(e.r, e.g, e.b, 1.0)
		return m
	m.vertex_color_use_as_albedo = b.vertex_color_use_as_albedo
	m.albedo_texture = b.albedo_texture
	m.uv1_scale = b.uv1_scale
	m.uv1_offset = b.uv1_offset
	m.texture_repeat = b.texture_repeat
	var a := b.albedo_color
	m.albedo_color = Color(a.r * ALBEDO_GAIN + FLOOR_TINT.r, a.g * ALBEDO_GAIN + FLOOR_TINT.g, a.b * ALBEDO_GAIN + FLOOR_TINT.b, 1.0)
	return m
