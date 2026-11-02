extends RefCounted
## Pooled colliders for street furniture and roof clutter. The static city keeps no collider per prop (thousands of shapes), so instead a small constant
## pool of StaticBody3D (layer world, one shape node each whose shape resource is swapped between a box, a capsule and a cylinder) follows the player: every few metres the nearest
## collidable instances (lamp poles, signal poles, dumpsters, kiosks, bus shelters, hydrants, barriers, planters, roof houses / AC units / tanks / cover walls)
## are assigned to the pool bodies. The shape count never changes after build(); a body that is not in use is parked far below the city with its shapes off.
## The source data is the full MultiMesh buffer of each family (read once at build time, before city_stream.gd windows it).

const KitSpecs := preload("res://scripts/world/city_kit.gd")

const POOL := 56                      ## bodies, one CollisionShape3D each (56 shapes, constant)
const REACH := 38.0                   ## metres (XZ) around the follow point that can receive colliders
const VERT := 14.0                    ## colliders further than this above / below the follow point are ignored (roofs over the street)
const CELL := 16.0
const STEP := 2.0                     ## refresh when the follow point moved this far ...
const MAX_AGE := 0.35                 ## ... or after this many seconds while moving
const PARK := Vector3(0.0, -1000.0, 0.0)
const THIN := ["Barriers", "RoofCover", "Planters"]   ## thin families: the pool body joins group "thin_wall" (phase-through) while it stands for one

enum Shape { BOX, CAPSULE, CYLINDER }

## Per family: [shape, size, centre offset]. BOX: full size (x, y, z) in the instance frame; CAPSULE / CYLINDER: (radius, height, 0).
const SPECS := {
	"Lamps": [Shape.CAPSULE, Vector3(0.2, 7.4, 0.0), Vector3(0.0, 3.7, 0.0)],
	"Signals": [Shape.CAPSULE, Vector3(0.18, 5.1, 0.0), Vector3(0.0, 2.55, 0.0)],
	"BusStops": [Shape.BOX, Vector3(3.3, 2.5, 1.0), Vector3(0.0, 1.25, -0.3)],
	"Kiosks": [Shape.BOX, Vector3(2.4, 2.6, 1.7), Vector3(0.0, 1.3, 0.0)],
	"Dumpsters": [Shape.BOX, Vector3(1.9, 1.25, 1.0), Vector3(0.0, 0.62, 0.0)],
	"Hydrants": [Shape.CYLINDER, Vector3(0.22, 0.85, 0.0), Vector3(0.0, 0.42, 0.0)],
	"Barriers": [Shape.BOX, Vector3(0.6, 0.85, 2.4), Vector3(0.0, 0.42, 0.0)],
	"Planters": [Shape.BOX, Vector3(2.2, 0.95, 0.9), Vector3(0.0, 0.47, 0.0)],
	"RoofHouses": [Shape.BOX, Vector3(3.6, 3.0, 3.2), Vector3(0.0, 1.5, 0.0)],
	"RoofAC": [Shape.BOX, Vector3(2.06, 1.05, 1.16), Vector3(0.0, 0.52, 0.0)],
	"RoofTanks": [Shape.CYLINDER, Vector3(1.6, 5.2, 0.0), Vector3(0.0, 2.6, 0.0)],
	"RoofCover": [Shape.BOX, Vector3(3.0, 1.15, 0.34), Vector3(0.0, 0.57, 0.0)],
	"RoofVents": [Shape.BOX, Vector3(2.4, 1.4, 2.4), Vector3(0.0, 0.7, 0.0)],
}

var bodies: Array[StaticBody3D] = []
var root: Node3D
## number of source instances (all families), for tests and stats
var source_count := 0
## pool bodies currently assigned to an instance
var in_use := 0
## how many times the pool was refilled (tests)
var refills := 0
var last_follow := Vector3.INF

