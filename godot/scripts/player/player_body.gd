class_name PlayerBody
extends Node3D
## The player's visible body. Uses Game.load_model("player"), an articulated skinned model (one mesh, one draw call; bones Hips, Torso, Head, UpperArmL/R,
## ForeArmL/R, Rifle, ThighL/R, ShinL/R, FootL/R) that CharacterRig poses procedurally: idle breathing, walk / run / strafe / backpedal cycles with knee and
## elbow bends and a pelvis that follows the lowest foot, torso counter-rotation, both gloves on the rifle (IK) in the aim pose, the head following the aim
## pitch, recoil kick, reload motion, hit flinch and a limp pose when dead. When the model is missing it falls back to a humanoid built from capsules and
## boxes (rigid legs, no articulation). Both variants expose the same parts:
##   upper   the node that carries the torso, arms and rifle (the model root, or the hip pivot of the primitive body)
##   leg_l / leg_r   hip-pivot nodes holding the thigh swing (x forward, z sideways); the primitive's legs hang from them, the model's thigh bones are posed by the rig and these nodes mirror that angle
##   muzzle  the rifle tip (follows the rifle bone): tracers and the muzzle flash start here
##   rig     the CharacterRig of the model (null for the primitive body)
## The node is top_level and placed every rendered frame from the interpolated physics position, so it never judders
## when the display refresh rate and the physics tick rate differ.
## A pause freezes the pose where it is; a dead body does not run (its legs relax while it falls), and the fallen body is laid on the floor using the
## convex hulls of its parts, so no limb is buried in the ground and nothing floats.

const HIP_Y := 0.93
const LEG_AMP := 0.62                ## radians of hip swing at run speed
const STRIDE_RATE := 1.6             ## leg phase per metre travelled (src/player.js)
const FLASH_TIME := 0.055
const LIGHT_TIME := 0.075
const LIGHT_ENERGY := 3.4
const LIGHT_COUNT := 2
## The imported fabric is vertex-coloured almost black (albedo about 0.04); at night it vanishes into wet asphalt. Per-instance material overrides lift it
## (the imported resources stay untouched): an albedo multiplier plus a faint cool emission that acts as a silhouette floor.
const FABRIC_LIFT := 2.6
const FABRIC_EMISSION := Color(0.035, 0.075, 0.095)
## The baked "Gear" atlas of the articulated model is already built around albedo 0.10 and up, so its lift is much smaller.
const GEAR_LIFT := 2.1                     ## the baked atlas keeps its own albedo variation (a bigger lift washed the plates out to one flat cyan)
const GEAR_RIM := 0.22                     ## a subtle always-on cool fresnel edge; it swells (RIM_BOOST) only on a hit, while aiming and while the quantum powers are active
const RIM_BOOST := 0.85                    ## extra rim at full excitement
const GLOW_BOOST := 0.7                    ## extra emission-texture energy (veins, core, slit) at full excitement
const LOW_ALBEDO := Color(0.72, 0.74, 0.78, 1.0)    ## LOW tier: the armour albedo is multiplied by this ...
const COMPAT_GLOW := 0.55                           ## the Compatibility renderer (exposure and bloom lift) shows the emission texture much brighter: whitish plates on a bright phone
const LOW_GLOW := 0.6                                ## ... and the emission texture (veins, core, slit) is this strong
const FABRIC_RIM := 0.3                    ## cloak and legs get a cool edge too: a thicker, readable silhouette from the chase camera
const TRIM_HUES := [Color(0.2, 0.95, 1.0), Color(0.75, 0.35, 1.0), Color(1.0, 0.35, 0.85)]   ## thin-film sheen of the armour trim: cyan to violet to magenta
const GEAR_EMISSION := Color(0.012, 0.026, 0.034)   ## a faint silhouette floor only; the glow comes from the emission texture
## The Compatibility (OpenGL) renderer lights the same scene much brighter than the Mobile renderer the boosts were tuned on: scale them down there.
## Its world environment also carries a flat teal ambient (the sky radiance map does not exist there), which fills every shadow of a standard material and
## turned the hero into pale-blue plastic: the hero's materials ignore ambient light on that renderer (the key and rim lights model him instead).
const COMPAT_BOOST := 0.22
const COMPAT_LIGHT := 0.4
## ... and its albedo is tinted down on that renderer, where the moon (no shadows reach the hero there), the exposure lift and the blue key and rim lights would
## still wash him out and turn him cold blue. Calibrated on the title view: his mean luminance and hue then match the Mobile renderer's (0.09 vs 0.084).
const COMPAT_TINT := Color(0.95, 0.74, 0.55)
## Visual layer (1..20) reserved for the player's meshes, so the two character lights (a soft key and a rim) light only the hero and never the world.
const CHARACTER_LAYER := 20
# the death pose: the body falls onto its left side (the rifle rides on the right, so it ends up on top, not under the body), the legs go slack
const FALL_TIME := 0.8
const DEAD_ROLL := PI * 0.5
const DEAD_TWIST := 0.2                ## lean of the lying body about its long axis (positive: chest toward the sky)
const DEAD_SLEW := 0.35                ## the body also turns a little as it goes down
const DEAD_SHIFT := 0.7                ## metres sideways, so the fallen body ends up around where the player stood, not beside it
const DEAD_CURL := 0.22                ## the torso bends a little against the legs
const DEAD_LEG_L := Vector3(0.45, 0.0, -0.17)
const DEAD_LEG_R := Vector3(-0.3, 0.0, -0.09)
const DEAD_REST_GAP := 0.012           ## the lowest point of the corpse floats this far above the floor (no z-fighting with the asphalt)
const DEAD_SETTLE := 0.6               ## seconds after the fall during which the resting height is still recomputed
const DEAD_LIGHT := 0.5                ## the hero lighting (key and rim) of a dead body: this fraction is left, so a corpse does not glow

## Tests flip this to exercise the primitive fallback.
static var force_primitive := false
## The superhero (HeroCharacter: Quaternius base character, male / female, skin, hair, beard from HeroLook) replaces the old skinned hero whenever its files are imported; tests flip this off.
static var use_superhero := true
const SUPERHERO_STEP := 1.15
const SUPERHERO_TURN := 0.2

static var _flash_star_tex: ImageTexture
static var _flash_streak_tex: ImageTexture
static var _flash_mat_star: StandardMaterial3D
static var _flash_mat_streak: StandardMaterial3D

var muzzle: Node3D
var _wp_mi: MeshInstance3D
var _wp_mat: StandardMaterial3D
var leg_l: Node3D
var leg_r: Node3D
var upper: Node3D
var rig: CharacterRig
var uses_model := false
var hero_mat: ShaderMaterial                    ## the superhero's material (hero_body.gdshader); null with the old hero
var hero_info := {}                             ## HeroCharacter.build info of the current model (tris, lods, ...)
var _hero_opts := {}                            ## body / skin / hair / beard the current superhero was built with
var _weapon_id: StringName = &""
var _pending_look: HeroLook                  ## the look a rebuild is made for (so the new model gets it before Progress knows)

