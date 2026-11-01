extends RefCounted
## Fixes found on the owner's phone (headless, the composed game): teleports and blinks are clamped to valid city ground and a lost hero is rescued, the camera arm
## ignores cars and fades the hero when the lens is close, pedestrians spread over the sidewalk with idle groups, the LOW tier draws no post pass and caps the bloom.
## Run: tools/test.sh tests/test_device_fixes.gd

const Fixture := preload("res://tests/player_fixture.gd")
const Crowd := preload("res://scripts/ambient/ambient_crowd.gd")

var host: Node
var main: Node
var p: Player
var city: City


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	city = Game.world as City
	Game.state = &"play"
	p.max_hp = 1.0e6
	await _teleport_clamp()
	await _blink_aimed_off_map()
	await _rescue()
	await _camera_ignores_cars()
	_hero_fade()
	_crowd_spread()
	_low_tier()
	main.queue_free()
	await frames(5)
	Game.state = &"menu"
	Sfx.muted = false


func _in_bounds(q: Vector3) -> bool:
	return absf(q.x) <= CityLayout.WALK and absf(q.z) <= CityLayout.WALK and q.y > -1.0 and q.y < 400.0


func _teleport_clamp() -> void:
	for target: Vector3 in [Vector3(900, 5, 900), Vector3(-500, 0, 40), Vector3(10, -500, 10), Vector3(0, 900, 0), Vector3(1.0e6, 0, -1.0e6)]:
		p.teleport_to(target)
		await frames(4)
		TestLib.check(_in_bounds(p.global_position) and p.global_position.y < 100.0, "teleport to %s lands inside the city walls (%s)" % [str(target), str(p.global_position)])
	p.teleport_to(Vector3(NAN, 0, 0))
	TestLib.check(_in_bounds(p.global_position), "a NaN teleport target falls back to a valid point")
	# a point inside a building volume moves out to a street
	var lot: CityLayout.Lot = city.layout.lots[40]
	p.teleport_to(Vector3(lot.cx, 3.0, lot.cz))
	await frames(4)
	TestLib.check(not city.is_inside_building(p.global_position + Vector3(0, 0.4, 0)), "a teleport into a building volume ends on the street")
	# the street / roof helpers
	var st := PlayerUtil.nearest_street(Vector3(35.0, 0.0, 35.0))
	TestLib.check(CityLayout.on_road(st.x, st.z), "nearest_street returns a road point")
	TestLib.check(PlayerUtil.outside_city(Vector3(CityLayout.WALK + 5.0, 0, 0)) and PlayerUtil.outside_city(Vector3(0, -20, 0)) and not PlayerUtil.outside_city(Game.SPAWN), "outside_city tests the walls and the floor")
	# the windowed city follows the jump at once
	p.teleport_to(Vector3(250.0, 0.0, -250.0))
	var near := false
	for f in city.stream_families():
		near = near or (f.built_at as Vector2).distance_to(Vector2(p.global_position.x, p.global_position.z)) < 30.0
	TestLib.check(near, "city_stream windows are rebuilt around the teleport target immediately")
	p.teleport_to(Game.SPAWN)
	await frames(3)


func _blink_aimed_off_map() -> void:
	var q := p.quantum
	for pitch: float in [0.6, -0.05, 1.2]:
		p.teleport_to(Vector3(CityLayout.WALK - 6.0, 0.0, 0.0))
		await frames(5)
		p.energy = p.max_energy
		var yaw := -PI * 0.5
		p.camera_rig.reset_view(yaw, pitch)
		p.camera_rig.aim_at(p.global_position + Vector3(60.0, 5.0 + pitch * 40.0, 0.0))
		await frames(3)
		q.cd_blink = 0.0
		q.blink()
		await frames(2)
		TestLib.check(not q.has_beacon or _in_bounds(q.beacon_pos), "a long blink aimed past the border (pitch %.2f) places the beacon inside the walls (%s)" % [pitch, str(q.beacon_pos)])
		q.cd_blink = 0.0
		q.blink()
		await frames(3)
		TestLib.check(_in_bounds(p.global_position), "the blink lands inside the walls (%s)" % str(p.global_position))
	p.teleport_to(Game.SPAWN)
	await frames(3)


func _rescue() -> void:
	p.global_position = Vector3(CityLayout.WALK + 80.0, 0.0, 10.0)
	await frames(4)
	TestLib.check(_in_bounds(p.global_position) and absf(p.global_position.x) <= CityLayout.WALK, "a hero outside the walls is rescued to the street")
	p.global_position = Vector3(20.0, -30.0, 20.0)
	await frames(4)
	TestLib.check(p.global_position.y > -1.0, "a hero below the floor is rescued")
	p.global_position = Vector3(0.0, -3000.0, 0.0)
	await frames(4)
	TestLib.check(_in_bounds(p.global_position), "a hero far below the world is brought back")
	TestLib.check(not p.is_dead() and Game.state == &"play", "a rescue does not kill the hero")
	p.teleport_to(Game.SPAWN)
	await frames(3)


func _cam_dist() -> float:
	return p.camera_rig.get_pivot_position().distance_to(p.camera_rig.camera.global_position)


