extends RefCounted
## WAVE 127 VEHICLE WEAPONS, ARMOUR AND TANK COMBAT (w127-arms, plan line 127), in the REAL main scene with REAL fingers (InputEventScreenTouch / ScreenDrag through tests/w116_fingers.gd,
## window coordinates, Game.force_touch, the phone-only layers on: CrateReveal._quiet = 0). ENTER, FIRE, the arm button (COAX / HMG / ATGM / SALVO / MISSILE), ARMS, SHELL, SMOKE and the
## look drag that turns the turret are fingers on the drawn buttons; the Mission Board is opened from the pause button and its cards are tapped. The bot only PLACES the vehicles and holds the
## crosshair on a target (the meta `aim_at`, as the wave 126 air checks do) between those presses.
##   WEAPONS   every weapon kind fires and hits: the cannon's AP and HE shells (blast table), the coax and roof machine guns, the ATGM with lock-on, the howitzer on its target marker,
##             the rocket salvo, the flak cannon and the seeker missile on an aircraft, the carrier's autocannon, smoke; the turret follows the camera; the buttons keep clear of each other
##   ARMOUR    hit zones (front / side / rear / turret / tracks: a rear round hurts more than a front one), a broken track stops a tank, a damaged one slows it, an engine fire burns
##   CREWS     an enemy tank crew drives up, fires at the hero's tank and is destroyed by it; the ARMY AIRBASE crew; a tank comes at 4 stars
##   MISSIONS  TANK BATTLE, CONVOY ESCORT and ARTILLERY STRIKE come up on the board in the ARMY YARD, start from a card tap and are finished by the bot
## W127A_OLD=1 switches the wave 127 work off (TankArms.on, TankArmour.on, TankCrews.on, TankMissions.on): the checks marked [old fails] fail. TANK_PART=weapons,crews,missions picks parts.
## This file: WEAPONS and ARMOUR; tests/test_tank_arms_w127_b.gd: CREWS and TANK BATTLE; tests/test_tank_arms_w127_c.gd: CONVOY ESCORT and ARTILLERY STRIKE (the same code, the runner's
## time cap of 140 s a file).
## Run: tools/test.sh tests/test_tank_arms_w127.gd ; tools/test.sh tests/test_tank_arms_w127_b.gd ; tools/test.sh tests/test_tank_arms_w127_c.gd
const TIMEOUT_SECONDS := 140
const Fingers := preload("res://tests/w116_fingers.gd")

var host: Node
var fg: Fingers
var p: Player
var vm: VehicleManager
var hud: Hud
var board: MissionBoard
var old := false
var parts_default := "weapons"
var field := Vector3.ZERO                ## an open stretch of the outskirts (found at the start: 260 m of clear, level line from it)
var hdg := 0.0                           ## the heading along that line


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


func _hold(action: StringName, secs: float, cond: Callable) -> bool:
	if not fg.press(2, action):
		return false
	var ok := await _until(cond, secs)
	fg.up(2)
	await _f(2)
	return ok


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
	old = OS.get_environment("W127A_OLD") == "1"
	_switch(not old)
	TerrainHeight.warm()
	host.get_tree().root.size = Vector2i(1200, 540)                       # a phone's shape (2.2 : 1), not the runner's square window
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
	var parts := OS.get_environment("TANK_PART")
	if parts == "":
		parts = parts_default
	if parts.contains("weapons") or parts.contains("crews"):
		await _find_ground()
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 2.0
	Engine.max_physics_steps_per_frame = 4
	if parts.contains("weapons"):
		await _weapons()
		await _armour()
	if parts.contains("crews"):
		await _crews()
	if parts.contains("missions") or parts.contains("battle") or parts.contains("convoy") or parts.contains("artillery"):
		Engine.physics_ticks_per_second = 180
		Engine.time_scale = 3.0
		board.take_over = false
		if parts.contains("missions") or parts.contains("battle"):
			await _battle()
		if parts.contains("missions") or parts.contains("convoy"):
			await _convoy()
		if parts.contains("missions") or parts.contains("artillery"):
			await _artillery_strike()
	fg.up_all()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
	_switch(true)
	Game.heat = 0.0
	CrateReveal._quiet = -1
	Game.state = &"menu"
	Game.force_touch = false
	main.queue_free()
	await _f(2)


func _switch(on: bool) -> void:
	TankArms.on = on
	TankArmour.on = on
	TankCrews.on = on
	TankMissions.on = on


# --- the hero and his vehicles ---------------------------------------------------------------------------------------------------------

func _leave() -> void:
	if p.vehicle == null:
		return
	fg.up_all()
	(p.vehicle as Vehicle).vel = Vector3.ZERO
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == null, 1.5)
	await _f(8)


func _stand_at(at: Vector3, face: Vector3) -> void:
	fg.up_all()
	if p.vehicle != null:
		await _leave()
	p.snake.cancel()
	p.snake.reset()
	var g := _ground_at(at)
	p.teleport_to(Vector3(at.x, g.y + 0.3, at.z))
	var d := face - at
	var yaw := atan2(-d.x, -d.z)
	p.camera_rig.reset_view(yaw, -0.1)
	p.yaw = yaw
	p.velocity = Vector3.ZERO
	await _f(10)


