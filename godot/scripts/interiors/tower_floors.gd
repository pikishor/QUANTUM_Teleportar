class_name TowerFloors
extends Node3D
## w121-floors (owner round 7: "building detail and interiors with stairs"): the tall city buildings (class "block", core districts, LOT >= MIN_H m) can be WALKED INTO from the
## street, with no loading screen: a street door on the street face the USE door (city_doors.gd) does not use. When the hero comes within NEAR m of such a building its own
## collider boxes (city.gd "Building<lot>_<k>") are switched off and this node builds the inside IN PLACE, the same size as the outside:
##   outer walls 0.35 m inside the facade with window holes on the facade shader's own grid (building_core.gdshaderinc: ground floor GROUND_H, floors fh = body / nfl, columns by
##   style), floor slabs at the facade's floor lines, a switchback STAIRWELL at the back wall (real steps, ramp colliders under them, no teleport) from the street floor to the roof,
##   a stair house with a door on the roof (roof height = lot.h: the same roof the zip / swing reach), and rooms per kind (OFFICE desks, APARTMENTS rooms with beds, HOTEL TOWER
##   lounges) built only for the hero's floor and the floors next to it (rebuilt when he changes floor, freed after).
## When he is more than FAR m away (and not inside) everything is freed and the building's colliders come back. One MeshInstance3D (one draw call) and one StaticBody3D.
## Frame of a tower: t = along the back wall, n = the street door's outward normal; (u, v) are metres from the back corner (u along t, v toward the street door).
## For w121-lifts: `current()` describes the open tower (levels, shaft, LIFT_BAY: a free 2.4 x 2.6 m bay beside the stairwell on every floor).

const SHADER := preload("res://assets/shaders/tower_floors.gdshader")
const MIN_H := 24.0
const NEAR := 30.0
const FAR := 42.0
const IN := 0.35                 ## inner wall plane, metres inside the facade
const WALL_T := 0.3
const SLAB := 0.3
const GROUND_H := 5.0            ## the facade shader's numbers (building_core.gdshaderinc)
const FLOOR_H := 3.5
const PARAPET_H := 1.2
const LANE := 1.3                ## stairwell: two lanes of LANE m, a floor landing of LAND m, flights of RUN m, a mid landing of LAND m
const LAND := 1.4
const RUN := 5.0
const SHAFT_L := LAND + RUN + LAND
const SHAFT_W := 2.0 * LANE
const LIFT_BAY := Rect2(SHAFT_L, 0.0, 2.4, SHAFT_W)      ## (u, v) rect left free on every floor for w121-lifts
const DOOR_W := 2.0
const SW_T := 0.35                 ## stairwell wall thickness (thin walls let a running capsule through at a turn)
const DOOR_H := 2.8
const STEP_MAX := 0.19
const GLOW_A := 2.0               ## colour alpha that marks a light panel / screen (survives the face shading factors)
const RAMP_T := 0.9               ## ramp collider thickness (solid under the treads)
const RAMP_EXT := 0.6
const HOUSE_H := 2.7
const KINDS := {&"office": "OFFICE TOWER", &"apartment": "APARTMENTS", &"hotel": "HOTEL TOWER"}

static var enabled := true       ## FLOORS_OLD=1 in the tests: the wave 120 buildings (solid boxes, USE door only)
static var instance: TowerFloors
static var open_lot := -1        ## lot index of the open tower (-1: none)
static var builds := 0           ## how many times a tower was opened (tests)

var towers: Array[Dictionary] = []     ## candidates: {lot, b, kind, face, n, t}
var _cur: Dictionary = {}
var _mesh: MeshInstance3D
var _body: StaticBody3D
var _room_body: StaticBody3D
var _mat: ShaderMaterial
var _scan := 0.0
var _floor := -99
var _levels := PackedFloat32Array()
# mesh scratch
var _v := PackedVector3Array()
var _nm := PackedVector3Array()
var _c := PackedColorArray()


func _ready() -> void:
	instance = self
	name = "TowerFloors"
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER


func _exit_tree() -> void:
	close()
	if instance == self:
		instance = null


## OFFICE behind ribbon / curtain glass, HOTEL TOWER behind fins and half of the punched facades, APARTMENTS behind brick and the other punched ones.
static func kind_of(style: int, idx := 0) -> StringName:
	if style == 3 or (style == 0 and fposmod(sin(float(idx) * 12.9898 + 77.0 * 78.233) * 43758.5453, 1.0) < 0.5):
		return &"hotel"
	if style == 1 or style == 2:
		return &"office"
	if style == 3:
		return &"hotel"
	return &"apartment"


