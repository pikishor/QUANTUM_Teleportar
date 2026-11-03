class_name Traversal
extends RefCounted
## Rooftop traversal of the player: vault low obstacles (up to 1.25 m, ends on the far side), mantle ledges up to 2.5 m, ledge grab after a rooftop
## jump (airborne, falling or rising slowly, forward held), and ladders on some low buildings (roof access). Contract: ARCHITECTURE.md "player".
##
## Touch friendly: no extra buttons. Forward + jump next to an obstacle vaults or mantles it instead of jumping; an airborne player pushing forward
## into a ledge within reach grabs and mantles it by itself. A ladder is climbed by walking into it (forward up, back down, jump hops off) and ends
## in a mantle onto the roof. Nothing here pauses or reads Game.state: Player._foot_tick only calls tick() in the play state.
## The body is moved by scripted position (no collision during the move, the end point is checked to fit the capsule first), so the camera rig,
## which follows the player, simply rides along; the spring arm keeps it out of walls as always. No nodes, no draws, no allocations per tick except
## the ray results.
## Ladder zones are static data: Traversal.zones {base, out, top_y}, filled by city_roofs.gd (cleared at each city build).

enum Kind { NONE, VAULT, MANTLE, CLIMB }

const VAULT_MAX := 1.25                     ## metres above the feet: up to here the obstacle is vaulted when there is floor behind it
const MANTLE_MAX := 2.5
const MIN_OBSTACLE := 0.45                  ## below this the step-up of the player copes (STEP_HEIGHT 0.38)
const REACH := 0.9                          ## how far ahead of the capsule an obstacle is looked for
const CLIMB_SPEED := 3.2
const VAULT_TIME := 0.38
const COOLDOWN := 0.25
const CAPSULE_RADIUS := 0.35

static var zones: Array[Dictionary] = []

var kind := Kind.NONE
var last_kind := Kind.NONE                  ## what happened last (tests, animation)
var count := 0                              ## traversals started since the object was made (tests wait on this, not on frames)
var _t := 0.0
var _dur := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _dir := Vector3.FORWARD
var _arc := 0.0
var _zone := {}
var _cooldown := 0.0
var _rq := PhysicsRayQueryParameters3D.new()


static func clear_zones() -> void:
	zones.clear()


## A ladder up a wall: base = foot of the ladder on the wall face, out = horizontal outward normal of the wall, top_y = roof height.
static func add_zone(base: Vector3, out: Vector3, top_y: float) -> void:
	zones.append({"base": base, "out": Vector3(out.x, 0.0, out.z).normalized(), "top_y": top_y})


func active() -> bool:
	return kind != Kind.NONE


## Cancel whatever runs (respawn, vehicle, teleport).
func cancel() -> void:
	kind = Kind.NONE
	_cooldown = 0.0


## One physics tick from Player._foot_tick. `wish` is the world move direction (length up to 1), `jump` is true while a jump press is pending.
## Returns true when the traversal moves the body this tick (the caller skips its own movement); `consumed_jump` tells it to drop the press.
var consumed_jump := false


func tick(p: Player, dt: float, forward_in: float, wish: Vector3, jump: bool) -> bool:
	consumed_jump = false
	_cooldown = maxf(0.0, _cooldown - dt)
	if kind == Kind.CLIMB:
		return _climb(p, dt, forward_in, jump)
	if kind != Kind.NONE:
		return _advance(p, dt)
	if _cooldown > 0.0:
		return false
	var flat := Vector3(wish.x, 0.0, wish.z)
	if forward_in > 0.3 and flat.length() > 0.3:
		var dir := flat.normalized()
		var grounded := p.is_on_floor()
		if not zones.is_empty() and _try_ladder(p, dir):
			return true
		var want := (jump and grounded) or (not grounded and p.velocity.y < 2.5 and p.air_time > 0.08)
		if want:
			var r := probe(p, dir, not grounded)
			if not r.is_empty():
				consumed_jump = true
				_begin(p, r)
				return true
	return false


## What is in front of the player: {} or {kind, to, dir, h}. `airborne` lowers the minimum height (a ledge grab reaches higher than a step).
func probe(p: Player, dir: Vector3, airborne := false) -> Dictionary:
	var space := p.get_world_3d().direct_space_state
	var o := p.global_position
	_rq.collision_mask = Game.L_WORLD
	_rq.exclude = []
	# a wall or obstacle ahead at knee height
	_rq.from = o + Vector3(0.0, 0.4, 0.0)
	_rq.to = _rq.from + dir * (CAPSULE_RADIUS + REACH)
	var wall := space.intersect_ray(_rq)
	if wall.is_empty() or absf((wall["normal"] as Vector3).y) > 0.5:
		return {}
	var face: Vector3 = wall["position"]
	# its top, a little behind the face
	var above := face + dir * 0.25
	_rq.from = Vector3(above.x, o.y + MANTLE_MAX + 0.1, above.z)
	_rq.to = Vector3(above.x, o.y + 0.05, above.z)
	var top := space.intersect_ray(_rq)
	if top.is_empty() or (top["normal"] as Vector3).y < 0.7:
		return {}
	var h: float = (top["position"] as Vector3).y - o.y
	if h < (0.3 if airborne else MIN_OBSTACLE) or h > MANTLE_MAX:
		return {}
	if p.test_move(p.global_transform, Vector3.UP * (h + 0.05)):
		return {}                                                  # no headroom to rise
	var ty: float = (top["position"] as Vector3).y
	if h <= VAULT_MAX and not airborne:
		for d in [0.75, 1.1, 1.5, 2.0, 2.6]:
			var f: Vector3 = face + dir * (float(d) + CAPSULE_RADIUS * 0.5)
			var g := _ground_at(space, f, ty + 0.3, o.y - 1.0)
			if g == -INF:
				continue
			if g <= o.y + 0.4 and _fits(p, Vector3(f.x, g + 0.03, f.z)):
				return {"kind": Kind.VAULT, "to": Vector3(f.x, g + 0.03, f.z), "dir": dir, "h": h}
			if g > o.y + 0.4:
				continue                                           # still on the obstacle: keep looking for the far side
	var spot := face + dir * (CAPSULE_RADIUS + 0.12)
	var sy := _ground_at(space, spot, ty + 0.3, ty - 0.3)
	if sy == -INF:
		spot = face + dir * 0.1                                    # a thin top: stand on its edge
		sy = ty
	if not _fits(p, Vector3(spot.x, sy + 0.03, spot.z)):
		return {}
	return {"kind": Kind.MANTLE, "to": Vector3(spot.x, sy + 0.03, spot.z), "dir": dir, "h": h}


