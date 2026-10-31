extends RefCounted
## Enemies module tests (headless): DynamicFill (layer, tint, light), types and the damage contract (crit, mirrored, link), death (score, heat, energy, drops,
## pool reuse), awareness, line of sight, firing (bolts, burst, operative hitscan), the striker explosion, the clone as a target, manager caps per tier,
## patrols, reinforcements by heat, heat decay and the lifecycle resets.
## Runs against the player test environment (floor, wall, a real Player) and small stubs for the world, missions and quantum; no other module is needed.
## Time runs 4x (time_scale and tick rate together, see ARCHITECTURE.md); every wait is in ticks of 1/60 s of game time.
## Run: tools/test.sh tests/test_enemies.gd

const Env := preload("res://tests/player_env.gd")
const Stubs := preload("res://tests/enemies_stubs.gd")

const K := 4

var e := Env.new()
var p: Player
var mgr: EnemyManager
var root: Node3D
var stub_missions := Stubs.StubMissions.new()
var stub_quantum := Stubs.StubQuantum.new()
var _saved_quality := 1


func run(host: Node) -> void:
	seed(11)
	await e.setup(host)
	p = e.p
	root = e.root
	_saved_quality = Game.quality
	Engine.time_scale = K
	Engine.physics_ticks_per_second = 60 * K
	p.max_hp = 1.0e6
	root.add_child(stub_missions)
	Game.missions = stub_missions
	await _dynamic_fill()
	_make_manager(false)
	await e.frames(3)
	await _types_and_contract()
	await _damage_contract()
	await _death()
	await _awareness()
	await _line_of_sight()
	await _firing()
	await _operative()
	await _striker()
	await _clone_target()
	await _caps()
	await _patrols()
	await _reinforcements()
	await _heat_decay()
	await _lifecycle()
	# teardown
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Game.set_quality(_saved_quality)
	Game.missions = null
	Game.world = null
	Game.heat = 0.0
	Game.score = 0
	p.quantum = null
	stub_quantum.free()
	if is_instance_valid(mgr):
		mgr.queue_free()
	await e.teardown()


func secs(s: float) -> void:
	await e.frames(int(ceil(s * 60.0)))


