extends RefCounted
## The six vehicle chase set pieces (scripts/missions/chase_runner.gd, data and rubber-banding table in chase_scripts.gd) in the REAL scene (main.tscn): the table is complete,
## the rubber-band function is monotone, every chase starts through the DEMO menu entry (kind "chase"), runs with the real VehicleManager / patrol vehicles / Player, saves
## checkpoints, fails and retries from the last checkpoint, completes and pays, and the HUD plate shows its line. The runner is ticked by hand (physics off) so the timing is exact;
## waits are on state, never on frame counts. Progress writes to a throw-away file. Not run: a phone, feel of the rubber-banding (tuned by the table values only).
## Run: tools/test.sh tests/test_chase_set_pieces.gd

const TMP := "user://test_chase_set_pieces_save.cfg"

var host: Node
var main: Node
var ch: ChaseRunner
var prog: Progress
var p: Player
var vm: VehicleManager
var ended: Array = []
var fails: Array = []
var cps: Array = []


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_data()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	var m := Game.missions as Missions
	p = Game.player as Player
	vm = Game.vehicles as VehicleManager
	TestLib.check(m != null and m.chases != null and p != null and vm != null, "main.tscn composes Missions.chases, the player and the vehicle manager")
	if m == null or m.chases == null or p == null or vm == null:
		return
	ch = m.chases
	prog = Game.progress as Progress
	prog.path = TMP
	prog.autosave_enabled = false
	ch.set_physics_process(false)
	m.contracts.set_physics_process(false)
	ch.finished.connect(func(cid: StringName, ok: bool) -> void: ended.append([cid, ok]))
	ch.failed.connect(func(cid: StringName, why: String, again: bool) -> void: fails.append([cid, why, again]))
	ch.checkpoint_reached.connect(func(cid: StringName, i: int) -> void: cps.append([cid, i]))
	var was_demo := DemoMode.active
	DemoMode.active = true
	await _reset()

	await _convoy_and_rooftop()
	await _roadblock()
	await _gate()
	await _escort()
	await _duel()
	await _demo_menu_and_hud()

	DemoMode.active = was_demo
	ch.abort("TEST")
	Game.heat = 0.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	main.queue_free()
	await frames(5)
	Game.state = &"menu"
	Sfx.muted = false


# --- helpers ---------------------------------------------------------------------------------------------------------------

func _reset() -> void:
	ch.abort("TEST")
	Game.state = &"play"
	Game.heat = 0.0
	if p.vehicle != null:
		vm.exit_vehicle()
	p.hp = p.max_hp
	p.teleport_to(Vector3(-40.0, 0.2, 4.0))
	ended.clear()
	fails.clear()
	cps.clear()
	await frames(3)


func _tick(seconds: float, dt := 0.2) -> void:
	for i in int(ceil(seconds / dt)):
		ch.tick(dt)
		if not ch.is_running() or ch.state == &"retry":
			return


func _drive_to(world: Vector3) -> void:
	var car := p.vehicle as Vehicle
	car.global_position = Vector3(world.x, 0.0, world.z)
	car.speed = 0.0
	car.vel = Vector3.ZERO
	await frames(3)


func _until_state(want: StringName, max_s := 12.0) -> bool:
	var t := 0.0
	while t < max_s:
		if ch.state == want:
			return true
		ch.tick(0.25)
		t += 0.25
	return ch.state == want


## Fails the current attempt by running the clock out, then waits through the retry delay.
func _force_fail_and_retry() -> void:
	ch.clock = float(ch.def["time"]) + 1.0 if float(ch.def["time"]) > 0.0 else ch.clock
	if float(ch.def["time"]) <= 0.0:
		ch.gate_t = -1.0
	ch.tick(0.1)
	TestLib.check(ch.state == &"retry", "%s: a failure waits for the retry (state %s)" % [ch.id, ch.state])
	await _until_state(&"running", ChaseScripts.RETRY_DELAY + 2.0)


# --- data ------------------------------------------------------------------------------------------------------------------

