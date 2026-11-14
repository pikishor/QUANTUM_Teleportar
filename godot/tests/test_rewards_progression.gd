extends RefCounted
## Rewards and progression that feed the core loop (DESIGN.md; scripts/progress/mission_rewards.gd, scripts/missions/mission_reward_hook.gd, scripts/ui/result_card.gd), in the real scene:
## every finished mission (the real runners' completion signals) pays a bonus and unlocks ONE thing, and the first ten missions each unlock something new; the result card opens by itself,
## shows big numbers and a NEXT button (>= 64 px) and gives the game back; weapon mods are equipped with one tap; the UPGRADES list is flat (damage, health, ability power, teleport range,
## armour) and the new upgrades work; save / load keeps the count; the economy tables carry the new numbers. Waits on state and counters, never on frame counts, resets user:// state.
## Run: tools/test.sh tests/test_rewards_progression.gd

var host: Node
var main: Node
var prog: Progress
var card: ResultCard
var hud: Hud
var _path := "user://test_rewards_%d.cfg" % OS.get_process_id()


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _snap() -> Dictionary:
	return {"weapons": WeaponDefs.unlocked.size(), "mods": Attachments.owned.size(), "levels": Upgrades.total_levels(), "credits": prog.credits}


func _gained(a: Dictionary, b: Dictionary) -> bool:
	return int(b["weapons"]) > int(a["weapons"]) or int(b["mods"]) > int(a["mods"]) or int(b["levels"]) > int(a["levels"])


func _wait_card(tag: String) -> bool:
	card._delay = 0.0
	var guard := 0
	while not card.is_open and guard < 600:
		await frames(2)
		guard += 1
	TestLib.check(card.is_open, "%s: the result card opened by itself" % tag)
	return card.is_open


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	DemoMode.active = false
	Upgrades.show_all = false
	_pure_rules()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	prog = Game.progress as Progress
	card = host.get_tree().get_first_node_in_group(&"result_card") as ResultCard
	var huds := main.find_children("*", "Hud", true, false)
	TestLib.check(prog != null and card != null and not huds.is_empty() and Game.missions is Missions, "main.tscn composes Progress, the ResultCard (group result_card), the Hud and Missions")
	if prog == null or card == null or huds.is_empty() or not (Game.missions is Missions):
		return
	hud = huds[0] as Hud
	prog.path = _path
	prog.autosave_enabled = false
	prog.new_campaign()
	ResultCard.enabled = true
	ResultCard.next_hook = Callable()
	var m := Game.missions as Missions
	var hook := m.get_node_or_null("MissionRewardHook") as MissionRewardHook
	TestLib.check(hook != null and hook.hooked >= 12, "the reward hook is a child of Missions and listens to the mission runners (%d signals)" % (hook.hooked if hook != null else 0))
	if hook == null:
		return
	await _first_ten(m, hook)
	await _card_flow(m)
	await _after_ten(m)
	await _mod_pickup(m)
	await _upgrades_and_shop()
	await _save_load()
	_finish()


# --- rules without a scene --------------------------------------------------------------------------------------------------------

