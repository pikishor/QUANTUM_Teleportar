extends RefCounted
## The endless megacity beyond the border roads: the same 80 m grid continues (the ground shader draws the roads analytically) with
## lean, unlit-detail towers on it. Visual only, no colliders, no shadows; three building classes, one MultiMesh each.

const MB := preload("res://scripts/world/mesh_builder.gd")
const BM := preload("res://scripts/world/building_meshes.gd")
const Buildings := preload("res://scripts/world/city_buildings.gd")
const FAR_SHADER := preload("res://assets/shaders/building_far.gdshader")
const FAR_MIRROR_SHADER := preload("res://assets/shaders/building_far_mirror.gdshader")

const CLASSES: Array[StringName] = [&"block", &"stepped", &"tiered"]
const HEIGHTS: Array[float] = [16.0, 28.0, 44.0, 62.0, 88.0, 118.0, 150.0]
## Blocks beyond the playable N x N: indices from RANGE_MIN to RANGE_MAX inclusive (N + 10 blocks per side, 5 blocks of towers beyond the walls).
const RANGE_MIN := -5
const RANGE_MAX := CityLayout.N + 4
## Cell grid of the camera window (city_stream.gd): covers the whole skyline.
const GRID_CELLS := CityLayout.N + 10                 ## 80 m cells: one per block of the skyline range
const GRID_ORIGIN := -CityLayout.HALF - 5.0 * CityLayout.PITCH
## The towers never reach into the walkable square or the invisible border walls (|x|, |z| < KEEP_OUT): they have no colliders, so a lot
## there would let the player or a car drive straight through a facade. Lots that would are dropped; the random stream is unchanged.
const KEEP_OUT := CityLayout.WALK + CityLayout.WALL_T + 2.0
## Towers farther than this from the camera are not drawn (they have melted into the fog; see city_stream.gd). The towers are what the
## horizon is made of, so the radius reaches the far corner of the grid from its centre.
const RADIUS := 900.0

var multimeshes := {}
var count := 0
## Footprints (x, z) of the placed towers, for tests.
var rects: Array[Rect2] = []


func build() -> void:
	rects.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var lists := {}
	for c in CLASSES:
		lists[c] = []
	for bi in range(RANGE_MIN, RANGE_MAX + 1):
		for bj in range(RANGE_MIN, RANGE_MAX + 1):
			if bi >= 0 and bi < CityLayout.N and bj >= 0 and bj < CityLayout.N:
				continue
			var bx := -CityLayout.HALF + (bi + 0.5) * CityLayout.PITCH
			var bz := -CityLayout.HALF + (bj + 0.5) * CityLayout.PITCH
			var central := 1.0 - minf(1.0, Vector2(bx, bz).length() / 1100.0)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					if rng.randf() < 0.08:
						continue
					var cx: float = bx + sx * CityLayout.LOT_OFFSET
					var cz: float = bz + sz * CityLayout.LOT_OFFSET
					var w: float = CityLayout.FOOT[rng.randi() % 2]
					var d: float = CityLayout.FOOT[rng.randi() % 2]
					var hi := clampi(int(floor(rng.randf() * 2.4 + central * 4.2)), 0, HEIGHTS.size() - 1)
					var h := HEIGHTS[hi]
					var r := rng.randf()
					var cls := &"block" if h < 40.0 else (&"stepped" if r < 0.5 else &"tiered")
					var tint: Color = Buildings.TINTS[rng.randi() % Buildings.TINTS.size()]
					var lit_p := lerpf(0.25, 0.6, rng.randf())
					var style := 4 if h < 20.0 and rng.randf() < 0.5 else (2 if h > 50.0 and rng.randf() < 0.6 else rng.randi() % 3)
					var flags := 4 if rng.randf() < 0.3 and h >= 44.0 else 0
					var custom := Color(rng.randf(), float(rng.randi() % 4), float(style), float(flags))
					if absf(cx) - w * 0.5 < KEEP_OUT and absf(cz) - d * 0.5 < KEEP_OUT:
						continue
					rects.append(Rect2(cx - w * 0.5, cz - d * 0.5, w, d))
					(lists[cls] as Array).append([Transform3D(Basis.from_scale(Vector3(w, h, d)), Vector3(cx, 0.0, cz)),
							Color(tint.r, tint.g, tint.b, lit_p), custom])
	count = 0
	for c in CLASSES:
		var list: Array = lists[c]
		var mm := MB.new_multimesh(BM.build(c), list.size(), true, true)
		var buf := MB.new_buffer(list.size(), true, true)
		for k in list.size():
			MB.write_instance(buf, k, list[k][0], true, list[k][1], true, list[k][2])
		mm.buffer = buf
		multimeshes[c] = mm
		count += list.size()


static func make_material(mirror := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FAR_MIRROR_SHADER if mirror else FAR_SHADER
	m.set_shader_parameter(&"far_fade_start", 140.0)
	m.set_shader_parameter(&"far_fade_end", 520.0)
	return m
