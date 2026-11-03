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
const DROP_DELAY := 0.66        ## a death drops its pickup late in the death animation (the explosion peak of four deaths at once has faded; the pickups' draws do not stack on it)
const TELEGRAPH := 0.45          ## seconds before a shot that the muzzle charges and the aim line shows (the attack telegraph)
const BAR_SECONDS := 3.0
const ROTOR_SPEED := 46.0
## The living drones have no rotors: the `Fins` node (a frill of tendrils, a ring of thorns, a skirt of cilia) turns and pulses. rate rad/s, pulse = scale amplitude, axis in the model frame.
const FIN_ANIM := {
	&"sentinel": {"rate": 0.8, "pulse": 0.14, "axis": Vector3.UP, "freq": 3.4},
	&"striker": {"rate": 5.0, "pulse": 0.06, "axis": Vector3.BACK, "freq": 9.0},
	&"heavy": {"rate": 2.4, "pulse": 0.07, "axis": Vector3.UP, "freq": 5.0},
}

var type: StringName = &"sentinel"
var cfg: Dictionary = {}
var hp := 60.0
var max_hp := 60.0
var radius := 0.95
var aware := false
var aware_dist := AWARE_DIST        ## sight range; interiors lower it for stealthy guards (scripts/interiors_gameplay/interior_actors.gd), activate() resets it
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
var _off := 0.0              ## COLLAPSE: seconds left switched off (no thinking, no shooting, glow flickers)
var _hover := 0.35
var _rotors: Array[Node3D] = []
var _fins: Node3D                      ## the `Fins` node of the living models (null for the primitive stand-in, which spins its rotors)
var _tele := 0.0                       ## 0..1: how far the next shot is charged (EnemyMarks draws the telegraph from it)
var _base_scale := 1.0
var _flare := 0.0                      ## 0..1: the striker's thorns flare as it closes in to burst
var _glow: Array[BaseMaterial3D] = []
var _body_mi: MeshInstance3D           ## the `Body` mesh (shadow caster) of the model, for the distance LOD
var _lights: Array[Light3D] = []
var _lod_lights := true
var _drop_pending := false
var _lod_shadow := true                ## LOD state (update_lod): casts a shadow / small parts shown / model shown
var _lod_parts := true
var _lod_shown := true
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
	aware_dist = AWARE_DIST
	reinforce = is_reinforce
	linked = null
	los = false
	home = Vector3(pos.x, 0.0, pos.z)
	_t = randf() * 10.0
	_dead_t = 0.0
	_flare = 0.0
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
	_off = 0.0
	yaw = randf() * TAU
	rotation = Vector3(0.0, yaw, 0.0)
	global_position = Vector3(pos.x, _hover, pos.z)
	if model != null:
		model.rotation = Vector3.ZERO
		model.position = Vector3.ZERO
		model.scale = Vector3.ONE * _base_scale
	_tele = 0.0
	_drop_pending = false
	_set_glow(2.0)
	_reset_lod()
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
## Weapon hit reaction: power 0.4 (carbine) .. 1.5 (lance) lengthens the stagger (the body slows and leans) and deepens the flinch.
func stagger(power: float) -> void:
	if dead:
		return
	_stagger = maxf(_stagger, 0.15 + 0.25 * power)
	if "_flinch" in self:
		set("_flinch", maxf(float(get("_flinch")), clampf(0.4 + 0.4 * power, 0.0, 1.0)))


## COLLAPSE: the drone is flipped off for `seconds` (it drifts to a stop, does not think or shoot, its glow flickers).
func disable(seconds: float) -> void:
	if dead or not active:
		return
	_off = maxf(_off, seconds)
	_stagger = maxf(_stagger, seconds)


func is_disabled() -> bool:
	return _off > 0.0


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
	if hp <= 0.0:
		return                                   # the killing blow gets the death effect only
	_burst(center(), cfg["color"], 4, 4.0, 0.25, 4.0)


