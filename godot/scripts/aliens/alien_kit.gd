class_name AlienKit
extends RefCounted
## Shared pieces of the alien life (wave 107b): the one shader and its per-body material, the cached model scenes and the PROCEDURAL bodies (the burrowing worm, the sea serpent, the kraken's
## mantle and arms, the spore sentry, the hive heart, the shield relay). Procedural bodies are one lofted ArrayMesh each (AlienMesh): final size in metres, facing -Z, standing on y = 0,
## vertex colour = paint, alpha = glow mask (alien.gdshader). No textures anywhere: the aliens cost no texture memory.

const SHADER := preload("res://assets/shaders/alien.gdshader")

static var _scenes := {}
static var _meshes := {}
static var _site_mat: ShaderMaterial = null


## A material of its own for one creature (Compatibility has no instance uniforms, so every body owns a copy).
static func material(glow: Color, shell := 0.55) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"glow", Vector3(glow.r, glow.g, glow.b))
	m.set_shader_parameter(&"shell", shell)
	return m


## The shared material of the static site meshes (camps, nests, wrecks): paint and glow from the vertex colours, no per-instance values.
static func site_material() -> ShaderMaterial:
	if _site_mat == null:
		_site_mat = material(Color(0.55, 1.0, 0.7), 0.35)
		_site_mat.set_shader_parameter(&"glow_k", 1.3)
	return _site_mat


static func available() -> bool:
	return ResourceLoader.exists(AlienSpecies.DIR + "grunt.scn")


## The converted model of a species (PackedScene, cached) or null (procedural bodies, a missing file).
static func scene(id: StringName) -> PackedScene:
	if _scenes.has(id):
		return _scenes[id]
	var path := AlienSpecies.model_path(id)
	var s: PackedScene = null
	if path != "" and ResourceLoader.exists(path):
		s = load(path) as PackedScene
	_scenes[id] = s
	return s


## The procedural mesh of species `id` (built once, cached): {mesh, height (m), hit (the body's reach for the shots)}.
static func proc_mesh(proc: StringName) -> ArrayMesh:
	if _meshes.has(proc):
		return _meshes[proc]
	var m: ArrayMesh = null
	match proc:
		&"worm": m = worm_mesh(13.0, 1.25, Color(0.58, 0.43, 0.27), Color(0.36, 0.25, 0.16), Color(1.0, 0.5, 0.15), false)
		&"serpent": m = worm_mesh(9.0, 0.62, Color(0.12, 0.34, 0.36), Color(0.07, 0.2, 0.26), Color(0.3, 1.0, 0.95), true)
		&"kraken": m = kraken_mesh()
		&"tentacle": m = tentacle_mesh()
		&"sentry": m = sentry_mesh()
		&"heart": m = heart_mesh()
		&"relay": m = relay_mesh()
	_meshes[proc] = m
	return m


