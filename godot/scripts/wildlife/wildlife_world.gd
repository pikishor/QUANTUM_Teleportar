class_name WildlifeWorld
extends Node3D
## The wildlife of the outskirts, the coast and the sea (owner round 5: "different animals on mountains and outskirts"): deer herds and wolf packs in the forests, mountain goats on the
## cliffs, boars, foxes, coyotes and zebras on the plains, cows / sheep / horses around the two farms, lizards in the desert, songbird flocks, eagles over the ranges, seagulls on the
## beaches and at the harbour, fish schools in the rivers, dolphins and sharks off the coast and the odd whale far out. Child `wildlife` of the City (WildlifeWorld.attach).
##
## How it stays cheap: bodies are pooled `Critter`s (skinned, ONE draw call each, 158 to 1354 triangles) and only exist near the hero. A spawn director fills four classes up to a
## cap per tier (LAND / AIR / WATER / SMALL x LOW MED HIGH) in a ring around the hero, outside the camera view, by the biome under the point (`AnimalSpecies.weights`: biome, height,
## slope, time of day, farm, shore). Far bodies are frozen (animation off beyond 55 m, ground sampling at a low rate), very far ones hidden, beyond the despawn range they go back to
## the pool. The terrain is asked at 6 Hz per moving animal, never per frame. QT_NO_WILDLIFE=1 leaves it out (perf A/B runs).
##
## Behaviour (all in this file, plain steering, no physics):
##  - prey (deer, goats, boars, sheep, cows, horses, zebras) graze, wander with the herd and run from the hero, gunfire, blasts, fast cars and hunting predators (the whole herd goes);
##  - predators (wolves, coyotes) pick a prey in reach and hunt it down (the prey dissolves, the pack feeds); provoked ones (and boars) charge the hero and bite a little;
##  - at night the grazers lie down (squashed pose), wolves and coyotes roam and howl, songbirds and eagles are gone, lizards hide;
##  - flocks circle (eagles soar, gulls work the coast, songbirds circle the trees) and scatter and climb away from shots and from the hero; gulls also stand on the sand;
##  - fish schools follow the river, dart and dive when scared; dolphin pods porpoise along the coast; a shark's fin cuts the surface; whales swim slowly far out.
## Hunting is optional: a hit costs health, a kill pays a bounty (deer 30, wolf 45, shark 80 ...) and the body dissolves into quantum dust (no gore); fish and dolphins pay nothing.
##   WildlifeWorld.instance   the node;  stats()  census(center, r)  spawn_group(id, pos, n)  settle(pos)  ray(origin, dir, max_t)  hurt(c, amount, by_hero)  kill(c, by_hero)

signal killed(species: StringName, pos: Vector3, by_hero: bool)

const CAPS := {
	AnimalSpecies.LAND: [8, 14, 22],
	AnimalSpecies.AIR: [5, 9, 15],
	AnimalSpecies.WATER: [4, 7, 11],
	AnimalSpecies.SMALL: [3, 6, 10],
}
const RING := [[26.0, 78.0], [28.0, 92.0], [30.0, 108.0]]               ## spawn ring (min, max metres from the hero) per tier
const DESPAWN_K := 1.55
const ANIM_RANGE := 58.0                                               ## beyond this a body holds its pose
const HIDE_RANGE := 150.0
const SPAWN_INTERVAL := 0.3
const DISSOLVE_TIME := 1.25
const TAU_TURN := 5.5
const FEAR_PROPAGATE := 46.0

static var instance: WildlifeWorld = null
static var total_kills := 0                                          ## kills by the hero this session (tests, achievements later)

var quality := 1
var enabled := true
var force_active := false                                           ## tests and captures: simulate whatever the game state
var director := true                                                ## false: nothing is spawned on its own (tests and captures place the animals by hand)
var critters: Array[Critter] = []
var rng := RandomNumberGenerator.new()
var bounty_total := 0
var spawned_total := 0
var stats_kills := {}                                                ## species -> kills by the hero
var _free := {}                                                      ## species -> Array[Critter]
var _farms: Array[Vector2] = []
var _hero := Vector3.INF
var _hero2 := Vector2.ZERO
var _hero_prev := Vector3.INF
var _hero_speed := 0.0
var _spawn_t := 0.0
var _hz_t := 0.0
var _danger: Array = []                                              ## [Vector2 pos, radius, speed, node] of fast vehicles near the hero
var _hunters: Array[Critter] = []
var _hooked: Node = null
var _active_prev := false
var _first_fill := 0.0
var _last_focus := Vector3.INF
var _t := 0.0
var _voice_gate := 0.0


static func attach(parent: Node) -> WildlifeWorld:
	var w := WildlifeWorld.new()
	w.name = "Wildlife"
	parent.add_child(w)
	return w


func _ready() -> void:
	instance = self
	top_level = true
	rng.seed = 90107
	if not WildlifeKit.available():
		enabled = false
		return
	TerrainHeight.warm()
	OutskirtsSites.ensure()
	for s in OutskirtsSites.list:
		if AnimalSpecies.FARMS.has(s["id"]):
			var p: Vector3 = s["pos"]
			_farms.append(Vector2(p.x, p.z))
	if not Game.exploded.is_connected(_on_exploded):
		Game.exploded.connect(_on_exploded)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func set_quality(level: int) -> void:
	quality = clampi(level, 0, 2)


func cap_of(cls: StringName) -> int:
	var n: int = CAPS[cls][quality]
	return LowPlus.scaled(n, 0.7, 2) if LowPlus.on() else n


## Live bodies (not counting the dying).
func count_of(cls: StringName) -> int:
	var n := 0
	for c in critters:
		if c.cls == cls and not c.dying:
			n += 1
	return n


