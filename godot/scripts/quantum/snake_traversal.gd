class_name SnakeTraversal
extends RefCounted
## THE HERO'S SIGNATURE MOVEMENT (wave 115): QUANTUM SNAKES as traversal. `Player.snake` owns one of these; Player._foot_tick calls `tick()` before anything else and, while a snake state owns the
## body, skips its own movement (the same contract as Traversal). Plain names: QUANTUM SNAKE, SNAKE SWING, SNAKE ZIP, SNAKE CLIMB, SNAKE FLIGHT.
##
## ONE contextual SNAKE button (action `snake`, touch SNAKE, key Tab) and ONE FLY / LAND button (action `fly`, touch FLY, key backslash):
##   in the air         hold SNAKE = SNAKE SWING at the best anchor up and ahead (the camera aims, the assist picks); keep holding = AUTO CHAIN; let go = launch with the release boost
##   on the ground      tap SNAKE = SNAKE ZIP to the aimed roof, ledge or wall (a wall ends in a climb); with nothing to zip to, the swing launches from the ground (a hop and a swing)
##   at a wall          tap SNAKE = SNAKE CLIMB (stick up, sideways; JUMP leaps off in the look direction; tap again lets go); ceilings too
##   no anchor in reach hold SNAKE (0.45 s) = SNAKE FLIGHT; FLY toggles it any time; in flight SNAKE held is BOOST
## The movement kit around it: DOUBLE JUMP (a second JUMP press while still rising: HeroPower air_jumps), SUPER JUMP (stand still, hold JUMP 0.3 s: the snake pushes the ground), AIR DASH (the existing QUANTUM
## GLIDE burst: a second press while falling), SAFE LANDING ROLL (a hard landing rolls and keeps the speed), plus the existing wall-run, ledge grab, mantle, vault and ground slam.
## Numbers: SnakePower (HeroPower rows by difficulty, skill nodes of the verb `snake`, HERO MODE). Energy: `energy` 0..100 (SnakePower.max_energy), regenerates on the ground, a third of that in the air.
## Shared tendril visual: SnakeTendril (snake_tendril.gd). Outputs for the body pose: `pose` (snake_pose.gd); for the camera: `cam` (snake_camera.gd). Counters (tests wait on these, not on frames):
## swings, zips, climbs, flights, double_jumps, super_jumps, rolls, whiffs, chain.

signal event(id: StringName)               ## swing_start, swing_attach, swing_release, zip, zip_land, climb, mantle, leap, flight, boost, land, double_jump, super_jump, whiff ... (the tutorial and the missions listen)

enum Mode { NONE, SWING, ZIP, CLIMB, FLY }

const DOUBLE_JUMP_SPEED := 8.4
const SUPER_THRUST := 58.0                 ## m/s^2 added while JUMP is held on the way up
const SUPER_TIME := 0.34
const SUPER_HOLD := 0.30                   ## seconds JUMP is held before the push begins (a tap is a plain jump)
const SUPER_MAX_STICK := 0.35             ## ... and the move stick is idle (forward + JUMP held is the vault / mantle / hop habit of a phone thumb, never a super jump)
const SUPER_MAX_RUN := 4.5                 ## the push only follows a jump from standing or walking: a hero who holds forward + JUMP is vaulting, mantling or hopping (Traversal), never super jumping
const ROLL_TIME := 0.56
const ROLL_FALL := 15.0                    ## landing faster than this (m/s down) rolls
const FLY_HOLD := 0.45
static var fly_show_air := 0.15            ## seconds in the air before the FLY button shows (was 0.3: after a JUMP tap the button was on screen for 0.38 s only, wave 116 touch probe)
const WHIFF_COOLDOWN := 0.35
const SCAN_RATE := 0.09
const ASSIST_DEFAULT := true

static var zip_takes_press := true         ## the press that started a zip cannot also start a flight when it is held on (a test switches it off to show the old behaviour)
static var assist := ASSIST_DEFAULT        ## the anchor assist (OPTIONS / TEST menu toggle): off = the crosshair ray alone
static var instance: SnakeTraversal        ## the player's (tests, tools and the HUD read it)
static var cpu_active_us := 0.0              ## script time of tick() while a snake state runs / while none does (microseconds and calls: the swing run test prints the means)
static var cpu_active_ticks := 0
static var cpu_idle_us := 0.0
static var cpu_idle_ticks := 0

var p: Player
var mode: int = Mode.NONE
var energy := 100.0
var anchors := SnakeAnchors.new()
var swing: SnakeSwing
var zip: SnakeZip
var climb: SnakeClimb
var flight: SnakeFlight
var director: SnakeMissionDirector            ## the courier of ROOFTOP CHASE, the tutorial flag and the first-time hints (snake_mission_director.gd)
var pose := SnakePose.new()
var cam := SnakeCamera.new()
var time := 0.0
var swings := 0                            ## counters
var zips := 0
var climbs := 0
var flights := 0
var double_jumps := 0
var super_jumps := 0
var landing_rolls := 0
var whiffs := 0
var best_chain := 0
var chain := 0                             ## consecutive swings without touching the ground
var swing_cd := 0.0
var zip_cd := 0.0
var air_jumps_used := 0
var air_momentum := 0.0                    ## seconds left of the weakened air steering after a release (the speed survives the first second)
var jump_consumed := false                 ## set by the double jump so the QUANTUM GLIDE burst does not take the same press
var roll_t := 0.0                          ## > 0 while a landing roll plays
var roll_speed := 0.0
var ground_time := 0.0
var preview: Dictionary = {}               ## the anchor the next swing would take (null while none is in sight): the marker reads it
var preview_kind: StringName = &""
var wall_ready := false                     ## a wall is in reach in front of the grounded hero (the button reads CLIMB)
var zip_target: Dictionary = {}             ## w117-rope: the SnakeAnchors.find_zip result behind zip_ready (the HUD marks that anchor: SnakeFx.zip_mark)
var zip_ready := false                      ## a zip target is under the crosshair (the button reads ZIP)
var hint: StringName = &"none"             ## what the SNAKE button would do now: swing, zip, climb, boost, fly, none (the touch button label reads it)
var last_label := ""
var jam_t := 0.0                           ## > 0 while a jammer keeps the snakes dead (jam(): the warden's phase pulse); the SNAKE and FLY presses do nothing and the button reads JAMMED
var jams := 0                              ## times a jammer reached the hero (counter)

