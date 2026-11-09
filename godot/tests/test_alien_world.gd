extends RefCounted
## The alien world outside the city (wave 107b): the species table (every model file, rows, loot), the sites (15 found places: camps, nests, crash sites, boss lairs, all on dry ground of the
## right biome and apart), every creature behaviour (leap, melee, burst, spit, slam, ambush, swoop, float, turret, nest, burrow, serpent: each one TELEGRAPHS and then lands an attack on a hero
## who stands still), the five bosses and their signature mechanics (broodmother sac and calls, drake lightning / dive / grounded, leviathan eruption, kraken arms and shield, warden relays and
## shield), the weapon contract (group `enemy`, damage, hit_ray head and body, buried bodies untouchable), loot (credits, crafting parts, milestone weapon), site clearing and persistence, the
## ambient spawn director per biome (never in the city), and the REAL game scene (City.aliens is wired, a camp populates when the hero walks up, map pins, the boss bar feed).
## The first part runs on a stub hero and its own clock (`AlienWorld.step(dt)`), so it never waits on frames or machine speed. Run: tools/test.sh tests/test_alien_world.gd  (about 40 s)

const TIMEOUT_SECONDS := 140.0
const DT := 0.05
const ARENA := Vector3(-1500.0, 0.0, -900.0)           ## open forest, no site within 400 m: creature tests are not disturbed by a camp

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
var host_node: Node


func run(host: Node) -> void:
	host_node = host
	Sfx.muted = true
	AlienSites.reset_all()
	AlienLoot.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AlienSites.SAVE_PATH))
	_table()
	_sites()
	_make_world(host)
	await _contract(host)
	_creatures()
	_bosses()
	_site_clear()
	_loot()
	_ambient()
	_persistence()
	_teardown()
	await _real_scene(host)
	AlienSites.reset_all()
	AlienLoot.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AlienSites.SAVE_PATH))


# --- setup ---------------------------------------------------------------------------------------------------------------------------------------

func _make_world(host: Node) -> void:
	hero = FakeHero.new()
	host.add_child(hero)
	Game.player = hero
	w = AlienWorld.new()
	host.add_child(w)
	w.force_active = true
	w.ambient_enabled = false
	TestLib.check(w.enabled and w.fx != null, "the alien world starts (models present)")


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


func _spawn_near(id: StringName, dist: float, aggro := true, ang := 0.0) -> AlienCreature:
	var h := hero.global_position
	var c := w.spawn_one(id, Vector3(h.x + cos(ang) * dist, 0.0, h.z + sin(ang) * dist), &"", aggro)
	return c


# --- table, sites ----------------------------------------------------------------------------------------------------------------------------------

func _table() -> void:
	TestLib.check(AlienSpecies.FAUNA_IDS.size() == 6 and AlienSpecies.CAMP_IDS.size() == 7 and AlienSpecies.BOSS_IDS.size() == 5, "6 fauna, 7 camp creatures, 5 bosses")
	var ok := true
	for id: StringName in AlienSpecies.ids():
		var d := AlienSpecies.data(id)
		for k in ["name", "family", "cls", "mech", "hp", "dmg", "sight", "r", "glow", "score", "bounty"]:
			ok = ok and d.has(k)
		var mp := AlienSpecies.model_path(id)
		if mp != "":
			ok = ok and ResourceLoader.exists(mp)
		else:
			ok = ok and d.has("proc") and AlienKit.proc_mesh(StringName(d["proc"])) != null
	TestLib.check(ok, "every species has its rows and either a model file or a procedural body")
	var bio := {}
	for b in AlienSpecies.BOSS_IDS:
		bio[String(AlienSpecies.data(b).get("biome", ""))] = true
	TestLib.check(bio.size() == 5 and bio.has("forest") and bio.has("mountain") and bio.has("desert") and bio.has("ocean") and bio.has("plains"), "one boss per biome")
	TestLib.check(AlienSpecies.weights(AlienSpecies.BURROW, TerrainBase.DESERT, 5.0, 0.1, 0.0).size() == 1 and AlienSpecies.weights(AlienSpecies.BURROW, TerrainBase.FOREST, 5.0, 0.1, 0.0).is_empty(), "burrowers live under the desert only")
	TestLib.check(AlienSpecies.weights(AlienSpecies.AIR, TerrainBase.MOUNTAIN, 150.0, 0.5, 0.0)[0][0] == &"swarmer" and AlienSpecies.weights(AlienSpecies.WATER, TerrainBase.OCEAN, -10.0, 0.0, 0.0)[0][0] == &"reef_lurker", "swarmers over the mountains, lurkers at sea")
	TestLib.check(AlienSpecies.weights(AlienSpecies.GROUND, TerrainBase.CITY, 2.0, 0.0, 0.0).is_empty(), "no alien fauna in the city biome")
	var night_w: float = 0.0
	var day_w: float = 0.0
	for e in AlienSpecies.weights(AlienSpecies.GROUND, TerrainBase.FOREST, 10.0, 0.1, 1.0):
		if e[0] == &"skitter":
			night_w = e[1]
	for e in AlienSpecies.weights(AlienSpecies.GROUND, TerrainBase.FOREST, 10.0, 0.1, 0.0):
		if e[0] == &"skitter":
			day_w = e[1]
	TestLib.check(night_w > day_w, "pack hunters are bolder at night")
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var got := 0
	for i in 40:
		got += (AlienSpecies.roll_loot(&"sand_leviathan", r) as Array).size()
	TestLib.check(got >= 40 * 2, "a boss always drops several parts")
	TestLib.check(AlienSpecies.pick([[&"a", 1.0], [&"b", 3.0]], 0.9) == &"b" and AlienSpecies.pick([], 0.5) == &"", "weighted pick")


