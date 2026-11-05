extends RefCounted
## Missions module tests (headless): placement rules over many seeds, collecting a core, winning, round growth, drops and pickups, resets,
## the vehicle trigger, pools and caps. Uses a fake world (the real junction list) and a fake player, so no other module is needed.
## Run: tools/test.sh tests/test_missions.gd

class FakeWorld extends Node3D:
	var intersections: Array[Vector3] = []


class FakePlayer extends Node3D:
	var hp := 100.0
	var max_hp := 100.0
	var energy := 100.0
	var max_energy := 100.0
	var vehicle: Node3D = null

	func heal(v: float) -> void:
		hp = minf(max_hp, hp + v)

	func add_energy(v: float) -> void:
		energy = minf(max_energy, energy + v)


var root: Node3D
var world: FakeWorld
var player: FakePlayer
var m: Missions
var messages: Array[String] = []
var wins := 0


func run(host: Node) -> void:
	var was_muted := Sfx.muted
	Sfx.muted = true
	root = Node3D.new()
	host.add_child(root)
	world = FakeWorld.new()
	world.intersections = CityLayout.make_intersections()
	root.add_child(world)
	Game.world = world
	player = FakePlayer.new()
	root.add_child(player)
	Game.player = player
	Game.state = &"play"
	Game.message.connect(func(t: String, _s: float) -> void: messages.append(t))
	Game.sector_cleared.connect(func() -> void: wins += 1)
	m = (load("res://scenes/missions.tscn") as PackedScene).instantiate() as Missions
	root.add_child(m)
	await TestLib.frames(host, 2)

	_registry()
	_placement()
	await _collect(host)
	await _win(host)
	_round_growth()
	await _pickups(host)
	await _vehicle(host)
	await _guards(host)
	_resets()
	await _pools(host)

	root.queue_free()
	await TestLib.frames(host, 2)
	TestLib.check(Game.missions == null, "Game.missions is cleared when the module leaves the tree")
	Game.world = null
	Game.player = null
	Sfx.muted = was_muted


func _registry() -> void:
	TestLib.check(Game.missions == m, "Game.missions is the module")
	TestLib.check(m.is_in_group(&"missions"), "module is in group 'missions'")
	TestLib.check(m.rounds == 1 and m.total == 6 and m.cores.size() == 6 and m.got == 0, "the first round (6 cores) is built at start without a new_game signal")
	TestLib.check(m.pickups.is_empty(), "no pickups at start")


func _valid_layout(spots: Array[Vector3]) -> String:
	for i in spots.size():
		var p := spots[i]
		if not world.intersections.has(p):
			return "core %d is not on an inner junction" % i
		if Vector2(p.x - Game.SPAWN.x, p.z - Game.SPAWN.z).length() < 140.0:
			return "core %d is %.0f m from the spawn" % [i, Vector2(p.x - Game.SPAWN.x, p.z - Game.SPAWN.z).length()]
		for j in range(i):
			if Vector2(p.x - spots[j].x, p.z - spots[j].z).length() < 110.0:
				return "cores %d and %d are %.0f m apart" % [i, j, Vector2(p.x - spots[j].x, p.z - spots[j].z).length()]
	return ""


func _spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for c: Dictionary in m.cores:
		out.append(c.pos)
	return out


func _placement() -> void:
	var bad := ""
	var short := 0
	for seed_i in 150:
		m.rng.seed = seed_i * 7919 + 11
		var n := 6 + (seed_i % 4)
		var placed := m.new_round(n)
		if placed != n:
			short += 1
		var why := _valid_layout(_spots())
		if why != "" and bad == "":
			bad = "seed %d: %s" % [seed_i, why]
	TestLib.check(bad == "", "placement rules (junction, >= 140 m from spawn, >= 110 m apart, distinct) hold for 150 seeds %s" % bad)
	TestLib.check(short == 0, "6..9 cores are always placed (%d short rounds in 150 seeds)" % short)
	m.rng.seed = 5
	var a := m.new_round(6)
	var first := _spots()
	m.rng.seed = 5
	m.new_round(6)
	TestLib.check(a == 6 and first == _spots(), "the same seed gives the same layout")
	TestLib.check(m.new_round(30) <= 9 and m.cores.size() <= 9, "a round never has more than 9 cores")
	var all_beams := true
	for c: Dictionary in m.cores:
		var node := c.node as Node3D
		all_beams = all_beams and node.visible and node.get_node_or_null("Beam") != null and node.position.is_equal_approx(c.pos)
	TestLib.check(all_beams, "every core has a visible node at its junction with a beam")
	var beam := (m.cores[0].node as Node3D).get_node("Beam") as MeshInstance3D
	TestLib.check((beam.mesh as CylinderMesh).height >= 300.0 and beam.position.y > 150.0, "the beam is a tall column that rises from the ground (visible above the skyline)")
	var gem := (m.cores[0].node as Node3D).get_node("Gem") as Node3D
	TestLib.check(gem.get_child_count() == 1 and gem.get_child(0).scale.is_equal_approx(Vector3.ONE), "the gem model is never scaled")
	m.new_round(6)
	TestLib.check(m.total == 6 and m.got == 0, "back to 6 cores")


