class_name FallWorld
extends Node3D
## The waterfalls in the live world (wave 112; data LandscapeSites.falls(), shader assets/shaders/fall_water.gdshader): per fall the falling SHEET hugging the cliff, the plunge POOL disc,
## the STREAMS above the lip and below the pool, MIST (CPU particles, one draw) rising from the foot, a SPRAY layer on higher tiers and the ROAR (a looping positional noise).
## Nothing is created per frame: the meshes are built once, a 0.4 s tick shows a fall within SHOW_RANGE, runs its particles and sound within NEAR_RANGE and leans the mist with the wind.
## Draw calls: sheet + pool + two streams + mist = 5 per VISIBLE fall, none beyond SHOW_RANGE (the city views never see one).
##   FallWorld.instance.fall_count()   stats()   {visible, near, tris}   node(i) -> the Node3D of fall i (tests)

const SHADER := "res://assets/shaders/fall_water.gdshader"
const SHOW_RANGE := 900.0
const BUILD_RANGE := 1150.0                  ## a fall is built (about 0.1 s on a desktop) when the hero comes within this range, one per 0.4 s tick; until then it costs nothing
const NEAR_RANGE := 440.0
const MIST_AMOUNT := [8, 18, 30]
const SPRAY_AMOUNT := [0, 12, 26]
const SHEET_COLS := [5, 7, 9]

static var instance: FallWorld = null
static var _mist_tex: ImageTexture
static var _roar: AudioStreamWAV

var quality := 1
var _items: Array = []                       ## per fall (index of LandscapeSites.falls()): {data, root, mist, spray, roar, near, tris} once built, else null
var _t := 0.0
var _mats := {}


func _ready() -> void:
	instance = self
	LandscapeSites.ensure()
	for _f in LandscapeSites.falls():
		_items.append(null)
	set_process(true)


## Builds every fall now (tests, look-dev bots, `Landscape.settle`).
func build_all() -> void:
	var falls := LandscapeSites.falls()
	for i in falls.size():
		if _items[i] == null:
			_items[i] = _build(falls[i])


func built_count() -> int:
	var n := 0
	for it in _items:
		n += 1 if it != null else 0
	return n


func _exit_tree() -> void:
	if instance == self:
		instance = null


func fall_count() -> int:
	return _items.size()


func node(i: int) -> Node3D:
	return _items[i]["root"] if _items[i] != null else null


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	var falls := LandscapeSites.falls()
	var rebuild: Array = []
	for i in _items.size():
		if _items[i] != null:
			(_items[i]["root"] as Node3D).queue_free()
			_items[i] = null
			rebuild.append(i)
	_mats.clear()
	for i in rebuild:
		_items[i] = _build(falls[i])


func stats() -> Dictionary:
	var v := 0
	var nr := 0
	var tris := 0
	for it in _items:
		if it == null:
			continue
		if ((it as Dictionary)["root"] as Node3D).visible:
			v += 1
			tris += int((it as Dictionary)["tris"])
		if bool((it as Dictionary)["near"]):
			nr += 1
	return {"falls": _items.size(), "falls_built": built_count(), "visible": v, "near": nr, "tris": tris}


# --- building ---------------------------------------------------------------------------------------------------------------------------------

func _mat(mode: int, spd := 7.0, impact := Vector2.ZERO, bias0 := 0.9) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER) as Shader
	m.set_shader_parameter(&"mode", mode)
	m.set_shader_parameter(&"speed", spd)
	m.set_shader_parameter(&"impact", impact)
	m.set_shader_parameter(&"bias0", bias0)
	return m


func _ground(x: float, z: float) -> float:
	return TerrainHeight.height_at(x, z)


