extends RefCounted
## WAVE 126 CRITIC (w126-critic) checks, in the REAL main scene. The player's actions are REAL FINGERS (InputEventScreenTouch / ScreenDrag through tests/w116_fingers.gd, window
## coordinates, Game.force_touch on, the phone-only layers on: CrateReveal._quiet = 0); set-up only places the hero.
##  1 ARMY SHELTERS: the fighter of each shelter is boarded with ENTER, rolled out of the door by the stick and taxied by the stick to the runway through the taxi lane in the
##    PLANE LINE and the HELI LINE, with no knock (before: the plane line was a wall from z -935 to -249, the fighter of shelter 1 hit a line helicopter and could not get through)
##  2 FIXED VEHICLES nearest first: the hero walks up to the HELI LINE; the helicopter in front of him stands within 2 s (before: 8 to 9 s, after the planes behind him)
##  5 RAIN: in the rain the hero walks by the stick into HANGAR A: no rain falls under its roof; out again, it rains (before: it rained inside)
##  4 HUD: in a plane at the airport a radio line of the cast shows; its portrait never stands on the landing guide or the instruments (before: it sat on the RWY label)
##  3 AIR TRAFFIC ground separation: 15 game minutes of the airport traffic, no two aircraft on the ground or under 15 m touch (fuselage and wing outlines); a departure waits off the
##    runway while it is in use; a landing goes around while a plane stands on the runway (before: an airliner lined up under a landing bizjet, took off 3 m over a rolling one,
##    a light plane taxied into a waiting airliner)
## W126C_OLD=1 is the wave 126 state as built (the nearest-first spawn and the traffic separation off); the shelter lanes are data (tools/gen_plane_roster.py LANES): their
## check failed on the tree before the lanes (log docs/sprint/progress/w126-critic.md). Checks marked [old fails] fail with W126C_OLD=1.
## Run: tools/test.sh tests/test_w126_critic.gd
const TIMEOUT_SECONDS := 140
const Fingers := preload("res://tests/w116_fingers.gd")

var host: Node
var fg: Fingers
var p: Player
var vm: VehicleManager
var _t := 0.0
var _min_gap := INF                     ## closest wing tip / rotor gap of the taxiing fighter (set inside the stick loop)
var _hit_txt := ""


