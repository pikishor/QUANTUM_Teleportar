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
const PAINT_GLOW := 0.15                    ## faint emission in the paint colour, so a car keeps its colour in the dark
const WHEEL_NAMES := [&"WheelFL", &"WheelFR", &"WheelRL", &"WheelRR"]

var model: Node3D
var body: MeshInstance3D
var wheels: Array[Node3D] = []              ## FL FR RL RR; steer = rotation.y of the front two, roll = rotation.x
var meshes: Array[MeshInstance3D] = []      ## every mesh of the model
var mirror_meshes: Array[MeshInstance3D] = []   ## what MirrorProxy tracks: the body only (the wheels are not worth their draw calls)
var uses_model := false
var wheel_radius := 0.335

var _body_mat: BaseMaterial3D
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
	model = Game.load_model(spec["model"])
	uses_model = model != null
	if model == null:
		model = _fallback(spec)
	body = model.get_node_or_null("Body") as MeshInstance3D
	for n: StringName in WHEEL_NAMES:
		var w := model.get_node_or_null(NodePath(n)) as Node3D
		if w != null:
			wheels.append(w)
	meshes = DynamicFill._meshes(model)
	DynamicFill.apply(model, glow)
	for mi in meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var mesh := mi.mesh
		if mesh == null:
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
	if body != null:
		mirror_meshes.append(body)
	set_lights(0.1, 0.35, 0.35)
	return model


## The paint: `color` times the lift DynamicFill gave the surface (so a dark vertex-coloured model still reads), only on the Body surface.
func set_paint(color: Color) -> void:
	if _body_mat == null:
		return
	var c := color * VehicleSpecs.PAINT_GAIN
	_body_mat.albedo_color = Color(c.r * _lift, c.g * _lift, c.b * _lift, 1.0)
	_body_mat.emission = color
	# metallic / roughness split: every colour gets its own finish (flake-heavy metallic, satin pearl, deep gloss) on top of the baked texture
	var k := fposmod(color.h * 5.0 + color.v * 3.0, 1.0)
	_body_mat.metallic = lerpf(0.55, BODY_METALLIC + 0.1, k)
	_body_mat.roughness = lerpf(BODY_ROUGHNESS, 0.6, k)
	_body_mat.clearcoat = lerpf(COAT, 1.0, k)


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
		wheels[i].rotation = Vector3(_roll, steer if i < 2 else 0.0, 0.0)


func set_wheels_visible(v: bool) -> void:
	if v == _wheels_shown:
		return
	_wheels_shown = v
	for w in wheels:
		w.visible = v


func wheels_visible() -> bool:
	return _wheels_shown


func set_shadow(on: bool) -> void:
	if body != null:
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
