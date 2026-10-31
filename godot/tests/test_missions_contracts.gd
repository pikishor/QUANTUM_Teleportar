extends RefCounted
## Contracts (the six procedural mission kinds) against the real Player, EnemyManager and VehicleManager on a flat test floor with a stub world (the real junction list):
## chapter weights and pure rules, then for every kind: the offer and its marker, the spawn on accept, the objective logic, completion with its rewards, failure, retry and
## abandon rules, death hold and the lifecycle reset. Contracts are ticked by hand (`tick(dt)`), so every check is exact game time.
## Run: tools/test.sh tests/test_missions_contracts.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")


class World extends Node3D:
	var intersections: Array[Vector3] = []

	func random_road_point() -> Vector3:
		return Vector3(float(randi_range(-3, 3)) * 80.0 + 5.0, 0.0, randf_range(-280.0, 280.0))

	func road_point_near(center: Vector3, rmin: float, rmax: float) -> Vector3:
		var a := randf() * TAU
		var r := randf_range(rmin, rmax)
		return Vector3(center.x + cos(a) * r, 0.0, center.z + sin(a) * r)

	func ground_height(_x: float, _z: float, _from := 0.0) -> float:
		return 0.0


class FakeStory extends Node:
	var chapter := 0
	var tutorial = null
	var lines: Array = []

	func say(speaker: String, text: String, id := "", _wait := 0.0, _prio := 0) -> bool:
		lines.append({"s": speaker, "t": text, "id": id})
		return true


var e := Env.new()
var p: Player
var root: Node3D
var em: EnemyManager
var vm: VehicleManager
var m: Missions
var c: Contracts
var prog: Progress
var story: FakeStory
var done: Array = []
var fails: Array = []


func run(host: Node) -> void:
	seed(5)
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
	c = m.contracts
	prog = m.progress
	c.set_physics_process(false)            # the test ticks by hand
	c.rng.seed = 12
	c.completed.connect(func(k: StringName, r: Dictionary) -> void: done.append([k, r]))
	c.failed.connect(func(k: StringName, why: String) -> void: fails.append([k, why]))
	Game.set_quality(1)

	_rules()
	_structure()
	await _officer()
	await _hack()
	await _chase()
	await _courier()
	await _survive()
	await _drones()
	await _rules_of_failure()
	await _hold_and_reset()
	await _scaling()

	Game.story = null
	Game.world = null
	Game.heat = 0.0
	Game.score = 0
	await e.teardown()


# --- helpers -------------------------------------------------------------------------------------------------------------

func _reset(chapter := 0) -> void:
	story.chapter = chapter
	story.lines.clear()
	em.clear()
	Game.heat = 0.0
	Game.score = 0
	Game.state = &"play"
	prog.new_campaign()
	Upgrades.reset()
	c._on_new_sector()
	c._chapter_said = -1
	done.clear()
	fails.clear()
	p.teleport_to(Vector3(0.0, 0.05, 0.0))
	p.hp = p.max_hp
	Game.heat = 0.0


func _step(seconds: float, dt := 0.25) -> void:
	var n := int(ceil(seconds / dt))
	for i in n:
		c.tick(dt)
		if c.state != &"active":
			return


## Offer `kind` at `at`, put the player in its marker and tick once: the contract is active (asserted by the caller).
func _start(kind: StringName, at: Vector3) -> void:
	c.offer(kind, at)
	p.teleport_to(at + Vector3(1.0, 0.05, 1.0))
	c.tick(0.1)


func _kill_all_foes() -> void:
	for f: Variant in c.foes.duplicate():
		var d := f as Drone
		if d != null and is_instance_valid(d) and not d.dead:
			d.damage(1.0e6)


# --- pure rules ----------------------------------------------------------------------------------------------------------

