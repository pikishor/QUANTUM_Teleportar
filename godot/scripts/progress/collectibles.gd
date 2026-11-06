class_name Collectibles
extends Node
## I2: 30 collectible quantum shards (Game.progress.collectibles). 20 hover over street corners (5 per district), 10 sit on low rooftops (reachable by climbing).
## Positions are pure data derived from the fixed city layout (spots()), so the save only stores which indices were taken. All uncollected shards are drawn by ONE MultiMesh
## (one draw call, spin and bob in the shader), proximity is checked at 10 Hz while Game.is_playing(). Each shard pays REWARD credits.
## The HUD shows "SHARDS n/30", the minimap marks shards in range and pins the nearest one to its rim (nearest_uncollected).

signal changed(count: int)
signal picked(index: int)

const Districts := preload("res://scripts/world/city_districts.gd")
const Bld := preload("res://scripts/world/city_buildings.gd")
const BM := preload("res://scripts/world/building_meshes.gd")
const COUNT := 30
const ROOF_COUNT := 10
const REWARD := Economy.SHARD_REWARD
const RADIUS := 2.6
const HEIGHT_REACH := 3.2
const CHECK := 0.1
const ROOF_PER_DISTRICT: Array[int] = [3, 2, 3, 2]
const GROUND_PER_DISTRICT := 5

static var _spots: Array[Vector3] = []

var collected: Array[int] = []
var _t := 0.0
var _mmi: MultiMeshInstance3D
var _mm: MultiMesh


## The 30 shard positions: indices 0..19 street level (district order), 20..29 rooftops.
static func spots() -> Array[Vector3]:
	if not _spots.is_empty():
		return _spots
	var out: Array[Vector3] = []
	var ints := CityLayout.make_intersections()
	for d in Districts.COUNT:
		var mine: Array[Vector3] = []
		for p in ints:
			if Districts.at(p.x, p.z) == d and Vector2(p.x, p.z).length() > 60.0:
				mine.append(p)
		mine.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x if not is_equal_approx(a.x, b.x) else a.z < b.z)
		var step := float(mine.size()) / float(GROUND_PER_DISTRICT)
		for k in GROUND_PER_DISTRICT:
			var p: Vector3 = mine[mini(int(float(k) * step + step * 0.5), mine.size() - 1)]
			out.append(Vector3(p.x + 7.0, 1.2, p.z + 7.0))
	var layout := CityLayout.new()
	var bld := Bld.new()
	bld.assign(layout)
	for d in Districts.COUNT:
		var picked_roofs: Array[Vector3] = []
		var cands: Array = []
		for b: Bld.Building in bld.buildings:
			if b.lot.h <= 30.0 and CityLayout.is_core_block(b.lot.block_i, b.lot.block_j) and Districts.at(b.lot.cx, b.lot.cz) == d and b.cls != &"landmark":     # the 30 shards stay in the original core
				cands.append(b)
		cands.sort_custom(func(a: Bld.Building, c: Bld.Building) -> bool: return a.index < c.index)
		var want := ROOF_PER_DISTRICT[d]
		var gap := 110.0
		while picked_roofs.size() < want and gap > 0.0:
			var stride := maxi(cands.size() / want, 1)
			for i in range(stride / 2, cands.size(), stride):
				var b: Bld.Building = cands[i]
				var pos := Vector3(b.lot.cx, _roof_y(b) + 1.3, b.lot.cz)
				var ok := true
				for q in picked_roofs:
					ok = ok and Vector2(q.x - pos.x, q.z - pos.z).length() >= gap
				if ok and picked_roofs.size() < want:
					picked_roofs.append(pos)
			gap -= 30.0
		out.append_array(picked_roofs)
	_spots = out
	return _spots


static func _roof_y(b: Bld.Building) -> float:
	var top := b.lot.h
	for box: Array in BM.collision_boxes(b.cls, b.lot.cx, b.lot.cz, b.lot.w, b.lot.d, b.lot.h):
		var c: Vector3 = box[0]
		var sz: Vector3 = box[1]
		if absf(b.lot.cx - c.x) <= sz.x * 0.5 and absf(b.lot.cz - c.z) <= sz.z * 0.5:
			top = c.y + sz.y * 0.5
	return top


