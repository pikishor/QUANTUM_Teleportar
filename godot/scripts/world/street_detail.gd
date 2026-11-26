class_name StreetDetail
extends Node3D
## w1242-street (finish of the wave 123 street detail; owner round 7: "not many details on the street").
## New street prop kinds, storefront depth and the outskirts' street clutter, drawn as ONE merged mesh around the camera (the street kit's way: city_kit_window.gd), so the whole
## layer costs ONE draw call however many kinds and props it holds. Placements are made once (deterministic, own random stream: no other placement of the city moves), in 40 m cells;
## the window concatenates the cached local geometry of the props in the cells within NEAR m of the camera (billboards to their own FAR radius) and re-fills when the camera moved STEP m.
##
##   kerb       newspaper boxes, bike racks, parking meters, street trees with grates, traffic signs (stop / no entry / speed), street name signs at every junction (two blades with the
##              names of the two roads), on the kerb strip of every block face; never in a door lane (StreetClutter), never on a bench seat or bus stop, never where the sidewalk
##              between the prop and the building would be narrower than WALK_GAP (the hero's path), never inside the street kit's own props (its spacing grid).
##   rooftop    a few billboards with original brand names on low roofs facing the street.
##   storefront per city door: a door frame with a step (the door reads recessed), an awning, a projecting shop sign with the shop's name (below the facade's sign band), and either
##              side of the door a shop window display (a bay box with lit goods) or a roller shutter (a closed shop). Walk-in shop doors (ShopFronts) keep their own glass front.
##   outskirts  bins, crates, mailboxes and cones along the main street of the towns (SettlementPlan.fits: off the road, off every house and yard).
## Text is geometry: a 5 x 7 block font (own-made) in the same mesh. Props are decor without colliders (thin, at the kerb or on the wall, never in a lane).
## Switch: `on` (env W1242_STREET_OLD=1 = the wave 124 street: no layer, no tower glass, the old shop sign height, the old accident cars, the old bus stop test).

const MB := preload("res://scripts/world/mesh_builder.gd")
const Kit := preload("res://scripts/world/city_kit.gd")
const Districts := preload("res://scripts/world/city_districts.gd")

static var on: bool = OS.get_environment("W1242_STREET_OLD") != "1"
static var instance: StreetDetail
static var _glass: StandardMaterial3D

const NEWS_BOX := 0
const BIKE_RACK := 1
const METER := 2
const TREE := 3
const TRAFFIC_SIGN := 4
const NAME_SIGN := 5
const BILLBOARD := 6
const SHOP_SIGN := 7
const AWNING := 8
const DOOR_FRAME := 9
const DISPLAY := 10
const SHUTTER := 11
const CLUTTER := 12
const KIND_COUNT := 13
const KIND_NAMES: Array[String] = ["NewsBox", "BikeRack", "Meter", "StreetTree", "TrafficSign", "NameSign", "Billboard", "ShopSign", "Awning", "DoorFrame", "Display", "Shutter", "Clutter"]
const KIND_R: Array[float] = [0.4, 0.95, 0.2, 0.65, 0.25, 0.25, 2.8, 0.55, 1.4, 1.5, 0.9, 1.2, 0.7]   ## footprint radius (m) for spacing and the door-lane test
const GROUND: Array[int] = [NEWS_BOX, BIKE_RACK, METER, TREE, TRAFFIC_SIGN, NAME_SIGN, CLUTTER]     ## the kinds that stand on the sidewalk (the lane test)

const CELL := 40.0
const STEP := 8.0
const NEAR_BASE := 34.0                ## m, times the quality scale (LOW 0.65, MED 0.85, HIGH 1.0)
const FAR_BILLBOARD := 230.0
const CROWN_LIFT := 1.2               ## m the street tree crowns are raised (underside 3.45 m: over the follow camera)
const AWNING_HW := 1.9               ## m, half the awning width (w1242-critic: the blade sign stands beyond it)
const WALK_GAP := 1.4                  ## m of free sidewalk kept between a kerb prop and the building
const STREET_WORDS: Array[String] = ["ALDER", "BRISK", "CINDER", "DUSK", "EMBER", "FLINT", "GALE", "HARROW", "IRIS", "JUNIPER", "KESTREL", "LUMEN", "MARLOW", "NOVA", "ONYX",
	"PIKE", "QUILL", "RIVET", "SABLE", "TALLOW", "UMBER", "VESPER", "WREN", "XENON", "YARROW", "ZEPHYR", "ASH"]
const BRANDS: Array[String] = ["SKYNOODLE", "RIFT TAXI", "QUANTA CELL", "VOLT COLA", "NIMBUS AIR", "ORBIT BANK", "PIXEL PALS", "KAPPA FIZZ"]

## 5 x 7 block font (own-made): rows top to bottom, '#' = lit.
const FONT := {
	"A": ".###.#...##...########...##...##...#", "B": "####.#...#####.#...##...##...#####.", "C": ".###.#...##....#....#....#...#.###.", "D": "####.#...##...##...##...##...#####.",
	"E": "######....####.#....#....#....#####", "F": "######....####.#....#....#....#....", "G": ".###.#...##....#.####...##...#.####", "H": "#...##...##...#######...##...##...#",
	"I": ".###...#....#....#....#....#...###.", "J": "..###...#....#....#....##...#.###..", "K": "#...##..#.#.#..##...#.#..#..#.#...#", "L": "#....#....#....#....#....#....#####",
	"M": "#...###.###.#.##...##...##...##...#", "N": "#...###..##.#.##..###...##...##...#", "O": ".###.#...##...##...##...##...#.###.", "P": "####.#...##...#####.#....#....#....",
	"Q": ".###.#...##...##...##.#.##..#..##.#", "R": "####.#...##...#####.#.#..#..#.#...#", "S": ".####.....#.....###.....#....#####.", "T": "#####..#....#....#....#....#....#..",
	"U": "#...##...##...##...##...##...#.###.", "V": "#...##...##...##...##...#.#.#...#..", "W": "#...##...##...##.#.##.#.##.#.#.#.#.", "X": "#...##...#.#.#...#...#.#.#...##...#",
	"Y": "#...##...#.#.#...#....#....#....#..", "Z": "#####....#...#...#...#...#....#####", "0": ".###.#...##..###.#.###..##...#.###.", "1": "..#...##....#....#....#....#...###.",
	"2": ".###.#...#....#...#...#...#...#####", "3": "#####...#...#.....#....##...#.###.", "4": "...#...##..#.#.#..#.#####...#....#.", "5": "######....####.....#....##...#.###.",
	"6": "..##..#...#....####.#...##...#.###.", "7": "#####....#...#...#...#....#....#...", "8": ".###.#...##...#.###.#...##...#.###.", "9": ".###.#...##...#.####....#...#..##..",
	"-": "...............###...............", ".": "..............................##...", "&": ".##..#..#.#.#...#...#.#.##..#..##.#",
}

