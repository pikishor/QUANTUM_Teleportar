class_name TestMode
extends RefCounted
## HACK / TEST MODE: the state of the cheat toggles and every action of the TEST MENU (scripts/ui/test_menu.gd), headless-testable (tests/test_testmode.gd).
## Available in debug builds and when the saved setting "test mode" (UiSettings.test_mode, or --test-mode) is on; release builds hide it entirely: every hook below is
## a single static-bool read that is false there.
## Hooks (one line each): Player.damage (god), PlayerWeapon.tick (infinite ammo), PlayerWeapon._hit_target and Game.explode (one-hit kills via `damage()`),
## Game.heat setter (no heat), Drone._physics_process (freeze).

static var forced := false              ## the saved setting / --test-mode: test mode in a release build too
static var god := false
static var infinite_ammo := false
static var one_hit := false
static var no_heat := false
static var freeze := false
static var quick_weapons := true        ## the 1-4 touch weapon buttons on the HUD while test mode is available
static var show_stats := false

const WEATHER := {"CLEAR": &"clear", "OVERCAST": &"overcast", "DRIZZLE": &"drizzle", "RAIN": &"rain", "STORM": &"storm", "FOG": &"fog"}
const ENEMIES: Array[StringName] = [&"sentinel", &"striker", &"heavy", &"operative", &"shield", &"flanker", &"sniper", &"brute", &"overseer"]
const VEHICLES: Array[StringName] = [&"sedan", &"sport", &"suv", &"taxi", &"wagon", &"van", &"truck", &"bike", &"hover", &"vael_patrol", &"bus", &"interceptor", &"ambulance", &"qbike"]
const CONTRACTS: Array[StringName] = [&"officer", &"hack", &"chase", &"courier", &"survive", &"drones", &"boss"]
const KILL := 1.0e6


static func available() -> bool:
	return forced or OS.is_debug_build()


## Test mode with the on-screen weapon buttons.
static func quick_buttons_on() -> bool:
	return available() and quick_weapons


static func reset_toggles() -> void:
	god = false
	infinite_ammo = false
	one_hit = false
	no_heat = false
	freeze = false
	show_stats = false


## Damage the player's weapons and explosions deal to an enemy: huge with one-hit kills.
static func damage(amount: float) -> float:
	return KILL if one_hit else amount


# --- helpers --------------------------------------------------------------------------------------------------------------------

static func _player() -> Player:
	return Game.player as Player if is_instance_valid(Game.player) else null


static func _crosshair_point(max_dist := 35.0) -> Vector3:
	var p := _player()
	if p == null:
		return Game.SPAWN
	var aim: Dictionary = p.get_aim()
	var o: Vector3 = aim["origin"]
	var hit: Vector3 = aim["hit"]
	var d := o.distance_to(hit)
	var pt := hit
	if d > max_dist:
		pt = o + ((hit - o) / maxf(d, 0.001)) * max_dist
	return PlayerUtil.safe_spot(Vector3(pt.x, maxf(pt.y, 0.0), pt.z), Game.world if is_instance_valid(Game.world) else null, p.get_world_3d().direct_space_state)


static func _say(text: String) -> String:
	Game.say(text, 1.6)
	return text


# --- toggles --------------------------------------------------------------------------------------------------------------------

static func toggle(id: StringName) -> bool:
	match id:
		&"god": god = not god
		&"ammo": infinite_ammo = not infinite_ammo
		&"onehit": one_hit = not one_hit
		&"noheat":
			no_heat = not no_heat
			if no_heat:
				Game.heat = 0.0
		&"freeze": freeze = not freeze
		&"stats": show_stats = not show_stats
		&"quick": quick_weapons = not quick_weapons
		_: return false
	return true


static func is_on(id: StringName) -> bool:
	match id:
		&"god": return god
		&"ammo": return infinite_ammo
		&"onehit": return one_hit
		&"noheat": return no_heat
		&"freeze": return freeze
		&"stats": return show_stats
		&"quick": return quick_weapons
	return false