func _make_manager(with_world: bool) -> void:
	if is_instance_valid(mgr):
		mgr.free()
	Game.world = Stubs.StubWorld.new() if with_world else null
	if Game.world != null:
		root.add_child(Game.world)
	mgr = (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	root.add_child(mgr)


## A clean slate: no enemies, bolts or heat, the player standing at (-30, 0, 4) looking +X with plenty of health.
func _fresh(quality := 1) -> void:
	Game.set_quality(quality)
	mgr.clear()
	Game.heat = 0.0
	Game.quiet = 0.0
	Game.score = 0
	stub_missions.drops.clear()
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	p.hp = p.max_hp
	p.energy = 50.0
	stub_quantum.clone = null
	p.quantum = stub_quantum
	if stub_quantum.get_parent() == null:
		root.add_child(stub_quantum)


func _spawn(type: StringName, pos: Vector3, aware := false, reinforce := false) -> Drone:
	var d := mgr.spawn(type, pos, aware, reinforce)
	TestLib.check(d != null, "spawn(%s) returned a drone" % type)
	return d


# ----------------------------------------------------------------------------------------------------------------------

func _dynamic_fill() -> void:
	var m := Game.load_model("drone_sentinel")
	TestLib.check(m != null, "drone_sentinel model loads")
	var imported_glow := 0.0
	var first := m.get_node("Body") as MeshInstance3D
	for s in first.mesh.get_surface_count():
		var mat := first.mesh.surface_get_material(s) as BaseMaterial3D
		if mat != null and String(mat.resource_name) == "Glow":
			imported_glow = mat.emission_energy_multiplier
	var tint := Color(1.0, 0.24, 0.37)
	root.add_child(m)
	DynamicFill.apply(m, tint)
	var all_fill := true
	var lifted := 0
	var eye_ok := false
	var own := true
	for mi: MeshInstance3D in DynamicFill._meshes(m):
		if (mi.layers & 1) == 0 or (mi.layers & DynamicFill.FILL_BIT) == 0:
			all_fill = false
		for s in mi.mesh.get_surface_count():
			var ov := mi.get_surface_override_material(s) as BaseMaterial3D
			if ov == null or ov == mi.mesh.surface_get_material(s):
				own = false
				continue
			if mi.name == &"Eye":
				eye_ok = ov.emission_enabled and ov.emission.is_equal_approx(tint) and ov.emission_energy_multiplier <= 2.0 + 0.001
			elif String(ov.resource_name) != "Glow" and ov.albedo_color.r > 1.4:
				lifted += 1
	TestLib.check(all_fill, "DynamicFill puts every mesh on layer 1 and layer 19")
	TestLib.check(own, "every surface has its own override material (the imported one is shared)")
	TestLib.check(eye_ok, "the Eye glows in the tint with emission <= 2")
	TestLib.check(lifted <= 3, "the baked drone atlases already sit at about 0.1 albedo or more, so DynamicFill lifts at most a few surfaces (%d lifted by > 1.4)" % lifted)
	var still := 0.0
	for s in first.mesh.get_surface_count():
		var mat := first.mesh.surface_get_material(s) as BaseMaterial3D
		if mat != null and String(mat.resource_name) == "Glow":
			still = mat.emission_energy_multiplier
	TestLib.check(is_equal_approx(still, imported_glow), "the imported (shared) materials stay untouched")
	TestLib.check((DynamicFill.FILL_BIT & 1) == 0 and DynamicFill.FILL_BIT == 1 << 18 and (1 << 19) != DynamicFill.FILL_BIT, "the fill layer is visual layer 19, not 1 or the player's 20")
	m.queue_free()
	# the one shared light
	var holder := Node3D.new()
	root.add_child(holder)
	Game.quality = 1
	var l := DynamicFill.ensure_light(holder)
	TestLib.check(l is DirectionalLight3D and l.light_cull_mask == DynamicFill.FILL_BIT, "the fill light is a DirectionalLight3D culled to layer 19 only")
	TestLib.check(not l.shadow_enabled and l.light_energy <= 1.0, "no shadows, low energy")
	TestLib.check(DynamicFill.ensure_light(holder) == l, "the light is created once")
	TestLib.check(l.visible, "the light is on at MED")
	DynamicFill.set_quality(0)
	TestLib.check(not l.visible, "LOW: no extra light")
	DynamicFill.set_quality(1)
	TestLib.check(l.visible, "MED: light back on")
	DynamicFill.aim_light(1.0)
	TestLib.check(absf(l.rotation.y - 1.0) < 0.001, "aim_light turns the light with the camera yaw")
	holder.queue_free()
	await e.frames(2)


func _types_and_contract() -> void:
	await _fresh()
	TestLib.check(Game.enemies == mgr, "Game.enemies is the manager")
	TestLib.check(mgr.cap() == 8, "MED cap is 8")
	var want := {&"sentinel": [60.0, 0.95], &"striker": [34.0, 0.8], &"heavy": [230.0, 1.35], &"operative": [80.0, 0.55]}
	var x := 20.0
	for t: StringName in want:
		var d := _spawn(t, Vector3(x, 0.0, 40.0))
		x += 4.0
		TestLib.check(is_equal_approx(d.hp, want[t][0]) and is_equal_approx(d.max_hp, want[t][0]), "%s hp %s" % [t, want[t][0]])
		TestLib.check(is_equal_approx(d.radius, want[t][1]), "%s radius %s" % [t, want[t][1]])
		TestLib.check(d.type == t and d.is_in_group(&"enemy") and d.collision_layer == Game.L_ENEMY and not d.dead, "%s: type, group enemy, layer enemy, alive" % t)
		TestLib.check(d.center().y > 0.5 and d.has_method(&"damage") and d.has_method(&"alert"), "%s: center() and the contract methods" % t)
		TestLib.check(d.uses_model, "%s uses its glb model" % t)
		TestLib.check(d is Operative == (t == &"operative"), "%s class" % t)
	TestLib.check(mgr.alive_count() == 4, "four alive")
	TestLib.check(mgr.get_children().filter(func(c: Node) -> bool: return c is Drone).size() == 4, "four pooled nodes")
	mgr.clear()
	TestLib.check(mgr.alive_count() == 0 and get_enemy_nodes() == 0, "clear() empties the group")


func get_enemy_nodes() -> int:
	return mgr.get_tree().get_nodes_in_group(&"enemy").size()


func _damage_contract() -> void:
	await _fresh()
	var a := _spawn(&"sentinel", Vector3(20.0, 0.0, 4.0))
	var b := _spawn(&"sentinel", Vector3(45.0, 0.0, 4.0))     # 25 m from a: inside the 35 m alert radius
	var c := _spawn(&"sentinel", Vector3(70.0, 0.0, 4.0))     # 50 m from a: outside
	a.damage(14.0)
	TestLib.check(is_equal_approx(a.hp, 46.0) and a.aware, "damage(14) leaves 46 hp and wakes the target")
	TestLib.check(b.aware and not c.aware, "a hit alerts neighbours within 35 m only")
	a.damage(30.0, true)
	TestLib.check(is_equal_approx(a.hp, 16.0), "a crit hit is applied with its amount (the weapon scales it)")
	# mirrored damage does not alert
	mgr.clear()
	a = _spawn(&"sentinel", Vector3(20.0, 0.0, 4.0))
	b = _spawn(&"sentinel", Vector3(30.0, 0.0, 4.0))
	a.damage(5.0, false, true)
	TestLib.check(not b.aware, "mirrored damage does not alert neighbours")
	# quantum link: damage is mirrored once, does not bounce back
	a.linked = b
	b.linked = a
	a.damage(10.0)
	TestLib.check(is_equal_approx(a.hp, 45.0) and is_equal_approx(b.hp, 50.0), "a linked drone takes the mirrored damage once (a 45, b 50)")
	a.hp = 5.0
	a.damage(10.0)
	TestLib.check(a.dead and not b.dead, "killing one linked drone does not kill the other")
	# a dead target ignores further damage
	var before := Game.score
	a.damage(50.0)
	TestLib.check(Game.score == before, "damage to a corpse does nothing")


func _death() -> void:
	await _fresh()
	var d := _spawn(&"sentinel", Vector3(20.0, 0.0, 4.0))
	p.energy = 50.0
	d.damage(1000.0)
	TestLib.check(d.dead and not d.is_in_group(&"enemy"), "a dead drone leaves the enemy group")
	TestLib.check(Game.score == 50, "sentinel kill: +50 score (got %d)" % Game.score)
	TestLib.check(is_equal_approx(Game.heat, 0.22), "sentinel kill: +0.22 heat (got %.2f)" % Game.heat)
	TestLib.check(is_equal_approx(p.energy, 58.0), "energy refund +8 (got %.1f)" % p.energy)
	TestLib.check(mgr.alive_count() == 0, "a corpse does not count towards the cap")
	await secs(1.0)
	TestLib.check(not mgr.list.has(d) and not d.visible, "the death animation ends and the manager releases the drone")
	# pool reuse: no new nodes for the next life
	var kids := mgr.get_child_count()
	var d2 := _spawn(&"sentinel", Vector3(22.0, 0.0, 4.0))
	TestLib.check(d2 == d and mgr.get_child_count() == kids and d2.hp == 60.0 and not d2.dead, "a pooled drone is reused with full hp")
	# drops: about 30 % health, 30 % energy over many kills
	mgr.clear()
	stub_missions.drops.clear()
	for i in 60:
		var k := mgr.spawn(&"striker", Vector3(30.0, 0.0, 30.0))
		k.damage(999.0)
		mgr.release(k)
	var health := 0
	var energy := 0
	for dr in stub_missions.drops:
		if dr[0] == &"health":
			health += 1
		elif dr[0] == &"energy":
			energy += 1
	TestLib.check(health >= 8 and health <= 30 and energy >= 8 and energy <= 30, "drops: ~30 %% health (%d) and ~30 %% energy (%d) of 60 kills" % [health, energy])
	Game.heat = 0.0
	# operative corpse
	mgr.clear()
	var o := _spawn(&"operative", Vector3(20.0, 0.0, 4.0))
	Game.graphic_violence = false
	o.damage(30.0)
	o.damage(1000.0)
	await secs(0.7)
	TestLib.check(o.dead and absf(absf(o.model.rotation.z) - PI * 0.5) < 0.1, "an operative falls onto its side")
	TestLib.check(mgr.list.has(o), "the corpse lies there for a while")
	await secs(4.2)
	TestLib.check(not mgr.list.has(o), "then it is released")
	Game.graphic_violence = true
	var o2 := _spawn(&"operative", Vector3(20.0, 0.0, 4.0))
	o2.damage(20.0)
	o2.damage(1000.0)
	Game.graphic_violence = false
	TestLib.check(o2.dead, "the blood branch (graphic_violence) runs without error")
	Game.heat = 0.0


func _awareness() -> void:
	await _fresh()
	var far := _spawn(&"sentinel", Vector3(20.0, 0.0, 4.0))     # 50 m
	await secs(0.6)
	TestLib.check(not far.aware, "50 m away, heat 0: still idle")
	var wander := far.global_position
	TestLib.check(Vector2(wander.x - 20.0, wander.z - 4.0).length() < 14.0, "idle drones stay near home")
	Game.heat = 1.0
	await secs(0.3)
	TestLib.check(far.aware, "heat > 0 and within 80 m: aware")
	Game.heat = 0.0
	mgr.clear()
	var near := _spawn(&"sentinel", Vector3(-10.0, 0.0, 40.0))   # about 41 m: outside 32
	var close := _spawn(&"sentinel", Vector3(-30.0, 0.0, 30.0))  # 26 m
	await secs(0.3)
	TestLib.check(close.aware and not near.aware, "within 32 m: aware; at 41 m: not")
	Game.heat = 0.0


func _line_of_sight() -> void:
	await _fresh()
	await e.prep(Vector3(-20.0, 0.0, 4.0))            # west of the wall (x -10.5 .. -9.5, z -6 .. 14)
	var d := _spawn(&"sentinel", Vector3(0.0, 0.0, 4.0), true)
	await secs(0.5)
	TestLib.check(d.aware and not d.los, "the wall between them: no line of sight")
	mgr.clear()
	await e.prep(Vector3(-20.0, 0.0, 30.0))           # beyond the wall's end
	d = _spawn(&"sentinel", Vector3(0.0, 0.0, 30.0), true)
	await secs(0.5)
	TestLib.check(d.aware and d.los, "open ground: line of sight")
	Game.heat = 0.0


func _firing() -> void:
	await _fresh()
	p.max_hp = 1000.0
	p.hp = 1000.0
	var d := _spawn(&"sentinel", Vector3(-16.0, 0.0, 4.0), true)
	var peak := 0
	for i in 150:
		await e.frames(1)
		peak = maxi(peak, mgr.active_bolts())
	TestLib.check(peak >= 1, "a sentinel with a line of sight fires bolts (peak %d in flight)" % peak)
	TestLib.check(p.hp < 1000.0, "a bolt reached the player (hp %.1f)" % p.hp)
	# the shot is dodgeable: it travels at 30 m/s
	mgr.clear()
	var hp0 := p.hp
	mgr.bolt(Vector3(-16.0, 1.2, 4.0), Vector3(-30.0, 1.2, 14.0), &"sentinel")   # aimed 10 m to the side of the player
	await secs(1.0)
	TestLib.check(is_equal_approx(p.hp, hp0), "a bolt that misses the player does nothing")
	hp0 = p.hp
	mgr.bolt(Vector3(-16.0, 1.2, 4.0), Vector3(-30.0, 1.2, 4.0), &"sentinel")
	await secs(0.8)
	TestLib.check(is_equal_approx(hp0 - p.hp, 7.0), "a bolt on target does its 7 damage (got %.1f)" % (hp0 - p.hp))
	# heavy: 3-round burst
	mgr.clear()
	var h := _spawn(&"heavy", Vector3(-10.0, 0.0, 4.0), true)
	peak = 0
	for i in 200:
		await e.frames(1)
		peak = maxi(peak, mgr.active_bolts())
	TestLib.check(peak >= 3, "the heavy fires a 3-round burst (peak %d)" % peak)
	TestLib.check(h.dead == false, "still alive")
	Game.heat = 0.0
	p.hp = p.max_hp


func _operative() -> void:
	await _fresh()
	p.max_hp = 1000.0
	p.hp = 1000.0
	var o := _spawn(&"operative", Vector3(-18.0, 0.0, 4.0), true) as Operative
	var leg_swing := 0.0
	for i in 300:
		await e.frames(1)
		if o.leg_l != null:
			leg_swing = maxf(leg_swing, o.leg_l.basis.get_rotation_quaternion().get_angle())
	TestLib.check(p.hp < 1000.0, "an operative's burst hit the player (hp %.1f)" % p.hp)
	TestLib.check(leg_swing > 0.05, "the legs swing while it moves (%.2f rad)" % leg_swing)
	TestLib.check(o.rig != null and o.rig.skeleton.get_bone_pose(o.rig.skeleton.find_bone("ShinL")).basis.get_euler().x != 0.0 or o.rig == null, "the knees bend (articulated shins)")
	TestLib.check(absf(o.global_position.y) < 0.05, "an operative stays on the ground")
	# calls for help
	mgr.clear()
	Game.heat = 0.0
	var a := _spawn(&"operative", Vector3(20.0, 0.0, 4.0))
	var b := _spawn(&"sentinel", Vector3(60.0, 0.0, 4.0))      # 40 m: beyond the drone alert radius, inside the call for help
	a.damage(5.0)
	TestLib.check(b.aware, "a hit operative calls for help within 50 m")
	Game.heat = 0.0
	p.hp = p.max_hp


func _striker() -> void:
	await _fresh()
	p.max_hp = 100.0
	p.hp = 100.0
	var s := _spawn(&"striker", Vector3(-24.0, 0.0, 4.0), true)
	await secs(1.2)
	TestLib.check(s.dead or not s.active, "the striker flew into the player and exploded")
	TestLib.check(p.hp < 95.0 and p.hp > 60.0, "the explosion hurt the player (hp %.1f)" % p.hp)
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	Game.heat = 0.0


func _clone_target() -> void:
	await _fresh()
	var clone := Node3D.new()
	root.add_child(clone)
	clone.global_position = Vector3(-10.0, 0.0, 40.0)
	stub_quantum.clone = clone
	clone.add_to_group(&"clone")
	TestLib.check(mgr.get_clone() == clone, "the manager finds player.quantum.clone")
	var d := _spawn(&"sentinel", Vector3(10.0, 0.0, 40.0), true)
	var seen := false
	for i in 120:
		await e.frames(1)
		seen = seen or d._tgt_clone
		if seen:
			break
	TestLib.check(seen, "a drone targets the clone about half the time")
	mgr.clear()
	if is_instance_valid(clone):
		stub_quantum.collapsed = 0
	else:
		clone = Node3D.new()
		root.add_child(clone)
		clone.global_position = Vector3(-10.0, 0.0, 40.0)
		stub_quantum.clone = clone
		stub_quantum.collapsed = 0
	mgr.bolt(Vector3(5.0, 1.0, 40.0), clone.global_position + Vector3(0.0, 1.0, 0.0), &"sentinel")
	await secs(0.8)
	TestLib.check(stub_quantum.collapsed == 1, "a bolt that hits the clone collapses it")
	TestLib.check(mgr.get_clone() == null, "no clone afterwards")
	Game.heat = 0.0


func _caps() -> void:
	for tier in 3:
		await _fresh(tier)
		var cap: int = EnemyTypes.CAPS[tier]
		var n := 0
		for i in 16:
			if mgr.spawn(&"sentinel", Vector3(float(i) * 3.0, 0.0, 60.0)) != null:
				n += 1
		TestLib.check(n == cap and mgr.alive_count() == cap, "tier %d: cap %d alive (got %d)" % [tier, cap, n])
		TestLib.check(mgr.spawn(&"striker", Vector3(0.0, 0.0, 70.0), true, true) == null, "tier %d: reinforcements respect the cap" % tier)
		var l := DynamicFill.get_light()
		TestLib.check(l != null and l.visible == (tier >= 1), "tier %d: fill light %s" % [tier, "on" if tier >= 1 else "off"])
	TestLib.check(EnemyTypes.CAPS[0] == 5 and EnemyTypes.CAPS[1] == 8 and EnemyTypes.CAPS[2] == 12, "caps are LOW 5, MED 8, HIGH 12")
	await _fresh(1)


func _patrols() -> void:
	_make_manager(true)
	await e.frames(2)
	await _fresh(1)
	mgr.init_patrols()
	var groups := mgr.patrol_groups()
	TestLib.check(groups.size() == 7, "7 patrol groups (got %d)" % groups.size())
	var sizes_ok := true
	var far_ok := true
	var heavy := 0
	var ops := 0
	for g: Dictionary in groups:
		sizes_ok = sizes_ok and g["types"].size() >= 2 and g["types"].size() <= 3
		var gp: Vector3 = g["pos"]
		far_ok = far_ok and Vector2(gp.x - Game.SPAWN.x, gp.z - Game.SPAWN.z).length() >= 110.0
		for t in g["types"]:
			heavy += 1 if t == &"heavy" else 0
			ops += 1 if t == &"operative" else 0
	TestLib.check(sizes_ok, "groups of 2-3")
	TestLib.check(far_ok, "all groups at least 110 m from the spawn")
	TestLib.check(ops >= 4, "squads of operatives exist (%d)" % ops)
	var started := mgr.alive_count()
	TestLib.check(started > 0 and started <= mgr.cap() - 2, "patrols start with fewer than the cap (%d of %d)" % [started, mgr.cap()])
	var pending := 0
	for g: Dictionary in groups:
		pending += 0 if g["spawned"] else 1
	TestLib.check(pending > 0, "the other groups wait (%d dormant)" % pending)
	# a dormant group wakes when the player is near and there is room
	mgr.clear()
	for g: Dictionary in groups:
		if not g["spawned"]:
			g["pos"] = Vector3(40.0, 0.0, 40.0)
			break
	await secs(1.6)
	TestLib.check(mgr.alive_count() >= 2, "a dormant group within 150 m is spawned (%d alive)" % mgr.alive_count())
	Game.heat = 0.0


func _reinforcements() -> void:
	TestLib.check(EnemyManager.pick_reinforcement_type(0.0, 0.05) == &"striker" and EnemyManager.pick_reinforcement_type(1.0, 0.3) == &"operative" \
			and EnemyManager.pick_reinforcement_type(1.0, 0.9) == &"sentinel", "type mix at low heat: striker, operative, sentinel")
	TestLib.check(EnemyManager.pick_reinforcement_type(3.0, 0.1) == &"heavy" and EnemyManager.pick_reinforcement_type(3.0, 0.3) == &"striker", "a heavy from heat 3")
	TestLib.check(EnemyManager.pick_reinforcement_type(2.9, 0.1) != &"heavy", "no heavy below heat 3")
	await _fresh(2)
	mgr.init_patrols()
	mgr.clear()
	Game.heat = 0.9
	await secs(3.0)
	TestLib.check(mgr.alive_count() == 0, "heat below 1: no reinforcements")
	p.max_hp = 1.0e6
	for i in 20:
		Game.heat = 2.0
		await secs(0.8)
	var near := 0
	var reinf := 0
	for d in mgr.list:
		if d.dead:
			continue
		reinf += 1 if d.reinforce else 0
		if Vector2(d.global_position.x - p.global_position.x, d.global_position.z - p.global_position.z).length() < 110.0:
			near += 1
	TestLib.check(near >= 4 and near <= 7, "heat 2: floor(2 + 2*2.6) = 7 wanted, %d within 110 m, never more" % near)
	TestLib.check(reinf >= 4 and mgr.alive_count() <= mgr.cap(), "they are reinforcements, within the cap (%d, cap %d)" % [reinf, mgr.cap()])
	# far reinforcements are released
	mgr.clear()
	var d := _spawn(&"sentinel", Vector3(0.0, 0.0, 30.0), true, true)
	d.global_position = p.global_position + Vector3(190.0, 0.0, 0.0)
	await secs(0.2)
	TestLib.check(not mgr.list.has(d), "a reinforcement more than 170 m away is released")
	var pa := _spawn(&"sentinel", Vector3(0.0, 0.0, 30.0), false, false)
	pa.global_position = p.global_position + Vector3(190.0, 0.0, 0.0)
	await secs(0.2)
	TestLib.check(mgr.list.has(pa), "a patrol is not released by distance")
	Game.heat = 0.0


func _heat_decay() -> void:
	await _fresh()
	mgr.clear()
	Game.heat = 0.9                 # below 1: no reinforcements that would watch the player
	Game.quiet = 0.0
	await secs(6.0)
	TestLib.check(Game.heat > 0.899, "no decay in the first 7 quiet seconds (heat %.3f)" % Game.heat)
	await secs(3.0)
	var h := Game.heat
	TestLib.check(h < 0.9 and h > 0.5, "after 7 s of quiet heat falls about 0.12 per second (%.2f)" % h)
	# an aware enemy within 70 m keeps the heat up
	var d := _spawn(&"heavy", Vector3(10.0, 0.0, 4.0), true)
	d.hp = 1.0e6
	d.max_hp = 1.0e6
	Game.quiet = 10.0
	await secs(0.3)
	TestLib.check(Game.quiet < 1.0, "an aware enemy within 70 m resets the quiet timer")
	var h2 := Game.heat
	await secs(2.0)
	TestLib.check(Game.heat >= h2 - 0.001, "no decay while it watches")
	mgr.clear()
	Game.heat = 0.0


func _lifecycle() -> void:
	await _fresh()
	mgr.clear()
	var r := _spawn(&"sentinel", Vector3(30.0, 0.0, 30.0), true, true)
	var q := _spawn(&"sentinel", Vector3(40.0, 0.0, 30.0))
	Game.heat = 0.5
	Game.respawn.emit()
	TestLib.check(not mgr.list.has(r) and mgr.list.has(q), "respawn: reinforcements are removed, patrols stay")
	Game.new_game.emit()
	var reinf := mgr.list.filter(func(d: Drone) -> bool: return d.reinforce).size()
	TestLib.check(reinf == 0 and mgr.alive_count() > 0 and mgr.alive_count() <= mgr.cap() - 2, "new game: cleared and the patrols rebuilt")
	var n1 := mgr.alive_count()
	mgr.bolt(Vector3(0.0, 5.0, 0.0), Vector3(50.0, 5.0, 0.0), &"sentinel")
	TestLib.check(mgr.active_bolts() == 1, "a bolt in flight")
	Game.next_sector.emit()
	TestLib.check(mgr.active_bolts() == 0, "next sector: bolts cleared")
	# the patrol spots are random road points and only the groups within 150 m of the player stream in, so the count differs from run to run (it depends on how much of the world RNG was used before)
	TestLib.check(mgr.alive_count() > 0 and mgr.alive_count() <= mgr.cap() - 2 and absi(mgr.alive_count() - n1) <= 3, "next sector: patrols rebuilt (%d, was %d)" % [mgr.alive_count(), n1])
	# not playing: nothing moves
	Game.state = &"paused"
	var d: Drone = null
	for dd in mgr.list:
		if not dd.dead:
			d = dd
			break
	var pos := d.global_position
	await secs(0.5)
	TestLib.check(d.global_position.is_equal_approx(pos), "paused: enemies do not simulate")
	Game.state = &"play"
	mgr.clear()
	# registry clears on exit
	var holder := mgr
	root.remove_child(holder)
	TestLib.check(Game.enemies == null, "Game.enemies is cleared when the manager leaves the tree")
	holder.free()
	Game.heat = 0.0
