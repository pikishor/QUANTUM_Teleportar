class_name TerrainWorld
extends Node3D
## The land outside the city: a 6 km square of terrain streamed around the player (owner round 5: "mountains outside the city, ocean, rivers, as big as possible").
##
## Heights come from TerrainHeight (the single source of truth: land, rivers, road benches), meshes are built from them on worker threads and uploaded on the main thread with a per-tier budget:
##   LOD0  chunks of CHUNK m with 32 cells (7.8 m), the 3 x 3 chunks around the focus, colliders on those (ConcavePolygonShape3D of the very same triangles)
##   LOD1  the same chunks with 16 cells (15.6 m), out to R1 chunks (LOW 2, MED 3, HIGH 4)
##   LOD2  far tiles of FAR_TILE m with 32 cells (31 m) for the whole world, built once, a few draw calls; they cut the square the near chunks cover out with a shader rectangle (`hole`)
##         and sit FAR_SINK m low, so the near chunks (which have skirts) always win at the seam.
## Nothing inside the city plateau is built (the city has its own ground plane; the shader discards the overlap). Colliders exist ONLY for the LOD0 chunks next to the player.
## The focus is the player (the camera when there is none). `settle(pos)` builds everything around a point at once (tests, teleports, cutscenes).
## API: height_at / normal_at / biome_at / surface_at / is_ground_ready / stats() / set_quality(level) / settle(pos) / fog_zone (0 in the city .. 1 far out).

const CHUNK := 250.0
const LOD0_CELLS := 32
const LOD1_CELLS := 16
const FAR_TILE := 1000.0
const FAR_CELLS := 32
const SKIRT0 := 6.0
const SKIRT1 := 14.0
const SKIRT_FAR := 70.0
const FAR_SINK := 2.5
const R0 := 1                                              ## LOD0 / collider radius in chunks
const R1_BY_TIER: Array[int] = [2, 3, 4]                   ## LOD1 radius by tier (LOW MED HIGH)
const UPLOADS_BY_TIER: Array[int] = [1, 2, 3]              ## chunk meshes uploaded per frame (chunk budget)
const JOBS_BY_TIER: Array[int] = [2, 3, 4]                 ## chunk jobs running at once
const FOG_RAMP := 500.0                                    ## metres beyond the plateau over which the fog thins out

static var fog_zone := 0.0                                 ## 0 in the city, 1 outside it (weather.gd reads it)

var quality := 1
var focus := Vector3.ZERO
var _grid := 0
var _chunks := {}                                          ## key -> {node, lod, body, faces}
var _jobs := {}                                            ## key -> {id, lod, res}
var _far := {}                                             ## tile key -> MeshInstance3D
var _far_jobs := {}
var _mat: ShaderMaterial
var _mat_far: ShaderMaterial
var _road_mats: Array[ShaderMaterial] = []
var road_nodes: Array[MeshInstance3D] = []
var ridges: TerrainRidges
var _root_near: Node3D
var _root_far: Node3D
var _hole := Vector4.ZERO
var _hole_r := -1
var _focus_chunk := Vector2i(-9999, -9999)
var _stats := {"chunks_built": 0, "far_built": 0, "bodies": 0, "uploads": 0, "max_upload_ms": 0.0}
var threaded := true
var _vis_t := 0.0
var _next_scan := 0
var _far_n := -1
var vis_dist := 6000.0                                      ## metres beyond which the fog has swallowed everything: far tiles, chunks and roads farther than this are not drawn
var hidden_count := 0


func _ready() -> void:
	name = "Terrain"
	TerrainHeight.warm()
	_grid = int(round(2.0 * TerrainHeight.WORLD_HALF / CHUNK))
	_root_near = Node3D.new()
	_root_near.name = "Chunks"
	add_child(_root_near)
	_root_far = Node3D.new()
	_root_far.name = "FarTiles"
	add_child(_root_far)
	_make_materials()
	_build_roads()
	ridges = TerrainRidges.new()
	add_child(ridges)                                            # the far horizon: distant ranges beyond the world over the sea
	set_quality(Game.quality if Game != null else 1)
	TerrainMap.start()                                         # the world map picture is drawn on a worker thread


