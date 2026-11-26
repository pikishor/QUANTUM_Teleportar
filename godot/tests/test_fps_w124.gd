extends RefCounted
## Wave 124 FRAME RATE (owner round 7: LOW+ 37 to 45 FPS, 13 to 28 in flight). Real main scene at a 20:9 phone window, touch HUD on, reward cards ON (CrateReveal._quiet = 0),
## the hero takes to the air by REAL FINGERS (InputEventScreenTouch through Input.parse_input_event, tests/w116_fingers.gd: FLY tapped while he falls, UP held). Each check runs the
## old behaviour on the same spot in the same run (W124 switches) and must show the old code over the same bound.
##   props     flying 70 m over the blocks, the street prop families (sidewalk dressing, cafe sets, stalls, trash, planters ...) submit at most PROP_TRIS triangles and at most
##             PROP_FAMS non-empty families per tier (the windows count the camera's height like the prop shader does; the old windows drew every street prop within the radius
##             of the camera's ground point, all shrunk to nothing by the shader at that height)
##   street    the street people (crowd, vendors, bench sitters, street beats, citizen life, promoted citizens) cost less than 60 % of the script time high in the air that they cost
##             with every-frame steps; on foot they still step every frame
##   frame     with a real renderer (xvfb, not --headless): flying over the city stays under DRAWS / TRIS total per tier (skipped with a note on the dummy renderer)
## Run: tools/test.sh tests/test_fps_w124.gd   (frame check: xvfb-run -a godot --rendering-driver vulkan --rendering-method mobile --path . res://tests/runner.tscn -- --test=res://tests/test_fps_w124.gd)

const TIMEOUT_SECONDS := 140
const Fingers := preload("res://tests/w116_fingers.gd")
const AmbientCity := preload("res://scripts/ambient/ambient_city.gd")
const Stream := preload("res://scripts/world/city_stream.gd")
const SPOT := Vector3(-30.0, 72.0, 4.0)
const PROP_TRIS: Array[int] = [47000, 78000, 115000]          ## prop triangles in the windows 60 m over the blocks (LOW MED HIGH; measured 42.5k / 70k / 106k, old 64k / 95.5k / 126k)
const PROP_FAMS: Array[int] = [21, 22, 23]                     ## non-empty prop families (measured 19 / 21 / 23, old 23 / 24 / 24)
const DRAWS: Array[int] = [100, 140, 160]                      ## the staged-view budgets of PerfProbe.BUDGETS: flight may not cost more than the ground view's ceiling
const TRIS: Array[int] = [150000, 270000, 420000]
var host: Node
var fg: Fingers
var p: Player
var sn: SnakeTraversal


func _f(n: int) -> void:
	await TestLib.frames(host, n)


