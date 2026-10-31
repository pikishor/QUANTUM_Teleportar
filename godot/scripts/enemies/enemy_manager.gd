class_name EnemyManager
extends Node
## Spawns, pools and rules the enemies (Game.enemies): patrols, reinforcements by heat, heat decay, the shared bolt pool and the lifecycle resets.
##
## Caps (alive at once, EnemyTypes.CAPS by graphics tier): LOW 5, MED 8, HIGH 12. spawn() returns null at the cap, so reinforcements, patrols and
## explicit callers all respect it. Patrols are 7 groups of 2-3 (sentinels; a heavy leads far groups; every third group is a squad of operatives),
## at least 110 m from the spawn. Only as many start as the tier allows (cap minus 2 slots kept for reinforcements); the other groups wait as
## dormant spots and are spawned when the player comes within 150 m and there is room.
## Reinforcements: while heat >= 1, floor(2 + heat * 2.6) enemies alive within 110 m of the player, spawned 38-75 m away on a road, a heavy from
## heat 3, strikers about 10 % (more in the heavy tiers), operatives about a third of the rest; reinforcements more than 170 m away are released.
## Heat decay: no aware enemy within 70 m for 7 s (Game.quiet) lowers heat by 0.12 per second.
## Bolts: one MultiMesh (a single draw call) with 48 pooled energy bolts (26-30 m/s, dodgeable) that hurt the player, a driven vehicle or the clone.

const BOLT_POOL := 48
const BOLT_LIFE := 3.0
const BOLT_COLOR_BOOST := 1.6
const BOLT_SHADER := preload("res://assets/shaders/fx_bolt.gdshader")
const BOLT_LEN := 3.6             ## streak length of a bolt (metres), see fx_bolt.gdshader
const REINFORCE_EVERY := 1.4
const NEAR_RADIUS := 110.0
const DESPAWN_DIST := 170.0
const PATROL_GROUPS := 7
const PATROL_MIN_SPAWN_DIST := 110.0
const PATROL_STREAM_DIST := 150.0
const QUIET_BEFORE_DECAY := 7.0
const HEAT_DECAY := 0.12
const AWARE_NEAR := 70.0

var list: Array[Drone] = []          ## every active enemy, corpses included until they are released

var _pool := {}                      ## type -> Array[Drone] (inactive)
var _groups: Array = []              ## dormant / spawned patrol spots {pos, types, spawned}
var _spawn_t := 0.0
var _stream_t := 0.0
var _patrols_built := false
var _clone: Node3D
var _clone_frame := -1
var marks: EnemyMarks                ## threat rings, attack telegraph, health bars (3 draws for everybody)
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _b_pos := PackedVector3Array()
var _b_vel := PackedVector3Array()
var _b_org := PackedVector3Array()
var _b_life := PackedFloat32Array()
var _b_wait := PackedFloat32Array()
var _b_dmg := PackedFloat32Array()
var _hidden_xform := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0.0, -1000.0, 0.0))


func _ready() -> void:
	Game.enemies = self
	DynamicFill.ensure_light(self)
	DynamicFill.set_quality(Game.quality)
	_build_bolts()
	marks = EnemyMarks.new()
	marks.name = "Marks"
	add_child(marks)
	Game.new_game.connect(_on_new_game)
	Game.respawn.connect(_on_respawn)
	Game.next_sector.connect(_on_next_sector)
	Game.quality_changed.connect(_on_quality)
	_initial_patrols.call_deferred()


func _exit_tree() -> void:
	if Game.enemies == self:
		Game.enemies = null


func _initial_patrols() -> void:
	if not _patrols_built and is_inside_tree():
		init_patrols()


# --- API ------------------------------------------------------------------------------------------------------------

func cap() -> int:
	return EnemyTypes.CAPS[clampi(Game.quality, 0, 2)]


## Enemies that are alive (corpses do not count towards the cap).
func alive_count() -> int:
	var n := 0
	for e in list:
		if e.active and not e.dead:
			n += 1
	return n


## Activate an enemy of `type` (sentinel, striker, heavy, operative) at the ground position `pos`. Returns null at the cap.
func spawn(type: StringName, pos: Vector3, aware := false, reinforce := false) -> Drone:
	if alive_count() >= cap():
		return null
	var d := _acquire(type)
	d.activate(pos, aware, reinforce)
	d.max_hp = float(d.cfg["hp"]) * Progress.enemy_hp_mult()       # sector difficulty (1.0 in sector 1)
	d.hp = d.max_hp
	if not list.has(d):
		list.append(d)
	return d


