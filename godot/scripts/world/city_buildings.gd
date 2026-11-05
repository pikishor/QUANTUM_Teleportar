extends RefCounted
## Buildings of the city: one MultiMesh per building class (block, stepped, offset, tiered, podium, landmark), facade drawn by
## the building shader. Per-instance data: transform scale = (width, height, depth), INSTANCE_CUSTOM = (seed, neon, style, flags),
## COLOR = (wall tint, lit-window probability). The classes, styles and flags are derived from the lot (the JS-faithful layout
## stream is never touched).

const MB := preload("res://scripts/world/mesh_builder.gd")
const BM := preload("res://scripts/world/building_meshes.gd")
const Districts := preload("res://scripts/world/city_districts.gd")
const BUILDING_SHADER := preload("res://assets/shaders/building.gdshader")
const MIRROR_SHADER := preload("res://assets/shaders/building_mirror.gdshader")
const LEAN_SHADER := preload("res://assets/shaders/building_far.gdshader")       ## LOW+: the lean facade of the distant megacity on every building

## Facade tints: desaturated concrete / glass / brick, the shader darkens them for night.
const TINTS: Array[Color] = [
	Color(0.34, 0.40, 0.44), Color(0.46, 0.42, 0.37), Color(0.28, 0.38, 0.48),
	Color(0.44, 0.27, 0.22), Color(0.36, 0.40, 0.31), Color(0.24, 0.26, 0.30),
]

const STYLE_PUNCHED := 0
const STYLE_RIBBON := 1
const STYLE_CURTAIN := 2
const STYLE_FINS := 3
const STYLE_BRICK := 4

const FLAG_CORNER := 1
const FLAG_BANDS := 2
const FLAG_ROOF_NEON := 4
const FLAG_SCREEN := 8
const FLAG_BEACON := 16


class Building extends RefCounted:
	var lot: CityLayout.Lot
	var cls: StringName = &"block"
	var style := 0
	var flags := 0
	var seed := 0.0
	var tint := Color.WHITE        ## rgb = wall tint, a = lit probability
	var index := 0


var buildings: Array[Building] = []
var meshes := {}                   ## class -> ArrayMesh
var multimeshes := {}              ## class -> MultiMesh
var instance_count := 0


static func hash01(i: int, salt: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + float(salt) * 78.233) * 43758.5453, 1.0)


func assign(layout: CityLayout) -> void:
	buildings.clear()
	for i in layout.lots.size():
		var lot: CityLayout.Lot = layout.lots[i]
		var b := Building.new()
		b.lot = lot
		b.index = i
		b.seed = hash01(i, 1)
		var r := hash01(i, 2)
		var rs := hash01(i, 3)
		var h := lot.h
		if h < 20.0:
			b.cls = &"block"
			b.style = STYLE_BRICK if rs < 0.55 else STYLE_PUNCHED
		elif h < 36.0:
			b.cls = &"block" if r < 0.55 else &"offset"
			b.style = STYLE_PUNCHED if rs < 0.40 else (STYLE_BRICK if rs < 0.65 else STYLE_RIBBON)
		elif h < 52.0:
			b.cls = &"stepped" if r < 0.40 else (&"offset" if r < 0.65 else &"podium")
			b.style = STYLE_RIBBON if rs < 0.30 else (STYLE_PUNCHED if rs < 0.65 else STYLE_CURTAIN)
		elif h < 75.0:
			b.cls = &"tiered" if r < 0.40 else (&"stepped" if r < 0.60 else &"podium")
			b.style = STYLE_CURTAIN if rs < 0.45 else (STYLE_FINS if rs < 0.70 else (STYLE_RIBBON if rs < 0.85 else STYLE_PUNCHED))
		else:
			b.cls = &"landmark" if r < 0.55 else (&"tiered" if r < 0.80 else &"podium")
			b.style = STYLE_CURTAIN if rs < 0.60 else STYLE_FINS
		var fl := 0
		if h >= 62.0 and hash01(i, 4) < 0.30:
			fl |= FLAG_CORNER
		if h >= 44.0 and hash01(i, 5) < 0.16:
			fl |= FLAG_BANDS
		if h >= 28.0 and hash01(i, 6) < 0.45:
			fl |= FLAG_ROOF_NEON
		var block_cz := -CityLayout.HALF + (lot.block_j + 0.5) * CityLayout.PITCH
		if h >= 44.0 and lot.cz > block_cz and hash01(i, 7) < 0.4:
			fl |= FLAG_SCREEN
		if h >= 62.0:
			fl |= FLAG_BEACON
		b.flags = fl
		var tint := TINTS[lot.tint % TINTS.size()]
		var lit_p := lerpf(0.30, 0.62, hash01(i, 8)) if h >= 44.0 else lerpf(0.14, 0.42, hash01(i, 8))
		var district := Districts.at(lot.cx, lot.cz)
		b.tint = Districts.wall_tint(Color(tint.r, tint.g, tint.b, lit_p), district)           # district palette: warm market, rust foundry, green-grey slums, cool towers
		lot.neon = Districts.neon_index(lot.neon, i, district)                                # most lots take the district's neon colour (ground spill and signs follow lot.neon)
		buildings.append(b)


## Fill one MultiMesh per class. Returns the number of instances.
func build_multimeshes() -> void:
	multimeshes.clear()
	instance_count = 0
	var per_class := {}
	for cls: StringName in BM.ORDER:
		per_class[cls] = []
	for b in buildings:
		(per_class[b.cls] as Array).append(b)
	for cls: StringName in BM.ORDER:
		var list: Array = per_class[cls]
		var mesh := BM.build(cls)
		meshes[cls] = mesh
		var mm := MB.new_multimesh(mesh, list.size(), true, true)
		var buf := MB.new_buffer(list.size(), true, true)
		for k in list.size():
			var b: Building = list[k]
			var lot := b.lot
			var xf := Transform3D(Basis.from_scale(Vector3(lot.w, lot.h, lot.d)), Vector3(lot.cx, 0.0, lot.cz))
			MB.write_instance(buf, k, xf, true, b.tint, true, Color(b.seed, float(lot.neon), float(b.style), float(b.flags)))
		mm.buffer = buf
		multimeshes[cls] = mm
		instance_count += list.size()


func make_material(mirror := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = MIRROR_SHADER if mirror else BUILDING_SHADER
	if mirror:
		m.render_priority = -120
	return m
