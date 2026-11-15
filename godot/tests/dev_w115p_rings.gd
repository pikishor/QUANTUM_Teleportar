extends RefCounted
## Dev probe (wave 115 PLAY critic, not a test): are the rings of SWING ACROSS THE CITY and ROOFTOP CHASE on real surfaces the hero can stand on or fly to?
## For many origins (the spawn, random core road points) the board builds both missions; every ring is checked:
##   roof rings (steps 1-4 of the tutorial, steps 1-3 of the chase): is there an upward surface within the ring's radius and 5 m of its height (the hero must stand on it within VERTICAL_REACH 6 m)?
##   the air ring (step 5): is the point free of colliders (a ring inside a tower can never be reached)?
##   the ground ring (step 6): is there ground within the radius (a ring inside a building footprint is reachable only from the street beside it)?
## env RP_N (origins, default 40), RP_SEED
## Run: tools/test.sh tests/dev_w115p_rings.gd

const TIMEOUT_SECONDS := 130.0

var host: Node
var p: Player


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _down(space: PhysicsDirectSpaceState3D, x: float, z: float, from_y: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -3.0, z), Game.L_WORLD)
	return space.intersect_ray(q)


func _inside(space: PhysicsDirectSpaceState3D, pos: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = pos
	q.collision_mask = Game.L_WORLD
	return not space.intersect_point(q, 1).is_empty()


## Best standable surface within `radius` of `c` and `dy_max` of c.y: the closest-height upward surface.
func _stand(space: PhysicsDirectSpaceState3D, c: Vector3, radius: float, dy_max: float) -> Dictionary:
	var best := {}
	var best_dy := INF
	for ring_r: float in [0.0, radius * 0.35, radius * 0.7, radius * 0.95]:
		var n := 1 if ring_r == 0.0 else 12
		for i in n:
			var a := TAU * float(i) / float(n)
			var x: float = c.x + cos(a) * ring_r
			var z: float = c.z + sin(a) * ring_r
			var h := _down(space, x, z, c.y + dy_max + 1.0)
			if h.is_empty():
				continue
			var hp: Vector3 = h["position"]
			if (h["normal"] as Vector3).y < 0.7:
				continue
			var dy := absf(hp.y - c.y)
			if dy < best_dy:
				best_dy = dy
				best = {"y": hp.y, "dy": dy, "at": hp}
	if best_dy <= dy_max:
		return best
	return {}


func _nearest_lot(city: City, pos: Vector3) -> CityLayout.Lot:
	var best: CityLayout.Lot = null
	var bd := INF
	for lot: CityLayout.Lot in city.layout.lots:
		var d := Vector2(lot.cx - pos.x, lot.cz - pos.z).length()
		if d < bd:
			bd = d
			best = lot
	return best


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	SnakeMissions.reset_flags()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(40)
	p = Game.player as Player
	(Game.enemies as EnemyManager).clear()
	Game.state = &"play"
	var board := (Game.missions as Missions).board
	var city := Game.world as City
	city.collision_chunks().activate_all()                          # the outer districts' colliders are streamed around the player: every block now
	await frames(4)                                                 # ... and the physics server needs a tick to see the new shapes
	var n := int(OS.get_environment("RP_N")) if OS.get_environment("RP_N") != "" else 40
	seed(int(OS.get_environment("RP_SEED")) if OS.get_environment("RP_SEED") != "" else 11)
	var space := p.get_world_3d().direct_space_state
	var origins: Array[Vector3] = [Game.SPAWN]
	for i in n:
		origins.append(city.random_core_road_point())
	var built := 0
	var bad_roof := 0
	var roof_total := 0
	var bad_air := 0
	var air_total := 0
	var bad_land := 0
	var land_total := 0
	var roof_dy_hist: Array[float] = []
	var oi := 0
	for o in origins:
		oi += 1
		for t: StringName in [&"swing_city", &"roof_chase"]:
			var rec := board.build(t, o)
			if rec.is_empty():
				print("RP origin %d %s: nothing built near (%.0f, %.0f)" % [oi, str(t), o.x, o.z])
				continue
			built += 1
			var steps: Array = rec["steps"]
			for i in steps.size():
				var st: Dictionary = steps[i]
				var pos: Vector3 = st["pos"]
				var rad := float(st.get("radius", 9.0))
				var kind := str(st["kind"])
				if kind != "reach":
					continue
				# make sure the streamed colliders around the ring exist (outer districts)
				if t == &"swing_city" and i == 4:
					air_total += 1
					var inside := _inside(space, pos)
					if inside:
						bad_air += 1
						print("RP BAD AIR ring %s step %d at %s is inside a collider" % [str(t), i, str(pos)])
				elif t == &"swing_city" and i == 5:
					land_total += 1
					# walkable share of the ring: ground samples (not inside a collider) within the radius
					var free_n := 0
					var all_n := 0
					for rr: float in [0.0, rad * 0.4, rad * 0.8]:
						var cnt := 1 if rr == 0.0 else 12
						for k in cnt:
							var aa := TAU * float(k) / float(cnt)
							var gx: float = pos.x + cos(aa) * rr
							var gz: float = pos.z + sin(aa) * rr
							all_n += 1
							var gh := _down(space, gx, gz, 8.0)
							if not gh.is_empty() and (gh["position"] as Vector3).y < 1.0 and not _inside(space, Vector3(gx, 1.0, gz)):
								free_n += 1
					var inside2 := _inside(space, Vector3(pos.x, 1.0, pos.z))
					if free_n == 0:
						bad_land += 1
						print("RP BAD LAND ring at %s: no walkable ground inside %.0f m" % [str(pos), rad])
					elif inside2 or free_n * 3 < all_n:
						print("RP NOTE LAND ring at %s: centre inside a collider %s, walkable share %d of %d samples" % [str(pos), str(inside2), free_n, all_n])
				else:
					roof_total += 1
					var st2 := _stand(space, pos, rad, 5.0)
					if st2.is_empty():
						bad_roof += 1
						var hh := _down(space, pos.x, pos.z, pos.y + 40.0)
						var lot := _nearest_lot(city, pos)
						var bd: Variant = city.building_data[lot.index] if lot != null else null
						var cls := str(bd.cls) if bd != null else "?"
						print("RP BAD ROOF ring %s step %d at %s radius %.0f: no standable surface within 5 m of its height (surface under centre: %s) lot cls %s w %.1f d %.1f h %.1f centre (%.1f, %.1f) ring offset (%.1f, %.1f) core %s" % [str(t), i, str(pos), rad, str((hh["position"] as Vector3).y) if not hh.is_empty() else "none", cls, lot.w, lot.d, lot.h, lot.cx, lot.cz, pos.x - lot.cx, pos.z - lot.cz, str(CityLayout.is_core_block(lot.block_i, lot.block_j))])
					else:
						roof_dy_hist.append(float(st2["dy"]))
	var avg_dy := 0.0
	for d in roof_dy_hist:
		avg_dy += d
	avg_dy /= maxf(float(roof_dy_hist.size()), 1.0)
	print("RP SUMMARY missions built %d: roof rings %d (bad %d, mean height error to the nearest standable roof %.2f m), air rings %d (bad %d), land rings %d (bad %d)" % [built, roof_total, bad_roof, avg_dy, air_total, bad_air, land_total, bad_land])
	main.queue_free()
	await frames(3)
