extends RefCounted
## QUANTUM SNAKE COMBAT in the real scene (main.tscn, the real hero, the real city, real enemies and cars): the tables (ten verbs, twelve bombs registered in the BlastTable, radii, rows), the skill
## column, energy and cooldowns, every verb on a dummy enemy and on a car (PULL, GRAB and throw, DISARM and the borrowed gun, YANK COVER, NET, LASH combo and takedown, SHIELD, DECOY, TRAP, GUARD), every
## bomb (spawns, goes off by its table radius, damages, applies its status, preview ring equals the table radius), the tier caps of the snakes, the weapon wheel (wedges, rings, arming, the gun stays quiet),
## the ABILITY wheel quick casts, the reactions (panic, a cut tendril, the jammer, the hunter's static net, the filming crowd) and the two board missions. Waits on counters and state, never on frame
## counts; user:// state is reset.
## Run: tools/test.sh tests/test_snake_combat.gd   (about 120 s)

const TIMEOUT_SECONDS := 140.0

var host: Node
var p: Player
var war: SnakeWar
var main: Node
var hud: Hud
var tc: TouchControls
var _spot := Vector3.ZERO
var _yaw := 0.0
var _foes: Array[Drone] = []
var _car: Vehicle


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func until(cond: Callable, secs: float) -> bool:
	var n := int(secs * 60.0)
	while n > 0 and not cond.call():
		await frames(1)
		n -= 1
	return cond.call()


func _dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _lane() -> bool:
	var city := Game.world as City
	if city == null:
		return false
	var space := p.get_world_3d().direct_space_state
	for tries in 600:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for k in 8:
			var yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var a := rp + Vector3(0, 1.5, 0)
			var ok := true
			for off in [-5.0, 0.0, 5.0]:
				var side := dir.cross(Vector3.UP) * float(off)
				var q := PhysicsRayQueryParameters3D.create(a + side, a + side + dir * 64.0, Game.L_WORLD | Game.L_VEHICLE)
				if not space.intersect_ray(q).is_empty():
					ok = false
					break
			if ok:
				_spot = rp
				_yaw = yaw
				return true
	return false


## A clean stage: no enemies, no snakes, the hero on the lane looking down it; `n` dummy operatives `dist` metres ahead (they cannot die and do not move); a parked car when `car`.
func _stage(n := 3, dist := 10.0, car := false, hp := 1.0e6) -> void:
	var sw := SnakeSwarm.current
	if sw != null:
		sw.clear()
	war.reset()
	war.disarm()
	if SnakeTendrilPool.current != null:
		SnakeTendrilPool.current.clear()
	var ops := BlastOps.shared(p.get_tree())
	ops.reset()
	(Game.enemies as EnemyManager).clear()
	_foes.clear()
	p.teleport_to(_spot)
	p.camera_rig.reset_view(_yaw, -0.06)
	p.velocity = Vector3.ZERO
	p.snake.cancel()
	p.snake.energy = SnakePower.max_energy()
	p.snake.jam_t = 0.0
	war.cd.clear()
	var at := _spot + _dir() * dist
	for k in n:
		var pos := at + _right() * (float(k - (n - 1) / 2.0) * 2.4) + _dir() * (float(k % 2) * 1.6)
		pos.y = _spot.y
		var f := (Game.enemies as EnemyManager).spawn(&"operative", pos, false)
		if f != null:
			f.set_physics_process(false)
			f.global_position = pos
			f.max_hp = hp
			f.hp = hp
			f.rotation.y = _yaw + PI
			_foes.append(f)
	if car:
		var vm := Game.vehicles as VehicleManager
		vm._reset_all()
		_car = vm.spawn_parked(&"sedan", at + _right() * 9.0 + _dir() * 2.0, _yaw + PI * 0.5)
		if _car != null:
			_car.hp = _car.max_hp
	await frames(4)


func _aim(n: Node3D) -> void:
	p.camera_rig.aim_at(SnakeAim.center_of(n))


func _aim_foes() -> void:
	var c := Vector3.ZERO
	var k := 0
	for f in _foes:
		if is_instance_valid(f):
			c += SnakeAim.center_of(f)
			k += 1
	if k > 0:
		p.camera_rig.aim_at(c / float(k))


func _hp_lost() -> float:
	var lost := 0.0
	for f in _foes:
		if is_instance_valid(f):
			lost += f.max_hp - f.hp
	return lost


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	SnakeWarMissions.reset_flags()
	SnakeMissions.reset_flags()
	SkillTree.reset()
	var mode0 := Difficulty.current
	var touch0 := Game.force_touch
	Game.force_touch = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	hud = Game.get_tree().root.find_child("Hud", true, false) as Hud
	tc = hud.touch if hud != null else null
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Game.state = &"play"
	TestMode.god = true
	Difficulty.set_mode(1)
	WeaponDefs.hero_mode = false
	war = SnakeWar.of(p)
	TestLib.check(war != null and war.p == p and war.swarm != null and war.holds != null and war.verbs != null and war.bombs != null and war.react != null, "the player owns a SnakeWar with its swarm, holds, verbs, bombs and reactions")
	if not _lane():
		TestLib.check(false, "an open lane in the city was found")
		return
	_tables()
	_skill()
	await _energy()
	await _pull()
	await _grab()
	await _disarm()
	await _yank()
	await _net()
	await _lash()
	await _shield()
	await _decoy()
	await _trap()
	await _guard()
	await _bombs()
	await _preview()
	await _caps()
	await _wheel()
	await _reactions()
	await _hints()
	await _missions()
	TestMode.god = false
	WeaponDefs.hero_mode = false
	war.reset()
	SnakeWarMissions.reset_flags()
	SkillTree.reset()
	Difficulty.set_mode(mode0)
	Game.force_touch = touch0
	main.queue_free()
	await frames(3)


# --- the tables ------------------------------------------------------------------------------------------------------------------------

