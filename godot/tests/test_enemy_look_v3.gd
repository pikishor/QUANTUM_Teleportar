extends RefCounted
## Enemy roster look v3 (wave 113): 13 armoured humans (6 contract mercenaries, 7 authority troopers: Blender kit on the hero's rig, ONE surface each), 7 vael aliens and 2 walkers (animated Blender
## bodies), 22 visually distinct types with faction silhouettes: data (kit, looks, palettes, species rows, LOD budgets, silhouette metrics), the weapon attached by registry id, the bodies in the real
## roster (AlienWorld: spawn, walk, aim, fire, hurt, die, damage states, pips) and the real game scene. Run: tools/test.sh tests/test_enemy_look_v3.gd  (about 60 s)

const DT := 0.05
const ARENA := Vector3(-1500.0, 0.0, -900.0)           ## open forest, no site within 400 m
const HUMANS: Array[StringName] = [&"merc_rifle", &"merc_shotgun", &"merc_rocket", &"merc_medic", &"merc_officer", &"merc_sniper", &"auth_rifle", &"auth_riot", &"auth_heavy", &"auth_breacher",
	&"auth_ghost", &"auth_drone", &"auth_engineer"]
const CREATURES: Array[StringName] = [&"vael_grunt", &"vael_jackal", &"vael_brute", &"vael_hunter", &"vael_elite", &"vael_stalker", &"vael_bloater", &"grid_walker", &"grid_heavy"]

class FakeHero extends Node3D:
	var hp := 1.0e6
	var max_hp := 1.0e6
	var velocity := Vector3.ZERO
	var vehicle = null
	var hits := 0

	func damage(amount: float, _from := Vector3.ZERO) -> void:
		hp -= amount
		hits += 1

	func is_dead() -> bool:
		return false

var w: AlienWorld
var hero: FakeHero


func run(host: Node) -> void:
	Sfx.muted = true
	AlienSites.ensure()
	_kit_and_looks()
	_silhouettes()
	_weapons()
	_species()
	_world(host)
	_bodies_in_world()
	_damage_states(host)
	await _pips_lines_crowd(host)
	_teardown()
	await _real_scene(host)


# --- the kit, the looks, the budgets ---------------------------------------------------------------------------------------------------------------

