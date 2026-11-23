extends RefCounted
## WAVE 120 (owner round 7: "fly anywhere", reach buildings; w120-sky). The real main scene as a phone, REAL FINGERS (tests/touch_audit_lib.gd:
## InputEventScreenTouch / Drag through Input.parse_input_event), touch HUD on, reward cards on (CrateReveal._quiet = 0).
##   1. helicopter: UP held over the city climbs past 340 m and stays there (old: the vehicle rescue put a heli more than ceil + 30 = 310 m above the ground back on it).
##   2. plane: UP and the throttle stick climb above the highest peak (559 m at x -200, z -2950) (old: the 420 m ceiling held it under the peak).
##   3. helicopter at a corner of the world, the stick forward toward the corner: a soft turn-back (old: it flew into the hard clamp at PLAY_HALF and stopped dead).
##   4. ten tallest city towers: the hero dropped over each roof stands on it (no falling through, no standing on air) and a finger on JUMP jumps off the roof and lands on it again.
## Old behaviour: W120_OLD=1 (AircraftFlight.sky_fix false): checks 1 to 3 fail.
## Run: tools/test.sh tests/test_sky_w120.gd

const TIMEOUT_SECONDS := 148
const Audit := preload("res://tests/touch_audit_lib.gd")
const PEAK := Vector2(-200.0, -2950.0)
var a: Audit
var p: Player


func _ck(ok: bool, text: String) -> bool:
	TestLib.check(ok, text)
	return ok


func _stick() -> Vector2:
	var s := a.tc._scale()
	return Vector2(190.0 * s + a.tc._insets().x, a.vp().y - 170.0 * s)


func _spawn(kind: StringName) -> Vehicle:
	var vm := Game.vehicles as VehicleManager
	DemoMenu.spawn_vehicle(kind)
	var best: Vehicle = null
	for v: Vehicle in vm.list:
		if is_instance_valid(v) and v.kind == kind and (best == null or v.global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position)):
			best = v
	return best


## Spawns `kind`, boards it, and puts it airborne at `pos` with `heading` (set-up only: every control after this is a finger).
func _air(kind: StringName, pos: Vector3, heading: float, speed: float) -> Vehicle:
	var vm := Game.vehicles as VehicleManager
	var v := _spawn(kind)
	if v == null:
		return null
	vm.enter(v)
	await a.pframes(10)
	v.craft.spool = 1.0
	v.craft.airborne = true
	v.craft.lever = 1.0
	v.global_position = pos
	v.heading = heading
	v.speed = speed
	v.vel = v.forward() * speed
	await a.pframes(4)
	return v


func _leave(v: Vehicle) -> void:
	var vm := Game.vehicles as VehicleManager
	a.release_all_fingers()
	if p.vehicle != null:
		vm.exit_vehicle()
	await a.pframes(6)
	if is_instance_valid(v):
		vm._release(v)
	await a.pframes(4)


func run(h: Node) -> void:
	AircraftFlight.sky_fix = OS.get_environment("W120_OLD") != "1"
	a = Audit.new()
	a.quiet = true
	var ok := await a.boot(h, "w120")
	TestLib.check(ok, "main.tscn boots as a phone with the touch controls")
	if not ok:
		return
	CrateReveal._quiet = 0
	(Game.progress as Progress).new_campaign()
	Game.state = &"play"
	await a.frames(30)
	p = Game.player as Player
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	(Game.enemies as EnemyManager).clear()
	if Encounters.current != null:
		Encounters.current.enabled = false
	await _heli_high()
	await _plane_peak()
	await _edge()
	await _roofs()
	for c: Array in a.checks:
		TestLib.check(c[0], c[1])
	await a.shutdown()