## Remove everybody (or only the reinforcements) and every flying bolt.
func clear(reinforcements_only := false) -> void:
	for e in list.duplicate():
		if not reinforcements_only or e.reinforce:
			release(e)
	for i in BOLT_POOL:
		_kill_bolt(i)


## Back to the pool: the drone is hidden, out of the group and out of the simulation.
func release(d: Drone) -> void:
	list.erase(d)
	d.deactivate()
	var arr: Array = _pool.get(d.type, [])
	if not arr.has(d):
		arr.append(d)
	_pool[d.type] = arr


## 7 patrol groups far from the spawn; as many as the tier allows start right away, the rest wait for the player (see the class comment).
func init_patrols() -> void:
	_patrols_built = true
	_groups.clear()
	var w := Game.world
	if not is_instance_valid(w) or not w.has_method(&"random_road_point"):
		return
	for g in PATROL_GROUPS:
		var p := Vector3.INF
		for tries in 40:
			var q: Vector3 = w.call(&"random_road_point")
			if Vector2(q.x - Game.SPAWN.x, q.z - Game.SPAWN.z).length() >= PATROL_MIN_SPAWN_DIST:
				p = q
				break
		if not p.is_finite():
			continue
		var far := Vector2(p.x, p.z).length() > 200.0
		var types: Array[StringName] = []
		for i in 2 + (g % 2):
			if g % 3 == 2:
				types.append(&"operative")
			elif far and i == 0 and g % 3 == 0:
				types.append(&"heavy")
			else:
				types.append(&"sentinel")
		_groups.append({"pos": p, "types": types, "spawned": false})
	var ref := Game.SPAWN
	if is_instance_valid(Game.player):
		ref = Game.player.global_position
	_groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Vector2(a["pos"].x - ref.x, a["pos"].z - ref.z).length() < Vector2(b["pos"].x - ref.x, b["pos"].z - ref.z).length())
	_stream_patrols(true)


func patrol_groups() -> Array:
	return _groups


## Wake up unaware enemies within `radius` (a hit enemy tells its neighbours).
func alert_near(pos: Vector3, radius: float, except: Drone = null) -> void:
	for e in list:
		if e == except or e.dead or not e.active or e.aware:
			continue
		if Vector2(e.global_position.x - pos.x, e.global_position.z - pos.z).length() < radius:
			e.alert()


## The player's superposition clone (a Node3D in group "clone", exposed as player.quantum.clone), or null. Cached per physics frame.
func get_clone() -> Node3D:
	var f := Engine.get_physics_frames()
	if f != _clone_frame:
		_clone_frame = f
		_clone = null
		var q := _quantum()
		if q != null:
			var c: Variant = q.get(&"clone")
			if c is Node3D and is_instance_valid(c):
				_clone = c as Node3D
	return _clone


func hit_clone() -> void:
	var q := _quantum()
	if q != null and q.has_method(&"collapse"):
		q.call(&"collapse")


func _quantum() -> Node:
	var p := Game.player
	if not is_instance_valid(p):
		return null
	var q: Variant = p.get(&"quantum")
	return q as Node if q is Node and is_instance_valid(q) else null


## Fire an energy bolt from `from` toward `to` (small random spread), `delay` seconds after now (burst rounds).
func bolt(from: Vector3, to: Vector3, type: StringName, delay := 0.0) -> void:
	var slot := -1
	for i in BOLT_POOL:
		if _b_life[i] <= 0.0:
			slot = i
			break
	if slot < 0:
		return
	var cfg := EnemyTypes.get_cfg(type)
	var dir := (to - from).normalized()
	dir += Vector3(randf_range(-0.035, 0.035), randf_range(-0.02, 0.02), randf_range(-0.035, 0.035))
	dir = dir.normalized()
	_b_pos[slot] = from
	_b_org[slot] = from
	_b_vel[slot] = dir * float(cfg["bolt"])
	_b_life[slot] = BOLT_LIFE
	_b_wait[slot] = delay
	_b_dmg[slot] = float(cfg["dmg"])
	var c: Color = cfg["color"]
	_mm.set_instance_color(slot, Color(c.r * BOLT_COLOR_BOOST, c.g * BOLT_COLOR_BOOST, c.b * BOLT_COLOR_BOOST, 1.0))
	if delay <= 0.0:
		_set_bolt(slot, from, dir)
	else:
		_mm.set_instance_transform(slot, _hidden_xform)


