class_name Operative
extends Drone
## Observer Corp rifleman (hp 80): the human enemy. Patrols near home, notices the player (or the quantum clone), takes aim for a moment, fires short
## three-round bursts with a tracer and a spread that grows with distance, strafes between bursts, backs off when pressed, flanks when it has no line of
## sight for a while, and calls for help when hit (alerts everyone within 50 m). Street props have no colliders, so there is no cover system: the strafe and
## the aim windup stand in for peeking.
## Visuals: Game.load_model("operative") (Body, LegL, LegR, Muzzle) or a primitive humanoid with the same node names. The legs swing with the real speed.
## Hits show dust and armour chips, blood only behind Game.graphic_violence. Death: the body folds onto its side, lies there for a few seconds.

const HELP_RADIUS := 50.0
const CORPSE_TIME := 4.0
const FALL_TIME := 0.45
const STRIDE_RAD_PER_M := 3.2
const LEG_AMP := 0.62
const FLANK_AFTER := 2.5

var leg_l: Node3D
var leg_r: Node3D

var _aim_t := 0.0
var _burst_left := 0
var _shot_t := 0.0
var _no_los := 0.0
var _flank := 1.0
var _stride := 0.0
var _roll_sign := 1.0
var _lean := 0.0
var _volley_origin := Vector3.ZERO


func _make_shape() -> Shape3D:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.5
	return cap


func _build_visual() -> void:
	super._build_visual()
	leg_l = model.get_node_or_null("LegL") as Node3D
	leg_r = model.get_node_or_null("LegR") as Node3D
	if is_instance_valid(Game.world) and Game.world.has_method(&"get_mirror_root"):
		var proxy := MirrorProxy.new()
		add_child(proxy)
		var body := model.get_node_or_null("Body") as MeshInstance3D
		if body != null:
			var arr: Array[MeshInstance3D] = [body]
			proxy.track(arr)


func _on_activate() -> void:
	_aim_t = 0.0
	_burst_left = 0
	_shot_t = 0.0
	_no_los = 0.0
	_flank = 1.0 if randf() < 0.5 else -1.0
	_stride = 0.0
	_lean = 0.0
	if leg_l != null:
		leg_l.rotation.x = 0.0
	if leg_r != null:
		leg_r.rotation.x = 0.0


func _idle_speed() -> float:
	return float(cfg["walk"])


func _ground_y(x: float, z: float) -> float:
	var city := Game.world as City
	if city != null:
		return city.ground_height(x, z, global_position.y + 1.0)
	return 0.0


func _hit_effect(crit: bool) -> void:
	var c := center()
	if Game.graphic_violence:
		FX.burst(c, Color(0.55, 0.03, 0.04), 6, 3.5, 0.45, 9.0)
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
		FX.burst(c, Color(0.5, 0.02, 0.03), 14, 4.0, 0.7, 10.0)
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
	model.rotation = Vector3(0.0, 0.0, _roll_sign * e * PI * 0.5)
	model.position.y = 0.32 * e
	if leg_l != null:
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
