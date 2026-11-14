class_name WeaponHandling
extends RefCounted
## Part motion of the weapon in the hero's hand (wave 114): the kit's models are ONE mesh, every vertex carries the id of the part it belongs to (slide, magazine, pump, hammer, rotor, lever, pulse) and the
## hero's own copy of the PBR material moves the parts through uniforms: no extra draw call. This class turns the shots and the reload into those uniforms:
##   semi-auto slides / bolt carriers kick back on every shot and stay back on an empty gun (pistol, SMG, rifle, LMG, shotgun), bolt actions cycle the handle after the shot, pump guns pump,
##   revolvers turn the cylinder one chamber and fall the hammer, rotary guns spin up while the trigger is held and run down, energy weapons pulse the coils, a magazine slides out and a new one comes
##   back during a reload (reload progress 0..1 from the rig).
## One instance per PlayerBody; `setup` on every weapon switch, `fired` on every shot, `update` every frame.

const TRAVEL := {&"pistol": 0.026, &"smg": 0.03, &"rifle": 0.04, &"shotgun": 0.034, &"lmg": 0.034, &"sniper": 0.045, &"launcher": 0.03}

var id: StringName = &""
var _mat: ShaderMaterial
var _meta: Dictionary = {}
var _profile := &"none"
var _slide := 0.0
var _slide_hold := false
var _cycle := -1.0                      ## a bolt / pump cycle in progress, 0..1, -1 none
var _cycle_wait := 0.0                  ## delay before the cycle starts
var _rotor := 0.0
var _rotor_w := 0.0
var _rotor_target := 0.0
var _hammer := 0.0
var _pulse := 0.0
var _mag_out := 0.0
var _fire_t := 0.0
var _cls: StringName = &"rifle"
var shots := 0                          ## lifetime shots seen (tests)


## Bind to the material of the weapon in the hand (a ShaderMaterial of the kit) and read its parts from the meta file.
func setup(mat: Material, weapon_id: StringName) -> void:
	id = weapon_id
	_mat = mat as ShaderMaterial
	_meta = WeaponModels.kit_meta().get(String(id), {})
	_slide = 0.0
	_cycle = -1.0
	_rotor = 0.0
	_rotor_w = 0.0
	_hammer = 0.0
	_pulse = 0.0
	_mag_out = 0.0
	_slide_hold = false
	_profile = &"none"
	if _mat == null or not _meta.has("parts"):
		return
	var parts: Array = _meta["parts"]
	var fn := String(_meta.get("fn", ""))
	var rec := String(_meta.get("rec", ""))
	var kind := String(_meta.get("kind", ""))
	_cls = StringName(WeaponDefs.class_of(id))
	if parts.has("rotor"):
		_profile = &"rotary" if (fn == "rotary" or kind == "rotary") else &"revolver"
	elif parts.has("pump"):
		_profile = &"pump"
	elif rec == "bolt" and parts.has("slide"):
		_profile = &"bolt"
	elif parts.has("slide"):
		_profile = &"slide"
	elif parts.has("pulse"):
		_profile = &"pulse"
	for k in ["rotor", "hinge"]:
		if _meta.has(k):
			var a: Array = _meta[k]
			_mat.set_shader_parameter(&"rotor_center" if k == "rotor" else &"hammer_hinge", Vector3(a[0], a[1], a[2]))
	_apply()


## One shot: the slide kicks, the pump / bolt cycle is queued, the cylinder turns, the coils pulse.
func fired() -> void:
	shots += 1
	_fire_t = 0.16
	match _profile:
		&"slide":
			_slide = 1.0
		&"bolt":
			_cycle_wait = 0.32
			_cycle = 0.0
		&"pump":
			_cycle_wait = 0.2
			_cycle = 0.0
		&"revolver":
			_rotor += deg_to_rad(60.0)
			_hammer = 1.0
		&"rotary":
			_rotor_target = 38.0
		&"pulse":
			_pulse = 2.4
	if _meta.get("parts", []).has("pulse"):
		_pulse = 2.4


## Every frame: dt, reload progress (-1 none, 0..1), rounds left in the magazine.
func update(dt: float, reload_k: float, ammo: int) -> void:
	if _mat == null or _profile == &"none" and _mag_out <= 0.0 and reload_k < 0.0 and _pulse <= 0.0:
		return
	_fire_t = maxf(0.0, _fire_t - dt)
	match _profile:
		&"slide":
			_slide_hold = ammo <= 0 and reload_k < 0.0 and String(_cls) != "melee"
			_slide = maxf(_slide - dt / 0.075, 1.0 if _slide_hold else 0.0) if not _slide_hold else 1.0
		&"bolt":
			if _cycle >= 0.0:
				if _cycle_wait > 0.0:
					_cycle_wait -= dt
				else:
					_cycle += dt / 0.6
					if _cycle >= 1.0:
						_cycle = -1.0
			_slide = 0.0 if _cycle < 0.0 else sin(clampf(_cycle, 0.0, 1.0) * PI)
		&"pump":
			if _cycle >= 0.0:
				if _cycle_wait > 0.0:
					_cycle_wait -= dt
				else:
					_cycle += dt / 0.5
					if _cycle >= 1.0:
						_cycle = -1.0
			_slide = 0.0 if _cycle < 0.0 else sin(clampf(_cycle, 0.0, 1.0) * PI)
		&"revolver":
			_hammer = maxf(0.0, _hammer - dt / 0.12)
		&"rotary":
			_rotor_target = 38.0 if _fire_t > 0.0 else 0.0
			_rotor_w = move_toward(_rotor_w, _rotor_target, dt * (60.0 if _rotor_target > _rotor_w else 22.0))
			_rotor += _rotor_w * dt
	_pulse = maxf(0.0, _pulse - dt * 5.0)
	# the magazine: out and down in the first third of a reload, away while the hand fetches a new one, back up before the end
	if reload_k >= 0.0:
		if reload_k < 0.3:
			_mag_out = smoothstep(0.0, 0.3, reload_k)
		elif reload_k < 0.62:
			_mag_out = 2.0
		elif reload_k < 0.86:
			_mag_out = 1.0 - smoothstep(0.62, 0.86, reload_k)
		else:
			_mag_out = 0.0
	else:
		_mag_out = 0.0
	_apply()


func _apply() -> void:
	if _mat == null:
		return
	var travel := float(TRAVEL.get(_cls, 0.035))
	match _profile:
		&"slide":
			_mat.set_shader_parameter(&"anim_slide", Vector3(0.0, 0.0, travel * _slide))
		&"bolt":
			_mat.set_shader_parameter(&"anim_slide", Vector3(0.0, 0.0, 0.06 * _slide))
		&"pump":
			_mat.set_shader_parameter(&"anim_pump", Vector3(0.0, 0.0, 0.085 * _slide))
			_mat.set_shader_parameter(&"anim_slide", Vector3(0.0, 0.0, 0.03 * _slide))
		&"revolver":
			_mat.set_shader_parameter(&"rotor_angle", _rotor)
			_mat.set_shader_parameter(&"hammer_angle", -0.55 * _hammer)
		&"rotary":
			_mat.set_shader_parameter(&"rotor_angle", _rotor)
	var out := clampf(_mag_out, 0.0, 1.0)
	_mat.set_shader_parameter(&"anim_mag", Vector3(0.0, -0.16 * out, 0.012 * out))
	_mat.set_shader_parameter(&"hide_mag", 1.0 if _mag_out > 1.0 else 0.0)
	_mat.set_shader_parameter(&"pulse", _pulse)
