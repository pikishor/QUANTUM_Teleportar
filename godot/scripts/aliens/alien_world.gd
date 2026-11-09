class_name AlienWorld
extends Node3D
## The alien world outside the city (wave 107b; docs/WORLD_EXPANSION.md "more aliens and better enemies", "alien wildlife and factions outside the city"). Child `aliens` of the City
## (AlienWorld.attach). It owns every AlienCreature and AlienBoss and does four jobs:
##   1. AMBIENT FAUNA: a spawn director fills four classes (ground, air, water, burrow) around the hero up to a cap per tier, outside the camera view, by the biome under the point
##      (AlienSpecies.weights): skitter packs in forests and on the plains, spore poppers, swarmers over the mountains, dune maws under the desert, reef lurkers and drift rays at sea. Never in the
##      city. Rare on purpose (EASY first): a gap between encounters, fewer when the hero is fast, none in interiors.
##   2. SITES (AlienSites): camps, nests, crash sites and boss lairs get a mesh (AlienSiteKit, one draw call) when the hero is within a kilometre and a garrison when he is within 200 m;
##      beyond that the garrison goes away again. Clearing a site (every guard dead, the heart destroyed, the boss down) pays credits, drops a quanta crystal and a ladder weapon, and is saved.
##   3. COMBAT SUPPORT for the creatures: projectiles (acid globs, spore and shock bolts, lobbed spore clouds), spore cloud hazards, the hero's hurt / knock-back, the leap and sentry gates that keep
##      at most a few attackers on the hero at once, the pack alarm, hatchlings.
##   4. LOOT: alien tech parts that drop as glowing shards, magnetise to the hero and bank into AlienLoot (credits, crafting parts, a ladder weapon every ten).
## Logic runs in `step(dt)` (from _physics_process while the game plays; tests call it with their own dt). QT_NO_ALIENS=1 leaves everything out (perf A/B runs).
##   AlienWorld.instance   the node;  stats()  census()  spawn_one(id, pos)  spawn_group(id, pos, n)  boss_info()  populate(site_id)  clear_all()

signal site_cleared(id: StringName)
signal boss_defeated(boss: StringName)
signal creature_killed(id: StringName, hero_kill: bool)

const CAPS := {
	AlienSpecies.GROUND: [4, 6, 9],
	AlienSpecies.AIR: [3, 5, 8],
	AlienSpecies.WATER: [1, 1, 2],
	AlienSpecies.BURROW: [1, 1, 2],
}
const RING := [[34.0, 80.0], [36.0, 92.0], [38.0, 105.0]]
const DESPAWN_K := 1.7
const AMBIENT_GAP := [16.0, 12.0, 9.0]
const SITE_TICK := 0.25
const MESH_R := 1000.0
const MESH_FREE_R := 1700.0
const POP_R := {&"camp": 200.0, &"nest": 200.0, &"crash": 230.0, &"lair": 260.0}
const NEAR_TICK := 130.0
const CITY_SKIRT := 780.0
const PROJECTILES := 22
const MAX_CREATURES := 44
const LOOT_POOL := 14
const LEAP_LIMIT := [2, 3, 4, 4]                  ## attackers on the hero at once, by difficulty mode (EASY .. QUANTUM)

static var instance: AlienWorld = null
static var total_kills := 0

var enabled := true
var quality := 1
var force_active := false                         ## tests and captures: simulate whatever the game state
var ambient_enabled := true
var fx: AlienFx
var creatures: Array[AlienCreature] = []
var hero: Node3D = null
var hero_pos := Vector3.INF                       ## the hero's chest
var hero_vel2 := Vector2.ZERO
var rng := RandomNumberGenerator.new()
var kills := {}                                   ## species -> kills by the hero
var stats_data := {"spawned": 0, "hero_hits": 0, "hero_damage": 0.0, "shots": 0, "clouds": 0, "loot": 0, "hatched": 0}
var bosses_engaged: Array[AlienBoss] = []
var sites: Dictionary = {}                        ## site id -> {node, populated, creatures, told, hearts}
var _proj: Array[Dictionary] = []
var _hazards: Array[Dictionary] = []
var _loot: Array[Dictionary] = []
var _loot_nodes: Array[MeshInstance3D] = []
var _loot_mats: Dictionary = {}
var _hero_prev := Vector3.INF
var _site_t := 0.0
var _spawn_t := 6.0
var _time := 0.0
var _first_fill := 1.0
var _hooked_new_game := false


static func attach(parent: Node) -> AlienWorld:
	var w := AlienWorld.new()
	w.name = "Aliens"
	parent.add_child(w)
	return w


func _ready() -> void:
	instance = self
	top_level = true
	rng.seed = 107007
	if not AlienKit.available():
		enabled = false
		return
	AlienSites.start()
	fx = AlienFx.new()
	fx.name = "Fx"
	add_child(fx)
	for i in PROJECTILES:
		_proj.append({"on": false})
	if not Game.new_game.is_connected(_on_new_game):
		Game.new_game.connect(_on_new_game)
	_build_loot_pool()


