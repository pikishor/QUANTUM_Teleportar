extends RefCounted
## The blast table as data (no scene): the 65 entries of the arsenal with their counts per category, valid numbers, a falloff that follows the curve at 0.5 / 1.0 / 1.5 x the radius, the
## migrated legacy blasts, the registration API, and the 46 hand-carried entries as weapons of the BLAST class that sit inside the balance bands of the weapon model.
## Run: tools/test.sh tests/test_blast_table.gd

const COUNTS := {&"grenade": 12, &"launcher": 14, &"mine": 10, &"strike": 10, &"ordnance": 9, &"ultimate": 6, &"world": 4}
const KEYS := ["id", "name", "cat", "radius", "core", "curve", "edge", "dmg", "pad", "knock", "lift", "status", "element", "wave", "shake", "snd", "crater", "scorch", "debris", "level", "friendly", "cover",
	"fx", "hold", "pre", "fire", "cluster", "tier", "note", "tag", "deliver"]
const DMG_KEYS := ["enemy", "civilian", "animal", "vehicle", "structure", "prop", "hero"]


func run(_host: Node) -> void:
	var all := BlastTable.ids()
	var arsenal := 0
	for cat: StringName in COUNTS:
		var n := BlastTable.count(cat)
		TestLib.check(n == int(COUNTS[cat]), "category %s has %d entries (want %d)" % [cat, n, int(COUNTS[cat])])
		arsenal += n
	TestLib.check(arsenal >= 60 and arsenal == 65, "the arsenal has %d entries (at least 60)" % arsenal)
	TestLib.check(BlastTable.count(&"legacy") >= 10, "the older weapons, gear and charges are migrated into the table (%d legacy entries)" % BlastTable.count(&"legacy"))
	TestLib.check(all.size() == BlastTable.count(), "ids() lists every entry once")
	var seen := {}
	var bad := PackedStringArray()
	for id in all:
		if seen.has(id):
			bad.append("duplicate %s" % id)
		seen[id] = true
		var e := BlastTable.entry(id)
		for k in KEYS:
			if not e.has(k):
				bad.append("%s lacks %s" % [id, k])
		if e.is_empty():
			continue
		var r := float(e["radius"])
		var core := float(e["core"])
		if r <= 0.0 or core < 0.0 or core > r + 0.001:
			bad.append("%s radius %.1f core %.1f" % [id, r, core])
		if not StringName(e["curve"]) in [&"flat", &"linear", &"quad"]:
			bad.append("%s curve %s" % [id, e["curve"]])
		if float(e["edge"]) < 0.0 or float(e["edge"]) > 1.0:
			bad.append("%s edge" % id)
		var dmg: Dictionary = e["dmg"]
		for k in DMG_KEYS:
			if not dmg.has(k) or float(dmg[k]) < 0.0:
				bad.append("%s dmg.%s" % [id, k])
		if not BlastElements.valid(StringName(e["element"])):
			bad.append("%s element %s" % [id, e["element"]])
		var dv: Dictionary = e["deliver"]
		if not dv.has("mode") or not StringName(dv["mode"]) in [&"throw", &"launch", &"place", &"mark", &"drop", &"cast", &"world"]:
			bad.append("%s deliver.mode" % id)
	TestLib.check(bad.is_empty(), "every entry is complete and valid %s" % ", ".join(bad.slice(0, 6)))

	# --- falloff: flat core, linear, quadratic, flat curve; nothing beyond the radius
	for id: StringName in [&"gr_frag", &"la_mortar", &"gr_blinder", &"st_orbital", &"mn_shaped", &"wb_barrel", &"la_thermo", &"ult_mega"]:
		var e := BlastTable.entry(id)
		var r := float(e["radius"])
		var core := float(e["core"])
		var edge := float(e["edge"])
		var curve := StringName(e["curve"])
		var f_half := BlastTable.factor(e, r * 0.5)
		var f_edge := BlastTable.factor(e, r)
		var f_out := BlastTable.factor(e, r * 1.5)
		var want_half := 1.0
		var want_edge := 1.0
		if curve != &"flat":
			var t_half := clampf((r * 0.5 - core) / maxf(r - core, 0.001), 0.0, 1.0) if r * 0.5 > core else 0.0
			want_half = (1.0 - (1.0 - edge) * t_half) if curve == &"linear" else (edge + (1.0 - edge) * (1.0 - t_half) * (1.0 - t_half))
			want_edge = edge
		TestLib.check(is_equal_approx(f_half, want_half), "%s (%s) share at 0.5 x radius is %.3f (want %.3f)" % [id, curve, f_half, want_half])
		TestLib.check(is_equal_approx(f_edge, want_edge), "%s share at the radius is %.3f (want %.3f)" % [id, f_edge, want_edge])
		TestLib.check(f_out == 0.0, "%s does nothing at 1.5 x radius" % id)
		TestLib.check(is_equal_approx(BlastTable.factor(e, minf(core, r) * 0.9), 1.0), "%s has a full-damage core" % id)
		TestLib.check(BlastTable.factor(e, r * 0.5) >= BlastTable.factor(e, r * 0.9) - 0.0001, "%s falloff never rises with distance" % id)
	var frag := BlastTable.entry(&"gr_frag")
	TestLib.check(is_equal_approx(BlastTable.damage_at(&"gr_frag", &"enemy", 0.0), float((frag["dmg"] as Dictionary)["enemy"])), "damage_at the centre is the table's enemy damage")
	TestLib.check(BlastTable.damage_at(&"gr_frag", &"vehicle", 6.0 + 1.0) > 0.0 and BlastTable.damage_at(&"gr_frag", &"enemy", 6.0 + 1.0) == 0.0, "a car counts its own length on top of the radius, a person does not")

	# --- the legacy numbers did not move
	var w_rocket := BlastTable.entry(&"w_rocket")
	TestLib.check(not w_rocket.is_empty() and is_equal_approx(float(w_rocket["radius"]), 7.0) and is_equal_approx(float((w_rocket["dmg"] as Dictionary)["enemy"]), 220.0) and is_equal_approx(float((w_rocket["dmg"] as Dictionary)["vehicle"]), 200.0),
			"the NOVA LAUNCHER keeps radius 7, 220 damage, 200 against cars")
	var c4 := BlastTable.entry(&"c4")
	TestLib.check(is_equal_approx(float(c4["radius"]), Charges.RADIUS) and is_equal_approx(float((c4["dmg"] as Dictionary)["hero"]), Charges.SELF_DAMAGE), "the C4 charge keeps its radius and its self damage")
	TestLib.check(is_equal_approx(BlastTable.factor(w_rocket, 7.0 + 0.8, 0.8), 0.4), "a migrated blast keeps its old 40 % at the edge of the reach")

	# --- registration: a quantum snake bomb of wave 115 joins in one call
	var e2 := BlastTable.register(&"test_snake_bomb", {"cat": &"ordnance", "name": "SNAKE BOMB", "radius": 4.2, "enemy": 90.0, "vehicle": 70.0, "element": &"quantum"})
	TestLib.check(BlastTable.has_entry(&"test_snake_bomb") and is_equal_approx(float(e2["radius"]), 4.2) and BlastTable.damage_at(&"test_snake_bomb", &"enemy", 0.0) > 89.0, "register() adds a complete entry")
	BlastTable.unregister(&"test_snake_bomb")
	TestLib.check(not BlastTable.has_entry(&"test_snake_bomb"), "unregister() removes it")

	# --- the arsenal as weapons of the BLAST class
	var pack := WeaponDefsBlast.ids()
	TestLib.check(pack.size() == 46, "46 hand-carried entries become weapons (%d)" % pack.size())
	var ok_defs := true
	var band_msgs := PackedStringArray()
	var carbine := BalanceModel.weapon_dps(&"carbine")
	for id: StringName in pack:
		var d := WeaponDefs.def(id)
		if not WeaponDefs.DEFS.has(id) or String(d["kind"]) != "throw" or StringName(d.get("bid", &"")) != id or WeaponDefs.class_of(id) != &"blast":
			ok_defs = false
			band_msgs.append("%s def" % id)
			continue
		var e := BlastTable.entry(id)
		if not is_equal_approx(float(d["blast_radius"]), float(e["radius"])) or not is_equal_approx(BlastTable.radius_of_def(d), float(e["radius"])):
			band_msgs.append("%s radius copy" % id)
		var ratio := BalanceModel.weapon_dps(id) / carbine
		if ratio < BalanceModel.WEAPON_BAND.x or ratio > BalanceModel.WEAPON_BAND.y:
			band_msgs.append("%s dps %.2f" % [id, ratio])
		var kills := (float(d["mag"]) + float(d["reserve"])) * float(d["damage"]) * float(BalanceModel.ACC[id]) / BalanceModel.op_hp(0, 1)
		if kills < BalanceModel.AMMO_KILLS_MIN:
			band_msgs.append("%s ammo %.1f" % [id, kills])
		if not WeaponLadder.entry(id).is_empty() == false or ShopScreen.SHOP_WEAPONS.find(id) < 0:
			band_msgs.append("%s not on the ladder or in the shop" % id)
		if Economy.weapon_price(id) <= 0:
			band_msgs.append("%s has no price" % id)
	TestLib.check(ok_defs, "every arsenal weapon is a throw def with its blast id, in the BLAST class")
	TestLib.check(band_msgs.is_empty(), "the arsenal weapons sit in the dps band, a full reserve kills 5.5 operatives, each is priced and on the ladder %s" % ", ".join(band_msgs.slice(0, 5)))
	TestLib.check(WeaponDefs.IDS.size() >= 58 + 46, "the roster counts the arsenal (%d weapons)" % WeaponDefs.IDS.size())
