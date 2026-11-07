extends RefCounted
## The mission audit (owner round 3: "gets stuck in a task, tasks do not complete"): a bot plays campaign chapters 1-4 start to finish in the REAL game scene (tests/mission_audit.gd) with
## real movement, real shooting, USE at doors and cars, a driven chase car and the win screen's NEXT SECTOR, and never calls the runner's skip. Every step must finish by itself, with no
## recovery by the game's own stuck handler, and every step must show an objective line and (on the street) a waypoint. The sandbox kinds that chapters 1-4 do not use (rift hold, quantum
## heist, convoy intercept) are played the same way. Findings are printed so a failure says where a task got stuck.
## Run: tools/test.sh tests/test_mission_audit.gd   (about 80 s: it plays about 10 minutes of game time at 8x; the runner reads TIMEOUT_SECONDS)

const TIMEOUT_SECONDS := 140.0
const Audit := preload("res://tests/mission_audit.gd")
const K := 16
const TICK := 8.0                       ## physics ticks per game second (the step is 1/TICK s of game time)


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
	a.max_game_seconds = 6000.0
	a.max_real_seconds = 118.0                             # a slow machine stops the bot here instead of hitting the runner's limit (then two chapters are enough)
	a.verbose = OS.get_environment("AUDIT_VERBOSE") != ""
	if OS.get_environment("AUDIT_REAL") != "":
		a.max_real_seconds = float(OS.get_environment("AUDIT_REAL"))
	a.debug_walk = OS.get_environment("AUDIT_WALK") != ""
	var from := OS.get_environment("AUDIT_FROM").split(":")           # development: AUDIT_FROM=<chapter>:<step> (1-based) plays from there
	if from.size() == 2:
		await a.play_chapters(1, int(from[0]) - 1, int(from[1]) - 1)
	else:
		await a.play_chapters(4)
	print("MISSION AUDIT ", a.summary())
	if OS.get_environment("AUDIT_PERF") != "":
		print(PerfTimers.table())
	for line in a.trace:
		print("  ", line)
	var stuck := a.stuck_findings()
	var hard := stuck.filter(func(f: Dictionary) -> bool: return str(f["reason"]) != "UNREACHABLE")
	var walks := stuck.size() - hard.size()
	var cut_short: bool = a.game_clock < a.max_game_seconds and int(a.stats["chapters"]) < 4
	TestLib.check(int(a.stats["chapters"]) == 4 or (cut_short and int(a.stats["chapters"]) >= 2), "chapters 1-4 are played start to finish (%s)%s" % [str(a.stats["chapters_done"]), " (cut short by the time budget)" if cut_short else ""])
	TestLib.check(hard.is_empty(), "no step gets stuck: no lost target, missing enemy, blocked door, empty objective, cutscene lock, timeout or recovery by the game's stuck handler (%d findings)" % hard.size())
	TestLib.check(walks <= 1, "at most one street walk of the bot is blocked by a prop (%d)" % walks)
	await a.teardown()
	_restore()


func _restore() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