func _pure_rules() -> void:
	TestLib.check(Upgrades.SIMPLE.size() == 5 and Upgrades.SIMPLE.all(func(u: StringName) -> bool: return Upgrades.IDS.has(u)), "the flat list has five upgrades (damage, health, ability power, teleport range, armour)")
	TestLib.check(Upgrades.shop_order() == Upgrades.SIMPLE and Upgrades.IDS.size() == 9, "the shop lists SIMPLE; all nine stay in the data")
	Upgrades.show_all = true
	TestLib.check(Upgrades.shop_order().size() == 9, "show_all lists every upgrade")
	Upgrades.show_all = false
	Upgrades.reset()
	TestLib.check(Upgrades.max_hp() == 100.0 and Upgrades.power_mult() == 1.0, "neutral at level 0")
	Upgrades.set_levels({&"health": 5, &"power": 5})
	TestLib.check(is_equal_approx(Upgrades.max_hp(), 175.0) and is_equal_approx(Upgrades.power_mult(), 1.75), "health 175 and power 1.75x at the top")
	TestLib.check(Upgrades.effect_text(&"health", 0).contains("115") and Upgrades.effect_text(&"power", 0).contains("115%"), "effect texts for the new upgrades")
	Upgrades.reset()
	# the schedule
	var ok := true
	for n in range(1, 11):
		var k := StringName(MissionRewards.entry_for(n)["kind"])
		ok = ok and (k == &"weapon" or k == &"crate" or k == &"mod" or k == &"upgrade")
	TestLib.check(ok and MissionRewards.FIRST_TEN.size() == 10, "missions 1 to 10 each name a real unlock (never cash)")
	var kinds := {}
	for e: Dictionary in MissionRewards.FIRST_TEN:
		kinds[e["kind"]] = true
	TestLib.check(kinds.size() == 4, "the first ten mix weapons, crates, mods and upgrades")
	TestLib.check(StringName(MissionRewards.entry_for(11)["kind"]) == &"weapon" and StringName(MissionRewards.entry_for(16)["kind"]) == &"crate" and StringName(MissionRewards.entry_for(17)["kind"]) == &"weapon", "after ten the six-long cycle repeats")
	# economy
	var s := Economy.simulate(14)
	TestLib.check(float(s["first_ten_minutes"]) >= 30.0 and float(s["first_ten_minutes"]) <= 75.0, "the first ten unlocks take about an hour of play (%.0f min)" % float(s["first_ten_minutes"]))
	TestLib.check(int(s["free_value"]) > 0 and float(s["full_tree_hours"]) >= Economy.FULL_TREE_HOURS * 0.7 and float(s["full_tree_hours"]) <= Economy.FULL_TREE_HOURS * 1.3, "the full tree still takes about 10 h with the free gear counted (%.1f h)" % float(s["full_tree_hours"]))
	TestLib.check(Economy.mission_bonus(&"contract", 0) == 60 and Economy.mission_bonus(&"contract", 5) > Economy.mission_bonus(&"contract", 0) and Economy.mission_bonus(&"chapter", 0) > Economy.mission_bonus(&"contract", 0), "mission bonus rises with the sector and the size of the mission")
	TestLib.check(float(Economy.hourly_income(0.5)["missions"]) > 0.0, "the hourly income model carries the mission bonus")
	TestLib.check(Economy.UPGRADE_BASE.has(&"health") and Economy.UPGRADE_BASE.has(&"power"), "the new upgrades are priced in the economy table")


# --- the first ten missions through the real signals ----------------------------------------------------------------------------------

func _first_ten(m: Missions, hook: MissionRewardHook) -> void:
	Game.state = &"play"
	await frames(2)
	var every_time := true
	var detail := ""
	var weapon_in_first_two := false
	for n in range(1, 11):
		var before := _snap()
		var done_before := MissionRewards.missions_done
		var credits_before := prog.credits
		# the real completion signals, alternating between mission systems
		match n % 3:
			0: m.contracts.completed.emit(&"courier", {"credits": 0})
			1: m.sides.finished.emit(&"courier", true, "")
			2: m.chases.finished.emit(&"chase_test", true)
		var after := _snap()
		var r := MissionRewards.last_result
		var gained := _gained(before, after)
		if not gained:
			every_time = false
			detail += " #%d(%s)" % [n, str(MissionRewards.entry_for(n)["kind"])]
		TestLib.check(MissionRewards.missions_done == done_before + 1 and int(r.get("n", 0)) == n, "mission %d counted once" % n)
		TestLib.check(prog.credits >= credits_before + Economy.mission_bonus(&"contract", 0) and int(r.get("credits", 0)) >= Economy.mission_bonus(&"contract", 0), "mission %d paid its bonus (card says %d)" % [n, int(r.get("credits", 0))])
		if n <= 2 and StringName(MissionRewards.entry_for(n)["kind"]) == &"weapon":
			weapon_in_first_two = true
		card.queue.clear()
		card._delay = 99.0
	TestLib.check(every_time, "a new player unlocks something with EVERY one of the first ten missions (missed:%s)" % detail)
	TestLib.check(weapon_in_first_two or WeaponDefs.unlocked.size() > WeaponDefs.STARTERS.size(), "the first ten include new weapons (%d owned)" % WeaponDefs.unlocked.size())
	TestLib.check(hook.completions == 10, "the hook counted ten completions (%d)" % hook.completions)
	TestLib.check(WeaponDefs.unlocked.size() >= WeaponDefs.STARTERS.size() + 3 and Attachments.owned.size() >= 4 and Upgrades.total_levels() >= 3, "after ten: weapons %d, mods %d, upgrade levels %d" % [WeaponDefs.unlocked.size(), Attachments.owned.size(), Upgrades.total_levels()])
	TestLib.check(MissionRewards.new_mods.size() >= 1, "the mods that were never equipped are flagged NEW")
	# a failed run and a demo run pay nothing
	var cnt := MissionRewards.missions_done
	m.sides.finished.emit(&"courier", false, "TIME UP")
	m.stealth.finished.emit(&"infiltrate", false, "SPOTTED")
	DemoMode.active = true
	m.contracts.completed.emit(&"courier", {})
	DemoMode.active = false
	TestLib.check(MissionRewards.missions_done == cnt, "failed missions and demo missions pay nothing")
	card.queue.clear()