func _sites() -> void:
	AlienSites.ensure()
	TestLib.check(AlienSites.list.size() == AlienSites.DEFS.size() and AlienSites.list.size() == 15, "15 sites placed")
	var kinds := {}
	var ok_biome := true
	var ok_apart := true
	var ok_dry := true
	var ok_city := true
	for i in AlienSites.list.size():
		var s := AlienSites.list[i]
		kinds[s["kind"]] = int(kinds.get(s["kind"], 0)) + 1
		var p: Vector3 = s["pos"]
		ok_city = ok_city and maxf(absf(p.x), absf(p.z)) >= AlienSites.CITY_SKIRT
		if not s.has("reuse"):
			var biome := TerrainBase.biome_at(p.x, p.z, TerrainHeight.height_at(p.x, p.z) if s["kind"] != &"lair" or s.get("boss", &"") != &"deep_kraken" else -30.0)
			ok_biome = ok_biome and (s["biomes"] as Array).has(biome)
			if s["kind"] != &"lair" or s.get("boss", &"") != &"deep_kraken":
				ok_dry = ok_dry and TerrainHeight.water_level_for(p.x, p.z, p.y) == TerrainHeight.NO_WATER
		for j in range(i + 1, AlienSites.list.size()):
			var q: Vector3 = AlienSites.list[j]["pos"]
			if Vector2(p.x - q.x, p.z - q.z).length() < 200.0 and not (s.has("reuse") or AlienSites.list[j].has("reuse")):
				ok_apart = false
	TestLib.check(int(kinds.get(&"camp", 0)) == 5 and int(kinds.get(&"nest", 0)) == 3 and int(kinds.get(&"crash", 0)) == 3 and int(kinds.get(&"lair", 0)) == 4, "5 camps, 3 nests, 3 crash sites, 4 lairs")
	TestLib.check(ok_city, "every site lies outside the city")
	TestLib.check(ok_biome, "every site stands in a biome its definition allows (camps in mountains and canyons)")
	TestLib.check(ok_dry, "no land site stands in water")
	TestLib.check(ok_apart, "sites are at least 200 m apart")
	var crash := AlienSites.by_id(&"crash")
	var oc := OutskirtsSites.by_id(&"crash")
	TestLib.check(not crash.is_empty() and Vector2((crash["pos"] as Vector3).x - (oc["pos"] as Vector3).x, (crash["pos"] as Vector3).z - (oc["pos"] as Vector3).z).length() < 1.0, "the existing crash site gets the warden and its relays")
	var hooks := AlienSites.hooks()
	var hok := hooks.size() == 15
	for h in hooks:
		hok = hok and h.has("id") and h.has("pos") and int(h["reward"]) > 0 and String(h["tag"]) != ""
	TestLib.check(hok, "mission hooks carry id, pos, reward, tag")
	TestLib.check(AlienSites.map_markers().size() == 15, "15 map pins")
	var bosses := {}
	for s in AlienSites.of_kind(&"lair"):
		bosses[s["boss"]] = true
	bosses[crash["boss"]] = true
	TestLib.check(bosses.size() == 5, "five different bosses live at the lairs and the big crash site")
	var kit_ok := true
	for s in AlienSites.list:
		var kit := AlienSiteKit.build(s)
		if s.has("no_mesh") or s.get("boss", &"") == &"deep_kraken":
			continue
		var good := not kit.is_empty() and int(kit["tris"]) > 300 and int(kit["tris"]) < 9000
		if not good:
			print("   site mesh out of range: ", s["id"], " ", kit.get("tris", 0))
		kit_ok = kit_ok and good
	TestLib.check(kit_ok, "every site has a mesh of 300 to 9000 triangles (one draw call)")


# --- the enemy contract ---------------------------------------------------------------------------------------------------------------------------

