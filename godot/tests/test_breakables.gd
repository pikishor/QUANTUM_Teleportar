extends RefCounted
## Breakable world in the REAL game scene: props, bullets via a real ray, explosions, a vehicle, debris pool, respawn, idle cost, per-surface decals.
## Run: tools/test.sh tests/test_breakables.gd


func _ray(host: Node, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.L_WORLD)
	return host.get_viewport().world_3d.direct_space_state.intersect_ray(q)


func _pick(b: Breakables, name: String, skip := 0) -> int:
	for i in Breakables.COUNT:
		if Breakables.KINDS[b.kind_of[i]]["name"] == name and b.broken[i] == 0:
			if skip == 0:
				return i
			skip -= 1
	return -1


func run(host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://progress.cfg"))
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 4)
	Game.state = &"play"
	var b := Breakables.current
	TestLib.check(is_instance_valid(b) and b.get_parent() == main, "Breakables is instantiated by main.gd")
	if not is_instance_valid(b):
		return
	TestLib.check(b.bodies.size() == Breakables.COUNT, "one body per prop")
	for k in Breakables.KINDS.size():
		var found := false
		for i in Breakables.COUNT:
			if b.kind_of[i] == k:
				found = true
		TestLib.check(found, "kind %s is placed" % Breakables.KINDS[k]["name"])
	var p: Node3D = Game.player
	p.set_physics_process(false)
	p.global_position = Vector3(0.0, 400.0, 0.0)          # away from everything: respawn is allowed
	var draws_note := b.get_node("Props") as MultiMeshInstance3D
	TestLib.check(draws_note.multimesh.instance_count == Breakables.COUNT, "all intact props are one MultiMesh")
	TestLib.check(not b.is_processing(), "idle: no per-frame processing")
	TestLib.check(not (b.get_node("Debris") as Node3D).visible, "idle: debris draw hidden")
	await TestLib.frames(host, 3)

	# --- bullets: a real ray finds the collider, hp counts down, glass breaks at once
	var g := _pick(b, "window")
	var gp: Vector3 = b.positions[g]
	var r := _ray(host, gp + Vector3(0, 0, 3).rotated(Vector3.UP, b.yaws[g]), gp)
	TestLib.check(not r.is_empty() and b.index_of(r["collider"]) == g, "a ray hits the glass prop's collider")
	TestLib.check(Breakables.surface_of(r["collider"]) == &"glass", "glass collider reports the glass surface")
	TestLib.check(b.hit_at(r["collider"], r["position"], r["normal"]), "bullet hit is handled")
	TestLib.check(b.broken[g] == 1 and b.broken_count == 1, "glass breaks in one hit")
	TestLib.check(b.bodies[g].collision_layer == 0, "a broken prop loses its collider")
	TestLib.check(b.debris_live > 0 and b.is_processing(), "debris flies from the break")
	var r2 := _ray(host, gp + Vector3(0, 0, 3).rotated(Vector3.UP, b.yaws[g]), gp)
	TestLib.check(r2.is_empty() or b.index_of(r2["collider"]) != g, "bullets and bodies pass through the gap")

	var c := _pick(b, "crate")
	var hp0 := int(b.hp[c])
	b.hit_at(b.bodies[c], b.positions[c], Vector3.UP)
	TestLib.check(b.hp[c] == hp0 - 1 and b.broken[c] == 0, "a crate survives the first hit")
	for _i in hp0:
		b.hit_at(b.bodies[c], b.positions[c], Vector3.UP)
	TestLib.check(b.broken[c] == 1, "a crate breaks after its hit points")

	# --- debris is pooled, never more than DEBRIS, and ends
	var nodes_before := main.get_tree().get_node_count()
	for i in 10:
		var k := _pick(b, "vending", 0)
		if k >= 0:
			b.break_prop(k)
	for i in 6:
		var k := _pick(b, "stall", 0)
		if k >= 0:
			b.break_prop(k)
	TestLib.check(b.debris_live <= Breakables.DEBRIS, "debris stays inside the pool (%d)" % b.debris_live)
	TestLib.check(main.get_tree().get_node_count() == nodes_before, "breaking creates no nodes")
	var t := 0.0
	while b.debris_live > 0 and t < 12.0:
		await TestLib.frames(host, 10)
		t += 10.0 / 60.0
		if t > 0.0 and b.debris_live > 0 and not b.is_processing():
			break
	# headless frames may run fast or slow; drive the sim by hand to the end of life
	for _i in 100:
		if b.debris_live <= 0:
			break
		b._process(0.1)
	TestLib.check(b.debris_live == 0 and not b.is_processing(), "debris ends and processing stops")
	TestLib.check(not (b.get_node("Debris") as Node3D).visible, "debris draw hidden again")

	# --- explosion through the real Game.explode
	var s := _pick(b, "bin")
	var before := b.broken_count
	Game.explode(b.positions[s] + Vector3(0.5, 0.0, 0.0), 4.0, {"enemy_dmg": 0.0, "car_dmg": 0.0, "player_dmg": 0.0})
	TestLib.check(b.broken[s] == 1 and b.broken_count > before, "Game.explode breaks nearby props")

	# --- vehicle: a fast car through a prop breaks it
	var f := _pick(b, "fence")
	var holder := _FakeCar.new()
	holder.add_to_group(&"vehicle")
	host.add_child(holder)
	holder.speed = 12.0
	holder.global_position = b.positions[f] + Vector3(0.5, 0.0, 0.0)
	b._vehicle_tick()
	TestLib.check(b.broken[f] == 1, "a vehicle moving fast breaks a prop on its path")
	var f2 := _pick(b, "fence")
	holder.speed = 1.0
	b._last_speed.clear()
	holder.global_position = b.positions[f2] + Vector3(0.5, 0.0, 0.0)
	b._vehicle_tick()
	TestLib.check(b.broken[f2] == 0, "a slow vehicle does not break props")
	holder.queue_free()

	# --- respawn: only after the delay, with the player away
	TestLib.check(b.broken_count > 0, "props are broken before the respawn check")
	for i in Breakables.COUNT:
		if b.broken[i] == 1:
			b.respawn_at[i] = PlayerUtil.now() + 100.0
	b._respawn_tick()
	TestLib.check(b.broken_count > 0, "props stay broken before the delay")
	for i in Breakables.COUNT:
		if b.broken[i] == 1:
			b.respawn_at[i] = PlayerUtil.now() - 1.0
	var near := b.positions[g]
	p.global_position = near + Vector3(2.0, 0.0, 0.0)
	b._respawn_tick()
	TestLib.check(b.broken[g] == 1, "a prop does not respawn in front of the player")
	p.global_position = Vector3(0.0, 400.0, 0.0)
	b._respawn_tick()
	TestLib.check(b.broken_count == 0 and b.broken[g] == 0, "props respawn once the player is away")
	TestLib.check(b.bodies[g].collision_layer == Game.L_WORLD and b.hp[g] > 0, "respawned prop is solid again with full hp")
	TestLib.check(b._timer.is_stopped(), "respawn timer stops when nothing is broken")

	# --- decals per surface
	var d: ImpactDecals = p.decals
	d.clear()
	for i in 30:
		d.add(Vector3(-10.5, 1.0 + i * 0.01, 4.0), Vector3(1, 0, 0), 0.17, &"glass")
	TestLib.check(d.count_on(&"glass") == int(ImpactDecals.SURFACES[&"glass"]["quota"]), "glass decals capped at their quota (%d)" % d.count_on(&"glass"))
	for i in 20:
		d.add(Vector3(-10.5, 2.0 + i * 0.01, 4.0), Vector3(1, 0, 0), 0.17, &"metal")
	TestLib.check(d.count_on(&"metal") == int(ImpactDecals.SURFACES[&"metal"]["quota"]), "metal decals capped at their quota")
	TestLib.check(d.count_on(&"glass") > 0, "metal holes do not push out glass")
	d.add(Vector3(-10.5, 3.0, 4.0), Vector3(1, 0, 0))
	TestLib.check(d.count_on(&"concrete") == 1, "default surface is concrete")
	TestLib.check(d.active_count() <= ImpactDecals.CAPACITY, "ring still bounded")
	d.clear()
	b.reset()
	TestLib.check(b.broken_count == 0 and b.debris_live == 0, "reset restores everything")


class _FakeCar extends Node3D:
	var speed := 0.0
