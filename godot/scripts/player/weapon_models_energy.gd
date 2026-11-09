class_name WeaponModelsEnergy
extends RefCounted
## The procedural models of the wave-108 weapons (the ENERGY family and the BLAST heavies, WeaponDefs ids eplasma ... tknife). Same frame as WeaponModels: the origin is the MUZZLE (the tip of a blade, the head of a
## hammer), the barrel points to -Z, the body extends toward +Z, +Y is up, +X the hero's right; vertex colour rgb = part, alpha = how much of it glows (the weapon_look shader). One silhouette rule per
## weapon so the pictures differ at a glance: the plasma pistol has a split emitter and a glowing cell, the repeater a finned heat shroud, the spiker crystals on its back, the beam rifle a big lens scope,
## the blade a long glowing edge, the maul a head on a haunch, the pod a block of six tubes, the railgun two rails with coils, the chaingun a cluster of six barrels, the cluster missile a fat tube with a warhead,
## the napalm launcher a fuel tank under a stubby barrel, the singularity cannon a funnel round a violet core, the beacon an antenna, the seeker a sight and a flared exhaust, the knives a blade.

const GUN := WeaponModels.GUN
const POLY := WeaponModels.POLY
const DARK := WeaponModels.DARK
const STEEL := WeaponModels.STEEL
const IDS: Array[StringName] = [&"eplasma", &"erepeat", &"espike", &"ebeam", &"eblade", &"emaul", &"epod", &"railgun", &"chaingun", &"cmissile", &"napalm", &"sing", &"orbital", &"seeker", &"tknife"]



static func build(b: WeaponModels._Builder, id: StringName, glow: Color) -> void:
	match id:
		&"eplasma":
			_eplasma(b, glow)
		&"erepeat":
			_erepeat(b, glow)
		&"espike":
			_espike(b, glow)
		&"ebeam":
			_ebeam(b, glow)
		&"eblade":
			_eblade(b, glow)
		&"emaul":
			_emaul(b, glow)
		&"epod":
			_epod(b, glow)
		&"railgun":
			_railgun(b, glow)
		&"chaingun":
			_chaingun(b, glow)
		&"cmissile":
			_cmissile(b, glow)
		&"napalm":
			_napalm(b, glow)
		&"sing":
			_sing(b, glow)
		&"orbital":
			_orbital(b, glow)
		&"seeker":
			_seeker(b, glow)
		&"tknife":
			_tknife(b, glow)


static func _grip(b: WeaponModels._Builder, z: float, y := -0.09) -> void:
	b.box(Vector3(0, y, z), Vector3(0.036, 0.11, 0.046), DARK, 0.0, -0.3)


## EMBER PLASMA PISTOL: a split emitter (two prongs with a glowing channel between), a body, a glowing plasma cell on top and heat vents on the sides.
static func _eplasma(b: WeaponModels._Builder, glow: Color) -> void:
	for sx in [-1.0, 1.0]:
		b.box(Vector3(0.032 * sx, 0.0, 0.075), Vector3(0.018, 0.056, 0.15), STEEL)
		b.box(Vector3(0.032 * sx, 0.0, 0.0), Vector3(0.022, 0.06, 0.018), glow, 1.0)
	b.box(Vector3(0, 0.0, 0.08), Vector3(0.046, 0.006, 0.12), glow, 0.9)
	b.box(Vector3(0, 0.0, 0.2), Vector3(0.076, 0.08, 0.2), GUN)
	b.cyl(Vector3(0, 0.05, 0.2), 0.034, 0.13, glow, 0.9, 10)
	b.cyl(Vector3(0, 0.05, 0.2), 0.039, 0.02, STEEL, 0.0, 10)
	for k in 3:
		b.box(Vector3(0.039, 0.0, 0.15 + 0.04 * float(k)), Vector3(0.004, 0.05, 0.02), glow, 0.7)
		b.box(Vector3(-0.039, 0.0, 0.15 + 0.04 * float(k)), Vector3(0.004, 0.05, 0.02), glow, 0.7)
	_grip(b, 0.26)
	b.box(Vector3(0, -0.04, 0.3), Vector3(0.05, 0.04, 0.04), POLY)


