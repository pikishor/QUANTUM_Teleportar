extends RefCounted
## Wave 113 critic (PLAY lens): regressions of the defects that measuring the blast arsenal, the damage layers and the enemies in the REAL game scene (main.tscn) found.
##   table     all 81 entries of the blast table (65 + the migrated legacy blasts + the storm bolt): an enemy at 0.5, 1.0 and 1.5 x the radius loses exactly what BlastTable.damage_at says (cover applied;
##             the shock chain of ARC COIL may add to it, never take away)
##   credit    what the hero's explosives, fires and chains did was invisible to the HUD and to everything that counts kills: three enemies killed by a frag left the BOSS-LITE HUNT side job at 0 of 8 (bullets
##             counted 3), no crosshair X, no kill ring, no damage number, no kill stat. BlastCredit.dealt now reports a hit (once a frame) and every kill (hit_confirmed) for blasts, legacy blasts, burns,
##             shock chains and fire; an enemy's blast credits nothing, QT_CREDIT=0 / BlastCredit.enabled switches it off
##   loud      an explosion is never a SILENT TAKEDOWN: the guard it hurts is aware (+150 and a stealth takedown for every unaware guard a grenade killed; inside a room the others heard nothing)
##   vehicle   the tank, car or aircraft that fired a shell that is not "friendly" does not take it (an AP shell 4 m ahead cost the hero's tank 520 of 2000 hull points), other cars still do, and a friendly
##             blast (a grenade) still hurts every car
##   crowd     with the option "people can be hurt" off a blast still sends the crowd running (nobody dies); with it on someone dies
##   pull      a well (WELL SEED, GRAVITY MINE, COLLAPSE FIELD, BLACK-HOLE) drags people through the air, not through a wall
##   pierce    the rounds of the wall-piercing rifles (TITAN ANTI-MATERIAL RIFLE, PHASE RIFLE, BREAKER ...) went through a car broadside without hurting it (the ray excluded the car as a "wall"): the AMR
##             could not wreck a car in 40 s; now the car takes the round (hit points, hole, marker) and the round goes on through it as before
##   freed     a body that is freed while a blast carries it (a tossed car, a launched or burning or frozen enemy: an alien dissolves and is freed) must not end the blast step with "Trying to cast a freed
##             object" every frame (it did, in the spam of 90 blasts at HIGH: the entry stayed and every other tossed car froze mid-air)
##   chains    a row of barrels goes off one after the other
## Waits on counters and state (game time advances by physics frames); user:// state is reset first. Run: tools/test.sh tests/test_play_critic_w113.gd (about 80 s)

const TIMEOUT_SECONDS := 140.0
const DT := 1.0 / 60.0

class FakeVisual extends Node3D:
	var model: Node3D


class FakeCar extends Node3D:
	var visual: Object


var host: Node
var main: Node
var p: Player
var mgr: EnemyManager
var ops: BlastOps
var spot := Vector3.ZERO
var yaw := 0.0
var _kill_sig := [0]
var _hit_sig := [0]


func _reset() -> void:
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://interiors.cfg", "user://roam_world.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _dir() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## An open lane of 70 m, 12 m wide, on a city road: the blasts of these checks have nothing but the ground around them.
func _lane() -> bool:
	var city := Game.world as City
	if city == null:
		return false
	var space := p.get_world_3d().direct_space_state
	for tries in 500:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for k in 8:
			var a_yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(a_yaw), 0.0, -cos(a_yaw))
			var a := rp + Vector3(0, 1.5, 0)
			var ok := true
			for off in [-6.0, 0.0, 6.0]:
				var side := dir.cross(Vector3.UP) * float(off)
				var q := PhysicsRayQueryParameters3D.create(a + side, a + side + dir * 70.0, Game.L_WORLD | Game.L_VEHICLE)
				if not space.intersect_ray(q).is_empty():
					ok = false
					break
			if ok:
				spot = rp
				yaw = a_yaw
				return true
	return false


func _foe(pos: Vector3, hp := 60.0, aware := false) -> Drone:
	var d := mgr.spawn(&"operative", pos, false)
	if d != null:
		d.set_physics_process(false)
		d.global_position = pos
		d.max_hp = hp
		d.hp = hp
		d.aware = aware
		d.rotation.y = yaw
	return d


func _frames(n: int) -> void:
	await TestLib.frames(host, n)


