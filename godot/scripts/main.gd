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
]


func _ready() -> void:
	var loaded := 0
	for path: String in MODULES:
		if ResourceLoader.exists(path):
			add_child((load(path) as PackedScene).instantiate())
			loaded += 1
	if loaded == 0:
		_build_placeholder()
	Game.set_quality(Game.quality)      # every module starts on the same graphics tier (--quality=N, saved setting)
	# With a HUD the menu is shown first; tools and tests (Game.autostart) skip straight to play.
	var has_ui := ResourceLoader.exists("res://scenes/hud.tscn")
	Game.state = &"play" if (Game.autostart or not has_ui) else &"menu"


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
