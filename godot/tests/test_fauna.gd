extends RefCounted
## Alien fauna (scripts/ambient/ambient_fauna.gd) in the real city: one MultiMesh, tier counts, day / night, scatter on gunfire, reset, no growth.
## Run: tools/test.sh tests/test_fauna.gd

const Fixture := preload("res://tests/ambient_fixture.gd")


func run(host: Node) -> void:
	var city := (load("res://scenes/world.tscn") as PackedScene).instantiate() as City
	host.add_child(city)
	await TestLib.frames(host, 3)
	var amb: Node3D = city.ambient
	var f: RefCounted = amb.fauna
	var player := Fixture.new()
	host.add_child(player)
	player.global_position = Vector3(-30.0, 0.0, 4.0)
	Game.player = player
	var prev := Game.state
	Game.state = &"play"
	amb.simulate = false

	var mi := city.find_child("AmbientFauna", true, false)
	TestLib.check(mi is MultiMeshInstance3D and (mi as MultiMeshInstance3D).multimesh == f.mm, "fauna is one MultiMesh in the city")
	TestLib.check(city.find_child("AmbientFauna_mirror", true, false) == null, "no mirror copy (one draw)")
	for lv in 3:
		amb.set_quality(lv)
		TestLib.check(f.count == f.COUNTS[lv] and f.mm.visible_instance_count == f.count, "tier %d shows %d" % [lv, f.count])
	amb.set_quality(2)

	var at := player.global_position
	f.step(0.1, at, 1.0)
	var night_n: int = f.alive_count()
	f.step(0.1, at, 0.0)
	var day_n: int = f.alive_count()
	TestLib.check(night_n < day_n and night_n > 0, "night has fewer flyers out than day (%d vs %d)" % [night_n, day_n])
	f.step(0.1, at, 0.0)
	var kinds := [0, 0]
	for i in f.count:
		kinds[f.kind[i]] += 1
	TestLib.check(kinds[0] > 0 and kinds[1] > 0, "flyers and crawlers both exist")

	# gunfire scatters: shoot at the centre of a group
	var near := -1
	for i in f.count:
		if f.kind[i] == 0 and f.active[i] == 1:
			near = i
			break
	var shot_at: Vector3 = f.pos[near]
	var before: Vector3 = f.pos[near]
	var scared: int = f.on_shot(shot_at + Vector3(2.0, 0.0, 0.0))
	TestLib.check(scared >= 1 and f.alarm[near] > 0.0, "a shot scares the creatures near it (%d)" % scared)
	for k in 20:
		f.step(0.1, at, 0.0)
	var moved: float = f.pos[near].distance_to(before)
	TestLib.check(moved > 3.0, "a scared flyer leaves the spot (%.1f m)" % moved)
	TestLib.check(f.alarm[near] < 5.0, "fright fades")

	# nobody drifts out of range of the player
	f.step(0.1, Vector3(150.0, 0.0, 150.0), 0.0)
	var worst := 0.0
	for i in f.count:
		if f.active[i] == 1:
			worst = maxf(worst, Vector2(f.pos[i].x - 150.0, f.pos[i].z - 150.0).length())
	TestLib.check(worst < 200.0, "creatures re-seed around a moved player (%.0f m)" % worst)

	# the live scene steps it only while playing
	amb.simulate = true
	Game.state = &"paused"
	var t0: float = f._time
	await TestLib.frames(host, 5)
	TestLib.check(is_equal_approx(f._time, t0), "frozen while paused")
	Game.state = &"play"
	var guard := 0
	while f._time <= t0 and guard < 600:
		await TestLib.frames(host, 2)
		guard += 1
	TestLib.check(f._time > t0, "runs while playing")
	f.reset()
	TestLib.check(f.alarm[near] == 0.0, "reset calms everyone")
	TestLib.check(f.mm.instance_count == f.BUILT, "no growth")

	Game.state = prev
	Game.player = null
	player.queue_free()
	city.queue_free()
	await TestLib.frames(host, 2)