func _tables() -> void:
	SnakeRows.ensure()
	TestLib.check(SnakeRows.VERB_IDS.size() == 10 and SnakeRows.BOMB_IDS.size() == 12, "ten snake verbs and twelve snake bombs")
	var names := {}
	var icons := {}
	var ok := true
	for id in SnakeRows.ids():
		var r := SnakeRows.row(id)
		var nm := String(r["name"])
		ok = ok and nm == nm.to_upper() and float(r["cost"]) > 0.0 and float(r["cd"]) > 0.0 and String(r["note"]) != "" and r["color"] is Color and int(r["lvl"]) >= 1
		names[nm] = true
		icons[r["icon"]] = true
	TestLib.check(ok and names.size() == 22 and icons.size() == 22, "every power has a plain upper-case name, a cost, a cooldown, a note, a colour and an icon of its own (%d names, %d icons)" % [names.size(), icons.size()])
	var reg := true
	var ids := BlastTable.ids_in(&"snake")
	for id in SnakeRows.BOMB_IDS:
		var e := BlastTable.entry(id)
		reg = reg and not e.is_empty() and ids.has(id) and float(e["radius"]) > 0.5 and float((e["dmg"] as Dictionary)["enemy"]) >= 0.0 and StringName(e["cat"]) == &"snake" and SnakeRows.radius_of(id) == float(e["radius"])
	TestLib.check(reg and ids.size() == 12, "the twelve bombs are registered in the BlastTable (category snake) with the radius of their row (%d)" % ids.size())
	TestLib.check(BlastTable.has_entry(SnakeRows.SLAM) and BlastTable.has_entry(SnakeRows.LASH_FINISH) and BlastTable.has_entry(&"sb_bomblet"), "the internal blasts of the verbs and the cluster exist")
	var radii := {}
	for id in SnakeRows.BOMB_IDS:
		radii[snappedf(float(BlastTable.entry(id)["radius"]), 0.1)] = true
	TestLib.check(radii.size() >= 9, "the bombs have different radii (%d of 12 distinct)" % radii.size())
	TestLib.check(float(BlastTable.entry(&"sb_mega")["radius"]) >= 20.0 and float(BlastTable.entry(&"sb_flare")["radius"]) >= 10.0 and float(BlastTable.entry(&"sb_coil")["radius"]) < 6.0, "from the coil bomb (small) to the flare (wide) to the MEGA PYTHON (a street)")
	var falloff := BlastTable.damage_at(&"sb_coil", &"enemy", 0.5) > BlastTable.damage_at(&"sb_coil", &"enemy", 4.4) and BlastTable.damage_at(&"sb_coil", &"enemy", 5.5) == 0.0
	TestLib.check(falloff, "the coil bomb's damage falls with the distance and is zero beyond its radius")
	var bad_brand := false
	for id in SnakeRows.ids():
		var words := String(SnakeRows.row(id)["name"]).split(" ")
		for w in ["GLOCK", "UZI", "AK47", "M4", "NERF", "MARVEL", "SPIDER", "VENOM", "CARNAGE", "BATMAN"]:
			bad_brand = bad_brand or words.has(w)
	TestLib.check(not bad_brand, "no real brand names in the power names")
	TestLib.check(SnakeRows.unlocked(&"sv_pull") and SnakeRows.unlocked(&"sb_coil") and not SnakeRows.unlocked(&"sb_mega") and not SnakeRows.unlocked(&"sb_storm"), "verbs and the first bombs are open from the start, the storm cobra and the mega python are not")
	WeaponDefs.hero_mode = true
	TestLib.check(SnakeRows.unlocked(&"sb_mega") and SnakeRows.unlocked(&"sb_storm"), "HERO MODE opens every snake power")
	WeaponDefs.hero_mode = false


func _skill() -> void:
	TestLib.check(SkillTree.VERBS.has(&"snakewar") and SkillTree.verb_nodes(&"snakewar").size() == 5 and SkillTree.title(&"sw_bite") == "BITE", "the skill tree has the SNAKE COMBAT column: BITE, COIL SPREAD, QUICK COIL, BIGGER BROOD, TIGHT GRIP")
	SkillTree.reset()
	var d0 := war.dmg_mult()
	var r0 := war.radius_mult()
	var c0 := war.cd_of(&"sb_coil")
	SkillTree.ranks[&"sw_bite"] = 3
	SkillTree.ranks[&"sw_spread"] = 3
	SkillTree.ranks[&"sw_quick"] = 3
	SkillTree.ranks[&"sw_brood"] = 2
	SkillTree.ranks[&"sw_grip"] = 3
	TestLib.check(war.dmg_mult() > d0 * 1.3 and war.radius_mult() > r0 * 1.2 and war.cd_of(&"sb_coil") < c0 * 0.8 and war.brood_extra() >= 5 and SkillTree.snakewar_grip() > 1.5, "the five nodes raise the damage, the bomb radius, the speed of the cooldown, the brood and the holds")
	SkillTree.reset()
	TestLib.check(SkillTree.LEVEL_CAP == 46 and SkillTree.ids().size() == 30, "six columns of five nodes and a level cap that still keeps the tree from being filled")


# --- energy and cooldown ---------------------------------------------------------------------------------------------------------------

func _energy() -> void:
	await _stage(3, 10.0)
	var e0 := p.snake.energy
	var cost := war.cost_of(&"sv_pull")
	TestLib.check(cost > 0.0 and cost <= SnakePower.max_energy(), "SNAKE PULL costs snake energy (%.1f)" % cost)
	var ok := war.cast(&"sv_pull")
	TestLib.check(ok and absf((e0 - p.snake.energy) - cost) < 0.8 and war.cd_left(&"sv_pull") > 0.0, "a cast pays its energy and starts its cooldown")
	var again := war.cast(&"sv_pull")
	TestLib.check(not again and war.last_denied.begins_with("READY"), "a second cast at once is refused by the cooldown (%s)" % war.last_denied)
	await until(func() -> bool: return war.cd_left(&"sv_pull") <= 0.0, 4.0)
	p.snake.energy = 0.0
	var dry := war.cast(&"sv_pull")
	TestLib.check(not dry and war.last_denied == "SNAKE ENERGY", "an empty snake bar refuses a cast (%s)" % war.last_denied)
	WeaponDefs.hero_mode = true
	p.snake.energy = 0.0
	war.cd.clear()
	var free := war.cast(&"sv_pull", false)
	TestLib.check(free, "HERO MODE casts with an empty bar")
	WeaponDefs.hero_mode = false
	p.snake.energy = SnakePower.max_energy()
	var regen0 := 5.0
	p.snake.energy = regen0
	await until(func() -> bool: return p.snake.energy > regen0 + 8.0, 6.0)
	TestLib.check(p.snake.energy > regen0 + 8.0, "the bar fills again by itself (%.1f)" % p.snake.energy)
	p.snake.jam(2.0)
	war.cd.clear()
	p.snake.energy = 100.0
	TestLib.check(not war.cast(&"sv_net") and war.last_denied == "SNAKE JAMMED", "a jammed hero casts nothing")
	p.snake.jam_t = 0.0


# --- the verbs -------------------------------------------------------------------------------------------------------------------------

