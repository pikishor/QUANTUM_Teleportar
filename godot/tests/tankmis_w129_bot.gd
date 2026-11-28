extends RefCounted
## w129-tankmis, OWNER REQUEST "TANK MISSIONS MUST FINISH BY NORMAL PLAY". A finger-only bot plays the TANK MISSIONS of the Mission Board to their normal end with the guide's stuck
## recovery SWITCHED OFF (MissionGuide.auto_recover = false: no SKIP STEP, no self-recovery). Real scene (main.tscn), Game.force_touch, the phone-only layers on (CrateReveal._quiet = 0),
## REAL finger events only (tests/w116_fingers.gd: InputEventScreenTouch / InputEventScreenDrag through Input.parse_input_event in window coordinates): the board opens by a tap on PAUSE
## and on MISSIONS, the card by a tap, the hero walks to the provided vehicle with the left thumb and taps ENTER, drives with the left thumb, aims with right-thumb swipes and shoots with
## a finger on FIRE. The only set-up that is not a finger: the hero is put at the ARMY YARD gate before each mission (the yard is where the board starts them).
## THE BOT (not a test by itself; the runner allows 140 s per file, so each mission has its own file): tests/test_tankmis_w129.gd TANK BATTLE (and the step that waits while the hero is
## out of the tank), tests/test_tankmis_w129_b.gd CONVOY ESCORT, tests/test_tankmis_w129_c.gd ARTILLERY STRIKE.
## Every check marked [old fails] fails with W129TM_OLD=1 (the wave 127 missions: fields 1.5 - 3.5 km away, crews that wait at the field, puppet trucks on straight lines).
## Run: tools/test.sh tests/test_tankmis_w129.gd (and _b, _c)
const Fingers := preload("res://tests/w116_fingers.gd")
var mission: StringName = &"tank_battle"
var budget := 240.0                       ## game seconds a finger player may need from the card to the end (a few minutes)

var host: Node
var fg: Fingers
var p: Player
var vm: VehicleManager
var hud: Hud
var board: MissionBoard
var _t := 0.0
var _k := 0.0
var old := OS.get_environment("W129TM_OLD") == "1"


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


func _wait(secs: float) -> void:
	await _until(func() -> bool: return false, secs)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _tap(action: StringName) -> bool:
	if not fg.press(6, action):
		return false
	await _f(4)
	fg.up(6)
	await _f(3)
	return true


func _tap_at(pos: Vector2) -> void:
	fg.down(7, pos)
	await _f(2)
	fg.up(7)
	await _f(3)


func run(h: Node) -> void:
	host = h
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	Game.force_touch = true
	host.get_tree().root.size = Vector2i(1200, 540)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await _f(20)
	Game.state = &"play"
	CrateReveal._quiet = 0
	MissionGuide.auto_recover = false
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	fg = Fingers.new(host)
	var mgr := Game.enemies as EnemyManager
	mgr.patrol_groups().clear()
	mgr.clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 3.0
	Engine.max_physics_steps_per_frame = 8
	hud = host.get_tree().root.find_children("*", "Hud", true, false)[0] as Hud
	board = MissionBoardScreen.board()
	board.take_over = false
	await play(mission)
	await after(mission)
	fg.up_all()
	MissionGuide.auto_recover = true
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


# --- the mission ----------------------------------------------------------------------------------------------------------------------

var ride: Vehicle = null
var task_start := Vector3.INF             ## where the hero was when the fight step began
var task_in_tank := false
var task_t0 := 0.0
var notes := {}