func _camera_ignores_cars() -> void:
	p.teleport_to(Game.SPAWN)
	p.camera_rig.reset_view(-PI * 0.5, -0.1)
	p.yaw = -PI * 0.5
	await frames(30)
	var open_d := _cam_dist()
	var back := -p.camera_rig.get_aim_forward()
	back.y = 0.0
	back = back.normalized()
	var vm := Game.vehicles as VehicleManager
	var car := vm.spawn_parked(&"suv", Game.SPAWN + back * 2.2, p.yaw)
	var wall := Fixture.add_box(host, Game.SPAWN + back * 2.0 + Vector3(0, 1.5, 0), Vector3(3.0, 3.0, 0.6))      # a solid wall at the same place, for contrast
	wall.collision_layer = 0
	await frames(30)
	TestLib.check(car != null, "a parked car stands right behind the hero")
	TestLib.check(_cam_dist() > open_d - 0.3, "the camera arm ignores the car behind the hero (%.2f m, open street %.2f m)" % [_cam_dist(), open_d])
	TestLib.check(p.camera_rig.hero_fade < 0.01, "the hero stays solid with a car behind him")
	wall.collision_layer = Game.L_WORLD
	await frames(40)
	TestLib.check(_cam_dist() < open_d - 0.8, "a solid world wall still shortens the arm (%.2f m)" % _cam_dist())
	wall.queue_free()
	if is_instance_valid(car):
		vm._release(car)
	await frames(60)
	TestLib.check(_cam_dist() > open_d - 0.4, "the arm lets out again when the wall is gone")


func _hero_fade() -> void:
	var rig := p.camera_rig
	var body := p.body
	rig._update_fade(2.5, false)
	TestLib.check(rig.hero_fade == 0.0 and body.fade == 0.0, "no fade at normal camera distance")
	rig._update_fade(1.05, false)
	var mid := rig.hero_fade
	TestLib.check(mid > 0.05 and mid < 0.95, "the hero fades smoothly between 1.2 m and 0.9 m (%.2f at 1.05 m)" % mid)
	rig._update_fade(0.85, false)
	TestLib.check(rig.hero_fade == 1.0 and not body._parts[0].visible, "the hero is hidden when the camera is inside his head")
	rig._update_fade(2.5, false)
	TestLib.check(rig.hero_fade == 0.0 and body._parts[0].visible, "the hero comes back when the camera backs off")
	rig._update_fade(0.8, true)
	TestLib.check(rig.hero_fade == 0.0, "no fade while driving (the hero is hidden anyway)")


func _crowd_spread() -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var crowd = Crowd.new()
	crowd.build(ImageTexture.create_from_image(img))
	crowd.set_tier(2)
	for i in 80:
		crowd.step(0.1, Vector3(-30.0, 0.0, 4.0))
	var offs: Array[float] = []
	var speeds: Array[float] = []
	var idle := 0
	var pairs := 0
	var in_range := true
	var alive: Array[int] = []
	for i in crowd.count:
		if crowd.is_alive(i):
			alive.append(i)
			offs.append(crowd._off[i])
			speeds.append(crowd._spd[i])
			idle += 1 if crowd._idle[i] > 0.0 else 0
			in_range = in_range and crowd._off[i] >= Crowd.OFF_MIN - 0.001 and crowd._off[i] <= Crowd.OFF_MAX + 0.001
	for a in alive.size():
		for b in range(a + 1, alive.size()):
			var i: int = alive[a]
			var j: int = alive[b]
			if crowd._idle[i] > 0.0 and crowd._idle[j] > 0.0 and crowd.person_position(i).distance_to(crowd.person_position(j)) < 2.0:
				pairs += 1
	TestLib.check(alive.size() > 40, "the crowd fills the ring (%d people)" % alive.size())
	TestLib.check(_std(offs) > 0.25 and in_range, "pedestrians have their own sideways offsets (std %.2f m)" % _std(offs))
	TestLib.check(_std(speeds) > 0.15, "walking speeds vary (std %.2f m/s)" % _std(speeds))
	TestLib.check(idle >= 3 and pairs >= 1, "some people stand around in small groups (%d idle, %d close pairs)" % [idle, pairs])
	# no ruler-straight file: among the walkers of one sidewalk line the lateral coordinates are not all equal
	var lines := {}
	for i in alive:
		var key := "%d_%d" % [crowd._axis[i], int(round(crowd._lat[i]))]
		var l: Array = lines.get(key, [])
		l.append(crowd._off[i])
		lines[key] = l
	var spread := 0.0
	for k in lines:
		var l: Array = lines[k]
		if l.size() >= 3:
			var mn := 9.0
			var mx := -9.0
			for v: float in l:
				mn = minf(mn, v)
				mx = maxf(mx, v)
			spread = maxf(spread, mx - mn)
	TestLib.check(spread > 0.5, "people of one sidewalk line are spread across its width (%.2f m)" % spread)


func _std(a: Array[float]) -> float:
	if a.size() < 2:
		return 0.0
	var m := 0.0
	for v in a:
		m += v
	m /= a.size()
	var s := 0.0
	for v in a:
		s += (v - m) * (v - m)
	return sqrt(s / a.size())


func _low_tier() -> void:
	var atm: Node = Game.atmosphere
	var env := (city._env as Object).get(&"env") as Environment
	Game.set_quality(0)
	TestLib.check(not atm.post.visible, "LOW draws no full-screen post pass (no screen copy)")
	TestLib.check(env.glow_hdr_luminance_cap <= 4.0 and env.glow_hdr_threshold > 1.0, "LOW caps and delays the bloom so the hero cannot bloom to white")
	TestLib.check(get_viewport_msaa() == Viewport.MSAA_DISABLED, "LOW has no MSAA")
	Game.set_quality(1)
	TestLib.check(atm.post.visible and env.glow_hdr_luminance_cap > 8.0, "MED keeps the post pass and the full bloom")
	Game.set_quality(0)
	TestLib.check(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0) is int, "the msaa project setting exists (the tier overrides it per viewport)")
	TestLib.check(TextureBudget.MODELS.size() >= 9, "the texture budget lists the model atlases")
	Game.set_quality(1)


func get_viewport_msaa() -> int:
	return host.get_viewport().msaa_3d