func _pull() -> void:
	await _stage(1, 10.0, true)
	var en := _foes[0]
	_aim(en)
	await frames(3)
	war.arm(&"sv_pull")
	TestLib.check(SnakeWar.holding() and war.armed == &"sv_pull", "arming a power puts it in the hand")
	var d0 := en.global_position.distance_to(p.global_position)
	var pulls0 := war.verbs.pulls
	TestLib.check(war.cast(&"sv_pull"), "SNAKE PULL finds the enemy under the crosshair")
	await until(func() -> bool: return war.holds.drags >= 1 and en.global_position.distance_to(p.global_position) < 4.2, 3.0)
	TestLib.check(war.verbs.pulls == pulls0 + 1 and war.holds.drags >= 1 and en.global_position.distance_to(p.global_position) < d0 - 4.0, "the enemy is dragged to the hero (%.1f m before, %.1f m after)" % [d0, en.global_position.distance_to(p.global_position)])
	TestLib.check(war.holds.is_held(en) or en.hp < en.max_hp, "and left stunned or hurt")
	# a prop: nothing in front means a whiff that costs nothing. The lane is random (a bench, a pickup or a passing car under the crosshair is something to pull) and the global gap of the last
	# cast may still run: up to three lanes, the gap cleared, and the cause of a miss is printed (it failed now and then on a loaded machine, in the wave 115 integration: 2 of 14 runs)
	var whiffed := false
	for attempt in 3:
		if attempt > 0 and not _lane():
			break
		await _stage(0, 10.0)
		war.cd.clear()
		war._gcd = 0.0
		var e1 := p.snake.energy
		var w0 := war.whiffs
		var seen := SnakeAim.pick(p, 38.0, [&"enemy", &"pickup", &"prop", &"car"])
		var miss := war.cast(&"sv_pull")
		whiffed = not miss and war.whiffs == w0 + 1 and absf(p.snake.energy - e1) < 0.5
		if whiffed:
			break
		print("WHIFF TRY %d: cast %s, denied '%s', game %s, dead %s, whiffs %d -> %d, energy %.1f -> %.1f, under the crosshair %s" % [attempt, str(miss), war.last_denied, str(Game.state), str(p.is_dead()), w0, war.whiffs, e1, p.snake.energy, str(seen.get("kind", "nothing"))])
	TestLib.check(whiffed, "with nothing to pull the snake whiffs and no energy is spent")
	# a heavy target: a car pulls the hero to it
	await _stage(0, 11.0, true)
	if _car != null:
		var carpos := _car.global_position
		var zips0 := p.snake.zips
		p.camera_rig.aim_at(carpos + Vector3(0.0, 0.7, 0.0))
		await frames(3)
		var ok := war.verbs.press(&"sv_pull", true)
		if ok:
			await until(func() -> bool: return p.snake.zips > zips0, 3.0)
		TestLib.check(ok and p.snake.zips > zips0, "a car is heavy: SNAKE PULL zips the hero to it")
		await until(func() -> bool: return not p.snake.zip.active and p.snake.mode == SnakeTraversal.Mode.NONE, 4.0)
		var beside := Vector2(p.global_position.x - carpos.x, p.global_position.z - carpos.z).length()
		TestLib.check(beside < 9.0, "and he lands beside it (%.1f m from its middle)" % beside)
		p.snake.cancel()
	war.disarm()
	TestLib.check(not SnakeWar.holding() and p.weapon != null, "disarming gives the gun back")


func _grab() -> void:
	await _stage(2, 9.0)
	var en := _foes[0]
	var d0 := en.global_position
	_aim(en)
	await frames(3)
	war.arm(&"sv_grab")
	var slam0 := int(BlastTable.by_id.get(SnakeRows.SLAM, 0))
	Input.action_press(&"fire")                                   # the thumb stays on FIRE while the snakes hold the body
	TestLib.check(war.cast(&"sv_grab"), "SNAKE GRAB takes hold of the enemy under the crosshair")
	await until(func() -> bool: return war.verbs.is_grabbing() and en.global_position.y > d0.y + 0.9, 2.5)
	TestLib.check(en.global_position.y > d0.y + 0.9 and war.holds.is_held(en), "the grabbed enemy hangs in the snakes above the street (%.1f m up)" % (en.global_position.y - d0.y))
	var hp0 := en.hp
	Input.action_release(&"fire")                                  # letting go throws
	await until(func() -> bool: return war.verbs.slams >= 1, 4.0)
	TestLib.check(war.verbs.throws >= 1 and war.verbs.slams >= 1 and int(BlastTable.by_id.get(SnakeRows.SLAM, 0)) > slam0, "letting go throws him and the landing is a blast of the table (sv_slam)")
	TestLib.check(en.hp < hp0 or _foes[1].hp < _foes[1].max_hp, "and it hurts")
	TestLib.check(en.global_position.distance_to(d0) > 1.0 or en.global_position.y < d0.y + 0.5, "the body has been thrown, not left in the air")
	war.disarm()


func _disarm() -> void:
	await _stage(1, 9.0)
	var en := _foes[0]
	var gun0 := p.weapon.current
	_aim(en)
	await frames(3)
	war.arm(&"sv_disarm")
	var n0 := war.verbs.disarms
	TestLib.check(war.cast(&"sv_disarm") and war.verbs.disarms == n0 + 1, "SNAKE DISARM snatches the gun of the enemy under the crosshair")
	await until(func() -> bool: return war.verbs.loan.has("id"), 2.0)
	TestLib.check(war.verbs.loan.has("id") and p.weapon.current == StringName(war.verbs.loan["id"]) and not SnakeWar.holding(), "the hero holds that gun now (%s)" % str(p.weapon.current))
	await until(func() -> bool: return war.holds.disarms >= 1, 2.0)
	TestLib.check(war.holds.disarms >= 1, "and the enemy's shot timer is pushed out")
	war.verbs.loan["left"] = 0.05
	await until(func() -> bool: return not war.verbs.loan.has("id"), 2.0)
	TestLib.check(p.weapon.current == gun0, "after twelve seconds the borrowed gun is gone and the old one is back (%s)" % str(p.weapon.current))
	TestLib.check(not WeaponDefs.unlocked.has(&"battle") or gun0 == &"battle", "a loan is not kept in the save")


func _yank() -> void:
	await _stage(2, 11.0, true)
	if _car == null:
		return
	var carpos := _car.global_position
	p.camera_rig.aim_at(carpos + Vector3(0.0, 0.7, 0.0))
	await frames(3)
	var hp0 := _car.hp
	war.arm(&"sv_yank")
	var ok := war.cast(&"sv_yank")
	TestLib.check(ok, "YANK COVER finds a car under the crosshair")
	await until(func() -> bool: return _car.hp < hp0 - 20.0, 3.0)
	TestLib.check(war.verbs.yanks >= 1 and _car.hp < hp0 - 20.0, "the cover is torn away and wrecked (%d of %d hit points left)" % [int(_car.hp), int(hp0)])
	war.disarm()


func _net() -> void:
	await _stage(3, 11.0)
	_aim_foes()
	await frames(3)
	war.arm(&"sv_net")
	var n0 := war.holds.nets
	TestLib.check(war.cast(&"sv_net"), "SNAKE NET goes off over the enemies")
	await until(func() -> bool: return war.holds.nets >= n0 + 3, 3.0)
	var held := 0
	var disabled := 0
	for f in _foes:
		if war.holds.is_held(f):
			held += 1
		if f.is_disabled():
			disabled += 1
	TestLib.check(held == 3 and disabled == 3, "all three enemies in the net are wrapped and cannot act (%d held, %d disabled)" % [held, disabled])
	TestLib.check(war.holds.kind_of(_foes[0]) == &"net" and bool(war.holds.recs[_foes[0].get_instance_id()]["disarm"]), "the net also takes the gun out of their hands")
	TestLib.check(SnakeSwarm.current.count() >= 3, "and the net and its coils are drawn")
	war.disarm()


