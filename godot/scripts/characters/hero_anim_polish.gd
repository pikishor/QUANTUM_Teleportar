class_name HeroAnimPolish
extends RefCounted
## The hero's animation polish layer, procedural on the skeleton and tuned only in HeroAnimTuning. PlayerBody owns one and calls update() right after Locomotion.update()
## and before CharacterRig.apply(); it adds to the rig's inputs (extra_torso, pose_hips, head_look, hand placement, the soles' height and pitch) and never poses a bone itself.
##   locomotion   start lean and stop rock, turn-in-place twist and roll, breathing idle, landing impact (dip and chest pitch)
##   weapons      reload and weapon swap shaping per class (rifle, shotgun, heavy)
##   states       cover (crouch, lean into the wall, peek), takedown, slam, glide, wall-run
##   traversal    vault and mantle with the hands placed on the obstacle
##   head         look-at toward the target (enemy or the aim), blink, eye saccades (micro movements of the gaze)
##   feet         ray per foot against the world: soles follow slopes and stairs (height and pitch)
## Public outputs for tests and the face shader: blink (0..1), gaze, foot_off_l/r, state.

const Tune := preload("res://scripts/characters/hero_anim_tuning.gd")

var rig: CharacterRig
var state: StringName = &"idle"               ## the dominant pose of the last update: idle, move, cover, peek, takedown, slam, glide, wall, vault, mantle, reload, swap
var blink := 0.0
var gaze := Vector2.ZERO                       ## the saccade offset of the last update (yaw, pitch, radians)
var foot_off_l := 0.0                          ## metres the left / right sole was raised (+) or lowered (-) by the ground under it
var foot_off_r := 0.0
var slope := 0.0                               ## ground pitch under the body along its forward axis (radians, + uphill)
var landings := 0                              ## counter (tests wait on this, not on frames)

var _t := 0.0
var _start := Vector2.ZERO                     ## springs (value, velocity)
var _turn := Vector2.ZERO
var _turn_roll := Vector2.ZERO
var _land := Vector2.ZERO
var _cover := Vector2.ZERO
var _peek := Vector2.ZERO
var _glide := Vector2.ZERO
var _wall := Vector2.ZERO
var _look := Vector2.ZERO
var _look_p := Vector2.ZERO
var _sacc := Vector2.ZERO
var _sacc_p := Vector2.ZERO
var _sacc_goal := Vector2.ZERO
var _sacc_t := 0.0
var _blink_t := 2.0
var _blink_k := -1.0
var _was_grounded := true
var _fall_speed := 0.0
var _speed_prev := 0.0
var _hand := Vector2.ZERO
var _fo := Vector2.ZERO
var _fo_ready := false
var _slope_s := 0.0
var _pose := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _rq := PhysicsRayQueryParameters3D.new()


func _init(r: CharacterRig = null) -> void:
	rig = r
	_rng.seed = 7731
	_rq.collision_mask = Game.L_WORLD


func reset() -> void:
	_start = Vector2.ZERO
	_turn = Vector2.ZERO
	_turn_roll = Vector2.ZERO
	_land = Vector2.ZERO
	_cover = Vector2.ZERO
	_peek = Vector2.ZERO
	_glide = Vector2.ZERO
	_wall = Vector2.ZERO
	_hand = Vector2.ZERO
	_fo = Vector2.ZERO
	_fo_ready = false
	_pose = Vector3.ZERO
	state = &"idle"
	blink = 0.0
	_blink_k = -1.0