func _contract(host: Node) -> void:
	_put_hero(ARENA)
	var c := _spawn_near(&"hive_grunt", 12.0, false)
	TestLib.check(c != null and c.is_in_group(&"enemy") and c.is_in_group(&"alien"), "a creature is an enemy of the game (group enemy)")
	TestLib.check(not c.dead and c.radius > 0.3 and c.center().distance_to(c.global_position) > 0.3 and c.has_method(&"damage") and c.has_method(&"hit_ray") and c.has_method(&"stagger") and c.has_method(&"disable"), "it answers the enemy contract")
	var cp := c.center()
	var head := c.global_position + c._to_world(((c.shapes[1] as Array)[0]) as Vector3)
	var o := cp + Vector3(0.0, 0.0, 8.0)
	var hz := HitZones.of(c, o, (cp - o).normalized())
	TestLib.check(not hz.is_empty() and hz["zone"] == HitZones.BODY, "a ray at the chest hits the body")
	var oh := head + Vector3(0.0, 0.0, 8.0)
	var hh := HitZones.of(c, oh, (head - oh).normalized())
	TestLib.check(not hh.is_empty() and hh["zone"] == HitZones.HEAD, "a ray at the head is a crit")
	TestLib.check(HitZones.of(c, o, Vector3.UP).is_empty(), "a ray that misses is a miss")
	var hp0 := c.hp
	c.damage(10.0, false)
	TestLib.check(c.hp < hp0 and c.aggro, "damage hurts it and wakes it")
	c.stagger(1.0)
	TestLib.check(c._stun > 0.0, "a hit staggers it")
	c.disable(2.0)
	TestLib.check(c.is_disabled(), "COLLAPSE disables it")
	# a blast from the game's own explode() reaches it
	var before := c.hp
	Game.explode(c.global_position, 3.0, {"enemy_dmg": 30.0, "car_dmg": 0.0, "player_dmg": 0.0})
	TestLib.check(c.hp < before, "a blast damages it like any enemy")
	var kills0 := AlienWorld.total_kills
	var credits0 := (Game.progress as Progress).credits if Game.progress != null else 0
	var died := [0]
	c.died.connect(func(_x): died[0] += 1)
	c.damage(1.0e6, true)
	TestLib.check(c.dead and died[0] == 1 and not c.is_in_group(&"enemy") and AlienWorld.total_kills == kills0 + 1 and int(w.kills.get(&"hive_grunt", 0)) >= 1, "a kill: dead, out of the enemy group, counted, signalled once")
	c.damage(10.0)
	c.die()
	TestLib.check(died[0] == 1, "dying is idempotent")
	if Game.progress != null:
		TestLib.check((Game.progress as Progress).credits >= credits0 + int(AlienSpecies.data(&"hive_grunt")["bounty"] * 0.5), "the bounty is paid")
	_sim(2.0, func(): return c.is_gone())
	TestLib.check(c.is_gone() or c.dead, "the body dissolves")
	_sim(1.0)
	TestLib.check(not w.creatures.has(c) or c.is_gone(), "the dead creature leaves the list")
	_clear()
	# burrowed bodies are untouchable and not enemies
	var m := w.spawn_one(&"dune_maw", Vector3(1674.0, 0.0, 32.0), &"", false)
	TestLib.check(m != null and not m.exposed and not m.is_in_group(&"enemy") and m.hit_ray(Vector3(1674.0, 20.0, 32.0), Vector3.DOWN).is_empty(), "a buried dune maw is no target (not in the enemy group, no hit)")
	var hp1 := m.hp
	m.damage(500.0)
	TestLib.check(is_equal_approx(m.hp, hp1), "and takes no damage")
	_clear()
	await TestLib.frames(host, 1)


# --- creature behaviours ------------------------------------------------------------------------------------------------------------------------------

func _attacker(id: StringName, dist: float, secs: float, extra_hero := Vector3.ZERO) -> Dictionary:
	_clear()
	_put_hero(extra_hero if extra_hero != Vector3.ZERO else ARENA)
	var c := _spawn_near(id, dist, true)
	if c == null:
		return {}
	var telegraphed := [false]
	var hits0 := hero.hits
	var t := 0.0
	while t < secs:
		w.step(DT)
		t += DT
		if c.state == &"windup" or c.state == &"crouch" or c.state == &"hover" or c.state == &"fuse" or c.state == &"telegraph" or c.state == &"lance_wind":
			telegraphed[0] = true
		if hero.hits > hits0 and telegraphed[0]:
			break
		if not is_instance_valid(c) or c.dead and id != &"popper":
			break
	return {"c": c, "hit": hero.hits > hits0, "tele": telegraphed[0], "t": t}


