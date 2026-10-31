extends RefCounted
## A small, self-contained wet night street for the atmosphere module's visual checks (tests/bot_atmosphere.gd): a glossy floor
## that reflects emissive neon strips, windows and lamps, dark buildings, a few props, lamp lights and a night environment with fog,
## bloom and the filmic tonemap the game uses. It depends on no other module (models are optional: primitives stand in).
## The wet floor reflects a mirrored copy of the emissive geometry placed under it, read back from the screen with a smear.

const FACADE_CODE := """
shader_type spatial;
render_mode cull_back;
uniform float mirror_mode = 0.0;
varying vec3 v_w;
varying vec3 v_n;
float h12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
void vertex() {
	v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	bool side = abs(v_n.y) < 0.5;
	float u = abs(v_n.x) > 0.5 ? v_w.z : v_w.x;
	float vv = abs(v_w.y);
	vec2 cell = vec2(floor(u / 3.1), floor(vv / 3.7));
	vec2 f = vec2(fract(u / 3.1), fract(vv / 3.7));
	float win = step(0.26, f.x) * step(f.x, 0.74) * step(0.30, f.y) * step(f.y, 0.70);
	float slab = step(f.y, 0.07) + step(0.93, f.y);
	float bld = floor(v_w.x * 0.045 + 7.0) * 3.1 + floor(v_w.z * 0.05 + 3.0) * 5.7;
	float r = h12(cell + bld);
	float lit = step(0.52, r) * win * (side ? 1.0 : 0.0);
	vec3 col = vec3(1.0, 0.62, 0.30);
	if (r > 0.96) col = vec3(1.0, 0.16, 0.52);
	else if (r > 0.90) col = vec3(0.40, 0.80, 1.0);
	else if (r > 0.80) col = vec3(0.62, 0.84, 1.0);
	float grime = h12(floor(vec2(u * 2.0, vv * 0.8))) * 0.5 + 0.5;
	vec3 wall = vec3(0.040, 0.044, 0.054) * (0.55 + 0.9 * grime) * (1.0 + 0.6 * slab);
	vec3 glass = vec3(0.010, 0.014, 0.020);
	ALBEDO = mix(wall, glass, win * (side ? 1.0 : 0.0));
	ROUGHNESS = mix(0.85, 0.2, win);
	METALLIC = win * 0.3;
	EMISSION = lit * col * (0.55 + 1.5 * h12(cell + 7.7));
	if (mirror_mode > 0.5) { ALBEDO = vec3(0.0); }
}
"""

