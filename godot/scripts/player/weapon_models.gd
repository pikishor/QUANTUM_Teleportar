class_name WeaponModels
extends RefCounted
## The weapons in the hero's hands: ONE ArrayMesh per weapon (vertex colour rgb = the part, alpha = how much of it glows), drawn as one extra draw call on the muzzle node.
## Every weapon is a real shape (receiver, barrel, magazine, stock, optic, ...), not a strip: the hero is built UNARMED (HeroCharacter `armed` false) and every weapon, the carbine
## included, rides the rifle bone the arms are solved on.
## Frame of a mesh: the origin is the MUZZLE, the barrel points to -Z, the body extends toward +Z (behind the muzzle), +Y up, +X the hero's right.
## SPEC[id]: `reach` = how far the muzzle sits in front of the rifle pivot (the carbine's is 0.86 m: shorter guns pull the muzzle back so the hands never reach for them),
## `gr` / `gl` = where the right / left wrist grips, in the mesh frame (PlayerBody turns that into the rig's per-hand offset). Silhouette rules: one distinguishing feature per class.

const GUN := Color(0.15, 0.16, 0.19)
const POLY := Color(0.085, 0.09, 0.105)
const DARK := Color(0.05, 0.055, 0.065)
const STEEL := Color(0.36, 0.38, 0.42)
const BRASS := Color(0.62, 0.5, 0.28)
const CARBINE_REACH := 0.86
const CARBINE_GR := Vector3(0.0, -0.095, 0.68)       ## the carbine's grips in its own mesh frame: the rig's rest wrists
const CARBINE_GL := Vector3(-0.012, -0.08, 0.39)
const MUZZLE_AT := Vector3(0.0, 0.01, -0.86)          ## HeroCharacter: the muzzle in the rifle frame

const SPEC0 := {
	&"pistol": {"reach": 0.6, "gr": Vector3(0.0, -0.085, 0.17), "gl": Vector3(-0.025, -0.1, 0.12)},
	&"burst": {"reach": 0.6, "gr": Vector3(0.0, -0.085, 0.2), "gl": Vector3(-0.025, -0.105, 0.14)},
	&"revolver": {"reach": 0.62, "gr": Vector3(0.0, -0.095, 0.25), "gl": Vector3(-0.025, -0.115, 0.2)},
	&"akimbo": {"reach": 0.62, "gr": Vector3(0.075, -0.085, 0.17), "gl": Vector3(-0.075, -0.085, 0.17)},
	&"flux": {"reach": 0.66, "gr": Vector3(0.0, -0.09, 0.34), "gl": Vector3(0.0, -0.085, 0.14)},
	&"carbine": {"reach": 0.86, "gr": Vector3(0.0, -0.095, 0.68), "gl": Vector3(-0.012, -0.08, 0.39)},
	&"marksman": {"reach": 0.92, "gr": Vector3(0.0, -0.09, 0.74), "gl": Vector3(0.0, -0.075, 0.44)},
	&"arc": {"reach": 0.8, "gr": Vector3(0.0, -0.09, 0.6), "gl": Vector3(0.0, -0.08, 0.32)},
	&"scatter": {"reach": 0.84, "gr": Vector3(0.0, -0.09, 0.66), "gl": Vector3(0.0, -0.1, 0.34)},
	&"breacher": {"reach": 0.74, "gr": Vector3(0.0, -0.1, 0.52), "gl": Vector3(0.0, -0.1, 0.24)},
	&"rail": {"reach": 0.98, "gr": Vector3(0.0, -0.09, 0.8), "gl": Vector3(0.0, -0.08, 0.48)},
	&"lance": {"reach": 1.0, "gr": Vector3(0.0, -0.07, 0.9), "gl": Vector3(0.0, -0.06, 0.52)},
	&"gravity": {"reach": 0.82, "gr": Vector3(0.0, -0.1, 0.62), "gl": Vector3(0.0, -0.11, 0.3)},
	&"rocket": {"reach": 0.8, "gr": Vector3(0.0, -0.11, 0.62), "gl": Vector3(0.0, -0.12, 0.3)},
	&"minigun": {"reach": 0.84, "gr": Vector3(0.0, -0.12, 0.6), "gl": Vector3(0.0, -0.14, 0.3)},
	&"grenade": {"reach": 0.5, "gr": Vector3(0.0, -0.02, 0.14), "gl": Vector3(-0.07, -0.12, 0.34)},
	&"blade": {"reach": 1.1, "gr": Vector3(0.0, 0.0, 0.88), "gl": Vector3(0.0, 0.0, 1.02)},
	&"whip": {"reach": 0.8, "gr": Vector3(0.0, -0.01, 0.28), "gl": Vector3(0.0, -0.01, 0.42)},
	&"swarm": {"reach": 0.62, "gr": Vector3(0.0, -0.075, 0.27), "gl": Vector3(-0.01, -0.08, 0.1)},
	&"vector": {"reach": 0.68, "gr": Vector3(0.0, -0.085, 0.38), "gl": Vector3(0.0, -0.08, 0.16)},
	&"battle": {"reach": 0.88, "gr": Vector3(0.0, -0.09, 0.7), "gl": Vector3(0.0, -0.08, 0.4)},
	&"sawn": {"reach": 0.66, "gr": Vector3(0.0, -0.09, 0.46), "gl": Vector3(0.0, -0.08, 0.22)},
	&"auto": {"reach": 0.84, "gr": Vector3(0.0, -0.09, 0.66), "gl": Vector3(0.0, -0.09, 0.36)},
	&"bolt": {"reach": 0.98, "gr": Vector3(0.0, -0.09, 0.8), "gl": Vector3(0.0, -0.08, 0.48)},
	&"dmr": {"reach": 0.94, "gr": Vector3(0.0, -0.09, 0.76), "gl": Vector3(0.0, -0.08, 0.46)},
	&"knife": {"reach": 1.0, "gr": Vector3(0.0, 0.0, 0.34), "gl": Vector3(0.0, 0.0, 0.42)},
	# round 5 roster
	&"magnum": {"reach": 0.62, "gr": Vector3(0.0, -0.095, 0.2), "gl": Vector3(-0.025, -0.115, 0.16)},
	&"mpistol": {"reach": 0.64, "gr": Vector3(0.0, -0.085, 0.22), "gl": Vector3(-0.015, -0.1, 0.12)},
	&"stun": {"reach": 0.6, "gr": Vector3(0.0, -0.085, 0.17), "gl": Vector3(-0.025, -0.1, 0.12)},
	&"ranger": {"reach": 0.86, "gr": Vector3(0.0, -0.095, 0.68), "gl": Vector3(-0.012, -0.08, 0.4)},
	&"bullpup": {"reach": 0.78, "gr": Vector3(0.0, -0.1, 0.5), "gl": Vector3(0.0, -0.09, 0.26)},
	&"lmg": {"reach": 0.88, "gr": Vector3(0.0, -0.1, 0.5), "gl": Vector3(0.0, -0.09, 0.26)},
	&"amr": {"reach": 0.98, "gr": Vector3(0.0, -0.09, 0.8), "gl": Vector3(0.0, -0.08, 0.5)},
	&"xbow": {"reach": 0.8, "gr": Vector3(0.0, -0.09, 0.52), "gl": Vector3(0.0, -0.06, 0.28)},
	&"flame": {"reach": 0.84, "gr": Vector3(0.0, -0.1, 0.62), "gl": Vector3(0.0, -0.06, 0.34)},
	&"katana": {"reach": 1.1, "gr": Vector3(0.0, 0.0, 0.98), "gl": Vector3(0.0, 0.0, 1.12)},
	&"bat": {"reach": 1.0, "gr": Vector3(0.0, 0.0, 0.8), "gl": Vector3(0.0, 0.0, 0.9)},
	&"qsuper": {"reach": 0.8, "gr": Vector3(0.0, -0.1, 0.56), "gl": Vector3(0.0, -0.08, 0.3)},
	&"qlink": {"reach": 0.78, "gr": Vector3(0.0, -0.1, 0.5), "gl": Vector3(0.0, -0.08, 0.26)},
	&"qcollapse": {"reach": 0.82, "gr": Vector3(0.0, -0.12, 0.62), "gl": Vector3(0.0, -0.12, 0.3)},
	&"qblink": {"reach": 0.6, "gr": Vector3(0.0, -0.085, 0.2), "gl": Vector3(-0.025, -0.1, 0.14)},
	&"qphase": {"reach": 0.88, "gr": Vector3(0.0, -0.09, 0.7), "gl": Vector3(0.0, -0.08, 0.4)},
	&"qstasis": {"reach": 0.8, "gr": Vector3(0.0, -0.1, 0.56), "gl": Vector3(0.0, -0.08, 0.3)},
	# wave 108: the ENERGY family and the BLAST heavies (scripts/player/weapon_models_energy.gd)
	&"eplasma": {"reach": 0.6, "gr": Vector3(0.0, -0.085, 0.22), "gl": Vector3(-0.025, -0.1, 0.15)},
	&"erepeat": {"reach": 0.8, "gr": Vector3(0.0, -0.095, 0.58), "gl": Vector3(0.0, -0.08, 0.3)},
	&"espike": {"reach": 0.8, "gr": Vector3(0.0, -0.1, 0.56), "gl": Vector3(0.0, -0.08, 0.3)},
	&"ebeam": {"reach": 1.0, "gr": Vector3(0.0, -0.07, 0.9), "gl": Vector3(0.0, -0.06, 0.5)},
	&"eblade": {"reach": 1.1, "gr": Vector3(0.0, 0.0, 0.94), "gl": Vector3(0.0, 0.0, 1.08)},
	&"emaul": {"reach": 1.0, "gr": Vector3(0.0, 0.0, 0.7), "gl": Vector3(0.0, 0.0, 0.92)},
	&"epod": {"reach": 0.82, "gr": Vector3(0.0, -0.11, 0.6), "gl": Vector3(0.0, -0.12, 0.3)},
	&"railgun": {"reach": 0.98, "gr": Vector3(0.0, -0.1, 0.84), "gl": Vector3(0.0, -0.09, 0.5)},
	&"chaingun": {"reach": 0.84, "gr": Vector3(0.0, -0.12, 0.62), "gl": Vector3(0.0, -0.14, 0.32)},
	&"cmissile": {"reach": 0.8, "gr": Vector3(0.0, -0.11, 0.62), "gl": Vector3(0.0, -0.12, 0.3)},
	&"napalm": {"reach": 0.78, "gr": Vector3(0.0, -0.11, 0.56), "gl": Vector3(0.0, -0.13, 0.26)},
	&"sing": {"reach": 0.82, "gr": Vector3(0.0, -0.13, 0.64), "gl": Vector3(0.0, -0.12, 0.32)},
	&"orbital": {"reach": 0.66, "gr": Vector3(0.0, -0.1, 0.4), "gl": Vector3(0.0, -0.1, 0.2)},
	&"seeker": {"reach": 0.84, "gr": Vector3(0.0, -0.11, 0.62), "gl": Vector3(0.0, -0.12, 0.32)},
	&"tknife": {"reach": 0.9, "gr": Vector3(0.0, 0.0, 0.26), "gl": Vector3(0.0, 0.0, 0.32)},
}
static var SPEC: Dictionary = SPEC0.merged(WeaponDefs.pack_dict("spec"))              ## the roster packs add theirs (WeaponDefs.PACKS)

