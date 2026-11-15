class_name SnakeTendrilPool
extends Node3D
## The pool and the renderer of every SnakeTendril (see snake_tendril.gd for the API). One child MultiMeshInstance3D, ONE draw call while any tendril lives (hidden otherwise);
## the control points of each live tendril go into one RGBA32F data texture (one row per tendril, one texel per point) that assets/shaders/snake_tendril.gdshader reads in its
## vertex stage, so the body is a smooth tube whatever its length, thickness or wriggle. Caps by tier (Game.quality): LOW 4 x 18 points x 20 rings x 6 sides, MED 6 x 26 x 28 x 8,
## HIGH 8 x 32 x 40 x 10 (a tendril is 288 / 704 / 1488 triangles). The node is a child of the Player (created on first use, top_level) or of the `host` of the first fire() call.
## It simulates in every state except a pause and renders what the tendrils say, including their travel particles (FX.burst) and the arrival burst.

const SHADER := preload("res://assets/shaders/snake_tendril.gdshader")
const TEX_W := 32
## per tier: [max tendrils, control points, body rings, sides, glow, head rings]
const TIERS: Array = [[4, 18, 18, 6, 1.0, 6], [6, 26, 34, 8, 1.0, 10], [8, 32, 48, 12, 1.05, 14]]
const FAR_AABB := AABB(Vector3(-6000.0, -600.0, -6000.0), Vector3(12000.0, 3000.0, 12000.0))

static var current: SnakeTendrilPool

var tendrils: Array[SnakeTendril] = []
var fired := 0                                  ## counters (tests wait on these, not on frames)
var retired := 0
var drawn := 0                                  ## tendrils written to the GPU last frame

var _tier := -1
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _img: Image
var _tex: ImageTexture
var _buf := PackedFloat32Array()
var _cap := 3
var _npts := 18
var _puff_t := 0.0


static func get_pool(host: Node = null) -> SnakeTendrilPool:
	if is_instance_valid(current) and current.is_inside_tree():
		return current
	var parent: Node = host
	if parent == null and is_instance_valid(Game.player):
		parent = Game.player
	if parent == null or not parent.is_inside_tree():
		return null
	var pool := SnakeTendrilPool.new()
	pool.name = "SnakeTendrils"
	parent.add_child(pool)
	return pool


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	current = self
	process_priority = 110                              # after the player and the camera rig: the hand it follows is where the frame left it
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.new_game.connect(clear)
	Game.respawn.connect(clear)
	Game.quality_changed.connect(func(_l: int) -> void: _build(Game.quality))
	_build(Game.quality)


func _exit_tree() -> void:
	if current == self:
		current = null


## Add a tendril to the pool (SnakeTendril.fire does this).
func add(t: SnakeTendril) -> void:
	if tendrils.size() >= _cap:
		_retire_one()
	t._pool = self
	tendrils.append(t)
	fired += 1
	set_process(true)


func _retire_one() -> void:
	var pick := -1
	for i in tendrils.size():
		if tendrils[i].state == SnakeTendril.State.ATTACHED and not bool(tendrils[i].user.get("keep", false)):
			pick = i
			break
	if pick < 0:
		for i in tendrils.size():
			if not bool(tendrils[i].user.get("keep", false)):
				pick = i
				break
	if pick < 0:
		pick = 0
	var t := tendrils[pick]
	tendrils.remove_at(pick)
	t.kill()
	retired += 1


## End every tendril at once (a new game, a respawn, a teleport that must not leave a snake behind).
func clear() -> void:
	for t in tendrils:
		t.kill()
	tendrils.clear()
	_sync_visible()


func count() -> int:
	return tendrils.size()


func cap() -> int:
	return _cap


func _build(level: int) -> void:
	var tier := clampi(level, 0, 2)
	if tier == _tier and _mm != null:
		return
	_tier = tier
	var row: Array = TIERS[tier]
	_cap = int(row[0])
	_npts = int(row[1])
	if _mmi == null:
		_mmi = MultiMeshInstance3D.new()
		_mmi.name = "Draw"
		_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mmi.custom_aabb = FAR_AABB
		add_child(_mmi)
		_img = Image.create_empty(TEX_W, 8, false, Image.FORMAT_RGBAF)
		_tex = ImageTexture.create_from_image(_img)
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_mat.set_shader_parameter("path_tex", _tex)
		_mmi.material_override = _mat
	_mat.set_shader_parameter("n_pts", _npts)
	_mat.set_shader_parameter("glow", float(row[4]))
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.instance_count = _cap
	_mm.mesh = _tube_mesh(int(row[2]) + int(row[5]), int(row[3]))
	_mat.set_shader_parameter("body_split", float(row[2]) / float(int(row[2]) + int(row[5])))
	for i in _cap:
		_mm.set_instance_transform(i, Transform3D.IDENTITY)
	_mm.visible_instance_count = 0
	_mmi.multimesh = _mm
	_buf.resize(TEX_W * 8 * 4)
	_buf.fill(0.0)
	while tendrils.size() > _cap:
		_retire_one()
	_sync_visible()


