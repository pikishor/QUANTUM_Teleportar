class_name BridgeTraffic
extends Node3D
## One scenery car on a bridge (wave 105: "traffic crossing the bridges"). No physics: it follows the deck of its bridge from end to end in its own lane (and starts again at the other end) (right-hand
## traffic), pitching with the ramps, and is only built and shown while the hero is within BridgeWorld.TRAFFIC_RANGE of the bridge (BridgeWorld calls set_active every half second). The model
## is the real car model of the street traffic (VehicleVisual), so a car seen up close on the harbour gate looks like the cars of the city. Hit it with a bullet and nothing happens: it is scenery.
## Round 6 (cars inside cars): every direction of a bridge runs at ONE speed with its cars half a bridge apart (they never catch up with each other), the hull is in the TrafficField, and the car
## brakes for anything that stands or drives in its lane (the hero's car, a real traffic car) with the shared safe-distance rule.
## State for tests: `u` (metres along the bridge), `dir` (+1 / -1), `speed`, `deck_error()` (how far the car is from the deck height: always about 0).

const KINDS: Array[StringName] = [&"sedan", &"taxi", &"suv", &"van", &"sport", &"compact", &"truck", &"wagon"]
const LANE := 3.0
const SPEED_UP := 11.0                           ## m/s of every car that crosses in the +u direction
const SPEED_DOWN := 12.6                         ## m/s of every car in the other direction
const BACK_OFF := 0.3                            ## m per physics tick a car rolls back while it overlaps another hull

var bridge: Dictionary = {}
var u := 0.0
var dir := 1
var speed := 11.0                                ## the cruise speed of this car's direction
var anchor := Vector3.ZERO                       ## the middle of the bridge (the range test)
var kind: StringName = &"sedan"
var active := false
var moved := 0.0                                 ## metres driven since built (tests)
var v := 0.0                                     ## the speed it drives right now (it waits for what is in its lane)
var waiting := false                             ## true: the car has no room to come onto the deck (the start is occupied): hidden, no hull, tries again every frame
var _overlap_t := 0.0                            ## seconds this car has been inside another hull (a deadlock breaker: two cars rolling back into each other)
var _visual: VehicleVisual
var _model: Node3D
var _len := 100.0
var _slot := -1
var _fwd := Vector2(0.0, -1.0)
var _hl := 2.4
var _hw := 0.95


func setup(b: Dictionary, k: int) -> void:
	bridge = b
	_len = float(b["len"])
	dir = 1 if k % 2 == 0 else -1
	var rank := k / 2                            # the 0th and 1st car of its direction: half a bridge apart
	u = fposmod(0.12 + 0.5 * float(rank) + (0.0 if dir > 0 else 0.27), 1.0) * _len
	speed = SPEED_UP if dir > 0 else SPEED_DOWN
	v = speed
	kind = KINDS[(k * 3 + int(_len)) % KINDS.size()]
	var spec: Dictionary = VehicleSpecs.SPECS[kind]
	_hl = float(spec["len"]) * 0.5
	_hw = float(spec["wid"]) * 0.5
	var pts: PackedVector3Array = b["pts"]
	anchor = pts[pts.size() / 2]
	name = "Traffic_%s_%d" % [b["id"], k]
	visible = false
	set_physics_process(false)


func _exit_tree() -> void:
	if _slot >= 0:
		TrafficField.release(TrafficField.BRIDGE, _slot)
		_slot = -1


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	visible = on
	set_physics_process(on)
	if on and _model == null:
		_build()
	if on:
		if _slot < 0:
			_slot = TrafficField.alloc(TrafficField.BRIDGE)
		waiting = true
		_try_enter()
	elif _slot >= 0:
		TrafficField.release(TrafficField.BRIDGE, _slot)
		_slot = -1


func _build() -> void:
	_visual = VehicleVisual.new()
	_model = _visual.build(kind, VehicleSpecs.GLOWS[0])
	add_child(_model)
	_visual.set_lights(0.4, 0.4, 0.0)


