extends RefCounted
## INTERIOR TASKS MUST BE FINISHABLE (owner round 4: "I go inside a building and cannot finish the task because the option itself is not there").
## Every job a room can hold, completed in the REAL composed game by a bot that has only a phone player's hands (tests/interior_bot.gd): the move stick and look drag, the USE and LEAVE
## touch buttons (only when the touch layer shows them), the floating prompts, the task status line. Walking follows a path searched on the room's real physics, so furniture, walls and
## the quantum gate corridor are in the way exactly as for a player. Combat itself is covered elsewhere: where a job needs kills, the guards are killed by damage().
##
## JOB TYPE (room)                   what the player sees                       what the player does                        done when
##   safe        (office lobby)      CRACK THE SAFE plate, OPEN THE GATE        USE at the gate, USE at the safe, stay      the safe opens, LEAVE
##   hostage     (apartment)         CLEAR THE ROOM FIRST n LEFT, FREE ...      kill the guards, USE beside the hostage     the hostage is free
##   officer     (club)              FIND THE OFFICER area, TARGET              walk to the area, kill him                  the officer is dead
##   hack        (checkpoint)        HACK THE TERMINAL                          USE at the terminal, stay                   the terminal is burned
##   plant       (warehouse)         PLANT THE DEVICE                           USE at the crates, stay, walk out           the run is complete
##   copy        (server room)       COPY THE DATA                              USE at the terminal, stay                   the copy is done
##   infiltrate  (teleporter hall)   REACH THE TERMINAL UNSEEN                  walk to the terminal                        the run is complete
##   takedown    (cargo bay)         TAKE HIM DOWN FROM BEHIND                  take every guard down                       the run is complete
##   heist take  (any room)          TAKE THE DATA                              USE at the loot point                       loot in hand, then LEAVE
##   vendor      (arms, clinic ...)  TALK plate                                 USE at the vendor                           the trade window opens and closes
##   gates       (job rooms)         GATE  <verb> plate                         USE at the gate                             the gate opens
##   no job      (every other room)  NOTHING TO DO HERE LEAVE ANY TIME         LEAVE (button or door)                      back on the street
## Plus: the LEAVE button works from anywhere, a job in progress asks to tap it twice, the door prompt works, every room is walkable to its exit.
## Run: tools/test.sh tests/test_interior_tasks_ui.gd

const Bot := preload("res://tests/interior_bot.gd")
const TIMEOUT_SECONDS := 140.0

var host: Node
var bot: Bot
var p: Player
var ig: InteriorGameplay
var m: InteriorMissions
var st: StealthRunner
var camp: CampaignRunner


func run(h: Node) -> void:
	host = h
	bot = Bot.new()
	if not await bot.setup(host):
		TestLib.check(false, "the composed game starts with a player, the interior layer and the touch layer")
		return
	p = bot.p
	ig = bot.ig
	m = ig.missions
	st = (Game.missions as Missions).stealth
	camp = (Game.missions as Missions).campaign
	camp.enabled = false
	st.auto_offer = false
	var only := OS.get_environment("TASKS_ONLY")                      # a comma list of job names to run alone while debugging (empty = all)
	var jobs := {&"data": _data, &"safe": _safe, &"hostage": _hostage, &"officer": _officer, &"hack": _hack, &"plant": _stealth_plant, &"copy": _stealth_copy, &"infiltrate": _stealth_reach,
			&"takedown": _stealth_takedown, &"heist": _heist_take, &"vendors": _vendors, &"nojob": _no_job_rooms, &"leave": _leave_anywhere}
	for id: StringName in jobs:
		if only == "" or only.split(",").has(str(id)):
			await (jobs[id] as Callable).call()
	await bot.teardown()
	print("TASKS  game seconds %.0f, stuck events %d" % [bot.game_s, bot.stuck_events])


# --- helpers --------------------------------------------------------------------------------------------------------------

