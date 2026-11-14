class_name WeaponModelsV3
extends RefCounted
## Procedural models of the roster pack of wave 113 (one mesh and one draw each, the weapon_look shader, built from boxes and cylinders like WeaponModels). The shape is read from the weapon's
## own def: its family sets the frame (length, stock, magazine, scope) and its mechanics add the parts you can see (a suppressor for silent, a heavy brake for knock, coil rings for zap, frost fins
## for chill, vents for burn, shards for dissolve, a sensor pod for mark, an underbarrel tube for the grenade alt, a bipod for the bipod alt, a second scope for the scope switch) so no two weapons
## look alike and a player can tell what a weapon does by looking at it. Mesh frame: origin = muzzle, barrel toward -Z, body toward +Z, y up (grips: WeaponDefsV3 spec rows).
## The Blender weapon kit of wave 114 replaces these with modelled meshes; ids and frames stay the same.

const GUN := WeaponModels.GUN
const POLY := WeaponModels.POLY
const DARK := WeaponModels.DARK
const STEEL := WeaponModels.STEEL
const BRASS := WeaponModels.BRASS
const ICE := Color(0.62, 0.86, 1.0)

## family -> frame: L total length, bar share of the length in front of the receiver, stock kind, magazine kind, top kind, receiver half height
const STYLE := {
	&"smg": {"L": 0.62, "bar": 0.36, "stock": &"skel", "mag": &"long", "top": &"dot", "rh": 0.036},
	&"assault": {"L": 0.95, "bar": 0.42, "stock": &"solid", "mag": &"curved", "top": &"dot", "rh": 0.04},
	&"battle": {"L": 1.0, "bar": 0.45, "stock": &"solid", "mag": &"straight", "top": &"scope", "rh": 0.042},
	&"carbine": {"L": 0.78, "bar": 0.36, "stock": &"skel", "mag": &"curved", "top": &"dot", "rh": 0.038},
	&"dmr": {"L": 1.05, "bar": 0.5, "stock": &"solid", "mag": &"straight", "top": &"scope", "rh": 0.04},
	&"sniper": {"L": 1.12, "bar": 0.52, "stock": &"solid", "mag": &"box", "top": &"scope", "rh": 0.04},
	&"shotgun": {"L": 0.9, "bar": 0.46, "stock": &"solid", "mag": &"tube", "top": &"iron", "rh": 0.04},
	&"lmg": {"L": 0.95, "bar": 0.4, "stock": &"solid", "mag": &"drumbox", "top": &"dot", "rh": 0.05},
	&"rotary": {"L": 0.9, "bar": 0.5, "stock": &"none", "mag": &"drumbox", "top": &"iron", "rh": 0.05},
	&"energy": {"L": 0.8, "bar": 0.42, "stock": &"skel", "mag": &"cell", "top": &"dot", "rh": 0.042},
	&"quantum": {"L": 0.78, "bar": 0.4, "stock": &"none", "mag": &"cell", "top": &"iron", "rh": 0.04},
}

static func build(b: WeaponModels._Builder, id: StringName, glow: Color) -> void:
	_cur_id = id
	var d := WeaponDefs.def(id)
	var fam := StringName(d.get("family", &"assault"))
	if String(d["kind"]) == "melee":
		_melee(b, id, d, glow)
	elif fam == &"exotic":
		_exotic(b, id, d, glow)
	elif fam == &"bow":
		_bow(b, id, d, glow)
	elif fam == &"flamer":
		_sprayer(b, id, d, glow)
	elif fam == &"pistol":
		_pistol(b, id, d, glow)
	else:
		_rifle(b, fam, d, glow)


## A frustum between two rectangles: front (z0, half width w0, half height h0, centre y0) and back (z1, w1, h1, y1): tapered blades, wedges, curved segments. Normals point out of the solid.
static func _prism(b: WeaponModels._Builder, z0: float, w0: float, h0: float, y0: float, z1: float, w1: float, h1: float, y1: float, col: Color, g := 0.0, x := 0.0) -> void:
	var c: Array[Vector3] = [
		Vector3(x - w0, y0 - h0, z0), Vector3(x + w0, y0 - h0, z0), Vector3(x + w0, y0 + h0, z0), Vector3(x - w0, y0 + h0, z0),
		Vector3(x - w1, y1 - h1, z1), Vector3(x + w1, y1 - h1, z1), Vector3(x + w1, y1 + h1, z1), Vector3(x - w1, y1 + h1, z1)]
	var mid := Vector3.ZERO
	for v in c:
		mid += v
	mid /= 8.0
	for f: Array in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [3, 2, 6, 7], [0, 3, 7, 4], [1, 2, 6, 5]]:
		var p0: Vector3 = c[f[0]]
		var p1: Vector3 = c[f[1]]
		var p2: Vector3 = c[f[2]]
		var p3: Vector3 = c[f[3]]
		var n := (p1 - p0).cross(p3 - p0)
		if n.length() < 0.000001:
			n = (p2 - p1).cross(p0 - p1)
		n = n.normalized()
		if n.dot((p0 + p1 + p2 + p3) * 0.25 - mid) < 0.0:
			n = -n
		b.quad(p0, p1, p2, p3, n, col, g)


## The body colour of a gun: the tier and the seed pick a shade (low tiers are dark polymer, high tiers lighter alloys with colour), so a rack of weapons does not look like one grey gun.
static func _body(d: Dictionary) -> Color:
	var seed_ := int(d.get("model_seed", 1))
	var tier := int(d.get("tier", 2))
	var base: Color = [GUN, GUN.lightened(0.1), Color(0.19, 0.2, 0.23), Color(0.16, 0.19, 0.15), Color(0.22, 0.19, 0.15), Color(0.2, 0.17, 0.2)][seed_ % 6]
	return base.lerp(Color(0.5, 0.54, 0.62), clampf(float(tier - 3) * 0.1, 0.0, 0.3))


static func _bx(b: WeaponModels._Builder, x: float, y: float, z: float, sx: float, sy: float, sz: float, col: Color, g := 0.0, rx := 0.0) -> void:
	b.box(Vector3(x, y, z), Vector3(sx, sy, sz), col, g, rx)