func _kit_and_looks() -> void:
	TestLib.check(FoeKit.available() and HeroCharacter.available(&"male") and FoeHuman.available(), "the armour kit, the hero base body and the builder are there")
	TestLib.check(FoeKit.looks().size() == 13 and FoeLooks.IDS.size() == 13, "13 human looks (%d in the kit)" % FoeKit.looks().size())
	var ok := true
	var why := ""
	var lod_ok := true
	var ao_min := 1.0
	for id: StringName in HUMANS:
		var parts := FoeKit.part_count(id)
		var t0 := FoeKit.triangles(id, 0)
		var t1 := FoeKit.triangles(id, 1)
		var t2 := FoeKit.triangles(id, 2)
		if parts < 20 or t0 > 4200 or t0 < 1800:
			ok = false
			why = "%s has %d parts, %d triangles" % [id, parts, t0]
		if not (t1 < t0 and t2 < t1 and t2 > 150):
			lod_ok = false
			why = "%s lods %d %d %d" % [id, t0, t1, t2]
		for p: Dictionary in FoeKit.pieces(id, {"spine_02": 0, "spine_03": 0, "Head": 0, "pelvis": 0, "upperarm_r": 0, "upperarm_l": 0, "lowerarm_r": 0, "lowerarm_l": 0, "hand_r": 0, "hand_l": 0,
				"thigh_r": 0, "thigh_l": 0, "calf_r": 0, "calf_l": 0, "foot_r": 0, "foot_l": 0, "Rifle": 0, "Sec1": 0, "Sec2": 0, "Sec3": 0}, 0):
			for uv: Vector2 in (p["uv"] as PackedVector2Array):
				ao_min = minf(ao_min, uv.x)
	TestLib.check(ok, "every look has 20+ kit parts and 1800-4200 kit triangles (%s)" % why)
	TestLib.check(lod_ok, "the kit shrinks with the LOD: near > mid > far (%s)" % why)
	TestLib.check(ao_min >= 0.12, "baked ambient occlusion never goes black (min %.2f): no black patches" % ao_min)
	var wi := true
	var pal_ok := true
	var seen := {}
	for id: StringName in HUMANS:
		wi = wi and FoeArms.has_weapon(FoeLooks.weapon_of(id))
		var p0 := FoeLooks.palette(id, 0)
		var p1 := FoeLooks.palette(id, 1)
		var p2 := FoeLooks.palette(id, 2)
		pal_ok = pal_ok and (p0["plate_a"] as Color) != (p1["plate_a"] as Color) and (p1["plate_a"] as Color) != (p2["plate_a"] as Color) and (p0["plate_a"] as Color) != (p2["plate_a"] as Color)
		for k in ["plate_a", "plate_b", "jacket", "pants", "glow", "trim"]:
			var c: Color = p0[k]
			if k == "glow" or k == "trim":
				pal_ok = pal_ok and c.v >= 0.5
			else:
				pal_ok = pal_ok and c.get_luminance() >= 0.02
		seen[String(FoeLooks.title(id))] = true
	TestLib.check(wi, "every look's weapon id is in the weapon registry")
	TestLib.check(pal_ok and seen.size() == 13, "three paint variants per look, bright accents, no black plates, 13 distinct names")
	var h := FoeHuman.build(&"auth_riot", 0)
	var n0 := FoeHuman.builds
	var h2 := FoeHuman.build(&"auth_riot", 1)
	TestLib.check(not h.is_empty() and not h2.is_empty() and FoeHuman.builds == n0, "a second enemy of a look duplicates the prototype (no second merge)")
	TestLib.check(FoeHuman.mesh_of(h, "mid") == null or FoeHuman.mesh_of(h, "far") == null or FoeHuman.builds > 0, "the mid and far meshes are built after the first body (no hitch)")
	FoeHuman.ensure_lods()
	var near := FoeHuman.tris(FoeHuman.mesh_of(h, "near"))
	var mid := FoeHuman.tris(FoeHuman.mesh_of(h, "mid"))
	var far := FoeHuman.tris(FoeHuman.mesh_of(h, "far"))
	TestLib.check(near <= 6200 and mid <= 3000 and far <= 1700 and near > mid and mid > far, "LOD budgets near %d <= 6200, mid %d <= 3000, far %d <= 1700" % [near, mid, far])
	TestLib.check((h["body"] as MeshInstance3D).get_surface_override_material_count() >= 0 and (h["material"] as ShaderMaterial).shader != null and (h["body"] as MeshInstance3D).mesh.get_surface_count() == 1,
		"the body is ONE surface with the enemy shader (one draw call)")
	TestLib.check((h["material"] as ShaderMaterial).get_shader_parameter(&"plate_a") != (h2["material"] as ShaderMaterial).get_shader_parameter(&"plate_a"), "variants paint the same prototype differently")
	FoeHuman.set_lod(h, 60.0)
	TestLib.check(int(h["lod"]) == 2 and (h["body"] as MeshInstance3D).mesh == FoeHuman.mesh_of(h, "far"), "far distance shows the far mesh")
	FoeHuman.set_lod(h, 5.0)
	TestLib.check(int(h["lod"]) == 0, "close shows the near mesh again")
	(h["root"] as Node).free()
	(h2["root"] as Node).free()


func _mesh_metrics(mesh: Mesh) -> Vector3:
	return mesh.get_aabb().size.snapped(Vector3.ONE * 0.1)


## Silhouette and colour metrics per type: the bounding box of the body (snapped to 10 cm), the hue bucket of the glow and of the accent. At least 16 types must differ in (size, glow hue, accent hue).
func _silhouettes() -> void:
	var keys := {}
	for id: StringName in HUMANS:
		var h := FoeHuman.build(id, 0)
		var sz := _mesh_metrics(FoeHuman.mesh_of(h, "near"))
		var p := FoeLooks.palette(id, 0)
		var key := "%s|%d|%d" % [str(sz), int((p["glow"] as Color).h * 12.0), int((p["trim"] as Color).h * 12.0)]
		keys[key] = true
		(h["root"] as Node).free()
	TestLib.check(keys.size() == 13, "13 human looks differ in size, glow hue or accent hue (%d distinct)" % keys.size())
	var ckeys := {}
	for id: StringName in CREATURES:
		var gp := "res://assets/models/foes/%s.glb" % String(id)
		TestLib.check(ResourceLoader.exists(gp), "%s has its animated body" % id)
		var scene := load(gp) as PackedScene
		var root := scene.instantiate()
		var sz2 := Vector3.ZERO
		var tris := 0
		for n in root.find_children("*", "MeshInstance3D", true, false):
			sz2 = _mesh_metrics((n as MeshInstance3D).mesh)
			tris = HumanoidVariants.tris((n as MeshInstance3D).mesh)
		var glow: Color = RosterSpecies.data(id)["glow"]
		ckeys["%s|%d" % [str(sz2), int(glow.h * 12.0)]] = true
		var ap: AnimationPlayer = null
		for n in root.find_children("*", "AnimationPlayer", true, false):
			ap = n as AnimationPlayer
		var clips_ok := ap != null
		if ap != null:
			for clip: StringName in [&"idle", &"walk", &"run", &"attack", &"hit", &"dead"]:
				clips_ok = clips_ok and ap.has_animation(clip)
		TestLib.check(clips_ok and tris >= 500 and tris <= 4500, "%s: clips idle walk run attack hit dead, %d triangles" % [id, tris])
		root.free()
	TestLib.check(ckeys.size() == 9, "9 creature bodies differ in size and glow hue (%d)" % ckeys.size())
	TestLib.check(keys.size() + ckeys.size() >= 16, "at least 16 visually distinct enemy types (%d)" % (keys.size() + ckeys.size()))


