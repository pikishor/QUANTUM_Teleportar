class_name HarbourWorld
extends Node3D
## The harbour in the live world (data: Harbour, meshes: HarbourKit). Child of the City (HarbourWorld.attach). FOUR draw calls for the whole port (ground, kit, detail, road), one StaticBody3D with
## the collision boxes of the sheds, stacks, cranes' legs, tanks, terminal and lighthouse, and the FERRY, a scenery passenger boat that sails a loop out of the basin through the channel and
## back to its landing every few minutes (an AnimatableBody3D so boats bump into it; it bobs on the real waves through WaterWorld.buoyancy). `QT_NO_HARBOUR=1` leaves the port out.
##   HarbourWorld.instance      the node
##   ferry_state                &"docked" | &"leaving" | &"sailing" | &"returning"
##   stats()                    {tris, boxes, ferry}

const DOCK_TIME := 60.0
const FERRY_SPEED := 6.5
const SHOW_DETAIL := 450.0
const SHOW_RANGE := 1450.0                       ## the port is drawn up to this distance (the perf budget counts every draw in the frustum: the start of the city, 1.5 km away, must not see it)
## The ferry's route (x, z): from the landing out through the channel, a wide loop in the bay and back; the loop closes on the first point.
const FERRY_PATH: Array[Vector2] = [Vector2(152.0, 1540.0), Vector2(125.0, 1650.0), Vector2(70.0, 1780.0), Vector2(0.0, 1950.0), Vector2(-120.0, 2100.0), Vector2(-300.0, 2160.0), Vector2(-420.0, 2040.0),
	Vector2(-330.0, 1900.0), Vector2(-120.0, 1820.0), Vector2(60.0, 1700.0), Vector2(134.0, 1600.0)]

static var instance: HarbourWorld = null

var tris := 0
var boxes := 0
var ferry: Node3D
var run: BoatRun                                    ## the boat run and the dock events (boat mission hooks)
var ferry_state: StringName = &"docked"
var ferry_u := 0.0                                 ## metres along the loop
var ferry_pos := Vector3.ZERO
var ferry_heading := 0.0
var _ferry_body: AnimatableBody3D
var _ferry_cs: CollisionShape3D
var _dock_t := 20.0
var _path_len := PackedFloat32Array()
var _total := 0.0
var _tick := 0.0


static func attach(parent: Node) -> HarbourWorld:
	var w := HarbourWorld.new()
	w.name = "HarbourWorld"
	parent.add_child(w)
	return w