## PULSE REPEATER: a finned heat shroud with glowing rings round the barrel, a boxy receiver, a glowing curved magazine, a short stock.
static func _erepeat(b: WeaponModels._Builder, glow: Color) -> void:
	b.cyl(Vector3(0, 0.0, 0.2), 0.03, 0.4, STEEL, 0.0, 10)
	for k in 5:
		b.cyl(Vector3(0, 0.0, 0.06 + 0.075 * float(k)), 0.048, 0.022, GUN, 0.0, 10)                  # the heat fins
		b.cyl(Vector3(0, 0.0, 0.095 + 0.075 * float(k)), 0.044, 0.01, glow, 0.9, 10)
	b.box(Vector3(0, 0.0, 0.0), Vector3(0.05, 0.05, 0.012), glow, 1.0)
	b.box(Vector3(0, 0.0, 0.55), Vector3(0.09, 0.11, 0.3), GUN)                                       # receiver
	b.box(Vector3(0, 0.04, 0.55), Vector3(0.094, 0.02, 0.24), glow, 0.8)
	b.box(Vector3(0, 0.075, 0.55), Vector3(0.026, 0.026, 0.22), STEEL)
	b.box(Vector3(0, -0.12, 0.5), Vector3(0.05, 0.14, 0.1), POLY, 0.0, 0.18)                          # magazine
	b.box(Vector3(0, -0.17, 0.52), Vector3(0.052, 0.03, 0.1), glow, 0.9, 0.18)
	_grip(b, 0.66)
	b.box(Vector3(0, -0.07, 0.34), Vector3(0.034, 0.08, 0.05), POLY)
	b.box(Vector3(0, -0.01, 0.78), Vector3(0.05, 0.09, 0.2), POLY)
	b.box(Vector3(0, -0.02, 0.88), Vector3(0.044, 0.12, 0.03), DARK)


## CRYSTAL SPIKER: crystals standing on its back (the magazine), tilted shards, a long needle barrel with a glowing tip.
static func _espike(b: WeaponModels._Builder, glow: Color) -> void:
	b.cyl(Vector3(0, 0.0, 0.2), 0.022, 0.4, STEEL, 0.0, 8)
	b.box(Vector3(0, 0.0, 0.0), Vector3(0.03, 0.03, 0.03), glow, 1.0)
	for k in 4:                                                                                       # the crystal magazine: a row of shards, each taller than the one before, leaning back
		var h := 0.1 + 0.035 * float(k)
		b.box(Vector3(0.0, 0.06 + h * 0.5, 0.34 + 0.07 * float(k)), Vector3(0.036, h, 0.034), glow, 0.85, -0.25)
		b.box(Vector3(0.026, 0.05 + h * 0.4, 0.37 + 0.07 * float(k)), Vector3(0.022, h * 0.8, 0.024), glow, 0.6, -0.2)
		b.box(Vector3(-0.026, 0.05 + h * 0.4, 0.37 + 0.07 * float(k)), Vector3(0.022, h * 0.8, 0.024), glow, 0.6, -0.3)
	b.box(Vector3(0, 0.0, 0.5), Vector3(0.08, 0.09, 0.34), GUN)
	b.box(Vector3(0, 0.0, 0.5), Vector3(0.084, 0.02, 0.26), glow, 0.7)
	_grip(b, 0.58)
	b.box(Vector3(0, -0.07, 0.3), Vector3(0.034, 0.08, 0.05), POLY)
	b.box(Vector3(0, -0.01, 0.74), Vector3(0.05, 0.09, 0.18), POLY)
	b.box(Vector3(0, -0.02, 0.84), Vector3(0.044, 0.12, 0.03), DARK)


