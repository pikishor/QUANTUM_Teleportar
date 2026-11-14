extends RefCounted
## DAMAGE EVERYWHERE (wave 113) in the REAL game scene: every damage system triggers, every pool respects its cap, nothing is waited on by frame counts (game time is advanced by hand, counters are read).
##   * the switch and the caps: every pool has a cap per tier that grows with the tier;
##   * structure damage (scripts/combat/structure_damage.gd): the blast table gives each weapon its destruction level (0 flash, 1 grenade, 2 rocket, 3 bunker buster), a blast leaves windows, scars,
##     craters and breaches in the structure pool of the mark ring (LOW 8, MED 16, HIGH 24), the same place takes staged damage (a second rocket finishes what the first began), the marks expire;
##   * bullet holes by material (concrete, metal, glass, wood, asphalt) in the one decal ring with a quota per material;
##   * the debris pool (Breakables.fling): shaped pieces, the ring is as long as the tier allows, props wear in stages, broken props give no cover (EnemyCover);
##   * people (FoeFx): armour plates break off at thresholds, a leg shot limps, fluid splatters on the street and the wall behind, burning / frozen / shocked / dissolving deaths, a blast throws a body;
##   * cars (CarFx): bullet holes (capped per car), a burst of rounds cracks and then shatters the glass, a shot tyre goes flat, the hood pops, a wreck stays and burns (flames and smoke from the shared cloud);
##   * the real chain: the hero's weapon, a real enemy, the observer sees Player.hit_confirmed (no enemy script was changed).
## Run: tools/test.sh tests/test_damage_everywhere.gd

var host: Node
var mgr: VehicleManager
var em: EnemyManager
var floor_body: StaticBody3D
var wall_body: StaticBody3D
const ORIGIN := Vector3(-700.0, 0.0, 400.0)


func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Game.L_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	host.add_child(b)
	b.global_position = pos
	return b


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


## Game time without waiting: the layers' own clocks in steps of 0.1 s (and the damage world's own tick).
func _advance(seconds: float) -> void:
	for i in roundi(seconds / 0.1):
		FX._process(0.1)
		FX.explosions._process(0.1)
		FX.qvfx._process(0.1)
		if FX.marks.is_processing():
			FX.marks._process(0.1)
		if FX.car_debris.is_processing():
			FX.car_debris._process(0.1)
		var br := Breakables.current
		if br != null and br.is_processing():
			br._process(0.1)
		var bf := BlastFx.instance
		if is_instance_valid(bf) and bf.is_processing():
			bf._process(0.1)
		DamageWorld.current._process(0.1)


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	mgr = Game.vehicles as VehicleManager
	em = Game.enemies as EnemyManager
	var old_q := Game.quality
	TestLib.check(Dmg.enabled and DamageWorld.current != null and FX.marks != null and Breakables.current != null, "the real scene has the damage world, the marks and the debris pool")
	if DamageWorld.current == null or mgr == null or em == null:
		return
	mgr.stream_every = 1.0e9
	mgr._stream_t = 1.0e9
	em.patrol_groups().clear()
	em.clear()
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	floor_body = _box(ORIGIN + Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0))
	wall_body = _box(ORIGIN + Vector3(9.0, 4.0, 0.0), Vector3(1.0, 8.0, 30.0))      # a facade east of the blast point; its west face is at x = 8.5
	var hero := Game.player as Player
	if hero != null:
		TestMode.god = true
		hero.teleport_to(ORIGIN + Vector3(-20.0, 0.0, 0.0))                    # the camera follows the hero: every effect is judged by its distance to the camera
	await TestLib.frames(host, 5)
	FX.reset()
	Dmg.reset_stats()
	StructureDamage.reset()
	StructureDamage.reset_stats()

	_caps_table()
	_destruction_levels()
	_structure_marks()
	_structure_blasts()
	_decals_by_material()
	_debris_and_props()
	await _people()
	await _fire_and_shields()
	await _cars()
	await _real_chain()
	FX.reset()
	Game.quality = old_q
	floor_body.queue_free()
	wall_body.queue_free()


# --- the caps ------------------------------------------------------------------------------------------------------------------

func _caps_table() -> void:
	var ok := true
	for key: StringName in Dmg.CAPS:
		var row: Array = Dmg.CAPS[key]
		if row.size() != 3 or int(row[0]) > int(row[1]) or int(row[1]) > int(row[2]) or int(row[0]) < 1:
			ok = false
			print("  cap row is not LOW <= MED <= HIGH: ", key, row)
	TestLib.check(ok and Dmg.CAPS.size() >= 12, "every damage pool has a cap per tier, LOW <= MED <= HIGH (%d pools)" % Dmg.CAPS.size())
	Game.quality = 0
	var low := Dmg.cap(&"debris")
	Game.quality = 2
	var high := Dmg.cap(&"debris")
	TestLib.check(low < high and BlastMarks.cap_struct(0) < BlastMarks.cap_struct(2), "caps follow Game.quality (debris %d -> %d)" % [low, high])
	TestLib.check(Dmg.fluid_of(&"merc") == null and Dmg.fluid_of(&"vael") is Color and Dmg.fluid_of(&"gang") != Dmg.fluid_of(&"drones"), "alien fluid by camp: Vael green, gangs amber, drones cyan, mercenaries none")
	Game.quality = 1


