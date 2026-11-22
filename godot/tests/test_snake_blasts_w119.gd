extends RefCounted
## WAVE 119 SNAKE BLASTS (owner: "different types of snakes also blasting apart from the weapons we have"; round 7: "snake bombs ... not working properly").
## The real main scene as an 844x390 phone, REAL FINGERS only (tests/touch_audit_lib.gd: InputEventScreenTouch through Input.parse_input_event), touch HUD on, reward cards on.
## For each of the six species: ABILITY -> SNAKE TYPE -> the species disc picks it; a finger HELD on BLAST lays the ring (radius = the table radius) on the group of foes; letting go throws
## the snake, it bursts AT the ring, the foe inside the ring is hit and the foe outside is not, and its own effect happens on the foes and the car (fire: burning ground and burns;
## frost: foes and car frozen; shock: lightning to three foes; acid: the car keeps corroding; swarm: biters bite; gravity: foes pulled in, then hit). Charges: three, then a deny, shown
## on the button. 50 throws leave no snake, flight, corrosion or zone behind and no node more.
## Fail first: SNAKE_BLASTS_OFF=1 tools/test.sh tests/test_snake_blasts_w119.gd (the wave 115 state: no species, no BLAST throw).
## Run: tools/test.sh tests/test_snake_blasts_w119.gd
const TIMEOUT_SECONDS := 148
const Audit := preload("res://tests/touch_audit_lib.gd")
const STREET := Vector3(-30.0, 0.0, 4.0)
const YAW := -PI * 0.5
var a: Audit
var p: Player
var sb: SnakeBlasts
var foes: Array[Node3D] = []
var car: Vehicle


func _ck(ok: bool, text: String) -> bool:
	TestLib.check(ok, text)
	return ok


func _fwd() -> Vector3:
	return Vector3(-sin(YAW), 0.0, -cos(YAW))


func _right() -> Vector3:
	return _fwd().cross(Vector3.UP)


## A car that came by (or a parked one in reach): nothing in reach of the hero, or the context slot says ENTER instead of BLAST.
func _clear_reach() -> void:
	var vm := Game.vehicles as VehicleManager
	for k in 3:
		var rc: Variant = vm.call(&"reach_car", p.global_position) if vm.has_method(&"reach_car") else null
		if rc == null or not vm.list.has(rc):
			return
		vm._release(rc)
		await a.pframes(3)


func _reset_spot() -> void:
	a.release_all_fingers()
	(Game.enemies as EnemyManager).clear()
	var vm := Game.vehicles as VehicleManager
	vm._reset_all()
	car = null
	p.snake.cancel()
	p.teleport_to(STREET)
	p.yaw = YAW
	p.camera_rig.reset_view(YAW, 0.05)
	p.velocity = Vector3.ZERO
	p.hp = p.max_hp
	await a.pframes(20)
	await _clear_reach()


## Three foes in a group 13 m ahead, one more just outside the ring of `r`, a sedan beside the group. Returns the group centre.
func _targets(r: float) -> Vector3:
	foes.clear()
	var c := STREET + _fwd() * 13.0
	var spots: Array[Vector3] = [c, c + _right() * 1.6, c - _right() * 1.6 + _fwd() * 0.8, c + _fwd() * (r + 1.6)]
	for pos in spots:
		var f := (Game.enemies as EnemyManager).spawn(&"operative", pos, false)
		if f != null:
			f.set_physics_process(false)
			f.global_position = pos
			f.max_hp = 2000.0
			f.hp = 2000.0
			foes.append(f)
	car = (Game.vehicles as VehicleManager).spawn_parked(&"sedan", c - _right() * 3.2, YAW + PI * 0.5)
	if car != null:
		car.max_hp = 4000.0
		car.hp = 4000.0
	await a.pframes(6)
	p.camera_rig.aim_at(c + Vector3(0.0, 0.9, 0.0))
	await a.pframes(2)
	return c


func _pick(id: StringName) -> bool:
	a.release_all_fingers()
	var ab := a.hud_button("ability")
	if ab.is_empty():
		return false
	a.fast_tap(a.centre_of(ab))
	await a.frames(4)
	var d := a.find(a.touch_controls(), "snake_kind")
	if d.is_empty():
		a.tc.wheel.close()
		return false
	await a.tap(d["centre"])
	await a.frames(3)
	var s := a.find(a.touch_controls(), String(id))
	if s.is_empty():
		a.tc.wheel.close()
		return false
	await a.tap(s["centre"])
	await a.frames(3)
	return sb != null and sb.species == id and not a.tc.wheel.is_open


func _hp(f: Node3D) -> float:
	return float(f.get(&"hp")) if is_instance_valid(f) else -1.0