# --- main loop ------------------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not enabled:
		return
	var active := force_active or Game.is_playing()
	if not active:
		_active_prev = false
		return
	var dt := minf(delta, 0.1)
	_t += dt
	_focus_hero(dt)
	if not _hero.is_finite():
		return
	if not _active_prev:
		_active_prev = true
		_first_fill = 1.2
	_hook_player()
	_first_fill = maxf(0.0, _first_fill - dt)
	_spawn_t -= dt
	if _spawn_t <= 0.0 and director:
		_spawn_t = SPAWN_INTERVAL if _first_fill <= 0.0 else 0.05
		_try_spawn()
	_hz_t -= dt
	if _hz_t <= 0.0:
		_hz_t = 0.2
		_tick_hazards()
	_hunters.clear()
	for c in critters:
		if c.state == &"hunt" and not c.dying:
			_hunters.append(c)
	var despawn_r: float = float(_ring()[1]) * DESPAWN_K
	var i := critters.size() - 1
	while i >= 0:
		var c := critters[i]
		i -= 1
		var d2 := Vector2(c.position.x, c.position.z).distance_to(_hero2)
		if d2 > despawn_r * (1.7 if c.cls == AnimalSpecies.AIR else 1.0) or (c.stuck > 6.0):
			_release(c)
			continue
		c.set_lod(2 if d2 > HIDE_RANGE else (1 if d2 > ANIM_RANGE else 0))
		if c.dying:
			_tick_dying(c, dt)
			continue
		match c.cls:
			AnimalSpecies.LAND:
				_tick_land(c, dt, d2)
			AnimalSpecies.SMALL:
				_tick_small(c, dt, d2)
			AnimalSpecies.AIR:
				_tick_air(c, dt, d2)
			AnimalSpecies.WATER:
				_tick_water(c, dt, d2)
		c.tick_visual(dt)
		c.apply_pose()
		_voice(c, dt, d2)
	_enforce_caps()


func _ring() -> Array:
	return RING[quality]


func _focus_hero(dt: float) -> void:
	var p := Game.player as Node3D
	var f := Vector3.INF
	if is_instance_valid(p):
		f = p.global_position
	else:
		var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
		if cam != null:
			f = cam.global_position
	if f.is_finite() and _hero_prev.is_finite() and dt > 0.0:
		var v := (f - _hero_prev) / dt
		v.y = 0.0
		_hero_speed = lerpf(_hero_speed, minf(v.length(), 60.0), clampf(dt * 5.0, 0.0, 1.0))
	_hero_prev = f
	_hero = f
	_hero2 = Vector2(f.x, f.z) if f.is_finite() else Vector2.ZERO


func _hook_player() -> void:
	var pl := Game.player
	if pl == _hooked or not is_instance_valid(pl):
		return
	_hooked = pl
	if pl.has_signal(&"fired") and not pl.is_connected(&"fired", _on_player_fired):
		pl.connect(&"fired", _on_player_fired)


func _on_player_fired() -> void:
	if not is_instance_valid(_hooked) or not Game.is_playing():
		return
	scare_all((_hooked as Node3D).global_position, 78.0)


# --- spawning -------------------------------------------------------------------------------------------------------------------------------

func _try_spawn() -> void:
	var order: Array = []
	for cls in [AnimalSpecies.LAND, AnimalSpecies.AIR, AnimalSpecies.WATER, AnimalSpecies.SMALL]:
		var cap := cap_of(cls)
		var n := count_of(cls)
		if n < cap:
			order.append([float(n) / float(cap) + rng.randf() * 0.15, cls])
	order.sort_custom(func(a, b): return a[0] < b[0])
	for e in order:
		if _spawn_for_class(e[1]):
			return


func _spawn_for_class(cls: StringName) -> bool:
	var tries := 5 if cls != AnimalSpecies.WATER else 8
	for t in tries:
		var p := _ring_point(cls)
		if not p.is_finite():
			continue
		var id := _choose_species(cls, p)
		if id == &"":
			continue
		var room := cap_of(cls) - count_of(cls)
		var spec := AnimalSpecies.data(id)
		var g: Array = spec["group"]
		var n := mini(rng.randi_range(int(g[0]), int(g[1])), room)
		if n <= 0:
			return false
		if spawn_group(id, p, n) > 0:
			return true
	return false


## A point of the ring around the hero for the class: out of the camera view (unless the first fill or `_first_fill`), outside the city's streets.
func _ring_point(cls: StringName) -> Vector3:
	var ring := _ring()
	var rmin: float = ring[0]
	var rmax: float = ring[1]
	if cls == AnimalSpecies.SMALL:
		rmin = 14.0
		rmax = 52.0
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var fwd := Vector2(0.0, -1.0)
	if cam != null:
		var f3 := -cam.global_basis.z
		fwd = Vector2(f3.x, f3.z).normalized() if Vector2(f3.x, f3.z).length() > 0.05 else fwd
	var a := atan2(fwd.y, fwd.x) + rng.randf_range(-1.4, 1.4) if rng.randf() < 0.6 else rng.randf() * TAU
	var r := lerpf(rmin, rmax, sqrt(rng.randf()))
	var x := _hero.x + cos(a) * r
	var z := _hero.z + sin(a) * r
	if maxf(absf(x), absf(z)) < AnimalSpecies.CITY_SKIRT or maxf(absf(x), absf(z)) > TerrainHeight.WORLD_HALF - 60.0:
		return Vector3.INF
	var h := TerrainHeight.height_at(x, z)
	var p := Vector3(x, h, z)
	if cam != null and _first_fill <= 0.0 and r < rmax * 0.92 and cam.is_position_in_frustum(p + Vector3(0.0, 1.0, 0.0)):
		return Vector3.INF
	return p


func _choose_species(cls: StringName, p: Vector3) -> StringName:
	var h := p.y
	var biome := TerrainBase.biome_at(p.x, p.z, h)
	var w := TerrainHeight.water_level_for(p.x, p.z, h)
	var depth := w - h if w != TerrainHeight.NO_WATER else 0.0
	var night := DayNight.night_now
	if cls == AnimalSpecies.WATER:
		if depth < 0.9:
			return &""
		var ocean := biome == TerrainBase.OCEAN and h < TerrainHeight.SEA_LEVEL - 1.0
		if ocean:
			var list := AnimalSpecies.weights(cls, TerrainBase.OCEAN, h, 0.0, night, 0.0, false)
			var id := AnimalSpecies.pick(list, rng.randf())
			if id == &"whale" and (depth < 10.0 or Vector2(p.x - _hero.x, p.z - _hero.z).length() < 60.0):
				return &"dolphin"
			if id == &"shark" and depth > 14.0:
				return &"dolphin"
			return id
		return &"fish" if depth > 1.0 and WaterLayout.surface_at(p.x, p.z) != TerrainHeight.NO_WATER else &""
	if depth > 0.45 and cls != AnimalSpecies.AIR:
		return &""
	var slope := TerrainHeight.slope_at(p.x, p.z)
	if cls == AnimalSpecies.LAND and slope > 1.0:
		return &""
	var shore := biome == TerrainBase.BEACH
	var list2 := AnimalSpecies.weights(cls, biome, h, slope, night, _farm_k(p), shore)
	return AnimalSpecies.pick(list2, rng.randf())


func _farm_k(p: Vector3) -> float:
	var best := 0.0
	for f in _farms:
		best = maxf(best, 1.0 - Vector2(p.x, p.z).distance_to(f) / AnimalSpecies.FARM_RADIUS)
	return clampf(best, 0.0, 1.0)