func _exit_tree() -> void:
	if instance == self:
		instance = null
		if Sfx.boss_active and not bosses_engaged.is_empty():
			Sfx.boss_active = false


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)


func cap_of(cls: StringName) -> int:
	var n: int = CAPS[cls][quality]
	return LowPlus.scaled(n, 0.6, 1) if LowPlus.on() else n


func _on_new_game() -> void:
	AlienSites.reset_all()
	clear_all()


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if force_active or Game.is_playing():
		step(minf(delta, 0.1))


# --- the main loop -------------------------------------------------------------------------------------------------------------------------------

func step(dt: float) -> void:
	if not enabled or fx == null:
		return
	_time += dt
	_focus_hero(dt)
	fx.tick(dt)
	_tick_projectiles(dt)
	_tick_hazards(dt)
	_tick_loot(dt)
	if not hero_pos.is_finite() or not AlienSites.ready_now():
		return
	_first_fill = maxf(0.0, _first_fill - dt)
	_site_t -= dt
	if _site_t <= 0.0:
		_site_t = SITE_TICK
		_tick_sites()
	if ambient_enabled:
		_spawn_t -= dt
		if _spawn_t <= 0.0:
			_spawn_t = float(AMBIENT_GAP[quality]) * (1.5 if Difficulty.current == Difficulty.EASY else 1.0) * rng.randf_range(0.8, 1.3)
			_try_spawn_ambient()
	var hero2 := Vector2(hero_pos.x, hero_pos.z)
	var despawn_r: float = float(RING[quality][1]) * DESPAWN_K
	var i := creatures.size() - 1
	while i >= 0:
		var c := creatures[i]
		i -= 1
		if not is_instance_valid(c):
			creatures.remove_at(i + 1)
			continue
		if c.is_gone():
			_remove(c)
			continue
		var d := Vector2(c.position.x, c.position.z).distance_to(hero2)
		if c.site == &"" and not c.dead and c.family != AlienSpecies.BOSS and d > despawn_r * (1.5 if c.cls == AlienSpecies.AIR else 1.0):
			_remove(c)
			continue
		c.visible = d < 190.0 and (c.exposed or c.rise > 0.02 or c.dead)
		if d > NEAR_TICK and not c.aggro and not c.dead and c.family != AlienSpecies.BOSS:
			continue                                                      # a far camp guard just stands there
		c.tick(dt)


func _remove(c: AlienCreature) -> void:
	creatures.erase(c)
	if c is AlienBoss:
		bosses_engaged.erase(c as AlienBoss)
	if is_instance_valid(c):
		if c.is_in_group(&"enemy"):
			c.remove_from_group(&"enemy")
		c.queue_free()


func clear_all() -> void:
	for c in creatures.duplicate():
		_remove(c)
	creatures.clear()
	bosses_engaged.clear()
	for k in sites:
		var sd: Dictionary = sites[k]
		sd["populated"] = false
		sd["creatures"] = []
		sd["told"] = false
	for p in _proj:
		p["on"] = false
	_hazards.clear()
	for l in _loot:
		(l["node"] as Node3D).visible = false
	_loot.clear()
	if fx != null:
		for i in AlienFx.SPRITES:
			fx.sprite_off(i)
	if Sfx.boss_active:
		Sfx.boss_active = false


func _focus_hero(dt: float) -> void:
	hero = Game.player as Node3D
	var f := Vector3.INF
	if is_instance_valid(hero):
		f = hero.global_position
	else:
		var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
		if cam != null:
			f = cam.global_position
	if f.is_finite() and _hero_prev.is_finite() and dt > 0.0:
		var v := (f - _hero_prev) / dt
		hero_vel2 = hero_vel2.lerp(Vector2(clampf(v.x, -40.0, 40.0), clampf(v.z, -40.0, 40.0)), clampf(dt * 6.0, 0.0, 1.0))
	_hero_prev = f
	hero_pos = f + Vector3(0.0, 1.0, 0.0) if f.is_finite() else Vector3.INF


func hero_alive() -> bool:
	if not hero_pos.is_finite():
		return false
	if is_instance_valid(hero) and hero.has_method(&"is_dead") and bool(hero.call(&"is_dead")):
		return false
	return force_active or Game.is_playing()


func hero_speed() -> float:
	return hero_vel2.length()


# --- ambient fauna -------------------------------------------------------------------------------------------------------------------------------

func count_of(cls: StringName) -> int:
	var n := 0
	for c in creatures:
		if c.site == &"" and c.cls == cls and not c.dead:
			n += 1
	return n


func ambient_count() -> int:
	var n := 0
	for c in creatures:
		if c.site == &"" and not c.dead and c.family == AlienSpecies.FAUNA:
			n += 1
	return n


