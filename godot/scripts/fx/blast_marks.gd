class_name BlastMarks
extends Node3D
## What a blast, a dying enemy, a wrecked car and a bullet in a puddle leave behind: coloured alien fluid that pools on the street and runs down walls, soot scorch,
## cracks and pockmarks in facades, cracked glass, puddle ripples. ONE MultiMesh ring of quads with one procedural shader (assets/shaders/fx_marks.gdshader): a draw call only
## while at least one mark is alive, never a new node and never a new draw however many blasts happen. When the ring is full the oldest mark of its pool is recycled.
## Pools (one ring, one draw): the first RIPPLE_MAX slots are short-lived puddle ripples, the rest long marks (liquid 30-60 s, scorch 45 s, cracks 90 s).
## Caps by tier (Game.quality): LOW 4 + 24, MED 6 + 44, HIGH 8 + 72 live marks (`cap_long`, `cap_ripples`). Fresh fluid glows (dimmed by UiSettings.s_reduce_flash).
## Falling glass and chunks of a hit facade come from two pooled emitters (`facade_shower`): chunks on every tier, glass from MED up.
## Called from FX.blast_marks (Game.explode), Drone death, Vehicle (wreck, leaks) and ImpactSparks (puddle splashes). FX owns the node (`FX.marks`).

const SHADER := preload("res://assets/shaders/fx_marks.gdshader")
const STREAK_SHADER := preload("res://assets/shaders/fx_streak.gdshader")
const MAX := 120
const RIPPLE_MAX := 8
const LONG_MAX := 96 - RIPPLE_MAX
const STRUCT_BASE := 96               ## the last 24 slots are the STRUCTURE pool (wave 113: broken windows, wall breaches, craters, spall scars of scripts/combat/structure_damage.gd), capped by tier on its own
const REBASE_AT := 40.0               ## seconds of the shader clock before every birth time is shifted back (half-float custom data loses precision on a large clock)
const LIFE_LIQUID := Vector2(30.0, 60.0)
const LIFE_SCORCH := 45.0
const LIFE_CRACK := 90.0
const LIFE_RIPPLE := 0.9
const K_SPLAT := 0
const K_RIPPLE := 1
const K_SCORCH := 2
const K_CRACK := 3
const K_GLASS := 4
const K_WALL := 5
const K_OIL := 6
const K_WINDOW := 7                   ## a window whose glass is out
const K_BREACH := 8                   ## a hole in a wall
const K_CRATER := 9                   ## a pit in the street
const K_CHIP := 10                    ## a scar of pale fresh concrete
const LIFE_STRUCT := 150.0
const WALL_RAYS := [2, 4, 6]          ## horizontal rays per blast by tier
const SATELLITES := [1, 2, 3]         ## extra splats around the centre by tier
const SHARDS := 28
const CHUNKS := 14

var _mm: MultiMesh
var _node: MultiMeshInstance3D
var _mat: ShaderMaterial
var _born := PackedFloat32Array()     ## birth (blast clock) per slot; after a rebase it can be negative
var _on := PackedByteArray()          ## 1 = the slot holds a live mark
var _life := PackedFloat32Array()
var _kind := PackedInt32Array()
var _seed := PackedFloat32Array()
var _next_long := RIPPLE_MAX
var _next_ripple := 0
var _next_struct := 0
var _live := 0
var _clock := 0.0
var _check := 0.0
var _hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -4000.0, 0.0))
var _rng := RandomNumberGenerator.new()
var shards: CPUParticles3D
var chunks: CPUParticles3D
var _shard_left := 0.0
var _chunk_left := 0.0
var total_added := 0                  ## marks placed since the start (tests)


static func cap_long(tier: int) -> int:
	return [24, 44, 72][clampi(tier, 0, 2)]


static func cap_ripples(tier: int) -> int:
	return [4, 6, 8][clampi(tier, 0, 2)]


## The structure pool (windows, breaches, craters, spall scars): LOW 8, MED 16, HIGH 24 live marks, the oldest is recycled.
static func cap_struct(tier: int) -> int:
	return [8, 16, 24][clampi(tier, 0, 2)]


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.randomize()
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	quad.material = _mat
	_mm.mesh = quad
	_mm.instance_count = MAX
	_born.resize(MAX)
	_on.resize(MAX)
	_life.resize(MAX)
	_seed.resize(MAX)
	_kind.resize(MAX)
	for i in MAX:
		_mm.set_instance_transform(i, _hidden)
	_node = MultiMeshInstance3D.new()
	_node.name = "Marks"
	_node.multimesh = _mm
	_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_node.custom_aabb = AABB(Vector3(-1500.0, -50.0, -1500.0), Vector3(3000.0, 400.0, 3000.0))
	_node.visible = false                       # no draw call while the ring is empty
	add_child(_node)
	_build_shower()
	set_process(false)