## Spawns `n` bodies of a species as one herd / flock / school around `pos` (ground height in y). Returns how many were placed.
func spawn_group(id: StringName, pos: Vector3, n: int) -> int:
	var spec := AnimalSpecies.data(id)
	if spec.is_empty() or n <= 0:
		return 0
	var cls: StringName = spec["cls"]
	var g := {"id": id, "cls": cls, "members": [], "center": Vector2(pos.x, pos.z), "home": Vector2(pos.x, pos.z), "timer": rng.randf_range(4.0, 14.0), "mode": &"graze"}
	var placed := 0
	var spread := 2.2 + 0.9 * float(n)
	if cls == AnimalSpecies.AIR:
		var orb: Array = spec["orbit"]
		var alt: Array = spec["alt"]
		g["r"] = rng.randf_range(float(orb[0]), float(orb[1]))
		g["dir"] = 1.0 if rng.randf() < 0.5 else -1.0
		g["ang"] = rng.randf() * TAU
		g["alt"] = rng.randf_range(float(alt[0]), float(alt[1]))
		g["omega"] = float(spec["speed"]) / g["r"]
		g["ground"] = pos.y
		var on_ground: bool = spec.get("perch", false) and TerrainBase.biome_at(pos.x, pos.z, pos.y) == TerrainBase.BEACH and rng.randf() < 0.55
		g["mode"] = &"perch" if on_ground else &"fly"
		# the orbit is centred so that the first bird sits at the spawn point
		var a0: float = g["ang"]
		g["center"] = Vector2(pos.x - cos(a0) * g["r"], pos.z - sin(a0) * g["r"]) if not on_ground else Vector2(pos.x, pos.z)
	elif cls == AnimalSpecies.WATER:
		g["heading"] = rng.randf() * TAU
		g["turn_t"] = rng.randf_range(3.0, 9.0)
	for i in n:
		var c := _acquire(id)
		if c == null:
			break
		var off := Vector2.ZERO
		if cls == AnimalSpecies.LAND or cls == AnimalSpecies.SMALL:
			var tries := 0
			while tries < 6:
				var a := rng.randf() * TAU
				var r := rng.randf_range(0.0, spread)
				off = Vector2(cos(a), sin(a)) * r
				if _land_ok(pos.x + off.x, pos.z + off.y):
					break
				off = Vector2.ZERO
				tries += 1
		c.group = g
		(g["members"] as Array).append(c)
		c.slot = off
		var x := pos.x + off.x
		var z := pos.z + off.y
		c.position = Vector3(x, TerrainHeight.height_at(x, z), z)
		c.heading = rng.randf() * TAU
		c.ground = c.position.y
		match cls:
			AnimalSpecies.AIR:
				c.slot = Vector2((float(i) - float(n) * 0.5) * 0.16 + rng.randf_range(-0.05, 0.05), rng.randf_range(-3.5, 3.5))
				c.phase = rng.randf() * TAU
				c.state = &"perch" if g["mode"] == &"perch" else &"orbit"
				if g["mode"] == &"perch":
					c.slot = Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
					c.position = Vector3(pos.x + c.slot.x, TerrainHeight.height_at(pos.x + c.slot.x, pos.z + c.slot.y) + 0.02, pos.z + c.slot.y)
				else:
					c.position.y = pos.y + g["alt"]
			AnimalSpecies.WATER:
				c.slot = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * (3.0 + 1.1 * float(n)) * (0.4 if id == &"fish" else 1.0)
				c.phase = rng.randf() * TAU
				c.state = &"swim"
				var w := TerrainHeight.water_level_for(x, z, c.position.y)
				c.water_y = w
				c.position.y = (w if w != TerrainHeight.NO_WATER else TerrainHeight.SEA_LEVEL) - float(spec.get("depth", 0.4))
				c.heading = g["heading"]
			_:
				c.state = &"idle"
				c.timer = rng.randf_range(0.5, 5.0)
		c.apply_pose()
		placed += 1
	if placed == 0:
		return 0
	spawned_total += placed
	return placed


func _acquire(id: StringName) -> Critter:
	var pool: Array = _free.get(id, [])
	var c: Critter = null
	if not pool.is_empty():
		c = pool.pop_back()
	else:
		c = Critter.new()
		c.name = String(id)
		if not c.setup(id, AnimalSpecies.data(id)):
			c.free()
			return null
		add_child(c)
	c.revive(rng)
	c.group = {}
	critters.append(c)
	return c


func _release(c: Critter) -> void:
	critters.erase(c)
	if c.group.has("members"):
		(c.group["members"] as Array).erase(c)
	c.group = {}
	c.prey = null
	c.visible = false
	c.set_lod(2)
	if c.ap != null:
		c.ap.speed_scale = 0.0
	if not _free.has(c.id):
		_free[c.id] = []
	(_free[c.id] as Array).append(c)


## Removes every body (tests, teleports, tier changes).
func clear() -> void:
	for c: Critter in critters.duplicate():
		_release(c)


func _enforce_caps() -> void:
	for cls in CAPS:
		var over := count_of(cls) - cap_of(cls) - 2
		if over <= 0:
			continue
		var far: Critter = null
		var far_d := -1.0
		for c in critters:
			if c.cls == cls and not c.dying:
				var d := Vector2(c.position.x, c.position.z).distance_to(_hero2)
				if d > far_d:
					far_d = d
					far = c
		if far != null:
			_release(far)


## Builds a whole neighbourhood around `pos` at once (tests and captures: no waiting for the director, no camera rule).
func settle(pos: Vector3, rounds := 40) -> void:
	force_active = true
	_hero = pos
	_hero2 = Vector2(pos.x, pos.z)
	_hero_prev = pos
	_first_fill = 5.0
	for i in rounds:
		_try_spawn()


# --- land ------------------------------------------------------------------------------------------------------------------------------------

func _land_ok(x: float, z: float) -> bool:
	var h := TerrainHeight.height_at(x, z)
	var w := TerrainHeight.water_level_for(x, z, h)
	return w == TerrainHeight.NO_WATER or w - h < 0.4