## One frame. `loco` is the Locomotion already updated this frame, `p` the player (velocity, cover, traversal, verbs, weapon), `body` the node the feet rays start from.
func update(dt: float, p: Player, body: Node3D, loco: Locomotion, grounded: bool, weapon_id: StringName, reload_k: float, reload_is_swap: bool, aim_target: Variant = null) -> void:
	if rig == null or loco == null or dt <= 0.0:
		return
	_t += dt
	var tx := Tune
	var speed := loco.speed
	var calm := 1.0 - clampf(speed / tx.f("breath_calm_speed"), 0.0, 1.0)
	var tw := Vector3.ZERO                     # extra torso (pitch, yaw, roll), added to what Locomotion wrote
	var hips := Vector3.ZERO
	var st: StringName = &"move" if speed > 0.5 else &"idle"

	# ---- breathing idle: chest and pelvis swell, strongest at rest
	var br := sin(_t * tx.f("breath_rate") * TAU * 0.5)
	tw.x += br * tx.f("breath_chest") * (0.4 + 0.6 * calm)
	hips.y += br * tx.f("breath_hips") * calm

	# ---- start, stop and turn in place
	var acc_f := loco.acc.y
	_start = PlayerUtil.spring(_start, clampf(-acc_f / 25.0, -1.0, 1.0), tx.f("start_spring"), dt)
	var stopping := clampf(-acc_f / 25.0, 0.0, 1.0)
	tw.x += _start.x * (tx.f("start_lean") if _start.x < 0.0 else tx.f("stop_rock"))
	tw.x += 0.0 * stopping
	var turning := absf(loco.yaw_rate) / tx.f("turn_rate_ref")
	var turn_gate := clampf(turning, 0.0, 1.0) * (1.0 - clampf(speed / 2.5, 0.0, 1.0))
	_turn = PlayerUtil.spring(_turn, signf(loco.yaw_rate) * turn_gate, tx.f("turn_spring"), dt)
	_turn_roll = PlayerUtil.spring(_turn_roll, clampf(loco.yaw_rate / tx.f("turn_rate_ref"), -1.0, 1.0) * clampf(speed / 6.0, 0.0, 1.0), tx.f("turn_spring"), dt)
	tw.y += -_turn.x * tx.f("turn_twist")
	tw.z += -_turn.x * tx.f("turn_roll") * 0.4 - _turn_roll.x * tx.f("turn_roll")

	# ---- landing impact
	if not grounded:
		_fall_speed = maxf(_fall_speed, -p.velocity.y)
	if grounded and not _was_grounded:
		var imp := clampf((_fall_speed - tx.f("land_min_speed")) / tx.f("land_ref_speed"), 0.0, 1.0)
		_land.x = 1.0 + 4.0 * imp
		_land.y = 0.0
		_fall_speed = 0.0
		landings += 1
	_was_grounded = grounded
	_land = PlayerUtil.spring(_land, 0.0, tx.f("land_spring"), dt) if (_land.x != 0.0 or _land.y != 0.0) else _land
	tw.x += _land.x * tx.f("land_pitch") * 0.25
	hips.y -= _land.x * tx.f("land_dip") * 0.2

	# ---- weapon handling by class
	var swap_w := 0.0
	var rl_w := 0.0
	if reload_k >= 0.0:
		var w := sin(PI * clampf(reload_k, 0.0, 1.0))
		if reload_is_swap:
			swap_w = w
			st = &"swap"
		else:
			rl_w = w
			st = &"reload"
	hips.y -= rl_w * Tune.cls("reload_pelvis", weapon_id) + swap_w * Tune.cls("swap_dip", weapon_id) * 0.3
	tw.x += rl_w * Tune.cls("reload_pitch", weapon_id) + swap_w * Tune.cls("swap_dip", weapon_id)
	tw.y += rl_w * Tune.cls("reload_twist", weapon_id) * sin(TAU * clampf(reload_k, 0.0, 1.0) * 0.5)

	# ---- cover: crouch, lean into the wall, peek out
	var c: PlayerCover = p.cover
	var in_cover := c != null and c.in_cover
	var side := 0.0
	if in_cover:
		var n := c.cover_normal
		var fwd := Vector3(-sin(body.rotation.y), 0.0, -cos(body.rotation.y))
		var right := Vector3(cos(body.rotation.y), 0.0, -sin(body.rotation.y))
		side = clampf(-n.dot(right), -1.0, 1.0) if absf(n.dot(fwd)) < 0.9 else 0.0
	var crouch := clampf(1.0 - (c.height - PlayerCover.CROUCH_HEIGHT) / (PlayerCover.STAND_HEIGHT - PlayerCover.CROUCH_HEIGHT), 0.0, 1.0) if c != null else 0.0
	_cover = PlayerUtil.spring(_cover, 1.0 if in_cover else crouch * 0.6, tx.f("cover_spring"), dt)
	_peek = PlayerUtil.spring(_peek, 1.0 if (in_cover and c.peeking) else 0.0, tx.f("cover_spring") * 1.3, dt)
	tw.x += _cover.x * tx.f("cover_lean") * (1.0 - _peek.x * 0.8)
	hips.y -= _cover.x * tx.f("cover_crouch") * 0.35
	tw.z += _peek.x * tx.f("cover_roll") * (side if side != 0.0 else 1.0)
	tw.y += _peek.x * tx.f("cover_twist") * (side if side != 0.0 else 1.0) * 0.5
	if _cover.x > 0.3:
		st = &"peek" if _peek.x > 0.4 else &"cover"

	# ---- takedown, slam, glide, wall-run
	var strike := c.strike if c != null else 0.0
	if strike > 0.0:
		tw.x += strike * tx.f("takedown_pitch")
		tw.y += strike * tx.f("takedown_twist")
		hips.y -= strike * tx.f("takedown_hips")
		st = &"takedown"
	var v = p.verbs
	var slamming: bool = v != null and v.slamming
	var wall: bool = v != null and v.wall_running
	if slamming:
		tw.x += tx.f("slam_pitch")
		hips.y -= tx.f("slam_hips")
		st = &"slam"
	_glide = PlayerUtil.spring(_glide, 1.0 if (p.gliding and not slamming and not wall) else 0.0, tx.f("glide_spring"), dt)
	tw.x += _glide.x * tx.f("glide_pitch")
	tw.z += _glide.x * sin(_t * 1.3) * tx.f("glide_roll_sway")
	if _glide.x > 0.5:
		st = &"glide"
	var wside: float = v.wall_side if v != null else 0.0
	_wall = PlayerUtil.spring(_wall, 1.0 if wall else 0.0, tx.f("wall_spring"), dt)
	tw.z += _wall.x * tx.f("wall_roll") * wside
	tw.y += _wall.x * tx.f("wall_twist") * wside
	if _wall.x > 0.5:
		st = &"wall"

	# ---- vault and mantle: lean over the obstacle, both hands placed on it
	var hw := Vector2.ZERO
	var tr = p.traversal
	var hand_l := Vector3.ZERO
	var hand_r := Vector3.ZERO
	if tr != null and tr.kind != Traversal.Kind.NONE and tr.kind != Traversal.Kind.CLIMB:
		var k: float = tr.progress()
		var reach := sin(PI * clampf(k * 1.15, 0.0, 1.0))
		hw = Vector2(reach, reach)
		if tr.kind == Traversal.Kind.VAULT:
			tw.x += reach * tx.f("vault_lean")
			hips.y -= reach * tx.f("vault_hips")
			hand_l = Vector3(-tx.f("vault_hand_x"), tx.f("vault_hand_y"), tx.f("vault_hand_z"))
			hand_r = Vector3(tx.f("vault_hand_x"), tx.f("vault_hand_y"), tx.f("vault_hand_z"))
			st = &"vault"
		else:
			tw.x += reach * tx.f("mantle_lean")
			hand_l = Vector3(-tx.f("vault_hand_x"), tx.f("mantle_hand_y"), tx.f("mantle_hand_z"))
			hand_r = Vector3(tx.f("vault_hand_x"), tx.f("mantle_hand_y"), tx.f("mantle_hand_z"))
			st = &"mantle"
	_hand = _hand.lerp(hw, 1.0 - exp(-tx.f("hand_spring") * dt))
	rig.hand_w = _hand
	rig.hand_off_l = hand_l
	rig.hand_off_r = hand_r
	_pose = _pose.lerp(hips, 1.0 - exp(-18.0 * dt))
	rig.pose_hips = _pose
	rig.extra_torso = Vector3(tw.x, rig.extra_torso.y + tw.y, tw.z)      # Locomotion rewrites y every frame and keeps x and z: those are ours alone
	state = st

	_update_head(dt, body, p, aim_target)
	_update_feet(dt, body, p, grounded)