static var _cache := {}
static var _material: ShaderMaterial


## The mesh of weapon `id` (cached), null for an unknown id.
static func mesh(id: StringName) -> ArrayMesh:
	if not WeaponDefs.DEFS.has(id):
		return null
	if _cache.has(id):
		return _cache[id]
	var glow: Color = WeaponDefs.def(id)["look"]
	var b := _Builder.new()
	var opened := false
	if id == &"akimbo":
		opened = _open(b, id, 0.075) and _open(b, id, -0.075)
	else:
		opened = _open(b, id)
	if opened:
		_extras(b, id)
	else:
		b = _Builder.new()
		_procedural(b, id, glow)
	var m := b.build()
	_cache[id] = m
	return m


## The open-source model of weapon `id` (assets/models/ow_<id>.glb, CC0 Quaternius / OpenGameArt guns converted by tools/open_models/convert_weapons.py: muzzle at the origin, barrel -Z, y = bore axis)
## appended to the builder, `dx` metres to the right. False when the model does not exist (the procedural mesh below is the fallback; QT_OPEN_MODELS=0 forces it).
static func _open(b: _Builder, id: StringName, dx := 0.0) -> bool:
	if OS.get_environment("QT_OPEN_MODELS") == "0":
		return false
	var path := "res://assets/models/ow_%s.glb" % String(id)
	if not ResourceLoader.exists(path):
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	var root := scene.instantiate()
	var mi: MeshInstance3D = root as MeshInstance3D if root is MeshInstance3D else root.find_child("*", true, false) as MeshInstance3D
	if mi == null or mi.mesh == null:
		root.free()
		return false
	var arr := mi.mesh.surface_get_arrays(0)
	root.free()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if v.is_empty() or idx.is_empty():
		return false
	var base := b.verts.size()
	for i in v.size():
		b.verts.append(v[i] + Vector3(dx, 0.0, 0.0))
		b.norms.append(n[i])
		var c := cols[i].srgb_to_linear() if i < cols.size() else GUN      # the glTF importer hands vertex colours over as sRGB, this shader reads them as linear
		b.cols.append(Color(c.r, c.g, c.b, 0.0))
	for i in idx:
		b.idx.append(base + i)
	return true


static func _procedural(b: _Builder, id: StringName, glow: Color) -> void:
	if WeaponDefs.def(id).has("model_seed"):                                                                    # the roster pack of wave 113 (weapon_models_v3.gd)
		WeaponModelsV3.build(b, id, glow)
		return
	match id:
		&"carbine":
			if not _carbine(b, glow):
				_boxy_carbine(b, glow)
		&"pistol":
			_pistol(b, glow, 1.0)
		&"burst":
			_pistol(b, glow, 1.35)
		&"revolver":
			_revolver(b, glow)
		&"akimbo":
			_pistol(b, glow, 1.0, 0.075)
			_pistol(b, glow, 1.0, -0.075)
		&"flux":
			_smg(b, glow)
		&"marksman":
			_marksman(b, glow)
		&"arc":
			_arc(b, glow)
		&"scatter":
			_shotgun(b, glow, false)
		&"breacher":
			_shotgun(b, glow, true)
		&"rail":
			_rail(b, glow)
		&"lance":
			_lance(b, glow)
		&"gravity":
			_gravity(b, glow)
		&"rocket":
			_rocket(b, glow)
		&"minigun":
			_minigun(b, glow)
		&"grenade":
			_grenade(b, glow)
		&"blade":
			_blade(b, glow)
		&"whip":
			_whip(b, glow)
		&"swarm", &"vector":
			_smg(b, glow)
		&"battle":
			_marksman(b, glow)
		&"sawn", &"auto":
			_shotgun(b, glow, id == &"sawn")
		&"bolt":
			_rail(b, glow)
		&"dmr":
			_marksman(b, glow)
		&"knife":
			_blade(b, glow)
		&"magnum":
			_pistol(b, glow, 1.15)
		&"mpistol":
			_smg(b, glow)
		&"ranger", &"bullpup":
			_marksman(b, glow)
		&"lmg":
			_lmg(b, glow)
		&"amr":
			_amr(b, glow)
		&"xbow":
			_xbow(b, glow)
		&"flame":
			_flame(b, glow)
		&"stun":
			_stun(b, glow)
		&"katana":
			_katana(b, glow)
		&"bat":
			_bat(b, glow)
		&"qsuper":
			_qsuper(b, glow)
		&"qlink":
			_qlink(b, glow)
		&"qcollapse":
			_qcollapse(b, glow)
		&"qblink":
			_qblink(b, glow)
		&"qphase":
			_qphase(b, glow)
		&"qstasis":
			_qstasis(b, glow)
		_:
			WeaponModelsEnergy.build(b, id, glow)                                                       # wave 108: the ENERGY and BLAST weapons (weapon_models_energy.gd)


## What the open-source model of a gun lacks: a bipod on the LMG and the anti-material rifle, a glowing muzzle ring on the quantum look of the rest (the real shapes are plain steel).
static func _extras(b: _Builder, id: StringName) -> void:
	match id:
		&"lmg":                                                                                         # a bipod folded under the handguard and a big box magazine
			b.box(Vector3(0.0, -0.045, 0.16), Vector3(0.05, 0.03, 0.05), DARK)
			b.box(Vector3(0.03, -0.12, 0.13), Vector3(0.008, 0.15, 0.008), DARK, 0.0, -0.4)
			b.box(Vector3(-0.03, -0.12, 0.13), Vector3(0.008, 0.15, 0.008), DARK, 0.0, -0.4)
			b.box(Vector3(0.0, -0.22, 0.52), Vector3(0.07, 0.1, 0.12), POLY)
		&"amr":
			b.box(Vector3(0.0, -0.035, 0.34), Vector3(0.05, 0.03, 0.05), DARK)
			b.box(Vector3(0.035, -0.12, 0.3), Vector3(0.008, 0.16, 0.008), DARK, 0.0, -0.35)
			b.box(Vector3(-0.035, -0.12, 0.3), Vector3(0.008, 0.16, 0.008), DARK, 0.0, -0.35)
			b.box(Vector3(0.0, 0.0, 0.05), Vector3(0.045, 0.045, 0.1), DARK)                               # muzzle brake


# --- the models ---------------------------------------------------------------------------------------------------------

