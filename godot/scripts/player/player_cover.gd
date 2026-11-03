class_name PlayerCover
extends Node
## Cover, crouch, slide and melee takedown of the player (G4 / A2 / A3). A child of the Player; the Player calls update() before it works out its
## speed and apply_velocity() after the horizontal velocity is set. Actions: `crouch` (hold; Ctrl, touch CROUCH) and `takedown` (V, touch TAKEDOWN).
##   crouch    the capsule shrinks (CROUCH_HEIGHT), speed x0.55, no sprint; stands up only with headroom.
##   cover     crouching within COVER_REACH of a wall or car snaps the body against it (hugging); head down it takes COVER_DAMAGE of the damage.
##   peek      aiming or firing while in cover stands the view up (the camera and body rise) and drops the damage cover: peek-fire.
##   slide     crouch while sprinting: a SLIDE_TIME burst that decays, with a SLIDE_HEIGHT capsule, so a gap of 1 m or more can be crossed.
##   takedown  within TAKEDOWN_REACH of a living enemy whose back is turned (angle) kills it with a short lunge effect; cooldown TAKEDOWN_COOLDOWN.
## Nothing here runs outside the play state (the Player only ticks in `play`), so a pause freezes it.

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const SLIDE_HEIGHT := 0.9
const CROUCH_SPEED := 0.55
const COVER_REACH := 0.85            ## metres from the body centre to a wall that counts as cover
const COVER_GAP := 0.08              ## metres left between the capsule and the wall when hugging
const COVER_DAMAGE := 0.5            ## damage taken head down in cover
const SLIDE_TIME := 0.7
const SLIDE_SPEED := 9.0
const SLIDE_MIN_SPEED := 4.0         ## a slide needs this much horizontal speed to start
const TAKEDOWN_REACH := 1.9
const TAKEDOWN_BACK := -0.3          ## dot(enemy forward, direction enemy to player) below this = the player is behind it
const TAKEDOWN_COOLDOWN := 0.8
const TAKEDOWN_STRIKE := 0.35        ## seconds of the strike pose

var crouching := false
var sliding := false
var in_cover := false
var peeking := false
var cover_normal := Vector3.ZERO     ## horizontal normal of the wall being hugged (points away from it)
var height := STAND_HEIGHT           ## current capsule height, eased
var strike := 0.0                    ## 1 at a takedown, decays to 0 (the body reads it)
var takedowns := 0
var target: Node3D                   ## the enemy a takedown would hit right now (the touch button shows for it)

var _p: Player
var _col: CollisionShape3D
var _slide_t := 0.0
var _slide_dir := Vector3.ZERO
var _cool := 0.0
var _crouch_was := false
var _td_was := false


## 0..1: how far down the view is (crouch drop in metres is drop()); peeking brings half of it back.
func drop() -> float:
	var d := STAND_HEIGHT - height
	return d * (0.45 if peeking else 1.0)


## Pure: is the player behind an enemy that faces `enemy_forward`? (all horizontal, `to_player` from the enemy)
static func is_behind(enemy_forward: Vector3, to_player: Vector3) -> bool:
	var f := Vector3(enemy_forward.x, 0.0, enemy_forward.z)
	var t := Vector3(to_player.x, 0.0, to_player.z)
	if f.length_squared() < 1e-6 or t.length_squared() < 1e-6:
		return false
	return f.normalized().dot(t.normalized()) < TAKEDOWN_BACK


func _ready() -> void:
	_p = get_parent() as Player
	if _p != null:
		_col = _p.get_node_or_null("Collision") as CollisionShape3D
		if _col != null and _col.shape != null:
			_col.shape = _col.shape.duplicate()             # the scene's shape resource is shared by every Player


func _process(dt: float) -> void:
	strike = maxf(0.0, strike - dt / TAKEDOWN_STRIKE)


## Before the player's top speed: reads the inputs and decides crouch, slide, cover, peek and takedown.
func update(dt: float, on_floor: bool, move_speed: float) -> void:
	if _p == null:
		return
	_cool = maxf(0.0, _cool - dt)
	var want := Input.is_action_pressed(&"crouch")
	var pressed := want and not _crouch_was
	_crouch_was = want
	if pressed and not sliding and on_floor and move_speed >= SLIDE_MIN_SPEED and _p.sprinting:
		sliding = true
		_slide_t = SLIDE_TIME
		var h := Vector3(_p.velocity.x, 0.0, _p.velocity.z)
		_slide_dir = h.normalized()
	if sliding:
		_slide_t -= dt
		if _slide_t <= 0.0 or not on_floor:
			sliding = false
	var low := want or sliding
	if low:
		crouching = true
	elif crouching and _headroom(STAND_HEIGHT):
		crouching = false
	_set_height(dt, SLIDE_HEIGHT if sliding else (CROUCH_HEIGHT if crouching else STAND_HEIGHT))

	# cover: only a crouched, grounded body that is not sliding
	in_cover = false
	cover_normal = Vector3.ZERO
	if crouching and not sliding and on_floor:
		_find_cover()
	peeking = in_cover and (Input.is_action_pressed(&"aim") or Input.is_action_pressed(&"fire"))

	# takedown
	target = _find_target()
	var td := Input.is_action_pressed(&"takedown")
	if td and not _td_was:
		try_takedown()
	_td_was = td