const FLOOR_CODE := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;
global uniform float wetness;
global uniform float rain;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
varying vec3 v_w;
float h12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
vec2 h22(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973)); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.xx + p3.yz) * p3.zy); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1, 0)), f.x), mix(h12(i + vec2(0, 1)), h12(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return vn(p) * 0.5 + vn(p * 2.03 + 11.7) * 0.3 + vn(p * 4.1 + 3.1) * 0.2; }
// concentric ripples of falling drops: x = height, y = radial slope
vec2 ripples(vec2 p, float t, float amount) {
	vec2 r = vec2(0.0);
	for (int k = 0; k < 2; k++) {
		vec2 pk = p * (1.7 + 0.8 * float(k)) + float(k) * 17.3;
		vec2 id = floor(pk); vec2 f = fract(pk) - 0.5;
		vec2 o = h22(id) - 0.5; float ph = h12(id + 3.7);
		float life = fract(t * (0.6 + 0.4 * ph) + ph * 7.0);
		float d = length(f - o * 0.6); float rad = life * 0.55;
		float ring = exp(-pow((d - rad) / 0.06, 2.0)) * (1.0 - life) * (1.0 - life);
		float on = step(0.7 - 0.45 * amount, h12(id + 9.1 + floor(t * (0.6 + 0.4 * ph) + ph * 7.0)));
		r.x += ring * on; r.y += ring * on * sign(d - rad);
	}
	return r;
}
void vertex() { v_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 q = v_w.xz;
	float wet = clamp(wetness, 0.0, 1.0);
	float rn = clamp(rain, 0.0, 1.0);
	float dist = length(CAMERA_POSITION_WORLD - v_w);
	float near = 1.0 - smoothstep(14.0, 48.0, dist);
	float tone = fbm(q * 0.33);
	float speck = h12(floor(q * 55.0));
	vec3 asph = vec3(0.058, 0.062, 0.070) * (0.62 + 0.75 * tone) * (0.90 + 0.20 * speck);
	// lane paint: centre dashes and the kerb lines
	float cl = abs(q.x);
	float dash = step(fract(q.y / 6.0), 0.5);
	float paint = (1.0 - smoothstep(0.07, 0.12, abs(cl - 0.18))) * dash;
	paint += 1.0 - smoothstep(0.08, 0.13, abs(cl - 7.4));
	asph = mix(asph, vec3(0.50, 0.42, 0.18), paint * (0.30 + 0.35 * tone));
	// sidewalks (outside the kerb) are paler concrete
	float walk = smoothstep(8.0, 8.3, cl);
	asph = mix(asph, vec3(0.085, 0.088, 0.095) * (0.7 + 0.6 * tone), walk);
	float pud = smoothstep(0.52, 0.64, fbm(q * 0.11 + 3.0) + 0.12 * (fbm(q * 0.8) - 0.5));
	float gloss = clamp(wet * (0.40 + 0.60 * pud), 0.0, 1.0);
	vec2 rp = ripples(q, TIME, rn);
	vec2 jitter = (vec2(vn(q * 2.3 + TIME * 0.15), vn(q * 2.9 - TIME * 0.11)) - 0.5) * 0.010 * (1.0 - 0.6 * pud);
	vec2 off = jitter + vec2(rp.y * 0.010, rp.x * 0.004) * near * pud * rn * 3.0;
	float lod = (1.0 - gloss) * 3.2 + 0.4;
	vec3 mir = textureLod(screen_tex, SCREEN_UV + off, lod).rgb;
	mir += textureLod(screen_tex, SCREEN_UV + off + vec2(0.0, 0.010), lod + 0.5).rgb * 0.6;
	mir += textureLod(screen_tex, SCREEN_UV + off - vec2(0.0, 0.010), lod + 0.5).rgb * 0.6;
	mir /= 2.2;
	float f = 0.04 + 0.96 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	float k = clamp(gloss * (0.26 + 0.9 * f), 0.0, 0.88);
	ALBEDO = asph * (1.0 - k) * mix(1.0, 0.55, wet);
	ROUGHNESS = mix(0.90, 0.08, gloss);
	SPECULAR = 0.55;
	EMISSION = mir * k;
}
"""

const POSES := {
	&"street": [Vector3(0.9, 1.72, 11.0), Vector3(-0.4, 3.2, -40.0), 66.0],
	&"low": [Vector3(-1.2, 0.5, 8.0), Vector3(0.6, 1.4, -40.0), 62.0],
	&"hero": [Vector3(3.2, 1.55, -1.2), Vector3(0.9, 1.35, -9.0), 58.0],
	&"lamp": [Vector3(-3.0, 1.4, -10.0), Vector3(-8.0, 6.5, -21.0), 68.0],
	&"wide": [Vector3(0.0, 2.2, 14.0), Vector3(0.0, 6.0, -60.0), 76.0],
}

var root: Node3D
var camera: Camera3D
var environment: Environment
var moon: DirectionalLight3D
var _real: Node3D
var _mirror: Node3D
var _facade_shader: Shader
var _glow_tex: GradientTexture2D


func build(parent: Node) -> void:
	root = Node3D.new()
	root.name = "AtmosphereFixture"
	parent.add_child(root)
	_facade_shader = Shader.new()
	_facade_shader.code = FACADE_CODE
	_glow_tex = GradientTexture2D.new()
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex.width = 128
	_glow_tex.height = 128
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 0.18, 1.0])
	_glow_tex.gradient = g
	_build_environment()
	_real = Node3D.new()
	_real.name = "Real"
	root.add_child(_real)
	_mirror = Node3D.new()
	_mirror.name = "Mirror"
	_mirror.scale = Vector3(1, -1, 1)
	root.add_child(_mirror)
	_build_floor()
	_build_geometry(_real, false)
	_build_geometry(_mirror, true)
	_build_lights()
	_build_characters()
	camera = Camera3D.new()
	camera.name = "FixtureCamera"
	camera.far = 600.0
	camera.near = 0.08
	root.add_child(camera)
	camera.make_current()
	Game.camera = camera
	set_pose(&"street")


func set_pose(pose: StringName, blend := 0.0, pose_b: StringName = &"") -> void:
	var a: Array = POSES[pose]
	var pos: Vector3 = a[0]
	var look: Vector3 = a[1]
	var fov: float = a[2]
	if pose_b != &"" and blend > 0.0:
		var b: Array = POSES[pose_b]
		pos = pos.lerp(b[0], blend)
		look = look.lerp(b[1], blend)
		fov = lerpf(fov, b[2], blend)
	camera.fov = fov
	camera.global_position = pos
	camera.look_at(look, Vector3.UP)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.020, 0.040, 0.085)
	sky_mat.sky_horizon_color = Color(0.150, 0.240, 0.320)
	sky_mat.ground_horizon_color = Color(0.150, 0.240, 0.320)
	sky_mat.ground_bottom_color = Color(0.02, 0.03, 0.05)
	sky_mat.sky_energy_multiplier = 0.9
	var sky := Sky.new()
	sky.sky_material = sky_mat
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.3
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.glow_hdr_threshold = 0.9
	environment.glow_hdr_scale = 2.0
	environment.glow_hdr_luminance_cap = 12.0
	var levels := [0.35, 0.55, 0.8, 0.65, 0.4, 0.2, 0.0]
	for i in levels.size():
		environment.set_glow_level(i, levels[i])
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.20, 0.27, 0.34)
	environment.fog_density = 0.011
	environment.fog_aerial_perspective = 0.2
	environment.fog_sky_affect = 0.2
	var we := WorldEnvironment.new()
	we.environment = environment
	root.add_child(we)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.58, 0.72, 1.0)
	moon.light_energy = 0.55
	moon.shadow_enabled = false
	moon.transform = Transform3D(Basis.looking_at(-Vector3(-0.43, 0.46, -0.78).normalized(), Vector3.UP), Vector3.ZERO)
	root.add_child(moon)


func _build_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 180.0)
	var m := MeshInstance3D.new()
	m.name = "WetFloor"
	m.mesh = plane
	m.position = Vector3(0.0, 0.0, -70.0)
	var sh := Shader.new()
	sh.code = FLOOR_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _build_geometry(parent: Node3D, mirror: bool) -> void:
	var facade := ShaderMaterial.new()
	facade.shader = _facade_shader
	facade.set_shader_parameter(&"mirror_mode", 1.0 if mirror else 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260508
	# two rows of towers lining the street
	for side in [-1, 1]:
		var z := 12.0
		while z > -150.0:
			var depth := rng.randf_range(10.0, 24.0)
			var h := rng.randf_range(16.0, 62.0)
			var w := rng.randf_range(10.0, 16.0)
			_box(parent, Vector3(side * (9.0 + w * 0.5), h * 0.5, z - depth * 0.5), Vector3(w, h, depth), facade)
			z -= depth + rng.randf_range(0.0, 1.2)
	# neon: base strips along the facades (cyan left, magenta right), vertical blade signs, an amber shopfront band
	var cyan := _emissive(Color(0.12, 0.85, 1.0), 4.2)
	var magenta := _emissive(Color(1.0, 0.10, 0.58), 4.2)
	var amber := _emissive(Color(1.0, 0.58, 0.18), 3.2)
	var violet := _emissive(Color(0.55, 0.30, 1.0), 3.6)
	var green := _emissive(Color(0.2, 1.0, 0.62), 3.4)
	for i in 7:
		var zc := 2.0 - i * 21.0
		_box(parent, Vector3(-9.05, 0.35, zc), Vector3(0.12, 0.14, 15.0), cyan)
		_box(parent, Vector3(9.05, 0.35, zc - 4.0), Vector3(0.12, 0.14, 12.0), magenta)
		_box(parent, Vector3(-9.05, 3.4, zc - 3.0), Vector3(0.12, 0.10, 8.0), amber if i % 2 == 0 else violet)
	for i in 6:
		var zc2 := -3.0 - i * 24.0
		_box(parent, Vector3(-9.1, 7.5 + (i % 3) * 3.0, zc2), Vector3(0.14, 5.5, 0.55), cyan if i % 2 == 0 else green)
		_box(parent, Vector3(9.1, 8.5 - (i % 2) * 2.5, zc2 - 11.0), Vector3(0.14, 6.5, 0.6), magenta if i % 2 == 0 else violet)
	# the big sign at the end of the street
	_box(parent, Vector3(0.0, 11.0, -112.0), Vector3(16.0, 2.2, 0.3), magenta)
	_box(parent, Vector3(0.0, 7.6, -112.0), Vector3(16.0, 0.35, 0.3), cyan)
	# props (dark solids: in the mirror they are black silhouettes so they occlude the reflected neon)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.07, 0.075, 0.085)
	dark.roughness = 0.55
	dark.metallic = 0.4
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.06, 0.10, 0.08)
	olive.roughness = 0.5
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.20, 0.21, 0.22)
	concrete.roughness = 0.9
	if mirror:
		for mm: StandardMaterial3D in [dark, olive, concrete]:
			mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mm.albedo_color = Color(0.01, 0.01, 0.012)
	_box(parent, Vector3(2.4, 0.45, -14.0), Vector3(3.0, 0.9, 0.55), concrete)                # barriers
	_box(parent, Vector3(5.6, 0.45, -14.6), Vector3(3.0, 0.9, 0.55), concrete)
	_box(parent, Vector3(7.2, 0.65, -6.0), Vector3(2.2, 1.3, 1.2), olive)                     # dumpster
	_box(parent, Vector3(-7.4, 0.5, -30.0), Vector3(1.1, 1.0, 1.1), dark)                     # crates
	_box(parent, Vector3(-7.4, 1.4, -30.0), Vector3(0.8, 0.8, 0.8), dark)
	_box(parent, Vector3(-4.6, 0.7, -41.0), Vector3(1.9, 1.4, 4.4), dark)                     # parked vehicle block
	# lamp posts with bulbs
	var bulb_warm := _emissive(Color(1.0, 0.72, 0.38), 9.0)
	var bulb_cool := _emissive(Color(0.65, 0.88, 1.0), 9.0)
	for i in 7:
		var zl := -3.0 - i * 19.0
		for side in [-1, 1]:
			var x: float = side * 8.4
			_box(parent, Vector3(x, 3.6, zl), Vector3(0.14, 7.2, 0.14), dark)
			_box(parent, Vector3(x - side * 0.8, 7.15, zl), Vector3(1.7, 0.1, 0.1), dark)
			_box(parent, Vector3(x - side * 1.5, 7.05, zl), Vector3(0.5, 0.14, 0.3), bulb_warm if side < 0 else bulb_cool)
	if not mirror:
		for i in 7:
			var zl := -3.0 - i * 19.0
			for side in [-1, 1]:
				var glow := MeshInstance3D.new()
				var q := QuadMesh.new()
				q.size = Vector2(5.5, 5.5)
				glow.mesh = q
				var gm := StandardMaterial3D.new()
				gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
				gm.albedo_texture = _glow_tex
				gm.albedo_color = Color(1.0, 0.70, 0.38, 0.34) if side < 0 else Color(0.62, 0.84, 1.0, 0.30)
				gm.no_depth_test = false
				glow.material_override = gm
				glow.position = Vector3(side * 8.4 - side * 1.5, 7.0, zl)
				glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				parent.add_child(glow)


func _build_lights() -> void:
	for i in 7:
		var zl := -3.0 - i * 19.0
		for side in [-1, 1]:
			var l := OmniLight3D.new()
			l.position = Vector3(side * 8.4 - side * 1.5, 6.6, zl)
			l.light_color = Color(1.0, 0.70, 0.40) if side < 0 else Color(0.62, 0.84, 1.0)
			l.light_energy = 6.0
			l.omni_range = 15.0
			l.omni_attenuation = 1.4
			l.shadow_enabled = false
			root.add_child(l)
	# coloured spill from the neon strips onto the street
	var spill := [[Vector3(-8.0, 1.2, -6.0), Color(0.12, 0.85, 1.0)], [Vector3(8.0, 1.2, -16.0), Color(1.0, 0.10, 0.58)],
			[Vector3(-8.0, 1.2, -36.0), Color(0.55, 0.30, 1.0)], [Vector3(8.0, 1.2, -50.0), Color(1.0, 0.10, 0.58)]]
	for s: Array in spill:
		var l2 := OmniLight3D.new()
		l2.position = s[0]
		l2.light_color = s[1]
		l2.light_energy = 3.2
		l2.omni_range = 11.0
		l2.shadow_enabled = false
		root.add_child(l2)


func _build_characters() -> void:
	var op: Node3D = Game.load_model("operative")
	if op == null:
		var body := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.28
		cap.height = 1.8
		body.mesh = cap
		body.position = Vector3(0.0, 0.9, 0.0)
		op = Node3D.new()
		op.add_child(body)
	var key := OmniLight3D.new()                       # warm key from the street lamp side, cool rim from behind: a lit character, not a silhouette
	key.position = Vector3(3.4, 2.6, -6.4)
	key.light_color = Color(1.0, 0.72, 0.45)
	key.light_energy = 2.4
	key.omni_range = 7.0
	root.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0.4, 2.2, -12.2)
	rim.light_color = Color(0.35, 0.85, 1.0)
	rim.light_energy = 3.0
	rim.omni_range = 6.0
	root.add_child(rim)
	op.position = Vector3(1.4, 0.0, -9.0)
	op.rotation.y = PI * 0.92
	_real.add_child(op)
	var car: Node3D = Game.load_model("car_sport")
	if car != null:
		car.position = Vector3(-4.6, 0.0, -24.0)
		car.rotation.y = 0.06
		_real.add_child(car)
