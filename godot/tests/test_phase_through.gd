extends RefCounted
## Phase-through tests (headless): thin walls pass during phase, buildings do not, enemies keep colliding, exceptions cleared, cooldown / energy gating.
## Run: tools/test.sh tests/test_phase_through.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")

var e := Env.new()


func run(host: Node) -> void:
	await e.setup(host)
	var p: Player = e.p
	Game.world = null
	var q := Quantum.new()
	p.add_child(q)
	await e.frames(2)
	var thin := Fixture.add_box(e.root, Vector3(0.0, 1.0, -10.0), Vector3(8.0, 2.0, 0.3))
	thin.add_to_group(PhaseThrough.THIN_GROUP)
	var solid := Fixture.add_box(e.root, Vector3(20.0, 3.0, -10.0), Vector3(8.0, 6.0, 0.3))
	# without phase the thin wall blocks
	await e.prep(Vector3(0.0, 0.05, -7.0), 0.0)
	Input.action_press(&"move_forward")
	await e.secs(1.5)
	TestLib.check(p.global_position.z > -9.8, "a thin wall blocks without phase")
	Input.action_release(&"move_forward")
	# phase-step passes
	await e.prep(Vector3(0.0, 0.05, -9.0), 0.0)
	p.energy = 50.0
	TestLib.check(q.phase_step(), "phase-step starts")
	TestLib.check(is_equal_approx(p.energy, 50.0 - PhaseThrough.STEP_COST), "phase-step costs coherence")
	TestLib.check(not q.phase_step(), "no second step during the cooldown")
	Input.action_press(&"move_forward")
	await e.secs(0.5)
	Input.action_release(&"move_forward")
	TestLib.check(p.global_position.z < -10.5, "the hero passes the thin wall while phasing")
	await e.secs(1.5)
	TestLib.check(not q.phase.active(), "phase ends and every exception is dropped")
	# the wall is solid again
	await e.prep(Vector3(0.0, 0.05, -7.0), 0.0)
	Input.action_press(&"move_forward")
	await e.secs(1.0)
	Input.action_release(&"move_forward")
	TestLib.check(p.global_position.z > -9.8, "solid again afterwards")
	# solid (non-thin) walls never pass
	await e.prep(Vector3(20.0, 0.05, -7.0), 0.0)
	q.phase.begin(2.0)
	Input.action_press(&"move_forward")
	await e.secs(1.0)
	Input.action_release(&"move_forward")
	TestLib.check(p.global_position.z > -9.8, "buildings are never passable")
	q.phase.end()
	# enemies are not affected: the exception lives on the player only
	q.phase.begin(1.0)
	TestLib.check(thin.collision_layer == Game.L_WORLD and thin.collision_mask == 0, "no layer is changed")
	q.phase.end()
	# teleport starts a phase; ending inside a wall pushes out safely
	await e.prep(Vector3(0.0, 0.05, -7.0), 0.0)
	q.phase.begin(0.2)
	p.global_position = Vector3(0.0, 0.05, -10.0)
	await e.secs(0.3)
	TestLib.check(q.phase.active(), "phase waits while inside a thin wall")
	await e.secs(1.4)
	TestLib.check(not q.phase.active(), "phase ends after the grace")
	TestLib.check(is_finite(p.global_position.y) and p.global_position.y > -1.0, "player is placed safely")
	TestLib.check(q.phase.cd >= 0.0, "cooldown value sane")
	await e.teardown()
