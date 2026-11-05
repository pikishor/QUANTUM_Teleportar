class_name ArenaRunner
extends Node
## BOSS RUSH and the ENDLESS ARENA (Game.missions.arena, wave 72): data and rules in arena_scripts.gd.
## RUSH: a break (countdown, heal) then a boss (EnemyManager.spawn on a road 34-56 m away, health x the difficulty), repeated for every boss of ArenaScripts.RUSH_ORDER. The clock runs from the
## start to the last boss down; the time goes on the local leaderboard (Progress.arena rush_<diff>, five best). A fall ends the run (nothing paid).
## ENDLESS: wave n spawns wave_count(n) troops (types by wave, health x ARMOURED) around the hero a few at a time; the wave is clear when all are down, a break follows. BRUTAL adds a boss every
## 4th wave. The run ends when the hero falls or LEAVES; the waves cleared are paid and may unlock cosmetics.
## While a run lasts the campaign and the contract board are frozen (their physics process is switched off and restored) so a story step cannot fight the arena.
## Live wiring: the pause menu ARENA button and the title ARENA button open the planning screen (scripts/ui/arena_board.gd, Hud `_arena_open`); the DEMO menu has an ARENA tab. HUD line via hud_line(),
## boss bar via boss(). Simulates only while Game.is_playing(); tick() is callable by tests.
## API: can_start() · start(mode, diff, mods) · abort(reason) · tick(dt) · hud_line() · boss() · state (&"idle" &"running") · phase (&"break" &"fight") · result (last run)

signal started(mode: StringName, diff: StringName)
signal boss_started(id: StringName, index: int)
signal wave_started(n: int)
signal finished(mode: StringName, ok: bool, reason: String)

var mode: StringName = &"rush"          ## rush | endless
var diff: StringName = &"normal"
var mods: Array[StringName] = []
var state: StringName = &"idle"
var phase: StringName = &"break"
var index := 0                          ## rush: bosses down; endless: waves cleared
var elapsed := 0.0
var break_t := 0.0
var kills := 0
var score := 0
var result: Dictionary = {}             ## {mode, diff, ok, reason, time, waves, kills, score, reward, cosmetics, rank}

var _foes: Array[Drone] = []
var _wave_boss_pending := false
var _pending := 0                       ## endless: foes of the wave still to spawn
var _boss: Drone
var _frozen: Array[Node] = []
var _rng := RandomNumberGenerator.new()
var _t := 0.0


func _ready() -> void:
	add_to_group(&"arena")
	_rng.randomize()
	Game.new_game.connect(abort.bind("RESET"))
	Game.player_died.connect(_on_player_died)
	Game.state_changed.connect(_on_state)


func _physics_process(delta: float) -> void:
	if state == &"running" and Game.is_playing():
		tick(delta)


func is_running() -> bool:
	return state == &"running"


func _chapter() -> int:
	return int(Game.story.get("chapter")) if is_instance_valid(Game.story) else 0


## True when a run could start now: nothing of ours or another job runs, the hero is on the street.
func can_start() -> bool:
	if is_running() or not is_instance_valid(Game.player) or not is_instance_valid(Game.enemies):
		return false
	var m := Game.missions as Missions
	if m == null:
		return false
	if m.sides != null and m.sides.active:
		return false
	if m.chases != null and m.chases.is_running():
		return false
	if m.stealth != null and m.stealth.is_running():
		return false
	if m.heists != null and m.heists.is_running():
		return false
	if m.contracts != null and bool(m.contracts.is_active()):
		return false
	var ig := InteriorGameplay.instance
	return not InteriorGameplay.active and not (ig != null and is_instance_valid(ig) and ig.busy)


func start(m: StringName = &"rush", d: StringName = &"normal", with_mods: Array = []) -> bool:
	if not can_start() or not (m == &"rush" or m == &"endless") or not ArenaScripts.DIFF_DEFS.has(d):
		return false
	mode = m
	diff = d if m == &"rush" else &"normal"
	mods.clear()
	if m == &"endless":
		for id: Variant in with_mods:
			if ArenaScripts.MOD_DEFS.has(StringName(id)) and not mods.has(StringName(id)):
				mods.append(StringName(id))
	index = 0
	elapsed = 0.0
	kills = 0
	score = 0
	_pending = 0
	_boss = null
	_foes.clear()
	result = {}
	phase = &"break"
	break_t = ArenaScripts.START_BREAK
	_freeze()
	state = &"running"
	Game.heat = 0.0
	var prog := Game.progress as Progress
	if prog != null:
		prog.arena["runs"] = int(prog.arena.get("runs", 0)) + 1
		prog.changed.emit()
	Game.say("BOSS RUSH  %s" % ArenaScripts.diff_title(diff) if m == &"rush" else "ARENA", 3.0)
	Sfx.play(&"mission_start")
	started.emit(mode, diff)
	return true


func abort(reason := "LEFT") -> void:
	if is_running():
		_end(mode == &"endless" and reason == "LEFT", reason)