func _stand_at(p: Vector3) -> void:
	player.global_position = p


func _collect(host: Node) -> void:
	Game.score = 0
	messages.clear()
	player.energy = 10.0
	_stand_at(Vector3(0.0, 0.0, 0.0))
	await TestLib.frames(host, 3)
	TestLib.check(m.got == 0 and m.cores.size() == 6, "nothing is collected away from a core")
	var c: Dictionary = m.cores[0]
	var p: Vector3 = c.pos
	_stand_at(p + Vector3(4.5, 0.0, 0.0))
	await TestLib.frames(host, 3)
	TestLib.check(m.got == 0, "4.5 m from a core is outside the trigger")
	var near := m.nearest_core(player.global_position)
	TestLib.check(near.has("pos") and near.has("dist") and absf(float(near.dist) - 4.5) < 0.01 and near.pos == p, "nearest_core returns the {pos, dist} of the closest core")
	_stand_at(p + Vector3(3.5, 0.0, 0.0))
	await TestLib.frames(host, 3)
	TestLib.check(m.got == 1 and m.cores.size() == 5, "a core is collected within 4 m")
	TestLib.check(Game.score == 250, "+250 score per core (got %d)" % Game.score)
	TestLib.check(player.energy == player.max_energy, "a core refunds full energy")
	TestLib.check(messages.size() > 0 and messages[messages.size() - 1].contains("1/6"), "a message announces the core: %s" % (messages[-1] if messages.size() > 0 else ""))
	TestLib.check(not (c.node as Node3D).visible, "the collected core's node is hidden (pooled)")
	TestLib.check(Game.state == &"play" and wins == 0, "the game continues after the first core")
	await TestLib.frames(host, 3)
	TestLib.check(m.got == 1 and Game.score == 250, "a collected core is not collected twice")
	var far := m.nearest_core(Vector3(-2000.0, 500.0, 0.0))
	TestLib.check(far.dist > 1700.0 and far.dist < 2300.0, "nearest_core measures the horizontal distance")


func _win(host: Node) -> void:
	for i in 10:
		if m.cores.is_empty():
			break
		_stand_at(m.cores[0].pos)
		await TestLib.frames(host, 2)
	TestLib.check(m.got == 6 and m.cores.is_empty(), "all 6 cores collected")
	TestLib.check(Game.state == &"win" and wins == 1, "the last core calls Game.win() once")
	TestLib.check(Game.score == 6 * 250, "score is 250 per core")
	TestLib.check(m.nearest_core(Vector3.ZERO).is_empty(), "nearest_core is empty without cores")
	await TestLib.frames(host, 5)
	TestLib.check(wins == 1, "winning is reported once, not every frame")


func _round_growth() -> void:
	Game.new_game.emit()
	TestLib.check(m.rounds == 1 and m.total == 6 and m.cores.size() == 6 and m.got == 0, "new_game: round 1 with 6 cores")
	var expect := [7, 8, 9, 9, 9]
	var ok := true
	var seen: Array[int] = []
	for e: int in expect:
		Game.next_sector.emit()
		seen.append(m.cores.size())
		ok = ok and m.cores.size() == e and m.total == e and _valid_layout(_spots()) == ""
	TestLib.check(ok, "next_sector builds min(9, 6 + rounds) valid cores: %s" % str(seen))
	TestLib.check(m.rounds == 6, "rounds counts the rounds (%d)" % m.rounds)
	Game.new_game.emit()
	TestLib.check(m.rounds == 1 and m.total == 6, "new_game resets the round counter")
	Game.state = &"play"


