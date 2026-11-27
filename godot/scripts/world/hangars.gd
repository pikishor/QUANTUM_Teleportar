class_name Hangars
extends RefCounted
## WAVE 126 HANGARS: the two hangars of EASTFIELD AIRPORT (hangar_a, hangar_b of Airport.BUILDINGS) are hollow now, with a big sliding door on the apron face, and the ARMY AIRBASE
## east of the runway gets two aircraft shelters with a door to the south. The hero walks in (the door slides open when he comes within OPEN_R of it, on foot or in a vehicle), the
## parked planes inside (PlaneRoster: two small planes in each airport hangar, one fighter in each shelter) are boarded with ENTER and rolled out through the open door.
## Everything is in the airport's LOCAL frame (Airport.to_world): the shells are part of AirportKit's merged KIT mesh (no extra draw), the walls and roofs are boxes of AirportWorld's
## collision body, the moving door leaves are ONE MultiMesh (one draw for all of them) plus one AnimatableBody3D per leaf (Hangars.Doors, a child of AirportWorld's field).
##   SITES                 id, name, centre (x, z), size, door face (&"e" = +x, &"s" = +z), door width / height, army
##   shell(mb, site)       the walls, roof, door frame and the inside (floor marks, lamps, benches) into an AirportKit MeshBuilder
##   boxes(site)           the collision boxes [centre, size] of the shell (the door leaves are not in it)
##   inside(site, local)   is a local point inside the hangar
##   Doors                 the node that moves the leaves; Doors.open_of(id) = 0 (shut) .. 1 (open)
## W126_PLANES_OLD=1 (on = false) is the wave 125 state: the airport hangars are solid boxes and there are no shelters.

static var on := OS.get_environment("W126_PLANES_OLD") != "1"
const WALL := 0.5
const OPEN_R := 30.0                      ## m from the middle of the door (or anywhere inside) at which the door opens
const DOOR_SPEED := 0.45                  ## of the full travel per second (a little over two seconds to open)
## w128-airlook: lamps inside the hangars (no shadow), on only while the hero is within LAMP_NEAR m; W128_OLD=1 = none (the dark wave 126 hangars).
static var lights_on := OS.get_environment("W128_OLD") != "1"
const LAMP_NEAR := 90.0
const LAMP_ENERGY := 2.2

const SITES: Array[Dictionary] = [
	{"id": &"hangar_a", "name": "HANGAR A", "pos": Vector2(1136.0, -940.0), "size": Vector3(50.0, 16.0, 44.0), "door": &"e", "dw": 38.0, "dh": 12.0, "army": false},
	{"id": &"hangar_b", "name": "HANGAR B", "pos": Vector2(1136.0, -876.0), "size": Vector3(50.0, 16.0, 44.0), "door": &"e", "dw": 38.0, "dh": 12.0, "army": false},
	{"id": &"shelter_1", "name": "ARMY SHELTER 1", "pos": Vector2(1360.0, -775.0), "size": Vector3(26.0, 10.0, 32.0), "door": &"s", "dw": 20.0, "dh": 7.6, "army": true},
	{"id": &"shelter_2", "name": "ARMY SHELTER 2", "pos": Vector2(1360.0, -575.0), "size": Vector3(26.0, 10.0, 32.0), "door": &"s", "dw": 20.0, "dh": 7.6, "army": true},
]


static func site(id: StringName) -> Dictionary:
	for s: Dictionary in SITES:
		if s["id"] == id:
			return s
	return {}


## The door frame of a site in local coordinates: centre of the opening on the face (y = 0), the axis the door runs along (the leaves slide on it), the outward normal.
static func door_frame(s: Dictionary) -> Dictionary:
	var p: Vector2 = s["pos"]
	var sz: Vector3 = s["size"]
	if s["door"] == &"e":
		return {"c": Vector3(p.x + sz.x * 0.5, 0.0, p.y), "along": Vector3(0.0, 0.0, 1.0), "out": Vector3(1.0, 0.0, 0.0), "span": sz.z}
	return {"c": Vector3(p.x, 0.0, p.y + sz.z * 0.5), "along": Vector3(1.0, 0.0, 0.0), "out": Vector3(0.0, 0.0, 1.0), "span": sz.x}


## w126-critic: a WORLD point under the roof of a hangar or shelter (the rain stops there: Atmosphere asks). rain_fix = false (W126C_OLD=1): it rained inside.
static var rain_fix := OS.get_environment("W126C_OLD") != "1"


static func under_roof(world: Vector3) -> bool:
	if not on or not rain_fix:
		return false
	var lp := Airport.to_local(world)
	for s: Dictionary in SITES:
		if inside(s, lp):
			return true
	return false


