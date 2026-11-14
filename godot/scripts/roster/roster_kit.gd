class_name RosterKit
extends RefCounted
## The bodies of the roster-2 enemies (wave 108): 19 procedural meshes, each ONE surface and ONE draw call (AlienMesh: lofted tubes, ellipsoids, cones, boxes), vertex colour = paint, alpha = the glow mask of
## assets/shaders/alien.gdshader. Final size in metres, facing -Z (the back is +Z), standing on y = 0 (the gunship hangs around y = 0). No textures: no texture memory. The plate brute's armour plates are
## three more small meshes (one per plate) so a broken plate can disappear on its own. Every body reads at phone distance by SILHOUETTE first (shield slab, jetpack, long beam rifle, spider legs, rotor
## ring, launcher tube, white pack), then by colour (faction paint) and by glow (the role accent: the weak points always glow).
##   setup_body(c, id, w)   the shared body set-up of RosterFoe and RosterBoss (material, mesh, hit spheres, weak points, groups)
##   HIP                    the height under which the `stride` shader swings the legs (assets/shaders/alien.gdshader)

static var _meshes := {}
const HIP := {&"hiveling": 0.0, &"shield_bearer": 0.95, &"jet_elite": 0.95, &"veil_stalker": 1.0, &"plate_brute": 1.2, &"beam_sniper": 1.2, &"strider": 3.0, &"merc_rifle": 0.95, &"merc_rocket": 0.95,
	&"merc_shotgun": 0.95, &"merc_sniper": 0.9, &"merc_medic": 0.95, &"mountain_titan": 4.2, &"mech_colossus": 4.6}


static func G(c: Color, a := 0.99) -> Color:
	return Color(c.r, c.g, c.b, a)


static func mesh_of(proc: StringName) -> ArrayMesh:
	if _meshes.has(proc):
		return _meshes[proc]
	var m: ArrayMesh = null
	match proc:
		&"hiveling": m = hiveling()
		&"shield_bearer": m = shield_bearer()
		&"jet_elite": m = jet_elite()
		&"veil_stalker": m = veil_stalker()
		&"plate_brute": m = plate_brute()
		&"beam_sniper": m = beam_sniper()
		&"strider": m = strider()
		&"crawler": m = crawler()
		&"wasp_drone": m = wasp_drone()
		&"auto_turret": m = auto_turret()
		&"merc_rifle", &"merc_rocket", &"merc_shotgun", &"merc_sniper", &"merc_medic": m = merc(proc)
		&"mountain_titan": m = mountain_titan()
		&"mech_colossus": m = mech_colossus()
		&"sea_leviathan": m = sea_leviathan()
		&"air_gunship": m = air_gunship()
	_meshes[proc] = m
	return m


## The three armour plates of the plate brute: front, left, right (ArrayMesh each, in the body's space).
static func plate_mesh(side: StringName) -> ArrayMesh:
	var key := StringName("plate_" + String(side))
	if _meshes.has(key):
		return _meshes[key]
	var am := AlienMesh.new()
	var bone := Color(0.78, 0.72, 0.58)
	var gold := Color(1.0, 0.72, 0.2)
	match side:
		&"front":
			am.box(Vector3(0.0, 1.95, -0.78), Vector3(1.25, 1.1, 0.2), bone, Basis.IDENTITY, bone.lerp(Color.WHITE, 0.15))
			am.box(Vector3(0.0, 2.52, -0.8), Vector3(1.3, 0.1, 0.24), G(gold, 0.7))
			am.box(Vector3(0.0, 1.38, -0.8), Vector3(1.3, 0.1, 0.24), G(gold, 0.7))
			am.box(Vector3(-0.64, 1.95, -0.8), Vector3(0.1, 1.2, 0.24), G(gold, 0.7))
			am.box(Vector3(0.64, 1.95, -0.8), Vector3(0.1, 1.2, 0.24), G(gold, 0.7))
		&"left", &"right":
			var sx := -1.0 if side == &"left" else 1.0
			am.ellipsoid(Vector3(sx * 1.12, 2.62, 0.0), Vector3(0.5, 0.32, 0.58), bone, 4, 8, Basis(Vector3.FORWARD, sx * 0.4))
			am.cone(Vector3(sx * 1.2, 2.84, 0.0), Vector3(sx * 1.3, 3.5, 0.1), 0.2, G(gold, 0.6), 4)
	var m := am.commit()
	_meshes[key] = m
	return m


# --- building blocks -------------------------------------------------------------------------------------------------------------------------------

static func _leg(am: AlienMesh, x: float, hip: float, r: float, col: Color, foot: Color, knee_z := -0.12, foot_len := 0.36) -> void:
	am.tube([Vector3(x, hip, 0.0), Vector3(x, hip * 0.5, knee_z), Vector3(x, 0.14, 0.02)], [r, r * 0.82, r * 0.7], [col, col, col], 6, true, true, 0.02)
	am.box(Vector3(x, 0.07, -foot_len * 0.22), Vector3(r * 2.3, 0.14, foot_len), foot)


static func _arm(am: AlienMesh, sx: float, sy: float, hand: Vector3, r: float, col: Color, glove: Color) -> void:
	var mid := (Vector3(sx, sy, 0.0) + hand) * 0.5 + Vector3(sx * 0.3, -0.06, -0.04)
	am.tube([Vector3(sx, sy, 0.0), mid, hand], [r, r * 0.86, r * 0.78], [col, col, glove], 6, false, true, 0.02)


static func _gun(am: AlienMesh, at: Vector3, length: float, r: float, col: Color, tip: Color) -> void:
	am.tube([at, at + Vector3(0.0, 0.0, -length * 0.5), at + Vector3(0.0, 0.0, -length)], [r * 1.3, r, r * 0.8], [col, col, tip], 6, true, true, 0.03)


# --- hive: alien infantry ------------------------------------------------------------------------------------------------------------------------------

