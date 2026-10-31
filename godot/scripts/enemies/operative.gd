class_name Operative
extends Drone
## Observer Corp rifleman (hp 80): the human enemy. Patrols near home, notices the player (or the quantum clone), takes aim for a moment, fires short
## three-round bursts with a tracer and a spread that grows with distance, strafes between bursts, backs off when pressed, flanks when it has no line of
## sight for a while, and calls for help when hit (alerts everyone within 50 m). Street props have no colliders, so there is no cover system: the strafe and
## the aim windup stand in for peeking.
## Visuals: Game.load_model("operative"), an articulated skinned model (one draw call) posed by CharacterRig: stride cycle with knee bends along the real
## speed and direction (strafe, back-pedal), rifle at low ready while patrolling and shouldered for the aim windup and the burst (both hands on the rifle, the
## head follows the aim pitch), recoil kick per round, hit flinch, and a death fall (the knees buckle, the body drops onto its side and goes limp).
## Without the model: a primitive humanoid with LegL / LegR (swung by the speed). Hits show dust and armour chips, blood only behind Game.graphic_violence.

const HELP_RADIUS := 50.0
const CORPSE_TIME := 4.0
const FALL_TIME := 0.45
const STRIDE_RAD_PER_M := 3.2
const LEG_AMP := 0.62
const FLANK_AFTER := 2.5
const STRIDE_RATE := 1.7               ## stride phase per metre travelled (the rig)
const READY_IDLE := 0.45               ## rifle at low ready while patrolling
const READY_AWARE := 0.8

var leg_l: Node3D                      ## hip pivots (the primitive's legs hang from them; with the model they mirror the thigh swing)
var leg_r: Node3D
var rig: CharacterRig

var _aim_t := 0.0
var _burst_left := 0
var _shot_t := 0.0
var _no_los := 0.0
var _flank := 1.0
var _stride := 0.0
var _roll_sign := 1.0
var _lean := 0.0
var _volley_origin := Vector3.ZERO
var _phase := 0.0
var _amp := 0.0
var _dir := Vector2(0.0, 1.0)         ## smoothed body-space movement direction (x right, y forward)
var _ready := READY_IDLE
var _aim_pitch := 0.0
var _kick := 0.0
var _flinch := 0.0
var _clock := 0.0
var _buckle := 0.0


func _make_shape() -> Shape3D:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.5
	return cap


func _build_visual() -> void:
	super._build_visual()
	rig = CharacterRig.find(model) if uses_model else null
	_restore_baked_glow()
	var mirror_body: MeshInstance3D = null
	if rig != null:
		mirror_body = rig.rest_mesh
		for n: String in ["WristL", "WristR", "MagWell", "MagPouch"]:
			var m := model.get_node_or_null(n)
			if m != null:
				model.remove_child(m)
				m.free()
		leg_l = Node3D.new()
		leg_l.name = "LegL"
		leg_r = Node3D.new()
		leg_r.name = "LegR"
		model.add_child(leg_l)
		model.add_child(leg_r)
		leg_l.position = Vector3(-0.1, 0.93, 0.0)
		leg_r.position = Vector3(0.1, 0.93, 0.0)
	else:
		leg_l = model.get_node_or_null("LegL") as Node3D
		leg_r = model.get_node_or_null("LegR") as Node3D
		mirror_body = model.get_node_or_null("Body") as MeshInstance3D
	if is_instance_valid(Game.world) and Game.world.has_method(&"get_mirror_root") and mirror_body != null:
		var proxy := MirrorProxy.new()
		add_child(proxy)
		var arr: Array[MeshInstance3D] = [mirror_body]
		proxy.track(arr)


## DynamicFill recolours "Glow" surfaces, but the baked character has ONE atlas material ("Gear") whose emission texture already carries the red optic slit,
## the trim lights and the status strips: DynamicFill's faint fill emission would dim all of that, so the imported emission values are put back.
func _restore_baked_glow() -> void:
	for mi: MeshInstance3D in DynamicFill._meshes(model):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si) as BaseMaterial3D
			var ov := mi.get_surface_override_material(si) as BaseMaterial3D
			if src != null and ov != null and src.resource_name == "Gear" and src.emission_enabled:
				ov.emission = src.emission
				ov.emission_energy_multiplier = src.emission_energy_multiplier
				if RenderingServer.get_current_rendering_method() == "gl_compatibility":
					ov.albedo_color = ov.albedo_color * 0.6          # that renderer lights the same scene much brighter


