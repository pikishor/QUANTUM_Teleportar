class_name TankPlaces
extends Node
## BOOTHS, BARRIERS AND FENCES of the military places of TankRoster (wave 129, w129-tankmis; until now the ARMY BASE row and the three road CHECKPOINTS were vehicles on bare ground).
##   CHECKPOINT  a guard booth with a window band and a flat roof on the shoulder, a red-and-white boom barrier raised at each end, concrete blocks along both shoulders behind the
##               parked vehicles, a run of chain-link fence (posts and wires) beyond them, and a CHECKPOINT sign
##   ARMY BASE   a fence behind the row (its east side) with short returns, a gate booth with a raised boom at the north end and an ARMY BASE sign; the west side stays open (the
##               vehicles drive out that way, and the ARMY SHELTER exit lanes lie further west)
## Built only while the hero is within BUILD_IN of a place (one merged mesh, one body, two labels per place) and freed past BUILD_OUT, like the ARMY YARD decor of ArmourSites.
## W129TM_OLD=1 (or TankPlaces.on = false): no decor.

const BUILD_IN := 230.0
const BUILD_OUT := 270.0
const BOOTH := Vector3(2.8, 2.7, 2.8)

static var on := OS.get_environment("W129TM_OLD") != "1"
static var instance: TankPlaces = null

var _built := {}
var _t := 0.0


static func attach(parent: Node) -> void:
	if not on or is_instance_valid(instance) or parent == null:
		return
	instance = TankPlaces.new()
	instance.name = "TankPlaces"
	parent.add_child(instance)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Every place that gets decor: [{id, kind (&"checkpoint" / &"base"), pos (world), dir (Vector2 along the road / the row), nrm, w (road width)}]. Empty until the outskirts roads exist.
static func places() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not TankRoster.on:
		return out
	var mid := TankRoster.BASE_LOCAL + Vector3(0.0, 0.0, TankRoster.BASE_DZ * 3.0)
	var bp := Airport.to_world(mid)
	var az := Airport.to_world(mid + Vector3(0.0, 0.0, 1.0)) - bp                 # the airport's local +z in the world (the row runs along it) ...
	var axx := Airport.to_world(mid + Vector3(1.0, 0.0, 0.0)) - bp                ## ... and its local +x (east: behind the row, the vehicles nose west)
	out.append({"id": &"army_base", "kind": &"base", "pos": bp, "dir": Vector2(az.x, az.z).normalized(), "nrm": Vector2(axx.x, axx.z).normalized(), "w": 0.0})
	if not TerrainRoads.built:
		return out
	for cp: Dictionary in TankRoster.CHECKPOINTS:
		var at := TankRoster.road_spot(String(cp["road"]), float(cp["at"]))
		if at.is_empty():
			continue
		var c: Vector2 = at["pos"]
		out.append({"id": cp["id"], "kind": &"checkpoint", "pos": Vector3(c.x, TerrainHeight.height_at(c.x, c.y), c.y), "dir": at["dir"], "nrm": at["nrm"], "w": float(at["w"])})
	return out


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	if not is_instance_valid(Game.player):
		return
	var pp := Game.player.global_position
	for s in places():
		var id: StringName = s["id"]
		var c: Vector3 = s["pos"]
		var d := Vector2(c.x - pp.x, c.z - pp.z).length()
		if not _built.has(id) and d < BUILD_IN:
			var n := build(s)
			add_child(n)
			_built[id] = n
		elif _built.has(id) and d > BUILD_OUT:
			(_built[id] as Node).queue_free()
			_built.erase(id)


func built_ids() -> Array:
	return _built.keys()


# --- building --------------------------------------------------------------------------------------------------------------------------

## A point `along` m down the road / row and `across` m to its side, on the ground (world), as a position local to `origin`.
static func _at(s: Dictionary, along: float, across: float) -> Vector3:
	var c: Vector3 = s["pos"]
	var p := Vector2(c.x, c.z) + (s["dir"] as Vector2) * along + (s["nrm"] as Vector2) * across
	return Vector3(p.x, Vehicle._terrain_y(p.x, p.y), p.y) - c


static func _yaw(s: Dictionary) -> float:
	var d: Vector2 = s["dir"]
	return atan2(-d.x, -d.y)


