class_name AlienSiteKit
extends RefCounted
## The meshes of the alien sites (wave 107b): camps, hive nests, wrecks and boss lairs, each ONE merged ArrayMesh (one draw call, 1.5 to 4 k triangles) in the site's local frame (x right, z back,
## y up from the site's ground height; the node is placed at the site and turned by its yaw). Vertex colour = paint, alpha = the glow mask of alien.gdshader. Every piece is set on the terrain
## under it (`_gh`), the camps and the nest rest on a platform with a skirt that reaches down to the lowest ground, so a site on a mountain slope still stands.
##   build(site) -> {mesh, boxes: [[centre, size], ...] (collision), tris}   (an empty dictionary for a site without a mesh)

const ROCK := Color(0.17, 0.16, 0.2)
const CHITIN := Color(0.27, 0.2, 0.34)
const CHITIN_LIGHT := Color(0.38, 0.3, 0.45)
const BONE := Color(0.78, 0.72, 0.6)
const FLESH := Color(0.44, 0.13, 0.2)
const TEAL := Color(0.1, 0.32, 0.34)
const METAL := Color(0.22, 0.24, 0.28)


static func build(s: Dictionary) -> Dictionary:
	var am := AlienMesh.new()
	var boxes: Array = []
	var kind: StringName = s["kind"]
	var gl := _glow_of(s)
	match kind:
		&"camp": _camp(am, boxes, s, gl)
		&"nest": _nest(am, boxes, s, gl)
		&"crash": _wreck(am, boxes, s, gl)
		&"lair": _lair(am, boxes, s, gl)
	if am.tris() == 0:
		return {}
	return {"mesh": am.commit(), "boxes": boxes, "tris": am.tris()}


static func _glow_of(s: Dictionary) -> Color:
	match StringName(s["kind"]):
		&"camp": return Color(0.55, 1.0, 0.45)
		&"nest": return Color(1.0, 0.35, 0.6)
		&"crash": return Color(0.35, 0.95, 1.0)
	match StringName(s.get("boss", &"")):
		&"broodmother": return Color(0.8, 0.45, 1.0)
		&"storm_drake": return Color(0.5, 0.85, 1.0)
		&"sand_leviathan": return Color(1.0, 0.5, 0.15)
	return Color(0.55, 1.0, 0.6)


## Ground height (relative to the site's pad height) under the local point (x, z).
static func _gh(s: Dictionary, x: float, z: float) -> float:
	var w := Basis(Vector3.UP, float(s["yaw"])) * Vector3(x, 0.0, z)
	var p: Vector3 = s["pos"]
	return TerrainHeight.height_at(p.x + w.x, p.z + w.z) - p.y


