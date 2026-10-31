class_name Drone
extends StaticBody3D
## Hovering Observer drone (sentinel, striker, heavy): the AI of src/enemies.js. Operative is the human subclass.
## Group "enemy", collision layer "enemy" (a sphere around the body centre, the rifle also ray-tests center() / radius). Pooled by the EnemyManager:
## setup() once, then activate() / deactivate() per life, so nothing is allocated while playing.
##
## Behaviour: idle wander near home -> aware (player within 32 m, or heat > 0 within 80 m, or damaged; alerts neighbours within 35 m) -> chase / back off /
## strafe at range with throttled line-of-sight rays, targets the player or the player's quantum clone (50 %), dodgeable energy bolts from the manager's pool,
## strikers explode on contact. Hit sparks, floating health bar, death: score, heat, energy refund, 30 % health / 30 % energy drops through Game.missions.

signal died(drone: Drone)

const AWARE_DIST := 32.0
const AWARE_HEAT_DIST := 80.0
const ALERT_RADIUS := 35.0
const LOS_RANGE := 90.0
const WORLD_LIMIT := 345.0
const DEATH_TIME := 0.7
const BAR_WIDTH := 1.4
const BAR_SECONDS := 3.0
const ROTOR_SPEED := 46.0

static var _bar_bg: StandardMaterial3D
static var _bar_fg: StandardMaterial3D
static var _bar_mesh: QuadMesh

var type: StringName = &"sentinel"
var cfg: Dictionary = {}
var hp := 60.0
var max_hp := 60.0
var radius := 0.95
var aware := false
var linked: Drone
var dead := false
var reinforce := false
var active := false          ## in play (pooled drones are inactive, hidden and out of the group)
var remove := false          ## the death animation is over: the manager releases it
var los := false             ## last throttled line-of-sight result to the current target
var home := Vector3.ZERO
var yaw := 0.0
var center_y := 0.95
var model: Node3D
var uses_model := false
var muzzle: Node3D

var _t := 0.0
var _dead_t := 0.0
var _retarget := 0.0
var _want_clone := false
var _tgt := Vector3.ZERO
var _tgt_ok := false
var _tgt_clone := false      ## the current target is the quantum clone
var _fire_t := 1.0
var _los_t := 0.0
var _strafe := 1.0
var _strafe_t := 2.0
var _wander_t := 0.0
var _wdir := 0.0
var _mx := 0.0
var _mz := 0.0
var _speed := 0.0
var _moved := 0.0
var _bar_t := 0.0
var _bank := 0.0
var _flash := 0.0
var _stagger := 0.0
var _hover := 0.35
var _rotors: Array[Node3D] = []
var _glow: Array[BaseMaterial3D] = []
var _bar: Node3D
var _bar_fill: MeshInstance3D
var _ray := PhysicsRayQueryParameters3D.new()
var _exclude: Array[RID] = []


## Build the visuals and the collider once. `t` is a key of EnemyTypes.TYPES.
func setup(t: StringName) -> void:
	type = t
	cfg = EnemyTypes.get_cfg(t)
	radius = cfg["radius"]
	center_y = cfg["center_y"]
	max_hp = cfg["hp"]
	hp = max_hp
	_hover = cfg["hover"]
	name = String(t).capitalize()
	collision_layer = 0
	collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = _make_shape()
	cs.position = Vector3(0.0, center_y, 0.0)
	add_child(cs)
	_build_visual()
	_build_bar()
	_ray.collision_mask = Game.L_WORLD
	_ray.collide_with_areas = false
	visible = false
	set_physics_process(false)


func _make_shape() -> Shape3D:
	var sph := SphereShape3D.new()
	sph.radius = radius
	return sph


