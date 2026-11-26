extends RefCounted
## WAVE 126 critic (w126-critic): an independent FINGER-ONLY review probe in the real main scene (headless runner). Every player action is a real InputEventScreenTouch / ScreenDrag
## (tests/w116_fingers.gd), Game.force_touch on, the phone-only layers on (CrateReveal._quiet = 0). Set-up only puts the hero at a start point.
## The bot pilot flies by the stick (throttle, bank) and UP / DOWN like a thumb would: taxi from the plane's own place onto the runway, take-off, a circuit, landing, brake.
## Prints "CRP ..." lines (findings). Not part of the suite (no test_ prefix).
##   CRP_PARTS=line,fly,missions,traffic  CRP_KINDS=p_duster,p_jumbo
##   godot --headless --path . res://tests/runner.tscn -- --test=res://tests/bot_w126_critic.gd
const TIMEOUT_SECONDS := 3000
const Fingers := preload("res://tests/w116_fingers.gd")
const AirT := preload("res://tests/test_air_w126.gd")

var host: Node
var fg: Fingers
var p: Player
var vm: VehicleManager
var _t := 0.0


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


func _on(part: String) -> bool:
	var parts := OS.get_environment("CRP_PARTS").split(",", false)
	return parts.is_empty() or parts.has(part)


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	TerrainHeight.warm()
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
	TestMode.god = OS.get_environment("CRP_GOD") != "0"
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	Engine.max_physics_steps_per_frame = 4
	if OS.get_environment("CRP_PARTS") == "terrain":
		for lz in range(-2600, 1400, 200):
			var row := "CRP terr z %5d:" % lz
			for lx in range(400, 2400, 150):
				var w := Airport.to_world(Vector3(lx, 0.0, lz))
				row += " %4.0f" % TerrainHeight.height_at(w.x, w.z)
			print(row)
	if _on("line"):
		await _line()
	if _on("fly"):
		var kinds := OS.get_environment("CRP_KINDS")
		var list: Array = kinds.split(",", false) if kinds != "" else ["p_duster", "p_twin", "p_regional", "p_jumbo", "p_attack", "p_bomber", "p_glider", "p_sst", "p_manta", "p_drone", "p_fighter", "p_cub"]
		for k: String in list:
			var rt := Time.get_ticks_msec()
			await _kind(StringName(k))
			if vm.driven != null:
				await _tap(&"interact")
			vm._reset_all()
			await _f(2)
			print("CRP %s took %.1f s real" % [k, (Time.get_ticks_msec() - rt) / 1000.0])
	if _on("missions"):
		await _missions()
	if _on("traffic"):
		await _traffic()
	fg.up_all()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


# --- the airport layout as it stands in the game ------------------------------------------------------------------------------------------

func _ground_y(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -80.0, z), Game.L_WORLD)
	var r := host.get_tree().root.get_world_3d().direct_space_state.intersect_ray(q)
	return float((r["position"] as Vector3).y) if not r.is_empty() else NAN


