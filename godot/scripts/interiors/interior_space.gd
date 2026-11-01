class_name InteriorSpace
extends RefCounted
## What the rest of the game may ask about the interior the player is standing in (at most one exists at a time). The Interior node registers itself when it enters the tree and
## unregisters when it leaves, so every query below is a cheap test on flat arrays (no allocation) and means "no interior" (false / the input) when nothing is registered.
##   contains(p)        the point is inside the interior's volume: the city rescue ("outside the walls") and the blink clamp must leave it alone
##   resolve(...)       an enemy step against the walls and props (slides along them): enemies are moved by code, not by physics, so they need this to stay in the rooms
##   cover_spot(...)    a spot behind a prop (as seen from the threat) for the enemy cover search
##   floor_y            the height enemies stand at

static var active := false
static var bounds := Rect2()                 ## world x/z rectangle (walls included)
static var floor_y := 0.0
static var min_y := 0.0
static var max_y := 0.0
static var _rects := PackedFloat32Array()    ## x0, z0, x1, z1 of every solid at body height (walls, posts, the closed street door, big props), world coordinates
static var _covers := PackedFloat32Array()   ## x, z, radius, height of the props an enemy can hide behind
static var _owner: Object = null


static func register(owner: Object, p_bounds: Rect2, p_floor_y: float, ceiling: float, rects: PackedFloat32Array, covers: PackedFloat32Array) -> void:
	_owner = owner
	active = true
	bounds = p_bounds
	floor_y = p_floor_y
	min_y = p_floor_y - 2.0
	max_y = p_floor_y + ceiling + 2.0
	_rects = rects
	_covers = covers


static func unregister(owner: Object) -> void:
	if _owner == owner:
		clear()


static func clear() -> void:
	_owner = null
	active = false
	bounds = Rect2()
	_rects = PackedFloat32Array()
	_covers = PackedFloat32Array()


static func contains(p: Vector3) -> bool:
	return active and p.y > min_y and p.y < max_y and bounds.grow(3.0).has_point(Vector2(p.x, p.z))


## True when a body of radius r centred at (x, z) overlaps a solid.
static func blocked(x: float, z: float, r: float) -> bool:
	var n := _rects.size()
	var i := 0
	while i < n:
		if x > _rects[i] - r and x < _rects[i + 2] + r and z > _rects[i + 1] - r and z < _rects[i + 3] + r:
			return true
		i += 4
	return false


## The step from (px, pz) to (nx, nz) of a body with radius r: the same point when free, else slid along the wall (one axis cancelled), else the old point.
static func resolve(px: float, pz: float, nx: float, nz: float, r: float) -> Vector2:
	if not blocked(nx, nz, r):
		return Vector2(nx, nz)
	if blocked(px, pz, r):
		return Vector2(nx, nz)          # already inside something (spawned in a doorway): never trap the body
	if not blocked(nx, pz, r):
		return Vector2(nx, pz)
	if not blocked(px, nz, r):
		return Vector2(px, nz)
	return Vector2(px, pz)


## A cover spot for `from` against `threat` within `radius`: behind the nearest tall prop as seen from the threat (one prop radius plus a stand-off further out), or Vector3.INF.
static func cover_spot(from: Vector3, threat: Vector3, radius := 18.0, min_threat := 3.0) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	var n := _covers.size()
	var i := 0
	while i < n:
		var cx := _covers[i]
		var cz := _covers[i + 1]
		var cr := _covers[i + 2]
		i += 4
		var ax := cx - threat.x
		var az := cz - threat.z
		var al := sqrt(ax * ax + az * az)
		if al < 0.1:
			continue
		var sx := cx + ax / al * (cr + 0.75)
		var sz := cz + az / al * (cr + 0.75)
		var dt := Vector2(sx - threat.x, sz - threat.z).length()
		var dd := Vector2(sx - from.x, sz - from.z).length()
		if dd > radius or dt < min_threat or dt < dd * 0.35 or blocked(sx, sz, 0.35) or not bounds.has_point(Vector2(sx, sz)):
			continue
		if dd < best_d:
			best_d = dd
			best = Vector3(sx, floor_y, sz)
	return best