# --- actions (each returns a short status line; "" = could not do it) ----------------------------------------------------------------

## Gives (unlocks) a weapon, makes it the weapon in hand and fills its magazine and reserve.
static func give_weapon(id: StringName) -> String:
	var p := _player()
	if p == null or not WeaponDefs.DEFS.has(id):
		return ""
	var w: PlayerWeapon = p.weapon
	if id != &"carbine":
		w.grant(id)
	w.switch_to(id, true)
	fill_ammo()
	return _say("GIVEN  %s" % WeaponDefs.title(id))


## Own and equip one throwable or gadget (and refill the throwable stock).
static func give_gear(id: StringName) -> String:
	if not (Gear.is_throwable(id) or Gear.is_gadget(id)):
		return ""
	Gear.give(id)
	Gear.equip(id)
	var p := _player()
	if p != null and p.throwables != null:
		p.throwables.refill()
	return _say("%s EQUIPPED" % Gear.title(id))


static func give_xp(n: int) -> String:
	SkillTree.add_xp(n)
	return _say("LEVEL %d · %d SKILL POINTS" % [SkillTree.level(), SkillTree.points()])


static func max_skills() -> String:
	SkillTree.max_all()
	return _say("ALL SKILLS MAXED")


static func give_all_gear() -> String:
	Gear.give_all()
	var p := _player()
	if p != null and p.throwables != null:
		p.throwables.refill()
	return _say("ALL THROWABLES AND GADGETS")


static func give_all_weapons() -> String:
	for id: StringName in WeaponDefs.IDS:
		give_weapon(id)
	var p := _player()
	if p != null:
		p.weapon.switch_to(&"carbine", true)
	return _say("ALL WEAPONS UNLOCKED")


## Select a weapon (the quick buttons): test mode may select anything, so a weapon not owned yet is unlocked and filled first.
static func select_weapon(id: StringName) -> bool:
	var p := _player()
	if p == null or not WeaponDefs.DEFS.has(id):
		return false
	if not WeaponDefs.is_unlocked(id):
		give_weapon(id)
		return true
	if id == p.weapon.current:
		return true
	return p.weapon.switch_to(id)


## Full magazine and reserve for the weapon in hand and every weapon held.
static func fill_ammo() -> String:
	var p := _player()
	if p == null:
		return ""
	var w: PlayerWeapon = p.weapon
	w.reload_t = 0.0
	w.ammo = w.mag
	if w.reserve >= 0:
		w.reserve = int(w.def["reserve"]) * 2
	for id: StringName in WeaponDefs.IDS:
		if id != w.current and w._store.has(id):
			var cap := int(WeaponDefs.def(id)["reserve"])
			w._store[id] = Vector2i(w._mag_for(id), cap * 2 if cap >= 0 else -1)
	return _say("AMMO FILLED")


static func add_credits(n: int) -> String:
	if Game.progress == null:
		return ""
	Game.progress.call(&"add_credits", n)
	return _say("+%d CREDITS" % n)


static func max_upgrades() -> String:
	if Game.progress == null:
		return ""
	for id: StringName in Upgrades.IDS:
		var guard := 0
		while int(Game.progress.call(&"level", id)) < Upgrades.MAX_LEVEL and guard < 10:
			Game.progress.call(&"grant_upgrade", id)
			guard += 1
	return _say("ALL UPGRADES MAXED")


static func set_heat(level: float) -> String:
	var was := no_heat
	no_heat = false
	Game.heat = level
	no_heat = was
	return _say("HEAT %.0f" % level)


static func set_weather(weather: String) -> String:
	if not WEATHER.has(weather) or not is_instance_valid(Game.atmosphere):
		return ""
	var w: Weather = Game.atmosphere.get(&"weather")
	if w == null:
		return ""
	w.set_state(WEATHER[weather], true)
	return _say("WEATHER  %s" % weather)


