class_name VehicleVisual
extends RefCounted
## The look of one car: the model (Game.load_model car_sedan / car_sport / car_suv, or primitives), its per-instance paint, the emissive lights and the wheels.
##
## No real lights per car: headlights, taillights and underglow are the models' own emissive surfaces (materials named Headlights / Taillights / Underglow),
## switched by scaling emission_energy_multiplier. The paint is the surface whose material is named Body, duplicated per instance by DynamicFill.apply
## (which also lifts the near-black legacy albedo) and then recoloured with set_surface_override_material. Models are never scaled.

const LIGHT_SURFACES := [&"Headlights", &"Taillights", &"Underglow"]
const BODY_METALLIC := 0.9                  ## factors on top of the baked ORM texture (paint = glossy low metal, chipped edges = bare metal): see set_paint for the per-car finish
const BODY_ROUGHNESS := 0.9
const COAT := 0.85                          ## clear coat strength / roughness: the wet sheen of lacquered paint under the neon
const COAT_ROUGHNESS := 0.07
const LAMP_GAIN := 0.6                      ## lamp surfaces are drawn additively (unshaded, vertex colour = soft falloff): albedo = colour x base energy x this x state
const PAINT_ROUGH_MAX := 0.5                 ## paint roughness range (was 0.9 .. 0.6: a flat matte red): low values let the neon street reflect in the lacquer
const PAINT_ROUGH_MIN := 0.22
const PAINT_RIM := 0.3                        ## grazing-angle sheen of every paint (material parameter, no extra draw)
const PAINT_GLOW := 0.2                    ## faint emission in the paint colour, so a car keeps its colour in the dark
const WHEEL_NAMES := [&"WheelFL", &"WheelFR", &"WheelRL", &"WheelRR"]
const BIKE_WHEEL_NAMES := [&"WheelF", &"WheelR"]    ## bikes: front (steers) and rear wheel; a hover craft has none
## LOD1: the new Wave 14 models ship a second, decimated body mesh ("Body_LOD1", about 30 % of the triangles, same UVs, materials and lamp surfaces, see tools/blender/lodlib.py).
## Body is shown up to LOD1_DIST metres from the camera, Body_LOD1 beyond (a hard switch with a small hysteresis margin, no fade pass). Both share the SAME per-instance materials,
## so the paint and the lamp colours follow. The older three cars have no LOD1 (the importer's own mesh LODs are all they use).
const LOD1_NAME := &"Body_LOD1"
const LOD1_DIST := 42.0
const LOD1_MARGIN := 3.0
## The three lamp surfaces (headlight, taillight and underglow halos, each its own additive material) are merged into ONE surface ("Lamps") with one tiny shader: the vertex alpha
## says which lamp a vertex belongs to, three colour uniforms carry the per-state colours. Two draw calls less per car (and per shadow-free pass), same look.
const LAMP_CODES := [0.1, 0.5, 0.9]                  ## vertex alpha of headlight / taillight / underglow vertices
const LAMP_SHADER_CODE := """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 head : source_color = vec3(0.0);
uniform vec3 tail : source_color = vec3(0.0);
uniform vec3 under : source_color = vec3(0.0);
varying float v_g;
void vertex() { v_g = COLOR.a; }
void fragment() {
	vec3 k = v_g < 0.3 ? head : (v_g < 0.7 ? tail : under);
	ALBEDO = COLOR.rgb * k;
	ALPHA = 1.0;
}
"""
static var _lamp_shader: Shader
static var _merged := {}                               ## source mesh key (resource_path, see _merge_lamps) -> ArrayMesh with the lamps merged (shared by every car of the model)