func _try_spawn_ambient() -> bool:
	if InteriorGameplay.active or hero_speed() > 26.0:
		return false
	if maxf(absf(hero_pos.x), absf(hero_pos.z)) < CITY_SKIRT + 20.0:
		return false
	if creatures.size() >= MAX_CREATURES:
		return false
	var order: Array = []
	for cls in [AlienSpecies.GROUND, AlienSpecies.AIR, AlienSpecies.WATER, AlienSpecies.BURROW]:
		var cap := cap_of(cls)
		var n := count_of(cls)
		if n < cap:
			order.append([float(n) / float(cap) + rng.randf() * 0.2, cls])
	order.sort_custom(func(a, b): return a[0] < b[0])
	for e in order:
		if _spawn_for_class(e[1]):
			return true
	return false


func _spawn_for_class(cls: StringName) -> bool:
	for t in 6:
		var p := _ring_point(cls)
		if not p.is_finite():
			continue
		var h := p.y
		var biome := TerrainBase.biome_at(p.x, p.z, h)
		var w := TerrainHeight.water_level_for(p.x, p.z, h)
		var depth := w - h if w != TerrainHeight.NO_WATER else 0.0
		if cls == AlienSpecies.WATER:
			if depth < 3.0 or biome != TerrainBase.OCEAN:
				continue
		elif cls == AlienSpecies.GROUND or cls == AlienSpecies.BURROW:
			if depth > 0.4 or TerrainHeight.slope_at(p.x, p.z) > 1.0:
				continue
		var list := AlienSpecies.weights(cls, biome, h, TerrainHeight.slope_at(p.x, p.z), DayNight.night_now)
		var id := AlienSpecies.pick(list, rng.randf())
		if id == &"":
			continue
		var spec := AlienSpecies.data(id)
		var g: Array = spec["group"]
		var room := cap_of(cls) - count_of(cls)
		var n := mini(rng.randi_range(int(g[0]), int(g[1])), room)
		if Difficulty.current == Difficulty.EASY:
			n = maxi(1, n - 1) if n > 2 else n
		if n <= 0:
			return false
		var placed := spawn_group(id, p, n, &"", 3.0 + 0.8 * float(n), false)
		if not placed.is_empty():
			return true
	return false


func _ring_point(cls: StringName) -> Vector3:
	var rmin: float = RING[quality][0]
	var rmax: float = RING[quality][1]
	if cls == AlienSpecies.WATER or cls == AlienSpecies.BURROW:
		rmin = 26.0
		rmax = 58.0
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var fwd := Vector2(0.0, -1.0)
	if cam != null:
		var f3 := -cam.global_basis.z
		fwd = Vector2(f3.x, f3.z).normalized() if Vector2(f3.x, f3.z).length() > 0.05 else fwd
	var a := atan2(fwd.y, fwd.x) + rng.randf_range(-1.4, 1.4) if rng.randf() < 0.6 else rng.randf() * TAU
	var r := lerpf(rmin, rmax, sqrt(rng.randf()))
	var x := hero_pos.x + cos(a) * r
	var z := hero_pos.z + sin(a) * r
	if maxf(absf(x), absf(z)) < CITY_SKIRT or maxf(absf(x), absf(z)) > TerrainHeight.WORLD_HALF - 60.0:
		return Vector3.INF
	if OutskirtsSites.inside(x, z, 20.0) >= 0:
		return Vector3.INF
	var h := TerrainHeight.height_at(x, z)
	var p := Vector3(x, h, z)
	if cam != null and _first_fill <= 0.0 and r < rmax * 0.9 and cls != AlienSpecies.AIR and cam.is_position_in_frustum(p + Vector3(0.0, 1.0, 0.0)):
		return Vector3.INF
	return p


# --- creating creatures -------------------------------------------------------------------------------------------------------------------------

func make(id: StringName) -> AlienCreature:
	var spec := AlienSpecies.data(id)
	if spec.is_empty():
		return null
	var c: AlienCreature
	var mech := StringName(spec["mech"])
	if mech == &"arm":
		c = AlienArm.new()
	elif String(mech).begins_with("boss_"):
		c = AlienBoss.new()
	else:
		c = AlienCreature.new()
	if not c.setup(id, self):
		c.free()
		return null
	return c


## One creature of species `id` at `pos` (x, z used; the height is the ground or the water line). `aggro` starts it awake. Null when the cap is full or the model is missing.
func spawn_one(id: StringName, pos: Vector3, site := &"", aggro := false) -> AlienCreature:
	if not enabled or creatures.size() >= MAX_CREATURES + (6 if site != &"" else 0):
		return null
	var c := make(id)
	if c == null:
		return null
	add_child(c)
	var gy := TerrainHeight.height_at(pos.x, pos.z)
	var w := TerrainHeight.water_level_for(pos.x, pos.z, gy)
	c.ground = gy
	c.water_y = w
	var y := gy
	if c.cls == AlienSpecies.WATER and w != TerrainHeight.NO_WATER:
		y = w
	elif c.cls == AlienSpecies.AIR:
		var al := float((AlienSpecies.data(id).get("alt", [4.0, 8.0]) as Array)[0]) if AlienSpecies.data(id).has("alt") else 24.0
		c.alt = al + 1.0 if c.family != AlienSpecies.BOSS else 24.0
		y = gy + c.alt
	c.position = Vector3(pos.x, y, pos.z)
	c.home = c.position
	c.site = site
	c.heading = rng.randf() * TAU
	if aggro:
		c.aggro = true
	c.visible = true
	creatures.append(c)
	stats_data["spawned"] = int(stats_data["spawned"]) + 1
	if site != &"" and sites.has(site):
		((sites[site] as Dictionary)["creatures"] as Array).append(c)
	return c


