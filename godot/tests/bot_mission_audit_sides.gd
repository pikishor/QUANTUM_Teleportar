extends RefCounted
## Long audit run (tools/mission_audit.sh): every one of the twenty side missions played by the mission audit bot (tests/mission_audit.gd) with real input, one result line each.
##   SIDES=courier,photo tools/test.sh tests/bot_mission_audit_sides.gd      (a subset; default all twenty, about 60 s)
## Not a CI test: some jobs are lost to the bot's driving (smuggler, car theft), which a player would also lose to traffic now and then; the lines show which and why.

const TIMEOUT_SECONDS := 140.0
const Audit := preload("res://tests/mission_audit.gd")


func run(host: Node) -> void:
	Engine.time_scale = 16
	Engine.physics_ticks_per_second = 8 * 16
	Engine.max_physics_steps_per_frame = 64
	var a := Audit.new()
	await a.setup(host)
	Game.start_new_game()
	a.story.skip_cards()
	await TestLib.frames(host, 3)
	var ids: Array = Array(OS.get_environment("SIDES").split(",")) if OS.get_environment("SIDES") != "" else SideMissions.ORDER
	var ok_n := 0
	for id: Variant in ids:
		var r: Dictionary = await a.audit_side(StringName(str(id)), 200.0)
		ok_n += 1 if bool(r["ok"]) else 0
		print("SIDE ", r)
	for f in a.findings:
		print("  finding: ", f)
	print("SIDES %d / %d completed" % [ok_n, ids.size()])
	await a.teardown()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8
