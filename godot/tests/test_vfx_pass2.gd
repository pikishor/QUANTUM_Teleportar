extends RefCounted
## Quantum realism VFX pass 2 (FX.qvfx, scripts/fx/quantum_vfx.gd): pooled layer idle cost, per-tier budgets, the verbs' call sites in the real player scene
## (teleport, entangle, collapse, superposition, TIME SLIP / PHASE SHIELD auras), weapon classes, death dissolve, reduce flash, everything ends by itself.
## Death dust is HIGH only. Waits on counters and on advancing the layer's own clock, never on frame counts. Run: tools/test.sh tests/test_vfx_pass2.gd

const Env := preload("res://tests/player_env.gd")
const Stubs := preload("res://tests/enemies_stubs.gd")
const QV := preload("res://scripts/fx/quantum_vfx.gd")

var e := Env.new()


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


## Run the layer's clock without waiting: `seconds` of game time in steps of 0.1.
func _advance(qv: Node, seconds: float) -> void:
	for i in roundi(seconds / 0.1):
		qv._process(0.1)


func run(host: Node) -> void:
	seed(7)
	await e.setup(host)
	var p: Player = e.p
	Game.world = null
	var stub := Stubs.StubMissions.new()
	e.root.add_child(stub)
	Game.missions = stub
	var old_q := Game.quality
	var old_rf := UiSettings.s_reduce_flash
	UiSettings.s_reduce_flash = false
	var qv: Node = FX.qvfx
	TestLib.check(qv != null and qv.get_script() == QV, "FX owns the quantum VFX layer")
	FX.reset()
	TestLib.check(qv.live_nodes() == 0, "idle: no effect node is visible, so the layer costs no draw call (%d)" % qv.live_nodes())

	# --- budgets per tier
	TestLib.check(QV.ring_cap(0) < QV.ring_cap(1) and QV.ring_cap(1) < QV.ring_cap(2), "ring budget grows with the tier")
	TestLib.check(QV.trail_cap(0) < QV.trail_cap(2) and QV.dust_cap(0) < QV.dust_cap(1) and QV.dust_cap(1) < QV.dust_cap(2), "trail and dust budgets grow with the tier")
	var nodes0 := _count_nodes(qv)
	for q in 3:
		Game.quality = q
		FX.reset()
		for i in 12:
			qv.ring(Vector3(i, 0, 0), Vector3.UP, 2.0, QV.CYAN, QV.MAGENTA, i % 4, 0.5)
			qv.trail(Vector3(i, 0, 0), Vector3(i, 1, 4), QV.CYAN, QV.MAGENTA, i % 4, 0.5)
			qv.dust(Vector3(i, 1, 0), 60, QV.CYAN, QV.MAGENTA)
		TestLib.check(qv.live_rings() <= QV.ring_cap(q), "tier %d: live rings %d within the cap %d" % [q, qv.live_rings(), QV.ring_cap(q)])
		TestLib.check(qv.live_trails() <= QV.trail_cap(q), "tier %d: live trails %d within the cap %d" % [q, qv.live_trails(), QV.trail_cap(q)])
		TestLib.check(qv.dust_live() <= QV.dust_cap(q) and qv.dust_live() > 0, "tier %d: dust %d within the cap %d" % [q, qv.dust_live(), QV.dust_cap(q)])
		TestLib.check(qv.live_nodes() <= QV.ring_cap(q) + QV.trail_cap(q) + 1, "tier %d: at most one draw per ring, trail and one for all dust (%d)" % [q, qv.live_nodes()])
		_advance(qv, 3.0)
		TestLib.check(qv.live_nodes() == 0 and qv.dust_live() == 0, "tier %d: every effect ends by itself" % q)
	TestLib.check(_count_nodes(qv) == nodes0, "no node is created while playing (%d -> %d)" % [nodes0, _count_nodes(qv)])

	# --- verbs in the real player scene
	Game.quality = 2
	FX.reset()
	var q := Quantum.new()
	p.add_child(q)
	var qverbs := QuantumVerbs.new()
	p.add_child(qverbs)
	p.set(&"qverbs", qverbs)
	p.set(&"quantum", q)
	await e.frames(2)
	p.energy = 100.0
	q.cd_blink = 0.0
	var r0: int = qv.rings_started
	var t0: int = qv.trails_started
	var d0: int = qv.dust_started
	q.aiming = true
	q.aim_pos = Vector3(12.0, 0.0, 12.0)
	TestLib.check(q.aim_go(), "QUANTUM TELEPORT fires")
	TestLib.check(qv.rings_started >= r0 + 2 and qv.trails_started > t0 and qv.dust_started > d0, "teleport: entry and exit portals, trail and dust start (%d rings)" % (qv.rings_started - r0))
	TestLib.check(qv.aura_on(), "teleport: the hero aura pulses")
	q._slow_end()
	_advance(qv, 1.5)
	TestLib.check(qv.live_nodes() == 0, "teleport: everything is gone after 1.5 s")

	r0 = qv.rings_started
	p.energy = 100.0
	q.cd_super = 0.0
	TestLib.check(q.superpose(), "SUPERPOSITION fires")
	TestLib.check(qv.rings_started > r0 and q.clone != null, "superposition: a ring at the split")
	var dn: int = qv.dust_started
	for i in 12:
		qv._process(0.2)
	TestLib.check(qv.dust_started > dn + 5, "superposition: the afterimage shimmer keeps shedding motes while the decoy lives")
	TestLib.check(qv.aura_on(), "superposition: the aura is held while the decoy lives")
	r0 = qv.rings_started
	p.energy = 100.0
	q.cd_collapse = 0.0
	TestLib.check(q.collapse_all(), "COLLAPSE fires")
	TestLib.check(qv.rings_started >= r0 + 2, "collapse: the pulse rings start (%d)" % (qv.rings_started - r0))
	q.collapse()
	_advance(qv, 2.0)

	p.energy = 100.0
	var a0: int = qv.auras_started
	qverbs.clear_cooldown(&"slip")
	TestLib.check(qverbs.use(&"slip"), "TIME SLIP opens")
	TestLib.check(qv.auras_started > a0, "TIME SLIP: aura pulse on cast")
	qv._process(0.3)
	TestLib.check(qv.aura_on(), "TIME SLIP: the aura stays while the bubble lasts")
	qverbs.reset()
	_advance(qv, 1.5)
	TestLib.check(not qv.aura_on(), "the aura ends with the effect")

	# entangle visuals (call site is in Quantum.entangle; the braid is driven directly so no enemy is needed)
	r0 = qv.rings_started
	t0 = qv.trails_started
	qv.entangle(Vector3(0, 1, 0), Vector3(10, 1, 3), 0.45)
	TestLib.check(qv.trails_started == t0 + 1 and qv.rings_started == r0 + 2, "entangle: one braid and a closing ring at each end")
	_advance(qv, 1.5)

	# --- weapons: every weapon has a class, a look and the muzzle / impact calls work
	for id in WeaponDefs.IDS:
		TestLib.check(QV.WEAPON_CLASS.has(id) and QV.CLASSES.has(QV.class_of(id)), "weapon %s has a VFX class" % id)
	var kinds := {}
	for id in WeaponDefs.IDS:
		kinds[QV.class_of(id)] = true
	TestLib.check(kinds.size() >= 6, "at least 6 distinct weapon VFX classes (%d)" % kinds.size())
	for id in WeaponDefs.IDS:
		qv.weapon_shot(id, Vector3(0, 1, 0), Vector3(0, 1, -30))
		qv.weapon_impact(Vector3(0, 1, -30), Vector3(0, 0, 1))
		_advance(qv, 0.6)
	qv.bolt(Vector3(0, 1, 0), Vector3(5, 1, 2))
	t0 = qv.trails_started
	qv.weapon_shot(&"lance", Vector3(0, 1, 0), Vector3(0, 1, -40))
	qv.weapon_shot(&"arc", Vector3(0, 1, 0), Vector3(0, 1, -20))
	TestLib.check(qv.trails_started == t0 + 2, "lance and arc draw their own beam and bolt")
	_advance(qv, 1.0)

	# --- death dissolve: MED / HIGH only, LOW keeps its blast
	Game.quality = 0
	FX.reset()
	var ds: int = qv.dust_started
	qv.death_dust(Vector3(0, 1, 0), 1.7, 0.45, QV.CYAN)
	TestLib.check(qv.dust_started == ds, "LOW: no extra death dust (the draw budget is tight)")
	Game.quality = 1
	qv.death_dust(Vector3(0, 1, 0), 1.7, 0.45, QV.CYAN)
	TestLib.check(qv.dust_started == ds, "MED: no extra death dust (the death spike budget is tight)")
	for q2 in [2]:
		Game.quality = q2
		FX.reset()
		qv.death_dust(Vector3(0, 1, 0), 1.7, 0.45, QV.CYAN)
		TestLib.check(qv.dust_started == ds + 1, "tier %d: the body dissolves into quantum dust (one pooled emitter, replaces the embers)" % q2)
		var live := 0
		for c in FX.get_children():
			live += 1 if c is CPUParticles3D and (c as CPUParticles3D).visible else 0
		TestLib.check(live == 1, "tier %d: dissolve is one pooled emitter (%d)" % [q2, live])
		_advance(qv, 3.0)
		TestLib.check(qv.live_nodes() == 0, "tier %d: nothing of the layer is left" % q2)

	# --- blast shockwave variety
	var r1 := 0
	Game.quality = 2
	FX.reset()
	r0 = qv.rings_started
	FX.blast(Vector3(5, 0.5, 5), 6.5, Color(1.0, 0.5, 0.2), 0.5, 0)
	FX.blast(Vector3(-5, 0.5, 5), 3.0, Color(0.3, 0.94, 1.0), 0.5)
	r1 = qv.rings_started
	FX.blast(Vector3(0, 0.5, 5), 3.5, Color(1.0, 0.5, 0.2), 0.5)
	TestLib.check(qv.rings_started == r1, "HIGH: a small fire blast (enemy death size) adds no ring")
	TestLib.check(r1 == r0 + 2, "fire and quantum blasts both get a shockwave ring on HIGH")
	Game.quality = 1
	FX.reset()
	r0 = qv.rings_started
	FX.blast(Vector3(5, 0.5, 5), 3.0, Color(1.0, 0.5, 0.2), 0.5)
	TestLib.check(qv.rings_started == r0, "MED: a generic fire blast adds no ring (death spike budget)")
	Game.quality = 0
	FX.reset()
	r0 = qv.rings_started
	FX.blast(Vector3(5, 0.5, 5), 3.0, Color(1.0, 0.5, 0.2), 0.5)
	TestLib.check(qv.rings_started == r0, "LOW: a generic fire blast adds no ring")
	FX.reset()

	# --- reduce flash
	Game.quality = 2
	UiSettings.s_reduce_flash = true
	var slot: int = qv.ring(Vector3.ZERO, Vector3.UP, 2.0, QV.CYAN, QV.MAGENTA, QV.MODE_SHOCK, 0.5)
	var gain := float(qv._ring_mats[slot].get_shader_parameter(&"gain"))
	TestLib.check(is_equal_approx(gain, QV.REDUCE_GAIN), "reduce flash dims rings to %.2f (%.2f)" % [QV.REDUCE_GAIN, gain])
	var ts: int = qv.trail(Vector3.ZERO, Vector3(0, 0, 5), QV.CYAN, QV.MAGENTA, QV.TRAIL_BRAID, 0.5)
	TestLib.check(float(qv._trail_mats[ts].get_shader_parameter(&"flicker")) == 0.0, "reduce flash stops the braid flicker")
	UiSettings.s_reduce_flash = false
	FX.reset()
	TestLib.check(qv.live_nodes() == 0, "FX.reset hides every quantum effect")

	# --- the DEMO menu (and the TEST menu page 2, same source) lists every showcase effect and each one plays
	var labels := {}
	for it: Dictionary in DemoMenu.entries():
		if it.has("fn"):
			labels[String(it["label"])] = it["fn"]
	Game.quality = 2
	for id: StringName in QV.SHOWCASE:
		var title := String(QV.SHOWCASE_TITLES[id])
		TestLib.check(labels.has(title), "DEMO menu has %s" % title)
		FX.reset()
		var before: int = qv.rings_started + qv.trails_started + qv.dust_started + qv.auras_started
		var line: String = qv.play_demo(id)
		var after: int = qv.rings_started + qv.trails_started + qv.dust_started + qv.auras_started
		TestLib.check(line.begins_with("VFX") and (after > before or id.begins_with("blast")), "showcase %s plays" % id)
		_advance(qv, 3.0)
		FX.explosions._process(0.1)
	FX.reset()

	Game.quality = old_q
	UiSettings.s_reduce_flash = old_rf
	Game.missions = null
	await e.teardown()