static func hiveling() -> ArrayMesh:
	var am := AlienMesh.new()
	var body := Color(0.34, 0.2, 0.12)
	var dark := Color(0.17, 0.1, 0.07)
	var glow := Color(1.0, 0.55, 0.12)
	am.ellipsoid(Vector3(0.0, 0.34, 0.06), Vector3(0.24, 0.2, 0.36), body, 4, 8, Basis.IDENTITY, body.lerp(Color(0.5, 0.3, 0.16), 0.6))
	am.ellipsoid(Vector3(0.0, 0.38, -0.36), Vector3(0.17, 0.15, 0.19), dark, 4, 7)
	for sx: float in [-1.0, 1.0]:                                                           # eyes and the jaw
		am.ellipsoid(Vector3(sx * 0.09, 0.43, -0.5), Vector3(0.05, 0.05, 0.03), G(glow), 3, 5)
		am.cone(Vector3(sx * 0.07, 0.29, -0.5), Vector3(sx * 0.1, 0.18, -0.74), 0.045, Color(0.9, 0.85, 0.7), 4)
	for k in 3:                                                                      # six legs, glowing feet
		var z := -0.18 + 0.2 * float(k)
		for sx: float in [-1.0, 1.0]:
			am.tube([Vector3(sx * 0.2, 0.34, z), Vector3(sx * 0.46, 0.5, z - 0.04), Vector3(sx * 0.6, 0.0, z + 0.1)], [0.045, 0.035, 0.03], [dark, dark, G(glow, 0.5)], 4, false, true, 0.03)
	for k in 4:                                                                      # dorsal spines and a stinger tail
		am.cone(Vector3(0.0, 0.5, -0.1 + 0.16 * float(k)), Vector3(0.0, 0.72 - 0.04 * float(k), 0.0 + 0.16 * float(k)), 0.05, G(glow, 0.7), 4)
	am.cone(Vector3(0.0, 0.34, 0.38), Vector3(0.0, 0.62, 0.78), 0.07, dark, 4, G(glow))
	return am.commit()


static func shield_bearer() -> ArrayMesh:
	var am := AlienMesh.new()
	var skin := Color(0.2, 0.3, 0.34)
	var dark := Color(0.1, 0.16, 0.2)
	var cy := Color(0.3, 0.9, 1.0)
	_leg(am, -0.26, 0.95, 0.16, skin, dark, -0.16, 0.5)
	_leg(am, 0.26, 0.95, 0.16, skin, dark, -0.16, 0.5)
	am.ellipsoid(Vector3(0.0, 1.35, 0.05), Vector3(0.55, 0.5, 0.42), skin, 5, 9, Basis.IDENTITY, skin.lerp(Color(0.34, 0.48, 0.5), 0.5))
	am.ellipsoid(Vector3(0.0, 1.88, -0.12), Vector3(0.22, 0.2, 0.26), dark, 4, 8)
	am.ellipsoid(Vector3(0.0, 1.9, -0.36), Vector3(0.2, 0.06, 0.05), G(cy), 3, 6)
	for k in 5:                                                                       # the spine: glowing ridge on the back (weak point)
		am.cone(Vector3(0.0, 1.72 - 0.14 * float(k), 0.4), Vector3(0.0, 1.9 - 0.16 * float(k), 0.78), 0.1, G(Color(1.0, 0.7, 0.3), 0.85), 4)
	_arm(am, 0.62, 1.5, Vector3(0.74, 1.3, -0.5), 0.12, skin, dark)                    # the gun arm beside the shield
	_gun(am, Vector3(0.74, 1.3, -0.45), 0.7, 0.07, dark, G(cy))
	# the shield: a slab ahead of the body, glowing edges, a darker panel, the arm behind it
	am.box(Vector3(0.0, 1.15, -0.88), Vector3(1.3, 1.5, 0.1), Color(0.12, 0.3, 0.36, 0.35))
	am.box(Vector3(0.0, 1.15, -0.95), Vector3(1.12, 1.32, 0.05), Color(0.08, 0.2, 0.26))
	am.box(Vector3(0.0, 1.92, -0.9), Vector3(1.36, 0.08, 0.14), G(cy))
	am.box(Vector3(0.0, 0.38, -0.9), Vector3(1.36, 0.08, 0.14), G(cy))
	am.box(Vector3(-0.66, 1.15, -0.9), Vector3(0.08, 1.5, 0.14), G(cy))
	am.box(Vector3(0.66, 1.15, -0.9), Vector3(0.08, 1.5, 0.14), G(cy))
	am.ellipsoid(Vector3(0.0, 1.15, -1.0), Vector3(0.2, 0.2, 0.05), G(cy, 0.8), 3, 6)
	_arm(am, -0.62, 1.5, Vector3(-0.5, 1.2, -0.8), 0.13, skin, dark)
	return am.commit()


static func jet_elite() -> ArrayMesh:
	var am := AlienMesh.new()
	var skin := Color(0.3, 0.18, 0.4)
	var dark := Color(0.12, 0.08, 0.17)
	var fire := Color(1.0, 0.55, 0.15)
	_leg(am, -0.16, 0.95, 0.1, skin, dark)
	_leg(am, 0.16, 0.95, 0.1, skin, dark)
	am.ellipsoid(Vector3(0.0, 1.32, 0.0), Vector3(0.32, 0.42, 0.24), skin, 5, 8)
	am.ellipsoid(Vector3(0.0, 1.76, -0.08), Vector3(0.14, 0.2, 0.2), dark, 4, 8)
	am.ellipsoid(Vector3(0.0, 1.8, -0.26), Vector3(0.13, 0.05, 0.04), G(fire), 3, 6)
	am.cone(Vector3(0.0, 1.9, 0.02), Vector3(0.0, 2.05, 0.7), 0.1, skin.lerp(fire, 0.2), 4, G(fire, 0.6))          # swept crest
	_arm(am, 0.42, 1.5, Vector3(0.3, 1.32, -0.55), 0.07, skin, dark)
	_gun(am, Vector3(0.3, 1.32, -0.5), 0.8, 0.06, dark, G(fire))
	_arm(am, -0.42, 1.5, Vector3(-0.38, 1.2, -0.3), 0.07, skin, dark)
	am.box(Vector3(0.0, 1.34, 0.36), Vector3(0.52, 0.72, 0.26), Color(0.2, 0.2, 0.24), Basis.IDENTITY, Color(0.3, 0.3, 0.36))   # the jetpack
	for sx: float in [-1.0, 1.0]:
		am.cone(Vector3(sx * 0.15, 0.98, 0.4), Vector3(sx * 0.15, 0.36, 0.4), 0.14, Color(0.24, 0.24, 0.28), 6, G(fire))
		am.cone(Vector3(sx * 0.36, 1.5, 0.4), Vector3(sx * 0.82, 1.82, 0.55), 0.09, skin, 4, G(fire, 0.55))                  # fins
	return am.commit()