func _destruction_levels() -> void:
	var lvl := func(id: StringName) -> int: return int((BlastTable.entry(id)["dmg"] as Dictionary)["structure"])
	TestLib.check(int(lvl.call(&"gr_blinder")) == 0 and int(lvl.call(&"gr_frag")) == 1 and int(lvl.call(&"la_rocket")) == 2 and int(lvl.call(&"la_bunker")) == 3, "every weapon has its own destruction level in the blast table (flash 0, frag 1, rocket 2, bunker buster 3)")
	var counts := [0, 0, 0, 0]
	for id in BlastTable.ids():
		var e := BlastTable.entry(id)
		if StringName(e["cat"]) in [&"grenade", &"launcher", &"mine", &"strike", &"ordnance", &"ultimate", &"world"]:
			counts[clampi(int((e["dmg"] as Dictionary)["structure"]), 0, 3)] += 1
	TestLib.check(counts[0] > 0 and counts[1] > 0 and counts[2] > 0 and counts[3] > 0, "the arsenal spreads over all four levels (%s)" % str(counts))


# --- the structure pool of the mark ring -----------------------------------------------------------------------------------------

func _structure_marks() -> void:
	for q in 3:
		Game.quality = q
		FX.reset()
		var n0 := _count_nodes(FX)
		for i in 60:
			FX.marks.crater(ORIGIN + Vector3(float(i) * 0.6, 0.0, 12.0), 2.0)
			FX.marks.breach(ORIGIN + Vector3(float(i) * 0.6, 3.0, -12.0), Vector3.BACK, 2.5)
			FX.marks.window_broken(ORIGIN + Vector3(float(i) * 0.6, 3.0, -13.0), Vector3.BACK, 2.2, 1.6)
			FX.marks.chip(ORIGIN + Vector3(float(i) * 0.6, 2.0, -14.0), Vector3.BACK, 1.5)
		TestLib.check(FX.marks.struct_live() == BlastMarks.cap_struct(q), "tier %d: the structure pool holds exactly %d marks after 240 were made (%d)" % [q, BlastMarks.cap_struct(q), FX.marks.struct_live()])
		TestLib.check(FX.marks.live_of(BlastMarks.K_SPLAT) + FX.marks.live_of(BlastMarks.K_SCORCH) == 0, "tier %d: the structure marks did not push out the other marks" % q)
		TestLib.check(_count_nodes(FX) == n0, "tier %d: 240 structure marks created no node" % q)
	# the four kinds exist and the old pool bound still holds beside the new one
	Game.quality = 1
	FX.reset()
	FX.marks.crater(ORIGIN, 3.0)
	FX.marks.breach(ORIGIN + Vector3(0.0, 3.0, 5.0), Vector3.BACK, 3.0)
	FX.marks.window_broken(ORIGIN + Vector3(0.0, 3.0, 6.0), Vector3.BACK, 2.2, 1.6)
	FX.marks.chip(ORIGIN + Vector3(0.0, 2.0, 7.0), Vector3.BACK, 1.5)
	TestLib.check(FX.marks.live_of(BlastMarks.K_CRATER) == 1 and FX.marks.live_of(BlastMarks.K_BREACH) == 1 and FX.marks.live_of(BlastMarks.K_WINDOW) == 1 and FX.marks.live_of(BlastMarks.K_CHIP) == 1, "a crater, a breach, a broken window and a spall scar are four kinds of mark")
	TestLib.check(FX.marks.visible_draw(), "structure marks share the one draw call of the ring")
	_advance(BlastMarks.LIFE_STRUCT + 5.0)
	TestLib.check(FX.marks.struct_live() == 0 and not FX.marks.visible_draw(), "structure marks end by themselves and the draw call goes with them")
	var m: Shader = load("res://assets/shaders/fx_marks.gdshader")
	TestLib.check(m.code.contains("wall breach") and m.code.contains("broken window") and m.code.contains("ground crater"), "the mark shader draws the structure kinds")


