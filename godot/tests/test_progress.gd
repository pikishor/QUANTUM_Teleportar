extends RefCounted
## Progress: the shop maths (costs, discounts, levels, caps), the upgrade effects on the real Player (damage, magazine, reload, armour, coherence regeneration, blink range),
## credits from score, reputation tiers, the save file round trip (and damaged / foreign files), autosave triggers, new game versus continue and the difficulty rules.
## Run: tools/test.sh tests/test_progress.gd

const Env := preload("res://tests/player_env.gd")
const Fixture := preload("res://tests/player_fixture.gd")
const TMP := "user://test_progress_save.cfg"


class World extends Node3D:
	var intersections: Array[Vector3] = []


class FakeStory extends Node:
	var chapter := 0
	var set_to := -1

	func set_chapter(i: int) -> void:
		set_to = i
		chapter = i


var e := Env.new()
var p: Player
var root: Node3D
var m: Missions
var prog: Progress
var story: FakeStory


func run(host: Node) -> void:
	seed(9)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	await e.setup(host)
	p = e.p
	root = e.root
	Fixture.add_floor(root, 600.0)
	var w := World.new()
	w.intersections = CityLayout.make_intersections()
	root.add_child(w)
	Game.world = w
	story = FakeStory.new()
	root.add_child(story)
	Game.story = story
	m = (load("res://scenes/missions.tscn") as PackedScene).instantiate() as Missions
	root.add_child(m)
	await e.frames(3)
	prog = m.progress
	prog.path = TMP
	Upgrades.reset()

	_upgrade_maths()
	_wallet_and_shop()
	_reputation()
	await _effects(host)
	_credits_from_score()
	_save_load()
	await _autosave()
	await _new_vs_continue()

	Upgrades.reset()
	Game.story = null
	Game.world = null
	Game.score = 0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	await e.teardown()


func _fresh() -> void:
	prog.autosave_enabled = false
	prog.new_campaign()
	prog.tutorial_done = false
	prog.best = 0
	Upgrades.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


# --- shop maths ----------------------------------------------------------------------------------------------------------

func _upgrade_maths() -> void:
	Upgrades.reset()
	TestLib.check(Upgrades.IDS.size() == 7 and Upgrades.MAX_LEVEL == 5 and Upgrades.decoy_bonus() == 0.0, "seven upgrades (incl. decoy), five levels each, decoy neutral at 0")
	TestLib.check(is_equal_approx(Upgrades.damage_mult(), 1.0) and Upgrades.mag_size() == 30 and is_equal_approx(Upgrades.reload_mult(), 1.0) and Upgrades.blink_bonus() == 0.0 \
			and is_equal_approx(Upgrades.regen_mult(), 1.0) and is_equal_approx(Upgrades.damage_taken(), 1.0), "level 0 is neutral everywhere")
	Upgrades.set_levels({&"damage": 5, &"mag": 5, &"reload": 5, &"blink": 5, &"regen": 5, &"armour": 5})
	TestLib.check(is_equal_approx(Upgrades.damage_mult(), 1.6) and Upgrades.mag_size() == 60 and is_equal_approx(Upgrades.reload_mult(), 0.4) and is_equal_approx(Upgrades.blink_bonus(), 40.0) \
			and is_equal_approx(Upgrades.regen_mult(), 2.0) and is_equal_approx(Upgrades.damage_taken(), 0.6), "level 5: +60 %% damage, 60 rounds, 40 %% reload time, +40 m blink, x2 regen, -40 %% damage taken")
	Upgrades.set_levels({&"damage": 99, &"bogus": 3, &"mag": -4})
	TestLib.check(Upgrades.level(&"damage") == 5 and Upgrades.level(&"mag") == 0 and Upgrades.total_levels() == 5, "levels are clamped and unknown ids dropped")
	Upgrades.reset()
	var prev := 0
	var rising := true
	for lvl in 5:
		var c := Upgrades.cost(&"damage", lvl)
		rising = rising and c > prev and c % 5 == 0
		prev = c
	TestLib.check(rising and Upgrades.cost(&"damage", 0) == Economy.upgrade_base(&"damage") and Upgrades.cost(&"damage", 4) > 4 * Upgrades.cost(&"damage", 0), "costs rise per level and are multiples of 5")
	TestLib.check(Upgrades.cost(&"damage", 5) == -1 and Upgrades.price(&"damage", 5) == -1 and Upgrades.cost(&"mag", -1) == -1, "no price beyond the last level")
	TestLib.check(Upgrades.price(&"damage", 0, 0.2) < Upgrades.price(&"damage", 0, 0.0) and Upgrades.price(&"damage", 0, -0.1) > Upgrades.price(&"damage", 0, 0.0) and Upgrades.price(&"damage", 0, 0.0) == Upgrades.cost(&"damage", 0), "reputation moves the price: LEGEND cheaper, SUSPECT dearer")
	TestLib.check(Upgrades.price(&"mag", 0, 0.99) >= 5, "a price is never below 5")
	TestLib.check(Upgrades.effect_text(&"mag", 0) == "30 ROUNDS  >  36 ROUNDS" and Upgrades.effect_text(&"damage", 5) == "160% DAMAGE" and "100% DAMAGE" in Upgrades.effect_text(&"damage", 0), "the shop row shows what the next level changes")
	var texts_ok := true
	for id: StringName in Upgrades.IDS:
		for lvl in 6:
			texts_ok = texts_ok and Upgrades.effect_text(id, lvl) != "" and Upgrades.effect_text(id, lvl).length() <= 44
	TestLib.check(texts_ok, "every row text exists and fits a phone line (44 characters)")


