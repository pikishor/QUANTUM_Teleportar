extends RefCounted
## The street kit (wave 16 art library): 16 new street props, placed per district, drawn as ONE merged mesh around the camera.
##
## Why a merged window and not 16 MultiMeshes: every MultiMesh family that has an instance near the camera costs a draw call, and the frame has about 10 draws of headroom.
## The window (city_kit_window.gd) concatenates the geometry of the props in the cells around the camera into one ArrayMesh (one draw call for all 16 kinds, no triangles wasted on
## unused kinds) and re-fills it when the camera has moved 10 m. LOD is per cell inside that one mesh: cells near the camera get the full-detail geometry of every kind, cells further out
## get the simplified geometry of the big kinds only (vent stacks, bus pods, antennas, billboards, stalls: the silhouettes that read from afar), the small kinds simply stop. Per-district
## palette: every kind is built per district with the district's paint tint, glow accents and awning fabrics (the geometry cache is keyed by kind, level, district and variant).
##
## Mesh conventions are the prop shader's (assets/shaders/prop_core.gdshaderinc): COLOR.rgb = base colour (linear), COLOR.a = emission code, UV2 = (metallic, roughness), and for the
## merged window the per-prop seed rides as CUSTOM0.x (one float per vertex). Local +Z is the front of a prop (it faces the street). Props have no instance data and no own nodes.

const MB := preload("res://scripts/world/mesh_builder.gd")
const Districts := preload("res://scripts/world/city_districts.gd")
const KitWorld := preload("res://scripts/world/city_kit_world.gd")

const PAINT_GAIN := 3.0
const EM_BEACON := 0.30
const EM_FLASHER := 0.45
const EM_SCREEN := 0.60
const EM_POSTER := 0.80
const EM_GLOW := 1.0

const STANDPIPE := 0
const VENT_STACK := 1
const BIN := 2
const BENCH := 3
const VEND_KIOSK := 4
const SHELTER := 5
const SPOOL := 6
const ANTENNA := 7
const BILLBOARD := 8
const PLANTER := 9
const BARRIER := 10
const STALL := 11
const TRANSFORMER := 12
const CHARGE_POST := 13
const CRATES := 14
const LANTERN := 15
const KIND_COUNT := 16                ## the new props (random, per-district placement)
const HYDRANT := 16                   ## folded families: the existing hydrants, lit kiosks and vent grates now ride in the same merged mesh (three draw calls less)
const KIOSK_LIT := 17
const VENT_GRATE := 18
const FLORA_TREE := 19                ## creature kit flora (creature_kit.gd): trees, plants and rocks round the plazas, geometry from assets/models/kit_flora.glb
const FLORA_PLANT := 20
const FLORA_ROCK := 21
const KC_FIRST := 22                  ## the city-kit kinds (city_kit_world.gd, Quaternius CC0 pieces): facade bands, rooftop units, street furniture, road markings
const DRESS_FIRST := KC_FIRST + KitWorld.DRESS_FIRST  ## first of the district dressing kinds (city_kit_dress.gd)
const TOTAL_KINDS := KC_FIRST + KitWorld.COUNT

const MODE_KERB := 1
const MODE_ALLEY := 2

const SHAPE_BOX := 0
const SHAPE_CAPSULE := 1
const SHAPE_CYLINDER := 2

