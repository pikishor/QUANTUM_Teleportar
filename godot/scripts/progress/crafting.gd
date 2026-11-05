class_name Crafting
extends RefCounted
## Weapon crafting and mods. Static state like SkillTree / Attachments (the bench screen, the player's weapon, the vendors and the save all read it).
## Materials: SCRAP, ALLOY, QUANTUM CORE (`parts`), found as loot (pickups), on kills, as mission payouts (side jobs, contracts, interior jobs, heists, overseers) and sold by tech vendors and the
## bench. Blueprints (`known`) say what can be made: a MOD (one slot per weapon, any weapon) or a VARIANT of one weapon. Every crafted item rolls a rarity (COMMON, RARE, EPIC, LEGENDARY),
## 1 to 4 stat multipliers (damage, crit, fire rate, reload, magazine, spread, kick, range) and sometimes a perk: CHAIN ARC (hits arc to nearby enemies), PHASE ROUNDS (shots pass shields)
## or SINGULARITY ON CRIT (a crit opens a short pull and blast). Perks grow with the skill tree (PERKS[..]["skill"]: each rank of the linked node adds 20 % potency, CHAIN ARC also a jump).
## Items live in `items` (cap ITEM_CAP), `equipped` is weapon -> {mod: uid, variant: uid}; Attachments.effective() calls apply() so everything shows up in the weapon definition.
## Prices, fees and dismantle yields are in Economy. Save: [crafting] (parts, blueprints, items with their rolled stats, equipped, next uid); older saves load the defaults.