func _structure_blasts() -> void:
	Game.quality = 1
	FX.reset()
	StructureDamage.reset()
	StructureDamage.reset_stats()
	var base := ORIGIN + Vector3(3.0, 1.4, 0.0)
	# level 0 (a flash) does not touch structures
	BlastTable.apply(&"gr_blinder", base, null, {"quiet": true})
	TestLib.check(StructureDamage.applied == 0, "a blinder (level 0) leaves the buildings alone")
	# level 1: windows break and the facade is chipped, no crater
	for i in 5:
		BlastTable.apply(&"gr_frag", ORIGIN + Vector3(3.0, 1.4, float(i) * 2.0 - 4.0), null, {"quiet": true})
	TestLib.check(StructureDamage.applied == 5 and StructureDamage.windows_broken >= 1, "a frag grenade (level 1) breaks windows (%d)" % StructureDamage.windows_broken)
	TestLib.check(StructureDamage.craters_made == 0 and StructureDamage.breaches_made == 0, "...but digs no crater and makes no breach")
	TestLib.check(FX.marks.live_of(BlastMarks.K_WINDOW) >= 1 and FX.marks.struct_live() <= BlastMarks.cap_struct(1), "...the marks are in the capped structure pool (%d)" % FX.marks.struct_live())
	# level 2: a crater and chunks out of the facade
	StructureDamage.reset_stats()
	var chunks0 := Dmg.count(&"debris_flung")
	for i in 6:
		BlastTable.apply(&"la_rocket", ORIGIN + Vector3(3.0, 1.4, float(i) * 1.5 - 4.0), null, {"quiet": true})
	TestLib.check(StructureDamage.craters_made >= 1 and FX.marks.live_of(BlastMarks.K_CRATER) >= 1, "a rocket (level 2) digs a crater in the street (%d)" % StructureDamage.craters_made)
	TestLib.check(StructureDamage.chips_made >= 1 and FX.marks.live_of(BlastMarks.K_CHIP) >= 1, "...and tears chunks out of the facade (%d scars)" % StructureDamage.chips_made)
	TestLib.check(Dmg.count(&"debris_flung") > chunks0 and Breakables.current.debris_live > 0, "...with pieces flying (%d flung, %d live)" % [Dmg.count(&"debris_flung") - chunks0, Breakables.current.debris_live])
	# staged damage: the same place takes more with every blast
	var s_before := StructureDamage.top_stage()
	TestLib.check(s_before >= 1, "the places the blasts touched remember it (stage %d)" % s_before)
	StructureDamage.reset()
	StructureDamage.reset_stats()
	FX.reset()
	var stages: Array[int] = []
	for i in 4:
		BlastTable.apply(&"la_rocket", ORIGIN + Vector3(5.0, 1.6, 0.0), null, {"quiet": true})
		stages.append(StructureDamage.top_stage())
	TestLib.check(stages[0] <= stages[1] and stages[1] <= stages[2] and stages[2] <= stages[3] and stages[3] >= 2 and stages[3] > stages[0], "a second rocket finishes what the first began: stage %s" % str(stages))
	TestLib.check(StructureDamage.breaches_made >= 1 and FX.marks.live_of(BlastMarks.K_BREACH) >= 1, "four rockets on one facade make a breach (%d)" % StructureDamage.breaches_made)
	# level 3 breaches at once
	StructureDamage.reset()
	StructureDamage.reset_stats()
	FX.reset()
	BlastTable.apply(&"la_bunker", ORIGIN + Vector3(5.5, 1.6, 0.0), null, {"quiet": true})
	TestLib.check(StructureDamage.breaches_made >= 1, "a bunker buster (level 3) breaches a wall with one blast (%d)" % StructureDamage.breaches_made)
	# caps hold under a barrage on LOW
	Game.quality = 0
	FX.reset()
	Breakables.current.reset()
	StructureDamage.reset()
	for i in 30:
		BlastTable.apply(&"la_bunker", ORIGIN + Vector3(5.5, 1.6, float(i) - 15.0), null, {"quiet": true})
	TestLib.check(FX.marks.struct_live() <= BlastMarks.cap_struct(0) and Breakables.current.debris_live <= Dmg.cap(&"debris") + 0, "LOW: thirty bunker busters stay inside the pools (%d marks, %d pieces)" % [FX.marks.struct_live(), Breakables.current.debris_live])
	_advance(5.0)
	Game.quality = 1
	FX.reset()


# --- bullet holes by material -----------------------------------------------------------------------------------------------------

func _decals_by_material() -> void:
	var p := Game.player as Player
	var d: ImpactDecals = p.decals
	d.clear()
	var mat: ShaderMaterial = ImpactDecals._get_material()
	TestLib.check(mat != null and mat.shader != null, "the bullet holes use the procedural decal shader (no texture)")
	for surf: StringName in [&"concrete", &"metal", &"glass", &"wood", &"asphalt"]:
		TestLib.check(ImpactDecals.SURFACES.has(surf), "%s holes have their own look and quota" % surf)
	for i in 30:
		d.add(ORIGIN + Vector3(8.4, 1.0 + float(i) * 0.02, 0.0), Vector3(-1.0, 0.0, 0.0), 0.25, &"wood")
	TestLib.check(d.count_on(&"wood") == int(ImpactDecals.SURFACES[&"wood"]["quota"]), "wood holes are capped at their quota (%d)" % d.count_on(&"wood"))
	for i in 30:
		d.add(ORIGIN + Vector3(float(i) * 0.1, 0.0, 3.0), Vector3.UP, 0.25, &"asphalt")
	TestLib.check(d.count_on(&"asphalt") == int(ImpactDecals.SURFACES[&"asphalt"]["quota"]) and d.active_count() <= ImpactDecals.CAPACITY, "asphalt holes are capped too and the ring never exceeds its capacity (%d)" % d.active_count())
	d.clear()
	TestLib.check(ImpactSparks.surface_at(Vector3(0.0, 0.2, 0.0), Vector3.UP) == &"asphalt", "a hit on the street is asphalt")