## The Blender carbine of the hero kit (2.3k triangles, glow seams in vertex colour G), moved into the muzzle frame.
static func _carbine(b: _Builder, glow: Color) -> bool:
	var arr := HeroCharacter._rifle_arrays()
	if arr.is_empty():
		return false
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		for i in v.size():
			idx.append(i)
	var base := b.verts.size()
	for i in v.size():
		var g := cols[i].g if i < cols.size() else 0.0
		b.verts.append(v[i] - MUZZLE_AT)
		b.norms.append(n[i])
		var c := GUN.lerp(STEEL, 0.25).lerp(glow, clampf(g, 0.0, 1.0))
		b.cols.append(Color(c.r, c.g, c.b, clampf(g, 0.0, 1.0)))
	for i in idx:
		b.idx.append(base + i)
	return true


## The same rifle from boxes when the glb is not imported (a headless check without assets).
static func _boxy_carbine(b: _Builder, glow: Color) -> void:
	b.box(Vector3(0, 0.0, 0.36), Vector3(0.06, 0.08, 0.5), GUN)
	b.box(Vector3(0, -0.08, 0.6), Vector3(0.04, 0.14, 0.1), POLY)
	b.box(Vector3(0, 0.0, 0.8), Vector3(0.05, 0.1, 0.2), POLY)
	b.cyl(Vector3(0, 0.01, 0.15), 0.014, 0.3, STEEL)
	b.box(Vector3(0, 0.0, 0.3), Vector3(0.02, 0.02, 0.4), glow, 1.0)


static func _pistol(b: _Builder, glow: Color, k: float, dx := 0.0) -> void:
	var o := Vector3(dx, 0.0, 0.0)
	var L := 0.2 * k
	b.box(o + Vector3(0, 0.0, 0.01 + L * 0.5), Vector3(0.036, 0.046, L), GUN)                    # slide
	b.box(o + Vector3(0, 0.0235, 0.01 + L * 0.5), Vector3(0.02, 0.006, L - 0.04), STEEL)         # slide top flat
	b.cyl(o + Vector3(0, 0.002, 0.0), 0.012, 0.028, STEEL)                                          # barrel tip
	b.box(o + Vector3(0, -0.038, 0.1 + 0.05 * (k - 1.0) + 0.04), Vector3(0.032, 0.03, 0.15 * k), POLY)   # frame under the slide
	b.box(o + Vector3(0, -0.085, 0.12 * k + 0.07), Vector3(0.034, 0.105, 0.042), DARK, 0.0, -0.28)        # raked grip
	b.box(o + Vector3(0, -0.075, 0.075 * k + 0.05), Vector3(0.012, 0.03, 0.05), POLY)                   # trigger guard front
	b.box(o + Vector3(0, 0.032, 0.015), Vector3(0.008, 0.016, 0.012), STEEL)                            # front sight
	b.box(o + Vector3(0, 0.032, 0.01 + L - 0.02), Vector3(0.022, 0.016, 0.012), STEEL)                  # rear sight
	b.box(o + Vector3(0.0195, 0.0, 0.01 + L * 0.5), Vector3(0.004, 0.018, L - 0.06), glow, 1.0)           # glow strip, right
	b.box(o + Vector3(-0.0195, 0.0, 0.01 + L * 0.5), Vector3(0.004, 0.018, L - 0.06), glow, 1.0)
	if k > 1.1:                                                                                          # the burst pistol: a vented compensator and a long magazine
		b.box(o + Vector3(0, 0.0, 0.0), Vector3(0.044, 0.05, 0.05), STEEL)
		b.box(o + Vector3(0, 0.0, 0.0), Vector3(0.048, 0.012, 0.03), glow, 1.0)
		b.box(o + Vector3(0, -0.15, 0.12 * k + 0.1), Vector3(0.03, 0.09, 0.05), DARK, 0.0, -0.28)


static func _revolver(b: _Builder, glow: Color) -> void:
	b.cyl(Vector3(0, 0.012, 0.15), 0.017, 0.3, STEEL)                                                   # the barrel
	b.box(Vector3(0, 0.038, 0.13), Vector3(0.012, 0.016, 0.24), GUN)                                    # the rib
	b.box(Vector3(0, 0.012, 0.012), Vector3(0.016, 0.014, 0.02), glow, 1.0)
	b.cyl(Vector3(0, 0.002, 0.3), 0.044, 0.092, GUN, 0.0, 10)                                           # the cylinder
	for k in 6:
		var a := TAU * float(k) / 6.0
		b.cyl(Vector3(cos(a) * 0.03, 0.002 + sin(a) * 0.03, 0.3), 0.009, 0.094, DARK)                   # chambers
	b.box(Vector3(0, 0.0, 0.2), Vector3(0.04, 0.05, 0.06), STEEL)                                       # frame in front of the cylinder
	b.box(Vector3(0, 0.003, 0.37), Vector3(0.04, 0.06, 0.07), GUN)                                      # frame behind
	b.box(Vector3(0, 0.046, 0.395), Vector3(0.014, 0.026, 0.028), STEEL, 0.0, 0.5)                     # hammer
	b.box(Vector3(0, -0.07, 0.4), Vector3(0.038, 0.12, 0.06), POLY, 0.0, -0.3)                           # grip
	b.box(Vector3(0.0215, 0.002, 0.3), Vector3(0.004, 0.018, 0.07), glow, 1.0)
	b.box(Vector3(-0.0215, 0.002, 0.3), Vector3(0.004, 0.018, 0.07), glow, 1.0)


static func _smg(b: _Builder, glow: Color) -> void:
	b.box(Vector3(0, 0.0, 0.3), Vector3(0.054, 0.07, 0.4), GUN)                                         # receiver
	b.box(Vector3(0, 0.0, 0.1), Vector3(0.05, 0.062, 0.2), POLY)                                        # handguard
	b.cyl(Vector3(0, 0.002, 0.04), 0.014, 0.08, STEEL)                                                  # barrel and suppressor
	b.cyl(Vector3(0, 0.002, 0.1), 0.026, 0.12, DARK)
	b.box(Vector3(0, 0.0, 0.0), Vector3(0.06, 0.07, 0.014), glow, 1.0)                                  # muzzle ring
	b.box(Vector3(0, 0.0475, 0.3), Vector3(0.02, 0.025, 0.3), STEEL)                                    # top rail
	b.box(Vector3(0, 0.07, 0.3), Vector3(0.03, 0.03, 0.07), DARK)                                       # red dot
	b.box(Vector3(0, 0.07, 0.268), Vector3(0.018, 0.018, 0.004), glow, 1.0)
	b.box(Vector3(0, -0.12, 0.33), Vector3(0.036, 0.19, 0.056), POLY, 0.0, -0.1)                         # long magazine
	b.box(Vector3(0, -0.1, 0.43), Vector3(0.036, 0.1, 0.04), DARK, 0.0, -0.3)                            # grip
	b.box(Vector3(0, -0.085, 0.14), Vector3(0.03, 0.08, 0.04), POLY, 0.0, 0.1)                         # foregrip
	b.box(Vector3(0, 0.005, 0.54), Vector3(0.028, 0.02, 0.24), STEEL)                                   # stock rails
	b.box(Vector3(0, -0.02, 0.66), Vector3(0.04, 0.095, 0.03), POLY)                                    # stock pad
	b.box(Vector3(0.028, 0.0, 0.26), Vector3(0.004, 0.02, 0.22), glow, 1.0)
	b.box(Vector3(-0.028, 0.0, 0.26), Vector3(0.004, 0.02, 0.22), glow, 1.0)


static func _marksman(b: _Builder, glow: Color) -> void:
	b.cyl(Vector3(0, 0.006, 0.2), 0.011, 0.4, STEEL)                                                    # long barrel
	b.cyl(Vector3(0, 0.006, 0.03), 0.02, 0.06, DARK)                                                    # brake
	b.box(Vector3(0, 0.006, 0.0), Vector3(0.05, 0.05, 0.012), glow, 1.0)
	b.box(Vector3(0, 0.0, 0.46), Vector3(0.05, 0.075, 0.28), POLY)                                      # handguard
	b.box(Vector3(0, 0.0, 0.68), Vector3(0.056, 0.08, 0.2), GUN)                                        # receiver
	b.box(Vector3(0, 0.05, 0.62), Vector3(0.024, 0.016, 0.4), STEEL)                                    # top rail
	b.cyl(Vector3(0, 0.085, 0.6), 0.024, 0.24, DARK)                                                    # scope body
	b.cyl(Vector3(0, 0.085, 0.47), 0.032, 0.05, POLY)
	b.cyl(Vector3(0, 0.085, 0.73), 0.028, 0.05, POLY)
	b.box(Vector3(0, 0.085, 0.455), Vector3(0.04, 0.04, 0.004), glow, 1.0)                              # lens
	b.box(Vector3(0, -0.08, 0.64), Vector3(0.036, 0.1, 0.058), DARK)                                    # box magazine
	b.box(Vector3(0, -0.095, 0.77), Vector3(0.036, 0.11, 0.045), POLY, 0.0, -0.3)                        # grip
	b.box(Vector3(0, 0.0, 0.92), Vector3(0.05, 0.085, 0.2), POLY)                                       # stock
	b.box(Vector3(0, 0.05, 0.88), Vector3(0.04, 0.03, 0.14), DARK)                                      # cheek rest
	b.box(Vector3(0, -0.01, 1.03), Vector3(0.044, 0.12, 0.03), DARK)
	b.box(Vector3(0.0285, 0.0, 0.46), Vector3(0.004, 0.02, 0.2), glow, 1.0)
	b.box(Vector3(-0.0285, 0.0, 0.46), Vector3(0.004, 0.02, 0.2), glow, 1.0)