func _line() -> void:
	# walk the hero along the PLANE LINE / HELI LINE; for each stop, how long until the vehicle right in front of him stands there
	for id_kind: Array in [["hl_h_police", Vector3(1322.0, 0.0, -854.0)], ["hl_h_scout", Vector3(1322.0, 0.0, -930.0)], ["pl_p_jumbo", Vector3(1300.0, 0.0, -690.0)], ["hl_h_attack", Vector3(1322.0, 0.0, -664.0)]]:
		vm._reset_all()
		var w := Airport.to_world(id_kind[1])
		p.teleport_to(w + Vector3(0.0, 0.5, 0.0))
		await _f(10)
		vm._spawn_t = 0.0
		var t0 := _t
		var got := await _until(func() -> bool:
			var x: Variant = vm._spawned.get(StringName(id_kind[0]))
			return is_instance_valid(x) and (x as Vehicle).active, 40.0)
		var n := 0
		for v in vm.list:
			if v.has_meta(&"fixed"):
				n += 1
		print("CRP line spawn %s in front of the hero after %.1f s game (%s), %d fixed vehicles spawned before" % [id_kind[0], _t - t0, got, n])
	# everything at the airport: under the floor? overlapping?
	p.teleport_to(Airport.to_world(Vector3(1250.0, 0.0, -600.0)) + Vector3(0.0, 0.5, 0.0))
	await _until(func() -> bool: return false, 60.0)
	var air: Array[Vehicle] = []
	for v in vm.list:
		if v.active and v.craft != null:
			air.append(v)
			var g := _ground_y(v.global_position.x, v.global_position.z)
			var lp := Airport.to_local(v.global_position)
			if absf(v.global_position.y - g) > 0.6:
				print("CRP floor %s %s at local (%.0f, %.0f): y %.2f ground %.2f (%.2f)" % [v.kind, v.get_meta(&"spawn_id", ""), lp.x, lp.z, v.global_position.y, g, v.global_position.y - g])
	for i in air.size():
		for j in range(i + 1, air.size()):
			var a := air[i]
			var b := air[j]
			var ra := maxf(float(a.spec.get("span", a.spec["wid"])), float(a.spec.get("rotor_r", 0.0)) * 2.0) * 0.5
			var rb := maxf(float(b.spec.get("span", b.spec["wid"])), float(b.spec.get("rotor_r", 0.0)) * 2.0) * 0.5
			if a.edge_distance(b.global_position) < 0.5 or b.edge_distance(a.global_position) < 0.5:
				print("CRP overlap hull %s / %s" % [a.kind, b.kind])
			elif _flat(a.global_position, b.global_position) < ra + rb - 1.0 and _flat(a.global_position, b.global_position) < 25.0:
				print("CRP near %s / %s %.1f m apart (radii %.1f + %.1f)" % [a.kind, b.kind, _flat(a.global_position, b.global_position), ra, rb])
	print("CRP airport aircraft standing: %d" % air.size())


# --- the bot pilot: only fingers ---------------------------------------------------------------------------------------------------------

var held := &""


func _hold(btn: StringName) -> void:
	if btn == held:
		return
	fg.up(1)
	if btn != &"":
		fg.press(1, btn)
	held = btn


## One step of the thumb: steer toward heading `want`, lever toward `lever` (stick y), UP / DOWN toward `agl`.
func _pilot(v: Vehicle, want: float, lever: float, agl: float) -> void:
	var err := wrapf(want - v.heading, -PI, PI)
	var sx := clampf(-2.0 * err + 0.6 * v.yaw_rate, -1.0, 1.0)
	var sy := 0.0
	if v.craft.lever < lever - 0.04:
		sy = -1.0
	elif v.craft.lever > lever + 0.04:
		sy = 1.0
	fg.stick(Vector2(sx, sy) if absf(sx) + absf(sy) > 0.02 else Vector2(0.0, 0.01))
	if agl < 0.0:
		_hold(&"")
		return
	var a := VehicleCraft.altitude(v)
	_hold(&"jump" if a < agl - 6.0 else (&"crouch" if a > agl + 10.0 else &""))


func _head_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


## Fly to `to` at `agl` m over the ground; true when within `r` m (flat).
func _fly_to(v: Vehicle, to: Vector3, agl: float, r: float, secs: float, A: AircraftFlight.Air) -> bool:
	var t0 := _t
	while _t - t0 < secs:
		await _step()
		if v.dead or not v.active or p.vehicle != v:
			return false
		_pilot(v, _head_to(v.global_position, to), 0.85, agl)
		if OS.get_environment("CRP_TRACE") == "1" and Engine.get_physics_frames() % 120 == 0:
			print("CRP trace %s agl %.0f y %.0f speed %.0f lever %.2f pitch %.2f roll %.2f hp %.0f held %s air %s dist %.0f" % [v.kind, VehicleCraft.altitude(v), v.global_position.y, v.speed, v.craft.lever, A.pitch, A.roll, v.hp, held, v.craft.airborne, _flat(v.global_position, to)])
		if _flat(v.global_position, to) < r:
			return true
	return false