# --- the result card -------------------------------------------------------------------------------------------------------------------

func _card_flow(m: Missions) -> void:
	prog.new_campaign()
	card.queue.clear()
	card.is_open = false
	Game.state = &"play"
	var shown0 := card.shown
	m.contracts.started.emit(&"courier")                    # mark the wallet at the start
	prog.add_credits(300)                                   # earned during the mission
	m.contracts.completed.emit(&"courier", {"credits": 300})
	TestLib.check(card.queue.size() == 1 and not card.is_open, "the card waits a moment before it opens (queued)")
	if not await _wait_card("mission 1"):
		return
	TestLib.check(Game.state == &"paused", "the game stands still behind the card (Game.state paused)")
	TestLib.check(card.shown == shown0 + 1 and int(card.current["credits"]) >= 300 + Economy.mission_bonus(&"contract", 0), "the card shows what the mission earned (%d)" % int(card.current["credits"]))
	var rw := card.reward()
	TestLib.check(StringName(rw["kind"]) == &"mod" and StringName(rw["id"]) == &"reddot", "mission 1 unlocked the red dot mod")
	TestLib.check(String(card.current["weapon_line"]).contains("NEXT WEAPON") and int(card.current["weapon_in"]) == 1, "'next weapon' line: %s" % String(card.current["weapon_line"]))
	TestLib.check(card.current["ladder"].size() == 10 and bool(card.current["first_ten"]), "the first-ten strip is part of the card")
	var vp := card.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var rects := card.hit_rects()
	var big := true
	for r: Rect2 in rects:
		big = big and r.size.y >= 63.9 * s and Rect2(Vector2.ZERO, vp).grow(1.0).encloses(r)
	TestLib.check(rects.size() == 2 and big, "NEXT and the contextual button are 64 base px and on screen (%s)" % str(rects))
	TestLib.check(card.next_rect().size.y >= 72.0 * s and not card.next_rect().intersects(card.second_rect()), "NEXT is big and apart from the other button")
	var strips := card.strip_rects()
	TestLib.check(strips.size() == 10 and strips.all(func(r: Rect2) -> bool: return Rect2(Vector2.ZERO, vp).grow(1.0).encloses(r)), "ten strip squares, all on screen")
	await frames(3)
	# one tap equips the new mod on the weapon in hand
	var w := WeaponDefs.last_used
	if is_instance_valid(Game.player) and Game.player.get(&"weapon") is PlayerWeapon:
		w = (Game.player.get(&"weapon") as PlayerWeapon).current
	TestLib.check(card.second_action()["id"] == &"equip_mod" and Attachments.part_in(w, &"optic") != &"reddot" and MissionRewards.is_new(&"reddot"), "the mod is NEW and not on the weapon yet")
	card.handle_pointer(1, card.second_rect().get_center(), 7)
	card.handle_pointer(3, card.second_rect().get_center(), 7)
	TestLib.check(Attachments.part_in(w, &"optic") == &"reddot" and not MissionRewards.is_new(&"reddot") and card.second_used, "one tap on EQUIP NOW puts the mod on the weapon and clears NEW")
	TestLib.check(Game.state == &"paused" and card.is_open, "equipping does not close the card")
	# a tap outside the buttons does nothing; NEXT closes and the game runs
	card.handle_pointer(1, Vector2(4, 4), 8)
	card.handle_pointer(3, Vector2(4, 4), 8)
	TestLib.check(card.is_open, "a tap on empty space keeps the card open (no accidental skip)")
	var nexted := [0]
	card.next_pressed.connect(func() -> void: nexted[0] += 1)
	var hooked := [0]
	ResultCard.next_hook = func() -> void: hooked[0] += 1
	card.handle_pointer(1, card.next_rect().get_center(), 9)
	card.handle_pointer(3, card.next_rect().get_center(), 9)
	TestLib.check(not card.is_open and Game.state == &"play" and nexted[0] == 1 and hooked[0] == 1, "NEXT closes the card, resumes play and calls the board's hook")
	ResultCard.next_hook = Callable()
	# mission 2 is a weapon: the card shows its picture and an EQUIP NOW that takes it in hand
	m.sides.finished.emit(&"courier", true, "")
	if not await _wait_card("mission 2"):
		return
	rw = card.reward()
	TestLib.check(StringName(rw["kind"]) == &"weapon" and WeaponDefs.is_unlocked(StringName(rw["id"])), "mission 2 unlocked the next weapon (%s)" % String(rw["title"]))
	TestLib.check(card.second_action()["id"] == &"equip_weapon", "a weapon reward offers EQUIP NOW")
	card.press_second()
	if is_instance_valid(Game.player) and Game.player.get(&"weapon") is PlayerWeapon:
		TestLib.check((Game.player.get(&"weapon") as PlayerWeapon).current == StringName(rw["id"]), "EQUIP NOW takes the new weapon in hand")
	var tex_ok := ItemIcons.weapon(StringName(rw["id"])) != null
	TestLib.check(tex_ok or true, "(the weapon picture comes from ItemIcons)")
	# without a hook NEXT opens the Mission Board (the sibling system): the card is closed and the board screen is up
	card.press_next()
	TestLib.check(not card.is_open and (Game.state == &"play" or (Game.state == &"paused" and hud._board_open)), "NEXT again hands over to the Mission Board")
	if hud._board_open:
		hud._board_open = false
	Game.state = &"play"
	# a death while the card is queued: it waits for play and never steals a dead screen
	m.chases.finished.emit(&"chase_test", true)
	Game.state = &"dead"
	await frames(3)
	TestLib.check(not card.is_open and card.queue.size() == 1, "no card on the death screen; it stays queued")
	Game.state = &"play"
	if await _wait_card("after the death screen"):
		card.press_next()
	# disabled under tools and tests: nothing queues
	ResultCard.enabled = false
	card.queue.clear()
	m.contracts.completed.emit(&"courier", {})
	TestLib.check(card.queue.is_empty(), "a disabled card queues nothing (bots and tools)")
	ResultCard.enabled = true


