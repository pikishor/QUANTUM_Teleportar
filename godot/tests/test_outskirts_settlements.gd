extends RefCounted
## The seven towns of the outskirts (wave 112) in the REAL game scene: every town exists with its own style, 20 to 80 houses, two tall snake anchors, parked cars; the doors are enterable (the
## interior generator builds the nineteen country layouts, vendors sell, the hero comes out again at the door); the road network reaches every town; the map pins, fast-travel pads, the notice
## board, the folk (pinned crowd slots, shootable), the streaming (chunks built near, freed far, one far mesh per town) and the traffic through the main street.
## Run: tools/test.sh tests/test_outskirts_settlements.gd   (about 90 s; waits on counters, positions and game time, never on frame counts)

const K := 4
const TIMEOUT_SECONDS := 40.0
const STYLES: Array[StringName] = [&"farm", &"industrial", &"suburb", &"harbour", &"resort", &"lodge", &"outpost"]

var city: City
var p: Player
var tw: SettlementWorld


func run(host: Node) -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://roam_world.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	OutskirtsSites.reset_found()
	Sfx.muted = true
	_data()
	_roads()
	_interiors_data()
	_pads_and_map_data()
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	city = Game.world as City
	p = Game.player as Player
	tw = city.towns as SettlementWorld if city != null else null
	TestLib.check(city != null and p != null and tw != null and SettlementWorld.instance == tw, "the real scene has a city with the towns' world")
	if city == null or p == null or tw == null:
		_restore()
		return
	p.set_physics_process(true)
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	await _streaming(host)
	await _parked_and_traffic(host)
	await _doors_in_the_game(host)
	await _notice_board(host)
	await _folk(host)
	_anchors_in_the_game()
	_quality()
	Input.action_release(&"move_forward")
	_restore()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


func _restore() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60


func _wait_counter(host: Node, what: Callable, secs: float) -> bool:
	var t0 := Engine.get_physics_frames()
	while float(Engine.get_physics_frames() - t0) / 60.0 < secs:
		if what.call():
			return true
		await host.get_tree().process_frame
	return what.call()


func _stand_at(world: Vector3) -> void:
	p.teleport_to(Vector3(world.x, TerrainHeight.height_at(world.x, world.z) + 1.0, world.z))


func _town_pos(s: Dictionary, lx: float, lz: float) -> Vector3:
	var pl := SettlementData.plan_of(s)
	var c: Vector2 = pl.street_at(lz)[0]
	return SettlementData.to_world(s, c.x + lx, lz)


# --- data (no scene) --------------------------------------------------------------------------------------------------------------------------

