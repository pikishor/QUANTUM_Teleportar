extends RefCounted
## WAVE 126 AIR TRAFFIC, AIR MISSIONS AND AIRCRAFT WEAPONS (w126-air, plan line 126), in the REAL main scene with REAL fingers (InputEventScreenTouch / ScreenDrag through tests/w116_fingers.gd,
## window coordinates, Game.force_touch, the phone-only layers on: CrateReveal._quiet = 0). Nothing the player does is a function call: ENTER, UP, DOWN, FIRE, the arm button (ROCKET / MISSILE /
## BOMB / DROP), ARMS and FLARE are fingers on the drawn buttons, the Mission Board is opened from the pause button and its cards are tapped. The bot PILOT only places the aircraft
## between those presses (the flying itself is covered by the wave 116 and 125 flight tests).
##   TRAFFIC   the roster flies (airliners of the roster on a timetable, light planes, the 23 helicopters, four crossers), take-offs and landings, pooled models, far specks
##   WEAPONS   by class: rockets (gunship, a blast of the table), missiles with LOCK-ON, bombs (jet), flares that pull a homing missile off; the new buttons keep clear of the others and the instruments
##   MISSIONS  the six air missions come up on the board, start from a card tap and are finished by the bot: DOGFIGHT (guns shoot the bandits down), AIRLINER ESCORT, BOMB RUN, CARGO DROP,
##             HELI RESCUE, SKY RINGS
## W126A_OLD=1 switches the wave 126 work off (AirArms.on, AirMissions.on, AirTraffic.roster_on): the checks marked [old fails] fail. AIR_PART=traffic,weapons,missions picks parts.
## This file: TRAFFIC and WEAPONS; tests/test_air_w126_b.gd: the MISSIONS (the same code, the runner's time cap).
## Run: tools/test.sh tests/test_air_w126.gd ; tools/test.sh tests/test_air_w126_b.gd
const TIMEOUT_SECONDS := 140
const Fingers := preload("res://tests/w116_fingers.gd")

var host: Node
var fg: Fingers
var p: Player
var vm: VehicleManager
var hud: Hud
var board: MissionBoard
var old := false


## The runner caps a file at about 140 s: this file runs the traffic and the weapons, tests/test_air_w126_b.gd the six missions (AIR_PART overrides both).
var parts_default := "traffic,weapons"


func default_parts() -> String:
	return parts_default


func _f(n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame


func _until(cond: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) < secs * 1000.0:
		if cond.call():
			return true
		await host.get_tree().physics_frame
	return cond.call()


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _f(3)
	fg.up(6)
	await _f(3)
	return true


func _tap_at(pos: Vector2) -> void:
	fg.down(7, pos)
	await _f(2)
	fg.up(7)
	await _f(3)


func _hud_rect(id: StringName) -> Rect2:
	hud._ensure_layout()
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b["rect"]
	return Rect2()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	old = OS.get_environment("W126A_OLD") == "1"
	AirArms.on = not old
	AirMissions.on = not old
	AirTraffic.roster_on = not old
	TerrainHeight.warm()
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	CrateReveal._quiet = 0
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	hud = host.get_tree().root.find_children("*", "Hud", true, false)[0] as Hud
	board = MissionBoardScreen.board()
	fg = Fingers.new(host)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	TestMode.god = true
	var parts := OS.get_environment("AIR_PART")
	if parts == "":
		parts = default_parts()
	if parts.contains("traffic"):
		await _traffic()
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 2.0
	Engine.max_physics_steps_per_frame = 4
	if parts.contains("weapons"):
		await _weapons()
	if parts.contains("missions"):
		Engine.physics_ticks_per_second = 180
		Engine.time_scale = 3.0
		Engine.max_physics_steps_per_frame = 4
		await _missions()
	fg.up_all()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	AirArms.on = true
	AirMissions.on = true
	AirTraffic.roster_on = true
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


# --- the hero and his aircraft --------------------------------------------------------------------------------------------------------

## Out of the aircraft: the bot pilot sets it down where it is (an EXIT in the air says LAND FIRST), then a finger on EXIT.
func _leave() -> void:
	var v := p.vehicle as Vehicle
	if v == null:
		return
	fg.up_all()
	if v.craft != null and v.craft.airborne:
		var g := _ground_at(v.global_position)
		_place(v, g + Vector3(0.0, 0.3, 0.0), g + v.forward() * 50.0, 0.0)
		v.craft.airborne = false
		v.vel = Vector3.ZERO
		await _until(func() -> bool: return not v.craft.airborne and absf(v.speed) < 2.0, 3.0)
		await _f(6)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == null, 1.5)
	await _f(10)


