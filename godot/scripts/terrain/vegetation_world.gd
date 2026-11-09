class_name VegetationWorld
extends Node3D
## The forests, bushes, grass and rocks of the outskirts around the hero (wave 105). Child `vegetation` of the City (VegetationWorld.attach). Data: VegScatter (where things grow), pieces and
## materials: VegKit (assets/models/nature_kit.glb + generated far LODs, assets/shaders/vegetation.gdshader with wind and snow).
##
## How it stays cheap: ONE MultiMesh per piece and LOD (at most 17 draw calls, however big the forest), refilled from a worker thread whenever the hero has moved a few metres. The worker
## generates the scatter cells around the hero (cached, evicted when far), sorts every plant into its LOD by distance (trees: near piece, cone / blob mid LOD, tiny far LOD; the next LOD
## dissolves in over the last 15 % of the previous one through the shader's dither, no popping), and the main thread only assigns the buffers. Per tier (LOW MED HIGH): LOD radii, shrub and
## grass radii, rock radius, how many pine / broadleaf variants, how many tree trunks get a collider. A pool of StaticBody3D cylinders follows the hero: you cannot drive or walk through
## a trunk or a boulder (the nearest few dozen within about 28 m).
## Shutdown rule (see TerrainWorld): the worker task is waited for in _exit_tree.
##   VegetationWorld.instance      the node;   stats()  {instances, tris, slots, cells, jobs, colliders}
##   settle(pos)                   build everything around a point NOW on this thread (tests, teleports, captures)
## `QT_NO_VEGETATION=1` leaves it out (perf A/B runs).

const TIERS := [
	{"r0": 24.0, "r1": 80.0, "r2": 140.0, "shrub": 30.0, "grass": 15.0, "rock": 80.0, "variants": 1, "blockers": 26},
	{"r0": 31.0, "r1": 98.0, "r2": 220.0, "shrub": 44.0, "grass": 22.0, "rock": 120.0, "variants": 2, "blockers": 38},
	{"r0": 42.0, "r1": 132.0, "r2": 320.0, "shrub": 64.0, "grass": 32.0, "rock": 170.0, "variants": 2, "blockers": 52},
]
const MOVE_TRIGGER := 5.0
const MIN_INTERVAL := 0.12
const BLOCK_RADIUS := 30.0
const FADE := 0.15
const FAR_KEEP := 0.55
const FAR_GROW := 1.3

static var instance: VegetationWorld = null

var quality := 1
var focus := Vector3.INF                          ## the point the plants are arranged around (the hero, the camera without one)
var enabled := true
var jobs_done := 0
var _slots := {}                                  ## slot name -> {mi: MultiMeshInstance3D, mm: MultiMesh, cap: int, n: int, tris: int}
var _cells := {}                                  ## worker-side cache: (layer, ci, cj) key -> PackedFloat32Array (only the running job touches it)
var _task := -1
var _result := {}
var _mutex := Mutex.new()
var _center := Vector2(1.0e9, 1.0e9)
var _t := 0.0
var _threaded := true
var _pool: Array[StaticBody3D] = []
var _pool_used := 0
var _pending_force := true
var _tier: Dictionary = TIERS[1]
var _stats := {"instances": 0, "tris": 0, "cells": 0, "jobs": 0, "colliders": 0}


static func attach(parent: Node) -> VegetationWorld:
	var w := VegetationWorld.new()
	w.name = "Vegetation"
	parent.add_child(w)
	return w


func _ready() -> void:
	instance = self
	if not VegKit.available():
		enabled = false
		return
	VegScatter.warm()
	set_quality(quality)
	set_process(true)


func _exit_tree() -> void:
	if instance == self:
		instance = null
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	_tier = TIERS[quality]
	_ensure_pool(int(_tier["blockers"]))
	_pending_force = true


func _focus_point() -> Vector3:
	var p := Game.player as Node3D
	if is_instance_valid(p):
		return p.global_position
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	return cam.global_position if cam != null else Vector3.INF


