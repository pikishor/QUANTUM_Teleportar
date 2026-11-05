class_name HeroVerbs
extends RefCounted
## Extra hero verbs of the player (wave 54b), owned by Player (`verbs`), ticked from Player._foot_tick once the vertical velocity is set.
##   WALL-RUN   airborne, holding toward a wall: run along it (camera direction on the wall plane; looking straight in runs up), gravity off, for wall_time;
##              jump kicks off the wall. One run per landing or kick-off.
##   GLIDE      HeroPower.glide caps the fall (player.gd); here the glide also keeps forward speed up.
##   SLAM       airborne, tap crouch: dive straight down; on landing a shockwave damages and staggers enemies, dents cars, breaks props.
##   WARP GRAB  hold `grab` (H, touch GRAB) to lift the nearest enemy, car or prop in front (rises to a point ahead and above the hero, off the camera line),
##              release to throw it: it flies, then hits for area damage. Cars need cars > 0 (STORY / NORMAL by default). Costs energy (HeroPower.cost).
## Strength: HeroPower.f("dmg"), HeroPower.cost(), can_wall_run() and f("glide") decide availability and scale. Per-verb numbers live in DEFAULTS (one row per
## difficulty); a HeroPower row that defines the same key (slam, slam_radius, slam_cost, wall_time, grab_range, grab_cost, throw, cars) overrides it.
## Only ticked in the play state (Player), so a pause freezes it. One shared proxy mesh for lifted props, no other nodes.

const DEFAULTS: Array[Dictionary] = [
	{"slam": 90.0, "slam_radius": 8.0, "slam_cost": 0.0, "wall_time": 3.5, "grab_range": 14.0, "grab_cost": 4.0, "throw": 1.4, "cars": 1.0},
	{"slam": 55.0, "slam_radius": 6.0, "slam_cost": 12.0, "wall_time": 2.0, "grab_range": 11.0, "grab_cost": 10.0, "throw": 1.0, "cars": 1.0},
	{"slam": 35.0, "slam_radius": 4.5, "slam_cost": 18.0, "wall_time": 1.2, "grab_range": 8.0, "grab_cost": 14.0, "throw": 0.8, "cars": 0.0},
	{"slam": 35.0, "slam_radius": 4.5, "slam_cost": 18.0, "wall_time": 1.2, "grab_range": 8.0, "grab_cost": 14.0, "throw": 0.8, "cars": 0.0},
]
const WALL_REACH := 0.8
const WALL_SPEED := 8.0
const SLAM_SPEED := 34.0
const SLAM_MIN_AIR := 0.2
const GRAB_UP := 2.2
const THROW_SPEED := 24.0
const THROW_GRAVITY := 22.0
const MAX_FLIGHT := 2.5
const HIT_RADIUS := 3.2
const GRAB_DRAIN := 0.5                      ## energy per second while holding, times the (difficulty scaled) grab cost

var wall_running := false
var wall_side := 0.0                         ## -1 / 1: which side of the body the wall is (the body rolls toward it)
var slamming := false
var holding := false
var held_kind: StringName = &""               ## enemy, vehicle, prop
var pose_roll := 0.0                         ## body hints read by PlayerBody (eased there)
var pose_pitch := 0.0
var _scrape_t := 0.0
var slams := 0                               ## counters (tests wait on these, not on frames)
var grabs := 0
var throws := 0
var wall_runs := 0
var wall_jumps := 0
var impacts := 0
var last_slam_hits := 0
var last_impact_hits := 0

var _p: Player
var _wall_t := 0.0
var _spent := false                          ## a wall-run was used since the last landing
var _crouch_was := false
var _grab_was := false
var _held: Node3D
var _held_prop := -1
var _held_from := Vector3.ZERO
var _held_layer := 0
var _lift := 0.0
var _flights: Array[Dictionary] = []
var _proxy: MeshInstance3D
var _rq := PhysicsRayQueryParameters3D.new()


static func cfg(key: String) -> float:
	var r := HeroPower.row()
	if r.has(key):
		return float(r[key])
	return float((DEFAULTS[Difficulty.clamp_mode(Difficulty.current)] as Dictionary)[key])


static func _flag(n: Object, key: String) -> bool:
	var v: Variant = n.get(key)
	return v != null and bool(v)


static func slam_radius() -> float:
	return cfg("slam_radius")


static func cars_ok() -> bool:
	return cfg("cars") > 0.5


func active() -> bool:
	return wall_running or slamming or holding