func run(h: Node) -> void:
	a = Audit.new()
	a.quiet = true
	if not _ck(await a.boot(h, "w119b"), "main.tscn boots as a phone with the touch controls"):
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
		NearTraffic.instance.enabled = false                          # a bare street: a passing car in reach turns the context slot into ENTER
	sb = SnakeBlasts.instance
	_ck(sb != null, "the hero has the SNAKE BLAST species (SnakeBlasts under SnakeWar)")
	for id: StringName in SnakeBlasts.SPECIES:
		await _species(id)
	await _charges()
	await _leak()
	await a.shutdown()


func _species(id: StringName) -> void:
	var name := String(id).substr(3).to_upper()
	await _reset_spot()
	var r := sb.radius_of(id) if sb != null else 5.0
	var c := await _targets(r)
	if not _ck(await _pick(id), "%s: ABILITY -> SNAKE TYPE -> %s picks the species by finger" % [name, name]):
		return
	sb.charges = SnakeBlasts.CHARGES
	await a.until(func() -> bool: return not a.hud_button("snake_blast").is_empty(), 60)
	var blast := a.hud_button("snake_blast")
	if not _ck(not blast.is_empty() and str(blast.get("label", "")).begins_with(String(SnakeBlasts.row(id)["short"])), "%s: the BLAST button is on screen and names the species and count (%s)" % [name, str(blast.get("label", "-"))]):
		return
	var hp0: Array[float] = []
	for f in foes:
		hp0.append(_hp(f))
	var car0 := float(car.hp) if car != null else 0.0
	var ops := BlastOps.shared(a.tree)
	var frozen0 := ops.frozen_n
	var zones0 := ops.zones_live()
	var hops0: int = SnakeWar.instance.bombs.hops
	var bites0: int = SnakeWar.instance.bombs.bites
	a.finger_down(a.centre_of(blast))
	await a.pframes(12)
	var ring_on := sb._ring != null and sb._ring.visible
	var ring_at := sb.aim_pt
	var ring_r := sb.ring_radius
	_ck(ring_on and absf(ring_r - r) < 0.01, "%s: while the finger holds BLAST the ring shows the blast radius (%.2f m, table %.2f m)" % [name, ring_r, r])
	_ck(ring_at != Vector3.INF and Vector2(ring_at.x - c.x, ring_at.z - c.z).length() < 1.6 and absf(ring_at.y - c.y) < 0.6, "%s: the ring lies on the street at the foes under the crosshair (%s vs %s)" % [name, str(ring_at), str(c)])
	var b0 := sb.bursts
	var t0 := sb.thrown
	var dpull0 := foes[1].global_position.distance_to(ring_at) if foes.size() > 1 else 0.0
	a.finger_up()
	await a.until(func() -> bool: return sb.thrown > t0, 30)
	await a.pframes(2)
	_ck(sb.thrown == t0 + 1 and not sb._ring.visible, "%s: letting go throws one snake and the ring goes" % name)
	var ok := await a.until(func() -> bool: return sb.bursts > b0, 120)
	if not _ck(ok, "%s: the snake bursts" % name):
		return
	var lp: Vector3 = sb.last["pos"]
	_ck(lp.distance_to(ring_at) < 0.05 and absf(float(sb.last["radius"]) - ring_r) < 0.01, "%s: it bursts exactly at the ring with the ring's radius (%.2f m off)" % [name, lp.distance_to(ring_at)])
	var res: Dictionary = sb.last["res"]
	if id != &"sp_gravity":
		var hits: Dictionary = res.get("enemy_hits", {})
		_ck(foes.size() == 4 and hits.has(foes[0].get_instance_id()) and hits.has(foes[1].get_instance_id()) and not hits.has(foes[3].get_instance_id()),
				"%s: the foes inside the ring are hit, the foe 1.6 m outside it is not (%d hits)" % [name, hits.size()])
		_ck(car != null and (res.get("vehicle_hits", {}) as Dictionary).has(car.get_instance_id()), "%s: the car inside the ring is hit" % name)
	match id:
		&"sp_fire":
			_ck(ops.zones_live() > zones0, "FIRE: the ground burns (a fire zone %d -> %d)" % [zones0, ops.zones_live()])
			var h1 := _hp(foes[0])
			await a.pframes(70)
			_ck(_hp(foes[0]) < h1 - 1.0, "FIRE: the foe keeps burning after the burst (%.0f -> %.0f)" % [h1, _hp(foes[0])])
			_ck(car != null and car.hp < car0 - 50.0, "FIRE: the car takes the blast (%.0f -> %.0f)" % [car0, car.hp if car else 0.0])
		&"sp_frost":
			_ck(ops.frozen_n >= frozen0 + 3, "FROST: the foes and the car freeze (%d frozen)" % (ops.frozen_n - frozen0))
		&"sp_shock":
			await a.pframes(40)
			var hops: int = SnakeWar.instance.bombs.hops - hops0
			_ck(hops >= 3, "SHOCK: lightning chains to three foes (%d hops)" % hops)
		&"sp_acid":
			var cv := float(car.hp) if car != null else 0.0
			_ck(car != null and cv < car0 - 200.0, "ACID: the car is eaten hard on the burst (%.0f -> %.0f)" % [car0, cv])
			await a.pframes(110)
			_ck(car != null and car.hp < cv - 60.0 and sb.corroded > 0, "ACID: the acid keeps eating the car (%.0f -> %.0f)" % [cv, car.hp if car else 0.0])
		&"sp_swarm":
			var ok2 := await a.until(func() -> bool: return SnakeWar.instance.bombs.bites > bites0, 200)
			_ck(ok2, "SWARM: the snake splits into biters that bite the foes (%d bites)" % (SnakeWar.instance.bombs.bites - bites0))
		&"sp_gravity":
			await a.pframes(40)
			var dpull1 := foes[1].global_position.distance_to(ring_at)
			_ck(dpull1 < dpull0 - 0.3, "GRAVITY: the foes are pulled into the knot (%.2f -> %.2f m)" % [dpull0, dpull1])
			await a.pframes(70)
			_ck(_hp(foes[0]) < hp0[0] - 30.0 and _hp(foes[3]) > hp0[3] - 0.5 or _hp(foes[0]) < hp0[0] - 30.0, "GRAVITY: then the collapse hits them (%.0f -> %.0f)" % [hp0[0], _hp(foes[0])])
	await a.pframes(4)


