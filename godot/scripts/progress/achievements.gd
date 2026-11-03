class_name Achievements
extends Node
## I3: 25 achievements (Game.progress.achievements). Each has a stat, a goal and a reward (credits, some also a cosmetic id). Stats come from the player's kills, the
## Progress counters (contracts, bosses, chapters, upgrades, weapons, credits earned) and the shard collection; evaluate() is cheap and runs on Progress.changed, on a kill,
## on a shard and twice a second for heat. Unlocking pays once, shows "ACHIEVEMENT  <TITLE>" and is saved (progress.gd: [achievements] section; old saves simply have none).
## Cosmetic ids are only recorded (`cosmetics`), a later wave applies them to the hero.

signal unlocked(id: StringName)

## id, title, description, stat, goal, credits, cosmetic ("" = none)
const DEFS: Array[Array] = [
	[&"first_kill", "FIRST CONTACT", "Down 1 Vael", &"kills", 1, 25, ""],
	[&"kills_25", "HUNTER", "Down 25 Vael", &"kills", 25, 60, ""],
	[&"kills_100", "EXTERMINATOR", "Down 100 Vael", &"kills", 100, 150, "decal_neon"],
	[&"kills_300", "VAEL BANE", "Down 300 Vael", &"kills", 300, 400, ""],
	[&"crits_25", "STEADY AIM", "25 critical hits", &"crits", 25, 80, ""],
	[&"shard_1", "FIRST SHARD", "Collect 1 shard", &"shards", 1, 20, ""],
	[&"shard_10", "SHARD RUNNER", "Collect 10 shards", &"shards", 10, 100, ""],
	[&"shard_20", "SHARD HOARD", "Collect 20 shards", &"shards", 20, 200, "trail_violet"],
	[&"shard_30", "FULL SPECTRUM", "Collect all 30 shards", &"shards", 30, 500, "aura_phase"],
	[&"roof_5", "HIGH GROUND", "5 rooftop shards", &"roof_shards", 5, 120, ""],
	[&"roof_10", "SKYLINE", "All 10 rooftop shards", &"roof_shards", 10, 300, "visor_gold"],
	[&"district_1", "LOCAL", "Clear one district's shards", &"districts", 1, 120, ""],
	[&"district_4", "CITYWIDE", "Clear all four districts", &"districts", 4, 400, ""],
	[&"contract_1", "FIRST CONTRACT", "Finish 1 contract", &"contracts", 1, 50, ""],
	[&"contract_10", "FIXER", "Finish 10 contracts", &"contracts", 10, 250, "outline_gold"],
	[&"boss_1", "OVERSEER DOWN", "Defeat 1 boss", &"bosses", 1, 150, ""],
	[&"boss_3", "OVERSEER HUNTER", "Defeat 3 bosses", &"bosses", 3, 400, ""],
	[&"chapter_2", "ON THE MAP", "Reach chapter 3", &"chapters", 2, 80, ""],
	[&"chapter_4", "DEEP COVER", "Reach chapter 5", &"chapters", 4, 200, ""],
	[&"earn_1000", "PAID", "Earn 1000 credits", &"earned", 1000, 0, "decal_neon2"],
	[&"earn_10000", "WELL FUNDED", "Earn 10000 credits", &"earned", 10000, 300, ""],
	[&"upgrade_1", "FIRST UPGRADE", "Buy 1 upgrade level", &"upgrades", 1, 30, ""],
	[&"upgrade_10", "TUNED", "Own 10 upgrade levels", &"upgrades", 10, 200, ""],
	[&"arsenal_3", "ARSENAL", "Own 3 weapons", &"weapons", 3, 150, ""],
	[&"wanted_5", "MOST WANTED", "Reach heat level 5", &"heat", 5, 100, ""],
]

var enabled := true                       ## Progress turns it off under Game.autostart (tools / tests / bots) so credit rewards never disturb other tests
var done: Dictionary = {}                 ## id -> true
var cosmetics: Array[StringName] = []
var stats: Dictionary = {"kills": 0, "crits": 0, "earned": 0, "heat": 0}   ## the counters that are not derived (saved)

var _prog: Progress
var _last_credits := 0
var _bound: Object
var _t := 0.0


static func count() -> int:
	return DEFS.size()


static func index_of(id: StringName) -> int:
	for i in DEFS.size():
		if DEFS[i][0] == id:
			return i
	return -1


static func title(i: int) -> String:
	return String(DEFS[i][1])


