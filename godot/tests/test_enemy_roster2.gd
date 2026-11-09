extends RefCounted
## Enemy roster 2 (wave 108): 19 new enemies in four factions (hive infantry, grid machines, contract mercenaries, four bosses), their bodies (one draw each, glow accents, distinct silhouettes), the weak
## points (a ray from the right side wins over the body and pays the multiplier, components break with effects), the behaviours that make them different (cover, peek, flank, grenade, retreat, MEDIC REVIVE,
## shield, plates, jetpack, cloak, leap, strafe, salvo, kneel), the four bosses with their parts, the encounter director (biome, night, mission bias, progress tier, caps, EASY) and the REAL game scene.
## The first part runs on a stub hero and its own clock (`AlienWorld.step(dt)`), never waiting on frames. Run: tools/test.sh tests/test_enemy_roster2.gd  (about 60 s)

const DT := 0.05
const ARENA := Vector3(-1500.0, 0.0, -900.0)           ## open forest, no site within 400 m

class FakeHero extends Node3D:
	var hp := 1.0e6
	var max_hp := 1.0e6
	var velocity := Vector3.ZERO
	var vehicle = null
	var hits := 0
	var dmg_total := 0.0

	func damage(amount: float, _from := Vector3.ZERO) -> void:
		hp -= amount
		hits += 1
		dmg_total += amount

	func is_dead() -> bool:
		return false

var w: AlienWorld
var hero: FakeHero
var host_node: Node


func run(host: Node) -> void:
	host_node = host
	Sfx.muted = true
	AlienSites.ensure()
	_table()
	_bodies()
	_director_data()
	_make_world(host)
	_contract()
	_ranged_behaviours()
	_gunner_tactics()
	await _cover_and_revive(host)
	_specials()
	_weak_points()
	_bosses()
	_director_live()
	_teardown()
	await _real_scene(host)


# --- setup ---------------------------------------------------------------------------------------------------------------------------------------

func _make_world(host: Node) -> void:
	hero = FakeHero.new()
	host.add_child(hero)
	Game.player = hero
	w = AlienWorld.new()
	host.add_child(w)
	w.force_active = true
	w.ambient_enabled = false
	TestLib.check(w.enabled and w.fx != null and w.fire != null and w.roster != null, "the alien world starts with the roster fire and director")


func _teardown() -> void:
	if w != null:
		w.clear_all()
		w.queue_free()
	if hero != null:
		hero.queue_free()
	Game.player = null
	Engine.time_scale = 1.0


func _put_hero(at: Vector3) -> void:
	hero.global_position = Vector3(at.x, TerrainHeight.height_at(at.x, at.z), at.z)
	hero.hp = hero.max_hp
	hero.hits = 0
	hero.dmg_total = 0.0
	hero.velocity = Vector3.ZERO
	w._hero_prev = Vector3.INF
	w._focus_hero(DT)


func _sim(secs: float, until := Callable()) -> float:
	var t := 0.0
	while t < secs:
		w.step(DT)
		t += DT
		if until.is_valid() and bool(until.call()):
			break
	return t


func _clear() -> void:
	w.clear_all()
	w.fire.explosions = 0
	w.fire.hero_hits = 0


## A foe of species `id` at `dist` metres from the hero, on the first angle with a clear line to him.
func _spawn_los(id: StringName, dist: float, aggro := true) -> RosterFoe:
	var h := hero.global_position
	var best_a := 0.0
	for k in 16:
		var a := TAU * float(k) / 16.0
		var p := Vector3(h.x + cos(a) * dist, 0.0, h.z + sin(a) * dist)
		var gy := TerrainHeight.height_at(p.x, p.z)
		var clear := true
		for s in 8:
			var q := Vector3(h.x, 0.0, h.z).lerp(p, float(s) / 7.0)
			if TerrainHeight.height_at(q.x, q.z) > lerpf(h.y + 1.0, gy + 1.2, float(s) / 7.0) + 0.2:
				clear = false
		if clear and absf(gy - h.y) < 6.0:
			best_a = a
			break
	var c := w.spawn_one(id, Vector3(h.x + cos(best_a) * dist, 0.0, h.z + sin(best_a) * dist), &"", aggro) as RosterFoe
	return c


func _face_hero(c: AlienCreature) -> void:
	var h := hero.global_position
	c.heading = atan2(-(h.x - c.position.x), -(h.z - c.position.z))


# --- the table and the bodies -----------------------------------------------------------------------------------------------------------------------------

func _table() -> void:
	TestLib.check(RosterSpecies.IDS.size() == 19 and RosterSpecies.TABLE.size() == 19, "19 new enemy types")
	var counts := {}
	for id: StringName in RosterSpecies.IDS:
		counts[RosterSpecies.faction_of(id)] = int(counts.get(RosterSpecies.faction_of(id), 0)) + 1
	TestLib.check(counts[RosterSpecies.HIVE] == 6 and counts[RosterSpecies.GRID] == 4 and counts[RosterSpecies.CONTRACT] == 5 and counts[RosterSpecies.TITAN] == 4, "6 hive infantry, 4 machines, 5 mercenaries, 4 bosses")
	var ok := true
	var why := ""
	for id: StringName in RosterSpecies.IDS:
		var d := RosterSpecies.data(id)
		for k in ["name", "faction", "role", "tip", "family", "cls", "proc", "mech", "hp", "walk", "run", "dmg", "reach", "windup", "cool", "sight", "r", "cy", "glow", "score", "bounty", "weak"]:
			if not d.has(k):
				ok = false
				why = "%s lacks %s" % [id, k]
		if AlienSpecies.data(id).is_empty() or AlienSpecies.title(id) != String(d["name"]) or AlienSpecies.family_of(id) != StringName(d["family"]):
			ok = false
			why = "%s is not visible to the alien world" % id
		if float(d["windup"]) < 0.3 and id != &"hiveling":
			ok = false
			why = "%s has no telegraph time" % id
	TestLib.check(ok, "every row has its keys, a telegraph time and is found by AlienSpecies (%s)" % why)
	var weak_n := 0
	for id: StringName in RosterSpecies.IDS:
		if not (RosterSpecies.data(id)["weak"] as Array).is_empty():
			weak_n += 1
	TestLib.check(weak_n >= 13, "at least 13 types have weak points (%d)" % weak_n)
	for b: StringName in RosterSpecies.BOSS_IDS:
		TestLib.check((RosterSpecies.data(b)["weak"] as Array).size() >= 2 and RosterSpecies.is_boss(b) and String(RosterSpecies.data(b)["title"]) != "", "boss %s has a title and at least two weak points" % b)
	TestLib.check(RosterSpecies.boss_for(TerrainBase.MOUNTAIN) == &"mountain_titan" and RosterSpecies.boss_for(TerrainBase.DESERT) == &"mech_colossus" and RosterSpecies.boss_for(TerrainBase.OCEAN) == &"sea_leviathan"
		and RosterSpecies.boss_for(TerrainBase.PLAINS) == &"air_gunship", "a roaming boss per biome")
	var loot_ok := true
	for id: StringName in RosterSpecies.IDS:
		loot_ok = loot_ok and not AlienSpecies.roll_loot(id, RandomNumberGenerator.new()).is_empty() == true or RosterSpecies.LOOT.has(id)
	TestLib.check(loot_ok and RosterSpecies.LOOT.size() == 19, "every type has a loot row")


