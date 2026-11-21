extends RefCounted
## OWNER ROUND 7, the snake zip ("zip line is not working properly", "behaves abnormally") and the frame rate in flight ("VEHICLES 4 to 6.5 ms far from any car", drops to 13 to 28 FPS).
## Real scene, REAL FINGERS (tests/w116_fingers.gd). Every check has an old-behaviour trial on the same places that must fail the same measure.
##   zip     a ZIP at a roof ends STANDING on that roof (the straight pull of wave 115 met the wall under the edge: a climb at the top of the facade, or back on the street);
##           a thumb that stays on ZIP after the pull does not take off in SNAKE FLIGHT from the roof
##   cost    flying outside the street grid the vehicle streamer runs no road search at all (it ran 204 passes over the road table every 0.4 s), the table of fixed spawn points
##           is not rebuilt every second, the road traffic tries one free slot per respawn pass (it tried all 64: 512 lane searches in one frame)
## Counters, not milliseconds: the numbers are in docs/sprint/progress/w116-flight-view.md (tests/dev_w116_vehicle_air.gd measures them). Run: tools/test.sh tests/test_flight_cost_w116.gd

const TIMEOUT_SECONDS := 140
const Fingers := preload("res://tests/w116_fingers.gd")
var host: Node
var fg: Fingers
var p: Player
var sn: SnakeTraversal
var spots: Array = []                    ## [position, yaw] of street spots whose SNAKE button reads ZIP at a roof


func _f(n: int) -> void:
	await TestLib.frames(host, n)


func _until(cond: Callable, seconds: float) -> bool:
	for i in int(seconds * 60.0):
		if cond.call():
			return true
		await _f(1)
	return cond.call()


func _tp(pos: Vector3, yaw: float, pitch: float, settle := 26) -> void:
	fg.up_all()
	await _f(2)
	sn.cancel()
	sn.reset()
	p.teleport_to(pos)
	p.camera_rig.reset_view(yaw, pitch)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await _f(settle)


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	var win_size := host.get_window().size
	host.get_window().size = Vector2i(1200, 540)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	sn = p.snake
	fg = Fingers.new(host)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	p.max_hp = 1.0e6
	p.hp = 1.0e6
	await _zip()
	await _cost()
	fg.up_all()
	SnakeZip.roof_arc = true
	SnakeZip.wall_end = true
	SnakeTraversal.zip_takes_press = true
	CityLayout.far_exit = true
	VehicleManager.cache_points = true
	CrateReveal._quiet = -1
	host.get_window().size = win_size
	Game.force_touch = false
	main.queue_free()
	await _f(2)


# --- ZIP ---------------------------------------------------------------------------------------------------------------------------------------

## A finger taps SNAKE at spot `i`. Returns 1 when the hero then stands on the roof he zipped to, 0 when he does not, -1 when the press was not a roof zip.
func _zip_once(i: int) -> int:
	var s: Array = spots[i]
	await _tp(s[0], s[1], 0.3)
	var from := p.global_position
	if sn.hint != &"zip" or not fg.press(1, &"snake_zip"):      # wave 118: ZIP is a button of its own (action snake_zip); the hint says a zip target is under the crosshair
		return -1
	await _f(4)
	fg.up(1)
	if sn.mode != SnakeTraversal.Mode.ZIP or sn.zip.kind != &"roof" or sn.zip.dest.y < from.y + 4.0:
		return -1
	var roof_y := sn.zip.dest.y
	await _until(func() -> bool: return sn.mode != SnakeTraversal.Mode.ZIP, 3.0)
	await _until(func() -> bool: return p.is_on_floor(), 0.6)
	return 1 if (sn.mode == SnakeTraversal.Mode.NONE and p.is_on_floor() and absf(p.global_position.y - roof_y) < 1.2) else 0


## A thumb holds SNAKE for 1.7 s at roof spot `i`. True when the hero ends up in SNAKE FLIGHT.
func _zip_hold(i: int, action: StringName = &"snake_zip") -> bool:
	var s: Array = spots[i]
	await _tp(s[0], s[1], 0.3)
	if not fg.press(1, action):
		return false
	await _f(102)
	var flew := sn.mode == SnakeTraversal.Mode.FLY
	fg.up(1)
	return flew