## The visible marks of the mechanics: used by every gun builder. `zb` = z of the front of the receiver, `bar_y` = barrel height.
static func _marks(b: WeaponModels._Builder, d: Dictionary, glow: Color, zb: float, bar_y: float, bar_r: float) -> void:
	var seed_ := int(d.get("model_seed", 1))
	if bool(d.get("silent", false)):                                                                       # suppressor
		b.cyl(Vector3(0, bar_y, 0.0 + 0.08), 0.026, 0.17, DARK, 0.0, 10)
		b.cyl(Vector3(0, bar_y, 0.0), 0.02, 0.02, STEEL, 0.0, 8)
	elif float(d.get("knock", 0.0)) >= 2.0 or d.has("sunder") or float(d.get("kick", 0.0)) > 0.025:        # heavy brake
		_bx(b, 0, bar_y, 0.04, 0.058, 0.058, 0.09, STEEL)
		_bx(b, 0, bar_y, 0.04, 0.062, 0.014, 0.05, glow, 1.0)
	elif seed_ % 3 == 0:                                                                                   # a flash hider
		b.cyl(Vector3(0, bar_y, 0.03), bar_r * 1.9, 0.06, STEEL, 0.0, 6)
	if d.has("zap"):                                                                                       # coil rings
		for i in 3:
			b.tube(Vector3(0, bar_y, zb * (0.25 + 0.2 * float(i))), bar_r * 3.2, bar_r * 2.0, 0.025, STEEL, 0.0, 10)
			b.tube(Vector3(0, bar_y, zb * (0.25 + 0.2 * float(i))), bar_r * 2.5, bar_r * 2.2, 0.012, glow, 1.0, 10)
	if d.has("chill") or bool(d.get("mist", false)) and not d.has("dissolve"):                             # frost fins
		for sgn in [-1.0, 1.0]:
			_bx(b, 0.04 * sgn, bar_y, zb * 0.5, 0.01, 0.06, zb * 0.5, ICE, 0.7)
	if d.has("burn") and not bool(d.get("flame", false)):                                                  # heat vents
		for i in 4:
			_bx(b, 0.0, bar_y + bar_r * 2.2, zb * (0.15 + 0.17 * float(i)), 0.022, 0.012, 0.03, Color(1.0, 0.45, 0.12), 1.0)
	if d.has("dissolve"):                                                                                  # violet shards at the muzzle
		for i in 3:
			_bx(b, 0.02 * float(i - 1), bar_y + 0.02 * float(i % 2), 0.0 + 0.02 * float(i), 0.012, 0.05, 0.016, glow, 1.0, 0.5 * float(i - 1))
	if d.has("mark"):                                                                                      # a sensor pod on the side
		_bx(b, 0.04, bar_y + 0.012, zb * 0.55, 0.026, 0.026, 0.05, DARK)
		_bx(b, 0.04, bar_y + 0.012, zb * 0.55 - 0.027, 0.018, 0.018, 0.006, Color(1.0, 0.35, 0.85), 1.0)
	if d.has("ricochet"):                                                                                  # a bent deflector plate under the muzzle
		_bx(b, 0.0, bar_y - 0.035, 0.05, 0.03, 0.01, 0.1, STEEL, 0.0, 0.3)
	if d.has("pull"):                                                                                      # a dish and a hook ring
		b.tube(Vector3(0, bar_y, 0.02), bar_r * 3.6, bar_r * 2.2, 0.03, STEEL, 0.0, 10)
		b.tube(Vector3(0, bar_y, -0.01), bar_r * 2.6, bar_r * 2.0, 0.01, glow, 1.0, 10)
	if d.has("crit_blast"):                                                                                # a shard bulb
		b.cyl(Vector3(0, bar_y, zb * 0.35), bar_r * 3.0, 0.05, DARK, 0.0, 8)
		_bx(b, 0.0, bar_y, zb * 0.35, bar_r * 3.4, 0.01, 0.052, glow, 1.0)
	var alt: Dictionary = WeaponDefs.alt_of(StringName(d.get("id_ref", &"")))
	var kind := String(alt.get("kind", ""))
	if kind == "ub_nade":                                                                                  # underbarrel launcher tube
		b.cyl(Vector3(0, bar_y - 0.05, zb * 0.55), 0.021, zb * 0.9, DARK, 0.0, 8)
		_bx(b, 0.0, bar_y - 0.05, zb * 0.55 - zb * 0.45, 0.034, 0.034, 0.01, glow, 1.0)
	elif kind == "brace":                                                                                  # a folded bipod
		for sgn in [-1.0, 1.0]:
			_bx(b, 0.03 * sgn, bar_y - 0.06, zb * 0.6, 0.008, 0.1, 0.008, DARK, 0.0, 0.5 * sgn)
	elif kind == "zoom":                                                                                   # a small flip-up scope beside the main sight
		b.cyl(Vector3(0.035, bar_y + 0.065, zb + 0.08), 0.014, 0.1, DARK, 0.0, 8)
		_bx(b, 0.035, bar_y + 0.065, zb + 0.08 - 0.052, 0.022, 0.022, 0.004, glow, 1.0)


static func _grip(b: WeaponModels._Builder, z: float, y: float, col: Color) -> void:
	_bx(b, 0, y, z, 0.034, 0.1, 0.042, col, 0.0, -0.3)