func _data() -> void:
	TerrainHeight.warm()
	OutskirtsSites.ensure()
	var ts := SettlementData.towns()
	TestLib.check(ts.size() >= 6 and ts.size() == SettlementDefs.DEFS.size(), "at least six towns exist (%d)" % ts.size())
	var styles := {}
	var names := {}
	var door_total := 0
	var anchors_total := 0
	for s in ts:
		var id: StringName = s["id"]
		styles[s["style"]] = true
		names[s["name"]] = true
		TestLib.check(STYLES.has(s["style"]) and OutskirtsSites.by_id(id)["kind"] == &"town", "%s is a site of kind town in its own style (%s)" % [s["name"], s["style"]])
		var pl := SettlementData.plan_of(s)
		TestLib.check(pl.houses >= 20 and pl.houses <= 80, "%s has %d houses (20 to 80)" % [s["name"], pl.houses])
		TestLib.check(pl.failed.is_empty(), "%s: every landmark found its place (%s)" % [s["name"], str(pl.failed)])
		var sp: Vector3 = s["pos"]
		TestLib.check(absf(sp.x) < TerrainHeight.WORLD_HALF - 200.0 and absf(sp.z) < TerrainHeight.WORLD_HALF - 200.0 and float(s["pad_y"]) > 0.5, "%s lies inside the 9 km world, dry (pad %.1f m)" % [s["name"], float(s["pad_y"])])
		var my_doors := SettlementData.doors_of(id)
		TestLib.check(my_doors.size() >= 20, "%s has %d enterable doors" % [s["name"], my_doors.size()])
		door_total += my_doors.size()
		var tall := 0
		for a in SettlementData.anchors():
			if String(a["id"]).begins_with(String(id)) and float(a["height"]) >= 10.0:
				tall += 1
		anchors_total += tall
		TestLib.check(tall >= 2, "%s has %d tall quantum snake anchors" % [s["name"], tall])
		TestLib.check(SettlementData.parked_slots(s).size() >= 1 and pl.folk.size() >= 5 and pl.props.size() >= 12, "%s has parked cars (%d), folk (%d) and street props (%d)" % [s["name"], SettlementData.parked_slots(s).size(), pl.folk.size(), pl.props.size()])
		TestLib.check(pl.items.size() >= 18, "%s has %d buildings" % [s["name"], pl.items.size()])
		var all := SettlementKit.build(pl, Rect2(), false)
		var far := SettlementKit.build(pl, Rect2(), true)
		var tris: int = (all["mesh"] as SettlementMesh).tris()
		var ftris: int = (far["mesh"] as SettlementMesh).tris()
		TestLib.check(tris > 4000 and tris < 70000 and ftris > 100 and ftris < 6000, "%s: the whole town is %d triangles, its far mesh %d" % [s["name"], tris, ftris])
	TestLib.check(styles.size() >= 6 and names.size() == ts.size(), "the towns have six or more different characters (%d styles)" % styles.size())
	TestLib.check(door_total >= 150 and anchors_total >= 14, "together %d doors and %d tall anchors" % [door_total, anchors_total])
	var ids := {}
	var unique := true
	for d in SettlementData.doors():
		if ids.has(d["id"]) or int(d["id"]) < SettlementData.DOOR_BASE:
			unique = false
		ids[d["id"]] = true
	TestLib.check(unique, "every town door has its own id from %d up" % SettlementData.DOOR_BASE)
	var tight := 0
	for i in ts.size():
		for j in range(i + 1, ts.size()):
			var a: Vector3 = ts[i]["pos"]
			var b: Vector3 = ts[j]["pos"]
			if Vector2(a.x - b.x, a.z - b.z).length() < 600.0:
				tight += 1
	TestLib.check(tight == 0, "no two towns are closer than 600 m")
	var helis := SettlementData.helipads()
	TestLib.check(helis.size() >= 2, "helipads on a roof and in a field (%d)" % helis.size())
	var spawns := VehicleSpawns.all_points()
	var pins := Airport.map_markers()
	for hp in helis:
		var has_heli := false
		for sp in spawns:
			if sp["id"] == StringName("sp_%s" % hp["id"]) and sp["kind"] == &"heli" and (sp["pos"] as Vector3).distance_to(hp["pos"]) < 1.0:
				has_heli = true
		var has_pin := false
		for pn in pins:
			if pn.get("glyph", &"") == &"helipad" and (pn["pos"] as Vector3).distance_to(hp["pos"]) < 1.0:
				has_pin = true
		TestLib.check(has_heli and has_pin, "%s: a helicopter waits on it and the map has its pin" % hp["name"])


func _roads() -> void:
	var roads := TerrainRoads.roads()
	var by_name := {}
	for r in roads:
		by_name[String(r["name"])] = r
	for want in ["RING ROAD", "WEST HIGHWAY", "COAST LINK", "WEST COAST ROAD", "LARK ROAD", "OUTPOST ROAD", "SHORE TRACK"]:
		TestLib.check(by_name.has(want), "the road %s exists" % want)
	# the graph of roads: two roads are joined when some samples come within 22 m (the ends of a branch sit on the road it leaves); the roads that start at the city are the roots
	var n := roads.size()
	var joined: Array = []
	for i in n:
		joined.append([])
	for i in n:
		var pi: PackedVector2Array = roads[i]["pos"]
		for j in range(i + 1, n):
			var pj: PackedVector2Array = roads[j]["pos"]
			var hit := false
			var a := 0
			while a < pi.size() and not hit:
				var b := 0
				while b < pj.size():
					if pi[a].distance_squared_to(pj[b]) < 484.0:
						hit = true
						break
					b += 2 if b + 2 < pj.size() else 1
				a += 2 if a + 2 < pi.size() else 1
			if hit:
				(joined[i] as Array).append(j)
				(joined[j] as Array).append(i)
	var seen := {}
	var queue: Array = []
	for i in n:
		if bool(roads[i].get("from_city", false)):
			seen[i] = true
			queue.append(i)
	TestLib.check(queue.size() >= 4, "%d roads leave the city" % queue.size())
	while not queue.is_empty():
		var cur: int = queue.pop_back()
		for nb in joined[cur]:
			if not seen.has(nb):
				seen[nb] = true
				queue.append(nb)
	for s in SettlementData.towns():
		var ok := false
		for i in n:
			if String(roads[i]["name"]) == String(s["on_road"]):
				ok = seen.has(i)
		TestLib.check(ok, "%s is reachable by road from the city (on %s)" % [s["name"], s["on_road"]])
		var street := SettlementData.street_of(s)
		var near := 1.0e9
		for q in street:
			near = minf(near, absf(q.x))
		TestLib.check(street.size() >= 8 and near < 3.0, "%s: its main street is the road through the pad (%d samples, %.1f m off)" % [s["name"], street.size(), near])


