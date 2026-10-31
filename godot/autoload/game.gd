extends Node
## Global state, shared constants, input map and the damage helpers every module uses.
## Modules register themselves here in _ready() (Game.player = self, ...), so they never need hard node paths.

signal message(text: String, seconds: float)
signal heat_changed(heat: float)
signal score_changed(score: int)
signal state_changed(state: StringName)
signal player_died
signal sector_cleared
signal quality_changed(level: int)
## Lifecycle: every module resets itself when these fire (see ARCHITECTURE.md).
signal new_game             # fresh run: score/heat zeroed, player at spawn, new cores, patrols rebuilt
signal respawn              # after death: player restored at spawn, reinforcements removed, cores kept
signal next_sector          # after a win: new (larger) core set, patrols rebuilt, player restored

# --- city layout: metres, Y up, forward is -Z ---------------------------------------------------
const PITCH := 80.0          # distance between road centre lines
const ROAD := 20.0           # road width
const N := 8                 # blocks per side
const HALF := N * PITCH / 2.0
const LANE := 5.0            # lane centre offset from a road's centre line
const SPAWN := Vector3(-30.0, 0.0, 4.0)

# --- physics layers (bit values; names are set in project.godot) --------------------------------
const L_WORLD := 1
const L_PLAYER := 2
const L_ENEMY := 4
const L_VEHICLE := 8
const L_PROJECTILE := 16
const L_TRIGGER := 32

# --- registry: each module assigns itself in _ready() -------------------------------------------
var player: Node3D           # Player
var world: Node3D            # City
var enemies: Node            # EnemyManager
var vehicles: Node           # VehicleManager
var missions: Node           # Missions
var atmosphere: Node         # Atmosphere
var progress: Node           # Progress (scripts/progress/progress.gd, child of Missions): credits, upgrades, reputation, save file
var story: Node              # Story (scripts/story/story.gd): radio subtitles, cards, chapters
var camera: Camera3D         # the active gameplay camera

var state: StringName = &"menu":   # menu | play | paused | dead | win
	set(v):
		if state != v:
			state = v
			state_changed.emit(state)
var score := 0:
	set(v):
		score = v
		score_changed.emit(score)
var heat := 0.0:             # Observation level, 0..5
	set(v):
		heat = clampf(v, 0.0, 5.0)
		heat_changed.emit(heat)
var quiet := 0.0             # seconds since any drone last had the player in sight
## True when launched by tests/bots/shot tools (or --autostart): skip the menu and start playing at once.
var autostart := false
## Blood and gore-style effects. Off until the store rating is decided; a settings toggle and regional builds can flip it.
var graphic_violence := false
## Force the touch overlay on (desktop testing). The HUD also shows it automatically on touchscreens.
var force_touch := false
## Graphics tier 0 (low) .. 2 (high). Change it only through set_quality(), which reaches the world and the atmosphere.
## Tools take --quality=N; the settings screen persists the player's choice and re-applies it at startup.
var quality := 1

const ACTION_KEYS := {
	&"move_forward": [KEY_W, KEY_UP], &"move_back": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT], &"move_right": [KEY_D, KEY_RIGHT],
	&"jump": [KEY_SPACE], &"sprint": [KEY_SHIFT], &"reload": [KEY_R],
	&"blink": [KEY_Q], &"entangle": [KEY_E], &"superpose": [KEY_G],
	&"interact": [KEY_F], &"pause": [KEY_ESCAPE],
}


