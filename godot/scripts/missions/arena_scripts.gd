class_name ArenaScripts
extends RefCounted
## Pure data and rules of BOSS RUSH and the ENDLESS ARENA (wave 72). The runner is scripts/missions/arena_runner.gd (Game.missions.arena); nothing here touches the scene tree.
## BOSS RUSH: every boss in sequence (RUSH_ORDER) with a short break between them (heal + countdown), difficulty NORMAL / HARD / NIGHTMARE (boss health, pay, break length). A clear
## is timed from the start to the last boss; the five best times per difficulty are kept (Progress.arena, saved in [arena]). A fall ends the run with nothing paid.
## ENDLESS ARENA: waves of Vael troops spawned around the hero on the streets until the hero falls (or LEAVES: the waves cleared are paid). MODIFIERS (any mix): ARMOURED (foe health x1.6),
## SWARM (x1.5 foes), BRUTAL (a boss joins every 4th wave). Each adds to the score and pay multiplier.
## Rewards: credits (RUSH_PAY, ENDLESS_WAVE_PAY) and cosmetics (HeroLook item keys granted free): one per rush difficulty cleared, two for endless wave milestones.

const RUSH_ORDER: Array[StringName] = [&"overseer", &"hound", &"bulwark", &"smelter", &"skimmer", &"phasewright"]
const DIFFS: Array[StringName] = [&"normal", &"hard", &"nightmare"]
const MODS: Array[StringName] = [&"armoured", &"swarm", &"brutal"]
const BOARD_SIZE := 5                  ## best times kept per difficulty
const START_BREAK := 3.0               ## countdown before the first boss / wave 1 (s)
const WAVE_BREAK := 4.0
const BREAK_HEAL := 0.35               ## fraction of max health given at each break
const BOSS_RING := Vector2(34.0, 56.0) ## distance from the hero a boss appears at
const FOE_RING := Vector2(16.0, 30.0)
const MAX_FOES := 8                    ## endless: foes alive at once (the manager cap lowers it)
const BRUTAL_EVERY := 4

const DIFF_DEFS := {
	&"normal": {"title": "NORMAL", "hp": 1.0, "pay": 1.0, "break": 14.0, "note": "Boss health as the story. 14 s breaks."},
	&"hard": {"title": "HARD", "hp": 1.6, "pay": 1.6, "break": 9.0, "note": "Boss health x1.6. 9 s breaks."},
	&"nightmare": {"title": "NIGHTMARE", "hp": 2.4, "pay": 2.4, "break": 5.0, "note": "Boss health x2.4. 5 s breaks."},
}
const MOD_DEFS := {
	&"armoured": {"title": "ARMOURED", "note": "Foe health x1.6", "hp": 1.6, "count": 1.0, "score": 1.3},
	&"swarm": {"title": "SWARM", "note": "Half as many foes again", "hp": 1.0, "count": 1.5, "score": 1.3},
	&"brutal": {"title": "BRUTAL", "note": "A boss every 4th wave", "hp": 1.0, "count": 1.0, "score": 1.5},
}
const RUSH_PAY := {&"normal": 1500, &"hard": 2400, &"nightmare": 3600}
const ENDLESS_WAVE_PAY := 70
const KILL_SCORE := 10
## Cosmetics: HeroLook keys with a credit price, granted free.
const RUSH_COSMETIC := {&"normal": "scheme:3", &"hard": "scheme:6", &"nightmare": "suit:stealth"}
const ENDLESS_COSMETIC := {4: "scheme:1", 8: "scheme:7"}      ## waves cleared in one run -> item

## Foe types by first wave (a wave picks from every type up to its number).
const WAVE_TYPES := [[1, &"sentinel"], [1, &"striker"], [3, &"operative"], [4, &"shield"], [5, &"heavy"], [6, &"flanker"], [8, &"brute"]]
const BRUTAL_BOSSES: Array[StringName] = [&"overseer", &"hound", &"bulwark"]


