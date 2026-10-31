class_name SkinnedMirror
extends Node
## The wet-street reflection of a SKINNED character that follows the pose. MirrorProxy copies a mesh by its transform, which for a skinned character is the rest pose (a second,
## stationary body: the bug that made the reflection get removed). This copy is a skinned MeshInstance3D of its own that shares the character's mesh, skin AND skeleton node, so it
## is posed by exactly the bone transforms the visible body gets (nothing is simulated twice, there is no second pose to drift), and it is placed under the world's `Mirror` node at
## the mirrored transform of the body every frame, like every other reflection.
## Cost: ONE extra draw call and the triangles of a coarse LOD (`lod_bias`, the same imported LODs as everything else; the mirror also needs a fraction of the detail) per character, only
## on MED and HIGH (the Mirror node is hidden on LOW) and only within RANGE metres of the camera; beyond it the copy is hidden. Unshaded stand-in material (the albedo atlas, dimmed
## like MirrorProxy's), no shadows, no lights. Without a world / Mirror node (tests, arenas) nothing is built.
##
##   var m := SkinnedMirror.new(); model.add_child(m); m.track(body_mesh)     # body_mesh: the skinned MeshInstance3D under the Skeleton3D

const PRIORITY := 90                     ## after the owners placed their bodies this frame, like MirrorProxy
const RANGE := 30.0                      ## default `range`: metres from the camera within which the reflection is drawn
const RANGE_HYSTERESIS := 6.0
const LOD_BIAS := 0.5
const GAIN := Color(0.9, 0.9, 0.9)
const FLOOR_TINT := Color(0.02, 0.035, 0.05)

var source: MeshInstance3D
var range := RANGE
var copy: MeshInstance3D
var _root: Node3D
var _flip := Transform3D(Basis.from_scale(Vector3(1.0, -1.0, 1.0)), Vector3.ZERO)
var _near := true
var _mat: Array[StandardMaterial3D] = []


func _ready() -> void:
	process_priority = PRIORITY
	set_process(source != null)


func _exit_tree() -> void:
	_free_copy()


func track(body: MeshInstance3D) -> void:
	_free_copy()
	source = body if body != null and body.mesh != null and body.skin != null and body.skeleton != NodePath("") else null
	_root = null
	set_process(is_inside_tree() and source != null)


func has_copy() -> bool:
	return is_instance_valid(copy)


func _process(_delta: float) -> void:
	if not is_instance_valid(source):
		return
	if _root == null or not is_instance_valid(_root):
		_root = Game.world.call(&"get_mirror_root") as Node3D if is_instance_valid(Game.world) and Game.world.has_method(&"get_mirror_root") else null
		if _root == null:
			return
		_build()
	if not _root.is_visible_in_tree() or not is_instance_valid(copy):
		return                                          # the LOW tier hides the whole mirrored city
	var show := source.is_visible_in_tree() and Game.quality >= 1
	if show and is_instance_valid(Game.camera):
		var d := Game.camera.global_position.distance_to(source.global_position)
		_near = d < range + (RANGE_HYSTERESIS if _near else 0.0)
		show = _near
	copy.visible = show
	if show:
		copy.transform = _root.global_transform.affine_inverse() * _flip * source.global_transform


func _build() -> void:
	copy = MeshInstance3D.new()
	copy.name = "SkinnedReflection"
	copy.mesh = source.mesh
	copy.skin = source.skin
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	copy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	copy.lod_bias = LOD_BIAS
	copy.extra_cull_margin = source.extra_cull_margin + 1.0
	copy.visible = false
	for s in source.mesh.get_surface_count():
		var src := source.mesh.surface_get_material(s) as BaseMaterial3D
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if src != null:
			m.albedo_texture = src.albedo_texture
			m.albedo_color = Color(GAIN.r + FLOOR_TINT.r, GAIN.g + FLOOR_TINT.g, GAIN.b + FLOOR_TINT.b, 1.0)
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		else:
			m.albedo_color = FLOOR_TINT
		copy.set_surface_override_material(s, m)
		_mat.append(m)
	_root.add_child(copy)
	copy.skeleton = copy.get_path_to(source.get_node(source.skeleton))       # the very same Skeleton3D node: same bones, same pose


func _free_copy() -> void:
	if is_instance_valid(copy):
		copy.queue_free()
	copy = null
	_mat.clear()
