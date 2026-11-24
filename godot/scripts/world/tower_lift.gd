class_name TowerLift
extends Node3D
## Wave 121 (w121-lifts): LIFTS in the tall city buildings. One lift is built at a time, for the tower next to the hero, and freed when he walks away:
##  - INSIDE mode: the walk-in towers of w121-floors (TowerFloors.current(): a block lot opened in place) get a lift in the LIFT_BAY beside the stairwell, with a stop on every
##    floor (TowerFloors levels: street, floors 1..n, roof), a shaft wall with a landing door on every floor (the hole in the slabs is fenced), one cabin door toward the floor.
##  - OUTSIDE mode: every other tall lot (h >= TALL_H) gets a glass lift on its side facade, street to roof (front door to the sidewalk, back door onto the roof).
## The cabin is a real moving body; a ride takes RIDE_MIN .. RIDE_MAX s (owner: under 3 s), the doors slide open and shut, the hero is carried (control_hold while moving).
## Phone: the context slot (the wave 119 door slot, action `interact`, via RideUse.prompt) reads LIFT at a call spot or inside the cabin. Outside it calls the cabin to you;
## inside it opens the floor panel (plain Buttons that TouchButtons makes answer a finger, at least 84 base px = 46 px on an 844 x 390 phone). The HUD label LiftFloor shows the floor
## while the hero is in the tower; the map draws the tower outline and the floor (map_info). QT_NO_LIFTS=1 leaves it out.
## Draw calls: shaft + landing doors 2, cabin 4 (opaque, glass, doors, lamp): vertex-coloured merged meshes.

static var instance: TowerLift

const TALL_H := 24.0
const BUILD_R := 70.0              ## an outside lift is built for the nearest tall lot within this distance
const FREE_R := 95.0
const CAB_H := 2.6
const OUT := 1.05                  ## outside mode: cabin centre in front of the wall (metres)
const REACH := 2.4                 ## call spot reach (a running hero slides a metre past the spot)
const RIDE_MAX := 2.6              ## seconds, the longest ride (owner: under 3 s)
const RIDE_MIN := 1.1
const SPEED := 40.0                ## metres per second the ride length is planned with
const DOOR_T := 0.45               ## seconds a door takes to open or close
const PANEL_BTN := 96.0            ## base px of a floor button (52 px at 844 x 390)
const PANEL_MIN := 84.0
const GATE_H := 2.5

var mode := &""                    ## &"in" (TowerFloors tower), &"out" (facade lift), &"" none
var lot_idx := -1
var stops := PackedFloat32Array()  ## cabin floor top y of every stop, ground first, roof last
var names: PackedStringArray = []
var base := Transform3D()          ## origin: cabin centre at y 0; local +Z = the (front) door side
var footprint := PackedVector2Array()
var cab_w := 2.0
var cab_d := 1.9
var at_stop := 0
var target := -1
var state := &"idle"               ## idle, opening, open, closing, moving
var door_k := 0.0                  ## 0 closed .. 1 open
var ride_t := 0.0
var ride_len := 1.0
var ride_from := 0.0
var cab_y := 0.0
var rides := 0                     ## finished rides (tests)
var last_ride_s := 0.0
var _scan_t := 0.0
var _carry := false
var _cabin: AnimatableBody3D
var _door_mm: MultiMeshInstance3D  ## the cabin's door leaves (local transforms)
var _door_shapes: Array = []       ## [front_l, front_r, back_l, back_r] CollisionShape3D (back only outside)
var _shaft: StaticBody3D
var _gate_mm: MultiMeshInstance3D  ## the landing doors (inside mode), one instance per stop
var _gate_shapes: Array = []
var _panel: CanvasLayer
var _list: Control
var _floor_label: Label
var _tower_lots := {}              ## lots TowerFloors handles (no outside lift there: its walk-in door is on that face)


static func attach(parent: Node) -> TowerLift:
	var w := TowerLift.new()
	w.name = "TowerLift"
	parent.add_child(w)
	return w


func _ready() -> void:
	instance = self
	process_physics_priority = 20                   # after the hero's own move: the cabin carries him
	_make_panel()


func _exit_tree() -> void:
	if instance == self:
		instance = null


# ---------------------------------------------------------------------------------------------------------------------
# data
# ---------------------------------------------------------------------------------------------------------------------

const Roofs := preload("res://scripts/world/city_roofs.gd")
const Buildings := preload("res://scripts/world/city_buildings.gd")


