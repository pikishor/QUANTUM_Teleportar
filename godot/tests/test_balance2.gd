extends RefCounted
## Balance pass v2: bands on the model of scripts/progress/balance_model.gd (14 weapons, 7 abilities, skill tree, factions / wanted, companion, chapters 1-12 on every difficulty,
## boss health of the sequel) and on the economy pacing of balance_economy.gd (20 side missions, stealth, heists, safehouses, crafting). Pure data, no scene tree, no timing.
## Tables: tools/balance_sim.sh and tools/economy_sim.sh (docs/BALANCE.md). Run: tools/test.sh tests/test_balance2.gd

const M := preload("res://scripts/progress/balance_model.gd")


func run(_host: Node) -> void:
	_weapons()
	_chapters()
	_bosses()
	_abilities()
	_systems()
	_economy()


func _weapons() -> void:
	TestLib.check(WeaponDefs.IDS.size() >= 18 and M.ACC.size() == WeaponDefs.IDS.size(), "the model covers all %d weapons" % WeaponDefs.IDS.size())
	var base := M.weapon_dps(&"carbine")
	var worst := ""
	var ok := true
	for id: StringName in WeaponDefs.IDS:
		var r := M.weapon_dps(id) / base
		if r < M.WEAPON_BAND.x or r > M.WEAPON_BAND.y:
			ok = false
			worst = "%s %.2f" % [id, r]
	TestLib.check(ok, "every weapon's sustained dps is within %.2f-%.2f of the carbine (%s)" % [M.WEAPON_BAND.x, M.WEAPON_BAND.y, worst])
	var ammo_ok := true
	for id: StringName in WeaponDefs.IDS:
		var d: Dictionary = WeaponDefs.DEFS[id]
		if float(d["reserve"]) < 0.0:
			continue
		var per := float(d["damage"]) * float(d.get("pellets", 1))
		if d.has("well_dps"):
			per += float(d["well_dps"]) * float(d["well_time"]) * 0.5
		var kills := (float(d["mag"]) + float(d["reserve"])) * per * float(M.ACC[id]) / M.op_hp(0, 1)
		ammo_ok = ammo_ok and kills >= M.AMMO_KILLS_MIN
	TestLib.check(ammo_ok, "a full reserve of any limited weapon kills at least %.0f operatives" % M.AMMO_KILLS_MIN)
	var scale_ok := true
	for id: StringName in WeaponDefs.IDS:
		scale_ok = scale_ok and M.weapon_dps(id, 11) > M.weapon_dps(id, 0) * 1.4 and M.weapon_dps(id, 11) < M.weapon_dps(id, 0) * 2.4
	TestLib.check(scale_ok, "gear growth lifts every weapon 1.4-2.4x from chapter 1 to 12")


func _chapters() -> void:
	var smooth := true
	var in_band := true
	var winnable := true
	for m in Difficulty.NAMES.size():
		for ch in M.CHAPTERS:
			var t := M.ttk(&"carbine", ch, m) / M.ttk(&"carbine", 0, m)
			in_band = in_band and t >= M.TTK_BAND.x and t <= M.TTK_BAND.y
			winnable = winnable and M.fight_ratio(ch, m) <= 1.3 and M.survive(ch, m) > 4.0
			if ch > 0:
				smooth = smooth and absf(M.ttk(&"carbine", ch, m) / M.ttk(&"carbine", ch - 1, m) - 1.0) <= M.MAX_STEP
				smooth = smooth and absf(M.survive(ch, m) / M.survive(ch - 1, m) - 1.0) <= M.MAX_STEP
	TestLib.check(smooth, "time-to-kill and survival move by at most %.0f %% from one chapter to the next, on every mode" % (M.MAX_STEP * 100.0))
	TestLib.check(in_band, "ttk stays within %.1f-%.1fx of chapter 1 through chapter 12 (the sequel)" % [M.TTK_BAND.x, M.TTK_BAND.y])
	TestLib.check(winnable, "three operatives in the open never cost more than ~130 % of the health on any mode and chapter")
	# Difficulty ladder: each step up is harder by a bounded, roughly geometric factor.
	var ladder := true
	var prev := M.fight_ratio(5, 0)
	for m in range(1, Difficulty.NAMES.size()):
		var f := M.fight_ratio(5, m)
		ladder = ladder and f > prev * 1.5 and f < prev * 5.5
		prev = f
	TestLib.check(ladder, "the fight cost grows 1.5-5.5x per difficulty step (STORY < NORMAL < HARD < QUANTUM)")
	var n := M.fight_ratio(5, Difficulty.NORMAL)
	TestLib.check(n >= 0.15 and n <= 0.4, "NORMAL: a fight with three operatives costs 15-40 %% of the health (%.2f)" % n)
	# HeroPower rows are monotone with the difficulty.
	var mono := true
	for k in ["regen", "dmg", "energy_regen", "sprint", "jump", "tp_range", "tp_hops"]:
		for m in range(1, Difficulty.NAMES.size()):
			mono = mono and HeroPower.f(k, m) <= HeroPower.f(k, m - 1)
	for k in ["energy_cost", "cooldown", "taken"]:
		for m in range(1, Difficulty.NAMES.size()):
			mono = mono and HeroPower.f(k, m) >= HeroPower.f(k, m - 1)
	TestLib.check(mono, "every HeroPower row is monotone across STORY -> QUANTUM")
	var inc := true
	for m in range(1, Difficulty.NAMES.size()):
		inc = inc and M.damage_taken(5, m) > M.damage_taken(5, m - 1)
	TestLib.check(inc and HeroPower.f("dmg", 0) <= 2.0 and HeroPower.f("taken", 0) >= 0.5, "STORY power fantasy is bounded: incoming damage rises per mode, hero damage <= 2x")