var _phase := 0.0
var _amp := 0.0
var _air := 0.0
var _sprint := 0.0
var _aim_pitch := 0.0
var _dir := Vector2(0.0, -1.0)        ## smoothed local movement direction (x right, y back)
var _recoil_push := 0.0
var _recoil_pitch := 0.0
var _kick := 0.0                      ## 0..1, one shot's recoil in the model's rifle
var _flinch := 0.0                    ## 0..1, a hit's snap of the torso and head
var _since_fire := 99.0
var _ready_w := 0.75                  ## weapon raised: 1 aiming / just fired / reloading, 0.75 relaxed, sprint handled by _sprint
var _rest_y := 0.0
var _clock := 0.0
var _dead_t := -1.0
var _flash_root: Node3D
var _flash_t := 0.0
var _lights: Array[OmniLight3D] = []
var _light_t := PackedFloat32Array()
var _li := 0
var _key_light: DirectionalLight3D
var _rim_light: DirectionalLight3D
var _gear_mats: Array[BaseMaterial3D] = []   ## the Gear override materials (rim and glow follow `_excite`)
var _gear_base: Array[Color] = []             ## the albedo each Gear override material was made with (the LOW tier darkens it a little)
var _gear_rim := 0.0
var _gear_emis: Array[Color] = []             ## the base emission colour of each Gear material (the trim tint blends toward the sheen)
var _fabric_mats: Array[BaseMaterial3D] = []
var _look_gear0: Array[Color] = []            ## G2: the albedo of each Gear / Fabric material before the hero look (apply_look multiplies it)
var _look_fab0: Array[Color] = []
var _look_emis0: Array[Color] = []
var _look_metal0: Array[float] = []
var _look_rough0: Array[float] = []
var _look_accent := Color.WHITE
var _look_mix := 0.0                           ## how far the trim sheen is pulled toward the look's accent
var _clock_look := 0.0
var _charge := 0.0                    ## 0..1 QUANTUM TELEPORT charge (aiming a destination), smoothed
var _ready_k := 1.0                   ## 0..1 how recharged the powers are (cooldown dims the seams)
var _verb_roll := 0.0                ## wall-run roll / glide and slam lean from HeroVerbs, eased
var _verb_pitch := 0.0
var _excite := 0.0                    ## 0..1: hit, aim or quantum-active moment (what the rim and glow react to)
var _excite_applied := -1.0
var _key_energy := 1.0
var _rim_energy := 1.0
var _burst: CPUParticles3D                    ## quantum motes on a hit and on death (HeroPresentation)
var _quality := 2
var loco: Locomotion                      ## foot planting, pelvis, weight shifts, cloak springs (the model's gait; see locomotion.gd)
var _last_pos := Vector3.ZERO
var _have_last := false
var _fdir := Vector2.ZERO                  ## where the last hit came from, body space (x right, y forward)
var _reflection: MirrorProxy              ## the hero's reflection on the wet street (the world's mirror pass; nothing without a world)
var _parts: Array[MeshInstance3D] = []   ## the character's meshes and the convex hull of each (points in the mesh's own space), for the corpse resting height
var _hulls: Array = []
var _rest_drop := 0.0                  ## lowest point of the fallen pose relative to the body's origin
## 0 opaque .. 1 hidden: the camera rig fades the hero out when the lens is closer than 1.2 m (a wall at the back). Per-instance transparency (dithered, Mobile renderer),
## and the meshes are hidden outright when nearly gone and on the Compatibility renderer, which has no instance transparency.
var fade := 0.0
func set_fade(f: float) -> void:
	if is_equal_approx(f, fade):
		return
	fade = f
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var gone := f >= (0.5 if compat else 0.96)
	for m: MeshInstance3D in _parts:
		if is_instance_valid(m):
			m.transparency = 0.0 if compat else clampf(f, 0.0, 0.96)
			m.visible = not gone
	if is_instance_valid(_wp_mi):
		_wp_mi.transparency = 0.0 if compat else clampf(f, 0.0, 0.96)       # its visibility belongs to the weapon switch (see set_weapon_look)


## Switch the character lights off (tests, or a graphics tier that wants the extra directional lights gone).
var character_light := true:
	set(v):
		character_light = v
		_apply_lights()


func _ready() -> void:
	top_level = true
	_build()


# ---------------------------------------------------------------------------------------------------------------------
# per-frame animation
# ---------------------------------------------------------------------------------------------------------------------