# --- debris, props, cover --------------------------------------------------------------------------------------------------------

func _debris_and_props() -> void:
	var br := Breakables.current
	br.reset()
	for q in 3:
		Game.quality = q
		for i in 140:
			br.fling(ORIGIN + Vector3(0.0, 1.0, 0.0), Vector3(randf_range(-2.0, 2.0), 3.0, randf_range(-2.0, 2.0)), Color(0.5, 0.5, 0.5), 0.2, Vector3(1.0, 0.12, 0.7), 2.0)
		TestLib.check(br.debris_live <= Dmg.cap(&"debris"), "tier %d: at most %d debris pieces fly at once (%d)" % [q, Dmg.cap(&"debris"), br.debris_live])
		br.reset()
	Game.quality = 1
	br.fling(ORIGIN + Vector3(0.0, 1.0, 0.0), Vector3(0.0, 4.0, 0.0), Color.WHITE, 0.3, Vector3(1.0, 0.1, 0.5), 1.0)
	var shaped := false
	for i in Breakables.DEBRIS:
		if br._dleft[i] > 0.0 and (br._dscale[i] as Vector3).y < 0.2:
			shaped = true
	TestLib.check(shaped, "a plate is a flat piece, not a cube")
	_advance(2.0)
	TestLib.check(br.debris_live == 0 and not br.is_processing(), "the pieces end and the processing stops")
	# kinds and wear
	var names: Array[String] = []
	for k in Breakables.KINDS:
		names.append(String(k["name"]))
	TestLib.check("bench" in names and "planter" in names and "kiosk" in names, "three more kinds of prop: bench, planter, kiosk")
	var idx := -1
	for i in Breakables.COUNT:
		if String(Breakables.KINDS[br.kind_of[i]]["name"]) == "barrier":
			idx = i
			break
	if idx < 0:
		idx = 0
	var body := br.bodies[idx]
	var hp0 := br.hp[idx]
	var n := maxi(hp0 / 2, 1)
	br.hit_at(body, br.positions[idx], Vector3.UP, n)
	var st1 := int(br.stage[idx])
	br.hit_at(body, br.positions[idx], Vector3.UP, maxi(br.hp[idx] - 1, 1))
	var st2 := int(br.stage[idx])
	TestLib.check(st1 >= 1 and st2 == 2 and br.broken[idx] == 0, "a prop wears in stages before it breaks (%d, then %d)" % [st1, st2])
	TestLib.check(not EnemyCover.body_info(body).is_empty() and br.cover_bodies().has(body), "a standing barrier is cover for the enemies")
	br.hit_at(body, br.positions[idx], Vector3.UP, 5)
	TestLib.check(br.broken[idx] == 1 and EnemyCover.body_info(body).is_empty() and not br.cover_bodies().has(body), "a broken barrier gives no protection (no cover body, no collider)")
	br._restore(idx)
	TestLib.check(br.stage[idx] == 0 and br.cover_bodies().has(body), "a restored prop is whole again")
	br.reset()


# --- people ----------------------------------------------------------------------------------------------------------------------

func _foe(at: Vector3, type := &"operative") -> Drone:
	var d := em.spawn(type, at, false)
	if d != null:
		d.set_physics_process(false)
		d.global_position = at
		d.aware_dist = 0.0
	return d