func _heli_high() -> void:
	var v := await _air(&"heli", Vector3(40.0, 295.0, -60.0), 0.0, 0.0)
	if not _ck(v != null and p.vehicle == v, "a helicopter is boarded"):
		return
	var up := a.hud_button("jump")
	_ck(not up.is_empty(), "the helicopter shows UP")
	a.finger_down(a.centre_of(up), 2)
	var dropped := [false]
	var high := await a.until(func() -> bool:
		dropped[0] = dropped[0] or v.global_position.y < 200.0
		return v.global_position.y > 340.0, 1500)
	a.finger_up(2)
	await a.pframes(60)
	_ck(high and not dropped[0] and v.global_position.y > 330.0, "helicopter: UP climbs past 340 m over the city and holds there, no forced landing (y %.0f, dropped %s)" % [v.global_position.y, dropped[0]])
	await _leave(v)


func _plane_peak() -> void:
	var v := await _air(&"plane", Vector3(PEAK.x, 500.0, PEAK.y + 900.0), 0.0, 60.0)       # heading 0 flies toward -z: over the peak
	if not _ck(v != null and p.vehicle == v, "a plane is boarded"):
		return
	var st := _stick()
	a.finger_down(st, 1)
	await a.frames(2)
	a.finger_move(st + Vector2(0.0, -95.0 * a.tc._scale()), 1)
	a.finger_down(a.centre_of(a.hud_button("jump")), 2)
	var over := await a.until(func() -> bool: return v.global_position.y > 600.0, 1500)
	a.release_all_fingers()
	_ck(over, "plane: UP with the throttle forward climbs above the 559 m peak (y %.0f)" % v.global_position.y)
	await _leave(v)


func _edge() -> void:
	var lim := CityLayout.PLAY_HALF
	var v := await _air(&"heli", Vector3(lim - 300.0, 160.0, lim - 300.0), -PI * 0.75, 40.0)     # facing the +x +z corner
	if not _ck(v != null, "a helicopter at the corner"):
		return
	var st := _stick()
	a.finger_down(st, 1)
	await a.frames(2)
	a.finger_move(st + Vector2(0.0, -95.0 * a.tc._scale()), 1)
	var far := 0.0
	var stopped := false
	for i in 900:
		await a.tree.physics_frame
		far = maxf(far, maxf(absf(v.global_position.x), absf(v.global_position.z)))
		if i > 30 and v.vel.length() < 0.5 and v.speed < 0.5:
			stopped = true
	a.release_all_fingers()
	var home := Vector3(-v.global_position.x, 0.0, -v.global_position.z).normalized()
	_ck(far < lim - 10.0 and not stopped and v.forward().dot(home) > 0.3, "corner: the helicopter turns back softly before the world edge (furthest %.0f of %.0f, stopped dead %s, facing home %.2f)" % [far, lim, stopped, v.forward().dot(home)])
	await _leave(v)


func _roofs() -> void:
	var city := a.root.find_child("World", true, false)
	var lay: CityLayout = city.get("layout") if city != null else null
	if not _ck(lay != null, "the city layout is there"):
		return
	var lots := lay.lots.duplicate()
	lots.sort_custom(func(x: CityLayout.Lot, y: CityLayout.Lot) -> bool: return x.h > y.h)
	var good := 0
	var notes := ""
	for k in 10:
		var lot: CityLayout.Lot = lots[k * 3]                  # spread over the tall ones, not ten neighbours
		p.teleport_to(Vector3(lot.cx, lot.h + 6.0, lot.cz))
		p.velocity = Vector3.ZERO
		await a.pframes(90)
		var y0 := p.global_position.y
		var on := p.is_on_floor() and absf(y0 - lot.h) < 1.6
		var jumped := [false]
		var j := a.hud_button("jump")
		if not j.is_empty():
			a.finger_down(a.centre_of(j))
			await a.until(func() -> bool:
				jumped[0] = p.global_position.y > y0 + 0.4
				return jumped[0], 40)
			a.finger_up()
		await a.pframes(90)
		var back := p.is_on_floor() and absf(p.global_position.y - lot.h) < 1.6
		if on and jumped[0] and back:
			good += 1
		else:
			notes += " [lot %d h %.0f: y %.1f, floor %s, jump %s, after %.1f]" % [lot.index, lot.h, y0, on, jumped[0], p.global_position.y]
	_ck(good == 10, "roofs: the hero stands on 10 of 10 tower tops, jumps by finger and lands on them again (%d of 10)%s" % [good, notes])