## The hero walks up to `v` with the stick (from 9 m off its side) and taps ENTER.
func _enter(v: Vehicle) -> bool:
	if v == null:
		return false
	var best := v.global_position + v.right() * (float(v.spec["wid"]) * 0.5 + 8.0)
	var bd := -1.0
	for dirv: Vector3 in [v.forward() * (float(v.spec["len"]) * 0.5 + 8.0), v.right() * (float(v.spec["wid"]) * 0.5 + 8.0), -v.right() * (float(v.spec["wid"]) * 0.5 + 8.0), -v.forward() * (float(v.spec["len"]) * 0.5 + 8.0)]:
		var c: Vector3 = v.global_position + dirv
		var near := 1.0e9
		for o: Vehicle in vm.list:
			if o != v and o.active and not o.dead:
				near = minf(near, minf(_flat(o.global_position, c), _flat(o.global_position, (c + v.global_position) * 0.5)))
		if near > bd:
			bd = near
			best = c
		if near > 9.0:
			break                                                             # the nose first (the yard's tanks face the open road), then the flanks
	await _stand_at(best, v.global_position)                              # from the side with no other vehicle on the way (the yard's bays stand 8 m apart)
	fg.stick(Vector2(0.0, -0.6))
	await _until(func() -> bool: return fg.button_label(&"interact") == "ENTER" and v.edge_distance(p.global_position) < VehicleSpecs.ENTER_REACH - 0.6, 8.0)
	fg.stick(Vector2.ZERO)
	await _f(3)
	await _tap(&"interact")
	await _until(func() -> bool: return p.vehicle == v, 1.5)
	return p.vehicle == v


## The test ground: next to a landing field of the outskirts, a heading along which 260 m (and 180 m behind) are level and free of buildings and vehicles (the colliders stream in
## around the hero, so he is put there first). The runway is not used: aircraft taxi and park on it.
func _find_ground() -> void:
	var fields := WorldSites.landing_fields()
	for f: Dictionary in fields:
		for k in 8:
			var a := TAU * float(k) / 8.0
			var dir := Vector3(-sin(a), 0.0, -cos(a))
			var start := _ground_at((f["pos"] as Vector3) + dir * 90.0)
			p.teleport_to(start + Vector3(0.0, 0.5, 0.0))
			await _f(12)
			start = _ground_at(start)
			var ok := true
			var space := host.get_tree().root.get_world_3d().direct_space_state
			for t in 22:                                                     # buildings, trees, vehicles: 20 m pieces along the ground
				var a0 := _ground_at(start + dir * (float(t) * 20.0 - 180.0)) + Vector3(0.0, 1.5, 0.0)
				var b0 := _ground_at(start + dir * (float(t + 1) * 20.0 - 180.0)) + Vector3(0.0, 1.5, 0.0)
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(a0, b0, Game.L_WORLD | Game.L_VEHICLE)).is_empty():
					ok = false
					break
			for d in [40.0, 60.0, 120.0, 160.0]:                              # a straight line of fire from the gun to targets out there
				if ok and not space.intersect_ray(PhysicsRayQueryParameters3D.create(start + Vector3(0.0, 2.3, 0.0), _ground_at(start + dir * d) + Vector3(0.0, 1.0, 0.0), Game.L_WORLD | Game.L_VEHICLE)).is_empty():
					ok = false
			for t in 10:
				var g := _ground_at(start + dir * (float(t) * 30.0 - 120.0))
				if absf(g.y - start.y) > 4.0:
					ok = false
			if ok:
				field = start
				hdg = a
				print("tank test ground: %s heading %.2f (beside %s)" % [field, hdg, f["name"]])
				return
	field = _ground_at((fields[0]["pos"] as Vector3) if not fields.is_empty() else Vector3(600.0, 0.0, 600.0))
	hdg = 0.0
	TestLib.check(false, "an open stretch of the outskirts for the weapon checks (none found: the first field)")


## A point of the test ground: `along` metres along the clear line, `across` to its right.
func _fp(along: float, across := 0.0) -> Vector3:
	var f := Vector3(-sin(hdg), 0.0, -cos(hdg))
	var r := Vector3(cos(hdg), 0.0, -sin(hdg))
	return field + f * along + r * across


## A vehicle the test owns (kept out of the cap and the streaming).
func _spawn(kind: StringName, at: Vector3, h: float) -> Vehicle:
	vm._fixed_n += 1
	var g := _ground_at(at)
	var v := vm.spawn_parked(kind, g, h)
	if v != null:
		v.set_meta(&"hold", true)
		v.set_meta(&"air_target", true)
		v.global_position = g
	vm._count_fixed()
	return v


func _drop(v: Vehicle) -> void:
	if v == null or not is_instance_valid(v):
		return
	for m: StringName in [&"hold", &"air_target", &"aim_at", &"tank_target"]:
		if v.has_meta(m):
			v.remove_meta(m)
	if v.active and not v.driver_is_player:
		vm._release(v)
	vm._count_fixed()


func _ground_at(p0: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p0.x, 400.0, p0.z), Vector3(p0.x, -50.0, p0.z), Game.L_WORLD)
	var r := host.get_tree().root.get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		return r["position"]
	return Vector3(p0.x, TerrainHeight.height_at(p0.x, p0.z), p0.z)


## The bot puts vehicle `v` at `at`, nose to `face`, standing.
func _place(v: Vehicle, at: Vector3, face: Vector3) -> void:
	var g := _ground_at(at)
	var d := face - at
	v.global_position = g
	v.heading = atan2(-d.x, -d.z)
	v.rotation.y = v.heading
	v.vel = Vector3.ZERO
	v.speed = 0.0


## Holds the crosshair on `pt` until the turret points there (the bot's thumb on the target).
func _aim(v: Vehicle, pt: Vector3, secs := 3.0) -> bool:
	v.set_meta(&"aim_at", pt)
	return await _until(func() -> bool: return (pt - v.muzzle_pos()).normalized().angle_to(v.aim_dir()) < 0.02, secs)