## SCRIPT errors the game logged so far (Dev.errors keeps the last 40 lines; a repeated line carries " xN"). A script error inside an awaited section ends that section without failing the test.
func _script_errors() -> int:
	var n := 0
	for line in Dev.errors.snapshot():
		if line.begins_with("[SCRIPT]"):
			var at := line.rfind(" x")
			n += line.substr(at + 2).to_int() if at > 0 and line.substr(at + 2).is_valid_int() else 1
	return n


func run(h: Node) -> void:
	host = h
	_reset()
	Sfx.muted = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _frames(6)
	Game.state = &"play"
	p = Game.player as Player
	mgr = Game.enemies as EnemyManager
	TestLib.check(p != null and mgr != null and BlastOps.shared(host.get_tree()) != null, "the real scene has a hero, the enemy manager and the blast operations")
	if p == null or mgr == null:
		return
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	p.set_physics_process(false)
	TestMode.god = true
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	TestLib.check(_lane(), "an open lane of 70 m for the blasts")
	ops = BlastOps.shared(host.get_tree())
	Game.set_quality(1)
	p.teleport_to(spot)
	p.camera_rig.reset_view(yaw, -0.03)
	p.hit_confirmed.connect(func(kill: bool, _c: bool) -> void:
		_hit_sig[0] += 1
		if kill:
			_kill_sig[0] += 1)
	await _frames(4)
	var script_errors0 := _script_errors()
	var only := OS.get_environment("W113_ONLY").split(",", false)            # look-dev: W113_ONLY=table,vehicle runs only those sections
	if only.is_empty() or only.has("table"):
		await _table()
	if only.is_empty() or only.has("credit"):
		await _credit()
	if only.is_empty() or only.has("loud"):
		await _loud()
	if only.is_empty() or only.has("vehicle"):
		await _vehicle()
	if only.is_empty() or only.has("crowd"):
		await _crowd()
	if only.is_empty() or only.has("pull"):
		await _pull()
	if only.is_empty() or only.has("pierce"):
		await _pierce()
	if only.is_empty() or only.has("freed"):
		await _freed_bodies()
	if only.is_empty() or only.has("chains"):
		await _chains()
	if only.is_empty() or only.has("interior"):
		await _interior_loud()
	TestLib.check(_script_errors() == script_errors0, "the whole run raised no script error (%d new)" % (_script_errors() - script_errors0))
	TestMode.god = false
	Game.state = &"menu"
	main.queue_free()
	await _frames(2)
	_reset()


# --- table ---------------------------------------------------------------------------------------------------------------------------

func _table() -> void:
	var base := spot + _dir() * 24.0
	base.y = spot.y
	var bad: Array[String] = []
	var n := 0
	for id: StringName in BlastTable.ids():
		var e := BlastTable.entry(id)
		var r := float(e["radius"])
		var dists := [r * 0.5, r * 0.999, r * 1.5]
		var angs := [0.0, 0.18, -0.18]
		var foes: Array[Drone] = []
		for k in 3:
			var off: Vector3 = _dir().rotated(Vector3.UP, float(angs[k])) * float(dists[k])
			foes.append(_foe(base + off, 1.0e6))
		if foes.size() < 3 or foes[2] == null:
			bad.append("%s: no enemies" % id)
			mgr.clear()
			continue
		BlastTable.apply(id, base, null, {"dmg_mult": 1.0, "quiet": true, "final": true, "dir": _dir()})
		n += 1
		var chain := StringName((e["status"] as Dictionary).get("kind", &"")) == &"shock"
		for k in 3:
			var lost := 1.0e6 - foes[k].hp
			var cov := 1.0
			if bool(e["cover"]):
				cov = Game.blast_cover(base + Vector3(0.0, 0.3, 0.0), foes[k].global_position + Vector3(0.0, 1.0, 0.0))
			var want := BlastTable.damage_at(id, &"enemy", foes[k].global_position.distance_to(base)) * cov
			var tol := maxf(0.6, want * 0.02)
			var off_by := lost - want
			if (chain and off_by < -tol) or (not chain and absf(off_by) > tol):
				bad.append("%s at %.2f x R lost %.1f, the table says %.1f" % [id, float(dists[k]) / r, lost, want])
		ops.reset()
		mgr.clear()
		await _frames(1)
	TestLib.check(n >= 81 and bad.is_empty(), "%d table entries: an enemy at 0.5, 1 and 1.5 x the radius loses what the table says (%s)" % [n, "; ".join(bad.slice(0, 3))])
	# the same for a car (it counts its own length on top of the radius): 0.5 x R, R and R + 1 m
	var vm := Game.vehicles as VehicleManager
	vm.set_physics_process(false)                                         # the manager streams ambient cars and, at its cap, releases and frees the cars of a test: it sleeps while the test owns the cars
	vm._reset_all()
	var car := vm.spawn_parked(&"sedan", base + _right() * 14.0, yaw)
	await _frames(3)
	var vbad: Array[String] = []
	var vn := 0
	if car != null:
		car.max_hp = 1.0e6
		for id: StringName in BlastTable.ids():
			var e := BlastTable.entry(id)
			if float((e["dmg"] as Dictionary)["vehicle"]) <= 0.0:
				continue
			var r := float(e["radius"])
			for dist: float in [r * 0.5, r, r + 1.0]:
				car.hp = 1.0e6
				car.global_position = base + _dir() * dist
				BlastTable.apply(id, base, null, {"dmg_mult": 1.0, "quiet": true, "final": true, "dir": _dir()})
				var cov := 1.0
				if bool(e["cover"]):
					cov = Game.blast_cover(base + Vector3(0.0, 0.3, 0.0), car.global_position + Vector3(0.0, 0.8, 0.0))
				var want := BlastTable.damage_at(id, &"vehicle", car.global_position.distance_to(base)) * cov * VehicleSpecs.EXTERNAL_DAMAGE
				var lost := 1.0e6 - car.hp
				if absf(lost - want) > maxf(0.8, want * 0.03):
					vbad.append("%s at %.1f m lost %.1f, the table says %.1f" % [id, dist, lost, want])
			vn += 1
			ops.reset()
		await _frames(1)
	TestLib.check(vn >= 70 and vbad.is_empty(), "%d table entries: a car at 0.5 x R, R and R + 1 m loses what the table says (%s)" % [vn, "; ".join(vbad.slice(0, 3))])
	if car != null:
		car.max_hp = float(car.spec["hp"])                                 # the pooled car must not keep the million hit points of the sweep
		car.hp = car.max_hp
	vm._reset_all()
	vm.set_physics_process(true)
	mgr.clear()


