class_name Breakables
extends Node3D
## Breakable world: crates, bins, glass panes, fences, light poles, vending machines and market stalls along the sidewalks. Every intact prop is one
## instance of ONE MultiMesh (a single draw call) with a StaticBody3D each (layer world, so bullets, the player and cars meet them); debris is a second pooled
## MultiMesh (DEBRIS pieces, one draw while any piece lives) and sparks come from the player's pooled ImpactSparks. A broken prop loses its collider and its
## instance, flings pooled debris, and respawns RESPAWN seconds later once the player is away. Breaks come from bullets (hit_at, wired in player_weapon),
## explosions (blast, wired in Game.explode) and fast vehicles (a 0.15 s Timer that exists only to look at vehicles moving faster than VEHICLE_SPEED).
## Idle cost: nothing runs per frame. _process is on only while debris flies; the respawn Timer only while something is broken.
## surface_of(collider) tells the bullet decals what they landed on: &"metal", &"glass" or &"concrete".

const COUNT := 140
const DEBRIS := 64
const RESPAWN := 40.0
const RESPAWN_AWAY := 22.0
const DEBRIS_LIFE := 4.0
const VEHICLE_SPEED := 6.0
const VEHICLE_REACH := 2.4
const GROUND := 0.0

## kind: size (m), color, hp (bullet hits), surface, debris pieces, spark color, weight (placement share)
const KINDS := [
	{"name": "crate", "size": Vector3(0.9, 0.9, 0.9), "color": Color(0.42, 0.31, 0.2), "hp": 3, "surface": &"concrete", "debris": 7, "spark": Color(0.9, 0.7, 0.4), "w": 3},
	{"name": "bin", "size": Vector3(0.7, 1.0, 0.7), "color": Color(0.16, 0.2, 0.24), "hp": 3, "surface": &"metal", "debris": 5, "spark": Color(1.0, 0.85, 0.5), "w": 3},
	{"name": "window", "size": Vector3(2.2, 1.8, 0.06), "color": Color(0.35, 0.55, 0.6), "hp": 1, "surface": &"glass", "debris": 10, "spark": Color(0.7, 0.95, 1.0), "w": 2},
	{"name": "fence", "size": Vector3(3.0, 1.3, 0.1), "color": Color(0.25, 0.27, 0.3), "hp": 4, "surface": &"metal", "debris": 6, "spark": Color(1.0, 0.85, 0.5), "w": 2},
	{"name": "pole", "size": Vector3(0.2, 5.0, 0.2), "color": Color(0.2, 0.22, 0.25), "hp": 8, "surface": &"metal", "debris": 8, "spark": Color(1.0, 0.8, 0.45), "w": 1},
	{"name": "vending", "size": Vector3(1.0, 1.9, 0.8), "color": Color(0.55, 0.12, 0.3), "hp": 6, "surface": &"metal", "debris": 9, "spark": Color(1.0, 0.5, 0.7), "w": 1},
	{"name": "stall", "size": Vector3(2.4, 1.6, 1.4), "color": Color(0.5, 0.36, 0.18), "hp": 4, "surface": &"concrete", "debris": 8, "spark": Color(0.9, 0.7, 0.4), "w": 2},
]

static var current: Breakables

var kind_of := PackedInt32Array()
var hp := PackedInt32Array()
var broken := PackedByteArray()             ## 1 = broken
var respawn_at := PackedFloat32Array()
var positions: Array[Vector3] = []          ## centre of each prop
var yaws := PackedFloat32Array()
var bodies: Array[StaticBody3D] = []
var broken_count := 0
var break_total := 0
var debris_live := 0

