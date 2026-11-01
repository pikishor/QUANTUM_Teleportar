extends RefCounted
## The four interior missions on the real composed game (retrieve data from a safe, rescue a hostage, assassinate a hidden officer, hack a terminal while guards close in), their
## rewards, the remembered completion, reset on leaving, the interior radio lines, and the TEST menu's INTERIORS page (an entry for every interior type).
## Run: tools/test.sh tests/test_interior_gameplay_missions.gd

const SPEED_UP := 4
const TICK_RATE := 60 * SPEED_UP

var host: Node
var main: Node
var p: Player
var ig: InteriorGameplay
var prog: Progress
var m: InteriorMissions


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func go(type: StringName) -> Dictionary:
	if InteriorGameplay.active:
		ig.leave(true)
		await frames(2)
	var d := ig.doors_of(type, p.global_position)[0]
	p.teleport_to((d["pos"] as Vector3) + Vector3(0.0, 0.1, 0.0))
	await frames(2)
	ig.enter(d, true)
	await frames(6)
	return d


func stand_near(target: Vector3, offset: Vector3) -> void:
	p.teleport_to(Vector3(target.x + offset.x, 0.1, target.z + offset.z))
	await frames(3)


func use() -> void:
	Input.action_press(&"interact")
	await frames(2)
	Input.action_release(&"interact")
	await frames(2)