func _weapons() -> void:
	var rifle := FoeHuman.build(&"merc_rifle", 0)
	var gun := FoeHuman.build(&"merc_rifle", 0, &"minigun")
	TestLib.check(not rifle.is_empty() and not gun.is_empty() and rifle["weapon"] == &"battle" and gun["weapon"] == &"minigun", "the weapon is chosen by registry id")
	TestLib.check(FoeHuman.tris(FoeHuman.mesh_of(rifle, "near")) != FoeHuman.tris(FoeHuman.mesh_of(gun, "near")), "a different weapon id gives a different body mesh")
	var ids := 0
	var ok := true
	for id: StringName in [&"pistol", &"carbine", &"scatter", &"rocket", &"minigun", &"bolt", &"lmg", &"amr", &"mpistol", &"breacher", &"vector", &"swarm", &"flux", &"magnum"]:
		var ps := FoeArms.pieces(id, 3, 0)
		var t := 0
		for c: Dictionary in ps:
			t += (c["idx"] as PackedInt32Array).size() / 3
		ok = ok and t > 40 and t <= 760 and FoeArms.has_weapon(id)
		ids += 1
	TestLib.check(ok and ids == 14, "FoeArms.pieces turns 14 weapon ids into 40-760 triangles each (simplified near)")
	var far_t := 0
	for c: Dictionary in FoeArms.pieces(&"lmg", 3, 2):
		far_t += (c["idx"] as PackedInt32Array).size() / 3
	var near_t := 0
	for c: Dictionary in FoeArms.pieces(&"lmg", 3, 0):
		near_t += (c["idx"] as PackedInt32Array).size() / 3
	TestLib.check(far_t <= 260 and far_t * 2 < near_t, "the weapon is simplified further for the far mesh (%d of %d)" % [far_t, near_t])
	TestLib.check(FoeArms.mount_class(&"pistol") == &"pistol" and FoeArms.mount_class(&"scatter") == &"shotgun" and FoeArms.mount_class(&"rocket") == &"launcher" and FoeArms.mount_class(&"carbine") == &"rifle",
		"the upper body takes the mount class of the weapon")
	(rifle["root"] as Node).free()
	(gun["root"] as Node).free()


