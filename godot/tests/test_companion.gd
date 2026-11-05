extends RefCounted
## COMPANION AI ALLY (scripts/npc/companion.gd) in the real scene (main.tscn): recruit with the cap of one, follow the hero, fire at an aware trooper, take cover, HOLD / ATTACK orders (API and
## the two 64 px touch buttons), rescue of the hero once per mission, health and being downed (the hero revives by standing close), the chapter 11-12 / side mission / DEMO wiring, hiding inside an
## interior, the budget (no visor light, near mesh within the trooper's triangle budget) and the optional save section. Waits are on state and counters, never frame counts; the progress file of
## the test is its own (user://test_companion_<pid>.cfg).
## Run: tools/test.sh tests/test_companion.gd

var host: Node
var main: Node
var c: Companion
var p: Player
var em: EnemyManager
var prog: Progress
var _save := "user://test_companion_%d.cfg" % OS.get_process_id()


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _wait(cond: Callable, max_frames := 1500) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await TestLib.frames(host, 1)
	return cond.call()


func _hdist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	_rm(_save)
	if not HumanoidVariants.available():
		TestLib.check(true, "hero character files absent: no ally to build")
		return
	Game.force_touch = true                 # the touch layer reads it when it is built
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(20)
	Game.state = &"play"
	c = Companion.current
	p = Game.player as Player
	em = Game.enemies as EnemyManager
	prog = Game.progress as Progress
	TestLib.check(c != null and p != null and em != null and prog != null, "main.tscn composes the Companion, the Player, the EnemyManager and Progress")
	if c == null or p == null or em == null or prog == null:
		return
	prog.path = _save
	prog.autosave_enabled = false
	prog.new_campaign()
	em.patrol_groups().clear()
	em.clear()
	Game.heat = 0.0
	p.invuln = 1.0e6
	TestLib.check(not c.active and not c.visible, "no ally before a recruitment")

	await _recruit()
	await _follow()
	await _combat()
	await _cover()
	await _orders()
	await _touch()
	await _health_and_down()
	await _rescue()
	await _wiring()
	_save_compat()

	c.dismiss()
	Game.force_touch = false
	prog.path = Progress.DEFAULT_PATH
	_rm(_save)
	_rm(_save + ".tmp")
	main.queue_free()
	await frames(3)
	Game.state = &"menu"


func _kill_enemies() -> void:
	em.clear()
	await frames(2)


func _recruit() -> void:
	TestLib.check(c.recruit("demo"), "recruit() brings the ally in")
	TestLib.check(c.active and c.visible and c.life == Companion.Life.UP and is_equal_approx(c.hp, Companion.MAX_HP), "recruited: active, visible, up, full health")
	TestLib.check(not c.recruit("demo"), "the cap is one: a second recruit is refused")
	TestLib.check(host.get_tree().get_nodes_in_group(&"companion").size() == 1, "one companion node in the scene")
	TestLib.check(c.revives_left == 1 and c.mode == Companion.Mode.FOLLOW, "one rescue left, following")
	TestLib.check(prog.companion_met, "the first recruitment is recorded in the profile")
	TestLib.check(_hdist(c.global_position, p.global_position) < 6.0, "it appears next to the hero")
	TestLib.check(c._root.get_node_or_null("VisorGlow") == null, "budget: the visor light of the model is dropped")
	TestLib.check(HumanoidVariants.tris(c._body.get_meta(&"near_mesh")) <= HumanoidVariants.NEAR_ENEMY + 200, "budget: the near mesh is within the trooper's triangle budget")
	TestLib.check(c._hanim != null and c._rig != null and c._loco != null, "it runs on the shared rig with HumanoidAnim and Locomotion")


func _follow() -> void:
	p.teleport_to(p.global_position + Vector3(30.0, 0.0, 0.0))
	var ok := await _wait(func() -> bool: return _hdist(c.global_position, p.global_position) < Companion.FOLLOW_FAR + 2.5, 2400)
	TestLib.check(ok, "the ally follows the hero down the street (%.1f m)" % _hdist(c.global_position, p.global_position))
	TestLib.check(c._moving or _hdist(c.global_position, p.global_position) < Companion.FOLLOW_FAR + 2.5, "following runs the locomotion")
	# far beyond the limit: it catches up at once instead of walking across the map
	var before := c.global_position
	p.teleport_to(Vector3(Game.SPAWN.x, p.global_position.y, Game.SPAWN.z))
	ok = await _wait(func() -> bool: return _hdist(c.global_position, p.global_position) < Companion.FOLLOW_FAR + 2.5, 2400)
	TestLib.check(ok and _hdist(before, c.global_position) > 5.0, "the ally comes back to a hero who moved on")


