extends RefCounted
## "Escape the Vael patrol": an escape step with `patrol` n sends real Vael patrol vehicles (wave 14: hover chassis, siren, rams) after the player the moment it starts, within the
## tier's patrol cap, tops the chase up while the heat is up, shows it on the HUD line and the minimap, and is only done when the player is far, the heat is low AND no chasing
## patrol is close. Also the data side: normalising the key and the two campaign steps that carry it. Same fixture as test_campaign_review.gd (real Player, Missions, VehicleManager).
## Run: tools/test.sh tests/test_campaign_patrol.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const RT := preload("res://tests/test_campaign_runner.gd")
const TMP := "user://test_campaign_patrol_save.cfg"

## A world whose road query always has an answer: a point on the north-south road nearest to the player, between rmin and rmax ahead of him.
class PatrolWorld extends RT.World:
	func road_point_near(center: Vector3, rmin: float, rmax: float) -> Vector3:
		return Vector3(VehicleSpecs.road_center(VehicleSpecs.road_index(center.x)) + 1.0, 0.0, clampf(center.z + (rmin + rmax) * 0.5, -250.0, 250.0))

var e := Env.new()
var p: Player
var root: Node3D
var vm: VehicleManager
var m: Missions
var camp: CampaignRunner
var prog: Progress
var story: RT.FakeStory
var done_steps: Array = []
var failed_steps: Array = []


func _reset() -> void:
	camp.abort()
	camp.enabled = false
	for v in vm.list.duplicate():
		vm._release(v)
	vm.patrols_spawned = 0
	Game.heat = 0.0
	Game.score = 0
	Game.state = &"play"
	prog.autosave_enabled = false
	prog.new_campaign()
	story.chapter = 0
	m.win_on_cores = true
	done_steps.clear()
	failed_steps.clear()
	p.hp = p.max_hp
	p.invuln = 0.0
	p.teleport_to(Vector3(0.0, 0.05, 0.0))


func _begin(steps: Array) -> bool:
	_reset()
	camp.set_chapters([{"id": "patrol_ch", "steps": steps}])
	var ok := camp.start_chapter(0, 0, true)
	camp.tick(0.1)
	return ok


func _tick(seconds: float, dt := 0.25) -> void:
	for i in int(ceil(seconds / dt)):
		camp.tick(dt)


func _data() -> void:
	var n := CampaignSteps.normalize_step({"kind": "escape"}, 0)
	TestLib.check(int(n["patrol"]) == 0, "an escape step has no patrol by default")
	TestLib.check(int(CampaignSteps.normalize_step({"kind": "escape", "patrol": 2}, 0)["patrol"]) == 2, "patrol 2 is kept")
	TestLib.check(int(CampaignSteps.normalize_step({"kind": "escape", "patrol": 9}, 0)["patrol"]) == 3 and int(CampaignSteps.normalize_step({"kind": "escape", "patrol": -4}, 0)["patrol"]) == 0, "patrol is clamped to 0..3")
	TestLib.check(not CampaignSteps.normalize_step({"kind": "hack"}, 0).has("patrol"), "only escape steps get the key")
	var with_patrol := 0
	var consistent := true
	var ch_index: Array[int] = []
	for i in CampaignData.count():
		for st: Dictionary in CampaignData.CAMPAIGN[i]["steps"]:
			if str(st["kind"]) != "escape":
				continue
			var mentions := str(st["obj"]).to_lower().contains("patrol")
			var has := int(st.get("patrol", 0)) > 0
			consistent = consistent and mentions == has
			if has:
				with_patrol += 1
				ch_index.append(i)
			TestLib.check(CampaignSteps.validate_step(st) == "", "chapter %d escape step '%s' validates" % [i + 1, st["obj"]])
	TestLib.check(with_patrol == 2 and ch_index == [3, 6], "the two 'Escape the Vael patrol' steps (chapters 4 and 7) carry a patrol, the others (forge, gate) do not (%s)" % str(ch_index))
	TestLib.check(consistent, "an escape step names a patrol exactly when it sends one")
	var by_chapter := {}
	for ci in ch_index:
		for st: Dictionary in CampaignData.CAMPAIGN[ci]["steps"]:
			if str(st["kind"]) == "escape":
				by_chapter[ci] = int(st.get("patrol", 0))
	TestLib.check(int(by_chapter[6]) >= int(by_chapter[3]), "the chapter 7 sweep asks for at least as many patrols as chapter 4 (%s)" % str(by_chapter))