func speed_mult() -> float:
	return CROUCH_SPEED if crouching and not sliding else 1.0


## After the horizontal velocity: a slide overrides it, cover pulls the body to the wall.
func apply_velocity(dt: float) -> void:
	if _p == null:
		return
	if sliding:
		var k := clampf(_slide_t / SLIDE_TIME, 0.0, 1.0)
		var s := lerpf(SLIDE_MIN_SPEED * 0.6, SLIDE_SPEED, k * k)
		_p.velocity.x = _slide_dir.x * s
		_p.velocity.z = _slide_dir.z * s
	elif in_cover:
		_p.velocity += -cover_normal * minf(_cover_gap_error() * 10.0, 2.0)
		var into := _p.velocity.dot(-cover_normal)
		if into > 0.0 and absf(_cover_gap_error()) < 0.03:
			_p.velocity += cover_normal * into          # already hugging: no more push into the wall


## Damage multiplier the Player applies to incoming hits.
func damage_mult() -> float:
	return COVER_DAMAGE if in_cover and not peeking else 1.0


## Kill the closest enemy whose back is turned, if one is in reach. Returns true on a takedown.
func try_takedown() -> bool:
	if _cool > 0.0 or _p == null or not Game.is_playing():
		return false
	var e := _find_target()
	if e == null:
		return false
	_cool = TAKEDOWN_COOLDOWN
	strike = 1.0
	takedowns += 1
	var to := e.global_position - _p.global_position
	_p.yaw = PlayerUtil.yaw_of(Vector3(to.x, 0.0, to.z).normalized())
	if e.has_method(&"damage"):
		e.call(&"damage", 9999.0, true)
	if _p.sparks != null:
		_p.sparks.puff(e.global_position + Vector3(0.0, 1.1, 0.0), -to.normalized(), Color(0.5, 0.9, 1.0, 0.5), 1.3)
	FX.shake(0.25)
	Sfx.play(&"hit")
	return true


func _find_target() -> Node3D:
	var best: Node3D
	var best_d := TAKEDOWN_REACH
	for n in get_tree().get_nodes_in_group(&"enemy"):
		var e := n as Node3D
		if e == null or not is_instance_valid(e) or not e.is_inside_tree() or bool(e.get(&"dead")):
			continue
		var d := Vector2(e.global_position.x - _p.global_position.x, e.global_position.z - _p.global_position.z).length()
		if d >= best_d or absf(e.global_position.y - _p.global_position.y) > 1.5:
			continue
		var fwd := -e.global_basis.z
		if is_behind(fwd, _p.global_position - e.global_position):
			best = e
			best_d = d
	return best


func _set_height(dt: float, goal: float) -> void:
	height = PlayerUtil.damp(height, goal, 18.0, dt)
	if absf(height - goal) < 0.005:
		height = goal
	if _col != null and _col.shape is CapsuleShape3D:
		(_col.shape as CapsuleShape3D).height = height
		_col.position.y = height * 0.5


## Is there room above the body to be `h` tall?
func _headroom(h: float) -> bool:
	var rise := h - height
	if rise <= 0.01:
		return true
	return not _p.test_move(_p.global_transform, Vector3.UP * rise)


func _ray(from: Vector3, dir: Vector3, reach: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, Game.L_WORLD | Game.L_VEHICLE)
	return _p.get_world_3d().direct_space_state.intersect_ray(q)


func _find_cover() -> void:
	var o := _p.global_position + Vector3(0.0, 0.5, 0.0)
	var best := COVER_REACH + 1.0
	for i in 8:
		var a := float(i) * TAU / 8.0
		var d := Vector3(cos(a), 0.0, sin(a))
		var hit := _ray(o, d, COVER_REACH)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if absf(n.y) > 0.5:
			continue                                   # floor or a roof, not a wall
		var dist := o.distance_to(hit["position"])
		if dist < best:
			best = dist
			cover_normal = Vector3(n.x, 0.0, n.z).normalized()
			in_cover = true


func _cover_gap_error() -> float:
	if not in_cover:
		return 0.0
	var o := _p.global_position + Vector3(0.0, 0.5, 0.0)
	var hit := _ray(o, -cover_normal, COVER_REACH + 0.3)
	if hit.is_empty():
		return 0.0
	return o.distance_to(hit["position"]) - (Player.CAPSULE_RADIUS + COVER_GAP)
