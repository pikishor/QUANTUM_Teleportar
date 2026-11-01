class_name Stability
extends Node
## The game's stability watchdog (composed by main.gd). Owns every "the screen got stuck" safety net that does not belong to a single module:
##  * input: when the state leaves play every held action is released (and again every frame while not playing), so a finger or key held across death,
##    pause, win or an app switch never keeps firing, driving or sprinting;
##  * time: the death slow motion is the only thing that ever touches Engine.time_scale; it is timed in REAL seconds, restored on any state change, on focus
##    return and on exit, and it puts back the value it found (test harnesses run at k times speed);
##  * feedback: hurt pulses and the death grade go to the Atmosphere with caps, and every transient (shake, hurt, grade) is cleared on a respawn, a new game and the menu;
##  * consistency audit after every transition and twice a second while playing: camera mode vs. vehicle, player body visible and collider on the player layer when on
##    foot, a live current camera, HUD layers matching the state; anything off is repaired and reported through `repairs`;
##  * the menu is light: while Game.state is menu the world and the atmosphere render at the LOW tier (cheaper rain, mirror and post), restored when the game starts.

signal repaired(what: String)

const SLOWMO_SCALE := 0.3                   ## Engine.time_scale during the death slow motion
const SLOWMO_HOLD := 1.1                    ## real seconds at that speed ...
const SLOWMO_RAMP := 0.5                    ## ... then eased back to normal over this many
const AUDIT_EVERY := 0.5
const INPUT_ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"reload", &"blink",
		&"entangle", &"superpose", &"interact", &"fire", &"aim"]

var repairs: Array[String] = []              ## what the audit had to fix (tests and the error log read it)
var slowmo_active := false
var menu_light := false

var _base_scale := 1.0
var _slow_scale := SLOWMO_SCALE
var _slow_hold := SLOWMO_HOLD
var _slow_ramp := SLOWMO_RAMP
var _slow_state: StringName = &"dead"       ## the slow motion belongs to this state and ends with it (death: dead; the boss beat: the cutscene state)
var _slow_t0 := 0.0
var _audit_t := 0.0
var _audit_soon := 0.0
var _player: Object
var _hud: Object


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 200
	Game.state_changed.connect(_on_state)
	Game.player_died.connect(_on_died)
	Game.new_game.connect(_clear_transients)
	Game.respawn.connect(_clear_transients)
	Game.next_sector.connect(_clear_transients)
	_on_state(Game.state)


func _exit_tree() -> void:
	end_slowmo()
	_set_menu_light(false)
	release_inputs()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		if not slowmo_active and Game.state != &"dead":
			_audit_soon = 0.05
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_inputs()


# ---------------------------------------------------------------------------------------------------------------------
# input watchdog
# ---------------------------------------------------------------------------------------------------------------------

## Lets go of every gameplay action (touch layers and bots press them through Input.action_press).
func release_inputs() -> void:
	for a: StringName in INPUT_ACTIONS:
		if InputMap.has_action(a):
			Input.action_release(a)


# ---------------------------------------------------------------------------------------------------------------------
# state transitions
# ---------------------------------------------------------------------------------------------------------------------

func _on_state(s: StringName) -> void:
	if s != &"play":
		release_inputs()
	if s != _slow_state:
		end_slowmo()
	if s != &"dead":
		_atmosphere_dead(false)
	if s == &"menu":
		_clear_transients()
	_set_menu_light(s == &"menu")
	_audit_soon = 0.05                       # after the other modules have reacted to the same transition


func _on_died() -> void:
	begin_slowmo()
	_atmosphere_dead(true)


func _clear_transients() -> void:
	FX.shake_amount = 0.0
	if is_instance_valid(Game.atmosphere) and Game.atmosphere.has_method(&"clear_feedback"):
		Game.atmosphere.call(&"clear_feedback")
	_audit_soon = 0.05


func _atmosphere_dead(on: bool) -> void:
	if is_instance_valid(Game.atmosphere) and Game.atmosphere.has_method(&"set_dead"):
		Game.atmosphere.call(&"set_dead", on)


## The death slow motion: Engine.time_scale SLOWMO_SCALE for SLOWMO_HOLD real seconds, then back to the value it replaced.
## The cinematics reuse it for the boss beats (scale / hold / ramp given, ending with the state they began in).
func begin_slowmo(scale := SLOWMO_SCALE, hold := SLOWMO_HOLD, ramp := SLOWMO_RAMP) -> void:
	if not slowmo_active:
		_base_scale = Engine.time_scale if Engine.time_scale > 0.0 else 1.0
		slowmo_active = true
	_slow_scale = clampf(scale, 0.1, 1.0)
	_slow_hold = hold
	_slow_ramp = maxf(ramp, 0.05)
	_slow_state = Game.state
	_slow_t0 = Time.get_ticks_usec() * 0.000001
	Engine.time_scale = minf(_base_scale, _slow_scale) if _base_scale <= 1.0 else _base_scale * _slow_scale


## Always safe: restores the time scale that begin_slowmo() replaced. Does nothing when no slow motion is running (never overrides someone else's scale).
func end_slowmo() -> void:
	if slowmo_active:
		slowmo_active = false
		Engine.time_scale = _base_scale
	_slow_state = &"dead"


func _slowmo_step() -> void:
	var t := Time.get_ticks_usec() * 0.000001 - _slow_t0
	if t >= _slow_hold + _slow_ramp or Game.state != _slow_state:
		end_slowmo()
	elif t > _slow_hold:
		var low := minf(_base_scale, _slow_scale) if _base_scale <= 1.0 else _base_scale * _slow_scale
		Engine.time_scale = lerpf(low, _base_scale, smoothstep(0.0, 1.0, (t - _slow_hold) / _slow_ramp))


