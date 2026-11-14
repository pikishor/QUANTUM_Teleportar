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
const TIER_K := [0.72, 0.9, 1.0]          ## the LOD ranges shrink on the weaker tiers (LOW / MED / HIGH): the mid mesh from 11.5 m and the far mesh from 33 m on a phone's default tier
const WARM_LOOKS: Array[StringName] = [&"merc_rifle", &"auth_riot"]      ## built behind the loading overlay (the two looks the first fights of the game use; the city troopers' looks are warmed with the enemy pool)
const WARM_CREATURES: Array[StringName] = [&"vael_grunt", &"grid_walker"]
const BASE_SCALE := 1.06                  ## the roster humans are a little larger than a person (readability, a hostile silhouette)

static var _protos := {}                 ## "look/weapon" -> {root, near, mid, far, info}: the mid and far meshes are built one per frame AFTER the first body of a look exists (no 0.9 s hitch)
static var _pending: Array = []          ## [[key, "mid" | "far", look, variant, weapon], ...]
static var _pump_frame := -1
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
		(r["root"] as Node).name = "FoeProto"
		_protos[key] = {"root": r["root"], "near": near_mesh, "mid": null, "far": null, "info": r["info"]}
		_pending.append([key, "mid", look, variant, wid])
		_pending.append([key, "far", look, variant, wid])
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
	rig.set_shadow(false)                                  # the shadow-only proxy of the rig stays off until the body is near (RosterHuman.update: MED / HIGH, within the tier's shadow range)
	var spec := FoeLooks.data(look)
	root.scale = (spec["scale"] as Vector3) * BASE_SCALE
	return {"root": root, "rig": rig, "loco": loco, "hanim": hanim, "body": body, "material": mat, "info": pr["info"], "look": look, "variant": variant, "weapon": wid,
			"proto": pr, "key": key, "mount": mount, "lod": 0, "_last": Vector3.INF, "hp": 1.0, "tele": 0.0}


## The mesh of a LOD level ("near", "mid", "far") of a body; the mid and far meshes of a look are built by pump() or by ensure_lods().
static func mesh_of(h: Dictionary, which: String) -> Mesh:
	return (h["proto"] as Dictionary)[which]


## Builds ONE pending LOD mesh per frame (call it every frame while enemies exist).
static func pump() -> void:
	var f := Engine.get_process_frames()
	if f == _pump_frame or _pending.is_empty():
		return
	_pump_frame = f
	var job: Array = _pending.pop_front()
	var pr: Dictionary = _protos.get(job[0], {})
	if pr.is_empty() or pr[job[1]] != null:
		return
	var mid: bool = job[1] == "mid"
	pr[job[1]] = _lod_mesh(job[2], job[3], job[4], MID if mid else FAR, 1 if mid else 2)


## Builds every pending LOD mesh now (tests, look-dev, a warm-up).
static func ensure_lods() -> void:
	_pump_frame = -1
	while not _pending.is_empty():
		_pump_frame = -1
		pump()


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


## Loading-time warm-up (ShaderWarmup hooks): builds the prototype of the most common looks and one creature of each material and puts a body of each in front of the camera for the warm-up frames,
## so the first mercenary or alien of a fight does not stall on the merge, the shader compile and the first draw. Returns the nodes; warm_end() frees them.
static func warm_begin(parent: Node, at: Vector3) -> Array:
	var out: Array = []
	if parent == null:
		return out
	var x := 0.0
	if available():
		for look in WARM_LOOKS:
			var h := build(look, 0)
			if h.is_empty():
				continue
			var root := h["root"] as Node3D
			parent.add_child(root)
			root.global_position = at + Vector3(x, 0.0, 0.0)
			x += 1.3
			out.append(root)
		pump()
	for gid in WARM_CREATURES:
		var path := RosterHuman.FOE_DIR + String(gid) + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var ps := load(path) as PackedScene
		if ps == null:
			continue
		var cr := ps.instantiate() as Node3D
		var mat := FoeLooks.creature_material(Color(1.0, 0.6, 0.2))
		for n in cr.find_children("*", "MeshInstance3D", true, false):
			(n as MeshInstance3D).material_override = mat
			(n as MeshInstance3D).extra_cull_margin = 2.0
		parent.add_child(cr)
		cr.global_position = at + Vector3(x, 0.0, 0.0)
		x += 1.6
		out.append(cr)
	return out


static func warm_end(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()


## Triangles of a mesh (tests, budgets).
static func tris(mesh: Mesh) -> int:
	return HumanoidVariants.tris(mesh)


## Near / mid / far mesh by camera distance; returns true when it changed.
static func set_lod(h: Dictionary, dist: float) -> bool:
	if h.is_empty():
		return false
	var cur := int(h["lod"])
	var want := cur
	var rk: float = TIER_K[clampi(Game.quality, 0, 2)]
	if dist > FAR_RANGE * rk - (HYST if cur == 2 else 0.0):
		want = 2
	elif dist > MID_RANGE * rk - (HYST if cur >= 1 else 0.0):
		want = 1
	else:
		want = 0
	if want == cur:
		return false
	var pr: Dictionary = h["proto"]
	var m: Mesh = [pr["near"], pr["mid"], pr["far"]][want]
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