var model: Node3D
var body: MeshInstance3D
var wheels: Array[Node3D] = []              ## FL FR RL RR; steer = rotation.y of the front two, roll = rotation.x
var meshes: Array[MeshInstance3D] = []      ## every mesh of the model
var mirror_meshes: Array[MeshInstance3D] = []   ## what MirrorProxy tracks: the body only (the wheels are not worth their draw calls)
var uses_model := false
var model_name := ""                        ## the Game.load_model name that was used ("" = primitive fallback)
var body_lod1: MeshInstance3D               ## the decimated far body (null for models without LOD1)
var cls: StringName = &"car"
var _front: Array[bool] = []                ## per wheel: steers with the handlebars / front axle
var lights: Array[Light3D] = []             ## the model lights that were kept (the underglow omni), on only within PerfTiers.light_range() of the camera
var lights_on := true
var shadow_on := true                       ## the body currently casts a shadow (Vehicle.update_lod: only within PerfTiers.SHADOW_RANGE of the camera)
var wheel_radius := 0.335

var _body_mat: BaseMaterial3D
var _lamp_mat: ShaderMaterial                ## per-car instance of the merged lamp shader (null for the primitive fallback and models without the lamp surfaces)
var _lamp_idx := -1
var _lamp_idx1 := -1                         ## the merged lamp surface of the LOD1 mesh
var _kind: StringName = &""
var _shadow: MeshInstance3D                 ## shadow-only copy of the body without the lamp surfaces (ShadowProxy), null when the body has nothing to drop
var _lift := 1.0
var _mats: Array = [[], [], []]             ## per light kind: Array of BaseMaterial3D
var _cols: Array = [[], [], []]             ## per light kind: Array[Color] (the lamp colour)
var _base: Array = [[], [], []]             ## per light kind: Array[float] base emission energy
var _last := [-1.0, -1.0, -1.0]
var _roll := 0.0
var _wheels_shown := true


## Builds the model for `kind` (VehicleSpecs.SPECS key), readable at night, glow colour `glow`. Returns the root to add to the vehicle.
func build(kind: StringName, glow: Color) -> Node3D:
	var spec: Dictionary = VehicleSpecs.SPECS[kind]
	wheel_radius = spec["wheel"]
	_kind = kind
	cls = VehicleSpecs.cls_of(kind)
	model = null
	for mn in VehicleSpecs.model_names(kind):            # best model first; a missing one (not built yet) falls through to the next and finally to primitives
		model = Game.load_model(mn)
		if model != null:
			model_name = mn
			break
	uses_model = model != null
	if model == null:
		model = _fallback(spec)
	body = model.get_node_or_null("Body") as MeshInstance3D
	for n: StringName in WHEEL_NAMES + BIKE_WHEEL_NAMES:
		var w := model.get_node_or_null(NodePath(n)) as Node3D
		if w != null:
			wheels.append(w)
			_front.append(String(n).begins_with("WheelF"))
	var lamp_src := _merge_lamps(body)
	body_lod1 = model.get_node_or_null(NodePath(LOD1_NAME)) as MeshInstance3D
	if body_lod1 != null:
		var idx0 := _lamp_idx
		_lamp_idx = -1
		_merge_lamps(body_lod1)                            # the far mesh gets its own merged "Lamps" surface (same shader, same per-car material below)
		_lamp_idx1 = _lamp_idx
		_lamp_idx = idx0
	lights = DynamicFill.trim_lights(model, PackedStringArray(["UnderglowLight"]))      # the headlight spot and the car's own fill go (shared fill + emissive lamps); the underglow pool stays, within range
	meshes = DynamicFill._meshes(model)
	DynamicFill.apply(model, glow)
	for mi in meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var mesh := mi.mesh
		if mesh == null or mi == body_lod1:                # LOD1 takes the materials of the body (_link_lod1)
			continue
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s) as BaseMaterial3D
			var ov := mi.get_surface_override_material(s) as BaseMaterial3D
			if src == null or ov == null:
				continue
			var nm := StringName(src.resource_name)
			if nm == &"Body":
				_body_mat = ov
				ov.metallic = BODY_METALLIC
				ov.roughness = BODY_ROUGHNESS
				ov.clearcoat_enabled = true
				ov.clearcoat = COAT
				ov.clearcoat_roughness = COAT_ROUGHNESS
				ov.emission_enabled = true
				ov.emission_energy_multiplier = 0.12 if DynamicFill._is_compat() else PAINT_GLOW
				var a := src.albedo_color
				var b := ov.albedo_color
				_lift = (b.r + b.g + b.b) / maxf(a.r + a.g + a.b, 0.05)
			elif nm in LIGHT_SURFACES:
				var kind_i: int = LIGHT_SURFACES.find(nm)
				var col: Color = glow if kind_i == 2 else src.emission
				_make_lamp(ov)
				_mats[kind_i].append(ov)
				_cols[kind_i].append(col)
				_base[kind_i].append(maxf(src.emission_energy_multiplier, 1.0))
	if _lamp_idx >= 0:
		_lamp_mat = ShaderMaterial.new()
		_lamp_mat.resource_name = "Lamps"
		_lamp_mat.shader = _lamp_shader
		body.set_surface_override_material(_lamp_idx, _lamp_mat)
		for k in 3:
			for info: Array in lamp_src:
				if int(info[0]) == k:
					_cols[k].append(glow if k == 2 else info[1])
					_base[k].append(info[2])
	if body_lod1 != null and body != null:
		_link_lod1()
	if body != null:
		_shadow = ShadowProxy.static_proxy(body)        # the lamp glow surfaces would cast a shadow draw each, in every cascade
		mirror_meshes.append(_make_mirror_source(body))
	set_lights(0.1, 0.35, 0.35)
	return model


