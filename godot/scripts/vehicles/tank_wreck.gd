class_name TankWreck
extends RefCounted
## Tank destruction (wave 108): when an armoured vehicle (VehicleCraft class tank: the battle tank, light tank, carrier, artillery, anti-air) blows up, its turret is thrown off, spins up to about
## six metres, lands beside the burning hull and stays there as a wreck piece for half a minute. The hull keeps the usual wreck (smoke, fire, chain blasts of Vehicle.explode). `Vehicle.activate`
## shows the turret again when the vehicle is recycled. Counters are for tests.

const FLIGHT := 1.7                        ## seconds in the air
const STAY := 30.0                         ## seconds the turret lies on the ground

static var popped := 0                     ## turrets thrown off, lifetime
static var live := 0                       ## turret wrecks lying around right now


## Throw the turret of `v` off. Returns the flying copy (null when the vehicle has no turret node or is not in a scene).
static func pop_turret(v: Vehicle) -> Node3D:
	if v.visual == null or not v.is_inside_tree():
		return null
	var t := v.visual.parts.get("Turret") as Node3D
	var host := v.get_parent()
	if t == null or host == null or not t.is_inside_tree() or not t.visible:
		return null
	var c := t.duplicate() as Node3D
	host.add_child(c)
	c.global_transform = t.global_transform
	t.visible = false
	popped += 1
	live += 1
	var start := c.global_position
	var a := randf() * TAU
	var dir := Vector3(cos(a), 0.0, sin(a))
	var ground := v.global_position.y + 0.9
	var vy := 9.0
	var g := 2.0 * (vy * FLIGHT * 0.5 + maxf(0.0, start.y - ground)) / (FLIGHT * FLIGHT) * 2.0       # lands at about `FLIGHT` seconds
	g = maxf(g, 8.0)
	var spin := Vector3(randf_range(-2.0, 2.0), randf_range(-3.0, 3.0), randf_range(-1.5, 1.5))
	var rot0 := c.rotation
	var tw := c.create_tween()
	tw.tween_method(func(k: float) -> void:
		if not is_instance_valid(c):
			return
		var tt := k * FLIGHT
		var y := start.y + vy * tt - 0.5 * g * tt * tt
		c.global_position = Vector3(start.x + dir.x * 3.2 * k, maxf(y, ground), start.z + dir.z * 3.2 * k)
		c.rotation = rot0 + spin * k, 0.0, 1.0, FLIGHT)
	tw.tween_interval(STAY)
	tw.tween_callback(func() -> void:
		live = maxi(0, live - 1)
		if is_instance_valid(c):
			c.queue_free())
	FX.burst(start, Color(1.0, 0.55, 0.15), 14, 6.0, 0.7, -3.0, 1.8)
	return c