# --- credit --------------------------------------------------------------------------------------------------------------------------

func _job_start() -> SideMissions:
	var sm: SideMissions = Game.missions.sides
	if sm.active:
		sm.abort()
	if is_instance_valid(Game.story):
		Game.story.set("chapter", 4)
	var ok := sm.start(&"hunt", spot)                                     # BOSS-LITE HUNT: eight confirmed kills, no other stage
	mgr.clear()
	sm._top_t = 1.0e9                                                     # the job's own top-up of foes must not wander into the test's blasts
	TestLib.check(ok and sm.active and String(sm.stages[0]["kind"]) == "kill", "the HUNT side job runs (a kill stage)")
	return sm


func _credit() -> void:
	var sm := _job_start()
	var base := spot + _dir() * 22.0
	base.y = spot.y
	var ach: Achievements = Game.progress.achievements if Game.progress != null else null
	# three enemies killed by the hero's frag grenade
	var foes: Array[Drone] = []
	for k in 3:
		foes.append(_foe(base + _right() * float(k - 1) * 1.5, 60.0))
	BlastCredit.reset_stats()
	_kill_sig[0] = 0
	_hit_sig[0] = 0
	var t0 := p.last_hit_time
	var prog0 := sm.progress_val
	var k0 := int(ach.stats.get("kills", 0)) if ach != null else 0
	var res := BlastTable.apply(&"gr_frag", base, p, {"quiet": true})
	var dead := 0
	for f in foes:
		if f.dead:
			dead += 1
	TestLib.check(dead == 3 and int(res["enemies"]) >= 3, "the frag killed the three enemies (%d)" % dead)
	TestLib.check(_kill_sig[0] == 3 and sm.progress_val - prog0 == 3.0, "...three kills reach the side job: hit_confirmed(kill) x%d, HUNT progress +%.0f (bullets gave +3, the blast gave 0)" % [_kill_sig[0], sm.progress_val - prog0])
	TestLib.check(p.last_hit_time != t0 and p.last_hit_kill and not p.last_hit_crit, "...the crosshair is told: a fresh last_hit_time and a kill (the red ring)")
	TestLib.check(ach == null or int(ach.stats.get("kills", 0)) - k0 == 3, "...and the kill stat of the achievements counts them")
	TestLib.check(BlastCredit.kills == 3 and BlastCredit.numbers >= 1 and BlastCredit.numbers <= BlastCredit.max_numbers() and BlastCredit.max_numbers() == Game.quality + 1, "...a damage number pops (at most %d a frame on this tier: %d)" % [BlastCredit.max_numbers(), BlastCredit.numbers])
	mgr.clear()
	# a blast that only hurts: one marker, no kill, the job does not move
	var tough: Array[Drone] = []
	for k in 3:
		tough.append(_foe(base + _right() * float(k - 1) * 1.5, 1.0e6))
	await _frames(2)
	BlastCredit.reset_stats()
	_kill_sig[0] = 0
	_hit_sig[0] = 0
	prog0 = sm.progress_val
	BlastTable.apply(&"gr_frag", base, p, {"quiet": true})
	TestLib.check(_hit_sig[0] == 1 and _kill_sig[0] == 0 and BlastCredit.marks == 1 and not p.last_hit_kill, "three enemies hurt but alive give ONE marker and no kill (%d hits)" % _hit_sig[0])
	TestLib.check(sm.progress_val == prog0, "...and the job does not move")
	mgr.clear()
	await _frames(2)
	# an enemy's blast credits nothing (its source is an enemy)
	var shooter := _foe(base + Vector3(9.0, 0.0, 0.0), 1.0e6)
	var victim := _foe(base, 30.0)
	BlastCredit.reset_stats()
	_kill_sig[0] = 0
	_hit_sig[0] = 0
	prog0 = sm.progress_val
	BlastTable.apply(&"gr_frag", base, shooter, {"quiet": true})
	TestLib.check(victim.dead and _kill_sig[0] == 0 and _hit_sig[0] == 0 and sm.progress_val == prog0, "a blast an enemy fired kills but credits the hero with nothing")
	mgr.clear()
	await _frames(2)
	# the old Game.explode numbers (a rocket of an older weapon, a quantum ability, a vehicle weapon): the legacy path credits too
	var lg := _foe(base, 30.0)
	BlastCredit.reset_stats()
	_kill_sig[0] = 0
	prog0 = sm.progress_val
	Game.explode(base + Vector3(0.0, 0.3, 0.0), 6.0, {"enemy_dmg": 200.0, "car_dmg": 0.0, "player_dmg": 0.0, "quiet": true})
	TestLib.check(lg.dead and _kill_sig[0] == 1 and sm.progress_val - prog0 == 1.0, "a legacy Game.explode kill counts for the job as well")
	mgr.clear()
	await _frames(2)
	# a person run over by the hero's car counts as well
	var vm := Game.vehicles as VehicleManager
	vm.set_physics_process(false)
	vm._reset_all()
	var rcar := vm.spawn_parked(&"sedan", base + Vector3(0.0, 0.0, -14.0), yaw)
	if rcar != null:
		await _frames(2)
		var victim2 := _foe(rcar.global_position + Vector3(1.0, 0.0, 0.0), 5.0)
		rcar.driver_is_player = true
		rcar.speed = 20.0
		_kill_sig[0] = 0
		prog0 = sm.progress_val
		vm._ram(rcar)
		TestLib.check(victim2.dead and _kill_sig[0] == 1 and sm.progress_val - prog0 == 1.0, "a person the hero's car runs over is a kill for the job")
		rcar.driver_is_player = false
	vm._reset_all()
	vm.set_physics_process(true)
	mgr.clear()
	await _frames(2)
	# a burn that kills (EMBER BOTTLE, a status): the kill comes seconds later and still counts, the ticks before do not flash the crosshair
	var burnt := _foe(base, 12.0)
	BlastCredit.reset_stats()
	_kill_sig[0] = 0
	_hit_sig[0] = 0
	prog0 = sm.progress_val
	ops.burn(burnt, 30.0, 3.0, true)
	var t := 0.0
	while t < 4.0 and not burnt.dead:
		await _frames(6)
		t += DT * 6.0
	TestLib.check(burnt.dead and _kill_sig[0] == 1 and _hit_sig[0] == 1 and sm.progress_val - prog0 == 1.0, "an enemy that burns to death is a kill for the hero (one signal, no marker before it)")
	mgr.clear()
	await _frames(2)
	# the shock chain: the neighbour that dies of a jump counts
	var a := _foe(base, 1.0e6)
	var b := _foe(base + Vector3(3.0, 0.0, 0.0), 2.0)
	BlastCredit.reset_stats()
	_kill_sig[0] = 0
	prog0 = sm.progress_val
	ops._chain(a, BlastTable.entry(&"gr_arc"), 0.4, 1.0, true)
	TestLib.check(b.dead and _kill_sig[0] == 1 and sm.progress_val - prog0 == 1.0, "a kill made by a shock chain counts for the job")
	mgr.clear()
	await _frames(2)
	# a shot barrel: the world's blast credits the hero (he shot it); a new job first, the eighth kill of the first one finished it
	sm = _job_start()
	var tgt := _foe(base + Vector3(0.0, 0.0, 2.0), 30.0)
	WorldBlasters.spawn(&"wb_barrel", base - Vector3(0.0, 0.0, 0.0), 0.0)
	BlastCredit.reset_stats()
	_kill_sig[0] = 0
	prog0 = sm.progress_val
	WorldBlasters.current.hit_at(base, 99.0)
	t = 0.0
	while t < 3.0 and not tgt.dead:
		await _frames(6)
		t += DT * 6.0
	TestLib.check(tgt.dead and _kill_sig[0] == 1 and sm.progress_val - prog0 == 1.0, "an enemy killed by a barrel the hero shot counts for the job (dead %s, %d kill signals, job +%.0f, %d barrels live)" % [tgt.dead, _kill_sig[0], sm.progress_val - prog0, WorldBlasters.current.live_count(&"wb_barrel")])
	mgr.clear()
	ops.reset()
	await _frames(2)
	# the switch (QT_CREDIT=0): nothing is credited
	BlastCredit.enabled = false
	var off_foe := _foe(base, 30.0)
	_kill_sig[0] = 0
	prog0 = sm.progress_val
	BlastTable.apply(&"gr_frag", base, p, {"quiet": true})
	TestLib.check(off_foe.dead and _kill_sig[0] == 0 and sm.progress_val == prog0, "with the credit switched off the old behaviour is back (the before frames of the look-dev bot)")
	BlastCredit.enabled = OS.get_environment("QT_CREDIT") != "0"
	mgr.clear()
	sm.abort()
	await _frames(2)