func _lash() -> void:
	await _stage(2, 5.0)
	war.arm(&"sv_lash")
	var hp0 := _hp_lost()
	var l0 := war.verbs.lashes
	for k in 3:
		war.verbs._lash_cd = 0.0
		war.cd.clear()
		war._gcd = 0.0
		var ok := war.verbs._lash(false, true)
		TestLib.check(ok, "lash %d lands on the nearest enemy" % (k + 1))
		await until(func() -> bool: return war.verbs.bites >= k + 1, 1.5)
	TestLib.check(war.verbs.lashes == l0 + 3 and _hp_lost() > hp0 + 40.0, "three lashes hurt (%.0f damage)" % (_hp_lost() - hp0))
	war.verbs._lash_cd = 0.0
	war.cd.clear()
	war._gcd = 0.0
	var f0 := war.verbs.finishers
	war.verbs._lash(false, true)
	await until(func() -> bool: return war.verbs.finishers > f0 or war.verbs.takedowns > 0, 1.5)
	TestLib.check(war.verbs.finishers > f0 or war.verbs.takedowns > 0, "the fourth lash is the finisher")
	# a stunned enemy goes down at once
	await _stage(1, 4.0, false, 400.0)
	var en := _foes[0]
	en.call(&"disable", 5.0)
	war.verbs._lash_step = 3
	war.verbs._lash_t = 1.0
	war.verbs._lash_cd = 0.0
	war.cd.clear()
	war._gcd = 0.0
	war.verbs._lash(true, true)
	await until(func() -> bool: return en.dead or war.verbs.takedowns > 0, 2.0)
	TestLib.check(war.verbs.takedowns >= 1 and (en.dead or en.hp <= 0.0), "a stunned enemy is taken down with one lash")
	war.disarm()


func _shield() -> void:
	await _stage(0, 10.0)
	TestMode.god = false
	p.invuln = 0.0
	p.hp = p.max_hp
	war.arm(&"sv_shield")
	TestLib.check(war.cast(&"sv_shield") and not war.verbs.shield.is_empty(), "SNAKE SHIELD puts snakes round the hero")
	await frames(6)
	var orbit := 0
	for b in SnakeSwarm.current.bodies:
		if b.shape == &"orbit":
			orbit += 1
	TestLib.check(orbit == 3 + clampi(Game.quality, 0, 2), "the shield draws 3 orbiting snakes on LOW, 4 on MED, 5 on HIGH (%d at tier %d)" % [orbit, Game.quality])
	var hp0 := p.hp
	var b0 := war.verbs.blocks
	p.damage(30.0, p.global_position + Vector3(6.0, 1.0, 0.0))
	TestLib.check(p.hp == hp0 and war.verbs.blocks == b0 + 1, "a shot at the hero is eaten by the snakes (health %.0f, blocks %d)" % [p.hp, war.verbs.blocks])
	var left := float(war.verbs.shield["hp"])
	war.verbs.shield["hp"] = 10.0
	p.damage(40.0, p.global_position + Vector3(6.0, 1.0, 0.0))
	TestLib.check(war.verbs.shield.is_empty() and p.hp == hp0, "the pool of the shield is used up: the snakes fall away after the last block (it held %.0f)" % left)
	p.damage(20.0, p.global_position + Vector3(6.0, 1.0, 0.0))
	TestLib.check(p.hp < hp0, "and the next shot hurts again")
	TestMode.god = true
	# the bite
	await _stage(1, 2.4)
	war.cast(&"sv_shield", true)
	var bites0 := war.verbs.bites
	await until(func() -> bool: return war.verbs.bites > bites0, 3.0)
	TestLib.check(war.verbs.bites > bites0 and _hp_lost() > 0.0, "an enemy who comes within three metres is bitten")
	war.disarm()


func _decoy() -> void:
	await _stage(1, 10.0)
	var em := Game.enemies as EnemyManager
	war.arm(&"sv_decoy")
	TestLib.check(war.cast(&"sv_decoy") and SnakeVerbs.decoy_node() != null, "SNAKE DECOY puts a coil of snakes where the crosshair is")
	await frames(2)
	em._clone_frame = -1
	TestLib.check(em.get_clone() == SnakeVerbs.decoy_node(), "the enemies' decoy target is that coil (EnemyManager.get_clone)")
	var hp0 := float(war.verbs.decoy["hp"])
	em.hit_clone()
	TestLib.check(float(war.verbs.decoy["hp"]) < hp0 and war.verbs.decoy_hits >= 1, "a bolt that crosses it damages the decoy, not the quantum clone")
	war.verbs.decoy["left"] = 0.05
	await until(func() -> bool: return SnakeVerbs.decoy_node() == null, 2.0)
	TestLib.check(SnakeVerbs.decoy_node() == null, "the decoy ends after its time")
	war.disarm()


func _trap() -> void:
	# the catch is tried on up to three lanes and the cause of a miss is printed: the first one failed now and then on a loaded machine (wave 115 integration, once in 14 runs, never in 75 probe lanes)
	var caught := false
	for attempt in 3:
		if attempt > 0 and not _lane():
			break
		await _stage(1, 12.0)
		var en := _foes[0]
		war.arm(&"sv_trap")
		war.cast(&"sv_trap", true)
		if attempt == 0:
			TestLib.check(war.verbs.trap_list.size() == 1, "SNAKE TRAP lays a coil on the ground")
		if war.verbs.trap_list.is_empty():
			print("TRAP TRY %d: no coil was laid" % attempt)
			continue
		var at: Vector3 = war.verbs.trap_list[0]["pos"]
		await frames(40)
		var c0 := war.verbs.trap_catches
		en.global_position = Vector3(at.x, en.global_position.y, at.z)
		await until(func() -> bool: return war.verbs.trap_catches > c0, 3.0)
		caught = war.verbs.trap_catches > c0 and war.holds.is_held(en) and war.verbs.trap_list.is_empty()
		if caught:
			break
		print("TRAP TRY %d: catches %d -> %d, held %s, coils %d, game %s, enemy %s at %s, coil at %s" % [attempt, c0, war.verbs.trap_catches, str(war.holds.is_held(en)), war.verbs.trap_list.size(), str(Game.state), str(is_instance_valid(en)), str(en.global_position if is_instance_valid(en) else Vector3.INF), str(at)])
	TestLib.check(caught, "the first enemy to step in is wrapped and the trap is spent")
	war.disarm()


func _guard() -> void:
	await _stage(1, 9.0)
	war.arm(&"sv_guard")
	TestLib.check(war.cast(&"sv_guard") and war.verbs.guard_list.size() >= 3, "SNAKE GUARD sends out at least three snakes (%d)" % war.verbs.guard_list.size())
	await until(func() -> bool: return war.verbs.guard_bites >= 1, 6.0)
	TestLib.check(war.verbs.guard_bites >= 1 and _hp_lost() > 0.0, "the guards hunt the enemy and bite him")
	war.disarm()


# --- the bombs -------------------------------------------------------------------------------------------------------------------------

var _base := {}


func _snapshot() -> void:
	var ops := BlastOps.shared(p.get_tree())
	_base = {"bites": war.bombs.bites, "hops": war.bombs.hops, "bolts": war.bombs.bolts, "bomblets": war.bombs.bomblets, "marks": war.bombs.marks_made, "knots": war.bombs.knots,
			"wraps": war.holds.wraps, "blind": ops.blinded_n, "bomblet_blasts": int(BlastTable.by_id.get(&"sb_bomblet", 0)), "car_hp": _car.hp if _car != null else 0.0}


func _frozen() -> int:
	var n := 0
	for f in _foes:
		if is_instance_valid(f) and f.is_disabled():
			n += 1
	return n