func _process(delta: float) -> void:
	if not enabled:
		return
	_t += delta
	_poll()
	if _task >= 0 or _t < MIN_INTERVAL:
		return
	var f := _focus_point()
	if not f.is_finite():
		return
	focus = f
	var c := Vector2(f.x, f.z)
	if not _pending_force and c.distance_to(_center) < MOVE_TRIGGER:
		return
	if TerrainHeight.city_distance(f.x, f.z) > float(_tier["r2"]) + 60.0 and _stats["instances"] == 0 and not _pending_force:
		return                                                             # deep inside the city: nothing to draw, nothing to compute
	_start(c)


func _start(c: Vector2) -> void:
	_t = 0.0
	_center = c
	_pending_force = false
	if _threaded:
		_task = WorkerThreadPool.add_task(_job.bind(c.x, c.y, _tier.duplicate()), false, "vegetation")
	else:
		_job(c.x, c.y, _tier.duplicate())
		_poll()


func _poll() -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_mutex.lock()
	var res := _result
	_result = {}
	_mutex.unlock()
	if not res.is_empty():
		_apply(res)


## Build everything around `p` right now (tests, teleports): same code as the worker, on this thread, waiting for a running job first.
func settle(p: Vector3) -> void:
	if not enabled:
		return
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_mutex.lock()
	_result = {}
	_mutex.unlock()
	focus = p
	_center = Vector2(p.x, p.z)
	_pending_force = false
	_job(p.x, p.z, _tier.duplicate())
	_poll()


# --- the worker -------------------------------------------------------------------------------------------------------------------------------

static func _ckey(layer: int, ci: int, cj: int) -> int:
	return (layer << 40) | ((ci + 4096) << 20) | (cj + 4096)


func _cell_list(layer: int, c: Vector2, radius: float) -> Array:
	var out: Array = []
	var cs := VegScatter.CELL
	var i0 := int(floor((c.x - radius) / cs))
	var i1 := int(floor((c.x + radius) / cs))
	var j0 := int(floor((c.y - radius) / cs))
	var j1 := int(floor((c.y + radius) / cs))
	for cj in range(j0, j1 + 1):
		for ci in range(i0, i1 + 1):
			var mx := (float(ci) + 0.5) * cs
			var mz := (float(cj) + 0.5) * cs
			if Vector2(mx, mz).distance_to(c) > radius + cs * 0.75:
				continue
			var key := _ckey(layer, ci, cj)
			var arr: PackedFloat32Array
			if _cells.has(key):
				arr = _cells[key]
			else:
				arr = VegScatter.cell(layer, ci, cj)
				_cells[key] = arr
			if not arr.is_empty():
				out.append(arr)
	return out


func _slot_name(species: int, variant: int, lod: int, variants: int) -> String:
	match species:
		VegScatter.PINE:
			return "pine_l%d" % lod if lod > 0 else ("pine_b" if (variant > 0 and variants > 1) else "pine_a")
		VegScatter.BROAD:
			return "broad_l%d" % lod if lod > 0 else ("broad_b" if (variant > 0 and variants > 1) else "broad_a")
		VegScatter.DEAD:
			return "dead_b" if (variant > 0 and variants > 1) else "dead_a"
		VegScatter.BUSH:
			return "bush"
		VegScatter.FERN:
			return "fern"
		VegScatter.GRASS:
			return "grass"
		VegScatter.TUFT:
			return "tuft"
	return ["rock_a", "rock_b", "rock_c"][variant % 3]


