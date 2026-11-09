class_name CaveSystem
extends Node3D
## The HIDDEN CAVE's inside (wave 105): a small system of four chambers joined by tunnels, built from a footprint (discs and capsules on a grid) as a floor and a ceiling sheet that pinch
## together at the edges (no wall quads, no blocky corners: a rounded, rocky tube), with stalactites, glowing crystals and a stash. It hangs 300 m under the terrain at the mouth's x / z
## (nothing of the world is there); the mouth teleports the hero in (`enter`), the exit ring at the first chamber brings him out (`leave`). One draw call, one trimesh collider, no lights:
## the shader (assets/shaders/cave.gdshader) is unshaded with the hero's headlamp and the crystal glows computed per pixel, so the sun can never reach in.
## Registers itself as the interior space while the hero is inside (the city rescue and the blink clamp then leave him alone).
##   CaveSystem.attach(parent, site)   builds nothing until `enter`
##   enter(player) / leave(player)     inside() true between them
##   stash_taken / take_stash(player)  the stash chest in the last chamber (once per cave)
##   stats()                           {tris, chambers, shapes}

const ORIGIN := Vector3(350.0, 12.0, -2430.0)          ## where the cave hangs: under the north massif (170 m of rock above, no water near; the void is at y -60)
const STEP := 1.6
const SHADER := preload("res://assets/shaders/cave.gdshader")
## chambers: x, z, radius (local frame: +Z runs into the mountain, the entrance chamber is at the origin)
const CHAMBERS: Array[Vector3] = [Vector3(0.0, 0.0, 9.0), Vector3(-4.0, 34.0, 12.0), Vector3(16.0, 62.0, 9.0), Vector3(38.0, 80.0, 8.0)]
const TUNNELS: Array[Vector3] = [Vector3(0.0, 0.0, 3.0), Vector3(-4.0, 34.0, 3.4), Vector3(16.0, 62.0, 3.0)]   ## unused tag: tunnels join consecutive chambers (radius below)
const TUNNEL_R := 3.2

var site: Dictionary = {}
var type: StringName = &"cave"
var built := false
var stash_taken := false
var _inside := false
var _origin := Vector3.ZERO
var _mi: MeshInstance3D
var _body: StaticBody3D
var _mat: ShaderMaterial
var _tris := 0
var _glows: Array[Vector4] = []
var _glow_cols: Array[Vector3] = []
var _back_to := Vector3.ZERO
var _stash_pos := Vector3.ZERO
var _exit_pos := Vector3.ZERO
var _sd_cache := {}
var _noise: FastNoiseLite


static func attach(parent: Node, p_site: Dictionary) -> CaveSystem:
	var c := CaveSystem.new()
	c.name = "CaveSystem"
	c.site = p_site
	parent.add_child(c)
	return c


func _ready() -> void:
	_origin = ORIGIN
	_back_to = OutskirtsSites.to_world(site, Vector3(0.0, 0.0, -6.0))


func inside() -> bool:
	return _inside


func origin() -> Vector3:
	return _origin


## Where the hero stands when he comes in, and where the exit ring is (world).
func entry_point() -> Vector3:
	return _origin + Vector3(0.0, 0.3, 3.5)


func exit_ring() -> Vector3:
	return _origin + Vector3(0.0, 0.0, 1.0)


func stash_point() -> Vector3:
	return _origin + _stash_pos


# --- the footprint -----------------------------------------------------------------------------------------------------------------------------

