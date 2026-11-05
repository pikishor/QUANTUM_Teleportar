extends RefCounted
## Weapon crafting and mods (scripts/progress/crafting.gd, scripts/ui/craft_screen.gd) in the REAL scene (main.tscn): data and Economy prices, the pure roll (rarity, stats, perks, determinism),
## craft / boost / inventory cap / dismantle / equip rules, the equipped item in the live weapon definition, the three perks working on real enemies (CHAIN ARC, PHASE ROUNDS, SINGULARITY ON CRIT)
## and their skill tree synergy, drops from real kills, loot pickups and side jobs, the tech vendor, the save round trip (and damaged / missing sections), the workbench screen opened from the
## shop and from a safehouse (64 px buttons, inside the screen, no overlaps, craft and equip through the buttons) and the DEMO entries.
## Progress writes to a throw-away file; waits are on state or counters. Not run: a phone, the feel of the screens, contract / heist / interior payouts (their hook lines are source-checked).
## Run: tools/test.sh tests/test_weapon_crafting.gd

const TMP := "user://test_weapon_crafting_save.cfg"
const DT := 1.0 / 60.0

var host: Node
var main: Node
var prog: Progress
var p: Player
var w: PlayerWeapon
var hud: Hud


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	_data()
	_roll()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 30)
	p = Game.player as Player
	prog = Game.progress as Progress
	w = p.weapon if p != null else null
	for n in main.find_children("*", "Hud", true, false):
		hud = n as Hud
	TestLib.check(p != null and prog != null and w != null and hud != null, "main.tscn composes the player, the weapon, progress and the HUD")
	if p == null or prog == null or w == null or hud == null:
		return
	prog.path = TMP
	prog.autosave_enabled = false
	prog.new_campaign()
	Game.state = &"play"
	TestMode.reset_toggles()
	TestMode.god = true
	TestMode.freeze = true
	TestMode.infinite_ammo = true
	_rules()
	await _live_weapon()
	await _perks()
	await _drops()
	_vendor()
	_save_roundtrip()
	await _screens()
	await _demo()
	Game.state = &"play"
	TestMode.reset_toggles()
	prog.new_campaign()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


# --- helpers ------------------------------------------------------------------------------------------------------------

func _fresh() -> void:
	prog.new_campaign()
	prog.credits = 1000000
	Crafting.rng.seed = 4242


func _give(scrap: int, alloy: int, core: int) -> void:
	Crafting.parts = {&"scrap": scrap, &"alloy": alloy, &"core": core}


## An item with fixed stats (no randomness), added to the inventory.
func _item(bp: StringName, rarity: int, stats: Dictionary, perk := &"") -> int:
	var it := Crafting.make_item(bp, rarity, 7)
	it["stats"] = stats
	it["perk"] = perk
	Crafting.add_item(it)
	return int(it["uid"])


func _idle(sec: float) -> void:
	var t := 0.0
	while t < sec:
		w.tick(DT, false, false, false, false)
		t += DT


func _target(dist: float, side := 0.0, type := &"heavy") -> Drone:
	var fwd := -p.camera_rig.camera.global_basis.z
	var right := p.camera_rig.camera.global_basis.x
	var at := p.camera_rig.camera.global_position + fwd * dist + right * side
	var d := (Game.enemies as EnemyManager).spawn(type, at, true)
	TestLib.check(d != null, "an enemy could be spawned")
	d.global_position = at - Vector3(0.0, d.center_y, 0.0)
	d.max_hp = 100000.0
	d.hp = d.max_hp
	return d


# --- data ---------------------------------------------------------------------------------------------------------------

func _data() -> void:
	var ids := Crafting.bp_ids()
	TestLib.check(ids.size() == Crafting.MOD_ORDER.size() + WeaponDefs.IDS.size(), "a blueprint per mod and per weapon (%d)" % ids.size())
	for id: StringName in ids:
		TestLib.check(Crafting.is_bp(id) and Crafting.bp_title(id) != "UNKNOWN" and Crafting.bp_short(id) != "", "%s is a blueprint with a name" % id)
		TestLib.check(Economy.blueprint_price(id) >= 0, "%s has an Economy blueprint price" % id)
		TestLib.check(not Crafting.parts_for(id).is_empty() and Crafting.cost_of(id)["credits"] > 0, "%s has a recipe and a fee" % id)
	for k: StringName in Crafting.START_KNOWN:
		TestLib.check(Economy.blueprint_price(k) == 0, "the starter blueprint %s is free" % k)
	TestLib.check(Economy.blueprint_price(&"mod_arc") < Economy.blueprint_price(&"mod_singularity"), "a stronger mod blueprint costs more")
	TestLib.check(Economy.blueprint_price(&"var_minigun") > Economy.blueprint_price(&"var_scatter"), "a dearer weapon has a dearer variant blueprint")
	for id: StringName in Crafting.PART_IDS:
		TestLib.check(Economy.craft_part_price(id) > 0 and Economy.CRAFT_PART_BUNDLE.has(id) and Crafting.PART_NAME.has(id), "part %s is priced and named" % id)
	TestLib.check(Economy.craft_part_price(&"scrap") < Economy.craft_part_price(&"alloy") and Economy.craft_part_price(&"alloy") < Economy.craft_part_price(&"core"), "parts rise in price")
	for r in Crafting.RARITY_NAME.size():
		TestLib.check(Economy.DISMANTLE_YIELD[r].size() >= 1, "rarity %d returns parts" % r)
	for perk: StringName in Crafting.PERK_IDS:
		TestLib.check(Crafting.PERKS.has(perk) and SkillTree.NODES.has(Crafting.PERKS[perk]["skill"]), "perk %s links to a real skill node" % perk)
	TestLib.check(Crafting.PERKS.has(&"chain_arc") and Crafting.PERKS.has(&"phase_rounds") and Crafting.PERKS.has(&"singularity_crit"), "the three quantum perks exist")
	for src: StringName in Crafting.DROPS:
		TestLib.check((Crafting.DROPS[src] as Dictionary).has("bp"), "drop source %s has a blueprint chance" % src)
	TestLib.check(float(Crafting.DROPS[&"boss"]["bp"]) > float(Crafting.DROPS[&"kill"]["bp"]), "bosses drop blueprints more often than grunts")
	for r in Crafting.RARITY_COLOR.size():
		TestLib.check(Crafting.RARITY_COLOR[r].a > 0.0, "rarity %d has a colour" % r)


