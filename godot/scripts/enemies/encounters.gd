class_name Encounters
extends Node
## ENCOUNTER DIRECTOR (slice script): about OPEN_DELAY s after play starts a radio callout names where a Vael patrol is coming from, then 5-8 troopers (by tier) arrive from clear
## directions (a squad ahead that rushes, a squad on the side that flanks, an anchor behind that takes cover), in THREE escalating waves, then the street is calm for SET_CALM s before
## the next set. The older rules below still hold (aware at once, rush, backup, caps, pools); the director keeps the ENCOUNTER DIRECTOR notes of the combat-feel wave:
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
signal callout(text: String, dirs: PackedStringArray)     ## the radio call before a wave: where the troopers come from
signal set_cleared(set_no: int)                          ## the third wave of a set is down: calm follows

const FIRST_DELAY := 18.0                 ## the patrol is on the street about 30 s after play starts (the callout comes CALLOUT_LEAD s earlier, they close in for a few seconds)
const CALLOUT_LEAD := 3.5                 ## seconds between the radio callout and the arrival
const SET_WAVES := 3                      ## waves of one set, escalating
const SET_CALM := 60.0                    ## calm seconds after a set before the next one is called
const PATROL_SIZES: Array = [[5, 5, 5], [6, 7, 7], [7, 8, 8]]   ## troopers of wave 1, 2, 3 of a set by tier (LOW, MED, HIGH): 5-8 (the tier's enemy cap trims it)
const GAP := Vector2(2.5, 4.5)            ## calm seconds after a cleared wave (shortened by wave number)
const QUIET_MAX := 12.0                   ## no aware enemy within ENGAGE_RADIUS this long: the next wave comes now
const ENGAGE_RADIUS := 55.0
const SPAWN_MIN := 11.0
const SPAWN_MAX := 21.0
const BACKUP_AFTER := 6.0                 ## seconds into a wave before backup may be called
const BACKUP_SIZE := 2
const WAVE_MAX := 35.0                    ## seconds into a wave after which stragglers out of view fall back (in view: 15 s more)
const HOLD_MAX := 8.0                     ## seconds a fight outside the director's own squad (a street patrol) may hold back the next wave of a set
const HEAT_KEEP := 0.3                    ## after a set the Watch forgets what the fight added: heat falls back to what it was before the set plus this
const PRESSURE_AFTER := 8.0              ## seconds into a wave before the last troopers are sent in (nobody camps in cover for ever); a smaller squad is pressed sooner
const PRESSURE_FEW := 2
const BEARING_MIN := 0.9                  ## radians between the spawn points of one squad when it can
const HEAT_SHARE := 0.05                  ## a squad attacks unprovoked: its kills add this share of the usual heat
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
var set_no := 0                           ## sets started (a set = SET_WAVES waves, then calm)
var wave_in_set := 0                      ## 1..SET_WAVES while a set runs
var phase: StringName = &"open"           ## open (the first countdown) | wave | gap (between waves of a set) | calm (after a set)
var callouts := 0                         ## radio callouts made
var last_callout := ""
var last_dirs: PackedStringArray = []
var sets_cleared := 0
var last_roles: Array[StringName] = []    ## the squad role of every member spawned by the last wave, in spawn order

var _plan: Array[Vector3] = []            ## spawn points picked at the callout (the squad arrives where the radio said)
var _plan_size := 0
var _plan_from := Vector3.INF
var _announced := false

var _calm_t := FIRST_DELAY
var _quiet_t := 0.0
var _wave_t := 0.0
var _backup_done := false
var _pressed := false
var _hold_t := 0.0                        ## seconds the next wave has been held back by somebody else's fight
var _heat0 := 0.0                         ## heat when the current set began
var falls_back := 0                       ## troopers withdrawn by the WAVE_MAX rule
var pressures := 0                        ## waves in which the director sent the remaining troopers in
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
	set_no = 0
	wave_in_set = 0
	phase = &"open"
	_plan.clear()
	_plan_size = 0
	_announced = false
	_hold_t = 0.0


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

## Troopers of wave `k` (1..SET_WAVES) of a set on a graphics tier (0 LOW, 1 MED, 2 HIGH): 5-8, growing with the wave.
static func patrol_size(k: int, tier: int) -> int:
	var row: Array = PATROL_SIZES[clampi(k - 1, 0, PATROL_SIZES.size() - 1)]
	return int(row[clampi(tier, 0, 2)])