var cells := {}                         ## cell key -> PackedFloat32Array, stride 8: kind, x, y, z, yaw, seed, variant, text id
var texts: Array[String] = [""]
var placements: Array[Dictionary] = []  ## {kind, pos, yaw, text, door (index or -1), n (outward normal for wall kinds)}
var kind_count := PackedInt32Array()
var built := false
var lanes := {}                         ## StreetClutter lane grid of every door (city, walk-in shops, towers, towns)
var mesh := ArrayMesh.new()
var node: MeshInstance3D
var q_scale := 1.0
var triangles := 0
var near_props := 0
var rebuilds := 0
var _built_at := Vector2(1.0e9, 1.0e9)
var _sig := -1
var _geo := {}
var _space := {}                        ## own spacing grid: key -> Array[Vector3(x, z, r)]
var _city: Node3D
var _seat_grid := {}                    ## 8 m cells -> Array[Vector3] of bench seats (r 1.8) and bus stops (r 3.2) as (x, z, r)
var _door_grid := {}                    ## 8 m cells -> Array[int] door indices
var _rng := RandomNumberGenerator.new()
static var solid_on: bool = OS.get_environment("W1242C_OLD") != "1"   ## w1242-critic: trunks, news boxes and town clutter stop the hero (W1242C_OLD=1: walk-through props, raised-crown off)
var _body := RID()                      ## one static body: the near window's solid props (no nodes)
var _shapes := {}                       ## kind*4+variant -> [shape RID, local Transform3D]
var solids := 0


## The shared window glass (tower and lobby window holes): light blue, see-through, both faces.
static func glass_material() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.albedo_color = Color(0.5, 0.68, 0.8, 0.34)
		_glass.metallic = 0.55
		_glass.roughness = 0.06
		_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass


## city.gd hook (_build_kit): the layer under `parent`, drawn with the street kit's material.
static func attach(city: Node3D, parent: Node3D, material: Material) -> StreetDetail:
	var sd := StreetDetail.new()
	sd.name = "StreetDetail"
	sd._city = city
	parent.add_child(sd)
	sd.node = MeshInstance3D.new()
	sd.node.name = "StreetDetailMesh"
	sd.node.mesh = sd.mesh
	sd.node.material_override = material
	sd.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sd.node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	sd.add_child(sd.node)
	return sd


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null
	if _body.is_valid():
		PhysicsServer3D.free_rid(_body)
		_body = RID()
	for e: Array in _shapes.values():
		PhysicsServer3D.free_rid(e[0])
	_shapes.clear()


func _process(_delta: float) -> void:
	if not built:
		if _city == null or not is_instance_valid(_city) or Game.world != _city:
			return
		build()
	var q := int(_city.get(&"quality")) if _city.get(&"quality") != null else 1
	var sc: float = [0.65, 0.85, 1.0][clampi(q, 0, 2)]
	if sc != q_scale:
		q_scale = sc
		_sig = -1
		_built_at = Vector2(1.0e9, 1.0e9)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		update(Vector2(cam.global_position.x, cam.global_position.z))


func near_radius() -> float:
	return NEAR_BASE * q_scale


# --- placement --------------------------------------------------------------------------------------------------------------------

func build() -> void:
	built = true
	cells.clear()
	placements.clear()
	texts = [""]
	_space.clear()
	kind_count = PackedInt32Array()
	kind_count.resize(KIND_COUNT)
	_rng.seed = 1242123
	var layout: CityLayout = _city.layout
	var doors: Array = _city.doors
	var all_lanes := StreetClutter.lanes_of(doors)
	for d: Dictionary in doors:
		if d.has("pos0"):
			var n0: Vector3 = d["normal"]
			var w0: Vector3 = (d["pos"] as Vector3) - n0 * 1.3
			w0.y = 0.0
			all_lanes.append([w0, n0, StreetClutter.kerb_out(w0, n0)])
	if TowerFloors.instance != null:
		for tw: Dictionary in TowerFloors.instance.towers:
			var w2 := TowerFloors.door_pos(tw, 0.0)
			w2.y = 0.0
			var n2 := TowerFloors.door_pos(tw, 1.0) - TowerFloors.door_pos(tw, 0.0)
			n2.y = 0.0
			n2 = n2.normalized()
			all_lanes.append([w2, n2, StreetClutter.kerb_out(w2, n2)])
	lanes = StreetClutter._index(all_lanes)
	_seat_grid.clear()
	for bn: Vector3 in StreetLife.benches:
		_grid_put(_seat_grid, bn.x, bn.z, Vector3(bn.x, bn.z, 1.8))
	for st: Vector3 in StreetLife.bus_stops:
		_grid_put(_seat_grid, st.x, st.z, Vector3(st.x, st.z, 3.2))
	_door_grid.clear()
	for di in doors.size():
		var wd: Vector3 = (doors[di] as Dictionary)["wall"]
		_grid_put(_door_grid, wd.x, wd.z, di)
	_storefronts(layout, doors)
	_kerb(layout)
	_billboards(layout)
	_outskirts()


func _key(x: float, z: float) -> int:
	return (int(floorf(x / CELL)) + 512) * 1024 + int(floorf(z / CELL)) + 512


func _skey(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / 4.0), floori(z / 4.0))


func _space_free(x: float, z: float, r: float) -> bool:
	var k := _skey(x, z)
	for ix in range(k.x - 1, k.x + 2):
		for iz in range(k.y - 1, k.y + 2):
			for o: Vector3 in _space.get(Vector2i(ix, iz), []):
				if Vector2(o.x - x, o.y - z).length() < o.z + r:
					return false
	return true


func _text_id(s: String) -> int:
	var i := texts.find(s)
	if i < 0:
		texts.append(s)
		i = texts.size() - 1
	return i


func _add(kind: int, pos: Vector3, yaw: float, variant: int, text := "", door := -1, n := Vector3.ZERO) -> void:
	var k := _key(pos.x, pos.z)
	if not cells.has(k):
		cells[k] = PackedFloat32Array()
	var tid := _text_id(text) if text != "" else 0
	var arr: PackedFloat32Array = cells[k]
	arr.append_array(PackedFloat32Array([float(kind), pos.x, pos.y, pos.z, yaw, _rng.randf(), float(variant), float(tid)]))
	cells[k] = arr
	var sk := _skey(pos.x, pos.z)
	if not _space.has(sk):
		_space[sk] = []
	(_space[sk] as Array).append(Vector3(pos.x, pos.z, KIND_R[kind] if kind in GROUND else 0.3))
	placements.append({"kind": kind, "pos": pos, "yaw": yaw, "text": text, "door": door, "n": n, "variant": variant})
	kind_count[kind] += 1


## Can a ground prop of radius r stand at (x, z) on a city sidewalk?
func _kerb_ok(layout: CityLayout, x: float, z: float, r: float) -> bool:
	if absf(x) > CityLayout.HALF or absf(z) > CityLayout.HALF:
		return false
	if CityLayout.on_road(x, z, 0.1 - r):
		return false
	if layout.lot_at(x, z, r + WALK_GAP) != null:
		return false
	if StreetClutter.blocks_lane(lanes, x, z, r):
		return false
	if ArmourSites.keeps_clear(x, z):
		return false
	var kit = _city.call(&"street_kit") if _city.has_method(&"street_kit") else null
	if kit != null and not kit._free(x, z, r):
		return false
	var gk := Vector2i(floori(x / 8.0), floori(z / 8.0))
	for ix in range(gk.x - 1, gk.x + 2):
		for iz in range(gk.y - 1, gk.y + 2):
			for o: Vector3 in _seat_grid.get(Vector2i(ix, iz), []):
				if Vector2(o.x - x, o.y - z).length() < r + o.z:
					return false
	return _space_free(x, z, r)