func _roll() -> void:
	TestLib.check(Crafting.roll_rarity(false, 0.0) == 0 and Crafting.roll_rarity(false, 1.0) == 3, "the rarity roll spans COMMON to LEGENDARY")
	var rare_plus := 0
	var rare_plus_boost := 0
	for i in 200:
		var r := float(i) / 200.0
		rare_plus += 1 if Crafting.roll_rarity(false, r) >= 2 else 0
		rare_plus_boost += 1 if Crafting.roll_rarity(true, r) >= 2 else 0
	TestLib.check(rare_plus_boost > rare_plus, "BOOST shifts the odds toward EPIC and LEGENDARY (%d vs %d)" % [rare_plus_boost, rare_plus])
	var mean := []
	for r in 4:
		var total := 0.0
		var n := 0
		for sd in 40:
			var it := Crafting.make_item(&"mod_basic", r, 100 + sd)
			TestLib.check((it["stats"] as Dictionary).size() == Crafting.MOD_STAT_COUNT[r], "a rarity %d mod rolls %d stats" % [r, Crafting.MOD_STAT_COUNT[r]])
			for k: String in it["stats"]:
				var v := float(it["stats"][k])
				var dir := float(Crafting.STATS[k][0])
				TestLib.check(v >= Crafting.STAT_MIN and v <= Crafting.STAT_MAX and (v - 1.0) * dir > 0.0, "stat %s=%.3f improves the weapon and stays in range" % [k, v])
				total += absf(v - 1.0)
				n += 1
		mean.append(total / float(maxi(n, 1)))
	TestLib.check(float(mean[0]) < float(mean[1]) and float(mean[1]) < float(mean[2]) and float(mean[2]) < float(mean[3]), "a higher rarity rolls bigger stats")
	var a := Crafting.make_item(&"mod_arc", 2, 99)
	var b := Crafting.make_item(&"mod_arc", 2, 99)
	TestLib.check(a == b, "the same blueprint, rarity and seed make the same item")
	TestLib.check(Crafting.make_item(&"mod_arc", 0, 5)["perk"] == &"chain_arc" and Crafting.make_item(&"mod_phase", 0, 5)["perk"] == &"phase_rounds" and Crafting.make_item(&"mod_singularity", 0, 5)["perk"] == &"singularity_crit", "the perk blueprints always carry their perk")
	var plain_perks := 0
	var epic_perks := 0
	for sd in 30:
		plain_perks += 1 if Crafting.make_item(&"mod_basic", 0, sd)["perk"] != &"" else 0
		epic_perks += 1 if Crafting.make_item(&"mod_basic", 3, sd)["perk"] != &"" else 0
	TestLib.check(plain_perks == 0 and epic_perks == 30, "a COMMON tuned mod has no perk, a LEGENDARY always has one")
	var v := Crafting.make_item(&"var_carbine", 1, 3)
	TestLib.check(v["kind"] == &"variant" and v["base"] == &"carbine" and (v["stats"] as Dictionary).size() == Crafting.MOD_STAT_COUNT[1] + Crafting.VARIANT_EXTRA, "a variant is bound to its weapon and rolls an extra stat")
	TestLib.check(Crafting.make_item(&"nonsense", 0, 1).is_empty(), "an unknown blueprint makes nothing")
	TestLib.check(Crafting.stat_text("interval", 0.8) == "FIRE RATE +25%" and Crafting.stat_text("damage", 1.1) == "DAMAGE +10%" and Crafting.stat_text("reload", 0.9) == "RELOAD -10%", "stat lines read as player-facing percentages")


# --- rules --------------------------------------------------------------------------------------------------------------

