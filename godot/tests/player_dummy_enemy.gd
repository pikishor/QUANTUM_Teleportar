extends StaticBody3D
## Stand-in for a Drone / operative, used by the player tests and the player bot: group "enemy", the damage contract
## damage(amount, crit := false, mirrored := false), center(), radius, hp, type. Optional collider on the enemy layer and a visible body.

var hp := 100.0
var max_hp := 100.0
var radius := 0.9
var dead := false
var type: StringName = &"sentinel"
var center_height := 1.0
var hits: Array[Vector2] = []              ## (amount, 1.0 when crit)
var respawn_after := -1.0                  ## > 0: stand up again this many seconds after dying (bot)
var _dead_time := 0.0
var _flash := 0.0
var _eye: MeshInstance3D
var _mat: StandardMaterial3D


func setup(r: float, with_collider: bool, visual: bool) -> void:
	radius = r
	collision_layer = Game.L_ENEMY if with_collider else 0
	collision_mask = 0
	if with_collider:
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = r
		cs.shape = sph
		cs.position = Vector3(0.0, center_height, 0.0)
		add_child(cs)
	if visual:
		_build_visual()


func _ready() -> void:
	add_to_group(&"enemy")


func center() -> Vector3:
	return global_position + Vector3(0.0, center_height, 0.0)


func damage(amount: float, crit := false, _mirrored := false) -> void:
	if dead:
		return
	hits.append(Vector2(amount, 1.0 if crit else 0.0))
	hp -= amount
	_flash = 0.12
	if hp <= 0.0:
		dead = true
		_dead_time = 0.0
		if _mat != null:
			_mat.albedo_color = Color(0.05, 0.05, 0.05)
		rotation.x = deg_to_rad(-75.0)


func total_damage() -> float:
	var t := 0.0
	for h in hits:
		t += h.x
	return t


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _mat != null and not dead:
			_mat.emission_enabled = _flash > 0.0
	if dead and respawn_after > 0.0:
		_dead_time += delta
		if _dead_time > respawn_after:
			dead = false
			hp = max_hp
			rotation.x = 0.0
			if _mat != null:
				_mat.albedo_color = Color(0.1, 0.11, 0.13)


func _build_visual() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.1, 0.11, 0.13)
	_mat.roughness = 0.6
	_mat.metallic = 0.5
	_mat.emission = Color(1.0, 0.25, 0.2)
	_mat.emission_energy_multiplier = 1.5
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.5
	body.mesh = cap
	body.material_override = _mat
	body.position = Vector3(0.0, 0.9, 0.0)
	add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.17
	sph.height = 0.34
	head.mesh = sph
	head.material_override = _mat
	head.position = Vector3(0.0, 1.78, 0.0)
	add_child(head)
	_eye = MeshInstance3D.new()
	var eye_mesh := BoxMesh.new()
	eye_mesh.size = Vector3(0.2, 0.05, 0.04)
	_eye.mesh = eye_mesh
	var em := StandardMaterial3D.new()
	em.albedo_color = Color.BLACK
	em.emission_enabled = true
	em.emission = Color(1.0, 0.1, 0.12)
	em.emission_energy_multiplier = 4.0
	_eye.material_override = em
	_eye.position = Vector3(0.0, 1.8, -0.15)
	add_child(_eye)