var _glow_mode := -1                       ## the state whose suit glow is shown (_glow_tick)
var _glow_t := 0.0
var _snake_was := false
var _fly_was := false
var _jump_was := false
var _hold_t := 0.0
var _jump_hold_t := 0.0
var _stick := 0.0                         ## the move stick this tick (0..1): the super jump needs it idle
var _floor_speed := 0.0                    ## horizontal speed the hero had on the ground (a jump from a run is not a super jump)
var _super_t := 0.0
var _super_used := false
var _whiff_cd := 0.0
var _scan_t := 0.0
var _chain_armed := 0.0                    ## seconds the auto chain stays armed after an auto release
var _since_release := 0.0
var _chain_hit: Dictionary = {}
var _chain_t := -10.0
var _chain_scan := -10.0
var _fall_vy := 0.0
var _was_air := false
var _wish := Vector3.ZERO
var _swing_blocked_press := false
static var jump_takes := true               ## critic 117: false = the builders' state (the JUMP that lets go of a swing also fires the glide burst)
var _jump_taken := false
var _post_swing := false                   ## in the air after a swing was let go (wave 117: the air brake and the landing roll)
var air_brakes := 0                        ## ticks the air brake worked (counter)
var _whiff_tendril: SnakeTendril
var _rq := PhysicsRayQueryParameters3D.new()


func _init() -> void:
	swing = SnakeSwing.new(self)
	zip = SnakeZip.new(self)
	climb = SnakeClimb.new(self)
	flight = SnakeFlight.new(self)
	instance = self


func bind(player: Player) -> void:
	p = player
	energy = SnakePower.max_energy()
	if player.get_node_or_null("SnakeFx") == null:
		var fx := SnakeFx.new()
		fx.st = self
		player.add_child(fx)
	if player.get_node_or_null("SnakeDirector") == null:
		var dr := SnakeMissionDirector.new()
		dr.st = self
		player.add_child(dr)
		director = dr


## True while a snake state owns the body.
func active() -> bool:
	return mode != Mode.NONE


func mode_name() -> StringName:
	match mode:
		Mode.SWING: return &"swing"
		Mode.ZIP: return &"zip"
		Mode.CLIMB: return &"climb"
		Mode.FLY: return &"fly"
	return &"none"


## Drop everything without effects (respawn, vehicle, teleport, death).
func cancel() -> void:
	swing.cancel()
	zip.cancel()
	climb.cancel()
	flight.cancel()
	mode = Mode.NONE
	chain = 0
	air_momentum = 0.0
	_chain_armed = 0.0
	roll_t = 0.0
	_snake_was = false
	_fly_was = false
	_jump_hold_t = 0.0
	_super_used = false
	air_jumps_used = 0
	_hold_t = 0.0
	jam_t = 0.0
	cam.reset()
	pose.reset()


func reset() -> void:
	cancel()
	energy = SnakePower.max_energy()
	swing_cd = 0.0
	zip_cd = 0.0


# --- energy ------------------------------------------------------------------------------------------------------------------------

func energy_spend(a: float) -> bool:
	if a <= 0.0:
		return true
	if energy < a * 0.25:
		energy = 0.0
		return false
	energy = maxf(0.0, energy - a)
	return true


func energy_gain(a: float) -> void:
	energy = minf(SnakePower.max_energy(), energy + a)


func energy_fraction() -> float:
	return clampf(energy / SnakePower.max_energy(), 0.0, 1.0)


# --- world positions of the hero's limbs (where snakes leave and arrive) --------------------------------------------------------------

func _model_point(local: Vector3) -> Vector3:
	var rig: CharacterRig = p.body.rig if (p != null and p.body != null) else null
	if rig == null or rig.model == null or not rig.model.is_inside_tree():
		return p.global_position + Vector3(0.0, 1.3, 0.0)
	return rig.model.global_transform * local


func hand_pos(side: int) -> Vector3:
	var rig: CharacterRig = p.body.rig if (p != null and p.body != null) else null
	if rig == null or rig.model == null or not rig.model.is_inside_tree():
		return p.global_position + Vector3(0.0, 1.3, 0.0) + Vector3(cos(p.yaw), 0.0, -sin(p.yaw)) * (0.3 * float(side))
	return rig.model.global_transform * rig.wrist_position(0 if side < 0 else 1)


func hand_callable(side: int) -> Callable:
	return func() -> Vector3: return hand_pos(side)


func foot_callable(side: int) -> Callable:
	return func() -> Vector3: return _model_point(Vector3(0.12 * float(side), 0.1, 0.05))


func back_callable(side: int) -> Callable:
	return func() -> Vector3: return _model_point(FlightView.wing_root(side))


# --- the physics tick -----------------------------------------------------------------------------------------------------------------

## One physics tick from Player._foot_tick (play state only). `iv` the stick (x right, y back), `wish` its world direction, `jump_down` the JUMP button.
## Returns true when a snake state moved the body this tick (the caller then skips its own movement).
func tick(pl: Player, dt: float, iv: Vector2, wish: Vector3, on_floor: bool, jump_down: bool) -> bool:
	var t0 := Time.get_ticks_usec()
	var r := _tick_body(pl, dt, iv, wish, on_floor, jump_down)
	var us := float(Time.get_ticks_usec() - t0)
	if mode != Mode.NONE or r:
		cpu_active_us += us
		cpu_active_ticks += 1
	else:
		cpu_idle_us += us
		cpu_idle_ticks += 1
	return r