## Per kind: name, footprint half width / half depth (m, for spacing and the lot test), placement modes, far geometry radius (0 = no far level: the kind vanishes beyond the near
## radius), weights per district (market, foundry, slums, towers), pooled collider [shape, size, offset] (see city_colliders.gd; empty = none).
const KINDS: Array[Dictionary] = [
	{"name": "Standpipe", "hw": 0.3, "hd": 0.3, "mode": 3, "far": 0.0, "w": [1, 1, 2, 1], "col": [2, Vector3(0.2, 1.0, 0.0), Vector3(0.0, 0.5, 0.0)]},
	{"name": "VentStack", "hw": 0.6, "hd": 0.5, "mode": 3, "far": 120.0, "w": [0, 3, 2, 0], "col": [2, Vector3(0.34, 3.0, 0.0), Vector3(0.0, 1.5, 0.0)]},
	{"name": "Bin", "hw": 0.5, "hd": 0.4, "mode": 3, "far": 0.0, "w": [2, 1, 3, 2], "col": [0, Vector3(0.75, 1.0, 0.6), Vector3(0.0, 0.5, 0.0)]},
	{"name": "Bench", "hw": 0.95, "hd": 0.45, "mode": 1, "far": 0.0, "w": [3, 0, 1, 3], "col": [0, Vector3(1.7, 0.9, 0.6), Vector3(0.0, 0.45, 0.0)]},
	{"name": "VendKiosk", "hw": 0.65, "hd": 0.5, "mode": 1, "far": 0.0, "w": [2, 0, 1, 3], "col": [0, Vector3(1.1, 2.2, 0.8), Vector3(0.0, 1.1, 0.0)]},
	{"name": "Shelter", "hw": 1.6, "hd": 0.85, "mode": 1, "far": 130.0, "w": [1, 0, 1, 3], "col": [0, Vector3(3.0, 2.5, 0.5), Vector3(0.0, 1.25, -0.6)]},
	{"name": "Spool", "hw": 0.9, "hd": 0.5, "mode": 3, "far": 0.0, "w": [1, 3, 2, 0], "col": [0, Vector3(1.6, 1.6, 0.7), Vector3(0.0, 0.8, 0.0)]},
	{"name": "Antenna", "hw": 0.4, "hd": 0.4, "mode": 3, "far": 300.0, "w": [0, 2, 3, 2], "col": [1, Vector3(0.14, 8.8, 0.0), Vector3(0.0, 4.4, 0.0)]},
	{"name": "Billboard", "hw": 2.6, "hd": 0.4, "mode": 1, "far": 260.0, "w": [2, 0, 1, 3], "col": [0, Vector3(0.5, 4.0, 0.4), Vector3(0.0, 2.0, 0.0)]},
	{"name": "PlanterHex", "hw": 1.0, "hd": 1.0, "mode": 1, "far": 0.0, "w": [3, 0, 0, 3], "col": [2, Vector3(0.95, 0.6, 0.0), Vector3(0.0, 0.3, 0.0)]},
	{"name": "BarrierGate", "hw": 1.4, "hd": 0.35, "mode": 3, "far": 0.0, "w": [0, 3, 2, 1], "col": [0, Vector3(2.6, 0.9, 0.35), Vector3(0.0, 0.45, 0.0)]},
	{"name": "Stall", "hw": 1.5, "hd": 1.0, "mode": 3, "far": 120.0, "w": [4, 0, 2, 0], "col": [0, Vector3(2.6, 1.0, 0.9), Vector3(0.0, 0.5, 0.1)]},
	{"name": "Transformer", "hw": 0.85, "hd": 0.55, "mode": 3, "far": 0.0, "w": [0, 3, 2, 1], "col": [0, Vector3(1.5, 1.6, 0.9), Vector3(0.0, 0.8, 0.0)]},
	{"name": "ChargePost", "hw": 0.25, "hd": 0.25, "mode": 1, "far": 0.0, "w": [1, 0, 0, 3], "col": [2, Vector3(0.14, 1.1, 0.0), Vector3(0.0, 0.55, 0.0)]},
	{"name": "Crates", "hw": 1.0, "hd": 0.8, "mode": 3, "far": 0.0, "w": [2, 3, 2, 0], "col": [0, Vector3(1.9, 1.3, 0.9), Vector3(0.0, 0.65, 0.0)]},
	{"name": "LanternPole", "hw": 0.5, "hd": 0.4, "mode": 1, "far": 0.0, "w": [3, 0, 2, 0], "col": [1, Vector3(0.1, 3.6, 0.0), Vector3(0.0, 1.8, 0.0)]},
	{"name": "Hydrant", "hw": 0.45, "hd": 0.45, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "fam": "Hydrants", "col": [2, Vector3(0.22, 0.85, 0.0), Vector3(0.0, 0.42, 0.0)]},
	{"name": "KioskLit", "hw": 1.35, "hd": 1.0, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "fam": "Kiosks", "col": [0, Vector3(2.4, 2.6, 1.7), Vector3(0.0, 1.3, 0.0)]},
	{"name": "VentGrate", "hw": 0.75, "hd": 0.5, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "fam": "VentGrates", "col": []},
	{"name": "FloraTree", "hw": 0.7, "hd": 0.7, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "fam": "Flora", "col": []},
	{"name": "FloraPlant", "hw": 0.5, "hd": 0.5, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "fam": "Flora", "col": []},
	{"name": "FloraRock", "hw": 0.8, "hd": 0.8, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "fam": "Flora", "col": []},
	{"name": "KcCornice", "hw": 2.0, "hd": 0.2, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "KcPilaster", "hw": 0.2, "hd": 0.2, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "KcWindow", "hw": 1.0, "hd": 0.2, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "KcAcUnit", "hw": 0.45, "hd": 0.2, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "KcBollard", "hw": 0.12, "hd": 0.12, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": [2, Vector3(0.12, 0.9, 0.0), Vector3(0.0, 0.45, 0.0)]},
	{"name": "KcPlanter", "hw": 1.0, "hd": 1.0, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": [0, Vector3(2.0, 0.6, 2.0), Vector3(0.0, 0.3, 0.0)]},
	{"name": "KcDrain", "hw": 0.3, "hd": 0.3, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "KcManhole", "hw": 0.5, "hd": 0.5, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "KcArrow", "hw": 1.0, "hd": 1.2, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "KcCrosswalk", "hw": 2.3, "hd": 2.7, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "KcDashLine", "hw": 6.0, "hd": 0.1, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "KcDoubleLine", "hw": 6.0, "hd": 0.2, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "DrStoop", "hw": 1.0, "hd": 1.0, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "DrAwning", "hw": 2.5, "hd": 1.0, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "DrBalcony", "hw": 1.5, "hd": 0.6, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "DrShutter", "hw": 2.0, "hd": 0.2, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "DrColonnade", "hw": 2.4, "hd": 0.5, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "DrParapet", "hw": 2.0, "hd": 0.2, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "DrRooftop", "hw": 2.0, "hd": 2.0, "mode": 0, "far": 160.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "DrFireEscape", "hw": 1.0, "hd": 0.5, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "DrCluster", "hw": 1.2, "hd": 0.6, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": [0, Vector3(1.8, 1.0, 1.0), Vector3(0.0, 0.5, 0.0)]},
	{"name": "DrBladeSign", "hw": 0.1, "hd": 0.6, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
	{"name": "DrLedge", "hw": 2.0, "hd": 0.3, "mode": 0, "far": 0.0, "w": [0, 0, 0, 0], "col": []},
]

const CELL := 20.0
const GRID_ORIGIN := -CityLayout.HALF - 40.0
const GRID_N := int((2.0 * CityLayout.HALF + 80.0) / 20.0)

## Placements per cell: stride 6 floats (kind, x, z, yaw, seed, variant). cells[c] is a PackedFloat32Array.
var cells: Array = []
var counts := PackedInt32Array()
var placements: Array[Dictionary] = []               ## {kind, pos, yaw, district, variant, seed} for tests, colliders and landmarks' neighbours
var kind_count := PackedInt32Array()
var district_count := PackedInt32Array()
var glow_sprites := 0
var rng := RandomNumberGenerator.new()

var _geo := {}                                        ## (kind, level, district, variant) -> {v, n, uv, uv2, c, count}
var _grid := {}                                       ## spacing grid: key -> Array[Vector3(x, z, radius)]
var _folded: Array = []                               ## [kind, Array of [Transform3D, seed]] handed in by city_props.gd before build()
var _folded_geo := {}                                 ## kind -> flat geometry of the folded family's mesh


static func kind_name(k: int) -> String:
	return String(KINDS[k]["name"])


static func far_radius(k: int) -> float:
	return float(KINDS[k]["far"])


## Placements as pooled-collider sources: family name ("Kit" + kind name) -> Array[Transform3D]. The specs are returned by `collider_spec`.
func collider_sources() -> Dictionary:
	var out := {}
	for p in placements:
		var k: int = p["kind"]
		if (KINDS[k]["col"] as Array).is_empty():
			continue
		var fam := collider_family(k)
		if not out.has(fam):
			out[fam] = [] as Array[Transform3D]
		(out[fam] as Array).append(Transform3D(Basis(Vector3.UP, float(p["yaw"])), p["pos"]))
	return out


## Pooled-collider family name of a kind: "Kit" + name, or the old family name for the folded kinds (Hydrants, Kiosks).
static func collider_family(k: int) -> String:
	return String(KINDS[k].get("fam", "Kit" + kind_name(k)))


static func collider_spec(family_name: String) -> Array:
	for k in TOTAL_KINDS:
		if collider_family(k) == family_name:
			return KINDS[k]["col"]
	return []


# --- geometry --------------------------------------------------------------------------------------------------------------

class Pal extends RefCounted:
	var tint := Color.WHITE
	var accent := Color.WHITE
	var accent2 := Color.WHITE
	var fabric: Array = []
	var variant := 0

	## Painted colour of a part: the district tint times PAINT_GAIN (night street furniture must stay readable against the lit street, the shader's grime darkens it again).
	func t(c: Color) -> Color:
		return Color(c.r * tint.r * PAINT_GAIN, c.g * tint.g * PAINT_GAIN, c.b * tint.b * PAINT_GAIN, c.a)

	func glow(k := 0.7, second := false) -> Color:
		var a := accent2 if second else accent
		return Color(a.r * k, a.g * k, a.b * k, EM_GLOW)

	func cloth() -> Color:
		var f: Color = fabric[variant % fabric.size()]
		return Color(f.r, f.g, f.b, 0.0)


static func _pal(d: int, variant: int) -> Pal:
	var src := Districts.palette(d)
	var p := Pal.new()
	p.tint = src["tint"]
	p.accent = src["accent"]
	p.accent2 = src["accent2"]
	p.fabric = src["fabric"]
	p.variant = variant
	return p


static func _mb(metal: float, rough: float) -> MB:
	var b := MB.new()
	b.uv2 = Vector2(metal, rough)
	return b


static func _uvq() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])


## Non-indexed copy of a built mesh (the window concatenates arrays without having to rebase indices).
static func _flat(b: MB) -> Dictionary:
	var n := b.idx.size()
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c := PackedColorArray()
	v.resize(n)
	nr.resize(n)
	uv.resize(n)
	uv2.resize(n)
	c.resize(n)
	for i in n:
		var j := b.idx[i]
		v[i] = b.verts[j]
		nr[i] = b.norms[j]
		uv[i] = b.uvs[j]
		uv2[i] = b.uv2s[j]
		c[i] = b.cols[j]
	return {"v": v, "n": nr, "uv": uv, "uv2": uv2, "c": c, "count": n}


## Geometry of one kind: near (full detail) or far (simplified, only for kinds with a far radius). Returns {} when the kind has no far level.
static func make_geo(kind: int, near: bool, d: int, variant: int) -> Dictionary:
	if not near and far_radius(kind) <= 0.0:
		return {}
	var p := _pal(d, variant)
	var b := _mb(0.5, 0.6)
	match kind:
		STANDPIPE:
			_standpipe(b, p)
		VENT_STACK:
			_vent_stack(b, p, near)
		BIN:
			_bin(b, p)
		BENCH:
			_bench(b, p)
		VEND_KIOSK:
			_vend_kiosk(b, p)
		SHELTER:
			_shelter(b, p, near)
		SPOOL:
			_spool(b, p)
		ANTENNA:
			_antenna(b, p, near)
		BILLBOARD:
			_billboard(b, p, near)
		PLANTER:
			_planter(b, p)
		BARRIER:
			_barrier(b, p)
		STALL:
			_stall(b, p, near)
		TRANSFORMER:
			_transformer(b, p)
		CHARGE_POST:
			_charge_post(b, p)
		CRATES:
			_crates(b, p)
		LANTERN:
			_lantern(b, p)
	return _flat(b)


static func triangles(kind: int, near: bool) -> int:
	var g := make_geo(kind, near, 0, 0)
	return 0 if g.is_empty() else int(g["count"]) / 3


static func _standpipe(b: MB, p: Pal) -> void:
	var metal := p.t(Color(0.085, 0.095, 0.10, 0.0))
	b.uv2 = Vector2(0.8, 0.45)
	b.cylinder(Vector3(0, 0, 0), 0.24, 0.07, 6, metal, -1.0, false)
	b.cylinder(Vector3(0, 0.07, 0), 0.16, 0.72, 6, metal, 0.13, false)
	b.cylinder(Vector3(0, 0.79, 0), 0.16, 0.14, 6, metal, 0.08)
	b.box(Vector3(0, 0.96, 0), Vector3(0.2, 0.05, 0.2), p.t(Color(0.05, 0.055, 0.06, 0.0)), false)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.2, 0.42, 0.0), Vector3(0.16, 0.12, 0.12), metal, false)
	b.box(Vector3(0, 0.4, 0.2), Vector3(0.14, 0.14, 0.16), metal, false)
	b.uv2 = Vector2(0.0, 0.3)
	b.cylinder(Vector3(0, 0.56, 0), 0.172, 0.05, 6, p.glow(0.7), -1.0, false)


