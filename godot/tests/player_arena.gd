extends RefCounted
## A small cyber-noir arena for the player's visual bot: wet asphalt, concrete walls with neon strips, containers, barriers, a parked car and
## target dummies, lit by a moon, neon spill and a sodium lamp. Built from the project's own PBR texture sets, no other module needed.
## Layout (x along the avenue, the player spawns at ARENA_SPAWN looking +X):
##   floor 120 x 120 m, a long wall at x = 34 with neon, side walls at z = +-20, a container stack at (-14, 0, 12), the 70 cm barrier row at x = 4.

const Fixture := preload("res://tests/player_fixture.gd")

const ARENA_SPAWN := Vector3(-8.0, 0.0, 0.0)
const ARENA_YAW := -PI * 0.5


## Returns {dummies: Array[Node3D], car: Node3D, wall_x: float, back_wall: Vector3}
static func build(parent: Node3D) -> Dictionary:
	var arena := Node3D.new()
	arena.name = "PlayerArena"
	parent.add_child(arena)
	_environment(arena)
	_lights(arena)

	var asphalt := _pbr("asphalt", Color(0.5, 0.52, 0.56), Vector3(30.0, 30.0, 1.0), 0.5)
	var concrete := _pbr("concrete", Color(0.55, 0.58, 0.62), Vector3(0.28, 0.28, 0.28), 0.9, true)
	var rust := _pbr("metal_painted", Color(0.36, 0.1, 0.07), Vector3(0.3, 0.3, 0.3), 0.8, true)
	var teal := _pbr("metal_painted", Color(0.06, 0.2, 0.24), Vector3(0.3, 0.3, 0.3), 0.8, true)

	# ground and walls (colliders on the world layer)
	Fixture.add_floor(arena, 60.0, 0.0)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	floor_mesh.mesh = plane
	floor_mesh.material_override = asphalt
	arena.add_child(floor_mesh)
	Fixture.add_box(arena, Vector3(34.0, 9.0, 0.0), Vector3(2.0, 18.0, 44.0), concrete)
	Fixture.add_box(arena, Vector3(0.0, 9.0, -21.0), Vector3(70.0, 18.0, 2.0), concrete)
	Fixture.add_box(arena, Vector3(0.0, 9.0, 21.0), Vector3(70.0, 18.0, 2.0), concrete)
	Fixture.add_box(arena, Vector3(-30.0, 9.0, 0.0), Vector3(2.0, 18.0, 44.0), concrete)
	# the pull-in test wall: a low wall behind the spawn
	Fixture.add_box(arena, Vector3(-17.0, 1.6, -4.0), Vector3(1.0, 3.2, 10.0), concrete)
	# containers and barriers
	Fixture.add_box(arena, Vector3(-14.0, 1.3, 12.0), Vector3(6.0, 2.6, 2.5), rust)
	Fixture.add_box(arena, Vector3(-14.0, 3.9, 12.5), Vector3(6.0, 2.6, 2.5), teal)
	Fixture.add_box(arena, Vector3(14.0, 1.3, -15.0), Vector3(6.0, 2.6, 2.5), teal)
	for i in 5:
		Fixture.add_box(arena, Vector3(4.0, 0.35, -8.0 + i * 3.4), Vector3(0.7, 0.7, 2.4), concrete)

	# neon strips (emissive) with a light each: magenta and cyan practical sources
	_neon(arena, Vector3(33.0, 5.0, -10.0), Vector3(0.12, 0.35, 14.0), Color(1.0, 0.1, 0.65), Vector3(31.0, 5.0, -10.0))
	_neon(arena, Vector3(33.0, 8.0, 8.0), Vector3(0.12, 0.35, 10.0), Color(0.1, 0.85, 1.0), Vector3(31.0, 8.0, 8.0))
	_neon(arena, Vector3(-8.0, 6.0, -19.8), Vector3(12.0, 0.3, 0.12), Color(0.1, 0.85, 1.0), Vector3(-8.0, 5.0, -17.5))
	_neon(arena, Vector3(18.0, 4.0, 19.8), Vector3(9.0, 0.3, 0.12), Color(1.0, 0.1, 0.65), Vector3(18.0, 4.0, 17.0))

	# targets
	var dummies: Array[Node3D] = []
	for pos: Vector3 in [Vector3(10.0, 0.0, 0.0), Vector3(17.0, 0.0, 6.0), Vector3(15.0, 0.0, -7.0), Vector3(24.0, 0.0, -2.0)]:
		var d := Fixture.add_dummy(arena, pos, 0.95, true, true)
		d.respawn_after = 2.0
		dummies.append(d)
	# a parked car
	var car := Fixture.add_vehicle(arena, Vector3(2.0, 0.0, 12.0), Vector3(1.9, 1.3, 4.5), true, true)
	car.rotation.y = PI * 0.5
	return {"dummies": dummies, "car": car, "wall_x": 34.0}


static func _environment(parent: Node3D) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.012, 0.025, 0.06)
	sky_mat.sky_horizon_color = Color(0.07, 0.12, 0.17)
	sky_mat.ground_horizon_color = Color(0.07, 0.12, 0.17)
	sky_mat.ground_bottom_color = Color(0.02, 0.03, 0.05)
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 2.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_scale = 2.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.24, 0.31)
	env.fog_density = 0.012
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)


static func _lights(parent: Node3D) -> void:
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.58, 0.72, 1.0)
	moon.light_energy = 1.5
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 70.0
	moon.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	parent.add_child(moon)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.72, 0.42)
	lamp.light_energy = 3.0
	lamp.omni_range = 22.0
	lamp.position = Vector3(2.0, 6.0, 0.0)
	parent.add_child(lamp)
	var post := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.09
	cyl.height = 6.0
	post.mesh = cyl
	post.position = Vector3(2.0, 3.0, 0.0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.05, 0.055, 0.06)
	post.material_override = pm
	parent.add_child(post)
	var bulb := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.22
	bm.height = 0.44
	bulb.mesh = bm
	var em := StandardMaterial3D.new()
	em.albedo_color = Color.BLACK
	em.emission_enabled = true
	em.emission = Color(1.0, 0.72, 0.42)
	em.emission_energy_multiplier = 6.0
	bulb.material_override = em
	bulb.position = Vector3(2.0, 6.0, 0.0)
	parent.add_child(bulb)


static func _neon(parent: Node3D, pos: Vector3, size: Vector3, color: Color, light_pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 5.0
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 2.6
	l.omni_range = 16.0
	l.position = light_pos
	parent.add_child(l)


## An ORM material from one of the project's procedural texture sets (assets/textures/<set>_albedo/orm/normal.png).
static func _pbr(set_name: String, tint: Color, uv: Vector3, rough_mult: float, triplanar := false) -> ORMMaterial3D:
	var m := ORMMaterial3D.new()
	var base := "res://assets/textures/%s_" % set_name
	if ResourceLoader.exists(base + "albedo.png"):
		m.albedo_texture = load(base + "albedo.png") as Texture2D
		m.orm_texture = load(base + "orm.png") as Texture2D
		m.normal_enabled = true
		m.normal_texture = load(base + "normal.png") as Texture2D
	m.albedo_color = tint
	m.roughness = rough_mult
	m.uv1_scale = uv
	m.uv1_triplanar = triplanar
	return m
