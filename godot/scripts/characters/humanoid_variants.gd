class_name HumanoidVariants
extends RefCounted
## Humanoid variants of the Superhero base characters (HeroCharacter, Quaternius Universal Base Characters, CC0) for NPCs and enemies: the same meshes, rig and textures (no new texture
## memory: every variant loads the hero's maps through the resource cache and shares them), different skin tint, hair, suit and helmet / visor colours.
##   vael       Vael trooper: helmet (the crown takes the helmet colour, no hair), alien visor colour as the trim / accent, dark armour suit, near mesh <= NEAR_ENEMY, mid mesh <= MID
##   citizen    civilian: casual suit colours, hair styles, unarmed, near mesh <= NEAR_CITIZEN, mid mesh <= MID
## Far distances keep the existing impostors (the MultiMesh crowd; enemies are hidden beyond Drone.MODEL_RANGE). With the hero files absent `build()` returns {"root": null} and the
## callers keep their existing models.

const NEAR_ENEMY := 6000
const NEAR_CITIZEN := 4000
const MID := 2500
const MID_RANGE := 24.0                          ## metres: beyond this the mid mesh is shown (hysteresis in set_lod)
const VAEL_COUNT := 6
const CITIZEN_COUNT := 10
const VISORS: Array[Color] = [Color(1.0, 0.2, 0.25), Color(0.25, 1.0, 0.7), Color(0.85, 0.35, 1.0), Color(1.0, 0.65, 0.15), Color(0.3, 0.75, 1.0), Color(1.0, 0.35, 0.8)]
const HELMETS: Array[Color] = [Color(0.07, 0.07, 0.09), Color(0.12, 0.1, 0.14), Color(0.06, 0.1, 0.1), Color(0.14, 0.09, 0.08), Color(0.08, 0.09, 0.14), Color(0.1, 0.1, 0.1)]
const SUITS: Array[Color] = [Color(0.12, 0.13, 0.17), Color(0.16, 0.12, 0.18), Color(0.1, 0.16, 0.16), Color(0.19, 0.13, 0.11), Color(0.11, 0.14, 0.2), Color(0.14, 0.14, 0.15)]
const CIVIL_SUITS: Array[Color] = [Color(0.55, 0.3, 0.25), Color(0.25, 0.42, 0.55), Color(0.3, 0.5, 0.35), Color(0.6, 0.55, 0.3), Color(0.45, 0.35, 0.55), Color(0.5, 0.5, 0.52),
		Color(0.7, 0.4, 0.5), Color(0.2, 0.3, 0.45), Color(0.65, 0.45, 0.25), Color(0.3, 0.3, 0.35)]
const HAIR_COLORS: Array[Color] = [Color(0.16, 0.11, 0.085), Color(0.05, 0.05, 0.06), Color(0.45, 0.3, 0.14), Color(0.62, 0.55, 0.4), Color(0.45, 0.12, 0.1), Color(0.3, 0.3, 0.34)]

## The Vael roster: six looks that differ in silhouette (width, height), armour colour and trim, so a squad is not six copies of one trooper. `scale3` is the body scale of the model root
## (x width, y height, z depth); the jacket / pants colours are what the body shader draws on the torso and the legs. Picked by VAEL_PICK (rifleman most often), or by the enemy's role (ROLE_CLASS).
const VAEL_CLASSES: Array[Dictionary] = [
	{"name": &"rifleman", "jacket": Color(0.23, 0.27, 0.35), "pants": Color(0.10, 0.11, 0.15), "helmet": Color(0.07, 0.07, 0.09), "trim": Color(1.0, 0.2, 0.25), "scale3": Vector3(1.0, 1.0, 1.0)},
	{"name": &"gunner", "jacket": Color(0.33, 0.31, 0.17), "pants": Color(0.17, 0.16, 0.10), "helmet": Color(0.14, 0.13, 0.08), "trim": Color(1.0, 0.65, 0.15), "scale3": Vector3(1.2, 1.03, 1.2)},
	{"name": &"scout", "jacket": Color(0.08, 0.24, 0.26), "pants": Color(0.05, 0.10, 0.12), "helmet": Color(0.06, 0.10, 0.10), "trim": Color(0.25, 1.0, 0.8), "scale3": Vector3(0.9, 0.96, 0.9)},
	{"name": &"grenadier", "jacket": Color(0.45, 0.20, 0.10), "pants": Color(0.14, 0.10, 0.08), "helmet": Color(0.14, 0.09, 0.08), "trim": Color(1.0, 0.85, 0.2), "scale3": Vector3(1.12, 1.0, 1.12)},
	{"name": &"marksman", "jacket": Color(0.27, 0.12, 0.37), "pants": Color(0.10, 0.07, 0.15), "helmet": Color(0.12, 0.10, 0.14), "trim": Color(1.0, 0.35, 0.8), "scale3": Vector3(0.94, 1.06, 0.94)},
	{"name": &"commander", "jacket": Color(0.36, 0.09, 0.12), "pants": Color(0.16, 0.12, 0.13), "helmet": Color(0.85, 0.85, 0.88), "trim": Color(1.0, 0.9, 0.5), "scale3": Vector3(1.06, 1.07, 1.06)},
]
## Wave 113 (enemy look v3): each trooper class wears the armour kit of an authority look (FoeKit): same rig, ONE surface, no textures; the carbine stays the weapon (the troopers' grips are solved on it).
const CLASS_LOOK: Array[StringName] = [&"auth_rifle", &"auth_heavy", &"auth_breacher", &"auth_engineer", &"auth_ghost", &"auth_drone"]
const VAEL_BIG := 1.12                          ## the Vael are a little taller and broader than a person (readable at phone size, a hostile silhouette)
const VAEL_PICK: Array[int] = [0, 0, 1, 2, 0, 3, 4, 5]            ## n % 8 -> class: riflemen 3 in 8, the others about one in 8
const ROLE_CLASS := {&"shield": 1, &"carrier": 1, &"flanker": 2, &"stalker": 2, &"pouncer": 2, &"sniper": 4, &"warden": 5, &"hivemother": 5, &"overseer": 5}