## The worker threads read the height function (script code, static tables): none may still run when the tree goes away, or the engine crashes at shutdown.
func _exit_tree() -> void:
	for key in _jobs.keys():
		var id: int = (_jobs[key] as Dictionary)["id"]
		if id >= 0:
			WorkerThreadPool.wait_for_task_completion(id)
	for key in _far_jobs.keys():
		var id2: int = (_far_jobs[key] as Dictionary)["id"]
		if id2 >= 0:
			WorkerThreadPool.wait_for_task_completion(id2)
	_jobs.clear()
	_far_jobs.clear()
	TerrainMap.shutdown()


func _make_materials() -> void:
	var sh := load("res://assets/shaders/terrain.gdshader") as Shader
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat_far = ShaderMaterial.new()
	_mat_far.shader = sh
	for m: ShaderMaterial in [_mat, _mat_far]:
		m.set_shader_parameter(&"city_half", TerrainHeight.CITY_HALF)
		m.set_shader_parameter(&"snow_line", TerrainBase.SNOW_LINE)
		m.set_shader_parameter(&"flat_col", TerrainTextures.flat_colors())
	_mat_far.set_shader_parameter(&"hole", _hole)


## One ribbon mesh per road (a few hundred triangles each; their AABBs are long, so a highway is one draw while you can see any of it).
func _build_roads() -> void:
	var sh := load("res://assets/shaders/terrain_road.gdshader") as Shader
	var roads := TerrainRoads.roads()
	var mats := {}
	for ri in roads.size():
		var kind: String = roads[ri]["kind"]
		if not mats.has(kind):
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter(&"kind", 0 if kind == "highway" else 1)
			m.render_priority = 2
			mats[kind] = m
			_road_mats.append(m)
		var mi := MeshInstance3D.new()
		mi.name = "Road_%s" % String(roads[ri]["name"]).replace(" ", "_")
		mi.mesh = TerrainRoads.build_ribbon(ri)
		mi.material_override = mats[kind]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mi)
		road_nodes.append(mi)


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	_next_scan = 0                                              # the radius changed: scan again now
	var arr := TerrainTextures.array(quality) if OS.get_environment("QT_TERRAIN_TEX") != "0" else null      # QT_TERRAIN_TEX=0: flat biome colours (what a device without the texture formats gets)
	TerrainTextures.prune(quality)
	for m: ShaderMaterial in [_mat, _mat_far]:
		if m == null:
			continue
		m.set_shader_parameter(&"layers", arr)
		m.set_shader_parameter(&"tex_k", 1.0 if arr != null else 0.0)
		m.set_shader_parameter(&"detail", 1.0 if quality >= 1 else 0.0)
	for rm in _road_mats:                                       # the gravel of the dirt tracks is layer 6 of the same array
		rm.set_shader_parameter(&"layers", arr)
		rm.set_shader_parameter(&"tex_k", 1.0 if arr != null else 0.0)


func r1() -> int:
	return R1_BY_TIER[quality]


# --- queries ------------------------------------------------------------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	return TerrainHeight.height_at(x, z)


func normal_at(x: float, z: float) -> Vector3:
	var e := 2.0
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func biome_at(x: float, z: float) -> StringName:
	return TerrainBase.biome_at(x, z, height_at(x, z))


## What the ground is made of at (x, z): &"city" (inside the plateau), &"asphalt" (highway), &"dirt" (track or verge), &"sand", &"rock", &"snow", &"grass", &"water" (deep).
static func surface_at(x: float, z: float) -> StringName:
	if TerrainHeight.city_distance(x, z) <= 0.0:
		return &"city"
	var r := TerrainRoads.nearest(x, z)
	if int(r[1]) >= 0:
		var road: Dictionary = TerrainRoads.roads()[int(r[1])]
		if float(r[0]) <= float(road["w"]) * 0.5:
			return &"asphalt" if road["kind"] == "highway" else &"dirt"
		if float(r[0]) <= float(road["w"]) * 0.5 + 4.0:
			return &"dirt"
	var h := TerrainHeight.height_at(x, z)
	if TerrainHeight.depth_at(x, z) > 0.8:
		return &"water"
	if h > TerrainBase.SNOW_LINE + 40.0:
		return &"snow"
	var b := TerrainBase.biome_at(x, z, h)
	if b == TerrainBase.BEACH or b == TerrainBase.DESERT:
		return &"sand"
	if b == TerrainBase.MOUNTAIN:
		return &"rock"
	return &"grass"


func _chunk_box(ci: int, cj: int) -> Rect2:
	return Rect2(-TerrainHeight.WORLD_HALF + float(ci) * CHUNK, -TerrainHeight.WORLD_HALF + float(cj) * CHUNK, CHUNK, CHUNK)


