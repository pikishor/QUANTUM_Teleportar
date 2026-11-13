class_name Landscape
extends Node3D
## Composer of the landscape dressing of wave 112 (child `landscape` of the City): the waterfalls (FallWorld), the grass airstrips (StripWorld) and the tall anchors (AnchorWorld:
## wind turbines, pylon lines, radio masts, quarry cranes). The trees, grass, flowers and rocks are VegetationWorld's (LandKit pieces); the wind is LandClimate's.
##   Landscape.instance                         the node;   stats()   {falls, strips, anchors ...}
##   settle(pos)                                look-dev bots and tests: build and show everything around `pos` now
## `QT_NO_LANDSCAPE=1` leaves it out (perf A/B runs).

static var instance: Landscape = null

const WAKE_EDGE := 470.0

var quality := 1
var awake := false                  ## waking has begun (the steps may still be running) or is done
var _todo: Array = []
var falls: FallWorld
var strips: Node3D
var anchors: Node3D


static func attach(parent: Node) -> Landscape:
	var l := Landscape.new()
	l.name = "Landscape"
	parent.add_child(l)
	return l


func _ready() -> void:
	instance = self
	LandscapeSites.ensure()
	set_process(true)


## The falls, strips and anchors are built when the hero leaves the middle of the city (|x| or |z| beyond WAKE_EDGE), one step per frame (a few tens of milliseconds each; the falls
## themselves are built one at a time when the hero comes within FallWorld.BUILD_RANGE of one), or all at once by `wake()` (`settle`, tests, look-dev bots). The start of the city pays for none of it.
func _begin() -> void:
	if awake:
		return
	awake = true
	_todo = [Callable(self, "_step_falls"), Callable(self, "_step_strips"), Callable(self, "_step_anchors"), Callable(self, "_step_quality")]


func wake() -> void:
	_begin()
	while not _todo.is_empty():
		(_todo.pop_front() as Callable).call()
	set_process(false)


func _step_falls() -> void:
	LandClimate.attach(self)
	falls = FallWorld.new()
	falls.name = "Falls"
	falls.quality = quality
	add_child(falls)


func _step_strips() -> void:
	strips = StripWorld.new()
	strips.name = "Strips"
	add_child(strips)


func _step_anchors() -> void:
	anchors = AnchorWorld.new()
	anchors.name = "Anchors"
	add_child(anchors)


func _step_quality() -> void:
	set_quality(quality)


func _process(_delta: float) -> void:
	if not awake:
		var p := Game.player as Node3D
		if is_instance_valid(p) and maxf(absf(p.global_position.x), absf(p.global_position.z)) > WAKE_EDGE:
			_begin()
		return
	if _todo.is_empty():
		set_process(false)
		return
	(_todo.pop_front() as Callable).call()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	if falls != null and falls.quality != quality:
		falls.set_quality(quality)
	for n in [strips, anchors]:
		if n != null and n.has_method(&"set_quality"):
			n.call(&"set_quality", quality)


func settle(pos: Vector3) -> void:
	wake()
	if falls != null:
		for _i in 8:                                            # one fall is built per tick: tick until every fall in range stands
			falls.tick(pos)
	for n in [strips, anchors]:
		if n != null and n.has_method(&"settle"):
			n.call(&"settle", pos)


func stats() -> Dictionary:
	var d := {}
	if falls != null:
		d.merge(falls.stats())
	for n in [strips, anchors]:
		if n != null and n.has_method(&"stats"):
			d.merge(n.call(&"stats"))
	return d