## Place the body at the interpolated world position and pose it from the player's state. Called by Player._process.
func update_view(p: Player, dt: float, view_pos: Vector3, yaw: float) -> void:
	var state := Game.state
	var adt := 0.0 if state == &"paused" else dt          # a pause freezes the pose; the flash and light timers at the end run on real time
	var dying := _dead_t >= 0.0
	_clock += adt
	var e := 0.0                                          # weight of the death pose, 0 standing .. 1 lying
	if dying:
		_dead_t += adt
		e = _fall_curve(clampf(_dead_t / FALL_TIME, 0.0, 1.0))
	var v := Vector3.ZERO if dying else p.velocity        # a dead body only slides along: its legs do not run
	var hv := Vector3(v.x, 0.0, v.z)
	var speed := hv.length()
	var grounded := p.air_time < 0.14 or dying           # rolling off a curb is not a jump
	var local := hv.rotated(Vector3.UP, -yaw)            # body space: x right, z back

	# --- legs: swing about the axis perpendicular to the movement direction
	var target_amp := minf(1.0, speed / 5.0) * LEG_AMP if grounded else 0.0
	_amp = PlayerUtil.damp(_amp, target_amp, 14.0, adt)
	_air = PlayerUtil.damp(_air, 0.0 if grounded else 1.0, 12.0, adt)
	if speed > 0.4:
		var td := Vector2(local.x, local.z) / speed
		_dir += (td - _dir) * (1.0 - exp(-16.0 * adt))
		if _dir.length_squared() < 0.0004:
			_dir = td
	_phase += adt * speed * STRIDE_RATE
	var m := Vector3(_dir.x, 0.0, _dir.y).normalized()
	var fw := -m.z                                       # +1 moving forward, -1 backing up
	var lw := m.x                                        # +1 moving right, -1 moving left
	var sl := sin(_phase) * _amp
	# forward / back swing about X (positive = foot forward); sideways swing about Z with a splay that keeps the feet apart while strafing
	var ax_l := lerpf(sl * fw, 0.42, _air)
	var ax_r := lerpf(-sl * fw, -0.3, _air)
	var az_l := -0.2 * absf(lw) + 0.5 * sl * lw
	var az_r := 0.2 * absf(lw) - 0.5 * sl * lw
	if e > 0.0:                                          # slack legs of the fallen body
		ax_l = lerpf(ax_l, DEAD_LEG_L.x, e)
		az_l = lerpf(az_l, DEAD_LEG_L.z, e)
		ax_r = lerpf(ax_r, DEAD_LEG_R.x, e)
		az_r = lerpf(az_r, DEAD_LEG_R.z, e)
	if leg_l != null:
		leg_l.basis = Basis.from_euler(Vector3(ax_l, 0.0, az_l))
	if leg_r != null:
		leg_r.basis = Basis.from_euler(Vector3(ax_r, 0.0, az_r))

	# --- torso: aim pitch, sprint lean, strafe roll, run twist, breathing, recoil
	var rig_view := p.camera_rig
	var look_pitch := 0.0 if dying else (rig_view.pitch + rig_view.recoil_pitch if rig_view != null else 0.0)
	_aim_pitch = PlayerUtil.damp(_aim_pitch, clampf(look_pitch * 0.6, -0.55, 0.65), 18.0, adt)
	_sprint = PlayerUtil.damp(_sprint, 1.0 if (p.sprinting and not dying) else 0.0, 9.0, adt)
	_recoil_push = PlayerUtil.damp(_recoil_push, 0.0, 17.0, adt)
	_recoil_pitch = PlayerUtil.damp(_recoil_pitch, 0.0, 13.0, adt)
	_kick = PlayerUtil.damp(_kick, 0.0, 12.0, adt)
	_flinch = PlayerUtil.damp(_flinch, 0.0, 7.0, adt)
	_since_fire += adt
	var reload_k := -1.0
	if not dying and p.weapon != null and p.reloading:
		reload_k = clampf(1.0 - p.weapon.reload_t / maxf(p.weapon.reload_total, 0.1), 0.0, 1.0)
	elif not dying and p.weapon != null and p.weapon.swap_t > 0.0:
		reload_k = clampf(1.0 - p.weapon.swap_t / PlayerWeapon.SWAP_TIME, 0.0, 1.0)         # the quick weapon swap: the rifle drops and comes back up (the reload pose)
	elif not dying and p.weapon != null and p.weapon.inspect_t > 0.0:
		reload_k = clampf(1.0 - p.weapon.inspect_t / PlayerWeapon.INSPECT_TIME, 0.0, 1.0)      # idle inspect: the same hand-over-rifle motion, no ammo change
	var want_ready := 1.0 if (p.aiming or _since_fire < 2.5 or reload_k >= 0.0) else 0.75
	_ready_w = PlayerUtil.damp(_ready_w, want_ready, 8.0, adt)
	var lean := -(0.10 * _sprint + 0.03 * minf(1.0, speed / 6.2))
	var roll := -local.x * 0.011
	var twist := sin(_phase) * 0.055 * (_amp / LEG_AMP)
	var calm := 1.0 - minf(1.0, speed / 2.0)
	var breathe := sin(_clock * 2.1) * 0.006 * calm
	var bob := -absf(sin(_phase)) * 0.016 * (_amp / LEG_AMP)
	if rig != null:
		var disp := Vector3.ZERO
		if _have_last and not dying and adt > 0.0:
			disp = Vector3(view_pos.x - _last_pos.x, 0.0, view_pos.z - _last_pos.z)
		_last_pos = view_pos
		_have_last = true
		if not dying and adt > 0.0:
			var air_flag := p.air_time > 0.14 or (p.air_time > 0.0 and p.velocity.y > 2.0)
			var aim_off := angle_difference(yaw, rig_view.get_aim_yaw()) if rig_view != null else 0.0
			loco.update(adt, disp, yaw, not air_flag, p.velocity.y, p.input_move.length(), p.sprinting, p.aiming, aim_off)
		rig.aim_pitch = _aim_pitch
		rig.recoil = _kick
		rig.flinch = _flinch
		rig.flinch_dir = _fdir * minf(1.0, _flinch * 3.0)
		rig.ready = _ready_w
		rig.reload = reload_k
		rig.reload_tilt = float(WeaponDefs.TILT.get(p.weapon.current, 1.0)) if p.weapon != null else 1.0
		rig.dead = e
		rig.head_yaw = 0.0
		rig.apply()
		muzzle.transform = rig.muzzle_transform()
		if leg_l != null:
			leg_l.basis = Basis.from_euler(Vector3(rig.hip_l.x, 0.0, rig.hip_l.y))
			leg_r.basis = Basis.from_euler(Vector3(rig.hip_r.x, 0.0, rig.hip_r.y))
	else:
		upper.rotation = Vector3(_aim_pitch + lean + _recoil_pitch + breathe + DEAD_CURL * e, twist, roll)
		upper.position = Vector3(0.0, HIP_Y + bob + sin(_clock * 1.7) * 0.0025 * calm, _recoil_push)

	_verb_roll = PlayerUtil.damp(_verb_roll, p.verbs.pose_roll, 10.0, adt)
	_verb_pitch = PlayerUtil.damp(_verb_pitch, p.verbs.pose_pitch, 10.0, adt)
	# --- placement (and the death fall: Euler YXZ = roll about the forward axis first, then the lean about the long axis, then the heading)
	global_position = view_pos
	rotation = Vector3(DEAD_TWIST * e, yaw + DEAD_SLEW * e, DEAD_ROLL * e)
	if e > 0.0:
		global_position += Vector3(cos(yaw), 0.0, -sin(yaw)) * (DEAD_SHIFT * e)
		_rest_on_floor(view_pos.y)
	else:
		_apply_cover_pose(p.cover, yaw)
		rotation.z += _verb_roll
		rotation.x += _verb_pitch

	# --- rim and glow: subtle at rest, brighter on a hit, while aiming and while a quantum power is active (no allocation: a few property writes on shared materials)
	var q = p.quantum
	var quantum_on: bool = q != null and (("clone" in q and q.clone != null) or ("links" in q and not q.links.is_empty()) or ("bits_left" in q and q.bits_left > 0.0))
	var want_ex := maxf(maxf(_flinch * 1.4, 0.45 if p.aiming else 0.0), 0.9 if quantum_on else 0.0)
	_excite = PlayerUtil.damp(_excite, minf(want_ex, 1.0), 10.0 if want_ex > _excite else 3.0, dt)
	if absf(_excite - _excite_applied) > 0.01:
		_excite_applied = _excite
		for gm in _gear_mats:
			gm.rim = _gear_rim + RIM_BOOST * _excite
			gm.emission_energy_multiplier = (LOW_GLOW if _quality == 0 else 1.0) * (COMPAT_GLOW if _is_compat() else 1.0) * (1.0 + GLOW_BOOST * _excite)

	_update_quantum_look(q, dt)

	# --- character lights follow the camera, so the hero is always modelled from the viewer's side and edged from behind
	if character_light and rig_view != null:
		var lit := lerpf(1.0, DEAD_LIGHT, e)
		_key_light.light_energy = _key_energy * lit * (0.8 if _quality == 0 else 1.0)      # LOW: a softer key (no rim light there; the bright panel of a phone must not clip him)
		_rim_light.light_energy = _rim_energy * lit
		var f := PlayerUtil.forward_of(rig_view.yaw, 0.0)
		var right := Vector3(-f.z, 0.0, f.x)
		_key_light.global_basis = Basis.looking_at((f * 0.82 - right * 0.28 + Vector3(0.0, -0.5, 0.0)).normalized(), Vector3.UP)
		_rim_light.global_basis = Basis.looking_at((-f * 0.8 + right * 0.55 + Vector3(0.0, -0.22, 0.0)).normalized(), Vector3.UP)

	# --- muzzle flash decay (real time)
	if _flash_t > 0.0:
		_flash_t -= dt
		if _flash_t <= 0.0:
			_flash_root.visible = false
	for i in _lights.size():
		if _light_t[i] > 0.0:
			_light_t[i] -= dt
			if _light_t[i] <= 0.0:
				_lights[i].visible = false
			else:
				var f := _light_t[i] / LIGHT_TIME
				_lights[i].light_energy = LIGHT_ENERGY * f * f