## Start a life at `pos` (ground position). Safe to call on a pooled drone.
func activate(pos: Vector3, is_aware := false, is_reinforce := false) -> void:
	hp = max_hp
	dead = false
	remove = false
	aware = is_aware
	reinforce = is_reinforce
	linked = null
	los = false
	home = Vector3(pos.x, 0.0, pos.z)
	_t = randf() * 10.0
	_dead_t = 0.0
	_retarget = 0.0
	_want_clone = false
	_fire_t = randf_range(0.5, 1.5)
	_los_t = 0.0
	_strafe = 1.0 if randf() < 0.5 else -1.0
	_strafe_t = randf_range(1.0, 3.0)
	_wander_t = 0.0
	_wdir = randf() * TAU
	_mx = 0.0
	_mz = 0.0
	_speed = 0.0
	_bar_t = 0.0
	_bank = 0.0
	_flash = 0.0
	_stagger = 0.0
	yaw = randf() * TAU
	rotation = Vector3(0.0, yaw, 0.0)
	global_position = Vector3(pos.x, _hover, pos.z)
	if model != null:
		model.rotation = Vector3.ZERO
		model.position = Vector3.ZERO
	_bar.visible = false
	_set_glow(2.0)
	_on_activate()
	collision_layer = Game.L_ENEMY
	if not is_in_group(&"enemy"):
		add_to_group(&"enemy")
	visible = true
	active = true
	set_physics_process(true)


func deactivate() -> void:
	active = false
	dead = false
	visible = false
	collision_layer = 0
	linked = null
	_bar.visible = false
	if is_in_group(&"enemy"):
		remove_from_group(&"enemy")
	set_physics_process(false)


## Alert: this drone knows where the player is.
func alert() -> void:
	aware = true


func center() -> Vector3:
	return global_position + Vector3(0.0, center_y, 0.0)


## The damage contract (see the player's enemy contract): crit only changes the effect, the amount is already scaled by the weapon.
## mirrored = damage that came through a quantum link (does not alert neighbours nor bounce back).
func damage(amount: float, crit := false, mirrored := false) -> void:
	if dead or not active:
		return
	hp -= amount
	aware = true
	_bar_t = BAR_SECONDS
	_stagger = 0.25
	_flash = 0.1
	_hit_effect(crit)
	Sfx.play_at(&"hit", center(), -5.0)
	if not mirrored:
		var mgr := Game.enemies as EnemyManager
		if mgr != null:
			mgr.alert_near(global_position, ALERT_RADIUS, self)
		if is_instance_valid(linked) and not linked.dead and linked.active:
			var other := linked
			other.damage(amount, false, true)
			FX.burst(other.center(), Color(0.5, 0.98, 1.0), 8, 6.0, 0.4, 2.0)
	if hp <= 0.0:
		die()


func _hit_effect(_crit: bool) -> void:
	FX.burst(center(), cfg["color"], 4, 4.0, 0.25, 4.0)


func die() -> void:
	if dead:
		return
	dead = true
	hp = minf(hp, 0.0)
	_dead_t = 0.0
	_bar.visible = false
	linked = null
	collision_layer = 0
	if is_in_group(&"enemy"):
		remove_from_group(&"enemy")           # corpses are not targets, minimap dots or explosion victims
	_death_effect()
	Game.score += int(cfg["score"])
	Game.heat += float(cfg["heat"])
	Game.quiet = 0.0
	var p := Game.player
	if is_instance_valid(p) and p.has_method(&"add_energy"):
		p.call(&"add_energy", EnemyTypes.ENERGY_REFUND)
	_drop()
	died.emit(self)


func _death_effect() -> void:
	var c: Color = cfg["color"]
	var pos := center()
	FX.burst(pos, c, 30, 9.0, 0.8, 10.0)
	FX.blast(pos, 2.5 * maxf(0.85, radius), c, 0.35)
	Sfx.play_at(&"boom", pos, -3.0)


func _drop() -> void:
	var m := Game.missions
	if not is_instance_valid(m) or not m.has_method(&"drop"):
		return
	var r := randf()
	var at := Vector3(global_position.x, 0.0, global_position.z)
	if r < 0.3:
		m.call(&"drop", &"health", at)
	elif r < 0.6:
		m.call(&"drop", &"energy", at)


