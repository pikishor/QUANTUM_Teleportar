extends RefCounted
## Living-city tests (headless): far traffic, pedestrian crowd and overhead patrols (scripts/ambient/*). Counts per tier, caps, reset on the lifecycle signals,
## simulation only while playing, the crowd running from gunfire, nothing growing over time. Run: tools/test.sh tests/test_ambient.gd

const Traffic := preload("res://scripts/ambient/ambient_traffic.gd")
const Crowd := preload("res://scripts/ambient/ambient_crowd.gd")
const Patrol := preload("res://scripts/ambient/ambient_sky.gd")
const Fixture := preload("res://tests/ambient_fixture.gd")

const TIMEOUT_SECONDS := 120.0                   ## the terrain streams in for a while before the nodes are counted (see _settle_terrain); the runner's default limit is 60 s


func run(host: Node) -> void:
	var city := (load("res://scenes/world.tscn") as PackedScene).instantiate() as City
	host.add_child(city)
	await TestLib.frames(host, 3)
	var amb: Node3D = city.ambient
	TestLib.check(amb != null and amb.get_parent() == city, "the city owns an ambient child")
	var player := Fixture.new()
	player.name = "AmbientTestPlayer"
	host.add_child(player)
	player.global_position = Vector3(-30.0, 0.0, 4.0)
	Game.player = player
	var prev_state := Game.state
	Game.state = &"play"

	amb.citizens.enabled = false                         # the MultiMesh crowd is tested alone; the 3D actors have tests/test_humanoid_variants.gd
	_test_traffic(city, amb)
	await _test_tiers(host, city, amb)
	await _test_crowd(host, amb, player)
	await _test_gunfire(host, amb, player)
	await _test_playing_only(host, amb)
	await _test_reset(host, amb)
	await _test_patrol(host, amb)
	await _test_no_growth(host, city, amb)

	Game.state = prev_state
	Game.player = null
	player.queue_free()
	city.queue_free()
	await TestLib.frames(host, 2)


func _test_traffic(city: City, amb: Node3D) -> void:
	var t: RefCounted = amb.traffic
	TestLib.check(Traffic.CAP == 760 and Traffic.BUILT <= Traffic.CAP, "far traffic is capped at 760 instances (built %d)" % Traffic.BUILT)
	TestLib.check(t.mm.instance_count == Traffic.BUILT, "the traffic MultiMesh holds %d cars" % t.mm.instance_count)
	# every car sits on one of the 36 lane lines, on the road, driving right-hand
	var on_lane := true
	var lanes := {}
	for i in Traffic.BUILT:
		var key := "%d:%.1f" % [t.axis[i], t.lat[i]]
		lanes[key] = true
		var off := absf(fposmod(t.lat[i] + CityLayout.HALF + CityLayout.PITCH * 0.5, CityLayout.PITCH) - CityLayout.PITCH * 0.5)
		if absf(off - CityLayout.LANE) > 0.01:
			on_lane = false
	TestLib.check(on_lane, "every far car is 5 m off a road centre line (a lane)")
	TestLib.check(lanes.size() == Traffic.LANES, "the cars use all %d lanes" % Traffic.LANES + " (%d)" % lanes.size())
	# the shader formula in GDScript: a car moves speed * dt along its lane and wraps inside the lane range
	var p0: Vector3 = t.car_position(3, 0.0)
	var p1: Vector3 = t.car_position(3, 2.0)
	var moved := p0.distance_to(p1)
	TestLib.check(absf(moved - absf(t.speed[3]) * 2.0) < 0.01 or moved > 600.0, "a car moves speed x time along its lane (%.1f m in 2 s)" % moved)
	var inside := true
	for i in Traffic.BUILT:
		var p: Vector3 = t.car_position(i, 123.4)
		if absf(p.x) > CityLayout.HALF + 21.0 or absf(p.z) > CityLayout.HALF + 21.0:
			inside = false
	TestLib.check(inside, "cars stay inside the lane range at any time")
	var emerg := 0
	for i in Traffic.BUILT:
		if t.is_emergency(i):
			emerg += 1
	TestLib.check(emerg >= 4, "emergency vehicles are part of the traffic (%d)" % emerg)
	TestLib.check(t.material != null and t.mirror_material != null and t.mirror_material.render_priority < 0, "traffic has a real and a mirrored material")