## Signed depth into the cave (positive inside) at a local (x, z): how far the point is inside the union of the chambers and tunnels.
func _depth(x: float, z: float) -> float:
	var best := -1.0e9
	for i in CHAMBERS.size():
		var c := CHAMBERS[i]
		var r := c.z
		var wob := 1.0 + 0.16 * sin(atan2(z - c.y, x - c.x) * 3.0 + float(i) * 1.7) + 0.08 * sin(atan2(z - c.y, x - c.x) * 7.0 + float(i))
		best = maxf(best, r * wob - Vector2(x - c.x, z - c.y).length())
	for i in CHAMBERS.size() - 1:
		var a := Vector2(CHAMBERS[i].x, CHAMBERS[i].y)
		var b := Vector2(CHAMBERS[i + 1].x, CHAMBERS[i + 1].y)
		var mid := (a + b) * 0.5 + Vector2(sin(float(i) * 2.1) * 7.0, 0.0)           # a bend in every tunnel
		best = maxf(best, TUNNEL_R * (1.0 + 0.2 * sin(z * 0.4 + float(i))) - _seg_dist(Vector2(x, z), a, mid))
		best = maxf(best, TUNNEL_R * (1.0 + 0.2 * sin(z * 0.4 + float(i))) - _seg_dist(Vector2(x, z), mid, b))
	return best


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _floor_y(x: float, z: float) -> float:
	return _noise.get_noise_2d(x * 2.0, z * 2.0) * 0.32 + 0.35 * sin(x * 0.11 + z * 0.07)


func _ceil_h(depth: float, x: float, z: float) -> float:
	var open := pow(clampf(depth / 2.1, 0.0, 1.0), 0.55)
	var tall := 2.9 + 3.6 * clampf(depth / 9.0, 0.0, 1.0) + _noise.get_noise_2d(x * 3.1 + 40.0, z * 3.1) * 0.7
	return open * tall


# --- build -------------------------------------------------------------------------------------------------------------------------------------