func _collect() -> void:
	towers.clear()
	var city = Game.world
	if city == null or not is_instance_valid(city) or not (&"building_data" in city):
		return
	var door_face := {}
	for d: Dictionary in city.doors:
		var nn: Vector3 = d["normal"]
		door_face[int(d["id"])] = 0 if nn.x > 0.5 else (1 if nn.x < -0.5 else (2 if nn.z > 0.5 else 3))
	for b in city.building_data:
		var lot: CityLayout.Lot = b.lot
		if b.cls != &"block" or lot.h < MIN_H or minf(lot.w, lot.d) < SHAFT_L + LIFT_BAY.size.x + 1.5 or not CityLayout.is_core_block(lot.block_i, lot.block_j):
			continue
		var bx := -CityLayout.HALF + (lot.block_i + 0.5) * CityLayout.PITCH
		var bz := -CityLayout.HALF + (lot.block_j + 0.5) * CityLayout.PITCH
		var faces: Array[int] = [0 if lot.cx > bx else 1, 2 if lot.cz > bz else 3]
		var face: int = faces[1] if int(door_face.get(lot.index, -1)) == faces[0] else faces[0]
		var n: Vector3 = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD][face]
		var t := Vector3(n.z, 0.0, -n.x)
		if t.x + t.z < 0.0:
			t = -t
		towers.append({"lot": lot, "b": b, "kind": kind_of(b.style, lot.index), "face": face, "n": n, "t": t})


## The tower whose street door is nearest to `p` (tests and the probe): {} when none.
func nearest(p: Vector3) -> Dictionary:
	if towers.is_empty():
		_collect()
	var best: Dictionary = {}
	var bd := INF
	for tw in towers:
		var d := door_pos(tw).distance_to(Vector3(p.x, 0.0, p.z))
		if d < bd:
			bd = d
			best = tw
	return best


# --- frame ---------------------------------------------------------------------------------------------------------------

static func _half_t(tw: Dictionary) -> float:
	var lot: CityLayout.Lot = tw["lot"]
	return (lot.w if absf((tw["t"] as Vector3).x) > 0.5 else lot.d) * 0.5


static func _half_n(tw: Dictionary) -> float:
	var lot: CityLayout.Lot = tw["lot"]
	return (lot.w if absf((tw["n"] as Vector3).x) > 0.5 else lot.d) * 0.5


## World point of (u, v) at height y.
static func at(tw: Dictionary, u: float, v: float, y := 0.0) -> Vector3:
	var lot: CityLayout.Lot = tw["lot"]
	var t: Vector3 = tw["t"]
	var n: Vector3 = tw["n"]
	return Vector3(lot.cx, y, lot.cz) + t * (-_half_t(tw) + IN + u) + n * (-_half_n(tw) + IN + v)


static func inner_u(tw: Dictionary) -> float:
	return 2.0 * (_half_t(tw) - IN)


static func inner_v(tw: Dictionary) -> float:
	return 2.0 * (_half_n(tw) - IN)


## The street door: the sidewalk point in front of it (y 0).
static func door_pos(tw: Dictionary, out := 1.3) -> Vector3:
	return at(tw, inner_u(tw) * 0.5, inner_v(tw) + IN + out)


## Floor levels: [0 (street), floor 1, ..., floor nfl, roof]. Same numbers as the facade shader, so slabs sit at the facade's floor lines.
static func levels_of(lot: CityLayout.Lot) -> PackedFloat32Array:
	var gh := 4.6 if lot.h < 20.0 else GROUND_H
	var body := maxf(lot.h - gh - PARAPET_H, FLOOR_H)
	var nfl := maxi(1, int(floor(body / FLOOR_H + 0.5)))
	var fh := body / nfl
	var out := PackedFloat32Array([0.0])
	for k in nfl:
		out.append(gh + k * fh)
	out.append(lot.h)
	return out


## Which level the height y stands on (0 street ... size-1 roof).
func floor_of(y: float) -> int:
	var k := 0
	for i in _levels.size():
		if y >= _levels[i] - 0.6:
			k = i
	return k


## The open tower for other modules (w121-lifts): {} when none, else {lot, kind, name, levels, floor, shaft: world points of the stair landing per level, lift_bay: world rect corners}.
static func current() -> Dictionary:
	if instance == null or instance._cur.is_empty():
		return {}
	var tw: Dictionary = instance._cur
	var land: Array = []
	for y in instance._levels:
		land.append(at(tw, LAND * 0.5, SHAFT_W + 0.6, y))
	return {"lot": (tw["lot"] as CityLayout.Lot).index, "kind": tw["kind"], "name": KINDS[tw["kind"]], "levels": instance._levels, "floor": instance._floor,
		"landing": land, "lift_bay": [at(tw, LIFT_BAY.position.x, 0.0), at(tw, LIFT_BAY.end.x, LIFT_BAY.end.y)], "door": door_pos(tw), "frame": tw}


## Is p inside the open tower's walls (between the street and the roof)?
static func inside(p: Vector3) -> bool:
	if instance == null or instance._cur.is_empty():
		return false
	var tw: Dictionary = instance._cur
	var lot: CityLayout.Lot = tw["lot"]
	return p.y > -1.0 and p.y < lot.h - 0.2 and absf(p.x - lot.cx) < lot.w * 0.5 - 0.05 and absf(p.z - lot.cz) < lot.d * 0.5 - 0.05