func _test_tiers(host: Node, city: City, amb: Node3D) -> void:
	var seen := []
	for q in 3:
		Game.set_quality(q)
		await TestLib.frames(host, 2)
		var s: Dictionary = amb.stats()
		seen.append([s["traffic"], s["crowd"], s["crowd_radius"]])
		TestLib.check(s["traffic"] == Traffic.COUNTS[q] and s["traffic"] <= Traffic.CAP, "tier %d draws %d far cars (cap %d)" % [q, s["traffic"], Traffic.CAP])
		TestLib.check(s["crowd"] == Crowd.COUNTS[q], "tier %d lets %d pedestrians walk" % [q, s["crowd"]])
		TestLib.check((amb.traffic.mm as MultiMesh).visible_instance_count == Traffic.COUNTS[q], "tier %d: the traffic MultiMesh draws %d instances" % [q, Traffic.COUNTS[q]])
	TestLib.check(seen[0][0] < seen[1][0] and seen[1][0] < seen[2][0], "far traffic grows with the tier")
	TestLib.check(seen[0][1] < seen[1][1] and seen[1][1] < seen[2][1], "the crowd grows with the tier")
	TestLib.check(seen[0][2] <= 42.5, "LOW has no pedestrians beyond 42 m (ring %.0f m)" % seen[0][2])
	TestLib.check(Crowd.COUNTS[0] <= 48 and Crowd.COUNTS[2] <= Crowd.BUILT, "crowd caps hold (LOW %d, HIGH %d of %d)" % [Crowd.COUNTS[0], Crowd.COUNTS[2], Crowd.BUILT])
	# the mirrored copies: traffic from MED, crowd on HIGH only; LOW has none
	var mirror_vis := {}
	for m in city.mirror_nodes:
		if m.name == "AmbientTraffic_mirror" or m.name == "AmbientCrowd_mirror":
			mirror_vis[m.name] = m
	TestLib.check(mirror_vis.size() == 2, "both ambient families have a mirrored copy under the wet ground")
	Game.set_quality(0)
	await TestLib.frames(host, 2)
	TestLib.check(not (mirror_vis["AmbientTraffic_mirror"] as Node3D).is_visible_in_tree(), "LOW draws no mirrored traffic")
	Game.set_quality(1)
	await TestLib.frames(host, 2)
	TestLib.check((mirror_vis["AmbientTraffic_mirror"] as Node3D).is_visible_in_tree() and not (mirror_vis["AmbientCrowd_mirror"] as Node3D).is_visible_in_tree(), "MED mirrors the traffic, not the crowd")
	Game.set_quality(2)
	await TestLib.frames(host, 2)
	TestLib.check((mirror_vis["AmbientCrowd_mirror"] as Node3D).is_visible_in_tree(), "HIGH also mirrors the crowd")
	Game.set_quality(1)
	await TestLib.frames(host, 2)


