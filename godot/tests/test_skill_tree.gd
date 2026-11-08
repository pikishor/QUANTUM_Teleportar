extends RefCounted
## SKILL TREE: the pure rules (4 verbs x 5 nodes, levels, points, prerequisites, respec, save round trip and damaged saves, difficulty scaling) and the live game in main.tscn:
## XP from real kills and from payouts, each node's effect on the real Quantum module (range, hops, blink strike, afterimage, decoy count and duration, explode on death, links,
## swap cooldown, damage share, collapse radius / pull / chain / damage, coherence cost), the SKILLS screen reached by touch from the shop (64 px buttons), RESPEC in the shop, the
## [skills] save section (older saves load level 1) and the TEST / DEMO menu entries. Waits on counters and state, never on frame counts; user:// state is reset.
## Run: tools/test.sh tests/test_skill_tree.gd

const SAVE := "user://test_skill_tree.cfg"

var host: Node
var main: Node
var p: Player
var em: EnemyManager
var hud: Hud
var prog: Progress
var q: Node
var _spawned: Array[Drone] = []
var _mode := 1


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _forward() -> Vector3:
	return Vector3(-sin(p.yaw), 0.0, -cos(p.yaw))


func _enemy(pos: Vector3) -> Drone:
	var d := em.spawn(&"operative", pos, false)
	if d == null:
		return null
	d.set_physics_process(false)
	d.max_hp = 5000.0
	d.hp = 5000.0
	_spawned.append(d)
	return d


func _clear_enemies() -> void:
	for d in _spawned:
		if is_instance_valid(d) and d.active:
			em.release(d)
	_spawned.clear()


func _level_to(l: int) -> void:
	SkillTree.reset()
	var need := 0
	for i in range(1, l):
		need += SkillTree.xp_for(i)
	SkillTree.xp = need


func run(h: Node) -> void:
	Upgrades.show_all = true                 # the advanced upgrade rows and the SKILLS / CRAFT tabs are behind this flag (scripts/progress/upgrades.gd)
	host = h
	Sfx.muted = true
	TestMode.reset_toggles()
	_mode = Difficulty.current
	Difficulty.current = 1
	SkillTree.reset()
	_tables()
	_levels_and_points()
	_prereqs_and_respec()
	_save_rules()
	_scaling()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	em = Game.enemies as EnemyManager
	prog = Game.progress as Progress
	var huds := main.find_children("*", "Hud", true, false)
	TestLib.check(p != null and em != null and prog != null and not huds.is_empty(), "main.tscn composes the player, enemies, progress and the HUD")
	if p == null or em == null or prog == null or huds.is_empty():
		Difficulty.current = _mode
		return
	hud = huds[0] as Hud
	q = p.get(&"quantum") as Node
	TestLib.check(q != null, "the player owns the Quantum module")
	prog.autosave_enabled = false
	prog.path = SAVE
	prog.new_campaign()
	Difficulty.current = 1
	Game.state = &"play"
	await frames(5)
	await _xp_live()
	await _effects()
	await _screen()
	_persistence()
	_menus()
	_clear_enemies()
	SkillTree.reset()
	Difficulty.current = _mode
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	main.queue_free()
	await frames(5)
	Game.state = &"menu"


# --- pure rules --------------------------------------------------------------------------------------------------------------

func _tables() -> void:
	TestLib.check(SkillTree.VERBS.size() == 4, "four verbs")
	var ok := true
	for v: StringName in SkillTree.VERBS:
		var n := SkillTree.verb_nodes(v)
		ok = ok and n.size() == 5 and SkillTree.VERB_NAMES.has(v)
	TestLib.check(ok and SkillTree.ids().size() == 20, "every verb has 5 nodes (20 in all)")
	var named := true
	for id: StringName in SkillTree.ids():
		named = named and SkillTree.title(id) == SkillTree.title(id).to_upper() and SkillTree.max_rank(id) >= 1 and SkillTree.effect_text(id) != ""
		for r: StringName in SkillTree.prereqs(id):
			named = named and SkillTree.NODES.has(r) and SkillTree.verb_of(r) == SkillTree.verb_of(id)
	TestLib.check(named, "nodes have plain upper-case names, effect text and same-verb prerequisites that exist")
	TestLib.check(SkillTree.verb_nodes(&"teleport").has(&"tp_strike") and SkillTree.verb_nodes(&"teleport").has(&"tp_after") and SkillTree.verb_nodes(&"collapse").has(&"co_chain"), "the nodes asked for exist (blink strike, afterimage, chain)")