## PRISM BEAM RIFLE: a long twin-rail barrel with a prism lens at the front, a big scope on top, a thick receiver and a stock.
static func _ebeam(b: WeaponModels._Builder, glow: Color) -> void:
	for sx in [-1.0, 1.0]:
		b.box(Vector3(0.03 * sx, 0.0, 0.34), Vector3(0.016, 0.04, 0.68), STEEL)
		b.box(Vector3(0.03 * sx, 0.0, 0.34), Vector3(0.018, 0.012, 0.6), glow, 0.7)
	b.tube(Vector3(0, 0.0, 0.015), 0.07, 0.05, 0.03, glow, 1.0, 12)                                   # the lens ring
	b.cyl(Vector3(0, 0.0, 0.035), 0.05, 0.01, glow, 0.5, 12)
	b.box(Vector3(0, 0.0, 0.78), Vector3(0.1, 0.12, 0.28), GUN)
	b.box(Vector3(0, 0.05, 0.78), Vector3(0.104, 0.02, 0.2), glow, 0.8)
	b.cyl(Vector3(0, 0.12, 0.5), 0.04, 0.36, DARK, 0.0, 10)                                           # the scope
	b.cyl(Vector3(0, 0.12, 0.31), 0.048, 0.04, STEEL, 0.0, 10)
	b.cyl(Vector3(0, 0.12, 0.3), 0.04, 0.006, glow, 1.0, 10)
	b.cyl(Vector3(0, 0.12, 0.69), 0.05, 0.05, STEEL, 0.0, 10)
	b.box(Vector3(0, 0.065, 0.5), Vector3(0.03, 0.05, 0.1), DARK)
	_grip(b, 0.88, -0.1)
	b.box(Vector3(0, -0.07, 0.56), Vector3(0.034, 0.08, 0.05), POLY)
	b.box(Vector3(0, -0.01, 1.0), Vector3(0.06, 0.1, 0.2), POLY)
	b.box(Vector3(0, -0.02, 1.1), Vector3(0.05, 0.14, 0.03), DARK)


## ION BLADE: a long glowing edge (the tip is the muzzle) from a hilt with a wide crossguard that carries two energy emitters.
static func _eblade(b: WeaponModels._Builder, glow: Color) -> void:
	b.box(Vector3(0, 0.0, 0.42), Vector3(0.012, 0.09, 0.84), glow, 0.55)                              # the energy blade: a soft wide halo ...
	b.box(Vector3(0, 0.0, 0.42), Vector3(0.008, 0.045, 0.82), Color(0.95, 1.0, 1.0), 1.0)             # ... round a white-hot core
	b.box(Vector3(0, 0.0, 0.0), Vector3(0.006, 0.04, 0.014), glow, 1.0)
	b.box(Vector3(0, 0.0, 0.87), Vector3(0.03, 0.26, 0.04), GUN)                                       # the crossguard
	for sy in [-1.0, 1.0]:
		b.box(Vector3(0, 0.12 * sy, 0.85), Vector3(0.036, 0.05, 0.05), glow, 1.0)
		b.box(Vector3(0, 0.15 * sy, 0.9), Vector3(0.03, 0.04, 0.1), STEEL)
	b.cyl(Vector3(0, 0.0, 0.99), 0.017, 0.2, POLY, 0.0, 8)                                             # the hilt
	for k in 3:
		b.cyl(Vector3(0, 0.0, 0.93 + 0.06 * float(k)), 0.0195, 0.012, DARK, 0.0, 8)
	b.cyl(Vector3(0, 0.0, 1.1), 0.025, 0.03, STEEL, 0.0, 8)


