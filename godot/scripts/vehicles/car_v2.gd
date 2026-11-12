class_name CarV2
extends RefCounted
## Cars v2 (round 6): the runtime of the Blender-built car models `assets/models/cv2_<archetype>.glb` (tools/blender/build_cars_v2.py, generator tools/blender/carv2/).
##
## A model has Body (LOD0, about 6-9k triangles with the wheels, surfaces Paint / Details / Glass), Body_LOD1 (about 1.5k, the same three surfaces, so one set of per-car materials),
## Body_LOD2 (about 400, one surface "Lod", drawn beyond LOD2_DIST), the wheel nodes WheelFL / FR / RL / RR (a tyre mesh and a coarse one each) and anchors (PlateF, PlateR, Driver, FxEngine ...).
## Per car this class makes five ShaderMaterials (paint with metallic flake, clear coat reflection and dents; trim; glass with a reflection of the street and cracks; wheel with the
## tread normal map; the far LOD) and drives them: paint finish, lamps, wear, dirt and wet, dents (vertex displacement on the GPU), cracked glass, torn-off parts. VehicleVisual calls it.

const LOD1_DIST := 26.0                       ## Body (LOD0) up to here, Body_LOD1 beyond
const LOD2_DIST := 64.0                       ## the 400 triangle car beyond here
const LOD_MARGIN := 3.0
const WHEEL_LOD1 := 22.0                      ## the full tyre mesh only this close
const COAT := 1.0                             ## clear coat strength of the paint (the shader's `coat`)
const PAINT_SPECULAR := 0.9                   ## the shader's `spec` default: a lacquer lets street lamps and neon leave a highlight
const PAINT_RIM := 0.6                        ## the shader's `rim` default
const MAX_DENTS := 6
const DENT_MERGE := 0.55
const SHADER_DIR := "res://assets/shaders/"
const FLAKE_TEX := "res://assets/textures/carv2_flake_normal.png"
const TREAD_TEX := "res://assets/textures/carv2_tread_normal.png"
const PART_BITS := {&"bumper_f": 1, &"bumper_r": 2, &"hood": 3, &"trunk": 4, &"door_fl": 5, &"door_fr": 6, &"door_rl": 7, &"door_rr": 8}

## The twelve paints of the street palette (VehicleSpecs.COLORS): colour, flake (0 flat .. 1 coarse), metal, rough, pearl shift, pearl colour.
const FINISH := [
	{"flake": 0.35, "metal": 0.28, "rough": 0.26},                                                                          # 0 oxblood
	{"flake": 0.55, "metal": 0.42, "rough": 0.24},                                                                          # 1 steel blue
	{"flake": 0.5, "metal": 0.4, "rough": 0.22, "pearl": 0.25, "pearl_tint": Color(1.0, 0.85, 0.5)},                         # 2 brass (the starter): pearl gold
	{"flake": 0.4, "metal": 0.3, "rough": 0.27},                                                                            # 3 sage teal
	{"flake": 0.3, "metal": 0.25, "rough": 0.2, "pearl": 0.5, "pearl_tint": Color(0.75, 0.35, 0.95)},                        # 4 dusk violet: pearl
	{"flake": 0.2, "metal": 0.15, "rough": 0.24, "pearl": 0.2, "pearl_tint": Color(0.7, 0.85, 1.0)},                         # 5 pearl white
	{"flake": 0.6, "metal": 0.45, "rough": 0.26},                                                                           # 6 burnt copper
	{"flake": 0.45, "metal": 0.4, "rough": 0.2},                                                                            # 7 midnight
	{"flake": 0.5, "metal": 0.35, "rough": 0.18},                                                                           # 8 cobalt
	{"flake": 0.2, "metal": 0.12, "rough": 0.16},                                                                           # 9 racing red (gloss)
	{"flake": 0.7, "metal": 0.45, "rough": 0.3},                                                                            # 10 gunmetal
	{"flake": 0.3, "metal": 0.2, "rough": 0.2, "pearl": 0.3, "pearl_tint": Color(1.0, 0.5, 0.2)},                            # 11 sunset orange
]

static var _shaders := {}
static var _flake: Texture2D
static var _tread: Texture2D