# --- loud ----------------------------------------------------------------------------------------------------------------------------

func _loud() -> void:
	var base := spot + _dir() * 22.0
	base.y = spot.y
	var g1 := _foe(base, 40.0, false)
	var g2 := _foe(base + Vector3(6.0, 0.0, 0.0), 40.0, false)
	await _frames(2)
	var tk0 := Stealth.takedowns
	var score0 := Game.score
	BlastTable.apply(&"gr_frag", base + Vector3(0.0, 0.3, 0.0), p, {"quiet": true})
	await _frames(2)
	TestLib.check(g1.dead and Stealth.takedowns == tk0, "a grenade kill on an unaware guard is not a silent takedown (takedowns +%d)" % (Stealth.takedowns - tk0))
	TestLib.check(Game.score - score0 < Stealth.takedown_bonus() + int(g1.cfg["score"]) or Game.score - score0 == int(g1.cfg["score"]), "...and pays no stealth bonus (score +%d)" % (Game.score - score0))
	TestLib.check(g2.aware, "...the guard next to it is alerted by the blast")
	mgr.clear()
	# a burn on an unaware guard is loud too
	var g3 := _foe(base, 8.0, false)
	await _frames(2)
	var tk1 := Stealth.takedowns
	ops.burn(g3, 40.0, 3.0, true)
	var t := 0.0
	while t < 3.0 and not g3.dead:
		await _frames(6)
		t += DT * 6.0
	TestLib.check(g3.dead and Stealth.takedowns == tk1, "a guard that burns to death is no silent takedown either")
	mgr.clear()
	ops.reset()