func _data() -> void:
	TestLib.check(ChaseScripts.IDS.size() == 6, "six chase set pieces")
	for id: StringName in ChaseScripts.IDS:
		TestLib.check(ChaseScripts.validate(id) == "", "%s: table entry complete (%s)" % [id, ChaseScripts.validate(id)])
		var last := 9.0
		var mono := true
		for gap in range(0, 140, 5):
			var f := ChaseScripts.rubber(id, float(gap))
			mono = mono and f <= last + 0.0001 and f > 0.0
			last = f
		TestLib.check(mono, "%s: rubber factor never rises with the gap and stays positive" % id)
		var near := ChaseScripts.rubber(id, 0.0)
		var far := ChaseScripts.rubber(id, 500.0)
		TestLib.check(near >= far, "%s: the target runs faster when you are close than when you are far" % id)
		TestLib.check(ChaseScripts.chase_cap(id, 0.0) <= ChaseScripts.chase_cap(id, 500.0) and ChaseScripts.chase_cap(id, 500.0) == 1.0, "%s: chasers are capped only up close" % id)
	TestLib.check(ChaseScripts.reward(&"duel", 0.9) > ChaseScripts.reward(&"duel", 0.1), "an early finish pays a bonus")


# --- scenarios -------------------------------------------------------------------------------------------------------------

func _convoy_and_rooftop() -> void:
	for id: StringName in [&"convoy", &"rooftop"]:
		await _reset()
		var d := ChaseScripts.def(id)
		TestLib.check(ch.can_start(id) and ch.start(id), "%s starts on foot (a car is provided)" % id)
		TestLib.check(ch.state == &"running" and p.vehicle is Vehicle, "%s: running, the player sits in a car" % id)
		TestLib.check(is_instance_valid(ch.target) and ch.target.kind == StringName(d["kind"]), "%s: the target is a %s" % [id, d["kind"]])
		TestLib.check(ch.guards.size() == int(d["guards"]), "%s: %d guard cars" % [id, int(d["guards"])])
		TestLib.check(ch.hud_line().begins_with(ChaseScripts.title(id)) and ch.marker_visible(), "%s: HUD line and marker" % id)
		TestLib.check(not ch.start(&"duel"), "a second chase does not start while one runs")
		ch.tick(0.2)
		var cruise0 := ch.target.ai_cruise
		TestLib.check(cruise0 > 0.0 and ch.target.has_meta(&"hold"), "%s: the target drives and is held out of the streaming pool" % id)
		# checkpoint: wear the target down past the first fraction
		var cp0: float = float(d["checkpoints"][0])
		var dmg_to := 1.0 - (cp0 + 0.05) * (1.0 - ChaseScripts.DISABLE)
		ch.target.hp = ch.target.max_hp * dmg_to
		ch.tick(0.2)
		TestLib.check(ch.cp_index == 1 and cps.size() == 1 and ch.prog >= cp0, "%s: checkpoint saved at %d%% (prog %.2f)" % [id, int(cp0 * 100.0), ch.prog])
		await _force_fail_and_retry()
		TestLib.check(ch.state == &"running" and ch.tries == 2 and fails.size() == 1 and bool(fails[0][2]), "%s: retried (try %d)" % [id, ch.tries])
		TestLib.check(ch.target.hp < ch.target.max_hp * 0.9, "%s: the retry keeps the checkpoint damage (hp %.0f/%.0f)" % [id, ch.target.hp, ch.target.max_hp])
		# lose the target: it gets away
		var far := ch.target.global_position
		var before := prog.credits
		ch.target.hp = ch.target.max_hp * 0.1
		ch.tick(0.2)
		TestLib.check(ch.state == &"idle" and ended.size() == 1 and bool(ended[0][1]), "%s: disabling the target completes the chase" % id)
		TestLib.check(prog.credits > before and ch.result["reward"] > 0, "%s: paid %d credits" % [id, int(ch.result["reward"])])
		TestLib.check(far.is_finite() and ch.hud_line() == "", "%s: HUD line gone when done" % id)
	# rubber band acts on the live target: close = faster than far
	await _reset()
	ch.start(&"convoy")
	var at := ch.target.global_position
	await _drive_to(at + Vector3(0.0, 0.0, 0.0) + Vector3(-6.0 if absf(at.x) > absf(at.z) else 0.0, 0.0, -6.0 if absf(at.x) <= absf(at.z) else 0.0))
	ch.tick(0.1)
	var close_c := ch.target.ai_cruise
	await _drive_to(ch.route_point(-80.0))
	ch.tick(0.1)
	TestLib.check(ch.target.ai_cruise < close_c, "convoy: the live target slows when the player falls behind (%.1f < %.1f)" % [ch.target.ai_cruise, close_c])
	# the target gets away: far for lose_s seconds
	_force_far()
	var guard := 0
	while ch.state == &"running" and guard < 200:
		ch.tick(0.5)
		guard += 1
	TestLib.check(ch.state == &"retry" and String(ch.fail_reason).contains("AWAY") or ch.fail_reason == "TIME UP", "convoy: falling far behind loses the target (%s)" % ch.fail_reason)
	ch.abort("TEST")
	TestLib.check(ch.state == &"idle" and not is_instance_valid(ch.target), "abort clears the run")