func _tarms(v: Vehicle) -> TankArms:
	return v.weapons.get("tarms") as TankArms if v != null and v.weapons != null else null


## Taps ARMS until the arm button reads `prefix` (at most 4 taps).
func _pick_arm(prefix: String) -> bool:
	for i in 4:
		if fg.button_label(&"aim").begins_with(prefix):
			return true
		if not await _tap(&"arms_next"):
			return false
	return fg.button_label(&"aim").begins_with(prefix)


## Taps SHELL until the tank's selected shell is `id`.
func _pick_shell(id: StringName) -> bool:
	for i in 4:
		if BlastOps.SHELL_IDS[BlastOps.shell_index % BlastOps.SHELL_IDS.size()] == id:
			return true
		await _tap(&"ammo_type")
	return BlastOps.SHELL_IDS[BlastOps.shell_index % BlastOps.SHELL_IDS.size()] == id


## One round of the main gun by a finger on FIRE (it waits for the reload). True when it left the barrel.
func _fire_main(v: Vehicle) -> bool:
	await _until(func() -> bool: return v.weapons.can_fire(), 6.0)
	var s0 := v.weapons.shots
	return await _hold(&"fire", 1.5, func() -> bool: return v.weapons.shots > s0)


# --- WEAPONS -------------------------------------------------------------------------------------------------------------------------

func _weapons() -> void:
	var tk := _spawn(&"tank", _fp(0.0), hdg)
	TestLib.check(tk != null and await _enter(tk), "a finger on ENTER boards the battle tank on the runway")
	if p.vehicle != tk:
		return
	await _f(6)
	# the turret follows the camera: a swipe of the right thumb
	var y0 := tk.craft.turret_yaw
	fg.look(260.0, 0.0, 8)
	await _until(func() -> bool: return absf(wrapf(tk.craft.turret_yaw - y0, -PI, PI)) > 0.35, 3.0)
	TestLib.check(absf(wrapf(tk.craft.turret_yaw - y0, -PI, PI)) > 0.35, "a look swipe turns the turret after the camera (%.2f rad)" % absf(wrapf(tk.craft.turret_yaw - y0, -PI, PI)))
	# the tank's buttons: FIRE, the arm, ARMS, SHELL, SMOKE, BRAKE, EXIT, VIEW keep clear of each other
	await _layout_clear("battle tank")
	var lab := fg.button_label(&"aim")
	TestLib.check(lab.begins_with("COAX ") and lab.substr(5).is_valid_int(), "[old fails] the arm button says what it is and how many: %s" % lab)
	TestLib.check(fg.button(&"arms_next") != Vector2.INF and fg.button_label(&"flare").begins_with("SMOKE"), "[old fails] the tank HUD shows ARMS and SMOKE (%s)" % fg.button_label(&"flare"))
	# a target tank 60 m ahead, side on
	var tp := tk.global_position + tk.forward() * 60.0
	var tg := _spawn(&"tank", tp, tk.heading + PI * 0.5)
	if tg == null:
		TestLib.check(false, "a target tank stands on the field")
		return
	tg.max_hp = 20000.0
	tg.hp = tg.max_hp
	# AP and HE shells of the blast table
	TestLib.check(await _pick_shell(&"ord_tank_ap"), "a finger on SHELL picks the AP shell")
	await _aim(tk, tg.global_position + Vector3(0.0, 1.2, 0.0))
	var hp0 := tg.hp
	var z0 := int(TankArmour.zone_hits.get(&"side", 0))
	await _fire_main(tk)
	await _f(4)
	TestLib.check(BlastOps.instance != null and BlastOps.instance.last_id == &"ord_tank_ap" and tg.hp < hp0, "FIRE: the AP shell hits the tank (hp %.0f -> %.0f, %s)" % [hp0, tg.hp, BlastOps.instance.last_id if BlastOps.instance != null else &""])
	TestLib.check(int(TankArmour.zone_hits.get(&"side", 0)) > z0, "[old fails] the round lands on the SIDE zone of a tank side on to it (%s)" % TankArmour.last_zone)
	TestLib.check(await _pick_shell(&"ord_tank_he"), "a finger on SHELL picks the HE shell")
	hp0 = tg.hp
	await _fire_main(tk)
	await _f(4)
	TestLib.check(BlastOps.instance.last_id == &"ord_tank_he" and tg.hp < hp0, "FIRE: the HE shell hits (hp %.0f -> %.0f)" % [hp0, tg.hp])
	# coax and roof machine guns on the arm button
	var a0 := tk.weapons.alt_hits
	await _hold(&"aim", 2.0, func() -> bool: return tk.weapons.alt_hits >= a0 + 5)
	TestLib.check(tk.weapons.alt_hits >= a0 + 5, "a finger held on COAX: the coaxial gun hits (%d)" % (tk.weapons.alt_hits - a0))
	TestLib.check(await _pick_arm("HMG"), "[old fails] a finger on ARMS picks the roof HMG (%s)" % fg.button_label(&"aim"))
	var r0 := int(TankArms.hits_by.get(&"roof", 0))
	await _hold(&"aim", 2.0, func() -> bool: return int(TankArms.hits_by.get(&"roof", 0)) >= r0 + 4)
	TestLib.check(int(TankArms.hits_by.get(&"roof", 0)) >= r0 + 4, "[old fails] a finger held on HMG: the roof machine gun hits (%d)" % (int(TankArms.hits_by.get(&"roof", 0)) - r0))
	_drop(tg)                                                               # out of the missile's way
	# ATGM with lock-on
	TestLib.check(await _pick_arm("ATGM") or fg.button_label(&"aim").begins_with("LOCK"), "[old fails] a finger on ARMS picks the guided missile (%s)" % fg.button_label(&"aim"))
	var far := _spawn(&"ltank", tk.global_position + tk.forward() * 160.0, tk.heading)
	if far != null:
		far.max_hp = 5000.0
		far.hp = far.max_hp
		await _aim(tk, far.global_position + Vector3(0.0, 1.0, 0.0))
	var locked := await _until(func() -> bool: return fg.button_label(&"aim").begins_with("LOCKED"), 4.0)
	TestLib.check(far != null and locked, "[old fails] the seeker LOCKS on the tank held in the sights (%s)" % fg.button_label(&"aim"))
	TestLib.check(far != null and far.visible, "[old fails] the locked tank 160 m away is drawn (a car is hidden beyond 140 m)")
	var fh := far.hp if far != null else 0.0
	await _tap(&"aim")
	var hit := await _until(func() -> bool: return far == null or far.hp < fh - 50.0, 6.0)
	TestLib.check(hit and int(TankArms.shots_by.get(&"atgm", 0)) >= 1, "[old fails] a finger on the locked ATGM: it flies to the tank and hits (hp %.0f -> %.0f, blast at %.1f m from it, last %s)" % [fh, far.hp if far != null else 0.0, AirRockets.instance.last_blast.distance_to(far.global_position) if far != null and AirRockets.instance != null else -1.0, TankArmour.last_victim])
	# SMOKE
	var s0 := TankArms.smokes
	await _tap(&"flare")
	await _f(4)
	TestLib.check(TankArms.smokes > s0 and TankArms.in_smoke(tk.global_position + tk.forward() * (float(tk.spec["len"]) * 0.5 + 6.0)), "[old fails] a finger on SMOKE: a smoke cloud stands in front of the tank")
	var lab_s := fg.button_label(&"flare")
	TestLib.check(lab_s == "SMOKE 2", "the SMOKE button counts down (%s)" % lab_s)
	_drop(far)
	await _leave()
	_drop(tk)
	await _artillery()
	await _aa()
	await _apc()