const PART_IDS: Array[StringName] = [&"scrap", &"alloy", &"core"]
const PART_NAME := {&"scrap": "SCRAP", &"alloy": "ALLOY", &"core": "QUANTUM CORE"}
const RARITY_NAME: Array[String] = ["COMMON", "RARE", "EPIC", "LEGENDARY"]
const RARITY_COLOR: Array[Color] = [Color(0.8, 0.85, 0.9), Color(0.35, 0.75, 1.0), Color(0.78, 0.45, 1.0), Color(1.0, 0.74, 0.25)]
const RARITY_WEIGHT: Array[float] = [60.0, 28.0, 10.0, 2.0]
const RARITY_WEIGHT_BOOST: Array[float] = [18.0, 44.0, 29.0, 9.0]
const RARITY_SCALE: Array[float] = [0.05, 0.09, 0.14, 0.20]          ## base size of one stat roll
const MOD_STAT_COUNT: Array[int] = [1, 2, 2, 3]
const VARIANT_EXTRA := 1                                              ## variants roll one more stat ...
const VARIANT_SCALE := 1.4                                            ## ... and bigger ones
const PERK_CHANCE_MOD: Array[float] = [0.0, 0.25, 0.6, 1.0]
const PERK_CHANCE_VARIANT: Array[float] = [0.0, 0.3, 0.7, 1.0]
const ITEM_CAP := 36
const STAT_MIN := 0.5
const STAT_MAX := 1.8
const SKILL_POTENCY := 0.2
## stat key: [direction (+1 the multiplier grows, -1 it shrinks), size factor, label]
const STATS := {
	"damage": [1.0, 1.0, "DAMAGE"], "crit": [1.0, 1.2, "CRIT"], "interval": [-1.0, 0.8, "FIRE RATE"], "reload": [-1.0, 0.8, "RELOAD"],
	"mag": [1.0, 1.5, "MAGAZINE"], "spread_hip": [-1.0, 1.4, "SPREAD"], "kick": [-1.0, 1.2, "KICK"], "range": [1.0, 1.3, "RANGE"],
}
const STAT_KEYS: Array[String] = ["damage", "crit", "interval", "reload", "mag", "spread_hip", "kick", "range"]
const PERK_IDS: Array[StringName] = [&"chain_arc", &"phase_rounds", &"singularity_crit"]
const PERKS := {
	&"chain_arc": {"name": "CHAIN ARC", "note": "HITS ARC TO NEARBY ENEMIES", "skill": &"tp_hops"},
	&"phase_rounds": {"name": "PHASE ROUNDS", "note": "SHOTS PASS THROUGH SHIELDS", "skill": &"sp_count"},
	&"singularity_crit": {"name": "SINGULARITY ON CRIT", "note": "A CRIT OPENS A PULL AND BLAST", "skill": &"co_radius"},
}
## Blueprints: the mods (fixed list) and one variant per weapon (`var_<weapon>`). parts = what one craft uses.
const MOD_BPS := {
	&"mod_basic": {"title": "TUNED MOD", "perk": &"", "parts": {&"scrap": 3}},
	&"mod_arc": {"title": "ARC MOD", "perk": &"chain_arc", "parts": {&"scrap": 4, &"alloy": 1}},
	&"mod_phase": {"title": "PHASE MOD", "perk": &"phase_rounds", "parts": {&"scrap": 4, &"alloy": 2}},
	&"mod_singularity": {"title": "SINGULARITY MOD", "perk": &"singularity_crit", "parts": {&"scrap": 4, &"alloy": 2, &"core": 1}},
}
const MOD_ORDER: Array[StringName] = [&"mod_basic", &"mod_arc", &"mod_phase", &"mod_singularity"]
const START_KNOWN: Array[StringName] = [&"mod_basic", &"var_carbine"]
## Drops: source -> {part id: [chance, min, max], "bp": chance of one unknown blueprint}.
const DROPS := {
	&"kill": {&"scrap": [0.22, 1, 2], &"alloy": [0.05, 1, 1], &"core": [0.004, 1, 1], "bp": 0.012},
	&"elite": {&"scrap": [0.6, 2, 3], &"alloy": [0.3, 1, 2], &"core": [0.05, 1, 1], "bp": 0.08},
	&"boss": {&"scrap": [1.0, 4, 6], &"alloy": [1.0, 2, 3], &"core": [0.6, 1, 1], "bp": 0.6},
	&"loot": {&"scrap": [0.4, 1, 2], &"alloy": [0.1, 1, 1], &"core": [0.01, 1, 1], "bp": 0.03},
	&"side": {&"scrap": [1.0, 2, 3], &"alloy": [0.6, 1, 1], &"core": [0.1, 1, 1], "bp": 0.3},
	&"contract": {&"scrap": [1.0, 3, 4], &"alloy": [0.8, 1, 2], &"core": [0.2, 1, 1], "bp": 0.35},
	&"heist": {&"scrap": [1.0, 4, 5], &"alloy": [1.0, 2, 2], &"core": [0.5, 1, 1], "bp": 0.5},
}
const QUIET_SOURCES: Array[StringName] = [&"kill", &"elite", &"loot"]   ## drops that toast at most every TOAST_GAP seconds
const TOAST_GAP := 6.0
const ELITE_SCORE := 150
const REWARD_TOAST_DELAY := 2.8

static var parts := {&"scrap": 0, &"alloy": 0, &"core": 0}
static var known: Array[StringName] = []
static var items: Array[Dictionary] = []
static var equipped := {}                  ## weapon id -> {"mod": uid, "variant": uid}
static var next_uid := 1
static var boost := false                  ## the bench's BOOST switch: costs a core, shifts the rarity odds
static var rev := 0                        ## bumped on every change (the HUD re-lays out its buttons)
static var drops := 0                      ## lifetime count of drops, for tests
static var crafted := 0                    ## lifetime count of crafted items
static var rng := RandomNumberGenerator.new()
static var _toast_t := -99.0


static func reset() -> void:
	parts = {&"scrap": 0, &"alloy": 0, &"core": 0}
	known = START_KNOWN.duplicate()
	items = []
	equipped = {}
	next_uid = 1
	boost = false
	rev += 1


# --- blueprints ---------------------------------------------------------------------------------------------------------