## One place: the merged lit mesh (vertex colours, ArmourSites' material), the body (booth and blocks) and the sign's labels.
static func build(s: Dictionary) -> Node3D:
	ArmourSites._materials()
	var root := Node3D.new()
	root.name = "Place_" + String(s["id"])
	root.position = s["pos"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	body.name = "PlaceBody"
	root.add_child(body)
	var yaw := _yaw(s)
	if s["kind"] == &"checkpoint":
		var edge := float(s["w"]) * 0.5
		var side := edge + 11.0                                                  # beyond the two parked vehicles (TankRoster: road edge + half a hull + 1.6 m) and the room to walk round them
		_booth(st, body, _at(s, -15.0, -(edge + 5.5)), yaw, "CHECKPOINT", root)      # behind the vehicle on this shoulder (it faces down the road the other way)
		for e: float in [-16.0, 16.0]:                                          # the two booms, one at each end, raised (traffic passes)
			_boom(st, _at(s, e, -(edge + 0.7) if e < 0.0 else edge + 0.7), yaw)
		for sgn: float in [-1.0, 1.0]:
			for i in 8:                                                         # concrete blocks along the shoulder
				var p := _at(s, -12.6 + 3.6 * float(i), sgn * side)
				ArmourSites._box(st, p + Vector3(0.0, 0.45, 0.0), Vector3(0.7, 0.9, 3.2), Color(0.56, 0.55, 0.52), yaw)
				ArmourSites._box(st, p + Vector3(0.0, 0.95, 0.0), Vector3(0.35, 0.12, 3.2), Color(0.95, 0.75, 0.12), yaw)      # the yellow band on top
				_wall_yaw(body, p + Vector3(0.0, 0.45, 0.0), Vector3(0.7, 0.9, 3.2), yaw)
			_fence(st, s, -30.0, 30.0, sgn * (side + 3.5), yaw)
	else:
		# the ARMY BASE: the row's local frame has the vehicles across x 1371..1381 (noses west), along z -690..-609
		var row := TankRoster.BASE_DZ * 3.0
		var east := 9.0                                                          # behind the row
		_fence(st, s, -row - 9.0, row + 9.0, east, yaw, true, body)
		_fence_cross(st, s, -row - 9.0, 1.0, east, yaw)
		_fence_cross(st, s, row + 9.0, 1.0, east, yaw)
		_booth(st, body, _at(s, -row - 12.0, 4.0), yaw + PI * 0.5, "ARMY BASE", root)
		_boom(st, _at(s, -row - 9.5, -5.0), yaw + PI * 0.5)
	var mi := MeshInstance3D.new()
	mi.name = "PlaceMesh"
	mi.mesh = st.commit()
	mi.material_override = ArmourSites._mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if Game.quality >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root


static func _wall_yaw(body: StaticBody3D, c: Vector3, size: Vector3, yaw: float) -> void:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.position = c
	cs.rotation.y = yaw
	body.add_child(cs)


## The guard booth: walls, a window band all round, a door, an overhanging flat roof, and the sign beside it.
static func _booth(st: SurfaceTool, body: StaticBody3D, p: Vector3, yaw: float, text: String, root: Node3D) -> void:
	var b := Basis(Vector3.UP, yaw)
	var wall := Color(0.82, 0.8, 0.72)
	var glass := Color(0.22, 0.34, 0.4)
	ArmourSites._box(st, p + Vector3(0.0, 0.08, 0.0), Vector3(BOOTH.x + 0.6, 0.16, BOOTH.z + 0.6), Color(0.5, 0.5, 0.48), yaw)                 # the plinth
	ArmourSites._box(st, p + Vector3(0.0, 0.16 + 0.55, 0.0), Vector3(BOOTH.x, 1.1, BOOTH.z), wall, yaw)                                  # below the windows
	ArmourSites._box(st, p + Vector3(0.0, 1.26 + 0.5, 0.0), Vector3(BOOTH.x - 0.06, 1.0, BOOTH.z - 0.06), glass, yaw)                   # the window band
	for cx: float in [-1.0, 1.0]:                                                                                                      # corner posts between the windows
		for cz: float in [-1.0, 1.0]:
			ArmourSites._box(st, p + b * Vector3(cx * (BOOTH.x * 0.5 - 0.08), 1.76, cz * (BOOTH.z * 0.5 - 0.08)), Vector3(0.16, 1.0, 0.16), wall, yaw)
	ArmourSites._box(st, p + Vector3(0.0, 2.26 + 0.22, 0.0), Vector3(BOOTH.x, 0.44, BOOTH.z), wall, yaw)                                 # above the windows
	ArmourSites._box(st, p + Vector3(0.0, 2.8, 0.0), Vector3(BOOTH.x + 0.9, 0.16, BOOTH.z + 0.9), Color(0.3, 0.32, 0.3), yaw)             # the roof
	ArmourSites._box(st, p + b * Vector3(BOOTH.x * 0.5 + 0.01, 1.1, 0.5), Vector3(0.04, 1.9, 0.9), Color(0.36, 0.38, 0.36), yaw)        # the door
	ArmourSites._box(st, p + b * Vector3(0.0, 3.0, 0.0), Vector3(0.5, 0.25, 0.5), Color(0.92, 0.55, 0.12), yaw)                           # the beacon lamp
	_wall_yaw(body, p + Vector3(0.0, 1.4, 0.0), Vector3(BOOTH.x, 2.8, BOOTH.z), yaw)
	var sg := Node3D.new()
	sg.position = p + b * Vector3(-BOOTH.x * 0.5 - 2.8, 0.0, 0.0)
	sg.rotation.y = yaw + PI * 0.5
	root.add_child(sg)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	ArmourSites._sign(sg, st2, Vector3.ZERO, text, 5.6, 3.6, Color(0.2, 0.25, 0.16))
	var smi := MeshInstance3D.new()
	smi.mesh = st2.commit()
	smi.material_override = ArmourSites._mat
	sg.add_child(smi)


## A boom barrier: the post with its counterweight box, the striped arm raised almost upright.
static func _boom(st: SurfaceTool, p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	ArmourSites._box(st, p + Vector3(0.0, 0.55, 0.0), Vector3(0.45, 1.1, 0.45), Color(0.85, 0.82, 0.7), yaw)
	ArmourSites._box(st, p + b * Vector3(0.0, 1.0, 0.45), Vector3(0.3, 0.35, 0.5), Color(0.25, 0.25, 0.25), yaw)
	var up := Basis(b.x, -0.25) * b                                                              # tipped a little off vertical
	for i in 7:                                                                                   # red and white segments
		var c := p + Vector3(0.0, 1.15, 0.0) + up * Vector3(0.0, 0.3 + 0.62 * float(i), 0.0)
		var col := Color(0.86, 0.12, 0.1) if i % 2 == 0 else Color(0.95, 0.95, 0.92)
		_box_basis(st, c, Vector3(0.12, 0.62, 0.12), col, up)


static func _box_basis(st: SurfaceTool, c: Vector3, size: Vector3, col: Color, b: Basis) -> void:
	var h := size * 0.5
	var faces := [[Vector3.UP, Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)], [Vector3.BACK, Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, -1, 1)],
		[Vector3.FORWARD, Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, -1)], [Vector3.RIGHT, Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(1, -1, -1)],
		[Vector3.LEFT, Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(-1, -1, 1)]]
	for f: Array in faces:
		st.set_color(col * (1.0 if f[0] == Vector3.UP else 0.84))
		st.set_normal(b * (f[0] as Vector3))
		for i: int in [1, 2, 3, 1, 3, 4]:
			st.add_vertex(c + b * ((f[i] as Vector3) * h))


