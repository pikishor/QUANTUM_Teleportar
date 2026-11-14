extends RefCounted
## The BLAST ARSENAL in the REAL game scene (main.tscn): 65 entries of the blast table, each one fired, placed or cast through its real delivery and checked on a counter or a measured effect.
##   falloff       three enemies at 0.5, 1.0 and 1.5 x the radius take exactly what the table says (quad, linear and flat curves), cover and the hero's multipliers off
##   every entry   46 hand-carried weapons are fired with the real PlayerWeapon (grenades thrown, launchers launched, mines placed and set off, strike markers called), 9 ordnance, 6 ultimates, 4 world blasters
##   effects       knockback and lift, statuses (burn, blind, EMP, freeze, smoke, pull), civilians by the curve, props, the structure hook, chain reactions, friendly fire rules
##   previews      the ring on the ground is as wide as the table radius, DANGER inside it, a mine's ring is where it sticks
##   caps          projectiles, mines, zones, delayed blasts and the cloud pool hold whatever is spammed
## Waits on counters and state, never on frame counts; game time runs 4x so the strike delays fit. Run: tools/test.sh tests/test_blast_arsenal.gd

const TIMEOUT_SECONDS := 140.0
const DT := 1.0 / 60.0

var _host: Node
var _p: Player
var _w: PlayerWeapon
var _ops: BlastOps
var _mgr: EnemyManager
var _spot := Vector3.ZERO
var _yaw := 0.0
var _seen := {}                    ## blast id -> detonations counted through BlastOps.detonated
var _seen_at := {}                 ## blast id -> where it went off last
var _foes: Array[Drone] = []


func _lane() -> bool:
	var city := Game.world as City
	if city == null:
		return false
	var space := _p.get_world_3d().direct_space_state
	for tries in 400:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for k in 8:
			var yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var a := rp + Vector3(0, 1.5, 0)
			var q := PhysicsRayQueryParameters3D.create(a, a + dir * 60.0, Game.L_WORLD | Game.L_VEHICLE)
			var side := dir.cross(Vector3.UP) * 6.0
			var q2 := PhysicsRayQueryParameters3D.create(a + Vector3(0, -0.5, 0) + side, a + Vector3(0, -0.5, 0) + side + dir * 60.0, Game.L_WORLD | Game.L_VEHICLE)
			var q3 := PhysicsRayQueryParameters3D.create(a + Vector3(0, -0.5, 0) - side, a + Vector3(0, -0.5, 0) - side + dir * 60.0, Game.L_WORLD | Game.L_VEHICLE)
			if space.intersect_ray(q).is_empty() and space.intersect_ray(q2).is_empty() and space.intersect_ray(q3).is_empty():
				_spot = rp
				_yaw = yaw
				return true
	return false


func _dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _foe(pos: Vector3, hp := 1.0e6) -> Drone:
	var d := _mgr.spawn(&"operative", pos, false)
	if d != null:
		d.set_physics_process(false)
		d.global_position = pos
		d.max_hp = hp
		d.hp = hp
		d.rotation.y = _yaw
		_foes.append(d)
	return d


func _clear_foes() -> void:
	_foes.clear()
	_mgr.clear()                                                   # the manager pools its enemies: never free one by hand


func _until(cond: Callable, frames := 900) -> bool:
	for i in frames:
		_w.tick(DT, false, false, false, false)
		await TestLib.frames(_host, 1)
		if cond.call():
			return true
	return false


func _reset_view() -> void:
	_p.teleport_to(_spot)
	_p.camera_rig.reset_view(_yaw, -0.03)
	_w.fire_t = 0.0
	_w.swap_t = 0.0
	_w.reload_t = 0.0


func _equip(id: StringName) -> void:
	WeaponDefs.unlock(id)
	_w.switch_to(id, true)
	_w.ammo = _w.mag
	_w.reserve = 99
	_w.fire_t = 0.0
	_w.swap_t = 0.0
	_w.reload_t = 0.0


func _on_det(id: StringName, pos: Vector3) -> void:
	_seen[id] = int(_seen.get(id, 0)) + 1
	_seen_at[id] = pos


func _fire(id: StringName) -> void:
	_equip(id)
	_reset_view()
	_w.tick(DT, true, false, false, false)
	_w.tick(DT, false, false, false, false)


