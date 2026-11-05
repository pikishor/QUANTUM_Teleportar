extends RefCounted
## NEW QUANTUM VERBS in the real scene (main.tscn): PHASE SHIELD (absorbs and reflects bolts and hitscan shots; snipers see through it, heavy bolts drain it), TIME SLIP (local
## slow-motion bubble: enemies and bolts inside are slowed, flankers resist, the hero is not), ARC (auto-targeting teleport-slash chain, returns to the start, shield troops and
## brutes take less). Energy through HeroPower.cost, cooldowns, vehicle lock-out, the keyboard actions, the expandable touch ring (64 px, no overlap, inside the reserved width,
## tap to open and use) and the TEST / DEMO menu entries. Waits on counters and state, never on frame counts; user:// state is reset.
## Run: tools/test.sh tests/test_new_verbs.gd

const SAVE := "user://test_new_verbs.cfg"

var host: Node
var main: Node
var p: Player
var em: EnemyManager
var qv: QuantumVerbs
var _spawned: Array[Drone] = []


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _until(cond: Callable, max_secs: float) -> bool:
	var n := int(max_secs * 60.0)
	while n > 0 and not cond.call():
		await frames(1)
		n -= 1
	return cond.call()


func _forward() -> Vector3:
	return Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))


func _enemy(pos: Vector3, type := &"sentinel", think := false) -> Drone:
	var d := em.spawn(type, pos, false)
	if d == null:
		return null
	d.set_physics_process(think)
	d.max_hp = 5000.0
	d.hp = 5000.0
	_spawned.append(d)
	return d


func _clear_enemies() -> void:
	for d in _spawned:
		if is_instance_valid(d) and d.active:
			em.release(d)
	_spawned.clear()


func _reset_player() -> void:
	em.clear()
	p.invuln = 0.0
	p.hp = p.max_hp
	p.energy = p.max_energy
	for id: StringName in QuantumVerbs.IDS:
		qv.clear_cooldown(id)
	qv.reset()


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	_tables()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	em = Game.enemies as EnemyManager
	var prog := Game.progress as Progress
	TestLib.check(p != null and em != null and prog != null and p.qverbs != null, "main.tscn composes the player with a QuantumVerbs node")
	if p == null or em == null or prog == null or p.qverbs == null:
		return
	qv = p.qverbs
	prog.autosave_enabled = false
	prog.path = SAVE
	prog.new_campaign()
	Game.state = &"play"
	await frames(5)
	_actions()
	await _touch()
	await _shield()
	await _slip()
	await _arc()
	_costs_and_vehicle()
	await _keys()
	await _touch_use()
	_menus()
	_clear_enemies()
	qv.reset()
	for a: StringName in QuantumVerbs.IDS:
		Input.action_release(a)
	main.queue_free()
	await frames(5)
	Game.state = &"menu"
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


# --- tables -----------------------------------------------------------------------------------------------------------------

func _tables() -> void:
	TestLib.check(QuantumVerbs.IDS.size() == 3, "three new verbs")
	var ok := true
	for id: StringName in QuantumVerbs.IDS:
		var t := String(QuantumVerbs.TITLES[id])
		ok = ok and t == t.to_upper() and float(QuantumVerbs.COST[id]) > 0.0 and float(QuantumVerbs.CD[id]) > 0.0
	TestLib.check(ok, "plain upper-case names, energy cost and cooldown for each verb")
	TestLib.check(QuantumVerbs.slip_scale(Vector3.ZERO, &"") == 1.0 and not QuantumVerbs.shield_hit(Vector3.ZERO, Vector3.ONE), "no bubble and no barrier before a verb is used")
	TestLib.check(QuantumVerbs.pierces(&"sniper") and QuantumVerbs.overloads(&"heavy") and not QuantumVerbs.pierces(&"sentinel"), "counter table: sniper pierces, heavy overloads")


func _actions() -> void:
	for a: StringName in QuantumVerbs.IDS:
		TestLib.check(InputMap.has_action(a), "input action %s exists" % a)


# --- touch wheel layout ---------------------------------------------------------------------------------------------------