static func _rifle(b: WeaponModels._Builder, fam: StringName, d: Dictionary, glow: Color) -> void:
	var st: Dictionary = STYLE.get(fam, STYLE[&"assault"])
	var seed_ := int(d.get("model_seed", 1))
	var lf := float(d.get("mlen", 1.0))
	var energy := fam == &"energy" or fam == &"quantum"
	var heavy := fam == &"lmg" or fam == &"rotary" or fam == &"shotgun"
	var kind := String(d["kind"])
	var bodyc := _body(d)
	var L := float(st["L"]) * lf * (0.94 + 0.12 * float(seed_ % 5) / 4.0)
	var rh := float(st["rh"]) * (0.9 + 0.2 * float((seed_ / 7) % 3) / 2.0)
	var rw := 0.05 + (0.012 if heavy else 0.0) + 0.006 * float(seed_ % 3)
	var zb := L * float(st["bar"]) * (0.88 + 0.24 * float((seed_ / 3) % 4) / 3.0)                                   # the barrel length varies with the seed
	var rl := L * (0.24 + 0.05 * float((seed_ / 5) % 3) / 2.0)
	var zr := zb + rl
	L = maxf(L, zr + 0.14)
	var bar_y := 0.004
	var bar_r := 0.011 + (0.003 if int(d.get("pellets", 1)) > 3 else 0.0)
	var hv := (seed_ / 11) % 4
	var tv := (seed_ / 13) % 4
	var sv := (seed_ / 17) % 3
	var mv := (seed_ / 19) % 3
	# barrel
	b.cyl(Vector3(0, bar_y, zb * 0.5), bar_r, zb, STEEL, 0.0, 8)
	# handguard
	var hg := zb * (0.72 if fam != &"sniper" else 0.42)
	var hgz := zb - hg * 0.5
	var hgw := 0.048 + (0.012 if heavy else 0.0)
	var hgh := 0.058 + (0.01 if heavy else 0.0)
	if hv == 3 and not energy:
		hg *= 0.7
		hgz = zb - hg * 0.5
	_bx(b, 0, 0.0, hgz, hgw, hgh, hg, POLY if hv % 2 == 0 else bodyc.darkened(0.15))
	if hv == 1:                                                                                                        # ribbed: dark slots along the sides
		for i in 5:
			for sgn in [-1.0, 1.0]:
				_bx(b, (hgw * 0.5 + 0.002) * sgn, 0.0, hgz - hg * 0.4 + hg * 0.2 * float(i), 0.004, hgh * 0.5, hg * 0.08, DARK)
	elif hv == 2:                                                                                                      # a quad rail: four small rails on the corners
		for sgx in [-1.0, 1.0]:
			for sgy in [-1.0, 1.0]:
				_bx(b, sgx * hgw * 0.5, sgy * hgh * 0.5, hgz, 0.01, 0.01, hg, STEEL)
	elif hv == 3:                                                                                                      # a short guard and a vertical foregrip
		_bx(b, 0, -hgh * 0.5 - 0.04, hgz, 0.028, 0.08, 0.036, DARK)
	if fam == &"shotgun":
		b.cyl(Vector3(0, bar_y - 0.034, zb * 0.5), 0.016, zb * 0.9, DARK, 0.0, 8)                                      # magazine tube under the barrel
		_bx(b, 0, -0.012, zb * 0.78, 0.05, 0.036, 0.14, GUN)                                                           # the pump
	if fam == &"rotary":                                                                                               # a cluster of barrels in a shroud
		for i in 6:
			var a := TAU * float(i) / 6.0
			b.cyl(Vector3(cos(a) * 0.03, bar_y + sin(a) * 0.03, zb * 0.5), 0.008, zb, STEEL, 0.0, 6)
		b.tube(Vector3(0, bar_y, zb * 0.55), 0.052, 0.04, 0.03, DARK, 0.0, 10)
		b.tube(Vector3(0, bar_y, 0.03), 0.052, 0.04, 0.03, DARK, 0.0, 10)
	if energy:                                                                                                         # emitters: four looks
		var ev := seed_ % 4
		match ev:
			0:
				for sgn in [-1.0, 1.0]:                                                                                # twin prongs
					_bx(b, 0.04 * sgn, 0.0, zb * 0.5, 0.012, 0.03, zb, STEEL)
				_bx(b, 0.0, 0.0, 0.01, 0.07, 0.016, 0.012, glow, 1.0)
			1:
				for i in 3:                                                                                            # emitter rings
					b.tube(Vector3(0, bar_y, 0.03 + zb * 0.2 * float(i)), 0.034, 0.016, 0.03, STEEL, 0.0, 10)
					b.tube(Vector3(0, bar_y, 0.03 + zb * 0.2 * float(i)), 0.028, 0.02, 0.012, glow, 1.0, 10)
			2:
				b.tube(Vector3(0, bar_y, 0.02), 0.05, 0.04, 0.04, STEEL, 0.0, 12)                                      # one open ring
				b.cyl(Vector3(0, bar_y, 0.1), 0.02, 0.1, DARK, 0.0, 8)
				b.cyl(Vector3(0, bar_y, 0.0), 0.012, 0.03, glow, 1.0, 8)
			_:
				for i in 3:                                                                                            # a bundle of three small barrels
					var a2 := TAU * float(i) / 3.0 + 0.5
					b.cyl(Vector3(cos(a2) * 0.022, bar_y + sin(a2) * 0.022, zb * 0.4), 0.007, zb * 0.9, STEEL, 0.0, 6)
					b.cyl(Vector3(cos(a2) * 0.022, bar_y + sin(a2) * 0.022, 0.0), 0.009, 0.01, glow, 1.0, 6)
	_bx(b, 0.0285, 0.0, hgz, 0.004, 0.02, hg * 0.8, glow, 1.0)
	_bx(b, -0.0285, 0.0, hgz, 0.004, 0.02, hg * 0.8, glow, 1.0)
	# receiver: a plain block, or a stepped one
	_bx(b, 0, 0.0, zb + rl * 0.5, rw, rh * 2.0, rl, bodyc)
	if seed_ % 3 == 1:
		_bx(b, 0, rh * 0.8, zb + rl * 0.35, rw * 0.9, rh * 0.8, rl * 0.6, bodyc.lightened(0.08))
	_bx(b, 0, rh + 0.006, zb + rl * 0.5, 0.024, 0.014, rl + 0.1, STEEL)                                                # top rail
	# top
	var scope_kind := StringName(d.get("scope", &""))
	var top := StringName(st["top"])
	if scope_kind == &"sniper" or scope_kind == &"x4" or (top == &"scope" and float(d["zoom"]) < 40.0):
		var sl := 0.2 + 0.08 * float(scope_kind == &"sniper")
		b.cyl(Vector3(0, rh + 0.052, zb + rl * 0.5), 0.025, sl, DARK, 0.0, 10)
		b.cyl(Vector3(0, rh + 0.052, zb + rl * 0.5 - sl * 0.5), 0.032, 0.04, POLY, 0.0, 10)
		b.cyl(Vector3(0, rh + 0.052, zb + rl * 0.5 + sl * 0.5), 0.028, 0.04, POLY, 0.0, 10)
		_bx(b, 0, rh + 0.052, zb + rl * 0.5 - sl * 0.5 - 0.022, 0.04, 0.04, 0.004, glow, 1.0)
		if scope_kind == &"thermal":
			_bx(b, 0.0, rh + 0.052, zb + rl * 0.5, 0.05, 0.05, sl * 0.6, DARK)
			_bx(b, 0.0, rh + 0.052, zb + rl * 0.5 - sl * 0.3 - 0.01, 0.036, 0.036, 0.006, Color(1.0, 0.2, 0.15), 1.0)
	elif scope_kind == &"x2" or top == &"scope":
		b.cyl(Vector3(0, rh + 0.045, zb + rl * 0.5), 0.02, 0.13, DARK, 0.0, 8)
		_bx(b, 0, rh + 0.045, zb + rl * 0.5 - 0.068, 0.03, 0.03, 0.004, glow, 1.0)
	elif tv == 0:
		_bx(b, 0, rh + 0.03, zb + rl * 0.4, 0.028, 0.03, 0.06, DARK)                                                   # a red dot
		_bx(b, 0, rh + 0.03, zb + rl * 0.4 - 0.032, 0.016, 0.016, 0.004, glow, 1.0)
	elif tv == 1:
		for sgn in [-1.0, 1.0]:                                                                                        # a holo frame
			_bx(b, 0.018 * sgn, rh + 0.034, zb + rl * 0.4, 0.006, 0.04, 0.05, DARK)
		_bx(b, 0.0, rh + 0.054, zb + rl * 0.4, 0.042, 0.008, 0.05, DARK)
		_bx(b, 0.0, rh + 0.036, zb + rl * 0.4 - 0.022, 0.03, 0.03, 0.004, glow, 0.6)
	elif tv == 2:
		_bx(b, 0.0, rh + 0.04, zb + rl * 0.35, 0.016, 0.014, rl * 0.7, STEEL)                                          # a carry handle
		for z in [zb + rl * 0.05, zb + rl * 0.65]:
			_bx(b, 0.0, rh + 0.022, z, 0.016, 0.034, 0.016, STEEL)
	else:
		_bx(b, 0, rh + 0.024, 0.04, 0.008, 0.016, 0.012, STEEL)
		_bx(b, 0, rh + 0.024, zr - 0.02, 0.02, 0.016, 0.012, STEEL)
	# magazine
	var mag := int(d.get("mag", 30))
	var mk := StringName(st["mag"])
	var mz := zb + rl * 0.45
	if energy:
		var cv := (seed_ / 3) % 3
		if cv == 0:
			_bx(b, 0, -rh - 0.045, mz, 0.05, 0.07, 0.12, DARK)                                                         # a cell under the receiver with a window
			_bx(b, 0.0265, -rh - 0.045, mz, 0.004, 0.04, 0.08, glow, 1.0)
			_bx(b, -0.0265, -rh - 0.045, mz, 0.004, 0.04, 0.08, glow, 1.0)
		elif cv == 1:
			b.cyl(Vector3(0, rh + 0.022, zb + rl * 0.6), 0.034, rl * 0.6, DARK, 0.0, 10)                              # a cylinder on the back
			b.tube(Vector3(0, rh + 0.022, zb + rl * 0.6), 0.036, 0.03, 0.02, glow, 1.0, 10)
		else:
			_bx(b, 0.0, -rh - 0.03, mz, 0.04, 0.05, 0.16, DARK)
			for i in 3:
				_bx(b, 0.0, -rh - 0.058, mz - 0.05 + 0.05 * float(i), 0.03, 0.01, 0.03, glow, 1.0)
	elif mk == &"tube":
		_bx(b, 0, -0.012, zb + rl * 0.3, 0.05, 0.03, 0.1, DARK)
	elif mag >= 100 or mk == &"drumbox":
		_bx(b, 0, -rh - 0.07, mz, 0.07, 0.12, 0.12, POLY)
		_bx(b, 0.0, -rh - 0.01, zb + rl * 0.15, 0.02, 0.012, 0.1, BRASS)
	elif mag >= 50:
		b.cyl(Vector3(0, -rh - 0.07, mz), 0.075, 0.06, POLY, 0.0, 14, Basis(Vector3.UP, PI * 0.5))
		_bx(b, 0, -rh - 0.012, mz, 0.034, 0.03, 0.05, DARK)
	else:
		var mh := 0.07 + 0.0035 * float(mini(mag, 40))
		if mv == 0:
			_bx(b, 0, -rh - mh * 0.5, mz, 0.034, mh, 0.05, DARK)
		elif mv == 1:
			_bx(b, 0, -rh - mh * 0.5, mz + 0.02, 0.034, mh, 0.05, DARK, 0.0, -0.22)
		else:
			_bx(b, 0, -rh - mh * 0.5, mz - 0.02, 0.034, mh, 0.036, DARK)
			_bx(b, 0, -rh - mh * 0.5, mz + 0.022, 0.034, mh * 0.9, 0.036, DARK)
	_grip(b, zb + rl * 0.8, -rh - 0.05, DARK)
	_bx(b, 0, -rh - 0.01, zb + rl * 0.6, 0.012, 0.03, 0.05, POLY)                                                      # trigger guard
	# stock
	var stock := StringName(st["stock"])
	if sv == 1 and stock == &"solid":
		stock = &"skel"
	elif sv == 1 and stock == &"skel":
		stock = &"solid"
	var sl2 := L - zr
	if sv == 2 and stock != &"none":                                                                                   # folded: a short stub with a hinge
		_bx(b, 0, 0.0, zr + 0.04, 0.036, 0.05, 0.08, POLY)
		_bx(b, 0.0, 0.0, zr + 0.09, 0.02, 0.07, 0.02, STEEL)
	elif stock == &"solid":
		_prism(b, zr, 0.025, 0.04, 0.0, L - 0.02, 0.022, 0.058, -0.01, POLY)
		_bx(b, 0, 0.045, zr + sl2 * 0.3, 0.04, 0.026, sl2 * 0.5, DARK)
		_bx(b, 0, -0.01, L - 0.01, 0.044, 0.12, 0.028, DARK)
	elif stock == &"skel":
		for sgn in [-1.0, 1.0]:
			_bx(b, 0.016 * sgn, 0.012, zr + sl2 * 0.5, 0.012, 0.016, sl2, STEEL)
		_bx(b, 0, 0.012, zr + sl2 * 0.5, 0.012, 0.03, 0.02, STEEL)
		_bx(b, 0, -0.012, L - 0.01, 0.04, 0.095, 0.028, POLY)
	if fam == &"shotgun" or fam == &"lmg":
		_bx(b, 0.0, rh * 0.5, zb + rl * 0.2, 0.014, 0.016, 0.03, BRASS)                                                # the ejection port
	if kind == "charge":                                                                                               # capacitor blocks along the barrel
		for i in 3:
			_bx(b, 0.0, 0.05, zb * (0.2 + 0.25 * float(i)), 0.03, 0.04, 0.05, DARK)
			_bx(b, 0.0, 0.074, zb * (0.2 + 0.25 * float(i)), 0.022, 0.006, 0.04, glow, 1.0)
	_marks(b, _with_id(d), glow, zb, bar_y, bar_r)
	if not bool(d.get("silent", false)) and float(d.get("knock", 0.0)) < 2.0 and seed_ % 4 == 1 and not energy:       # a vented compensator
		_bx(b, 0, bar_y, 0.03, 0.04, 0.04, 0.06, STEEL)
		for sgn in [-1.0, 1.0]:
			_bx(b, 0.021 * sgn, bar_y, 0.03, 0.004, 0.02, 0.04, DARK)
	_bx(b, 0.0, 0.0, zb * 0.5, 0.004, 0.006, zb * 0.8, glow, 1.0)
	if seed_ % 2 == 0 and not energy:
		_bx(b, 0.0, rh * 0.2, zb + rl * 0.5, rw + 0.002, 0.004, rl * 0.7, glow, 0.6)                                  # a glow seam in the receiver