func _tick_body(pl: Player, dt: float, iv: Vector2, wish: Vector3, on_floor: bool, jump_down: bool) -> bool:
	p = pl
	time += dt
	_glow_tick(dt)
	if InteriorSpace.active or InteriorGameplay.active:           # no swinging indoors: a state that was running is dropped, the button is hidden
		if mode != Mode.NONE:
			cancel()
		return false
	_wish = wish
	var down := Input.is_action_pressed(&"snake")
	var pressed := down and not _snake_was
	_snake_was = down
	var fly_down := Input.is_action_pressed(&"fly")
	var fly_pressed := fly_down and not _fly_was
	_fly_was = fly_down
	if jam_t > 0.0:                                            # a jammer's pulse: the buttons are dead (a press says why), a held button starts nothing when the jam ends
		jam_t = maxf(0.0, jam_t - dt)
		if (pressed or fly_pressed) and _whiff_cd <= 0.0:
			_whiff_cd = WHIFF_COOLDOWN
			Game.say("SNAKE JAMMED", 0.9)
			Sfx.play(&"snk_miss", -6.0)
		pressed = false
		fly_pressed = false
		if down:
			_swing_blocked_press = true
	var jump_pressed := jump_down and not _jump_was
	_jump_was = jump_down
	var crouch := Input.is_action_pressed(&"crouch")
	jump_consumed = false
	# critic 117: a JUMP that a snake state took (let go of a swing, a leap off a haul or a wall) stays taken until the thumb lifts. The state returns before the hero's own
	# verbs run, so they saw the same press as NEW one tick later and fired the QUANTUM GLIDE burst on top: 14.6 -> 27.1 m/s along the camera, the swing's own velocity gone
	if not jump_down:
		_jump_taken = false
	elif jump_pressed and mode != Mode.NONE and jump_takes:
		_jump_taken = true
	if _jump_taken:
		jump_consumed = true
	swing_cd = maxf(0.0, swing_cd - dt)
	zip_cd = maxf(0.0, zip_cd - dt)
	_whiff_cd = maxf(0.0, _whiff_cd - dt)
	air_momentum = maxf(0.0, air_momentum - dt)
	_since_release += dt
	_chain_armed = maxf(0.0, _chain_armed - dt)
	_hold_t = _hold_t + dt if down else 0.0
	var air := not on_floor and p.air_time > 0.08
	# energy: it comes back on the ground and, a third as fast, anywhere that is not a snake effort
	if mode == Mode.NONE:
		energy_gain(SnakePower.regen() * (1.0 if on_floor else 0.34) * dt)
	elif mode == Mode.ZIP and zip.phase == &"land":
		energy_gain(SnakePower.regen() * 0.4 * dt)
	if on_floor:
		ground_time += dt
		if mode != Mode.FLY:
			chain = 0
			swing.chain = 0
	else:
		ground_time = 0.0
	var cam_fwd := _aim()
	var started_mode := mode
	match mode:
		Mode.SWING:
			var swing_was := swing.active
			if swing.tick(p, dt, wish, down, jump_pressed):
				return true
			_end_mode(Mode.SWING)
			if swing_was and not SnakeSwing.old_motion:
				return true                                    # wave 117: the swing moved the body in the tick it let go; the player's own air movement used to move it AGAIN in the same tick (a jump of twice the speed, 0.95 m at 28 m/s, on every release)
		Mode.ZIP:
			if zip.tick(p, dt, jump_pressed):
				return true
			if mode == Mode.ZIP:
				_end_mode(Mode.ZIP)
			else:
				return true
		Mode.CLIMB:
			if climb.tick(p, dt, iv, p.camera_rig.yaw, jump_pressed, pressed):
				return true
			if mode == Mode.CLIMB:
				_end_mode(Mode.CLIMB)
		Mode.FLY:
			if flight.tick(p, dt, iv, cam_fwd, jump_down, crouch, down, fly_pressed):
				return true
			_end_mode(Mode.FLY)
	if started_mode == Mode.CLIMB and pressed:                       # the tap that let go of a wall is not also a new press
		pressed = false
	# --- mode NONE: contextual buttons, auto chain, the movement kit
	if mode == Mode.NONE:
		_none_tick(dt, iv, wish, on_floor, air, down, pressed, fly_pressed, jump_down, jump_pressed, crouch)
		if mode != Mode.NONE:
			return true
	return false


## The suit answers the snakes (critic 115 look: HeroLook has a layer for exactly this, "flow: SWING, energy runs from the core to the hands" and "wings: FLIGHT, the wing mounts burn", and nothing
## called it): the circuits flow while he swings, zips or climbs and the wing mounts burn in flight; a state that ends releases its layer. A power armed by the combat wave owns the hands
## (SnakeWar sets the same flow layer in the colour of the power), so the traversal leaves that layer alone then. Cheap: it acts on a change of state and re-asserts twice a second.
static var suit_glow := true               ## a look-dev bot switches it off to show the old suit (frames of the critic 115 sheets)


func _glow_tick(dt: float) -> void:
	if not suit_glow:
		return
	_glow_t -= dt
	var changed := mode != _glow_mode
	if not changed and _glow_t > 0.0:
		return
	_glow_t = 0.5
	var was := _glow_mode
	_glow_mode = mode
	var flows := mode == Mode.SWING or mode == Mode.ZIP or mode == Mode.CLIMB
	var flies := mode == Mode.FLY
	var armed := SnakeWar.holding()
	if changed:
		if (was == Mode.SWING or was == Mode.ZIP or was == Mode.CLIMB) and not flows and not armed:
			HeroLook.set_glow(Color.WHITE, 0.0, &"flow")
		if was == Mode.FLY and not flies:
			HeroLook.set_glow(Color.WHITE, 0.0, &"wings")
	if flies:
		HeroLook.set_glow(Color(0.55, 0.95, 1.0), 1.8, &"wings")                     # (the first version, 1.3 and 1.5, was a difference of a few grey levels on the thin circuit lines at LOW: the A/B frames of the critic sheet)
	elif flows and not armed:
		HeroLook.set_glow(Color(0.2, 0.95, 1.0), 2.1 if mode == Mode.SWING else 1.7, &"flow")


