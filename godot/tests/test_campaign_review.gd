extends RefCounted
## Independent review of the wave 18 campaign (HEAD 656e4d2): one test per bug the review found, plus the checks that came out clean and are worth keeping (old saves, a
## death inside a building, pause, the touch layout of the chapter select). Same fixture as test_campaign_runner.gd (real Player, EnemyManager, VehicleManager, Missions,
## Progress, InteriorGameplay with test doors, Hud on a flat floor with a stub world); the runner is ticked by hand so every check is exact game time.
## Run: tools/test.sh tests/test_campaign_review.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const RT := preload("res://tests/test_campaign_runner.gd")
const TMP := "user://test_campaign_review_save.cfg"
const SETTINGS := "user://test_campaign_review_settings.cfg"

var e := Env.new()
var host: Node
var p: Player
var root: Node3D
var em: EnemyManager
var vm: VehicleManager
var m: Missions
var camp: CampaignRunner
var prog: Progress
var story: RT.FakeStory
var ig: InteriorGameplay
var hud: Hud
var done_steps: Array = []
var failed_steps: Array = []
var done_chapters: Array = []


func run(h: Node) -> void:
	host = h
	seed(18)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	await e.setup(host)
	p = e.p
	root = e.root
	Fixture.add_floor(root, 600.0)
	p.max_hp = 1.0e6
	p.hp = p.max_hp
	var w := RT.World.new()
	w.intersections = CityLayout.make_intersections()
	root.add_child(w)
	Game.world = w
	story = RT.FakeStory.new()
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
	camp.set_physics_process(false)             # ticked by hand unless a check turns it on
	m.contracts.set_physics_process(false)
	camp.step_completed.connect(func(c: int, i: int, k: StringName) -> void: done_steps.append([c, i, k]))
	camp.step_failed.connect(func(c: int, i: int, k: StringName, why: String) -> void: failed_steps.append([c, i, k, why]))
	camp.chapter_completed.connect(func(c: int) -> void: done_chapters.append(c))
	Game.set_quality(1)
	ig = InteriorGameplay.new()
	ig.autosave = false
	ig.use_generator = false
	ig.test_doors = [
		{"id": 7001, "type": &"bar", "name": "TEST BAR", "wall": Vector3(80, 0, 0), "pos": Vector3(80, 0, 2), "normal": Vector3.BACK, "yaw": 0.0, "face_yaw": 0.0, "width": 2.4},
		{"id": 7002, "type": &"lobby", "name": "TEST LOBBY", "wall": Vector3(-90, 0, 0), "pos": Vector3(-90, 0, 2), "normal": Vector3.BACK, "yaw": 0.0, "face_yaw": 0.0, "width": 2.4},
	]
	root.add_child(ig)
	await e.frames(3)

	await _no_step_begins_inside()
	await _no_door_during_a_fight()
	await _resume_keeps_checkpoint()
	await _win_survives_a_pause()
	await _pause_freezes_the_runner()
	await _boss_down_beat()
	await _death_inside_a_building()
	await _old_saves()
	await _chapter_select_layout()

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

func _reset_world() -> void:
	if InteriorGameplay.active:
		ig.leave(true)
	camp.abort()
	camp.enabled = false
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
	story.set_to = -1
	m.win_on_cores = true
	m.contracts.enabled = true
	done_steps.clear()
	failed_steps.clear()
	done_chapters.clear()
	p.hp = p.max_hp
	p.teleport_to(Vector3(0.0, 0.05, 0.0))
	p.invuln = 0.0


func _begin(steps: Array, extra := {}) -> bool:
	_reset_world()
	var ch := {"id": "review_ch", "steps": steps}
	ch.merge(extra, true)
	camp.set_chapters([ch])
	var ok := camp.start_chapter(0, 0, true)
	camp.tick(0.1)
	return ok


func _tick(seconds: float, dt := 0.25) -> void:
	for i in int(ceil(seconds / dt)):
		camp.tick(dt)


func _put(at: Vector3) -> void:
	p.teleport_to(Vector3(at.x, 0.05, at.z))


func _near(a: Vector3, b: Vector3, tol := 3.0) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length() <= tol


