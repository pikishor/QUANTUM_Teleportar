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
## Lacquer is a dielectric under a clear coat: a high metallic factor made the paint a mirror of the dark sky radiance (one flat purple / red blob at night, no shading, no highlights).
## Low metal keeps the diffuse colour lit by the street lights; the clear coat adds the gloss.
const PAINT_SPECULAR := 0.9                   ## dielectric specular of the lacquer (default 0.5): street lamps and neon leave a visible highlight
const PAINT_METAL_MIN := 0.12
const PAINT_METAL_MAX := 0.4
const PAINT_RIM := 0.6                       ## grazing-angle sheen of every paint (material parameter, no extra draw)
const PAINT_GLOW := 0.12                   ## emission in the paint colour, so a car keeps its colour and its shape in the dark (0.2 made the cars read as emissive clay next to the key light: round 6, second pass)
const PAINT_GLOW_LOW := 0.18               ## LOW has no fill light: the paint carries more of its own light
const PAINT_GLOW_COMPAT := 0.34            ## the compatibility renderer lights the paint less, so it needs less of the lift


static func paint_glow() -> float:
	if DynamicFill._is_compat():
		return PAINT_GLOW_COMPAT
	return PAINT_GLOW_LOW if Game.quality <= 0 else PAINT_GLOW


## The cars' own key light: ONE shared directional light that lights only the cars (their meshes are on KEY_LAYER too), from the side and above relative to the camera, so a car
## has a lit and a shaded side instead of the flat look the camera-facing fill gives (no shadows, one light for every car, any tier).
const KEY_LAYER := 18
const KEY_BIT := 1 << (KEY_LAYER - 1)
const KEY_ENERGY := 2.2
const KEY_YAW := 0.95                         ## rad from the camera heading
const KEY_PITCH := -40.0
static var _key: DirectionalLight3D


static func ensure_key_light(parent: Node) -> DirectionalLight3D:
	if is_instance_valid(_key) and _key.is_inside_tree():
		return _key
	var l := DirectionalLight3D.new()
	l.name = "VehicleKeyLight"
	l.light_cull_mask = KEY_BIT
	l.shadow_enabled = false
	l.light_color = Color(1.0, 0.93, 0.88)
	l.light_energy = KEY_ENERGY * (0.55 if DynamicFill._is_compat() else 1.0)
	l.light_specular = 1.0
	l.rotation_degrees = Vector3(KEY_PITCH, 0.0, 0.0)
	parent.add_child(l)
	_key = l
	return l


