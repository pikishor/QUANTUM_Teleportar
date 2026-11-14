class_name StructureDamage
extends RefCounted
## STRUCTURE DAMAGE (wave 113, damage everywhere): what a blast does to the buildings, the street and the fences around it. BlastTable._run calls `StructureDamage.apply(pos, radius, level)` for every
## blast whose entry has a destruction `level` (0 none, 1 a grenade: windows go and the facade is chipped, 2 a rocket or a strike: chunks fall out of the facade and the street gets a crater, 3 a bunker
## buster or a heavy bomb: a wall is breached). The level of an entry is data in scripts/combat/blast_rows.gd (`level`), so every weapon has its own destruction level.
## The damage is STAGED per place: the places a blast touched are remembered (3 m cells, `stage_of`), so a second rocket on the same facade finishes what the first one began: stage points = level x level
## (1, 4, 9), a window breaks from stage 1, a chunk-loss scar from stage 3, a breach from stage 8.
## Everything it draws is pooled: marks in the structure pool of BlastMarks (LOW 8, MED 16, HIGH 24 live, the oldest is recycled), flying pieces in the shared debris pool of Breakables (one draw call
## for every system), dust in the shared puff cloud of BlastFx (one draw call), at most `Dmg.cap(&"wall_rays")` physics rays per blast (4 / 6 / 9). Nothing is allocated per frame, no node is created.
##   StructureDamage.apply(pos, radius, level)     the blast's effect (call it once per blast)
##   StructureDamage.stage_of(pos) -> int          0 untouched, 1 windows, 2 scarred, 3 breached: what this place of a facade has taken so far
##   StructureDamage.reset()                       new game: the places forget what they took
## Counters (tests wait on them): applied windows_broken chips_made breaches_made craters_made chunks_flung

const FLOOR_H := 3.5                       ## the facade shader's floor height and ground floor (building_core.gdshaderinc)
const GROUND_H := 5.0
const BAY_W := 2.6
const CELL := 3.0
const CELL_MAX := 96
const CELL_LIFE := 150.0
const POINTS := [0, 1, 4, 9]
const AT_WINDOW := 1
const AT_CHIP := 3
const AT_BREACH := 8
const CONCRETE := [Color(0.44, 0.42, 0.39), Color(0.34, 0.33, 0.31), Color(0.5, 0.48, 0.44)]
const BRICK := [Color(0.5, 0.27, 0.2), Color(0.42, 0.22, 0.17)]
const METAL := [Color(0.32, 0.34, 0.37), Color(0.5, 0.52, 0.55)]
const ASPHALT := [Color(0.16, 0.15, 0.14), Color(0.22, 0.2, 0.19)]

static var applied := 0
static var windows_broken := 0
static var chips_made := 0
static var breaches_made := 0
static var craters_made := 0
static var chunks_flung := 0
static var _cells: Dictionary = {}          ## Vector3i cell -> [points, time]
static var _windows: Dictionary = {}        ## Vector3i of a broken pane -> time
static var _rng := RandomNumberGenerator.new()
static var _seeded := false


static func reset() -> void:
	_cells.clear()
	_windows.clear()


static func reset_stats() -> void:
	applied = 0
	windows_broken = 0
	chips_made = 0
	breaches_made = 0
	craters_made = 0
	chunks_flung = 0


static func _now() -> float:
	return Time.get_ticks_msec() * 0.001


static func _key(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / CELL), floori(p.y / FLOOR_H), floori(p.z / CELL))


## 0 untouched, 1 windows broken, 2 scarred (chunks gone), 3 breached.
static func stage_of(pos: Vector3) -> int:
	var c: Variant = _cells.get(_key(pos))
	if c == null:
		return 0
	var pts: int = int((c as Array)[0])
	return 3 if pts >= AT_BREACH else (2 if pts >= AT_CHIP else (1 if pts >= AT_WINDOW else 0))


## The worst stage any place has reached (tests and bots).
static func top_stage() -> int:
	var best := 0
	for k: Vector3i in _cells:
		var pts: int = int((_cells[k] as Array)[0])
		best = maxi(best, 3 if pts >= AT_BREACH else (2 if pts >= AT_CHIP else (1 if pts >= AT_WINDOW else 0)))
	return best