## TREMOR MAUL: a massive two-sided head at the muzzle (glowing impact plates and a violet band), a long haft, a counterweight.
static func _emaul(b: WeaponModels._Builder, glow: Color) -> void:
	b.box(Vector3(0, 0.0, 0.0), Vector3(0.34, 0.2, 0.22), GUN)                                         # the head
	for sx in [-1.0, 1.0]:
		b.box(Vector3(0.18 * sx, 0.0, 0.0), Vector3(0.03, 0.23, 0.25), glow, 1.0)                      # glowing impact plates
		b.box(Vector3(0.13 * sx, 0.0, 0.0), Vector3(0.1, 0.24, 0.26), STEEL)
	for sz in [-1.0, 1.0]:                                                                              # thin glowing seams along the top, the head itself stays dark metal
		b.box(Vector3(0, 0.103, 0.075 * sz), Vector3(0.3, 0.012, 0.025), glow, 0.9)
		b.box(Vector3(0, -0.103, 0.075 * sz), Vector3(0.3, 0.012, 0.025), glow, 0.9)
	b.box(Vector3(0, 0.0, 0.113), Vector3(0.2, 0.12, 0.01), glow, 0.6)
	b.cyl(Vector3(0, 0.0, 0.52), 0.032, 0.84, POLY, 0.0, 8)                                            # the haft
	for k in 5:
		b.cyl(Vector3(0, 0.0, 0.3 + 0.12 * float(k)), 0.037, 0.02, glow, 0.5, 8)
	b.box(Vector3(0, 0.0, 0.14), Vector3(0.1, 0.1, 0.06), STEEL)
	b.cyl(Vector3(0, 0.0, 1.0), 0.05, 0.1, DARK, 0.0, 8)                                               # the counterweight
	b.cyl(Vector3(0, 0.0, 1.06), 0.04, 0.02, glow, 0.9, 8)


## HORNET ROCKET POD: a block of six tubes (2 x 3) with glowing rims, a carry handle and a rear grip.
static func _epod(b: WeaponModels._Builder, glow: Color) -> void:
	b.box(Vector3(0, 0.0, 0.46), Vector3(0.2, 0.15, 0.82), GUN)
	for ix in 3:
		for iy in 2:
			var cx := (float(ix) - 1.0) * 0.062
			var cy := (float(iy) - 0.5) * 0.068
			b.tube(Vector3(cx, cy, 0.02), 0.03, 0.021, 0.05, STEEL, 0.0, 8)
			b.tube(Vector3(cx, cy, -0.008), 0.031, 0.024, 0.008, glow, 1.0, 8)
	b.box(Vector3(0, 0.0, 0.1), Vector3(0.21, 0.16, 0.03), STEEL)
	b.box(Vector3(0, 0.0, 0.5), Vector3(0.204, 0.02, 0.5), glow, 0.55)
	b.box(Vector3(0, 0.11, 0.5), Vector3(0.03, 0.05, 0.4), DARK)                                       # carry rail
	b.box(Vector3(0, 0.15, 0.5), Vector3(0.04, 0.014, 0.3), POLY)
	_grip(b, 0.6, -0.14)
	b.box(Vector3(0, -0.13, 0.3), Vector3(0.036, 0.09, 0.05), POLY)
	b.box(Vector3(0, 0.0, 0.92), Vector3(0.22, 0.17, 0.04), DARK)                                          # the rear plate (the hero is seen from behind: dark, with a glowing ring)
	b.tube(Vector3(0, 0.0, 0.945), 0.06, 0.044, 0.012, glow, 1.0, 10)


## COIL RAILGUN: two long rails with copper-glow coils, a capacitor block with a glowing core, a scope, a heavy stock.
static func _railgun(b: WeaponModels._Builder, glow: Color) -> void:
	for sy in [-1.0, 1.0]:
		b.box(Vector3(0, 0.026 * sy, 0.5), Vector3(0.05, 0.016, 1.0), STEEL)
	for k in 7:
		b.tube(Vector3(0, 0.0, 0.06 + 0.13 * float(k)), 0.058, 0.046, 0.034, glow, 0.9, 10)           # the coils
	b.box(Vector3(0, 0.0, 0.0), Vector3(0.05, 0.06, 0.01), glow, 1.0)
	b.box(Vector3(0, 0.0, 1.08), Vector3(0.14, 0.18, 0.3), GUN)                                        # capacitor block
	b.cyl(Vector3(0, 0.0, 1.08), 0.06, 0.34, glow, 0.8, 10)
	b.box(Vector3(0, 0.11, 0.84), Vector3(0.04, 0.05, 0.3), DARK)                                      # optic
	b.cyl(Vector3(0, 0.14, 0.84), 0.034, 0.3, DARK, 0.0, 10)
	b.cyl(Vector3(0, 0.14, 0.68), 0.04, 0.01, glow, 1.0, 10)
	_grip(b, 1.2, -0.13)
	b.box(Vector3(0, -0.1, 0.84), Vector3(0.04, 0.1, 0.05), POLY)
	b.box(Vector3(0, -0.01, 1.32), Vector3(0.07, 0.12, 0.2), POLY)
	b.box(Vector3(0, -0.02, 1.42), Vector3(0.06, 0.16, 0.03), DARK)