## Throws bomb `id` at a stage and waits for `ok.call(by_id_before)`. A throw can land on a parked car or against a lamp post, so a failed attempt is made again on another lane (three tries in all):
## the bomb has to work in an open street, not in every geometry.
func _trial(id: StringName, label: String, ok: Callable, o := {}) -> bool:
	var foes := int(o.get("foes", 3))
	var done := false
	var attempt := 0
	while attempt < 3 and not done:
		if attempt > 0:
			_lane()
		attempt += 1
		await _stage(foes, float(o.get("dist", 12.0)), bool(o.get("car", false)))
		if foes > 0:
			_aim_foes()
		elif _car != null:
			_aim(_car)
		await frames(3)
		war.arm(id)
		war.bomb_sel = id
		var base := int(war.bombs.by_id.get(id, 0))
		_snapshot()
		war.cast(id, true)
		await until(func() -> bool: return ok.call(base), float(o.get("secs", 8.0)))
		done = ok.call(base)
	TestLib.check(done, "%s%s" % [label, "" if attempt == 1 else " (on the %d. lane)" % attempt])
	return done


func _bombs() -> void:
	WeaponDefs.hero_mode = true                                   # the storm cobra and the mega python need it
	var by := func(id: StringName) -> int: return int(war.bombs.by_id.get(id, 0))
	await _trial(&"sb_coil", "the coil bomb goes off, wraps the enemies in its radius and crushes them",
		func(base: int) -> bool: return int(by.call(&"sb_coil")) > base and war.holds.wraps >= int(_base["wraps"]) + 1 and _hp_lost() > 30.0)
	TestLib.check(StringName(war.bombs.last_res.get("id", &"")) == &"sb_coil" and absf(float(war.bombs.last_res.get("radius", 0.0)) - SnakeRows.radius_of(&"sb_coil")) < 0.01, "and blasts exactly its table radius (%.1f m)" % float(war.bombs.last_res.get("radius", 0.0)))
	await _trial(&"sb_swarm", "the swarm bomb's snakes hunt the enemies and bite (three bites)",
		func(base: int) -> bool: return int(by.call(&"sb_swarm")) > base and war.bombs.bites >= int(_base["bites"]) + 3 and _hp_lost() > 30.0, {"secs": 6.0})
	TestLib.check(SnakeSwarm.current.peak >= 6, "and they are drawn as snakes (%d at most at once)" % SnakeSwarm.current.peak)
	await _trial(&"sb_flare", "the flare serpent blinds the enemies and marks them for the hero's eyes",
		func(base: int) -> bool: return int(by.call(&"sb_flare")) > base and war.bombs.marks_made > int(_base["marks"]) and war.bombs.marks.size() >= 1)
	await _trial(&"sb_freeze", "the freezing viper stops the enemies in its field (two at least)",
		func(base: int) -> bool: return int(by.call(&"sb_freeze")) > base and _frozen() >= 2)
	await _trial(&"sb_seeker", "the seeker snake drives at the enemies and blows up on them",
		func(base: int) -> bool: return int(by.call(&"sb_seeker")) > base and _hp_lost() > 50.0, {"dist": 14.0, "secs": 9.0})
	await _trial(&"sb_chain", "the chain bomb arcs from enemy to enemy (three hops)",
		func(base: int) -> bool: return int(by.call(&"sb_chain")) > base and war.bombs.hops >= int(_base["hops"]) + 3)
	await _trial(&"sb_cluster", "the cluster snake bomb throws out four bomblet snakes that blow up in a ring",
		func(base: int) -> bool: return int(by.call(&"sb_cluster")) > base and war.bombs.bomblets >= int(_base["bomblets"]) + 4 and int(BlastTable.by_id.get(&"sb_bomblet", 0)) >= int(_base["bomblet_blasts"]) + 3)
	# CONSTRICTOR MINE: laid on the ground, springs on the first foot
	var mine_ok := false
	var tries := 0
	while tries < 3 and not mine_ok:
		if tries > 0:
			_lane()
		tries += 1
		await _stage(1, 14.0)
		_aim_foes()
		await frames(3)
		war.arm(&"sb_constrict")
		var ops := BlastOps.shared(p.get_tree())
		var m0 := ops.placed_n
		war.cast(&"sb_constrict", true)
		if ops.placed_n != m0 + 1:
			continue
		var mine_pos := Vector3.INF
		for it in ops._items:
			if StringName(it.get("id", &"")) == &"sb_constrict":
				mine_pos = it["pos"]
		await frames(50)
		_foes[0].global_position = Vector3(mine_pos.x, _foes[0].global_position.y, mine_pos.z)
		await until(func() -> bool: return int(by.call(&"sb_constrict")) >= 1 and _foes[0].hp < _foes[0].max_hp, 6.0)
		mine_ok = int(by.call(&"sb_constrict")) >= 1 and _foes[0].hp < _foes[0].max_hp
	TestLib.check(mine_ok, "the constrictor mine is laid on the ground, springs when an enemy steps on it and crushes him")
	await _trial(&"sb_burrow", "the burrower goes under the parked car and wrecks it",
		func(base: int) -> bool: return int(by.call(&"sb_burrow")) > base and (_car == null or _car.dead or _car.hp < float(_base["car_hp"]) - 100.0), {"foes": 0, "dist": 16.0, "car": true, "secs": 10.0})
	await _trial(&"sb_gravity", "the gravity snake pulls the enemies into a knot and the collapse hurts them",
		func(base: int) -> bool: return int(by.call(&"sb_gravity")) >= base + 2 and war.bombs.knots > int(_base["knots"]) and _hp_lost() > 30.0, {"secs": 9.0})
	await _trial(&"sb_storm", "the storm cobra arcs lightning at the enemies (three bolts)",
		func(base: int) -> bool: return int(by.call(&"sb_storm")) > base and war.bombs.bolts >= int(_base["bolts"]) + 3 and _hp_lost() > 30.0, {"secs": 9.0})
	p.hp = p.max_hp
	await _trial(&"sb_mega", "the mega python rises and slams",
		func(base: int) -> bool: return int(by.call(&"sb_mega")) > base, {"dist": 16.0, "secs": 12.0})
	var lost := _hp_lost()
	TestLib.check(StringName(war.bombs.last_res.get("id", &"")) == &"sb_mega" and absf(float(war.bombs.last_res.get("radius", 0.0)) - 20.0) < 0.01, "with a 20 m radius (%s %.1f)" % [str(war.bombs.last_res.get("id", "")), float(war.bombs.last_res.get("radius", 0.0))])
	var all_down := true
	for f in _foes:
		all_down = all_down and (not is_instance_valid(f) or f.dead or f.max_hp - f.hp > 150.0)
	TestLib.check(lost > 150.0 or all_down, "everything in the street is flattened (%.0f damage)" % lost)
	TestLib.check(p.hp >= p.max_hp - 0.1, "the hero is not hurt by his own snakes")
	war.disarm()
	WeaponDefs.hero_mode = false


func _preview() -> void:
	await _stage(0, 10.0)
	var rows_ok := true
	var seen := []
	for id in SnakeRows.BOMB_IDS:
		WeaponDefs.hero_mode = true
		war.arm(id)
		await frames(5)
		var want := float(BlastTable.entry(id)["radius"])
		var shown := war.preview_radius
		rows_ok = rows_ok and absf(shown - want) < 0.05
		if absf(shown - want) >= 0.05:
			seen.append("%s %.2f != %.2f" % [id, shown, want])
		war.disarm()
	WeaponDefs.hero_mode = false
	TestLib.check(rows_ok, "the aim ring of every bomb is as wide as its table radius %s" % str(seen))
	war.arm(&"sv_net")
	await frames(5)
	TestLib.check(absf(war.preview_radius - SnakeRows.radius_of(&"sv_net")) < 0.05, "the aim ring of SNAKE NET shows its 6 m")
	war.disarm()