## Type of slot `slot` in wave `k` of a set: wave 1 troopers only, wave 2 adds a rusher and a kamikaze, wave 3 a shield and a kamikaze (chapter and tier limits trim it later; a hovering drone is never part of a patrol: it would sit out of reach and stall the wave).
static func patrol_type(k: int, slot: int, chapter: int) -> StringName:
	if slot == 0 or k <= 1:
		return &"operative"
	if k == 2:
		if slot == 1:
			return &"flanker" if chapter >= 1 else &"operative"
		return &"striker" if slot == 2 else &"operative"
	if slot == 1:
		return &"shield" if chapter >= 1 else &"operative"
	return &"striker" if slot == 2 else &"operative"


## Desired bearing (radians from where the camera looks; negative = left) of spawn group `g` of a wave: ahead, the side, behind. Waves flip the side so the set does not repeat.
static func group_bearing(g: int, wave_k: int) -> float:
	var flip := -1.0 if wave_k % 2 == 0 else 1.0
	match g:
		0:
			return 0.35 * flip
		1:
			return -1.75 * flip
		_:
			return 2.7 * flip


## The role of spawn group `g`: the ahead group pushes straight in, the side group flanks, the rest anchor behind cover.
static func group_role(g: int) -> StringName:
	return [&"pusher", &"flanker", &"anchor"][clampi(g, 0, 2)]


## Direction word of a bearing (radians from the camera's forward, negative = left).
static func dir_word(bearing: float) -> String:
	var a := absf(bearing)
	if a < 0.7:
		return "AHEAD"
	if a > 2.3:
		return "BEHIND"
	return "LEFT" if bearing < 0.0 else "RIGHT"


## "VAEL PATROL: 6 TROOPERS. AHEAD AND LEFT" from the count and the direction words.
static func callout_text(n: int, dirs: PackedStringArray) -> String:
	return "VAEL PATROL: %d TROOPERS. %s" % [n, " AND ".join(dirs)]


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


## True while a set is under way (a wave on, or the gap between two waves): the Watch's own heat reinforcements stay home then (the patrol IS the response; stacking street reinforcements on it made the set unwinnable and endless).
func set_busy() -> bool:
	return enabled and (phase == &"wave" or phase == &"gap") and Game.heat < 4.0


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
			_maybe_press()
		return
	_calm_t -= dt
	_quiet_t = 0.0 if near_aware > 0 else _quiet_t + dt
	if phase == &"gap" and _quiet_t >= QUIET_MAX:         # between the waves of a set nobody waits long; the opening and the calm after a set run their full time
		_calm_t = minf(_calm_t, 0.0)
	if near_aware >= 2 and phase != &"calm" and _hold_t < HOLD_MAX:
		_hold_t += dt
		_calm_t = maxf(_calm_t, CALLOUT_LEAD + 1.0)            # a fight is already on (a street patrol): let it play for a few seconds, then the director calls its wave anyway (a camper must not stall the set)
		_announced = false
		_plan.clear()
		return
	if not _announced and _calm_t <= CALLOUT_LEAD:
		announce(mgr, ppos)
	if _calm_t <= 0.0:
		if phase == &"calm" and near_aware > 0:
			_calm_t = 2.0                                      # the calm after a set is not broken while somebody still shoots
			return
		start_wave(mgr, ppos)


## The street's own patrol members and reinforcements farthest from the hero go back to the pool until `want` slots are free (the patrol is the fight of the moment; the cap is the tier's, never raised).
## Mission targets, bosses and anybody within 25 m stay. Returns the room there is afterwards.
func _free_room(mgr: EnemyManager, ppos: Vector3, want: int) -> int:
	var room := mgr.cap() - mgr.alive_count()
	while room < want:
		var best: Drone = null
		var bd := 25.0
		for e in mgr.list:
			if not e.active or e.dead or squad.has(e) or bool(e.cfg.get("boss", false)):
				continue
			if not (e.reinforce or e.has_meta(&"patrol")):
				continue
			var d := Vector2(e.global_position.x - ppos.x, e.global_position.z - ppos.z).length()
			if d > bd:
				bd = d
				best = e
		if best == null:
			break
		mgr.release(best)
		room += 1
	return room


