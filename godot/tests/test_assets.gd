extends RefCounted
## ASSETS module test: loads every generated model through Game.load_model and every sound as an AudioStreamWAV, and checks the
## contract in ARCHITECTURE.md / tools/blender/README.md: node names, orientation (front = -Z), ground contact, scale, triangle and
## draw-call budgets, emissive and recolourable materials, the lights that ship with the models, and the audio format, levels, mix
## headroom and loop.
## Models come in two generations: the old ones textured from the shared tiling sets (legacy) and the baked-atlas ones (tools/blender/atlas.py,
## textures named assets/textures/<model>_albedo...). The strict budgets apply to the baked generation; legacy models only have to keep
## the old limits and the test prints a WARN line (run tools/build_assets.sh to regenerate them).
## Run: tools/test.sh tests/test_assets.gd   (run tools/import.sh first after regenerating assets)

const CHARACTERS := ["player", "operative"]
const DRONES := ["drone_sentinel", "drone_striker", "drone_heavy"]
const CARS := ["car_sedan", "car_sport", "car_suv", "car_taxi", "car_wagon", "car_van", "car_truck"]
const PROPS := ["pickup_health", "pickup_energy", "core_gem"]
const BUDGET_CHARACTER := 18000                     ## hero (the operative has BUDGET_OPERATIVE)
const BUDGET_OPERATIVE := 12000
const BUDGET_DRONE := 8000
const BUDGET_CAR := 15000
const BUDGET_PROP := 2500
## Draw calls per model: every (mesh node, material) pair is one surface. Legacy models (several tiling-texture materials each).
const SURFACES_LEGACY_CHARACTER := 10
const SURFACES_LEGACY_DRONE := 11
const SURFACES_LEGACY_CAR := 11
## Baked-atlas models: characters ONE skinned Body mesh (one draw call; the legs, arms, torso and head are bones), drones Body + Fins + Eye (living drones: the Fins node is a frill / thorn ring / cilia skirt the game turns and pulses), cars Body (paint, details, 3 emissive) + 4 wheels, props one.
const SURFACES_CHARACTER := 4
const SURFACES_DRONE := 3
const SURFACES_CAR := 9
const SURFACES_PROP := 2
## A firefight in view (6 operatives, 3 sentinels, 1 striker, 1 heavy, 6 cars): the models must leave room for the world and the player
## inside the 150 draw calls / 300k triangles of the MED tier in BUDGETS.md.
const SCENARIO := {"operative": 6, "drone_sentinel": 3, "drone_striker": 1, "drone_heavy": 1, "car_sedan": 2, "car_sport": 2, "car_suv": 2}
const SCENARIO_SURFACES := 110
const SCENARIO_TRIS := 130000
## Light layer 19 (bit 18): fill lights that light only their own model (see tools/blender/post_import.gd).
const FILL_MASK := 1 << 18
## name -> [min seconds, max seconds, peak level in dBFS]. Levels are mix levels (see tools/audio/make_audio.py LEVELS_DB).
const SFX := {
	"shot": [0.3, 1.5, -12.0], "enemy_shot": [0.2, 1.2, -13.0], "hit": [0.1, 0.8, -14.0], "hurt": [0.4, 1.8, -13.0],
	"boom": [1.5, 5.0, -10.0], "blink": [0.5, 2.0, -12.0], "link": [0.5, 2.0, -13.0], "superpos": [0.8, 3.0, -13.0],
	"pickup": [0.3, 1.5, -14.0], "reload": [0.8, 2.0, -14.0], "core": [1.5, 6.0, -10.0],
}
const MUSIC_LEVEL := -17.0
const POOL := 12                  ## Sfx.POOL: AudioStreamPlayers used round robin


func run(host: Node) -> void:
	for n in CHARACTERS:
		_character(host, n)
	_citizen(host)
	for n in DRONES:
		_drone(host, n)
	for n in CARS:
		_car(host, n)
	for n in PROPS:
		_prop(host, n)
	_scenario(host)
	_textures()
	_audio()
	_mix()