func _f(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame


func _step() -> void:
	await host.get_tree().physics_frame
	_t += 1.0 / float(Engine.physics_ticks_per_second) * Engine.time_scale


func _until(cond: Callable, secs: float) -> bool:
	var t0 := _t
	while _t - t0 < secs:
		if cond.call():
			return true
		await _step()
	return cond.call()


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _f(4)
	fg.up(6)
	await _f(3)
	return true


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	var old := OS.get_environment("W126C_OLD") == "1"
	VehicleManager.W126C_OLD = old
	AirTraffic.separate = not old
	StoryView.badge_fix = not old
	Hangars.rain_fix = not old
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	fg = Fingers.new(host)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	Engine.max_physics_steps_per_frame = 4
	var parts := OS.get_environment("W126C_PART")
	if parts == "" or parts.contains("heli"):
		await _heli_line()
	if parts == "" or parts.contains("shelter"):
		await _shelter(&"p_fighter", -721.0)
		await _shelter(&"p_stealthf", -531.0)
	if parts == "" or parts.contains("rain"):
		await _rain()
	if parts == "" or parts.contains("hud"):
		await _hud()
	if parts == "" or parts.contains("traffic"):
		await _traffic()
	fg.up_all()
	VehicleManager.W126C_OLD = false
	AirTraffic.separate = true
	StoryView.badge_fix = true
	Hangars.rain_fix = true
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


func _stand(local: Vector3, look_local: Vector3) -> void:
	if vm.driven != null:
		await _tap(&"interact")
	fg.up_all()
	p.snake.cancel()
	p.snake.reset()
	var w := Airport.to_world(local)
	var d := Airport.to_world(look_local) - w
	p.teleport_to(w + Vector3(0.0, 0.3, 0.0))
	p.yaw = atan2(-d.x, -d.z)
	p.camera_rig.reset_view(p.yaw, -0.1)
	p.velocity = Vector3.ZERO
	await _f(10)


# --- 2: the helicopter in front of the hero stands first -----------------------------------------------------------------------------

func _heli_line() -> void:
	for k: StringName in [&"h_police", &"h_attack"]:
		vm._reset_all()
		var i := HeliRoster.NEW.find(k)
		var pad := Vector3(HeliRoster.LINE_X, 0.0, HeliRoster.LINE_Z0 + HeliRoster.LINE_STEP * float(i))
		await _stand(pad + Vector3(-14.0, 0.0, 0.0), pad)
		# walk two steps toward it by the stick (the hero is "walking up to the line")
		fg.stick(Vector2(0.0, -0.4))
		vm._spawn_t = 0.0
		var t0 := _t
		var id := StringName("hl_" + String(k))
		var got := await _until(func() -> bool:
			var x: Variant = vm._spawned.get(id)
			return is_instance_valid(x) and (x as Vehicle).active, 15.0)
		fg.stick(Vector2.ZERO)
		var n := 0
		for v in vm.list:
			if v.has_meta(&"fixed"):
				n += 1
		TestLib.check(got and _t - t0 <= 2.0, "[old fails] %s: walking up to the HELI LINE, the helicopter in front of the hero stands within 2 s (%.1f s, %d fixed vehicles stood by then)" % [k, _t - t0, n])


# --- 1: the shelter fighters reach the runway -----------------------------------------------------------------------------------------

func _shelter(k: StringName, lane_z: float) -> void:
	vm._reset_all()
	var pl: Array = PlaneRoster.PLACES[k]
	var pos: Vector3 = pl[0]
	var nose := pos + Vector3(0.0, 0.0, float(VehicleSpecs.SPECS[k]["len"]) * 0.5 + 3.5)
	await _stand(nose, pos)
	vm._spawn_t = 0.0
	var id := StringName("hg_" + String(k))
	await _until(func() -> bool: return is_instance_valid(vm._spawned.get(id)) and (vm._spawned.get(id) as Vehicle).active, 20.0)
	var v: Vehicle = vm._spawned.get(id)
	if v == null:
		TestLib.check(false, "%s waits in its shelter" % k)
		return
	# the planes and helicopters on both sides of the lane stand first (they appear one a second)
	var near_ids: Array[StringName] = []
	for pt: Dictionary in VehicleSpawns.all_points():
		var lp0 := Airport.to_local(pt["pos"])
		if (String(pt["id"]).begins_with("pl_") or String(pt["id"]).begins_with("hl_")) and absf(lp0.z - lane_z) < 45.0:
			near_ids.append(pt["id"])
	var all_up := await _until(func() -> bool:
		for nid in near_ids:
			var x: Variant = vm._spawned.get(nid)
			if not (is_instance_valid(x) and (x as Vehicle).active):
				return false
		return true, 30.0)
	TestLib.check(all_up and near_ids.size() >= 4, "%s: the %d aircraft beside the lane stand (%s)" % [k, near_ids.size(), near_ids])
	fg.stick(Vector2(0.0, -1.0))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 14.0)
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle != null, 1.0)
	TestLib.check(p.vehicle == v, "%s: walk up by the stick, a finger on ENTER boards it" % k)
	if p.vehicle != v:
		return
	var hp0 := v.hp
	var cr0 := v.crashes
	# taxi by the stick: out of the door (south), into the lane, west to the runway centre line
	var path: Array[Vector3] = [Vector3(pos.x, 0.0, lane_z - 14.0), Vector3(pos.x - 12.0, 0.0, lane_z), Vector3(1300.0, 0.0, lane_z), Vector3(Airport.RUNWAY_X, 0.0, lane_z)]
	var reached := true
	_min_gap = INF
	_hit_txt = ""
	for wl in path:
		var wp := Airport.to_world(wl)
		var ok := await _until(func() -> bool:
			var err := wrapf(atan2(-(wp.x - v.global_position.x), -(wp.z - v.global_position.z)) - v.heading, -PI, PI)
			var sy := 0.0
			var vt := 3.0 if absf(err) > 0.4 else 7.0
			if v.speed < vt and v.craft.lever < 0.25:
				sy = -0.6
			elif v.speed > vt + 1.0:
				sy = 1.0
			var sx := clampf(-2.5 * err, -1.0, 1.0)
			fg.stick(Vector2(sx, sy) if absf(sx) + absf(sy) > 0.02 else Vector2(0.0, 0.01))
			for o in vm.list:                                     # wing tips and rotor discs: the fighter's half span from the other's hull
				if o != v and o.active and _flat(o.global_position, v.global_position) < 40.0:
					var gap := o.edge_distance(v.global_position) - float(v.spec.get("span", v.spec["wid"])) * 0.5
					if o.craft != null and o.spec.has("rotor_r"):
						gap = minf(gap, _flat(o.global_position, v.global_position) - float(o.spec["rotor_r"]) - float(v.spec.get("span", v.spec["wid"])) * 0.5)
					if gap < _min_gap:
						_min_gap = gap
						_hit_txt = "%s %.1f m (fighter at local %s)" % [o.kind, gap, Airport.to_local(v.global_position).round()]
			return _flat(v.global_position, wp) < 5.0, 45.0)
		if not ok:
			reached = false
			break
	fg.stick(Vector2(0.0, 1.0))
	await _until(func() -> bool: return v.speed < 1.0, 10.0)
	fg.stick(Vector2.ZERO)
	var lp := Airport.to_local(v.global_position)
	TestLib.check(reached and absf(lp.x - Airport.RUNWAY_X) < 6.0 and v.crashes == cr0 and v.hp >= hp0 - 0.5 and _min_gap > 0.0,
		"%s: the stick rolls it out of %s and taxis it through the lane to the runway centre line, wings clear of every aircraft (at local %s, crashes %d, hp %.0f of %.0f; closest %s)" % [k, String(PlaneRoster.DEFS[k]["place"]), lp.round(), v.crashes - cr0, v.hp, hp0, _hit_txt])
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == null, 1.0)