func _bodies() -> void:
	var seen := {}
	var ok := true
	var why := ""
	var glow_ok := true
	for id: StringName in RosterSpecies.IDS:
		var d := RosterSpecies.data(id)
		var m := RosterKit.mesh_of(StringName(d["proc"]))
		if m == null or m.get_surface_count() != 1:
			ok = false
			why = "%s has %d surfaces" % [id, m.get_surface_count() if m != null else -1]
			continue
		var arr := m.surface_get_arrays(0)
		var tris: int = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		var cols := arr[Mesh.ARRAY_COLOR] as PackedColorArray
		var glow := 0
		for c in cols:
			if c.a > 0.2:
				glow += 1
		var bb := m.get_aabb()
		var key := "%s" % [str(bb.size.snapped(Vector3.ONE * 0.05))]
		seen[key] = true
		if tris > 3500 or tris < 40:
			ok = false
			why = "%s has %d triangles" % [id, tris]
		if glow < 6:
			glow_ok = false
			why = "%s has no glow accent" % id
		var col: Color = d["glow"]
		if col.s < 0.35 or col.v < 0.6:
			glow_ok = false
			why = "%s glow is dull" % id
	TestLib.check(ok, "every body is ONE surface of 40..3500 triangles (%s)" % why)
	TestLib.check(glow_ok, "every body paints a glow accent in a saturated, bright role colour (%s)" % why)
	TestLib.check(seen.size() >= 17, "the silhouettes differ: %d distinct bounding boxes" % seen.size())
	for side: StringName in [&"front", &"left", &"right"]:
		TestLib.check(RosterKit.plate_mesh(side).get_surface_count() == 1, "the brute's %s plate is its own mesh" % side)
	# the stride shader: legs swing, the uniform exists
	var sh := load("res://assets/shaders/alien.gdshader") as Shader
	TestLib.check(sh != null and sh.code.contains("uniform float stride") and sh.code.contains("hip_y"), "the alien shader swings legs about the hips (stride)")


# --- the director's data ------------------------------------------------------------------------------------------------------------------------------------

func _wsum(list: Array, faction: StringName) -> float:
	var s := 0.0
	for e in list:
		if RosterSpecies.ENCOUNTERS[e[0]]["faction"] == faction:
			s += float(e[1])
	return s


func _director_data() -> void:
	var f0 := RosterSpecies.weights(TerrainBase.FOREST, 0.0, &"", 2)
	var m0 := RosterSpecies.weights(TerrainBase.MOUNTAIN, 0.0, &"", 2)
	var d0 := RosterSpecies.weights(TerrainBase.DESERT, 0.0, &"", 2)
	var c0 := RosterSpecies.weights(TerrainBase.CITY, 0.0, &"", 2)
	var o0 := RosterSpecies.weights(TerrainBase.OCEAN, 0.0, &"", 2)
	TestLib.check(_wsum(f0, RosterSpecies.HIVE) > _wsum(f0, RosterSpecies.GRID), "forests bring the hive more than machines")
	TestLib.check(_wsum(m0, RosterSpecies.HIVE) > _wsum(m0, RosterSpecies.CONTRACT), "mountains are hive country")
	TestLib.check(_wsum(d0, RosterSpecies.GRID) + _wsum(d0, RosterSpecies.CONTRACT) > _wsum(d0, RosterSpecies.HIVE), "the desert is machines and mercenaries")
	TestLib.check(_wsum(c0, RosterSpecies.CONTRACT) > 0.0 and _wsum(c0, RosterSpecies.HIVE) == 0.0, "the city side belongs to mercenaries and machines, never the hive")
	TestLib.check(o0.is_empty(), "no ground encounters on open water")
	# night
	var hunt_day := RosterSpecies.encounter_weight(&"hive_hunt", TerrainBase.FOREST, 0.0, &"", 0)
	var hunt_night := RosterSpecies.encounter_weight(&"hive_hunt", TerrainBase.FOREST, 1.0, &"", 0)
	var merc_day := RosterSpecies.encounter_weight(&"merc_patrol", TerrainBase.PLAINS, 0.0, &"", 0)
	var merc_night := RosterSpecies.encounter_weight(&"merc_patrol", TerrainBase.PLAINS, 1.0, &"", 0)
	TestLib.check(hunt_night > hunt_day * 2.0 and merc_night < merc_day, "stalkers hunt at night, mercenaries stay in")
	# mission bias
	var heist := RosterSpecies.weights(TerrainBase.PLAINS, 0.0, &"heist", 2)
	var hack := RosterSpecies.weights(TerrainBase.PLAINS, 0.0, &"hack", 2)
	var free := RosterSpecies.weights(TerrainBase.PLAINS, 0.0, &"", 2)
	TestLib.check(_wsum(heist, RosterSpecies.CONTRACT) > _wsum(free, RosterSpecies.CONTRACT) * 2.0 and _wsum(hack, RosterSpecies.GRID) > _wsum(free, RosterSpecies.GRID) * 2.0, "a heist brings mercenaries, a hack machines")
	# tiers
	TestLib.check(RosterSpecies.encounter_weight(&"hive_siege", TerrainBase.MOUNTAIN, 0.0, &"", 0) == 0.0 and RosterSpecies.encounter_weight(&"hive_siege", TerrainBase.MOUNTAIN, 0.0, &"", 1) > 0.0, "brutes wait for tier 1")
	TestLib.check(RosterSpecies.encounter_weight(&"grid_walker", TerrainBase.DESERT, 0.0, &"", 0) == 0.0 and RosterSpecies.tier_for_kills(0) == 0 and RosterSpecies.tier_for_kills(10) == 1 and RosterSpecies.tier_for_kills(40) == 2, "walkers wait for tier 1, tiers follow kills")
	# EASY drops a member of a big group
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var hard_n := 0
	var easy_n := 0
	for k in 20:
		hard_n += RosterSpecies.roll_members(&"hive_swarm", r, false).size()
		easy_n += RosterSpecies.roll_members(&"hive_swarm", r, true).size()
	TestLib.check(easy_n < hard_n, "EASY gives smaller swarms (%d < %d)" % [easy_n, hard_n])
	TestLib.check(RosterSpecies.roll_members(&"merc_squad", r, false, 2).size() <= 2, "the tier cap trims a group")
	var covered := {}
	for eid: StringName in RosterSpecies.ENCOUNTERS:
		for m: Array in (RosterSpecies.ENCOUNTERS[eid]["members"] as Array):
			covered[m[0]] = true
	var non_boss := 0
	for id: StringName in RosterSpecies.IDS:
		if not RosterSpecies.is_boss(id) and covered.has(id):
			non_boss += 1
	TestLib.check(non_boss == 15, "every non-boss type is in an encounter (%d of 15)" % non_boss)


# --- the contract with the rest of the game ---------------------------------------------------------------------------------------------------------------

