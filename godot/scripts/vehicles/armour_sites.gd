class_name ArmourSites
extends Node3D
## WAVE 118 (owner round 7: "where are tanks and helicopters etc."): the FIXED PLACES where the armour and the aircraft always wait, and the CALL-IN that brings one to the hero.
## Found by finger play: the tanks stood in the traffic lanes of the west ring road 300 m from the start, the one city helicopter among plaza statues, every map marker of them wore
## the GARAGE car glyph and lay under the fog, a vehicle only existed within 100 m, and on LOW+ (2 live cars) every new tank released the one beside it.
##   ARMY YARD            plaza (-135, -55), 120 m from the start: main battle tank, light tank, armoured carrier, nose to the road
##   CITY HELIPAD EAST    plaza (105, 25): helicopter          CITY HELIPAD SOUTH   plaza (-25, 185): gunship
##   EASTFIELD AIRPORT    planes and helicopters on the apron (Airport.spawn_points; the ids in FIXED_AIRPORT are kept like the yard's)
## Data is static (VehicleSpawns, the map and the tests read it); the node (one per world, added by VehicleManager) only builds the paint, barriers and signs of a place while the
## hero is within DECOR_IN metres and frees them beyond DECOR_OUT: far away a place costs no node and no draw call.
## A FIXED vehicle (is_fixed(point id)) is outside the live car cap, appears SPAWN_AT metres out and is never released while the hero is within KEEP metres (VehicleManager._tick_spawn_points).
## CALL-IN: call_in(kind) puts a tank, a helicopter or a small plane beside the hero, one cooldown per kind (CALL_COOLDOWN). The phone panel is scripts/ui/call_in.gd.

const SPAWN_AT := 112.0               ## a fixed vehicle stands on its place when the hero is this close (the yard is 120 m from the start: nothing of it exists in the staged perf view)
const KEEP := 150.0                   ## ... and is never released inside this
const DECOR_IN := 112.0
const DECOR_OUT := 135.0
const CALL_COOLDOWN := {&"tank": 90.0, &"heli": 60.0, &"plane": 60.0}
const CALL_KINDS: Array[StringName] = [&"tank", &"heli", &"plane"]
const CALL_NAMES := {&"tank": "TANK", &"heli": "HELICOPTER", &"plane": "PLANE"}

const YARD := Vector3(-135.0, 0.0, -55.0)
const PAD_EAST := Vector3(105.0, 0.0, 25.0)
const PAD_SOUTH := Vector3(-25.0, 0.0, 185.0)
## The places: id, name, pos (a plaza lot centre of the core), type (yard / helipad), glyph (MapIcons), what stands there.
const SITES: Array[Dictionary] = [
	{"id": &"army_yard", "name": "ARMY YARD", "pos": YARD, "type": &"yard", "glyph": &"tank", "label": "TANKS"},
	{"id": &"pad_east", "name": "CITY HELIPAD EAST", "pos": PAD_EAST, "type": &"helipad", "glyph": &"heli", "label": "HELICOPTER"},
	{"id": &"pad_south", "name": "CITY HELIPAD SOUTH", "pos": PAD_SOUTH, "type": &"helipad", "glyph": &"heli", "label": "GUNSHIP"},
]
## The vehicles of the places (VehicleSpawns.POINTS carries the three old depot ids and heli_pad with these positions; pad_south_heli is added by vehicle_points()).
const YARD_BAYS := {&"depot": Vector3(-143.0, 0.0, -53.0), &"depot_light": Vector3(-135.0, 0.0, -53.0), &"depot_apc": Vector3(-127.0, 0.0, -53.0)}
const FIXED_CITY: Array[StringName] = [&"depot", &"depot_light", &"depot_apc", &"heli_pad", &"pad_south_heli"]
const FIXED_AIRPORT: Array[StringName] = [&"ap_heli_a", &"ap_heli_b", &"ap_plane_a", &"ap_jet_a"]