func _wallet_and_shop() -> void:
	_fresh()
	var bought: Array = []
	prog.purchased.connect(func(id: StringName, lvl: int) -> void: bought.append([id, lvl]))
	TestLib.check(not prog.can_buy(&"damage") and not prog.buy(&"damage") and prog.credits == 0, "with no credits nothing can be bought")
	prog.add_credits(2000)
	TestLib.check(prog.credits == 2000 and prog.can_buy(&"damage"), "credits arrive")
	TestLib.check(prog.buy(&"damage") and prog.credits == 2000 - Economy.upgrade_base(&"damage") and prog.level(&"damage") == 1 and is_equal_approx(Upgrades.damage_mult(), 1.12), "buying damage level 1 costs 240 and raises damage +12 %%")
	TestLib.check(bought.size() == 1 and bought[0][0] == &"damage" and bought[0][1] == 1, "the purchase signal fires")
	var p2 := prog.price(&"damage")
	var left := prog.credits - p2
	TestLib.check(p2 == Upgrades.cost(&"damage", 1) and prog.buy(&"damage") and prog.credits == left, "level 2 costs %d" % p2)
	TestLib.check(prog.price(&"damage") > prog.credits and not prog.buy(&"damage") and prog.credits == left and prog.level(&"damage") == 2, "level 3 is too dear: nothing changes")
	TestLib.check(not prog.buy(&"nonsense") and not prog.can_buy(&"nonsense"), "an unknown id is refused")
	prog.add_credits(10000)
	for i in 3:
		prog.buy(&"damage")
	TestLib.check(prog.level(&"damage") == 5 and not prog.can_buy(&"damage") and not prog.buy(&"damage"), "the top level cannot be bought again")
	var credits := prog.credits
	TestLib.check(prog.spend(100) and prog.credits == credits - 100 and not prog.spend(10 ** 9) and prog.credits == credits - 100, "spend() refuses what the wallet cannot cover")
	prog.add_credits(-10 ** 9)
	TestLib.check(prog.credits == 0, "the wallet never goes below zero")
	# free upgrades
	var g := prog.grant_upgrade(&"regen")
	TestLib.check(g == &"regen" and prog.level(&"regen") == 1, "a granted upgrade adds a level for free")
	for i in 40:
		prog.grant_upgrade()
	TestLib.check(Upgrades.total_levels() == Upgrades.IDS.size() * Upgrades.MAX_LEVEL and prog.grant_upgrade() == &"", "random grants fill every upgrade and then stop")
	_fresh()