func _levels_and_points() -> void:
	SkillTree.reset()
	TestLib.check(SkillTree.level() == 1 and SkillTree.points() == 0, "a new profile is level 1 with no points")
	SkillTree.add_xp(SkillTree.xp_for(1))
	TestLib.check(SkillTree.level() == 2 and SkillTree.points() == 1, "enough XP gives level 2 and one point")
	_level_to(SkillTree.LEVEL_CAP)
	TestLib.check(SkillTree.level() == SkillTree.LEVEL_CAP and SkillTree.points() == SkillTree.LEVEL_CAP - 1, "the level cap holds")
	SkillTree.add_xp(1000000)
	TestLib.check(SkillTree.level() == SkillTree.LEVEL_CAP, "XP past the cap changes nothing")
	var total := 0
	for id: StringName in SkillTree.ids():
		total += SkillTree.max_rank(id)
	TestLib.check(total > SkillTree.points_total() and total < SkillTree.points_total() * 2, "the tree cannot be filled at the cap, so choices matter (%d ranks, %d points)" % [total, SkillTree.points_total()])
	SkillTree.reset()
	TestLib.check(SkillTree.kill_xp(15) == 8 and SkillTree.kill_xp(2500) == 250 and SkillTree.kill_xp(160) == 40, "kill XP follows the enemy score, clamped")


func _prereqs_and_respec() -> void:
	_level_to(10)
	TestLib.check(not SkillTree.buy(&"tp_strike") and SkillTree.rank(&"tp_strike") == 0, "a node cannot be bought before its prerequisite")
	TestLib.check(SkillTree.buy(&"tp_range") and SkillTree.rank(&"tp_range") == 1 and SkillTree.points() == 8, "a root node is bought for one point")
	TestLib.check(SkillTree.buy(&"tp_strike") and not SkillTree.buy(&"tp_cost"), "the prerequisite opens the next node; the capstone needs both branches")
	while SkillTree.buy(&"tp_range"):
		pass
	TestLib.check(SkillTree.rank(&"tp_range") == SkillTree.max_rank(&"tp_range"), "ranks stop at the maximum")
	SkillTree.reset()
	TestLib.check(not SkillTree.buy(&"tp_range"), "no points, no purchase")
	_level_to(3)
	SkillTree.buy(&"co_pull")
	SkillTree.buy(&"co_pull")
	TestLib.check(SkillTree.spent() == 2 and SkillTree.points() == 0 and SkillTree.respec_price() == 2 * SkillTree.RESPEC_PER_POINT, "respec price follows the points spent")
	SkillTree.respec()
	TestLib.check(SkillTree.spent() == 0 and SkillTree.points() == 2 and SkillTree.level() == 3, "respec refunds the points and keeps the level")
	TestLib.check(SkillTree.range_mult() == 1.0 and SkillTree.strike_damage() == 0.0 and SkillTree.cost_mult(&"collapse") == 1.0 and SkillTree.share_mult() == 1.0, "every effect is neutral at rank 0")


func _save_rules() -> void:
	_level_to(12)
	SkillTree.buy(&"en_links")
	SkillTree.buy(&"en_share")
	SkillTree.buy(&"sp_life")
	var d := SkillTree.to_save()
	var xp0 := SkillTree.xp
	SkillTree.reset()
	SkillTree.from_save(d)
	TestLib.check(SkillTree.xp == xp0 and SkillTree.rank(&"en_links") == 1 and SkillTree.rank(&"en_share") == 1 and SkillTree.rank(&"sp_life") == 1, "the tree round-trips through the save dictionary")
	SkillTree.from_save({"xp": "junk", "r_tp_range": 99, "r_bogus": 3, "r_tp_strike": 2})
	TestLib.check(SkillTree.level() == 1 and SkillTree.spent() == 0, "a damaged section loads clean: no XP, no points, no free ranks")
	SkillTree.from_save({"xp": 0, "r_co_cost": 3, "r_co_chain": 1, "r_co_dmg": 1})
	TestLib.check(SkillTree.spent() == 0, "ranks beyond the available points or without prerequisites are dropped")
	SkillTree.from_save({})
	TestLib.check(SkillTree.level() == 1 and SkillTree.spent() == 0, "an older save with no [skills] loads at level 1")
	SkillTree.reset()


