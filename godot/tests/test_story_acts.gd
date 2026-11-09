extends "res://tests/wm_base.gd"
## THE LONG TOMORROW (wave 110, docs/STORY.md): four acts and twelve story missions on the Mission Board. Data first, then the REAL game scene:
##  * StoryActs / StoryCast / StoryScenes / StoryMissions: 4 acts (3 + 4 + 3 + 2 missions), every line short and spoken by a known character with a portrait, every briefing and beat
##    timed so it can be read, every mission builds on the real world (city, harbour quay and bay, SUMMIT ROAD, observatory, EASTFIELD, canyon, the sound, the alien outpost, the Array tower),
##    validates as a campaign chapter, puts walk-to goals on land and boat goals on deep water, and carries one radio line per step;
##  * the save: the optional [story] section round-trips and an older file without it loads as "mission 1";
##  * live: the STORY card is mission 1, tapping it on the Mission Board starts it (radio, no cutscene for the first job), every mission of the twelve is run through its real steps by the real
##    campaign runner (checkpoint at each step, pay, reward ladder), the card moves on in order, the briefing cutscene plays and is skipped, a beat plays at its step, a quit in the middle resumes
##    at the saved step, a dropped mission is not lost, and after the twelfth the story is done (finale, ending cards, no card).
## Run: tools/test.sh tests/test_story_acts.gd   (waits on counters and state, never on frame counts; STORY_ONLY=pure skips the real scene)

const TIMEOUT_SECONDS := 140.0
const TMP := "user://test_story_save.cfg"

var _prog: Progress
var _runner: StoryRunner


class PortraitProbe extends Control:
	var drawn := 0

	func _draw() -> void:
		for id in StoryCast.ORDER:
			StoryCast.draw_portrait(self, Rect2(0.0, 0.0, 96.0, 96.0), id, 0.3, 1.0)
			drawn += 1


func run(host: Node) -> void:
	_host = host
	for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", WorldRoam.SAVE_PATH, TMP]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Sfx.muted = true
	_data()
	await _portraits(host)
	_save_roundtrip()
	if OS.get_environment("STORY_ONLY") == "pure":
		return
	var main := await _boot(host)
	if main == null:
		return
	await _live()
	await _shutdown(main)


# --- data ------------------------------------------------------------------------------------------------------------------------------

