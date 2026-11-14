class_name WeaponDefsBlast
extends RefCounted
## Roster pack of the BLAST ARSENAL (wave 113): the 46 hand-carried entries of BlastRows (12 thrown grenades, 14 launchers, 10 mines and charges, 10 strike designators) as weapons of the BLAST wheel class,
## merged into the WeaponDefs tables by its PACKS hook (`tables()`, the format of scripts/player/weapon_defs_v3.gd: DEFS, IDS, CLASS_OF, FAMILY_OF, ALTS, HIT_SND, TILT, PROJ plus the rows of Economy.WEAPON_PRICE,
## PlayerWeapon.AMMO_PACK, BalanceModel.ACC, AimAssist.STAGGER, QuantumVfx.WEAPON_CLASS, HeroAnimTuning.WEAPON_CLASS, WeaponModels.SPEC, ShopScreen.SHOP_WEAPONS, WeaponLadder.LADDER and CRATES).
## Every def is `kind: "throw"` with a `bid` (the id of its BlastTable entry): PlayerWeapon._throw hands such a round to BlastOps.weapon_fire, which throws, launches, places or marks it. The numbers of the
## blast itself (radius, damage per target, falloff, status) live in the table, never here: `blast_radius`, `blast_damage` and `car_dmg` of a def are copies for the weapon cards and the aim ring.
## This file must not read WeaponDefs, Economy and the other tables while it builds (they are being built from it); it reads BlastRows and BlastElements, which are pure data.

const Rows := preload("res://scripts/combat/blast_rows.gd")

const CARBINE_DPS := 42.47                   ## BalanceModel.weapon_dps(carbine), see WeaponDefsV3
const WEAPON_CATS: Array[StringName] = [&"grenade", &"launcher", &"mine", &"strike"]
const FAMILY_NAMES := {&"grenade": "THROWN GRENADES", &"launcher": "LAUNCHERS", &"mine": "MINES AND CHARGES", &"strike": "CALLED-IN STRIKES"}
const ALT_NAMES := {&"grenade": "TWIN THROW", &"launcher": "TWIN SHOT", &"mine": "PAIR", &"strike": "DOUBLE MARK"}
const TIER_PRICE := [0, 90, 190, 340, 560, 900, 1400]
const TARGET_POWER := [0.0, 0.8, 0.88, 0.96, 1.05, 1.14, 1.22]       ## sustained dps against the carbine by tier (inside the balance band 0.62 .. 1.7)
const AMMO_KILLS := 6.4                                              ## operatives a full reserve must kill (the balance test asks for 5.5)
const OPERATIVE_HP := 80.0                                           ## BalanceModel.op_hp(0, 1): the health of the operative the ammo check is measured on
const UTILITY_DAMAGE := 70.0                                         ## the nominal damage of a weapon that does none (flash, smoke, EMP): only the balance model reads it
const DROP_TYPES := {&"grenade": [&"operative", &"flanker", &"shield", &"striker"], &"launcher": [&"heavy", &"sentinel", &"brute", &"sniper"], &"mine": [&"sentinel", &"flanker", &"striker", &"operative"],
	&"strike": [&"sniper", &"sentinel", &"heavy", &"brute"]}
## City crates of the arsenal: road junction (x, z of the grid), sidewalk corner sign (sx, sz): different junctions than the guns of the roster pack.
const CITY_SPOTS: Array = [[5, 5, 1.0, 1.0], [5, 12, 1.0, -1.0], [12, 5, -1.0, 1.0], [12, 10, -1.0, -1.0], [8, 13, 1.0, -1.0], [8, 4, -1.0, 1.0], [10, 8, 1.0, 1.0], [6, 8, -1.0, 1.0]]
const CACHE_SITES: Array = [
	[&"observatory", Vector2(-14.0, -10.0)], [&"radio_tower", Vector2(12.0, -9.0)], [&"mine", Vector2(-11.0, 9.0)], [&"crash", Vector2(-30.0, -12.0)], [&"cave", Vector2(-7.0, -5.0)],
	[&"lodge", Vector2(16.0, -10.0)], [&"hunters", Vector2(-18.0, 12.0)], [&"pine_hollow", Vector2(-26.0, -18.0)], [&"dust_wells", Vector2(24.0, -16.0)], [&"south_farm", Vector2(-22.0, 20.0)]]

static var _built := false
static var _defs := {}
static var _ids: Array = []
static var _class_of := {}
static var _family_of := {}
static var _alts := {}
static var _hit_snd := {}
static var _tilt := {}
static var _price := {}
static var _ammo_pack := {}
static var _acc := {}
static var _stagger := {}
static var _vfx := {}
static var _anim := {}
static var _spec := {}
static var _shop: Array = []
static var _ladder: Array = []
static var _crates: Array = []
static var _city_i := 0
static var _site_i := 0