func _on_activate() -> void:
	_aim_t = 0.0
	_burst_left = 0
	_shot_t = 0.0
	_no_los = 0.0
	_flank = 1.0 if randf() < 0.5 else -1.0
	_stride = 0.0
	_lean = 0.0
	_phase = 0.0
	_amp = 0.0
	_ready = READY_IDLE
	_aim_pitch = 0.0
	_kick = 0.0
	_flinch = 0.0
	_buckle = 0.0
	if leg_l != null:
		leg_l.rotation.x = 0.0
	if leg_r != null:
		leg_r.rotation.x = 0.0
	if rig != null:
		rig.reset()


func _idle_speed() -> float:
	return float(cfg["walk"])


func _ground_y(x: float, z: float) -> float:
	var city := Game.world as City
	if city != null:
		return city.ground_height(x, z, global_position.y + 1.0)
	return 0.0


func _hit_effect(crit: bool) -> void:
	_flinch = 1.0 if crit else 0.7
	var c := center()
	if Game.graphic_violence:
		FX.burst(c, Color(0.5, 1.0, 0.2), 6, 3.5, 0.5, 9.0, 1.8)          # Vael ichor, not blood
	else:
		FX.burst(c, Color(0.85, 0.8, 0.7), 5, 2.5, 0.5, 3.0, 2.0)     # dust off the plates
		FX.burst(c, Color(1.0, 0.82, 0.45), 3 if not crit else 5, 5.0, 0.2, 9.0)   # chips and sparks
	if _burst_left > 0 and _stagger > 0.0:
		_burst_left = maxi(0, _burst_left - 1)


func alert() -> void:
	aware = true


func damage(amount: float, crit := false, mirrored := false) -> void:
	var was_aware := aware
	super.damage(amount, crit, mirrored)
	if not was_aware and not dead and not mirrored:
		var mgr := Game.enemies as EnemyManager
		if mgr != null:
			mgr.alert_near(global_position, HELP_RADIUS, self)     # calls for help


func _death_effect() -> void:
	var c := center()
	if Game.graphic_violence:
		ichor(c, 0.8)
	FX.burst(c, Color(0.85, 0.8, 0.7), 8, 3.0, 0.6, 3.0, 2.5)
	FX.burst(c, Color(1.0, 0.8, 0.4), 8, 6.0, 0.3, 10.0)
	Sfx.play_at(&"hit", c, 0.0, 0.8)
	_roll_sign = 1.0 if randf() < 0.5 else -1.0
	_burst_left = 0
	_aim_t = 0.0


func _think_aware(delta: float, dx: float, dz: float, d: float) -> void:
	var speed: float = cfg["speed"]
	var rng: float = cfg["range"]
	yaw = lerp_angle(yaw, atan2(-dx, -dz), 1.0 - exp(-8.0 * delta))
	var ux := dx / d
	var uz := dz / d
	_no_los = 0.0 if los else _no_los + delta
	if d > rng * 0.95 or not los:
		_mx = ux
		_mz = uz
		_speed = speed
		if not los and _no_los > FLANK_AFTER:         # no sight line for a while: come in at an angle
			_mx = ux * 0.6 - uz * 0.8 * _flank
			_mz = uz * 0.6 + ux * 0.8 * _flank
	elif d < rng * 0.4:
		_mx = -ux
		_mz = -uz
		_speed = speed * 0.7
	else:
		_strafe_t -= delta
		if _strafe_t <= 0.0:
			_strafe_t = randf_range(1.0, 2.5)
			_strafe = -_strafe
		_mx = -uz * _strafe
		_mz = ux * _strafe
		_speed = speed * 0.45
	# aim, then a short burst, then a pause
	if _aim_t > 0.0:
		_speed *= 0.2
		_aim_t -= delta
		if _aim_t <= 0.0:
			_burst_left = int(cfg["burst"])
			_shot_t = 0.0
			_volley_origin = _muzzle_pos()
			Sfx.play_at(&"enemy_shot", _volley_origin, -4.0)
	elif _burst_left > 0:
		_speed *= 0.3
		_shot_t -= delta
		if _shot_t <= 0.0:
			_shoot(d)
			_burst_left -= 1
			_shot_t = float(cfg["burst_gap"])
			if _burst_left == 0:
				var f: Vector2 = cfg["fire"]
				_fire_t = randf_range(f.x, f.y)
	else:
		_fire_t -= delta
		if los and d < rng * 1.15 and _fire_t <= 0.0:
			_aim_t = float(cfg["aim_time"])


## Attack telegraph: the rifle charges during the aim windup (a flare at the muzzle and an aim line), full during the burst.
func threat_charge() -> float:
	if dead:
		return 0.0
	if _aim_t > 0.0:
		return clampf(1.0 - _aim_t / float(cfg["aim_time"]), 0.0, 1.0)
	return 1.0 if _burst_left > 0 else 0.0


func shows_aim_line() -> bool:
	return _aim_t > 0.0 and _tgt_ok


func muzzle_world() -> Vector3:
	return _muzzle_pos()


