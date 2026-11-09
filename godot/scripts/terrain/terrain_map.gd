class_name TerrainMap
extends RefCounted
## The world map layer: one top-down picture of the whole 6 km world (hill-shaded land by biome, snow, sea, rivers, lakes, roads), drawn by the map screen under the city and by the
## minimap outside it. It is built ONCE on a worker thread from TerrainHeight (RES x RES samples, a couple of seconds on a phone, nothing on the main thread) and installed by
## `poll()` (TerrainWorld calls it every frame). Until then `texture` is null and the map keeps its dark ground.
## world_to_uv(x, z) maps world metres to 0..1 on it; region_name(x, z) is the name the map prints.

const RES := 512
const MARGIN := 1                                       ## heights are sampled one pixel beyond the image for the hill shading

## Region names printed on the WORLD map (x, z in metres).
const LABELS := [["HIGH RANGE", Vector2(1650, -1700)], ["FOREST HILLS", Vector2(-1600, -1300)], ["DRY PLAINS", Vector2(1650, 900)], ["COAST", Vector2(-1750, 700)], ["OPEN SEA", Vector2(-2300, 2300)],
	["MIRROR LAKE", Vector2(-250, -2150)], ["PASS ROAD", Vector2(150, -1500)], ["CITY", Vector2(0, 0)]]

static var texture: ImageTexture = null
static var ready := false
static var _task := -1
static var _out := {}
static var _cancel := false                 ## set by `shutdown()`: the worker stops at the next row (the process may be quitting under it)


static func extent() -> float:
	return TerrainHeight.WORLD_HALF


static func world_to_uv(x: float, z: float) -> Vector2:
	var e := extent()
	return Vector2((x + e) / (2.0 * e), (z + e) / (2.0 * e))


static func start() -> void:
	if ready or _task >= 0:
		return
	TerrainHeight.warm()
	_out = {}
	_cancel = false
	_task = WorkerThreadPool.add_task(func() -> void: _out["img"] = _build())


## Main thread: install the texture when the worker is done. Returns true once the map exists.
static func poll() -> bool:
	if ready:
		return true
	if _task < 0:
		return false
	if not WorkerThreadPool.is_task_completed(_task):
		return false
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var img: Image = _out.get("img")
	if img != null and img.get_width() == RES:
		texture = ImageTexture.create_from_image(img)
		ready = true
	return ready


## Stop the worker and wait for it (TerrainWorld._exit_tree): a task that runs script code while the engine shuts down would crash it.
static func shutdown() -> void:
	if _task < 0:
		return
	_cancel = true
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_cancel = false


## Build it right now on the calling thread (tests).
static func build_now() -> bool:
	TerrainHeight.warm()
	_out = {"img": _build()}
	_task = -1
	var img: Image = _out["img"]
	texture = ImageTexture.create_from_image(img)
	ready = true
	return true


static func region_name(x: float, z: float) -> String:
	var h := TerrainHeight.height_at(x, z)
	var rn := TerrainRoads.name_at(x, z, 40.0)
	if TerrainHeight.city_distance(x, z) <= 0.0:
		return "CITY"
	if h < TerrainHeight.SEA_LEVEL - 0.2:
		return "OPEN SEA"
	if rn != "":
		return rn
	match TerrainBase.biome_at(x, z, h):
		TerrainBase.MOUNTAIN:
			return "HIGH RANGE"
		TerrainBase.FOREST:
			return "FOREST HILLS"
		TerrainBase.DESERT:
			return "DRY PLAINS"
		TerrainBase.BEACH:
			return "COAST"
	return "OUTSKIRTS"


static func _build() -> Image:
	var n := RES
	var e := extent()
	var mpp := 2.0 * e / float(n)
	var n2 := n + 2 * MARGIN
	var hs := PackedFloat32Array()
	hs.resize(n2 * n2)
	for j in n2:
		if _cancel:
			return Image.create(1, 1, false, Image.FORMAT_RGBA8)
		var z := -e + (float(j - MARGIN) + 0.5) * mpp
		for i in n2:
			hs[j * n2 + i] = TerrainHeight.height_at(-e + (float(i - MARGIN) + 0.5) * mpp, z)
	var data := PackedByteArray()
	data.resize(n * n * 4)
	var sun := Vector3(-0.55, 0.75, -0.35).normalized()
	for j in n:
		var z := -e + (float(j) + 0.5) * mpp
		for i in n:
			var x := -e + (float(i) + 0.5) * mpp
			var k := (j + MARGIN) * n2 + i + MARGIN
			var h := hs[k]
			var dx := (hs[k + 1] - hs[k - 1]) / (2.0 * mpp)
			var dz := (hs[k + n2] - hs[k - n2]) / (2.0 * mpp)
			var shade := clampf(Vector3(-dx * 2.2, 1.0, -dz * 2.2).normalized().dot(sun) * 0.85 + 0.25, 0.3, 1.25)
			var col := _colour(x, z, h)
			var o := (j * n + i) * 4
			col = col * shade
			data[o] = int(clampf(col.r, 0.0, 1.0) * 255.0)
			data[o + 1] = int(clampf(col.g, 0.0, 1.0) * 255.0)
			data[o + 2] = int(clampf(col.b, 0.0, 1.0) * 255.0)
			data[o + 3] = 255
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
	_draw_roads(img, mpp)
	return img


static func _colour(x: float, z: float, h: float) -> Color:
	var w := TerrainHeight.water_level_for(x, z, h)
	if w != TerrainHeight.NO_WATER:
		var d := clampf((w - h) / 40.0, 0.0, 1.0)
		return Color(0.07, 0.3, 0.46).lerp(Color(0.02, 0.1, 0.22), d)
	if TerrainHeight.city_distance(x, z) <= 0.0:
		return Color(0.12, 0.2, 0.25)
	var col: Color
	match TerrainBase.biome_at(x, z, h):
		TerrainBase.BEACH:
			col = Color(0.72, 0.68, 0.5)
		TerrainBase.FOREST:
			col = Color(0.15, 0.36, 0.2)
		TerrainBase.DESERT:
			col = Color(0.66, 0.48, 0.28)
		TerrainBase.MOUNTAIN:
			col = Color(0.46, 0.45, 0.44)
		_:
			col = Color(0.32, 0.45, 0.24)
	if h > TerrainBase.SNOW_LINE:
		col = col.lerp(Color(0.92, 0.96, 1.0), clampf((h - TerrainBase.SNOW_LINE) / 90.0, 0.0, 1.0))
	return col


static func _draw_roads(img: Image, mpp: float) -> void:
	var e := extent()
	for r in TerrainRoads.roads():
		var pts: PackedVector2Array = r["pos"]
		var col := Color(1.0, 0.82, 0.25) if r["kind"] == "highway" else Color(0.9, 0.5, 0.2)
		var rad := 1 if r["kind"] == "highway" else 0
		for p in pts:
			var ix := int((p.x + e) / mpp)
			var iy := int((p.y + e) / mpp)
			for ox in range(-rad, rad + 1):
				for oy in range(-rad, rad + 1):
					var px := ix + ox
					var py := iy + oy
					if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
						img.set_pixel(px, py, col)
