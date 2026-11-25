class_name RoofParapets
extends Node3D
## Wave 122 (w122-shops; open since wave 121 "no roof parapet colliders"): a low wall (HEIGHT m, one collider box per edge run) along the roof edges of the city buildings around the
## hero while he is up on the roofs, so a walk does not carry him over the edge by accident. A jump clears it (JUMP_SPEED 7.6 m/s: apex 1.31 m > HEIGHT), and the snake's swing
## and zip move him over it. An edge is fenced only where the roof really ends: a piece whose outside is another part of the same building at that height (a setback joining a
## taller part) stays open. Built for the lots within RADIUS m of the hero, rebuilt when he moves more than REBUILD m; nothing at all while he is near the street.
## One StaticBody3D on the world layer and one mesh (a dark coping strip, one draw call) for the edges that exist.

const BM := preload("res://scripts/world/building_meshes.gd")
const HEIGHT := 0.9
const THICK := 0.25
const RADIUS := 45.0
const REBUILD := 12.0
const MIN_Y := 5.0              ## the hero must be this high to need parapets
const PIECE := 2.0

static var enabled := OS.get_environment("W122_SHOPS_OLD") != "1"      ## W122_SHOPS_OLD=1 in the checks: no parapets (the wave 121 roofs)
static var instance: RoofParapets
static var built := 0           ## boxes standing now (tests)

var _body: StaticBody3D
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _at := Vector3.INF
var _scan := 0.0
var _lift_at := Vector3.INF     ## w122 integrator: the TowerLift cabin the walls were built around (a gap at its roof door)


func _ready() -> void:
	instance = self
	name = "RoofParapets"
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.9


func _exit_tree() -> void:
	_clear()
	if instance == self:
		instance = null


func _physics_process(delta: float) -> void:
	# w122 integrator (tests/test_flight_cost_w116.gd zip check: 5 of 6 roof zips, 7 of 7 without parapets): a ZIP's arc comes in low over the roof edge and met this wall,
	# so the walls do not block the hero while a snake move (zip, swing, haul) carries him
	if is_instance_valid(_body):
		var pl = Game.player
		var moving: bool = is_instance_valid(pl) and (&"snake" in pl) and pl.snake != null and pl.snake.mode != SnakeTraversal.Mode.NONE
		_body.collision_layer = 0 if moving else Game.L_WORLD
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = 0.3
	var p := Game.player as Node3D
	if not enabled or not is_instance_valid(p) or Game.world == null or not (&"building_data" in Game.world):
		_clear()
		return
	var pp := p.global_position
	if pp.y < MIN_Y or absf(pp.x) > CityLayout.HALF or absf(pp.z) > CityLayout.HALF:
		if pp.y < MIN_Y - 2.0:
			_clear()
		return
	if _at.is_finite() and Vector2(pp.x - _at.x, pp.z - _at.z).length() < REBUILD and _lift_pos() == _lift_at:
		return
	_build(pp)


func _clear() -> void:
	if is_instance_valid(_body):
		_body.queue_free()
	if is_instance_valid(_mesh):
		_mesh.queue_free()
	_body = null
	_mesh = null
	_at = Vector3.INF
	built = 0


## w122 integrator (tests/test_lifts_w121.gd: the stick could not walk the hero out of the lift onto the roof): the lift's cabin, or INF with no lift.
func _lift_pos() -> Vector3:
	var tl := TowerLift.instance
	if tl == null or not is_instance_valid(tl) or tl.lot_idx < 0:
		return Vector3.INF
	return tl.base.origin