static func _grid_put(g: Dictionary, x: float, z: float, v: Variant) -> void:
	var k := Vector2i(floori(x / 8.0), floori(z / 8.0))
	if not g.has(k):
		g[k] = []
	(g[k] as Array).append(v)


func _kerb(layout: CityLayout) -> void:
	var n := CityLayout.N
	for i in n:
		for j in n:
			var bx := -CityLayout.HALF + (float(i) + 0.5) * CityLayout.PITCH
			var bz := -CityLayout.HALF + (float(j) + 0.5) * CityLayout.PITCH
			var dist := Districts.look_at(bx, bz)
			for face in 4:
				var nrm := Vector2(1, 0) if face == 0 else (Vector2(-1, 0) if face == 1 else (Vector2(0, 1) if face == 2 else Vector2(0, -1)))
				var tan_v := Vector2(-nrm.y, nrm.x)
				var yaw := atan2(nrm.x, nrm.y)
				var at := func(u: float, v: float) -> Vector3:
					var q := Vector2(bx, bz) + nrm * u + tan_v * v
					return Vector3(q.x, 0.0, q.y)
				var try := func(kind: int, u: float, v: float, yw: float, variant: int, text := "") -> bool:
					var p: Vector3 = at.call(u, v)
					if not _kerb_ok(layout, p.x, p.z, KIND_R[kind]):
						return false
					_add(kind, p, yw, variant, text)
					return true
				# street trees with grates: a row along the kerb
				if _rng.randf() < (0.55 if dist != Districts.FOUNDRY else 0.25):
					var v := -21.0 + _rng.randf_range(0.0, 3.0)
					while v < 21.0:
						try.call(TREE, 28.75, v, yaw + _rng.randf_range(-0.4, 0.4), _rng.randi() % 3)
						v += _rng.randf_range(9.0, 12.0)
				# parking meters beside the bays
				if _rng.randf() < 0.45:
					var v0 := _rng.randf_range(-18.0, 8.0)
					for m in _rng.randi_range(3, 5):
						try.call(METER, 29.55, v0 + float(m) * 6.4, yaw, _rng.randi() % 3)
				# newspaper boxes (a pair)
				if _rng.randf() < 0.5:
					var vn := _rng.randf_range(-20.0, 20.0)
					try.call(NEWS_BOX, 29.25, vn, yaw, _rng.randi() % 3)
					try.call(NEWS_BOX, 29.25, vn + 0.82, yaw, (_rng.randi() % 3))
				# a bike rack along the kerb
				if _rng.randf() < 0.35:
					try.call(BIKE_RACK, 28.95, _rng.randf_range(-20.0, 20.0), yaw + PI * 0.5, _rng.randi() % 3)
				# a traffic sign near one end of the face (faces the oncoming lane)
				if _rng.randf() < 0.6:
					var end := 1.0 if _rng.randf() < 0.5 else -1.0
					try.call(TRAFFIC_SIGN, 29.6, end * _rng.randf_range(19.0, 23.0), yaw + end * PI * 0.5, _rng.randi() % 3)
			# the street name sign at the north-east corner of the block (one per junction): the road along x (z = road j+1) and the road along z (x = road i+1)
			if i + 1 < n and j + 1 < n:
				var cx := bx + 29.3
				var cz := bz + 29.3
				var label := _street_name(0, j + 1) + "|" + _street_name(1, i + 1)
				for tries in 4:
					var px := cx - float(tries) * 0.6
					if _kerb_ok(layout, px, cz, KIND_R[NAME_SIGN]):
						_add(NAME_SIGN, Vector3(px, 0.0, cz), 0.0, 0, label)
						break


## Original street names: roads along x are STREETs, roads along z AVENUEs (two words of the list by road index).
static func _street_name(axis: int, road: int) -> String:
	var w := STREET_WORDS[posmod(road * (7 if axis == 0 else 11) + axis * 5, STREET_WORDS.size())]
	return w + (" ST" if axis == 0 else " AVE")


func _billboards(layout: CityLayout) -> void:
	var lots: Array = []
	for lot: CityLayout.Lot in layout.lots:
		if lot.h >= 10.0 and lot.h <= 30.0 and maxf(absf(lot.cx), absf(lot.cz)) < CityLayout.CORE_HALF + 160.0:
			lots.append(lot)
	var r2 := RandomNumberGenerator.new()
	r2.seed = 124206
	var made := 0
	var tries := 0
	while made < 18 and tries < 400 and not lots.is_empty():
		tries += 1
		var lot: CityLayout.Lot = lots[r2.randi() % lots.size()]
		var bx := -CityLayout.HALF + (lot.block_i + 0.5) * CityLayout.PITCH
		var bz := -CityLayout.HALF + (lot.block_j + 0.5) * CityLayout.PITCH
		var n := Vector3(signf(lot.cx - bx), 0.0, 0.0) if r2.randf() < 0.5 else Vector3(0.0, 0.0, signf(lot.cz - bz))
		var depth := lot.w if absf(n.x) > 0.5 else lot.d
		var pos := Vector3(lot.cx, lot.h, lot.cz) + n * (depth * 0.5 - 1.6)
		if not _space_free(pos.x, pos.z, 12.0):
			continue
		# w1242-critic: stand on the roof that is really there (stepped crowns: the front can be a lower step); all four feet on one level
		var bs := Basis(Vector3.UP, atan2(n.x, n.z))
		var lvl := -1.0
		var flat := true
		for lp: Vector3 in [Vector3(-2.2, 0, -0.2), Vector3(2.2, 0, -0.2), Vector3(-2.2, 0, -1.4), Vector3(2.2, 0, -1.4)]:
			var fw := pos + bs * lp
			var gh: float = _city.ground_height(fw.x, fw.z, lot.h + 1.0) if _city.has_method(&"ground_height") else lot.h
			if lvl < 0.0:
				lvl = gh
			elif absf(gh - lvl) > 0.2:
				flat = false
		if not flat or lvl < 8.0:
			continue
		pos.y = lvl
		_add(BILLBOARD, pos, atan2(n.x, n.z), made % 3, BRANDS[made % BRANDS.size()])
		made += 1


## Storefront depth at every city door (not the walk-in shops of the core: they show their own glass front and room).
func _storefronts(layout: CityLayout, doors: Array) -> void:
	for di in doors.size():
		var d: Dictionary = doors[di]
		var n: Vector3 = d["normal"]
		var w: Vector3 = d["wall"]
		w.y = 0.0
		var type: StringName = d["type"]
		var lot_i := int(d["id"])
		var walk_in := (ShopFronts.FROM_TYPE.has(type) or ShopFronts.OTHER_TYPES.has(type)) and maxf(absf(w.x), absf(w.z)) < CityLayout.CORE_HALF + 60.0
		if walk_in or d.has("pos0") or maxf(absf(w.x), absf(w.z)) > CityLayout.HALF + 20.0:
			continue                                                    # (the towns' house doors are in the list too: no shop front on a cottage)
		var t := Vector3(-n.z, 0.0, n.x)
		var yaw := atan2(n.x, n.z)
		var dw: float = d.get("width", 2.4)
		var h := _hash(lot_i, 3)
		var name_s := String(d.get("name", ""))
		var short := name_s.get_slice(" ", name_s.get_slice_count(" ") - 1) if name_s != "" else ""
		if short.length() > 9:
			short = short.substr(0, 9)
		_add(DOOR_FRAME, w, yaw, int(h * 3.0), "", di, n)
		var awned := h < 0.75
		if awned:
			_add(AWNING, w, yaw, int(_hash(lot_i, 5) * 3.0), "", di, n)
		if short != "":                                                 # w1242-critic: beside the awning, not through its cloth
			_add(SHOP_SIGN, w + t * (maxf(dw * 0.5 + 0.55, AWNING_HW + 0.25) if awned else dw * 0.5 + 0.55), yaw, int(_hash(lot_i, 7) * 3.0), short, di, n)
		# a window either side of the door: a lit display or a roller shutter (a closed shop)
		for side: float in [-1.0, 1.0]:
			var c := w + t * side * (dw * 0.5 + 1.75)
			var inside := c - n * 0.6
			if layout.lot_at(inside.x + t.x * 1.0, inside.z + t.z * 1.0) == null or layout.lot_at(inside.x - t.x * 1.0, inside.z - t.z * 1.0) == null:
				continue                                                # the wall does not run on that far: a corner or an alley
			if _near_other_door(doors, di, c, 3.4):
				continue
			if StreetClutter.blocks_lane(lanes, c.x + n.x * 0.25, c.z + n.z * 0.25, 0.9):
				continue
			var hk := _hash(lot_i, 11 + int(side + 1.0))
			_add(SHUTTER if hk < 0.3 else DISPLAY, c, yaw, int(hk * 9.0) % 3, "", di, n)


