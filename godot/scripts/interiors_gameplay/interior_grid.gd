class_name InteriorGrid
extends RefCounted
## A small walkability grid of the interior the hero stands in, taken from InteriorSpace (the same solids the enemies obey) on a 0.3 m grid: breadth-first reachability from a point,
## "how close can the hero get to this spot", and the corridor test of the quantum puzzles (extra solid rectangles can be stamped in before the search). Built once per room
## (about 2000 cells, a few milliseconds); every query after that is a flat array walk. Pure geometry: no nodes, no physics.
##   var g := InteriorGrid.of(room); g.stamp(Rect2(...)); g.flood(door_pos); g.gap(object_pos) <= reach

const CELL := 0.3
const RADIUS := 0.34

var origin := Vector2.ZERO
var cols := 0
var rows := 0
var solid := PackedByteArray()
var seen := PackedByteArray()


## The grid of `room` (an Interior node: `bounds` and the registered InteriorSpace solids).
static func of(room: Node3D) -> InteriorGrid:
	var g := InteriorGrid.new()
	var b := (room.get("bounds") as Rect2).grow(0.3)
	g.origin = b.position
	g.cols = int(ceilf(b.size.x / CELL))
	g.rows = int(ceilf(b.size.y / CELL))
	g.solid.resize(g.cols * g.rows)
	for y in g.rows:
		for x in g.cols:
			var c := g.centre(x, y)
			g.solid[y * g.cols + x] = 1 if InteriorSpace.blocked(c.x, c.y, RADIUS) else 0
	return g


func centre(x: int, y: int) -> Vector2:
	return Vector2(origin.x + (float(x) + 0.5) * CELL, origin.y + (float(y) + 0.5) * CELL)


func copy() -> InteriorGrid:
	var g := InteriorGrid.new()
	g.origin = origin
	g.cols = cols
	g.rows = rows
	g.solid = solid.duplicate()
	return g


## Marks every cell a body of the hero's radius would touch inside `r` (world x / z) as solid.
func stamp(r: Rect2) -> void:
	var rr := r.grow(RADIUS)
	var x0 := maxi(0, int(floorf((rr.position.x - origin.x) / CELL)))
	var x1 := mini(cols - 1, int(floorf((rr.end.x - origin.x) / CELL)))
	var y0 := maxi(0, int(floorf((rr.position.y - origin.y) / CELL)))
	var y1 := mini(rows - 1, int(floorf((rr.end.y - origin.y) / CELL)))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if rr.has_point(centre(x, y)):
				solid[y * cols + x] = 1


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floorf((p.x - origin.x) / CELL)), int(floorf((p.y - origin.y) / CELL)))


func _free_near(c: Vector2i) -> int:
	for r in 8:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var x := c.x + dx
				var y := c.y + dy
				if x >= 0 and y >= 0 and x < cols and y < rows and solid[y * cols + x] == 0:
					return y * cols + x
	return -1


## Flood fill (8 neighbours, no corner cutting) from the free cell nearest to `from`. Returns the number of reachable cells.
func flood(from: Vector3) -> int:
	seen = PackedByteArray()
	seen.resize(cols * rows)
	var start := _free_near(cell_of(Vector2(from.x, from.z)))
	if start < 0:
		return 0
	var queue: Array[int] = [start]
	seen[start] = 1
	var head := 0
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
			if solid[j] != 0 or seen[j] != 0:
				continue
			if dx != 0 and dy != 0 and (solid[cy * cols + nx] != 0 or solid[ny * cols + cx] != 0):
				continue
			seen[j] = 1
			queue.append(j)
	return queue.size()


## After flood(): the distance (metres) from `p` to the nearest reachable cell centre within `max_d` (INF when none).
func gap(p: Vector3, max_d := 6.0) -> float:
	var c := cell_of(Vector2(p.x, p.z))
	var span := int(ceilf(max_d / CELL))
	var best := INF
	for dy in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var x := c.x + dx
			var y := c.y + dy
			if x < 0 or y < 0 or x >= cols or y >= rows or seen[y * cols + x] == 0:
				continue
			best = minf(best, centre(x, y).distance_to(Vector2(p.x, p.z)))
	return best


## True when the cell under `p` is free (not solid).
func free_at(p: Vector3) -> bool:
	var c := cell_of(Vector2(p.x, p.z))
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows and solid[c.y * cols + c.x] == 0
