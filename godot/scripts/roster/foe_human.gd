class_name FoeHuman
extends RefCounted
## The skinned bodies of the humanoid roster enemies (wave 113, enemy look v3): a Quaternius base body (the hero's rig, CC0) in the armour of a FoeKit look, ONE surface and one draw call, three meshes
## (near / mid / far, the base body reduced first, the small armour parts dropped), driven by the same CharacterRig + Locomotion + HumanoidAnim as the hero and the troopers.
##   build(look, variant, weapon)   {root, rig, loco, hanim, body, material, info, look, variant, weapon, near, mid, far, mount}: the model of one enemy ({} when the files are absent)
##   set_lod(h, dist)               near < 16 m, mid < 46 m, far beyond (hysteresis 3 m); true when the mesh changed
##   drive(h, dt, disp, yaw, ...)   one frame of locomotion + upper body + rig.apply()
##   fire / hit / die / windup      the combat inputs of HumanoidAnim; set_glow / set_hp / set_tele the shader state
## Prototype per (look, weapon) is built once (the merge of body, kit and weapon is the expensive part); every further enemy duplicates the node tree and shares the meshes and the skin.

const NEAR := 6000
const MID := 2600
const FAR := 1100
const MID_RANGE := 16.0
const FAR_RANGE := 46.0
const HYST := 3.0
const BASE_SCALE := 1.06                  ## the roster humans are a little larger than a person (readability, a hostile silhouette)

static var _protos := {}                 ## "look/weapon" -> {root, near, mid, far, info}
static var builds := 0                   ## full builds (tests: a second enemy of a look must not rebuild)


static func available() -> bool:
	return HeroCharacter.available(&"male") and FoeKit.available()


static func _opts(look: StringName, variant: int, weapon: StringName, budget: int, kit_lod: int) -> Dictionary:
	return {"body": &"male", "skin": &"dark", "hair": &"none", "beard": false, "armed": true, "map_body": &"male", "map_skin": &"dark", "budget": budget, "foe_look": look,
			"weapon_id": weapon, "kit_lod": kit_lod, "variant": variant}


static func _key(look: StringName, weapon: StringName) -> String:
	return "%s/%s" % [look, weapon]


## Builds (or duplicates) the model of `look`. `weapon` = a weapon registry id, &"" = the look's own.
static func build(look: StringName, variant := 0, weapon: StringName = &"") -> Dictionary:
	if not available() or not FoeLooks.has(look):
		return {}
	var wid := weapon if weapon != &"" else FoeLooks.weapon_of(look)
	if not FoeArms.has_weapon(wid):
		wid = &"carbine"
	var key := _key(look, wid)
	if not _protos.has(key):
		var r := HeroCharacter.build(_opts(look, variant, wid, NEAR, 0))
		if r["root"] == null:
			return {}
		builds += 1
		var body0 := r["body"] as MeshInstance3D
		var near_mesh: Mesh = body0.mesh
		var mid_mesh := _lod_mesh(look, variant, wid, MID, 1)
		var far_mesh := _lod_mesh(look, variant, wid, FAR, 2)
		(r["root"] as Node).name = "FoeProto"
		_protos[key] = {"root": r["root"], "near": near_mesh, "mid": mid_mesh, "far": far_mesh, "info": r["info"]}
	var pr: Dictionary = _protos[key]
	var root := (pr["root"] as Node3D).duplicate() as Node3D
	root.name = "FoeModel"
	var body := _find_body(root)
	if body == null:
		root.free()
		return {}
	var mat := FoeLooks.make_material(look, variant)
	body.material_override = mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.extra_cull_margin = 1.5
	body.mesh = pr["near"]
	var rig := CharacterRig.find(root)
	if rig == null:
		root.free()
		return {}
	var loco := Locomotion.new(rig)
	loco.scale_amp = 0.9
	var hanim := HumanoidAnim.new()
	var mount := FoeArms.setup(rig, hanim, wid)
	rig.reflection = null
	var spec := FoeLooks.data(look)
	root.scale = (spec["scale"] as Vector3) * BASE_SCALE
	return {"root": root, "rig": rig, "loco": loco, "hanim": hanim, "body": body, "material": mat, "info": pr["info"], "look": look, "variant": variant, "weapon": wid,
			"near": pr["near"], "mid": pr["mid"], "far": pr["far"], "mount": mount, "lod": 0, "_last": Vector3.INF, "hp": 1.0, "tele": 0.0}


static func _find_body(root: Node) -> MeshInstance3D:
	for n in root.find_children("Body", "MeshInstance3D", true, false):
		return n as MeshInstance3D
	return null


static func _lod_mesh(look: StringName, variant: int, weapon: StringName, budget: int, kit_lod: int) -> Mesh:
	var r := HeroCharacter.build(_opts(look, variant, weapon, budget, kit_lod))
	if r["root"] == null:
		return null
	var m: Mesh = (r["body"] as MeshInstance3D).mesh
	(r["body"] as MeshInstance3D).mesh = null
	(r["root"] as Node).free()
	return m


