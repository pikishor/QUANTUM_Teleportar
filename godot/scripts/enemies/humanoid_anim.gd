class_name HumanoidAnim
extends RefCounted
## Procedural combat layer of the humanoid enemy variants, on the hero-shared rig (CharacterRig + Locomotion own the legs, pelvis and gait: reuse them).
## This class owns the upper-body state machine and writes only the combat inputs of the rig: aim, fire kick, windup tell, hit flinch, death fall.
##   states  IDLE, AIM (rifle up, torso blades), FIRE (recoil kick per shot), WINDUP (telegraph: the tell charge 0..1 rises), HIT (flinch from a direction), DEAD.
## Everything is a closed form or a critically damped decay: no allocation per frame.

enum State { IDLE, AIM, FIRE, WINDUP, HIT, DEAD }

## Per variant weapon mount: grip offset in the Rifle bone frame (metres) and the muzzle offset past the grip.
const MOUNTS := {
	&"rifle": {"grip": Vector3(0.0, -0.04, -0.1), "muzzle": Vector3(0.0, 0.02, -0.75), "ready": 0.9},
	&"pistol": {"grip": Vector3(0.0, -0.03, -0.05), "muzzle": Vector3(0.0, 0.02, -0.3), "ready": 0.7},
	&"shotgun": {"grip": Vector3(0.0, -0.04, -0.12), "muzzle": Vector3(0.0, 0.02, -0.7), "ready": 0.85},
	&"launcher": {"grip": Vector3(0.0, -0.06, -0.1), "muzzle": Vector3(0.0, 0.05, -0.9), "ready": 1.0},
}
const FLINCH_TIME := 0.35
const FIRE_KICK := 1.0
const DEATH_TIME := 1.1

var state := State.IDLE
var aim_pitch := 0.0
var ready := 0.4          ## rifle raise 0 low .. 1 up
var recoil := 0.0
var flinch := 0.0
var flinch_dir := Vector2.ZERO
var charge := 0.0         ## telegraph 0..1
var dead := 0.0           ## 0..1 fall progress
var death_kind := 0
var shots := 0
var weapon: StringName = &"rifle"
var windup_time := 0.6
var _state_t := 0.0


func set_weapon(w: StringName) -> void:
	weapon = w if MOUNTS.has(w) else &"rifle"


func mount() -> Dictionary:
	return MOUNTS[weapon]


func set_state(s: State) -> void:
	if state == State.DEAD:
		return
	state = s
	_state_t = 0.0


func fire() -> void:
	if state == State.DEAD:
		return
	shots += 1
	recoil = FIRE_KICK
	state = State.FIRE
	_state_t = 0.0


func hit(dir: Vector2, strength := 1.0) -> void:
	if state == State.DEAD:
		return
	flinch = clampf(strength, 0.0, 1.0)
	flinch_dir = dir.normalized() if dir.length() > 0.001 else Vector2(0, 1)
	_state_t = 0.0
	if state != State.WINDUP:
		state = State.HIT


func die(kind := 0) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	death_kind = kind
	_state_t = 0.0


func update(dt: float, target_pitch := 0.0) -> void:
	_state_t += dt
	var k := 1.0 - exp(-12.0 * dt)
	aim_pitch = lerpf(aim_pitch, clampf(target_pitch, -0.6, 0.6), k)
	recoil = maxf(0.0, recoil - dt * 7.0)
	flinch = maxf(0.0, flinch - dt / FLINCH_TIME)
	var want_ready := 0.4
	match state:
		State.AIM, State.FIRE, State.WINDUP:
			want_ready = float(mount()["ready"])
		State.HIT:
			want_ready = 0.5
		State.DEAD:
			want_ready = 0.0
	ready = lerpf(ready, want_ready, k)
	if state == State.WINDUP:
		charge = clampf(_state_t / maxf(windup_time, 0.05), 0.0, 1.0)
	else:
		charge = maxf(0.0, charge - dt * 4.0)
	match state:
		State.FIRE:
			if _state_t > 0.15:
				state = State.AIM
		State.HIT:
			if flinch <= 0.0:
				state = State.AIM
		State.DEAD:
			dead = clampf(_state_t / DEATH_TIME, 0.0, 1.0)


## True once a windup has fully charged (the shot may go out).
func windup_done() -> bool:
	return state == State.WINDUP and charge >= 1.0


## Write the combat inputs to the rig (call before rig.apply(), after Locomotion.update()).
func write(rig: CharacterRig) -> void:
	rig.aim_pitch = aim_pitch
	rig.ready = ready
	rig.recoil = recoil
	rig.flinch = flinch
	rig.flinch_dir = flinch_dir * minf(1.0, flinch * 2.0)
	rig.death_kind = death_kind
	rig.dead = dead
	rig.knee_buckle = 0.6 * dead if state == State.DEAD else 0.0
	rig.reload = -1.0