func _spawn_trooper(offset: Vector3) -> Operative:
	var o := em.spawn(&"operative", p.global_position + offset, true) as Operative
	if o != null:
		o._cover_on = false
		o._cover_state = 0
	return o


func _combat() -> void:
	await _kill_enemies()
	var o := _spawn_trooper(Vector3(22.0, 0.0, 0.0))
	TestLib.check(o != null, "a trooper to shoot at")
	if o == null:
		return
	var start_hp := o.hp
	var shots0 := c.shots
	var ok := await _wait(func() -> bool: return c.shots >= shots0 + 3 and (o.hp < start_hp or o.dead), 2400)
	TestLib.check(ok, "the ally fires at an aware trooper in sight and hits it (shots %d, hp %.0f of %.0f)" % [c.shots - shots0, o.hp, start_hp])
	TestLib.check(c.target == o or o.dead or o.hp < start_hp, "the trooper is its target")
	await _kill_enemies()
	# a patrol that has not noticed the hero is left alone
	var calm := em.spawn(&"operative", p.global_position + Vector3(-20.0, 0.0, 0.0), false) as Operative
	if calm != null:
		calm.aware = false
		calm.aware_dist = 0.5
		calm.set_physics_process(false)         # it never notices anything
		await _wait(func() -> bool: return c._burst_left == 0 and not is_instance_valid(c.target), 1500)   # a burst at the released trooper may still be finishing
		var shots1 := c.shots
		await frames(90)
		TestLib.check(c.shots == shots1 and calm.hp >= calm.max_hp - 0.01, "the ally does not wake an unaware patrol (shots %d, aware %s, hp %.0f of %.0f)" % [c.shots - shots1, calm.aware, calm.hp, calm.max_hp])
	await _kill_enemies()


func _cover() -> void:
	var o := _spawn_trooper(Vector3(20.0, 0.0, 0.0))
	if o == null:
		TestLib.check(false, "a trooper for the cover check")
		return
	c.test_cover = c.global_position + Vector3(3.0, 0.0, 2.0)
	var used := c.cover_used
	var ok := await _wait(func() -> bool: return c.cover_used > used, 2400)
	TestLib.check(ok, "under fire the ally runs to cover and reaches it (cover spot %s)" % str(c._cover))
	TestLib.check(c._cover.is_finite() and _hdist(c.global_position, c._cover) < 1.6, "it stands at the cover spot")
	c.test_cover = Vector3.INF
	await _kill_enemies()
	await _wait(func() -> bool: return not c._cover.is_finite(), 600)
	TestLib.check(not c._cover.is_finite(), "with the fight over it leaves cover")


func _orders() -> void:
	await _kill_enemies()
	TestLib.check(c.command(&"hold") and c.mode == Companion.Mode.HOLD and c.hold_pos.is_finite(), "HOLD: the ally holds its spot")
	var spot := c.hold_pos
	p.teleport_to(p.global_position + Vector3(26.0, 0.0, 0.0))
	await frames(120)
	TestLib.check(_hdist(c.global_position, spot) < 2.5 and _hdist(c.global_position, p.global_position) > 15.0, "holding: it does not follow the hero (%.1f m from its spot)" % _hdist(c.global_position, spot))
	TestLib.check(c.command(&"hold") and c.mode == Companion.Mode.FOLLOW, "HOLD again: back to following")
	var ok := await _wait(func() -> bool: return _hdist(c.global_position, p.global_position) < Companion.FOLLOW_FAR + 2.5, 2400)
	TestLib.check(ok, "released, it rejoins the hero")
	# ATTACK: it pushes at the nearest enemy for a while
	var o := _spawn_trooper(Vector3(-30.0, 0.0, 0.0))
	if o == null:
		TestLib.check(false, "a trooper to attack")
		return
	TestLib.check(c.command(&"attack") and c.mode == Companion.Mode.ATTACK, "ATTACK: the push starts")
	var d0 := _hdist(c.global_position, o.global_position)
	ok = await _wait(func() -> bool: return o.dead or _hdist(c.global_position, o.global_position) < d0 - 6.0, 2400)
	TestLib.check(ok, "attacking: it closes on the enemy (%.0f m to %.0f m)" % [d0, _hdist(c.global_position, o.global_position)])
	c._attack_t = 0.05
	ok = await _wait(func() -> bool: return c.mode == Companion.Mode.FOLLOW, 600)
	TestLib.check(ok, "the push ends by itself and the ally follows again")
	await _kill_enemies()


