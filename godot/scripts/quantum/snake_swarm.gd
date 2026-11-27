class_name SnakeSwarm
extends Node3D
## THE POOL AND THE RENDERER OF THE COMBAT SNAKES (wave 115, combat side): the swarm of a SWARM BOMB, the coils that wrap an enemy, the three snakes of SNAKE SHIELD, the guards, the net, the trap,
## the thrown bomb itself (a coiled ball), the seeker, the burrower, the rising cobra of the STORM COBRA, the rings of the MEGA PYTHON. They are the same creature as the hero's tendrils (the same
## shader, assets/shaders/snake_tendril.gdshader: a dark scaled hide with lit seams, an energy pulse and a viper head), but they are free-moving bodies, not ropes from the hand.
## ONE MultiMesh draw call for all of them while any lives (hidden otherwise): every body writes its control points into one RGBA32F data texture (a row per body) and the vertex shader builds
## the tube on a spline. Caps by tier (Game.quality): LOW 16 bodies x 14 points, MED 28 x 20, HIGH 44 x 26 (a body is 216 / 480 / 672 triangles); a full pool retires the oldest body of the
## lowest priority (decoration before a hero's own shield). The simulation runs in every state but a pause.
##
## USAGE   var b := swarm.spawn(&"crawl", pos, {"color": c, "len": 1.6, "target": enemy, "speed": 13.0, "on_arrive": cb})   -> SnakeSwarm.Body (null when the pool is full of better bodies)
## SHAPES (b.shape)  crawl (head at pos, the body trails behind along heading), coil (a helix round `anchor` + offset: height y0..y1, radius, turns, spin), orbit (an arc of a circle round `anchor`),
##   ball (a tight curled ball at pos: the thrown bomb), ring (a circle on the ground: the net, the trap), rise (a vertical S, the cobra), free (the owner writes b.pts itself)
## MODES (b.mode)    hunt (home on `target` or `target_pos` and call `on_arrive(b)`; true from it = coil round the target), idle (the owner moves it), none
## Every body can carry `tick` (Callable(b, dt) -> bool: false ends the body), `life` (seconds, < 0 = until the owner kills it) and `user` (free data).

const SHADER := preload("res://assets/shaders/snake_tendril.gdshader")
const TEX_W := 32
const ROWS := 48
## per tier: [max bodies, control points, body rings, sides, head rings]
const TIERS: Array = [[16, 14, 12, 6, 6], [28, 20, 20, 8, 10], [44, 26, 30, 8, 12]]
const FAR_AABB := AABB(Vector3(-6000.0, -600.0, -6000.0), Vector3(12000.0, 3000.0, 12000.0))
const FADE := 0.35
const NEAR_FROM := 1.3                             ## a snake closer than this to the camera is drawn as a thread (thickness x NEAR_MIN) ...
const NEAR_TO := 4.4                               ## ... and at full thickness from this far: a shield or a guard that passes between the shoulder camera and the hero never becomes a wall
const NEAR_MIN := 0.1
const GLOW := 0.6                                ## the shader's brightness for the combat snakes: the colour of the power stays a colour instead of washing out to white

static var current: SnakeSwarm
static var strike_on := OS.get_environment("W128_OLD") != "1"     ## w128-anim: a crawling snake rears back and strikes as it reaches its target (false = the old straight slide)


class Body extends RefCounted:
	var shape: StringName = &"crawl"
	var mode: StringName = &"none"
	var pos := Vector3.ZERO                     ## the head
	var heading := Vector3.FORWARD
	var color := Color(0.16, 0.88, 1.0)
	var thick := 0.07
	var len := 1.6
	var head := 1.0
	var amp := 0.16                             ## slither amplitude (metres)
	var rate := 1.0                             ## slither speed factor
	var lift := 0.0                             ## the head rises (a striking snake)
	var tension := 0.6
	var pattern := 0                            ## wave 119: the skin of a snake species (SnakeBlasts.ROWS): 0 plain, 1 bands, 2 diamonds, 3 zigzag, 4 spots, 5 stripes, 6 spiral
	var age := 0.0
	var life := 4.0
	var seed := 0.0
	var prio := 1
	var speed := 12.0
	var reach := 1.0
	var steer := 6.0
	var target: Node3D
	var target_pos := Vector3.INF
	var anchor: Node3D
	var anchor_pos := Vector3.INF               ## a fixed centre when there is no anchor node
	var offset := Vector3.ZERO
	var radius := 0.5
	var y0 := 0.1
	var y1 := 1.6
	var turns := 2.5
	var spin := 3.0
	var phase := 0.0
	var span := 2.2
	var height := 3.0
	var rise_t := 0.6
	var fade_k := 1.0
	var stick := false                          ## the body keeps its row while the owner holds it (not retired for a better one)
	var arrived := false
	var tick: Callable
	var on_arrive: Callable
	var on_done: Callable
	var user := {}
	var pts := PackedVector3Array()
	var dead := false
	var _gy := 0.0
	var _gy_t := 0.0

	func kill() -> void:
		dead = true