static func veil_stalker() -> ArrayMesh:
	var am := AlienMesh.new()
	var skin := Color(0.17, 0.2, 0.3)
	var dark := Color(0.07, 0.08, 0.14)
	var mg := Color(1.0, 0.2, 0.7)
	_leg(am, -0.16, 1.0, 0.075, skin, dark, -0.22, 0.4)
	_leg(am, 0.16, 1.0, 0.075, skin, dark, -0.22, 0.4)
	am.ellipsoid(Vector3(0.0, 1.35, 0.04), Vector3(0.26, 0.42, 0.2), skin, 5, 8, Basis(Vector3.RIGHT, -0.25))
	am.ellipsoid(Vector3(0.0, 1.74, -0.22), Vector3(0.13, 0.17, 0.2), dark, 4, 8)
	for sx: float in [-0.06, 0.0, 0.06]:                                                      # three eyes
		am.ellipsoid(Vector3(sx, 1.76, -0.4), Vector3(0.025, 0.025, 0.02), G(mg), 3, 5)
	for sx: float in [-1.0, 1.0]:                                                             # long arms with forearm blades
		am.tube([Vector3(sx * 0.3, 1.58, 0.0), Vector3(sx * 0.42, 1.18, -0.18), Vector3(sx * 0.34, 0.86, -0.42)], [0.06, 0.05, 0.04], [skin, skin, dark], 5, false, true, 0.03)
		am.cone(Vector3(sx * 0.34, 0.86, -0.42), Vector3(sx * 0.3, 0.52, -1.0), 0.05, Color(0.75, 0.78, 0.85), 4, G(mg, 0.8))
	for k in 4:                                                                        # back fins
		am.cone(Vector3(0.0, 1.62 - 0.14 * float(k), 0.18), Vector3(0.0, 1.8 - 0.14 * float(k), 0.62), 0.07, dark, 4, G(mg, 0.4))
	return am.commit()


static func plate_brute() -> ArrayMesh:
	var am := AlienMesh.new()
	var skin := Color(0.42, 0.2, 0.16)
	var dark := Color(0.2, 0.1, 0.09)
	var amber := Color(1.0, 0.7, 0.2)
	_leg(am, -0.5, 1.2, 0.26, skin, dark, -0.2, 0.7)
	_leg(am, 0.5, 1.2, 0.26, skin, dark, -0.2, 0.7)
	am.ellipsoid(Vector3(0.0, 1.9, 0.08), Vector3(0.88, 0.82, 0.62), skin, 5, 10, Basis.IDENTITY, skin.lerp(Color(0.6, 0.3, 0.2), 0.4))
	am.ellipsoid(Vector3(0.0, 1.72, -0.55), Vector3(0.4, 0.4, 0.22), G(amber, 0.9), 4, 8)                         # the core under the front plate
	am.ellipsoid(Vector3(0.0, 2.72, -0.22), Vector3(0.34, 0.3, 0.34), dark, 4, 8)
	for sx: float in [-1.0, 1.0]:
		am.ellipsoid(Vector3(sx * 0.12, 2.76, -0.5), Vector3(0.07, 0.05, 0.04), G(amber), 3, 5)
		am.tube([Vector3(sx * 0.95, 2.4, 0.0), Vector3(sx * 1.25, 1.6, -0.1), Vector3(sx * 1.2, 0.8, -0.2)], [0.3, 0.27, 0.22], [skin, skin, dark], 6, false, true, 0.02)
		am.ellipsoid(Vector3(sx * 1.2, 0.62, -0.2), Vector3(0.3, 0.32, 0.3), dark, 4, 7)
		am.cone(Vector3(sx * 0.4, 2.55, 0.5), Vector3(sx * 0.5, 3.3, 0.85), 0.16, skin.lerp(amber, 0.15), 4, G(amber, 0.5))
	for k in 4:
		am.cone(Vector3(0.0, 2.45 - 0.35 * float(k), 0.6), Vector3(0.0, 2.8 - 0.38 * float(k), 1.15), 0.14, dark, 4, G(amber, 0.45))
	return am.commit()


static func beam_sniper() -> ArrayMesh:
	var am := AlienMesh.new()
	var skin := Color(0.82, 0.82, 0.78)
	var dark := Color(0.34, 0.34, 0.38)
	var cy := Color(0.35, 1.0, 1.0)
	_leg(am, -0.14, 1.2, 0.07, skin, dark, -0.18, 0.4)
	_leg(am, 0.14, 1.2, 0.07, skin, dark, -0.18, 0.4)
	am.ellipsoid(Vector3(0.0, 1.55, 0.0), Vector3(0.24, 0.4, 0.18), skin, 5, 8)
	am.tube([Vector3(0.0, 1.8, 0.0), Vector3(0.0, 2.0, -0.04), Vector3(0.0, 2.14, -0.1)], [0.08, 0.06, 0.1], [skin, skin, skin], 6, false, false)
	am.ellipsoid(Vector3(0.0, 2.2, -0.1), Vector3(0.15, 0.2, 0.17), skin, 4, 8)                                    # tall narrow head with one big lens
	am.ellipsoid(Vector3(0.0, 2.18, -0.26), Vector3(0.13, 0.13, 0.05), G(cy), 4, 8)
	am.tube([Vector3(0.22, 1.62, 0.4), Vector3(0.22, 1.62, -0.5), Vector3(0.22, 1.62, -1.5)], [0.07, 0.055, 0.045], [dark, dark, G(cy)], 6, true, true, 0.03)    # the beam rifle
	_arm(am, 0.3, 1.78, Vector3(0.22, 1.62, -0.55), 0.05, skin, dark)
	_arm(am, -0.3, 1.78, Vector3(0.2, 1.58, -0.2), 0.05, skin, dark)
	for k in 3:
		am.cone(Vector3(0.0, 1.9 - 0.22 * float(k), 0.16), Vector3(0.0, 2.0 - 0.3 * float(k), 0.8), 0.1, dark, 4, G(cy, 0.35))   # cape fins
	return am.commit()


# --- grid: machines -------------------------------------------------------------------------------------------------------------------------------------

