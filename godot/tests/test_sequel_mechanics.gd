extends RefCounted
## The three sequel mission mechanics as campaign step kinds (scripts/missions/campaign_runner.gd, section "sequel mechanics"; data keys in campaign_steps.gd): `rift_hold` (feed a collapse
## anomaly with verbs while waves drain it), `heist` (go in, steal, get out, lose the patrol vehicles) and `convoy_intercept` (stop moving traffic cars with ENTANGLE / COLLAPSE / damage), with
## markers, HUD line, fail and retry, the DEMO menu entries and the real verbs of the player. The runner is ticked by hand (exact game time) against the real Player, EnemyManager,
## VehicleManager, Missions and InteriorGameplay on a flat test floor. Not run here: the streamed city (stub world), a phone, the live DEMO launch on the title screen (test_demo_mode.gd does that).
## Run: tools/test.sh tests/test_sequel_mechanics.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const TMP := "user://test_sequel_mechanics_save.cfg"


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

	func say(_speaker: String, _text: String, _id := "", _wait := 0.0, _prio := 0) -> bool:
		return true

	func set_chapter(i: int) -> void:
		chapter = i

	func cards_active() -> bool:
		return false


var e := Env.new()
var host: Node
var p: Player
var root: Node3D
var em: EnemyManager
var vm: VehicleManager
var m: Missions
var camp: CampaignRunner
var prog: Progress
var ig: InteriorGameplay
var done_steps: Array = []
var failed_steps: Array = []


func run(h: Node) -> void:
	host = h
	seed(11)
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
	var story := FakeStory.new()
	root.add_child(story)
	Game.story = story
	em = (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
	root.add_child(em)
	vm = (load("res://scenes/vehicle_manager.tscn") as PackedScene).instantiate() as VehicleManager
	root.add_child(vm)
	Game.vehicles = vm
	m = (load("res://scenes/missions.tscn") as PackedScene).instantiate() as Missions
	root.add_child(m)
	ig = InteriorGameplay.new()
	ig.autosave = false
	ig.use_generator = false
	ig.test_doors = [{"id": 7001, "type": &"bar", "name": "TEST BAR", "wall": Vector3(80, 0, 0), "pos": Vector3(80, 0, 2), "normal": Vector3.BACK, "yaw": 0.0, "face_yaw": 0.0, "width": 2.4},
		{"id": 7002, "type": &"lobby", "name": "TEST LOBBY", "wall": Vector3(-90, 0, 0), "pos": Vector3(-90, 0, 2), "normal": Vector3.BACK, "yaw": 0.0, "face_yaw": 0.0, "width": 2.4}]
	root.add_child(ig)
	await e.frames(4)
	camp = m.campaign
	prog = m.progress
	prog.path = TMP
	prog.autosave_enabled = false
	camp.set_physics_process(false)
	m.contracts.set_physics_process(false)
	camp.step_completed.connect(func(c: int, i: int, k: StringName) -> void: done_steps.append([c, i, k]))
	camp.step_failed.connect(func(c: int, i: int, k: StringName, why: String) -> void: failed_steps.append([c, i, k, why]))
	Game.set_quality(1)

	_data()
	await _rift_hold()
	await _convoy()
	await _heist()
	await _demo()

	camp.abort()
	em.clear()
	Game.story = null
	Game.world = null
	Game.vehicles = null
	Game.heat = 0.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	await e.teardown()


# --- helpers ---------------------------------------------------------------------------------------------------------------

func _reset() -> void:
	camp.abort()
	if InteriorGameplay.active:
		ig.leave(true)
	em.clear()
	Game.heat = 0.0
	Game.state = &"play"
	prog.new_campaign()
	prog.unlocked = 1
	m.contracts.enabled = true
	done_steps.clear()
	failed_steps.clear()
	p.hp = p.max_hp
	p.energy = p.max_energy
	p.teleport_to(Vector3(0.0, 0.05, 0.0))


func _begin(steps: Array) -> void:
	_reset()
	camp.set_chapters([{"id": "seq_test", "steps": steps, "clears_sector": false}])
	camp.start_chapter(0, 0, true)
	camp.tick(0.1)


func _tick(seconds: float, dt := 0.25) -> void:
	for i in int(ceil(seconds / dt)):
		camp.tick(dt)


func _until(cond: Callable, max_s: float, dt := 0.25) -> bool:
	var t := 0.0
	while t < max_s:
		if cond.call():
			return true
		camp.tick(dt)
		t += dt
	return bool(cond.call())


func _put(at: Vector3) -> void:
	p.teleport_to(Vector3(at.x, 0.05, at.z))


func _kill_foes() -> void:
	for f: Variant in camp.foes.duplicate():
		var d := f as Drone
		if d != null and is_instance_valid(d) and not d.dead and d.active:
			d.damage(1.0e6)


## A verb the way the live game emits it (the player's own Quantum node); falls back to the signal when the player has none.
func _verb(id: StringName) -> void:
	if p.quantum != null and p.quantum.has_signal(&"verb_used"):
		p.quantum.emit_signal(&"verb_used", id)
	else:
		camp._on_verb(id)


# --- data ------------------------------------------------------------------------------------------------------------------

func _data() -> void:
	for k: String in ["rift_hold", "heist", "convoy_intercept"]:
		TestLib.check(CampaignRunner.StepKinds.has(StringName(k)) and CampaignSteps.KIND_DATA.has(StringName(k)), "%s is a step kind with data" % k)
		TestLib.check(CampaignSteps.validate_step({"kind": k}) == "", "%s validates" % k)
	for k: StringName in CampaignSteps.KIND_DATA:
		TestLib.check(CampaignRunner.StepKinds.has(k), "kind %s is registered in the runner" % k)
	var r := CampaignSteps.normalize_step({"kind": "rift_hold"}, 0)
	TestLib.check(r["hold"] == 40.0 and r["radius"] == 12.0 and r["integrity"] == 100.0 and r["feed"] == 5.0, "rift_hold defaults")
	var h := CampaignSteps.normalize_step({"kind": "heist"}, 0)
	TestLib.check(h["interior"] == &"lobby" and h["patrol"] == 2 and h["heat"] == 3.0 and h["dist"] == 110.0 and h["escape_time"] == 100.0, "heist defaults")
	TestLib.check(CampaignSteps.normalize_step({"kind": "heist", "door": 5}, 0)["interior"] == &"", "a heist with a door id has no default interior")
	var c := CampaignSteps.normalize_step({"kind": "convoy_intercept", "cars": 9}, 0)
	TestLib.check(c["cars"] == 3 and c["time"] == 120.0 and c["hp"] == 90.0, "convoy defaults (cars clamped to 3)")
	TestLib.check(CampaignSteps.validate_step({"kind": "convoy_intercept", "cars": 9}) != "", "convoy: cars outside 1..3 is refused")
	TestLib.check(CampaignSteps.validate_step({"kind": "rift_hold", "text": "x".repeat(CampaignSteps.MAX_TEXT + 1)}) != "", "the objective text limit applies")
	TestLib.check(CampaignSteps.validate_chapter({"steps": [{"kind": "rift_hold"}, {"kind": "heist"}, {"kind": "convoy_intercept"}]}).is_empty(), "a chapter of the three validates")
	for id: StringName in CampaignSteps.DEMO_IDS:
		TestLib.check(CampaignSteps.validate_chapter(CampaignSteps.demo_chapter(id)).is_empty(), "demo chapter %s is valid" % id)


# --- rift hold -------------------------------------------------------------------------------------------------------------

func _rift_hold() -> void:
	var at := Vector3(100.0, 0.0, 0.0)
	_begin([{"kind": "rift_hold", "pos": at, "radius": 10.0, "hold": 6.0, "gap": 999.0, "integrity": 40.0, "text": "Hold the rift"}])
	TestLib.check(camp.state == &"active" and camp.kind == &"rift_hold", "rift: the step runs")
	var mk := camp.markers()
	TestLib.check(camp.marker_count() == 1 and mk[0]["kind"] == &"zone" and float(mk[0]["radius"]) == 10.0, "rift: a zone marker of the step's radius")
	TestLib.check(camp.waypoint().has("pos") and camp.hud_line().contains("RIFT 100%"), "rift: waypoint and HUD line (%s)" % camp.hud_line())
	_put(at + Vector3(2, 0, 2))
	_tick(2.0)
	TestLib.check(camp.progress_fraction() == 0.0 and camp.hud_line().contains("USE A VERB"), "rift: standing in the ring without verbs does not fill the bar (%s)" % camp.hud_line())
	# a verb outside the ring feeds nothing
	_put(Vector3(0, 0, 0))
	_verb(&"entangle")
	TestLib.check(camp.feed_left == 0.0, "rift: a verb far from the rift feeds nothing")
	_put(at + Vector3(2, 0, 2))
	_verb(&"entangle")
	TestLib.check(camp.feed_left >= 4.9, "rift: ENTANGLE inside the ring feeds the rift (%.1f s)" % camp.feed_left)
	_tick(2.0)
	TestLib.check(camp.progress > 0.2 and camp.progress < 0.5, "rift: the bar fills while fed (%.2f)" % camp.progress)
	_tick(4.0)
	var stalled := camp.progress
	_tick(2.0)
	TestLib.check(camp.progress < stalled or camp.progress == 0.0, "rift: it drains once the feeding runs out (%.2f -> %.2f)" % [stalled, camp.progress])
	# the real COLLAPSE of the player feeds it too
	p.energy = p.max_energy
	if p.quantum != null and p.quantum.has_method(&"collapse_all"):
		p.quantum.cd_collapse = 0.0
		TestLib.check(bool(p.quantum.call(&"collapse_all")) and camp.feed_left >= 4.9, "rift: the real COLLAPSE feeds the rift (%.1f s)" % camp.feed_left)
	for i in 12:
		_verb(&"collapse")
		if not _until(func() -> bool: return camp.state != &"active", 1.0):
			continue
		break
	var ok := _until(func() -> bool:
		_verb(&"superposition")
		_kill_foes()
		return camp.state != &"active", 20.0)
	TestLib.check(ok and done_steps.size() == 1 and done_steps[0][2] == &"rift_hold", "rift: holding it fed completes the step (%s)" % str(failed_steps))
	await e.frames(1)
	# waves attack the rift and drain its integrity
	_begin([{"kind": "rift_hold", "pos": at, "radius": 10.0, "hold": 60.0, "gap": 999.0, "integrity": 20.0}])
	_put(at)
	for i in 4:
		camp._spawn(&"sentinel", at + Vector3(3 + i, 0, 3), true)
	var lost := _until(func() -> bool: return camp.state != &"active", 40.0)
	TestLib.check(lost and failed_steps.size() == 1 and failed_steps[0][3] == "RIFT LOST", "rift: aware enemies at the rift destroy it: RIFT LOST (%s)" % str(failed_steps))
	camp.tick(CampaignRunner.RETRY_PAUSE + 0.1)
	camp.tick(1.0)
	_kill_foes()
	TestLib.check(camp.state == &"active" and camp.rift_hp > 0.0, "rift: the step is retried with a fresh rift (%s, %.0f)" % [camp.state, camp.rift_hp])
	# wandering off
	_begin([{"kind": "rift_hold", "pos": at, "radius": 10.0, "hold": 60.0, "gap": 999.0}])
	_put(Vector3(0, 0, 0))
	_until(func() -> bool: return camp.state != &"active", CampaignRunner.ZONE_LEASH_TIME + 3.0)
	TestLib.check(failed_steps.size() == 1 and failed_steps[0][3] == "ZONE LOST", "rift: leaving the ring for 10 s loses it")
	# waves spawn on their own schedule
	_begin([{"kind": "rift_hold", "pos": at, "radius": 10.0, "hold": 60.0, "gap": 3.0, "count": 2, "types": ["sentinel"]}])
	_put(at)
	_tick(6.0)
	TestLib.check(camp.wave >= 1 and camp.foes_alive() >= 1, "rift: a wave hits the rift (%d foes)" % camp.foes_alive())
	camp.abort()
	await e.frames(1)
	TestLib.check(em.alive_count() == 0, "rift: aborting releases the wave")


# --- convoy intercept ------------------------------------------------------------------------------------------------------

func _release_all_cars() -> void:
	for v: Vehicle in vm.list.duplicate():
		if v != vm.starter and not v.driver_is_player:
			vm._release(v)


func _convoy() -> void:
	_release_all_cars()
	_begin([{"kind": "convoy_intercept", "pos": Vector3(20, 0, 0), "cars": 3, "time": 90.0, "hp": 100.0, "text": "Stop the convoy"}])
	TestLib.check(camp.state == &"active" and camp.convoy.size() == 3, "convoy: three cars (%d)" % camp.convoy.size())
	var all_ok := true
	for c: Vehicle in camp.convoy:
		all_ok = all_ok and c.ai and c.has_meta(&"hold") and c.max_hp == 100.0 and c.ai_cruise == 13.0
	TestLib.check(all_ok, "convoy: held traffic cars with the step's hp and speed")
	var mk := camp.markers()
	TestLib.check(camp.marker_count() == 3 and mk[0]["kind"] == &"target" and camp.waypoint().has("pos"), "convoy: a marker per car and a waypoint")
	TestLib.check(camp.hud_line().contains("STOPPED 0/3"), "convoy: HUD line (%s)" % camp.hud_line())
	var a: Vehicle = camp.convoy[0]
	var b: Vehicle = camp.convoy[1]
	var c3: Vehicle = camp.convoy[2]
	# ENTANGLE only stops a car right where the swap put the player
	_put(a.global_position + Vector3(0, 0, 40))
	_verb(&"entangle")
	TestLib.check(camp.stopped.is_empty(), "convoy: ENTANGLE far from every car stops nothing")
	_put(a.global_position + Vector3(0, 0, 3))
	_verb(&"entangle")
	TestLib.check(camp.stopped.has(a) and a.ai_stun > 1000.0, "convoy: ENTANGLE stops the car it swapped with")
	camp.tick(0.1)
	camp.markers()
	TestLib.check(camp.hud_line().contains("STOPPED 1/3") and camp.marker_count() == 2 and camp.progress_fraction() > 0.3, "convoy: HUD, markers and bar follow (%s)" % camp.hud_line())
	# the real COLLAPSE
	_put(b.global_position + Vector3(0, 0, 4))
	p.energy = p.max_energy
	var hp0 := b.hp
	if p.quantum != null and p.quantum.has_method(&"collapse_all"):
		p.quantum.cd_collapse = 0.0
		TestLib.check(bool(p.quantum.call(&"collapse_all")), "convoy: the real COLLAPSE fires")
	else:
		_verb(&"collapse")
	camp.tick(0.1)
	TestLib.check(camp.stopped.has(b) and (b.hp < hp0 or b.dead), "convoy: COLLAPSE stops and damages the cars around the player")
	TestLib.check(camp.state == &"active", "convoy: one car still moving keeps the step open")
	# damage disables the last one
	c3.damage(c3.max_hp * 0.7)
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 1 and done_steps[0][2] == &"convoy_intercept", "convoy: every car stopped completes it")
	await e.frames(1)
	TestLib.check(not a.has_meta(&"hold") and camp.convoy.is_empty(), "convoy: the holds are lifted afterwards")
	_release_all_cars()
	# a wreck counts as stopped
	_begin([{"kind": "convoy_intercept", "pos": Vector3(-20, 0, 0), "cars": 1, "time": 90.0}])
	camp.convoy[0].damage(1.0e6)
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 1, "convoy: a wrecked car counts")
	_release_all_cars()
	# it gets away
	_begin([{"kind": "convoy_intercept", "pos": Vector3(20, 0, 0), "cars": 2, "time": 90.0}])
	var ca: Vehicle = camp.convoy[0]
	_put(ca.global_position + Vector3(0, 0, 220))
	_until(func() -> bool: return camp.state != &"active", CampaignRunner.CONVOY_ESCAPE_TIME + 3.0, 0.5)
	TestLib.check(failed_steps.size() == 1 and failed_steps[0][3] == "CONVOY GOT AWAY", "convoy: a car 150 m away for 6 s gets away (%s)" % str(failed_steps))
	TestLib.check(not ca.has_meta(&"hold"), "convoy: failing lifts the holds")
	camp.tick(CampaignRunner.RETRY_PAUSE + 0.1)
	camp.tick(1.0)
	TestLib.check(camp.state == &"active" and camp.convoy.size() == 2, "convoy: the retry brings a new convoy (%s, %d cars)" % [camp.state, camp.convoy.size()])
	# time out
	_release_all_cars()
	_begin([{"kind": "convoy_intercept", "pos": Vector3(20, 0, 0), "cars": 1, "time": 4.0}])
	_put(camp.convoy[0].global_position + Vector3(0, 0, 60))
	_tick(5.0, 0.5)
	TestLib.check(failed_steps.size() == 1 and failed_steps[0][3] == "TIME OUT", "convoy: the clock fails it")
	camp.abort()
	_release_all_cars()