func _ready() -> void:
	_setup_input_map()
	# Global shader parameters every material may read (declare in a shader as: global uniform float wetness;).
	# wetness 0..1 = how wet/reflective surfaces look; rain 0..1 = rain intensity. The Atmosphere module drives them.
	RenderingServer.global_shader_parameter_add(&"wetness", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.8)
	RenderingServer.global_shader_parameter_add(&"rain", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	for a in OS.get_cmdline_user_args():
		if a in ["--autostart", "--shot", "--bot", "--shot-seq"] or a.begins_with("--shot=") or a.begins_with("--bot=") or a.begins_with("--shot-seq="):
			autostart = true
		if a == "--touch":
			force_touch = true
		if a.begins_with("--quality="):
			quality = clampi(a.get_slice("=", 1).to_int(), 0, 2)


func is_playing() -> bool:
	return state == &"play"


## The one switch for everything that scales with the graphics tier: the world (shadows, reflections, render scale, MSAA) and the
## atmosphere (rain density, post effects). Safe to call at any time, with or without those modules present.
func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	if is_instance_valid(world) and world.has_method(&"set_quality"):
		world.call(&"set_quality", quality)
	if is_instance_valid(atmosphere) and atmosphere.has_method(&"set_quality"):
		atmosphere.call(&"set_quality", quality)
	quality_changed.emit(quality)


## Instantiate res://assets/models/<name>.glb, or null when the model has not been made yet.
## Modules must fall back to primitive meshes on null so the game always runs.
func load_model(model_name: String) -> Node3D:
	var path := "res://assets/models/%s.glb" % model_name
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene:
			return scene.instantiate() as Node3D
	return null


func start_new_game() -> void:
	score = 0
	heat = 0.0
	quiet = 0.0
	new_game.emit()
	state = &"play"


func do_respawn() -> void:
	heat = 0.0
	quiet = 0.0
	respawn.emit()
	state = &"play"


func do_next_sector() -> void:
	heat = 0.0
	quiet = 0.0
	next_sector.emit()
	state = &"play"


## Called by the Player when hp reaches 0.
func die() -> void:
	if state == &"play":
		state = &"dead"
		player_died.emit()


## Called by Missions when the last core is collected.
func win() -> void:
	if state == &"play":
		state = &"win"
		sector_cleared.emit()


## Gameplay reads only these actions. Touch controls and the dev bot drive them with Input.action_press().
func _setup_input_map() -> void:
	for action: StringName in ACTION_KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in ACTION_KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)
	for pair: Array in [[&"fire", MOUSE_BUTTON_LEFT], [&"aim", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1] as MouseButton
		InputMap.action_add_event(pair[0], mb)


func add_heat(v: float) -> void:
	heat += v
	quiet = 0.0


func add_score(v: int) -> void:
	score += v


func say(text: String, seconds := 2.0) -> void:
	message.emit(text, seconds)


## Area damage plus the explosion effect (FX.blast: fireball, smoke, ground ring, sparks, debris, light, heat haze).
## opts: enemy_dmg (60), car_dmg (60), player_dmg (30), color (orange), burn (seconds a wreck keeps burning: default 6 from radius 8 up, 0 below),
## style (optional, FX.blast: -1 auto from colour and radius).
func explode(pos: Vector3, radius: float, opts := {}) -> void:
	var enemy_dmg: float = opts.get("enemy_dmg", 60.0)
	var car_dmg: float = opts.get("car_dmg", 60.0)
	var player_dmg: float = opts.get("player_dmg", 30.0)
	var color: Color = opts.get("color", Color(1.0, 0.54, 0.19))
	FX.blast(pos, radius, color, 0.5, int(opts.get("style", -1)), float(opts.get("burn", 0.0)))
	var cam_pos: Vector3 = camera.global_position if is_instance_valid(camera) else pos
	FX.shake(clampf(radius * 1.6 / (cam_pos.distance_to(pos) + 6.0), 0.0, 1.0))
	Sfx.play_at(&"boom" if radius >= 5.0 else &"explosion_small", pos, -3.0)                 # positional: an explosion across the street is quieter and comes from where it is
	if enemy_dmg > 0.0:
		for e: Node3D in get_tree().get_nodes_in_group(&"enemy"):
			var reach := radius + 0.8
			var d := e.global_position.distance_to(pos)
			if d < reach:
				e.damage(enemy_dmg * (1.0 - 0.6 * d / reach))
	for v: Node3D in get_tree().get_nodes_in_group(&"vehicle"):
		var d := v.global_position.distance_to(pos)
		if d < radius + 2.0:
			v.damage(car_dmg * (1.0 - 0.6 * d / (radius + 2.0)))
	if player_dmg > 0.0 and is_instance_valid(player):
		var d := player.global_position.distance_to(pos)
		if d < radius:
			player.damage(player_dmg * (1.0 - 0.6 * d / radius), pos)