## A run of chain-link fence `across` m off the line, from `a` to `b` m along it: posts every 3 m, four wires, a top rail. `wall`: one thin collider along it.
static func _fence(st: SurfaceTool, s: Dictionary, a: float, b: float, across: float, yaw: float, wall := false, body: StaticBody3D = null) -> void:
	var post := Color(0.42, 0.44, 0.42)
	var wire := Color(0.55, 0.57, 0.55)
	var n := maxi(int((b - a) / 3.0), 1)
	for i in n + 1:
		var p := _at(s, a + (b - a) * float(i) / float(n), across)
		ArmourSites._box(st, p + Vector3(0.0, 1.1, 0.0), Vector3(0.09, 2.2, 0.09), post, yaw)
		if i < n:
			var q := _at(s, a + (b - a) * float(i + 1) / float(n), across)
			var mid := (p + q) * 0.5
			var seg := Vector2(q.x - p.x, q.z - p.z).length()
			for hgt: float in [0.35, 0.9, 1.45, 2.0]:
				ArmourSites._box(st, mid + Vector3(0.0, hgt, 0.0), Vector3(0.025, 0.03 if hgt < 2.0 else 0.06, seg), wire if hgt < 2.0 else post, yaw)
	if wall and body != null:
		var c0 := _at(s, (a + b) * 0.5, across)
		_wall_yaw(body, c0 + Vector3(0.0, 1.1, 0.0), Vector3(0.2, 2.2, b - a), yaw)


## A short return of fence across the line at `along`, from `across0` to `across1`.
static func _fence_cross(st: SurfaceTool, s: Dictionary, along: float, across0: float, across1: float, yaw: float) -> void:
	var n := maxi(int(absf(across1 - across0) / 3.0), 1)
	for i in n + 1:
		var p := _at(s, along, lerpf(across0, across1, float(i) / float(n)))
		ArmourSites._box(st, p + Vector3(0.0, 1.1, 0.0), Vector3(0.09, 2.2, 0.09), Color(0.42, 0.44, 0.42), yaw)
	var c := _at(s, along, (across0 + across1) * 0.5)
	for hgt: float in [0.35, 0.9, 1.45, 2.0]:
		ArmourSites._box(st, c + Vector3(0.0, hgt, 0.0), Vector3(absf(across1 - across0), 0.03, 0.025), Color(0.55, 0.57, 0.55), yaw)