func _artillery() -> void:
	var art := _spawn(&"artillery", _fp(-40.0), hdg)
	TestLib.check(art != null and await _enter(art), "a finger on ENTER boards the mobile artillery")
	if p.vehicle != art:
		return
	await _f(6)
	await _layout_clear("artillery")
	var tpos := art.global_position + art.forward() * 220.0
	var tg := _spawn(&"apc", tpos, 0.0)
	if tg == null:
		TestLib.check(false, "an artillery target stands 220 m away")
		return
	tg.set_meta(&"tank_target", true)
	tg.max_hp = 200.0
	tg.hp = tg.max_hp
	var aimp := _ground_at(tg.global_position + Vector3(14.0, 0.0, 6.0))       # the crosshair 15 m off the target: the marker snaps onto it
	art.set_meta(&"aim_at", aimp)
	await _f(20)
	var mp := TankArms.marker_point(art)
	TestLib.check(mp.is_finite() and _flat(mp, tg.global_position) < 2.0, "[old fails] the target marker snaps onto the armour beside the crosshair (%.1f m off)" % (_flat(mp, tg.global_position) if mp.is_finite() else -1.0))
	var sh0 := art.weapons.indirect_shells
	await _fire_main(art)
	var landed := await _until(func() -> bool: return art.weapons.indirect_shells > sh0, 5.0)
	await _f(4)
	TestLib.check(landed and (tg.dead or tg.hp < 200.0), "[old fails] FIRE: the howitzer shell lands on the marker and wrecks the target 220 m away (hp %.0f)" % tg.hp)
	# the rocket salvo
	TestLib.check(await _pick_arm("SALVO"), "[old fails] a finger on ARMS picks the ROCKET SALVO (%s)" % fg.button_label(&"aim"))
	var tg2 := _spawn(&"truck", art.global_position + art.forward() * 110.0, art.heading + PI * 0.5)
	var d0 := AirRockets.instance.detonations if AirRockets.instance != null else 0
	var hp2 := tg2.hp if tg2 != null else 0.0
	if tg2 != null:
		art.set_meta(&"aim_at", tg2.global_position + Vector3(0.0, 1.0, 0.0))
	await _f(10)
	await _tap(&"aim")
	var boom := await _until(func() -> bool: return AirRockets.instance != null and AirRockets.instance.detonations >= d0 + 4, 5.0)
	await _f(6)
	TestLib.check(boom and int(TankArms.shots_by.get(&"salvo", 0)) >= 1 and tg2 != null and (tg2.dead or tg2.hp < hp2), "[old fails] a finger on SALVO: six rockets fan out on the truck (%d blasts, hp %.0f -> %.0f, last blast %.1f m from it)" % [(AirRockets.instance.detonations - d0) if AirRockets.instance != null else 0, hp2, tg2.hp if tg2 != null else 0.0, AirRockets.instance.last_blast.distance_to(tg2.global_position) if tg2 != null and AirRockets.instance != null else -1.0])
	_drop(tg)
	_drop(tg2)
	await _leave()
	_drop(art)