## Yaw the body faces while a snake state runs (NAN: the normal aim facing).
func facing_yaw() -> float:
	match mode:
		Mode.SWING:
			var d := swing.swing_dir
			return PlayerUtil.yaw_of(d) if Vector2(d.x, d.z).length() > 0.1 else NAN
		Mode.ZIP:
			var z := zip.dir
			return PlayerUtil.yaw_of(z) if Vector2(z.x, z.z).length() > 0.1 else NAN
		Mode.CLIMB:
			return climb.face_yaw()
		Mode.FLY:
			var f := flight.dir
			return PlayerUtil.yaw_of(f) if Vector2(f.x, f.z).length() > 0.1 else NAN
	return NAN


func _aim() -> Vector3:
	return PlayerUtil.forward_of(p.camera_rig.yaw, p.camera_rig.pitch)


func _heading() -> Vector3:
	var yaw := p.camera_rig.yaw
	var h := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var vh := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if not SnakeSwing.old_motion:
		# wave 117: the next rope goes where the player LOOKS, bent by the stick (left / right / forward; a stick pulled back is a brake, not a direction), and only a
		# little by the way he already moves, and never against the look: the old 70 / 30 mix with the velocity let a chain drift round and turn back on itself
		var w := Vector3(_wish.x, 0.0, _wish.z)
		if w.dot(h) < 0.0:
			w -= h * w.dot(h)
		if w.length() > 0.3:
			h = (h * 0.45 + w.normalized() * 0.55).normalized()
		if vh.length() > 8.0 and vh.normalized().dot(h) > 0.0:
			h = (h * 0.75 + vh.normalized() * 0.25).normalized()
		return h
	if vh.length() > 8.0:
		h = (h * 0.7 + vh.normalized() * 0.3).normalized()
	return h


func _end_mode(old: int) -> void:
	match old:
		Mode.SWING:
			pass
		Mode.ZIP:
			pass
		Mode.CLIMB:
			pass
		Mode.FLY:
			pass
	if mode == old:
		mode = Mode.NONE
	_hold_t = 0.0
	cam.on_mode(mode)


func _none_tick(dt: float, iv: Vector2, wish: Vector3, on_floor: bool, air: bool, down: bool, pressed: bool, fly_pressed: bool, jump_down: bool, jump_pressed: bool, crouch: bool) -> void:
	_stick = iv.length()
	# landing roll and chain bookkeeping
	if on_floor:
		_floor_speed = Vector2(p.velocity.x, p.velocity.z).length()
	if not on_floor:
		_fall_vy = minf(_fall_vy, p.velocity.y)
		_was_air = true
	elif _was_air:
		_was_air = false
		_landed(-_fall_vy)
		_fall_vy = 0.0
		air_jumps_used = 0
		_super_used = false
		_super_t = 0.0
	if roll_t > 0.0:
		roll_t = maxf(0.0, roll_t - dt)
	# the FLY / LAND button
	if fly_pressed and not p.control_hold:
		_start_flight(on_floor)
		if mode == Mode.FLY:
			return
	# the contextual SNAKE button
	if pressed and swing_cd <= 0.0 and not p.control_hold:
		_press(on_floor, air, iv)
		if mode != Mode.NONE:
			return
	# auto chain: still holding after an auto release, scan for the next anchor
	if down and _chain_armed > 0.0 and not on_floor and swing_cd <= 0.0 and _since_release > 0.2 and time - _chain_scan >= SCAN_RATE:
		if (p.velocity.y < 2.5 or _since_release > 1.0) if SnakeSwing.old_motion else (p.velocity.y < 3.0 or _since_release > 0.7):       # wave 117: the next rope leaves at the top of the throw
			_chain_scan = time
			var hit := _scan_swing(SnakeSwing.old_motion or (_since_release > 0.8 and _near_ground(TURN_HEIGHT)))       # wave 117: straight on first; the chain only turns (never back) when the street is coming up with nothing ahead
			if not hit.is_empty():
				_start_swing(hit, false)
				swing.fresh_press = false                        # critic 117: fired by the held chain, not by a press (a thumb lifted right after it lets go, it is not a tap)
				return
	# hold SNAKE in the air with nothing to bite: SNAKE FLIGHT
	if down and _hold_t >= FLY_HOLD and not p.control_hold and (not on_floor or _hold_t >= FLY_HOLD + 0.2) and SnakePower.flight_unlocked() and not _swing_blocked_press:
		if _chain_armed <= 0.0 or _hold_t >= FLY_HOLD + 1.0:
			_start_flight(on_floor)
			if mode == Mode.FLY:
				return
	if not down:
		_swing_blocked_press = false
	if _post_swing and not on_floor and not SnakeSwing.old_motion:
		_air_brake(dt, down)
	# the movement kit
	_kit(dt, on_floor, air, jump_down, jump_pressed)
	_update_hint(on_floor, air)
	_preview(dt, on_floor, air)


