class_name CarParts
extends RefCounted
## What makes a car stop reading as a toy (round 4, "cars not cartoon"): real wheels (tyre with sidewall and tread, a dished rim with spokes, a brake disc behind), tinted glass that
## is split off the dark "Details" surface of the open-source models (so it can reflect the sky and glow from inside at night), licence plates (a shared set of generated textures),
## and a soft headlight beam. Everything is generated once, cached and shared by every car (no texture files, no new imports); the per-car cost is 4 wheel meshes swapped in place,
## 2 plate quads and 1 beam mesh (all with a visibility range) and one extra surface on the body for the glass.
##
## Used by `VehicleVisual.build`; the pure functions here are covered by tests/test_cars_world_scale.gd.

const WHEEL_SEGMENTS := 28                   ## HIGH; MED 20, LOW 14 (a wheel is 580 / 420 / 300 triangles): see `segments()`
const GLASS_FROM := 0.52                     ## triangles of the "Details" surface above this fraction of the body height are windows (the rest is bumpers, arches, grille)
const PLATE_W := 0.52
const PLATE_H := 0.12
const PLATE_VARIANTS := 8
const BEAM_LEN := 15.0
const BEAM_SHADER_CODE := """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
global uniform float night;
global uniform float wetness;
instance uniform float k : hint_range(0.0, 2.0) = 0.0;     // headlight factor of this car (VehicleVisual.set_lights)
varying float v_a;
void vertex() { v_a = COLOR.a; }
void fragment() {
	float edge = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 1.6);   // the shell fades at its silhouette: a shaft of light, not a solid cone
	float gain = (0.06 + 0.94 * night * night) * (0.7 + 0.8 * clamp(wetness, 0.0, 1.0));
	ALBEDO = vec3(1.0, 0.93, 0.78) * v_a * edge * gain * k * 0.05;
	ALPHA = 1.0;
}
"""

static var _wheel_cache := {}
static var _tyre_mat: StandardMaterial3D
static var _rim_mat: StandardMaterial3D
static var _brake_mat: StandardMaterial3D
static var _glass_mat: StandardMaterial3D
static var _plate_tex: Array[ImageTexture] = []
static var _plate_mats: Array[StandardMaterial3D] = []
static var _plate_mesh: QuadMesh
static var _beam_cache := {}
static var _beam_shader: Shader
static var _split_cache := {}
static var _beam_mat: ShaderMaterial


# --- wheels ---------------------------------------------------------------------------------------------------------------------------------------------

## A wheel of radius `r` and tyre width `w`, axle along X, centred on the origin, shifted outward by `shift` along X (the tyre sits flush with the body). Three surfaces: tyre, rim, brake disc.
static func segments() -> int:
	return WHEEL_SEGMENTS if Game.quality >= 2 else (20 if Game.quality == 1 else 14)