## Walk route (world points) from the street door up the stairs: [door in, lobby, landing 0, A top, B top = landing 1, ...] up to `level`; the last point steps out
## through the landing's door (or the roof door). For tests and bots: every point is reached by walking.
func route(level: int) -> Array[Vector3]:
	var tw: Dictionary = _cur
	var out: Array[Vector3] = []
	if tw.is_empty():
		return out
	var iu := inner_u(tw)
	var iv := inner_v(tw)
	out.append(at(tw, iu * 0.5, iv - 1.0))
	out.append(at(tw, LAND * 0.5, SHAFT_W + 1.2))
	for k in level:
		var y0 := _levels[k]
		var y1 := _levels[k + 1]
		out.append(at(tw, 0.8, LANE + 0.3, y0))
		out.append(at(tw, LAND + 0.8, SHAFT_W - LANE * 0.5, y0 + 0.3))
		out.append(at(tw, LAND + RUN + LAND * 0.5, SHAFT_W - LANE * 0.5, (y0 + y1) * 0.5))
		out.append(at(tw, LAND + RUN + LAND * 0.5, LANE * 0.5, (y0 + y1) * 0.5))
		out.append(at(tw, LAND * 0.5, LANE * 0.5, y1))
	out.append(at(tw, LAND * 0.5, SHAFT_W + 1.2, _levels[level]))
	return out


# --- open / close --------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = 0.2
	var p := Game.player
	if not enabled or p == null or not is_instance_valid(p) or InteriorGameplay.active:
		if not _cur.is_empty():
			close()
		return
	var pp: Vector3 = p.global_position
	if towers.is_empty():
		_collect()
	# the tower nearest to the hero (distance to its footprint); a neighbour takes over only when it is clearly nearer
	var best: Dictionary = {}
	var bd := INF
	for tw in towers:
		var lot: CityLayout.Lot = tw["lot"]
		var d := _rect_dist(lot.rect, pp)
		if d < bd:
			bd = d
			best = tw
	if not _cur.is_empty():
		var lot: CityLayout.Lot = _cur["lot"]
		var dc := _rect_dist(lot.rect, pp)
		var keep := inside(pp) or (dc < FAR and pp.y < lot.h + 30.0 and not (best != _cur and bd + 3.0 < dc and bd < NEAR))
		if keep:
			var k := floor_of(pp.y) if inside(pp) or pp.y > lot.h - 1.0 else 0
			if k != _floor:
				_floor = k
				_build_mesh()
				_build_rooms()
			return
		close()
	if not best.is_empty() and bd < NEAR and pp.y < (best["lot"] as CityLayout.Lot).h + 25.0:
		open(best)


static func _rect_dist(r: Rect2, p: Vector3) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - p.z, p.z - r.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


func open(tw: Dictionary) -> void:
	close()
	_cur = tw
	var lot: CityLayout.Lot = tw["lot"]
	open_lot = lot.index
	builds += 1
	_levels = levels_of(lot)
	_floor = floor_of(Game.player.global_position.y) if Game.player != null and inside(Game.player.global_position) else 0
	_set_city_boxes(lot.index, true)
	_body = StaticBody3D.new()
	_body.name = "TowerShell"
	_body.collision_layer = Game.L_WORLD
	_body.collision_mask = 0
	add_child(_body)
	_room_body = StaticBody3D.new()
	_room_body.name = "TowerRooms"
	_room_body.collision_layer = Game.L_WORLD
	_room_body.collision_mask = 0
	add_child(_room_body)
	_mesh = MeshInstance3D.new()
	_mesh.name = "TowerMesh"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.material_override = _mat
	add_child(_mesh)
	_build_shell()
	_build_mesh()
	_build_rooms()


func close() -> void:
	if _cur.is_empty():
		return
	_set_city_boxes((_cur["lot"] as CityLayout.Lot).index, false)
	for n in [_mesh, _body, _room_body]:
		if n != null and is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_mesh = null
	_body = null
	_room_body = null
	_cur = {}
	open_lot = -1
	_floor = -99


func _set_city_boxes(idx: int, off: bool) -> void:
	var city = Game.world
	if city == null or not is_instance_valid(city) or city.get(&"collision_body") == null:
		return
	var cb: Node = city.collision_body
	var k := 0
	while true:
		var cs := cb.get_node_or_null("Building%d_%d" % [idx, k]) as CollisionShape3D
		if cs == null:
			break
		cs.set_deferred(&"disabled", off)
		k += 1


# --- colliders -----------------------------------------------------------------------------------------------------------

## A box between (u0, v0, y0) and (u1, v1, y1) of the frame.
func _box(body: StaticBody3D, u0: float, v0: float, y0: float, u1: float, v1: float, y1: float) -> void:
	var a := at(_cur, u0, v0, y0)
	var b := at(_cur, u1, v1, y1)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(absf(b.x - a.x), absf(b.y - a.y), absf(b.z - a.z)).max(Vector3(0.02, 0.02, 0.02))
	cs.shape = sh
	cs.position = (a + b) * 0.5
	body.add_child(cs)