func _until(cond: Callable, frames: int) -> bool:
	for i in frames:
		if cond.call():
			return true
		await _f(1)
	return cond.call()


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
	TestLib.check(fg.tc != null and fg.tc.controls_on, "the touch HUD is on")
	var tier := clampi(Game.quality, 0, 2)
	var def_h := Stream.height_on                          # the game's own setting (W124_OLD=1 runs the old code here: every check below must then fail)
	var def_t := AmbientCity.alt_throttle
	# --- into the air by fingers ---
	p.teleport_to(SPOT)
	p.camera_rig.reset_view(-PI * 0.5, -0.25)
	await _f(2)
	var shown := await _until(func() -> bool: return fg.button(&"fly") != Vector2.INF, 90)
	if shown:
		fg.press(1, &"fly")
		await _f(4)
		fg.up(1)
	var flying := await _until(func() -> bool: return sn.mode == SnakeTraversal.Mode.FLY, 30)
	TestLib.check(flying, "FLY tapped by a finger in the air: the hero flies (button shown %s)" % str(shown))
	fg.press(1, &"jump")                                   # UP held: hold the height over the roofs
	await _f(30)
	fg.up(1)
	var alt := p.global_position.y
	TestLib.check(flying and alt > 55.0, "the hero flies high over the blocks (%.0f m)" % alt)
	# --- props: the street families' windows 70 m up, new and old ---
	var city := Game.world as City
	var fams: Array = city.stream_families() if city.has_method(&"stream_families") else []
	var now := await _props(city, fams, def_h)
	var old := await _props(city, fams, false)
	TestLib.check(now[0] <= PROP_TRIS[tier] and now[1] <= PROP_FAMS[tier], "60 m up the street props submit %d triangles in %d families (budget %d / %d, tier %d)" % [now[0], now[1], PROP_TRIS[tier], PROP_FAMS[tier], tier])
	TestLib.check(old[0] > PROP_TRIS[tier] or old[1] > PROP_FAMS[tier], "OLD windows over the same budget: %d triangles in %d families" % [old[0], old[1]])
	TestLib.check(now[0] < old[0] * 0.9, "the windows that count the height submit under 90 %% of the old triangles (%d vs %d)" % [now[0], old[0]])
	# --- street people script time in the air, throttled vs every frame ---
	var t_off := await _street_ms(false)
	var t_on := await _street_ms(def_t)
	t_off = minf(t_off, await _street_ms(false))           # twice each, the better run: another process on the machine can stall either one
	t_on = minf(t_on, await _street_ms(def_t))
	var amb: Object = (Game.world as Node).get(&"ambient")
	var share_on := await _street_share(amb, def_t)
	var share_off := await _street_share(amb, false)
	TestLib.check(share_on < 0.4 and share_off > 0.95, "high in the air the street people step in %.0f %% of the frames (the old code: %.0f %%)" % [share_on * 100.0, share_off * 100.0])
	TestLib.check(t_on < t_off * 0.6, "high in the air the street people cost %.3f ms a frame, under 60 %% of every-frame steps (%.3f ms, the old code)" % [t_on, t_off])
	# --- the frame, with a real renderer ---
	var s := PerfProbe.snapshot(host.get_viewport())
	if int(s["total_draws"]) == 0:
		print("NOTE: dummy renderer (--headless): the draw / triangle budget of the flight frame is checked under xvfb only")
	else:
		await _f(10)
		s = PerfProbe.snapshot(host.get_viewport())
		TestLib.check(int(s["total_draws"]) <= DRAWS[tier] and int(s["total_prims"]) <= TRIS[tier], "flying over the city the frame draws %d calls, %d triangles (budget %d / %d, tier %d)" % [s["total_draws"], s["total_prims"], DRAWS[tier], TRIS[tier], tier])
	# --- the sun's shadow high over the outskirts (MED / HIGH have one) ---
	var def_s := City.high_shadow_on
	var base_on: bool = PostFx2.SHADOW[tier]["on"]
	if base_on:
		var gx := 1750.0
		var gz := 850.0
		var gy := TerrainHeight.height_at(gx, gz)
		var want := gy + city.sun.directional_shadow_max_distance + 50.0
		p.teleport_to(Vector3(gx, want, gz))                 # setup: the flying hero is put high over the hills, he keeps flying by UP held
		var high := await _shadow_at(city, want, def_s)
		var high_old := await _shadow_at(city, want, false)
		TestLib.check(not high[0] and high_old[0], "%.0f m over the outskirts the sun's shadow pass is off (old code: on); its range is %.0f m" % [high[2], city.sun.directional_shadow_max_distance])
		if int(high[1]) > 0:
			TestLib.check(int(high[1]) < int(high_old[1]), "... and the frame draws fewer calls (%d vs %d)" % [high[1], high_old[1]])
		var low := await _shadow_at(city, gy + 30.0, def_s)
		TestLib.check(low[0], "30 m over the hills the sun casts shadows again")
		City.high_shadow_on = def_s
	else:
		print("NOTE: tier %d has no sun shadow: the height rule has nothing to switch" % tier)
	# --- on foot the street still steps every frame ---
	AmbientCity.alt_throttle = def_t
	sn.cancel()
	sn.reset()
	p.teleport_to(Vector3(-30.0, 0.0, 4.0))
	await _f(30)
	var t0 := int(amb.get(&"ticks"))
	var s0 := int(amb.get(&"street_ticks"))
	await _until(func() -> bool: return int(amb.get(&"ticks")) - t0 >= 30, 400)
	var dt := int(amb.get(&"ticks")) - t0
	var ds := int(amb.get(&"street_ticks")) - s0
	TestLib.check(dt > 10 and ds == dt, "on foot the street people step every frame (%d of %d)" % [ds, dt])
	fg.up_all()
	AmbientCity.alt_throttle = def_t
	Stream.height_on = def_h
	CrateReveal._quiet = -1
	host.get_window().size = win_size
	Game.force_touch = false
	main.queue_free()
	await _f(2)