func _tick_land(c: Critter, dt: float, dh: float) -> void:
	var sp := c.spec
	var pos2 := Vector2(c.position.x, c.position.z)
	c.timer -= dt
	c.cool = maxf(0.0, c.cool - dt)
	c.bite_t = maxf(0.0, c.bite_t - dt)
	c.think_t -= dt
	if c.think_t <= 0.0:
		c.think_t = 0.2 + rng.randf() * 0.1 + (0.4 if dh > ANIM_RANGE else 0.0)
		_think_land(c, pos2, dh)
	var moving := false
	match c.state:
		&"idle", &"graze":
			c.speed = move_toward(c.speed, 0.0, 6.0 * dt)
			c.play(&"idle", 1.0)
			if c.timer <= 0.0:
				_next_land_state(c, pos2, dh)
		&"sleep":
			c.speed = 0.0
			c.play(&"idle", 0.15)
			if DayNight.night_now < 0.5 or dh < 11.0:
				c.asleep = false
				c.state = &"idle"
				c.timer = rng.randf_range(0.5, 2.0)
		&"walk":
			var to := c.target - pos2
			var d := to.length()
			if d < 1.2 or c.timer <= 0.0:
				c.state = &"idle"
				c.timer = rng.randf_range(2.0, 8.0)
			else:
				_steer(c, to / d, float(sp["walk"]), dt, 3.5)
				c.play(&"walk", clampf(c.speed / float(sp["stride_walk"]), 0.2, 2.2))
				moving = true
		&"flee":
			var to2 := c.target - pos2
			var d2 := to2.length()
			if d2 < 2.0 or c.timer <= 0.0:
				c.state = &"idle"
				c.timer = rng.randf_range(2.0, 5.0)
			else:
				_steer(c, to2 / d2, float(sp["run"]), dt, 8.0)
				c.play(&"run", clampf(c.speed / float(sp["stride_run"]), 0.4, 2.4))
				moving = true
		&"hunt":
			if not is_instance_valid(c.prey) or c.prey.dying or not c.prey.alive or c.timer <= 0.0:
				c.prey = null
				c.state = &"idle"
				c.cool = 18.0
				c.timer = 1.0
			else:
				var pp := Vector2(c.prey.position.x, c.prey.position.z)
				var to3 := pp - pos2
				var d3 := to3.length()
				if d3 < 1.7:
					kill(c.prey, false)
					c.prey = null
					c.state = &"eat"
					c.timer = 6.0
					c.cool = 45.0
				else:
					_steer(c, to3 / d3, float(sp["run"]) * 1.06, dt, 8.0)
					c.play(&"run", clampf(c.speed / float(sp["stride_run"]), 0.4, 2.4))
					moving = true
		&"eat":
			c.speed = move_toward(c.speed, 0.0, 8.0 * dt)
			c.play(&"idle", 0.7)
			if c.timer <= 0.0:
				c.state = &"idle"
				c.timer = 2.0
		&"chase":
			var to4 := _hero2 - pos2
			var d4 := to4.length()
			if c.timer <= 0.0 or d4 > 55.0:
				c.aggro = false
				c.state = &"idle"
				c.timer = 3.0
			elif d4 < 1.9:
				c.speed = move_toward(c.speed, 0.0, 10.0 * dt)
				c.play(&"idle", 1.0)
				if c.bite_t <= 0.0:
					c.bite_t = 1.3
					_bite_hero(c)
			else:
				_steer(c, to4 / d4, float(sp["run"]) * 0.95, dt, 8.0)
				c.play(&"run", clampf(c.speed / float(sp["stride_run"]), 0.4, 2.4))
				moving = true
	_ground_step(c, dt, moving or c.speed > 0.2, dh)


func _next_land_state(c: Critter, pos2: Vector2, dh: float) -> void:
	var sp := c.spec
	var night := DayNight.night_now
	if bool(sp.get("sleeps", false)) and night > 0.78 and dh > 20.0:
		c.asleep = true
		c.state = &"sleep"
		c.timer = rng.randf_range(25.0, 50.0)
		return
	if sp["role"] == AnimalSpecies.PREDATOR and c.cool <= 0.0 and rng.randf() < 0.5:
		var prey := _find_prey(c, pos2, 58.0)
		if prey != null:
			c.prey = prey
			c.state = &"hunt"
			c.timer = 16.0
			_alarm_prey(prey, pos2)
			return
	if rng.randf() < 0.6:
		var cen: Vector2 = c.group.get("center", pos2)
		var a := rng.randf() * TAU
		var r := rng.randf_range(3.0, 20.0)
		c.target = cen + Vector2(cos(a), sin(a)) * r + c.slot * 0.4
		var home: Vector2 = c.group.get("home", cen)
		if c.target.distance_to(home) > 42.0:                          # a herd keeps to its range: it drifts, it does not leave
			c.target = home + (c.target - home).normalized() * 42.0
		c.state = &"walk"
		c.timer = rng.randf_range(6.0, 16.0)
		# the herd drifts: its centre follows the first walker (so a herd moves as a herd)
		if rng.randf() < 0.35 and c.group.has("center"):
			c.group["center"] = (c.group["center"] as Vector2).lerp(c.target, 0.6)
	else:
		c.state = &"graze" if rng.randf() < 0.6 else &"idle"
		c.timer = rng.randf_range(3.0, 9.0)


func _find_prey(pred: Critter, pos2: Vector2, reach: float) -> Critter:
	var best: Critter = null
	var best_d := reach
	for o in critters:
		if o.cls != AnimalSpecies.LAND or o.spec["role"] != AnimalSpecies.PREY or o.dying or o.state == &"flee":
			continue
		var d := pos2.distance_to(Vector2(o.position.x, o.position.z))
		if d < best_d:
			best_d = d
			best = o
	return best


func _alarm_prey(prey: Critter, from: Vector2) -> void:
	_start_flee(prey, from)


func _think_land(c: Critter, pos2: Vector2, dh: float) -> void:
	var sp := c.spec
	if c.state == &"flee" or c.state == &"hunt" or c.state == &"chase":
		return
	var flee_r := float(sp["flee"]) * (1.0 + clampf(_hero_speed / 9.0, 0.0, 0.8)) * (0.55 if c.asleep else 1.0)
	if c.aggro and dh < 45.0:
		c.asleep = false
		c.state = &"chase"
		c.timer = 14.0
		return
	if sp["role"] == AnimalSpecies.PREDATOR and not c.aggro:
		flee_r = minf(flee_r, 9.0)                                       # a pack does not run from a person standing 30 m away
	if dh < flee_r:
		_start_flee(c, _hero2)
		return
	if sp["role"] == AnimalSpecies.PREY:
		for h in _hunters:
			if h != c and Vector2(h.position.x, h.position.z).distance_to(pos2) < 30.0:
				_start_flee(c, Vector2(h.position.x, h.position.z))
				return
	for d in _danger:
		if pos2.distance_to(d[0]) < float(d[1]):
			_start_flee(c, d[0])
			return