func _reputation() -> void:
	TestLib.check(Progress.rep_tier(-5) == 0 and Progress.rep_tier(0) == 1 and Progress.rep_tier(9) == 1 and Progress.rep_tier(10) == 2 and Progress.rep_tier(39) == 2 and Progress.rep_tier(40) == 3, "reputation tiers: <0 SUSPECT, 0 UNKNOWN, 10 TRUSTED, 40 LEGEND")
	TestLib.check(Progress.rep_name(50) == "LEGEND" and Progress.rep_name(-1) == "SUSPECT", "tier names")
	TestLib.check(Progress.rep_discount(-1) == -0.1 and Progress.rep_discount(0) == 0.0 and Progress.rep_discount(12) == 0.1 and Progress.rep_discount(60) == 0.2, "shop discounts -10 / 0 / 10 / 20 %%")
	TestLib.check(Progress.rep_bonus(-1) == -0.1 and Progress.rep_bonus(60) == 0.25, "contract pay factors -10 .. +25 %%")
	_fresh()
	prog.add_reputation(500)
	TestLib.check(prog.reputation == Progress.REP_MAX, "reputation is capped at %d" % Progress.REP_MAX)
	prog.add_reputation(-5000)
	TestLib.check(prog.reputation == Progress.REP_MIN, "and floored at %d" % Progress.REP_MIN)
	prog.add_credits(2000)
	TestLib.check(prog.price(&"damage") == Upgrades.price(&"damage", 0, -0.1), "a SUSPECT pays more in the shop")
	prog.reputation = 40
	TestLib.check(prog.price(&"damage") == Upgrades.price(&"damage", 0, 0.2) and prog.buy(&"damage") and prog.credits == 2000 - Upgrades.price(&"damage", 0, 0.2), "a LEGEND buys at 20 %% off")
	_fresh()


# --- upgrades on the real player -----------------------------------------------------------------------------------------

func _effects(_host: Node) -> void:
	_fresh()
	var d := Fixture.add_dummy(e.root, Vector3(-23.0, 0.0, 4.0), 1.0, true)
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	await e.shoot_dummy(d, -0.3, 1.0)
	TestLib.check(d.hits.size() == 1 and absf(d.hits[0].x - 14.0) < 0.001, "baseline shot: 14 damage")
	Upgrades.set_levels({&"damage": 5})
	p.weapon.reset()
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	d.hits.clear()
	await e.shoot_dummy(d, -0.3, 1.0)
	TestLib.check(d.hits.size() == 1 and absf(d.hits[0].x - 14.0 * 1.6) < 0.01, "damage level 5: %.1f per shot (x1.6)" % (d.hits[0].x if d.hits.size() > 0 else 0.0))
	Upgrades.reset()
	# magazine and reload
	prog.add_credits(5000)
	p.weapon.reset()
	prog.buy(&"mag")
	prog.buy(&"mag")
	TestLib.check(p.mag == 42 and p.ammo == 42, "buying magazine upgrades applies at once to the live player, new rounds included (%d / %d)" % [p.ammo, p.mag])
	p.weapon.reset()
	TestLib.check(p.mag == 42 and p.ammo == 42, "a reset keeps the bigger magazine (%d / %d)" % [p.ammo, p.mag])
	Upgrades.set_levels({&"reload": 5})
	p.weapon.reset()
	p.weapon.ammo = 10
	Input.action_press(&"reload")
	await e.frames(2)
	Input.action_release(&"reload")
	TestLib.check(p.reloading and p.weapon.reload_t <= 1.3 * 0.4 + 0.02, "reload level 5: %.2f s instead of 1.3 s" % p.weapon.reload_t)
	await e.secs(0.7)
	TestLib.check(not p.reloading, "and it is over after about half a second")
	# armour
	Upgrades.reset()
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	p.invuln = 0.0
	var hp0 := p.hp
	p.damage(10.0)
	TestLib.check(is_equal_approx(hp0 - p.hp, 10.0), "baseline hit: 10 damage")
	Upgrades.set_levels({&"armour": 5})
	p.invuln = 0.0
	hp0 = p.hp
	p.damage(10.0)
	TestLib.check(is_equal_approx(hp0 - p.hp, 6.0), "armour level 5: the same hit does 6")
	# coherence regeneration
	Upgrades.reset()
	await e.prep(Vector3(-30.0, 0.0, 4.0))
	p.energy = 0.0
	await e.secs(1.0)
	var base_gain := p.energy
	Upgrades.set_levels({&"regen": 5})
	p.energy = 0.0
	await e.secs(1.0)
	TestLib.check(p.energy > base_gain * 1.7 and base_gain > 5.0, "coherence regen level 5: %.1f instead of %.1f per second" % [p.energy, base_gain])
	# blink range
	Upgrades.reset()
	await e.prep(Vector3(-30.0, 0.0, 4.0), PI * 0.5, 0.0)
	p.energy = p.max_energy
	var q := p.quantum as Quantum
	q.reset()
	q.blink()
	var near := Vector2(q.beacon_pos.x - p.global_position.x, q.beacon_pos.z - p.global_position.z).length()
	q.reset()
	Upgrades.set_levels({&"blink": 5})
	p.energy = p.max_energy
	await e.prep(Vector3(-30.0, 0.0, 4.0), PI * 0.5, 0.0)
	q.blink()
	var far := Vector2(q.beacon_pos.x - p.global_position.x, q.beacon_pos.z - p.global_position.z).length()
	TestLib.check(near > 35.0 and absf((far - near) - 40.0) < 4.0, "blink range level 5 reaches 40 m further (%.0f m -> %.0f m)" % [near, far])
	q.reset()
	Upgrades.reset()
	d.queue_free()
	_fresh()