func _build(pp: Vector3) -> void:
	_clear()
	_at = pp
	_lift_at = _lift_pos()
	_body = StaticBody3D.new()
	_body.name = "ParapetBody"
	_body.collision_layer = Game.L_WORLD
	_body.collision_mask = 0
	add_child(_body)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var city = Game.world
	for b in city.building_data:
		var lot: CityLayout.Lot = b.lot
		if Vector2(lot.cx - pp.x, lot.cz - pp.z).length() > RADIUS + maxf(lot.w, lot.d) * 0.5:
			continue
		var parts: Array = BM.CLASSES[b.cls]
		for p: Array in parts:
			var top: float = float(p[5]) * lot.h
			var x0: float = lot.cx + float(p[0]) * lot.w
			var x1: float = lot.cx + float(p[1]) * lot.w
			var z0: float = lot.cz + float(p[2]) * lot.d
			var z1: float = lot.cz + float(p[3]) * lot.d
			_edge(st, b, Vector3(x0, top, z0), Vector3(x1, top, z0), Vector3(0, 0, -1))
			_edge(st, b, Vector3(x0, top, z1), Vector3(x1, top, z1), Vector3(0, 0, 1))
			_edge(st, b, Vector3(x0, top, z0), Vector3(x0, top, z1), Vector3(-1, 0, 0))
			_edge(st, b, Vector3(x1, top, z0), Vector3(x1, top, z1), Vector3(1, 0, 0))
	if built > 0:
		st.generate_normals()
		_mesh = MeshInstance3D.new()
		_mesh.name = "ParapetMesh"
		_mesh.mesh = st.commit()
		_mesh.material_override = _mat
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)


## One roof edge from a to b (outward normal `out`), fenced in runs where its outside drops away.
func _edge(st: SurfaceTool, b, a: Vector3, c: Vector3, out: Vector3) -> void:
	var lot: CityLayout.Lot = b.lot
	var len := a.distance_to(c)
	var n := maxi(1, int(ceil(len / PIECE)))
	var run0 := -1
	for i in n + 1:
		var open_here := true
		if i < n:
			var m := a.lerp(c, (float(i) + 0.5) / float(n)) + out * 0.4
			open_here = BM.contains(b.cls, m.x - lot.cx, a.y - 0.05, m.z - lot.cz, lot.w, lot.d, lot.h)
			if _lift_at.is_finite() and Vector2(m.x - _lift_at.x, m.z - _lift_at.z).length() < 3.2:
				open_here = true                                # the gap at the lift's roof door
		if not open_here and run0 < 0:
			run0 = i
		elif open_here and run0 >= 0:
			_wall(st, a.lerp(c, float(run0) / float(n)), a.lerp(c, float(i) / float(n)), out)
			run0 = -1


func _wall(st: SurfaceTool, a: Vector3, c: Vector3, out: Vector3) -> void:
	var lo := Vector3(minf(a.x, c.x), a.y, minf(a.z, c.z)) - out * THICK * (0.0 if (out.x + out.z) < 0.0 else 1.0)
	var hi := Vector3(maxf(a.x, c.x), a.y + HEIGHT, maxf(a.z, c.z)) - out * THICK * (1.0 if (out.x + out.z) < 0.0 else 0.0)
	if absf(out.x) > 0.5:
		lo.x = minf(a.x, a.x - out.x * THICK)
		hi.x = maxf(a.x, a.x - out.x * THICK)
	else:
		lo.z = minf(a.z, a.z - out.z * THICK)
		hi.z = maxf(a.z, a.z - out.z * THICK)
	var sh := BoxShape3D.new()
	sh.size = hi - lo
	var cs := CollisionShape3D.new()
	cs.shape = sh
	cs.position = (lo + hi) * 0.5
	_body.add_child(cs)
	built += 1
	var col := Color(0.16, 0.16, 0.18)
	var v := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
			Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	for f: Array in [[4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		var q: Array = [v[f[0]], v[f[1]], v[f[2]], v[f[3]]]
		var nn: Vector3 = (q[1] - q[0]).cross(q[2] - q[0])
		var center: Vector3 = (lo + hi) * 0.5
		var outward: Vector3 = (q[0] + q[2]) * 0.5 - center
		var order := [0, 3, 2, 0, 2, 1] if nn.dot(outward) > 0.0 else [0, 1, 2, 0, 2, 3]
		var shade := 1.0 if f[0] == 4 else 0.75
		for k: int in order:
			st.set_color(Color(col.r * shade, col.g * shade, col.b * shade))
			st.add_vertex(q[k])