## What happens when the player presses SNAKE: climb at a wall, zip at a target, swing from the air, else a miss.
func _press(on_floor: bool, air: bool, iv: Vector2) -> void:
	var reach := SnakePower.range_m()
	var aim := _aim()
	if not air:
		# 1. a wall in reach in front: stick to it
		var look_h := Vector3(-sin(p.camera_rig.yaw), 0.0, -cos(p.camera_rig.yaw))
		var wdir := _wish if _wish.length() > 0.3 else look_h
		var w := anchors.find_wall(p, wdir, 1.15)
		if w.is_empty() and wdir != look_h:
			w = anchors.find_wall(p, look_h, 1.15)
		if not w.is_empty() and absf((w["normal"] as Vector3).y) < 0.55:
			if (w["normal"] as Vector3).dot(-look_h) > 0.35 or _wish.length() > 0.3:
				if SnakePower.unlimited() or energy > 6.0:
					_start_climb(w)
					return
		# 2. a zip target under the crosshair
		if zip_cd <= 0.0:
			var z := anchors.find_zip(p, aim, reach, assist)
			if not z.is_empty() and (SnakePower.unlimited() or energy > SnakePower.cost(8.0) * 0.5):
				_start_zip(z)
				return
	# a ceiling just over the head (a jump into a bridge's underside, an overhang): stick to it
	if air:
		var ce := anchors.find_wall(p, Vector3.ZERO, 0.1, true)
		if not ce.is_empty() and ce["kind"] == &"ceiling" and (SnakePower.unlimited() or energy > 6.0):
			_start_climb(ce)
			return
	# 3. a swing (from the air, or a hop + swing from the ground)
	var hit := _scan_swing()
	if not hit.is_empty():
		_start_swing(hit, not air)
		return
	if air:
		var look_h2 := Vector3(-sin(p.camera_rig.yaw), 0.0, -cos(p.camera_rig.yaw))
		var w2 := anchors.find_wall(p, _wish if _wish.length() > 0.3 else look_h2, 1.15, false)
		if not w2.is_empty() and absf((w2["normal"] as Vector3).y) < 0.55 and (SnakePower.unlimited() or energy > 6.0):
			_start_climb(w2)                                                       # nothing to swing from but a wall within reach: hold on to it
			return
		if _post_swing and not SnakeSwing.old_motion:
			# wave 117: "press SNAKE again in the air = the next rope". Between two swings the hero is often above every anchor for a moment (the throw carried him to the
			# roofline): the press used to be a miss, and the thumb that stayed on the button for the rope started SNAKE FLIGHT 0.45 s later. Now the press WAITS: the rope
			# leaves the hand as soon as an anchor comes into reach on the way down, for as long as the button is held (CHAIN_WAIT); no flight out of it
			_chain_armed = CHAIN_WAIT
			_swing_blocked_press = true
			return
	_whiff(aim, reach)


func _scan_swing(wide := false) -> Dictionary:
	return anchors.find_swing(p, _heading(), _aim(), SnakePower.range_m(), assist, Vector3.INF, false, wide)


func _start_swing(hit: Dictionary, from_ground: bool) -> void:
	if not SnakePower.unlimited() and energy < 3.0:
		Game.say("OUT OF SNAKE ENERGY", 1.0)
		return
	swing.begin(p, hit, from_ground)
	swing.fresh_press = true
	mode = Mode.SWING
	swings += 1
	swing_cd = SnakePower.cd(0.12)
	_chain_armed = 0.0
	_hold_t = 0.0
	air_jumps_used = 0
	cam.on_mode(mode)
	pose.on_mode(mode, self)


func _start_zip(z: Dictionary) -> void:
	zip.begin(p, z)
	mode = Mode.ZIP
	zips += 1
	zip_cd = SnakePower.cd(1.0)
	_hold_t = 0.0
	if zip_takes_press:
		_swing_blocked_press = true                # wave 116 (touch probe): a thumb that stayed on ZIP a moment longer than the pull took (0.3 to 0.9 s) took off in SNAKE FLIGHT from the roof it had just reached: the press that zipped starts nothing else
	cam.on_mode(mode)
	pose.on_mode(mode, self)


## A zip at two anchors: ride the snake from a to b (missions and the world place such lines).
func start_line(a: Vector3, b: Vector3) -> void:
	cancel()
	zip.start_line(p, a, b)
	mode = Mode.ZIP
	zips += 1
	cam.on_mode(mode)
	pose.on_mode(mode, self)


func _start_climb(w: Dictionary) -> void:
	climb.begin(p, w)
	mode = Mode.CLIMB
	climbs += 1
	_hold_t = 0.0
	cam.on_mode(mode)
	pose.on_mode(mode, self)


## Called by SnakeZip when a zip ends at a wall: the climb takes over.
func climb_from_zip(pl: Player, wall: Dictionary) -> bool:
	p = pl
	zip.cancel()
	_start_climb(wall)
	return true


func _start_flight(on_floor: bool) -> void:
	if mode == Mode.FLY:
		return
	if flight.begin(p, _aim()):
		mode = Mode.FLY
		flights += 1
		_hold_t = 0.0
		cam.on_mode(mode)
		pose.on_mode(mode, self)


func _whiff(aim: Vector3, reach: float) -> void:
	if _whiff_cd > 0.0:
		return
	_whiff_cd = WHIFF_COOLDOWN
	whiffs += 1
	_swing_blocked_press = false
	var o := hand_pos(1)
	var tip := o + aim * minf(reach * 0.45, 22.0)
	_whiff_tendril = SnakeTendril.fire(hand_callable(1), tip, {"travel": 0.1, "wriggle": 0.8, "tension": 0.1, "thickness": 0.06, "life": 0.04, "host": p})
	Game.say("NO ANCHOR IN REACH", 0.9)
	Sfx.play(&"snk_miss", -6.0)
	event.emit(&"whiff")


# --- enemy counters: the sniper's lead and the jammer ---------------------------------------------------------------------------------------

## A JAMMER (the warden's phase pulse, specialist.gd) reaches the hero: every snake state ends at once (a swing lets go WITHOUT its release boost, a zip stops where it is, a climb loses its
## grip, flight drops out of the sky), the SNAKE and FLY presses are dead for `seconds` (-1: SnakePower.jam_seconds by difficulty; HERO MODE is immune) and the button reads JAMMED.
## Returns true when the jam took.
func jam(seconds: float = -1.0) -> bool:
	if p == null or not is_instance_valid(p) or InteriorSpace.active or InteriorGameplay.active:
		return false
	var secs := SnakePower.jam_seconds() if seconds < 0.0 else seconds
	if secs <= 0.0:
		return false
	match mode:
		Mode.SWING:
			swing.release(p, false, &"jam")
		Mode.ZIP:
			zip.cancel()
			air_momentum = 0.3
		Mode.CLIMB:
			climb.drop(p)
		Mode.FLY:
			flight.end(p, false)
	if mode != Mode.NONE:                                      # a state that did not hand the body back through its own end hook
		swing.cancel()
		zip.cancel()
		climb.cancel()
		flight.cancel()
		mode = Mode.NONE
		cam.on_mode(mode)
	jam_t = maxf(jam_t, secs)
	jams += 1
	_chain_armed = 0.0
	_swing_blocked_press = true
	_hold_t = 0.0
	FX.burst(p.global_position + Vector3(0.0, 1.0, 0.0), Color(0.82, 0.8, 1.0), 14, 5.5, 0.5, 2.0, 1.0)
	FX.shake(0.25)
	p.camera_rig.bump(0.3)
	Game.say("SNAKE JAMMED", 1.3)
	Sfx.play(&"snk_miss", -2.0, 0.7)
	event.emit(&"jam")
	return true