func _test_crowd(host: Node, amb: Node3D, player: Node3D) -> void:
	amb.reset()
	await TestLib.frames(host, 25)
	var c: RefCounted = amb.crowd
	var alive: int = c.alive_count()
	TestLib.check(alive == c.count, "the whole MED crowd is on the street after a few frames (%d of %d)" % [alive, c.count])
	# near / far crowd: the nearest people use the full citizen mesh (capped), nobody is drawn twice, the far buffer hides whoever is near
	var near_expected := 0
	for i in c.count:
		var q: Vector3 = c.person_position(i)
		if Vector2(q.x - player.global_position.x, q.z - player.global_position.z).length() < Crowd.NEAR_RADIUS:
			near_expected += 1
	near_expected = mini(near_expected, Crowd.NEAR_CAP)
	var far_drawn := 0
	for i in c.count:
		far_drawn += 1 if c._buf[i * Crowd.STRIDE + 5] > 0.0 else 0
	TestLib.check(c.mm_near.visible_instance_count == c._nn and c._nn <= Crowd.NEAR_CAP and absi(c._nn - near_expected) <= 2,
			"the near crowd (%d people, %d expected within %.0f m, cap %d) uses the full mesh" % [c._nn, near_expected, Crowd.NEAR_RADIUS, Crowd.NEAR_CAP])
	TestLib.check(c._nn + far_drawn == alive, "every pedestrian is drawn exactly once (%d near + %d far of %d)" % [c._nn, far_drawn, alive])
	TestLib.check(c.mm_near.mesh != c.mm.mesh and c.mm.mesh.get_surface_count() == 1 and c.mm_near.mesh.get_surface_count() == 1, "near and far crowd are two one-surface meshes (2 draws)")
	var ok_pos := true
	var ok_walk := true
	var worst := 0.0
	for i in c.count:
		var p: Vector3 = c.person_position(i)
		var d := Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length()
		worst = maxf(worst, d)
		if d > c.radius * 1.1:
			ok_pos = false
		# on a sidewalk line: 11.3 m (+-0.25) from a road centre line, and not inside a road
		var lat := p.z if c._axis[i] == 0 else p.x
		var off := absf(fposmod(lat + CityLayout.HALF + CityLayout.PITCH * 0.5, CityLayout.PITCH) - CityLayout.PITCH * 0.5)
		if absf(off - Crowd.LINE_OFF) > 0.35 + maxf(-Crowd.OFF_MIN, Crowd.OFF_MAX):       # the line (+-0.2) plus the person's own lateral offset
			ok_walk = false
	TestLib.check(ok_pos, "everybody stays inside the ring (farthest %.0f m of %.0f m)" % [worst, c.radius])
	TestLib.check(ok_walk, "everybody walks a sidewalk line (11.3 m from a road centre)")
	# sample the first 16 people and wait on their movement (a state, not a frame count: which ones stand in a group is random and the frame time differs per machine)
	var n := mini(16, c.count)
	var before: Array[Vector3] = []
	for i in n:
		before.append(c.person_position(i))
	var moved := 0
	for step in 40:
		await TestLib.frames(host, 10)
		moved = 0
		for i in n:
			if c.person_position(i).distance_to(before[i]) > 0.3:
				moved += 1
		if moved >= n / 2:
			break
	TestLib.check(moved >= n / 4 and moved < n + 1, "pedestrians walk, a few stand in groups (%d of %d moved)" % [moved, n])
	# a long walk: people leave the ring and re-appear, the ring never empties
	player.global_position = Vector3(-30.0, 0.0, 4.0)
	for k in 6:
		player.global_position += Vector3(30.0, 0.0, 0.0)
		await TestLib.frames(host, 8)
	TestLib.check(c.alive_count() >= c.count - 2, "after a 180 m walk the street is populated again (%d of %d)" % [c.alive_count(), c.count])
	player.global_position = Vector3(-30.0, 0.0, 4.0)
	await TestLib.frames(host, 20)
	# corners: 300 s of walking in big steps; people turn onto the crossing line (axis flips) and always stay on a sidewalk line
	var flips := 0
	var off_line := 0
	var axes := PackedByteArray()
	var was := PackedByteArray()
	axes.resize(c.count)
	was.resize(c.count)
	for i in c.count:
		axes[i] = c._axis[i]
		was[i] = c._alive[i]
	for k in 1500:
		c.step(0.2, player.global_position)
		for i in c.count:
			if c._alive[i] == 1:
				if was[i] == 1 and c._axis[i] != axes[i]:
					flips += 1
				var lat: float = c._lat[i]
				var off := absf(fposmod(lat + CityLayout.HALF + CityLayout.PITCH * 0.5, CityLayout.PITCH) - CityLayout.PITCH * 0.5)
				if absf(off - Crowd.LINE_OFF) > 0.35:
					off_line += 1
			axes[i] = c._axis[i]
			was[i] = c._alive[i]
	TestLib.check(flips > 10, "pedestrians turn at corners (%d turns in 300 s)" % flips)
	TestLib.check(off_line == 0, "... and every turn lands on a sidewalk line (%d samples off a line)" % off_line)


func _test_gunfire(host: Node, amb: Node3D, player: Node3D) -> void:
	var c: RefCounted = amb.crowd
	# the signal path: the player stands 8 m from pedestrian 5 and fires; everybody in range runs, nobody beyond it
	var q: Vector3 = c.person_position(5)
	player.global_position = q + Vector3(0.0, 0.0, 8.0)
	await TestLib.frames(host, 2)
	for i in c.count:
		c._flee[i] = 0.0
	var fled_before: int = c.fled_total()
	player.fired.emit()
	var range_n := 0
	var wrong := 0
	var r: float = Crowd.SHOT_RADIUS[amb.quality]
	for i in c.count:
		if not c.is_alive(i):
			continue
		var d: float = c.person_position(i).distance_to(player.global_position)
		if d < r - 0.5:
			range_n += 1
			if not (c.is_fleeing(i) or c.is_cowering(i) or c.state_of(i) == &"linger"):      # NPC life: a close person may cower or point instead of running
				wrong += 1
		elif d > r + 0.5 and (c.is_fleeing(i) or c.is_cowering(i)):
			wrong += 1
	TestLib.check((c.is_fleeing(5) or c.is_cowering(5) or c.state_of(5) == &"linger") and c.fled_total() - fled_before >= range_n and wrong == 0, "player.fired sends the %d pedestrians within %.0f m running, nobody beyond" % [range_n, r])
	# put a pedestrian right next to the muzzle and fire: he runs away along his line
	var w := 0
	while w < c.count - 1 and not c.is_alive(w):
		w += 1
	var p: Vector3 = c.person_position(w)
	player.global_position = p + Vector3(0.0, 0.0, 6.0)
	c._flee[w] = 0.0
	var u_before: float = c._u[w]
	var along := player.global_position.x if c._axis[w] == 0 else player.global_position.z
	var away := signf(u_before - along)
	c.on_shot(player.global_position)
	TestLib.check(c.is_fleeing(w), "a pedestrian 6 m from the shot flees")
	TestLib.check(c._dir[w] == away or away == 0.0, "... away from the shooter")
	for k in 6:
		c.step(0.1, player.global_position)
	var gap := absf(c._u[w] - along)
	TestLib.check(gap > absf(u_before - along), "running increases the distance (%.1f -> %.1f m)" % [absf(u_before - along), gap])
	for k in 70:
		c.step(0.1, player.global_position)
	TestLib.check(not c.is_fleeing(w), "the panic wears off")
	player.global_position = Vector3(-30.0, 0.0, 4.0)


