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
const RELAX_DROP := 0.985       ## relaxed arm: hand distance below the shoulder as a fraction of the arm length (a slight elbow bend)
const RELAX_SWING := 0.42       ## relaxed arm swing: metres of hand travel per radian of the opposite thigh swing

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
var death_time := DEATH_TIME  ## seconds the fall takes (the owner syncs it with the body's own tumble)
var buckle := 0.0             ## knee buckle 0..1 (the knees give way first, then ease off as the body goes limp)
var _state_t := 0.0


## Back to the idle pose (pooled enemies are reused).
func reset() -> void:
	state = State.IDLE
	aim_pitch = 0.0
	ready = 0.4
	recoil = 0.0
	flinch = 0.0
	flinch_dir = Vector2.ZERO
	charge = 0.0
	dead = 0.0
	buckle = 0.0
	death_kind = 0
	shots = 0
	_state_t = 0.0


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
			var dt_total := maxf(death_time, 0.05)
			dead = clampf((_state_t - 0.25 * dt_total) / (0.75 * dt_total), 0.0, 1.0)
			buckle = clampf(_state_t / (0.45 * dt_total), 0.0, 1.0) * (1.0 - 0.6 * dead * (2.0 - dead))


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
	rig.knee_buckle = buckle if state == State.DEAD else 0.0
	rig.reload = -1.0


## Model-space transform of the muzzle node: the rig's own (it follows the Rifle bone, the carbine mesh is skinned to it) shifted along the rifle by the weapon mount's muzzle offset
## relative to the carbine, so a pistol or a launcher mount puts tracers where its barrel would end. The grip offset of MOUNTS is informational: the hands are solved on the
## carbine's grips by the rig (the shared skeleton has one weapon mesh).
func muzzle_transform(rig: CharacterRig) -> Transform3D:
	var t := rig.muzzle_transform()
	var delta: Vector3 = (mount()["muzzle"] as Vector3) - (MOUNTS[&"rifle"]["muzzle"] as Vector3)
	if delta != Vector3.ZERO:
		t.origin += t.basis * delta
	return t


## Unarmed people (citizens): both arms hang relaxed at the sides and swing against the legs while walking, instead of holding a rifle. Call after Locomotion.update() and before
## rig.apply(); the hand targets are relative to the shoulders (the rig's hand placement inputs), so nothing is allocated and no rig state beyond hand_w / hand_off is touched.
static func relax_arms(rig: CharacterRig) -> void:
	rig.hand_w = Vector2.ONE
	for k in 2:
		var left := k == 0
		var side := -1.0 if left else 1.0
		var opposite := rig.hip_r.x if left else rig.hip_l.x          # the arm swings forward with the opposite leg
		var off := Vector3(side * 0.07, -rig.arm_reach(k) * RELAX_DROP, 0.03 - opposite * RELAX_SWING)
		if left:
			rig.hand_off_l = off
		else:
			rig.hand_off_r = off