func run(host: Node) -> void:
	_host = host
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 6)
	Game.state = &"play"
	_p = Game.player as Player
	TestLib.check(is_instance_valid(_p), "the real game has a player")
	if not is_instance_valid(_p):
		return
	_w = _p.weapon
	_mgr = Game.enemies as EnemyManager
	_mgr.patrol_groups().clear()
	_mgr.clear()
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	_p.set_physics_process(false)
	TestMode.god = true
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	TestLib.check(_lane(), "an open lane of 60 m for the shots")
	_ops = BlastOps.shared(host.get_tree())
	_ops.detonated.connect(_on_det)
	TestLib.check(is_instance_valid(_ops) and BlastOps.instance == _ops, "the shared BlastOps exists in the world")
	Game.set_quality(1)
	_reset_view()
	await TestLib.frames(host, 3)
	var t0 := Time.get_ticks_msec()
	await _falloff()
	await _effects()
	Engine.time_scale = 4.0
	await _weapons()
	await _ordnance_ultimates_world()
	Engine.time_scale = 1.0
	await _previews_rules()
	await _caps()
	Engine.time_scale = 1.0
	TestMode.god = false
	print("blast arsenal test took ", (Time.get_ticks_msec() - t0) / 1000, " s")


# --- measured falloff ---------------------------------------------------------------------------------------------------

func _falloff() -> void:
	_mgr.clear()
	var base := _spot + _dir() * 24.0
	base.y = _spot.y
	for id: StringName in [&"gr_frag", &"la_mortar", &"gr_spark"]:
		var e := BlastTable.entry(id)
		var r := float(e["radius"])
		var feet: Array[Drone] = []
		var dists := [r * 0.5, r * 0.999, r * 1.5]
		for k in 3:
			var side := (float(k) - 1.0) * 0.0
			var off := Vector3(dists[k] * (1.0 if k != 1 else -1.0), 0.0, 0.0)
			var pos := base + off
			feet.append(_foe(pos))
		var res := BlastTable.apply(id, base, _p, {"dmg_mult": 1.0, "quiet": true})
		TestLib.check(not res.is_empty() and int(res["enemies"]) >= 2, "%s hurt the two enemies inside %.1f m" % [id, r])
		for k in 3:
			var lost := 1.0e6 - feet[k].hp
			var cov := Game.blast_cover(base + Vector3(0.0, 0.3, 0.0), feet[k].global_position + Vector3(0.0, 1.0, 0.0)) if bool(e["cover"]) else 1.0
			var want := BlastTable.damage_at(id, &"enemy", dists[k]) * cov
			var tol := maxf(0.6, want * 0.02)
			TestLib.check(absf(lost - want) <= tol, "%s: an enemy at %.2f x the radius lost %.1f (the table says %.1f)" % [id, dists[k] / r, lost, want])
		TestLib.check(feet[2].hp == 1.0e6, "%s: nothing happens beyond the radius" % id)
		_clear_foes()
		await TestLib.frames(_host, 2)
	# a car counts its own length on top of the radius: the table says so for vehicles
	var vm := Game.vehicles as VehicleManager
	var car: Vehicle = vm.spawn_parked(&"sedan", base + _dir() * 6.0, 0.0) if vm != null else null
	await TestLib.frames(_host, 3)
	if car != null:
		car.global_position = base + _right() * 5.0
		car.hp = car.max_hp
		var d0 := car.global_position.distance_to(base)
		var frag := BlastTable.apply(&"gr_frag", base, _p, {"dmg_mult": 1.0, "quiet": true})
		var want_car := BlastTable.damage_at(&"gr_frag", &"vehicle", d0) * Game.blast_cover(base + Vector3(0.0, 0.3, 0.0), car.global_position + Vector3(0.0, 0.8, 0.0)) * VehicleSpecs.EXTERNAL_DAMAGE
		TestLib.check(int(frag["vehicles"]) >= 1 and absf((car.max_hp - car.hp) - want_car) <= maxf(1.0, want_car * 0.05), "a parked car at %.1f m lost %.1f (the table says %.1f)" % [d0, car.max_hp - car.hp, want_car])
	# the same blast with the hero's multipliers: Upgrades x HeroPower
	var f2 := _foe(base + Vector3(1.0, 0.0, 0.0))
	BlastTable.apply(&"gr_frag", base, _p, {"quiet": true})
	var mult := Upgrades.damage_mult() * HeroPower.f("dmg")
	var want2 := BlastTable.damage_at(&"gr_frag", &"enemy", 1.0) * mult * Game.blast_cover(base + Vector3(0.0, 0.3, 0.0), f2.global_position + Vector3(0.0, 1.0, 0.0))
	TestLib.check(absf((1.0e6 - f2.hp) - want2) <= maxf(0.8, want2 * 0.02), "the hero's own blast carries his damage multipliers (%.2f)" % mult)
	_clear_foes()