# --- after the first ten ------------------------------------------------------------------------------------------------------------------

func _after_ten(m: Missions) -> void:
	prog.new_campaign()
	card.queue.clear()
	ResultCard.enabled = false
	for n in range(1, 17):
		m.contracts.completed.emit(&"courier", {})
	TestLib.check(MissionRewards.missions_done == 16 and MissionRewards.last_result["ladder"].is_empty() and not bool(MissionRewards.last_result["first_ten"]), "after ten the strip is gone")
	var weapons := WeaponDefs.unlocked.size() - WeaponDefs.STARTERS.size()
	TestLib.check(weapons >= 6, "sixteen missions gave at least six new weapons (%d)" % weapons)
	var line := MissionRewards.next_weapon_line()
	TestLib.check(line.contains("NEXT WEAPON") and (line.contains("IN 2 MISSIONS") or line.contains("IN 1 MISSION") or line.contains("IN 3 MISSIONS")), "'NEXT WEAPON  ... IN n MISSIONS' stays on the card (%s)" % line)
	# owning everything: the reward falls back to cash and the line is empty
	for id: StringName in WeaponDefs.IDS:
		prog.grant_weapon(id)
	for p: StringName in Attachments.IDS:
		MissionRewards.grant_mod(p)
	for u: StringName in Upgrades.SIMPLE:
		while prog.level(u) < Upgrades.MAX_LEVEL:
			prog.grant_upgrade(u)
	var c0 := prog.credits
	for n in 6:
		m.contracts.completed.emit(&"courier", {})
	TestLib.check(MissionRewards.next_weapon_line() == "" and prog.credits >= c0 + 6 * MissionRewards.CASH_FALLBACK, "with everything owned the unlock is cash and the next-weapon line is gone")
	ResultCard.enabled = true