## A pack of `n` creatures around `pos` (spread metres); they share a group dictionary (the pack alarm, the fan-out). Returns the creatures made.
func spawn_group(id: StringName, pos: Vector3, n: int, site := &"", spread := 5.0, aggro := false) -> Array[AlienCreature]:
	var out: Array[AlienCreature] = []
	var g := {"members": [], "id": id}
	for k in n:
		var a := TAU * float(k) / float(maxi(n, 1)) + rng.randf() * 0.6
		var rr := rng.randf_range(0.0, spread) if n > 1 else 0.0
		var c := spawn_one(id, pos + Vector3(cos(a) * rr, 0.0, sin(a) * rr), site, aggro)
		if c == null:
			continue
		c.group = g
		c.slot = TAU * float(k) / float(maxi(n, 1))
		(g["members"] as Array).append(c)
		out.append(c)
	return out


# --- sites ----------------------------------------------------------------------------------------------------------------------------------------

func _tick_sites() -> void:
	var built_one := false
	var hero2 := Vector2(hero_pos.x, hero_pos.z)
	for s in AlienSites.list:
		var id: StringName = s["id"]
		var sp: Vector3 = s["pos"]
		var d := hero2.distance_to(Vector2(sp.x, sp.z))
		if not sites.has(id):
			sites[id] = {"node": null, "populated": false, "creatures": [], "told": false, "body": null}
		var sd: Dictionary = sites[id]
		if sd["node"] == null and d < MESH_R and not built_one and not bool(s.get("no_mesh", false)):
			_build_site_mesh(s, sd)
			built_one = true
		elif sd["node"] != null and d > MESH_FREE_R:
			(sd["node"] as Node).queue_free()
			sd["node"] = null
			if sd["body"] != null and is_instance_valid(sd["body"]):
				(sd["body"] as Node).queue_free()
			sd["body"] = null
		var cleared := AlienSites.is_cleared(id)
		if d < 170.0 and not bool(sd["told"]) and not cleared:
			sd["told"] = true
			Game.say("%s  %s" % [String(s["name"]), String(s["tag"])], 2.8)
		var pr: float = POP_R.get(s["kind"], 200.0)
		if not bool(sd["populated"]) and not cleared and d < pr and hero_alive():
			populate(id)
		elif bool(sd["populated"]) and d > pr * 1.9:
			_depopulate(id)


func _build_site_mesh(s: Dictionary, sd: Dictionary) -> void:
	var kit := AlienSiteKit.build(s)
	if kit.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = kit["mesh"]
	mi.material_override = AlienKit.site_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = MESH_R + 200.0
	mi.extra_cull_margin = 60.0
	mi.position = (s["pos"] as Vector3)
	mi.rotation.y = float(s["yaw"])
	add_child(mi)
	sd["node"] = mi
	var boxes: Array = kit.get("boxes", [])
	if not boxes.is_empty():
		var body := StaticBody3D.new()
		body.collision_layer = Game.L_WORLD
		body.collision_mask = 0
		body.position = mi.position
		body.rotation.y = mi.rotation.y
		for b: Array in boxes:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = b[1] as Vector3
			cs.shape = bs
			cs.position = b[0] as Vector3
			body.add_child(cs)
		add_child(body)
		sd["body"] = body
	sd["tris"] = int(kit.get("tris", 0))