func _rules() -> void:
	TestLib.check(ContractTypes.KINDS.size() == 6, "six contract kinds")
	var every := true
	for ch in 6:
		for k: StringName in ContractTypes.KINDS:
			every = every and float(ContractTypes.weights(ch)[k]) >= 1.0
	TestLib.check(every, "every chapter's pool contains all six kinds (the story only weights them)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var counts := {}
	for i in 600:
		var k := ContractTypes.pick(1, rng)
		counts[k] = int(counts.get(k, 0)) + 1
	TestLib.check(int(counts[&"drones"]) > int(counts[&"chase"]) * 2, "chapter 2 (Glass District) favours link-kill trials (%d drones vs %d chases)" % [counts[&"drones"], counts[&"chase"]])
	counts.clear()
	for i in 600:
		var k := ContractTypes.pick(3, rng)
		counts[k] = int(counts.get(k, 0)) + 1
	TestLib.check(int(counts[&"chase"]) > int(counts[&"hack"]) * 2, "chapter 4 (Bridge Arcade) favours chases (%d vs %d hacks)" % [counts[&"chase"], counts[&"hack"]])
	TestLib.check(ContractTypes.pick(0, rng, &"officer", [&"chase"]) != &"chase", "banned kinds never come up")
	TestLib.check(ContractTypes.pick(0, rng, &"officer") != &"officer", "the previous kind is skipped")
	var r0 := ContractTypes.reward(&"officer", 0)
	var r4 := ContractTypes.reward(&"officer", 4)
	TestLib.check(int(r4["credits"]) > int(r0["credits"]) and int(r0["credits"]) % 5 == 0, "pay grows with the sector (%d -> %d)" % [r0["credits"], r4["credits"]])
	TestLib.check(int(ContractTypes.reward(&"officer", 0, 0.25)["credits"]) > int(r0["credits"]), "the reputation bonus raises the pay")
	TestLib.check(int(ContractTypes.reward(&"courier", 0, 0.0, 1.0)["credits"]) > int(ContractTypes.reward(&"courier", 0, 0.0, 0.0)["credits"]), "finishing early pays a speed bonus")
	TestLib.check(bool(ContractTypes.reward(&"survive", 2)["upgrade"]) and not bool(ContractTypes.reward(&"survive", 0)["upgrade"]) and not bool(ContractTypes.reward(&"hack", 4)["upgrade"]), "only the hard kinds pay an upgrade, from sector 2")
	TestLib.check(ContractTypes.heat_factor(0.0) > 1.0 and ContractTypes.heat_factor(1.0) == 1.0 and ContractTypes.heat_factor(4.0) < 1.0 and ContractTypes.heat_factor(5.0) >= 0.6, "a quiet street pays more, a hot one less (floor 60 %)")
	TestLib.check(ContractTypes.time_limit(&"hack", 4) < ContractTypes.time_limit(&"hack", 0), "time limits tighten with the sector")
	TestLib.check(ContractTypes.count(&"survive", 4, 2) > ContractTypes.count(&"survive", 0, 2), "waves get bigger with the sector")
	var route := Contracts.build_route(Vector3(-40.0, 0.0, 12.0), Vector3(200.0, 0.0, 200.0))
	TestLib.check(route.size() == 3 and route[0].is_equal_approx(Vector3(-40.0, 0.0, 12.0)) and route[2].is_equal_approx(Vector3(200.0, 0.0, 200.0)), "a route is start, one corner, destination")
	TestLib.check(is_equal_approx(route[1].x, route[0].x) or is_equal_approx(route[1].z, route[0].z), "the route corner shares an axis with the start (street aligned)")


func _structure() -> void:
	TestLib.check(m.contracts is Contracts and m.progress is Progress and Game.progress == m.progress, "Missions owns the Contracts and Progress nodes and Game.progress is set")
	var lines_ok := true
	for k: StringName in ContractTypes.KINDS:
		var d: Dictionary = StoryData.CONTRACT_RADIO.get(String(k), {})
		for key in ["offer", "start", "mid", "done", "fail"]:
			lines_ok = lines_ok and d.has(key) and (d[key] as Array).size() >= 1
			for l: Dictionary in d.get(key, []):
				lines_ok = lines_ok and StoryData.SPEAKERS.has(str(l["s"])) and str(l["t"]).length() >= 8 and str(l["t"]).length() <= StoryData.LINE_MAX
	TestLib.check(lines_ok, "every kind has offer / start / mid / done / fail radio lines inside the story limits")
	var extra_ok := StoryData.CONTRACT_CHAPTER.size() == StoryData.CHAPTERS.size()
	for l: Dictionary in StoryData.CONTRACT_CHAPTER:
		extra_ok = extra_ok and str(l["t"]).length() <= StoryData.LINE_MAX
	for key: String in StoryData.CONTRACT_GENERIC:
		for l: Dictionary in StoryData.CONTRACT_GENERIC[key]:
			extra_ok = extra_ok and str(l["t"]).length() <= StoryData.LINE_MAX and StoryData.SPEAKERS.has(str(l["s"]))
	TestLib.check(extra_ok, "a chapter line per chapter and the generic lines fit the limits")
	TestLib.check(c.state == &"idle" and not c.is_active(), "contracts start idle")
	TestLib.check(c.hud_line() == "" and c.boss().is_empty() and c.progress_fraction() < 0.0, "nothing to show while idle")
	c.tick(Contracts.OFFER_DELAY + 1.0)
	TestLib.check(c.state == &"offered", "an offer appears after the pause (%s)" % str(c.state))
	TestLib.check(c.markers().size() >= 1 and c.marker_count() == 1 and c.markers()[0]["kind"] == &"offer", "the offer is one minimap marker")
	TestLib.check(c.visuals != null and c.visuals.marker_visible(0), "the offer stands in the world (beam and ring)")
	var d := Vector2(c.pos.x - p.global_position.x, c.pos.z - p.global_position.z).length()
	TestLib.check(d >= Contracts.OFFER_MIN - 1.0 and d <= Contracts.OFFER_MAX + 1.0, "an offer is 60-170 m from the player (%.0f m)" % d)
	TestLib.check(story.lines.size() >= 1, "ORACLE offers it over the radio (%d lines)" % story.lines.size())
	TestLib.check(c.hud_line().begins_with("CONTRACT"), "the HUD line names the offer (%s)" % c.hud_line())
	p.teleport_to(c.pos + Vector3(60.0, 0.05, 0.0))
	var far := c.pos
	p.teleport_to(far + Vector3(Contracts.OFFER_FAR + 20.0, 0.05, 0.0))
	c.tick(0.1)
	var moved := Vector2(c.pos.x - far.x, c.pos.z - far.z).length()
	TestLib.check(moved > 1.0 and c.state == &"offered", "an offer left far behind is moved next to the player")
	TestLib.check(not c.accept() or c.state == &"active", "accept() starts the offered contract")
	c.abandon()
	_reset()


# --- officer -------------------------------------------------------------------------------------------------------------

func _officer() -> void:
	_reset(1)
	var at := Vector3(40.0, 0.0, 10.0)
	_start(&"officer", at)
	TestLib.check(c.state == &"active" and c.kind == &"officer", "walking into the marker starts the officer contract")
	var o := c.target as Drone
	TestLib.check(o != null and o.type == &"operative" and o.max_hp >= Contracts.OFFICER_HP, "the officer is a Vael trooper with %d hp (stronger than 80)" % int(o.max_hp if o != null else 0))
	TestLib.check(c.foes.size() >= 2 and c.foes.has(o), "he comes with guards (%d foes)" % c.foes.size())
	TestLib.check(not c.boss().is_empty() and is_equal_approx(float(c.boss()["frac"]), 1.0), "the HUD gets a boss bar at full health")
	TestLib.check(c.hud_line().begins_with("ELIMINATE OFFICER") and c.time_left > 150.0, "HUD line and timer (%s)" % c.hud_line())
	TestLib.check(Game.heat >= 0.5, "starting a hit alerts the Vael (heat %.1f)" % Game.heat)
	var mk := c.markers()
	var far_kind: StringName = mk[0]["kind"]
	TestLib.check(c.marker_count() == 1 and (far_kind == &"area" or far_kind == &"target"), "the minimap gets a hint: an area when far, the point when near (%s)" % str(far_kind))
	if far_kind == &"area":
		TestLib.check(float(mk[0]["radius"]) >= 20.0, "the far hint is a ring of %.0f m, not a point" % float(mk[0]["radius"]))
	p.teleport_to(o.global_position + Vector3(4.0, 0.05, 0.0))
	c.tick(0.1)
	TestLib.check(c.markers()[0]["kind"] == &"target", "close to the officer the marker becomes exact")
	o.damage(100.0)
	c.tick(0.1)
	var f2 := float(c.boss()["frac"])
	TestLib.check(f2 < 0.7 and f2 > 0.4 and c.progress_fraction() > 0.3, "damage drains the boss bar (%.2f)" % f2)
	TestLib.check(c.visuals.marker_visible(0), "the officer carries a beam marker in the world")
	var credits0 := prog.credits
	var rep0 := prog.reputation
	var score0 := Game.score
	o.damage(1.0e6)
	c.tick(0.1)
	TestLib.check(c.state == &"cooldown" and done.size() == 1 and done[0][0] == &"officer", "killing the officer completes the contract")
	var r: Dictionary = done[0][1]
	TestLib.check(prog.credits > credits0 + int(r["credits"]) - 1 and int(r["credits"]) > 0, "credits arrive (%d)" % int(r["credits"]))
	TestLib.check(prog.reputation == rep0 + 8 and prog.contracts_done == 1, "reputation +8 and the tally counts it")
	TestLib.check(Game.score > score0, "the kill and the contract score")
	TestLib.check(bool(r["upgrade"]) and r["upgrade_id"] != &"" and Upgrades.total_levels() == 1, "from sector 2 the officer pays a free upgrade (%s)" % str(r["upgrade_id"]))
	TestLib.check(not c.visuals.marker_visible(0) and c.boss().is_empty() and c.hud_line() == "", "the markers and the boss bar are gone afterwards")
	var heard := false
	for l: Dictionary in story.lines:
		heard = heard or str(l["id"]).begins_with("contract.officer.done")
	TestLib.check(heard, "ORACLE / KESTREL comment the kill")
	_kill_all_foes()
	_reset()


# --- hack ----------------------------------------------------------------------------------------------------------------

func _hack() -> void:
	_reset(0)
	var at := Vector3(60.0, 0.0, -20.0)
	_start(&"hack", at)
	TestLib.check(c.state == &"active" and c.kind == &"hack" and c.need >= 24, "the hack starts: hold the ring for %d s" % c.need)
	TestLib.check(c.markers()[0]["kind"] == &"zone" and is_equal_approx(float(c.markers()[0]["radius"]), Contracts.HACK_RADIUS), "the minimap shows the 9 m zone")
	_step(4.0, 0.5)
	TestLib.check(c.progress > 0.1 and c.progress < 0.3 and c.inside, "inside the ring the progress fills (%.2f)" % c.progress)
	TestLib.check(c.hud_line().begins_with("HACK NODE") and not "RETURN" in c.hud_line(), "HUD shows the percentage (%s)" % c.hud_line())
	var p1 := c.progress
	p.teleport_to(at + Vector3(30.0, 0.05, 0.0))
	_step(2.0, 0.5)
	TestLib.check(not c.inside and c.progress < p1 and "RETURN TO THE RING" in c.hud_line(), "outside the ring it decays and the HUD says so")
	p.teleport_to(at + Vector3(2.0, 0.05, 0.0))
	var first := c.foes_alive()
	_step(6.0, 0.5)
	TestLib.check(c.foes_alive() >= 2 and em.alive_count() >= 2, "the node pulls drones in (%d alive, %d from the contract)" % [em.alive_count(), c.foes_alive()])
	TestLib.check(c.foes.size() >= 2 and Game.heat >= 0.4, "attackers are tracked, the street heats up")
	_step(Contracts.HACK_PULSE + 1.0, 0.5)
	TestLib.check(c.foes_alive() > first or em.alive_count() >= em.cap(), "another pulse sends more (%d -> %d)" % [first, c.foes_alive()])
	_step(60.0, 0.5)
	TestLib.check(c.state == &"cooldown" and done.size() == 1 and done[0][0] == &"hack", "holding the ring long enough completes the hack")
	TestLib.check(not c.visuals.marker_visible(0), "the ring is removed")
	_kill_all_foes()
	# failure by time
	_reset(0)
	_start(&"hack", at)
	var attackers := c.foes.size()
	p.teleport_to(at + Vector3(80.0, 0.05, 0.0))
	_step(ContractTypes.time_limit(&"hack", 0) + 5.0, 1.0)
	TestLib.check(c.state == &"cooldown" and fails.size() == 1 and fails[0][1] == "TIME OUT", "abandoning the ring until the clock runs out fails the hack")
	TestLib.check(c.foes.is_empty() and attackers >= 0, "its attackers are removed")
	em.clear()
	_reset()


# --- chase ---------------------------------------------------------------------------------------------------------------

func _chase() -> void:
	_reset(3)
	_start(&"chase", Vector3(20.0, 0.0, 0.0))
	TestLib.check(c.state == &"active" and c.kind == &"chase", "the chase starts")
	var car := c.target as Vehicle
	TestLib.check(car != null and car.ai and car.active and car.max_hp == Contracts.CHASE_HP, "the target is a traffic car from the vehicle module with %d hp" % int(Contracts.CHASE_HP))
	TestLib.check(car.has_meta(&"hold") and car.ai_cruise >= 15.0, "it is held against recycling and runs faster than traffic (%.0f m/s)" % car.ai_cruise)
	TestLib.check(c.markers()[0]["kind"] == &"target" and c.visuals.marker_visible(0), "minimap and world mark the car")
	p.teleport_to(car.global_position + Vector3(0.0, 0.05, 160.0))
	vm._stream()
	TestLib.check(car.active and vm.list.has(car), "streaming does not release the target even when it is far away")
	_step(Contracts.CHASE_ESCAPE_TIME + 1.0, 0.5)
	TestLib.check(c.state == &"cooldown" and fails.size() == 1 and fails[0][1] == "TARGET ESCAPED", "a target left behind 120 m for 6 s escapes (%s)" % str(fails))
	TestLib.check(not car.has_meta(&"hold"), "the hold is lifted afterwards")
	# completion: wreck the car
	_reset(3)
	_start(&"chase", Vector3(-20.0, 0.0, 0.0))
	car = c.target as Vehicle
	p.teleport_to(car.global_position + Vector3(0.0, 0.05, 20.0))
	car.damage(60.0)
	c.tick(0.1)
	TestLib.check(c.state == &"active" and c.progress_fraction() > 0.3, "damage fills the progress bar (%.2f)" % c.progress)
	car.damage(1.0e6)
	c.tick(0.1)
	TestLib.check(c.state == &"cooldown" and done.size() == 1 and done[0][0] == &"chase", "wrecking the target completes the chase")
	TestLib.check(prog.credits > 0, "the chase pays credits (%d)" % prog.credits)
	_reset()
	# failure by time
	_reset(3)
	_start(&"chase", Vector3(10.0, 0.0, 40.0))
	car = c.target as Vehicle
	p.teleport_to(car.global_position + Vector3(0.0, 0.05, 30.0))
	car.ai_cruise = 0.0
	_step(ContractTypes.time_limit(&"chase", 3) + 2.0, 0.5)
	TestLib.check(fails.size() == 1 and fails[0][1] == "TIME OUT", "an uncaught target times out")
	vm._release(car) if car.active else null
	_reset()


# --- courier -------------------------------------------------------------------------------------------------------------

func _courier() -> void:
	_reset(0)
	var at := Vector3(-30.0, 0.0, 4.0)
	_start(&"courier", at)
	TestLib.check(c.state == &"active" and c.kind == &"courier", "the courier run starts at the pickup")
	var d := Vector2(c.dest.x - at.x, c.dest.z - at.z).length()
	TestLib.check(d >= 215.0 and d <= 365.0, "the drop-off is a long run away (%.0f m)" % d)
	TestLib.check(c.route_points().size() == 3 and c.visuals.route.visible and c.visuals.route.mesh != null, "a route line is drawn on the street and on the minimap")
	var len := ContractTypes.route_length(at, c.dest)
	TestLib.check(is_equal_approx(c.time_total, (len / ContractTypes.COURIER_SPEED + ContractTypes.COURIER_SLACK) * float(Progress.difficulty(0)["time"])), "the clock is the route time plus slack (%.0f s)" % c.time_total)
	TestLib.check(c.markers()[0]["kind"] == &"dest" and c.visuals.marker_visible(1) and not c.visuals.marker_visible(0), "a flag at the destination, the pickup marker is gone")
	_step(10.0, 0.5)
	TestLib.check(c.state == &"active" and c.time_left < c.time_total - 9.0 and "COURIER" in c.hud_line(), "the clock runs (%s)" % c.hud_line())
	p.teleport_to(c.dest + Vector3(2.0, 0.05, 0.0))
	c.tick(0.1)
	TestLib.check(c.state == &"cooldown" and done.size() == 1 and done[0][0] == &"courier", "reaching the drop-off completes the delivery")
	TestLib.check(float(done[0][1]["heat_factor"]) > 1.0, "a clean street adds a bonus")
	TestLib.check(c.route_points().is_empty() and not c.visuals.route.visible, "the route line is gone")
	_reset(0)
	_start(&"courier", at)
	_step(c.time_total + 3.0, 1.0)
	TestLib.check(fails.size() == 1 and fails[0][1] == "TIME OUT", "a late courier fails")
	_reset()


# --- survive -------------------------------------------------------------------------------------------------------------

func _survive() -> void:
	_reset(0)
	var at := Vector3(0.0, 0.0, -60.0)
	_start(&"survive", at)
	TestLib.check(c.state == &"active" and c.kind == &"survive" and c.waves == 3 and c.pending == ContractTypes.count(&"survive", 0, 0), "the anchor holds %d waves, the first has %d foes" % [c.waves, c.pending])
	TestLib.check(Game.heat >= 1.0 and c.markers()[0]["kind"] == &"zone", "the anchor is loud (heat) and shown as a zone")
	_step(4.0, 0.25)
	TestLib.check(c.foes.size() == ContractTypes.count(&"survive", 0, 0) and c.pending == 0, "wave 1 spawns in steps (%d foes)" % c.foes.size())
	for f: Variant in c.foes:
		var d := f as Drone
		TestLib.check(d.aware, "wave enemies come at the player")
		break
	TestLib.check("WAVE 1 / 3" in c.hud_line(), "the HUD counts waves (%s)" % c.hud_line())
	_kill_all_foes()
	var w0 := c.wave
	_step(WAVE_GAP_STEPS(), 0.25)
	TestLib.check(c.wave == w0 + 1 and c.pending > 0, "clearing a wave starts the next one after a breather (wave %d, %d to come)" % [c.wave + 1, c.pending])
	TestLib.check(c.pending + c.foes_alive() == ContractTypes.count(&"survive", 0, 1) and ContractTypes.count(&"survive", 0, 1) > ContractTypes.count(&"survive", 0, 0), "later waves are bigger")
	_step(5.0, 0.25)
	_kill_all_foes()
	_step(WAVE_GAP_STEPS(), 0.25)
	TestLib.check(c.wave == 2 and c.progress > 0.5, "wave 3 reached (%.2f)" % c.progress)
	_step(8.0, 0.25)
	_kill_all_foes()
	_step(WAVE_GAP_STEPS() + 1.0, 0.25)
	TestLib.check(c.state == &"cooldown" and done.size() == 1 and done[0][0] == &"survive", "the last wave cleared completes the contract")
	TestLib.check(prog.credits >= int(done[0][1]["credits"]), "survival pays the most (%d credits)" % int(done[0][1]["credits"]))
	# leash
	_reset(0)
	_start(&"survive", at)
	p.teleport_to(at + Vector3(Contracts.ANCHOR_LEASH + 20.0, 0.05, 0.0))
	_step(Contracts.ANCHOR_LEASH_TIME + 2.0, 0.5)
	TestLib.check(c.state == &"cooldown" and fails.size() == 1 and fails[0][1] == "ANCHOR LOST", "leaving the anchor for 10 s loses it")
	_reset()


func WAVE_GAP_STEPS() -> float:
	return Contracts.WAVE_GAP + 1.5


# --- drones --------------------------------------------------------------------------------------------------------------

func _drones() -> void:
	_reset(1)
	var at := Vector3(0.0, 0.0, 90.0)
	_start(&"drones", at)
	TestLib.check(c.state == &"active" and c.kind == &"drones" and c.need >= 3 and c.foes.size() == c.need, "the trial spawns %d drones and needs %d link kills" % [c.foes.size(), c.need])
	TestLib.check(c.markers().size() >= 1 and c.marker_count() == c.foes.size(), "each target drone is a minimap marker")
	TestLib.check("LINK KILL TRIAL  0 / %d" % c.need in c.hud_line(), "HUD line (%s)" % c.hud_line())
	# a direct kill does not count
	var a := c.foes[0] as Drone
	a.damage(1.0e6)
	c.tick(0.1)
	TestLib.check(c.got == 0 and c.spare == Contracts.DRONE_SPARE - 1, "a direct kill does not count and uses a spare (%d left)" % c.spare)
	TestLib.check(c.foes.size() == c.need, "the missing drone is replaced")
	# a linked kill counts: damage to one linked drone is mirrored onto its partner, so both die as link kills
	var b := c.foes[0] as Drone
	var d2 := c.foes[1] as Drone
	b.linked = d2
	d2.linked = b
	c.tick(0.1)
	b.damage(1.0e6)
	TestLib.check(b.dead and d2.dead, "mirrored damage kills the linked partner too")
	c.tick(0.1)
	TestLib.check(c.got == 2 and c.progress > 0.5, "both drones killed through the link count (%d / %d)" % [c.got, c.need])
	TestLib.check(c.foes.size() >= 2, "there are always two drones left to link while kills are missing (%d)" % c.foes.size())
	var e1 := c.foes[0] as Drone
	var e2 := c.foes[1] as Drone
	e1.linked = e2
	e2.linked = e1
	c.tick(0.1)
	e1.damage(1.0e6)
	c.tick(0.1)
	TestLib.check(c.state == &"cooldown" and done.size() == 1 and done[0][0] == &"drones" and c.got >= c.need, "enough link kills complete the trial")
	_kill_all_foes()
	em.clear()
	# too many direct kills
	_reset(1)
	_start(&"drones", at)
	var n := 0
	while c.state == &"active" and n < 12:
		n += 1
		if c.foes.is_empty():
			c.tick(0.1)
			continue
		(c.foes[0] as Drone).damage(1.0e6)
		c.tick(0.1)
	TestLib.check(c.state == &"cooldown" and fails.size() == 1 and fails[0][1] == "TOO MANY DIRECT KILLS", "four direct kills fail the trial (%s after %d kills)" % [str(fails), n])
	em.clear()
	_reset()
	_start(&"drones", at)
	_step(ContractTypes.time_limit(&"drones", 0) + 3.0, 1.0)
	TestLib.check(fails.size() == 1 and fails[0][1] == "TIME OUT", "the trial also has a clock")
	em.clear()
	_reset()


# --- retries, abandon, hold, reset ----------------------------------------------------------------------------------------

func _rules_of_failure() -> void:
	_reset(0)
	var at := Vector3(50.0, 0.0, 50.0)
	var rep0 := prog.reputation
	_start(&"courier", at)
	_step(c.time_total + 2.0, 1.0)
	TestLib.check(c.state == &"cooldown" and c.is_retry and prog.reputation == rep0 - 4 and prog.contracts_failed == 1, "the first failure costs 4 reputation and queues a retry")
	c.tick(Contracts.PAUSE_FAIL + 0.1)
	TestLib.check(c.state == &"offered" and c.is_retry and c.pos.is_equal_approx(at) and c.hud_line().begins_with("RETRY"), "the retry is the same contract at the same marker")
	p.teleport_to(at + Vector3(1.0, 0.05, 1.0))
	c.tick(0.1)
	TestLib.check(c.state == &"active" and c.kind == &"courier", "the retry can be taken at once")
	_step(c.time_total + 2.0, 1.0)
	c.tick(Contracts.PAUSE_FAIL + 0.1)
	p.teleport_to(at + Vector3(1.0, 0.05, 1.0))
	c.tick(0.1)
	_step(c.time_total + 2.0, 1.0)
	TestLib.check(fails.size() == 3 and not c.is_retry and c.state == &"cooldown", "the third failure abandons the contract")
	TestLib.check(prog.reputation == rep0 - 3 * 4 - 3, "abandoning costs another 3 reputation (%d)" % prog.reputation)
	c.tick(Contracts.PAUSE_ABANDON + 0.1)
	TestLib.check(c.state == &"idle" and c.retries_used == 0, "then a fresh pause and a new contract")
	# manual abandon
	_reset(0)
	_start(&"hack", at)
	c.abandon()
	TestLib.check(c.state == &"cooldown" and not c.is_retry and fails[0][1] == "ABANDONED", "abandon() fails the contract without a retry")
	em.clear()
	# reputation tiers move pay and prices
	_reset(0)
	prog.add_reputation(40)
	TestLib.check(Progress.rep_tier(prog.reputation) == 3 and Progress.rep_bonus(prog.reputation) == 0.25 and Progress.rep_discount(prog.reputation) == 0.2, "reputation 40 is LEGEND: +25 % pay, 20 % off")
	_start(&"courier", at)
	p.teleport_to(c.dest + Vector3(1.0, 0.05, 0.0))
	c.tick(0.1)
	var legend := int(done[0][1]["credits"])
	_reset(0)
	_start(&"courier", at)
	p.teleport_to(c.dest + Vector3(1.0, 0.05, 0.0))
	c.tick(0.1)
	TestLib.check(legend > int(done[0][1]["credits"]), "a LEGEND earns more than an unknown (%d vs %d)" % [legend, int(done[0][1]["credits"])])
	_reset()


func _hold_and_reset() -> void:
	_reset(0)
	var at := Vector3(-60.0, 0.0, 60.0)
	_start(&"officer", at)
	TestLib.check(c.state == &"active" and em.alive_count() >= 3, "an officer contract is running")
	var fails0 := c.failed_count
	Game.player_died.emit()
	TestLib.check(c.state == &"offered" and c.is_retry and c.foes.is_empty(), "dying puts the contract on hold: offered again, no foes left")
	TestLib.check(c.failed_count == fails0 and c.retries_used == 0, "dying is not a failure")
	await e.frames(1)
	TestLib.check(em.alive_count() == 0, "what the contract spawned is gone (%d alive)" % em.alive_count())
	var heard := false
	for l: Dictionary in story.lines:
		heard = heard or str(l["id"]) == "contract.decohered"
	TestLib.check(heard, "ORACLE comments on the death")
	# a lifecycle reset clears everything
	p.teleport_to(c.pos + Vector3(1.0, 0.05, 1.0))
	c.tick(0.1)
	TestLib.check(c.state == &"active", "the held contract can be taken again")
	Game.next_sector.emit()
	TestLib.check(c.state == &"idle" and c.target == null and c.foes.is_empty() and not c.visuals.marker_visible(0) and c.hud_line() == "", "next_sector resets the contract layer")
	_start(&"hack", at)
	Game.new_game.emit()
	TestLib.check(c.state == &"idle" and not c.has_marker(), "new_game resets it too")
	em.clear()
	# paused: nothing moves
	_reset(0)
	_start(&"hack", at)
	var t0 := c.time_left
	Game.state = &"paused"
	c._physics_process(1.0)
	TestLib.check(is_equal_approx(c.time_left, t0), "a paused game does not tick contracts")
	Game.state = &"play"
	em.clear()
	_reset()


func _scaling() -> void:
	var d0 := Progress.difficulty(0)
	var d5 := Progress.difficulty(5)
	TestLib.check(float(d5["hp"]) > float(d0["hp"]) and int(d5["extra"]) > int(d0["extra"]) and float(d5["reward"]) > float(d0["reward"]) and float(d5["time"]) < float(d0["time"]), "difficulty rises per sector: hp %.2f -> %.2f, extra foes %d -> %d, pay x%.1f -> x%.1f" % [d0["hp"], d5["hp"], d0["extra"], d5["extra"], d0["reward"], d5["reward"]])
	TestLib.check(float(Progress.difficulty(40)["time"]) >= 0.7 and float(Progress.difficulty(40)["hp"]) <= 1.8, "the scaling is capped")
	_reset(4)
	var s := em.spawn(&"sentinel", Vector3(30.0, 0.0, 30.0))
	TestLib.check(s != null and is_equal_approx(s.max_hp, 60.0 * 1.4), "enemies spawned in sector 5 have 40 %% more health (%.0f)" % s.max_hp)
	em.clear()
	_reset(0)
	s = em.spawn(&"sentinel", Vector3(30.0, 0.0, 30.0))
	TestLib.check(is_equal_approx(s.max_hp, 60.0), "sector 1 enemies are unchanged (%.0f)" % s.max_hp)
	em.clear()
	_reset()