func _credits_from_score() -> void:
	_fresh()
	Game.score = 0
	prog._last_score = 0
	Game.score = 100
	TestLib.check(prog.credits == 40, "a score of 100 pays 40 credits (%d)" % prog.credits)
	Game.score += 2
	Game.score += 2
	Game.score += 1
	TestLib.check(prog.credits == 42, "small gains are accumulated, not lost (%d)" % prog.credits)
	var c0 := prog.credits
	Game.score = 0
	TestLib.check(prog.credits == c0, "a score reset pays nothing")
	prog.bonus_score(100)
	TestLib.check(prog.credits == c0 and Game.score == 100, "a bonus score does not pay credits twice")
	Game.score = 0
	_fresh()


# --- save and load -------------------------------------------------------------------------------------------------------

func _save_load() -> void:
	_fresh()
	prog.credits = 777
	prog.reputation = 23
	prog.sector = 3
	prog.best = 4321
	prog.tutorial_done = true
	prog.contracts_done = 7
	prog.contracts_failed = 2
	prog.levels = Upgrades.set_levels({&"damage": 3, &"armour": 2, &"blink": 5})
	TestLib.check(prog.save_file() and FileAccess.file_exists(TMP), "save_file writes the ConfigFile")
	TestLib.check(prog.has_save(), "has_save sees it")
	var other := Progress.new()
	other.path = TMP
	other.autosave_enabled = false
	Upgrades.reset()
	TestLib.check(other.load_file(), "load_file reads it back")
	TestLib.check(other.credits == 777 and other.reputation == 23 and other.sector == 3 and other.best == 4321 and other.tutorial_done and other.contracts_done == 7 and other.contracts_failed == 2, "credits, reputation, sector, best, tutorial flag and tallies round-trip")
	TestLib.check(Upgrades.level(&"damage") == 3 and Upgrades.level(&"armour") == 2 and Upgrades.level(&"blink") == 5 and Upgrades.level(&"mag") == 0, "upgrade levels round-trip into the live state")
	TestLib.check(other.level(&"damage") == 3 and other.price(&"damage") == Upgrades.price(&"damage", 3, 0.1), "the loaded node prices from its levels and reputation")
	other.free()
	# a damaged file changes nothing
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("this is not a config file [[[")
	f.close()
	var bad := Progress.new()
	bad.path = TMP
	bad.credits = 5
	TestLib.check(not bad.load_file() and bad.credits == 5 and not bad.has_save(), "a damaged save is refused and changes nothing")
	f = FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("[meta]\nversion=99\n[wallet]\ncredits=999\n")
	f.close()
	TestLib.check(not bad.load_file() and bad.credits == 5 and not bad.has_save(), "a save of a foreign version is refused")
	f = FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("[meta]\nversion=1\n[wallet]\ncredits=-50\nreputation=9999\n[upgrades]\ndamage=77\n[campaign]\nsector=-3\n")
	f.close()
	TestLib.check(bad.load_file() and bad.credits == 0 and bad.reputation == Progress.REP_MAX and Upgrades.level(&"damage") == 5 and bad.sector == 0, "absurd values are clamped on load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	TestLib.check(not bad.load_file() and not bad.has_save(), "a missing file loads nothing")
	bad.free()
	Upgrades.reset()
	_fresh()


# --- autosave, new game, continue --------------------------------------------------------------------------------------

func _read_cfg() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(TMP)
	return cf


func _autosave() -> void:
	_fresh()
	prog.autosave_enabled = true
	story.chapter = 2
	prog.credits = 321
	Game.state = &"play"
	Game.state = &"paused"
	var cf := _read_cfg()
	TestLib.check(FileAccess.file_exists(TMP) and int(cf.get_value("wallet", "credits", -1)) == 321 and int(cf.get_value("campaign", "sector", -1)) == 2, "pausing autosaves (credits 321, sector 2)")
	Game.state = &"play"
	prog.credits = 400
	Game.state = &"dead"
	TestLib.check(int(_read_cfg().get_value("wallet", "credits", -1)) == 400, "dying autosaves")
	Game.state = &"play"
	Game.state = &"win"
	Game.sector_cleared.emit()
	cf = _read_cfg()
	TestLib.check(int(cf.get_value("campaign", "sector", -1)) == 3, "clearing a sector saves the NEXT sector (3)")
	prog.add_credits(1000)
	prog.buy(&"armour")
	cf = _read_cfg()
	TestLib.check(int(cf.get_value("upgrades", "armour", 0)) == 1, "a purchase is saved at once")
	prog.mark_tutorial_done()
	TestLib.check(bool(_read_cfg().get_value("flags", "tutorial_done", false)), "finishing the tutorial is saved")
	Game.state = &"play"
	prog.autosave_enabled = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	Game.state = &"paused"
	Game.state = &"play"
	TestLib.check(not FileAccess.file_exists(TMP), "with autosave off (tools, tests, bots) nothing is written")
	_fresh()


func _new_vs_continue() -> void:
	_fresh()
	prog.autosave_enabled = true
	# a played campaign, saved
	story.chapter = 3
	prog.credits = 900
	prog.reputation = 31
	prog.tutorial_done = true
	prog.best = 5000
	prog.levels = Upgrades.set_levels({&"mag": 2, &"regen": 1})
	prog.sector = 3
	prog.save_file()
	# the title screen
	Game.state = &"menu"
	TestLib.check(prog.has_save(), "the title screen finds the save")
	prog.credits = 0
	prog.reputation = 0
	prog.levels = Upgrades.set_levels({})
	prog.sector = 0
	story.set_to = -1
	var flag := [false]
	var on_new := func() -> void: flag[0] = true
	Game.new_game.connect(on_new)
	TestLib.check(prog.continue_game(), "CONTINUE starts a run")
	Game.new_game.disconnect(on_new)
	TestLib.check(flag[0] and Game.state == &"play", "it goes through the normal new game flow")
	TestLib.check(prog.credits == 900 and prog.reputation == 31 and Upgrades.level(&"mag") == 2 and Upgrades.level(&"regen") == 1, "credits, reputation and upgrades are restored")
	TestLib.check(story.set_to == 3 and story.chapter == 3, "the story resumes at the saved chapter (4)")
	TestLib.check(m.rounds == 4 and m.total == mini(Missions.CORE_MAX, 9) and m.cores.size() == 9, "the sector's cores are rebuilt for sector 4 (%d cores)" % m.cores.size())
	TestLib.check(p.mag == 42 and p.ammo <= p.mag, "the bigger magazine is on the live player")
	TestLib.check(prog.best == 5000 and prog.tutorial_done, "best score and tutorial flag survive")
	# continue is refused outside the title and without a save
	TestLib.check(not prog.continue_game(), "CONTINUE only works from the title screen")
	Game.state = &"menu"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	prog.autosave_enabled = true
	TestLib.check(not prog.has_save() and not prog.continue_game(), "without a save there is nothing to continue")
	# NEW GAME wipes the campaign but keeps the tutorial flag and the best score
	prog.credits = 500
	prog.reputation = 20
	prog.levels = Upgrades.set_levels({&"damage": 2})
	prog.sector = 2
	prog.tutorial_done = true
	prog.best = 777
	Game.start_new_game()
	TestLib.check(prog.credits == 0 and prog.reputation == 0 and Upgrades.total_levels() == 0 and prog.sector == 0, "a new game starts from nothing")
	TestLib.check(prog.tutorial_done and prog.best == 777, "but the tutorial is not repeated and the best score stays")
	TestLib.check(m.rounds == 1 and m.cores.size() == 6, "and sector 1 has 6 cores")
	prog.autosave_enabled = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_fresh()