# --- placing marks ------------------------------------------------------------------------------------------------------------

## Basis of a quad lying on a surface: ground quads get a random spin, wall quads keep +Y up so drips run down.
func _surface_basis(n: Vector3, size: float, spin := true) -> Basis:
	var up := Vector3.UP
	var t: Vector3
	if absf(n.y) > 0.8:
		t = Vector3.RIGHT.rotated(Vector3.UP, _rng.randf() * TAU) if spin else Vector3.RIGHT
	else:
		t = up.cross(n).normalized()
	var b := n.cross(t).normalized()
	return Basis(t, b, n) * Basis.from_scale(Vector3(size, size, size))


func _put(i: int, xf: Transform3D, color: Color, kind: int, life: float, seed_v: float) -> void:
	if _on[i] == 0:
		_live += 1
	_on[i] = 1
	_born[i] = _clock
	_life[i] = life
	_kind[i] = kind
	_seed[i] = seed_v
	_mm.set_instance_transform(i, xf)
	_mm.set_instance_color(i, color)
	_mm.set_instance_custom_data(i, Color(_clock, seed_v, life, float(kind)))
	total_added += 1
	_mat.set_shader_parameter(&"dim", 0.35 if UiSettings.s_reduce_flash else 1.0)
	_node.visible = true
	set_process(true)


func _slot_long() -> int:
	var cap := cap_long(Game.quality)
	if _next_long < RIPPLE_MAX or _next_long >= RIPPLE_MAX + cap:
		_next_long = RIPPLE_MAX
	var i := _next_long
	_next_long += 1
	return i


func _slot_struct() -> int:
	var cap := cap_struct(Game.quality)
	if _next_struct >= cap:
		_next_struct = 0
	var i := STRUCT_BASE + _next_struct
	_next_struct += 1
	return i


func _slot_ripple() -> int:
	var cap := cap_ripples(Game.quality)
	if _next_ripple >= cap:
		_next_ripple = 0
	var i := _next_ripple
	_next_ripple += 1
	return i


## Liquid on a surface: `size` is the diameter in metres. `fluid` is an element id (&"toxic") or a colour; the life is 30-60 s unless given. Ground and wall splats share the call:
## a surface normal with |y| < 0.6 is a wall (drips run down it).
func splat(pos: Vector3, normal: Vector3, size: float, fluid: Variant, life := -1.0, glow := -1.0) -> void:
	if _mm == null:
		return
	var col: Color
	var gl: float
	var el := BlastElements.FIRE
	if fluid is Color:
		col = fluid
		el = BlastElements.of_color(col)
		gl = BlastElements.data(el)["glow"]
	else:
		el = fluid as StringName
		col = BlastElements.color(el, "fluid")
		gl = BlastElements.data(el)["glow"]
	if glow >= 0.0:
		gl = glow
	var n := normal.normalized() if normal != Vector3.ZERO else Vector3.UP
	var wall := absf(n.y) < 0.6
	var kind := K_WALL if wall else (K_OIL if gl <= 0.01 else K_SPLAT)
	var lf := life if life > 0.0 else _rng.randf_range(LIFE_LIQUID.x, LIFE_LIQUID.y)
	var s := _rng.randf()
	_put(_slot_long(), Transform3D(_surface_basis(n, size * (1.25 if wall else 1.0)), pos + n * 0.01), Color(col.r, col.g, col.b, gl), kind, lf, s)


## A dark oil puddle with a rainbow film (a leaking or wrecked car).
func oil(pos: Vector3, size: float, life := -1.0) -> void:
	if _mm == null:
		return
	var lf := life if life > 0.0 else _rng.randf_range(LIFE_LIQUID.x, LIFE_LIQUID.y)
	_put(_slot_long(), Transform3D(_surface_basis(Vector3.UP, size), pos + Vector3(0.0, 0.01, 0.0)), Color(0.02, 0.02, 0.025, 0.0), K_OIL, lf, _rng.randf())


## Soot scorch with an ember rim that cools in three seconds. `glow` is the colour of the rim.
func scorch(pos: Vector3, normal: Vector3, size: float, glow: Color, life := LIFE_SCORCH) -> void:
	if _mm == null:
		return
	var n := normal.normalized() if normal != Vector3.ZERO else Vector3.UP
	_put(_slot_long(), Transform3D(_surface_basis(n, size), pos + n * 0.008), Color(glow.r, glow.g, glow.b, 0.5), K_SCORCH, life, _rng.randf())


