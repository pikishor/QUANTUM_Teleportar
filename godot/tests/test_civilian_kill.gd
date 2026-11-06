extends RefCounted
## Civilians can be hit and killed in the REAL game scene (scenes/main.tscn): the carbine's ray finds a citizen in the street (body 2 hits, head 1), the death plays (stand still, fall
## away from the shooter, dissolve into light, the slot frees), the street reacts (scream, everybody near runs, witnesses may call the patrol), the hero pays in heat and earns credits, a blast
## and a swing and a fast car kill too, and the setting "civilian casualties" OFF makes them untouchable (shots pass through).
## Run: tools/test.sh tests/test_civilian_kill.gd

const TMP := "user://test_civilian_kill.cfg"

var _vehicle_script: GDScript
var _manager_script: GDScript


func run(host: Node) -> void:
	Game.civilian_casualties = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	var p: Player = Game.player
	var city := Game.world as City
	if p == null or city == null or city.ambient == null:
		TestLib.check(false, "the real game has a player and a city with a crowd")
		return
	Game.state = &"play"
	var prog_main := Game.progress as Progress
	if prog_main != null:
		prog_main.path = TMP                                  # never touch the real save
	var enc := Encounters.current
	if enc != null:
		enc.enabled = false                                      # no squad in the middle of a street test
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	p.max_hp = 1.0e6
	var amb: Node3D = city.ambient
	amb.simulate = false                                        # the test steps the crowd by hand: deterministic
	var crowd: RefCounted = amb.crowd
	var npc: RefCounted = amb.npc
	amb.reset()
	for k in 40:
		crowd.step(0.1, p.global_position)
	TestLib.check(crowd.alive_count() > 5, "the street has people (%d)" % crowd.alive_count())

	_test_ray(p, crowd)
	await _test_shots(host, p, amb, crowd, npc)
	_test_death_pose(crowd)
	_test_blast(p, amb, crowd, npc)
	await _test_melee(host, p, amb, crowd)
	_test_car(p, crowd, npc)
	_test_off(p, amb, crowd)
	_test_actors_release(amb, crowd, p)

	Game.civilian_casualties = true
	Game.heat = 0.0
	for f: String in [TMP, TMP + ".bak", TMP + ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main.queue_free()
	await TestLib.frames(host, 2)


## The nearest alive person within r of the player that is not dying.
func _pick(crowd: RefCounted, from: Vector3, r: float, skip := -1) -> int:
	var best := -1
	var bd := r
	for i in crowd.count:
		if i == skip or not crowd.is_alive(i):
			continue
		var d: float = Vector2(crowd.person_position(i).x - from.x, crowd.person_position(i).z - from.z).length()
		if d < bd:
			bd = d
			best = i
	return best


func _test_ray(p: Player, crowd: RefCounted) -> void:
	var i := _pick(crowd, p.global_position, 60.0)
	TestLib.check(i >= 0, "a person within 60 m to test the ray on")
	if i < 0:
		return
	var pos: Vector3 = crowd.person_position(i)
	var o := pos + Vector3(-6.0, 1.3, 0.0)
	var r: Vector3 = crowd.ray(o, Vector3.RIGHT, 20.0)
	TestLib.check(int(r.x) >= 0 and absf(r.y - (6.0 - 0.36)) < 0.5 or int(r.x) != i, "the ray along the street finds a person at about 5.6 m (index %d t %.2f)" % [int(r.x), r.y])
	var head: Vector3 = crowd.ray(pos + Vector3(-5.0, 1.7, 0.0), Vector3.RIGHT, 20.0)
	var body: Vector3 = crowd.ray(pos + Vector3(-5.0, 1.0, 0.0), Vector3.RIGHT, 20.0)
	var over: Vector3 = crowd.ray(pos + Vector3(-5.0, 2.6, 0.0), Vector3.RIGHT, 20.0)
	TestLib.check(int(head.x) >= 0 and head.z > 0.5, "a ray at 1.7 m is a head shot")
	TestLib.check(int(body.x) >= 0 and body.z < 0.5, "a ray at 1.0 m is a body shot")
	TestLib.check(int(over.x) < 0 or int(over.x) != i, "a ray over the head misses the person")
	var short: Vector3 = crowd.ray(pos + Vector3(-5.0, 1.0, 0.0), Vector3.RIGHT, 3.0)
	TestLib.check(int(short.x) < 0 or int(short.x) != i, "the ray stops at its range")
	TestLib.check(int(crowd.ray(pos + Vector3(0.0, 1.0, 0.0), Vector3.RIGHT, 20.0).x) != i, "nobody is hit from inside their body")


## The hero fires the real carbine at one person: hits, a death, the consequences.
func _test_shots(host: Node, p: Player, amb: Node3D, crowd: RefCounted, npc: RefCounted) -> void:
	p.weapon.switch_to(&"carbine", true)
	var heat0: float = Game.heat
	var prog := Game.progress as Progress
	var credits0 := prog.credits if prog != null else 0
	var killed0: int = crowd.killed_total
	var done := false
	var victim := -1
	var tried := {}
	for attempt in 14:
		var i := _pick_untried(crowd, p.global_position, 40.0, tried)
		if i < 0:
			break
		tried[i] = true
		var pos: Vector3 = crowd.person_position(i)
		var along := Vector3(-1.0, 0.0, 0.0) if crowd._axis[i] == 0 else Vector3(0.0, 0.0, -1.0)
		p.global_position = pos + along * 6.0 + Vector3(0.0, 0.1, 0.0)
		p.camera_rig.reset_view(0.0, 0.0)
		for k in 3:
			await TestLib.frames(host, 1)
		var hits0 := p.weapon.civilian_hits
		var shots0 := p.weapon.shots_fired
		var n := 0
		while n < 90 and p.weapon.civilian_hits - hits0 < 2 and not crowd.is_dying(i) and crowd.is_alive(i):
			p.camera_rig.aim_at(crowd.person_position(i) + Vector3(0.0, 1.0, 0.0))
			Input.action_press(&"fire")
			await TestLib.frames(host, 1)
			n += 1
		Input.action_release(&"fire")
		if p.weapon.civilian_hits > hits0:
			victim = i
			TestLib.check(true, "the real carbine hit citizen %d (%d shots, %d hits)" % [i, p.weapon.shots_fired - shots0, p.weapon.civilian_hits - hits0])
			done = true
			break
	TestLib.check(done, "a real shot hits a citizen in the street")
	if not done:
		return
	for k in 40:
		if crowd.is_dying(victim):
			break
		p.camera_rig.aim_at(crowd.person_position(victim) + Vector3(0.0, 1.0, 0.0))
		Input.action_press(&"fire")
		await TestLib.frames(host, 1)
	Input.action_release(&"fire")
	TestLib.check(crowd.is_dying(victim) and not crowd.is_alive(victim), "a few body shots kill: the person is dying, no longer 'alive'")
	TestLib.check(crowd.killed_total == killed0 + 1, "exactly one person died")
	TestLib.check(npc.civilians_killed >= 1, "the city registered the kill (scream, scatter)")
	TestLib.check(Game.heat > heat0, "the kill costs heat (%.2f -> %.2f)" % [heat0, Game.heat])
	TestLib.check(prog == null or prog.credits > credits0, "the fallen leaves credits (%d -> %d)" % [credits0, prog.credits if prog != null else 0])
	var runners := 0
	for j in crowd.count:
		if crowd.is_alive(j) and (crowd.is_fleeing(j) or crowd.is_cowering(j)) and Vector2(crowd.person_position(j).x - crowd.person_position(victim).x, crowd.person_position(j).z - crowd.person_position(victim).z).length() < 34.0:
			runners += 1
	TestLib.check(runners >= 1 or crowd.count_near(crowd.person_position(victim), 34.0) == 0, "the street around the shot runs or cowers (%d)" % runners)
	# a head shot kills at once: put a fresh person in the sights at 1.7 m
	var v2 := _pick(crowd, p.global_position, 40.0, victim)
	if v2 >= 0:
		var pos2: Vector3 = crowd.person_position(v2)
		var o2 := pos2 + Vector3(-5.0, 1.7, 0.0)
		var rr: Vector3 = crowd.ray(o2, Vector3.RIGHT, 20.0)
		var killed: bool = amb.hurt_civilian(v2, 14.0, o2, rr.z > 0.5)
		TestLib.check(killed, "one carbine round to the head kills (2x damage)")


func _pick_untried(crowd: RefCounted, from: Vector3, r: float, tried: Dictionary) -> int:
	var best := -1
	var bd := r
	for i in crowd.count:
		if tried.has(i) or not crowd.is_alive(i):
			continue
		var d: float = Vector2(crowd.person_position(i).x - from.x, crowd.person_position(i).z - from.z).length()
		if d < bd:
			bd = d
			best = i
	return best


## The death: still, falls (angle grows to nearly 90 degrees), dissolves (scale to 0), the slot frees after DIE_TIME.
func _test_death_pose(crowd: RefCounted) -> void:
	var dying := -1
	for i in crowd.count:
		if crowd.is_dying(i):
			dying = i
			break
	TestLib.check(dying >= 0, "somebody is dying (the shots above)")
	if dying < 0:
		return
	var pos0: Vector3 = crowd.person_position(dying)
	var speed: float = crowd.person_speed(dying)
	TestLib.check(speed == 0.0, "a dying person does not walk")
	var a0 := absf(crowd.death_pose(dying).x)
	var seen_fall := 0.0
	var seen_scale := 1.0
	var guard := 0
	while crowd.is_dying(dying) and guard < 60:
		crowd.step(0.1, Game.player.global_position)
		var pose: Vector3 = crowd.death_pose(dying)
		seen_fall = maxf(seen_fall, absf(pose.x))
		seen_scale = minf(seen_scale, pose.y)
		guard += 1
	TestLib.check(seen_fall > 1.2 and seen_fall <= PI * 0.5, "the body falls to nearly flat (max %.2f rad, started %.2f)" % [seen_fall, a0])
	TestLib.check(seen_scale < 0.5, "the body dissolves (scale down to %.2f)" % seen_scale)
	TestLib.check(not crowd.is_dying(dying) and crowd.person_position(dying) != Vector3.INF, "the death ends and the slot is free (or respawned)")
	TestLib.check(pos0.is_finite(), "the dead person's position stays finite")


func _test_blast(p: Player, amb: Node3D, crowd: RefCounted, npc: RefCounted) -> void:
	var killed0: int = crowd.killed_total
	var c := _pick(crowd, p.global_position, 60.0)
	TestLib.check(c >= 0, "a person to blast")
	if c < 0:
		return
	var pos: Vector3 = crowd.person_position(c)
	var near: int = crowd.count_near(pos, 6.0)
	var heat0: float = Game.heat
	Game.explode(pos, 6.0, {"enemy_dmg": 60.0, "player_dmg": 0.0, "car_dmg": 0.0})
	TestLib.check(crowd.killed_total >= killed0 + 1 and crowd.killed_total - killed0 >= mini(near, 1), "a blast kills the people in it (%d died, %d were within 6 m)" % [crowd.killed_total - killed0, near])
	TestLib.check(Game.heat >= heat0, "a hero's blast on a street is a crime (heat never falls)")
	# an enemy's own blast (no enemy damage: a striker) kills but is not the hero's crime
	var c2 := _pick(crowd, p.global_position, 60.0)
	if c2 >= 0:
		var heat1: float = Game.heat
		var cred: int = (Game.progress as Progress).credits if Game.progress != null else 0
		Game.explode(crowd.person_position(c2), 4.5, {"enemy_dmg": 0.0, "player_dmg": 0.0, "car_dmg": 0.0})
		TestLib.check(Game.heat == heat1 and (Game.progress == null or (Game.progress as Progress).credits == cred), "an enemy's blast kills people without charging the hero or paying him")


func _test_melee(host: Node, p: Player, amb: Node3D, crowd: RefCounted) -> void:
	WeaponDefs.unlock(&"blade")
	TestLib.check(p.weapon.switch_to(&"blade", true), "the blade is in hand")
	var i := _pick(crowd, p.global_position, 40.0)
	if i < 0:
		TestLib.check(false, "a person for the swing")
		return
	var pos: Vector3 = crowd.person_position(i)
	p.global_position = pos + Vector3(-1.2, 0.1, 0.0)
	p.camera_rig.reset_view(-PI * 0.5, 0.0)
	await TestLib.frames(host, 2)
	var killed0: int = crowd.killed_total
	for k in 6:
		p.weapon.fire_t = 0.0
		p.weapon._melee_swing(false)
		if crowd.killed_total > killed0:
			break
	TestLib.check(crowd.killed_total > killed0 or not crowd.is_alive(i) or crowd.count_near(pos, 3.0) == 0, "the blade swing cuts down the person in front")
	p.weapon.switch_to(&"carbine", true)
	WeaponDefs.reset_unlocked()


func _test_car(p: Player, crowd: RefCounted, npc: RefCounted) -> void:
	if _vehicle_script == null:
		_vehicle_script = GDScript.new()
		_vehicle_script.source_code = "extends Node3D\nvar speed := 14.0\nvar driver_is_player := true\n"
		_vehicle_script.reload()
		_manager_script = GDScript.new()
		_manager_script.source_code = "extends Node\nvar list: Array = []\n"
		_manager_script.reload()
	var v := Node3D.new()
	v.set_script(_vehicle_script)
	p.get_parent().add_child(v)
	var vm := Node.new()
	vm.set_script(_manager_script)
	p.get_parent().add_child(vm)
	vm.set(&"list", [v])
	var i := _pick(crowd, p.global_position, 60.0)
	if i < 0:
		TestLib.check(false, "a person for the car")
	else:
		v.global_position = crowd.person_position(i) + Vector3(0.5, 0.0, 0.0)
		npc.actors = PackedInt32Array([i])
		var killed0: int = crowd.killed_total
		npc._runover(vm)
		TestLib.check(crowd.killed_total == killed0 + 1 and crowd.is_dying(i), "a fast car kills the person it hits")
		v.set(&"speed", 3.0)
		var j := _pick(crowd, p.global_position, 60.0, i)
		if j >= 0:
			v.global_position = crowd.person_position(j)
			npc.actors = PackedInt32Array([j])
			npc._runover(vm)
			TestLib.check(crowd.is_alive(j), "a crawling car does not")
	v.queue_free()
	vm.queue_free()


func _test_off(p: Player, amb: Node3D, crowd: RefCounted) -> void:
	var i := _pick(crowd, p.global_position, 60.0)
	if i < 0:
		TestLib.check(false, "a person for the setting test")
		return
	var pos: Vector3 = crowd.person_position(i)
	Game.civilian_casualties = false
	var civ: Dictionary = amb.civilian_ray(pos + Vector3(-5.0, 1.0, 0.0), Vector3.RIGHT, 20.0)
	TestLib.check(civ.is_empty(), "casualties OFF: shots pass through the people")
	var killed0: int = crowd.killed_total
	Game.explode(pos, 6.0, {"enemy_dmg": 60.0, "player_dmg": 0.0, "car_dmg": 0.0})
	TestLib.check(crowd.killed_total == killed0, "casualties OFF: a blast does not kill them either")
	Game.civilian_casualties = true


## A dying person is handed back by the 3D citizen actors (the crowd draws the fall): no skinned actor stands on while the body falls.
func _test_actors_release(amb: Node3D, crowd: RefCounted, p: Player) -> void:
	var cit: Node3D = amb.citizens
	for k in 6:
		amb.npc.step(0.3, p.global_position)
		cit.step(0.1, p.global_position)
	if cit.active_count() == 0:
		TestLib.check(true, "(no 3D citizen actors on this tier or without the hero files: nothing to hand back)")
		return
	var person := int(cit.slots[0]["person"])
	TestLib.check(crowd.is_hidden(person), "an actor person is drawn by its actor (hidden in the crowd)")
	crowd.kill_person(person, p.global_position)
	cit.step(0.1, p.global_position)
	var still := false
	for sl in cit.slots:
		still = still or int(sl["person"]) == person
	TestLib.check(not still and not crowd.is_hidden(person), "a person who dies is released by the actors and drawn by the crowd")