func play(t: StringName) -> void:
	var done0 := board.done_count
	var t0 := _t
	TestLib.check(await _board_start(t), "%s: the card is offered at the ARMY YARD and starts by a finger" % t)
	if not board.is_running():
		return
	var k := _camp()
	var guide := k.guide
	var rec0 := guide.recoveries if guide != null else 0
	var skip0 := guide.skips if guide != null else 0
	var fails := 0
	var guard := 0
	while board.is_running() and _t - t0 < budget and guard < 12:
		guard += 1
		await _until(func() -> bool: return k.state == &"active" or not board.is_running(), 10.0)
		if not board.is_running():
			break
		if k.state != &"active":
			fails += 1
			continue
		var st: Dictionary = k.step
		var idx := k.step_index
		print("STEP %d %s: %s  hud '%s'  goal %s  %d m from the hero" % [idx, st.get("kind"), st.get("text"), k.hud_line(), k.pos, roundi(_flat(k.pos, p.global_position))])
		if st.get("kind") == "reach" and st.has("provide"):
			await _board_provided(k)
		elif st.get("kind") == "reach":
			await _drive_reach(k, t0)
		elif st.get("kind") == "tank_task":
			task_start = p.global_position
			task_in_tank = p.vehicle != null and p.vehicle == ride
			task_t0 = _t
			print("TASK BEGINS: hero in %s, provided %s, step ride %s" % [p.vehicle, ride, k.tank.ride])
			await _task(k, t0)
		await _until(func() -> bool: return k.step_index != idx or not board.is_running(), 3.0)
	var took := _t - t0
	var finished := board.done_count > done0
	print("MISSION %s: finished %s in %.0f game s (state %s, hud '%s', recoveries %d, skips %d, fails %d)" % [t, finished, took, k.state, k.hud_line(), (guide.recoveries - rec0) if guide else -1, (guide.skips - skip0) if guide else -1, fails])
	TestLib.check(task_start.is_finite() and _flat(task_start, ArmourSites.YARD) < 120.0, "[old fails] %s: the fight step begins at the yard, not across the city (%d m from it)" % [t, roundi(_flat(task_start, ArmourSites.YARD)) if task_start.is_finite() else -1])
	TestLib.check(task_in_tank, "%s: the fight step begins with the hero in the provided vehicle" % t)
	TestLib.check(finished, "[old fails] %s: a finger player finishes it by normal play in %.0f game s (budget %.0f; state %s)" % [t, took, budget, k.state])
	TestLib.check(guide == null or (guide.recoveries == rec0 and guide.skips == skip0), "%s: no step was skipped or recovered (recovery switched off)" % t)
	check_extra(t, k)
	if board.is_running():
		board.abandon("TEST")
	await _f(4)


## After the mission, the focused checks of each file. Battle: the tank's gun sight stays where the thumb laid it.
func after(_t0: StringName) -> void:
	var v := await _own_tank(&"tank")
	if v == null:
		TestLib.check(false, "GUN SIGHT: a tank to sit in")
		return
	# lay the sight 0.6 rad off the hull nose on a point 120 m away, lift the thumb and wait well past the free-look time
	var h := v.heading + 0.6
	var pt := v.global_position + Vector3(-sin(h), 0.0, -cos(h)) * 120.0 + Vector3(0.0, 3.0, 0.0)
	await _aim_finger(pt, 0.01)
	var yp0 := _cam_yp()
	await _wait(CameraRig.FREE_LOOK_TIME * 3.0)
	var yp1 := _cam_yp()
	var drift := absf(wrapf(yp1.x - yp0.x, -PI, PI)) + absf(yp1.y - yp0.y)
	var ad := v.aim_dir()
	var terr := absf(wrapf(atan2(-ad.x, -ad.z) - yp0.x, -PI, PI))
	print("SIGHT: drift %.3f rad, turret off the laid sight %.3f rad" % [drift, terr])
	TestLib.check(drift < 0.03 and terr < 0.06, "[old fails] GUN SIGHT: in a standing tank the view (and the turret) stays where the thumb laid it %.1f s after the swipe (drift %.3f rad, turret %.3f rad)" % [CameraRig.FREE_LOOK_TIME * 3.0, drift, terr])