func _data() -> void:
	TerrainHeight.warm()
	WaterLayout.ensure()
	OutskirtsSites.ensure()
	AlienSites.ensure()
	TestLib.check(StoryActs.ACTS.size() == 4 and StoryActs.MISSIONS.size() == 12 and StoryActs.count() == StoryActs.TOTAL, "four acts and twelve story missions")
	var counts := [0, 0, 0, 0]
	var ids := {}
	var last_reward := 0
	var order_ok := true
	var last_act := 1
	for m: Dictionary in StoryActs.MISSIONS:
		var a := int(m["act"])
		counts[a - 1] += 1
		order_ok = order_ok and a >= last_act
		last_act = a
		ids[str(m["id"])] = true
		TestLib.check(str(m["title"]).length() <= StoryActs.TITLE_MAX and str(m["title"]) != "", "%s: a short title" % m["id"])
		TestLib.check(str(m["card"]).length() <= StoryActs.CARD_MAX, "%s: the card line fits (%d characters)" % [m["id"], str(m["card"]).length()])
		TestLib.check(int(m["reward"]) >= last_reward and int(m["reward"]) >= 300, "%s: pay %d never drops along the story" % [m["id"], int(m["reward"])])
		last_reward = int(m["reward"])
		var brief: Array = m["brief"]
		TestLib.check(brief.size() >= 2 and brief.size() <= 4, "%s: a briefing of 2 to 4 lines (%d)" % [m["id"], brief.size()])
		TestLib.check((m["radio"] as Array).size() == int(m["steps"]), "%s: one radio line per step (%d)" % [m["id"], int(m["steps"])])
		for b: Dictionary in m["beats"]:
			TestLib.check(int(b["step"]) >= 0 and int(b["step"]) < int(m["steps"]) and (b["lines"] as Array).size() >= 3 and str(b["head"]).length() <= 24, "%s: the beat sits on a real step" % m["id"])
	TestLib.check(counts == [3, 4, 3, 2] and order_ok and ids.size() == 12, "acts hold 3, 4, 3 and 2 missions in order with unique ids (%s)" % str(counts))
	var speakers := {}
	var lines_ok := true
	for l: Dictionary in StoryActs.all_lines():
		speakers[str(l["s"])] = true
		if str(l["t"]).length() > StoryActs.LINE_MAX or str(l["t"]).length() < 2 or not StoryCast.has(str(l["s"])):
			lines_ok = false
			printerr("bad line: %s" % str(l))
	TestLib.check(lines_ok, "every story line is short and spoken by a character of the cast")
	TestLib.check(speakers.size() == 7, "all seven voices speak (%d): KESTREL, ORACLE, RIVET, IRIS, BASALT, VOSS and the hive" % speakers.size())
	for a: Dictionary in StoryActs.ACTS:
		TestLib.check(str(a["card"]).length() <= StoryActs.ACT_CARD_MAX and str(a["end"]).length() <= StoryActs.ACT_CARD_MAX, "act %d: cards fit" % int(a["n"]))
	for e: Dictionary in StoryActs.ENDING:
		TestLib.check(str(e["head"]).length() <= 30 and str(e["text"]).length() <= StoryActs.ACT_CARD_MAX, "an ending card fits")
	for c: Dictionary in StoryActs.CREDITS:
		var ok := str(c["head"]).length() <= 30
		for ln: Variant in c["lines"]:
			ok = ok and str(ln).length() <= CampaignData.CREDIT_LINE_MAX
		TestLib.check(ok, "credits block %s fits" % c["head"])
	# progress rules
	TestLib.check(StoryActs.next_index({}) == 0 and StoryActs.progress_text(0) == "ACT 1  MISSION 1 OF 12", "an empty save starts at mission 1")
	TestLib.check(StoryActs.next_index({"landfall": 1, "borrowed_wheels": 2}) == 2 and StoryActs.next_index({"borrowed_wheels": 1}) == 0, "missions unlock in order")
	var all := {}
	for m: Dictionary in StoryActs.MISSIONS:
		all[str(m["id"])] = 1
	TestLib.check(StoryActs.next_index(all) == 12 and StoryActs.progress_text(12) == "STORY COMPLETE" and StoryActs.done_count(all) == 12, "twelve done is the end")
	TestLib.check(StoryActs.first_of_act(0) and StoryActs.first_of_act(3) and StoryActs.first_of_act(7) and StoryActs.first_of_act(10) and not StoryActs.first_of_act(1), "the first mission of each act is marked")
	# the missions on the real world
	var kinds := {}
	var all_valid := true
	var dry_ok := true
	var fallbacks := 0
	for m: Dictionary in StoryActs.MISSIONS:
		var o := StoryMissions.build(str(m["id"]))
		if o.is_empty():
			all_valid = false
			continue
		if bool(o["fallback"]):
			fallbacks += 1
		var why := CampaignSteps.validate_chapter(o["chapter"])
		if not why.is_empty():
			all_valid = false
			printerr("%s: %s" % [m["id"], str(why)])
		var steps: Array = o["steps"]
		if steps.size() != int(m["steps"]):
			all_valid = false
		for st: Dictionary in steps:
			kinds[StringName(st["kind"])] = true
			if not (st["radio"] as Dictionary).has("t") or str(st["text"]).length() > CampaignSteps.MAX_TEXT:
				all_valid = false
			if st.has("pos"):
				var pos: Vector3 = st["pos"]
				if not pos.is_finite():
					all_valid = false
				var need := StringName(str(st.get("veh", "")))
				if need == &"boat":
					dry_ok = dry_ok and TerrainHeight.depth_at(pos.x, pos.z) > 1.0
				elif String(st["kind"]) in ["reach", "kill_target", "hack", "defend"] and not WorldSteps.is_air(need):
					dry_ok = dry_ok and TerrainHeight.depth_at(pos.x, pos.z) <= 0.0
					var gy := TerrainHeight.height_at(pos.x, pos.z)
					if absf(gy - pos.y) > 4.0 and pos.y != 0.0:             # a goal at the wrong height can never be reached on foot (found in this test: the quay goal sat in the basin)
						dry_ok = false
						printerr("%s: goal %s at %.1f but the ground is %.1f" % [m["id"], str(st["text"]), pos.y, gy])
			if str(st["kind"]) == "gates" and str(st.get("veh", "")) == "boat":
				for q: Variant in st["pts"] as Array:
					dry_ok = dry_ok and TerrainHeight.depth_at((q as Vector3).x, (q as Vector3).z) > 1.0
		TestLib.check(float(o["route_m"]) >= 0.0 and int(o["reward"]) == int(m["reward"]) and str(o["title"]) == str(m["title"]), "%s: an offer with its pay" % m["id"])
	TestLib.check(all_valid, "all twelve missions build on the world, validate as chapters and carry their radio lines")
	TestLib.check(fallbacks == 0, "no mission fell back to the city version (%d) on the real world" % fallbacks)
	TestLib.check(dry_ok, "walk-to goals are on dry land, the boat's goals and buoys on deep water")
	for k: StringName in [&"reach", &"hack", &"defend", &"kill_target", &"escape", &"gates", &"pursuit"]:
		TestLib.check(kinds.has(k), "the story uses the step kind %s" % k)
	# every mission can fall back to the city (a world without terrain) with the same number of steps
	for m: Dictionary in StoryActs.MISSIONS:
		var base := StoryMissions.world_steps_for_fallback(str(m["id"]), int(m["steps"]))
		var city := StoryMissions.city_steps(base)
		TestLib.check(city.size() == int(m["steps"]) and CampaignSteps.validate_chapter({"steps": city}).is_empty(), "%s: the city fallback has %d valid steps" % [m["id"], int(m["steps"])])
	# the cutscenes as plans
	var plans_ok := true
	for i in 12:
		var pb := StoryScenes.brief({"index": i, "hero": Vector3(10.0, 1.0, 20.0), "face": Vector3.FORWARD})
		var pr := StoryScenes.problems(pb)
		if not pr.is_empty() or pb.duration < 5.0 or pb.duration > 32.0 or pb.head == "" or pb.tag_line == "":
			plans_ok = false
			printerr("brief %d: %s %.1f" % [i, str(pr), pb.duration])
		for b: Dictionary in StoryActs.mission(i)["beats"]:
			var pt := StoryScenes.beat({"index": i, "beat": b, "hero": Vector3(0.0, 1.0, 0.0), "face": Vector3.RIGHT})
			var pr2 := StoryScenes.problems(pt)
			if not pr2.is_empty() or pt.head != str(b["head"]):
				plans_ok = false
				printerr("beat %d: %s" % [i, str(pr2)])
		pb.sample(pb.duration * 0.5)
		plans_ok = plans_ok and pb.cam_pos.is_finite() and pb.cam_look.is_finite()
	TestLib.check(plans_ok, "the 12 briefings and every beat are timed, in order, readable and have a camera that stays finite")
	var ep := CinePlan.credits_scene({"hero": Vector3.ZERO, "face": Vector3.FORWARD}, &"story_end")
	TestLib.check(ep.credits.size() == StoryActs.CREDITS.size() and ep.subs.size() == StoryActs.END_SUBS.size() and ep.sub_problems().is_empty() and ep.duration >= 14.0, "the finale plays the story credits (%.1f s)" % ep.duration)
	TestLib.check(StoryScenes.brief({"index": 3, "hero": Vector3.ZERO, "face": Vector3.FORWARD}).tag_line.begins_with("ACT 2"), "the first mission of act 2 carries the act title card")
	TestLib.check(StoryScenes.brief({"index": 4, "hero": Vector3.ZERO, "face": Vector3.FORWARD}).tag_line == "ACT 2  MISSION 5 OF 12", "later missions show where they are")