## `_marks` reads the alt-fire of the weapon: the def carries no id, so the builder entry puts it back.
static var _cur_id: StringName = &""


static func _with_id(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	out["id_ref"] = _cur_id
	return out


static func _pistol(b: WeaponModels._Builder, id: StringName, d: Dictionary, glow: Color) -> void:
	var seed_ := int(d.get("model_seed", 1))
	var lf := float(d.get("mlen", 1.0))
	var big := float(d.get("damage", 20.0)) > 50.0
	var mag := int(d.get("mag", 12))
	var bodyc := _body(d)
	_cur_id = id
	if big:                                                                                                         # a hand cannon: a revolver frame
		b.cyl(Vector3(0, 0.012, 0.13), 0.019, 0.26, STEEL, 0.0, 8)
		b.cyl(Vector3(0, 0.002, 0.28), 0.046, 0.08, bodyc, 0.0, 10)
		for k in 6:
			var a := TAU * float(k) / 6.0
			b.cyl(Vector3(cos(a) * 0.03, 0.002 + sin(a) * 0.03, 0.28), 0.009, 0.082, DARK, 0.0, 8)
		_bx(b, 0, 0.0, 0.34, 0.04, 0.06, 0.07, bodyc)
		_bx(b, 0, 0.044, 0.37, 0.014, 0.026, 0.028, STEEL, 0.0, 0.5)
		_bx(b, 0, -0.07, 0.38, 0.038, 0.12, 0.06, DARK, 0.0, -0.3)
		_bx(b, 0.0, 0.034, 0.12, 0.012, 0.016, 0.24, STEEL)
		_bx(b, 0.0215, 0.002, 0.28, 0.004, 0.018, 0.06, glow, 1.0)
		_marks(b, _with_id(d), glow, 0.26, 0.012, 0.019)
		return
	var frame := seed_ % 3
	var L := (0.2 + (0.06 if bool(d.get("silent", false)) else 0.0) + (0.04 if frame == 1 else 0.0)) * lf
	var sw := 0.036 + (0.006 if frame == 2 else 0.0)
	_bx(b, 0, 0.0, 0.01 + L * 0.5, sw, 0.05, L, bodyc)                                                              # slide
	_bx(b, 0, 0.0255, 0.01 + L * 0.5, 0.02, 0.006, L - 0.04, STEEL)
	if frame == 0:                                                                                                  # serrations and a bare barrel tip
		for i in 5:
			_bx(b, (sw * 0.5 + 0.002), 0.0, 0.01 + L * 0.7 + 0.014 * float(i - 2), 0.004, 0.036, 0.006, DARK)
			_bx(b, -(sw * 0.5 + 0.002), 0.0, 0.01 + L * 0.7 + 0.014 * float(i - 2), 0.004, 0.036, 0.006, DARK)
		b.cyl(Vector3(0, 0.002, 0.0), 0.012, 0.03, STEEL, 0.0, 8)
	elif frame == 1:                                                                                                # a long slide with a mounted red dot and a protruding barrel
		b.cyl(Vector3(0, 0.002, -0.01), 0.011, 0.05, STEEL, 0.0, 8)
		_bx(b, 0, 0.04, 0.01 + L * 0.7, 0.024, 0.026, 0.05, DARK)
		_bx(b, 0, 0.042, 0.01 + L * 0.7 - 0.027, 0.014, 0.014, 0.004, glow, 1.0)
	else:                                                                                                           # a boxy modern frame with a rail under the barrel
		b.cyl(Vector3(0, 0.0, 0.0), 0.014, 0.03, STEEL, 0.0, 8)
		_bx(b, 0, -0.03, 0.07, 0.026, 0.016, 0.1, STEEL)
		_bx(b, 0, 0.032, 0.015, 0.008, 0.016, 0.012, STEEL)
	_bx(b, 0, -0.038, 0.1 + 0.05 * (lf - 1.0) + 0.04, 0.032, 0.03, 0.15 * lf, POLY)
	_bx(b, 0, -0.085, 0.12 * lf + 0.07, 0.034, 0.105, 0.042, DARK, 0.0, -0.28)
	_bx(b, 0, -0.075, 0.075 * lf + 0.05, 0.012, 0.03, 0.05, POLY)
	_bx(b, 0.0195, 0.0, 0.01 + L * 0.5, 0.004, 0.018, L - 0.06, glow, 1.0)
	_bx(b, -0.0195, 0.0, 0.01 + L * 0.5, 0.004, 0.018, L - 0.06, glow, 1.0)
	if mag > 14:                                                                                                    # an extended magazine
		_bx(b, 0, -0.13, 0.12 * lf + 0.095, 0.03, 0.06 + 0.002 * float(mini(mag, 40)), 0.05, DARK, 0.0, -0.28)
	if bool(d.get("twin", false)):                                                                                  # two guns in one: a second slide
		_bx(b, 0.05, 0.0, 0.01 + L * 0.5, sw, 0.05, L, bodyc)
		_bx(b, 0.05, -0.038, 0.14, 0.032, 0.03, 0.15 * lf, POLY)
		_bx(b, 0.05, -0.085, 0.12 * lf + 0.07, 0.034, 0.105, 0.042, DARK, 0.0, -0.28)
	if int(d.get("pellets", 1)) > 1:
		b.cyl(Vector3(0, 0.002, 0.012), 0.02, 0.026, DARK, 0.0, 8)
	_marks(b, _with_id(d), glow, 0.14 * lf, 0.002, 0.012)
	if float(d.get("interval", 0.2)) > 0.8:                                                                         # a flare pistol: a fat open muzzle
		b.tube(Vector3(0, 0.0, 0.0), 0.028, 0.02, 0.04, STEEL, 0.0, 10)


static func _bow(b: WeaponModels._Builder, id: StringName, d: Dictionary, glow: Color) -> void:
	var seed_ := int(d.get("model_seed", 1))
	var fam_cross := int(d.get("mag", 1)) > 1 or float(d.get("interval", 1.0)) < 0.7 or id == &"bw_heavybolt" or id == &"bw_repeater"
	var big := float(d["damage"]) > 100.0
	var wood := Color(0.34, 0.24, 0.14)
	_cur_id = id
	if fam_cross:
		var span := 0.4 + (0.1 if big else 0.0) + (0.06 if seed_ % 2 == 0 else 0.0)
		_bx(b, 0, 0.0, 0.34, 0.044, 0.05, 0.5, POLY)                                                                # the stock and rail
		_bx(b, 0, 0.032, 0.2, 0.016, 0.014, 0.4, STEEL)
		for sgn in [-1.0, 1.0]:                                                                                     # recurved limbs: three bent segments each
			_prism(b, 0.12, 0.007, 0.014, 0.0, 0.08, 0.007, 0.014, 0.0, DARK, 0.0, 0.0)
			_bx(b, span * 0.22 * sgn, 0.0, 0.1, span * 0.45, 0.014, 0.02, DARK)
			_bx(b, span * 0.5 * sgn, 0.0, 0.06, span * 0.2, 0.014, 0.02, DARK, 0.0, 0.0)
			_bx(b, span * 0.62 * sgn, 0.0, 0.02, span * 0.12, 0.014, 0.02, STEEL)
		_bx(b, 0.0, 0.016, 0.06, span * 1.2, 0.004, 0.004, glow, 1.0)                                               # the string
		_bx(b, 0.0, 0.03, 0.2, 0.008, 0.008, 0.2, glow, 1.0)                                                        # the bolt
		_bx(b, 0, -0.075, 0.46, 0.036, 0.11, 0.05, DARK, 0.0, -0.25)
		if int(d.get("mag", 1)) > 1:
			_bx(b, 0.0, 0.05, 0.32, 0.04, 0.05, 0.14, GUN)                                                          # a bolt magazine on top
		_bx(b, 0.0, -0.01, 0.62, 0.044, 0.07, 0.07, DARK)
	else:
		var h := 0.5 + (0.12 if seed_ % 2 == 1 else 0.0) + (0.1 if id == &"bw_recurve" else 0.0)
		_bx(b, 0, 0.0, 0.3, 0.03, 0.14, 0.05, wood.lerp(DARK, 0.3))                                                 # the riser and grip
		_bx(b, 0, -0.06, 0.34, 0.034, 0.1, 0.034, DARK, 0.0, -0.2)
		for sgn in [-1.0, 1.0]:                                                                                     # the limbs: four segments curving forward and back
			var y0: float = 0.07 * float(sgn)
			_bx(b, 0.0, y0 + 0.07 * sgn, 0.29, 0.016, 0.14, 0.02, wood, 0.0, 0.18 * sgn)
			_bx(b, 0.0, y0 + 0.19 * sgn, 0.24, 0.014, 0.12, 0.018, wood.lerp(STEEL, 0.4), 0.0, 0.4 * sgn)
			_bx(b, 0.0, y0 + 0.29 * sgn, 0.18, 0.012, 0.1, 0.016, STEEL, 0.0, 0.7 * sgn)
		_bx(b, 0.0, 0.0, 0.14, 0.004, h * 0.9, 0.004, glow, 1.0)                                                    # the string
		_bx(b, 0.0, 0.0, 0.1, 0.008, 0.008, 0.36, glow, 1.0)                                                        # the arrow
		_bx(b, 0.0, 0.0, 0.0, 0.016, 0.016, 0.02, STEEL)
	_marks(b, _with_id(d), glow, 0.2, 0.0, 0.01)


static func _sprayer(b: WeaponModels._Builder, id: StringName, d: Dictionary, glow: Color) -> void:
	var seed_ := int(d.get("model_seed", 1))
	_cur_id = id
	var tank := glow.lerp(Color.WHITE, 0.25) if bool(d.get("mist", false)) else Color(1.0, 0.45, 0.15)
	var body := _body(d)
	b.cyl(Vector3(0, 0.0, 0.2), 0.02, 0.4, STEEL, 0.0, 8)                                                           # the nozzle pipe
	b.cyl(Vector3(0, 0.0, 0.01), 0.034, 0.05, DARK, 0.0, 10)
	b.tube(Vector3(0, 0.0, 0.0), 0.038, 0.026, 0.02, glow, 1.0, 10)
	_bx(b, 0, 0.0, 0.5, 0.06, 0.08, 0.26, body)                                                                     # the body
	_bx(b, 0.0, 0.0, 0.3, 0.05, 0.05, 0.14, POLY)
	for i in (2 if seed_ % 2 == 0 else 1):                                                                          # fuel / coolant tanks along the back
		b.cyl(Vector3(0.0, 0.075, 0.5 + 0.1 * float(i)), 0.036, 0.24, POLY, 0.0, 10)
		_bx(b, 0.0, 0.075, 0.5 + 0.1 * float(i), 0.074, 0.01, 0.12, tank, 0.8)
	_bx(b, 0, -0.085, 0.6, 0.036, 0.1, 0.05, DARK, 0.0, -0.25)
	_bx(b, 0, -0.04, 0.4, 0.03, 0.05, 0.05, DARK)
	_prism(b, 0.64, 0.025, 0.04, 0.0, 0.92, 0.022, 0.058, -0.01, POLY)
	_bx(b, 0.0, 0.03, 0.05, 0.016, 0.02, 0.02, tank, 1.0)                                                           # the pilot light on the nozzle
	_marks(b, _with_id(d), glow, 0.4, 0.0, 0.02)


static func _exotic(b: WeaponModels._Builder, id: StringName, d: Dictionary, glow: Color) -> void:
	_cur_id = id
	_bx(b, 0, 0.0, 0.5, 0.07, 0.085, 0.3, GUN)                                                                      # a body for all of them
	_bx(b, 0, -0.095, 0.58, 0.036, 0.1, 0.05, DARK, 0.0, -0.25)
	_bx(b, 0.0, -0.01, 0.74, 0.05, 0.1, 0.12, POLY)
	_bx(b, 0.0, -0.06, 0.4, 0.034, 0.05, 0.06, DARK)
	b.cyl(Vector3(0, 0.0, 0.25), 0.024, 0.34, STEEL, 0.0, 8)                                                        # the barrel that joins the head to the body
	match id:
		&"x_grav":                                                                                                  # a funnel with a floating core
			b.tube(Vector3(0, 0.0, 0.14), 0.08, 0.05, 0.12, STEEL, 0.0, 12)
			b.tube(Vector3(0, 0.0, 0.05), 0.095, 0.07, 0.04, glow, 1.0, 12)
			b.cyl(Vector3(0, 0.0, 0.14), 0.026, 0.05, glow, 1.0, 10)
			for sgn in [-1.0, 1.0]:
				_bx(b, 0.0, 0.07 * sgn, 0.26, 0.012, 0.05, 0.14, STEEL)
		&"x_frost":                                                                                                  # a long nozzle between two coolant tanks
			b.cyl(Vector3(0, 0.0, 0.24), 0.026, 0.48, STEEL, 0.0, 8)
			b.tube(Vector3(0, 0.0, 0.02), 0.04, 0.026, 0.04, ICE, 1.0, 10)
			for sgn in [-1.0, 1.0]:
				b.cyl(Vector3(0.062 * sgn, 0.0, 0.44), 0.034, 0.3, POLY, 0.0, 10)
				_bx(b, 0.062 * sgn, 0.0, 0.44, 0.07, 0.01, 0.2, ICE, 0.8)
		&"x_tesla":                                                                                                  # a stack of coils
			b.cyl(Vector3(0, 0.0, 0.2), 0.02, 0.4, STEEL, 0.0, 8)
			for i in 5:
				b.tube(Vector3(0, 0.0, 0.04 + 0.07 * float(i)), 0.06 - 0.005 * float(i), 0.03, 0.03, STEEL, 0.0, 12)
				b.tube(Vector3(0, 0.0, 0.04 + 0.07 * float(i)), 0.05 - 0.005 * float(i), 0.04, 0.012, glow, 1.0, 12)
			b.cyl(Vector3(0, 0.0, -0.01), 0.018, 0.04, glow, 1.0, 8)
		&"x_sonic":                                                                                                  # a horn
			for i in 4:
				b.tube(Vector3(0, 0.0, 0.03 + 0.07 * float(i)), 0.09 - 0.016 * float(i), 0.06 - 0.014 * float(i), 0.06, STEEL if i % 2 == 0 else DARK, 0.0, 12)
			b.tube(Vector3(0, 0.0, 0.0), 0.1, 0.092, 0.012, glow, 1.0, 12)
		&"x_repulse":                                                                                                # a wide dish
			b.tube(Vector3(0, 0.0, 0.06), 0.13, 0.05, 0.05, STEEL, 0.0, 14)
			b.tube(Vector3(0, 0.0, 0.0), 0.13, 0.115, 0.014, glow, 1.0, 14)
			b.cyl(Vector3(0, 0.0, 0.16), 0.03, 0.2, DARK, 0.0, 8)
		_:                                                                                                           # PRISM SPLITTER: three lenses behind a prism
			for i in 3:
				var a := TAU * float(i) / 3.0
				b.cyl(Vector3(cos(a) * 0.03, 0.004 + sin(a) * 0.03, 0.12), 0.012, 0.24, STEEL, 0.0, 8)
				b.cyl(Vector3(cos(a) * 0.03, 0.004 + sin(a) * 0.03, 0.0), 0.016, 0.012, glow, 1.0, 8)
			b.cyl(Vector3(0, 0.0, 0.3), 0.034, 0.1, DARK, 0.0, 6)
	_bx(b, 0.0, 0.058, 0.5, 0.024, 0.016, 0.3, STEEL)
	_bx(b, 0.0, 0.0, 0.5, 0.074, 0.01, 0.2, glow, 0.8)


static func _blade(b: WeaponModels._Builder, z_tip: float, z_base: float, w: float, thick: float, col: Color, g := 0.0, curve := 0.0) -> void:
	## a tapered blade from the tip (z_tip) to the base (z_base): two frustums (the cutting edge tapers to a point), `curve` bends it up
	var mid := lerpf(z_tip, z_base, 0.28)
	_prism(b, z_tip, 0.0015, 0.004, curve * 0.1, mid, thick, w * 0.95, curve * 0.02, col, g)
	_prism(b, mid, thick, w * 0.95, curve * 0.02, z_base, thick, w, 0.0, col, g)


static func _melee(b: WeaponModels._Builder, id: StringName, d: Dictionary, glow: Color) -> void:
	var mi: Array = WeaponDefsV3.MELEE.get(id, [0.9, false])
	var L: float = mi[0]
	var blade := Color(0.78, 0.82, 0.9)
	var wood := Color(0.34, 0.24, 0.14)
	var seed_ := int(d.get("model_seed", 1))
	_cur_id = id
	match id:
		&"m_dagger", &"m_hook":
			_blade(b, 0.0, L * 0.66, 0.02, 0.005, blade)
			_bx(b, 0, 0.0, L * 0.7, 0.056, 0.022, 0.012, DARK)
			_bx(b, 0, 0.0, L - 0.07, 0.024, 0.026, 0.12, DARK)
			_bx(b, 0.0, 0.0, L * 0.4, 0.004, 0.012, L * 0.4, glow, 1.0)
			if id == &"m_hook":
				_prism(b, 0.0, 0.003, 0.004, -0.02, 0.07, 0.005, 0.016, -0.045, blade)
		&"m_machete":
			for i in 4:                                                                                             # a long blade with a slight curve and a wide belly
				var z0 := 0.0 + 0.12 * float(i)
				_prism(b, z0, 0.004, 0.012 + 0.012 * float(i), 0.012 * float(i) * 0.4, z0 + 0.12, 0.004, 0.012 + 0.012 * float(i + 1), 0.012 * float(i + 1) * 0.4, blade)
			_bx(b, 0, 0.0, 0.56, 0.05, 0.016, 0.012, STEEL)
			_bx(b, 0, 0.0, L - 0.05, 0.026, 0.03, 0.14, DARK)
			_bx(b, 0.0, 0.0, 0.3, 0.003, 0.012, 0.4, glow, 0.5)
		&"m_cutlass", &"m_phaseblade", &"m_arcsabre", &"q_blinkblade":
			var hl := 0.2
			var wd := 0.026 if id != &"m_cutlass" else 0.034
			_blade(b, 0.0, L - hl, wd, 0.006, glow, 1.0, 1.0 if id == &"m_cutlass" else 0.0)
			if id != &"m_cutlass":
				_bx(b, 0, 0.0, (L - hl) * 0.5, 0.012, wd * 1.8, L - hl, glow, 0.4)
			_bx(b, 0, 0.0, L - hl, 0.07, 0.02, 0.016, STEEL)
			_bx(b, 0, 0.0, L - hl * 0.5, 0.028, 0.03, hl, DARK)
			if id == &"m_phaseblade" or id == &"q_blinkblade":
				b.tube(Vector3(0, 0.0, L - hl - 0.05), 0.04, 0.03, 0.02, glow, 1.0, 10)
				_bx(b, 0.0, 0.0, L - hl - 0.12, 0.05, 0.004, 0.02, glow, 1.0)
			if id == &"m_arcsabre":
				for i in 4:
					_bx(b, 0.0, 0.018 * (1.0 if i % 2 == 0 else -1.0), 0.1 + 0.16 * float(i), 0.008, 0.02, 0.05, glow, 1.0, 0.4)
		&"m_twinkat":
			for sgn in [-1.0, 1.0]:
				_blade(b, 0.0, L - 0.2, 0.014, 0.004, blade)
				_bx(b, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, blade)
				_bx(b, 0.03 * sgn, 0.0, L - 0.1, 0.022, 0.024, 0.16, DARK)
				_bx(b, 0.03 * sgn, 0.0, L - 0.2, 0.05, 0.016, 0.01, BRASS)
				_prism(b, 0.0, 0.0015 + 0.03 * sgn, 0.004, 0.0, L - 0.2, 0.004 + 0.03 * sgn, 0.014, 0.0, blade, 0.0, 0.0)
		&"m_hatchet", &"m_axe", &"m_greataxe":
			var hw := 0.1 if id == &"m_hatchet" else (0.13 if id == &"m_axe" else 0.2)
			_bx(b, 0, 0.0, L * 0.5 + 0.04, 0.03, 0.03, L - 0.04, wood)
			_bx(b, 0.0, 0.0, 0.07, 0.014, hw * 0.55, 0.1, STEEL)
			_prism(b, 0.0, 0.003, hw * 0.5, 0.0, 0.08, 0.012, hw * 0.28, 0.0, blade)                              # the cutting edge flares from the eye of the axe
			if id == &"m_greataxe":
				_prism(b, 0.14, 0.003, hw * 0.4, 0.0, 0.08, 0.012, hw * 0.22, 0.0, blade)
				_bx(b, 0.0, 0.0, 0.12, 0.02, 0.02, 0.05, glow, 1.0)
		&"m_mallet", &"m_sledge":
			var hs := 0.11 if id == &"m_mallet" else 0.15
			_bx(b, 0, 0.0, L * 0.5 + 0.06, 0.032, 0.032, L - 0.06, wood)
			_bx(b, 0.0, 0.0, 0.08, hs * 0.9, hs, hs * 1.6, STEEL)
			_bx(b, 0.0, 0.0, 0.0, hs * 0.95, hs * 1.05, 0.02, glow, 1.0)
			_bx(b, 0.0, 0.0, 0.08, hs * 0.96, hs * 0.2, hs * 1.0, DARK)
		&"m_crowbar":
			b.cyl(Vector3(0, 0.0, L * 0.5), 0.014, L, STEEL, 0.0, 8)
			_prism(b, 0.0, 0.007, 0.004, 0.0, 0.06, 0.007, 0.03, 0.02, STEEL)
			_bx(b, 0.0, 0.03, L - 0.02, 0.016, 0.05, 0.03, STEEL, 0.0, -0.5)
			_bx(b, 0.0, 0.0, L - 0.12, 0.022, 0.022, 0.14, glow, 0.6)
		&"m_spear":
			b.cyl(Vector3(0, 0.0, L * 0.5 + 0.1), 0.014, L - 0.2, wood, 0.0, 8)
			_blade(b, 0.0, 0.24, 0.032, 0.006, blade)
			_bx(b, 0.0, 0.0, 0.25, 0.04, 0.04, 0.03, BRASS)
			_bx(b, 0.0, 0.0, L - 0.02, 0.026, 0.026, 0.05, STEEL)
		&"m_staff":
			b.cyl(Vector3(0, 0.0, L * 0.5), 0.016, L, wood, 0.0, 8)
			for z in [0.02, L - 0.02]:
				b.tube(Vector3(0, 0.0, z), 0.03, 0.018, 0.05, STEEL, 0.0, 10)
				_bx(b, 0.0, 0.0, z, 0.03, 0.03, 0.02, glow, 1.0)
			_bx(b, 0.0, 0.0, L * 0.5, 0.024, 0.024, 0.18, POLY)
		&"m_chainblade":
			_bx(b, 0, 0.0, L * 0.4, 0.024, 0.07, L * 0.8, STEEL)
			for i in 12:
				_bx(b, 0.0, 0.04 * (1.0 if i % 2 == 0 else -1.0), 0.04 + 0.06 * float(i), 0.012, 0.016, 0.03, blade)
			_bx(b, 0, -0.01, L - 0.08, 0.06, 0.1, 0.16, GUN)
			_bx(b, 0.0, 0.06, L - 0.08, 0.02, 0.016, 0.1, glow, 1.0)
		&"m_baton":
			b.cyl(Vector3(0, 0.0, L * 0.5), 0.02, L, DARK, 0.0, 8)
			b.cyl(Vector3(0, 0.0, 0.05), 0.026, 0.1, glow, 1.0, 8)
			_bx(b, 0.0, 0.0, L - 0.08, 0.03, 0.03, 0.12, POLY)
			for i in 3:
				_bx(b, 0.0, 0.0, 0.2 + 0.07 * float(i), 0.034, 0.034, 0.012, glow, 0.8)
		&"m_gauntlet":
			_bx(b, 0.0, 0.0, 0.12, 0.09, 0.08, 0.14, STEEL)                                                         # the fist
			for i in 4:
				_bx(b, -0.03 + 0.02 * float(i), 0.0, 0.03, 0.018, 0.022, 0.05, DARK)
			_bx(b, 0.0, 0.042, 0.12, 0.08, 0.008, 0.1, glow, 1.0)
			_bx(b, 0.0, 0.0, 0.26, 0.07, 0.065, 0.1, DARK)                                                          # the forearm
		&"m_chainwhip":
			_bx(b, 0.0, 0.0, L - 0.08, 0.034, 0.034, 0.16, DARK)
			for i in 9:                                                                                             # links that overlap, so the chain is one piece
				_bx(b, 0.0, 0.025 * sin(float(i) * 0.9), 0.04 + 0.04 * float(i), 0.016, 0.022, 0.05, STEEL if i % 2 == 0 else DARK)
			_bx(b, 0.0, 0.0, 0.0, 0.034, 0.034, 0.04, glow, 1.0)
		&"m_shield":
			_prism(b, 0.08, 0.17, 0.25, 0.0, 0.12, 0.17, 0.25, 0.0, STEEL)
			_prism(b, 0.12, 0.14, 0.21, 0.0, 0.13, 0.14, 0.21, 0.0, DARK)
			_bx(b, 0.0, 0.0, 0.07, 0.04, 0.34, 0.006, glow, 1.0)
			_bx(b, 0.0, 0.0, 0.2, 0.03, 0.04, 0.16, DARK)
			_bx(b, 0.0, 0.07, 0.26, 0.026, 0.026, 0.12, DARK)
		&"m_tonfa":
			_bx(b, 0.0, 0.0, 0.17, 0.03, 0.03, 0.34, DARK)
			_bx(b, 0.0, 0.0, 0.17, 0.034, 0.008, 0.2, glow, 1.0)
			_bx(b, 0.0, -0.035, L - 0.08, 0.03, 0.08, 0.03, DARK)
			_bx(b, 0.0, 0.0, L - 0.1, 0.03, 0.04, 0.1, DARK)
		&"m_scythe":
			b.cyl(Vector3(0, 0.0, L * 0.5 + 0.1), 0.016, L - 0.1, wood, 0.0, 8)
			for i in 6:                                                                                             # the blade sweeps out of the top of the shaft
				var t := float(i) / 5.0
				_prism(b, 0.12 - 0.07 * t * t, 0.003, 0.055, 0.1 + 0.2 * t, 0.12 - 0.07 * t * t + 0.07, 0.005, 0.06, 0.1 + 0.2 * (t + 0.15), blade)
			_bx(b, 0.0, 0.1, 0.12, 0.004, 0.28, 0.01, glow, 1.0)
			_bx(b, 0.0, 0.0, 0.14, 0.03, 0.03, 0.03, STEEL)
		_:
			_bx(b, 0, 0.0, L * 0.5, 0.02, 0.04, L, blade)
			_bx(b, 0, 0.0, L - 0.08, 0.03, 0.03, 0.16, DARK)
	if seed_ % 2 == 0 and L > 0.5:
		_bx(b, 0.0, 0.0, L - 0.02, 0.026, 0.026, 0.02, STEEL)