## How far the fall has come, 0..1, for a normalised time k: it starts slowly and the weight of the body takes it down faster and faster.
## Crouch squats the whole body (scale), a slide leans it back, a takedown lunges and tips it forward for a moment (G4).
func _apply_cover_pose(c: PlayerCover, yaw: float) -> void:
	var k := 1.0
	if c != null:
		k = clampf(c.height / PlayerCover.STAND_HEIGHT, 0.4, 1.0)
		if c.peeking:
			k = lerpf(k, 1.0, 0.55)
		rotation.x += (0.55 if c.sliding else 0.0) - 0.45 * c.strike
		global_position += Vector3(-sin(yaw), 0.0, -cos(yaw)) * (0.3 * c.strike)
	scale = Vector3(1.0, k, 1.0)


static func _fall_curve(k: float) -> float:
	return pow(k, 1.6)


## Lay the fallen body on the floor: the lowest point of its geometry (hulls of its parts, at the current pose) sits DEAD_REST_GAP above the floor.
## Followed every frame while the body is still falling and settling, then kept (the pose no longer changes).
func _rest_on_floor(floor_y: float) -> void:
	if _dead_t < FALL_TIME + DEAD_SETTLE:
		_rest_drop = _lowest_point() - global_position.y
	global_position.y = floor_y + DEAD_REST_GAP - _rest_drop


## World-space y of the lowest vertex among the convex hulls of the character's parts at their current transforms.
func _lowest_point() -> float:
	if rig != null:
		return rig.lowest_world_y()
	var lo := INF
	for i in _parts.size():
		var xf := _parts[i].global_transform
		for pt: Vector3 in _hulls[i]:
			lo = minf(lo, (xf * pt).y)
	return lo if lo != INF else global_position.y


## The rifle's weapon look: one emissive strip riding on the muzzle (the rifle bone), tinted and shaped per weapon (WeaponDefs look / look_size). One extra draw call, no new model.
func set_weapon_look(id: StringName) -> void:
	_weapon_id = id
	if muzzle == null:
		return
	var d := WeaponDefs.def(id)
	if _wp_mi == null:
		_wp_mi = MeshInstance3D.new()
		_wp_mi.name = "WeaponLook"
		_wp_mi.mesh = BoxMesh.new()
		_wp_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_wp_mat = StandardMaterial3D.new()
		_wp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wp_mi.material_override = _wp_mat
		muzzle.add_child(_wp_mi)
	var sz: Vector3 = d["look_size"]
	(_wp_mi.mesh as BoxMesh).size = sz
	_wp_mi.position = Vector3(0.0, 0.0, sz.z * 0.5 + 0.02)         # behind the muzzle along the barrel (muzzle forward is -Z)
	var col: Color = d["look"]
	_wp_mat.albedo_color = col * 1.4
	_wp_mi.visible = id != &"carbine"                              # the carbine is the plain rifle: the hero stays ONE mesh until another weapon is in hand


## One shot: flash card, light pulse and the body's recoil. intensity scales the flash.
func fire_flash(intensity := 1.0) -> void:
	if _flash_root != null:
		_flash_t = FLASH_TIME
		_flash_root.visible = true
		var s := randf_range(0.8, 1.25) * intensity
		_flash_root.rotation = Vector3(0.0, 0.0, randf() * TAU)
		_flash_root.scale = Vector3(s, s, s * randf_range(0.8, 1.5))
	if not _lights.is_empty() and _quality >= 1:
		var l := _lights[_li]
		_light_t[_li] = LIGHT_TIME
		_li = (_li + 1) % _lights.size()
		l.light_energy = LIGHT_ENERGY
		l.visible = true
	_recoil_push = minf(_recoil_push + 0.045, 0.12)
	_recoil_pitch = minf(_recoil_pitch + 0.04, 0.16)
	_kick = minf(_kick + 0.55, 1.0)
	_since_fire = 0.0


## A hit reaction: the torso snaps back for a moment.
func flinch(strength := 1.0, from_pos := Vector3.ZERO) -> void:
	if from_pos != Vector3.ZERO:
		var h := Vector3(from_pos.x - global_position.x, 0.0, from_pos.z - global_position.z)
		if h.length() > 0.2:
			h = h.normalized()
			var yw := rotation.y
			_fdir = Vector2(h.dot(Vector3(cos(yw), 0.0, -sin(yw))), h.dot(Vector3(-sin(yw), 0.0, -cos(yw))))
	_recoil_pitch = minf(_recoil_pitch + 0.1 * strength, 0.25)
	_recoil_push = minf(_recoil_push + 0.06 * strength, 0.15)
	_flinch = minf(_flinch + 0.55 * strength, 1.0)
	_fire_burst(global_position + Vector3(0.0, 1.3, 0.0), int(HeroPresentation.HIT_MOTES * clampf(strength, 0.4, 1.5)))


## The pooled quantum burst is created on the first hit (an idle emitter node costs draw calls in the tier-0 budget).
func _fire_burst(at: Vector3, count: int) -> void:
	if _burst == null or not is_instance_valid(_burst):
		_burst = HeroPresentation.make_burst(self)
	HeroPresentation.burst(_burst, at, count)


func set_dead(is_dead: bool) -> void:
	_dead_t = 0.0 if is_dead else -1.0
	_rest_drop = 0.0
	if is_dead:
		_fire_burst(global_position + Vector3(0.0, 1.0, 0.0), HeroPresentation.DEATH_MOTES)
	if not is_dead:
		rotation = Vector3(0.0, rotation.y, 0.0)


## Hide the flash and clear every transient pose (respawn, teleport).
func reset_pose() -> void:
	_dead_t = -1.0
	_flash_t = 0.0
	_recoil_push = 0.0
	_recoil_pitch = 0.0
	_kick = 0.0
	_flinch = 0.0
	_since_fire = 99.0
	_fdir = Vector2.ZERO
	_have_last = false
	if rig != null:
		rig.reset()
		rig.death_kind = 0
		if loco != null:
			loco.reset()
	if _flash_root != null:
		_flash_root.visible = false
	for i in _lights.size():
		_light_t[i] = 0.0
		_lights[i].visible = false


# ---------------------------------------------------------------------------------------------------------------------
# construction
# ---------------------------------------------------------------------------------------------------------------------

func _build() -> void:
	upper = Node3D.new()
	upper.name = "Upper"
	upper.position = Vector3(0.0, HIP_Y, 0.0)
	add_child(upper)
	var model: Node3D = null if force_primitive else _make_model()
	if model != null and CharacterRig.has_rig(model):
		_adopt_model(model)
	else:
		if model != null:
			model.free()
		_build_primitive()
	_collect_hulls()
	_build_flash()
	_build_character_lights()
	_reflection = MirrorProxy.new()
	_reflection.name = "Reflection"
	add_child(_reflection)
	# A skinned character is NOT reflected: its mirror copy would be the unskinned rest-pose mesh, a second body that stands still while the real one moves.
	var reflected: Array[MeshInstance3D] = []
	if rig == null:
		reflected.assign(_parts)
	_reflection.track(reflected)


## The hero model: the superhero when available, else the old skinned hero.
func _make_model(look: HeroLook = null) -> Node3D:
	hero_mat = null
	hero_info = {}
	if use_superhero:
		_hero_opts = _look_opts(look if look != null else (Game.progress.get(&"hero") as HeroLook if Game.progress != null else null))
		var r := HeroCharacter.build(_hero_opts)
		if r["root"] != null:
			if bool(r["ok"]):
				hero_mat = r["material"]
				hero_info = r["info"]
				return r["root"]
			(r["root"] as Node).free()
	return Game.load_model("player")


