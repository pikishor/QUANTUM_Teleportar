extends RefCounted
## DEV PROBE 2 of the wave 113 play critic (not a regression test): hit feedback of blasts, side job kill credit, chain reactions (barrels, cars), pooled enemies after a status death.
## Prints PROBE lines. Run: tools/test.sh tests/dev_w113_behaviour.gd

const TIMEOUT_SECONDS := 140.0
const DT := 1.0 / 60.0

var _host: Node
var _p: Player
var _mgr: EnemyManager
var _ops: BlastOps
var _spot := Vector3.ZERO
var _yaw := 0.0


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
			var ok := true
			for off in [-6.0, 0.0, 6.0]:
				var side := dir.cross(Vector3.UP) * float(off)
				var q := PhysicsRayQueryParameters3D.create(a + side, a + side + dir * 70.0, Game.L_WORLD | Game.L_VEHICLE)
				if not space.intersect_ray(q).is_empty():
					ok = false
					break
			if ok:
				_spot = rp
				_yaw = yaw
				return true
	return false


func _dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _foe(pos: Vector3, hp := 60.0) -> Drone:
	var d := _mgr.spawn(&"operative", pos, false)
	if d != null:
		d.set_physics_process(false)
		d.global_position = pos
		d.max_hp = hp
		d.hp = hp
		d.rotation.y = _yaw
	return d


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
	_mgr = Game.enemies as EnemyManager
	_mgr.patrol_groups().clear()
	_mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	if Game.missions != null:
		Game.missions.contracts.enabled = false
	_p.set_physics_process(false)
	_p.max_hp = 1.0e6
	_p.hp = 1.0e6
	TestMode.god = true
	var city := Game.world as City
	if city != null and city.ambient != null:
		city.ambient.set_process(false)
	print("PROBE lane ", _lane(), " spot ", _spot)
	_ops = BlastOps.shared(host.get_tree())
	Game.set_quality(1)
	_p.teleport_to(_spot)
	_p.camera_rig.reset_view(_yaw, -0.03)
	await TestLib.frames(host, 4)
	var only := OS.get_environment("W113_ONLY")
	if only == "" or only == "feedback":
		await _feedback()
	if only == "" or only == "chains":
		await _chains()
	if only == "" or only == "pool":
		await _pool_reuse()
	if only == "" or only == "crowd":
		await _crowd()
	if only == "" or only == "tank":
		await _tank()
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)


## C1: what the hero sees and what the jobs count after his own blast killed three people.
func _feedback() -> void:
	var base := _spot + _dir() * 20.0
	base.y = _spot.y
	var sm: SideMissions = Game.missions.sides
	if is_instance_valid(Game.story):
		Game.story.set("chapter", 4)
	print("PROBE sides ", sm, " started ", sm.start(&"hunt", _spot) if sm != null else false, " active ", sm.active, " stage ", sm.stage)
	await TestLib.frames(_host, 2)
	var t0 := _p.last_hit_time
	var kills_sig := [0]
	var hits_sig := [0]
	_p.hit_confirmed.connect(func(kill: bool, _c: bool) -> void:
		hits_sig[0] += 1
		if kill:
			kills_sig[0] += 1)
	var ach: Achievements = Game.progress.achievements if Game.progress != null else null
	var stats0 := int(ach.stats.get("kills", 0)) if ach != null else -1
	var foes: Array[Drone] = []
	for k in 3:
		foes.append(_foe(base + _right() * float(k - 1) * 1.5))
	var prog0 := sm.progress_val
	var res := BlastTable.apply(&"gr_frag", base, _p, {"quiet": true})
	await TestLib.frames(_host, 3)
	var dead := 0
	for f in foes:
		if f.dead:
			dead += 1
	print("PROBE blast feedback: enemies hit ", res["enemies"], " dead ", dead, " | last_hit_time moved ", _p.last_hit_time != t0, " | hit_confirmed signals ", hits_sig[0], " kills ", kills_sig[0],
			" | side job progress ", sm.progress_val - prog0, " | achievements kills +", (int(ach.stats.get("kills", 0)) - stats0) if ach != null else -1)
	# the same three people killed by bullets (the weapon path), for comparison
	var foes2: Array[Drone] = []
	for k in 3:
		foes2.append(_foe(base + _right() * float(k - 1) * 1.5 + Vector3(0, 0, 4.0)))
	var prog1 := sm.progress_val
	for f in foes2:
		var w := _p.weapon
		w._hit_target(f, f.global_position + Vector3(0, 1.0, 0), Vector3.UP, 99.0)
	await TestLib.frames(_host, 2)
	print("PROBE bullet feedback: side job progress ", sm.progress_val - prog1, " (3 bullet kills)")
	_mgr.clear()
	sm.abort() if sm.has_method(&"abort") else null