static func bp_ids() -> Array[StringName]:
	var out: Array[StringName] = MOD_ORDER.duplicate()
	for w: StringName in WeaponDefs.IDS:
		out.append(StringName("var_%s" % w))
	return out


static func is_bp(id: StringName) -> bool:
	return MOD_BPS.has(id) or (String(id).begins_with("var_") and WeaponDefs.DEFS.has(StringName(String(id).substr(4))))


static func kind_of(bp: StringName) -> StringName:
	return &"mod" if MOD_BPS.has(bp) else &"variant"


## The weapon a variant blueprint is for (&"" for a mod).
static func base_of(bp: StringName) -> StringName:
	return &"" if MOD_BPS.has(bp) else StringName(String(bp).substr(4))


static func bp_title(bp: StringName) -> String:
	if MOD_BPS.has(bp):
		return String(MOD_BPS[bp]["title"])
	return "%s VARIANT" % WeaponDefs.title(base_of(bp)) if is_bp(bp) else "UNKNOWN"


static func bp_short(bp: StringName) -> String:
	if MOD_BPS.has(bp):
		return String(MOD_BPS[bp]["title"])
	return "%s VARIANT" % String(WeaponDefs.def(base_of(bp)).get("tag", "WPN")) if is_bp(bp) else "UNKNOWN"


static func bp_perk(bp: StringName) -> StringName:
	return MOD_BPS[bp]["perk"] if MOD_BPS.has(bp) else &""


static func knows(bp: StringName) -> bool:
	return known.has(bp)


static func learn(bp: StringName) -> bool:
	if not is_bp(bp) or known.has(bp):
		return false
	known.append(bp)
	rev += 1
	return true


static func unknown_bps() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in bp_ids():
		if not known.has(id):
			out.append(id)
	return out


## Parts one craft uses (without the BOOST core).
static func parts_for(bp: StringName) -> Dictionary:
	if MOD_BPS.has(bp):
		return (MOD_BPS[bp]["parts"] as Dictionary).duplicate()
	var price := int(Economy.WEAPON_PRICE.get(base_of(bp), 0))
	var d := {&"scrap": 5, &"alloy": 1 + (1 if price >= 800 else 0)}
	if price >= 1100:
		d[&"core"] = 1
	return d


## Best BENCH level among the owned safehouses (0 when none): each level takes CRAFT_BENCH_DISCOUNT off the fee.
static func bench_level() -> int:
	var prog := Game.progress as Progress
	if prog == null:
		return 0
	var best := 0
	for id: StringName in prog.safehouses_owned:
		best = maxi(best, Safehouses.level(prog, id, &"bench"))
	return best


static func fee(bp: StringName) -> int:
	var base := float(Economy.craft_fee(kind_of(bp)))
	return maxi(5, int(roundf(base * (1.0 - Economy.CRAFT_BENCH_DISCOUNT * float(bench_level())) / 5.0)) * 5)


## {parts: {id: n}, credits: n} of one craft, with the BOOST core when `with_boost`.
static func cost_of(bp: StringName, with_boost := false) -> Dictionary:
	var p := parts_for(bp)
	if with_boost:
		p[&"core"] = int(p.get(&"core", 0)) + Economy.CRAFT_BOOST_CORES
	return {"parts": p, "credits": fee(bp)}


static func part_count(id: StringName) -> int:
	return int(parts.get(id, 0))


static func add_part(id: StringName, n: int) -> void:
	if PART_IDS.has(id) and n > 0:
		parts[id] = mini(part_count(id) + n, 9999)
		rev += 1


static func can_pay(cost: Dictionary) -> bool:
	for id: StringName in cost:
		if part_count(id) < int(cost[id]):
			return false
	return true


static func parts_text(cost: Dictionary) -> String:
	var bits: PackedStringArray = []
	for id: StringName in PART_IDS:
		if cost.has(id):
			bits.append("%d %s" % [int(cost[id]), PART_NAME[id]])
	return "  ".join(bits)


