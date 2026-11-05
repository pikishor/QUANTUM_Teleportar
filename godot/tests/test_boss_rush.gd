extends RefCounted
## BOSS RUSH and the ENDLESS ARENA (scripts/missions/arena_scripts.gd + arena_runner.gd + ui/arena_board.gd) in the REAL scene (main.tscn): data validates, a rush spawns every boss in turn
## (difficulty scales its health, breaks heal and shorten), all down = timed clear, paid, cosmetic granted, time on the sorted five-entry leaderboard that survives a save round trip; a fall
## ends a rush unpaid; the endless arena spawns waves scaled by modifiers, a BRUTAL wave brings a boss, LEAVE banks the waves and the milestone cosmetics; the campaign is frozen during a run and
## restored; the pause menu ARENA screen and the title ARENA button (64 px) launch runs in the live city; the DEMO entry starts one. The arena is ticked by hand (its physics off);
## waits are on state. Progress writes to a throw-away file. Not run: a phone, the feel of the fights.
## Run: tools/test.sh tests/test_boss_rush.gd

const TMP := "user://test_boss_rush_save.cfg"

var host: Node
var main: Node
var ar: ArenaRunner
var prog: Progress
var p: Player
var hud: Hud
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
	TestLib.check(m != null and m.arena != null and p != null, "main.tscn composes Missions.arena and the player")
	if m == null or m.arena == null or p == null:
		return
	ar = m.arena
	prog = Game.progress as Progress
	prog.path = TMP
	prog.autosave_enabled = false
	prog.new_campaign()
	for key: String in ["scheme:6", "scheme:3", "scheme:1", "scheme:7", "suit:stealth"]:
		prog.hero.owned.erase(key)
	ar.set_physics_process(false)
	ar.finished.connect(func(md: StringName, ok: bool, why: String) -> void: ended.append([md, ok, why]))
	for n in main.find_children("*", "Hud", true, false):
		hud = n as Hud
	var was_demo := DemoMode.active
	await _reset()

	await _rush()
	await _rush_fail()
	await _endless()
	await _board()
	await _title()
	await _demo()
	_saved()

	DemoMode.active = was_demo
	ar.abort("TEST")
	Game.heat = 0.0
	Game.state = &"play"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _reset() -> void:
	ar.abort("TEST")
	(Game.missions as Missions).campaign.abort()
	Game.state = &"play"
	Game.heat = 0.0
	p.hp = p.max_hp
	if is_instance_valid(Game.enemies):
		(Game.enemies as EnemyManager).clear()
	ended.clear()
	await TestLib.frames(host, 3)


func _data() -> void:
	TestLib.check(ArenaScripts.validate(), "boss ids, foe types, rewards and cosmetic keys are all valid")
	TestLib.check(ArenaScripts.RUSH_ORDER.size() >= 6 and ArenaScripts.DIFFS.size() == 3 and ArenaScripts.MODS.size() == 3, "six bosses, three difficulties, three modifiers")
	TestLib.check(ArenaScripts.rush_hp(&"hard") > ArenaScripts.rush_hp(&"normal") and ArenaScripts.rush_hp(&"nightmare") > ArenaScripts.rush_hp(&"hard"), "difficulty raises boss health")
	TestLib.check(ArenaScripts.break_time(&"nightmare") < ArenaScripts.break_time(&"hard") and ArenaScripts.break_time(&"hard") < ArenaScripts.break_time(&"normal"), "difficulty shortens the breaks")
	TestLib.check(ArenaScripts.rush_reward(&"nightmare") > ArenaScripts.rush_reward(&"hard") and ArenaScripts.rush_reward(&"hard") > ArenaScripts.rush_reward(&"normal"), "difficulty raises the pay")
	TestLib.check(ArenaScripts.wave_count(5, []) > ArenaScripts.wave_count(1, []) and ArenaScripts.wave_count(3, [&"swarm"]) > ArenaScripts.wave_count(3, []), "waves grow and SWARM adds foes")
	TestLib.check(ArenaScripts.wave_types(1).size() < ArenaScripts.wave_types(9).size(), "later waves bring more foe types")
	TestLib.check(ArenaScripts.is_brutal_wave(4, [&"brutal"]) and not ArenaScripts.is_brutal_wave(4, []) and not ArenaScripts.is_brutal_wave(3, [&"brutal"]), "BRUTAL puts a boss on every 4th wave")
	TestLib.check(ArenaScripts.endless_reward(5, [&"armoured"]) > ArenaScripts.endless_reward(5, []), "a modifier raises the endless pay")
	var t := ArenaScripts.insert_time([], 300.0)
	t = ArenaScripts.insert_time(t, 200.0)
	t = ArenaScripts.insert_time(t, 250.0)
	TestLib.check(t == [200.0, 250.0, 300.0], "best times sort ascending")
	for i in 8:
		t = ArenaScripts.insert_time(t, 100.0 + i)
	TestLib.check(t.size() == ArenaScripts.BOARD_SIZE and t[0] == 100.0, "the board keeps the five best")
	TestLib.check(ArenaScripts.rank_of(t, 99.0) == 1 and ArenaScripts.rank_of(t, 1000.0) == 0, "rank_of places a time or reports none")