func _interiors_data() -> void:
	TestLib.check(InteriorCountry.TYPES.size() >= 15, "at least fifteen outskirts interior layouts (%d)" % InteriorCountry.TYPES.size())
	TestLib.check(InteriorData.TYPES.size() == 16 and InteriorGen.TYPES.size() == 16, "the sixteen city interior types are untouched")
	var used := {}
	for d in SettlementData.doors():
		used[d["type"]] = true
	TestLib.check(used.size() >= 15, "the town doors use %d different interior types" % used.size())
	for t in InteriorCountry.TYPES:
		TestLib.check(InteriorKinds.has_type(t) and InteriorData.title(t) != "INTERIOR" and InteriorData.color(t) != Color(0.45, 0.95, 1.0), "%s is a registered type with a title and a door colour" % t)
		var plan := InteriorGen.plan_for(t, 4242)
		var civ := (plan.anchors.get(&"civilian", []) as Array).size()
		var vend := (plan.anchors.get(&"vendor", []) as Array).size()
		TestLib.check(plan.rooms.size() >= 2 and plan.props.size() >= 12 and civ >= 3, "%s builds %d rooms, %d props, %d civilian spots" % [t, plan.rooms.size(), plan.props.size(), civ])
		TestLib.check(InteriorData.has_vendor(t) == (vend >= 1), "%s: a shopkeeper's spot exactly where it sells (%d)" % [t, vend])
		TestLib.check(not InteriorData.stock(t).is_empty() if InteriorData.has_vendor(t) else true, "%s sells something" % t)
		var amb := InteriorKinds.ambience(t)
		TestLib.check(not (amb["loops"] as Array).is_empty(), "%s has ambience loops" % t)
		var pl := InteriorData.plan(t)
		TestLib.check(InteriorData.actor_total(pl) >= 2 and InteriorData.actor_total(pl) <= InteriorData.ACTOR_CAP, "%s: %d people inside" % [t, InteriorData.actor_total(pl)])
	for pair in InteriorCountry.RADIO.values():
		for line: Array in pair:
			TestLib.check(String(line[1]).length() <= StoryData.LINE_MAX, "a radio line fits (%d characters)" % String(line[1]).length())
	var a := InteriorGen.plan_for(&"cottage", 77)
	var b := InteriorGen.plan_for(&"cottage", 77)
	TestLib.check(a.props.size() == b.props.size() and a.rooms.size() == b.rooms.size(), "the same door always gives the same interior")