## Brings the garrison of a site to life. Idempotent. Returns the creatures made.
func populate(id: StringName) -> Array[AlienCreature]:
	var out: Array[AlienCreature] = []
	var s := AlienSites.by_id(id)
	if s.is_empty() or not enabled:
		return out
	if not sites.has(id):
		sites[id] = {"node": null, "populated": false, "creatures": [], "told": false, "body": null}
	var sd: Dictionary = sites[id]
	if bool(sd["populated"]):
		return out
	sd["populated"] = true
	sd["creatures"] = []
	var kind: StringName = s["kind"]
	var c0: Vector3 = s["pos"]
	var rad := float(s["r"])
	var guard_n := 0
	for g: Array in (s["guards"] as Array):
		for k in int(g[1]):
			var a := rng.randf() * TAU
			var rr := rng.randf_range(rad * 0.25, rad * 0.55)
			var c := spawn_one(StringName(g[0]), c0 + Vector3(cos(a) * rr, 0.0, sin(a) * rr), id, false)
			if c != null:
				c.leash = rad * 2.2
				out.append(c)
				guard_n += 1
	for k in int(s.get("sentries", 0)):
		var a2 := TAU * float(k) / float(maxi(int(s["sentries"]), 1)) + 0.7
		var c2 := spawn_one(&"spore_sentry", c0 + Vector3(cos(a2) * rad * 0.62, 0.0, sin(a2) * rad * 0.62), id, false)
		if c2 != null:
			out.append(c2)
			guard_n += 1
	match kind:
		&"nest":
			var heart := spawn_one(&"hive_heart", c0, id, false)
			if heart != null:
				out.append(heart)
				sd["heart"] = heart
		&"crash", &"lair":
			var boss_id: StringName = s.get("boss", &"")
			if boss_id != &"" and not AlienSites.boss_down(boss_id):
				var b := _spawn_boss(s, boss_id, c0)
				if b != null:
					out.append(b)
					sd["boss"] = b
	sd["guards"] = guard_n
	return out


func _spawn_boss(s: Dictionary, boss_id: StringName, c0: Vector3) -> AlienBoss:
	var spec := AlienSpecies.data(boss_id)
	var at := c0
	if boss_id == &"deep_kraken":
		at = Vector3(c0.x, TerrainHeight.SEA_LEVEL, c0.z)
	var b := spawn_one(boss_id, at, StringName(s["id"]), false) as AlienBoss
	if b == null:
		return null
	b.lair = c0
	b.leash = float(spec["sight"]) * 2.0
	if boss_id == &"storm_drake":
		b.alt = 24.0
		b.position.y = TerrainHeight.height_at(c0.x, c0.z) + 24.0
	if boss_id == &"hive_warden":
		b.alt = 5.0
		b.position.y = TerrainHeight.height_at(c0.x, c0.z) + 5.0
		var n := int(s.get("relays", 3))
		for k in n:
			var a := TAU * float(k) / float(n) + 0.5
			var rp := c0 + Vector3(cos(a) * 22.0, 0.0, sin(a) * 22.0)
			var r := spawn_one(&"relay_pod", rp, StringName(s["id"]), false)
			if r != null:
				b.relays.append(r)
		b.shield_on = not b.relays.is_empty()
	return b


func _depopulate(id: StringName) -> void:
	var sd: Dictionary = sites.get(id, {})
	for c: Variant in (sd.get("creatures", []) as Array):
		if is_instance_valid(c) and not (c as AlienCreature).dead:
			_remove(c as AlienCreature)
		elif is_instance_valid(c):
			_remove(c as AlienCreature)
	sd["creatures"] = []
	sd["populated"] = false
	sd["boss"] = null
	sd["heart"] = null


func site_creatures(id: StringName) -> Array[AlienCreature]:
	var out: Array[AlienCreature] = []
	if sites.has(id):
		for c: Variant in ((sites[id] as Dictionary)["creatures"] as Array):
			if is_instance_valid(c) and not (c as AlienCreature).dead:
				out.append(c as AlienCreature)
	return out


## One camp-mate was hurt or woke: the rest of the camp within 70 m wakes too.
func alert_site(id: StringName, from: AlienCreature) -> void:
	if id == &"":
		return
	for c in creatures:
		if c != from and c.site == id and not c.dead and not c.aggro and c.global_position.distance_to(from.global_position) < 70.0 and c.family != AlienSpecies.BOSS:
			c.aggro = true


func note_hit(_c: AlienCreature) -> void:
	pass


func on_died(c: AlienCreature, hero_kill: bool) -> void:
	if hero_kill:
		kills[c.id] = int(kills.get(c.id, 0)) + 1
		total_kills += 1
		var pg := Game.progress as Progress
		if pg != null and int(c.spec["bounty"]) > 0:
			pg.add_credits(int(round(float(c.spec["bounty"]) * Difficulty.mult("credits"))))
		_drop_loot(c)
	creature_killed.emit(c.id, hero_kill)
	if c.site != &"":
		_check_site(c.site, c)


func _check_site(id: StringName, dead_one: AlienCreature) -> void:
	var s := AlienSites.by_id(id)
	if s.is_empty() or AlienSites.is_cleared(id):
		return
	var sd: Dictionary = sites.get(id, {})
	var kind: StringName = s["kind"]
	var done := false
	match kind:
		&"nest":
			var h: Variant = sd.get("heart")
			done = h != null and (not is_instance_valid(h) or (h as AlienCreature).dead)
		&"lair", &"crash":
			var b: Variant = sd.get("boss")
			if b != null and (not is_instance_valid(b) or (b as AlienCreature).dead):
				done = true
				AlienSites.mark_boss(StringName(s.get("boss", &"")))
				boss_defeated.emit(StringName(s.get("boss", &"")))
			elif b == null and kind == &"crash":
				done = _guards_down(id)
		_:
			done = _guards_down(id)
	if done:
		_clear_site(s, dead_one.global_position)