func _stand_at(at: Vector3, face: Vector3) -> void:
	fg.up_all()
	if p.vehicle != null:
		await _leave()
	p.snake.cancel()
	p.snake.reset()
	var g := TerrainHeight.height_at(at.x, at.z) if (absf(at.x) > TerrainHeight.CITY_HALF or absf(at.z) > TerrainHeight.CITY_HALF) else 0.0
	p.teleport_to(Vector3(at.x, maxf(at.y, g) + 0.3, at.z))
	var d := face - at
	var yaw := atan2(-d.x, -d.z)
	p.camera_rig.reset_view(yaw, -0.1)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await _f(10)


## The hero walks up to `v` with the stick (from 14 m off its side) and taps ENTER with a finger.
func _enter(v: Vehicle) -> bool:
	if v == null:
		return false
	var side := v.right() * (float(v.spec["wid"]) * 0.5 + 9.0)
	var v0 := v.global_position
	await _stand_at(v.global_position + side, v.global_position)
	fg.stick(Vector2(0.0, -0.6))
	var shown := await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER" and v.edge_distance(p.global_position) < VehicleSpecs.ENTER_REACH - 0.6, 8.0)
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == v, 1.5)
	if p.vehicle != v:
		print("DBG enter %s: label '%s' shown %s dist %.1f edge %.1f dy %.1f near %s" % [v.kind, fg.button_label(&"interact"), shown, _flat(p.global_position, v.global_position), v.edge_distance(p.global_position), p.global_position.y - v.global_position.y, vm.nearest(p.global_position, 6.0)])
	return p.vehicle == v


## The bot pilot puts the aircraft at `at`, nose to `face`, flying at `spd` (airborne).
func _place(v: Vehicle, at: Vector3, face: Vector3, spd: float) -> void:
	var d := face - at
	v.global_position = at
	v.heading = atan2(-d.x, -d.z)
	v.rotation.y = v.heading
	v.craft.airborne = true
	v.craft.vy = 0.0
	v.speed = spd
	v.vel = v.forward() * spd
	if v.cls == &"plane":
		v.craft.lever = 0.8 if spd > 1.0 else 0.0
	v.craft.spool = 1.0


func _spawn(kind: StringName, at: Vector3, h: float) -> Vehicle:
	vm._fixed_n += 1
	var v := vm.spawn_parked(kind, at, h)
	if v != null:
		v.set_meta(&"hold", true)
		v.set_meta(&"air_target", true)                                # kept out of the car cap and the streaming while the test needs it
	vm._count_fixed()
	return v


## A hostile aircraft hanging in the air as a target (an AirSteps puppet).
func _puppet(kind: StringName, at: Vector3, hp: float) -> Vehicle:
	vm._fixed_n += 1
	var v := vm.spawn_parked(kind, at, 0.0)
	if v == null:
		vm._count_fixed()
		return null
	v.set_meta(&"air_puppet", true)
	v.set_meta(&"hold", true)
	v.set_meta(&"air_bandit", true)
	vm._count_fixed()
	v.global_position = at
	v.craft.airborne = true
	v.max_hp = hp
	v.hp = hp
	return v


## The ground under `p` (the colliders: the airport's field sits higher than the bare terrain function in places).
func _ground_at(p0: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p0.x, 400.0, p0.z), Vector3(p0.x, -50.0, p0.z), Game.L_WORLD)
	var r := host.get_tree().root.get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		return r["position"]
	return Vector3(p0.x, TerrainHeight.height_at(p0.x, p0.z), p0.z)


func _arms(v: Vehicle) -> AirArms:
	return v.weapons.get("arms") as AirArms if v != null and v.weapons != null else null


# --- TRAFFIC --------------------------------------------------------------------------------------------------------------------------