## A rising worm: starts upright on y = 0 (the sand line), bends over toward -Z near the top, ends in a toothed maw that looks forward and down. `fin` adds the serpent's dorsal crest and fangs.
static func worm_mesh(length: float, rad: float, body: Color, band: Color, glow: Color, fin: bool) -> ArrayMesh:
	var am := AlienMesh.new()
	var n := 22
	var path := []
	var radii := []
	var cols := []
	var pos := Vector3.ZERO
	var step := length / float(n)
	var dirs := []
	for k in n + 1:
		var t := float(k) / float(n)
		var theta := deg_to_rad(115.0) * smoothstep(0.3, 1.0, t)
		var dir := Vector3(0.0, cos(theta), -sin(theta))
		dirs.append(dir)
		path.append(pos)
		pos += dir * step
		var r := rad * (1.0 + 0.3 * (1.0 - t) - 0.2 * smoothstep(0.35, 0.85, t))
		if t > 0.9:
			r *= 1.0 + 0.5 * (t - 0.9) / 0.1 if not fin else 1.0 + 0.25 * (t - 0.9) / 0.1
		radii.append(r)
		var ring := k % 2 == 0
		var col := body if ring else body.lerp(band, 0.4)
		col = col.lerp(Color(0.2, 0.15, 0.1), 0.25 * (1.0 - t))
		col.a = 0.55 if k % 3 == 1 else 0.0                                       # glowing seams every third ring
		cols.append(col)
	am.tube(path, radii, cols, 10, true, false)
	# the head: an open maw of petals around the last ring, a glowing throat inside, spines along the back
	var head: Vector3 = path[n]
	var hd: Vector3 = (dirs[n] as Vector3)
	var hr: float = radii[n]
	var side := hd.cross(Vector3.RIGHT).normalized()
	var up := side.cross(hd).normalized()
	var petals := 6 if not fin else 4
	for pnum in petals:
		var a := TAU * float(pnum) / float(petals) + 0.3
		var off := side * cos(a) + up * sin(a)
		var tipp := head + hd * (rad * 1.5) + off * (hr * 1.25)
		am.cone(head + off * hr * 0.55, tipp, hr * 0.34, body.lerp(Color.WHITE, 0.12), 5, Color(glow.r, glow.g, glow.b, 0.99) if fin else Color(0.9, 0.82, 0.68, 0.5))
		# teeth inside the petals
		am.cone(head + off * hr * 0.4 + hd * rad * 0.3, head + off * hr * 0.1 + hd * rad * 1.1, hr * 0.11, Color(glow.r, glow.g, glow.b, 0.99), 4)
	am.ellipsoid(head + hd * rad * 0.1, Vector3(hr * 0.62, hr * 0.62, hr * 0.3), Color(glow.r, glow.g, glow.b, 0.99), 4, 8, Basis.looking_at(hd, up))
	for k in range(3, n - 2, 2):
		var p: Vector3 = path[k]
		var d: Vector3 = dirs[k]
		var s := d.cross(Vector3.RIGHT).normalized()
		var u := s.cross(d).normalized()
		var rr: float = radii[k]
		var spine := (u + d * 0.2).normalized()
		if absf(u.z) < 0.01:
			spine = Vector3.UP
		am.cone(p + spine * rr * 0.85, p + spine * (rr * (1.9 if not fin else 2.4)), rr * 0.2, band.lerp(Color.WHITE, 0.1), 4, Color(glow.r, glow.g, glow.b, 0.8))
	if fin:                                                                        # the serpent's crest: a row of tall flat spines
		for k in range(2, n, 1):
			var p2: Vector3 = path[k]
			var d2: Vector3 = dirs[k]
			var s2 := d2.cross(Vector3.RIGHT).normalized()
			var u2 := s2.cross(d2).normalized()
			var rr2: float = radii[k]
			am.cone(p2 + u2 * rr2 * 0.8 + d2 * step * 0.3, p2 + u2 * (rr2 * 2.6) - d2 * step * 0.6, rr2 * 0.35, Color(glow.r, glow.g, glow.b, 0.7), 3)
	return am.commit()


## The kraken's mantle: a domed, ridged head that floats half out of the water (its centre at y = 0, so the node sits on the water line), two huge glowing eyes, a hooked beak and a skirt of
## short tentacle stumps; the long arms are separate bodies (`tentacle_mesh`).
static func kraken_mesh() -> ArrayMesh:
	var am := AlienMesh.new()
	var body := Color(0.16, 0.24, 0.34)
	var dark := Color(0.08, 0.13, 0.22)
	var glow := Color(0.3, 1.0, 0.9)
	am.ellipsoid(Vector3(0.0, 1.8, 0.8), Vector3(3.6, 3.4, 4.2), body, 7, 12, Basis(Vector3.RIGHT, deg_to_rad(-18.0)), Color(0.28, 0.38, 0.5, 0.0))
	am.ellipsoid(Vector3(0.0, 1.3, -2.4), Vector3(2.9, 2.2, 2.4), body.lerp(dark, 0.3), 6, 10)
	for sx in [-1.0, 1.0]:
		am.ellipsoid(Vector3(sx * 1.8, 2.1, -3.6), Vector3(0.6, 0.72, 0.4), Color(glow.r * 0.6, glow.g * 0.6, glow.b * 0.6, 0.45), 4, 8)
		am.ellipsoid(Vector3(sx * 1.8, 2.1, -3.95), Vector3(0.1, 0.55, 0.14), Color(0.02, 0.02, 0.04, 0.0), 3, 6)
	am.cone(Vector3(0.0, 0.4, -4.2), Vector3(0.0, -0.9, -5.6), 0.7, Color(0.75, 0.68, 0.52), 5, Color(0.95, 0.9, 0.8, 0.4))
	for k in 7:                                                                    # dorsal ridges over the mantle
		var a := -0.9 + 0.3 * float(k)
		am.cone(Vector3(0.0, 4.4 - absf(a) * 1.2, 1.2 + a * 3.0), Vector3(0.0, 6.0 - absf(a) * 1.6, 1.4 + a * 3.6), 0.38, dark, 4, Color(glow.r, glow.g, glow.b, 0.8))
	for k in 8:                                                                    # short stumps around the water line
		var a2 := TAU * float(k) / 8.0
		var p := Vector3(cos(a2) * 3.1, 0.4, sin(a2) * 3.1 + 0.4)
		var path := [p, p + Vector3(cos(a2) * 1.2, 0.5, sin(a2) * 1.2), p + Vector3(cos(a2) * 2.2, -0.2, sin(a2) * 2.2)]
		am.tube(path, [0.45, 0.32, 0.12], [dark, body, Color(glow.r, glow.g, glow.b, 0.6)], 6, false, true, 0.2)
	return am.commit()


