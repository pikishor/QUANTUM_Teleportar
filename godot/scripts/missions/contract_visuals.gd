class_name ContractVisuals
extends Node3D
## Everything a contract draws in the world, built once and only shown / hidden / moved afterwards (no lights, no per-frame allocation):
##   two markers (a beam of light plus a ground ring with a progress arc: `a` is the main objective, `b` the second point of a courier run) and one route line (dashes
##   along the streets, rebuilt only when a contract starts). A marker is 2 draw calls, the route 1; hidden ones cost nothing.
## Beam colours come from MissionVisuals.make_beam (shared cached materials); the ring is a flat quad with a polar shader: a thin band, filled up to `progress`.

const RING_SHADER_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.72, 0.25, 1.0);
uniform float progress = -1.0;   // 0..1 filled arc (clockwise from the top), negative = plain ring
uniform float inner = 0.90;
uniform float fill_a = 0.035;   // brightness of the disc inside the band (the hack ring is a lit pad you stand on)
uniform float ripple = 0.0;      // 0..1 inward data ripple inside the pad
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float band = smoothstep(inner - 0.02, inner, r) * (1.0 - smoothstep(0.985, 1.0, r));
	float a = atan(p.x, -p.y);
	float f = (a < 0.0 ? a + 6.2831853 : a) / 6.2831853;
	float fill = progress < 0.0 ? 1.0 : (f <= progress ? 1.0 : 0.2);
	float disc = (1.0 - smoothstep(0.0, inner, r)) * fill_a * (1.0 - ripple + ripple * (0.55 + 0.45 * sin(r * 26.0 + TIME * 3.5)));
	ALBEDO = tint.rgb * 1.5;
	ALPHA = clamp(band * fill * (0.75 + 0.25 * sin(TIME * 3.0)) + disc, 0.0, 1.0);
}
"""

## Strike-zone hazard ring (set pieces): a pulsing band while warning, a filled flash while hitting; one flat quad per zone, pooled, hidden when idle.
const ZONE_SHADER_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.2, 0.25, 1.0);
uniform float hit = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float band = smoothstep(0.86, 0.9, r) * (1.0 - smoothstep(0.985, 1.0, r));
	float pulse = 0.55 + 0.45 * sin(TIME * 14.0);
	float disc = (1.0 - smoothstep(0.0, 0.9, r)) * mix(0.10 + 0.08 * pulse, 0.85, hit);
	ALBEDO = mix(tint.rgb, vec3(1.0, 0.9, 0.7), hit) * 1.5;
	ALPHA = clamp(band * mix(pulse, 1.0, hit) + disc * step(r, 0.9), 0.0, 1.0);
}
"""
const ZONE_POOL := 4
static var _zone_shader: Shader

const BEAM_HEIGHT := 150.0
const BEAM_NEAR := 22.0
const ROUTE_Y := 0.14
const DASH := 3.4
const GAP := 2.2
const ROUTE_WIDTH := 1.4
const ROUTE_FADE_NEAR := 3.0           ## metres from the camera: the route line is invisible closer than this and solid beyond ROUTE_FADE_FAR
const ROUTE_FADE_FAR := 9.0

static var _ring_shader: Shader
static var _route_mat: StandardMaterial3D

var markers: Array[Dictionary] = []       ## [{node, beam, ring, mat, beams: {StringName: Material}}] for a and b
var route: MeshInstance3D
var _t := 0.0
var zone_rings: Array[MeshInstance3D] = []


func _init() -> void:
	name = "ContractVisuals"
	for i in 2:
		markers.append(_build_marker(i))
	route = MeshInstance3D.new()
	route.name = "Route"
	route.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	route.extra_cull_margin = 4096.0
	route.visible = false
	add_child(route)


static func ring_shader() -> Shader:
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = RING_SHADER_CODE
	return _ring_shader