func _traffic() -> void:
	var at := AirportWorld.instance.traffic if AirportWorld.instance != null else null
	TestLib.check(at != null, "the airport has its air traffic")
	if at == null:
		return
	var kinds := {}
	var crossers := 0
	for f in at.flights:
		kinds[f.kind] = true
		if f.get("cross") == true:
			crossers += 1
	TestLib.check(at.flights.size() >= 11 and crossers >= 4, "[old fails] the traffic has %d flights, %d of them crossers over the outskirts" % [at.flights.size(), crossers])
	at.fast_forward(1500.0)
	var liners := 0
	var liner_ok := 0
	var liner_kinds := {}
	var flown := {}
	for f in at.flights:
		var kf: Variant = f.get("kinds_flown")
		if kf is Dictionary:
			for k: StringName in kf:
				flown[k] = true
		if int(f.get("slot") if f.get("slot") != null else -1) >= 0:
			liners += 1
			if f.takeoffs >= 1 and f.landings >= 1:
				liner_ok += 1
			for k: StringName in (kf as Dictionary):
				liner_kinds[k] = true
	var deps: Variant = at.get("departures")
	TestLib.check(liners >= 2 and liner_ok == liners and deps != null and int(deps) >= 2, "[old fails] the airliners fly the timetable: %d of %d took off and landed, %s departures" % [liner_ok, liners, str(deps)])
	TestLib.check(liner_kinds.size() >= 2, "[old fails] the airliner slots fly the roster's airliners (%s)" % ", ".join(liner_kinds.keys()))
	var heli_new := 0
	var plane_new := 0
	for k: StringName in flown:
		if HeliRoster.NEW.has(k):
			heli_new += 1
		if PlaneRoster.NEW.has(k):
			plane_new += 1
	TestLib.check(heli_new >= 3 and plane_new >= 3, "[old fails] new helicopters (%d kinds) and new planes (%d kinds) crossed the sky in 25 minutes" % [heli_new, plane_new])
	var st := at.stats()
	TestLib.check(float(st["min_clear"]) > 20.0, "no flight went near the ground on its cruise (lowest %.0f m)" % float(st["min_clear"]))
	# pooled models near, specks far: stand at the gates, then 700 m east of the field, then back
	var gate := Airport.to_world(Vector3(1180.0, 0.0, -520.0))
	await _stand_at(gate, Airport.to_world(Vector3(1262.0, 0.0, -520.0)))
	await _f(20)
	var built0 := int(at.get("models_built") if at.get("models_built") != null else 0)
	var near_nodes := 0
	for f in at.flights:
		if f.node != null and is_instance_valid(f.node) and f.node.visible:
			near_nodes += 1
	var far := Airport.to_world(Vector3(1900.0, 0.0, -900.0))
	await _stand_at(far, gate)
	await _f(20)
	var pooled: int = at.call(&"pooled_count") if at.has_method(&"pooled_count") else 0
	var specks: int = at.call(&"speck_count") if at.has_method(&"speck_count") else 0
	TestLib.check(near_nodes >= 2 and pooled >= 1, "[old fails] models near the gates (%d), back in the pool when the hero walks away (%d pooled)" % [near_nodes, pooled])
	TestLib.check(specks >= 1, "[old fails] a far flight is a speck of the shared MultiMesh (%d specks)" % specks)
	await _stand_at(gate, Airport.to_world(Vector3(1262.0, 0.0, -520.0)))
	await _f(20)
	var reused: int = int(at.get("pool_reused")) if at.get("pool_reused") != null else 0
	TestLib.check(reused >= 1, "[old fails] coming back takes the models from the pool (%d reused, %d built before)" % [reused, built0])


# --- WEAPONS --------------------------------------------------------------------------------------------------------------------------