## The radio callout: picks where the next wave arrives (one point per spawn group), says it in plain words and plays the cue. Does nothing when no road point is found (the countdown retries).
func announce(mgr: EnemyManager, ppos: Vector3) -> bool:
	var k := wave_in_set + 1 if phase != &"open" and wave_in_set < SET_WAVES else 1
	var want := mini(patrol_size(k, Game.quality), _free_room(mgr, ppos, patrol_size(k, Game.quality)))
	if want < 2:
		return false
	var groups := 2 if want <= 3 else 3
	var pts := _pick_points(ppos, groups, k)
	if pts.is_empty():
		return false
	_plan = pts
	_plan_size = want
	_plan_from = ppos
	_announced = true
	callouts += 1
	var dirs := PackedStringArray()
	for pt in pts:
		var w := dir_word(_bearing_of(pt, ppos))
		if not dirs.has(w):
			dirs.append(w)
	last_dirs = dirs
	last_callout = callout_text(want, dirs)
	Game.say(last_callout, 3.0)
	Sfx.play(&"drone_alert", -6.0, 1.15)
	callout.emit(last_callout, dirs)
	return true


## Spawn the next wave now. Returns how many came (0 = no room or no road point: the countdown retries in a second).
func start_wave(mgr: EnemyManager, ppos: Vector3) -> int:
	var k := wave_in_set + 1 if phase != &"open" and wave_in_set < SET_WAVES else 1
	var room := _free_room(mgr, ppos, patrol_size(k, Game.quality))
	var want := mini(patrol_size(k, Game.quality), room)
	if want < 2:
		_calm_t = 1.0
		return 0
	var pts: Array[Vector3] = _plan
	if pts.is_empty() or _plan_from.distance_to(ppos) > 18.0:        # nobody called it, or the hero walked away from the plan
		pts = _pick_points(ppos, 2 if want <= 3 else 3, k)
	if pts.is_empty():
		_calm_t = 1.0
		return 0
	if phase == &"open" or phase == &"calm" or wave_in_set >= SET_WAVES:
		set_no += 1
		wave_in_set = 0
		_heat0 = Game.heat
	wave_in_set += 1
	wave += 1
	waves_started += 1
	squad.clear()
	last_spawn_points.clear()
	last_roles.clear()
	var chapter := mgr.chapter_now()
	for slot in want:
		var g := slot % pts.size()
		var pt: Vector3 = pts[g] + Vector3(_rng.randf_range(-2.0, 2.0), 0.0, _rng.randf_range(-2.0, 2.0))
		var d := _spawn_one(mgr, patrol_type(wave_in_set, slot, chapter), pt, chapter, g)
		if d != null:
			squad.append(d)
			last_roles.append(group_role(g))
	if squad.is_empty():
		wave -= 1
		waves_started -= 1
		wave_in_set -= 1
		_calm_t = 1.0
		return 0
	for pt in pts:
		last_spawn_points.append(pt)
	_plan = []
	_announced = false
	state = &"wave"
	phase = &"wave"
	_hold_t = 0.0
	_wave_t = 0.0
	_backup_done = false
	_pressed = false
	_wave_size = squad.size()
	if first_wave_t < 0.0:
		first_wave_t = play_t
	_cue(pts)
	wave_started.emit(wave, squad.size())
	return squad.size()


func _spawn_one(mgr: EnemyManager, type: StringName, pt: Vector3, chapter: int, group := 0) -> Drone:
	var camp := &"drones" if type == &"striker" else &"vael"      # the patrol is Vael troopers; the kamikaze is the swarm's
	var t := Factions.fit_type(type, camp, chapter)
	if mgr.count_type(t) >= EnemyTypes.tier_limit(t, Game.quality) or (EnemyTypes.is_elite(t) and mgr.elite_count() >= EnemyTypes.ELITE_CAPS[clampi(Game.quality, 0, 2)]):
		t = &"operative"
	var d := mgr.spawn(t, pt, true, true, camp)
	if d == null:
		return null
	d.heat_scale = HEAT_SHARE
	if d is Operative:
		(d as Operative).set_squad_role(group_role(group), -1.0 if group % 2 == 1 else 1.0)
	return d


## Bearing of `pt` seen from `ppos`, radians from the camera's forward (negative = left of the view).
static func _bearing_of(pt: Vector3, ppos: Vector3) -> float:
	var cam := Game.camera
	var fwd := Vector3(0.0, 0.0, -1.0)
	if is_instance_valid(cam):
		fwd = -cam.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0.0, 0.0, -1.0)
	var off := Vector3(pt.x - ppos.x, 0.0, pt.z - ppos.z)
	if off.length() < 0.01:
		return 0.0
	off = off.normalized()
	var right := fwd.cross(Vector3.UP)
	return atan2(off.dot(right), off.dot(fwd))