func _test_playing_only(host: Node, amb: Node3D) -> void:
	var clock: float = amb.clock
	var c: RefCounted = amb.crowd
	var p0: Vector3 = c.person_position(1)
	for st in [&"paused", &"dead", &"menu"]:
		Game.state = st
		await TestLib.frames(host, 15)
		TestLib.check(is_equal_approx(amb.clock, clock) and c.person_position(1).is_equal_approx(p0), "nothing simulates while the game is %s" % st)
	Game.state = &"play"
	await TestLib.frames(host, 15)
	TestLib.check(amb.clock > clock, "the ambient clock runs again when the game plays")


func _test_reset(host: Node, amb: Node3D) -> void:
	await TestLib.frames(host, 10)
	amb.sky.start_sweep()
	var c: RefCounted = amb.crowd
	for sig: Signal in [Game.new_game, Game.respawn, Game.next_sector]:
		await TestLib.frames(host, 6)
		TestLib.check(amb.clock > 0.0, "the clock runs before the reset")
		amb.sky.start_sweep()
		sig.emit()
		TestLib.check(amb.clock == 0.0 and c.alive_count() == 0 and not amb.sky.active, "%s resets the clock, the crowd and the patrol" % sig.get_name())
	await TestLib.frames(host, 25)
	TestLib.check(c.alive_count() == c.count, "the crowd is back on the street after a reset")


func _test_patrol(host: Node, amb: Node3D) -> void:
	var s: RefCounted = amb.sky
	s.reset()
	TestLib.check(not s.active and not s.node.visible, "no searchlight until a patrol starts")
	var before: int = s.sweeps
	s.start_sweep()
	await TestLib.frames(host, 3)
	TestLib.check(s.active and s.node.visible and s.sweeps == before + 1, "a patrol starts the searchlight (one MeshInstance3D)")
	var t0: Transform3D = s.node.transform
	for k in 40:
		s.step(0.5, Vector3.ZERO, amb.traffic, amb.clock, 1)
	TestLib.check(not s.node.transform.is_equal_approx(t0) or not s.active, "the airship moves")
	for k in 80:
		s.step(0.5, Vector3.ZERO, amb.traffic, amb.clock, 1)
	TestLib.check(not s.active and not s.node.visible, "the patrol ends and the light goes out (no draw call between sweeps)")
	amb.set_quality(0)
	s.reset()
	for k in 400:
		s.step(0.5, Vector3.ZERO, amb.traffic, amb.clock, 0)
	TestLib.check(not s.active and s.sweeps == before + 1, "LOW never starts a sweep")
	amb.set_quality(1)
	# sirens: asked for through Sfx (silent until assets/audio/siren.wav exists), only for emergency cars in range
	var asked: int = s.sirens
	s._siren_in = 0.0
	var centre := Vector3.ZERO
	for i in amb.traffic.count:
		if amb.traffic.is_emergency(i):
			centre = amb.traffic.car_position(i, amb.clock) + Vector3(120.0, 0.0, 0.0)
			break
	s.step(0.1, centre, amb.traffic, amb.clock, 1)
	TestLib.check(s.sirens == asked + 1, "a siren is requested for an emergency car 120 m away")
	TestLib.check(s.siren_player != null and s.siren_player.stream != null and s._siren_left > 0.0, "the siren is the seamless loop on ONE follow emitter (siren_loop.wav)")
	var car: int = s._siren_car
	s.step(0.5, centre, amb.traffic, amb.clock + 2.0, 1)
	var want: Vector3 = amb.traffic.car_position(car, amb.clock + 2.0) + Vector3(0, 1.0, 0)
	TestLib.check(s.siren_player.global_position.distance_to(want) < 0.01, "the emitter rides the emergency car")
	var emitters_before: int = s.siren_player.get_parent().get_child_count()
	s._siren_in = 0.0
	s.step(0.1, centre, amb.traffic, amb.clock, 1)
	TestLib.check(s.siren_player.get_parent().get_child_count() == emitters_before, "a second siren call re-uses the emitter (no new node)")
	s.reset()
	TestLib.check(not s.siren_player.playing and s._siren_left == 0.0, "reset stops the siren")