static func inside(s: Dictionary, local: Vector3) -> bool:
	var p: Vector2 = s["pos"]
	var sz: Vector3 = s["size"]
	return absf(local.x - p.x) < sz.x * 0.5 - WALL and absf(local.z - p.y) < sz.z * 0.5 - WALL and local.y < sz.y


## The collision boxes of the shell: [centre, size] in local coordinates.
static func boxes(s: Dictionary) -> Array:
	var p: Vector2 = s["pos"]
	var sz: Vector3 = s["size"]
	var out: Array = []
	var h := sz.y
	var df := door_frame(s)
	var dw := float(s["dw"])
	var dh := float(s["dh"])
	var jamb := (float(df["span"]) - dw) * 0.5
	out.append([Vector3(p.x, h + 0.3, p.y), Vector3(sz.x, 0.6, sz.z)])                       # the roof
	if s["door"] == &"e":
		out.append([Vector3(p.x - sz.x * 0.5 + WALL * 0.5, h * 0.5, p.y), Vector3(WALL, h, sz.z)])             # back wall (west)
		for sz2 in [-1.0, 1.0]:
			out.append([Vector3(p.x, h * 0.5, p.y + sz2 * (sz.z * 0.5 - WALL * 0.5)), Vector3(sz.x, h, WALL)])  # side walls
			out.append([Vector3(p.x + sz.x * 0.5 - WALL * 0.5, h * 0.5, p.y + sz2 * (sz.z * 0.5 - jamb * 0.5)), Vector3(WALL, h, jamb)])   # jambs
		out.append([Vector3(p.x + sz.x * 0.5 - WALL * 0.5, (h + dh) * 0.5, p.y), Vector3(WALL, h - dh, dw)])     # lintel
	else:
		out.append([Vector3(p.x, h * 0.5, p.y - sz.z * 0.5 + WALL * 0.5), Vector3(sz.x, h, WALL)])             # back wall (north)
		for sx in [-1.0, 1.0]:
			out.append([Vector3(p.x + sx * (sz.x * 0.5 - WALL * 0.5), h * 0.5, p.y), Vector3(WALL, h, sz.z)])
			out.append([Vector3(p.x + sx * (sz.x * 0.5 - jamb * 0.5), h * 0.5, p.y + sz.z * 0.5 - WALL * 0.5), Vector3(jamb, h, WALL)])
		out.append([Vector3(p.x, (h + dh) * 0.5, p.y + sz.z * 0.5 - WALL * 0.5), Vector3(dw, h - dh, WALL)])
	return out