var bodies: Array[Body] = []
var spawned := 0                                ## counters (tests wait on these, not on frames)
var retired := 0
var arrived_n := 0
var drawn := 0                                  ## bodies written to the GPU last frame
var peak := 0                                   ## the most bodies alive at once since the last reset_stats()

var _tier := -1
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _img: Image
var _tex: ImageTexture
var _buf := PackedFloat32Array()
var _cap := 16
var _npts := 14
var _rq := PhysicsRayQueryParameters3D.new()
var _rng := RandomNumberGenerator.new()


## The swarm of the player (created on first use under the player, top_level). Null without a player in the tree.
static func get_swarm(host: Node = null) -> SnakeSwarm:
	if is_instance_valid(current) and current.is_inside_tree():
		return current
	var parent: Node = host
	if parent == null and is_instance_valid(Game.player):
		parent = Game.player
	if parent == null or not parent.is_inside_tree():
		return null
	var s := SnakeSwarm.new()
	s.name = "SnakeSwarm"
	parent.add_child(s)
	return s


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	current = self
	process_priority = 111
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_rq.collision_mask = 1
	Game.new_game.connect(clear)
	Game.respawn.connect(clear)
	Game.quality_changed.connect(func(_l: int) -> void: _build(Game.quality))
	_build(Game.quality)
	set_process(false)


func _exit_tree() -> void:
	if current == self:
		current = null


func count() -> int:
	return bodies.size()


func cap() -> int:
	return _cap


func points_per_body() -> int:
	return _npts


func reset_stats() -> void:
	spawned = 0
	retired = 0
	arrived_n = 0
	peak = 0


## Every body ends at once (a new game, a respawn).
func clear() -> void:
	for b in bodies:
		b.dead = true
		if b.on_done.is_valid():
			b.on_done.call(b)
	bodies.clear()
	_sync_visible()


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
		_img = Image.create_empty(TEX_W, ROWS, false, Image.FORMAT_RGBAF)
		_tex = ImageTexture.create_from_image(_img)
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_mat.set_shader_parameter("path_tex", _tex)
		_mmi.material_override = _mat
	_mat.set_shader_parameter("n_pts", _npts)
	_mat.set_shader_parameter("glow", float(OS.get_environment("SNAKE_GLOW")) if OS.get_environment("SNAKE_GLOW") != "" else GLOW)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.instance_count = _cap
	_mm.mesh = SnakeTendrilPool._tube_mesh(int(row[2]) + int(row[4]), int(row[3]))
	_mat.set_shader_parameter("body_split", float(row[2]) / float(int(row[2]) + int(row[4])))
	for i in _cap:
		_mm.set_instance_transform(i, Transform3D.IDENTITY)
	_mm.visible_instance_count = 0
	_mmi.multimesh = _mm
	_buf.resize(TEX_W * ROWS * 4)
	_buf.fill(0.0)
	while bodies.size() > _cap:
		_retire_one(0)
	_sync_visible()