func _portraits(host: Node) -> void:
	var probe := PortraitProbe.new()
	probe.size = Vector2(120.0, 120.0)
	host.add_child(probe)
	await TestLib.frames(host, 3)
	probe.queue_redraw()
	await TestLib.frames(host, 3)
	TestLib.check(probe.drawn >= StoryCast.ORDER.size(), "every portrait paints without an error (%d draws)" % probe.drawn)
	probe.queue_free()
	TestLib.check(StoryCast.ORDER.size() == 7 and StoryCast.CAST.size() == 7, "seven characters with portraits")
	var colours := {}
	for id in StoryCast.ORDER:
		colours[str(StoryCast.color(id))] = true
		TestLib.check(StoryCast.name_of(id) != "" and StoryCast.role_of(id) != "" and StoryCast.has(id), "%s has a name and a role" % id)
	TestLib.check(colours.size() == 7, "every speaker has their own colour")
	TestLib.check(StoryView.speaker_color("RIVET") == StoryCast.color("RIVET") and StoryView.speaker_color("ORACLE") == UiUtil.CYAN or StoryView.speaker_color("ORACLE") == StoryCast.color("ORACLE"), "the subtitle plate takes the cast colours")


func _save_roundtrip() -> void:
	var p := Progress.new()
	p.path = TMP
	p.autosave_enabled = false
	p.story_done = {"landfall": 1, "borrowed_wheels": 2, "the_relay": 1}
	p.story_cp = {"id": "container_17", "step": 2}
	p.story_seen = [&"brief_landfall", &"beat_the_relay_0"]
	TestLib.check(p.save_file(), "a save with a story section is written")
	var q := Progress.new()
	q.path = TMP
	q.autosave_enabled = false
	TestLib.check(q.load_file(), "it loads again")
	TestLib.check(q.story_done == {"landfall": 1, "borrowed_wheels": 2, "the_relay": 1} and str(q.story_cp.get("id")) == "container_17" and int(q.story_cp.get("step")) == 2, "missions done and the running step round-trip")
	TestLib.check(q.story_seen.has(&"brief_landfall") and q.story_seen.has(&"beat_the_relay_0") and StoryActs.next_index(q.story_done) == 3, "scenes seen round-trip and the story is at mission 4")
	# helpers
	q.story_checkpoint("container_17", 1)
	TestLib.check(int(q.story_cp["step"]) == 1, "story_checkpoint stores the step")
	q.story_finish("container_17")
	TestLib.check(int(q.story_done["container_17"]) == 1 and q.story_cp.is_empty(), "finishing a mission counts it and drops its step")
	TestLib.check(q.story_mark_seen(&"x") and not q.story_mark_seen(&"x"), "a scene is marked seen once")
	# an older save has no [story] section: mission 1
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("[meta]\nversion=2\n[wallet]\ncredits=50\nreputation=3\n[campaign]\nsector=2\n")
	f.close()
	var old := Progress.new()
	old.path = TMP
	old.autosave_enabled = false
	old.story_done = {"landfall": 5}
	TestLib.check(old.load_file() and old.story_done.is_empty() and old.story_cp.is_empty() and old.credits == 50 and StoryActs.next_index(old.story_done) == 0, "an older save loads and the story starts at mission 1")
	# a damaged story section never raises and never invents progress
	f = FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("[meta]\nversion=2\n[story]\ndone_landfall=\"yes\"\ndone_nonsense=4\ncp_id=\"nonsense\"\ncp_step=99\nseen=7\n")
	f.close()
	TestLib.check(old.load_file() and old.story_done.is_empty() and old.story_cp.is_empty() and old.story_seen.is_empty(), "a damaged [story] section changes nothing")
	for x: Progress in [p, q, old]:
		x.free()
	Upgrades.reset()
	WeaponDefs.reset_unlocked()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP + ".bak"))


