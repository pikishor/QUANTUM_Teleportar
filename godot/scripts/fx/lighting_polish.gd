class_name LightingPolish
extends RefCounted
## Lighting polish helpers (pure functions + one merged light-cone mesh). No lights, no extra draws except ONE additive mesh for all street lamps.
## - window_mood(hour): global shader vec4 `window_mood` (rgb tint of lit windows, a = share of windows still lit), driven by DayNight.
## - flicker(t, seed): neon tube flicker factor 0..1 (same shape as the signage shader, for tests and CPU-side emissive users).
## - glow_for(night, tier): bloom strength scale so daytime windows/signs do not bloom.
## - build_cones(heads): one ArrayMesh of open cones below the lamp heads, vertex alpha falls off to the ground.

const MOOD_PARAM := &"window_mood"
const CONE_HEIGHT := 7.0
const CONE_RADIUS := 3.2
const CONE_SIDES := 10                ## ten faces with smooth normals: six flat faces read as a paper tent at MED (director review 5, defect 11)
const CONE_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
global uniform float night;
global uniform float rain;
uniform float strength = 0.06;
void fragment() {
	float flick = 0.94 + 0.06 * sin(TIME * 2.1 + float(VERTEX.x) * 0.37);
	// a soft haze, not a solid wedge: the brightness falls to nothing at the silhouette (view along the surface), squares away along the height and fades near the lens
	float nv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float haze = pow(nv, 2.6) * COLOR.a * COLOR.a * (0.75 + 0.25 * COLOR.a);      // a steeper falloff than 1.7: the wall of a cone seen from the side no longer ends in a hard straight edge (paper tents at MED, director review 5 #11a)
	float lens = smoothstep(3.0, 12.0, length(VERTEX));
	ALBEDO = COLOR.rgb * haze * strength * night * (1.0 + 0.5 * rain) * flick * lens;
}
"""


## Tint (rgb) and lit share (a) for an hour 0..24: late evening warm and full, deep night thinned out, pre-dawn cool, day nearly off.
static func window_mood(h: float) -> Color:
	h = fposmod(h, 24.0)
	var evening := smoothstep(17.5, 20.0, h) * (1.0 - smoothstep(22.0, 24.0, h))
	var deep := smoothstep(1.0, 3.5, h) * (1.0 - smoothstep(4.5, 6.0, h))
	var late := smoothstep(22.0, 24.0, h) if h >= 12.0 else 1.0 - smoothstep(0.0, 2.0, h)
	var warm := Color(1.10, 0.92, 0.72)
	var cool := Color(0.86, 0.96, 1.12)
	var tint := Color(1, 1, 1).lerp(warm, evening).lerp(cool, deep)
	var life := 1.0 - 0.45 * clampf(late, 0.0, 1.0) - 0.30 * deep
	life = clampf(life, 0.3, 1.0)
	return Color(tint.r, tint.g, tint.b, life)


## Neon flicker factor: gentle hum plus the odd dropout, deterministic per seed and time.
static func flicker(t: float, seed_v: float) -> float:
	var hum := 0.88 + 0.12 * sin(t * 2.0 + seed_v * 30.0)
	var drop := 1.0 if fposmod(sin(floorf(t * 8.0) * 12.9898 + seed_v * 77.0) * 43758.5453, 1.0) < 0.992 else 0.1
	return hum * drop


## Bloom strength multiplier: 0.65 by day (lit windows and tubes are weak then), 1.0 at night; LOW stays a touch lower.
static func glow_for(night: float, tier: int) -> float:
	return lerpf(0.65, 1.0, clampf(night, 0.0, 1.0)) * (0.9 if tier == 0 else 1.0)


## heads: Array of Vector3 lamp head positions. One merged mesh (6 tris per lamp), vertex colour = warm light, alpha 1 at the head, 0 on the ground.
static func build_cones(heads: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var top_c := Color(1.0, 0.72, 0.40, 1.0)
	var bot_c := Color(1.0, 0.72, 0.40, 0.0)
	var up_k := CONE_RADIUS / CONE_HEIGHT                    # the side normal of a cone leans up by this much
	for h in heads:
		var p: Vector3 = h
		for i in CONE_SIDES:
			var a0 := TAU * float(i) / float(CONE_SIDES)
			var a1 := TAU * float(i + 1) / float(CONE_SIDES)
			var am := (a0 + a1) * 0.5
			var base := verts.size()
			verts.append(p)                                  # an apex vertex per face, its normal points out of the face middle: smooth across the face, no hard tent edges
			norms.append(Vector3(cos(am), up_k, sin(am)).normalized())
			cols.append(top_c)
			verts.append(Vector3(p.x + cos(a0) * CONE_RADIUS, 0.05, p.z + sin(a0) * CONE_RADIUS))
			norms.append(Vector3(cos(a0), up_k, sin(a0)).normalized())
			cols.append(bot_c)
			verts.append(Vector3(p.x + cos(a1) * CONE_RADIUS, 0.05, p.z + sin(a1) * CONE_RADIUS))
			norms.append(Vector3(cos(a1), up_k, sin(a1)).normalized())
			cols.append(bot_c)
			idx.append(base)
			idx.append(base + 1)
			idx.append(base + 2)
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func make_cone_node(heads: Array) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "LampCones"
	mi.mesh = build_cones(heads)
	var sh := Shader.new()
	sh.code = CONE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.custom_aabb = AABB(Vector3(-400, 0, -400), Vector3(800, 8, 800))
	return mi
