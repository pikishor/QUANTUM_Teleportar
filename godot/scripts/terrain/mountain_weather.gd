class_name MountainWeather
extends Node3D
## The air of the mountains (wave 105): a CLOUD DECK, snow and thicker fog up on the ridges. Child of the City (MountainWeather.attach); everything is a function of where the camera is.
##  - the cloud deck: one flat disc (assets/shaders/cloud_layer.gdshader) at CLOUD_Y that follows the camera, alpha by the mountain weight and by how close the camera's height is to the deck:
##    from a ridge above it you look down on the clouds between the peaks, from the valley under it you see the underside; over the city and the sea it fades to nothing;
##  - snow: flurries of CPU particles around the camera above the SNOW_START altitude in the mountains (heavier with height, none in the city, none on the plains), lighter on LOW;
##  - fog: `fog_boost` (read by Weather._apply_env) thickens the haze inside the cloud band so a climb through the deck really is a climb through cloud.
## The snow LINE itself (white ground) is the terrain's own (TerrainBase.SNOW_LINE); trees and site roofs get their dusting from their shaders with the same heights.
##   MountainWeather.instance / fog_boost / altitude_factor(y)   cloud_alpha()   snow_rate()

const CLOUD_Y := 188.0
const BAND := 52.0                                    ## half thickness of the cloud band (the fog thickens inside it)
const SNOW_START := 150.0
const SNOW_FULL := 260.0

static var instance: MountainWeather = null
static var fog_boost := 0.0                            ## extra fog density (a multiple of the base): read by Weather

var quality := 1
var cloud_alpha := 0.0
var snow_rate := 0.0
var _mi: MeshInstance3D
var _mat: ShaderMaterial
var _snow: CPUParticles3D
var _drift := Vector2.ZERO
var _t := 0.0


static func attach(parent: Node) -> MountainWeather:
	var w := MountainWeather.new()
	w.name = "MountainWeather"
	parent.add_child(w)
	return w


func _ready() -> void:
	instance = self
	var pm := PlaneMesh.new()
	pm.size = Vector2(5200.0, 5200.0)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	_mi = MeshInstance3D.new()
	_mi.name = "CloudDeck"
	_mi.mesh = pm
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/cloud_layer.gdshader") as Shader
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mi.top_level = true
	_mi.custom_aabb = AABB(Vector3(-2700.0, -10.0, -2700.0), Vector3(5400.0, 20.0, 5400.0))
	_mi.visible = false
	add_child(_mi)
	set_process(true)


## The snow node exists only while it snows: a CPU particle node in the tree costs draws in the start view even when it is hidden (measured: +5 at LOW), so it is built on the first
## flurry and freed again when the snow has stopped.
func _make_snow() -> void:
	_snow = CPUParticles3D.new()
	_snow.name = "Snow"
	_snow.top_level = true
	_snow.amount = 240
	_snow.lifetime = 4.5
	_snow.local_coords = false
	_snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_snow.emission_box_extents = Vector3(22.0, 0.5, 22.0)
	_snow.direction = Vector3(0.25, -1.0, 0.1)
	_snow.spread = 8.0
	_snow.gravity = Vector3(0.6, -1.2, 0.3)
	_snow.initial_velocity_min = 1.0
	_snow.initial_velocity_max = 2.0
	_snow.scale_amount_min = 0.6
	_snow.scale_amount_max = 1.2
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	_snow.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	m.albedo_texture = FX._soft_texture()                     # round soft flakes, not flat squares
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_snow.material_override = m
	_snow.visibility_aabb = AABB(Vector3(-40.0, -30.0, -40.0), Vector3(80.0, 60.0, 80.0))
	_snow.emitting = true
	_snow.visible = true
	add_child(_snow)
	_snow.amount = [110, 190, 300][quality]


func _exit_tree() -> void:
	if instance == self:
		instance = null
	fog_boost = 0.0


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)
	if _snow != null:
		_snow.amount = [110, 190, 300][quality]


## 0..1 how mountainous the place is for the sky: the mountain weight, zero over the city.
static func mountain_factor(x: float, z: float) -> float:
	if TerrainHeight.city_distance(x, z) <= 40.0:
		return 0.0
	return TerrainHeight.mountain_weight(x, z) * smoothstep(300.0, 900.0, TerrainHeight.city_distance(x, z))


## 0..1 snowfall strength for a camera at height y (above the snow start, in the mountains).
static func snow_for(x: float, y: float, z: float) -> float:
	return mountain_factor(x, z) * smoothstep(SNOW_START, SNOW_FULL, y)


func _process(delta: float) -> void:
	_t += delta
	if _snow != null and Game.world is City and (Game.world as City).quality != quality:
		set_quality((Game.world as City).quality)
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return
	var cp := cam.global_position
	var mf := mountain_factor(cp.x, cp.z)
	var above := absf(cp.y - CLOUD_Y)
	cloud_alpha = mf * (1.0 - smoothstep(60.0, 170.0, above))
	snow_rate = snow_for(cp.x, cp.y, cp.z)
	fog_boost = 1.6 * mf * (1.0 - smoothstep(0.0, BAND, above))
	_drift += Vector2(7.0, 3.0) * delta
	_mi.visible = cloud_alpha > 0.01
	if _mi.visible:
		_mi.global_position = Vector3(cp.x, CLOUD_Y, cp.z)
		_mat.set_shader_parameter(&"fade", cloud_alpha)
		_mat.set_shader_parameter(&"drift", _drift)
	if snow_rate > 0.05 and _snow == null:
		_make_snow()
	elif snow_rate <= 0.02 and _snow != null:
		_snow.queue_free()
		_snow = null
	if _snow != null:
		_snow.visible = snow_rate > 0.05
		_snow.emitting = snow_rate > 0.05
	if _snow != null and _snow.emitting:
		_snow.global_position = cp + Vector3(0.0, 11.0, 0.0)
		_snow.speed_scale = 0.8 + snow_rate