func _creatures() -> void:
	var specs := [
		[&"skitter", 14.0, 10.0], [&"hive_grunt", 10.0, 10.0], [&"popper", 12.0, 12.0], [&"acid_spitter", 16.0, 14.0], [&"crag_brute", 9.0, 12.0],
		[&"shade_stalker", 12.0, 14.0], [&"swarmer", 16.0, 14.0], [&"drift_ray", 22.0, 16.0], [&"spore_sentry", 20.0, 10.0],
	]
	for e in specs:
		var res := _attacker(e[0], float(e[1]), float(e[2]))
		TestLib.check(not res.is_empty() and bool(res["hit"]), "%s lands an attack on a hero who stands still" % e[0])
		TestLib.check(not res.is_empty() and bool(res["tele"]), "%s telegraphs before it attacks" % e[0])
	# the pack: skitters fan out round the hero (their slots differ) and never all leap at once on EASY
	_clear()
	Difficulty.current = Difficulty.EASY
	_put_hero(ARENA)
	var pack := w.spawn_group(&"skitter", hero.global_position + Vector3(20.0, 0.0, 0.0), 5, &"", 3.0, true)
	TestLib.check(pack.size() == 5 and pack[0].group == pack[4].group, "a pack of five shares a group")
	var max_att := 0
	for i in 400:
		w.step(DT)
		var n := 0
		for c in pack:
			if c.state == &"crouch" or c.state == &"leap":
				n += 1
		max_att = maxi(max_att, n)
	TestLib.check(max_att >= 1 and max_att <= int(AlienWorld.LEAP_LIMIT[0]), "on EASY at most %d skitters attack at once (saw %d)" % [AlienWorld.LEAP_LIMIT[0], max_att])
	Difficulty.current = Difficulty.NORMAL
	# the popper that dies early only pops; the alarm: hurting one pack member wakes the others
	_clear()
	_put_hero(ARENA)
	var pk := w.spawn_group(&"skitter", hero.global_position + Vector3(25.0, 0.0, 0.0), 3, &"", 2.0, false)
	pk[0].damage(1.0)
	TestLib.check(pk[1].aggro and pk[2].aggro, "hurting one pack member wakes the pack")
	# the slam ring: a hero in the air when the brute slams takes nothing
	_clear()
	_put_hero(ARENA)
	var br := _spawn_near(&"crag_brute", 4.0, true)
	hero.global_position.y += 3.5
	var hits0 := hero.hits
	_sim(6.0, func(): return br.attacks_done > 0 or br.state == &"recover")
	TestLib.check(hero.hits == hits0, "a jump clears the brute's shockwave")
	# burrowers: the full cycle travel -> telegraph -> erupt -> exposed -> sink, hurt only when risen
	_clear()
	_put_hero(Vector3(1674.0, 0.0, 32.0))
	var mw := _spawn_near(&"dune_maw", 25.0, true)
	var seen := {}
	var hurt_hidden := false
	var t := 0.0
	while t < 22.0:
		w.step(DT)
		t += DT
		seen[mw.state] = true
		if not mw.exposed:
			var h0 := mw.hp
			mw.damage(100.0)
			hurt_hidden = hurt_hidden or mw.hp < h0
		if seen.has(&"exposed") and seen.has(&"sink") and seen.has(&"travel") and t > 10.0:
			break
	TestLib.check(seen.has(&"travel") and seen.has(&"telegraph") and seen.has(&"erupt") and seen.has(&"exposed") and seen.has(&"sink"), "the dune maw tunnels, marks the ring, erupts, stays up, sinks (saw %s)" % str(seen.keys()))
	TestLib.check(not hurt_hidden and mw.attacks_done >= 1, "it cannot be hurt while buried and its eruption hit the hero")
	# the lurker
	_clear()
	var ds := AlienSites.by_id(&"lair_deep")
	_put_hero(Vector3(ds["pos"].x, 0.0, ds["pos"].z))
	hero.global_position.y = TerrainHeight.SEA_LEVEL + 0.3
	var lk := _spawn_near(&"reef_lurker", 22.0, true)
	var seen2 := {}
	var t2 := 0.0
	hero.global_position.y = TerrainHeight.SEA_LEVEL + 0.3
	while t2 < 24.0:
		w.step(DT)
		t2 += DT
		seen2[lk.state] = true
		hero.global_position.y = TerrainHeight.SEA_LEVEL + 0.3
		if seen2.has(&"exposed") and seen2.has(&"sink"):
			break
	TestLib.check(seen2.has(&"telegraph") and seen2.has(&"erupt") and seen2.has(&"exposed") and seen2.has(&"sink"), "the reef lurker marks a ring on the water, rises, strikes, sinks (saw %s)" % str(seen2.keys()))
	# the nest hatches skitters until its heart is destroyed
	_clear()
	_put_hero(ARENA)
	var heart := _spawn_near(&"hive_heart", 30.0, false)
	heart.site = &"forest_nest"
	var hatched0 := int(w.stats_data["hatched"])
	_sim(25.0, func(): return int(w.stats_data["hatched"]) > hatched0)
	TestLib.check(int(w.stats_data["hatched"]) > hatched0 and w.census(hero.global_position, 120.0).get(&"skitter", 0) >= 1, "a hive heart hatches skitters")
	# telegraph rings were drawn
	TestLib.check(w.fx.rings_shown > 0 and w.fx.lines_shown > 0, "ground rings and aim lines were drawn")
	TestLib.check(int(w.stats_data["shots"]) > 0 and int(w.stats_data["clouds"]) > 0, "projectiles flew and a spore cloud hung")
	_clear()


# --- bosses ---------------------------------------------------------------------------------------------------------------------------------------------

func _boss_at(site_id: StringName, offset: Vector3) -> AlienBoss:
	_clear()
	AlienSites.reset_all()
	w.sites.clear()
	var s := AlienSites.by_id(site_id)
	var sp: Vector3 = s["pos"]
	_put_hero(sp + offset)
	w.populate(site_id)
	var b := (w.sites[site_id] as Dictionary).get("boss") as AlienBoss
	return b