func _weapons() -> void:
	var rw := Airport.to_world(Vector3(Airport.RUNWAY_X, 0.0, -1000.0))
	var gs := _spawn(&"gunship", rw, Airport.heading_world(0.0))
	TestLib.check(gs != null and await _enter(gs), "a finger on ENTER boards the gunship")
	if p.vehicle != gs:
		return
	await _f(6)
	var lab := fg.button_label(&"aim")
	TestLib.check(lab.begins_with("ROCKET ") and lab.substr(7).is_valid_int(), "[old fails] the arm button says what it is and how many: %s" % lab)
	var arms_at := fg.button(&"ammo_type")
	var flare_at := fg.button(&"flare")
	TestLib.check(arms_at != Vector2.INF and flare_at != Vector2.INF, "[old fails] the flight HUD shows ARMS and FLARE")
	await _layout_clear(["aim", "ammo_type", "flare", "fire", "jump", "crouch", "interact", "veh_view"])
	fg.press(1, &"jump")
	var up := await _until(func() -> bool: return VehicleCraft.altitude(gs) > 22.0, 12.0)
	fg.up(1)
	TestLib.check(up, "UP lifts the gunship (%.0f m)" % VehicleCraft.altitude(gs))
	await _f(10)
	# ROCKETS: a car 80 m ahead on the ground, the crosshair on it
	var tp0 := _ground_at(gs.global_position + gs.forward() * 80.0)
	var tgt := _spawn(&"sedan", tp0, gs.heading)
	if tgt != null:
		tgt.global_position.y = tp0.y                                          # on the field's floor (the parked spot came out under it here)
		gs.set_meta(&"aim_at", tgt.global_position + Vector3(0.0, 0.8, 0.0))
	var b0 := int(BlastTable.by_id.get(&"ord_air_rocket", 0))
	var hp0 := tgt.hp if tgt != null else 0.0
	fg.press(2, &"aim")
	await _until(func() -> bool: return gs.weapons.alt_shots >= 2, 3.0)
	fg.up(2)
	var hit := await _until(func() -> bool: return tgt == null or tgt.dead or tgt.hp < hp0 - 40.0, 5.0)
	TestLib.check(hit and int(BlastTable.by_id.get(&"ord_air_rocket", 0)) > b0, "[old fails] a finger on ROCKET: the salvo hits the car with the AIR ROCKET blast of the table (hp %.0f of %.0f, %d blasts)" % [tgt.hp if tgt != null else 0.0, hp0, int(BlastTable.by_id.get(&"ord_air_rocket", 0)) - b0])
	# MISSILE with lock-on: ARMS, then a bandit 220 m ahead in the seeker
	await _tap(&"ammo_type")
	TestLib.check(fg.button_label(&"aim").begins_with("MISSILE") or fg.button_label(&"aim").begins_with("LOCK"), "[old fails] a finger on ARMS picks the missiles (%s)" % fg.button_label(&"aim"))
	var bandit := _puppet(&"plane", gs.global_position + gs.forward() * 220.0 + Vector3(0.0, 6.0, 0.0), 120.0)
	if bandit != null:
		gs.set_meta(&"aim_at", bandit.global_position)
	await _until(func() -> bool: return false, 1.5)                        # the manager's LOD pass runs a few times a second
	TestLib.check(bandit != null and bandit.visible, "[old fails] the bandit 220 m away in the air is drawn (a car is hidden beyond 140 m)")
	var locked := await _until(func() -> bool: return fg.button_label(&"aim").begins_with("LOCKED"), 4.0)
	TestLib.check(bandit != null and locked, "[old fails] the seeker LOCKS on the bandit held in the sights (%s)" % fg.button_label(&"aim"))
	var bhp := bandit.hp if bandit != null else 0.0
	await _tap(&"aim")
	var down := await _until(func() -> bool: return bandit == null or bandit.dead or bandit.hp < bhp - 60.0, 6.0)
	TestLib.check(down, "[old fails] a finger on the locked MISSILE: it homes and hits (hp %.0f of %.0f)" % [bandit.hp if bandit != null else 0.0, bhp])
	# FLARES: a homing missile from the side; first without flares (it hits), then a finger on FLARE (it is pulled off)
	gs.remove_meta(&"aim_at")
	var shooter := _puppet(&"plane", gs.global_position + gs.right() * 160.0 + Vector3(0.0, 10.0, 0.0), 500.0)
	if shooter != null:
		var hp1 := gs.hp
		var dir := (gs.global_position - shooter.global_position).normalized().rotated(Vector3.UP, 0.5)
		AirRockets.launch(shooter, AirSteps.BANDIT_MISSILE, shooter.global_position + dir * 6.0, dir, gs)
		var struck := await _until(func() -> bool: return gs.hp < hp1 - 5.0, 5.0)
		TestLib.check(struck, "a homing missile turns onto the gunship and hits it (hp %.0f -> %.0f)" % [hp1, gs.hp])
		gs.hp = gs.max_hp
		var hp2 := gs.hp
		var dec0 := AirArms.decoyed
		AirRockets.launch(shooter, AirSteps.BANDIT_MISSILE, shooter.global_position + dir * 6.0, dir, gs)
		await _f(4)
		var flared := await _tap(&"flare")
		await _until(func() -> bool: return AirRockets.instance.live_count() == 0, 6.0)
		TestLib.check(flared and AirArms.decoyed > dec0 and gs.hp >= hp2 - 1.0, "[old fails] a finger on FLARE pulls the missile off (decoyed %d, hp %.0f -> %.0f)" % [AirArms.decoyed - dec0, hp2, gs.hp])
	for v: Vehicle in [tgt, bandit, shooter]:
		if is_instance_valid(v) and not v.dead:
			v.remove_meta(&"air_puppet")
			v.remove_meta(&"air_target")
			vm._release(v)
	vm._count_fixed()
	# down by a finger on DOWN, out by EXIT
	fg.press(1, &"crouch")
	await _until(func() -> bool: return not gs.craft.airborne and absf(gs.speed) < 4.0, 15.0)
	fg.up(1)
	await _f(10)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == null, 1.5)
	TestLib.check(p.vehicle == null, "DOWN lands the gunship, EXIT leaves it")
	await _f(20)
	# BOMBS: the jet, ARMS to BOMB, a column of two armoured cars under the predicted fall
	var jet := _spawn(&"jet", rw + Airport.FRAME.basis * Vector3(40.0, 0.0, 0.0), Airport.heading_world(0.0))
	TestLib.check(jet != null and await _enter(jet), "a finger on ENTER boards the jet")
	if p.vehicle != jet:
		return
	var ja := _arms(jet)
	for i in 3:
		if fg.button_label(&"aim").begins_with("BOMB"):
			break
		await _tap(&"ammo_type")
	TestLib.check(fg.button_label(&"aim").begins_with("BOMB"), "[old fails] ARMS reaches the jet's BOMBS (%s)" % fg.button_label(&"aim"))
	var drop_at := _ground_at(jet.global_position + jet.forward() * 300.0)
	var col: Array[Vehicle] = []
	for i in 2:
		var a := _spawn(&"apc", drop_at + jet.right() * (float(i) * 6.0 - 3.0), jet.heading)
		if a != null:
			col.append(a)
	var hp_c := 0.0
	for a in col:
		hp_c += a.hp
	var bombs0 := int(AirRockets.instance.by_look.get(&"bomb", 0)) if AirRockets.instance != null else 0
	await _release_over(jet, ja, &"bomb", drop_at, 110.0, 60.0)
	var boomed := await _until(func() -> bool: return AirRockets.instance != null and int(AirRockets.instance.by_look.get(&"bomb", 0)) > bombs0, 8.0)
	await _f(10)
	var hp_after := 0.0
	for a in col:
		hp_after += a.hp if is_instance_valid(a) and not a.dead else 0.0
	TestLib.check(boomed and hp_after < hp_c - 300.0, "[old fails] a finger on BOMB: the bomb falls on the column (hp %.0f -> %.0f)" % [hp_c, hp_after])
	_place(jet, Vector3(jet.global_position.x, 2.0, jet.global_position.z), jet.global_position + jet.forward() * 100.0, 0.0)
	jet.craft.airborne = false
	await _f(6)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == null, 1.5)
	for a in col:
		if is_instance_valid(a) and not a.dead and a.active:
			a.remove_meta(&"air_target")
			vm._release(a)
	vm._count_fixed()