## Drop everything without effects (respawn, vehicle, teleport).
func cancel() -> void:
	wall_running = false
	slamming = false
	_spent = false
	_release_held()
	for f in _flights:
		_land_node(f)
	_flights.clear()
	if _proxy != null:
		_proxy.visible = false
	pose_roll = 0.0
	pose_pitch = 0.0


## One physics tick. `wish` is the world move direction, `on_floor` the ground state of this tick, `jump_buffered` a pending jump press.
## Returns true when a jump press was used up (wall kick).
func tick(p: Player, dt: float, forward_in: float, wish: Vector3, on_floor: bool, jump_buffered: bool) -> bool:
	_p = p
	var kicked := false
	if on_floor:
		_spent = false
	var crouch := Input.is_action_pressed(&"crouch")
	var crouch_pressed := crouch and not _crouch_was
	_crouch_was = crouch
	var grab := Input.is_action_pressed(&"grab")
	var grab_pressed := grab and not _grab_was
	var grab_released := _grab_was and not grab
	_grab_was = grab
	_flight_tick(dt)

	# --- slam
	if slamming:
		if on_floor:
			_slam_impact()
		else:
			p.velocity = Vector3(0.0, -SLAM_SPEED, 0.0)
			pose_pitch = 0.5
	elif crouch_pressed and not on_floor and p.air_time > SLAM_MIN_AIR and p.energy >= HeroPower.cost(cfg("slam_cost")):
		slamming = true
		slams += 1
		p.energy -= HeroPower.cost(cfg("slam_cost"))
		p.velocity = Vector3(0.0, -SLAM_SPEED, 0.0)
		wall_running = false

	# --- wall-run
	if not slamming:
		kicked = _wall_tick(p, dt, forward_in, wish, on_floor, jump_buffered)
	if not wall_running and not slamming and not holding and not p.gliding:
		pose_roll = 0.0
		pose_pitch = 0.0

	# --- glide keeps its speed
	if p.gliding and not wall_running and not slamming:
		var top := Player.WALK_SPEED * 1.25 * (p.speed_boost if p.speed_boost >= 1.0 else 1.0 + p.speed_boost)
		p.velocity.x = PlayerUtil.damp(p.velocity.x, wish.x * top, 1.5, dt)
		p.velocity.z = PlayerUtil.damp(p.velocity.z, wish.z * top, 1.5, dt)
		pose_pitch = 0.35

	# --- warp grab
	if holding:
		if grab_released or (not is_instance_valid(_held) and _held_prop < 0) or p.energy <= 0.0:
			_throw(not grab_released)
		else:
			p.energy -= HeroPower.cost(cfg("grab_cost")) * GRAB_DRAIN * dt
			_hold_tick(dt)
	elif grab_pressed and not slamming and not wall_running:
		_try_grab()
	return kicked


# --- wall-run ---------------------------------------------------------------------------------------------------------

func _wall_tick(p: Player, dt: float, forward_in: float, wish: Vector3, on_floor: bool, jump_buffered: bool) -> bool:
	if on_floor or not HeroPower.can_wall_run() or forward_in < 0.3 or holding:
		_end_wall()
		return false
	var flat := Vector3(wish.x, 0.0, wish.z)
	if flat.length() < 0.3:
		_end_wall()
		return false
	var dir := flat.normalized()
	if not wall_running and (_spent or p.air_time < 0.1):
		return false
	var n := _wall_normal(p, dir)
	if n == Vector3.ZERO:
		_end_wall()
		return false
	if not wall_running:
		wall_running = true
		wall_runs += 1
		_wall_t = 0.0
		_spent = true
		_scrape_t = 0.0
	_wall_t += dt
	_scrape_t -= dt
	if _scrape_t <= 0.0:
		_scrape_t = 0.3
		Sfx.verb(&"wallrun")
	if _wall_t > cfg("wall_time"):
		_end_wall()
		return false
	if jump_buffered:
		p.velocity = n * 6.0 + Vector3.UP * Player.JUMP_SPEED * 0.9 * HeroPower.f("jump")
		wall_jumps += 1
		_end_wall()
		_spent = false
		FX.burst(p.global_position + Vector3.UP, Color(0.5, 0.98, 1.0), 8, 5.0, 0.35, 2.0)
		return true
	var look := p.camera_rig.yaw
	var fwd := Vector3(-sin(look), 0.0, -cos(look))
	var along := fwd - n * fwd.dot(n)
	var up_run := along.length() < 0.25
	var speed := WALL_SPEED * (p.speed_boost if p.speed_boost >= 1.0 else 1.0) * (1.0 + 0.1 * (HeroPower.f("sprint") - 1.0))
	if up_run:
		p.velocity.x = -n.x * 1.5
		p.velocity.z = -n.z * 1.5
	else:
		along = along.normalized()
		p.velocity.x = along.x * speed - n.x * 1.5
		p.velocity.z = along.z * speed - n.z * 1.5
	p.velocity.y = lerpf(3.5 if up_run else 1.2, -1.0, _wall_t / maxf(cfg("wall_time"), 0.1))
	p.wall_running = true
	var right := Vector3(cos(look), 0.0, -sin(look))
	wall_side = signf(-n.dot(right)) if absf(n.dot(right)) > 0.2 else 0.0
	pose_roll = 0.35 * wall_side
	pose_pitch = -0.15 if up_run else 0.0
	return false