# --- 3: air traffic ground separation -------------------------------------------------------------------------------------------------

func _traffic() -> void:
	var tr := AirTraffic.instance
	TestLib.check(tr != null, "the airport traffic runs")
	if tr == null:
		return
	if vm.driven != null:
		await _tap(&"interact")
	vm._reset_all()
	# the hero far from the airport (no real aircraft there), then the traffic runs for 15 game minutes in 0.1 s steps
	p.teleport_to(Vector3(0.0, 0.5, 0.0))
	await _f(10)
	var worst := INF
	var worst_txt := ""
	var t := 0.0
	var lineups_busy := 0
	var to0 := 0
	var la0 := 0
	for f in tr.flights:
		if not f.heli and not f.cross:
			to0 += f.takeoffs
			la0 += f.landings
	while t < 900.0:
		for f in tr.flights:
			tr._step(f, 0.1)
		t += 0.1
		for i in tr.flights.size():
			var a: AirTraffic.Flight = tr.flights[i]
			if a.heli or a.gone > 0.0 or a.pos.y > 15.0:
				continue
			if a.phase == &"lineup" and _other_on_runway(tr, a):
				lineups_busy += 1
			for j in range(i + 1, tr.flights.size()):
				var b: AirTraffic.Flight = tr.flights[j]
				if b.heli or b.gone > 0.0 or b.pos.y > 15.0:
					continue
				if absf(a.pos.y - b.pos.y) > 8.0 or a.pos.distance_to(b.pos) > 80.0:
					continue
				var sep := _clearance(a, b)
				if sep < worst:
					worst = sep
					worst_txt = "%s (%s) / %s (%s) %.1f m apart at local %s, outline clearance %.1f m" % [a.kind, a.phase, b.kind, b.phase, a.pos.distance_to(b.pos), a.pos.round(), sep]
	var to1 := -to0
	var la1 := -la0
	for f in tr.flights:
		if not f.heli and not f.cross:
			to1 += f.takeoffs
			la1 += f.landings
	TestLib.check(to1 >= 4 and la1 >= 4, "the traffic still flows: %d take-offs and %d landings of the airport planes in 15 min" % [to1, la1])
	TestLib.check(worst > 0.0, "[old fails] 15 min of airport traffic: no two aircraft on the ground or under 15 m touch (fuselage and wing outlines) (closest: %s)" % worst_txt)
	TestLib.check(lineups_busy == 0, "[old fails] a departure never lines up while another aircraft uses the runway (%d steps)" % lineups_busy)
	# a plane standing on the runway: landings go around, nothing lands through it
	var at := Airport.to_world(Vector3(Airport.RUNWAY_X, 0.0, -300.0))
	p.teleport_to(at + Vector3(30.0, 0.5, 0.0))
	await _f(4)
	vm._fixed_n += 1
	var blk := vm.spawn_parked(&"plane", at, Airport.heading_world(0.0))
	vm._count_fixed()
	if blk != null:
		blk.set_meta(&"hold", true)
	await _f(4)
	var ga0: int = tr.go_arounds if "go_arounds" in tr else 0
	var through := 0
	t = 0.0
	while t < 600.0 and blk != null:
		for f in tr.flights:
			tr._step(f, 0.1)
		t += 0.1
		var bl := Airport.to_local(blk.global_position)
		for f in tr.flights:
			if not f.heli and f.gone <= 0.0 and f.pos.y < 12.0 and Vector2(f.pos.x - bl.x, f.pos.z - bl.z).length() < 0.5 * AirTraffic._len_of(f.kind) + 5.0:
				through += 1
	var ga: int = (tr.go_arounds if "go_arounds" in tr else 0) - ga0
	TestLib.check(blk != null and through == 0 and ga > 0, "[old fails] a plane standing on the runway: 10 min of traffic, landings go around (%d) and nothing passes through it under 12 m (%d steps)" % [ga, through])
	if blk != null:
		vm._release(blk)