## The bot pilot holds the aircraft `agl` m over the line to `at` so that the arm's fall ends on `at` (bombs: AirArms.bomb_impact; crates: the chute's drift), and a finger
## held on the arm button releases it there.
func _release_over(v: Vehicle, a: AirArms, arm: StringName, at: Vector3, agl: float, spd: float) -> bool:
	if a == null:
		return false
	var fwd := Vector3(0.0, 0.0, -1.0)
	var n0 := int(a.shots.get(arm, 0))
	_place(v, at + Vector3(0.0, agl, 0.0) - fwd * 200.0, at + Vector3(0.0, agl, 0.0) + fwd * 400.0, spd)
	fg.press(2, &"aim")
	var t0 := Time.get_ticks_msec()
	while int(a.shots.get(arm, 0)) <= n0 and float(Time.get_ticks_msec() - t0) < 3000.0:
		var ip := a.bomb_impact() if arm == &"bomb" else v.global_position + fwd * (spd * 0.8 * 0.8 + pow(spd * 0.8, 2.0) / 12.0)
		var off := Vector3(at.x - ip.x, 0.0, at.z - ip.z) if ip.is_finite() else Vector3.ZERO
		_place(v, v.global_position + off, v.global_position + off + fwd * 400.0, spd)
		await host.get_tree().physics_frame
	fg.up(2)
	await _f(2)
	return int(a.shots.get(arm, 0)) > n0


## The wave 116 view rule for the new buttons: no two buttons on screen overlap, and none covers the flight instruments.
func _layout_clear(actions: Array) -> void:
	var root := host.get_tree().root
	var was := root.size
	for sz: Vector2i in [Vector2i(2400, 1080), Vector2i(844, 390), Vector2i(1024, 768)]:
		root.size = sz
		await _f(3)
		_layout_at(str(sz))
	root.size = was
	await _f(3)