## Runs away from `from`; the herd runs with it.
func _start_flee(c: Critter, from: Vector2, propagate := true) -> void:
	if c.dying or c.state == &"flee":
		return
	var pos2 := Vector2(c.position.x, c.position.z)
	var dir := (pos2 - from)
	dir = dir.normalized() if dir.length() > 0.05 else Vector2.from_angle(rng.randf() * TAU)
	dir = dir.rotated(rng.randf_range(-0.5, 0.5))
	c.asleep = false
	c.state = &"flee"
	c.timer = rng.randf_range(5.0, 9.0)
	c.target = pos2 + dir * rng.randf_range(40.0, 70.0)
	if c.spec.get("sound", &"") != &"" and rng.randf() < 0.35:
		c.voice_t = minf(c.voice_t, 0.1)
	if propagate and c.group.has("members"):
		for m: Critter in c.group["members"]:
			if m != c and not m.dying and m.state != &"flee" and Vector2(m.position.x, m.position.z).distance_to(pos2) < FEAR_PROPAGATE:
				m.think_t = rng.randf_range(0.0, 0.35)
				_start_flee(m, from, false)


## Steering: turn toward `dir`, accelerate to `spd`, walk. Returns nothing; the ground is sampled separately (`_ground_step`).
func _steer(c: Critter, dir: Vector2, spd: float, dt: float, accel: float) -> void:
	var want := atan2(-dir.x, -dir.y)
	c.heading = lerp_angle(c.heading, want, clampf(dt * TAU_TURN * (1.4 if spd > 4.0 else 1.0), 0.0, 1.0))
	var align := clampf(1.0 - absf(angle_difference(c.heading, want)) / 1.2, 0.15, 1.0)
	c.speed = move_toward(c.speed, spd * align, accel * dt)
	var fwd := Vector2(-sin(c.heading), -cos(c.heading))
	c.position.x += fwd.x * c.speed * dt
	c.position.z += fwd.y * c.speed * dt


## Ground contact at a low rate: height, water, pitch, a look ahead that turns the animal away from deep water and cliffs.
func _ground_step(c: Critter, dt: float, moving: bool, dh: float) -> void:
	c.sample_t -= dt
	if c.sample_t <= 0.0:
		c.sample_t = (0.17 if moving else 0.9) * (3.0 if dh > ANIM_RANGE else 1.0)
		var x := c.position.x
		var z := c.position.z
		var h := TerrainHeight.height_at(x, z)
		var w := TerrainHeight.water_level_for(x, z, h)
		c.ground = h
		c.water_y = w
		if w != TerrainHeight.NO_WATER and w - h > 0.9:
			c.stuck += 1.0                                              # in deep water: it was pushed or spawned there; it gets out or goes
		elif c.stuck > 0.0:
			c.stuck = maxf(0.0, c.stuck - 0.5)
		if moving:
			var fwd := Vector2(-sin(c.heading), -cos(c.heading))
			var h2 := TerrainHeight.height_at(x + fwd.x * 1.1, z + fwd.y * 1.1)
			c.pitch = lerpf(c.pitch, clampf(atan2(h2 - h, 1.1), -0.5, 0.5), 0.6)
			var ax := x + fwd.x * (1.5 + c.speed * 0.5)
			var az := z + fwd.y * (1.5 + c.speed * 0.5)
			var ah := TerrainHeight.height_at(ax, az)
			var aw := TerrainHeight.water_level_for(ax, az, ah)
			var limit := 2.1 if c.spec.get("climb", false) else 1.1
			if (aw != TerrainHeight.NO_WATER and aw - ah > 0.45) or absf(ah - h) / (1.5 + c.speed * 0.5) > limit:
				c.stuck += 0.3
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var back := (Vector2(x, z) - Vector2(ax, az)).normalized().rotated(side * rng.randf_range(0.5, 1.4))
				c.target = Vector2(x, z) + back * 22.0
				c.heading += side * 0.8
				if c.state == &"flee" or c.state == &"hunt" or c.state == &"chase":
					c.timer = minf(c.timer, 2.5)
		else:
			c.pitch = lerpf(c.pitch, 0.0, 0.5)
	c.position.y = lerpf(c.position.y, c.ground, clampf(dt * 9.0, 0.0, 1.0)) if c.cls != AnimalSpecies.AIR else c.position.y


func _bite_hero(c: Critter) -> void:
	var p := Game.player
	if is_instance_valid(p) and p.has_method(&"damage") and Game.is_playing():
		p.call(&"damage", TestMode.damage(float(c.spec.get("bite", 5.0))), c.global_position)
		Sfx.play_at(&"hit", c.global_position, -8.0, 0.8)


# --- small (lizards) -----------------------------------------------------------------------------------------------------------------------

func _tick_small(c: Critter, dt: float, dh: float) -> void:
	var pos2 := Vector2(c.position.x, c.position.z)
	c.timer -= dt
	c.think_t -= dt
	if DayNight.night_now > 0.75:
		c.stuck = 99.0                                                  # they hide for the night
		return
	if c.think_t <= 0.0:
		c.think_t = 0.25
		if c.state != &"flee" and dh < float(c.spec["flee"]):
			c.state = &"flee"
			c.timer = 1.6
			var away := (pos2 - _hero2).normalized()
			c.heading = atan2(-away.x, -away.y) + rng.randf_range(-0.6, 0.6)
			c.mat.set_shader_parameter(&"wiggle_rate", 26.0)
	match c.state:
		&"idle":
			c.speed = 0.0
			if c.timer <= 0.0:
				c.state = &"dart"
				c.timer = rng.randf_range(0.5, 1.2)
				c.heading += rng.randf_range(-1.4, 1.4)
				c.mat.set_shader_parameter(&"wiggle_rate", 18.0)
		&"dart":
			c.speed = float(c.spec["walk"]) * 2.2
			if c.timer <= 0.0:
				c.state = &"idle"
				c.timer = rng.randf_range(1.5, 5.0)
				c.speed = 0.0
		&"flee":
			c.speed = float(c.spec["run"])
			if c.timer <= 0.0:
				c.state = &"idle"
				c.timer = rng.randf_range(2.0, 5.0)
				c.speed = 0.0
	if c.speed > 0.0:
		var fwd := Vector2(-sin(c.heading), -cos(c.heading))
		c.position.x += fwd.x * c.speed * dt
		c.position.z += fwd.y * c.speed * dt
	c.mat.set_shader_parameter(&"wiggle", 0.012 if c.speed > 0.0 else 0.0)
	c.sample_t -= dt
	if c.sample_t <= 0.0:
		c.sample_t = 0.2
		var h := TerrainHeight.height_at(c.position.x, c.position.z)
		var w := TerrainHeight.water_level_for(c.position.x, c.position.z, h)
		if w != TerrainHeight.NO_WATER and w - h > 0.2:
			c.heading += PI
			c.stuck += 0.5
		c.ground = h
	c.position.y = lerpf(c.position.y, c.ground, clampf(dt * 12.0, 0.0, 1.0))