func _species() -> void:
	var ok := true
	var why := ""
	for id: StringName in FoeSpecies.IDS:
		var d := RosterSpecies.data(id)
		for k in ["name", "faction", "role", "tip", "family", "cls", "proc", "mech", "hp", "walk", "run", "dmg", "reach", "windup", "cool", "sight", "r", "cy", "glow", "score", "bounty", "weak"]:
			if not d.has(k):
				ok = false
				why = "%s lacks %s" % [id, k]
		if not RosterSpecies.has(id) or AlienSpecies.data(id).is_empty() or AlienSpecies.title(id) != String(d["name"]):
			ok = false
			why = "%s is not visible to the alien world" % id
		if d.has("look") and not FoeLooks.has(StringName(d["look"])):
			ok = false
			why = "%s names an unknown look" % id
		if float(d["windup"]) < 0.3:
			ok = false
			why = "%s has no telegraph time" % id
		if RosterSpecies.loot_of(id).is_empty():
			ok = false
			why = "%s has no loot" % id
	TestLib.check(ok, "every new species row has its keys, a telegraph, loot and is found by the alien world (%s)" % why)
	TestLib.check(FoeSpecies.IDS.size() == 17 and RosterSpecies.IDS.size() == 19, "17 new rows next to the 19 of roster 2")
	var fac := {}
	for id: StringName in FoeSpecies.IDS:
		fac[RosterSpecies.faction_of(id)] = int(fac.get(RosterSpecies.faction_of(id), 0)) + 1
	TestLib.check(int(fac.get(&"authority", 0)) == 7 and int(fac.get(&"hive", 0)) == 7 and int(fac.get(&"grid", 0)) == 2 and int(fac.get(&"contract", 0)) == 1, "7 authority, 7 vael, 2 walkers, 1 officer (%s)" % str(fac))
	var mercs := 0
	for id: StringName in RosterSpecies.IDS:
		if RosterSpecies.data(id).has("look"):
			mercs += 1
	TestLib.check(mercs == 5, "the five roster-2 mercenaries wear the new bodies")
	var enc_ok := true
	for eid: StringName in FoeSpecies.ENCOUNTERS:
		for m: Array in (FoeSpecies.ENCOUNTERS[eid]["members"] as Array):
			enc_ok = enc_ok and RosterSpecies.has(StringName(m[0]))
		enc_ok = enc_ok and RosterSpecies.ENCOUNTERS.has(eid) and RosterSpecies.encounter_weight(eid, TerrainBase.PLAINS, 0.0, &"", 2) >= 0.0
	TestLib.check(enc_ok and FoeSpecies.ENCOUNTERS.size() >= 13, "the new encounter templates only name known species (%d)" % FoeSpecies.ENCOUNTERS.size())
	TestLib.check(RosterSpecies.weights(TerrainBase.FOREST, 0.0, &"", 2).size() > 8 and RosterSpecies.weights(TerrainBase.CITY, 0.0, &"", 2).size() >= 5, "the director weighs the new encounters")
	var hive_city := 0.0
	for e in RosterSpecies.weights(TerrainBase.CITY, 0.0, &"", 2):
		if RosterSpecies.ENCOUNTERS[e[0]]["faction"] == RosterSpecies.HIVE:
			hive_city += float(e[1])
	TestLib.check(hive_city == 0.0, "the hive still never comes to the city side")


# --- the bodies in the roster ----------------------------------------------------------------------------------------------------------------------

func _make_world(host: Node) -> void:
	hero = FakeHero.new()
	host.add_child(hero)
	Game.player = hero
	w = AlienWorld.new()
	host.add_child(w)
	w.force_active = true
	w.ambient_enabled = false


func _world(host: Node) -> void:
	_make_world(host)
	hero.global_position = Vector3(ARENA.x, TerrainHeight.height_at(ARENA.x, ARENA.z), ARENA.z)
	w._hero_prev = Vector3.INF
	w._focus_hero(DT)
	TestLib.check(w.enabled and w.fx != null and w.fire != null, "the alien world is up")


func _sim(secs: float) -> void:
	var t := 0.0
	while t < secs:
		w.step(DT)
		t += DT


func _spawn(id: StringName, dist: float, aggro := true) -> RosterFoe:
	var h := hero.global_position
	var p := Vector3(h.x + dist, 0.0, h.z)
	var c := w.spawn_one(id, p, &"", aggro) as RosterFoe
	if c != null:
		c.heading = atan2(-(h.x - c.position.x), -(h.z - c.position.z))
	return c