## Head: look toward the target within range, else the aim (Locomotion already leads with the aim); saccades and blinks on top.
func _update_head(dt: float, body: Node3D, p: Player, aim_target: Variant) -> void:
	var tx := Tune
	var yaw_t := 0.0
	var pitch_t := 0.0
	if aim_target is Node3D and is_instance_valid(aim_target):
		var d: Vector3 = (aim_target as Node3D).global_position + Vector3(0.0, 1.5, 0.0) - (body.global_position + Vector3(0.0, 1.6, 0.0))
		if d.length() < tx.f("look_range") and d.length() > 0.5:
			var fwd_yaw := body.rotation.y
			var want_yaw := atan2(-d.x, -d.z)
			yaw_t = clampf(angle_difference(fwd_yaw, want_yaw), -tx.f("look_yaw_max"), tx.f("look_yaw_max"))
			pitch_t = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -tx.f("look_pitch_max"), tx.f("look_pitch_max"))
	_look = PlayerUtil.spring(_look, yaw_t, tx.f("look_spring"), dt)
	_look_p = PlayerUtil.spring(_look_p, pitch_t, tx.f("look_spring"), dt)
	_sacc_t -= dt
	if _sacc_t <= 0.0:
		_sacc_t = tx.f("saccade_every") * _rng.randf_range(0.5, 1.5)
		_sacc_goal = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.6, 0.6)) * tx.f("saccade_amp")
	_sacc = PlayerUtil.spring(_sacc, _sacc_goal.x, tx.f("saccade_spring"), dt)
	_sacc_p = PlayerUtil.spring(_sacc_p, _sacc_goal.y, tx.f("saccade_spring"), dt)
	gaze = Vector2(_sacc.x, _sacc_p.x)
	_blink_t -= dt
	if _blink_t <= 0.0 and _blink_k < 0.0:
		_blink_k = 0.0
		_blink_t = tx.f("blink_every") + _rng.randf() * tx.f("blink_jitter")
	if _blink_k >= 0.0:
		_blink_k += dt / tx.f("blink_time")
		if _blink_k >= 1.0:
			_blink_k = -1.0
			blink = 0.0
		else:
			blink = sin(PI * _blink_k)
	rig.head_look = rig.head_look + Vector2(_look.x + gaze.x, _look_p.x + gaze.y + blink * tx.f("blink_nod"))


