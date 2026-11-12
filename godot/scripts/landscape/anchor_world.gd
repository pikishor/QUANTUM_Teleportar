class_name AnchorWorld
extends Node3D
## The tall anchors of the outskirts in the live world (wave 112): wind turbine fields (towers one MultiMesh, heads another: the blades spin in the vertex shader with the wind and the
## heads turn into it), pylon lines with sagging wires, guyed radio masts with blinking beacons, tower cranes at the quarry. Kit: assets/models/land_props.glb (tools/landscape/props.py),
## shader assets/shaders/land_prop.gdshader, places AnchorSites. One node per site at its centre with a visibility range, so every site costs a handful of draws within SHOW m of the
## camera and none beyond it (the city views never see one). A pool of cylinder colliders follows the hero: you cannot walk or drive through a tower.
##   AnchorWorld.instance.anchors_near(pos, radius) -> [{id, kind, name, pos (top), base, height, radius}]: where a rope (quantum snake) can be fixed
##   stats() {sites, drawn_tris, anchors}      settle(pos) (look-dev)

const MODEL_PATH := "res://assets/models/land_props.glb"
const SHADER_PATH := "res://assets/shaders/land_prop.gdshader"
const SHOW := 1300.0
const COLLIDERS := 10
const ARMS := [[30.0, 7.2], [33.6, 6.4], [37.0, 5.4]]
const INSULATOR := 2.3
const HUB_Y := 62.2                                   ## the hub height above the base (tower 64 m minus the nacelle's offset)

static var instance: AnchorWorld = null
static var _meshes := {}

var quality := 1
var _mat: ShaderMaterial
var _sites: Array = []                                ## {node, kind, centre}
var _anchors: Array = []
var _heads: Array = []                                ## per turbine field: {mm, pos: Array[Vector3], yaw: PackedFloat32Array, centre}
var _pool: Array[StaticBody3D] = []
var _tris := 0
var _last_pool := Vector2(1.0e9, 1.0e9)
var _t := 0.0


func _ready() -> void:
	instance = self
	_load_meshes()
	if _meshes.is_empty():
		return
	LandClimate.ensure()
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH) as Shader
	AnchorSites.ensure()
	_anchors = AnchorSites.all_anchors()
	_build_turbines()
	_build_lines()
	_build_masts()
	_build_cranes()
	_make_pool()
	set_process(true)


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func _load_meshes() -> void:
	if not _meshes.is_empty():
		return
	var ps := load(MODEL_PATH) as PackedScene
	if ps == null:
		return
	var root := ps.instantiate()
	for n in root.get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			_meshes[String(n.name)] = (n as MeshInstance3D).mesh
	root.free()


static func mesh(nm: String) -> Mesh:
	_load_meshes()
	return _meshes.get(nm)


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)


func stats() -> Dictionary:
	return {"anchor_sites": _sites.size(), "anchors": _anchors.size(), "anchor_tris": _tris}


## The anchors within `radius` metres of `pos` (horizontally), nearest first.
func anchors_near(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	for a: Dictionary in _anchors:
		var b: Vector3 = a["base"]
		var d := Vector2(b.x - pos.x, b.z - pos.z).length()
		if d <= radius:
			var e: Dictionary = a.duplicate()
			e["dist"] = d
			out.append(e)
	out.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["dist"]) < float(q["dist"]))
	return out


func settle(pos: Vector3) -> void:
	_refresh_pool(pos)
	_turn_heads(true)


# --- builders -----------------------------------------------------------------------------------------------------------------------------------