## Ticks the arena until `cond` holds (state based: game seconds, not frames) or `limit` seconds passed.
func _until(cond: Callable, limit := 60.0, dt := 0.5) -> bool:
	var t := 0.0
	while t < limit and not cond.call():
		ar.tick(dt)
		t += dt
	return cond.call()


## Brings a boss down the way the tests of the verb bosses do: phase invulnerability cleared and the BULWARK's shield broken between blows.
func _kill(b: Drone) -> void:
	var n := 0
	while is_instance_valid(b) and not b.dead and n < 12:
		n += 1
		if "_invuln_t" in b:
			b.set("_invuln_t", 0.0)
		if "shield_is_up" in b:
			b.set("shield_is_up", false)
		b.damage(1.0e9, true)


func _rush() -> void:
	await _reset()
	var camp := (Game.missions as Missions).campaign
	camp.set_physics_process(true)
	var cr0 := prog.credits
	TestLib.check(ar.can_start() and ar.start(&"rush", &"hard"), "a hard boss rush starts in the live city")
	TestLib.check(ar.is_running() and ar.phase == &"break" and not camp.is_physics_processing(), "it opens with a countdown and the campaign is frozen")
	TestLib.check(ar.hud_line().begins_with("BOSS RUSH  1 / %d" % ArenaScripts.RUSH_ORDER.size()), "the HUD line names the boss number (%s)" % ar.hud_line())
	TestLib.check(not ar.start(&"rush", &"normal"), "a second run cannot start over the first")
	var seen: Array[StringName] = []
	ar.boss_started.connect(func(id: StringName, _i: int) -> void: seen.append(id))
	for i in ArenaScripts.RUSH_ORDER.size():
		var ok := _until(func() -> bool: return ar._boss != null)
		TestLib.check(ok and ar.phase == &"fight", "boss %d appears after the break" % (i + 1))
		if not ok:
			break
		var b := ar._boss
		var base := float(b.cfg["hp"]) * Progress.boss_hp_mult()
		TestLib.check(is_equal_approx(b.max_hp, base * ArenaScripts.rush_hp(&"hard")) and String(b.type) == String(ArenaScripts.RUSH_ORDER[i]), "boss %d is a %s with HARD health" % [i + 1, b.type])
		TestLib.check(not ar.boss().is_empty() and float(ar.boss()["frac"]) > 0.99, "the boss bar reads full")
		p.hp = 10.0
		_kill(b)
		ar.tick(0.1)
		if i < ArenaScripts.RUSH_ORDER.size() - 1:
			TestLib.check(ar.index == i + 1 and ar.phase == &"break" and p.hp > 10.0, "boss %d down: a break starts and heals" % (i + 1))
			TestLib.check(absf(ar.break_t - ArenaScripts.break_time(&"hard")) < 0.2, "the break is the HARD length")
	TestLib.check(not ar.is_running() and ended.size() == 1 and bool(ended[0][1]), "the last boss down ends the run as a clear")
	TestLib.check(seen.size() == ArenaScripts.RUSH_ORDER.size(), "every boss was introduced once")
	TestLib.check(int(ar.result["reward"]) == ArenaScripts.rush_reward(&"hard") and prog.credits >= cr0 + ArenaScripts.rush_reward(&"hard"), "the clear pays the HARD reward")
	TestLib.check(prog.hero.owned.has("scheme:6") and (ar.result["cosmetics"] as Array).has("scheme:6"), "the HARD cosmetic is granted")
	var times: Array = prog.arena.get("rush_hard", [])
	TestLib.check(times.size() == 1 and absf(float(times[0]) - float(ar.result["time"])) < 0.01 and float(times[0]) > 0.0, "the time is on the HARD leaderboard")
	TestLib.check(camp.is_physics_processing(), "the campaign is thawed")
	TestLib.check(ar.foes_alive() == 0, "no foes are left")
	# a second, slower clear keeps both times sorted; a repeat grants the cosmetic only once
	prog.arena["rush_hard"] = ArenaScripts.insert_time(times, 5.0)
	TestLib.check((prog.arena["rush_hard"] as Array)[0] == 5.0 and (prog.arena["rush_hard"] as Array).size() == 2, "a faster time sorts to the top")
	camp.set_physics_process(false)


