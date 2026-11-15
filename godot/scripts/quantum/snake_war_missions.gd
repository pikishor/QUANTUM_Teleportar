class_name SnakeWarMissions
extends RefCounted
## The two SNAKE COMBAT missions of the Mission Board (wave 115, combat side) and the director around them. Built like the other board missions (a chapter of campaign steps run by CampaignRunner: checkpoint
## at every step, instant retry, objective line, beacon), everything EASY (wide rings, no time limit, no instant failure):
##   SNAKE ARENA          1 REACH the arena ring on a street; 2 DEFEND it for 48 seconds against three waves (the runner sends them), snakes on: the director fills the SNAKE ENERGY while it lasts, calls the hints
##                        and pays a bonus per different snake power used (40 credits each, six at most)
##   ROOFTOP SNAKE HUNT   1 REACH a roof (zip up with SNAKE), 2 TAKE DOWN the sniper on the next roof and his guards (SNAKE PULL drags a sniper off his roof, SNAKE NET holds the guards), 3 the elite gunner on the
##                        roof after that; the same bonus
## `hooked()` is true while one of them runs; `note_power(id)` counts the snake powers used in it. The hints of the first minutes (one line each, once per profile, saved in user://snake_war.cfg) are
## `SnakeWarMissions.tick_hints`: HOLD WEAPON AND PICK THE SNAKE WEDGE, FIRE TO PULL, TRY THE BOMBS.
## Hooks: MissionBoard.generate calls `inject`, MissionBoard.build calls `build` for these types, SnakeWar._physics_process calls `tick`.

const TYPES: Array[StringName] = [&"snake_arena", &"snake_hunt"]
const DEFS := {
	&"snake_arena": {"title": "SNAKE ARENA", "brief": "Hold the ring against three waves. Pull, net and bomb them with your snakes.", "base": 380, "weight": 3, "glyph": &"dest"},
	&"snake_hunt": {"title": "ROOFTOP SNAKE HUNT", "brief": "Snake up to the roofs. Pull the snipers off their perches and take down the gunner.", "base": 440, "weight": 3, "glyph": &"dest"},
}
const INJECT_CHANCE := 0.28
const BONUS_PER_POWER := 40
const BONUS_MAX := 6
const SAVE := "user://snake_war.cfg"
const HINTS := {
	&"wedge": "HOLD WEAPON  PICK THE SNAKE WEDGE",
	&"fire": "FIRE AT AN ENEMY  SNAKE PULL YANKS HIM TO YOU",
	&"bombs": "TRY THE BOMBS WEDGE  A SNAKE BOMB CLEARS A STREET",
	&"arena": "HOLD THE RING  ANY SNAKE POWER WORKS",
	&"hunt": "PULL THE SNIPER OFF HIS ROOF",
}

static var active_mission := ""
static var powers_used: Dictionary = {}
static var bonus_paid := 0
static var seen: Dictionary = {}
static var _loaded := false
static var _camp: CampaignRunner
static var _hooked_camp := false
static var _hint_t := 0.0
static var _play_t := 0.0
static var _tick_t := 0.0


static func hooked() -> bool:
	return active_mission != ""


static func note_power(id: StringName) -> void:
	powers_used[id] = int(powers_used.get(id, 0)) + 1


static func reset_flags() -> void:
	active_mission = ""
	powers_used.clear()
	bonus_paid = 0
	seen.clear()
	_loaded = true
	_hooked_camp = false
	_camp = null
	_hint_t = 0.0
	_play_t = 0.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SAVE) == OK and cf.has_section("hints"):
		for k in cf.get_section_keys("hints"):
			seen[StringName(k)] = bool(cf.get_value("hints", k, false))


static func _save() -> void:
	var cf := ConfigFile.new()
	for k: Variant in seen:
		cf.set_value("hints", str(k), seen[k])
	cf.save(SAVE)


static func _s(kind: String, text: String, extra := {}) -> Dictionary:
	var d := {"kind": kind, "text": text.substr(0, CampaignSteps.MAX_TEXT), "quiet": true}
	d.merge(extra, true)
	return d


# --- the board -------------------------------------------------------------------------------------------------------------------------

## A snake combat mission now and then instead of the last pick (live game only; picks that already hold a snake mission stay).
static func inject(picks: Array[StringName], rng: RandomNumberGenerator, banned: Array = []) -> Array[StringName]:
	for p in picks:
		if DEFS.has(p) or SnakeMissions.DEFS.has(p):
			return picks
	if picks.is_empty() or not (Game.world is City) or (Game.world as City).layout == null:
		return picks
	if rng.randf() >= INJECT_CHANCE:
		return picks
	var chosen: StringName = &"snake_arena" if rng.randf() < 0.5 else &"snake_hunt"
	if banned.has(chosen):
		chosen = &"snake_hunt" if chosen == &"snake_arena" else &"snake_arena"
	var out: Array[StringName] = picks.duplicate()
	out[out.size() - 1] = chosen
	return out


