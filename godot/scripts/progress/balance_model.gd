class_name BalanceModel
extends RefCounted
## Pure static balance model shared by tools/balance_sim.gd (prints the tables for docs/BALANCE.md) and tests/test_balance2.gd (asserts the bands).
## It reads the live constants (WeaponDefs, EnemyTypes, Difficulty, HeroPower, Upgrades, SkillTree, Factions, Wanted, Companion, Economy) and models a typical player:
## the hero lands ACC[weapon] of the shots, owns the upgrade level and crafting mods a chapter implies, and fights FOES operatives. Chapters are 0-based here (0 = chapter 1, 8-11 = the sequel).

const CHAPTERS := 12
const FOES := 3
const ENEMY_HIT := 0.35                  ## share of an operative's rounds that land
const HERO_HP := 100.0
const UPGRADE_LEVEL_PER_CHAPTER := 0.7   ## shop damage level the hero holds (cap Upgrades.MAX_LEVEL)
const MOD_GROWTH := 0.03                 ## crafted-mod damage per chapter from chapter 4 on (Crafting RARITY_SCALE rolls)
const MOD_FROM := 3
const ARMOUR_LEVEL_PER_CHAPTER := 0.5    ## shop armour level held
## Share of rounds that land per weapon class (hitscan precise, spread / pellets, area, melee).
const ACC0 := {
	&"carbine": 0.45, &"scatter": 0.55, &"lance": 0.70, &"grenade": 0.80, &"burst": 0.50, &"rail": 0.70, &"flux": 0.35, &"gravity": 0.80, &"minigun": 0.35,
	&"akimbo": 0.42, &"arc": 0.50, &"revolver": 0.55, &"whip": 0.85, &"blade": 0.85, &"pistol": 0.5, &"marksman": 0.65, &"breacher": 0.55, &"rocket": 0.8,
	&"swarm": 0.35, &"vector": 0.4, &"battle": 0.55, &"sawn": 0.55, &"auto": 0.5, &"bolt": 0.75, &"dmr": 0.6, &"knife": 0.85,
	&"magnum": 0.5, &"mpistol": 0.38, &"stun": 0.6, &"ranger": 0.45, &"bullpup": 0.5, &"lmg": 0.4, &"amr": 0.7, &"xbow": 0.8, &"flame": 0.5, &"katana": 0.85, &"bat": 0.85,
	&"qsuper": 0.5, &"qlink": 0.5, &"qcollapse": 0.8, &"qblink": 0.5, &"qphase": 0.45, &"qstasis": 0.5,
	&"eplasma": 0.5, &"erepeat": 0.4, &"espike": 0.5, &"ebeam": 0.7, &"eblade": 0.85, &"emaul": 0.85, &"epod": 0.7, &"railgun": 0.7, &"chaingun": 0.35, &"cmissile": 0.8, &"napalm": 0.8, &"sing": 0.8, &"orbital": 0.8, &"seeker": 0.85, &"tknife": 0.7,
}
static var ACC: Dictionary = ACC0.merged(WeaponDefs.pack_dict("acc"))              ## the roster packs add theirs (WeaponDefs.PACKS)
const WEAPON_BAND := Vector2(0.62, 1.7)  ## sustained DPS of every weapon relative to the carbine must stay inside this band
const MELEE_UPTIME := 0.4               ## share of the time a melee weapon is in reach (closing in, enemies at range)
const AMMO_KILLS_MIN := 5.5             ## operatives one full reserve of a limited weapon kills at chapter 1
const BOSS_TTK_BAND := Vector2(14.0, 52.0)   ## seconds of carbine fire on NORMAL for one boss
const TTK_BAND := Vector2(0.6, 2.2)
const MAX_STEP := 0.12                   ## largest chapter-to-chapter relative change of ttk / survival on one mode

## Campaign boss steps: chapter index -> [{enemy, hp_mult}] (read from CampaignData so a new boss shows up in the table).
static func bosses_at(ch: int) -> Array:
	var out: Array = []
	if ch < 0 or ch >= CampaignData.CAMPAIGN.size():
		return out
	for st: Dictionary in CampaignData.CAMPAIGN[ch]["steps"]:
		if st.get("kind", "") == "assassinate" and st.get("target", "") == "boss":
			var e := StringName(str(st.get("enemy", "overseer")))
			out.append({"enemy": e, "hp_mult": float(st.get("hp_mult", 1.0 if e == &"overseer" else 2.5))})
	return out


static func upgrade_level(ch: int) -> float:
	return minf(float(Upgrades.MAX_LEVEL), UPGRADE_LEVEL_PER_CHAPTER * float(ch))


## Damage factor of the hero's gear in chapter `ch` (shop damage upgrade + crafted mods), before HeroPower.
static func gear_mult(ch: int) -> float:
	return 1.0 + float(Upgrades.DATA[&"damage"]["per"]) * upgrade_level(ch) + MOD_GROWTH * float(maxi(0, ch - MOD_FROM + 1))