## Radial cracks and a cluster of pockmarks in concrete, or a star of cracked glass.
func cracks(pos: Vector3, normal: Vector3, size: float, glass := false, life := LIFE_CRACK) -> void:
	if _mm == null:
		return
	var n := normal.normalized() if normal != Vector3.ZERO else Vector3.UP
	_put(_slot_long(), Transform3D(_surface_basis(n, size, true), pos + n * 0.014), Color(0.8, 0.95, 1.0, 0.0), K_GLASS if glass else K_CRACK, life, _rng.randf())


## A puddle ripple: two rings that spread over 0.9 s.
func ripple(pos: Vector3, size := 0.9) -> void:
	if _mm == null:
		return
	_put(_slot_ripple(), Transform3D(_surface_basis(Vector3.UP, size, false), pos + Vector3(0.0, 0.01, 0.0)), Color(0.6, 0.8, 1.0, 0.0), K_RIPPLE, LIFE_RIPPLE, _rng.randf())


# --- structure damage marks (wave 113, scripts/combat/structure_damage.gd) ---------------------------------------------------------------

## Basis of a w x h rectangle lying on a wall (+Y up, so drips and soot run the right way) or on the ground.
func _rect_basis(n: Vector3, w: float, h: float) -> Basis:
	var t: Vector3
	if absf(n.y) > 0.8:
		t = Vector3.RIGHT.rotated(Vector3.UP, _rng.randf() * TAU)
	else:
		t = Vector3.UP.cross(n).normalized()
	var b := n.cross(t).normalized()
	return Basis(t * w, b * h, n)


## A window whose glass is out: `w` x `h` metres on the wall at `pos` (surface normal `n`), `broken` 0..1 how much of the pane is gone, `room` the light of the room behind it.
func window_broken(pos: Vector3, n: Vector3, w := 2.0, h := 1.5, broken := 0.8, room := Color(0.95, 0.72, 0.4), life := LIFE_STRUCT) -> void:
	if _mm == null:
		return
	var nn := n.normalized() if n != Vector3.ZERO else Vector3.BACK
	_put(_slot_struct(), Transform3D(_rect_basis(nn, w, h), pos + nn * 0.02), Color(room.r, room.g, room.b, clampf(broken, 0.0, 1.0)), K_WINDOW, life, _rng.randf())
	Dmg.bump(&"window")


## A hole in a wall, `size` metres across: a dark opening, a pale broken rim, a spall scar, soot above.
func breach(pos: Vector3, n: Vector3, size: float, life := LIFE_STRUCT) -> void:
	if _mm == null:
		return
	var nn := n.normalized() if n != Vector3.ZERO else Vector3.BACK
	_put(_slot_struct(), Transform3D(_rect_basis(nn, size, size), pos + nn * 0.024), Color(1.0, 1.0, 1.0, 0.0), K_BREACH, life, _rng.randf())
	Dmg.bump(&"breach")


## A pit in the street: dark, with a lit ridge and rays of thrown earth.
func crater(pos: Vector3, size: float, life := LIFE_STRUCT) -> void:
	if _mm == null:
		return
	_put(_slot_struct(), Transform3D(_rect_basis(Vector3.UP, size, size), pos + Vector3(0.0, 0.016, 0.0)), Color(1.0, 1.0, 1.0, 0.0), K_CRATER, life, _rng.randf())
	Dmg.bump(&"crater")


## Patches of pale fresh concrete where a facade lost chunks.
func chip(pos: Vector3, n: Vector3, size: float, life := LIFE_STRUCT) -> void:
	if _mm == null:
		return
	var nn := n.normalized() if n != Vector3.ZERO else Vector3.UP
	_put(_slot_struct(), Transform3D(_rect_basis(nn, size, size), pos + nn * 0.018), Color(1.0, 1.0, 1.0, 0.0), K_CHIP, life, _rng.randf())
	Dmg.bump(&"chip")


func struct_live() -> int:
	var c := 0
	for i in range(STRUCT_BASE, MAX):
		if _on[i] == 1:
			c += 1
	return c


# --- composed effects ------------------------------------------------------------------------------------------------------------

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var vp := get_viewport()
	if vp == null or vp.world_3d == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = Game.L_WORLD
	q.collide_with_areas = false
	return vp.world_3d.direct_space_state.intersect_ray(q)