func _bosses() -> void:
	var seq := 0
	var band := true
	var lost := true
	var doubles := true
	var finale := 0.0
	var longest_other := 0.0
	for ch in M.CHAPTERS:
		var bs := M.bosses_at(ch)
		seq += bs.size()
		var tot := 0.0
		for b: Dictionary in bs:
			var r := M.boss_row(ch, 1, b["enemy"], b["hp_mult"])
			tot += float(r["ttk"])
			band = band and float(r["ttk"]) >= M.BOSS_TTK_BAND.x and float(r["ttk"]) <= M.BOSS_TTK_BAND.y
			lost = lost and float(r["lost"]) <= 1.05
			var q := M.boss_row(ch, 3, b["enemy"], b["hp_mult"])
			band = band and float(q["ttk"]) <= M.BOSS_TTK_BAND.y * 2.0
		doubles = doubles and tot <= 80.0
		for b: Dictionary in bs:
			var t := float(M.boss_row(ch, 1, b["enemy"], b["hp_mult"])["ttk"])
			if ch == M.CHAPTERS - 1:
				finale = t
			elif ch >= 8:
				longest_other = maxf(longest_other, t)
	TestLib.check(seq >= 10 and not M.bosses_at(9).is_empty() and not M.bosses_at(11).is_empty(), "the campaign table has bosses in the sequel chapters 10 and 12 (%d boss steps)" % seq)
	TestLib.check(band, "every boss takes %.0f-%.0f s of carbine fire on NORMAL (and at most twice that on QUANTUM)" % [M.BOSS_TTK_BAND.x, M.BOSS_TTK_BAND.y])
	TestLib.check(lost, "a boss costs at most ~100 % of the hero's health on NORMAL with half of its fire landing")
	TestLib.check(doubles, "a chapter with two bosses (7, 10) stays under 80 s of boss fire in total")
	TestLib.check(finale >= longest_other * 0.95, "the finale boss is the longest single boss of the sequel (%.0f s vs %.0f s)" % [finale, longest_other])
	# Boss and troop health curves of the sequel: smooth, capped.
	var curve := true
	for ch in range(8, 12):
		curve = curve and Difficulty.boss_hp(ch) >= Difficulty.boss_hp(ch - 1) and Difficulty.boss_hp(ch) - Difficulty.boss_hp(ch - 1) <= 0.1
		curve = curve and Difficulty.chapter_hp(ch) - Difficulty.chapter_hp(ch - 1) <= 0.11
	TestLib.check(curve, "enemy and boss HP curves of chapters 9-12 rise by at most one step per chapter")


func _abilities() -> void:
	var abs_ := M.abilities()
	TestLib.check(abs_.size() == 7, "seven abilities in the table")
	var ok := true
	var util := true
	for a: Dictionary in abs_:
		for m in range(2, Difficulty.NAMES.size()):
			ok = ok and M.ability_period(a, m) >= M.ability_period(a, m - 1)
		ok = ok and M.ability_period(a, 1) > 0.2
		util = util and M.ability_dps(a, 1) <= M.weapon_dps(&"carbine") * 0.8
	TestLib.check(ok, "ability cadence slows from NORMAL to QUANTUM and no ability can be spammed on NORMAL (period > 0.2 s)")
	TestLib.check(util, "no ability out-damages the carbine on its own (sustained dps <= 80 %)")
	var per_energy := true
	for a: Dictionary in abs_:
		if float(a["cost"]) > 0.0 and float(a["dmg"]) > 0.0:
			per_energy = per_energy and float(a["dmg"]) / float(a["cost"]) >= 0.7
	TestLib.check(per_energy, "offensive abilities deal at least 0.7 damage per coherence")
	var bar := 100.0 / M.energy_regen(1)
	TestLib.check(bar >= 8.0 and bar <= 16.0 and 100.0 / M.energy_regen(3) <= 24.0, "a full coherence bar refills in 8-16 s on NORMAL, under 24 s on QUANTUM (%.1f s)" % bar)