## C2: a row of barrels, a row of cars.
func _chains() -> void:
	_mgr.clear()
	var vm := Game.vehicles as VehicleManager
	var wb := WorldBlasters.current
	var row := _spot + _dir() * 30.0
	row.y = _spot.y
	var n_barrels := 8
	for i in n_barrels:
		WorldBlasters.spawn(&"wb_barrel", row + _right() * (float(i) * 2.0), 0.0)
	print("PROBE barrels live ", wb.live_count(&"wb_barrel"))
	var d0 := wb.detonations
	var t := 0.0
	wb.hit_at(row, 99.0)
	var peak_marks := 0
	while t < 6.0 and wb.detonations - d0 < n_barrels:
		await _host.get_tree().physics_frame
		t += DT
	print("PROBE barrel chain: ", wb.detonations - d0, " of ", n_barrels, " went off in ", snappedf(t, 0.01), " s")
	_ops.reset()
	await TestLib.frames(_host, 5)
	# cars
	vm._reset_all()
	var cars: Array[Vehicle] = []
	var rowc := _spot + _dir() * 36.0 + _right() * 10.0
	rowc.y = _spot.y
	for i in 6:
		var c := vm.spawn_parked(&"sedan", rowc - _right() * (float(i) * 5.5), _yaw + PI * 0.5)
		if c != null:
			c.hp = c.max_hp
			cars.append(c)
	await TestLib.frames(_host, 4)
	var exploded := [0]
	for c in cars:
		c.exploded.connect(func(_v: Node) -> void: exploded[0] += 1)
	print("PROBE cars placed ", cars.size(), " hp ", cars[0].max_hp if not cars.is_empty() else 0)
	if not cars.is_empty():
		var tt := 0.0
		cars[0].hp = 2.0
		cars[0].damage(50.0)
		var last_n := 0
		while tt < 12.0:
			await _host.get_tree().physics_frame
			tt += DT
			if exploded[0] != last_n:
				last_n = exploded[0]
				print("PROBE car chain t=", snappedf(tt, 0.01), " exploded ", last_n)
			if exploded[0] >= cars.size():
				break
		print("PROBE car chain: ", exploded[0], " of ", cars.size(), " exploded, hp left ", cars.map(func(c: Vehicle) -> int: return int(c.hp)))
	_ops.reset()
	vm._reset_all()


## C3: a pooled enemy that died frozen, burning or flung comes back clean.
func _pool_reuse() -> void:
	_mgr.clear()
	var base := _spot + _dir() * 18.0
	base.y = _spot.y
	var d := _foe(base, 60.0)
	print("PROBE pool: first enemy ", d, " hp ", d.hp)
	BlastTable.apply(&"gr_still", base, _p, {"quiet": true})
	var frozen := d.is_disabled()
	var kid := d.get_instance_id()
	d.damage(9999.0)
	await TestLib.frames(_host, 30)
	_ops.reset()
	var dm := DamageWorld.current
	print("PROBE pool: frozen then killed (disabled while frozen ", frozen, ", dead ", d.dead, ")")
	BlastTable.apply(&"gr_frag", base, _p, {"quiet": true})
	await TestLib.frames(_host, 10)
	_mgr.clear()
	await TestLib.frames(_host, 5)
	var e := _foe(base, 60.0)
	print("PROBE pool: respawned ", e, " same node ", e.get_instance_id() == kid, " disabled ", e.is_disabled(), " dead ", e.dead, " scale ", e.scale, " rot ", e.rotation, " model vis ", (e.get(&"model") as Node3D).visible if e.get(&"model") != null else "n/a",
			" model scale ", (e.get(&"model") as Node3D).scale if e.get(&"model") != null else "n/a")
	await TestLib.frames(_host, 12)
	var st := dm.foes.state_of(e) if dm != null else {}
	print("PROBE pool: foe fx state after reuse ", {"plates": st.get("plates", -1), "limp": st.get("limp", -1), "died": st.get("died", false), "until": st.get("until", -1)})
	e.damage(25.0)
	await TestLib.frames(_host, 12)
	var st2 := dm.foes.state_of(e) if dm != null else {}
	print("PROBE pool: after 25 damage ", {"plates": st2.get("plates", -1), "hp": e.hp, "max": e.max_hp})