## A parked vehicle of `kind` beside the yard gate that the hero boards by finger (for the focused checks after a mission).
func _own_tank(kind: StringName) -> Vehicle:
	if p.vehicle != null:
		await _tap(&"interact")
		await _f(10)
	var at := Vector3(-160.0, 0.0, -84.0)
	vm._fixed_n += 1
	var v := vm.spawn_parked(kind, at, -PI * 0.5 + PI)                      # nose west, down the street
	vm._count_fixed()
	if v == null:
		return null
	v.set_meta(&"hold", true)
	v.global_position = at
	await _f(4)
	return v if await _board(v) else null


## Per-mission checks of the subclass files (notes filled while it played).
func check_extra(_t0: StringName, _k0: CampaignRunner) -> void:
	TestLib.check(bool(notes.get("came", false)), "[old fails] TANK BATTLE: the enemy tanks come down the street to the hero waiting at the yard (closest %s m)" % str(notes.get("closest", "?")))
	TestLib.check(bool(notes.get("waited", false)), "[old fails] TANK BATTLE: out of the tank the step waits: the crews hold still and the HUD says GET BACK IN THE TANK ('%s', crew moved %s m)" % [str(notes.get("wait_hud", "")), str(notes.get("wait_move", "?"))])
	TestLib.check(bool(notes.get("reboarded", false)), "TANK BATTLE: a finger on ENTER puts the hero back in his tank and the fight goes on")


func _board_provided(k: CampaignRunner) -> void:
	await _until(func() -> bool: return not k.ws.provided.is_empty(), 4.0)
	var v: Vehicle = k.ws.provided[0] if not k.ws.provided.is_empty() else null
	if v == null:
		print("no vehicle provided")
		return
	ride = v
	var idx := k.step_index
	await _board(v)
	await _until(func() -> bool: return k.step_index > idx, 4.0)
	print("BOARDED: hero in %s (%s), provided %s, step %d" % [p.vehicle, p.vehicle.kind if p.vehicle else "-", v, k.step_index])
	# out of the bay, nose first onto the street
	if p.vehicle == v:
		await _drive_to(v, v.global_position + v.forward() * 24.0, 4.0, 10.0)


func _drive_reach(k: CampaignRunner, t0: float) -> void:
	var v := p.vehicle
	if v == null:
		return
	await _drive_to(v, k.pos, float(k.step.get("radius", 14.0)) * 0.6, budget - (_t - t0))


## The fight. Battle: wait at the yard gate facing west for the crews to come, check that they do, step out once (the step waits), get back in by finger, then shoot them.
func _task(k: CampaignRunner, t0: float) -> void:
	if mission == &"tank_convoy":
		await _task_convoy(k, t0)
		return
	if mission == &"tank_artillery":
		await _task_art(k, t0)
		return
	var tk := k.tank
	var v := ride
	var d0 := _closest(tk.enemies, v.global_position)
	await _turn_to(v, Vector3(-1.0, 0.0, 0.0))
	# they come: measured over 30 s while the hero waits at the gate
	await _until(func() -> bool: return _closest(tk.enemies, v.global_position) < 150.0, 30.0)
	var d1 := _closest(tk.enemies, v.global_position)
	notes["closest"] = roundi(d1)
	notes["came"] = d1 < d0 - 60.0 and d1 < 160.0
	print("CREWS: closest %d m -> %d m in the wait" % [roundi(d0), roundi(d1)])
	# out of the tank: the step waits
	if await _tap(&"interact"):
		await _until(func() -> bool: return p.vehicle == null, 2.0)
		await _wait(1.0)
		var pos0: Array[Vector3] = []
		for e in tk.enemies:
			pos0.append(e.global_position)
		await _wait(6.0)
		var moved := 0.0
		for i in mini(pos0.size(), tk.enemies.size()):
			if is_instance_valid(tk.enemies[i]):
				moved = maxf(moved, _flat(tk.enemies[i].global_position, pos0[i]))
		var line := k.hud_line()
		notes["wait_hud"] = line
		notes["wait_move"] = snappedf(moved, 0.1)
		notes["waited"] = p.vehicle == null and moved < 1.5 and line.contains("GET BACK IN THE TANK") and _flat(k.pos, v.global_position) < 3.0
		notes["reboarded"] = await _board(v)
		print("WAIT: hud '%s' moved %.1f m; back in %s (tank hp %.0f hold %s)" % [line, moved, notes["reboarded"], v.hp, v.has_meta(&"hold")])
	await _fight(k, v, t0)