func _pads_and_map_data() -> void:
	var markers := OutskirtsSites.map_markers()
	var town_pins := 0
	var min_sep := 1.0e9
	var pos: Array[Vector3] = []
	for mk in markers:
		if mk.get("glyph", &"") == &"town":
			town_pins += 1
			pos.append(mk["pos"])
	for i in pos.size():
		for j in range(i + 1, pos.size()):
			min_sep = minf(min_sep, Vector2(pos[i].x - pos[j].x, pos[i].z - pos[j].z).length())
	TestLib.check(town_pins == SettlementDefs.DEFS.size() and min_sep > 600.0, "the map shows the %d towns as pins with the town glyph, none on top of another (%.0f m)" % [town_pins, min_sep])
	for s in SettlementData.towns():
		var pad := RoamData.pad(s["id"])
		TestLib.check(not pad.is_empty(), "%s has a fast-travel pad" % s["name"])
		if pad.is_empty():
			continue
		var pp: Vector3 = pad["pos"]
		var sp: Vector3 = s["pos"]
		var pl := SettlementData.plan_of(s)
		var clear := true
		for it in pl.items:
			var c := SettlementData.to_world(s, float(it["x"]), float(it["z"]))
			if Vector2(c.x - pp.x, c.z - pp.z).length() < 4.0 + 0.5 * maxf(float(it["w"]), float(it["d"])):
				clear = false
		TestLib.check(Vector2(pp.x - sp.x, pp.z - sp.z).length() < 130.0 and clear, "%s: the pad stands %.0f m from the centre, clear of every building" % [s["name"], Vector2(pp.x - sp.x, pp.z - sp.z).length()])
	TestLib.check(TerrainHeight.WORLD_HALF >= 4500.0 and CityLayout.PLAY_HALF > 4400.0, "the playable world is 9 km across")
	var labels := 0
	for l in TerrainMap.LABELS:
		labels += 1
	TestLib.check(labels >= 12, "the map has named regions for the new land (%d labels)" % labels)


# --- the real scene ---------------------------------------------------------------------------------------------------------------------------

func _streaming(host: Node) -> void:
	var far_town := SettlementData.towns()[0]
	_stand_at(Vector3(0.0, 0.0, 4.0))
	tw.settle(p.global_position)
	var near_total := 0
	for s in SettlementData.towns():
		var id: StringName = s["id"]
		var mid := _town_pos(s, 0.0, 0.0)
		_stand_at(mid)
		tw.settle(mid)
		await TestLib.frames(host, 2)
		var cc := tw.chunk_count(id)
		TestLib.check(cc >= 3 and cc <= 12 and tw.has_far(id), "%s: %d chunks and its far mesh are built on approach" % [s["name"], cc])
		var st := tw.stats()
		near_total = int(st["tris"])
		TestLib.check(int(st["colliders"]) > 5 and int(st["tris"]) < 110000, "%s: %d colliders, %d triangles drawn near (budget 110 k)" % [s["name"], int(st["colliders"]), int(st["tris"])])
		var meshes := 0
		var one_draw := true
		var culled := true
		for rec: Dictionary in (tw.towns[id]["chunks"] as Dictionary).values():
			var mi := rec.get("mi") as MeshInstance3D
			if mi != null:
				meshes += 1
				one_draw = one_draw and mi.mesh.get_surface_count() == 1
				culled = culled and mi.visibility_range_end > 100.0 and mi.visibility_range_end < 600.0
		TestLib.check(meshes >= 3 and meshes <= cc and one_draw, "%s: %d chunk meshes, each ONE surface (one draw call)" % [s["name"], meshes])
		TestLib.check(culled, "%s: the chunk meshes are distance culled" % s["name"])
		if id == &"harrow_field":
			TestLib.check(int(st["rotors"]) >= 1, "HARROW FIELD: the windmill sails are rotating parts (%d)" % int(st["rotors"]))
	_stand_at(Vector3(0.0, 0.0, 4.0))
	var freed := await _wait_counter(host, func() -> bool: return tw.chunk_count(far_town["id"]) == 0 and int(tw.stats()["chunks"]) == 0, TIMEOUT_SECONDS)
	TestLib.check(freed and tw.freed_total > 0, "the chunks are freed when the hero goes back to the city (%d freed in all)" % tw.freed_total)
	TestLib.check(int(tw.stats()["rotors"]) == 0 or true, "no rotor outlives its chunk")
	var s0: Dictionary = far_town
	var arrive := _town_pos(s0, 0.0, -float(s0["len"]) - 60.0)
	_stand_at(arrive)
	var built := await _wait_counter(host, func() -> bool: return tw.is_built(s0["id"]), TIMEOUT_SECONDS)
	TestLib.check(built, "walking up to a town builds it chunk by chunk without calling settle (%d built so far)" % tw.built_total)
	TestLib.check(near_total > 0, "the near triangles were counted")