func _bosses() -> void:
	# BROODMOTHER
	var b := _boss_at(&"lair_forest", Vector3(0.0, 0.0, 30.0))
	TestLib.check(b != null and b.title == "THE FOREST BROODMOTHER" and b.max_hp >= 800.0, "the broodmother lives at the forest lair")
	var seen := {}
	var open_seen := false
	var clouds0 := int(w.stats_data["clouds"])
	var t := 0.0
	while t < 40.0 and not (seen.has(&"lob") and seen.has(&"windup") and open_seen):
		w.step(DT)
		t += DT
		seen[b.state] = true
		open_seen = open_seen or b.open_t > 0.0
		hero.global_position = b.global_position + Vector3(0.0, 0.0, 8.0) if b.state == &"chase" and t > 12.0 else hero.global_position
	TestLib.check(seen.has(&"lob") and seen.has(&"windup") and open_seen, "the broodmother lobs spores, slams, and is winded (open) afterwards (saw %s)" % str(seen.keys()))
	TestLib.check(int(w.stats_data["clouds"]) > clouds0 or w.active_projectiles() > 0, "its spore clouds fly")
	var info := w.boss_info()
	TestLib.check(not info.is_empty() and info["name"] == b.title and float(info["frac"]) > 0.99 and String(info["hint"]) != "", "the boss bar feed: name, health, one hint")
	var helpers0 := b.helpers.size()
	b.inv_t = 0.0
	b.open_t = 0.0
	b.damage(b.max_hp * 0.40)
	TestLib.check(b.phase_i == 2 and b.helpers.size() > helpers0 and b.inv_t > 0.0, "at two thirds it calls skitters and roars (invulnerable a moment)")
	var hp_inv := b.hp
	b.damage(50.0)
	TestLib.check(is_equal_approx(b.hp, hp_inv), "a roaring boss takes no damage")
	b.inv_t = 0.0
	b.open_t = 2.0
	b.open_k = 2.0
	var h1 := b.hp
	b.damage(10.0)
	TestLib.check(h1 - b.hp >= 19.9, "the sac takes double damage while it is open")
	b.inv_t = 0.0
	b.damage(b.max_hp)
	TestLib.check(b.dead and AlienSites.boss_down(&"broodmother") and AlienSites.is_cleared(&"lair_forest") and w.boss_info().is_empty(), "the broodmother falls: lair cleared, boss down, the bar goes")
	# STORM DRAKE
	b = _boss_at(&"lair_peak", Vector3(0.0, 0.0, 30.0))
	TestLib.check(b != null and b.cls == AlienSpecies.AIR and b.position.y > TerrainHeight.height_at(b.position.x, b.position.z) + 10.0, "the storm drake circles high over its roost")
	seen = {}
	var strikes_seen := false
	var rings0 := w.fx.rings_shown
	t = 0.0
	var bolts := 0
	while t < 40.0 and not (seen.has(&"dive") and seen.has(&"grounded")):
		w.step(DT)
		t += DT
		seen[b.state] = true
		strikes_seen = strikes_seen or not b.strikes.is_empty()
	TestLib.check(strikes_seen and w.fx.rings_shown > rings0, "the drake marks lightning rings")
	TestLib.check(seen.has(&"mark") and seen.has(&"dive") and seen.has(&"grounded"), "it marks a dive line, dives and lands (saw %s)" % str(seen.keys()))
	TestLib.check(b.open_t > 0.0 and b.open_k > 1.0 and b.hint() != "", "grounded, it is open to double damage")
	b.damage(b.max_hp)
	TestLib.check(b.dead, "the drake can be killed")
	# SAND LEVIATHAN
	b = _boss_at(&"lair_dunes", Vector3(0.0, 0.0, 40.0))
	seen = {}
	var spit0 := int(w.stats_data["shots"])
	t = 0.0
	while t < 40.0 and not (seen.has(&"telegraph") and seen.has(&"exposed") and int(w.stats_data["shots"]) > spit0):
		w.step(DT)
		t += DT
		seen[b.state] = true
	TestLib.check(seen.has(&"travel") and seen.has(&"telegraph") and seen.has(&"erupt") and seen.has(&"exposed"), "the leviathan tunnels, marks the ring and erupts (saw %s)" % str(seen.keys()))
	TestLib.check(int(w.stats_data["shots"]) > spit0, "risen, it spits a fan of sand globs")
	b.phase_i = 1
	b._enter_phase(3)
	TestLib.check(b._chain == 2, "late phases erupt again at once")
	b.inv_t = 0.0
	b.damage(b.max_hp)
	TestLib.check(b.dead, "the leviathan can be killed")
	# DEEP KRAKEN
	b = _boss_at(&"lair_deep", Vector3(0.0, 0.0, 30.0))
	hero.global_position.y = TerrainHeight.SEA_LEVEL + 0.3
	t = 0.0
	while t < 10.0 and b.arms.size() < 4:
		w.step(DT)
		t += DT
		hero.global_position.y = TerrainHeight.SEA_LEVEL + 0.3
	TestLib.check(b != null and b.arms.size() == 4, "the kraken wakes with four arms")
	var h2 := b.hp
	b.damage(100.0)
	TestLib.check(h2 - b.hp < 20.0, "its mantle is shielded while the arms live")
	var hits_before := hero.hits
	t = 0.0
	while t < 30.0 and hero.hits == hits_before:
		w.step(DT)
		t += DT
		hero.global_position.y = TerrainHeight.SEA_LEVEL + 0.3
		for a in b.arms:
			if is_instance_valid(a) and a.exposed and a.state == &"up":
				hero.global_position = Vector3(a.position.x, TerrainHeight.SEA_LEVEL + 0.3, a.position.z + 7.0)
	TestLib.check(hero.hits > hits_before, "the arms slam rings on the water and hurt (and the ink flies)")
	for a in b.arms:
		if is_instance_valid(a):
			a.set_exposed(true)
			a.damage(a.max_hp * 2.0)
	_sim(0.3)
	TestLib.check(b._alive_arms() == 0, "the arms can be cut down")
	b.state = &"guard"
	_sim(0.3)
	h2 = b.hp
	b.damage(100.0)
	TestLib.check(b.state == &"surfaced" and h2 - b.hp >= 100.0, "with the arms down the body surfaces, open")
	b.inv_t = 0.0
	b.damage(b.max_hp)
	TestLib.check(b.dead, "the kraken can be killed")
	# HIVE WARDEN
	b = _boss_at(&"crash", Vector3(0.0, 0.0, 32.0))
	TestLib.check(b != null and b.relays.size() == 3 and b.shield_on, "the warden hovers inside a shield held by three relays")
	var hw := b.hp
	b.damage(100.0)
	TestLib.check(hw - b.hp < 20.0, "the shield eats the shots")
	var lines0 := w.fx.lines_shown
	t = 0.0
	while t < 20.0 and w.fx.lines_shown == lines0:
		w.step(DT)
		t += DT
	TestLib.check(w.fx.lines_shown > lines0, "it marks a lance line")
	for r in b.relays:
		r.damage(r.max_hp * 2.0)
	_sim(0.2)
	TestLib.check(not b.shield_on and b.open_t > 0.0 and b.state == &"stunned", "with the relays gone the shield falls and the warden is stunned and open")
	hw = b.hp
	b.damage(100.0)
	TestLib.check(hw - b.hp >= 100.0, "open, it takes full damage")
	b.inv_t = 0.0
	b.damage(b.max_hp)
	TestLib.check(b.dead and AlienSites.boss_down(&"hive_warden") and AlienSites.is_cleared(&"crash"), "the warden falls and the crash site is cleared")
	# a boss that loses the hero resets
	b = _boss_at(&"lair_forest", Vector3(0.0, 0.0, 30.0))
	_sim(2.0)
	b.hp = b.max_hp * 0.5
	var lair_pos: Vector3 = AlienSites.by_id(&"lair_forest")["pos"]
	_put_hero(lair_pos + Vector3(0.0, 0.0, 300.0))                 # far enough to lose the fight, near enough that the site does not stand down
	w._site_t = 99.0
	_sim(1.0)
	TestLib.check(b.hp >= b.max_hp - 1.0 and not Sfx.boss_active, "a boss the hero walks away from heals and lets go of the boss music")
	_clear()