# --- air -------------------------------------------------------------------------------------------------------------------------------------

func _tick_air(c: Critter, dt: float, dh: float) -> void:
	var g := c.group
	var sp := c.spec
	if DayNight.night_now > 0.8 and bool(sp.get("day_only", false)) and c.state != &"flee":
		_scatter_bird(c, _hero2 + Vector2.from_angle(rng.randf() * TAU) * 30.0)       # the day birds head home at dusk
	match c.state:
		&"orbit":
			if not g.has("r"):
				return
			if not g.has("tick") or g["tick"] != Engine.get_process_frames():
				g["tick"] = Engine.get_process_frames()
				g["ang"] = float(g["ang"]) + float(g["dir"]) * float(g["omega"]) * dt
				g["ground_t"] = float(g.get("ground_t", 0.0)) - dt
				if g["ground_t"] <= 0.0:
					g["ground_t"] = 1.2
					var cc: Vector2 = g["center"]
					g["ground"] = maxf(TerrainHeight.height_at(cc.x, cc.y), TerrainHeight.SEA_LEVEL)
			var a: float = float(g["ang"]) + c.slot.x
			var rr: float = float(g["r"]) + c.slot.y
			var cen: Vector2 = g["center"]
			c.phase += dt * 2.3
			var nx := cen.x + cos(a) * rr
			var nz := cen.y + sin(a) * rr
			var tang := Vector2(-sin(a), cos(a)) * float(g["dir"])
			var want := atan2(-tang.x, -tang.y)
			c.turn = angle_difference(c.heading, want)
			c.heading = want
			c.bank = lerpf(c.bank, clampf(-float(g["dir"]) * float(sp["speed"]) / maxf(rr, 8.0) * 0.9, -0.7, 0.7), clampf(dt * 3.0, 0.0, 1.0))
			c.position = Vector3(nx, float(g["ground"]) + float(g["alt"]) + c.slot.y * 0.5 + sin(c.phase) * 0.7, nz)
			c.pitch = lerpf(c.pitch, cos(c.phase) * 0.12, clampf(dt * 2.0, 0.0, 1.0))
			c.speed = float(sp["speed"])
			c.play(&"fly", float(sp["flap"]) * (0.8 + 0.2 * sin(c.phase * 0.7 + c.slot.x * 9.0)))
		&"perch":
			c.play(&"idle", 0.0)
			c.speed = 0.0
			c.think_t -= dt
			if c.think_t <= 0.0:
				c.think_t = 0.25 + rng.randf() * 0.1
				if dh < float(sp["flee"]) or _hero_speed > 6.0 and dh < float(sp["flee"]) * 1.6:
					_scatter_flock(g, _hero2)
			c.sample_t -= dt
			if c.sample_t <= 0.0:
				c.sample_t = 1.0
				c.ground = TerrainHeight.height_at(c.position.x, c.position.z)
			c.position.y = c.ground + 0.04
			c.pitch = 0.0
			c.bank = 0.0
		&"flee":
			c.timer -= dt
			var fwd := Vector2(-sin(c.heading), -cos(c.heading))
			c.speed = move_toward(c.speed, float(sp["speed"]) * 1.7, 10.0 * dt)
			c.position.x += fwd.x * c.speed * dt
			c.position.z += fwd.y * c.speed * dt
			c.position.y += (5.5 if c.position.y < c.ground + 28.0 else 0.5) * dt
			c.pitch = lerpf(c.pitch, 0.35, clampf(dt * 3.0, 0.0, 1.0))
			c.bank = lerpf(c.bank, 0.0, clampf(dt * 3.0, 0.0, 1.0))
			c.play(&"fly", float(sp["flap"]) * 1.9)
			if c.timer <= 0.0:
				c.stuck = 99.0


## Everybody of a flock leaves: climbs away from `from`.
func _scatter_flock(g: Dictionary, from: Vector2) -> void:
	for m: Critter in g.get("members", []):
		if not m.dying:
			_scatter_bird(m, from)


func _scatter_bird(c: Critter, from: Vector2) -> void:
	if c.state == &"flee" or c.dying:
		return
	var pos2 := Vector2(c.position.x, c.position.z)
	var away := pos2 - from
	away = away.normalized() if away.length() > 0.1 else Vector2.from_angle(rng.randf() * TAU)
	away = away.rotated(rng.randf_range(-0.7, 0.7))
	c.state = &"flee"
	c.timer = rng.randf_range(7.0, 10.0)
	c.heading = atan2(-away.x, -away.y)
	c.ground = maxf(c.ground, TerrainHeight.height_at(c.position.x, c.position.z))
	c.speed = float(c.spec["speed"])


# --- water -----------------------------------------------------------------------------------------------------------------------------------