## Triangles of a mesh (tests, budgets).
static func tris(mesh: Mesh) -> int:
	return HumanoidVariants.tris(mesh)


## Near / mid / far mesh by camera distance; returns true when it changed.
static func set_lod(h: Dictionary, dist: float) -> bool:
	if h.is_empty():
		return false
	var cur := int(h["lod"])
	var want := cur
	if dist > FAR_RANGE - (HYST if cur == 2 else 0.0):
		want = 2
	elif dist > MID_RANGE - (HYST if cur >= 1 else 0.0):
		want = 1
	else:
		want = 0
	if want == cur:
		return false
	var m: Mesh = [h["near"], h["mid"], h["far"]][want]
	if m == null:
		return false
	(h["body"] as MeshInstance3D).mesh = m
	h["lod"] = want
	return true


## One frame: Locomotion for the legs and pelvis (planted feet), the upper-body state machine for aim, recoil, flinch and the fall, then the rig. `disp` = the world displacement of the body
## since the last frame (flat), `yaw` the body yaw, `moving` 0..1 how hard it walks, `firing` whether the weapon is raised, `want_pitch` the aim pitch, `look_off` the aim yaw relative to the body.
static func drive(h: Dictionary, dt: float, disp: Vector3, yaw: float, moving: float, firing: bool, want_pitch := 0.0, look_off := 0.0) -> void:
	if h.is_empty() or dt <= 0.0:
		return
	var rig: CharacterRig = h["rig"]
	var loco: Locomotion = h["loco"]
	var hanim: HumanoidAnim = h["hanim"]
	loco.update(dt, disp, yaw, true, 0.0, moving, false, firing, look_off)
	hanim.update(dt, want_pitch)
	hanim.write(rig)
	rig.head_yaw = 0.0
	rig.apply()


## One frame of a body that is dying or downed: the upper-body machine and the rig (the limp pose), no locomotion.
static func drive_dead(h: Dictionary, dt: float) -> void:
	if h.is_empty() or dt <= 0.0:
		return
	var rig: CharacterRig = h["rig"]
	var hanim: HumanoidAnim = h["hanim"]
	hanim.update(dt, 0.0)
	hanim.write(rig)
	rig.apply()


static func fire(h: Dictionary) -> void:
	if not h.is_empty():
		(h["hanim"] as HumanoidAnim).fire()


static func hit(h: Dictionary, dir: Vector2, strength := 1.0) -> void:
	if not h.is_empty():
		(h["hanim"] as HumanoidAnim).hit(dir, strength)


static func die(h: Dictionary, kind := 0, secs := 1.1) -> void:
	if not h.is_empty():
		var ha := h["hanim"] as HumanoidAnim
		ha.death_time = secs
		ha.die(kind)


static func aim(h: Dictionary, on: bool) -> void:
	if h.is_empty():
		return
	var ha := h["hanim"] as HumanoidAnim
	if ha.state == HumanoidAnim.State.DEAD:
		return
	ha.set_state(HumanoidAnim.State.AIM if on else HumanoidAnim.State.IDLE)


static func windup(h: Dictionary, secs: float) -> void:
	if h.is_empty():
		return
	var ha := h["hanim"] as HumanoidAnim
	ha.windup_time = maxf(secs, 0.05)
	ha.set_state(HumanoidAnim.State.WINDUP)


## Resets the pose state of a pooled body.
static func reset(h: Dictionary) -> void:
	if h.is_empty():
		return
	(h["hanim"] as HumanoidAnim).reset()
	(h["loco"] as Locomotion).reset()
	(h["rig"] as CharacterRig).reset()
	h["_last"] = Vector3.INF
	set_hp(h, 1.0)
	set_tele(h, 0.0)


static func set_hp(h: Dictionary, k: float) -> void:
	if h.is_empty():
		return
	h["hp"] = k
	(h["body"] as MeshInstance3D).set_instance_shader_parameter(&"hp_k", clampf(k, 0.0, 1.0))


static func set_tele(h: Dictionary, k: float) -> void:
	if h.is_empty():
		return
	h["tele"] = k
	(h["body"] as MeshInstance3D).set_instance_shader_parameter(&"tele", clampf(k, 0.0, 1.0))


static func set_far(h: Dictionary, k: float) -> void:
	if not h.is_empty():
		(h["body"] as MeshInstance3D).set_instance_shader_parameter(&"far_k", clampf(k, 0.0, 1.0))


static func set_hit(h: Dictionary, k: float) -> void:
	if not h.is_empty():
		(h["body"] as MeshInstance3D).set_instance_shader_parameter(&"hit_k", clampf(k, 0.0, 1.0))


## Model-space muzzle transform (the weapon's own muzzle).
static func muzzle_transform(h: Dictionary) -> Transform3D:
	var t := (h["rig"] as CharacterRig).muzzle_transform()
	var shift := float((h["mount"] as Dictionary).get("muzzle_shift", 0.0))
	t.origin += t.basis * Vector3(0.0, 0.0, shift)
	return t
