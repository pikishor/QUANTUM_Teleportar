extends RefCounted
## w119-critic: the defects the independent review of wave 119 found, each driven by REAL FINGERS (InputEventScreenTouch through Input.parse_input_event) on the real main scene
## as an 844x390 phone, touch HUD on, reward cards on (tests/touch_audit_lib.gd).
##  1 the context slot (ENTER / SNAKE BLAST) followed every car that came into reach: on a street with traffic it flipped several times a second, the word under the thumb was not the
##    action the thumb got (an ENTER tap threw a snake) and a held BLAST turned into ENTER mid-aim. Now it settles, never changes under a finger, and stays BLAST just after a throw.
##  2 the BLAST button of the fire species read "FIRE 3" one thumb above the FIRE button (now BLAZE).
##  4 a snake bomb armed on the weapon wheel (BOMBS wedge) and thrown with FIRE at a crosshair on the sky burst metres over the street; now it lands on the street under it.
##  3 holding WEAPON with a real finger opens the weapon wheel.
## Fail first: W119C_OLD=1 tools/test.sh tests/test_w119_critic.gd
const TIMEOUT_SECONDS := 140
const Audit := preload("res://tests/touch_audit_lib.gd")
const STREET := Vector3(-30.0, 0.0, 4.0)
const YAW := -PI * 0.5
var a: Audit
var p: Player
var sb: SnakeBlasts


func _ck(ok: bool, text: String) -> bool:
	TestLib.check(ok, text)
	return ok


func _slot() -> String:
	if not a.hud_button("snake_blast").is_empty():
		return "blast"
	if not a.hud_button("interact").is_empty():
		return "enter"
	return "-"


## What the crosshair ray (SnakeAim.point's ray) hits within `reach`: "nothing" or the collider and the point (w119 CI diagnostics).
func _ray_hit(pl: Player, reach: float) -> String:
	var r := SnakeAim.ray(pl)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	var start := o + d * maxf(0.0, (pl.camera_rig.get_pivot_position() - o).dot(d))
	var q := PhysicsRayQueryParameters3D.create(start, start + d * reach, Game.L_WORLD | Game.L_VEHICLE | Game.L_ENEMY, [pl.get_rid()])
	var res := pl.get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return "nothing"
	var c: Object = res["collider"]
	return "%s at %s" % [str(c.get_path()) if c is Node else str(c), str((res["position"] as Vector3).snapped(Vector3(0.1, 0.1, 0.1)))]


func _street() -> void:
	a.release_all_fingers()
	(Game.enemies as EnemyManager).clear()
	(Game.vehicles as VehicleManager)._reset_all()
	p.snake.cancel()
	p.teleport_to(STREET)
	p.yaw = YAW
	p.camera_rig.reset_view(YAW, 0.05)
	p.velocity = Vector3.ZERO
	await a.pframes(30)


func run(h: Node) -> void:
	a = Audit.new()
	a.quiet = true
	if not _ck(await a.boot(h, "w119c"), "main.tscn boots as a phone with the touch controls"):
		return
	(Game.progress as Progress).new_campaign()
	Game.state = &"play"
	await a.frames(30)
	p = Game.player as Player
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	if Encounters.current != null:
		Encounters.current.enabled = false
	if NearTraffic.instance != null:
		NearTraffic.instance.enabled = false                 # the cars here are placed by the test
	sb = SnakeBlasts.instance
	if not _ck(sb != null, "SnakeBlasts is on the hero"):
		await a.shutdown()
		return
	await _held_blast()
	await _flicker()
	await _labels()
	await _weapon_hold()
	await _bomb_sky()
	await _tank()
	await a.shutdown()