static func _layout() -> CityLayout:
	if is_instance_valid(Game.world) and Game.world.get("layout") is CityLayout:
		return Game.world.get("layout") as CityLayout
	return null


## The tall lots (indices) of the city.
static func tall_lots() -> Array[int]:
	var out: Array[int] = []
	var lay := _layout()
	if lay == null:
		return out
	for lot: CityLayout.Lot in lay.lots:
		if lot.h >= TALL_H:
			out.append(lot.index)
	return out


## Outside mode: where the facade lift of a lot stands: {pos (cabin centre, y 0), yaw, normal, face}. On the street face the USE door does not use, near its corner.
static func spot(lot: CityLayout.Lot) -> Dictionary:
	var bx := -CityLayout.HALF + (lot.block_i + 0.5) * CityLayout.PITCH
	var bz := -CityLayout.HALF + (lot.block_j + 0.5) * CityLayout.PITCH
	var sx := 1 if lot.cx > bx else -1
	var sz := 1 if lot.cz > bz else -1
	var faces: Array[int] = [0 if sx > 0 else 1, 2 if sz > 0 else 3]
	var door_face := faces[0 if Buildings.hash01(lot.index, 22) < 0.5 else 1]
	var face := faces[1] if door_face == faces[0] else faces[0]
	var fw := Roofs.wall_width(lot, face)
	var wp: Array = Roofs.wall_point(lot, face, clampf(fw * 0.2, 2.0, fw - 2.0))
	var p2: Vector2 = wp[0]
	var yaw := float(wp[1])
	var n := Basis(Vector3.UP, yaw) * Vector3.BACK
	return {"pos": Vector3(lot.cx + p2.x, 0.0, lot.cz + p2.y) + n * OUT, "yaw": yaw, "normal": n, "face": face}


static var _spots := {}               ## Vector2i (8 m cell) -> Array of Vector2 outside lift street spots (lazy)


