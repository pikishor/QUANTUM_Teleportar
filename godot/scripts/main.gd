extends Node3D
## Composition root. Instantiates each module's scene if it exists, so modules can be built independently.
## Modules register themselves on the Game singleton (Game.player, Game.world, ...) in their own _ready().

const MODULES := [
	"res://scenes/world.tscn",
	"res://scenes/atmosphere.tscn",
	"res://scenes/player.tscn",
	"res://scenes/enemy_manager.tscn",
	"res://scenes/vehicle_manager.tscn",
	"res://scenes/missions.tscn",
	"res://scenes/hud.tscn",
	"res://scenes/story.tscn",      # after the HUD: its cards get taps before the HUD and the touch controls do
]


func _ready() -> void:
	# A real run (not a tool, test or bot) first shows LOADING and builds the heavy modules two frames later, so the title never looks frozen.
	var overlay: LoadingOverlay = null
	if not Game.autostart and DisplayServer.get_name() != "headless":
		overlay = LoadingOverlay.new()
		add_child(overlay)
		await get_tree().process_frame
		await get_tree().process_frame
	var loaded := 0
	for path: String in MODULES:
		if ResourceLoader.exists(path):
			add_child((load(path) as PackedScene).instantiate())
			loaded += 1
	if loaded == 0:
		_build_placeholder()
	Game.set_quality(Game.quality)      # every module starts on the same graphics tier (--quality=N, saved setting)
	add_child(PerfTiers.new())          # mesh LOD threshold, anisotropy and mip bias per tier, Compatibility pool caps (scripts/common/perf_tiers.gd)
	add_child(AutoQuality.new())        # touchscreens start on LOW until the player chooses; a sustained low frame rate drops one tier
	add_child(Stability.new())          # watchdog: held input, time scale, camera / player / HUD consistency, hurt and death feedback
	if not Game.autostart:
		Sfx.play_music()                # the ambient loop: not under tools, tests and bots (Game.autostart), which stay silent
	if overlay != null:                 # behind the opaque loading overlay: draw every effect, enemy type and car kind once, so the first fight has no shader hitch
		await ShaderWarmup.run(self)
	# With a HUD the menu is shown first; tools and tests (Game.autostart) skip straight to play.
	var has_ui := ResourceLoader.exists("res://scenes/hud.tscn")
	Game.state = &"play" if (Game.autostart or not has_ui) else &"menu"
	if overlay != null:
		await get_tree().process_frame
		overlay.finish()


## Shown until the first module exists, so the project always renders something.
func _build_placeholder() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 6, 12)
	cam.look_at(Vector3.ZERO)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