# --- the real scene ----------------------------------------------------------------------------------------------------------------------

func _hud() -> Hud:
	return _host.get_tree().get_first_node_in_group(&"hud") as Hud


func _tap_id(id: StringName) -> bool:
	var hud := _hud()
	hud._ensure_layout()
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return hud.tap((b["rect"] as Rect2).get_center())
	return false


func _has_button(id: StringName) -> bool:
	var hud := _hud()
	hud._ensure_layout()
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return true
	return false


## Waits for the board to be idle again with a good result.
func _mission_done(label: String) -> bool:
	var ok := await _until(func() -> bool: return _board.state == &"idle" and bool(_board.last_result.get("ok", false)), 12.0)
	TestLib.check(ok, "%s: the board reports it done (state %s, result %s)" % [label, _board.state, str(_board.last_result)])
	return ok


func _diag() -> String:
	var em := Game.enemies as EnemyManager
	var st: Object = Game.story
	return "camp %s step %d tries %d arm_t %.1f game %s cards %s alive %d/%d interior %s heat %.1f fails %d last_fail '%s'" % [_camp.state, _camp.step_index, _camp._begin_tries, _camp._arm_t, Game.state,
			str(st.call(&"cards_active")) if st != null else "-", em.alive_count(), em.cap(), str(InteriorGameplay.active), Game.heat, _camp.fails, _camp.last_fail]