# --- vehicle -------------------------------------------------------------------------------------------------------------------------

func _vehicle() -> void:
	var vm := Game.vehicles as VehicleManager
	vm.set_physics_process(false)
	vm._reset_all()
	var at := spot + _dir() * 20.0
	at.y = spot.y
	var tank := vm.spawn_parked(&"tank", at, yaw)
	var side := vm.spawn_parked(&"sedan", at + _right() * 7.0, yaw)
	TestLib.check(tank != null and side != null, "a tank and a sedan stand in the lane")
	if tank == null or side == null:
		vm.set_physics_process(true)
		return
	await _frames(3)
	if not is_instance_valid(tank) or not is_instance_valid(side):
		TestLib.check(false, "the tank and the sedan are still there after three frames")
		vm.set_physics_process(true)
		return
	tank.driver_is_player = true
	var lost := {}
	for id: StringName in [&"ord_tank_he", &"ord_tank_ap", &"ord_tank_cluster"]:
		tank.hp = tank.max_hp
		side.hp = side.max_hp
		BlastTable.apply(id, at + _dir() * 4.0, tank, {"quiet": true})
		lost[id] = tank.max_hp - tank.hp
	TestLib.check(float(lost[&"ord_tank_he"]) == 0.0 and float(lost[&"ord_tank_ap"]) == 0.0 and float(lost[&"ord_tank_cluster"]) == 0.0, "the tank does not wreck itself with its own shells 4 m ahead (HE %.0f, AP %.0f, CLUSTER %.0f of %.0f)" % [lost[&"ord_tank_he"], lost[&"ord_tank_ap"], lost[&"ord_tank_cluster"], tank.max_hp])
	tank.driver_is_player = false
	# the sedan next to it is not spared: a shell that lands beside it hurts it
	side.hp = side.max_hp
	BlastTable.apply(&"ord_tank_he", at + _right() * 5.0, tank, {"quiet": true})
	TestLib.check(side.hp < side.max_hp, "...but another car beside the impact still takes it (%.0f of %.0f)" % [side.hp, side.max_hp])
	# an enemy tank (nobody drives it) spares itself too: a shell is not aimed at its own hull
	tank.hp = tank.max_hp
	BlastTable.apply(&"ord_tank_ap", at + _dir() * 4.0, tank, {"quiet": true})
	TestLib.check(tank.hp == tank.max_hp, "an AI tank does not hurt itself either")
	# a friendly blast (a grenade, the hero's own risk) still hurts every car, a standing hero's included
	tank.hp = tank.max_hp
	side.hp = side.max_hp
	BlastTable.apply(&"gr_frag", side.global_position + Vector3(2.0, 0.0, 0.0), p, {"quiet": true})
	TestLib.check(side.hp < side.max_hp, "a friendly blast (frag) still hurts a car (%.0f of %.0f)" % [side.hp, side.max_hp])
	# the car the hero drives is spared by his ultimate (friendly:false)
	side.hp = side.max_hp
	var sv: Variant = p.get(&"vehicle")
	p.set(&"vehicle", side)
	BlastTable.apply(&"ult_mega", side.global_position, p, {"quiet": true})
	var survived: bool = side.hp == side.max_hp
	p.set(&"vehicle", sv)
	TestLib.check(survived, "the hero's own ultimate does not wreck the car he sits in")
	# legacy blasts (vehicle weapons, flak) spare the hero's car too
	side.hp = side.max_hp
	p.set(&"vehicle", side)
	Game.explode(side.global_position + Vector3(2.0, 0.0, 0.0), 6.0, {"enemy_dmg": 50.0, "car_dmg": 120.0, "player_dmg": 0.0, "quiet": true})
	var survived2: bool = side.hp == side.max_hp
	p.set(&"vehicle", sv)
	TestLib.check(survived2, "a legacy vehicle-weapon blast spares the car the hero drives")
	vm._reset_all()
	vm.set_physics_process(true)
	ops.reset()


