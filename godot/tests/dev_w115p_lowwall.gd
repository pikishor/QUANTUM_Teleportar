extends RefCounted
## Dev probe (wave 115 PLAY critic): the CLIMB trigger takes any static collider within 1.15 m in front of a hero on foot. How tall are the things it finds? 400 random street spots x 8 headings.
const TIMEOUT_SECONDS := 120.0
var host: Node

func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 40)
	var p := Game.player as Player
	var sn := p.snake
	var city := Game.world as City
	city.collision_chunks().activate_all()
	TrafficField.bare_street()
	await TestLib.frames(host, 6)
	var space := p.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var heights: Array[float] = []
	var spots := 0
	var near_hits := 0
	for i in 400:
		var rp := city.random_core_road_point()
		# step toward the nearest wall like a player who walks up to a shop front: try 8 headings and 6 distances
		for k in 8:
			var yaw := TAU * float(k) / 8.0
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			p.global_position = rp
			var w := sn.anchors.find_wall(p, dir, 1.15)
			if w.is_empty():
				continue
			near_hits += 1
			var hp: Vector3 = w["pos"]
			var n: Vector3 = w["normal"]
			var inside := hp - Vector3(n.x, 0.0, n.z).normalized() * 0.3
			var q := PhysicsRayQueryParameters3D.create(inside + Vector3(0, 120.0, 0), inside + Vector3(0, -2.0, 0), Game.L_WORLD)
			var top := space.intersect_ray(q)
			if not top.is_empty():
				heights.append((top["position"] as Vector3).y - rp.y)
		spots += 1
	heights.sort()
	var low := 0
	for hh in heights:
		if hh < 4.0:
			low += 1
	if heights.is_empty():
		print("LW no wall in reach at any of %d spots" % spots)
	else:
		print("LW %d wall hits in reach at %d spots: height median %.1f m, p10 %.1f, p90 %.1f; %d of %d under 4 m (a climb on a prop)" % [heights.size(), spots, heights[heights.size() / 2], heights[heights.size() / 10], heights[heights.size() * 9 / 10], low, heights.size()])
	main.queue_free()
	await TestLib.frames(host, 3)