func build() -> void:
	if built:
		return
	built = true
	_noise = FastNoiseLite.new()
	_noise.seed = 4813
	_noise.frequency = 0.09
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	var x0 := -22.0
	var x1 := 56.0
	var z0 := -8.0
	var z1 := 100.0
	var nx := int((x1 - x0) / STEP) + 1
	var nz := int((z1 - z0) / STEP) + 1
	var depth := PackedFloat32Array()
	depth.resize(nx * nz)
	for j in nz:
		for i in nx:
			depth[j * nx + i] = _depth(x0 + float(i) * STEP, z0 + float(j) * STEP)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var fl := {}                                                           # grid vertex -> floor vertex index
	var ce := {}                                                           # grid vertex -> ceiling vertex index
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for j in nz - 1:
		for i in nx - 1:
			var dmax := maxf(maxf(depth[j * nx + i], depth[j * nx + i + 1]), maxf(depth[(j + 1) * nx + i], depth[(j + 1) * nx + i + 1]))
			if dmax <= 0.0:
				continue
			var ids_f: Array[int] = []
			var ids_c: Array[int] = []
			for k in 4:
				var ci := i + (k & 1)
				var cj := j + (k >> 1)
				var key := cj * nx + ci
				if not fl.has(key):
					var x := x0 + float(ci) * STEP
					var z := z0 + float(cj) * STEP
					var d := maxf(depth[key], 0.0)
					var fy := _floor_y(x, z)
					var cy := fy + _ceil_h(d, x, z)
					var shade := 0.5 + 0.5 * _noise.get_noise_2d(x * 1.7, z * 1.7)
					fl[key] = verts.size()
					verts.append(Vector3(x, fy, z))
					cols.append(Color(0.16 + 0.09 * shade, 0.16 + 0.09 * shade, 0.19 + 0.09 * shade, 0.0))
					ce[key] = verts.size()
					verts.append(Vector3(x, cy, z))
					cols.append(Color(0.13 + 0.08 * shade, 0.13 + 0.08 * shade, 0.16 + 0.08 * shade, 0.0))
				ids_f.append(fl[key])
				ids_c.append(ce[key])
			# floor (counter-clockwise seen from above) and ceiling (seen from below)
			idx.append_array([ids_f[0], ids_f[2], ids_f[1], ids_f[1], ids_f[2], ids_f[3]])
			idx.append_array([ids_c[0], ids_c[1], ids_c[2], ids_c[1], ids_c[3], ids_c[2]])
	# stalactites (down from the ceiling) and stalagmites; crystals (glow): added as small cones
	var cones: Array = []
	var glow_spots: Array[Vector3] = []
	for k in 90:
		var cx := rng.randf_range(x0, x1)
		var cz := rng.randf_range(z0, z1)
		var d := _depth(cx, cz)
		if d < 1.6:
			continue
		var fy := _floor_y(cx, cz)
		var cy := fy + _ceil_h(d, cx, cz)
		if k % 3 == 0:
			cones.append([Vector3(cx, cy, cz), Vector3(cx, cy - rng.randf_range(0.8, 2.6), cz), rng.randf_range(0.18, 0.5), Color(0.2, 0.18, 0.17, 0.0)])
		elif k % 3 == 1:
			cones.append([Vector3(cx, fy, cz), Vector3(cx, fy + rng.randf_range(0.5, 1.6), cz), rng.randf_range(0.15, 0.4), Color(0.22, 0.19, 0.18, 0.0)])
		elif glow_spots.size() < 14:
			var h := rng.randf_range(0.7, 2.2)
			var tint := Color(0.25, 0.9, 1.0, 1.0) if (k / 3) % 3 != 0 else Color(0.9, 0.35, 0.95, 1.0)
			cones.append([Vector3(cx, fy, cz), Vector3(cx + rng.randf_range(-0.3, 0.3), fy + h, cz + rng.randf_range(-0.3, 0.3)), 0.22, tint])
			glow_spots.append(Vector3(cx, fy + h * 0.6, cz))
	# the big crystal cluster in the last chamber and the stash chest
	var last := CHAMBERS[CHAMBERS.size() - 1]
	for k in 7:
		var a := TAU * float(k) / 7.0 + 0.3
		var base := Vector3(last.x + cos(a) * 3.8, _floor_y(last.x, last.y), last.y + sin(a) * 3.8)
		cones.append([base, base + Vector3(cos(a) * 0.5, rng.randf_range(2.0, 3.6), sin(a) * 0.5), 0.5, Color(0.25, 0.9, 1.0, 1.0) if k % 2 == 0 else Color(0.9, 0.35, 0.95, 1.0)])
	_stash_pos = Vector3(last.x, _floor_y(last.x, last.y), last.y)
	_exit_pos = Vector3(0.0, _floor_y(0.0, 1.0), 1.0)
	cones.append([_stash_pos, _stash_pos + Vector3(0.0, 0.01, 0.0), 0.01, Color(0, 0, 0, 0)])
	for c: Array in cones:
		_cone(verts, cols, idx, c[0], c[1], float(c[2]), c[3])
	# the stash: a chest with a lit lid, the exit ring marker
	_box(verts, cols, idx, _stash_pos + Vector3(0.0, 0.35, 0.0), Vector3(1.3, 0.7, 0.8), Color(0.12, 0.09, 0.07, 0.0))
	_box(verts, cols, idx, _stash_pos + Vector3(0.0, 0.74, 0.0), Vector3(1.2, 0.08, 0.7), Color(1.0, 0.8, 0.3, 1.0))
	_glows.clear()
	_glow_cols.clear()
	_glows.append(Vector4(_stash_pos.x, _stash_pos.y + 1.2, _stash_pos.z, 7.0))
	_glow_cols.append(Vector3(1.0, 0.75, 0.3))
	_glows.append(Vector4(_exit_pos.x, _exit_pos.y + 1.5, _exit_pos.z, 7.5))
	_glow_cols.append(Vector3(0.35, 0.8, 1.0))
	for k in mini(glow_spots.size(), 4):
		var g := glow_spots[k * 3 % glow_spots.size()]
		_glows.append(Vector4(g.x, g.y, g.z, 8.0))
		_glow_cols.append(Vector3(0.2, 0.9, 1.0) if k % 2 == 0 else Vector3(0.85, 0.35, 0.95))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	for t in idx.size() / 3:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		nrm[a] += n
		nrm[b] += n
		nrm[c] += n
	for v in nrm.size():
		nrm[v] = nrm[v].normalized() if nrm[v].length() > 1.0e-6 else Vector3.UP
	arr[Mesh.ARRAY_NORMAL] = nrm
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_tris = idx.size() / 3
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_apply_glows()
	_mi = MeshInstance3D.new()
	_mi.name = "Cave"
	_mi.mesh = mesh
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mi.custom_aabb = AABB(Vector3(-40.0, -10.0, -20.0), Vector3(140.0, 40.0, 140.0))
	_mi.position = _origin
	_mi.visible = false
	add_child(_mi)
	_body = StaticBody3D.new()
	_body.name = "CaveBody"
	_body.collision_layer = Game.L_WORLD
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	var faces := PackedVector3Array()
	for t in idx.size() / 3:
		if verts[idx[t * 3]].y - 0.0 > 0.0 or true:
			faces.append(verts[idx[t * 3]])
			faces.append(verts[idx[t * 3 + 1]])
			faces.append(verts[idx[t * 3 + 2]])
	shape.set_faces(faces)
	shape.backface_collision = true
	cs.shape = shape
	_body.add_child(cs)
	_body.position = _origin
	add_child(_body)
	set_collision_enabled(false)