static func wheel_mesh(r: float, w: float, shift := 0.0) -> ArrayMesh:
	var segs := segments()
	var key := "%d_%d_%d_%d" % [roundi(r * 1000.0), roundi(w * 1000.0), roundi(shift * 1000.0), segs]
	if _wheel_cache.has(key):
		return _wheel_cache[key]
	_ensure_wheel_materials()
	var rr := r * 0.62                                   # rim radius (the tyre sidewall is 38 % of the radius: a normal car, not a toy)
	var h := r - rr
	var hw := w * 0.5
	var mesh := ArrayMesh.new()
	# tyre: a revolved profile (x along the axle, y = radius), smooth normals round the wheel and along the profile
	var prof: Array[Vector2] = [Vector2(-hw * 0.86, rr), Vector2(-hw, rr + h * 0.42), Vector2(-hw * 0.94, r - h * 0.2), Vector2(-hw * 0.66, r), Vector2(hw * 0.66, r),
			Vector2(hw * 0.94, r - h * 0.2), Vector2(hw, rr + h * 0.42), Vector2(hw * 0.86, rr)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_prof := prof.size()
	for j in n_prof:
		var a: Vector2 = prof[maxi(j - 1, 0)]
		var b: Vector2 = prof[mini(j + 1, n_prof - 1)]
		var t := (b - a).normalized()
		var pn := Vector2(t.y, -t.x)                      # outward normal of the profile in (x, radius) space
		for i in segs + 1:
			var ang := TAU * float(i) / float(segs)
			var cy := cos(ang)
			var sy := sin(ang)
			st.set_normal(Vector3(pn.x, pn.y * cy, pn.y * sy).normalized())
			st.set_uv(Vector2(float(i) / float(segs), float(j) / float(n_prof - 1)))
			st.add_vertex(Vector3(prof[j].x + shift, prof[j].y * cy, prof[j].y * sy))
	for j in n_prof - 1:
		for i in segs:
			var i0 := j * (segs + 1) + i
			var i1 := i0 + 1
			var i2 := i0 + segs + 1
			var i3 := i2 + 1
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i3)
	st.generate_tangents()
	mesh = st.commit(mesh)
	mesh.surface_set_material(0, _tyre_mat)
	mesh.surface_set_name(0, "Tyre")
	# rim: a lip ring, five spokes and a hub cap on both faces
	var rs := SurfaceTool.new()
	rs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		var x := side * hw * 0.8 + shift
		var xo := side * hw * 0.88 + shift
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			_quad(rs, Vector3(xo, rr * 1.0 * cos(a0), rr * 1.0 * sin(a0)), Vector3(xo, rr * 1.0 * cos(a1), rr * 1.0 * sin(a1)),
					Vector3(x, rr * 0.9 * cos(a1), rr * 0.9 * sin(a1)), Vector3(x, rr * 0.9 * cos(a0), rr * 0.9 * sin(a0)), Vector3(side, 0.0, 0.0))
		for sp in 5:
			var a := TAU * float(sp) / 5.0 + 0.3
			var half := 0.17                                # spoke half angle at the rim, narrower at the hub
			var p0 := Vector3(x, rr * 0.2 * cos(a - 0.38), rr * 0.2 * sin(a - 0.38))
			var p1 := Vector3(x, rr * 0.2 * cos(a + 0.38), rr * 0.2 * sin(a + 0.38))
			var p2 := Vector3(x, rr * 0.9 * cos(a + half), rr * 0.9 * sin(a + half))
			var p3 := Vector3(x, rr * 0.9 * cos(a - half), rr * 0.9 * sin(a - half))
			_quad(rs, p0, p1, p2, p3, Vector3(side, 0.0, 0.0))
		for i in 10:                                         # hub cap
			var a0 := TAU * float(i) / 10.0
			var a1 := TAU * float(i + 1) / 10.0
			_tri(rs, Vector3(x + side * 0.012, 0.0, 0.0), Vector3(x, rr * 0.22 * cos(a0), rr * 0.22 * sin(a0)), Vector3(x, rr * 0.22 * cos(a1), rr * 0.22 * sin(a1)), Vector3(side, 0.0, 0.0))
	rs.generate_tangents()
	mesh = rs.commit(mesh)
	mesh.surface_set_material(1, _rim_mat)
	mesh.surface_set_name(1, "Rim")
	# brake disc, seen between the spokes
	var bs := SurfaceTool.new()
	bs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		var x := side * hw * 0.5 + shift
		for i in 16:
			var a0 := TAU * float(i) / 16.0
			var a1 := TAU * float(i + 1) / 16.0
			_tri(bs, Vector3(x, 0.0, 0.0), Vector3(x, rr * 0.8 * cos(a0), rr * 0.8 * sin(a0)), Vector3(x, rr * 0.8 * cos(a1), rr * 0.8 * sin(a1)), Vector3(side, 0.0, 0.0))
	bs.generate_tangents()
	mesh = bs.commit(mesh)
	mesh.surface_set_material(2, _brake_mat)
	mesh.surface_set_name(2, "Brake")
	_wheel_cache[key] = mesh
	return mesh


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	var fn := (b - a).cross(c - a)
	var flip := fn.dot(n) < 0.0                           # wind so the face looks along `n`
	for p: Vector3 in ([a, c, b] if flip else [a, b, c]):
		st.set_normal(n)
		st.set_uv(Vector2(p.y, p.z))
		st.add_vertex(p)


static func _ensure_wheel_materials() -> void:
	if _tyre_mat != null:
		return
	_tyre_mat = StandardMaterial3D.new()
	_tyre_mat.resource_name = "Tyre"
	_tyre_mat.albedo_color = Color(0.11, 0.115, 0.125)
	_tyre_mat.roughness = 0.7
	_tyre_mat.metallic = 0.0
	_rim_mat = StandardMaterial3D.new()
	_rim_mat.resource_name = "Rim"
	_rim_mat.albedo_color = Color(0.66, 0.68, 0.72)
	_rim_mat.metallic = 0.92
	_rim_mat.roughness = 0.26
	_rim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_brake_mat = StandardMaterial3D.new()
	_brake_mat.resource_name = "Brake"
	_brake_mat.albedo_color = Color(0.13, 0.13, 0.14)
	_brake_mat.metallic = 0.6
	_brake_mat.roughness = 0.55
	_brake_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