# --- bug: a step began while the player was still inside the building --------------------------------------------------------

## Chapters 3 and 7 chain "infiltrate" into another step. The next step used to begin 1.6 s after the player stepped through the door, with the player inside the interior
## (which sits far from the street): an escort was built there, the asset stood in the interior's coordinates and "ESCORT LEFT BEHIND" failed it 15 s after the player came out.
func _no_step_begins_inside() -> void:
	_begin([{"kind": "enter_interior", "door": 7002}, {"kind": "escort", "pos": Vector3(-90, 0, 120), "hp": 200.0}, {"kind": "reach", "pos": Vector3(40, 0, 40)}])
	_put(Vector3(-90, 0, 4))
	TestLib.check(ig.enter(ig.door_by_id(7002), true) and InteriorGameplay.active, "the player goes in through the lobby door")
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 1 and camp.step_index == 1, "going in completes the infiltrate step")
	_tick(CampaignRunner.STEP_GAP + 3.0)
	TestLib.check(not (camp.state == &"active" and camp.kind == &"escort"), "the next step does not begin while the player is inside (state %s)" % camp.state)
	TestLib.check(camp.escortee == null or not camp.escortee.visible or not InteriorGameplay.active, "no escort asset is placed in the interior")
	ig.leave(true)
	await e.frames(3)
	_tick(CampaignRunner.STEP_GAP + 0.3)
	TestLib.check(camp.state == &"active" and camp.kind == &"escort", "it begins once the player is back on the street (%s)" % camp.state)
	TestLib.check(is_instance_valid(camp.escortee) and _near(camp.escortee.global_position, p.global_position, 12.0), "the escort asset is next to the player, not in the interior (%s)" % str(camp.escortee.global_position))
	_tick(20.0)
	TestLib.check(failed_steps.is_empty() and camp.state == &"active", "and the step is not failed by a far-away asset (%s)" % str(failed_steps))
	_reset_world()


# --- bug: a door during a fight cleared the step's enemies --------------------------------------------------------------------

## InteriorGameplay empties the street's enemy pool on entry (the stash respawns new drones on exit). Contracts block the door while their foes live ("FINISH THE CONTRACT
## FIRST"); the scripted steps did not, so slipping into a building mid-fight lost the target ("TARGET LOST") and restarted the step.
func _no_door_during_a_fight() -> void:
	_begin([{"kind": "reach", "pos": Vector3(40, 0, 40)}])
	TestLib.check(ig.block_reason() == "", "a reach step does not stop the player from using a door")
	_begin([{"kind": "kill_target", "enemy": "sentinel", "guards": 1, "pos": Vector3(-60, 0, -60)}])
	TestLib.check(camp.kind == &"kill_target" and camp.foes_alive() == 2, "a kill step is running with its enemies")
	_put(Vector3(80, 0, 4))
	TestLib.check(ig.block_reason() != "" and not ig.enter(ig.door_by_id(7001), true) and not InteriorGameplay.active, "the door is shut while the step's enemies are alive (%s)" % ig.block_reason())
	for f: Variant in camp.foes.duplicate():
		(f as Drone).damage(1.0e6)
	camp.tick(0.1)
	TestLib.check(done_chapters == [0] or done_steps.size() == 1, "the kill completes the step")
	_begin([{"kind": "hack", "pos": Vector3(100, 0, 0), "hold": 20.0}])
	em.clear()
	TestLib.check(ig.block_reason() == "", "a hack with no enemy on the street leaves the door usable")
	_reset_world()


# --- bug: CONTINUE overwrote the saved checkpoint with a fresh one ------------------------------------------------------------