static var fixed_on := true           ## false: the wave 117 rules (cap, 100 m, released like traffic) for the old-behaviour trial of tests/test_armour_w118.gd
static var icons_on := true           ## false: the wave 117 map (fogged GARAGE car glyphs)
static var pick_on := true            ## false: ENTER takes the nearest vehicle in reach even when a called / fixed one stands beside it (wave 117)
static var demo_on := true            ## false: the wave 117 SPAWN lists (no armour section)
static var _call_ready := {}          ## kind -> Game clock (s, Time ticks) from which the call-in works again
static var instance: ArmourSites

var _built := {}                      ## site id -> Node3D
var _t := 0.0


static func is_fixed(id: StringName) -> bool:
	return fixed_on and (FIXED_CITY.has(id) or FIXED_AIRPORT.has(id) or Helipads.owns(id) or HeliRoster.owns(id) or PlaneRoster.owns(id) or TankRoster.owns(id))     # w125-pads: and the helicopters of the new pads (w125-ci: and of the HELI LINE; w126: the PLANE LINE, hangars, shelters)


## The points this file adds to VehicleSpawns.all_points().
static func vehicle_points() -> Array[Dictionary]:
	return [{"id": &"pad_south_heli", "kind": &"gunship", "pos": PAD_SOUTH, "h": 0.0, "label": "CITY HELIPAD SOUTH"}]


## The plaza lot at (x, z) belongs to a place: the plaza furniture and the flora ring stay off it (CityProps._place_plazas, CityKit._place_flora).
static func claims(x: float, z: float) -> bool:
	for s in SITES:
		var p: Vector3 = s["pos"]
		if absf(p.x - x) < 14.0 and absf(p.z - z) < 14.0:
			return true
	return false


## The kerb strip between the ARMY YARD and its road: no street prop stands in the tanks' way out (CityKit._clear_armour_lanes).
static func keeps_clear(x: float, z: float) -> bool:
	return fixed_on and absf(x - YARD.x) <= 13.6 and z - YARD.z <= -11.0 and z - YARD.z >= -17.5


## The parking bays along the yard's frontage stay empty (ParkedCars._gen_cell, VehicleManager._find_spot): a kerb car there shut the tanks in.
static func no_parking(x: float, z: float) -> bool:
	return fixed_on and absf(x - YARD.x) <= 15.5 and z - YARD.z <= -11.0 and z - YARD.z >= -20.0


## Map markers (kind armour, never fogged, a tank / helicopter / plane glyph): the three city places, the old ring-road depot, the airstrip and the airport's apron. Cached (the
## minimap asks on every redraw); `icons_on = false` gives none.
static var _markers: Array[Dictionary] = []


static func map_markers() -> Array[Dictionary]:
	if not icons_on:
		return []
	if not _markers.is_empty():
		return _markers
	var out: Array[Dictionary] = []
	for s in SITES:
		out.append({"kind": &"armour", "pos": s["pos"], "fog": false, "label": s["label"], "glyph": s["glyph"]})
	out.append({"kind": &"armour", "pos": Vector3(-320.0, 0.0, 120.0), "fog": false, "label": "ARTILLERY", "glyph": &"tank"})
	out.append({"kind": &"armour", "pos": Vector3(340.0, 0.0, 0.0), "fog": false, "label": "PLANE", "glyph": &"plane"})
	var plane := VehicleSpawns.point(&"ap_plane_a")
	if not plane.is_empty():
		out.append({"kind": &"armour", "pos": plane["pos"], "fog": false, "label": "PLANES", "glyph": &"plane"})
	var heli := VehicleSpawns.point(&"ap_heli_a")
	if not heli.is_empty():
		out.append({"kind": &"armour", "pos": heli["pos"], "fog": false, "label": "HELICOPTERS", "glyph": &"heli"})
	out.append_array(TankRoster.map_markers())                   # w127-tanks: ARMY BASE, VEHICLE DEPOT and the three road CHECKPOINTS (a tank glyph each)
	out.append_array(Helipads.map_markers())                     # w125-pads: an H badge on every helipad of the world (never fogged)
	if OutskirtsSites.built or not Helipads.enabled:             # w125-pads: the towns' pads exist once the roads are built (cache the whole list only)
		_markers = out
	return out