# --- rolling ------------------------------------------------------------------------------------------------------------

static func roll_rarity(with_boost: bool, r: float) -> int:
	var w := RARITY_WEIGHT_BOOST if with_boost else RARITY_WEIGHT
	var total := 0.0
	for x in w:
		total += x
	var at := clampf(r, 0.0, 0.999999) * total
	for i in w.size():
		at -= w[i]
		if at < 0.0:
			return i
	return w.size() - 1


## Pure roll of one item from a blueprint, a rarity and a seed (the same inputs always give the same item). uid is 0 until it enters the inventory.
static func make_item(bp: StringName, rarity: int, seed_value: int) -> Dictionary:
	if not is_bp(bp):
		return {}
	rarity = clampi(rarity, 0, RARITY_NAME.size() - 1)
	var kind := kind_of(bp)
	var rg := RandomNumberGenerator.new()
	rg.seed = seed_value
	var n := MOD_STAT_COUNT[rarity] + (VARIANT_EXTRA if kind == &"variant" else 0)
	var keys: Array[String] = STAT_KEYS.duplicate()
	var stats := {}
	for _i in n:
		var k: String = keys.pop_at(rg.randi() % keys.size())
		var row: Array = STATS[k]
		var size := RARITY_SCALE[rarity] * rg.randf_range(0.6, 1.0) * float(row[1]) * (VARIANT_SCALE if kind == &"variant" else 1.0)
		stats[k] = str(snappedf(clampf(1.0 + float(row[0]) * size, STAT_MIN, STAT_MAX), 0.0001)).to_float()      # the printed value is the stored one: a save round trip is exact
	var perk := bp_perk(bp)
	var roll := rg.randf()
	if perk == &"":
		var chance := (PERK_CHANCE_VARIANT if kind == &"variant" else PERK_CHANCE_MOD)[rarity]
		if roll < chance:
			perk = PERK_IDS[rg.randi() % PERK_IDS.size()]
	return {"uid": 0, "kind": kind, "base": base_of(bp), "bp": bp, "rarity": rarity, "seed": seed_value, "perk": perk, "stats": stats}


static func item(uid: int) -> Dictionary:
	for it: Dictionary in items:
		if int(it["uid"]) == uid:
			return it
	return {}


static func item_name(it: Dictionary) -> String:
	if it.is_empty():
		return ""
	var r := int(it["rarity"])
	if it["kind"] == &"variant":
		return "%s  %s" % [RARITY_NAME[r], WeaponDefs.title(it["base"] as StringName)]
	var perk: StringName = it["perk"]
	return "%s  %s MOD" % [RARITY_NAME[r], String(PERKS[perk]["name"]) if PERKS.has(perk) else "TUNED"]


static func item_short(it: Dictionary) -> String:
	if it.is_empty():
		return ""
	var r := String(RARITY_NAME[int(it["rarity"])]).substr(0, 3)
	if it["kind"] == &"variant":
		return "%s  %s" % [r, String(WeaponDefs.def(it["base"] as StringName).get("tag", "WPN"))]
	var perk: StringName = it["perk"]
	return "%s  %s" % [r, String(PERKS[perk]["name"]).substr(0, 12) if PERKS.has(perk) else "MOD"]


static func stat_text(k: String, m: float) -> String:
	var pct := int(roundf((1.0 / m - 1.0 if k == "interval" else m - 1.0) * 100.0))
	return "%s %+d%%" % [String((STATS[k] as Array)[2]), pct]


static func item_stats_text(it: Dictionary) -> String:
	var bits: PackedStringArray = []
	var st: Dictionary = it.get("stats", {})
	for k: String in STAT_KEYS:
		if st.has(k):
			bits.append(stat_text(k, float(st[k])))
	return "  ".join(bits)