## C4: the crowd next to a blast, casualties on and off.
func _crowd() -> void:
	var city := Game.world as City
	var crowd = city.ambient.crowd if city != null and city.ambient != null else null
	print("PROBE crowd ", crowd, " count ", crowd.count if crowd != null else -1)
	if crowd == null or crowd.count == 0:
		return
	city.ambient.set_process(true)
	var waited := 0
	while waited < 300:
		await TestLib.frames(_host, 5)
		waited += 5
		var n_alive := 0
		for i in int(crowd.count):
			if crowd.is_alive(i):
				n_alive += 1
		if n_alive >= 20:
			break
	print("PROBE crowd waited frames ", waited)
	for casualties in [true, false]:
		Game.civilian_casualties = casualties
		var pi := -1
		var best := 1.0e9
		for i in int(crowd.count):
			if crowd.is_alive(i):
				var dd: float = (crowd.person_position(i) as Vector3).distance_to(_p.global_position)
				if dd < best:
					best = dd
					pi = i
		print("PROBE crowd person ", pi, " at ", best, " m")
		if pi < 0:
			continue
		var pp: Vector3 = crowd.person_position(pi)
		var fled0: int = crowd._fled
		var alive0 := 0
		for i in int(crowd.count):
			if crowd.is_alive(i):
				alive0 += 1
		var res := BlastTable.apply(&"gr_frag", pp + Vector3(0.0, 0.3, 0.0), _p, {"quiet": true})
		await TestLib.frames(_host, 2)
		var alive1 := 0
		var dying := 0
		for i in int(crowd.count):
			if crowd.is_alive(i):
				alive1 += 1
			if crowd.is_dying(i):
				dying += 1
		print("PROBE crowd casualties=", casualties, " : fled +", crowd._fled - fled0, " alive ", alive0, "->", alive1, " dying ", dying, " result civilians ", res.get("civilians"), " killed ", res.get("civilians_killed"))
		await TestLib.frames(_host, 20)
		for i in int(crowd.count):               # bring everybody back for the next run
			if not crowd.is_alive(i) and crowd.has_method(&"revive_person"):
				crowd.revive_person(i)
	Game.civilian_casualties = true


## C5: the hero's own tank and the shells it fires at a wall four metres ahead.
func _tank() -> void:
	var vm := Game.vehicles as VehicleManager
	vm._reset_all()
	var spot := _spot + _dir() * 20.0
	spot.y = _spot.y
	var tank := vm.spawn_parked(&"tank", spot, _yaw)
	print("PROBE tank ", tank, " hp ", tank.hp if tank != null else 0)
	if tank == null:
		return
	tank.driver_is_player = true
	for id: StringName in [&"ord_tank_he", &"ord_tank_ap", &"ord_tank_cluster"]:
		tank.hp = tank.max_hp
		var at := spot + _dir() * 4.0
		BlastTable.apply(id, at, tank, {"quiet": true})
		print("PROBE tank own shell ", id, " at 4 m: hull lost ", tank.max_hp - tank.hp, " of ", tank.max_hp)
	tank.driver_is_player = false
	# the same from a car that the hero sits in, with a launcher blast that is not friendly (a mounted gun)
	vm._reset_all()