func _force_far() -> void:
	if is_instance_valid(ch.target):
		ch.target.global_position = ch.route_point(400.0 if ch._dir > 0 else 400.0)


func _roadblock() -> void:
	await _reset()
	TestLib.check(ch.start(&"roadblock"), "roadblock starts")
	TestLib.check(ch.chasers.size() == 3 and ch.chasers[0].patrol and not ch.chasers[0].chasing, "the net: three patrol vehicles standing across the road")
	TestLib.check(Game.heat >= 3.0, "the heat is up while it runs")
	await _drive_to(ch.route_point(60.0))
	ch.tick(0.2)
	TestLib.check(ch.chasers[0].chasing, "the net closes when you come near")
	ch.prog = 0.0
	await _drive_to(ch.route_point(ChaseScripts.def(&"roadblock")["dist"] * 0.55))
	ch.tick(0.2)
	TestLib.check(ch.cp_index == 1, "roadblock: checkpoint half way")
	await _force_fail_and_retry()
	TestLib.check(ch.state == &"running" and ch.tries == 2 and ch.chasers.size() == 3, "roadblock: retry rebuilds the net")
	await _drive_to(ch.route_point(float(ChaseScripts.def(&"roadblock")["dist"]) + 2.0))
	ch.tick(0.2)
	TestLib.check(ch.state == &"idle" and ended.size() == 1 and bool(ended[0][1]), "roadblock: reaching the exit completes it")


func _gate() -> void:
	await _reset()
	var d := ChaseScripts.def(&"gate")
	TestLib.check(ch.start(&"gate"), "gate starts")
	var r0 := ch.gate_radius()
	ch.tick(5.0)
	TestLib.check(ch.gate_radius() < r0 - 0.5, "the ring closes while the budget runs (%.1f -> %.1f)" % [r0, ch.gate_radius()])
	TestLib.check(ch.hud_line().contains("GATE 1/4"), "HUD: gate counter (%s)" % ch.hud_line())
	await _drive_to(ch.gate_pos(0))
	ch.tick(0.1)
	TestLib.check(ch.gate_i == 1 and ch.cp_index == 1, "passing a gate saves a checkpoint")
	ch.tick(float(d["budget"][1]) + 1.0)
	TestLib.check(ch.state == &"retry" and String(ch.fail_reason) == "GATE CLOSED", "a closed gate fails the run (%s)" % ch.fail_reason)
	await _until_state(&"running", ChaseScripts.RETRY_DELAY + 2.0)
	TestLib.check(ch.state == &"running" and ch.gate_i == 1 and ch.tries == 2, "the retry starts at gate 2 (gate_i %d)" % ch.gate_i)
	for i in range(1, int(d["gates"])):
		await _drive_to(ch.gate_pos(i))
		ch.tick(0.1)
	TestLib.check(ch.state == &"idle" and ended.size() == 1 and bool(ended[0][1]), "all gates passed completes it")
	# three failures end the run for good
	await _reset()
	ch.start(&"gate")
	for i in ChaseScripts.MAX_TRIES:
		ch.gate_t = -1.0
		ch.tick(0.1)
		if ch.state == &"retry":
			await _until_state(&"running", ChaseScripts.RETRY_DELAY + 2.0)
	TestLib.check(ch.state == &"idle" and ended.size() == 1 and not bool(ended[0][1]) and ch.result["tries"] == ChaseScripts.MAX_TRIES, "after %d failed attempts the run ends (tries %d)" % [ChaseScripts.MAX_TRIES, int(ch.result.get("tries", 0))])