## A ramp along u from (u0, y0) to (u1, y1) over the lane v0..v1 (its top runs half a step over the step noses, so the feet stand on the treads).
func _ramp(u0: float, y0: float, u1: float, y1: float, v0: float, v1: float) -> void:
	var a := at(_cur, u0, (v0 + v1) * 0.5, y0)
	var b := at(_cur, u1, (v0 + v1) * 0.5, y1)
	var d := b - a
	var x := d.normalized()
	var lo := a if y0 < y1 else b
	var hi := b if y0 < y1 else a
	var dn := (hi - lo).normalized()
	lo -= dn * RAMP_EXT                 # the foot of the ramp runs on under the floor: no lip to catch the feet, no gap to slip under
	hi += dn * 0.05
	var len := lo.distance_to(hi)
	var up := (Vector3.UP - x * x.y).normalized()
	var side := x.cross(up)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(len, RAMP_T, v1 - v0 - 0.02)
	cs.shape = sh
	var lift := absf(y1 - y0) / maxf(1.0, ceilf(absf(y1 - y0) / STEP_MAX)) * 0.5
	cs.transform = Transform3D(Basis(x, up, side), (lo + hi) * 0.5 - up * RAMP_T * 0.5 + Vector3.UP * lift)
	_body.add_child(cs)