func _scaling() -> void:
	var m := Difficulty.current
	Difficulty.current = 0
	var story_p := SkillTree.power()
	_level_to(5)
	SkillTree.buy(&"tp_range")
	var story_range := SkillTree.range_mult()
	SkillTree.reset()
	Difficulty.current = 2
	_level_to(5)
	SkillTree.buy(&"tp_range")
	var hard_range := SkillTree.range_mult()
	SkillTree.reset()
	TestLib.check(story_p > 1.0 and story_range > hard_range and hard_range > 1.0, "node values scale with the difficulty (STORY stronger than HARD)")
	Difficulty.current = 0
	var a := SkillTree.xp
	SkillTree.add_xp(100)
	var story_gain := SkillTree.xp - a
	SkillTree.reset()
	Difficulty.current = 1
	SkillTree.add_xp(100)
	TestLib.check(story_gain > SkillTree.xp, "STORY earns XP faster than NORMAL")
	SkillTree.reset()
	Difficulty.current = m


# --- XP in the live game -----------------------------------------------------------------------------------------------------

func _xp_live() -> void:
	SkillTree.reset()
	var d := _enemy(p.global_position + _forward() * 8.0)
	TestLib.check(d != null, "an enemy spawns")
	if d == null:
		return
	var x0 := SkillTree.xp
	d.damage(99999.0)
	TestLib.check(SkillTree.xp >= x0 + 8, "a real kill pays XP")
	var x1 := SkillTree.xp
	prog.add_credits(400)
	TestLib.check(SkillTree.xp >= x1 + 100, "a mission payout pays XP")
	var x2 := SkillTree.xp
	prog._in_score = true
	prog.add_credits(400)
	prog._in_score = false
	TestLib.check(SkillTree.xp == x2, "the score-to-credits payout does not pay XP twice")
	SkillTree.reset()


# --- node effects on the real Quantum module -----------------------------------------------------------------------------------

func _effects() -> void:
	_clear_enemies()
	p.energy = 1000.0
	Game.state = &"play"
	# blink strike and afterimage
	SkillTree.max_all()
	var e1 := _enemy(p.global_position + _forward() * 12.0 + Vector3(0, 0.1, 0))
	var e2 := _enemy(p.global_position + Vector3(2.0, 0.0, 0.0))
	if e1 != null and e2 != null:
		var h1 := e1.hp
		var h2 := e2.hp
		q.call(&"_skill_blink_damage", p.global_position, e1.global_position)
		TestLib.check(e1.hp < h1 and e2.hp < h2, "BLINK STRIKE hurts the arrival point and AFTERIMAGE the departure point")
	TestLib.check(SkillTree.range_mult() > 1.2 and SkillTree.hops_extra() == 2, "teleport range and extra hops grow with ranks")
	TestLib.check(SkillTree.cost_mult(&"teleport") < 1.0 and SkillTree.cost_mult(&"collapse") < 1.0, "COHERENCE COST lowers the cost")
	# coherence cost used by the verbs
	SkillTree.reset()
	p.energy = 100.0
	_clear_enemies()
	await frames(2)
	var base_e := p.energy
	q.set(&"cd_collapse", 0.0)
	q.call(&"collapse_all")
	var spent_base := base_e - p.energy
	_level_to(40)
	SkillTree.buy(&"co_radius")
	SkillTree.buy(&"co_pull")
	SkillTree.buy(&"co_chain")
	SkillTree.buy(&"co_dmg")
	SkillTree.buy(&"co_cost")
	p.energy = 100.0
	q.set(&"cd_collapse", 0.0)
	q.call(&"collapse_all")
	var spent_skill := 100.0 - p.energy
	TestLib.check(spent_base > 0.0 and spent_skill < spent_base, "COLLAPSE costs less coherence with the capstone")
	# collapse pull, damage and chain
	SkillTree.reset()
	_level_to(40)
	for id: StringName in [&"co_radius", &"co_pull", &"co_pull", &"co_pull", &"co_chain", &"co_chain", &"co_chain", &"co_dmg"]:
		SkillTree.buy(id)
	var far := _enemy(p.global_position + Vector3(10.0, 0.0, 0.0))
	var victim := _enemy(p.global_position + Vector3(-9.0, 0.0, 0.0))
	var bystander := _enemy(p.global_position + Vector3(-9.0, 0.0, 4.0))
	if far != null and victim != null and bystander != null:
		victim.hp = 5.0
		var d0 := Vector2(far.global_position.x - p.global_position.x, far.global_position.z - p.global_position.z).length()
		var bh := bystander.hp
		p.energy = 100.0
		q.set(&"cd_collapse", 0.0)
		TestLib.check(bool(q.call(&"collapse_all")), "COLLAPSE fires")
		var d1 := Vector2(far.global_position.x - p.global_position.x, far.global_position.z - p.global_position.z).length()
		TestLib.check(d1 < d0 - 2.0, "PULL draws enemies toward the centre (%.1f m to %.1f m)" % [d0, d1])
		TestLib.check(victim.dead and bystander.hp < bh, "CHAIN: a kill detonates and hurts its neighbour")
	# superposition: decoys, duration, explode on death
	SkillTree.reset()
	_clear_enemies()
	var base_life: float = 0.0
	p.energy = 100.0
	q.set(&"cd_super", 0.0)
	q.call(&"superpose")
	base_life = float(q.get(&"clone_left"))
	q.call(&"_kill_clone")
	q.set(&"cd_super", 0.0)
	_level_to(40)
	for id: StringName in [&"sp_count", &"sp_count", &"sp_life", &"sp_life", &"sp_boom", &"sp_boom", &"sp_boom"]:
		SkillTree.buy(id)
	p.energy = 100.0
	q.call(&"superpose")
	TestLib.check(float(q.get(&"clone_left")) > base_life + 2.0, "DURATION lengthens the decoy")
	var echoes: Array = q.get(&"_echoes")
	var shown := 0
	for e: Variant in echoes:
		if (e as MeshInstance3D).visible:
			shown += 1
	TestLib.check(shown == 2, "DECOY COUNT adds two extra decoys (%d)" % shown)
	var picks := {}
	for i in 4:
		picks[(q.call(&"decoy_pick") as Node3D).get_instance_id()] = true
	TestLib.check(q.call(&"decoy_pick") != null, "enemies can pick among the decoys")
	q.call(&"_kill_clone")
	shown = 0
	for e: Variant in echoes:
		if (e as MeshInstance3D).visible:
			shown += 1
	TestLib.check(shown == 0, "the extra decoys vanish with the ghost")
	var near := _enemy(p.global_position + Vector3(3.0, 0.0, 0.0))
	if near != null:
		var nh := near.hp
		q.call(&"_on_player_died")
		TestLib.check(near.hp < nh, "EXPLODE ON DEATH hurts enemies around the fallen hero")
	# entangle: links, swap cooldown, damage share
	SkillTree.reset()
	_clear_enemies()
	var base_links: int = int(q.call(&"_max_links"))
	_level_to(40)
	for id: StringName in [&"en_links", &"en_links", &"en_swap", &"en_swap", &"en_swap", &"en_share", &"en_life"]:
		SkillTree.buy(id)
	TestLib.check(int(q.call(&"_max_links")) == base_links + 2, "MULTI LINK raises the link cap by two")
	TestLib.check(SkillTree.swap_cd_mult() < 0.7 and SkillTree.link_life() > 0.0, "SWAP COOLDOWN and LINK TIME apply")
	var a := _enemy(p.global_position + Vector3(6.0, 0.0, 0.0))
	var b := _enemy(p.global_position + Vector3(6.0, 0.0, 6.0))
	if a != null and b != null:
		a.linked = b
		b.linked = a
		var ha := b.hp
		a.damage(50.0)
		TestLib.check(ha - b.hp >= 50.0 * 1.15, "DAMAGE SHARE sends more than the hit to the partner (%.0f)" % (ha - b.hp))
		a.linked = null
		b.linked = null
	SkillTree.reset()
	_clear_enemies()
	q.call(&"reset")
	p.energy = 100.0