func run(host: Node) -> void:
	seed(21)
	_data()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	await e.setup(host)
	p = e.p
	root = e.root
	Fixture.add_floor(root, 600.0)
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	var w := PatrolWorld.new()
	w.intersections = CityLayout.make_intersections()
	root.add_child(w)
	Game.world = w
	story = RT.FakeStory.new()
	root.add_child(story)
	Game.story = story
	var em := (load("res://scenes/enemy_manager.tscn") as PackedScene).instantiate() as EnemyManager
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
	camp.set_physics_process(false)
	m.contracts.set_physics_process(false)
	vm.set_physics_process(false)                      # the manager's own heat-3 patrols would hide what the step does: the runner is ticked by hand
	camp.step_completed.connect(func(c: int, i: int, k: StringName) -> void: done_steps.append([c, i, k]))
	camp.step_failed.connect(func(c: int, i: int, k: StringName, why: String) -> void: failed_steps.append([c, i, k, why]))
	Game.set_quality(1)

	# --- the chase starts with the step ---------------------------------------------------------------------------------------------
	TestLib.check(vm.patrol_cap() == 1, "MED allows one patrol vehicle at a time")
	TestLib.check(_begin([{"kind": "escape", "patrol": 1, "dist": 80.0, "clear": 0.5, "text": "Escape the Vael patrol"}]), "the escape step starts")
	TestLib.check(camp.kind == &"escape" and Game.heat >= VehicleSpecs.PATROL_HEAT - 0.01, "the heat jumps to the patrol level (%.1f)" % Game.heat)
	TestLib.check(vm.patrols_spawned == 1 and vm.patrol_count(true) == 1, "one chasing Vael patrol vehicle exists at once (spawned %d, chasing %d)" % [vm.patrols_spawned, vm.patrol_count(true)])
	var pats := camp._chasing_patrols()
	TestLib.check(pats.size() == 1 and pats[0].patrol and pats[0].chasing and pats[0].active, "it is the wave 14 patrol vehicle, chasing")
	var d := Vector2(pats[0].global_position.x - p.global_position.x, pats[0].global_position.z - p.global_position.z).length()
	TestLib.check(d >= VehicleSpecs.PATROL_MIN - 1.0 and d <= VehicleSpecs.PATROL_MAX + 1.0, "it starts %.0f m away, where the manager puts patrols" % d)
	TestLib.check(camp.hud_line().contains("PATROL") and camp.hud_line().contains("HEAT"), "the HUD line shows the patrol (%s)" % camp.hud_line())
	var marks := camp.markers()
	var target_marks := 0
	for i in camp.marker_count():
		target_marks += 1 if marks[i]["kind"] == &"target" else 0
	TestLib.check(target_marks == 1 and camp.markers()[0]["kind"] == &"area", "the minimap shows the escape ring and the patrol")
	TestLib.check(camp.waypoint().is_empty(), "there is still no waypoint to walk to")
	# the vehicle really hunts him: let the manager simulate for a moment (the runner stays hand-ticked)
	var pv := pats[0]
	var d0 := Vector2(pv.global_position.x - p.global_position.x, pv.global_position.z - p.global_position.z).length()
	vm.set_physics_process(true)
	await e.frames(150)
	vm.set_physics_process(false)
	var d1 := Vector2(pv.global_position.x - p.global_position.x, pv.global_position.z - p.global_position.z).length()
	TestLib.check(d1 < d0 - 15.0 or pv.ram_hits > 0, "the patrol vehicle closes in on the player (%.0f m -> %.0f m, %d rams)" % [d0, d1, pv.ram_hits])

	# --- it is not enough to be far away and cool while a patrol is close ----------------------------------------------------------
	var far := Vector3(0.0, 0.05, 120.0)
	p.teleport_to(far)
	var pat := pats[0]
	pat.global_position = Vector3(far.x + 12.0, 0.0, far.z + 8.0)
	Game.heat = 0.3
	camp.tick(0.1)
	TestLib.check(camp.state == &"active" and done_steps.is_empty(), "far away and cool, but a chasing patrol is 14 m off: the step stays open")
	TestLib.check(camp._patrol_near(far), "(the patrol counts as close)")
	pat.global_position = Vector3(far.x + 90.0, 0.0, far.z)
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 1 and done_steps[0][2] == &"escape", "once the patrol is more than %.0f m away the step is done" % CampaignRunner.PATROL_LOSE)
	_reset()

	# --- a patrol that stands down (heat < 2) no longer holds the step -------------------------------------------------------------
	_begin([{"kind": "escape", "patrol": 1, "dist": 80.0}])
	pat = camp._chasing_patrols()[0]
	p.teleport_to(far)
	pat.global_position = Vector3(far.x + 10.0, 0.0, far.z)
	Game.heat = 0.2
	camp.tick(0.1)
	TestLib.check(camp.state == &"active", "(held by the close patrol)")
	pat.chasing = false                                # what VehicleManager does below heat 2: the patrol stops chasing
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 1, "a patrol that stood down no longer holds the step")
	_reset()

	# --- a destroyed patrol does not hold it either ----------------------------------------------------------------------------------
	_begin([{"kind": "escape", "patrol": 1, "dist": 80.0}])
	pat = camp._chasing_patrols()[0]
	p.teleport_to(far)
	pat.global_position = Vector3(far.x + 10.0, 0.0, far.z)
	Game.heat = 0.2
	pat.dead = true
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 1, "a wrecked patrol vehicle no longer holds the step")
	_reset()

	# --- the chase is topped up while the heat is up, never when it is down ---------------------------------------------------------
	_begin([{"kind": "escape", "patrol": 1, "dist": 400.0}])
	TestLib.check(vm.patrols_spawned == 1, "(one so far)")
	vm._release(camp._chasing_patrols()[0])
	TestLib.check(camp._chasing_patrols().is_empty(), "(the patrol is gone)")
	_tick(CampaignRunner.PATROL_TOPUP + 1.0)
	TestLib.check(vm.patrols_spawned == 2 and vm.patrol_count(true) == 1, "with the heat up a new patrol joins the chase within %.0f s (spawned %d)" % [CampaignRunner.PATROL_TOPUP, vm.patrols_spawned])
	vm._release(camp._chasing_patrols()[0])
	Game.heat = 1.0
	_tick(CampaignRunner.PATROL_TOPUP * 3.0)
	TestLib.check(vm.patrols_spawned == 2 and vm.patrol_count(true) == 0, "with the heat below the stand-down level no more patrols are sent (spawned %d)" % vm.patrols_spawned)
	_reset()

	# --- the tier's patrol cap rules ------------------------------------------------------------------------------------------------
	_begin([{"kind": "escape", "patrol": 2, "dist": 400.0}])
	TestLib.check(vm.patrol_count(true) == 1, "MED: a step that asks for two sends one (the car and draw budget of the tier)")
	Game.set_quality(2)
	TestLib.check(vm.patrol_cap() == 2, "HIGH allows two")
	_begin([{"kind": "escape", "patrol": 2, "dist": 400.0}])
	TestLib.check(vm.patrol_count(true) == 2 and vm.patrols_spawned == 2, "HIGH: two patrols chase at once (%d)" % vm.patrol_count(true))
	TestLib.check(camp.hud_line().contains("PATROL"), "(the HUD line)")
	var tm := 0
	var marks2 := camp.markers()
	for i in camp.marker_count():
		tm += 1 if marks2[i]["kind"] == &"target" else 0
	TestLib.check(tm == 2, "both patrols are on the minimap (%d)" % tm)
	Game.set_quality(1)
	_reset()

	# --- a plain escape is unchanged: heat only ---------------------------------------------------------------------------------------
	_begin([{"kind": "escape", "heat": 3.0, "clear": 0.5, "dist": 60.0}])
	TestLib.check(vm.patrols_spawned == 0 and vm.patrol_count() == 0, "an escape without `patrol` spawns no vehicle")
	_tick(CampaignRunner.PATROL_TOPUP * 2.0)
	TestLib.check(vm.patrols_spawned == 0 and not camp.hud_line().contains("PATROL"), "...and never tops anything up")
	p.teleport_to(far)
	Game.heat = 0.2
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 1, "it ends on distance and heat alone, as before")
	_reset()

	# --- a patrol the world cannot place never fails the step -----------------------------------------------------------------------
	var saved_world := Game.world
	Game.world = null                                  # no world at all: the road query is gone
	_begin([{"kind": "escape", "patrol": 1, "dist": 60.0}])
	TestLib.check(camp.state == &"active" and failed_steps.is_empty() and vm.patrols_spawned == 0, "no road spot: the step still starts, with the heat only (%s)" % camp.state)
	_tick(10.0)
	TestLib.check(camp.state == &"active" and failed_steps.is_empty(), "...and keeps trying without failing")
	Game.world = saved_world

	# --- the data steps of the campaign play: chapter 4 and chapter 7 ---------------------------------------------------------------
	for ci in [3, 6]:
		_reset()
		camp.set_chapters(CampaignData.CAMPAIGN)
		var step: Dictionary = (CampaignData.CAMPAIGN[ci]["steps"] as Array).filter(func(s: Dictionary) -> bool: return str(s["kind"]) == "escape")[0]
		camp.set_chapters([{"id": "data_ch", "steps": [step]}])
		camp.start_chapter(0, 0, true)
		camp.tick(0.1)
		TestLib.check(camp.kind == &"escape" and vm.patrol_count(true) == 1, "chapter %d '%s' starts with a patrol on the street" % [ci + 1, step["obj"]])
	_reset()

	camp.abort()
	em.clear()
	Game.story = null
	Game.world = null
	Game.heat = 0.0
	Game.score = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	await e.teardown()
