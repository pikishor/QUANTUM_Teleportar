extends RefCounted
## The three heist missions (VAULT, CONVOY, DATA CENTRE; scripts/missions/heist_scripts.gd + heist_runner.gd) in the REAL scene (main.tscn): every heist x approach builds a valid chapter of
## campaign step kinds, approaches differ (loud adds a fight, quantum a rift, stealth neither), pay reads Economy and a replay pays less, the DEMO entry starts a run, a real step (reach) is
## completed by the live CampaignRunner, the stages are skipped through to the end (paid, tallied, saved), three step failures call the heist off, the story chapter that ran before comes back,
## the crew toggle recruits and dismisses the ally, and the planning screen (pause shop HEISTS) picks, toggles the crew and LAUNCHes with 64 px buttons; locked sectors refuse. The campaign is
## ticked by hand (physics off); waits are on state. Progress writes to a throw-away file. Not run: a phone, the feel of the stages.
## Run: tools/test.sh tests/test_heists.gd

const TMP := "user://test_heists_save.cfg"

var host: Node
var main: Node
var hr: HeistRunner
var k: CampaignRunner
var prog: Progress
var p: Player
var ended: Array = []


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_data()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	var m := Game.missions as Missions
	p = Game.player as Player
	TestLib.check(m != null and m.heists != null and m.campaign != null and p != null, "main.tscn composes Missions.heists, the campaign and the player")
	if m == null or m.heists == null or m.campaign == null or p == null:
		return
	hr = m.heists
	k = m.campaign
	prog = Game.progress as Progress
	prog.path = TMP
	prog.autosave_enabled = false
	prog.new_campaign()
	k.set_physics_process(false)
	k.set_process(false)
	hr.finished.connect(func(hid: StringName, ok: bool, why: String) -> void: ended.append([hid, ok, why]))
	var was_demo := DemoMode.active
	DemoMode.active = true
	await _reset()

	await _launch_and_real_step()
	await _complete_all()
	await _fail_out()
	await _story_returns()
	await _board()
	_locked()

	DemoMode.active = was_demo
	hr.abort("TEST")
	k.abort()
	Game.heat = 0.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _reset() -> void:
	hr.abort("TEST")
	k.abort()
	Game.state = &"play"
	Game.heat = 0.0
	p.hp = p.max_hp
	ended.clear()
	await TestLib.frames(host, 3)


func _kinds(ch: Dictionary) -> Array:
	var out: Array = []
	for s: Dictionary in CampaignSteps.normalize_chapter(ch):
		out.append(String(s["kind"]))
	return out


func _data() -> void:
	TestLib.check(HeistScripts.IDS.size() == 3 and HeistScripts.APPROACHES.size() == 3, "three heists, three approaches")
	for id: StringName in HeistScripts.IDS:
		for ap: StringName in HeistScripts.APPROACHES:
			var why := HeistScripts.validate(id, ap)
			TestLib.check(why == "", "%s / %s is valid (%s)" % [id, ap, why])
			var ch := HeistScripts.chapter(id, ap)
			TestLib.check(not bool(ch["clears_sector"]) and (ch["steps"] as Array).size() >= 3, "%s / %s: a multi-stage chapter that does not clear the sector" % [id, ap])
	TestLib.check(_kinds(HeistScripts.chapter(&"vault", &"loud")).has("defend") and not _kinds(HeistScripts.chapter(&"vault", &"stealth")).has("defend"), "loud adds a fight, stealth does not")
	TestLib.check(_kinds(HeistScripts.chapter(&"convoy", &"quantum")).has("rift_hold") and _kinds(HeistScripts.chapter(&"convoy", &"quantum")).has("convoy_intercept"), "the convoy heist intercepts, quantum adds a rift")
	TestLib.check(_kinds(HeistScripts.chapter(&"datacenter", &"stealth")).has("heist") and _kinds(HeistScripts.chapter(&"vault", &"stealth")).has("heist"), "vault and data centre use the heist step")
	var types := {}
	for id: StringName in HeistScripts.IDS:
		var texts: Array = []
		for st: Dictionary in HeistScripts.chapter(id, &"stealth")["steps"]:
			texts.append(String(st["text"]))
		types[texts.hash()] = true
	TestLib.check(types.size() == 3, "the three heists have different stages")
	var a := HeistScripts.reward(&"vault", &"stealth", 2, 0, false)
	var b := HeistScripts.reward(&"vault", &"quantum", 2, 0, false)
	var c := HeistScripts.reward(&"vault", &"loud", 2, 0, false)
	TestLib.check(a < b and b < c, "pay rises stealth < quantum < loud (%d %d %d)" % [a, b, c])
	TestLib.check(HeistScripts.reward(&"vault", &"loud", 2, 0, true) < c, "a replay pays less")
	TestLib.check(HeistScripts.reward(&"datacenter", &"stealth", 6, 0, false) > HeistScripts.reward(&"datacenter", &"stealth", 2, 0, false), "pay grows with the sector")
	var cat := DemoMode.catalog()
	var group: Dictionary = {}
	for g: Dictionary in cat:
		if g["kind"] == &"heist":
			group = g
	TestLib.check(not group.is_empty() and (group["items"] as Array).size() == 9, "the DEMO catalogue lists every heist x approach")
	TestLib.check(DemoPanel.TABS.has("HEIST") and DemoPanel.TABS.find("HEIST") == cat.find(group), "the HEIST tab is the heist catalogue page")