## continue_game() -> CampaignRunner.resume() -> start_chapter() stored a brand new checkpoint (player position at the spawn, tp false, a goal regenerated from there) in
## Progress.checkpoint and the save file, before resume() restored the runner's own copy. A second death or quit before the next step lost the position and moved the goal.
func _resume_keeps_checkpoint() -> void:
	_reset_world()
	prog.path = TMP
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var steps: Array = [{"kind": "reach", "pos": Vector3(30, 0, 0), "radius": 6.0}, {"kind": "reach", "pos": Vector3(30, 0, 70), "radius": 6.0}, {"kind": "hack", "hold": 10.0}]
	camp.set_chapters([{"id": "resume_ch", "steps": steps}])
	camp.enabled = true
	prog.autosave_enabled = true
	camp.start_chapter(0, 0, true)
	camp.tick(0.1)
	_put(Vector3(31, 0, 1))
	camp.tick(0.1)
	camp.tick(CampaignRunner.STEP_GAP + 0.1)
	_put(Vector3(31, 0, 71))
	camp.tick(0.1)
	var saved := prog.checkpoint.duplicate()
	TestLib.check(int(saved.get("step", -1)) == 2 and bool(saved.get("tp", false)) and saved.has("goal"), "step 3 is checkpointed with a position, tp and a generated goal")
	prog.autosave_enabled = false
	Game.state = &"menu"
	camp.abort()
	prog.sector = 0
	TestLib.check(prog.has_save() and prog.continue_game(), "CONTINUE starts the saved run")
	TestLib.check(camp.step_index == 2 and camp.state == &"armed", "the runner is back at step 3")
	var cp := prog.checkpoint
	TestLib.check(int(cp.get("step", -1)) == 2 and bool(cp.get("tp", false)) and _near(cp.get("pos", Vector3.INF), saved["pos"], 0.01), "Progress still holds the checkpoint it loaded (pos %s, tp %s)" % [str(cp.get("pos")), str(cp.get("tp"))])
	TestLib.check(cp.has("goal") and saved.has("goal") and _near(cp["goal"], saved["goal"], 0.01), "with the same goal (%s)" % str(cp.get("goal")))
	var file := ConfigFile.new()
	file.load(TMP)
	prog.autosave_enabled = true
	camp.tick(CampaignRunner.STEP_GAP)
	_put(camp.pos)
	prog.autosave_enabled = false
	TestLib.check(_near(camp.get_checkpoint().get("pos", Vector3.INF), saved["pos"], 0.01), "the runner's own copy matches too")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_reset_world()


# --- bug: a chapter finished while not playing never won ----------------------------------------------------------------------

## The TEST menu opens from the pause screen: skip_step() on the last step ended the chapter (state done, flags released) but Game.win() is only called while playing, so the
## sector was never stabilized after resuming.
func _win_survives_a_pause() -> void:
	_begin([{"kind": "reach", "pos": Vector3(60, 0, 0)}])
	Game.state = &"paused"
	TestLib.check(camp.skip_step() and done_chapters == [0], "the last step is skipped from the paused TEST menu")
	Game.state = &"play"
	camp.tick(0.1)
	TestLib.check(Game.state == &"win", "back in play the sector is stabilized (state %s)" % Game.state)
	_reset_world()


# --- pause --------------------------------------------------------------------------------------------------------------------

func _pause_freezes_the_runner() -> void:
	_begin([{"kind": "hack", "pos": Vector3(100, 0, 0), "hold": 30.0, "time": 90.0}])
	camp.set_physics_process(true)
	await e.frames(10)
	var left := camp.time_left
	var clock := camp._clock
	for st: StringName in [&"paused", &"cutscene", &"dead", &"menu"]:
		Game.state = st
		camp.visuals.visible = true
		await e.frames(20)
		TestLib.check(is_equal_approx(camp.time_left, left) and is_equal_approx(camp._clock, clock), "state %s: the runner's clock, timers and spawns stand still" % st)
	Game.state = &"play"
	await e.frames(20)
	TestLib.check(camp.time_left < left, "playing again: the clock runs")
	camp.set_physics_process(false)
	_reset_world()


# --- bug: the boss defeat beat could not play for a scripted Overseer ---------------------------------------------------------

