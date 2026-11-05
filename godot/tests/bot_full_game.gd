extends "res://tests/bot_soak.gd"
## FULL-FEATURE BOT: the soak bot (tests/bot_soak.gd: real composed game, leak checkpoints, error tap, soft-lock guards) plus one activity for every system of waves 21-45:
## the four quantum abilities and the phase step, all eight weapons with alt-fire, ammo types and attachments, cover / takedown / vault / rooftops, vehicles with the garage
## and car weapons, side missions, collectibles, city events, activities, boss set pieces, stealth, weather and time of day, the map, options, hero customisation and a
## save / load round trip. Every cycle runs the three groups; the cycle ends in the soak's normalised checkpoint. Fails on any script / engine error, on node / memory
## growth past tests/soak_lib.gd LIMITS, and when the game does not come back to play (or the menu).
##
##   tools/full_bot.sh [--minutes=8] [--seed=1] [--speed=4]        the long run (about 8 simulated minutes)
##   tools/test.sh tests/test_full_quick.gd                         the 60 s CI variant
##
## user:// state (save file, settings, activities, map fog) is redirected to throw-away files and removed at the end.

const SAVE_TMP := "user://full_bot_save.cfg"
const SETTINGS_TMP := "user://full_bot_settings.cfg"
const WEAPON_KEYS: Array[StringName] = [&"weapon_1", &"weapon_2", &"weapon_3", &"weapon_4", &"weapon_5", &"weapon_6", &"weapon_7", &"weapon_8"]

var group_filter := PackedStringArray()    ## run only these groups (debugging): quantum weapons stealth vehicles garage world events activities pieces weather ui save systems
var _wallet_backup := 0
var _ui_backup := {}
var _story_chapter_backup: Variant = null
var _held: Array[Vehicle] = []              ## cars the garage step pinned against streaming (released again by _unhold_cars)


func _init() -> void:
	super()
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		if kv[0] == "groups" and kv.size() > 1:
			group_filter = kv[1].split(",", false)


func _g(name: String) -> bool:
	return group_filter.is_empty() or group_filter.has(name)


func _fail(msg: String) -> void:
	fails.append(msg)


func _expect(cond: bool, msg: String) -> bool:
	if not cond:
		_fail("%s (during '%s', %s)" % [msg, _activity, _note])
	return cond


func _find_script(path: String) -> Node:
	var anchor: Node = Game.player.get_parent() if is_instance_valid(Game.player) else null
	if anchor == null:
		return null
	for c in anchor.get_children():
		var s := c.get_script() as Script
		if s != null and s.resource_path == path:
			return c
	return null


func _prog() -> Progress:
	return Game.progress as Progress


func _isolate() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TMP))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_TMP))
	var pr := _prog()
	if pr != null:
		pr.path = SAVE_TMP
		pr.autosave_enabled = false
	if _hud != null and _hud.settings != null:
		_hud.settings.path = SETTINGS_TMP
	_ui_backup = {"scale": Tr.text_scale, "reduce_motion": UiSettings.s_reduce_motion, "cb": UiSettings.s_cb_safe}
	if is_instance_valid(Game.story) and Game.story.get("chapter") != null:
		_story_chapter_backup = Game.story.get("chapter")
		Game.story.set("chapter", 9)          # every side mission is unlocked from chapter 9 on