static func perk_text(perk: StringName) -> String:
	if not PERKS.has(perk):
		return ""
	var sk: StringName = PERKS[perk]["skill"]
	return "%s  %s  (+%d%% PER %s RANK)" % [PERKS[perk]["name"], PERKS[perk]["note"], int(SKILL_POTENCY * 100.0), SkillTree.title(sk)]


## 1.0 plus SKILL_POTENCY for every rank of the skill node the perk is linked to.
static func perk_power(perk: StringName) -> float:
	if not PERKS.has(perk):
		return 1.0
	return 1.0 + SKILL_POTENCY * float(SkillTree.rank(PERKS[perk]["skill"] as StringName))


# --- craft, inventory ---------------------------------------------------------------------------------------------------

## "" when `bp` can be crafted now, else the reason.
static func why_not(prog: Progress, bp: StringName, with_boost := false) -> String:
	if prog == null or not is_bp(bp) or not knows(bp):
		return "BLUEPRINT NOT FOUND"
	if kind_of(bp) == &"variant" and not WeaponDefs.is_unlocked(base_of(bp)):
		return "NEEDS %s" % WeaponDefs.title(base_of(bp))
	if items.size() >= ITEM_CAP:
		return "INVENTORY FULL"
	var c := cost_of(bp, with_boost)
	if not can_pay(c["parts"] as Dictionary):
		return "NEED MORE PARTS"
	if prog.credits < int(c["credits"]):
		return "NEED MORE CREDITS"
	return ""


## Craft one item: spends the parts and the fee, rolls rarity and stats, adds it to the inventory. Returns the item ({} when refused).
static func craft(prog: Progress, bp: StringName, with_boost := false) -> Dictionary:
	if why_not(prog, bp, with_boost) != "":
		return {}
	var c := cost_of(bp, with_boost)
	if not prog.spend(int(c["credits"])):
		return {}
	var cp: Dictionary = c["parts"]
	for id: StringName in cp:
		parts[id] = part_count(id) - int(cp[id])
	var it := make_item(bp, roll_rarity(with_boost, rng.randf()), rng.randi())
	add_item(it)
	crafted += 1
	_commit(prog)
	return it


static func add_item(it: Dictionary) -> void:
	it["uid"] = next_uid
	next_uid += 1
	items.append(it)


static func equipped_on(uid: int) -> StringName:
	for w: StringName in equipped:
		for slot: String in (equipped[w] as Dictionary):
			if int((equipped[w] as Dictionary)[slot]) == uid:
				return w
	return &""


static func slot_item(weapon: StringName, slot: String) -> Dictionary:
	return item(int((equipped.get(weapon, {}) as Dictionary).get(slot, 0)))


static func has_gear(weapon: StringName) -> bool:
	return not (equipped.get(weapon, {}) as Dictionary).is_empty()


## Equip an item: a mod on `weapon`, a variant on its own weapon. It leaves whatever weapon held it. Returns false for an unknown item or a weapon you do not own.
static func equip(prog: Progress, uid: int, weapon: StringName) -> bool:
	var it := item(uid)
	if it.is_empty():
		return false
	var slot := "variant" if it["kind"] == &"variant" else "mod"
	var w: StringName = it["base"] if slot == "variant" else weapon
	if not WeaponDefs.DEFS.has(w) or not WeaponDefs.is_unlocked(w):
		return false
	_unequip_item(uid)
	var d: Dictionary = equipped.get(w, {})
	d[slot] = uid
	equipped[w] = d
	_commit(prog)
	return true


static func unequip(prog: Progress, uid: int) -> bool:
	if equipped_on(uid) == &"":
		return false
	_unequip_item(uid)
	_commit(prog)
	return true


static func _unequip_item(uid: int) -> void:
	for w: StringName in equipped.keys():
		var d: Dictionary = equipped[w]
		for slot: String in d.keys():
			if int(d[slot]) == uid:
				d.erase(slot)
		if d.is_empty():
			equipped.erase(w)


