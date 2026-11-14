extends RefCounted
## Balance of the whole roster (wave 113, 183 weapons and more): the TIME TO KILL of an operative and of a heavy by weapon class and range (tools/balance_sim.sh prints the same table), on the model of
## scripts/progress/balance_model.gd (sustained damage per second with reloads, charge and melee uptime, the hero's damage of the mode, the enemy's health of the table). Pure data, no scene tree.
## Rules: within a class (and within a family of four or more) no weapon that reaches the range kills more than 3 times slower or 3 times faster than the median of the others, on EASY the default
## stays easy (a kill takes seconds, not minutes), HARD is slower but fair, and the sustained damage stays in the band of the first rosters. The table is printed (lines starting with TTK).
## Run: tools/test.sh tests/test_weapon_balance_v3.gd

const M := preload("res://scripts/progress/balance_model.gd")
const RANGES: Array[float] = [2.0, 6.0, 15.0, 40.0, 100.0]
const OUTLIER := 3.0                       ## times the median of its class
const EASY := 0
const NORMAL := 1
const HARD := 2


## How far a weapon is really used: the end of the stretch where it still does at least 60 % of its damage (a sprayer at the very edge of its range is not a rifle that is bad at 15 m), and for a cone
## weapon (SONIC CANNON, KINETIC REPULSOR) the length of its cone.
static func reach_of(id: StringName) -> float:
	var d: Dictionary = WeaponDefs.DEFS[id]
	if String(d["kind"]) == "melee":
		return float(d["range"]) + 0.8
	var rng := float(d.get("cone_range", d["range"]))
	var fall := minf(float(d["falloff_from"]), rng)
	return lerpf(fall, rng, 0.4)


## Seconds one weapon needs to kill `foe` at `dist` metres, INF when the distance is beyond its reach.
static func ttk_at(id: StringName, dist: float, foe: StringName, ch := 0, m := NORMAL) -> float:
	var d: Dictionary = WeaponDefs.DEFS[id]
	if dist > reach_of(id):
		return INF
	var dps := M.weapon_dps(id, ch, m)
	if String(d["kind"]) != "melee":
		dps *= WeaponStats.damage_at(id, dist) / maxf(WeaponStats.damage_at(id, 0.0), 0.001)
	return M.op_hp(ch, m, foe) / maxf(dps, 0.001)


static func _median(a: Array[float]) -> float:
	var s := a.duplicate()
	s.sort()
	return s[s.size() / 2] if s.size() % 2 == 1 else 0.5 * (s[s.size() / 2 - 1] + s[s.size() / 2])


func run(_host: Node) -> void:
	_table_by_class()
	_table_by_family()
	_modes()
	_bands()


func _groups_by(fn: Callable) -> Dictionary:
	var out := {}
	for id: StringName in WeaponDefs.IDS:
		var key: StringName = fn.call(id)
		if not out.has(key):
			out[key] = []
		(out[key] as Array).append(id)
	return out


func _check_group(label: String, ids: Array, foe: StringName) -> void:
	for dist in RANGES:
		var times: Array[float] = []
		var who: Array[StringName] = []
		for id: StringName in ids:
			var t := ttk_at(id, dist, foe)
			if t != INF:
				times.append(t)
				who.append(id)
		if times.size() < 3:
			continue
		var med := _median(times)
		var worst_hi := 0.0
		var worst_lo := 1.0e9
		var name_hi := ""
		var name_lo := ""
		for i in times.size():
			var r := times[i] / med
			if r > worst_hi:
				worst_hi = r
				name_hi = String(who[i])
			if r < worst_lo:
				worst_lo = r
				name_lo = String(who[i])
		print("TTK %-8s %-9s %5.0f m  n %2d  median %5.2f s  slowest %-12s x%.2f  fastest %-12s x%.2f" % [label, foe, dist, times.size(), med, name_hi, worst_hi, name_lo, worst_lo])
		TestLib.check(worst_hi <= OUTLIER, "%s at %.0f m (%s): no weapon kills more than %.0fx slower than the median %.2f s (%s x%.2f)" % [label, dist, foe, OUTLIER, med, name_hi, worst_hi])
		TestLib.check(worst_lo >= 1.0 / OUTLIER, "%s at %.0f m (%s): no weapon kills more than %.0fx faster than the median %.2f s (%s x%.2f)" % [label, dist, foe, OUTLIER, med, name_lo, worst_lo])