func _tick_water(c: Critter, dt: float, dh: float) -> void:
	var g := c.group
	var sp := c.spec
	var pos2 := Vector2(c.position.x, c.position.z)
	c.sample_t -= dt
	c.timer -= dt
	var fleeing := c.state == &"dart"
	var spd := float(sp["speed"]) * (3.2 if fleeing else 1.0)
	if fleeing and c.timer <= 0.0:
		c.state = &"swim"
	# the school's heading wanders; every body steers to the school centre + its slot
	if not g.has("tick") or g["tick"] != Engine.get_process_frames():
		g["tick"] = Engine.get_process_frames()
		g["turn_t"] = float(g.get("turn_t", 5.0)) - dt
		if g["turn_t"] <= 0.0:
			g["turn_t"] = rng.randf_range(3.5, 10.0)
			g["heading"] = float(g.get("heading", 0.0)) + rng.randf_range(-0.9, 0.9)
		var cen: Vector2 = g["center"]
		var gh: float = g["heading"]
		var gs := float(sp["speed"]) * (0.7 if sp.get("porpoise", false) else 0.8)
		g["center"] = cen + Vector2(-sin(gh), -cos(gh)) * gs * dt
	var cen2: Vector2 = g["center"]
	var gh2: float = g["heading"]
	var slot_w := c.slot.rotated(-gh2)
	var goal := cen2 + slot_w
	var to := goal - pos2
	var d := to.length()
	if fleeing:
		var away := (pos2 - _hero2).normalized()
		to = away * 10.0
		d = 10.0
	var want := atan2(-to.x, -to.y) if d > 0.4 else gh2
	c.heading = lerp_angle(c.heading, want, clampf(dt * 3.0, 0.0, 1.0))
	c.speed = move_toward(c.speed, minf(spd * (0.5 + clampf(d / 6.0, 0.0, 1.0) * 0.8), spd * 1.5), 3.0 * dt)
	var fwd := Vector2(-sin(c.heading), -cos(c.heading))
	c.position.x += fwd.x * c.speed * dt
	c.position.z += fwd.y * c.speed * dt
	c.phase += dt * (float(sp.get("swim_flap", 2.0)) * (1.0 + (1.6 if fleeing else 0.0)))
	if c.sample_t <= 0.0:
		c.sample_t = 0.16 * (3.0 if dh > ANIM_RANGE else 1.0)
		var x := c.position.x
		var z := c.position.z
		var h := TerrainHeight.height_at(x, z)
		var w := TerrainHeight.water_level_for(x, z, h)
		c.ground = h
		c.water_y = w
		var ax := x + fwd.x * (4.0 + c.speed * 1.5)
		var az := z + fwd.y * (4.0 + c.speed * 1.5)
		var ah := TerrainHeight.height_at(ax, az)
		var aw := TerrainHeight.water_level_for(ax, az, ah)
		if aw == TerrainHeight.NO_WATER or aw - ah < 0.8:
			# the shore or a shallow ahead: the whole school turns back
			g["heading"] = float(g["heading"]) + PI * rng.randf_range(0.7, 1.3)
			g["turn_t"] = 6.0
			c.stuck += 0.4
		elif c.stuck > 0.0:
			c.stuck = maxf(0.0, c.stuck - 0.2)
		if w == TerrainHeight.NO_WATER or w - h < 0.5:
			c.stuck += 1.0
	if c.water_y == TerrainHeight.NO_WATER:
		c.water_y = TerrainHeight.SEA_LEVEL
	var surf := c.water_y
	var depth := float(sp.get("depth", 0.4))
	var y := surf - depth
	var arc := 0.0
	if sp.get("porpoise", false):
		var s := sin(c.phase + c.slot.x * 0.4)
		arc = pow(maxf(s, 0.0), 0.8) * 1.5
		y = surf - 0.55 + arc * 1.25
		c.pitch = lerpf(c.pitch, clampf(cos(c.phase + c.slot.x * 0.4) * 0.8, -0.7, 0.7) * (1.0 if arc > 0.0 else 0.4), clampf(dt * 6.0, 0.0, 1.0))
		if arc > 0.2 and not c.get_meta(&"splash", false):
			c.set_meta(&"splash", true)
			Sfx.play_at(&"water_splash", Vector3(c.position.x, surf, c.position.z), -12.0, 1.1)
		elif arc < 0.05:
			c.set_meta(&"splash", false)
	else:
		c.pitch = lerpf(c.pitch, 0.0, clampf(dt * 3.0, 0.0, 1.0))
		if c.id == &"shark" or c.id == &"whale":
			y += sin(c.phase * 0.5) * 0.18
	if fleeing and c.id == &"fish":
		y = surf - depth - 0.5
	c.position.y = lerpf(c.position.y, y, clampf(dt * 8.0, 0.0, 1.0)) if not sp.get("porpoise", false) else y
	c.bank = sin(c.phase * 0.5) * 0.05
	c.play(&"swim", clampf(0.6 + c.speed * 0.5, 0.6, 3.0))
	if not fleeing and sp["flee"] > 0.0 and dh < float(sp["flee"]):
		_dart_school(g, _hero2)


func _dart_school(g: Dictionary, from: Vector2) -> void:
	for m: Critter in g.get("members", []):
		if not m.dying:
			m.state = &"dart"
			m.timer = rng.randf_range(2.0, 3.5)
	g["heading"] = atan2(-(float((g["center"] as Vector2).x) - from.x), -(float((g["center"] as Vector2).y) - from.y))


# --- hits, damage, death ---------------------------------------------------------------------------------------------------------------------

## A ray against the animals (the same call shape as AmbientCity.civilian_ray): {c, t, head} for the nearest body hit within `max_t`, {} for none.
func ray(origin: Vector3, dir: Vector3, max_t: float) -> Dictionary:
	var best := max_t
	var hit: Critter = null
	for c in critters:
		if c.dying or c.lod >= 2:
			continue
		var centre := c.global_position + Vector3(0.0, float(c.spec["mid"]) * c.scale_k, 0.0)
		var r := float(c.spec["hit_r"]) * c.scale_k
		var oc := origin - centre
		var b := oc.dot(dir)
		var cq := oc.dot(oc) - r * r
		var disc := b * b - cq
		if disc < 0.0:
			continue
		var t := -b - sqrt(disc)
		if t < 0.0:
			t = -b + sqrt(disc)
		if t >= 0.0 and t < best:
			best = t
			hit = c
	if hit == null:
		return {}
	return {"c": hit, "t": best, "head": false}


## Damage from the hero's weapon. True when it killed.
func hurt(c: Critter, amount: float, by_hero := true, from := Vector3.ZERO) -> bool:
	if c.dying or amount <= 0.0:
		return false
	c.hp -= amount
	c.flash()
	var pos2 := Vector2(c.position.x, c.position.z)
	if c.hp <= 0.0:
		kill(c, by_hero)
		return true
	# a hurt animal reacts: prey runs (the herd with it), a predator or a boar turns on the hero
	if by_hero:
		if bool(c.spec.get("aggro", false)):
			c.aggro = true
			c.asleep = false
			c.state = &"chase"
			c.timer = 14.0
		elif c.cls == AnimalSpecies.LAND or c.cls == AnimalSpecies.SMALL:
			_start_flee(c, Vector2(from.x, from.z) if from != Vector3.ZERO else _hero2)
		elif c.cls == AnimalSpecies.AIR:
			_scatter_flock(c.group, pos2)
		elif c.cls == AnimalSpecies.WATER:
			_dart_school(c.group, _hero2)
	return false