## A decorative particle burst through the manager's budget (each live emitter is a draw call: four enemies dying at once must not add dozens). Without a manager it just plays.
func _burst(pos: Vector3, color: Color, count: int, speed: float, life: float, gravity: float, size := 1.0) -> void:
	var mgr := Game.enemies as EnemyManager
	if mgr == null or mgr.fx_token():
		FX.burst(pos, color, count, speed, life, gravity, size)


func die() -> void:
	if dead:
		return
	dead = true
	hp = minf(hp, 0.0)
	_dead_t = 0.0
	_flare = 0.0
	linked = null
	collision_layer = 0
	if is_in_group(&"enemy"):
		remove_from_group(&"enemy")           # corpses are not targets, minimap dots or explosion victims
	_death_effect()
	_drop_pending = true
	Game.score += int(cfg["score"])
	Game.heat += float(cfg["heat"])
	Game.quiet = 0.0
	var p := Game.player
	if is_instance_valid(p) and p.has_method(&"add_energy"):
		p.call(&"add_energy", EnemyTypes.ENERGY_REFUND)
	died.emit(self)


func _death_effect() -> void:
	var c: Color = cfg["color"]
	var pos := center()
	var mgr := Game.enemies as EnemyManager
	if mgr == null or mgr.death_blast():
		FX.blast(pos, 2.5 * maxf(0.85, radius), c, 0.35)             # the burst: fireball, ring, sparks (one pooled slot), then the shell dissolves
	else:
		_burst(pos, c, 18, 6.0, 0.5, 2.0, 2.2)                       # the tier's blast slots are busy (4 deaths at once): one particle draw (if the budget allows) instead of a slot
	if Game.graphic_violence:
		ichor(pos, 1.0)
	Sfx.play_at(&"boom", pos, -3.0)


## Vael ichor: a spray of acid-green drops and a low cloud of teal goo. Only behind Game.graphic_violence (the non-violent build dissolves into light motes).
static func ichor(pos: Vector3, k: float) -> void:
	FX.burst(pos, Color(0.5, 1.0, 0.2), int(24.0 * k), 7.0 * k, 1.0, 12.0, 2.6)


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
	elif r < 0.7 and cfg.get("drops_weapon", true) and m.has_method(&"drop_weapon"):
		m.call(&"drop_weapon", WeaponDefs.pick_drop(randf(), randf()), at)


# --- simulation -----------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not Game.is_playing() or (TestMode.freeze and not dead):
		return
	if dead:
		_tick_dead(delta)
		return
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	_stagger = maxf(0.0, _stagger - delta)
	if _off > 0.0:
		_off -= delta
		_mx = 0.0
		_mz = 0.0
		_speed = 0.0
		_moved = 0.0
		_tele = 0.0
		_place(delta)
		_animate(delta)
		_bar_t = maxf(_bar_t - delta, 0.0)
		return
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
	if _tgt_ok and not aware and (d < aware_dist * Weather.sight_mult() or (Game.heat > 0.0 and d < AWARE_HEAT_DIST)):
		aware = true
	_mx = 0.0
	_mz = 0.0
	_speed = 0.0
	_tele = 0.0
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
	_bar_t = maxf(_bar_t - delta, 0.0)


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
	if los and d < rng * 1.15:
		_tele = clampf(1.0 - _fire_t / TELEGRAPH, 0.0, 1.0)       # the muzzle charges and the aim line shows for the last 0.45 s
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
	if InteriorSpace.contains_xz(pos.x, pos.z):      # inside a generated interior: slide along its walls and props; the street map's clamp and buildings do not apply there
		var rs := InteriorSpace.resolve(pos.x, pos.z, nx, nz, radius * 0.7)
		global_position = Vector3(rs.x, _ground_y(rs.x, rs.y), rs.y)
		return
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
	return _hover + sin(_t * 2.2) * 0.12 + (InteriorSpace.floor_y if InteriorSpace.contains_xz(global_position.x, global_position.z) else 0.0)