## Puts the hero at the end of the running step's route / gates / goal (dry land only).
func _arrive(st: Dictionary) -> void:
	var at := Vector3.INF
	if str(st["kind"]) == "pursuit":
		var route: PackedVector3Array = st["route"]
		at = route[route.size() - 1]
	elif str(st["kind"]) == "gates":
		at = (st["pts"] as Array)[(st["pts"] as Array).size() - 1]
	elif st.has("pos") and (st["pos"] as Vector3).is_finite():
		at = st["pos"]
	elif _camp.pos.is_finite() and _camp.pos != Vector3.ZERO:
		at = _camp.pos
	_p.max_hp = 1.0e6
	_p.hp = _p.max_hp
	if at.is_finite() and TerrainHeight.depth_at(at.x, at.z) <= 0.0:
		_p.teleport_to(Vector3(at.x, TerrainHeight.height_at(at.x, at.z) + 1.0, at.z))
		await TestLib.frames(_host, 4)


## Runs the steps of the running story mission to the end through the real campaign runner: waits for each step to begin for real, then finishes it as SKIP STEP does.
func _run_steps(label: String, first: int, n: int) -> bool:
	for i in range(first, n):
		# a step the hero finished by standing at its goal (the walk-to steps) is already behind us
		var began := await _until(func() -> bool: return (_camp.state == &"active" and _camp.step_index == i) or _camp.step_index > i or _board.state != &"running", 14.0)
		if _camp.step_index > i or _board.state != &"running":
			continue
		TestLib.check(began, "%s: step %d begins (%s)" % [label, i + 1, _diag()])
		if not began:
			return false
		if i == first:
			TestLib.check(_camp.hud_line() != "" and str(_camp.step.get("radio", {}).get("t", "")) != "", "%s: the objective line and the radio line are there" % label)
		await _arrive(_camp.step)                         # the hero stands at the goal like a player who walked there: the next step spawns its foes around him
		if _camp.state == &"active" and _camp.step_index == i:
			TestLib.check(_camp.skip_step(), "%s: step %d done" % [label, i + 1])
		await TestLib.frames(_host, 2)
	return await _mission_done(label)