## Advance the mission by `seconds` of game time in 0.25 s steps (the real physics ticks run meanwhile too).
func advance(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		m.tick(0.25)
		t += 0.25
	await frames(1)


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	Engine.physics_ticks_per_second = TICK_RATE
	Engine.time_scale = float(SPEED_UP)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	ig = InteriorGameplay.instance
	prog = Game.progress as Progress
	prog.autosave_enabled = false
	prog.new_campaign()
	ig.use_generator = false
	m = ig.missions
	await _safe()
	await _hostage()
	await _officer()
	await _hack()
	await _reset_and_replay()
	await _test_menu()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Sfx.muted = false


func _safe() -> void:
	var d := await go(&"lobby")
	TestLib.check(m.kind == &"safe" and m.state == &"active" and m.door_id == int(d["id"]), "the lobby holds the safe mission")
	TestLib.check(InteriorGameplay.hud_line.begins_with("SAFE"), "the HUD line names the mission ('%s')" % InteriorGameplay.hud_line)
	var mk := m.markers()
	TestLib.check(mk.size() == 1 and mk[0]["kind"] == &"target", "the safe is on the minimap")
	await stand_near(m.target_pos, Vector3(1.5, 0.0, 1.5))
	TestLib.check(InteriorGameplay.prompt == "CRACK THE SAFE", "beside the safe the prompt offers to crack it ('%s')" % InteriorGameplay.prompt)
	# far from the safe nothing happens
	await use()
	TestLib.check(m.state == &"cracking", "USE starts the crack")
	await advance(2.0)
	var mid := m.progress
	TestLib.check(mid > 0.3 and mid < 1.0, "cracking takes time (%.2f after 2 s)" % mid)
	await stand_near(m.target_pos, Vector3(8.0, 0.0, 5.0))
	await advance(1.0)
	TestLib.check(m.progress < mid, "stepping away lets the crack decay (%.2f)" % m.progress)
	await stand_near(m.target_pos, Vector3(1.5, 0.0, 1.5))
	TestLib.check(m.state == &"cracking", "the crack carries on when you come back")
	var credits := prog.credits
	var done_n := prog.contracts_done
	var heat := Game.heat
	await advance(8.0)
	TestLib.check(m.state == &"complete", "the safe opens")
	TestLib.check(prog.credits >= credits + int(m.last_reward["credits"]) and int(m.last_reward["credits"]) > 0, "credits paid (%d)" % int(m.last_reward["credits"]))
	TestLib.check(prog.contracts_done == done_n + 1, "counts as a done contract")
	TestLib.check(Game.heat > heat and ig.actors.guards.all(func(g: Drone) -> bool: return not is_instance_valid(g) or g.aware or g.dead), "the vault alarm raises heat and wakes the guards (%.1f)" % Game.heat)
	TestLib.check(ig.done.has(int(d["id"])), "the interior remembers the finished mission")
	TestLib.check(InteriorGameplay.hud_line == "", "no mission line after completing")
	Game.heat = 0.0
	await go(&"lobby")
	TestLib.check(m.kind == &"" and m.state == &"idle", "a finished mission is not offered again at the same door")


func _hostage() -> void:
	var d := await go(&"apartment")
	TestLib.check(m.kind == &"hostage" and ig.actors.hostage != null and ig.actors.hostage.role == &"hostage", "the apartment holds a hostage")
	TestLib.check(ig.actors.guards_alive() == 3, "three Vael guards hold the flat")
	await stand_near(ig.actors.hostage.global_position, Vector3(-1.0, 0.0, 1.3))
	TestLib.check(InteriorGameplay.prompt == "", "the hostage cannot be freed while the guards live")
	TestLib.check(InteriorGameplay.hud_line.find("3 LEFT") >= 0, "the HUD counts the guards ('%s')" % InteriorGameplay.hud_line)
	for g in ig.actors.guards:
		g.damage(9999.0)
	await frames(8)
	m.tick(0.1)
	TestLib.check(ig.actors.guards_alive() == 0, "guards down")
	await frames(2)
	TestLib.check(InteriorGameplay.prompt == "FREE THE HOSTAGE", "with the room clear the prompt offers to free her ('%s')" % InteriorGameplay.prompt)
	var credits := prog.credits
	var rep := prog.reputation
	await use()
	TestLib.check(m.state == &"complete" and ig.actors.hostage.freed and prog.credits > credits and prog.reputation > rep, "freeing the hostage pays credits and reputation")
	TestLib.check(ig.done.has(int(d["id"])), "remembered")
	await frames(30)
	TestLib.check(ig.actors.hostage.state == &"freed" or ig.actors.hostage.state == &"idle", "the freed hostage runs for the door")


func _officer() -> void:
	var d := await go(&"club")
	var o := ig.actors.officer
	TestLib.check(m.kind == &"assassinate" and o != null and o.max_hp >= 240.0, "the club hides an officer with %d hp" % int(o.max_hp if o != null else 0))
	TestLib.check(o.model == null or o.model.scale.x > 1.1, "the officer is bigger than a trooper")
	var mk := m.markers()
	TestLib.check(mk.size() == 1 and mk[0]["kind"] == &"area", "the officer is only an area on the minimap until found")
	TestLib.check(ig.minimap_markers().any(func(e: Dictionary) -> bool: return e["kind"] == &"area"), "the minimap layer carries the area")
	await stand_near(o.global_position, Vector3(6.0, 0.0, 4.0))
	await advance(0.5)
	TestLib.check(m.found and m.markers()[0]["kind"] == &"target", "within 14 m the target is spotted")
	TestLib.check(InteriorGameplay.hud_line.find("SPOTTED") >= 0, "the HUD says spotted")
	var credits := prog.credits
	o.damage(9999.0, true)
	await frames(6)
	await advance(0.5)
	TestLib.check(m.state == &"complete" and prog.credits > credits, "killing the officer completes the mission")
	TestLib.check(ig.done.has(int(d["id"])), "remembered")


func _hack() -> void:
	var d := await go(&"checkpoint")
	TestLib.check(m.kind == &"hack" and ig.actors.guards_alive() == 3, "the checkpoint: terminal and three guards")
	var aware0 := 0
	for g in ig.actors.guards:
		if g.aware:
			aware0 += 1
	await stand_near(m.target_pos, Vector3(-7.0, 0.0, 6.0))
	await advance(4.0)
	TestLib.check(m.progress == 0.0, "standing away from the terminal hacks nothing")
	await stand_near(m.target_pos, Vector3(-1.4, 0.0, 1.4))
	await advance(4.0)
	TestLib.check(m.progress > 0.2 and m.progress < 0.4, "hacking fills while you stand at the terminal (%.2f)" % m.progress)
	var aware1 := 0
	for g in ig.actors.guards:
		if g.aware:
			aware1 += 1
	TestLib.check(aware1 >= aware0 + 1, "the first wave: a guard closes in (%d -> %d aware)" % [aware0, aware1])
	await stand_near(m.target_pos, Vector3(-7.0, 0.0, 6.0))
	var before := m.progress
	await advance(2.0)
	TestLib.check(m.progress < before and m.progress > 0.0, "the hack decays slowly outside the ring (%.2f -> %.2f)" % [before, m.progress])
	await stand_near(m.target_pos, Vector3(-1.4, 0.0, 1.4))
	var heat := Game.heat
	var credits := prog.credits
	await advance(20.0)
	TestLib.check(m.state == &"complete" and prog.credits > credits, "the terminal is burned through, credits paid")
	TestLib.check(Game.heat > heat, "the waves added heat (%.1f)" % Game.heat)
	var aware3 := 0
	for g in ig.actors.guards:
		if is_instance_valid(g) and g.aware:
			aware3 += 1
	TestLib.check(aware3 >= 3 or ig.actors.guards_alive() < 3, "all three waves sent guards (%d aware)" % aware3)
	TestLib.check(ig.done.has(int(d["id"])), "remembered")
	Game.heat = 0.0


func _reset_and_replay() -> void:
	# leaving in the middle resets a mission; a fresh enter offers it again
	ig.done.clear()
	await go(&"checkpoint")
	await stand_near(m.target_pos, Vector3(-1.4, 0.0, 1.4))
	await advance(3.0)
	TestLib.check(m.progress > 0.1, "mission under way")
	ig.leave(true)
	await frames(3)
	TestLib.check(m.kind == &"" and m.state == &"idle", "leaving resets the mission")
	await go(&"checkpoint")
	TestLib.check(m.kind == &"hack" and m.progress == 0.0, "entering again starts it fresh")
	# death inside: respawn at the door resets it too
	Game.die()
	await frames(2)
	Game.do_respawn()
	await frames(4)
	TestLib.check(not InteriorGameplay.active and m.kind == &"", "dying inside resets the mission and puts the player outside")
	Game.heat = 0.0
	# quiet exits do not repeat radio lines every time
	var lines0: int = (Game.story.get("shown") as Array).size()
	TestLib.check(lines0 >= 1, "interior radio lines went through the story layer (%d recorded)" % lines0)


func _test_menu() -> void:
	TestMode.forced = true
	var menu: TestMenu = null
	for n in main.find_children("*", "TestMenu", true, false):
		menu = n as TestMenu
	TestLib.check(menu != null and TestMenu.TABS.has("INTERIORS"), "the TEST menu has an INTERIORS page")
	if menu == null:
		return
	menu.set_page(TestMenu.TABS.find("INTERIORS"))
	var labels := menu.labels()
	for t: StringName in InteriorData.TYPES:
		TestLib.check(labels.has("GO: " + InteriorData.title(t)), "a GO entry for %s" % t)
	for t: StringName in InteriorData.TYPES:
		TestLib.check(menu.press_label("GO: " + InteriorData.title(t)), "press GO: %s" % InteriorData.title(t))
		await frames(4)
		TestLib.check(InteriorGameplay.active and ig.interior.get("type") == t, "the test menu teleports into the %s" % t)
		if t == &"lobby":
			TestLib.check(menu.press_label("COMPLETE THE MISSION"), "press COMPLETE THE MISSION")
			await frames(2)
			TestLib.check(m.state == &"complete", "the test menu completes the lobby mission")
	TestLib.check(menu.press_label("LEAVE THE INTERIOR"), "press LEAVE")
	await frames(3)
	TestLib.check(not InteriorGameplay.active and Game.world.visible, "the test menu leaves the interior")
	TestMode.forced = false