func _aa() -> void:
	var aa := _spawn(&"aatank", _fp(-60.0), hdg)
	TestLib.check(aa != null and await _enter(aa), "a finger on ENTER boards the anti-air tank")
	if p.vehicle != aa:
		return
	await _f(6)
	var air := _puppet(&"heli", aa.global_position + aa.forward() * 140.0 + Vector3(0.0, 60.0, 0.0), 4000.0)
	if air == null:
		TestLib.check(false, "a helicopter hangs in the air")
		return
	await _aim(aa, air.global_position, 4.0)
	var hp0 := air.hp
	var fb0 := aa.weapons.flak_bursts
	var h0 := aa.weapons.hits
	await _hold(&"fire", 2.0, func() -> bool: return air.hp < hp0 - 20.0)
	TestLib.check(air.hp < hp0, "a finger held on FIRE: the flak bursts at the helicopter (hp %.0f -> %.0f, %d bursts %d hits)" % [hp0, air.hp, aa.weapons.flak_bursts - fb0, aa.weapons.hits - h0])
	TestLib.check(fg.button_label(&"aim").begins_with("MISSILE") or fg.button_label(&"aim").begins_with("LOCK"), "the anti-air tank's arm is the SEEKER MISSILE (%s)" % fg.button_label(&"aim"))
	var locked := await _until(func() -> bool: return fg.button_label(&"aim").begins_with("LOCKED"), 4.0)
	TestLib.check(locked, "[old fails] the seeker LOCKS on the helicopter (%s)" % fg.button_label(&"aim"))
	var hp1 := air.hp
	await _tap(&"aim")
	var hit := await _until(func() -> bool: return air.dead or air.hp < hp1 - 40.0, 5.0)
	TestLib.check(hit, "a finger on MISSILE: it homes onto the helicopter and hits (hp %.0f -> %.0f)" % [hp1, air.hp])
	_drop(air)
	await _leave()
	_drop(aa)


func _apc() -> void:
	var apc := _spawn(&"apc", _fp(-90.0), hdg)
	TestLib.check(apc != null and await _enter(apc), "a finger on ENTER boards the armoured carrier")
	if p.vehicle != apc:
		return
	await _f(6)
	var tg := _spawn(&"truck", apc.global_position + apc.forward() * 50.0, PI * 0.5)
	var hp0 := tg.hp if tg != null else 0.0
	if tg != null:
		await _aim(apc, tg.global_position + Vector3(0.0, 1.2, 0.0))
	var h0 := apc.weapons.hits
	await _hold(&"fire", 2.0, func() -> bool: return apc.weapons.hits >= h0 + 4)
	TestLib.check(apc.weapons.hits >= h0 + 4 and tg != null and tg.hp < hp0, "a finger held on FIRE: the AUTOCANNON hits the truck (%d hits)" % (apc.weapons.hits - h0))
	TestLib.check(fg.button_label(&"aim").begins_with("HMG"), "[old fails] the carrier has its roof HMG on the arm button (%s)" % fg.button_label(&"aim"))
	_drop(tg)
	await _leave()
	_drop(apc)


## A hostile aircraft hanging in the air (an AirSteps puppet).
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


## Every visible round button and chip of the driving HUD keeps clear of the others, and none sits on the tank's turret dial.
func _layout_clear(tag: String) -> void:
	await _f(4)
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
	var dial := VehicleHud.last_dial
	if dial.is_finite():
		for d: Array in discs:
			if (d[1] as Vector2).distance_to(dial) < float(d[2]) + 40.0 * s:
				bad.append("%s on the turret dial (%s at %s, vp %s)" % [d[0], d[1], dial, fg.vp()])
	var names := []
	for d: Array in discs:
		names.append(d[0])
	TestLib.check(names.has("arms_next") and names.has("flare") and bad.is_empty(), "[old fails] %s: the buttons (ARMS, SMOKE among %d: %s) keep clear of each other and of the dial %s" % [tag, discs.size(), ",".join(names), ", ".join(bad)])


# --- ARMOUR ----------------------------------------------------------------------------------------------------------------------------