# --- crowd ---------------------------------------------------------------------------------------------------------------------------

func _crowd() -> void:
	var city := Game.world as City
	var crowd = city.ambient.crowd if city != null and city.ambient != null else null
	if crowd == null or crowd.count == 0:
		TestLib.check(false, "the city has a crowd")
		return
	city.ambient.set_process(true)
	var waited := 0
	while waited < 360:
		await _frames(5)
		waited += 5
		var alive := 0
		for i in int(crowd.count):
			if crowd.is_alive(i):
				alive += 1
		if alive >= 12:
			break
	var dying0 := 0
	for casualties in [false, true]:
		Game.civilian_casualties = casualties
		var pi := -1
		var best := 1.0e9
		for i in int(crowd.count):
			if crowd.is_alive(i) and not crowd.is_dying(i):
				var dd: float = (crowd.person_position(i) as Vector3).distance_to(p.global_position)
				if dd < best:
					best = dd
					pi = i
		if pi < 0:
			TestLib.check(false, "a person to blast at (casualties %s)" % casualties)
			continue
		dying0 = 0
		for i in int(crowd.count):
			if crowd.is_dying(i):
				dying0 += 1
		var fled0: int = crowd._fled
		var pp: Vector3 = crowd.person_position(pi)
		var res := BlastTable.apply(&"gr_frag", pp + Vector3(0.0, 0.3, 0.0), p, {"quiet": true})
		await _frames(2)
		var dying1 := 0
		for i in int(crowd.count):
			if crowd.is_dying(i):
				dying1 += 1
		if casualties:
			TestLib.check(int(res["civilians_killed"]) >= 1 and dying1 > dying0, "casualties on: a frag at a person's feet kills (%d killed)" % int(res["civilians_killed"]))
		else:
			TestLib.check(crowd._fled > fled0 and dying1 == dying0 and int(res["civilians_killed"]) == 0, "casualties off: the crowd runs (%d ran) and nobody dies" % (crowd._fled - fled0))
		await _frames(30)
	Game.civilian_casualties = true
	city.ambient.set_process(false)
	ops.reset()


