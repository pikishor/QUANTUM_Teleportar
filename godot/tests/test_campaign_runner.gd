extends RefCounted
## The scripted campaign step runner (scripts/missions/campaign_runner.gd) against the real Player, EnemyManager, VehicleManager, Missions, Progress, InteriorGameplay and Hud on a flat test
## floor with a stub world: the documented step contract (StepKinds, aliases, defaults, validation, scope A's campaign data), a tiny two-step sample chapter end to end (reach, then a target;
## checkpoint, chapter clear, win), every step kind (reach, enter_interior, escort, defend, hack, kill_target, chase, escape, survive), fail and retry (time out, zone lost, escort lost, death and
## respawn), checkpoints that survive a save and a load (and old save files without them), the chapter select on the title and pause screens by tap and by touch, the HUD line, waypoint and the
## minimap markers. The runner is ticked by hand (`tick(dt)`), so every check is exact game time. Not run here: the real streamed city (stub world) and a phone.
## Run: tools/test.sh tests/test_campaign_runner.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const TMP := "user://test_campaign_runner_save.cfg"
const SETTINGS := "user://test_campaign_runner_settings.cfg"


class World extends Node3D:
	var intersections: Array[Vector3] = []

	func road_point_near(center: Vector3, rmin: float, rmax: float) -> Vector3:
		var a := randf() * TAU
		var r := randf_range(rmin, rmax)
		return Vector3(clampf(center.x + cos(a) * r, -250.0, 250.0), 0.0, clampf(center.z + sin(a) * r, -250.0, 250.0))

	func ground_height(_x: float, _z: float, _from := 0.0) -> float:
		return 0.0


class FakeStory extends Node:
	var chapter := 0
	var tutorial = null
	var lines: Array = []
	var set_to := -1
	var cards := false

	func say(speaker: String, text: String, id := "", _wait := 0.0, _prio := 0) -> bool:
		lines.append({"s": speaker, "t": text, "id": id})
		return true

	func set_chapter(i: int) -> void:
		set_to = i
		chapter = i

	func cards_active() -> bool:
		return cards


var e := Env.new()
var host: Node
var p: Player
var root: Node3D
var em: EnemyManager
var vm: VehicleManager
var m: Missions
var camp: CampaignRunner
var prog: Progress
var story: FakeStory
var ig: InteriorGameplay
var hud: Hud
var done_steps: Array = []
var failed_steps: Array = []
var done_chapters: Array = []


func run(h: Node) -> void:
	host = h
	seed(8)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	await e.setup(host)
	p = e.p
	root = e.root
	Fixture.add_floor(root, 600.0)
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	var w := World.new()
	w.intersections = CityLayout.make_intersections()
	root.add_child(w)
	Game.world = w
	story = FakeStory.new()
	root.add_child(story)
	Game.story = story
	em = (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	root.add_child(em)
	vm = (load("res://scenes/vehicle_manager.tscn") as PackedScene).instantiate() as VehicleManager
	root.add_child(vm)
	m = (load("res://scenes/missions.tscn") as PackedScene).instantiate() as Missions
	root.add_child(m)
	await e.frames(4)
	camp = m.campaign
	prog = m.progress
	prog.path = TMP
	prog.autosave_enabled = false
	camp.set_physics_process(false)             # the test ticks by hand
	m.contracts.set_physics_process(false)
	camp.step_completed.connect(func(c: int, i: int, k: StringName) -> void: done_steps.append([c, i, k]))
	camp.step_failed.connect(func(c: int, i: int, k: StringName, why: String) -> void: failed_steps.append([c, i, k, why]))
	camp.chapter_completed.connect(func(c: int) -> void: done_chapters.append(c))
	Game.set_quality(1)

	_contract_data()
	_structure()
	await _sample_chapter()
	await _reach_and_interior()
	await _hack()
	await _defend_and_survive()
	await _escort()
	await _kill_target()
	await _chase()
	await _escape()
	await _fail_and_retry()
	await _death_and_respawn()
	await _checkpoint_save_load()
	await _old_saves()
	await _chapter_select_logic()
	await _hud_and_minimap()
	await _chapter_select_ui()

	if is_instance_valid(hud):
		hud.queue_free()
	camp.abort()
	em.clear()
	Game.story = null
	Game.world = null
	Game.heat = 0.0
	Game.score = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	await e.teardown()


# --- helpers -------------------------------------------------------------------------------------------------------------

func _step_dict(kind: String, extra := {}) -> Dictionary:
	var d := {"kind": kind}
	d.merge(extra, true)
	return d


func _reset_world() -> void:
	camp.abort()
	em.clear()
	Game.heat = 0.0
	Game.score = 0
	Game.state = &"play"
	prog.autosave_enabled = false
	prog.new_campaign()
	prog.unlocked = 1
	story.chapter = 0
	story.lines.clear()
	story.cards = false
	m.win_on_cores = true
	m.contracts.enabled = true
	done_steps.clear()
	failed_steps.clear()
	done_chapters.clear()
	p.hp = p.max_hp
	p.teleport_to(Vector3(0.0, 0.05, 0.0))
	p.invuln = 0.0


## Registers a one-chapter campaign, arms it at once and ticks until its first step is active.
func _begin(steps: Array, extra := {}) -> bool:
	_reset_world()
	var ch := {"id": "test_ch", "steps": steps}
	ch.merge(extra, true)
	camp.set_chapters([ch])
	var ok := camp.start_chapter(0, 0, true)
	camp.tick(0.1)
	return ok


func _tick(seconds: float, dt := 0.25) -> void:
	var n := int(ceil(seconds / dt))
	for i in n:
		camp.tick(dt)


## Ticks until `cond` holds (or `max_s` seconds pass); returns whether it held.
func _until(cond: Callable, max_s: float, dt := 0.25) -> bool:
	var t := 0.0
	while t < max_s:
		if cond.call():
			return true
		camp.tick(dt)
		t += dt
	return bool(cond.call())


func _kill_foes() -> void:
	for f: Variant in camp.foes.duplicate():
		var d := f as Drone
		if d != null and is_instance_valid(d) and not d.dead and d.active:
			d.damage(1.0e6)


func _put(at: Vector3) -> void:
	p.teleport_to(Vector3(at.x, 0.05, at.z))


func _near(a: Vector3, b: Vector3, tol := 3.0) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= tol


# --- the documented contract ---------------------------------------------------------------------------------------------

func _contract_data() -> void:
	TestLib.check(CampaignRunner.StepKinds.size() == 12, "twelve documented step kinds (nine plus the sequel rift_hold, heist, convoy_intercept)")
	var all_known := true
	for k: StringName in CampaignRunner.StepKinds:
		all_known = all_known and CampaignSteps.KIND_DATA.has(k)
	TestLib.check(all_known and CampaignSteps.KIND_DATA.size() == CampaignRunner.StepKinds.size(), "StepKinds and the per-kind data (CampaignSteps.KIND_DATA) list the same kinds")
	for k: String in ["reach", "enter_interior", "escort", "defend", "hack", "kill_target", "chase", "escape", "survive"]:
		TestLib.check(CampaignRunner.StepKinds.has(StringName(k)), "StepKinds has %s" % k)
	TestLib.check(CampaignSteps.kind_of({"kind": "infiltrate"}) == &"enter_interior" and CampaignSteps.kind_of({"kind": &"assassinate"}) == &"kill_target", "scope A's names infiltrate / assassinate are aliases")
	TestLib.check(CampaignSteps.kind_of({"kind": "teleport_cow"}) == &"" and CampaignSteps.kind_of({}) == &"", "unknown kinds are rejected")
	TestLib.check(CampaignSteps.vec3(Vector3(1, 2, 3)) == Vector3(1, 2, 3) and CampaignSteps.vec3(Vector2(4, 5)) == Vector3(4, 0, 5) and CampaignSteps.vec3([6, 7]) == Vector3(6, 0, 7) and CampaignSteps.vec3([1.5, 2.0, 3.5]) == Vector3(1.5, 2.0, 3.5), "positions parse from Vector3, Vector2 and arrays")
	TestLib.check(not CampaignSteps.vec3("north").is_finite() and not CampaignSteps.vec3([1]).is_finite() and not CampaignSteps.vec3(["a", "b"]).is_finite(), "bad positions come out as INF")
	TestLib.check(CampaignSteps.validate_step({"kind": "reach", "pos": [10, 20], "text": "Go"}) == "", "a minimal step validates")
	TestLib.check(CampaignSteps.validate_step({"kind": "nope"}) != "" and CampaignSteps.validate_step({"kind": "reach", "pos": "x"}) != "" and CampaignSteps.validate_step({"kind": "hack", "text": "x".repeat(60)}) != "" \
			and CampaignSteps.validate_step({"kind": "reach", "radio": {"t": "x".repeat(StoryData.LINE_MAX + 1), "s": "ORACLE"}}) != "" and CampaignSteps.validate_step(5) != "", "bad kinds, positions, long text and long radio lines are reported")
	TestLib.check(CampaignSteps.validate_chapter({"steps": []}).size() == 1 and CampaignSteps.validate_chapter({"steps": [{"kind": "reach"}, {"kind": "zzz"}]}).size() == 1 and CampaignSteps.validate_chapter({"steps": [{"kind": "reach"}]}).is_empty(), "chapters need steps and every step is checked")
	var n := CampaignSteps.normalize_step({"kind": "infiltrate", "obj": "Slip into the lobby", "interior": "lobby"}, 2)
	TestLib.check(n["kind"] == &"enter_interior" and n["id"] == "enter_interior_2" and n["text"] == "Slip into the lobby" and n["interior"] == &"lobby" and not (n["pos"] as Vector3).is_finite() and n["checkpoint"] == true, "normalising resolves the alias, the id, the text (obj) and the defaults")
	var a := CampaignSteps.normalize_step({"kind": "assassinate", "target": "boss"}, 0)
	var b := CampaignSteps.normalize_step({"kind": "assassinate", "target": "specialist"}, 0)
	TestLib.check(a["enemy"] == &"overseer" and a["hp_mult"] == 1.0 and b["enemy"] == &"" and b["hp_mult"] > 1.0, "assassinate: boss = the Overseer, specialist = one picked for the chapter")
	TestLib.check(CampaignSteps.normalize_step({"kind": "hack"}, 0)["hold"] == 24.0 and CampaignSteps.normalize_step({"kind": "defend"}, 0)["hold"] == 60.0 and CampaignSteps.normalize_step({"kind": "escape"}, 0)["heat"] == 3.0, "defaults per kind")
	var src := {"kind": "reach", "pos": [3, 4]}
	CampaignSteps.normalize_step(src, 0)
	TestLib.check(src["pos"] is Array and not src.has("id"), "normalising never changes the input dictionary")
	var line := CampaignSteps.point_along(PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0), Vector3(10, 0, 10)]), 15.0)
	TestLib.check(_near(line["pos"], Vector3(10, 0, 5), 0.01) and CampaignSteps.route_length(PackedVector3Array([Vector3.ZERO, Vector3(10, 0, 0), Vector3(10, 0, 10)])) == 20.0, "points along a route and its length")
	# scope A's campaign data (when it exists): every chapter must be playable by the runner
	var camp_data := CampaignRunner._campaign_data()
	var all_ok := true
	for ch: Dictionary in camp_data:
		var problems := CampaignSteps.validate_chapter(ch)
		if not problems.is_empty():
			printerr("campaign data problem: ", problems)
		all_ok = all_ok and problems.is_empty()
	TestLib.check(all_ok, "every chapter of scripts/story/campaign_data.gd (%d) passes the runner's validation" % camp_data.size())
	TestLib.check(CampaignRunner.chapter_count() >= StoryData.FINAL + 1, "the chapter select lists at least the story's chapters (%d)" % CampaignRunner.chapter_count())