static var enabled := true                       ## tests flip this off to compare with the old models
static var use_kit := OS.get_environment("FOE_NO_KIT") != "1"   ## false (look-dev / perf comparison: FOE_NO_KIT=1): the Vael troopers keep the hero-shader look (colour classes only)
static var _mid_cache := {}                      ## variant key -> mid ArrayMesh (shared by every instance of the variant)


static func available() -> bool:
	return enabled and HeroCharacter.available(&"male") and HeroCharacter.available(&"female")


## The deterministic variant of `kind` for `seed_value`: {kind, key, opts (HeroCharacter), budget, suit, trim, helmet, hair_color, helmeted}.
static func variant(kind: StringName, seed_value: int, force_class := -1) -> Dictionary:
	var n := absi(seed_value)
	var vael := kind == &"vael"
	var count := VAEL_COUNT if vael else CITIZEN_COUNT
	var v := n % count
	if vael:
		v = force_class if force_class >= 0 else VAEL_PICK[n % VAEL_PICK.size()]
	var skins := HeroCharacter.SKINS
	var opts := {"body": HeroCharacter.BODIES[(n / 2) % 2], "skin": skins[(n / 3) % skins.size()], "beard": (not vael) and n % 5 == 0,
			"map_body": &"male", "map_skin": &"dark"}      # one shared set of skin maps (the hero's default): the skin tone is the tint, no extra texture memory
	if vael:
		opts["hair"] = &"none"
		opts["armed"] = true
		opts["budget"] = NEAR_ENEMY
		if FoeKit.available() and use_kit:
			opts["foe_look"] = CLASS_LOOK[(force_class if force_class >= 0 else VAEL_PICK[n % VAEL_PICK.size()]) % CLASS_LOOK.size()]
			opts["weapon_id"] = &"carbine"
			opts["variant"] = (n / 5) % 3
	else:
		opts["hair"] = HeroCharacter.HAIRS[1 + (n / 4) % (HeroCharacter.HAIRS.size() - 1)]
		opts["armed"] = false
		opts["budget"] = NEAR_CITIZEN
	var d := {"kind": kind, "opts": opts, "budget": int(opts["budget"]), "helmeted": vael}
	d["suit"] = SUITS[v % SUITS.size()] if vael else CIVIL_SUITS[v % CIVIL_SUITS.size()]
	d["trim"] = VISORS[v % VISORS.size()] if vael else Color(0.6, 0.65, 0.7)
	d["helmet"] = HELMETS[v % HELMETS.size()]
	d["hair_color"] = HAIR_COLORS[(n / 7) % HAIR_COLORS.size()]
	d["key"] = "%s/%s/%s/%s/%d" % [kind, opts["body"], opts["skin"], opts["hair"], v]
	if vael:
		var c: Dictionary = VAEL_CLASSES[v % VAEL_CLASSES.size()]
		d["class"] = c["name"]
		d["suit"] = c["pants"]
		d["helmet"] = c["helmet"]
		d["trim"] = c["trim"]
		d["jacket"] = c["jacket"]
		d["pants"] = c["pants"]
		var j := 0.94 + 0.12 * float((n / 11) % 5) / 4.0              # a little personal jitter on top of the class (height 0.94 .. 1.06)
		d["scale3"] = (c["scale3"] as Vector3) * Vector3(1.0, j, 1.0) * VAEL_BIG
	return d