func _people() -> void:
	var dw := DamageWorld.current
	var foes := dw.foes
	Game.quality = 1
	FX.reset()
	Dmg.reset_stats()
	var en := _foe(ORIGIN + Vector3(-6.0, 0.0, 0.0))
	TestLib.check(en != null, "an operative stands in the arena")
	if en == null:
		return
	_advance(0.3)                                                          # the tick hooks the died signal and takes the first health reading
	var c := en.center()
	# a body hit that took half the health: the first big plate flies off
	en.hp = en.max_hp * 0.55
	foes.on_bullet(en, {"zone": &"body", "hit": c, "dir": Vector3(-1.0, 0.0, 0.0)}, false, false, {"damage": 20.0})
	TestLib.check(Dmg.count(&"plate") >= 1 and Breakables.current.debris_live >= 1, "an armour plate flies off at 30 %% lost (%d plates, %d pieces)" % [Dmg.count(&"plate"), Breakables.current.debris_live])
	var before := Dmg.count(&"plate")
	en.hp = en.max_hp * 0.2
	_advance(0.3)
	foes.on_bullet(en, {"zone": &"body", "hit": c, "dir": Vector3(-1.0, 0.0, 0.0)}, false, false, {"damage": 20.0})
	TestLib.check(Dmg.count(&"plate") > before, "a second plate flies off at 62 % lost")
	# fluid: the Vael leave acid-green ichor, not on a mercenary
	var splats0 := FX.marks.live_of(BlastMarks.K_SPLAT) + FX.marks.live_of(BlastMarks.K_OIL)
	foes._tokens = 4.0
	foes.on_bullet(en, {"zone": &"head", "hit": c + Vector3(0.0, 0.5, 0.0), "dir": Vector3(-1.0, 0.0, 0.0)}, true, false, {"damage": 40.0})
	TestLib.check(Dmg.count(&"splat_ground") >= 1 and FX.marks.live_of(BlastMarks.K_SPLAT) + FX.marks.live_of(BlastMarks.K_OIL) > splats0, "a critical hit splashes alien fluid on the street (%d)" % Dmg.count(&"splat_ground"))
	TestLib.check(foes.camp_of(en) in [&"vael", &"gang", &"drones"], "the camp of the enemy picks its fluid (%s)" % foes.camp_of(en))
	# a leg shot limps
	var en2 := _foe(ORIGIN + Vector3(-6.0, 0.0, 3.0))
	_advance(0.3)
	var sp0 := en2.camp_speed
	foes.on_bullet(en2, {"zone": &"legs", "hit": en2.global_position + Vector3(0.0, 0.4, 0.0), "dir": Vector3(-1.0, 0.0, 0.0)}, false, false, {"damage": 10.0})
	TestLib.check(en2.camp_speed < sp0 and float(foes.state_of(en2)["limp"]) > 0.0 and Dmg.count(&"limp") == 1, "a shot in the legs makes him limp (%.2f -> %.2f)" % [sp0, en2.camp_speed])
	_advance(LIMP_TIME() + 0.5)
	TestLib.check(absf(en2.camp_speed - sp0) < 0.001, "...and the limp ends by itself")
	# statuses on the body
	var en3 := _foe(ORIGIN + Vector3(-6.0, 0.0, 6.0))
	_advance(0.3)
	foes.set_status(en3, &"burn", 3.0)
	TestLib.check(foes.status_of(en3) == &"burn", "a burning enemy shows it")
	if en3.humanoid_body != null:
		var v: Variant = en3.humanoid_body.get_instance_shader_parameter(&"dmg_fx")
		TestLib.check(v is Vector4 and (v as Vector4).x == 1.0 and (v as Vector4).y > 0.5, "...the body shader gets the burning state")
	var bf := BlastFx.instance
	var live0 := bf.cloud_live() if is_instance_valid(bf) else 0
	_advance(1.0)
	TestLib.check(is_instance_valid(bf) and bf.cloud_live() >= live0 and bf.cloud_live() > 0, "...flames and smoke come out of the shared cloud (%d puffs)" % (bf.cloud_live() if is_instance_valid(bf) else -1))
	en3.damage(99999.0)
	TestLib.check(en3.dead and Dmg.count(&"death_burn") == 1, "a burning enemy that dies is a burning death")
	# frozen death shatters
	var en4 := _foe(ORIGIN + Vector3(-6.0, 0.0, 9.0))
	_advance(0.3)
	foes.set_status(en4, &"freeze", 3.0)
	var deb0 := Dmg.count(&"debris_flung")
	en4.damage(99999.0)
	TestLib.check(Dmg.count(&"death_freeze") == 1 and Dmg.count(&"shatter") == 1 and Dmg.count(&"debris_flung") > deb0, "a frozen enemy shatters into ice")
	_advance(0.2)
	TestLib.check(not en4.model.visible, "...and the body is gone")
	# shocked and dissolving deaths
	var en5 := _foe(ORIGIN + Vector3(-6.0, 0.0, 12.0))
	_advance(0.3)
	foes.set_status(en5, &"shock", 3.0)
	en5.damage(99999.0)
	TestLib.check(Dmg.count(&"death_shock") == 1, "a shocked enemy dies in a crackle of arcs")
	var en6 := _foe(ORIGIN + Vector3(-6.0, 0.0, 15.0))
	_advance(0.3)
	foes.set_status(en6, &"dissolve", 3.0)
	en6.damage(99999.0)
	TestLib.check(Dmg.count(&"death_quantum") == 1 and foes.flings_live() >= 1, "a dissolving enemy comes apart (quantum death)")
	_advance(1.5)
	TestLib.check(not en6.model.visible, "...its body shrinks away")
	# a blast kills and throws a body
	em.clear()
	_advance(0.2)
	var en7 := _foe(ORIGIN + Vector3(-6.0, 0.0, -4.0))
	var en8 := _foe(ORIGIN + Vector3(-9.0, 0.0, -4.0), &"sentinel")
	_advance(0.3)
	var p7 := en7.global_position
	en7.hp = 20.0
	BlastTable.apply(&"gr_frag", p7 + Vector3(1.5, 0.3, 0.0), null, {"quiet": true})
	await TestLib.frames(host, 2)                                          # the blast's second look (deferred) is one frame later
	TestLib.check(en7.dead and Dmg.count(&"death_blast") >= 1 and Dmg.count(&"fling") >= 1, "a blast kills and throws the body (dead %s, %s)" % [str(en7.dead), str(Dmg.stats)])
	_advance(0.6)
	TestLib.check(en7.global_position.distance_to(p7) > 0.8, "...it flew (%.1f m)" % en7.global_position.distance_to(p7))
	_advance(3.5)
	TestLib.check(foes.flings_live() == 0 and absf(en7.rotation.x) < 0.01 and absf(en7.rotation.z) < 0.01, "...and lands flat: no body in the air any more")
	if en8 != null:
		TestLib.check(Dmg.count(&"plate") >= 3, "a machine breaks into plates and sparks when it goes (%d plates)" % Dmg.count(&"plate"))
	# plates in flight stay inside the cap
	em.clear()
	Game.quality = 0
	var e9 := _foe(ORIGIN + Vector3(-6.0, 0.0, 20.0))
	_advance(0.3)
	for i in 30:
		e9.hp = e9.max_hp * 0.1
		foes._state(e9)["plates"] = 0
		foes._state(e9)["t_plate"] = -9.0
		foes.on_bullet(e9, {"zone": &"body", "hit": e9.center(), "dir": Vector3(-1.0, 0.0, 0.0)}, false, false, {"damage": 20.0})
	TestLib.check(Breakables.current.debris_live <= Dmg.cap(&"plates") + 4, "LOW: a hail of hits never has more than a handful of plates in the air (%d)" % Breakables.current.debris_live)
	_advance(3.0)
	Game.quality = 1
	em.clear()