func _structure() -> void:
	TestLib.check(m.campaign is CampaignRunner and m.campaign.get_parent() == m, "Missions owns the CampaignRunner node")
	TestLib.check(not camp.enabled, "under tests (Game.autostart) the runner does not start chapters by itself")
	TestLib.check(camp.state == &"idle" and camp.hud_line() == "" and camp.boss().is_empty() and camp.progress_fraction() < 0.0 and camp.waypoint().is_empty(), "idle: nothing to show")
	camp.markers()
	TestLib.check(camp.marker_count() == 0 and camp.route_points().is_empty(), "idle: no markers, no route")
	TestLib.check(not camp.start_chapter(99), "a chapter without steps does not start")


# --- the sample two-step chapter ---------------------------------------------------------------------------------------------

func _sample_chapter() -> void:
	var goal := Vector3(60.0, 0.0, 0.0)
	var steps := [
		{"kind": "reach", "pos": goal, "radius": 6.0, "text": "Cross the trading floor", "radio": {"s": "ORACLE", "t": "Beacon is live. Cross the floor and keep to the shadows."}},
		{"kind": "kill_target", "enemy": "sentinel", "guards": 0, "pos": Vector3(60.0, 0.0, 60.0), "text": "Eliminate the Vael watcher", "name": "VAEL WATCHER",
			"radio": {"start": {"s": "KESTREL", "t": "One watcher on the roof. One."}, "done": {"s": "ORACLE", "t": "Clean. The beacon goes dark."}}},
	]
	TestLib.check(_begin(steps), "the sample chapter starts")
	TestLib.check(camp.state == &"active" and camp.kind == &"reach" and camp.step_index == 0, "step 1 is active (reach)")
	TestLib.check(m.win_on_cores == false and m.contracts.enabled == false, "a scripted chapter makes the cores optional and holds back random contract offers")
	TestLib.check(prog.checkpoint.get("chapter", -1) == 0 and prog.checkpoint.get("step", -1) == 0, "the chapter start is a checkpoint (step 0)")
	TestLib.check(camp.hud_line().begins_with("1/2  CROSS THE TRADING FLOOR") and camp.hud_line().ends_with(" M"), "the HUD line: step counter, objective, distance (%s)" % camp.hud_line())
	TestLib.check(story.lines.size() >= 1 and story.lines[0]["t"].begins_with("Beacon is live"), "the step's radio line is said through the story layer")
	var wp := camp.waypoint()
	TestLib.check(wp.has("pos") and _near(wp["pos"], goal, 0.01) and absf(camp.distance_to_goal() - 60.0) < 1.0, "the waypoint is the goal, %d m away" % int(camp.distance_to_goal()))
	var mk := camp.markers()
	TestLib.check(camp.marker_count() == 1 and mk[0]["kind"] == &"dest" and _near(mk[0]["pos"], goal, 0.01), "one minimap marker on the goal")
	TestLib.check(camp.route_points().size() >= 3 and camp.visuals != null and camp.visuals.marker_visible(0), "the street route and the world ring are shown")
	_tick(2.0)
	TestLib.check(camp.state == &"active" and done_steps.is_empty(), "standing far from the ring does nothing")
	_put(goal + Vector3(1, 0, 1))
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 1 and done_steps[0] == [0, 0, &"reach"], "stepping into the ring completes step 1")
	TestLib.check(prog.checkpoint.get("step", -1) == 1 and prog.checkpoint.get("tp", false) == true and _near(prog.checkpoint["pos"], goal, 3.0), "step 2 is a checkpoint at the player's spot (tp: %s)" % str(prog.checkpoint))
	TestLib.check(prog.checkpoint.has("goal") and _near(prog.checkpoint["goal"], Vector3(60.0, 0.0, 60.0), 0.01), "the next goal is saved in the checkpoint")
	TestLib.check(camp.state == &"armed" and camp.hud_line() == "", "a short breath between the steps")
	camp.tick(CampaignRunner.STEP_GAP + 0.1)
	TestLib.check(camp.state == &"active" and camp.kind == &"kill_target" and camp.target != null and camp.target.get("type") == &"sentinel", "step 2 begins: a target spawns")
	TestLib.check(story.lines.back()["t"].begins_with("One watcher"), "its start line (radio {start, done, fail}) is said")
	var boss := camp.boss()
	TestLib.check(boss.get("name", "") == "VAEL WATCHER" and float(boss["frac"]) > 0.99, "the HUD boss bar shows the target's health")
	TestLib.check(camp.markers()[0]["kind"] in [&"target", &"area"] and camp.hud_line().begins_with("2/2  ELIMINATE THE VAEL WATCHER"), "target marker and HUD line")
	(camp.target as Drone).damage((camp.target as Drone).hp * 0.5)
	camp.tick(0.1)
	TestLib.check(camp.progress_fraction() > 0.4 and camp.progress_fraction() < 0.6, "damage fills the progress bar (%.2f)" % camp.progress_fraction())
	var tgt := camp.target as Drone
	tgt.damage(1.0e6)
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 2 and done_chapters == [0], "killing the target ends step 2 and the chapter")
	TestLib.check(story.lines.any(func(l: Dictionary) -> bool: return str(l["t"]).begins_with("Clean.")), "the step's done line is said")
	TestLib.check(Game.state == &"win", "the chapter ends with the sector-stabilized flow (Game.win)")
	TestLib.check(prog.checkpoint.is_empty() and m.win_on_cores == true and m.contracts.enabled == true and camp.state == &"done", "checkpoint cleared, cores and contracts back to normal")
	TestLib.check(prog.unlocked >= 2, "clearing the chapter unlocks the next (%d)" % prog.unlocked)
	TestLib.check(prog.credits >= 0 and Game.score >= 200, "each step pays a score bonus (%d)" % Game.score)
	_reset_world()
	# the TEST menu's skip: finishes the running step (and only a running one)
	_begin([{"kind": "hack", "pos": Vector3(100, 0, 0)}, {"kind": "reach", "pos": Vector3(0, 0, 100)}])
	TestLib.check(camp.skip_step() and done_steps.size() == 1 and camp.step_index == 1 and prog.checkpoint["step"] == 1, "skip_step finishes the step like an objective would")
	TestLib.check(not camp.skip_step(), "and does nothing while the next step is only armed")
	_reset_world()
	# clears_sector: false keeps the player in the world
	_begin([{"kind": "reach", "pos": Vector3(20, 0, 0)}], {"clears_sector": false})
	_put(Vector3(20.5, 0, 0.5))
	camp.tick(0.1)
	TestLib.check(done_chapters == [0] and Game.state == &"play", "clears_sector: false completes the chapter without the win screen")
	# cores are optional while a chapter runs: collecting the last one does not win
	_reset_world()
	_begin([{"kind": "reach", "pos": Vector3(200, 0, 0)}])
	m.new_round(1)
	await e.frames(2)
	var core_pos: Vector3 = m.cores[0].pos
	_put(core_pos)
	await e.frames(4)
	TestLib.check(m.cores.is_empty() and Game.state == &"play", "collecting the last core while a scripted chapter runs does not win the sector")
	camp.abort()
	TestLib.check(m.win_on_cores == true and m.contracts.enabled == true, "abort gives the cores and the contracts their normal rules back")
	_reset_world()