## The nearest marker of `glyph` (tank / heli / plane) to `from`: {} when none.
static func nearest_marker(glyph: StringName, from: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for m in map_markers():
		if m["glyph"] != glyph:
			continue
		var p: Vector3 = m["pos"]
		var d := Vector2(p.x - from.x, p.z - from.z).length()
		if d < bd:
			bd = d
			best = m
	return best


# --- call-in ---------------------------------------------------------------------------------------------------------------------------

static var _scaled_clock := 0.0        ## game seconds (advanced by the node's _process, so a sped-up test waits game time, not wall time)


## Seconds until `kind` can be called again (0 = ready).
static func call_wait(kind: StringName) -> float:
	return maxf(float(_call_ready.get(kind, 0.0)) - _scaled_clock, 0.0)


static func reset_calls() -> void:
	_call_ready.clear()


## CALL-IN: a tank, a helicopter or a small plane is delivered beside the hero (on foot, outdoors, on the ground). Returns the vehicle, or null with a message that says why.
static func call_in(kind: StringName) -> Vehicle:
	var vm := Game.vehicles as VehicleManager
	var p := Game.player
	if vm == null or not is_instance_valid(p) or not Game.is_playing() or not CALL_KINDS.has(kind):
		return null
	if vm.driven != null or p.get(&"vehicle") != null:
		Game.say("LEAVE THE VEHICLE FIRST", 1.4)
		return null
	if InteriorGameplay.active or not p.is_on_floor() or p.global_position.y >= 2.0:
		Game.say("CALL-IN NEEDS OPEN GROUND", 1.4)
		return null
	var wait := call_wait(kind)
	if wait > 0.0:
		Game.say("%s READY IN %d S" % [CALL_NAMES[kind], int(ceilf(wait))], 1.4)
		return null
	var yaw := float(p.get(&"yaw")) if p.get(&"yaw") != null else 0.0
	var at := drop_point(vm, kind, p.global_position, yaw)
	if at == Vector3.INF:
		Game.say("NO ROOM HERE FOR A %s" % CALL_NAMES[kind], 1.6)
		return null
	for old: Vehicle in vm.list.duplicate():                       # the one called before goes when a new one of its kind comes (never the one being driven)
		if old.has_meta(&"called") and old.kind == kind and not old.driver_is_player:
			vm._release(old)
	vm._fixed_n += 1                                                # room above the cap for the delivery (counted again below)
	var v := vm.spawn_parked(kind, at, yaw)
	if v == null:
		vm._count_fixed()
		return null
	v.set_meta(&"called", true)
	v.set_meta(&"hold", true)                                       # the delivery is not streamed away or trimmed by the cap while he walks to it (dropped when he gets in, or beyond KEEP)
	vm._count_fixed()
	v.update_lod(0.0)
	_call_ready[kind] = _scaled_clock + float(CALL_COOLDOWN[kind])
	FX.burst(Vector3(at.x, 1.0, at.z), Color(0.75, 1.0, 0.3), 18, 5.0, 0.6, 0.0)
	Sfx.play_at(&"blink", at, -6.0)
	Game.say("%s DELIVERED" % CALL_NAMES[kind], 1.8)
	return v


## DEMO and TEST menu (the SPAWN lists): `kind` stands next to the hero at once, no cooldown. Returns the line the menu shows.
static func spawn_beside(kind: StringName) -> String:
	var vm := Game.vehicles as VehicleManager
	var p := Game.player
	if vm == null or not is_instance_valid(p) or not VehicleSpecs.SPECS.has(kind):
		return ""
	var yaw := float(p.get(&"yaw")) if p.get(&"yaw") != null else 0.0
	var at := drop_point(vm, kind, p.global_position, yaw)
	if at == Vector3.INF:
		return "NO ROOM HERE FOR %s" % VehicleSpecs.name_of(kind)
	vm._fixed_n += 1
	var v := vm.spawn_parked(kind, at, yaw)
	if v == null:
		vm._count_fixed()
		return ""
	v.set_meta(&"called", true)
	v.set_meta(&"hold", true)
	vm._count_fixed()
	v.update_lod(0.0)
	Game.say("%s NEXT TO YOU" % VehicleSpecs.name_of(kind), 1.8)
	return "SPAWNED  %s" % VehicleSpecs.name_of(kind)


## The kinds of the demo SPAWN list's first section.
const DEMO_KINDS: Array[StringName] = [&"tank", &"ltank", &"apc", &"heli", &"gunship", &"plane", &"jet"]


static func demo_kinds() -> Array[StringName]:
	var none: Array[StringName] = []
	return DEMO_KINDS if demo_on else none


## A free spot for a hull of `kind` near `from`: in front of the hero first, then a ring of other directions and distances; never inside a building, never on another vehicle.
static func drop_point(vm: VehicleManager, kind: StringName, from: Vector3, yaw: float) -> Vector3:
	var spec: Dictionary = VehicleSpecs.SPECS[kind]
	var half := maxf(float(spec["len"]), float(spec["wid"])) * 0.5
	var world: Object = Game.world if is_instance_valid(Game.world) else null
	for dist: float in [half + 5.0, half + 9.0, half + 14.0]:
		for turn: float in [0.0, 0.6, -0.6, 1.3, -1.3, 2.2, -2.2, PI]:
			var a := yaw + turn
			var at := Vector3(from.x - sin(a) * dist, 0.0, from.z - cos(a) * dist)
			if world != null and world.has_method(&"is_inside_building"):
				var blocked := false
				for o: Vector2 in [Vector2.ZERO, Vector2(half, 0.0), Vector2(-half, 0.0), Vector2(0.0, half), Vector2(0.0, -half)]:
					if world.call(&"is_inside_building", Vector3(at.x + o.x, 1.0, at.z + o.y)):
						blocked = true
						break
				if blocked:
					continue
			if not vm._spot_free(at, half + 2.5) or not vm._hull_ok(kind, at, yaw, true):
				continue
			return at
	return Vector3.INF


# --- the node: decor of the places near the hero ----------------------------------------------------------------------------------------------

static func attach(parent: Node) -> void:
	if is_instance_valid(instance) or parent == null:
		return
	instance = ArmourSites.new()
	instance.name = "ArmourSites"
	parent.add_child(instance)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	_scaled_clock += delta
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	if not is_instance_valid(Game.player):
		return
	var pp := Game.player.global_position
	for s in SITES:
		var id: StringName = s["id"]
		var c: Vector3 = s["pos"]
		var d := Vector2(c.x - pp.x, c.z - pp.z).length()
		if not _built.has(id) and d < DECOR_IN:
			var n := _build(s)
			add_child(n)
			_built[id] = n
		elif _built.has(id) and d > DECOR_OUT:
			(_built[id] as Node).queue_free()
			_built.erase(id)


func built_count() -> int:
	return _built.size()


static var _mat: StandardMaterial3D
static var _glow: StandardMaterial3D


static func _materials() -> void:
	if _mat != null:
		return
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.roughness = 0.92
	_glow = StandardMaterial3D.new()
	_glow.vertex_color_use_as_albedo = true
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


static func _quad(st: SurfaceTool, c: Vector3, sx: float, sz: float, col: Color, yaw := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	var a := c + b * Vector3(-sx, 0.0, -sz) * 0.5
	var d := c + b * Vector3(sx, 0.0, -sz) * 0.5
	var e := c + b * Vector3(sx, 0.0, sz) * 0.5
	var f := c + b * Vector3(-sx, 0.0, sz) * 0.5
	st.set_color(col)
	st.set_normal(Vector3.UP)
	for v: Vector3 in [a, d, e, a, e, f]:
		st.add_vertex(v)


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color, yaw := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	var h := size * 0.5
	var faces := [
		[Vector3.UP, Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3.BACK, Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, -1, 1)],
		[Vector3.FORWARD, Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, -1)],
		[Vector3.RIGHT, Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(1, -1, -1)],
		[Vector3.LEFT, Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(-1, -1, 1)],
	]
	for f: Array in faces:
		var n: Vector3 = f[0]
		st.set_color(col * (1.0 if n == Vector3.UP else 0.82))
		st.set_normal(b * n)
		for i: int in [1, 2, 3, 1, 3, 4]:
			st.add_vertex(c + b * ((f[i] as Vector3) * h))