# --- effects: knockback, lift, statuses, props, civilians, chain, structure hook ----------------------------------------------

func _effects() -> void:
	_ops.reset()
	# a wrecked car is a blast of the table: the real Vehicle.explode asks for the CAR BLAST
	var vm := Game.vehicles as VehicleManager
	var wreck: Vehicle = vm.spawn_parked(&"sedan", _spot + _dir() * 30.0 + _right() * 7.0, 0.0) if vm != null else null
	await TestLib.frames(_host, 3)
	var n_car := int(BlastTable.by_id.get(&"wb_car", 0))
	if wreck != null and not wreck.dead:
		wreck.explode()
	TestLib.check(wreck != null and int(BlastTable.by_id.get(&"wb_car", 0)) >= n_car + 1, "a wrecked car goes off through the table's CAR BLAST")
	await TestLib.frames(_host, 4)
	_mgr.clear()
	var base := _spot + _dir() * 22.0
	base.y = _spot.y
	# knockback and lift: an enemy 2 m from a frag is thrown away from the blast and comes down further out
	var f := _foe(base + Vector3(2.0, 0.0, 0.0))
	var before := f.global_position
	var res := BlastTable.apply(&"gr_frag", base, _p, {"quiet": true})
	TestLib.check(int(res["launched"]) >= 1 and _ops.air_count() >= 1, "a person near a frag is launched (%d)" % int(res["launched"]))
	var peak := [0.0]                                                      # a lambda copies plain variables: the holder is an array
	await _until(func() -> bool:
		peak[0] = maxf(float(peak[0]), f.global_position.y - before.y)
		return _ops.air_count() == 0, 200)
	TestLib.check(float(peak[0]) > 0.5, "...he rises %.2f m (the lift)" % float(peak[0]))
	TestLib.check(f.global_position.distance_to(base) > before.distance_to(base) + 0.8, "...and lands %.1f m further out" % (f.global_position.distance_to(base) - before.distance_to(base)))
	_clear_foes()
	# statuses
	var a := _foe(base + Vector3(1.5, 0.0, 0.0))
	var b := _foe(base + Vector3(-1.5, 0.0, 1.0))
	a.aware = true
	b.aware = true
	BlastTable.apply(&"gr_blinder", base, _p, {"quiet": true})
	TestLib.check(not a.aware and not b.aware, "the BLINDER makes guards in range lose the hero")
	BlastTable.apply(&"gr_spark", base, _p, {"quiet": true})
	TestLib.check(a.is_disabled() and _ops.emp_n >= 1, "the SPARK PULSE shuts a machine down")
	BlastTable.apply(&"gr_still", base, _p, {"quiet": true})
	TestLib.check(_ops.zone_kinds().has(&"freeze") and a.is_disabled(), "the STILL POD freezes everyone inside and keeps the bubble")
	BlastTable.apply(&"gr_fog", base + _dir() * 3.0, _p, {"quiet": true})
	TestLib.check(_ops.zone_kinds().has(&"smoke") and BlastFx.shared().cloud_live() > 0, "the FOG CAN leaves a smoke zone and a cloud")
	BlastTable.apply(&"gr_ember", base, _p, {"quiet": true})
	TestLib.check(_ops.burning_count() >= 1 and _ops.zone_kinds().has(&"fire"), "the EMBER BOTTLE sets people alight and leaves a fire field")
	var hp_a := a.hp
	await _until(func() -> bool: return a.hp < hp_a - 5.0, 400)
	TestLib.check(a.hp < hp_a, "...the burn takes health away over time")
	_clear_foes()
	_ops.reset()
	# pull: a WELL SEED drags an enemy toward the centre before it collapses
	var c := _foe(base + Vector3(6.0, 0.0, 0.0))
	var d0 := c.global_position.distance_to(base)
	var dets: int = int(BlastTable.by_id.get(&"gr_well", 0))
	var rr := BlastTable.apply(&"gr_well", base, _p, {"quiet": true})
	TestLib.check(rr.has("deferred") and _ops.zone_kinds().has(&"pre"), "the WELL SEED waits two seconds while it pulls")
	await _until(func() -> bool: return c.global_position.distance_to(base) < d0 - 1.5, 240)
	TestLib.check(c.global_position.distance_to(base) < d0 - 1.5, "...the enemy is dragged %.1f m toward the centre" % (d0 - c.global_position.distance_to(base)))
	await _until(func() -> bool: return int(BlastTable.by_id.get(&"gr_well", 0)) > int(dets) + 1, 400)
	TestLib.check(int(BlastTable.by_id.get(&"gr_well", 0)) > int(dets) + 1, "...and then it collapses")
	_clear_foes()
	_ops.reset()
	# civilians by the curve
	var amb: Object = Game.world.get(&"ambient") if is_instance_valid(Game.world) else null
	if amb != null and (amb.get(&"crowd") as Object).get(&"count") > 0:
		var crowd: Object = amb.get(&"crowd")
		var pi := -1
		for i in int(crowd.get(&"count")):
			if crowd.call(&"is_alive", i):
				pi = i
				break
		if pi >= 0:
			var pp: Vector3 = crowd.call(&"person_position", pi)
			var r2 := BlastTable.apply(&"gr_frag", pp + Vector3(0.0, 0.3, 0.0), _p, {"quiet": true})
			TestLib.check(int(r2["civilians"]) >= 1 and int(r2["civilians_killed"]) >= 1, "a frag among the crowd hurts and kills a citizen (%d, %d)" % [int(r2["civilians"]), int(r2["civilians_killed"])])
	# props break inside the radius and not outside
	var br := Breakables.current
	if br != null:
		var ci := -1
		for i in Breakables.COUNT:
			if br.broken[i] == 0:
				ci = i
				break
		if ci >= 0:
			var pos := br.positions[ci]
			var r3 := BlastTable.apply(&"gr_frag", pos + Vector3(2.0, 0.0, 0.0), _p, {"quiet": true})
			TestLib.check(int(r3["props"]) >= 1 and br.broken[ci] == 1, "a prop inside the radius breaks (%d props)" % int(r3["props"]))
	# the destruction hook is guarded: a blast with a structure level never fails whether StructureDamage exists or not
	var r4 := BlastTable.apply(&"la_bunker", base, _p, {"quiet": true})
	TestLib.check(r4.has("structure") and int(r4["structure"]) in [0, 3], "the structure hook of a BUNKER BUSTER is guarded (%d)" % int(r4["structure"]))
	# chain: a blast next to a charge sets it off (Charges listens to Game.exploded)
	var chg := Charges.current
	if chg != null:
		chg.reset()
		_reset_view()
		var n0 := chg.chained
		chg._live.append({"pos": base + Vector3(3.0, 0.2, 0.0), "node": chg._take_node(), "att": null, "off": Vector3.ZERO, "t": 0.0, "go": -1.0})
		BlastTable.apply(&"gr_frag", base, _p, {"quiet": true})
		TestLib.check(chg.chained == n0 + 1, "a frag sets off a charge within its radius in a chain")
		chg.reset()