func _guards_down(id: StringName) -> bool:
	for c: Variant in ((sites.get(id, {}) as Dictionary).get("creatures", []) as Array):
		if is_instance_valid(c) and not (c as AlienCreature).dead and (c as AlienCreature).mech != &"relay":
			return false
	return true


func _clear_site(s: Dictionary, at: Vector3) -> void:
	var id: StringName = s["id"]
	AlienSites.mark_cleared(id)
	var reward := int(s["reward"])
	var pg := Game.progress as Progress
	if pg != null:
		pg.add_credits(reward)
	Game.say("%s CLEARED  +%d" % [String(s["name"]), reward], 3.4)
	Sfx.play(&"mission_complete", -4.0)
	var c0: Vector3 = s["pos"]
	drop_part(&"crystal", 1 + (1 if s["kind"] == &"lair" else 0), Vector3(c0.x, TerrainHeight.height_at(c0.x, c0.z), c0.z) + Vector3(2.0, 0.0, 0.0))
	var m := Game.missions
	if (s["kind"] == &"lair" or s["kind"] == &"crash") and is_instance_valid(m) and m.has_method(&"drop_weapon"):
		var w := WeaponLadder.next_target()
		if w != &"":
			m.call(&"drop_weapon", w, c0 + Vector3(0.0, 0.0, -2.0))
	Crafting.award(&"side")
	site_cleared.emit(id)
	# the camp falls quiet: the rest of the garrison (a stray hatchling) dissolves
	for c: Variant in ((sites.get(id, {}) as Dictionary).get("creatures", []) as Array):
		if is_instance_valid(c) and not (c as AlienCreature).dead:
			(c as AlienCreature).die(false)


## The heart of a nest hatches `n` skitters at once (3 at most alive per heart).
func hatch(heart: AlienCreature, n: int) -> void:
	var alive := 0
	for c in creatures:
		if c.site == heart.site and c.id == &"skitter" and not c.dead:
			alive += 1
	var room := maxi(0, 5 - alive)
	if room <= 0:
		return
	var made := spawn_group(&"skitter", heart.position + Vector3(0.0, 0.0, 3.5), mini(n, room), heart.site, 3.5, true)
	for m in made:
		m.leash = 120.0
	stats_data["hatched"] = int(stats_data["hatched"]) + made.size()
	FX.burst(heart.position + Vector3(0.0, 1.0, 3.5), Color(1.0, 0.4, 0.6), 12, 4.0, 0.7, 3.0, 3.0)
	Sfx.play_at(&"water_bubble", heart.position, -2.0, 0.6)


# --- attackers' gates -----------------------------------------------------------------------------------------------------------------------------

func leap_gate(c: AlienCreature) -> bool:
	var limit := int(LEAP_LIMIT[Difficulty.clamp_mode(Difficulty.current)])
	var n := 0
	for o in creatures:
		if o != c and not o.dead and (o.state == &"crouch" or o.state == &"leap" or o.state == &"dive" or o.state == &"hover" or o.state == &"windup"):
			n += 1
	return n < limit


func sentry_gate(c: AlienCreature) -> bool:
	var n := 0
	for o in creatures:
		if o != c and not o.dead and o.mech == &"turret" and (o.state == &"windup" or o.state == &"fire"):
			n += 1
	return n < 2


# --- hurting the hero -----------------------------------------------------------------------------------------------------------------------------

func hurt_hero(amount: float, from: Vector3, _by: AlienCreature = null) -> bool:
	var p := Game.player
	if not is_instance_valid(p) or not hero_alive() or amount <= 0.0 or not p.has_method(&"damage"):
		return false
	var before: Variant = p.get(&"hp")
	p.call(&"damage", amount, from)
	stats_data["hero_hits"] = int(stats_data["hero_hits"]) + 1
	var after: Variant = p.get(&"hp")
	if before is float and after is float:
		stats_data["hero_damage"] = float(stats_data["hero_damage"]) + maxf(0.0, float(before) - float(after))
	return true


func knock_hero(impulse: Vector3) -> void:
	var p := Game.player
	if not is_instance_valid(p) or not hero_alive():
		return
	var v: Variant = p.get(&"vehicle")
	if v is Node3D and is_instance_valid(v):
		return
	var cur: Variant = p.get(&"velocity")
	if cur is Vector3:
		p.set(&"velocity", (cur as Vector3) + impulse)


# --- projectiles and hazards ----------------------------------------------------------------------------------------------------------------------

## A straight shot (acid glob, spore bolt, shock bolt) from `from` along `dir`.
func shoot(from: Vector3, dir: Vector3, speed: float, dmg: float, radius: float, color: Color, size: float, owner: AlienCreature = null) -> void:
	_add_proj({"pos": from, "vel": dir.normalized() * speed, "dmg": dmg, "r": radius, "col": color, "size": size, "life": 4.0, "grav": 2.0, "owner": owner, "kind": &"shot"})