func _closest(list: Array[Vehicle], at: Vector3) -> float:
	var best := 99999.0
	for e in list:
		if is_instance_valid(e):
			best = minf(best, _flat(e.global_position, at))
	return best


## Shoot every enemy / target of the step until it ends: aim with right-thumb swipes, wait for the turret, a finger on FIRE.
func _fight(k: CampaignRunner, v: Vehicle, t0: float) -> void:
	var tk := k.tank
	while k.kind == &"tank_task" and k.state == &"active" and _t - t0 < budget:
		if not is_instance_valid(v) or v.dead:
			print("FIGHT: the tank is gone (hero hp %.0f)" % p.hp)
			return
		if p.vehicle != v:
			await _board(v)
			continue
		var tgt: Vehicle = null
		var bd := INF
		for e in (tk.enemies + tk.targets):
			if is_instance_valid(e) and not e.dead:
				var d := _flat(e.global_position, v.global_position)
				if d < bd:
					bd = d
					tgt = e
		if tgt == null:
			if not tk.trucks.is_empty():
				await escort(k, v)
			else:
				await _wait(0.5)
			continue
		var rng := float(v.weapons.def.get("range", 200.0)) if v.weapons != null else 200.0
		var indirect := v.weapons != null and bool(v.weapons.def.get("indirect", false))
		if bd > (rng * 0.9 if indirect else minf(rng * 0.9, 300.0)):
			if not tk.trucks.is_empty():
				await escort(k, v)
			else:
				await _wait(0.5)
			continue
		await shoot(v, tgt)


## What stands in the line of fire from the gun to `tgt`: null when it is clear (or only the target itself).
func _blocker(v: Vehicle, tgt: Vehicle) -> Object:
	var q := PhysicsRayQueryParameters3D.create(VehicleCraft.muzzle_origin(v), tgt.global_position + Vector3(0.0, 1.2, 0.0), Game.L_WORLD | Game.L_VEHICLE)
	q.exclude = [v.get_rid(), tgt.get_rid()]
	var r := v.get_world_3d().direct_space_state.intersect_ray(q)
	return null if r.is_empty() else r["collider"]


func _los(v: Vehicle, tgt: Vehicle) -> bool:
	return _blocker(v, tgt) == null


## No line of fire: drive round the block towards it (along the streets, as a player follows the road), a couple of seconds at a time.
func close_in(v: Vehicle, tgt: Vehicle) -> void:
	var goal := TankCrews.road_goal(v.global_position, tgt.global_position, v.get_world_3d().direct_space_state, [v.get_rid()])
	await _drive_to(v, goal, 6.0, 2.5)