## Adds a body. Returns it, or null when every row holds a body of at least this priority.
func spawn(shape: StringName, pos: Vector3, opts: Dictionary = {}) -> Body:
	var b := Body.new()
	b.shape = shape
	b.pos = pos
	b.color = opts.get("color", b.color)
	b.thick = float(opts.get("thick", b.thick))
	b.len = float(opts.get("len", b.len))
	b.head = float(opts.get("head", b.head))
	b.amp = float(opts.get("amp", b.amp))
	b.rate = float(opts.get("rate", b.rate))
	b.lift = float(opts.get("lift", b.lift))
	b.tension = float(opts.get("tension", b.tension))
	b.pattern = int(opts.get("pattern", 0))
	b.life = float(opts.get("life", b.life))
	b.prio = int(opts.get("prio", b.prio))
	b.speed = float(opts.get("speed", b.speed))
	b.reach = float(opts.get("reach", b.reach))
	b.steer = float(opts.get("steer", b.steer))
	b.target = opts.get("target", null) as Node3D
	b.target_pos = opts.get("target_pos", Vector3.INF)
	b.anchor = opts.get("anchor", null) as Node3D
	b.anchor_pos = opts.get("anchor_pos", Vector3.INF)
	b.offset = opts.get("offset", Vector3.ZERO)
	b.radius = float(opts.get("radius", b.radius))
	b.y0 = float(opts.get("y0", b.y0))
	b.y1 = float(opts.get("y1", b.y1))
	b.turns = float(opts.get("turns", b.turns))
	b.spin = float(opts.get("spin", b.spin))
	b.span = float(opts.get("span", b.span))
	b.height = float(opts.get("height", b.height))
	b.rise_t = float(opts.get("rise_t", b.rise_t))
	b.stick = bool(opts.get("stick", false))
	b.tick = opts.get("tick", Callable())
	b.on_arrive = opts.get("on_arrive", Callable())
	b.on_done = opts.get("on_done", Callable())
	b.mode = opts.get("mode", &"none")
	b.user = opts.get("user", {})
	b.heading = opts.get("heading", Vector3.FORWARD)
	if b.heading.length() < 0.01:
		b.heading = Vector3.FORWARD
	b.heading = b.heading.normalized()
	b.seed = _rng.randf() * 100.0
	b.phase = float(opts.get("phase", _rng.randf() * TAU))
	b._gy = pos.y
	b.pts.resize(_npts)
	if bodies.size() >= _cap:
		if not _retire_one(b.prio):
			return null
	bodies.append(b)
	spawned += 1
	peak = maxi(peak, bodies.size())
	_shape(b)
	set_process(true)
	_sync_visible()
	return b


func _retire_one(for_prio: int) -> bool:
	var pick := -1
	var best := 99
	var oldest := -1.0
	for i in bodies.size():
		var b := bodies[i]
		if b.stick and for_prio <= 3:
			continue
		if b.prio > for_prio:
			continue
		if b.prio < best or (b.prio == best and b.age > oldest):
			best = b.prio
			oldest = b.age
			pick = i
	if pick < 0:
		return false
	var v := bodies[pick]
	bodies.remove_at(pick)
	v.dead = true
	if v.on_done.is_valid():
		v.on_done.call(v)
	retired += 1
	return true


func _sync_visible() -> void:
	if _mm != null:
		_mm.visible_instance_count = mini(bodies.size(), _cap)
	if _mmi != null:
		_mmi.visible = not bodies.is_empty()
	if bodies.is_empty():
		set_process(false)


func _process(delta: float) -> void:
	if bodies.is_empty():
		set_process(false)
		return
	var dt := minf(delta, 0.1)
	if Game.state != &"paused":
		_step(dt)
	_upload()


func _step(dt: float) -> void:
	var i := bodies.size() - 1
	while i >= 0:
		var b := bodies[i]
		if not b.dead:
			_update(b, dt)
		if b.dead:
			bodies.remove_at(i)
			if b.on_done.is_valid():
				b.on_done.call(b)
		else:
			_shape(b)
		i -= 1
	_sync_visible()


func _update(b: Body, dt: float) -> void:
	b.age += dt
	if b.life >= 0.0 and b.age >= b.life:
		b.dead = true
		return
	b.fade_k = 1.0 if b.life < 0.0 else clampf((b.life - b.age) / FADE, 0.0, 1.0)
	if b.tick.is_valid():
		var keep: Variant = b.tick.call(b, dt)
		if keep is bool and not keep:
			b.dead = true
			return
	if b.mode == &"hunt":
		_hunt(b, dt)


## Home on the target at `speed`, hugging the ground; the arrival goes to on_arrive (true = coil round the target for the rest of its life).
func _hunt(b: Body, dt: float) -> void:
	var goal := b.target_pos
	if is_instance_valid(b.target) and b.target.is_inside_tree():
		var c: Vector3 = b.target.call(&"center") if b.target.has_method(&"center") else b.target.global_position + Vector3(0.0, 0.9, 0.0)
		goal = Vector3(c.x, b.target.global_position.y + 0.15, c.z)
		if bool(b.target.get(&"dead")):
			b.target = null
			goal = Vector3.INF
	if goal == Vector3.INF:
		b.mode = &"none"
		return
	var rest := crawl_to(b, goal, dt, b.speed)
	if rest <= b.reach:
		b.mode = &"none"
		b.arrived = true
		arrived_n += 1
		var coil := false
		if b.on_arrive.is_valid():
			var r: Variant = b.on_arrive.call(b)
			coil = r is bool and r
		if coil and is_instance_valid(b.target):
			b.shape = &"coil"
			b.anchor = b.target
			b.mode = &"none"
			b.radius = 0.5
			b.y0 = 0.1
			b.y1 = 1.55
			b.turns = 2.4
			b.spin = 2.6
		else:
			b.dead = true