static func _look_opts(look: HeroLook) -> Dictionary:
	if look == null:
		return HeroCharacter.sanitize({})
	return HeroCharacter.sanitize({"body": look.body, "skin": look.skin_tone, "hair": look.hair, "beard": look.beard})


## A changed body, skin, hair or beard replaces the model in place (the same sequence as _build, without the lights and the reflection).
func _rebuild_model(look: HeroLook = null) -> void:
	var old := upper
	for pv: Node3D in [leg_l, leg_r]:
		remove_child_safe(pv)
	leg_l = null
	leg_r = null
	_lights.clear()
	_flash_root = null
	_wp_mi = null
	rig = null
	loco = null
	if old != null and is_instance_valid(old):
		remove_child(old)
		old.free()
	upper = Node3D.new()
	upper.name = "Upper"
	upper.position = Vector3(0.0, HIP_Y, 0.0)
	add_child(upper)
	uses_model = false
	_pending_look = look
	var model: Node3D = _make_model(look)
	if model != null and CharacterRig.has_rig(model):
		_adopt_model(model)
	else:
		if model != null:
			model.free()
		_build_primitive()
	_collect_hulls()
	_build_flash()
	_set_layer(self, 1 << (CHARACTER_LAYER - 1))
	if rig != null:
		var reflected: Array[MeshInstance3D] = []
		_reflection.track(reflected)
	if _weapon_id != &"":
		set_weapon_look(_weapon_id)
	_pending_look = null
	_have_last = false
	_excite_applied = -1.0
	set_fade(fade)


func _adopt_model(model: Node3D) -> void:
	uses_model = true
	rig = CharacterRig.find(model)
	if rig != null:
		loco = Locomotion.new(rig)
		if hero_mat != null:
			loco.turn_scale = SUPERHERO_TURN
			loco.scale_amp = SUPERHERO_STEP      # longer, human legs: longer strides and a longer leash than the short digitigrade legs of the old hero
	model.name = "Model"
	remove_child_safe(upper)
	upper = model
	add_child(model)
	for n: String in ["Fill", "Rim"]:                       # the model's own readability lights: the hero has his key and rim lights (below)
		var l := model.get_node_or_null(n)
		if l != null:
			model.remove_child(l)
			l.free()
	muzzle = model.get_node_or_null("Muzzle") as Node3D
	if muzzle == null:
		muzzle = Node3D.new()
		muzzle.name = "Muzzle"
		model.add_child(muzzle)
	for n: String in ["WristL", "WristR", "MagWell", "MagPouch"]:
		var m := model.get_node_or_null(n)
		if m != null:
			model.remove_child(m)
			m.free()
	# hip pivots that mirror the thigh swing of the rig (the primitive body's legs hang from the same two nodes)
	for side: int in [-1, 1]:
		var pivot := Node3D.new()
		pivot.name = "LegL" if side < 0 else "LegR"
		pivot.position = Vector3(side * 0.1, HIP_Y, 0.0)
		add_child(pivot)
		if side < 0:
			leg_l = pivot
		else:
			leg_r = pivot
	_prepare_materials(model, true)
	if hero_mat != null:
		_apply_hero_look(_pending_look if _pending_look != null else (Game.progress.get(&"hero") as HeroLook if Game.progress != null else null))
	HeroPresentation.set_height(HeroPresentation.measure_height(model))
	if rig != null:
		HeroPresentation.hand_mount(rig.skeleton, &"r")
		HeroPresentation.hand_mount(rig.skeleton, &"l")


func remove_child_safe(n: Node) -> void:
	if n != null and n.get_parent() == self:
		remove_child(n)
		n.free()


## Per-instance override materials (the imported resources stay untouched): every surface whose material is called "Fabric" is lifted (see FABRIC_LIFT) when
## `lift_fabric` is set (the imported model only: the primitive body is already light enough), and on the Compatibility renderer every surface stops receiving
## ambient light (see COMPAT_BOOST). Nothing else about the materials is changed on purpose: the lighting of this model was tuned and verified with exactly these
## shader variants, and adding a per-material feature (a dithered distance fade, alpha scissor) changes its shading a lot (3x brighter or black on the same lights).
func _prepare_materials(root: Node, lift_fabric: bool) -> void:
	if lift_fabric:
		_gear_mats.clear()
		_gear_emis.clear()
		_fabric_mats.clear()
	var compat := _is_compat()
	var boost := COMPAT_BOOST if compat else 1.0
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			var gear := lift_fabric and mat.resource_name == "Gear"
			var lift := (lift_fabric and mat.resource_name == "Fabric") or gear
			if not lift and not compat:
				continue
			var own := mat.duplicate() as BaseMaterial3D
			if lift:
				var k := lerpf(1.0, GEAR_LIFT if gear else FABRIC_LIFT, boost)
				own.albedo_color = Color(k, k, k, 1.0)
				if gear:
					own.rim_enabled = true                      # a fresnel edge light in the model's own cool tint keeps the silhouette against wet asphalt and neon
					_gear_rim = GEAR_RIM * (0.6 if compat else 1.0)
					own.rim = _gear_rim
					own.rim_tint = 0.2                           # mostly the cool light colour (a clean cool edge on DARK armour, not a pale outline)
					_gear_mats.append(own)
					_gear_base.append(own.albedo_color)
					_gear_emis.append(mat.emission if mat.emission_enabled else GEAR_EMISSION * boost)
					own.emission_enabled = true
					own.emission_texture = mat.emission_texture if mat.emission_enabled else null
					own.emission = (mat.emission if mat.emission_enabled else GEAR_EMISSION * boost)
					own.emission_energy_multiplier = mat.emission_energy_multiplier if mat.emission_enabled else 1.0
				else:
					own.emission_enabled = true
					own.emission = FABRIC_EMISSION * boost
					own.emission_energy_multiplier = 1.0
					own.rim_enabled = true
					own.rim = FABRIC_RIM * (0.6 if compat else 1.0)
					own.rim_tint = 0.3
					_fabric_mats.append(own)
			if compat:
				own.disable_ambient_light = true
				# the baked atlas is much lighter than the legacy fabric the warm tint was calibrated on: darker and neutral-cool there
				own.albedo_color = Color(0.36, 0.42, 0.5, 1.0) if gear else own.albedo_color * COMPAT_TINT
			mi.set_surface_override_material(i, own)
	if lift_fabric:
		_look_gear0.clear()
		_look_fab0.clear()
		_look_emis0 = _gear_emis.duplicate()
		_look_metal0.clear()
		_look_rough0.clear()
		for gm in _gear_mats:
			_look_gear0.append(gm.albedo_color)
			_look_metal0.append(gm.metallic)
			_look_rough0.append(gm.roughness)
		for fm in _fabric_mats:
			_look_fab0.append(fm.albedo_color)
		_look_mix = 0.0
		if Game.progress != null and Game.progress.get(&"hero") is HeroLook:
			apply_look(Game.progress.get(&"hero") as HeroLook)