static func _arc(b: _Builder, glow: Color) -> void:
	for sx in [-1.0, 1.0]:                                                                              # two prongs with a spark gap
		b.box(Vector3(0.05 * sx, 0.0, 0.18), Vector3(0.024, 0.04, 0.36), STEEL)
		b.box(Vector3(0.05 * sx, 0.0, 0.01), Vector3(0.05, 0.05, 0.03), glow, 1.0)
		b.box(Vector3(0.034 * sx, 0.0, 0.32), Vector3(0.012, 0.012, 0.06), glow, 1.0)
	b.box(Vector3(0.0, 0.0, 0.34), Vector3(0.12, 0.05, 0.06), POLY)                                     # yoke
	b.box(Vector3(0, 0.0, 0.5), Vector3(0.07, 0.09, 0.26), GUN)                                         # body
	b.cyl(Vector3(0, 0.0, 0.44), 0.05, 0.05, glow, 1.0, 10)                                             # coil
	b.cyl(Vector3(0, 0.0, 0.54), 0.05, 0.05, glow, 1.0, 10)
	b.box(Vector3(0, 0.06, 0.52), Vector3(0.024, 0.03, 0.2), STEEL)                                     # rail
	b.box(Vector3(0, -0.07, 0.4), Vector3(0.034, 0.08, 0.05), POLY)                                     # foregrip
	b.box(Vector3(0, -0.1, 0.62), Vector3(0.036, 0.11, 0.046), DARK, 0.0, -0.3)                          # grip
	b.box(Vector3(0, -0.01, 0.78), Vector3(0.05, 0.1, 0.22), POLY)                                      # stock
	b.box(Vector3(0, -0.09, 0.52), Vector3(0.04, 0.12, 0.07), DARK)                                     # cell


static func _shotgun(b: _Builder, glow: Color, auto: bool) -> void:
	var s := 0.0 if not auto else -0.1                                                                  # the breacher is stubbier
	b.cyl(Vector3(0, 0.012, 0.28 + s), 0.02, 0.56 + 2.0 * s, STEEL)                                      # barrel
	b.cyl(Vector3(0, 0.012, 0.02), 0.032, 0.05, DARK)                                                   # flared muzzle
	b.box(Vector3(0, 0.012, 0.0), Vector3(0.07, 0.07, 0.012), glow, 1.0)
	if not auto:
		b.cyl(Vector3(0, -0.026, 0.26), 0.016, 0.44, GUN)                                               # magazine tube
		b.box(Vector3(0, -0.032, 0.36), Vector3(0.05, 0.05, 0.2), POLY)                                 # the pump
		for k in 4:
			b.box(Vector3(0, -0.032, 0.3 + 0.045 * float(k)), Vector3(0.054, 0.054, 0.01), DARK)
		b.box(Vector3(0, 0.005, 0.62), Vector3(0.056, 0.07, 0.24), GUN)                                 # receiver
		b.box(Vector3(0.0285, 0.005, 0.62), Vector3(0.004, 0.02, 0.18), glow, 1.0)
		b.box(Vector3(-0.0285, 0.005, 0.62), Vector3(0.004, 0.02, 0.18), glow, 1.0)
		b.box(Vector3(0, -0.075, 0.72), Vector3(0.036, 0.1, 0.045), POLY, 0.0, -0.3)                     # grip
		b.box(Vector3(0, -0.005, 0.9), Vector3(0.05, 0.1, 0.24), POLY, 0.0, 0.0)                        # stock
		b.box(Vector3(0, -0.03, 1.04), Vector3(0.046, 0.13, 0.03), DARK)
		b.box(Vector3(0, 0.044, 0.5), Vector3(0.01, 0.014, 0.04), STEEL)                                # bead sight
	else:
		b.cyl(Vector3(0, 0.012, 0.18), 0.042, 0.26, DARK)                                               # heat shield
		for k in 3:
			b.box(Vector3(0, 0.012, 0.1 + 0.07 * float(k)), Vector3(0.09, 0.09, 0.012), glow, 1.0)
		b.box(Vector3(0, 0.005, 0.42), Vector3(0.07, 0.085, 0.3), GUN)                                  # receiver
		b.cyl(Vector3(0, -0.085, 0.4), 0.085, 0.1, POLY, 0.0, 12, Basis(Vector3.UP, PI * 0.5))             # drum magazine (axis across the gun)
		b.box(Vector3(0, 0.06, 0.42), Vector3(0.03, 0.04, 0.22), STEEL)                                 # carry handle
		b.box(Vector3(0, 0.082, 0.42), Vector3(0.02, 0.016, 0.26), POLY)
		b.box(Vector3(0, -0.095, 0.57), Vector3(0.038, 0.11, 0.05), POLY, 0.0, -0.3)                     # grip
		b.box(Vector3(0, -0.04, 0.2), Vector3(0.036, 0.07, 0.05), DARK)                                 # foregrip
		b.box(Vector3(0, -0.005, 0.7), Vector3(0.05, 0.085, 0.16), POLY)                                # stock
		b.box(Vector3(0, -0.02, 0.8), Vector3(0.044, 0.11, 0.03), DARK)
		b.box(Vector3(0.036, 0.005, 0.42), Vector3(0.004, 0.026, 0.22), glow, 1.0)
		b.box(Vector3(-0.036, 0.005, 0.42), Vector3(0.004, 0.026, 0.22), glow, 1.0)


static func _rail(b: _Builder, glow: Color) -> void:
	b.box(Vector3(0, 0.0, 0.5), Vector3(0.05, 0.05, 1.0), GUN)                                          # long barrel shroud
	for k in 5:                                                                                         # coil rings along the barrel
		b.cyl(Vector3(0, 0.0, 0.1 + 0.15 * float(k)), 0.047, 0.04, STEEL, 0.0, 10)
		b.cyl(Vector3(0, 0.0, 0.1 + 0.15 * float(k)), 0.04, 0.052, glow, 0.55, 10)
	b.box(Vector3(0, 0.0, 0.0), Vector3(0.06, 0.06, 0.012), glow, 1.0)
	b.box(Vector3(0, 0.0, 0.86), Vector3(0.06, 0.09, 0.24), POLY)                                       # receiver
	b.box(Vector3(0, 0.06, 0.8), Vector3(0.026, 0.016, 0.36), STEEL)                                    # rail
	b.cyl(Vector3(0, 0.095, 0.7), 0.03, 0.34, DARK)                                                     # scope
	b.cyl(Vector3(0, 0.095, 0.53), 0.04, 0.06, POLY)
	b.cyl(Vector3(0, 0.095, 0.87), 0.036, 0.06, POLY)
	b.box(Vector3(0, 0.095, 0.5), Vector3(0.05, 0.05, 0.004), glow, 1.0)
	b.box(Vector3(0, -0.07, 0.8), Vector3(0.034, 0.09, 0.07), DARK)                                     # magazine
	b.box(Vector3(0, -0.09, 0.9), Vector3(0.036, 0.11, 0.045), POLY, 0.0, -0.3)                          # grip
	b.box(Vector3(0, 0.0, 1.08), Vector3(0.052, 0.09, 0.22), POLY)                                      # stock
	b.box(Vector3(0, 0.055, 1.04), Vector3(0.04, 0.03, 0.14), DARK)
	b.box(Vector3(0, -0.01, 1.2), Vector3(0.046, 0.13, 0.03), DARK)
	b.box(Vector3(0.0275, 0.0, 0.5), Vector3(0.004, 0.012, 0.8), glow, 0.8)
	b.box(Vector3(-0.0275, 0.0, 0.5), Vector3(0.004, 0.012, 0.8), glow, 0.8)
	b.box(Vector3(0.05, -0.05, 0.32), Vector3(0.008, 0.1, 0.008), STEEL, 0.0, 0.5)                      # folded bipod legs
	b.box(Vector3(-0.05, -0.05, 0.32), Vector3(0.008, 0.1, 0.008), STEEL, 0.0, -0.5)