## The shell into AirportKit's KIT MeshBuilder (local frame): walls (both faces: thin boxes), roof with its ceiling, door frame, lamps, floor marks and a few work benches.
static func shell(mb: RefCounted, s: Dictionary) -> void:
	var p: Vector2 = s["pos"]
	var sz: Vector3 = s["size"]
	var army: bool = s["army"]
	var wall := AirportKit._c(Color(0.5, 0.5, 0.46) if army else Color(0.62, 0.64, 0.66), AirportKit.CONCRETE if army else AirportKit.CLAD)
	var inner := AirportKit._c(Color(0.7, 0.71, 0.72) if not army else Color(0.56, 0.56, 0.52), AirportKit.CONCRETE)
	var roof := AirportKit._c(Color(0.42, 0.44, 0.48) if not army else Color(0.36, 0.38, 0.34), AirportKit.CLAD if not army else AirportKit.CONCRETE)
	for b: Array in boxes(s):
		var c: Vector3 = b[0]
		var bs: Vector3 = b[1]
		mb.call(&"box", c, bs, wall if c.y < sz.y else roof, true)
	var h := sz.y
	# the inside: a lighter skin on the walls (a hair inside them), lamp rows under the roof, painted parking boxes, benches and tool chests at the back
	var df := door_frame(s)
	var out: Vector3 = df["out"]
	var along: Vector3 = df["along"]
	var back := Vector3(p.x, 0.0, p.y) - out * (sz.x if s["door"] == &"e" else sz.z) * 0.5
	var depth: float = sz.x if s["door"] == &"e" else sz.z
	var span: float = df["span"]
	var skin := _yaw_box(back + out * (WALL + 0.03) + Vector3(0.0, h * 0.5, 0.0), Vector3(span - 2.0 * WALL - 0.1, h - 0.2, 0.06), out)
	mb.call(&"box", skin[0], skin[1], inner, false)
	for i in 3:
		var lp := back + out * depth * (0.25 + 0.25 * float(i)) + Vector3(0.0, h - 0.25, 0.0)
		var lb := _yaw_box(lp, Vector3(span * 0.7, 0.12, 0.5), out)
		mb.call(&"box", lb[0], lb[1], AirportKit._c(Color(1.0, 0.97, 0.88), AirportKit.LAMP), true)
	var yellow := AirportKit.YELLOW
	for k in ([-0.25, 0.25] if not army else [0.0]):
		var mid := Vector3(p.x, 0.0, p.y) + along * span * float(k)
		for e in [-1.0, 1.0]:
			var l1 := _yaw_box(mid + along * e * span * (0.2 if not army else 0.36) + Vector3(0.0, AirportKit.Y_PAINT, 0.0), Vector3(0.3, 0.02, depth * 0.8), along)
			mb.call(&"box", l1[0], l1[1], yellow, false)
		var l2 := _yaw_box(mid - out * depth * 0.38 + Vector3(0.0, AirportKit.Y_PAINT, 0.0), Vector3(span * (0.4 if not army else 0.72), 0.02, 0.3), out)
		mb.call(&"box", l2[0], l2[1], yellow, false)
	var bench := AirportKit._c(Color(0.32, 0.36, 0.42), AirportKit.STEEL)
	var red := AirportKit._c(Color(0.7, 0.16, 0.12), AirportKit.STEEL)
	for j in 4:
		var bp := back + out * (WALL + 0.8) + along * span * (-0.38 + 0.25 * float(j))
		var bb := _yaw_box(bp + Vector3(0.0, 0.5, 0.0), Vector3(2.6, 1.0, 1.0), out)
		mb.call(&"box", bb[0], bb[1], bench if j % 2 == 0 else red, true)
	# the outside: the stepped roof of the airport hangars or the earth berm of a shelter, and the lit stripe over the door
	if not army:
		mb.call(&"box", Vector3(p.x, h + 1.0, p.y), Vector3(sz.x - 6.0, 0.8, sz.z - 4.0), roof, true)
		mb.call(&"box", Vector3(p.x, h + 1.7, p.y), Vector3(sz.x - 16.0, 0.6, sz.z - 10.0), roof, true)
	else:
		var berm := AirportKit._c(Color(0.32, 0.36, 0.24), AirportKit.CONCRETE)
		for sx in [-1.0, 1.0]:                                                # an earth berm leans on each side wall: a sloped face and two end triangles
			var xo: float = p.x + sx * (sz.x * 0.5 + 4.5)
			var xw: float = p.x + sx * (sz.x * 0.5 + 0.02)
			var z0 := p.y - sz.z * 0.5
			var z1 := p.y + sz.z * 0.5
			var nrm: Vector3 = Vector3(sx * h * 0.85, 4.5, 0.0).normalized()
			mb.call(&"quad", Vector3(xo, 0.05, z0), Vector3(xo, 0.05, z1), Vector3(xw, h * 0.85, z1), Vector3(xw, h * 0.85, z0), nrm, berm)
			for zz: float in [z0, z1]:
				var en := Vector3(0.0, 0.0, -1.0 if zz == z0 else 1.0)
				mb.call(&"quad", Vector3(xo, 0.05, zz), Vector3(xw, 0.05, zz), Vector3(xw, h * 0.85, zz), Vector3(xw, h * 0.85, zz), en, berm)
	var c0: Vector3 = df["c"]
	var stripe := _yaw_box(c0 + out * 0.1 + Vector3(0.0, float(s["dh"]) + 0.5, 0.0), Vector3(float(s["dw"]), 0.5, 0.2), along)
	mb.call(&"box", stripe[0], stripe[1], AirportKit._c(Color(0.95, 0.6, 0.12), AirportKit.LAMP), false)


## A box given in the frame of a horizontal direction `dir` (size.x along dir's right, size.z along dir): an axis-aligned [centre, size] (dir is always an axis here).
static func _yaw_box(c: Vector3, size: Vector3, dir: Vector3) -> Array:
	if absf(dir.x) > 0.5:
		return [c, Vector3(size.z, size.y, size.x)]
	return [c, size]