func shoot(v: Vehicle, tgt: Vehicle) -> void:
	var b := _blocker(v, tgt) if not bool(v.weapons.def.get("indirect", false)) else null
	if b is Vehicle:                                                         # a convoy truck (or a car) in the line of fire: pull out to the side, never shoot through it
		var d := (tgt.global_position - v.global_position).normalized()
		var side := Vector3(-d.z, 0.0, d.x)
		var sgn := -signf(((b as Vehicle).global_position - v.global_position).dot(side))
		await _drive_to(v, v.global_position + d * 8.0 + side * (sgn if sgn != 0.0 else 1.0) * 8.0, 3.0, 2.5)
		return
	if b != null:
		await close_in(v, tgt)
		return
	var aim_pt := tgt.global_position + Vector3(0.0, 1.0, 0.0)
	var aimed := await _aim_finger(aim_pt, 0.012)
	var hp0 := tgt.hp
	var mz := VehicleCraft.muzzle_origin(v)
	var lob := bool(v.weapons.def.get("indirect", false))                   # the howitzer lobs: its marker (TankArms.marker_point) must sit on the target, the barrel points up
	await _until(func() -> bool: return not is_instance_valid(tgt) or (v.weapons.can_fire() and (_flat(TankArms.marker_point(v), tgt.global_position) < 3.0 if lob else (aim_pt - mz).normalized().angle_to(v.aim_dir()) < 0.03)), 5.0)
	if not is_instance_valid(tgt):
		return
	var s0 := v.weapons.shots
	if fg.press(2, &"fire"):
		await _until(func() -> bool: return v.weapons.shots > s0, 1.5)
		fg.up(2)
	await _wait(2.4 if bool(v.weapons.def.get("indirect", false)) else 0.5)
	print("SHOT %s %d m: aimed %s turret err %.3f fired %s hp %.0f -> %s" % [tgt.kind if is_instance_valid(tgt) else "?", roundi(_flat(v.global_position, aim_pt)), aimed, (aim_pt - VehicleCraft.muzzle_origin(v)).normalized().angle_to(v.aim_dir()), v.weapons.shots > s0, hp0, str(roundi(tgt.hp)) if is_instance_valid(tgt) else "gone"])


# --- convoy (tests/test_tankmis_w129_b.gd checks what this records) ---------------------------------------------------------------

var off_road := 0.0                       ## the farthest a truck was from a city road (m)
var order_ok := true
var lead_turn := 0.0                      ## how far the lead truck turned (rad)
var waited := false
var samples := 0
var driven := true


func _road_off(q: Vector3) -> float:
	var ox := absf(CityLayout.road_offset(q.x))
	var oz := absf(CityLayout.road_offset(q.z))
	return maxf(minf(ox, oz) - CityLayout.ROAD * 0.5, 0.0) if absf(q.x) < CityLayout.HALF and absf(q.z) < CityLayout.HALF else 999.0


func _task_convoy(k: CampaignRunner, t0: float) -> void:
	var tk := k.tank
	var v := ride
	var h0 := tk.trucks[0].heading if not tk.trucks.is_empty() else 0.0
	var p0 := tk.trucks[0].global_position if not tk.trucks.is_empty() else Vector3.ZERO
	await _wait(3.0)
	waited = not tk.trucks.is_empty() and _flat(tk.trucks[0].global_position, p0) < 1.0 and _flat(v.global_position, p0) > 50.0
	print("CONVOY: %d trucks (%s), escort %d m away, lead moved %.1f m while it waited" % [tk.trucks.size(), tk.trucks[0].kind if not tk.trucks.is_empty() else "-", roundi(_flat(v.global_position, p0)), _flat(tk.trucks[0].global_position, p0) if not tk.trucks.is_empty() else -1.0])
	var last_log := 0.0
	while k.kind == &"tank_task" and k.state == &"active" and _t - t0 < budget:
		_sample(tk, h0)
		if _t - last_log > 8.0:
			last_log = _t
			var ed := []
			for e in tk.enemies:
				if is_instance_valid(e):
					ed.append(roundi(_flat(e.global_position, v.global_position)))
			print("  t %.0f: ts %s, trucks %s, hero %s (%d m to lead), halted %s joined %s wave %d enemies %s speed %s" % [_t - t0, tk._ts, tk.trucks.map(func(x: Vehicle) -> Vector3: return x.global_position.snapped(Vector3.ONE)), v.global_position.snapped(Vector3.ONE), roundi(_flat(v.global_position, tk.trucks[0].global_position)) if not tk.trucks.is_empty() else -1, tk.halted, tk.joined, tk.wave, ed, tk.trucks.map(func(x: Vehicle) -> float: return snappedf(x.speed, 0.1))])
		if not is_instance_valid(v) or v.dead or p.vehicle != v:
			print("CONVOY: the hero is out of his tank")
			return
		var tgt: Vehicle = null
		var bd := INF
		for e in tk.enemies:
			if is_instance_valid(e) and not e.dead:
				var d := _flat(e.global_position, v.global_position)
				if d < bd:
					bd = d
					tgt = e
		if tgt != null and bd < 190.0:
			await shoot(v, tgt)
			continue
		await escort(k, v)
	_sample(tk, h0)