## Body_LOD1 shares the per-instance materials of Body (matched by the source material's name; its merged lamp surface gets the lamp shader material) and takes over beyond LOD1_DIST.
func _link_lod1() -> void:
	var m0 := body.mesh
	var m1 := body_lod1.mesh
	if m0 == null or m1 == null:
		return
	for s in m1.get_surface_count():
		if s == _lamp_idx1 and _lamp_mat != null:
			body_lod1.set_surface_override_material(s, _lamp_mat)
			continue
		var nm := StringName((m1.surface_get_material(s) as Material).resource_name) if m1.surface_get_material(s) != null else &""
		for t in m0.get_surface_count():
			var m := m0.surface_get_material(t)
			if t != _lamp_idx and m != null and StringName(m.resource_name) == nm:
				body_lod1.set_surface_override_material(s, body.get_surface_override_material(t))
				break
	body.visibility_range_end = LOD1_DIST
	body.visibility_range_end_margin = LOD1_MARGIN
	body_lod1.visibility_range_begin = LOD1_DIST
	body_lod1.visibility_range_begin_margin = LOD1_MARGIN
	body.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	body_lod1.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## Merge the Headlights / Taillights / Underglow surfaces of the body mesh into one "Lamps" surface (once per source mesh, shared). Returns [[kind, colour, base energy], ...] of the
## surfaces that were merged (read from their materials), or an empty array when the mesh has nothing to merge (the model then keeps its own lamp surfaces and materials).
func _merge_lamps(mi: MeshInstance3D) -> Array:
	var info: Array = []
	if mi == null or mi.mesh == null:
		return info
	var src := mi.mesh
	var lamp_of := {}                                    # surface index -> kind
	for s in src.get_surface_count():
		var m := src.surface_get_material(s) as BaseMaterial3D
		if m != null and StringName(m.resource_name) in LIGHT_SURFACES:
			lamp_of[s] = LIGHT_SURFACES.find(StringName(m.resource_name))
			info.append([lamp_of[s], m.emission, maxf(m.emission_energy_multiplier, 1.0)])
	if lamp_of.size() < 2:
		return []
	var key: Variant = src.resource_path if src.resource_path != "" else src.get_instance_id()     # the path, not the instance id: a reloaded model has new mesh objects (see ShadowProxy._shadow_mesh)
	var out: ArrayMesh = _merged.get(key)
	if out == null:
		if _lamp_shader == null:
			_lamp_shader = Shader.new()
			_lamp_shader.code = LAMP_SHADER_CODE
		var im := ImporterMesh.new()                     # the importer's own mesh builder: it also regenerates the LODs the merge would otherwise lose
		var verts := PackedVector3Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		for s in src.get_surface_count():
			if lamp_of.has(s):
				var arrays := src.surface_get_arrays(s)
				var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var c: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] is PackedColorArray else PackedColorArray()
				var base := verts.size()
				var code: float = LAMP_CODES[lamp_of[s]]
				for i in v.size():
					var col := c[i] if i < c.size() else Color.WHITE
					cols.append(Color(col.r, col.g, col.b, code))
				verts.append_array(v)
				var ii: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
				for i in ii.size():
					idx.append(ii[i] + base)
			else:
				im.add_surface(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s), [], {}, src.surface_get_material(s), String((src.surface_get_material(s) as Material).resource_name))
		var lamp_arrays := []
		lamp_arrays.resize(Mesh.ARRAY_MAX)
		lamp_arrays[Mesh.ARRAY_VERTEX] = verts
		var nrm := PackedVector3Array()
		nrm.resize(verts.size())
		nrm.fill(Vector3.UP)
		lamp_arrays[Mesh.ARRAY_NORMAL] = nrm
		lamp_arrays[Mesh.ARRAY_COLOR] = cols
		lamp_arrays[Mesh.ARRAY_INDEX] = idx
		var lm := ShaderMaterial.new()
		lm.resource_name = "Lamps"
		lm.shader = _lamp_shader
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, lamp_arrays, [], {}, lm, "Lamps")
		im.generate_lods(25.0, 60.0, [])
		out = im.get_mesh()
		_merged[key] = out
	mi.mesh = out
	_lamp_idx = out.get_surface_count() - 1
	return info