# --- simulation -----------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not Game.is_playing():
		return
	if dead:
		_tick_dead(delta)
		return
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	_stagger = maxf(0.0, _stagger - delta)
	var p := Game.player
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = randf_range(0.6, 1.4)
		_want_clone = randf() < 0.5
	_tgt_ok = _pick_target(p)
	var pos := global_position
	var dx := _tgt.x - pos.x
	var dz := _tgt.z - pos.z
	var d := maxf(sqrt(dx * dx + dz * dz), 0.001)
	if _tgt_ok and not aware and (d < AWARE_DIST or (Game.heat > 0.0 and d < AWARE_HEAT_DIST)):
		aware = true
	_mx = 0.0
	_mz = 0.0
	_speed = 0.0
	if not aware or not _tgt_ok:
		_think_idle(delta)
	else:
		_los_t -= delta
		if _los_t <= 0.0:
			_los_t = randf_range(0.25, 0.4)
			los = d < LOS_RANGE and _line_clear(center(), _tgt)
		_think_aware(delta, dx, dz, d)
		if dead:
			return
	_separate()
	var sp := _speed * (0.35 if _stagger > 0.0 else 1.0)
	_moved = sp
	_step(_mx * sp * delta, _mz * sp * delta)
	_place(delta)
	_animate(delta)
	_update_bar(delta)


func _on_activate() -> void:
	pass


## Target point: the player's chest, or the quantum clone half of the time. Returns false when there is nothing to aim at.
func _pick_target(p: Node3D) -> bool:
	_tgt_clone = false
	if _want_clone:
		var mgr := Game.enemies as EnemyManager
		var c: Node3D = mgr.get_clone() if mgr != null else null
		if c != null:
			_tgt = c.global_position + Vector3(0.0, 1.0, 0.0)
			_tgt_clone = true
			return true
	if not is_instance_valid(p):
		return false
	_tgt = p.call(&"chest_position") if p.has_method(&"chest_position") else p.global_position + Vector3(0.0, 1.2, 0.0)
	return true


func _think_idle(delta: float) -> void:
	var pos := global_position
	_wander_t -= delta
	if _wander_t <= 0.0:
		_wander_t = randf_range(2.0, 5.0)
		_wdir = randf() * TAU if randf() < 0.4 else atan2(home.x - pos.x, home.z - pos.z) - PI
	var hx := home.x - pos.x
	var hz := home.z - pos.z
	var hd := sqrt(hx * hx + hz * hz)
	if hd < 14.0:
		_mx = -sin(_wdir)
		_mz = -cos(_wdir)
		_speed = _idle_speed()
	else:
		_mx = hx / hd
		_mz = hz / hd
		_speed = _idle_speed() * 1.8
	yaw = lerp_angle(yaw, atan2(-_mx, -_mz), 1.0 - exp(-3.0 * delta))


func _idle_speed() -> float:
	return 1.4


func _think_aware(delta: float, dx: float, dz: float, d: float) -> void:
	var speed: float = cfg["speed"]
	var rng: float = cfg["range"]
	yaw = lerp_angle(yaw, atan2(-dx, -dz), 1.0 - exp(-9.0 * delta))
	var ux := dx / d
	var uz := dz / d
	var kamikaze: bool = cfg["kamikaze"]
	if kamikaze:
		_mx = ux
		_mz = uz
		_speed = speed
		if d < 2.4:
			_explode()
		return
	if d > rng * 0.95 or not los:
		_mx = ux
		_mz = uz
		_speed = speed
	elif d < rng * 0.45:
		_mx = -ux
		_mz = -uz
		_speed = speed * 0.8
	else:
		_strafe_t -= delta
		if _strafe_t <= 0.0:
			_strafe_t = randf_range(1.2, 3.0)
			_strafe = -_strafe
		_mx = -uz * _strafe
		_mz = ux * _strafe
		_speed = speed * 0.6
	_fire_t -= delta
	if los and d < rng * 1.15 and _fire_t <= 0.0:
		var f: Vector2 = cfg["fire"]
		_fire_t = randf_range(f.x, f.y)
		_fire()