static func _vent_stack(b: MB, p: Pal, near: bool) -> void:
	var metal := p.t(Color(0.075, 0.08, 0.085, 0.0))
	b.uv2 = Vector2(0.7, 0.55)
	b.box(Vector3(0, 0.3, 0), Vector3(1.0, 0.6, 0.8), p.t(Color(0.10, 0.10, 0.105, 0.0)), false)
	if not near:
		b.cylinder(Vector3(0, 0.6, 0), 0.28, 2.6, 5, metal, 0.36)
		return
	b.cylinder(Vector3(0, 0.6, 0), 0.28, 2.3, 8, metal, 0.28, false)
	b.cylinder(Vector3(0, 2.9, 0), 0.28, 0.2, 8, metal, 0.42)
	for h in [1.2, 2.0]:
		b.cylinder(Vector3(0, h, 0), 0.31, 0.08, 8, p.t(Color(0.12, 0.12, 0.125, 0.0)), -1.0, false)
	b.strut(Vector3(-0.26, 1.5, 0), Vector3(-0.8, 1.2, 0.0), 0.12, metal, false)
	b.strut(Vector3(-0.8, 1.2, 0.0), Vector3(-0.8, 0.0, 0.0), 0.12, metal, false)
	b.uv2 = Vector2(0.0, 0.3)
	for y in [1.55, 1.75, 1.95, 2.15]:
		b.quad(Vector3(-0.15, y, 0.285), Vector3(0.15, y, 0.285), Vector3(0.15, y + 0.06, 0.285), Vector3(-0.15, y + 0.06, 0.285), Vector3.BACK, p.glow(0.8, true))


static func _bin(b: MB, p: Pal) -> void:
	var body := p.t(Color(0.07, 0.11, 0.10, 0.0))
	b.uv2 = Vector2(0.3, 0.6)
	b.box(Vector3(0, 0.5, 0), Vector3(0.7, 0.9, 0.52), body, false)
	b.box(Vector3(0, 0.96, -0.02), Vector3(0.76, 0.07, 0.58), p.t(Color(0.045, 0.05, 0.05, 0.0)))
	b.box(Vector3(0, 0.1, 0), Vector3(0.6, 0.12, 0.44), Color(0.02, 0.02, 0.02, 0.0), false)
	b.uv2 = Vector2(0.0, 0.3)
	b.quad(Vector3(-0.2, 0.62, 0.262), Vector3(0.2, 0.62, 0.262), Vector3(0.2, 0.7, 0.262), Vector3(-0.2, 0.7, 0.262), Vector3.BACK, p.glow(0.6))
	b.quad(Vector3(-0.1, 0.32, 0.262), Vector3(0.1, 0.32, 0.262), Vector3(0.1, 0.4, 0.262), Vector3(-0.1, 0.4, 0.262), Vector3.BACK, p.glow(0.35, true))


static func _bench(b: MB, p: Pal) -> void:
	var wood := p.t(Color(0.13, 0.10, 0.08, 0.0))
	var metal := p.t(Color(0.06, 0.065, 0.07, 0.0))
	b.uv2 = Vector2(0.0, 0.7)
	for z in [-0.05, 0.17]:
		b.box(Vector3(0, 0.45, z), Vector3(1.7, 0.05, 0.19), wood, false)
	for y in [0.74, 0.9]:
		b.box(Vector3(0, y, -0.2), Vector3(1.7, 0.12, 0.04), wood, false)
	b.uv2 = Vector2(0.75, 0.45)
	for sx in [-0.78, 0.78]:
		b.box(Vector3(sx, 0.22, 0.05), Vector3(0.05, 0.44, 0.5), metal, false)
		b.box(Vector3(sx, 0.7, -0.2), Vector3(0.05, 0.5, 0.05), metal, false)
		b.box(Vector3(sx, 0.62, 0.05), Vector3(0.05, 0.05, 0.45), metal, false)


