extends Node3D
func _ready() -> void:
	var a := Airport.to_world(Vector3(1262.0, 0.0, -300.0))
	var b := Airport.to_world(Vector3(1262.0, 0.0, -800.0))
	print("RUNWAY ", a, " ", b, " h ", TerrainHeight.height_at(a.x, a.z), " heading ", Airport.heading_world(0.0))
	get_tree().quit()