static func strider() -> ArrayMesh:
	var am := AlienMesh.new()
	var steel := Color(0.42, 0.46, 0.52)
	var dark := Color(0.17, 0.19, 0.22)
	var amber := Color(1.0, 0.5, 0.1)
	var hazard := Color(0.95, 0.75, 0.1)
	for sx: float in [-1.0, 1.0]:
		var x := sx * 0.95
		am.tube([Vector3(x, 3.0, 0.0), Vector3(x, 2.0, -0.55), Vector3(x, 1.2, 0.35), Vector3(x, 0.25, -0.05)], [0.3, 0.26, 0.24, 0.2], [steel, steel, dark, steel], 6, true, true, 0.02)
		am.ellipsoid(Vector3(x, 2.0, -0.55), Vector3(0.34, 0.34, 0.34), G(amber, 0.45), 3, 6)
		am.box(Vector3(x, 0.1, -0.2), Vector3(0.74, 0.2, 1.2), dark)
		am.box(Vector3(x, 1.7, -0.3), Vector3(0.4, 0.14, 0.3), hazard)
	am.box(Vector3(0.0, 3.2, 0.0), Vector3(2.1, 0.5, 1.3), dark)
	am.box(Vector3(0.0, 3.95, -0.1), Vector3(1.8, 0.9, 1.5), steel, Basis(Vector3.RIGHT, 0.0), steel.lerp(Color.WHITE, 0.15))
	am.box(Vector3(0.0, 4.02, -0.86), Vector3(1.4, 0.2, 0.06), G(amber))                                   # the eye strip
	am.box(Vector3(0.0, 3.55, -0.8), Vector3(0.9, 0.3, 0.2), dark)
	am.tube([Vector3(0.0, 3.5, -0.9), Vector3(0.0, 3.5, -1.6), Vector3(0.0, 3.5, -2.3)], [0.2, 0.15, 0.13], [dark, dark, G(amber)], 6, true, true, 0.04)    # the chin cannon
	for sx: float in [-1.0, 1.0]:                                                                                # shoulder missile pods
		am.box(Vector3(sx * 1.25, 4.3, -0.1), Vector3(0.7, 0.55, 1.1), dark)
		for r in 2:
			for cc in 2:
				am.ellipsoid(Vector3(sx * (1.1 + 0.3 * float(cc)), 4.15 + 0.28 * float(r), -0.68), Vector3(0.1, 0.1, 0.05), G(amber, 0.8), 3, 5)
	am.ellipsoid(Vector3(0.0, 3.25, 0.95), Vector3(0.66, 0.66, 0.34), G(amber, 0.9), 4, 8)                  # the rear core
	for k in 3:
		am.box(Vector3(0.0, 2.95 + 0.3 * float(k), 1.22), Vector3(1.0, 0.07, 0.12), dark)
	am.box(Vector3(0.0, 4.5, 0.5), Vector3(0.5, 0.2, 0.5), hazard)
	return am.commit()


static func crawler() -> ArrayMesh:
	var am := AlienMesh.new()
	var dark := Color(0.14, 0.14, 0.17)
	var steel := Color(0.32, 0.33, 0.38)
	var red := Color(1.0, 0.2, 0.2)
	am.ellipsoid(Vector3(0.0, 1.1, 0.0), Vector3(0.95, 0.5, 1.15), steel, 5, 10, Basis.IDENTITY, steel.lerp(Color.WHITE, 0.12))
	am.ellipsoid(Vector3(0.0, 0.9, -0.5), Vector3(0.7, 0.38, 0.7), dark, 4, 8)
	am.box(Vector3(0.0, 1.66, 0.1), Vector3(0.7, 0.3, 0.7), dark)                                          # the dorsal vent
	am.ellipsoid(Vector3(0.0, 1.88, 0.1), Vector3(0.32, 0.22, 0.32), G(red), 3, 7)
	for sx: float in [-1.0, 1.0]:
		am.tube([Vector3(sx * 0.4, 1.0, -0.9), Vector3(sx * 0.4, 1.0, -1.6), Vector3(sx * 0.4, 1.0, -2.2)], [0.1, 0.08, 0.07], [dark, dark, G(red)], 5, true, true, 0.03)
		for k in 3:                                                                                         # three legs a side: up, out, down
			var z := -0.7 + 0.7 * float(k)
			am.tube([Vector3(sx * 0.8, 1.1, z), Vector3(sx * 1.7, 1.85, z - 0.1), Vector3(sx * 2.15, 0.9, z + 0.25), Vector3(sx * 2.25, 0.0, z + 0.4)],
				[0.13, 0.11, 0.09, 0.07], [steel, steel, dark, G(red, 0.4)], 5, false, true, 0.03)
	for sx: float in [-0.28, 0.0, 0.28]:
		am.ellipsoid(Vector3(sx, 1.0, -1.02), Vector3(0.1, 0.1, 0.06), G(red), 3, 6)                        # the sensor eyes
	return am.commit()


static func wasp_drone() -> ArrayMesh:
	var am := AlienMesh.new()
	var dark := Color(0.12, 0.13, 0.16)
	var steel := Color(0.4, 0.42, 0.46)
	var yel := Color(0.95, 0.75, 0.1)
	var red := Color(1.0, 0.25, 0.2)
	am.ellipsoid(Vector3(0.0, 0.5, 0.0), Vector3(0.32, 0.2, 0.5), steel, 4, 8)
	for k in 3:
		am.box(Vector3(0.0, 0.58, -0.2 + 0.2 * float(k)), Vector3(0.5, 0.06, 0.08), yel if k % 2 == 0 else dark)
	am.ellipsoid(Vector3(0.0, 0.5, -0.46), Vector3(0.16, 0.12, 0.08), G(red), 3, 6)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			am.tube([Vector3(sx * 0.2, 0.52, sz * 0.2), Vector3(sx * 0.48, 0.58, sz * 0.5), Vector3(sx * 0.68, 0.58, sz * 0.7)], [0.04, 0.035, 0.03], [dark, dark, dark], 4, false, true, 0.02)
			am.disc(Vector3(sx * 0.68, 0.66, sz * 0.7), 0.42, G(red, 0.8), 10, 0.28)                         # the rotor ring: a glowing blur
	for sx: float in [-1.0, 1.0]:
		am.tube([Vector3(sx * 0.14, 0.4, -0.3), Vector3(sx * 0.14, 0.4, -0.62), Vector3(sx * 0.14, 0.4, -0.9)], [0.05, 0.04, 0.035], [dark, dark, G(red)], 4, true, true, 0.02)
	am.cone(Vector3(0.0, 0.46, 0.45), Vector3(0.0, 0.52, 0.95), 0.06, dark, 4, G(red, 0.8))
	return am.commit()