static func _vend_kiosk(b: MB, p: Pal) -> void:
	b.uv2 = Vector2(0.5, 0.5)
	b.box(Vector3(0, 1.05, 0), Vector3(1.1, 2.1, 0.76), p.t(Color(0.07, 0.075, 0.085, 0.0)), false)
	b.box(Vector3(0, 2.14, 0), Vector3(1.2, 0.1, 0.86), p.t(Color(0.04, 0.04, 0.045, 0.0)))
	b.uv2 = Vector2(0.0, 0.3)
	b.quad(Vector3(-0.4, 1.0, 0.385), Vector3(0.4, 1.0, 0.385), Vector3(0.4, 1.95, 0.385), Vector3(-0.4, 1.95, 0.385), Vector3.BACK, Color(1, 1, 1, EM_SCREEN),
			Vector2.ZERO, Vector2.ZERO, _uvq())
	b.quad(Vector3(-0.45, 0.62, 0.385), Vector3(0.45, 0.62, 0.385), Vector3(0.45, 0.68, 0.385), Vector3(-0.45, 0.68, 0.385), Vector3.BACK, p.glow(0.7))
	b.uv2 = Vector2(0.5, 0.5)
	b.box(Vector3(0, 0.38, 0.42), Vector3(0.7, 0.34, 0.12), Color(0.02, 0.02, 0.025, 0.0))


static func _shelter(b: MB, p: Pal, near: bool) -> void:
	var metal := p.t(Color(0.09, 0.095, 0.10, 0.0))
	b.uv2 = Vector2(0.6, 0.5)
	b.box(Vector3(0, 2.55, 0), Vector3(3.2, 0.1, 1.7), p.t(Color(0.055, 0.06, 0.065, 0.0)))
	b.uv2 = Vector2(0.0, 0.08)
	b.box(Vector3(0, 1.3, -0.72), Vector3(3.0, 2.2, 0.04), Color(0.03, 0.05, 0.06, 0.0), false)
	if not near:
		return
	b.uv2 = Vector2(0.6, 0.5)
	for x in [-1.5, 1.5]:
		for z in [-0.72, 0.72]:
			b.box(Vector3(x, 1.25, z), Vector3(0.07, 2.5, 0.07), metal, false)
	b.box(Vector3(0, 2.63, 0), Vector3(3.2, 0.04, 1.7), p.t(Color(0.13, 0.135, 0.14, 0.0)))
	b.uv2 = Vector2(0.4, 0.7)
	b.box(Vector3(-0.2, 0.5, -0.45), Vector3(2.0, 0.05, 0.4), p.t(Color(0.12, 0.10, 0.08, 0.0)), false)
	for x in [-1.0, 0.6]:
		b.box(Vector3(x, 0.25, -0.45), Vector3(0.05, 0.5, 0.36), metal, false)
	b.uv2 = Vector2(0.0, 0.3)
	b.box(Vector3(0, 2.46, 0.72), Vector3(3.0, 0.05, 0.05), p.glow(0.75), false)
	b.box(Vector3(0, 2.46, -0.72), Vector3(3.0, 0.05, 0.05), p.glow(0.5, true), false)
	b.uv2 = Vector2(0.6, 0.5)
	b.box(Vector3(1.95, 1.0, -0.2), Vector3(0.62, 2.0, 0.14), p.t(Color(0.07, 0.075, 0.08, 0.0)), false)
	b.uv2 = Vector2(0.0, 0.3)
	b.quad(Vector3(1.69, 0.5, -0.125), Vector3(2.21, 0.5, -0.125), Vector3(2.21, 1.8, -0.125), Vector3(1.69, 1.8, -0.125), Vector3.BACK, Color(1, 1, 1, EM_POSTER),
			Vector2.ZERO, Vector2.ZERO, _uvq())


static func _spool(b: MB, p: Pal) -> void:
	var start := b.verts.size()
	b.uv2 = Vector2(0.0, 0.8)
	var wood := p.t(Color(0.15, 0.11, 0.08, 0.0))
	for s in [-0.27, 0.23]:
		b.cylinder(Vector3(0, s, 0), 0.8, 0.05, 10, wood, -1.0, true, true)
	b.cylinder(Vector3(0, -0.25, 0), 0.3, 0.5, 8, p.t(Color(0.09, 0.08, 0.07, 0.0)), -1.0, false)
	b.uv2 = Vector2(0.1, 0.5)
	b.cylinder(Vector3(0, -0.22, 0), 0.56, 0.44, 10, Color(0.015, 0.02, 0.02, 0.0), -1.0, false)
	b.xform_from(start, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.8, 0)))
	b.uv2 = Vector2(0.0, 0.3)
	b.box(Vector3(0.5, 0.06, 0.62), Vector3(0.5, 0.012, 0.01), p.glow(0.5, true), false)


static func _antenna(b: MB, p: Pal, near: bool) -> void:
	var iron := p.t(Color(0.08, 0.08, 0.085, 0.0))
	b.uv2 = Vector2(0.7, 0.5)
	if not near:
		b.cylinder(Vector3(0, 0, 0), 0.12, 8.8, 4, iron, 0.04, false)
		b.uv2 = Vector2(0.0, 0.3)
		b.box(Vector3(0, 8.9, 0), Vector3(0.16, 0.2, 0.16), Color(1, 1, 1, EM_BEACON), false)
		return
	b.box(Vector3(0, 0.05, 0), Vector3(0.5, 0.1, 0.5), p.t(Color(0.12, 0.12, 0.125, 0.0)), false)
	b.cylinder(Vector3(0, 0.1, 0), 0.12, 8.7, 6, iron, 0.04, false)
	for k in 3:
		var h := 4.6 + 1.6 * float(k)
		var w := 0.7 - 0.2 * float(k)
		b.strut(Vector3(-w, h, 0), Vector3(w, h, 0), 0.04, iron, false)
		b.strut(Vector3(0, h + 0.5, -w * 0.8), Vector3(0, h + 0.5, w * 0.8), 0.04, iron, false)
	var start := b.verts.size()
	b.cylinder(Vector3(0, 0, 0), 0.5, 0.1, 8, p.t(Color(0.2, 0.2, 0.21, 0.0)), 0.08)
	b.xform_from(start, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-70.0)), Vector3(0.45, 6.4, 0.2)))
	b.uv2 = Vector2(0.0, 0.3)
	b.box(Vector3(0, 8.9, 0), Vector3(0.16, 0.2, 0.16), Color(1, 1, 1, EM_BEACON), false)
	b.box(Vector3(0, 6.1, 0.1), Vector3(0.1, 0.1, 0.1), p.glow(0.8), false)