static func _add_points(at: Vector3, level: int) -> int:
	var k := _key(at)
	var now := _now()
	var c: Array = _cells.get(k, [0, now])
	c[0] = int(c[0]) + int(POINTS[clampi(level, 0, 3)])
	c[1] = now
	_cells[k] = c
	if _cells.size() > CELL_MAX:
		var oldest := INF
		var ok: Vector3i = k
		for kk: Vector3i in _cells:
			var t: float = float((_cells[kk] as Array)[1])
			if t < oldest and kk != k:
				oldest = t
				ok = kk
		_cells.erase(ok)
	return int(c[0])


## The blast: `level` 1..3 (the table's `structure` number), `radius` m. Reads the entry of the blast that is running (BlastTable.last) for its element, its debris kind and its crater factor.
static func apply(pos: Vector3, radius: float, level: int) -> void:
	if not Dmg.enabled or level <= 0 or radius < 1.5 or FX == null or FX.marks == null:
		return
	var vp := Game.get_tree().root
	if vp == null or vp.world_3d == null:
		return
	var cam := vp.get_camera_3d()
	if cam != null and cam.global_position.distance_to(pos) > 170.0:
		return                                                      # nobody sees it: the old marks of the blast are all a far blast gets
	applied += 1
	var space := vp.world_3d.direct_space_state
	var e: Dictionary = BlastTable.entry(StringName(BlastTable.last.get("id", &"")))
	var crater_k := float(e.get("crater", 1.0))
	var debris_kind := StringName(e.get("debris", &"rubble"))
	var tier := Dmg.tier()
	var rng := _rng
	if not _seeded:
		_seeded = true
		rng.randomize()
	var power := clampf(radius / 6.0, 0.5, 1.8)
	var pieces: int = [3, 6, 10][tier]
	# --- the street: a crater from level 2, a ring of thrown earth
	if level >= 2 and crater_k > 0.0 and debris_kind != &"none":
		var g: Vector3 = FX.marks.ground_under(pos, 6.0)
		if g != Vector3.INF:
			var size := clampf(radius * (0.8 if level == 2 else 1.1) * clampf(crater_k, 0.5, 2.0), 1.6, 11.0)
			FX.marks.crater(g, size)
			craters_made += 1
			if debris_kind != &"sparks":
				_ring(g, radius, pieces, level)
	# --- the walls
	var rays: int = Dmg.cap(&"wall_rays")
	var reach := radius * 1.35 + 2.0
	var o := Vector3(pos.x, clampf(pos.y, 1.2, 5.0), pos.z)
	var base := rng.randf() * TAU
	var windows_left := Dmg.cap(&"windows")
	var chunk_walls := 2 if tier > 0 else 1
	var breaches_left := (2 if level >= 3 else 1) if level >= 2 else 0
	var showered := false
	for k in rays:
		var ang := base + TAU * float(k) / float(rays)
		var tilt := 0.0 if (k % 2 == 0) else 0.5                      # every other probe looks up: the floors above
		var dir := Vector3(cos(ang) * cos(tilt), sin(tilt), sin(ang) * cos(tilt))
		var q := PhysicsRayQueryParameters3D.create(o, o + dir * reach)
		q.collision_mask = Game.L_WORLD
		q.collide_with_areas = false
		var h := space.intersect_ray(q)
		if h.is_empty():
			continue
		var col := h["collider"] as Node
		if col != null and col.has_meta(&"bk_index"):
			continue                                                    # a prop (a crate, a barrier): Breakables.blast breaks those
		var n: Vector3 = h["normal"]
		if absf(n.y) > 0.5:
			continue
		var at: Vector3 = h["position"]
		var close := 1.0 - clampf(o.distance_to(at) / reach, 0.0, 1.0)
		if close < 0.12:
			continue
		var pts := _add_points(at, level)
		# windows: from stage 1, one pane per probe (the facade grid is 2.6 m bays, 3.5 m floors)
		if pts >= AT_WINDOW and windows_left > 0 and close > 0.18:
			if _window(at, n, close, level):
				windows_left -= 1
				if not showered:
					showered = true
					FX.marks.facade_shower(at, n, close * clampf(radius / 6.0, 0.5, 1.4))
					Sfx.impact(&"glass", at, n)
		# chunks out of the facade: stage 3
		if level >= 2 and pts >= AT_CHIP and chunk_walls > 0 and close > 0.3 and debris_kind != &"none":
			chunk_walls -= 1
			FX.marks.chip(at, n, clampf(radius * 0.4 * (0.5 + close), 0.9, 3.4))
			chips_made += 1
			_chunks(at, n, pieces, power * (0.6 + close * 0.6), debris_kind)
			_dust(at, n, radius, 1)
		# a breach: stage 8, the nearest facade of the blast
		if level >= 2 and pts >= AT_BREACH and breaches_left > 0 and close > 0.42 and debris_kind != &"none":
			breaches_left -= 1
			var by := clampf(at.y, 1.6, 14.0)
			FX.marks.breach(Vector3(at.x, by, at.z), n, clampf(radius * 0.55 * (0.7 + close), 1.9, 5.8))
			breaches_made += 1
			_chunks(Vector3(at.x, by, at.z), n, pieces + 2, power * 1.3, debris_kind)
			_dust(Vector3(at.x, by, at.z), n, radius, 2)
			Sfx.play_at(&"explosion_small", at, -6.0, 0.7)


