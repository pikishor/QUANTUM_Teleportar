class_name WeaponModels
extends RefCounted
## Weapon silhouettes. The hero's carbine is baked into his mesh; every OTHER class used to be a thin glowing strip, so a scatter gun and a lance looked the same from the shoulder camera.
## Each class now has its own readable shape, built once from boxes and cylinders into ONE ArrayMesh (vertex colours: rgb the part, alpha the glow), drawn as one extra draw call on the hand
## mount (PlayerBody.set_weapon_look). The mesh origin is the MUZZLE and the weapon extends toward +Z (behind the muzzle): barrel forward is -Z, like the muzzle node.
## Silhouette rules: LONG vs STUBBY, THIN vs FAT, one distinguishing feature per class (pump, fins, coils, drum, barrel cluster, prongs, tube, blade), a glow trim in the weapon's colour.

const GUN := Color(0.16, 0.17, 0.2)
const DARK := Color(0.07, 0.075, 0.09)
const STEEL := Color(0.34, 0.36, 0.4)

static var _cache := {}
static var _material: ShaderMaterial


## The silhouette mesh of weapon `id`, or null for the carbine (its model is part of the hero).
static func mesh(id: StringName) -> ArrayMesh:
	if id == &"carbine" or not WeaponDefs.DEFS.has(id):
		return null
	if _cache.has(id):
		return _cache[id]
	var glow: Color = WeaponDefs.def(id)["look"]
	var b := _Builder.new()
	match id:
		&"scatter":                                                   # a fat short shotgun: a wide flared muzzle, a pump, a big stock block
			b.box(Vector3(0, 0, 0.3), Vector3(0.12, 0.12, 0.6), GUN)
			b.box(Vector3(0, -0.095, 0.34), Vector3(0.09, 0.07, 0.3), DARK)                  # the pump
			b.box(Vector3(0, 0.0, 0.02), Vector3(0.19, 0.19, 0.07), glow, 1.0)               # the flared muzzle ring
			b.box(Vector3(0, -0.02, 0.78), Vector3(0.1, 0.17, 0.3), STEEL)                   # stock
			b.box(Vector3(0, 0.075, 0.3), Vector3(0.03, 0.02, 0.5), glow, 1.0)
		&"lance":                                                     # a long thin rail with two fins and a glowing core
			b.box(Vector3(0, 0, 0.62), Vector3(0.05, 0.05, 1.25), GUN)
			b.box(Vector3(0, 0, 0.25), Vector3(0.26, 0.018, 0.2), STEEL)
			b.box(Vector3(0, 0, 0.7), Vector3(0.018, 0.22, 0.2), STEEL)
			b.box(Vector3(0, 0.0, 0.5), Vector3(0.025, 0.025, 1.0), glow, 1.0)
			b.box(Vector3(0, -0.06, 0.95), Vector3(0.08, 0.14, 0.34), DARK)
		&"grenade", &"gravity":                                       # a fat launcher tube with a drum
			b.cyl(Vector3(0, 0, 0.35), 0.085 if id == &"grenade" else 0.11, 0.7, GUN)
			b.cyl(Vector3(0, 0, 0.03), 0.105 if id == &"grenade" else 0.135, 0.06, glow, 1.0)
			b.box(Vector3(0, -0.12, 0.55), Vector3(0.1, 0.14, 0.26), DARK)
			b.box(Vector3(0, 0.1, 0.4), Vector3(0.05, 0.06, 0.2), STEEL)
		&"burst", &"akimbo", &"revolver":                              # a heavy pistol: a tall slide, a glowing rail, a big grip
			var big := 1.25 if id == &"revolver" else 1.0
			b.box(Vector3(0, 0.0, 0.2), Vector3(0.075, 0.1, 0.4) * big, GUN)
			b.box(Vector3(0, 0.0, 0.02), Vector3(0.1, 0.12, 0.05) * big, glow, 1.0)
			b.box(Vector3(0, -0.14, 0.34), Vector3(0.06, 0.2, 0.09), DARK)
			b.box(Vector3(0, 0.062, 0.2), Vector3(0.02, 0.015, 0.34), glow, 1.0)
			if id == &"revolver":
				b.cyl(Vector3(0, 0, 0.3), 0.075, 0.16, STEEL)                               # the cylinder
		&"rail":                                                      # long with coil rings all along
			b.box(Vector3(0, 0, 0.55), Vector3(0.07, 0.07, 1.1), GUN)
			for k in 5:
				b.box(Vector3(0, 0, 0.12 + 0.2 * float(k)), Vector3(0.17, 0.17, 0.05), glow, 1.0)
			b.box(Vector3(0, -0.07, 0.95), Vector3(0.09, 0.14, 0.34), DARK)
		&"flux":                                                      # a boxy SMG with a glowing block and a long curved magazine
			b.box(Vector3(0, 0, 0.26), Vector3(0.11, 0.15, 0.52), GUN)
			b.box(Vector3(0, -0.2, 0.34), Vector3(0.07, 0.3, 0.1), DARK)
			b.box(Vector3(0, 0.0, 0.03), Vector3(0.13, 0.17, 0.06), glow, 1.0)
			b.box(Vector3(0.062, 0.0, 0.3), Vector3(0.015, 0.08, 0.32), glow, 1.0)
			b.box(Vector3(-0.062, 0.0, 0.3), Vector3(0.015, 0.08, 0.32), glow, 1.0)
		&"minigun":                                                   # a barrel cluster and a drum
			for k in 6:
				var a := TAU * float(k) / 6.0
				b.cyl(Vector3(cos(a) * 0.07, sin(a) * 0.07, 0.32), 0.026, 0.64, STEEL)
			b.cyl(Vector3(0, 0, 0.03), 0.13, 0.05, glow, 1.0)
			b.cyl(Vector3(0, 0, 0.5), 0.12, 0.16, DARK)
			b.box(Vector3(0, -0.2, 0.62), Vector3(0.24, 0.24, 0.28), GUN)
		&"arc":                                                       # two prongs that arc between their tips
			b.box(Vector3(0.07, 0.0, 0.25), Vector3(0.035, 0.035, 0.5), STEEL)
			b.box(Vector3(-0.07, 0.0, 0.25), Vector3(0.035, 0.035, 0.5), STEEL)
			b.box(Vector3(0.07, 0.0, 0.02), Vector3(0.06, 0.06, 0.06), glow, 1.0)
			b.box(Vector3(-0.07, 0.0, 0.02), Vector3(0.06, 0.06, 0.06), glow, 1.0)
			b.box(Vector3(0, 0, 0.55), Vector3(0.14, 0.12, 0.32), GUN)
			b.box(Vector3(0, 0.0, 0.3), Vector3(0.05, 0.05, 0.12), glow, 1.0)
		&"whip":                                                      # a handle with a glowing coil
			b.cyl(Vector3(0, 0, 0.3), 0.04, 0.5, GUN)
			b.cyl(Vector3(0, 0, 0.05), 0.075, 0.1, glow, 1.0)
			b.cyl(Vector3(0, 0, 0.4), 0.07, 0.12, glow, 1.0)
		&"blade":                                                     # a glowing blade, a guard, a handle
			b.box(Vector3(0, 0, -0.15), Vector3(0.035, 0.13, 0.92), glow, 1.0)
			b.box(Vector3(0, 0, 0.36), Vector3(0.2, 0.05, 0.05), STEEL)
			b.box(Vector3(0, 0, 0.6), Vector3(0.055, 0.055, 0.5), GUN)
		_:
			b.box(Vector3(0, 0, 0.3), Vector3(0.1, 0.1, 0.6), GUN)
			b.box(Vector3(0, 0, 0.3), Vector3(0.03, 0.03, 0.5), glow, 1.0)
	var m := b.build()
	_cache[id] = m
	return m