# --- reach, enter_interior ------------------------------------------------------------------------------------------------------

func _reach_and_interior() -> void:
	# a generated goal (no pos): a street point 110..190 m from where the step starts, the same one after a retry
	_begin([{"kind": "reach"}])
	var g := camp.pos
	var d0 := Vector2(g.x - p.global_position.x, g.z - p.global_position.z).length()
	TestLib.check(d0 >= 100.0 and d0 <= 200.0, "a step without pos gets a street goal %d m away" % int(d0))
	TestLib.check(prog.checkpoint.has("goal") and _near(prog.checkpoint["goal"], g, 0.01), "the first goal is resolved when the chapter starts and saved in its checkpoint")
	camp.retry()
	camp.tick(CampaignRunner.STEP_GAP)
	TestLib.check(camp.state == &"active" and _near(camp.pos, g, 0.01), "the goal survives a retry")
	# a vehicle counts for the ring
	_begin([{"kind": "reach", "pos": Vector3(40, 0, 0), "radius": 8.0}])
	_put(Vector3(40, 0, 7.0))
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 1, "inside the ring radius (7 of 8 m) counts")
	# elevated player (roof) does not count
	_begin([{"kind": "reach", "pos": Vector3(40, 0, 0), "radius": 8.0}])
	p.teleport_to(Vector3(40, 0.05, 0))
	p.global_position.y = 20.0
	camp.tick(0.1)
	TestLib.check(done_steps.is_empty(), "a player 20 m above the ring does not reach it")
	p.teleport_to(Vector3(0, 0.05, 0))

	# --- enter_interior with the real InteriorGameplay and the stub room
	ig = InteriorGameplay.new()
	ig.autosave = false
	ig.use_generator = false
	ig.test_doors = [{"id": 7001, "type": &"bar", "name": "TEST BAR", "wall": Vector3(80, 0, 0), "pos": Vector3(80, 0, 2), "normal": Vector3.BACK, "yaw": 0.0, "face_yaw": 0.0, "width": 2.4},
		{"id": 7002, "type": &"lobby", "name": "TEST LOBBY", "wall": Vector3(-90, 0, 0), "pos": Vector3(-90, 0, 2), "normal": Vector3.BACK, "yaw": 0.0, "face_yaw": 0.0, "width": 2.4}]
	root.add_child(ig)
	await e.frames(3)
	TestLib.check(InteriorGameplay.instance == ig, "an InteriorGameplay is present for the interior steps")
	_begin([{"kind": "infiltrate", "interior": "lobby", "obj": "Slip into the lobby"}])
	TestLib.check(camp.kind == &"enter_interior" and _near(camp.pos, Vector3(-90, 0, 2), 0.01), "infiltrate = enter_interior: the marker is on the nearest door of that type")
	TestLib.check(camp.markers()[0]["kind"] == &"dest" and camp.hud_line().begins_with("1/1  SLIP INTO THE LOBBY"), "door marker and HUD line")
	_put(Vector3(-90, 0, 4))
	camp.tick(0.5)
	TestLib.check(done_steps.is_empty(), "standing at the door does not complete it")
	TestLib.check(ig.enter(ig.door_by_id(7002), true) and InteriorGameplay.active, "the player goes through the door")
	camp.tick(0.1)
	TestLib.check(done_chapters == [0] or done_steps.size() == 1, "being inside completes the step")
	var cp_after: Dictionary = camp.checkpoint
	ig.leave(true)
	await e.frames(2)
	TestLib.check(not InteriorGameplay.active, "back on the street")
	# the other door type does not count; `door` by id; leave: true needs the way back out
	_begin([{"kind": "enter_interior", "door": 7001, "leave": true}])
	camp.tick(0.1)
	TestLib.check(_near(camp.pos, Vector3(80, 0, 2), 0.01), "a door can be named by id")
	ig.enter(ig.door_by_id(7002), true)
	camp.tick(0.1)
	TestLib.check(done_steps.is_empty() and camp.state == &"active", "another building does not count")
	ig.leave(true)
	await e.frames(2)
	ig.enter(ig.door_by_id(7001), true)
	camp.tick(0.1)
	TestLib.check(camp.state == &"active" and camp._phase == 2 and camp.hud_line().contains("LEAVE THE BUILDING") and done_steps.is_empty(), "leave: true waits for the way back out")
	camp.markers()
	TestLib.check(camp.marker_count() >= 1 and camp.waypoint().has("pos"), "while inside to leave, the way out is still marked")
	_tick(1.0)
	TestLib.check(done_steps.is_empty(), "still inside, not done")
	ig.leave(true)
	await e.frames(2)
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 1, "back on the street completes it")
	# a street step does not run while the player is inside
	_begin([{"kind": "reach", "pos": Vector3(20, 0, 0), "time": 5.0}])
	ig.enter(ig.door_by_id(7001), true)
	var tl := camp.time_left
	_tick(2.0)
	camp.markers()                                                          # markers() refreshes the count
	TestLib.check(is_equal_approx(camp.time_left, tl) and camp.marker_count() == 0 and camp.waypoint().is_empty(), "street objectives wait while the player is inside a building (clock stopped, markers hidden)")
	ig.leave(true)
	await e.frames(2)
	camp.abort()
	# no doors at all: the step degrades to reaching the spot
	var saved_doors := ig.test_doors.duplicate()
	ig.test_doors = []
	_begin([{"kind": "enter_interior", "pos": Vector3(30, 0, 0)}])
	_put(Vector3(30, 0, 1))
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 1, "a city without doors degrades enter_interior to reaching its position")
	ig.test_doors = saved_doors
	_reset_world()


# --- hack ------------------------------------------------------------------------------------------------------------------------

func _hack() -> void:
	var at := Vector3(100.0, 0.0, 0.0)
	_begin([{"kind": "hack", "pos": at, "hold": 8.0, "radius": 9.0}])
	TestLib.check(camp.kind == &"hack" and camp.markers()[0]["kind"] == &"zone" and float(camp.markers()[0]["radius"]) == 9.0, "hack: a zone ring marker")
	camp.tick(0.25)
	TestLib.check(camp.progress_fraction() == 0.0, "no progress outside the ring")
	TestLib.check(camp.hud_line().contains("RETURN TO THE RING"), "outside the ring the HUD says so (%s)" % camp.hud_line())
	_put(at + Vector3(2, 0, 2))
	_tick(4.0)
	var half := camp.progress
	TestLib.check(camp.inside and half > 0.4 and half < 0.6, "inside the ring the bar fills (%.2f after 4 s of 8)" % half)
	_tick(1.5)
	TestLib.check(camp.foes.size() >= 1, "a drone pulse hits the node after 5 s (%d foes)" % camp.foes.size())
	var before_leaving := camp.progress
	_put(Vector3(0, 0, 0))
	_tick(2.0)
	TestLib.check(camp.progress < before_leaving, "outside the ring the progress drains (%.2f -> %.2f)" % [before_leaving, camp.progress])
	_put(at)
	_kill_foes()
	var ok := _until(func() -> bool: _kill_foes(); return camp.state != &"active", 20.0)
	TestLib.check(ok and done_steps.size() == 1 and done_steps[0][2] == &"hack", "holding the ring completes the hack")
	TestLib.check(camp.state == &"armed" or camp.state == &"done", "the foes and the ring are cleaned up with the step")
	await e.frames(1)
	TestLib.check(em.alive_count() == 0, "no enemy of the hack is left alive (%d)" % em.alive_count())


# --- defend, survive ---------------------------------------------------------------------------------------------------------

func _defend_and_survive() -> void:
	var at := Vector3(-80.0, 0.0, 0.0)
	_begin([{"kind": "defend", "pos": at, "radius": 20.0, "hold": 6.0, "gap": 3.0, "count": 2, "types": ["sentinel"]}])
	_put(at + Vector3(3, 0, 3))
	TestLib.check(camp.kind == &"defend" and camp.markers()[0]["kind"] == &"zone" and float(camp.markers()[0]["radius"]) == 20.0, "defend: a zone marker of the step's radius")
	_tick(1.0)
	camp.tick(1.5)
	TestLib.check(camp.wave >= 1 and camp.foes_alive() >= 1, "defend: a wave attacks the zone (%d foes)" % camp.foes_alive())
	TestLib.check(camp.progress > 0.2, "defend: holding fills the bar (%.2f)" % camp.progress)
	var ok := _until(func() -> bool: _kill_foes(); return camp.state != &"active", 20.0)
	TestLib.check(ok and done_steps.size() == 1 and done_steps[0][2] == &"defend", "defend: the hold time completes it")
	# leaving the zone loses it
	_begin([{"kind": "defend", "pos": at, "radius": 20.0, "hold": 60.0}])
	_put(Vector3(150, 0, 150))
	_tick(1.0)
	TestLib.check(camp.hud_line().contains("RETURN TO THE ZONE"), "defend: the HUD tells you to return (%s)" % camp.hud_line())
	_until(func() -> bool: return camp.state != &"active", CampaignRunner.ZONE_LEASH_TIME + 2.0)
	TestLib.check(camp.state == &"retry" and failed_steps.size() == 1 and failed_steps[0][3] == "ZONE LOST", "defend: ten seconds outside lose the zone (%s)" % str(failed_steps))
	TestLib.check(camp.foes.is_empty() and camp.visuals != null and not camp.visuals.marker_visible(0), "a failed step cleans up its foes and ring")
	# survive
	_begin([{"kind": "survive", "hold": 5.0, "gap": 2.0, "count": 2, "types": ["sentinel"], "text": "Outlast the sweep"}])
	TestLib.check(camp.kind == &"survive" and camp.waypoint().is_empty() and camp.hud_line().begins_with("1/1  OUTLAST THE SWEEP  0:0"), "survive: a countdown and no waypoint (%s)" % camp.hud_line())
	camp.tick(2.5)
	TestLib.check(camp.foes_alive() >= 1, "survive: waves come at the player (%d)" % camp.foes_alive())
	ok = _until(func() -> bool: _kill_foes(); return camp.state != &"active", 20.0)
	TestLib.check(ok and done_steps.size() == 1 and done_steps[0][2] == &"survive", "survive: the clock completes it")
	_reset_world()


# --- escort ------------------------------------------------------------------------------------------------------------------

func _escort() -> void:
	var dest := Vector3(140.0, 0.0, 0.0)
	var steps := [{"kind": "escort", "from": Vector3(0, 0, 0), "to": dest, "speed": 30.0, "leash": 20.0, "hp": 100.0, "radius": 5.0,
		"ambush": [{"at": 0.5, "n": 2, "types": ["sentinel"]}], "text": "Escort the survivor"}]
	_begin(steps)
	TestLib.check(camp.kind == &"escort" and is_instance_valid(camp.escortee) and camp.escortee.visible, "escort: the civilian stands on the street")
	TestLib.check(camp.markers().size() >= 2 and camp.marker_count() == 2 and camp.markers()[0]["kind"] == &"target" and camp.markers()[1]["kind"] == &"dest", "escort: the escortee and the destination are marked")
	TestLib.check(camp.route_points().size() >= 3 and camp.visuals.marker_visible(1), "escort: the route line is drawn and the destination ring stands")
	TestLib.check(camp.hud_line().contains("ESCORT 100%"), "escort: the HUD shows the escort's health (%s)" % camp.hud_line())
	# far away the escortee waits
	_put(Vector3(0, 0, 150))
	var before := camp.escortee.global_position
	_tick(1.0)
	TestLib.check(_near(camp.escortee.global_position, before, 0.5), "escort: the civilian waits when the player is far (leash 20 m)")
	TestLib.check(camp.waypoint()["pos"].is_equal_approx(camp.escortee.global_position), "escort: the waypoint points at the asset when you fell behind")
	# close: it walks
	_put(camp.escortee.global_position + Vector3(0, 0, 3))
	_tick(1.0)
	TestLib.check(not _near(camp.escortee.global_position, before, 5.0), "escort: it walks when the player is close (%.0f m)" % camp.escortee.global_position.distance_to(before))
	_put(camp.escortee.global_position + Vector3(0, 0, 3))
	camp.tick(0.01)
	TestLib.check(camp.waypoint()["pos"].is_equal_approx(dest), "escort: with the asset close the waypoint is the destination")
	# follow it to the end, killing the ambush
	var saw := [false]                                                     # a lambda copies plain variables: the flag lives in an array
	var ok := _until(func() -> bool:
		if is_instance_valid(camp.escortee):
			p.global_position = camp.escortee.global_position + Vector3(-2.0, 0.05, 2.0)
		saw[0] = saw[0] or camp.foes_alive() > 0
		_kill_foes()
		return camp.state != &"active", 30.0, 0.2)
	TestLib.check(saw[0], "escort: an ambush hits halfway")
	TestLib.check(ok and done_steps.size() == 1 and done_steps[0][2] == &"escort", "escort: arriving at the destination completes it")
	TestLib.check(camp.escortee == null or not camp.escortee.visible, "escort: the civilian is put away when the step ends")
	# enemies hurt the escortee and its death fails the step
	_begin(steps)
	_put(camp.escortee.global_position + Vector3(0, 0, 3))
	var foe := em.spawn(&"sentinel", camp.escortee.global_position + Vector3(2, 0, 2), true)
	camp.foes.append(foe)
	foe.set_physics_process(false)
	foe.global_position = camp.escortee.global_position + Vector3(2, 1, 2)
	camp.tick(0.5)
	TestLib.check(camp.escort_hp < 100.0 and camp.state == &"active", "escort: an aware enemy next to the civilian hurts it (%.0f hp)" % camp.escort_hp)
	TestLib.check(_near(camp.escortee.global_position, Vector3(0, 0, 0), 2.0), "escort: it stops while enemies are close")
	_until(func() -> bool: foe.global_position = camp.escortee.global_position + Vector3(2, 1, 2); return camp.state != &"active", 30.0, 0.5)
	TestLib.check(camp.state == &"retry" and failed_steps.size() == 1 and failed_steps[0][3] == "ESCORT LOST", "escort: its death fails the step (%s)" % str(failed_steps))
	# abandoning it
	_begin(steps)
	_put(Vector3(0, 0, 200))
	_until(func() -> bool: return camp.state != &"active", CampaignRunner.ESCORT_LEFT_TIME + 3.0, 0.5)
	TestLib.check(camp.state == &"retry" and failed_steps.size() == 1 and failed_steps[0][3] == "ESCORT LEFT BEHIND", "escort: leaving it 60 m behind for 15 s fails the step (%s)" % str(failed_steps))
	_reset_world()


# --- kill_target ---------------------------------------------------------------------------------------------------------------

func _kill_target() -> void:
	_begin([{"kind": "assassinate", "target": "specialist", "pos": Vector3(0, 0, -90), "obj": "Eliminate the specialist", "guards": 2}], {"id": "ch_spec"})
	story.chapter = 3
	camp.retry()
	camp.tick(1.0)
	TestLib.check(camp.state == &"active" and camp.target != null, "assassinate (specialist): a target spawns")
	TestLib.check(camp.foes.size() == 3 and camp.foes_alive() == 3, "the target comes with its guards (3 foes)")
	TestLib.check(camp.target.get("hp") > float(EnemyTypes.get_cfg(camp.target.get("type"))["hp"]), "the target is tougher than the type's base health")
	var mk := camp.markers()[0]
	TestLib.check(mk["kind"] == &"area" or mk["kind"] == &"target", "far from the player the target is an area ring, near it a point")
	_put(camp.target.global_position + Vector3(0, 0, 30))
	camp.tick(0.1)
	TestLib.check(camp.markers()[0]["kind"] == &"target", "near the target the minimap marks it exactly")
	# lost target
	var d := camp.target as Drone
	em.release(d)
	camp.tick(0.1)
	TestLib.check(camp.state == &"retry" and failed_steps.size() == 1 and failed_steps[0][3] == "TARGET LOST", "a target that vanishes without dying fails the step")
	TestLib.check(camp.foes.is_empty(), "its guards are sent away with it")
	# the boss alias: the Overseer, and his death counts as the chapter's boss
	_begin([{"kind": "assassinate", "target": "boss", "pos": Vector3(0, 0, -90), "guards": 0, "obj": "Kill the Overseer"}], {"id": "ch_boss"})
	TestLib.check(camp.state == &"active" and camp.target is Overseer, "assassinate (boss): the Vael Overseer spawns")
	TestLib.check(camp.target.get("max_hp") == float(EnemyTypes.get_cfg(&"overseer")["hp"]) * Progress.enemy_hp_mult(), "the Overseer keeps his own health (hp_mult 1)")
	TestLib.check(camp.boss().get("name", "") == "VAEL OVERSEER", "the boss bar names him")
	camp.target.set("hp", 0.0)
	camp.tick(0.1)
	TestLib.check(done_steps.is_empty() and camp.state == &"active", "the Overseer's death holds the step open for a beat (the defeat scene starts, tests/test_campaign_review.gd)")
	camp.tick(CampaignRunner.BOSS_BEAT + 0.1)
	TestLib.check(done_steps.size() == 1 and 0 in prog.bosses_cleared, "his death completes the step and clears the chapter's boss")
	await e.frames(1)
	_reset_world()


# --- chase ---------------------------------------------------------------------------------------------------------------------

func _chase() -> void:
	Game.vehicles = vm
	_begin([{"kind": "chase", "pos": Vector3(20, 0, 0), "time": 60.0, "hp": 100.0}])
	TestLib.check(camp.state == &"active" and camp.car != null and camp.car.ai and camp.car.max_hp == 100.0, "chase: a traffic car is the target")
	TestLib.check(camp.car.has_meta(&"hold") and camp.markers()[0]["kind"] == &"target" and camp.waypoint().has("pos"), "chase: it is held against recycling, marked and tracked")
	var car := camp.car
	_put(car.global_position + Vector3(0, 0, 200))
	vm._stream()
	TestLib.check(car.active and vm.list.has(car), "chase: streaming does not release the target")
	_until(func() -> bool: return camp.state != &"active", CampaignRunner.CHASE_GRACE - 5.0, 0.5)
	TestLib.check(camp.state == &"active", "chase: the target cannot escape in the first %d s (the player has to reach a car)" % int(CampaignRunner.CHASE_GRACE))
	_until(func() -> bool: return camp.state != &"active", CampaignRunner.CHASE_ESCAPE_TIME + 8.0, 0.5)
	TestLib.check(camp.state == &"retry" and failed_steps.size() == 1 and failed_steps[0][3] == "TARGET ESCAPED", "chase: a target 200 m away escapes after the grace time (%s)" % str(failed_steps))
	TestLib.check(not car.has_meta(&"hold"), "chase: the hold is lifted afterwards")
	_begin([{"kind": "chase", "pos": Vector3(-20, 0, 0), "time": 60.0, "hp": 100.0}])
	car = camp.car
	_put(car.global_position + Vector3(0, 0, 20))
	car.damage(50.0)
	camp.tick(0.1)
	TestLib.check(camp.state == &"active" and camp.progress_fraction() > 0.3, "chase: damage fills the bar (%.2f)" % camp.progress_fraction())
	car.damage(1.0e6)
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 1 and done_steps[0][2] == &"chase", "chase: wrecking the car completes it")
	# time out
	_begin([{"kind": "chase", "pos": Vector3(10, 0, 40), "time": 6.0}])
	car = camp.car
	car.ai_cruise = 0.0
	_put(car.global_position + Vector3(0, 0, 30))
	_tick(7.0, 0.5)
	TestLib.check(failed_steps.size() == 1 and failed_steps[0][3] == "TIME OUT", "chase: an uncaught target times out")
	if car != null and car.active:
		vm._release(car)
	_reset_world()


# --- escape (heat) ----------------------------------------------------------------------------------------------------------------

func _escape() -> void:
	_begin([{"kind": "escape", "heat": 3.0, "clear": 0.5, "dist": 60.0, "text": "Lose the hunters", "time": 90.0}])
	TestLib.check(camp.kind == &"escape" and Game.heat >= 2.9, "escape: the heat jumps to the step's level (%.1f)" % Game.heat)
	TestLib.check(camp.markers()[0]["kind"] == &"area" and float(camp.markers()[0]["radius"]) == 60.0, "escape: the minimap ring shows how far to get away")
	TestLib.check(camp.hud_line().contains("HEAT 3.0") and camp.waypoint().is_empty(), "escape: the HUD shows the heat and no waypoint (%s)" % camp.hud_line())
	camp.tick(0.1)
	TestLib.check(camp.progress >= 0.0 and camp.progress < 0.3, "escape: no progress while hot and close (%.2f)" % camp.progress)
	_put(Vector3(0, 0, 80))
	camp.tick(0.1)
	TestLib.check(camp.state == &"active", "escape: being far away is not enough while the heat is up")
	Game.heat = 0.3
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 1 and done_steps[0][2] == &"escape", "escape: far away and heat below the clear level completes it")
	# the heat has to fall too: cooling down at the start does not skip the distance
	_begin([{"kind": "escape", "heat": 2.0, "dist": 60.0}])
	Game.heat = 0.0
	camp.tick(0.1)
	TestLib.check(camp.state == &"active", "escape: cold but still on the spot does not complete it")
	_reset_world()


# --- fail, retry ----------------------------------------------------------------------------------------------------------------

func _fail_and_retry() -> void:
	var a := Vector3(40, 0, 0)
	var b := Vector3(-60, 0, -60)
	var steps := [{"kind": "reach", "pos": a, "radius": 6.0}, {"kind": "reach", "pos": b, "radius": 6.0, "time": 4.0, "text": "Beat the clock",
		"radio": {"start": {"s": "ORACLE", "t": "Four seconds, Kestrel."}, "fail": {"s": "ORACLE", "t": "Too slow. Again."}}}]
	_begin(steps)
	_put(a + Vector3(1, 0, 1))
	camp.tick(0.1)
	camp.tick(CampaignRunner.STEP_GAP + 0.1)
	TestLib.check(camp.step_index == 1 and camp.state == &"active" and camp.time_left > 3.5, "step 2 is running on its clock (%.1f)" % camp.time_left)
	TestLib.check(camp.hud_line().contains("0:0"), "the clock is on the HUD line (%s)" % camp.hud_line())
	_put(Vector3(150, 0, 150))
	_tick(4.5)
	TestLib.check(camp.state == &"retry" and camp.last_fail == "TIME OUT" and camp.fails == 1 and failed_steps == [[0, 1, &"reach", "TIME OUT"]], "time out: the step fails (%s)" % str(failed_steps))
	TestLib.check(camp.hud_line().begins_with("MISSION FAILED  TIME OUT  RETRY IN"), "the HUD shows the failure and the countdown (%s)" % camp.hud_line())
	TestLib.check(story.lines.any(func(l: Dictionary) -> bool: return str(l["t"]).begins_with("Too slow")), "the step's fail line is said")
	camp.markers()
	TestLib.check(camp.progress_fraction() < 0.0 and camp.marker_count() == 0, "a failed step shows nothing on the map")
	TestLib.check(_until(func() -> bool: return camp.state == &"armed", CampaignRunner.RETRY_PAUSE + 1.0), "after the pause the step re-arms (%s)" % str(camp.state))
	TestLib.check(_until(func() -> bool: return camp.state == &"active", 3.0, 0.1) and camp.step_index == 1 and camp.time_left > 3.0, "the same step runs again with a fresh clock (%.1f)" % camp.time_left)
	TestLib.check(_near(p.global_position, a, 4.0), "the player is moved back to the checkpoint (%s)" % str(p.global_position))
	TestLib.check(done_steps.size() == 1 and camp.steps_done == 1, "completed steps stay completed")
	camp.retry()
	TestLib.check(camp.state == &"armed", "retry() restarts the step by hand")
	# manual retry from the retry state
	camp.abort()
	_reset_world()


func _death_and_respawn() -> void:
	var a := Vector3(40, 0, 0)
	var steps := [{"kind": "reach", "pos": a, "radius": 6.0}, {"kind": "kill_target", "enemy": "sentinel", "guards": 1, "pos": Vector3(-60, 0, -60)}]
	_begin(steps)
	_put(a + Vector3(1, 0, 1))
	camp.tick(0.1)
	camp.tick(CampaignRunner.STEP_GAP + 0.1)
	TestLib.check(camp.kind == &"kill_target" and camp.foes_alive() == 2, "the second step is running with its enemies")
	_put(Vector3(-100, 0, 100))
	p.hp = 0.0
	Game.die()
	TestLib.check(camp.state == &"held" and camp.foes.is_empty() and camp.hud_line() == "", "death: the step is on hold and its enemies are gone")
	camp.tick(5.0)
	TestLib.check(camp.state == &"held", "the hold lasts until the respawn")
	Game.do_respawn()
	TestLib.check(camp.state == &"armed" and failed_steps.is_empty(), "respawn: the step re-arms without counting as a failure")
	await e.frames(2)
	camp.tick(1.0)
	TestLib.check(camp.state == &"active" and camp.kind == &"kill_target" and camp.step_index == 1, "the same step begins again (%s)" % str(camp.state))
	var goal := Vector3(-60, 0, -60)
	TestLib.check(Vector2(p.global_position.x - goal.x, p.global_position.z - goal.z).length() < CampaignRunner.RETRY_DIST + 45.0 and not _near(p.global_position, Vector3(0, 0, 0), 20.0), "a fight step restarts at the fight (about %d m from the target), not at the spawn point (%s)" % [int(CampaignRunner.RETRY_DIST), str(p.global_position)])
	TestLib.check(camp.foes_alive() == 2, "fresh enemies, not the old ones")
	_reset_world()


# --- checkpoints through save and load ---------------------------------------------------------------------------------------------

func _checkpoint_save_load() -> void:
	prog.path = TMP
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var pts := [Vector3(30, 0, 0), Vector3(30, 0, 70), Vector3(-50, 0, 70)]
	var steps: Array = []
	for pt: Vector3 in pts:
		steps.append({"kind": "reach", "pos": pt, "radius": 6.0})
	steps[2]["checkpoint"] = false
	steps.append({"kind": "hack", "hold": 10.0})                            # no pos: its goal is generated and must come back the same
	_begin(steps)
	prog.autosave_enabled = true                                            # the runner's checkpoints now write the file
	_put(pts[0] + Vector3(1, 0, 1))
	camp.tick(0.1)
	TestLib.check(FileAccess.file_exists(TMP), "a checkpoint writes the save file when autosave is on")
	var cf := ConfigFile.new()
	TestLib.check(cf.load(TMP) == OK and cf.has_section("checkpoint") and int(cf.get_value("checkpoint", "chapter", -1)) == 0 and int(cf.get_value("checkpoint", "step", -1)) == 1, "the file has a [checkpoint] section (chapter 0, step 1)")
	TestLib.check(int(cf.get_value("meta", "version", 0)) == Progress.SAVE_VERSION and cf.has_section_key("wallet", "credits") and cf.has_section_key("campaign", "sector") and cf.has_section_key("weapons", "unlocked"), "the old sections and the version number are unchanged")
	camp.tick(CampaignRunner.STEP_GAP + 0.1)
	_put(pts[1] + Vector3(1, 0, 1))
	camp.tick(0.1)
	camp.tick(CampaignRunner.STEP_GAP + 0.1)
	TestLib.check(camp.step_index == 2 and prog.checkpoint["step"] == 2, "step 2 is a checkpoint too")
	_put(pts[2] + Vector3(1, 0, 1))
	camp.tick(0.1)
	TestLib.check(camp.step_index == 3 and prog.checkpoint["step"] == 2, "a step with checkpoint: false does not move the checkpoint (still step 2)")
	var goal := camp.goal_for(3)
	TestLib.check(goal.is_finite() and Vector2(goal.x + 50.0, goal.z - 70.0).length() >= 70.0, "the hack's goal was generated 70+ m from where the previous step ended (%s)" % str(goal))
	var saved := prog.checkpoint.duplicate()
	# a fresh Progress state: load the file back
	prog.checkpoint = {}
	prog.autosave_enabled = false
	TestLib.check(prog.load_file(), "the file loads")
	TestLib.check(prog.checkpoint.get("chapter", -1) == 0 and prog.checkpoint.get("step", -1) == 2 and prog.checkpoint.get("tp", false) == true and _near(prog.checkpoint["pos"], saved["pos"], 0.01), "the checkpoint comes back from the file (%s)" % str(prog.checkpoint))
	TestLib.check(prog.checkpoint.has("goal") and _near(prog.checkpoint["goal"], saved["goal"], 0.01), "with the next goal")
	# resume on a rebuilt runner state
	camp.abort()
	_put(Vector3(200, 0, 200))
	TestLib.check(camp.resume(prog.checkpoint), "the runner resumes from the loaded checkpoint")
	TestLib.check(camp.state == &"armed" and camp.step_index == 2 and camp.chapter_index == 0, "it is back at step 3 of the chapter")
	TestLib.check(_near(p.global_position, saved["pos"], 4.0), "the player stands at the checkpoint again")
	camp.tick(0.1)
	TestLib.check(camp.state == &"active" and camp.kind == &"reach" and _near(camp.pos, pts[2], 0.01), "step 3 is running")
	_put(pts[2] + Vector3(1, 0, 1))
	camp.tick(0.1)
	TestLib.check(_near(camp.goal_for(3), goal, 0.01), "the generated goal of step 4 is the same after the reload (%s)" % str(camp.goal_for(3)))
	camp.tick(CampaignRunner.STEP_GAP + 0.1)
	TestLib.check(camp.kind == &"hack" and _near(camp.pos, goal, 0.01), "and the hack begins there")
	# the chapter ending clears the checkpoint (and the file when saved)
	prog.autosave_enabled = true
	_put(goal)
	_until(func() -> bool: _kill_foes(); _put(goal); return camp.state == &"done", 30.0)
	TestLib.check(camp.state == &"done" and prog.checkpoint.is_empty(), "finishing the chapter clears the checkpoint")
	var cf2 := ConfigFile.new()
	cf2.load(TMP)
	TestLib.check(not cf2.has_section("checkpoint"), "and the section leaves the file")
	prog.autosave_enabled = false
	# damaged checkpoint sections load as no checkpoint
	for bad: Dictionary in [{"chapter": -1, "step": 2, "pos": Vector3.ONE}, {"chapter": 0, "step": -4, "pos": Vector3.ONE}, {"chapter": 0, "step": 1, "pos": "nowhere"}, {"chapter": "x", "step": 1, "pos": Vector3.ONE}]:
		var cf3 := ConfigFile.new()
		cf3.load(TMP)
		for k: String in bad:
			cf3.set_value("checkpoint", k, bad[k])
		cf3.save(TMP)
		prog.checkpoint = {"chapter": 9}
		prog.load_file()
		TestLib.check(prog.checkpoint.is_empty(), "a damaged [checkpoint] section is ignored (%s)" % str(bad))
	camp.abort()
	_reset_world()


func _old_saves() -> void:
	# a save written before the chapter select: no unlocked key, no checkpoint section
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", Progress.SAVE_VERSION)
	cf.set_value("wallet", "credits", 450)
	cf.set_value("wallet", "reputation", 5)
	cf.set_value("campaign", "sector", 3)
	cf.set_value("campaign", "best", 1200)
	cf.set_value("weapons", "unlocked", PackedStringArray(["carbine", "scatter"]))
	cf.save(TMP)
	prog.unlocked = 1
	prog.checkpoint = {"chapter": 4}
	TestLib.check(prog.has_save() and prog.load_file(), "an old save loads")
	TestLib.check(prog.credits == 450 and prog.sector == 3 and prog.reputation == 5 and WeaponDefs.is_unlocked(&"scatter"), "its wallet, sector, reputation and weapons are intact")
	TestLib.check(prog.unlocked == 4 and prog.checkpoint.is_empty(), "chapters up to its sector are unlocked (4), and it has no checkpoint")
	# a later save keeps unlocked and is still readable the old way
	prog.unlocked = 6
	prog.save_file()
	var cf2 := ConfigFile.new()
	cf2.load(TMP)
	TestLib.check(int(cf2.get_value("campaign", "unlocked", 0)) == 6 and int(cf2.get_value("campaign", "sector", -1)) == 3 and int(cf2.get_value("wallet", "credits", -1)) == 450, "unlocked is saved next to the old keys")
	prog.unlocked = 1
	prog.load_file()
	TestLib.check(prog.unlocked == 6, "and loads back")
	# a new campaign keeps the unlocked chapters (they are meta progress like the best score) but drops the checkpoint
	prog.checkpoint = {"chapter": 1, "step": 1, "pos": Vector3.ZERO, "tp": true}
	prog.new_campaign()
	TestLib.check(prog.unlocked == 6 and prog.checkpoint.is_empty() and prog.credits == 0, "NEW GAME resets the wallet and checkpoint but not the unlocked chapters")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_reset_world()


# --- chapter select: Progress side ----------------------------------------------------------------------------------------------------

func _chapter_select_logic() -> void:
	_reset_world()
	prog.path = TMP
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var ch := {"id": "sel1", "steps": [{"kind": "reach", "pos": Vector3(50, 0, 0)}, {"kind": "reach", "pos": Vector3(50, 0, 50)}]}
	camp.set_chapters([{}, ch, ch])
	camp.enabled = true
	prog.credits = 500
	prog.unlocked = 1
	Game.state = &"menu"
	TestLib.check(not prog.can_select_chapter() and not prog.start_chapter(1), "only chapter 1 unlocked: no chapter select, chapter 2 is refused")
	prog.unlock(1)
	TestLib.check(prog.chapters_unlocked() == 2 and prog.can_select_chapter(), "unlocking chapter 2 shows the chapter select")
	TestLib.check(not prog.start_chapter(2) and not prog.start_chapter(-1), "a locked or negative chapter is refused")
	Game.state = &"play"
	TestLib.check(not prog.start_chapter(1), "chapters are only chosen on the title or pause screen")
	Game.state = &"paused"
	TestLib.check(prog.start_chapter(1), "an unlocked chapter starts from the pause screen")
	TestLib.check(Game.state == &"play" and story.set_to == 1 and m.rounds == 2 and prog.sector == 1, "the run plays chapter 2: story, cores (a fresh round) and sector follow")
	TestLib.check(prog.credits == 500 and prog.continued == false, "credits are kept and the saved interior is not resumed")
	TestLib.check(camp.is_running() and camp.chapter_index == 1 and camp.state == &"armed" and camp.step_index == 0, "the scripted steps of that chapter are armed")
	camp.tick(CampaignRunner.START_DELAY + 0.1)
	TestLib.check(camp.state == &"active" and camp.kind == &"reach", "and begin")
	# CONTINUE resumes from the checkpoint of that chapter
	camp.tick(0.1)
	_put(Vector3(50, 0, 0))
	camp.tick(0.1)
	TestLib.check(prog.checkpoint.get("step", -1) == 1 and prog.checkpoint.get("chapter", -1) == 1, "step 1 of chapter 2 made a checkpoint")
	prog.save_file()
	Game.state = &"menu"
	story.set_to = -1
	prog.sector = 1
	var cp_saved := prog.checkpoint.duplicate()
	prog.checkpoint = {}
	TestLib.check(prog.has_save() and prog.continue_game(), "CONTINUE starts the saved run")
	TestLib.check(story.set_to == 1 and camp.chapter_index == 1 and camp.step_index == 1 and camp.state == &"armed", "CONTINUE resumes the scripted chapter at the checkpoint's step (%d)" % camp.step_index)
	TestLib.check(prog.continued == true and _near(p.global_position, cp_saved["pos"], 4.0), "continued, and the player is at the checkpoint")
	# a checkpoint of another chapter is stale
	prog.checkpoint = {"chapter": 2, "step": 1, "pos": Vector3(1, 0, 1), "tp": true}
	prog.sector = 1
	prog.save_file()
	Game.state = &"menu"
	prog.continue_game()
	TestLib.check(camp.chapter_index == 1 and camp.step_index == 0, "a checkpoint of another chapter is ignored: the chapter starts from its first step")
	# without scripted steps (enabled off) CONTINUE plays the plain core hunt like before
	camp.enabled = false
	camp.abort()
	Game.state = &"menu"
	prog.continue_game()
	TestLib.check(camp.state == &"idle" and m.win_on_cores == true, "with the runner off CONTINUE is the plain core hunt")
	camp.enabled = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_reset_world()