static func _gc(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## The platform: a deck at the highest ground of its footprint with a skirt to the lowest, rock-coloured below and glowing seams on the deck edge.
static func _platform(am: AlienMesh, s: Dictionary, r: float, gl: Color) -> float:
	var hi := -1.0e9
	var lo := 1.0e9
	for k in 12:
		var a := TAU * float(k) / 12.0
		for rr in [0.0, r * 0.6, r]:
			var g := _gh(s, cos(a) * rr, sin(a) * rr)
			hi = maxf(hi, g)
			lo = minf(lo, g)
	var top := hi + 0.35
	var path := [Vector3(0.0, top, 0.0), Vector3(0.0, top - 0.5, 0.0), Vector3(0.0, lo - 3.0, 0.0)]
	am.tube(path, [r, r * 1.02, r * 1.2], [Color(0.2, 0.19, 0.24, 0.0), _gc(ROCK, 0.5), _gc(ROCK, 0.0)], 14, true, false)
	am.disc(Vector3(0.0, top + 0.02, 0.0), r * 0.55, Color(0.24, 0.22, 0.29, 0.0), 14, r * 0.47)         # an inlaid ring on the deck
	for k in 14:
		var a2 := TAU * float(k) / 14.0
		am.box(Vector3(cos(a2) * r * 0.995, top, sin(a2) * r * 0.995), Vector3(1.3, 0.34, 0.6), _gc(gl, 0.8), Basis(Vector3.UP, -a2))
	return top


static func _spire(am: AlienMesh, base: Vector3, h: float, r: float, col: Color, gl: Color, twist := 0.5) -> void:
	var path := []
	var radii := []
	var cols := []
	var n := 12
	for k in n + 1:
		var t := float(k) / float(n)
		path.append(base + Vector3(sin(t * 5.0) * twist * (1.0 - t), t * h, cos(t * 5.0) * twist * (1.0 - t)))
		radii.append(r * (1.0 - 0.9 * t) * (1.0 + 0.15 * sin(t * 18.0)))
		cols.append(_gc(col.lerp(CHITIN_LIGHT, t * 0.5), 0.9 if k % 4 == 3 else 0.0))
	am.tube(path, radii, cols, 7, true, true, 0.8)
	am.ellipsoid(base + Vector3(0.0, h + 0.5, 0.0), Vector3(r * 0.5, r * 0.8, r * 0.5), _gc(gl, 0.99), 4, 8)
	for k in 5:                                                                    # buttress fins at the foot
		var a := TAU * float(k) / 5.0
		am.cone(base + Vector3(cos(a) * r * 0.8, 0.0, sin(a) * r * 0.8), base + Vector3(cos(a) * r * 0.3, h * 0.35, sin(a) * r * 0.3), r * 0.35, col, 4, _gc(gl, 0.5))


## A dome pod: a half-buried ellipsoid with ribs, a dark mouth on the front (-Z after `rot`) and a glowing bulb above the door.
static func _pod(am: AlienMesh, c: Vector3, r: float, yaw: float, col: Color, gl: Color) -> void:
	var rot := Basis(Vector3.UP, yaw)
	am.ellipsoid(c + Vector3(0.0, r * 0.2, 0.0), Vector3(r, r * 0.8, r), col, 5, 10, rot, _gc(col.lerp(CHITIN_LIGHT, 0.4), 0.0))
	am.ellipsoid(c + rot * Vector3(0.0, r * 0.28, -r * 0.82), Vector3(r * 0.34, r * 0.38, r * 0.2), Color(0.02, 0.02, 0.04, 0.0), 3, 6, rot)
	am.ellipsoid(c + rot * Vector3(0.0, r * 0.82, -r * 0.5), Vector3(r * 0.13, r * 0.13, r * 0.13), _gc(gl, 0.99), 3, 6)
	for k in 4:
		var a := yaw + 0.8 + TAU * float(k) / 4.0
		am.cone(c + Vector3(cos(a) * r * 0.78, r * 0.35, sin(a) * r * 0.78), c + Vector3(cos(a) * r * 0.5, r * 1.25, sin(a) * r * 0.5), r * 0.1, BONE, 4, _gc(gl, 0.4))


static func _camp(am: AlienMesh, boxes: Array, s: Dictionary, gl: Color) -> void:
	var r := 19.0
	var top := _platform(am, s, r, gl)
	_spire(am, Vector3(0.0, top, 0.0), 15.0, 2.2, CHITIN, gl, 0.7)
	boxes.append([Vector3(0.0, top + 6.0, 0.0), Vector3(3.2, 12.0, 3.2)])
	var kinds := [[-9.0, 6.0, 3.2], [9.5, 5.0, 3.0], [-6.0, -9.5, 3.4], [7.0, -10.0, 2.8], [0.0, 13.0, 3.0]]
	for i in kinds.size():
		var k: Array = kinds[i]
		var yaw := atan2(float(k[0]), float(k[1])) + PI
		_pod(am, Vector3(float(k[0]), top, float(k[1])), float(k[2]), yaw, CHITIN.lerp(TEAL, 0.25 * float(i % 3)), gl)
		boxes.append([Vector3(float(k[0]), top + 1.4, float(k[1])), Vector3(float(k[2]) * 1.6, 2.8, float(k[2]) * 1.6)])
	# bone fence with a gate toward -Z
	for k in 22:
		var a := TAU * float(k) / 22.0
		if absf(wrapf(a - PI * 1.5, -PI, PI)) < 0.35:
			continue
		var p := Vector3(cos(a) * (r - 0.8), top, sin(a) * (r - 0.8))
		var lean := Vector3(cos(a), 0.0, sin(a)) * 0.9
		am.cone(p, p + Vector3(0.0, 2.8 + 0.7 * float(k % 3), 0.0) + lean, 0.28, BONE, 4, _gc(gl, 0.5))
	# torches at the gate and around
	for a3 in [PI * 1.5 - 0.5, PI * 1.5 + 0.5, 0.3, 2.4]:
		var p2 := Vector3(cos(a3) * (r - 1.6), top, sin(a3) * (r - 1.6))
		am.tube([p2, p2 + Vector3(0.0, 1.2, 0.0), p2 + Vector3(0.0, 2.0, 0.1)], [0.14, 0.1, 0.1], [_gc(BONE, 0.0), _gc(BONE, 0.0), _gc(gl, 0.0)], 5, true, false)
		am.ellipsoid(p2 + Vector3(0.0, 2.3, 0.1), Vector3(0.28, 0.34, 0.28), _gc(gl, 0.99), 3, 6)
	# the cache: a cluster of crystals
	for k in 5:
		var a4 := TAU * float(k) / 5.0
		var b := Vector3(cos(a4) * 0.8 + 3.5, top, sin(a4) * 0.8 - 6.0)
		am.cone(b, b + Vector3(0.0, 1.1 + 0.4 * float(k % 3), 0.0) + Vector3(cos(a4), 0.0, sin(a4)) * 0.3, 0.3, Color(0.35, 0.85, 0.95, 0.9), 5, Color(0.7, 1.0, 1.0, 0.99))


static func _nest(am: AlienMesh, boxes: Array, s: Dictionary, gl: Color) -> void:
	var r := 13.0
	var hi := -1.0e9
	for k in 12:
		var a := TAU * float(k) / 12.0
		hi = maxf(hi, _gh(s, cos(a) * r, sin(a) * r))
	var top := maxf(hi, _gh(s, 0.0, 0.0)) + 0.3
	# the mound: a low dome of flesh and chitin, ridged
	am.ellipsoid(Vector3(0.0, top - 1.0, 0.0), Vector3(r, 3.4, r), FLESH.lerp(CHITIN, 0.35), 6, 16, Basis.IDENTITY, _gc(FLESH, 0.0))
	for k in 10:                                                                   # fleshy ridges radiating out
		var a2 := TAU * float(k) / 10.0 + 0.2
		var p0 := Vector3(cos(a2) * 3.0, top + 0.2, sin(a2) * 3.0)
		var p1 := Vector3(cos(a2) * 7.5, top - 0.2, sin(a2) * 7.5)
		var p2 := Vector3(cos(a2) * 12.5, _gh(s, cos(a2) * 12.5, sin(a2) * 12.5) + 0.1, sin(a2) * 12.5)
		am.tube([p0, p1, p2], [0.55, 0.45, 0.22], [_gc(FLESH, 0.6), _gc(FLESH, 0.3), _gc(gl, 0.7)], 5, false, true, 0.2)
	for k in 22:                                                                   # eggs
		var a3 := TAU * float(k) / 22.0 * 1.0 + float(k) * 0.37
		var rr := 4.5 + float((k * 7) % 9)
		var p := Vector3(cos(a3) * rr, 0.0, sin(a3) * rr)
		var gy := _gh(s, p.x, p.z)
		var e := 0.55 + 0.25 * float(k % 3)
		am.ellipsoid(Vector3(p.x, gy + e * 0.6, p.z), Vector3(e, e * 1.25, e), Color(0.8, 0.7, 0.58, 0.0), 4, 7, Basis.IDENTITY, Color(0.95, 0.55, 0.6, 0.3))
	for k in 6:                                                                    # bone ribs arching over the heart
		var a4 := TAU * float(k) / 6.0
		var path := []
		for j in 7:
			var t := float(j) / 6.0
			var rr2 := lerpf(10.0, 2.5, t)
			path.append(Vector3(cos(a4) * rr2, top + sin(t * PI * 0.5) * 7.5 - 1.0, sin(a4) * rr2))
		am.tube(path, [0.5, 0.42, 0.36, 0.3, 0.25, 0.2, 0.14], [BONE, BONE, BONE, BONE, BONE, _gc(gl, 0.5), _gc(gl, 0.8)], 5, true, true, 0.3)
	boxes.append([Vector3(0.0, top, 0.0), Vector3(4.0, 3.5, 4.0)])


static func _wreck(am: AlienMesh, boxes: Array, s: Dictionary, gl: Color) -> void:
	var base := _gh(s, 0.0, 0.0)
	# a crater scorch and the hull: a cigar lying tilted, broken open on one side
	am.disc(Vector3(0.0, base + 0.06, 0.0), 12.0, Color(0.06, 0.05, 0.06, 0.0), 14)
	var path := []
	var radii := []
	var cols := []
	var n := 12
	for k in n + 1:
		var t := float(k) / float(n)
		path.append(Vector3(lerpf(-9.0, 8.0, t), base + 1.2 + 2.6 * t + 0.6 * sin(t * 3.0), lerpf(1.0, -1.5, t)))
		radii.append(1.0 + 2.2 * sin(t * PI) + 0.3)
		cols.append(_gc(METAL.lerp(CHITIN, 0.25) if k % 2 == 0 else METAL, 0.55 if k == 6 else 0.0))
	am.tube(path, radii, cols, 9, true, true, 1.0)
	for sx in [-1.0, 1.0]:                                                         # swept fins, one snapped
		var root: Vector3 = path[3]
		var tipp := root + Vector3(sx * (5.5 if sx > 0.0 else 2.2), -0.6, 1.8)
		am.cone(root + Vector3(sx * 1.0, 0.0, 0.0), tipp, 1.1, METAL, 4, _gc(gl, 0.7))
	am.ellipsoid(path[7] + Vector3(0.0, 1.5, 0.0), Vector3(1.1, 0.9, 1.4), _gc(gl, 0.99), 4, 8)         # the exposed core
	for k in 6:                                                                    # crystals and debris
		var a := TAU * float(k) / 6.0 + 0.3
		var b := Vector3(cos(a) * 4.5, 0.0, sin(a) * 4.5 + 3.0)
		b.y = _gh(s, b.x, b.z)
		am.cone(b, b + Vector3(0.2, 1.4 + 0.5 * float(k % 3), 0.1), 0.34, Color(0.3, 0.8, 0.95, 0.9), 5, Color(0.7, 1.0, 1.0, 0.99))
	for k in 9:
		var a2 := float(k) * 2.4
		var rr := 6.0 + float(k % 4) * 2.5
		var p := Vector3(cos(a2) * rr, 0.0, sin(a2) * rr)
		p.y = _gh(s, p.x, p.z) + 0.3
		am.box(p, Vector3(1.3 + 0.4 * float(k % 3), 0.5, 0.9), METAL, Basis(Vector3.UP, a2) * Basis(Vector3.RIGHT, 0.3 * float(k % 3)), _gc(gl, 0.0))
	boxes.append([Vector3(-0.5, base + 2.5, -0.2), Vector3(17.0, 4.0, 4.0)])


static func _lair(am: AlienMesh, boxes: Array, s: Dictionary, gl: Color) -> void:
	var boss: StringName = s.get("boss", &"")
	if boss == &"deep_kraken":
		return
	var base := _gh(s, 0.0, 0.0)
	match boss:
		&"broodmother":
			# spore pillars: tall stalks with glowing caps, a ring of them, a carpet of small ones
			for k in 9:
				var a := TAU * float(k) / 9.0 + 0.2
				var rr := 14.0 + float(k % 3) * 3.0
				var p := Vector3(cos(a) * rr, 0.0, sin(a) * rr)
				p.y = _gh(s, p.x, p.z)
				var h := 5.0 + 2.5 * float(k % 4)
				am.tube([p, p + Vector3(0.3, h * 0.5, 0.0), p + Vector3(0.0, h, 0.2)], [0.7, 0.45, 0.4], [CHITIN, CHITIN_LIGHT, _gc(CHITIN_LIGHT, 0.4)], 6, true, false)
				am.ellipsoid(p + Vector3(0.0, h + 0.3, 0.2), Vector3(1.9, 0.9, 1.9), CHITIN.lerp(gl, 0.25), 4, 9, Basis.IDENTITY, _gc(gl, 0.8))
				if k % 2 == 0:
					boxes.append([p + Vector3(0.0, 2.5, 0.0), Vector3(1.4, 5.0, 1.4)])
			for k in 24:
				var a2 := float(k) * 2.39996
				var rr2 := 3.0 + 12.0 * sqrt(float(k) / 24.0)
				var p2 := Vector3(cos(a2) * rr2, 0.0, sin(a2) * rr2)
				p2.y = _gh(s, p2.x, p2.z)
				am.cone(p2, p2 + Vector3(0.0, 0.7 + 0.5 * float(k % 3), 0.0), 0.16, CHITIN_LIGHT, 4, _gc(gl, 0.99))
		&"storm_drake":
			# needle peaks around a bone-white nest
			for k in 7:
				var a3 := TAU * float(k) / 7.0
				var p3 := Vector3(cos(a3) * 15.0, 0.0, sin(a3) * 15.0)
				p3.y = _gh(s, p3.x, p3.z) - 1.0
				am.cone(p3, p3 + Vector3(cos(a3) * -2.0, 15.0 + 5.0 * float(k % 3), sin(a3) * -2.0), 2.2 + float(k % 2), ROCK.lerp(CHITIN, 0.3), 5, _gc(gl, 0.6))
				boxes.append([p3 + Vector3(0.0, 4.0, 0.0), Vector3(3.0, 8.0, 3.0)])
			am.ellipsoid(Vector3(0.0, base + 0.5, 0.0), Vector3(6.5, 1.0, 6.5), BONE.lerp(ROCK, 0.3), 3, 12)
			for k in 12:                                                           # a ring of broken eggshell and a heap of bones on the roost
				var a7 := TAU * float(k) / 12.0 + 0.2
				am.ellipsoid(Vector3(cos(a7) * 4.2, base + 1.0, sin(a7) * 4.2), Vector3(0.9, 0.5, 0.9), BONE, 3, 6, Basis(Vector3.UP, a7), Color(0.9, 0.85, 0.7, 0.0))
				am.cone(Vector3(cos(a7) * 8.0, _gh(s, cos(a7) * 8.0, sin(a7) * 8.0), sin(a7) * 8.0), Vector3(cos(a7) * 7.2, _gh(s, cos(a7) * 8.0, sin(a7) * 8.0) + 3.5 + float(k % 3), sin(a7) * 7.2), 0.45, ROCK.lerp(BONE, 0.3), 5, _gc(gl, 0.6))
			for k in 4:
				var a8 := TAU * float(k) / 4.0 + 0.5
				var path := []
				for j in 6:
					var t := float(j) / 5.0
					path.append(Vector3(cos(a8) * lerpf(6.0, 1.5, t), base + 0.6 + sin(t * PI * 0.5) * 5.0, sin(a8) * lerpf(6.0, 1.5, t)))
				am.tube(path, [0.4, 0.36, 0.32, 0.28, 0.2, 0.12], [BONE, BONE, BONE, BONE, BONE, _gc(gl, 0.7)], 5, true, true, 0.3)
			for k in 8:
				var a4 := TAU * float(k) / 8.0
				am.cone(Vector3(cos(a4) * 5.0, base + 0.8, sin(a4) * 5.0), Vector3(cos(a4) * 3.0, base + 3.0, sin(a4) * 3.0), 0.3, BONE, 4, _gc(gl, 0.6))
		_:
			# the dunes: a ring of fang pillars and bone ribs rising out of a sand crater
			for k in 8:
				var a5 := TAU * float(k) / 8.0 + 0.2
				var p5 := Vector3(cos(a5) * 17.0, 0.0, sin(a5) * 17.0)
				p5.y = _gh(s, p5.x, p5.z) - 0.5
				am.cone(p5, p5 + Vector3(-cos(a5) * 4.0, 9.0 + 2.5 * float(k % 3), -sin(a5) * 4.0), 1.5, BONE.lerp(Color(0.62, 0.5, 0.36), 0.4), 5, _gc(gl, 0.7))
				boxes.append([p5 + Vector3(0.0, 3.0, 0.0), Vector3(2.4, 6.0, 2.4)])
			for k in 4:
				var a6 := TAU * float(k) / 4.0 + 0.6
				var path := []
				for j in 8:
					var t := float(j) / 7.0
					var rr := lerpf(9.0, 4.0, t)
					path.append(Vector3(cos(a6) * rr, _gh(s, cos(a6) * rr, sin(a6) * rr) + sin(t * PI * 0.55) * 6.5, sin(a6) * rr))
				am.tube(path, [0.6, 0.55, 0.5, 0.45, 0.4, 0.34, 0.28, 0.2], [BONE, BONE, BONE, BONE, BONE, BONE, BONE, _gc(gl, 0.7)], 5, true, true, 0.4)
