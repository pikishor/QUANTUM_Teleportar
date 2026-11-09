class_name BridgeTraffic
extends Node3D
## One scenery car on a bridge (wave 105: "traffic crossing the bridges"). No physics and no AI: it follows the deck of its bridge from end to end at a steady speed in its own lane (and starts again at the other end) (right-hand
## traffic), pitching with the ramps, and is only built and shown while the hero is within BridgeWorld.TRAFFIC_RANGE of the bridge (BridgeWorld calls set_active every half second). The model
## is the real car model of the street traffic (VehicleVisual), so a car seen up close on the harbour gate looks like the cars of the city. Hit it with a bullet and nothing happens: it is scenery.
## State for tests: `u` (metres along the bridge), `dir` (+1 / -1), `speed`, `deck_error()` (how far the car is from the deck height: always about 0).

const KINDS: Array[StringName] = [&"sedan", &"taxi", &"suv", &"van", &"sport", &"compact", &"truck", &"wagon"]
const LANE := 3.0

var bridge: Dictionary = {}
var u := 0.0
var dir := 1
var speed := 11.0
var anchor := Vector3.ZERO                       ## the middle of the bridge (the range test)
var kind: StringName = &"sedan"
var active := false
var moved := 0.0                                 ## metres driven since built (tests)
var _visual: VehicleVisual
var _model: Node3D
var _len := 100.0


func setup(b: Dictionary, k: int) -> void:
	bridge = b
	_len = float(b["len"])
	dir = 1 if k % 2 == 0 else -1
	u = fmod(float(k) * 0.37 + 0.11, 1.0) * _len
	speed = 9.0 + float((k * 7) % 5) * 1.6
	kind = KINDS[(k * 3 + int(_len)) % KINDS.size()]
	var pts: PackedVector3Array = b["pts"]
	anchor = pts[pts.size() / 2]
	name = "Traffic_%s_%d" % [b["id"], k]
	visible = false
	set_physics_process(false)


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	visible = on
	set_physics_process(on)
	if on and _model == null:
		_build()
	if on:
		_place()


func _build() -> void:
	_visual = VehicleVisual.new()
	_model = _visual.build(kind, VehicleSpecs.GLOWS[0])
	add_child(_model)
	_visual.set_lights(0.4, 0.4, 0.0)


func _physics_process(delta: float) -> void:
	u += float(dir) * speed * delta
	moved += speed * delta
	if u > _len - 2.0 or u < 2.0:                 # past the end it comes in again at the other end (right-hand traffic: every car keeps its lane and direction)
		u = 2.0 if dir > 0 else _len - 2.0
	_place()


func _place() -> void:
	var pa := Bridges.point_at(bridge, u)
	var p: Vector3 = pa[0]
	var d: Vector3 = pa[1]
	var right := d.cross(Vector3.UP).normalized()
	var lane := right * LANE * float(dir)
	var ahead := Bridges.point_at(bridge, clampf(u + float(dir) * 3.0, 0.0, _len))
	var look := (ahead[0] as Vector3) - p
	if look.length() < 0.01:
		look = d * float(dir)
	var pos := p + lane + Vector3(0.0, 0.08, 0.0)
	global_transform = Transform3D(Basis.looking_at(look.normalized(), Vector3.UP), pos)


## Test helper: the distance between the car and the deck height at its position.
func deck_error() -> float:
	var y := Bridges.deck_y(global_position.x, global_position.z, global_position.y)
	return absf(global_position.y - y) if y != Bridges.NONE else INF