func _near_other_door(doors: Array, me: int, c: Vector3, r: float) -> bool:
	var gk := Vector2i(floori(c.x / 8.0), floori(c.z / 8.0))
	for ix in range(gk.x - 1, gk.x + 2):
		for iz in range(gk.y - 1, gk.y + 2):
			for k: int in _door_grid.get(Vector2i(ix, iz), []):
				if k == me:
					continue
				var wp: Vector3 = (doors[k] as Dictionary)["wall"]
				if absf(wp.x - c.x) < r and absf(wp.z - c.z) < r:
					return true
	return false


static func _hash(a: int, b: int) -> float:
	var hv := int(a) * 73856093 ^ int(b) * 19349663
	return float(posmod(hv, 100003)) / 100003.0


## The towns' main streets: bins, crates, mailboxes and cones on the sidewalk strip (town frame -> world by the town pad), out of every house door's lane.
func _outskirts() -> void:
	var tdoors := SettlementData.doors()
	var tl := StreetClutter.grid_for(tdoors)
	for s: Dictionary in SettlementData.towns():
		var plan := SettlementData.plan_of(s)
		if plan == null or plan.street.size() < 2:
			continue
		var sp: Vector3 = s["pos"]
		var xf := Transform3D(Basis(Vector3.UP, float(s["yaw"])), Vector3(sp.x, float(s["pad_y"]), sp.z))
		var total := 0.0
		for i in plan.street.size() - 1:
			var a := plan.street[i]
			var b := plan.street[i + 1]
			var seg := a.distance_to(b)
			var tg := (b - a) / maxf(seg, 0.001)
			var nr := Vector2(-tg.y, tg.x)
			var u := fmod(total, 17.0)
			while u < seg:
				for side: float in [-1.0, 1.0]:
					if _rng.randf() < 0.45:
						continue
					var q := a + tg * (u + _rng.randf_range(-2.0, 2.0)) + nr * side * (SettlementPlan.STREET_HALF - 1.0)
					var yaw_l := atan2(-nr.x * side, -nr.y * side)
					if not plan.fits(q.x, q.y, 0.55, 0.55, yaw_l, 0.4, -2.6):
						continue
					var wp := xf * Vector3(q.x, 0.0, q.y)
					if StreetClutter.blocks_lane(tl, wp.x, wp.z, 0.8) or not _space_free(wp.x, wp.z, 0.8):
						continue
					var near_prop := false
					for pr: Dictionary in plan.props:
						if absf(float(pr["x"]) - q.x) < 2.2 and absf(float(pr["z"]) - q.y) < 2.2:
							near_prop = true
							break
					if near_prop:
						continue
					_add(CLUTTER, wp, yaw_l + float(s["yaw"]), _rng.randi() % 4)
				u += 17.0
			total += seg


# --- the window --------------------------------------------------------------------------------------------------------------------

func update(cam: Vector2, force := false) -> void:
	if not built:
		return
	if not force and cam.distance_to(_built_at) < STEP:
		return
	_built_at = cam
	var rn := near_radius()
	var rf := FAR_BILLBOARD * q_scale
	var sel_near: Array[int] = []
	var sel_far: Array[int] = []
	var s := 7
	var k0 := _key(cam.x - rf, cam.y - rf)
	var k1 := _key(cam.x + rf, cam.y + rf)
	for kx in range(k0 / 1024, k1 / 1024 + 1):
		for kz in range(k0 % 1024, k1 % 1024 + 1):
			var k := kx * 1024 + kz
			if not cells.has(k):
				continue
			var x0 := float(kx - 512) * CELL
			var z0 := float(kz - 512) * CELL
			var dx := maxf(maxf(x0 - cam.x, cam.x - (x0 + CELL)), 0.0)
			var dz := maxf(maxf(z0 - cam.y, cam.y - (z0 + CELL)), 0.0)
			var dd := sqrt(dx * dx + dz * dz)
			if dd <= rn:
				sel_near.append(k)
				s = s * 1000003 + k * 2 + 1
			elif dd <= rf:
				sel_far.append(k)
				s = s * 1000003 + k * 2
	if s == _sig and not force:
		return
	_sig = s
	_fill(sel_near, sel_far)


## Every placement at full detail (tests).
func show_all() -> void:
	var all: Array[int] = []
	for k: int in cells.keys():
		all.append(k)
	_sig = -1
	_fill(all, [])


func _fill(sel_near: Array[int], sel_far: Array[int]) -> void:
	rebuilds += 1
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var sd := PackedFloat32Array()
	near_props = 0
	for level in 2:
		var list := sel_near if level == 0 else sel_far
		for k in list:
			var arr: PackedFloat32Array = cells[k]
			for o in range(0, arr.size(), 8):
				var kind := int(arr[o])
				if level == 1 and kind != BILLBOARD:
					continue
				var g := _geo_of(kind, int(arr[o + 6]), int(arr[o + 7]), Districts.look_at(arr[o + 1], arr[o + 3]), level == 0)
				if g.is_empty():
					continue
				var xf := Transform3D(Basis(Vector3.UP, arr[o + 4]), Vector3(arr[o + 1], arr[o + 2], arr[o + 3]))
				v.append_array(xf * (g["v"] as PackedVector3Array))
				nr.append_array(Transform3D(xf.basis, Vector3.ZERO) * (g["n"] as PackedVector3Array))
				uv.append_array(g["uv"])
				uv2.append_array(g["uv2"])
				col.append_array(g["c"])
				var seeds := PackedFloat32Array()
				seeds.resize(int(g["count"]))
				seeds.fill(arr[o + 5])
				sd.append_array(seeds)
				if level == 0:
					near_props += 1
	_fill_solids(sel_near)
	mesh.clear_surfaces()
	triangles = v.size() / 3
	if v.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nr
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_CUSTOM0] = sd
	var flags := Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_R_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)