func set_collision_enabled(on: bool) -> void:
	if _body != null:
		_body.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if _mi != null:
		_mi.visible = on


func _apply_glows() -> void:
	var gp := PackedVector4Array()
	var gc := PackedVector3Array()
	for i in 8:
		gp.append(Vector4(_origin.x + _glows[i].x, _origin.y + _glows[i].y, _origin.z + _glows[i].z, _glows[i].w) if i < _glows.size() else Vector4(0, 0, 0, 0))
		gc.append(_glow_cols[i] if i < _glow_cols.size() else Vector3.ZERO)
	_mat.set_shader_parameter(&"glow_pos", gp)
	_mat.set_shader_parameter(&"glow_col", gc)


static func _cone(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array, base: Vector3, tip: Vector3, r: float, col: Color) -> void:
	var seg := 5
	var b0 := verts.size()
	for k in seg:
		var a := TAU * float(k) / float(seg)
		verts.append(base + Vector3(cos(a) * r, 0.0, sin(a) * r))
		cols.append(col)
	var t := verts.size()
	verts.append(tip)
	cols.append(Color(col.r * 1.3, col.g * 1.3, col.b * 1.3, col.a))
	for k in seg:
		idx.append_array([b0 + k, t, b0 + (k + 1) % seg])


static func _box(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array, c: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var b0 := verts.size()
	for i in 8:
		verts.append(c + Vector3(h.x * (1.0 if i & 1 else -1.0), h.y * (1.0 if i & 2 else -1.0), h.z * (1.0 if i & 4 else -1.0)))
		cols.append(col)
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 2, 6, 4], [1, 5, 7, 3], [2, 3, 7, 6], [0, 4, 5, 1]]:
		idx.append_array([b0 + f[0], b0 + f[1], b0 + f[2], b0 + f[0], b0 + f[2], b0 + f[3]])


# --- going in and out -------------------------------------------------------------------------------------------------------------------------

func enter(p: Player) -> void:
	build()
	set_collision_enabled(true)
	_inside = true
	InteriorSpace.register(self, Rect2(_origin.x - 30.0, _origin.z - 14.0, 100.0, 124.0), _origin.y, 12.0, PackedFloat32Array(), PackedFloat32Array())
	p.teleport_to(entry_point())
	p.velocity = Vector3.ZERO
	p.camera_rig.snap()
	Game.say("THE CAVE  FOLLOW THE CRYSTALS", 3.0)


func leave(p: Player) -> void:
	_inside = false
	InteriorSpace.unregister(self)
	p.teleport_to(_back_to + Vector3(0.0, 0.5, 0.0))
	p.velocity = Vector3.ZERO
	p.camera_rig.snap()
	var yaw: float = site["yaw"] + PI
	p.camera_rig.yaw = yaw + PI
	set_collision_enabled(false)


func take_stash(p: Player) -> bool:
	if stash_taken or not _inside:
		return false
	if Vector2(p.global_position.x - (_origin.x + _stash_pos.x), p.global_position.z - (_origin.z + _stash_pos.z)).length() > 2.6:
		return false
	stash_taken = true
	return true


func _process(_delta: float) -> void:
	if not _inside or _mat == null:
		return
	var p := Game.player as Node3D
	if is_instance_valid(p):
		_mat.set_shader_parameter(&"torch", p.global_position + Vector3(0.0, 1.5, 0.0))


func _exit_tree() -> void:
	if _inside:
		InteriorSpace.unregister(self)


func stats() -> Dictionary:
	return {"tris": _tris, "chambers": CHAMBERS.size(), "built": built, "inside": _inside}