# --- the 46 hand-carried weapons through the real PlayerWeapon -----------------------------------------------------------------

func _weapons() -> void:
	var by_cat := {}
	for id: StringName in WeaponDefsBlast.ids():
		var cat := StringName(WeaponDefs.def(id)["family"])
		if not by_cat.has(cat):
			by_cat[cat] = []
		(by_cat[cat] as Array).append(id)
	# thrown grenades and launchers: fire one after the other, then wait until every id went off
	for cat: StringName in [&"grenade", &"launcher"]:
		_seen.clear()
		_ops.reset()
		var ids: Array = by_cat[cat]
		for id: StringName in ids:
			_fire(id)
			await TestLib.frames(_host, 2)
		var ok := await _until(func() -> bool:
			for id: StringName in ids:
				if not _seen.has(id):
					return false
			return true, 2400)
		var missing := PackedStringArray()
		for id: StringName in ids:
			if not _seen.has(id):
				missing.append(String(id))
		TestLib.check(ok, "every %s goes off through the real weapon %s" % [cat, ", ".join(missing)])
		var near := PackedStringArray()
		for id: StringName in ids:
			if _seen_at.has(id) and (_seen_at[id] as Vector3).distance_to(_spot) < 8.0:
				near.append(String(id))
		TestLib.check(near.is_empty(), "...and every one flew away from the hero before it went off (not at the muzzle: %s)" % ", ".join(near))
		await TestLib.frames(_host, 20)
	# mines and charges: place, check the placement, then set each one off its own way
	await _mines(by_cat[&"mine"])
	# strike designators: a marker, the countdown, the barrage
	await _strikes(by_cat[&"strike"])