func _ready() -> void:
	instance = self
	var L := Harbour.layout()
	_mesh("Ground", HarbourKit.ground(), null, SHOW_RANGE)
	_mesh("Kit", HarbourKit.kit(), null, SHOW_RANGE, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_mesh("Detail", HarbourKit.detail(), null, SHOW_DETAIL)
	var road := _mesh("Road", HarbourKit.road_mesh(), BridgeKit.road_material(&"road"), SHOW_RANGE)
	road.position.y = 0.0
	_collision(L)
	_build_ferry()
	run = BoatRun.new()
	run.name = "BoatRun"
	add_child(run)
	set_process(true)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _mesh(nm: String, m: ArrayMesh, mat: Material, vis_end: float, shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = m
	if mat != null:
		mi.material_override = mat
	mi.cast_shadow = shadow
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
		tris += BridgeWorld._tri_count(m)
	add_child(mi)
	return mi


func _collision(L: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	for bx: Dictionary in L["boxes"]:
		_add_box(body, bx["pos"], bx["size"])
	for px in Harbour.PIER_X:                                  # the pier decks (the ground under them is the sea: a deck box makes them walkable) and the pier heads
		_add_box(body, Vector3(px, Harbour.QUAY_Y - 0.5, (Harbour.PIER_Z0 + Harbour.PIER_Z1) * 0.5), Vector3(Harbour.PIER_W, 1.0, Harbour.PIER_Z1 - Harbour.PIER_Z0 + 1.0))
	add_child(body)


func _add_box(body: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)
	boxes += 1


# --- the ferry --------------------------------------------------------------------------------------------------------------------------

func _build_ferry() -> void:
	ferry = Node3D.new()
	ferry.name = "Ferry"
	var mi := MeshInstance3D.new()
	mi.mesh = HarbourKit.ferry()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.name = "Hull"
	ferry.add_child(mi)
	tris += BridgeWorld._tri_count(mi.mesh)
	_ferry_body = AnimatableBody3D.new()
	_ferry_body.name = "FerryBody"
	_ferry_body.collision_layer = Game.L_WORLD
	_ferry_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(9.0, 3.6, 38.0)
	cs.shape = bs
	cs.position = Vector3(0.0, 0.6, 0.0)
	cs.disabled = true                                  # solid only while the ferry is near the player (it never blocks the avenue at the origin before its first placement)
	_ferry_cs = cs
	_ferry_body.add_child(cs)
	add_child(ferry)
	add_child(_ferry_body)                              # a sibling that is moved itself: an AnimatableBody3D under a moving parent is pulled back to the origin by the physics server
	var run := 0.0
	_path_len.clear()
	_path_len.append(0.0)
	for i in range(1, FERRY_PATH.size() + 1):
		run += FERRY_PATH[i % FERRY_PATH.size()].distance_to(FERRY_PATH[i - 1])
		_path_len.append(run)
	_total = run
	ferry_u = 0.0
	_place_ferry(0.0)


## Position and heading on the loop at distance `u` (a straight interpolation between the route points, the heading smoothed over a few metres).
func path_at(u: float) -> Array:
	u = fposmod(u, _total)
	var n := FERRY_PATH.size()
	for i in n:
		if u <= _path_len[i + 1]:
			var a := FERRY_PATH[i]
			var b := FERRY_PATH[(i + 1) % n]
			var t := (u - _path_len[i]) / maxf(_path_len[i + 1] - _path_len[i], 0.01)
			return [a.lerp(b, t), (b - a).normalized()]
	return [FERRY_PATH[0], Vector2.DOWN]


func _place_ferry(dt: float) -> void:
	var pa := path_at(ferry_u)
	var p2: Vector2 = pa[0]
	var d2: Vector2 = pa[1]
	var target := atan2(-d2.x, -d2.y)
	ferry_heading = lerp_angle(ferry_heading, target, 1.0 - exp(-2.0 * dt)) if dt > 0.0 else target
	var bu := WaterWorld.buoyancy(Vector3(p2.x, 0.0, p2.y), ferry_heading, 12.0, 3.5)
	var y := float(bu["y"]) if bu["water"] else TerrainHeight.SEA_LEVEL
	ferry_pos = Vector3(p2.x, y - 0.5, p2.y)
	ferry.transform = Transform3D(Basis(Vector3.UP, ferry_heading) * Basis(Vector3.RIGHT, float(bu["pitch"]) * 0.6) * Basis(Vector3.FORWARD, -float(bu["roll"]) * 0.6), ferry_pos)
	_ferry_body.transform = ferry.transform


func _process(delta: float) -> void:
	_tick += delta
	var ppos := Vector3.INF
	var p := Game.player as Node3D
	if is_instance_valid(p):
		ppos = p.global_position
	var near := ppos.is_finite() and Vector2(ppos.x - 100.0, ppos.z - 1650.0).length() < 1600.0
	ferry.visible = near
	if _ferry_cs.disabled == near:
		_ferry_cs.set_deferred(&"disabled", not near)
	if not near:
		return                                         # the ferry only sails where somebody can see it
	match ferry_state:
		&"docked":
			_dock_t -= delta
			if _dock_t <= 0.0:
				ferry_state = &"leaving"
		&"leaving", &"sailing", &"returning":
			ferry_u += FERRY_SPEED * delta
			if ferry_u >= _total - 1.0:
				ferry_u = 0.0
				ferry_state = &"docked"
				_dock_t = DOCK_TIME
			elif ferry_u > 60.0:
				ferry_state = &"sailing" if ferry_u < _total - 120.0 else &"returning"
	_place_ferry(delta)
	if ferry_state != &"docked" and _tick > 0.12:
		_tick = 0.0
		var wake := ferry_pos + Vector3(sin(ferry_heading), 0.0, cos(ferry_heading)) * 17.0
		FX.burst(Vector3(wake.x, TerrainHeight.SEA_LEVEL + 0.15, wake.z), Color(0.9, 0.96, 1.0, 0.7), 2, 2.0, 1.0, 2.5, 2.0)


func stats() -> Dictionary:
	return {"tris": tris, "boxes": boxes, "ferry": ferry_state, "ferry_u": ferry_u}