func _caps() -> void:
	var sw := SnakeSwarm.current
	var caps := {}
	for tier in 3:
		Game.quality = tier
		Game.quality_changed.emit(tier)
		await frames(2)
		sw.clear()
		for i in 70:
			sw.spawn(&"crawl", p.global_position + Vector3(float(i) * 0.3, 0.2, 3.0), {"life": 30.0, "prio": 1})
		caps[tier] = [sw.count(), sw.cap(), sw.points_per_body()]
		sw.clear()
	TestLib.check(caps[0][0] == 16 and caps[1][0] == 28 and caps[2][0] == 44, "the snakes alive at once are capped by the tier: 16 on LOW, 28 on MED, 44 on HIGH (%s)" % str(caps))
	TestLib.check(caps[0][2] < caps[1][2] and caps[1][2] < caps[2][2], "and so are the control points of a body")
	# the worst case at LOW: everything at once
	Game.quality = 0
	Game.quality_changed.emit(0)
	await _stage(3, 10.0)
	sw.reset_stats()
	WeaponDefs.hero_mode = true
	for id in [&"sv_shield", &"sv_guard", &"sv_net", &"sb_swarm", &"sb_coil", &"sb_storm", &"sb_gravity"]:
		war.cd.clear()
		war._gcd = 0.0
		war.cast(id, true)
		await frames(3)
	await frames(30)
	var pool := SnakeTendrilPool.current
	TestLib.check(sw.count() <= 16 and sw.peak <= 16, "at LOW even a shield, a guard, a net and four bombs together keep to 16 snakes (%d now, %d at most)" % [sw.count(), sw.peak])
	TestLib.check(pool == null or pool.count() <= pool.cap(), "and the hero's tendrils stay inside their cap")
	WeaponDefs.hero_mode = false
	Game.quality = 1
	Game.quality_changed.emit(1)
	await frames(3)


# --- the weapon wheel and the ability wheel ----------------------------------------------------------------------------------------------

func _wheel() -> void:
	await _stage(0, 10.0)
	var plain := WeaponWheel.items()
	var snake_plain := 0
	for it: Dictionary in plain:
		if StringName(it.get("type", &"")) == &"snake":
			snake_plain += 1
	var items := tc.wheel_items(&"weapon")                                         # the touch wheel: the weapon classes, then the two snake wedges
	var snakes: Array[Dictionary] = []
	for it: Dictionary in items:
		if StringName(it.get("type", &"")) == &"snake":
			snakes.append(it)
	TestLib.check(snake_plain == 0 and snakes.size() == 2 and snakes[0]["id"] == SnakeUi.TAB_VERBS and snakes[1]["id"] == SnakeUi.TAB_BOMBS and items.size() == plain.size() + 2, "the weapon wheel of the phone ends with the SNAKE and the SNAKE BOMB wedges (the class list itself stays weapons only)")
	tc.wheel.close()
	tc._open_wheel(&"weapon", 90, Vector2.ZERO)
	tc._wheel_finger = 90                                                          # a finger drags the wheel open from its button
	var last := tc.wheel.items.size() - 1
	var at_last := tc.wheel.item_centre(last)
	tc._wheel_held = 0.6
	tc.touch_move(90, at_last - tc.wheel.centre, at_last - tc.wheel.centre)       # wave 118: the drag is read from where the thumb went down (here Vector2.ZERO)
	TestLib.check(tc.wheel.sel == last and StringName(tc.wheel.items[last]["type"]) == &"snake", "dragging to the last disc points at the SNAKE BOMB wedge")
	tc.touch_up(90)
	TestLib.check(tc.wheel.is_open and tc.wheel.sticky and tc.wheel.items.size() == 9 and StringName(tc.wheel.items[0]["type"]) == &"snake_power", "releasing on a snake wedge opens the ring of its powers and the wheel stays (%d discs)" % tc.wheel.items.size())
	var picked_open := tc._wheel_pick(0)
	TestLib.check(not picked_open and war.armed == &"sb_coil", "a pick on the ring arms the bomb (COIL BOMB first) and the wheel closes (armed %s)" % war.armed)
	tc.wheel.close()
	tc.release_all()
	war.disarm()
	var ring := WeaponWheel.ring_items(SnakeUi.TAB_VERBS, 0, p.weapon.current)
	TestLib.check(ring.size() == 9 and StringName(ring[8]["type"]) == &"page" and StringName(ring[0]["type"]) == &"snake_power", "the ring of the verbs shows eight powers and a NEXT disc (%d discs)" % ring.size())
	var ring2 := WeaponWheel.ring_items(SnakeUi.TAB_VERBS, 1, p.weapon.current)
	TestLib.check(ring2.size() == 3, "the second page shows the last two verbs and the NEXT disc (%d)" % ring2.size())
	var bring := WeaponWheel.ring_items(SnakeUi.TAB_BOMBS, 0, p.weapon.current)
	TestLib.check(bring.size() == 9 and bring[0]["icon"] == &"sb_coil", "the ring of the bombs starts with the coil bomb")
	var locked := 0
	for it: Dictionary in WeaponWheel.ring_items(SnakeUi.TAB_BOMBS, 1, p.weapon.current):
		if StringName(it["type"]) == &"snake_power" and not bool(it["ready"]):
			locked += 1
	TestLib.check(locked >= 2, "bombs the hero has not earned yet are dimmed on the wheel (%d)" % locked)
	var pw := p.weapon
	var next := WeaponWheel.activate(snakes[0], pw)
	TestLib.check(StringName(next.get("tab", &"")) == SnakeUi.TAB_VERBS, "a pick of the SNAKE wedge opens its ring")
	WeaponWheel.activate(ring[1], pw)
	TestLib.check(war.armed == &"sv_grab" and SnakeWar.holding(), "a pick of a disc arms that power")
	# the gun keeps quiet
	var shots0 := pw.shots_fired
	Input.action_press(&"fire")
	await frames(14)
	Input.action_release(&"fire")
	TestLib.check(pw.shots_fired == shots0, "with a power in hand FIRE fires no gun")
	var gun := &"carbine" if pw.current != &"carbine" else &"pistol"
	pw.switch_to(gun, true)
	await frames(2)
	war.armed = &"sv_pull"
	war._holster(true)
	TestLib.check(SnakeWar.holding(), "(armed again by hand)")
	# a weapon pick brings the gun back: Hud / wheel call switch_to
	WeaponWheel.activate(WeaponWheel.items()[0], pw)
	await frames(2)
	TestLib.check(war.armed == &"" or not SnakeWar.holding() or pw.current != &"", "picking a weapon on the wheel works with a power armed")
	war.disarm()
	# the picture of every power
	var c := Control.new()
	host.add_child(c)
	var drawn := [0]
	c.draw.connect(func() -> void:
		for id in SnakeRows.ids():
			SnakeIcons.draw(c, id, Rect2(Vector2(10.0, 10.0), Vector2(96.0, 96.0)), Color(1, 1, 1, 0.95))
			WeaponIcons.draw(c, id, Rect2(Vector2(120.0, 10.0), Vector2(96.0, 96.0)), Color(1, 1, 1, 0.9))
		drawn[0] += 1)
	c.queue_redraw()
	await frames(3)
	TestLib.check(drawn[0] >= 1 and SnakeIcons.handles(&"sb_mega") and SnakeIcons.handles(&"sv_net") and not SnakeIcons.handles(&"carbine"), "all 22 powers draw their own picture (no script error, the weapon icons route to them)")
	c.queue_free()
	# the ability wheel
	tc._open_wheel(&"ability", -1, Vector2.ZERO)
	var abil: Array = tc.wheel.items
	var snake_abilities := 0
	for it: Dictionary in abil:
		if str(it["label"]).begins_with("SNAKE"):
			snake_abilities += 1
	TestLib.check(abil.size() == 11 and snake_abilities == 4, "the ABILITY wheel has the seven quantum verbs and four snake quick casts (%d discs)" % abil.size())
	tc.wheel.close()
	await _stage(1, 10.0)
	war.cd.clear()
	Input.action_press(&"snake_shield")
	await frames(3)
	Input.action_release(&"snake_shield")
	TestLib.check(not war.verbs.shield.is_empty() and not SnakeWar.holding(), "a quick cast of SNAKE SHIELD works with the gun in hand")
	war.cd.clear()
	war._gcd = 0.0
	Input.action_press(&"snake_net")
	await frames(3)
	Input.action_release(&"snake_net")
	TestLib.check(war.verbs.nets >= 1, "a quick cast of SNAKE NET too")
	war.bomb_sel = &"sb_coil"
	war.cd.clear()
	war._gcd = 0.0
	var t0 := war.bombs.thrown
	Input.action_press(&"snake_bomb")
	await frames(3)
	Input.action_release(&"snake_bomb")
	TestLib.check(war.bombs.thrown == t0 + 1, "and SNAKE BOMB throws the bomb last armed")
	# the HUD says what is in hand
	war.arm(&"sv_net")
	TestLib.check(hud.ammo_text().ends_with("%") or hud.ammo_text().ends_with(" S"), "the HUD reads the energy while a power is in hand (%s)" % hud.ammo_text())
	TestLib.check(hud.weapon_text().begins_with("SNAKE NET") and hud.alt_text() == "", "and its name and cost (%s)" % hud.weapon_text())
	war.disarm()