static func _inside_plateau(r: Rect2) -> bool:
	var h := TerrainHeight.CITY_HALF
	return r.position.x >= -h and r.position.y >= -h and r.end.x <= h and r.end.y <= h


func chunk_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int(floor((x + TerrainHeight.WORLD_HALF) / CHUNK)), 0, _grid - 1), clampi(int(floor((z + TerrainHeight.WORLD_HALF) / CHUNK)), 0, _grid - 1))


## True when a collider (or the city ground) holds the hero up at (x, z).
func is_ground_ready(x: float, z: float) -> bool:
	if absf(x) < TerrainHeight.CITY_HALF - 1.0 and absf(z) < TerrainHeight.CITY_HALF - 1.0:
		return true
	var c := chunk_of(x, z)
	var key := _key(c.x, c.y)
	return _chunks.has(key) and (_chunks[key] as Dictionary).get("body") != null


static func _key(ci: int, cj: int) -> int:
	return ci * 1000 + cj


func _cell_of_key(key: int) -> Vector2i:
	return Vector2i(key / 1000, key % 1000)


# --- streaming ----------------------------------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var f := _focus_point()
	if f == Vector3.INF:
		return
	focus = f
	var d := TerrainHeight.city_distance(f.x, f.z)
	fog_zone = clampf(d / FOG_RAMP, 0.0, 1.0)
	update(f)
	_rescue_player()
	TerrainMap.poll()
	_vis_t -= _delta
	if _vis_t <= 0.0:
		_vis_t = 0.25
		update_visibility()


func _focus_point() -> Vector3:
	if is_instance_valid(Game.player):
		return (Game.player as Node3D).global_position
	if is_instance_valid(Game.camera):
		return Game.camera.global_position
	return Vector3.INF


## Stream around `p`: queue jobs, upload finished ones (budget), drop what is far, move the colliders and the far-tile hole.
func update(p: Vector3) -> void:
	var fc := chunk_of(p.x, p.z)
	var now := Time.get_ticks_msec()
	if fc == _focus_chunk and _jobs.is_empty() and _far_jobs.is_empty() and now < _next_scan:
		return                                              # nothing in flight and the hero is in the same chunk: the full scan runs twice a second at most
	_next_scan = now + 400
	_focus_chunk = fc
	_queue_far(p)
	_queue_near(fc)
	_collect(UPLOADS_BY_TIER[quality])
	_drop_far_chunks(fc)
	_update_colliders(fc)
	_update_hole(fc)


## Fog culling: in the city the fog (density about 0.005) has swallowed everything beyond ~1 km, so no terrain tile, chunk or road that far away is drawn; in the thin outskirts air the
## limit grows to several km. Keeps the city views free of the terrain's draw calls and triangles (perf gate) and the outskirts bounded by what can be seen.
func update_visibility() -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return
	var env := vp.world_3d.environment if vp.world_3d != null else null
	var dens := env.fog_density if env != null and env.fog_enabled else 0.0
	vis_dist = clampf(5.0 / maxf(dens, 0.0003), 700.0, 14000.0)
	var c := Vector2(cam.global_position.x, cam.global_position.z)
	var hidden := 0
	for key in _chunks.keys():
		var rec: Dictionary = _chunks[key]
		var cc := _cell_of_key(int(key))
		var show := _box_dist(_chunk_box(cc.x, cc.y), c) <= vis_dist
		(rec["node"] as MeshInstance3D).visible = show
		hidden += 0 if show else 1
	for key in _far.keys():
		var show2 := _box_dist(_tile_box(int(key) / 100, int(key) % 100), c) <= vis_dist
		(_far[key] as MeshInstance3D).visible = show2
		hidden += 0 if show2 else 1
	for i in road_nodes.size():
		var show3 := _road_dist(i, c) <= vis_dist
		road_nodes[i].visible = show3
		hidden += 0 if show3 else 1
	if ridges != null:                                           # the far ring only matters where the air is clear enough to see 2.5 km: not in the fog of the city streets
		ridges.visible = vis_dist >= 2500.0
		hidden += 0 if ridges.visible else 1
	hidden_count = hidden


static func _box_dist(r: Rect2, c: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - c.x, 0.0), c.x - r.end.x)
	var dz := maxf(maxf(r.position.y - c.y, 0.0), c.y - r.end.y)
	return sqrt(dx * dx + dz * dz)


