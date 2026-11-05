class_name Atmosphere
extends Node3D
## The cinematic layer of the game (ARCHITECTURE.md, atmosphere): film look + weather on top of whatever the world renders.
##
##  * a full-screen post-process (scripts/fx/atmosphere_post.gd, assets/shaders/post_film.gdshader): colour grade with
##    lift/gamma/gain (cool teal shadows, warm highlights, crushed blacks), vignette, edge chromatic aberration, temporal film
##    grain, optional sharpening, heat haze, lens droplets and a rain curtain. One pass; each effect individually tunable.
##  * rain (scripts/fx/atmosphere_rain.gd): pooled streak particles and, on MED and HIGH, ground splashes (thin ripples and tiny droplets that
##    only brighten what the wet ground reflects) that follow Game.camera.
##  * the global shader parameters `wetness` and `rain` (registered by Game._ready, which always runs first: it is an autoload) that
##    every material reads; set_weather() eases them.
##
## API: set_quality(level 0..2) · set_weather(rain, wetness) · enabled (post-process toggle). It never touches gameplay state and
## works without a world, a player or even a camera (the rain then simply is not drawn). It joins the group `atmosphere`.

const PostLayer := preload("res://scripts/fx/atmosphere_post.gd")
const RainField := preload("res://scripts/fx/atmosphere_rain.gd")

## Time constant (seconds) with which rain and wetness ease towards a new set_weather() target.
@export var weather_tau := 1.4
## The weather the game starts with: a steady night rain on soaked streets.
@export var default_rain := 0.7
@export var default_wetness := 0.85
## Post-process toggle for the settings screen. The rain is weather, it is controlled by set_weather() / rain_enabled.
@export var enabled := true:
	set(v):
		enabled = v
		if post:
			post.visible = v and quality >= 1        # LOW draws no full-screen post pass at all (it needs a screen copy: GPU-bound phones lose 5-10 ms to it)
## Hides or shows the rain particles (the global `rain` value that wet materials read is not affected).
@export var rain_enabled := true:
	set(v):
		rain_enabled = v
		if rainfield:
			rainfield.rain_visible = v

## 0 low, 1 medium, 2 high.
var quality := 1
## Current (smoothed) and target values.
var rain_now := 0.0
var wetness_now := 0.0
var rain_target := 0.0
var wetness_target := 0.0
var post: PostLayer
var rainfield: RainField
var weather: Weather                        ## the weather state machine (scripts/fx/weather.gd)

var hurt_level := 0.0                       ## 0..1: a short chromatic-aberration kick after a hit (never accumulates, recovers in about 0.35 s)
var dead_level := 0.0                       ## 0..1: eased desaturation while the player is dead (at most 35 % of the colour)

var _globals_dirty := true
var ability_level := 0.0                    ## 0..1: film kick after a QUANTUM verb (PostFx2.pulse), eases out by itself
var _look_acc := 1.0
var _sun: Node3D
var _dead_target := 0.0


func _ready() -> void:
	add_to_group(&"atmosphere")
	Game.atmosphere = self
	process_priority = 100                      # after the camera rigs, so the rain sits on this frame's camera
	post = PostLayer.new()
	post.name = "PostProcess"
	post.visible = enabled
	add_child(post)
	rainfield = RainField.new()
	rainfield.name = "Rain"
	add_child(rainfield)
	rainfield.rain_visible = rain_enabled
	set_quality(quality)
	set_weather(default_rain, default_wetness, true)
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)


func _exit_tree() -> void:
	if Game.atmosphere == self:
		Game.atmosphere = null


## Rain intensity and surface wetness, both 0..1. They ease in over `weather_tau` seconds (instant = true snaps).
## `rain` drives the streaks, splashes, lens droplets, haze and the rain-dependent materials; `wetness` is how soaked and
## reflective the world looks (the ground shader reads it), so wet streets can stay shiny after the rain stops.
func set_weather(rain: float, wetness: float, instant := false) -> void:
	rain_target = clampf(rain, 0.0, 1.0)
	wetness_target = clampf(wetness, 0.0, 1.0)
	if instant:
		rain_now = rain_target
		wetness_now = wetness_target
		_globals_dirty = true
		_push_weather()


## 0 low, 1 medium, 2 high: scales the rain density, the splash count and which post effects exist. LOW draws no ground splashes
## (its ground is matte; the splashes need the screen copy that the world's wet ground makes on MED and HIGH) and no lens effects.
func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	if post:
		post.set_quality(quality)
		post.visible = enabled and quality >= 1
	if rainfield:
		rainfield.set_quality(quality)


## A hit landed: kicks the chromatic aberration up to its cap and lets it fall back at once. Repeated hits keep it at the cap, they never stack higher.
func hurt_pulse(strength := 1.0) -> void:
	hurt_level = maxf(hurt_level, clampf(strength, 0.0, 1.0))


