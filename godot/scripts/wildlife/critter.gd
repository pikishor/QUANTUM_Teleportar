class_name Critter
extends Node3D
## One animal of the wild (a pooled body, wave 107). The WildlifeWorld simulates it; this node only holds the model (skinned, one draw call), the clip player, the material (own
## copy: dissolve, colour variation, hurt flash) and the state the simulation keeps between frames. Faces -Z; `heading` is its yaw.

var id: StringName = &""
var spec: Dictionary = {}
var cls: StringName = AnimalSpecies.LAND
var state: StringName = &"idle"
var alive := true
var dying := false
var hp := 10.0
var timer := 0.0
var heading := 0.0
var speed := 0.0
var turn := 0.0                          ## air: signed turn rate, drives the bank
var target := Vector2.ZERO               ## xz goal
var group: Dictionary = {}               ## the herd / flock / school this body belongs to (shared by reference)
var slot := Vector2.ZERO                 ## personal offset inside the group
var ground := 0.0                        ## last sampled ground height under the feet
var water_y := TerrainHeight.NO_WATER    ## last sampled water surface (NO_WATER on dry land)
var pitch := 0.0
var bank := 0.0
var sample_t := 0.0
var phase := 0.0
var voice_t := 5.0
var prey: Critter = null
var cool := 0.0
var aggro := false
var stuck := 0.0
var dissolve := 0.0
var scale_k := 1.0
var think_t := 0.0
var bite_t := 0.0
var lod := 0                             ## 0 animated, 1 frozen pose (far), 2 hidden (very far)
var asleep := false
var clip: StringName = &""
var model: Node3D = null
var ap: AnimationPlayer = null
var mat: ShaderMaterial = null
var mesh: MeshInstance3D = null
var _idle_is_walk := false
var _flash := 0.0


func setup(species: StringName, sp: Dictionary) -> bool:
	id = species
	spec = sp
	cls = sp["cls"]
	mat = WildlifeKit.material()
	if species == &"lizard":
		mesh = MeshInstance3D.new()
		mesh.mesh = WildlifeKit.lizard_mesh()
		mesh.material_override = mat
		mesh.scale = Vector3.ONE * 1.35
		add_child(mesh)
		mat.set_shader_parameter(&"wiggle", 0.012)
		model = mesh
		return true
	var ps := WildlifeKit.scene(species)
	if ps == null:
		return false
	model = ps.instantiate() as Node3D
	add_child(model)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		mesh = n as MeshInstance3D
		mesh.material_override = mat
		mesh.extra_cull_margin = 1.5
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if not found.is_empty():
		ap = found[0] as AnimationPlayer
	return true


## Back to a fresh life (a pooled body is reused for any individual of its species).
func revive(rng: RandomNumberGenerator) -> void:
	alive = true
	dying = false
	state = &"idle"
	hp = float(spec["hp"])
	timer = rng.randf_range(0.5, 4.0)
	speed = 0.0
	turn = 0.0
	prey = null
	cool = 0.0
	aggro = false
	stuck = 0.0
	dissolve = 0.0
	asleep = false
	lod = 0
	bite_t = 0.0
	sample_t = 0.0
	think_t = rng.randf()
	voice_t = rng.randf_range(2.0, 12.0)
	_flash = 0.0
	var m: Array = spec["mul"]
	var v := rng.randf_range(float(m[0]), float(m[1]))
	scale_k = rng.randf_range(0.92, 1.08) * float(spec.get("vis", 1.45))      # a little bigger than life: a phone screen needs to read them at 40 m
	mat.set_shader_parameter(&"mul", Vector3(v, v * rng.randf_range(0.96, 1.04), v))
	mat.set_shader_parameter(&"dissolve", 0.0)
	mat.set_shader_parameter(&"pulse", 0.0)
	visible = true
	clip = &""
	if mesh != null:
		mesh.visible = true


## Plays a clip (falls back: run -> walk -> idle; a body without an idle clip holds the walk pose slowly). `spd` is the playback speed.
func play(want: StringName, spd := 1.0, blend := 0.25) -> void:
	if ap == null:
		return
	var name := want
	if not ap.has_animation(name):
		match want:
			&"run":
				name = &"walk" if ap.has_animation(&"walk") else &"idle"
			&"idle":
				name = &"walk" if ap.has_animation(&"walk") else (&"fly" if ap.has_animation(&"fly") else &"swim")
				spd *= 0.1
			&"walk":
				name = &"fly" if ap.has_animation(&"fly") else (&"swim" if ap.has_animation(&"swim") else &"idle")
			_:
				name = &"idle"
		if not ap.has_animation(name):
			return
	if name != clip:
		clip = name
		ap.play(name, blend)
		if lod == 0:
			ap.seek(randf() * ap.current_animation_length, true)
	ap.speed_scale = spd if lod == 0 else 0.0


func set_lod(l: int) -> void:
	if l == lod:
		return
	lod = l
	var show := l < 2
	if visible != show:
		visible = show
	if ap != null and l > 0:
		ap.speed_scale = 0.0


func set_dissolve(v: float) -> void:
	if absf(v - dissolve) > 0.004 or v == 0.0:
		dissolve = v
		mat.set_shader_parameter(&"dissolve", v)


func flash() -> void:
	_flash = 1.0
	mat.set_shader_parameter(&"pulse", 1.0)


func tick_visual(dt: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 4.0)
		mat.set_shader_parameter(&"pulse", _flash)


## Writes heading, pitch and bank (and the sleeping squash) into the node's transform.
func apply_pose() -> void:
	var b := Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, bank)
	var sy := scale_k * (0.74 if asleep else 1.0)
	basis = b * Basis.from_scale(Vector3(scale_k, sy, scale_k))