## Swap the meshes of a car's four wheel nodes (MeshInstance3D children named WheelFL / FR / RL / RR) for real wheels of radius `r`. Returns how many were swapped.
static func upgrade_wheels(model: Node3D, r: float, w: float) -> int:
	var n := 0
	for nm: StringName in VehicleVisual.WHEEL_NAMES:
		var mi := model.get_node_or_null(NodePath(nm)) as MeshInstance3D
		if mi == null:
			continue
		var sign := signf(mi.position.x) if absf(mi.position.x) > 0.05 else 1.0
		mi.mesh = wheel_mesh(r, w, sign * 0.045)
		for s in 3:
			mi.set_surface_override_material(s, null)
		mi.visibility_range_end = 0.0
		n += 1
	return n


# --- glass ----------------------------------------------------------------------------------------------------------------------------------------------

static func glass_material() -> StandardMaterial3D:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.resource_name = "Glass"
		_glass_mat.albedo_color = Color(0.02, 0.03, 0.045)
		_glass_mat.metallic = 0.15
		_glass_mat.metallic_specular = 1.0
		_glass_mat.roughness = 0.05
		_glass_mat.rim_enabled = true
		_glass_mat.rim = 0.22
		_glass_mat.rim_tint = 0.4
		_glass_mat.emission_enabled = true
		_glass_mat.emission = Color(0.5, 0.62, 0.78)
		_glass_mat.emission_energy_multiplier = 0.0
		_glass_mat.cull_mode = BaseMaterial3D.CULL_BACK            # the panes face outward: from inside the car (hood view) they are not drawn, the road shows through
	return _glass_mat


## The triangles of surface `si` that count as windows: centroid above `from_y`. Returns the index arrays [rest, glass] (the vertex arrays are shared).
static func split_indices(verts: PackedVector3Array, idx: PackedInt32Array, from_y: float) -> Array:
	var rest := PackedInt32Array()
	var glass := PackedInt32Array()
	for t in range(0, idx.size() - 2, 3):
		var cy := (verts[idx[t]].y + verts[idx[t + 1]].y + verts[idx[t + 2]].y) / 3.0
		var lo := minf(verts[idx[t]].y, minf(verts[idx[t + 1]].y, verts[idx[t + 2]].y))
		if cy > from_y and lo > from_y * 0.8:
			glass.append_array([idx[t], idx[t + 1], idx[t + 2]])
		else:
			rest.append_array([idx[t], idx[t + 1], idx[t + 2]])
	return [rest, glass]


## Split the windows off the "Details" surface of `mi`'s mesh into a new "Glass" surface (cached per source mesh, the mesh is replaced in place). Returns true when a Glass surface exists afterwards.
static func split_glass(mi: MeshInstance3D, body_h: float) -> bool:
	if mi == null or mi.mesh == null:
		return false
	var src := mi.mesh
	var key: Variant = src.resource_path if src.resource_path != "" else src.get_instance_id()
	if _split_cache.has(key):
		var cached: ArrayMesh = _split_cache[key]
		if cached != null:
			mi.mesh = cached
		return cached != null
	var details := -1
	for s in src.get_surface_count():
		var m := src.surface_get_material(s)
		if m != null and m.resource_name == "Glass":
			_split_cache[key] = null
			return true
		if m != null and m.resource_name == "Details":
			details = s
	if details < 0:
		_split_cache[key] = null
		return false
	var arrays := src.surface_get_arrays(details)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
	var parts := split_indices(verts, idx, body_h * GLASS_FROM)
	if (parts[1] as PackedInt32Array).size() < 6:
		_split_cache[key] = null
		return false
	var im := ImporterMesh.new()
	for s in src.get_surface_count():
		var sa := src.surface_get_arrays(s)
		var mat := src.surface_get_material(s)
		var nm := String(mat.resource_name) if mat != null else ""
		if s == details:
			var ra := sa.duplicate()
			ra[Mesh.ARRAY_INDEX] = parts[0]
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, ra, [], {}, mat, nm)
			var ga := sa.duplicate()
			ga[Mesh.ARRAY_INDEX] = parts[1]
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, ga, [], {}, glass_material(), "Glass")
		else:
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, sa, [], {}, mat, nm)
	var out := im.get_mesh()
	_split_cache[key] = out
	mi.mesh = out
	return true


# --- plates ---------------------------------------------------------------------------------------------------------------------------------------------

const _GLYPHS := {
	"0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111", "4": "101101111001001", "5": "111100111001111", "6": "111100111101111",
	"7": "111001010010010", "8": "111101111101111", "9": "111101111001111", "Q": "111101101111001", "T": "111010010010010", "V": "101101101101010", "A": "010101111101101",
	"E": "111100110100111", "L": "100100100100111", "X": "101101010101101", "K": "101101110101101", "R": "110101110101101", "N": "101111111111101",
}


