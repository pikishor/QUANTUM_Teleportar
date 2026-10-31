class_name ShadowProxy
extends RefCounted
## Cheaper shadow casters. Every shadow-casting surface costs one draw call and its triangles in EVERY shadow cascade, so a model that is lit with five surfaces
## (a car body: paint, trim, headlight glow, taillight glow, underglow) or a 15k-triangle skinned hero pays much more in the shadow pass than it shows on screen.
## A proxy is a second MeshInstance3D that is drawn ONLY into shadow maps (`SHADOWS_ONLY`, never into the camera pass), while the visible mesh stops casting:
##   * `static_proxy(mesh_instance)`: a mesh of the casting surfaces only (the glow / lamp / eye surfaces are skipped), built once per source mesh and shared.
##   * `skinned_proxy(mesh_instance)`: the same skinned mesh and skin on the same skeleton (so it follows the pose), asking the renderer for a coarse LOD (`lod_bias`):
##     the silhouette of a shadow does not need the 15k triangles of the hero.
## `set_enabled(proxy, on)` turns the shadow of a model on or off by distance (LOD hook): the proxy's `visible` flag, which the shadow pass respects.
## Nodes created here carry the group-free name "ShadowProxy"; tests that count meshes skip `cast_shadow == SHADOWS_ONLY`.

const PROXY_NAME := "ShadowProxy"
const NO_SHADOW := [&"Headlights", &"Taillights", &"Underglow", &"Glow", &"Eye", &"Visor"]
const SKINNED_LOD_BIAS := 0.25

static var _meshes := {}                      ## source mesh instance id -> ArrayMesh of the shadow surfaces (or null when no surface can be dropped)


## The casting surfaces of `mi` as one SHADOWS_ONLY child (identity transform), or null when all surfaces cast anyway (then `mi` simply keeps casting).
static func static_proxy(mi: MeshInstance3D) -> MeshInstance3D:
	if mi == null or mi.mesh == null:
		return null
	var sm := _shadow_mesh(mi.mesh)
	if sm == null:
		return null
	var p := MeshInstance3D.new()
	p.name = PROXY_NAME
	p.mesh = sm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.layers = mi.layers
	mi.add_child(p)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## A coarse-LOD shadow caster that shares the skeleton of the skinned `body` (a sibling of it): the body itself stops casting.
static func skinned_proxy(body: MeshInstance3D, lod_bias := SKINNED_LOD_BIAS) -> MeshInstance3D:
	if body == null or body.mesh == null or body.get_parent() == null or body.skin == null:
		return null
	var p := MeshInstance3D.new()
	p.name = PROXY_NAME
	p.mesh = body.mesh
	p.skin = body.skin
	p.skeleton = body.skeleton                      # same parent, same relative path
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	p.lod_bias = lod_bias
	p.layers = body.layers
	p.extra_cull_margin = body.extra_cull_margin
	body.get_parent().add_child(p)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Shadow on / off for a model whose caster is `proxy` (or `mi` itself when it has no proxy).
static func set_enabled(mi: MeshInstance3D, proxy: MeshInstance3D, on: bool) -> void:
	if proxy != null:
		proxy.visible = on
	elif mi != null:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _shadow_mesh(src: Mesh) -> ArrayMesh:
	var key := src.get_instance_id()
	if _meshes.has(key):
		return _meshes[key]
	var keep: Array[int] = []
	for s in src.get_surface_count():
		var mat := src.surface_get_material(s)
		if mat == null or not (StringName(mat.resource_name) in NO_SHADOW):
			keep.append(s)
	var out: ArrayMesh = null
	if keep.size() > 0 and keep.size() < src.get_surface_count():
		out = ArrayMesh.new()
		for s in keep:
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s))
			var mat := src.surface_get_material(s)
			out.surface_set_material(out.get_surface_count() - 1, mat)
	_meshes[key] = out
	return out