static func aim_key(cam_yaw: float) -> void:
	if is_instance_valid(_key):
		_key.rotation = Vector3(deg_to_rad(KEY_PITCH), cam_yaw + KEY_YAW, 0.0)


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
uniform vec3 pool = vec3(0.0, 0.0, 0.12);       // gain of the glow that lies on the road (headlight and taillight pools, the underglow disc): flat translucent patches read as a toy
uniform float halo = 0.3;                     // gain of the soft halos round the lamps (the lens boxes themselves stay at full strength)
uniform float ground = 0.08;                   // vertices lower than this (model space) are road glow; < 0 = a hover craft, nothing is classified as road glow
varying float v_g;
varying float v_road;
void vertex() {
	v_g = COLOR.a;
	v_road = VERTEX.y < ground ? 1.0 : 0.0;
}
void fragment() {
	vec3 k = v_g < 0.3 ? head : (v_g < 0.7 ? tail : under);
	float pk = v_g < 0.3 ? pool.x : (v_g < 0.7 ? pool.y : pool.z);
	float lens = step(0.95, max(COLOR.r, max(COLOR.g, COLOR.b)));
	float g = mix(1.0, pk, v_road) * mix(halo, 1.0, lens);
	ALBEDO = COLOR.rgb * k * g;
	ALPHA = 1.0;
}
"""
static var _lamp_shader: Shader
static var _merged := {}                               ## source mesh key (resource_path, see _merge_lamps) -> ArrayMesh with the lamps merged (shared by every car of the model)

var v2: CarV2                               ## the Cars v2 runtime (cv2_* models: shader materials, GPU dents, cracks, torn-off parts); null for the older art and the primitive fallback
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
var parts: Dictionary = {}                  ## roster craft: animated nodes by name (Rotor, TailRotor, Prop, Turret) and their blur discs (RotorDisc ...)

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
	if model != null and model_name.begins_with("cv2_"):
		var v2_root := _build_v2(spec, glow)
		if v2_root != null:
			return v2_root
		model.free()                                          # not a usable v2 model: the older art or the primitives take over
		model = null
		uses_model = false
		for mn in VehicleSpecs.model_names(kind):
			if not mn.begins_with("cv2_"):
				model = Game.load_model(mn)
				if model != null:
					model_name = mn
					uses_model = true
					break
	if model == null:
		model = _fallback(spec)
	if bool(spec.get("armour", false)):                  # the armoured truck: plates, bull bar and a turret ring on the van body (before the surfaces are processed)
		VehicleCraftModels.dress_armoured(model, spec)
	body = model.get_node_or_null("Body") as MeshInstance3D
	for n: StringName in WHEEL_NAMES + BIKE_WHEEL_NAMES:
		var w := model.get_node_or_null(NodePath(n)) as Node3D
		if w != null:
			wheels.append(w)
			_front.append(String(n).begins_with("WheelF"))
	if kind == &"hoverbike":                              # a quantum cushion, no wheels: the bike model's wheels are hidden for good
		for w in wheels:
			w.visible = false
		wheels.clear()
		_front.clear()
	body_lod1 = model.get_node_or_null(NodePath(LOD1_NAME)) as MeshInstance3D
	if cls == &"car" and body != null and bool(spec.get("parts", true)):         # windows split off the dark "Details" surface: tinted glass that reflects the sky and glows from inside at night
		var hgt := float(spec["hgt"])
		CarParts.split_glass(body, hgt)
		if body_lod1 != null:
			CarParts.split_glass(body_lod1, hgt)
	var lamp_src := _merge_lamps(body)
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
		mi.layers = mi.layers | KEY_BIT
		var mesh := mi.mesh
		if mesh == null or mi == body_lod1:                # LOD1 takes the materials of the body (_link_lod1)
			continue
		for s in mesh.get_surface_count():
			var src := mesh.surface_get_material(s) as BaseMaterial3D
			var ov := mi.get_surface_override_material(s) as BaseMaterial3D
			if src == null or ov == null:
				continue
			var nm := StringName(src.resource_name)
			if nm == &"Body" and (body == null or mi == body):       # a rotor, a turret: their "Body" surface takes the hull's paint material later (_bind_craft)
				_body_mat = ov
				ov.metallic = BODY_METALLIC
				ov.roughness = BODY_ROUGHNESS
				ov.clearcoat_enabled = true
				ov.clearcoat = COAT
				ov.clearcoat_roughness = COAT_ROUGHNESS
				ov.emission_enabled = true
				ov.emission_energy_multiplier = paint_glow()
				ov.metallic_specular = PAINT_SPECULAR
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
	if cls == &"car" and body != null and bool(spec.get("parts", true)):
		_finish_car(spec)
	if bool(spec.get("craft", false)):
		_bind_craft(spec)
	if body_lod1 != null and body != null:
		_link_lod1()
	if body != null:
		_shadow = ShadowProxy.static_proxy(body)        # the lamp glow surfaces would cast a shadow draw each, in every cascade
		mirror_meshes.append(_make_mirror_source(body))
	set_lights(0.1, 0.35, 0.35)
	return model


## The Cars v2 path of build(): the model is a cv2_* glb (CarV2 dresses it). Fills the same members the older art does (body, body_lod1, wheels, meshes, mirror_meshes, plates, beams, shadow proxy).
func _build_v2(spec: Dictionary, glow: Color) -> Node3D:
	var c2 := CarV2.new()
	if not c2.setup(self, model, _kind, glow):
		return null
	v2 = c2
	body = c2.body
	body_lod1 = c2.lod1
	for n: StringName in WHEEL_NAMES:
		var w := model.get_node_or_null(NodePath(n)) as Node3D
		if w != null:
			wheels.append(w)
			_front.append(String(n).begins_with("WheelF"))
	meshes = [body]
	for extra: MeshInstance3D in [c2.lod1, c2.lod2]:
		if extra != null:
			meshes.append(extra)
	var ln: float = spec["len"]
	var wid: float = spec["wid"]
	var hgt: float = spec["hgt"]
	_dims = Vector3(wid, hgt, ln)
	if cls == &"car":
		_plate_n += 1
		c2.set_plate_seed(float(_plate_n) * 7.31 + 3.0)                  # the plates are part of the Details surface now (no quad, no texture, two draws fewer): the seed makes the number
	_add_beams(wid, hgt, ln)
	if c2.lod2 != null:
		_shadow = MeshInstance3D.new()                          # the 400 triangle car is the shadow caster, drawn only into the shadow maps
		_shadow.name = ShadowProxy.PROXY_NAME
		_shadow.mesh = c2.lod2.mesh
		_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_shadow.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_shadow.layers = body.layers
		body.add_child(_shadow)
		var twin := MeshInstance3D.new()                        # what the wet street reflects: the same small mesh, on no render layer
		twin.name = "MirrorSource"
		twin.mesh = c2.lod2.mesh
		twin.layers = 0
		twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		twin.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		twin.set_surface_override_material(0, c2.lod_mat)
		body.add_child(twin)
		mirror_meshes.append(twin)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if spec.get("driver", true) == false:
		c2.set_driver(false)
	set_lights(0.1, 0.35, 0.35)
	return model


func _add_beams(wid: float, hgt: float, ln: float) -> void:
	_beams = MeshInstance3D.new()
	_beams.name = "Beams"
	_beams.mesh = CarParts.beam_mesh(wid * 0.3, clampf(hgt * 0.4, 0.5, 0.95))
	_beams.material_override = CarParts.beam_material()
	_beams.position = Vector3(0.0, 0.0, -ln * 0.5 + 0.25)
	_beams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beams.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_beams.visibility_range_end = 80.0
	_beams.visibility_range_end_margin = 6.0
	model.add_child(_beams)
	_write_beam(0.1)


## The roster craft (helicopter, plane, boat, tank): the animated nodes are found by name, their paint surface shares the hull's paint material, the glass gets the car glass, and the rotors
## get a blur disc each (VehicleCraft shows it above a spin speed).
func _bind_craft(spec: Dictionary) -> void:
	for nm: String in ["Rotor", "TailRotor", "Prop", "Turret"]:
		var n := model.get_node_or_null(NodePath(nm)) as Node3D
		if n != null:
			parts[nm] = n
	if bool(spec.get("burner", false)):                                 # a jet's afterburner cone (VehicleCraft.sync lights it with the throttle)
		AircraftModels.add_burner(model, spec)
		parts["Burner"] = model.get_node_or_null("Burner")
	if body != null:
		for s in body.mesh.get_surface_count():
			var m := body.mesh.surface_get_material(s)
			var nm := m.resource_name if m != null else ""
			if nm == "Glass":
				body.set_surface_override_material(s, CarParts.glass_material())
	for nm: String in parts:
		var mi := parts[nm] as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mi.layers = mi.layers | KEY_BIT
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m != null and m.resource_name == "Body" and _body_mat != null:
				mi.set_surface_override_material(s, _body_mat)             # the turret wears the hull paint
	var disc_for := {"Rotor": "rotor_r", "Prop": "prop_r"}
	for nm: String in disc_for:
		if parts.has(nm):
			var r := float(spec.get(disc_for[nm], 1.3 if nm == "Prop" else 3.6))
			var d := VehicleCraftModels.disc(r, 0.08)
			d.name = nm + "Disc"
			model.add_child(d)
			d.position = (parts[nm] as Node3D).position
			if nm == "Prop":
				d.rotation = Vector3(PI * 0.5, 0.0, 0.0)               # the prop turns about the nose axis (Z)
			parts[nm + "Disc"] = d


const INTERIOR_GLOW := {&"taxi": 1.0, &"bus": 1.5, &"ambulance": 1.2, &"interceptor": 0.7, &"van": 0.2, &"truck": 0.2, &"garbage": 0.2}
const INTERIOR_BASE := 0.14                           ## cabin light behind the glass at night (a dashboard and a courtesy lamp), scaled per kind above
static var _plate_n := 0

var _glass_mat: StandardMaterial3D                    ## per-car copy of the shared glass (the interior glow follows this car's lights)
var _beams: MeshInstance3D
var plates: Array[MeshInstance3D] = []


## Real wheels, glass material, licence plates and the headlight beams of a four-wheeled car (see CarParts). Called once from build().
func _finish_car(spec: Dictionary) -> void:
	var r: float = spec["wheel"]
	var w := clampf(r * 0.62, 0.2, 0.3)
	CarParts.upgrade_wheels(model, r, w)
	var gi := -1
	for t in body.mesh.get_surface_count():
		var m := body.mesh.surface_get_material(t)
		if m != null and m.resource_name == "Glass":
			gi = t
	if gi >= 0:
		_glass_mat = CarParts.glass_material().duplicate() as StandardMaterial3D
		body.set_surface_override_material(gi, _glass_mat)
	var ln: float = spec["len"]
	var wid: float = spec["wid"]
	var hgt: float = spec["hgt"]
	_dims = Vector3(wid, hgt, ln)
	_plate_n += 1
	plates = CarParts.add_plates(model, AABB(Vector3(-wid * 0.5, 0.0, -ln * 0.5), Vector3(wid, hgt, ln)), _plate_n, clampf(hgt * 0.36, 0.42, 0.62))
	for p in plates:
		p.layers = p.layers | KEY_BIT
	_add_beams(wid, hgt, ln)


var _dims := Vector3(1.9, 1.4, 4.6)                   ## width, height, length of the car (for the door)
var _door: Node3D
var _door_tw: Tween
var door_cycles := 0                                  ## doors swung so far (tests wait on this)


## The door on `side` (+1 right, -1 left) swings open, stays open for `hold` s and shuts: played when the hero gets in or out (and when a driver is pulled out). One pooled panel + window
## strip per car, built on first use, hidden while shut. Only four-wheeled cars have one.
func door_cycle(side: float, hold := 0.75) -> void:
	if cls != &"car" or model == null or not model.is_inside_tree():
		return
	if v2 != null:
		var dn := v2.set_door_open(side, true)                         # the shell's door hides, the same panel on its hinge swings
		door_cycles += 1
		if dn == null:
			return
		if _door_tw != null and _door_tw.is_valid():
			_door_tw.kill()
			_close_v2_doors()
		_door = dn
		var sd2 := 1.0 if side >= 0.0 else -1.0
		dn.rotation = Vector3.ZERO
		dn.visible = true
		_door_tw = model.create_tween()
		_door_tw.tween_property(dn, "rotation:y", sd2 * 1.15, 0.17).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_door_tw.tween_interval(hold)
		_door_tw.tween_property(dn, "rotation:y", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_door_tw.tween_callback(func() -> void:
			dn.visible = false
			v2.set_door_open(side, false))
		return
	if _door == null:
		_door = Node3D.new()
		_door.name = "DoorSwing"
		var panel := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, _dims.y * 0.4, _dims.z * 0.27)
		panel.mesh = bm
		panel.position = Vector3(0.0, 0.0, _dims.z * 0.135)
		panel.material_override = _body_mat
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.045, _dims.y * 0.22, _dims.z * 0.24)
		strip.mesh = sm
		strip.position = Vector3(0.0, _dims.y * 0.31, _dims.z * 0.12)
		strip.material_override = CarParts.glass_material()
		for m: MeshInstance3D in [panel, strip]:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			m.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			m.layers = m.layers | KEY_BIT
			_door.add_child(m)
		_door.visible = false
		model.add_child(_door)
	if _door_tw != null and _door_tw.is_valid():
		_door_tw.kill()
	var sd := 1.0 if side >= 0.0 else -1.0
	_door.position = Vector3(sd * (_dims.x * 0.5 + 0.02), _dims.y * 0.42, -_dims.z * 0.12)
	_door.rotation = Vector3.ZERO
	_door.visible = true
	door_cycles += 1
	_door_tw = model.create_tween()
	_door_tw.tween_property(_door, "rotation:y", sd * 1.15, 0.17).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_door_tw.tween_interval(hold)
	_door_tw.tween_property(_door, "rotation:y", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_door_tw.tween_callback(func() -> void: _door.visible = false)


func _close_v2_doors() -> void:
	for key: String in v2.doors:
		var dn := v2.doors[key] as Node3D
		dn.visible = false
		v2.set_door_open(1.0 if key == "R" else -1.0, false)


## Cars v2: a fresh random look for a pooled car going into play (road dirt, racing stripes on sporty kinds). The older art has none.
func randomize_look(rng: RandomNumberGenerator) -> void:
	if v2 != null:
		v2.randomize_look(rng)


## A hit tears a body part off (Cars v2: bumper, hood, trunk lid, door): returns the part's name, or &"" for the older art and when nothing was left to tear.
func tear_part_at(at: Vector3) -> StringName:
	if v2 == null:
		return &""
	return v2.tear_part_at(at, _dims)


func part_gone(part: StringName) -> bool:
	return v2 != null and v2.part_gone(part)


## The car is on fire (hull below the fire threshold): the engine bay glows.
func set_burning(on: bool) -> void:
	if v2 != null:
		v2.set_burning(on)


func _write_beam(f: float) -> void:
	if _beams != null:
		_beams.set_instance_shader_parameter(&"k", clampf(f, 0.0, 2.0))
		_beams.visible = f > 0.2                       # lamps off (day): the cone adds about 0.003 of light, so it is not drawn at all (one draw call per car in view, wave 111 perf)
	if v2 != null:
		v2.set_interior_glow(clampf(f - 0.3, 0.0, 1.0) * float(INTERIOR_GLOW.get(_kind, 0.08)) * 1.2)
	elif _glass_mat != null:
		var g: float = INTERIOR_GLOW.get(_kind, 0.35)
		_glass_mat.emission_energy_multiplier = clampf(f - 0.3, 0.0, 1.0) * INTERIOR_BASE * g


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
	if v2 != null:
		color = VehicleSpecs.paint_for(_kind, color)
		v2.set_paint(color)
		_base_col = color * VehicleSpecs.PAINT_GAIN
		damage_look = 0.0
		_flick = 0.0
		_setup_finish()
		return
	if _body_mat == null:
		return
	color = VehicleSpecs.paint_for(_kind, color)            # taxis, vans, trucks and Vael patrols wear their own palettes (a husk's colour passes through)
	var c := color * VehicleSpecs.PAINT_GAIN
	_body_mat.albedo_color = Color(c.r * _lift, c.g * _lift, c.b * _lift, 1.0)
	_body_mat.emission = color
	# metallic / roughness split: every colour gets its own finish (flake-heavy metallic, satin pearl, deep gloss) on top of the baked texture
	var k := fposmod(color.h * 5.0 + color.v * 3.0, 1.0)
	_body_mat.metallic = lerpf(PAINT_METAL_MIN, PAINT_METAL_MAX, k)
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
	if v2 != null:
		v2.set_iridescent(iridescent)
		return
	if _body_mat != null:
		_body_mat.rim_enabled = true
		_body_mat.rim = 0.7 if iridescent else PAINT_RIM
		_body_mat.rim_tint = 0.35 if iridescent else 0.6


## Thin-film shimmer: the hue of the film drifts with time and with how fast the car moves; a flicker car swaps to its second state for a blink.
func shimmer(t: float, speed: float) -> void:
	if v2 != null:
		if iridescent:
			v2.shimmer(t, speed, _phase)
		return
	if _body_mat == null or not (iridescent or flicker_car):
		return
	var c := _base_col
	if iridescent:
		var h := fposmod(c.h + IRIS_SPAN * sin(t * 0.9 + _phase + absf(speed) * 0.05) + 0.08, 1.0)
		var film := Color.from_hsv(h, clampf(c.s + 0.35, 0.0, 1.0), clampf(c.v + 0.25, 0.0, 1.0))
		_body_mat.emission = film
		_body_mat.emission_energy_multiplier = paint_glow() * (1.6 + 0.8 * sin(t * 1.7 + _phase))
		_body_mat.rim_tint = 0.2 + 0.3 * (0.5 + 0.5 * sin(t * 0.6 + _phase))
	else:
		var on := fposmod(t + _phase * 10.0, FLICKER_EVERY) < 0.18
		var f := 1.0 if on else 0.0
		if absf(f - _flick) > 0.5:
			_flick = f
			var alt := Color.from_hsv(fposmod(c.h + 0.5, 1.0), 0.6, 0.9) if on else c
			_body_mat.emission = alt
			_body_mat.emission_energy_multiplier = paint_glow() * (4.0 if on else 1.0)


## Wear and damage as material state: scuffed clear coat, duller flake, soot (the paint darkens as the hull goes). `frac` = 0 sound .. 1 wrecked. No glow: a hurt car is dirty, not neon.
func set_damage_look(frac: float) -> void:
	frac = clampf(frac, 0.0, 1.0)
	if v2 != null:
		if absf(frac - damage_look) >= 0.02:
			damage_look = frac
			v2.set_scuff(frac)
		return
	if _body_mat == null or absf(frac - damage_look) < 0.02:
		return
	damage_look = frac
	_apply_surface()
	if not iridescent:
		_body_mat.emission = _base_col
		_body_mat.emission_energy_multiplier = paint_glow() * (1.0 - 0.6 * frac)


## Lopsided sag of a badly hurt car (a few centimetres lower, a little off level): no scaling of the model, the dents carry the shape. 0 restores it.
var deform := 0.0


func set_deform(frac: float) -> void:
	deform = clampf(frac, 0.0, 1.0)


# --- crash damage: dents in the panels, cracked windows -----------------------------------------------------------------------------------------------------
const MAX_DENTS := 7
const DENT_MERGE := 0.55                      ## an impact this close (m) to an older dent deepens that dent instead of making a new one
const GLASS_TEX := 128
static var _crack_tex: ImageTexture
var dents: Array[Dictionary] = []             ## {at: Vector3, dir: Vector3 (the way the panel is pushed, into the car), r: radius m, d: depth m}
var cracks := 0.0                             ## 0..1 how much of the glass is cracked
var _orig_mesh: Mesh
var _src_arrays: Array = []                   ## per surface: the undented arrays of the body mesh (read once, on the first dent)
var _crack_mi: MeshInstance3D
var _crack_seed := 0


## Dent the panels around `at` (model space, metres) pushed along `dir` (horizontal, into the car), by an impact of damage fraction `frac` (0..1 of a hull): a smooth crater
## with a crumpled rim on the surfaces that face the impact, with the normals tilted so the light shows it. Rebuilds the body mesh once (a car has its own copy while dented);
## nothing runs per frame. Up to MAX_DENTS dents, close ones deepen each other.
func add_dent(at: Vector3, dir: Vector3, frac: float) -> void:
	if v2 != null:
		if frac >= VehicleSpecs.DENT_MIN:
			v2.add_dent(at, dir, frac)
			dents = v2.dents
		return
	if body == null or body.mesh == null or frac < VehicleSpecs.DENT_MIN:
		return
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
	_rebuild_dents()


func _rebuild_dents() -> void:
	if _orig_mesh == null:
		_orig_mesh = body.mesh
		for s in _orig_mesh.get_surface_count():
			_src_arrays.append(_orig_mesh.surface_get_arrays(s))
	var out := ArrayMesh.new()
	for s in _src_arrays.size():
		var arrays: Array = (_src_arrays[s] as Array).duplicate()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array else PackedVector3Array()
		var has_n := nrm.size() == verts.size()
		var vcount := verts.size()
		for dt in dents:
			var c: Vector3 = dt["at"]
			var d: Vector3 = dt["dir"]
			var r: float = dt["r"]
			var depth: float = dt["d"]
			var r2 := r * r
			for i in vcount:
				var v := verts[i]
				var rel := v - c
				var q := rel.length_squared()
				if q >= r2:
					continue
				var face := 1.0
				if has_n:
					face = smoothstep(-0.15, 0.45, -nrm[i].dot(d))      # only the surfaces that face the impactor are pushed
					if face <= 0.0:
						continue
				var sq := q / r2
				var w := (1.0 - sq) * (1.0 - sq) * face
				var jit := fposmod(sin(v.x * 127.1 + v.y * 311.7 + v.z * 74.7) * 43758.5453, 1.0) - 0.5
				verts[i] = v + d * (depth * w * (1.0 + 0.12 * jit)) + Vector3(jit * 0.015, jit * 0.012, -jit * 0.015) * depth * w * 6.0      # a clean crater, not a torn sheet (the jitter is only a crumple)
				if has_n:
					var radial := rel - d * rel.dot(d)
					var tilt := radial * (depth * 4.0 * (1.0 - sq) * face / maxf(r, 0.1) / maxf(r, 0.1))
					nrm[i] = (nrm[i] - tilt).normalized()
		arrays[Mesh.ARRAY_VERTEX] = verts
		if has_n:
			arrays[Mesh.ARRAY_NORMAL] = nrm
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(s, _orig_mesh.surface_get_material(s))
		out.surface_set_name(s, (_orig_mesh as ArrayMesh).surface_get_name(s) if _orig_mesh is ArrayMesh else "")
	body.mesh = out
	if body_lod1 != null:                                    # the far LOD is the undented model: a damaged car keeps its dented body at any distance
		body.visibility_range_end = 0.0
		body_lod1.visible = false


## The windows crack: level 0..1 (only ever grows). A cracked-glass overlay (one transparent draw call, built on the first crack) over the windscreen first, then the rear
## window and the side windows. `at` (model space) says which side took the hit, so that side's window goes first.
func crack_glass(level: float, at := Vector3.ZERO) -> void:
	level = clampf(level, 0.0, 1.0)
	if v2 != null:
		v2.crack_glass(level, at, _dims)
		cracks = v2.cracks
		return
	if body == null or level <= cracks + 0.02:
		return
	cracks = level
	if _crack_mi == null:
		_crack_mi = MeshInstance3D.new()
		_crack_mi.name = "Cracks"
		_crack_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_crack_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _cracks_texture()
		m.albedo_color = Color(0.9, 0.95, 1.0, 1.0)
		m.no_depth_test = false
		m.render_priority = 2
		_crack_mi.material_override = m
		model.add_child(_crack_mi)
	_crack_seed = int(absf(at.x * 7.0 + at.z * 13.0))
	_crack_mi.mesh = _crack_mesh(level, at)
	_crack_mi.visible = true


## Window quads from the car's proportions (windscreen, rear window, both side windows), pushed 1.5 cm off the glass. `reveal` per quad is its vertex alpha.
func _crack_mesh(level: float, at: Vector3) -> ArrayMesh:
	var spec: Dictionary = VehicleSpecs.SPECS[_kind]
	var ln := float(spec["len"])
	var wd := float(spec["wid"])
	var hg := float(spec["hgt"])
	var gl: Dictionary = spec.get("glass", {})
	var ws_z0 := float(gl.get("ws_z0", -0.168)) * ln                  # windscreen: bottom edge z, top edge z (front is -Z)
	var ws_z1 := float(gl.get("ws_z1", 0.02)) * ln
	var ws_h0 := float(gl.get("ws_h0", 0.63)) * hg
	var ws_h1 := float(gl.get("ws_h1", 0.84)) * hg
	var ws_w0 := float(gl.get("ws_w0", 0.41)) * wd
	var ws_w1 := float(gl.get("ws_w1", 0.34)) * wd
	var rw_z0 := float(gl.get("rw_z0", 0.305)) * ln
	var rw_z1 := float(gl.get("rw_z1", 0.17)) * ln
	var rw_h0 := float(gl.get("rw_h0", 0.64)) * hg
	var sd_z0 := float(gl.get("sd_z0", -0.02)) * ln
	var sd_z1 := float(gl.get("sd_z1", 0.25)) * ln
	var sd_h0 := float(gl.get("sd_h0", 0.62)) * hg
	var sd_h1 := float(gl.get("sd_h1", 0.83)) * hg
	var sd_x0 := float(gl.get("sd_x0", 0.455)) * wd
	var sd_x1 := float(gl.get("sd_x1", 0.40)) * wd
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var side_hit := signf(at.x)
	var quads: Array = [
		[[Vector3(-ws_w0, ws_h0, ws_z0), Vector3(ws_w0, ws_h0, ws_z0), Vector3(ws_w1, ws_h1, ws_z1), Vector3(-ws_w1, ws_h1, ws_z1)], clampf(level * 3.0, 0.0, 1.0)],
		[[Vector3(-ws_w0 * 0.9, rw_h0, rw_z0), Vector3(ws_w0 * 0.9, rw_h0, rw_z0), Vector3(ws_w1 * 0.95, ws_h1, rw_z1), Vector3(-ws_w1 * 0.95, ws_h1, rw_z1)], clampf(level * 3.0 - 0.9, 0.0, 1.0)],
		[[Vector3(sd_x0, sd_h0, sd_z0), Vector3(sd_x0, sd_h0, sd_z1), Vector3(sd_x1, sd_h1, sd_z1 - 0.15 * ln * 0.3), Vector3(sd_x1, sd_h1, sd_z0 + 0.04 * ln)], clampf(level * 3.0 - (0.4 if side_hit >= 0.0 else 1.6), 0.0, 1.0)],
		[[Vector3(-sd_x0, sd_h0, sd_z1), Vector3(-sd_x0, sd_h0, sd_z0), Vector3(-sd_x1, sd_h1, sd_z0 + 0.04 * ln), Vector3(-sd_x1, sd_h1, sd_z1 - 0.15 * ln * 0.3)], clampf(level * 3.0 - (0.4 if side_hit < 0.0 else 1.6), 0.0, 1.0)],
	]
	var qi := 0
	for q in quads:
		var pts: Array = q[0]
		var a: float = q[1]
		if a > 0.02:
			var n: Vector3 = ((pts[1] as Vector3) - (pts[0] as Vector3)).cross((pts[3] as Vector3) - (pts[0] as Vector3)).normalized()
			var base := verts.size()
			var flip := (_crack_seed + qi) % 2 == 0
			for k in 4:
				verts.append((pts[k] as Vector3) + n * (0.015 if n.dot(pts[k] as Vector3) >= 0.0 else -0.015))
				cols.append(Color(1.0, 1.0, 1.0, a * 0.9))
			var u: Array = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			for k in 4:
				uvs.append(Vector2(1.0 - (u[k] as Vector2).x, (u[k] as Vector2).y) if flip else u[k])
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		qi += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts if verts.size() > 0 else PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	arrays[Mesh.ARRAY_TEX_UV] = uvs if verts.size() > 0 else PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	arrays[Mesh.ARRAY_COLOR] = cols if verts.size() > 0 else PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0)])
	arrays[Mesh.ARRAY_INDEX] = idx if verts.size() > 0 else PackedInt32Array([0, 1, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## One shared 128 px cracked-glass texture: a star of cracks from near the middle, ring cracks and a few branches, white on transparent, drawn once.
static func _cracks_texture() -> ImageTexture:
	if _crack_tex != null:
		return _crack_tex
	var img := Image.create(GLASS_TEX, GLASS_TEX, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var c := Vector2(GLASS_TEX * 0.46, GLASS_TEX * 0.5)
	var n := 11
	for i in n:
		var a := TAU * float(i) / float(n) + rng.randf_range(-0.15, 0.15)
		var p := c
		var ang := a
		var len_left := float(GLASS_TEX) * rng.randf_range(0.35, 0.8)
		while len_left > 0.0:
			var step := rng.randf_range(5.0, 11.0)
			ang += rng.randf_range(-0.22, 0.22)
			var q := p + Vector2(cos(ang), sin(ang)) * step
			_line(img, p, q, 1.0 - clampf(p.distance_to(c) / (GLASS_TEX * 0.9), 0.0, 0.7))
			if rng.randf() < 0.22:                                              # a branch
				var b := ang + rng.randf_range(0.5, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0)
				_line(img, q, q + Vector2(cos(b), sin(b)) * rng.randf_range(8.0, 22.0), 0.65)
			p = q
			len_left -= step
	for ring in [10.0, 21.0, 36.0]:                                             # ring cracks join the spokes
		var prev := c + Vector2(ring, 0.0)
		for k in range(1, 25):
			var th := TAU * float(k) / 24.0
			var rr: float = ring * rng.randf_range(0.9, 1.1)
			var cur := c + Vector2(cos(th), sin(th)) * rr
			if rng.randf() < 0.72:
				_line(img, prev, cur, 0.8)
			prev = cur
	img.generate_mipmaps()                                                      # the shader blurs the lines with the distance (car_glass.gdshader crack_lod)
	_crack_tex = ImageTexture.create_from_image(img)
	return _crack_tex


static func _line(img: Image, a: Vector2, b: Vector2, alpha: float) -> void:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		var x := int(p.x)
		var y := int(p.y)
		for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:           # two pixels thick: a 1 px line is gone at a distance
			var qx: int = x + o.x
			var qy: int = y + o.y
			if qx >= 0 and qy >= 0 and qx < img.get_width() and qy < img.get_height():
				img.set_pixel(qx, qy, Color(1, 1, 1, alpha))


## Hull condition from the damage fraction (0 sound .. 1 wrecked): the glass cracks from GLASS_BREAK_AT on even without a hard single hit.
func set_condition(frac: float) -> void:
	if frac >= VehicleSpecs.GLASS_BREAK_AT:
		crack_glass((frac - VehicleSpecs.GLASS_BREAK_AT) / (1.0 - VehicleSpecs.GLASS_BREAK_AT) * 0.7 + 0.25)


## Back to a sound, clean car (a pooled car being put into play again, the garage, a repair station): original body mesh, no dents, no cracks, no wear.
func repair() -> void:
	if v2 != null:
		v2.repair()
		dents = v2.dents
		cracks = 0.0
		damage_look = 0.0
		deform = 0.0
		restore_wheels()
		return
	if _orig_mesh != null and body != null:
		body.mesh = _orig_mesh
		if body_lod1 != null:
			body.visibility_range_end = LOD1_DIST
			body_lod1.visible = true
	dents.clear()
	_src_arrays.clear()
	_orig_mesh = null
	restore_wheels()
	cracks = 0.0
	if _crack_mi != null:
		_crack_mi.visible = false
	deform = 0.0
	if _body_mat != null and damage_look > 0.0:
		damage_look = 0.0
		_apply_surface()
		_body_mat.emission = _base_col
		_body_mat.emission_energy_multiplier = paint_glow()


## Wet streets: a wet car is glossier (lower roughness, full clear coat). Follows the global `wetness`.
func set_wet(w: float) -> void:
	w = clampf(w, 0.0, 1.0)
	if v2 != null:
		if absf(w - wet_look) >= 0.03:
			wet_look = w
			v2.set_wet(w)
		return
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


## The finish of the paint as numbers, whatever the material is: roughness, metallic, clearcoat, specular, glow (emission floor), albedo, rim, emission colour. The older art reads its Body
## StandardMaterial3D, Cars v2 asks the shader parameters (CarV2.paint_state); tests and tools use this instead of reaching into the material.
func paint_state() -> Dictionary:
	if v2 != null:
		return v2.paint_state()
	if _body_mat == null:
		return {}
	return {"roughness": _body_mat.roughness, "metallic": _body_mat.metallic, "clearcoat": _body_mat.clearcoat if _body_mat.clearcoat_enabled else 0.0, "specular": _body_mat.metallic_specular,
			"glow": _body_mat.emission_energy_multiplier, "albedo": _body_mat.albedo_color, "rim": _body_mat.rim if _body_mat.rim_enabled else 0.0, "emission": _body_mat.emission}


func get_paint() -> Color:
	if v2 != null:
		return v2.get_paint()
	return _body_mat.albedo_color if _body_mat != null else Color.BLACK


func set_glow(color: Color) -> void:
	if v2 != null:
		v2.set_glow(color)
		var sir: Array = VehicleSpecs.PATROL_SIREN
		if color.is_equal_approx(sir[0] as Color) or color.is_equal_approx(sir[1] as Color):        # the siren colours of Vehicle._chase_siren: the light bar flashes red and blue
			v2.set_siren(1.0 if color.is_equal_approx(sir[0] as Color) else 0.0, true)
		else:
			v2.set_siren(0.5, false)
		return
	for i in _cols[2].size():
		_cols[2][i] = color
	_write_light(2, _last[2])


## Light factors (multipliers of the model's own emission): headlights, taillights, underglow. Only changes are written.
func set_lights(head: float, tail: float, under: float) -> void:
	if v2 != null:
		if absf(head - float(_last[0])) > 0.01 or absf(tail - float(_last[1])) > 0.01 or absf(under - float(_last[2])) > 0.01:
			_last = [head, tail, under]
			v2.set_lights(head, tail, under)
			_write_beam(head)
		return
	_set_light(0, head)
	_set_light(1, tail)
	_set_light(2, under)


func _set_light(k: int, f: float) -> void:
	if absf(f - float(_last[k])) < 0.01:
		return
	_last[k] = f
	_write_light(k, f)


func _write_light(k: int, f: float) -> void:
	if k == 0:
		_write_beam(f)
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
	if v2 != null:
		v2.set_wheel_pose(_roll, steer)                                # the wheels are vertices of the Details surface: the shader turns them


func set_wheels_visible(v: bool) -> void:
	if v == _wheels_shown:
		return
	_wheels_shown = v
	for i in wheels.size():
		wheels[i].visible = v and not wheel_shed(i)
		if v2 != null:
			v2.set_wheel_lost(i, not v or wheel_shed(i))


## A wheel has flown off (CarDebris): its node stays hidden until restore_wheels() (repair, respawn).
var _shed := PackedByteArray()


func shed_wheel(i: int) -> void:
	if i < 0 or i >= wheels.size():
		return
	if _shed.size() != wheels.size():
		_shed.resize(wheels.size())
	_shed[i] = 1
	wheels[i].visible = false
	if v2 != null:
		v2.set_wheel_lost(i, true)


func wheel_shed(i: int) -> bool:
	return i < _shed.size() and _shed[i] == 1


func wheels_lost() -> int:
	var n := 0
	for b in _shed:
		n += int(b)
	return n


func restore_wheels() -> void:
	if wheels_lost() == 0:
		return
	_shed.fill(0)
	for w in wheels:
		w.visible = _wheels_shown
	if v2 != null:
		for k in wheels.size():
			v2.set_wheel_lost(k, not _wheels_shown)


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
	if spec.has("procedural"):                           # quad, scooter: VehicleCraftModels
		return VehicleCraftModels.build(String(spec["procedural"]), spec)
	if bool(spec.get("shape", false)):
		return _fallback_shaped(spec)
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


## A shaped primitive (VehicleSilhouettes): compact, bus, interceptor, ambulance, scooter. Same node names as the art models (Body, Headlights, Taillights, Underglow, wheels).
func _fallback_shaped(spec: Dictionary) -> Node3D:
	var kind := StringName(String(spec["model"]).trim_prefix("car_").trim_prefix("bike_"))
	for k: StringName in VehicleSpecs.SPECS:
		if VehicleSpecs.SPECS[k] == spec:
			kind = k
	var ln: float = spec["len"]
	var wid: float = spec["wid"]
	var hgt: float = spec["hgt"]
	var r: float = spec["wheel"]
	var root := Node3D.new()
	root.name = String(spec["model"])
	var hull := VehicleSilhouettes.build_body(kind, spec)
	root.add_child(hull)
	var bike := StringName(spec.get("cls", &"car")) == &"bike"
	_strip(root, "Headlights", Vector3(wid * (0.3 if bike else 0.8), 0.12, 0.06), Vector3(0.0, hgt * (0.9 if bike else 0.36), -ln * 0.5 + (0.3 if bike else 0.0)), Color(1.0, 0.94, 0.8), 7.0)
	_strip(root, "Taillights", Vector3(wid * (0.3 if bike else 0.8), 0.1, 0.06), Vector3(0.0, hgt * (0.72 if bike else 0.5), ln * 0.5 - (0.2 if bike else 0.0)), Color(1.0, 0.06, 0.12), 5.0)
	_strip(root, "Underglow", Vector3(wid * 0.9, 0.04, ln * 0.8), Vector3(0.0, 0.12, 0.0), Color(1.0, 0.18, 0.84), 4.0)
	for row: Array in VehicleSilhouettes.lights_of(kind, spec):
		_strip(root, String(row[0]), row[1], row[2], row[3], row[4])
	if bike:
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
	var axle := ln * (0.31 if ln < 6.0 else 0.28)
	for i in 4:
		var w := Node3D.new()
		w.name = String(WHEEL_NAMES[i])
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = r
		cyl.bottom_radius = r
		cyl.height = 0.28 if r < 0.45 else 0.4
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