## A rect (u0..u1, v0..v1) minus the stair hole: up to four rects.
func _minus_hole(u0: float, v0: float, u1: float, v1: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var hu0 := LAND
	var hu1 := SHAFT_L
	var hv1 := SHAFT_W
	var bu1 := LIFT_BAY.end.x if TowerLift.instance != null else hu1      # w121-lifts: the LIFT_BAY is a hole too (the lift shaft runs through every slab; TowerLift fences it)
	out.append(Rect2(bu1, v0, u1 - bu1, v1 - v0))                  # beyond the hole (and the lift bay) along u
	out.append(Rect2(u0, hv1, bu1 - u0, v1 - hv1))                 # in front of the hole, the lift bay and the landing
	out.append(Rect2(u0, v0, hu0 - u0, hv1 - v0))                  # the landing
	return out


func _build_shell() -> void:
	var tw := _cur
	var lot: CityLayout.Lot = tw["lot"]
	var iu := inner_u(tw)
	var iv := inner_v(tw)
	var H := lot.h
	var top := H - PARAPET_H
	# outer walls (WALL_T thick, outside the inner plane), the street door a gap in the n wall
	var du := iu * 0.5
	_box(_body, -WALL_T, -WALL_T, 0.0, 0.0, iv + WALL_T, top)                  # u = 0 side
	_box(_body, iu, -WALL_T, 0.0, iu + WALL_T, iv + WALL_T, top)               # far side
	_box(_body, 0.0, -WALL_T, 0.0, iu, 0.0, top)                               # back wall
	_box(_body, 0.0, iv, 0.0, du - DOOR_W * 0.5, iv + WALL_T, top)             # street wall, left of the door
	_box(_body, du + DOOR_W * 0.5, iv, 0.0, iu, iv + WALL_T, top)              # right of the door
	_box(_body, du - DOOR_W * 0.5, iv, DOOR_H, du + DOOR_W * 0.5, iv + WALL_T, top)
	# slabs of floors 1..nfl and the roof (minus the stair hole)
	for k in range(1, _levels.size()):
		var y := _levels[k]
		var y0 := y - SLAB if k < _levels.size() - 1 else top
		for r in _minus_hole(-WALL_T, -WALL_T, iu + WALL_T, iv + WALL_T):
			_box(_body, r.position.x, r.position.y, y0, r.end.x, r.end.y, y)
	# the stairwell: inner long wall with a doorway on every level, end wall, lane divider, mid landings, flights
	for k in _levels.size() - 1:
		var y0 := _levels[k]
		var y1 := _levels[k + 1]
		var ym := (y0 + y1) * 0.5
		_box(_body, LAND, SHAFT_W, y0, SHAFT_L, SHAFT_W + SW_T, y1)
		_box(_body, 0.0, SHAFT_W, y0 + DOOR_H, LAND, SHAFT_W + SW_T, y1)
		_box(_body, LAND, LANE - 0.06, y0, LAND + RUN, LANE + 0.06, y1)
		_box(_body, LAND + RUN, 0.0, ym - SLAB, SHAFT_L, SHAFT_W, ym)
		_ramp(LAND - 0.05, y0, LAND + RUN + 0.05, ym, LANE, SHAFT_W)
		_ramp(LAND + RUN + 0.05, ym, LAND - 0.05, y1, 0.0, LANE)
	_box(_body, SHAFT_L, 0.0, 0.0, SHAFT_L + SW_T, SHAFT_W, top)
	_box(_body, LAND, 0.0, 0.0, LAND + RUN, LANE - 0.06, (_levels[0] + _levels[1]) * 0.5 - 0.25)      # street floor: solid under the second flight (no crawling under the stairs)
	# stair house on the roof: walls round the shaft, a door on the landing side, a lid
	_box(_body, -WALL_T, -WALL_T, H, 0.0, SHAFT_W + SW_T, H + HOUSE_H)
	_box(_body, -WALL_T, -WALL_T, H, SHAFT_L + SW_T, 0.0, H + HOUSE_H)
	_box(_body, SHAFT_L, 0.0, H, SHAFT_L + SW_T, SHAFT_W + SW_T, H + HOUSE_H)
	_box(_body, LAND, SHAFT_W, H, SHAFT_L + SW_T, SHAFT_W + SW_T, H + HOUSE_H)
	_box(_body, 0.0, SHAFT_W, H + DOOR_H, LAND, SHAFT_W + SW_T, H + HOUSE_H)
	_box(_body, -WALL_T, -WALL_T, H + HOUSE_H, SHAFT_L + SW_T, SHAFT_W + SW_T, H + HOUSE_H + 0.2)


## Rooms and furniture colliders of the floors the hero can see (his floor and the next ones).
func _build_rooms() -> void:
	if _room_body == null:
		return
	for c in _room_body.get_children():
		_room_body.remove_child(c)
		c.queue_free()
	for k in _room_floors():
		for b: Array in _room_boxes(k):
			if b[6]:
				_box(_room_body, b[0], b[1], b[2], b[3], b[4], b[5])


func _room_floors() -> Array[int]:
	var out: Array[int] = []
	for k in [_floor - 1, _floor, _floor + 1]:
		if k >= 0 and k < _levels.size() - 1:
			out.append(k)
	return out


## Boxes of a floor's rooms and furniture: [u0, v0, y0, u1, v1, y1, solid, colour, glow].
func _room_boxes(k: int) -> Array:
	var tw := _cur
	var kind: StringName = tw["kind"]
	var iu := inner_u(tw)
	var iv := inner_v(tw)
	var y := _levels[k]
	var ceil_y := _levels[k + 1] - SLAB
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = (tw["lot"] as CityLayout.Lot).index * 131 + k
	var wall_c := Color(0.62, 0.6, 0.56) if kind == &"office" else (Color(0.66, 0.55, 0.45) if kind == &"apartment" else Color(0.42, 0.4, 0.5))
	var wood := Color(0.42, 0.28, 0.17)
	if k == 0:
		# lobby: a reception desk beside the door, planters, a light bench
		var du := iu * 0.5
		out.append([du + 2.2, iv - 4.2, y, du + 4.6, iv - 3.4, y + 1.05, true, wood, false])
		out.append([du + 2.3, iv - 4.15, y + 1.05, du + 4.5, iv - 3.45, y + 1.12, false, Color(0.9, 0.85, 0.7), true])
		out.append([1.0, iv - 1.5, y, 1.8, iv - 0.7, y + 0.9, true, Color(0.18, 0.4, 0.2), false])
		out.append([iu - 1.8, iv - 1.5, y, iu - 1.0, iv - 0.7, y + 0.9, true, Color(0.18, 0.4, 0.2), false])
		out.append([du - 5.0, SHAFT_W + 3.5, y, du + 1.0, SHAFT_W + 4.1, y + 0.45, true, Color(0.25, 0.25, 0.3), false])
		return out
	# rooms along the street side: a corridor wall with a door gap per room, separators
	var band := minf(7.0, iv - SHAFT_W - 5.0)
	var cv := iv - band
	var nroom := clampi(int(iu / 6.5), 2, 5)
	var rw := iu / nroom
	for i in nroom:
		var u0 := i * rw
		var gap := u0 + rw * 0.5
		out.append([u0, cv - 0.08, y, gap - 0.6, cv + 0.08, ceil_y, true, wall_c, false])
		out.append([gap + 0.6, cv - 0.08, y, u0 + rw, cv + 0.08, ceil_y, true, wall_c, false])
		out.append([gap - 0.6, cv - 0.08, y + DOOR_H - 0.6, gap + 0.6, cv + 0.08, ceil_y, true, wall_c, false])
		if i > 0:
			out.append([u0 - 0.08, cv, y, u0 + 0.08, iv, ceil_y, true, wall_c, false])
		# room furniture against the street wall (away from the door gap)
		match kind:
			&"office":
				out.append([u0 + 0.6, iv - 1.4, y, u0 + rw - 0.6, iv - 0.6, y + 0.75, true, wood, false])
				out.append([u0 + rw * 0.5 - 0.4, iv - 1.2, y + 0.75, u0 + rw * 0.5 + 0.2, iv - 1.15, y + 1.2, false, Color(0.5, 0.8, 1.0), true])
			&"apartment":
				out.append([u0 + 0.5, iv - 2.4, y, u0 + 2.1, iv - 0.3, y + 0.55, true, Color(0.75, 0.72, 0.8), false])
				out.append([u0 + rw - 1.5, iv - 1.0, y, u0 + rw - 0.4, iv - 0.4, y + 1.9, true, wood, false])
			_:
				out.append([u0 + 0.6, iv - 2.2, y, u0 + 2.4, iv - 0.5, y + 0.5, true, Color(0.55, 0.15, 0.2), false])
				out.append([u0 + rw - 1.2, iv - 1.2, y, u0 + rw - 0.4, iv - 0.4, y + 0.75, true, wood, false])
	# the open floor between the stairwell and the rooms
	var v0 := SHAFT_W + 2.4
	var v1 := cv - 1.6
	var u_from := SHAFT_L + LIFT_BAY.size.x + 1.4
	var gu := u_from
	while gu + 1.6 < iu - 1.0 and v1 - v0 > 1.0:
		var gv := v0
		while gv + 0.8 < v1:
			match kind:
				&"office":
					out.append([gu, gv, y, gu + 1.6, gv + 0.8, y + 0.75, true, Color(0.75, 0.74, 0.7), false])
					out.append([gu + 0.5, gv + 0.15, y + 0.75, gu + 1.1, gv + 0.2, y + 1.15, false, Color(0.45, 0.75, 1.0), true])
				&"apartment":
					if rng.randf() < 0.5:
						out.append([gu, gv, y, gu + 2.0, gv + 0.8, y + 0.7, true, Color(0.3, 0.35, 0.5), false])
				_:
					out.append([gu + 0.3, gv, y, gu + 1.2, gv + 0.9, y + 0.72, true, Color(0.2, 0.18, 0.16), false])
			gv += 3.2
		gu += 3.6
	return out


# --- mesh ----------------------------------------------------------------------------------------------------------------

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var nn := (b - a).cross(c - a).normalized()
	col.a = 1.0 if col.a > GLOW_A * 0.6 else 0.0      # only colours marked GLOW_A light up (Color() defaults to alpha 1)
	_v.append_array([a, c, b, a, d, c])          # Godot: clockwise is the front face
	for i in 6:
		_nm.append(nn)
		_c.append(col)


## A face of the frame-aligned box, seen from outside (the six faces when `faces` is 63; bits: 1 -u, 2 +u, 4 -v, 8 +v, 16 bottom, 32 top).
func _mbox(u0: float, v0: float, y0: float, u1: float, v1: float, y1: float, col: Color, faces := 63) -> void:
	var p := func(u: float, v: float, y: float) -> Vector3: return at(_cur, u, v, y)
	var flip := _flip()
	var q := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, cc: Color) -> void:
		if flip:
			_quad(a, d, c, b, cc)
		else:
			_quad(a, b, c, d, cc)
	if faces & 32:
		q.call(p.call(u0, v0, y1), p.call(u0, v1, y1), p.call(u1, v1, y1), p.call(u1, v0, y1), col)
	if faces & 16:
		q.call(p.call(u0, v0, y0), p.call(u1, v0, y0), p.call(u1, v1, y0), p.call(u0, v1, y0), col * 0.7)
	if faces & 1:
		q.call(p.call(u0, v0, y0), p.call(u0, v1, y0), p.call(u0, v1, y1), p.call(u0, v0, y1), col * 0.85)
	if faces & 2:
		q.call(p.call(u1, v0, y0), p.call(u1, v0, y1), p.call(u1, v1, y1), p.call(u1, v1, y0), col * 0.85)
	if faces & 4:
		q.call(p.call(u0, v0, y0), p.call(u0, v0, y1), p.call(u1, v0, y1), p.call(u1, v0, y0), col * 0.92)
	if faces & 8:
		q.call(p.call(u0, v1, y0), p.call(u1, v1, y0), p.call(u1, v1, y1), p.call(u0, v1, y1), col * 0.92)