var _mm: MultiMesh
var _inst: MultiMeshInstance3D
var _dmm: MultiMesh
var _dinst: MultiMeshInstance3D
var _dpos := PackedVector3Array()
var _dvel := PackedVector3Array()
var _dspin := PackedVector3Array()
var _dang := PackedVector3Array()
var _dsize := PackedFloat32Array()
var _dleft := PackedFloat32Array()
var _dnext := 0
var _timer: Timer
var _veh_timer: Timer
var _last_speed := {}
var _hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -4000.0, 0.0))
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	current = self
	top_level = true
	global_transform = Transform3D.IDENTITY
	_build_props()
	_build_debris()
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.one_shot = false
	_timer.timeout.connect(_respawn_tick)
	add_child(_timer)
	_veh_timer = Timer.new()
	_veh_timer.wait_time = 0.15
	_veh_timer.timeout.connect(_vehicle_tick)
	add_child(_veh_timer)
	_veh_timer.start()
	Game.new_game.connect(reset)
	Game.respawn.connect(reset)
	set_process(false)


func _exit_tree() -> void:
	if current == self:
		current = null


func _build_props() -> void:
	_rng.seed = 5150
	var weights: Array[int] = []
	for k in KINDS.size():
		for _j in int(KINDS[k]["w"]):
			weights.append(k)
	kind_of.resize(COUNT)
	hp.resize(COUNT)
	broken.resize(COUNT)
	respawn_at.resize(COUNT)
	yaws.resize(COUNT)
	var half := Game.PITCH * Game.N * 0.5
	var edge := Game.ROAD * 0.5 + 1.9
	for i in COUNT:
		var along_x := (i % 2) == 0
		var road := _rng.randi_range(0, Game.N)
		var rc := -half + road * Game.PITCH
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var block := _rng.randi_range(0, Game.N - 1)
		var t := -half + block * Game.PITCH + _rng.randf_range(Game.ROAD * 0.5 + 5.0, Game.PITCH - Game.ROAD * 0.5 - 5.0)
		var k: int = weights[_rng.randi() % weights.size()]
		var sz: Vector3 = KINDS[k]["size"]
		var pos := Vector3(t, sz.y * 0.5, rc + side * edge) if along_x else Vector3(rc + side * edge, sz.y * 0.5, t)
		kind_of[i] = k
		hp[i] = int(KINDS[k]["hp"])
		yaws[i] = 0.0 if along_x else PI * 0.5
		positions.append(pos)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.7
	mat.metallic = 0.3
	box.material = mat
	_mm.mesh = box
	_mm.instance_count = COUNT
	_inst = MultiMeshInstance3D.new()
	_inst.name = "Props"
	_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # small props: one less shadow-pass draw (perf budget)
	_inst.multimesh = _mm
	_inst.custom_aabb = AABB(Vector3(-1200.0, -50.0, -1200.0), Vector3(2400.0, 400.0, 2400.0))
	add_child(_inst)
	for i in COUNT:
		var k := kind_of[i]
		var sz: Vector3 = KINDS[k]["size"]
		_mm.set_instance_transform(i, _prop_xf(i))
		var c: Color = KINDS[k]["color"]
		var v := 0.85 + 0.3 * float((i * 37) % 11) / 10.0
		_mm.set_instance_color(i, Color(c.r * v, c.g * v, c.b * v))
		var b := StaticBody3D.new()
		b.collision_layer = Game.L_WORLD
		b.collision_mask = 0
		b.set_meta(&"bk_index", i)
		b.set_meta(&"surface", KINDS[k]["surface"])
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sz
		cs.shape = bs
		b.add_child(cs)
		add_child(b)
		b.global_position = positions[i]
		b.rotation.y = yaws[i]
		bodies.append(b)


func _prop_xf(i: int) -> Transform3D:
	var sz: Vector3 = KINDS[kind_of[i]]["size"]
	return Transform3D(Basis(Vector3.UP, yaws[i]) * Basis.from_scale(sz), positions[i])


