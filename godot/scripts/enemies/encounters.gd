class_name Encounters
extends Node
## ENCOUNTER DIRECTOR: there is almost always a fight within 20-40 m. The owner's phone test said "enemies do not come": the patrols stood 110 m away until heat rose, so the
## streets around the hero were empty. The director keeps the street busy on foot:
##   calm  -> a short countdown (first contact FIRST_DELAY s after play starts, GAP s between waves; shorter when nobody aware is near for QUIET_MAX s)
##   wave  -> a squad of 2-5 spawns 20-34 m away on the road grid, out of the camera's view where it can, from up to three bearings (a flank), aware and RUSHING
##            (Operative.rush: cover only briefly, closes to the middle of its range, no idle strafing at distance). A threat cue (a low alarm sting, the squad's own alert calls and a
##            ground burst at each spawn point) tells the player where. Down to one left and at least 3 spawned: BACKUP, two more from the far side, once per wave.
##   Each cleared wave grows the next one (size, then a specialist, a rusher, a kamikaze) up to the tier's enemy cap.
## Nothing here allocates per frame; the squads come from the EnemyManager pools and obey its caps (LOW 5 / MED 8 / HIGH 12, LOW+ 3), tier limits and Factions. The director is silent
## in menus, cutscenes, interiors, vehicles, side activities, contracts and the tutorial (Game.state stays the only pause). It is OFF under tools / tests / bots (Game.autostart) so every other
## test and the perf gate see the world as before; tests switch it on (`enabled = true`) and drive `tick(delta)` or let the live scene run.

signal wave_started(wave: int, size: int)
signal wave_cleared(wave: int)

const FIRST_DELAY := 8.0
const GAP := Vector2(2.5, 4.5)            ## calm seconds after a cleared wave (shortened by wave number)
const QUIET_MAX := 12.0                   ## no aware enemy within ENGAGE_RADIUS this long: the next wave comes now
const ENGAGE_RADIUS := 55.0
const SPAWN_MIN := 20.0
const SPAWN_MAX := 34.0
const MAX_WAVE_SIZE := 5
const BACKUP_AFTER := 6.0                 ## seconds into a wave before backup may be called
const BACKUP_SIZE := 2
const BEARING_MIN := 0.9                  ## radians between the spawn points of one squad when it can
const HEAT_SHARE := 0.3                   ## a squad attacks unprovoked: its kills add this share of the usual heat
const TICK := 0.25
const STING_GAP := 12.0

static var current: Encounters

var enabled := false
var wave := 0                             ## waves started this life
var state: StringName = &"calm"           ## calm | wave
var squad: Array[Drone] = []              ## the living members of the current wave (corpses and released ones are dropped)
var waves_started := 0                    ## lifetime counters for tests and the fight bot
var waves_cleared := 0
var squad_kills := 0
var backups := 0
var first_wave_t := -1.0                  ## seconds from the start of play to the first wave spawning
var first_engaged_t := -1.0               ## seconds from the start of play to the first aware enemy within 40 m of the hero
var play_t := 0.0                         ## seconds of play since the last reset (only counts while the director may run)
var last_spawn_points: Array[Vector3] = []
var stings := 0

var _calm_t := FIRST_DELAY
var _quiet_t := 0.0
var _wave_t := 0.0
var _backup_done := false
var _wave_size := 0
var _acc := 0.0
var _sting_clock := -100.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	current = self
	enabled = not Game.autostart
	_rng.randomize()
	for sig: Signal in [Game.new_game, Game.respawn, Game.next_sector]:
		sig.connect(reset)
	reset()


func _exit_tree() -> void:
	if current == self:
		current = null
	for sig: Signal in [Game.new_game, Game.respawn, Game.next_sector]:
		if sig.is_connected(reset):
			sig.disconnect(reset)


func reset() -> void:
	wave = 0
	state = &"calm"
	squad.clear()
	_calm_t = FIRST_DELAY
	_quiet_t = 0.0
	_wave_t = 0.0
	_backup_done = false
	_wave_size = 0
	play_t = 0.0
	first_wave_t = -1.0
	first_engaged_t = -1.0
	last_spawn_points.clear()


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_acc += delta
	if _acc < TICK:
		return
	var dt := _acc
	_acc = 0.0
	tick(dt)


# --- rules (pure, tested) ---------------------------------------------------------------------------------------------

## Squad size of wave n (1-based): 2, 2, 3, 3, 4, 4, 5 ... capped.
static func size_of(n: int) -> int:
	return clampi(2 + (n - 1) / 2, 2, MAX_WAVE_SIZE)