func _physics_process(delta: float) -> void:
	if waiting:
		_try_enter()
		return
	var want := speed
	var l := TrafficField.lead(global_position.x, global_position.z, _fwd.x, _fwd.y, _hl, _hw, TrafficBrain.look_for(v), TrafficField.BRIDGE, _slot)
	if l.x < INF:
		want = minf(want, TrafficBrain.safe_speed(l.x, l.y))
	v = TrafficBrain.approach(v, want, delta, 2.6)
	u += float(dir) * v * delta
	moved += v * delta
	if _slot >= 0 and TrafficField.first_overlap(global_position.x, global_position.z, _fwd.x, _fwd.y, _hl, _hw, -0.1, TrafficField.BRIDGE, _slot) >= 0:
		u = clampf(u - float(dir) * BACK_OFF, 2.0, _len - 2.0)       # a car that stopped dead in its lane (a crash, a wall) was reached faster than it could brake: this scenery car has no body, it rolls back out of it
		v = 0.0
		_overlap_t += delta
		if _overlap_t > 0.8:                                          # it cannot roll back out of it (the start of the deck, or the car behind rolls back into it as well: two cars stuck in each other for a minute in the highway audit):
			_overlap_t = 0.0                                          # off the deck, back to the start, and it comes in again when the place is free
			u = 2.0 if dir > 0 else _len - 2.0
			waiting = true
			_try_enter()
			return
	else:
		_overlap_t = 0.0
	if u > _len - 2.0 or u < 2.0:                 # past the end it comes in again at the other end (right-hand traffic: every car keeps its lane and direction), once that end is free
		u = 2.0 if dir > 0 else _len - 2.0
		waiting = true
		_try_enter()
		return
	_place()


## The car's pose at deck distance `u`: [position, unit forward on the ground plane].
func _pose(at_u: float) -> Array:
	var pa := Bridges.point_at(bridge, at_u)
	var p: Vector3 = pa[0]
	var d: Vector3 = pa[1]
	var right := d.cross(Vector3.UP).normalized()
	var lane := right * LANE * float(dir)
	var ahead := Bridges.point_at(bridge, clampf(at_u + float(dir) * 3.0, 0.0, _len))
	var look := (ahead[0] as Vector3) - p
	if look.length() < 0.01:
		look = d * float(dir)
	var lf := Vector2(look.x, look.z)
	return [p + lane + Vector3(0.0, 0.08, 0.0), look.normalized(), lf.normalized() if lf.length_squared() > 1e-6 else _fwd]


## Comes onto the deck at `u` when no hull stands there (a car that wrapped round, or one switched on beside the hero's car): hidden and without a hull until the place is free, and it
## enters at a speed from which it can still stop for what is ahead.
func _try_enter() -> void:
	var pose := _pose(u)
	var pos: Vector3 = pose[0]
	var f: Vector2 = pose[2]
	if not TrafficField.clear(pos.x, pos.z, f.x, f.y, _hl, _hw, 2.0, TrafficField.BRIDGE, _slot):
		visible = false
		if _slot >= 0:
			TrafficField.remove(TrafficField.BRIDGE, _slot)
		return
	var l := TrafficField.lead(pos.x, pos.z, f.x, f.y, _hl, _hw, TrafficBrain.look_for(speed), TrafficField.BRIDGE, _slot)
	v = speed if l.x == INF else minf(speed, TrafficBrain.safe_speed(l.x, l.y))
	waiting = false
	visible = true
	_place()


func _place() -> void:
	var pose := _pose(u)
	var pos: Vector3 = pose[0]
	global_transform = Transform3D(Basis.looking_at(pose[1], Vector3.UP), pos)
	_fwd = pose[2]
	if _slot >= 0:
		TrafficField.put(TrafficField.BRIDGE, _slot, pos.x, pos.z, _fwd.x, _fwd.y, _hl, _hw, v, TrafficField.F_AI)


## Test helper: the distance between the car and the deck height at its position.
func deck_error() -> float:
	var y := Bridges.deck_y(global_position.x, global_position.z, global_position.y)
	return absf(global_position.y - y) if y != Bridges.NONE else INF