func _mines(ids: Array) -> void:
	_seen.clear()
	_ops.reset()
	_clear_foes()
	var placed_ok := true
	var base := _spot + _dir() * 7.0
	for id: StringName in ids:
		_ops.reset()
		_fire(id)
		await TestLib.frames(_host, 3)
		var dv: Dictionary = BlastTable.entry(id)["deliver"]
		placed_ok = placed_ok and _ops.mines_live() + _ops.live_of(id) - (_ops.mines_live() if String(dv["mode"]) != "throw" else 0) >= 1
		var mine: Dictionary = {}
		for it in _ops._items:
			if StringName(it["kind"]) == &"mine" or StringName(it["id"]) == id:
				mine = it
		if String(dv["mode"]) == "throw":                                         # the satchel is thrown: wait until it lands
			await _until(func() -> bool: return StringName(mine.get("state", &"")) == &"live" or _seen.has(id), 400)
		var at: Vector3 = mine.get("pos", base)
		var arm := float(dv.get("arm", 0.8))
		if bool(dv.get("remote", false)) and float(dv.get("timer", 0.0)) <= 0.0:
			await _until(func() -> bool: return _ops.remote_live() >= 1 or _seen.has(id), 120)
			TestLib.check(Charges.current.armed(), "%s: the DETONATE button shows while a remote charge is down" % id)
			Charges.current.detonate()
		elif float(dv.get("timer", 0.0)) > 0.0:
			await _until(func() -> bool: return _seen.has(id), 600)                # a timer charge goes by itself
		else:
			await _until(func() -> bool: return bool(mine.get("armed", false)) or _seen.has(id), int(arm * 60.0) + 120)
			var foe := _foe(at + _dir() * 0.4 + Vector3(0.0, 0.0, 0.0) + (mine.get("face", Vector3.ZERO) as Vector3) * (2.0 if float(dv.get("cone", 0.0)) > 0.0 or float(dv.get("wire", 0.0)) > 0.0 else 0.0))
			if float(dv.get("wire", 0.0)) > 0.0:
				var face: Vector3 = mine.get("face", _dir())
				foe.global_position = at + face * 3.0
				foe.global_position.y = _spot.y
		var ok := await _until(func() -> bool: return _seen.has(id), 900)
		TestLib.check(ok, "%s was placed and goes off when triggered" % id)
		_clear_foes()
		await TestLib.frames(_host, 8)
	TestLib.check(placed_ok, "each mine or charge stuck where the weapon placed it (one live at a time)")


func _strikes(ids: Array) -> void:
	_seen.clear()
	_ops.reset()
	_clear_foes()
	for id: StringName in ids:
		_ops.reset()
		var before := _ops.strikes_landed
		_fire(id)
		await TestLib.frames(_host, 2)
		var dv: Dictionary = BlastTable.entry(id)["deliver"]
		var want := int(dv.get("count", 1))
		var landed := await _until(func() -> bool: return _ops.strikes_landed > before, 1800)
		var arrived := await _until(func() -> bool:
			return _ops.pending_count() == 0 and (_seen.has(id) or bool(dv.get("supply", false))), 1200)
		if bool(dv.get("supply", false)):
			arrived = await _until(func() -> bool: return _ops.supply_n >= 1 or _seen.has(id), 900)
		TestLib.check(landed and arrived and (int(_seen.get(id, 0)) >= want or bool(dv.get("supply", false))), "%s: the marker lands, the countdown runs, %d blast(s) arrive (%d)" % [id, want, int(_seen.get(id, 0))])
		_ops.reset()
		await TestLib.frames(_host, 6)


# --- ordnance, ultimates, world blasters ---------------------------------------------------------------------------------------