## The type of slot k in wave n before the camp / tier fit: operatives, with a rusher every 3rd wave, a shield from wave 4 (every 4th), a kamikaze in waves 2 and 5, a drone in wave 6+.
static func type_of(n: int, k: int, chapter: int) -> StringName:
	if k == 0:
		return &"operative"
	if n % 3 == 0 and k == 1:
		return &"flanker" if chapter >= 1 else &"operative"
	if n % 4 == 0 and k == 1:
		return &"shield" if chapter >= 1 else &"operative"
	if (n == 2 or n == 5) and k == 2:
		return &"striker"
	if n >= 6 and k == 3:
		return &"sentinel"
	return &"operative"


## Calm seconds after wave n is cleared.
static func gap_after(n: int, roll: float) -> float:
	return lerpf(GAP.x, GAP.y, roll) * clampf(1.15 - 0.06 * float(n), 0.6, 1.0)


# --- the director -------------------------------------------------------------------------------------------------------

## May the director run now? Never in a menu, a cutscene, an interior, a vehicle, a side activity, a contract or the tutorial.
func may_run() -> bool:
	if not Game.is_playing() or not is_instance_valid(Game.player) or not is_instance_valid(Game.enemies):
		return false
	var p := Game.player as Player
	if p == null or p.is_dead() or p.vehicle != null or InteriorGameplay.active:
		return false
	var act := get_tree().get_first_node_in_group(&"activities") if is_inside_tree() else null
	if act != null and StringName(act.get("active")) != &"":
		return false
	var m := Game.missions
	if m != null and m.get("contracts") != null and StringName(m.contracts.get("state")) == &"active":
		return false
	var story := Game.story
	if story != null and story.get("tutorial") != null and bool(story.tutorial.get("active")):
		return false
	return true


## One director step of `dt` seconds (tests call it directly).
func tick(dt: float) -> void:
	if not may_run():
		return
	play_t += dt
	var mgr := Game.enemies as EnemyManager
	var ppos := (Game.player as Node3D).global_position
	_prune()
	var near_aware := _aware_near(mgr, ppos, ENGAGE_RADIUS)
	if first_engaged_t < 0.0 and _aware_near(mgr, ppos, 40.0) > 0:
		first_engaged_t = play_t
	if state == &"wave":
		_wave_t += dt
		if squad.is_empty():
			_end_wave()
		else:
			_maybe_backup(mgr, ppos)
		return
	_calm_t -= dt
	_quiet_t = 0.0 if near_aware > 0 else _quiet_t + dt
	if _quiet_t >= QUIET_MAX:
		_calm_t = minf(_calm_t, 0.0)
	if near_aware >= 2:
		_calm_t = maxf(_calm_t, 1.5)                            # a fight is already on (a patrol, a reinforcement): let it play
		return
	if _calm_t <= 0.0:
		start_wave(mgr, ppos)


## Spawn the next wave now. Returns how many came (0 = no room or no road point: the countdown retries in a second).
func start_wave(mgr: EnemyManager, ppos: Vector3) -> int:
	var room := mgr.cap() - mgr.alive_count()
	var want := mini(size_of(wave + 1), room)
	if want < 2:
		_calm_t = 1.0
		return 0
	var pts := _pick_points(ppos, mini(want, 3))
	if pts.is_empty():
		_calm_t = 1.0
		return 0
	wave += 1
	waves_started += 1
	squad.clear()
	last_spawn_points.clear()
	var chapter := mgr.chapter_now()
	for k in want:
		var pt: Vector3 = pts[k % pts.size()] + Vector3(_rng.randf_range(-2.5, 2.5), 0.0, _rng.randf_range(-2.5, 2.5))
		var d := _spawn_one(mgr, type_of(wave, k, chapter), pt, chapter)
		if d != null:
			squad.append(d)
	if squad.is_empty():
		wave -= 1
		waves_started -= 1
		_calm_t = 1.0
		return 0
	for pt in pts:
		last_spawn_points.append(pt)
	state = &"wave"
	_wave_t = 0.0
	_backup_done = false
	_wave_size = squad.size()
	if first_wave_t < 0.0:
		first_wave_t = play_t
	_cue(pts)
	wave_started.emit(wave, squad.size())
	return squad.size()


func _spawn_one(mgr: EnemyManager, type: StringName, pt: Vector3, chapter: int) -> Drone:
	var camp := Factions.camp_for(pt, _rng.randf())
	var t := Factions.fit_type(type, camp, chapter)
	if mgr.count_type(t) >= EnemyTypes.tier_limit(t, Game.quality) or (EnemyTypes.is_elite(t) and mgr.elite_count() >= EnemyTypes.ELITE_CAPS[clampi(Game.quality, 0, 2)]):
		t = &"operative"
	var d := mgr.spawn(t, pt, true, true, camp)
	if d == null:
		return null
	d.heat_scale = HEAT_SHARE
	if "rush" in d:
		d.set(&"rush", true)
	return d


## Up to `n` spawn points 20-34 m from the hero on roads: out of the camera's view where possible, separated in bearing so the squad arrives from different sides.
func _pick_points(ppos: Vector3, n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var w := Game.world
	if not is_instance_valid(w) or not w.has_method(&"road_point_near"):
		return out
	var cam := Game.camera
	var fwd := Vector3.ZERO
	if is_instance_valid(cam):
		fwd = -cam.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
	for k in n:
		var best := Vector3.INF
		var best_score := -1.0e9
		for attempt in 8:
			var q: Vector3 = w.call(&"road_point_near", ppos, SPAWN_MIN, SPAWN_MAX)
			if not q.is_finite():
				continue
			var off := Vector3(q.x - ppos.x, 0.0, q.z - ppos.z)
			var dist := off.length()
			if dist < 1.0:
				continue
			var s := 0.0
			var dir := off / dist
			if fwd != Vector3.ZERO and fwd.dot(dir) > 0.55 and dist < SPAWN_MAX - 4.0:
				s -= 3.0                                         # right in front of the lens: a pop-in
			for o in out:
				var ang := absf(angle_difference(atan2(o.x - ppos.x, o.z - ppos.z), atan2(off.x, off.z)))
				if ang < BEARING_MIN:
					s -= 2.0 * (BEARING_MIN - ang)
			s += _rng.randf() * 0.5
			if s > best_score:
				best_score = s
				best = q
		if best.is_finite():
			out.append(best)
	return out


## The threat cue: a low alarm, the squad's own alert calls from where it stands and a ground burst per spawn point. No text on screen.
func _cue(pts: Array[Vector3]) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _sting_clock >= STING_GAP or wave <= 1:
		_sting_clock = now
		stings += 1
		Sfx.play(&"drone_alert", -3.0, 0.8)
	for i in pts.size():
		var pt: Vector3 = pts[i]
		Sfx.play_at(StringName("trooper_alert_%d" % (i % 3)), pt, -2.0, _rng.randf_range(0.9, 1.1))
		FX.burst(pt + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.25, 0.2), 22, 6.0, 0.6, 0.0)


func _maybe_backup(mgr: EnemyManager, ppos: Vector3) -> void:
	if _backup_done or _wave_t < BACKUP_AFTER or _wave_size < 3 or squad.size() > 1:
		return
	_backup_done = true
	var room := mgr.cap() - mgr.alive_count()
	var n := mini(BACKUP_SIZE, room)
	if n <= 0:
		return
	var far := Vector3.INF
	if not squad.is_empty():                                       # the far side from the one that is left
		var s := squad[0].global_position
		var mirror := Vector3(2.0 * ppos.x - s.x, 0.0, 2.0 * ppos.z - s.z)
		var w := Game.world
		if is_instance_valid(w) and w.has_method(&"road_point_near"):
			far = w.call(&"road_point_near", mirror, 0.0, 14.0)
	var pts: Array[Vector3] = []
	if far.is_finite() and Vector2(far.x - ppos.x, far.z - ppos.z).length() >= SPAWN_MIN - 6.0:
		pts.append(far)
	else:
		pts = _pick_points(ppos, 1)
	if pts.is_empty():
		return
	backups += 1
	var chapter := mgr.chapter_now()
	for k in n:
		var d := _spawn_one(mgr, &"operative", pts[0] + Vector3(_rng.randf_range(-2.0, 2.0), 0.0, _rng.randf_range(-2.0, 2.0)), chapter)
		if d != null:
			squad.append(d)
	_cue(pts)


func _end_wave() -> void:
	state = &"calm"
	waves_cleared += 1
	_calm_t = gap_after(wave, _rng.randf())
	_quiet_t = 0.0
	wave_cleared.emit(wave)


## Drop dead and released squad members (their kills are counted once).
func _prune() -> void:
	var i := squad.size() - 1
	while i >= 0:
		var d := squad[i]
		if not is_instance_valid(d) or not d.active:
			squad.remove_at(i)
		elif d.dead:
			squad_kills += 1
			squad.remove_at(i)
		i -= 1


static func _aware_near(mgr: EnemyManager, ppos: Vector3, r: float) -> int:
	var n := 0
	var r2 := r * r
	for e in mgr.list:
		if e.active and not e.dead and e.aware:
			var dx := e.global_position.x - ppos.x
			var dz := e.global_position.z - ppos.z
			if dx * dx + dz * dz < r2:
				n += 1
	return n


func stats() -> Dictionary:
	return {"wave": wave, "started": waves_started, "cleared": waves_cleared, "kills": squad_kills, "backups": backups, "alive": squad.size(),
			"first_wave_t": first_wave_t, "first_engaged_t": first_engaged_t, "state": state}
