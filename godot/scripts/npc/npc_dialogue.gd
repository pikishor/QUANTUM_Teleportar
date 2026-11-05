extends RefCounted
## NPC DIALOGUE v2: contextual barks, 2-3 line exchanges, hint rumours and vendor lines. Pure rules, no nodes: NpcLife (citizens) and VendorScreen (vendors) call `context()` and
## the pickers. The words live in npc_dialogue_data.gd (every line [en, es, hi], keyed through Tr by the spoken string).
## Context: district (quadrant under the hero), time of day, weather state, heat, story chapter and two memories of the hero's actions: a recent kill and a recent vehicle theft
## (`note_kill()`, `note_theft()`; NpcLife feeds them from the kill counter and the COMMANDEERED message; both fade after KILL_WINDOW / THEFT_WINDOW seconds of `tick`).

const Data := preload("res://scripts/npc/npc_dialogue_data.gd")

const KILL_WINDOW := 60.0
const THEFT_WINDOW := 90.0
const ACTION_BIAS := 0.6                ## chance a recent hero action decides the line
const HINT_BIAS := 0.5

static var clock := 0.0                 ## seconds of play (advanced by NpcLife.step)
static var kill_at := -1.0e9
static var theft_at := -1.0e9
static var kills_seen := -1             ## last kill counter value (NpcLife.poll_kills)


static func reset_memory() -> void:
	clock = 0.0
	kill_at = -1.0e9
	theft_at = -1.0e9
	kills_seen = -1


static func tick(delta: float) -> void:
	clock += delta


static func note_kill() -> void:
	kill_at = clock


static func note_theft() -> void:
	theft_at = clock


static func recent_kill() -> bool:
	return clock - kill_at < KILL_WINDOW


static func recent_theft() -> bool:
	return clock - theft_at < THEFT_WINDOW


## Feed the hero's kill counter (Achievements.stats["kills"]): the first read only sets the baseline.
static func poll_kills() -> void:
	var prog := Game.progress as Progress
	if prog == null or prog.achievements == null:
		return
	var n := int(prog.achievements.stats.get("kills", 0))
	if kills_seen >= 0 and n > kills_seen:
		note_kill()
	kills_seen = n


static func district_of(pos: Vector3) -> String:
	return Data.DISTRICTS[(1 if pos.x >= 0.0 else 0) + (2 if pos.z >= 0.0 else 0)]


## The facts a line depends on at `pos`.
static func context(pos: Vector3) -> Dictionary:
	var hour := 12.0
	if is_instance_valid(Game.world) and Game.world.get("day_night") is DayNight:
		hour = (Game.world.get("day_night") as DayNight).hour
	var chapter := 0
	if is_instance_valid(Game.story):
		chapter = int(Game.story.get("chapter"))
	return {
		"district": district_of(pos), "hour": hour, "night": DayNight.night_amount(hour) > 0.5, "weather": Weather.current,
		"heat": Game.heat, "chapter": chapter, "kills": recent_kill(), "theft": recent_theft(),
	}


static func chapter_tag(ch: int) -> String:
	return "early" if ch < 3 else ("mid" if ch < 8 else "late")


## Tags that apply to `ctx`, most specific first (hero actions, weather, heat, time, district, chapter, calm).
static func tags(ctx: Dictionary) -> Array[String]:
	var t: Array[String] = []
	if ctx.get("theft", false):
		t.append("theft")
	if ctx.get("kills", false):
		t.append("kills")
	match str(ctx.get("weather", &"clear")):
		"storm": t.append("storm")
		"rain", "drizzle": t.append("rain")
		"fog": t.append("fog")
	var heat := float(ctx.get("heat", 0.0))
	if heat >= 1.0:
		t.append("heat")
	t.append("night" if ctx.get("night", false) else "day")
	t.append("d_" + str(ctx.get("district", "market")))
	t.append(chapter_tag(int(ctx.get("chapter", 0))))
	if heat < 1.0:
		t.append("calm")
	return t


static func _spoken(prefix: String, entry: Array) -> String:
	return prefix + str(entry[0])