## The street point under `pos` (a hit on an upward surface within `reach` m below, else the y = 0 plane when the point is near the ground). Vector3.INF when there is none.
func ground_under(pos: Vector3, reach := 8.0) -> Vector3:
	var hit := _ray(pos + Vector3(0.0, 1.0, 0.0), pos - Vector3(0.0, reach, 0.0))
	if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.6:
		return hit["position"]
	if pos.y < 3.0 and hit.is_empty():
		return Vector3(pos.x, 0.0, pos.z)
	return Vector3.INF


## Everything a blast of `radius` metres leaves: scorch and a pool of the element's fluid on the street, satellite splashes, and on any wall within reach scorch, cracks,
## pockmarks, running fluid and a shower of glass and chunks. A handful of raycasts, no allocations beyond them.
func blast(pos: Vector3, radius: float, element: StringName) -> void:
	if _mm == null or radius < 1.8:
		return
	var tier := clampi(Game.quality, 0, 2)
	var pal := BlastElements.data(element)
	var g := ground_under(pos)
	var size := clampf(radius * 1.5, 1.8, 10.0)
	if g != Vector3.INF:
		scorch(g, Vector3.UP, size * 1.15, pal["ring"])
		if element == BlastElements.FIRE:
			oil(g + Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)) * radius * 0.2, size * 0.5)
		else:
			splat(g, Vector3.UP, size * 0.95, element)
		var n_sat: int = SATELLITES[tier] + (1 if radius >= 6.0 else 0)
		for k in n_sat:
			var ang := _rng.randf() * TAU
			var d := radius * _rng.randf_range(0.7, 1.5)
			var p := g + Vector3(cos(ang), 0.0, sin(ang)) * d
			var gp := ground_under(Vector3(p.x, g.y + 0.5, p.z), 2.0)
			if gp == Vector3.INF:
				continue
			var s := radius * (_rng.randf_range(0.12, 0.24) if element == BlastElements.FIRE else _rng.randf_range(0.28, 0.55))
			if element == BlastElements.FIRE:
				splat(gp, Vector3.UP, s, Color(0.8, 0.2, 0.03), _rng.randf_range(6.0, 10.0), 0.6)       # molten droplets that cool and go dark
			else:
				splat(gp, Vector3.UP, s, element)
	# walls
	var rays: int = WALL_RAYS[tier]
	var reach := radius * 1.4 + 2.0
	var oy := maxf(pos.y, 1.2)
	var base := _rng.randf() * TAU
	var showered := 0
	for k in rays:
		var ang := base + TAU * float(k) / float(rays)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var hit := _ray(Vector3(pos.x, oy, pos.z), Vector3(pos.x, oy, pos.z) + dir * reach)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if absf(n.y) > 0.5:
			continue
		var at: Vector3 = hit["position"]
		var close := 1.0 - clampf(Vector2(at.x - pos.x, at.z - pos.z).length() / reach, 0.0, 1.0)
		scorch(at, n, clampf(radius * 0.9 * (0.5 + close), 1.2, 6.0), pal["ring"])
		cracks(at + n * 0.01, n, clampf(radius * 0.7 * (0.5 + close), 1.0, 5.0), false)
		if element != BlastElements.FIRE and close > 0.35:
			splat(at, n, clampf(radius * 0.55 * close, 0.8, 3.5), element)
		if showered < 2 and close > 0.25:
			showered += 1
			facade_shower(at, n, close * clampf(radius / 6.0, 0.5, 1.4))


# --- falling glass and chunks ------------------------------------------------------------------------------------------------------

func _build_shower() -> void:
	var smat := ShaderMaterial.new()
	smat.shader = STREAK_SHADER
	var shard_mesh := QuadMesh.new()
	shard_mesh.size = Vector2(0.05, 0.34)
	shard_mesh.material = smat
	shards = CPUParticles3D.new()
	shards.one_shot = true
	shards.emitting = false
	shards.visible = false
	shards.explosiveness = 0.9
	shards.local_coords = false
	shards.amount = SHARDS
	shards.mesh = shard_mesh
	shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shards.particle_flag_align_y = true
	shards.spread = 55.0
	shards.lifetime = 1.5
	shards.gravity = Vector3(0.0, -9.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	g.add_point(0.4, Color(0.7, 0.93, 1.0, 0.9))
	g.set_color(g.get_point_count() - 1, Color(0.4, 0.8, 1.0, 0.0))
	shards.color_ramp = g
	add_child(shards)
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.13, 0.17)
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.vertex_color_use_as_albedo = true
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material = cmat
	chunks = CPUParticles3D.new()
	chunks.one_shot = true
	chunks.emitting = false
	chunks.visible = false
	chunks.explosiveness = 0.9
	chunks.local_coords = false
	chunks.amount = CHUNKS
	chunks.mesh = box
	chunks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunks.particle_flag_rotate_y = true
	chunks.angular_velocity_min = -400.0
	chunks.angular_velocity_max = 400.0
	chunks.spread = 50.0
	chunks.lifetime = 1.7
	chunks.gravity = Vector3(0.0, -12.0, 0.0)
	var cg := Gradient.new()
	cg.set_color(0, Color(0.46, 0.44, 0.41, 1.0))
	cg.add_point(0.8, Color(0.3, 0.29, 0.28, 1.0))
	cg.set_color(cg.get_point_count() - 1, Color(0.3, 0.3, 0.3, 0.0))
	chunks.color_ramp = cg
	var shrink := Curve.new()                                          # a chunk that flies at the lens gets small as it falls: no tan paper squares in the frame
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.4, 0.6))
	shrink.add_point(Vector2(1.0, 0.2))
	chunks.scale_amount_curve = shrink
	add_child(chunks)


