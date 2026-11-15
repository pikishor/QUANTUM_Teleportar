class_name SnakeTendril
extends RefCounted
## THE ONE QUANTUM SNAKE VISUAL (wave 115). The traversal builder (swing, zip, climb, flight; scripts/quantum/snake_*.gd) and the combat builder (pull, grab, nets, shield, bombs)
## both draw their snakes through this file, so the owner sees one creature: a glowing, segmented, scaled body with a viper head and lit eyes that slithers out of the hero's
## hand, reaches its target in a fraction of a second, goes taut (or hangs slack), and slides back into the hand. One tendril is a tiny state machine (this class, no node);
## the pool node (snake_tendril_pool.gd) ticks every live tendril and draws ALL of them with ONE MultiMesh draw call (shader assets/shaders/snake_tendril.gdshader,
## control points in a data texture). Nothing is drawn while no tendril lives.
##
## USAGE
##   var t := SnakeTendril.fire(origin, target, {...options})          # origin / target: Vector3, a Node3D (follows it) or a Callable returning a Vector3
##   t.tension = 0.8                  # 0 slack (the body sags), 1 taut (a straight line): the swing sets it from the rope
##   t.bow / t.flutter                # a world offset of the middle of the body (an arched wing) and an amplitude of lasting slither in metres (set them every frame, 0 = off)
##   t.retract()                      # head slides back to the hand and the tendril ends (retracted signal); t.kill() ends it at once
##   t.attached / t.state / t.progress / t.head_pos / t.length() / t.age        # read-only state
## OPTIONS (all optional)
##   speed          head speed in m/s (default 95); travel (seconds) overrides it when given
##   wriggle        lateral slither amplitude in metres while it travels (default 0.45; 0 = a ruler-straight snake)
##   color          core colour (default quantum cyan); rim and accent are derived in the shader
##   thickness      body radius in metres (default 0.075); the head is 2.1 x wider
##   head           false = plain rope without a head (default true)
##   life           > 0: retract by itself this many seconds after it attached
##   origin_offset  Vector3 added to a Node3D origin (local space of that node); target_offset likewise
##   tension        starting tension (default 0.55); the owner changes it every frame
##   on_attach      Callable called once when the head arrives
##   host           Node used to find / create the pool when there is no Game.player
## POOL CAPS BY TIER (Game.quality): LOW 4 tendrils x 18 control points, MED 6 x 26, HIGH 8 x 32. When the pool is full the oldest tendril that already attached is retired
## (its owner just sees `retracted`), so the hero's own tendril is never starved by decoration.
## Signals: attached (the head arrived), retracted (the tendril is gone from the pool: killed, fully retracted or its owner node was freed).
## The state machine and its timing run without a renderer, so tests can wait on `attached` and `retracted`.

signal attached
signal retracted

enum State { TRAVEL, ATTACHED, RETRACT, DONE }

const DEFAULT_COLOR := Color(0.16, 0.88, 1.0)
const RETRACT_TIME := 0.16
const MIN_TRAVEL := 0.05
const MAX_TRAVEL := 0.6

var state := State.TRAVEL
var color := DEFAULT_COLOR
var thickness := 0.075
var wriggle := 0.45
var tension := 0.55
var head_scale := 1.0
var speed := 95.0
var travel_time := 0.0                         ## seconds the head needs, computed when it leaves
var life := 0.0
var age := 0.0                                 ## seconds since it was fired
var attached_age := 0.0                        ## seconds since the head arrived
var progress := 0.0                            ## 0..1 of the way the head has gone (1 once attached; falls back to 0 while retracting)
var origin_pos := Vector3.ZERO                 ## tail (hand) now
var target_pos := Vector3.ZERO                 ## where the head goes / is
var head_pos := Vector3.ZERO
var slack_sag := 1.0                           ## how much a slack body hangs (1 = natural)
var bow := Vector3.ZERO                        ## world offset (metres) the middle of the body is pushed by: an arched wing, a curled tail (the owner sets it every frame; 0 = straight)
var flutter := 0.0                             ## extra slither amplitude (metres) that stays on an attached tendril: wings and idle snakes breathe with it
var user := {}                                 ## free data for the owner (a test or a verb can tag its tendril)

var _origin: Variant
var _origin_off := Vector3.ZERO
var _target: Variant
var _target_off := Vector3.ZERO
var _on_attach: Callable
var _retract_dur := RETRACT_TIME
var _retract_left := 0.0
var _retract_from := 0.0
var _seed := 0.0
var _row := -1                                 ## pool row while drawn
var _pool: Node                                ## SnakeTendrilPool
var _speed_given := false