static func set_post_fx2(on: bool) -> String:
	PostFx2.set_enabled(on)
	return _say("POST LOOK  %s" % ("FILM FX2" if on else "BASE"))


static func set_materials_v2(on: bool) -> String:
	MaterialsV2.set_enabled(on)
	return _say("SURFACE LOOK  %s" % ("MATERIALS V2" if on else "V1"))


## Uses a quantum verb (PHASE SHIELD, TIME SLIP, ARC) at once: energy refilled, cooldown cleared.
static func use_verb(id: StringName) -> String:
	var p := _player()
	if p == null or p.qverbs == null or not QuantumVerbs.TITLES.has(id):
		return ""
	p.energy = p.max_energy
	p.qverbs.clear_cooldown(id)
	if p.qverbs.use(id):
		return QuantumVerbs.TITLES[id]
	return _say("%s: NO TARGET" % QuantumVerbs.TITLES[id] if id == &"arc" else "%s NOT READY" % QuantumVerbs.TITLES[id])


static func kill_all_enemies() -> String:
	if not is_instance_valid(Game.enemies):
		return ""
	var n := 0
	for e: Drone in (Game.enemies as EnemyManager).list.duplicate():
		if is_instance_valid(e) and not e.dead:
			e.damage(KILL, true)
			n += 1
	return _say("%d ENEMIES DOWN" % n)


static func spawn_enemy(type: StringName) -> String:
	if not is_instance_valid(Game.enemies) or not EnemyTypes.TYPES.has(type):
		return ""
	var mgr := Game.enemies as EnemyManager
	var at := _crosshair_point()
	if mgr.alive_count() >= mgr.cap():                        # the pool is full: retire the oldest one for the one asked for
		for e: Drone in mgr.list:
			if is_instance_valid(e):
				mgr.release(e)
				break
	var d := mgr.spawn(type, at, true)
	return _say("SPAWNED  %s" % String(type).to_upper()) if d != null else ""


static func spawn_vehicle(kind: StringName) -> String:
	if not is_instance_valid(Game.vehicles) or not kind in VEHICLES:
		return ""
	var vm := Game.vehicles as VehicleManager
	var p := _player()
	var at := _crosshair_point(14.0)
	var heading := p.yaw if p != null else 0.0
	if vm.list.size() >= vm.cap():                           # the pool is full: retire a parked car for the one asked for
		for old: Vehicle in vm.list:
			if is_instance_valid(old) and (p == null or old != p.vehicle):
				vm._release(old)
				break
	var v := vm.spawn_parked(kind, at, heading)
	return _say("SPAWNED  %s" % String(kind).to_upper()) if v != null else ""


## "core", "contract", "roof", "ne" / "nw" / "se" / "sw" (the four map corners, on the nearest street), "spawn".
static func teleport(where: String) -> String:
	var p := _player()
	if p == null:
		return ""
	var target := Vector3.INF
	var e := CityLayout.HALF - 20.0
	match where:
		"core":
			if is_instance_valid(Game.missions):
				var c: Dictionary = Game.missions.call(&"nearest_core", p.global_position)
				if not c.is_empty():
					target = (c["pos"] as Vector3) + Vector3(4.0, 0.0, 0.0)
		"contract":
			var k = Game.missions.get(&"contracts") if is_instance_valid(Game.missions) else null
			if k != null and bool(k.call(&"has_marker")):
				target = (k.get(&"pos") as Vector3) + Vector3(5.0, 0.0, 0.0)
		"roof": target = _tall_roof(p.global_position)
		"ne": target = PlayerUtil.nearest_street(Vector3(e, 0.0, -e))
		"nw": target = PlayerUtil.nearest_street(Vector3(-e, 0.0, -e))
		"se": target = PlayerUtil.nearest_street(Vector3(e, 0.0, e))
		"sw": target = PlayerUtil.nearest_street(Vector3(-e, 0.0, e))
		"spawn": target = Game.SPAWN
	if not target.is_finite():
		return ""
	p.teleport_to(target + Vector3(0.0, 0.1, 0.0))
	return _say("TELEPORTED  %s" % where.to_upper())


