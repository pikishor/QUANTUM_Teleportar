class_name PhaseThrough
extends RefCounted
## Phase-through (B5): while QUANTUM TELEPORT or a short phase-step is active the hero passes thin walls, fences and doors (bodies in group THIN_GROUP; buildings
## and the ground never are). Done with per-body collision exceptions on the player only, so enemies, projectiles and vehicles keep colliding with the same bodies and
## no physics layer is changed. When the phase ends inside a thin body it is extended (up to GRACE) and then the player is pushed out through PlayerUtil.safe_spot.

const THIN_GROUP := &"thin_wall"
const TELEPORT_TIME := 1.2          ## seconds of phase after a QUANTUM TELEPORT
const STEP_TIME := 0.5              ## a short phase-step
const STEP_COST := 10.0
const STEP_CD := 3.0
const GRACE := 1.0                  ## extra seconds allowed to leave a wall before the push-out

var left := 0.0                     ## seconds of phase remaining (HUD)
var cd := 0.0
var shimmer := 0.0                  ## 0..1 screen / body effect strength (HUD)
var _p: Player
var _ex: Array[PhysicsBody3D] = []
var _grace := 0.0


func _init(p: Player) -> void:
	_p = p


func active() -> bool:
	return left > 0.0 or not _ex.is_empty()


## Start (or extend) a phase of `t` seconds.
func begin(t: float) -> void:
	if _p == null:
		return
	if left <= 0.0:
		FX.burst(_p.global_position + Vector3(0.0, 1.0, 0.0), Quantum.PALE, 14, 4.0, 0.4, 0.0)
	left = maxf(left, t)
	_grace = 0.0
	_sync()


## The short phase-step: costs coherence, has its own cooldown. Returns true when started.
func step() -> bool:
	if _p == null or cd > 0.0 or left > 0.0 or not Game.is_playing() or _p.is_dead() or _p.vehicle != null or _p.energy < STEP_COST:
		return false
	_p.energy -= STEP_COST
	cd = STEP_CD
	begin(STEP_TIME)
	return true


func tick(delta: float) -> void:
	cd = maxf(cd - delta, 0.0)
	shimmer = move_toward(shimmer, 1.0 if left > 0.0 else 0.0, delta * 6.0)
	if left > 0.0:
		left = maxf(left - delta, 0.0)
		_sync()
	elif not _ex.is_empty():
		if _inside() and _grace < GRACE:
			_grace += delta
		else:
			var was_inside := _inside()
			end()
			if was_inside:
				_p.teleport_to(_p.global_position)


## Drop every exception at once (death, new game, vehicle).
func end() -> void:
	left = 0.0
	_grace = 0.0
	for b in _ex:
		if is_instance_valid(b) and is_instance_valid(_p):
			_p.remove_collision_exception_with(b)
	_ex.clear()


func _sync() -> void:
	if not is_instance_valid(_p) or not _p.is_inside_tree():
		return
	for n in _p.get_tree().get_nodes_in_group(THIN_GROUP):
		var b := n as PhysicsBody3D
		if b != null and not _ex.has(b):
			_p.add_collision_exception_with(b)
			_ex.append(b)


## True while the player's capsule overlaps a thin body.
func _inside() -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, _p.global_position + Vector3(0.0, 0.95, 0.0))
	q.collision_mask = Game.L_WORLD
	for h in _p.get_world_3d().direct_space_state.intersect_shape(q, 8):
		if (h["collider"] as Node).is_in_group(THIN_GROUP):
			return true
	return false