## The quantum-dust death: the body dissolves (shader), a burst of cold light, a sound, the bounty.
func kill(c: Critter, by_hero := true) -> void:
	if c.dying:
		return
	c.dying = true
	c.alive = false
	c.state = &"dead"
	c.timer = DISSOLVE_TIME
	c.speed = 0.0
	c.hp = 0.0
	if c.ap != null:
		c.ap.speed_scale = 0.0
	var at := c.global_position + Vector3(0.0, maxf(float(c.spec["mid"]), 0.3) * c.scale_k, 0.0)
	var col := Color(0.35, 0.95, 1.0, 0.9) if by_hero else Color(0.75, 0.5, 1.0, 0.9)
	FX.burst(at, col, 16, 3.2, 0.9, -0.6, 0.9)
	FX.burst(at, Color(0.8, 0.9, 1.0, 0.8), 8, 1.6, 0.7, -1.2, 0.6)
	Sfx.play_at(&"civ_dissolve", at, -5.0)
	if c.group.has("members"):
		(c.group["members"] as Array).erase(c)
	if by_hero:
		var bounty := int(c.spec["bounty"])
		total_kills += 1
		stats_kills[c.id] = int(stats_kills.get(c.id, 0)) + 1
		if bounty > 0:
			bounty_total += bounty
			var pr = Game.progress
			if is_instance_valid(pr) and pr.has_method(&"add_credits"):
				pr.call(&"add_credits", bounty)
			Game.say("%s  +%d CR" % [c.spec["name"], bounty], 1.6)
		# the others of the herd, flock or school notice
		if c.cls == AnimalSpecies.LAND and c.group.has("members"):
			for m: Critter in c.group["members"]:
				_start_flee(m, Vector2(c.position.x, c.position.z), false)
		elif c.cls == AnimalSpecies.AIR and c.group.has("members"):
			_scatter_flock(c.group, Vector2(c.position.x, c.position.z))
		elif c.cls == AnimalSpecies.WATER and c.group.has("members"):
			_dart_school(c.group, Vector2(c.position.x, c.position.z))
	killed.emit(c.id, c.global_position, by_hero)


func _tick_dying(c: Critter, dt: float) -> void:
	c.timer -= dt
	c.set_dissolve(1.0 - clampf(c.timer / DISSOLVE_TIME, 0.0, 1.0))
	c.position.y += dt * 0.25
	if c.timer <= 0.0:
		c.stuck = 99.0                                                    # released by the loop's despawn rule on the next frame
		_release(c)


# --- hazards, scares, voices -----------------------------------------------------------------------------------------------------------------

## Gunfire, a bang or a car horn at `at`: everything within `r` metres reacts.
func scare_all(at: Vector3, r: float) -> int:
	var n := 0
	var a2 := Vector2(at.x, at.z)
	for c: Critter in critters.duplicate():
		if c.dying:
			continue
		var p2 := Vector2(c.position.x, c.position.z)
		var d := p2.distance_to(a2)
		match c.cls:
			AnimalSpecies.LAND, AnimalSpecies.SMALL:
				if d < r * (0.55 if c.spec["role"] == AnimalSpecies.PREDATOR else 1.0) and not c.aggro:
					_start_flee(c, a2, false)
					n += 1
			AnimalSpecies.AIR:
				if d < r * 0.9:
					_scatter_bird(c, a2)
					n += 1
			AnimalSpecies.WATER:
				if d < r * 0.3 and c.spec["flee"] > 0.0 and c.state != &"dart":
					c.state = &"dart"
					c.timer = 2.5
					n += 1
	return n


func _on_exploded(pos: Vector3, radius: float) -> void:
	if not enabled or not Game.is_playing() and not force_active:
		return
	for c: Critter in critters.duplicate():
		if c.dying:
			continue
		var d := c.global_position.distance_to(pos)
		if d < radius * 1.05 + float(c.spec["hit_r"]):
			hurt(c, BlastTable.animal_damage(pos, radius, d, 80.0 * (1.0 - 0.5 * d / maxf(radius, 1.0)) + 40.0), true, pos)
	scare_all(pos, radius * 5.0 + 55.0)


func _tick_hazards() -> void:
	_danger.clear()
	var hv := Vector2(_hero.x, _hero.z)
	for v in get_tree().get_nodes_in_group(&"vehicle"):
		if not is_instance_valid(v) or not (v is Node3D):
			continue
		var s = v.get(&"speed")
		if s == null:
			continue
		var sp := absf(float(s))
		var vp := (v as Node3D).global_position
		var v2 := Vector2(vp.x, vp.z)
		if sp < 4.5 or v2.distance_to(hv) > 150.0:
			continue
		_danger.append([v2, 8.0 + sp * 0.9, sp, v])
		for c: Critter in critters.duplicate():
			if c.dying or c.cls == AnimalSpecies.AIR or c.cls == AnimalSpecies.WATER:
				continue
			if sp > 6.0 and Vector2(c.position.x, c.position.z).distance_to(v2) < 2.4 and absf(c.position.y - vp.y) < 3.0:
				kill(c, true)                                          # run over: quantum dust, the bounty is the hero's


func _voice(c: Critter, dt: float, dh: float) -> void:
	c.voice_t -= dt
	if c.voice_t > 0.0:
		return
	var sp := c.spec
	var snd: StringName = sp.get("sound", &"")
	var night := DayNight.night_now
	var gap := float(sp.get("gap", 0.0))
	c.voice_t = (maxf(gap, 4.0) * rng.randf_range(0.7, 1.5)) * (1.0 - 0.5 * night if sp["role"] == AnimalSpecies.PREDATOR else 1.0)
	if snd == &"" or dh > 85.0 or _t < _voice_gate:
		return
	if bool(sp.get("day_only", false)) and night > 0.5:
		return
	if c.asleep:
		return
	_voice_gate = _t + 0.9
	var db := -6.0 - dh * 0.06
	Sfx.play_at(snd, c.global_position, db, rng.randf_range(0.92, 1.08))


# --- tests and the bot -----------------------------------------------------------------------------------------------------------------------

func stats() -> Dictionary:
	var by := {}
	var cls := {AnimalSpecies.LAND: 0, AnimalSpecies.AIR: 0, AnimalSpecies.WATER: 0, AnimalSpecies.SMALL: 0}
	var tris := 0
	for c in critters:
		by[c.id] = int(by.get(c.id, 0)) + 1
		if not c.dying:
			cls[c.cls] = int(cls[c.cls]) + 1
		if c.mesh != null and c.mesh.mesh != null:
			tris += c.mesh.mesh.get_surface_count()
	return {"active": critters.size(), "land": cls[AnimalSpecies.LAND], "air": cls[AnimalSpecies.AIR], "water": cls[AnimalSpecies.WATER], "small": cls[AnimalSpecies.SMALL],
		"by_species": by, "spawned": spawned_total, "kills": total_kills, "bounty": bounty_total, "pooled": _pool_size()}


func _pool_size() -> int:
	var n := 0
	for k in _free:
		n += (_free[k] as Array).size()
	return n


## Bodies within `r` metres (xz) of `center`.
func census(center: Vector3, r: float, cls: StringName = &"") -> Array[Critter]:
	var out: Array[Critter] = []
	for c in critters:
		if (cls == &"" or c.cls == cls) and Vector2(c.position.x - center.x, c.position.z - center.z).length() <= r:
			out.append(c)
	return out