## The warden's pulse calls this with its own position: a hero within `radius` metres (sideways) is jammed, from 6 m below the pulse up to `height` above it (the pulse is a column: a hero
## swinging over the warden's head is in it, the warden's AI pulses at a hero 24 m away sideways whatever his height). Returns true when he was.
static func jam_in_radius(at: Vector3, radius: float, seconds: float = -1.0, height: float = 45.0) -> bool:
	var s := instance
	if s == null or s.p == null or not is_instance_valid(s.p):
		return false
	var d := s.p.global_position - at
	if Vector2(d.x, d.z).length() > radius or d.y > height or d.y < -6.0:
		return false
	return s.jam(seconds)


## Where a sniper should aim to hit a hero who moves under the snakes (swinging, zipping, climbing, flying, or flying out of a release): his velocity times `t` seconds (the time between the
## lock and the shot), scaled by how good the sniper is on this difficulty (SnakePower.sniper_lead). Zero for a hero on foot (the old behaviour) and for slow movement.
static func lead_offset(t: float) -> Vector3:
	var s := instance
	if s == null or s.p == null or not is_instance_valid(s.p) or (s.mode == Mode.NONE and s.air_momentum <= 0.0):
		return Vector3.ZERO
	var v := s.p.velocity
	if v.length() < 6.0:
		return Vector3.ZERO
	return v * (t * SnakePower.sniper_lead())


# --- callbacks of the states (sounds, effects, events) ---------------------------------------------------------------------------------

func say_swing_started() -> void:
	Sfx.play(&"snk_fire", -3.0)
	event.emit(&"swing_start")


func on_swing_attached(at: Vector3) -> void:
	chain = swing.chain
	best_chain = maxi(best_chain, chain)
	FX.burst(at, Color(0.5, 1.0, 1.0), 9, 5.0, 0.45, 2.0, 0.9)
	FX.shake(0.1)
	Sfx.play_at(&"snk_attach", at, -2.0)
	Sfx.play(&"snk_strain", -9.0)
	p.camera_rig.punch_fov(5.0)
	event.emit(&"swing_attach")


func on_swing_released(was_hang: bool, spd: float) -> void:
	mode = Mode.NONE
	_since_release = 0.0
	_hold_t = 0.0
	air_momentum = 1.4 if SnakeSwing.old_motion else 1.0
	_swing_blocked_press = true
	_post_swing = was_hang
	if was_hang:
		Sfx.play(&"snk_release", -4.0)
		p.camera_rig.punch_fov(7.0 + clampf(spd * 0.15, 0.0, 6.0))
		var held := Input.is_action_pressed(&"snake")
		if held and assist and (SnakeSwing.old_motion or swing.last_why in SwingMotion.AUTO_WHYS):       # wave 117: only a swing that let go by itself at the front of its arc chains on; after JUMP, a wall, the street or a still rope the next rope is the player's own press
			_chain_armed = 1.7 if SnakeSwing.old_motion else CHAIN_WAIT
			_swing_blocked_press = not SnakeSwing.old_motion      # wave 117: a hold that began as a swing never turns into SNAKE FLIGHT when the chain finds no anchor (he lands with a roll); flight is a fresh hold or the FLY button
			_chain_t = -10.0
	cam.on_mode(mode)
	event.emit(&"swing_release")


## The swing asks before an auto release: is there a good next anchor ahead? (cached for SCAN_RATE seconds)
func chain_anchor_ready(pl: Player) -> bool:
	if time - _chain_t >= SCAN_RATE:
		_chain_t = time
		var vh := Vector3(pl.velocity.x, 0.0, pl.velocity.z)
		var h := vh.normalized() if vh.length() > 4.0 else _heading()
		_chain_hit = anchors.find_swing(pl, h, _aim(), SnakePower.range_m(), true)
	return not _chain_hit.is_empty() and float(_chain_hit.get("dist", 0.0)) >= 14.0


func on_zip_started(from: Vector3, dest: Vector3) -> void:
	Sfx.play(&"snk_fire", -2.0)
	Sfx.play(&"snk_zip", -3.0)
	event.emit(&"zip")


func on_zip_landed(at: Vector3) -> void:
	Sfx.play_at(&"snk_land", at, -4.0)
	event.emit(&"zip_land")


func on_zip_ended() -> void:
	if mode == Mode.ZIP:
		mode = Mode.NONE
	air_momentum = 0.5
	cam.on_mode(mode)


func on_climb_started(ceiling: bool) -> void:
	Sfx.play_at(&"snk_attach", p.global_position + Vector3(0.0, 1.2, 0.0), -3.0)
	event.emit(&"climb")


func on_climb_ceiling() -> void:
	event.emit(&"ceiling")


func on_climb_mantle() -> void:
	Sfx.play(&"snk_land", -6.0)
	event.emit(&"mantle")


func on_climb_ended(_ceiling: bool) -> void:
	if mode == Mode.CLIMB:
		mode = Mode.NONE
	_hold_t = 0.0
	cam.on_mode(mode)
	event.emit(&"climb_end")


func on_climb_leap(v: Vector3, _ceiling: bool) -> void:
	p.verbs._spent = true                                      # a leap off a wall is not caught by a wall-run at once (one run per kick-off)
	if mode == Mode.CLIMB:
		mode = Mode.NONE
	air_momentum = 1.2
	_hold_t = 0.0
	Sfx.play(&"snk_release", -3.0)
	p.camera_rig.punch_fov(6.0)
	cam.on_mode(mode)
	event.emit(&"leap")