# --- the reactions -----------------------------------------------------------------------------------------------------------------------

func _reactions() -> void:
	# panic
	await _stage(4, 9.0)
	var ran := 0
	for f in _foes:
		if war.react.panic(f):
			ran += 1
	await frames(2)
	var retreating := 0
	for f in _foes:
		if bool(f.get(&"_retreating")):
			retreating += 1
	TestLib.check(ran >= 3 and retreating >= 3 and war.react.panics >= 3, "troopers can be sent running by snakes (%d ran)" % retreating)
	var boss_safe := not war.react.panic(_foes[0])
	TestLib.check(boss_safe, "a trooper that already runs is not sent twice")
	# a cut tendril drops what the snake holds
	await _stage(1, 8.0)
	war.arm(&"sv_grab")
	war.cast(&"sv_grab", true)
	await until(func() -> bool: return war.verbs.is_grabbing(), 2.0)
	var held := war.verbs.grab_node()
	war.verbs.cut_grab()
	TestLib.check(not war.verbs.is_grabbing() and not war.holds.is_held(held) or war.holds.kind_of(held) == &"snare", "a rifleman who shoots the tendril makes the snake let go")
	war.disarm()
	# the jammer
	await _stage(0, 10.0)
	war.arm(&"sv_net")
	var j0 := war.react.jams
	p.snake.jam(2.5)
	await frames(6)
	TestLib.check(war.react.jams == j0 + 1 and war.armed == &"", "a jammer drops the armed power and the buttons say SNAKE JAMMED")
	p.snake.jam_t = 0.0
	await frames(4)
	war.cast(&"sv_shield", true)
	p.snake.jam(2.5)
	await frames(6)
	TestLib.check(war.verbs.shield.is_empty(), "and the shield's snakes fade")
	p.snake.jam_t = 0.0
	# the hunter's net
	await _stage(0, 10.0)
	var em := Game.enemies as EnemyManager
	var h := em.spawn(&"hunter", _spot + _dir() * 18.0, true)
	TestLib.check(h != null and h is Specialist and StringName(h.cfg.get("role", &"")) == &"hunter", "the snake hunter exists (a specialist with a static net launcher)")
	if h != null:
		h.set_physics_process(false)
		h.global_position = _spot + _dir() * 14.0
		var jam0 := war.react.jams
		SnakeReact.fire_net(h)
		await until(func() -> bool: return p.snake.jam_t > 0.0, 4.0)
		TestLib.check(p.snake.jam_t > 0.0, "his net lands on the hero: every snake is jammed")
		p.snake.jam_t = 0.0
		em.clear()
	# the crowd films the hero
	var crowd: Object = null
	if is_instance_valid(Game.world) and Game.world.get(&"ambient") != null:
		crowd = (Game.world.get(&"ambient") as Object).get(&"crowd")
	if crowd != null and int(crowd.get(&"count")) > 0:
		var who := [-1]
		await until(func() -> bool:
			for i in int(crowd.get(&"count")):
				if bool(crowd.call(&"is_alive", i)) and not bool(crowd.call(&"is_dying", i)) and not bool(crowd.call(&"is_fleeing", i)):
					who[0] = i
					return true
			return false, 8.0)
		TestLib.check(who[0] >= 0, "the streets hold a civilian who can film the hero")
		if who[0] >= 0:
			var home := p.global_position                                          # the street is random: stand the hero 14 m from a civilian for the call (nothing moves in between)
			p.global_position = (crowd.call(&"person_position", who[0]) as Vector3) + Vector3(14.0, 0.0, 0.0)
			var f0 := war.react.films
			for k in 40:
				war.react._civilians(&"sv_net", p.global_position)
			p.global_position = home
			TestLib.check(war.react.films > f0, "civilians near the fight stop and film it (%d)" % (war.react.films - f0))
	# the counter-units come after a run of powers, never on STORY
	await _stage(0, 10.0)
	em.clear()
	war.react._hunter_cd = 0.0
	war.react._casts.clear()
	for k in 7:
		war.react._casts.append(war.react._now)
	var found := false
	for attempt in 4:                                                          # `_try_hunter` runs at most every half second of play (`_hunter_try_t`, a try that the earlier casts of this test had just made left it running: the check failed now and
		war.react._hunter_try_t = 0.0                                          # then, 17 of 17 times in a probe that called it again at once); a try can also find no spot in ten random places: the game tries again
		war.react._try_hunter()
		for e: Node3D in Gear.living_enemies(p.get_tree()):
			if StringName(e.get(&"type")) == &"hunter":
				found = true
		if found:
			break
		await frames(2)
	TestLib.check(found and war.react.hunters >= 1, "after a run of snake powers a hunter is called (NORMAL)")
	em.clear()
	Difficulty.set_mode(0)
	war.react._hunter_cd = 0.0
	war.react._casts.clear()
	for k in 9:
		war.react._casts.append(war.react._now)
	var h0 := war.react.hunters
	war.react._try_hunter()
	TestLib.check(war.react.hunters == h0, "never on STORY")
	Difficulty.set_mode(1)
	em.clear()