## w1242-critic: the hero walked through street tree trunks, news boxes and the towns' bins. The near window's solid props as shapes of one static body.
func _solid_shape(kind: int, variant: int) -> Array:
	var key := kind * 4 + variant % 4
	if _shapes.has(key):
		return _shapes[key]
	var e: Array = []
	match kind:
		TREE:
			var c := PhysicsServer3D.cylinder_shape_create()
			PhysicsServer3D.shape_set_data(c, {"radius": 0.16, "height": 2.6})
			e = [c, Transform3D(Basis(), Vector3(0, 1.3, 0))]
		NEWS_BOX:
			var b := PhysicsServer3D.box_shape_create()
			PhysicsServer3D.shape_set_data(b, Vector3(0.28, 0.5, 0.23))
			e = [b, Transform3D(Basis(), Vector3(0, 0.5, 0))]
		CLUTTER:
			var b2 := PhysicsServer3D.box_shape_create()
			var he := Vector3(0.12, 0.65, 0.25) if variant % 4 == 2 else (Vector3(0.7, 0.5, 0.4) if variant % 4 == 0 else Vector3(0.6, 0.5, 0.5))
			PhysicsServer3D.shape_set_data(b2, he)
			e = [b2, Transform3D(Basis(), Vector3(0, he.y, 0))]
	_shapes[key] = e
	return e


func _fill_solids(sel_near: Array[int]) -> void:
	solids = 0
	if not solid_on or not is_inside_tree():
		return
	if not _body.is_valid():
		_body = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(_body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_collision_layer(_body, Game.L_WORLD)
		PhysicsServer3D.body_set_collision_mask(_body, 0)
		PhysicsServer3D.body_set_space(_body, get_world_3d().space)
	PhysicsServer3D.body_clear_shapes(_body)
	for k in sel_near:
		var arr: PackedFloat32Array = cells[k]
		for o in range(0, arr.size(), 8):
			var kind := int(arr[o])
			if kind != TREE and kind != NEWS_BOX and kind != CLUTTER:
				continue
			var e := _solid_shape(kind, int(arr[o + 6]))
			if e.is_empty():
				continue
			var xf := Transform3D(Basis(Vector3.UP, arr[o + 4]), Vector3(arr[o + 1], arr[o + 2], arr[o + 3])) * (e[1] as Transform3D)
			PhysicsServer3D.body_add_shape(_body, e[0], xf)
			solids += 1


func _geo_of(kind: int, variant: int, tid: int, d: int, near: bool) -> Dictionary:
	var key := (((kind * 4 + variant) * 4 + d) * 2 + (1 if near else 0)) * 4096 + tid
	if not _geo.has(key):
		_geo[key] = make_geo(kind, variant, texts[tid] if tid < texts.size() else "", d, near)
	return _geo[key]


# --- geometry (local: +Z = the front, towards the street; y = 0 the ground or the roof) ----------------------------------------------

static func make_geo(kind: int, variant: int, text: String, d: int, near := true) -> Dictionary:
	var p := Kit._pal(d, variant)
	var b := MB.new()
	b.uv2 = Vector2(0.5, 0.6)
	match kind:
		NEWS_BOX:
			_news_box(b, p, variant)
		BIKE_RACK:
			_bike_rack(b, p)
		METER:
			_meter(b, p)
		TREE:
			_tree(b, p, variant)
		TRAFFIC_SIGN:
			_traffic_sign(b, p, variant)
		NAME_SIGN:
			_name_sign(b, p, text)
		BILLBOARD:
			_billboard(b, p, text, variant, near)
		SHOP_SIGN:
			_shop_sign(b, p, text, variant)
		AWNING:
			_awning(b, p, variant)
		DOOR_FRAME:
			_door_frame(b, p, variant)
		DISPLAY:
			_display(b, p, variant)
		SHUTTER:
			_shutter(b, p, variant)
		CLUTTER:
			_clutter(b, p, variant)
	return Kit._flat(b)


static func _glow(c: Color, k := 1.0) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 1.0)


static func _news_box(b: MB, p: Kit.Pal, variant: int) -> void:
	var body: Color = [Color(0.16, 0.05, 0.04), Color(0.03, 0.07, 0.15), Color(0.13, 0.11, 0.02)][variant % 3]
	b.uv2 = Vector2(0.5, 0.45)
	b.box(Vector3(0, 0.62, 0), Vector3(0.52, 0.62, 0.42), p.t(body), false)
	b.box(Vector3(0, 0.96, -0.02), Vector3(0.56, 0.06, 0.46), p.t(body * 0.7))
	b.box(Vector3(0, 0.155, 0), Vector3(0.08, 0.31, 0.08), p.t(Color(0.05, 0.05, 0.05)), false)
	b.box(Vector3(0, 0.02, 0), Vector3(0.4, 0.04, 0.34), p.t(Color(0.05, 0.05, 0.05)), false)
	b.uv2 = Vector2(0.0, 0.2)
	b.quad(Vector3(-0.2, 0.62, 0.215), Vector3(0.2, 0.62, 0.215), Vector3(0.2, 0.86, 0.215), Vector3(-0.2, 0.86, 0.215), Vector3.BACK, Color(0.55, 0.55, 0.5, 0.0))
	b.quad(Vector3(-0.18, 0.66, 0.218), Vector3(0.18, 0.66, 0.218), Vector3(0.18, 0.7, 0.218), Vector3(-0.18, 0.7, 0.218), Vector3.BACK, Color(0.05, 0.05, 0.05, 0.0))
	b.quad(Vector3(-0.18, 0.74, 0.218), Vector3(0.1, 0.74, 0.218), Vector3(0.1, 0.8, 0.218), Vector3(-0.18, 0.8, 0.218), Vector3.BACK, Color(0.08, 0.08, 0.08, 0.0))


static func _bike_rack(b: MB, p: Kit.Pal) -> void:
	var steel := p.t(Color(0.1, 0.11, 0.12))
	b.uv2 = Vector2(0.85, 0.35)
	for k in 4:
		var x := -0.9 + float(k) * 0.6
		b.strut(Vector3(x, 0.0, -0.3), Vector3(x, 0.72, -0.3), 0.045, steel, false)
		b.strut(Vector3(x, 0.0, 0.3), Vector3(x, 0.72, 0.3), 0.045, steel, false)
		b.strut(Vector3(x, 0.72, -0.3), Vector3(x, 0.8, 0.0), 0.045, steel, false)
		b.strut(Vector3(x, 0.8, 0.0), Vector3(x, 0.72, 0.3), 0.045, steel, false)
	b.box(Vector3(0, 0.02, 0), Vector3(2.1, 0.04, 0.1), steel, false)


static func _meter(b: MB, p: Kit.Pal) -> void:
	var grey := p.t(Color(0.09, 0.095, 0.1))
	b.uv2 = Vector2(0.8, 0.4)
	b.box(Vector3(0, 0.55, 0), Vector3(0.07, 1.1, 0.07), grey, false)
	b.box(Vector3(0, 1.25, 0), Vector3(0.2, 0.3, 0.16), p.t(Color(0.04, 0.08, 0.06)))
	b.uv2 = Vector2(0.0, 0.25)
	b.quad(Vector3(-0.07, 1.22, 0.082), Vector3(0.07, 1.22, 0.082), Vector3(0.07, 1.33, 0.082), Vector3(-0.07, 1.33, 0.082), Vector3.BACK, _glow(p.accent, 0.35))