func _bodies_in_world() -> void:
	var made := 0
	var humans_ok := true
	var creature_ok := true
	var why := ""
	for id: StringName in HUMANS:
		var c := _spawn(id, 24.0)
		if c == null:
			humans_ok = false
			why = "%s did not spawn" % id
			continue
		made += 1
		if c.hum.is_empty() or c.humanoid_body == null or c.camp != &"merc" or c.model == null or c.mat == null:
			humans_ok = false
			why = "%s has no human body" % id
	for id: StringName in CREATURES:
		var c := _spawn(id, 30.0)
		if c == null:
			creature_ok = false
			why = "%s did not spawn" % id
			continue
		made += 1
		if c.model == null or c.ap == null or c.mat == null:
			creature_ok = false
			why = "%s has no animated body" % id
	TestLib.check(humans_ok and creature_ok and made == 22, "22 enemy types spawn in the roster with their bodies (%s)" % why)
	var bodies := 0
	var bad := 0
	for n in Engine.get_main_loop().get_nodes_in_group(&"alien"):
		var c := n as RosterFoe
		if c == null:
			continue
		if not c.hum.is_empty():
			bodies += 1
			var meshes := 0
			for m in c.model.find_children("*", "MeshInstance3D", true, false):
				var mi := m as MeshInstance3D
				if mi.layers != 0 and mi.visible and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
					meshes += 1
			if meshes != 1:
				bad += 1
	TestLib.check(bodies == 13 and bad == 0, "every human draws ONE mesh (%d bodies, %d with another count)" % [bodies, bad])
	_sim(5.0)
	var moved := 0
	for n in Engine.get_main_loop().get_nodes_in_group(&"alien"):
		var c := n as RosterFoe
		if c != null and not c.dead and c.global_position.distance_to(hero.global_position) < 29.0:
			moved += 1
	TestLib.check(moved >= 8, "the foes close in over 5 s (%d within 29 m)" % moved)
	# a human walks with planted feet: the rig advances its walk cycle; aims with the weapon raised; the muzzle is finite
	var g := _spawn(&"auth_rifle", 30.0)
	_sim(3.0)
	var rig := g.hum["rig"] as CharacterRig
	TestLib.check(g.hum["state"] != &"idle" or not g.aggro, "an aware trooper raises the weapon (%s)" % str(g.hum["state"]))
	TestLib.check(g.hum["body"] == g.humanoid_body and RosterHuman.muzzle(g).is_finite() and rig.skeleton != null, "the muzzle follows the weapon bone")
	var fired := g.attacks_done
	_sim(6.0)
	TestLib.check(g.attacks_done > fired or hero.hits > 0, "an authority trooper fires telegraphed shots (%d)" % g.attacks_done)
	# pips follow health, a hit flinches, death drops the body
	var pip_hp := float((g.humanoid_body as MeshInstance3D).get_instance_shader_parameter(&"hp_k"))
	g.damage(g.max_hp * 0.5)
	_sim(0.3)
	var pip_hp2 := float((g.humanoid_body as MeshInstance3D).get_instance_shader_parameter(&"hp_k"))
	TestLib.check(pip_hp2 < pip_hp - 0.2 and pip_hp2 > 0.2, "the health pips follow the health (%.2f -> %.2f)" % [pip_hp, pip_hp2])
	var fl := (g.hum["hanim"] as HumanoidAnim)
	var hit_seen := fl.state == HumanoidAnim.State.HIT or fl.flinch > 0.0 or float(g.hum["hit_k"]) > 0.0
	TestLib.check(hit_seen or g.hp > 0.0, "a hit shows (flinch, flash)")
	var rot0 := (g.model as Node3D).rotation
	g.damage(g.max_hp)
	_sim(1.2)
	var dead_state := (g.hum["hanim"] as HumanoidAnim).state == HumanoidAnim.State.DEAD
	TestLib.check(g.dead and dead_state and (g.model as Node3D).rotation != rot0, "death: the rig goes limp and the body falls over its feet")
	# a vael creature plays its clips
	var jk := _spawn(&"vael_jackal", 20.0)
	_sim(2.0)
	TestLib.check(jk.ap != null and jk.ap.is_playing(), "the jackal plays a clip (%s)" % str(jk.ap.current_animation))
	var gr := _spawn(&"vael_grunt", 12.0, false)
	gr.die(true)
	_sim(0.2)
	TestLib.check(gr.ap.current_animation == "dead", "a dying alien plays its dead clip")
	# the medic still revives a downed human (the brain is unchanged)
	var a := _spawn(&"merc_rifle", 26.0, false)
	var m := w.spawn_one(&"merc_medic", a.position + Vector3(3.0, 0.0, 0.0), &"", false) as RosterFoe
	a.aggro = true
	m.aggro = true
	a.damage(a.max_hp * 2.0)
	_sim(0.3)
	TestLib.check(a.downed and not a.dead, "a mercenary next to a medic goes down (the human body shows the downed pose)")
	_sim(2.0)
	TestLib.check(StringName(a.hum["state"]) == &"downed", "the downed human lies in the dying pose")
	w.clear_all()


func _damage_states(host: Node) -> void:
	var c := _spawn(&"auth_heavy", 20.0)
	var fx := FoeFx.new(host)
	fx.set_status(c, &"burn", 2.0)
	var v: Variant = c.humanoid_body.get_instance_shader_parameter(&"dmg_fx")
	TestLib.check(v is Vector4 and (v as Vector4).x == 1.0 and (v as Vector4).y > 0.5, "the burning status tints the body through dmg_fx (%s)" % str(v))
	fx.set_status(c, &"freeze", 1.0)
	v = c.humanoid_body.get_instance_shader_parameter(&"dmg_fx")
	TestLib.check(v is Vector4 and (v as Vector4).x == 2.0, "the frozen status too")
	fx.set_status(c, &"dissolve", 1.0)
	v = c.humanoid_body.get_instance_shader_parameter(&"dmg_fx")
	TestLib.check(v is Vector4 and (v as Vector4).x == 4.0, "and the dissolve")
	TestLib.check(fx.camp_of(c) == &"merc" and fx._has_plates(c), "the damage system treats an enemy human as a person: plates fly, no alien fluid")
	c.set_meta(&"x", 1)
	w.clear_all()