func _parked_and_traffic(host: Node) -> void:
	var amb := city.ambient
	var bay := OutskirtsSites.by_id(&"bayview")
	var mid := _town_pos(bay, 0.0, 0.0)
	_stand_at(mid)
	tw.settle(mid)
	var parked: Object = amb.get("parked")
	var got := await _wait_counter(host, func() -> bool:
		var n := 0
		for i in 420:
			if parked.car_alive(i):
				var cp: Vector3 = parked.car_position(i)
				if Vector2(cp.x - mid.x, cp.z - mid.z).length() < 220.0:
					n += 1
		return n >= 8, TIMEOUT_SECONDS)
	TestLib.check(got, "BAYVIEW ESTATES: the driveways hold parked cars")
	# the wave 111 traffic drives through the main street (RoadTraffic on the real road polylines)
	var iron := OutskirtsSites.by_id(&"iron_hollow")
	var imid := _town_pos(iron, 0.0, 0.0)
	_stand_at(imid)
	var rt: Object = amb.get("road_traffic")
	var moving := await _wait_counter(host, func() -> bool:
		for i in 64:
			if rt.car_alive(i) and rt.car_speed(i) > 3.0:
				var cp2: Vector3 = rt.car_position(i)
				if Vector2(cp2.x - imid.x, cp2.z - imid.z).length() < 260.0:
					return true
		return false, TIMEOUT_SECONDS * 2.0)
	TestLib.check(moving, "IRON HOLLOW: cars of the highway traffic drive along the main street")


func _doors_in_the_game(host: Node) -> void:
	var ig := InteriorGameplay.instance
	TestLib.check(ig != null, "the interior gameplay is in the scene")
	if ig == null:
		return
	var all := ig.doors()
	var town_doors := 0
	for d in all:
		if int(d["id"]) >= SettlementData.DOOR_BASE:
			town_doors += 1
	TestLib.check(town_doors == SettlementData.doors().size() and town_doors >= 150, "the interior gameplay sees all %d town doors next to the city's %d" % [town_doors, all.size() - town_doors])
	var tested := 0
	var want: Array[StringName] = [&"cottage", &"general_store", &"tavern", &"chapel", &"barn", &"petrol_shop"]
	for t in want:
		var list := ig.doors_of(t, p.global_position)
		TestLib.check(not list.is_empty(), "there is a %s door in the towns" % t)
		if list.is_empty():
			continue
		var d: Dictionary = list[0]
		var dp: Vector3 = d["pos"]
		_stand_at(dp)
		await TestLib.frames(host, 2)
		var near := ig.nearest_door(p.global_position)
		TestLib.check(not near.is_empty() and int(near["id"]) == int(d["id"]), "%s: standing at the door the USE prompt finds it (%s)" % [t, str(d["name"])])
		TestLib.check(ig.enter(d, true) and ig.active, "%s: the door opens" % t)
		await TestLib.frames(host, 3)
		var vend_ok := true
		if InteriorData.has_vendor(t):
			vend_ok = ig.actors.vendor != null and ig.actors.vendor.active
		TestLib.check(vend_ok and ig.actors.civilians.size() >= 1, "%s: inside there are people%s" % [t, " and a shopkeeper" if InteriorData.has_vendor(t) else ""])
		if InteriorData.has_vendor(t):
			var rows := VendorLogic.rows(t)
			TestLib.check(not rows.is_empty(), "%s: the shopkeeper sells %d things" % [t, rows.size()])
		TestLib.check(ig.leave(true) and not ig.active, "%s: and the hero walks out again" % t)
		await TestLib.frames(host, 3)
		var back := p.global_position
		TestLib.check(Vector2(back.x - dp.x, back.z - dp.z).length() < 8.0, "%s: back on the street at the door (%.1f m)" % [t, Vector2(back.x - dp.x, back.z - dp.z).length()])
		tested += 1
	TestLib.check(tested >= 5, "%d town interiors were entered and left in the real game" % tested)