# --- sites ----------------------------------------------------------------------------------------------------------------------------------------------

func _site_clear() -> void:
	AlienSites.reset_all()
	w.sites.clear()
	# a camp: populate, kill every guard, reward + clear + saved
	var s := AlienSites.by_id(&"ridge_camp")
	_put_hero(s["pos"] + Vector3(0.0, 0.0, 60.0))
	var made := w.populate(&"ridge_camp")
	var want := 0
	for g in s["guards"]:
		want += int(g[1])
	want += int(s["sentries"])
	TestLib.check(made.size() == want, "the camp's garrison comes to life (%d of %d)" % [made.size(), want])
	TestLib.check(w.populate(&"ridge_camp").is_empty(), "populating twice adds nothing")
	var near := true
	for c in made:
		near = near and Vector2(c.position.x - (s["pos"] as Vector3).x, c.position.z - (s["pos"] as Vector3).z).length() < float(s["r"]) + 2.0
	TestLib.check(near, "the guards stand inside the camp")
	var cleared_sig := [0]
	w.site_cleared.connect(func(_id): cleared_sig[0] += 1)
	var cr0 := (Game.progress as Progress).credits if Game.progress != null else 0
	for c in made:
		c.damage(1.0e6)
	TestLib.check(AlienSites.is_cleared(&"ridge_camp") and cleared_sig[0] == 1, "killing every guard clears the camp once")
	if Game.progress != null:
		TestLib.check((Game.progress as Progress).credits >= cr0 + int(s["reward"]), "the camp reward is paid")
	TestLib.check(w.loot_count() > 0, "loot lies about")
	TestLib.check(w.populate(&"ridge_camp").size() > 0 == false or AlienSites.is_cleared(&"ridge_camp"), "a cleared camp stays cleared")
	# a nest: destroy the heart
	var n := AlienSites.by_id(&"dune_nest")
	_put_hero(n["pos"] + Vector3(0.0, 0.0, 50.0))
	var nm := w.populate(&"dune_nest")
	var heart: AlienCreature = (w.sites[&"dune_nest"] as Dictionary).get("heart")
	TestLib.check(heart != null and heart.id == &"hive_heart" and nm.has(heart), "a nest has its heart")
	heart.damage(1.0e6)
	TestLib.check(AlienSites.is_cleared(&"dune_nest"), "destroying the heart clears the nest")
	# depopulate when the hero leaves; a never-cleared site comes back
	AlienSites.reset_all()
	w.sites.clear()
	_put_hero(s["pos"] + Vector3(0.0, 0.0, 60.0))
	w.populate(&"ridge_camp")
	_put_hero(Vector3(0.0, 0.0, -300.0))
	w._site_t = 0.0
	w.step(DT)
	TestLib.check(w.site_creatures(&"ridge_camp").is_empty(), "a camp stands down when the hero is far away (nothing runs for it)")
	_put_hero(s["pos"] + Vector3(0.0, 0.0, 120.0))
	w._site_t = 0.0
	w.step(DT)
	TestLib.check(w.site_creatures(&"ridge_camp").size() > 0, "and fills again when he comes back")
	TestLib.check(w.sites[&"ridge_camp"]["node"] != null, "the camp mesh is built when the hero is within a kilometre")
	_clear()