func on_flight_started(from_ground: bool) -> void:
	var hud := p.get_tree().get_first_node_in_group(&"hud") if p != null and p.is_inside_tree() else null       # wave 116 (owner frames): the MORE tray (C4, CROUCH, THROW, MELEE, CALL CAR, ALT) sits over the middle of the screen, on the flying hero: a take-off closes it (MORE opens it again)
	if hud != null and hud.get(&"touch") != null and not FlightView.old_look:
		(hud.get(&"touch") as TouchControls).more_open = false
	Sfx.play(&"snk_wings", -2.0)
	Sfx.play(&"snk_boost", -6.0)
	p.camera_rig.punch_fov(8.0)
	event.emit(&"flight")


func on_flight_boost() -> void:
	Sfx.play(&"snk_boost", -2.0)
	p.camera_rig.punch_fov(9.0)
	event.emit(&"boost")


func on_flight_roll() -> void:
	Sfx.play(&"snk_roll", -3.0)
	event.emit(&"roll")


func on_flight_crash(into: float) -> void:
	Sfx.play(&"snk_land", -1.0)
	event.emit(&"crash")


func on_flight_ended(to_ground: bool) -> void:
	if mode == Mode.FLY:
		mode = Mode.NONE
	_hold_t = 0.0
	_swing_blocked_press = true
	air_momentum = 0.8
	if to_ground:
		Sfx.play_at(&"snk_land", p.global_position, -3.0)
	cam.on_mode(mode)
	event.emit(&"land" if to_ground else &"flight_end")


# --- air physics shared by the swing's travel phase ----------------------------------------------------------------------------------

func free_air(pl: Player, dt: float, wish: Vector3) -> void:
	var v := pl.velocity
	v.y = maxf(v.y - Player.GRAVITY * 0.9 * dt, -Player.MAX_FALL_SPEED)
	if wish.length() > 0.05:
		v += Vector3(wish.x, 0.0, wish.z) * 6.0 * dt
	pl.velocity = v
	pl.move_and_slide()


## The horizontal damping of the player's air steering, scaled while the speed of a release should survive (Player._foot_tick multiplies its air accel by this).
func air_k_scale() -> float:
	if _post_swing and not SnakeSwing.old_motion and p != null and not p.is_on_floor():
		return 0.05 if _stick < 0.2 else 0.3      # wave 117: a throw is a throw. With the thumbs off, the player's air damping stopped the hero dead over the street one second after a release (28 m/s to 0, then straight down); the stick still steers and brakes
	if air_momentum <= 0.0:
		return 1.0
	return lerpf(1.0, 0.04, clampf(air_momentum / 1.0, 0.0, 1.0))


# --- movement kit: double jump, super jump, landing roll ------------------------------------------------------------------------------

func _kit(dt: float, on_floor: bool, air: bool, jump_down: bool, jump_pressed: bool) -> void:
	if jump_down:
		_jump_hold_t += dt
	else:
		_jump_hold_t = 0.0
	if on_floor:
		return
	# DOUBLE JUMP: a second press while still rising
	if jump_pressed and air and p.air_time > 0.12 and p.velocity.y > 1.5 and air_jumps_used < SnakePower.air_jumps() and not flight.active and not p.verbs.wall_running:
		air_jumps_used += 1
		double_jumps += 1
		p.velocity.y = DOUBLE_JUMP_SPEED * HeroPower.f("jump") ** 0.5 + maxf(p.velocity.y * 0.25, 0.0)
		jump_consumed = true
		FX.burst(p.global_position + Vector3(0.0, 0.2, 0.0), Color(0.5, 1.0, 1.0), 10, 5.0, 0.4, 0.0, 1.0)
		Sfx.play(&"snk_roll", -8.0, 1.4)
		event.emit(&"double_jump")
		return
	# SUPER JUMP: hold JUMP while rising, the snake pushes the ground away
	if jump_down and _jump_hold_t >= SUPER_HOLD and (_super_t > 0.0 or (_floor_speed < SUPER_MAX_RUN and _stick < SUPER_MAX_STICK)) and p.velocity.y > 1.0 and _super_t < SUPER_TIME and not _super_used and not p.verbs.wall_running and air_jumps_used == 0 and p.air_time < 0.9:
		if _super_t == 0.0:
			if not SnakePower.unlimited() and energy < 6.0:
				_super_used = true
			else:
				energy_spend(SnakePower.cost(6.0))
				super_jumps += 1
				Sfx.play(&"snk_boost", -6.0, 1.3)
				FX.burst(p.global_position + Vector3(0.0, 0.1, 0.0), Color(0.5, 1.0, 1.0), 12, 6.0, 0.4, 3.0, 1.0)
				event.emit(&"super_jump")
		if not _super_used:
			_super_t += dt
			p.velocity.y += SUPER_THRUST * HeroPower.f("jump") ** 0.5 * dt
	elif not jump_down and _super_t > 0.0:
		_super_used = true


## Wave 117, after a swing is let go: the snakes spread and brake the hero as the street comes up, so he does not meet it at swing speed (measured before: 34 m/s 3 m over the
## street two seconds after a release). Only while he is falling, lower than AIR_BRAKE_H, and faster over the ground than AIR_BRAKE_TO; the fall itself is cushioned to SOFT_FALL.
const CHAIN_WAIT := 3.0                    ## seconds a held SNAKE keeps looking for the next anchor after a swing
const TURN_HEIGHT := 9.0                   ## a chain with nothing ahead turns to an anchor beside it only this near the ground
const AIR_BRAKE_H := 10.0
const AIR_BRAKE_TO := 11.0
const AIR_BRAKE_ACC := 18.0
const SOFT_FALL := 15.0
const ROLL_SPEED := 7.5                    ## a landing out of a swing faster than this over the ground (or SOFT_ROLL_FALL down) rolls
const SOFT_ROLL_FALL := 8.0


