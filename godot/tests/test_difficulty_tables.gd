extends RefCounted
## Difficulty tables through the whole campaign (chapter indexes 0-7 and the endless sectors after): contract weights, the specialist share and pick bias of the reinforcements,
## and the sector scaling of Progress.difficulty. Pure data and rules, no scene tree.
## Run: tools/test.sh tests/test_difficulty_tables.gd


func _freq(chapter: int, n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + chapter
	var out := {}
	for k: StringName in ContractTypes.KINDS:
		out[k] = 0
	for i in n:
		out[ContractTypes.pick(chapter, rng)] += 1
	return out


func _top(freq: Dictionary) -> StringName:
	var best: StringName = &""
	var bv := -1
	for k: StringName in freq:
		if int(freq[k]) > bv:
			bv = int(freq[k])
			best = k
	return best


func _spec_counts(chapter: int, heat: float) -> Dictionary:
	var out := {&"operative": 0}
	for i in 1000:
		var t := EnemyTypes.specialist_for(chapter, heat, 0.0, float(i) / 1000.0)
		out[t] = int(out.get(t, 0)) + 1
	return out


func run(_host: Node) -> void:
	# --- contract weights: one row per chapter plus the endless row -------------------------------------------------------------------
	var chapters := CampaignData.count()
	TestLib.check(ContractTypes.WEIGHTS.size() >= chapters + 1, "the weight table has a row for each of the %d chapters and the aftermath (%d rows)" % [chapters, ContractTypes.WEIGHTS.size()])
	var rows_ok := true
	for row: Dictionary in ContractTypes.WEIGHTS:
		for k: StringName in ContractTypes.KINDS:
			rows_ok = rows_ok and row.has(k) and float(row[k]) >= 1.0
	TestLib.check(rows_ok, "every row has every kind with weight >= 1")
	var distinct := true
	for i in range(1, chapters + 1):
		distinct = distinct and ContractTypes.weights(i) != ContractTypes.weights(i - 1)
	TestLib.check(distinct, "neighbouring chapters do not repeat a row (chapters 7 to 10 do not reuse each other's rows)")
	TestLib.check(ContractTypes.weights(6) != ContractTypes.WEIGHTS[5] and ContractTypes.weights(7) != ContractTypes.WEIGHTS[5], "chapters 7 and 8 (index 6, 7) have rows of their own")
	TestLib.check(ContractTypes.weights(chapters) == ContractTypes.weights(chapters + 50) and ContractTypes.weights(-3) == ContractTypes.weights(0), "later sectors share the last row, negative ones clamp to the first")
	var f6 := _freq(6, 4000)
	var f7 := _freq(7, 4000)
	TestLib.check(_top(f6) == &"courier" and int(f6[&"courier"]) > int(f6[&"hack"]) * 2, "Neon Market (index 6) is about timing: couriers lead (%s)" % str(f6))
	TestLib.check(_top(f7) == &"survive" and int(f7[&"survive"]) > int(f7[&"courier"]) * 2, "the Meridian Gate (index 7) is sieges: anchors lead (%s)" % str(f7))
	var f8 := _freq(8, 4000)
	var all_come := true
	for k: StringName in ContractTypes.KINDS:
		all_come = all_come and int(f6[k]) > 0 and int(f7[k]) > 0 and int(f8[k]) > 0
	TestLib.check(all_come, "every kind still comes up in the late chapters and the aftermath")
	TestLib.check(ContractTypes.is_boss_chapter(7) and ContractTypes.is_boss_chapter(5) and ContractTypes.is_boss_chapter(2) and not ContractTypes.is_boss_chapter(6), "the boss chapters are 3, 6 and 8")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	TestLib.check(ContractTypes.pick(7, rng, &"survive") != &"survive", "the previous kind is skipped in a late chapter too")

	# --- sector scaling ----------------------------------------------------------------------------------------------------------------
	var mono := true
	var prev := Progress.difficulty(0)
	for c in range(1, 12):
		var d := Progress.difficulty(c)
		mono = mono and float(d["hp"]) >= float(prev["hp"]) and float(d["reward"]) >= float(prev["reward"]) and float(d["time"]) <= float(prev["time"]) and int(d["extra"]) >= int(prev["extra"])
		prev = d
	TestLib.check(mono, "health, pay and extra enemies never fall and the time limit never grows from chapter 1 to the free city")
	TestLib.check(float(Progress.difficulty(7)["hp"]) > float(Progress.difficulty(5)["hp"]) and float(Progress.difficulty(7)["reward"]) > float(Progress.difficulty(5)["reward"]), "chapter 8 is harder and pays more than chapter 6")
	TestLib.check(ContractTypes.count(&"survive", 7, 2) > ContractTypes.count(&"survive", 5, 2) and ContractTypes.time_limit(&"hack", 7) <= ContractTypes.time_limit(&"hack", 5), "late waves are bigger and limits no looser")

	# --- the specialist share and the late pick bias ------------------------------------------------------------------------------------
	TestLib.check(EnemyTypes.SPECIALIST_SHARE.size() >= chapters + 1, "the specialist share table covers chapters 1-8 and the aftermath")
	var share_ok := true
	for i in range(1, EnemyTypes.SPECIALIST_SHARE.size()):
		share_ok = share_ok and EnemyTypes.SPECIALIST_SHARE[i] >= EnemyTypes.SPECIALIST_SHARE[i - 1] and EnemyTypes.SPECIALIST_SHARE[i] <= 0.85
	TestLib.check(share_ok, "the share only rises, and stays below 85 % so plain operatives remain")
	TestLib.check(is_equal_approx(EnemyTypes.specialist_share(1), 0.55) and is_equal_approx(EnemyTypes.specialist_share(3), 0.55), "chapters 2-4 keep the original 55 %")
	TestLib.check(EnemyTypes.specialist_share(7) > EnemyTypes.specialist_share(3) and EnemyTypes.specialist_share(9) > EnemyTypes.specialist_share(7) and EnemyTypes.specialist_share(10) == EnemyTypes.specialist_share(40) and EnemyTypes.specialist_share(-1) == EnemyTypes.specialist_share(0), "chapter 8 is above chapter 4, the sequel chapters 9-10 climb further, later sectors share the last row")
	for c in [3, 5, 7, 9]:
		var n := 0
		for i in 1000:
			if EnemyTypes.specialist_for(c, 4.0, float(i) / 1000.0, 0.5) != &"operative":
				n += 1
		TestLib.check(absf(float(n) / 1000.0 - EnemyTypes.specialist_share(c)) < 0.01, "chapter index %d: %d of 1000 slots are specialists (share %.2f)" % [c, n, EnemyTypes.specialist_share(c)])
	# chapters up to 4 are unchanged: the four types in equal parts at high heat
	var c3 := _spec_counts(3, 4.0)
	TestLib.check(int(c3[&"flanker"]) == 250 and int(c3[&"shield"]) == 250 and int(c3[&"sniper"]) == 250 and int(c3[&"brute"]) == 250, "chapter 4 is unchanged: the four specialists in equal parts (%s)" % str(c3))
	var c5 := _spec_counts(5, 4.0)
	var c7 := _spec_counts(7, 4.0)
	TestLib.check(int(c5[&"sniper"]) > int(c5[&"flanker"]) and int(c5[&"brute"]) > int(c5[&"flanker"]), "chapter 6: snipers and brutes outweigh flankers (%s)" % str(c5))
	TestLib.check(int(c7[&"sniper"]) > int(c7[&"brute"]) and int(c7[&"brute"]) == int(c7[&"shield"]) and int(c7[&"shield"]) > int(c7[&"flanker"]), "chapter 8: snipers lead, then brutes and shields, then flankers (%s)" % str(c7))
	var late := _spec_counts(30, 4.0)
	var c10 := _spec_counts(9, 4.0)
	TestLib.check(late == _spec_counts(10, 4.0) and int(c10[&"brute"]) > int(c7[&"brute"]) and int(late[&"shield"]) > int(c10[&"shield"]) , "every later sector uses the last row; chapter 10 leans on brutes more than chapter 8")
	var lowheat := _spec_counts(7, 1.0)
	TestLib.check(int(lowheat.get(&"brute", 0)) == 0 and int(lowheat[&"sniper"]) > 0, "no brutes below heat 2.5 in the late chapters either")
	var only_known := true
	for t: StringName in c7:
		only_known = only_known and (t == &"operative" or EnemyTypes.is_specialist(t))
	TestLib.check(only_known, "the late mix only draws known specialists")
	TestLib.check(EnemyTypes.specialist_for(0, 4.0, 0.1, 0.5) == &"operative", "chapter 1 still has plain operatives only")