func _sample(tk: TankSteps, h0: float) -> void:
	if tk.trucks.is_empty():
		return
	samples += 1
	for i in tk.trucks.size():
		var t := tk.trucks[i]
		if not is_instance_valid(t):
			continue
		off_road = maxf(off_road, _road_off(t.global_position))
		driven = driven and t.scripted
	if tk._ts.size() >= 2:
		for i in range(1, mini(tk._ts.size(), tk.trucks.size())):
			if tk._ts[i] > tk._ts[i - 1] - 4.0:
				order_ok = false
	elif tk.trucks.size() >= 2:
		order_ok = false                                                     # the old puppets have no road order to read
	lead_turn = maxf(lead_turn, absf(wrapf(tk.trucks[0].heading - h0, -PI, PI)))


## Keep 20 m behind the rear truck on its road (the left thumb), never in front of the convoy.
func escort(k: CampaignRunner, v: Vehicle) -> void:
	var tk := k.tank
	if tk.trucks.is_empty():
		await _wait(0.5)
		return
	var goal: Vector3
	if not tk.road.is_empty() and not tk._ts.is_empty():
		goal = tk._road_at(tk._ts[tk._ts.size() - 1] - 20.0)
	else:
		var rear := tk.trucks[tk.trucks.size() - 1]
		goal = rear.global_position - rear.forward() * 20.0
	if _flat(v.global_position, goal) < 8.0:
		await _wait(0.4)
		return
	await _drive_to(v, goal, 6.0, 2.0)



# --- artillery (tests/test_tankmis_w129_c.gd) ------------------------------------------------------------------------------------

var fire_from := Vector3.INF
var max_off := 0.0


func _task_art(k: CampaignRunner, t0: float) -> void:
	var v := ride
	fire_from = v.global_position
	await _turn_to(v, Vector3(-1.0, 0.0, 0.0))
	await _fight(k, v, t0)
	max_off = _flat(v.global_position, fire_from) if is_instance_valid(v) else 999.0



# --- fingers --------------------------------------------------------------------------------------------------------------------------

func _hud_rect(id: StringName) -> Rect2:
	hud._ensure_layout()
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b["rect"]
	return Rect2()


func _camp() -> CampaignRunner:
	return board._campaign()


func _board_start(t: StringName) -> bool:
	if board.is_running():
		board.abandon("TEST")
		await _f(4)
	await _place_hero(ArmourSites.YARD + Vector3(0.0, 0.0, 12.0), ArmourSites.YARD)
	board.world_offers = true
	board.offers.clear()
	await _tap_at(fg.tc._pause_center())
	await _until(func() -> bool: return Game.state == &"paused", 1.0)
	var r := _hud_rect(&"board_open")
	if r.has_area():
		await _tap_at(r.get_center())
	await _until(func() -> bool: return hud._board_open, 1.0)
	if not hud._board_open:
		print("board did not open")
		return false
	var idx := -1
	for tries in 12:
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
	if idx < 0:
		print("%s not offered" % t)
		return false
	await _tap_at(_hud_rect(StringName("board_pick_%d" % idx)).get_center())
	await _until(func() -> bool: return board.is_running() and Game.state == &"play", 2.0)
	return board.is_running()


func _place_hero(stand: Vector3, at: Vector3) -> void:
	if p.vehicle != null:
		await _tap(&"interact")
		await _f(10)
	fg.up_all()
	var d := at - stand
	var yaw := atan2(-d.x, -d.z)
	p.snake.cancel()
	p.snake.reset()
	p.teleport_to(stand + Vector3(0.0, 0.4, 0.0))
	p.camera_rig.reset_view(yaw, -0.1)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await _f(12)