## Soles follow the ground: a ray per foot (model space sole -> world), height clamped, pitch from the slope.
func _update_feet(dt: float, body: Node3D, p: Player, grounded: bool) -> void:
	var tx := Tune
	var space := body.get_world_3d().direct_space_state if body.is_inside_tree() else null
	var want := Vector2.ZERO
	var floor_n := Vector3.UP
	if space != null and grounded and p.is_on_floor():
		floor_n = p.get_floor_normal()
		var gb := body.global_basis
		var base_y := p.global_position.y
		for k in 2:
			var s: Vector3 = rig.sole_l if k == 0 else rig.sole_r
			var wp := body.global_transform * Vector3(s.x, 0.0, s.z)
			wp.y = base_y
			_rq.from = wp + Vector3(0.0, tx.f("foot_ray_up"), 0.0)
			_rq.to = wp - Vector3(0.0, tx.f("foot_ray_down"), 0.0)
			var hit := space.intersect_ray(_rq)
			if not hit.is_empty():
				want[k] = clampf((hit["position"] as Vector3).y - base_y, -tx.f("foot_max_down"), tx.f("foot_max_up"))
		var fwd := -gb.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var sp := atan2(-floor_n.dot(fwd), maxf(floor_n.y, 0.2))
		_slope_s = lerpf(_slope_s, sp, 1.0 - exp(-12.0 * dt))
	else:
		_slope_s = lerpf(_slope_s, 0.0, 1.0 - exp(-8.0 * dt))
	if not _fo_ready:
		_fo = want
		_fo_ready = true
	_fo = _fo.lerp(want, 1.0 - exp(-tx.f("foot_spring") * dt))
	foot_off_l = _fo.x
	foot_off_r = _fo.y
	slope = _slope_s
	var sp_pitch := clampf(_slope_s * tx.f("slope_pitch_mul"), -tx.f("slope_pitch_max"), tx.f("slope_pitch_max"))
	# a raised sole keeps its swing arc: the offset applies in proportion to the support the foot carries (a planted foot follows the step, a swinging one clears it)
	rig.sole_l.y += _fo.x * (0.4 + 0.6 * rig.support_l)
	rig.sole_r.y += _fo.y * (0.4 + 0.6 * rig.support_r)
	rig.pitch_l += sp_pitch * rig.support_l
	rig.pitch_r += sp_pitch * rig.support_r