## G2: the hero look as material parameters only (albedo tint, metallic, roughness, emission, trim accent) on the existing override materials. Safe before the model exists.
func apply_look(look: HeroLook) -> void:
	if look != null and use_superhero and not force_primitive and (hero_mat != null or HeroCharacter.available(look.body)) and _look_opts(look) != _hero_opts and is_inside_tree():
		_rebuild_model(look)
	if hero_mat != null:
		_apply_hero_look(look)
	if look == null or _look_gear0.size() != _gear_mats.size():
		return
	var sd := look.suit_def()
	var mult := (sd["albedo"] as Color) * look.tint()
	var acc := look.accent()
	var glow := float(sd["glow"])
	var neutral := look.suit == &"standard" and look.scheme == 0 and look.accent_hue < 0
	_look_accent = acc
	_look_mix = 0.0 if neutral else HeroLook.ACCENT_MIX
	for i in _gear_mats.size():
		var gm := _gear_mats[i]
		_gear_base[i] = Color(_look_gear0[i].r * mult.r, _look_gear0[i].g * mult.g, _look_gear0[i].b * mult.b, 1.0)
		gm.albedo_color = _gear_base[i] * (LOW_ALBEDO if _quality == 0 else Color.WHITE)
		gm.metallic = clampf(_look_metal0[i] + float(sd["metal"]), 0.0, 1.0)
		gm.roughness = clampf(_look_rough0[i] + float(sd["rough"]), 0.05, 1.0)
		_gear_emis[i] = _look_emis0[i].lerp(acc * (_look_emis0[i].get_luminance() + 0.02) * 4.0, 0.0 if neutral else HeroLook.ACCENT_MIX) * glow
		gm.emission_energy_multiplier = glow if gm.emission_texture != null else 1.0
	for i in _fabric_mats.size():
		var fm := _fabric_mats[i]
		fm.albedo_color = Color(_look_fab0[i].r * lerpf(1.0, mult.r, 0.5), _look_fab0[i].g * lerpf(1.0, mult.g, 0.5), _look_fab0[i].b * lerpf(1.0, mult.b, 0.5), 1.0)


## The look on the superhero's material: suit finish (albedo multiplier, metal, rough, glow) and the scheme's accent for the seams. Parameters only.
func _apply_hero_look(look: HeroLook) -> void:
	if hero_mat == null or look == null:
		return
	var sd := look.suit_def()
	var mult := (sd["albedo"] as Color) * look.tint()
	var neutral := look.suit == &"standard" and look.scheme == 0 and look.accent_hue < 0
	_look_accent = look.accent()
	_look_mix = 0.0 if neutral else HeroLook.ACCENT_MIX
	hero_mat.set_shader_parameter(&"look_tint", Color(mult.r, mult.g, mult.b))
	hero_mat.set_shader_parameter(&"suit_metal", clampf(0.3 + float(sd["metal"]), 0.0, 1.0))
	hero_mat.set_shader_parameter(&"suit_rough", clampf(0.5 + float(sd["rough"]), 0.05, 1.0))
	hero_mat.set_shader_parameter(&"glow", float(sd["glow"]) * (LOW_GLOW if _quality == 0 else 1.0))
	hero_mat.set_shader_parameter(&"accent", _look_accent)
	hero_mat.set_shader_parameter(&"accent_mix", _look_mix)


## Thin-film sheen of the trim: the hue drifts with time and view-independent phase; `charge` (QUANTUM TELEPORT aim) pushes it toward violet-magenta and brighter,
## `ready_k` (1 recharged .. 0 just used) dims the seams. Pure, so the test can check it.
static func trim_tint(t: float, charge: float, ready_k: float) -> Color:
	var ph := fposmod(t * 0.35 + charge * 0.8, 1.0) * 3.0
	var i := int(ph) % 3
	var c: Color = (TRIM_HUES[i] as Color).lerp(TRIM_HUES[(i + 1) % 3] as Color, ph - floorf(ph))
	return c * (0.55 + 0.45 * ready_k) * (1.0 + 0.8 * charge)


func _update_quantum_look(q: Variant, dt: float) -> void:
	var charge_t := 0.0
	var cd := 0.0
	if q != null:
		if "aiming" in q and q.aiming:
			charge_t = 1.0
		if "cd_blink" in q:
			cd = maxf(cd, minf(1.0, float(q.cd_blink) / 1.5))
		if "cd_link" in q:
			cd = maxf(cd, minf(1.0, float(q.cd_link) / 1.5))
		if "cd_super" in q:
			cd = maxf(cd, minf(1.0, float(q.cd_super) / 1.5))
	_charge = PlayerUtil.damp(_charge, charge_t, 12.0 if charge_t > _charge else 4.0, dt)
	_ready_k = PlayerUtil.damp(_ready_k, 1.0 - cd, 8.0, dt)
	_clock_look += dt
	var tint := trim_tint(_clock_look, _charge, _ready_k).lerp(_look_accent, _look_mix)
	if hero_mat != null:
		hero_mat.set_shader_parameter(&"trim_color", tint)
		hero_mat.set_shader_parameter(&"charge", _charge)
		hero_mat.set_shader_parameter(&"ready_k", _ready_k)
		hero_mat.set_shader_parameter(&"excite", _excite)
	var k := 0.35 if _is_compat() else 1.0
	for i in _gear_mats.size():
		_gear_mats[i].emission = _gear_emis[i].lerp(tint, 0.5 * (0.4 + 0.6 * _charge)) * (1.0 + 0.0 * k) if _gear_mats[i].emission_texture == null else tint * 0.9 * k
		_gear_mats[i].rim_tint = 0.2 + 0.4 * _charge


## The convex hull of every mesh of the character (body and legs, not the flash cards), kept in the mesh's own space: the corpse rests on them.
func _collect_hulls() -> void:
	_parts.clear()
	_hulls.clear()
	if rig != null:                                       # the skinned model: the mirror copy of its mesh, and the bone hulls of the rig for the corpse
		_parts.append(rig.rest_mesh)
		return
	var roots: Array[Node3D] = [upper, leg_l, leg_r]
	for root in roots:
		if root == null:
			continue
		var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
		if root is MeshInstance3D:
			meshes.append(root)
		for node in meshes:
			var mi := node as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var shape := mi.mesh.create_convex_shape(true, false)
			if shape != null and not shape.points.is_empty():
				_parts.append(mi)
				_hulls.append(shape.points)


# --- primitive fallback ----------------------------------------------------------------------------------------------