## What the street reflection copies: the body without its lamp / glow surfaces (their additive halos are not worth a draw call each in the mirror pass: 2 draws instead of 5 per
## car). An invisible-to-the-camera twin (render layers 0) of the body on the shadow mesh, carrying the body's own per-instance override materials (so the paint colour follows).
func _make_mirror_source(src: MeshInstance3D) -> MeshInstance3D:
	if _shadow == null:
		return src
	var keep := ShadowProxy.kept_surfaces(src.mesh)
	var twin := MeshInstance3D.new()
	twin.name = "MirrorSource"
	twin.mesh = _shadow.mesh
	twin.layers = 0
	twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	twin.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for k in keep.size():
		twin.set_surface_override_material(k, src.get_surface_override_material(keep[k]))
	src.add_child(twin)
	return twin


## The paint: `color` times the lift DynamicFill gave the surface (so a dark vertex-coloured model still reads), only on the Body surface.
func set_paint(color: Color) -> void:
	if _body_mat == null:
		return
	color = VehicleSpecs.paint_for(_kind, color)            # taxis, vans, trucks and Vael patrols wear their own palettes (a husk's colour passes through)
	var c := color * VehicleSpecs.PAINT_GAIN
	_body_mat.albedo_color = Color(c.r * _lift, c.g * _lift, c.b * _lift, 1.0)
	_body_mat.emission = color
	# metallic / roughness split: every colour gets its own finish (flake-heavy metallic, satin pearl, deep gloss) on top of the baked texture
	var k := fposmod(color.h * 5.0 + color.v * 3.0, 1.0)
	_body_mat.metallic = lerpf(0.55, BODY_METALLIC + 0.1, k)
	_body_mat.roughness = lerpf(PAINT_ROUGH_MAX, PAINT_ROUGH_MIN, k)
	_body_mat.clearcoat = lerpf(COAT, 1.0, k)
	_base_col = c
	damage_look = 0.0
	_flick = 0.0
	_setup_finish()


## --- quantum-realism finish (material parameters only: no extra draw call, no extra material) ---
const IRIS_KINDS := [&"hover", &"vael_patrol"]       ## thin-film iridescent sheen on the paint
const IRIS_SPAN := 0.16                               ## hue swing of the film
const FLICKER_CHANCE := 0.06                          ## share of cars that now and then flick to a second paint state
const FLICKER_EVERY := 7.0
const WEAR_ROUGH := 0.35                              ## roughness added at full damage
const SEAM_BELOW := 0.55                              ## damage fraction (0..1) from which phase-seam cracks glow
var iridescent := false
var flicker_car := false
var damage_look := 0.0
var wet_look := 0.0
var _base_col := Color.WHITE
var _phase := 0.0
var _flick := 0.0