func _other_on_runway(tr: AirTraffic, a: AirTraffic.Flight) -> bool:
	for g in tr.flights:
		if g == a or g.heli or g.cross or g.gone > 0.0:
			continue
		if g.phase in [&"roll", &"touchdown", &"rollout", &"flare"] or (g.phase == &"climb" and g.pos.y < 20.0):
			return true
	return false


## The outline of a plane on the ground: its fuselage (len x 0.12 span) and its wing (span x 0.3 len), as oriented rectangles [centre, half axis 1, half axis 2] (2D, local x/z).
func _rects(f: AirTraffic.Flight) -> Array:
	var sp: Dictionary = VehicleSpecs.SPECS.get(f.kind, {})
	var ln := float(sp.get("len", 12.0))
	var span := float(sp.get("span", sp.get("wid", 3.0)))
	var fw := Vector2(-sin(f.heading), -cos(f.heading))
	var rt := Vector2(-fw.y, fw.x)
	var c := Vector2(f.pos.x, f.pos.z)
	return [[c, fw * ln * 0.5, rt * maxf(span * 0.06, 1.2)], [c, fw * ln * 0.15, rt * span * 0.5]]


## Smallest gap between the outlines of two planes (negative when they overlap): separating-axis distance of every rectangle pair.
func _clearance(a: AirTraffic.Flight, b: AirTraffic.Flight) -> float:
	var best := INF
	for ra: Array in _rects(a):
		for rb: Array in _rects(b):
			var gap := -INF
			for ax: Vector2 in [(ra[1] as Vector2).normalized(), (ra[2] as Vector2).normalized(), (rb[1] as Vector2).normalized(), (rb[2] as Vector2).normalized()]:
				var d := absf(((rb[0] as Vector2) - (ra[0] as Vector2)).dot(ax))
				var r := absf((ra[1] as Vector2).dot(ax)) + absf((ra[2] as Vector2).dot(ax)) + absf((rb[1] as Vector2).dot(ax)) + absf((rb[2] as Vector2).dot(ax))
				gap = maxf(gap, d - r)
			best = minf(best, gap)
	return best


# --- 4: the radio portrait and the flight instruments ---------------------------------------------------------------------------------