func _table_by_class() -> void:
	var groups := _groups_by(func(id: StringName) -> StringName: return WeaponDefs.class_of(id))
	TestLib.check(groups.size() >= 10, "the roster has %d weapon classes" % groups.size())
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		if not groups.has(cls):
			continue
		for foe: StringName in [&"operative", &"heavy"]:
			_check_group(String(cls), groups[cls], foe)


func _table_by_family() -> void:
	var groups := _groups_by(func(id: StringName) -> StringName: return WeaponDefs.family_of(id))
	for fam: StringName in groups:
		var ids: Array = groups[fam]
		if ids.size() >= 4:
			_check_group(String(fam), ids, &"operative")


## EASY stays easy (a kill of an operative takes 2.5 s at most at half the weapon's range, never more than 20 m), HARD is slower but fair (7 s), and the three modes are in order.
func _modes() -> void:
	var slow_easy: Array[String] = []
	var slow_hard: Array[String] = []
	var unordered: Array[String] = []
	for id: StringName in WeaponDefs.IDS:
		var d: Dictionary = WeaponDefs.DEFS[id]
		var dist := 1.5 if String(d["kind"]) == "melee" else minf(20.0, 0.5 * reach_of(id))
		var te := ttk_at(id, dist, &"operative", 0, EASY)
		var tn := ttk_at(id, dist, &"operative", 0, NORMAL)
		var th := ttk_at(id, dist, &"operative", 0, HARD)
		if te > 2.5:
			slow_easy.append("%s %.1f" % [id, te])
		if th > 7.0:
			slow_hard.append("%s %.1f" % [id, th])
		if not (te < tn and tn < th):
			unordered.append(String(id))
	TestLib.check(slow_easy.is_empty(), "on EASY every weapon kills an operative within 2.5 s (slow: %s)" % str(slow_easy))
	TestLib.check(slow_hard.is_empty(), "on HARD every weapon still kills an operative within 7 s (slow: %s)" % str(slow_hard))
	TestLib.check(unordered.is_empty(), "EASY kills faster than NORMAL and NORMAL faster than HARD for every weapon (%s)" % str(unordered))


func _bands() -> void:
	var base := M.weapon_dps(&"carbine")
	var out: Array[String] = []
	for id: StringName in WeaponDefs.IDS:
		var r := M.weapon_dps(id) / base
		if r < M.WEAPON_BAND.x or r > M.WEAPON_BAND.y:
			out.append("%s %.2f" % [id, r])
	TestLib.check(out.is_empty(), "every one of the %d weapons sits inside the sustained-damage band of the first rosters (%s)" % [WeaponDefs.IDS.size(), str(out)])
	# a limited weapon's full reserve kills enough enemies to be worth carrying
	var starved: Array[String] = []
	for id: StringName in WeaponDefs.IDS:
		var d: Dictionary = WeaponDefs.DEFS[id]
		if float(d["reserve"]) < 0.0 or String(d["kind"]) == "melee":
			continue
		var per := float(d["damage"]) * float(d.get("pellets", 1))
		if d.has("well_dps"):
			per += float(d["well_dps"]) * float(d["well_time"]) * 0.5                 # a singularity also pulls and hurts for a while (the model of tests/test_balance2.gd)
		var kills := (float(d["mag"]) + float(d["reserve"])) * per * float(M.ACC[id]) / M.op_hp(0, NORMAL)
		if kills < M.AMMO_KILLS_MIN:
			starved.append("%s %.1f" % [id, kills])
	TestLib.check(starved.is_empty(), "a full reserve of every limited weapon kills at least %.1f operatives (%s)" % [M.AMMO_KILLS_MIN, str(starved)])