## The outfit colours of a variant {jacket, pants} for the body shader. Troopers: dark armour, a little lighter on the torso than on the legs, so they never read as the hero's light
## jacket; citizens: their casual colour on the torso over dark trousers.
static func outfit(d: Dictionary) -> Dictionary:
	if d.has("jacket"):
		return {"jacket": d["jacket"], "pants": d["pants"]}
	var sc: Color = d["suit"]
	if bool(d["helmeted"]):
		return {"jacket": Color(sc.r * 1.6 + 0.02, sc.g * 1.6 + 0.02, sc.b * 1.6 + 0.03), "pants": Color(sc.r * 0.8, sc.g * 0.8, sc.b * 0.8)}
	return {"jacket": sc, "pants": Color(0.14, 0.15, 0.18)}


## Applies the variant's colours to a hero material (also used by tests).
static func tint(mat: ShaderMaterial, d: Dictionary) -> void:
	if (d["opts"] as Dictionary).has("foe_look"):                 # the kit's textureless body shader: its palette was applied by the builder
		return
	mat.set_shader_parameter(&"suit_color", d["suit"])
	var fit := outfit(d)
	mat.set_shader_parameter(&"jacket_color", fit["jacket"])
	mat.set_shader_parameter(&"pants_color", fit["pants"])
	mat.set_shader_parameter(&"trim_color", d["trim"])
	mat.set_shader_parameter(&"accent", d["trim"])
	if bool(d["helmeted"]):
		mat.set_shader_parameter(&"hair_color", d["helmet"])
		mat.set_shader_parameter(&"scalp", 1.0)                 # the crown takes the helmet colour; no hair geometry
		mat.set_shader_parameter(&"accent_mix", 0.5)
		mat.set_shader_parameter(&"glow", 1.6)
	else:
		mat.set_shader_parameter(&"hair_color", d["hair_color"])
		mat.set_shader_parameter(&"glow", 0.2)
		mat.set_shader_parameter(&"suit_metal", 0.05)


## {root, ok, info, body, material, variant}; root null when the files are absent or `enabled` is off. info["tris"] is the triangle count of the near mesh.
static func build(kind: StringName, seed_value: int, force_class := -1) -> Dictionary:
	if not available():
		return {"root": null, "ok": false, "info": {}}
	var d := variant(kind, seed_value, force_class)
	var r := HeroCharacter.build(d["opts"])
	if r["root"] == null:
		return r
	tint(r["material"], d)
	r["variant"] = d
	var body := r["body"] as MeshInstance3D
	if body != null:
		body.set_meta(&"variant_key", d["key"])
		body.set_meta(&"near_mesh", body.mesh)
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if kind == &"vael":                              # the old trooper model carried its own visor glow light (switched by distance through the enemy's lod hook)
		var l := OmniLight3D.new()
		l.name = "VisorGlow"
		l.light_color = d["trim"]
		l.light_energy = 0.6
		l.omni_range = 3.0
		l.shadow_enabled = false
		l.position = Vector3(0.0, 1.55, -0.35)
		(r["root"] as Node3D).add_child(l)
	return r


## The mid mesh of a variant (<= MID triangles, same skin binding as the near mesh), built once per variant key and shared.
static func mid_mesh(d: Dictionary) -> Mesh:
	var key := String(d["key"])
	if _mid_cache.has(key):
		return _mid_cache[key]
	var o: Dictionary = (d["opts"] as Dictionary).duplicate()
	o["budget"] = MID
	if o.has("foe_look"):
		o["kit_lod"] = 1
	var r := HeroCharacter.build(o)
	var mesh: Mesh = null
	if r["root"] != null:
		var b := r["body"] as MeshInstance3D
		mesh = b.mesh
		tint(r["material"], d)
		b.mesh = null
		(r["root"] as Node).free()
	_mid_cache[key] = mesh
	return mesh


## Near / mid switch by camera distance (call a few times a second); hysteresis of 4 m. Returns true when the mesh changed.
static func set_lod(body: MeshInstance3D, d: Dictionary, dist: float) -> bool:
	if body == null or not body.has_meta(&"near_mesh"):
		return false
	var near: Mesh = body.get_meta(&"near_mesh")
	var is_mid := body.mesh != near
	var want_mid := dist > MID_RANGE - (4.0 if is_mid else 0.0)
	if want_mid == is_mid:
		return false
	var m: Mesh = mid_mesh(d) if want_mid else near
	if m == null:
		return false
	body.mesh = m
	return true


static func tris(mesh: Mesh) -> int:
	var t := 0
	if mesh == null:
		return 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		t += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t