func _hud() -> void:
	vm._reset_all()
	var k := &"p_twin"
	var pl: Array = PlaneRoster.PLACES[k]
	var pos: Vector3 = pl[0]
	await _stand(pos + Vector3(0.0, 0.0, -(float(VehicleSpecs.SPECS[k]["len"]) * 0.5 + 3.5)), pos)
	vm._spawn_t = 0.0
	var id := StringName("pl_" + String(k))
	await _until(func() -> bool: return is_instance_valid(vm._spawned.get(id)) and (vm._spawned.get(id) as Vehicle).active, 20.0)
	fg.stick(Vector2(0.0, -1.0))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 14.0)
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle != null, 1.0)
	TestLib.check(p.vehicle != null and p.vehicle.cls == &"plane", "HUD: walk up by the stick, ENTER boards the %s" % k)
	var st := Game.story as Story
	if st == null or st.view == null:
		TestLib.check(false, "HUD: the story layer runs")
		return
	st.queue.clear()
	st.current = {}
	st.say("ORACLE", "Runway is yours. Keep the nose on the centre line and climb out east.", "w126c_test", 0.0, 5)
	await _until(func() -> bool: return not st.current.is_empty() and FlightHud.showing(), 4.0)
	TestLib.check(not st.current.is_empty() and FlightHud.showing(), "HUD: the radio line and the flight instruments show together")
	var root := host.get_tree().root
	var was := root.size
	for sz: Vector2i in [Vector2i(2400, 1080), Vector2i(1200, 540), Vector2i(844, 390)]:          # phone screens
		root.size = sz
		await _f(4)
		var vp := root.get_visible_rect().size
		var s := UiUtil.ui_scale(vp)
		var ins := UiUtil.insets(vp)
		var badge: Rect2 = st.view.badge_rect(vp)
		var guide := FlightHud.guide_rect(vp, s, ins)
		var inst := FlightHud.instruments_rect(vp, s, ins)
		TestLib.check(FlightHud.showing() and not badge.intersects(guide) and not badge.intersects(inst), "[old fails] HUD %s: the radio portrait stands clear of the landing guide %s and the instruments %s (portrait %s)" % [sz, guide, inst, badge])
	root.size = was
	await _f(3)
	st.queue.clear()
	st.current = {}
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == null, 1.0)


# --- 5: no rain under the hangar roof ---------------------------------------------------------------------------------------------------

func _rain() -> void:
	var atm := Game.atmosphere as Atmosphere
	if atm == null:
		TestLib.check(false, "RAIN: the atmosphere runs")
		return
	if atm.weather != null:
		atm.weather.process_mode = Node.PROCESS_MODE_DISABLED                 # set-up: steady rain for the check
	atm.set_weather(1.0, 1.0, true)
	var s := Hangars.site(&"hangar_a")
	var df := Hangars.door_frame(s)
	var c: Vector3 = df["c"]
	var out: Vector3 = df["out"]
	await _stand(c + out * 26.0, c - out * 10.0)
	await _f(10)
	var rain_out := atm.rainfield.streak_count() > 0
	fg.stick(Vector2(0.0, -1.0))
	var cam_in := await _until(func() -> bool:
		var cam := host.get_viewport().get_camera_3d()
		return cam != null and Hangars.inside(s, Airport.to_local(cam.global_position)) and Hangars.inside(s, Airport.to_local(p.global_position)) and Airport.to_local(p.global_position).distance_to(c) > 14.0, 20.0)
	fg.stick(Vector2.ZERO)
	await _f(10)
	var rain_in := atm.rainfield.streak_count()
	TestLib.check(rain_out and cam_in and rain_in == 0, "[old fails] RAIN: it rains on the apron (%s); the stick walks the hero into HANGAR A (camera inside %s) and no rain falls under the roof (%d streaks)" % [rain_out, cam_in, rain_in])
	fg.stick(Vector2(0.0, 1.0))
	await _until(func() -> bool:
		var cam := host.get_viewport().get_camera_3d()
		return cam != null and not Hangars.inside(s, Airport.to_local(cam.global_position)) and Airport.to_local(p.global_position).distance_to(c) > 10.0, 20.0)
	fg.stick(Vector2.ZERO)
	await _f(10)
	TestLib.check(atm.rainfield.streak_count() > 0, "RAIN: back out on the apron it rains again (%d streaks)" % atm.rainfield.streak_count())
	atm.set_weather(0.0, 0.0, true)
	if atm.weather != null:
		atm.weather.process_mode = Node.PROCESS_MODE_INHERIT