var _xf: Array[Transform3D] = []          ## world transform (without scale) of each source instance
var _spec: PackedInt32Array = PackedInt32Array()
var _spec_list: Array = []                 ## [shape, size, offset, family name]
var _grid := {}                            ## cell key -> PackedInt32Array of source ids
var _assigned := PackedInt32Array()        ## per body: source id or -1
var _shapes: Array = []                    ## per body: [CollisionShape3D, [box, capsule, cylinder resources]]
var enabled := true                        ## false: the pool stays parked (tests that need the bare buildings)
var _age := 0.0


static func spec_for(family_name: String) -> Array:
	return SPECS.get(family_name, [])


## Read every collidable family out of the props builder's parts ({name, mm, ...}) and create the pool under `parent`.
## `extra`: more collidable instances that do not live in a MultiMesh (the street kit window): family name -> Array[Transform3D]; the shapes come from `Kit.collider_spec`.
func build(parent: Node3D, parts: Array[Dictionary], extra: Dictionary = {}) -> void:
	_xf.clear()
	_grid.clear()
	_spec_list.clear()
	var spec_ids := {}
	var spec_tmp: Array[int] = []
	for part: Dictionary in parts:
		var fname: String = part.get("name", "")
		if not SPECS.has(fname):
			continue
		var mm: MultiMesh = part["mm"]
		var stride := 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
		var buf := mm.buffer
		var sp: Array = SPECS[fname]
		var si := _spec_list.size()
		_spec_list.append([sp[0], sp[1], sp[2], fname])
		spec_ids[fname] = si
		for i in mm.instance_count:
			var o := i * stride
			var b := Basis(Vector3(buf[o], buf[o + 4], buf[o + 8]), Vector3(buf[o + 1], buf[o + 5], buf[o + 9]), Vector3(buf[o + 2], buf[o + 6], buf[o + 10])).orthonormalized()
			var p := Vector3(buf[o + 3], buf[o + 7], buf[o + 11])
			var id := _xf.size()
			_xf.append(Transform3D(b, p))
			spec_tmp.append(si)
			var key := _key(p.x, p.z)
			var arr: PackedInt32Array = _grid.get(key, PackedInt32Array())
			arr.append(id)
			_grid[key] = arr
	for fam: String in extra:
		var sp2: Array = KitSpecs.collider_spec(fam)
		if sp2.is_empty():
			continue
		var si2 := _spec_list.size()
		_spec_list.append([sp2[0], sp2[1], sp2[2], fam])
		for xf: Transform3D in extra[fam]:
			var id2 := _xf.size()
			_xf.append(xf)
			spec_tmp.append(si2)
			var key2 := _key(xf.origin.x, xf.origin.z)
			var arr2: PackedInt32Array = _grid.get(key2, PackedInt32Array())
			arr2.append(id2)
			_grid[key2] = arr2
	_spec = PackedInt32Array(spec_tmp)
	source_count = _xf.size()
	if root == null:
		_make_pool(parent)
	park_all()