func _kind(k: StringName) -> void:
	var line: bool = PlaneRoster.DEFS.has(k) and PlaneRoster.DEFS[k]["place"] == &"line"
	var id := StringName(("pl_" if line else "hg_") + String(k))
	var pl: Array = PlaneRoster.PLACES[k]
	var pos := Airport.to_world(pl[0])
	var spec: Dictionary = VehicleSpecs.SPECS[k]
	var hw := Airport.heading_world(float(pl[1]))
	var fwd := Vector3(-sin(hw), 0.0, -cos(hw))
	var stand := pos + fwd * (float(spec["len"]) * 0.5 + 3.5)
	if vm.driven != null:
		await _tap(&"interact")
	fg.up_all()
	p.snake.cancel()
	p.snake.reset()
	p.teleport_to(stand + Vector3(0.0, 0.3, 0.0))
	var d := pos - stand
	p.yaw = atan2(-d.x, -d.z)
	p.camera_rig.reset_view(p.yaw, -0.1)
	p.velocity = Vector3.ZERO
	await _f(10)
	vm._spawn_t = 0.0
	var v: Vehicle = null
	var t0 := _t
	while _t - t0 < 30.0:
		await _step()
		var x: Variant = vm._spawned.get(id)
		if is_instance_valid(x) and (x as Vehicle).active:
			v = x
			break
	if v == null:
		print("CRP %s DEFECT never stood at its place (%.0f s)" % [k, _t - t0])
		return
	print("CRP %s stood after %.1f s; y %.2f ground %.2f" % [k, _t - t0, v.global_position.y, _ground_y(v.global_position.x, v.global_position.z)])
	fg.stick(Vector2(0.0, -1.0))
	var reached := await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 14.0)
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle != null, 1.0)
	if p.vehicle != v:
		print("CRP %s DEFECT not boarded (reached %s, label '%s', in %s)" % [k, reached, fg.button_label(&"interact"), p.vehicle.kind if p.vehicle != null else &"-"])
		return
	var A := AircraftFlight.air(v.craft)
	var hp0 := v.hp
	# TAXI by the stick from its place onto the runway centre line (whichever way is shorter), slow
	var lp := Airport.to_local(v.global_position)
	var entry_l := Vector3(Airport.RUNWAY_X, 0.0, clampf(lp.z, Airport.RUNWAY_N + 60.0, Airport.RUNWAY_S - 60.0))
	if not line:
		# hangars and shelters: out through the door first
		if PlaneRoster.DEFS[k]["place"] in [&"hangar_a", &"hangar_b"]:
			entry_l = Vector3(Airport.RUNWAY_X, 0.0, lp.z)
	var long_n := entry_l.z > -450.0                      # the mountains rise 600 m north of the runway: take off south when there is room
	var dir_l := Vector3(0.0, 0.0, -1.0) if long_n else Vector3(0.0, 0.0, 1.0)
	var path: Array[Vector3] = []
	if not line:
		var out_l: Vector3 = lp + Vector3(-sin(float(pl[1])), 0.0, -cos(float(pl[1]))) * 40.0
		path.append(Airport.to_world(out_l))
	path.append(Airport.to_world(entry_l - dir_l * 30.0 + Vector3(18.0 if line else -18.0, 0.0, 0.0)))
	path.append(Airport.to_world(entry_l))
	path.append(Airport.to_world(entry_l + dir_l * 40.0))
	var taxi_ok := true
	for wp in path:
		var tt := _t
		while _t - tt < 60.0:
			await _step()
			var want := _head_to(v.global_position, wp)
			var err := wrapf(want - v.heading, -PI, PI)
			var sx := clampf(-2.5 * err, -1.0, 1.0)
			var sy := 0.0
			var vt := 4.0 if absf(err) > 0.4 else 8.0
			if v.speed < vt and v.craft.lever < 0.25:
				sy = -0.6
			elif v.speed > vt + 1.0:
				sy = 1.0
			fg.stick(Vector2(sx, sy) if absf(sx) + absf(sy) > 0.02 else Vector2(0.0, 0.01))
			if _flat(v.global_position, wp) < 6.0:
				break
		if _flat(v.global_position, wp) >= 6.0:
			taxi_ok = false
			print("CRP %s DEFECT taxi stuck %.0f m from waypoint local %s (at local %s, speed %.1f, hp %.0f/%.0f, hits %d)" % [k, _flat(v.global_position, wp), Airport.to_local(wp).round(), Airport.to_local(v.global_position).round(), v.speed, v.hp, v.max_hp, v.crashes])
			break
	if v.hp < hp0 - 1.0 or v.crashes > 0:
		print("CRP %s DEFECT taxi damage hp %.0f -> %.0f crashes %d" % [k, hp0, v.hp, v.crashes])
	if not taxi_ok:
		# put it on the runway (set-up) to go on with the flight review
		v.global_position = Airport.to_world(entry_l) + Vector3(0.0, v.global_position.y - Airport.to_world(entry_l).y, 0.0)
		v.speed = 0.0
		v.vel = Vector3.ZERO
	var dir := Airport.FRAME.basis * dir_l
	var side := Vector3(-dir.z, 0.0, dir.x)
	var hdir := atan2(-dir.x, -dir.z)
	# TAKE-OFF: full lever, UP; steer on the centre line
	var axis0 := Airport.to_world(Vector3(Airport.RUNWAY_X, 0.0, 0.0))
	var start := v.global_position
	var hp1 := v.hp
	fg.press(1, &"jump")
	held = &"jump"
	var off := false
	var tt2 := _t
	while _t - tt2 < 40.0:
		await _step()
		var g := v.global_position
		var lat := (g - axis0).dot(side)
		var want := hdir + clampf(lat * 0.03, -0.3, 0.3) * (1.0 if true else -1.0)
		var tg := g + dir * 60.0 - side * lat
		want = _head_to(g, tg)
		var err := wrapf(want - v.heading, -PI, PI)
		fg.stick(Vector2(clampf(-2.5 * err, -1.0, 1.0), -1.0))
		if v.craft.airborne:
			off = true
			break
	var run := _flat(v.global_position, start)
	var lat_off := absf((v.global_position - axis0).dot(side))
	print("CRP %s take-off %s after %.0f m (lateral %.1f m, hp %.0f -> %.0f)" % [k, off, run, lat_off, hp1, v.hp])
	if not off:
		print("CRP %s DEFECT cannot take off (speed %.1f stall %.0f lever %.2f)" % [k, v.speed, float(spec["stall"]), v.craft.lever])
		fg.up_all()
		held = &""
		return
	# CIRCUIT: out, crosswind, downwind, base, final (left-hand, away from the city side), 90 m
	# land northbound on 09 (from the flat south); take-offs north turn east at once (the mountains)
	var near_end := Airport.to_world(Vector3(Airport.RUNWAY_X, 0.0, Airport.RUNWAY_S))
	var ldir := Airport.FRAME.basis * Vector3(0.0, 0.0, -1.0)
	var wl: Array = [Vector3(1900.0, 0.0, -900.0), Vector3(1900.0, 0.0, 1400.0), Vector3(1262.0, 0.0, 1700.0)] if long_n else [Vector3(1262.0, 0.0, 700.0), Vector3(1700.0, 0.0, 1400.0), Vector3(1262.0, 0.0, 1700.0)]
	var wps: Array[Vector3] = []
	for q: Vector3 in wl:
		wps.append(Airport.to_world(q))
	var max_agl := 0.0
	var circ := true
	for wp in wps:
		var ok := await _fly_to(v, wp, 120.0, 150.0, 150.0, A)
		max_agl = maxf(max_agl, VehicleCraft.altitude(v))
		if not ok:
			circ = false
			print("CRP %s DEFECT circuit leg failed (%.0f m off, agl %.0f, speed %.0f, dead %s) at local %s" % [k, _flat(v.global_position, wp), VehicleCraft.altitude(v), v.speed, v.dead, Airport.to_local(v.global_position).round()])
			break
	if not circ:
		fg.up_all()
		held = &""
		return
	# FINAL: line up, glide slope, lever by speed, flare by the game
	var landed := false
	var stall := float(spec["stall"])
	var tt3 := _t
	while _t - tt3 < 120.0:
		await _step()
		if v.dead or p.vehicle != v:
			break
		var g := v.global_position
		var along := (g - near_end).dot(ldir)
		var lat := (g - axis0).dot(side)
		var tg := near_end + ldir * (along + maxf(150.0, -along * 0.35)) + Vector3.ZERO
		tg -= side * 0.0
		var want := _head_to(g, Vector3(tg.x, 0.0, tg.z) - side * 0.0)
		want = _head_to(g, near_end + ldir * (along + maxf(150.0, -along * 0.35)))
		var want_agl := maxf(-along, 0.0) * 0.07 + 4.0
		var lv := 0.0
		if along < -60.0:
			lv = 0.55 if v.speed < stall * 1.35 else 0.15
		var a := VehicleCraft.altitude(v)
		var btn := &""
		if along < -40.0:
			btn = &"crouch" if a > want_agl + 6.0 else (&"jump" if a < want_agl - 6.0 else &"")
		_pilot(v, want, lv, -1.0)
		_hold(btn)
		if not v.craft.airborne:
			landed = true
			break
	_hold(&"")
	var gp := v.global_position
	var al := (gp - near_end).dot(ldir)
	var latl := absf((gp - axis0).dot(side))
	print("CRP %s landing %s at %.0f m along, %.1f m off the axis, crashes %d wing strikes %d, hp %.0f, max agl %.0f" % [k, landed, al, latl, A.crashes, A.wing_strikes, v.hp, max_agl])
	if not landed or latl > Airport.RUNWAY_W * 0.5 or al < -5.0 or A.crashes > 0:
		print("CRP %s DEFECT landing" % k)
	var stopped := await _until(func() -> bool:
		var g2 := v.global_position
		var e2 := wrapf(_head_to(g2, near_end + ldir * ((g2 - near_end).dot(ldir) + 40.0)) - v.heading, -PI, PI)
		fg.stick(Vector2(clampf(-2.5 * e2, -0.7, 0.7), 1.0))
		return v.speed < 2.0, 40.0)
	fg.stick(Vector2.ZERO)
	var al2 := (v.global_position - near_end).dot(ldir)
	print("CRP %s stop %s at %.0f m along (runway %.0f), hp %.0f of %.0f, vehicle crashes %d" % [k, stopped, al2, Airport.RUNWAY_LEN, v.hp, v.max_hp, v.crashes])
	if al2 > Airport.RUNWAY_LEN:
		print("CRP %s DEFECT overran the runway" % k)
	fg.up_all()
	held = &""
	await _tap(&"interact")