func _build_debris() -> void:
	_dmm = MultiMesh.new()
	_dmm.transform_format = MultiMesh.TRANSFORM_3D
	_dmm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	box.material = mat
	_dmm.mesh = box
	_dmm.instance_count = DEBRIS
	_dpos.resize(DEBRIS)
	_dvel.resize(DEBRIS)
	_dspin.resize(DEBRIS)
	_dang.resize(DEBRIS)
	_dsize.resize(DEBRIS)
	_dleft.resize(DEBRIS)
	_dleft.fill(0.0)
	for i in DEBRIS:
		_dmm.set_instance_transform(i, _hidden)
	_dinst = MultiMeshInstance3D.new()
	_dinst.name = "Debris"
	_dinst.multimesh = _dmm
	_dinst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dinst.custom_aabb = AABB(Vector3(-1200.0, -50.0, -1200.0), Vector3(2400.0, 400.0, 2400.0))
	_dinst.visible = false                  # no draw call while nothing flies
	add_child(_dinst)


# --- API -----------------------------------------------------------------------------------------------------------------

## Index of the live prop whose collider is `c`, or -1.
func index_of(c: Object) -> int:
	if c is Node and (c as Node).has_meta(&"bk_index"):
		return int((c as Node).get_meta(&"bk_index"))
	return -1


## Surface name of a collider for decals: a breakable's own surface, else concrete.
static func surface_of(c: Object) -> StringName:
	if c is Node and (c as Node).has_meta(&"surface"):
		return (c as Node).get_meta(&"surface")
	return &"concrete"


## A bullet landed at `pos` (normal n) on `collider`: sparks, damage, break at 0 hp. Returns true when it was a breakable.
func hit_at(collider: Object, pos: Vector3, n: Vector3, hits := 1) -> bool:
	var i := index_of(collider)
	if i < 0 or broken[i] == 1:
		return false
	_spark(pos, n, KINDS[kind_of[i]]["spark"], 0.7)
	hp[i] -= hits
	if hp[i] <= 0:
		break_prop(i, n * 3.0)
	return true


func break_prop(i: int, push := Vector3.ZERO) -> void:
	if i < 0 or i >= COUNT or broken[i] == 1:
		return
	broken[i] = 1
	broken_count += 1
	break_total += 1
	respawn_at[i] = PlayerUtil.now() + RESPAWN
	_mm.set_instance_transform(i, _hidden)
	bodies[i].collision_layer = 0
	var k: Dictionary = KINDS[kind_of[i]]
	var p := positions[i]
	_spark(p, Vector3.UP, k["spark"], 1.2)
	var sz: Vector3 = k["size"]
	for j in int(k["debris"]):
		var off := Vector3(randf_range(-0.5, 0.5) * sz.x, randf_range(-0.4, 0.5) * sz.y, randf_range(-0.5, 0.5) * sz.z)
		var out := (Basis(Vector3.UP, yaws[i]) * off).normalized()
		_spawn_debris(p + Basis(Vector3.UP, yaws[i]) * off, out * randf_range(1.5, 4.5) + Vector3.UP * randf_range(1.5, 4.0) + push, k["color"], clampf(minf(sz.x, minf(sz.y, maxf(sz.z, 0.2))) * 0.3, 0.08, 0.3))
	Sfx.play_at(&"explosion_small", p, -14.0)
	if _timer != null and _timer.is_stopped():
		_timer.start()


## A prop is lifted away (WARP GRAB): hidden and not solid, no debris; it comes back after RESPAWN like a broken one.
func take_prop(i: int) -> void:
	if i < 0 or i >= COUNT or broken[i] == 1:
		return
	broken[i] = 1
	broken_count += 1
	respawn_at[i] = PlayerUtil.now() + RESPAWN
	_mm.set_instance_transform(i, _hidden)
	bodies[i].collision_layer = 0
	if _timer != null and _timer.is_stopped():
		_timer.start()


## Explosion at `pos`: every prop within radius breaks, pushed away.
func blast(pos: Vector3, radius: float) -> int:
	var n := 0
	for i in COUNT:
		if broken[i] == 0 and positions[i].distance_to(pos) < radius + 1.0:
			var d := positions[i] - pos
			d.y = 0.0
			break_prop(i, d.normalized() * 5.0)
			n += 1
	return n