static func _tree(b: MB, p: Kit.Pal, variant: int) -> void:
	var iron := p.t(Color(0.05, 0.05, 0.05))
	b.uv2 = Vector2(0.6, 0.6)
	# the grate: a dark square flush with the paving, a frame and two bars (top faces only: it is flat)
	b.quad(Vector3(-0.6, 0.012, -0.6), Vector3(0.6, 0.012, -0.6), Vector3(0.6, 0.012, 0.6), Vector3(-0.6, 0.012, 0.6), Vector3.UP, Color(0.025, 0.02, 0.015, 0.0))
	for q: Array in [[Vector3(0, 0.02, -0.55), Vector3(1.2, 0.03, 0.1)], [Vector3(0, 0.02, 0.55), Vector3(1.2, 0.03, 0.1)], [Vector3(-0.55, 0.02, 0), Vector3(0.1, 0.03, 1.0)],
			[Vector3(0.55, 0.02, 0), Vector3(0.1, 0.03, 1.0)], [Vector3(-0.25, 0.02, 0), Vector3(0.05, 0.03, 1.0)], [Vector3(0.25, 0.02, 0), Vector3(0.05, 0.03, 1.0)]]:
		b.box(q[0], q[1], iron, false, b.uv2, MB.F_PX | MB.F_NX | MB.F_PZ | MB.F_NZ)
	# trunk, a low-poly crown (tall enough to walk under) and a light guard
	var bark := Color(0.09, 0.06, 0.04, 0.0)
	b.uv2 = Vector2(0.0, 0.9)
	var lift := 0.0 if not solid_on else CROWN_LIFT                 # w1242-critic: the crown's underside was 2.25 m up, in the follow camera's path (a green wall on screen)
	b.cylinder(Vector3(0, 0, 0), 0.11, 2.7 + lift, 5, bark, 0.08)
	var leaf: Color = [Color(0.06, 0.16, 0.05), Color(0.09, 0.15, 0.04), Color(0.05, 0.12, 0.08)][variant % 3]
	var hgt := 3.4 + lift + 0.3 * float(variant)
	b.sphere(Vector3(0, hgt, 0), Vector3(1.45, 1.15, 1.45), 6, 3, Color(leaf.r, leaf.g, leaf.b, 0.0))
	b.sphere(Vector3(0.45, hgt + 0.65, 0.2), Vector3(0.9, 0.75, 0.9), 5, 3, Color(leaf.r * 1.25, leaf.g * 1.25, leaf.b * 1.25, 0.0))
	b.uv2 = Vector2(0.85, 0.4)
	for q2: Vector2 in [Vector2(-0.22, -0.22), Vector2(0.22, 0.22)]:
		b.box(Vector3(q2.x, 0.55, q2.y), Vector3(0.035, 1.1, 0.035), iron, false, b.uv2, MB.F_TOP)


static func _traffic_sign(b: MB, p: Kit.Pal, variant: int) -> void:
	var grey := p.t(Color(0.1, 0.1, 0.11))
	b.uv2 = Vector2(0.8, 0.4)
	b.box(Vector3(0, 1.2, 0), Vector3(0.07, 2.4, 0.07), grey, false)
	b.uv2 = Vector2(0.1, 0.4)
	var z := 0.05
	var back := Color(0.12, 0.12, 0.12, 0.0)
	match variant % 3:
		0:                                                              # STOP: a red octagon with the word
			var pts := PackedVector3Array()
			for k in 8:
				var a := PI / 8.0 + float(k) * PI / 4.0
				pts.append(Vector3(cos(a) * 0.38, 2.55 + sin(a) * 0.38, z))
			for k in 8:
				b.quad(Vector3(0, 2.55, z), pts[k], pts[(k + 1) % 8], Vector3(0, 2.55, z), Vector3.BACK, Color(0.55, 0.03, 0.02, 0.0))
				b.quad(Vector3(0, 2.55, z - 0.02), pts[(k + 1) % 8] - Vector3(0, 0, 0.02), pts[k] - Vector3(0, 0, 0.02), Vector3(0, 2.55, z - 0.02), Vector3.FORWARD, back)
			_text(b, "STOP", Vector3(0, 2.55, z + 0.005), Vector3.RIGHT, 0.13, Color(0.9, 0.9, 0.9, 0.0))
		1:                                                              # NO ENTRY: a red disc with a white bar
			b.cylinder(Vector3(0, 2.55, z - 0.02), 0.34, 0.03, 10, Color(0.55, 0.03, 0.02, 0.0))
			b.quad(Vector3(-0.24, 2.5, z + 0.012), Vector3(0.24, 2.5, z + 0.012), Vector3(0.24, 2.6, z + 0.012), Vector3(-0.24, 2.6, z + 0.012), Vector3.BACK, Color(0.85, 0.85, 0.85, 0.0))
		_:                                                              # speed limit 30: a white panel with a red ring
			b.box(Vector3(0, 2.55, z - 0.01), Vector3(0.5, 0.62, 0.02), Color(0.75, 0.75, 0.72, 0.0))
			_text(b, "30", Vector3(0, 2.52, z + 0.002), Vector3.RIGHT, 0.24, Color(0.04, 0.04, 0.04, 0.0))
			_text(b, "LIMIT", Vector3(0, 2.76, z + 0.002), Vector3.RIGHT, 0.07, Color(0.04, 0.04, 0.04, 0.0))
	# rotate the plate face-on to traffic: the post stands by the kerb, the plate faces along the road (yaw from the caller)


static func _name_sign(b: MB, p: Kit.Pal, text: String) -> void:
	var grey := Color(0.03, 0.032, 0.035, 0.0)                   # dark steel, not tinted (the district gain read it white)
	b.uv2 = Vector2(0.8, 0.4)
	b.box(Vector3(0, 1.45, 0), Vector3(0.08, 2.9, 0.08), grey, false)
	b.box(Vector3(0, 2.95, 0), Vector3(0.12, 0.1, 0.12), grey)
	var parts := text.split("|")
	var green := Color(0.02, 0.16, 0.08, 0.0)
	b.uv2 = Vector2(0.2, 0.4)
	for k in mini(parts.size(), 2):
		var nm := parts[k]
		var y := 2.62 + float(k) * 0.36
		var len_m := maxf(1.0, 0.137 * float(nm.length()) + 0.3)
		if k == 0:                                                       # blade along x: read from the road along x (the faces look at +z / -z)
			b.box(Vector3(-len_m * 0.5 + 0.05, y, 0), Vector3(len_m, 0.28, 0.03), green)
			_text(b, nm, Vector3(-len_m * 0.5 + 0.05, y, 0.017), Vector3.RIGHT, 0.16, Color(0.95, 0.97, 0.95, 0.0))
			_text(b, nm, Vector3(-len_m * 0.5 + 0.05, y, -0.017), Vector3.LEFT, 0.16, Color(0.95, 0.97, 0.95, 0.0))
		else:                                                            # blade along z
			b.box(Vector3(0, y, -len_m * 0.5 + 0.05), Vector3(0.03, 0.28, len_m), green)
			_text(b, nm, Vector3(0.017, y, -len_m * 0.5 + 0.05), Vector3.FORWARD, 0.16, Color(0.95, 0.97, 0.95, 0.0))
			_text(b, nm, Vector3(-0.017, y, -len_m * 0.5 + 0.05), Vector3.BACK, 0.16, Color(0.95, 0.97, 0.95, 0.0))