## Collects parts per material and bakes each material group into one surface of one ArrayMesh.
class Batch:
	var _tools := {}
	var _mats := {}

	func add(key: StringName, mat: Material, mesh: Mesh, xf: Transform3D) -> void:
		if not _tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_material(mat)
			_tools[key] = st
		(_tools[key] as SurfaceTool).append_from(mesh, 0, xf)

	func box(key: StringName, mat: Material, center: Vector3, size: Vector3, rot := Vector3.ZERO) -> void:
		var m := BoxMesh.new()
		m.size = size
		add(key, mat, m, Transform3D(Basis.from_euler(rot), center))

	func sphere(key: StringName, mat: Material, center: Vector3, radius: float, squash := Vector3.ONE) -> void:
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = 16
		m.rings = 8
		add(key, mat, m, Transform3D(Basis.from_scale(squash), center))

	func limb(key: StringName, mat: Material, a: Vector3, b: Vector3, radius: float) -> void:
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = a.distance_to(b) + radius * 2.0
		m.radial_segments = 12
		m.rings = 4
		var dir := (b - a).normalized()
		var basis := Basis.IDENTITY
		if absf(dir.dot(Vector3.UP)) < 0.9999:
			basis = Basis(Quaternion(Vector3.UP, dir))
		elif dir.y < 0.0:
			basis = Basis(Vector3.RIGHT, PI)
		add(key, mat, m, Transform3D(basis, (a + b) * 0.5))

	func cylinder(key: StringName, mat: Material, center: Vector3, radius: float, height: float, rot := Vector3.ZERO) -> void:
		var m := CylinderMesh.new()
		m.top_radius = radius
		m.bottom_radius = radius
		m.height = height
		m.radial_segments = 12
		m.rings = 1
		add(key, mat, m, Transform3D(Basis.from_euler(rot), center))

	func build() -> ArrayMesh:
		var am := ArrayMesh.new()
		for key: StringName in _tools:
			(_tools[key] as SurfaceTool).commit(am)
		return am


static func _pbr(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _build_primitive() -> void:
	uses_model = false
	var fabric := _pbr(Color(0.2, 0.23, 0.245), 0.93, 0.0)
	fabric.resource_name = "Fabric"
	var armor := _pbr(Color(0.17, 0.2, 0.215), 0.52, 0.35)
	armor.resource_name = "Armor"
	var gun := _pbr(Color(0.06, 0.065, 0.075), 0.36, 0.85)
	gun.resource_name = "Gunmetal"
	var visor := _pbr(Color(0.02, 0.035, 0.045), 0.07, 0.9)
	visor.resource_name = "Visor"
	var glow := StandardMaterial3D.new()
	glow.resource_name = "Glow"
	glow.albedo_color = Color.BLACK
	glow.emission_enabled = true
	glow.emission = Color(0.15, 0.9, 1.0)
	glow.emission_energy_multiplier = 3.5

	# upper body, authored with the feet at the origin like the glb (the Upper pivot carries the -HIP_Y offset)
	var b := Batch.new()
	b.box(&"fabric", fabric, Vector3(0.0, 0.98, 0.0), Vector3(0.34, 0.2, 0.22))            # pelvis
	b.box(&"gun", gun, Vector3(0.0, 1.06, 0.0), Vector3(0.37, 0.055, 0.245))               # belt
	b.box(&"fabric", fabric, Vector3(0.0, 1.19, 0.0), Vector3(0.37, 0.22, 0.235))          # abdomen
	b.box(&"fabric", fabric, Vector3(0.0, 1.41, 0.0), Vector3(0.43, 0.28, 0.26))           # chest
	b.box(&"armor", armor, Vector3(0.0, 1.41, -0.15), Vector3(0.37, 0.29, 0.06))           # front plate
	b.box(&"armor", armor, Vector3(-0.225, 1.4, 0.0), Vector3(0.045, 0.22, 0.19))          # side plates
	b.box(&"armor", armor, Vector3(0.225, 1.4, 0.0), Vector3(0.045, 0.22, 0.19))
	for px: float in [-0.11, 0.0, 0.11]:
		b.box(&"gun", gun, Vector3(px, 1.25, -0.165), Vector3(0.085, 0.11, 0.05))          # ammo pouches
	b.box(&"armor", armor, Vector3(0.0, 1.38, 0.2), Vector3(0.3, 0.34, 0.13))              # backpack
	b.cylinder(&"gun", gun, Vector3(-0.1, 1.62, 0.2), 0.008, 0.3)                          # antenna
	b.cylinder(&"fabric", fabric, Vector3(0.0, 1.575, 0.0), 0.05, 0.1)                     # neck
	b.sphere(&"fabric", fabric, Vector3(0.0, 1.685, 0.0), 0.105, Vector3(1.0, 1.12, 1.06)) # head
	b.sphere(&"armor", armor, Vector3(0.0, 1.715, 0.012), 0.135, Vector3(1.0, 0.92, 1.1))  # helmet
	b.box(&"gun", gun, Vector3(0.0, 1.79, 0.0), Vector3(0.05, 0.02, 0.2))                  # helmet rail
	b.box(&"visor", visor, Vector3(0.0, 1.69, -0.108), Vector3(0.175, 0.055, 0.075))       # visor
	b.box(&"glow", glow, Vector3(0.0, 1.69, -0.148), Vector3(0.15, 0.011, 0.008))          # visor light strip
	b.sphere(&"armor", armor, Vector3(-0.258, 1.515, 0.0), 0.085, Vector3(1.0, 0.9, 1.0))  # shoulder pads
	b.sphere(&"armor", armor, Vector3(0.258, 1.515, 0.0), 0.085, Vector3(1.0, 0.9, 1.0))
	# right arm (trigger hand) and left arm (foregrip)
	b.limb(&"fabric", fabric, Vector3(0.258, 1.5, 0.0), Vector3(0.275, 1.27, -0.11), 0.05)
	b.limb(&"fabric", fabric, Vector3(0.275, 1.27, -0.11), Vector3(0.158, 1.31, -0.4), 0.045)
	b.limb(&"fabric", fabric, Vector3(-0.258, 1.5, 0.0), Vector3(-0.3, 1.31, -0.24), 0.05)
	b.limb(&"fabric", fabric, Vector3(-0.3, 1.31, -0.24), Vector3(0.1, 1.345, -0.72), 0.045)
	b.box(&"gun", gun, Vector3(0.158, 1.31, -0.41), Vector3(0.07, 0.07, 0.09))             # gloves
	b.box(&"gun", gun, Vector3(0.1, 1.345, -0.73), Vector3(0.075, 0.075, 0.1))
	# rifle, muzzle at z = -1.06
	b.box(&"gun", gun, Vector3(0.14, 1.34, -0.5), Vector3(0.07, 0.115, 0.44))              # receiver
	b.box(&"gun", gun, Vector3(0.14, 1.345, -0.86), Vector3(0.075, 0.075, 0.32))           # handguard
	b.cylinder(&"gun", gun, Vector3(0.14, 1.345, -1.0), 0.013, 0.14, Vector3(PI * 0.5, 0.0, 0.0))  # barrel
	b.box(&"gun", gun, Vector3(0.14, 1.205, -0.47), Vector3(0.05, 0.17, 0.08), Vector3(0.18, 0.0, 0.0))  # magazine
	b.box(&"gun", gun, Vector3(0.14, 1.32, -0.14), Vector3(0.05, 0.1, 0.22))               # stock
	b.box(&"gun", gun, Vector3(0.14, 1.425, -0.5), Vector3(0.05, 0.05, 0.13))              # optic
	b.box(&"glow", glow, Vector3(0.14, 1.426, -0.57), Vector3(0.012, 0.012, 0.012))        # optic reticle glint
	var body_mi := MeshInstance3D.new()
	body_mi.name = "Body"
	body_mi.mesh = b.build()
	body_mi.position = Vector3(0.0, -HIP_Y, 0.0)
	upper.add_child(body_mi)

	muzzle = Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.14, 1.345, -1.07) - Vector3(0.0, HIP_Y, 0.0)
	upper.add_child(muzzle)

	# legs, pivots at the hips
	for side: int in [-1, 1]:
		var lb := Batch.new()
		var s := float(side)
		lb.limb(&"fabric", fabric, Vector3(0.0, -0.06, 0.0), Vector3(0.0, -0.45, 0.0), 0.088)       # thigh
		lb.limb(&"fabric", fabric, Vector3(0.0, -0.49, 0.0), Vector3(0.0, -0.8, 0.0), 0.068)        # shin
		lb.box(&"armor", armor, Vector3(0.0, -0.47, -0.075), Vector3(0.115, 0.1, 0.05))             # knee pad
		lb.box(&"armor", armor, Vector3(s * 0.085, -0.25, 0.0), Vector3(0.03, 0.2, 0.12))           # thigh holster plate
		lb.box(&"gun", gun, Vector3(0.0, -0.885, -0.05), Vector3(0.115, 0.1, 0.27))                 # boot
		lb.box(&"gun", gun, Vector3(0.0, -0.925, -0.055), Vector3(0.12, 0.025, 0.285))              # sole
		var leg := MeshInstance3D.new()
		leg.mesh = lb.build()
		leg.position = Vector3(s * 0.098, HIP_Y, 0.0)
		add_child(leg)
		if side < 0:
			leg.name = "LegL"
			leg_l = leg
		else:
			leg.name = "LegR"
			leg_r = leg
	_prepare_materials(upper, false)
	_prepare_materials(leg_l, false)
	_prepare_materials(leg_r, false)