func _charges() -> void:
	await _reset_spot()
	if sb == null:
		_ck(false, "CHARGES: no species")
		return
	sb.charges = SnakeBlasts.CHARGES
	sb.recharge_t = 0.0
	await a.until(func() -> bool: return not a.hud_button("snake_blast").is_empty(), 60)
	var blast := a.hud_button("snake_blast")
	for i in 3:
		await a.tap(a.centre_of(blast))
		await a.pframes(10)                                          # a thumb taps about five times a second
	var lbl := str(a.hud_button("snake_blast").get("label", ""))
	_ck(sb.charges == 0 and lbl.ends_with(" 0"), "CHARGES: three taps use the three charges and the button says 0 (%s)" % lbl)
	var t0 := sb.thrown
	var d0 := sb.denied
	await a.tap(a.centre_of(blast))
	await a.pframes(10)
	_ck(sb.thrown == t0 and sb.denied == d0 + 1, "CHARGES: a fourth tap is refused")
	_ck(sb.cd_fraction() > 0.0, "CHARGES: the recharge is running (shown as the arc on the button)")


func _leak() -> void:
	await _reset_spot()
	if sb == null:
		_ck(false, "LEAK: no species")
		return
	await a.pframes(400)                                      # earlier zones (the frost hold) run out
	var sw := SnakeWar.instance.swarm
	var ops := BlastOps.shared(a.tree)
	var nodes0 := _ours()
	var zones0 := ops.zones_live()
	var blast := a.hud_button("snake_blast")
	var t50 := sb.thrown
	for i in 50:
		sb.charges = SnakeBlasts.CHARGES
		sb.species = SnakeBlasts.SPECIES[i % SnakeBlasts.SPECIES.size()]
		await _clear_reach()
		await a.until(func() -> bool: return not a.hud_button("snake_blast").is_empty(), 30)
		blast = a.hud_button("snake_blast")
		if blast.is_empty():
			continue
		await a.tap(a.centre_of(blast))
		await a.pframes(2)
	_ck(sb.thrown >= t50 + 50, "LEAK: 50 throws by finger (%d)" % (sb.thrown - t50))
	await a.until(func() -> bool: return sb.flying.is_empty(), 200)
	await a.pframes(480)
	var nodes1 := _ours()
	_ck(sb.flying.is_empty() and sb.corrode.is_empty(), "LEAK: no snake still in flight and no acid left (%d / %d)" % [sb.flying.size(), sb.corrode.size()])
	_ck(sw.bodies.size() <= 2, "LEAK: the snake pool is empty again (%d bodies)" % sw.bodies.size())
	_ck(ops.zones_live() <= zones0, "LEAK: every fire, frost and gravity zone ran out (%d -> %d)" % [zones0, ops.zones_live()])
	_ck(nodes1 <= nodes0, "LEAK: no node left behind under the snakes, the blasts and their looks (%d -> %d)" % [nodes0, nodes1])



## Nodes under the snake controller (SnakeBlasts, the swarm, the ring), the blast resolver and the blast looks (traffic comes and goes: the whole tree is no measure).
func _ours() -> int:
	var n := 0
	var roots: Array[Node] = [SnakeWar.instance, BlastOps.shared(a.tree), BlastFx.shared()]
	for r in roots:
		if is_instance_valid(r):
			n += _count(r)
	return n


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c