static func _billboard(b: MB, p: Kit.Pal, text: String, variant: int, near: bool) -> void:
	var iron := p.t(Color(0.06, 0.065, 0.07))
	b.uv2 = Vector2(0.7, 0.5)
	for x in [-2.2, 2.2]:
		b.box(Vector3(x, 1.3, -0.2), Vector3(0.2, 2.6, 0.2), iron, false)
		if near:
			b.strut(Vector3(x, 0.0, -1.4), Vector3(x, 2.6, -0.2), 0.1, iron, false)
	var ground: Color = [Color(0.05, 0.02, 0.12), Color(0.12, 0.02, 0.05), Color(0.01, 0.08, 0.1)][variant % 3]
	b.box(Vector3(0, 3.6, -0.1), Vector3(6.0, 2.2, 0.2), Color(0.03, 0.03, 0.035, 0.0), false)
	b.uv2 = Vector2(0.0, 0.3)
	b.quad(Vector3(-2.85, 2.62, 0.005), Vector3(2.85, 2.62, 0.005), Vector3(2.85, 4.58, 0.005), Vector3(-2.85, 4.58, 0.005), Vector3.BACK, _glow(ground, 0.8))
	_text(b, text, Vector3(0, 3.75, 0.02), Vector3.RIGHT, minf(0.75, 5.2 / maxf(1.0, float(text.length()) * 6.0 / 7.0) ), _glow(p.accent2.lerp(Color.WHITE, 0.5), 1.0))
	b.quad(Vector3(-2.4, 2.9, 0.012), Vector3(2.4, 2.9, 0.012), Vector3(2.4, 3.0, 0.012), Vector3(-2.4, 3.0, 0.012), Vector3.BACK, _glow(p.accent, 0.9))
	if near:
		b.box(Vector3(0, 2.5, 0.25), Vector3(5.6, 0.06, 0.5), iron)                     # the catwalk


static func _shop_sign(b: MB, p: Kit.Pal, text: String, variant: int) -> void:
	# a blade sticking out of the wall beside the door, at 2.85 .. 3.55 m: under the facade's own sign band (3.9 m) and over every head
	var iron := p.t(Color(0.05, 0.05, 0.055))
	b.uv2 = Vector2(0.8, 0.4)
	b.box(Vector3(0, 3.62, 0.55), Vector3(0.05, 0.05, 1.1), iron)
	b.box(Vector3(0, 3.2, 0.06), Vector3(0.12, 0.85, 0.12), iron, false)
	var face: Color = [Color(0.02, 0.02, 0.03), Color(0.1, 0.03, 0.02), Color(0.02, 0.05, 0.08)][variant % 3]
	b.uv2 = Vector2(0.1, 0.4)
	b.box(Vector3(0, 3.2, 0.62), Vector3(0.08, 0.66, 0.96), face)
	var px := minf(0.11, 0.86 / maxf(1.0, float(text.length()) * 6.0 / 7.0))
	_text(b, text, Vector3(0.042, 3.2, 0.62), Vector3.FORWARD, px, _glow(p.accent, 1.0))
	_text(b, text, Vector3(-0.042, 3.2, 0.62), Vector3.BACK, px, _glow(p.accent, 1.0))


static func _awning(b: MB, p: Kit.Pal, variant: int) -> void:
	var cloth := p.cloth()
	var dark := Color(cloth.r * 0.6, cloth.g * 0.6, cloth.b * 0.6, 0.0)
	b.uv2 = Vector2(0.0, 0.85)
	var hw := AWNING_HW
	var stripes := 6
	for k in stripes:
		var x0 := -hw + 2.0 * hw * float(k) / float(stripes)
		var x1 := -hw + 2.0 * hw * float(k + 1) / float(stripes)
		var c := cloth if (k + variant) % 2 == 0 else Color(0.5, 0.5, 0.48, 0.0)
		b.quad(Vector3(x0, 3.45, 0.02), Vector3(x1, 3.45, 0.02), Vector3(x1, 2.95, 1.35), Vector3(x0, 2.95, 1.35), Vector3(0, 0.94, 0.35).normalized(), c)
		b.quad(Vector3(x0, 3.45, 0.02), Vector3(x0, 2.95, 1.35), Vector3(x1, 2.95, 1.35), Vector3(x1, 3.45, 0.02), Vector3(0, -0.94, -0.35).normalized(), dark)
	b.box(Vector3(0, 2.83, 1.35), Vector3(2.0 * hw, 0.24, 0.03), cloth)                    # valance
	b.uv2 = Vector2(0.8, 0.4)
	b.box(Vector3(0, 3.46, 0.06), Vector3(2.0 * hw + 0.1, 0.08, 0.12), p.t(Color(0.05, 0.05, 0.05)))


static func _door_frame(b: MB, p: Kit.Pal, variant: int) -> void:
	# jambs and lintel standing 0.35 m proud of the wall round a 2.4 m door, a dark reveal, a step: the door reads set back into the wall
	var stone: Color = [Color(0.16, 0.15, 0.14), Color(0.07, 0.07, 0.08), Color(0.17, 0.11, 0.08)][variant % 3]
	var c := p.t(stone * 0.33)
	b.uv2 = Vector2(0.1, 0.8)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 1.38, 1.45, 0.17), Vector3(0.36, 2.9, 0.34), c, false)
		b.quad(Vector3(sx * 1.2, 0.0, 0.34), Vector3(sx * 1.2, 2.75, 0.34), Vector3(sx * 1.2, 2.75, 0.0), Vector3(sx * 1.2, 0.0, 0.0), Vector3(-sx, 0, 0), Color(0.012, 0.012, 0.014, 0.0))
	b.box(Vector3(0, 2.92, 0.19), Vector3(3.12, 0.36, 0.38), c)
	b.quad(Vector3(-1.2, 2.74, 0.34), Vector3(1.2, 2.74, 0.34), Vector3(1.2, 2.74, 0.0), Vector3(-1.2, 2.74, 0.0), Vector3.DOWN, Color(0.012, 0.012, 0.014, 0.0))
	b.box(Vector3(0, 0.04, 0.3), Vector3(3.0, 0.08, 0.6), p.t(Color(0.05, 0.05, 0.05)))
	b.uv2 = Vector2(0.0, 0.3)
	b.box(Vector3(0, 3.02, 0.39), Vector3(2.2, 0.05, 0.02), _glow(p.accent, 0.6), false)    # the lit lintel line