var vis: VehicleVisual
var model: Node3D
var body: MeshInstance3D
var lod1: MeshInstance3D
var lod2: MeshInstance3D
var wheel_meshes: Array[MeshInstance3D] = []      ## every tyre mesh (both LODs of the four wheels)
var anchors := {}                                 ## name -> Vector3 (model space)
var paint_mat: ShaderMaterial
var details_mat: ShaderMaterial
var glass_mat: ShaderMaterial
var wheel_mat: ShaderMaterial
var lod_mat: ShaderMaterial
var dents: Array[Dictionary] = []
var doors := {}                                   ## "L" / "R" -> the door node (hinge pivot, hidden until a door swings): DoorL / DoorR of the model
var parts_lost := 0                               ## torn off for good (bumpers, hood, trunk lid, doors)
var parts_open := 0                               ## a door that is swinging (the shell's own door is hidden meanwhile)
var burning := false
var cracks := 0.0
var base_color := Color.WHITE
var finish := {}
var scuff := 0.0
var wet := 0.0
var dirt := 0.0
var glass_glow := 0.0                             ## cabin glow (set by VehicleVisual._write_beam)
var _kind: StringName = &""
var _rough := 0.26
var _metal := 0.3
var _pearl_col := Color.WHITE
var _glow := 0.18
var _iridescent := false
var _livery := 0
var _siren_on := false


static func shader(nm: String) -> Shader:
	if not _shaders.has(nm):
		_shaders[nm] = load(SHADER_DIR + nm + ".gdshader") as Shader
	return _shaders[nm]


static func flake_texture() -> Texture2D:
	if _flake == null and ResourceLoader.exists(FLAKE_TEX):
		_flake = load(FLAKE_TEX) as Texture2D
	return _flake


static func tread_texture() -> Texture2D:
	if _tread == null and ResourceLoader.exists(TREAD_TEX):
		_tread = load(TREAD_TEX) as Texture2D
	return _tread


## True when cars v2 are switched on for this run (QT_CARS_V2=0, QT_OPEN_MODELS=0 and QT_RV_MODELS=0 bring the older art back for before / after captures and the legacy tests).
static func enabled() -> bool:
	return OS.get_environment("QT_CARS_V2") != "0" and OS.get_environment("QT_OPEN_MODELS") != "0" and OS.get_environment("QT_RV_MODELS") != "0"


## The cv2 model name of a kind ("cv2_sedan") when it exists and is enabled, else "".
static func model_of(kind: StringName) -> String:
	if not enabled() or not VehicleSpecs.SPECS.has(kind):
		return ""
	var nm := String(VehicleSpecs.SPECS[kind].get("cv2", ""))
	if nm == "" or not ResourceLoader.exists("res://assets/models/cv2_%s.glb" % nm):
		return ""
	return "cv2_" + nm


## Dress a freshly instantiated model: materials per surface, LOD ranges, layers, wheels. Returns false when the model is not a v2 model.
func setup(visual: VehicleVisual, m: Node3D, kind: StringName, glow: Color) -> bool:
	vis = visual
	model = m
	_kind = kind
	body = m.get_node_or_null("Body") as MeshInstance3D
	lod1 = m.get_node_or_null("Body_LOD1") as MeshInstance3D
	lod2 = m.get_node_or_null("Body_LOD2") as MeshInstance3D
	if body == null:
		return false
	var spec: Dictionary = VehicleSpecs.SPECS[kind]
	for n in m.get_children():
		if n is Node3D and not (n is MeshInstance3D):
			anchors[String(n.name)] = (n as Node3D).position
	_make_materials(spec)
	_bind(body)
	if lod1 != null:
		_bind(lod1)
		body.visibility_range_end = LOD1_DIST
		body.visibility_range_end_margin = LOD_MARGIN
		lod1.visibility_range_begin = LOD1_DIST
		lod1.visibility_range_begin_margin = LOD_MARGIN
		lod1.visibility_range_end = LOD2_DIST
		lod1.visibility_range_end_margin = LOD_MARGIN
	if lod2 != null:
		_bind(lod2)
		lod2.visibility_range_begin = LOD2_DIST
		lod2.visibility_range_begin_margin = LOD_MARGIN
	for mi: MeshInstance3D in [body, lod1, lod2]:
		if mi != null:
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for wn: StringName in VehicleVisual.WHEEL_NAMES:
		var w := m.get_node_or_null(NodePath(wn)) as Node3D
		if w == null:
			continue
		var idx := 0
		for c in w.get_children():
			var wm := c as MeshInstance3D
			if wm == null:
				continue
			wm.set_surface_override_material(0, wheel_mat)
			wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wm.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			wm.layers = wm.layers | VehicleVisual.KEY_BIT | DynamicFill.FILL_BIT
			if idx == 0:
				wm.visibility_range_end = WHEEL_LOD1
				wm.visibility_range_end_margin = 2.0
			else:
				wm.visibility_range_begin = WHEEL_LOD1
				wm.visibility_range_begin_margin = 2.0
			wm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			wheel_meshes.append(wm)
			idx += 1
	for side in ["L", "R"]:
		var dn := m.get_node_or_null("Door" + side) as Node3D
		if dn != null:
			dn.visible = false
			for c in dn.get_children():
				if c is MeshInstance3D:
					_bind(c as MeshInstance3D)
			doors[side] = dn
	_glow = VehicleVisual.paint_glow()
	set_glow(glow)
	return true


