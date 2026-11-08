extends RefCounted
## The fight bot of the combat-feel wave: a hero standing in the street who shoots the nearest aware enemy it can see (the way a player with aim assist would) and reloads when empty.
## It plays through the real input actions and the real camera rig, so recoil, spread, tracers and hit feedback all run. It stays put unless somebody aware is near but a parked car or wall hides every one of them: then it steps sideways (_step_aside) until it has a line, and it
## is made nearly unkillable so a measurement run is not cut short. Numbers it keeps: shots, hits (Player.hit_confirmed), kills, the time of the first shot at an enemy.
## Use through preload: const FightBot := preload("res://tests/fight_bot.gd"); bot.step(dt) once per physics frame.

var p: Player
var shots := 0
var hits := 0
var kills := 0
var elapsed := 0.0
var first_shot_t := -1.0
var aim_error := 0.0                    ## radians of deliberate aim error (a human is not perfect)
var target: Drone
var _err := Vector3.ZERO
var _err_t := 0.0
var _shots_at_start := 0
var _strafe_t := 0.0
var _strafe_dir := 1.0
var strafe_fire := false                ## a player does not stand planted: with a target the hero side-steps (a new direction every 0.8-1.6 s) while it fires
var strafe_moves := 0
var _sf_t := 0.0
var _sf_dir := 1.0
var strafes := 0                        ## times the hero stepped aside to get a clear line (a parked car in the way)


func setup(player: Player) -> void:
	p = player
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	p.hit_confirmed.connect(_on_hit)
	_shots_at_start = p.weapon.shots_fired


func _on_hit(kill: bool, _crit: bool) -> void:
	hits += 1
	if kill:
		kills += 1


func finish() -> void:
	Input.action_release(&"fire")
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	if p != null and p.hit_confirmed.is_connected(_on_hit):
		p.hit_confirmed.disconnect(_on_hit)


## The nearest living, aware, active enemy within `reach` metres that the world does not hide (a ray against the world layer).
func pick(reach := 70.0) -> Drone:
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
		var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0.0, 1.5, 0.0), e.center(), Game.L_WORLD | Game.L_VEHICLE)         # a parked car stops a round: the player does not shoot the car
		if not space.intersect_ray(q).is_empty():
			continue
		best = e
		bd = d
	return best


func step(dt: float) -> void:
	elapsed += dt
	p.invuln = 5.0
	p.hp = p.max_hp
	if p.weapon.ammo <= 0 and not p.weapon.is_reloading():
		Input.action_press(&"reload")
	else:
		Input.action_release(&"reload")
	if target == null or not is_instance_valid(target) or target.dead or not target.active:
		target = pick()
	if target == null:
		Input.action_release(&"fire")
		_step_aside(dt)
		return
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	_strafe_t = 0.0
	if strafe_fire:
		_sf_t -= dt
		if _sf_t <= 0.0:
			_sf_t = randf_range(0.8, 1.6)
			_sf_dir = -_sf_dir
			strafe_moves += 1
		Input.action_press(&"move_right" if _sf_dir > 0.0 else &"move_left")
	_err_t -= dt
	if _err_t <= 0.0:
		_err_t = 0.35
		_err = Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6), randf_range(-1.0, 1.0)) * aim_error * target.global_position.distance_to(p.global_position)
	p.camera_rig.aim_at(target.center() + _err)
	Input.action_press(&"fire")
	shots = p.weapon.shots_fired - _shots_at_start
	if first_shot_t < 0.0 and shots > 0:
		first_shot_t = elapsed


func kills_per_minute() -> float:
	return float(kills) / maxf(elapsed / 60.0, 0.001)


## Somebody aware is near but no clear line (a car, a corner): a player steps sideways until there is one. Alternates sides every 0.9 s.
func _step_aside(dt: float) -> void:
	var mgr := Game.enemies as EnemyManager
	var near := false
	for e in mgr.list:
		if e.active and not e.dead and e.aware and e.global_position.distance_to(p.global_position) < 45.0:
			near = true
			break
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	if not near:
		_strafe_t = 0.0
		return
	if _strafe_t <= 0.0:
		_strafe_t = 0.9
		_strafe_dir = -_strafe_dir
		strafes += 1
	_strafe_t -= dt
	Input.action_press(&"move_right" if _strafe_dir > 0.0 else &"move_left")