static func hero_mult(ch: int, m: int) -> float:
	return gear_mult(ch) * HeroPower.f("dmg", m)


## Sustained damage per second of one weapon on one target: shots per cycle x damage x pellets x accuracy, including reloads and charge time.
static func weapon_dps(id: StringName, ch := 0, m := 1) -> float:
	var d: Dictionary = WeaponDefs.DEFS[id]
	var kind := str(d["kind"])
	var dmg := float(d["damage"]) * float(d.get("pellets", 1))
	var acc: float = ACC[id]
	var interval := float(d["interval"])
	var mag := float(d["mag"])
	var reload := float(d["reload"])
	var dps := 0.0
	match kind:
		"charge":
			var cycle := interval + float(d.get("charge_time", 1.0)) * 0.7
			dps = dmg * acc / cycle * mag / (mag + reload / cycle)
		"throw":
			var well := float(d.get("well_dps", 0.0)) * float(d.get("well_time", 0.0)) * 0.5
			var cycle2 := interval + 0.3
			dps = (dmg + well) * acc / cycle2 * mag / (mag + reload / cycle2)
		"melee":
			var combo: Array = d.get("combo", [1.0])
			var avg := 0.0
			for c in combo:
				avg += float(c)
			dps = dmg * (avg / float(combo.size())) * acc / interval * MELEE_UPTIME
		_:
			var burst := float(d.get("burst", 1))
			var mag_time := mag * interval / burst
			dps = dmg * burst * acc / interval * (mag_time / (mag_time + reload))
			if d.has("chain"):
				dps *= 1.0 + float(d["chain_k"]) * 0.5
	return dps * hero_mult(ch, m)


static func op_hp(ch: int, m: int, type: StringName = &"operative") -> float:
	return float(EnemyTypes.get_cfg(type)["hp"]) * Difficulty.chapter_hp(ch) * Difficulty.mult("hp", m)


static func ttk(id: StringName, ch: int, m: int, type: StringName = &"operative") -> float:
	return op_hp(ch, m, type) / weapon_dps(id, ch, m)


## Incoming dps of one enemy type at a hero hit rate ENEMY_HIT (chapter and mode scaled, shop armour included).
static func enemy_dps(m: int, ch: int, type: StringName = &"operative") -> float:
	var c: Dictionary = EnemyTypes.get_cfg(type)
	var f: Vector2 = c["fire"]
	var burst := maxf(1.0, float(c["burst"]))
	var cycle := (f.x + f.y) * 0.5 / Difficulty.mult("aggr", m) + float(c.get("aim_time", 0.0)) + burst * float(c.get("burst_gap", 0.1))
	var spread_hit := ENEMY_HIT / maxf(Difficulty.mult("spread", m), 0.1) ** 0.5
	return float(c["dmg"]) * burst / cycle * minf(spread_hit, 0.9) * damage_taken(ch, m)


static func armour_level(ch: int) -> float:
	return minf(float(Upgrades.MAX_LEVEL), ARMOUR_LEVEL_PER_CHAPTER * float(ch))


static func damage_taken(ch: int, m: int) -> float:
	return Difficulty.damage_taken(ch, m) * (1.0 - float(Upgrades.DATA[&"armour"]["per"]) * armour_level(ch)) * HeroPower.f("taken", m)


static func hero_hp(_ch: int) -> float:
	return HERO_HP


## Seconds a hero survives against `n` operatives that all shoot at once.
static func survive(ch: int, m: int, n := FOES) -> float:
	return hero_hp(ch) / (enemy_dps(m, ch) * float(n))


## Fight length: seconds to clear FOES operatives one after the other with the carbine, over survive(): below 1 the hero wins before he would die.
static func fight_ratio(ch: int, m: int) -> float:
	var inc := 0.0
	for i in FOES:
		inc += enemy_dps(m, ch) * ttk(&"carbine", ch, m) * float(FOES - i)
	return inc / hero_hp(ch)


## One boss: {enemy, hp, ttk (s, carbine), dps (incoming), dmg_taken_pct (share of hero hp lost during the kill with half the fire on the hero)}.
static func boss_row(ch: int, m: int, enemy: StringName, hp_mult: float) -> Dictionary:
	var cfg: Dictionary = EnemyTypes.get_cfg(enemy)
	var hp := float(cfg["hp"]) * Difficulty.boss_hp(ch) * Difficulty.mult("hp", m) * hp_mult
	var t := hp / weapon_dps(&"carbine", ch, m)
	var inc := enemy_dps(m, ch, enemy) * 0.5
	return {"enemy": enemy, "hp": hp, "ttk": t, "dps": inc, "lost": inc * t / hero_hp(ch)}


## Total boss ttk of a chapter on mode m (0 when the chapter has none).
static func boss_ttk(ch: int, m: int) -> float:
	var t := 0.0
	for b: Dictionary in bosses_at(ch):
		t += float(boss_row(ch, m, b["enemy"], b["hp_mult"])["ttk"])
	return t