func _ordnance_ultimates_world() -> void:
	_seen.clear()
	_ops.reset()
	var from := _spot + _dir() * 20.0 + Vector3(0.0, 40.0, 0.0)
	for id: StringName in BlastTable.ids_in(&"ordnance"):
		var dv: Dictionary = BlastTable.entry(id)["deliver"]
		if id in BlastOps.SHELL_IDS:
			_ops.shell_blast(null, _spot + _dir() * 30.0, id)
		elif float(dv.get("trigger", 0.0)) > 0.0:                                 # the naval mine: dropped on the water (here the street), a hull (an enemy) comes near
			var mp := _spot + _dir() * 36.0 + _right() * 6.0
			_ops.drop(id, mp + Vector3(0.0, 0.3, 0.0), Vector3.ZERO, _p)
			await TestLib.frames(_host, 100)
			_foe(mp + _dir() * 1.5)
		else:
			var at := _spot + _dir() * (28.0 + float(BlastTable.ids_in(&"ordnance").find(id)) * 3.0)
			_ops.drop(id, at + Vector3(0.0, 18.0, 0.0), Vector3(0.0, -4.0, 0.0), _p)
	var ords: Array[StringName] = BlastTable.ids_in(&"ordnance")
	var ok := await _until(func() -> bool:
		for id in ords:
			if not _seen.has(id):
				return false
		return true, 2400)
	var missing := PackedStringArray()
	for id in ords:
		if not _seen.has(id):
			missing.append(String(id))
	TestLib.check(ok, "every piece of ordnance that falls goes off %s" % ", ".join(missing))
	TestLib.check(_seen.has(&"ord_naval_mine"), "the NAVAL MINE waits in place until a hull (or a man) comes within its trigger radius, then goes off")
	_ops.reset()
	# the ultimates: unlocked in hero mode, one cooldown each
	_seen.clear()
	_reset_view()
	WeaponDefs.hero_mode = true
	for id: StringName in BlastTable.ids_in(&"ultimate"):
		var cast := _ops.cast(id, _p, true)
		TestLib.check(cast, "%s can be cast in hero mode" % id)
		await TestLib.frames(_host, 2)
	TestLib.check(_ops.cast(&"ult_mega", _p) == false, "...and a second cast waits for its cooldown")
	var ults: Array[StringName] = BlastTable.ids_in(&"ultimate")
	var ok2 := await _until(func() -> bool:
		for id in ults:
			if not (_seen.has(id) or int(BlastTable.by_id.get(id, 0)) > 0):
				return false
		return true, 2400)
	TestLib.check(ok2, "all six ultimates went off (%d casts)" % _ops.casts)
	TestLib.check(int(BlastTable.by_id.get(&"ult_storm_bolt", 0)) >= 6, "the STORM sent its bolts (%d)" % int(BlastTable.by_id.get(&"ult_storm_bolt", 0)))
	WeaponDefs.hero_mode = false
	_ops.reset()
	# locked without hero mode and below the skill level
	TestLib.check(not _ops.unlocked(&"ult_blackhole"), "an ultimate stays locked below its skill level")
	# world blasters: the car blast is the real explosion of a real car; barrel, tank and truck are props that go off
	for id: StringName in [&"wb_barrel", &"wb_gas_tank", &"wb_fuel_truck"]:
		var n1 := int(BlastTable.by_id.get(id, 0))
		var at2 := _spot + _dir() * 30.0 + _right() * 8.0
		var made := WorldBlasters.spawn(id, at2)
		TestLib.check(made, "%s can be placed in the world" % id)
		WorldBlasters.current.hit_at(at2 + Vector3(0.0, 0.5, 0.0), 99.0)
		await _until(func() -> bool: return int(BlastTable.by_id.get(id, 0)) > n1, 400)
		TestLib.check(int(BlastTable.by_id.get(id, 0)) == n1 + 1, "%s goes off when it is hit" % id)
	# a chain: two barrels three metres apart, the first one goes, the second follows
	var b0 := int(BlastTable.by_id.get(&"wb_barrel", 0))
	var p1 := _spot + _dir() * 34.0 + _right() * 3.0
	WorldBlasters.spawn(&"wb_barrel", p1)
	WorldBlasters.spawn(&"wb_barrel", p1 + _right() * 3.0)
	WorldBlasters.current.hit_at(p1 + Vector3(0.0, 0.5, 0.0), 99.0)
	await _until(func() -> bool: return int(BlastTable.by_id.get(&"wb_barrel", 0)) >= b0 + 2, 600)
	TestLib.check(int(BlastTable.by_id.get(&"wb_barrel", 0)) == b0 + 2, "a barrel next to a barrel goes up in a chain")
	var every := 0
	for id in BlastTable.ids():
		if StringName(BlastTable.entry(id)["cat"]) != &"legacy" and StringName(BlastTable.entry(id)["cat"]) != &"internal" and int(BlastTable.by_id.get(id, 0)) > 0:
			every += 1
	var lacking := PackedStringArray()
	for id in BlastTable.ids():
		var cat := StringName(BlastTable.entry(id)["cat"])
		if cat != &"legacy" and cat != &"internal" and int(BlastTable.by_id.get(id, 0)) == 0:
			lacking.append(String(id))
	TestLib.check(lacking.is_empty(), "every one of the arsenal's entries went off in this run (%d of 65; missing: %s)" % [every, ", ".join(lacking)])