## One arm of the kraken: 11 m high, an S-curve that hooks over at the tip, suckers on the inner side, a glowing tip. Built upright from y = 0 (the water line), leaning toward -Z.
static func tentacle_mesh() -> ArrayMesh:
	var am := AlienMesh.new()
	var body := Color(0.18, 0.26, 0.36)
	var dark := Color(0.09, 0.15, 0.24)
	var glow := Color(0.3, 1.0, 0.9)
	var path := []
	var radii := []
	var cols := []
	var n := 16
	for k in n + 1:
		var t := float(k) / float(n)
		var p := Vector3(0.9 * sin(t * 5.0) * (1.0 - t * 0.4), t * 11.0 - 1.5 * t * t * 3.0, -0.2 - 2.4 * t * t - 1.6 * smoothstep(0.7, 1.0, t))
		path.append(p)
		radii.append(0.95 * (1.0 - 0.88 * t) + 0.06)
		var c := body if k % 2 == 0 else dark
		c.a = 0.9 if k == n else (0.35 if k % 3 == 0 else 0.0)
		cols.append(c)
	am.tube(path, radii, cols, 7, true, true, 0.4)
	for k in range(2, n, 2):                                                       # suckers along the inner (+Z) side
		var p2: Vector3 = path[k]
		am.ellipsoid(p2 + Vector3(0.0, 0.0, float(radii[k]) * 0.85), Vector3(float(radii[k]) * 0.4, float(radii[k]) * 0.4, float(radii[k]) * 0.25), Color(0.7, 0.62, 0.78, 0.45), 3, 6)
	am.cone(path[n], (path[n] as Vector3) + Vector3(0.0, 0.5, -1.0), 0.14, Color(glow.r, glow.g, glow.b, 0.99), 4)
	return am.commit()


## The spore sentry: a 2.2 m stalk with a bulb, four leaf petals and one big glowing eye on the front; roots at the foot.
static func sentry_mesh() -> ArrayMesh:
	var am := AlienMesh.new()
	var stalk := Color(0.22, 0.3, 0.16)
	var leaf := Color(0.14, 0.24, 0.12)
	var glow := Color(0.8, 1.0, 0.2)
	var path := [Vector3(0, 0, 0), Vector3(0.0, 0.7, 0.1), Vector3(0.05, 1.3, -0.1), Vector3(0.0, 1.8, -0.25)]
	am.tube(path, [0.32, 0.22, 0.2, 0.26], [stalk, stalk.lerp(leaf, 0.5), stalk, Color(stalk.r, stalk.g, stalk.b, 0.4)], 7, true, false)
	am.ellipsoid(Vector3(0.0, 2.05, -0.32), Vector3(0.62, 0.55, 0.62), Color(0.3, 0.36, 0.18), 5, 9)
	am.ellipsoid(Vector3(0.0, 2.08, -0.8), Vector3(0.3, 0.3, 0.14), Color(glow.r, glow.g, glow.b, 0.99), 4, 8)
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.4
		var off := Vector3(cos(a), 0.0, sin(a))
		am.ellipsoid(Vector3(0.0, 2.0, -0.3) + off * 0.55 + Vector3(0.0, 0.25, 0.0), Vector3(0.2, 0.6, 0.45), leaf, 3, 6, Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, 0.5), Color(0.28, 0.4, 0.14, 0.3))
	for k in 5:
		var a2 := TAU * float(k) / 5.0
		am.cone(Vector3(cos(a2) * 0.2, 0.2, sin(a2) * 0.2), Vector3(cos(a2) * 0.95, 0.0, sin(a2) * 0.95), 0.12, stalk.lerp(leaf, 0.5), 4)
	return am.commit()


