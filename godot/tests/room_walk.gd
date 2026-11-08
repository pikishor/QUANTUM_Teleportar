extends RefCounted
## Room walking for bots and audits (interior tasks): a walkability grid of the CURRENT interior taken from the real physics world (the hero's own capsule swept over a 0.25 m grid
## against the world layer, so furniture, walls and the quantum puzzle corridor all count), a breadth-first search over it, and a path the bot can follow with real input.
##   var rw := RoomWalk.new(); rw.build(interior, space_state, exclude_rids); rw.reachable(door_pos); rw.reach_gap(target)
## Cells are CELL metres. A cell is blocked when a cylinder the size of the hero hits anything on Game.L_WORLD (the puzzle gates' barriers are excluded on request: they open with USE).

const CELL := 0.25
const RADIUS := 0.36
const HEIGHT := 1.5

var origin := Vector2.ZERO
var cols := 0
var rows := 0
var blocked := PackedByteArray()
var dist := PackedInt32Array()
var clear := PackedInt32Array()          ## cells to the nearest blocked cell (capped), for the centre-line preference
var parent := PackedInt32Array()
var start_cell := -1
var radius := RADIUS                    ## the swept cylinder's radius (a planning grid uses a wider one so a path keeps clear of corners)


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floorf((p.x - origin.x) / CELL)), int(floorf((p.z - origin.y) / CELL)))


func idx(c: Vector2i) -> int:
	return c.y * cols + c.x


func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows


func centre_of(c: Vector2i) -> Vector3:
	return Vector3(origin.x + (float(c.x) + 0.5) * CELL, 0.0, origin.y + (float(c.y) + 0.5) * CELL)


## Sweep the physics world over `bounds` (a Rect2 in world x, z). `exclude`: RIDs of bodies that do not count (open gates).
func build(bounds: Rect2, space: PhysicsDirectSpaceState3D, exclude: Array[RID] = []) -> void:
	origin = bounds.position
	cols = int(ceilf(bounds.size.x / CELL))
	rows = int(ceilf(bounds.size.y / CELL))
	blocked = PackedByteArray()
	blocked.resize(cols * rows)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = Game.L_WORLD
	q.exclude = exclude
	q.margin = 0.0
	for y in rows:
		for x in cols:
			var c := centre_of(Vector2i(x, y))
			q.transform = Transform3D(Basis.IDENTITY, Vector3(c.x, 0.1 + HEIGHT * 0.5, c.z))
			var hit := space.intersect_shape(q, 1)
			blocked[y * cols + x] = 1 if not hit.is_empty() else 0


## Cheapest-path search (8 neighbours, no corner cutting) from the walkable cell nearest to `from`. A step costs its length times (1 + a penalty that grows as the cell gets close to a wall), so a path
## runs down the middle of a doorway or an aisle instead of hugging its corner. Returns the number of reachable cells; `dist` is >= 0 on a reachable cell.
func reachable(from: Vector3) -> int:
	_ensure_clearance()
	dist = PackedInt32Array()
	dist.resize(cols * rows)
	dist.fill(-1)
	parent = PackedInt32Array()
	parent.resize(cols * rows)
	parent.fill(-1)
	var cost := PackedFloat32Array()
	cost.resize(cols * rows)
	cost.fill(1.0e9)
	start_cell = _nearest_free(cell_of(from))
	if start_cell < 0:
		return 0
	var queue: Array[int] = [start_cell]
	cost[start_cell] = 0.0
	dist[start_cell] = 0
	var head := 0
	var n := 1
	while head < queue.size():
		var i := queue[head]
		head += 1
		var cx := i % cols
		var cy := i / cols
		for d in 8:
			var dx: int = [1, -1, 0, 0, 1, 1, -1, -1][d]
			var dy: int = [0, 0, 1, -1, 1, -1, 1, -1][d]
			var nx := cx + dx
			var ny := cy + dy
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var j := ny * cols + nx
			if blocked[j] != 0:
				continue
			if dx != 0 and dy != 0 and (blocked[cy * cols + nx] != 0 or blocked[ny * cols + cx] != 0):
				continue
			var step := (1.0 if dx == 0 or dy == 0 else 1.4142) * (1.0 + 2.5 * clampf((3.0 - float(clear[j])) / 3.0, 0.0, 1.0))
			var c := cost[i] + step
			if c + 0.0001 < cost[j]:
				if dist[j] < 0:
					n += 1
				cost[j] = c
				dist[j] = 1
				parent[j] = i
				queue.append(j)                         # relaxed again: a cell may be queued more than once, the cheapest parent wins
	return n


## Distance (in cells, capped) from every cell to the nearest blocked one: filled once per grid.
func _ensure_clearance() -> void:
	if clear.size() == cols * rows:
		return
	clear = PackedInt32Array()
	clear.resize(cols * rows)
	clear.fill(9)
	var q: Array[int] = []
	for i in cols * rows:
		if blocked[i] != 0:
			clear[i] = 0
			q.append(i)
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		if clear[i] >= 4:
			continue
		var cx := i % cols
		var cy := i / cols
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := cx + dx
				var ny := cy + dy
				if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
					continue
				var j := ny * cols + nx
				if clear[j] > clear[i] + 1:
					clear[j] = clear[i] + 1
					q.append(j)


func _nearest_free(c: Vector2i) -> int:
	for r in 12:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := Vector2i(c.x + dx, c.y + dy)
				if inside(q) and blocked[idx(q)] == 0:
					return idx(q)
	return -1


## The smallest horizontal distance (metres) from `target` to any reachable cell: 0 when the target stands on a reachable cell. INF when nothing is reachable.
func reach_gap(target: Vector3) -> float:
	var best := INF
	var c := cell_of(target)
	var span := 24                                     # cells (6 m) around the target are enough for every reach in the game
	for dy in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var q := Vector2i(c.x + dx, c.y + dy)
			if not inside(q) or dist[idx(q)] < 0:
				continue
			var cc := centre_of(q)
			var d := Vector2(cc.x - target.x, cc.z - target.z).length()
			best = minf(best, d)
	return best


## The reachable cell centre nearest to `target` that is within `reach` of it (or the nearest reachable one when none is). Vector3.INF without any.
func goal_near(target: Vector3, reach: float) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	var c := cell_of(target)
	var span := int(ceilf((reach + 1.0) / CELL))
	for dy in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var q := Vector2i(c.x + dx, c.y + dy)
			if not inside(q) or dist[idx(q)] < 0:
				continue
			var cc := centre_of(q)
			var d := Vector2(cc.x - target.x, cc.z - target.z).length()
			var score := d if d <= reach else d + 100.0
			if score < bd:
				bd = score
				best = cc
	return best


## Waypoints (every cell centre) from the search start to `goal`; empty when the goal is not reachable.
func path_to(goal: Vector3) -> PackedVector3Array:
	var c := cell_of(goal)
	var out := PackedVector3Array()
	if not inside(c) or dist[idx(c)] < 0:
		return out
	var cells: Array[int] = []
	var i := idx(c)
	var guard := 0
	while i >= 0 and guard < cols * rows:
		cells.push_front(i)
		i = parent[i]
		guard += 1
	for k in cells.size():
		out.append(centre_of(Vector2i(cells[k] % cols, cells[k] / cols)))
	return out