func _rules() -> void:
	_fresh()
	Crafting.reset()
	TestLib.check(Crafting.knows(&"mod_basic") and Crafting.knows(&"var_carbine") and not Crafting.knows(&"mod_arc"), "a new campaign starts with two blueprints")
	_give(0, 0, 0)
	TestLib.check(Crafting.why_not(prog, &"mod_arc") == "BLUEPRINT NOT FOUND" and Crafting.craft(prog, &"mod_arc").is_empty(), "an unknown blueprint cannot be crafted")
	TestLib.check(Crafting.why_not(prog, &"mod_basic") == "NEED MORE PARTS" and Crafting.craft(prog, &"mod_basic").is_empty(), "no parts, no craft")
	_give(10, 10, 10)
	prog.credits = 0
	TestLib.check(Crafting.why_not(prog, &"mod_basic") == "NEED MORE CREDITS" and Crafting.craft(prog, &"mod_basic").is_empty(), "no credits, no craft")
	prog.credits = 100000
	var c0 := prog.credits
	var fee := Crafting.fee(&"mod_basic")
	var it := Crafting.craft(prog, &"mod_basic")
	TestLib.check(not it.is_empty() and int(it["uid"]) > 0 and Crafting.items.size() == 1, "a tuned mod is crafted into the inventory")
	TestLib.check(Crafting.part_count(&"scrap") == 10 - 3 and Crafting.part_count(&"alloy") == 10 and prog.credits == c0 - fee, "its parts and fee were spent exactly")
	TestLib.check(fee == Crafting.cost_of(&"mod_basic")["credits"] and fee >= Economy.craft_fee(&"mod") / 2, "the fee is the Economy fee")
	TestLib.check(Crafting.why_not(prog, &"var_carbine") == "" and not Crafting.craft(prog, &"var_carbine").is_empty(), "a starter variant is crafted")
	Crafting.learn(&"var_scatter")
	TestLib.check(Crafting.why_not(prog, &"var_scatter").begins_with("NEEDS "), "a variant needs its weapon")
	Crafting.learn(&"mod_singularity")
	_give(10, 10, 5)
	var cost_boost := Crafting.cost_of(&"mod_singularity", true)
	var cost_plain := Crafting.cost_of(&"mod_singularity", false)
	TestLib.check(int(cost_boost["parts"][&"core"]) == int(cost_plain["parts"][&"core"]) + Economy.CRAFT_BOOST_CORES, "BOOST costs one extra core")
	var made := Crafting.craft(prog, &"mod_singularity", true)
	TestLib.check(not made.is_empty() and Crafting.part_count(&"core") == 5 - int(cost_boost["parts"][&"core"]), "a boosted craft spends the extra core")
	TestLib.check(made["perk"] == &"singularity_crit", "the singularity blueprint gives its perk")
	# bench discount from a safehouse
	var plain_fee := Crafting.fee(&"mod_basic")
	prog.safehouses_owned.append(&"loft")
	prog.safehouse_lv["loft:bench"] = 2
	TestLib.check(Crafting.bench_level() == 2 and Crafting.fee(&"mod_basic") < plain_fee, "a BENCH upgrade discounts the fee (%d to %d)" % [plain_fee, Crafting.fee(&"mod_basic")])
	prog.safehouses_owned.clear()
	prog.safehouse_lv.clear()
	# equip rules
	var mod_uid := _item(&"mod_basic", 1, {"damage": 1.1})
	TestLib.check(Crafting.equip(prog, mod_uid, &"carbine") and Crafting.equipped_on(mod_uid) == &"carbine", "a mod is equipped on the carbine")
	WeaponDefs.unlock(&"scatter")
	TestLib.check(Crafting.equip(prog, mod_uid, &"scatter") and Crafting.equipped_on(mod_uid) == &"scatter" and not Crafting.has_gear(&"carbine"), "moving a mod frees the old weapon")
	TestLib.check(not Crafting.equip(prog, mod_uid, &"rail"), "a weapon you do not own takes no mod")
	TestLib.check(not Crafting.equip(prog, 9999, &"carbine"), "an unknown item is refused")
	var var_uid := _item(&"var_carbine", 1, {"damage": 1.1})
	TestLib.check(Crafting.equip(prog, var_uid, &"scatter") and Crafting.equipped_on(var_uid) == &"carbine", "a variant goes on its own weapon whatever weapon is named")
	TestLib.check(Crafting.unequip(prog, var_uid) and not Crafting.has_gear(&"carbine") and not Crafting.unequip(prog, var_uid), "unequip frees the slot once")
	# dismantle
	var leg := _item(&"mod_arc", 3, {"damage": 1.2}, &"chain_arc")
	Crafting.equip(prog, leg, &"carbine")
	_give(0, 0, 0)
	var y := Crafting.dismantle(prog, leg)
	TestLib.check(not y.is_empty() and Crafting.part_count(&"scrap") == int(Economy.DISMANTLE_YIELD[3][&"scrap"]) and Crafting.part_count(&"core") == int(Economy.DISMANTLE_YIELD[3][&"core"]), "dismantling a LEGENDARY returns its parts")
	TestLib.check(Crafting.item(leg).is_empty() and not Crafting.has_gear(&"carbine") and Crafting.dismantle(prog, leg).is_empty(), "the item is gone and unequipped, and cannot be dismantled twice")
	# inventory cap
	while Crafting.items.size() < Crafting.ITEM_CAP:
		_item(&"mod_basic", 0, {"damage": 1.05})
	_give(50, 50, 50)
	TestLib.check(Crafting.why_not(prog, &"mod_basic") == "INVENTORY FULL" and Crafting.craft(prog, &"mod_basic").is_empty() and Crafting.part_count(&"scrap") == 50, "a full inventory refuses a craft and keeps the parts")
	# supply
	_fresh()
	Crafting.reset()
	prog.credits = 0
	TestLib.check(not Crafting.buy_part(prog, &"scrap") and not Crafting.buy_blueprint(prog, &"mod_arc"), "supply needs credits")
	prog.credits = 100000
	var cr := prog.credits
	TestLib.check(Crafting.buy_part(prog, &"alloy") and Crafting.part_count(&"alloy") == int(Economy.CRAFT_PART_BUNDLE[&"alloy"]) and prog.credits == cr - Crafting.part_price(&"alloy", prog), "a part bundle is bought at its price")
	TestLib.check(Crafting.buy_blueprint(prog, &"mod_arc") and Crafting.knows(&"mod_arc") and not Crafting.buy_blueprint(prog, &"mod_arc"), "a blueprint is bought once")
	TestLib.check(not Crafting.buy_blueprint(prog, &"nonsense") and not Crafting.buy_part(prog, &"nonsense"), "an unknown supply entry is refused")


# --- live weapon --------------------------------------------------------------------------------------------------------