## 1a: a car rolls into reach while the thumb holds BLAST: the button stays BLAST, letting go throws; the slot stays BLAST just after the throw, then ENTER, and a tap on ENTER enters.
func _held_blast() -> void:
	await _street()
	var vm := Game.vehicles as VehicleManager
	sb.charges = SnakeBlasts.CHARGES
	await a.until(func() -> bool: return _slot() == "blast", 60)
	var blast := a.hud_button("snake_blast")
	if not _ck(not blast.is_empty(), "BLAST is in the context slot on a bare street"):
		return
	var at := a.centre_of(blast)
	a.finger_down(at)
	await a.pframes(6)
	var car := vm.spawn_parked(&"sedan", p.global_position + Vector3(0.0, 0.0, 2.6), YAW)
	await a.pframes(40)
	_ck(car != null and _slot() == "blast" and sb.aiming, "a car in reach while the thumb holds BLAST: the button under the thumb stays BLAST and the ring stays (%s)" % _slot())
	var t0 := sb.thrown
	a.finger_up()
	await a.pframes(4)
	_ck(sb.thrown == t0 + 1, "letting go throws the snake")
	await a.pframes(20)
	_ck(_slot() == "blast", "just after a throw the slot is still BLAST for the next throw, car or no car (%s)" % _slot())
	await a.until(func() -> bool: return sb.flying.is_empty(), 90)
	if car != null:                                         # the burst may have pushed the car: put it back beside the hero
		car.global_position = p.global_position + Vector3(0.0, 0.0, 2.6)
		car.velocity = Vector3.ZERO
	var ok := await a.until(func() -> bool: return _slot() == "enter", 260)
	_ck(ok, "a few seconds later the car in reach puts ENTER in the slot")
	var eb := a.hud_button("interact")
	var t1 := sb.thrown
	if not eb.is_empty():
		await a.tap(a.centre_of(eb))
		await a.pframes(40)
	_ck(p.vehicle != null and sb.thrown == t1, "a tap on ENTER enters a car and throws nothing (in %s, car %s hp %s, thrown +%d)" % [p.vehicle, car, car.hp if car else -1.0, sb.thrown - t1])
	if p.vehicle != null:
		vm.toggle_enter_exit()
		await a.pframes(30)


## 1b: a car at the edge of reach (traffic passing, jams) goes in and out of reach every few frames: the slot does not flip each time, and every tap gets the action it showed.
func _flicker() -> void:
	await _street()
	var vm := Game.vehicles as VehicleManager
	var near := p.global_position + Vector3(0.0, 0.0, 2.6)
	var far := p.global_position + Vector3(0.0, 0.0, 40.0)
	var car := vm.spawn_parked(&"sedan", far, YAW)
	await a.pframes(10)
	var flips := 0
	var last := _slot()
	var wrong := 0
	var taps := 0
	for k in 48:
		if car != null:
			car.global_position = near if (k / 4) % 2 == 0 else far
		await a.frames(1)
		var s := _slot()
		if s != last:
			flips += 1
			last = s
		if k % 12 == 6 and s == "enter":                   # a thumb on what is drawn (ENTER): it must not throw a snake
			var t0 := sb.thrown
			var b := a.hud_button("interact")
			a.finger_down(a.centre_of(b))
			await a.frames(3)
			a.finger_up()
			taps += 1
			if sb.thrown != t0:
				wrong += 1
			if p.vehicle != null:
				vm.toggle_enter_exit()
				await a.pframes(10)
	_ck(flips <= 2, "a car that comes and goes every 4 frames does not flip the slot each time (%d flips in 48 frames)" % flips)
	_ck(wrong == 0, "no tap on a drawn ENTER throws a snake (%d of %d)" % [wrong, taps])


## 2: the BLAST label never starts with the word of another round button on screen.
func _labels() -> void:
	await _street()
	sb.select(&"sp_fire")
	await a.until(func() -> bool: return _slot() == "blast", 60)
	await a.pframes(4)
	var bl := str(a.hud_button("snake_blast").get("label", ""))
	var clash := ""
	for c: Dictionary in a.touch_controls():
		var l := str(c.get("label", ""))
		if c["id"] != "snake_blast" and l.length() >= 3 and bl.begins_with(l):
			clash = l
	_ck(bl != "" and clash == "", "the fire species' BLAST button does not read like another button (%s vs %s)" % [bl, clash])