# --- the board missions ------------------------------------------------------------------------------------------------------------------

# --- the tutorial hints ---------------------------------------------------------------------------------------------------------------

## Three one-line hints in the first minutes, each shown once per profile (user://snake_war.cfg): HOLD WEAPON AND PICK THE SNAKE WEDGE after thirty quiet seconds, FIRE TO PULL once a power is armed,
## TRY THE BOMBS after three casts without a bomb. The state is reset before and after (no user:// file is left behind).
func _hints() -> void:
	SnakeWarMissions.reset_flags()
	var casts0 := war.casts
	var armed0 := war.armed
	war.disarm()
	war.casts = 0
	var said: Array[String] = []
	var catcher := func(t: String, _secs: float) -> void:
		said.append(t)
	Game.message.connect(catcher)
	Game.state = &"play"
	SnakeWarMissions._hint_t = 0.0
	SnakeWarMissions._play_t = 5.0
	SnakeWarMissions._tick_hints(war, 0.25, "")
	TestLib.check(said.is_empty(), "no hint in the first seconds of play")
	SnakeWarMissions._play_t = 31.0
	SnakeWarMissions._tick_hints(war, 0.25, "")
	TestLib.check(said.size() == 1 and said[0] == String(SnakeWarMissions.HINTS[&"wedge"]), "after thirty quiet seconds the first hint says to hold the weapon button and pick the SNAKE wedge (%s)" % str(said))
	SnakeWarMissions._hint_t = 0.0
	SnakeWarMissions._tick_hints(war, 0.25, "")
	TestLib.check(said.size() == 1, "the same hint never comes twice")
	war.armed = &"sv_pull"                                                   # armed by hand: the gun is not touched
	SnakeWarMissions._hint_t = 0.0
	SnakeWarMissions._tick_hints(war, 0.25, "")
	TestLib.check(said.size() == 2 and said[1] == String(SnakeWarMissions.HINTS[&"fire"]), "a power in hand that was never cast says FIRE TO PULL (%s)" % str(said))
	var waiting := said.size()
	SnakeWarMissions._tick_hints(war, 0.25, "")
	TestLib.check(said.size() == waiting, "a hint leaves a pause of its own before the next one")
	war.armed = &""
	war.casts = 3
	war.bombs.thrown = 0
	SnakeWarMissions._hint_t = 0.0
	SnakeWarMissions._tick_hints(war, 0.25, "")
	TestLib.check(said.size() == 3 and said[2] == String(SnakeWarMissions.HINTS[&"bombs"]), "three casts and no bomb: try the BOMBS wedge (%s)" % str(said))
	var cf := ConfigFile.new()
	TestLib.check(cf.load(SnakeWarMissions.SAVE) == OK and bool(cf.get_value("hints", "wedge", false)) and bool(cf.get_value("hints", "fire", false)) and bool(cf.get_value("hints", "bombs", false)), "the three hints are written to the profile file: once per profile")
	var plain := true
	for k: Variant in SnakeWarMissions.HINTS.values():
		plain = plain and String(k).length() <= 64 and not String(k).to_lower().contains("physics")
	TestLib.check(plain and SnakeWarMissions.HINTS.size() >= 5, "the hint texts are short plain lines (%d hints)" % SnakeWarMissions.HINTS.size())
	Game.message.disconnect(catcher)
	SnakeWarMissions.reset_flags()
	war.casts = casts0
	war.armed = armed0


func _missions() -> void:
	TestLib.check(SnakeWarMissions.TYPES.size() == 2 and SnakeWarMissions.DEFS.has(&"snake_arena") and SnakeWarMissions.DEFS.has(&"snake_hunt"), "two board missions: SNAKE ARENA and ROOFTOP SNAKE HUNT")
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var arena := SnakeWarMissions.build(&"snake_arena", 1, _spot, r)
	TestLib.check(not arena.is_empty() and (arena["steps"] as Array).size() == 2 and StringName((arena["steps"] as Array)[1]["kind"]) == &"defend" and float((arena["steps"] as Array)[1]["hold"]) >= 40.0, "SNAKE ARENA is a ring and a 48 s defence against waves")
	var hunt := SnakeWarMissions.build(&"snake_hunt", 1, _spot, r)
	TestLib.check(not hunt.is_empty() and (hunt["steps"] as Array).size() == 3 and StringName((hunt["steps"] as Array)[1]["kind"]) == &"kill_target" and (hunt["steps"] as Array)[1]["enemy"] == "sniper", "ROOFTOP SNAKE HUNT is a roof, a sniper with guards and a gunner")
	var first: Vector3 = (hunt["steps"] as Array)[0]["pos"]
	TestLib.check(first.y > 15.0, "the first goal is on a real roof (%.0f m up)" % first.y)
	var mb := (Game.missions as Missions).board
	var offer := {}
	if mb != null:
		offer = mb.build(&"snake_arena", _spot)
	TestLib.check(not offer.is_empty() and bool(offer.get("snake", false)) and (offer["chapter"] as Dictionary)["steps"].size() == 2, "the Mission Board builds the arena offer (a chapter of steps)")
	# a whole arena through the runner, the defence shortened to a few seconds
	SnakeWarMissions.reset_flags()
	await _stage(0, 10.0)
	var camp := Game.missions.campaign as CampaignRunner
	var ch: Dictionary = (offer["chapter"] as Dictionary).duplicate(true)
	var steps: Array = ch["steps"]
	(steps[0] as Dictionary)["pos"] = _spot + _dir() * 12.0
	(steps[0] as Dictionary)["radius"] = 14.0
	(steps[1] as Dictionary)["hold"] = 5.0
	(steps[1] as Dictionary)["pos"] = _spot + _dir() * 12.0
	(steps[1] as Dictionary)["count"] = 1
	var done := [false]
	camp.chapter_completed.connect(func(_c: int) -> void: done[0] = true)
	TestLib.check(camp.start_custom(ch), "the runner starts the arena chapter")
	await until(func() -> bool: return camp.state == &"active" and camp.step_index == 0, 6.0)
	await until(func() -> bool: return SnakeWarMissions.active_mission == "arena", 3.0)
	TestLib.check(SnakeWarMissions.active_mission == "arena" and SnakeWarMissions.hooked(), "the director knows the arena runs")
	p.snake.energy = 0.0
	await frames(30)
	TestLib.check(p.snake.energy > 5.0, "and fills the snake bar while it lasts (%.1f)" % p.snake.energy)
	p.teleport_to(_spot + _dir() * 12.0)
	await until(func() -> bool: return camp.state == &"active" and camp.step_index == 1, 8.0)
	war.cd.clear()
	war.cast(&"sv_shield", true)
	war.cd.clear()
	war._gcd = 0.0
	war.cast(&"sv_net", true)
	await until(func() -> bool: return done[0], 30.0)
	TestLib.check(done[0], "the arena can be finished")
	TestLib.check(SnakeWarMissions.bonus_paid >= 80 or SnakeWarMissions.powers_used.size() >= 2, "and pays a bonus for the different snake powers used (%d credits)" % SnakeWarMissions.bonus_paid)
	camp.abort()
	SnakeWarMissions.reset_flags()