func _launch_and_real_step() -> void:
	var status := DemoMode.launch(&"heist", "vault:quantum")
	TestLib.check(status != "" and hr.is_running() and hr.id == &"vault" and hr.approach == &"quantum", "the DEMO entry starts VAULT / QUANTUM (%s)" % status)
	TestLib.check(k.is_running() and k.steps.size() == int(hr.stage()["count"]) and int(hr.stage()["index"]) == 1, "the campaign runs the heist's stages")
	var c := Companion.current
	TestLib.check(c == null or c.active, "the DEMO launch brings the crew ally")
	# a real stage: the reach step ends when the hero gets there (live CampaignRunner)
	var t := 0.0
	while t < 10.0 and not k.is_active():
		k.tick(0.25)
		t += 0.25
	TestLib.check(k.is_active() and k.kind == &"reach", "the first stage is a live REACH")
	p.teleport_to(Vector3(k.pos.x, 0.1, k.pos.z))
	t = 0.0
	while t < 10.0 and k.step_index < 1:
		k.tick(0.25)
		t += 0.25
	TestLib.check(k.step_index >= 1 and k.steps_done >= 1, "arriving completes the reach stage")
	hr.abort("TEST")
	TestLib.check(not hr.is_running() and not k.is_running() and (c == null or not c.active), "abort stops the run and sends the crew away")


## Skips every stage (the TEST path) until the heist reports done.
func _finish(hid: StringName) -> void:
	var guard := 0
	while hr.is_running() and guard < 400:
		guard += 1
		if k.is_active():
			k.skip_step()
		else:
			k.tick(0.5)


func _complete_all() -> void:
	for id: StringName in HeistScripts.IDS:
		await _reset()
		var ap: StringName = HeistScripts.APPROACHES[HeistScripts.IDS.find(id)]
		var cr0 := prog.credits
		var want := HeistScripts.reward(id, ap, int(Game.story.get("chapter")), prog.reputation, false)
		TestLib.check(DemoMode.launch(&"heist", "%s:%s" % [id, ap]) != "" and hr.is_running(), "%s / %s starts" % [id, ap])
		_finish(id)
		TestLib.check(not hr.is_running() and ended.size() == 1 and bool(ended[0][1]), "%s / %s completes" % [id, ap])
		TestLib.check(prog.credits - cr0 == want and int(hr.result["reward"]) == want, "%s pays %d (got %d)" % [id, want, prog.credits - cr0])
		TestLib.check(int(prog.heist_done.get(id, 0)) == 1, "%s is tallied" % id)
		TestLib.check(not k.is_running(), "the campaign is idle after %s" % id)
	# replayable: the same heist again pays the replay share and bumps the tally
	await _reset()
	var cr1 := prog.credits
	var want2 := HeistScripts.reward(&"vault", &"stealth", int(Game.story.get("chapter")), prog.reputation, true)
	TestLib.check(DemoMode.launch(&"heist", "vault:stealth") != "", "the vault can be replayed")
	_finish(&"vault")
	TestLib.check(bool(hr.result["replay"]) and prog.credits - cr1 == want2 and int(prog.heist_done[&"vault"]) == 2, "a replay pays %d and counts again" % want2)
	TestLib.check(prog.save_file(), "save")
	var done := prog.heist_done.duplicate()
	prog.heist_done.clear()
	TestLib.check(prog.load_file() and prog.heist_done == done, "the heist tally survives a save round trip")


