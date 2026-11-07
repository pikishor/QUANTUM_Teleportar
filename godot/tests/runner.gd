extends Node
## Test runner scene: loads the test script given as `--test=res://tests/x.gd` and awaits its run(host).
## A test script is `extends RefCounted` and defines `func run(host: Node) -> void` (it may await).
## It reports through TestLib.check(); the process exit code is 0 only if every check passed.


func _ready() -> void:
	Game.autostart = true
	var path := ""
	var limit := 60.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			path = a.substr(7)
		elif a.begins_with("--timeout="):
			limit = float(a.substr(10))
	var script := load(path) as GDScript
	if script == null:
		printerr("FAIL: cannot load test script '%s'" % path)
		get_tree().quit(2)
		return
	var consts0 := script.get_script_constant_map()
	if consts0.has("TIMEOUT_SECONDS"):                   # a long real-scene test (tests/test_mission_audit.gd) declares its own limit; test.sh's wrapper still stops everything at 150 s
		limit = maxf(limit, minf(float(consts0["TIMEOUT_SECONDS"]), 140.0))
	# Watchdog: a runtime error inside an awaited test leaves the await pending forever. It runs in REAL seconds (ignore_time_scale): a test that sets Engine.time_scale = 4
	# (test_enemies) would otherwise get a 15 s wall-clock budget and time out whenever its marks / frame waits took a little longer.
	get_tree().create_timer(limit, true, false, true).timeout.connect(func() -> void:
		printerr("FAIL: test timed out after %ss (a SCRIPT ERROR above usually explains why)" % limit)
		get_tree().quit(3))
	if not script.can_instantiate():
		printerr("FAIL: '%s' has compile errors (see above). New class_name scripts also need tools/import.sh first." % path)
		get_tree().quit(2)
		return
	var test = script.new()
	await test.run(self)
	TestLib.finish(get_tree())
