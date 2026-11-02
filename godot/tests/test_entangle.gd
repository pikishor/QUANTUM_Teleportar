extends RefCounted
## ENTANGLE tests (headless): swap places with the aimed enemy, cooldown, energy, line of sight, range, beam, safe-spot clamping, HUD name.
## Run: tools/test.sh tests/test_entangle.gd

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
	var mgr := (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	e.root.add_child(mgr)
	await e.frames(3)
	var q := Quantum.new()
	p.add_child(q)
	await e.frames(2)
	p.energy = 100.0
	q.cd_link = 0.0
	var d: Drone = mgr.spawn(&"sentinel", p.global_position + Vector3(0.0, 0.0, -15.0)) if mgr.has_method(&"spawn") else null
	TestLib.check(d != null, "a drone spawned")
	if d == null:
		Game.missions = null
		return
	p.camera_rig.aim_at(d.center())
	await e.frames(3)
	var from := p.global_position
	var dpos := d.global_position
	var e0 := p.energy
	TestLib.check(not q.swap_target().is_empty(), "the aimed drone is a swap target")
	TestLib.check(q.entangle(), "entangle swaps with the aimed drone")
	TestLib.check(p.global_position.distance_to(dpos) < 2.5, "the player took the drone's place")
	TestLib.check(d.global_position.distance_to(from) < 2.5, "the drone took the player's place")
	TestLib.check(is_equal_approx(e0 - p.energy, Quantum.SWAP_COST), "costs coherence once")
	TestLib.check(q.cd_link > 3.0 and q._swap_left > 0.0 and q.fx_flash > 0.9, "cooldown, beam and screen effect start")
	TestLib.check(not d.aware, "the drone is confused")
	q._process(0.016)
	TestLib.check(q._swap_beams.size() == 2, "the beam pair exists")
	TestLib.check(not q.entangle(), "no swap during the cooldown")
	q.cancel_aim()
	q._slow_end()
	q.cd_link = 0.0
	p.energy = 5.0
	TestLib.check(not q.entangle(), "no swap without coherence")
	p.energy = 100.0
	# range
	d.global_position = p.global_position + Vector3(0.0, 0.0, -60.0)
	p.camera_rig.aim_at(d.center())
	await e.frames(3)
	TestLib.check(q.swap_target().is_empty() and not q.entangle(), "a target beyond 40 m is refused")
	# safe spot
	TestLib.check(not PlayerUtil.outside_city(PlayerUtil.safe_spot(Vector3(9999.0, 50.0, -9999.0))), "a far spot is clamped inside the city")
	var names := ""
	for a: Dictionary in UiUtil.ABILITIES:
		names += a["label"]
	TestLib.check(names.contains("ENTANGLE"), "the HUD names it ENTANGLE")
	q._slow_end()
	Game.missions = null