## STORM CHAINGUN: six barrels round an axis behind a muzzle ring, a thick gearbox housing, an ammo drum and two heavy handles.
static func _chaingun(b: WeaponModels._Builder, glow: Color) -> void:
	for k in 6:
		var a := TAU * float(k) / 6.0
		b.cyl(Vector3(cos(a) * 0.045, sin(a) * 0.045, 0.2), 0.016, 0.4, STEEL, 0.0, 8)
	b.tube(Vector3(0, 0.0, 0.015), 0.075, 0.06, 0.03, STEEL, 0.0, 12)
	b.tube(Vector3(0, 0.0, 0.2), 0.075, 0.06, 0.03, glow, 0.8, 12)
	b.cyl(Vector3(0, 0.0, 0.5), 0.1, 0.3, GUN, 0.0, 12)                                               # the housing
	b.cyl(Vector3(0, 0.0, 0.5), 0.104, 0.04, glow, 0.9, 12)
	b.cyl(Vector3(0, -0.2, 0.55), 0.13, 0.2, POLY, 0.0, 12)                                           # the drum
	b.cyl(Vector3(0, -0.2, 0.55), 0.134, 0.03, glow, 0.7, 12)
	b.box(Vector3(0, 0.12, 0.5), Vector3(0.03, 0.06, 0.3), DARK)                                       # carry handle
	b.box(Vector3(0, 0.16, 0.5), Vector3(0.05, 0.016, 0.3), POLY)
	_grip(b, 0.7, -0.14)
	b.box(Vector3(0, -0.14, 0.32), Vector3(0.036, 0.1, 0.05), POLY)
	b.box(Vector3(0, 0.0, 0.76), Vector3(0.12, 0.12, 0.08), STEEL)


## HIVE CLUSTER MISSILE: a fat tube with the warhead nose showing at the front (glowing), a sight and a flared exhaust.
static func _cmissile(b: WeaponModels._Builder, glow: Color) -> void:
	b.cyl(Vector3(0, 0.0, 0.46), 0.1, 0.92, GUN, 0.0, 12)
	b.cyl(Vector3(0, 0.0, 0.02), 0.115, 0.05, STEEL, 0.0, 12)
	b.cyl(Vector3(0, 0.0, 0.1), 0.07, 0.14, STEEL, 0.0, 10)                                            # the missile nose inside the mouth
	b.cyl(Vector3(0, 0.0, 0.025), 0.045, 0.05, glow, 1.0, 10)
	for k in 3:
		b.cyl(Vector3(0, 0.0, 0.3 + 0.2 * float(k)), 0.104, 0.024, glow, 0.8, 12)
	b.cyl(Vector3(0, 0.0, 0.96), 0.12, 0.1, STEEL, 0.0, 12)
	b.box(Vector3(0, 0.14, 0.45), Vector3(0.05, 0.06, 0.22), DARK)
	b.box(Vector3(0, 0.178, 0.45), Vector3(0.06, 0.014, 0.16), POLY)
	b.box(Vector3(0, 0.178, 0.38), Vector3(0.03, 0.01, 0.004), glow, 1.0)
	_grip(b, 0.64, -0.14)
	b.box(Vector3(0, -0.13, 0.3), Vector3(0.036, 0.09, 0.05), POLY)
	b.box(Vector3(0, -0.1, 0.5), Vector3(0.05, 0.05, 0.3), POLY)