func _make_materials(spec: Dictionary) -> void:
	paint_mat = ShaderMaterial.new()
	paint_mat.resource_name = "Paint"
	paint_mat.shader = shader("car_paint")
	paint_mat.set_shader_parameter(&"flake_tex", flake_texture())
	details_mat = ShaderMaterial.new()
	details_mat.resource_name = "Details"
	details_mat.shader = shader("car_details")
	glass_mat = ShaderMaterial.new()
	glass_mat.resource_name = "Glass"
	glass_mat.shader = shader("car_glass")
	glass_mat.set_shader_parameter(&"crack_tex", VehicleVisual._cracks_texture())
	var gl: Dictionary = spec.get("glass_tint", {})
	if gl.has("tint"):
		glass_mat.set_shader_parameter(&"tint", gl["tint"])
	if gl.has("opacity"):
		glass_mat.set_shader_parameter(&"opacity", gl["opacity"])
	wheel_mat = ShaderMaterial.new()
	wheel_mat.resource_name = "Wheel"
	wheel_mat.shader = shader("car_wheel")
	wheel_mat.set_shader_parameter(&"tread", tread_texture())
	lod_mat = ShaderMaterial.new()
	lod_mat.resource_name = "Lod"
	lod_mat.shader = shader("car_lod")
	_livery = int(spec.get("livery", 0))
	paint_mat.set_shader_parameter(&"livery", _livery)
	if spec.has("livery_color"):
		paint_mat.set_shader_parameter(&"livery_color", spec["livery_color"])
	if spec.has("livery_color2"):
		paint_mat.set_shader_parameter(&"livery_color2", spec["livery_color2"])