static func _ring(st: SurfaceTool, c: Vector3, r0: float, r1: float, col: Color, seg := 40) -> void:
	st.set_color(col)
	st.set_normal(Vector3.UP)
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var p0 := c + Vector3(cos(a0), 0.0, sin(a0)) * r0
		var p1 := c + Vector3(cos(a1), 0.0, sin(a1)) * r0
		var q0 := c + Vector3(cos(a0), 0.0, sin(a0)) * r1
		var q1 := c + Vector3(cos(a1), 0.0, sin(a1)) * r1
		for v: Vector3 in [q0, q1, p1, q0, p1, p0]:
			st.add_vertex(v)


static func _wall(body: StaticBody3D, c: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.position = c
	body.add_child(cs)


static func _sign(root: Node3D, st: SurfaceTool, at: Vector3, text: String, w: float, top: float, col: Color) -> void:
	_box(st, at + Vector3(-w * 0.5 + 0.2, top * 0.5, 0.0), Vector3(0.18, top, 0.18), Color(0.22, 0.24, 0.24))
	_box(st, at + Vector3(w * 0.5 - 0.2, top * 0.5, 0.0), Vector3(0.18, top, 0.18), Color(0.22, 0.24, 0.24))
	_box(st, at + Vector3(0.0, top - 0.75, 0.0), Vector3(w, 1.5, 0.14), col)
	for side: float in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = text
		l.font_size = 96
		l.pixel_size = 0.0095
		l.outline_size = 0
		l.modulate = Color(0.96, 0.95, 0.86)
		l.shaded = false
		l.double_sided = false
		l.position = at + Vector3(0.0, top - 0.75, 0.09 * side)
		l.rotation.y = 0.0 if side > 0.0 else PI
		root.add_child(l)


## The paint, the barriers and the sign of one place. Two surfaces (lit paint and concrete, unlit lamps), one body with a few boxes, two labels.
static func _build(s: Dictionary) -> Node3D:
	_materials()
	var root := Node3D.new()
	root.name = String(s["id"])
	var c: Vector3 = s["pos"]
	root.position = c
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gl := SurfaceTool.new()
	gl.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	root.add_child(body)
	var y := 0.045
	if s["type"] == &"yard":
		var olive := Color(0.2, 0.25, 0.16)
		var conc := Color(0.5, 0.5, 0.47)
		var yellow := Color(0.95, 0.74, 0.1)
		_quad(st, Vector3(0.0, y, 0.0), 27.0, 27.0, Color(0.15, 0.165, 0.15))
		for e: Array in [[Vector3(0.0, y + 0.01, -13.2), 27.0, 0.5], [Vector3(0.0, y + 0.01, 13.2), 27.0, 0.5], [Vector3(-13.2, y + 0.01, 0.0), 0.5, 27.0], [Vector3(13.2, y + 0.01, 0.0), 0.5, 27.0]]:
			_quad(st, e[0], e[1], e[2], yellow)
		for bx: float in [-12.0, -4.0, 4.0, 12.0]:                      # the three bays (tanks at local x -8, 0, 8, z +2)
			_quad(st, Vector3(bx, y + 0.01, 2.0), 0.3, 11.0, Color(0.92, 0.92, 0.88))
		for i in 9:                                                       # back wall (north) and the east side: concrete blocks, shoulder high
			_box(st, Vector3(-12.0 + 3.0 * float(i), 0.55, 12.6), Vector3(2.7, 1.1, 0.6), conc)
		for i in 7:
			_box(st, Vector3(12.9, 0.55, 10.0 - 3.0 * float(i)), Vector3(0.6, 1.1, 2.7), conc)
		_wall(body, Vector3(0.0, 0.55, 12.6), Vector3(26.7, 1.1, 0.6))
		_wall(body, Vector3(12.9, 0.55, 1.0), Vector3(0.6, 1.1, 20.7))
		_sign(root, st, Vector3(0.0, 0.0, 12.6), "ARMY YARD", 9.0, 5.6, olive)
		_wall(body, Vector3(-4.3, 2.0, 12.6), Vector3(0.2, 4.0, 0.6))
		_wall(body, Vector3(4.3, 2.0, 12.6), Vector3(0.2, 4.0, 0.6))
		for mx: float in [-12.6, 12.6]:                                   # two floodlight masts at the back corners: seen over the tanks from the road
			_box(st, Vector3(mx, 4.0, 12.6), Vector3(0.22, 8.0, 0.22), Color(0.24, 0.26, 0.26))
			_box(gl, Vector3(mx, 8.1, 12.3), Vector3(1.2, 0.45, 0.5), Color(1.0, 0.96, 0.8))
		for sx: float in [-9.0, 9.0]:                                     # chevrons on the road side: this is the way out
			_quad(st, Vector3(sx, y + 0.01, -11.0), 3.0, 0.5, yellow, 0.6)
			_quad(st, Vector3(sx, y + 0.01, -11.0), 3.0, 0.5, yellow, -0.6)
	else:
		var white := Color(0.94, 0.94, 0.9)
		_ring(st, Vector3(0.0, y, 0.0), 0.0, 9.5, Color(0.13, 0.14, 0.16))
		_ring(st, Vector3(0.0, y + 0.01, 0.0), 7.7, 8.4, Color(0.95, 0.74, 0.1))
		_quad(st, Vector3(-1.6, y + 0.01, 0.0), 0.8, 5.4, white)
		_quad(st, Vector3(1.6, y + 0.01, 0.0), 0.8, 5.4, white)
		_quad(st, Vector3(0.0, y + 0.01, 0.0), 3.2, 0.8, white)
		for i in 8:
			var a := TAU * float(i) / 8.0 + 0.39
			_box(gl, Vector3(cos(a) * 9.0, 0.12, sin(a) * 9.0), Vector3(0.3, 0.24, 0.3), Color(0.3, 1.0, 0.45) if i % 2 == 0 else Color(1.0, 0.3, 0.25))
		_sign(root, st, Vector3(0.0, 0.0, 12.8), "HELIPAD", 6.0, 3.6, Color(0.1, 0.22, 0.4))
		_wall(body, Vector3(-2.8, 1.8, 12.8), Vector3(0.2, 3.6, 0.2))
		_wall(body, Vector3(2.8, 1.8, 12.8), Vector3(0.2, 3.6, 0.2))
		_box(st, Vector3(-11.5, 3.0, 11.5), Vector3(0.14, 6.0, 0.14), Color(0.8, 0.8, 0.8))       # windsock
		_box(gl, Vector3(-10.6, 5.7, 11.5), Vector3(1.8, 0.5, 0.5), Color(1.0, 0.45, 0.1))
		_wall(body, Vector3(-11.5, 3.0, 11.5), Vector3(0.2, 6.0, 0.2))
	var mesh := st.commit()
	mesh.surface_set_material(0, _mat)
	gl.commit(mesh)
	mesh.surface_set_material(1, _glow)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = DECOR_OUT
	root.add_child(mi)
	return root