func _road_dist(i: int, c: Vector2) -> float:
	var pts: PackedVector2Array = TerrainRoads.roads()[i]["pos"]
	var best := 1.0e18
	for k in range(0, pts.size(), 3):
		best = minf(best, pts[k].distance_squared_to(c))
	return sqrt(best)


func _desired_lod(fc: Vector2i, ci: int, cj: int) -> int:
	var d := maxi(absi(ci - fc.x), absi(cj - fc.y))
	if d <= R0:
		return 0
	if d <= r1():
		return 1
	return -1


func _queue_near(fc: Vector2i) -> void:
	if _jobs.size() >= JOBS_BY_TIER[quality]:
		return
	var best_key := -1
	var best_d := 1.0e9
	var best_lod := 0
	for dj in range(-r1(), r1() + 1):
		for di in range(-r1(), r1() + 1):
			var ci := fc.x + di
			var cj := fc.y + dj
			if ci < 0 or cj < 0 or ci >= _grid or cj >= _grid:
				continue
			var lod := _desired_lod(fc, ci, cj)
			if lod < 0 or _inside_plateau(_chunk_box(ci, cj)):
				continue
			var key := _key(ci, cj)
			if _jobs.has(key):
				continue
			if _chunks.has(key) and int((_chunks[key] as Dictionary)["lod"]) == lod:
				continue
			var dd := float(di * di + dj * dj) + (0.0 if lod == 0 else 0.5)
			if dd < best_d:
				best_d = dd
				best_key = key
				best_lod = lod
	if best_key < 0:
		return
	_start_job(best_key, best_lod)


func _start_job(key: int, lod: int) -> void:
	var c := _cell_of_key(key)
	var box := _chunk_box(c.x, c.y)
	var res := {}
	var cells := LOD0_CELLS if lod == 0 else LOD1_CELLS
	var skirt := SKIRT0 if lod == 0 else SKIRT1
	var work := func() -> void:
		var d := TerrainMesher.build(box.position.x, box.position.y, CHUNK, cells, skirt, 0.0, lod == 0)
		res["d"] = d
	var id := -1
	if threaded:
		id = WorkerThreadPool.add_task(work)
	else:
		work.call()
	_jobs[key] = {"id": id, "lod": lod, "res": res}


func _queue_far(p: Vector3) -> void:
	if _far.size() + _far_jobs.size() >= _far_total():
		return
	if _far_jobs.size() >= 2:
		return
	var tiles := int(round(2.0 * TerrainHeight.WORLD_HALF / FAR_TILE))
	var best := -1
	var best_d := 1.0e18
	for tj in tiles:
		for ti in tiles:
			var key := ti * 100 + tj
			if _far.has(key) or _far_jobs.has(key):
				continue
			var r := _tile_box(ti, tj)
			if _inside_plateau(r):
				continue
			var d := (r.get_center() - Vector2(p.x, p.z)).length_squared()
			if d < best_d:
				best_d = d
				best = key
	if best < 0:
		return
	var ti2 := best / 100
	var tj2 := best % 100
	var box := _tile_box(ti2, tj2)
	var res := {}
	var work := func() -> void:
		res["d"] = TerrainMesher.build(box.position.x, box.position.y, FAR_TILE, FAR_CELLS, SKIRT_FAR, FAR_SINK, false)
	var id := -1
	if threaded:
		id = WorkerThreadPool.add_task(work)
	else:
		work.call()
	_far_jobs[best] = {"id": id, "res": res}


func _tile_box(ti: int, tj: int) -> Rect2:
	return Rect2(-TerrainHeight.WORLD_HALF + float(ti) * FAR_TILE, -TerrainHeight.WORLD_HALF + float(tj) * FAR_TILE, FAR_TILE, FAR_TILE)


func _far_total() -> int:
	if _far_n >= 0:
		return _far_n
	var tiles := int(round(2.0 * TerrainHeight.WORLD_HALF / FAR_TILE))
	var n := 0
	for tj in tiles:
		for ti in tiles:
			if not _inside_plateau(_tile_box(ti, tj)):
				n += 1
	_far_n = n
	return n