static func district_of_spot(i: int) -> int:
	var p := spots()[i]
	return Districts.at(p.x, p.z)


static func is_roof(i: int) -> bool:
	return i >= COUNT - ROOF_COUNT


func _ready() -> void:
	name = "Collectibles"
	_build_visual()
	set_process(true)


func count() -> int:
	return collected.size()


func is_collected(i: int) -> bool:
	return collected.has(i)


func roof_count() -> int:
	var n := 0
	for i in collected:
		n += 1 if is_roof(i) else 0
	return n


## Districts whose street and roof shards are all taken.
func districts_done() -> int:
	var per: Array[int] = [0, 0, 0, 0]
	var total: Array[int] = [0, 0, 0, 0]
	for i in COUNT:
		total[district_of_spot(i)] += 1
		if collected.has(i):
			per[district_of_spot(i)] += 1
	var n := 0
	for d in 4:
		n += 1 if per[d] >= total[d] and total[d] > 0 else 0
	return n


## Takes shard i (pays the reward unless `silent`). False when it is invalid or already taken.
func collect(i: int, silent := false) -> bool:
	if i < 0 or i >= COUNT or collected.has(i):
		return false
	collected.append(i)
	collected.sort()
	_refresh()
	if not silent:
		var prog := Game.progress as Progress
		if prog != null:
			prog.add_credits(REWARD)
		Game.say("SHARD  %d / %d" % [collected.size(), COUNT], 2.0)
		Sfx.play(&"pickup")
		picked.emit(i)
	changed.emit(collected.size())
	return true


func nearest_uncollected(pos: Vector3) -> int:
	var best := -1
	var bd := INF
	var sp := spots()
	for i in COUNT:
		if collected.has(i):
			continue
		var d := Vector2(sp[i].x - pos.x, sp[i].z - pos.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


func reset() -> void:
	collected.clear()
	_refresh()
	changed.emit(0)


func to_save() -> PackedInt32Array:
	return PackedInt32Array(collected)


## Damaged data is dropped value by value (out of range, duplicates).
func from_save(v: Variant) -> void:
	collected.clear()
	if v is PackedInt32Array or v is Array:
		for x: Variant in v:
			if x is int and int(x) >= 0 and int(x) < COUNT and not collected.has(int(x)):
				collected.append(int(x))
	collected.sort()
	_refresh()
	changed.emit(collected.size())


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = CHECK
	if not Game.is_playing() or not is_instance_valid(Game.player):
		return
	var pp := Game.player.global_position
	var sp := spots()
	for i in COUNT:
		if collected.has(i):
			continue
		var s := sp[i]
		if absf(s.y - pp.y - 1.0) <= HEIGHT_REACH and Vector2(s.x - pp.x, s.z - pp.z).length() <= RADIUS:
			collect(i)
			return


func _build_visual() -> void:
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := SphereMesh.new()
	mesh.radial_segments = 4
	mesh.rings = 2
	mesh.radius = 0.45
	mesh.height = 1.3
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nvarying float ph;\nvoid vertex(){ ph = MODEL_MATRIX[3].x * 0.13 + MODEL_MATRIX[3].z * 0.07; float a = TIME * 1.7 + ph; float c = cos(a); float s = sin(a); VERTEX = vec3(VERTEX.x * c - VERTEX.z * s, VERTEX.y + 0.18 * sin(TIME * 2.0 + ph), VERTEX.x * s + VERTEX.z * c); }\nvoid fragment(){ float f = 0.5 + 0.5 * sin(TIME * 2.5 + ph); ALBEDO = mix(vec3(0.55, 0.25, 1.0), vec3(0.4, 0.95, 1.0), f) * (0.9 + 0.5 * pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0)); }\n"
	mat.shader = sh
	mesh.material = mat
	_mm.mesh = mesh
	_mm.instance_count = COUNT
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Shards"
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.extra_cull_margin = 1000.0
	add_child(_mmi)
	_refresh()


func _refresh() -> void:
	if _mm == null:
		return
	var sp := spots()
	var live := 0
	for i in COUNT:
		if not collected.has(i):
			_mm.set_instance_transform(live, Transform3D(Basis(), sp[i]))
			live += 1
	_mm.visible_instance_count = live