func _on_state(st: StringName) -> void:
	if st == &"menu":
		abort("LEFT")                         # ABORT TO MENU ends the run (an endless run keeps its waves)


func _on_player_died() -> void:
	if is_running():
		_end(mode == &"endless", "DOWN")


# --- simulation -------------------------------------------------------------------------------------------------------------

func tick(dt: float) -> void:
	if not is_running():
		return
	_t += dt
	elapsed += dt
	_prune()
	if phase == &"break":
		break_t -= dt
		if break_t <= 0.0:
			_begin_fight()
		return
	if mode == &"rush":
		_tick_rush()
	else:
		_tick_endless()


func _freeze() -> void:
	_frozen.clear()
	var m := Game.missions as Missions
	if m == null:
		return
	for n: Node in [m.campaign, m.contracts]:
		if n != null and is_instance_valid(n) and n.is_physics_processing():
			n.set_physics_process(false)
			_frozen.append(n)


func _thaw() -> void:
	for n: Node in _frozen:
		if is_instance_valid(n):
			n.set_physics_process(true)
	_frozen.clear()


func _alive(d: Drone) -> bool:
	return d != null and is_instance_valid(d) and d.active and not d.dead and not d.remove


func _prune() -> void:
	for i in range(_foes.size() - 1, -1, -1):
		var d := _foes[i]
		if d == null or not is_instance_valid(d) or not d.active or d.remove:
			_foes.remove_at(i)


func foes_alive() -> int:
	var n := 0
	for d: Drone in _foes:
		if _alive(d):
			n += 1
	return n


func _on_died(d: Drone) -> void:
	if is_running() and _foes.has(d):
		kills += 1
		score += int(round(float(ArenaScripts.KILL_SCORE * maxi(index + 1, 1)) * ArenaScripts.mod_mult(mods, "score")))


func _begin_fight() -> void:
	phase = &"fight"
	if mode == &"endless":
		var wave := index + 1
		_pending = ArenaScripts.wave_count(wave, mods)
		_wave_boss_pending = ArenaScripts.is_brutal_wave(wave, mods)
		Game.say("WAVE %d" % wave, 2.0)
		Sfx.play(&"core")
		wave_started.emit(wave)
	else:
		Game.say("BOSS %d / %d  %s" % [index + 1, ArenaScripts.RUSH_ORDER.size(), String(ArenaScripts.RUSH_ORDER[index]).to_upper()], 2.5)
		Sfx.play(&"core")


func _tick_rush() -> void:
	if _boss == null:
		var id: StringName = ArenaScripts.RUSH_ORDER[index]
		_boss = _spawn(id, ArenaScripts.BOSS_RING, ArenaScripts.rush_hp(diff))
		if _boss != null:
			boss_started.emit(id, index)
		return
	if _alive(_boss):
		return
	_boss = null
	index += 1
	score += 500 * index
	if index >= ArenaScripts.RUSH_ORDER.size():
		_end(true, "")
		return
	_heal()
	phase = &"break"
	break_t = ArenaScripts.break_time(diff)
	Game.say("BOSS DOWN  NEXT IN %d" % int(break_t), 2.0)


func _tick_endless() -> void:
	var cap := mini(ArenaScripts.MAX_FOES, maxi(2, (Game.enemies as EnemyManager).cap() - 2))
	var wave := index + 1
	if _wave_boss_pending:
		_wave_boss_pending = false
		var bid: StringName = ArenaScripts.BRUTAL_BOSSES[(wave / ArenaScripts.BRUTAL_EVERY - 1) % ArenaScripts.BRUTAL_BOSSES.size()]
		_boss = _spawn(bid, ArenaScripts.BOSS_RING, 1.0)
		if _boss == null:
			_wave_boss_pending = true
	var types := ArenaScripts.wave_types(wave)
	var guard := 0
	while _pending > 0 and foes_alive() < cap and guard < 4:
		guard += 1
		var t: StringName = types[_rng.randi() % types.size()]
		if _spawn(t, ArenaScripts.FOE_RING, ArenaScripts.mod_mult(mods, "hp")) != null:
			_pending -= 1
		else:
			break
	if _pending == 0 and foes_alive() == 0 and not _wave_boss_pending:
		_boss = null
		index += 1
		score += 100 * index
		_heal(0.2)
		phase = &"break"
		break_t = ArenaScripts.WAVE_BREAK
		Game.say("WAVE %d CLEAR" % index, 1.5)


func _heal(frac := ArenaScripts.BREAK_HEAL) -> void:
	var p := Game.player as Player
	if p != null and is_instance_valid(p) and p.hp > 0.0:
		p.hp = minf(p.max_hp, p.hp + p.max_hp * frac)