func _systems() -> void:
	var prev := -1.0
	var up := true
	for ch in M.CHAPTERS:
		var l := float(M.skill_level(ch, 1))
		up = up and l >= prev and (ch == 0 or l - prev <= 6.0)
		prev = l
	TestLib.check(up and M.skill_level(M.CHAPTERS - 1, 1) >= 36 and M.skill_level(0, 1) <= 12, "skill levels rise every chapter by at most 6 and the tree is nearly full by chapter 12 on NORMAL")
	TestLib.check(M.skill_mult(11, 1) > 1.0 and M.skill_mult(11, 1) <= 1.35, "the skill tree adds at most 35 % damage")
	TestLib.check(M.faction_pressure(0) > M.faction_pressure(1) and M.faction_pressure(1) > M.faction_pressure(2) and M.faction_pressure(0) <= 1.7, "faction standing: hostile > neutral > allied, hostile at most 1.7x")
	var w := true
	for l in range(1, 6):
		w = w and M.wanted_pressure(l) > M.wanted_pressure(l - 1)
	TestLib.check(w and M.wanted_pressure(5) <= 2.6, "wanted pressure rises with every heat level, level 5 at most 2.6x")
	var c10 := M.companion_share(10, 1)
	TestLib.check(c10 >= 0.05 and c10 <= 0.25 and M.companion_share(11, 1) <= 0.25 and M.companion_share(3, 1) == 0.0, "the companion adds 5-25 %% of the hero's dps in its chapters (%.0f %%)" % (c10 * 100.0))


func _economy() -> void:
	var side_ok := true
	var worst := ""
	var rows := BalanceEconomy.side_rows()
	var lo := 99.0
	var hi := 0.0
	for r: Dictionary in rows:
		var rate := float(r["rate"])
		lo = minf(lo, rate)
		hi = maxf(hi, rate)
		if rate < BalanceEconomy.SIDE_RATE_BAND.x or rate > BalanceEconomy.SIDE_RATE_BAND.y:
			side_ok = false
			worst = "%s %.2f" % [r["id"], rate]
	TestLib.check(rows.size() >= 20, "all 20+ side missions are in the table (%d)" % rows.size())
	TestLib.check(side_ok, "side mission credits per minute stay within %.2f-%.2f of the sector average (%s)" % [BalanceEconomy.SIDE_RATE_BAND.x, BalanceEconomy.SIDE_RATE_BAND.y, worst])
	TestLib.check(hi / lo <= 2.6, "the best and the worst side job differ by at most 2.6x per minute (%.2f)" % (hi / lo))
	var heist_ok := true
	for r: Dictionary in BalanceEconomy.heist_rows():
		heist_ok = heist_ok and float(r["rate"]) >= BalanceEconomy.HEIST_RATE_BAND.x and float(r["rate"]) <= BalanceEconomy.HEIST_RATE_BAND.y and float(r["replay"]) < float(r["pay"])
	TestLib.check(heist_ok, "heist pay per minute within %.1f-%.1f of the sector average, replays pay less" % [BalanceEconomy.HEIST_RATE_BAND.x, BalanceEconomy.HEIST_RATE_BAND.y])
	var st_ok := true
	for r: Dictionary in BalanceEconomy.stealth_rows():
		st_ok = st_ok and float(r["rate"]) >= 0.7 and float(r["rate"]) <= 1.9
	TestLib.check(st_ok, "stealth jobs pay 0.7-1.9x of the sector average per minute")
	var sh_ok := true
	var prev_h := 0.0
	for r: Dictionary in BalanceEconomy.safehouse_rows():
		sh_ok = sh_ok and float(r["hours"]) >= BalanceEconomy.SAFEHOUSE_HOURS.x and float(r["hours"]) <= BalanceEconomy.SAFEHOUSE_HOURS.y and float(r["hours"]) >= prev_h - 0.05 and float(r["upgrade_hours"]) <= 1.6
		prev_h = float(r["hours"])
	TestLib.check(sh_ok, "safehouses cost %.1f-%.1f hours of income at their unlock chapter, rising with the house" % [BalanceEconomy.SAFEHOUSE_HOURS.x, BalanceEconomy.SAFEHOUSE_HOURS.y])
	var cr_ok := true
	for r: Dictionary in BalanceEconomy.craft_rows():
		cr_ok = cr_ok and float(r["hours"]) <= BalanceEconomy.CRAFT_HOURS_MAX
	TestLib.check(cr_ok, "one craft never costs more than %.1f hours of income at chapter 5" % BalanceEconomy.CRAFT_HOURS_MAX)
	var s := Economy.simulate(16)
	TestLib.check(float(s["full_tree_hours"]) >= 8.0 and float(s["full_tree_hours"]) <= 14.5, "the full gear tree still takes 8-14 hours (%.1f; the energy / blast weapons and gadgets of wave 108 added about 1.2)" % float(s["full_tree_hours"]))
	var income_up := true
	for ch in range(1, M.CHAPTERS):
		income_up = income_up and BalanceEconomy.per_minute(ch) > BalanceEconomy.per_minute(ch - 1)
	TestLib.check(income_up, "credits per minute rise with every sector, 1-12")