static func auto_turret() -> ArrayMesh:
	var am := AlienMesh.new()
	var olive := Color(0.3, 0.33, 0.22)
	var dark := Color(0.13, 0.14, 0.12)
	var yel := Color(1.0, 0.85, 0.1)
	for k in 3:
		var a := TAU * float(k) / 3.0 + 0.5
		am.cone(Vector3(cos(a) * 0.15, 0.66, sin(a) * 0.15), Vector3(cos(a) * 0.95, 0.0, sin(a) * 0.95), 0.07, dark, 4)
	am.ellipsoid(Vector3(0.0, 0.7, 0.0), Vector3(0.34, 0.2, 0.34), olive, 4, 8)
	am.box(Vector3(0.0, 1.0, 0.0), Vector3(0.62, 0.4, 0.72), olive, Basis.IDENTITY, olive.lerp(Color.WHITE, 0.12))
	for sx: float in [-1.0, 1.0]:
		am.tube([Vector3(sx * 0.14, 1.0, -0.3), Vector3(sx * 0.14, 1.0, -0.8), Vector3(sx * 0.14, 1.0, -1.4)], [0.09, 0.07, 0.07], [dark, dark, G(yel, 0.6)], 6, true, true, 0.03)
	am.box(Vector3(0.38, 0.95, 0.12), Vector3(0.2, 0.28, 0.4), dark)
	am.ellipsoid(Vector3(0.0, 1.36, 0.02), Vector3(0.2, 0.18, 0.2), G(yel), 4, 8)
	am.box(Vector3(0.0, 1.1, -0.38), Vector3(0.5, 0.06, 0.04), G(yel, 0.7))
	return am.commit()


# --- contract: human mercenaries --------------------------------------------------------------------------------------------------------------------

static func merc(kind: StringName) -> ArrayMesh:
	var am := AlienMesh.new()
	var tan := Color(0.58, 0.5, 0.34)
	var olive := Color(0.27, 0.31, 0.2)
	var dark := Color(0.13, 0.14, 0.13)
	var skin := Color(0.68, 0.52, 0.42)
	var band := Color(1.0, 0.6, 0.15)
	var bulk := 1.0
	match kind:
		&"merc_rocket":
			bulk = 1.12
			band = Color(1.0, 0.3, 0.2)
			tan = Color(0.5, 0.36, 0.24)
		&"merc_shotgun":
			bulk = 1.22
			band = Color(1.0, 0.25, 0.15)
			tan = Color(0.3, 0.3, 0.32)
			olive = Color(0.18, 0.18, 0.2)
		&"merc_sniper":
			bulk = 0.9
			tan = Color(0.38, 0.44, 0.26)
			olive = Color(0.24, 0.3, 0.17)
			band = Color(0.4, 1.0, 1.0)
		&"merc_medic":
			tan = Color(0.86, 0.86, 0.82)
			olive = Color(0.4, 0.42, 0.36)
			band = Color(0.3, 1.0, 0.5)
	var lx := 0.17 * bulk
	_leg(am, -lx, 0.92, 0.11 * bulk, olive, dark)
	_leg(am, lx, 0.92, 0.11 * bulk, olive, dark)
	am.box(Vector3(0.0, 0.98, 0.0), Vector3(0.48 * bulk, 0.2, 0.3), dark)
	am.box(Vector3(0.0, 1.3, 0.0), Vector3(0.58 * bulk, 0.54, 0.34), tan, Basis.IDENTITY, tan.lerp(Color.WHITE, 0.1))
	am.box(Vector3(0.0, 1.32, -0.19), Vector3(0.44 * bulk, 0.36, 0.07), olive.lerp(tan, 0.3))
	am.box(Vector3(0.0, 1.5, -0.23), Vector3(0.46 * bulk, 0.06, 0.03), G(band, 0.95))                      # the faction band across the chest
	for sx: float in [-1.0, 1.0]:
		am.ellipsoid(Vector3(sx * 0.34 * bulk, 1.52, 0.0), Vector3(0.13, 0.1, 0.16), dark, 3, 6)             # shoulder pads
	am.tube([Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.58, -0.01)], [0.07, 0.07], [skin, skin], 6, false, false)   # neck
	am.ellipsoid(Vector3(0.0, 1.68, -0.02), Vector3(0.15, 0.17, 0.16), skin, 4, 8)                          # head, bigger than before
	var gx := 0.34 * bulk
	match kind:
		&"merc_rifle":
			am.ellipsoid(Vector3(0.0, 1.76, -0.02), Vector3(0.19, 0.13, 0.2), olive, 4, 8)                  # helmet
			am.box(Vector3(0.0, 1.69, -0.18), Vector3(0.26, 0.06, 0.04), G(band, 0.9))                      # visor band
			am.box(Vector3(0.0, 1.32, 0.27), Vector3(0.4, 0.44, 0.2), olive)                                  # pack
			_arm(am, gx, 1.5, Vector3(0.12, 1.3, -0.42), 0.08, tan, dark)
			_arm(am, -gx, 1.5, Vector3(-0.02, 1.34, -0.66), 0.08, tan, dark)
			_gun(am, Vector3(0.04, 1.32, -0.2), 1.05, 0.05, dark, Color(0.2, 0.2, 0.2))
			am.box(Vector3(0.04, 1.24, -0.55), Vector3(0.05, 0.16, 0.08), dark)
		&"merc_rocket":
			am.ellipsoid(Vector3(0.0, 1.76, -0.02), Vector3(0.2, 0.14, 0.21), dark, 4, 8)
			am.box(Vector3(0.0, 1.69, -0.18), Vector3(0.28, 0.08, 0.04), G(band, 0.9))
			am.box(Vector3(0.0, 1.32, 0.28), Vector3(0.44, 0.5, 0.24), olive)
			for k in 2:                                                                                       # spare rockets in the pack
				am.cone(Vector3(-0.1 + 0.2 * float(k), 1.55, 0.4), Vector3(-0.1 + 0.2 * float(k), 1.95, 0.42), 0.07, tan, 5, G(band, 0.9))
			am.tube([Vector3(0.32, 1.66, 0.65), Vector3(0.32, 1.7, -0.4), Vector3(0.32, 1.72, -1.2)], [0.17, 0.15, 0.22], [dark, olive, G(band, 0.8)], 8, true, true, 0.03)    # the launcher on the shoulder
			_arm(am, gx, 1.5, Vector3(0.32, 1.52, -0.32), 0.085, tan, dark)
			_arm(am, -gx, 1.5, Vector3(0.24, 1.56, -0.74), 0.085, tan, dark)
			am.cone(Vector3(0.32, 1.7, 0.65), Vector3(0.32, 1.7, 0.95), 0.2, dark, 8)
		&"merc_shotgun":
			am.ellipsoid(Vector3(0.0, 1.76, -0.02), Vector3(0.2, 0.14, 0.21), dark, 4, 8)
			am.box(Vector3(0.0, 1.69, -0.19), Vector3(0.3, 0.08, 0.05), G(Color(1.0, 0.2, 0.1), 0.98))     # goggles
			am.box(Vector3(0.0, 1.34, -0.22), Vector3(0.56 * bulk, 0.4, 0.12), Color(0.2, 0.2, 0.22))       # heavy chest plate
			for sx: float in [-1.0, 1.0]:
				am.ellipsoid(Vector3(sx * 0.42 * bulk, 1.56, 0.0), Vector3(0.18, 0.13, 0.2), dark, 3, 6)   # big pauldrons
			_arm(am, gx, 1.5, Vector3(0.16, 1.2, -0.52), 0.1, tan, dark)
			_arm(am, -gx, 1.5, Vector3(0.0, 1.24, -0.76), 0.1, tan, dark)
			am.tube([Vector3(0.08, 1.24, -0.1), Vector3(0.08, 1.24, -0.6), Vector3(0.08, 1.24, -1.05)], [0.1, 0.09, 0.09], [dark, dark, G(band, 0.6)], 6, true, true, 0.03)
			am.box(Vector3(0.08, 1.1, -0.55), Vector3(0.12, 0.1, 0.34), olive)
		&"merc_sniper":
			am.cone(Vector3(0.0, 1.78, -0.02), Vector3(0.0, 1.9, -0.02), 0.34, olive, 10)                    # a wide boonie hat
			am.ellipsoid(Vector3(0.0, 1.8, -0.02), Vector3(0.16, 0.09, 0.17), olive, 4, 8)
			for k in 8:                                                                                       # ghillie fringe
				var a := TAU * float(k) / 8.0
				am.cone(Vector3(cos(a) * 0.22, 1.5, sin(a) * 0.18), Vector3(cos(a) * 0.38, 0.95, sin(a) * 0.3), 0.07, olive.lerp(Color(0.5, 0.55, 0.3), 0.4), 4)
			_arm(am, gx, 1.48, Vector3(0.14, 1.28, -0.5), 0.07, tan, dark)
			_arm(am, -gx, 1.48, Vector3(0.0, 1.3, -0.95), 0.07, tan, dark)
			_gun(am, Vector3(0.06, 1.3, 0.25), 1.8, 0.045, dark, Color(0.2, 0.2, 0.2))
			am.ellipsoid(Vector3(0.06, 1.4, -0.3), Vector3(0.05, 0.05, 0.16), G(band, 0.95), 3, 6)             # the scope lens
		&"merc_medic":
			am.ellipsoid(Vector3(0.0, 1.76, -0.02), Vector3(0.17, 0.1, 0.18), tan, 4, 8)                      # a soft white cap
			am.box(Vector3(0.0, 1.69, -0.17), Vector3(0.14, 0.14, 0.04), G(band, 0.95))
			am.box(Vector3(0.0, 1.33, 0.29), Vector3(0.58, 0.66, 0.28), Color(0.9, 0.9, 0.88))                # the big white med pack
			am.box(Vector3(0.0, 1.34, 0.44), Vector3(0.38, 0.11, 0.03), G(band))                              # a glowing cross on it
			am.box(Vector3(0.0, 1.34, 0.44), Vector3(0.11, 0.38, 0.03), G(band))
			am.box(Vector3(0.0, 1.5, -0.24), Vector3(0.12, 0.12, 0.03), G(band, 0.95))
			_arm(am, gx, 1.5, Vector3(0.12, 1.3, -0.44), 0.075, tan, dark)
			_arm(am, -gx, 1.5, Vector3(-0.26, 1.3, -0.36), 0.075, tan, dark)
			_gun(am, Vector3(0.12, 1.28, -0.32), 0.45, 0.045, dark, Color(0.2, 0.2, 0.2))
	return am.commit()


