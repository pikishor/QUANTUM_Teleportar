extends StaticBody3D
## Stand-in for a Vehicle, used by the player tests and the bot: group "vehicle", damage(amount), heading (Node3D.rotation.y convention),
## speed, hp. A box collider on the vehicle layer when built with a collider.

var hp := 200.0
var heading := 0.0
var speed := 0.0
var hits: Array[float] = []


func setup(size: Vector3, with_collider: bool, visual: bool) -> void:
	collision_layer = Game.L_VEHICLE if with_collider else 0
	collision_mask = 0
	if with_collider:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position = Vector3(0.0, size.y * 0.5, 0.0)
		add_child(cs)
	if visual:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.15, 0.2)
		m.metallic = 0.7
		m.roughness = 0.35
		mi.material_override = m
		mi.position = Vector3(0.0, size.y * 0.5, 0.0)
		add_child(mi)


func _ready() -> void:
	add_to_group(&"vehicle")


func damage(amount: float) -> void:
	hits.append(amount)
	hp -= amount


## Drive in a straight line along the heading.
func drive(delta: float) -> void:
	rotation.y = heading
	global_position += Vector3(-sin(heading), 0.0, -cos(heading)) * speed * delta