## The frame (t, n, up) is left-handed for half of the faces: then every quad winds the other way.
func _flip() -> bool:
	var t: Vector3 = _cur["t"]
	var n: Vector3 = _cur["n"]
	return t.cross(n).y > 0.0


## A wall plane at v = const (normal +v when `face_plus`) or u = const, with rectangular holes: cut into cells, holes left open. `holes`: Array of Rect2 (s, y) in the wall's own s.
func _wall(fixed_u: bool, at_c: float, s0: float, s1: float, y0: float, y1: float, holes: Array, plus: bool, col: Color) -> void:
	var ss := [s0, s1]
	var ys := [y0, y1]
	for h: Rect2 in holes:
		ss.append(clampf(h.position.x, s0, s1))
		ss.append(clampf(h.end.x, s0, s1))
		ys.append(clampf(h.position.y, y0, y1))
		ys.append(clampf(h.end.y, y0, y1))
	ss.sort()
	ys.sort()
	for i in ss.size() - 1:
		var a: float = ss[i]
		var b: float = ss[i + 1]
		if b - a < 0.005:
			continue
		for j in ys.size() - 1:
			var c: float = ys[j]
			var d: float = ys[j + 1]
			if d - c < 0.005:
				continue
			var m := Vector2((a + b) * 0.5, (c + d) * 0.5)
			var open := false
			for h: Rect2 in holes:
				if h.has_point(m):
					open = true
					break
			if open:
				continue
			if fixed_u:
				_mbox(at_c, a, c, at_c, b, d, col, 2 if plus else 1)
			else:
				_mbox(a, at_c, c, b, at_c, d, col, 8 if plus else 4)


