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

## Wave 112: the trees are the nine species of LandKit (LOD0 full or lite, LOD1, one shared cross-billboard impostor mesh): `lite` = LOW uses the lite LOD0, `imp_keep` = the share of
## the far trees the impostors draw (the kept ones grow `imp_grow` times so the forest keeps its mass). Radii: LOD0 to r0, LOD1 to r1, impostors to r2.
const TIERS := [
	{"r0": 17.0, "r1": 58.0, "r2": 150.0, "shrub": 30.0, "grass": 15.0, "rock": 80.0, "variants": 1, "blockers": 26, "lite": true, "imp_keep": 0.5, "imp_grow": 1.25},
	{"r0": 27.0, "r1": 86.0, "r2": 240.0, "shrub": 44.0, "grass": 22.0, "rock": 120.0, "variants": 2, "blockers": 38, "lite": false, "imp_keep": 0.62, "imp_grow": 1.18},
	{"r0": 40.0, "r1": 124.0, "r2": 350.0, "shrub": 64.0, "grass": 32.0, "rock": 170.0, "variants": 2, "blockers": 52, "lite": false, "imp_keep": 0.8, "imp_grow": 1.1},
]
const TREE_NAMES := {0: "pine", 1: "oak", 2: "dead", 8: "fir", 9: "birch", 10: "palm", 11: "alien", 12: "poplar", 13: "acacia"}
const WAKE_EDGE := 470.0                           ## the vegetation sleeps until the hero is this far from the middle of the city (max of |x| and |z|): the start and the centre of the city pay for none of it (no kit, no textures, no collider pool)
const MOVE_TRIGGER := 5.0
const MIN_INTERVAL := 0.12
const BLOCK_RADIUS := 30.0
const FADE := 0.15
const FAR_KEEP := 0.55
const FAR_GROW := 1.3

static var instance: VegetationWorld = null
static var giants_list: Array = []                 ## the ancient trees round the hero from the last job: [{pos (the top), base, height, radius, name}] (AnchorWorld.anchors_near adds them as kind &"tree")

var quality := 1
var focus := Vector3.INF                          ## the point the plants are arranged around (the hero, the camera without one)
var enabled := true
var awake := false
var jobs_done := 0
var _slots := {}                                  ## slot name -> {mi: MultiMeshInstance3D, mm: MultiMesh, cap: int, n: int, tris: int}
var _cells := {}                                  ## worker-side cache: (layer, ci, cj) key -> PackedFloat32Array (only the running job touches it)
var _task := -1
var _result := {}
var _mutex := Mutex.new()
var _center := Vector2(1.0e9, 1.0e9)
var _t := 0.0
var _threaded := true
var _land := false                                ## the landscape trees (LandKit) are available; without them the old Quaternius pieces are drawn
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
	_tier = TIERS[quality]
	set_process(true)


## Loads the kit (meshes, the foliage and bark textures), builds the collider pool and starts the wind: called when the hero leaves the middle of the city, by `settle` and by tests.
func wake() -> void:
	if awake:
		return
	awake = true
	if not VegKit.available():
		enabled = false
		return
	VegScatter.warm()
	_land = LandKit.available()
	LandClimate.attach(self)
	set_quality(quality)


func _exit_tree() -> void:
	if instance == self:
		instance = null
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	_tier = TIERS[quality]
	if not awake:
		return                                                                 # asleep: only the tier is remembered
	LandKit.set_quality(quality)
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
	if not awake:
		var f0 := _focus_point()
		if f0.is_finite() and maxf(absf(f0.x), absf(f0.z)) > WAKE_EDGE:
			wake()
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
	wake()
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
	if _land:
		match species:
			VegScatter.GRASS:
				return "g_grass1" if variant != 1 else "g_grass2"
			VegScatter.TUFT:
				return "g_dry" if variant != 2 else "g_tall"
			VegScatter.FLOWER:
				return ["g_daisy", "g_poppy", "g_lav", "g_clover"][variant % 4]
			VegScatter.FERN:
				return "g_fern1" if variant != 1 else "g_fern2"
			VegScatter.BUSH:
				return "g_bush1" if variant != 1 else "g_bush2"
			VegScatter.REED:
				return "g_reed"
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
		VegScatter.GRASS, VegScatter.REED:
			return "grass"
		VegScatter.TUFT, VegScatter.FLOWER:
			return "tuft"
		VegScatter.FIR, VegScatter.POPLAR:
			return "pine_l%d" % lod if lod > 0 else "pine_a"
		VegScatter.BIRCH, VegScatter.PALM, VegScatter.ALIEN, VegScatter.ACACIA:
			return "broad_l%d" % lod if lod > 0 else "broad_a"
	return ["rock_a", "rock_b", "rock_c"][variant % 3]