## CINDER NAPALM LAUNCHER: a stubby wide barrel with fire-orange bands, a fuel tank slung underneath and a pump grip.
static func _napalm(b: WeaponModels._Builder, glow: Color) -> void:
	b.cyl(Vector3(0, 0.0, 0.3), 0.075, 0.6, GUN, 0.0, 12)
	b.cyl(Vector3(0, 0.0, 0.02), 0.095, 0.05, STEEL, 0.0, 12)
	b.cyl(Vector3(0, 0.0, 0.0), 0.09, 0.012, glow, 1.0, 12)
	b.cyl(Vector3(0, 0.0, 0.18), 0.082, 0.026, glow, 0.9, 12)
	b.cyl(Vector3(0, 0.0, 0.42), 0.082, 0.026, glow, 0.9, 12)
	b.cyl(Vector3(0, -0.14, 0.46), 0.085, 0.46, POLY, 0.0, 12)                                        # the fuel tank
	b.cyl(Vector3(0, -0.14, 0.46), 0.089, 0.04, glow, 0.8, 12)
	b.cyl(Vector3(0, -0.14, 0.62), 0.089, 0.04, glow, 0.8, 12)
	b.box(Vector3(0, -0.07, 0.46), Vector3(0.03, 0.08, 0.2), STEEL)
	b.box(Vector3(0, 0.1, 0.4), Vector3(0.03, 0.05, 0.14), DARK)
	b.box(Vector3(0, 0.0, 0.66), Vector3(0.1, 0.12, 0.14), GUN)
	_grip(b, 0.7, -0.11)
	b.box(Vector3(0, -0.01, 0.82), Vector3(0.06, 0.1, 0.16), POLY)
	b.box(Vector3(0, -0.04, 0.2), Vector3(0.036, 0.08, 0.09), POLY)


## VOID SINGULARITY CANNON: a wide funnel round a dark violet core, tapering into a coil body with violet rings, a big side cell.
static func _sing(b: WeaponModels._Builder, glow: Color) -> void:
	b.tube(Vector3(0, 0.0, 0.03), 0.14, 0.11, 0.06, STEEL, 0.0, 14)
	b.tube(Vector3(0, 0.0, 0.11), 0.115, 0.09, 0.09, GUN, 0.0, 14)
	b.tube(Vector3(0, 0.0, 0.0), 0.142, 0.112, 0.014, glow, 1.0, 14)
	b.cyl(Vector3(0, 0.0, 0.17), 0.09, 0.012, glow, 0.5, 12)                                          # the core deep inside
	b.cyl(Vector3(0, 0.0, 0.36), 0.085, 0.36, GUN, 0.0, 12)
	for k in 4:
		b.cyl(Vector3(0, 0.0, 0.24 + 0.1 * float(k)), 0.092, 0.024, glow, 0.9, 12)
	b.cyl(Vector3(0, 0.0, 0.64), 0.12, 0.26, POLY, 0.0, 12)
	b.cyl(Vector3(0, 0.0, 0.64), 0.124, 0.05, glow, 1.0, 12)
	b.cyl(Vector3(0.12, 0.04, 0.5), 0.05, 0.2, STEEL, 0.0, 10)                                         # a side cell
	b.cyl(Vector3(0.12, 0.04, 0.5), 0.054, 0.04, glow, 0.9, 10)
	b.box(Vector3(0, 0.14, 0.5), Vector3(0.03, 0.05, 0.16), DARK)
	_grip(b, 0.7, -0.14)
	b.box(Vector3(0, -0.14, 0.4), Vector3(0.04, 0.1, 0.05), POLY)
	b.box(Vector3(0, 0.0, 0.86), Vector3(0.08, 0.12, 0.14), POLY)