func LIMP_TIME() -> float:
	return FoeFx.LIMP_TIME


# --- fire fields, failing shields -----------------------------------------------------------------------------------------------

func _fire_and_shields() -> void:
	var dw := DamageWorld.current
	var br := Breakables.current
	Game.quality = 1
	FX.reset()
	em.clear()
	# a fire field (napalm, ember bottle, thermobaric) sets the cars inside it alight (the props inside are already broken by the blast itself)
	var f0 := dw.fires_started
	var car := mgr.spawn_parked(&"sedan", ORIGIN + Vector3(5.0, 0.0, -6.0), 0.0)
	_advance(0.2)
	BlastTable.apply(&"gr_ember", ORIGIN + Vector3(4.0, 0.3, -5.0), null, {"quiet": true})
	await TestLib.frames(host, 2)
	TestLib.check(car != null and dw.fires_started > f0 and (car.fuse >= 0.0 or car.dead), "a fire field (EMBER BOTTLE) sets the car inside it alight (%d things lit)" % (dw.fires_started - f0))
	mgr._reset_all()
	_advance(0.2)
	# a shield trooper whose shield is nearly gone flickers
	var sh := em.spawn(&"shield", ORIGIN + Vector3(-6.0, 0.0, 6.0), false)
	if sh == null:
		TestLib.check(false, "a shield trooper can be spawned")
		return
	sh.set_physics_process(false)
	sh.global_position = ORIGIN + Vector3(-6.0, 0.0, 6.0)
	_advance(0.3)
	var node := sh.get(&"shield_node") as MeshInstance3D
	TestLib.check(node != null and float(sh.get(&"shield_hp")) > 0.0 and node.visible, "the shield trooper's shield stands")
	sh.set(&"shield_hp", float(sh.get(&"shield_max")) * 0.3)
	_advance(0.3)
	TestLib.check(dw.foes.shields_live() >= 1 and Dmg.count(&"shield_flicker") >= 1, "a nearly spent shield is flagged to flicker")
	var seen_on := false
	var seen_off := false
	for i in 12:
		dw.foes.step(0.016)
		if node.visible:
			seen_on = true
		else:
			seen_off = true
		await TestLib.frames(host, 1)
		OS.delay_msec(12)
	TestLib.check(seen_on and seen_off, "...and it blinks (on and off both seen)")
	sh.set(&"shield_hp", 0.0)
	sh.call(&"break_shield")
	_advance(0.3)
	TestLib.check(dw.foes.shields_live() == 0 and not node.visible, "a broken shield stops flickering and stays gone")
	em.clear()


# --- cars ------------------------------------------------------------------------------------------------------------------------

## A round at the car: from the world hit point on the car's side toward its middle (the direction carries the round on through the body).
func _shot(car: Vehicle, local_hit: Vector3) -> Dictionary:
	var w := car.to_global(local_hit)
	var centre := car.to_global(Vector3(0.0, float(car.spec["hgt"]) * 0.45, 0.0))
	return {"hit": w, "dir": (centre - w).normalized()}