# --- pull ----------------------------------------------------------------------------------------------------------------------------

func _pull() -> void:
	mgr.clear()
	ops.reset()
	var base := spot + _dir() * 26.0
	base.y = spot.y
	# a wall of the world layer 3 m from the centre, across the way to the foe that stands behind it
	var wall := StaticBody3D.new()
	wall.collision_layer = Game.L_WORLD
	wall.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(9.0, 5.0, 1.0)                                      # 9 m across the line from the centre to the foe, 1 m thick along it
	cs.shape = bs
	wall.add_child(cs)
	host.add_child(wall)
	wall.global_position = base + _dir() * 3.0 + Vector3(0.0, 2.5, 0.0)
	wall.global_basis = Basis(Vector3.UP, yaw)
	var behind := _foe(base + _dir() * 6.5, 1.0e6)
	var open := _foe(base - _dir() * 6.5, 1.0e6)
	await _frames(3)
	var d_behind := behind.global_position.distance_to(base)
	var d_open := open.global_position.distance_to(base)
	BlastTable.apply(&"gr_well", base, p, {"quiet": true})
	var t := 0.0
	while t < 1.8:
		await _frames(6)
		t += DT * 6.0
	var pulled_open := d_open - open.global_position.distance_to(base)
	var moved_behind := d_behind - behind.global_position.distance_to(base)
	TestLib.check(pulled_open > 1.2, "a well pulls the enemy in the open towards its centre (%.1f m)" % pulled_open)
	TestLib.check(behind.global_position.distance_to(base) > 3.5 and moved_behind < pulled_open, "...but the one behind a wall stops at it: he is dragged up to the wall (%.1f m) and never through it (%.1f m from the centre, the wall's far face is at 3.5 m)" % [moved_behind, behind.global_position.distance_to(base)])
	wall.queue_free()
	mgr.clear()
	ops.reset()
	await _frames(3)


# --- piercing rounds -----------------------------------------------------------------------------------------------------------------

func _pierce() -> void:
	var vm := Game.vehicles as VehicleManager
	vm.set_physics_process(false)
	vm._reset_all()
	var at := spot + _dir() * 9.0
	at.y = spot.y
	var car := vm.spawn_parked(&"sedan", at, yaw + PI * 0.5)               # broadside to the hero
	await _frames(3)
	if not is_instance_valid(car):
		TestLib.check(false, "a car stands in the lane")
		vm.set_physics_process(true)
		return
	var w := p.weapon
	WeaponDefs.unlock(&"amr")
	w.switch_to(&"amr", true)
	p.teleport_to(spot)
	p.camera_rig.reset_view(yaw, -0.03)
	p.aiming = true
	car.hp = car.max_hp
	var walls0 := w.wall_hits
	var shots := 0
	var hp_after_first := -1.0
	while shots < 8 and not car.dead:
		w.ammo = w.mag
		w.reserve = 99
		w.fire_t = 0.0
		w.swap_t = 0.0
		w.reload_t = 0.0
		p.camera_rig.aim_at(car.global_position + Vector3(0.0, 0.7, 0.0))
		w.tick(DT, true, false, true, false)
		w.tick(DT, false, false, true, false)
		shots += 1
		await _frames(2)
		if shots == 1:
			hp_after_first = car.hp                                       # after the FIRST round: the car is still standing and has taken it
	p.aiming = false
	TestLib.check(car.dead and shots <= 5, "the anti-material rifle wrecks a car broadside in %d rounds (it went through it without a scratch before)" % shots)
	TestLib.check(hp_after_first >= 0.0 and hp_after_first < car.max_hp * 0.8 and w.wall_hits - walls0 >= shots, "...the first round alone cost the car %.0f of %.0f and every round still counts as passing a wall (%d)" % [car.max_hp - hp_after_first, car.max_hp, w.wall_hits - walls0])
	w.switch_to(&"carbine", true)
	vm._reset_all()
	vm.set_physics_process(true)
	mgr.clear()
	ops.reset()


# --- freed bodies --------------------------------------------------------------------------------------------------------------------

