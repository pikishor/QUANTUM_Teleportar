class_name MissionVisuals
extends RefCounted
## Builders for the mission module's visuals: the tall core beam, the trigger ring, glow halos and the per-instance glow tints of the legacy models.
## Everything here is created once and shared (materials, meshes, textures); the module pools the nodes.
##
## Readability (Direction + wave-1 findings): the legacy glow materials use emission 4-7x, which ACES turns white, so each model's `Glow` materials are
## duplicated with a saturated tint and an emission of about 2 (the model's own materials are never touched). The dark parts are lifted by the
## core's own omni light and, when it exists, by DynamicFill.

const BEAM_SHADER_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.2, 0.9, 1.0);
uniform float strength = 1.5;
uniform float height = 400.0;
uniform float top_fade = 0.35;
uniform float pulse = 0.0;
varying float h01;
void vertex() {
	h01 = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
}
void fragment() {
	float f = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(f, 1.6);
	float along = mix(1.0, top_fade, h01) * (1.0 + 0.12 * sin(TIME * 2.0 + h01 * 18.0 + pulse));
	ALBEDO = tint.rgb * strength;
	ALPHA = clamp(edge * along, 0.0, 1.0);
}
"""

static var _beam_shader: Shader
static var _soft_tex: GradientTexture2D
static var _tint_cache: Dictionary = {}
static var _beam_cache: Dictionary = {}
static var _halo_cache: Dictionary = {}
static var _ring_mat: StandardMaterial3D
static var _ring_mesh: TorusMesh

const CORE_MAGENTA := Color(1.0, 0.18, 0.92)
const CORE_CYAN := Color(0.25, 0.92, 1.0)
const HEALTH_GREEN := Color(0.25, 1.0, 0.4)
const ENERGY_CYAN := Color(0.2, 0.85, 1.0)


static func beam_shader() -> Shader:
	if _beam_shader == null:
		_beam_shader = Shader.new()
		_beam_shader.code = BEAM_SHADER_CODE
	return _beam_shader


## A tall open cylinder, centred on its node: place the node at height/2. One draw call, soft edges, never fogged.
static func make_beam(color: Color, radius: float, height: float, strength := 1.5, top_fade := 0.35) -> MeshInstance3D:
	var key := "%s/%s/%s/%s/%s" % [color.to_html(), radius, height, strength, top_fade]
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 10
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	m.mesh = cyl
	if not _beam_cache.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = beam_shader()
		mat.set_shader_parameter(&"tint", color)
		mat.set_shader_parameter(&"strength", strength)
		mat.set_shader_parameter(&"height", height)
		mat.set_shader_parameter(&"top_fade", top_fade)
		_beam_cache[key] = mat
	m.material_override = _beam_cache[key]
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.extra_cull_margin = 16384.0       # a 400 m column must never be culled by its small AABB centre test at the screen edge
	return m


## The flat ring on the ground that shows the 4 m trigger radius of a core.
static func make_ring(radius: float) -> MeshInstance3D:
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = radius - 0.14
		_ring_mesh.outer_radius = radius
		_ring_mesh.rings = 40
		_ring_mesh.ring_segments = 4
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat.albedo_color = Color(CORE_CYAN.r * 0.9, CORE_CYAN.g * 0.9, CORE_CYAN.b * 0.9, 0.75)
		_ring_mat.disable_receive_shadows = true
	var m := MeshInstance3D.new()
	m.mesh = _ring_mesh
	m.material_override = _ring_mat
	m.scale = Vector3(1.0, 0.05, 1.0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


static func soft_texture() -> GradientTexture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		g.add_point(0.35, Color(1.0, 1.0, 1.0, 0.45))
		g.set_color(g.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft_tex = t
	return _soft_tex


## A camera-facing soft glow sprite (one draw call): the floating marker that keeps a small pickup readable at 20-30 m.
static func make_halo(color: Color, size: float) -> MeshInstance3D:
	var key := "%s/%s" % [color.to_html(), size]
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	m.mesh = q
	if not _halo_cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_texture = soft_texture()
		mat.albedo_color = color
		mat.disable_receive_shadows = true
		mat.no_depth_test = false
		_halo_cache[key] = mat
	m.material_override = _halo_cache[key]
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## Override the model's glow surfaces: `tints` maps a material resource_name ("Glow", "GlowRing") to [color, energy]. The override is a duplicate of the
## model's own material with a new emission, shared by every instance of the same model, so the shared mesh resource stays untouched.
static func tint_glow(model: Node, model_name: String, tints: Dictionary) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null or not tints.has(src.resource_name):
				continue
			var key := "%s/%s" % [model_name, src.resource_name]
			if not _tint_cache.has(key):
				var spec: Array = tints[src.resource_name]
				var mat := src.duplicate() as StandardMaterial3D
				mat.emission_enabled = true
				mat.emission = spec[0]
				mat.emission_energy_multiplier = spec[1]
				mat.albedo_color = Color(0.03, 0.03, 0.03, 1.0)
				_tint_cache[key] = mat
			mi.set_surface_override_material(i, _tint_cache[key])


## Visible meshes of a model (for MirrorProxy.track).
static func meshes_of(model: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	return out


## Primitive stand-ins when a model is missing (the game must run without art).
static func fallback_gem() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.55
	s.height = 1.3
	s.radial_segments = 6
	s.rings = 3
	mi.mesh = s
	mi.position.y = 0.95
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.03, 0.03)
	mat.emission_enabled = true
	mat.emission = CORE_MAGENTA
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	root.add_child(mi)
	return root


static func fallback_pickup(color: Color) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.45, 0.45, 0.45)
	mi.mesh = b
	mi.position.y = 0.25
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.03, 0.03)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	root.add_child(mi)
	return root