func _job(cx: float, cz: float, tier: Dictionary) -> void:
	var c := Vector2(cx, cz)
	var out := {}                                                           # slot -> PackedFloat32Array (16 floats per instance)
	var near: Array = []
	var giants: Array = []
	var r0: float = tier["r0"]
	var r1: float = tier["r1"]
	var r2: float = tier["r2"]
	var variants: int = tier["variants"]
	var lite: bool = tier["lite"]
	var imp_keep: float = tier["imp_keep"]
	var imp_grow: float = tier["imp_grow"]
	var land := _land
	var radii := [r2 + 20.0, float(tier["shrub"]) + 10.0, float(tier["grass"]) + 10.0, maxf(float(tier["rock"]), 420.0), r2 + 20.0, float(tier["grass"]) * 1.4 + 10.0, float(tier["grass"]) * 4.6 + 10.0]
	for layer in VegScatter.LAYERS:
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
				if land and (sp == VegScatter.DRIFT or sp == VegScatter.PEBBLE):                  # the shore: pebbles near, logs of driftwood a bit farther
					var lims: float = float(tier["grass"]) * (4.6 if sp == VegScatter.DRIFT else 2.0)
					if d > lims:
						continue
					var gsh := maxf(0.0, (d - lims * 0.8) / (lims * 0.2))
					if sp == VegScatter.DRIFT:
						_put(out, "drift_%s_%s" % ["a" if variant == 0 else "b", "1" if d > 30.0 else "0"], x, arr[o + 1], z, arr[o + 3], sc, rnd, gsh)
					else:
						var pl := 9 if rnd < 0.5 else (10 if rnd < 0.8 else 4)                      # scree grey, dark sea-worn stones, a few pale ones (never the beach layer: they melted into the sand)
						_put(out, "pebble_%s_0" % ["a" if variant == 0 else "c"], x, arr[o + 1], z, arr[o + 3], sc, rnd, gsh, -1.0, -1.0, float(pl), 1.0)
					continue
				if land and sp == VegScatter.LOG:                                                 # a fallen trunk of the forest floor
					var lim_l: float = float(tier["shrub"])
					if d > lim_l:
						continue
					_put(out, "log_%s_%s" % ["a" if variant == 0 else "b", "1" if d > 36.0 else "0"], x, arr[o + 1], z, arr[o + 3], sc, rnd, maxf(0.0, (d - lim_l * 0.8) / (lim_l * 0.2)))
					continue
				var is_tree := land and TREE_NAMES.has(sp)
				if is_tree or sp == VegScatter.PINE or sp == VegScatter.BROAD:
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
				elif sp == VegScatter.DEAD or sp == VegScatter.FIR or sp == VegScatter.BIRCH or sp == VegScatter.PALM or sp == VegScatter.ALIEN or sp == VegScatter.POPLAR or sp == VegScatter.ACACIA:
					var limd := r1 * 0.9
					if d > limd:
						continue
					g = maxf(0.0, (d - limd * 0.85) / (limd * 0.15))
				elif sp == VegScatter.BUSH or sp == VegScatter.FERN:
					var lim2: float = tier["shrub"]
					if d > lim2:
						continue
					g = maxf(0.0, (d - lim2 * 0.8) / (lim2 * 0.2))
				elif sp == VegScatter.GRASS or sp == VegScatter.TUFT or sp == VegScatter.FLOWER or sp == VegScatter.REED:
					var lim3: float = tier["grass"] * (1.4 if sp == VegScatter.REED else 1.0)
					if d > lim3:
						continue
					g = maxf(0.0, (d - lim3 * 0.7) / (lim3 * 0.3))
				else:
					var lim4: float = tier["rock"] if sc < 2.4 else float(tier["rock"]) * 2.4
					if d > lim4:
						continue
					g = maxf(0.0, (d - lim4 * 0.85) / (lim4 * 0.15))
				if is_tree:
					var nm: String = TREE_NAMES[sp]
					if lod == 2:
						if rnd > imp_keep:
							continue
						sc *= imp_grow
					_put_tree(out, nm, lod, lite, x, arr[o + 1], z, arr[o + 3], sc, rnd, g)
					if variant == VegScatter.GIANT and d < 260.0:
						var gh := LandKit.height(nm) * sc
						giants.append({"pos": Vector3(x, arr[o + 1] + gh * 0.92, z), "base": Vector3(x, arr[o + 1], z), "height": gh, "radius": LandKit.trunk_radius(nm) * sc, "name": "ANCIENT " + nm.to_upper()})
					if lod2 == 1 or (lod2 == 2 and rnd <= imp_keep):
						_put_tree(out, nm, lod2, lite, x, arr[o + 1], z, arr[o + 3], sc * (imp_grow if lod2 == 2 else 1.0), rnd, g2)
					if d < BLOCK_RADIUS:
						var rad := LandKit.trunk_radius(nm) * sc * 0.9 + 0.12
						near.append([d, x, arr[o + 1], z, clampf(rad, 0.3, 1.8), 7.0 if variant != VegScatter.GIANT else 16.0])
					continue
				if land and sp == VegScatter.ROCK:
					var shape: String = ["a", "b", "c", "d"][int(rnd * 4.0) % 4]
					var lod_d := 34.0 * sqrt(maxf(sc, 1.0))
					var rlayer := 4
					var dwq := TerrainBase.desert_weight(x, z)
					if dwq > 0.4 or rnd > 0.84:
						rlayer = 8 if rnd < 0.9 else 9
					elif arr[o + 1] > 120.0 or rnd < 0.2:
						rlayer = 10
					elif rnd > 0.7:
						rlayer = 4
					_put(out, "rock_%s%s" % [shape, "_1" if d > lod_d else ""], x, arr[o + 1], z, arr[o + 3], sc, rnd, g, -1.0, -1.0, float(rlayer))
					if d < BLOCK_RADIUS and sc > 0.9:
						near.append([d, x, arr[o + 1], z, clampf(1.15 * sc, 0.3, 4.5), 1.6 * sc])
					continue
				if lod == 2:                                                    # old pieces (without the landscape kit): the far LOD draws about half of the trees, a third bigger
					if rnd > FAR_KEEP:
						continue
					sc *= FAR_GROW
				_put(out, _slot_name(sp, variant, lod, variants), x, arr[o + 1], z, arr[o + 3], sc, rnd, g)
				if lod2 == 1 or (lod2 == 2 and rnd <= FAR_KEEP):
					_put(out, _slot_name(sp, variant, lod2, variants), x, arr[o + 1], z, arr[o + 3], sc * (FAR_GROW if lod2 == 2 else 1.0), rnd, g2)
				if d < BLOCK_RADIUS and (sp == VegScatter.PINE or sp == VegScatter.BROAD or sp == VegScatter.DEAD or (sp == VegScatter.ROCK and sc > 0.9)):
					var rad2 := 0.3 * sc if sp != VegScatter.ROCK else 1.15 * sc
					near.append([d, x, arr[o + 1], z, clampf(rad2, 0.3, 4.5), 7.0 if sp != VegScatter.ROCK else 1.6 * sc])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	if near.size() > int(tier["blockers"]):
		near.resize(int(tier["blockers"]))
	# forget the cells that are far away now
	if _cells.size() > 4200:
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
	_result = {"slots": out, "near": near, "cells": _cells.size(), "giants": giants}
	_mutex.unlock()