func _build(f: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = String(f["id"])
	root.top_level = true
	root.visible = false
	add_child(root)
	var tris := 0
	var sheet := _sheet_mesh(f)
	var mi := MeshInstance3D.new()
	mi.name = "Sheet"
	mi.mesh = sheet
	mi.material_override = _mat(0, 7.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	tris += _tri(sheet)
	var wet := _sheet_mesh(f, true)
	var wi := MeshInstance3D.new()
	wi.name = "Wet"
	wi.mesh = wet
	wi.material_override = _mat(3, 7.0, Vector2.ZERO, 0.45)
	wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wi)
	tris += _tri(wet)
	var pool := _pool_mesh(f)
	var pi := MeshInstance3D.new()
	pi.name = "Pool"
	pi.mesh = pool
	var pc: Vector2 = f["pool"]
	var base: Vector2 = f["base"]
	var imp := (base - pc) / maxf(float(f["pool_r"]), 1.0)
	pi.material_override = _mat(1, 1.0, Vector2(imp.x, imp.y))
	pi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pi)
	tris += _tri(pool)
	for key in ["up", "out"]:
		var rb := _ribbon(f, key)
		if rb != null:
			var ri := MeshInstance3D.new()
			ri.name = "Stream" + String(key).capitalize()
			ri.mesh = rb
			ri.material_override = _mat(2, 7.0)
			ri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(ri)
			tris += _tri(rb)
	var foot := Vector3(base.x + (f["dir"] as Vector2).x * 2.5, float(f["pool_y"]) + 1.2, base.y + (f["dir"] as Vector2).y * 2.5)
	var mist := _mist(f, foot, quality)
	root.add_child(mist)
	var spray: CPUParticles3D = null
	if int(SPRAY_AMOUNT[quality]) > 0:
		spray = _spray(f, foot, quality)
		root.add_child(spray)
	var roar := AudioStreamPlayer3D.new()
	roar.name = "Roar"
	roar.stream = _roar_stream()
	roar.unit_size = 55.0
	roar.max_distance = 420.0
	roar.volume_db = -3.0
	roar.bus = &"SFX"
	roar.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	roar.position = foot
	roar.autoplay = false
	root.add_child(roar)
	root.global_position = Vector3.ZERO
	return {"data": f, "root": root, "mist": mist, "spray": spray, "roar": roar, "near": false, "tris": tris, "foot": foot}


