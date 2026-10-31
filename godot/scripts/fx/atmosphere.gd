class_name Atmosphere
extends Node3D
## The cinematic layer of the game (ARCHITECTURE.md, atmosphere): film look + weather on top of whatever the world renders.
##
##  * a full-screen post-process (scripts/fx/atmosphere_post.gd, assets/shaders/post_film.gdshader): colour grade with
##    lift/gamma/gain (cool teal shadows, warm highlights, crushed blacks), vignette, edge chromatic aberration, temporal film
##    grain, optional sharpening, heat haze, lens droplets and a rain curtain. One pass; each effect individually tunable.
##  * rain (scripts/fx/atmosphere_rain.gd): pooled streak and splash particles that follow Game.camera.
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
			post.visible = v
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

var _globals_dirty := true


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


## 0 low, 1 medium, 2 high: scales the rain density, the splash count and which post effects exist.
func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	if post:
		post.set_quality(quality)
	if rainfield:
		rainfield.set_quality(quality)


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
	var cam := _camera()
	rainfield.update(delta, cam, rain_now)
	if cam != null and rainfield.is_visible_in_tree():
		post.set_slant(rainfield.screen_slant(cam))


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