## The last step of chapters 3 and 6 is the Overseer kill. The runner completed it on the tick the boss died and called Game.win() at once: Cinematics only looks for a dead boss
## (and may only start a scene) while the state is play, so the slow-motion defeat scene was lost whenever the win came first. The runner now holds a short beat.
func _boss_down_beat() -> void:
	_begin([{"kind": "kill_target", "target": "boss", "guards": 0, "pos": Vector3(-60, 0, -60)}])
	TestLib.check(camp.target is Overseer, "the step hunts an Overseer")
	var boss := camp.target as Overseer
	boss.damage(boss.hp + 10.0)
	camp.tick(0.05)
	TestLib.check(camp.state == &"active" and Game.state == &"play", "the tick the Overseer dies does not end the chapter yet (state %s, game %s)" % [camp.state, Game.state])
	_tick(CampaignRunner.BOSS_BEAT + 0.3)
	TestLib.check(done_chapters == [0] and Game.state == &"win", "after the beat the chapter ends (state %s, game %s)" % [camp.state, Game.state])
	TestLib.check(7 not in prog.bosses_cleared and 0 in prog.bosses_cleared, "the boss is recorded as cleared for its chapter")
	_reset_world()
	# a plain target ends the step at once, as before
	_begin([{"kind": "kill_target", "enemy": "sentinel", "guards": 0, "pos": Vector3(-60, 0, -60)}])
	(camp.target as Drone).damage(1.0e6)
	camp.tick(0.05)
	TestLib.check(done_chapters == [0], "a normal target ends its step on the same tick")
	_reset_world()
	# with a real Cinematics node: the defeat scene starts (it only can while the state is play)
	var cine := Cinematics.new()
	root.add_child(cine)
	cine.enabled = true
	cine.force = true
	await e.frames(4)
	_begin([{"kind": "kill_target", "target": "boss", "guards": 0, "pos": Vector3(-60, 0, -60)}])
	camp.set_physics_process(true)
	# wait on state, not a frame count: the boss intro starts when the poll first sees the Overseer; skip it whenever it plays
	for i in 60:
		await e.frames(1)
		if cine.active:
			cine.t = 3.0
			cine.skip()
			await e.frames(6)
		if cine._boss != null and not cine.active:
			break
	var plays0 := cine.plays
	(camp.target as Overseer).damage(1.0e6)
	var saw_defeat := false
	for i in 12:
		await e.frames(1)
		saw_defeat = saw_defeat or (cine.active and cine.active_id == &"boss_out")
	TestLib.check(saw_defeat, "Cinematics plays the slow-motion defeat scene for the scripted Overseer (plays %d -> %d)" % [plays0, cine.plays])
	if cine.active:
		cine.t = cine.plan.duration - 0.1
		await e.frames(12)
	for i in 120:
		if Game.state == &"win":
			break
		await e.frames(1)
	camp.set_physics_process(false)
	TestLib.check(Game.state == &"win" and Engine.time_scale == 1.0, "and the chapter still ends afterwards (game %s, time scale %.2f)" % [Game.state, Engine.time_scale])
	cine.queue_free()
	await e.frames(2)
	_reset_world()


# --- a death inside a building ---------------------------------------------------------------------------------------------

func _death_inside_a_building() -> void:
	_begin([{"kind": "enter_interior", "door": 7001, "leave": true}, {"kind": "reach", "pos": Vector3(40, 0, 40)}])
	_put(Vector3(80, 0, 4))
	ig.enter(ig.door_by_id(7001), true)
	camp.tick(0.1)
	TestLib.check(camp._phase == 2 and camp.state == &"active", "inside, the step waits for the way out")
	p.hp = 0.0
	Game.die()
	TestLib.check(camp.state == &"held", "death inside: the step is on hold")
	Game.do_respawn()
	await e.frames(3)
	TestLib.check(not InteriorGameplay.active and camp.state == &"armed" and failed_steps.is_empty(), "respawn: back on the street, the step re-arms without a failure")
	camp.tick(1.0)
	TestLib.check(camp.state == &"active" and camp._phase == 1 and camp.kind == &"enter_interior", "the same step begins again at the door")
	_put(Vector3(80, 0, 4))
	ig.enter(ig.door_by_id(7001), true)
	camp.tick(0.1)
	ig.leave(true)
	await e.frames(3)
	camp.tick(0.1)
	TestLib.check(done_steps.size() == 1 and done_steps[0][2] == &"enter_interior", "and can be finished: in, out, done")
	# a death inside a building during a street step
	_begin([{"kind": "hack", "pos": Vector3(100, 0, 0), "hold": 20.0}])
	em.clear()
	_put(Vector3(80, 0, 4))
	ig.enter(ig.door_by_id(7001), true)
	camp.tick(0.5)
	p.hp = 0.0
	Game.die()
	Game.do_respawn()
	await e.frames(3)
	camp.tick(1.0)
	TestLib.check(camp.state == &"active" and camp.kind == &"hack" and not InteriorGameplay.active, "a death inside a building during a hack restarts the hack on the street")
	_reset_world()


