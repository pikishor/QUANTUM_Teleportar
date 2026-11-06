extends Node3D
## Spent shell casings: tumbling brass that pops out of the ejection port, bounces once or twice on the ground and fades. ONE MultiMesh, ONE draw call, and only while at least one
## casing is alive (the node hides itself otherwise). Pooled: CAP casings, nothing is allocated while the game runs. LOW+ ejects none (no particles at half rate there).
## FX.casings.eject(pos, velocity) from PlayerWeapon._eject_shell; the ground is the hero's feet level (street level), good enough for a 1.5 s flight.

const CAP := 14
const LIFE := 1.6
const GRAVITY := 16.0
const SIZE := Vector3(0.085, 0.03, 0.03)            ## a brass box, stylised big enough to read from the shoulder camera
const BRASS := Color(1.0, 0.72, 0.28)

var mm: MultiMesh
var live := 0                                          ## casings in flight (tests)
var ejected := 0                                       ## lifetime count (tests)
var _mmi: MultiMeshInstance3D
var _p := PackedVector3Array()
var _v := PackedVector3Array()
var _rot := PackedVector3Array()                       ## euler angles
var _spin := PackedVector3Array()
var _age := PackedFloat32Array()
var _floor_y := PackedFloat32Array()
var _bounces := PackedByteArray()


func _ready() -> void:
	name = "Casings"
	top_level = true
	global_transform = Transform3D.IDENTITY
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = SIZE
	mm.mesh = box
	mm.instance_count = CAP
	mm.visible_instance_count = 0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BRASS
	mat.metallic = 0.9
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = BRASS
	mat.emission_energy_multiplier = 0.55                # a glint even at night
	box.material = mat
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.extra_cull_margin = 50.0
	_mmi.visible = false
	add_child(_mmi)
	for a: PackedVector3Array in [_p, _v, _rot, _spin]:
		a.resize(CAP)
	_age.resize(CAP)
	_floor_y.resize(CAP)
	_bounces.resize(CAP)


func clear() -> void:
	live = 0
	mm.visible_instance_count = 0
	_mmi.visible = false


## A casing leaves `pos` with velocity `vel` (m/s); `floor_y` is the ground it will land on.
func eject(pos: Vector3, vel: Vector3, floor_y := 0.0) -> void:
	if Game.low_plus or live >= CAP:
		return
	var i := live
	live += 1
	ejected += 1
	_p[i] = pos
	_v[i] = vel
	_rot[i] = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_spin[i] = Vector3(randf_range(-22.0, 22.0), randf_range(-22.0, 22.0), randf_range(-22.0, 22.0))
	_age[i] = 0.0
	_floor_y[i] = floor_y + SIZE.y
	_bounces[i] = 0
	mm.visible_instance_count = live
	_mmi.visible = true


func _process(delta: float) -> void:
	if live == 0:
		return
	delta = minf(delta, 0.05)
	var i := 0
	while i < live:
		_age[i] += delta
		if _age[i] >= LIFE:
			live -= 1                                    # swap the last one in
			_p[i] = _p[live]
			_v[i] = _v[live]
			_rot[i] = _rot[live]
			_spin[i] = _spin[live]
			_age[i] = _age[live]
			_floor_y[i] = _floor_y[live]
			_bounces[i] = _bounces[live]
			continue
		var v := _v[i]
		v.y -= GRAVITY * delta
		var p := _p[i] + v * delta
		if p.y < _floor_y[i]:
			p.y = _floor_y[i]
			if _bounces[i] < 2 and absf(v.y) > 0.8:
				v.y = -v.y * 0.35
				v.x *= 0.55
				v.z *= 0.55
				_spin[i] *= 0.5
				_bounces[i] += 1
			else:
				v = Vector3.ZERO
				_spin[i] = Vector3.ZERO
		_v[i] = v
		_p[i] = p
		_rot[i] += _spin[i] * delta
		var fade := clampf((LIFE - _age[i]) / 0.4, 0.0, 1.0)         # shrinks away at the end
		var b := Basis.from_euler(_rot[i]).scaled(Vector3.ONE * fade)
		mm.set_instance_transform(i, Transform3D(b, p))
		i += 1
	mm.visible_instance_count = live
	_mmi.visible = live > 0