func mark_size() -> float:
	return 2.5


func death_progress() -> float:
	return clampf(_dead_t / 0.7, 0.0, 1.0)


func _muzzle_pos() -> Vector3:
	return muzzle.global_position if muzzle != null else center() + Vector3(0.0, 0.3, 0.0)


## One round: hitscan with a spread that grows with distance. The tracer ends at the first world hit or past the target.
func _shoot(d: float) -> void:
	var origin := _muzzle_pos()
	var aim := _tgt
	var spread: float = float(cfg["spread"]) + float(cfg["spread_per_m"]) * d
	var dir := (aim - origin).normalized()
	var off := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	dir = (dir + (off - dir * off.dot(dir)) * spread).normalized()
	var t_close := maxf((aim - origin).dot(dir), 0.0)
	var closest := origin + dir * t_close
	var miss := closest.distance_to(aim)
	var end := origin + dir * (t_close + 6.0)
	_ray.from = origin
	_ray.to = end
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	var blocked := false
	if not hit.is_empty():
		end = hit["position"]
		blocked = origin.distance_to(end) < t_close - 0.3
	_kick = 1.0
	FX.tracer(origin, end, Color(1.0, 0.45, 0.35))
	FX.burst(origin, Color(1.0, 0.8, 0.45), 3, 2.5, 0.08, 0.0)
	var mgr := Game.enemies as EnemyManager
	var p := Game.player
	if blocked or mgr == null:
		return
	if _tgt_clone:
		if miss < 0.6:
			mgr.hit_clone()
		return
	if not is_instance_valid(p):
		return
	var reach := 1.5 if p.get(&"vehicle") != null else 0.5
	if miss < reach:
		p.call(&"damage", float(cfg["dmg"]), origin)


func _animate(delta: float) -> void:
	if rig == null:
		_animate_legs_only(delta)
		return
	var cfg_speed: float = cfg["speed"]
	var moving := _moved > 0.1
	var v := Vector3(_mx, 0.0, _mz) * _moved
	var local := v.rotated(Vector3.UP, -yaw)                 # body space: x right, z back
	var speed := v.length()
	_amp = lerpf(_amp, minf(1.0, speed / 4.0) if moving else 0.0, 1.0 - exp(-12.0 * delta))
	if speed > 0.4:
		var td := Vector2(local.x, -local.z) / speed
		_dir += (td - _dir) * (1.0 - exp(-14.0 * delta))
		if _dir.length_squared() < 0.0004:
			_dir = td
	_phase += delta * speed * STRIDE_RATE
	_clock += delta
	var m := _dir.normalized() if _dir.length_squared() > 0.0001 else Vector2(0.0, 1.0)
	var firing := _aim_t > 0.0 or _burst_left > 0
	var want_ready := 1.0 if firing else (READY_AWARE if aware else READY_IDLE)
	_ready = lerpf(_ready, want_ready, 1.0 - exp(-9.0 * delta))
	var want_pitch := 0.0
	if aware and not dead:
		var o := _muzzle_pos()
		var hd := maxf(Vector2(_tgt.x - o.x, _tgt.z - o.z).length(), 1.0)
		want_pitch = clampf(atan2(_tgt.y - o.y, hd) * 0.6, -0.55, 0.65)
	_aim_pitch = lerpf(_aim_pitch, want_pitch, 1.0 - exp(-10.0 * delta))
	_kick = maxf(0.0, _kick - delta * 7.0)
	_flinch = maxf(0.0, _flinch - delta * 5.0)
	var calm := 1.0 - minf(1.0, speed / 2.0)
	rig.phase = _phase
	rig.amp = _amp
	rig.run = clampf(speed / (cfg_speed * 1.4), 0.0, 1.0)
	rig.fw = m.y
	rig.lw = m.x
	rig.air = 0.0
	rig.aim_pitch = _aim_pitch
	rig.lean = -0.05 * _amp - (0.1 if _stagger > 0.0 else 0.0)
	rig.twist = sin(_phase) * 0.06 * _amp
	rig.roll = -local.x * 0.012
	rig.breathe = sin(_clock * 2.0) * 0.018 * calm
	rig.recoil = _kick
	rig.flinch = _flinch
	rig.ready = _ready
	rig.sprint = 0.0
	rig.reload = -1.0
	rig.clock = _clock
	rig.dead = 0.0
	rig.knee_buckle = 0.0
	rig.apply()
	if muzzle != null:
		muzzle.transform = rig.muzzle_transform()
	if leg_l != null:
		leg_l.basis = Basis.from_euler(Vector3(rig.hip_l.x, 0.0, rig.hip_l.y))
		leg_r.basis = Basis.from_euler(Vector3(rig.hip_r.x, 0.0, rig.hip_r.y))