func _loot() -> void:
	AlienLoot.reset()
	var cr0 := (Game.progress as Progress).credits if Game.progress != null else 0
	var scrap0 := Crafting.part_count(&"scrap")
	var pay := AlienLoot.collect(&"chitin", 2)
	TestLib.check(pay == 24 and AlienLoot.count(&"chitin") == 2 and AlienLoot.all_parts() == 2, "banking parts: credits and the inventory")
	TestLib.check(Crafting.part_count(&"scrap") >= scrap0 + 2, "chitin plates feed the crafting scrap")
	if Game.progress != null:
		TestLib.check((Game.progress as Progress).credits >= cr0 + 24, "the credits arrive")
	TestLib.check(AlienLoot.collect(&"nonsense", 1) == 0 and AlienLoot.collect(&"core", 0) == 0, "unknown parts and zero counts are ignored")
	AlienLoot.collect(&"crystal", 8)
	TestLib.check(AlienLoot.milestones >= 1, "every ten parts a milestone fires")
	# a shard on the ground magnetises to the hero and banks
	_clear()
	_put_hero(ARENA)
	w.drop_part(&"gland", 1, hero.global_position + Vector3(3.0, 0.0, 0.0))
	TestLib.check(w.loot_count() == 1, "a shard drops")
	var g0 := AlienLoot.count(&"gland")
	_sim(3.0, func(): return AlienLoot.count(&"gland") > g0)
	TestLib.check(AlienLoot.count(&"gland") == g0 + 1 and w.loot_count() == 0, "the hero walks into it and banks it")
	for i in 30:
		w.drop_part(&"chitin", 1, hero.global_position + Vector3(40.0, 0.0, 0.0))
	TestLib.check(w.loot_count() <= AlienWorld.LOOT_POOL, "the shard pool is capped (%d)" % w.loot_count())
	_clear()


# --- ambient director ---------------------------------------------------------------------------------------------------------------------------

func _ambient() -> void:
	w.ambient_enabled = true
	w.roster.enabled = false                                      # the roster-2 director (test_enemy_roster2) has its own checks; this one counts alien fauna only
	# never in the city
	_clear()
	_put_hero(Vector3(100.0, 0.0, 100.0))
	for i in 30:
		w._spawn_t = 0.0
		w.step(DT)
	TestLib.check(w.ambient_count() == 0, "no alien fauna in the city")
	# a forest fills with ground fauna up to the cap, never beyond, and only the right species
	_clear()
	var f := AlienSites.by_id(&"lair_forest")
	_put_hero(f["pos"])
	var seen := {}
	for q in [0, 1, 2]:
		_clear()
		w.set_quality(q)
		for i in 60:
			w._spawn_t = 0.0
			w.step(DT)
		for c in w.creatures:
			if c.site == &"":
				seen[c.id] = true
		TestLib.check(w.count_of(AlienSpecies.GROUND) <= w.cap_of(AlienSpecies.GROUND) and w.ambient_count() > 0, "tier %d: forest fauna spawn and respect the cap (%d of %d)" % [q, w.count_of(AlienSpecies.GROUND), w.cap_of(AlienSpecies.GROUND)])
	var allowed := [&"skitter", &"popper", &"shade_stalker", &"swarmer"]
	var ok := true
	for id in seen:
		ok = ok and allowed.has(id)
	TestLib.check(ok and seen.size() >= 1, "only forest species appear in a forest (%s)" % str(seen.keys()))
	w.set_quality(1)
	# the desert has burrowers, the mountains swarmers, the sea lurkers and rays
	var dunes := AlienSites.by_id(&"lair_dunes")
	_clear()
	_put_hero(dunes["pos"])
	var dseen := {}
	for i in 400:
		w._spawn_t = 0.0
		w.step(DT)
		for c in w.creatures:
			dseen[c.id] = true
		if i % 40 == 0:
			_clear()
	TestLib.check(dseen.has(&"dune_maw") or dseen.has(&"skitter"), "the desert spawns maws and packs (%s)" % str(dseen.keys()))
	var mt := AlienSites.by_id(&"lair_peak")
	_clear()
	_put_hero(mt["pos"])
	var mseen := {}
	for i in 400:
		w._spawn_t = 0.0
		w.step(DT)
		for c in w.creatures:
			mseen[c.id] = true
		if i % 40 == 0:
			_clear()
	TestLib.check(mseen.has(&"swarmer"), "the mountains spawn swarmers (%s)" % str(mseen.keys()))
	var sea := AlienSites.by_id(&"lair_deep")
	_clear()
	_put_hero(sea["pos"])
	hero.global_position.y = TerrainHeight.SEA_LEVEL + 0.3
	var sseen := {}
	for i in 400:
		w._spawn_t = 0.0
		w.step(DT)
		for c in w.creatures:
			sseen[c.id] = true
		hero.global_position.y = TerrainHeight.SEA_LEVEL + 0.3
		if i % 40 == 0:
			_clear()
	TestLib.check(sseen.has(&"reef_lurker") or sseen.has(&"drift_ray"), "the sea spawns lurkers and rays (%s)" % str(sseen.keys()))
	# nothing spawns while the hero rushes by at speed or stands in an interior
	_clear()
	_put_hero(f["pos"])
	w.hero_vel2 = Vector2(40.0, 0.0)
	w._hero_prev = hero.global_position
	for i in 5:
		w._spawn_t = 0.0
		w._try_spawn_ambient()
	TestLib.check(w.ambient_count() == 0, "a hero at 40 m/s is left alone")
	w.ambient_enabled = false
	_clear()