func _cars() -> void:
	var dw := DamageWorld.current
	var cars := dw.cars
	Game.quality = 1
	FX.reset()
	Dmg.reset_stats()
	var car := mgr.spawn_parked(&"sedan", ORIGIN + Vector3(6.0, 0.0, 12.0), 0.0)
	TestLib.check(car != null and car.visual != null and car.visual.v2 != null, "a Cars v2 sedan stands in the arena")
	if car == null or car.visual == null or car.visual.v2 == null:
		return
	var v2: CarV2 = car.visual.v2
	car.hp = car.max_hp
	car.visual.repair()
	_advance(0.3)
	var hg := float(car.spec["hgt"])
	var ln := float(car.spec["len"])
	var wid := float(car.spec["wid"])
	# zones
	TestLib.check(cars.zone_at(car, Vector3(0.0, hg * 0.85, 0.0))["zone"] == &"glass" and cars.zone_at(car, Vector3(0.0, hg * 0.55, -ln * 0.35))["zone"] == &"hood" and cars.zone_at(car, Vector3(wid * 0.5, hg * 0.5, 0.2))["zone"] == &"body", "a point on the car is glass, hood or body by where it is")
	var wp := car.to_local(car.visual.wheels[0].global_position)
	TestLib.check(cars.zone_at(car, Vector3(wp.x, 0.3, wp.z))["zone"] == &"tyre", "a low point beside a wheel is the tyre")
	# bullet holes on the paint
	cars.on_bullet(car, _shot(car, Vector3(wid * 0.6, hg * 0.45, 0.3)), {"damage": 14.0})
	TestLib.check(v2.holes.size() == 1 and int(v2.paint_mat.get_shader_parameter(&"hole_n")) == 1, "a round leaves a bullet hole in the paint shader (%d)" % v2.holes.size())
	for i in 14:
		cars.on_bullet(car, _shot(car, Vector3(wid * 0.6, hg * 0.45 + float(i) * 0.01, -ln * 0.3 + float(i) * 0.2)), {"damage": 14.0})
	TestLib.check(v2.holes.size() <= Dmg.cap(&"car_holes") and v2.holes.size() <= CarV2.MAX_HOLES, "the holes on one car stay inside the cap (%d, cap %d)" % [v2.holes.size(), Dmg.cap(&"car_holes")])
	# glass: a star at the hole first, then the pane cracks in stages, then it shatters
	var cr0 := v2.cracks
	cars.on_bullet(car, _shot(car, Vector3(wid * 0.7, hg * 0.8, 0.0)), {"damage": 14.0})
	TestLib.check(v2.cracks == cr0 and not v2.glass_shattered, "the first round in the windscreen only stars the pane at the hole (%.2f)" % v2.cracks)
	for i in 2:
		cars.on_bullet(car, _shot(car, Vector3(wid * 0.7, hg * 0.8, 0.0)), {"damage": 14.0})
	TestLib.check(v2.cracks > cr0 and v2.cracks < 0.99 and not v2.glass_shattered, "...the third cracks the pane (%.2f)" % v2.cracks)
	for i in 8:
		cars.on_bullet(car, _shot(car, Vector3(wid * 0.7, hg * 0.8, 0.0)), {"damage": 14.0})
	TestLib.check(v2.glass_shattered and Dmg.count(&"glass_shatter") == 1, "a burst of rounds shatters the glass")
	TestLib.check(float(v2.glass_mat.get_shader_parameter(&"opacity")) < 0.2, "...the pane is almost clear")
	# a tyre
	cars.on_bullet(car, _shot(car, Vector3(wp.x * 1.3, 0.3, wp.z)), {"damage": 14.0})
	TestLib.check((v2.wheels_flat & 1) == 1 and car.tires_flat > 0.0 and Dmg.count(&"tyre") == 1, "a round in the tyre flattens it and the car limps (flat %d, tires %.1f, %s)" % [v2.wheels_flat, car.tires_flat, str(Dmg.stats)])
	# hood
	car.hp = car.max_hp * 0.3
	car._update_damage_state()
	for i in 12:
		_advance(0.1)
	TestLib.check(car.damage_stage() >= 2 and v2.hood_pop > 0.9 and Dmg.count(&"hood") >= 1, "below 40 %% of the hull the hood pops open (%.2f, stage %d, popped %d)" % [v2.hood_pop, car.damage_stage(), Dmg.count(&"hood")])
	# repair puts everything back
	car.repair()
	TestLib.check(v2.holes.is_empty() and v2.hood_pop == 0.0 and v2.wheels_flat == 0 and not v2.glass_shattered, "the mechanic puts it all back (holes, hood, tyre, glass)")
	# a blast sprays shrapnel into the flank that faces it
	car.hp = car.max_hp
	cars.on_blast(car, car.global_position + Vector3(4.0, 0.5, 0.0), 0.8)
	TestLib.check(v2.holes.size() >= 1 and v2.cracks > 0.0, "a blast leaves shrapnel holes and cracks the glass (%d holes)" % v2.holes.size())
	car.repair()
	# a wreck stays and burns
	var bf := BlastFx.instance
	car.explode()
	await TestLib.frames(host, 2)
	var neighbour := mgr.spawn_parked(&"taxi", car.global_position + Vector3(2.8, 0.0, 0.0), 0.0)       # parked beside the wreck AFTER the blast: only the spreading fire can light it
	_advance(0.3)
	TestLib.check(car.wreck or car.dead, "the car exploded")
	TestLib.check(cars.wrecks_live() >= 1 and Dmg.count(&"wreck") >= 1, "the wreck is remembered by the damage world (%d)" % cars.wrecks_live())
	var puffs0 := Dmg.count(&"wreck")
	_advance(2.0)
	TestLib.check(is_instance_valid(bf) and bf.cloud_live() > 0, "a burning wreck makes flames and smoke (%d puffs)" % (bf.cloud_live() if is_instance_valid(bf) else -1))
	if neighbour != null:
		cars._spread(car)
		for i in 12:
			cars._spread(car)
		TestLib.check(cars.spread_fires >= 1 and (neighbour.fuse >= 0.0 or neighbour.dead), "the fire spreads to the car next to it (%d)" % cars.spread_fires)
	# ...and to a wooden bench beside it
	var bench := -1
	for i in Breakables.COUNT:
		if String(Breakables.KINDS[Breakables.current.kind_of[i]]["name"]) == "bench" and Breakables.current.broken[i] == 0:
			bench = i
			break
	if bench >= 0:
		Breakables.current.positions[bench] = car.global_position + Vector3(0.0, 0.4, 3.0)
		var fp0 := Dmg.count(&"fire_spread")
		for i in 14:
			cars._spread(car)
		TestLib.check(Breakables.current.broken[bench] == 1 and Dmg.count(&"fire_spread") > fp0, "...and a wooden bench beside the wreck burns down")
		Breakables.current.reset()
	_advance(CarFx.WRECK_SMOULDER + 5.0)
	TestLib.check(cars.wrecks_live() == 0, "the wreck stops smoking after a minute or so")
	FX.reset()
	mgr._reset_all()