static func tables() -> Dictionary:
	_build()
	return {"defs": _defs, "ids": _ids, "class_of": _class_of, "family_of": _family_of, "alts": _alts, "hit_snd": _hit_snd, "tilt": _tilt, "price": _price, "ammo_pack": _ammo_pack, "acc": _acc,
			"stagger": _stagger, "vfx_class": _vfx, "anim_class": _anim, "spec": _spec, "shop": _shop, "ladder": _ladder, "crates": _crates}


## The ids of this pack in catalogue order (grenades, launchers, mines, strikes).
static func ids() -> Array:
	_build()
	return _ids


static func _build() -> void:
	if _built:
		return
	_built = true
	var drop_i := {}
	for pair: Array in Rows.all():
		var cat := StringName(pair[0])
		if not WEAPON_CATS.has(cat):
			continue
		var row: Array = pair[1]
		var id := StringName(row[0])
		var x: Dictionary = row[7]
		var base: Dictionary = Rows.DEFAULTS[cat]
		var dv: Dictionary = (base["deliver"] as Dictionary).duplicate(true)
		dv.merge(x.get("deliver", {}) as Dictionary, true)
		var wk: Dictionary = (base["w"] as Dictionary).duplicate(true)
		wk.merge(x.get("w", {}) as Dictionary, true)
		var tier := int(x.get("tier", 1))
		var element := StringName(row[6])
		var col: Color = BlastElements.color(element, "mid")
		var radius := float(row[2])
		var enemy := float(row[4])
		var vehicle := float(row[5])
		var mode := StringName(dv["mode"])
		# the expected damage on one target (several shells and bomblets do not all land on one man) and the nominal number of a utility
		var eff := enemy
		var cl: Array = x.get("cluster", [])
		if not cl.is_empty():
			eff *= minf(1.0 + 0.35 * float(int(cl[0]) - 1), 3.0)
		var shells := int(dv.get("count", 1))
		if mode == &"mark" and shells > 1:
			eff *= minf(1.0 + 0.4 * float(shells - 1), 2.6)
		var salvo := int(dv.get("salvo", 1))
		if salvo > 1:
			eff *= minf(1.0 + 0.5 * float(salvo - 1), 3.0)
		if x.has("status") and StringName((x["status"] as Dictionary)["k"]) == &"burn":                     # burning counts for what it does over its time
			eff += float((x["status"] as Dictionary)["p"]) * float((x["status"] as Dictionary)["t"]) * 0.6
		if x.has("fire"):
			eff += float((x["fire"] as Array)[2]) * float((x["fire"] as Array)[1]) * 0.4
		var utility := eff < 60.0
		if utility:
			eff = UTILITY_DAMAGE
		var mag := int(wk["mag"])
		var reserve := int(wk["reserve"])
		var interval := float(wk["interval"]) + 0.00011 * float(_ids.size() + 1)                 # every weapon of the roster has its own fire interval (test_weapons)
		var reload := float(wk["reload"])
		var acc := clampf(0.5 + 0.015 * radius, 0.5, 0.88)
		# bring the sustained dps to this tier's power by scaling the nominal damage, then make sure a full reserve kills enough operatives
		var cycle := interval + 0.3
		var raw := eff * acc / cycle * float(mag) / (float(mag) + reload / cycle)
		var power := float(TARGET_POWER[clampi(tier, 1, 6)])
		eff = eff * clampf(power * CARBINE_DPS / maxf(raw, 0.01), 0.45, 2.2)
		var guard := 0
		while float(mag + reserve) * eff * acc / OPERATIVE_HP < AMMO_KILLS and guard < 40:
			reserve += 1
			guard += 1
		var launch := mode == &"launch"
		var d := {"name": String(row[1]), "tag": String(x.get("tag", String(id).substr(3, 3).to_upper())), "kind": "throw", "family": cat, "bid": id, "mag": mag, "reserve": reserve, "interval": interval,
				"damage": snappedf(eff, 0.5), "crit": snappedf(eff, 0.5), "pellets": 1, "pattern": [Vector2(0.0, 0.6)], "shake": clampf(0.04 + radius * 0.012, 0.04, 0.2), "vol": float(wk.get("vol", -2.0)),
				"pitch_lo": float(wk.get("pitch", 1.0)) - 0.05, "pitch_hi": float(wk.get("pitch", 1.0)) + 0.05, "eject": 0, "flash": 0.0, "ads_kick": 1.0, "ads_spread": 1.0, "spread_hip": 0.0, "spread_ads": 0.0,
				"spread_move": 0.0, "bloom": 0.0, "bloom_max": 0.0, "kick": 0.01 + 0.004 * radius if launch else 0.012, "kick_end": 0.01 + 0.004 * radius if launch else 0.012, "kick_yaw": 0.0, "reload": reload,
				"range": float(wk.get("range", 60.0)), "falloff_from": 9999.0, "tracer": col, "look": col, "look_size": Vector3(0.12, 0.12, 0.3 + 0.35 * float(launch)), "zoom": 56.0, "pierce_shield": true,
				"speed": float(dv.get("speed", 20.0)), "fuse": maxf(float(dv.get("fuse", 2.0)), 0.1), "grav": float(dv.get("grav", 22.0)), "well_time": 0.1, "well_radius": radius, "well_pull": 0.0, "well_dps": 0.0,
				"blast_radius": radius, "impact": bool(dv.get("impact", false)), "blast_damage": enemy, "car_dmg": vehicle, "blast_color": col, "blast_element": element, "launch": launch,
				"snd": StringName(wk.get("snd", &"shot")), "tier": tier, "role": String(x.get("note", "")), "utility": utility, "mode": mode, "mlen": 1.0, "slots": 3}
		var price := int(roundf(float(TIER_PRICE[clampi(tier, 1, 6)]) * (1.0 + 0.25 * float(cat == &"strike") + 0.1 * float(cat == &"launcher")) / 5.0)) * 5
		d["price"] = maxi(price, 25)
		_defs[id] = d
		_ids.append(id)
		_class_of[id] = &"blast"
		_family_of[id] = cat
		_price[id] = int(d["price"])
		_ammo_pack[id] = maxi(1, int(ceilf(float(reserve) / 3.0)))
		_acc[id] = acc
		_stagger[id] = clampf(0.7 + radius * 0.08, 0.7, 1.6)
		_vfx[id] = (&"spray" if element == &"fire" else (&"beam" if element == &"plasma" else (&"arc" if element == &"electric" else &"gravity")))
		_anim[id] = "heavy" if launch else "rifle"
		_tilt[id] = 1.4 if launch else 1.0
		_hit_snd[id] = [0.8, 0.0, &""]
		_spec[id] = {"reach": 0.8 if launch else 0.5, "gr": Vector3(0.0, -0.11, 0.62) if launch else Vector3(0.0, -0.02, 0.14), "gl": Vector3(0.0, -0.12, 0.3) if launch else Vector3(-0.07, -0.12, 0.34)}
		_alts[id] = {"name": String(ALT_NAMES[cat]), "kind": "cluster", "cost": 1, "mult": 1.0, "cd": 4.0 if cat == &"strike" else 1.3}       # a pair for one round: two grenades or rockets in a fan, two mines, two markers
		_shop.append(id)
		_ladder_row(id, d, cat, tier, drop_i)