static func _lance(b: _Builder, glow: Color) -> void:
	b.box(Vector3(0, 0.0, 0.62), Vector3(0.04, 0.04, 1.24), GUN)                                        # long spine
	b.box(Vector3(0, 0.0, 0.5), Vector3(0.022, 0.022, 1.0), glow, 1.0)                                  # the glowing core
	for k in 3:
		var z := 0.12 + 0.19 * float(k)
		b.box(Vector3(0, 0.0, z), Vector3(0.24 - 0.04 * float(k), 0.014, 0.12), STEEL)                  # fins, wide at the tip
		b.box(Vector3(0, 0.0, z + 0.09), Vector3(0.016, 0.2 - 0.04 * float(k), 0.1), STEEL)
	b.box(Vector3(0, 0.0, 0.0), Vector3(0.05, 0.05, 0.012), glow, 1.0)
	b.box(Vector3(0, 0.0, 0.88), Vector3(0.07, 0.1, 0.3), POLY)                                         # body
	b.box(Vector3(0, -0.09, 0.9), Vector3(0.04, 0.09, 0.05), DARK, 0.0, -0.3)                            # grip
	b.box(Vector3(0, -0.07, 0.52), Vector3(0.034, 0.08, 0.05), POLY)                                    # foregrip
	b.cyl(Vector3(0, 0.07, 0.84), 0.026, 0.2, DARK)                                                     # scope
	b.box(Vector3(0, 0.07, 0.74), Vector3(0.04, 0.04, 0.004), glow, 1.0)
	b.box(Vector3(0, 0.0, 1.14), Vector3(0.06, 0.1, 0.16), POLY)                                        # butt
	b.box(Vector3(0, 0.0, 1.24), Vector3(0.05, 0.13, 0.03), DARK)


static func _gravity(b: _Builder, glow: Color) -> void:
	b.cyl(Vector3(0, 0.0, 0.26), 0.058, 0.52, GUN, 0.0, 12)                                             # fat launcher tube
	b.cyl(Vector3(0, 0.0, 0.03), 0.078, 0.06, STEEL, 0.0, 12)                                           # flared muzzle
	b.cyl(Vector3(0, 0.0, 0.0), 0.07, 0.014, glow, 1.0, 12)
	b.cyl(Vector3(0, 0.0, 0.4), 0.084, 0.06, STEEL, 0.0, 12)                                            # reinforcing bands
	b.cyl(Vector3(0, 0.0, 0.4), 0.074, 0.07, glow, 0.5, 12)
	b.cyl(Vector3(0, 0.0, 0.54), 0.09, 0.2, POLY, 0.0, 12)                                              # revolving drum
	b.cyl(Vector3(0, 0.0, 0.54), 0.094, 0.015, STEEL, 0.0, 12)
	b.box(Vector3(0, 0.1, 0.4), Vector3(0.012, 0.07, 0.1), STEEL)                                       # ladder sight
	b.box(Vector3(0, 0.138, 0.4), Vector3(0.05, 0.01, 0.01), STEEL)
	b.box(Vector3(0, -0.11, 0.62), Vector3(0.04, 0.1, 0.05), DARK, 0.0, -0.3)                            # grip
	b.box(Vector3(0, -0.09, 0.3), Vector3(0.036, 0.09, 0.05), POLY)                                     # foregrip
	b.box(Vector3(0, -0.02, 0.76), Vector3(0.05, 0.1, 0.18), POLY)                                      # stock
	b.box(Vector3(0, -0.03, 0.86), Vector3(0.046, 0.13, 0.03), DARK)


static func _rocket(b: _Builder, glow: Color) -> void:
	b.cyl(Vector3(0, 0.0, 0.46), 0.085, 0.92, GUN, 0.0, 12)                                             # the tube
	b.cyl(Vector3(0, 0.0, 0.03), 0.105, 0.07, STEEL, 0.0, 12)                                           # flared muzzle
	b.cyl(Vector3(0, 0.0, 0.0), 0.1, 0.014, glow, 1.0, 12)
	b.cyl(Vector3(0, 0.0, 0.95), 0.108, 0.1, STEEL, 0.0, 12)                                            # exhaust flare
	b.cyl(Vector3(0, 0.0, 0.2), 0.092, 0.02, glow, 0.7, 12)                                             # glowing bands
	b.cyl(Vector3(0, 0.0, 0.7), 0.092, 0.02, glow, 0.7, 12)
	b.box(Vector3(0, 0.13, 0.5), Vector3(0.03, 0.05, 0.2), DARK)                                        # optic
	b.box(Vector3(0, 0.162, 0.5), Vector3(0.05, 0.014, 0.14), POLY)
	b.box(Vector3(0, 0.162, 0.43), Vector3(0.03, 0.01, 0.004), glow, 1.0)
	b.box(Vector3(0, -0.13, 0.62), Vector3(0.04, 0.1, 0.05), DARK, 0.0, -0.3)                            # grip
	b.box(Vector3(0, -0.12, 0.3), Vector3(0.036, 0.09, 0.05), POLY)                                     # foregrip
	b.box(Vector3(0, -0.075, 0.5), Vector3(0.05, 0.05, 0.3), POLY)                                      # rail under the tube


static func _minigun(b: _Builder, glow: Color) -> void:
	for k in 6:                                                                                         # six barrels around the axis
		var a := TAU * float(k) / 6.0
		b.cyl(Vector3(cos(a) * 0.055, sin(a) * 0.055, 0.3), 0.017, 0.6, STEEL, 0.0, 8)
	b.cyl(Vector3(0, 0.0, 0.0), 0.085, 0.03, DARK, 0.0, 12)                                             # muzzle clamp
	b.cyl(Vector3(0, 0.0, 0.0), 0.08, 0.012, glow, 1.0, 12)
	b.cyl(Vector3(0, 0.0, 0.32), 0.09, 0.03, STEEL, 0.0, 12)                                            # middle clamp
	b.cyl(Vector3(0, 0.0, 0.62), 0.11, 0.22, GUN, 0.0, 12)                                              # housing
	b.cyl(Vector3(0, 0.0, 0.5), 0.1, 0.02, glow, 0.7, 12)
	b.box(Vector3(0, 0.1, 0.62), Vector3(0.03, 0.06, 0.22), POLY)                                       # carry handle
	b.box(Vector3(0, 0.14, 0.62), Vector3(0.04, 0.02, 0.26), DARK)
	b.box(Vector3(0, -0.14, 0.62), Vector3(0.14, 0.12, 0.2), POLY)                                      # ammo drum
	b.box(Vector3(0, -0.12, 0.3), Vector3(0.036, 0.1, 0.05), DARK)                                      # front handle
	b.box(Vector3(0, -0.13, 0.6), Vector3(0.04, 0.09, 0.05), DARK, 0.0, -0.3)                            # grip
	b.box(Vector3(0, 0.0, 0.8), Vector3(0.1, 0.12, 0.08), POLY)                                         # rear


static func _grenade(b: _Builder, glow: Color) -> void:
	b.cyl(Vector3(0, 0.0, 0.14), 0.05, 0.1, GUN, 0.0, 12)                                               # the singularity grenade: a canister with a glowing band
	b.cyl(Vector3(0, 0.0, 0.14), 0.054, 0.03, glow, 1.0, 12)
	b.cyl(Vector3(0, 0.0, 0.07), 0.034, 0.04, STEEL, 0.0, 10)
	b.cyl(Vector3(0, 0.0, 0.205), 0.04, 0.03, STEEL, 0.0, 10)
	b.box(Vector3(0.0, 0.052, 0.11), Vector3(0.012, 0.012, 0.06), STEEL)                                # the pin and lever
	b.box(Vector3(0.0, 0.058, 0.17), Vector3(0.016, 0.01, 0.07), STEEL)


static func _blade(b: _Builder, glow: Color) -> void:
	b.box(Vector3(0, 0.0, 0.4), Vector3(0.006, 0.07, 0.8), STEEL)                                       # blade
	b.box(Vector3(0, 0.0, 0.4), Vector3(0.008, 0.05, 0.78), glow, 0.9)                                  # glowing edge core
	b.box(Vector3(0, 0.0, 0.0), Vector3(0.004, 0.04, 0.012), glow, 1.0)                                 # tip
	b.box(Vector3(0, 0.0, 0.82), Vector3(0.026, 0.2, 0.03), GUN)                                        # guard
	b.box(Vector3(0, 0.1, 0.82), Vector3(0.036, 0.02, 0.04), STEEL)
	b.box(Vector3(0, -0.1, 0.82), Vector3(0.036, 0.02, 0.04), STEEL)
	b.cyl(Vector3(0, 0.0, 0.95), 0.016, 0.24, POLY, 0.0, 8)                                             # handle
	for k in 4:
		b.cyl(Vector3(0, 0.0, 0.88 + 0.05 * float(k)), 0.0185, 0.012, DARK, 0.0, 8)
	b.cyl(Vector3(0, 0.0, 1.08), 0.024, 0.03, STEEL, 0.0, 8)                                            # pommel
	b.cyl(Vector3(0, 0.0, 1.1), 0.012, 0.012, glow, 1.0, 8)