# --- the SKILLS screen, RESPEC in the shop ---------------------------------------------------------------------------------------

func _button(id: StringName) -> Dictionary:
	for b: Dictionary in hud.buttons:
		if b["id"] == id:
			return b
	return {}


func _screen() -> void:
	SkillTree.reset()
	_level_to(6)
	prog.credits = 10000
	Game.state = &"play"
	hud.pause_game()
	hud._ensure_layout()
	var sb := _button(&"skills_open")
	TestLib.check(hud.press_button(&"shop") , "UPGRADES opens the shop")
	hud._ensure_layout()
	sb = _button(&"hero_tab_skills")
	TestLib.check(not sb.is_empty() and (sb["rect"] as Rect2).size.y >= 64.0 * UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size) - 0.5, "the HERO hub has a SKILLS tab of at least 64 px")
	TestLib.check(hud.press_button(&"skills_open") and hud._skills_open, "SKILLS opens the tree")
	hud._ensure_layout()
	var vp := hud.get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var missing: Array[String] = []
	var big := true
	var inside := true
	var rects: Array[Rect2] = []
	for id: StringName in SkillTree.ids():
		var b := _button(StringName("sk_%s" % id))
		if b.is_empty():
			missing.append(String(id))
			continue
		var r: Rect2 = b["rect"]
		rects.append(r)
		big = big and r.size.y >= 64.0 * s - 0.5
		inside = inside and r.position.x >= -0.5 and r.end.x <= vp.x + 0.5 and r.end.y <= vp.y + 0.5
	for id: StringName in [&"sk_respec", &"sk_back"]:
		var b := _button(id)
		if b.is_empty():
			missing.append(String(id))
		else:
			rects.append(b["rect"])
			big = big and (b["rect"] as Rect2).size.y >= 64.0 * s - 0.5
	TestLib.check(missing.is_empty(), "a button for every node, RESPEC and BACK (missing: %s)" % ", ".join(missing))
	TestLib.check(big, "every skill button is at least 64 px high")
	TestLib.check(inside, "every node button is inside the screen")
	var overlap := false
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				overlap = true
	TestLib.check(not overlap, "skill buttons do not overlap")
	var pts := SkillTree.points()
	TestLib.check(hud.press_button(&"sk_tp_range") and SkillTree.rank(&"tp_range") == 1 and SkillTree.points() == pts - 1, "tapping a node spends a point")
	TestLib.check(not hud.press_button(&"sk_tp_cost") and SkillTree.rank(&"tp_cost") == 0, "a locked node refuses")
	hud._ensure_layout()
	TestLib.check(hud.press_button(&"sk_tp_hops") and hud.press_button(&"sk_tp_strike"), "more nodes can be bought through the screen")
	var cr := prog.credits
	var price := SkillTree.respec_price()
	hud._ensure_layout()
	TestLib.check(hud.press_button(&"sk_respec") and SkillTree.spent() == 0 and prog.credits == cr - price and SkillTree.points() == SkillTree.points_total(), "RESPEC refunds every rank for credits")
	prog.credits = 0
	SkillTree.buy(&"tp_range")
	TestLib.check(not hud.press_button(&"sk_respec") and SkillTree.rank(&"tp_range") == 1, "RESPEC needs the credits")
	TestLib.check(hud.press_button(&"sk_back") and not hud._skills_open and not hud._shop_open and not hud._hero_hub, "BACK leaves the HERO hub")
	hud.press_button(&"shop_back")
	hud.press_button(&"resume")
	await frames(2)
	Game.state = &"play"
	TestLib.check(not hud._skills_open, "resuming closes the tree")