func _end_wall() -> void:
	wall_running = false
	wall_side = 0.0


func _wall_normal(p: Player, dir: Vector3) -> Vector3:
	var space := p.get_world_3d().direct_space_state
	_rq.collision_mask = Game.L_WORLD
	_rq.exclude = []
	_rq.from = p.global_position + Vector3(0.0, 1.0, 0.0)
	_rq.to = _rq.from + dir * (Player.CAPSULE_RADIUS + WALL_REACH)
	var r := space.intersect_ray(_rq)
	if r.is_empty():
		return Vector3.ZERO
	var n: Vector3 = r["normal"]
	if absf(n.y) > 0.3:
		return Vector3.ZERO
	return Vector3(n.x, 0.0, n.z).normalized()


# --- slam -------------------------------------------------------------------------------------------------------------

func _slam_impact() -> void:
	slamming = false
	pose_pitch = 0.0
	var pos := _p.global_position
	var r := slam_radius()
	last_slam_hits = _area_damage(pos, r, cfg("slam") * HeroPower.f("dmg"), null, 1.5)
	FX.qvfx.slam(pos, r)
	FX.blast(pos + Vector3.UP * 0.2, r * 0.6, Color(0.45, 0.95, 1.0), 0.45)
	FX.burst(pos + Vector3.UP * 0.3, Color(0.6, 1.0, 1.0), 24, 9.0, 0.5, 4.0)
	GameFeel.fire(&"slam")
	if is_instance_valid(_p.camera_rig):
		_p.camera_rig.bump(0.8)
	Sfx.verb(&"slam", pos)
	Sfx.play_at(&"explosion_small", pos, -8.0)


## Damage everything hostile within `r` of pos (linear falloff to 40 %): enemies (+ stagger), cars, breakable props. Returns how many were hit.
func _area_damage(pos: Vector3, r: float, dmg: float, except: Node, stagger_power: float) -> int:
	var n := 0
	for e: Node in _p.get_tree().get_nodes_in_group(&"enemy"):
		if e == except or not (e is Node3D) or _flag(e, "dead"):
			continue
		var d := (e as Node3D).global_position.distance_to(pos)
		if d <= r:
			e.call(&"damage", dmg * lerpf(1.0, 0.4, d / r), false)
			if e.has_method(&"stagger"):
				e.call(&"stagger", stagger_power)
			n += 1
	for v: Node in _p.get_tree().get_nodes_in_group(&"vehicle"):
		if v == except or not (v is Node3D) or v == _p.vehicle:
			continue
		if (v as Node3D).global_position.distance_to(pos) <= r and v.has_method(&"damage"):
			v.call(&"damage", dmg * 0.5)
			n += 1
	if Breakables.current != null:
		n += Breakables.current.blast(pos, r * 0.6)
	return n


# --- warp grab --------------------------------------------------------------------------------------------------------

func _look_forward() -> Vector3:
	var yaw := _p.camera_rig.yaw
	var pit := _p.camera_rig.pitch
	return Vector3(-sin(yaw) * cos(pit), sin(pit), -cos(yaw) * cos(pit)).normalized()