static func _billboard(b: MB, p: Pal, near: bool) -> void:
	var iron := p.t(Color(0.07, 0.075, 0.08, 0.0))
	b.uv2 = Vector2(0.7, 0.5)
	for x in [-1.7, 1.7]:
		b.box(Vector3(x, 1.9, -0.12), Vector3(0.24, 3.8, 0.24), iron, false)
	b.box(Vector3(0, 4.9, 0), Vector3(5.2, 2.6, 0.22), p.t(Color(0.04, 0.042, 0.046, 0.0)), false)
	b.uv2 = Vector2(0.0, 0.3)
	b.quad(Vector3(-2.4, 3.8, 0.115), Vector3(2.4, 3.8, 0.115), Vector3(2.4, 5.95, 0.115), Vector3(-2.4, 5.95, 0.115), Vector3.BACK, Color(1, 1, 1, EM_POSTER),
			Vector2.ZERO, Vector2.ZERO, _uvq())
	if near:
		b.box(Vector3(0, 6.3, 0.25), Vector3(5.0, 0.07, 0.07), p.glow(0.8), false)
		b.uv2 = Vector2(0.7, 0.5)
		b.strut(Vector3(-1.7, 3.0, -0.12), Vector3(-1.7, 4.0, -0.9), 0.08, iron, false)
		b.strut(Vector3(1.7, 3.0, -0.12), Vector3(1.7, 4.0, -0.9), 0.08, iron, false)


static func _planter(b: MB, p: Pal) -> void:
	var conc := p.t(Color(0.17, 0.17, 0.175, 0.0))
	b.uv2 = Vector2(0.0, 0.85)
	b.cylinder(Vector3(0, 0, 0), 0.95, 0.52, 6, conc, 0.9, false)
	b.cylinder(Vector3(0, 0.52, 0), 1.0, 0.07, 6, p.t(Color(0.24, 0.24, 0.245, 0.0)), 0.95)
	b.uv2 = Vector2(0.0, 0.9)
	b.cylinder(Vector3(0, 0.56, 0), 0.82, 0.05, 6, Color(0.02, 0.04, 0.025, 0.0), -1.0, true)
	b.uv2 = Vector2(0.0, 0.5)
	var stems := [[Vector3(-0.3, 0.6, 0.1), 1.2, 0.24], [Vector3(0.28, 0.6, -0.12), 0.95, 0.2], [Vector3(0.05, 0.6, 0.3), 0.7, 0.17]]
	for s in stems:
		var base: Vector3 = s[0]
		var h: float = s[1]
		b.cylinder(base, 0.045, h, 5, Color(0.02, 0.07, 0.04, 0.0), 0.012, false)
		b.sphere(base + Vector3(0, h + 0.05, 0), Vector3(s[2], s[2] * 0.8, s[2]), 5, 3, p.glow(0.65, base.x > 0.0))


static func _barrier(b: MB, p: Pal) -> void:
	var iron := p.t(Color(0.07, 0.075, 0.08, 0.0))
	b.uv2 = Vector2(0.5, 0.6)
	for x in [-1.15, 1.15]:
		b.box(Vector3(x, 0.45, 0), Vector3(0.22, 0.9, 0.22), iron, false)
	var stripe := [Color(0.5, 0.2, 0.03, 0.0), Color(0.47, 0.47, 0.45, 0.0)]
	for k in 6:
		var c: Color = p.t(stripe[k % 2])
		b.box(Vector3(-0.96 + 0.385 * float(k), 0.7, 0), Vector3(0.385, 0.16, 0.1), c, false)
	for k in 4:
		b.box(Vector3(-0.75 + 0.5 * float(k), 0.4, 0), Vector3(0.32, 0.12, 0.08), p.t(stripe[(k + 1) % 2]), false)
	b.uv2 = Vector2(0.0, 0.3)
	for x in [-1.15, 1.15]:
		b.box(Vector3(x, 0.96, 0), Vector3(0.12, 0.1, 0.12), Color(1.0, 0.5, 0.05, EM_FLASHER))


static func _stall(b: MB, p: Pal, near: bool) -> void:
	var cloth := p.cloth()
	var wood := p.t(Color(0.11, 0.085, 0.065, 0.0))
	b.uv2 = Vector2(0.0, 0.75)
	b.box(Vector3(0, 0.45, 0.15), Vector3(2.6, 0.9, 0.8), wood, false)
	# canopy: a sloped sheet from the high back (y 2.5) down to the front edge (y 2.05), both faces
	var n_up := Vector3(0, 0.9, 0.44).normalized()
	b.quad(Vector3(-1.5, 2.5, -0.85), Vector3(1.5, 2.5, -0.85), Vector3(1.5, 2.05, 1.05), Vector3(-1.5, 2.05, 1.05), n_up, cloth)
	b.quad(Vector3(-1.5, 2.5, -0.85), Vector3(1.5, 2.5, -0.85), Vector3(1.5, 2.05, 1.05), Vector3(-1.5, 2.05, 1.05), -n_up, cloth * 0.55)
	if not near:
		return
	b.quad(Vector3(-1.5, 2.05, 1.05), Vector3(1.5, 2.05, 1.05), Vector3(1.5, 1.85, 1.05), Vector3(-1.5, 1.85, 1.05), Vector3.BACK, cloth * 0.8)
	b.uv2 = Vector2(0.6, 0.5)
	for x in [-1.4, 1.4]:
		b.box(Vector3(x, 1.2, -0.75), Vector3(0.07, 2.4, 0.07), p.t(Color(0.07, 0.07, 0.075, 0.0)), false)
		b.box(Vector3(x, 1.0, 0.95), Vector3(0.07, 2.0, 0.07), p.t(Color(0.07, 0.07, 0.075, 0.0)), false)
	b.uv2 = Vector2(0.0, 0.8)
	b.box(Vector3(0, 1.5, -0.85), Vector3(2.8, 1.6, 0.04), p.t(Color(0.05, 0.05, 0.055, 0.0)), false)
	b.uv2 = Vector2(0.0, 0.3)
	var wares := [[-0.85, 0.3, 0.22], [-0.2, 0.22, 0.3], [0.5, 0.26, 0.2], [1.0, 0.18, 0.24]]
	for w in wares:
		b.box(Vector3(w[0], 0.9 + w[1] * 0.5, 0.1), Vector3(w[2], w[1], w[2]), p.glow(0.55, w[0] > 0.0), false)
	b.uv2 = Vector2(0.0, 0.4)
	for x in [-0.9, 0.9]:
		b.sphere(Vector3(x, 1.95, 0.85), Vector3(0.14, 0.18, 0.14), 5, 3, p.glow(0.8, x > 0.0))