# --- save compatibility, menus ---------------------------------------------------------------------------------------------------

func _persistence() -> void:
	SkillTree.reset()
	_level_to(8)
	SkillTree.buy(&"co_pull")
	SkillTree.buy(&"sp_count")
	var xp0 := SkillTree.xp
	TestLib.check(prog.save_file(), "the profile saves")
	SkillTree.reset()
	TestLib.check(prog.load_file() and SkillTree.xp == xp0 and SkillTree.rank(&"co_pull") == 1 and SkillTree.rank(&"sp_count") == 1, "the [skills] section loads back")
	var cf := ConfigFile.new()
	cf.load(SAVE)
	cf.erase_section("skills")
	cf.save(SAVE)
	_level_to(20)
	TestLib.check(prog.load_file() and SkillTree.level() == 1 and SkillTree.spent() == 0, "an older save without [skills] loads at level 1")
	cf = ConfigFile.new()
	cf.load(SAVE)
	cf.set_value("skills", "xp", Vector2.ONE)
	cf.set_value("skills", "r_tp_range", "many")
	cf.save(SAVE)
	TestLib.check(prog.load_file() and SkillTree.level() == 1 and SkillTree.rank(&"tp_range") == 0, "a damaged [skills] section loads clean")
	_level_to(9)
	prog.new_campaign()
	TestLib.check(SkillTree.level() == 1 and SkillTree.spent() == 0, "a new campaign resets the tree")


func _menus() -> void:
	SkillTree.reset()
	TestLib.check(TestMode.give_xp(100000) != "" and SkillTree.level() > 5, "TEST MENU: XP is given")
	TestLib.check(TestMode.max_skills() != "" and SkillTree.rank(&"co_cost") == SkillTree.max_rank(&"co_cost") and SkillTree.level() == SkillTree.LEVEL_CAP, "TEST MENU: all skills maxed")
	SkillTree.reset()
	var labels: Array[String] = []
	for it: Dictionary in DemoMenu.entries():
		labels.append(String(it["label"]))
	TestLib.check(labels.has("SKILLS") and labels.has("MAX ALL SKILLS") and labels.has("+5000 XP"), "DEMO tab lists the skill entries")
	var tm := TestMenu.new()
	main.add_child(tm)
	tm.page = 1
	var tl: Array[String] = []
	for it: Dictionary in tm._page_items():
		tl.append(String(it.get("label", "")))
	TestLib.check(tl.has("MAX ALL SKILLS") and tl.has("+500 XP"), "TEST MENU LOOT tab lists the skill entries")
	tm.queue_free()