# ------------------------------------------------------------------ the pedestrian citizen mesh (vertex colours, no texture) and the high-poly bake of the characters
func _citizen(host: Node) -> void:
	var m := _load(host, "citizen")
	if m == null:
		return
	var meshes := _meshes(m)
	var near: MeshInstance3D = null
	var far: MeshInstance3D = null
	for mi in meshes:
		if String(mi.name).begins_with("CitizenFar"):
			far = mi
		elif String(mi.name).begins_with("Citizen"):
			near = mi
	TestLib.check(meshes.size() == 2 and near != null and far != null and near.mesh.get_surface_count() == 1 and far.mesh.get_surface_count() == 1, "citizen = a near and a far mesh of ONE surface each (the crowd is 2 draws)")
	if near == null or far == null:
		return
	var tris: int = 0
	var tris_far: int = 0
	for si in near.mesh.get_surface_count():
		tris += (near.mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	for si in far.mesh.get_surface_count():
		tris_far += (far.mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	TestLib.check(tris >= 600 and tris <= 900, "citizen (near) triangle count %d within 600..900 (all optional pieces included)" % tris)
	TestLib.check(tris_far >= 150 and tris_far <= 350, "citizen (far) triangle count %d within 150..350" % tris_far)
	var arrays: Array = near.mesh.surface_get_arrays(0)
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	TestLib.check(cols.size() == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() and cols.size() > 0, "citizen carries vertex colours (surface / piece / shadow / part tag)")
	var tags := {}
	var pieces := {}
	for c in cols:
		tags[snappedf(c.a, 0.1)] = true
		pieces[roundi(c.g * 20.0)] = true
	TestLib.check(tags.size() >= 6 and pieces.size() >= 14, "citizen has every part tag (%d) and every optional piece (%d of 14 ids, piece = G * 20)" % [tags.size(), pieces.size()])
	var box := near.mesh.get_aabb()
	TestLib.check(box.size.y > 1.9 and box.size.y < 2.2 and absf(box.position.y) < 0.05, "citizen stands on the origin, %.2f m with the umbrella" % box.size.y)
	# the hero and the trooper are baked from a high-poly source: their normal maps are not flat (a procedural-only map is nearly flat on large plates)
	for n in CHARACTERS:
		var tex := load("res://assets/textures/%s_normal.png" % n) as Texture2D
		TestLib.check(tex != null and tex.get_width() >= 2048, "%s normal map is a 2K bake" % n)


# ------------------------------------------------------------------ helpers
func _load(host: Node, model_name: String) -> Node3D:
	var m := Game.load_model(model_name)
	TestLib.check(m != null, "%s.glb loads through Game.load_model" % model_name)
	if m:
		host.add_child(m)
	return m


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in root.find_children("*", "MeshInstance3D", true, false):
		out.append(c as MeshInstance3D)
	return out


func _lights(root: Node) -> Array[Light3D]:
	var out: Array[Light3D] = []
	for c in root.find_children("*", "Light3D", true, false):
		out.append(c as Light3D)
	return out


func _tris(root: Node) -> int:
	var total := 0
	for mi in _meshes(root):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx := arr[Mesh.ARRAY_INDEX] as PackedInt32Array
			if idx.size() > 0:
				total += idx.size() / 3
			else:
				total += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


## World-space bounds of all meshes under root (root must be in the tree).
func _aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(root):
		var a := mi.global_transform * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


## Bounds of the solid geometry only: the soft glow fans of the car lamps (halos, light pools on the road, vertex-coloured, drawn additively) belong to the
## Headlights / Taillights / Underglow surfaces and reach past the body on purpose, so a car's size is measured without them.
func _aabb_solid(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _meshes(root):
		var mesh := mi.mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat != null and String(mat.resource_name) in ["Headlights", "Taillights", "Underglow"]:
				continue
			var vs := mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array
			for v in vs:
				var p := mi.global_transform * v
				box = AABB(p, Vector3.ZERO) if first else box.expand(p)
				first = false
	return box


func _surfaces(root: Node) -> int:
	var n := 0
	for mi in _meshes(root):
		if mi.mesh and not String(mi.name).ends_with("_LOD1"):      # the LOD1 body replaces Body (never drawn with it)
			n += mi.mesh.get_surface_count()
	return n


func _node(root: Node, node_name: String) -> Node3D:
	return root.find_child(node_name, true, false) as Node3D


func _material(root: Node, mat_name: String) -> StandardMaterial3D:
	for mi in _meshes(root):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if m and m.resource_name == mat_name:
				return m
	return null


## Mean z of the vertices of every surface that uses the named material (front of the model is -Z).
func _mean_z(root: Node, mat_name: String) -> float:
	var sum := 0.0
	var n := 0
	for mi in _meshes(root):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m and m.resource_name == mat_name:
				var vs := mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array
				for v in vs:
					sum += (mi.global_transform * v).z
					n += 1
	return sum / maxf(n, 1)


func _is_emissive(m: BaseMaterial3D) -> bool:
	return m != null and m.emission_enabled and m.emission_energy_multiplier >= 1.0


## True when any surface of the model glows (practical lights, optics, status strips).
func _any_emissive(root: Node) -> bool:
	for mi in _meshes(root):
		for s in mi.mesh.get_surface_count():
			if _is_emissive(mi.mesh.surface_get_material(s) as BaseMaterial3D):
				return true
	return false


## True for the baked generation: the model ships lights (legacy models never did), or an opaque surface uses the baked material
## (Gear / Hull / Details) or a texture baked for this model (assets/textures/<model>_albedo...).
func _baked(root: Node, model_name: String) -> bool:
	if _lights(root).size() > 0:
		return true
	for mi in _meshes(root):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			if mat.resource_name in ["Gear", "Hull", "Details"]:
				return true
			if mat.albedo_texture != null and mat.albedo_texture.resource_path.contains("/%s_" % model_name):
				return true
	return false


func _finish(m: Node3D) -> void:
	m.get_parent().remove_child(m)
	m.free()


## Checks every baked model has to pass: real lights that make it read at night, none of them casting shadows, no emitter hot enough to
## turn white under the city's ACES tonemap, and the legacy-state reminder for the others.
func _baked_common(m: Node3D, model_name: String, baked: bool, min_lights: int, own_fill: bool) -> void:
	if not baked:
		print("WARN: %s is still a legacy (tiling texture) model: run tools/build_assets.sh to bake its atlas, lights and LOD tags" % model_name)
		return
	var lights := _lights(m)
	TestLib.check(lights.size() >= min_lights, "%s ships %d real lights (>= %d) so it stays readable in the dark city" % [model_name, lights.size(), min_lights])
	var shadows := false
	var fill := false
	for l in lights:
		shadows = shadows or l.shadow_enabled
		fill = fill or l.light_cull_mask == FILL_MASK
	TestLib.check(not shadows, "%s lights cast no shadows (cheap on phones)" % model_name)
	if own_fill:
		TestLib.check(fill, "%s has a fill light that lights only the model itself (light layer 19)" % model_name)
	var hot := 0.0
	for mi in _meshes(m):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat != null and mat.emission_enabled:
				hot = maxf(hot, mat.emission_energy_multiplier)
	TestLib.check(hot <= 3.01, "%s emission strength %.2f stays at or below 3 (hotter turns white under ACES and the colour code is lost)" % [model_name, hot])


# ------------------------------------------------------------------ models
const BONES := ["Hips", "Torso", "Head", "UpperArmL", "ForeArmL", "UpperArmR", "ForeArmR", "Rifle", "ThighL", "ShinL", "FootL", "ThighR", "ShinR", "FootR"]


func _character(host: Node, model_name: String) -> void:
	var m := _load(host, model_name)
	if m == null:
		return
	var baked := _baked(m, model_name)
	var tris := _tris(m)
	var budget := BUDGET_CHARACTER if model_name == "player" else BUDGET_OPERATIVE
	TestLib.check(tris > 3000 and tris <= budget, "%s triangle count %d within 3000..%d" % [model_name, tris, budget])
	var limit := SURFACES_CHARACTER if baked else SURFACES_LEGACY_CHARACTER
	TestLib.check(_surfaces(m) <= limit, "%s draws in %d surfaces (<= %d)" % [model_name, _surfaces(m), limit])
	var skel := m.find_child("Skeleton3D", true, false) as Skeleton3D
	TestLib.check(skel != null, "%s is articulated: it has a Skeleton3D" % model_name)
	var body := m.find_child("Body", true, false) as MeshInstance3D
	TestLib.check(body != null and body.mesh != null and body.skin != null, "%s has one skinned Body mesh" % model_name)
	var muzzle := _node(m, "Muzzle")
	TestLib.check(muzzle != null, "%s has a Muzzle empty" % model_name)
	for n in ["WristL", "WristR", "MagWell", "MagPouch"]:
		TestLib.check(_node(m, n) != null, "%s has the rig marker %s" % [model_name, n])
	var rig := CharacterRig.find(m)
	TestLib.check(rig != null, "%s has every bone of the contract (%s)" % [model_name, ", ".join(BONES)])
	var box := body.get_aabb() if body != null else AABB()      # the mesh lives in the model's own space
	TestLib.check(box.size.y > 1.7 and box.size.y < 2.05, "%s is tall and lean, not a giant (%.2f m)" % [model_name, box.size.y])
	TestLib.check(absf(box.position.y) < 0.02, "%s stands on the ground (min y %.3f)" % [model_name, box.position.y])
	TestLib.check(box.size.x < 1.1 and box.size.z < 2.6, "%s has realistic breadth (%.2f x %.2f)" % [model_name, box.size.x, box.size.z])
	TestLib.check(box.size.x > 0.55, "%s has wide athletic shoulders (%.2f m across with the gear)" % [model_name, box.size.x])
	if muzzle:
		TestLib.check(muzzle.position.z < -0.6 and muzzle.position.y > 1.1 and muzzle.position.y < 1.6, "%s muzzle points forward (-Z) at chest height %s" % [model_name, muzzle.position])
		TestLib.check(muzzle.position.z <= box.position.z + 0.12, "%s muzzle is the front-most point" % model_name)
	if skel != null:
		var tl := skel.find_bone("ThighL")
		var tr_ := skel.find_bone("ThighR")
		var sl := skel.find_bone("ShinL")
		if tl >= 0 and tr_ >= 0 and sl >= 0:
			var gl := skel.get_bone_global_rest(tl).origin
			var gr := skel.get_bone_global_rest(tr_).origin
			TestLib.check(absf(gl.x) > 0.05 and gl.x * gr.x < 0.0, "%s thigh bones sit on both sides of the hips" % model_name)
			var knee := skel.get_bone_global_rest(sl).origin
			TestLib.check(gl.distance_to(knee) > 0.35 and gl.distance_to(knee) < 0.55, "%s thigh length %.2f m" % [model_name, gl.distance_to(knee)])
	TestLib.check(_any_emissive(m), "%s has emissive practical lights" % model_name)
	_baked_common(m, model_name, baked, 2, true)
	if rig != null:
		_rig_poses(m, rig, model_name)
	_finish(m)


## The procedural poses on the real skeleton: a walk cycle keeps the feet on the floor, the arms follow the rifle, every pose is finite and the aim pitch lifts the muzzle.
func _rig_poses(m: Node3D, rig: CharacterRig, model_name: String) -> void:
	rig.reset()
	var rest_low := rig.lowest_world_y()
	TestLib.check(absf(rest_low) < 0.03, "%s rests on the floor with the rig at rest (lowest %.3f)" % [model_name, rest_low])
	var rest_mz := rig.muzzle_transform().origin
	var mz := _node(m, "Muzzle")
	TestLib.check(mz != null and rest_mz.distance_to(mz.position) < 0.01, "%s muzzle follows the rifle bone (rest %s)" % [model_name, str(rest_mz)])
	var worst := 0.0
	var knee := 0.0
	for k in 12:                                                       # a full stride cycle: soles stay near the floor
		rig.phase = TAU * k / 12.0
		rig.amp = 1.0
		rig.run = 1.0
		rig.fw = 1.0
		rig.ready = 1.0
		rig.apply()
		worst = maxf(worst, absf(rig.lowest_world_y()))
		var sk := rig.skeleton
		knee = maxf(knee, absf(sk.get_bone_pose(sk.find_bone("ShinL")).basis.get_euler().x))
	TestLib.check(worst < 0.1, "%s run cycle: the lowest foot stays within %.3f m of the floor (digitigrade legs, the pelvis height is approximated)" % [model_name, worst])
	TestLib.check(knee > 0.6, "%s run cycle: the knees bend (%.2f rad)" % [model_name, knee])
	rig.phase = 0.0
	rig.amp = 0.0
	rig.apply()
	var level := rig.muzzle_transform().origin
	rig.aim_pitch = 0.5
	rig.apply()
	TestLib.check(rig.muzzle_transform().origin.y > level.y + 0.15, "%s head and rifle follow the aim pitch: the muzzle rises (%.2f -> %.2f)" % [model_name, level.y, rig.muzzle_transform().origin.y])
	rig.aim_pitch = 0.0
	var worst_hand := 0.0
	for pose in 6:                                                      # both gloves stay on the rifle wherever the rifle goes (aim pitch, low ready, sprint carry, kick, run)
		rig.ready = 1.0 if pose != 1 else 0.0
		rig.sprint = 1.0 if pose == 2 else 0.0
		rig.aim_pitch = -0.4 if pose == 3 else (0.5 if pose == 4 else 0.0)
		rig.recoil = 1.0 if pose == 5 else 0.0
		rig.amp = 1.0 if pose >= 1 else 0.0
		rig.phase = 1.3
		rig.apply()
		for k in 2:
			worst_hand = maxf(worst_hand, rig.wrist_position(k).distance_to(rig.rifle_grip(k)))
	TestLib.check(worst_hand < 0.07, "%s both gloves stay on the rifle in every carry pose (worst %.3f m off; the hands sway a few cm with the stride at low ready)" % [model_name, worst_hand])
	rig.recoil = 0.0
	rig.amp = 0.0
	rig.sprint = 0.0
	rig.aim_pitch = 0.0
	rig.ready = 1.0
	rig.apply()
	var grip0 := rig.rifle_grip(0)
	var far := 0.0
	for k in 11:                                                        # the reload takes the support hand off the rifle and back
		rig.reload = k / 10.0
		rig.apply()
		far = maxf(far, rig.wrist_position(0).distance_to(grip0))
	TestLib.check(far > 0.2, "%s reload: the support hand travels to the magazine and the vest (%.2f m)" % [model_name, far])
	rig.reload = 1.0
	rig.apply()
	TestLib.check(rig.wrist_position(0).distance_to(rig.rifle_grip(0)) < 0.03, "%s reload: the hand is back on the foregrip at the end" % model_name)
	rig.reload = -1.0
	var finite := true
	for pose in 5:                                                      # low ready, sprint carry, reload, collapse, limp: all finite and above the floor
		rig.ready = 0.0 if pose == 0 else 1.0
		rig.sprint = 1.0 if pose == 1 else 0.0
		rig.reload = 0.3 if pose == 2 else -1.0
		rig.knee_buckle = 1.0 if pose == 3 else 0.0
		rig.dead = 1.0 if pose == 4 else 0.0
		rig.apply()
		var low := rig.lowest_world_y()
		var mzp := rig.muzzle_transform().origin
		finite = finite and is_finite(low) and is_finite(mzp.x) and is_finite(mzp.y) and low > -0.2
		for i in rig.skeleton.get_bone_count():
			var t := rig.skeleton.get_bone_pose(i)
			finite = finite and is_finite(t.origin.x) and is_finite(t.basis.x.x) and is_finite(t.basis.y.y) and is_finite(t.basis.z.z)
	TestLib.check(finite, "%s low ready, sprint carry, reload, collapse and limp poses are finite and above the floor" % model_name)
	rig.reset()


func _drone(host: Node, model_name: String) -> void:
	var m := _load(host, model_name)
	if m == null:
		return
	var baked := _baked(m, model_name)
	var tris := _tris(m)
	TestLib.check(tris > 1500 and tris <= BUDGET_DRONE, "%s triangle count %d within 1500..%d" % [model_name, tris, BUDGET_DRONE])
	var limit := SURFACES_DRONE if baked else SURFACES_LEGACY_DRONE
	TestLib.check(_surfaces(m) <= limit, "%s draws in %d surfaces (<= %d)" % [model_name, _surfaces(m), limit])
	var eye := _node(m, "Eye")
	TestLib.check(eye != null, "%s has an Eye node" % model_name)
	for n in ["Body", "Fins"]:
		TestLib.check(_node(m, n) != null, "%s has node %s" % [model_name, n])
	var box := _aabb(m)
	TestLib.check(box.position.y > 0.1 and box.end.y < 2.6, "%s hovers above the ground (y %.2f..%.2f)" % [model_name, box.position.y, box.end.y])
	TestLib.check(box.size.x > 0.8 and box.size.x < 3.2 and box.size.z > 0.8 and box.size.z < 3.2, "%s has a plausible size (%.2f x %.2f)" % [model_name, box.size.x, box.size.z])
	if eye:
		var ec := (eye as Node3D).global_transform * (eye as MeshInstance3D).get_aabb().get_center()
		TestLib.check(ec.z < box.get_center().z, "%s Eye is on the front (-Z) side" % model_name)
		TestLib.check(ec.y > 0.5 and ec.y < 2.0, "%s Eye is at body height (%.2f)" % [model_name, ec.y])
		var eye_mat := (eye as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D
		TestLib.check(_is_emissive(eye_mat), "%s Eye surface material is emissive (the enemies module recolours a duplicate of it)" % model_name)
	if baked:
		for n in ["Fins"]:
			var rotor := _node(m, n) as GeometryInstance3D
			if rotor:
				TestLib.check(rotor.visibility_range_end > 10.0 and rotor.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s %s fades out with distance and casts no shadow" % [model_name, n])
	_baked_common(m, model_name, baked, 2, true)
	_finish(m)


func _car(host: Node, model_name: String) -> void:
	var m := _load(host, model_name)
	if m == null:
		return
	var baked := _baked(m, model_name)
	var tris := _tris(m)
	TestLib.check(tris > 4000 and tris <= BUDGET_CAR, "%s triangle count %d within 4000..%d" % [model_name, tris, BUDGET_CAR])
	var limit := SURFACES_CAR if baked else SURFACES_LEGACY_CAR
	TestLib.check(_surfaces(m) <= limit, "%s draws in %d surfaces (<= %d)" % [model_name, _surfaces(m), limit])
	var box := _aabb_solid(m)
	var big := model_name in ["car_van", "car_truck"]
	TestLib.check(box.size.z > (4.2 if not big else 4.8) and box.size.z < (5.2 if not big else 7.0), "%s is about 4.5 m long (%.2f)" % [model_name, box.size.z])
	TestLib.check(box.size.x > 1.7 and box.size.x < (2.3 if not big else 2.6), "%s is about 1.9 m wide (%.2f)" % [model_name, box.size.x])
	TestLib.check(box.size.y > 1.1 and box.size.y < (1.95 if not big else 3.2), "%s is %.2f m tall" % [model_name, box.size.y])
	TestLib.check(box.position.y > -0.02 and box.position.y < 0.05, "%s touches the ground (min y %.3f)" % [model_name, box.position.y])
	var radii := []
	for pair in [["WheelFL", -1, -1], ["WheelFR", 1, -1], ["WheelRL", -1, 1], ["WheelRR", 1, 1]]:
		var w := _node(m, pair[0])
		TestLib.check(w is MeshInstance3D, "%s has %s" % [model_name, pair[0]])
		if w:
			TestLib.check(signf(w.position.x) == pair[1] and signf(w.position.z) == pair[2], "%s %s is on the right corner %s (front is -Z)" % [model_name, pair[0], w.position])
			var wb := (w as MeshInstance3D).get_aabb()
			TestLib.check(wb.get_center().length() < 0.06, "%s %s is pivoted at the axle" % [model_name, pair[0]])
			radii.append(wb.size.y * 0.5)
			TestLib.check(absf(w.position.y - wb.size.y * 0.5) < 0.03, "%s %s rests on the ground" % [model_name, pair[0]])
			if baked:
				TestLib.check((w as GeometryInstance3D).visibility_range_end > 10.0 and (w as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s %s fades out with distance and casts no shadow" % [model_name, pair[0]])
	if radii.size() == 4:
		TestLib.check(radii[0] > 0.28 and radii[0] < 0.45, "%s wheel radius %.2f m" % [model_name, radii[0]])
	var body := _material(m, "Body")
	TestLib.check(body != null and body.albedo_texture != null and body.normal_texture != null, "%s has a textured PBR 'Body' paint material (vehicles recolour a duplicate through albedo_color)" % model_name)
	for n in ["Headlights", "Taillights", "Underglow"]:
		TestLib.check(_is_emissive(_material(m, n)), "%s %s are emissive" % [model_name, n])
	TestLib.check(_mean_z(m, "Headlights") < -1.0 and _mean_z(m, "Taillights") > 1.0, "%s headlights face -Z, taillights +Z" % model_name)
	_baked_common(m, model_name, baked, 3, true)
	_finish(m)


func _prop(host: Node, model_name: String) -> void:
	var m := _load(host, model_name)
	if m == null:
		return
	var baked := _baked(m, model_name)
	var tris := _tris(m)
	TestLib.check(tris > 300 and tris <= BUDGET_PROP, "%s triangle count %d within 300..%d" % [model_name, tris, BUDGET_PROP])
	if baked:
		TestLib.check(_surfaces(m) <= SURFACES_PROP, "%s draws in %d surfaces (<= %d)" % [model_name, _surfaces(m), SURFACES_PROP])
	var box := _aabb(m)
	TestLib.check(absf(box.position.y) < 0.02, "%s sits on the ground (min y %.3f)" % [model_name, box.position.y])
	TestLib.check(box.size.x < 1.2 and box.size.y < 2.0 and box.size.y > 0.15, "%s is prop sized (%s)" % [model_name, box.size])
	TestLib.check(_any_emissive(m), "%s has an emissive part" % model_name)
	if baked and model_name != "core_gem":
		TestLib.check(box.size.y > 0.9 and box.size.x > 0.9, "%s is a beacon: large enough to read from far away (%s)" % [model_name, box.size])
	_baked_common(m, model_name, baked, 1, false)
	_finish(m)


## The models of a firefight together: draw calls and triangles that the world, the player and the effects have to share.
func _scenario(host: Node) -> void:
	var surf := 0
	var tris := 0
	var all_baked := true
	for model_name: String in SCENARIO:
		var m := Game.load_model(model_name)
		if m == null:
			continue
		host.add_child(m)
		all_baked = all_baked and _baked(m, model_name)
		surf += _surfaces(m) * int(SCENARIO[model_name])
		tris += _tris(m) * int(SCENARIO[model_name])
		_finish(m)
	if all_baked:
		TestLib.check(surf <= SCENARIO_SURFACES, "a firefight of 17 models costs %d draw calls (<= %d, leaving room for the world inside the 150 budget)" % [surf, SCENARIO_SURFACES])
		TestLib.check(tris <= SCENARIO_TRIS, "a firefight of 17 models is %d triangles before LOD (<= %d)" % [tris, SCENARIO_TRIS])
	else:
		print("WARN: firefight scenario (%d surfaces, %d triangles) not enforced: some models are still legacy" % [surf, tris])


func _textures() -> void:
	for set_name in ["plating", "metal_painted", "fabric", "carbon", "rubber", "concrete", "asphalt", "steel", "glass"]:
		for kind in ["albedo", "orm", "normal"]:
			var path := "res://assets/textures/%s_%s.png" % [set_name, kind]
			var t := load(path) as Texture2D if ResourceLoader.exists(path) else null
			TestLib.check(t != null and t.get_width() >= 512 and t.get_width() == t.get_height(), "texture %s_%s loads as a square >= 512 px" % [set_name, kind])


# ------------------------------------------------------------------ audio
func _audio() -> void:
	for sfx_name: String in SFX:
		var s := _wav(sfx_name)
		if s == null:
			continue
		var lim: Array = SFX[sfx_name]
		var dur := s.get_length()
		TestLib.check(dur >= float(lim[0]) and dur <= float(lim[1]), "%s.wav duration %.2f s within %.1f..%.1f" % [sfx_name, dur, lim[0], lim[1]])
		var peak := _peak_db(s, 1)
		TestLib.check(absf(peak - float(lim[2])) < 1.0, "%s.wav peak %.2f dBFS is its mix level (%.1f)" % [sfx_name, peak, lim[2]])
		TestLib.check(s.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s.wav does not loop" % sfx_name)
	var music := _wav("music_ambient")
	if music:
		TestLib.check(absf(music.get_length() - 30.0) < 0.5, "music_ambient.wav is about 30 s (%.2f)" % music.get_length())
		TestLib.check(music.loop_mode == AudioStreamWAV.LOOP_FORWARD, "music_ambient.wav loops forward (smpl chunk)")
		TestLib.check(music.loop_end > music.get_length() * music.mix_rate * 0.99, "music loop covers the whole file (end %d)" % music.loop_end)
		var peak := _peak_db(music, 5)
		TestLib.check(absf(peak - MUSIC_LEVEL) < 1.0, "music_ambient.wav peak %.2f dBFS is its bed level (%.1f, well below the effects)" % [peak, MUSIC_LEVEL])
		# seamless: the step across the loop point is no bigger than a typical step inside the file
		var d := music.data
		var n := d.size() / 2
		var a := d.decode_s16((n - 1) * 2)
		var b := d.decode_s16(0)
		var typical := 0.0
		for i in range(1000, 21000):
			typical += absf(d.decode_s16((i + 1) * 2) - d.decode_s16(i * 2))
		typical /= 20000.0
		TestLib.check(absf(a - b) <= typical * 3.0 + 200.0, "music loop point is continuous (jump %d vs typical %.0f)" % [absf(a - b), typical])


func _wav(wav_name: String) -> AudioStreamWAV:
	var path := "res://assets/audio/%s.wav" % wav_name
	var s := load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
	TestLib.check(s != null, "%s.wav loads as AudioStreamWAV" % wav_name)
	if s:
		TestLib.check(s.format == AudioStreamWAV.FORMAT_16_BITS and (s.mix_rate == 44100 or s.mix_rate == 22050) and not s.stereo, "%s.wav is 44.1 or import-tuned 22.05 kHz mono 16-bit" % wav_name)
	return s


func _peak_db(s: AudioStreamWAV, stride: int) -> float:
	var d := s.data
	var peak := 1
	var i := 0
	var n := d.size() / 2
	while i < n:
		var v := absi(d.decode_s16(i * 2))
		if v > peak:
			peak = v
		i += stride
	return 20.0 * log(float(peak) / 32768.0) / log(10.0)


# ------------------------------------------------------------------ mix headroom
## Float samples of a sound (empty when it is missing).
func _pcm(wav_name: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var path := "res://assets/audio/%s.wav" % wav_name
	var s := load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
	if s == null:
		return out
	var d := s.data
	var n := d.size() / 2
	out.resize(n)
	for i in n:
		out[i] = float(d.decode_s16(i * 2)) / 32768.0
	return out


## Peak of the events summed the way Sfx plays them: POOL AudioStreamPlayers used round robin, and a new play() on a busy player cuts
## the sound that was on it. events: Array of [sound name, start second], sorted by time.
func _pool_peak(sounds: Dictionary, events: Array) -> float:
	var rate := 44100
	var total := 0
	for e: Array in events:
		var len_e := (sounds[e[0]] as PackedFloat32Array).size()
		total = maxi(total, int(float(e[1]) * rate) + len_e)
	var buf := PackedFloat32Array()
	buf.resize(total)
	for i in events.size():
		var e: Array = events[i]
		var t0 := int(float(e[1]) * rate)
		var data: PackedFloat32Array = sounds[e[0]]
		var end := t0 + data.size()
		if i + POOL < events.size():
			end = mini(end, int(float((events[i + POOL] as Array)[1]) * rate))
		for k in range(t0, end):
			buf[k] += data[k - t0]
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	return peak


## The reviewers' worst cases: sustained fire (28 shots at the 0.11 s fire interval) and a 3 s firefight with hits, an explosion and a
## hurt on top must stay clear of 0 dBFS on the Master bus, without any limiter.
func _mix() -> void:
	var sounds := {}
	for n in ["shot", "enemy_shot", "hit", "hurt", "boom"]:
		sounds[n] = _pcm(n)
	for n in sounds:
		if (sounds[n] as PackedFloat32Array).is_empty():
			return
	var rapid := []
	for k in 28:
		rapid.append(["shot", k * 0.11])
	var fight := []
	for k in 20:
		fight.append(["shot", k * 0.11])
	for k in 4:
		fight.append(["enemy_shot", 0.3 + k * 0.5])
	for k in 8:
		fight.append(["hit", 0.2 + k * 0.25])
	fight.append(["boom", 1.0])
	fight.append(["hurt", 1.2])
	fight.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	var rapid_peak := _pool_peak(sounds, rapid)
	var fight_peak := _pool_peak(sounds, fight)
	TestLib.check(rapid_peak < 0.5, "28 shots at the fire interval peak at %.1f dBFS (below -6)" % (20.0 * log(maxf(rapid_peak, 1e-6)) / log(10.0)))
	TestLib.check(fight_peak < 0.8, "a 3 s firefight (shots, hits, explosion, hurt) peaks at %.1f dBFS (below -2): no clipping" % (20.0 * log(maxf(fight_peak, 1e-6)) / log(10.0)))
