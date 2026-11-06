extends RefCounted
## Streamed collision chunks of the outer districts (wave 84, big city).
##
## The original 8 x 8 core keeps its building colliders for good (they are part of `City.collision_body`). The 192 outer blocks of the 16 x 16 map
## would add about 1,300 box shapes that nobody can reach at the same time, so they are generated and freed by distance instead: a block (one
## StaticBody3D on layer world, shapes = the boxes of its buildings) exists while the follow point (player, or the camera) is within RADIUS of the block
## centre and goes back to the pool when it is further than KEEP. Bodies and shape nodes are POOLED: a freed body keeps its shape nodes (disabled, parked
## below the map) and is handed to the next block, so after the first minutes of play no node is created or freed while the player crosses the city and the
## number of live shapes depends on where the player stands, not on the size of the city.
##
## Refreshing costs a distance test per outer block (192) every STEP metres and at most PER_FRAME block (re)assignments per call; a teleport
## (`refill`) assigns everything around the new point at once so there is never a hole to fall through.

const BM := preload("res://scripts/world/building_meshes.gd")

const RADIUS := 300.0               ## blocks closer than this to the follow point have colliders (about 10 s of driving at 28 m/s)
const KEEP := 380.0                 ## ... and keep them until they are this far away (hysteresis: no churn at the border)
const STEP := 20.0                  ## re-evaluate when the follow point has moved this far
const PER_FRAME := 4                ## block assignments per call outside a refill
const PARK := Vector3(0.0, -1500.0, 0.0)

var root: Node3D
var _boxes := {}                    ## block key (i * N + j) -> Array of [center: Vector3, size: Vector3]
var _centres := {}                  ## block key -> Vector2
var _keys: Array[int] = []          ## the outer block keys, fixed order
var active := {}                    ## block key -> body
var _free: Array[StaticBody3D] = [] ## pooled bodies (shapes disabled)
var _all: Array[StaticBody3D] = []  ## every body ever made (pool + active)
var _shapes := {}                   ## body -> Array[CollisionShape3D]
var _last := Vector2(1.0e9, 1.0e9)
var assigned := 0                   ## block assignments so far (tests)
var released := 0                   ## blocks sent back to the pool so far (tests)
var created_shapes := 0             ## shape nodes ever created (pooling keeps this bounded)
var enabled := true                 ## false: nothing is assigned (tests that want the bare world)


func build(parent: Node3D, layout: CityLayout, building_data: Array) -> void:
	root = Node3D.new()
	root.name = "OuterChunks"
	parent.add_child(root)
	_boxes.clear()
	_centres.clear()
	_keys.clear()
	for b in building_data:
		var lot: CityLayout.Lot = b.lot
		if CityLayout.is_core_block(lot.block_i, lot.block_j):
			continue
		var key := lot.block_i * CityLayout.N + lot.block_j
		if not _boxes.has(key):
			_boxes[key] = []
			_centres[key] = Vector2(-CityLayout.HALF + (lot.block_i + 0.5) * CityLayout.PITCH, -CityLayout.HALF + (lot.block_j + 0.5) * CityLayout.PITCH)
			_keys.append(key)
		var arr: Array = _boxes[key]
		arr.append_array(BM.collision_boxes(b.cls, lot.cx, lot.cz, lot.w, lot.d, lot.h))
	_keys.sort()


## Blocks with a collider body right now.
func active_count() -> int:
	return active.size()


## Live (enabled) shapes of the active blocks.
func shape_count() -> int:
	var n := 0
	for key: int in active:
		n += (_boxes[key] as Array).size()
	return n


## Block count of the outer districts (what a non-streamed world would keep alive).
func block_total() -> int:
	return _keys.size()


func is_active(i: int, j: int) -> bool:
	return active.has(i * CityLayout.N + j)


## Shape nodes that exist (live and pooled): bounded by the largest neighbourhood the player has stood in.
func pooled_shapes() -> int:
	var n := 0
	for body in _all:
		n += (_shapes[body] as Array).size()
	return n


## Follow the player (or camera) at `p`: assign blocks that came into RADIUS, release blocks beyond KEEP.
func follow(p: Vector3) -> void:
	if not enabled or _keys.is_empty():
		return
	var q := Vector2(p.x, p.z)
	if q.distance_to(_last) < STEP and not active.is_empty():
		return
	_last = q
	_update(q, PER_FRAME)


## Assign every block around `p` now and release the far ones (teleports, respawns, tests).
func refill(p: Vector3) -> void:
	if not enabled or _keys.is_empty():
		return
	var q := Vector2(p.x, p.z)
	_last = q
	_update(q, 1 << 20)


## Every outer block gets its colliders (tests of the whole map; the pool grows to the whole city).
func activate_all() -> void:
	for key in _keys:
		if not active.has(key):
			_assign(key)


func _update(q: Vector2, budget: int) -> void:
	for key in active.keys():                                   # release first, so the pool serves the blocks that come into range
		if (_centres[key] as Vector2).distance_to(q) > KEEP:
			_release(key)
	var wanted: Array = []
	for key in _keys:
		if active.has(key):
			continue
		var d := (_centres[key] as Vector2).distance_to(q)
		if d <= RADIUS:
			wanted.append([d, key])
	if wanted.is_empty():
		return
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for w: Array in wanted:
		if budget <= 0:
			_last = Vector2(1.0e9, 1.0e9)                       # more are waiting: try again next call
			return
		_assign(int(w[1]))
		budget -= 1


func _assign(key: int) -> void:
	var body: StaticBody3D
	if _free.is_empty():
		body = StaticBody3D.new()
		body.name = "Chunk%d" % _all.size()
		body.collision_layer = Game.L_WORLD
		body.collision_mask = 0
		root.add_child(body)
		_all.append(body)
		_shapes[body] = []
	else:
		body = _free.pop_back()
	var shapes: Array = _shapes[body]
	var boxes: Array = _boxes[key]
	while shapes.size() < boxes.size():
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		cs.disabled = true
		body.add_child(cs)
		shapes.append(cs)
		created_shapes += 1
	for k in boxes.size():
		var cs: CollisionShape3D = shapes[k]
		(cs.shape as BoxShape3D).size = boxes[k][1]
		cs.position = boxes[k][0]
		cs.disabled = false
	body.set_meta(&"block", key)
	active[key] = body
	assigned += 1


func _release(key: int) -> void:
	var body: StaticBody3D = active[key]
	for cs: CollisionShape3D in _shapes[body]:
		if not cs.disabled:
			cs.disabled = true
			cs.position = PARK
	active.erase(key)
	_free.append(body)
	released += 1