func _touch() -> void:
	await frames(4)
	var tcs := main.find_children("*", "TouchControls", true, false)
	TestLib.check(not tcs.is_empty(), "the HUD owns the touch controls")
	if tcs.is_empty():
		return
	var tc := tcs[0] as TouchControls
	var hold := {}
	var atk := {}
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"companion_hold":
			hold = b
		elif b["action"] == &"companion_attack":
			atk = b
	TestLib.check(not hold.is_empty() and not atk.is_empty(), "the two ally buttons exist (HOLD, ATTACK)")
	if hold.is_empty() or atk.is_empty():
		return
	tc.more_open = true                         # the ally orders sit behind MORE
	TestLib.check(tc.controls_on and tc.button_visible(hold) and tc.button_visible(atk), "the ally buttons show while it is recruited")
	var win := host.get_window()
	var old := win.size
	for size: Vector2i in [Vector2i(844, 390), Vector2i(1280, 720)]:
		win.size = size
		await frames(3)
		Game.state = &"play"
		var vp := host.get_viewport().get_visible_rect().size
		for b: Dictionary in [hold, atk]:
			TestLib.check(float(b["r"]) * 2.0 >= UiUtil.TOUCH_MIN and float(b["dx"]) + float(b["r"]) <= StoryView.TOUCH_BUTTONS_W + 100.0, "%s: at least %d px across and inside the reserved width (+100: the ally column is MORE-only)" % [b["label"], int(UiUtil.TOUCH_MIN)])
			var ctr := tc._button_center(b)
			TestLib.check(Rect2(Vector2.ZERO, vp).grow(-float(b["r"])).has_point(ctr), "%s is on screen at %dx%d" % [b["label"], size.x, size.y])
			var clear := true
			for o: Dictionary in TouchControls.BUTTONS:
				if o == b:
					continue
				var dd := Vector2(float(b["dx"]) - float(o["dx"]), float(b["dy"]) - float(o["dy"])).length()
				if dd < (float(b["r"]) + float(o["r"])) * 0.95:
					clear = false
			TestLib.check(clear, "%s does not overlap another touch button" % b["label"])
		tc.touch_down(21, tc._button_center(hold))
		tc.touch_up(21)
		TestLib.check(c.mode == Companion.Mode.HOLD, "tapping HOLD holds the ally at %dx%d" % [size.x, size.y])
		tc.touch_down(22, tc._button_center(hold))
		tc.touch_up(22)
		TestLib.check(c.mode == Companion.Mode.FOLLOW, "tapping HOLD again releases it")
		tc.touch_down(23, tc._button_center(atk))
		tc.touch_up(23)
		TestLib.check(c.mode == Companion.Mode.ATTACK, "tapping ATTACK sends it in at %dx%d" % [size.x, size.y])
		c.mode = Companion.Mode.FOLLOW
		c._attack_t = 0.0
	win.size = old
	await frames(3)
	Game.state = &"play"
	c.mode = Companion.Mode.FOLLOW
	c._attack_t = 0.0
	c.dismiss()
	await frames(2)
	TestLib.check(not tc.button_visible(hold) and not tc.button_visible(atk), "the ally buttons are gone without an ally")
	TestLib.check(c.recruit("demo"), "recruit again")


