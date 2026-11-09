extends RefCounted
## The wildlife of the outskirts, the coast and the sea (wave 107) in the REAL game scene: the species table (every model file, size, clips, voices), the rules of where each one lives
## (biome, height, farm, time of day), the spawn director around the hero (nothing inside the city, caps per tier, only near the hero), herds that run from gunfire and from the hero,
## wolves that hunt prey, sleeping at night, flocks that scatter, dolphins that porpoise, fish that stay in the water, the real carbine killing a deer (quantum dust, the bounty, the pool),
## cars that run animals over, a blast, pause.
## Run: tools/test.sh tests/test_animals_biomes.gd   (about 70 s; waits on counters and game time, never on frame counts)

const K := 4
const TIMEOUT_SECONDS := 140.0
const TMP := "user://test_animals_biomes.cfg"
const FOREST := Vector3(-1600.0, 0.0, -1400.0)
const MOUNTAIN := Vector3(-600.0, 0.0, -2400.0)
const DESERT := Vector3(0.0, 0.0, 1300.0)
const PLAINS := Vector3(1400.0, 0.0, -1000.0)
const BEACH := Vector3(-1590.0, 0.0, -200.0)

var city: City
var p: Player
var w: WildlifeWorld


func run(host: Node) -> void:
	for f in [TMP, TMP + ".bak", TMP + ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_species_table()
	_rules()
	_sounds()
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	city = Game.world as City
	p = Game.player as Player
	w = city.wildlife as WildlifeWorld if city != null else null
	TestLib.check(city != null and p != null and w != null and w.enabled, "the real scene has a city with a wildlife world")
	if city == null or p == null or w == null or not w.enabled:
		_restore()
		return
	var prog := Game.progress as Progress
	if prog != null:
		prog.path = TMP                                           # never touch the real save
	if Encounters.current != null:
		Encounters.current.enabled = false
	(Game.enemies as EnemyManager).clear()
	p.set_physics_process(true)
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	if city.day_night != null:
		city.day_night.frozen = true
		city.day_night.set_hour(12.0)
	await _city_has_none(host)
	await _biomes(host)
	await _tiers(host)
	await _flee_and_hunt(host)
	await _flocks_and_water(host)
	await _night(host)
	await _hunting(host, prog)
	await _hazards(host)
	await _pause(host)
	w.clear()
	w.director = true
	w.force_active = false
	_restore()
	Game.state = &"menu"
	main.queue_free()
	for f in [TMP, TMP + ".bak", TMP + ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	await TestLib.frames(host, 2)


func _restore() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60


## Waits `secs` SECONDS OF THE WILDLIFE'S OWN CLOCK (the sum of the steps it simulated), so the waits follow the simulation, never the machine; an idle world (paused) needs `_wait_real`.
func _wait(host: Node, what: Callable, secs: float) -> bool:
	var t0 := w._t
	var guard := Engine.get_physics_frames()
	while w._t - t0 < secs and Engine.get_physics_frames() - guard < int(60.0 * secs * 6.0):
		if what.call():
			return true
		await host.get_tree().process_frame
	return what.call()


## Game seconds by the physics clock (60 per game second at the K-fold tick rate).
func _wait_real(host: Node, what: Callable, secs: float) -> bool:
	var t0 := Engine.get_physics_frames()
	while float(Engine.get_physics_frames() - t0) / 60.0 < secs:
		if what.call():
			return true
		await host.get_tree().process_frame
	return what.call()


func _teleport(pos: Vector3, yaw := 0.0) -> Vector3:
	var at := Vector3(pos.x, TerrainHeight.height_at(pos.x, pos.z) + 0.9, pos.z)
	if city.terrain != null:
		city.terrain.settle(at)
	if city.vegetation != null:
		city.vegetation.settle(at)
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.teleport_to(at)
	p.camera_rig.reset_view(yaw, 0.0)
	return at


# --- data -------------------------------------------------------------------------------------------------------------------------------------

func _species_table() -> void:
	var ids := AnimalSpecies.ids()
	TestLib.check(ids.size() >= 17, "at least 17 species (%d)" % ids.size())
	var classes := {}
	var missing := ""
	var heavy := ""
	var no_clip := ""
	for id: StringName in ids:
		var s := AnimalSpecies.data(id)
		classes[s["cls"]] = true
		for key in ["name", "cls", "role", "hp", "bounty", "flee", "group", "hit_r", "mid", "mul"]:
			if not s.has(key):
				missing += "%s.%s " % [id, key]
		if id == &"lizard":
			continue
		var path := AnimalSpecies.model_path(id)
		if path == "" or not ResourceLoader.exists(path):
			missing += "%s(file) " % id
			continue
		var ps := load(path) as PackedScene
		var inst := ps.instantiate()
		var tris := 0
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			for si in m.get_surface_count():
				var arr := m.surface_get_arrays(si)
				tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			if m.get_surface_count() != 1:
				heavy += "%s(%d surfaces) " % [id, m.get_surface_count()]
		if tris > 1500:
			heavy += "%s(%d tris) " % [id, tris]
		var ap := inst.find_children("*", "AnimationPlayer", true, false)
		if ap.is_empty():
			no_clip += "%s " % id
		else:
			var player := ap[0] as AnimationPlayer
			var want: Array = ["swim"] if s["cls"] == AnimalSpecies.WATER else (["fly"] if s["cls"] == AnimalSpecies.AIR else ["walk"])
			for clip in want:
				if not player.has_animation(clip):
					no_clip += "%s.%s " % [id, clip]
			if s["cls"] == AnimalSpecies.LAND and s["role"] == AnimalSpecies.PREY:
				for clip in ["idle", "run"]:
					if not player.has_animation(clip):
						no_clip += "%s.%s " % [id, clip]
		inst.free()
	TestLib.check(missing == "", "every species has its data and its model file (%s)" % missing)
	TestLib.check(heavy == "", "every model is ONE surface under 1500 triangles (%s)" % heavy)
	TestLib.check(no_clip == "", "every model has the clips its behaviour plays (%s)" % no_clip)
	for c in [AnimalSpecies.LAND, AnimalSpecies.AIR, AnimalSpecies.WATER, AnimalSpecies.SMALL]:
		TestLib.check(classes.has(c), "a species of class %s" % c)
	for id in [&"deer", &"wolf", &"goat", &"eagle", &"seagull", &"fish", &"dolphin", &"shark", &"coyote", &"zebra", &"cow", &"sheep", &"horse", &"boar", &"fox", &"songbird", &"lizard", &"whale"]:
		TestLib.check(AnimalSpecies.TABLE.has(id), "species %s exists" % id)
	TestLib.check(int(AnimalSpecies.data(&"wolf")["bounty"]) > int(AnimalSpecies.data(&"deer")["bounty"]) and int(AnimalSpecies.data(&"fish")["bounty"]) == 0, "predators pay more than grazers, fish pay nothing")
	TestLib.check(WildlifeKit.lizard_mesh().get_surface_count() == 1, "the lizard is one surface built in code")


func _ids_of(list: Array) -> Array:
	var out: Array = []
	for e in list:
		if float(e[1]) > 0.0:
			out.append(e[0])
	return out


func _rules() -> void:
	var L := AnimalSpecies.LAND
	var A := AnimalSpecies.AIR
	var W := AnimalSpecies.WATER
	var forest := _ids_of(AnimalSpecies.weights(L, TerrainBase.FOREST, 30.0, 0.1, 0.0, 0.0, false))
	TestLib.check(forest.has(&"deer") and forest.has(&"wolf") and forest.has(&"boar") and forest.has(&"fox") and not forest.has(&"zebra"), "the forest has deer, wolves, boars and foxes (%s)" % str(forest))
	var cliffs := _ids_of(AnimalSpecies.weights(L, TerrainBase.MOUNTAIN, 160.0, 0.5, 0.0, 0.0, false))
	TestLib.check(cliffs.has(&"goat") and cliffs.has(&"wolf"), "the mountains have goats and wolves (%s)" % str(cliffs))
	var desert := _ids_of(AnimalSpecies.weights(L, TerrainBase.DESERT, 4.0, 0.05, 0.0, 0.0, false))
	TestLib.check(desert.has(&"coyote") and desert.has(&"zebra") and not desert.has(&"deer"), "the desert has coyotes and zebras (%s)" % str(desert))
	var lizards := _ids_of(AnimalSpecies.weights(AnimalSpecies.SMALL, TerrainBase.DESERT, 4.0, 0.05, 0.0, 0.0, false))
	TestLib.check(lizards == [&"lizard"], "lizards live in the desert")
	var farm_w := {}
	for e in AnimalSpecies.weights(L, TerrainBase.PLAINS, 6.0, 0.05, 0.0, 1.0, false):
		farm_w[e[0]] = float(e[1])
	var far_w := {}
	for e in AnimalSpecies.weights(L, TerrainBase.PLAINS, 6.0, 0.05, 0.0, 0.0, false):
		far_w[e[0]] = float(e[1])
	TestLib.check(float(farm_w.get(&"sheep", 0.0)) > 4.0 * float(far_w.get(&"sheep", 1.0)) and float(farm_w.get(&"cow", 0.0)) > 4.0 * float(far_w.get(&"cow", 1.0)) and far_w.has(&"deer"), "sheep and cows gather round a farm")
	var coast := _ids_of(AnimalSpecies.weights(A, TerrainBase.BEACH, 0.5, 0.0, 0.0, 0.0, true))
	TestLib.check(coast == [&"seagull"], "gulls work the beach")
	var peaks := _ids_of(AnimalSpecies.weights(A, TerrainBase.MOUNTAIN, 200.0, 0.3, 0.0, 0.0, false))
	TestLib.check(peaks.has(&"eagle"), "eagles circle the mountains")
	var sea := _ids_of(AnimalSpecies.weights(W, TerrainBase.OCEAN, -20.0, 0.0, 0.0, 0.0, false))
	TestLib.check(sea.has(&"dolphin") and sea.has(&"shark") and sea.has(&"whale"), "the sea has dolphins, sharks and whales")
	var river := _ids_of(AnimalSpecies.weights(W, TerrainBase.FOREST, 3.0, 0.0, 0.0, 0.0, false))
	TestLib.check(river == [&"fish"], "the rivers have fish")
	# time of day: songbirds and eagles are gone at night, wolves are more than twice as likely
	var night_birds := _ids_of(AnimalSpecies.weights(A, TerrainBase.FOREST, 30.0, 0.1, 1.0, 0.0, false))
	TestLib.check(not night_birds.has(&"songbird") and not night_birds.has(&"eagle"), "songbirds and eagles are gone at night")
	var wd := 0.0
	var wn := 0.0
	var dd := 0.0
	var dn := 0.0
	for e in AnimalSpecies.weights(L, TerrainBase.FOREST, 30.0, 0.1, 0.0, 0.0, false):
		if e[0] == &"wolf":
			wd = float(e[1])
		if e[0] == &"deer":
			dd = float(e[1])
	for e in AnimalSpecies.weights(L, TerrainBase.FOREST, 30.0, 0.1, 1.0, 0.0, false):
		if e[0] == &"wolf":
			wn = float(e[1])
		if e[0] == &"deer":
			dn = float(e[1])
	TestLib.check(wn > 1.9 * wd and absf(dn - dd) < 0.01, "wolves are about twice as likely at night, deer are not (%.1f -> %.1f)" % [wd, wn])
	TestLib.check(AnimalSpecies.pick([], 0.3) == &"" and AnimalSpecies.pick([[&"deer", 1.0], [&"wolf", 3.0]], 0.1) == &"deer" and AnimalSpecies.pick([[&"deer", 1.0], [&"wolf", 3.0]], 0.9) == &"wolf", "the weighted pick follows the weights")


func _sounds() -> void:
	var missing := ""
	for id: StringName in AnimalSpecies.ids():
		var snd: StringName = AnimalSpecies.data(id).get("sound", &"")
		if snd != &"" and Sfx.variants_of(snd).is_empty():
			missing += "%s " % snd
	TestLib.check(missing == "", "every animal voice has a sound file (%s)" % missing)
	TestLib.check(Sfx.variants_of(&"animal_wolf").size() >= 2 and Sfx.variants_of(&"animal_gull").size() >= 3 and Sfx.variants_of(&"animal_bird").size() >= 3, "wolves, gulls and birds have several calls")


# --- the real scene --------------------------------------------------------------------------------------------------------------------------

func _city_has_none(host: Node) -> void:
	w.clear()
	var at := Vector3(0.0, 1.0, 0.0)
	p.global_position = at
	p.teleport_to(at)
	await _wait(host, func(): return false, 3.0)
	var near := w.census(at, 500.0)
	TestLib.check(near.is_empty(), "no animals in the streets of the city (%d within 500 m)" % near.size())


func _biomes(_host: Node) -> void:
	var spots := {
		"forest": [FOREST, [&"deer", &"boar", &"fox", &"wolf", &"goat", &"songbird", &"eagle"]],
		"mountain": [MOUNTAIN, [&"goat", &"wolf", &"fox", &"deer", &"eagle", &"songbird"]],
		"desert": [DESERT, [&"coyote", &"zebra", &"fox", &"lizard", &"eagle", &"songbird", &"dolphin", &"shark", &"whale", &"seagull"]],
		"plains": [PLAINS, [&"deer", &"fox", &"coyote", &"sheep", &"cow", &"horse", &"songbird", &"eagle", &"lizard", &"fish"]],
		"beach": [BEACH, [&"seagull", &"fox", &"dolphin", &"shark", &"whale", &"deer", &"boar", &"wolf", &"songbird", &"eagle", &"goat"]],
	}
	for k in spots:
		w.clear()
		var at := _teleport(spots[k][0])
		w.settle(at, 60)
		var s := w.stats()
		var allowed: Array = spots[k][1]
		var odd := ""
		for id in s["by_species"]:
			if not allowed.has(id):
				odd += "%s " % id
		TestLib.check(int(s["active"]) >= 4, "the %s fills with animals (%d)" % [k, s["active"]])
		TestLib.check(odd == "", "only species of the %s live there (strangers: %s)" % [k, odd])
		var far := 0
		for c in w.critters:
			if Vector2(c.position.x - at.x, c.position.z - at.z).length() > float(WildlifeWorld.RING[1][1]) * 1.2:
				far += 1
		TestLib.check(far == 0, "everything of the %s stays within the ring around the hero (%d outside)" % [k, far])
	w.clear()


func _tiers(host: Node) -> void:
	var at := _teleport(FOREST)
	for q in [0, 1, 2]:
		city.set_quality(q)
		w.clear()
		w.settle(at, 120)
		var bad := ""
		for cls in [AnimalSpecies.LAND, AnimalSpecies.AIR, AnimalSpecies.WATER, AnimalSpecies.SMALL]:
			if w.count_of(cls) > w.cap_of(cls):
				bad += "%s=%d>%d " % [cls, w.count_of(cls), w.cap_of(cls)]
		TestLib.check(bad == "", "tier %d keeps every class within its cap (%s)" % [q, bad])
		var s := w.stats()
		var meshes := 0
		for c in w.critters:
			meshes += 1 if c.mesh != null else 0
		TestLib.check(meshes == int(s["active"]), "one mesh (one draw) per animal at tier %d (%d)" % [q, meshes])
		if q == 0:
			TestLib.check(int(s["active"]) <= 8 + 5 + 4 + 3, "LOW keeps at most %d bodies (%d)" % [8 + 5 + 4 + 3, s["active"]])
	var caps: Array = WildlifeWorld.CAPS[AnimalSpecies.LAND]
	TestLib.check(caps[0] < caps[1] and caps[1] < caps[2], "caps grow with the tier")
	city.set_quality(1)
	# the director fills the world around a hero who stands still (no settle): animals appear out of the view within seconds and the cap holds
	w.clear()
	w.director = true
	at = _teleport(PLAINS)
	var ok := await _wait(host, func(): return w.count_of(AnimalSpecies.LAND) >= 3, 14.0)
	TestLib.check(ok, "the spawn director brings animals to a hero standing in the open (%d land)" % w.count_of(AnimalSpecies.LAND))
	TestLib.check(w.count_of(AnimalSpecies.LAND) <= w.cap_of(AnimalSpecies.LAND), "the director never passes the cap")
	w.director = false
	w.clear()


func _spawn_herd(id: StringName, at: Vector3, n: int) -> Array[Critter]:
	var before := w.critters.size()
	w.spawn_group(id, at, n)
	var out: Array[Critter] = []
	for i in range(before, w.critters.size()):
		out.append(w.critters[i])
	return out


func _ahead(from: Vector3, yaw: float, dist: float) -> Vector3:
	var f := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var q := from + f * dist
	q.y = TerrainHeight.height_at(q.x, q.z)
	return q


func _flee_and_hunt(host: Node) -> void:
	w.clear()
	w.director = false
	var at := _teleport(PLAINS, 0.0)
	await TestLib.frames(host, 4)
	# --- a herd of deer 30 m ahead runs from a shot, the whole herd together
	var herd := _spawn_herd(&"deer", _ahead(at, 0.0, 30.0), 5)
	TestLib.check(herd.size() == 5, "a herd of five deer is placed")
	for c in herd:
		c.think_t = 99.0                                                 # nobody reacts to the hero before the shot
		c.state = &"idle"
		c.timer = 99.0
	var d0 := 0.0
	for c in herd:
		d0 += Vector2(c.position.x - at.x, c.position.z - at.z).length()
	d0 /= herd.size()
	p.fired.emit()
	var all_flee := await _wait(host, func():
		for c in herd:
			if c.state != &"flee":
				return false
		return true, 2.0)
	TestLib.check(all_flee, "a shot sends the whole herd running")
	await _wait(host, func(): return false, 4.0)
	var d1 := 0.0
	var fast := 0
	for c in herd:
		d1 += Vector2(c.position.x - at.x, c.position.z - at.z).length()
		if c.ap != null and c.clip == &"run":
			fast += 1
	d1 /= herd.size()
	TestLib.check(d1 > d0 + 12.0, "the herd ran away from the hero (%.0f m -> %.0f m)" % [d0, d1])
	TestLib.check(fast >= 3, "they play the run clip while fleeing (%d)" % fast)
	var ground_ok := true
	for c in herd:
		if absf(c.position.y - TerrainHeight.height_at(c.position.x, c.position.z)) > 1.2:
			ground_ok = false
	TestLib.check(ground_ok, "the herd keeps its feet on the ground")
	# --- the hero standing close to grazers makes them leave (nobody shoots)
	w.clear()
	var herd2 := _spawn_herd(&"deer", _ahead(at, 0.0, 22.0), 3)
	for c in herd2:
		c.timer = 99.0
		c.state = &"graze"
	var left := await _wait(host, func():
		for c in herd2:
			if c.state == &"flee":
				return true
		return false, 4.0)
	TestLib.check(left, "grazing deer notice a hero closer than their nerve (34 m)")
	# --- a wolf hunts a deer
	w.clear()
	var far_at := _ahead(at, 0.0, 55.0)
	var prey := _spawn_herd(&"deer", far_at, 1)[0]
	var wolf := _spawn_herd(&"wolf", far_at + Vector3(14.0, 0.0, 0.0), 1)[0]
	prey.think_t = 99.0
	prey.timer = 99.0
	wolf.think_t = 99.0
	wolf.cool = 0.0
	wolf.prey = prey
	wolf.state = &"hunt"
	wolf.timer = 20.0
	var killed := [0]
	var by_hero := [false]
	var cb := func(sp: StringName, _pos: Vector3, hero: bool):
		if sp == &"deer":
			killed[0] += 1
			by_hero[0] = hero
	w.killed.connect(cb)
	var kills0 := WildlifeWorld.total_kills
	var caught := await _wait(host, func(): return killed[0] > 0, 16.0)
	w.killed.disconnect(cb)
	TestLib.check(caught, "a wolf runs a deer down")
	TestLib.check(not by_hero[0] and WildlifeWorld.total_kills == kills0, "a predator's kill is not the hero's (no bounty)")
	TestLib.check(wolf.state == &"eat" or wolf.state == &"idle", "the wolf feeds afterwards (%s)" % wolf.state)
	var gone := await _wait(host, func(): return not w.critters.has(prey), 4.0)
	TestLib.check(gone, "the dissolved deer returns to the pool")
	# --- prey nearby run from a hunting predator
	w.clear()
	var others := _spawn_herd(&"deer", far_at, 3)
	var hunter := _spawn_herd(&"wolf", far_at + Vector3(10.0, 0.0, 0.0), 1)[0]
	for c in others:
		c.timer = 99.0
		c.state = &"graze"
	hunter.state = &"hunt"
	hunter.prey = others[0]
	hunter.timer = 20.0
	var fled := await _wait(host, func():
		for c in others:
			if c.state == &"flee" or c.dying:
				return true
		return false, 3.0)
	TestLib.check(fled, "deer run from a hunting wolf")
	w.clear()


func _flocks_and_water(host: Node) -> void:
	w.clear()
	var at := _teleport(FOREST, 0.0)
	await TestLib.frames(host, 4)
	# --- songbirds circle, then scatter from a shot and climb away
	var birds := _spawn_herd(&"songbird", _ahead(at, 0.0, 40.0), 6)
	await _wait(host, func(): return false, 1.0)
	var circling := 0
	var airborne := true
	for c in birds:
		if c.state == &"orbit":
			circling += 1
		if c.position.y < TerrainHeight.height_at(c.position.x, c.position.z) + 2.0:
			airborne = false
	TestLib.check(circling == 6 and airborne, "a flock circles above the trees (%d circling)" % circling)
	var y0 := birds[0].position.y
	w.scare_all(at, 80.0)
	var scattered := await _wait(host, func():
		for c in birds:
			if c.state != &"flee":
				return false
		return true, 1.0)
	TestLib.check(scattered, "a shot scatters the flock")
	await _wait(host, func(): return false, 3.0)
	TestLib.check(birds[0].position.y > y0 + 3.0, "the birds climb away (%.1f -> %.1f m)" % [y0, birds[0].position.y])
	var left := await _wait(host, func(): return not w.critters.has(birds[0]), 14.0)
	TestLib.check(left, "a scattered flock leaves the world")
	# --- eagles soar high
	w.clear()
	var eagle := _spawn_herd(&"eagle", _ahead(at, 0.0, 60.0), 1)[0]
	await _wait(host, func(): return false, 0.5)
	TestLib.check(eagle.position.y > TerrainHeight.height_at(eagle.position.x, eagle.position.z) + 40.0, "an eagle soars above 40 m")
	# --- gulls on the sand stand until the hero comes close
	w.clear()
	var shore := _teleport(BEACH, 1.57)
	var perched := 0
	var gulls: Array[Critter] = []
	for tries in 14:
		w.clear()
		var spot := _ahead(shore, 1.57, -6.0 + float(tries) * 3.0)
		if TerrainBase.biome_at(spot.x, spot.z, spot.y) != TerrainBase.BEACH:
			continue
		gulls = _spawn_herd(&"seagull", spot, 5)
		perched = 0
		for c in gulls:
			if c.state == &"perch":
				perched += 1
		if perched >= 3:
			break
	TestLib.check(perched >= 3, "gulls can stand on the beach (%d standing)" % perched)
	if perched >= 3:
		var near := _teleport(Vector3(gulls[0].position.x - 4.0, 0.0, gulls[0].position.z), 1.57)
		var flew := await _wait(host, func():
			for c in gulls:
				if c.state == &"flee":
					return true
			return false, 3.0)
		TestLib.check(flew, "they take off when the hero walks up")
		near = near
	# --- dolphins porpoise in the sea
	w.clear()
	var sea_pt := Vector3(-1700.0, 0.0, -200.0)
	var ground := TerrainHeight.height_at(sea_pt.x, sea_pt.z)
	TestLib.check(TerrainHeight.is_water(sea_pt.x, sea_pt.z) and TerrainHeight.depth_at(sea_pt.x, sea_pt.z) > 2.0, "the test sea point is deep water (%.1f m)" % TerrainHeight.depth_at(sea_pt.x, sea_pt.z))
	_teleport(BEACH, 1.57)
	var pod := _spawn_herd(&"dolphin", Vector3(sea_pt.x, ground, sea_pt.z), 3)
	var surf := TerrainHeight.SEA_LEVEL
	var ymin := 1.0e9
	var ymax := -1.0e9
	var t0 := w._t
	var wet := true
	while w._t - t0 < 7.0:
		await host.get_tree().process_frame
		for c in pod:
			ymin = minf(ymin, c.position.y)
			ymax = maxf(ymax, c.position.y)
			if TerrainHeight.depth_at(c.position.x, c.position.z) < 0.3:
				wet = false
	TestLib.check(ymax - ymin > 0.9 and ymax > surf + 0.25, "dolphins leap out of the water and dive again (%.2f .. %.2f, sea %.1f)" % [ymin, ymax, surf])
	TestLib.check(wet, "the pod stays over water")
	# --- a shark cruises just under the surface and stays in the sea
	w.clear()
	var shark := _spawn_herd(&"shark", Vector3(sea_pt.x, ground, sea_pt.z), 1)[0]
	await _wait(host, func(): return false, 5.0)
	TestLib.check(TerrainHeight.depth_at(shark.position.x, shark.position.z) > 0.5 and absf(shark.position.y - (surf - 0.75)) < 0.8, "the shark cruises just under the surface (y %.2f)" % shark.position.y)
	# --- fish: in a river, they stay in it
	w.clear()
	WaterLayout.ensure()
	var rp: PackedVector2Array = WaterLayout.paths[0]["pos"]
	var rpt := rp[rp.size() / 3]
	var river_ground := TerrainHeight.height_at(rpt.x, rpt.y)
	var rdepth := TerrainHeight.depth_at(rpt.x, rpt.y)
	TestLib.check(rdepth > 0.8, "the test river point is water (%.1f m)" % rdepth)
	_teleport(Vector3(rpt.x + 20.0, 0.0, rpt.y), 4.7)
	var fish := _spawn_herd(&"fish", Vector3(rpt.x, river_ground, rpt.y), 6)
	await _wait(host, func(): return false, 6.0)
	var in_water := 0
	for c in fish:
		if w.critters.has(c) and TerrainHeight.depth_at(c.position.x, c.position.z) > 0.3:
			in_water += 1
	TestLib.check(in_water >= 4, "the school stays in the river (%d of 6 over water)" % in_water)
	var surface_here := TerrainHeight.water_level_at(fish[0].position.x, fish[0].position.z)
	TestLib.check(surface_here != TerrainHeight.NO_WATER and fish[0].position.y < surface_here - 0.1 and fish[0].position.y > surface_here - 1.5, "fish swim just under the surface")
	w.clear()


func _night(host: Node) -> void:
	w.clear()
	var at := _teleport(PLAINS, 0.0)
	await TestLib.frames(host, 4)
	var herd := _spawn_herd(&"deer", _ahead(at, 0.0, 60.0), 4)
	var pack := _spawn_herd(&"wolf", _ahead(at, 0.0, 40.0) + Vector3(-90.0, 0.0, 0.0), 2)        # out of reach of the deer: wolves hunt at night
	city.day_night.set_hour(1.0)
	await TestLib.frames(host, 3)
	TestLib.check(DayNight.night_now > 0.9, "it is night (%.2f)" % DayNight.night_now)
	for c in herd:
		c.state = &"idle"
		c.timer = 0.0
		c.think_t = 99.0
	for c in pack:
		c.state = &"idle"
		c.timer = 0.0
		c.think_t = 99.0
	var slept := await _wait(host, func():
		var n := 0
		for c in herd:
			if c.state == &"sleep":
				n += 1
		return n >= 3, 4.0)
	var st := ""
	for c in herd:
		st += "%s/%.1f/%.0f " % [c.state, c.timer, Vector2(c.position.x - at.x, c.position.z - at.z).length()]
	TestLib.check(slept, "deer lie down at night (%s)" % st)
	var squash := true
	for c in herd:
		if c.state == &"sleep" and not c.asleep:
			squash = false
	TestLib.check(squash, "a sleeping animal is marked asleep (squashed pose)")
	var wolves_awake := true
	for c in pack:
		if c.state == &"sleep":
			wolves_awake = false
	TestLib.check(wolves_awake, "wolves do not sleep at night")
	# the hero walking up wakes them
	var wake := _ahead(at, 0.0, 9.0)
	for c in herd:
		c.global_position = Vector3(wake.x, c.position.y, wake.z)
		c.timer = 90.0
		c.state = &"sleep"
		c.asleep = true
		c.think_t = 0.0
	var woke := await _wait(host, func():
		for c in herd:
			if c.state != &"sleep":
				return true
		return false, 4.0)
	TestLib.check(woke, "sleepers wake when the hero is near")
	# day returns: they stand up
	city.day_night.set_hour(12.0)
	var away := _ahead(at, 0.0, 80.0)
	for c in herd:
		c.global_position = Vector3(away.x, c.position.y, away.z)
		c.state = &"sleep"
		c.asleep = true
		c.timer = 90.0
		c.think_t = 99.0
	var up := await _wait(host, func():
		for c in herd:
			if c.state == &"sleep":
				return false
		return true, 4.0)
	st = ""
	for c in herd:
		st += "%s/%.1f " % [c.state, c.timer]
	TestLib.check(up, "they get up when the day comes (%s)" % st)
	w.clear()


func _hunting(host: Node, prog: Progress) -> void:
	w.clear()
	w.director = false
	city.day_night.set_hour(12.0)
	var at := _teleport(PLAINS, 0.0)
	await TestLib.frames(host, 8)
	# --- the real carbine hits and kills a deer
	p.weapon.switch_to(&"carbine", true)
	var deer := _spawn_herd(&"deer", _ahead(at, 0.0, 14.0), 1)[0]
	deer.think_t = 99.0
	deer.state = &"idle"
	deer.timer = 99.0
	var eye := at + Vector3(0.0, 1.5, 0.0)
	var centre := deer.global_position + Vector3(0.0, float(deer.spec["mid"]) * deer.scale_k, 0.0)
	var r := w.ray(eye, (centre - eye).normalized(), 60.0)
	TestLib.check(not r.is_empty() and r["c"] == deer and absf(float(r["t"]) - centre.distance_to(eye)) < 2.0, "the animal ray finds the deer at its distance")
	TestLib.check(w.ray(eye, (centre - eye).normalized(), 5.0).is_empty(), "the ray stops at its range")
	TestLib.check(w.ray(eye, Vector3.UP, 60.0).is_empty(), "and misses what is not on its line")
	var credits0 := prog.credits if prog != null else 0
	var kills0 := WildlifeWorld.total_kills
	var hits0 := p.weapon.animal_hits
	var shots0 := p.weapon.shots_fired
	var n := 0
	while n < 160 and not deer.dying and w.critters.has(deer):
		p.camera_rig.aim_at(deer.global_position + Vector3(0.0, float(deer.spec["mid"]) * deer.scale_k, 0.0))
		Input.action_press(&"fire")
		await TestLib.frames(host, 1)
		n += 1
	Input.action_release(&"fire")
	TestLib.check(p.weapon.animal_hits > hits0, "the real carbine hit the deer (%d shots, %d hits)" % [p.weapon.shots_fired - shots0, p.weapon.animal_hits - hits0])
	TestLib.check(deer.dying or not w.critters.has(deer), "a few hits kill it")
	TestLib.check(WildlifeWorld.total_kills == kills0 + 1, "exactly one kill counted")
	if prog != null:
		TestLib.check(prog.credits >= credits0 + int(AnimalSpecies.data(&"deer")["bounty"]), "the bounty is paid (%d -> %d CR)" % [credits0, prog.credits])
	TestLib.check(deer.dissolve > 0.0 or not w.critters.has(deer), "the body dissolves into quantum dust")
	var released := await _wait(host, func(): return not w.critters.has(deer), 4.0)
	TestLib.check(released, "the dust settles and the body returns to the pool")
	TestLib.check(int(w.stats()["pooled"]) >= 1, "pooled bodies wait for the next animal")
	# --- a boar turns on the hero when shot at; a hurt prey runs
	w.clear()
	var boar := _spawn_herd(&"boar", _ahead(at, 0.0, 10.0), 1)[0]
	boar.state = &"idle"
	boar.think_t = 99.0
	boar.timer = 99.0
	w.hurt(boar, 5.0, true, at)
	TestLib.check(boar.state == &"chase" and boar.aggro, "a hurt boar charges the hero")
	p.max_hp = 1000.0
	p.hp = 1000.0
	var bit := await _wait(host, func(): return p.hp < 1000.0, 10.0)
	TestLib.check(bit, "it reaches him and bites (a little)")
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	w.clear()
	var goat := _spawn_herd(&"goat", _ahead(at, 0.0, 20.0), 3)
	for c in goat:
		c.state = &"idle"
		c.timer = 99.0
		c.think_t = 99.0
	w.hurt(goat[0], 1.0, true, at)
	TestLib.check(goat[0].state == &"flee" and goat[1].state == &"flee", "a hurt goat runs and its herd with it")
	# --- a shark pays 80
	w.clear()
	var credits1 := prog.credits if prog != null else 0
	var shark := _spawn_herd(&"shark", _ahead(at, 0.0, 30.0), 1)[0]
	w.kill(shark, true)
	if prog != null:
		TestLib.check(prog.credits == credits1 + 80, "a shark pays 80 CR (%d)" % (prog.credits - credits1))
	# --- a blast kills what is in it and scatters the rest
	w.clear()
	var inside := _spawn_herd(&"sheep", _ahead(at, 0.0, 35.0), 3)
	var outside := _spawn_herd(&"deer", _ahead(at, 0.0, 70.0), 2)
	for c in outside:
		c.think_t = 99.0
		c.state = &"idle"
		c.timer = 99.0
	var blast_at := inside[0].global_position
	var kills1 := WildlifeWorld.total_kills
	Game.explode(blast_at, 6.0, {"enemy_dmg": 0.0, "player_dmg": 0.0, "car_dmg": 0.0})
	TestLib.check(WildlifeWorld.total_kills > kills1 and (inside[0].dying or not w.critters.has(inside[0])), "a blast kills the animal in it")
	TestLib.check(outside[0].state == &"flee", "and scares the ones farther out")
	w.clear()


func _hazards(host: Node) -> void:
	w.clear()
	w.director = false
	var at := _teleport(PLAINS, 0.0)
	await TestLib.frames(host, 4)
	var path := _ahead(at, 0.0, 30.0)
	var deer := _spawn_herd(&"deer", path, 1)[0]
	deer.think_t = 99.0
	deer.state = &"idle"
	deer.timer = 99.0
	var src := GDScript.new()
	src.source_code = "extends Node3D\nvar speed := 18.0\n"
	src.reload()
	var car := Node3D.new()
	car.set_script(src)
	city.add_child(car)
	car.add_to_group(&"vehicle")
	car.global_position = Vector3(deer.position.x, deer.position.y, deer.position.z + 12.0)
	deer.think_t = 0.0
	var scared := await _wait(host, func(): return deer.state == &"flee", 2.0)
	TestLib.check(scared, "a fast car makes animals run")
	car.global_position = deer.global_position
	var kills0 := WildlifeWorld.total_kills
	var run_over := await _wait(host, func(): return deer.dying or not w.critters.has(deer), 2.0)
	TestLib.check(run_over, "a fast car runs an animal over (quantum dust)")
	TestLib.check(WildlifeWorld.total_kills > kills0, "a run-over counts for the hero")
	car.remove_from_group(&"vehicle")
	car.queue_free()
	w.clear()


func _pause(host: Node) -> void:
	w.clear()
	var at := _teleport(PLAINS, 0.0)
	var herd := _spawn_herd(&"horse", _ahead(at, 0.0, 70.0), 3)
	for c in herd:
		c.state = &"walk"
		c.target = Vector2(c.position.x + 30.0, c.position.z)
		c.timer = 30.0
		c.think_t = 99.0
	await _wait(host, func(): return false, 1.0)
	var p0 := herd[0].position
	Game.state = &"paused"
	w.force_active = false
	await _wait_real(host, func(): return false, 1.5)
	TestLib.check(herd[0].position.distance_to(p0) < 0.05 and w.critters.has(herd[0]), "the animals stand still while the game is paused")
	Game.state = &"play"
	w.force_active = true
	var moved := await _wait(host, func(): return herd[0].position.distance_to(p0) > 1.0, 3.0)
	TestLib.check(moved, "and move again afterwards")
	w.clear()
