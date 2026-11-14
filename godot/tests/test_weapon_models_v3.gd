extends RefCounted
## The weapon kit (wave 114): every one of the game's weapons has its own model made by godot/tools/blender/weapon_kit.py. Run: tools/test.sh tests/test_weapon_models_v3.gd
## Data (all ids): a glb with LOD0 and LOD1 inside the triangle budget, one surface, valid material layers, no black or untextured surfaces, the PBR material with its three texture arrays, a muzzle at the
## origin, grips and an eject port, distinct silhouettes. Real scene: the hero holds a kit weapon with the kit's PBR material, a shot kicks the slide, a reload takes the magazine out, an empty
## pistol keeps its slide back, a rotary gun spins up, the enemy carries the same model (LOD1) through FoeArms, the build() node has its markers, the shell leaves the weapon's own eject port.

const DT := 1.0 / 60.0
const LOD0_MAX := 5200
const LOD1_MAX := 2400


func run(host: Node) -> void:
	_data()
	_build_api()
	await _live(host)


func _data() -> void:
	var ids := WeaponDefs.all_ids()
	TestLib.check(ids.size() >= 200, "200 or more weapons (%d)" % ids.size())
	var meta := WeaponModels.kit_meta()
	var sigs := {}
	var tot0 := 0
	var tot1 := 0
	var parts_seen := {}
	var mat := WeaponModels.pbr_material()
	TestLib.check(mat is ShaderMaterial and mat != WeaponModels.material(), "the kit has its own PBR material")
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		TestLib.check(sm.shader != null and sm.get_shader_parameter(&"tex_alb") != null and sm.get_shader_parameter(&"tex_orm") != null and sm.get_shader_parameter(&"tex_nrm") != null,
				"the PBR material has its shader and the three texture arrays")
		var arr = sm.get_shader_parameter(&"tex_alb")
		TestLib.check(arr is TextureLayered and (arr as TextureLayered).get_layers() >= 28, "the albedo array holds the material swatches (%d layers)" % ((arr as TextureLayered).get_layers() if arr is TextureLayered else 0))
	for id: StringName in ids:
		TestLib.check(WeaponModels.has_model(id) and WeaponModels.path(id) != "", "%s has a kit model" % id)
		var m: Dictionary = meta.get(String(id), {})
		var t0 := int(m.get("tris0", 0))
		var t1 := int(m.get("tris1", 0))
		tot0 += t0
		tot1 += t1
		TestLib.check(t0 >= 250 and t0 <= LOD0_MAX, "%s LOD0 triangles in budget (%d)" % [id, t0])
		TestLib.check(t1 >= 40 and t1 <= LOD1_MAX and t1 < t0, "%s LOD1 exists and is lighter (%d < %d)" % [id, t1, t0])
		for pn: String in m.get("parts", []):
			parts_seen[pn] = true
		var lod0 := WeaponModels.mesh(id, 0)
		var lod1 := WeaponModels.mesh(id, 1)
		TestLib.check(lod0 != null and lod0.get_surface_count() == 1 and lod1 != null and lod1.get_surface_count() == 1 and lod0 != lod1, "%s: LOD0 and LOD1 are two one-surface meshes" % id)
		if lod0 == null:
			continue
		var bb := lod0.get_aabb()
		TestLib.check(bb.size.z > 0.06 and bb.size.z < 1.6 and bb.size.y > 0.02 and bb.position.z > -0.03 and bb.position.z < 0.05, "%s: %.2f m long, its tip at the origin (z %.3f)" % [id, bb.size.z, bb.position.z])
		sigs["%d_%d_%d_%d" % [roundi(bb.size.x * 80.0), roundi(bb.size.y * 80.0), roundi(bb.size.z * 40.0), t0 / 60]] = true
		# no black, no untextured surface: every vertex has a layer of the swatch array and a base colour (or it glows)
		var a := lod0.surface_get_arrays(0)
		var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
		var bad_layer := 0
		var black := 0
		var empty_ao := 0
		for i in cols.size():
			var layer := int(roundf(uv[i].x * 255.0))
			if layer < 0 or layer > 31:
				bad_layer += 1
			var c := cols[i]
			if maxf(c.r, maxf(c.g, c.b)) < 0.012 and c.a < 0.3:
				black += 1
			if uv2[i].x < 0.02:
				empty_ao += 1
		TestLib.check(cols.size() > 100 and uv.size() == cols.size() and uv2.size() == cols.size(), "%s carries layer, tint and AO on every vertex" % id)
		TestLib.check(bad_layer == 0 and black <= cols.size() / 50, "%s: valid material layers (%d bad) and no black surface (%d of %d vertices)" % [id, bad_layer, black, cols.size()])
		TestLib.check(lod0.surface_get_material(0) == WeaponModels.pbr_material() and WeaponModels.material_for(id) == WeaponModels.pbr_material(), "%s is drawn with the PBR material" % id)
		for k: String in ["gr", "gl", "eject", "aim", "mag", "optic", "laser"]:
			var pt := WeaponModels.point(id, k)
			TestLib.check(pt.length() < 2.0 and is_finite(pt.x + pt.y + pt.z), "%s marker %s is a point (%s)" % [id, k, pt])
		var spec := WeaponModels.spec(id)
		TestLib.check(float(spec["reach"]) > 0.3 and (spec["gr"] as Vector3).z > 0.0 or WeaponDefs.class_of(id) == &"melee", "%s has grips and a reach" % id)
	TestLib.check(sigs.size() >= 190, "the models have distinct silhouettes (%d signatures among %d)" % [sigs.size(), ids.size()])
	TestLib.check(tot0 / ids.size() >= 1500, "LOD0 is detailed: %d triangles on average" % (tot0 / ids.size()))
	TestLib.check(tot1 * 10 / ids.size() <= 9000, "LOD1 is light: %d triangles on average" % (tot1 / ids.size()))
	for pn in ["slide", "mag", "pump", "rotor", "hammer"]:
		TestLib.check(parts_seen.has(pn), "some weapons have a moving %s" % pn)