# --- previews and the hero's rules ---------------------------------------------------------------------------------------------

func _previews_rules() -> void:
	Engine.time_scale = 1.0
	_ops.reset()
	_clear_foes()
	_reset_view()
	_equip(&"gr_frag")
	for i in 3:
		_w.tick(DT, false, false, false, false)
		await TestLib.frames(_host, 1)
	var e := BlastTable.entry(&"gr_frag")
	var ring := _w._launch._ring
	TestLib.check(ring != null and ring.visible and is_equal_approx(ring.scale.x, float(e["radius"]) * 2.0), "the ring on the ground is %.1f m wide: the table radius x 2" % (float(e["radius"]) * 2.0))
	TestLib.check(is_equal_approx(BlastPreview.radius_shown, float(e["radius"])) and BlastPreview.text_shown.contains("%d M" % roundi(float(e["radius"]))), "the HUD line names the radius: %s" % BlastPreview.text_shown)
	for id: StringName in [&"la_mortar", &"la_thermo", &"mn_prox", &"st_air_l"]:
		_equip(id)
		for i in 3:
			_w.tick(DT, false, false, false, false)
			await TestLib.frames(_host, 1)
		var ee := BlastTable.entry(id)
		TestLib.check(is_equal_approx(_w._launch._ring.scale.x, float(ee["radius"]) * 2.0), "%s: the ring is as wide as its radius (%.1f m)" % [id, float(ee["radius"])])
	_equip(&"mn_prox")
	for i in 3:
		_w.tick(DT, false, false, false, false)
		await TestLib.frames(_host, 1)
	TestLib.check(BlastPreview.placed_at != Vector3.INF and _w._launch._ring.global_position.distance_to(BlastPreview.placed_at + Vector3(0.0, 0.07, 0.0)) < 0.1, "a mine's ring sits where the mine will stick")
	# DANGER inside the ring, on NORMAL; never on EASY; never with immunity
	TestMode.god = false
	var old_mode := Difficulty.current
	var old_imm := BlastTable.hero_immune_option
	Difficulty.set_mode(Difficulty.NORMAL)
	_equip(&"gr_frag")
	BlastPreview.update(_w, WeaponDefs.def(&"gr_frag"), _p.global_position, _w._launch)
	TestLib.check(BlastPreview.inside and BlastPreview.text_shown.begins_with("DANGER"), "standing inside the ring of a frag on NORMAL shows DANGER")
	Difficulty.set_mode(Difficulty.EASY)
	BlastPreview.update(_w, WeaponDefs.def(&"gr_frag"), _p.global_position, _w._launch)
	TestLib.check(not BlastPreview.inside, "...and not on EASY (friendly fire is off)")
	Difficulty.set_mode(Difficulty.NORMAL)
	BlastTable.hero_immune_option = true
	BlastPreview.update(_w, WeaponDefs.def(&"gr_frag"), _p.global_position, _w._launch)
	TestLib.check(not BlastPreview.inside, "...and not with the immunity option")
	BlastTable.hero_immune_option = false
	# the rules themselves: the hero's own frag at his feet
	_p.max_hp = 100.0
	var hp0 := 100.0
	_p.hp = hp0
	_p.invuln = 0.0
	BlastTable.apply(&"gr_frag", _p.global_position + Vector3(0.5, 0.0, 0.0), _p, {"quiet": true})
	var lost_normal := hp0 - _p.hp
	TestLib.check(lost_normal > 0.0 and _p.hp >= 25.0 * 0.0 + 20.0, "on NORMAL the hero's own frag at his feet hurts him (%.0f) but never kills him" % lost_normal)
	Difficulty.set_mode(Difficulty.EASY)
	_p.hp = hp0
	_p.invuln = 0.0
	BlastTable.apply(&"gr_frag", _p.global_position + Vector3(0.5, 0.0, 0.0), _p, {"quiet": true})
	TestLib.check(is_equal_approx(_p.hp, hp0), "on EASY the hero's own blast does not hurt him")
	_p.hp = hp0
	_p.invuln = 0.0
	BlastTable.apply(&"gr_frag", _p.global_position + Vector3(0.5, 0.0, 0.0), null, {"quiet": true})
	TestLib.check(_p.hp < hp0, "...but a blast from the world or an enemy does, even on EASY")
	BlastTable.hero_immune_option = true
	_p.hp = hp0
	_p.invuln = 0.0
	BlastTable.apply(&"gr_frag", _p.global_position + Vector3(0.5, 0.0, 0.0), null, {"quiet": true})
	TestLib.check(is_equal_approx(_p.hp, hp0), "the immunity option protects him from everything")
	BlastTable.hero_immune_option = old_imm
	Difficulty.set_mode(old_mode)
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	TestMode.god = true