static func reward_text(i: int) -> String:
	var d := DEFS[i]
	var parts: Array[String] = []
	if int(d[5]) > 0:
		parts.append("%d CR" % int(d[5]))
	if String(d[6]) != "":
		parts.append(String(d[6]).replace("_", " ").to_upper())
	return "  +  ".join(parts)


func _ready() -> void:
	name = "Achievements"
	_prog = get_parent() as Progress
	if _prog != null:
		_last_credits = _prog.credits
		_prog.changed.connect(_on_changed)


func unlocked_count() -> int:
	return done.size()


func is_done(id: StringName) -> bool:
	return done.has(id)


## Current value of the stat of definition i (derived stats read the live state).
func value(i: int) -> int:
	var st: StringName = DEFS[i][3]
	var col: Collectibles = _prog.collectibles if _prog != null else null
	match st:
		&"shards":
			return col.count() if col != null else 0
		&"roof_shards":
			return col.roof_count() if col != null else 0
		&"districts":
			return col.districts_done() if col != null else 0
		&"contracts":
			return _prog.contracts_done if _prog != null else 0
		&"bosses":
			return _prog.bosses_cleared.size() if _prog != null else 0
		&"chapters":
			return maxi(_prog.unlocked - 1, 0) if _prog != null else 0
		&"upgrades":
			var n := 0
			if _prog != null:
				for u: StringName in Upgrades.IDS:
					n += _prog.level(u)
			return n
		&"weapons":
			return WeaponDefs.unlocked.size()
	return int(stats.get(String(st), 0))


func progress_text(i: int) -> String:
	return "%d / %d" % [mini(value(i), int(DEFS[i][4])), int(DEFS[i][4])]


func add_stat(key: String, n := 1) -> void:
	stats[key] = int(stats.get(key, 0)) + n
	evaluate()


## Unlocks everything whose goal is met. Returns how many were unlocked now.
func evaluate() -> int:
	var n := 0
	if not enabled:
		return 0
	for i in DEFS.size():
		var id: StringName = DEFS[i][0]
		if not done.has(id) and value(i) >= int(DEFS[i][4]):
			_unlock(i)
			n += 1
	return n


func _unlock(i: int) -> void:
	var id: StringName = DEFS[i][0]
	done[id] = true                                    # first: the reward's credit change re-enters evaluate()
	var cos := StringName(String(DEFS[i][6]))
	if cos != &"" and not cosmetics.has(cos):
		cosmetics.append(cos)
	if _prog != null and int(DEFS[i][5]) > 0:
		_prog.add_credits(int(DEFS[i][5]))
	Game.say("ACHIEVEMENT  " + title(i), 3.0)
	unlocked.emit(id)


func reset() -> void:
	done.clear()
	cosmetics.clear()
	stats = {"kills": 0, "crits": 0, "earned": 0, "heat": 0}
	_last_credits = _prog.credits if _prog != null else 0


func _on_changed() -> void:
	if _prog == null:
		return
	if _prog.credits > _last_credits:
		stats["earned"] = int(stats.get("earned", 0)) + _prog.credits - _last_credits
	_last_credits = _prog.credits
	evaluate()


func _on_hit(kill: bool, crit: bool) -> void:
	if kill:
		stats["kills"] = int(stats.get("kills", 0)) + 1
	if crit:
		stats["crits"] = int(stats.get("crits", 0)) + 1
	if kill or crit:
		evaluate()


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	var p := Game.player if is_instance_valid(Game.player) else null
	if p != null and p != _bound and p.has_signal(&"hit_confirmed"):
		_bound = p
		p.connect(&"hit_confirmed", _on_hit)
	if Game.is_playing() and int(floorf(Game.heat)) > int(stats.get("heat", 0)):
		stats["heat"] = int(floorf(Game.heat))
		evaluate()


func to_save() -> Dictionary:
	var ids := PackedStringArray()
	for id: StringName in done:
		ids.append(String(id))
	var cos := PackedStringArray()
	for c in cosmetics:
		cos.append(String(c))
	return {"done": ids, "cosmetics": cos, "stats": stats.duplicate()}


func from_save(d: Dictionary) -> void:
	reset()
	for s: Variant in Array(d.get("done", [])):
		var id := StringName(str(s))
		if index_of(id) >= 0:
			done[id] = true
	for s: Variant in Array(d.get("cosmetics", [])):
		cosmetics.append(StringName(str(s)))
	var st: Variant = d.get("stats", {})
	if st is Dictionary:
		for k: Variant in (st as Dictionary):
			if (st as Dictionary)[k] is int:
				stats[str(k)] = maxi(0, int((st as Dictionary)[k]))