func _layout_at(tag: String) -> void:
	var tc := fg.tc
	var s := tc._scale()
	var discs: Array = []
	for b: Dictionary in TouchControls.BUTTONS:
		if tc.button_visible(b):
			discs.append([str(b["action"]), tc._button_center(b), float(b["r"]) * s * (1.12 if b.get("chip", false) else 1.0)])
	var bad := PackedStringArray()
	for i in discs.size():
		for j in range(i + 1, discs.size()):
			if (discs[i][1] as Vector2).distance_to(discs[j][1]) < float(discs[i][2]) + float(discs[j][2]) - 2.0:
				bad.append("%s/%s" % [discs[i][0], discs[j][0]])
	var vp := fg.vp()
	var ins := UiUtil.insets(vp)
	var irect := FlightHud.instruments_rect(vp, UiUtil.ui_scale(vp), ins)
	for d: Array in discs:
		if d[0] in ["flare", "ammo_type"] and irect.grow(4.0).intersects(Rect2(d[1] - Vector2(d[2], d[2]), Vector2(d[2], d[2]) * 2.0)):
			bad.append("%s over the instruments" % d[0])
	var has := false
	for d: Array in discs:
		has = has or d[0] == "flare"
	TestLib.check(has and bad.is_empty(), "[old fails] %s: the flight buttons (FLARE, ARMS among %d) keep clear of each other and of the instruments %s" % [tag, discs.size(), ", ".join(bad)])


# --- MISSIONS -------------------------------------------------------------------------------------------------------------------------

## Opens the board from the pause button and taps the card of type `t` (NEW OFFERS until it shows). True when the mission runs.
func _board_start(t: StringName) -> bool:
	if board.is_running():
		board.abandon("TEST")
		await _f(4)
	if p.vehicle != null:
		await _leave()
	var ap := WorldSites.airport()
	var last: Vehicle = vm.driven
	await _stand_at(ap["gate"] + Vector3(6.0, 0.0, 6.0), ap["strip"])
	if is_instance_valid(last) and last.active and not last.dead and p.vehicle == null:
		for m: StringName in [&"hold", &"air_target"]:
			if last.has_meta(m):
				last.remove_meta(m)
		vm._release(last)                                               # the last mission's aircraft goes (it was set down on the strip where the next one waits)
	board.world_offers = true
	board.offers.clear()
	await _tap_at(fg.tc._pause_center())
	await _until(func() -> bool: return Game.state == &"paused", 1.0)
	var r := _hud_rect(&"board_open")
	if r.has_area():
		await _tap_at(r.get_center())
	await _until(func() -> bool: return hud._board_open, 1.0)
	if not hud._board_open:
		TestLib.check(false, "the board opens from the pause menu by a finger")
		return false
	var idx := -1
	for tries in 10:
		for i in board.offers.size():
			if StringName(board.offers[i]["type"]) == t:
				idx = i
		if idx >= 0:
			break
		var nr := _hud_rect(&"board_new")
		if not nr.has_area():
			break
		await _tap_at(nr.get_center())
		await _f(2)
	TestLib.check(idx >= 0, "[old fails] the board offers %s at the airport" % AirMissions.DEFS[t]["title"])
	if idx < 0:
		if Game.state == &"paused":
			var br := _hud_rect(&"board_back")
			await _tap_at(br.get_center())
		return false
	var cr := _hud_rect(StringName("board_pick_%d" % idx))
	await _tap_at(cr.get_center())
	await _until(func() -> bool: return board.is_running() and Game.state == &"play", 2.0)
	TestLib.check(board.is_running() and StringName(board.active.get("type", &"")) == t, "a finger on the card starts %s" % AirMissions.DEFS[t]["title"])
	return board.is_running()


func _camp() -> CampaignRunner:
	return board._campaign()


func _step_is(i: int, secs := 4.0) -> bool:
	var k := _camp()
	return await _until(func() -> bool: return k.step_index >= i and k.state == &"active", secs)


## The first step of every air mission: the provided aircraft waits; board it by touch.
func _board_provided() -> Vehicle:
	var k := _camp()
	await _until(func() -> bool: return not k.ws.provided.is_empty(), 4.0)
	if k.ws.provided.is_empty():
		TestLib.check(false, "the mission leaves an aircraft waiting")
		return null
	var v: Vehicle = k.ws.provided[0]
	var ok := await _enter(v)
	await _step_is(1, 4.0)
	TestLib.check(ok and k.step_index >= 1, "%s waits; a finger on ENTER boards it and the mission goes on (%s)" % [VehicleSpecs.name_of(v.kind), k.hud_line()])
	return v if ok else null