## A tube of (rings + 1) x (sides + 1) vertices: UV.x = angle 0..1, UV.y = along 0..1 (the vertex shader places every vertex on the spline; the positions here are dummies).
static func _tube_mesh(rings: int, sides: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for r in rings + 1:
		var u := float(r) / float(rings)
		for s in sides + 1:
			var a := float(s) / float(sides)
			verts.append(Vector3(cos(a * TAU), sin(a * TAU), u))
			norms.append(Vector3(cos(a * TAU), sin(a * TAU), 0.0))
			uvs.append(Vector2(a, u))
	for r in rings:
		for s in sides:
			var i0 := r * (sides + 1) + s
			var i1 := i0 + 1
			var i2 := i0 + sides + 1
			var i3 := i2 + 1
			idx.append_array(PackedInt32Array([i0, i2, i1, i1, i2, i3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _sync_visible() -> void:
	if _mm != null:
		_mm.visible_instance_count = tendrils.size()
	if _mmi != null:
		_mmi.visible = not tendrils.is_empty()
	if tendrils.is_empty():
		set_process(false)


func _process(delta: float) -> void:
	if tendrils.is_empty():
		set_process(false)
		return
	var dt := minf(delta, 0.1)
	if Game.state != &"paused":
		_step(dt)
	_upload()


func _step(dt: float) -> void:
	var i := tendrils.size() - 1
	_puff_t -= dt
	var puff := _puff_t <= 0.0
	if puff:
		_puff_t = 0.035
	while i >= 0:
		var t := tendrils[i]
		var was := t.state
		t.step(dt)
		if t.state == SnakeTendril.State.TRAVEL and puff:
			_trail_puff(t)
		elif was == SnakeTendril.State.TRAVEL and t.state == SnakeTendril.State.ATTACHED:
			_arrive_burst(t)
		if t.state == SnakeTendril.State.DONE:
			tendrils.remove_at(i)
		i -= 1
	_sync_visible()


func _trail_puff(t: SnakeTendril) -> void:
	if Game.quality == 0 and (Engine.get_process_frames() & 1) == 1:
		return
	FX.burst(t.head_pos, t.color.lerp(Color.WHITE, 0.35), 1, 1.6, 0.32, 0.0, 0.55)


func _arrive_burst(t: SnakeTendril) -> void:
	FX.burst(t.head_pos, t.color.lerp(Color.WHITE, 0.4), 7 if Game.quality > 0 else 4, 4.5, 0.4, 3.0, 0.8)


func _upload() -> void:
	var n := mini(tendrils.size(), _cap)
	drawn = n
	if n == 0:
		return
	for r in n:
		var t := tendrils[r]
		_write_row(t, r)
		var c := t.color
		_mm.set_instance_color(r, Color(c.r, c.g, c.b, t.head_scale))
		_mm.set_instance_custom_data(r, Color(float(r), t.thickness, clampf(t.tension, 0.0, 1.0), maxf(t.length(), 0.05)))
	_img.set_data(TEX_W, 8, false, Image.FORMAT_RGBAF, _buf.to_byte_array())
	_tex.update(_img)


## The control points of one tendril: hand -> head along a line, slither (two phase-shifted waves), slack sag.
func _write_row(t: SnakeTendril, row: int) -> void:
	var o := t.origin_pos
	var d := t.head_pos - o
	var len := d.length()
	var dir := d / len if len > 0.001 else Vector3.FORWARD
	var l1 := dir.cross(Vector3.UP)
	if l1.length() < 0.1:
		l1 = dir.cross(Vector3.RIGHT)
	l1 = l1.normalized()
	var l2 := dir.cross(l1)
	var tm := t.age * 13.0 + t._seed
	var amp := t.wriggle * clampf(len / 7.0, 0.3, 1.0)
	match t.state:
		SnakeTendril.State.TRAVEL:
			amp *= 1.0
		SnakeTendril.State.ATTACHED:
			amp = amp * exp(-t.attached_age * 5.0) + (0.05 + 0.14 * (1.0 - t.tension)) * clampf(len / 12.0, 0.35, 1.0)
		SnakeTendril.State.RETRACT:
			amp *= 1.15
	amp *= 1.0 - 0.55 * clampf(t.tension, 0.0, 1.0) * (0.0 if t.state != SnakeTendril.State.ATTACHED else 1.0)
	if t.flutter > 0.0:
		amp += t.flutter * (0.7 + 0.3 * sin(t.age * 5.0 + t._seed))
	var waves := clampf(len / 2.4, 1.2, float(_npts - 1) / 5.0)
	var sag_k := (1.0 - clampf(t.tension, 0.0, 1.0)) * t.slack_sag * minf(len * 0.09, 1.8)
	var base := row * TEX_W * 4
	var last := float(_npts - 1)
	for i in _npts:
		var u := float(i) / last
		var env := pow(sin(PI * u), 0.85)
		var ph := u * waves * TAU - tm
		var off := l1 * (sin(ph) * amp * env) + l2 * (cos(ph * 0.7 + 1.3) * amp * 0.42 * env)
		var sag := Vector3(0.0, -sag_k * 4.0 * u * (1.0 - u), 0.0)
		var p := o + d * u + off + sag + t.bow * (4.0 * u * (1.0 - u))
		var k := base + i * 4
		_buf[k] = p.x
		_buf[k + 1] = p.y
		_buf[k + 2] = p.z
		_buf[k + 3] = 1.0