func _live_weapon() -> void:
	_fresh()
	Crafting.reset()
	Attachments.reset()
	SkillTree.reset()
	w.switch_to(&"carbine", true)
	await TestLib.frames(host, 2)
	var base := WeaponDefs.def(&"carbine")
	var d0 := float(w.def["damage"])
	TestLib.check(is_equal_approx(d0, float(base["damage"])), "the carbine starts at its base damage")
	var uid := _item(&"mod_basic", 1, {"damage": 1.25, "mag": 1.4, "interval": 0.8, "reload": 0.9})
	TestLib.check(prog.equip_part(&"carbine", &"reddot") == false, "(attachments untouched: the red dot is not owned)")
	TestLib.check(Crafting.equip(prog, uid, &"carbine"), "the mod is equipped")
	TestLib.check(is_equal_approx(float(w.def["damage"]), d0 * 1.25) and is_equal_approx(float(w.def["interval"]), float(base["interval"]) * 0.8), "the live weapon definition carries the mod's stats")
	TestLib.check(int(w.def["mag"]) == int(roundf(float(base["mag"]) * 1.4)) and w.mag >= int(base["mag"]), "the magazine follows (%d)" % w.mag)
	TestLib.check(is_equal_approx(float(WeaponDefs.def(&"carbine")["damage"]), d0), "the base definitions are never changed")
	var vid := _item(&"var_carbine", 2, {"damage": 1.2, "crit": 1.2})
	Crafting.equip(prog, vid, &"carbine")
	TestLib.check(is_equal_approx(float(w.def["damage"]), d0 * 1.2 * 1.25), "variant and mod stack (%.2f)" % float(w.def["damage"]))
	# attachments stack too
	Attachments.give(&"overcharge")
	prog.equip_part(&"carbine", &"overcharge")
	TestLib.check(is_equal_approx(float(w.def["damage"]), d0 * 1.2 * 1.25 * 1.2), "crafted gear stacks with attachment parts")
	# shots in the real scene hit for the crafted damage
	(Game.enemies as EnemyManager).clear()
	var t := _target(14.0)
	_idle(1.0)
	var hp0 := t.hp
	var tries := 0
	while t.hp >= hp0 and tries < 10:
		_idle(0.3)
		w.tick(DT, true, false, true, false)
		tries += 1
	TestLib.check(t.hp < hp0 and hp0 - t.hp >= d0 * 1.2, "a real shot lands for at least the crafted damage (%.1f)" % (hp0 - t.hp))
	Crafting.unequip(prog, uid)
	Crafting.unequip(prog, vid)
	TestLib.check(is_equal_approx(float(w.def["damage"]), d0 * 1.2), "unequipping returns the weapon to its parts-only numbers")
	prog.equip_part(&"carbine", &"overcharge")
	(Game.enemies as EnemyManager).clear()


func _perks() -> void:
	_fresh()
	Crafting.reset()
	Attachments.reset()
	SkillTree.reset()
	w.switch_to(&"carbine", true)
	(Game.enemies as EnemyManager).clear()
	# CHAIN ARC
	TestLib.check(not w.def.has("chain"), "the carbine does not chain")
	var arc := _item(&"mod_arc", 1, {"damage": 1.05}, &"chain_arc")
	Crafting.equip(prog, arc, &"carbine")
	var jumps := int(w.def.get("chain", 0))
	TestLib.check(jumps >= 1 and float(w.def["chain_range"]) >= 5.9, "CHAIN ARC gives the carbine a chain (%d jumps)" % jumps)
	var ta := _target(14.0)
	var tb := _target(14.0, 4.0)
	var far := _target(14.0, 40.0)
	var ch0 := w.chain_hits
	var hp_a := ta.hp
	var tries := 0
	while ta.hp >= hp_a and tries < 10:
		_idle(0.3)
		w.tick(DT, true, false, true, false)
		tries += 1
	TestLib.check(ta.hp < hp_a, "the carbine hits the aimed target")
	TestLib.check(w.chain_hits > ch0 and tb.hp < tb.max_hp, "CHAIN ARC jumps to a neighbour (%d jumps)" % (w.chain_hits - ch0))
	TestLib.check(is_equal_approx(far.hp, far.max_hp), "an enemy out of arc range is untouched")
	# skill tree synergy
	var power0 := Crafting.perk_power(&"chain_arc")
	SkillTree.ranks[&"tp_hops"] = 2
	Crafting.refresh_weapon()
	TestLib.check(is_equal_approx(Crafting.perk_power(&"chain_arc"), power0 + 2.0 * Crafting.SKILL_POTENCY), "teleport HOPS ranks add potency")
	TestLib.check(int(w.def["chain"]) == jumps + 2 and float(w.def["chain_range"]) > 6.0, "and extra arc jumps in the live weapon (%d)" % int(w.def["chain"]))
	SkillTree.reset()
	Crafting.refresh_weapon()
	TestLib.check(int(w.def["chain"]) == jumps, "a respec takes the synergy away again")
	Crafting.unequip(prog, arc)
	(Game.enemies as EnemyManager).clear()
	# PHASE ROUNDS
	TestLib.check(not bool(w.def["pierce_shield"]), "the carbine does not pierce shields")
	var control := _target(10.0, 0.0, &"shield")
	var tester := _target(10.0, 1.5, &"shield")
	var phase := _item(&"mod_phase", 1, {"range": 1.1}, &"phase_rounds")
	var r0 := float(w.def["range"])
	var blocked := control.has_method(&"shield_blocks") and bool(control.call(&"shield_blocks", p.global_position)) and bool(tester.call(&"shield_blocks", p.global_position))
	if blocked:
		var hp_c := control.hp
		w._hit_target(control, control.center(), Vector3.UP)
		TestLib.check(is_equal_approx(control.hp, hp_c), "without the perk the frontal shield absorbs the shot")
	Crafting.equip(prog, phase, &"carbine")
	TestLib.check(bool(w.def["pierce_shield"]) and float(w.def["range"]) > r0 * 1.1, "PHASE ROUNDS pierce shields and reach further")
	if blocked:
		var hp_t := tester.hp
		w._hit_target(tester, tester.center(), Vector3.UP)
		TestLib.check(tester.hp < hp_t, "a phase round goes through the frontal shield")
	else:
		TestLib.check(true, "(the shield troopers do not face the hero: shield pass-through not asserted)")
	Crafting.unequip(prog, phase)
	(Game.enemies as EnemyManager).clear()
	# SINGULARITY ON CRIT
	var sing := _item(&"mod_singularity", 2, {"damage": 1.05}, &"singularity_crit")
	Crafting.equip(prog, sing, &"carbine")
	TestLib.check(w.def.has("sing") and float(w.def["sing"]["radius"]) >= 4.0, "SINGULARITY ON CRIT adds a pull and blast")
	var victim := _target(14.0)
	var near := _target(14.0, 3.0)
	var away := _target(14.0, 30.0)
	var crit_at: Vector3 = victim.center() + Vector3(0.0, victim.radius * 0.6, 0.0)
	var n0 := w.singularities
	var near_hp := near.hp
	var near_x := near.global_position
	w._hit_target(victim, crit_at, Vector3.UP)
	TestLib.check(w.singularities == n0 + 1, "a crit opens a singularity")
	TestLib.check(near.hp < near_hp and near.global_position.distance_to(near_x) > 0.05, "it burns and pulls the neighbour")
	TestLib.check(is_equal_approx(away.hp, away.max_hp), "an enemy outside the radius is untouched")
	w._hit_target(victim, crit_at, Vector3.UP)
	TestLib.check(w.singularities == n0 + 1, "the singularity has a cooldown")
	var body_hit := victim.center() - Vector3(0.0, victim.radius * 0.6, 0.0)
	w._sing_t = 0.0
	w._hit_target(victim, body_hit, Vector3.UP)
	TestLib.check(w.singularities == n0 + 1, "a body hit (no crit) opens nothing")
	var rad0 := float(w.def["sing"]["radius"])
	SkillTree.ranks[&"co_radius"] = 3
	Crafting.refresh_weapon()
	TestLib.check(float(w.def["sing"]["radius"]) > rad0, "COLLAPSE radius ranks widen the singularity")
	SkillTree.reset()
	Crafting.unequip(prog, sing)
	Crafting.refresh_weapon()
	TestLib.check(not w.def.has("sing"), "unequipped, the perk is gone")
	(Game.enemies as EnemyManager).clear()