## Fire a tendril. Returns it at once (the head leaves the hand this frame). See the header for the options.
static func fire(origin: Variant, target: Variant, opts: Dictionary = {}) -> SnakeTendril:
	var t := SnakeTendril.new()
	t._setup(origin, target, opts)
	var host: Node = opts.get("host") as Node
	var pool := SnakeTendrilPool.get_pool(host)
	if pool != null:
		pool.add(t)
	else:
		t._pool = null
	return t


func _setup(origin: Variant, target: Variant, opts: Dictionary) -> void:
	_origin = origin
	_target = target
	_origin_off = opts.get("origin_offset", Vector3.ZERO)
	_target_off = opts.get("target_offset", Vector3.ZERO)
	color = opts.get("color", DEFAULT_COLOR)
	thickness = float(opts.get("thickness", 0.075))
	wriggle = float(opts.get("wriggle", 0.45))
	tension = float(opts.get("tension", 0.55))
	head_scale = 1.0 if bool(opts.get("head", true)) else 0.0
	life = float(opts.get("life", 0.0))
	_on_attach = opts.get("on_attach", Callable())
	_seed = randf() * 100.0
	_refresh_ends()
	head_pos = origin_pos
	var dist := origin_pos.distance_to(target_pos)
	if opts.has("travel"):
		travel_time = clampf(float(opts["travel"]), MIN_TRAVEL, 3.0)
		speed = dist / maxf(travel_time, 0.001)
	else:
		speed = float(opts.get("speed", 95.0))
		travel_time = clampf(dist / maxf(speed, 1.0), MIN_TRAVEL, MAX_TRAVEL)
	_speed_given = opts.has("speed")


func is_alive() -> bool:
	return state != State.DONE


func is_attached() -> bool:
	return state == State.ATTACHED


## Length of the visible body in metres (hand to head).
func length() -> float:
	return origin_pos.distance_to(head_pos)


## Slide back into the hand and end. Calling it twice, or on a tendril that already ended, does nothing.
func retract(time := RETRACT_TIME) -> void:
	if state == State.RETRACT or state == State.DONE:
		return
	state = State.RETRACT
	_retract_dur = maxf(time, 0.04)
	_retract_left = _retract_dur
	_retract_from = maxf(progress, 0.02)


## End it now (no animation): the pool row is freed.
func kill() -> void:
	if state == State.DONE:
		return
	state = State.DONE
	progress = 0.0
	retracted.emit()


## Move the goal of a travelling or attached tendril (a swing anchor on a moving car, an enemy that is pulled).
func set_target(target: Variant, offset := Vector3.ZERO) -> void:
	_target = target
	_target_off = offset
	_refresh_ends()


func _pos_of(src: Variant, off: Vector3, fallback: Vector3) -> Vector3:
	if src is Vector3:
		return src
	if src is Node3D:
		var n := src as Node3D
		if is_instance_valid(n) and n.is_inside_tree():
			return n.global_transform * off
		return fallback
	if src is Callable:
		var c := src as Callable
		if c.is_valid():
			var r: Variant = c.call()
			if r is Vector3:
				return r
		return fallback
	return fallback


func _refresh_ends() -> void:
	origin_pos = _pos_of(_origin, _origin_off, origin_pos)
	target_pos = _pos_of(_target, _target_off, target_pos)


## True when the node this tendril hangs on was freed (the owner is gone, so the tendril ends).
func _owner_gone() -> bool:
	if _origin is Node3D and not is_instance_valid(_origin):
		return true
	if _origin is Object and not (_origin is Node3D) and not is_instance_valid(_origin):
		return true
	return false


## One simulation step (the pool calls it every frame in the play state).
func step(dt: float) -> void:
	if state == State.DONE:
		return
	if _owner_gone():
		kill()
		return
	age += dt
	_refresh_ends()
	match state:
		State.TRAVEL:
			progress = minf(1.0, progress + dt / travel_time)
			var e := progress * progress * (3.0 - 2.0 * progress)
			head_pos = origin_pos.lerp(target_pos, maxf(e, 0.001))
			if progress >= 1.0:
				state = State.ATTACHED
				attached_age = 0.0
				head_pos = target_pos
				attached.emit()
				if _on_attach.is_valid():
					_on_attach.call()
		State.ATTACHED:
			attached_age += dt
			head_pos = target_pos
			if life > 0.0 and attached_age >= life:
				retract()
		State.RETRACT:
			_retract_left -= dt
			progress = _retract_from * clampf(_retract_left / _retract_dur, 0.0, 1.0)
			var e2 := progress * progress * (3.0 - 2.0 * progress)
			head_pos = origin_pos.lerp(target_pos, e2)
			if _retract_left <= 0.0:
				state = State.DONE
				progress = 0.0
				retracted.emit()