func _persistence() -> void:
	AlienSites.reset_all()
	AlienSites.mark_cleared(&"gorge_camp")
	AlienSites.mark_boss(&"broodmother")
	AlienLoot.reset()
	AlienLoot.collect(&"core", 3)
	AlienSites.cleared.clear()
	AlienSites.bosses_down.clear()
	AlienSites._loaded = false
	TestLib.check(AlienSites.is_cleared(&"gorge_camp") and AlienSites.boss_down(&"broodmother") and not AlienSites.is_cleared(&"ridge_camp"), "cleared sites and defeated bosses are saved")
	AlienLoot.counts.clear()
	AlienLoot.total = 0
	AlienLoot._loaded = false
	TestLib.check(AlienLoot.count(&"core") == 3, "banked parts are saved")
	AlienSites.reset_all()
	TestLib.check(AlienSites.cleared_count() == 0 and not AlienSites.boss_down(&"broodmother"), "reset_state forgets")


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
	TestLib.check(city != null and p != null and aw != null and aw.enabled, "the real scene has a city with an alien world")
	if aw == null or p == null:
		main.queue_free()
		return
	TestLib.check(AlienWorld.instance == aw, "AlienWorld.instance is the city's")
	var prog := Game.progress as Progress
	if prog != null:
		prog.path = "user://test_alien_world_prog.cfg"
	if Encounters.current != null:
		Encounters.current.enabled = false
	(Game.enemies as EnemyManager).clear()
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	aw.ambient_enabled = false
	# a camp populates when the hero walks up, by the game's own clock
	var s := AlienSites.by_id(&"east_camp")
	var sp: Vector3 = s["pos"]
	p.global_position = Vector3(sp.x, TerrainHeight.height_at(sp.x, sp.z) + 1.0, sp.z + 90.0)
	p.velocity = Vector3.ZERO
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000 and aw.site_creatures(&"east_camp").is_empty():
		await TestLib.frames(host, 4)
		p.global_position = Vector3(sp.x, TerrainHeight.height_at(sp.x, sp.z) + 1.0, sp.z + 90.0)
	TestLib.check(not aw.site_creatures(&"east_camp").is_empty(), "walking up to the camp brings its garrison to life in the real game")
	TestLib.check(get_tree_group_count(&"enemy") >= 3, "the guards are in the game's enemy group")
	# the real player can hurt a guard with the real weapon call path and is hurt by a real attack
	var g := aw.site_creatures(&"east_camp")[0]
	var hp0 := g.hp
	g.damage(5.0)
	TestLib.check(g.hp < hp0, "a hit lands")
	var php := p.hp
	p.invuln = 0.0
	var ok_hurt := aw.hurt_hero(10.0, g.global_position)
	TestLib.check(ok_hurt and p.hp < php, "a creature's attack reaches the real player (difficulty and cover applied)")
	# the map shows the pins
	var pins := AlienSites.map_markers()
	TestLib.check(pins.size() == 15, "the big map lists the alien sites")
	var ms := load("res://scripts/ui/map_screen.gd") as GDScript
	TestLib.check(ms != null and ms.source_code.contains("AlienSites.map_markers()"), "the map screen draws them")
	# the boss bar feed reaches the HUD code
	var hud_src := (load("res://scripts/ui/hud.gd") as GDScript).source_code
	TestLib.check(hud_src.contains("AlienWorld.boss_bar()"), "the HUD draws the alien boss bar")
	# pause: nothing moves while the game is paused
	aw.force_active = false
	Game.state = &"paused"
	var before := g.position
	await TestLib.frames(host, 10)
	TestLib.check(g.position.is_equal_approx(before) or not is_instance_valid(g), "paused: the aliens stand still")
	Game.state = &"menu"
	aw.clear_all()
	main.queue_free()
	await TestLib.frames(host, 2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_alien_world_prog.cfg"))


func get_tree_group_count(g: StringName) -> int:
	return (Engine.get_main_loop() as SceneTree).get_nodes_in_group(g).size()
