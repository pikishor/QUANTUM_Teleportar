class_name SnakeClimb
extends RefCounted
## SNAKE CLIMB: the hero sticks to a wall or a ceiling with snakes at his hands and feet (the Spider-Man crawl): climb, run up a wall, crawl across a ceiling, mantle onto a roof, leap off in the look
## direction. Owned by SnakeTraversal (`player.snake.climb`). One tap of SNAKE next to a wall starts it (or a zip that ends at a wall), a second tap lets go, JUMP leaps off.
## The stick moves along the surface the way the picture looks: forward is up the wall (the camera turns to face the wall by itself), right is right; on a ceiling the stick moves the hero in the
## camera's horizontal directions. Every tick the surface is probed again (a curved wall, a corner, an overhang all work): the normal follows the surface, a blocked way up that meets a ceiling turns
## the climb into a ceiling crawl, a wall that ends under the hero's head becomes a mantle onto the roof, the floor under the feet ends the climb.
## The body is moved with move_and_collide (no floor snapping, no slide sticking). Grip snakes: a short tendril from a hand or a foot to the wall every GRIP_STEP metres, alternating limbs.

const HOLD := 0.42                       ## metres from the wall to the body's centre line
const PROBE := 1.7
const GRIP_STEP := 0.5
const LEAP_SPEED := 17.0
const MANTLE_TIME := 0.5
const TOP_REACH := 2.9                   ## a roof this much above the feet (or less) can be mantled
const DAMP := 14.0

var st: SnakeTraversal
var active := false
var phase: StringName = &"none"           ## cling, mantle
var n := Vector3.ZERO                     ## wall normal (out of the wall, toward the hero)
var surf := Vector3.ZERO                  ## the surface point under the hero's centre line
var ceiling := false
var node: Node3D
var up_s := Vector3.UP                    ## direction "up" along the surface for the stick / the camera
var right_s := Vector3.RIGHT
var move_speed := 0.0                     ## speed along the surface (m/s), for the pose and the grip rhythm
var move_dir := Vector2.ZERO              ## stick on the surface: x right, y up
var climbs := 0                           ## counters
var mantles := 0
var leaps := 0
var ceiling_climbs := 0
var climbed_m := 0.0
var time := 0.0
var _mantle_t := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _grip_acc := 0.0
var _grip_i := 0
var _lost := 0.0
var _vel := Vector3.ZERO
var _rq := PhysicsRayQueryParameters3D.new()
var _wall_yaw := 0.0


func _init(owner_st: SnakeTraversal = null) -> void:
	st = owner_st


func cancel() -> void:
	active = false
	phase = &"none"
	ceiling = false
	_vel = Vector3.ZERO


func _ray(p: Player, from: Vector3, to: Vector3) -> Dictionary:
	_rq.from = from
	_rq.to = to
	_rq.collision_mask = Game.L_WORLD
	_rq.exclude = [p.get_rid()]
	return p.get_world_3d().direct_space_state.intersect_ray(_rq)


## Stick to the surface of an SnakeAnchors.find_wall / zip result: {pos, normal, node}.
func begin(p: Player, wall: Dictionary) -> void:
	active = true
	phase = &"cling"
	n = (wall["normal"] as Vector3).normalized()
	surf = wall["pos"]
	node = wall.get("node") as Node3D
	ceiling = n.y < -0.5
	time = 0.0
	_lost = 0.0
	_vel = Vector3.ZERO
	_grip_acc = 0.0
	climbs += 1
	if ceiling:
		ceiling_climbs += 1
	p.velocity = Vector3.ZERO
	_wall_yaw = atan2(n.x, n.z)
	if not ceiling:
		var want := Vector3(surf.x + n.x * HOLD, p.global_position.y, surf.z + n.z * HOLD)
		p.move_and_collide(want - p.global_position)
	else:
		p.move_and_collide(Vector3(0.0, (surf.y - Player.CAPSULE_HEIGHT - 0.05) - p.global_position.y, 0.0))
	_grip(p, true)
	_grip(p, false)
	st.on_climb_started(ceiling)


func face_yaw() -> float:
	return _wall_yaw


func _frame(cam_yaw: float) -> void:
	if ceiling:
		up_s = Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
		right_s = Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	else:
		up_s = (Vector3.UP - n * n.dot(Vector3.UP)).normalized()
		right_s = up_s.cross(n).normalized()


