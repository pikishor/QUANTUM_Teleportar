extends RefCounted
## The ground of the city: one big analytic-shader plane (roads, kerbs, sidewalks, plazas) plus the two tiny data textures it
## samples: the lot map (which lots hold a building) and the light map (baked lamp and neon pools, HDR, 2 m per texel).

const GROUND_SHADER := preload("res://assets/shaders/ground.gdshader")

const LIGHT_SIZE := 704.0            ## metres covered by the light map (centred on the city)
const LIGHT_TEXELS := 352            ## 2 m per texel

var material: ShaderMaterial
var light_texture: ImageTexture
var lot_texture: ImageTexture
var _light := PackedFloat32Array()


func make_lot_map(layout: CityLayout) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	for p in layout.plazas:
		var i := int(floor((p.x + CityLayout.HALF) / CityLayout.PITCH))
		var j := int(floor((p.y + CityLayout.HALF) / CityLayout.PITCH))
		var cx := 1 if (p.x - (-CityLayout.HALF + (i + 0.5) * CityLayout.PITCH)) > 0.0 else 0
		var cz := 1 if (p.y - (-CityLayout.HALF + (j + 0.5) * CityLayout.PITCH)) > 0.0 else 0
		img.set_pixel(i * 2 + cx, j * 2 + cz, Color(0, 0, 0, 1))
	lot_texture = ImageTexture.create_from_image(img)
	return lot_texture


## Start a fresh light map (all black).
func begin_light_map() -> void:
	_light = PackedFloat32Array()
	_light.resize(LIGHT_TEXELS * LIGHT_TEXELS * 4)


## Add a soft round pool of light (linear RGB, already scaled by intensity) at world (x, z).
func add_pool(x: float, z: float, radius: float, color: Color, intensity: float) -> void:
	var inv := float(LIGHT_TEXELS) / LIGHT_SIZE
	var cx := (x + LIGHT_SIZE * 0.5) * inv
	var cz := (z + LIGHT_SIZE * 0.5) * inv
	var rt := radius * inv
	var x0 := maxi(0, int(floor(cx - rt)))
	var x1 := mini(LIGHT_TEXELS - 1, int(ceil(cx + rt)))
	var z0 := maxi(0, int(floor(cz - rt)))
	var z1 := mini(LIGHT_TEXELS - 1, int(ceil(cz + rt)))
	for tz in range(z0, z1 + 1):
		for tx in range(x0, x1 + 1):
			var dx := (float(tx) + 0.5 - cx) / rt
			var dz := (float(tz) + 0.5 - cz) / rt
			var d2 := dx * dx + dz * dz
			if d2 >= 1.0:
				continue
			var f := 1.0 - d2
			f = f * f / (1.0 + 5.0 * d2)          # soft core, long tail, windowed to zero at the radius
			var o := (tz * LIGHT_TEXELS + tx) * 4
			_light[o] += color.r * intensity * f
			_light[o + 1] += color.g * intensity * f
			_light[o + 2] += color.b * intensity * f


## A glowing line segment (neon strip along a facade foot, shop front spill): pools stamped along it.
func add_strip(a: Vector2, b: Vector2, radius: float, color: Color, intensity: float) -> void:
	var len := a.distance_to(b)
	var n := maxi(1, int(ceil(len / (radius * 0.6))))
	for k in n + 1:
		var p := a.lerp(b, float(k) / float(n))
		add_pool(p.x, p.y, radius, color, intensity * (1.0 / (1.0 + float(n) * 0.18)))


func finish_light_map() -> ImageTexture:
	var img := Image.create_from_data(LIGHT_TEXELS, LIGHT_TEXELS, false, Image.FORMAT_RGBAF, _light.to_byte_array())
	img.convert(Image.FORMAT_RGBAH)
	light_texture = ImageTexture.create_from_image(img)
	_light = PackedFloat32Array()
	return light_texture


func make_material() -> ShaderMaterial:
	material = ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.render_priority = -100          # blended ground first among transparents (mirrored glows draw before it)
	material.set_shader_parameter(&"lot_map", lot_texture)
	material.set_shader_parameter(&"light_map", light_texture)
	material.set_shader_parameter(&"light_rect", Vector4(-LIGHT_SIZE * 0.5, -LIGHT_SIZE * 0.5, LIGHT_SIZE, LIGHT_SIZE))
	return material


func make_node(size := 6000.0) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi
