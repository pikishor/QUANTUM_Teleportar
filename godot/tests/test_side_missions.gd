extends RefCounted
## Side missions: the ten definitions and their rules, every stage primitive driven by tick(), reward / reputation / tally, the clock, abort, and the save round trip
## ([side] section, damaged values). Run: tools/test.sh tests/test_side_missions.gd

const Env := preload("res://tests/player_env.gd")
const TMP := "user://test_side_save.cfg"

class FakeStory extends Node:
	var chapter := 9

var e := Env.new()
var m: Missions
var sm: SideMissions
var prog: Progress


func run(host: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	await e.setup(host)
	var story := FakeStory.new()
	e.root.add_child(story)
	Game.story = story
	m = (load("res://scenes/missions.tscn") as PackedScene).instantiate() as Missions
	e.root.add_child(m)
	await e.frames(3)
	sm = m.sides
	prog = m.progress
	prog.path = TMP
	prog.autosave_enabled = false
	prog.new_campaign()
	_rules()
	_all_kinds()
	_clock_and_abort()
	_save_load()
	Game.story = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	await e.teardown()


func _rules() -> void:
	TestLib.check(SideMissions.ORDER.size() == 10 and SideMissions.DEFS.size() == 10, "ten side missions")
	var ok := true
	for id: StringName in SideMissions.ORDER:
		var d := SideMissions.def(id)
		ok = ok and d.has("title") and int(d["pay"]) > 0 and not (d["stages"] as Array).is_empty()
		ok = ok and SideMissions.build_route(id, Vector3.ZERO, 0).size() == (d["stages"] as Array).size()
	TestLib.check(ok, "every job has a title, a payout and a route with one waypoint per stage")
	var a := SideMissions.build_route(&"rooftop", Vector3(5, 0, 5), 2)
	var b := SideMissions.build_route(&"rooftop", Vector3(5, 0, 5), 2)
	TestLib.check(a == b and a != SideMissions.build_route(&"rooftop", Vector3(5, 0, 5), 3), "routes are deterministic per seed")
	var back := SideMissions.build_route(&"rescue", Vector3(7, 0, 9), 0)
	TestLib.check((back[1]["pos"] as Vector3).is_equal_approx(Vector3(7, 0, 9)), "rescue returns to the start")
	TestLib.check(SideMissions.unlocked(&"courier", 0) and not SideMissions.unlocked(&"smuggler", 3) and SideMissions.unlocked(&"smuggler", 4), "chapter gates")
	TestLib.check(SideMissions.reward(&"courier", 0, 0, 0.0) == 220 and SideMissions.reward(&"courier", 0, 0, 0.5) > 220 and SideMissions.reward(&"courier", 0, 50, 0.0) > 220, "reward: base, time bonus, reputation bonus")
	TestLib.check(SideMissions.reward(&"nope", 0, 0, 0.0) == 0, "unknown job pays nothing")


## Walk the player through every stage of the job (teleport onto waypoints, hold, look, kill).
func _complete(id: StringName) -> bool:
	if not sm.start(id, Vector3(10, 0, 10)):
		return false
	var guard := 0
	while sm.active and guard < 40:
		guard += 1
		var s: Dictionary = sm.stages[sm.stage]
		var pos: Vector3 = s["pos"]
		match String(s["kind"]):
			"goto":
				sm.tick(0.1, pos + Vector3(1, 0, 0), Vector3.RIGHT, bool(s["car"]))
			"dwell":
				sm.tick(float(s["secs"]) + 0.5, pos, Vector3.RIGHT, false)
			"photo":
				var from := pos + Vector3(-20, 0, 0)
				sm.tick(0.1, from, Vector3.RIGHT, false)
			"kill":
				for i in int(s["n"]):
					sm.on_kill()
				sm.tick(0.1, pos, Vector3.RIGHT, false)
	return not sm.active and bool(sm.last_result.get("ok", false))


func _all_kinds() -> void:
	var before := prog.credits
	for id: StringName in SideMissions.ORDER:
		TestLib.check(_complete(id), "%s completes through its stages" % id)
	TestLib.check(prog.side_done.size() == 10 and prog.credits > before + 3000, "ten tallies and credits paid")
	TestLib.check(prog.reputation > 0 and prog.side_best.size() == 10, "reputation and best times recorded")
	# primitives refuse wrong conditions
	sm.start(&"car_drop", Vector3.ZERO)
	var p: Vector3 = sm.stages[0]["pos"]
	sm.tick(0.1, p, Vector3.RIGHT, false)
	TestLib.check(sm.active, "car delivery needs a car")
	sm.tick(0.1, p, Vector3.RIGHT, true)
	TestLib.check(not sm.active, "car delivery completes in a car")
	sm.start(&"photo", Vector3.ZERO)
	var lp: Vector3 = sm.stages[0]["pos"]
	sm.tick(0.1, lp + Vector3(-10, 0, 0), Vector3.LEFT, false)
	TestLib.check(sm.stage == 0, "photo needs the landmark in frame")
	sm.tick(0.1, lp + Vector3(-10, 0, 0), Vector3.RIGHT, false)
	TestLib.check(sm.stage == 1, "photo taken when looking at it")
	sm.abort()
	sm.start(&"relay", Vector3.ZERO)
	var rp: Vector3 = sm.stages[0]["pos"]
	sm.tick(0.1, rp, Vector3.RIGHT, false)
	sm.tick(10.0, rp + Vector3(100, 0, 0), Vector3.RIGHT, false)
	TestLib.check(sm.active and sm.progress_val < 1.0, "the hack does not progress outside the ring")
	TestLib.check(sm.status_line() != "" and sm.waypoint().is_finite(), "status line and waypoint while active")
	sm.abort()


func _clock_and_abort() -> void:
	var rep := prog.reputation
	sm.start(&"courier", Vector3.ZERO)
	sm.tick(1000.0, Vector3(9999, 0, 9999), Vector3.RIGHT, false)
	TestLib.check(not sm.active and sm.last_result["reason"] == "TIME UP" and prog.reputation == rep - 1, "the clock fails the job (-1 reputation)")
	TestLib.check(sm.status_line() == "" and not sm.waypoint().is_finite(), "idle: no line, no waypoint")
	TestLib.check(sm.start(&"courier", Vector3.ZERO) and not sm.start(&"photo"), "only one job at a time")
	sm.abort("ABANDONED")
	TestLib.check(not sm.active and sm.last_result["reason"] == "ABANDONED", "abort ends the job")
	Game.story.chapter = 0
	TestLib.check(not sm.can_start(&"hunt"), "locked jobs cannot start")
	Game.story.chapter = 9


func _save_load() -> void:
	var done := prog.side_done.duplicate()
	var best := prog.side_best.duplicate()
	TestLib.check(prog.save_file(), "save")
	prog.side_done.clear()
	prog.side_best.clear()
	TestLib.check(prog.load_file() and prog.side_done == done and prog.side_best.size() == best.size(), "side progress survives a save round trip")
	var cf := ConfigFile.new()
	cf.load(TMP)
	cf.set_value("side", "done_courier", "junk")
	cf.set_value("side", "done_photo", -4)
	cf.set_value("side", "best_relay", "x")
	cf.save(TMP)
	TestLib.check(prog.load_file() and not prog.side_done.has(&"courier") and not prog.side_done.has(&"photo") and not prog.side_best.has(&"courier"), "damaged side values are ignored")
	var cf2 := ConfigFile.new()
	cf2.load(TMP)
	cf2.erase_section("side")
	cf2.save(TMP)
	TestLib.check(prog.load_file() and prog.side_done.is_empty(), "an old save without [side] loads")
	prog.new_campaign()
	TestLib.check(prog.side_done.is_empty() and prog.side_best.is_empty(), "a new campaign clears the tallies")