## One step of a crawling body toward `goal` on the ground plane (the head turns at `steer`, follows the ground, rises as it strikes). Returns the flat distance that is left.
func crawl_to(b: Body, goal: Vector3, dt: float, speed: float) -> float:
	var to := goal - b.pos
	var flat := Vector3(to.x, 0.0, to.z)
	var d := flat.length()
	if d <= 0.05:
		return d
	var want := flat / d
	b.heading = b.heading.slerp(want, clampf(b.steer * dt, 0.0, 1.0)) if b.heading.length() > 0.01 else want
	if b.heading.length() < 0.01:
		b.heading = want
	b.heading = b.heading.normalized()
	var step := minf(speed * dt, d)
	b.pos += Vector3(b.heading.x, 0.0, b.heading.z).normalized() * step
	b._gy_t -= dt
	if b._gy_t <= 0.0:
		b._gy_t = 0.1 + _rng.randf() * 0.05
		b._gy = ground_y(b.pos, goal.y)
	b.pos.y = lerpf(b.pos.y, b._gy + b.thick * 1.3, clampf(dt * 14.0, 0.0, 1.0))
	b.lift = lerpf(b.lift, clampf(1.0 - d / 4.0, 0.0, 1.0) * 0.55, clampf(dt * 8.0, 0.0, 1.0))
	return maxf(d - step, 0.0)


## The ground under `p` (a ray down; `fallback` when nothing is hit).
func ground_y(p: Vector3, fallback := 0.0) -> float:
	var space := get_world_3d().direct_space_state
	_rq.from = Vector3(p.x, p.y + 2.2, p.z)
	_rq.to = Vector3(p.x, p.y - 6.0, p.z)
	var res := space.intersect_ray(_rq)
	return float((res["position"] as Vector3).y) if not res.is_empty() else fallback


func _center(b: Body) -> Vector3:
	if is_instance_valid(b.anchor) and b.anchor.is_inside_tree():
		return b.anchor.global_position + b.offset
	if b.anchor_pos != Vector3.INF:
		return b.anchor_pos + b.offset
	return b.pos + b.offset