# --- the real chain ---------------------------------------------------------------------------------------------------------------

func _real_chain() -> void:
	var p := Game.player as Player
	if p == null:
		TestLib.check(false, "the real scene has a player")
		return
	Game.quality = 1
	em.clear()
	FX.reset()
	Dmg.reset_stats()
	p.max_hp = 1.0e6
	p.hp = 1.0e6
	TestMode.god = true
	p.teleport_to(ORIGIN + Vector3(-30.0, 0.0, 0.0))
	p.camera_rig.reset_view(-PI * 0.5, -0.05)
	await TestLib.frames(host, 4)
	var at := p.global_position + Vector3(8.0, 0.0, 0.0)                    # the camera looks +x here
	var en := _foe(at)
	en.set_physics_process(true)
	en.aware_dist = 0.0
	p.weapon.switch_to(&"carbine", true)
	p.weapon.ammo = p.weapon.mag
	p.weapon.reserve = 99
	var hits0 := DamageWorld.current.hits_seen
	var t := 0
	Input.action_press(&"fire")
	while t < 240 and Dmg.count(&"plate") + Dmg.count(&"splat_ground") + Dmg.count(&"limp") + Dmg.count(&"chip") == 0:
		p.camera_rig.aim_at(en.center())
		en.global_position = at
		await TestLib.frames(host, 1)
		t += 1
	Input.action_release(&"fire")
	TestLib.check(DamageWorld.current.hits_seen > hits0, "the hero's real shots reach the damage world through Player.hit_confirmed (%d hits)" % (DamageWorld.current.hits_seen - hits0))
	TestLib.check(Dmg.count(&"plate") + Dmg.count(&"splat_ground") + Dmg.count(&"limp") + Dmg.count(&"chip") >= 1, "...and the enemy shows it (plates %d, splatter %d, limp %d, chips %d)" % [Dmg.count(&"plate"), Dmg.count(&"splat_ground"), Dmg.count(&"limp"), Dmg.count(&"chip")])
	var p0 := DamageWorld.current.cars.holes_made
	# a real round into a parked car
	var car := mgr.spawn_parked(&"sedan", p.global_position + Vector3(6.0, 0.0, 4.0), 0.0)
	await TestLib.frames(host, 2)
	if car != null and car.visual != null and car.visual.v2 != null:
		p.camera_rig.aim_at(car.global_position + Vector3(0.0, 0.7, 0.0))
		Input.action_press(&"fire")
		t = 0
		while t < 200 and DamageWorld.current.cars.holes_made == p0:
			p.camera_rig.aim_at(car.global_position + Vector3(0.0, 0.7, 0.0))
			await TestLib.frames(host, 1)
			t += 1
		Input.action_release(&"fire")
		TestLib.check(DamageWorld.current.cars.holes_made > p0, "a real round into a parked car leaves a hole (%d)" % (DamageWorld.current.cars.holes_made - p0))
	Input.action_release(&"fire")
	TestMode.god = false
	em.clear()
	mgr._reset_all()
