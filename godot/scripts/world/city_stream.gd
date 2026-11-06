extends RefCounted
## Camera-centred instance windows for the static MultiMesh families of the city.
##
## A MultiMesh of the whole city has one bounding box that always contains the camera, so the engine can never cull any of its instances:
## all 6800 props and 900 skyline towers would be submitted every frame, wherever the camera looks. Instead every family keeps its
## instances bucketed in square cells, and the MultiMesh only draws the cells that lie within the family's radius of the camera
## (`visible_instance_count` over a re-filled buffer). The shaders shrink an instance to nothing between 75 % and 100 % of the radius
## (see `lod_range` in prop_core.gdshaderinc and building_core.gdshaderinc), so instances never pop.
##
## The window is rebuilt only when the camera has moved `step` metres (and only when the set of cells really changes), at most
## MAX_PER_FRAME families per frame; a jump (teleport, respawn, camera cut) rebuilds everything at once so no frame shows a hole.
## Without a camera (headless tests) the families keep all their instances.

const MAX_PER_FRAME := 2
const FADE_START := 0.75           ## fraction of the radius where instances start to shrink
## The default cell grid of the playable city: 40 m cells from -(HALF + 40) over (2 * HALF + 80) / 40 cells per side.
const CITY_ORIGIN := -CityLayout.HALF - 40.0
const CITY_CELL := 40.0
const CITY_CELLS := int((2.0 * CityLayout.HALF + 80.0) / 40.0)


class Family extends RefCounted:
	var name := ""
	var mm: MultiMesh
	var stride := 0
	var total := 0
	var tris := 0                  ## triangles of one instance
	var radius := 150.0            ## metres from the camera where the family has faded out completely (before the quality scale)
	var scale := 1.0               ## quality scale of the radius
	var origin := CITY_ORIGIN      ## the cell grid: lower-left corner, cell size and cells per side
	var cell := 40.0
	var n := CITY_CELLS
	var cells: Array = []          ## n * n entries; each a PackedFloat32Array with `stride` floats per instance (empty cells stay empty)
	var counts := PackedInt32Array()
	var materials: Array[ShaderMaterial] = []
	var built_at := Vector2(1.0e9, 1.0e9)
	var step := 12.0
	var shown := -1                ## instances currently drawn (-1: not windowed yet, all of them)
	var sig := -1
	var rank_off := -1             ## >= 0: float offset (in a record) of a 0..1 rank; only records with rank < keep are drawn (steam: puffs per vent by tier)
	var keep := 1.0

	func fade_end() -> float:
		return radius * scale

	func apply_lod() -> void:
		var e := fade_end()
		for m in materials:
			m.set_shader_parameter(&"lod_range", Vector2(e * FADE_START, e))


var families: Array[Family] = []
var _sel := PackedInt32Array()


## Register a family whose MultiMesh already holds its full buffer (instance-major, `stride` floats per instance, origin in floats 3 and 11).
func add(name: String, mm: MultiMesh, radius: float, tris: int, materials: Array[ShaderMaterial], grid_origin := CITY_ORIGIN, cell := CITY_CELL, cells_per_side := CITY_CELLS) -> Family:
	var f := Family.new()
	f.name = name
	f.mm = mm
	f.stride = 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
	f.total = mm.instance_count
	f.tris = tris
	f.radius = radius
	f.origin = grid_origin
	f.cell = cell
	f.n = cells_per_side
	f.materials = materials
	f.step = 10.0 + 0.9 * float(families.size() % 7)           # staggered, so the families do not all rebuild in the same frame
	f.cells.resize(cells_per_side * cells_per_side)
	f.counts.resize(cells_per_side * cells_per_side)
	for c in f.cells.size():
		f.cells[c] = PackedFloat32Array()
	var buf := mm.buffer
	var s := f.stride
	for i in f.total:
		var o := i * s
		var c := _cell_of(f, buf[o + 3], buf[o + 11])
		var arr: PackedFloat32Array = f.cells[c]
		arr.append_array(buf.slice(o, o + s))
		f.cells[c] = arr
		f.counts[c] += 1
	f.apply_lod()
	families.append(f)
	return f


## Triangles of one instance of a mesh (all surfaces).
static func mesh_triangles(mesh: Mesh) -> int:
	var t := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.size() > 0:
			t += idx.size() / 3
		else:
			t += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t