func _freed_bodies() -> void:
	ops.reset()
	var e0 := _script_errors()
	var a := Node3D.new()
	var b := Node3D.new()
	var c := FakeCar.new()                                                # a toss needs a car with a visual and a model, or its first step drops the entry
	var cv := FakeVisual.new()
	cv.model = Node3D.new()
	cv.add_child(cv.model)
	c.visual = cv
	c.add_child(cv)
	var d := Node3D.new()
	for n: Node3D in [a, b, c, d]:
		host.add_child(n)
	ops._air.append({"n": a, "vel": Vector3.UP, "t": 0.0, "y0": 0.0, "spin": 1.0, "dir": Vector3.FORWARD})
	ops._burn[b.get_instance_id()] = {"node": b, "dps": 5.0, "left": 3.0, "acc": 0.0, "fx": 0.0, "credit": false}
	ops._toss.append({"v": c, "t": 0.0, "dur": 4.0, "h": 1.0, "roll": 1.0, "side": 1.0})
	ops._hold[d.get_instance_id()] = {"node": d, "left": 3.0, "k": 1.0}
	await _frames(2)
	TestLib.check(ops._toss.size() == 1 and ops._air.size() == 1 and ops._burn.size() == 1 and ops._hold.size() == 1, "four bodies are carried by the blast (an airborne person, a burning one, a tossed car, a held vehicle)")
	for n: Node3D in [a, b, c, d]:
		n.free()                                                          # the way an alien creature that dissolved leaves the world
	await _frames(4)
	TestLib.check(_script_errors() == e0 and ops._air.is_empty() and ops._burn.is_empty() and ops._toss.is_empty() and ops._hold.is_empty(), "a body freed in the air, in a burn, in a toss or in a hold is dropped quietly (%d new script errors)" % (_script_errors() - e0))
	ops.reset()


# --- chains --------------------------------------------------------------------------------------------------------------------------

func _chains() -> void:
	var wb := WorldBlasters.current
	if wb == null:
		TestLib.check(false, "the world blasters exist")
		return
	var row := spot + _dir() * 30.0
	row.y = spot.y
	var n := 6
	for i in n:
		WorldBlasters.spawn(&"wb_barrel", row + _right() * (float(i) * 2.0 - 5.0), 0.0)
	var d0 := wb.detonations
	wb.hit_at(row + _right() * -5.0, 99.0)
	var t := 0.0
	while t < 6.0 and wb.detonations - d0 < n:
		await _frames(6)
		t += DT * 6.0
	TestLib.check(wb.detonations - d0 >= n, "a row of %d barrels goes off one after the other (%d in %.1f s)" % [n, wb.detonations - d0, t])
	ops.reset()


# --- interior ------------------------------------------------------------------------------------------------------------------------

func _interior_loud() -> void:
	var ig := InteriorGameplay.instance
	if ig == null:
		return
	var d := ig.doors_of(&"weapons", p.global_position)[0]
	p.teleport_to((d["pos"] as Vector3) + Vector3(0.0, 0.1, 0.0))
	await _frames(5)
	TestLib.check(ig.enter(d, true), "enter a gun shop")
	await _frames(60)
	TestLib.check(InteriorGameplay.active, "inside the room")
	mgr.clear()
	var g1 := mgr.spawn(&"operative", p.global_position + Vector3(4.0, 0.0, 0.0), false)
	var g2 := mgr.spawn(&"operative", p.global_position + Vector3(0.0, 0.0, 9.0), false)
	if g1 == null or g2 == null:
		TestLib.check(false, "two guards stand in the room")
		return
	for g in [g1, g2]:
		g.set_physics_process(false)
		g.max_hp = 40.0
		g.hp = 40.0
		g.aware = false
	Game.heat = 1.0                                                       # the earlier kills of this test ran the heat up to its limit of 5
	Game.quiet = 0.0
	var tk0 := Stealth.takedowns
	var heat0 := Game.heat
	BlastTable.apply(&"gr_frag", g1.global_position + Vector3(0.0, 0.3, 0.0), p, {"quiet": true})
	await _frames(4)
	TestLib.check(g1.dead and Stealth.takedowns == tk0, "in a room a frag kill is no silent takedown (takedowns +%d)" % (Stealth.takedowns - tk0))
	TestLib.check(g2.aware and Game.heat > heat0, "...the second guard hears it and the heat rises (%.2f -> %.2f)" % [heat0, Game.heat])
	mgr.clear()
	ops.reset()