## A lobbed spore cloud: flies in an arc to `to`, then a cloud of radius `r` hangs there `secs` seconds.
func lob_cloud(from: Vector3, to: Vector3, flight: float, r: float, secs: float) -> void:
	var g := 18.0
	var d := to - from
	var vel := Vector3(d.x / flight, d.y / flight + 0.5 * g * flight, d.z / flight)
	_add_proj({"pos": from, "vel": vel, "dmg": 0.0, "r": 0.5, "col": Color(0.8, 0.45, 1.0), "size": 1.0, "life": flight + 1.0, "grav": g, "owner": null, "kind": &"lob", "to": to, "cr": r, "cs": secs})


func _add_proj(d: Dictionary) -> void:
	for i in _proj.size():
		if not bool(_proj[i]["on"]):
			d["on"] = true
			d["slot"] = i
			_proj[i] = d
			stats_data["shots"] = int(stats_data["shots"]) + 1
			return
	var oldest := 0
	d["on"] = true
	d["slot"] = oldest
	_proj[oldest] = d


func active_projectiles() -> int:
	var n := 0
	for p in _proj:
		if bool(p["on"]):
			n += 1
	return n


func _hero_segment_dist(p: Vector3) -> float:
	var pl := Game.player as Node3D
	if not is_instance_valid(pl):
		return INF
	var v: Variant = pl.get(&"vehicle")
	if v is Node3D and is_instance_valid(v):
		return (v as Node3D).global_position.distance_to(p) - 1.6
	var a := pl.global_position + Vector3(0.0, 0.2, 0.0)
	var b := pl.global_position + Vector3(0.0, 1.7, 0.0)
	return WorldSteps.seg_dist(a, b, p)


func _tick_projectiles(dt: float) -> void:
	for i in _proj.size():
		var p: Dictionary = _proj[i]
		if not bool(p["on"]):
			continue
		p["life"] = float(p["life"]) - dt
		var vel: Vector3 = p["vel"]
		vel.y -= float(p["grav"]) * dt
		p["vel"] = vel
		var pos: Vector3 = p["pos"]
		var np := pos + vel * dt
		p["pos"] = np
		fx.sprite(i, np, float(p["size"]), p["col"])
		var kind: StringName = p["kind"]
		var gy := TerrainHeight.height_at(np.x, np.z)
		var hit_hero := kind == &"shot" and hero_alive() and _hero_segment_dist(np) < float(p["r"]) + 0.3
		if hit_hero:
			var owner: Variant = p["owner"]
			hurt_hero(float(p["dmg"]), pos)
			FX.burst(np, p["col"], 8, 5.0, 0.35, 5.0, 2.0)
			_end_proj(i)
			continue
		if np.y < gy + 0.1 or float(p["life"]) <= 0.0:
			if kind == &"lob":
				spore_cloud(p["to"] as Vector3, float(p["cr"]), float(p["cs"]))
				fx.splash(np, 2.0)
			elif np.y < gy + 0.1:
				FX.burst(np, p["col"], 8, 4.0, 0.4, 6.0, 2.0)
				if FX.marks != null:
					var c: Color = p["col"]
					FX.marks.splat(Vector3(np.x, gy + 0.05, np.z), Vector3.UP, 0.9, c.lerp(Color(0.5, 1.0, 0.2), 0.4))
				if hero_alive() and hero_pos.distance_to(Vector3(np.x, gy, np.z)) < 1.8 and float(p["dmg"]) > 0.0:
					hurt_hero(float(p["dmg"]) * 0.5, pos)                              # an acid splash on the ground still burns a hero standing in it
			_end_proj(i)


func _end_proj(i: int) -> void:
	_proj[i]["on"] = false
	fx.sprite_off(i)


## A cloud hazard of radius `r` at `pos` for `secs` seconds (spore popper, broodmother): it hurts a little every half second inside.
func spore_cloud(pos: Vector3, r: float, secs: float) -> void:
	stats_data["clouds"] = int(stats_data["clouds"]) + 1
	if _hazards.size() >= 6:
		_hazards.remove_at(0)
	_hazards.append({"pos": pos, "r": r, "t": secs, "tick": 0.3, "puff": 0.0})
	FX.burst(pos + Vector3(0.0, 0.6, 0.0), Color(0.75, 0.95, 0.3, 0.6), 14, 3.0, 1.2, -0.5, 6.0)


func hazard_count() -> int:
	return _hazards.size()


func _tick_hazards(dt: float) -> void:
	var i := _hazards.size() - 1
	while i >= 0:
		var h: Dictionary = _hazards[i]
		h["t"] = float(h["t"]) - dt
		h["tick"] = float(h["tick"]) - dt
		h["puff"] = float(h["puff"]) - dt
		var pos: Vector3 = h["pos"]
		if float(h["puff"]) <= 0.0:
			h["puff"] = 0.8
			FX.burst(pos + Vector3(0.0, 0.5, 0.0), Color(0.75, 0.95, 0.3, 0.45), 6, 1.8, 1.0, -0.3, 5.0)
		if float(h["tick"]) <= 0.0:
			h["tick"] = 0.5
			if hero_alive() and hero_pos.distance_to(pos + Vector3(0.0, 0.8, 0.0)) < float(h["r"]):
				hurt_hero(3.5, pos)
		if float(h["t"]) <= 0.0:
			_hazards.remove_at(i)
		i -= 1