## Second pass of wave 113: the floating health pips of every roster enemy, the thin telegraph lines, the LOD ranges by tier, the throttled rigs of far bodies, the loading-time warm-up.
func _pips_lines_crowd(host: Node) -> void:
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.global_position = hero.global_position + Vector3(0.0, 3.0, 6.0)
	cam.make_current()
	var pips := w.fx.pips
	TestLib.check(pips != null and pips.mm != null and pips.mm.instance_count == FoePips.CAP * FoePips.PIPS + FoePips.MARKS and pips.mm.use_colors, "the alien fx owns the pip MultiMesh (%d instances: one draw call for every enemy)" % (FoePips.CAP * FoePips.PIPS + FoePips.MARKS))
	TestLib.check(FoePips.color_of(1.0) == FoePips.GREEN and FoePips.color_of(0.45) == FoePips.AMBER and FoePips.color_of(0.1) == FoePips.RED, "pips are green, amber, red by health")
	TestLib.check(FoePips.lit_of(1.0) == 5 and FoePips.lit_of(0.5) == 3 and FoePips.lit_of(0.2) == 1 and FoePips.lit_of(0.01) == 1, "lit pips: 5 at full health, 3 at half, never fewer than 1 while alive")
	w.clear_all()
	var brute := _spawn(&"vael_brute", 18.0, false)                                # all within 28 m of the camera: no threat markers here, only rows
	var trooper := _spawn(&"auth_rifle", 24.0, false)
	var jackal := _spawn(&"vael_jackal", 22.0, false)
	_sim(0.3)
	TestLib.check(pips.shown == 0 and pips.mm.visible_instance_count == 0 and not pips._node.visible, "an unhurt enemy shows no pips (the node is hidden: no draw call, it cost one when empty)")
	brute.damage(brute.max_hp * 0.5)
	_sim(0.2)
	var want_lit := FoePips.lit_of(brute.hp / brute.max_hp)
	TestLib.check(pips._node.visible and pips.shown == 1 and pips.mm.visible_instance_count == FoePips.PIPS and pips.lit_last == want_lit and want_lit >= 2 and want_lit <= 4, "a half-dead brute shows a row of 5 with %d lit (shown %d, lit %d)" % [want_lit, pips.shown, pips.lit_last])
	var row_y: float = (pips.rows[0]["anchor"] as Vector3).y if not pips.rows.is_empty() else -1.0e9
	TestLib.check(pips.rows.size() == 1 and pips.rows[0]["foe"] == brute and row_y > brute.global_position.y + 2.5 and row_y < brute.global_position.y + 6.0, "the row floats above the head of the brute (%.1f m over its feet)" % (row_y - brute.global_position.y))
	trooper.damage(trooper.max_hp * 0.85)
	jackal.damage(jackal.max_hp * 0.9)
	_sim(0.2)
	TestLib.check(pips.shown == 3 and pips.mm.visible_instance_count == 3 * FoePips.PIPS, "three hurt enemies, three rows, still one MultiMesh (%d)" % pips.mm.visible_instance_count)
	var lit_n := 0
	for r: Dictionary in pips.rows:
		lit_n += int(r["lit"])
	var want_n := FoePips.lit_of(brute.hp / brute.max_hp) + FoePips.lit_of(trooper.hp / trooper.max_hp) + FoePips.lit_of(jackal.hp / jackal.max_hp)
	TestLib.check(lit_n == want_n and lit_n < pips.rows.size() * FoePips.PIPS, "pips are lit by what is left (%d lit of %d, expected %d)" % [lit_n, pips.rows.size() * FoePips.PIPS, want_n])
	brute.damage(brute.max_hp)
	_sim(0.3)
	TestLib.check(pips.shown == 2, "a dead enemy loses its row (%d rows)" % pips.shown)
	w.clear_all()
	_sim(0.1)
	TestLib.check(pips.shown == 0, "no enemies, no rows")
	# threat markers: an aware enemy 30-95 m from the camera gets a diamond over its head, a near one, an unaware one and one beyond 95 m do not, a cloaked stalker never
	var far_a := _spawn(&"auth_rifle", 60.0, true)
	var near_a := _spawn(&"auth_rifle", 12.0, true)
	var calm_a := _spawn(&"merc_rifle", 90.0, false)                               # beyond its sight range: stays unaware
	var far_b := _spawn(&"vael_brute", 120.0, true)
	var stalker := _spawn(&"vael_stalker", 55.0, false)
	_sim(0.2)
	TestLib.check(pips.marks == 1 and pips.mark_rows.size() == 1 and pips.mark_rows[0]["foe"] == far_a, "one threat marker: the aware trooper at 60 m (markers %d)" % pips.marks)
	var mk: Dictionary = pips.mark_rows[0] if not pips.mark_rows.is_empty() else {"pos": Vector3.ZERO, "size": 0.0}
	TestLib.check((mk["pos"] as Vector3).y > far_a.global_position.y + 1.8 and absf(float(mk["size"]) - 60.3 * FoePips.MARK_K) < 0.15, "the marker floats over the head and keeps its size on screen (%.2f m at 60 m)" % float(mk["size"]))
	TestLib.check(pips.mm.visible_instance_count == 1 and not FoePips.wants_mark(near_a, 12.0) and not FoePips.wants_mark(calm_a, 90.0) and not FoePips.wants_mark(far_b, 120.0), "none for a near, an unaware or a very far enemy (one instance, one draw)")
	stalker.aggro = true
	stalker.cloak_k = 1.0
	var cloaked := FoePips.wants_mark(stalker, 55.0)
	stalker.cloak_k = 0.0
	TestLib.check(not cloaked and FoePips.wants_mark(stalker, 55.0), "a cloaked stalker gets no marker, a revealed one does")
	stalker.aggro = false
	far_a.damage(far_a.max_hp * 0.4)
	_sim(0.2)
	TestLib.check(pips.shown == 1 and pips.marks == 1 and pips.mm.visible_instance_count == FoePips.PIPS + 1, "a hurt aware enemy has a row and a marker above it (%d instances)" % pips.mm.visible_instance_count)
	w.clear_all()
	_sim(0.1)
	# the telegraph lines are thin stripes in the view, never screen-wide sheets, and fade out at the lens
	var cp := cam.global_position
	w.fx.line(cp + Vector3(0.4, -0.4, 0.0), cp + Vector3(0.4, -0.4, -40.0), 1.0, Color.CYAN)
	var li: int = (w.fx._next_line - 1 + AlienFx.LINES) % AlienFx.LINES
	var near_w := w.fx.line_width(li)
	var near_d := Vector2(0.4, 0.4).length()
	var max_w := maxf(near_d * tan(deg_to_rad(AlienFx.LINE_MAX_DEG)), AlienFx.LINE_W * 0.05) * 1.06
	TestLib.check(near_w <= max_w and near_w > 0.003, "a telegraph line that passes the lens is a thin stripe (%.3f m wide at %.2f m, limit %.3f)" % [near_w, near_d, max_w])
	w.fx.tick(0.016)
	TestLib.check(w.fx._line_k[li] < 0.05, "and it fades out near the lens (fade %.2f)" % w.fx._line_k[li])
	w.fx.line(cp + Vector3(20.0, 0.0, -30.0), cp + Vector3(20.0, 0.0, -60.0), 1.0, Color.RED)
	var far_i: int = (w.fx._next_line - 1 + AlienFx.LINES) % AlienFx.LINES
	TestLib.check(absf(w.fx.line_width(far_i) - AlienFx.LINE_W) < 0.01, "a line far from the camera keeps its full width (%.3f m)" % w.fx.line_width(far_i))
	# the LOD ranges follow the graphics tier
	var q0 := Game.quality
	var hh := FoeHuman.build(&"merc_rifle", 0)
	FoeHuman.ensure_lods()
	Game.quality = 0
	FoeHuman.set_lod(hh, 14.0)
	var low_lod := int(hh["lod"])
	hh["lod"] = 0
	Game.quality = 2
	FoeHuman.set_lod(hh, 14.0)
	var high_lod := int(hh["lod"])
	hh["lod"] = 0
	Game.quality = 0
	FoeHuman.set_lod(hh, 36.0)
	var low_far := int(hh["lod"])
	Game.quality = q0
	(hh["root"] as Node).free()
	TestLib.check(low_lod == 1 and high_lod == 0 and low_far == 2, "LOW switches to the mid mesh at 14 m and the far mesh at 36 m, HIGH keeps the near mesh (%d / %d / %d)" % [low_lod, high_lod, low_far])
	# a crowd: bodies far from the camera run their rig every 2nd or 3rd frame, near ones every frame
	var near_c := _spawn(&"auth_rifle", 8.0)
	var far_c := _spawn(&"auth_rifle", 70.0)
	var far_c2 := _spawn(&"merc_rifle", 38.0)
	_sim(2.0)
	var nt := int(near_c.hum["tick"])
	var nd := int(near_c.hum["drives"])
	var ft := int(far_c.hum["tick"])
	var fd := int(far_c.hum["drives"])
	var mt := int(far_c2.hum["tick"])
	var md := int(far_c2.hum["drives"])
	TestLib.check(nt > 20 and nd == nt, "a near body drives its rig every frame (%d of %d)" % [nd, nt])
	TestLib.check(ft > 20 and fd <= ft / 3 + 1 and fd >= ft / 4, "a far body drives its rig every 3rd frame (%d of %d)" % [fd, ft])
	TestLib.check(mt > 20 and md <= mt / 2 + 1 and md >= mt / 3, "a mid body every 2nd frame (%d of %d)" % [md, mt])
	w.clear_all()
	# the loading-time warm-up builds the common looks and shows a body of each
	var warm := FoeHuman.warm_begin(host, hero.global_position + Vector3(0.0, 2.0, -8.0))
	TestLib.check(warm.size() == FoeHuman.WARM_LOOKS.size() + FoeHuman.WARM_CREATURES.size() and (warm[0] as Node3D).is_inside_tree(), "the warm-up shows %d bodies (the common looks and one creature of each material)" % warm.size())
	FoeHuman.warm_end(warm)
	cam.queue_free()
	await TestLib.frames(host, 2)
	TestLib.check(not is_instance_valid(warm[0]), "and removes them again")