## Dismantle an item: it leaves the inventory (and the weapon) and returns parts by rarity (Economy.DISMANTLE_YIELD).
static func dismantle(prog: Progress, uid: int) -> Dictionary:
	var it := item(uid)
	if it.is_empty():
		return {}
	_unequip_item(uid)
	items.erase(it)
	var y: Dictionary = Economy.DISMANTLE_YIELD[int(it["rarity"])]
	for id: StringName in y:
		add_part(id, int(y[id]))
	_commit(prog)
	return y.duplicate()


static func _commit(prog: Progress) -> void:
	rev += 1
	var p := Game.player
	if is_instance_valid(p) and p.get(&"weapon") is PlayerWeapon:
		(p.get(&"weapon") as PlayerWeapon).apply_upgrades(false)
	if prog != null:
		prog.changed.emit()
		if prog.autosave_enabled:
			prog.save_file()


## The skill tree changed (a rank bought, a respec): perks scale with it, so the weapon in hand reloads its numbers.
static func refresh_weapon() -> void:
	rev += 1
	var p := Game.player
	if is_instance_valid(p) and p.get(&"weapon") is PlayerWeapon:
		(p.get(&"weapon") as PlayerWeapon).apply_upgrades(false)


# --- applying to a weapon definition ------------------------------------------------------------------------------------

## Applies the equipped variant and mod of `weapon` to `out` (a copy of its definition; the base DEFS never change).
static func apply(out: Dictionary, weapon: StringName) -> void:
	var eq: Dictionary = equipped.get(weapon, {})
	for slot: String in ["variant", "mod"]:
		var it := item(int(eq.get(slot, 0)))
		if it.is_empty():
			continue
		var st: Dictionary = it["stats"]
		for k: String in st:
			if not out.has(k):
				continue
			var v := float(out[k]) * float(st[k])
			out[k] = maxi(1, int(roundf(v))) if k == "mag" else v
		_apply_perk(out, it["perk"] as StringName, int(it["rarity"]))


static func _apply_perk(out: Dictionary, perk: StringName, rarity: int) -> void:
	var power := perk_power(perk)
	var kind := String(out.get("kind", "hit"))
	match perk:
		&"chain_arc":
			if kind == "hit":
				var jumps := int(out.get("chain", 0)) + 1 + (1 if rarity >= 3 else 0) + SkillTree.rank(&"tp_hops")
				out["chain"] = jumps
				out["chain_range"] = maxf(float(out.get("chain_range", 0.0)), 6.0 * power)
				out["chain_k"] = maxf(float(out.get("chain_k", 0.0)), 0.4 + 0.05 * float(rarity))
		&"phase_rounds":
			out["pierce_shield"] = true
			if out.has("range"):
				out["range"] = float(out["range"]) * (1.0 + 0.08 * power)
		&"singularity_crit":
			out["sing"] = {"radius": 4.0 * power, "dmg": (16.0 + 6.0 * float(rarity)) * power, "pull": 1.8, "cd": 0.7}


# --- drops, supply ------------------------------------------------------------------------------------------------------

## Pure drop roll of a source with `r`: {parts: {id: n}, bp: StringName (&"" none)}. The blueprint is an unknown one, or a CORE when everything is known.
static func roll_drop(source: StringName, r: RandomNumberGenerator) -> Dictionary:
	var out := {"parts": {}, "bp": &""}
	if not DROPS.has(source):
		return out
	var t: Dictionary = DROPS[source]
	for id: StringName in PART_IDS:
		if not t.has(id):
			continue
		var row: Array = t[id]
		if r.randf() < float(row[0]):
			(out["parts"] as Dictionary)[id] = r.randi_range(int(row[1]), int(row[2]))
	if r.randf() < float(t["bp"]):
		var unk := unknown_bps()
		if unk.is_empty():
			(out["parts"] as Dictionary)[&"core"] = int((out["parts"] as Dictionary).get(&"core", 0)) + 1
		else:
			out["bp"] = unk[r.randi() % unk.size()]
	return out