## Finish jobs: at most `budget` chunk meshes per call (the upload is the main-thread cost), far tiles one per call.
func _collect(budget: int) -> void:
	var done := 0
	for key in _jobs.keys():
		var j: Dictionary = _jobs[key]
		if j["id"] >= 0 and not WorkerThreadPool.is_task_completed(j["id"]):
			continue
		if done >= budget:
			break
		if j["id"] >= 0:
			WorkerThreadPool.wait_for_task_completion(j["id"])
		_jobs.erase(key)
		_install(int(key), int(j["lod"]), (j["res"] as Dictionary)["d"])
		done += 1
	for key in _far_jobs.keys():
		var j: Dictionary = _far_jobs[key]
		if j["id"] >= 0 and not WorkerThreadPool.is_task_completed(j["id"]):
			continue
		if j["id"] >= 0:
			WorkerThreadPool.wait_for_task_completion(j["id"])
		_far_jobs.erase(key)
		_install_far(int(key), (j["res"] as Dictionary)["d"])
		break


func _install(key: int, lod: int, d: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var c := _cell_of_key(key)
	var rec: Dictionary = _chunks.get(key, {})
	var mi: MeshInstance3D = rec.get("node")
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Chunk_%d_%d" % [c.x, c.y]
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_root_near.add_child(mi)
		rec["node"] = mi
		rec["body"] = null
	mi.mesh = TerrainMesher.to_mesh(d)
	mi.custom_aabb = AABB(Vector3(_chunk_box(c.x, c.y).position.x, float(d["min_y"]) - 1.0, _chunk_box(c.x, c.y).position.y), Vector3(CHUNK, float(d["max_y"]) - float(d["min_y"]) + 2.0, CHUNK))
	rec["lod"] = lod
	rec["faces"] = d["faces"] if lod == 0 else PackedVector3Array()
	if rec.get("body") != null and lod != 0:
		(rec["body"] as Node).queue_free()
		rec["body"] = null
	_chunks[key] = rec
	_stats["chunks_built"] += 1
	_stats["uploads"] += 1
	_stats["max_upload_ms"] = maxf(float(_stats["max_upload_ms"]), float(Time.get_ticks_usec() - t0) / 1000.0)


func _install_far(key: int, d: Dictionary) -> void:
	var ti := key / 100
	var tj := key % 100
	var mi := MeshInstance3D.new()
	mi.name = "Far_%d_%d" % [ti, tj]
	mi.mesh = TerrainMesher.to_mesh(d)
	var box := _tile_box(ti, tj)
	mi.custom_aabb = AABB(Vector3(box.position.x, float(d["min_y"]) - 1.0, box.position.y), Vector3(FAR_TILE, float(d["max_y"]) - float(d["min_y"]) + 2.0, FAR_TILE))
	mi.material_override = _mat_far
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_root_far.add_child(mi)
	_far[key] = mi
	_stats["far_built"] += 1


func _drop_far_chunks(fc: Vector2i) -> void:
	var keep := r1() + 1
	for key in _chunks.keys():
		var c := _cell_of_key(int(key))
		if maxi(absi(c.x - fc.x), absi(c.y - fc.y)) > keep:
			var rec: Dictionary = _chunks[key]
			if rec.get("body") != null:
				(rec["body"] as Node).queue_free()
			(rec["node"] as Node).queue_free()
			_chunks.erase(key)


func _update_colliders(fc: Vector2i) -> void:
	for key in _chunks.keys():
		var rec: Dictionary = _chunks[key]
		var c := _cell_of_key(int(key))
		var near := maxi(absi(c.x - fc.x), absi(c.y - fc.y)) <= R0 and int(rec["lod"]) == 0
		if near and rec.get("body") == null:
			var faces: PackedVector3Array = rec["faces"]
			if faces.is_empty():
				continue
			var body := StaticBody3D.new()
			body.name = "Collider_%d_%d" % [c.x, c.y]
			body.collision_layer = Game.L_WORLD
			body.collision_mask = 0
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			add_child(body)
			rec["body"] = body
			_stats["bodies"] += 1
			break                                                  # one collider per update: building the shape is the expensive part
		elif not near and rec.get("body") != null:
			(rec["body"] as Node).queue_free()
			rec["body"] = null


## The far tiles cut out the square of chunks that are complete (every needed chunk of that ring exists at its LOD): never a hole, never a double layer.
func _update_hole(fc: Vector2i) -> void:
	var ring := -1
	for r in range(0, r1() + 1):
		var ok := true
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var ci := fc.x + di
				var cj := fc.y + dj
				if ci < 0 or cj < 0 or ci >= _grid or cj >= _grid or _inside_plateau(_chunk_box(ci, cj)):
					continue
				var key := _key(ci, cj)
				if not _chunks.has(key) or int((_chunks[key] as Dictionary)["lod"]) < 0:
					ok = false
		if not ok:
			break
		ring = r
	if ring < 0:
		_set_hole(Vector4.ZERO, -1)
		return
	var lo := _chunk_box(maxi(fc.x - ring, 0), maxi(fc.y - ring, 0))
	var hi := _chunk_box(mini(fc.x + ring, _grid - 1), mini(fc.y + ring, _grid - 1))
	_set_hole(Vector4(lo.position.x, lo.position.y, hi.end.x, hi.end.y), ring)


func _set_hole(h: Vector4, ring: int) -> void:
	if h != _hole:
		_hole = h
		_hole_r = ring
		_mat_far.set_shader_parameter(&"hole", h)


## If the hero ended up under the ground outside the city (a teleport into a chunk that was not there yet), put him on it.
func _rescue_player() -> void:
	var p := Game.player as Node3D
	if p == null or not is_instance_valid(p) or InteriorSpace.contains(p.global_position):
		return
	var pos := p.global_position
	if absf(pos.x) < TerrainHeight.CITY_HALF + 4.0 and absf(pos.z) < TerrainHeight.CITY_HALF + 4.0:
		return
	var h := TerrainHeight.height_at(pos.x, pos.z)
	if pos.y < h - 3.0 and pos.y > h - 400.0 and not is_ground_ready(pos.x, pos.z):
		p.global_position = Vector3(pos.x, h + 0.6, pos.z)
		if p is CharacterBody3D:
			(p as CharacterBody3D).velocity = Vector3.ZERO


## Build everything around `p` right now (no threads): tests, teleports, cutscene cuts. Returns the number of chunks built.
func settle(p: Vector3, near_only := false) -> int:
	var old_threaded := threaded
	threaded = false
	var fc := chunk_of(p.x, p.z)
	var n := 0
	for _i in 400:
		var before: int = int(_stats["chunks_built"]) + int(_stats["far_built"])
		if not near_only:
			_queue_far(p)
		_queue_near(fc)
		_collect(64)
		_update_colliders(fc)
		for _k in 8:
			_update_colliders(fc)
		var after: int = int(_stats["chunks_built"]) + int(_stats["far_built"])
		n += after - before
		if after == before and _jobs.is_empty() and _far_jobs.is_empty():
			break
	_focus_chunk = fc
	_drop_far_chunks(fc)
	_update_hole(fc)
	threaded = old_threaded
	update_visibility()
	return n


## The hero is about to stand at `p`: make sure the ground there exists (builds the LOD0 ring synchronously when it does not; a no-op inside the city).
func ensure_ground(p: Vector3) -> void:
	if is_ground_ready(p.x, p.z):
		return
	settle(p, true)


func stats() -> Dictionary:
	var tris := 0
	var draws := 0
	for key in _chunks.keys():
		var m := ((_chunks[key] as Dictionary)["node"] as MeshInstance3D).mesh
		if m != null:
			tris += m.surface_get_array_index_len(0) / 3
			draws += 1
	for key in _far.keys():
		var m2 := (_far[key] as MeshInstance3D).mesh
		if m2 != null:
			tris += m2.surface_get_array_index_len(0) / 3
			draws += 1
	var shown := 0
	for key in _chunks.keys():
		shown += 1 if ((_chunks[key] as Dictionary)["node"] as MeshInstance3D).visible else 0
	for key in _far.keys():
		shown += 1 if (_far[key] as MeshInstance3D).visible else 0
	for rn in road_nodes:
		shown += 1 if rn.visible else 0
	return {"shown": shown, "vis_dist": vis_dist, "chunks": _chunks.size(), "far_tiles": _far.size(), "jobs": _jobs.size() + _far_jobs.size(), "bodies": _bodies(), "tris": tris, "nodes": draws,
		"hole_ring": _hole_r, "built_total": int(_stats["chunks_built"]) + int(_stats["far_built"]), "max_upload_ms": _stats["max_upload_ms"], "tex_bytes": TerrainTextures.estimate_bytes(quality)}


func _bodies() -> int:
	var n := 0
	for key in _chunks.keys():
		if (_chunks[key] as Dictionary).get("body") != null:
			n += 1
	return n


func chunk_lod(ci: int, cj: int) -> int:
	var key := _key(ci, cj)
	return int((_chunks[key] as Dictionary)["lod"]) if _chunks.has(key) else -1


func has_chunk(ci: int, cj: int) -> bool:
	return _chunks.has(_key(ci, cj))