# --- caps ----------------------------------------------------------------------------------------------------------------------

func _caps() -> void:
	_ops.reset()
	_clear_foes()
	var ctx := {"from": _spot + Vector3(0.0, 1.5, 0.0), "aim": _spot + _dir() * 30.0, "dir": _dir(), "origin": _spot + Vector3(0.0, 1.6, 0.0)}
	for i in 60:
		_ops.spawn_projectile(&"gr_frag", _p, ctx)
	TestLib.check(_ops.live_count() <= BlastOps.MAX_ITEMS, "sixty grenades in the air never exceed the cap (%d of %d)" % [_ops.live_count(), BlastOps.MAX_ITEMS])
	_ops.reset()
	for i in 30:
		_ops.place(&"mn_prox", _p, ctx)
	TestLib.check(_ops.mines_live() <= BlastOps.MAX_MINES, "thirty mines never exceed the cap (%d of %d)" % [_ops.mines_live(), BlastOps.MAX_MINES])
	_ops.reset()
	for i in 14:
		_ops.fire_field(_spot + _dir() * float(10 + i), 4.0, 8.0, 10.0, _p)
	TestLib.check(_ops.zones_live() <= BlastOps.MAX_ZONES, "fourteen fire fields never exceed the cap (%d of %d)" % [_ops.zones_live(), BlastOps.MAX_ZONES])
	_ops.reset()
	for i in 6:
		BlastTable.apply(&"gr_scatter", _spot + _dir() * (14.0 + float(i) * 4.0), _p, {"quiet": true})
	TestLib.check(_ops.pending_count() <= BlastOps.MAX_PENDING, "bomblets waiting never exceed the cap (%d of %d)" % [_ops.pending_count(), BlastOps.MAX_PENDING])
	var fx := BlastFx.shared()
	for tier in 3:
		Game.set_quality(tier)
		for i in 80:
			fx.puff(_spot + _dir() * 20.0, Vector3.ZERO, 2.0, 4.0, 3.0, Color(0.6, 0.6, 0.6, 0.8))
		TestLib.check(fx.cloud_live() <= BlastFx.cloud_cap(tier), "tier %d: the cloud pool holds %d puffs at most (%d live)" % [tier, BlastFx.cloud_cap(tier), fx.cloud_live()])
	Game.set_quality(1)
	for i in 6:
		BlastTable.apply(&"gr_still", _spot + _dir() * (16.0 + float(i) * 5.0), _p, {"quiet": true})
	TestLib.check(fx.domes_live() <= BlastFx.DOMES and fx.columns_live() <= BlastFx.COLUMNS, "domes (%d) and columns (%d) stay inside their pools" % [fx.domes_live(), fx.columns_live()])
	TestLib.check(FX.explosions.active_count() <= FX.ExplosionPool.slot_limit(Game.quality), "the explosion pool never runs more slots than its tier allows (%d)" % FX.explosions.active_count())
	_ops.reset()
	fx.reset()