# --- the bosses -------------------------------------------------------------------------------------------------------------------------------------------

static func mountain_titan() -> ArrayMesh:
	var am := AlienMesh.new()
	var rock := Color(0.55, 0.52, 0.48)
	var dark := Color(0.3, 0.29, 0.3)
	var moss := Color(0.36, 0.5, 0.25)
	var cy := Color(0.4, 0.95, 1.0)
	for sx: float in [-1.0, 1.0]:
		am.tube([Vector3(sx * 1.45, 4.3, 0.0), Vector3(sx * 1.5, 2.2, -0.15), Vector3(sx * 1.5, 0.3, 0.0)], [1.25, 1.1, 1.0], [rock, rock, dark], 8, true, true, 0.02)
		am.box(Vector3(sx * 1.5, 0.2, -0.5), Vector3(2.0, 0.4, 2.6), dark)
		am.ellipsoid(Vector3(sx * 3.1, 7.7, 0.0), Vector3(1.4, 1.1, 1.3), rock, 5, 8, Basis.IDENTITY, moss)
		am.tube([Vector3(sx * 3.0, 7.3, 0.0), Vector3(sx * 3.7, 5.4, -0.5), Vector3(sx * 3.4, 3.6, -1.0)], [0.95, 0.85, 0.75], [rock, rock, dark], 7, false, true, 0.02)
		am.ellipsoid(Vector3(sx * 3.4, 3.1, -1.1), Vector3(1.0, 0.95, 1.0), dark, 4, 8)
	am.ellipsoid(Vector3(0.0, 5.6, 0.2), Vector3(2.3, 2.3, 1.9), rock, 6, 10, Basis.IDENTITY, moss)
	am.ellipsoid(Vector3(0.0, 4.4, 0.0), Vector3(1.9, 1.3, 1.6), dark, 5, 9)
	am.ellipsoid(Vector3(0.0, 9.6, -0.5), Vector3(1.0, 0.95, 1.1), rock, 5, 9)
	am.box(Vector3(0.0, 9.1, -1.1), Vector3(1.1, 0.3, 0.8), dark)                                                    # jaw
	for sx: float in [-0.4, 0.4]:
		am.ellipsoid(Vector3(sx, 9.8, -1.45), Vector3(0.26, 0.16, 0.08), G(cy), 3, 6)
	am.ellipsoid(Vector3(0.0, 5.6, -2.0), Vector3(0.7, 0.9, 0.2), G(cy, 0.6), 4, 8)                                   # a glowing chest core on the front
	for k in 6:                                                                                                      # glowing cracks across the chest
		var a := TAU * float(k) / 6.0 + 0.3
		am.tube([Vector3(cos(a) * 0.3, 6.2, -1.7), Vector3(cos(a) * 1.0, 5.6, -1.85), Vector3(cos(a) * 1.5, 4.9, -1.5)], [0.05, 0.06, 0.04], [G(cy, 0.7), G(cy, 0.7), G(cy, 0.4)], 4, false, false)
	for p in [Vector3(-1.9, 8.2, 1.7), Vector3(1.9, 8.2, 1.7), Vector3(0.0, 6.0, 2.5)]:                              # the three crystals
		am.cone(p + Vector3(0.0, -0.9, 0.0), p + Vector3(0.0, 1.0, 0.4), 0.62, G(cy, 0.85), 6, G(Color(0.8, 1.0, 1.0), 0.99))
		am.cone(p + Vector3(0.3, -0.7, 0.0), p + Vector3(0.9, 0.6, 0.6), 0.34, G(cy, 0.6), 5)
	for k in 5:
		am.cone(Vector3(-1.4 + 0.7 * float(k), 7.3, 1.4), Vector3(-1.6 + 0.8 * float(k), 8.4, 2.3), 0.38, dark, 4)
	return am.commit()


