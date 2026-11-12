class_name Landscape
extends Node3D
## Composer of the landscape dressing of wave 112 (child `landscape` of the City): the waterfalls (FallWorld), the grass airstrips (StripWorld) and the tall anchors (AnchorWorld:
## wind turbines, pylon lines, radio masts, quarry cranes). The trees, grass, flowers and rocks are VegetationWorld's (LandKit pieces); the wind is LandClimate's.
##   Landscape.instance                         the node;   stats()   {falls, strips, anchors ...}
##   settle(pos)                                look-dev bots and tests: build and show everything around `pos` now
## `QT_NO_LANDSCAPE=1` leaves it out (perf A/B runs).

static var instance: Landscape = null

var quality := 1
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
	falls = FallWorld.new()
	falls.name = "Falls"
	falls.quality = quality
	add_child(falls)
	if ResourceLoader.exists("res://scripts/landscape/strip_world.gd"):
		strips = (load("res://scripts/landscape/strip_world.gd") as GDScript).new() as Node3D
		strips.name = "Strips"
		add_child(strips)
	if ResourceLoader.exists("res://scripts/landscape/anchor_world.gd"):
		anchors = (load("res://scripts/landscape/anchor_world.gd") as GDScript).new() as Node3D
		anchors.name = "Anchors"
		add_child(anchors)
	set_quality(quality)


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
	if falls != null:
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
