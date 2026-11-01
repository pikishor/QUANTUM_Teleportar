class_name EnemyTells
extends RefCounted
## Emissive "tells" of the specialist enemies: what makes each type readable at 10-25 m WITHOUT the HUD threat ring.
## One small additive, unshaded mesh per role, built once (static cache) and shared by every enemy of that role, ONE draw call per specialist
## (a specialist stays at most +1 mesh over a plain operative; the shield trooper's plate takes that slot, so the shield has no tell mesh).
##   flanker  four swept orange speed streaks that fade out behind the shoulders and hips (it is always moving: the streaks say "fast")
##   sniper   a hot magenta eye (cross flare), a tall antenna with a magenta tip and a short always-on sight beam in front of the eye
##   brute    orange heat cracks across the chest, hot slabs on both shoulders and a glowing maw: the heat reads even when the body is a dark shape
## Model space is the trooper model's (metres, +Y up, the body faces -Z, head at y 1.5-1.65), scaled by the enemy's own scale. No per-frame work at all.
## The shield trooper's tell is the plate: `shield_texture()` (hex cells and a bright frame, one cached 64 px texture).

const HOT_ORANGE := Color(1.0, 0.34, 0.05)      ## vertex colours are 8 bit (no HDR): the material albedo_color (GLOW) multiplies them above 1
const HOT_MAGENTA := Color(1.0, 0.1, 0.8)
const HOT_RED := Color(1.0, 0.1, 0.03)
const GLOW := 1.9

static var _meshes := {}
static var _mat: StandardMaterial3D
static var _shield_tex: ImageTexture


## The cached tell mesh of a role (null for roles without one).
static func mesh_for(role: StringName) -> ArrayMesh:
	if _meshes.has(role):
		return _meshes[role]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match role:
		&"flanker":
			_flanker(st)
		&"sniper":
			_sniper(st)
		&"brute":
			_brute(st)
		_:
			_meshes[role] = null
			return null
	var m := st.commit()
	m.surface_set_material(0, material())
	_meshes[role] = m
	return m


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.resource_name = "EnemyTell"
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.vertex_color_use_as_albedo = true
		_mat.albedo_color = Color(GLOW, GLOW, GLOW, 1.0)
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.disable_fog = true
		_mat.no_depth_test = false
		_mat.disable_receive_shadows = true
	return _mat


## A MeshInstance3D with the role's tell (null without one). Not shadow casting, no collision, hidden by the owner when the model is.
static func make(role: StringName) -> MeshInstance3D:
	var m := mesh_for(role)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Tell"
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- geometry ------------------------------------------------------------------------------------------------------------------

## A thin ribbon from `a` to `b`, `w` wide at a and `w2` at b, brightness `c0` at a fading to `c1` at b; two crossed quads (about `up`), so it shows from every side.
static func _ribbon(st: SurfaceTool, a: Vector3, b: Vector3, w: float, w2: float, c0: Color, c1: Color) -> void:
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.05:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(dir).normalized()
	for axis: Vector3 in [side, up]:
		var p0 := a - axis * w * 0.5
		var p1 := a + axis * w * 0.5
		var p2 := b + axis * w2 * 0.5
		var p3 := b - axis * w2 * 0.5
		_tri(st, p0, p1, p2, c0, c0, c1)
		_tri(st, p0, p2, p3, c0, c1, c1)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


## A four-armed flare (two crossed diamonds in the XY and ZY planes plus one in XZ): a bright point that reads from any side.
static func _flare(st: SurfaceTool, at: Vector3, r: float, col: Color) -> void:
	var dark := Color(0, 0, 0, 0)
	for ax: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		var u := ax * r
		var v := Vector3.UP * r
		_tri(st, at - u, at + v, at, dark, dark, col)
		_tri(st, at + v, at + u, at, dark, dark, col)
		_tri(st, at + u, at - v, at, dark, dark, col)
		_tri(st, at - v, at - u, at, dark, dark, col)
	var x := Vector3.RIGHT * r
	var z := Vector3.BACK * r
	_tri(st, at - x, at + z, at, dark, dark, col)
	_tri(st, at + z, at + x, at, dark, dark, col)
	_tri(st, at + x, at - z, at, dark, dark, col)
	_tri(st, at - z, at - x, at, dark, dark, col)


