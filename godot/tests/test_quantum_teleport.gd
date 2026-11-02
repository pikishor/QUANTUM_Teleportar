extends RefCounted
## QUANTUM TELEPORT tests (headless): hold-to-aim marker, release teleports, slow motion restored, screen effect, cooldown, safe-spot clamping, on-screen names.
## Run: tools/test.sh tests/test_quantum_teleport.gd

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
	p.energy = 100.0
	q.cd_blink = 0.0
	var scale0 := Engine.time_scale
	# hold -> aim
	q.aiming = false
	q._slow_begin(0.0)
	TestLib.check(Engine.time_scale < scale0, "aiming slows time")
	q.cancel_aim()
	TestLib.check(is_equal_approx(Engine.time_scale, scale0), "cancel restores the time scale")
	q.aiming = true
	q.aim_pos = Vector3(10.0, 0.0, 10.0)
	var e0 := p.energy
	var from := p.global_position
	TestLib.check(q.aim_go(), "release teleports to the aimed marker")
	TestLib.check(p.global_position.distance_to(Vector3(10.0, 0.05, 10.0)) < 1.5 and p.global_position.distance_to(from) > 5.0, "the player is at the marker")
	TestLib.check(is_equal_approx(e0 - p.energy, Quantum.BLINK_COST), "costs coherence once")
	TestLib.check(q.fx_flash > 0.9 and not q.aiming and q.cd_blink > 0.0, "screen effect starts, aiming ends, cooldown runs")
	TestLib.check(Engine.time_scale < scale0, "short slow motion after the teleport")
	q._slow_until = 1
	q._process(0.016)
	TestLib.check(is_equal_approx(Engine.time_scale, scale0), "slow motion ends and time is restored")
	# cooldown / energy gating
	q.aiming = true
	TestLib.check(not q.aim_go() and not q.aiming, "no teleport during the cooldown")
	q.cd_blink = 0.0
	p.energy = 5.0
	q.aiming = true
	TestLib.check(not q.aim_go(), "no teleport without coherence")
	p.energy = 100.0
	# safe spot
	q.cd_blink = 0.0
	q.aiming = true
	q.aim_pos = PlayerUtil.safe_spot(Vector3(9999.0, 50.0, -9999.0))
	TestLib.check(not PlayerUtil.outside_city(q.aim_pos), "a far aim is clamped inside the city")
	q.cancel_aim()
	# names
	var names := ""
	for a: Dictionary in UiUtil.ABILITIES:
		names += a["label"]
	TestLib.check(names.contains("QUANTUM TELEPORT") and not names.contains("BLINK"), "the HUD names it QUANTUM TELEPORT")
	TestLib.check(Quantum.fix_for(0, 0) == "NOTHING", "state unchanged")
	Game.missions = null
	TestLib.check(is_equal_approx(Engine.time_scale, scale0), "time scale untouched at the end")