static func _tri(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		n += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func _sheet_mesh(f: Dictionary, wide := false) -> ArrayMesh:
	var dir: Vector2 = f["dir"]
	var lip: Vector2 = f["lip"]
	var base: Vector2 = f["base"]
	var side := Vector2(-dir.y, dir.x)
	var run := lip.distance_to(base)
	var rows := maxi(10, int(run / 1.6) + 1)
	var cols: int = SHEET_COLS[quality] if not wide else 6
	var width: float = float(f["width"]) * (2.1 if wide else 1.0)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var prev := PackedVector3Array()
	var run_len := PackedFloat32Array()
	run_len.resize(cols + 1)
	for i in rows + 1:
		var t := float(i) / float(rows)
		var q := lip.lerp(base, t)
		for j in cols + 1:
			var u := float(j) / float(cols)
			var wob := (sin(float(i) * 1.7 + float(j) * 2.3) + sin(float(i) * 0.6 - float(j) * 4.1)) * 0.22
			var s := (u - 0.5) * width * (0.78 + 0.22 * t) + wob * (1.0 if (j > 0 and j < cols) else 0.4)
			var qx := q.x + side.x * s
			var qz := q.y + side.y * s
			var gy := _ground(qx, qz)
			var e := 1.2
			var nx := _ground(qx - e, qz) - _ground(qx + e, qz)
			var nz := _ground(qx, qz - e) - _ground(qx, qz + e)
			var n := Vector3(nx, 2.0 * e, nz).normalized()
			var bul := 1.5 * pow(maxf(0.0, 1.0 - t / 0.22), 2.0)
			var p := Vector3(qx, gy, qz) + n * ((0.55 + 0.35 * (1.0 - t)) if not wide else 0.18) + Vector3(dir.x, 0.0, dir.y) * (bul if not wide else 0.0)
			pos.append(p)
			nrm.append(n)
			if i == 0:
				run_len[j] = 0.0
			else:
				run_len[j] += p.distance_to(prev[j])
			if prev.size() <= j:
				prev.append(p)
			else:
				prev[j] = p
			uv.append(Vector2(u, run_len[j]))
			var edge := smoothstep(0.0, 0.2, u) * smoothstep(1.0, 0.8, u)
			col.append(Color(t, 0.0, 0.0, edge))
	for i in rows:
		for j in cols:
			var a := i * (cols + 1) + j
			var b := a + 1
			var c := a + cols + 1
			var d := c + 1
			idx.append_array(PackedInt32Array([a, c, b, b, c, d]))
	return _mesh(pos, nrm, uv, col, idx)


func _pool_mesh(f: Dictionary) -> ArrayMesh:
	var pc: Vector2 = f["pool"]
	var r: float = float(f["pool_r"]) + 0.9
	var segs: int = [28, 40, 56][quality]
	var rings: int = [4, 6, 8][quality]
	var y: float = float(f["pool_y"]) + 0.03
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	pos.append(Vector3(pc.x, y, pc.y))
	nrm.append(Vector3.UP)
	uv.append(Vector2.ZERO)
	col.append(Color(0, 0, 0, 0))
	for ri in range(1, rings + 1):
		var rr := float(ri) / float(rings)
		for si in segs:
			var a := TAU * float(si) / float(segs)
			var lx := cos(a) * rr * r
			var lz := sin(a) * rr * r
			pos.append(Vector3(pc.x + lx, y, pc.y + lz))
			nrm.append(Vector3.UP)
			uv.append(Vector2(cos(a) * rr * (r / float(f["pool_r"])), sin(a) * rr * (r / float(f["pool_r"]))))
			col.append(Color(0, 0, 0, smoothstep(0.55, 1.0, rr)))
	for si in segs:
		idx.append_array(PackedInt32Array([0, 1 + si, 1 + (si + 1) % segs]))
	for ri in range(0, rings - 1):
		for si in segs:
			var a0 := 1 + ri * segs + si
			var a1 := 1 + ri * segs + (si + 1) % segs
			var b0 := 1 + (ri + 1) * segs + si
			var b1 := 1 + (ri + 1) * segs + (si + 1) % segs
			idx.append_array(PackedInt32Array([a0, b0, a1, a1, b0, b1]))
	return _mesh(pos, nrm, uv, col, idx)


func _ribbon(f: Dictionary, key: String) -> ArrayMesh:
	var pts: PackedVector2Array = f[key]
	var beds: PackedFloat32Array = f[key + "_y"]
	if pts.size() < 3:
		return null
	var start := 0
	if key == "out":                                         # skip the part inside the pool
		var pc: Vector2 = f["pool"]
		while start < pts.size() - 2 and pts[start].distance_to(pc) < float(f["pool_r"]) - 1.0:
			start += 1
	var width := 3.6 if key == "up" else 4.6
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var run := 0.0
	var n := pts.size()
	for i in range(start, n):
		if i > start:
			run += pts[i].distance_to(pts[i - 1])
		var tg := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, start)]).normalized()
		var nr := Vector2(-tg.y, tg.x)
		var w := width * (0.8 + 0.4 * smoothstep(0.0, 1.0, float(i - start) / float(maxi(n - start, 1))))
		var slope_i := TerrainHeight.slope_at(pts[i].x, pts[i].y)
		var fast := clampf(0.35 + 2.6 * slope_i, 0.35, 1.0)
		var steep_fade := 1.0 - smoothstep(0.13, 0.28, slope_i)                                    # a ribbon on a slope looked like a plank: it fades out where the ground is steep
		if key == "up" and i >= n - 3:
			fast = 1.0
			steep_fade = 1.0
		for k in 3:
			var off := (float(k) - 1.0) * w * 0.5
			var q := pts[i] + nr * off
			var yq := maxf(TerrainHeight.height_at(q.x, q.y), beds[i] + 0.1) + 0.12                    # on the real (carved) surface at each vertex, never a plank hung from the centre line
			pos.append(Vector3(q.x, yq, q.y))
			nrm.append(Vector3.UP)
			uv.append(Vector2(float(k) * 0.5, run))
			var fade := steep_fade
			if key == "up" and i == start:
				fade = 0.0
			if key == "out" and i >= n - 2:
				fade = 0.0
			col.append(Color(fast, 0.0, 0.0, (1.0 if k == 1 else 0.0) * fade if fade > 0.0 else 0.0))
	var m := n - start
	for i in m - 1:
		for k in 2:
			var a := i * 3 + k
			idx.append_array(PackedInt32Array([a, a + 3, a + 1, a + 1, a + 3, a + 4]))
	return _mesh(pos, nrm, uv, col, idx)


