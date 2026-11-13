class_name StripWorld
extends Node3D
## The grass airstrips in the live world (wave 112; data LandscapeSites.strips(), shader assets/shaders/airstrip.gdshader): the mown strip, a gabled hangar (with a collision box), a
## windsock that swings with the wind (the shader turns it), edge markers with lights that glow at night. The ground itself is the graded terrain (flat, drivable); the aircraft wave
## places its planes using `StripWorld.hooks()`.  Nodes sit at the strip centre with a visibility range; none is drawn beyond SHOW m.
##   StripWorld.instance.strip_count()   stats()   settle(pos)
## Names of the strips: FOOTHILL, WESTWOOD, SOUTH, LAGOON, EAST SHORE, FAR NORTH and FAR WEST STRIP (found by LandscapeSites on the flattest corridors clear of roads and site pads; the first four are near the city).

const SHADER := "res://assets/shaders/airstrip.gdshader"
const SHOW := 1000.0
const TONES := {&"foothill_strip": 0.15, &"westwood_strip": 0.05, &"south_strip": 0.45, &"lagoon_strip": 0.2, &"east_shore_strip": 0.5, &"far_north_strip": 0.1, &"far_west_strip": 0.2}      ## fresh grass .. dry straw per strip (the shader's `tone`)

static var instance: StripWorld = null

var quality := 1
var _nodes: Array[Node3D] = []

var _tris := 0


func _ready() -> void:
	instance = self
	LandscapeSites.ensure()
	LandClimate.ensure()
	if AnchorWorld.mesh("hangar") == null:
		return
	for s: Dictionary in LandscapeSites.strips():
		_nodes.append(_build(s))


func _exit_tree() -> void:
	if instance == self:
		instance = null


func strip_count() -> int:
	return _nodes.size()


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)


func settle(_pos: Vector3) -> void:
	pass


func stats() -> Dictionary:
	return {"strips": _nodes.size(), "strip_tris": _tris}


static func hooks() -> Array:
	return LandscapeSites.hooks().filter(func(h: Dictionary) -> bool: return StringName(h["kind"]) == &"airstrip")


func _prop_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(AnchorWorld.SHADER_PATH) as Shader
	return m


func _build(s: Dictionary) -> Node3D:
	var c2: Vector2 = s["c"]
	var u: Vector2 = s["u"]
	var len_m: float = s["len"]
	var wid: float = s["wid"]
	var y0: float = s["y"]
	var root := Node3D.new()
	root.name = String(s["id"])
	root.top_level = true
	root.position = Vector3(c2.x, y0, c2.y)
	add_child(root)
	var yaw := atan2(u.x, u.y)                              # the strip runs along local +z after this yaw (u = (sin yaw, cos yaw))
	# the strip: a grid following the ground
	var rows := int((len_m + 12.0) / 10.0)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var cols := 4
	var side := Vector2(-u.y, u.x)
	for i in rows + 1:
		var a := -len_m * 0.5 - 6.0 + (len_m + 12.0) * float(i) / float(rows)
		for j in cols + 1:
			var b := (float(j) / float(cols) - 0.5) * (wid + 5.0)
			var q := c2 + u * a + side * b
			var gy := TerrainHeight.height_at(q.x, q.y) + 0.09
			pos.append(Vector3(q.x, gy, q.y) - root.position)
			nrm.append(Vector3.UP)
			uv.append(Vector2(b, a + len_m * 0.5))
			col.append(Color(len_m / 1000.0, wid / 100.0, 0.0, 1.0))
	for i in rows:
		for j in cols:
			var k := i * (cols + 1) + j
			idx.append_array(PackedInt32Array([k, k + cols + 1, k + 1, k + 1, k + cols + 1, k + cols + 2]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Strip"
	mi.mesh = m
	var sm := ShaderMaterial.new()
	sm.shader = load(SHADER) as Shader
	sm.set_shader_parameter(&"tone", float(TONES.get(StringName(s["id"]), 0.3)))
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = SHOW
	root.add_child(mi)
	_tris += idx.size() / 3
	var pm := _prop_material()
	# the hangar beside the middle of the strip, its doors towards the strip
	var hp := c2 + side * (wid * 0.5 + 24.0) + u * (len_m * 0.18)
	_prop(root, "hangar", pm, Transform3D(Basis.from_euler(Vector3(0.0, yaw + (PI if true else 0.0), 0.0)), Vector3(hp.x, TerrainHeight.height_at(hp.x, hp.y), hp.y)))
	var body := StaticBody3D.new()
	body.name = "HangarBody"
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	var bs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(14.2, 6.0, 10.4)
	bs.shape = box
	bs.rotation.y = yaw
	bs.position = Vector3(0.0, 3.0, 0.0)
	body.add_child(bs)
	body.top_level = true
	body.position = Vector3(hp.x, TerrainHeight.height_at(hp.x, hp.y), hp.y)                  # top_level: the position is global (global_position needs the tree)
	root.add_child(body)
	# the windsock at the other side of the strip
	var wp := c2 - side * (wid * 0.5 + 14.0) - u * (len_m * 0.12)
	_prop(root, "windsock", pm, Transform3D(Basis.IDENTITY, Vector3(wp.x, TerrainHeight.height_at(wp.x, wp.y), wp.y)), true)
	# edge markers every 24 m on both sides
	var marks: Array = []
	var k := -len_m * 0.5 + 6.0
	while k <= len_m * 0.5 - 6.0:
		for sd in [-1.0, 1.0]:
			var q2 := c2 + u * k + side * (float(sd) * (wid * 0.5 + 1.2))
			marks.append(Transform3D(Basis.IDENTITY, Vector3(q2.x, TerrainHeight.height_at(q2.x, q2.y), q2.y)))
		k += 24.0
	_prop_many(root, "marker", pm, marks)
	return root


func _prop(root: Node3D, mesh_name: String, mat: ShaderMaterial, t: Transform3D, custom := false) -> void:
	_prop_many(root, mesh_name, mat, [t], custom)


func _prop_many(root: Node3D, mesh_name: String, mat: ShaderMaterial, xfs: Array, custom := true) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = AnchorWorld.mesh(mesh_name)
	mm.instance_count = xfs.size()
	for i in xfs.size():
		var t: Transform3D = xfs[i]
		t.origin -= root.position
		mm.set_instance_transform(i, t)
		mm.set_instance_custom_data(i, Color(fposmod(float(i) * 0.37 + 0.2, 1.0), 0.0, 0.0, 0.0))
	var mi := MultiMeshInstance3D.new()
	mi.name = mesh_name
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = SHOW
	root.add_child(mi)
	_tris += AnchorWorld._mesh_tris(mesh_name) * xfs.size()