# --- abilities ----------------------------------------------------------------------------------------------------------

## The seven abilities: {name, cost (coherence), cd (s), dmg (one use, at the centre), note}.
static func abilities() -> Array[Dictionary]:
	return [
		{"name": "QUANTUM TELEPORT", "cost": Quantum.BLINK_COST, "cd": Quantum.BLINK_CD, "dmg": 0.0},
		{"name": "ENTANGLE LINK", "cost": Quantum.LINK_COST, "cd": Quantum.LINK_CD, "dmg": 0.0},
		{"name": "ENTANGLE SWAP", "cost": Quantum.SWAP_COST, "cd": Quantum.SWAP_CD, "dmg": 0.0},
		{"name": "SUPERPOSITION", "cost": Quantum.SUPER_COST, "cd": Quantum.SUPER_LIFE, "dmg": Quantum.PULSE_DMG},
		{"name": "COLLAPSE", "cost": 0.0, "cd": Quantum.COLLAPSE_CD, "dmg": Quantum.PULSE_DMG * 2.0},
		{"name": "WAVE", "cost": Quantum.WAVE_COST, "cd": Quantum.WAVE_CD, "dmg": Quantum.WAVE_DMG + Quantum.WAVE_LINK_DMG * 0.5},
		{"name": "ARC", "cost": float(QuantumVerbs.COST[&"arc"]), "cd": float(QuantumVerbs.CD[&"arc"]), "dmg": QuantumVerbs.ARC_DMG},
	]


static func energy_regen(m: int) -> float:
	return Player.ENERGY_REGEN * HeroPower.f("energy_regen", m)


## Seconds of regeneration one use costs, scaled by the mode (energy_cost) and, for the sustained rate, floored by its cooldown.
static func ability_period(a: Dictionary, m: int) -> float:
	var cost := float(a["cost"]) * HeroPower.f("energy_cost", m)
	return maxf(float(a["cd"]) * HeroPower.f("cooldown", m), cost / energy_regen(m))


## Damage per second an ability sustains next to the carbine (dmg / period); 0 for the utilities.
static func ability_dps(a: Dictionary, m: int) -> float:
	return float(a["dmg"]) * HeroPower.f("dmg", m) / ability_period(a, m)


# --- skill tree ---------------------------------------------------------------------------------------------------------

const KILLS_PER_CHAPTER := 55.0
const XP_PER_KILL := 20.0

## XP gained by the end of chapter `ch` (0-based, inclusive) on mode m: kills plus mission payouts (CREDITS_PER_XP).
static func skill_xp(ch: int, m: int) -> float:
	var xp := 0.0
	for c in ch + 1:
		var pay := 0.0
		for id: StringName in Economy.CONTRACT_BASE:
			pay += float(Economy.CONTRACT_BASE[id]) * 0.4
		xp += (KILLS_PER_CHAPTER * XP_PER_KILL + pay * Progress.difficulty(c)["reward"] / SkillTree.CREDITS_PER_XP * 3.0) * SkillTree.XP_MULT[m]
	return xp


static func skill_level(ch: int, m: int) -> int:
	var l := 1
	var left := skill_xp(ch, m)
	while l < SkillTree.LEVEL_CAP and left >= float(SkillTree.xp_for(l)):
		left -= float(SkillTree.xp_for(l))
		l += 1
	return l


## Damage factor the tree adds (collapse damage + chain, teleport strike as a share of a 100 hp operative), a gentle ramp from the points spent on offence.
static func skill_mult(ch: int, m: int) -> float:
	var pts := float(skill_level(ch, m) - 1)
	return 1.0 + minf(pts, 20.0) * 0.006 * SkillTree.POWER[m]


# --- factions, wanted, companion ----------------------------------------------------------------------------------------

## Incoming-pressure factor of a faction standing: hostile = one extra reinforcement slot and 1.4x sight, allied = unaware patrol.
static func faction_pressure(status: int) -> float:
	if status == 0:
		return (float(FOES) + 1.0) / float(FOES) * 1.15
	return 0.7 if status == 2 else 1.0


## Enemies that answer a heat level (Wanted responses): 0 none .. 5 elite squad; the pressure factor over FOES operatives.
static func wanted_pressure(level: int) -> float:
	return 1.0 + [0.0, 0.2, 0.45, 0.7, 1.0, 1.4][clampi(level, 0, 5)]


static func companion_dps() -> float:
	var burst := float(Companion.BURST)
	var cycle := Companion.WINDUP + burst * Companion.BURST_GAP + Companion.BURST_REST
	return Companion.FIRE_DMG * burst / cycle * ENEMY_HIT


## Share of the hero's carbine dps the ally adds in chapter `ch` (only the chapters in Companion.CHAPTERS).
static func companion_share(ch: int, m: int) -> float:
	return companion_dps() / weapon_dps(&"carbine", ch, m) if Companion.CHAPTERS.has(ch) else 0.0