## Called once per paint: thin-film cars get a rim sheen, a few cars carry a second state.
func _setup_finish() -> void:
	iridescent = _kind in IRIS_KINDS
	var _rng := RandomNumberGenerator.new()  # local, so global RNG streams stay untouched
	_rng.seed = hash(str(get_instance_id()))
	_phase = float(_rng.randi() % 1000) * 0.01
	flicker_car = (not iridescent) and _rng.randf() < FLICKER_CHANCE
	if _body_mat != null:
		_body_mat.rim_enabled = true
		_body_mat.rim = 0.7 if iridescent else PAINT_RIM
		_body_mat.rim_tint = 0.35 if iridescent else 0.6


## Thin-film shimmer: the hue of the film drifts with time and with how fast the car moves; a flicker car swaps to its second state for a blink.
func shimmer(t: float, speed: float) -> void:
	if _body_mat == null or not (iridescent or flicker_car):
		return
	var c := _base_col
	if iridescent:
		var h := fposmod(c.h + IRIS_SPAN * sin(t * 0.9 + _phase + absf(speed) * 0.05) + 0.08, 1.0)
		var film := Color.from_hsv(h, clampf(c.s + 0.35, 0.0, 1.0), clampf(c.v + 0.25, 0.0, 1.0))
		_body_mat.emission = film
		_body_mat.emission_energy_multiplier = (0.12 if DynamicFill._is_compat() else PAINT_GLOW) * (1.6 + 0.8 * sin(t * 1.7 + _phase))
		_body_mat.rim_tint = 0.2 + 0.3 * (0.5 + 0.5 * sin(t * 0.6 + _phase))
	else:
		var on := fposmod(t + _phase * 10.0, FLICKER_EVERY) < 0.18
		var f := 1.0 if on else 0.0
		if absf(f - _flick) > 0.5:
			_flick = f
			var alt := Color.from_hsv(fposmod(c.h + 0.5, 1.0), 0.6, 0.9) if on else c
			_body_mat.emission = alt
			_body_mat.emission_energy_multiplier = (0.12 if DynamicFill._is_compat() else PAINT_GLOW) * (4.0 if on else 1.0)


## Wear and damage decals as material state: scuffed clear coat, duller flake, soot, and glowing phase seams (emission) when hurt badly.
## `frac` = 0 sound .. 1 wrecked.
func set_damage_look(frac: float) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if _body_mat == null or absf(frac - damage_look) < 0.02:
		return
	damage_look = frac
	_apply_surface()
	if frac >= SEAM_BELOW and not iridescent:
		_body_mat.emission = Color(0.55, 0.9, 1.0)
		_body_mat.emission_energy_multiplier = 0.4 + 1.2 * (frac - SEAM_BELOW) / (1.0 - SEAM_BELOW)
	elif frac < SEAM_BELOW:
		_body_mat.emission = _base_col
		_body_mat.emission_energy_multiplier = 0.12 if DynamicFill._is_compat() else PAINT_GLOW


## Crash deformation, lite: the whole body crumples with the damage (lower, shorter, wider), no extra mesh, material or draw call. 0 restores the model.
const DEFORM := Vector3(0.03, -0.1, -0.07)
var deform := 0.0
var _deform_base := Vector3.ONE
var _deform_known := false


func set_deform(frac: float) -> void:
	if model == null:
		return
	frac = clampf(frac, 0.0, 1.0)
	if not _deform_known:
		_deform_known = true
		_deform_base = model.scale
	if absf(frac - deform) < 0.02 and frac > 0.0:
		return
	deform = frac
	model.scale = _deform_base * (Vector3.ONE + DEFORM * frac)


## Wet streets: a wet car is glossier (lower roughness, full clear coat). Follows the global `wetness`.
func set_wet(w: float) -> void:
	w = clampf(w, 0.0, 1.0)
	if _body_mat == null or absf(w - wet_look) < 0.03:
		return
	wet_look = w
	_apply_surface()


