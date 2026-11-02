extends RefCounted
## SUPERPOSITION decoy tests (headless): lifetime, timeout pulse vs manual blast, upgrade hook, cooldown, HUD ability state, ghost shader.
## Run: tools/test.sh tests/test_superposition.gd

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
	TestLib.check(q.superpose() and q.clone != null, "decoy spawns")
	TestLib.check(absf(q.clone_left - 6.0) < 0.01, "decoy lasts 6 s")
	TestLib.check(bool(UiUtil.ability_state(p, UiUtil.ABILITIES[2])["active"]), "HUD ability shows the decoy active")
	q.clone_left = 0.01
	q._physics_process(0.05)
	TestLib.check(q.clone == null and q.cd_super > 0.0, "decoy collapses on timeout and starts the cooldown")
	TestLib.check(Quantum.PULSE_RADIUS < Quantum.BLAST_RADIUS and Quantum.PULSE_DMG < 70.0, "timeout pulse is smaller than a manual collapse")
	q.cd_super = 0.0
	Upgrades.levels = {&"decoy": 2}
	TestLib.check(q.superpose() and absf(q.clone_left - 7.0) < 0.01, "upgrade hook extends the lifetime")
	Upgrades.reset()
	q.collapse()
	TestLib.check(q.clone == null, "manual collapse removes the decoy")
	TestLib.check(Quantum.GHOST_SHADER.contains("flick") and Quantum.GHOST_SHADER.contains("seam"), "ghost shader flickers and has phase seams")