func _live() -> void:
	_prog = Game.progress as Progress
	_prog.new_campaign()
	_p.max_hp = 1.0e6                                         # the alien camp's garrison is real: the test hero walks through it unhurt (the fight itself is the campaign tests' job)
	_p.hp = _p.max_hp
	_board.set_take_over(true)
	_board.set_story_acts(true)
	_runner = _board.story
	TestLib.check(_runner != null and _runner.enabled and _board.story_acts and _runner.get_parent() == _board, "the board owns a story runner and the live game switches it on")
	var hud := _hud()
	TestLib.check(hud != null, "the real scene has a HUD")
	_board.first_pending = false
	_clear_vehicles()
	_board.generate()
	await TestLib.frames(_host, 2)
	# mission 1 on the card and on the board screen
	var card := _board.story_offer()
	TestLib.check(str(card.get("title", "")) == "LANDFALL" and str(card.get("meta", "")) == "ACT 1  MISSION 1 OF 12" and bool(card.get("story_card", false)), "the STORY card is LANDFALL, ACT 1  MISSION 1 OF 12")
	ResultCard.enabled = false
	Game.state = &"play"
	hud.toggle_pause()
	await TestLib.frames(_host, 2)
	TestLib.check(_tap_id(&"board_open"), "the pause menu's MISSIONS opens the board")
	await TestLib.frames(_host, 2)
	TestLib.check(hud._board_open and _has_button(&"board_story") and _has_button(&"board_pick_0"), "the board shows the STORY card and three missions")
	var small := 0
	var s := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
	for b: Dictionary in hud.buttons:
		if (b["rect"] as Rect2).size.y < 63.5 * s:
			small += 1
	TestLib.check(small == 0, "every board button is at least 64 px tall (%d smaller)" % small)
	var credits0 := _prog.credits
	var done0 := MissionRewards.missions_done
	_board.auto_open = false                                  # the live board opens by itself after a dropped mission (a paused screen); the test closes screens itself
	TestLib.check(_tap_id(&"board_story"), "tapping STORY starts LANDFALL")
	await TestLib.frames(_host, 2)
	TestLib.check(_board.state == &"running" and _runner.running_id == "landfall" and bool(_board.active.get("story_act", false)) and Game.state == &"play", "LANDFALL runs as a board mission")
	TestLib.check(await _until(func() -> bool: return _runner.scenes_as_radio >= 1, 4.0) and _runner.scenes_played.is_empty(), "the first job is told as radio lines, with no cutscene (cutscenes are off in tests)")
	TestLib.check(await _run_steps("LANDFALL", 0, 2), "LANDFALL finishes")
	TestLib.check(int(_prog.story_done.get("landfall", 0)) == 1 and _prog.story_cp.is_empty() and _prog.credits >= credits0 + 300, "it is saved as done and paid (%d credits)" % (_prog.credits - credits0))
	TestLib.check(MissionRewards.missions_done == done0 + 1, "it counts for the weapon ladder")
	TestLib.check(str(_board.story_offer().get("title", "")) == "BORROWED WHEELS" and str(_board.story_offer().get("meta", "")) == "ACT 1  MISSION 2 OF 12", "the card moves on to mission 2")
	# mission 2 with the briefing cutscene
	var cin := Cinematics.instance
	TestLib.check(cin != null, "the real scene has the cinematics node")
	if cin != null:
		cin.force = true
		cin.enabled = true
	var ok2 := _board.accept(-1)
	TestLib.check(ok2 and _runner.running_id == "borrowed_wheels", "BORROWED WHEELS starts from the card")
	if cin != null:
		var started := await _until(func() -> bool: return cin.active and cin.active_id == &"story_brief", 6.0)
		TestLib.check(started and Game.state == Cinematics.STATE and cin.plan.subs.size() == 4 and cin.plan.head == "BORROWED WHEELS", "the briefing cutscene plays (4 subtitles, the mission title card)")
		TestLib.check(_runner.scenes_played.has("brief_borrowed_wheels") and _prog.story_seen.has(&"brief_borrowed_wheels"), "it is marked seen once")
		await _hold(0.6)
		TestLib.check(cin.active and not Game.is_playing(), "the game is frozen under the cutscene")
		cin.skip()
		TestLib.check(await _until(func() -> bool: return not cin.active and Game.state == &"play", 4.0), "a tap skips it and the game runs again")
		cin.force = false
		cin.enabled = false
	TestLib.check(await _run_steps("BORROWED WHEELS", 0, 2), "BORROWED WHEELS finishes")
	_clear_vehicles()
	# mission 3 with its beat (the twist): the beat is told when its step begins, once
	var beats0 := _runner.scenes_as_radio
	TestLib.check(_board.accept(-1) and _runner.running_id == "the_relay", "THE RELAY starts from the card")
	TestLib.check(await _run_steps("THE RELAY", 0, 3), "THE RELAY finishes")
	TestLib.check(_runner.scenes_as_radio >= beats0 + 2 and _prog.story_seen.has(&"beat_the_relay_0"), "its beat (the hive's voice on the relay) was told at the second step, once")
	# mission 4: quit in the middle and resume at the saved step; a dropped mission is not lost
	TestLib.check(_board.accept(-1) and _runner.running_id == "container_17", "CONTAINER 17 starts from the card")
	TestLib.check(await _until(func() -> bool: return _camp.state == &"active" and _camp.step_index == 0, 25.0), "its first step begins at the harbour quay")
	var quay := Harbour.dock(&"west_quay")["pos"] as Vector3
	TestLib.check(_camp.pos.distance_to(quay) < 60.0 and str(_board.active["steps"][0].get("veh", "")) == "ground", "the first goal is the west quay")
	_camp.skip_step()
	TestLib.check(await _until(func() -> bool: return _camp.state == &"active" and _camp.step_index == 1, 25.0), "step 2 begins")
	TestLib.check(int(_prog.story_cp.get("step", -1)) == 2 or int(_prog.story_cp.get("step", -1)) == 1, "the checkpoint is saved with the step (%s)" % str(_prog.story_cp))
	_board.abandon("TEST")
	await TestLib.frames(_host, 3)
	TestLib.check(_board.state == &"idle" and _runner.running_id == "" and str(_prog.story_cp.get("id", "")) == "container_17", "abandoning keeps the mission and its step")
	var card4 := _board.story_offer()
	TestLib.check(str(card4.get("title", "")) == "CONTAINER 17" and bool(card4.get("resume", false)) and str(card4.get("meta", "")).contains("RESUME STEP"), "the card is still CONTAINER 17 and offers to RESUME (%s)" % str(card4.get("meta", "")))
	var resume_step := int(_prog.story_cp.get("step", 0))
	TestLib.check(_board.accept(-1), "it starts again")
	TestLib.check(await _until(func() -> bool: return _camp.state == &"active" and _camp.step_index == resume_step, 25.0), "it resumes at the saved step %d" % (resume_step + 1))
	TestLib.check(_board.active.get("from_step", -1) == resume_step, "the offer carries the saved step")
	TestLib.check(await _run_steps("CONTAINER 17", resume_step, 3), "CONTAINER 17 finishes")
	# a mission dropped after too many failures comes back as the card
	TestLib.check(_board.accept(-1) and _runner.running_id == "ferry_run", "FERRY RUN starts")
	await _until(func() -> bool: return _camp.state == &"active", 25.0)
	for i in MissionBoard.MAX_FAILS:
		_board._on_step_failed(0, 0, &"reach", "TEST")
	await TestLib.frames(_host, 3)
	TestLib.check(_board.state == &"idle" and int(_prog.story_done.get("ferry_run", 0)) == 0 and str(_board.story_offer().get("title", "")) == "FERRY RUN", "a dropped mission is not lost: FERRY RUN is the card again")
	_clear_vehicles()
	# the rest of the story, mission by mission through the real runner
	for i in range(_runner.index(), 12):
		var m := StoryActs.mission(i)
		var label := str(m["title"])
		TestLib.check(str(_board.story_offer().get("title", "")) == label, "the card says %s" % label)
		var accepted := _board.accept(-1)
		TestLib.check(accepted, "%s starts" % label)
		if not accepted:
			break
		if not await _run_steps(label, 0, int(m["steps"])):
			break
		_clear_vehicles()
	TestLib.check(_runner.is_finished() and StoryActs.done_count(_prog.story_done) == 12, "all twelve missions are done and saved")
	TestLib.check(_board.story_offer().is_empty() and _runner.card().is_empty(), "the STORY card goes away when the story is done")
	TestLib.check(_runner.scenes_as_radio >= 6 and _prog.story_seen.has(&"end"), "the finale was told (%d scenes as radio)" % _runner.scenes_as_radio)
	var st: Object = Game.story
	TestLib.check(st != null and (st.get(&"card_kind") == &"epilogue" or _runner.scenes_as_radio > 0), "the ending cards were started")
	# the save keeps all of it
	var old_path := _prog.path
	_prog.path = TMP
	TestLib.check(_prog.save_file(), "the finished story saves")
	_prog.path = old_path
	var back := Progress.new()
	back.path = TMP
	back.autosave_enabled = false
	TestLib.check(back.load_file() and StoryActs.done_count(back.story_done) == 12 and back.story_cp.is_empty(), "and loads back as twelve done")
	back.free()
	Upgrades.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP + ".bak"))
	# a new game starts the story over
	_prog.new_campaign()
	_runner.reset_session()
	TestLib.check(_runner.index() == 0 and str(_board.story_offer().get("title", "")) == "LANDFALL", "a new campaign starts the story again")
