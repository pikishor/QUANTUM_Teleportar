extends RefCounted
## The camera-centred window over the street kit (city_kit.gd): ONE ArrayMesh in ONE MeshInstance3D that holds the props of the cells around the camera, in world space.
##
## Cells are 40 m squares. A cell whose nearest point is within `near_radius` of the camera contributes the full-detail geometry of every prop in it; a cell between `near_radius`
## and `far_radius` contributes the simplified geometry of the kinds that have a far level (and only while the cell is within that kind's own far radius); nothing beyond. The window
## is re-filled when the camera has moved `STEP` metres (and only if the set of cells, hence the contents, really changes). A re-fill concatenates cached local geometry with one
## native transform per prop (`Transform3D * PackedVector3Array`), so it costs about a millisecond and allocates no nodes. The per-prop seed rides along as CUSTOM0.x.
## Without a camera (headless tests) nothing is drawn until `update()` or `show_all()` is called.

const Kit := preload("res://scripts/world/city_kit.gd")

const STEP := 10.0
const NEAR_BASE := 64.0                  ## metres, scaled by the quality
const FAR_BASE := 175.0
const KC_NEAR := 38.0                    ## city-kit pieces (city_kit_world.gd) draw within this many metres (scaled by the quality)
const DRESS_NEAR := 44.0                 ## the district dressing (city_kit_dress.gd) reads a little further: its rooftop structures also draw to their own far radius
const DRESS_MIN_SCALE := 0.8             ## the LOW tier (scale 0.65) skips the district dressing: its draw budget has no room for the extra draws the dressing was measured to cost there
const LM_NEAR := 230.0                   ## landmarks switch to their coarse silhouette beyond this distance (metres, not scaled by the quality)

var kit: Kit
var landmarks: Array = []                ## city_landmarks.gd items: {pos, near, far, seed}: merged into the same mesh (full detail within LM_NEAR metres, coarse beyond)
var landmark_tris := 0
var mesh := ArrayMesh.new()
var node: MeshInstance3D
var scale := 1.0:
	set(v):
		scale = v
		built_at = Vector2(1.0e9, 1.0e9)
		sig = -1
var built_at := Vector2(1.0e9, 1.0e9)
var sig := -1
var near_props := 0                      ## props at full detail in the current window
var kc_props := 0                        ## city-kit pieces in the current window (facade, rooftop, street dressing, markings)
var far_props := 0                       ## props at the simplified level
var triangles := 0
var rebuilds := 0

var _sel_near := PackedInt32Array()
var _sel_far := PackedInt32Array()


func near_radius() -> float:
	return NEAR_BASE * scale


func far_radius() -> float:
	return FAR_BASE * scale


func setup(parent: Node3D, kit_ref: Kit, material: Material) -> MeshInstance3D:
	kit = kit_ref
	node = MeshInstance3D.new()
	node.name = "StreetKit"
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	parent.add_child(node)
	return node


## Re-centre on a camera at (x, z): rebuilds when it has moved STEP metres (or `force`).
func update(cam: Vector2, force := false) -> void:
	if kit == null:
		return
	if force or cam.distance_to(built_at) > STEP:
		rebuild(cam)


func _min_dist(c: int, cam: Vector2) -> float:
	var cx := c % Kit.GRID_N
	var cz := c / Kit.GRID_N
	var x0 := Kit.GRID_ORIGIN + float(cx) * Kit.CELL
	var z0 := Kit.GRID_ORIGIN + float(cz) * Kit.CELL
	var dx := maxf(maxf(x0 - cam.x, cam.x - (x0 + Kit.CELL)), 0.0)
	var dz := maxf(maxf(z0 - cam.y, cam.y - (z0 + Kit.CELL)), 0.0)
	return sqrt(dx * dx + dz * dz)