func _hold_air() -> void:
	sn.energy = SnakePower.max_energy()
	if p.global_position.y < 66.0 and fg.button(&"jump") != Vector2.INF and not fg.held.has(1):
		fg.press(1, &"jump")
	elif p.global_position.y > 74.0 and fg.held.has(1):
		fg.up(1)


## [triangles, non-empty families] of the street prop families (height_fade) after the windows settle at the hero's height, with the height rule on or off.
func _props(city: City, fams: Array, on: bool) -> Array:
	Stream.height_on = on
	var cam := host.get_viewport().get_camera_3d()
	city.update_streaming(Vector2(cam.global_position.x, cam.global_position.z), true)
	for i in 6:
		_hold_air()
		await _f(1)
	var tris := 0
	var n := 0
	for f in fams:
		if not bool(f.get(&"height_fade")):
			continue
		var sh := int(f.get(&"shown"))
		if sh < 0:
			sh = int(f.get(&"total"))
		if sh > 0 and (f.get(&"mm") as MultiMesh) != null:
			tris += sh * int(f.get(&"tris"))
			n += 1
			if OS.get_environment("W124_VERBOSE") != "":
				print("  fam %s on=%s shown %d tris %d top %.0f" % [f.get(&"name"), str(on), sh, sh * int(f.get(&"tris")), float(f.get(&"top_y"))])
	return [tris, n]


## The street people's script time (CROWD + NPC + CITIZENS, ms per frame averaged over 120 frames) in the air with the altitude throttle on or off.
func _street_ms(on: bool) -> float:
	AmbientCity.alt_throttle = on
	for i in 30:
		_hold_air()
		await _f(1)
	# the mean of the smoothed average over 150 frames is the mean cost per frame (the smoothing is linear)
	var acc := 0.0
	for i in 150:
		_hold_air()
		await _f(1)
		for id in [PerfTimers.CROWD, PerfTimers.NPC, PerfTimers.CITIZENS]:
			acc += PerfTimers.avg_ms(id)
	return acc / 150.0


## Share of the ambient frames with a street step over 60 frames in the air.
func _street_share(amb: Object, on: bool) -> float:
	AmbientCity.alt_throttle = on
	var t0 := int(amb.get(&"ticks"))
	var s0 := int(amb.get(&"street_ticks"))
	for i in 60:
		_hold_air()
		await _f(1)
	return float(int(amb.get(&"street_ticks")) - s0) / maxf(float(int(amb.get(&"ticks")) - t0), 1.0)


## [sun shadow on, total draws (0 headless), height over the terrain] after holding the hero at `y` for a moment, with the height rule on or off.
func _shadow_at(city: City, y: float, on: bool) -> Array:
	City.high_shadow_on = on
	for i in 40:
		sn.energy = SnakePower.max_energy()
		var pos := p.global_position
		if absf(pos.y - y) > 3.0:
			p.global_position = Vector3(pos.x, y, pos.z)   # setup: hold the height exactly (UP / DOWN would overshoot by metres)
			p.velocity = Vector3.ZERO
		await _f(1)
	var s := PerfProbe.snapshot(host.get_viewport())
	return [city.sun.shadow_enabled, int(s["total_draws"]), p.global_position.y - TerrainHeight.height_at(p.global_position.x, p.global_position.z)]