## One bark for `ctx`: a recent hero action decides it ACTION_BIAS of the time, otherwise any applicable line.
static func bark(ctx: Dictionary, rng: RandomNumberGenerator) -> String:
	var tg := tags(ctx)
	var pool: Array[String] = []
	var action: Array[String] = []
	for k in tg:
		if not Data.BARKS.has(k):
			continue
		for e: Array in Data.BARKS[k]:
			var s := _spoken(Data.CITIZEN, e)
			pool.append(s)
			if k == "theft" or k == "kills":
				action.append(s)
	if not action.is_empty() and rng.randf() < ACTION_BIAS:
		return action[rng.randi() % action.size()]
	return pool[rng.randi() % pool.size()]


## A 2-3 line exchange (speaker alternates), chosen among the tags that have one; hero actions first.
static func exchange(ctx: Dictionary, rng: RandomNumberGenerator) -> Array[String]:
	var opts: Array = []
	var first_action := -1
	for k in tags(ctx):
		if Data.EXCHANGES.has(k):
			if first_action < 0 and (k == "theft" or k == "kills"):
				first_action = opts.size()
			for ex: Array in Data.EXCHANGES[k]:
				opts.append(ex)
	var out: Array[String] = []
	if opts.is_empty():
		return out
	var pick: Array = opts[first_action] if first_action >= 0 and rng.randf() < ACTION_BIAS else opts[rng.randi() % opts.size()]
	for j in pick.size():
		out.append(_spoken(Data.CITIZEN if j % 2 == 0 else Data.REPLY, pick[j]))
	return out


## Hint keys that make sense now: districts with shards left, and side jobs not yet done (the district of a job is a pure hash of its id, a hint not a marker).
static func hint_keys() -> Array[String]:
	var keys: Array[String] = []
	var prog := Game.progress as Progress
	if prog == null:
		return keys
	if prog.collectibles != null:
		var left := [0, 0, 0, 0]
		for i in Collectibles.COUNT:
			if not prog.collectibles.is_collected(i):
				left[Collectibles.district_of_spot(i)] += 1
		for d in 4:
			if left[d] > 0:
				keys.append("shards_" + Data.DISTRICTS[d])
	var chapter := int(Game.story.get("chapter")) if is_instance_valid(Game.story) else 0
	for mid: StringName in SideMissions.DEFS:
		if SideMissions.unlocked(mid, chapter) and int(prog.side_done.get(mid, 0)) == 0:
			var k := "side_" + Data.DISTRICTS[absi(str(mid).hash()) % 4]
			if not keys.has(k):
				keys.append(k)
	return keys


## A rumour that hints at a collectible or a side job ("" when nothing is left to hint at). `prefix` is the speaker (CITIZEN or VENDOR).
static func hint(rng: RandomNumberGenerator, prefix: String = Data.CITIZEN) -> String:
	var keys := hint_keys()
	if keys.is_empty():
		return ""
	var k: String = keys[rng.randi() % keys.size()]
	var arr: Array = Data.HINTS[k]
	return _spoken(prefix, arr[rng.randi() % arr.size()])


## The vendor's line when the window opens: the hero's actions, heat, night or rain, otherwise the shop's own greeting; sometimes a hint.
static func vendor_line(type: StringName, ctx: Dictionary, rng: RandomNumberGenerator) -> String:
	var order: Array[String] = []
	if ctx.get("theft", false):
		order.append("theft")
	if ctx.get("kills", false):
		order.append("kills")
	if float(ctx.get("heat", 0.0)) >= 1.0:
		order.append("heat")
	if ctx.get("night", false):
		order.append("night")
	if str(ctx.get("weather", &"")) in ["rain", "drizzle", "storm"]:
		order.append("rain")
	if rng.randf() < HINT_BIAS * 0.5:
		var h := hint(rng, Data.VENDOR)
		if h != "":
			return h
	if not order.is_empty() and (rng.randf() < ACTION_BIAS or not Data.VENDOR_LINES.has("greet_" + str(type))):
		var k: String = order[rng.randi() % order.size()]
		return _spoken(Data.VENDOR, Data.VENDOR_LINES[k][0])
	var g := "greet_" + str(type)
	if Data.VENDOR_LINES.has(g):
		return _spoken(Data.VENDOR, Data.VENDOR_LINES[g][0])
	return _spoken(Data.VENDOR, Data.VENDOR_LINES["greet_bodega"][0])


## Stock rotation: which of the type's three specials is on the shelf. It changes every time the hero walks through a door.
static func rotation_index(type: StringName) -> int:
	var ig := InteriorGameplay.instance
	var n := ig.enter_count if ig != null else 0
	return (n + absi(str(type).hash())) % 3