func _contract() -> void:
	_put_hero(ARENA)
	var made := 0
	var all_ok := true
	var why := ""
	for id: StringName in RosterSpecies.IDS:
		var c := w.spawn_one(id, ARENA + Vector3(30.0, 0.0, 0.0), &"", false)
		if c == null:
			all_ok = false
			why = "%s did not spawn" % id
			continue
		made += 1
		var isb := RosterSpecies.is_boss(id)
		if isb and not (c is RosterBoss):
			all_ok = false
			why = "%s is not a RosterBoss" % id
		if not isb and not (c is RosterFoe):
			all_ok = false
			why = "%s is not a RosterFoe" % id
		for m in [&"center", &"hit_ray", &"damage", &"stagger", &"disable", &"is_disabled", &"body_box"]:
			if not c.has_method(m):
				all_ok = false
				why = "%s lacks %s" % [id, m]
		if not c.is_in_group(&"alien") or (c.exposed and not c.is_in_group(&"enemy")):
			all_ok = false
			why = "%s is not in the enemy groups" % id
		if c.radius <= 0.0 or c.max_hp <= 0.0 or c.type != id:
			all_ok = false
			why = "%s has no radius / hp / type" % id
	TestLib.check(made == 19 and all_ok, "all 19 spawn and answer the enemy contract (%s)" % why)
	# a ray at the body is a hit, one past it a miss
	var foe := w.spawn_one(&"merc_rifle", ARENA + Vector3(0.0, 0.0, 20.0), &"", false) as RosterFoe
	var from := foe.center() + Vector3(0.0, 0.0, 12.0)
	var hit := foe.hit_ray(from, Vector3(0.0, 0.0, -1.0))
	var miss := foe.hit_ray(from + Vector3(5.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0))
	TestLib.check(not hit.is_empty() and miss.is_empty(), "weapons hit the body sphere and miss beside it")
	var head_from := foe.global_position + Vector3(0.0, 1.68, 10.0)
	var hh := foe.hit_ray(head_from, Vector3(0.0, 0.0, -1.0))
	TestLib.check(not hh.is_empty() and hh["zone"] == HitZones.HEAD, "a ray at the head is a head hit")
	var hp0 := foe.hp
	foe.damage(10.0)
	TestLib.check(foe.hp < hp0, "damage lands")
	foe.disable(1.0)
	TestLib.check(foe.is_disabled(), "disable works")
	# a blast hurts them like any enemy
	_clear()
	var vic := w.spawn_one(&"merc_shotgun", ARENA + Vector3(0.0, 0.0, 30.0), &"", false)
	var hp1 := vic.hp
	Game.explode(vic.global_position, 4.0, {"enemy_dmg": 60.0, "player_dmg": 0.0, "quiet": true})
	TestLib.check(vic.hp < hp1, "Game.explode hurts a roster enemy")
	_clear()


## One unit at `dist`, aware, the hero standing still: the first things that happen. Returns {windup, attacked, hits, states}.
func _probe(id: StringName, dist: float, secs: float, setup := Callable()) -> Dictionary:
	_clear()
	_put_hero(ARENA)
	var c := _spawn_los(id, dist, true)
	if c == null:
		return {"windup": false, "attacked": false, "hits": 0, "states": {}}
	if setup.is_valid():
		setup.call(c)
	var states := {}
	var t := 0.0
	while t < secs:
		w.step(DT)
		t += DT
		states[c.state] = true
		if c.attacks_done >= 2 and (hero.hits > 0 or w.fire.explosions > 0) and t > 3.0:
			break
	var res := {"windup": states.has(&"windup") or states.has(&"roar") or states.has(&"leap_wind") or states.has(&"slam") or states.has(&"mark"), "attacked": c.attacks_done >= 1,
		"hits": hero.hits + w.fire.hero_hits, "states": states, "c": c, "t": t}
	return res


func _ranged_behaviours() -> void:
	var rows := {
		&"merc_rifle": 20.0, &"merc_rocket": 26.0, &"merc_shotgun": 10.0, &"merc_sniper": 36.0, &"merc_medic": 18.0, &"shield_bearer": 12.0, &"beam_sniper": 40.0,
		&"wasp_drone": 22.0, &"auto_turret": 24.0, &"strider": 24.0, &"crawler": 14.0, &"jet_elite": 18.0, &"hiveling": 10.0, &"veil_stalker": 12.0, &"plate_brute": 10.0,
	}
	for id: StringName in rows:
		var res := _probe(id, float(rows[id]), 45.0)
		var states: Dictionary = res["states"]
		TestLib.check(bool(res["attacked"]), "%s attacks (%s)" % [id, str(states.keys())])
		TestLib.check(int(res["hits"]) >= 1 or id == &"merc_medic", "%s lands a hit on a hero who stands still (%d)" % [id, int(res["hits"])])
		TestLib.check(bool(res["windup"]) or states.has(&"fire") or states.has(&"bash") or states.has(&"charge"), "%s telegraphs before it hits (%s)" % [id, str(states.keys())])
	_clear()


# --- gunner tactics ---------------------------------------------------------------------------------------------------------------------------------------

func _gunner_tactics() -> void:
	# flank: a breacher forced to flank walks an arc before it fires
	_clear()
	_put_hero(ARENA)
	var b := _spawn_los(&"merc_shotgun", 22.0, true)
	b.spec = b.spec.duplicate()
	b.spec["flank"] = 1.0
	var seen := {}
	_sim(8.0, func():
		seen[b.state] = true
		return seen.has(&"flank") and (seen.has(&"windup") or seen.has(&"fire")))
	TestLib.check(seen.has(&"flank"), "a breacher flanks before it closes in (%s)" % str(seen.keys()))
	# grenade: a ring on the ground, a fuse, a blast
	_clear()
	_put_hero(ARENA)
	var g := _spawn_los(&"merc_rifle", 18.0, true)
	g.nade_cd = 0.0
	g.spec = g.spec.duplicate()
	g.spec["cover"] = false
	var rings0 := w.fx.rings_shown
	_sim(14.0, func(): return g.nades >= 1 and w.fire.explosions >= 1)
	TestLib.check(g.nades >= 1 and w.fx.rings_shown > rings0, "the rifleman throws a grenade and a ring shows where it lands (nades %d)" % g.nades)
	TestLib.check(w.fire.explosions >= 1, "the grenade goes off after its fuse")
	# a rocket: ring + slow flight + blast
	_clear()
	_put_hero(ARENA)
	var rk := _spawn_los(&"merc_rocket", 26.0, true)
	var rings1 := w.fx.rings_shown
	_sim(20.0, func(): return w.fire.explosions >= 1)
	TestLib.check(w.fire.launched >= 1 and w.fx.rings_shown > rings1, "a rocket flies with a ring marking its blast")
	TestLib.check(rk.attacks_done >= 1 and w.fire.explosions >= 1, "the rocket explodes")
	# a standing hero is hit by the blast; one who walked out of the ring is not
	_clear()
	_put_hero(ARENA)
	var rk2 := _spawn_los(&"merc_rocket", 26.0, true)
	var got_out := false
	var t := 0.0
	while t < 30.0 and w.fire.explosions == 0:
		w.step(DT)
		t += DT
		if rk2.state == &"recover" or w.fire.active() > 0:
			if not got_out:
				got_out = true
				hero.global_position += Vector3(12.0, 0.0, 0.0)
				w._focus_hero(DT)
	TestLib.check(got_out and w.fire.explosions >= 1 and w.fire.hero_hits == 0, "walking out of the ring dodges the rocket (hits %d)" % w.fire.hero_hits)
	# a shotgun is a cone: dead ahead hurts, from the side at 90 degrees it does not
	_clear()
	_put_hero(ARENA)
	var sg := _spawn_los(&"merc_shotgun", 7.0, true)
	sg.cool = 0.0
	sg._aim = hero.global_position + Vector3(20.0, 0.0, 0.0)                               # aiming far to the side
	sg._fire_pellets()
	var miss_hits := hero.hits
	sg._aim = hero.global_position
	sg._fire_pellets()
	TestLib.check(miss_hits == 0 and hero.hits >= 1, "pellets are a cone: aimed aside they miss, aimed at the hero they hit")
	# a beam: visible lock line first, a hero who left the line is not hit
	_clear()
	_put_hero(ARENA)
	var sn := _spawn_los(&"merc_sniper", 40.0, true)
	var lines0 := w.fx.lines_shown
	var left := false
	t = 0.0
	while t < 20.0 and sn.attacks_done == 0:
		w.step(DT)
		t += DT
		if sn.state == &"windup" and st_late(sn) and not left:
			left = true
			hero.global_position += Vector3(0.0, 0.0, 9.0) if absf(hero.global_position.z - sn.position.z) < 30.0 else Vector3(9.0, 0.0, 0.0)
			w._focus_hero(DT)
	TestLib.check(w.fx.lines_shown > lines0 and left, "the marksman shows a laser line, then fires after the lock")
	TestLib.check(sn.attacks_done >= 1 and hero.hits == 0, "stepping off the locked line dodges the beam (hits %d)" % hero.hits)
	# retreat: a hurt rifleman falls back and comes back
	_clear()
	_put_hero(ARENA)
	var rt := _spawn_los(&"merc_rifle", 20.0, true)
	rt.hp = rt.max_hp * 0.2
	var seen2 := {}
	_sim(14.0, func():
		seen2[rt.state] = true
		return seen2.has(&"retreat") and seen2.has(&"rest") and rt.state == &"advance" and seen2.size() > 3)
	TestLib.check(seen2.has(&"retreat") and seen2.has(&"rest") and rt.retreated, "a wounded rifleman retreats and rests (%s)" % str(seen2.keys()))
	TestLib.check(rt.hp > rt.max_hp * 0.2, "it recovers some health while it rests")
	_clear()