## The shared material (one for every weapon): vertex colour albedo, the alpha channel glows; `glow` is pulsed by the shots.
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://assets/shaders/weapon_look.gdshader")
	return _material


## Length of the weapon behind the muzzle (metres) for the tests and the hand mount.
static func length_of(id: StringName) -> float:
	var m := mesh(id)
	return m.get_aabb().end.z if m != null else 0.0


class _Builder extends RefCounted:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	## A box: `center`, full `size`, colour; `glow` 0..1 goes into the colour's alpha.
	func box(center: Vector3, size: Vector3, color: Color, glow := 0.0) -> void:
		var h := size * 0.5
		var c := Color(color.r, color.g, color.b, glow)
		for axis in 3:
			for sgn in [-1.0, 1.0]:
				var n := Vector3.ZERO
				n[axis] = sgn
				var u := Vector3.ZERO
				u[(axis + 1) % 3] = 1.0
				var v := n.cross(u)
				var base := verts.size()
				for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					verts.append(center + n * h[axis] + u * (q.x * h[(axis + 1) % 3]) + v * (q.y * h[(axis + 2) % 3]))
					norms.append(n)
					cols.append(c)
				idx.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))      # u x v = n: counter-clockwise from outside, Godot's front face is clockwise

	## A cylinder along Z (length `len`), 8 sides, centred at `center`.
	func cyl(center: Vector3, radius: float, len: float, color: Color, glow := 0.0) -> void:
		var c := Color(color.r, color.g, color.b, glow)
		var sides := 8
		var base := verts.size()
		for k in sides:
			var a := TAU * float(k) / float(sides)
			var n := Vector3(cos(a), sin(a), 0.0)
			for zz in [-0.5, 0.5]:
				verts.append(center + Vector3(n.x * radius, n.y * radius, zz * len))
				norms.append(n)
				cols.append(c)
		for k in sides:
			var i0 := base + k * 2
			var i1 := base + ((k + 1) % sides) * 2
			idx.append_array(PackedInt32Array([i0, i0 + 1, i1, i1, i0 + 1, i1 + 1]))
		for zz in [-0.5, 0.5]:                                       # the two caps
			var cb := verts.size()
			verts.append(center + Vector3(0.0, 0.0, zz * len))
			norms.append(Vector3(0.0, 0.0, signf(zz)))
			cols.append(c)
			for k in sides:
				var a := TAU * float(k) / float(sides)
				verts.append(center + Vector3(cos(a) * radius, sin(a) * radius, zz * len))
				norms.append(Vector3(0.0, 0.0, signf(zz)))
				cols.append(c)
			for k in sides:
				var a0 := cb + 1 + k
				var a1 := cb + 1 + (k + 1) % sides
				if zz > 0.0:
					idx.append_array(PackedInt32Array([cb, a1, a0]))
				else:
					idx.append_array(PackedInt32Array([cb, a0, a1]))

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