## The best target in front within grab_range: {node, prop (index or -1), kind, pos}, or {}.
func find_target() -> Dictionary:
	var o := _p.global_position + Vector3(0.0, 1.0, 0.0)
	var f := _look_forward()
	var flat := Vector3(f.x, 0.0, f.z).normalized()
	var reach := cfg("grab_range")
	var st := {"best": {}, "score": INF}                  # a lambda captures by value: results go through this dictionary
	var consider := func(node: Node3D, idx: int, kind: StringName, pos: Vector3) -> void:
		var d := pos - o
		var dist := d.length()
		if dist > reach or dist < 0.5:
			return
		var dot := Vector3(d.x, 0.0, d.z).normalized().dot(flat)
		if dot < 0.55:
			return
		var score := dist * (2.0 - dot) - (3.0 if kind == &"enemy" else 0.0)
		if score < float(st["score"]):
			st["score"] = score
			st["best"] = {"node": node, "prop": idx, "kind": kind, "pos": pos}
	for e: Node in _p.get_tree().get_nodes_in_group(&"enemy"):
		if e is Node3D and not _flag(e, "dead") and not ("active" in e and not _flag(e, "active")):
			consider.call(e, -1, &"enemy", (e as Node3D).global_position + Vector3(0.0, 0.8, 0.0))
	if cars_ok():
		for v: Node in _p.get_tree().get_nodes_in_group(&"vehicle"):
			if v is Node3D and v != _p.vehicle and not _flag(v, "dead") and not ("active" in v and not _flag(v, "active")):
				consider.call(v, -1, &"vehicle", (v as Node3D).global_position + Vector3(0.0, 0.7, 0.0))
	var bk := Breakables.current
	if bk != null:
		for i in bk.positions.size():
			if bk.broken[i] == 0:
				var sz: Vector3 = Breakables.KINDS[bk.kind_of[i]]["size"]
				if sz.y > 2.5 or sz.x > 2.5:
					continue                                     # poles, fences and windows stay put
				consider.call(null, i, &"prop", bk.positions[i])
	return st["best"]


func _try_grab() -> bool:
	if _p.energy < HeroPower.cost(cfg("grab_cost")):
		return false
	var t := find_target()
	if t.is_empty():
		return false
	_p.energy -= HeroPower.cost(cfg("grab_cost"))
	held_kind = t["kind"]
	_held = t["node"]
	_held_prop = int(t["prop"])
	_lift = 0.0
	holding = true
	grabs += 1
	Sfx.verb(&"grab")
	_held_from = t["pos"]
	if held_kind == &"prop":
		_take_prop(_held_prop, t["pos"])
	elif held_kind == &"vehicle":
		_held_layer = (_held as CollisionObject3D).collision_layer
		(_held as CollisionObject3D).collision_layer = 0
	FX.burst(t["pos"], Color(0.5, 0.98, 1.0), 10, 5.0, 0.4, 0.0)
	return true


func _take_prop(i: int, pos: Vector3) -> void:
	var bk := Breakables.current
	var kd: Dictionary = Breakables.KINDS[bk.kind_of[i]]
	bk.take_prop(i)
	if _proxy == null:
		_proxy = MeshInstance3D.new()
		_proxy.mesh = BoxMesh.new()
		_proxy.top_level = true
		_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.emission_enabled = true
		m.emission = Color(0.3, 0.9, 1.0)
		m.emission_energy_multiplier = 0.6
		_proxy.material_override = m
		_p.add_child(_proxy)
	(_proxy.material_override as StandardMaterial3D).albedo_color = kd["color"]
	_proxy.scale = kd["size"]
	_proxy.global_position = pos
	_proxy.visible = true


func _hold_point() -> Vector3:
	var yaw := _p.camera_rig.yaw
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var big := held_kind == &"vehicle"
	return _p.global_position + fwd * (4.2 if big else 2.4) + Vector3.UP * (GRAB_UP + (0.9 if big else 0.0))


func _hold_tick(dt: float) -> void:
	_lift = minf(1.0, _lift + dt / 0.25)
	var pos := _held_from.lerp(_hold_point(), _lift * _lift * (3.0 - 2.0 * _lift))
	match held_kind:
		&"prop":
			_proxy.global_position = pos
			_proxy.rotation = Vector3(_lift * 1.3, _lift * 0.9, 0.0)
		&"enemy":
			_held.global_position = pos - Vector3(0.0, 0.8, 0.0)
			if _held.has_method(&"disable"):
				_held.call(&"disable", 0.3)
		&"vehicle":
			_held.global_position = pos - Vector3(0.0, 0.7, 0.0)
			if "ai_stun" in _held:
				_held.set("ai_stun", 1.0)
			if _held is CharacterBody3D:
				(_held as CharacterBody3D).velocity = Vector3.ZERO
	pose_pitch = -0.1


## Let go of the held thing without throwing it (respawn, cancel): it is put back on the ground.
func _release_held() -> void:
	if not holding:
		return
	holding = false
	if held_kind != &"prop" and is_instance_valid(_held):
		_put_down(_held, _held_layer)
	_held = null
	_held_prop = -1
	held_kind = &""


