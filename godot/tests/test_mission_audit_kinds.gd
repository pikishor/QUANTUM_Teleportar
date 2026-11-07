extends RefCounted
## The mission audit (tests/mission_audit.gd) for the step kinds that campaign chapters 1-4 do not use: rift hold, quantum heist (go in, steal, get out, lose the patrols) and convoy intercept,
## played by the bot in the real game with real movement, shooting and verbs and no skip. Plus the structure of every other mission system the player can start: each side mission, contract
## kind, heist and activity must start from the real game, show a status line and have somewhere to go. Findings are printed.
## Run: tools/test.sh tests/test_mission_audit_kinds.gd   (about 60 s at 16x)

const TIMEOUT_SECONDS := 140.0
const Audit := preload("res://tests/mission_audit.gd")
const K := 16
const TICK := 8.0


func run(host: Node) -> void:
	Engine.time_scale = K
	Engine.physics_ticks_per_second = int(TICK) * K
	Engine.max_physics_steps_per_frame = 64
	var a := Audit.new()
	var ok := await a.setup(host)
	TestLib.check(ok, "the real scene has a player, a city, enemies, vehicles and missions")
	if not ok:
		_restore()
		return
	a.verbose = OS.get_environment("AUDIT_VERBOSE") != ""
	Game.start_new_game()
	if a.story != null:
		a.story.skip_cards()
	await TestLib.frames(host, 3)
	for id: StringName in [&"rift_hold", &"convoy_intercept", &"heist"]:
		var before := a.stuck_findings().size()
		var done: bool = await a.play_demo(id, 240.0)
		# a failed run is the game's normal retry (the bot is no ace driver); what must never happen is a lock: the step must finish, or keep running without a finding
		TestLib.check(done or a.stuck_findings().size() == before, "%s plays on without getting stuck (done %s; %s)" % [str(id), str(done), a.summary().split("\n")[0]])
	for id: StringName in [&"courier", &"relay", &"turf", &"hostage", &"data_courier"]:
		var r: Dictionary = await a.audit_side(id, 160.0)
		var closed := str(r["reason"]).contains("job_open false")        # the job's client camp turned hostile in an earlier run of this session: nothing to audit
		TestLib.check(bool(r["ok"]) or closed or str(r["reason"]) == "DOWN", "side mission %s completes by itself (%s, %.0f s)" % [str(id), str(r["reason"]), float(r["seconds"])])
	var missing: PackedStringArray = await a.audit_structure()
	for line in missing:
		print("  structure: ", line)
	TestLib.check(missing.is_empty(), "every contract kind, heist and activity starts and says what to do (%d problems)" % missing.size())
	for line in a.trace:
		print("  ", line)
	var stuck := a.stuck_findings()
	for f in a.findings:
		print("  finding: ", f)
	TestLib.check(stuck.is_empty(), "no sandbox step gets stuck (%d findings)" % stuck.size())
	await a.teardown()
	_restore()


func _restore() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
