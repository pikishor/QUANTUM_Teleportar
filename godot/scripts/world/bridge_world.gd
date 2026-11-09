class_name BridgeWorld
extends Node3D
## The bridges in the live world (data: Bridges, meshes: BridgeKit). Child `bridges` of the City (BridgeWorld.attach). Per bridge: the structure mesh and the road surface (two draw calls, culled by
## distance), ONE StaticBody3D with the deck as a box per straight run and a parapet wall per side (so a car cannot leave the deck and the hero walks on it), and for the three big road crossings
## and the HARBOUR GATE a few scenery cars that drive across when the hero is near (BridgeTraffic: no physics, they follow the deck and are always on it).
##   BridgeWorld.instance        the node (null before the city is built)
##   stats()                     {bridges, shapes, tris, traffic}
## `QT_NO_BRIDGES=1` leaves them out (perf A/B runs).

const SHOW_RANGE := 1450.0                       ## structures are drawn up to this distance from the camera (the per-tier draw budget counts everything in the frustum: the start of the city must not see them)
const TRAFFIC_RANGE := 520.0
const TRAFFIC_PER_BRIDGE := 4

static var instance: BridgeWorld = null

var bodies := {}                                 ## bridge id -> StaticBody3D
var shapes := 0
var tris := 0
var traffic: Array[BridgeTraffic] = []
var _nodes: Array[Node3D] = []
var _tick := 0.0


static func attach(parent: Node) -> BridgeWorld:
	var w := BridgeWorld.new()
	w.name = "BridgeWorld"
	parent.add_child(w)
	return w


func _ready() -> void:
	instance = self
	Bridges.ensure()
	for b in Bridges.list:
		_build(b)
	set_process(true)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _build(b: Dictionary) -> void:
	var id: StringName = b["id"]
	var holder := Node3D.new()
	holder.name = String(id)
	add_child(holder)
	_nodes.append(holder)
	var mi := MeshInstance3D.new()
	mi.name = "Structure"
	mi.mesh = BridgeKit.structure(b)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = SHOW_RANGE
	tris += _tri_count(mi.mesh)
	holder.add_child(mi)
	if b["kind"] in [&"road", &"track", &"suspension"]:
		var rd := MeshInstance3D.new()
		rd.name = "Road"
		rd.mesh = BridgeKit.road_ribbon(b)
		rd.material_override = BridgeKit.road_material(&"track" if b["kind"] == &"track" else &"road")
		rd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rd.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		rd.visibility_range_end = SHOW_RANGE
		tris += _tri_count(rd.mesh)
		holder.add_child(rd)
	var body := _collider(b)
	holder.add_child(body)
	bodies[id] = body
	if (b["kind"] == &"road" and float(b["len"]) > 60.0) or b["kind"] == &"suspension":
		for k in TRAFFIC_PER_BRIDGE:
			var t := BridgeTraffic.new()
			t.setup(b, k)
			traffic.append(t)
			add_child(t)


static func _tri_count(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		n += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if arr[Mesh.ARRAY_INDEX] != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


## The deck (a box per segment of the centre line, its top exactly at the deck height) and a parapet wall along each edge, in one body on the world layer.
func _collider(b: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Deck"
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	var pts: PackedVector3Array = b["pts"]
	var hw := float(b["w"]) * 0.5
	var rail: bool = b["kind"] != &"rail"
	for s in pts.size() - 1:
		var a := pts[s]
		var c := pts[s + 1]
		var d := c - a
		var l := d.length()
		if l < 0.5:
			continue
		var fwd := d / l
		var up := Vector3.UP
		var right := fwd.cross(up).normalized()
		up = right.cross(fwd).normalized()
		var basis := Basis(right, up, -fwd)                          # looking down -Z along the segment
		var mid := (a + c) * 0.5
		var thick := 1.0
		_box(body, Transform3D(basis, mid - up * thick * 0.5), Vector3(hw * 2.0, thick, l + 0.2))
		if rail:
			for sx in [-1.0, 1.0]:
				_box(body, Transform3D(basis, mid + right * float(sx) * (hw - 0.25) + up * 0.55), Vector3(0.5, 1.2, l + 0.2))
	return body


func _box(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	body.add_child(cs)
	shapes += 1


func stats() -> Dictionary:
	return {"bridges": Bridges.list.size(), "shapes": shapes, "tris": tris, "traffic": traffic.size()}


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	var ppos := Vector3.INF
	var p := Game.player as Node3D
	if is_instance_valid(p):
		ppos = p.global_position
	for t in traffic:
		t.set_active(ppos.is_finite() and Vector2(t.anchor.x - ppos.x, t.anchor.z - ppos.z).length() < TRAFFIC_RANGE)