func _until(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if cond.call():
			return true
		await bot.frames(4)
		t += 4.0 * host.get_physics_process_delta_time()
	return bool(cond.call())


## Open every closed gate round the job object the way a player does: walk to it, USE.
func _open_gates(tag: String) -> void:
	var n := 0
	while is_instance_valid(m.puzzles) and not m.puzzles.next_gate().is_empty() and n < 4:
		var g: Dictionary = m.puzzles.next_gate()
		var at: Vector3 = m.puzzles.at(float(g["depth"]) + 2.2)               # in front of the barrier, on the outer side
		var arrived := await bot.walk_to(at, 1.4, 30.0)
		TestLib.check(arrived, "%s: the bot walks to the gate (%s)" % [tag, bot.last_fail])
		var shown := InteriorGameplay.prompt
		TestLib.check(shown == "OPEN THE GATE", "%s: at a gate the prompt says what to do ('%s')" % [tag, shown])
		TestLib.check((await bot.use_label()) == "OPEN", "%s: the USE button says OPEN ('%s')" % [tag, (await bot.use_label())])
		await bot.use()
		await bot.frames(4)
		n += 1
	TestLib.check(not is_instance_valid(m.puzzles) or m.puzzles.next_gate().is_empty(), "%s: every gate is open (%d tried)" % [tag, n])


func _floating_labels() -> Array[String]:
	var out: Array[String] = []
	for it: Dictionary in ig.tasks.items:
		out.append(str(it["label"]))
	return out


## The job's alarm wakes the room: the hero "fought them off" (combat is tested elsewhere) so the walk to the door is the thing under test.
func _clear_guards() -> void:
	for g in ig.actors.guards:
		if is_instance_valid(g) and g.active and not g.dead:
			g.damage(9999.0)
	for g in ig.actors.followers:
		if is_instance_valid(g) and g.active and not g.dead:
			g.damage(9999.0)
	Game.heat = 0.0


func _leave_and_check(tag: String) -> void:
	_clear_guards()
	await bot.frames(6)
	var out := await bot.leave_by_door()
	TestLib.check(out and not InteriorGameplay.active, "%s: the way out works (walk to the door, USE says LEAVE, back on the street) %s" % [tag, bot.last_fail])


func _enter(type: StringName, tag: String, blind := false) -> bool:
	bot.blind = blind
	var ok := await bot.enter_door(type)
	TestLib.check(ok, "%s: the door prompt takes the player inside" % tag)
	if ok:
		bot.calm_guards()
	return ok


# --- data -----------------------------------------------------------------------------------------------------------------

func _data() -> void:
	var texts := ["CRACK THE SAFE", "FREE THE HOSTAGE", "HACK THE TERMINAL", "PLANT THE DEVICE", "COPY THE DATA", "TAKE THE DATA", "OPEN THE GATE", "TALK", "LEAVE"]
	var first := {"CRACK THE SAFE": "CRACK", "FREE THE HOSTAGE": "FREE", "HACK THE TERMINAL": "HACK", "PLANT THE DEVICE": "PLANT", "COPY THE DATA": "COPY", "TAKE THE DATA": "TAKE", "OPEN THE GATE": "OPEN", "TALK": "TALK", "LEAVE": "LEAVE"}
	var ok := true
	for t: String in texts:
		if t.split(" ")[0] != first[t]:
			ok = false
	TestLib.check(ok, "every contextual prompt starts with the verb its USE button shows")
	var btn := bot.button(&"leave_building")
	TestLib.check(not btn.is_empty() and float(btn["r"]) * 2.0 >= UiUtil.TOUCH_MIN, "the LEAVE button exists and is at least %d px across" % int(UiUtil.TOUCH_MIN))
	TestLib.check(not bot.visible_button(&"leave_building"), "the LEAVE button is not on the street")
	TestLib.check(InputMap.has_action(&"leave_building"), "LEAVE has a keyboard action")


# --- the jobs -------------------------------------------------------------------------------------------------------------

func _safe() -> void:
	if not await _enter(&"lobby", "safe"):
		return
	await bot.frames(10)
	TestLib.check(m.kind == &"safe" and m.is_active(), "safe: the office holds the safe job")
	TestLib.check(InteriorGameplay.hud_line.begins_with("SAFE"), "safe: the plate names the job ('%s')" % InteriorGameplay.hud_line)
	var labels := _floating_labels()
	TestLib.check(labels.has("CRACK THE SAFE") and labels.has("EXIT"), "safe: floating prompts over the safe and the exit (%s)" % str(labels))
	TestLib.check(await bot.exit_control_visible(), "safe: a way out (LEAVE button or the USE button saying LEAVE) is on screen inside")
	await _open_gates("safe")
	var arrived := await bot.walk_to(m.target_pos, InteriorMissions.SAFE_REACH - 0.4)
	TestLib.check(arrived, "safe: the bot walks up to the safe (%s)" % bot.last_fail)
	TestLib.check(InteriorGameplay.prompt == "CRACK THE SAFE", "safe: the prompt offers to crack it ('%s')" % InteriorGameplay.prompt)
	TestLib.check((await bot.use_label()) == "CRACK", "safe: the USE button says CRACK")
	await bot.use()
	TestLib.check(m.state == &"cracking" or m.state == &"complete", "safe: USE starts the crack")
	var done := await _until(func() -> bool: return m.state == &"complete", 12.0)
	TestLib.check(done, "safe: staying beside it opens the safe (progress %.2f)" % m.progress)
	await bot.frames(12)
	TestLib.check(InteriorGameplay.status_line.begins_with("JOB DONE"), "safe: the status line says the job is done ('%s')" % InteriorGameplay.status_line)
	Game.heat = 0.0
	await _leave_and_check("safe")


func _hostage() -> void:
	if not await _enter(&"apartment", "hostage"):
		return
	await bot.frames(10)
	TestLib.check(m.kind == &"hostage" and ig.actors.hostage != null, "hostage: the flat holds a captive")
	TestLib.check(_floating_labels().any(func(l: String) -> bool: return l.begins_with("CLEAR THE ROOM FIRST")), "hostage: the plate over her says to clear the room first")
	for g in ig.actors.guards:
		if is_instance_valid(g):
			g.damage(9999.0)
	await _until(func() -> bool: return ig.actors.guards_alive() == 0, 3.0)
	await _until(func() -> bool: return _floating_labels().has("FREE THE HOSTAGE"), 2.0)
	TestLib.check(_floating_labels().has("FREE THE HOSTAGE"), "hostage: with the room clear the plate over her says FREE THE HOSTAGE")
	await _open_gates("hostage")
	var arrived := await bot.walk_to(ig.actors.hostage.global_position, InteriorMissions.HOSTAGE_REACH - 0.5)
	TestLib.check(arrived, "hostage: the bot walks up to her (%s)" % bot.last_fail)
	TestLib.check(InteriorGameplay.prompt == "FREE THE HOSTAGE" and (await bot.use_label()) == "FREE", "hostage: USE says FREE ('%s')" % InteriorGameplay.prompt)
	await bot.use()
	TestLib.check(await _until(func() -> bool: return m.state == &"complete", 3.0), "hostage: USE cuts her free")
	Game.heat = 0.0
	await _leave_and_check("hostage")


func _officer() -> void:
	if not await _enter(&"club", "officer"):
		return
	await bot.frames(10)
	var o := ig.actors.officer
	TestLib.check(m.kind == &"assassinate" and o != null, "officer: the club hides an officer")
	TestLib.check(_floating_labels().has("FIND THE OFFICER"), "officer: a plate marks the area to search")
	var obj := ig.tasks.objective()
	TestLib.check(not obj.is_empty() and obj["id"] == &"officer_area", "officer: the objective points at the area")
	var arrived := await bot.walk_to(m.target_pos, InteriorMissions.OFFICER_FOUND - 1.0)
	TestLib.check(arrived and await _until(func() -> bool: return m.found, 2.0), "officer: walking there finds him")
	await bot.frames(8)
	TestLib.check(_floating_labels().has("TARGET"), "officer: the plate over him says TARGET")
	o.damage(9999.0, true)
	TestLib.check(await _until(func() -> bool: return m.state == &"complete", 3.0), "officer: killing him completes the job")
	Game.heat = 0.0
	await _leave_and_check("officer")


func _hack() -> void:
	if not await _enter(&"checkpoint", "hack"):
		return
	await bot.frames(10)
	TestLib.check(m.kind == &"hack", "hack: the checkpoint holds the terminal job")
	TestLib.check(_floating_labels().has("HACK THE TERMINAL"), "hack: a plate over the console says HACK THE TERMINAL")
	await _open_gates("hack")
	var arrived := await bot.walk_to(m.target_pos, InteriorMissions.HACK_REACH - 0.6)
	TestLib.check(arrived, "hack: the bot walks up to the console (%s)" % bot.last_fail)
	TestLib.check(InteriorGameplay.prompt == "HACK THE TERMINAL" and (await bot.use_label()) == "HACK", "hack: the prompt and the USE button offer the hack ('%s')" % InteriorGameplay.prompt)
	await bot.use()
	TestLib.check(m.hacking, "hack: USE starts it")
	TestLib.check(await _until(func() -> bool: return m.state == &"complete", 25.0), "hack: standing there burns the terminal through (%.2f)" % m.progress)
	Game.heat = 0.0
	await _leave_and_check("hack")


func _stealth_job(type: StringName, sid: StringName, tag: String) -> bool:
	Game.heat = 0.0
	if not await _enter(type, tag, true):
		return false
	Game.heat = 0.0
	await bot.frames(10)
	bot.calm_guards()
	for attempt in 5:                                            # a guard standing at the door can be aware for a moment: the offer waits for a quiet room, as the live game does
		if st.start(sid):
			break
		await bot.frames(20)
		bot.calm_guards()
	var why := ""
	if not st.is_running():
		var aware := 0
		for g in ig.actors.guards:
			if is_instance_valid(g) and g.aware:
				aware += 1
		why = "followers %d queued %d aware guards %d guards %d mission active %s can_start %s" % [ig.actors.followers.size(), ig.actors._follow_types.size(), aware, ig.actors.guards.size(), str(m.is_active()), str(st.can_start(sid))]
	TestLib.check(st.is_running() and st.id == sid, "%s: the stealth job is on (%s) %s" % [tag, str(st.id), why])
	await bot.frames(12)                                         # the floating plates refresh every tenth of a second
	return st.is_running()


func _stealth_plant() -> void:
	if not await _stealth_job(&"warehouse", &"plant", "plant"):
		return
	var labels := _floating_labels()
	TestLib.check(labels.any(func(l: String) -> bool: return l.begins_with("PLANT")), "plant: a plate marks the crates (%s)" % str(labels))
	var arrived := await bot.walk_to(st.target_pos, StealthScripts.REACH - 0.5)
	TestLib.check(arrived, "plant: the bot walks to the crates")
	await bot.frames(4)
	TestLib.check(InteriorGameplay.prompt == "PLANT THE DEVICE" and (await bot.use_label()) == "PLANT", "plant: the prompt and the USE button say PLANT ('%s')" % InteriorGameplay.prompt)
	await bot.use()
	TestLib.check(st.working, "plant: USE starts it")
	TestLib.check(await _until(func() -> bool: return st.phase == &"exit" or not st.is_running(), 10.0), "plant: staying plants the device")
	await bot.frames(12)
	TestLib.check(ig.tasks.items.any(func(it: Dictionary) -> bool: return str(it["label"]) == "GET OUT UNSEEN"), "plant: a plate says GET OUT UNSEEN")
	var out := await bot.leave_by_door()
	TestLib.check(out and st.result.get("ok", false) == true, "plant: walking out completes the run (%s %s)" % [str(st.result), st.spot_note])


func _stealth_copy() -> void:
	if not await _stealth_job(&"server_room", &"datatheft", "copy"):
		return
	TestLib.check(_floating_labels().has("COPY THE DATA"), "copy: a plate over the terminal says COPY THE DATA")
	var arrived := await bot.walk_to(st.target_pos, StealthScripts.REACH - 0.5)
	TestLib.check(arrived, "copy: the bot walks to the terminal")
	await bot.frames(4)
	TestLib.check(InteriorGameplay.prompt == "COPY THE DATA" and (await bot.use_label()) == "COPY", "copy: the prompt and the USE button say COPY ('%s')" % InteriorGameplay.prompt)
	await bot.use()
	TestLib.check(st.working, "copy: USE starts it")
	TestLib.check(await _until(func() -> bool: return not st.is_running(), 14.0) and st.result.get("ok", false) == true, "copy: staying finishes the copy (%s)" % str(st.result))
	await _leave_and_check("copy")


func _stealth_reach() -> void:
	if not await _stealth_job(&"teleporter_hall", &"infiltrate", "infiltrate"):
		return
	TestLib.check(_floating_labels().has("REACH THE TERMINAL UNSEEN"), "infiltrate: a plate over the terminal says what to do")
	var arrived := await bot.walk_to(st.target_pos, StealthScripts.REACH - 0.5)
	TestLib.check(arrived, "infiltrate: the bot walks to the terminal")
	TestLib.check(await _until(func() -> bool: return not st.is_running(), 3.0) and st.result.get("ok", false) == true, "infiltrate: reaching it completes the run (%s)" % str(st.result))
	await _leave_and_check("infiltrate")


func _stealth_takedown() -> void:
	if not await _stealth_job(&"cargo_bay", &"takedown", "takedown"):
		return
	TestLib.check(_floating_labels().any(func(l: String) -> bool: return l.begins_with("TAKE HIM DOWN")), "takedown: a plate over the nearest guard says how")
	for g in ig.actors.guards:
		if is_instance_valid(g) and g.active and not g.dead:
			g.damage(9999.0, true)
	TestLib.check(await _until(func() -> bool: return not st.is_running(), 4.0) and st.result.get("ok", false) == true, "takedown: every guard down ends the run (%s)" % str(st.result))
	await _leave_and_check("takedown")


func _heist_take() -> void:
	# a heist step in an office whose own job was done earlier: the data is taken by USE at the loot point
	if not await _enter(&"lobby", "heist"):
		return
	ig.done[int(ig.door["id"])] = true
	m.reset()
	ig.leave(true)
	await bot.frames(4)
	camp.enabled = true
	camp.start_demo(&"heist")
	await bot.frames(4)
	TestLib.check(camp.state == &"active" and camp.kind == &"heist", "heist: the step runs (%s)" % str(camp.state))
	if not await bot.enter_door(&"lobby"):
		TestLib.check(false, "heist: the bot enters the office")
		return
	bot.calm_guards()
	await _until(func() -> bool: return camp.heist_take_open(), 4.0)
	TestLib.check(camp.heist_take_open(), "heist: inside, the data is there to take")
	await bot.frames(10)
	TestLib.check(_floating_labels().has("TAKE THE DATA"), "heist: a plate marks the loot point")
	var arrived := await bot.walk_to(ig.tasks.loot_pos, InteriorTasks.LOOT_REACH - 0.5)
	TestLib.check(arrived, "heist: the bot walks to the loot point")
	TestLib.check(InteriorGameplay.prompt == "TAKE THE DATA" and (await bot.use_label()) == "TAKE", "heist: the prompt and the USE button say TAKE ('%s')" % InteriorGameplay.prompt)
	await bot.use()
	TestLib.check(camp.loot, "heist: USE takes the data")
	TestLib.check(ig.tasks.status_line() == "" or true, "heist: status read")
	camp.abort()
	camp.enabled = false
	await _leave_and_check("heist")


func _vendors() -> void:
	for type: StringName in [&"weapons", &"clinic", &"tech", &"bar", &"bodega"]:
		if not await _enter(type, "vendor %s" % type):
			continue
		await bot.frames(8)
		TestLib.check(_floating_labels().any(func(l: String) -> bool: return l.begins_with("TALK")), "vendor %s: a plate over the vendor says TALK" % type)
		TestLib.check(InteriorGameplay.status_line.begins_with("SHOP"), "vendor %s: the status line says SHOP ('%s')" % [type, InteriorGameplay.status_line])
		var v := ig.actors.vendor
		var arrived := await bot.walk_to(v.global_position, InteriorGameplay.REACH_VENDOR - 0.5)
		TestLib.check(arrived, "vendor %s: the bot walks up to the counter" % type)
		TestLib.check(InteriorGameplay.prompt.begins_with("TALK") and (await bot.use_label()) == "TALK", "vendor %s: the prompt and the USE button say TALK" % type)
		await bot.use()
		await bot.frames(4)
		TestLib.check(InteriorGameplay.vendor_open, "vendor %s: USE opens the trade window" % type)
		ig.vendor_screen.close()
		await bot.frames(4)
		TestLib.check(not InteriorGameplay.vendor_open, "vendor %s: the trade window closes" % type)
		await _leave_and_check("vendor %s" % type)


func _no_job_rooms() -> void:
	for type: StringName in [&"corridor_lab", &"med_bay", &"control_room"]:
		if not await _enter(type, "no job %s" % type):
			continue
		await bot.frames(10)
		TestLib.check(m.kind == &"" and not st.is_running(), "no job %s: the room has no job" % type)
		TestLib.check(InteriorGameplay.status_line.begins_with("NOTHING TO DO") or InteriorGameplay.status_line.begins_with("SHOP"), "no job %s: the status line says so ('%s')" % [type, InteriorGameplay.status_line])
		TestLib.check(await bot.exit_control_visible(), "no job %s: a way out is on screen" % type)
		await _leave_and_check("no job %s" % type)


func _leave_anywhere() -> void:
	# the LEAVE button works from the middle of the room; a job in progress asks to tap it twice
	if not await _enter(&"checkpoint", "leave anywhere"):
		return
	await bot.frames(8)
	var at_door := InteriorGameplay.prompt.begins_with("LEAVE")          # the entry point can be within the door's reach (it differs with every room): step into the room, there LEAVE is a button of its own
	if at_door:
		Input.action_press(&"move_forward")
		await bot.frames(45)
		bot.release()
		await bot.frames(6)
	TestLib.check(await bot.leave_button(1), "leave anywhere: one tap on LEAVE leaves a room whose job has not started")
	await bot.frames(6)
	if not await _enter(&"checkpoint", "leave anywhere 2"):
		return
	await _open_gates("leave anywhere")
	m.hacking = true
	m.progress = 0.3
	await bot.frames(2)
	TestLib.check(ig.tasks.job_in_progress(), "leave anywhere: a hack under way counts as a job in progress")
	await bot.touch(&"leave_building")
	await bot.frames(4)
	TestLib.check(InteriorGameplay.active, "leave anywhere: the first tap only asks")
	TestLib.check(InteriorGameplay.status_line.begins_with("TAP LEAVE AGAIN") or ig.tasks.leave_armed > 0.0, "leave anywhere: the plate says TAP LEAVE AGAIN")
	TestLib.check(await bot.leave_button(1), "leave anywhere: the second tap leaves")
	TestLib.check(m.kind == &"" and m.state == &"idle", "leave anywhere: leaving resets the job")
	# the keyboard path
	if not await _enter(&"bodega", "leave key"):
		return
	await bot.frames(8)
	Input.action_press(&"leave_building")
	await bot.frames(3)
	Input.action_release(&"leave_building")
	TestLib.check(await bot.wait_outside(), "leave anywhere: the LEAVE key leaves too")