func _mesh(pos: PackedVector3Array, nrm: PackedVector3Array, uv: PackedVector2Array, col: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# --- particles and sound ------------------------------------------------------------------------------------------------------------------------

static func _mist_texture() -> ImageTexture:
	if _mist_tex == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for y in n:
			for x in n:
				var dx := (float(x) + 0.5) / float(n) * 2.0 - 1.0
				var dy := (float(y) + 0.5) / float(n) * 2.0 - 1.0
				var d := sqrt(dx * dx + dy * dy)
				var a := clampf(1.0 - d, 0.0, 1.0)
				a = a * a * (3.0 - 2.0 * a)
				a *= 0.75 + 0.25 * sin(float(x) * 0.7 + float(y) * 0.45) * cos(float(y) * 0.6 - float(x) * 0.3)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
		_mist_tex = ImageTexture.create_from_image(img)
	return _mist_tex


func _particle_mesh(size: float, tex: Texture2D, tint: Color) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.disable_receive_shadows = true
	q.material = m
	return q


func _mist(f: Dictionary, foot: Vector3, q: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Mist"
	p.amount = int(MIST_AMOUNT[q])
	p.lifetime = 4.2
	p.preprocess = 4.2
	p.explosiveness = 0.0
	p.local_coords = false
	p.emitting = false
	p.position = foot
	p.mesh = _particle_mesh(1.0, _mist_texture(), Color(1, 1, 1, 1))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = clampf(float(f["pool_r"]) * 0.5, 4.0, 8.0)
	p.direction = Vector3(0, 1, 0)
	p.spread = 40.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0.0, 0.08, 0.0)
	p.scale_amount_min = 9.0
	p.scale_amount_max = 16.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.18, Color(0.95, 0.98, 1.0, 0.40))
	g.add_point(0.6, Color(0.92, 0.96, 1.0, 0.20))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _spray(f: Dictionary, foot: Vector3, q: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Spray"
	p.amount = int(SPRAY_AMOUNT[q])
	p.lifetime = 1.6
	p.preprocess = 1.6
	p.local_coords = false
	p.emitting = false
	p.position = foot - Vector3(0, 0.6, 0)
	p.mesh = _particle_mesh(1.0, _mist_texture(), Color(1, 1, 1, 1))
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 3.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0.0, -7.0, 0.0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.7
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.30))
	g.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## A looping roar: brown noise through two one-pole filters with a slow swell, crossfaded at the loop point (16-bit mono, 22.05 kHz, 3 s).
static func _roar_stream() -> AudioStreamWAV:
	if _roar != null:
		return _roar
	var rate := 22050
	var n := rate * 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var data := PackedFloat32Array()
	data.resize(n)
	var lp1 := 0.0
	var lp2 := 0.0
	var br := 0.0
	for i in n:
		var w := rng.randf() * 2.0 - 1.0
		br = clampf(br * 0.985 + w * 0.12, -1.0, 1.0)
		lp1 += (w - lp1) * 0.30
		lp2 += (lp1 - lp2) * 0.22
		var swell := 0.85 + 0.15 * sin(float(i) / float(rate) * TAU * 0.7) + 0.08 * sin(float(i) / float(rate) * TAU * 2.3)
		data[i] = (br * 0.9 + lp2 * 0.85) * swell
	var xf := rate / 5
	for i in xf:                                             # crossfade the tail into the head so the loop is seamless
		var k := float(i) / float(xf)
		data[i] = data[i] * k + data[n - xf + i] * (1.0 - k)
	var bytes := PackedByteArray()
	bytes.resize((n - xf) * 2)
	var peak := 0.0001
	for i in n - xf:
		peak = maxf(peak, absf(data[i]))
	for i in n - xf:
		var v := clampi(int(data[i] / peak * 0.8 * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n - xf
	w.data = bytes
	_roar = w
	return w


# --- the tick -----------------------------------------------------------------------------------------------------------------------------------

func _focus() -> Vector3:
	var p := Game.player as Node3D
	if is_instance_valid(p):
		return p.global_position
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	return cam.global_position if cam != null else Vector3(1.0e9, 0.0, 1.0e9)


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.4:
		return
	_t = 0.0
	tick(_focus())


## One update for a viewer at `at` (public so tests and look-dev bots can drive it).
func tick(at: Vector3) -> void:
	var wv := LandClimate.vec()
	var falls := LandscapeSites.falls()
	var built_one := false
	for i in _items.size():
		if _items[i] == null:                                   # not built yet: build it when the hero is within BUILD_RANGE (one per tick)
			if built_one:
				continue
			var pcb: Vector2 = falls[i]["pool"]
			if Vector2(at.x, at.z).distance_to(pcb) < BUILD_RANGE:
				_items[i] = _build(falls[i])
				built_one = true
			continue
		var it: Dictionary = _items[i]
		var f: Dictionary = it["data"]
		var pc: Vector2 = f["pool"]
		var d := Vector2(at.x, at.z).distance_to(pc)
		var root: Node3D = it["root"]
		var show := d < SHOW_RANGE
		if root.visible != show:
			root.visible = show
		var near := d < NEAR_RANGE
		if near != bool(it["near"]):
			it["near"] = near
			(it["mist"] as CPUParticles3D).emitting = near
			if it["spray"] != null:
				(it["spray"] as CPUParticles3D).emitting = near
			var roar := it["roar"] as AudioStreamPlayer3D
			if near:
				if not roar.playing:
					roar.play()
			else:
				roar.stop()
		if near:
			(it["mist"] as CPUParticles3D).gravity = Vector3(wv.x * wv.y * 1.6, 0.1, wv.z * wv.y * 1.6)