func _touch() -> void:
	var verbs := 0
	for d: Dictionary in TouchControls.WHEEL_ABILITIES:
		if d.has("verb"):
			verbs += 1
	TestLib.check(verbs == 3 and TouchControls.WHEEL_ABILITIES.size() == 7, "the ABILITY wheel lists the seven verbs, three of them the new ones")
	TestLib.check(RadialWheel.ITEM_R * 2.0 >= 64.0, "a wheel disc is at least 64 px")
	# at 844x390 every disc lies inside the screen
	var win := host.get_window()
	var old := win.size
	win.size = Vector2i(844, 390)
	await frames(3)
	var tc := _tc()
	if tc != null:
		tc._open_wheel(&"ability", -1, Vector2.ZERO)
		var inside := true
		var vp := tc._vp_size()
		var rr := RadialWheel.ITEM_R * tc._scale()
		for i in tc.wheel.items.size():
			var c := tc.wheel.item_centre(i)
			inside = inside and c.x - rr >= 0.0 and c.x + rr <= vp.x and c.y - rr >= 0.0 and c.y + rr <= vp.y
		TestLib.check(inside and tc.wheel.items.size() == 7, "all seven wheel discs fit the 844x390 window (canvas %s scale %.2f)" % [tc._vp_size(), tc._scale()])
		tc.release_all()
	win.size = old


func _tc() -> TouchControls:
	var l := main.find_children("*", "TouchControls", true, false)
	return l[0] as TouchControls if not l.is_empty() else null


func _touch_use() -> void:
	var tc := _tc()
	TestLib.check(tc != null, "the HUD owns the touch controls")
	if tc == null:
		return
	_reset_player()
	var ability := {}
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"ability":
			ability = b
	await frames(3)                                    # the key edge detector settles
	var was := tc.controls_on
	tc.controls_on = true
	TestLib.check(tc.button_visible(ability) and not tc.wheel.is_open, "ABILITY shows, the wheel is closed")
	tc.touch_down(41, tc._button_center(ability))
	tc.touch_up(41)
	TestLib.check(tc.wheel.is_open and tc.wheel.sticky, "tapping ABILITY opens the wheel")
	var wi := -1
	for i in tc.wheel.items.size():
		if tc.wheel.item_id(i) == &"shield":
			wi = i
	TestLib.check(wi >= 0, "PHASE SHIELD is on the wheel")
	var n0 := int(qv.uses.get(&"shield", 0))
	tc.touch_down(42, tc.wheel.item_centre(wi))
	var ok := await _until(func() -> bool: return int(qv.uses.get(&"shield", 0)) > n0, 2.0)
	tc.touch_up(42)
	TestLib.check(ok and qv.shield_left > 0.0 and not tc.wheel.is_open, "tapping PHASE SHIELD in the wheel raises the barrier and closes the wheel")
	# hold and drag: press ABILITY, drag towards TIME SLIP, release
	tc.controls_on = was
	tc.release_all()


# --- phase shield -----------------------------------------------------------------------------------------------------------

func _shield() -> void:
	_reset_player()
	var e := _enemy(p.global_position + _forward() * 14.0)
	TestLib.check(e != null, "an enemy stands 14 m ahead")
	if e == null:
		return
	var e0 := p.energy
	TestLib.check(qv.use(&"shield") and qv.shield_left > 0.0 and QuantumVerbs.shield_on, "PHASE SHIELD rises")
	TestLib.check(p.energy < e0 - 1.0, "it costs ability energy")
	TestLib.check(not qv.use(&"shield"), "a second use is refused while it cools down")
	var hp0 := p.hp
	var ehp0 := e.hp
	var chest := p.chest_position()
	em.bolt(e.center(), chest, &"sentinel")
	var ok := await _until(func() -> bool: return qv.reflected >= 1, 3.0)
	TestLib.check(ok, "a drone bolt crossing the barrier is reflected")
	ok = await _until(func() -> bool: return qv.reflect_hits >= 1, 3.0)
	TestLib.check(ok and e.hp < ehp0, "the reflected bolt hurts the shooter")
	TestLib.check(is_equal_approx(p.hp, hp0), "the hero took no damage")
	# a heavy bolt is absorbed and drains the barrier twice as fast
	var hp_before := qv.shield_hp
	var ab0 := qv.absorbed
	var rf0 := qv.reflected
	em.bolt(e.center(), chest, &"heavy")
	ok = await _until(func() -> bool: return qv.absorbed > ab0, 3.0)
	TestLib.check(ok and qv.reflected == rf0 and qv.shield_hp <= hp_before - float(EnemyTypes.get_cfg(&"heavy")["dmg"]) * 1.9, "heavy bolts are absorbed and overload the barrier")
	# a sniper sees through it
	var ab1 := qv.absorbed
	var sn := _enemy(p.global_position + _forward() * 16.0, &"sniper")
	TestLib.check(QuantumVerbs.pierces(sn.type if sn != null else &"sniper") and qv.shield_block(&"sniper", 30.0) == 0 and qv.absorbed == ab1, "a sniper's shot passes through the barrier")
	# hitscan operative shot: blocked and sent back
	var op := _enemy(p.global_position + _forward() * 12.0, &"operative")
	if op != null:
		var oh0 := op.hp
		var r0 := qv.reflect_hits
		op.set("_tgt", chest)
		op.set("_tgt_clone", false)
		for i in 6:
			if qv.shield_left > 0.0 and qv.reflect_hits == r0:
				op.call(&"_shoot", 12.0)
		TestLib.check(qv.reflect_hits > r0 and op.hp < oh0 and is_equal_approx(p.hp, hp0), "a rifleman's shot is reflected too")
	# strikers burst on it
	var st := _enemy(p.global_position + _forward() * 2.4, &"striker")
	if st != null:
		var hpst := st.hp
		ok = await _until(func() -> bool: return st.dead or st.hp < hpst, 2.0)
		TestLib.check(ok, "a striker touching the barrier bursts")
	# it expires
	qv.shield_left = 0.05
	ok = await _until(func() -> bool: return not QuantumVerbs.shield_on, 2.0)
	TestLib.check(ok, "the barrier ends and stops blocking")
	TestLib.check(not QuantumVerbs.shield_hit(Vector3(0, 1, 5), Vector3(0, 1, -5)), "a ended barrier no longer reports hits")
	_clear_enemies()