func _place(delta: float) -> void:
	rotation.y = yaw
	if model != null:
		_bank = lerpf(_bank, clampf(-_mx * 0.15, -0.2, 0.2), 1.0 - exp(-5.0 * delta))
		model.rotation.z = _bank


func _animate(delta: float) -> void:
	var s := ROTOR_SPEED * delta
	for i in _rotors.size():
		_rotors[i].rotate_y(s if i % 2 == 0 else -s)
	var flare_target := 0.0
	if bool(cfg["kamikaze"]) and aware and Game.player != null:
		flare_target = clampf((9.0 - global_position.distance_to((Game.player as Node3D).global_position)) / 5.0, 0.0, 1.0)
	_flare = move_toward(_flare, flare_target, delta * 3.0)
	if _fins != null:
		var fa: Dictionary = FIN_ANIM.get(type, FIN_ANIM[&"sentinel"])
		var spin: float = fa["rate"] * (1.0 + 4.0 * _flare)
		_fins.rotate_object_local(fa["axis"], spin * delta)
		var pulse: float = sin(_t * float(fa["freq"]) * (1.0 + _flare)) * float(fa["pulse"])
		var k := 1.0 + 0.55 * _flare
		if type == &"sentinel":                                      # a jelly pulse: long and thin, then short and wide
			_fins.scale = Vector3(k * (1.0 - pulse * 0.4), k * (1.0 + pulse), k * (1.0 - pulse * 0.4))
		else:
			_fins.scale = Vector3(k * (1.0 + pulse), k * (1.0 + pulse), k * (1.0 + pulse))
	if _off > 0.0:
		_set_glow(2.0 if int(floor(_t * 14.0)) % 2 == 0 else 0.2)
	elif _flash > 0.0:
		_set_glow(5.0 if _flash > 0.05 else 2.0)
	elif _flare > 0.02:
		_set_glow(2.0 + 2.2 * _flare)


## The pickup of a death appears DROP_DELAY after it (both death animations call this).
func _tick_drop() -> void:
	if _drop_pending and _dead_t >= DROP_DELAY:
		_drop_pending = false
		_drop()


func _tick_dead(delta: float) -> void:
	_dead_t += delta
	_tick_drop()
	var k := clampf(_dead_t / DEATH_TIME, 0.0, 1.0)
	if model != null:
		model.rotation.z += delta * 4.0
		model.position.y -= delta * 2.5
		model.scale = Vector3.ONE * _base_scale * (1.0 - 0.85 * k * k)            # dissolve: it shrinks away while it burns white-hot
	_set_glow(2.0 + 9.0 * sin(k * PI))
	if _dead_t > DEATH_TIME:
		_burst(center(), cfg["color"], 14, 5.0, 0.8, -1.5, 1.6)                   # the last motes of light drift up
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
	var m: Node3D = CharacterImport.instantiate(String(cfg["body"])) if cfg.has("body") else Game.load_model(String(cfg["model"]))   # "body": imported creature kit (assets_incoming/characters), falls back to the model
	uses_model = m != null
	if m == null:
		m = _make_fallback()
	_base_scale = float(cfg.get("scale", 1.0))
	m.scale = Vector3.ONE * _base_scale
	add_child(m)
	model = m
	muzzle = m.get_node_or_null("Muzzle") as Node3D
	_fins = m.get_node_or_null("Fins") as Node3D
	for n: String in ["RotorFL", "RotorFR", "RotorRL", "RotorRR"]:
		var r := m.get_node_or_null(n) as Node3D
		if r != null:
			_rotors.append(r)
	_lights = DynamicFill.trim_lights(m)                   # the model's own fill / rim / eye lights stay (a trooper is a black cut-out without them), on only within PerfTiers.light_range()
	DynamicFill.apply(m, cfg["color"])
	for mi: MeshInstance3D in DynamicFill._meshes(m):
		if mi.name == &"Body" and _body_mi == null:
			_body_mi = mi
		if mi.name != &"Body":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF      # fins, rotors and the eye are small: every shadow-cast surface is a draw call per cascade
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(s) as BaseMaterial3D
			if mat != null and mat.emission_enabled and mat.emission_energy_multiplier >= 1.0 and (mi.name == &"Eye" or String(mat.resource_name).contains("Glow")):
				_glow.append(mat)