static func _whip(b: _Builder, glow: Color) -> void:
	b.cyl(Vector3(0, 0.0, 0.3), 0.022, 0.36, POLY, 0.0, 8)                                              # handle
	for k in 5:
		b.cyl(Vector3(0, 0.0, 0.17 + 0.07 * float(k)), 0.0255, 0.012, DARK, 0.0, 8)
	b.cyl(Vector3(0, 0.0, 0.09), 0.04, 0.06, STEEL, 0.0, 10)                                            # emitter
	b.cyl(Vector3(0, 0.0, 0.04), 0.03, 0.05, glow, 1.0, 10)
	b.cyl(Vector3(0, 0.0, 0.5), 0.03, 0.04, STEEL, 0.0, 10)                                             # pommel
	b.box(Vector3(0, 0.0, -0.1), Vector3(0.008, 0.008, 0.2), glow, 1.0)                                 # a short tendril of the whip
	b.box(Vector3(0.012, 0.0, -0.24), Vector3(0.006, 0.006, 0.1), glow, 1.0)


## ROUND 5: weapons without an open model (generic shapes, the glow of the quantum look on the parts that matter).
static func _lmg(b: _Builder, glow: Color) -> void:                                                     # fallback shape when the open model is missing
	_marksman(b, glow)
	b.box(Vector3(0, -0.14, 0.5), Vector3(0.1, 0.14, 0.14), DARK)                                       # the box magazine under the receiver


static func _amr(b: _Builder, glow: Color) -> void:
	_rail(b, glow)


static func _xbow(b: _Builder, glow: Color) -> void:
	b.box(Vector3(0, 0.0, 0.34), Vector3(0.05, 0.06, 0.62), GUN)                                        # stock and rail
	b.box(Vector3(0, 0.035, 0.28), Vector3(0.026, 0.016, 0.52), STEEL)                                  # flight rail on top
	b.cyl(Vector3(0, 0.05, 0.2), 0.007, 0.36, BRASS, 0.0, 6)                                            # the bolt
	b.box(Vector3(0, 0.05, 0.02), Vector3(0.016, 0.016, 0.04), glow, 1.0)                               # the bolt's glowing head
	for sx in [-1.0, 1.0]:                                                                              # the prod: thick limbs sweeping back to glowing tips
		b.box(Vector3(0.075 * sx, 0.0, 0.125), Vector3(0.15, 0.026, 0.05), POLY)
		b.box(Vector3(0.17 * sx, 0.0, 0.145), Vector3(0.07, 0.024, 0.04), GUN)
		b.box(Vector3(0.225 * sx, 0.0, 0.175), Vector3(0.05, 0.022, 0.036), GUN)
		b.box(Vector3(0.255 * sx, 0.0, 0.2), Vector3(0.02, 0.024, 0.03), glow, 1.0)                      # glowing tip
	b.box(Vector3(0, 0.0, 0.2), Vector3(0.5, 0.006, 0.006), glow, 0.7)                                  # the string
	b.box(Vector3(0, 0.0, 0.2), Vector3(0.04, 0.05, 0.03), STEEL)                                       # latch
	b.box(Vector3(0, 0.0, 0.0), Vector3(0.05, 0.05, 0.05), STEEL)                                       # the foot stirrup
	b.cyl(Vector3(0, 0.075, 0.42), 0.02, 0.16, DARK, 0.0, 8)                                            # small scope
	b.box(Vector3(0, 0.075, 0.33), Vector3(0.036, 0.036, 0.004), glow, 1.0)
	b.box(Vector3(0, -0.085, 0.44), Vector3(0.034, 0.1, 0.046), DARK, 0.0, -0.3)                         # grip
	b.box(Vector3(0, -0.01, 0.64), Vector3(0.05, 0.08, 0.2), POLY)                                      # stock
	b.box(Vector3(0, -0.015, 0.75), Vector3(0.044, 0.11, 0.03), DARK)


static func _flame(b: _Builder, glow: Color) -> void:
	b.cyl(Vector3(0, 0.0, 0.3), 0.026, 0.6, STEEL, 0.0, 8)                                              # the lance
	b.cyl(Vector3(0, 0.0, 0.03), 0.044, 0.07, DARK, 0.0, 10)                                            # nozzle
	b.cyl(Vector3(0, 0.0, 0.0), 0.034, 0.012, glow, 1.0, 10)                                            # the pilot light
	b.box(Vector3(0, 0.03, 0.01), Vector3(0.016, 0.03, 0.016), glow, 1.0)
	for k in 3:
		b.cyl(Vector3(0, 0.0, 0.2 + 0.12 * float(k)), 0.034, 0.02, POLY, 0.0, 8)                        # heat rings
	b.box(Vector3(0, 0.0, 0.62), Vector3(0.08, 0.1, 0.22), GUN)                                         # valve body
	b.cyl(Vector3(0, -0.14, 0.62), 0.07, 0.46, GUN, 0.0, 12)                                            # the fuel tank under the gun
	b.cyl(Vector3(0, -0.14, 0.62), 0.074, 0.05, glow, 0.7, 12)                                          # glowing fuel band
	b.cyl(Vector3(0, -0.14, 0.44), 0.074, 0.03, STEEL, 0.0, 12)
	b.cyl(Vector3(0, -0.14, 0.8), 0.074, 0.03, STEEL, 0.0, 12)
	b.box(Vector3(0, -0.07, 0.62), Vector3(0.016, 0.06, 0.016), DARK)                                   # feed hose
	b.box(Vector3(0, -0.1, 0.3), Vector3(0.034, 0.09, 0.05), POLY)                                      # foregrip
	b.box(Vector3(0, -0.07, 0.76), Vector3(0.036, 0.1, 0.045), DARK, 0.0, -0.3)                          # grip
	b.box(Vector3(0, 0.0, 0.8), Vector3(0.05, 0.08, 0.14), POLY)                                        # stock


static func _stun(b: _Builder, glow: Color) -> void:
	b.box(Vector3(0, 0.0, 0.12), Vector3(0.05, 0.07, 0.24), GUN)                                        # body
	b.box(Vector3(0, 0.0, 0.12), Vector3(0.056, 0.03, 0.16), POLY)
	b.box(Vector3(0.026, 0.0, 0.1), Vector3(0.004, 0.026, 0.12), glow, 1.0)
	b.box(Vector3(-0.026, 0.0, 0.1), Vector3(0.004, 0.026, 0.12), glow, 1.0)
	for sx in [-1.0, 1.0]:                                                                              # two electrode prongs with a spark gap
		b.box(Vector3(0.022 * sx, 0.0, -0.025), Vector3(0.008, 0.012, 0.07), STEEL)
		b.box(Vector3(0.022 * sx, 0.0, -0.062), Vector3(0.012, 0.016, 0.014), glow, 1.0)
	b.box(Vector3(0, 0.0, -0.062), Vector3(0.03, 0.004, 0.004), glow, 1.0)
	b.box(Vector3(0, -0.085, 0.16), Vector3(0.036, 0.105, 0.046), DARK, 0.0, -0.28)                      # grip
	b.box(Vector3(0, -0.04, 0.12), Vector3(0.012, 0.03, 0.05), POLY)                                    # trigger guard


static func _katana(b: _Builder, glow: Color) -> void:
	for k in 3:                                                                                         # a blade with the slight curve of a katana: three tilted segments
		b.box(Vector3(0, 0.0, 0.15 + 0.3 * float(k)), Vector3(0.006, 0.05, 0.3), STEEL, 0.0, -0.03 + 0.015 * float(k))
		b.box(Vector3(0, 0.0, 0.15 + 0.3 * float(k)), Vector3(0.008, 0.008, 0.3), glow, 0.6, -0.03 + 0.015 * float(k))   # the glowing edge line
	b.box(Vector3(0, 0.0, 0.0), Vector3(0.004, 0.02, 0.012), glow, 1.0)                                 # tip
	b.cyl(Vector3(0, 0.0, 0.91), 0.034, 0.008, GUN, 0.0, 12)                                            # tsuba: a round guard
	b.cyl(Vector3(0, 0.0, 0.905), 0.036, 0.004, glow, 0.8, 12)
	b.cyl(Vector3(0, 0.0, 1.07), 0.015, 0.3, DARK, 0.0, 8)                                              # wrapped handle
	for k in 6:
		b.cyl(Vector3(0, 0.0, 0.95 + 0.047 * float(k)), 0.0175, 0.012, POLY, 0.0, 8)
	b.cyl(Vector3(0, 0.0, 1.225), 0.02, 0.016, STEEL, 0.0, 8)                                           # pommel