## One physics tick. `iv` is the stick (x right, y back), `cam_yaw` the camera yaw. Returns true while the climb still owns the body.
func tick(p: Player, dt: float, iv: Vector2, cam_yaw: float, jump_pressed: bool, snake_pressed: bool) -> bool:
	if not active:
		return false
	time += dt
	if phase == &"mantle":
		return _tick_mantle(p, dt)
	_frame(cam_yaw)
	if jump_pressed:
		_leap(p)
		return false
	if snake_pressed and time > 0.25:
		_let_go(p, false)
		return false
	# energy
	if not SnakePower.unlimited():
		st.energy_spend(SnakePower.cost(2.4) * dt)
		if st.energy <= 0.0:
			Game.say("OUT OF SNAKE ENERGY", 1.2)
			_let_go(p, false)
			return false
	# surface probe: the normal follows a curved wall; a miss for a while lets go
	var centre := p.global_position + (Vector3(0.0, Player.CAPSULE_HEIGHT * 0.55, 0.0) if not ceiling else Vector3(0.0, Player.CAPSULE_HEIGHT - 0.1, 0.0))
	var hit := _ray(p, centre + n * 0.55, centre - n * PROBE)
	if hit.is_empty():
		_lost += dt
		if _lost > 0.18:
			if not ceiling and iv.y < -0.2 and _try_mantle(p):
				return true
			_let_go(p, false)
			return false
	else:
		_lost = 0.0
		var hn: Vector3 = hit["normal"]
		if hn.y > 0.62:
			# the surface under the hero became a floor: stand on it
			_let_go(p, false)
			return false
		n = n.slerp(hn, 1.0 - exp(-14.0 * dt)).normalized()
		surf = hit["position"]
		node = hit.get("collider") as Node3D
		var was_ceiling := ceiling
		ceiling = n.y < -0.5
		if ceiling != was_ceiling:
			_frame(cam_yaw)
	# the wanted velocity along the surface
	var spd := SnakePower.climb_speed()
	var want := up_s * (-iv.y) * spd + right_s * iv.x * spd * 0.9
	var moving := want.length() > 0.2
	_vel = _vel.lerp(want, 1.0 - exp(-DAMP * dt))
	var motion := _vel * dt
	# corners: what blocks the way
	if moving:
		var mdir := want.normalized()
		var block := _ray(p, centre, centre + mdir * 0.75)
		if not block.is_empty():
			var bn: Vector3 = block["normal"]
			if bn.y < -0.5 and not ceiling and mdir.dot(Vector3.UP) > 0.3:
				_turn_to(p, bn, cam_yaw)                                    # an overhang or a ceiling above: crawl on it
			elif absf(bn.y) < 0.6 and bn.dot(n) < 0.8:
				_turn_to(p, bn, cam_yaw)                                    # an inside corner: the next wall
			else:
				motion = motion.slide(bn)
		elif not ceiling and mdir.dot(Vector3.UP) > 0.3:
			var headp := p.global_position + Vector3(0.0, Player.CAPSULE_HEIGHT + 0.25, 0.0)
			var up_hit := _ray(p, headp + n * 0.5, headp - n * PROBE)
			if up_hit.is_empty() and _try_mantle(p):
				return true
	# stick to the surface: the distance error is pulled in
	if not ceiling:
		var dnow := (p.global_position + Vector3(0.0, Player.CAPSULE_HEIGHT * 0.55, 0.0) - surf).dot(n)
		motion += n * clampf(HOLD - dnow, -0.12, 0.12) * minf(1.0, 18.0 * dt)
	else:
		var head_y := p.global_position.y + Player.CAPSULE_HEIGHT
		motion.y += clampf((surf.y - 0.04) - head_y, -0.12, 0.12) * minf(1.0, 18.0 * dt)
	var before := p.global_position
	p.move_and_collide(motion)
	p.velocity = (p.global_position - before) / maxf(dt, 0.0001)
	var moved := p.global_position.distance_to(before)
	move_speed = moved / maxf(dt, 0.0001)
	move_dir = Vector2(iv.x, -iv.y)
	_wall_yaw = atan2(n.x, n.z)
	if not ceiling and motion.y > 0.0:
		climbed_m += maxf(p.global_position.y - before.y, 0.0)
	_grip_acc += moved
	if _grip_acc >= GRIP_STEP:
		_grip_acc = 0.0
		_grip(p, (_grip_i & 1) == 0)
		_grip_i += 1
	# the floor under the feet ends a downward climb
	if not ceiling and iv.y > 0.3 and p.is_on_floor():
		_let_go(p, false)
		return false
	return true