func _finished(title: String, done0: int, secs := 6.0) -> void:
	var ok := await _until(func() -> bool: return board.done_count > done0, secs)
	TestLib.check(ok, "[old fails] %s is finished by the bot (done %d -> %d, %s)" % [title, done0, board.done_count, _camp().hud_line()])
	if not ok and board.is_running():
		board.abandon("TEST")
	await _f(4)


func _missions() -> void:
	board.take_over = false
	await _dogfight()
	await _escort()
	await _bomb_run()
	await _cargo()
	await _rescue()
	await _rings()


## Keep the hero's aircraft 110 m behind `b`, nose and guns on it, and hold FIRE.
func _gun_down(v: Vehicle, b: Vehicle, secs: float) -> bool:
	fg.press(2, &"fire")
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(b) and not b.dead and float(Time.get_ticks_msec() - t0) < secs * 1000.0:
		var bp := b.global_position
		var back := b.vel.normalized() if b.vel.length() > 1.0 else Vector3.FORWARD
		_place(v, bp - back * 110.0 + Vector3(0.0, 4.0, 0.0), bp, 50.0)
		v.set_meta(&"aim_at", bp)
		await host.get_tree().physics_frame
	fg.up(2)
	v.remove_meta(&"aim_at")
	return not is_instance_valid(b) or b.dead


func _dogfight() -> void:
	var done0 := board.done_count
	if not await _board_start(&"air_dogfight"):
		return
	var v := await _board_provided()
	if v == null:
		return
	var k := _camp()
	_place(v, k.pos + Vector3(0.0, 0.0, 300.0), k.pos, 55.0)
	await _until(func() -> bool: return not k.air.bandits.is_empty(), 3.0)
	var n := k.air.bandits.size()
	TestLib.check(n >= 2 and k.hud_line().contains("BANDITS"), "the bandits circle over the plain: %s" % k.hud_line())
	var guns0 := v.weapons.hits
	for i in 6:
		if k.air.bandits.is_empty():
			break
		await _gun_down(v, k.air.bandits[0], 8.0)
	TestLib.check(k.air.kills >= n and v.weapons.hits > guns0, "[old fails] a finger held on FIRE: the guns shoot every bandit down (%d of %d, %d hits)" % [k.air.kills, n, v.weapons.hits - guns0])
	await _step_is(2, 3.0)
	_place(v, k.pos + Vector3(0.0, 0.0, 30.0), k.pos, 50.0)
	await _finished("DOGFIGHT", done0)


func _escort() -> void:
	var done0 := board.done_count
	if not await _board_start(&"air_escort"):
		return
	var v := await _board_provided()
	if v == null:
		return
	var k := _camp()
	_place(v, k.pos + Vector3(40.0, 0.0, 40.0), k.pos, 55.0)
	await _step_is(2, 3.0)
	TestLib.check(k.kind == &"air_task" and is_instance_valid(k.air.liner), "the airliner meets the jet: %s" % k.hud_line())
	var t0 := Time.get_ticks_msec()
	while k.kind == &"air_task" and k.state == &"active" and float(Time.get_ticks_msec() - t0) < 70000.0:
		if not k.air.bandits.is_empty():
			await _gun_down(v, k.air.bandits[0], 6.0)
		elif is_instance_valid(k.air.liner):
			var lp := k.air.liner.global_position
			_place(v, lp + k.air.liner.right() * 60.0 + Vector3(0.0, 20.0, 0.0), lp + k.air.liner.forward() * 300.0, 62.0)
		await host.get_tree().physics_frame
	TestLib.check(k.air.wave >= 2 or board.done_count > done0, "two waves of raiders came at the airliner (wave %d)" % k.air.wave)
	await _finished("AIRLINER ESCORT", done0)


func _bomb_run() -> void:
	var done0 := board.done_count
	if not await _board_start(&"air_bomb"):
		return
	var v := await _board_provided()
	if v == null:
		return
	var k := _camp()
	await _until(func() -> bool: return not k.air.targets.is_empty(), 3.0)
	TestLib.check(fg.button_label(&"aim").begins_with("BOMB") and k.air.targets.size() >= 3, "the bomb run arms the BOMBS (%s) and parks the column (%d)" % [fg.button_label(&"aim"), k.air.targets.size()])
	var a := _arms(v)
	for i in 8:
		if k.kind != &"air_task" or k.air.targets.is_empty():
			break
		var tp: Vector3 = k.air.targets[0].global_position
		while a != null and int(a.ammo.get(&"bomb", 0)) <= 0:
			await _f(10)
		await _release_over(v, a, &"bomb", tp, 120.0, 60.0)
		await _until(func() -> bool: return AirRockets.instance.live_count() == 0, 6.0)
		await _f(6)
	TestLib.check(k.step_index >= 2 or board.done_count > done0, "[old fails] fingers on BOMB wreck the column (%d of %d)" % [k.air.kills, k.air.need])
	await _step_is(2, 3.0)
	_place(v, k.pos + Vector3(0.0, 0.0, 30.0), k.pos, 50.0)
	await _finished("BOMB RUN", done0)


