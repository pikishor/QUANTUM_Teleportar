extends RefCounted
## Dev probe (wave 115 PLAY critic, not a test): does the RADIUS RING of each of the twelve snake bombs say what the bomb does? For each bomb: the hero arms it and aims at a spot 20 m down a street, the ring
## radius on screen is read (war.preview_radius), 16 dummy enemies stand on a spiral round the impact point (0.5 m to 1.7 x the table radius, physics off, a million hit points), the bomb is thrown with FIRE,
## 5 s later the damage of every dummy is read: the effective damage radius (the farthest dummy that lost health), the damage at the centre and at the rim, and what happened to the hero (he stands 4 m beyond
## the ring: he must not be hurt). env BM_IDS (default all twelve), BM_K
## Run: scratchpad/run_probe.sh tests/dev_w115p_bombs.gd 560 "^BM"

const TIMEOUT_SECONDS := 560.0

var host: Node
var p: Player
var war: SnakeWar
var _spot := Vector3.ZERO
var _yaw := 0.0


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _dir() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func _right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


func _lane() -> bool:
	var city := Game.world as City
	var space := p.get_world_3d().direct_space_state
	for tries in 800:
		var rp: Vector3 = city.random_core_road_point()
		if not rp.is_finite():
			continue
		for k in 8:
			var yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var a := rp + Vector3(0, 1.5, 0)
			var ok := true
			for off in [-14.0, -7.0, 0.0, 7.0, 14.0]:
				var side := dir.cross(Vector3.UP) * float(off)
				var q := PhysicsRayQueryParameters3D.create(a + side, a + side + dir * 52.0, Game.L_WORLD | Game.L_VEHICLE)
				if not space.intersect_ray(q).is_empty():
					ok = false
					break
			if ok:
				_spot = rp
				_yaw = yaw
				return true
	return false


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	SnakeWarMissions.reset_flags()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	war = SnakeWar.of(p)
	if Encounters.current != null:
		Encounters.current.enabled = false
	TrafficField.bare_street()
	Game.state = &"play"
	TestMode.god = false
	WeaponDefs.hero_mode = true
	Difficulty.set_mode(1)
	if not _lane():
		print("BM no wide open lane")
		return
	var k := float(int(OS.get_environment("BM_K")) if OS.get_environment("BM_K") != "" else 2)
	Engine.time_scale = k
	Engine.physics_ticks_per_second = int(60.0 * k)
	var ids_s := OS.get_environment("BM_IDS")
	var ids: Array[StringName] = []
	for v in (ids_s.split(",", false) if ids_s != "" else PackedStringArray(SnakeRows.BOMB_IDS)):
		ids.append(StringName(v))
	await frames(5)
	print("BM lane at %s yaw %.2f" % [str(_spot.snapped(Vector3(1, 1, 1))), _yaw])
	for id in ids:
		var line := await _trial(id)
		print("BM %-12s %s" % [str(id), line])
	WeaponDefs.hero_mode = false
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	main.queue_free()
	await frames(3)


func _trial(id: StringName) -> String:
	Input.action_release(&"fire")
	var sw := SnakeSwarm.current
	if sw != null:
		sw.clear()
	war.reset()
	war.disarm()
	var ops := BlastOps.shared(p.get_tree())
	ops.reset()
	(Game.enemies as EnemyManager).clear()
	var table_r := SnakeRows.radius_of(id)
	var impact := _spot + _dir() * 20.0
	# the hero stands 4 m beyond the ring from the impact point, back along the lane
	var hero_back := minf(20.0 + table_r + 4.0, 36.0) if table_r < 30.0 else 40.0
	p.invuln = 0.0
	p.max_hp = 1000.0
	p.hp = 1000.0
	p.teleport_to(impact - _dir() * (table_r + 4.0 if table_r + 4.0 < 30.0 else 30.0))
	p.camera_rig.reset_view(_yaw, -0.08)
	p.yaw = _yaw
	p.velocity = Vector3.ZERO
	p.snake.cancel()
	var hero_dist := p.global_position.distance_to(impact)
	var em := Game.enemies as EnemyManager
	var dummies: Array[Drone] = []
	var dists: Array[float] = []
	var n := 16
	for i in n:
		var r := 0.5 + (1.7 * table_r - 0.5) * float(i) / float(n - 1)
		var a := float(i) * 2.399963                                  # the golden angle: no two dummies in a line from the impact point
		var pos := impact + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var f := em.spawn(&"operative", pos, false)
		if f != null:
			f.set_physics_process(false)
			f.global_position = pos
			f.max_hp = 1.0e6
			f.hp = 1.0e6
			dummies.append(f)
			dists.append(r)
	await frames(6)
	var hp0 := p.hp
	war.arm(id)
	await frames(8)
	var ring := war.preview_radius
	# aim at the impact point on the ground
	p.camera_rig.aim_at(impact)
	await frames(2)
	var aim_pt := SnakeAim.point(p, float(SnakeRows.row(id).get("range", 40.0)))
	var hp_before: Array[float] = []
	for f in dummies:
		hp_before.append(f.hp)
	Input.action_press(&"fire")
	await frames(6)
	Input.action_release(&"fire")
	await frames(60 * 5)
	var eff := 0.0
	var centre_loss := 0.0
	var rim_loss := 0.0
	var hit := 0
	var worst_far := 0.0
	for i in dummies.size():
		var f := dummies[i]
		if not is_instance_valid(f):
			continue
		var loss := hp_before[i] - f.hp
		if loss > 1.0:
			hit += 1
			eff = maxf(eff, dists[i])
			if dists[i] > table_r * 1.05:
				worst_far = maxf(worst_far, dists[i])
		if dists[i] < 1.6:
			centre_loss = maxf(centre_loss, loss)
		if dists[i] > table_r * 0.8 and dists[i] <= table_r * 1.0:
			rim_loss = maxf(rim_loss, loss)
	var hero_loss := hp0 - p.hp
	var verdict: Array[String] = []
	if absf(ring - table_r) > 0.6 and ring > 0.0:
		verdict.append("RING %.1f differs from the table radius %.1f" % [ring, table_r])
	if ring <= 0.0:
		verdict.append("no ring shown")
	if eff > table_r * 1.12 + 0.6:
		verdict.append("damage reaches %.1f m, beyond the ring %.1f" % [eff, table_r])
	if eff < table_r * 0.6:
		verdict.append("damage stops at %.1f m, far inside the ring %.1f" % [eff, table_r])
	if hero_loss > 1.0:
		verdict.append("the hero (%.1f m from the impact, ring %.1f) lost %.0f" % [hero_dist, table_r, hero_loss])
	if aim_pt.distance_to(impact) > 4.0:
		verdict.append("the aim point is %.1f m from the target" % aim_pt.distance_to(impact))
	war.disarm()
	return "%s ring %.1f table %.1f | effective radius %.1f (%d of %d dummies hurt) centre -%.0f rim -%.0f | hero at %.1f m lost %.0f | %s" % ["OK " if verdict.is_empty() else "BAD", ring, table_r, eff, hit, dummies.size(), centre_loss, rim_loss, hero_dist, hero_loss, "; ".join(verdict)]