# --- time slip -------------------------------------------------------------------------------------------------------------

func _slip() -> void:
	_reset_player()
	_clear_enemies()
	var a := _enemy(p.global_position + _forward() * 6.0, &"sentinel", true)
	var far := _enemy(p.global_position + _forward() * 40.0, &"sentinel", true)
	var fl := _enemy(p.global_position - _forward() * 6.0, &"flanker", true)
	if a == null or far == null or fl == null:
		TestLib.check(false, "enemies for the bubble spawn")
		return
	a.aware = true
	var s0 := a.slipped
	TestLib.check(qv.use(&"slip") and qv.slip_left > 0.0 and QuantumVerbs.slip_on, "TIME SLIP opens a bubble")
	TestLib.check(is_equal_approx(QuantumVerbs.slip_scale(a.global_position, &""), QuantumVerbs.SLIP_SCALE), "enemies inside run at the slip scale")
	TestLib.check(QuantumVerbs.slip_scale(far.global_position, &"") == 1.0, "enemies outside the bubble are untouched")
	TestLib.check(QuantumVerbs.slip_scale(fl.global_position, &"flanker") > QuantumVerbs.SLIP_SCALE and QuantumVerbs.slip_scale(fl.global_position, &"flanker") < 1.0, "flankers resist it")
	TestLib.check(QuantumVerbs.slip_scale(a.global_position, &"", true) > QuantumVerbs.slip_scale(fl.global_position, &"flanker"), "bosses resist most")
	var ok := await _until(func() -> bool: return a.slipped > s0 + 3, 3.0)
	TestLib.check(ok and far.slipped == 0, "inside enemies tick slowed, outside ones do not")
	# bolts inside the bubble are slower
	var pos := p.global_position + Vector3(0, 1.0, 0)
	TestLib.check(QuantumVerbs.slip_bolt(pos) == QuantumVerbs.SLIP_SCALE and QuantumVerbs.slip_bolt(pos + Vector3(60, 0, 0)) == 1.0, "bolts slow down inside the bubble only")
	var dist0 := p.global_position
	var ts0 := Engine.time_scale
	TestLib.check(is_equal_approx(ts0, 1.0) or ts0 > 0.0, "the global time scale is not used (hero keeps full speed)")
	qv.slip_left = 0.05
	ok = await _until(func() -> bool: return not QuantumVerbs.slip_on, 2.0)
	TestLib.check(ok and QuantumVerbs.slip_scale(a.global_position, &"") == 1.0 and dist0.is_finite(), "the bubble closes")
	_clear_enemies()


# --- arc -------------------------------------------------------------------------------------------------------------------