func _cargo() -> void:
	var done0 := board.done_count
	if not await _board_start(&"air_cargo"):
		return
	var v := await _board_provided()
	if v == null:
		return
	var k := _camp()
	await _f(4)
	TestLib.check(fg.button_label(&"aim").begins_with("DROP"), "[old fails] the cargo plane's arm is the CARGO DROP (%s)" % fg.button_label(&"aim"))
	var a := _arms(v)
	for i in 3:
		if k.kind != &"air_task" or k.state != &"active":
			break
		while a != null and int(a.ammo.get(&"drop", 0)) <= 0:
			await _f(10)
		var n0 := AirRockets.instance.drops.size() if AirRockets.instance != null else 0
		await _release_over(v, a, &"drop", k.pos, 70.0, 40.0)
		var t0 := Time.get_ticks_msec()
		var hold := v.global_position
		while AirRockets.instance != null and AirRockets.instance.drops.size() <= n0 and float(Time.get_ticks_msec() - t0) < 12000.0:
			_place(v, hold, hold + Vector3(0.0, 0.0, -400.0), 40.0)       # the bot keeps the plane up there while the crate floats down
			await host.get_tree().physics_frame
		await _f(4)
	TestLib.check(k.air.dropped_in >= 1 or board.done_count > done0, "[old fails] a finger on DROP: the crate lands in the ring (%d)" % k.air.dropped_in)
	await _finished("CARGO DROP", done0)


func _rescue() -> void:
	var done0 := board.done_count
	if not await _board_start(&"air_rescue"):
		return
	var v := await _board_provided()
	if v == null:
		return
	var k := _camp()
	_place(v, k.pos + Vector3(0.0, 40.0, 0.0), k.pos + Vector3(0.0, 40.0, -50.0), 0.0)
	await _step_is(2, 3.0)
	TestLib.check(k.kind == &"air_task" and k.hud_line().contains("LAND"), "at the climbers' pad: %s" % k.hud_line())
	_place(v, k.pos + Vector3(0.0, 8.0, 0.0), k.pos + Vector3(0.0, 8.0, -50.0), 0.0)
	fg.press(1, &"crouch")                                                  # DOWN held: it sets down and stays down while the climbers board
	await _until(func() -> bool: return k.step_index >= 3, 25.0)
	fg.up(1)
	TestLib.check(k.step_index >= 3, "[old fails] a finger on DOWN lands it, the climbers board (%s)" % k.hud_line())
	await _until(func() -> bool: return k.step_index >= 3 and k.state == &"active" and k.kind == &"reach", 5.0)
	_place(v, k.pos + Vector3(0.0, 9.0, 0.0), k.pos + Vector3(0.0, 9.0, -50.0), 0.0)
	fg.press(1, &"crouch")
	await _until(func() -> bool: return board.done_count > done0, 25.0)
	fg.up(1)
	await _finished("HELI RESCUE", done0)


func _rings() -> void:
	var done0 := board.done_count
	if not await _board_start(&"air_rings"):
		return
	var v := await _board_provided()
	if v == null:
		return
	var k := _camp()
	var ws := k.ws
	TestLib.check(k.kind == &"gates" and ws.gates.size() >= 8, "the rings hang over the airport (%d)" % ws.gates.size())
	var t0 := Time.get_ticks_msec()
	var from := v.global_position + Vector3(0.0, 60.0, 0.0)
	while k.kind == &"gates" and k.state == &"active" and float(Time.get_ticks_msec() - t0) < 30000.0:
		if ws.gi >= ws.gates.size():
			break
		var g := ws.gates[ws.gi]
		var d := g - from
		var stp := minf(d.length(), 18.0)
		from += d.normalized() * stp if d.length() > 0.01 else Vector3.ZERO
		_place(v, from, from + d, 55.0)
		await host.get_tree().physics_frame
	await _finished("SKY RINGS", done0)