func _job(cx: float, cz: float, tier: Dictionary) -> void:
	var c := Vector2(cx, cz)
	var out := {}                                                           # slot -> PackedFloat32Array (16 floats per instance)
	var near: Array = []
	var r0: float = tier["r0"]
	var r1: float = tier["r1"]
	var r2: float = tier["r2"]
	var variants: int = tier["variants"]
	var radii := [r2 + 20.0, float(tier["shrub"]) + 10.0, float(tier["grass"]) + 10.0, maxf(float(tier["rock"]), 420.0)]
	for layer in 4:
		for arr: PackedFloat32Array in _cell_list(layer, c, float(radii[layer])):
			var n := arr.size() / VegScatter.STRIDE
			for k in n:
				var o := k * VegScatter.STRIDE
				var x := arr[o]
				var z := arr[o + 2]
				var d := Vector2(x - cx, z - cz).length()
				var sp := int(arr[o + 5])
				var sc := arr[o + 4]
				var rnd := arr[o + 6]
				var variant := int(arr[o + 7])
				var lod := 0
				var g := 0.0                                                # dissolve: + fading out, - fading in
				var g2 := 0.0                                               # the second LOD present in a crossfade band
				var lod2 := -1
				match sp:
					VegScatter.PINE, VegScatter.BROAD:
						if d <= r0 * (1.0 - FADE):
							lod = 0
						elif d <= r0:
							lod = 0
							g = (d - r0 * (1.0 - FADE)) / (r0 * FADE)
							lod2 = 1
							g2 = -g
						elif d <= r1 * (1.0 - FADE):
							lod = 1
						elif d <= r1:
							lod = 1
							g = (d - r1 * (1.0 - FADE)) / (r1 * FADE)
							lod2 = 2
							g2 = -g
						elif d <= r2 * (1.0 - FADE):
							lod = 2
						elif d <= r2:
							lod = 2
							g = (d - r2 * (1.0 - FADE)) / (r2 * FADE)
						else:
							continue
					VegScatter.DEAD:
						var lim := r1 * 0.9
						if d > lim:
							continue
						g = maxf(0.0, (d - lim * 0.85) / (lim * 0.15))
					VegScatter.BUSH, VegScatter.FERN:
						var lim2: float = tier["shrub"]
						if d > lim2:
							continue
						g = maxf(0.0, (d - lim2 * 0.8) / (lim2 * 0.2))
					VegScatter.GRASS, VegScatter.TUFT:
						var lim3: float = tier["grass"]
						if d > lim3:
							continue
						g = maxf(0.0, (d - lim3 * 0.7) / (lim3 * 0.3))
					_:
						var lim4: float = tier["rock"] if sc < 2.4 else float(tier["rock"]) * 2.4
						if d > lim4:
							continue
						g = maxf(0.0, (d - lim4 * 0.85) / (lim4 * 0.15))
				if lod == 2:                                                    # the far LOD draws about half of the trees, a third bigger (the crowns close the gaps): half the instances for the same forest
					if rnd > FAR_KEEP:
						continue
					sc *= FAR_GROW
				_put(out, _slot_name(sp, variant, lod, variants), x, arr[o + 1], z, arr[o + 3], sc, rnd, g)
				if lod2 == 1 or (lod2 == 2 and rnd <= FAR_KEEP):
					_put(out, _slot_name(sp, variant, lod2, variants), x, arr[o + 1], z, arr[o + 3], sc * (FAR_GROW if lod2 == 2 else 1.0), rnd, g2)
				if d < BLOCK_RADIUS and (sp == VegScatter.PINE or sp == VegScatter.BROAD or sp == VegScatter.DEAD or (sp == VegScatter.ROCK and sc > 0.9)):
					var rad := 0.3 * sc if sp != VegScatter.ROCK else 1.15 * sc
					near.append([d, x, arr[o + 1], z, clampf(rad, 0.3, 4.5), 7.0 if sp != VegScatter.ROCK else 1.6 * sc])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	if near.size() > int(tier["blockers"]):
		near.resize(int(tier["blockers"]))
	# forget the cells that are far away now
	if _cells.size() > 3000:
		var drop: Array = []
		for key in _cells.keys():
			var layer2 := int(key) >> 40
			var ci := ((int(key) >> 20) & 0xfffff) - 4096
			var cj := (int(key) & 0xfffff) - 4096
			var mid := Vector2((float(ci) + 0.5) * VegScatter.CELL, (float(cj) + 0.5) * VegScatter.CELL)
			if mid.distance_to(c) > float(radii[layer2]) * 1.6:
				drop.append(key)
		for key in drop:
			_cells.erase(key)
	_mutex.lock()
	_result = {"slots": out, "near": near, "cells": _cells.size()}
	_mutex.unlock()


static func _put(out: Dictionary, slot: String, x: float, y: float, z: float, yaw: float, sc: float, rnd: float, g: float) -> void:
	var buf: PackedFloat32Array = out.get(slot, PackedFloat32Array())
	var s := sc * (0.92 + 0.16 * rnd)
	var cy := cos(yaw) * s
	var sy := sin(yaw) * s
	buf.append_array(PackedFloat32Array([cy, 0.0, sy, x, 0.0, s, 0.0, y, -sy, 0.0, cy, z, rnd, g, 0.0, 0.0]))
	out[slot] = buf