func _bind(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.layers = mi.layers | VehicleVisual.KEY_BIT | DynamicFill.FILL_BIT
	var mesh := mi.mesh
	if mesh == null:
		return
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_material(s)
		var nm := String(src.resource_name) if src != null else ""
		match nm:
			"Paint":
				mi.set_surface_override_material(s, paint_mat)
			"Details":
				mi.set_surface_override_material(s, details_mat)
			"Glass":
				mi.set_surface_override_material(s, glass_mat)
			"Lod":
				mi.set_surface_override_material(s, lod_mat)


## The materials that carry the shared damage state (dents, lost parts): every body surface.
func _body_mats() -> Array[ShaderMaterial]:
	return [paint_mat, details_mat, glass_mat]


# --- paint ------------------------------------------------------------------------------------------------------------------------------------------------

## The finish of a paint colour: a FINISH row when the colour is one of the street palette, else derived from the colour itself (every colour gets its own flake, metal and gloss).
static func finish_for(c: Color) -> Dictionary:
	var i := VehicleSpecs.COLORS.find(c)
	if i >= 0 and i < FINISH.size():
		return FINISH[i]
	var k := fposmod(c.h * 5.0 + c.v * 3.0, 1.0)
	return {"flake": lerpf(0.25, 0.6, k), "metal": lerpf(0.14, 0.42, k), "rough": lerpf(0.3, 0.2, k)}


func set_paint(color: Color) -> void:
	base_color = color
	finish = finish_for(color)
	var c := color * VehicleSpecs.PAINT_GAIN
	paint_mat.set_shader_parameter(&"paint", Color(c.r, c.g, c.b, 1.0))
	paint_mat.set_shader_parameter(&"flake", float(finish.get("flake", 0.4)))
	_metal = float(finish.get("metal", 0.3))
	_rough = float(finish.get("rough", 0.26))
	_pearl_col = finish.get("pearl_tint", Color(0.5, 0.3, 0.9)) as Color
	paint_mat.set_shader_parameter(&"metal", _metal)
	paint_mat.set_shader_parameter(&"rough", _rough)
	paint_mat.set_shader_parameter(&"pearl", float(finish.get("pearl", 0.0)))
	paint_mat.set_shader_parameter(&"pearl_tint", _pearl_col)
	paint_mat.set_shader_parameter(&"flake_tint", Color(1.0, 0.95, 0.85).lerp(color, 0.5))
	details_mat.set_shader_parameter(&"body_color", color)
	lod_mat.set_shader_parameter(&"paint", color)
	lod_mat.set_shader_parameter(&"metal", float(finish.get("metal", 0.3)))
	lod_mat.set_shader_parameter(&"rough", float(finish.get("rough", 0.26)) + 0.05)
	scuff = 0.0
	_apply_scuff()
	_apply_glow()


func get_paint() -> Color:
	return base_color


## The finish as numbers (what the shader makes of the uniforms: wear roughens and dulls the coat, rain glosses it). VehicleVisual.paint_state() returns the same keys for the older art.
func paint_state() -> Dictionary:
	var sc := scuff
	return {
		"roughness": clampf(_rough + sc * 0.4 - wet * 0.14, 0.08, 1.0),
		"metallic": _metal,
		"clearcoat": COAT * (1.0 - sc * 0.8),
		"specular": PAINT_SPECULAR,
		"glow": _glow * (1.0 - 0.6 * sc),
		"albedo": base_color.lerp(base_color * 0.35, sc * 0.65),
		"rim": PAINT_RIM,
		"emission": _pearl_col if _iridescent else base_color,
	}


func paint_value(nm: StringName) -> Variant:
	return paint_mat.get_shader_parameter(nm)


func set_dirt(d: float) -> void:
	dirt = clampf(d, 0.0, 1.0)
	paint_mat.set_shader_parameter(&"dirt", dirt)
	wheel_mat.set_shader_parameter(&"dirt", dirt)


## A decal pattern on the paint (CarV2 shader `livery`: 1 dual stripes, 2 side stripe, 3 checker band, 4 two-tone doors, 5 hood and roof stripe, 6 emergency band), 0 = none.
func set_livery(mode: int, c: Color = Color.WHITE) -> void:
	_livery = mode
	paint_mat.set_shader_parameter(&"livery", mode)
	paint_mat.set_shader_parameter(&"livery_color", c)


## What makes two cars of one model differ: road dirt (most cars are clean, a few filthy) and, on sporty kinds, racing stripes now and then. Called when a pooled car is put into play.
func randomize_look(rng: RandomNumberGenerator) -> void:
	var r := rng.randf()
	set_dirt(rng.randf_range(0.0, 0.15) if r < 0.55 else (rng.randf_range(0.2, 0.5) if r < 0.9 else rng.randf_range(0.6, 0.9)))
	var spec: Dictionary = VehicleSpecs.SPECS[_kind]
	if not spec.has("livery") and _kind in [&"sport", &"racer", &"muscle"]:
		if rng.randf() < 0.4:
			var cols: Array[Color] = [Color(0.92, 0.92, 0.94), Color(0.03, 0.03, 0.04), Color(0.9, 0.7, 0.15), Color(0.08, 0.5, 0.9)]
			set_livery(1 if rng.randf() < 0.7 else 5, cols[rng.randi() % cols.size()])
		else:
			set_livery(0)


func set_wet(w: float) -> void:
	wet = clampf(w, 0.0, 1.0)
	paint_mat.set_shader_parameter(&"wet", wet)
	glass_mat.set_shader_parameter(&"wet", wet)


func set_scuff(frac: float) -> void:
	scuff = clampf(frac, 0.0, 1.0)
	_apply_scuff()
	_apply_glow()


func _apply_scuff() -> void:
	paint_mat.set_shader_parameter(&"scuff", scuff)
	details_mat.set_shader_parameter(&"scuff", scuff)
	lod_mat.set_shader_parameter(&"scuff", scuff)


func _apply_glow() -> void:
	var g := _glow * (1.0 - 0.6 * scuff)
	paint_mat.set_shader_parameter(&"glow", g)
	lod_mat.set_shader_parameter(&"glow", g)


## A thin-film car (hover craft, Vael patrol): the pearl colour drifts with time and speed.
func set_iridescent(on: bool) -> void:
	_iridescent = on
	if on:
		_metal = 0.45
		_rough = 0.16
		paint_mat.set_shader_parameter(&"pearl", 0.75)
		paint_mat.set_shader_parameter(&"metal", _metal)
		paint_mat.set_shader_parameter(&"rough", _rough)


func shimmer(t: float, speed: float, phase: float) -> void:
	if not _iridescent:
		return
	var h := fposmod(base_color.h + 0.16 * sin(t * 0.9 + phase + absf(speed) * 0.05) + 0.08, 1.0)
	_pearl_col = Color.from_hsv(h, clampf(base_color.s + 0.35, 0.0, 1.0), clampf(base_color.v + 0.35, 0.0, 1.0))
	paint_mat.set_shader_parameter(&"pearl_tint", _pearl_col)
	paint_mat.set_shader_parameter(&"pearl", 0.55 + 0.25 * sin(t * 1.7 + phase))


# --- lamps and glass ----------------------------------------------------------------------------------------------------------------------------------------

## Headlights, tail lights (brake lights push it up), and the hover emitter / underglow, as the 0 .. 1+ factors VehicleVisual.set_lights passes.
func set_lights(head: float, tail: float, under: float) -> void:
	details_mat.set_shader_parameter(&"head", head)
	details_mat.set_shader_parameter(&"tail", tail)
	details_mat.set_shader_parameter(&"glow", under)
	lod_mat.set_shader_parameter(&"head", head)
	lod_mat.set_shader_parameter(&"tail", tail)


func set_glow(c: Color) -> void:
	details_mat.set_shader_parameter(&"glow_color", c)


const COOL_CABIN := [&"bus", &"ambulance", &"interceptor", &"truck", &"van", &"garbage"]   ## fluorescent white cabins; the rest glow warm


func set_interior_glow(g: float) -> void:
	glass_glow = g
	glass_mat.set_shader_parameter(&"interior", minf(g, 1.0))
	glass_mat.set_shader_parameter(&"interior_color", Color(0.78, 0.9, 1.0) if _kind in COOL_CABIN else Color(1.0, 0.85, 0.6))
	details_mat.set_shader_parameter(&"interior", g)


func set_indicator(on: bool) -> void:
	details_mat.set_shader_parameter(&"ind", 1.0 if on else 0.0)


func set_siren(phase: float, on: bool) -> void:
	_siren_on = on
	details_mat.set_shader_parameter(&"siren", phase)
	details_mat.set_shader_parameter(&"siren_on", 1.0 if on else 0.0)


func set_driver(on: bool) -> void:
	details_mat.set_shader_parameter(&"driver_on", 1.0 if on else 0.0)


func set_reverse(on: bool) -> void:
	details_mat.set_shader_parameter(&"reverse_lamp", 1.0 if on else 0.0)


# --- damage -------------------------------------------------------------------------------------------------------------------------------------------------

## A dent around `at` (model space) pushed along `dir` (horizontal, into the car) by an impact of damage fraction `frac`: the vertex stage of every body surface displaces the panel.
func add_dent(at: Vector3, dir: Vector3, frac: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < 1e-6:
		return
	dir = dir.normalized()
	var radius := lerpf(0.45, 1.15, clampf(frac * 1.6, 0.0, 1.0))
	var depth := lerpf(0.05, 0.27, clampf(frac * 1.8, 0.0, 1.0))
	var merged := false
	for dt in dents:
		if (dt["at"] as Vector3).distance_to(at) < DENT_MERGE:
			dt["d"] = minf(float(dt["d"]) + depth * 0.6, 0.34)
			dt["r"] = maxf(float(dt["r"]), radius)
			dt["dir"] = ((dt["dir"] as Vector3) + dir).normalized()
			merged = true
			break
	if not merged:
		if dents.size() >= MAX_DENTS:
			dents.remove_at(0)
		dents.append({"at": at, "dir": dir, "r": radius, "d": depth})
	_push_dents()


func _push_dents() -> void:
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	a.resize(MAX_DENTS)
	b.resize(MAX_DENTS)
	for i in dents.size():
		var dt: Dictionary = dents[i]
		var at: Vector3 = dt["at"]
		var d: Vector3 = dt["dir"]
		a[i] = Vector4(at.x, at.y, at.z, float(dt["r"]))
		b[i] = Vector4(d.x, d.y, d.z, float(dt["d"]))
	for m in _body_mats():
		m.set_shader_parameter(&"dent_a", a)
		m.set_shader_parameter(&"dent_b", b)
		m.set_shader_parameter(&"dent_n", dents.size())


func crack_glass(level: float, at: Vector3, spec_dims: Vector3) -> void:
	level = clampf(level, 0.0, 1.0)
	if level <= cracks + 0.02:
		return
	cracks = level
	var c := Vector3(0.0, spec_dims.y * 0.78, -spec_dims.z * 0.09)            # the windscreen first
	if absf(at.x) > spec_dims.x * 0.3 and level > 0.4:
		c = Vector3(signf(at.x) * spec_dims.x * 0.46, spec_dims.y * 0.72, 0.0)     # then the window on the side that took the hit
	elif at.z > spec_dims.z * 0.2 and level > 0.5:
		c = Vector3(0.0, spec_dims.y * 0.74, spec_dims.z * 0.26)                 # or the rear window
	glass_mat.set_shader_parameter(&"crack", cracks)
	glass_mat.set_shader_parameter(&"crack_at", Vector4(c.x, c.y, c.z, 0.55 + 0.3 * level))


## A body part is torn off (bumper, hood, trunk lid, a door): its vertices collapse on every surface (the dark engine bay or the cabin shows where it was).
func lose_part(part: StringName) -> bool:
	if not PART_BITS.has(part):
		return false
	var bit: int = 1 << int(PART_BITS[part])
	if parts_lost & bit != 0:
		return false
	parts_lost |= bit
	_push_parts()
	return true


func part_gone(part: StringName) -> bool:
	return PART_BITS.has(part) and (parts_lost & (1 << int(PART_BITS[part]))) != 0


func _push_parts() -> void:
	for m in _body_mats():
		m.set_shader_parameter(&"part_lost", float(parts_lost | parts_open))


## Which part a hit at `at` (model space) takes off, by where it landed: the bumper or the hood on a frontal hit, a door on the flank, the trunk lid or the rear bumper behind. Returns the part
## that was actually lost (a part that is already gone is skipped for the next candidate), or &"".
func tear_part_at(at: Vector3, dims: Vector3) -> StringName:
	var fz := at.z / maxf(dims.z, 0.1)                       # -0.5 at the nose .. +0.5 at the tail
	var low := at.y < dims.y * 0.42
	var order: Array = []
	if absf(at.x) > dims.x * 0.3 and absf(fz) < 0.3:
		order.assign([&"door_fr", &"door_rr"] if at.x > 0.0 else [&"door_fl", &"door_rl"])
	elif fz < -0.2:
		order.assign([&"bumper_f", &"hood"] if low else [&"hood", &"bumper_f"])
	elif fz > 0.2:
		order.assign([&"bumper_r", &"trunk"] if low else [&"trunk", &"bumper_r"])
	else:
		order.assign([&"hood", &"trunk"])
	for p: StringName in order:
		if lose_part(p):
			return p
	return &""


## A door swings: `side` > 0 the right one. The shell's own door is hidden while the door node (the same panel on a hinge) turns; false puts it back. Returns the door node or null.
func set_door_open(side: float, open: bool) -> Node3D:
	var key := "R" if side >= 0.0 else "L"
	var bit: int = 1 << (int(PART_BITS[&"door_fr"]) if key == "R" else int(PART_BITS[&"door_fl"]))
	var dn := doors.get(key) as Node3D
	if dn == null or (parts_lost & bit) != 0:
		return null
	if open:
		parts_open |= bit
	else:
		parts_open &= ~bit
	_push_parts()
	return dn


## Fire in the engine bay (a car below the fire threshold): the dark bay and the bare underside glow orange.
func set_burning(on: bool) -> void:
	burning = on
	details_mat.set_shader_parameter(&"fire", 1.0 if on else 0.0)


func repair() -> void:
	dents.clear()
	_push_dents()
	cracks = 0.0
	glass_mat.set_shader_parameter(&"crack", 0.0)
	parts_lost = 0
	parts_open = 0
	_push_parts()
	set_burning(false)
	for side in doors:
		(doors[side] as Node3D).visible = false
	scuff = 0.0
	_apply_scuff()
	_apply_glow()