func active_bolts() -> int:
	var n := 0
	for i in BOLT_POOL:
		if _b_life[i] > 0.0:
			n += 1
	return n


# --- lifecycle ------------------------------------------------------------------------------------------------------

func _on_new_game() -> void:
	_reset_all()


func _on_next_sector() -> void:
	_reset_all()


func _on_respawn() -> void:
	clear(true)
	_spawn_t = 0.0


func _reset_all() -> void:
	clear(false)
	_spawn_t = 0.0
	init_patrols()


func _on_quality(level: int) -> void:
	DynamicFill.set_quality(level)


# --- simulation -----------------------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var cam := Game.camera
	if is_instance_valid(cam):
		DynamicFill.aim_light(cam.global_rotation.y)
	marks.refresh(list)


func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return
	var p := Game.player
	var ppos := p.global_position if is_instance_valid(p) else Vector3.INF
	_sweep(ppos)
	if is_instance_valid(p):
		_tick_heat(delta, ppos)
		_tick_reinforcements(delta, ppos)
		_tick_stream(delta, ppos)
	_tick_bolts(delta)


func _sweep(ppos: Vector3) -> void:
	var i := list.size() - 1
	while i >= 0:
		var e := list[i]
		if e.remove:
			release(e)
		elif e.reinforce and not e.dead and ppos.is_finite() \
				and Vector2(e.global_position.x - ppos.x, e.global_position.z - ppos.z).length() > DESPAWN_DIST:
			release(e)
		i = mini(i - 1, list.size() - 1)


func _tick_heat(delta: float, ppos: Vector3) -> void:
	var seen := false
	for e in list:
		if not e.dead and e.active and e.aware \
				and Vector2(e.global_position.x - ppos.x, e.global_position.z - ppos.z).length() < AWARE_NEAR:
			seen = true
			break
	Game.quiet = 0.0 if seen else Game.quiet + delta
	if Game.quiet > QUIET_BEFORE_DECAY and Game.heat > 0.0:
		Game.heat = maxf(0.0, Game.heat - HEAT_DECAY * delta)


func _tick_reinforcements(delta: float, ppos: Vector3) -> void:
	_spawn_t -= delta
	var heat := Game.heat
	var want := int(floor(2.0 + heat * 2.6)) if heat >= 1.0 else 0
	if _spawn_t > 0.0 or want <= 0:
		return
	_spawn_t = REINFORCE_EVERY
	var near := 0
	for e in list:
		if not e.dead and e.active and Vector2(e.global_position.x - ppos.x, e.global_position.z - ppos.z).length() < NEAR_RADIUS:
			near += 1
	if near >= want or alive_count() >= cap():
		return
	var w := Game.world
	if not is_instance_valid(w) or not w.has_method(&"road_point_near"):
		return
	var pt: Vector3 = w.call(&"road_point_near", ppos, 38.0, 75.0)
	if not pt.is_finite():
		return
	var type := pick_reinforcement_type(heat, randf())
	var d := spawn(type, pt, true, true)
	if d != null:
		FX.burst(pt + Vector3(0.0, 1.0, 0.0), d.cfg["color"], 25, 6.0, 0.6, 0.0)


## Reinforcement mix for a roll r in 0..1: heavy from heat 3 (25 %), strikers 10 % (35 % band from heat 3), then a third operatives, rest sentinels.
static func pick_reinforcement_type(heat: float, r: float) -> StringName:
	if heat >= 3.0 and r < 0.25:
		return &"heavy"
	var striker_to := 0.35 if heat >= 3.0 else 0.10
	if r < striker_to:
		return &"striker"
	if r < striker_to + 0.30:
		return &"operative"
	return &"sentinel"


func _tick_stream(delta: float, ppos: Vector3) -> void:
	_stream_t -= delta
	if _stream_t > 0.0:
		return
	_stream_t = 1.0
	_stream_patrols(false, ppos)