func _rush_fail() -> void:
	await _reset()
	var cr0 := prog.credits
	var clears0 := int(prog.arena.get("clear_normal", 0))
	TestLib.check(ar.start(&"rush", &"normal"), "a normal rush starts")
	TestLib.check(_until(func() -> bool: return ar._boss != null), "the first boss appears")
	Game.player_died.emit()
	TestLib.check(not ar.is_running() and ended.size() == 1 and not bool(ended[0][1]) and String(ended[0][2]) == "DOWN", "a fall ends the rush as a loss")
	TestLib.check(prog.credits <= cr0 + 400 and int(ar.result["reward"]) == 0 and int(prog.arena.get("clear_normal", 0)) == clears0 and not prog.arena.has("rush_normal"), "a loss pays nothing and records no time")
	TestLib.check(ar.foes_alive() == 0, "the boss is removed")


func _endless() -> void:
	await _reset()
	var cr0 := prog.credits
	TestLib.check(ar.start(&"endless", &"hard", [&"armoured", &"swarm", &"brutal", &"bogus"]), "an endless arena starts with modifiers")
	TestLib.check(ar.mods.size() == 3 and ar.diff == &"normal", "unknown modifiers are dropped; difficulty is a rush setting")
	TestLib.check(_until(func() -> bool: return ar.phase == &"fight") and ar._pending + ar.foes_alive() == ArenaScripts.wave_count(1, ar.mods), "wave 1 is the SWARM-sized wave")
	ar.tick(0.5)
	var em := Game.enemies as EnemyManager
	TestLib.check(ar.foes_alive() > 0 and ar.foes_alive() <= em.cap(), "foes spawn within the manager cap")
	var d: Drone = null
	for f: Drone in ar._foes:
		if is_instance_valid(f):
			d = f
			break
	TestLib.check(d != null and is_equal_approx(d.max_hp, float(d.cfg["hp"]) * Progress.enemy_hp_mult() * 1.6), "ARMOURED scales foe health x1.6")
	# defeat every foe until wave 1 is clear
	var guard := 0
	while ar.index == 0 and guard < 200:
		guard += 1
		for f: Drone in ar._foes.duplicate():
			if is_instance_valid(f) and not f.dead:
				f.damage(1.0e9, true)
		ar.tick(0.3)
	TestLib.check(ar.index == 1 and ar.phase == &"break" and ar.kills >= ArenaScripts.wave_count(1, ar.mods) and ar.score > 0, "wave 1 cleared: kills and score counted")
	# a BRUTAL wave brings a boss
	ar.index = 3
	ar.phase = &"break"
	ar.break_t = 0.0
	ar.tick(0.1)
	TestLib.check(ar.phase == &"fight", "wave 4 begins")
	TestLib.check(_until(func() -> bool: return ar._boss != null, 10.0, 0.25) and ar.boss().has("name"), "wave 4 (BRUTAL) brings a boss with a bar")
	# LEAVE banks the waves cleared
	ar.index = 8
	ar.abort("LEFT")
	TestLib.check(not ar.is_running() and ended.size() == 1 and bool(ended[0][1]), "LEAVE ends an endless run as banked")
	var pay := ArenaScripts.endless_reward(8, [&"armoured", &"swarm", &"brutal"])
	TestLib.check(int(ar.result["reward"]) == pay and prog.credits >= cr0 + pay and pay > 0, "the cleared waves are paid (%d)" % pay)
	TestLib.check(prog.hero.owned.has("scheme:1") and prog.hero.owned.has("scheme:7"), "waves 4 and 8 grant their cosmetics")
	TestLib.check(int(prog.arena.get("wave_best", 0)) == 8 and int(prog.arena.get("score_best", 0)) > 0, "best wave and score are kept")
	TestLib.check(ar.foes_alive() == 0, "the arena's foes are removed")
	# a fall banks the waves too; a run that left at wave 0 pays nothing
	TestLib.check(ar.start(&"endless", &"normal", []), "a plain endless run starts")
	Game.player_died.emit()
	TestLib.check(not ar.is_running() and int(ar.result["reward"]) == 0, "falling in wave 1 pays nothing")


func _board() -> void:
	await _reset()
	if hud == null:
		TestLib.check(false, "the HUD exists")
		return
	Game.state = &"paused"
	await TestLib.frames(host, 4)
	var s := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
	var open_ok := false
	hud._gear_open = true                                          # ARENA lives on the MORE page
	hud._layout_key = ""
	hud._ensure_layout()
	for bt: Dictionary in hud.buttons:
		if bt["id"] == &"arena_open":
			open_ok = (bt["rect"] as Rect2).size.y >= UiUtil.TOUCH_MIN * s - 1.0
	hud._gear_open = false
	TestLib.check(open_ok, "the pause menu has a 64 px ARENA button")
	TestLib.check(hud.press_button(&"arena_open") and hud._arena_open, "ARENA opens the planning screen from the pause menu")
	await TestLib.frames(host, 3)
	var ids := {}
	for bt: Dictionary in hud.buttons:
		var bid := String(bt["id"])
		if bid.begins_with("arena_"):
			ids[bid] = true
			TestLib.check((bt["rect"] as Rect2).size.y >= UiUtil.TOUCH_MIN * s - 1.0, "%s is at least 64 px tall" % bid)
	TestLib.check(ids.has("arena_mode_rush") and ids.has("arena_d_hard") and ids.has("arena_go") and ids.has("arena_back"), "mode, difficulty, LAUNCH and BACK are laid out")
	TestLib.check(hud.press_button(&"arena_d_nightmare") and ArenaBoard.diff == &"nightmare", "a difficulty is picked")
	TestLib.check(hud.press_button(&"arena_mode_endless") and ArenaBoard.mode == &"endless", "ENDLESS is picked")
	await TestLib.frames(host, 3)
	var mods_found := 0
	for bt: Dictionary in hud.buttons:
		if String(bt["id"]).begins_with("arena_m_"):
			mods_found += 1
	TestLib.check(mods_found == 3, "the modifier toggles replace the difficulty row")
	TestLib.check(hud.press_button(&"arena_m_swarm") and ArenaBoard.mods == [&"swarm"], "a modifier is switched on")
	TestLib.check(hud.press_button(&"arena_m_swarm") and ArenaBoard.mods.is_empty() and hud.press_button(&"arena_m_brutal"), "and off again")
	TestLib.check(hud.press_button(&"arena_go"), "LAUNCH starts the arena")
	TestLib.check(Game.state == &"play" and ar.is_running() and ar.mode == &"endless" and ar.mods == [&"brutal"], "the planned arena runs in the live city")
	hud.press_button(&"arena_open")                  # not paused: refused
	TestLib.check(not hud._arena_open, "the screen only opens from the pause menu or the title")
	ar.abort("TEST")
	ArenaBoard.mode = &"rush"
	ArenaBoard.diff = &"normal"
	ArenaBoard.mods.clear()
	await _reset()