static func drop_text(d: Dictionary) -> String:
	var bits: PackedStringArray = []
	var dp: Dictionary = d["parts"]
	for id: StringName in PART_IDS:
		if dp.has(id):
			bits.append("+%d %s" % [int(dp[id]), PART_NAME[id]])
	if d["bp"] != &"":
		bits.append("BLUEPRINT  %s" % bp_title(d["bp"] as StringName))
	return "  ".join(bits)


## Rolls and gives a drop of `source`. Quiet sources toast at most every TOAST_GAP s, mission payouts toast after REWARD_TOAST_DELAY s (their own banner shows first).
static func award(source: StringName) -> Dictionary:
	var d := roll_drop(source, rng)
	var dp: Dictionary = d["parts"]
	if dp.is_empty() and d["bp"] == &"":
		return d
	for id: StringName in dp:
		add_part(id, int(dp[id]))
	if d["bp"] != &"":
		learn(d["bp"] as StringName)
	drops += 1
	var text := drop_text(d)
	if QUIET_SOURCES.has(source):
		var now := PlayerUtil.now()
		if d["bp"] != &"" or now - _toast_t >= TOAST_GAP:
			_toast_t = now
			Game.say(text, 1.4)
	else:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.create_timer(REWARD_TOAST_DELAY).timeout.connect(func() -> void:
				if Game.state == &"play":
					Game.say(text, 2.0))
		else:
			Game.say(text, 2.0)
	return d


## A kill: an elite (score from ELITE_SCORE) drops better, a boss best.
static func on_kill(score: int, boss: bool) -> void:
	award(&"boss" if boss else (&"elite" if score >= ELITE_SCORE else &"kill"))


static func shop_discount(prog: Progress) -> float:
	return prog.shop_discount() if prog != null else 0.0


static func _disc(base: int, prog: Progress) -> int:
	return maxi(5, int(roundf(float(base) * (1.0 - shop_discount(prog)) / 5.0)) * 5)


static func part_price(id: StringName, prog: Progress) -> int:
	return _disc(Economy.craft_part_price(id) * int(Economy.CRAFT_PART_BUNDLE.get(id, 1)), prog)


static func bp_price(bp: StringName, prog: Progress) -> int:
	return _disc(Economy.blueprint_price(bp), prog)


## Buy one bundle of a part (Economy.CRAFT_PART_BUNDLE units).
static func buy_part(prog: Progress, id: StringName) -> bool:
	if prog == null or not PART_IDS.has(id) or not prog.spend(part_price(id, prog)):
		return false
	add_part(id, int(Economy.CRAFT_PART_BUNDLE[id]))
	_commit(prog)
	return true


static func buy_blueprint(prog: Progress, bp: StringName) -> bool:
	if prog == null or not is_bp(bp) or knows(bp) or prog.credits < bp_price(bp, prog) or not prog.spend(bp_price(bp, prog)):
		return false
	learn(bp)
	_commit(prog)
	return true


## DEMO: every blueprint, a pile of parts, and one LEGENDARY item per perk (a mod each, plus a variant of the carbine). Nothing is equipped.
static func grant_all(prog: Progress) -> void:
	for id: StringName in bp_ids():
		learn(id)
	for id: StringName in PART_IDS:
		parts[id] = maxi(part_count(id), 99)
	var seed_value := 1000
	for bp: StringName in [&"mod_arc", &"mod_phase", &"mod_singularity", &"var_carbine"]:
		if items.size() < ITEM_CAP:
			add_item(make_item(bp, 3, seed_value))
		seed_value += 1
	_commit(prog)


# --- save ---------------------------------------------------------------------------------------------------------------

static func _stats_str(st: Dictionary) -> String:
	var bits: PackedStringArray = []
	for k: String in STAT_KEYS:
		if st.has(k):
			bits.append("%s:%s" % [k, str(snappedf(float(st[k]), 0.0001))])
	return ";".join(bits)