# --- drops --------------------------------------------------------------------------------------------------------------

func _drops() -> void:
	_fresh()
	Crafting.reset()
	var r := RandomNumberGenerator.new()
	r.seed = 1
	var got_scrap := 0
	var got_bp := 0
	for i in 400:
		var d := Crafting.roll_drop(&"kill", r)
		got_scrap += 1 if (d["parts"] as Dictionary).has(&"scrap") else 0
		got_bp += 1 if d["bp"] != &"" else 0
	TestLib.check(got_scrap > 40 and got_scrap < 200, "grunt kills drop scrap now and then (%d of 400)" % got_scrap)
	TestLib.check(got_bp < 40, "blueprints from grunts are rare (%d of 400)" % got_bp)
	var boss := Crafting.roll_drop(&"boss", r)
	TestLib.check((boss["parts"] as Dictionary).has(&"scrap") and (boss["parts"] as Dictionary).has(&"alloy"), "a boss always drops scrap and alloy")
	TestLib.check((Crafting.roll_drop(&"nonsense", r)["parts"] as Dictionary).is_empty(), "an unknown source drops nothing")
	for bp: StringName in Crafting.bp_ids():
		Crafting.learn(bp)
	var allk := Crafting.roll_drop(&"boss", RandomNumberGenerator.new())
	TestLib.check(allk["bp"] == &"", "with every blueprint known a drop never names one")
	Crafting.reset()
	# real kills
	Crafting.rng.seed = 77
	(Game.enemies as EnemyManager).clear()
	var drops0 := Crafting.drops
	var kills := 0
	while Crafting.drops == drops0 and kills < 60:
		var d := _target(12.0)
		d.max_hp = 50.0
		d.hp = 50.0
		d.damage(1000.0, false)
		kills += 1
	TestLib.check(Crafting.drops > drops0, "killing real enemies drops parts (%d kills)" % kills)
	TestLib.check(Crafting.part_count(&"scrap") + Crafting.part_count(&"alloy") + Crafting.part_count(&"core") > 0 or not Crafting.unknown_bps().is_empty(), "the drop arrived in the inventory")
	(Game.enemies as EnemyManager).clear()
	# loot pickups
	var m := Game.missions as Missions
	var d1 := Crafting.drops
	var picks := 0
	while Crafting.drops == d1 and picks < 40:
		m.drop(&"health", p.global_position + Vector3(3.0, 0.0, 0.0))
		var s: Dictionary = m.pickups.back()
		m._collect_pickup(s, m.pickups.size() - 1, p)
		picks += 1
	TestLib.check(Crafting.drops > d1, "picking up loot can drop parts (%d pickups)" % picks)
	# side jobs always pay scrap
	var sc := Crafting.part_count(&"scrap")
	prog.complete_side(&"courier", 100, 1, 30.0)
	TestLib.check(Crafting.part_count(&"scrap") >= sc + 2, "a finished side job pays scrap")
	# the other payout hooks sit in the mission code
	for pair: Array in [["res://scripts/missions/contracts.gd", "Crafting.award(&\"contract\")"], ["res://scripts/missions/contracts.gd", "Crafting.award(&\"boss\")"], ["res://scripts/missions/heist_runner.gd", "Crafting.award(&\"heist\")"], ["res://scripts/interiors_gameplay/interior_missions.gd", "Crafting.award(&\"contract\")"], ["res://scripts/enemies/drone.gd", "Crafting.on_kill("]]:
		var f := FileAccess.open(pair[0], FileAccess.READ)
		TestLib.check(f != null and f.get_as_text().contains(pair[1]), "%s pays crafting drops" % pair[0].get_file())