## The player died (true) or lives again (false): the colour drains by at most 35 % and returns by itself.
func set_dead(on: bool) -> void:
	_dead_target = 1.0 if on else 0.0


## Drop every transient feedback effect at once (state changes: respawn, menu, new sector).
func clear_feedback() -> void:
	hurt_level = 0.0
	dead_level = 0.0
	_dead_target = 0.0
	if post:
		post.set_feedback(0.0, 1.0)


## Designer access to every post effect, for example set_effect(&"grain_amount", 0.03). Names are the uniforms of
## post_film.gdshader; the quality tier still masks effects the device cannot afford.
func set_effect(effect: StringName, value: Variant) -> void:
	if post:
		post.set_param(effect, value)


## Streaks plus splashes currently drawn.
func particle_count() -> int:
	return rainfield.particle_count() if rainfield else 0


## What a quality tier draws at full rain (independent of the current intensity).
static func particle_budget(level: int) -> int:
	return RainField.budget(level)


func _process(delta: float) -> void:
	var k := 1.0 - exp(-delta / maxf(weather_tau, 0.001))
	if rain_now != rain_target:
		rain_now = rain_target if absf(rain_target - rain_now) < 0.002 else lerpf(rain_now, rain_target, k)
		_globals_dirty = true
	if wetness_now != wetness_target:
		wetness_now = wetness_target if absf(wetness_target - wetness_now) < 0.002 else lerpf(wetness_now, wetness_target, k)
		_globals_dirty = true
	if _globals_dirty:
		_push_weather()
	_feedback_step(delta)
	_look_step(delta)
	var cam := _camera()
	rainfield.update(delta, cam, rain_now)
	if cam != null and rainfield.is_visible_in_tree():
		post.set_slant(rainfield.screen_slant(cam))


## QUANTUM verb used: a short chromatic-aberration / grain / cool-edge kick (MED and HIGH). Never accumulates above 1; off with reduce-flash.
func ability_pulse(strength := 1.0) -> void:
	if UiSettings.s_reduce_flash:
		return
	ability_level = maxf(ability_level, clampf(strength, 0.0, 1.0))


## District grade, light shafts and the ability kick (PostFx2). The grade follows the hero through the city and eases between districts.
func _look_step(delta: float) -> void:
	if post == null:
		return
	if ability_level > 0.0:
		ability_level = maxf(0.0, ability_level - delta / maxf(Engine.time_scale, 0.05) * PostFx2.PULSE_DECAY)
		post.set_param(&"ability_amount", ability_level)
	if not post.visible:
		return                                              # LOW: no post pass, nothing more to drive
	_look_acc += delta
	if _look_acc < 0.1:
		return
	_look_acc = 0.0
	var pos: Variant = (Game.player as Node3D).global_position if is_instance_valid(Game.player) and Game.player is Node3D else null
	if InteriorSpace.active:
		pos = null                                          # inside a room the interior's own palette is the look: the street district's grade (the Foundry's red) never tints it
	var g := PostFx2.district_grade(pos)
	post.set_param(&"d_gain", g["gain"])
	post.set_param(&"d_lift", g["lift"])
	post.set_param(&"d_sat", g["sat"])
	var nv: Variant = RenderingServer.global_shader_parameter_get(&"night")
	var night := float(nv) if nv != null else 1.0
	if _sun == null or not is_instance_valid(_sun):
		_sun = get_tree().root.find_child("Moon", true, false) as Node3D
	var cam := _camera()
	if _sun != null and cam != null:
		var to_light := _sun.global_transform.basis.z
		var tw := 4.0 * night * (1.0 - night)               # dusk and dawn: the night amount is half way
		post.set_shafts(PostFx2.sun_screen(cam, to_light), (_sun as DirectionalLight3D).light_color, PostFx2.shaft_amount(night, tw, rain_now))


func _feedback_step(delta: float) -> void:
	if hurt_level <= 0.0 and dead_level == _dead_target:
		return
	var real := delta / maxf(Engine.time_scale, 0.05)             # real seconds: a slow-motion death never stretches the recovery
	hurt_level = maxf(0.0, hurt_level - real * 3.0)
	dead_level = move_toward(dead_level, _dead_target, real * 2.5)
	if post:
		post.set_feedback(hurt_level * PostLayer.FB_CA_MAX, 1.0 - dead_level * PostLayer.FB_SAT_LOSS_MAX)


func _physics_process(_delta: float) -> void:
	rainfield.probe_ground(_camera())


func _camera() -> Camera3D:
	if is_instance_valid(Game.camera) and Game.camera.is_inside_tree():
		return Game.camera
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _push_weather() -> void:
	_globals_dirty = false
	RenderingServer.global_shader_parameter_set(&"rain", rain_now)
	RenderingServer.global_shader_parameter_set(&"wetness", wetness_now)
	post.set_rain(rain_now)