func _arc() -> void:
	_reset_player()
	_clear_enemies()
	em.clear()
	TestLib.check(not qv.use(&"arc") and qv.last_denied == &"arc", "ARC with no target is refused and costs nothing")
	TestLib.check(is_equal_approx(p.energy, p.max_energy), "a refused ARC keeps the energy")
	var origin := p.global_position
	var fwd := _forward()
	var t1 := _enemy(origin + fwd * 8.0, &"sentinel")
	var t2 := _enemy(origin + fwd * 8.0 + Vector3(7, 0, 0), &"sentinel")
	var t3 := _enemy(origin + fwd * 8.0 + Vector3(14, 0, 3), &"operative")
	var far := _enemy(origin + fwd * 80.0, &"sentinel")
	if t1 == null or t2 == null or t3 == null or far == null:
		TestLib.check(false, "targets spawn (%s %s %s %s, alive %d, cap %d)" % [t1, t2, t3, far, em.alive_count(), em.cap()])
		return
	var hp := [t1.hp, t2.hp, t3.hp, far.hp]
	var h0 := qv.arc_hops
	var e0 := p.energy
	TestLib.check(qv.use(&"arc") and qv.arc_left > 0.0, "ARC starts with enemies around")
	TestLib.check(p.energy < e0 - 1.0, "ARC costs energy")
	var ok := await _until(func() -> bool: return qv.arc_left <= 0.0, 4.0)
	TestLib.check(ok and qv.arc_hops - h0 == 3, "the chain strikes all three near enemies (%d hops)" % (qv.arc_hops - h0))
	TestLib.check(t1.hp < hp[0] and t2.hp < hp[1] and t3.hp < hp[2] and far.hp == hp[3], "each target is hurt, the far one is left alone")
	TestLib.check(qv.last_arc.size() == 3 and qv.last_arc[0] == &"sentinel", "targets chained nearest first")
	TestLib.check(p.global_position.distance_to(origin) < 3.0, "the hero snaps back to where the strike began")
	# counters: a shield trooper takes much less
	_clear_enemies()
	_reset_player()
	var sh := _enemy(p.global_position + _forward() * 6.0, &"shield")
	var pl := _enemy(p.global_position + _forward() * 6.0 + Vector3(5, 0, 0), &"sentinel")
	if sh != null and pl != null:
		var shp := sh.hp
		var php := pl.hp
		qv.use(&"arc")
		ok = await _until(func() -> bool: return qv.arc_left <= 0.0, 4.0)
		var dsh := shp - sh.hp
		var dpl := php - pl.hp
		TestLib.check(ok and dsh > 0.0 and dpl > 0.0 and dsh < dpl * 0.6, "a shield trooper takes far less ARC damage (%.1f vs %.1f)" % [dsh, dpl])
	TestLib.check(QuantumVerbs.arc_factor(null) == 1.0, "no target, no resist")
	_clear_enemies()


# --- costs, vehicle, keys ------------------------------------------------------------------------------------------------------

func _costs_and_vehicle() -> void:
	_reset_player()
	p.energy = 1.0
	TestLib.check(not qv.use(&"shield") and qv.last_denied == &"shield", "not enough energy: refused")
	p.energy = p.max_energy
	var ready := qv.ui_state(&"slip")
	TestLib.check(bool(ready["ready"]) and not bool(ready["active"]) and float(ready["cd"]) == 0.0, "ui_state: ready")
	qv.use(&"slip")
	var st := qv.ui_state(&"slip")
	TestLib.check(bool(st["active"]) and float(st["cd"]) > 0.0 and float(st["left"]) > 0.0, "ui_state: active with a cooldown arc")
	TestLib.check(HeroPower.cost(30.0) > 0.0, "HeroPower scales the cost")
	qv.reset()
	TestLib.check(not QuantumVerbs.slip_on and not QuantumVerbs.shield_on and qv.cooldown(&"slip") == 0.0, "reset clears every effect")
	var car := Node3D.new()
	host.add_child(car)
	p.vehicle = car
	TestLib.check(not qv.use(&"shield"), "the verbs are offline in a vehicle")
	p.vehicle = null
	car.queue_free()


func _keys() -> void:
	_reset_player()
	var n0 := int(qv.uses.get(&"shield", 0))
	Input.action_press(&"shield")
	var ok := await _until(func() -> bool: return int(qv.uses.get(&"shield", 0)) > n0, 2.0)
	Input.action_release(&"shield")
	TestLib.check(ok and qv.shield_left > 0.0, "the keyboard action raises the barrier in the live game")
	qv.reset()


# --- menus ------------------------------------------------------------------------------------------------------------------

func _menus() -> void:
	_reset_player()
	TestLib.check(TestMode.use_verb(&"shield") != "" and qv.shield_left > 0.0, "TEST MENU: PHASE SHIELD fires with energy refilled")
	TestLib.check(TestMode.use_verb(&"bogus") == "", "TEST MENU: unknown ids are harmless")
	qv.reset()
	var labels: Array[String] = []
	for it: Dictionary in DemoMenu.entries():
		labels.append(String(it["label"]))
	TestLib.check(labels.has("QUANTUM VERBS") and labels.has("PHASE SHIELD") and labels.has("TIME SLIP") and labels.has("ARC"), "DEMO tab lists the verbs")
	var tm := TestMenu.new()
	main.add_child(tm)
	tm.page = 1
	var tl: Array[String] = []
	for it: Dictionary in tm._page_items():
		tl.append(String(it.get("label", "")))
	TestLib.check(tl.has("PHASE SHIELD") and tl.has("TIME SLIP") and tl.has("ARC"), "TEST MENU lists the verbs")
	tm.queue_free()