static func mech_colossus() -> ArrayMesh:
	var am := AlienMesh.new()
	var steel := Color(0.4, 0.43, 0.5)
	var dark := Color(0.16, 0.17, 0.2)
	var amber := Color(1.0, 0.5, 0.1)
	var hazard := Color(0.95, 0.75, 0.1)
	for sx: float in [-1.0, 1.0]:
		var x := sx * 1.9
		am.box(Vector3(x, 4.2, 0.0), Vector3(1.5, 2.0, 1.6), steel)                                                  # thigh
		am.ellipsoid(Vector3(x, 3.0, -0.5), Vector3(0.9, 0.9, 0.7), G(amber, 0.45), 4, 8)                            # the knee joint (weak)
		am.box(Vector3(x, 1.6, 0.1), Vector3(1.2, 2.6, 1.3), dark)
		am.box(Vector3(x, 0.25, -0.5), Vector3(1.9, 0.5, 2.8), steel)
		am.box(Vector3(x, 1.9, -0.55), Vector3(0.8, 0.14, 0.3), hazard)
	am.box(Vector3(0.0, 5.4, 0.0), Vector3(3.8, 0.9, 2.6), dark)
	am.box(Vector3(0.0, 6.9, 0.0), Vector3(4.2, 2.4, 3.0), steel, Basis.IDENTITY, steel.lerp(Color.WHITE, 0.12))
	am.box(Vector3(0.0, 7.0, -1.55), Vector3(3.2, 1.4, 0.1), dark)
	am.box(Vector3(0.0, 8.7, -0.7), Vector3(1.7, 1.0, 1.5), steel)
	am.box(Vector3(0.0, 8.8, -1.46), Vector3(1.4, 0.3, 0.06), G(amber))                                              # the visor
	for k in 5:                                                                                                       # the rotary gatling on the left shoulder
		var a := TAU * float(k) / 5.0
		am.tube([Vector3(-3.0 + cos(a) * 0.32, 7.2 + sin(a) * 0.32, -1.2), Vector3(-3.0 + cos(a) * 0.32, 7.2 + sin(a) * 0.32, -3.0), Vector3(-3.0 + cos(a) * 0.32, 7.2 + sin(a) * 0.32, -4.6)],
			[0.15, 0.13, 0.12], [dark, dark, G(amber, 0.7)], 5, true, true, 0.03)
	am.box(Vector3(-2.9, 7.2, -0.3), Vector3(1.4, 1.4, 1.8), dark)
	am.box(Vector3(3.0, 7.8, -0.4), Vector3(1.5, 1.2, 2.2), dark)                                                    # the missile rack on the right
	for r in 2:
		for cc in 3:
			am.ellipsoid(Vector3(2.6 + 0.4 * float(cc), 7.5 + 0.5 * float(r), -1.52), Vector3(0.16, 0.16, 0.06), G(amber, 0.85), 3, 6)
	am.ellipsoid(Vector3(0.0, 6.7, 1.9), Vector3(1.2, 1.2, 0.55), G(amber, 0.9), 4, 8)                               # the reactor on the back
	for k in 4:
		am.box(Vector3(0.0, 5.9 + 0.4 * float(k), 2.3), Vector3(1.8, 0.1, 0.14), dark)
	am.box(Vector3(0.0, 8.5, 1.4), Vector3(1.0, 0.4, 0.8), hazard)
	return am.commit()


static func sea_leviathan() -> ArrayMesh:
	var am := AlienMesh.new()
	var body := Color(0.1, 0.2, 0.34)
	var dark := Color(0.05, 0.1, 0.2)
	var tl := Color(0.3, 1.0, 0.85)
	var path := []
	var radii := []
	var cols := []
	var n := 14
	for k in n + 1:
		var t := float(k) / float(n)
		path.append(Vector3(0.5 * sin(t * 4.0) * (1.0 - t), t * 8.8, -2.6 * t * t - 1.8 * smoothstep(0.75, 1.0, t)))
		radii.append(1.5 * (1.0 - 0.45 * t) + 0.12)
		var c := body if k % 2 == 0 else body.lerp(dark, 0.5)
		c.a = 0.35 if k % 3 == 1 else 0.0
		cols.append(c)
	am.tube(path, radii, cols, 9, true, false)
	am.ellipsoid(Vector3(0.0, 0.3, 1.6), Vector3(2.7, 1.2, 3.8), body, 5, 10, Basis.IDENTITY, body.lerp(tl, 0.1))     # the hump at the water line
	var head := Vector3(0.0, 8.9, -4.8)
	am.ellipsoid(head, Vector3(0.95, 0.75, 1.6), body, 5, 10)
	for sx: float in [-1.0, 1.0]:                                                                                           # eyes, jaw teeth
		am.ellipsoid(head + Vector3(sx * 0.6, 0.35, -0.8), Vector3(0.18, 0.18, 0.12), G(tl), 3, 6)
		for k in 4:
			am.cone(head + Vector3(sx * 0.5, -0.55, -0.4 - 0.4 * float(k)), head + Vector3(sx * 0.45, -1.0, -0.5 - 0.4 * float(k)), 0.1, Color(0.9, 0.9, 0.8), 4)
	am.ellipsoid(head + Vector3(0.0, -0.5, -0.4), Vector3(0.7, 0.22, 1.3), dark, 4, 8)
	for k in range(2, n, 1):                                                                                         # dorsal crest along the back of the neck
		var p: Vector3 = path[k]
		am.cone(p + Vector3(0.0, 0.0, float(radii[k]) * 0.8), p + Vector3(0.0, 0.5, float(radii[k]) * 0.8 + 1.1), float(radii[k]) * 0.25, G(tl, 0.55), 3)
	for sx: float in [-1.0, 1.0]:                                                                                           # gill slits (weak points)
		for k in 3:
			am.ellipsoid(Vector3(sx * 1.0, 4.6 + 0.35 * float(k), -0.95), Vector3(0.1, 0.09, 0.3), G(tl, 0.95), 3, 6, Basis(Vector3.UP, sx * 0.5))
	return am.commit()