## The door leaves of every site: one MultiMesh (two leaves a door), one AnimatableBody3D per leaf. Opens while the hero (or the vehicle he drives) is within OPEN_R of the door.
class Doors extends Node3D:
	static var instance: Doors
	var _open := {}                      ## site id -> 0..1
	var _bodies: Array[AnimatableBody3D] = []
	var _mm: MultiMesh
	var _leaf: Array[Dictionary] = []    ## per leaf: site, side (-1 / +1)
	var _lamps: Array = []               ## w128-airlook: [OmniLight3D, site] the lamps inside the hangars

	static func open_of(id: StringName) -> float:
		return float(instance._open.get(id, 0.0)) if is_instance_valid(instance) else 0.0

	func _ready() -> void:
		name = "HangarDoors"
		instance = self
		var mb := AirportKit.MB.new()
		mb.box(Vector3.ZERO, Vector3(1.0, 1.0, 1.0), AirportKit._c(Color(0.26, 0.28, 0.31), AirportKit.CLAD), true)
		for i in 5:
			mb.box(Vector3(0.0, -0.4 + 0.2 * float(i), 0.52), Vector3(0.96, 0.025, 0.04), AirportKit._c(Color(0.5, 0.52, 0.55), AirportKit.STEEL), false)
		var mesh := mb.build(BridgeKit.kit_material())
		for s: Dictionary in SITES:
			for side in [-1.0, 1.0]:
				_leaf.append({"site": s, "side": side})
		_mm = MultiMesh.new()
		_mm.transform_format = MultiMesh.TRANSFORM_3D
		_mm.mesh = mesh
		_mm.instance_count = _leaf.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Leaves"
		mmi.multimesh = _mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = 900.0
		add_child(mmi)
		for l: Dictionary in _leaf:
			var s2: Dictionary = l["site"]
			var b := AnimatableBody3D.new()
			b.sync_to_physics = false
			b.collision_layer = Game.L_WORLD
			b.collision_mask = 0
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(float(s2["dw"]) * 0.5 + 0.4, float(s2["dh"]), 0.4)
			cs.shape = bx
			b.add_child(cs)
			add_child(b)
			_bodies.append(b)
		_place()
		if Hangars.lights_on:                                                       # w128-airlook: the hangar lamps light the inside (it was lit by the sky ambient only: dark planes in a dark box)
			for st: Dictionary in SITES:
				var sp: Vector2 = st["pos"]
				var sz3: Vector3 = st["size"]
				for k in (2 if not bool(st["army"]) else 1):
					var lt := OmniLight3D.new()
					lt.name = "Lamp_%s_%d" % [st["id"], k]
					var off := 0.0 if bool(st["army"]) else (k - 0.5) * sz3.z * 0.45
					lt.position = Vector3(sp.x, sz3.y - 1.6, sp.y + off)
					lt.omni_range = maxf(sz3.x, sz3.z) * (0.62 if not bool(st["army"]) else 0.8)
					lt.omni_attenuation = 0.6
					lt.light_energy = Hangars.LAMP_ENERGY
					lt.light_color = Color(1.0, 0.95, 0.86)
					lt.shadow_enabled = false
					lt.light_specular = 0.4
					lt.visible = false
					add_child(lt)
					_lamps.append([lt, st])

	func _exit_tree() -> void:
		if instance == self:
			instance = null

	func _physics_process(dt: float) -> void:
		var hero := Game.player as Node3D
		if not is_instance_valid(hero):
			return
		var hp := hero.global_position
		var lp := Airport.to_local(hp)
		var moved := false
		for s: Dictionary in SITES:
			var df := Hangars.door_frame(s)
			var c: Vector3 = df["c"]
			var want := 1.0 if (Vector2(lp.x - c.x, lp.z - c.z).length() < OPEN_R or Hangars.inside(s, lp)) else 0.0
			var o := float(_open.get(s["id"], 0.0))
			var o2 := move_toward(o, want, DOOR_SPEED * dt)
			if o2 != o:
				_open[s["id"]] = o2
				moved = true
		if moved:
			_place()
		for e: Array in _lamps:                                              # w128-airlook: a hangar's lamps are on while the hero is within LAMP_NEAR m of it
			var st2: Dictionary = e[1]
			var sp2: Vector2 = st2["pos"]
			var near := Vector2(lp.x - sp2.x, lp.z - sp2.y).length() < Hangars.LAMP_NEAR
			if (e[0] as OmniLight3D).visible != near:
				(e[0] as OmniLight3D).visible = near

	## Leaf transforms: shut, the two leaves meet in the middle of the opening; open, each slides out along the face past the jamb (on rails in front of the wall).
	func _place() -> void:
		for i in _leaf.size():
			var l: Dictionary = _leaf[i]
			var s: Dictionary = l["site"]
			var df := Hangars.door_frame(s)
			var dw := float(s["dw"])
			var dh := float(s["dh"])
			var o := float(_open.get(s["id"], 0.0))
			var side: float = l["side"]
			var along: Vector3 = df["along"]
			var out: Vector3 = df["out"]
			var lw := dw * 0.5 + 0.4
			var off := side * (dw * 0.25 + o * dw * 0.5)
			var pos: Vector3 = (df["c"] as Vector3) + along * off + out * (0.45 + (0.35 if side > 0.0 else 0.0)) + Vector3(0.0, dh * 0.5, 0.0)
			var basis := Basis.looking_at(-out, Vector3.UP)       # local x along the face, z out of it
			var xf := Transform3D(basis * Basis.from_scale(Vector3(lw, dh, 0.4)), pos)
			_mm.set_instance_transform(i, xf)
			_bodies[i].transform = Transform3D(basis, pos)