static func _flanker(st: SurfaceTool) -> void:
	var fade := Color(0, 0, 0, 0)
	# the body faces -Z: streaks stream back (+Z) from the shoulder blades and the hips, flaring outwards
	for s in [-1.0, 1.0]:
		_ribbon(st, Vector3(s * 0.26, 1.42, 0.12), Vector3(s * 0.55, 1.36, 1.25), 0.07, 0.015, HOT_ORANGE, fade)
		_ribbon(st, Vector3(s * 0.2, 1.22, 0.14), Vector3(s * 0.42, 1.08, 1.0), 0.05, 0.01, HOT_ORANGE * 0.8, fade)
		_ribbon(st, Vector3(s * 0.16, 0.98, 0.0), Vector3(s * 0.3, 0.9, 0.85), 0.04, 0.01, HOT_ORANGE * 0.7, fade)
	_flare(st, Vector3(0.0, 1.5, -0.56), 0.07, HOT_ORANGE)                       # hot eye cluster


static func _sniper(st: SurfaceTool) -> void:
	var fade := Color(0, 0, 0, 0)
	_flare(st, Vector3(0.0, 1.5, -0.58), 0.2, HOT_MAGENTA)                       # the laser eye: a big cross flare (a few pixels even at 25 m)
	_ribbon(st, Vector3(0.0, 1.5, -0.58), Vector3(0.0, 1.5, -2.2), 0.025, 0.006, HOT_MAGENTA * 0.55, fade)    # the sight beam in front of the eye (the aimed beam is EnemyMarks')
	_ribbon(st, Vector3(0.1, 1.62, -0.2), Vector3(0.12, 2.25, -0.05), 0.03, 0.012, Color(0.5, 0.07, 0.4), HOT_MAGENTA)      # a tall antenna: the silhouette taller than a trooper
	_flare(st, Vector3(0.12, 2.25, -0.05), 0.09, HOT_MAGENTA)


static func _brute(st: SurfaceTool) -> void:
	var fade := Color(0, 0, 0, 0)
	# heat cracks across the chest (front is -Z, the carapace surface is about z -0.37) as jagged polylines
	var cracks := [
		[Vector3(-0.02, 1.46, -0.385), Vector3(0.05, 1.36, -0.395), Vector3(-0.04, 1.27, -0.4), Vector3(0.06, 1.18, -0.385), Vector3(0.0, 1.08, -0.35)],
		[Vector3(0.05, 1.36, -0.395), Vector3(0.17, 1.31, -0.39), Vector3(0.24, 1.2, -0.37)],
		[Vector3(-0.04, 1.27, -0.4), Vector3(-0.16, 1.24, -0.395), Vector3(-0.23, 1.14, -0.365)],
		[Vector3(0.05, 1.4, -0.39), Vector3(0.16, 1.45, -0.38), Vector3(0.22, 1.5, -0.34)],
	]
	for c: Array in cracks:
		for i in c.size() - 1:
			_ribbon(st, c[i], c[i + 1], 0.045, 0.035, HOT_RED, HOT_ORANGE)
	for s in [-1.0, 1.0]:                                                           # hot slabs on top of the shoulders, seen from the chase camera too
		_ribbon(st, Vector3(s * 0.2, 1.56, 0.0), Vector3(s * 0.4, 1.5, 0.12), 0.16, 0.09, HOT_ORANGE, HOT_RED)
		_flare(st, Vector3(s * 0.045, 1.5, -0.56), 0.05, HOT_RED)
	_ribbon(st, Vector3(0.0, 1.12, 0.12), Vector3(0.0, 1.5, 0.2), 0.12, 0.06, HOT_RED, HOT_ORANGE)    # a hot spine seam on the back
	_ribbon(st, Vector3(0.0, 1.5, -0.6), Vector3(0.0, 1.38, -0.78), 0.1, 0.06, HOT_ORANGE, fade)     # the maw glow below the mandibles


## The shield plate texture: dark transparent cells, hex-grid lines and a bright frame, additive (the alpha channel is the glow).
static func shield_texture() -> ImageTexture:
	if _shield_tex != null:
		return _shield_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n
			var v := (y + 0.5) / n
			var edge := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
			var frame := 1.0 - smoothstep(0.0, 0.07, edge)
			# hex-ish lattice from three line families
			var px := u * 5.0
			var py := v * 5.0 * 1.1547
			var a := absf(fposmod(px, 1.0) - 0.5)
			var b := absf(fposmod(px * 0.5 + py * 0.866, 1.0) - 0.5)
			var c := absf(fposmod(-px * 0.5 + py * 0.866, 1.0) - 0.5)
			var lat := 1.0 - smoothstep(0.0, 0.09, minf(a, minf(b, c)))
			var vig := smoothstep(0.0, 0.5, edge)                                # cells fade towards the centre: a see-through window with a rim
			var al := clampf(0.16 + 0.35 * lat * (1.0 - 0.5 * vig) + 0.85 * frame, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.45, 0.9, 1.0, al))
	img.generate_mipmaps()
	_shield_tex = ImageTexture.create_from_image(img)
	return _shield_tex
