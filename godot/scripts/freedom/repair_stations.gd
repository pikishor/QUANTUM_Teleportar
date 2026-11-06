class_name RepairStations
extends Node
## MECHANIC bays on the kerbside of the avenues (a green ring and beam, on the minimap): drive the damaged car into one and stop (below MAX_SPEED) for REPAIR_TIME seconds and the
## mechanic puts it right: full hull, dents hammered out, windows replaced, no smoke or fire. A bay then rests for COOLDOWN seconds. The garage car also arrives repaired
## (VehicleManager.summon_garage). One MultiMesh (ring + beam, Jobs.beam_mesh) draws every bay in one call.

const RADIUS := 4.8                        ## m from the bay centre: the lane beside it is inside
const REPAIR_TIME := 1.6                   ## s standing in the ring
const MAX_SPEED := 9.0                     ## m/s: faster cars drive through without stopping
const COOLDOWN := 15.0                     ## s a bay is busy after a repair
const COLOR_READY := Color(0.35, 1.0, 0.55)
const COLOR_BUSY := Color(0.45, 0.5, 0.5)
## (road index along X, road index along Z, kerb side +1 / -1): the bay stands mid-block on the parking strip of the east-west road z = road_center(j) (the first one is next to the spawn).
const STATIONS: Array[Vector3i] = [
	Vector3i(7, 8, 1), Vector3i(9, 6, -1), Vector3i(5, 5, 1), Vector3i(10, 10, -1), Vector3i(7, 12, 1), Vector3i(3, 9, -1),
	Vector3i(12, 7, 1), Vector3i(8, 3, -1), Vector3i(11, 13, 1), Vector3i(1, 4, -1), Vector3i(14, 11, 1), Vector3i(4, 14, -1),
]

var repaired_count := 0                    ## cars put right so far (tests wait on this)
var progress := 0.0                        ## s of the current repair
var _ready_at: Array[float] = []
var _t := 0.0
var _mm: MultiMesh
var _poll := 0.0


static func count() -> int:
	return STATIONS.size()


## World position (ground) of bay i.
static func pos(i: int) -> Vector3:
	var s: Vector3i = STATIONS[i]
	return Vector3(CityLayout.road_center(s.x) + CityLayout.PITCH * 0.5, 0.0, CityLayout.road_center(s.y) + float(s.z) * VehicleSpecs.BAY)


func _ready() -> void:
	name = "RepairStations"
	_ready_at.resize(count())
	_ready_at.fill(0.0)
	_build()


func is_ready(i: int) -> bool:
	return _ready_at[i] <= _t


## The bay the point `p` is inside (-1 when none).
func bay_at(p: Vector3) -> int:
	for i in count():
		var c := pos(i)
		if Vector2(c.x - p.x, c.z - p.z).length() <= RADIUS:
			return i
	return -1


## Minimap markers {pos, color, radius, goal} of the bays within `near` metres.
func markers(near := 320.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var p := Game.player
	if not is_instance_valid(p):
		return out
	var pp := p.global_position
	for i in count():
		var c := pos(i)
		if Vector2(c.x - pp.x, c.z - pp.z).length() <= near:
			out.append({"pos": c, "color": COLOR_READY if is_ready(i) else COLOR_BUSY, "radius": RADIUS, "goal": false})
	return out


func _physics_process(dt: float) -> void:
	if not Game.is_playing():
		return
	_t += dt
	_poll += dt
	var vm := Game.vehicles as VehicleManager
	var car: Vehicle = vm.driven if vm != null else null
	if car == null or not is_instance_valid(car) or car.dead:
		progress = 0.0
		if _poll >= 0.5:
			_poll = 0.0
			_refresh()
		return
	var i := bay_at(car.global_position)
	if i < 0 or not is_ready(i) or absf(car.speed) > MAX_SPEED or not needs_repair(car):
		progress = maxf(progress - dt * 2.0, 0.0)
		if _poll >= 0.5:
			_poll = 0.0
			_refresh()
		return
	if progress <= 0.0:
		Game.say("MECHANIC: HOLD STILL", 1.4)
	progress += dt
	if progress >= REPAIR_TIME:
		repair(i, car)


static func needs_repair(car: Vehicle) -> bool:
	return car.hp < car.max_hp - 0.5 or car.visual.dents.size() > 0 or car.visual.cracks > 0.0 or car.dmg_state > 0


## Put `car` right at bay i (also called by tests and the TEST menu).
func repair(i: int, car: Vehicle) -> void:
	car.repair()
	progress = 0.0
	_ready_at[i] = _t + COOLDOWN
	repaired_count += 1
	var c := pos(i)
	FX.burst(c + Vector3(0.0, 1.0, 0.0), COLOR_READY, 16, 4.0, 0.6, 3.0, 1.0)
	Sfx.play(&"pickup_health")
	Game.say("CAR REPAIRED", 2.0)
	_refresh()


## A flat ring on the road (inner RADIUS - 1.1, outer RADIUS - 0.1): no beam and no translucent cone (those read as glitches on the phone). The minimap shows the bay too.
static func bay_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 28
	var ro := RADIUS - 0.1
	var ri := RADIUS - 1.1
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var c := Color(1, 1, 1, 0.55)
		for v: Vector3 in [Vector3(cos(a0) * ri, 0.06, sin(a0) * ri), Vector3(cos(a0) * ro, 0.06, sin(a0) * ro), Vector3(cos(a1) * ri, 0.06, sin(a1) * ri),
				Vector3(cos(a1) * ri, 0.06, sin(a1) * ri), Vector3(cos(a0) * ro, 0.06, sin(a0) * ro), Vector3(cos(a1) * ro, 0.06, sin(a1) * ro)]:
			st.set_color(c)
			st.add_vertex(v)
	return st.commit()


func _build() -> void:
	var beam := bay_mesh()
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.vertex_color_use_as_albedo = true
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	beam.surface_set_material(0, bm)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = beam
	_mm.instance_count = count()
	var mi := MultiMeshInstance3D.new()
	mi.name = "Bays"
	mi.multimesh = _mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-900, -2, -900), Vector3(1800, 40, 1800))
	mi.top_level = true
	add_child(mi)
	_refresh()


func _refresh() -> void:
	for i in count():
		var c := pos(i)
		var ready := is_ready(i)
		var sc := Basis.from_scale(Vector3(1.0, 1.0 if ready else 0.1, 1.0))
		_mm.set_instance_transform(i, Transform3D(sc, c))
		var col := COLOR_READY if ready else COLOR_BUSY
		_mm.set_instance_color(i, Color(col.r, col.g, col.b, 0.9 if ready else 0.45))