## Stand beside `v` and walk to it with the left thumb, ENTER by a finger; tries the sides in turn (west side first: in the yard the light tank stands in the next bay east).
func _board(v: Vehicle) -> bool:
	for side in [-v.right(), -v.forward(), v.right(), v.forward()]:
		var at: Vector3 = v.global_position + (side as Vector3) * (float(v.spec["wid"]) * 0.5 + 4.0)
		await _place_hero(at, v.global_position)
		if await _walk_board(v):
			return true
		print("BOARD: not from %s (label '%s', hero in %s, hp %.0f)" % [at, fg.button_label(&"interact"), p.vehicle, p.hp])
	return false


func _walk_board(v: Vehicle) -> bool:
	fg.stick(Vector2(0.0, -1.0))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER", 10.0)
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle != null, 1.5)
	return p.vehicle == v


func _cam_yp() -> Vector2:
	var cf := -p.camera_rig.camera.global_basis.z
	return Vector2(atan2(-cf.x, -cf.z), asin(clampf(cf.y, -1.0, 1.0)))


## The right thumb puts the crosshair on `pt` (closed loop of swipes). True when within `tol` rad.
func _aim_finger(pt: Vector3, tol := 0.02, tries := 12) -> bool:
	if _k == 0.0:
		var a := _cam_yp()
		fg.look(200.0, 0.0)
		await _f(4)
		var b := _cam_yp()
		var d := wrapf(b.x - a.x, -PI, PI)
		_k = -200.0 / d if absf(d) > 0.01 else -500.0
	for i in tries:
		var cam := p.camera_rig.camera.global_position
		var d3 := pt - cam
		var want := Vector2(atan2(-d3.x, -d3.z), atan2(d3.y, Vector2(d3.x, d3.z).length()))
		var now := _cam_yp()
		var e := Vector2(wrapf(want.x - now.x, -PI, PI), want.y - now.y)
		if absf(e.x) < tol and absf(e.y) < tol * 2.0:
			return true
		fg.look(clampf(-e.x * _k, -500.0, 500.0), clampf(-e.y * absf(_k), -300.0, 300.0), 4)
		await _f(3)
	return false


## Turn the hull on the spot (left thumb sideways) until it faces `dir`.
func _turn_to(v: Vehicle, dir: Vector3) -> void:
	var want := atan2(-dir.x, -dir.z)
	var t0 := _t
	while _t - t0 < 8.0 and p.vehicle == v:
		var e := wrapf(want - v.heading, -PI, PI)
		if absf(e) < 0.08:
			break
		fg.stick(Vector2(clampf(-e * 1.5, -1.0, 1.0), -0.15))
		await _step()
	fg.stick(Vector2.ZERO)
	await _wait(0.4)


## The left thumb drives vehicle v to `goal` (within `rad`), steering by the heading error; backs off when stuck. Returns the metres left.
func _drive_to(v: Vehicle, goal: Vector3, rad: float, secs: float, speed := 1.0) -> float:
	var t0 := _t
	var last_pos := v.global_position
	var last_t := _t
	while _t - t0 < secs and _flat(v.global_position, goal) > rad and p.vehicle == v:
		var d := goal - v.global_position
		var e := wrapf(atan2(-d.x, -d.z) - v.heading, -PI, PI)
		fg.stick(Vector2(clampf(-e * 1.5, -1.0, 1.0), (-1.0 if absf(e) < 1.2 else -0.4) * speed))
		await _step()
		if _t - last_t > 3.0:
			if _flat(v.global_position, last_pos) < 2.0:
				fg.stick(Vector2(clampf(e, -1.0, 1.0), 1.0))
				await _wait(1.5)
			last_pos = v.global_position
			last_t = _t
	fg.stick(Vector2.ZERO)
	return _flat(v.global_position, goal)