func reset() -> void:
	for i in COUNT:
		if broken[i] == 1:
			_restore(i)
	for i in DEBRIS:
		if _dleft[i] > 0.0:
			_dleft[i] = 0.0
			_dmm.set_instance_transform(i, _hidden)
	debris_live = 0
	_dinst.visible = false
	set_process(false)
	_timer.stop()
	_last_speed.clear()


func _restore(i: int) -> void:
	broken[i] = 0
	broken_count -= 1
	hp[i] = int(KINDS[kind_of[i]]["hp"])
	_mm.set_instance_transform(i, _prop_xf(i))
	bodies[i].collision_layer = Game.L_WORLD


func _spark(pos: Vector3, n: Vector3, color: Color, power: float) -> void:
	if is_instance_valid(Game.player) and Game.player.sparks != null:
		Game.player.sparks.spark(pos, n, color, power)
	else:
		FX.burst(pos, color, 6, 4.0, 0.3, 8.0, 1.0)


func _spawn_debris(pos: Vector3, vel: Vector3, color: Color, size: float) -> void:
	var i := _dnext
	_dnext = (_dnext + 1) % DEBRIS
	if _dleft[i] <= 0.0:
		debris_live += 1
	_dpos[i] = pos
	_dvel[i] = vel
	_dspin[i] = Vector3(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
	_dang[i] = Vector3.ZERO
	_dsize[i] = size
	_dleft[i] = DEBRIS_LIFE
	_dmm.set_instance_color(i, color)
	_dinst.visible = true
	set_process(true)


func _process(delta: float) -> void:
	for i in DEBRIS:
		var left := _dleft[i]
		if left <= 0.0:
			continue
		left -= delta
		if left <= 0.0:
			_dleft[i] = 0.0
			debris_live -= 1
			_dmm.set_instance_transform(i, _hidden)
			continue
		_dleft[i] = left
		var v := _dvel[i]
		var p := _dpos[i]
		var s := _dsize[i]
		if p.y <= GROUND + s * 0.5 and v.y <= 0.0:
			p.y = GROUND + s * 0.5
			v.y = -v.y * 0.3
			v.x *= 0.6
			v.z *= 0.6
			if absf(v.y) < 0.5:
				v = Vector3.ZERO
				_dspin[i] = Vector3.ZERO
		else:
			v.y -= 14.0 * delta
		p += v * delta
		_dvel[i] = v
		_dpos[i] = p
		_dang[i] += _dspin[i] * delta
		var fade := clampf(left / 0.6, 0.0, 1.0)
		var b := Basis.from_euler(_dang[i]) * Basis.from_scale(Vector3.ONE * s * fade)
		_dmm.set_instance_transform(i, Transform3D(b, p))
	if debris_live <= 0:
		_dinst.visible = false
		set_process(false)


func _respawn_tick() -> void:
	var now := PlayerUtil.now()
	var pp := Game.player.global_position if is_instance_valid(Game.player) else Vector3(1e6, 0.0, 1e6)
	for i in COUNT:
		if broken[i] == 1 and now >= respawn_at[i] and positions[i].distance_to(pp) > RESPAWN_AWAY:
			_restore(i)
	if broken_count <= 0:
		_timer.stop()


func _vehicle_tick() -> void:
	if not Game.is_playing():
		return
	for v: Node in get_tree().get_nodes_in_group(&"vehicle"):
		if not (v is Node3D) or not ("speed" in v):
			continue
		var id := v.get_instance_id()
		var sp := absf(float(v.speed))
		var fast := maxf(sp, float(_last_speed.get(id, 0.0)))
		_last_speed[id] = sp
		if fast < VEHICLE_SPEED:
			continue
		var vp: Vector3 = (v as Node3D).global_position
		for i in COUNT:
			if broken[i] == 0:
				var d := positions[i] - vp
				d.y = 0.0
				if d.length() < VEHICLE_REACH + KINDS[kind_of[i]]["size"].x * 0.35:
					break_prop(i, d.normalized() * minf(fast * 0.5, 9.0))
	if _last_speed.size() > 64:
		_last_speed.clear()