func _apply_surface() -> void:
	var k := fposmod(_base_col.h * 5.0 + _base_col.v * 3.0, 1.0)
	var r := lerpf(PAINT_ROUGH_MAX, PAINT_ROUGH_MIN, k)
	r = r + WEAR_ROUGH * damage_look - 0.28 * wet_look * (1.0 - damage_look)
	_body_mat.roughness = clampf(r, 0.12, 1.0)
	var cc := lerpf(COAT, 1.0, k)
	_body_mat.clearcoat = clampf(cc * (1.0 - 0.7 * damage_look) + 0.15 * wet_look, 0.0, 1.0)
	var soot := 1.0 - 0.45 * damage_look
	_body_mat.albedo_color = Color(_base_col.r * _lift * soot, _base_col.g * _lift * soot, _base_col.b * _lift * soot, 1.0)


func get_paint() -> Color:
	return _body_mat.albedo_color if _body_mat != null else Color.BLACK


func set_glow(color: Color) -> void:
	for i in _cols[2].size():
		_cols[2][i] = color
	_write_light(2, _last[2])


## Light factors (multipliers of the model's own emission): headlights, taillights, underglow. Only changes are written.
func set_lights(head: float, tail: float, under: float) -> void:
	_set_light(0, head)
	_set_light(1, tail)
	_set_light(2, under)


func _set_light(k: int, f: float) -> void:
	if absf(f - float(_last[k])) < 0.01:
		return
	_last[k] = f
	_write_light(k, f)


func _write_light(k: int, f: float) -> void:
	if _lamp_mat != null:                                # merged lamps: one colour uniform per lamp kind
		var cols: Array = _cols[k]
		if not cols.is_empty():
			var c: Color = cols[0]
			var e: float = float((_base[k] as Array)[0]) * LAMP_GAIN * maxf(f, 0.0) * (0.4 if DynamicFill._is_compat() else 1.0)
			_lamp_mat.set_shader_parameter([&"head", &"tail", &"under"][k], Color(c.r * e, c.g * e, c.b * e, 1.0))
		return
	var mats: Array = _mats[k]
	var bases: Array = _base[k]
	var cols: Array = _cols[k]
	var g: float = LAMP_GAIN * maxf(f, 0.0) * (0.4 if DynamicFill._is_compat() else 1.0)      # the Compatibility renderer shows additive pools much hotter
	for i in mats.size():
		var c: Color = cols[i]
		var e: float = float(bases[i]) * g
		(mats[i] as BaseMaterial3D).albedo_color = Color(c.r * e, c.g * e, c.b * e, 1.0)


## A lamp surface: unshaded, additive, double sided, vertex colours (the baked halo and light-pool falloff) multiply the colour. Lens boxes are white
## vertex colours (full colour), the halos / road pools fall off to black, so they blend into the wet road without any real light.
static func _make_lamp(m: BaseMaterial3D) -> void:
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = null
	m.emission_enabled = false
	m.rim_enabled = false
	m.normal_enabled = false
	m.roughness_texture = null
	m.metallic_texture = null


func light_factor(kind_i: int) -> float:
	return _last[kind_i]


## Roll the wheels by `dist` metres of travel and steer the front pair by `steer` radians.
func spin(dist: float, steer: float) -> void:
	if wheels.is_empty() or not _wheels_shown:
		return
	_roll = fposmod(_roll - dist / wheel_radius, TAU)
	for i in wheels.size():
		wheels[i].rotation = Vector3(_roll, steer if _front[i] else 0.0, 0.0)


func set_wheels_visible(v: bool) -> void:
	if v == _wheels_shown:
		return
	_wheels_shown = v
	for w in wheels:
		w.visible = v


func wheels_visible() -> bool:
	return _wheels_shown


func set_model_lights(on: bool) -> void:
	if on != lights_on:
		lights_on = on
		DynamicFill.set_lights_visible(lights, on)


func set_shadow(on: bool) -> void:
	shadow_on = on
	ShadowProxy.set_enabled(body, _shadow, on)


