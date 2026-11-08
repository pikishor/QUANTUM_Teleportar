extends RefCounted
## The hero of the real-fight wave: a player who MOVES while he shoots (real input actions, real camera rig). He picks the nearest aware enemy that the world and the cars do not hide
## (and drops a target the moment it ducks behind something: the old bot kept firing into a parked van), strafes left and right while he fires, backs off when somebody is inside
## BACK_OFF metres, walks towards the fight when nobody is in sight, turns to the nearest threat when he has no target, reloads when empty. He is nearly unkillable (a measurement run
## must not be cut short). Numbers kept: shots, hits, kills, moved metres, strafe switches, back steps, advance steps, the time of the first shot.
## Use through preload: const RealFightBot := preload("res://tests/real_fight_bot.gd"); bot.step(dt) once per physics frame.

const BACK_OFF := 6.5
const ADVANCE_FROM := 30.0
const RETARGET := 0.3

var p: Player
var shots := 0
var hits := 0
var kills := 0
var elapsed := 0.0
var first_shot_t := -1.0
var aim_error := 0.012                  ## radians of deliberate aim error per metre of range scale (a human is not perfect)
var target: Drone
var moved := 0.0                        ## metres walked
var strafes := 0                        ## direction changes of the sideways run
var back_steps := 0                     ## physics frames spent backing off
var advance_steps := 0                  ## physics frames spent walking towards the fight
var turns := 0                          ## turns to a threat without a target
var fire_while_moving := 0              ## physics frames in which he fired while his speed was above 1.5 m/s

var _err := Vector3.ZERO
var _err_t := 0.0
var _pick_t := 0.0
var _sf_t := 0.0
var _sf_dir := 1.0
var _turn_t := 0.0
var _last := Vector3.INF
var _shots_at_start := 0
var _god := true


func setup(player: Player, god := true) -> void:
	p = player
	_god = god
	if god:
		p.max_hp = 1.0e6
		p.hp = p.max_hp
	p.hit_confirmed.connect(_on_hit)
	_shots_at_start = p.weapon.shots_fired
	_last = p.global_position


func _on_hit(kill: bool, _crit: bool) -> void:
	hits += 1
	if kill:
		kills += 1


func finish() -> void:
	for a: StringName in [&"fire", &"move_left", &"move_right", &"move_forward", &"move_back", &"reload"]:
		Input.action_release(a)
	if p != null and p.hit_confirmed.is_connected(_on_hit):
		p.hit_confirmed.disconnect(_on_hit)


## The nearest aware enemy within `reach` that nothing hides from the hero's eye (world and vehicles).
func pick(reach := 60.0) -> Drone:
	var mgr := Game.enemies as EnemyManager
	var best: Drone = null
	var bd := reach
	var space := p.get_world_3d().direct_space_state
	for e in mgr.list:
		if not e.active or e.dead or not e.aware:
			continue
		var d := e.global_position.distance_to(p.global_position)
		if d >= bd:
			continue
		if not clear_to(space, e):
			continue
		best = e
		bd = d
	return best


func clear_to(space: PhysicsDirectSpaceState3D, e: Drone) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0.0, 1.5, 0.0), e.center(), Game.L_WORLD | Game.L_VEHICLE)
	return space.intersect_ray(q).is_empty()


## The nearest aware enemy (hidden or not) and its distance.
func nearest_aware(reach := 80.0) -> Drone:
	var mgr := Game.enemies as EnemyManager
	var best: Drone = null
	var bd := reach
	for e in mgr.list:
		if not e.active or e.dead or not e.aware:
			continue
		var d := e.global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func _hold(dir: StringName, on: bool) -> void:
	if on:
		Input.action_press(dir)
	else:
		Input.action_release(dir)


func step(dt: float) -> void:
	elapsed += dt
	if _god:
		p.invuln = 5.0
		p.hp = p.max_hp
	if _last.is_finite():
		moved += Vector2(p.global_position.x - _last.x, p.global_position.z - _last.z).length()
	_last = p.global_position
	if p.weapon.ammo <= 0 and not p.weapon.is_reloading():
		Input.action_press(&"reload")
	else:
		Input.action_release(&"reload")
	_pick_t -= dt
	if target == null or not is_instance_valid(target) or target.dead or not target.active:
		target = null
		_pick_t = 0.0
	if _pick_t <= 0.0:
		_pick_t = RETARGET
		var keep := target
		if keep != null and not clear_to(p.get_world_3d().direct_space_state, keep):
			keep = null                                          # it ducked behind a car: a player stops shooting the car
		target = keep if keep != null else pick()
	var near := nearest_aware()
	var near_d := near.global_position.distance_to(p.global_position) if near != null else 1.0e9
	var fwd := false
	var back := false
	var left := false
	var right := false
	if target != null:
		_err_t -= dt
		if _err_t <= 0.0:
			_err_t = 0.35
			_err = Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6), randf_range(-1.0, 1.0)) * aim_error * target.global_position.distance_to(p.global_position)
		p.camera_rig.aim_at(target.center() + _err)
		Input.action_press(&"fire")
		shots = p.weapon.shots_fired - _shots_at_start
		if first_shot_t < 0.0 and shots > 0:
			first_shot_t = elapsed
		_sf_t -= dt
		if _sf_t <= 0.0:
			_sf_t = randf_range(0.45, 0.9)
			_sf_dir = -_sf_dir
			strafes += 1
		left = _sf_dir < 0.0
		right = _sf_dir > 0.0
		if near_d < BACK_OFF:
			back = true
			back_steps += 1
		elif near_d > ADVANCE_FROM:
			fwd = true
			advance_steps += 1
	else:
		Input.action_release(&"fire")
		if near != null:                                           # somebody is coming but there is no line: turn to him, side-step to open a line, walk in when far
			_turn_t -= dt
			if _turn_t <= 0.0:
				_turn_t = 1.2
				turns += 1
				p.camera_rig.aim_at(near.center())
			_sf_t -= dt
			if _sf_t <= 0.0:
				_sf_t = 0.9
				_sf_dir = -_sf_dir
				strafes += 1
			left = _sf_dir < 0.0
			right = _sf_dir > 0.0
			if near_d > 22.0:
				fwd = true
				advance_steps += 1
	_hold(&"move_left", left)
	_hold(&"move_right", right)
	_hold(&"move_forward", fwd)
	_hold(&"move_back", back)
	if target != null and p.velocity.length() > 1.5:
		fire_while_moving += 1