func _make_pool(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "PropColliders"
	parent.add_child(root)
	_assigned.resize(POOL)
	for k in POOL:
		var body := StaticBody3D.new()
		body.name = "PropCollider%d" % k
		body.collision_layer = Game.L_WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.disabled = true
		body.add_child(cs)
		var trio: Array = [cs, [BoxShape3D.new(), CapsuleShape3D.new(), CylinderShape3D.new()]]
		body.position = PARK
		root.add_child(body)
		bodies.append(body)
		_shapes.append(trio)
		_assigned[k] = -1


static func _key(x: float, z: float) -> int:
	return (int(floor((x + 400.0) / CELL)) << 10) | int(floor((z + 400.0) / CELL))


## Total collision shapes owned by the pool (constant).
func shape_count() -> int:
	var n := 0
	for b in bodies:
		for c in b.get_children():
			if c is CollisionShape3D:
				n += 1
	return n


func park_all() -> void:
	in_use = 0
	last_follow = Vector3.INF
	for k in bodies.size():
		_release(k)


## Call every physics frame with the point the pool should surround (null / INF = park everything). Cheap: it only works when the point moved.
func follow(p: Vector3, delta: float, force := false) -> void:
	if p == Vector3.INF or not enabled:
		return
	_age += delta
	var moved := Vector2(p.x - last_follow.x, p.z - last_follow.z).length() if last_follow != Vector3.INF else 1.0e9
	if not force and moved < STEP and (_age < MAX_AGE or moved < 0.01) and absf(p.y - last_follow.y) < 3.0:
		return
	_age = 0.0
	refill(p)


## Assign the nearest collidable instances within REACH of p to the pool bodies.
func refill(p: Vector3) -> void:
	if not enabled:
		park_all()
		return
	refills += 1
	last_follow = p
	var cands: Array[Vector2] = []
	var c0x := int(floor((p.x - REACH + 400.0) / CELL))
	var c1x := int(floor((p.x + REACH + 400.0) / CELL))
	var c0z := int(floor((p.z - REACH + 400.0) / CELL))
	var c1z := int(floor((p.z + REACH + 400.0) / CELL))
	var r2 := REACH * REACH
	for cx in range(c0x, c1x + 1):
		for cz in range(c0z, c1z + 1):
			var arr: PackedInt32Array = _grid.get((cx << 10) | cz, PackedInt32Array())
			for id in arr:
				var o := _xf[id].origin
				if absf(o.y - p.y) > VERT:
					continue
				var dx := o.x - p.x
				var dz := o.z - p.z
				var d2 := dx * dx + dz * dz
				if d2 <= r2:
					cands.append(Vector2(d2, float(id)))
	cands.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var want := {}
	var n := mini(cands.size(), POOL)
	for k in n:
		want[int(cands[k].y)] = true
	# keep bodies whose instance is still wanted, free the rest
	var free: Array[int] = []
	var have := {}
	for k in bodies.size():
		var src := _assigned[k]
		if src >= 0 and want.has(src):
			have[src] = k
		else:
			if src >= 0:
				_release(k)
			free.append(k)
	var fi := 0
	for k in n:
		var src := int(cands[k].y)
		if have.has(src):
			continue
		_assign(free[fi], src)
		fi += 1
	in_use = n


func _release(k: int) -> void:
	_assigned[k] = -1
	(_shapes[k][0] as CollisionShape3D).disabled = true
	bodies[k].position = PARK
	bodies[k].remove_from_group(&"thin_wall")


func _assign(k: int, src: int) -> void:
	_assigned[k] = src
	var sp: Array = _spec_list[_spec[src]]
	var xf := _xf[src]
	var which: int = sp[0]
	var size: Vector3 = sp[1]
	var cs: CollisionShape3D = _shapes[k][0]
	var res: Shape3D = (_shapes[k][1] as Array)[which]
	match which:
		Shape.BOX:
			(res as BoxShape3D).size = size
		Shape.CAPSULE:
			var cap := res as CapsuleShape3D
			cap.radius = size.x
			cap.height = maxf(size.y, size.x * 2.0 + 0.01)
		_:
			var cyl := res as CylinderShape3D
			cyl.radius = size.x
			cyl.height = size.y
	cs.shape = res
	cs.disabled = false
	var body := bodies[k]
	body.transform = Transform3D(xf.basis, xf.origin + xf.basis * (sp[2] as Vector3))
	if THIN.has(sp[3]):
		body.add_to_group(&"thin_wall")
	else:
		body.remove_from_group(&"thin_wall")


## World transforms of every source instance of a family (for tests and gameplay queries such as "find cover").
func instances_of(family_name: String) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for id in _xf.size():
		if String((_spec_list[_spec[id]] as Array)[3]) == family_name:
			out.append(_xf[id])
	return out


## Family name of the instance a body currently stands for ("" when parked); for tests.
func family_of(k: int) -> String:
	var src := _assigned[k]
	return "" if src < 0 else String((_spec_list[_spec[src]] as Array)[3])