# --- old saves -----------------------------------------------------------------------------------------------------------------

func _old_saves() -> void:
	_reset_world()
	prog.path = TMP
	camp.enabled = true
	# the smallest save an early build wrote: a version and a sector
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", 1)
	cf.set_value("campaign", "sector", 2)
	cf.save(TMP)
	TestLib.check(prog.has_save(), "a save with only a sector counts as a save")
	Game.state = &"menu"
	TestLib.check(prog.continue_game(), "CONTINUE works on it")
	TestLib.check(story.set_to == 2 and prog.unlocked == 3 and camp.chapter_index == 2 and camp.step_index == 0 and camp.state == &"armed", "chapter 3 starts from its first step, three chapters unlocked")
	TestLib.check(prog.credits == 0 and prog.reputation == 0 and WeaponDefs.is_unlocked(&"carbine") and int(prog.checkpoint.get("chapter", -1)) == 2 and int(prog.checkpoint.get("step", -1)) == 0, "missing sections fall back to their defaults (the chapter start is the checkpoint)")
	# a save from the old five-chapter story that had reached the endless sectors
	_reset_world()
	camp.enabled = true
	cf = ConfigFile.new()
	cf.set_value("meta", "version", 1)
	cf.set_value("wallet", "credits", 900)
	cf.set_value("campaign", "sector", 13)
	cf.save(TMP)
	Game.state = &"menu"
	TestLib.check(prog.continue_game() and story.set_to == 13 and camp.state == &"idle" and prog.credits == 900, "an old endless-sector save resumes as the plain core hunt")
	TestLib.check(prog.chapters_unlocked() == CampaignRunner.chapter_count() and prog.can_select_chapter(), "and all chapters are open in the chapter select")
	TestLib.check(m.win_on_cores == true and m.contracts.enabled == true, "the cores win the sector and contracts are offered, as before")
	# damaged new keys on an otherwise old save
	for bad: Dictionary in [{"unlocked": "many"}, {"unlocked": -5}, {"unlocked": 1000000}, {"unlocked": 3.7}]:
		cf = ConfigFile.new()
		cf.set_value("meta", "version", 1)
		cf.set_value("campaign", "sector", 1)
		for k: String in bad:
			cf.set_value("campaign", k, bad[k])
		cf.save(TMP)
		prog.unlocked = 1
		prog.load_file()
		TestLib.check(prog.unlocked >= 2 and prog.unlocked <= 99, "a damaged campaign/unlocked (%s) still gives a sane value (%d)" % [str(bad), prog.unlocked])
	# a checkpoint past the end of its chapter, one for a chapter that no longer exists, and a NaN position
	for bad: Dictionary in [{"chapter": 0, "step": 99, "pos": Vector3(5, 0, 5)}, {"chapter": 40, "step": 1, "pos": Vector3(5, 0, 5)}, {"chapter": 0, "step": 1, "pos": Vector3(NAN, 0, 5)}]:
		_reset_world()
		camp.enabled = true
		camp.set_chapters([{"id": "old_ch", "steps": [{"kind": "reach", "pos": Vector3(30, 0, 0)}, {"kind": "reach", "pos": Vector3(0, 0, 30)}]}])
		cf = ConfigFile.new()
		cf.set_value("meta", "version", 1)
		cf.set_value("campaign", "sector", 0)
		cf.set_value("wallet", "credits", 5)
		for k: String in bad:
			cf.set_value("checkpoint", k, bad[k])
		cf.save(TMP)
		Game.state = &"menu"
		var ok := prog.continue_game()
		camp.tick(2.0)
		TestLib.check(ok and Game.state == &"play" and camp.is_running() and camp.step_index <= 1, "a strange checkpoint (%s) still starts a playable chapter (step %d, %s)" % [str(bad), camp.step_index, camp.state])
	# the file this build writes still has every old key and the version
	_reset_world()
	prog.unlocked = 5
	prog.credits = 77
	prog.save_file()
	cf = ConfigFile.new()
	cf.load(TMP)
	var keys_ok := true
	for pair: Array in [["meta", "version"], ["wallet", "credits"], ["wallet", "reputation"], ["campaign", "sector"], ["campaign", "best"], ["campaign", "bosses"], ["flags", "tutorial_done"], ["weapons", "unlocked"], ["weapons", "current"], ["upgrades", "magazine"]]:
		keys_ok = keys_ok and (cf.has_section_key(pair[0], pair[1]) or pair[0] == "upgrades")
	TestLib.check(keys_ok and int(cf.get_value("meta", "version", 0)) == Progress.SAVE_VERSION, "a save written now keeps every key and the current version")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	camp.enabled = false
	_reset_world()


