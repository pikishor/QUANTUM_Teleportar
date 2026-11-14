class_name WeaponShopsV3
extends RefCounted
## Where the roster of wave 113 turns up in the world besides the ladder (WeaponLadder: missions, crates, boss drops) and the HERO hub catalogue: the HERO TIER, the ARMS DEALER's back room (a weapon the
## hero already owns is sold out and makes room for one of his tier) and the random weapon an enemy may carry. Pure rules on WeaponDefs and WeaponDefsV3, no scene tree.

const TIER_STEP := 12                          ## owned weapons per tier: the seven starters are tier 1, every twelve more open the next tier
const DROP_BAND := 0.07                        ## share of the roll `r1` of WeaponLadder.enemy_drop (just above the NEXT-weapon band) that is a random weapon of the pack


## 1 .. 6: how far the hero has come in the roster (more owned weapons, higher tier). With HERO MODE on everything is owned, so it is 6.
static func hero_tier() -> int:
	var owned := 0
	for id: StringName in WeaponDefs.IDS:
		if WeaponDefs.is_unlocked(id):
			owned += 1
	return clampi(1 + (owned - WeaponDefs.STARTERS.size()) / TIER_STEP, 1, 6)


## The weapons of the pack the hero does not own, of his tier or below, cheapest tier first and in roster order inside a tier (what a shop or a drop may offer).
static func candidates(type: StringName = &"") -> Array[StringName]:
	var out: Array[StringName] = []
	var tier := hero_tier()
	for id: StringName in WeaponDefsV3.ids():
		if WeaponDefs.is_unlocked(id) or WeaponDefsV3.tier_of(id) > tier:
			continue
		if type != &"" and not (WeaponDefsV3.drop_candidates(type, tier, func(w: StringName) -> bool: return WeaponDefs.is_unlocked(w)).has(id)):
			continue
		out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return WeaponDefsV3.tier_of(a) < WeaponDefsV3.tier_of(b))
	return out


## The back room of the ARMS DEALER (from tier 2): the stock rows of `base` where every weapon the hero owns is replaced by a weapon of his tier he does not own (a pick that rotates with what he owns, so a purchase
## changes the offer); rows that are not weapons stay. Never offers the same weapon twice.
static func dealer_stock(base: Array) -> Array:
	if hero_tier() < 2:
		return base                                   # a new hero finds the stock he knows (a weapon he buys is marked OWNED); the back room opens from tier 2
	var picks := candidates()
	var rot := 0
	for id: StringName in WeaponDefs.IDS:
		if WeaponDefs.is_unlocked(id):
			rot += 1
	var used := {}
	var out: Array = []
	for row in base:
		var r: Dictionary = row
		if str(r.get("kind", "")) == "weapon" and WeaponDefs.is_unlocked(StringName(r["id"])) and not picks.is_empty():
			var tries := 0
			var at := rot % picks.size()
			while used.has(picks[at]) and tries < picks.size():
				at = (at + 1) % picks.size()
				tries += 1
			if not used.has(picks[at]):
				var pid: StringName = picks[at]
				used[pid] = true
				out.append({"id": pid, "kind": "weapon", "name": WeaponDefs.title(pid)})
				rot += 3
				continue
		out.append(r)
	return out


## The weapon a fallen enemy of `type` carries for the roll `r` (0..1 inside the DROP_BAND): one of the pack weapons that type may carry and the hero does not own, of his tier; &"" for none.
static func drop_for(type: StringName, r: float) -> StringName:
	var pool: Array[StringName] = []
	var tier := hero_tier()
	for id: StringName in WeaponDefsV3.drop_candidates(type, tier, func(w: StringName) -> bool: return WeaponDefs.is_unlocked(w)):
		pool.append(id)
	if pool.is_empty():
		return &""
	return pool[mini(int(clampf(r, 0.0, 0.9999) * float(pool.size())), pool.size() - 1)]