func _zip() -> void:
	var city := Game.world as City
	seed(1160)
	var cand: Array = []
	for k in 40:
		var rp: Vector3 = city.random_core_road_point()
		if rp.is_finite():
			cand.append([rp, randf_range(-PI, PI)])
	# the roof zips among them (the button reads ZIP, the anchor table says roof, the roof is at least 4 m up)
	for c: Array in cand:
		if spots.size() >= 7:
			break
		await _tp(c[0], c[1], 0.3, 14)
		if sn.hint != &"zip":
			continue
		var z := sn.anchors.find_zip(p, PlayerUtil.forward_of(p.camera_rig.yaw, p.camera_rig.pitch), SnakePower.range_m(), SnakeTraversal.assist)
		if not z.is_empty() and z["kind"] == &"roof" and (z["dest"] as Vector3).y > p.global_position.y + 4.0:
			spots.append(c)
	TestLib.check(spots.size() >= 5, "found %d street spots whose ZIP goes to a roof" % spots.size())
	var stood := 0
	var tried := 0
	for i in spots.size():
		var r := await _zip_once(i)
		if r >= 0:
			tried += 1
			stood += r
	TestLib.check(tried >= 5 and stood == tried, "a finger on ZIP at a roof: the hero stands on that roof in %d of %d zips" % [stood, tried])
	SnakeZip.roof_arc = false
	SnakeZip.wall_end = false                       # wave 117: the old code also left a zip that met the wall hanging there (now the snakes haul him over the edge: the straight pull alone lands 7 of 7)
	var stood_old := 0
	var tried_old := 0
	for i in spots.size():
		var r := await _zip_once(i)
		if r >= 0:
			tried_old += 1
			stood_old += r
	SnakeZip.roof_arc = true
	SnakeZip.wall_end = true
	TestLib.check(tried_old >= 5 and stood_old < tried_old, "OLD (the straight pull): %d of %d (the rest hang under the roof edge or are back on the street)" % [stood_old, tried_old])
	# a thumb that stays on the button
	var flew := 0
	for i in spots.size():
		if await _zip_hold(i):
			flew += 1
	TestLib.check(flew == 0, "SNAKE held 1.7 s on a ZIP never ends in SNAKE FLIGHT (%d of %d)" % [flew, spots.size()])
	SnakeTraversal.zip_takes_press = false
	SnakeTraversal.split_buttons = false                        # the wave 116 state: ONE snake button (it zipped, and the thumb that stayed on it took off); wave 118 gave ZIP its own button
	var flew_old := 0
	for i in spots.size():
		if await _zip_hold(i, &"snake"):
			flew_old += 1
	SnakeTraversal.zip_takes_press = true
	SnakeTraversal.split_buttons = true
	TestLib.check(flew_old > 0, "OLD: the held press took off from the roof in %d of %d" % [flew_old, spots.size()])


# --- the vehicle code while the hero flies -----------------------------------------------------------------------------------------------------

func _fly_at(pos: Vector3) -> bool:
	await _tp(pos, -PI * 0.5, 0.0, 6)
	if not await _until(func() -> bool: return fg.button(&"fly") != Vector2.INF, 1.0):
		return false
	fg.press(1, &"fly")
	await _f(4)
	fg.up(1)
	return await _until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 0.5)


func _cost() -> void:
	var vm := Game.vehicles as VehicleManager
	var out := Vector3(1500.0, 70.0, 850.0)                                               # over the hills, outside the street grid (CityLayout.HALF = 1040)
	TestLib.check(await _fly_at(out), "FLY by a finger in the air over the hills: the hero flies")
	await _f(30)
	var s0 := CityLayout.searches
	var p0 := CityLayout.passes
	var b0 := VehicleManager.point_builds
	await _f(180)
	TestLib.check(sn.mode == SnakeTraversal.Mode.FLY and CityLayout.passes == p0 and CityLayout.searches == s0, "3 s of flight outside the grid: the vehicle streamer ran %d road searches, %d passes over the road table" % [CityLayout.searches - s0, CityLayout.passes - p0])
	TestLib.check(VehicleManager.point_builds - b0 <= 1, "and built the spawn point table %d time(s)" % (VehicleManager.point_builds - b0))
	CityLayout.far_exit = false
	VehicleManager.cache_points = false
	p0 = CityLayout.passes
	b0 = VehicleManager.point_builds
	await _f(180)
	CityLayout.far_exit = true
	VehicleManager.cache_points = true
	TestLib.check(CityLayout.passes - p0 > 400 and VehicleManager.point_builds - b0 >= 2, "OLD: %d passes over the road table and %d builds of the spawn table in the same 3 s" % [CityLayout.passes - p0, VehicleManager.point_builds - b0])
	TestLib.check(vm.list.size() <= vm.cap(), "the streamer still keeps its cap (%d cars)" % vm.list.size())
	# back over the city the streamer finds its spots as before
	TestLib.check(await _fly_at(Vector3(-30.0, 60.0, 4.0)), "and over the city")
	s0 = CityLayout.searches
	var n0 := vm.list.size()
	await _f(150)
	TestLib.check(CityLayout.searches > s0, "over the city the streamer searches the roads again (%d searches, cars %d -> %d)" % [CityLayout.searches - s0, n0, vm.list.size()])
	# the road traffic: one free slot per respawn pass
	var rt := RoadTraffic.instance
	var worst := 0
	var worst_old := 0
	for trial in 2:
		RoadTraffic.one_try = trial == 0
		var up := await _fly_at(Vector3(1880.0, 105.0, 886.0))
		if trial == 0:
			TestLib.check(up and rt != null, "flying along the east highway")
		fg.stick(Vector2(0.0, -1.0))
		var last := rt.spawn_calls
		for i in 260:
			await _f(1)
			if trial == 0:
				worst = maxi(worst, rt.spawn_calls - last)
			else:
				worst_old = maxi(worst_old, rt.spawn_calls - last)
			last = rt.spawn_calls
		fg.stick(Vector2.ZERO)
	RoadTraffic.one_try = true
	TestLib.check(worst <= 1, "the road traffic tries at most one free slot per tick (%d)" % worst)
	TestLib.check(worst_old > 1, "OLD: up to %d slot tries (8 lane searches each) in one tick on the same pass" % worst_old)