# --- vendor -------------------------------------------------------------------------------------------------------------

func _vendor() -> void:
	_fresh()
	Crafting.reset()
	var rows := VendorLogic.rows(&"tech")
	var parts_row := {}
	var bp_row := {}
	for r: Dictionary in rows:
		if r["id"] == &"parts":
			parts_row = r
		elif r["id"] == &"blueprint":
			bp_row = r
	TestLib.check(not parts_row.is_empty() and not bp_row.is_empty(), "the tech vendor sells salvage and a blueprint")
	TestLib.check(int(parts_row["price"]) > 0 and int(bp_row["price"]) > 0 and String(bp_row["name"]).begins_with("BLUEPRINT"), "both are priced and named")
	prog.credits = 1
	var poor := VendorLogic.buy(&"tech", &"parts")
	TestLib.check(not poor["ok"] and Crafting.part_count(&"scrap") == 0, "salvage needs credits")
	prog.credits = 100000
	var c0 := prog.credits
	var ok := VendorLogic.buy(&"tech", &"parts")
	TestLib.check(ok["ok"] and Crafting.part_count(&"scrap") == int(Economy.CRAFT_PART_BUNDLE[&"scrap"]) and Crafting.part_count(&"alloy") == int(Economy.CRAFT_PART_BUNDLE[&"alloy"]) and prog.credits < c0, "salvage gives scrap and alloy")
	var unk := Crafting.unknown_bps().size()
	var bp_ok := VendorLogic.buy(&"tech", &"blueprint")
	TestLib.check(bp_ok["ok"] and Crafting.unknown_bps().size() == unk - 1, "the blueprint is learned")
	for bp: StringName in Crafting.bp_ids():
		Crafting.learn(bp)
	var done := VendorLogic.buy(&"tech", &"blueprint")
	TestLib.check(not done["ok"], "nothing left to sell once every blueprint is known")


# --- save ---------------------------------------------------------------------------------------------------------------

func _save_roundtrip() -> void:
	_fresh()
	Crafting.reset()
	WeaponDefs.unlock(&"scatter")
	Crafting.learn(&"mod_arc")
	Crafting.learn(&"var_scatter")
	_give(7, 3, 1)
	var mod_uid := int(Crafting.make_item(&"mod_arc", 2, 55)["uid"])
	var it := Crafting.make_item(&"mod_arc", 2, 55)
	Crafting.add_item(it)
	mod_uid = int(it["uid"])
	var it2 := Crafting.make_item(&"var_scatter", 3, 56)
	Crafting.add_item(it2)
	Crafting.equip(prog, mod_uid, &"carbine")
	Crafting.equip(prog, int(it2["uid"]), &"scatter")
	TestLib.check(prog.save_file(), "the save is written")
	var items_before := Crafting.items.duplicate(true)
	var eq_before := Crafting.equipped.duplicate(true)
	var nxt := Crafting.next_uid
	Crafting.reset()
	TestLib.check(prog.load_file(), "the save loads")
	TestLib.check(Crafting.part_count(&"scrap") == 7 and Crafting.part_count(&"alloy") == 3 and Crafting.part_count(&"core") == 1, "parts come back")
	TestLib.check(Crafting.knows(&"mod_arc") and Crafting.knows(&"var_scatter") and Crafting.knows(&"mod_basic"), "blueprints come back")
	TestLib.check(Crafting.items == items_before, "items come back with their rolled stats")
	TestLib.check(Crafting.equipped == eq_before and Crafting.equipped_on(mod_uid) == &"carbine", "equipped items come back")
	TestLib.check(Crafting.next_uid == nxt, "new items keep counting up")
	# damaged section
	var cf := ConfigFile.new()
	cf.load(TMP)
	cf.set_value("crafting", "scrap", "lots")
	cf.set_value("crafting", "bps", PackedStringArray(["mod_arc", "nonsense", "var_nothing"]))
	cf.set_value("crafting", "items", PackedStringArray(["junk", "1|mod|||mod_arc|9|1|chain_arc|damage:9.0", "2|mod||mod_arc|2|3||damage:1.1;bogus:1.5", "3|mod||mod_arc|9|3|nonperk|damage:1.1", "4|mod||mod_arc|2|3|chain_arc|damage:99.0;mag:nan",
		"5|mod||mod_arc|2|3|chain_arc|damage:1.1", "5|mod||mod_arc|1|3||damage:1.2"]))
	cf.set_value("crafting", "eq", PackedStringArray(["carbine|5|5", "nowhere|5|0", "carbine|x|y"]))
	cf.set_value("crafting", "next", -4)
	cf.save(TMP)
	TestLib.check(prog.load_file(), "a damaged crafting section still loads")
	TestLib.check(Crafting.part_count(&"scrap") == 0, "a junk part count reads as zero")
	TestLib.check(Crafting.knows(&"mod_arc") and not Crafting.knows(&"nonsense") and not Crafting.knows(&"var_nothing"), "unknown blueprints are dropped")
	TestLib.check(Crafting.items.size() == 1 and not Crafting.item(5).is_empty() and Crafting.item(4).is_empty() and Crafting.item(2).is_empty() and Crafting.item(3).is_empty(), "malformed items are dropped (kept %d)" % Crafting.items.size())
	var kept := Crafting.item(5)
	TestLib.check(kept["rarity"] == 2 and kept["perk"] == &"chain_arc" and kept["kind"] == &"mod", "the duplicate uid keeps its first entry")
	TestLib.check(float(kept["stats"]["damage"]) <= Crafting.STAT_MAX, "a stat is clamped to the legal range")
	TestLib.check(Crafting.next_uid > 5, "the uid counter is above every kept item")
	TestLib.check(Crafting.equipped_on(5) == &"carbine" and not Crafting.equipped.has(&"nowhere"), "a valid equip row is kept, a bad one dropped")
	# a save without the section
	var cf2 := ConfigFile.new()
	cf2.load(TMP)
	cf2.erase_section("crafting")
	cf2.save(TMP)
	TestLib.check(prog.load_file() and Crafting.items.is_empty() and Crafting.knows(&"mod_basic") and Crafting.known.size() == Crafting.START_KNOWN.size() and Crafting.part_count(&"scrap") == 0, "an older save without the section loads the starter blueprints and nothing else")
	prog.new_campaign()
	TestLib.check(Crafting.items.is_empty() and Crafting.equipped.is_empty() and not Crafting.knows(&"mod_arc"), "a new campaign clears crafting")
	TestLib.check(not (WeaponDefs.is_unlocked(&"scatter")), "(a new campaign also locks the weapons again)")