# --- the main thread --------------------------------------------------------------------------------------------------------------------------

func _apply(res: Dictionary) -> void:
	jobs_done += 1
	var slots: Dictionary = res["slots"]
	var total := 0
	var tris := 0
	for name_k in slots.keys():
		var buf: PackedFloat32Array = slots[name_k]
		var n := buf.size() / 16
		var s := _slot(String(name_k))
		_fill(s, buf, n)
		total += n
		tris += n * int(s["mtris"])
	for name_k in _slots.keys():
		if not slots.has(name_k):
			var s2: Dictionary = _slots[name_k]
			if int(s2["n"]) > 0:
				_fill(s2, PackedFloat32Array(), 0)
	_stats["instances"] = total
	_stats["tris"] = tris
	_stats["cells"] = int(res["cells"])
	_stats["jobs"] = jobs_done
	_place_blockers(res["near"])


func _slot(nm: String) -> Dictionary:
	if _slots.has(nm):
		return _slots[nm]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = VegKit.mesh(nm)
	mm.instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = VegKit.material(nm)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.top_level = true
	mi.visible = false
	mi.custom_aabb = AABB(Vector3(-TerrainHeight.WORLD_HALF, -60.0, -TerrainHeight.WORLD_HALF), Vector3(2.0 * TerrainHeight.WORLD_HALF, 700.0, 2.0 * TerrainHeight.WORLD_HALF))
	add_child(mi)
	var s := {"mi": mi, "mm": mm, "cap": 0, "n": 0, "mtris": VegKit.tris(nm)}
	_slots[nm] = s
	return s


func _fill(s: Dictionary, buf: PackedFloat32Array, n: int) -> void:
	var mm: MultiMesh = s["mm"]
	var mi: MultiMeshInstance3D = s["mi"]
	if n == 0:
		mm.visible_instance_count = 0
		mi.visible = false
		s["n"] = 0
		return
	var cap: int = s["cap"]
	if n > cap or n < cap / 3:
		cap = ((int(float(n) * 1.3) + 63) / 64) * 64
		mm.instance_count = cap
		s["cap"] = cap
	if buf.size() < cap * 16:
		buf.resize(cap * 16)
	mm.buffer = buf
	mm.visible_instance_count = n
	s["n"] = n
	mi.visible = true


func _ensure_pool(n: int) -> void:
	while _pool.size() < n:
		var b := StaticBody3D.new()
		b.name = "Trunk%d" % _pool.size()
		b.collision_layer = Game.L_WORLD
		b.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = CylinderShape3D.new()
		b.add_child(cs)
		b.top_level = true
		b.position = Vector3(0.0, -2000.0, 0.0)
		add_child(b)
		_pool.append(b)
	for i in _pool.size():
		_pool[i].process_mode = Node.PROCESS_MODE_INHERIT if i < n else Node.PROCESS_MODE_DISABLED


func _place_blockers(near: Array) -> void:
	var used := mini(near.size(), int(_tier["blockers"]))
	for i in _pool.size():
		var b := _pool[i]
		if i < used:
			var e: Array = near[i]
			var cyl := (b.get_child(0) as CollisionShape3D).shape as CylinderShape3D
			cyl.radius = float(e[4])
			cyl.height = float(e[5])
			b.global_position = Vector3(float(e[1]), float(e[2]) + float(e[5]) * 0.5 - 0.1, float(e[3]))
		else:
			b.global_position = Vector3(0.0, -2000.0, 0.0)
	_pool_used = used
	_stats["colliders"] = used


func stats() -> Dictionary:
	var d := _stats.duplicate()
	var drawn := 0
	for s: Dictionary in _slots.values():
		if int(s["n"]) > 0:
			drawn += 1
	d["slots"] = drawn
	return d


## The names and instance counts of the pieces drawn right now ({slot: n}).
func slot_counts() -> Dictionary:
	var out := {}
	for k in _slots.keys():
		if int((_slots[k] as Dictionary)["n"]) > 0:
			out[k] = int((_slots[k] as Dictionary)["n"])
	return out