static func _transformer(b: MB, p: Pal) -> void:
	b.uv2 = Vector2(0.6, 0.55)
	b.box(Vector3(0, 0.8, 0), Vector3(1.5, 1.4, 0.9), p.t(Color(0.10, 0.105, 0.11, 0.0)), false)
	b.box(Vector3(0, 1.54, 0), Vector3(1.62, 0.08, 1.02), p.t(Color(0.05, 0.05, 0.055, 0.0)))
	b.box(Vector3(0, 0.07, 0), Vector3(1.56, 0.14, 0.96), p.t(Color(0.15, 0.15, 0.155, 0.0)), false)
	for k in 4:
		b.box(Vector3(-0.45 + 0.3 * float(k), 0.85, 0.455), Vector3(0.2, 0.7, 0.02), Color(0.015, 0.016, 0.018, 0.0))
	b.strut(Vector3(0.55, 1.58, 0.0), Vector3(1.25, 1.2, 0.0), 0.07, p.t(Color(0.06, 0.06, 0.065, 0.0)), false)
	b.strut(Vector3(1.25, 1.2, 0.0), Vector3(1.25, 0.0, 0.0), 0.07, p.t(Color(0.06, 0.06, 0.065, 0.0)), false)
	for x in [-0.4, 0.0, 0.4]:
		b.cylinder(Vector3(x, 1.58, 0), 0.07, 0.22, 5, Color(0.15, 0.14, 0.12, 0.0), 0.04)
	b.uv2 = Vector2(0.0, 0.3)
	b.box(Vector3(0.6, 1.4, 0.455), Vector3(0.1, 0.1, 0.03), Color(1.0, 0.5, 0.05, EM_FLASHER))


static func _charge_post(b: MB, p: Pal) -> void:
	var metal := p.t(Color(0.075, 0.08, 0.09, 0.0))
	b.uv2 = Vector2(0.7, 0.4)
	b.cylinder(Vector3(0, 0, 0), 0.2, 0.06, 6, metal, -1.0, false)
	b.cylinder(Vector3(0, 0.06, 0), 0.11, 1.0, 8, metal, 0.09, false)
	b.cylinder(Vector3(0, 1.06, 0), 0.12, 0.1, 8, p.t(Color(0.04, 0.04, 0.045, 0.0)), 0.07)
	b.uv2 = Vector2(0.0, 0.3)
	b.cylinder(Vector3(0, 0.74, 0), 0.118, 0.07, 8, p.glow(0.7), -1.0, false)
	b.cylinder(Vector3(0, 0.3, 0), 0.113, 0.03, 8, p.glow(0.4, true), -1.0, false)


static func _crates(b: MB, p: Pal) -> void:
	var wood := p.t(Color(0.12, 0.09, 0.065, 0.0))
	var dark := p.t(Color(0.07, 0.065, 0.06, 0.0))
	b.uv2 = Vector2(0.0, 0.8)
	for k in 3:
		b.box(Vector3(-0.35 + 0.35 * float(k), 0.05, 0.0), Vector3(0.2, 0.1, 1.0), dark, false)
	b.box(Vector3(-0.05, 0.45, 0.0), Vector3(1.0, 0.7, 0.9), wood, false)
	b.box_yaw(Vector3(-0.1, 1.1, 0.0), Vector3(0.8, 0.6, 0.78), 0.35, p.t(Color(0.13, 0.1, 0.07, 0.0)), false)
	b.box(Vector3(0.85, 0.3, 0.1), Vector3(0.7, 0.5, 0.8), dark, false)
	b.uv2 = Vector2(0.4, 0.5)
	b.box(Vector3(-0.05, 0.62, 0.455), Vector3(0.9, 0.06, 0.012), p.glow(0.35), false)


static func _lantern(b: MB, p: Pal) -> void:
	var iron := p.t(Color(0.07, 0.07, 0.075, 0.0))
	b.uv2 = Vector2(0.7, 0.5)
	b.cylinder(Vector3(0, 0, 0), 0.08, 3.6, 6, iron, 0.045, false)
	b.strut(Vector3(0, 3.35, 0), Vector3(-0.9, 3.5, 0), 0.05, iron, false)
	b.strut(Vector3(0, 3.35, 0), Vector3(0.9, 3.5, 0), 0.05, iron, false)
	b.uv2 = Vector2(0.0, 0.4)
	for k in 2:
		var x := -0.9 if k == 0 else 0.9
		b.strut(Vector3(x, 3.5, 0), Vector3(x, 3.18, 0), 0.015, iron, false)
		b.sphere(Vector3(x, 2.98, 0), Vector3(0.2, 0.26, 0.2), 6, 4, p.glow(0.85, k == 1))
	b.cylinder(Vector3(0, 3.6, 0), 0.05, 0.12, 5, iron, 0.01, false)


## Hand an existing family (its mesh and [Transform3D, Color(seed, ...)] items) over to the merged window instead of drawing it as a MultiMesh of its own.
func fold_family(kind: int, mesh: ArrayMesh, items: Array) -> void:
	_folded_geo[kind] = geo_from_mesh(mesh)
	_folded.append([kind, items])