func _air_brake(dt: float, _down: bool) -> void:
	if _since_release < 0.5 or p.velocity.y > -2.0:
		return
	_rq.collision_mask = Game.L_WORLD
	_rq.exclude = [p.get_rid()]
	_rq.from = p.global_position + Vector3(0.0, 0.5, 0.0)
	_rq.to = p.global_position + Vector3(0.0, -AIR_BRAKE_H, 0.0)
	var hit := p.get_world_3d().direct_space_state.intersect_ray(_rq)
	if hit.is_empty():
		return
	var hs := Vector2(p.velocity.x, p.velocity.z).length()
	if hs > AIR_BRAKE_TO:
		var k := maxf(AIR_BRAKE_TO, hs - AIR_BRAKE_ACC * dt) / hs
		p.velocity.x *= k
		p.velocity.z *= k
	if p.velocity.y < -SOFT_FALL:
		p.velocity.y = minf(-SOFT_FALL, p.velocity.y + 60.0 * dt)
	air_brakes += 1


func _near_ground(h: float) -> bool:
	_rq.collision_mask = Game.L_WORLD
	_rq.exclude = [p.get_rid()]
	_rq.from = p.global_position + Vector3(0.0, 0.5, 0.0)
	_rq.to = p.global_position + Vector3(0.0, -h, 0.0)
	return not p.get_world_3d().direct_space_state.intersect_ray(_rq).is_empty()


func _landed(fall_speed: float) -> void:
	var soft := _post_swing and not SnakeSwing.old_motion and (Vector2(p.velocity.x, p.velocity.z).length() > ROLL_SPEED or fall_speed >= SOFT_ROLL_FALL)
	_post_swing = false
	if (fall_speed >= ROLL_FALL or soft) and mode == Mode.NONE and not p.verbs.slamming:
		roll_t = ROLL_TIME
		landing_rolls += 1
		var hv := Vector3(p.velocity.x, 0.0, p.velocity.z)
		roll_speed = hv.length()
		if hv.length() < 4.0:
			var fh := Vector3(-sin(p.camera_rig.yaw), 0.0, -cos(p.camera_rig.yaw))
			p.velocity += fh * 4.0
		p.invuln = maxf(p.invuln, 0.35)
		p.camera_rig.bump(0.25)
		FX.burst(p.global_position + Vector3(0.0, 0.1, 0.0), Color(0.55, 1.0, 1.0), 8, 4.0, 0.4, 2.0, 0.9)
		Sfx.play_at(&"snk_land", p.global_position, -6.0)
		event.emit(&"roll_land")
	elif fall_speed > 6.0:
		event.emit(&"land")


# --- hints and the anchor preview ----------------------------------------------------------------------------------------------------

func _update_hint(on_floor: bool, air: bool) -> void:
	if mode == Mode.FLY:
		hint = &"boost"
		return
	if air:
		hint = &"swing" if not preview.is_empty() else &"none"
	elif wall_ready:
		hint = &"climb"
	elif zip_ready:
		hint = &"zip"
	elif not preview.is_empty():
		hint = &"swing"
	else:
		hint = &"none"


func _preview(dt: float, on_floor: bool, air: bool) -> void:
	_scan_t -= dt
	if _scan_t > 0.0:
		return
	_scan_t = 0.25 if Game.quality > 0 else 0.4
	# the quick scan: the fan without the arc simulation (a handful of rays, four times a second): the marker, the button label
	preview = anchors.find_swing(p, _heading(), _aim(), SnakePower.range_m(), assist, Vector3.INF, true)
	preview_kind = preview.get("kind", &"")
	wall_ready = false
	zip_ready = false
	if on_floor and not air:
		var look_h := Vector3(-sin(p.camera_rig.yaw), 0.0, -cos(p.camera_rig.yaw))
		var w := anchors.find_wall(p, look_h, 1.0)
		wall_ready = not w.is_empty() and absf((w["normal"] as Vector3).y) < 0.55
		if not wall_ready and zip_cd <= 0.0:
			var z := anchors.find_zip(p, _aim(), SnakePower.range_m(), assist)
			zip_ready = not z.is_empty()
	zip_target = anchors.last if zip_ready else {}                   # w117-rope hook


## The text of the touch SNAKE button: what a press would do now (cached by the scans in _preview, never casts a ray itself).
func button_label() -> String:
	if jam_t > 0.0:
		return "JAMMED"
	var cue := SnakeFx.label_cue()                                  # w117-rope hook: "NO ANCHOR" for a second after a press that found nothing
	if cue != "":
		return cue
	match mode:
		Mode.SWING: return "LET GO"                                    # critic 115 look: one word for both (swing and climb): "RELEASE" had to be drawn a fifth smaller to fit the disc
		Mode.CLIMB: return "LET GO"
		Mode.FLY: return "BOOST"
		Mode.ZIP: return "ZIP"
	match hint:
		&"climb": return "CLIMB"
		&"zip": return "ZIP"
		&"swing": return "SWING"
	return "SNAKE"


## In the air after a swing let go and before he lands or takes the next rope (the pose leans him along the throw).
func thrown() -> bool:
	return _post_swing and mode == Mode.NONE and p != null and not p.is_on_floor() and roll_t <= 0.0


## The SNAKE button is on screen while the hero is on foot outside the interiors.
func button_shown() -> bool:
	return p != null and not p.control_hold and not InteriorSpace.active and not InteriorGameplay.active and not p.is_dead()


## The FLY / LAND button: while flying, or in the air (swinging, falling, jumping) when flight is open to the hero and the energy lasts.
func fly_button_shown() -> bool:
	if not button_shown() or not SnakePower.flight_unlocked() or jam_t > 0.0:
		return false
	if mode == Mode.FLY:
		return true
	return (mode == Mode.NONE or mode == Mode.SWING) and p.air_time > fly_show_air and (energy >= 8.0 or SnakePower.unlimited())