## ORBITAL STRIKE BEACON: a short tube with a target-painting lens, a tall antenna with a glowing tip, a status ring.
static func _orbital(b: WeaponModels._Builder, glow: Color) -> void:
	b.cyl(Vector3(0, 0.0, 0.2), 0.06, 0.4, GUN, 0.0, 10)
	b.tube(Vector3(0, 0.0, 0.01), 0.07, 0.05, 0.02, glow, 1.0, 12)
	b.cyl(Vector3(0, 0.0, 0.02), 0.05, 0.008, glow, 0.5, 12)
	b.cyl(Vector3(0, 0.0, 0.3), 0.066, 0.03, glow, 0.9, 12)
	b.box(Vector3(0, 0.06, 0.38), Vector3(0.016, 0.3, 0.016), STEEL)                                   # the antenna
	b.box(Vector3(0, 0.22, 0.38), Vector3(0.04, 0.03, 0.04), glow, 1.0)
	b.box(Vector3(0, 0.13, 0.38), Vector3(0.1, 0.012, 0.012), STEEL)
	b.box(Vector3(0, 0.0, 0.5), Vector3(0.1, 0.1, 0.2), POLY)
	b.box(Vector3(0, 0.054, 0.5), Vector3(0.06, 0.006, 0.1), glow, 0.8)
	_grip(b, 0.52)
	b.box(Vector3(0, -0.07, 0.24), Vector3(0.034, 0.08, 0.05), POLY)
	b.box(Vector3(0, -0.01, 0.66), Vector3(0.05, 0.09, 0.14), POLY)


## SEEKER GUIDED LAUNCHER: a long tube with a flared mouth, a big seeker sight on the left (a lens that glows) and a flared exhaust.
static func _seeker(b: WeaponModels._Builder, glow: Color) -> void:
	b.cyl(Vector3(0, 0.0, 0.46), 0.068, 0.92, GUN, 0.0, 12)
	b.tube(Vector3(0, 0.0, 0.025), 0.09, 0.066, 0.05, STEEL, 0.0, 12)
	b.tube(Vector3(0, 0.0, 0.0), 0.092, 0.068, 0.012, glow, 1.0, 12)
	b.cyl(Vector3(0, 0.0, 0.97), 0.1, 0.1, STEEL, 0.0, 12)
	b.cyl(Vector3(0, 0.0, 0.3), 0.074, 0.02, glow, 0.7, 12)
	b.box(Vector3(-0.1, 0.03, 0.4), Vector3(0.1, 0.1, 0.3), POLY)                                      # the seeker sight
	b.cyl(Vector3(-0.1, 0.03, 0.22), 0.04, 0.03, STEEL, 0.0, 10)
	b.cyl(Vector3(-0.1, 0.03, 0.205), 0.034, 0.008, glow, 1.0, 10)
	b.box(Vector3(-0.05, 0.03, 0.4), Vector3(0.06, 0.03, 0.1), DARK)
	b.box(Vector3(0, 0.09, 0.55), Vector3(0.03, 0.05, 0.2), DARK)
	_grip(b, 0.64, -0.12)
	b.box(Vector3(0, -0.12, 0.32), Vector3(0.036, 0.09, 0.05), POLY)


## THROWING KNIVES: a small balanced blade with a glowing fuller, a wrapped handle and a pommel ring.
static func _tknife(b: WeaponModels._Builder, glow: Color) -> void:
	b.box(Vector3(0, 0.0, 0.1), Vector3(0.005, 0.034, 0.2), STEEL)
	b.box(Vector3(0, 0.0, 0.1), Vector3(0.007, 0.01, 0.18), glow, 0.6)
	b.box(Vector3(0, 0.0, 0.0), Vector3(0.004, 0.016, 0.012), glow, 1.0)
	b.box(Vector3(0, 0.0, 0.21), Vector3(0.016, 0.06, 0.016), GUN)
	b.cyl(Vector3(0, 0.0, 0.29), 0.013, 0.14, DARK, 0.0, 8)
	for k in 4:
		b.cyl(Vector3(0, 0.0, 0.24 + 0.03 * float(k)), 0.0145, 0.008, POLY, 0.0, 8)
	b.tube(Vector3(0, 0.0, 0.37), 0.02, 0.012, 0.01, STEEL, 0.0, 8)