func _turn_to(p: Player, new_n: Vector3, cam_yaw: float) -> void:
	n = new_n.normalized()
	ceiling = n.y < -0.5
	_vel = Vector3.ZERO
	_wall_yaw = atan2(n.x, n.z)
	_frame(cam_yaw)
	if ceiling:
		ceiling_climbs += 1
		st.on_climb_ceiling()
	FX.burst(p.global_position + Vector3(0.0, 1.2, 0.0), Color(0.5, 1.0, 1.0), 5, 3.0, 0.3, 0.0, 0.7)


## A short snake from a hand (left = false: right hand) or a foot to a spot on the wall: the grips of the crawl.
func _grip(p: Player, hand: bool) -> void:
	if Game.quality == 0 and not hand:
		return
	var side := 1 if (_grip_i & 1) == 0 else -1
	var spot := surf + right_s * (0.3 * float(side)) + up_s * (0.35 if hand else -0.7) + n * 0.04
	var src := st.hand_callable(side) if hand else st.foot_callable(side)
	var t := SnakeTendril.fire(src, spot, {"travel": 0.07, "wriggle": 0.05, "tension": 0.9, "thickness": 0.045, "head": false, "life": 0.45, "host": p})
	t.user["grip"] = true


## Lose the grip (a jammer's pulse): no push off the wall, the hero simply falls.
func drop(p: Player) -> void:
	if active:
		_let_go(p, false)


func _let_go(p: Player, boost: bool) -> void:
	active = false
	phase = &"none"
	var was_ceiling := ceiling
	ceiling = false
	p.velocity = (-n * 0.5) if boost else Vector3.ZERO
	st.on_climb_ended(was_ceiling)


func _leap(p: Player) -> void:
	var yaw := p.camera_rig.yaw
	var pit := clampf(p.camera_rig.pitch, -0.4, 0.9)
	var look := Vector3(-sin(yaw) * cos(pit), sin(pit), -cos(yaw) * cos(pit)).normalized()
	if look.dot(n) < -0.15 and not ceiling:
		look = (look - n * look.dot(n) * 1.8 + Vector3.UP * 0.25).normalized()          # looking into the wall: the leap goes off it, the way a mirror would throw the look
	var v := look * LEAP_SPEED + n * 3.0
	if ceiling:
		v = look * LEAP_SPEED * 0.8 + Vector3.DOWN * 2.0
	else:
		v.y = maxf(v.y, 5.5)
	active = false
	phase = &"none"
	var was_ceiling := ceiling
	ceiling = false
	p.velocity = v
	leaps += 1
	st.on_climb_leap(v, was_ceiling)


## The wall ends above the hero's head: find the roof within TOP_REACH and mantle onto it.
func _try_mantle(p: Player) -> bool:
	var into := -Vector3(n.x, 0.0, n.z)
	if into.length() < 0.2:
		return false
	into = into.normalized()
	var feet := p.global_position
	for depth in [0.7, 1.1, 1.6]:
		var col := feet + into * float(depth)
		var top := _ray(p, col + Vector3.UP * (TOP_REACH + 0.5), col + Vector3.DOWN * 0.6)
		if top.is_empty():
			continue
		var tp: Vector3 = top["position"]
		if (top["normal"] as Vector3).y < 0.7 or tp.y < feet.y + 0.6 or tp.y > feet.y + TOP_REACH:
			continue
		var stand := tp + Vector3(0.0, 0.05, 0.0)
		var up := _ray(p, stand + Vector3.UP * 0.3, stand + Vector3.UP * 2.0)
		if not up.is_empty():
			continue
		phase = &"mantle"
		_mantle_t = 0.0
		_mantle_from = feet
		_mantle_to = stand + into * 0.25
		p.velocity = Vector3.ZERO
		st.on_climb_mantle()
		return true
	return false


func _tick_mantle(p: Player, dt: float) -> bool:
	_mantle_t += dt
	var k := clampf(_mantle_t / MANTLE_TIME, 0.0, 1.0)
	var up := clampf(k / 0.62, 0.0, 1.0)
	var fw := clampf((k - 0.3) / 0.7, 0.0, 1.0)
	var pos := _mantle_from
	pos.y = lerpf(_mantle_from.y, _mantle_to.y, up * up * (3.0 - 2.0 * up))
	var fe := fw * fw * (3.0 - 2.0 * fw)
	pos.x = lerpf(_mantle_from.x, _mantle_to.x, fe)
	pos.z = lerpf(_mantle_from.z, _mantle_to.z, fe)
	p.global_position = pos
	p.velocity = Vector3.ZERO
	if k >= 1.0:
		active = false
		phase = &"none"
		mantles += 1
		var into := -Vector3(n.x, 0.0, n.z).normalized()
		p.velocity = into * 3.0
		st.on_climb_ended(false)
		return false
	return true