## The terrain is the one streamer that fills the tree late and all at once: it draws the world map picture on a worker thread first (about 10 s of one core for the 9 km world) and its far
## tiles and chunks queue behind that job in the pool; when the map is done the 96 far tiles arrive one a frame. A quiet stretch of 60 frames proves nothing while the map is still being
## drawn: on the CI runner the burst fell inside the counting window below ("2105 -> 2152", on both attempts), in the sandbox just after it (a 200 frame pause before the count reproduces
## the failure here). So the test waits on the terrain's own counters (the map is installed, every far tile stands, no job is in flight; progress based and in real time, like
## test_terrain_world) and only then lets the node count hold still and counts. The check itself is unchanged: once the world has settled, the living city creates no node.
func _settle_terrain(host: Node, city: City) -> void:
	var terrain := city.terrain
	if terrain == null:
		return
	terrain.far_jobs_max = 4                         # a phone builds two far tiles at a time; four finish the 9 km world sooner (test_terrain_world does the same)
	var total: int = terrain._far_total()
	var t0 := Time.get_ticks_msec()
	var t_last := t0
	var last := -1
	var done := false
	var st: Dictionary = {}
	while true:
		st = terrain.stats()
		if TerrainMap.ready and int(st["far_tiles"]) >= total and int(st["jobs"]) == 0:
			done = true
			break
		var progress := int(st["far_tiles"]) + int(st["chunks"]) + (1000 if TerrainMap.ready else 0)
		var now := Time.get_ticks_msec()
		if progress != last:
			last = progress
			t_last = now
		if float(now - t_last) / 1000.0 > 45.0 or float(now - t0) / 1000.0 > 100.0:   # (a stuck worker; the map alone takes about 10 s without any tile)
			break
		await TestLib.frames(host, 6)
	TestLib.check(done, "the terrain has streamed in before the nodes are counted (map %s, %d of %d far tiles, %d jobs, %.0f s)" % [str(TerrainMap.ready), int(st["far_tiles"]), total, int(st["jobs"]), float(Time.get_ticks_msec() - t0) / 1000.0])


func _test_no_growth(host: Node, city: City, amb: Node3D) -> void:
	await _settle_terrain(host, city)
	var calm := 0                                   # the rest of the streamed world (rail chunks, outskirts) may still be building around the spawn: wait until the node count holds still
	var last := host.get_tree().get_node_count()
	for k in 600:
		await TestLib.frames(host, 5)
		var now := host.get_tree().get_node_count()
		calm = calm + 1 if now == last else 0
		last = now
		if calm >= 12:
			break
	var nodes_before := host.get_tree().get_node_count()
	var mm_nodes := city.multimesh_nodes.size()
	var inst_t: int = amb.traffic.mm.instance_count
	var inst_c: int = amb.crowd.mm.instance_count
	var arrays_before: int = amb.crowd._u.size() + amb.crowd._buf.size()
	for k in 5:
		amb.crowd.on_shot(Vector3(-30.0, 0.0, 4.0))
		await TestLib.frames(host, 40)
	TestLib.check(host.get_tree().get_node_count() <= nodes_before, "no nodes are created while the city lives (%d -> %d)" % [nodes_before, host.get_tree().get_node_count()])
	TestLib.check(city.multimesh_nodes.size() == mm_nodes and amb.traffic.mm.instance_count == inst_t and amb.crowd.mm.instance_count == inst_c and amb.crowd.mm_near.instance_count == Crowd.NEAR_CAP, "MultiMesh nodes and instance counts stay constant")
	TestLib.check(amb.crowd._u.size() + amb.crowd._buf.size() == arrays_before, "the crowd's arrays never grow")
	TestLib.check(Crowd.BUILT * Crowd.STRIDE == amb.crowd._buf.size(), "the crowd writes one fixed buffer (%d floats)" % amb.crowd._buf.size())