# --- HUD, minimap, chapter select on screen --------------------------------------------------------------------------------------------

func _hud_and_minimap() -> void:
	_reset_world()
	var scene := load("res://scenes/hud.tscn") as PackedScene
	hud = scene.instantiate() as Hud
	hud.settings_path = SETTINGS
	root.add_child(hud)
	await e.frames(3)
	_begin([{"kind": "hack", "pos": Vector3(30, 0, 30), "hold": 20.0, "text": "Hack the ledger node"}])
	Game.state = &"play"
	_put(Vector3(31, 0, 31))
	camp.tick(0.1)
	await e.frames(24)
	TestLib.check(hud._camp_text.begins_with("1/1  HACK THE LEDGER NODE"), "the HUD's priority line is the step line (%s)" % hud._camp_text)
	var mm := hud.minimap
	mm.size = Vector2(176, 176)
	await e.frames(8)
	TestLib.check(mm.campaign_markers == 1 and mm.contract_markers == 1, "the minimap draws the step's zone marker (%d)" % mm.campaign_markers)
	camp.abort()
	await e.frames(24)
	TestLib.check(mm.campaign_markers == 0 and hud._camp_text == "", "no step, no marker, no campaign line")
	# a step far from the camera: the edge waypoint code runs without error (camera and unproject)
	_begin([{"kind": "reach", "pos": Vector3(-150, 0, 150)}])
	await e.frames(24)
	TestLib.check(hud._camp_text != "" and camp.waypoint().has("pos"), "a reach step has a waypoint for the HUD")
	camp.abort()
	_reset_world()


func _button(id: StringName) -> Dictionary:
	hud._ensure_layout()
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b
	return {}


func _ids() -> Array:
	hud._ensure_layout()
	return hud.buttons.map(func(b: Dictionary) -> StringName: return b["id"])


func _chapter_select_ui() -> void:
	_reset_world()
	prog.autosave_enabled = false
	var ch := {"id": "ui1", "steps": [{"kind": "reach", "pos": Vector3(50, 0, 0)}]}
	camp.set_chapters([{}, ch, ch, ch])
	camp.enabled = true
	prog.unlocked = 1
	prog.credits = 321
	Game.state = &"play"
	Game.state = &"menu"
	TestLib.check(not _ids().has(&"chapters") and (_ids().has(&"deploy") or _ids().has(&"continue")), "title with one chapter unlocked: no CHAPTERS button")
	prog.unlock(2)                                                                  # three chapters
	hud._gear_open = true                                                           # CHAPTERS lives on the MORE page
	hud._layout_key = ""
	hud._ensure_layout()
	TestLib.check(_ids().has(&"chapters") and _button(&"chapters")["label"] == "CHAPTERS", "title with chapters unlocked: a CHAPTERS button")
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var br: Rect2 = _button(&"chapters")["rect"]
	TestLib.check(br.size.y >= 44.0 * s - 0.5 and br.size.x >= 160.0 * s - 0.5, "the CHAPTERS button is a real touch target (%dx%d px)" % [br.size.x, br.size.y])
	var overlap := false
	for b: Dictionary in hud.buttons:
		for b2: Dictionary in hud.buttons:
			if b != b2 and (b["rect"] as Rect2).intersects(b2["rect"]):
				overlap = true
	TestLib.check(not overlap, "no title button overlaps another")
	# open by touch
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.index = 0
	ev.position = br.get_center()
	hud._input(ev)
	TestLib.check(hud._chapters_open, "a tap on CHAPTERS opens the chapter select")
	var ids := _ids()
	TestLib.check(ids.has(&"chapter_0") and ids.has(&"chapter_1") and ids.has(&"chapter_2") and not ids.has(&"chapter_3") and ids.has(&"chapters_back"), "three unlocked chapters are buttons, the locked ones are not (%s)" % str(ids))
	var tall := true
	var wide := true
	for id: StringName in [&"chapter_0", &"chapter_1", &"chapter_2", &"chapters_back"]:
		var r: Rect2 = _button(id)["rect"]
		tall = tall and r.size.y >= UiUtil.TOUCH_MIN * s - 0.5
		wide = wide and r.size.x >= UiUtil.TOUCH_MIN * s
	TestLib.check(tall and wide, "every chapter cell and BACK are at least %d px (touch minimum)" % int(UiUtil.TOUCH_MIN * s))
	var inside := true
	for b: Dictionary in hud.buttons:
		inside = inside and Rect2(Vector2.ZERO, vp).encloses(b["rect"])
	TestLib.check(inside, "the whole grid fits the screen (%dx%d)" % [vp.x, vp.y])
	# the screen draws without error
	hud._screen.queue_redraw()
	await e.frames(3)
	# back, then again
	hud.tap((_button(&"chapters_back")["rect"] as Rect2).get_center())
	TestLib.check(not hud._chapters_open and hud._gear_open and _ids().has(&"chapters"), "BACK returns to the MORE page of the title")
	hud.press_button(&"chapters")
	# choose chapter 2 by a touch
	var r1: Rect2 = _button(&"chapter_1")["rect"]
	var ev2 := InputEventScreenTouch.new()
	ev2.pressed = true
	ev2.position = r1.get_center()
	story.set_to = -1
	hud._input(ev2)
	TestLib.check(Game.state == &"play" and story.set_to == 1 and camp.chapter_index == 1 and prog.credits == 321, "a tap on chapter 2 starts it with the wallet kept (state %s, story %d)" % [Game.state, story.set_to])
	TestLib.check(not hud._chapters_open, "the chapter select closes")
	# the pause screen
	Game.state = &"paused"
	hud._gear_open = true
	hud._layout_key = ""
	hud._ensure_layout()
	var ids2 := _ids()
	TestLib.check(ids2.has(&"chapters") and ids2.has(&"hero_open") and ids2.has(&"menu"), "the pause MORE page has CHAPTERS next to HERO")
	var pr: Rect2 = _button(&"chapters")["rect"]
	var sr: Rect2 = _button(&"hero_open")["rect"]
	TestLib.check(not pr.intersects(sr) and pr.size.y >= 44.0 * s - 0.5, "CHAPTERS and HERO share the grid without overlap")
	TestLib.check(hud.press_button(&"chapters") and hud._chapters_open and _ids().has(&"chapter_2"), "CHAPTERS opens from the pause screen")
	TestLib.check(_button(&"chapter_1")["on"] == true and _button(&"chapter_0")["on"] == false, "the running chapter is highlighted")
	TestLib.check(hud.press_button(&"chapter_2") and Game.state == &"play" and story.set_to == 2, "chapter 3 starts from the pause screen")
	Game.state = &"paused"
	hud.press_button(&"chapters")
	TestLib.check(not hud.press_button(&"chapter_3"), "a locked chapter does nothing")
	Game.state = &"play"
	TestLib.check(not hud._chapters_open, "leaving the pause screen closes the chapter select")
	TestLib.check(not hud.press_button(&"chapter_0") and not hud.press_button(&"chapters"), "chapter buttons do nothing in play")
	# no save and nothing else unlocked on the title: with a save the NEW GAME / CHAPTERS row is shared
	prog.autosave_enabled = false
	prog.credits = 100
	prog.sector = 2
	prog.path = TMP
	prog.save_file()
	Game.state = &"menu"
	var ids3 := _ids()
	hud._gear_open = true
	hud._layout_key = ""
	hud._ensure_layout()
	var ids4 := _ids()
	hud._gear_open = false
	TestLib.check(ids3.has(&"continue") and ids4.has(&"deploy") and ids4.has(&"chapters"), "with a save: CONTINUE on the title, NEW GAME and CHAPTERS on MORE")
	var dr: Rect2 = _button(&"deploy")["rect"]
	var cr: Rect2 = _button(&"chapters")["rect"]
	TestLib.check(not dr.intersects(cr) and absf(dr.position.y - cr.position.y) < 1.0, "NEW GAME and CHAPTERS sit side by side")
	camp.enabled = false
	camp.abort()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	Game.state = &"play"
	_reset_world()