func _fire() -> void:
	var mgr := Game.enemies as EnemyManager
	if mgr == null:
		return
	var from := muzzle.global_position if muzzle != null else center()
	for i in int(cfg["burst"]):
		mgr.bolt(from, _tgt, type, i * 0.12)
	Sfx.play_at(&"enemy_shot", from, -4.0)


func _explode() -> void:
	Game.explode(center(), 4.5, {"enemy_dmg": 0.0, "car_dmg": 30.0, "player_dmg": float(cfg["dmg"]), "color": cfg["color"]})
	hp = 0.0
	die()


## Keep a little room between enemies.
func _separate() -> void:
	var mgr := Game.enemies as EnemyManager
	if mgr == null:
		return
	var pos := global_position
	for e in mgr.list:
		if e == self or e.dead or not e.active:
			continue
		var ex := pos.x - e.global_position.x
		var ez := pos.z - e.global_position.z
		var ed := sqrt(ex * ex + ez * ez)
		if ed < 2.0 and ed > 0.001:
			_mx += ex / ed * 0.8
			_mz += ez / ed * 0.8


## Move in the XZ plane. Streets have no prop colliders, buildings do: a step into a building is cancelled per axis (slides along walls).
func _step(sx: float, sz: float) -> void:
	var pos := global_position
	var nx := pos.x + sx
	var nz := pos.z + sz
	var city := Game.world as City
	if city != null:
		var m := radius * 0.7
		var ax := signf(sx) * m
		var az := signf(sz) * m
		if city.is_inside_building(Vector3(nx + ax, 1.0, nz + az)):
			if city.is_inside_building(Vector3(nx + ax, 1.0, pos.z + az)):
				nx = pos.x
			if city.is_inside_building(Vector3(pos.x + ax, 1.0, nz + az)):
				nz = pos.z
			if nx == pos.x + sx and nz == pos.z + sz:
				nx = pos.x
				nz = pos.z
	nx = clampf(nx, -WORLD_LIMIT, WORLD_LIMIT)
	nz = clampf(nz, -WORLD_LIMIT, WORLD_LIMIT)
	global_position = Vector3(nx, _ground_y(nx, nz), nz)


## Drones hover with a bob; an operative overrides this to stand on the ground.
func _ground_y(_x: float, _z: float) -> float:
	return _hover + sin(_t * 2.2) * 0.12


func _place(delta: float) -> void:
	rotation.y = yaw
	if model != null:
		_bank = lerpf(_bank, clampf(-_mx * 0.15, -0.2, 0.2), 1.0 - exp(-5.0 * delta))
		model.rotation.z = _bank


func _animate(delta: float) -> void:
	var s := ROTOR_SPEED * delta
	for i in _rotors.size():
		_rotors[i].rotate_y(s if i % 2 == 0 else -s)
	if _flash > 0.0:
		_set_glow(5.0 if _flash > 0.05 else 2.0)


func _tick_dead(delta: float) -> void:
	_dead_t += delta
	if model != null:
		model.rotation.z += delta * 4.0
		model.position.y -= delta * 2.5
	if _dead_t > DEATH_TIME:
		remove = true
		set_physics_process(false)
		visible = false


## Throttled-ray visibility. Origin and target are world points; the ray only sees the world layer (buildings, walls).
func _line_clear(from: Vector3, to: Vector3) -> bool:
	_ray.from = from
	_ray.to = to
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	return hit.is_empty()


# --- visuals --------------------------------------------------------------------------------------------------------