func _stream_patrols(initial: bool, ppos := Vector3.INF) -> void:
	var patrol_cap := maxi(2, cap() - 2)
	for g: Dictionary in _groups:
		if g["spawned"]:
			continue
		var gp: Vector3 = g["pos"]
		if not initial and (not ppos.is_finite() or Vector2(gp.x - ppos.x, gp.z - ppos.z).length() > PATROL_STREAM_DIST):
			continue
		var types: Array = g["types"]
		var patrols := 0
		for e in list:
			if e.active and not e.dead and not e.reinforce:
				patrols += 1
		if patrols + types.size() > patrol_cap or alive_count() + types.size() > cap():
			if initial:
				continue
			return
		g["spawned"] = true
		for t: StringName in types:
			spawn(t, gp + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0)))


func _acquire(type: StringName) -> Drone:
	var arr: Array = _pool.get(type, [])
	if not arr.is_empty():
		return arr.pop_back() as Drone
	var d: Drone = Operative.new() if type == &"operative" else Drone.new()
	add_child(d)
	d.setup(type)
	return d


# --- bolts ----------------------------------------------------------------------------------------------------------

func _build_bolts() -> void:
	_b_pos.resize(BOLT_POOL)
	_b_vel.resize(BOLT_POOL)
	_b_org.resize(BOLT_POOL)
	_b_life.resize(BOLT_POOL)
	_b_wait.resize(BOLT_POOL)
	_b_dmg.resize(BOLT_POOL)
	var sm := QuadMesh.new()                      # a glowing streak (white-hot head, coloured halo, tail), turned to the camera by the shader
	sm.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = BOLT_SHADER
	sm.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = sm
	_mm.instance_count = BOLT_POOL
	for i in BOLT_POOL:
		_mm.set_instance_transform(i, _hidden_xform)
		_mm.set_instance_color(i, Color.WHITE)
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Bolts"
	_mmi.multimesh = _mm
	_mmi.custom_aabb = AABB(Vector3(-600.0, -10.0, -600.0), Vector3(1200.0, 200.0, 1200.0))
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)


## Place one streak so that its head is at `pos` and it trails behind along `dir` (the shader turns it to face the camera around that axis).
func _set_bolt(i: int, pos: Vector3, dir: Vector3) -> void:
	var y := dir * BOLT_LEN
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	var x := dir.cross(up).normalized() * 1.6          # width of the streak quad
	var z := x.cross(dir)
	_mm.set_instance_transform(i, Transform3D(Basis(x, y, z), pos - dir * (BOLT_LEN * 0.3)))


func _kill_bolt(i: int) -> void:
	_b_life[i] = 0.0
	_b_wait[i] = 0.0
	_mm.set_instance_transform(i, _hidden_xform)


func _tick_bolts(delta: float) -> void:
	var p := Game.player
	var player_ok := is_instance_valid(p)
	var ppos := p.global_position if player_ok else Vector3.ZERO
	var veh: Node3D = null
	if player_ok:
		var v: Variant = p.get(&"vehicle")
		if v is Node3D and is_instance_valid(v):
			veh = v as Node3D
	var clone := get_clone()
	var city := Game.world as City
	for i in BOLT_POOL:
		if _b_life[i] <= 0.0:
			continue
		if _b_wait[i] > 0.0:
			_b_wait[i] -= delta
			if _b_wait[i] <= 0.0:
				_set_bolt(i, _b_pos[i], _b_vel[i].normalized())
			continue
		_b_life[i] -= delta
		var pos := _b_pos[i] + _b_vel[i] * delta
		_b_pos[i] = pos
		var gone := _b_life[i] <= 0.0 or pos.y < 0.0
		if not gone and city != null:
			gone = city.is_inside_building(pos)
		if not gone and clone != null:
			var cp := clone.global_position
			if Vector2(pos.x - cp.x, pos.z - cp.z).length() < 0.9 and pos.y < cp.y + 1.9 and pos.y > cp.y:
				gone = true
				hit_clone()
		if not gone and player_ok:
			if veh != null:
				var vp := veh.global_position
				if Vector2(pos.x - vp.x, pos.z - vp.z).length() < 2.1 and pos.y < vp.y + 2.0:
					gone = true
					p.call(&"damage", _b_dmg[i], _b_org[i])
			elif Vector2(pos.x - ppos.x, pos.z - ppos.z).length() < 0.6 and pos.y > ppos.y and pos.y < ppos.y + 1.9:
				gone = true
				p.call(&"damage", _b_dmg[i], _b_org[i])
		if gone:
			_kill_bolt(i)
			FX.burst(pos, Color(1.0, 0.5, 0.6), 8, 5.0, 0.3, 4.0, 1.6)
		else:
			_set_bolt(i, pos, _b_vel[i].normalized())