# --- character lights ---------------------------------------------------------------------------------------------------

func _build_character_lights() -> void:
	var mask := 1 << (CHARACTER_LAYER - 1)
	_set_layer(self, mask)
	var boost := COMPAT_LIGHT if _is_compat() else 1.0
	_key_energy = 2.4 * boost                                  # a stronger front key: the face plate, chest core and weapon read at 3-15 m
	_rim_energy = 1.1 * boost                                  # a soft edge light, not an outline (the rim material term carries the excited moments)
	_key_light = _make_character_light("KeyLight", Color(0.82, 0.9, 1.0), _key_energy, mask)
	_rim_light = _make_character_light("RimLight", Color(0.55, 0.88, 1.0), _rim_energy, mask)
	_apply_lights()


## Graphics tier (Game.quality): LOW keeps the key light but drops the rim light and the muzzle-flash light pulses (the flash sprites stay).
func set_quality(level: int) -> void:
	_quality = level
	_apply_lights()
	if hero_mat != null:
		hero_mat.set_shader_parameter(&"brightness", 0.9 if level == 0 else 1.0)
	# LOW (phones with bright panels, no rim light, no post grade): darker armour and a calmer emission, so the hero reads as dark plates with cyan accents, never a pale glow
	for i in _gear_mats.size():
		_gear_mats[i].albedo_color = _gear_base[i] * (LOW_ALBEDO if level == 0 else Color.WHITE)
	_excite_applied = -1.0




func _apply_lights() -> void:
	if _key_light != null:
		_key_light.visible = character_light
		_rim_light.visible = character_light and _quality >= 1 and not _is_compat()      # Compat: no rim light (it, the exposure lift and the bloom made the hero white)


func _make_character_light(light_name: String, color: Color, energy: float, mask: int) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = light_name
	l.light_color = color
	l.light_energy = energy
	l.light_specular = 0.8
	l.light_cull_mask = mask
	l.shadow_enabled = false
	add_child(l)
	return l


static func _is_compat() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## Put every mesh of `node` on the character layer in addition to the default layer 1.
static func _set_layer(node: Node, mask: int) -> void:
	if node is GeometryInstance3D and (node as GeometryInstance3D).layers != 0:     # a mesh on no layer (the rig's rest-pose twin) must stay invisible
		var g := node as GeometryInstance3D
		if _is_compat() and g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			g.layers = mask                                  # Compat: ONLY the hero layer, so the world's lights (the unshadowed moon, lamps) cannot wash him out; his own key light stays
		else:
			g.layers |= mask
	for c in node.get_children():
		_set_layer(c, mask)


# --- muzzle flash -----------------------------------------------------------------------------------------------------

func _build_flash() -> void:
	_flash_root = Node3D.new()
	_flash_root.name = "Flash"
	_flash_root.visible = false
	muzzle.add_child(_flash_root)
	var star := MeshInstance3D.new()
	var star_mesh := QuadMesh.new()
	star_mesh.size = Vector2(0.5, 0.5)
	star.mesh = star_mesh
	star.material_override = _get_flash_material(true)
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_root.add_child(star)
	# two crossed streaks that jet forward from the barrel
	var streak_mesh := QuadMesh.new()
	streak_mesh.size = Vector2(0.2, 0.75)
	for i in 2:
		var streak := MeshInstance3D.new()
		streak.mesh = streak_mesh
		streak.material_override = _get_flash_material(false)
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var flat := Basis(Vector3.RIGHT, -PI * 0.5)                  # long axis along -Z, lying flat
		streak.transform = Transform3D(Basis(Vector3.FORWARD, i * PI * 0.5) * flat, Vector3(0.0, 0.0, -0.37))
		_flash_root.add_child(streak)
	for i in LIGHT_COUNT:
		var l := OmniLight3D.new()
		l.name = "FlashLight%d" % i
		l.light_color = Color(1.0, 0.72, 0.38)
		l.omni_range = 9.0
		l.omni_attenuation = 1.5
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		l.position = Vector3(0.0, 0.05, -0.25)
		muzzle.add_child(l)
		_lights.append(l)
	_light_t.resize(LIGHT_COUNT)
	_light_t.fill(0.0)


static func _get_flash_material(star: bool) -> StandardMaterial3D:
	if _flash_mat_star == null:
		_paint_flash_textures()
		for is_star: bool in [true, false]:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.disable_receive_shadows = true
			if is_star:
				m.albedo_texture = _flash_star_tex
				m.albedo_color = Color(2.2, 1.7, 1.0)
				m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
				_flash_mat_star = m
			else:
				m.albedo_texture = _flash_streak_tex
				m.albedo_color = Color(2.4, 1.6, 0.8)
				_flash_mat_streak = m
	return _flash_mat_star if star else _flash_mat_streak


static func _paint_flash_textures() -> void:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var ang := atan2(v, u)
			var core := exp(-r * r * 16.0)
			var halo := exp(-r * 3.4) * 0.5
			var rays := pow(absf(cos(ang * 3.0 + 0.3)), 14.0) * exp(-r * 2.4) * 0.9
			var a := clampf(core + halo + rays, 0.0, 1.0) * (1.0 - smoothstep(0.85, 1.0, r))
			img.set_pixel(x, y, Color(1.0, 0.95, 0.8, a))
	_flash_star_tex = ImageTexture.create_from_image(img)
	var w := 32
	var h := 64
	var img2 := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var t := (y + 0.5) / h                        # 0 at the tip, 1 at the barrel
			var s := (x + 0.5) / w * 2.0 - 1.0
			var a := pow(t, 1.6) * exp(-s * s * 5.0)
			img2.set_pixel(x, y, Color(1.0, 0.9, 0.7, clampf(a, 0.0, 1.0)))
	_flash_streak_tex = ImageTexture.create_from_image(img2)


## True when no mirror copy of an unskinned (rest pose) mesh is tracked for a skinned hero.
func reflection_free() -> bool:
	return rig == null or _reflection == null or _reflection.get_child_count() == 0