static func diff_title(d: StringName) -> String:
	return String(DIFF_DEFS.get(d, {}).get("title", String(d).to_upper()))


static func mod_title(m: StringName) -> String:
	return String(MOD_DEFS.get(m, {}).get("title", String(m).to_upper()))


static func rush_hp(d: StringName) -> float:
	return float(DIFF_DEFS.get(d, DIFF_DEFS[&"normal"])["hp"])


static func break_time(d: StringName) -> float:
	return float(DIFF_DEFS.get(d, DIFF_DEFS[&"normal"])["break"])


## Product of a modifier field over the active mods ("hp", "count" or "score").
static func mod_mult(mods: Array, key: String) -> float:
	var m := 1.0
	for id: Variant in mods:
		if MOD_DEFS.has(StringName(id)):
			m *= float(MOD_DEFS[StringName(id)][key])
	return m


static func rush_reward(d: StringName) -> int:
	return int(RUSH_PAY.get(d, 0))


static func endless_reward(waves: int, mods: Array) -> int:
	return int(round(float(maxi(waves, 0) * ENDLESS_WAVE_PAY) * mod_mult(mods, "score")))


## Foes in wave n (1-based): 3 at the start, +1 every wave, SWARM x1.5, never over 40.
static func wave_count(n: int, mods: Array) -> int:
	return clampi(int(ceil(float(2 + maxi(n, 1)) * mod_mult(mods, "count"))), 1, 40)


## The foe types wave n may use (wave 1: sentinel, striker; later waves add the rest).
static func wave_types(n: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for row: Array in WAVE_TYPES:
		if n >= int(row[0]):
			out.append(StringName(row[1]))
	return out


static func is_brutal_wave(n: int, mods: Array) -> bool:
	return mods.has(&"brutal") and n > 0 and n % BRUTAL_EVERY == 0


## The cosmetic keys an endless run of `waves` waves earns (every milestone reached).
static func endless_cosmetics(waves: int) -> Array[String]:
	var out: Array[String] = []
	for w: Variant in ENDLESS_COSMETIC:
		if waves >= int(w):
			out.append(String(ENDLESS_COSMETIC[w]))
	return out


## The best-times list with `t` added: ascending, at most BOARD_SIZE entries.
static func insert_time(times: Array, t: float) -> Array:
	var out: Array = []
	for v: Variant in times:
		if (v is float or v is int) and float(v) > 0.0 and is_finite(float(v)):
			out.append(float(v))
	out.append(t)
	out.sort()
	return out.slice(0, BOARD_SIZE)


## 1-based place of `t` in `times` (the list before it was added), 0 when it does not make the board.
static func rank_of(times: Array, t: float) -> int:
	var r := 1
	for v: Variant in times:
		if float(v) <= t:
			r += 1
	return r if r <= BOARD_SIZE else 0


static func clock_text(t: float) -> String:
	var s := int(maxf(t, 0.0))
	return "%d:%02d" % [s / 60, s % 60]


## Boss ids that exist in EnemyTypes (a typo here must not hang a run).
static func validate() -> bool:
	for b: StringName in RUSH_ORDER:
		if not EnemyTypes.TYPES.has(b) or not bool(EnemyTypes.TYPES[b].get("boss", false)):
			return false
	for b: StringName in BRUTAL_BOSSES:
		if not EnemyTypes.TYPES.has(b):
			return false
	for row: Array in WAVE_TYPES:
		if not EnemyTypes.TYPES.has(StringName(row[1])):
			return false
	for d: StringName in DIFFS:
		if not DIFF_DEFS.has(d) or not RUSH_PAY.has(d) or not HeroLook.valid_key(String(RUSH_COSMETIC[d])):
			return false
	for k: Variant in ENDLESS_COSMETIC:
		if not HeroLook.valid_key(String(ENDLESS_COSMETIC[k])):
			return false
	return true