## 3: a real finger held on WEAPON opens the weapon wheel; letting go keeps the weapon.
func _weapon_hold() -> void:
	await _street()
	var w := a.hud_button("swap")
	if not _ck(not w.is_empty(), "WEAPON is on screen on foot"):
		return
	a.finger_down(a.centre_of(w))
	var opened := await a.until(func() -> bool: return a.tc.wheel.is_open, 60)
	_ck(opened and a.tc.wheel.kind == &"weapon", "holding WEAPON with a finger opens the weapon wheel")
	a.finger_up()
	await a.frames(4)
	a.tc.wheel.close()
	await a.frames(2)


## 4: WEAPON held -> BOMBS wedge -> a bomb -> FIRE with the crosshair a little over the horizon (nothing hit within reach): the bomb bursts on the street, not in the air.
func _bomb_sky() -> void:
	await _street()
	var war := SnakeWar.of(p)
	war.cd.clear()
	p.snake.energy = SnakePower.max_energy()
	var w := a.hud_button("swap")
	a.finger_down(a.centre_of(w))
	if not await a.until(func() -> bool: return a.tc.wheel.is_open, 60):
		a.finger_up()
		_ck(false, "the weapon wheel opens to reach the BOMBS wedge")
		return
	var bw := a.find(a.touch_controls(), "snake_bombs")
	if bw.is_empty():
		a.finger_up()
		a.tc.wheel.close()
		_ck(false, "the weapon wheel has the BOMBS wedge")
		return
	a.finger_move(a.centre_of(w) + (bw["centre"] as Vector2 - a.tc.wheel.centre))      # the drag is read from where the thumb went down (wave 118)
	await a.frames(3)
	a.finger_up()
	await a.frames(4)
	var picked := ""
	print("CRITIC ring ", a.tc.wheel.is_open, " ", a.touch_controls().map(func(c: Dictionary) -> String: return str(c["id"])))
	for c: Dictionary in a.touch_controls():
		if str(c["id"]).begins_with("sb_") and picked == "" and not (str(c["id"]) in ["sb_seeker", "sb_burrow", "sb_mega", "sb_constrict"]):
			picked = str(c["id"])
			await a.tap(a.centre_of(c))
			await a.frames(6)
	if a.tc.wheel.is_open:
		a.tc.wheel.close()
	if not _ck(picked != "" and war.armed != &"", "a bomb is armed from the BOMBS wedge by finger (%s)" % picked):
		return
	(Game.enemies as EnemyManager).clear()                     # w119 CI: the premise is "nothing within reach under the crosshair": no foe (a snake hunter the casts called) or car stands in the ray
	(Game.vehicles as VehicleManager)._reset_all()
	p.yaw = YAW + PI
	p.camera_rig.reset_view(YAW + PI, 0.1)                    # the crosshair a little over the street's far end: open sky over the road
	await a.pframes(6)
	var hit_by := _ray_hit(p, 30.0)
	var ops := BlastOps.shared(p.get_tree())
	var hits: Array = []
	var cb := func(_id: StringName, at: Vector3) -> void: hits.append(at)
	ops.detonated.connect(cb)
	var n0: int = ops._items.size()
	var aims: Array = []
	a.finger_down(a.centre_of(a.hud_button("fire")))
	for k in 6:
		await a.pframes(1)
		for it: Dictionary in ops._items:
			if it.has("aim") and aims.is_empty() and StringName(it["kind"]) == &"proj":
				aims.append(it["aim"])
	a.finger_up()
	await a.until(func() -> bool: return not hits.is_empty(), 200)
	_ck(not aims.is_empty() and (aims[0] as Vector3).y - p.global_position.y < 1.0, "the bomb is aimed at the street under the crosshair, not at a point in the air (%s, %d items before, crosshair ray before the throw: %s, hero %s)" % [str(aims), n0, hit_by, str(p.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
	ops.detonated.disconnect(cb)
	var ground := p.global_position                          # a flat street: the hero stands on it
	print("CRITIC bomb hits ", hits, " pitch ", p.camera_rig.pitch)
	_ck(not hits.is_empty(), "the bomb bursts (%s above the ground: it may meet a car or a lamp on the way)" % (str((hits[0] as Vector3).y - ground.y) if not hits.is_empty() else "no burst"))


##  5 (review) a tank hit by a BLAZE or ACID snake caught fire at 93 to 98 % (a fire field or a car blowing up beside it lights every vehicle): one throw killed a tank.
## Review: every species thrown by finger (hold BLAST, the ring on the tank, let go) at a tank 12 m ahead: the tank inside the ring takes damage.
func _tank() -> void:
	var vm := Game.vehicles as VehicleManager
	for id: StringName in SnakeBlasts.SPECIES:
		await _street()
		BlastOps.shared(p.get_tree()).reset()                   # w122-ci: each species is measured alone (the BLAZE ground fire burns 6 s at the same spot and was counted as FROST's damage)
		var at := STREET + Vector3(-sin(YAW), 0.0, -cos(YAW)) * 12.0
		var tank := vm.spawn_parked(&"tank", at, YAW)
		if tank == null:
			await a.pframes(60)
			vm._reset_all()
			tank = vm.spawn_parked(&"tank", at, YAW)
		if tank == null:
			_ck(false, "%s: a tank is spawned" % id)
			continue
		tank.max_hp = 5000.0
		tank.hp = 5000.0
		await a.pframes(6)
		p.camera_rig.aim_at(at + Vector3(0.0, 0.5, 0.0))
		sb.select(id)
		sb.charges = SnakeBlasts.CHARGES
		for k in 3:                                          # a parked car of the street in reach: ENTER has the slot (that is right); take it away
			var rc: Variant = vm.reach_car(p.global_position)
			if rc == null or rc == tank:
				break
			vm._release(rc)
			await a.pframes(3)
		await a.until(func() -> bool: return _slot() == "blast", 60)
		var b := a.hud_button("snake_blast")
		if b.is_empty():
			_ck(false, "%s: BLAST on screen beside the tank" % id)
			continue
		var h0 := tank.hp
		a.finger_down(a.centre_of(b))
		await a.pframes(10)
		var ring := sb.aim_pt
		var b0 := sb.bursts
		a.finger_up()
		await a.until(func() -> bool: return sb.bursts > b0, 120)
		var lit := false
		for k in 15:
			await a.pframes(10)
			if is_instance_valid(tank) and tank.fuse >= 0.0 and not lit:
				lit = true
				print("CRITIC tank lit at hp ", tank.hp, " / ", tank.max_hp, " after ", k * 10, " frames (", id, ")")
		var same := is_instance_valid(tank) and vm.list.has(tank)
		if not same:
			print("CRITIC tank gone: valid=", is_instance_valid(tank), " in list=", vm.list.has(tank) if is_instance_valid(tank) else false, " dead=", tank.dead if is_instance_valid(tank) else null, " hp=", tank.hp if is_instance_valid(tank) else null, " wreck=", tank.wreck if is_instance_valid(tank) else null)
		_ck(same and not lit, "%s: a tank at more than 90 %% does not catch fire from the burst (lit %s)" % [id, lit])
		_ck(same and tank.hp <= h0 - (5.0 if id == &"sp_swarm" else 20.0), "%s: thrown at a tank 12 m ahead (ring %.1f m from it) the tank takes damage (%.0f -> %.0f)" % [id, Vector2(ring.x - at.x, ring.z - at.z).length(), h0, tank.hp if same else -1.0])
