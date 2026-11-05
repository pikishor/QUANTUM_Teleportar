class_name BalanceReport
extends RefCounted
## The text tables of docs/BALANCE.md (printed by tools/balance_sim.gd, and with the skill tree by tests/balance_sim.gd through tools/balance_sim.sh).

const M := preload("res://scripts/progress/balance_model.gd")


## Report lines. `skills` adds the skill-tree table (needs the game classes, so only inside the test runner).
static func lines(skills: bool) -> Array[String]:
	var out: Array[String] = []
	out.append("## WEAPONS  sustained dps at chapter 1 / 6 / 12 (NORMAL), ttk of an operative (s), ammo kills (mag + reserve at chapter 1)")
	out.append("weapon      ac   dps1   dps6  dps12  ttk1  ttk6  ttk12  vs_carbine  kills_per_ammo")
	var base := M.weapon_dps(&"carbine")
	for id: StringName in WeaponDefs.IDS:
		var d: Dictionary = WeaponDefs.DEFS[id]
		var rounds := float(d["mag"]) + maxf(float(d["reserve"]), 0.0) if float(d["reserve"]) >= 0.0 else -1.0
		var kills := -1.0 if rounds < 0.0 else rounds * float(d["damage"]) * float(d.get("pellets", 1)) * float(M.ACC[id]) / M.op_hp(0, 1) if str(d["kind"]) != "charge" and str(d["kind"]) != "throw" else (rounds * (float(d["damage"]) + float(d.get("well_dps", 0.0)) * float(d.get("well_time", 0.0)) * 0.5) * float(M.ACC[id]) / M.op_hp(0, 1) if rounds >= 0.0 else -1.0)
		out.append("%-10s %.2f  %5.0f  %5.0f  %5.0f  %4.2f  %4.2f  %5.2f  %9.2f  %s" % [id, M.ACC[id], M.weapon_dps(id, 0), M.weapon_dps(id, 5), M.weapon_dps(id, 11), M.ttk(id, 0, 1), M.ttk(id, 5, 1), M.ttk(id, 11, 1), M.weapon_dps(id, 0) / base, "inf" if kills < 0.0 else "%.1f" % kills])
	out.append("")
	out.append("## TIME TO KILL (carbine, one operative, s) and SURVIVAL against %d operatives (s) per chapter and mode" % M.FOES)
	out.append("chapter  " + "  ".join(PackedStringArray(Difficulty.NAMES.map(func(n: String) -> String: return "%-7s ttk  surv  fight" % n))))
	for ch in M.CHAPTERS:
		var cells: Array[String] = []
		for m in Difficulty.NAMES.size():
			cells.append("%5.2f %5.1f %5.2f" % [M.ttk(&"carbine", ch, m), M.survive(ch, m), M.fight_ratio(ch, m)])
		out.append("%7d  %s" % [ch + 1, "   ".join(cells)])
	var worst := 0.0
	for m in Difficulty.NAMES.size():
		for ch in range(1, M.CHAPTERS):
			worst = maxf(worst, absf(M.ttk(&"carbine", ch, m) / M.ttk(&"carbine", ch - 1, m) - 1.0))
			worst = maxf(worst, absf(M.survive(ch, m) / M.survive(ch - 1, m) - 1.0))
	out.append("largest chapter-to-chapter change: %.1f %%" % (worst * 100.0))
	out.append("")
	out.append("## BOSSES  hp, carbine ttk (s), hero hp share lost while killing it (half the fire lands on the hero)")
	out.append("chapter  boss         " + "  ".join(PackedStringArray(Difficulty.NAMES.map(func(n: String) -> String: return "%-7s hp   ttk  lost" % n))))
	for ch in M.CHAPTERS:
		for b: Dictionary in M.bosses_at(ch):
			var cells2: Array[String] = []
			for m in Difficulty.NAMES.size():
				var r := M.boss_row(ch, m, b["enemy"], b["hp_mult"])
				cells2.append("%5.0f %5.1f %4.0f%%" % [r["hp"], r["ttk"], float(r["lost"]) * 100.0])
			out.append("%7d  %-11s  %s" % [ch + 1, b["enemy"], "  ".join(cells2)])
	out.append("")
	out.append("## ABILITIES  coherence cost, cooldown, sustained period (s) and dps per mode (STORY / NORMAL / HARD / QUANTUM)")
	for a: Dictionary in M.abilities():
		var p: Array[String] = []
		for m in Difficulty.NAMES.size():
			p.append("%.2fs/%.0f" % [M.ability_period(a, m), M.ability_dps(a, m)])
		out.append("%-17s cost %4.0f  cd %4.1f  dmg %4.0f   %s" % [a["name"], a["cost"], a["cd"], a["dmg"], "  ".join(p)])
	out.append("")
	if skills:
		out.append("## SKILL TREE  level / damage factor by chapter (STORY, NORMAL, HARD, QUANTUM)")
		for ch in M.CHAPTERS:
			var s: Array[String] = []
			for m in Difficulty.NAMES.size():
				s.append("L%02d x%.2f" % [M.skill_level(ch, m), M.skill_mult(ch, m)])
			out.append("%7d  %s" % [ch + 1, "   ".join(s)])
		out.append("")
	out.append("## FACTIONS / WANTED / COMPANION")
	out.append("faction pressure  hostile x%.2f  neutral x%.2f  allied x%.2f" % [M.faction_pressure(0), M.faction_pressure(1), M.faction_pressure(2)])
	var wl: Array[String] = []
	for l in 6:
		wl.append("L%d x%.2f" % [l, M.wanted_pressure(l)])
	out.append("wanted pressure   " + "  ".join(wl))
	out.append("companion dps %.1f; share of hero carbine dps at chapters 11 / 12 (NORMAL): %.0f %% / %.0f %%" % [M.companion_dps(), M.companion_share(10, 1) * 100.0, M.companion_share(11, 1) * 100.0])
	out.append("")
	out.append("## HEROPOWER rows  hero dps factor, incoming damage factor, energy regen /s, teleport hops")
	for m in Difficulty.NAMES.size():
		out.append("%-8s dmg x%.2f  taken x%.2f  regen %.1f  hops %d  cooldown x%.2f" % [Difficulty.NAMES[m], HeroPower.f("dmg", m), HeroPower.f("taken", m) * Difficulty.mult("dmg", m), M.energy_regen(m), int(HeroPower.f("tp_hops", m)), HeroPower.f("cooldown", m)])
	return out