## The primitive operative (no model): legs swing with the real speed, the body leans when staggered.
func _animate_legs_only(delta: float) -> void:
	if leg_l == null or leg_r == null:
		return
	var k := clampf(_moved / float(cfg["speed"]), 0.0, 1.0)
	_stride += _moved * delta * STRIDE_RAD_PER_M
	var swing := sin(_stride) * LEG_AMP * minf(1.0, 0.25 + k)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, swing if _moved > 0.1 else 0.0, 1.0 - exp(-14.0 * delta))
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -swing if _moved > 0.1 else 0.0, 1.0 - exp(-14.0 * delta))
	_lean = lerpf(_lean, 0.12 if _stagger > 0.0 else 0.0, 1.0 - exp(-12.0 * delta))
	model.rotation.x = _lean


func _place(delta: float) -> void:
	rotation.y = yaw          # no banking for a human


func _tick_dead(delta: float) -> void:
	_dead_t += delta
	var k := clampf(_dead_t / FALL_TIME, 0.0, 1.0)
	var e := 1.0 - (1.0 - k) * (1.0 - k)
	if rig != null:
		# the knees give way first, the body drops onto its side, then everything goes limp
		_buckle = clampf(_dead_t / (FALL_TIME * 0.5), 0.0, 1.0)
		_kick = 0.0
		_flinch = maxf(0.0, _flinch - delta * 3.0)
		rig.phase = _phase
		rig.amp = lerpf(_amp, 0.0, k)
		rig.ready = lerpf(_ready, 0.0, k)
		rig.recoil = 0.0
		rig.flinch = _flinch
		rig.knee_buckle = _buckle * (1.0 - e * 0.6)
		rig.dead = clampf((_dead_t - FALL_TIME * 0.3) / (FALL_TIME * 0.9), 0.0, 1.0)
		rig.reload = -1.0
		rig.apply()
		if leg_l != null:
			leg_l.basis = Basis.from_euler(Vector3(rig.hip_l.x, 0.0, rig.hip_l.y))
	model.rotation = Vector3(0.0, 0.0, _roll_sign * e * PI * 0.5)
	model.position.y = 0.32 * e
	if rig == null and leg_l != null:
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.5, 1.0 - exp(-6.0 * delta))
	if _dead_t > CORPSE_TIME:
		FX.burst(global_position + Vector3(0.0, 0.2, 0.0), Color(0.6, 0.6, 0.65), 6, 1.5, 0.5, 1.0, 2.0)
		remove = true
		set_physics_process(false)
		visible = false


func _make_fallback() -> Node3D:
	var root := Node3D.new()
	var fabric := _flat(Color(0.12, 0.13, 0.16), 0.8)
	var armor := _flat(Color(0.2, 0.22, 0.26), 0.55)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var tm := CapsuleMesh.new()
	tm.radius = 0.24
	tm.height = 0.72
	tm.material = armor
	body.mesh = tm
	body.position = Vector3(0.0, 1.3, 0.0)
	root.add_child(body)
	var head := MeshInstance3D.new()
	head.name = "Helmet"
	var hm := SphereMesh.new()
	hm.radius = 0.15
	hm.height = 0.3
	hm.material = armor
	head.mesh = hm
	body.add_child(head)
	head.position = Vector3(0.0, 0.5, 0.0)
	var visor := MeshInstance3D.new()
	visor.name = "Eye"
	var vm := BoxMesh.new()
	vm.size = Vector3(0.2, 0.05, 0.05)
	var gm := _flat(Color.BLACK, 0.5)
	gm.emission_enabled = true
	gm.emission = cfg["color"]
	gm.emission_energy_multiplier = 2.0
	gm.resource_name = "Glow"
	vm.material = gm
	visor.mesh = vm
	visor.position = Vector3(0.0, 0.52, -0.14)
	body.add_child(visor)
	var rifle := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.07, 0.09, 0.9)
	rm.material = _flat(Color(0.08, 0.08, 0.1), 0.5)
	rifle.mesh = rm
	rifle.position = Vector3(0.2, 0.12, -0.5)
	body.add_child(rifle)
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "LegL" if side < 0.0 else "LegR"
		var lm := CapsuleMesh.new()
		lm.radius = 0.1
		lm.height = 0.9
		lm.material = fabric
		leg.position = Vector3(side * 0.1, 0.93, 0.0)
		var inner := MeshInstance3D.new()
		inner.mesh = lm
		inner.position = Vector3(0.0, -0.46, 0.0)
		leg.add_child(inner)
		root.add_child(leg)
	var mz := Node3D.new()
	mz.name = "Muzzle"
	mz.position = Vector3(0.12, 1.38, -1.0)
	root.add_child(mz)
	return root