func _health_and_down() -> void:
	var hp0 := c.hp
	c.shot_passes(c.global_position + Vector3(-5.0, 1.0, 0.0), c.global_position + Vector3(5.0, 1.0, 0.0), 10.0)
	TestLib.check(is_equal_approx(c.hp, hp0 - 10.0 * Companion.ARMOUR), "a round through the ally hurts it (%.1f hp)" % c.hp)
	c.shot_passes(c.global_position + Vector3(-5.0, 1.0, 4.0), c.global_position + Vector3(5.0, 1.0, 4.0), 10.0)
	TestLib.check(is_equal_approx(c.hp, hp0 - 10.0 * Companion.ARMOUR), "a round that passes 4 m away misses")
	var bolt_ok := c.bolt_hit(c.global_position + Vector3(0.0, 1.0, 0.0), 8.0, c.global_position + Vector3(10.0, 1.0, 0.0))
	TestLib.check(bolt_ok and c.hp < hp0 - 10.0 * Companion.ARMOUR, "an energy bolt hurts it and is spent")
	var downs := c.times_downed
	c.damage(1000.0, c.global_position + Vector3(8.0, 0.0, 0.0))
	TestLib.check(c.life == Companion.Life.DOWNED and c.times_downed == downs + 1 and c.hp == 0.0, "lethal damage downs the ally")
	TestLib.check(not c.command(&"hold"), "a downed ally takes no orders (%s)" % c.mode_name())
	TestLib.check(not c.command(&"attack"), "ATTACK is refused while it is down")
	_spawn_trooper(Vector3(18.0, 0.0, 0.0))
	var shots0 := c.shots
	await frames(90)
	TestLib.check(c.shots == shots0, "a downed ally does not shoot")
	await _kill_enemies()
	# the hero stands next to it: it gets up
	p.teleport_to(c.global_position + Vector3(1.5, 0.0, 0.0))
	var ok := await _wait(func() -> bool: return c.life == Companion.Life.UP, 1200)
	TestLib.check(ok and c.hp > 0.0 and c.hp < Companion.MAX_HP, "the hero revives the downed ally by standing close (%.0f hp)" % c.hp)
	TestLib.check(c.hp_fraction() > 0.0 and c.hp_fraction() < 1.0, "health fraction for the HUD plate")
	c.hp = Companion.MAX_HP


func _rescue() -> void:
	c._rush_to(p.global_position)
	c.revives_left = 1
	p.invuln = 0.0
	p.hp = 1.0
	p.damage(500.0, p.global_position + Vector3(5.0, 0.0, 0.0))
	TestLib.check(p.hp > 1.0 and Game.state == &"play" and c.rescues == 1 and c.revives_left == 0, "a lethal hit is turned back by the ally, once (hero %.0f hp, state %s)" % [p.hp, Game.state])
	TestLib.check(p.invuln > 0.5 and p.hp <= p.max_hp * 0.5, "the rescued hero is hurt but protected for a moment")
	p.invuln = 0.0
	p.hp = 1.0
	p.damage(500.0, p.global_position + Vector3(5.0, 0.0, 0.0))
	TestLib.check(Game.state == &"dead", "the second lethal hit of the mission kills the hero (state %s)" % Game.state)
	Game.do_respawn()
	await frames(6)
	TestLib.check(Game.state == &"play" and c.active and c.life == Companion.Life.UP and c.revives_left == 1, "after the respawn the ally is back at full health with its rescue")
	TestLib.check(_hdist(c.global_position, p.global_position) < 8.0, "and next to the hero")
	p.invuln = 1.0e6
	# too far away to help
	c.revives_left = 1
	c.global_position = p.global_position + Vector3(Companion.RESCUE_RANGE + 20.0, 0.0, 0.0)
	TestLib.check(not Companion.rescue(p), "an ally out of range cannot rescue")
	c._rush_to(p.global_position)


