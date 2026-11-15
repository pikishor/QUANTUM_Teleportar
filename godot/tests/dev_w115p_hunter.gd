extends RefCounted
## Dev probe (wave 115 PLAY critic): where does SnakeReact._try_hunter put the snake hunter? The same ray as the game's (30 m from the hero at a random angle, a ray from 40 m above to 80 m below),
## 600 random street positions: how often is the spot inside a building, on a roof or in a place the hero cannot see?
const TIMEOUT_SECONDS := 120.0
var host: Node
func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 40)
	var p := Game.player as Player
	var city := Game.world as City
	city.collision_chunks().activate_all()
	TrafficField.bare_street()
	await TestLib.frames(host, 6)
	var space := p.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var inside := 0
	var roof := 0
	var street := 0
	var nohit := 0
	var blocked := 0
	var n := 600
	for i in n:
		var rp := city.random_core_road_point()
		var a := rng.randf() * TAU
		var at := rp + Vector3(cos(a), 0.0, sin(a)) * 30.0
		var g := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 40.0, at + Vector3.DOWN * 80.0, Game.L_WORLD))
		if g.is_empty():
			nohit += 1
			continue
		var pos: Vector3 = g["position"]
		var q := PhysicsPointQueryParameters3D.new()
		q.position = pos + Vector3(0, 1.0, 0)
		q.collision_mask = Game.L_WORLD
		var in_b := not space.intersect_point(q, 1).is_empty()
		if in_b:
			inside += 1
		elif pos.y > 4.0:
			roof += 1
		else:
			street += 1
			# a clear line from the hero's chest to the hunter's chest?
			var ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(rp + Vector3(0, 1.4, 0), pos + Vector3(0, 1.4, 0), Game.L_WORLD))
			if not ray.is_empty():
				blocked += 1
	print("HU %d hunter spots: inside a building %d (%.0f %%), on a roof %d (%.0f %%), no ground hit %d, on a street %d of which behind a wall from the hero %d" % [n, inside, 100.0 * inside / n, roof, 100.0 * roof / n, nohit, street, blocked])
	main.queue_free()
	await TestLib.frames(host, 3)
