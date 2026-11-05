extends RefCounted
## COLLAPSE tests (headless): cost and cooldown, area damage and stagger, drones switched off, SUPERPOSITION decoy detonates, ENTANGLE links shatter, HUD/touch entries.
## Run: tools/test.sh tests/test_collapse.gd

const Env := preload("res://tests/player_env.gd")
const Stubs := preload("res://tests/enemies_stubs.gd")

var e := Env.new()


func run(host: Node) -> void:
	seed(5)
	await e.setup(host)
	var p: Player = e.p
	Game.world = null
	var stub := Stubs.StubMissions.new()
	e.root.add_child(stub)
	Game.missions = stub
	await e.frames(3)
	var q := Quantum.new()
	p.add_child(q)
	await e.frames(2)
	p.quantum = q
	Upgrades.reset()
	p.energy = 100.0
	var mgr := (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	e.root.add_child(mgr)
	Game.enemies = mgr
	await e.frames(2)
	var d1 := mgr.spawn(&"sentinel", p.global_position + Vector3(5.0, 0.0, 0.0))
	var d2 := mgr.spawn(&"sentinel", p.global_position + Vector3(60.0, 0.0, 0.0))
	for d: Drone in [d1, d2]:
		d.hp = 100.0
		d.max_hp = 100.0
	var h1 := d1.hp
	TestLib.check(q.collapse_all(), "collapse fires")
	TestLib.check(is_equal_approx(100.0 - p.energy, Quantum.WAVE_COST), "costs coherence once")
	TestLib.check(d1.hp < h1 and d1.is_disabled(), "enemy in range is damaged and switched off")
	TestLib.check(is_equal_approx(d2.hp, 100.0) and not d2.is_disabled(), "enemy out of range is untouched")
	TestLib.check(q.collapse_fx > 0.9 and q.cd_collapse > 0.0, "screen effect and cooldown start")
	TestLib.check(not q.collapse_all(), "no second collapse during the cooldown")
	q.cd_collapse = 0.0
	p.energy = 10.0
	TestLib.check(not q.collapse_all(), "no collapse without coherence")
	# SUPERPOSITION combo
	p.energy = 100.0
	q.cd_super = 0.0
	q.superpose()
	TestLib.check(q.clone != null, "decoy out")
	TestLib.check(q.collapse_all() and q.clone == null, "collapse detonates the decoy")
	# ENTANGLE combo
	q.cd_collapse = 0.0
	p.energy = 100.0
	d1 = mgr.spawn(&"sentinel", p.global_position + Vector3(5.0, 0.0, 3.0))
	d2 = mgr.spawn(&"sentinel", p.global_position + Vector3(60.0, 0.0, 3.0))
	d1.hp = 400.0
	d2.hp = 400.0
	d1.linked = d2
	d2.linked = d1
	q.links.append({"a": d1, "b": d2, "t": 5.0, "slot": 0})
	q._slot_used.resize(1)
	q._slot_beams(0)
	TestLib.check(q.collapse_all() and q.links.is_empty() and d1.linked == null, "collapse shatters the links")
	TestLib.check(d2.hp < 400.0, "the far partner took the entangled damage")
	# HUD / touch / input
	var found := false
	for a: Dictionary in UiUtil.ABILITIES:
		found = found or a["action"] == &"collapse"
	TestLib.check(found and InputMap.has_action(&"collapse"), "HUD ability and input action exist")
	var btn := false
	for w: Dictionary in TouchControls.WHEEL_ABILITIES:
		if w["id"] == &"collapse":
			btn = int(w["ui"]) < UiUtil.ABILITIES.size()
	TestLib.check(btn, "COLLAPSE is on the ABILITY wheel (the default HUD has one ABILITY button)")
	Game.state = &"pause"
	q.cd_collapse = 0.0
	TestLib.check(not q.collapse_all(), "paused: refuses to fire")
	Game.state = &"play"