## The hive heart: a throbbing 3.4 m mass of dark red flesh with glowing veins on a pad of roots, ringed by six eggs.
static func heart_mesh() -> ArrayMesh:
	var am := AlienMesh.new()
	var flesh := Color(0.42, 0.1, 0.18)
	var vein := Color(1.0, 0.3, 0.55)
	am.ellipsoid(Vector3(0.0, 1.7, 0.0), Vector3(1.8, 1.7, 1.7), flesh, 6, 10, Basis.IDENTITY, Color(0.55, 0.16, 0.24, 0.0))
	am.ellipsoid(Vector3(0.9, 2.1, -0.5), Vector3(0.9, 0.9, 0.9), flesh.lerp(vein, 0.1), 4, 8)
	am.ellipsoid(Vector3(-0.8, 2.4, 0.4), Vector3(0.8, 0.8, 0.8), flesh.lerp(vein, 0.1), 4, 8)
	for k in 6:                                                                    # veins crawling over it
		var a := TAU * float(k) / 6.0
		var path := [Vector3(cos(a) * 0.6, 3.2, sin(a) * 0.6), Vector3(cos(a) * 1.5, 2.6, sin(a) * 1.5), Vector3(cos(a) * 1.95, 1.7, sin(a) * 1.95), Vector3(cos(a) * 1.8, 0.7, sin(a) * 1.8)]
		am.tube(path, [0.06, 0.08, 0.07, 0.06], [Color(vein.r, vein.g, vein.b, 0.99), Color(vein.r, vein.g, vein.b, 0.99), Color(vein.r, vein.g, vein.b, 0.99), Color(vein.r, vein.g, vein.b, 0.7)], 4, false, false)
	for k in 7:                                                                    # roots on the ground
		var a2 := TAU * float(k) / 7.0 + 0.2
		var path2 := [Vector3(cos(a2) * 1.4, 0.4, sin(a2) * 1.4), Vector3(cos(a2) * 2.6, 0.25, sin(a2) * 2.6), Vector3(cos(a2) * 3.8 + sin(a2) * 0.5, 0.1, sin(a2) * 3.8 - cos(a2) * 0.5)]
		am.tube(path2, [0.34, 0.22, 0.08], [flesh, flesh, Color(vein.r, vein.g, vein.b, 0.5)], 5, false, true, 0.2)
	for k in 6:                                                                    # eggs
		var a3 := TAU * float(k) / 6.0 + 0.5
		am.ellipsoid(Vector3(cos(a3) * 3.0, 0.45, sin(a3) * 3.0), Vector3(0.5, 0.65, 0.5), Color(0.75, 0.68, 0.55, 0.0), 4, 7, Basis.IDENTITY, Color(0.9, 0.5, 0.55, 0.25))
	return am.commit()


## The shield relay: a 3.6 m crystal spire on a ring of prongs, glowing cyan.
static func relay_mesh() -> ArrayMesh:
	var am := AlienMesh.new()
	var rock := Color(0.2, 0.22, 0.27)
	var cyan := Color(0.3, 0.9, 1.0)
	am.disc(Vector3(0, 0.05, 0), 1.3, rock, 8)
	am.cone(Vector3(0, 0.1, 0), Vector3(0, 3.7, 0), 0.62, Color(cyan.r * 0.5, cyan.g * 0.6, cyan.b * 0.6, 0.85), 6, Color(cyan.r, cyan.g, cyan.b, 0.99))
	am.cone(Vector3(0, -0.1, 0), Vector3(0, 0.1, 0), 0.7, rock, 6)
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.6
		am.cone(Vector3(cos(a) * 0.95, 0.0, sin(a) * 0.95), Vector3(cos(a) * 0.55, 2.2, sin(a) * 0.55), 0.26, rock.lerp(cyan, 0.15), 4, Color(cyan.r, cyan.g, cyan.b, 0.8))
	return am.commit()
