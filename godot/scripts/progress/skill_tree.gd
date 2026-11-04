class_name SkillTree
extends RefCounted
## Skill tree per quantum verb (QUANTUM TELEPORT, SUPERPOSITION, ENTANGLE, COLLAPSE), 5 nodes each. Static state like Upgrades / Gear: Quantum, Drone and the HUD read it directly.
## XP comes from kills and from mission / contract payouts (Progress), one skill point per level (LEVEL_CAP), spent on node ranks. Prerequisites: node 2 needs node 0, node 3 needs node 1,
## node 4 (the capstone, COHERENCE COST) needs nodes 2 and 3. Respec (Progress.respec_skills, the shop) refunds every rank for credits.
## Scaling: XP_MULT and POWER are tables keyed like HeroPower.ROWS (STORY, NORMAL, HARD, QUANTUM): POWER multiplies every node value, XP_MULT every XP gain.
## Save: [skills] xp + one `r_<node id>` key per ranked node (older saves have none: level 1, no ranks).

const VERBS: Array[StringName] = [&"teleport", &"superposition", &"entangle", &"collapse"]
const VERB_NAMES := {&"teleport": "QUANTUM TELEPORT", &"superposition": "SUPERPOSITION", &"entangle": "ENTANGLE", &"collapse": "COLLAPSE"}
const LEVEL_CAP := 40
const XP_PER_SCORE := 0.25                  ## a kill pays this much XP per point of its score (min 8, max 250)
const CREDITS_PER_XP := 4.0                 ## mission payouts: one XP per this many credits
const RESPEC_PER_POINT := 60
const XP_MULT: Array[float] = [1.5, 1.0, 1.0, 1.1]
const POWER: Array[float] = [1.5, 1.0, 0.9, 0.9]

## id: [verb, name, max rank, per rank, unit text, prerequisite ids]
const NODES := {
	&"tp_range": [&"teleport", "RANGE", 3, 0.12, "%d%% range", []],
	&"tp_hops": [&"teleport", "HOPS", 2, 1.0, "+%d chained hop", []],
	&"tp_strike": [&"teleport", "BLINK STRIKE", 3, 40.0, "%d damage on arrival", [&"tp_range"]],
	&"tp_after": [&"teleport", "AFTERIMAGE", 3, 30.0, "%d damage where you left", [&"tp_hops"]],
	&"tp_cost": [&"teleport", "COHERENCE COST", 3, 0.08, "-%d%% coherence cost", [&"tp_strike", &"tp_after"]],
	&"sp_count": [&"superposition", "DECOY COUNT", 2, 1.0, "+%d extra decoy", []],
	&"sp_life": [&"superposition", "DURATION", 3, 1.5, "+%.1f s decoy time", []],
	&"sp_boom": [&"superposition", "EXPLODE ON DEATH", 3, 60.0, "%d damage when you fall", [&"sp_count"]],
	&"sp_speed": [&"superposition", "SPEED", 3, 0.08, "+%d%% speed while split", [&"sp_life"]],
	&"sp_cost": [&"superposition", "COHERENCE COST", 3, 0.08, "-%d%% coherence cost", [&"sp_boom", &"sp_speed"]],
	&"en_links": [&"entangle", "MULTI LINK", 2, 1.0, "+%d link at once", []],
	&"en_swap": [&"entangle", "SWAP COOLDOWN", 3, 0.15, "-%d%% swap cooldown", []],
	&"en_share": [&"entangle", "DAMAGE SHARE", 3, 0.2, "+%d%% shared damage", [&"en_links"]],
	&"en_life": [&"entangle", "LINK TIME", 3, 2.0, "+%.1f s link time", [&"en_swap"]],
	&"en_cost": [&"entangle", "COHERENCE COST", 3, 0.08, "-%d%% coherence cost", [&"en_share", &"en_life"]],
	&"co_radius": [&"collapse", "RADIUS", 3, 0.15, "+%d%% radius", []],
	&"co_pull": [&"collapse", "PULL", 3, 3.0, "pull %.0f m inward", []],
	&"co_chain": [&"collapse", "CHAIN", 3, 30.0, "%d damage blast per kill", [&"co_radius"]],
	&"co_dmg": [&"collapse", "DAMAGE", 3, 0.2, "+%d%% damage", [&"co_pull"]],
	&"co_cost": [&"collapse", "COHERENCE COST", 3, 0.08, "-%d%% coherence cost", [&"co_chain", &"co_dmg"]],
}

static var xp := 0
static var ranks := {}                         ## node id -> rank 1..max


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for v: StringName in VERBS:
		out.append_array(verb_nodes(v))
	return out


