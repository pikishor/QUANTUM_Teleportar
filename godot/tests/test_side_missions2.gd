extends RefCounted
## Side missions batch 2 (scripts/missions/side_missions.gd): ten more jobs (twenty in all) in the REAL scene (main.tscn): the table, Economy rows and chapter gates agree,
## every new job completes through its stages (hand-ticked), smash stages count real Breakables.break_total through _physics_process, the blackout job turns night vision on and
## off, vehicle theft adds heat, the board pages through all twenty jobs and START begins a job from page 2, tallies are save-compatible. Progress writes to a throw-away file;
## state, not frame counts. Not run: a phone, the look of the night-vision tint.
## Run: tools/test.sh tests/test_side_missions2.gd

const TMP := "user://test_side_missions2_save.cfg"
const NEW: Array[StringName] = [&"bounty", &"sniper", &"swarm", &"car_theft", &"hostage", &"blackout", &"data_courier", &"arena", &"demolition", &"anomaly"]

var host: Node
var main: Node
var sm: SideMissions
var prog: Progress


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	var m := Game.missions as Missions
	if m == null or m.sides == null or Game.player == null:
		TestLib.check(false, "main.tscn composes Missions.sides and the player")
		return
	sm = m.sides
	prog = Game.progress as Progress
	prog.path = TMP
	prog.autosave_enabled = false
	prog.new_campaign()
	m.contracts.set_physics_process(false)
	sm.set_physics_process(false)
	var was_demo := DemoMode.active
	DemoMode.active = true
	_table()
	_complete_all()
	await _smash_live()
	_night_and_heat()
	await _board()
	_save()
	DemoMode.active = was_demo
	sm.abort("TEST")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _table() -> void:
	TestLib.check(SideMissions.ORDER.size() == 20 and SideMissions.DEFS.size() == 20, "twenty side missions")
	var ok := true
	for id in NEW:
		ok = ok and SideMissions.ORDER.has(id) and SideMissions.DEFS.has(id) and Economy.SIDE_PAY.has(id) and Economy.SIDE_CHAPTER.has(id)
		ok = ok and int(Economy.SIDE_PAY[id]) == int(SideMissions.def(id)["pay"]) and int(Economy.SIDE_CHAPTER[id]) == int(SideMissions.def(id)["chapter"])
		ok = ok and SideMissions.build_route(id, Vector3.ZERO, 0).size() == (SideMissions.def(id)["stages"] as Array).size()
	TestLib.check(ok, "new jobs: table, Economy rows, chapter gates and routes agree")


func _complete(id: StringName) -> bool:
	if not sm.start(id, Vector3(10, 0, 10)):
		return false
	var guard := 0
	while sm.active and guard < 40:
		guard += 1
		var s: Dictionary = sm.stages[sm.stage]
		var pos: Vector3 = s["pos"]
		match String(s["kind"]):
			"goto": sm.tick(0.1, pos + Vector3(1, 0, 0), Vector3.RIGHT, bool(s["car"]))
			"dwell": sm.tick(float(s["secs"]) + 0.5, pos, Vector3.RIGHT, false)
			"photo": sm.tick(0.1, pos + Vector3(-20, 0, 0), Vector3.RIGHT, false)
			"kill":
				for i in int(s["n"]):
					sm.on_kill()
				sm.tick(0.1, pos, Vector3.RIGHT, false)
			"smash":
				for i in int(s["n"]):
					sm.on_smash()
				sm.tick(0.1, pos, Vector3.RIGHT, false)
	return not sm.active and bool(sm.last_result.get("ok", false))


func _complete_all() -> void:
	var before := prog.credits
	for id in NEW:
		TestLib.check(_complete(id), "%s completes through its stages" % id)
		TestLib.check(sm.status_line() == "", "%s: idle afterwards" % id)
	TestLib.check(prog.credits > before + 2000 and prog.side_done.size() >= 10, "credits paid and tallies recorded")
	sm.start(&"demolition", Vector3.ZERO)
	TestLib.check(sm.status_line().contains("BREAK PROPS") and not sm.waypoint().is_finite(), "smash stage: status line, no waypoint")
	sm.tick(1000.0, Vector3.ZERO, Vector3.RIGHT, false)
	TestLib.check(not sm.active and sm.last_result["reason"] == "TIME UP", "demolition fails on the clock")


func _smash_live() -> void:
	var b := Breakables.current
	TestLib.check(b != null, "Breakables exists in the live scene")
	if b == null:
		return
	sm.set_physics_process(true)
	Game.state = &"play"
	TestLib.check(sm.start(&"demolition", Game.player.global_position), "demolition starts in the live scene")
	var n := 0
	var i := 0
	while n < 8 and i < b.positions.size():
		if b.broken[i] == 0:
			b.break_prop(i)
			n += 1
		i += 1
	var guard := 0
	while sm.active and guard < 300:
		guard += 1
		await TestLib.frames(host, 2)
	TestLib.check(not sm.active and bool(sm.last_result.get("ok", false)), "real prop breaks complete the demolition (%s)" % str(sm.last_result))
	sm.set_physics_process(false)


func _night_and_heat() -> void:
	sm.start(&"blackout", Vector3.ZERO)
	TestLib.check(sm.night_vision_on(), "blackout: night vision on")
	sm.abort("TEST")
	TestLib.check(not sm.night_vision_on(), "night vision off when the job ends")
	var h0: float = Game.heat
	sm.start(&"car_theft", Vector3.ZERO)
	TestLib.check(Game.heat > h0, "vehicle theft adds heat")
	sm.abort("TEST")


func _board() -> void:
	var hud: Hud = null
	for n in main.find_children("*", "Hud", true, false):
		hud = n as Hud
	if hud == null:
		TestLib.check(false, "the HUD exists")
		return
	Game.state = &"paused"
	await TestLib.frames(host, 4)
	hud._shop_open = true
	TestLib.check(hud.press_button(&"side_open") and hud._side_open and SideBoard.page == 0, "board opens on page 1")
	TestLib.check(SideBoard.pages() == 2, "two pages")
	TestLib.check(hud.press_button(&"side_page") and SideBoard.page == 1, "PAGE shows the second ten")
	await TestLib.frames(host, 3)
	var found := 0
	for bt: Dictionary in hud.buttons:
		var sid := String(bt["id"])
		if sid.begins_with("side_") and NEW.has(StringName(sid.substr(5))):
			found += 1
			TestLib.check((bt["rect"] as Rect2).size.y >= 1.0, "%s button has a rect" % sid)
	TestLib.check(found == 10, "page 2 lays out the ten new jobs (%d)" % found)
	TestLib.check(hud.press_button(&"side_demolition") and sm.active and sm.id == &"demolition", "START on page 2 begins the job")
	TestLib.check(Game.state == &"play", "the job runs in the live city")
	sm.abort("TEST")
	SideBoard.page = 0


func _save() -> void:
	var done := prog.side_done.duplicate()
	TestLib.check(prog.save_file(), "save")
	prog.side_done.clear()
	prog.side_best.clear()
	TestLib.check(prog.load_file() and prog.side_done == done and prog.side_done.has(&"anomaly"), "new tallies survive a save round trip")