func _put_down(n: Node3D, layer: int) -> void:
	if _p != null and _p.is_inside_tree():
		_rq.collision_mask = Game.L_WORLD
		_rq.exclude = []
		_rq.from = n.global_position + Vector3.UP * 1.0
		_rq.to = _rq.from + Vector3.DOWN * 80.0
		var r := _p.get_world_3d().direct_space_state.intersect_ray(_rq)
		if not r.is_empty():
			n.global_position = (r["position"] as Vector3) + Vector3(0.0, 0.05, 0.0)
	if n.is_in_group(&"vehicle") and n is CollisionObject3D and (n as CollisionObject3D).collision_layer == 0:
		(n as CollisionObject3D).collision_layer = layer if layer != 0 else Game.L_VEHICLE


func _throw(weak: bool) -> void:
	var kind := held_kind
	var node := _held
	var from := Vector3.ZERO
	if kind == &"prop":
		from = _proxy.global_position
	elif is_instance_valid(node):
		from = node.global_position + (Vector3(0.0, 0.8, 0.0) if kind == &"enemy" else Vector3(0.0, 0.7, 0.0))
	else:
		_release_held()
		return
	holding = false
	held_kind = &""
	_held = null
	_held_prop = -1
	throws += 1
	Sfx.verb(&"throw")
	var speed := THROW_SPEED * cfg("throw") * (0.6 if kind == &"vehicle" else 1.0) * (0.1 if weak else 1.0)
	_flights.append({"node": node, "kind": kind, "pos": from, "vel": _look_forward() * speed + Vector3.UP * 2.0, "t": 0.0, "layer": _held_layer})
	pose_pitch = 0.0
	if is_instance_valid(_p.camera_rig):
		_p.camera_rig.kick(0.03)


func _flight_tick(dt: float) -> void:
	var i := _flights.size() - 1
	while i >= 0:
		if _fly(_flights[i], dt):
			_flights.remove_at(i)
		i -= 1
	if _flights.is_empty() and not holding and _proxy != null and _proxy.visible:
		_proxy.visible = false


## Move one thrown thing; true when it has landed.
func _fly(f: Dictionary, dt: float) -> bool:
	var kind: StringName = f["kind"]
	var node: Node3D = f["node"]
	if kind != &"prop" and not is_instance_valid(node):
		return true
	var vel: Vector3 = f["vel"]
	vel.y -= THROW_GRAVITY * dt
	var pos: Vector3 = f["pos"]
	var next := pos + vel * dt
	f["t"] = float(f["t"]) + dt
	_rq.collision_mask = Game.L_WORLD
	_rq.exclude = []
	_rq.from = pos
	_rq.to = next + vel.normalized() * 0.4
	var hit := _p.get_world_3d().direct_space_state.intersect_ray(_rq)
	var done := float(f["t"]) > MAX_FLIGHT
	if not hit.is_empty():
		next = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.3
		done = true
	else:
		for e: Node in _p.get_tree().get_nodes_in_group(&"enemy"):
			if e != node and e is Node3D and not _flag(e, "dead") and (e as Node3D).global_position.distance_to(next - Vector3(0.0, 0.8, 0.0)) < 1.5:
				done = true
				break
	f["vel"] = vel
	f["pos"] = next
	if kind == &"prop":
		_proxy.global_position = next
		_proxy.rotation += Vector3(6.0, 4.0, 0.0) * dt
	else:
		node.global_position = next - (Vector3(0.0, 0.8, 0.0) if kind == &"enemy" else Vector3(0.0, 0.7, 0.0))
	if not done:
		return false
	_impact(f)
	return true


func _impact(f: Dictionary) -> void:
	var kind: StringName = f["kind"]
	var node: Node3D = f["node"]
	var pos: Vector3 = f["pos"]
	var base := 45.0 if kind == &"enemy" else (70.0 if kind == &"vehicle" else 30.0)
	var dmg := base * HeroPower.f("dmg") * cfg("throw")
	last_impact_hits = _area_damage(pos, HIT_RADIUS, dmg, node, 1.2)
	if kind != &"prop" and is_instance_valid(node) and node.has_method(&"damage") and not _flag(node, "dead"):
		if kind == &"enemy":
			node.call(&"damage", dmg, false)
		else:
			node.call(&"damage", base * 0.5)
	impacts += 1
	FX.blast(pos, 1.6, Color(0.45, 0.95, 1.0), 0.35)
	FX.burst(pos, Color(0.6, 1.0, 1.0), 14, 7.0, 0.45, 5.0)
	FX.shake(0.4)
	_land_node(f)
	Sfx.play_at(&"explosion_small", pos, -12.0)


func _land_node(f: Dictionary) -> void:
	if f["kind"] == &"prop":
		return
	var node: Node3D = f["node"]
	if is_instance_valid(node):
		_put_down(node, int(f["layer"]))