static func to_save() -> Dictionary:
	var d := {}
	for id: StringName in PART_IDS:
		d[String(id)] = part_count(id)
	var bps := PackedStringArray()
	for b: StringName in known:
		bps.append(String(b))
	d["bps"] = bps
	var its := PackedStringArray()
	for it: Dictionary in items:
		its.append("%d|%s|%s|%s|%d|%d|%s|%s" % [int(it["uid"]), it["kind"], it["base"], it["bp"], int(it["rarity"]), int(it["seed"]), it["perk"], _stats_str(it["stats"])])
	d["items"] = its
	var eq := PackedStringArray()
	for w: StringName in equipped:
		var row: Dictionary = equipped[w]
		eq.append("%s|%d|%d" % [w, int(row.get("mod", 0)), int(row.get("variant", 0))])
	d["eq"] = eq
	d["next"] = next_uid
	return d


static func _num(v: Variant) -> int:
	return int(v) if (v is int or (v is float and is_finite(float(v)))) else 0


static func _parse_item(line: String) -> Dictionary:
	var f := line.split("|")
	if f.size() != 8:
		return {}
	var bp := StringName(f[3])
	if not is_bp(bp) or StringName(f[1]) != kind_of(bp) or StringName(f[2]) != base_of(bp) or not f[0].is_valid_int() or not f[4].is_valid_int() or not f[5].is_valid_int():
		return {}
	var uid := int(f[0])
	if uid <= 0:
		return {}
	var perk := StringName(f[6])
	if perk != &"" and not PERK_IDS.has(perk):
		return {}
	var stats := {}
	if f[7] != "":
		for part in f[7].split(";"):
			var kv := part.split(":")
			if kv.size() != 2 or not STAT_KEYS.has(kv[0]) or not kv[1].is_valid_float() or not is_finite(kv[1].to_float()):
				return {}
			stats[kv[0]] = clampf(kv[1].to_float(), STAT_MIN, STAT_MAX)
	return {"uid": uid, "kind": kind_of(bp), "base": base_of(bp), "bp": bp, "rarity": clampi(int(f[4]), 0, RARITY_NAME.size() - 1), "seed": int(f[5]), "perk": perk, "stats": stats}


static func from_save(d: Dictionary) -> void:
	reset()
	for id: StringName in PART_IDS:
		parts[id] = clampi(_num(d.get(String(id), 0)), 0, 9999)
	var bv: Variant = d.get("bps", [])
	if bv is Array or bv is PackedStringArray:
		for b: Variant in bv:
			var id := StringName(str(b))
			if is_bp(id) and not known.has(id):
				known.append(id)
	var iv: Variant = d.get("items", [])
	if iv is Array or iv is PackedStringArray:
		for line: Variant in iv:
			var it := _parse_item(str(line))
			if it.is_empty() or items.size() >= ITEM_CAP or not item(int(it["uid"])).is_empty():
				continue
			items.append(it)
	var top := 0
	for it: Dictionary in items:
		top = maxi(top, int(it["uid"]))
	next_uid = maxi(maxi(_num(d.get("next", 1)), 1), top + 1)
	var ev: Variant = d.get("eq", [])
	if ev is Array or ev is PackedStringArray:
		for line: Variant in ev:
			var f := str(line).split("|")
			if f.size() != 3 or not f[1].is_valid_int() or not f[2].is_valid_int():
				continue
			var w := StringName(f[0])
			if not WeaponDefs.DEFS.has(w):
				continue
			var m := item(int(f[1]))
			var v := item(int(f[2]))
			var row := {}
			if not m.is_empty() and m["kind"] == &"mod" and equipped_on(int(m["uid"])) == &"":
				row["mod"] = int(m["uid"])
			if not v.is_empty() and v["kind"] == &"variant" and v["base"] == w and equipped_on(int(v["uid"])) == &"":
				row["variant"] = int(v["uid"])
			if not row.is_empty():
				equipped[w] = row
	rev += 1