## Is the straight line from the spawn point to the hero at chest height blocked by the world (a building)?
func _walled(q: Vector3, ppos: Vector3) -> bool:
	var pl := Game.player as Node3D
	if not is_instance_valid(pl) or not pl.is_inside_tree():
		return false
	var space := pl.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, q.y + 1.2, q.z), Vector3(ppos.x, ppos.y + 1.2, ppos.z), Game.L_WORLD)
	return not space.intersect_ray(rq).is_empty()


## One road point per spawn group of wave `k`, SPAWN_MIN..SPAWN_MAX from the hero, each as close as the grid allows to the group's bearing (ahead, the side, behind: see group_bearing).
func _pick_points(ppos: Vector3, n: int, k := 1) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var w := Game.world
	if not is_instance_valid(w) or not w.has_method(&"road_point_near"):
		return out
	for g in n:
		var want_b := group_bearing(g, k)
		var best := Vector3.INF
		var best_score := -1.0e9
		for attempt in 20:
			var q: Vector3 = w.call(&"road_point_near", ppos, SPAWN_MIN, SPAWN_MAX)
			if not q.is_finite():
				continue
			var dist := Vector2(q.x - ppos.x, q.z - ppos.z).length()
			if dist < 1.0:
				continue
			var s := -absf(angle_difference(_bearing_of(q, ppos), want_b))
			if g == 0 and dist < SPAWN_MAX - 6.0:
				s -= 0.4                                           # the squad that arrives in view starts at the far end of the street: no pop-in at arm's length
			for o in out:
				s -= 0.6 * maxf(0.0, 0.8 - absf(angle_difference(_bearing_of(o, ppos), _bearing_of(q, ppos))))
			if _walled(q, ppos):
				s -= 0.9 if g > 0 else 1.6                           # a wall between the point and the hero: the troopers have no path finding and would stand against it
			s += _rng.randf() * 0.15
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


## Waves do not stall: PRESSURE_AFTER s in, or with only PRESSURE_FEW left for a third of that, every trooper still standing comes in (Operative.squad_rush) and keeps coming (one that
## slips back into cover is told again). WAVE_MAX s in, the stragglers out of the camera's view fall back (back to the pool in a flash), so a wave always ends.
func _maybe_press() -> void:
	if squad.is_empty():
		return
	var late := _wave_t >= PRESSURE_AFTER or (squad.size() <= PRESSURE_FEW and _wave_t >= PRESSURE_AFTER * 0.5 and _wave_size > PRESSURE_FEW)
	if not late:
		return
	if not _pressed:
		_pressed = true
		pressures += 1
	for d in squad:
		if is_instance_valid(d) and d.active and not d.dead and d is Operative and (d as Operative).needs_push():
			(d as Operative).squad_rush()
	if _wave_t >= WAVE_MAX:
		var cam := Game.camera
		var mgr := Game.enemies as EnemyManager
		for d in squad.duplicate():
			if not is_instance_valid(d) or not d.active or d.dead:
				continue
			if is_instance_valid(cam) and cam.is_position_in_frustum(d.center()) and _wave_t < WAVE_MAX + 15.0:
				continue
			FX.burst(d.global_position + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.25, 0.2), 14, 5.0, 0.5, 0.0)
			falls_back += 1
			mgr.release(d)


func _end_wave() -> void:
	state = &"calm"
	waves_cleared += 1
	_quiet_t = 0.0
	_announced = false
	_plan.clear()
	if wave_in_set >= SET_WAVES:
		phase = &"calm"
		sets_cleared += 1
		Game.heat = minf(Game.heat, _heat0 + HEAT_KEEP)        # the patrol is down: the street (and the Watch) calms with it
		_calm_t = SET_CALM
		set_cleared.emit(set_no)
	else:
		phase = &"gap"
		_calm_t = gap_after(wave, _rng.randf())
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
	return {"wave": wave, "set": set_no, "in_set": wave_in_set, "phase": phase, "started": waves_started, "cleared": waves_cleared, "kills": squad_kills, "backups": backups, "alive": squad.size(),
			"first_wave_t": first_wave_t, "first_engaged_t": first_engaged_t, "state": state}