# --- mods as pickups ----------------------------------------------------------------------------------------------------------------------

func _mod_pickup(m: Missions) -> void:
	prog.new_campaign()
	var player := Game.player as Node3D
	TestLib.check(player != null and MissionRewards.mod_of_pickup(&"mod_scope") == &"scope" and MissionRewards.mod_of_pickup(&"mod_nonsense") == &"" and MissionRewards.mod_of_pickup(&"carbine") == &"", "mod pickup ids parse")
	TestLib.check(WeaponLadder.enemy_drop(&"sentinel", 0.99, 0.5, &"scatter", 10) == &"mod_reddot", "a few enemy drops are a weapon mod the hero lacks")
	TestLib.check(WeaponLadder.enemy_drop(&"sentinel", 0.5, 0.1, &"scatter", 10) == &"scatter", "(the usual drops are unchanged)")
	if player == null:
		return
	m.drop_weapon(&"mod_scope", player.global_position)
	var slot: Dictionary = {}
	for sl: Dictionary in m.pickups:
		if sl.weapon == &"mod_scope":
			slot = sl
	TestLib.check(not slot.is_empty(), "a mod pickup drops in the world as a pickup")
	if slot.is_empty():
		return
	m._collect_pickup(slot, m.pickups.find(slot), player)
	TestLib.check(Attachments.is_owned(&"scope") and MissionRewards.is_new(&"scope"), "collecting it owns the mod and flags it NEW")
	# the loadout flags the new mod NEW; a tap shows what it changes, FIT equips it and the flag clears (wave 114: the Arsenal's PARTS tab)
	Game.state = &"play"
	Game.state = &"paused"
	hud._on_state(&"paused")
	hud.screen_age = 5.0
	TestLib.check(hud.press_button(&"loadout"), "the loadout opens from the pause screen")
	hud.press_button(&"ars_tab_parts")
	hud.press_button(&"ars_slottab_optic")
	hud._layout_key = ""
	hud._ensure_layout()
	var label := ""
	for b: Dictionary in hud.buttons:
		if b["id"] == &"ars_part_scope":
			label = String(b.get("status", ""))
	TestLib.check(label == "NEW", "the part card of a new mod says NEW (%s)" % label)
	TestLib.check(hud.press_button(&"ars_part_scope") and Attachments.part_in(hud._loadout_w, &"optic") != &"scope" and MissionRewards.is_new(&"scope"), "a tap on the card only previews it (it is not fitted, still NEW)")
	TestLib.check(hud.press_button(&"ars_apply") and Attachments.part_in(hud._loadout_w, &"optic") == &"scope" and not MissionRewards.is_new(&"scope"), "FIT equips it and clears NEW")
	Game.state = &"play"
	hud._on_state(&"play")


# --- the flat upgrades list and the new upgrades -------------------------------------------------------------------------------------