# --- missions, played by the bot pilot (fingers) -----------------------------------------------------------------------------------------

var at: AirT


func _missions() -> void:
	at = AirT.new()
	at.host = host
	at.fg = fg
	at.p = p
	at.vm = vm
	at.hud = host.get_tree().root.find_children("*", "Hud", true, false)[0] as Hud
	at.board = MissionBoardScreen.board()
	at.board.take_over = false
	Engine.physics_ticks_per_second = 180
	Engine.time_scale = 3.0
	var list := OS.get_environment("CRP_MISSIONS")
	for t: String in (list.split(",", false) if list != "" else ["air_rings", "air_dogfight", "air_bomb", "air_escort", "air_cargo", "air_rescue"]):
		var done0 := at.board.done_count
		var ok := await at._board_start(StringName(t))
		if not ok:
			print("CRP mission %s DEFECT did not start" % t)
			continue
		var k := at._camp()
		var steps_txt := ""
		for s: Dictionary in k.steps:
			steps_txt += "%s@%s; " % [s.get("kind", ""), (s.get("pos", Vector3.ZERO) as Vector3).round()]
		print("CRP mission %s steps %s" % [t, steps_txt])
		var v := await at._board_provided()
		if v == null:
			print("CRP mission %s DEFECT provided aircraft not boarded" % t)
			continue
		var t0 := _t
		await _play(StringName(t), v, k)
		var fin := at.board.done_count > done0
		print("CRP mission %s finished %s in %.0f s game (%s) hp %.0f/%.0f" % [t, fin, _t - t0, k.hud_line(), v.hp, v.max_hp])
		fg.up_all()
		held = &""
		if at.board.is_running():
			at.board.abandon("CRP")
		await _f(4)