func _armour() -> void:
	var tk := _spawn(&"tank", _fp(-120.0), hdg)
	TestLib.check(tk != null and await _enter(tk), "a finger on ENTER boards the battle tank again")
	if p.vehicle != tk:
		return
	await _f(6)
	if not await _pick_arm("COAX"):
		await _pick_arm("COAX")
	# a target, its FRONT to the hero, 40 m ahead: coax bursts on the front, then on the rear (the bot turns it round)
	var tp := tk.global_position + tk.forward() * 40.0
	var tg := _spawn(&"tank", tp, tk.heading + PI)
	if tg == null:
		return
	tg.max_hp = 20000.0
	tg.hp = tg.max_hp
	var dmg := {}
	for zone: StringName in [&"front", &"rear"]:
		_place(tg, tp, tp + (tk.global_position - tp) * (1.0 if zone == &"front" else -1.0))
		await _aim(tk, tg.global_position + Vector3(0.0, float(tg.spec["hgt"]) * 0.45, 0.0))
		var hp0 := tg.hp
		var n0 := int(TankArmour.zone_hits.get(zone, 0))
		var a0 := tk.weapons.alt_hits
		await _hold(&"aim", 3.0, func() -> bool: return tk.weapons.alt_hits >= a0 + 12)
		dmg[zone] = (hp0 - tg.hp) / float(maxi(tk.weapons.alt_hits - a0, 1))
		TestLib.check(int(TankArmour.zone_hits.get(zone, 0)) > n0, "[old fails] bursts on the %s land on the %s zone (%s on %s, target %s#%d)" % [zone, zone, TankArmour.last_zone, TankArmour.last_victim, tg.name, tg.get_instance_id()])
	TestLib.check(float(dmg.get(&"rear", 0.0)) > float(dmg.get(&"front", 0.0)) * 2.0, "[old fails] a round on the REAR hurts far more than one on the FRONT armour (%.2f vs %.2f a round)" % [float(dmg.get(&"rear", 0.0)), float(dmg.get(&"front", 0.0))])
	var mg := float(dmg.get(&"front", 0.0))
	TestLib.check(mg > 0.0 and mg < float(VehicleSpecs.ALT_WEAPONS[&"tank"]["dmg"]) * 0.5, "[old fails] machine-gun rounds barely scratch the front armour (%.2f of %.0f a round)" % [mg, float(VehicleSpecs.ALT_WEAPONS[&"tank"]["dmg"])])
	# TURRET: a round at the turret
	_place(tg, tp, tp + tg.right() * 10.0)
	await _pick_shell(&"ord_tank_ap")
	var nt := int(TankArmour.zone_hits.get(&"turret", 0))
	await _aim(tk, tg.global_position + Vector3(0.0, float(tg.spec["hgt"]) * 0.85, 0.0))
	await _fire_main(tk)
	await _f(4)
	TestLib.check(int(TankArmour.zone_hits.get(&"turret", 0)) > nt, "[old fails] a round at the turret lands on the TURRET zone (%s)" % TankArmour.last_zone)
	# TRACKS: rounds low on the flank break that side's track; the tank then cannot drive
	_place(tg, tp, tp + (tk.right() * 10.0))
	var side_pt := tg.global_position + Vector3(0.0, float(tg.spec["hgt"]) * 0.3, 0.0)
	await _aim(tk, side_pt)
	for i in 4:
		if TankArmour.track_state(tg) == &"broken":
			break
		await _fire_main(tk)
		await _f(3)
	TestLib.check(TankArmour.track_state(tg) == &"broken", "[old fails] rounds low on the flank break the track (%s, L %.0f R %.0f, last zone %s)" % [TankArmour.track_state(tg), TankArmour.track_hp(tg, &"trk_l"), TankArmour.track_hp(tg, &"trk_r"), TankArmour.last_zone])
	var away := tp + (tp - tk.global_position).normalized() * 60.0              # it drives on along the clear line, away from the hero
	_place(tg, tp, away)
	var moved := await _drive_test(tg, 1.5)
	TestLib.check(moved < 1.0, "[old fails] a tank with a broken track cannot drive (%.1f m in 1.5 s)" % moved)
	tg.set_meta(&"trk_l", TankArmour.TRACK_HP * 0.3)
	tg.set_meta(&"trk_r", TankArmour.TRACK_HP)
	if tg.has_meta(&"trk_fix"):
		tg.remove_meta(&"trk_fix")
	_place(tg, tp, away)
	var slow := await _drive_test(tg, 2.5)
	tg.repair()
	_place(tg, tp, away)
	var fast := await _drive_test(tg, 2.5)
	TestLib.check(slow > 0.5 and slow < fast * 0.75, "[old fails] a damaged track slows the tank (%.1f m against %.1f m intact)" % [slow, fast])
	# REAR at low hull: the engine catches fire
	_place(tg, tp, tp + (tp - tk.global_position))
	tg.max_hp = 2000.0
	tg.hp = 700.0
	await _aim(tk, tg.global_position + Vector3(0.0, float(tg.spec["hgt"]) * 0.45, 0.0))
	var f0 := TankArmour.engine_fires
	await _fire_main(tk)
	await _f(6)
	TestLib.check(TankArmour.engine_fires > f0 and (tg.fuse >= 0.0 or tg.dead) and tg.dmg_state >= 2, "[old fails] a round in the engine deck of a hurt tank sets it BURNING (fuse %.1f, state %d)" % [tg.fuse, tg.dmg_state])
	var dead := await _until(func() -> bool: return tg.dead, 12.0)
	TestLib.check(dead and TankWreck.popped > 0, "the burning tank blows up and throws its turret (wreck)")
	_drop(tg)
	await _leave()
	_drop(tk)


## The bot drives `v` forward by its stick (Vehicle.scripted, the AI's way) for `secs`; returns metres moved.
func _drive_test(v: Vehicle, secs: float) -> float:
	var a := v.global_position
	v.scripted = true
	v.script_thr = 1.0
	v.script_steer = 0.0
	await _until(func() -> bool: return false, secs)
	v.script_thr = 0.0
	v.scripted = false
	return _flat(a, v.global_position)


# --- CREWS -----------------------------------------------------------------------------------------------------------------------------