## Window rects (s along this wall from its inner start, y) of the facade face whose inner plane is this wall, on the facade shader's grid.
func _windows(fw: float, s_off: float, k: int, style: int) -> Array:
	var out: Array = []
	var col_w := 2.4 if style == 4 else (1.5 if style == 3 else (1.7 if style == 2 else (2.1 if style == 1 else 2.6)))
	var w0: Vector2 = [Vector2(0.18, 0.22), Vector2(0.03, 0.26), Vector2(0.05, 0.10), Vector2(0.30, 0.08), Vector2(0.28, 0.24)][clampi(style, 0, 4)]
	var w1: Vector2 = [Vector2(0.82, 0.80), Vector2(0.97, 0.76), Vector2(0.95, 0.90), Vector2(0.70, 0.93), Vector2(0.72, 0.78)][clampi(style, 0, 4)]
	var ncol := maxf(2.0, floorf(fw / col_w + 0.5))
	var cw := fw / ncol
	var ya: float
	var yb: float
	if k == 0:
		ya = 0.9
		yb = _levels[1] - 1.3
	else:
		var fh := _levels[k + 1] - _levels[k] if k + 1 < _levels.size() - 1 else (_levels[k + 1] - PARAPET_H - _levels[k])
		ya = _levels[k] + fh * w0.y
		yb = _levels[k] + fh * w1.y
	for ci in int(ncol):
		out.append(Rect2(ci * cw + cw * w0.x - s_off, ya, cw * (w1.x - w0.x), yb - ya))
	return out