func _build_marker(i: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Marker%s" % ["A", "B"][i]
	root.visible = false
	var beams := {}
	for key: StringName in [&"amber", &"cyan", &"red"]:
		var col := ContractTypes.AMBER
		if key == &"cyan":
			col = ContractTypes.CYAN
		elif key == &"red":
			col = ContractTypes.RED
		beams[key] = MissionVisuals.make_beam(col, 0.8, BEAM_HEIGHT, 1.3, 0.25).material_override
	var beam := MissionVisuals.make_beam(ContractTypes.AMBER, 0.8, BEAM_HEIGHT, 1.3, 0.25)
	beam.name = "Beam"
	beam.position.y = BEAM_HEIGHT * 0.5
	root.add_child(beam)
	var mat := ShaderMaterial.new()
	mat.shader = ring_shader()
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var quad := PlaneMesh.new()
	quad.size = Vector2(2.0, 2.0)
	ring.mesh = quad
	ring.material_override = mat
	ring.position.y = 0.1
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	add_child(root)
	return {node = root, beam = beam, ring = ring, mat = mat, beams = beams, beam_on = true}


## Show marker `i` (0 = a, 1 = b) at `pos`: `radius` is the ring's size in metres, `kind` colours it, `progress` < 0 draws a plain ring.
func show_marker(i: int, pos: Vector3, radius: float, color: Color, progress := -1.0, beam := true) -> void:
	var m: Dictionary = markers[i]
	set_pad_style(i, false)
	var node: Node3D = m.node
	node.position = Vector3(pos.x, maxf(pos.y, 0.0), pos.z)
	node.visible = true
	m.beam_on = beam
	(m.beam as MeshInstance3D).visible = beam
	var key := &"amber"
	if color.is_equal_approx(ContractTypes.CYAN):
		key = &"cyan"
	elif color.is_equal_approx(ContractTypes.RED):
		key = &"red"
	(m.beam as MeshInstance3D).material_override = m.beams[key]
	(m.ring as MeshInstance3D).scale = Vector3(radius, 1.0, radius)
	var mat: ShaderMaterial = m.mat
	mat.set_shader_parameter(&"tint", color)
	mat.set_shader_parameter(&"progress", progress)


## Shows the strike zones (centres, radius in metres); `hitting` flashes them. Extra zones beyond the pool are not drawn. An empty array hides all.
func show_zones(centres: Array[Vector3], radius: float, hitting := false) -> void:
	if centres.is_empty() and zone_rings.is_empty():
		return
	while zone_rings.size() < ZONE_POOL and not centres.is_empty():
		if _zone_shader == null:
			_zone_shader = Shader.new()
			_zone_shader.code = ZONE_SHADER_CODE
		var m := MeshInstance3D.new()
		var q := PlaneMesh.new()
		q.size = Vector2(2.0, 2.0)
		m.mesh = q
		var sm := ShaderMaterial.new()
		sm.shader = _zone_shader
		m.material_override = sm
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		zone_rings.append(m)
	for i in zone_rings.size():
		var m := zone_rings[i]
		m.visible = i < centres.size()
		if m.visible:
			m.global_position = Vector3(centres[i].x, 0.12, centres[i].z)
			m.scale = Vector3(radius, 1.0, radius)
			(m.material_override as ShaderMaterial).set_shader_parameter(&"hit", 1.0 if hitting else 0.0)


func zones_visible() -> int:
	var n := 0
	for m in zone_rings:
		if m.visible:
			n += 1
	return n


func move_marker(i: int, pos: Vector3) -> void:
	var node: Node3D = markers[i].node
	node.position = Vector3(pos.x, maxf(pos.y, 0.0), pos.z)


func set_progress(i: int, progress: float) -> void:
	(markers[i].mat as ShaderMaterial).set_shader_parameter(&"progress", progress)


## A lit pad instead of a thin ring (the hack site: the player must see where to stand): a wide band, a bright disc with a ripple that runs inwards.
func set_pad_style(i: int, on := true) -> void:
	var mat := markers[i].mat as ShaderMaterial
	mat.set_shader_parameter(&"inner", 0.78 if on else 0.90)
	mat.set_shader_parameter(&"fill_a", 0.28 if on else 0.035)
	mat.set_shader_parameter(&"ripple", 1.0 if on else 0.0)


func hide_marker(i: int) -> void:
	(markers[i].node as Node3D).visible = false


func marker_visible(i: int) -> bool:
	return (markers[i].node as Node3D).visible


func hide_all() -> void:
	for zr in zone_rings:
		zr.visible = false
	for i in markers.size():
		hide_marker(i)
	route.visible = false


## Draws the route polyline as dashes on the street (one ArrayMesh, one draw call). Pass at least two points; fewer hides the line.
func set_route(points: PackedVector3Array) -> void:
	if points.size() < 2:
		route.visible = false
		return
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for s in points.size() - 1:
		var a := points[s]
		var b := points[s + 1]
		var seg := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var seg_len := seg.length()
		if seg_len < 0.5:
			continue
		var dir := seg / seg_len
		var side := Vector3(-dir.z, 0.0, dir.x) * (ROUTE_WIDTH * 0.5)
		var d := 0.0
		while d < seg_len:
			var e := minf(d + DASH, seg_len)
			var p0 := a + dir * d
			var p1 := a + dir * e
			var base := verts.size()
			verts.append(Vector3(p0.x - side.x, ROUTE_Y, p0.z - side.z))
			verts.append(Vector3(p0.x + side.x, ROUTE_Y, p0.z + side.z))
			verts.append(Vector3(p1.x + side.x, ROUTE_Y, p1.z + side.z))
			verts.append(Vector3(p1.x - side.x, ROUTE_Y, p1.z - side.z))
			idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
			d += DASH + GAP
	if verts.is_empty():
		route.visible = false
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _route_mat == null:
		_route_mat = StandardMaterial3D.new()
		_route_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_route_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_route_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_route_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_route_mat.albedo_color = Color(ContractTypes.AMBER.r, ContractTypes.AMBER.g, ContractTypes.AMBER.b, 0.6)
		# a dash right under the lens is a metre-wide cream plane across half the frame (director review: white planes at the lens): invisible within ROUTE_FADE_NEAR, solid from ROUTE_FADE_FAR
		_route_mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		_route_mat.distance_fade_min_distance = ROUTE_FADE_NEAR
		_route_mat.distance_fade_max_distance = ROUTE_FADE_FAR
		_route_mat.disable_receive_shadows = true
	mesh.surface_set_material(0, _route_mat)
	route.mesh = mesh
	route.visible = true


## Called by Contracts from _process while a marker is visible: the beam turns slowly and is hidden within BEAM_NEAR metres of the camera, where an additive
## column right next to the lens would only wash the street out (the ring stays).
func animate(delta: float) -> void:
	_t += delta
	var cam := Game.camera if is_instance_valid(Game.camera) else null
	for m: Dictionary in markers:
		var node: Node3D = m.node
		if node.visible:
			var beam := m.beam as Node3D
			beam.rotation.y += delta * 0.8
			if m.beam_on and cam != null:
				var cp := cam.global_position
				beam.visible = Vector2(node.global_position.x - cp.x, node.global_position.z - cp.z).length() > BEAM_NEAR