func _fail_out() -> void:
	await _reset()
	var rep0 := prog.reputation
	var cr0 := prog.credits
	TestLib.check(DemoMode.launch(&"heist", "convoy:loud") != "", "CONVOY / LOUD starts")
	var t := 0.0
	while t < 10.0 and not k.is_active():
		k.tick(0.25)
		t += 0.25
	for i in HeistScripts.MAX_FAILS:
		if not hr.is_running():
			break
		TestLib.check(k.is_active() or k.state == &"retry", "a stage is live before failure %d" % (i + 1))
		k._fail("TEST")
		if hr.is_running():
			t = 0.0
			while t < 12.0 and not k.is_active():
				k.tick(0.25)
				t += 0.25
	TestLib.check(not hr.is_running() and ended.size() == 1 and not bool(ended[0][1]), "three failed stages call the heist off")
	TestLib.check(prog.credits == cr0 and prog.reputation == rep0 + HeistScripts.FAIL_REP, "a failure pays nothing and costs reputation")
	TestLib.check(not k.is_running() and not bool(hr.result["ok"]), "the campaign stopped with it")


func _story_returns() -> void:
	await _reset()
	var idx := maxi(int(Game.story.get("chapter")), 0)
	var story_id := str(k.chapter_data(idx).get("id", ""))
	var started := k.start_chapter(idx, 0, true)
	TestLib.check(started and k.is_running(), "a story chapter is running (%s)" % story_id)
	if not started:
		return
	var t := 0.0
	while t < 5.0 and not k.is_active():
		k.tick(0.25)
		t += 0.25
	TestLib.check(hr.can_start(&"datacenter"), "a heist can be planned while the chapter runs")
	TestLib.check(hr.start(&"datacenter", &"stealth", false) and str(k.chapter_data(idx).get("id", "")).begins_with("heist_"), "the heist takes the step slot")
	hr.abort("TEST")
	TestLib.check(k.is_running() and str(k.chapter_data(idx).get("id", "")) == story_id and k.chapter_index == idx, "the story chapter comes back after the heist")
	k.abort()


func _board() -> void:
	await _reset()
	var hud: Hud = null
	for n in main.find_children("*", "Hud", true, false):
		hud = n as Hud
	if hud == null:
		TestLib.check(false, "the HUD exists")
		return
	Game.state = &"paused"
	await TestLib.frames(host, 4)
	hud._shop_open = true
	TestLib.check(hud.press_button(&"heist_open") and hud._heist_open, "HEISTS opens the planning screen from the shop")
	await TestLib.frames(host, 3)
	var s := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
	var ids := {}
	for bt: Dictionary in hud.buttons:
		var bid := String(bt["id"])
		if bid.begins_with("heist_"):
			ids[bid] = true
			TestLib.check((bt["rect"] as Rect2).size.y >= UiUtil.TOUCH_MIN * s - 1.0, "%s is at least 64 px tall" % bid)
	TestLib.check(ids.size() == 9, "pick x3, approach x3, crew, LAUNCH, BACK are laid out (%d)" % ids.size())
	TestLib.check(hud.press_button(&"heist_pick_datacenter") and HeistBoard.sel == &"datacenter", "a heist is picked")
	TestLib.check(hud.press_button(&"heist_ap_quantum") and HeistBoard.approach == &"quantum", "an approach is picked")
	var before := HeistBoard.payout()
	TestLib.check(hud.press_button(&"heist_ap_loud") and HeistBoard.payout() > before, "the loud approach shows more pay")
	TestLib.check(hud.press_button(&"heist_ap_quantum") and hud.press_button(&"heist_crew") and HeistBoard.crew, "the crew is switched to ALLY")
	TestLib.check(hud.press_button(&"heist_go"), "LAUNCH starts the heist")
	TestLib.check(Game.state == &"play" and hr.is_running() and hr.id == &"datacenter" and hr.approach == &"quantum" and hr.crew, "the planned heist runs in the live city")
	var c := Companion.current
	TestLib.check(c == null or c.active, "the planned crew joins")
	hr.abort("TEST")
	TestLib.check(c == null or not c.active, "the crew leaves when the heist ends")
	HeistBoard.crew = false
	HeistBoard.sel = &"vault"
	HeistBoard.approach = &"stealth"
	await _reset()


func _locked() -> void:
	DemoMode.active = false
	prog.new_campaign()
	Game.story.set("chapter", 0)
	TestLib.check(not hr.can_start(&"vault") and not hr.start(&"vault", &"stealth", false), "a heist stays locked below its sector")
	DemoMode.active = true