func _build_api() -> void:
	for id in [&"carbine", &"pistol", &"katana", &"rocket", &"gr_frag", &"bw_hunter", &"minigun", &"revolver"]:
		for lod in [0, 1]:
			var n := WeaponModels.build(id, lod)
			var body := n.get_node_or_null("Body") as MeshInstance3D
			TestLib.check(body != null and body.mesh != null and body.material_override != null, "build(%s, %d) has a Body mesh with its material" % [id, lod])
			for mk in ["Muzzle", "GripR", "GripL", "Eject", "Aim", "Mag"]:
				TestLib.check(n.get_node_or_null(mk) is Marker3D, "build(%s, %d) has the marker %s" % [id, lod, mk])
			var gr := (n.get_node("GripR") as Marker3D).position
			var bb := body.mesh.get_aabb().grow(0.35)
			TestLib.check(bb.has_point(gr), "%s: the right grip lies on the weapon (%s in %s)" % [id, gr, bb])
			TestLib.check((n.get_node("Muzzle") as Marker3D).position == Vector3.ZERO, "%s: the muzzle node sits at the origin" % id)
			n.free()
	TestLib.check(ResourceLoader.exists(WeaponModels.path(&"carbine")), "the glb of the carbine exists")


func _live(host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg.bak"))
	WeaponDefs.reset_unlocked()
	WeaponDefs.hero_mode = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	Game.state = &"play"
	var p := Game.player as Player
	var w := p.weapon
	TestLib.check(p != null and w != null, "the game is up")
	var body := p.body
	TestLib.check(body != null and body.hero_mat != null, "the hero has his superhero body")
	TestMode.god = true
	# the hero holds a kit weapon with his own copy of the PBR material and the kit's look scale
	for id in [&"pistol", &"a_pillar", &"scatter", &"rail"]:
		w.switch_to(id, true)
		await TestLib.frames(host, 4)
		var look := body.find_child("WeaponLook", true, false) as MeshInstance3D
		TestLib.check(look != null and look.mesh == WeaponModels.mesh(id) and look.visible, "the hero holds the %s" % id)
		TestLib.check(look.material_override is ShaderMaterial and look.material_override != WeaponModels.pbr_material(), "%s: the hero's weapon has his own PBR material copy" % id)
		TestLib.check(look.scale.is_equal_approx(WeaponModels.look_scale(id)), "%s is drawn with the kit's look scale %s" % [id, look.scale])
		var g := WeaponModels.grip_offsets(id, WeaponModels.look_scale(id))
		TestLib.check(body.rig.grip_off_l.is_equal_approx(g[0]) and body.rig.grip_off_r.is_equal_approx(g[1]), "%s: both hands are on the grips of the drawn weapon" % id)
	# a shot kicks the slide of a pistol and it stays back on an empty gun
	w.switch_to(&"pistol", true)
	await TestLib.frames(host, 4)
	var mat := (body.find_child("WeaponLook", true, false) as MeshInstance3D).material_override as ShaderMaterial
	body._handling.fired()
	body._handling.update(DT, -1.0, 6)
	var kick := (mat.get_shader_parameter(&"anim_slide") as Vector3).z
	TestLib.check(kick > 0.012, "a shot kicks the pistol slide back (%.3f m)" % kick)
	for i in 30:
		body._handling.update(DT, -1.0, 6)
	TestLib.check(absf((mat.get_shader_parameter(&"anim_slide") as Vector3).z) < 0.002, "the slide returns")
	body._handling.fired()
	for i in 30:
		body._handling.update(DT, -1.0, 0)
	TestLib.check((mat.get_shader_parameter(&"anim_slide") as Vector3).z > 0.02, "an empty pistol holds its slide back")
	# the magazine leaves the weapon during a reload and comes back
	body._handling.update(DT, 0.25, 0)
	var mag_mid := (mat.get_shader_parameter(&"anim_mag") as Vector3).y
	body._handling.update(DT, 0.45, 0)
	var hid := float(mat.get_shader_parameter(&"hide_mag"))
	body._handling.update(DT, 0.95, 20)
	var mag_end := (mat.get_shader_parameter(&"anim_mag") as Vector3).y
	TestLib.check(mag_mid < -0.05 and hid > 0.5 and absf(mag_end) < 0.001, "the magazine slides out (%.3f), is away while the hand fetches a new one (hide %.0f) and is back at the end (%.3f)" % [mag_mid, hid, mag_end])
	# a pump gun pumps, a rotary gun spins, a revolver turns its cylinder
	w.switch_to(&"scatter", true)
	await TestLib.frames(host, 4)
	var pm := (body.find_child("WeaponLook", true, false) as MeshInstance3D).material_override as ShaderMaterial
	body._handling.fired()
	var peak := 0.0
	for i in 60:
		body._handling.update(DT, -1.0, 5)
		peak = maxf(peak, (pm.get_shader_parameter(&"anim_pump") as Vector3).z)
	TestLib.check(peak > 0.04, "the shotgun pumps its forend (%.3f m)" % peak)
	w.switch_to(&"minigun", true)
	await TestLib.frames(host, 4)
	var rm := (body.find_child("WeaponLook", true, false) as MeshInstance3D).material_override as ShaderMaterial
	for i in 40:
		body._handling.fired()
		body._handling.update(DT, -1.0, 100)
	TestLib.check(float(rm.get_shader_parameter(&"rotor_angle")) > 6.0, "the rotary barrels spin (%.1f rad)" % float(rm.get_shader_parameter(&"rotor_angle")))
	w.switch_to(&"revolver", true)
	await TestLib.frames(host, 4)
	var vm := (body.find_child("WeaponLook", true, false) as MeshInstance3D).material_override as ShaderMaterial
	var a0 := float(vm.get_shader_parameter(&"rotor_angle"))
	body._handling.fired()
	body._handling.update(DT, -1.0, 5)
	TestLib.check(float(vm.get_shader_parameter(&"rotor_angle")) - a0 > 0.9, "a revolver turns one chamber per shot")
	# the glow kicks on a shot through the hero's own material
	body.fire_flash(1.0)
	TestLib.check(float(vm.get_shader_parameter(&"glow")) > 2.0, "the trim of the weapon kicks light on a shot")
	# the enemy carries the same model (LOD1) in his hands
	var pieces := FoeArms.pieces(&"battle", 0, 0)
	var tris := 0
	for pc in pieces:
		tris += (pc["idx"] as PackedInt32Array).size() / 3
	TestLib.check(pieces.size() > 0 and tris > 60 and tris <= FoeArms.TARGET_TRIS[0] + 40, "an enemy carries the kit's battle rifle (%d triangles, %d pieces)" % [tris, pieces.size()])
	var setup := FoeArms.setup(null, null, &"battle")
	TestLib.check(float(setup["reach"]) > 0.5 and absf(float(setup["muzzle_shift"])) < 0.6, "the enemy's grips and muzzle come from the kit (%s)" % setup)
	# a shell leaves the eject port of the weapon in the hand
	w.switch_to(&"a_pillar", true)
	await TestLib.frames(host, 4)
	FX.casings.clear()
	var n0: int = FX.casings.ejected
	w._eject_shell()
	TestLib.check(FX.casings.ejected == n0 + 1, "a casing is ejected from the kit weapon")
	main.queue_free()
	WeaponDefs.hero_mode = false
	await TestLib.frames(host, 2)