func _build_mesh() -> void:
	if _mesh == null:
		return
	_v.clear()
	_nm.clear()
	_c.clear()
	var tw := _cur
	var lot: CityLayout.Lot = tw["lot"]
	var kind: StringName = tw["kind"]
	var style: int = tw["b"].style
	var iu := inner_u(tw)
	var iv := inner_v(tw)
	var top := lot.h - PARAPET_H
	var fu := iu + 2.0 * IN               # facade widths along u and along v
	var fv := iv + 2.0 * IN
	var wall_c := Color(0.72, 0.7, 0.66) if kind == &"office" else (Color(0.74, 0.62, 0.5) if kind == &"apartment" else Color(0.48, 0.46, 0.58))
	var floor_c := Color(0.36, 0.36, 0.38) if kind == &"office" else (Color(0.34, 0.27, 0.2) if kind == &"apartment" else Color(0.3, 0.12, 0.14))
	var ceil_c := Color(0.82, 0.82, 0.8)
	var shaft_c := Color(0.55, 0.56, 0.58)
	var step_c := Color(0.5, 0.5, 0.52)
	var du := iu * 0.5
	var near := _room_floors()
	for k in _levels.size() - 1:
		var y0 := _levels[k]
		var y1 := (_levels[k + 1] - SLAB) if k + 1 < _levels.size() - 1 else top
		var shown := near.has(k)
		# outer walls with the facade's windows (every floor: they enclose the stairwell too)
		var hz: Array = _windows(fu, IN, k, style)
		var hn: Array = _windows(fu, IN, k, style)
		if k == 0:
			hn = hn.filter(func(r: Rect2) -> bool: return r.end.x < du - DOOR_W * 0.5 - 0.2 or r.position.x > du + DOOR_W * 0.5 + 0.2)
			hn.append(Rect2(du - DOOR_W * 0.5, 0.0, DOOR_W, DOOR_H))
		_wall(false, 0.0, 0.0, iu, y0, y1, hz, true, wall_c)                   # back wall (seen from +v)
		_wall(false, iv, 0.0, iu, y0, y1, hn, false, wall_c)                   # street wall
		_wall(true, 0.0, 0.0, iv, y0, y1, _windows(fv, IN, k, style), true, wall_c)
		_wall(true, iu, 0.0, iv, y0, y1, _windows(fv, IN, k, style), false, wall_c)
		# floor and ceiling (minus the stair hole); the street floor is a lobby floor
		var y_top := _levels[k + 1] - SLAB if k + 1 < _levels.size() - 1 else top
		for r in (_minus_hole(0.0, 0.0, iu, iv) if k > 0 else [Rect2(0.0, 0.0, iu, iv)]):
			_mbox(r.position.x, r.position.y, y0 - 0.02, r.end.x, r.end.y, y0 + (0.015 if k == 0 else 0.0), floor_c if k > 0 else Color(0.5, 0.48, 0.45), 32)
		for r in _minus_hole(0.0, 0.0, iu, iv):
			_mbox(r.position.x, r.position.y, y_top, r.end.x, r.end.y, y_top + 0.02, ceil_c, 16)
		# light panels on the ceiling
		if shown:
			var gu := 3.0
			while gu < iu - 1.0:
				var gv := SHAFT_W + 2.0
				while gv < iv - 1.0:
					_mbox(gu - 0.6, gv - 0.3, y_top - 0.03, gu + 0.6, gv + 0.3, y_top - 0.01, Color(1.0, 0.95, 0.85, GLOW_A), 16)
					gv += 5.0
				gu += 5.0
			for b: Array in _room_boxes(k):
				var col: Color = b[7]
				col.a = GLOW_A if b[8] else 0.0
				_mbox(b[0], b[1], b[2], b[3], b[4], b[5], col)
		# the stairwell of this level: walls, lane divider, mid landing, steps
		var yn := _levels[k + 1]
		var ym := (y0 + yn) * 0.5
		_wall(false, SHAFT_W, LAND, SHAFT_L, y0, yn, [], false, shaft_c)            # inside of the long wall
		_wall(false, SHAFT_W + SW_T, LAND, SHAFT_L, y0, yn, [], true, wall_c)       # its room side
		_mbox(0.0, SHAFT_W, y0 + DOOR_H, LAND, SHAFT_W + SW_T, yn, shaft_c, 4 | 8 | 16)
		_mbox(LAND, LANE - 0.06, y0, LAND + RUN, LANE + 0.06, ym + 1.0, shaft_c, 4 | 8 | 1 | 32)
		_mbox(LAND + RUN, 0.0, ym - SLAB, SHAFT_L, SHAFT_W, ym, step_c, 32 | 16 | 1)
		_wall(true, SHAFT_L, 0.0, SHAFT_W, y0, yn, [], false, shaft_c)
		_wall(true, SHAFT_L + SW_T, 0.0, SHAFT_W, y0, yn, [], true, wall_c)
		_steps(LAND, y0, LAND + RUN, ym, LANE, SHAFT_W, step_c)
		_steps(LAND + RUN, ym, LAND, yn, 0.0, LANE, step_c)
		_mbox(0.2, SHAFT_W - 0.02, y0 + 2.2, 0.9, SHAFT_W, y0 + 2.45, Color(0.1, 1.0, 0.4, GLOW_A), 4)      # the green floor sign over the stair door
	_mbox(LAND, 0.0, 0.0, LAND + RUN, LANE - 0.06, (_levels[0] + _levels[1]) * 0.5 - 0.25, shaft_c, 1 | 2 | 4 | 8)
	# the roof: stair house (inside and outside) with its door; the street door outside: a dark doorway with a lit lintel
	var H := lot.h
	_wall(false, 0.0, 0.0, SHAFT_L, H, H + HOUSE_H, [], true, shaft_c)
	_wall(false, -WALL_T, -WALL_T, SHAFT_L + SW_T, H, H + HOUSE_H, [], false, Color(0.4, 0.4, 0.42))
	_wall(true, 0.0, 0.0, SHAFT_W, H, H + HOUSE_H, [], true, shaft_c)
	_wall(true, -WALL_T, -WALL_T, SHAFT_W + SW_T, H, H + HOUSE_H, [], false, Color(0.4, 0.4, 0.42))
	_wall(true, SHAFT_L + SW_T, -WALL_T, SHAFT_W + SW_T, H, H + HOUSE_H, [], true, Color(0.4, 0.4, 0.42))
	_wall(false, SHAFT_W + SW_T, -WALL_T, SHAFT_L + SW_T, H, H + HOUSE_H, [Rect2(0.0, H, LAND, DOOR_H)], true, Color(0.4, 0.4, 0.42))
	_wall(false, SHAFT_W, 0.0, SHAFT_L, H, H + HOUSE_H, [Rect2(0.0, H, LAND, DOOR_H)], false, shaft_c)
	_mbox(-WALL_T, -WALL_T, H + HOUSE_H, SHAFT_L + SW_T, SHAFT_W + SW_T, H + HOUSE_H + 0.2, Color(0.3, 0.3, 0.32), 32 | 16)
	_mbox(0.1, SHAFT_W + SW_T, H + DOOR_H + 0.05, LAND - 0.1, SHAFT_W + SW_T + 0.05, H + DOOR_H + 0.2, Color(0.1, 1.0, 0.4, GLOW_A), 8)
	var fo := iv + IN + 0.03
	_mbox(du - DOOR_W * 0.5 - 0.25, fo - 0.03, 0.0, du - DOOR_W * 0.5, fo + 0.06, DOOR_H + 0.25, Color(0.15, 0.15, 0.17), 63)
	_mbox(du + DOOR_W * 0.5, fo - 0.03, 0.0, du + DOOR_W * 0.5 + 0.25, fo + 0.06, DOOR_H + 0.25, Color(0.15, 0.15, 0.17), 63)
	_mbox(du - DOOR_W * 0.5 - 0.25, fo - 0.03, DOOR_H, du + DOOR_W * 0.5 + 0.25, fo + 0.08, DOOR_H + 0.3, Color(1.0, 0.75, 0.3, GLOW_A), 63)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _nm
	arr[Mesh.ARRAY_COLOR] = _c
	var am := ArrayMesh.new()
	if _v.size() > 0:
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh.mesh = am


## Visible steps of a flight along u (treads and risers as boxes from the flight's foot).
func _steps(u0: float, y0: float, u1: float, y1: float, v0: float, v1: float, col: Color) -> void:
	var n := maxi(1, int(ceilf(absf(y1 - y0) / STEP_MAX)))
	var dy := (y1 - y0) / n
	var du := (u1 - u0) / n
	var base := minf(y0, y1) - 0.25
	for i in n:
		var ua := u0 + du * i
		var ub := ua + du
		var yt := y0 + dy * (i + 1)
		var c := col if i % 2 == 0 else col * 0.93
		_mbox(minf(ua, ub), v0, maxf(base, yt - 0.6), maxf(ua, ub), v1, yt, c, 32 | (1 if du > 0.0 else 2) | 16)