## The roof of the tallest building 60-220 m from `from`.
static func _tall_roof(from: Vector3) -> Vector3:
	var world := Game.world
	if not is_instance_valid(world) or world.get(&"layout") == null:
		return Vector3.INF
	var best := Vector3.INF
	var best_h := -1.0
	for lot in (world.get(&"layout").lots as Array):
		var d := Vector2(lot.cx - from.x, lot.cz - from.z).length()
		if d < 60.0 or d > 220.0:
			continue
		var top := float(world.call(&"ground_height", lot.cx, lot.cz))
		if top > best_h:
			best_h = top
			best = Vector3(lot.cx, top + 0.4, lot.cz)
	return best


## Jumps to sector `index` (0 based): the story chapter, a fresh round of cores, the enemies and the heat cleared; the hero keeps his weapons and stays where he is.
static func jump_to_chapter(index: int) -> String:
	index = clampi(index, 0, 11)
	if is_instance_valid(Game.story):
		Game.story.call(&"set_chapter", index)
	if Game.progress != null:
		Game.progress.set(&"sector", index)
	if is_instance_valid(Game.missions):
		Game.missions.call(&"new_round", mini(9, 6 + index))
	if is_instance_valid(Game.enemies):
		(Game.enemies as EnemyManager).clear()
	Game.heat = 0.0
	return _say("SECTOR %d" % (index + 1))


static func start_contract(kind: StringName) -> String:
	if not is_instance_valid(Game.missions):
		return ""
	var k = Game.missions.get(&"contracts")
	if k == null or not kind in CONTRACTS:
		return ""
	if bool(k.call(&"is_active")):
		k.call(&"abandon")
	k.call(&"offer", kind)
	var ok: bool = bool(k.call(&"accept"))
	return _say("CONTRACT  %s" % ContractTypes.title(kind)) if ok else ""


static func skip_contract() -> String:
	var k = Game.missions.get(&"contracts") if is_instance_valid(Game.missions) else null
	if k == null:
		return ""
	if bool(k.call(&"is_active")):
		k.call(&"_complete", 1.0)
		return _say("CONTRACT SKIPPED (PAID)")
	if bool(k.call(&"has_marker")):
		k.call(&"abandon")
		return _say("OFFER DROPPED")
	return ""


## Perf and world numbers for the STATS page and the overlay.
static func stats_text() -> String:
	var lines: Array[String] = []
	var rs := RenderingServer
	lines.append("FPS %d   DRAWS %d   TRIS %dk   TEX %d MB" % [Engine.get_frames_per_second(), int(rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)) / 1000, int(rs.get_rendering_info(rs.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576])
	lines.append("TIER %s   RENDERER %s   NODES %d" % [["LOW", "MED", "HIGH"][clampi(Game.quality, 0, 2)], rs.get_current_rendering_method(), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	if is_instance_valid(Game.world) and Game.world.has_method(&"stats"):
		var st: Dictionary = Game.world.call(&"stats")
		var pc = Game.world.call(&"prop_colliders")
		lines.append("COLLIDERS %s   PROP COLLIDERS IN USE %d" % [str(st.get("colliders", "?")), int(pc.in_use) if pc != null else 0])
	if is_instance_valid(Game.enemies):
		var cars := (Game.vehicles as VehicleManager).list.size() if is_instance_valid(Game.vehicles) else 0
		lines.append("ENEMIES %d / %d   CARS %d" % [(Game.enemies as EnemyManager).alive_count(), (Game.enemies as EnemyManager).cap(), cars])
	var p := _player()
	if p != null:
		lines.append("POS %.0f %.0f %.0f   HP %.0f   HEAT %.1f" % [p.global_position.x, p.global_position.y, p.global_position.z, p.hp, Game.heat])
	return "\n".join(lines)