func rebuild(cam: Vector2) -> void:
	built_at = cam
	var rn := near_radius()
	var rf := far_radius()
	_sel_near.clear()
	_sel_far.clear()
	var s := 5
	var c0x := maxi(0, int(floor((cam.x - rf - Kit.GRID_ORIGIN) / Kit.CELL)))
	var c1x := mini(Kit.GRID_N - 1, int(floor((cam.x + rf - Kit.GRID_ORIGIN) / Kit.CELL)))
	var c0z := maxi(0, int(floor((cam.y - rf - Kit.GRID_ORIGIN) / Kit.CELL)))
	var c1z := mini(Kit.GRID_N - 1, int(floor((cam.y + rf - Kit.GRID_ORIGIN) / Kit.CELL)))
	for cz in range(c0z, c1z + 1):
		for cx in range(c0x, c1x + 1):
			var c := cz * Kit.GRID_N + cx
			if kit.counts[c] == 0:
				continue
			var d := _min_dist(c, cam)
			if d <= rn:
				_sel_near.append(c)
				s = s * 1000003 + c * 2 + 1
			elif d <= rf:
				_sel_far.append(c)
				s = s * 1000003 + c * 2
	for it in landmarks:
		var lp: Vector3 = it["pos"]
		s = s * 1000003 + (7 if Vector2(lp.x, lp.z).distance_to(cam) <= LM_NEAR else 3)
	if s == sig:
		return
	sig = s
	_fill(cam, false)


## Every prop of the city at full detail (tests, stills of far districts).
func show_all() -> void:
	if kit == null:
		return
	built_at = Vector2(1.0e9, 1.0e9)
	sig = -1
	_sel_near.clear()
	_sel_far.clear()
	for c in Kit.GRID_N * Kit.GRID_N:
		if kit.counts[c] > 0:
			_sel_near.append(c)
	_fill(Vector2.ZERO, true)


func _fill(cam: Vector2, everything: bool) -> void:
	rebuilds += 1
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var sd := PackedFloat32Array()
	near_props = 0
	far_props = 0
	kc_props = 0
	for level in 2:
		var list := _sel_near if level == 0 else _sel_far
		for c in list:
			var dmin := 0.0 if everything else _min_dist(c, cam)
			var arr: PackedFloat32Array = kit.cells[c]
			for o in range(0, arr.size(), 6):
				var kind := int(arr[o])
				if level == 1 and Kit.far_radius(kind) < dmin:
					continue
				var x := arr[o + 1]
				var z := arr[o + 2]
				var d := _district(x, z)
				if kind >= Kit.DRESS_FIRST and scale < DRESS_MIN_SCALE:
					continue
				if level == 0 and kind >= Kit.KC_FIRST and dmin > (DRESS_NEAR if kind >= Kit.DRESS_FIRST else KC_NEAR) * scale and Kit.far_radius(kind) <= 0.0:
					continue                                              # facade bands, markings and street dressing only close to the camera
				var vr := int(arr[o + 5])
				var g := kit.geo(kind, level == 0, d, vr & 3)
				if g.is_empty():
					continue
				var xf := Transform3D(Basis(Vector3.UP, arr[o + 3]), Vector3(x, float(vr >> 2) * 0.25, z))
				v.append_array(xf * (g["v"] as PackedVector3Array))
				nr.append_array(Transform3D(xf.basis, Vector3.ZERO) * (g["n"] as PackedVector3Array))
				uv.append_array(g["uv"])
				uv2.append_array(g["uv2"])
				col.append_array(g["c"])
				var seeds := PackedFloat32Array()
				seeds.resize(int(g["count"]))
				seeds.fill(arr[o + 4])
				sd.append_array(seeds)
				if level == 0 and kind >= Kit.KC_FIRST:
					kc_props += 1
				elif level == 0:
					near_props += 1
				else:
					far_props += 1
	landmark_tris = 0
	for it in landmarks:
		var lp2: Vector3 = it["pos"]
		var lg: Dictionary = it["near"] if everything or Vector2(lp2.x, lp2.z).distance_to(cam) <= LM_NEAR else it["far"]
		var xf2 := Transform3D(Basis.IDENTITY, lp2)
		v.append_array(xf2 * (lg["v"] as PackedVector3Array))
		nr.append_array(lg["n"])
		uv.append_array(lg["uv"])
		uv2.append_array(lg["uv2"])
		col.append_array(lg["c"])
		var ls := PackedFloat32Array()
		ls.resize(int(lg["count"]))
		ls.fill(float(it["seed"]))
		sd.append_array(ls)
		landmark_tris += int(lg["count"]) / 3
	mesh.clear_surfaces()
	triangles = v.size() / 3
	if v.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nr
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_CUSTOM0] = sd
	var flags := Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)


static func _district(x: float, z: float) -> int:
	return (1 if x >= 0.0 else 0) + (2 if z >= 0.0 else 0)