## One of PLATE_VARIANTS generated plate textures: a white plate with a blue edge strip and a seven character number in a 3 x 5 pixel font.
static func plate_texture(variant: int) -> ImageTexture:
	if _plate_tex.is_empty():
		for v in PLATE_VARIANTS:
			_plate_tex.append(_make_plate(v))
	return _plate_tex[posmod(variant, PLATE_VARIANTS)]


static func _make_plate(variant: int) -> ImageTexture:
	var img := Image.create(160, 36, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.9, 0.84))
	img.fill_rect(Rect2i(0, 0, 160, 3), Color(0.1, 0.1, 0.12))
	img.fill_rect(Rect2i(0, 33, 160, 3), Color(0.1, 0.1, 0.12))
	img.fill_rect(Rect2i(0, 0, 18, 36), Color(0.1, 0.3, 0.78))
	img.fill_rect(Rect2i(5, 8, 8, 2), Color(0.95, 0.95, 1.0))
	img.fill_rect(Rect2i(5, 24, 8, 2), Color(0.95, 0.95, 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + variant * 31
	var text := "QT"
	var pool := "0123456789"
	for i in 5:
		text += pool[rng.randi() % pool.length()]
	var x := 24
	for ch in text:
		var g: String = _GLYPHS.get(ch, _GLYPHS["0"])
		for py in 5:
			for px in 3:
				if g[py * 3 + px] == "1":
					img.fill_rect(Rect2i(x + px * 6, 6 + py * 4, 6, 4), Color(0.06, 0.06, 0.08))
		x += 22
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func plate_material(variant: int) -> StandardMaterial3D:
	if _plate_mats.is_empty():
		for v in PLATE_VARIANTS:
			var m := StandardMaterial3D.new()
			m.resource_name = "Plate"
			m.albedo_texture = plate_texture(v)
			m.roughness = 0.45
			m.metallic = 0.1
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			_plate_mats.append(m)
	return _plate_mats[posmod(variant, PLATE_VARIANTS)]


## Two plate quads on a car whose body spans `box` (model space, nose at -Z): returns the new nodes (front, rear).
static func add_plates(model: Node3D, box: AABB, variant: int, y: float) -> Array[MeshInstance3D]:
	if _plate_mesh == null:
		_plate_mesh = QuadMesh.new()
		_plate_mesh.size = Vector2(PLATE_W, PLATE_H)
	var out: Array[MeshInstance3D] = []
	for front in [true, false]:
		var mi := MeshInstance3D.new()
		mi.name = "PlateF" if front else "PlateR"
		mi.mesh = _plate_mesh
		mi.material_override = plate_material(variant + (0 if front else 3))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var z := box.position.z - 0.015 if front else box.end.z + 0.015
		mi.position = Vector3(box.position.x + box.size.x * 0.5, y, z)
		mi.rotation = Vector3(0.0, PI if front else 0.0, 0.0)               # a quad faces +Z: the front plate turns round
		mi.visibility_range_end = 38.0
		mi.visibility_range_end_margin = 4.0
		model.add_child(mi)
		out.append(mi)
	return out


# --- headlight beams --------------------------------------------------------------------------------------------------------------------------------------

## Two soft cones from the headlights over the road ahead (nose at -Z). Vertex alpha = brightness (strong at the lamp, nothing at the far end).
static func beam_mesh(half_width: float, lamp_y: float) -> ArrayMesh:
	var key := "%d_%d" % [roundi(half_width * 100.0), roundi(lamp_y * 100.0)]
	if _beam_cache.has(key):
		return _beam_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 10
	for lamp_x: float in [-half_width, half_width]:
		var apex := Vector3(lamp_x, lamp_y, -0.2)
		var ends: Array[Vector3] = []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			ends.append(Vector3(lamp_x * 0.6 + cos(a) * 2.6, maxf(0.05, 0.05 + (sin(a) * 0.5 + 0.5) * 2.4), -BEAM_LEN))
		for i in sides:
			var e0 := ends[i]
			var e1 := ends[(i + 1) % sides]
			var nrm := ((e0 - apex).cross(e1 - apex)).normalized()
			st.set_color(Color(1, 1, 1, 1.0))
			st.set_normal(nrm)
			st.add_vertex(apex)
			st.set_color(Color(1, 1, 1, 0.0))
			st.set_normal(nrm)
			st.add_vertex(e0)
			st.set_color(Color(1, 1, 1, 0.0))
			st.set_normal(nrm)
			st.add_vertex(e1)
	var bm := st.commit()
	_beam_cache[key] = bm
	return bm


static func beam_material() -> ShaderMaterial:
	if _beam_mat == null:
		_beam_shader = Shader.new()
		_beam_shader.code = BEAM_SHADER_CODE
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = _beam_shader
	return _beam_mat