# --- screens ------------------------------------------------------------------------------------------------------------

func _reset_ui() -> void:
	Game.state = &"play"
	await TestLib.frames(host, 2)
	Game.state = &"paused"
	await TestLib.frames(host, 4)


## Every `cr_` button: at least 64 px tall, inside the viewport and not overlapping another.
func _scan(tag: String, prefixes := ["cr_"]) -> Dictionary:
	var ids := {}
	var vp := hud.get_viewport().get_visible_rect()
	var s := UiUtil.ui_scale(vp.size)
	var rects: Array[Rect2] = []
	for bt: Dictionary in hud.buttons:
		var bid := String(bt["id"])
		var hit := false
		for pre: String in prefixes:
			hit = hit or bid.begins_with(pre)
		if not hit:
			continue
		ids[bid] = true
		var r: Rect2 = bt["rect"]
		TestLib.check(r.size.y >= UiUtil.TOUCH_MIN * s - 1.0, "%s: %s is at least 64 px tall" % [tag, bid])
		TestLib.check(r.position.y >= -2.0 and r.end.y <= vp.size.y + 2.0, "%s: %s is inside the screen vertically" % [tag, bid])
		if bid.begins_with("cr_"):
			TestLib.check(r.position.x >= -2.0 and r.end.x <= vp.size.x + 2.0, "%s: %s is inside the screen horizontally" % [tag, bid])
		for o: Rect2 in rects:
			TestLib.check(not o.grow(-1.0).intersects(r.grow(-1.0)), "%s: %s overlaps nothing" % [tag, bid])
		rects.append(r)
	return ids