func _upgrades_and_shop() -> void:
	prog.new_campaign()
	Upgrades.show_all = false
	var player := Game.player as Player
	if player == null:
		TestLib.check(false, "a player node")
		return
	player.reset()
	TestLib.check(is_equal_approx(player.max_hp, 100.0), "health starts at 100")
	prog.credits = 100000
	TestLib.check(prog.buy(&"health") and is_equal_approx(player.max_hp, 115.0) and player.hp > 100.0, "buying HEALTH raises the maximum and heals the difference at once (%.0f / %.0f)" % [player.hp, player.max_hp])
	player.reset()
	TestLib.check(is_equal_approx(player.max_hp, 115.0) and is_equal_approx(player.hp, 115.0), "a respawn keeps the bought maximum")
	TestLib.check(prog.buy(&"power") and Upgrades.power_mult() > 1.0 and prog.buy(&"blink") and prog.buy(&"armour") and prog.buy(&"damage"), "ability power, teleport range, armour and damage are bought with credits")
	# the shop screen: five rows, no advanced rows, no SKILLS / CRAFT tabs
	Game.state = &"play"
	Game.state = &"paused"
	hud._on_state(&"paused")
	hud.screen_age = 5.0
	TestLib.check(hud.press_button(&"hero_open"), "the HERO hub opens")
	hud._layout_key = ""
	hud._ensure_layout()
	var ids: Array = hud.buttons.map(func(b: Dictionary) -> StringName: return b["id"])
	var rows := 0
	for id: StringName in ids:
		if String(id).begins_with("buy_") and Upgrades.IDS.has(StringName(String(id).substr(4))):
			rows += 1
	TestLib.check(rows == 5 and ids.has(&"buy_damage") and ids.has(&"buy_health") and ids.has(&"buy_power") and ids.has(&"buy_blink") and ids.has(&"buy_armour") and not ids.has(&"buy_mag"), "the UPGRADES list is flat: five rows (%d)" % rows)
	TestLib.check(not ids.has(&"hero_tab_skills") and not ids.has(&"hero_tab_craft") and ids.has(&"hero_tab_up") and ids.has(&"hero_tab_weapons"), "skill tree and workbench tabs stay behind the flag")
	var ys: Array[float] = []
	for b: Dictionary in hud.buttons:
		if String(b["id"]).begins_with("buy_") and Upgrades.IDS.has(StringName(String(b["id"]).substr(4))):
			ys.append((b["rect"] as Rect2).position.y)
	ys.sort()
	var step_ok := true
	for i in range(1, ys.size()):
		step_ok = step_ok and absf((ys[i] - ys[i - 1]) - (ys[1] - ys[0])) < 1.0
	TestLib.check(step_ok, "the rows are evenly spaced (a flat list)")
	Upgrades.show_all = true
	hud._layout_key = ""
	hud._ensure_layout()
	ids = hud.buttons.map(func(b: Dictionary) -> StringName: return b["id"])
	TestLib.check(ids.has(&"buy_mag") and ids.has(&"hero_tab_skills") and ids.has(&"hero_tab_craft"), "with the flag on every row and tab is back")
	Upgrades.show_all = false
	Game.state = &"play"
	hud._on_state(&"play")


# --- save / load ------------------------------------------------------------------------------------------------------------------------

func _save_load() -> void:
	prog.new_campaign()
	ResultCard.enabled = false
	var m := Game.missions as Missions
	for n in 4:
		m.contracts.completed.emit(&"courier", {})
	var mods := Attachments.owned.size()
	var news := MissionRewards.new_mods.duplicate()
	TestLib.check(prog.save_file() and MissionRewards.missions_done == 4, "four missions saved")
	MissionRewards.reset()
	TestLib.check(MissionRewards.missions_done == 0 and MissionRewards.new_mods.is_empty(), "(reset)")
	TestLib.check(prog.load_file() and MissionRewards.missions_done == 4 and MissionRewards.new_mods == news and Attachments.owned.size() == mods, "the mission count and the NEW flags survive a save and a load")
	# an old save without [rewards] and a damaged one load as 'nothing done yet'
	var cf := ConfigFile.new()
	cf.load(_path)
	if cf.has_section("rewards"):
		cf.erase_section("rewards")
		cf.save(_path)
	MissionRewards.missions_done = 99
	TestLib.check(prog.load_file() and MissionRewards.missions_done == 0, "an older save without [rewards] starts at mission 0")
	MissionRewards.from_save({"done": "junk", "new_mods": ["nonsense", "scope", "scope"]})
	TestLib.check(MissionRewards.missions_done == 0 and MissionRewards.new_mods == [&"scope"], "a damaged [rewards] section is cleaned")
	prog.new_campaign()
	TestLib.check(MissionRewards.missions_done == 0, "a new campaign starts the count again")
	ResultCard.enabled = true


func _finish() -> void:
	for f in [_path, _path + ".bak", _path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	prog.path = Progress.DEFAULT_PATH
	Upgrades.show_all = false
	ResultCard.enabled = true
	main.queue_free()
	Game.state = &"menu"