## One foe of `type` on a road 'ring' metres from the hero, aware, health scaled. Null at the manager's cap (a patrol foe is retired to make room).
func _spawn(type: StringName, ring: Vector2, hp_mult: float) -> Drone:
	var em := Game.enemies as EnemyManager
	var p := Game.player as Player
	if em == null or p == null:
		return null
	if em.alive_count() >= em.cap():
		for e: Drone in em.list:
			if is_instance_valid(e) and e.active and not e.dead and not _foes.has(e) and not bool(e.cfg.get("boss", false)):
				em.release(e)
				break
	var at := _point(p.global_position, ring)
	var d := em.spawn(type, at, true)
	if d == null:
		return null
	if hp_mult != 1.0:
		d.max_hp *= hp_mult
		d.hp = d.max_hp
	if not d.died.is_connected(_on_died):
		d.died.connect(_on_died)
	_foes.append(d)
	return d


func _point(center: Vector3, ring: Vector2) -> Vector3:
	var m := Game.missions as Missions
	if m != null and m.contracts != null:
		var q: Vector3 = m.contracts.road_point(center, ring.x, ring.y)
		if q.is_finite():
			return Vector3(q.x, center.y, q.z)
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(ring.x, ring.y)
	return Vector3(center.x + cos(a) * r, center.y, center.z + sin(a) * r)


# --- the end ----------------------------------------------------------------------------------------------------------------

func _end(ok: bool, reason: String) -> void:
	if state != &"running":
		return
	state = &"idle"
	var prog := Game.progress as Progress
	var pay := 0
	var cosmetics: Array[String] = []
	var rank := 0
	var waves := index
	if mode == &"rush" and ok:
		pay = ArenaScripts.rush_reward(diff)
		var key := "rush_%s" % diff
		var times: Array = prog.arena.get(key, []) if prog != null else []
		rank = ArenaScripts.rank_of(times, elapsed)
		if prog != null:
			prog.arena[key] = ArenaScripts.insert_time(times, elapsed)
			prog.arena["clear_%s" % diff] = int(prog.arena.get("clear_%s" % diff, 0)) + 1
		cosmetics.append(String(ArenaScripts.RUSH_COSMETIC[diff]))
	elif mode == &"endless" and ok:
		pay = ArenaScripts.endless_reward(waves, mods)
		cosmetics.append_array(ArenaScripts.endless_cosmetics(waves))
		if prog != null:
			prog.arena["wave_best"] = maxi(int(prog.arena.get("wave_best", 0)), waves)
			prog.arena["score_best"] = maxi(int(prog.arena.get("score_best", 0)), score)
	var granted: Array[String] = []
	if prog != null:
		if pay > 0:
			prog.add_credits(pay)
			prog.bonus_score(pay)
		for key2: String in cosmetics:
			if HeroLook.valid_key(key2) and not prog.hero.owned.has(key2):
				prog.hero.grant(key2)
				granted.append(key2)
		prog.changed.emit()
	result = {"mode": mode, "diff": diff, "ok": ok, "reason": reason, "time": elapsed, "waves": waves, "kills": kills, "score": score, "reward": pay, "cosmetics": granted, "rank": rank, "mods": mods.duplicate()}
	_clear_foes()
	_thaw()
	Sfx.boss_active = false
	Sfx.play(&"ui_contract_complete" if ok else &"ui_contract_fail")
	if mode == &"rush":
		Game.say(("BOSS RUSH CLEAR  %s  +%d CREDITS" % [ArenaScripts.clock_text(elapsed), pay]) if ok else "BOSS RUSH OVER  %s" % reason, 4.0)
	else:
		Game.say("ARENA  %d WAVES  +%d CREDITS" % [waves, pay], 4.0)
	finished.emit(mode, ok, reason)


func _clear_foes() -> void:
	var em := Game.enemies as EnemyManager
	for d: Drone in _foes:
		if em != null and is_instance_valid(d) and d.active and not d.dead:
			em.release(d)
	_foes.clear()
	_boss = null
	_pending = 0
	_wave_boss_pending = false


# --- HUD --------------------------------------------------------------------------------------------------------------------

func hud_line() -> String:
	if not is_running():
		return ""
	if phase == &"break":
		return "%s  NEXT IN %d" % [_head(), int(ceilf(maxf(break_t, 0.0)))]
	if mode == &"rush":
		return "%s  %s" % [_head(), ArenaScripts.clock_text(elapsed)]
	return "%s  FOES %d" % [_head(), foes_alive() + _pending]


func _head() -> String:
	if mode == &"rush":
		return "BOSS RUSH  %d / %d" % [mini(index + 1, ArenaScripts.RUSH_ORDER.size()), ArenaScripts.RUSH_ORDER.size()]
	return "ARENA  WAVE %d" % (index + 1)


## {name, frac} of the boss in the fight for the HUD's boss bar, {} otherwise.
func boss() -> Dictionary:
	if not is_running() or _boss == null or not _alive(_boss):
		return {}
	return {"name": String(_boss.type).to_upper(), "frac": clampf(_boss.hp / maxf(_boss.max_hp, 1.0), 0.0, 1.0)}


func progress_fraction() -> float:
	if not is_running() or mode != &"rush":
		return -1.0
	return float(index) / float(ArenaScripts.RUSH_ORDER.size())
