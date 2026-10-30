extends RefCounted
## WorldEnvironment + moon light for the cyber-noir city: procedural night sky (ambient and reflections come from it),
## exponential fog plus a ground haze layer, glow/bloom, ACES tonemap and a restrained grade. Quality tiers scale shadows, MSAA,
## render scale and the sky radiance size.

const SKY_SHADER := preload("res://assets/shaders/sky.gdshader")

var world_env: WorldEnvironment
var env: Environment
var sky: Sky
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var moon_dir := Vector3(-0.43, 0.46, -0.78).normalized()


func build(parent: Node3D) -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter(&"moon_dir", moon_dir)
	sky = Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_QUALITY          # the radiance map is generated once; clouds animate in the visible pass only
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# cool teal shadows, soft filmic shoulder so neon rolls off instead of clipping
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.0
	# bloom: windows, signs and lamps carry HDR emission
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 0.9
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 12.0
	var levels := [0.35, 0.55, 0.8, 0.65, 0.4, 0.2, 0.0]
	for i in levels.size():
		env.set_glow_level(i, levels[i])
	# haze: distance fog in the colour of wet night air, thicker near the ground
	env.fog_enabled = true
	env.fog_light_color = Color(0.135, 0.185, 0.245)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0052
	env.fog_aerial_perspective = 0.2
	env.fog_sky_affect = 0.55
	env.fog_height = 8.0
	env.fog_height_density = 0.03

	world_env = WorldEnvironment.new()
	world_env.name = "Environment"
	world_env.environment = env
	parent.add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Moon"
	sun.light_color = Color(0.58, 0.72, 1.0)
	sun.light_energy = 0.9
	sun.light_angular_distance = 1.2
	sun.light_specular = 1.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_split_1 = 0.22
	sun.directional_shadow_blend_splits = true
	sun.transform = Transform3D(Basis.looking_at(-moon_dir, Vector3.UP), Vector3.ZERO)
	parent.add_child(sun)


## level 0 low, 1 medium, 2 high. `vp` is the viewport the world renders into (MSAA / render scale live there).
func apply_quality(level: int, vp: Viewport) -> void:
	level = clampi(level, 0, 2)
	sun.shadow_enabled = level >= 1
	sun.directional_shadow_max_distance = 90.0 if level == 1 else 150.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_blur = 1.0 if level == 1 else 1.6
	sky.radiance_size = Sky.RADIANCE_SIZE_32 if level == 0 else Sky.RADIANCE_SIZE_64
	if vp != null:
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][level]
		vp.scaling_3d_scale = 0.7 if level == 0 else 1.0
	env.glow_intensity = [0.8, 0.9, 1.0][level]
	env.fog_density = 0.0052