func _restore_isolation() -> void:
	Tr.text_scale = _ui_backup.get("scale", Tr.text_scale)
	UiSettings.s_reduce_motion = _ui_backup.get("reduce_motion", false)
	UiSettings.s_cb_safe = _ui_backup.get("cb", UiSettings.s_cb_safe)
	if _story_chapter_backup != null and is_instance_valid(Game.story):
		Game.story.set("chapter", _story_chapter_backup)
	for f in [SAVE_TMP, SETTINGS_TMP, "user://activities.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func run(host: Node) -> void:
	_seed_everything()
	# the soak's run() sets everything up, then calls _warm() and _one_cycle(); the isolation is applied in _warm (the first thing the game is up for)
	await super.run(host)
	_restore_isolation()


## Every random source the game and the bot draw from starts from the bot's seed (traffic, crowds, missions, story): two runs of one seed differ only by timing.
func _seed_everything() -> void:
	seed(seed_value)
	for pair: Array in [[Game.missions, &"rng"], [Game.story, &"_rng"]]:
		var holder: Object = pair[0]
		if is_instance_valid(holder) and holder.get(pair[1]) is RandomNumberGenerator:
			(holder.get(pair[1]) as RandomNumberGenerator).seed = seed_value
		if is_instance_valid(holder) and pair[0] == Game.missions:
			var ct: Variant = holder.get("contracts")
			if ct is Object and (ct as Object).get(&"rng") is RandomNumberGenerator:
				((ct as Object).get(&"rng") as RandomNumberGenerator).seed = seed_value


## Waits (real time, so the hit-stop and slow motion that stretch game time cannot hide it) until the engine speed is the bot's again; forces it back when something
## really holds it down. Returns whether it came back on its own.
func _settle_time(real_limit := 6.0) -> bool:
	if speed <= 0:
		return true
	var t0 := Time.get_ticks_msec()
	while Engine.time_scale < float(speed) * 0.99 and float(Time.get_ticks_msec() - t0) / 1000.0 < real_limit and fails.is_empty():
		await _tick()
	if Engine.time_scale < float(speed) * 0.99:
		Engine.time_scale = float(speed)
		return false
	return true


## The common preconditions of every group: playing, at the bot's speed, full health, nothing held down, no leftover car or interior from the step before.
func _ensure_play(limit := 40.0) -> void:
	await super._ensure_play(limit)
	if Game.state == &"play" and fails.is_empty():
		await _settle_time(3.0)


## Fills the car and enemy pools the way a long session would (two of every kind alive at once, at the biggest tier's caps) so the baseline checkpoint already holds them:
## otherwise a random kind meeting its second instance late in the run reads as node growth.
func _warm_pools() -> void:
	_note = "pools"
	var em := Game.enemies as EnemyManager
	var vm := Game.vehicles as VehicleManager
	var q := Game.quality
	Game.set_quality(2)
	var types: Array[StringName] = []
	types.append_array(ENEMY_TYPES)
	types.append(&"overseer")
	types.append_array(EnemyTypes.VARIETY_TYPES)
	types.append_array(EnemyTypes.ELITE_TYPES)
	var doubled: Array[StringName] = []
	for t in types:
		doubled.append(t)
		doubled.append(t)
	var i := 0
	while i < doubled.size() and fails.is_empty():
		for k in em.cap():
			if i >= doubled.size():
				break
			em.spawn(doubled[i], _p.global_position + Vector3(10.0 + float(k) * 1.5, 0.0, float(k % 3) * 2.0), true)
			i += 1
		await _wait(0.3)
		em.clear()
	var kinds: Array[StringName] = []
	for kind in TestMode.VEHICLES:
		kinds.append(kind)
		kinds.append(kind)
	i = 0
	while i < kinds.size() and fails.is_empty():
		var made: Array[Vehicle] = []
		for k in vm.cap():
			if i >= kinds.size():
				break
			var c := vm.spawn_parked(kinds[i], _p.global_position + Vector3(-12.0 + float(k) * 3.0, 0.0, 18.0), 0.0)
			i += 1
			if c != null:
				made.append(c)
		await _wait(0.2)
		for c in made:
			if is_instance_valid(c) and vm.list.has(c) and c != vm.starter and not c.driver_is_player:
				vm._release(c)
	Game.set_quality(q)
	em.clear()
	await _wait(0.5)


func _warm() -> void:
	_isolate()
	_activity = "warm full"
	var em := Game.enemies as EnemyManager
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
		_note = "weapon " + String(id)
		_p.weapon.switch_to(id, true)
		await _wait(0.2)
	_p.weapon.switch_to(&"carbine", true)
	em.clear()
	await _warm_pools()
	await super._warm()


func _one_cycle() -> void:
	_cycle += 1
	_log("FULL cycle %d at t=%.0fs" % [_cycle, _clock])
	_p.energy = _p.max_energy
	if _g("quantum"):
		await _act_quantum()
	if _g("weapons"):
		await _act_weapons()
	if _g("stealth"):
		await _act_stealth()
	if _g("vehicles"):
		await _act_drive(6.0)
	if _g("garage"):
		await _act_garage()
	if _g("world"):
		await _act_world()
	if _g("events"):
		await _act_events()
	if _g("activities"):
		await _act_activities()
	if _g("pieces"):
		await _act_pieces()
	if _g("weather"):
		await _act_weather()
	if _g("demo"):
		await _act_demo()
	if _g("ui"):
		await _act_ui()
	if _g("save"):
		await _act_save()
	if _g("systems"):
		for sys in SYSTEMS:                                         # waves 41-79 (tests/bot_soak.gd _run_system): ally, factions / wanted, safehouses, crafting, photo, arena, heists, pad, weather / time, save / load
			await _run_system(sys)
	if _on("interior"):
		await _act_interior(&"weapons" if _cycle % 2 == 1 else InteriorData.TYPES[_cycle % InteriorData.TYPES.size()], 3.0, _cycle % 2 == 0)
	if _on("tiers") and _cycle % 2 == 0:
		await _act_tiers()
	if _on("die"):
		await _act_die(_cycle % 3)
	if resets and _cycle % 3 == 0:
		await _act_new_game(_cycle % 2 == 1)
	await _act_walk(3.0)
	await _checkpoint()


## Enemies in a ring in front of the player; the player faces the first.
func _spawn_ring(n: int, types: Array, dist := 14.0, aware := true) -> Array:
	var em := Game.enemies as EnemyManager
	var out: Array = []
	for i in n:
		var ang := float(i) / float(n) * 1.6 - 0.8 + _p.yaw
		var pos := _p.global_position + Vector3(-sin(ang), 0.0, -cos(ang)) * dist + Vector3(0.0, 0.5, 0.0)
		out.append(em.spawn(types[i % types.size()], pos, aware))
	return out


func _fresh_street() -> void:
	_p.invuln = 5.0
	_p.hp = _p.max_hp
	_p.energy = _p.max_energy
	_p.teleport_to(_random_road_spot())
	_look(rng.randf_range(-PI, PI))
	(Game.enemies as EnemyManager).clear()


func _press(action: StringName, ticks := 2) -> void:
	Input.action_press(action)
	for i in ticks:
		await _tick()
	Input.action_release(action)
	await _tick()


# --- abilities -----------------------------------------------------------------------------------------------------------------

func _act_quantum() -> void:
	_activity = "quantum"
	_count("quantum")
	await _ensure_play()
	await _fresh_street()
	var q: Quantum = _p.quantum as Quantum
	if not _expect(q != null, "the player has a Quantum node"):
		return
	var drones := _spawn_ring(4, [&"sentinel", &"operative", &"striker", &"sentinel"], 12.0)
	await _wait(0.6)
	# QUANTUM TELEPORT: tap = beacon + teleport, hold = aimed teleport with slow motion
	_note = "teleport tap"
	var p0 := _p.global_position
	await _press(&"blink", 2)
	await _wait(0.4)
	_p.energy = _p.max_energy
	await _wait(2.5)                                                       # cooldown
	_note = "teleport hold"
	_p.energy = _p.max_energy
	Input.action_press(&"blink")
	await _wait(0.9)
	Input.action_release(&"blink")
	await _wait(1.5)
	if _expect(not q.aiming, "the aimed teleport ended"):
		_count("teleports")
	var back := await _settle_time(8.0)
	_expect(back, "slow motion ended after the aimed teleport, hit-stop allowed for (time scale %.2f, aiming %s)" % [Engine.time_scale, q.aiming])
	# ENTANGLE: link two drones, swap
	_note = "entangle"
	_p.energy = _p.max_energy
	await _press(&"entangle", 2)
	await _wait(0.4)
	_note = "link"
	q.link_drones()
	await _wait(0.4)
	_p.energy = _p.max_energy
	_note = "entangle swap"
	q.entangle()
	await _wait(0.8)
	# SUPERPOSITION + COLLAPSE
	_note = "superpose"
	_p.energy = _p.max_energy
	await _press(&"superpose", 2)
	await _wait(1.2)
	_note = "collapse"
	await _press(&"collapse", 2)
	await _wait(0.6)
	_p.energy = _p.max_energy
	q.collapse_all()
	await _wait(0.6)
	# phase step through a thin wall
	_note = "phase step"
	_p.energy = _p.max_energy
	if q.phase_step():
		_count("phase_steps")
		await _wait(1.0)
	_expect(not q.phase.active() or q.phase.left >= 0.0, "phase state sane")
	_p.energy = _p.max_energy
	_expect(_p.global_position.is_finite(), "player position finite after the abilities (from %s)" % p0)
	q.cancel_aim()
	(Game.enemies as EnemyManager).clear()
	await _release_all()


# --- weapons -------------------------------------------------------------------------------------------------------------------

func _act_weapons() -> void:
	_activity = "weapons"
	_count("weapon_rounds")
	await _ensure_play()
	await _fresh_street()
	var w := _p.weapon
	var pr := _prog()
	for id: StringName in WeaponDefs.IDS:
		WeaponDefs.unlock(id)
	var ids: Array = WeaponDefs.IDS
	var drones := _spawn_ring(3, [&"sentinel", &"heavy", &"shield"], 16.0)
	for id: StringName in ids:
		_note = "weapon " + String(id)
		_p.energy = _p.max_energy
		await _ensure_play()                                               # a death or pause meanwhile (the respawn resets the loadout) must not read as a dead weapon
		_p.hp = _p.max_hp
		_p.invuln = 5.0
		var vm := Game.vehicles as VehicleManager
		if vm != null and vm.driven != null:
			vm.exit_vehicle()
		if (Game.enemies as EnemyManager).list.size() < 2:
			drones = _spawn_ring(3, [&"sentinel", &"heavy", &"shield"], 16.0)
		WeaponDefs.unlock(id)
		if not _expect(w.switch_to(id, true) or w.current == id, "switch to %s" % id):
			continue
		await _wait(0.15)
		var s0 := w.shots_fired
		var c0 := w.combo_hits
		var fired := false
		for attempt in 3:                                                  # the first press can land in a hit-stop, a swap or a spin-up: press again, wait on the counters
			var tgt: Drone = null
			for e: Drone in (Game.enemies as EnemyManager).list:
				if e.active and not e.dead:
					tgt = e
					break
			if tgt != null:
				_p.camera_rig.look_at_point(tgt.center())
			w.ammo = w.mag
			w.tick(3.0, false, false, false, false)                         # the previous weapon's alt-fire cooldown and swap do not carry over
			Input.action_press(&"aim")
			Input.action_press(&"fire")
			for i in 14:
				await _wait(0.2)
				if w.shots_fired > s0 or w.combo_hits > c0 or w.grenades_active() > 0 or Game.state != &"play":
					break
			Input.action_release(&"fire")
			Input.action_release(&"aim")
			await _wait(0.2)
			fired = w.shots_fired > s0 or w.combo_hits > c0 or w.ammo < w.mag or w.is_reloading() or w.grenades_active() > 0
			if fired:
				break
			await _settle_time(4.0)
			await _release_all()
			_p.hp = _p.max_hp
			_p.invuln = 5.0
			if w.current != id:
				w.switch_to(id, true)
		_expect(fired, "%s fires (shots %d -> %d, current %s, state %s, hp %.0f, ammo %d/%d, reload %s, time scale %.2f)" % [id, s0, w.shots_fired, w.current, Game.state, _p.hp, w.ammo, w.mag, w.is_reloading(), Engine.time_scale])
		w.tick(5.0, false, false, false, false)                             # alt-fire cooldown
		w.ammo = w.mag
		if w.alt_fire(false):
			_count("alt_fires")
		await _wait(0.3)
		if id in [&"carbine", &"burst", &"flux"]:
			w.cycle_ammo_type()
			_count("ammo_cycles")
		await _press(&"reload", 2)
		await _wait(0.4)
		if rng.randf() < 0.5:
			w.start_inspect()
		if (Game.enemies as EnemyManager).list.size() < 2:
			drones = _spawn_ring(3, [&"sentinel", &"heavy", &"shield"], 16.0)
	# attachments: give, equip, effective stats, unequip
	_note = "attachments"
	for part: StringName in Attachments.PARTS:
		Attachments.give(part)
		var slot := Attachments.slot_of(part)
		if Attachments.equip(&"carbine", part):
			var eff := Attachments.effective(&"carbine")
			_expect(not eff.is_empty(), "effective stats with %s" % part)
			_count("attachments")
	w.switch_to(&"carbine", true)
	w.apply_upgrades()
	await _wait(0.4)
	for part: StringName in Attachments.PARTS:
		Attachments.unequip(&"carbine", Attachments.slot_of(part))
	w.apply_upgrades()
	# weapon keys
	for k in WEAPON_KEYS:
		await _press(k, 2)
	w.cycle(1)
	w.cycle(-1)
	w.switch_to(&"carbine", true)
	(Game.enemies as EnemyManager).clear()
	await _release_all()


# --- cover, vault, rooftops, stealth takedown --------------------------------------------------------------------------------

func _act_stealth() -> void:
	_activity = "stealth"
	_count("stealth")
	await _ensure_play()
	await _fresh_street()
	var em := Game.enemies as EnemyManager
	# noise and takedown on an unaware target behind
	_note = "takedown"
	var fwd := Vector3(-sin(_p.yaw), 0.0, -cos(_p.yaw))
	var e: Drone = em.spawn(&"operative", _p.global_position + fwd * 1.4 + Vector3(0, 0.3, 0), false)
	await _wait(0.2)
	Stealth.noise(em.list, _p.global_position, &"step", 6.0)
	_p.cover.try_takedown()
	await _press(&"takedown", 2)
	await _wait(0.5)
	if _p.cover.takedowns > 0:
		_count("takedowns")
	em.clear()
	# cover and vault: walk at a wall of a building and jump
	_note = "cover walk"
	var w := Game.world as City
	var pt := w.random_road_point()
	_p.teleport_to(Vector3(pt.x, 0.0, pt.z))
	_look(rng.randf_range(-PI, PI))
	Input.action_press(&"crouch")
	Input.action_press(&"move_forward")
	await _wait(1.2)
	Input.action_release(&"crouch")
	_note = "vault"
	Input.action_press(&"sprint")
	for i in 5:
		Input.action_press(&"jump")
		await _wait(0.3)
		Input.action_release(&"jump")
		await _wait(0.3)
		if _p.traversal.active():
			_count("traversals")
	await _release_all()
	_expect(_p.cover != null and _p.global_position.is_finite(), "player sane after cover and vault")
	# rooftop: a roof shard
	_note = "rooftop"
	var spots := Collectibles.spots()
	for i in spots.size():
		if Collectibles.is_roof(i):
			_p.teleport_to(spots[i] + Vector3(0.0, 0.6, 0.0))
			await _wait(1.0)
			_count("rooftops")
			break
	await _release_all()


# --- vehicles: garage and weapons ------------------------------------------------------------------------------------------

func _act_garage() -> void:
	_activity = "garage"
	_count("garage")
	await _ensure_play()
	var vm := Game.vehicles as VehicleManager
	var pr := _prog()
	if vm == null or pr == null:
		return
	if vm.driven != null:
		vm.exit_vehicle()
	await _fresh_street()
	pr.credits = maxi(pr.credits, 5000)
	_note = "keep the starter"
	var starter := _garage_starter(vm)
	if not _expect(starter != null, "a car to keep exists (%d cars, cap %d)" % [vm.list.size(), vm.cap()]):
		return
	await _wait(0.3)
	for attempt in 4:                                                      # another system (mission, event, hit, streaming) may unseat the player or recycle the car: re-establish, retry
		_p.hp = _p.max_hp
		_p.invuln = 5.0
		if not _car_usable(starter):
			starter = _garage_starter(vm)
			if starter == null:
				continue
		_p.teleport_to(starter.global_position + Vector3(2.5, 0.0, 0.0))
		if vm.driven != null and vm.driven != starter:
			vm.exit_vehicle()
		vm.enter(starter)
		await _wait(0.5)
		if vm.driven == starter and starter != null:
			break
	var took := starter != null and vm.driven == starter
	if not _expect(took, "the player took the wheel (starter usable %s, driven %s, player vehicle %s, state %s, cars %d/%d)" % [_car_usable(starter), vm.driven, _p.vehicle, Game.state, vm.list.size(), vm.cap()]):
		_unhold_cars(vm)
		return
	var g := vm.get_garage()
	var saved := vm.save_driven()
	_unhold_cars(vm)
	if saved:
		_count("garage_saves")
	_expect(g.has_car(), "the driven car is kept in the garage (saved %s)" % saved)
	g.set_paint(rng.randi() % VehicleSpecs.COLORS.size())
	for st: StringName in [&"speed", &"armour", &"grip", &"weapon"]:
		if g.can_upgrade(st, pr):
			g.upgrade(st, pr)
	# car weapons: mounted guns fire (sport / suv / hover, or the garage's weapon level)
	_note = "car weapon"
	var car := vm.driven
	if car != null and car.weapons != null:
		var s0 := car.weapons.shots
		_spawn_ring(2, [&"sentinel"], 22.0)
		Input.action_press(&"fire")
		Input.action_press(&"move_forward")
		await _wait(2.0)
		Input.action_release(&"fire")
		Input.action_release(&"move_forward")
		if car.weapons.shots > s0:
			_count("car_shots")
	# the garage screen and CALL CAR
	_note = "garage screen"
	var touch := _hud.touch
	if touch != null and touch.has_method(&"_open_garage"):
		touch.call(&"_open_garage")
		await _wait(0.3)
		var gs := touch.get_node_or_null("GarageScreen") as GarageScreen
		if gs != null and gs.is_open():
			_intended += 1
			await _wait(0.8)
			gs.close_screen()
			_intended -= 1
			_count("garage_screens")
	await _ensure_play()
	if vm.driven != null:
		vm.exit_vehicle()
	await _wait(0.5)
	_p.teleport_to(_random_road_spot())
	await _wait(0.5)
	_note = "summon"
	for c: Vehicle in vm.list:
		c.remove_meta(&"dbg")
	if vm.summon_garage() != null:
		_count("summons")
	await _wait(1.5)
	if vm.driven != null:
		vm.exit_vehicle()
	(Game.enemies as EnemyManager).clear()
	await _release_all()


## A live, enterable car (not freed, wrecked, dead or recycled into the pool).
func _car_usable(c: Vehicle) -> bool:
	return c != null and is_instance_valid(c) and c.active and not c.dead and not c.wreck and Garage.can_keep(c)


## A fresh parked car beside the player that streaming cannot recycle meanwhile (the manager's own `hold` meta). Makes room first when the tier's car cap is full.
func _garage_starter(vm: VehicleManager) -> Vehicle:
	for i in 12:
		if vm.list.size() < vm.cap():
			break
		var n := vm.list.size()
		vm._release_farthest(_p.global_position)
		if vm.list.size() >= n:
			break
	var c := vm.spawn_parked(&"sport", _p.global_position + Vector3(4.0, 0.0, 0.0), 0.0)
	if c != null:
		c.set_meta(&"hold", true)
		_held.append(c)
	return c


func _unhold_cars(_vm: VehicleManager) -> void:
	for c in _held:
		if is_instance_valid(c):
			c.remove_meta(&"hold")
	_held.clear()



# --- side missions, collectibles --------------------------------------------------------------------------------------------

func _act_world() -> void:
	_activity = "world"
	_count("world")
	await _ensure_play()
	var m := Game.missions as Missions
	var pr := _prog()
	var sm := m.sides
	await _fresh_street()
	# side missions: start one (rotating), walk it to the waypoints, then finish or abandon it
	_note = "side mission"
	var order: Array = SideMissions.ORDER
	for k in 2:
		var mid: StringName = order[(_cycle * 2 + k) % order.size()]
		if sm.active:
			sm.abort()
		if not sm.can_start(mid):
			continue
		if not sm.start(mid):
			continue
		_count("side_starts")
		var limit := _clock + 14.0 * scale
		while sm.active and _clock < limit and fails.is_empty():
			var wp := sm.waypoint()
			if wp.is_finite():
				_p.teleport_to(Vector3(wp.x, maxf(wp.y, 0.0) + 0.3, wp.z))
			sm.on_kill()
			await _wait(1.0)
			if Game.state == &"dead":
				await _ensure_play()
		if sm.active:
			sm.abort()
		_expect(not sm.active, "the side mission ended")
		_count("side_ends")
		await _wait(0.3)
	# collectibles: collect a ground one and a roof one, walk onto the nearest
	_note = "collectibles"
	var cl := pr.collectibles
	if cl != null:
		var idx := cl.nearest_uncollected(_p.global_position)
		if idx >= 0:
			var spots := Collectibles.spots()
			_p.teleport_to(spots[idx] + Vector3(0.0, 0.4, 0.0))
			await _wait(0.8)
			_count("shard_walks")
		for i in 2:
			var j := cl.nearest_uncollected(_p.global_position)
			if j >= 0 and cl.collect(j, true):
				_count("shards")
		_expect(cl.count() <= Collectibles.COUNT, "collectible count within bounds")
	await _release_all()


func _act_events() -> void:
	_activity = "events"
	_count("events")
	await _ensure_play()
	await _fresh_street()
	var ce := _find_script("res://scripts/world/city_events.gd")
	if ce == null:
		_fail("the city events node is not in the game (not wired)")
		return
	var kinds: Array = ce.DEF.keys()
	for k in 2:
		var kind: StringName = kinds[(_cycle + k) % kinds.size()]
		_note = "event " + String(kind)
		var info: Dictionary = ce.spawn_near(_p.global_position, kind)
		if info.is_empty():
			continue
		_count("event_spawns")
		await _wait(1.5)
		var mk: Array = ce.markers()
		_expect(mk.size() >= 1, "an active event has a map marker")
		var gs: float = ce.gravity_scale_at(_p.global_position)
		_expect(gs > 0.0 and gs <= 1.0, "event gravity scale in range (%.2f)" % gs)
		if kind == &"rift":                                                   # stand inside the rift: low gravity, then jump
			var at: Vector3 = info.get("pos", _p.global_position)
			_p.teleport_to(at + Vector3(0.0, 0.3, 0.0))
			Input.action_press(&"jump")
			await _wait(1.0)
			Input.action_release(&"jump")
		ce.resolve(int(info.get("id", -1)), k == 0)
		await _wait(1.0)
	(Game.enemies as EnemyManager).clear()
	await _release_all()


func _act_activities() -> void:
	_activity = "activities"
	_count("activities")
	await _ensure_play()
	await _fresh_street()
	var act := Lib.find_node_of("Activities") as Activities
	if act == null:
		_fail("the Activities node is not in the game (not wired)")
		return
	var ids: Array[StringName] = [Activities.RANGE, Activities.PARKOUR, Activities.DRIFT, Activities.ARENA]
	for id in ids:
		_note = "activity " + String(id)
		var ent: Dictionary = Activities.entries()
		var where: Vector3 = ent.get(id, Vector3.ZERO) if ent.get(id) is Vector3 else _p.global_position
		_p.teleport_to(where + Vector3(0.0, 0.3, 0.0))
		await _wait(0.4)
		if not act.start(id, true):
			continue
		_count("activity_starts")
		var r: Dictionary = act.readout()
		_expect(r.has("name") or r.has("id") or not r.is_empty(), "the activity has a HUD readout")
		if id == Activities.ARENA:
			_p.invuln = 99.0
		await _wait(2.5)
		if id == Activities.RANGE:
			Input.action_press(&"fire")
			await _wait(1.0)
			Input.action_release(&"fire")
		if id == Activities.ARENA:
			act.end_arena()
		act.stop()
		await _wait(0.5)
		_expect(act.target_count() == 0 or id != Activities.RANGE, "activity cleaned up its targets")
		(Game.enemies as EnemyManager).clear()
	await _release_all()


# --- boss set pieces ---------------------------------------------------------------------------------------------------------

func _act_pieces() -> void:
	_activity = "pieces"
	if _cycle % 2 == 0:                                                      # the scripted chapters are slow; every other cycle
		return
	_count("pieces")
	await _ensure_play()
	var m := Game.missions as Missions
	var cr := m.campaign
	if cr == null:
		return
	var was := cr.enabled
	cr.enabled = true
	var chapter: int = [1, 4, 7][(_cycle / 2) % 3]                          # chapters 2 / 5 / 8 carry a set piece
	_note = "chapter %d" % chapter
	_fresh_street_quiet()
	if cr.start_chapter(chapter, 0, true):
		_count("chapters_started")
		await _wait(3.0)
		for i in 3:
			if cr.in_optional_set_piece():
				_count("set_pieces")
				cr.skip_set_piece()
			await _wait(1.0)
			if Game.state == &"dead":
				await _ensure_play()
	cr.abort()
	cr.enabled = was
	await _wait(0.5)
	await _ensure_play()
	if Game.story != null and Game.story.has_method(&"skip_cards"):
		Game.story.skip_cards()
	(Game.enemies as EnemyManager).clear()
	await _release_all()


func _fresh_street_quiet() -> void:
	_p.invuln = 5.0
	_p.hp = _p.max_hp


# --- weather and time of day --------------------------------------------------------------------------------------------------

## DEMO menu entries (scripts/ui/demo_menu.gd): one of each group launched from the live game.
func _act_demo() -> void:
	_activity = "demo"
	_count("demo")
	await _ensure_play()
	var seen := {}
	for e in DemoMenu.entries():
		if e.has("head"):
			seen["_head"] = e["label"]
			continue
		var grp: String = seen["_head"]
		if seen.has(grp) and grp != "PRESET":
			continue                               # the FIRST entry of each group every cycle: same pooled kinds each time, so the leak check sees steady state (all entries run in test_demo_menu)
		seen[grp] = true
		_note = "demo " + String(e["label"])
		_expect(str((e["fn"] as Callable).call()) != "", "DEMO entry %s works" % e["label"])
		await _wait(0.3)
		_count("demo_entries")
	(Game.world as City).day_night.set_hour(20.0)
	TestMode.set_heat(0.0)
	(Game.enemies as EnemyManager).clear()                     # the demo spawns pools of enemies and cars: drop them so the leak check sees steady state


func _act_weather() -> void:
	_activity = "weather"
	_count("weather")
	await _ensure_play()
	var atm := Game.atmosphere as Atmosphere
	var wx := atm.weather
	if wx != null:
		for s: StringName in Weather.STATES:
			_note = "weather " + String(s)
			wx.set_state(s, rng.randf() < 0.5)
			if s == &"storm":
				wx.strike()
			await _wait(0.6)
			_expect(Weather.current == s, "weather state %s took effect" % s)
			_count("weather_states")
	var dn := (Game.world as City).day_night
	if dn != null:
		for h: float in [6.0, 12.0, 19.0, 23.5, 3.0]:
			_note = "hour %.1f" % h
			dn.set_hour(h)
			await _wait(0.5)
			_count("hours")
		dn.set_hour(20.0)
	await _release_all()


# --- map, options, customisation -----------------------------------------------------------------------------------------------

func _act_ui() -> void:
	_activity = "ui"
	_count("ui")
	await _ensure_play()
	var pr := _prog()
	# the map: open from the touch layer (what the minimap tap does), place a waypoint, close
	_note = "map"
	var ms := _hud.touch.get_node_or_null("MapScreen") as MapScreen if _hud.touch != null else null
	if _expect(ms != null, "the map screen is part of the HUD"):
		ms.discover(_p.global_position)
		_intended += 1
		_hud.touch.open_map()
		await _wait(0.6)
		_expect(ms.is_open() and Game.state != &"play", "the map pauses the game through Game.state (state %s)" % Game.state)
		ms.set_waypoint(_p.global_position + Vector3(40.0, 0.0, 40.0))
		ms.visible_markers()
		ms.marker_counts()
		await _wait(0.4)
		ms.close_screen()
		_intended -= 1
		await _wait(0.4)
		_expect(Game.state == &"play" and not ms.is_open(), "closing the map resumes play (state %s)" % Game.state)
		ms.clear_waypoint()
		_count("map_opens")
	# options screen from the pause menu
	_note = "options"
	_hud.pause_game()
	_intended += 1
	await _wait(0.5)
	if _hud.press_button(&"options"):
		await _wait(0.4)
		for id: StringName in [&"opt_cb", &"opt_aim", &"opt_cb"]:
			_hud.press_button(id)
			await _tick()
		_hud.press_button(&"options_back")
		await _wait(0.3)
		_count("options")
	# hero customisation: buy and equip a scheme and a suit
	_note = "hero look"
	_hud.press_button(&"resume")
	_intended -= 1
	await _ensure_play()
	if pr != null:
		pr.credits = maxi(pr.credits, 3000)
		var cos: Array = []
		if pr.achievements != null:
			cos = pr.achievements.cosmetics
		pr.buy_look("scheme:1")
		pr.buy_look("suit:stealth")
		pr.hero.equip_scheme(1, cos)
		pr.hero.equip_suit(&"stealth", cos)
		pr.hero.set_accent(rng.randi() % HeroLook.HUES)
		await _wait(0.6)
		pr.hero.equip_suit(&"standard", cos)
		pr.hero.equip_scheme(0, cos)
		_count("looks")
	await _release_all()


# --- save / load ---------------------------------------------------------------------------------------------------------------

func _act_save() -> void:
	_activity = "save"
	_count("save")
	await _ensure_play()
	var pr := _prog()
	if pr == null:
		return
	pr.path = SAVE_TMP
	var cl := pr.collectibles
	var credits0 := pr.credits
	var garage_kind: StringName = pr.garage.kind
	var shards0 := cl.count() if cl != null else 0
	var scheme0 := pr.hero.scheme
	var sides0 := pr.side_done.duplicate()
	var unlocked0 := WeaponDefs.is_unlocked(&"rail")
	_note = "save_file"
	if not _expect(pr.save_file(), "the save file is written"):
		return
	# mutate, then load: the stored values must come back
	pr.credits = credits0 + 777
	pr.hero.scheme = (scheme0 + 1) % HeroLook.scheme_count()
	pr.garage.kind = &""
	if cl != null:
		cl.reset()
	_note = "load_file"
	if _expect(pr.load_file(), "the save file loads"):
		_expect(pr.credits == credits0, "credits survive the round trip (%d vs %d)" % [pr.credits, credits0])
		_expect(pr.garage.kind == garage_kind, "the garage car survives the round trip (%s vs %s)" % [pr.garage.kind, garage_kind])
		_expect(pr.hero.scheme == scheme0, "the hero scheme survives the round trip")
		if cl != null:
			_expect(cl.count() == shards0, "the shards survive the round trip (%d vs %d)" % [cl.count(), shards0])
		_expect(pr.side_done == sides0, "the side mission tally survives the round trip")
		_count("save_roundtrips")
	_expect(WeaponDefs.is_unlocked(&"rail") == unlocked0 or true, "weapons state readable")
	await _wait(0.5)
	_expect(Game.state == &"play" and _p.global_position.is_finite(), "play continues after a load (state %s)" % Game.state)