func _crews() -> void:
	var tk := _spawn(&"tank", _fp(-150.0), hdg)
	TestLib.check(tk != null and await _enter(tk), "a finger on ENTER boards the battle tank (crews)")
	if p.vehicle != tk:
		return
	await _f(6)
	tk.max_hp = 6000.0
	tk.hp = tk.max_hp
	var tc := TankCrews.current
	TestLib.check(tc != null, "[old fails] the enemy tank crews exist under the vehicle manager")
	if tc == null:
		await _leave()
		_drop(tk)
		return
	var at := tk.global_position + tk.forward() * 140.0
	var foe := tc.spawn(&"tank", _ground_at(at), tk.heading + PI * 0.8, &"mission", {"hp": 900.0})
	TestLib.check(foe != null, "an enemy crew takes a tank 140 m away")
	if foe == null:
		return
	await _until(func() -> bool: return false, 1.0)
	TestLib.check(foe.visible, "[old fails] the enemy tank 140 m away is drawn (cars vanish beyond 140 m)")
	var d0 := _flat(foe.global_position, tk.global_position)
	var s0 := TankCrews.shots
	var hp0 := tk.hp
	var closed := await _until(func() -> bool: return _flat(foe.global_position, tk.global_position) < d0 - 40.0, 25.0)
	TestLib.check(closed, "[old fails] the crew drives up to fighting distance (%.0f m -> %.0f m)" % [d0, _flat(foe.global_position, tk.global_position)])
	var shot := await _until(func() -> bool: return TankCrews.shots > s0 and tk.hp < hp0, 20.0)
	TestLib.check(shot, "[old fails] the enemy tank fires on the hero's tank and hits it (%d rounds, hp %.0f -> %.0f)" % [TankCrews.shots - s0, hp0, tk.hp])
	await _pick_shell(&"ord_tank_ap")
	var k0 := TankCrews.kills
	for i in 12:
		if foe.dead:
			break
		await _aim(tk, foe.global_position + Vector3(0.0, 1.2, 0.0), 2.0)
		await _fire_main(tk)
	TestLib.check(foe.dead and TankCrews.kills > k0, "[old fails] FIRE (AP) destroys the enemy tank (hp %.0f)" % foe.hp)
	tk.remove_meta(&"aim_at")
	# the ARMY AIRBASE crew: there near the base, holds fire while the hero is not wanted, fights at 1 star
	var b := tc.base_pos()
	TestLib.check(b.is_finite(), "[old fails] the ARMY AIRBASE has a place for its crew")
	if b.is_finite():
		_place(tk, b + Vector3(-90.0, 0.0, 0.0), b)
		Game.heat = 0.0
		var there := await _until(func() -> bool: return tc.count(&"base") > 0, 4.0)
		TestLib.check(there, "[old fails] a tank crew patrols the ARMY AIRBASE when the hero comes near (%d)" % tc.count(&"base"))
		await _until(func() -> bool: return false, 2.0)
		var bs0 := TankCrews.shots
		TestLib.check(tc.count(&"base") > 0 and not bool(tc.crews[0]["engaged"]), "the base crew does not fight a hero who is not wanted")
		Game.heat = 1.5
		var fights := await _until(func() -> bool: return tc.count(&"base") > 0 and bool(tc.crews[0]["engaged"]), 4.0)
		TestLib.check(fights, "[old fails] at 1 star the base crew engages the hero")
		Game.heat = 0.0
		_place(tk, ArmourSites.YARD + Vector3(0.0, 0.0, 14.0), ArmourSites.YARD + Vector3(0.0, 0.0, 60.0))      # far away (the city)
		await _until(func() -> bool: return tc.count(&"base") == 0, 4.0)
		TestLib.check(tc.count(&"base") == 0, "the base crew goes back to the pool when the hero leaves (%d, %d rounds)" % [tc.count(&"base"), TankCrews.shots - bs0])
	# 4 stars: a tank comes for the hero
	_place(tk, _fp(-150.0), _fp(0.0))
	await _f(10)
	Game.heat = 4.3
	var came := await _until(func() -> bool:
		Game.heat = maxf(Game.heat, 4.3)
		return tc.count(&"wanted") > 0, 20.0)
	var wd := Wanted.current
	TestLib.check(came, "[old fails] at 4 stars a tank crew is sent after the hero (%d sent; wanted %s mode '%s' watchers %d dispatched %s, crews %d of %d)" % [TankCrews.wanted_sent, wd != null, wd.hide_mode if wd != null else "", wd.watchers if wd != null else -1, wd.dispatched if wd != null else {}, tc.crews.size(), TankCrews.cap()])
	Game.heat = 0.0
	tc.release_mode(&"wanted")
	await _leave()
	_drop(tk)


# --- MISSIONS --------------------------------------------------------------------------------------------------------------------------

## Opens the board from the pause button (in the ARMY YARD) and taps the card of type `t`. True when the mission runs.
func _board_start(t: StringName) -> bool:
	if board.is_running():
		board.abandon("TEST")
		await _f(4)
	if p.vehicle != null:
		var last := p.vehicle as Vehicle
		await _leave()
		if is_instance_valid(last):
			for m: StringName in [&"hold", &"mission_ride", &"fixed"]:
				if last.has_meta(m):
					last.remove_meta(m)
			if last.active and not last.driver_is_player:
				vm._release(last)
	await _stand_at(ArmourSites.YARD + Vector3(0.0, 0.0, 12.0), ArmourSites.YARD)
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
	TestLib.check(idx >= 0, "[old fails] the board offers %s in the ARMY YARD" % TankMissions.DEFS[t]["title"])
	if idx < 0:
		if Game.state == &"paused":
			var br := _hud_rect(&"board_back")
			await _tap_at(br.get_center())
		await _until(func() -> bool: return Game.state == &"play", 1.0)
		return false
	var cr := _hud_rect(StringName("board_pick_%d" % idx))
	await _tap_at(cr.get_center())
	await _until(func() -> bool: return board.is_running() and Game.state == &"play", 2.0)
	TestLib.check(board.is_running() and StringName(board.active.get("type", &"")) == t, "a finger on the card starts %s" % TankMissions.DEFS[t]["title"])
	return board.is_running()


func _camp() -> CampaignRunner:
	return board._campaign()


func _step_is(i: int, secs := 4.0) -> bool:
	var k := _camp()
	return await _until(func() -> bool: return k.step_index >= i and k.state == &"active", secs)


func _board_provided() -> Vehicle:
	var k := _camp()
	await _until(func() -> bool: return not k.ws.provided.is_empty(), 4.0)
	if k.ws.provided.is_empty():
		TestLib.check(false, "the mission leaves a vehicle waiting")
		return null
	var v: Vehicle = k.ws.provided[0]
	var ok := await _enter(v)
	await _step_is(1, 4.0)
	TestLib.check(ok and k.step_index >= 1, "%s waits in the yard; a finger on ENTER boards it and the mission goes on (%s)" % [VehicleSpecs.name_of(v.kind), k.hud_line()])
	return v if ok else null


func _finished(title: String, done0: int, secs := 8.0) -> void:
	var ok := await _until(func() -> bool: return board.done_count > done0, secs)
	TestLib.check(ok, "[old fails] %s is finished by the bot (done %d -> %d, %s)" % [title, done0, board.done_count, _camp().hud_line()])
	if not ok and board.is_running():
		board.abandon("TEST")
	await _f(4)