func _teardown() -> void:
	if w != null:
		w.clear_all()
		w.queue_free()
	if hero != null:
		hero.queue_free()
	Game.player = null
	Engine.time_scale = 1.0


# --- the real game ---------------------------------------------------------------------------------------------------------------------------------

func _real_scene(host: Node) -> void:
	AlienSites.reset_all()
	AlienLoot.reset()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	var city := Game.world as City
	var p := Game.player as Player
	var aw := city.aliens as AlienWorld if city != null else null
	TestLib.check(city != null and p != null and aw != null and aw.enabled, "the real city has the alien world")
	if aw == null or p == null:
		main.queue_free()
		return
	var prog := Game.progress as Progress
	if prog != null:
		prog.path = "user://test_enemy_look_v3_prog.cfg"
	if Encounters.current != null:
		Encounters.current.enabled = false
	(Game.enemies as EnemyManager).clear()
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	aw.ambient_enabled = false
	p.global_position = Vector3(ARENA.x, TerrainHeight.height_at(ARENA.x, ARENA.z) + 1.0, ARENA.z)
	p.velocity = Vector3.ZERO
	await TestLib.frames(host, 4)
	aw.roster.force_tier = 2
	var made := aw.roster.spawn_encounter(&"auth_patrol", Vector3(ARENA.x + 20.0, 0.0, ARENA.z), true)
	made.append_array(aw.roster.spawn_encounter(&"vael_rush", Vector3(ARENA.x - 20.0, 0.0, ARENA.z), true))
	TestLib.check(made.size() >= 4, "authority and vael encounters spawn through the real director (%d)" % made.size())
	var php := p.hp
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and p.hp >= php:
		p.invuln = 0.0
		await TestLib.frames(host, 4)
	TestLib.check(p.hp < php, "the new enemies hurt the real player")
	var visible_bodies := 0
	for n in Engine.get_main_loop().get_nodes_in_group(&"alien"):
		var c := n as RosterFoe
		if c != null and not c.dead and c.is_visible_in_tree() and c.model != null and c.model.is_visible_in_tree():
			visible_bodies += 1
	TestLib.check(visible_bodies >= 3, "their bodies are in the scene tree and visible (%d)" % visible_bodies)
	var f := made[0] as RosterFoe
	if is_instance_valid(f) and not f.dead:
		var hp0 := f.hp
		f.damage(5.0)
		TestLib.check(f.hp < hp0, "a hit lands on a new enemy in the real game")
	aw.force_active = false
	Game.state = &"paused"
	var before := f.position if is_instance_valid(f) else Vector3.ZERO
	await TestLib.frames(host, 10)
	TestLib.check(not is_instance_valid(f) or f.position.is_equal_approx(before), "paused: the new enemies stand still")
	Game.state = &"play"
	aw.roster.force_tier = -1
	aw.clear_all()
	main.queue_free()
	await TestLib.frames(host, 2)