static func air_gunship() -> ArrayMesh:
	var am := AlienMesh.new()
	var steel := Color(0.28, 0.3, 0.34)
	var dark := Color(0.12, 0.13, 0.15)
	var org := Color(1.0, 0.4, 0.15)
	am.ellipsoid(Vector3(0.0, 0.0, 0.0), Vector3(1.3, 1.25, 3.3), steel, 5, 10, Basis.IDENTITY, steel.lerp(Color.WHITE, 0.1))
	am.ellipsoid(Vector3(0.0, 0.5, -1.9), Vector3(0.95, 0.7, 1.3), Color(0.12, 0.16, 0.2, 0.55), 4, 8)                # the canopy glow
	am.tube([Vector3(0.0, 0.3, 2.5), Vector3(0.0, 0.7, 4.8), Vector3(0.0, 1.0, 6.8)], [0.6, 0.4, 0.22], [steel, steel, dark], 7, false, true, 0.02)
	am.box(Vector3(0.0, 1.5, 6.6), Vector3(0.12, 1.4, 1.1), dark)
	am.ellipsoid(Vector3(0.35, 1.1, 6.5), Vector3(0.05, 0.85, 0.85), G(org, 0.6), 3, 10)                              # the tail rotor blur (weak)
	am.cone(Vector3(0.0, 1.2, 0.0), Vector3(0.0, 1.9, 0.0), 0.3, dark, 6)
	am.disc(Vector3(0.0, 1.9, 0.0), 5.2, G(org, 0.28), 14, 4.7)                                                       # the main rotor blur
	for sx: float in [-1.0, 1.0]:
		am.box(Vector3(sx * 2.2, 0.15, -0.2), Vector3(2.0, 0.14, 1.1), dark)
		for k in 2:
			am.tube([Vector3(sx * (1.8 + 0.5 * float(k)), 0.0, 0.1), Vector3(sx * (1.8 + 0.5 * float(k)), 0.0, -0.9), Vector3(sx * (1.8 + 0.5 * float(k)), 0.0, -1.6)], [0.14, 0.12, 0.1],
				[dark, dark, G(org, 0.7)], 5, true, true, 0.03)
		am.ellipsoid(Vector3(sx * 1.7, 0.9, 0.9), Vector3(0.7, 0.66, 1.3), dark, 5, 8)                                # the engine pods (weak)
		am.cone(Vector3(sx * 1.7, 0.9, 2.1), Vector3(sx * 1.7, 0.9, 2.9), 0.55, steel, 8, G(org))
		am.cone(Vector3(sx * 0.7, -1.1, -0.5), Vector3(sx * 0.7, -1.6, -0.5), 0.1, dark, 4)
	am.tube([Vector3(0.0, -1.0, -2.6), Vector3(0.0, -1.1, -3.6), Vector3(0.0, -1.1, -4.6)], [0.2, 0.15, 0.13], [dark, dark, G(org, 0.8)], 6, true, true, 0.04)   # the chin gatling
	return am.commit()


# --- the shared body set-up ------------------------------------------------------------------------------------------------------------------------------

## Builds the body of species `sid` on the creature `c` (an AlienCreature or AlienBoss): fields, material, mesh, hit spheres (body, head, weak points), groups. False when the id is unknown.
static func setup_body(c: AlienCreature, sid: StringName, w: AlienWorld) -> bool:
	var spec := RosterSpecies.data(sid)
	if spec.is_empty():
		return false
	c.id = sid
	c.type = sid
	c.world = w
	c.spec = spec
	c.family = spec["family"]
	c.cls = spec["cls"]
	c.mech = spec["mech"]
	c.vis = float(spec.get("vis", 1.0))
	c.max_hp = float(spec["hp"]) * Difficulty.mult("hp")
	c.hp = c.max_hp
	c.radius = float(spec["r"]) * c.vis
	var look := StringName(spec.get("look", &""))
	var human := look != &"" and RosterHuman.attach(c, look, spec)             # wave 113: the armoured, skinned humans (FoeHuman) instead of a procedural mesh
	if not human:
		var pm := mesh_of(StringName(spec["proc"]))
		if pm == null:
			return false
		c.mat = AlienKit.material(spec["glow"], 0.45)
		c.mat.set_shader_parameter(&"body_h", maxf(float(spec.get("hy", 1.6)), float(spec.get("cy", 1.0)) * 1.8) * c.vis)
		c.mat.set_shader_parameter(&"hip_y", float(HIP.get(sid, 0.0)))
		c.mesh = MeshInstance3D.new()
		c.mesh.mesh = pm
		c.mesh.material_override = c.mat
		c.mesh.extra_cull_margin = 4.0
		c.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.mesh.scale = Vector3.ONE * c.vis
		c.add_child(c.mesh)
		c.model = c.mesh
	var shapes: Array = [[Vector3(0.0, float(spec["cy"]), 0.0), float(spec["r"]), false, -1]]
	if float(spec["hr"]) > 0.0:
		shapes.append([Vector3(0.0, float(spec["hy"]), float(spec.get("hz", 0.0))), float(spec["hr"]), true, -1])
	var wi := 0
	for wk: Dictionary in (spec.get("weak", []) as Array):
		shapes.append([wk["pos"], float(wk["r"]), true, wi])
		wi += 1
	c.shapes = shapes
	if c.cls == WATER_CLS:
		c.set_exposed(false)
		c.rise = 0.0
	c.phase = randf() * TAU
	c.slot = randf() * TAU
	c._voice_t = randf_range(2.0, 7.0)
	c.add_to_group(&"alien")
	if c.exposed:
		c.add_to_group(&"enemy")
	return true


const WATER_CLS := &"water"