## The free route of a weapon: the cheap ones in the shop, the middle ones as drops, the strong ones in crates on the street and hidden in the outskirts.
static func _ladder_row(id: StringName, d: Dictionary, cat: StringName, tier: int, drop_i: Dictionary) -> void:
	var route := &"shop"
	if tier >= 2 and tier <= 3:
		route = &"drop" if int(_ids.size()) % 2 == 0 else &"crate"
	elif tier >= 4:
		route = &"crate" if int(_ids.size()) % 3 != 0 else &"drop"
	if route == &"crate":
		var key := "bx_%s" % String(id)
		var title := "%s CRATE" % String(d["name"]).split(" ")[0]
		var crate := {"key": key, "weapon": id, "name": title}
		var secret := _city_i >= CITY_SPOTS.size() or (tier >= 5 and _site_i < CACHE_SITES.size())
		if secret:
			var cs: Array = CACHE_SITES[_site_i % CACHE_SITES.size()]
			var turn := _site_i / CACHE_SITES.size()                                      # a second crate at the same place stands a quarter turn round it
			_site_i += 1
			crate["site"] = cs[0]
			crate["off"] = (cs[1] as Vector2).rotated(PI * 0.5 * float(turn))
			crate["secret"] = true
			crate["name"] = "SECRET CACHE"
		else:
			var sp: Array = CITY_SPOTS[_city_i]
			_city_i += 1
			crate["g"] = Vector2i(int(sp[0]), int(sp[1]))
			crate["sx"] = float(sp[2])
			crate["sz"] = float(sp[3])
		_crates.append(crate)
		_ladder.append({"id": id, "route": &"crate", "crate": key, "arg": 0, "tier": tier})
	elif route == &"drop":
		var list: Array = DROP_TYPES[cat]
		var n := int(drop_i.get(cat, 0))
		drop_i[cat] = n + 1
		_ladder.append({"id": id, "route": &"drop", "arg": list[n % list.size()], "tier": tier})
	else:
		_ladder.append({"id": id, "route": &"shop", "arg": 0, "tier": tier})