## Distance LOD (EnemyManager calls it a few times a second with the camera distance): the shadow only within PerfTiers.SHADOW_RANGE, the small parts (fins) within
## PART_RANGE, the whole model hidden beyond MODEL_RANGE (the marks stop at 90 m). Hysteresis, so nothing flickers at a border; only changes are written.
func update_lod(dist: float) -> void:
	var sh := Game.quality >= 1 and dist < PerfTiers.shadow_range() + (4.0 if _lod_shadow else 0.0)
	if sh != _lod_shadow:
		_lod_shadow = sh
		_apply_shadow(sh)
	var lit := dist < PerfTiers.light_range(Game.quality) + (4.0 if _lod_lights else 0.0)
	if lit != _lod_lights:
		_lod_lights = lit
		DynamicFill.set_lights_visible(_lights, lit)
	var parts := dist < PerfTiers.PART_RANGE + (6.0 if _lod_parts else 0.0)
	if parts != _lod_parts:
		_lod_parts = parts
		_apply_parts(parts)
	var shown := dist < PerfTiers.MODEL_RANGE + (10.0 if _lod_shown else 0.0)
	if shown != _lod_shown:
		_lod_shown = shown
		if model != null:
			model.visible = shown


func _reset_lod() -> void:
	_lod_shown = true
	_lod_parts = true
	_lod_lights = true
	DynamicFill.set_lights_visible(_lights, true)
	_lod_shadow = Game.quality >= 1
	if model != null:
		model.visible = true
	_apply_parts(true)
	_apply_shadow(_lod_shadow)


func _apply_shadow(on: bool) -> void:
	if _body_mi != null:
		_body_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _apply_parts(on: bool) -> void:
	if _fins != null:
		_fins.visible = on


## Pre-warm: show every mark of this enemy (rim ring, muzzle flare and aim line, health bar) on the next refresh. Only used while the game is not playing (the loading overlay).
func warm_marks() -> void:
	_tgt_ok = true                              # the aim line needs a target
	_tgt = global_position + Vector3(0.0, 1.0, 6.0)
	_tele = 0.6
	_bar_t = BAR_SECONDS
	_flash = 0.1


func lod_state() -> Dictionary:
	return {"shadow": _lod_shadow, "parts": _lod_parts, "shown": _lod_shown, "lights": _lod_lights}


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


## --- EnemyMarks API (scripts/enemies/enemy_marks.gd draws the threat marker, the attack telegraph and the health bar for every enemy) ---------------

func mark_color() -> Color:
	var c: Color = cfg["color"]
	return Color(minf(c.r * 1.25, 1.0), minf(c.g * 1.25, 1.0), minf(c.b * 1.25, 1.0))


## World diameter of the threat ring (not the collider).
func mark_size() -> float:
	return radius * 2.5


## 0..1: how far the next attack is charged (a striker: how close it is to bursting).
func threat_charge() -> float:
	if dead:
		return 0.0
	return _flare if bool(cfg["kamikaze"]) else _tele


func muzzle_world() -> Vector3:
	return muzzle.global_position if muzzle != null else center()


func aim_point() -> Vector3:
	return _tgt


func shows_aim_line() -> bool:
	return not bool(cfg["kamikaze"]) and _tele > 0.0 and _tgt_ok


func hit_flash() -> float:
	return clampf(_flash / 0.1, 0.0, 1.0)


## Seconds the health bar stays up after a hit (0 = hidden).
func bar_time() -> float:
	return 0.0 if dead else maxf(_bar_t, 0.0)


func death_progress() -> float:
	return clampf(_dead_t / DEATH_TIME, 0.0, 1.0)