func _site(kind: String, id: String, centre: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = id
	n.top_level = true
	n.position = centre
	add_child(n)
	_sites.append({"node": n, "kind": kind, "centre": centre})
	return n


func _mm(parent: Node3D, mesh_name: String, xfs: Array, centre: Vector3, custom := false, material: ShaderMaterial = null) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = custom
	mm.mesh = mesh(mesh_name)
	mm.instance_count = xfs.size()
	for i in xfs.size():
		var t: Transform3D = xfs[i]
		t.origin -= centre
		mm.set_instance_transform(i, t)
		if custom:
			mm.set_instance_custom_data(i, Color(fposmod(float(i) * 0.37 + 0.11, 1.0), 0.0, 0.0, 0.0))
	var mi := MultiMeshInstance3D.new()
	mi.name = mesh_name
	mi.multimesh = mm
	mi.material_override = material if material != null else _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = SHOW
	mi.visibility_range_end_margin = 80.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	parent.add_child(mi)
	_tris += (mesh(mesh_name) as ArrayMesh).get_surface_count() * 0 + _mesh_tris(mesh_name) * xfs.size()
	return mi


static func _mesh_tris(nm: String) -> int:
	var m := mesh(nm)
	if m == null:
		return 0
	var n := 0
	for s in m.get_surface_count():
		n += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func _build_turbines() -> void:
	var turb := AnchorSites.turbines()
	for fd: Dictionary in AnchorSites.fields():
		var centre: Vector3 = fd["centre"]
		var site := _site("turbines", String(fd["id"]), centre)
		var towers: Array = []
		var heads: Array = []
		var tops: Array[Vector3] = []
		var yaws := PackedFloat32Array()
		for ti: int in fd["turbines"]:
			var p: Vector3 = turb[ti]["pos"]
			towers.append(Transform3D(Basis.from_euler(Vector3(0.0, float(ti) * 1.7, 0.0)), p + Vector3(0, -0.4, 0)))
			heads.append(Transform3D(Basis.IDENTITY, p + Vector3(0, HUB_Y, 0)))
			tops.append(p + Vector3(0, HUB_Y, 0))
			yaws.append(0.0)
		_mm(site, "turbine_tower", towers, centre)
		var hm := _mm(site, "turbine_head", heads, centre, true)
		_heads.append({"mm": hm.multimesh, "tops": tops, "yaw": yaws, "centre": centre})
	_turn_heads(true)


## Turn every turbine head towards the wind (rotor facing into it); `snap` = at once (a build or a teleport), else at most a few degrees per tick.
func _turn_heads(snap: bool) -> void:
	var wd := LandClimate.direction()
	var target := atan2(-wd.x, -wd.y)
	for h: Dictionary in _heads:
		var mm: MultiMesh = h["mm"]
		var tops: Array = h["tops"]
		var yaws: PackedFloat32Array = h["yaw"]
		for i in tops.size():
			var y := yaws[i]
			y = target if snap else y + clampf(angle_difference(y, target), -0.12, 0.12)
			yaws[i] = y
			var t := Transform3D(Basis.from_euler(Vector3(0.0, y, 0.0)), (tops[i] as Vector3) - (h["centre"] as Vector3))
			mm.set_instance_transform(i, t)
		h["yaw"] = yaws


func _build_lines() -> void:
	for ld: Dictionary in AnchorSites.pylon_lines():
		var py: Array = ld["pylons"]
		var xfs: Array = []
		var cs := Vector3.ZERO
		var n := 0
		for p: Dictionary in py:
			if p.has("gap"):
				continue
			xfs.append(Transform3D(Basis.from_euler(Vector3(0.0, float(p["yaw"]), 0.0)), p["pos"]))
			cs += p["pos"]
			n += 1
		if n < 2:
			continue
		var centre := cs / float(n)
		var site := _site("pylons", String(ld["id"]), centre)
		_mm(site, "pylon", xfs, centre)
		var wires := _wire_mesh(py, centre)
		var wi := MeshInstance3D.new()
		wi.name = "Wires"
		wi.mesh = wires
		wi.material_override = _mat
		wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wi.visibility_range_end = SHOW
		site.add_child(wi)
		_tris += wires.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3


## Conductors between consecutive pylons: six wires per span (three arms, both sides), a parabola with a sag of 2.4 % of the span, each wire two thin crossed quads (code 3 = wire).
func _wire_mesh(py: Array, centre: Vector3) -> ArrayMesh:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var wcol := Color(0.1, 0.1, 0.11, 3.0)
	for i in py.size() - 1:
		if (py[i] as Dictionary).has("gap") or (py[i + 1] as Dictionary).has("gap"):
			continue
		var a: Dictionary = py[i]
		var b: Dictionary = py[i + 1]
		for arm: Array in ARMS:
			for sx in [-1.0, 1.0]:
				var pa := _attach(a, float(sx) * float(arm[1]), float(arm[0]) - INSULATOR)
				var pb := _attach(b, float(sx) * float(arm[1]), float(arm[0]) - INSULATOR)
				var span := pa.distance_to(pb)
				var sag := span * 0.024
				var prev := pa
				for k in range(1, 11):
					var t := float(k) / 10.0
					var q := pa.lerp(pb, t) - Vector3(0.0, sag * 4.0 * t * (1.0 - t), 0.0)
					for cross in 2:
						var side := Vector3(0.0, 1.0, 0.0) if cross == 0 else (pb - pa).cross(Vector3.UP).normalized()
						var w := 0.07
						var base := pos.size()
						pos.append(prev - centre - side * w)
						pos.append(prev - centre + side * w)
						pos.append(q - centre + side * w)
						pos.append(q - centre - side * w)
						for _j in 4:
							nrm.append(Vector3.UP)
							col.append(wcol)
							uv2.append(Vector2.ZERO)
						idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
					prev = q
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	if pos.size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _attach(p: Dictionary, local_x: float, y: float) -> Vector3:
	var yaw: float = p["yaw"]
	var base: Vector3 = p["pos"]
	var c := cos(yaw)
	var s := sin(yaw)
	return base + Vector3(local_x * c, y, -local_x * s)


func _build_masts() -> void:
	for md: Dictionary in AnchorSites.masts():
		var p: Vector3 = md["pos"]
		var site := _site("mast", String(md["id"]), p)
		_mm(site, "mast", [Transform3D(Basis.from_euler(Vector3(0.0, hash(String(md["id"])) % 628 / 100.0, 0.0)), p)], p)


func _build_cranes() -> void:
	for cd: Dictionary in AnchorSites.cranes():
		var p: Vector3 = cd["pos"]
		var site := _site("crane", String(cd["id"]), p)
		_mm(site, "crane", [Transform3D(Basis.from_euler(Vector3(0.0, float(cd["yaw"]), 0.0)), p)], p)


# --- colliders and the tick -----------------------------------------------------------------------------------------------------------------------

func _make_pool() -> void:
	for i in COLLIDERS:
		var b := StaticBody3D.new()
		b.name = "Anchor%d" % i
		b.collision_layer = Game.L_WORLD
		b.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = CylinderShape3D.new()
		b.add_child(cs)
		b.top_level = true
		b.position = Vector3(0.0, -2000.0, 0.0)
		add_child(b)
		_pool.append(b)


func _refresh_pool(at: Vector3) -> void:
	var near := anchors_near(at, 110.0)
	for i in _pool.size():
		var b := _pool[i]
		if i < near.size():
			var a: Dictionary = near[i]
			var cyl := (b.get_child(0) as CollisionShape3D).shape as CylinderShape3D
			cyl.radius = float(a["radius"])
			cyl.height = float(a["height"])
			var base: Vector3 = a["base"]
			b.global_position = base + Vector3(0.0, float(a["height"]) * 0.5, 0.0)
		else:
			b.global_position = Vector3(0.0, -2000.0, 0.0)
	_last_pool = Vector2(at.x, at.z)


func _process(delta: float) -> void:
	if _mat == null:
		return
	_t += delta
	if _t < 0.5:
		return
	_t = 0.0
	var p := Game.player as Node3D
	if not is_instance_valid(p):
		return
	var at := p.global_position
	if Vector2(at.x, at.z).distance_to(_last_pool) > 14.0:
		_refresh_pool(at)
	_turn_heads(false)