static func _bat(b: _Builder, glow: Color) -> void:
	var wood := Color(0.5, 0.34, 0.18)
	b.cyl(Vector3(0, 0.0, 0.22), 0.044, 0.44, wood, 0.0, 10)                                            # the barrel of the bat
	b.cyl(Vector3(0, 0.0, 0.0), 0.042, 0.012, wood.darkened(0.3), 0.0, 10)                              # capped end
	b.cyl(Vector3(0, 0.0, 0.5), 0.034, 0.14, wood, 0.0, 10)                                             # taper
	b.cyl(Vector3(0, 0.0, 0.62), 0.021, 0.12, wood, 0.0, 10)
	b.cyl(Vector3(0, 0.0, 0.8), 0.015, 0.26, DARK, 0.0, 8)                                              # taped grip
	for k in 4:
		b.cyl(Vector3(0, 0.0, 0.72 + 0.06 * float(k)), 0.0165, 0.008, POLY, 0.0, 8)
	b.cyl(Vector3(0, 0.0, 0.945), 0.024, 0.03, wood.darkened(0.15), 0.0, 8)                             # knob
	b.cyl(Vector3(0, 0.0, 0.3), 0.0455, 0.03, glow, 0.9, 10)                                            # a glowing sweet-spot band
	b.cyl(Vector3(0, 0.0, 0.14), 0.0455, 0.012, glow, 0.9, 10)


static func _qsuper(b: _Builder, glow: Color) -> void:                                                  # SUPERPOSITION: two barrels, one real and one echo
	for sx in [-1.0, 1.0]:
		b.cyl(Vector3(0.032 * sx, 0.0, 0.2), 0.016, 0.4, STEEL if sx > 0.0 else POLY, 0.0, 8)
		b.tube(Vector3(0.032 * sx, 0.0, 0.012), 0.03, 0.017, 0.024, glow, 1.0 if sx > 0.0 else 0.45, 10)   # muzzle ring: bright for the real shot, dim for the echo
	b.tube(Vector3(0, 0.0, 0.2), 0.062, 0.05, 0.016, glow, 0.8, 12)                                     # a split ring around both
	b.box(Vector3(0, 0.0, 0.5), Vector3(0.09, 0.09, 0.3), GUN)                                          # receiver
	b.box(Vector3(0, 0.0, 0.5), Vector3(0.094, 0.02, 0.22), glow, 0.9)
	b.box(Vector3(0, 0.06, 0.5), Vector3(0.024, 0.02, 0.2), STEEL)
	b.box(Vector3(0, -0.09, 0.62), Vector3(0.038, 0.11, 0.046), DARK, 0.0, -0.3)                         # grip
	b.box(Vector3(0, -0.07, 0.34), Vector3(0.034, 0.08, 0.05), POLY)                                    # foregrip
	b.box(Vector3(0, -0.01, 0.76), Vector3(0.05, 0.09, 0.2), POLY)                                      # stock
	b.box(Vector3(0, -0.02, 0.86), Vector3(0.044, 0.12, 0.03), DARK)


static func _qlink(b: _Builder, glow: Color) -> void:                                                   # ENTANGLE: two emitter prongs with a glowing link between them
	for sx in [-1.0, 1.0]:
		b.box(Vector3(0.06 * sx, 0.0, 0.14), Vector3(0.022, 0.05, 0.28), STEEL)
		b.box(Vector3(0.06 * sx, 0.0, 0.01), Vector3(0.036, 0.06, 0.03), glow, 1.0)
	b.box(Vector3(0, 0.0, 0.01), Vector3(0.1, 0.008, 0.008), glow, 1.0)                                 # the link across the gap
	b.box(Vector3(0, 0.0, 0.14), Vector3(0.1, 0.008, 0.008), glow, 0.7)
	b.box(Vector3(0, 0.0, 0.34), Vector3(0.1, 0.07, 0.12), POLY)                                        # yoke
	b.cyl(Vector3(0, 0.0, 0.5), 0.05, 0.22, GUN, 0.0, 12)                                               # coil housing
	b.cyl(Vector3(0, 0.0, 0.5), 0.054, 0.03, glow, 1.0, 12)
	b.cyl(Vector3(0, 0.0, 0.58), 0.054, 0.03, glow, 1.0, 12)
	b.box(Vector3(0, -0.09, 0.56), Vector3(0.036, 0.11, 0.046), DARK, 0.0, -0.3)                         # grip
	b.box(Vector3(0, -0.07, 0.34), Vector3(0.034, 0.08, 0.05), POLY)
	b.box(Vector3(0, -0.01, 0.74), Vector3(0.05, 0.09, 0.18), POLY)
	b.box(Vector3(0, -0.02, 0.84), Vector3(0.044, 0.12, 0.03), DARK)


static func _qcollapse(b: _Builder, glow: Color) -> void:                                               # COLLAPSE CANNON: a funnel muzzle around a glowing core
	b.tube(Vector3(0, 0.0, 0.03), 0.11, 0.085, 0.06, STEEL, 0.0, 14)                                    # the funnel: two hollow rings, wide at the mouth
	b.tube(Vector3(0, 0.0, 0.1), 0.095, 0.07, 0.08, GUN, 0.0, 14)
	b.tube(Vector3(0, 0.0, 0.0), 0.108, 0.088, 0.014, glow, 1.0, 14)                                    # glowing mouth rim
	b.cyl(Vector3(0, 0.0, 0.14), 0.07, 0.01, glow, 0.35, 12)                                            # the dim core deep inside
	b.cyl(Vector3(0, 0.0, 0.3), 0.075, 0.36, GUN, 0.0, 12)                                              # tube
	b.cyl(Vector3(0, 0.0, 0.3), 0.08, 0.03, glow, 0.9, 12)
	b.cyl(Vector3(0, 0.0, 0.42), 0.08, 0.03, glow, 0.9, 12)
	b.cyl(Vector3(0, 0.0, 0.56), 0.1, 0.2, POLY, 0.0, 12)                                               # the energy cell
	b.cyl(Vector3(0, 0.0, 0.56), 0.104, 0.05, glow, 1.0, 12)
	b.box(Vector3(0, 0.12, 0.42), Vector3(0.03, 0.05, 0.16), DARK)                                      # optic
	b.box(Vector3(0, 0.15, 0.42), Vector3(0.05, 0.012, 0.12), POLY)
	b.box(Vector3(0, -0.13, 0.64), Vector3(0.04, 0.1, 0.05), DARK, 0.0, -0.3)                            # grip
	b.box(Vector3(0, -0.12, 0.32), Vector3(0.036, 0.09, 0.05), POLY)                                    # foregrip
	b.box(Vector3(0, -0.01, 0.8), Vector3(0.06, 0.1, 0.2), POLY)                                        # shoulder rest
	b.box(Vector3(0, -0.02, 0.9), Vector3(0.05, 0.13, 0.03), DARK)


static func _qblink(b: _Builder, glow: Color) -> void:                                                  # BLINK PISTOL: a ring emitter on the muzzle
	_pistol(b, glow, 1.0)
	b.tube(Vector3(0, 0.0, -0.01), 0.052, 0.038, 0.012, glow, 1.0, 14)                                  # the blink ring
	b.tube(Vector3(0, 0.0, 0.004), 0.034, 0.02, 0.016, STEEL, 0.0, 10)
	b.box(Vector3(0, 0.0, -0.034), Vector3(0.012, 0.012, 0.03), glow, 1.0)


static func _qphase(b: _Builder, glow: Color) -> void:                                                  # PHASE RIFLE: an open frame of ribs, half in, half out of this world
	b.box(Vector3(0, 0.0, 0.34), Vector3(0.026, 0.026, 0.68), STEEL)                                    # the spine
	for k in 7:
		var z := 0.06 + 0.1 * float(k)
		b.box(Vector3(0, 0.0, z), Vector3(0.09 - 0.006 * float(k), 0.012, 0.014), glow, 0.9)            # horizontal ribs
		b.box(Vector3(0, 0.0, z), Vector3(0.012, 0.09 - 0.006 * float(k), 0.014), glow, 0.6)            # vertical ribs
	b.box(Vector3(0, 0.0, 0.0), Vector3(0.05, 0.05, 0.012), glow, 1.0)
	b.box(Vector3(0, 0.0, 0.78), Vector3(0.07, 0.09, 0.22), GUN)                                        # receiver
	b.box(Vector3(0, 0.06, 0.76), Vector3(0.024, 0.016, 0.3), STEEL)
	b.box(Vector3(0, -0.09, 0.8), Vector3(0.036, 0.11, 0.046), DARK, 0.0, -0.3)                          # grip
	b.box(Vector3(0, -0.07, 0.58), Vector3(0.034, 0.08, 0.05), POLY)
	b.box(Vector3(0, 0.0, 1.0), Vector3(0.05, 0.09, 0.2), POLY)                                         # stock
	b.box(Vector3(0, -0.01, 1.11), Vector3(0.044, 0.12, 0.03), DARK)