static func _display(b: MB, p: Kit.Pal, variant: int) -> void:
	# a bay window box: frame, sill, a lit back with goods on two shelves; the front is open (a glass sheen strip at the top and bottom)
	var frame := p.t(Color(0.04, 0.04, 0.045))
	b.uv2 = Vector2(0.7, 0.4)
	b.box(Vector3(0, 0.3, 0.24), Vector3(1.8, 0.6, 0.48), p.t(Color(0.07, 0.065, 0.06)), false)    # stall riser
	b.box(Vector3(0, 0.62, 0.26), Vector3(1.9, 0.05, 0.52), frame)
	b.box(Vector3(0, 2.4, 0.24), Vector3(1.9, 0.1, 0.48), frame)
	for sx in [-0.93, 0.93]:
		b.box(Vector3(sx, 1.5, 0.46), Vector3(0.05, 1.8, 0.04), frame, false)
	b.box(Vector3(0, 1.5, 0.46), Vector3(0.03, 1.8, 0.03), frame, false)
	b.uv2 = Vector2(0.0, 0.35)
	var lit: Color = [Color(1.0, 0.8, 0.55), Color(0.75, 0.9, 1.0), Color(1.0, 0.7, 0.85)][variant % 3]
	b.quad(Vector3(-0.9, 0.65, 0.02), Vector3(0.9, 0.65, 0.02), Vector3(0.9, 2.35, 0.02), Vector3(-0.9, 2.35, 0.02), Vector3.BACK, _glow(lit, 0.22))
	b.uv2 = Vector2(0.2, 0.6)
	b.box(Vector3(0, 1.45, 0.2), Vector3(1.7, 0.03, 0.3), frame, false)
	var goods: Array[Color] = [p.accent, p.accent2, Color(0.8, 0.75, 0.6), Color(0.3, 0.5, 0.8)]
	for k in 5:
		var x := -0.68 + float(k) * 0.34
		var gh := 0.22 + 0.12 * float((k + variant) % 3)
		var gc: Color = goods[(k + variant) % goods.size()]
		b.box(Vector3(x, 0.66 + gh * 0.5, 0.22), Vector3(0.22, gh, 0.22), Color(gc.r * 0.35, gc.g * 0.35, gc.b * 0.35, 0.0), false)
		var gh2 := 0.18 + 0.1 * float((k + variant + 1) % 3)
		b.box(Vector3(x, 1.47 + gh2 * 0.5, 0.22), Vector3(0.2, gh2, 0.18), Color(gc.r * 0.3, gc.g * 0.3, gc.b * 0.3, 0.0), false)
	if variant % 3 == 1:                                                 # a mannequin
		b.box(Vector3(0.45, 1.55, 0.25), Vector3(0.3, 0.6, 0.16), Color(0.25, 0.22, 0.2, 0.0), false)
		b.sphere(Vector3(0.45, 2.0, 0.25), Vector3(0.1, 0.12, 0.1), 6, 3, Color(0.3, 0.28, 0.26, 0.0))
	b.uv2 = Vector2(0.9, 0.05)
	b.quad(Vector3(-0.9, 2.1, 0.47), Vector3(0.9, 2.1, 0.47), Vector3(0.9, 2.33, 0.47), Vector3(-0.9, 2.33, 0.47), Vector3.BACK, Color(0.3, 0.38, 0.45, 0.0))


static func _shutter(b: MB, p: Kit.Pal, variant: int) -> void:
	var metal: Color = [Color(0.12, 0.12, 0.13), Color(0.1, 0.11, 0.1), Color(0.13, 0.11, 0.1)][variant % 3]
	b.uv2 = Vector2(0.8, 0.5)
	b.box(Vector3(0, 2.62, 0.16), Vector3(2.3, 0.34, 0.32), p.t(metal * 0.5))                     # the roll box
	for k in 12:
		var y0 := 0.05 + float(k) * 0.2
		var c := p.t(metal * (0.42 if k % 2 == 0 else 0.33))
		b.quad(Vector3(-1.08, y0, 0.07), Vector3(1.08, y0, 0.07), Vector3(1.08, y0 + 0.2, 0.07), Vector3(-1.08, y0 + 0.2, 0.07), Vector3.BACK, c)
	for sx in [-1.12, 1.12]:
		b.box(Vector3(sx, 1.25, 0.06), Vector3(0.08, 2.5, 0.12), p.t(metal * 0.3), false)
	b.box(Vector3(0, 0.05, 0.08), Vector3(2.16, 0.1, 0.06), p.t(Color(0.03, 0.03, 0.03)), false)
	if variant % 3 != 2:                                                 # a sprayed tag
		b.uv2 = Vector2(0.0, 0.7)
		_text(b, ["CLOSED", "TO LET"][variant % 3], Vector3(0, 1.3, 0.075), Vector3.RIGHT, 0.06, Color(0.5, 0.48, 0.44, 0.0))


static func _clutter(b: MB, p: Kit.Pal, variant: int) -> void:
	b.uv2 = Vector2(0.3, 0.7)
	match variant % 4:
		0:                                                              # two wheelie bins
			for x in [-0.36, 0.36]:
				var c := Color(0.04, 0.1, 0.05, 0.0) if x < 0.0 else Color(0.06, 0.06, 0.07, 0.0)
				b.box(Vector3(x, 0.5, 0), Vector3(0.6, 1.0, 0.7), p.t(c * 0.5 + Color(0, 0, 0, 0)), false)
				b.box(Vector3(x, 1.03, -0.02), Vector3(0.64, 0.06, 0.76), p.t(c * 0.4))
		1:                                                              # crates on a pallet
			b.box(Vector3(0, 0.07, 0), Vector3(1.2, 0.14, 1.0), Color(0.2, 0.14, 0.08, 0.0), false)
			b.box(Vector3(-0.25, 0.44, 0.05), Vector3(0.6, 0.6, 0.6), Color(0.26, 0.19, 0.1, 0.0), false)
			b.box(Vector3(0.32, 0.36, -0.1), Vector3(0.5, 0.44, 0.5), Color(0.22, 0.16, 0.09, 0.0), false)
			b.box(Vector3(0.0, 0.92, 0.0), Vector3(0.45, 0.36, 0.45), Color(0.24, 0.17, 0.1, 0.0), false)
		2:                                                              # a mailbox on a post
			b.box(Vector3(0, 0.55, 0), Vector3(0.08, 1.1, 0.08), Color(0.12, 0.09, 0.06, 0.0), false)
			b.box(Vector3(0, 1.2, 0.05), Vector3(0.28, 0.24, 0.5), p.t(Color(0.1, 0.02, 0.02)))
			b.box(Vector3(0.16, 1.32, -0.1), Vector3(0.03, 0.2, 0.06), p.t(Color(0.15, 0.12, 0.02)), false)
		_:                                                              # a barrel and two cones
			b.cylinder(Vector3(-0.3, 0, 0), 0.3, 0.9, 8, p.t(Color(0.08, 0.06, 0.03)))
			for x in [0.25, 0.6]:
				b.cylinder(Vector3(x, 0, 0.1), 0.15, 0.55, 6, Color(0.5, 0.12, 0.02, 0.0), 0.03)
				b.box(Vector3(x, 0.02, 0.1), Vector3(0.34, 0.04, 0.34), Color(0.05, 0.05, 0.05, 0.0), false)


## Block letters as quads (runs of lit pixels merged per row), centred on `centre`, along `right`, facing right x up (the front normal), letter height h (7 pixels).
static func _text(b: MB, s: String, centre: Vector3, right: Vector3, h: float, col: Color) -> void:
	var px := h / 7.0
	var up := Vector3.UP
	var nrm := right.cross(up).normalized()
	var total := float(s.length()) * 6.0 - 1.0
	var x0 := -total * 0.5
	for ci in s.length():
		var g: String = FONT.get(s[ci], "")
		if g.length() < 35:
			x0 += 6.0
			continue
		for row in 7:
			var c := 0
			while c < 5:
				if g[row * 5 + c] != "#":
					c += 1
					continue
				var e := c
				while e < 5 and g[row * 5 + e] == "#":
					e += 1
				var xa := (x0 + float(c)) * px
				var xb := (x0 + float(e)) * px
				var ya := (3.5 - float(row) - 1.0) * px
				var yb := (3.5 - float(row)) * px
				b.quad(centre + right * xa + up * ya, centre + right * xb + up * ya, centre + right * xb + up * yb, centre + right * xa + up * yb, nrm, col)
				c = e
		x0 += 6.0