func _ground_at(space: PhysicsDirectSpaceState3D, at: Vector3, from_y: float, to_y: float) -> float:
	_rq.from = Vector3(at.x, from_y, at.z)
	_rq.to = Vector3(at.x, to_y, at.z)
	var r := space.intersect_ray(_rq)
	if r.is_empty() or (r["normal"] as Vector3).y < 0.7:
		return -INF
	return (r["position"] as Vector3).y


func _fits(p: Player, at: Vector3) -> bool:
	var xf := p.global_transform
	xf.origin = at + Vector3(0.0, 0.04, 0.0)
	return not p.test_move(xf, Vector3.UP * 0.01)


func _begin(p: Player, r: Dictionary) -> void:
	kind = r["kind"]
	last_kind = kind
	count += 1
	_t = 0.0
	_from = p.global_position
	_to = r["to"]
	_dir = r["dir"]
	var h: float = r["h"]
	if kind == Kind.VAULT:
		_dur = VAULT_TIME
		_arc = h * 0.35 + 0.18
	else:
		_dur = 0.42 + 0.14 * h
		_arc = 0.0
	p.velocity = Vector3.ZERO


func _advance(p: Player, dt: float) -> bool:
	_t += dt
	var k := clampf(_t / _dur, 0.0, 1.0)
	var pos := _from
	if kind == Kind.VAULT:
		var e := k * k * (3.0 - 2.0 * k)
		pos = _from.lerp(_to, e)
		pos.y += sin(k * PI) * _arc + 0.0
		pos.y = maxf(pos.y, minf(_from.y, _to.y))
	else:
		var up := clampf(k / 0.65, 0.0, 1.0)
		var fw := clampf((k - 0.35) / 0.65, 0.0, 1.0)
		pos.y = lerpf(_from.y, _to.y, up * up * (3.0 - 2.0 * up))
		var fe := fw * fw * (3.0 - 2.0 * fw)
		pos.x = lerpf(_from.x, _to.x, fe)
		pos.z = lerpf(_from.z, _to.z, fe)
	p.global_position = pos
	p.velocity = Vector3.ZERO
	if k >= 1.0:
		_finish(p)
	return true


func _finish(p: Player) -> void:
	p.global_position = _to
	p.velocity = _dir * 3.0 if kind == Kind.VAULT else Vector3.ZERO
	kind = Kind.NONE
	_cooldown = COOLDOWN


# --- ladders ----------------------------------------------------------------------------------------------------------------------

func _try_ladder(p: Player, dir: Vector3) -> bool:
	var o := p.global_position
	for z: Dictionary in zones:
		var base: Vector3 = z["base"]
		if o.y < base.y - 0.5 or o.y > float(z["top_y"]) - 0.5:
			continue
		var out: Vector3 = z["out"]
		if dir.dot(-out) < 0.5:
			continue
		var rel := o - base
		var along := rel.dot(out)
		var lateral := rel.dot(out.cross(Vector3.UP))
		if along < -0.2 or along > 1.0 or absf(lateral) > 0.55:
			continue
		_zone = z
		kind = Kind.CLIMB
		last_kind = kind
		count += 1
		_dir = -out
		p.velocity = Vector3.ZERO
		return true
	return false


func _climb(p: Player, dt: float, forward_in: float, jump: bool) -> bool:
	var base: Vector3 = _zone["base"]
	var out: Vector3 = _zone["out"]
	var top_y: float = _zone["top_y"]
	var pos := p.global_position
	var axis := base + out * 0.5
	pos.x = lerpf(pos.x, axis.x, minf(1.0, 12.0 * dt))
	pos.z = lerpf(pos.z, axis.z, minf(1.0, 12.0 * dt))
	if jump:
		consumed_jump = true
		kind = Kind.NONE
		_cooldown = 0.5
		p.velocity = out * 3.5 + Vector3.UP * 3.0
		return false
	var v := 0.0
	if forward_in > 0.3:
		v = CLIMB_SPEED
	elif forward_in < -0.3:
		v = -CLIMB_SPEED
	pos.y += v * dt
	if pos.y <= base.y + 0.02 and v < 0.0:
		pos.y = base.y
		kind = Kind.NONE
		_cooldown = COOLDOWN
		p.global_position = pos
		p.velocity = Vector3.ZERO
		return false
	p.global_position = pos
	p.velocity = Vector3.ZERO
	if pos.y >= top_y - 0.05:
		kind = Kind.MANTLE                                         # over the parapet: onto the roof
		last_kind = kind
		_t = 0.0
		_dur = 0.55
		_from = Vector3(pos.x, top_y, pos.z)
		_to = Vector3(base.x - out.x * 0.9, top_y + 0.03, base.z - out.z * 0.9)
		_dir = -out
		_arc = 0.0
	return true