## Take off from where the provided aircraft stands (straight ahead along its nose) and climb out.
func _takeoff(v: Vehicle) -> bool:
	var A := AircraftFlight.air(v.craft)
	var hd := v.heading
	_hold(&"jump")
	var ok := await _until(func() -> bool:
		_pilot(v, hd, 1.0, -1.0)
		_hold(&"jump")
		return v.craft.airborne, 40.0)
	if not ok:
		print("CRP DEFECT provided %s did not take off (speed %.0f, at local %s)" % [v.kind, v.speed, Airport.to_local(v.global_position).round()])
		return false
	await _until(func() -> bool:
		_pilot(v, hd, 1.0, 80.0)
		return VehicleCraft.altitude(v) > 40.0, 30.0)
	return true


func _play(t: StringName, v: Vehicle, k: CampaignRunner) -> void:
	var A := AircraftFlight.air(v.craft)
	if v.cls == &"plane":
		if not await _takeoff(v):
			return
	var t0 := _t
	var fire_held := false
	while _t - t0 < 600.0 and at.board.is_running() and p.vehicle == v and not v.dead:
		await _step()
		var target: Vector3 = k.pos
		var agl := 90.0
		var tsk := String(k.step.get("task", k.step.get("kind", "")))
		if k.step.get("kind", "") == "gates":
			agl = -2.0
		if tsk == "dogfight" or tsk == "escort":
			var best: Vehicle = null
			for b in k.air.bandits:
				if is_instance_valid(b) and (best == null or _flat(b.global_position, v.global_position) < _flat(best.global_position, v.global_position)):
					best = b
			if best != null:
				target = best.global_position + best.vel * 1.5
				agl = -2.0
				var to := target - v.global_position
				var ang := v.forward().angle_to(to.normalized())
				var want_fire := to.length() < 500.0 and ang < 0.12
				if want_fire != fire_held:
					if want_fire:
						fg.press(2, &"fire")
					else:
						fg.up(2)
					fire_held = want_fire
			elif tsk == "escort" and is_instance_valid(k.air.liner):
				target = k.air.liner.global_position
		if tsk == "bomb" or tsk == "drop":
			agl = 70.0
		if agl == -2.0:
			# fly at the target's height
			var dy := target.y - v.global_position.y
			_pilot(v, _head_to(v.global_position, target), 0.9, -1.0)
			_hold(&"jump" if dy > 6.0 else (&"crouch" if dy < -6.0 else &""))
		elif v.cls == &"heli":
			pass
		else:
			_pilot(v, _head_to(v.global_position, target), 0.85, agl)
		if (tsk == "bomb" or tsk == "drop") and v.weapons != null and v.weapons.arms != null:
			var arms: AirArms = v.weapons.arms
			var imp: Vector3 = arms.bomb_impact()
			if _flat(imp, target) < 15.0 and int(_t * 4.0) % 2 == 0:
				fg.press(4, &"aim")
				await _f(2)
				fg.up(4)
	if fire_held:
		fg.up(2)