## A pane of the facade at the hit goes: snapped to the facade grid, a dark room behind it. Returns false when that pane is already out.
static func _window(at: Vector3, n: Vector3, close: float, level: int) -> bool:
	var t := Vector3.UP.cross(n).normalized()
	var s := at.dot(t)
	var snapped := (floorf(s / BAY_W) + 0.5) * BAY_W
	var c := at + t * (snapped - s)
	var wh: float
	if at.y > GROUND_H:
		c.y = GROUND_H + (floorf((at.y - GROUND_H) / FLOOR_H) + 0.5) * FLOOR_H
		wh = 1.7
	else:
		c.y = 2.1
		wh = 2.5
	var key := Vector3i(roundi(c.x * 2.0), roundi(c.y * 2.0), roundi(c.z * 2.0))
	if _windows.has(key):
		return false
	_windows[key] = _now()
	if _windows.size() > CELL_MAX * 2:
		_windows.clear()
	var lit := _rng.randf() < 0.55
	var room := Color(1.0, 0.78, 0.45) if lit else Color(0.2, 0.3, 0.45)
	FX.marks.window_broken(c, n, BAY_W * 0.88, wh, clampf(0.4 + 0.5 * close + 0.1 * float(level), 0.35, 1.0), room)
	windows_broken += 1
	return true


## Pooled pieces flung out of a wall at `at` along `n`: concrete, brick or metal by the blast's debris kind.
static func _chunks(at: Vector3, n: Vector3, count: int, power: float, kind: StringName) -> void:
	var br := Breakables.current
	if br == null:
		return
	var rng := _rng
	var pal: Array = METAL if kind == &"metal" else (BRICK if rng.randf() < 0.3 else CONCRETE)
	for j in count:
		var vel := n * rng.randf_range(2.0, 5.5) * power + Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(1.5, 5.0), rng.randf_range(-2.0, 2.0)) * power
		var sz := rng.randf_range(0.1, 0.3) * clampf(power, 0.7, 1.4)
		br.fling(at + n * 0.2 + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.5, 0.5), 0.0), vel, pal[rng.randi() % pal.size()], sz, Vector3(1.0, rng.randf_range(0.45, 1.0), rng.randf_range(0.55, 1.0)), 3.6)
		chunks_flung += 1


## A ring of earth and asphalt thrown out of a crater.
static func _ring(g: Vector3, radius: float, count: int, level: int) -> void:
	var br := Breakables.current
	if br == null:
		return
	var rng := _rng
	for j in count:
		var ang := rng.randf() * TAU
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var vel := out * rng.randf_range(2.5, 6.0) * (0.6 + 0.2 * float(level)) + Vector3(0.0, rng.randf_range(4.0, 8.0), 0.0)
		br.fling(g + out * radius * 0.2 + Vector3(0.0, 0.3, 0.0), vel, ASPHALT[rng.randi() % ASPHALT.size()], rng.randf_range(0.1, 0.26), Vector3(1.0, rng.randf_range(0.4, 0.9), rng.randf_range(0.6, 1.0)), 3.0)
		chunks_flung += 1


## A puff of grey dust where the wall lost something (the shared puff cloud: one draw call).
static func _dust(at: Vector3, n: Vector3, radius: float, count: int) -> void:
	var bf := BlastFx.instance
	if not is_instance_valid(bf):
		return
	for j in count:
		bf.puff(at + n * (0.4 + 0.5 * float(j)), n * 1.1 + Vector3(0.0, 0.9, 0.0), 0.9, clampf(radius * 0.55, 2.0, 4.5), 2.2, Color(0.56, 0.53, 0.49, 0.5), BlastFx.K_SMOKE, 0.0, 0.8)