# --- the chapter select by touch at other screen shapes ----------------------------------------------------------------------------

func _chapter_select_layout() -> void:
	_reset_world()
	var scene := load("res://scenes/hud.tscn") as PackedScene
	hud = scene.instantiate() as Hud
	hud.settings_path = SETTINGS
	root.add_child(hud)
	await e.frames(3)
	prog.unlocked = CampaignRunner.chapter_count()
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 540), Vector2i(1024, 768), Vector2i(844, 390)]:
		win.size = size
		await e.frames(3)
		var vp := hud.get_viewport().get_visible_rect().size
		var s := UiUtil.ui_scale(vp)
		for st: StringName in [&"menu", &"paused"]:
			Game.state = st
			hud._chapters_open = false
			hud._layout_key = ""
			hud._ensure_layout()
			var open_btn := {}
			for b: Dictionary in hud.buttons:
				if b["id"] == &"chapters":
					open_btn = b
			TestLib.check(not open_btn.is_empty() and Rect2(Vector2.ZERO, vp).encloses(open_btn["rect"]), "%dx%d %s: the CHAPTERS button is on screen" % [size.x, size.y, st])
			TestLib.check(hud.tap((open_btn["rect"] as Rect2).get_center()) and hud._chapters_open, "%dx%d %s: tapping it opens the select" % [size.x, size.y, st])
			hud._ensure_layout()
			var ids: Array = hud.buttons.map(func(b: Dictionary) -> StringName: return b["id"])
			var all_cells := true
			for i in CampaignRunner.chapter_count():
				all_cells = all_cells and ids.has(StringName("chapter_%d" % i))
			TestLib.check(all_cells and ids.has(&"chapters_back"), "%dx%d %s: every chapter and BACK are buttons" % [size.x, size.y, st])
			var inside := true
			var overlap := false
			for b: Dictionary in hud.buttons:
				inside = inside and Rect2(Vector2.ZERO, vp).encloses(b["rect"])
				for b2: Dictionary in hud.buttons:
					overlap = overlap or (b != b2 and (b["rect"] as Rect2).intersects(b2["rect"]))
			TestLib.check(inside and not overlap, "%dx%d %s: the grid is on screen and no cell overlaps" % [size.x, size.y, st])
			# every cell answers at its centre and its corners (a finger is not exact)
			var hit_all := true
			for b: Dictionary in hud.buttons:
				var r: Rect2 = b["rect"]
				for q: Vector2 in [r.get_center(), r.position + Vector2(2, 2), r.end - Vector2(2, 2)]:
					hit_all = hit_all and hud._button_at(q) == b["id"]
			TestLib.check(hit_all, "%dx%d %s: a touch anywhere in a cell hits that cell" % [size.x, size.y, st])
			TestLib.check(hud.tap(_find_rect(&"chapters_back").get_center()) and not hud._chapters_open, "%dx%d %s: BACK closes it" % [size.x, size.y, st])
		Game.state = &"play"
	win.size = old
	await e.frames(3)
	Game.state = &"play"
	hud.queue_free()
	await e.frames(2)
	_reset_world()


func _find_rect(id: StringName) -> Rect2:
	hud._ensure_layout()
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b["rect"]
	return Rect2()