# --- air traffic for 2 minutes ---------------------------------------------------------------------------------------------------------

func _traffic() -> void:
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 2.0
	if vm.driven != null:
		await _tap(&"interact")
	vm._reset_all()
	p.teleport_to(Airport.to_world(Vector3(1240.0, 0.0, -560.0)) + Vector3(0.0, 0.5, 0.0))
	await _f(10)
	var tr := AirTraffic.instance
	if tr == null:
		print("CRP traffic DEFECT no AirTraffic")
		return
	var minpair := INF
	var minpair_txt := ""
	var t0 := _t
	var seen := {}
	var close := {}
	var to0 := 0
	var la0 := 0
	for f in tr.flights:
		to0 += f.takeoffs
		la0 += f.landings
	while _t - t0 < 120.0:
		await _step()
		if Engine.get_physics_frames() % 20 != 0:
			continue
		for f in tr.flights:
			seen[f.kind] = true
		for i in tr.flights.size():
			var a: AirTraffic.Flight = tr.flights[i]
			if a.gone > 0.0:
				continue
			for j in range(i + 1, tr.flights.size()):
				var b: AirTraffic.Flight = tr.flights[j]
				if b.gone > 0.0:
					continue
				var dd := a.pos.distance_to(b.pos)
				if dd < minpair:
					minpair = dd
					minpair_txt = "%s(%s)/%s(%s) at local %s" % [a.kind, a.phase, b.kind, b.phase, Airport.to_local(a.pos).round()]
			# a flight on the ground or low near a parked / player vehicle
			if a.pos.y < 15.0:
				for v in vm.list:
					if not v.active:
						continue
					var rr := float(v.spec.get("span", v.spec["wid"])) * 0.5 + 6.0
					var dd2 := _flat(a.pos, v.global_position)
					if dd2 < rr:
						var key := "%s/%s" % [a.kind, v.kind]
						if not close.has(key):
							close[key] = true
							print("CRP traffic DEFECT %s (%s, y %.1f) through %s %s at local %s (%.1f m)" % [a.kind, a.phase, a.pos.y, v.kind, v.get_meta(&"spawn_id", ""), Airport.to_local(v.global_position).round(), dd2])
	var to1 := 0
	var la1 := 0
	for f in tr.flights:
		to1 += f.takeoffs
		la1 += f.landings
	print("CRP traffic 120 s: %d flights, kinds seen %s; take-offs %d landings %d; closest pair %.1f m %s" % [tr.flights.size(), seen.keys(), to1 - to0, la1 - la0, minpair, minpair_txt])