func _screens() -> void:
	_fresh()
	Crafting.reset()
	Attachments.reset()
	SkillTree.reset()
	CraftScreen.reset_state()
	_give(30, 10, 5)
	Crafting.learn(&"mod_arc")
	await _reset_ui()
	# from the shop
	TestLib.check(hud.press_button(&"shop") and hud._shop_open, "UPGRADES opens the shop")
	await TestLib.frames(host, 3)
	var shop_ids := _scan("shop", ["cr_", "shop_", "skills_", "loadout", "side_open", "look_open", "heist_open"])
	TestLib.check(shop_ids.has("cr_open"), "the shop has a CRAFT button")
	TestLib.check(hud.press_button(&"cr_open") and hud._craft_open, "CRAFT opens the workbench")
	await TestLib.frames(host, 3)
	TestLib.check(hud.panel_cover(), "the workbench covers the gameplay HUD")
	var ids := _scan("craft")
	TestLib.check(ids.has("cr_tab_0") and ids.has("cr_tab_1") and ids.has("cr_tab_2") and ids.has("cr_back") and ids.has("cr_cell_0") and ids.has("cr_prev") and ids.has("cr_next") and ids.has("cr_boost") and ids.has("cr_make"), "the CRAFT page lays out tabs, cells, paging, BOOST and CRAFT (%d buttons)" % ids.size())
	# pick the arc mod and craft through the buttons
	var cell := -1
	var all := CraftScreen.entries()
	for i in mini(all.size(), CraftScreen.PAGE_CELLS):
		if all[i] == &"mod_arc":
			cell = i
	TestLib.check(cell >= 0 and hud.press_button(StringName("cr_cell_%d" % cell)) and CraftScreen.sel_bp == &"mod_arc", "a blueprint cell selects it")
	var n0 := Crafting.items.size()
	var s0 := Crafting.part_count(&"scrap")
	var cr0 := prog.credits
	TestLib.check(hud.press_button(&"cr_make") and Crafting.items.size() == n0 + 1 and Crafting.part_count(&"scrap") < s0 and prog.credits < cr0, "CRAFT through the button makes an item")
	TestLib.check(CraftScreen.last.begins_with("CRAFTED"), "the screen says what it made (%s)" % CraftScreen.last)
	var locked := &"mod_singularity"
	CraftScreen.sel_bp = locked
	TestLib.check(not hud.press_button(&"cr_make") and CraftScreen.last == "BLUEPRINT NOT FOUND", "a locked blueprint cannot be crafted from the screen")
	TestLib.check(hud.press_button(&"cr_boost") and Crafting.boost and hud.press_button(&"cr_boost") and not Crafting.boost, "BOOST toggles")
	# inventory page
	TestLib.check(hud.press_button(&"cr_tab_1") and CraftScreen.page == 1, "INVENTORY tab")
	await TestLib.frames(host, 3)
	ids = _scan("inventory")
	TestLib.check(ids.has("cr_cell_0") and ids.has("cr_equip") and ids.has("cr_dismantle"), "the INVENTORY page lays out items, EQUIP and DISMANTLE")
	var uid := CraftScreen.sel_item
	TestLib.check(Crafting.item(uid).is_empty() == false, "the crafted item is selected")
	WeaponDefs.last_used = &"carbine"
	TestLib.check(hud.press_button(&"cr_equip") and Crafting.equipped_on(uid) == &"carbine" and w.def.has("chain"), "EQUIP puts the mod on the weapon in hand and the weapon changes")
	TestLib.check(hud.press_button(&"cr_equip") and Crafting.equipped_on(uid) == &"", "the button unequips when pressed again")
	TestLib.check(hud.press_button(&"cr_equip") and hud.press_button(&"cr_dismantle") and Crafting.item(uid).is_empty() and not w.def.has("chain"), "DISMANTLE removes an equipped item and the weapon forgets it")
	# supply page
	TestLib.check(hud.press_button(&"cr_tab_2") and CraftScreen.page == 2, "SUPPLY tab")
	await TestLib.frames(host, 3)
	ids = _scan("supply")
	TestLib.check(ids.has("cr_cell_0") and ids.has("cr_cell_3"), "the SUPPLY page lists parts and blueprints")
	var a0 := Crafting.part_count(&"alloy")
	TestLib.check(hud.press_button(&"cr_cell_1") and Crafting.part_count(&"alloy") > a0, "a part cell buys its bundle")
	var known0 := Crafting.known.size()
	TestLib.check(hud.press_button(&"cr_cell_3") and Crafting.known.size() == known0 + 1, "a blueprint cell buys the blueprint")
	prog.credits = 0
	TestLib.check(not hud.press_button(&"cr_cell_1"), "buying without credits is refused")
	prog.credits = 100000
	# paging
	for bp: StringName in Crafting.bp_ids():
		Crafting.learn(bp)
	TestLib.check(hud.press_button(&"cr_tab_0"), "back to CRAFT")
	TestLib.check(CraftScreen.pages() == 2 and hud.press_button(&"cr_next") and CraftScreen.grid_page == 1 and hud.press_button(&"cr_prev") and CraftScreen.grid_page == 0, "18 blueprints page over two grids")
	hud.press_button(&"cr_next")
	await TestLib.frames(host, 3)
	_scan("page 2")
	hud.press_button(&"cr_prev")
	TestLib.check(hud.press_button(&"cr_back") and not hud._craft_open and hud._shop_open, "BACK returns to the shop")
	TestLib.check(not hud.press_button(&"cr_make"), "a closed bench ignores its buttons")
	hud.press_button(&"shop_back")
	await _reset_ui()
	# from a safehouse
	prog.unlock(6)
	prog.credits = 100000
	Safehouses.buy(prog, &"loft")
	Safehouses.sel = &"loft"
	TestLib.check(hud.press_button(&"sh_open") and hud._safe_open, "SAFEHOUSE opens")
	await TestLib.frames(host, 3)
	var sh_ids := _scan("safehouse", ["sh_"])
	TestLib.check(sh_ids.has("sh_craft") and sh_ids.has("sh_back") and sh_ids.has("sh_trophy"), "an owned house lists WORKBENCH next to its services")
	TestLib.check(hud.press_button(&"sh_craft") and hud._craft_open, "WORKBENCH opens the bench from the house")
	TestLib.check(not hud.press_button(&"sh_rest"), "house buttons are inert under the bench")
	TestLib.check(hud.press_button(&"cr_back") and not hud._craft_open and hud._safe_open, "BACK returns to the house")
	hud.press_button(&"sh_back")
	Game.state = &"play"
	await TestLib.frames(host, 2)
	TestLib.check(not hud.press_button(&"cr_open"), "the bench does not open while playing")


# --- demo ---------------------------------------------------------------------------------------------------------------

func _demo() -> void:
	TestLib.check(DemoPanel.TABS.has("WORKBENCH"), "the DEMO panel has a WORKBENCH tab")
	var cat := DemoMode.catalog()
	var found := false
	for g: Dictionary in cat:
		if g["kind"] == &"crafting":
			found = (g["items"] as Array).size() >= 3
	TestLib.check(found, "the DEMO catalogue lists the workbench entries")
	TestLib.check(DemoPanel.TABS.size() == cat.size() + 2, "a DEMO tab per group plus SPAWN and TOOLS")
	_fresh()
	Crafting.reset()
	DemoMode._grant_all(prog)
	TestLib.check(Crafting.unknown_bps().is_empty() and Crafting.part_count(&"core") >= 50, "the demo profile knows every blueprint and has parts")
	var perks := {}
	for it: Dictionary in Crafting.items:
		perks[it["perk"]] = true
	TestLib.check(perks.has(&"chain_arc") and perks.has(&"phase_rounds") and perks.has(&"singularity_crit"), "the demo profile holds one item per perk")
	Crafting.items.clear()
	Crafting.equipped.clear()
	var was := DemoMode.active
	DemoMode.active = true
	Game.state = &"play"
	await TestLib.frames(host, 3)
	var r := DemoMode.launch(&"crafting", &"bench")
	TestLib.check(r != "" and Game.state == &"paused" and hud._craft_open, "the DEMO entry opens the workbench (%s)" % r)
	Game.state = &"play"
	await TestLib.frames(host, 2)
	WeaponDefs.last_used = &"carbine"
	var k := DemoMode.launch(&"crafting", &"kit")
	TestLib.check(k != "" and Crafting.has_gear(&"carbine") and w.def.has("sing"), "the kit entry crafts and equips legendary gear (%s)" % k)
	var d := DemoMode.launch(&"crafting", &"drop")
	TestLib.check(d != "", "the drop entry rolls a drop (%s)" % d)
	var pa := DemoMode.launch(&"crafting", &"parts")
	TestLib.check(pa != "" and Crafting.part_count(&"scrap") >= 99, "the parts entry refills the bench")
	DemoMode.active = was
	Crafting.reset()
	Crafting.refresh_weapon()
	Game.state = &"play"
	await TestLib.frames(host, 2)
