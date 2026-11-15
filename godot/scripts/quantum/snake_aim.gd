class_name SnakeAim
extends RefCounted
## Where a snake power aims (wave 115, combat side): the crosshair ray of the camera, the point it lands on, and the target under it (an enemy, a car, a pickup or a prop) with a generous cone like the
## aim assist of the guns (the SNAKE ASSIST option of the traversal also widens it). Pure functions of the player and the scene; nothing is kept between calls.
##   SnakeAim.ray(p)                         [origin, direction] of the crosshair
##   SnakeAim.point(p, reach)                where the crosshair lands within `reach` (world and cars); the far point of the ray when it hits nothing
##   SnakeAim.pick(p, reach, kinds, cone)    the best target {node, kind, pos, dist, idx} (idx = the prop index) or {}; kinds: &"enemy", &"car", &"pickup", &"prop"
##   SnakeAim.center_of(node)                the middle of an enemy or car
##   SnakeAim.heavy(node)                    bosses, brutes and cars: the hero is pulled TO them, they are not pulled to him
##   SnakeAim.clear_line(p, a, b)            nothing of the world between the two points

const CONE := 0.17                             ## radians around the crosshair a target is picked within (about 10 degrees)
const ASSIST_CONE := 1.45                      ## the cone grows by this with the aim assist on
const MIN_DIST := 0.8

static var _rq := PhysicsRayQueryParameters3D.new()


static func ray(p: Player) -> Array:
	var cam := p.camera_rig.camera
	var origin := cam.global_position
	var dir := -cam.global_basis.z
	return [origin, dir.normalized()]


static func chest(p: Player) -> Vector3:
	return p.global_position + Vector3(0.0, 1.25, 0.0)


static func point(p: Player, reach: float) -> Vector3:
	var r := ray(p)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	var start := o + d * maxf(0.0, (p.camera_rig.get_pivot_position() - o).dot(d))
	_rq.from = start
	_rq.to = start + d * reach
	_rq.collision_mask = Game.L_WORLD | Game.L_VEHICLE | Game.L_ENEMY
	_rq.exclude = [p.get_rid()]
	var res := p.get_world_3d().direct_space_state.intersect_ray(_rq)
	return res["position"] if not res.is_empty() else start + d * reach


## The street (or roof) under a point: a ray down from a metre above it; the point itself when nothing is below within eight metres.
static func ground_under(p: Player, pt: Vector3) -> Vector3:
	_rq.from = pt + Vector3.UP * 1.0
	_rq.to = pt + Vector3.DOWN * 8.0
	_rq.collision_mask = Game.L_WORLD
	_rq.exclude = [p.get_rid()]
	var res := p.get_world_3d().direct_space_state.intersect_ray(_rq)
	return res["position"] if not res.is_empty() else pt


static func center_of(n: Node3D) -> Vector3:
	if n.has_method(&"center"):
		return n.call(&"center")
	return n.global_position + Vector3(0.0, 0.9, 0.0)


static func is_boss(n: Node) -> bool:
	var cfg: Variant = EnemyTypes.TYPES.get(n.get(&"type"))
	return cfg is Dictionary and bool((cfg as Dictionary).get("boss", false))


static func heavy(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n.is_in_group(&"vehicle"):
		return true
	if is_boss(n):
		return true
	var cfg: Variant = EnemyTypes.TYPES.get(n.get(&"type"))
	return cfg is Dictionary and StringName((cfg as Dictionary).get("role", &"")) in [&"brute", &"heavy"]


static func is_live_enemy(n: Node) -> bool:
	return n is Node3D and is_instance_valid(n) and n.is_inside_tree() and not bool(n.get(&"dead")) and (n.get(&"active") == null or bool(n.get(&"active"))) and n.get(&"friendly") != true


static func clear_line(p: Player, a: Vector3, b: Vector3) -> bool:
	_rq.from = a
	_rq.to = b
	_rq.collision_mask = Game.L_WORLD
	_rq.exclude = [p.get_rid()]
	return p.get_world_3d().direct_space_state.intersect_ray(_rq).is_empty()


## The living enemies within `reach` of the hero, nearest first.
static func enemies_near(p: Player, reach: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var o := chest(p)
	for n: Node3D in Gear.living_enemies(p.get_tree()):
		if n.get(&"friendly") == true:
			continue
		if center_of(n).distance_to(o) <= reach:
			out.append(n)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(o) < b.global_position.distance_squared_to(o))
	return out


## The best target under the crosshair. Score = the angle to the ray, a little less for an enemy, so a trooper standing next to a barrier is the one picked.
static func pick(p: Player, reach: float, kinds: Array, cone := CONE) -> Dictionary:
	var r := ray(p)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	var me := chest(p)
	var wide := cone * (ASSIST_CONE if SnakeTraversal.assist else 1.0)
	var st := {"best": {}, "score": INF}                      # a lambda captures by value: the result goes through this dictionary
	var consider := func(node: Node3D, kind: StringName, pos: Vector3, idx: int) -> void:
		var dist := pos.distance_to(me)
		if dist > reach or dist < MIN_DIST:
			return
		var to := pos - o
		var ang := d.angle_to(to.normalized()) if to.length() > 0.01 else 0.0
		if ang > wide or to.dot(d) < 0.0:
			return
		var score := ang + dist * 0.0015 - (0.05 if kind == &"enemy" else 0.0)
		if score < float(st["score"]):
			st["score"] = score
			st["best"] = {"node": node, "kind": kind, "pos": pos, "dist": dist, "idx": idx}
	if kinds.has(&"enemy"):
		for n: Node3D in Gear.living_enemies(p.get_tree()):
			if n.get(&"friendly") == true:
				continue
			consider.call(n, &"enemy", center_of(n), -1)
	if kinds.has(&"car"):
		for v: Node in p.get_tree().get_nodes_in_group(&"vehicle"):
			var vn := v as Node3D
			if vn == null or not is_instance_valid(vn) or vn == p.vehicle or bool(vn.get(&"dead")) or (vn.get(&"active") != null and not bool(vn.get(&"active"))):
				continue
			consider.call(vn, &"car", vn.global_position + Vector3(0.0, 0.7, 0.0), -1)
	if kinds.has(&"pickup") and Game.missions != null:
		for s: Variant in Game.missions.pickups:
			if s is Dictionary and (s as Dictionary).has("pos"):
				consider.call(null, &"pickup", (s as Dictionary)["pos"] as Vector3, -1)
	if kinds.has(&"prop") and Breakables.current != null:
		var bk := Breakables.current
		var lim := reach * reach
		for i in bk.positions.size():
			if bk.broken[i] != 0:
				continue
			var pp: Vector3 = bk.positions[i]
			if pp.distance_squared_to(me) > lim:
				continue
			var sz: Vector3 = Breakables.KINDS[bk.kind_of[i]]["size"]
			if sz.y > 2.5 or sz.x > 2.5:
				continue
			consider.call(null, &"prop", pp, i)
	return st["best"]
