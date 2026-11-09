class_name PlayerSwim
extends RefCounted
## The hero in water (oxygen-free: nobody drowns). Wading in the shallows slows him and kicks up splashes; chest-deep water makes him SWIM: he floats with the
## water at his chest, strokes in the stick direction (sprint = a fast crawl), is carried by a river's current, bobs on the waves and can hop out onto a ledge with
## JUMP. Landing in deep water from a height plunges him in with a big splash and he eases back up. Player._foot_tick asks `tick()` once per physics step before the
## ground movement; when it returns true the swim has moved the body and ground movement is skipped. The water comes from WaterWorld.surface_y (TerrainHeight under it).
##
## State read by the body animation and the tests: `active` (swimming), `wading`, `depth` (m of water over the feet), `surface` (y), `lean` (0..1 the crawl pitch),
## `stroke_phase`, `splashes` (count, for tests), `last_splash`.

const WADE_FROM := 0.3                  ## water over the feet (m) that counts as wading
const SWIM_ENTER := 1.25                ## ... that starts swimming
const SWIM_LEAVE := 0.95                ## ... below which he stands up again (hysteresis)
const FLOAT_DEPTH := 1.1                ## feet this far under the surface while swimming (water at the chest)
const SWIM_SPEED := 3.3
const CRAWL_SPEED := 5.6
const WADE_MULT := 0.62
const STROKE_RATE := 2.2                ## strokes per second at swim speed
const HOP_SPEED := 6.2

var active := false
var wading := false
var depth := 0.0
var surface := TerrainHeight.NO_WATER
var lean := 0.0
var stroke_phase := 0.0
var splashes := 0
var last_splash := 0.0
var wade_mult := 1.0                    ## ground speed factor Player applies while wading
var _step_t := 0.0
var _hop_cool := 0.0
var _hop_t := 0.0
var _stroke_n := 0
var _entered_t := 99.0


func reset() -> void:
	active = false
	wading = false
	depth = 0.0
	surface = TerrainHeight.NO_WATER
	lean = 0.0
	wade_mult = 1.0
	_step_t = 0.0
	_entered_t = 99.0


## Looks at the water under the hero. Cheap: one terrain sample plus the wave sum.
func probe(p: Node3D) -> void:
	var pos := p.global_position
	surface = WaterWorld.surface_y(pos.x, pos.z)
	depth = 0.0 if surface == TerrainHeight.NO_WATER else surface - pos.y
	wading = depth > WADE_FROM and not active
	wade_mult = WADE_MULT if wading else 1.0


## One physics step. Returns true when the hero is swimming (the body has been moved: skip the ground movement). `wish` = horizontal move direction (length <= 1).
func tick(p: CharacterBody3D, dt: float, wish: Vector3, jump_down: bool, sprint: bool) -> bool:
	probe(p)
	_entered_t += dt
	_hop_cool = maxf(0.0, _hop_cool - dt)
	_hop_t = maxf(0.0, _hop_t - dt)
	if surface == TerrainHeight.NO_WATER:
		_leave(p)
		return false
	if not active:
		if depth < SWIM_ENTER or p.velocity.y > 3.0:
			_wade(p, dt, wish)
			return false
		_enter(p)
	elif depth < SWIM_LEAVE and _hop_t <= 0.0:
		_leave(p)
		return false
	# --- swimming: float with the water at the chest, stroke along the stick, drift with the river
	var pos := p.global_position
	var top := (CRAWL_SPEED if sprint else SWIM_SPEED) * (1.0 if wish.length_squared() > 0.01 else 0.0)
	var flow := TerrainHeight.flow_at(pos.x, pos.z)
	var target := Vector3(wish.x * top + flow.x, 0.0, wish.z * top + flow.y)
	p.velocity.x = PlayerUtil.damp(p.velocity.x, target.x, 4.5, dt)
	p.velocity.z = PlayerUtil.damp(p.velocity.z, target.z, 4.5, dt)
	var want_y := surface - FLOAT_DEPTH
	if _hop_t > 0.0:
		p.velocity.y -= 16.0 * dt                       # a hop: free flight for a moment, no spring
	elif _entered_t < 0.8 and p.velocity.y < -2.0:
		p.velocity.y *= exp(-9.0 * dt)                  # the plunge: the water eats the fall, then the spring brings him up
		p.velocity.y += (want_y - pos.y) * 14.0 * dt
	else:
		p.velocity.y = PlayerUtil.damp(p.velocity.y, clampf((want_y - pos.y) * 7.0, -5.0, 5.0), 8.0, dt)
	if jump_down and _hop_cool <= 0.0:
		p.velocity.y = HOP_SPEED                        # a hop that clears a ledge; the spring pulls him back down if there is none
		_hop_cool = 0.6
		_hop_t = 0.4
		WaterWorld.splash(Vector3(pos.x, pos.y, pos.z), 0.7)
		splashes += 1
	p.move_and_slide()
	var sp := Vector2(p.velocity.x - flow.x, p.velocity.z - flow.y).length()
	lean = PlayerUtil.damp(lean, clampf(sp / CRAWL_SPEED, 0.0, 1.0), 5.0, dt)
	stroke_phase += dt * STROKE_RATE * clampf(sp / SWIM_SPEED, 0.0, 1.8) * TAU * 0.5
	var n := int(floor(stroke_phase / PI))
	if n != _stroke_n:
		_stroke_n = n
		if sp > 1.0:
			Sfx.play_at(&"water_stroke", p.global_position, -7.0)
			if FX.marks != null:
				FX.marks.ripple(Vector3(p.global_position.x, surface + 0.02, p.global_position.z), 1.0 + lean * 0.8)
	return true


func _enter(p: CharacterBody3D) -> void:
	active = true
	wading = false
	_entered_t = 0.0
	var fall := -p.velocity.y
	var strength := clampf(0.7 + maxf(fall - 3.0, 0.0) * 0.12, 0.7, 2.6)
	WaterWorld.splash(Vector3(p.global_position.x, surface, p.global_position.z), strength)
	splashes += 1
	last_splash = strength


func _leave(_p: Node3D) -> void:
	if active:
		var pos := _p.global_position
		WaterWorld.splash(Vector3(pos.x, maxf(surface, pos.y), pos.z), 0.5)
	active = false
	lean = 0.0


## Shallow water: footsteps splash and rustle (the body keeps its normal ground movement at WADE_MULT speed).
func _wade(p: CharacterBody3D, dt: float, wish: Vector3) -> void:
	if not wading:
		return
	var sp := Vector2(p.velocity.x, p.velocity.z).length()
	_step_t -= dt * clampf(sp / 3.0, 0.0, 2.0)
	if _step_t <= 0.0 and sp > 0.8 and p.is_on_floor():
		_step_t = 0.42
		WaterWorld.splash(Vector3(p.global_position.x, surface, p.global_position.z), 0.3 + clampf(depth, 0.0, 1.0) * 0.2)
		splashes += 1
	if wish.length_squared() < 0.0001:
		_step_t = minf(_step_t, 0.15)