static func verb_nodes(verb: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in NODES:
		if NODES[id][0] == verb:
			out.append(id)
	return out


static func reset() -> void:
	xp = 0
	ranks = {}


static func respec() -> void:
	ranks = {}


static func scale_row() -> int:
	return Difficulty.clamp_mode(Difficulty.current)


static func power() -> float:
	return POWER[scale_row()]


static func title(id: StringName) -> String:
	return String(NODES[id][1])


static func max_rank(id: StringName) -> int:
	return int(NODES[id][2])


static func rank(id: StringName) -> int:
	return clampi(int(ranks.get(id, 0)), 0, max_rank(id)) if NODES.has(id) else 0


static func prereqs(id: StringName) -> Array:
	return NODES[id][5]


static func verb_of(id: StringName) -> StringName:
	return NODES[id][0]


static func spent() -> int:
	var n := 0
	for id: StringName in NODES:
		n += rank(id)
	return n


static func spent_in(verb: StringName) -> int:
	var n := 0
	for id: StringName in verb_nodes(verb):
		n += rank(id)
	return n


# --- levels and points -------------------------------------------------------------------------------------------------

static func xp_for(level: int) -> int:                    ## XP needed to go from `level` to the next
	return 100 + 40 * (level - 1)


static func level() -> int:
	var l := 1
	var left := xp
	while l < LEVEL_CAP and left >= xp_for(l):
		left -= xp_for(l)
		l += 1
	return l


## XP into the current level and what the level needs: [have, need] (need 0 at the cap).
static func level_progress() -> Array:
	var l := 1
	var left := xp
	while l < LEVEL_CAP and left >= xp_for(l):
		left -= xp_for(l)
		l += 1
	return [left, xp_for(l) if l < LEVEL_CAP else 0]


static func points_total() -> int:
	return level() - 1


static func points() -> int:
	return maxi(0, points_total() - spent())


static func kill_xp(score: int) -> int:
	return clampi(int(float(score) * XP_PER_SCORE), 8, 250)


## Adds XP (scaled by the difficulty row). Returns the levels gained.
static func add_xp(n: int) -> int:
	if n <= 0:
		return 0
	var before := level()
	xp += maxi(1, int(round(float(n) * XP_MULT[scale_row()])))
	xp = mini(xp, total_xp_cap())
	var gained := level() - before
	if gained > 0:
		Game.say("LEVEL %d · SKILL POINT READY" % level(), 1.6)
	return gained


static func total_xp_cap() -> int:
	var t := 0
	for l in range(1, LEVEL_CAP):
		t += xp_for(l)
	return t


static func unlocked(id: StringName) -> bool:
	for r: StringName in prereqs(id):
		if rank(r) < 1:
			return false
	return true


static func can_buy(id: StringName) -> bool:
	return NODES.has(id) and rank(id) < max_rank(id) and unlocked(id) and points() > 0


static func buy(id: StringName) -> bool:
	if not can_buy(id):
		return false
	ranks[id] = rank(id) + 1
	return true


static func respec_price() -> int:
	return RESPEC_PER_POINT * spent()


static func max_all() -> void:
	xp = total_xp_cap()
	for id: StringName in NODES:
		ranks[id] = max_rank(id)


## "NEXT: +12% range" style line for a node at its current rank (the tree screen).
static func effect_text(id: StringName) -> String:
	var per := float(NODES[id][3]) * power()
	var unit := String(NODES[id][4])
	var v: Variant = per * 100.0 if unit.contains("%%") else per
	if unit.contains("%d"):
		return unit % int(round(float(v)))
	return unit % float(v)


# --- effects (neutral at rank 0) ---------------------------------------------------------------------------------------

static func _v(id: StringName) -> float:
	return float(NODES[id][3]) * rank(id) * power()


static func range_mult() -> float: return 1.0 + _v(&"tp_range")
static func hops_extra() -> int: return rank(&"tp_hops")
static func strike_damage() -> float: return _v(&"tp_strike")
static func afterimage_damage() -> float: return _v(&"tp_after")
static func extra_decoys() -> int: return rank(&"sp_count")
static func decoy_life() -> float: return _v(&"sp_life")
static func death_blast() -> float: return _v(&"sp_boom")
static func split_speed() -> float: return 1.0 + _v(&"sp_speed")
static func extra_links() -> int: return rank(&"en_links")
static func swap_cd_mult() -> float: return maxf(0.3, 1.0 - _v(&"en_swap"))
static func share_mult() -> float: return 1.0 + _v(&"en_share")
static func link_life() -> float: return _v(&"en_life")
static func wave_radius_mult() -> float: return 1.0 + _v(&"co_radius")
static func wave_pull() -> float: return float(NODES[&"co_pull"][3]) * rank(&"co_pull") * power()
static func wave_chain() -> float: return _v(&"co_chain")
static func wave_damage_mult() -> float: return 1.0 + _v(&"co_dmg")


static func cost_mult(verb: StringName) -> float:
	var id: StringName = &"tp_cost"
	match verb:
		&"superposition": id = &"sp_cost"
		&"entangle": id = &"en_cost"
		&"collapse": id = &"co_cost"
	return maxf(0.4, 1.0 - _v(id))


# --- save --------------------------------------------------------------------------------------------------------------

static func _int(v: Variant) -> int:
	return int(v) if v is int or v is float else 0


static func to_save() -> Dictionary:
	var d := {"xp": xp}
	for id: StringName in NODES:
		if rank(id) > 0:
			d["r_%s" % id] = rank(id)
	return d


static func from_save(d: Dictionary) -> void:
	reset()
	xp = clampi(_int(d.get("xp", 0)), 0, total_xp_cap())
	for id: StringName in NODES:
		var r := clampi(_int(d.get("r_%s" % id, 0)), 0, max_rank(id))
		if r > 0:
			ranks[id] = r
	# a hand-edited or older tree must never exceed the points or skip prerequisites: drop ranks that break the rules
	var changed := true
	while changed:
		changed = false
		for id: StringName in NODES:
			if rank(id) > 0 and not unlocked(id):
				ranks.erase(id)
				changed = true
	while spent() > points_total():
		var order := ids()
		order.reverse()
		for id: StringName in order:
			if rank(id) > 0:
				ranks[id] = rank(id) - 1
				if rank(id) == 0:
					ranks.erase(id)
				break