func _build_visual() -> void:
	var m := Game.load_model(String(cfg["model"]))
	uses_model = m != null
	if m == null:
		m = _make_fallback()
	add_child(m)
	model = m
	muzzle = m.get_node_or_null("Muzzle") as Node3D
	for n: String in ["RotorFL", "RotorFR", "RotorRL", "RotorRR"]:
		var r := m.get_node_or_null(n) as Node3D
		if r != null:
			_rotors.append(r)
	DynamicFill.apply(m, cfg["color"])
	for mi: MeshInstance3D in DynamicFill._meshes(m):
		if mi.name != &"Body":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF      # rotors and the eye are small: every shadow-cast surface is a draw call per cascade
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(s) as BaseMaterial3D
			if mat != null and mat.emission_enabled and mat.emission_energy_multiplier >= 1.0 and (mi.name == &"Eye" or String(mat.resource_name).contains("Glow")):
				_glow.append(mat)


func _set_glow(energy: float) -> void:
	for m in _glow:
		m.emission_energy_multiplier = energy


## Primitive stand-in with the same node names as the real model (Body, Eye, Muzzle, RotorXX).
func _make_fallback() -> Node3D:
	var root := Node3D.new()
	var col: Color = cfg["color"]
	var s := radius / 0.95
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.5, 1.0) * s
	body.mesh = bm
	bm.material = _flat(Color(0.16, 0.16, 0.2), 0.6)
	body.position = Vector3(0.0, center_y, 0.0)
	root.add_child(body)
	var eye := MeshInstance3D.new()
	eye.name = "Eye"
	var sm := SphereMesh.new()
	sm.radius = 0.14 * s
	sm.height = 0.28 * s
	var em := _flat(Color.BLACK, 0.5)
	em.emission_enabled = true
	em.emission = col
	em.emission_energy_multiplier = 2.0
	em.resource_name = "Glow"
	sm.material = em
	eye.mesh = sm
	eye.position = Vector3(0.0, center_y + 0.05, -0.5 * s)
	root.add_child(eye)
	var mz := Node3D.new()
	mz.name = "Muzzle"
	mz.position = Vector3(0.0, center_y, -0.55 * s)
	root.add_child(mz)
	var k := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var r := MeshInstance3D.new()
			r.name = ["RotorFL", "RotorFR", "RotorRL", "RotorRR"][k]
			k += 1
			var cm := CylinderMesh.new()
			cm.top_radius = 0.28 * s
			cm.bottom_radius = 0.28 * s
			cm.height = 0.03
			cm.material = _flat(Color(0.1, 0.1, 0.12), 0.7)
			r.mesh = cm
			r.position = Vector3(sx * 0.55 * s, center_y + 0.25 * s, sz * 0.45 * s)
			root.add_child(r)
	return root


static func _flat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = 0.4
	return m


func _build_bar() -> void:
	if _bar_mesh == null:
		_bar_mesh = QuadMesh.new()
		_bar_mesh.size = Vector2(BAR_WIDTH, 0.12)
		_bar_bg = _unshaded(Color(0.13, 0.04, 0.09))
		_bar_fg = _unshaded(Color(1.0, 0.27, 0.4))
	_bar = Node3D.new()
	_bar.top_level = true
	_bar.visible = false
	add_child(_bar)
	var bg := MeshInstance3D.new()
	bg.mesh = _bar_mesh
	bg.material_override = _bar_bg
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.add_child(bg)
	_bar_fill = MeshInstance3D.new()
	_bar_fill.mesh = _bar_mesh
	_bar_fill.material_override = _bar_fg
	_bar_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_fill.position.z = 0.004
	_bar.add_child(_bar_fill)


static func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.disable_receive_shadows = true
	return m


func _bar_height() -> float:
	return center_y + radius + 0.55


func _update_bar(delta: float) -> void:
	if _bar_t <= 0.0:
		return
	_bar_t -= delta
	_bar.visible = _bar_t > 0.0 and not dead
	if not _bar.visible:
		return
	var cam := Game.camera
	var gp := global_position
	_bar.global_position = Vector3(gp.x, gp.y + _bar_height(), gp.z)
	if is_instance_valid(cam):
		_bar.global_basis = cam.global_basis
	var f := clampf(hp / max_hp, 0.001, 1.0)
	_bar_fill.scale.x = f
	_bar_fill.position.x = -BAR_WIDTH * 0.5 * (1.0 - f)