static func _qstasis(b: _Builder, glow: Color) -> void:                                                 # STASIS RAY: an emitter dish on a body, a tank on top
	b.tube(Vector3(0, 0.0, 0.02), 0.078, 0.052, 0.02, glow, 1.0, 14)                                    # the dish rim
	b.cyl(Vector3(0, 0.0, 0.035), 0.05, 0.01, glow, 0.3, 12)
	b.cyl(Vector3(0, 0.0, 0.07), 0.05, 0.08, STEEL, 0.0, 12)
	b.cyl(Vector3(0, 0.0, 0.2), 0.034, 0.2, GUN, 0.0, 10)                                               # barrel with ice-blue rings
	for k in 3:
		b.cyl(Vector3(0, 0.0, 0.14 + 0.07 * float(k)), 0.04, 0.016, glow, 0.8, 10)
	b.box(Vector3(0, 0.0, 0.46), Vector3(0.08, 0.09, 0.3), POLY)                                        # body
	b.cyl(Vector3(0, 0.07, 0.46), 0.036, 0.26, DARK, 0.0, 10)                                           # coolant tank on top
	b.cyl(Vector3(0, 0.07, 0.46), 0.039, 0.04, glow, 0.7, 10)
	b.box(Vector3(0, -0.09, 0.56), Vector3(0.036, 0.11, 0.046), DARK, 0.0, -0.3)                         # grip
	b.box(Vector3(0, -0.07, 0.32), Vector3(0.034, 0.08, 0.05), POLY)
	b.box(Vector3(0, -0.01, 0.7), Vector3(0.05, 0.09, 0.18), POLY)
	b.box(Vector3(0, -0.02, 0.8), Vector3(0.044, 0.12, 0.03), DARK)


# --- material, icon, geometry helpers --------------------------------------------------------------------------------------

## A weapon crate for the world (about 1.1 x 0.7 x 0.7 m, origin at its base): dark body, a glowing band and a glowing lid plate; tint it per instance (the glow follows the tint).
static func crate_mesh() -> ArrayMesh:
	if _cache.has(&"_crate"):
		return _cache[&"_crate"]
	var b := _Builder.new()
	var w := Color(1, 1, 1)
	b.box(Vector3(0, 0.3, 0), Vector3(1.1, 0.6, 0.7), GUN.lightened(0.05))
	b.box(Vector3(0, 0.62, 0), Vector3(1.16, 0.06, 0.76), STEEL.darkened(0.3))                  # lid rim
	b.box(Vector3(0, 0.655, 0), Vector3(0.8, 0.02, 0.4), w, 1.0)                                 # glowing lid plate
	for sx in [-1.0, 1.0]:
		b.box(Vector3(0.4 * sx, 0.3, 0), Vector3(0.06, 0.64, 0.74), STEEL.darkened(0.45))        # straps
		b.box(Vector3(0.4 * sx, 0.3, 0.371), Vector3(0.05, 0.4, 0.01), w, 1.0)
		b.box(Vector3(0.4 * sx, 0.3, -0.371), Vector3(0.05, 0.4, 0.01), w, 1.0)
	b.box(Vector3(0.0, 0.3, 0.356), Vector3(0.3, 0.12, 0.02), DARK)                              # latch
	b.box(Vector3(0.0, 0.3, -0.356), Vector3(0.3, 0.12, 0.02), DARK)
	var m := b.build()
	_cache[&"_crate"] = m
	return m


## The shared material (one for every weapon): vertex colour albedo, the alpha channel glows; `glow` is pulsed by the shots.
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://assets/shaders/weapon_look.gdshader")
	return _material


## Length of the weapon behind the muzzle (metres).
static func length_of(id: StringName) -> float:
	var m := mesh(id)
	return m.get_aabb().end.z if m != null else 0.0


static func spec(id: StringName) -> Dictionary:
	return SPEC.get(id, SPEC[&"carbine"])


## How far the muzzle node moves BACK along the rifle for this weapon (a pistol's muzzle is nearer the body than the carbine's).
static func muzzle_shift(id: StringName) -> float:
	return CARBINE_REACH - float(spec(id)["reach"])


## Per-hand grip offsets for the rig, in the rifle frame relative to the carbine's wrists: [left, right]. Both are added to the rest wrist targets (CharacterRig `grip_off`).
static func grip_offsets(id: StringName) -> Array[Vector3]:
	var sp := spec(id)
	var reach := float(sp["reach"])
	var gr: Vector3 = sp["gr"]
	var gl: Vector3 = sp["gl"]
	var sr := Vector3(gr.x, gr.y, gr.z - reach) - Vector3(CARBINE_GR.x, CARBINE_GR.y, CARBINE_GR.z - CARBINE_REACH)
	var sl := Vector3(gl.x, gl.y, gl.z - reach) - Vector3(CARBINE_GL.x, CARBINE_GL.y, CARBINE_GL.z - CARBINE_REACH)
	return [sl, sr]


class _Builder extends RefCounted:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	## A box: `center`, full `size`, colour; `glow` 0..1 goes into the colour's alpha; `rx` tilts it about X (a raked grip: positive leans the top forward... toward -Z).
	func box(center: Vector3, size: Vector3, color: Color, glow := 0.0, rx := 0.0) -> void:
		var h := size * 0.5
		var c := Color(color.r, color.g, color.b, glow)
		var rot := Basis(Vector3.RIGHT, rx)
		for axis in 3:
			for sgn in [-1.0, 1.0]:
				var n := Vector3.ZERO
				n[axis] = sgn
				var u := Vector3.ZERO
				u[(axis + 1) % 3] = 1.0
				var v := n.cross(u)
				var base := verts.size()
				for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var local: Vector3 = n * h[axis] + u * (q.x * h[(axis + 1) % 3]) + v * (q.y * h[(axis + 2) % 3])
					verts.append(center + rot * local)
					norms.append(rot * n)
					cols.append(c)
				idx.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))      # u x v = n: counter-clockwise from outside, Godot's front face is clockwise

	## A cylinder along Z (length `len`), `sides` sides, centred at `center`, smooth sides and flat caps.
	func cyl(center: Vector3, radius: float, len: float, color: Color, glow := 0.0, sides := 8, rot := Basis.IDENTITY) -> void:
		var c := Color(color.r, color.g, color.b, glow)
		var base := verts.size()
		for k in sides:
			var a := TAU * float(k) / float(sides)
			var n := Vector3(cos(a), sin(a), 0.0)
			for zz in [-0.5, 0.5]:
				verts.append(center + rot * Vector3(n.x * radius, n.y * radius, zz * len))
				norms.append(rot * n)
				cols.append(c)
		for k in sides:
			var i0 := base + k * 2
			var i1 := base + ((k + 1) % sides) * 2
			idx.append_array(PackedInt32Array([i0, i0 + 1, i1, i1, i0 + 1, i1 + 1]))
		for zz in [-0.5, 0.5]:                                       # the two caps
			var cb := verts.size()
			verts.append(center + rot * Vector3(0.0, 0.0, zz * len))
			norms.append(rot * Vector3(0.0, 0.0, signf(zz)))
			cols.append(c)
			for k in sides:
				var a := TAU * float(k) / float(sides)
				verts.append(center + rot * Vector3(cos(a) * radius, sin(a) * radius, zz * len))
				norms.append(rot * Vector3(0.0, 0.0, signf(zz)))
				cols.append(c)
			for k in sides:
				var a0 := cb + 1 + k
				var a1 := cb + 1 + (k + 1) % sides
				if zz > 0.0:
					idx.append_array(PackedInt32Array([cb, a1, a0]))
				else:
					idx.append_array(PackedInt32Array([cb, a0, a1]))

	## A quad from four corners in any order of winding; `n` is its outward normal (the winding is fixed to Godot's clockwise front face).
	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, color: Color, glow := 0.0) -> void:
		var c := Color(color.r, color.g, color.b, glow)
		var base := verts.size()
		for p: Vector3 in [p0, p1, p2, p3]:
			verts.append(p)
			norms.append(n)
			cols.append(c)
		if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:                    # counter-clockwise from outside: Godot's front face is clockwise
			idx.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
		else:
			idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

	## A hollow tube along Z (an emitter ring, a funnel): outer radius, inner radius, length, flat annular caps, inner wall facing the axis.
	func tube(center: Vector3, r_out: float, r_in: float, len: float, color: Color, glow := 0.0, sides := 12) -> void:
		var hz := len * 0.5
		for k in sides:
			var a0 := TAU * float(k) / float(sides)
			var a1 := TAU * float(k + 1) / float(sides)
			var am := (a0 + a1) * 0.5
			var rad := Vector3(cos(am), sin(am), 0.0)
			var d0 := Vector3(cos(a0), sin(a0), 0.0)
			var d1 := Vector3(cos(a1), sin(a1), 0.0)
			var zf := Vector3(0.0, 0.0, hz)
			var zb := Vector3(0.0, 0.0, -hz)
			quad(center + d0 * r_out + zb, center + d1 * r_out + zb, center + d1 * r_out + zf, center + d0 * r_out + zf, rad, color, glow)
			quad(center + d0 * r_in + zb, center + d1 * r_in + zb, center + d1 * r_in + zf, center + d0 * r_in + zf, -rad, color, glow)
			quad(center + d0 * r_in + zf, center + d0 * r_out + zf, center + d1 * r_out + zf, center + d1 * r_in + zf, Vector3(0, 0, 1), color, glow)
			quad(center + d0 * r_in + zb, center + d0 * r_out + zb, center + d1 * r_out + zb, center + d1 * r_in + zb, Vector3(0, 0, -1), color, glow)

	func build() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m