## Flat geometry (see make_geo) of the first surface of an ArrayMesh.
static func geo_from_mesh(mesh: ArrayMesh) -> Dictionary:
	var arr := mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var u2s: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2] if arr[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var n := idx.size()
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c := PackedColorArray()
	v.resize(n)
	nr.resize(n)
	uv.resize(n)
	uv2.resize(n)
	c.resize(n)
	for i in n:
		var j := idx[i]
		v[i] = vs[j]
		nr[i] = ns[j]
		uv[i] = uvs[j] if j < uvs.size() else Vector2.ZERO
		uv2[i] = u2s[j] if j < u2s.size() else Vector2.ZERO
		c[i] = cs[j] if j < cs.size() else Color(1, 1, 1, 0)
	return {"v": v, "n": nr, "uv": uv, "uv2": uv2, "c": c, "count": n}


# --- placement -------------------------------------------------------------------------------------------------------------

func _cell_of(x: float, z: float) -> int:
	var cx := clampi(int(floor((x - GRID_ORIGIN) / CELL)), 0, GRID_N - 1)
	var cz := clampi(int(floor((z - GRID_ORIGIN) / CELL)), 0, GRID_N - 1)
	return cz * GRID_N + cx


func _gkey(x: float, z: float) -> int:
	return (int(floor(x / 4.0)) + 200) * 1000 + (int(floor(z / 4.0)) + 200)


func _block_obstacle(x: float, z: float, r: float) -> void:
	var k := _gkey(x, z)
	var arr: Array = _grid.get(k, [])
	arr.append(Vector3(x, z, r))
	_grid[k] = arr


func _free(x: float, z: float, r: float) -> bool:
	var cx := int(floor(x / 4.0))
	var cz := int(floor(z / 4.0))
	for ix in range(cx - 2, cx + 3):
		for iz in range(cz - 2, cz + 3):
			var arr: Array = _grid.get((ix + 200) * 1000 + (iz + 200), [])
			for o: Vector3 in arr:
				var dx := o.x - x
				var dz := o.y - z
				var rr := o.z + r
				if dx * dx + dz * dz < rr * rr:
					return false
	return true


## Existing street furniture and plazas become obstacles: the kit never stands inside them.
func _collect_obstacles(layout: CityLayout, parts: Array[Dictionary]) -> void:
	var radius := {"Lamps": 1.1, "Signals": 1.2, "Dumpsters": 1.7, "BusStops": 2.4, "Kiosks": 1.8, "Planters": 1.6, "Hydrants": 0.9, "Barriers": 1.5, "Trash": 1.0}
	for part: Dictionary in parts:
		var fname: String = part.get("name", "")
		if not radius.has(fname):
			continue
		var mm: MultiMesh = part["mm"]
		var stride := 12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
		var buf := mm.buffer
		for i in mm.instance_count:
			_block_obstacle(buf[i * stride + 3], buf[i * stride + 11], float(radius[fname]))
	for pl: Vector2 in layout.plazas:
		_block_obstacle(pl.x, pl.y, 14.0)


func _pick_kind(d: int, mode: int) -> int:
	var total := 0.0
	for k in KIND_COUNT:
		if (int(KINDS[k]["mode"]) & mode) != 0:
			total += float((KINDS[k]["w"] as Array)[d])
	var r := rng.randf() * total
	for k in KIND_COUNT:
		if (int(KINDS[k]["mode"]) & mode) == 0:
			continue
		var w := float((KINDS[k]["w"] as Array)[d])
		if w <= 0.0:
			continue
		if r <= w:
			return k
		r -= w
	return STANDPIPE


func _try_place(layout: CityLayout, kind: int, x: float, z: float, yaw: float) -> bool:
	if absf(x) > CityLayout.HALF + 8.0 or absf(z) > CityLayout.HALF + 8.0:
		return false
	var info: Dictionary = KINDS[kind]
	var r := maxf(float(info["hw"]), float(info["hd"]))
	if CityLayout.on_road(x, z, 0.1 - float(info["hd"])):              # the prop's depth must stay on the sidewalk side of the kerb
		return false
	if layout.lot_at(x, z, r + 0.35) != null:
		return false
	if not _free(x, z, r):
		return false
	var d := Districts.look_at(x, z)
	var variant := rng.randi() % 3
	var seed_v := rng.randf()
	var c := _cell_of(x, z)
	var arr: PackedFloat32Array = cells[c]
	arr.append_array(PackedFloat32Array([float(kind), x, z, yaw, seed_v, float(variant)]))
	cells[c] = arr
	counts[c] += 1
	_block_obstacle(x, z, r)
	placements.append({"kind": kind, "pos": Vector3(x, 0.0, z), "yaw": yaw, "district": d, "variant": variant, "seed": seed_v})
	kind_count[kind] += 1
	district_count[d] += 1
	return true


## Fill the placements (deterministic) and add the light sprites (props.glow_add) of the lit kinds.
func build(props: RefCounted, layout: CityLayout, parts: Array[Dictionary]) -> void:
	rng.seed = 160016
	cells.clear()
	placements.clear()
	_grid.clear()
	_geo.clear()
	glow_sprites = 0
	kind_count = PackedInt32Array()
	kind_count.resize(TOTAL_KINDS)
	district_count = PackedInt32Array()
	district_count.resize(Districts.COUNT)
	counts = PackedInt32Array()
	counts.resize(GRID_N * GRID_N)
	for c in GRID_N * GRID_N:
		cells.append(PackedFloat32Array())
	_collect_obstacles(layout, parts)
	for f in _folded:
		var fk: int = f[0]
		for it in f[1]:
			var fxf: Transform3D = it[0]
			var fc := _cell_of(fxf.origin.x, fxf.origin.z)
			var farr: PackedFloat32Array = cells[fc]
			farr.append_array(PackedFloat32Array([float(fk), fxf.origin.x, fxf.origin.z, atan2(fxf.basis.z.x, fxf.basis.z.z), (it[1] as Color).r, 0.0]))
			cells[fc] = farr
			counts[fc] += 1
			var fd := Districts.look_at(fxf.origin.x, fxf.origin.z)
			placements.append({"kind": fk, "pos": Vector3(fxf.origin.x, 0.0, fxf.origin.z), "yaw": atan2(fxf.basis.z.x, fxf.basis.z.z), "district": fd, "variant": 0, "seed": (it[1] as Color).r})
			kind_count[fk] += 1
			_block_obstacle(fxf.origin.x, fxf.origin.z, maxf(float(KINDS[fk]["hw"]), float(KINDS[fk]["hd"])))
	var n := CityLayout.N
	for i in n:
		for j in n:
			var bx := -CityLayout.HALF + (float(i) + 0.5) * CityLayout.PITCH
			var bz := -CityLayout.HALF + (float(j) + 0.5) * CityLayout.PITCH
			# the four faces of the block: outward normal, then props stand just inside the kerb, front towards the street
			for face in 4:
				var nrm := Vector2(1, 0) if face == 0 else (Vector2(-1, 0) if face == 1 else (Vector2(0, 1) if face == 2 else Vector2(0, -1)))
				var tan_v := Vector2(-nrm.y, nrm.x)
				var yaw := atan2(nrm.x, nrm.y)
				for attempt in 6:
					var d := Districts.look_at(bx + nrm.x * 29.0, bz + nrm.y * 29.0)
					var kind := _pick_kind(d, MODE_KERB)
					var info: Dictionary = KINDS[kind]
					var hd: float = info["hd"]
					var u := 30.0 - hd - 0.45
					var v := rng.randf_range(-22.0, 22.0)
					var pos := Vector2(bx, bz) + nrm * u + tan_v * v
					_try_place(layout, kind, pos.x, pos.y, yaw)
			# the alleys (the cross between the four lots) and the empty corners of the block
			for attempt in 6:
				var along_x := rng.randf() < 0.5
				var w := rng.randf_range(-5.0, 5.0)
				var s := rng.randf_range(-24.0, 24.0)
				var pos2 := Vector2(bx + s, bz + w) if along_x else Vector2(bx + w, bz + s)
				var d2 := Districts.look_at(pos2.x, pos2.y)
				var kind2 := _pick_kind(d2, MODE_ALLEY)
				var yaw2 := (0.0 if along_x else PI * 0.5) + float(rng.randi() % 2) * PI + rng.randf_range(-0.12, 0.12)
				_try_place(layout, kind2, pos2.x, pos2.y, yaw2)
	_place_flora(layout)
	_build_city_kit(layout)
	_add_glow(props)


## Park / plaza dressing of the creature kit: trees, plants and rocks in a ring round every plaza (own generator per plaza, the rest of the kit is unaffected).
func _place_flora(layout: CityLayout) -> void:
	for pl: Vector2 in layout.plazas:
		for it in CreatureKit.ring(pl):
			var pos: Vector2 = it["pos"]
			var kind := FLORA_TREE + int(it["kind"])
			var c := _cell_of(pos.x, pos.y)
			var arr: PackedFloat32Array = cells[c]
			arr.append_array(PackedFloat32Array([float(kind), pos.x, pos.y, float(it["yaw"]), float(it["seed"]), float(it["variant"])]))
			cells[c] = arr
			counts[c] += 1
			placements.append({"kind": kind, "pos": Vector3(pos.x, 0.0, pos.y), "yaw": float(it["yaw"]), "district": Districts.look_at(pos.x, pos.y), "variant": int(it["variant"]), "seed": float(it["seed"])})
			kind_count[kind] += 1
			district_count[Districts.look_at(pos.x, pos.y)] += 1


## City-kit placements (facade bands, rooftop units, road markings from city_kit_world.gd) plus kerb furniture (bollards, planters, drains, manholes).
## Height rides in the variant slot: variant = (variant & 3) | (round(y * 4) << 2).
func _build_city_kit(layout: CityLayout) -> void:
	for it in KitWorld.layout_items(layout):
		_add_raw(KC_FIRST + int(it["kind"]), it["x"], it["z"], it["yaw"], it["y"], int(it["variant"]))
	var r2 := RandomNumberGenerator.new()
	r2.seed = 190020
	for i in CityLayout.N:
		for j in CityLayout.N:
			var base := Vector2(-CityLayout.HALF + (float(i) + 0.5) * CityLayout.PITCH, -CityLayout.HALF + (float(j) + 0.5) * CityLayout.PITCH)
			for face in 4:
				var nrm := Vector2(1, 0) if face == 0 else (Vector2(-1, 0) if face == 1 else (Vector2(0, 1) if face == 2 else Vector2(0, -1)))
				var tan_v := Vector2(-nrm.y, nrm.x)
				var yaw := atan2(nrm.x, nrm.y)
				if r2.randf() < 0.6:                                              # a short row of bollards at the kerb
					var v0 := r2.randf_range(-20.0, 20.0)
					for b in 3:
						var pb := base + nrm * 29.2 + tan_v * (v0 + float(b) * 1.8)
						_try_place(layout, KC_FIRST + KitWorld.BOLLARD, pb.x, pb.y, yaw)
				if r2.randf() < 0.3:
					var pp := base + nrm * (30.0 - 1.45) + tan_v * r2.randf_range(-20.0, 20.0)
					_try_place(layout, KC_FIRST + KitWorld.PLANTER, pp.x, pp.y, yaw)
				if r2.randf() < 0.5:                                              # storm drain in the gutter
					var pd := base + nrm * 30.35 + tan_v * r2.randf_range(-22.0, 22.0)
					_add_raw(KC_FIRST + KitWorld.DRAIN, pd.x, pd.y, yaw, KitWorld.DECAL_Y, 0)
				if r2.randf() < 0.35:                                             # manhole in the lane
					var pm := base + nrm * 35.0 + tan_v * r2.randf_range(-22.0, 22.0)
					_add_raw(KC_FIRST + KitWorld.MANHOLE, pm.x, pm.y, r2.randf() * TAU, KitWorld.DECAL_Y, 0)


## A placement without spacing or lot tests (the caller knows it is clear): decals, facade bands, rooftop units.
func _add_raw(kind: int, x: float, z: float, yaw: float, y: float, variant: int) -> void:
	var d := Districts.look_at(x, z)
	var packed := (variant & 3) | (int(round(y * 4.0)) << 2)
	var c := _cell_of(x, z)
	var arr: PackedFloat32Array = cells[c]
	arr.append_array(PackedFloat32Array([float(kind), x, z, yaw, 0.5, float(packed)]))
	cells[c] = arr
	counts[c] += 1
	placements.append({"kind": kind, "pos": Vector3(x, y, z), "yaw": yaw, "district": d, "variant": variant & 3, "seed": 0.5})
	kind_count[kind] += 1
	district_count[d] += 1


func _add_glow(props: RefCounted) -> void:
	for p in placements:
		var k: int = p["kind"]
		var pos: Vector3 = p["pos"]
		var xf := Transform3D(Basis(Vector3.UP, float(p["yaw"])), pos)
		var pal := Districts.palette(int(p["district"]))
		var acc: Color = pal["accent"]
		var acc2: Color = pal["accent2"]
		var sd: float = p["seed"]
		match k:
			SHELTER:
				props.call("glow_add", xf * Vector3(0, 2.3, 0.4), Color(acc.r, acc.g, acc.b, 0.8), 0, 3.6, 0.0, sd)
			BILLBOARD:
				props.call("glow_add", xf * Vector3(0, 4.9, 1.2), Color(0.8 + 0.2 * acc.r, 0.8 + 0.2 * acc.g, 0.8 + 0.2 * acc.b, 0.8), 0, 8.0, 0.0, sd)
			STALL:
				props.call("glow_add", xf * Vector3(0, 1.7, 0.8), Color(acc2.r, acc2.g, acc2.b, 0.9), 1, 3.0, 0.0, sd)
			LANTERN:
				props.call("glow_add", xf * Vector3(-0.9, 2.98, 0), Color(acc.r, acc.g, acc.b, 1.0), 1, 2.2, 0.0, sd)
				props.call("glow_add", xf * Vector3(0.9, 2.98, 0), Color(acc2.r, acc2.g, acc2.b, 1.0), 1, 2.2, 0.0, fposmod(sd + 0.37, 1.0))
				glow_sprites += 1
			VENT_STACK:
				props.call("glow_add", xf * Vector3(0, 1.95, 0.5), Color(1.0, 0.45, 0.15, 0.9), 0, 2.6, 0.0, sd)
			_:
				continue
		glow_sprites += 1


# --- the geometry cache ------------------------------------------------------------------------------------------------------

## Cached geometry of (kind, level, district, variant); {} when the kind has no far level.
func geo(kind: int, near: bool, d: int, variant: int) -> Dictionary:
	if kind >= KC_FIRST:
		if not near:
			var fkey := ((kind * 4 + d) * 4 + (variant & 3)) + 200000
			if not _geo.has(fkey):
				_geo[fkey] = KitWorld.make_far(kind - KC_FIRST, d, variant & 3)
			return _geo[fkey]
		var ckey := ((kind * 4 + d) * 4 + (variant & 3)) + 100000
		if not _geo.has(ckey):
			_geo[ckey] = KitWorld.make_geo(kind - KC_FIRST, d, variant & 3, Districts.palette(d)["tint"])
		return _geo[ckey]
	if kind >= FLORA_TREE:
		return CreatureKit.geo(kind, variant) if near else {}
	if kind >= KIND_COUNT:
		return _folded_geo.get(kind, {}) if near else {}
	var key := ((kind * 2 + (1 if near else 0)) * 4 + d) * 4 + variant
	if not _geo.has(key):
		_geo[key] = make_geo(kind, near, d, variant)
	return _geo[key]


func total_placements() -> int:
	return placements.size()
