class_name BoatWake
extends MeshInstance3D
## The foam trail of a boat (wave 105): a soft white ribbon on the water behind the hull, wide and bright at the stern, spreading and fading over LIFE seconds, drawn in ONE draw call (one
## ArrayMesh rebuilt each frame from at most MAX_POINTS points, about 50 triangles). It lives in world space (top_level), is added by VehicleCraft._wake for a boat that is near the player and
## is hidden again when the boat stops or is far. No textures: vertex colour alpha across the ribbon makes the soft edge.
## `update(dt, stern, y, speed01, heading)`: add a point when the hull moved, age the rest, rebuild.

const LIFE := 3.2
const MAX_POINTS := 28
const SPACING := 1.6                      ## metres between points

static var _mat: StandardMaterial3D

var pts: Array[Vector3] = []
var ages: Array[float] = []
var widths: Array[float] = []
var strength := 0.0


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.vertex_color_use_as_albedo = true
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.no_depth_test = false
		_mat.render_priority = 3
	return _mat


func _init() -> void:
	name = "Wake"
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	material_override = material()
	extra_cull_margin = 40.0
	mesh = ArrayMesh.new()


func clear() -> void:
	pts.clear()
	ages.clear()
	widths.clear()
	(mesh as ArrayMesh).clear_surfaces()
	visible = false


## `stern` = the point behind the hull on the water surface (world), `half_w` the hull's half width, `speed01` 0..1 of its top speed.
func update(dt: float, stern: Vector3, half_w: float, speed01: float) -> void:
	strength = lerpf(strength, speed01, 1.0 - exp(-4.0 * dt))
	for i in ages.size():
		ages[i] += dt
	while not ages.is_empty() and ages[0] > LIFE:
		pts.remove_at(0)
		ages.remove_at(0)
		widths.remove_at(0)
	if speed01 > 0.12 and (pts.is_empty() or pts[pts.size() - 1].distance_to(stern) >= SPACING):
		if pts.size() >= MAX_POINTS:
			pts.remove_at(0)
			ages.remove_at(0)
			widths.remove_at(0)
		pts.append(stern)
		ages.append(0.0)
		widths.append(half_w * (1.0 + 1.6 * speed01))
	_rebuild()


func _rebuild() -> void:
	var m := mesh as ArrayMesh
	m.clear_surfaces()
	var n := pts.size()
	if n < 2:
		visible = false
		return
	visible = true
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var t := Vector3(b.x - a.x, 0.0, b.z - a.z)
		t = t.normalized() if t.length_squared() > 1.0e-6 else Vector3.FORWARD
		var side := Vector3(-t.z, 0.0, t.x)
		var age := ages[i] / LIFE
		var w := widths[i] * (1.0 + age * 2.6)                       # the foam spreads as it ages
		var alpha := clampf((1.0 - age) * (1.0 - age) * 0.85 * (0.35 + 0.65 * strength), 0.0, 0.9)
		var p := pts[i]
		verts.append(p - side * w)
		verts.append(p)
		verts.append(p + side * w)
		cols.append(Color(1.0, 1.0, 1.0, 0.0))
		cols.append(Color(0.96, 0.99, 1.0, alpha))
		cols.append(Color(1.0, 1.0, 1.0, 0.0))
		if i < n - 1:
			var k := i * 3
			idx.append_array(PackedInt32Array([k, k + 3, k + 1, k + 1, k + 3, k + 4, k + 1, k + 4, k + 2, k + 2, k + 4, k + 5]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = norms
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