func _pickups(host: Node) -> void:
	_stand_at(Vector3(Game.SPAWN))
	player.hp = 40.0
	player.energy = 20.0
	messages.clear()
	m.drop(&"health", Vector3(-20.0, 2.5, 4.0))
	m.drop(&"bogus", Vector3(0.0, 0.0, 0.0))
	TestLib.check(m.pickups.size() == 1, "drop adds one pickup and ignores unknown kinds")
	var pk: Dictionary = m.pickups[0]
	TestLib.check(pk.kind == &"health" and absf((pk.pos as Vector3).y) < 0.01 and absf((pk.pos as Vector3).x + 20.0) < 0.01, "a pickup settles on the floor below its drop point")
	TestLib.check((pk.node as Node3D).visible and absf(pk.t - 40.0) < 0.1, "pickups live 40 s")
	await TestLib.frames(host, 3)
	TestLib.check(m.pickups.size() == 1 and player.hp == 40.0, "a pickup 10 m away is left alone")
	var lo := 1000.0
	var hi := -1000.0
	for i in 40:
		await TestLib.frames(host, 1)
		var y := (pk.node as Node3D).position.y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	TestLib.check(hi - lo > 0.05 and lo > 0.3 and hi < 0.8, "pickups bob around their hover height (%.2f..%.2f)" % [lo, hi])
	_stand_at(Vector3(-20.0, 0.0, 4.0) + Vector3(1.5, 0.0, 0.0))
	await TestLib.frames(host, 3)
	TestLib.check(m.pickups.is_empty() and absf(player.hp - 70.0) < 0.01, "a health pickup heals 30 (hp %.0f)" % player.hp)
	TestLib.check(messages.any(func(t: String) -> bool: return t.contains("INTEGRITY")), "a health pickup says so (a loot part message may follow it)")
	m.drop(&"energy", Vector3(-20.0, 0.0, 4.0))
	await TestLib.frames(host, 3)
	TestLib.check(m.pickups.is_empty() and absf(player.energy - 55.0) < 0.01, "an energy pickup refunds 35 (energy %.0f)" % player.energy)
	player.hp = 100.0
	m.drop(&"health", Vector3(-20.0, 0.0, 4.0))
	await TestLib.frames(host, 3)
	TestLib.check(player.hp == 100.0 and m.pickups.is_empty(), "health is clamped at the maximum")
	# despawn timer
	_stand_at(Vector3(300.0, 0.0, 300.0))
	m.drop(&"energy", Vector3(0.0, 0.0, 0.0))
	m.pickups[0].t = 0.05
	await TestLib.frames(host, 8)
	TestLib.check(m.pickups.is_empty(), "an uncollected pickup despawns when its timer runs out")
	# cap: more drops than the pool recycle the oldest
	for i in 20:
		m.drop(&"health" if i % 2 == 0 else &"energy", Vector3(float(i) * 3.0, 0.0, 100.0))
	TestLib.check(m.pickups.size() == Missions.PICKUP_POOL, "at most %d pickups exist at once (%d)" % [Missions.PICKUP_POOL, m.pickups.size()])
	var newest: Vector3 = m.pickups[m.pickups.size() - 1].pos
	TestLib.check(newest.x == 57.0, "the newest drop is kept when the pool recycles")
	m.clear_pickups()
	TestLib.check(m.pickups.is_empty(), "clear_pickups empties the list")


func _vehicle(host: Node) -> void:
	Game.state = &"play"
	m.new_round(6)
	var car := Node3D.new()
	root.add_child(car)
	var p: Vector3 = m.cores[0].pos
	player.global_position = Vector3(290.0, 0.0, 290.0)      # the player node is far away: only the vehicle reaches the core
	player.vehicle = car
	car.global_position = p + Vector3(0.0, 0.0, 3.0)
	await TestLib.frames(host, 3)
	TestLib.check(m.got == 1, "a driven vehicle within 4 m collects a core")
	m.drop(&"health", car.global_position + Vector3(1.0, 0.0, 0.0))
	player.hp = 50.0
	await TestLib.frames(host, 3)
	TestLib.check(player.hp > 79.0, "a driven vehicle also collects pickups")
	player.vehicle = null
	car.queue_free()


func _guards(host: Node) -> void:
	Game.state = &"play"
	m.new_round(6)
	var p: Vector3 = m.cores[0].pos
	Game.state = &"paused"
	_stand_at(p)
	await TestLib.frames(host, 4)
	TestLib.check(m.got == 0, "nothing is collected while paused")
	Game.state = &"play"
	_stand_at(p + Vector3(0.0, 30.0, 0.0))
	await TestLib.frames(host, 4)
	TestLib.check(m.got == 0, "a player on a roof 30 m above a junction does not collect it")
	_stand_at(Vector3(300.0, 0.0, 300.0))
	Game.state = &"dead"
	Game.state = &"play"


func _resets() -> void:
	m.new_round(6)
	m.drop(&"health", Vector3(1.0, 0.0, 1.0))
	var before := _spots()
	Game.respawn.emit()
	TestLib.check(m.pickups.is_empty() and _spots() == before and m.cores.size() == 6, "respawn clears pickups and keeps the cores")
	var r := m.rounds
	Game.next_sector.emit()
	TestLib.check(m.cores.size() == mini(9, 6 + r), "next_sector after round %d builds %d cores (got %d)" % [r, mini(9, 6 + r), m.cores.size()])
	m.drop(&"energy", Vector3(1.0, 0.0, 1.0))
	Game.new_game.emit()
	TestLib.check(m.pickups.is_empty() and m.total == 6 and m.rounds == 1 and m.got == 0, "new_game rebuilds everything")


func _pools(host: Node) -> void:
	var nodes := m.get_child(0).get_child_count()
	for i in 40:
		m.drop(&"health", Vector3(float(i), 0.0, 50.0))
		Game.next_sector.emit()
	await TestLib.frames(host, 2)
	TestLib.check(m.get_child(0).get_child_count() >= nodes, "pooled nodes are kept, not freed (%d -> %d)" % [nodes, m.get_child(0).get_child_count()])
	TestLib.check(m.get_child(0).get_child_count() <= Missions.PICKUP_POOL + Missions.CORE_MAX, "never more than %d pooled nodes" % (Missions.PICKUP_POOL + Missions.CORE_MAX))