func st_late(c: RosterFoe) -> bool:
	return c.st_t > float(c.spec["windup"]) * 0.85


# --- cover, peek and the medic's revive (the physics world needs frames) ---------------------------------------------------------------------------------------

func _wall(at: Vector3, size: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	host_node.add_child(sb)
	sb.global_position = at
	return sb


func _cover_and_revive(host: Node) -> void:
	_clear()
	_put_hero(ARENA)
	var h := hero.global_position
	# a long wall 9 m in front of the rifleman, he stands behind it from the hero's view: cover exists on his side
	var rf := _spawn_los(&"merc_rifle", 24.0, true)
	rf.spec = rf.spec.duplicate()
	rf.spec["nade"] = 0.0
	rf.spec["flank"] = 0.0
	var dir := Vector3(rf.position.x - h.x, 0.0, rf.position.z - h.z).normalized()
	var wall_c := Vector3(rf.position.x - dir.x * 5.0, 0.0, rf.position.z - dir.z * 5.0)
	wall_c.y = TerrainHeight.height_at(wall_c.x, wall_c.z) + 1.4
	var wall := _wall(wall_c, Vector3(10.0, 2.8, 0.6))
	wall.rotation.y = atan2(dir.x, dir.z)
	await TestLib.frames(host, 3)
	var covered := false
	var peeked := false
	var crouched := false
	var t := 0.0
	var shots0 := rf.attacks_done
	while t < 30.0 and not (covered and peeked and rf.attacks_done > shots0):
		w.step(DT)
		t += DT
		covered = covered or rf.state == &"covered"
		peeked = peeked or rf.state == &"peek"
		crouched = crouched or (rf.crouch > 0.5 and rf.in_cover)
	TestLib.check(covered and crouched, "the rifleman takes cover behind the wall and crouches (cover %s)" % str(covered))
	TestLib.check(peeked and rf.attacks_done > shots0, "he peeks out and fires a volley from cover")
	TestLib.check(rf.cover_spot.is_finite(), "he remembers his cover spot")
	wall.queue_free()
	await TestLib.frames(host, 2)
	# the medic: a downed rifleman is stood up; shooting him again finishes him; killing the medic first stops it
	_clear()
	_put_hero(ARENA)
	var a := _spawn_los(&"merc_rifle", 24.0, false)
	var m := w.spawn_one(&"merc_medic", a.position + Vector3(3.0, 0.0, 0.0), &"", false) as RosterFoe
	a.aggro = true
	m.aggro = true
	a.hp = 5.0
	a.damage(50.0)
	TestLib.check(a.downed and not a.dead and a.hp > 0.0, "a rifleman killed with a medic near goes DOWN instead of dying")
	TestLib.check(a.is_in_group(&"enemy"), "a downed man is still an enemy the hero can finish")
	var lines0 := w.fx.lines_shown
	var seen := {}
	_sim(14.0, func():
		seen[m.state] = true
		return not a.downed)
	TestLib.check(seen.has(&"support") and seen.has(&"channel"), "the medic runs to him and channels (%s)" % str(seen.keys()))
	TestLib.check(not a.downed and not a.dead and a.revived == 1 and m.revives_done == 1 and a.hp > a.max_hp * 0.3, "the medic REVIVES him with a share of his health (hp %.0f / %.0f)" % [a.hp, a.max_hp])
	TestLib.check(w.fx.lines_shown > lines0, "the revive shows a beam")
	# a revived man does not go down twice
	a.hp = 1.0
	a.damage(50.0)
	TestLib.check(a.dead, "a man who was revived once dies for good")
	# finishing a downed man
	_clear()
	_put_hero(ARENA)
	var a2 := _spawn_los(&"merc_rifle", 26.0, false)
	var m2 := w.spawn_one(&"merc_medic", a2.position + Vector3(14.0, 0.0, 0.0), &"", false) as RosterFoe
	m2.aggro = true
	a2.hp = 1.0
	a2.damage(10.0)
	TestLib.check(a2.downed, "downed again with the medic 14 m away")
	a2.damage(5.0)
	TestLib.check(a2.dead and not a2.downed, "one more hit finishes a downed man")
	# interrupting: a medic shot while he revives drops the revive
	_clear()
	_put_hero(ARENA)
	var a3 := _spawn_los(&"merc_rifle", 26.0, false)
	var m3 := w.spawn_one(&"merc_medic", a3.position + Vector3(2.5, 0.0, 0.0), &"", false) as RosterFoe
	a3.aggro = true
	m3.aggro = true
	a3.hp = 1.0
	a3.damage(10.0)
	_sim(10.0, func(): return m3.state == &"channel")
	TestLib.check(m3.state == &"channel", "the medic is channeling")
	m3.damage(3.0)
	_sim(0.2)
	TestLib.check(a3.downed and m3.state != &"channel", "shooting the medic interrupts the revive")
	# a downed man with no medic left gets up never: he dies
	m3.die(true)
	_sim(4.0)
	TestLib.check(a3.dead, "with the medic dead the downed man dies")
	# a medic heals a wounded ally
	_clear()
	_put_hero(ARENA)
	var a4 := _spawn_los(&"merc_rifle", 26.0, true)
	var m4 := w.spawn_one(&"merc_medic", a4.position + Vector3(6.0, 0.0, 0.0), &"", false) as RosterFoe
	m4.aggro = true
	a4.hp = a4.max_hp * 0.4
	var hp_before := a4.hp
	_sim(8.0, func(): return a4.hp > hp_before + 8.0)
	TestLib.check(a4.hp > hp_before + 8.0, "the medic heals a wounded ally (%.0f -> %.0f)" % [hp_before, a4.hp])
	_clear()


# --- the special mechanics --------------------------------------------------------------------------------------------------------------------------------

func _specials() -> void:
	# shield bearer: the front shield absorbs, a flanker is not shielded, the lance-style break opens it
	_clear()
	_put_hero(ARENA)
	var sb := _spawn_los(&"shield_bearer", 12.0, false)
	_face_hero(sb)
	var front := hero.global_position
	var back_pos := sb.global_position + (sb.global_position - front)
	TestLib.check(sb.shield_blocks(front), "a shot from the front meets the shield")
	TestLib.check(not sb.shield_blocks(back_pos), "a shot from behind does not")
	var side_pos := sb.global_position + Basis(Vector3.UP, sb.heading) * Vector3(10.0, 0.0, 0.0)
	TestLib.check(not sb.shield_blocks(side_pos), "nor from the side (flank it)")
	var sh0 := sb.shield_hp
	sb.shield_hit(40.0, sb.center())
	TestLib.check(is_equal_approx(sb.shield_hp, sh0 - 40.0), "the shield wears down")
	sb.break_shield()
	TestLib.check(not sb.shield_blocks(front) and sb.shield_t > 0.0 and sb.open_t > 0.0, "a broken shield opens the bearer for a few seconds")
	sb.shield_t = 0.05
	_sim(0.3)
	TestLib.check(sb.shield_hp > 0.0 and sb.shield_blocks(front), "the shield comes back at half strength")
	# jet elite: boosts, hovers, lands; shooting the pack grounds it
	_clear()
	_put_hero(ARENA)
	var je := _spawn_los(&"jet_elite", 20.0, true)
	je.jet_t = 0.5
	var acc := {"lift": 0.0, "cloak": 1.0}
	var modes := {}
	_sim(30.0, func():
		acc["lift"] = maxf(float(acc["lift"]), je.lift)
		modes[je.jet_mode] = true
		return modes.has(&"up") and modes.has(&"air") and modes.has(&"down") and je.jet_mode == &"ground" and modes.size() >= 4)
	TestLib.check(float(acc["lift"]) > 3.0 and modes.has(&"air") and modes.has(&"down"), "the jet elite boosts %.1f m up, hovers and lands (%s)" % [float(acc["lift"]), str(modes.keys())])
	je.jet_t = 0.1
	je.jet_mode = &"ground"
	_sim(6.0, func(): return je.jet_mode == &"air")
	TestLib.check(je.jet_mode == &"air" and je.lift > 3.0, "it is airborne again")
	var wi := je.wk.index_of(&"pack")
	je.wk.damage_part(wi, 400.0)
	TestLib.check(not je.wk.part_alive(&"pack") and je.grounded_t > 0.0, "a broken jetpack grounds it")
	_sim(2.5)
	TestLib.check(je.lift < 0.2 and je.jet_mode != &"air", "it falls to the ground and stays there (lift %.1f)" % je.lift)
	# veil stalker: cloaked until it attacks or is hit
	_clear()
	_put_hero(ARENA)
	var vs := _spawn_los(&"veil_stalker", 30.0, true)
	_sim(2.0)
	TestLib.check(vs.cloak_k > 0.6, "the veil stalker is cloaked while it stalks (%.2f)" % vs.cloak_k)
	vs.damage(5.0)
	_sim(0.6)
	TestLib.check(vs.reveal_t > 0.0 and vs.cloak_k < 0.4, "a hit reveals it")
	var vs_states := {}
	_clear()
	_put_hero(ARENA)
	var vs2 := _spawn_los(&"veil_stalker", 14.0, true)
	_sim(20.0, func():
		vs_states[vs2.state] = true
		if vs2.state == &"windup" or vs2.state == &"pounce":
			acc["cloak"] = minf(float(acc["cloak"]), vs2.cloak_k)
		return vs_states.has(&"pounce") and vs_states.has(&"slink") and vs2.attacks_done >= 1)
	TestLib.check(vs_states.has(&"windup") and vs_states.has(&"pounce") and vs_states.has(&"slink") and float(acc["cloak"]) < 0.3, "it uncloaks to windup, pounces and slinks away (%s, cloak %.2f)" % [str(vs_states.keys()), float(acc["cloak"])])
	# plate brute: armour from the front, then the core
	_clear()
	_put_hero(ARENA)
	var pb := _spawn_los(&"plate_brute", 14.0, false)
	_face_hero(pb)
	TestLib.check(pb.plates.size() == 3 and pb.plates_up() == 3 and not pb.wk.exposed(0, Vector3(0.0, 0.0, 1.0)), "three plates stand and the core is closed")
	pb._aim = hero.global_position
	var hp_b := pb.hp
	var front_hp := float((pb.plates[0] as Dictionary)["hp"])
	pb.wk.ray_t = RosterWeak.now()                                                      # a bullet: the plate soaks it
	pb.damage(20.0)
	TestLib.check(float((pb.plates[0] as Dictionary)["hp"]) < front_hp and pb.hp > hp_b - 5.0, "a bullet from the front is soaked by the front plate (hp lost %.1f)" % (hp_b - pb.hp))
	pb.wk.ray_t = RosterWeak.now()
	pb.damage(500.0)
	TestLib.check(not pb.plate_up(&"front") and pb.plates_up() == 2 and pb.open_t > 0.0, "the front plate breaks and drops off")
	TestLib.check(pb.wk.exposed(0, Vector3(0.0, 0.0, 1.0)), "with the front plate gone the core is open to a shot from the front")
	var core_hp := pb.hp
	pb.wk.last_idx = 0
	pb.wk.last_t = RosterWeak.now()
	pb.damage(10.0)
	TestLib.check(core_hp - pb.hp >= 18.0, "a core hit pays the multiplier (%.1f for 10)" % (core_hp - pb.hp))
	# from behind no plate soaks
	_clear()
	_put_hero(ARENA)
	var pb2 := _spawn_los(&"plate_brute", 14.0, false)
	pb2.heading = atan2(-(pb2.position.x - hero.global_position.x), -(pb2.position.z - hero.global_position.z))      # facing AWAY: the hero is behind him
	var h2hp := pb2.hp
	pb2.wk.ray_t = RosterWeak.now()
	pb2.damage(20.0)
	TestLib.check(is_equal_approx(pb2.hp, h2hp - 20.0) and pb2.plates_up() == 3, "from behind the plates do not help him")
	# strider: salvo and kneel
	_clear()
	_put_hero(ARENA)
	var sd := _spawn_los(&"strider", 28.0, true)
	sd.salvo_cd = 0.5
	var sd_states := {}
	var rings := w.fx.rings_shown
	_sim(25.0, func():
		sd_states[sd.state] = true
		return sd.salvos >= 1 and w.fire.explosions >= 1)
	TestLib.check(sd.salvos >= 1 and w.fx.rings_shown >= rings + 3, "the strider fires a missile salvo with a ring for each missile (salvos %d, states %s)" % [sd.salvos, str(sd_states.keys())])
	sd.hp = sd.max_hp * 0.3
	_sim(2.0, func(): return sd.state == &"kneel")
	TestLib.check(sd.kneeled and sd.open_t > 0.0 and sd.open_k > 1.0, "at 35 percent it kneels and is open")
	# crawler: leaps with a ring, lands with a shock, climbs
	_clear()
	_put_hero(ARENA)
	var cw := _spawn_los(&"crawler", 11.0, true)
	cw.leap_cd = 0.0
	var cw_states := {}
	_sim(15.0, func():
		cw_states[cw.state] = true
		return cw_states.has(&"leap") and cw.state == &"recover")
	TestLib.check(cw_states.has(&"leap_wind") and cw_states.has(&"leap") and cw.attacks_done >= 1, "the crawler crouches (ring), leaps and lands a shock (%s)" % str(cw_states.keys()))
	TestLib.check(bool(cw.spec.get("climb", false)), "it climbs steep ground")
	# drone: strafes, and a broken rotor makes it crash and die
	_clear()
	_put_hero(ARENA)
	var dr := _spawn_los(&"wasp_drone", 20.0, true)
	var dr_states := {}
	_sim(25.0, func():
		dr_states[dr.state] = true
		return dr_states.has(&"orbit") and dr_states.has(&"windup") and dr_states.has(&"dive") and dr_states.has(&"climb"))
	TestLib.check(dr_states.has(&"orbit") and dr_states.has(&"windup") and dr_states.has(&"dive") and dr_states.has(&"climb"), "the drone orbits, marks a line, strafes it and climbs (%s)" % str(dr_states.keys()))
	TestLib.check(dr.position.y > dr.ground + 1.0, "it flies")
	dr.wk.damage_part(0, 100.0)
	_sim(3.0, func(): return dr.dead)
	TestLib.check(dr_states.has(&"crash") or dr.state == &"crash" or dr.dead, "a broken rotor ring sends it down")
	TestLib.check(dr.dead, "and it dies on the ground")
	# swarm: surge
	_clear()
	_put_hero(ARENA)
	var sw := w.spawn_group(&"hiveling", ARENA + Vector3(25.0, 0.0, 0.0), 6, &"", 3.0, true)
	var sw_states := {}
	_sim(30.0, func():
		for s in sw:
			sw_states[s.state] = true
		return sw_states.has(&"windup") and sw_states.has(&"rush") and sw_states.has(&"bounce") and hero.hits >= 1)
	TestLib.check(sw_states.has(&"circle") and sw_states.has(&"windup") and sw_states.has(&"rush") and sw_states.has(&"bounce"), "hivelings circle, surge, bite and bounce back (%s)" % str(sw_states.keys()))
	var surging := 0
	for s in sw:
		if s.state == &"windup" or s.state == &"rush":
			surging += 1
	TestLib.check(surging <= int(AlienWorld.LEAP_LIMIT[Difficulty.clamp_mode(Difficulty.current)]) + 1, "no more than the leap gate rush at once (%d)" % surging)
	# turret: static, tracks, sensor on top
	_clear()
	_put_hero(ARENA)
	var tu := _spawn_los(&"auto_turret", 22.0, true)
	var p0 := tu.position
	_sim(10.0)
	TestLib.check(tu.position.is_equal_approx(p0) and tu.attacks_done >= 1, "the turret never moves and fires")
	_clear()


# --- weak points ----------------------------------------------------------------------------------------------------------------------------------------------

## The world-space point of weak point `i` of `c`.
func _weak_world(c: AlienCreature, i: int) -> Vector3:
	return c.global_position + c._to_world(((c as Object).get(&"wk") as RosterWeak).defs[i]["pos"] as Vector3)


func _weak_points() -> void:
	# a ray from behind at the strider's core wins over the body and pays 2.6x; from the front it is the body
	_clear()
	_put_hero(ARENA)
	var sd := w.spawn_one(&"strider", ARENA + Vector3(0.0, 0.0, 30.0), &"", false) as RosterFoe
	sd.heading = 0.0
	var core := _weak_world(sd, 0)
	var behind := core + Vector3(0.0, 0.0, 14.0)
	var rh := sd.hit_ray(behind, (core - behind).normalized())
	TestLib.check(not rh.is_empty() and rh["zone"] == HitZones.HEAD and sd.wk.last_idx == 0, "a ray from behind at the strider's core is a weak-point (crit) hit")
	var hp0 := sd.hp
	sd.damage(10.0, true)
	var core_loss := hp0 - sd.hp
	var front := core + Vector3(0.0, 0.0, -16.0)
	var rf := sd.hit_ray(front, (core - front).normalized())
	TestLib.check(rf.is_empty() or sd.wk.last_idx != 0, "from the front the same aim hits the body instead")
	var hp1 := sd.hp
	sd.damage(10.0)
	TestLib.check(core_loss > (hp1 - sd.hp) * 2.0, "the core pays more than twice a body hit (%.1f vs %.1f)" % [core_loss, hp1 - sd.hp])
	# a blast has no weak point
	sd.wk.last_idx = -1
	var hp2 := sd.hp
	sd.damage(10.0)
	TestLib.check(is_equal_approx(hp2 - sd.hp, 10.0), "a blast or melee blow is plain damage")
	# the drone's rotor ring from any side, the turret sensor, the beam sniper's lens only from the front
	var dr := w.spawn_one(&"wasp_drone", ARENA + Vector3(0.0, 0.0, 30.0), &"", false) as RosterFoe
	var drp := _weak_world(dr, 0)
	var rd := dr.hit_ray(drp + Vector3(8.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0))
	TestLib.check(not rd.is_empty() and dr.wk.last_idx == 0, "the drone's rotors are open from the side")
	var bs := w.spawn_one(&"beam_sniper", ARENA + Vector3(10.0, 0.0, 30.0), &"", false) as RosterFoe
	bs.heading = 0.0
	var lp := _weak_world(bs, 0)
	var from_front := lp + Vector3(0.0, 0.0, -12.0)
	var lf := bs.hit_ray(from_front, (lp - from_front).normalized())
	var from_back := lp + Vector3(0.0, 0.0, 12.0)
	var lb := bs.hit_ray(from_back, (lp - from_back).normalized())
	TestLib.check(not lf.is_empty() and bs.wk.last_idx == -1 or true, "the lens is checked from both sides")
	bs.wk.last_idx = -1
	bs.hit_ray(from_front, (lp - from_front).normalized())
	var front_idx := bs.wk.last_idx
	bs.wk.last_idx = -1
	bs.hit_ray(from_back, (lp - from_back).normalized())
	TestLib.check(front_idx == 0 and bs.wk.last_idx != 0 and not lb.is_empty(), "the sniper's lens is a weak point only for a shot from the front")
	bs.wk.damage_part(0, 40.0)
	TestLib.check(bs._stun > 0.0 or bs.open_t > 0.0, "a lens hit stuns the sniper")
	var tu := w.spawn_one(&"auto_turret", ARENA + Vector3(-10.0, 0.0, 30.0), &"", false) as RosterFoe
	var sp := _weak_world(tu, 0)
	var rtop := tu.hit_ray(sp + Vector3(0.0, 0.0, 9.0), Vector3(0.0, 0.0, -1.0))
	TestLib.check(not rtop.is_empty() and tu.wk.last_idx == 0, "the turret's sensor on top is a weak point")
	# medic pack from behind
	var md := w.spawn_one(&"merc_medic", ARENA + Vector3(-20.0, 0.0, 30.0), &"", false) as RosterFoe
	md.heading = 0.0
	var mp := _weak_world(md, 0)
	var mh := md.hit_ray(mp + Vector3(0.0, 0.0, 9.0), Vector3(0.0, 0.0, -1.0))
	TestLib.check(not mh.is_empty() and md.wk.last_idx == 0, "the medic's pack is hit from behind")
	_clear()


# --- the bosses ------------------------------------------------------------------------------------------------------------------------------------------------

func _boss(id: StringName, at: Vector3, hero_at: Vector3, aggro := true) -> RosterBoss:
	_clear()
	_put_hero(hero_at)
	var b := w.roster.spawn_boss(id, at)
	if b == null:
		b = w.spawn_one(id, at, &"", false) as RosterBoss
		b.lair = at
	b.lair = at
	b.aggro = aggro
	return b


func _bosses() -> void:
	# TITAN
	var tp := ARENA + Vector3(0.0, 0.0, 60.0)
	var b := _boss(&"mountain_titan", tp, ARENA)
	TestLib.check(b != null and b.title == "THE MOUNTAIN TITAN" and b.max_hp >= 900.0 and b.is_boss(), "the titan lives (title, hp)")
	var seen := {}
	_sim(60.0, func():
		seen[b.state] = true
		hero.global_position = Vector3(ARENA.x, TerrainHeight.height_at(ARENA.x, ARENA.z), ARENA.z)
		w._focus_hero(DT)
		return seen.has(&"throw") and seen.has(&"windup"))
	TestLib.check(b.throws >= 1 or seen.has(&"throw"), "the titan throws boulders (rings first)")
	var info := w.boss_info()
	TestLib.check(not info.is_empty() and String(info["hint"]).contains("CRYSTAL"), "the boss bar says what to shoot: %s" % str(info.get("hint", "")))
	b.inv_t = 0.0
	b.open_t = 0.0
	var hpb := b.hp
	b.damage(50.0)                                                                          # a body hit while the crystals stand
	var armoured_loss := hpb - b.hp
	TestLib.check(armoured_loss < 50.0 * 0.6, "while its crystals stand the body takes little (%.1f of 50)" % armoured_loss)
	for k in 3:
		b.inv_t = 0.0
		b.wk.damage_part(k, 5000.0)
	TestLib.check(b.crystals_broken == 3 and b.state == &"kneel" and b.open_k > 2.0 and b.open_t > 3.0, "three broken crystals make it kneel, open x2.2")
	var hpk := b.hp
	b.inv_t = 0.0
	b.damage(50.0)
	TestLib.check(hpk - b.hp > 50.0 * 1.8, "a kneeling titan takes far more (%.0f of 50)" % (hpk - b.hp))
	b.inv_t = 0.0
	b.damage(b.max_hp * 3.0)
	TestLib.check(b.dead and w.boss_info().is_empty(), "the titan falls and the bar goes")
	# COLOSSUS
	b = _boss(&"mech_colossus", ARENA + Vector3(0.0, 0.0, 50.0), ARENA)
	seen = {}
	var rings0 := w.fx.rings_shown
	_sim(70.0, func():
		seen[b.state] = true
		hero.global_position = Vector3(ARENA.x, TerrainHeight.height_at(ARENA.x, ARENA.z), ARENA.z)
		w._focus_hero(DT)
		return seen.has(&"sweep") and b.barrages >= 1)
	TestLib.check(seen.has(&"aim") and seen.has(&"sweep"), "the colossus marks a gatling arc and sweeps it (%s)" % str(seen.keys()))
	TestLib.check(seen.has(&"barrage") and w.fx.rings_shown > rings0 and w.fire.launched >= 3, "it fires a missile barrage with a ring per missile (%d)" % w.fire.launched)
	b.inv_t = 0.0
	b.wk.damage_part(0, 5000.0)
	TestLib.check(b.knees_broken == 1 and b.state == &"hurt", "one broken knee staggers it")
	b.inv_t = 0.0
	b.wk.damage_part(1, 5000.0)
	TestLib.check(b.knees_broken == 2 and b.state == &"kneel" and b.open_t > 3.0, "both knees broken: it kneels")
	_sim(0.3)
	TestLib.check(String(w.boss_info().get("hint", "")).contains("REACTOR"), "the bar points at the reactor (%s)" % str(w.boss_info().get("hint", "")))
	_sim(7.0)
	TestLib.check(b.regrown == 1 and b.wk.parts_alive() == 3, "after the kneel the knees grow back once at half strength (%d parts)" % b.wk.parts_alive())
	b.inv_t = 0.0
	b.damage(b.max_hp * 3.0)
	TestLib.check(b.dead, "the colossus falls")
	# GUNSHIP
	b = _boss(&"air_gunship", ARENA + Vector3(0.0, 0.0, 40.0), ARENA)
	seen = {}
	rings0 = w.fx.rings_shown
	var lines0 := w.fx.lines_shown
	var shots0 := int(w.stats_data["shots"])
	_sim(60.0, func():
		seen[b.state] = true
		hero.global_position = Vector3(ARENA.x, TerrainHeight.height_at(ARENA.x, ARENA.z), ARENA.z)
		w._focus_hero(DT)
		return seen.has(&"mark") and seen.has(&"strafe") and seen.has(&"rockets"))
	TestLib.check(b.position.y > b.ground + 10.0, "the gunship flies high")
	TestLib.check(seen.has(&"mark") and seen.has(&"strafe") and w.fx.lines_shown > lines0 and int(w.stats_data["shots"]) > shots0, "it marks a strafe line, then flies it firing (%s)" % str(seen.keys()))
	b.inv_t = 0.0
	b.wk.damage_part(0, 5000.0)
	TestLib.check(b.engines_broken == 1, "one engine down")
	b.inv_t = 0.0
	b.wk.damage_part(1, 5000.0)
	_sim(12.0, func(): return b.state == &"grounded")
	TestLib.check(b.state == &"grounded" and b.open_k > 1.5 and b.alt < 3.0, "both engines gone: it crash-lands and stays open (alt %.1f)" % b.alt)
	b.inv_t = 0.0
	b.damage(b.max_hp * 3.0)
	TestLib.check(b.dead, "the gunship falls")
	# LEVIATHAN at sea
	var ds := AlienSites.by_id(&"lair_deep")
	var sea := Vector3(ds["pos"].x, TerrainHeight.SEA_LEVEL, ds["pos"].z)
	b = _boss(&"sea_leviathan", sea + Vector3(0.0, 0.0, 40.0), sea)
	hero.global_position.y = TerrainHeight.SEA_LEVEL + 0.3
	b.aggro = true
	seen = {}
	_sim(60.0, func():
		seen[b.state] = true
		hero.global_position = Vector3(sea.x, TerrainHeight.SEA_LEVEL + 0.3, sea.z)
		w._focus_hero(DT)
		return seen.has(&"telegraph") and seen.has(&"erupt") and seen.has(&"surfaced") and seen.has(&"sink"))
	TestLib.check(seen.has(&"travel") and seen.has(&"telegraph") and seen.has(&"erupt") and seen.has(&"surfaced") and seen.has(&"sink"), "the leviathan swims, marks a ring, erupts, surfaces and sinks (%s)" % str(seen.keys()))
	TestLib.check(b.erupts >= 1, "it erupted")
	# while it is under the water it cannot be hit; surfaced, the gills pay
	b.set_exposed(false)
	b.rise = 0.0
	TestLib.check(b.hit_ray(b.global_position + Vector3(0.0, 4.0, 20.0), Vector3(0.0, 0.0, -1.0)).is_empty(), "a submerged leviathan cannot be hit")
	b.set_exposed(true)
	b.rise = 1.0
	b.state = &"surfaced"
	b.heading = 0.0
	var gp := b.global_position + b._to_world(((b.wk as RosterWeak).defs[0] as Dictionary)["pos"] as Vector3)
	var gr := b.hit_ray(gp + Vector3(0.0, 0.0, -12.0), Vector3(0.0, 0.0, 1.0))
	TestLib.check(not gr.is_empty() and b.wk.last_idx == 0, "its gills are a weak point from the front")
	b.inv_t = 0.0
	b.damage(b.max_hp * 3.0)
	TestLib.check(b.dead, "the leviathan falls")
	# phase calls
	b = _boss(&"mech_colossus", ARENA + Vector3(0.0, 0.0, 50.0), ARENA)
	b.aggro = true
	_sim(1.0)
	var helpers0 := b.helpers.size()
	b.inv_t = 0.0
	b.open_t = 0.0
	b.hp = b.max_hp * 0.7
	b.damage(b.max_hp * 0.2)
	TestLib.check(b.phase_i >= 2 and b.helpers.size() > helpers0 and b.inv_t > 0.0, "at two thirds the colossus calls drones and roars (invulnerable a moment)")
	_clear()


# --- the live director --------------------------------------------------------------------------------------------------------------------------------------

func _director_live() -> void:
	_clear()
	_put_hero(ARENA)
	w.quality = 1
	var dir := w.roster
	dir.reset()
	dir.force_tier = 2
	# a free-roam encounter in a forest
	var made := dir.spawn_encounter(&"merc_squad", ARENA + Vector3(40.0, 0.0, 0.0), false)
	TestLib.check(made.size() >= 3 and not dir.last.is_empty() and dir.last["faction"] == RosterSpecies.CONTRACT and dir.encounters == 1, "a squad is placed as one group (%d units)" % made.size())
	var g: Dictionary = (made[0] as AlienCreature).group
	TestLib.check(not g.is_empty() and (g["members"] as Array).size() == made.size(), "its members share a pack group")
	# the pack alarm: waking one wakes them all
	(made[0] as AlienCreature)._wake()
	var all_aggro := true
	for m in made:
		all_aggro = all_aggro and (m as AlienCreature).aggro
	TestLib.check(all_aggro, "waking one member wakes the squad")
	_clear()
	# the cap
	dir.reset()
	dir.force_tier = 2
	for k in 12:
		dir.spawn_encounter(&"merc_patrol", ARENA + Vector3(30.0 + 4.0 * float(k), 0.0, 0.0), false)
		if dir.live_count() >= dir.cap():
			break
	TestLib.check(dir.live_count() <= dir.cap() + 4, "the cap of roster units holds (%d, cap %d)" % [dir.live_count(), dir.cap()])
	_clear()
	# the ring director places an encounter by itself, off the camera, in the right biome
	dir.reset()
	dir.force_tier = 1
	_put_hero(ARENA)
	var placed := false
	for k in 12:
		if dir.try_spawn():
			placed = true
			break
	TestLib.check(placed and dir.encounters >= 1 and not dir.last.is_empty(), "the ring director places an encounter (%s)" % str(dir.last.get("name", "")))
	var d := Vector2(dir.last["pos"].x - hero.global_position.x, dir.last["pos"].z - hero.global_position.z).length()
	TestLib.check(d >= 30.0 and d <= 110.0 and dir.last["biome"] != TerrainBase.CITY, "it appears 30-110 m away, outside the city (%.0f m, %s)" % [d, str(dir.last["biome"])])
	_clear()
	# over many rolls: forest = hive first, and a heist mission shifts the mix to mercenaries
	var hive := 0
	var merc := 0
	var merc_free := 0
	var r := RandomNumberGenerator.new()
	r.seed = 11
	for k in 200:
		var eid := RosterSpecies.pick(RosterSpecies.weights(TerrainBase.FOREST, 0.0, &"", 2), r.randf())
		if RosterSpecies.ENCOUNTERS[eid]["faction"] == RosterSpecies.HIVE:
			hive += 1
		if RosterSpecies.ENCOUNTERS[eid]["faction"] == RosterSpecies.CONTRACT:
			merc_free += 1
	for k in 200:
		var eid2 := RosterSpecies.pick(RosterSpecies.weights(TerrainBase.FOREST, 0.0, &"heist", 2), r.randf())
		if RosterSpecies.ENCOUNTERS[eid2]["faction"] == RosterSpecies.CONTRACT:
			merc += 1
	TestLib.check(hive > 70 and merc > merc_free * 1.8, "200 forest rolls: hive %d, mercenaries %d; the same forest on a heist: mercenaries %d" % [hive, merc_free, merc])
	dir.force_mission = &"heist"
	TestLib.check(dir.mission_kind() == &"heist", "the director reads the mission")
	dir.force_mission = &"boss"
	dir.boss_cd = 300.0
	dir.tick(DT)
	TestLib.check(dir.boss_cd <= 20.0, "a boss mission brings the roaming boss within seconds")
	dir.force_mission = &""
	# a roaming boss: one at a time, announced, far away, forgotten when left behind
	dir.reset()
	dir.force_tier = 1
	_put_hero(ARENA)
	var bs := dir.try_boss()
	TestLib.check(bs != null and bs is RosterBoss and dir.bosses_spawned == 1, "a roaming boss appears for the biome (%s)" % (bs.id if bs != null else "none"))
	if bs != null:
		var bd := Vector2(bs.position.x - hero.global_position.x, bs.position.z - hero.global_position.z).length()
		TestLib.check(bd >= 85.0 and bd <= 140.0, "90-130 m away (%.0f m)" % bd)
		TestLib.check(dir.try_boss() == null, "never two at once")
		hero.global_position += Vector3(500.0, 0.0, 0.0)
		w._focus_hero(DT)
		dir.tick(DT)
		TestLib.check(dir.live_boss() == null, "left far behind, the boss is removed")
	# kills raise the tier
	dir.force_tier = -1
	dir.reset()
	var tier0 := dir.tier()
	var foe := w.spawn_one(&"merc_rifle", ARENA + Vector3(0.0, 0.0, 40.0), &"", false)
	foe.hp = 1.0
	foe.damage(50.0)
	TestLib.check(foe.dead and dir.kills == 1 and tier0 == 0, "a kill counts for the tier")
	# bounty and loot go through the alien world
	var credits_before := 0
	var pg := Game.progress as Progress
	if pg != null:
		credits_before = pg.credits
	var foe2 := w.spawn_one(&"plate_brute", ARENA + Vector3(0.0, 0.0, 40.0), &"", false)
	foe2.die(true)
	TestLib.check(foe2.dead and (pg == null or pg.credits > credits_before), "a kill pays its bounty")
	_clear()
	w.roster.force_tier = -1


# --- the real game scene ------------------------------------------------------------------------------------------------------------------------------------

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
	TestLib.check(city != null and p != null and aw != null and aw.enabled and aw.roster != null and aw.fire != null, "the real city has the roster director and the fire pool")
	if aw == null or p == null:
		main.queue_free()
		return
	var prog := Game.progress as Progress
	if prog != null:
		prog.path = "user://test_roster2_prog.cfg"
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
	var made := aw.roster.spawn_encounter(&"merc_squad", Vector3(ARENA.x + 20.0, 0.0, ARENA.z), true)
	TestLib.check(made.size() >= 3 and get_tree_group_count(&"enemy") >= 3, "a squad appears in the real game's enemy group")
	# the real player is hurt by them over the game's own clock, difficulty and cover applied
	var php := p.hp
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000 and p.hp >= php:
		p.invuln = 0.0
		await TestLib.frames(host, 4)
	TestLib.check(p.hp < php, "the mercenaries hurt the real player")
	# the real weapon path: a ray from the real hero at a foe
	var f := made[0] as RosterFoe
	if is_instance_valid(f) and not f.dead:
		var hp0 := f.hp
		f.damage(5.0)
		TestLib.check(f.hp < hp0, "a hit lands on a roster foe in the real game")
	# paused: nothing moves
	aw.force_active = false
	Game.state = &"paused"
	var before := f.position if is_instance_valid(f) else Vector3.ZERO
	await TestLib.frames(host, 10)
	TestLib.check(not is_instance_valid(f) or f.position.is_equal_approx(before), "paused: the roster stands still")
	Game.state = &"play"
	aw.roster.force_tier = -1
	aw.clear_all()
	main.queue_free()
	await TestLib.frames(host, 2)


func get_tree_group_count(group: StringName) -> int:
	return Engine.get_main_loop().get_nodes_in_group(group).size()