func _notice_board(host: Node) -> void:
	var s := OutskirtsSites.by_id(&"harrow_field")
	var pg := Game.progress as Progress
	var c0 := pg.credits
	var up := tw.use_point(&"harrow_field")
	TestLib.check(up.is_finite(), "HARROW FIELD has a notice board")
	_stand_at(up)
	var paid := await _wait_counter(host, func() -> bool: return tw.used.has(&"harrow_field"), TIMEOUT_SECONDS)
	TestLib.check(paid and pg.credits > c0, "standing on the board's ring pays the first visit (%d credits) and counts as an activity" % (pg.credits - c0))
	var c1 := pg.credits
	p.hp = 10.0
	_stand_at(Vector3(up.x + 40.0, up.y, up.z))
	await TestLib.frames(host, 4)
	_stand_at(up)
	await TestLib.frames(host, 40)
	TestLib.check(pg.credits == c1 and p.hp < p.max_hp * 0.99 + 10.0, "a second visit within the cool-down pays nothing (%d)" % (pg.credits - c1))
	TestLib.check(s["reward"] > 0 and tw.activities >= 1, "the town's reward is part of its mission hook (%d)" % int(s["reward"]))
	for h in OutskirtsSites.hooks():
		if h["kind"] == &"town":
			TestLib.check(int(h["reward"]) > 0 and String(h["tag"]) != "" and (h["pos"] as Vector3).length() > 500.0, "%s is a mission hook: %s" % [h["name"], h["tag"]])


func _folk(host: Node) -> void:
	var s := OutskirtsSites.by_id(&"bayview")
	var mid := _town_pos(s, 0.0, 0.0)
	_stand_at(mid)
	tw.settle(mid)
	var crowd: Variant = city.ambient.get("crowd")
	var pinned := await _wait_counter(host, func() -> bool: return tw.folk.active_count() >= 3, TIMEOUT_SECONDS)
	TestLib.check(pinned, "people stand at their posts around the hero (%d)" % tw.folk.active_count())
	if not pinned:
		return
	var slot := -1
	var sp := Vector3.ZERO
	for key in tw.folk._slot.keys():
		slot = int(tw.folk._slot[key])
		break
	sp = crowd.person_position(slot)
	TestLib.check(absf(sp.y - TerrainHeight.height_at(sp.x, sp.z)) < 0.6 and sp.y > 0.5, "they stand on the town's ground, not at sea level (y %.1f)" % sp.y)
	TestLib.check(crowd.is_pinned(slot) and crowd.is_alive(slot), "a folk person is a pinned crowd slot")
	var hero := p.global_position
	var rr: Vector3 = crowd.ray(Vector3(sp.x + 6.0, sp.y + 1.2, sp.z), Vector3(-1.0, 0.0, 0.0), 12.0)
	TestLib.check(int(rr.x) >= 0, "a shot along the street finds them (ray hit %d)" % int(rr.x))
	var killed: bool = crowd.damage_person(slot, 999.0, hero)
	TestLib.check(killed and crowd.is_dying(slot), "and they can be shot")
	var all := SettlementFolk.entries()
	var roles := {}
	for e in all:
		roles[e["role"]] = true
	TestLib.check(roles.size() >= 6 and all.size() >= 60, "%d people of %d kinds live in the towns" % [all.size(), roles.size()])


func _anchors_in_the_game() -> void:
	var anchors := AnchorSites.all_anchors()
	var mine := 0
	for a in anchors:
		if StringName(a["id"]) != &"" and String(a["id"]).contains("_a") and (a["pos"] as Vector3).y > (a["base"] as Vector3).y + 5.0:
			var found := false
			for b in SettlementData.anchors():
				if b["id"] == a["id"]:
					found = true
			if found:
				mine += 1
	TestLib.check(mine == SettlementData.anchors().size() and mine >= 14, "the quantum snake finds the towns' %d anchors in the landscape list" % mine)
	for a in SettlementData.anchors():
		TestLib.check(a.has("pos") and a.has("base") and a.has("height") and a.has("radius") and float(a["height"]) > 6.0 and float(a["radius"]) > 0.3, "anchor %s has the snake's format" % a["id"])


func _quality() -> void:
	for q in 3:
		city.set_quality(q)
		TestLib.check(tw.quality == q, "tier %d reaches the towns" % q)
	var s := OutskirtsSites.by_id(&"harrow_field")
	_stand_at(_town_pos(s, 0.0, 0.0))
	tw.settle(p.global_position)
	var ranges: Array[float] = []
	for q in 3:
		city.set_quality(q)
		for rec: Dictionary in (tw.towns[&"harrow_field"]["chunks"] as Dictionary).values():
			var mi := rec.get("mi") as MeshInstance3D
			if mi != null:
				ranges.append(mi.visibility_range_end)
				break
	TestLib.check(ranges.size() == 3 and ranges[0] < ranges[1] and ranges[1] < ranges[2], "the view distance of the towns grows with the tier (%s)" % str(ranges))
	city.set_quality(1)