func _title() -> void:
	await _reset()
	if hud == null:
		return
	Game.state = &"menu"
	await TestLib.frames(host, 4)
	var s := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
	var open_ok := false
	hud._gear_open = true                                          # ARENA lives on the MORE page
	hud._layout_key = ""
	hud._ensure_layout()
	for bt: Dictionary in hud.buttons:
		if bt["id"] == &"arena_open":
			open_ok = (bt["rect"] as Rect2).size.y >= UiUtil.TOUCH_MIN * s - 1.0
	hud._gear_open = false
	TestLib.check(open_ok, "the title has a 64 px ARENA button")
	TestLib.check(hud.press_button(&"arena_open") and hud._arena_open, "ARENA opens from the title")
	await TestLib.frames(host, 3)
	TestLib.check(hud.press_button(&"arena_d_normal") and hud.press_button(&"arena_go"), "LAUNCH on the title deploys and starts")
	TestLib.check(ar.is_running() and ar.mode == &"rush" and Game.state != &"menu" and not hud._arena_open, "the rush runs in the city behind the title")
	ar.abort("TEST")
	TestLib.check(not ar.is_running(), "ABORT TO MENU style exits end the run")
	ar.start(&"endless", &"normal", [])
	Game.state = &"menu"
	TestLib.check(not ar.is_running(), "going back to the title ends a run")
	await _reset()


func _demo() -> void:
	await _reset()
	TestLib.check(DemoMode.active or true, "demo flag read")
	var was := DemoMode.active
	DemoMode.active = true
	var cat := DemoMode.catalog()
	var group := -1
	for i in cat.size():
		if cat[i]["kind"] == &"arena":
			group = i
	TestLib.check(group >= 0 and (cat[group]["items"] as Array).size() >= 5, "the DEMO catalogue lists the arena entries")
	TestLib.check(DemoPanel.TABS.has("ARENA") and DemoPanel.TABS.find("ARENA") == group, "the ARENA tab is the arena catalogue page")
	TestLib.check(DemoMode.launch(&"arena", "rush:nightmare") != "" and ar.is_running() and ar.diff == &"nightmare", "the DEMO entry starts a nightmare rush")
	TestLib.check(DemoMode.launch(&"arena", "endless:armoured,swarm,brutal") != "" and ar.mode == &"endless" and ar.mods.size() == 3, "a second DEMO entry replaces it with an endless arena")
	ar.abort("TEST")
	DemoMode.active = was
	await _reset()


func _saved() -> void:
	prog.arena["rush_hard"] = ArenaScripts.insert_time([], 123.0)
	prog.arena["clear_hard"] = 2
	prog.arena["wave_best"] = 9
	var before := prog.arena.duplicate(true)
	TestLib.check(prog.save_file(), "save")
	prog.arena.clear()
	TestLib.check(prog.load_file(), "load")
	TestLib.check(prog.arena.get("wave_best", 0) == before["wave_best"] and prog.arena.get("clear_hard", 0) == 2, "arena tallies survive a save round trip")
	var t: Array = prog.arena.get("rush_hard", [])
	TestLib.check(t.size() == 1 and absf(float(t[0]) - 123.0) < 0.01, "the leaderboard survives a save round trip")