func _wiring() -> void:
	c.dismiss()
	await frames(2)
	var m := Game.missions as Missions
	TestLib.check(m != null and m.campaign != null and m.sides != null, "Missions owns the campaign and the side missions")
	TestLib.check(Companion.CHAPTERS == [10, 11] and CampaignRunner.chapter_count() >= 12, "chapters 11 and 12 (index 10, 11) are the ally chapters")
	# chapter 1: no ally
	TestLib.check(m.campaign.start_chapter(0, 0, true), "chapter 1 starts")
	await frames(40)
	TestLib.check(not c.active, "chapter 1 has no ally")
	m.campaign.abort()
	# chapter 11: the ally joins by itself, leaves when the chapter ends
	TestLib.check(m.campaign.start_chapter(10, 0, true), "chapter 11 starts")
	var ok := await _wait(func() -> bool: return c.active, 600)
	TestLib.check(ok and c.reason == "chapter" and not c.manual, "chapter 11: the ally joins")
	m.campaign.abort()
	ok = await _wait(func() -> bool: return not c.active, 600)
	TestLib.check(ok, "the ally leaves when the chapter stops")
	em.clear()
	TestLib.check(m.campaign.start_chapter(11, 0, true), "chapter 12 starts")
	ok = await _wait(func() -> bool: return c.active, 600)
	TestLib.check(ok, "chapter 12: the ally joins")
	m.campaign.abort()
	await _wait(func() -> bool: return not c.active, 600)
	em.clear()
	# a side mission of the list
	DemoMode.active = true                  # only so every job is startable (SideMissions.unlocked)
	var started := m.sides.start(&"turf")
	DemoMode.active = false
	TestLib.check(started, "TURF DEFENCE starts")
	ok = await _wait(func() -> bool: return c.active, 600)
	TestLib.check(ok and c.reason == "side", "side mission TURF DEFENCE: the ally joins")
	m.sides.abort("TEST")
	ok = await _wait(func() -> bool: return not c.active, 600)
	TestLib.check(ok, "and leaves with it")
	DemoMode.active = true
	started = m.sides.start(&"courier")
	DemoMode.active = false
	await frames(60)
	TestLib.check(started and not c.active, "COURIER has no ally")
	m.sides.abort("TEST")
	# DEMO menu
	var cat := DemoMode.catalog()
	var group := {}
	for g: Dictionary in cat:
		if g["kind"] == &"companion":
			group = g
	TestLib.check(not group.is_empty() and (group["items"] as Array).size() == 2, "the DEMO catalogue has the COMPANION group")
	TestLib.check(DemoPanel.TABS.has("ALLY") and DemoPanel.TABS.find("ALLY") == cat.find(group), "the ALLY tab is the companion catalogue page")
	TestLib.check(DemoMode.start_companion(&"recruit").begins_with("ALLY") and c.active and c.manual, "DEMO RECRUIT puts the ally next to the hero")
	await frames(60)
	TestLib.check(c.active, "a DEMO recruit stays without a mission")
	TestLib.check(DemoMode.start_companion(&"dismiss") == "ALLY DISMISSED" and not c.active, "DEMO DISMISS sends it away")
	# inside an interior or a vehicle it is not drawn and takes no orders
	TestLib.check(c.recruit("demo"), "recruit for the interior check")
	var entered := InteriorTestActions.enter(&"lobby")
	TestLib.check(entered != "" and InteriorGameplay.active, "a real interior is entered (%s)" % entered)
	var ok2 := await _wait(func() -> bool: return c._hidden_by == "interior", 600)
	TestLib.check(ok2 and not c._root.visible and not Companion.controllable(), "inside an interior the ally is hidden and takes no orders")
	var ig := InteriorGameplay.instance
	if ig != null:
		ig.leave(true)
	ok2 = await _wait(func() -> bool: return c._hidden_by == "" and not InteriorGameplay.active, 900)
	TestLib.check(ok2 and c._root.visible and Companion.controllable(), "back outside it is drawn again")
	TestLib.check(_hdist(c.global_position, p.global_position) < 10.0, "next to the hero")
	# a new run sends it away
	Game.new_game.emit()
	TestLib.check(not c.active and not c.visible, "a new run dismisses the ally")


func _save_compat() -> void:
	prog.companion_met = true
	TestLib.check(prog.save_file(), "the profile saves with the ally flag")
	prog.companion_met = false
	TestLib.check(prog.load_file() and prog.companion_met, "the [companion] section loads back")
	var cf := ConfigFile.new()
	TestLib.check(cf.load(_save) == OK and cf.has_section("companion"), "the flag lives in its own optional section")
	cf.erase_section("companion")
	cf.save(_save)
	prog.companion_met = true
	TestLib.check(prog.load_file() and not prog.companion_met, "a save without the section (older builds) still loads")