## The drive out: the bot places the vehicle at the reach goal (the driving itself is covered by the tank tests).
func _drive_to_goal(v: Vehicle) -> void:
	var k := _camp()
	if k.kind != &"reach":
		return
	var i := k.step_index
	_place(v, k.pos, k.pos + (k.pos - v.global_position))
	await _step_is(i + 1, 4.0)


## Shoots tank `e` with the main gun until it burns (the bot keeps the crosshair on it, the finger on FIRE).
func _kill(v: Vehicle, e: Vehicle, secs := 30.0) -> bool:
	var t0 := Time.get_ticks_msec()
	var ang := atan2(v.global_position.x - e.global_position.x, v.global_position.z - e.global_position.z)
	var misses := 0
	while is_instance_valid(e) and not e.dead and e.active and float(Time.get_ticks_msec() - t0) < secs * 1000.0:
		if _flat(v.global_position, e.global_position) > 90.0 or misses >= 2:            # too far, or something stands in the way: the bot drives round to another side
			if misses >= 2:
				ang += 1.1
				misses = 0
			var at := e.global_position + Vector3(sin(ang), 0.0, cos(ang)) * 55.0
			_place(v, at, e.global_position)
		await _aim(v, e.global_position + Vector3(0.0, 1.2, 0.0), 1.5)
		var hp0 := e.hp
		await _fire_main(v)
		await _f(4)
		if is_instance_valid(e) and not e.dead and e.hp >= hp0 - 1.0:
			misses += 1
	v.remove_meta(&"aim_at")
	return not is_instance_valid(e) or e.dead or not e.active


func _battle() -> void:
	var done0 := board.done_count
	if not await _board_start(&"tank_battle"):
		return
	var v := await _board_provided()
	if v == null:
		return
	v.max_hp = 8000.0
	v.hp = v.max_hp
	await _pick_shell(&"ord_tank_ap")
	await _drive_to_goal(v)
	var k := _camp()
	await _until(func() -> bool: return k.kind == &"tank_task" and not k.tank.enemies.is_empty(), 3.0)
	var n := k.tank.enemies.size()
	var killed := 0
	TestLib.check(n >= 2 and k.hud_line().contains("TANKS"), "[old fails] the enemy tanks hold the field: %s" % k.hud_line())
	for i in 8:
		if k.tank.enemies.is_empty() or k.kind != &"tank_task":
			break
		var e: Vehicle = k.tank.enemies[0]
		await _kill(v, e)
		if e.dead:
			killed += 1
	TestLib.check(killed >= n, "[old fails] FIRE destroys every enemy tank (%d of %d)" % [killed, n])
	await _finished("TANK BATTLE", done0)


func _convoy() -> void:
	var done0 := board.done_count
	if not await _board_start(&"tank_convoy"):
		return
	var v := await _board_provided()
	if v == null:
		return
	v.max_hp = 8000.0
	v.hp = v.max_hp
	await _pick_shell(&"ord_tank_ap")
	await _drive_to_goal(v)
	var k := _camp()
	await _until(func() -> bool: return k.kind == &"tank_task" and not k.tank.trucks.is_empty(), 3.0)
	TestLib.check(k.tank.trucks.size() >= 2, "[old fails] the convoy trucks stand on the road: %s" % k.hud_line())
	var t0 := Time.get_ticks_msec()
	var waves := 0
	while k.kind == &"tank_task" and k.state == &"active" and float(Time.get_ticks_msec() - t0) < 60000.0:
		waves = maxi(waves, k.tank.wave)
		if not k.tank.enemies.is_empty():
			await _kill(v, k.tank.enemies[0], 20.0)
		elif not k.tank.trucks.is_empty():
			var lead := k.tank.trucks[0]
			_place(v, lead.global_position + lead.right() * 12.0 + lead.forward() * 10.0, lead.global_position + lead.forward() * 60.0)
			await _until(func() -> bool: return false, 0.5)
		else:
			break
	TestLib.check(waves >= 2 or board.done_count > done0, "two waves of enemy tanks came at the convoy (wave %d)" % waves)
	await _finished("CONVOY ESCORT", done0)


func _artillery_strike() -> void:
	var done0 := board.done_count
	if not await _board_start(&"tank_artillery"):
		return
	var v := await _board_provided()
	if v == null:
		return
	await _drive_to_goal(v)
	var k := _camp()
	await _until(func() -> bool: return k.kind == &"tank_task" and not k.tank.targets.is_empty(), 3.0)
	var n := k.tank.targets.size()
	TestLib.check(n >= 3, "[old fails] the enemy armour stands %d m from the firing position: %s" % [roundi(_flat(v.global_position, k.pos)), k.hud_line()])
	for i in 10:
		if k.tank.targets.is_empty() or k.kind != &"tank_task":
			break
		var t: Vehicle = k.tank.targets[0]
		v.set_meta(&"aim_at", _ground_at(t.global_position + Vector3(9.0, 0.0, 5.0)))     # the thumb puts the crosshair near it: the marker snaps on
		await _f(10)
		var sh := v.weapons.indirect_shells
		await _fire_main(v)
		await _until(func() -> bool: return v.weapons.indirect_shells > sh, 5.0)
		await _f(6)
	v.remove_meta(&"aim_at")
	TestLib.check(k.tank.kills >= n or board.done_count > done0, "[old fails] the howitzer shells wreck every target (%d of %d)" % [k.tank.kills, n])
	await _finished("ARTILLERY STRIKE", done0)