static func _put_tree(out: Dictionary, nm: String, lod: int, lite: bool, x: float, y: float, z: float, yaw: float, sc: float, rnd: float, g: float) -> void:
	if lod >= 2:
		var sz := LandKit.impostor_size(nm)
		_put(out, "imp", x, y, z, yaw, sc, rnd, g, sz.x, sz.y, float(LandKit.impostor_cell(nm)))
	elif lod == 1:
		_put(out, nm + "_1", x, y, z, yaw, sc, rnd, g)
	else:
		_put(out, nm + ("_0l" if lite else "_0"), x, y, z, yaw, sc, rnd, g)


static func _put(out: Dictionary, slot: String, x: float, y: float, z: float, yaw: float, sc: float, rnd: float, g: float, width := -1.0, hgt := -1.0, cell := 0.0, flag := 0.0) -> void:
	var buf: PackedFloat32Array = out.get(slot, PackedFloat32Array())
	var j := 0.92 + 0.16 * rnd
	var sw := (width if width > 0.0 else 1.0) * sc * j
	var sh := (hgt if hgt > 0.0 else 1.0) * sc * j
	var cy := cos(yaw)
	var sy := sin(yaw)
	buf.append_array(PackedFloat32Array([cy * sw, 0.0, sy * sw, x, 0.0, sh, 0.0, y, -sy * sw, 0.0, cy * sw, z, rnd, g, cell, flag]))
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
	giants_list = res.get("giants", [])


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
			b.set_meta(&"surface", &"wood" if float(e[5]) >= 5.0 else &"concrete")      # wave 114: a bullet knows a trunk from a boulder (impact sound, splinters, no hole)
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
