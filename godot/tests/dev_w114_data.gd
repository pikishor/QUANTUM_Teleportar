extends RefCounted
## DEV PROBE of the wave 114 play critic (not a regression test): is every weapon obtainable (a route in the ladder, a price, a crate on land), does every def carry what the screens and the hand need.
## Prints PROBE lines. Run: tools/test.sh tests/dev_w114_data.gd

const TIMEOUT_SECONDS := 100.0


func run(host: Node) -> void:
	WeaponDefs.reset_unlocked()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await TestLib.frames(host, 8)
	var no_route: Array[String] = []
	var routes := {}
	var no_price: Array[String] = []
	var crate_ids := {}
	for c: Dictionary in WeaponLadder.CRATES:
		crate_ids[StringName(c["weapon"])] = true
	var bad_crate: Array[String] = []
	var water_crate: Array[String] = []
	var nc := WeaponLadder.CRATES.size()
	for i in nc:
		var cp := WeaponLadder.crate_pos(i)
		if not cp.is_finite():
			bad_crate.append("crate %d at %s" % [i, cp])
			continue
		if is_instance_valid(Game.world) and Game.world.has_method(&"ground_height"):
			var gh := float(Game.world.call(&"ground_height", cp.x, cp.z))
			if gh < -0.5:
				water_crate.append("crate %d (%s) at (%.0f,%.0f) ground %.1f" % [i, WeaponLadder.CRATES[i]["weapon"], cp.x, cp.z, gh])
	for id: StringName in WeaponDefs.all_ids():
		if WeaponDefs.STARTERS.has(id):
			routes["starter"] = int(routes.get("starter", 0)) + 1
			continue
		var e := WeaponLadder.entry(id)
		var r := StringName(e.get("route", &""))
		if e.is_empty():
			no_route.append(String(id))
		else:
			routes[String(r)] = int(routes.get(String(r), 0)) + 1
		if WeaponDefs.price(id) <= 0 and r == WeaponLadder.SHOP:
			no_price.append(String(id))
	print("PROBE routes ", routes)
	print("PROBE weapons without a ladder route: %d  %s" % [no_route.size(), ", ".join(no_route.slice(0, 40))])
	print("PROBE shop routes without a price: %s" % ", ".join(no_price))
	print("PROBE crates %d, bad positions %s" % [nc, str(bad_crate.slice(0, 5))])
	print("PROBE crates on water or below sea level: %d %s" % [water_crate.size(), str(water_crate.slice(0, 8))])
	# how many weapons does the shop sell, how many crates exist in the main city, how many secret caches
	var secret := 0
	for c: Dictionary in WeaponLadder.CRATES:
		secret += 1 if bool(c.get("secret", false)) else 0
	print("PROBE secret caches %d of %d crates" % [secret, nc])

	# numeric sanity of every def and the numbers the screens show
	var odd: Array[String] = []
	var fast: Array[String] = []
	for id: StringName in WeaponDefs.all_ids():
		var d := WeaponDefs.def(id)
		for k: String in ["interval", "reload", "mag", "damage", "range", "zoom", "vol", "kick", "spread_hip", "spread_ads", "pellets"]:
			if not d.has(k):
				odd.append("%s lacks %s" % [id, k])
				continue
			var v := float(d[k])
			if is_nan(v) or is_inf(v):
				odd.append("%s %s=%s" % [id, k, v])
		if d.has("interval"):
			var iv := float(d["interval"])
			if iv < 0.045 and String(d["kind"]) != "melee":
				fast.append("%s %.3f s (%.0f rpm)" % [id, iv, 60.0 / iv])
			if iv > 4.0:
				odd.append("%s interval %.2f" % [id, iv])
		if d.has("zoom") and (float(d["zoom"]) < 15.0 or float(d["zoom"]) > 80.0):
			odd.append("%s zoom %.0f" % [id, float(d["zoom"])])
		if d.has("reload") and (float(d["reload"]) < 0.2 or float(d["reload"]) > 8.0):
			odd.append("%s reload %.2f" % [id, float(d["reload"])])
		if d.has("mag") and int(d["mag"]) < 1:
			odd.append("%s mag %d" % [id, int(d["mag"])])
	print("PROBE odd numbers: %d %s" % [odd.size(), "; ".join(odd.slice(0, 20))])
	print("PROBE faster than 1300 rpm (a shot every <0.045 s; the Sfx shot family only starts one per 0.04 s): %d %s" % [fast.size(), "; ".join(fast.slice(0, 12))])

	# polyphony: how many voices of the shot family one weapon keeps busy (body length / interval); the family cap is 6 voices
	var poly: Array = []
	for id: StringName in WeaponDefs.all_ids():
		var d := WeaponDefs.def(id)
		if String(d["kind"]) != "hit":
			continue
		var sd := WeaponAudio.data(WeaponAudio.set_of(id))
		if sd.is_empty():
			continue
		var vs := Sfx.variants_of(StringName(sd["body"]))
		if vs.is_empty():
			poly.append([id, 99.0, 0.0, "NO STREAM " + String(sd["body"])])
			continue
		var len := 0.0
		for v in vs:
			len = maxf(len, float((v as AudioStream).get_length()))
		var iv := float(d["interval"])
		var rate_k := 1.0
		poly.append([id, len / maxf(iv, 0.02), len, "%s %.2f s every %.3f s" % [sd["body"], len, iv]])
	poly.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var over6 := 0
	var over4 := 0
	for pr: Array in poly:
		over6 += 1 if float(pr[1]) > 6.0 else 0
		over4 += 1 if float(pr[1]) > 4.0 else 0
	print("PROBE shot polyphony: %d hitscan weapons need more than 6 voices at full auto, %d more than 4" % [over6, over4])
	for k in mini(14, poly.size()):
		print("PROBE   %-14s %.1f voices  %s" % [poly[k][0], poly[k][1], poly[k][3]])

	# ammo packs: a pickup of an owned weapon adds AMMO_PACK rounds (6 when the table has no row); how much is that against the magazine and the reserve
	var tiny: Array[String] = []
	var missing: Array[String] = []
	for id: StringName in WeaponDefs.all_ids():
		var d := WeaponDefs.def(id)
		var reserve := int(d["reserve"])
		if reserve <= 0:
			continue
		var has_row := PlayerWeapon.AMMO_PACK.has(id)
		var pack := int(PlayerWeapon.AMMO_PACK.get(id, 6))
		var mag := int(d["mag"])
		if not has_row:
			missing.append("%s (mag %d, reserve %d)" % [id, mag, reserve])
		if pack * 4 < mag and mag >= 20:
			tiny.append("%s pack %d for a magazine of %d" % [id, pack, mag])
	print("PROBE ammo packs: %d weapons have no row (default 6 rounds) %s" % [missing.size(), "; ".join(missing.slice(0, 10))])
	print("PROBE ammo packs smaller than a quarter of the magazine: %d %s" % [tiny.size(), "; ".join(tiny.slice(0, 10))])

	# enemy hands: every weapon id as a LOD0 / LOD2 weapon piece set for an enemy, grips and muzzle finite
	var bad_foe: Array[String] = []
	var tris_max := 0
	for id: StringName in WeaponDefs.all_ids():
		var pcs := FoeArms.pieces(id, 0, 0)
		var tris := 0
		for pc in pcs:
			tris += (pc["idx"] as PackedInt32Array).size() / 3
		tris_max = maxi(tris_max, tris)
		var st := FoeArms.setup(null, null, id)
		var pcs2 := FoeArms.pieces(id, 0, 2)
		var tris2 := 0
		for pc2 in pcs2:
			tris2 += (pc2["idx"] as PackedInt32Array).size() / 3
		if pcs.is_empty() or tris < 30 or tris > FoeArms.TARGET_TRIS[0] + 120 or not is_finite(float(st["muzzle_shift"])) or not is_finite(float(st["reach"])) or tris2 > FoeArms.TARGET_TRIS[2] + 120 or tris2 < 10:
			bad_foe.append("%s tris %d / %d reach %s shift %s" % [id, tris, tris2, st["reach"], st["muzzle_shift"]])
	print("PROBE enemy weapon pieces: %d of %d weapons odd (max %d tris at LOD0) %s" % [bad_foe.size(), WeaponDefs.all_ids().size(), tris_max, "; ".join(bad_foe.slice(0, 8))])
	# upgrade of the hero_mode: everything owned
	print("PROBE all_ids %d, owned at start %d" % [WeaponDefs.all_ids().size(), WeaponDefs.owned_ordered().size()])
	Game.state = &"menu"
	main.queue_free()
	await TestLib.frames(host, 2)