## The record the board turns into an offer: {title, brief, base, glyph, steps, route_m, pos}; {} when the city has no suitable place near `origin`.
static func build(t: StringName, tier: int, origin: Vector3, r: RandomNumberGenerator) -> Dictionary:
	if not DEFS.has(t):
		return {}
	var o := Vector3(origin.x, 0.0, origin.z)
	var out: Array[Dictionary] = []
	match t:
		&"snake_arena":
			out = [
				_s("reach", "GO TO THE ARENA RING", {"radius": 14.0, "snake_war_mission": "arena", "dist": [95.0, 170.0]}),
				_s("defend", "HOLD THE RING  USE YOUR SNAKES", {"radius": 16.0, "hold": 48.0, "count": 2 + clampi(tier, 0, 2), "gap": 11.0, "types": ["operative", "flanker"], "snake_war_mission": "arena"}),
			]
		&"snake_hunt":
			var a := SnakeMissions._pick(SnakeMissions.roofs(o, 55.0, 120.0, 22.0, 80.0), r)
			if a.is_empty():
				return {}
			var used: Array = [a["pos"]]
			var b := SnakeMissions._pick(SnakeMissions.roofs(a["pos"], 70.0, 140.0, 22.0, 90.0, used), r)
			if b.is_empty():
				return {}
			used.append(b["pos"])
			var c := SnakeMissions._pick(SnakeMissions.roofs(b["pos"], 70.0, 150.0, 22.0, 100.0, used), r)
			if c.is_empty():
				return {}
			out = [
				_s("reach", "SNAKE UP TO THE ROOF  TAP SNAKE", {"pos": a["pos"], "radius": SnakeMissions.ROOF_R + 4.0, "snake_war_mission": "hunt"}),
				_s("kill_target", "PULL THE SNIPER OFF HIS ROOF", {"pos": b["pos"], "enemy": "sniper", "guards": 2, "hp_mult": 1.2, "name": "SNIPER", "snake_war_mission": "hunt"}),
				_s("kill_target", "TAKE DOWN THE GUNNER", {"pos": c["pos"], "enemy": "heavy", "guards": 1, "hp_mult": 1.0, "name": "GUNNER", "snake_war_mission": "hunt"}),
			]
	if out.is_empty():
		return {}
	var route := 0.0
	var prev := o
	for st: Dictionary in out:
		var q: Variant = st.get("pos", prev + Vector3(60.0, 0.0, 0.0))
		route += Vector2((q as Vector3).x - prev.x, (q as Vector3).z - prev.z).length()
		prev = q as Vector3
	var def: Dictionary = DEFS[t]
	var first: Vector3 = out[0].get("pos", o + Vector3(120.0, 0.0, 0.0))
	return {"title": def["title"], "brief": def["brief"], "base": def["base"], "glyph": def["glyph"], "steps": out, "route_m": maxf(route, 120.0), "pos": first}


# --- the director -----------------------------------------------------------------------------------------------------------------------

static func _runner() -> CampaignRunner:
	if _camp == null or not is_instance_valid(_camp):
		var m := Game.missions as Missions
		_camp = m.campaign if m != null else null
		_hooked_camp = false
	if _camp != null and not _hooked_camp:
		_hooked_camp = true
		if not _camp.chapter_completed.is_connected(_on_chapter_completed):
			_camp.chapter_completed.connect(_on_chapter_completed)
	return _camp


## Called by SnakeWar every physics frame: which mission runs, the energy boost, the hints.
static func tick(war: SnakeWar, dt: float) -> void:
	_load()
	_tick_t -= dt
	if _tick_t > 0.0:
		_energy_boost(war, dt)
		return
	_tick_t = 0.25
	var camp := _runner()
	var mission := ""
	if camp != null and (camp.state == &"active" or camp.state == &"retry"):
		mission = str(camp.step.get("snake_war_mission", ""))
	if mission != "" and active_mission == "":
		powers_used.clear()
		bonus_paid = 0
	if mission != "":
		active_mission = mission
	elif active_mission != "" and (camp == null or camp.state == &"idle" or camp.state == &"done"):
		active_mission = ""
	_tick_hints(war, 0.25, mission)


static func _energy_boost(war: SnakeWar, dt: float) -> void:
	if active_mission != "" and war.p != null and war.p.snake != null:
		war.p.snake.energy_gain(30.0 * dt)


static func _tick_hints(war: SnakeWar, dt: float, mission: String) -> void:
	if Game.state != &"play" or war.p == null or war.p.is_dead() or war.p.vehicle != null:
		return
	_play_t += dt
	_hint_t = maxf(0.0, _hint_t - dt)
	if _hint_t > 0.0:
		return
	if mission == "arena" and not bool(seen.get(&"arena", false)):
		_hint(&"arena")
		return
	if mission == "hunt" and not bool(seen.get(&"hunt", false)):
		_hint(&"hunt")
		return
	if mission != "":
		return
	if _play_t > 30.0 and war.casts == 0 and war.armed == &"" and not bool(seen.get(&"wedge", false)):
		_hint(&"wedge")
	elif war.armed != &"" and war.casts == 0 and not bool(seen.get(&"fire", false)):
		_hint(&"fire")
	elif war.casts >= 3 and not bool(seen.get(&"bombs", false)) and war.bombs.thrown == 0:
		_hint(&"bombs")


static func _hint(id: StringName) -> void:
	seen[id] = true
	_hint_t = 18.0
	Game.say(String(HINTS[id]), 3.0)
	_save()


static func _on_chapter_completed(_chapter: int) -> void:
	if active_mission == "":
		return
	var n := mini(powers_used.size(), BONUS_MAX)
	if n > 0:
		bonus_paid = n * BONUS_PER_POWER
		var prog := Game.progress as Progress
		if prog != null:
			prog.add_credits(bonus_paid)
		Game.say("SNAKE BONUS  %d POWERS  +%d" % [n, bonus_paid], 2.4)
	active_mission = ""