## Falling glass (MED and HIGH) and chunks of the wall at `pos` (surface normal `n`): `power` 0.3..1.4.
func facade_shower(pos: Vector3, n: Vector3, power := 1.0) -> void:
	if chunks == null:
		return
	var tier := Game.quality
	var out := Vector3(n.x, 0.0, n.z).normalized() if absf(n.y) < 0.9 else Vector3.UP
	var dir := (out + Vector3.UP * 0.25).normalized()
	chunks.global_position = pos + n * 0.15
	chunks.direction = dir
	chunks.initial_velocity_min = 1.0 * power
	chunks.initial_velocity_max = 4.5 * power
	chunks.scale_amount_min = 0.6
	chunks.scale_amount_max = 1.4
	chunks.amount = maxi(6, int(round(CHUNKS * (0.5 if tier == 0 else 1.0))))
	chunks.visible = true
	chunks.restart()
	chunks.emitting = true
	_chunk_left = chunks.lifetime + 0.3
	if tier >= 1:
		shards.global_position = pos + n * 0.2 + Vector3(0.0, 0.6, 0.0)
		shards.direction = dir
		shards.initial_velocity_min = 0.8 * power
		shards.initial_velocity_max = 3.5 * power
		shards.visible = true
		shards.restart()
		shards.emitting = true
		_shard_left = shards.lifetime + 0.3
	set_process(true)


# --- bookkeeping ----------------------------------------------------------------------------------------------------------------

func live_count() -> int:
	return _live


func live_of(kind: int) -> int:
	var n := 0
	for i in MAX:
		if _on[i] == 1 and _kind[i] == kind:
			n += 1
	return n


func visible_draw() -> bool:
	return _node != null and _node.visible


func shower_live() -> int:
	return (1 if shards != null and shards.visible else 0) + (1 if chunks != null and chunks.visible else 0)


func clock() -> float:
	return _clock


func _free_slot(i: int) -> void:
	_mm.set_instance_transform(i, _hidden)
	_on[i] = 0
	_live -= 1


func _process(delta: float) -> void:
	_clock += delta
	_mat.set_shader_parameter(&"clock", _clock)
	_check += delta
	if _check >= 0.25:
		_check = 0.0
		for i in MAX:
			if _on[i] == 1 and _clock - _born[i] >= _life[i]:
				_free_slot(i)
		if _clock > REBASE_AT:
			var shift := _clock
			_clock = 0.0
			for i in MAX:
				if _on[i] == 1:
					_born[i] -= shift
					_mm.set_instance_custom_data(i, Color(_born[i], _seed[i], _life[i], float(_kind[i])))
			_mat.set_shader_parameter(&"clock", _clock)
	if _shard_left > 0.0:
		_shard_left -= delta
		if _shard_left <= 0.0:
			shards.emitting = false
			shards.visible = false
	if _chunk_left > 0.0:
		_chunk_left -= delta
		if _chunk_left <= 0.0:
			chunks.emitting = false
			chunks.visible = false
	if _live <= 0:
		_node.visible = false
		if _shard_left <= 0.0 and _chunk_left <= 0.0:
			set_process(false)


func clear() -> void:
	if _mm == null:
		return
	for i in MAX:
		if _on[i] == 1:
			_mm.set_instance_transform(i, _hidden)
			_on[i] = 0
	_live = 0
	_next_long = RIPPLE_MAX
	_next_ripple = 0
	_next_struct = 0
	_node.visible = false
	shards.emitting = false
	shards.visible = false
	chunks.emitting = false
	chunks.visible = false
	_shard_left = 0.0
	_chunk_left = 0.0
	set_process(false)