static func _cell_of(f: Family, x: float, z: float) -> int:
	var cx := clampi(int(floor((x - f.origin) / f.cell)), 0, f.n - 1)
	var cz := clampi(int(floor((z - f.origin) / f.cell)), 0, f.n - 1)
	return cz * f.n + cx


## Move every family's window to the camera at `cam` (x, z). A family rebuilds when the camera has left its window's centre by
## `step` metres (a few per frame; a big jump rebuilds at once); `force` rebuilds all of them now.
func update(cam: Vector2, force := false) -> void:
	var rebuilt := 0
	for f in families:
		var moved := cam.distance_to(f.built_at)
		if force or moved > f.step + 14.0 or (moved > f.step and rebuilt < MAX_PER_FRAME):
			rebuild(f, cam)
			rebuilt += 1


## Re-centre one family's window on `cam`.
func rebuild(f: Family, cam: Vector2) -> void:
	f.built_at = cam
	# the window must cover everything within fade_end of the camera until the next rebuild: the camera may travel `step` (plus a few
	# frames of delay), and an included cell only needs to touch the disc
	var r := f.fade_end() + f.step + 16.0
	var c0x := maxi(0, int(floor((cam.x - r - f.origin) / f.cell)))
	var c1x := mini(f.n - 1, int(floor((cam.x + r - f.origin) / f.cell)))
	var c0z := maxi(0, int(floor((cam.y - r - f.origin) / f.cell)))
	var c1z := mini(f.n - 1, int(floor((cam.y + r - f.origin) / f.cell)))
	_sel.clear()
	var sig := 7
	for cz in range(c0z, c1z + 1):
		var z0 := f.origin + float(cz) * f.cell
		var dz := maxf(maxf(z0 - cam.y, cam.y - (z0 + f.cell)), 0.0)
		for cx in range(c0x, c1x + 1):
			var idx := cz * f.n + cx
			if f.counts[idx] == 0:
				continue
			var x0 := f.origin + float(cx) * f.cell
			var dx := maxf(maxf(x0 - cam.x, cam.x - (x0 + f.cell)), 0.0)
			if dx * dx + dz * dz > r * r:
				continue
			_sel.append(idx)
			sig = sig * 1000003 + idx
	if sig == f.sig and f.shown >= 0:
		return                                           # the same cells as before: nothing to upload
	f.sig = sig
	var out := PackedFloat32Array()
	var shown := 0
	for idx in _sel:
		if f.rank_off >= 0 and f.keep < 1.0:
			var cell: PackedFloat32Array = f.cells[idx]
			for o in range(0, cell.size(), f.stride):
				if cell[o + f.rank_off] < f.keep:
					out.append_array(cell.slice(o, o + f.stride))
					shown += 1
			continue
		out.append_array(f.cells[idx])
		shown += f.counts[idx]
	out.resize(f.total * f.stride)                       # the tail is never drawn (visible_instance_count)
	f.mm.buffer = out
	f.mm.visible_instance_count = shown
	f.shown = shown


## Show every instance again (no windows). The instance order changes to cell order, which does not matter for a MultiMesh.
func show_all() -> void:
	for f in families:
		var out := PackedFloat32Array()
		for idx in f.cells.size():
			if f.counts[idx] > 0:
				out.append_array(f.cells[idx])
		f.mm.buffer = out
		f.mm.visible_instance_count = f.total
		f.shown = -1
		f.sig = -1
		f.built_at = Vector2(1.0e9, 1.0e9)


## Draw only the records whose rank (float `rank_off` of a record) is below `keep` (the puffs per vent of the steam, by tier).
func set_keep(f: Family, rank_off: int, keep: float) -> void:
	f.rank_off = rank_off
	f.keep = keep
	f.built_at = Vector2(1.0e9, 1.0e9)
	f.sig = -1


## Apply a new quality scale to the radii (and the shader fade ranges); the windows are rebuilt on the next update.
func set_scale(s: float) -> void:
	for f in families:
		f.scale = s
		f.apply_lod()
		f.built_at = Vector2(1.0e9, 1.0e9)
		f.sig = -1


## Triangles currently drawn by the real (not the mirrored) nodes of the windowed families.
func visible_triangles() -> int:
	var t := 0
	for f in families:
		t += f.tris * (f.total if f.shown < 0 else f.shown)
	return t


func total_triangles() -> int:
	var t := 0
	for f in families:
		t += f.tris * f.total
	return t