## Fills b.pts (tail -> head) for the shape of the body.
func _shape(b: Body) -> void:
	var n := _npts
	var last := float(n - 1)
	var t := b.age * b.rate + b.seed
	if b.pts.size() != n:
		b.pts.resize(n)
	match b.shape:
		&"crawl":
			var h := b.heading
			var side := h.cross(Vector3.UP)
			if side.length() < 0.1:
				side = Vector3.RIGHT
			side = side.normalized()
			var l := b.len * b.fade_k
			var sk := clampf(b.lift / 0.4, 0.0, 1.0) if strike_on else 0.0       # w128-anim: the STRIKE as it closes in: the neck draws back into an S (coil), then the head lunges
			var coil := sin(minf(sk / 0.6, 1.0) * PI * 0.5) * (1.0 - smoothf(0.6, 0.85, sk))
			var lunge := smoothf(0.6, 0.85, sk)
			for i in n:
				var u := float(i) / last
				var s := (1.0 - u) * l
				var wave := sin(t * 9.0 - s * 4.4) * b.amp * minf(1.0, 0.2 + u * 0.9) * clampf(l / 1.2, 0.5, 1.2)
				var rise := b.lift * smoothf(0.5, 1.0, u) * l * 0.5
				var pt := b.pos - h * s + side * wave + Vector3(0.0, rise + absf(sin(t * 9.0 - s * 4.4 + 1.4)) * b.thick * 0.6, 0.0)
				if sk > 0.0:
					var nw := smoothf(0.5, 1.0, u)                                       # the neck and the head (the front half)
					pt += -h * (0.42 * coil - 0.22 * lunge) * l * 0.5 * nw + side * sin((u - 0.5) * 12.0) * 0.16 * coil * nw * l * 0.6
				b.pts[i] = pt
		&"coil":
			var c := _center(b)
			var ramp := clampf(b.age / 0.35, 0.0, 1.0)
			var rr := b.radius * (1.0 + 0.8 * (1.0 - ramp))
			for i in n:
				var u := float(i) / last
				var a := b.phase + u * b.turns * TAU + t * b.spin
				var r := rr * (1.0 - 0.3 * u) * (1.0 + 0.06 * sin(u * 20.0 - t * 6.0))
				b.pts[i] = c + Vector3(cos(a) * r, lerpf(b.y0, b.y1, u) * ramp + b.y0 * (1.0 - ramp), sin(a) * r)
			b.pos = b.pts[n - 1]
		&"orbit":
			var c2 := _center(b)
			var a0 := b.phase + t * b.spin
			for i in n:
				var u := float(i) / last
				var a := a0 - (1.0 - u) * b.span
				var hgt := b.y0 + (b.y1 - b.y0) * (0.5 + 0.5 * sin(a * 1.0 + b.phase * 2.0)) + 0.14 * sin(u * 9.0 - t * 5.0)
				b.pts[i] = c2 + Vector3(cos(a) * b.radius, hgt, sin(a) * b.radius)
			b.pos = b.pts[n - 1]
		&"ball":
			var c3 := b.pos
			var rad := b.radius * (0.9 + 0.1 * sin(t * 14.0))
			for i in n:
				var u := float(i) / last
				var k := u * TAU * 3.0 + t * 11.0
				var s2 := sin(u * PI)
				b.pts[i] = c3 + Vector3(s2 * cos(k), cos(u * PI) * 0.9, s2 * sin(k)) * rad
		&"ring":
			var c4 := b.pos
			var grow := clampf(b.age / maxf(b.rise_t, 0.05), 0.0, 1.0)
			grow = 1.0 - (1.0 - grow) * (1.0 - grow)
			for i in n:
				var u := float(i) / last
				var a := b.phase + u * TAU * 0.96 + t * b.spin
				var r2 := b.radius * grow * (1.0 + 0.05 * sin(u * 30.0 + t * 4.0))
				b.pts[i] = c4 + Vector3(cos(a) * r2, 0.06 + b.thick + 0.05 * sin(u * 12.0 - t * 6.0), sin(a) * r2)
		&"rise":
			var base := b.pos
			var rise_k := clampf(b.age / maxf(b.rise_t, 0.05), 0.0, 1.0)
			rise_k = 1.0 - (1.0 - rise_k) * (1.0 - rise_k)
			var hh := b.height * rise_k
			var side2 := b.heading.cross(Vector3.UP)
			if side2.length() < 0.1:
				side2 = Vector3.RIGHT
			side2 = side2.normalized()
			for i in n:
				var u := float(i) / last
				var sway := sin(u * 5.0 - t * 2.2) * 0.22 * u
				var fwd := pow(u, 3.0) * hh * 0.28
				b.pts[i] = base + Vector3(0.0, u * hh, 0.0) + side2 * sway + b.heading * fwd
		&"free":
			pass
	if b.shape == &"crawl":
		pass


## smoothstep helper (GDScript's own `smoothstep` takes (from, to, x)).
static func smoothf(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)


func _upload() -> void:
	var n := mini(bodies.size(), _cap)
	drawn = n
	if n == 0:
		return
	var cam := Game.camera
	var cp: Vector3 = cam.global_position if is_instance_valid(cam) else Vector3.INF
	for r in n:
		var b := bodies[r]
		var length := _write_row(b, r)
		var c := b.color
		var near_k := 1.0
		if cp != Vector3.INF:                                                  # the point of the body nearest to the lens decides (every third of the points is enough)
			var dmin := 1.0e12
			for i in range(0, _npts, 3):
				dmin = minf(dmin, cp.distance_squared_to(b.pts[i]))
			near_k = clampf((sqrt(dmin) - NEAR_FROM) / (NEAR_TO - NEAR_FROM), NEAR_MIN, 1.0)
		_mm.set_instance_color(r, Color(c.r, c.g, c.b, b.head * b.fade_k * lerpf(0.4, 1.0, near_k)))
		_mm.set_instance_custom_data(r, Color(float(r), b.thick * (0.35 + 0.65 * b.fade_k) * near_k, clampf(b.tension, 0.0, 1.0) + 2.0 * float(b.pattern), maxf(length * (0.4 + 0.6 * b.fade_k), 0.05)))
	_img.set_data(TEX_W, ROWS, false, Image.FORMAT_RGBAF, _buf.to_byte_array())
	_tex.update(_img)


## Writes the control points of one body into the data texture row; returns the length of the polyline.
func _write_row(b: Body, row: int) -> float:
	var base := row * TEX_W * 4
	var total := 0.0
	var prev := Vector3.INF
	for i in _npts:
		var p: Vector3 = b.pts[i]
		if prev != Vector3.INF:
			total += prev.distance_to(p)
		prev = p
		var k := base + i * 4
		_buf[k] = p.x
		_buf[k + 1] = p.y
		_buf[k + 2] = p.z
		_buf[k + 3] = 1.0
	return total