## True where a kerb car must not park: within 4.5 m of a facade lift's street door (ParkedCars asks; a car on the bay stood on the call spot and the hero climbed its roof).
static func no_parking(x: float, z: float) -> bool:
	if _spots.is_empty():
		var lay := _layout()
		if lay == null:
			return false
		_spots[Vector2i(1 << 20, 0)] = []                     # marks "built" even for a city without towers
		for lot: CityLayout.Lot in lay.lots:
			if lot.h < TALL_H:
				continue
			var sp: Dictionary = spot(lot)
			var c: Vector3 = Vector3(sp["pos"]) + Vector3(sp["normal"]) * 2.0
			var k := Vector2i(floori(c.x / 8.0), floori(c.z / 8.0))
			if not _spots.has(k):
				_spots[k] = []
			(_spots[k] as Array).append(Vector2(c.x, c.z))
	var k0 := Vector2i(floori(x / 8.0), floori(z / 8.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for q: Vector2 in _spots.get(k0 + Vector2i(dx, dz), []):
				if q.distance_to(Vector2(x, z)) < 4.5:
					return true
	return false


func floor_name(i: int) -> String:
	if i < 0 or i >= stops.size():
		return ""
	return "GROUND" if i == 0 else ("ROOF" if i == stops.size() - 1 else "FLOOR %d" % i)


# ---------------------------------------------------------------------------------------------------------------------
# which lift
# ---------------------------------------------------------------------------------------------------------------------

func _hero() -> Node3D:
	return Game.player as Node3D if is_instance_valid(Game.player) else null


func _scan() -> void:
	var p := _hero()
	var lay := _layout()
	if p == null or lay == null:
		return
	if _carry:
		return
	var hp := p.global_position
	var cur: Dictionary = TowerFloors.current() if TowerFloors.enabled else {}
	if not cur.is_empty():
		if mode != &"in" or lot_idx != int(cur["lot"]):
			build_inside(cur)
		return
	if mode == &"in":
		_free_lift()
	if mode == &"out":
		if Vector2(hp.x - base.origin.x, hp.z - base.origin.z).length() < FREE_R:
			return
		_free_lift()
	if _tower_lots.is_empty() and TowerFloors.instance != null and TowerFloors.enabled:
		if TowerFloors.instance.towers.is_empty():
			TowerFloors.instance._collect()
		for tw: Dictionary in TowerFloors.instance.towers:
			_tower_lots[(tw["lot"] as CityLayout.Lot).index] = true
		_tower_lots[-1] = true
	var best := -1
	var best_d := BUILD_R
	for lot: CityLayout.Lot in lay.lots:
		if lot.h < TALL_H or _tower_lots.has(lot.index):
			continue
		var d := Vector2(lot.cx - hp.x, lot.cz - hp.z).length() - 0.5 * maxf(lot.w, lot.d)
		if d < best_d:
			best_d = d
			best = lot.index
	if best >= 0:
		build_for(best)


func _ray_y(x: float, z: float, from_y: float, fallback: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, from_y - 400.0, z), 1)
	if _cabin != null:
		q.exclude = [_cabin.get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return float((r["position"] as Vector3).y) if not r.is_empty() else fallback


func _reset_state(lot: CityLayout.Lot, g: float) -> void:
	lot_idx = lot.index
	footprint = PackedVector2Array([Vector2(lot.rect.position.x, lot.rect.position.y), Vector2(lot.rect.end.x, lot.rect.position.y),
			Vector2(lot.rect.end.x, lot.rect.end.y), Vector2(lot.rect.position.x, lot.rect.end.y)])
	at_stop = 0
	target = -1
	cab_y = g
	state = &"idle"
	door_k = 0.0
	names = PackedStringArray()
	for i in stops.size():
		names.append("G" if i == 0 else ("ROOF" if i == stops.size() - 1 else str(i)))


## Outside mode: the facade lift of lot `idx`, street to roof.
func build_for(idx: int) -> void:
	_free_lift()
	var lay := _layout()
	if lay == null or idx < 0 or idx >= lay.lots.size():
		return
	var lot: CityLayout.Lot = lay.lots[idx]
	var sp := spot(lot)
	var n: Vector3 = sp["normal"]
	mode = &"out"
	cab_w = 2.0
	cab_d = 1.9
	base = Transform3D(Basis(Vector3.UP, float(sp["yaw"])), Vector3(sp["pos"]))
	var c := base.origin
	var g := _ray_y(c.x + n.x * 0.2, c.z + n.z * 0.2, 8.0, 0.0)
	var roof_in := c - n * (OUT + 1.6)
	var roof := _ray_y(roof_in.x, roof_in.z, lot.h + 30.0, lot.h)
	var edge := c - n * (OUT + 0.25)
	roof = maxf(roof, minf(_ray_y(edge.x, edge.z, lot.h + 30.0, roof), roof + 1.2))       # a parapet: the cabin stops level with its top
	stops = PackedFloat32Array([g, roof])
	_reset_state(lot, g)
	_build_shaft_out(roof + CAB_H + 0.6 - g, g)
	_build_cabin(true)
	_place_cabin()


## Inside mode: the lift in the LIFT_BAY of the open walk-in tower (TowerFloors.current()).
func build_inside(cur: Dictionary) -> void:
	_free_lift()
	var tw: Dictionary = cur["frame"]
	var lot: CityLayout.Lot = tw["lot"]
	var n: Vector3 = tw["n"]
	mode = &"in"
	var bay := TowerFloors.LIFT_BAY
	var u0 := bay.position.x + TowerFloors.SW_T
	cab_w = minf(1.8, bay.end.x - u0 - 0.12)
	cab_d = bay.size.y - 0.3
	var cu := (u0 + bay.end.x) * 0.5
	var cv := bay.end.y - 0.08 - cab_d * 0.5
	base = Transform3D(Basis(Vector3.UP, atan2(n.x, n.z)), TowerFloors.at(tw, cu, cv, 0.0))
	stops = PackedFloat32Array(cur["levels"])
	_reset_state(lot, stops[0])
	_build_shaft_in(tw, lot)
	_build_cabin(false)
	_place_cabin()


func _free_lift() -> void:
	if _carry:
		_release()
	for nd in [_cabin, _shaft]:
		if is_instance_valid(nd):
			nd.queue_free()
	_cabin = null
	_shaft = null
	_door_mm = null
	_gate_mm = null
	_door_shapes.clear()
	_gate_shapes.clear()
	lot_idx = -1
	mode = &""
	stops = PackedFloat32Array()
	names = PackedStringArray()
	close_panel()


# ---------------------------------------------------------------------------------------------------------------------
# meshes and bodies
# ---------------------------------------------------------------------------------------------------------------------

static var _mats := {}


static func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	match key:
		"solid":
			m.metallic = 0.25
			m.roughness = 0.5
		"glass":
			m.albedo_color = Color(1, 1, 1, 0.3)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_:
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(0.2, 0.9, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.2, 0.9, 1.0)
			m.emission_energy_multiplier = 2.0
	_mats[key] = m
	return m


const C_FRAME := Color(0.16, 0.18, 0.21)
const C_FLOOR := Color(0.3, 0.3, 0.32)
const C_WALL := Color(0.42, 0.44, 0.47)
const C_DOOR := Color(0.62, 0.66, 0.7)
const C_GLASS := Color(0.55, 0.8, 0.9)


## Add a box (centre c, size s, in `xf`'s frame) to a SurfaceTool.
static func _st_box(st: SurfaceTool, xf: Transform3D, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD], [Vector3.UP, Vector3.BACK, Vector3.RIGHT],
		[Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT], [Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	st.set_color(col)
	for f: Array in faces:
		var nn: Vector3 = f[0]
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		var o := c + nn * h
		var ea := a * h
		var eb := b * h
		var p := [o - ea - eb, o + ea - eb, o + ea + eb, o - ea + eb]
		var wn := (xf.basis * nn).normalized()
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(wn)
			st.add_vertex(xf * (p[idx] as Vector3))


static func _shape(body: Node3D, c: Vector3, s: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = s
	cs.shape = sh
	cs.position = c
	body.add_child(cs)
	return cs


static func _st_begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _mi(parent: Node3D, st: SurfaceTool, mat: String, nm: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = st.commit()
	mi.material_override = _mat(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _new_shaft(origin_y: float) -> void:
	_shaft = StaticBody3D.new()
	_shaft.name = "LiftShaft"
	_shaft.collision_layer = Game.L_WORLD
	_shaft.collision_mask = 0
	add_child(_shaft)
	_shaft.global_transform = Transform3D(base.basis, base.origin + Vector3(0.0, origin_y, 0.0))


func _build_shaft_out(shaft_h: float, g: float) -> void:
	_new_shaft(g)
	var st := _st_begin()
	var id := Transform3D.IDENTITY
	var hx := cab_w * 0.5 + 0.08
	var hz := cab_d * 0.5 + 0.08
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_st_box(st, id, Vector3(sx * hx, shaft_h * 0.5, sz * hz), Vector3(0.12, shaft_h, 0.12), C_FRAME)
	_st_box(st, id, Vector3(0.0, shaft_h + 0.25, 0.0), Vector3(cab_w + 0.4, 0.5, cab_d + 0.4), C_FRAME)         # the machine head
	_mi(_shaft, st, "solid", "ShaftMesh")
	var lamp := _st_begin()
	_st_box(lamp, id, Vector3(0.0, 2.9, hz + 0.02), Vector3(cab_w + 0.3, 0.06, 0.1), Color.WHITE)            # the lit header over the street door
	_mi(_shaft, lamp, "lamp", "ShaftLamp")


## Inside mode: walls round the bay on the floor side (with a doorway and a landing door on every level), the side wall, the machine head over the roof.
func _build_shaft_in(tw: Dictionary, lot: CityLayout.Lot) -> void:
	_new_shaft(0.0)
	var st := _st_begin()
	var id := Transform3D.IDENTITY
	var bay := TowerFloors.LIFT_BAY
	var u0 := bay.position.x + TowerFloors.SW_T
	var top := lot.h + CAB_H + 0.5
	# shaft-local frame: x along t (u), z along n (v); the base origin sits at the cabin centre
	var cu := (u0 + bay.end.x) * 0.5
	var cv := bay.end.y - 0.08 - cab_d * 0.5
	var bw := bay.end.x - u0
	var tdir: Vector3 = tw["t"]
	var side_x := (bay.end.x - cu + 0.1) * (1.0 if (base.basis * Vector3.RIGHT).dot(tdir) > 0.0 else -1.0)      # +u may be local -x (TowerFloors flips t to point +x / +z)
	var front_z := bay.end.y - cv + 0.1
	# the side wall (u = bay end), full height
	_st_box(st, id, Vector3(side_x, top * 0.5, -0.05 + (bay.end.y * 0.5 - cv)), Vector3(0.2, top, bay.size.y + 0.4), C_WALL)
	_shape(_shaft, Vector3(side_x, top * 0.5, -0.05 + (bay.end.y * 0.5 - cv)), Vector3(0.2, top, bay.size.y + 0.4))
	# the front wall: above each doorway up to the next level, and the jambs beside the doorway
	var dw := cab_w
	var jamb := (bw - dw) * 0.5
	for k in stops.size():
		var y0 := stops[k]
		var y1 := stops[k + 1] if k + 1 < stops.size() else top
		var lintel := Vector3(0.0, (y0 + GATE_H + y1) * 0.5, front_z)
		var ls := Vector3(bw + 0.2, maxf(y1 - y0 - GATE_H, 0.05), 0.2)
		_st_box(st, id, lintel, ls, C_WALL)
		_shape(_shaft, lintel, ls)
		if jamb > 0.03:
			for sgn in [-1.0, 1.0]:
				var jc := Vector3(sgn * (dw * 0.5 + jamb * 0.5), y0 + GATE_H * 0.5, front_z)
				_st_box(st, id, jc, Vector3(jamb + 0.02, GATE_H, 0.2), C_WALL)
				_shape(_shaft, jc, Vector3(jamb + 0.02, GATE_H, 0.2))
	# below the street floor nothing; above the roof the machine head
	_st_box(st, id, Vector3(0.0, top + 0.2, 0.0), Vector3(bw + 0.3, 0.4, cab_d + 0.5), C_FRAME)
	_mi(_shaft, st, "solid", "ShaftMesh")
	# landing doors, one per level: a MultiMesh (one draw) and a collider each
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	var gm := BoxMesh.new()
	gm.size = Vector3(dw, GATE_H, 0.06)
	mm.mesh = gm
	mm.instance_count = stops.size()
	_gate_mm = MultiMeshInstance3D.new()
	_gate_mm.name = "LandingDoors"
	_gate_mm.multimesh = mm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = C_DOOR
	gmat.metallic = 0.8
	gmat.roughness = 0.3
	_gate_mm.material_override = gmat
	_gate_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shaft.add_child(_gate_mm)
	_gate_shapes.clear()
	for k in stops.size():
		var gc := Vector3(0.0, stops[k] + GATE_H * 0.5, front_z - 0.05)
		mm.set_instance_transform(k, Transform3D(Basis(), gc))
		_gate_shapes.append(_shape(_shaft, gc, Vector3(dw, GATE_H, 0.12)))
	var lamp := _st_begin()
	for k in stops.size():
		_st_box(lamp, id, Vector3(0.0, stops[k] + GATE_H + 0.12, front_z + 0.11), Vector3(dw * 0.6, 0.08, 0.04), Color.WHITE)      # the lit header over every landing door
	_mi(_shaft, lamp, "lamp", "ShaftLamp")


func _build_cabin(two_doors: bool) -> void:
	_cabin = AnimatableBody3D.new()
	_cabin.name = "LiftCabin"
	_cabin.sync_to_physics = false
	_cabin.collision_layer = Game.L_WORLD
	_cabin.collision_mask = 0
	add_child(_cabin)
	var st := _st_begin()
	var gl := _st_begin()
	var id := Transform3D.IDENTITY
	_st_box(st, id, Vector3(0.0, -0.08, 0.0), Vector3(cab_w, 0.16, cab_d), C_FLOOR)
	_shape(_cabin, Vector3(0.0, -0.08, 0.0), Vector3(cab_w, 0.16, cab_d))
	_st_box(st, id, Vector3(0.0, CAB_H + 0.06, 0.0), Vector3(cab_w, 0.12, cab_d), C_FRAME)
	_shape(_cabin, Vector3(0.0, CAB_H + 0.06, 0.0), Vector3(cab_w, 0.12, cab_d))
	for sx in [-1.0, 1.0]:
		_st_box(gl, id, Vector3(sx * (cab_w * 0.5 - 0.03), CAB_H * 0.5, 0.0), Vector3(0.05, CAB_H, cab_d - 0.1), C_GLASS)
		_shape(_cabin, Vector3(sx * (cab_w * 0.5 - 0.03), CAB_H * 0.5, 0.0), Vector3(0.06, CAB_H, cab_d))
		for sz in [-1.0, 1.0]:
			_st_box(st, id, Vector3(sx * (cab_w * 0.5 - 0.04), CAB_H * 0.5, sz * (cab_d * 0.5 - 0.04)), Vector3(0.08, CAB_H, 0.08), C_FRAME)
		_st_box(st, id, Vector3(sx * (cab_w * 0.5 - 0.04), 1.0, 0.0), Vector3(0.05, 0.05, cab_d - 0.1), C_FRAME)        # hand rail
	if not two_doors:
		_st_box(gl, id, Vector3(0.0, CAB_H * 0.5, -cab_d * 0.5 + 0.03), Vector3(cab_w - 0.1, CAB_H, 0.05), C_GLASS)       # the back glass (inside: toward the outer wall)
		_shape(_cabin, Vector3(0.0, CAB_H * 0.5, -cab_d * 0.5 + 0.03), Vector3(cab_w, CAB_H, 0.06))
	_mi(_cabin, st, "solid", "CabinMesh")
	_mi(_cabin, gl, "glass", "CabinGlass")
	var lamp := _st_begin()
	_st_box(lamp, id, Vector3(cab_w * 0.5 - 0.09, 1.3, cab_d * 0.5 - 0.45), Vector3(0.04, 0.3, 0.22), Color.WHITE)       # the lit floor panel on the side glass
	_st_box(lamp, id, Vector3(0.0, CAB_H - 0.02, 0.0), Vector3(cab_w * 0.5, 0.03, cab_d * 0.5), Color.WHITE)                   # the ceiling light
	_mi(_cabin, lamp, "lamp", "CabinLamp")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dm := BoxMesh.new()
	dm.size = Vector3(cab_w * 0.5 - 0.04, CAB_H - 0.05, 0.05)
	mm.mesh = dm
	mm.instance_count = 4 if two_doors else 2
	_door_mm = MultiMeshInstance3D.new()
	_door_mm.name = "CabinDoors"
	_door_mm.multimesh = mm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = C_DOOR
	dmat.metallic = 0.8
	dmat.roughness = 0.3
	_door_mm.material_override = dmat
	_door_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cabin.add_child(_door_mm)
	_door_shapes.clear()
	for i in mm.instance_count:
		var sz := 1.0 if i < 2 else -1.0
		_door_shapes.append(_shape(_cabin, Vector3(0.0, CAB_H * 0.5, sz * (cab_d * 0.5 - 0.02)), dm.size + Vector3(0.0, 0.0, 0.03)))


func _place_cabin() -> void:
	if not is_instance_valid(_cabin):
		return
	_cabin.global_transform = Transform3D(base.basis, base.origin + Vector3(0.0, cab_y, 0.0))
	var top_stop := stops.size() - 1
	var front_open := door_k if (mode == &"in" or at_stop == 0) and target < 0 else 0.0
	var back_open := door_k if mode == &"out" and at_stop == top_stop and target < 0 else 0.0
	var mm := _door_mm.multimesh
	for i in _door_shapes.size():
		var k := front_open if i < 2 else back_open
		var sx := -1.0 if i % 2 == 0 else 1.0
		var sz := 1.0 if i < 2 else -1.0
		var p := Vector3(sx * (cab_w * 0.25 + k * (cab_w * 0.5 - 0.12)), CAB_H * 0.5, sz * (cab_d * 0.5 - 0.02))
		mm.set_instance_transform(i, Transform3D(Basis(), p))
		var cs: CollisionShape3D = _door_shapes[i]
		cs.position = p
		cs.disabled = k > 0.6
	if _gate_mm != null:
		var gm := _gate_mm.multimesh
		for k in _gate_shapes.size():
			var open := door_k if k == at_stop and target < 0 else 0.0
			var cs: CollisionShape3D = _gate_shapes[k]
			var t := gm.get_instance_transform(k)
			t.origin.x = open * (cab_w + 0.05)
			t.origin.y = stops[k] + GATE_H * 0.5 if open < 0.98 else stops[k] - 50.0        # an open landing door slides into the wall (hidden)
			gm.set_instance_transform(k, t)
			cs.disabled = open > 0.6


# ---------------------------------------------------------------------------------------------------------------------
# play
# ---------------------------------------------------------------------------------------------------------------------

## The hero's position in the cabin's frame (x across, z toward the front door, y above the cabin floor).
func _local(p: Vector3) -> Vector3:
	return base.basis.inverse() * (p - (base.origin + Vector3(0.0, cab_y, 0.0)))


func in_cabin(p: Vector3) -> bool:
	if lot_idx < 0:
		return false
	var l := _local(p)
	return absf(l.x) < cab_w * 0.5 and absf(l.z) < cab_d * 0.5 and l.y > -0.6 and l.y < CAB_H


## Where the hero calls the lift at stop i: in front of its door (outside mode: the street door at the ground, the roof door above).
func call_point(i: int) -> Vector3:
	var fwd := base.basis * Vector3.BACK
	var off := cab_d * 0.5 + 0.9
	if mode == &"out" and i > 0:
		off = -(OUT + 1.1)
	return base.origin + fwd * off + Vector3(0.0, stops[i], 0.0)


## The stop the hero stands at (outside the cabin, by its call spot), or -1.
func call_stop(p: Vector3) -> int:
	if lot_idx < 0:
		return -1
	for i in stops.size():
		var s := call_point(i)
		if absf(p.y - s.y) < 1.6 and Vector2(p.x - s.x, p.z - s.z).length() < REACH:
			return i
	return -1


func use_prompt() -> String:
	var p := _hero()
	if p == null or lot_idx < 0 or p.get("vehicle") != null or not Game.is_playing():
		return ""
	if in_cabin(p.global_position) or call_stop(p.global_position) >= 0:
		return "LIFT"
	return ""


## The context slot pressed: inside the cabin it opens the floor panel, at a call spot it calls the cabin.
func use_do() -> void:
	var p := _hero()
	if p == null or lot_idx < 0:
		return
	if in_cabin(p.global_position):
		if state != &"moving":
			open_panel()
		return
	var s := call_stop(p.global_position)
	if s >= 0:
		go_to(s)


func go_to(stop: int) -> void:
	if stop < 0 or stop >= stops.size() or state == &"moving":
		return
	close_panel()
	if stop == at_stop and absf(cab_y - stops[stop]) < 0.01:
		if state != &"open":
			state = &"opening"
		return
	target = stop
	state = &"closing" if door_k > 0.0 else &"moving"
	if state == &"moving":
		_start_ride()


func _start_ride() -> void:
	ride_from = cab_y
	ride_t = 0.0
	ride_len = clampf(absf(stops[target] - cab_y) / SPEED, RIDE_MIN, RIDE_MAX)
	var p := _hero()
	_carry = p != null and in_cabin(p.global_position)
	if _carry:
		p.set(&"control_hold", true)
	Sfx.play(&"ui_tap")


func _release() -> void:
	_carry = false
	var p := _hero()
	if p != null:
		p.set(&"control_hold", false)


func _physics_process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.25
		_scan()
	if lot_idx < 0:
		_update_label()
		return
	match state:
		&"opening":
			door_k = minf(1.0, door_k + delta / DOOR_T)
			if door_k >= 1.0:
				state = &"open"
		&"closing":
			door_k = maxf(0.0, door_k - delta / DOOR_T)
			if door_k <= 0.0:
				state = &"moving"
				_start_ride()
		&"moving":
			ride_t += delta
			var k := clampf(ride_t / ride_len, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			var old_y := cab_y
			cab_y = lerpf(ride_from, stops[target], e)
			var p := _hero()
			if _carry and p != null:
				var l := _local(p.global_position + Vector3(0.0, -(cab_y - old_y), 0.0))
				l.x = clampf(l.x, -cab_w * 0.5 + 0.35, cab_w * 0.5 - 0.35)
				l.z = clampf(l.z, -cab_d * 0.5 + 0.35, cab_d * 0.5 - 0.35)
				p.global_position = base.origin + Vector3(0.0, cab_y + 0.02, 0.0) + base.basis * Vector3(l.x, 0.0, l.z)
				(p as CharacterBody3D).velocity = Vector3.ZERO
			if k >= 1.0:
				at_stop = target
				target = -1
				rides += 1
				last_ride_s = ride_t
				state = &"opening"
				if _carry:
					_release()
	if Game.is_playing() and Input.is_action_just_pressed(&"interact") and use_prompt() != "" and not panel_open():
		use_do()
	if panel_open():
		var p2 := _hero()
		if p2 == null or not in_cabin(p2.global_position) or not Game.is_playing():
			close_panel()                         # walked out, or a menu came up: the panel never stays over another screen
	_place_cabin()
	_update_label()


# ---------------------------------------------------------------------------------------------------------------------
# HUD floor and map
# ---------------------------------------------------------------------------------------------------------------------

## "GROUND" / "FLOOR 3" / "ROOF" ("LIFT  FLOOR 3" in the cabin) while the hero is in the tower (its footprint or the cabin), "" elsewhere.
func hud_floor() -> String:
	var p := _hero()
	if p == null or lot_idx < 0:
		return ""
	var hp := p.global_position
	var lay := _layout()
	var lot: CityLayout.Lot = lay.lots[lot_idx] if lay != null else null
	var cab := in_cabin(hp)
	if not cab and (lot == null or not lot.contains_xz(hp.x, hp.z, 0.2) or hp.y < stops[0] - 1.0):
		return ""
	var best := 0
	for i in stops.size():
		if hp.y >= stops[i] - 0.8:
			best = i
	if not cab and mode == &"out" and best < stops.size() - 1:
		return ""                                     # outside mode: the street beside the tower is not "in" it (only the roof is)
	return ("LIFT  " + floor_name(best)) if cab else floor_name(best)


## For the map: {outline: PackedVector2Array (world x, z), floor: String} of the tower the hero is in, empty when outside.
static func map_info() -> Dictionary:
	if instance == null or instance.lot_idx < 0:
		return {}
	var f := instance.hud_floor()
	if f == "":
		return {}
	return {"outline": instance.footprint, "floor": f.replace("LIFT  ", "")}


func _update_label() -> void:
	if _floor_label == null:
		return
	var t := hud_floor()
	_floor_label.visible = t != "" and Game.is_playing() and not panel_open() and not MapScreen.up
	if _floor_label.visible and _floor_label.text != t:
		_floor_label.text = t


# ---------------------------------------------------------------------------------------------------------------------
# the floor panel
# ---------------------------------------------------------------------------------------------------------------------

func _make_panel() -> void:
	_panel = CanvasLayer.new()
	_panel.name = "LiftPanel"
	_panel.layer = 12
	add_child(_panel)
	_floor_label = Label.new()
	_floor_label.name = "LiftFloor"
	_floor_label.add_theme_font_size_override("font_size", 26)
	_floor_label.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	_floor_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_floor_label.add_theme_constant_override("outline_size", 6)
	_floor_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_floor_label.position = Vector2(-110.0, 150.0)
	_floor_label.size = Vector2(220.0, 34.0)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor_label.visible = false
	_panel.add_child(_floor_label)
	_list = PanelContainer.new()
	_list.name = "LiftList"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.06, 0.09, 0.9)
	sb.border_color = Color(0.2, 0.9, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(14)
	_list.add_theme_stylebox_override("panel", sb)
	_list.visible = false
	_panel.add_child(_list)


func panel_open() -> bool:
	return _list != null and _list.visible


## The panel's buttons (floors top first, then CLOSE).
func panel_buttons() -> Array[Button]:
	var out: Array[Button] = []
	if _list == null:
		return out
	for b in _list.find_children("*", "Button", true, false):
		out.append(b as Button)
	return out


func _btn(text: String, nm: String, h: float, w: float) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", 28)
	b.focus_mode = Control.FOCUS_NONE
	return b


func open_panel() -> void:
	for c in _list.get_children():
		c.free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_list.add_child(vb)
	var title := Label.new()
	title.text = "LIFT  choose a floor"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	vb.add_child(title)
	var vp := get_viewport().get_visible_rect().size
	var n := stops.size()
	var cols := 1
	var bh := PANEL_BTN
	while true:                                            # as few columns as fit the screen height with buttons of at least PANEL_MIN
		var rows := ceili(float(n) / cols) + 1
		bh = clampf((vp.y - 110.0) / rows - 10.0, 0.0, PANEL_BTN)
		if bh >= PANEL_MIN or cols >= 6:
			bh = maxf(bh, PANEL_MIN)
			break
		cols += 1
	var bw := clampf((vp.x - 80.0) / cols - 10.0, 150.0, 240.0)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vb.add_child(grid)
	for i in range(n - 1, -1, -1):
		var b := _btn(floor_name(i) + ("  <" if i == at_stop else ""), "Floor_%s" % names[i], bh, bw)
		b.pressed.connect(go_to.bind(i))
		grid.add_child(b)
	var cl := _btn("CLOSE", "LiftClose", bh, bw)
	cl.pressed.connect(close_panel)
	vb.add_child(cl)
	_list.visible = true
	_list.reset_size()
	var sz := _list.get_combined_minimum_size()
	_list.size = sz
	_list.position = Vector2(vp.x * 0.5 - sz.x * 0.5, maxf(6.0, vp.y * 0.5 - sz.y * 0.5))


func close_panel() -> void:
	if _list != null:
		_list.visible = false