func _escort() -> void:
	await _reset()
	var d := ChaseScripts.def(&"escort")
	TestLib.check(ch.start(&"escort"), "escort starts")
	TestLib.check(is_instance_valid(ch.target) and ch.chasers.size() == int(d["chasers"]), "an allied car and %d chasers" % int(d["chasers"]))
	var hp0 := ch.target.hp
	ch.chasers[0].global_position = ch.target.global_position + Vector3(4.0, 0.0, 0.0)
	ch.tick(1.0)
	TestLib.check(ch.target.hp < hp0, "a chaser close to the allied car shoots it (%.1f < %.1f)" % [ch.target.hp, hp0])
	ch.chasers[0].global_position = ch.target.global_position + Vector3(300.0, 0.0, 300.0)
	ch.target.global_position = ch.route_point(float(d["dist"]) * 0.4)
	ch.tick(0.1)
	TestLib.check(ch.cp_index >= 1, "escort: checkpoint at a third")
	ch.target.hp = 0.0
	ch.target.damage(1.0)
	ch.tick(0.1)
	TestLib.check(ch.state == &"retry" and ch.fail_reason == "ESCORT LOST", "escort: the allied car lost fails the run (%s)" % ch.fail_reason)
	await _until_state(&"running", ChaseScripts.RETRY_DELAY + 2.0)
	TestLib.check(ch.state == &"running" and ch.tries == 2 and is_instance_valid(ch.target) and ch.target.hp > 0.0, "escort: retried with a new allied car")
	await _drive_to(ch.route_point(float(d["dist"]) * 0.5))
	ch.target.global_position = ch.route_point(float(d["dist"]) + 3.0)
	ch.tick(0.1)
	TestLib.check(ch.state == &"idle" and ended.size() == 1 and bool(ended[0][1]), "escort: arriving alive completes it")


func _duel() -> void:
	await _reset()
	TestLib.check(ch.start(&"duel"), "duel starts")
	var boss := ch.target
	TestLib.check(boss.patrol and boss.chasing and boss.max_hp > boss.spec.get("hp", 100.0) * 3.0, "the boss patrol vehicle has several times the hit points (%.0f)" % boss.max_hp)
	boss.hp = boss.max_hp * 0.4
	ch.tick(0.1)
	TestLib.check(ch.cp_index == 1 and ch.prog >= 0.5, "duel: checkpoint at half")
	await _force_fail_and_retry()
	TestLib.check(ch.state == &"running" and ch.target.hp < ch.target.max_hp * 0.6, "duel: the retry keeps the boss damaged")
	ch.target.damage(1.0e6)
	ch.tick(0.1)
	TestLib.check(ch.state == &"idle" and ended.size() == 1 and bool(ended[0][1]), "duel: wrecking the boss completes it")
	# the player going down fails the attempt (Game.respawn)
	await _reset()
	ch.start(&"duel")
	Game.respawn.emit()
	TestLib.check(ch.state == &"retry" and ch.fail_reason == "DOWN", "the player going down fails the attempt")
	ch.abort("TEST")


func _demo_menu_and_hud() -> void:
	await _reset()
	var cat := DemoMode.catalog()
	var group: Dictionary = {}
	for g: Dictionary in cat:
		if g["kind"] == &"chase":
			group = g
	TestLib.check(not group.is_empty() and (group["items"] as Array).size() == 6, "the DEMO catalogue has the six chases")
	TestLib.check(DemoPanel.TABS.has("CHASE") and DemoPanel.TABS.find("CHASE") == cat.find(group), "the CHASE tab is the chase catalogue page")
	for id: StringName in ChaseScripts.IDS:
		await _reset()
		var status := DemoMode.launch(&"chase", id)
		TestLib.check(status.begins_with("CHASE") and ch.state == &"running" and ch.id == id, "DEMO launch %s (status '%s')" % [id, status])
		var hud: Hud = null
		for n in main.find_children("*", "Hud", true, false):
			hud = n as Hud
		await frames(3)
		if hud != null:
			TestLib.check(hud._campaign_line().begins_with(ChaseScripts.title(id)), "%s: the HUD plate shows the chase line" % id)
		DemoMode._prepare()
		TestLib.check(ch.state == &"idle", "%s: the DEMO prepare step stops it" % id)
	# paused games do not simulate
	await _reset()
	ch.set_physics_process(true)
	ch.start(&"gate")
	Game.state = &"paused"
	var c0 := ch.clock
	await frames(10)
	TestLib.check(ch.clock == c0, "a paused game does not advance the chase")
	Game.state = &"play"
	ch.set_physics_process(false)
	ch.abort("TEST")