# --- quantum heist ---------------------------------------------------------------------------------------------------------

func _heist() -> void:
	var door := Vector3(80, 0, 2)
	_begin([{"kind": "heist", "interior": "bar", "patrol": 0, "grace": 1.0, "dist": 60.0, "clear": 0.5, "text": "Steal the data"}])
	TestLib.check(camp.state == &"active" and camp.kind == &"heist" and camp.pos.distance_to(door) < 0.5, "heist: the step runs and points at the door")
	var mk := camp.markers()
	TestLib.check(camp.marker_count() == 1 and mk[0]["kind"] == &"dest" and camp.waypoint().has("pos") and camp.hud_line().contains("M"), "heist: phase 1 marker, waypoint and HUD (%s)" % camp.hud_line())
	_put(door + Vector3(0, 0, 3))
	camp.tick(0.5)
	TestLib.check(camp.state == &"active" and not camp.loot, "heist: standing at the door is not enough")
	TestLib.check(ig.enter(ig.door_by_id(7001), true) and InteriorGameplay.active, "heist: the player goes through the door")
	camp.tick(0.3)
	TestLib.check(camp.state == &"active" and camp._phase == 2 and camp.hud_line().contains("STEAL THE DATA"), "heist: inside, the step is stealing (%s)" % camp.hud_line())
	camp.markers()
	TestLib.check(camp.marker_count() == 0 and camp.waypoint().is_empty(), "heist: no street hints inside the building")
	# leaving empty-handed sends the player back in
	ig.leave(true)
	camp.tick(0.3)
	TestLib.check(camp.state == &"active" and camp._phase == 1 and not camp.loot, "heist: leaving without the data is not a getaway (phase %d)" % camp._phase)
	ig.enter(ig.door_by_id(7001), true)
	camp.tick(0.3)
	var got := _until(func() -> bool: return camp.loot, 6.0)
	TestLib.check(got and camp.hud_line().contains("GET OUT"), "heist: the data is taken (%s)" % camp.hud_line())
	ig.leave(true)
	camp.tick(0.3)
	TestLib.check(camp._phase == 3 and Game.heat >= 2.9 and camp.hud_line().contains("GETAWAY"), "heist: out with the data the heat jumps and the getaway starts (%s)" % camp.hud_line())
	camp.markers()
	TestLib.check(camp.marker_count() >= 1 and camp.waypoint().is_empty(), "heist: getaway ring on the minimap, no waypoint")
	_put(door + Vector3(0, 0, 100))
	camp.tick(0.2)
	TestLib.check(camp.state == &"active", "heist: far away but still hot is not lost")
	Game.heat = 0.2
	camp.tick(0.2)
	TestLib.check(done_steps.size() == 1 and done_steps[0][2] == &"heist", "heist: far away and cold completes it")
	# the real interior mission is the loot of a lobby
	_begin([{"kind": "heist", "interior": "lobby", "patrol": 0, "dist": 60.0}])
	TestLib.check(camp.pos.distance_to(Vector3(-90, 0, 2)) < 0.5, "heist: the default interior is the lobby")
	_put(Vector3(-90, 0, 4))
	ig.enter(ig.door_by_id(7002), true)
	camp.tick(0.3)
	if ig.missions.is_active():
		ig.test_complete_mission()
		TestLib.check(camp.loot, "heist: cracking the lobby safe is the theft")
	else:
		TestLib.check(_until(func() -> bool: return camp.loot, 6.0), "heist: a lobby without a mission is plain loot after the grace time")
	# patrols chase the getaway
	ig.leave(true)
	_begin([{"kind": "heist", "interior": "bar", "patrol": 2, "grace": 0.5, "escape_time": 3.0, "dist": 60.0}])
	_put(door + Vector3(0, 0, 3))
	ig.enter(ig.door_by_id(7001), true)
	camp.tick(0.3)
	_until(func() -> bool: return camp.loot, 4.0)
	ig.leave(true)
	camp.tick(0.3)
	TestLib.check(camp._phase == 3 and camp._patrol_want == 2 and Game.heat >= VehicleSpecs.PATROL_HEAT, "heist: the getaway sends patrol vehicles (want %d, heat %.1f)" % [camp._patrol_want, Game.heat])
	_until(func() -> bool: return camp.state != &"active", 6.0)
	TestLib.check(failed_steps.size() == 1 and failed_steps[0][3] == "NOT LOST", "heist: not losing the chase in time fails it (%s)" % str(failed_steps))
	camp.tick(CampaignRunner.RETRY_PAUSE + 0.1)
	camp.tick(1.0)
	TestLib.check(camp.state == &"active" and camp._phase == 1 and not camp.loot, "heist: the retry starts at the door again (%s, phase %d)" % [camp.state, camp._phase])
	camp.abort()
	for v: Vehicle in vm.list.duplicate():
		if v.patrol:
			vm._release(v)


# --- DEMO menu ---------------------------------------------------------------------------------------------------------------

func _demo() -> void:
	var cat := DemoMode.catalog()
	var found := {}
	for g: Dictionary in cat:
		if g["kind"] == &"sequel":
			found = g
	TestLib.check(not found.is_empty() and (found["items"] as Array).size() == 3, "DEMO menu: a SEQUEL MECHANICS group with three entries")
	TestLib.check(DemoPanel.TABS.size() == cat.size() + 2, "DEMO panel: a tab per group plus SPAWN and TOOLS")
	TestLib.check(DemoPanel.TABS.has("SEQUEL"), "DEMO panel: the SEQUEL tab")
	for id: StringName in CampaignSteps.DEMO_IDS:
		_reset()
		TestLib.check(camp.start_demo(id), "demo %s starts" % id)
		camp.tick(0.1)
		TestLib.check(camp.state == &"active" and camp.kind == id, "demo %s: the step is active (%s)" % [id, camp.kind])
		camp.abort()
		TestLib.check(camp.chapter_data(0).get("id", "") != "demo_" + String(id), "demo %s: the sandbox chapter is gone after the run" % id)
	TestLib.check(not camp.start_demo(&"nonsense"), "an unknown demo id does not start")
	_reset()