# --- loot -----------------------------------------------------------------------------------------------------------------------------------------

func _build_loot_pool() -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.5
	sm.radial_segments = 4
	sm.rings = 2
	for pid: StringName in AlienSpecies.PART_IDS:
		var m := AlienFx._mat()
		var c: Color = AlienSpecies.PARTS[pid]["color"]
		m.albedo_color = Color(c.r, c.g, c.b, 1.0)
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		m.emission_enabled = true
		_loot_mats[pid] = m
	for i in LOOT_POOL:
		var n := MeshInstance3D.new()
		n.mesh = sm
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.visible = false
		add_child(n)
		_loot_nodes.append(n)


func _drop_loot(c: AlienCreature) -> void:
	for e: Array in AlienSpecies.roll_loot(c.id, rng):
		drop_part(StringName(e[0]), int(e[1]), c.global_position)


## Drops `n` shards of `part` at `pos` (they scatter a little; the oldest shard is recycled when the pool is full).
func drop_part(part: StringName, n: int, pos: Vector3) -> void:
	for k in n:
		var node: MeshInstance3D = null
		for nd in _loot_nodes:
			if not nd.visible:
				node = nd
				break
		if node == null:
			var oldest: Dictionary = _loot[0]
			node = oldest["node"]
			_loot.remove_at(0)
		var a := rng.randf() * TAU
		var p := pos + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.4, 1.8)
		p.y = TerrainHeight.height_at(p.x, p.z) + 0.6
		node.material_override = _loot_mats[part]
		node.position = p
		node.visible = true
		_loot.append({"node": node, "part": part, "pos": p, "t": 150.0, "ph": rng.randf() * TAU})
		stats_data["loot"] = int(stats_data["loot"]) + 1


func loot_count() -> int:
	return _loot.size()


func _tick_loot(dt: float) -> void:
	var i := _loot.size() - 1
	while i >= 0:
		var l: Dictionary = _loot[i]
		var node: MeshInstance3D = l["node"]
		l["t"] = float(l["t"]) - dt
		var pos: Vector3 = l["pos"]
		if hero_pos.is_finite():
			var to := (hero_pos - Vector3(0.0, 0.2, 0.0)) - pos
			var d := to.length()
			if d < 6.5:
				pos += to.normalized() * minf(d, (4.0 + (6.5 - d) * 3.0) * dt)
				l["pos"] = pos
			if d < 1.5:
				AlienLoot.collect(StringName(l["part"]), 1, pos)
				node.visible = false
				_loot.remove_at(i)
				i -= 1
				continue
		node.position = pos + Vector3(0.0, 0.12 * sin(_time * 3.0 + float(l["ph"])), 0.0)
		node.rotation.y += dt * 2.0
		if float(l["t"]) <= 0.0:
			node.visible = false
			_loot.remove_at(i)
		i -= 1


# --- bosses and the HUD -----------------------------------------------------------------------------------------------------------------------------

func boss_engaged(b: AlienBoss) -> void:
	if not (b in bosses_engaged):
		bosses_engaged.append(b)


func boss_left(b: AlienBoss) -> void:
	bosses_engaged.erase(b)
	if bosses_engaged.is_empty():
		Sfx.boss_active = false


## {name, frac, hint} of the boss the hero is fighting (the nearest engaged one), {} when none.
func boss_info() -> Dictionary:
	var best: AlienBoss = null
	var bd := INF
	for b in bosses_engaged:
		if is_instance_valid(b) and not b.dead:
			var d := b.global_position.distance_to(hero_pos) if hero_pos.is_finite() else 0.0
			if d < bd:
				bd = d
				best = b
	if best == null:
		return {}
	return {"name": best.title, "frac": best.frac(), "hint": best.hint()}


static func boss_bar() -> Dictionary:
	return instance.boss_info() if instance != null and is_instance_valid(instance) else {}


# --- reading the world (tests, map, HUD) -------------------------------------------------------------------------------------------------------------

func census(center: Vector3, r: float) -> Dictionary:
	var out := {}
	for c in creatures:
		if not c.dead and Vector2(c.position.x - center.x, c.position.z - center.z).length() <= r:
			out[c.id] = int(out.get(c.id, 0)) + 1
	return out


func stats() -> Dictionary:
	var d := stats_data.duplicate()
	d["alive"] = creatures.size()
	d["ambient"] = ambient_count()
	d["kills"] = total_kills
	d["loot_live"] = _loot.size()
	d["projectiles"] = active_projectiles()
	d["hazards"] = _hazards.size()
	return d