# ---------------------------------------------------------------------------------------------------------------------
# hurt feedback
# ---------------------------------------------------------------------------------------------------------------------

func _connect_player() -> void:
	var p: Object = Game.player if is_instance_valid(Game.player) else null
	if p == _player:
		return
	_player = p
	if p != null and p.has_signal(&"hurt"):
		p.connect(&"hurt", _on_hurt)


func _on_hurt(amount: float) -> void:
	if is_instance_valid(Game.atmosphere) and Game.atmosphere.has_method(&"hurt_pulse"):
		Game.atmosphere.call(&"hurt_pulse", clampf(amount / 30.0, 0.35, 1.0))


# ---------------------------------------------------------------------------------------------------------------------
# menu
# ---------------------------------------------------------------------------------------------------------------------

## While the title is up the world and the atmosphere draw at the LOW tier (Game.quality is untouched, so nothing else reacts); leaving the menu restores them.
func _set_menu_light(on: bool) -> void:
	if on == menu_light:
		return
	menu_light = on
	if Game.quality <= 0:
		return
	var w: Object = Game.world if is_instance_valid(Game.world) else null
	var a: Object = Game.atmosphere if is_instance_valid(Game.atmosphere) else null
	var q := 0 if on else Game.quality
	if w != null and w.has_method(&"set_quality"):
		w.call(&"set_quality", q)
	if a != null and a.has_method(&"set_quality"):
		a.call(&"set_quality", q)


# ---------------------------------------------------------------------------------------------------------------------
# audit
# ---------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_connect_player()
	if slowmo_active:
		_slowmo_step()
	if Game.state != &"play":
		for a: StringName in INPUT_ACTIONS:
			if Input.is_action_pressed(a):
				release_inputs()
				break
	var real := delta / maxf(Engine.time_scale, 0.05)
	if _audit_soon > 0.0:
		_audit_soon -= real
		if _audit_soon <= 0.0:
			audit()
	_audit_t += real
	if _audit_t >= AUDIT_EVERY:
		_audit_t = 0.0
		audit()


func _fix(what: String) -> void:
	repairs.append(what)
	if repairs.size() > 40:
		repairs.remove_at(0)
	repaired.emit(what)


## Checks that camera, player, shake, time and HUD layers agree with the state, repairs what does not and returns what it repaired.
func audit() -> Array[String]:
	var fixed: Array[String] = []
	var p := Game.player as Player
	if p != null and is_instance_valid(p) and p.camera_rig != null:
		var rig := p.camera_rig
		var driving := p.vehicle != null
		if rig.mode == &"vehicle" and not driving:
			rig.recover_to_player()
			fixed.append("camera followed a vehicle the player is not in")
		elif driving and rig.mode != &"vehicle":
			rig.mode = &"vehicle"
			rig.follow_target = p.vehicle
			fixed.append("camera not in vehicle mode while driving")
		if not driving:
			if p.body != null and not p.body.visible:
				p.body.visible = true
				fixed.append("player body hidden on foot")
			if p.collision_layer != Game.L_PLAYER:
				p.collision_layer = Game.L_PLAYER
				p.collision_mask = Game.L_WORLD | Game.L_ENEMY | Game.L_VEHICLE
				fixed.append("player collider off on foot")
			if rig.follow_target != p:
				rig.follow_target = p
				fixed.append("camera follows something else on foot")
		if is_instance_valid(rig.camera) and not rig.camera.current:
			rig.camera.make_current()
			fixed.append("gameplay camera not current")
	if not (FX.shake_amount >= 0.0 and FX.shake_amount <= 1.0):
		FX.shake_amount = clampf(FX.shake_amount if is_finite(FX.shake_amount) else 0.0, 0.0, 1.0)
		fixed.append("shake out of range")
	if Game.state == &"cutscene":              # a cutscene state with no cinematic running (it errored or was freed) would freeze the game for good
		var cine := get_tree().get_first_node_in_group(&"cinematics")
		if cine == null or not bool(cine.get(&"active")):
			Game.state = &"play"
			fixed.append("cutscene state left without a cinematic")
	if p != null and is_instance_valid(p) and p.camera_rig != null and p.camera_rig.is_cinematic() and Game.state == &"play" and not _cine_allowed():
		p.camera_rig.cine_clear()
		fixed.append("cinematic camera left on during play")
	if not slowmo_active and Game.state == &"play" and Engine.time_scale > 0.0 and Engine.time_scale < 0.9 and _base_scale >= 0.9:
		Engine.time_scale = _base_scale
		fixed.append("time scale left slowed")
	if _hud == null or not is_instance_valid(_hud):
		_hud = _find_hud()
	if _hud != null and _hud.has_method(&"refresh_layers") and not bool(_hud.call(&"layers_consistent")):
		_hud.call(&"refresh_layers")
		fixed.append("HUD layers did not match the state")
	for f in fixed:
		_fix(f)
	return fixed


## The cinematics themselves may hold the camera during play (never today: the boss beats run in the cutscene state), nothing else may.
func _cine_allowed() -> bool:
	var cine := get_tree().get_first_node_in_group(&"cinematics")
	return cine != null and bool(cine.get(&"active"))


func _find_hud() -> Object:
	var par := get_parent()
	if par == null:
		return null
	for c in par.get_children():
		if c is Hud:
			return c
	return null