## Primitive car: a hull, a cabin, four wheels and emissive light strips, with the same node and material names as the real models.
func _fallback(spec: Dictionary) -> Node3D:
	var ln: float = spec["len"]
	var wid: float = spec["wid"]
	var hgt: float = spec["hgt"]
	var r: float = spec["wheel"]
	var root := Node3D.new()
	root.name = String(spec["model"])
	var hull := MeshInstance3D.new()
	hull.name = "Body"
	var hm := BoxMesh.new()
	hm.size = Vector3(wid, hgt * 0.42, ln)
	hm.material = _mat("Body", Color(0.8, 0.8, 0.8), 0.6, 0.4)
	hull.mesh = hm
	hull.position = Vector3(0.0, r + hgt * 0.26, 0.0)
	root.add_child(hull)
	var cabin := MeshInstance3D.new()
	cabin.name = "Cabin"
	var cm := BoxMesh.new()
	cm.size = Vector3(wid * 0.86, hgt * 0.34, ln * 0.5)
	cm.material = _mat("Glass", Color(0.08, 0.1, 0.14), 0.2, 0.3)
	cabin.mesh = cm
	hull.add_child(cabin)
	cabin.position = Vector3(0.0, hgt * 0.38, ln * 0.06)
	_strip(hull, "Headlights", Vector3(wid * 0.8, 0.12, 0.06), Vector3(0.0, hgt * 0.05, -ln * 0.5), Color(1.0, 0.94, 0.8), 7.0)
	_strip(hull, "Taillights", Vector3(wid * 0.8, 0.1, 0.06), Vector3(0.0, hgt * 0.05, ln * 0.5), Color(1.0, 0.06, 0.12), 5.0)
	_strip(hull, "Underglow", Vector3(wid * 0.9, 0.04, ln * 0.8), Vector3(0.0, -hgt * 0.21 - r * 0.5, 0.0), Color(1.0, 0.18, 0.84), 4.0)
	var axle := ln * 0.3
	var spec_cls := StringName(spec.get("cls", &"car"))
	if spec_cls == &"hover":                         # no wheels: a flat hull on an underglow pool
		cabin.position.y = hgt * 0.3
		return root
	if spec_cls == &"bike":                          # two wheels on the centre line, a narrow hull
		hm.size = Vector3(wid * 0.55, hgt * 0.3, ln * 0.62)
		cm.size = Vector3(wid * 0.45, hgt * 0.3, ln * 0.25)
		for j in 2:
			var bw := Node3D.new()
			bw.name = String(BIKE_WHEEL_NAMES[j])
			var bmi := MeshInstance3D.new()
			var bc := CylinderMesh.new()
			bc.top_radius = r
			bc.bottom_radius = r
			bc.height = 0.16
			bc.radial_segments = 14
			bc.rings = 1
			bc.material = _mat("Wheel", Color(0.06, 0.06, 0.07), 0.2, 0.7)
			bmi.mesh = bc
			bmi.rotation = Vector3(0.0, 0.0, PI * 0.5)
			bw.add_child(bmi)
			bw.position = Vector3(0.0, r, -ln * 0.36 if j == 0 else ln * 0.36)
			root.add_child(bw)
		return root
	for i in 4:
		var w := Node3D.new()
		w.name = String(WHEEL_NAMES[i])
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = r
		cyl.bottom_radius = r
		cyl.height = 0.26
		cyl.radial_segments = 14
		cyl.rings = 1
		cyl.material = _mat("Wheel", Color(0.06, 0.06, 0.07), 0.2, 0.7)
		mi.mesh = cyl
		mi.rotation = Vector3(0.0, 0.0, PI * 0.5)
		w.add_child(mi)
		w.position = Vector3(-(wid * 0.5 - 0.12) if i % 2 == 0 else (wid * 0.5 - 0.12), r, -axle if i < 2 else axle)
		root.add_child(w)
	return root


func _strip(parent: Node3D, nm: String, size: Vector3, pos: Vector3, color: Color, energy: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = size
	var m := _mat(nm, Color.BLACK, 0.0, 0.5)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)


static func _mat(nm: String, color: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = nm
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	return m
