extends RefCounted
## NPC life on top of the MultiMesh crowd (scripts/ambient/ambient_crowd.gd): schedules, reactions, patrol calls and a proximity prompt dialogue.
##
## - Schedules (time-of-day free) live in the crowd: people walk the sidewalk lines between shop fronts and bus stops, linger there facing the window or the road
##   and chat in groups (see Crowd._assign_goal). This class adds the reactions and the talk.
## - Only the nearest PROMOTE_MAX people within PROMOTE_RADIUS are "actors": they get the per-person scans (speeding cars, the prompt line, pointing, calling
##   patrols). Everybody else stays a record in the MultiMesh; gunfire, explosions and heat scares are one pass over the whole pool (<= 90 people).
## - Reactions: gunfire (run, or cower / point when close), explosions (run from a wide radius, cower close), the player's heat rising a star (the street
##   scatters), fast vehicles (the people in their way jump aside). A person who sees it may call the Vael patrol: heat + CALL_HEAT, at most one call per CALL_CD
##   seconds and never above CALL_HEAT_CAP.
## - Dialogue: standing within TALK_RANGE of an actor who is not running shows one line through Game.say (the HUD centre message), at most one per TALK_CD seconds.
## Nothing is allocated per frame (fixed arrays, counters).

const Lines := preload("res://scripts/npc/npc_lines.gd")
const Dlg := preload("res://scripts/npc/npc_dialogue.gd")

const PROMOTE_MAX := 12
const PROMOTE_RADIUS := 26.0
const PROMOTE_EVERY := 0.25
const SCAN_EVERY := 0.2
const TALK_RANGE := 3.4
const TALK_CD := 9.0
const PERSON_TALK_CD := 60.0
const CLOSE := 10.0                      ## within this of a shot / blast a person may cower or point instead of running
const COWER_CHANCE := 0.35
const POINT_CHANCE := 0.15
const HEAT_SCATTER := 30.0              ## the street scatters within this of the player when heat gains a star
const CALL_RADIUS := 20.0
const CALL_CHANCE := 0.3
const CALL_CD := 8.0
const CALL_HEAT := 0.08
const CALL_HEAT_CAP := 2.5
const BLAST_REACH := 5.0                 ## blast radius multiplier for the run-away zone (min BLAST_MIN)
const BLAST_MIN := 28.0
const CAR_SPEED := 7.0                   ## vehicles slower than this do not scare anybody
const POOL := 100
const EXCHANGE_CHANCE := 0.4             ## a chatting / lingering person starts a 2-3 line exchange this often
const EXCHANGE_GAP := 3.4                ## seconds between the lines of an exchange

var crowd: RefCounted
var rng := RandomNumberGenerator.new()
var actors := PackedInt32Array()         ## promoted people, nearest first (at most PROMOTE_MAX)
var clock := 0.0
var enabled := true
var calls := 0                           ## patrol calls made
var lines_said := 0
var last_line := ""
var reactions := 0                       ## cower / point reactions made
var car_scares := 0
var blasts_seen := 0
var exchanges := 0                       ## 2-3 line exchanges started
var theft_seen := 0                      ## vehicle thefts noted (COMMANDEERED)
var barks := 0                    ## alien calls voiced through Sfx.bark

var _promote_t := 0.0
var _scan_t := 0.0
var _talk_cd := 0.0
var _call_cd := 0.0
var _last_serial := 0
var _ext_until := 0.0                    ## clock time until which a message that is not ours (mission, pickup, tutorial) owns the HUD centre line
var _last_heat := 0.0
var _talked := PackedFloat32Array()      ## clock time of the last line per pool slot
var _rumours: Array[String] = []
var _queue: Array[String] = []           ## the rest of an exchange, spoken from step()
var _queue_t := 0.0
var _dist := PackedFloat32Array()


func setup(crowd_ref: RefCounted) -> void:
	crowd = crowd_ref
	rng.seed = 777001
	_talked.resize(POOL)
	_dist.resize(POOL)
	_rumours = Lines.rumours()
	Dlg.reset_memory()
	if not Game.message.is_connected(_on_game_message):
		Game.message.connect(_on_game_message)
	reset()


func reset() -> void:
	actors.clear()
	clock = 0.0
	_promote_t = 0.0
	_scan_t = 0.0
	_talk_cd = 3.0
	_call_cd = 0.0
	_ext_until = 0.0
	_queue.clear()
	_last_heat = Game.heat
	_talked.fill(-1000.0)
	_sync_serial()


## Remember the explosions that already exist, so only new ones scare people.
func _sync_serial() -> void:
	_last_serial = 0
	for s in _slots():
		_last_serial = maxi(_last_serial, s.serial)


func _slots() -> Array:
	var pool: Object = FX.explosions if FX != null else null
	if pool == null or not is_instance_valid(pool):
		return []
	return pool.get("slots") as Array


func step(delta: float, center: Vector3) -> void:
	if not enabled or crowd == null:
		return
	clock += delta
	Dlg.tick(delta)
	_speak_queue()
	_talk_cd = maxf(0.0, _talk_cd - delta)
	_call_cd = maxf(0.0, _call_cd - delta)
	_promote_t -= delta
	if _promote_t <= 0.0:
		_promote_t = PROMOTE_EVERY
		_promote(center)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_EVERY
		_poll_blasts(center)
		_poll_heat(center)
		_scan_vehicles()
		Dlg.poll_kills()
		_talk(center)


## The nearest PROMOTE_MAX living people within PROMOTE_RADIUS (insertion into a tiny sorted list).
func _promote(center: Vector3) -> void:
	actors.clear()
	var r2 := PROMOTE_RADIUS * PROMOTE_RADIUS
	for i in crowd.count:
		if not crowd.is_alive(i):
			continue
		var p: Vector3 = crowd.person_position(i)
		var d := (p.x - center.x) * (p.x - center.x) + (p.z - center.z) * (p.z - center.z)
		if d > r2:
			continue
		_dist[i] = d
		var at := actors.size()
		while at > 0 and _dist[actors[at - 1]] > d:
			at -= 1
		if at >= PROMOTE_MAX:
			continue
		actors.insert(at, i)
		if actors.size() > PROMOTE_MAX:
			actors.resize(PROMOTE_MAX)


func is_actor(i: int) -> bool:
	return actors.has(i)


## The player fired at `pos` (the crowd has already been sent running by Crowd.on_shot): close people cower or point instead, and somebody may call the patrol.
func on_shot(pos: Vector3, player_pos: Vector3) -> void:
	if not enabled or crowd == null:
		return
	crowd.on_shot(pos)
	_after_scare(pos, player_pos, CLOSE)


## A blast at `pos` of `radius`.
func on_blast(pos: Vector3, radius: float, player_pos: Vector3) -> void:
	if not enabled or crowd == null:
		return
	blasts_seen += 1
	crowd.scare_from(pos, maxf(BLAST_MIN, radius * BLAST_REACH))
	_after_scare(pos, player_pos, maxf(CLOSE, radius * 1.5))


func _after_scare(pos: Vector3, player_pos: Vector3, close_r: float) -> void:
	var near_runner := false
	for i in crowd.count:
		if not crowd.is_alive(i) or not crowd.is_fleeing(i):
			continue
		var p: Vector3 = crowd.person_position(i)
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if d < close_r:
			var roll := rng.randf()
			if roll < COWER_CHANCE:
				crowd.cower_person(i, rng.randf_range(3.0, 7.0))
				reactions += 1
				_voice(&"yelp", i)
			elif roll < COWER_CHANCE + POINT_CHANCE:
				crowd.attend(i, player_pos, rng.randf_range(2.0, 4.0))
				reactions += 1
		if crowd.is_fleeing(i) and Vector2(p.x - player_pos.x, p.z - player_pos.z).length() < CALL_RADIUS:
			near_runner = true
	if near_runner:
		_try_call(player_pos)


## One person in sight calls the Vael patrol: heat goes up a little (never above CALL_HEAT_CAP through this).
func _try_call(player_pos: Vector3) -> bool:
	if _call_cd > 0.0 or rng.randf() >= CALL_CHANCE:
		return false
	_call_cd = CALL_CD
	calls += 1
	if Game.heat < CALL_HEAT_CAP:
		Game.add_heat(minf(CALL_HEAT, CALL_HEAT_CAP - Game.heat))
	_say(Lines.pick(Lines.CALL, rng), 2.4)
	return true


func _poll_blasts(player_pos: Vector3) -> void:
	var top := _last_serial
	for s in _slots():
		if s.active and s.serial > _last_serial:
			top = maxi(top, s.serial)
			on_blast(s.pos, s.radius, player_pos)
	_last_serial = top


func _poll_heat(player_pos: Vector3) -> void:
	var h: float = Game.heat
	if floorf(h) > floorf(_last_heat):
		crowd.scare_from(player_pos, HEAT_SCATTER)
	_last_heat = h


## Fast vehicles scare the actors they are about to run over.
func _scan_vehicles() -> void:
	var vm: Object = Game.vehicles
	if vm == null or actors.is_empty():
		return
	var list: Array = vm.get("list") as Array
	for v: Variant in list:
		if not is_instance_valid(v):
			continue
		var speed := absf(float(v.get("speed")))
		if speed < CAR_SPEED:
			continue
		var vp: Vector3 = (v as Node3D).global_position
		var reach := 3.5 + 0.25 * speed
		for i in actors:
			if not crowd.is_alive(i) or crowd.is_fleeing(i):
				continue
			var p: Vector3 = crowd.person_position(i)
			if Vector2(p.x - vp.x, p.z - vp.z).length() < reach:
				crowd.scare_person(i, vp)
				car_scares += 1


## The proximity prompt: the nearest actor within TALK_RANGE says one line (barks / rumours; scared or wanted lines by the situation).
func _talk(player_pos: Vector3) -> void:
	if _talk_cd > 0.0 or clock < _ext_until or actors.is_empty() or not Game.is_playing():
		return
	if Game.vehicles != null and Game.vehicles.get("driven") != null:
		return
	var i: int = actors[0]
	if _dist[i] > TALK_RANGE * TALK_RANGE or crowd.is_fleeing(i) or clock - _talked[i] < PERSON_TALK_CD:
		return
	var st: StringName = crowd.state_of(i)
	if (st == &"idle" or st == &"linger") and Game.heat < 3.0 and rng.randf() < EXCHANGE_CHANCE:
		var ex := Dlg.exchange(Dlg.context(player_pos), rng)
		if ex.size() >= 2:
			_talked[i] = clock
			_talk_cd = TALK_CD + EXCHANGE_GAP * float(ex.size())
			_voice(&"chitter", i)
			if not crowd.is_cowering(i):
				crowd.attend(i, player_pos, 3.0 + EXCHANGE_GAP * float(ex.size()))
			exchanges += 1
			for k in range(1, ex.size()):
				_queue.append(ex[k])
			_queue_t = clock + EXCHANGE_GAP
			_say(ex[0], 3.2)
			return
	var line := line_for(i)
	_talked[i] = clock
	_talk_cd = TALK_CD
	_voice(&"chitter", i)
	if not crowd.is_cowering(i):
		crowd.attend(i, player_pos, 3.0)
	_say(line, 3.2)


## The line person `i` would say now (also for tests).
func line_for(i: int) -> String:
	var st: StringName = crowd.state_of(i)
	if st == &"cower":
		return Lines.pick(Lines.SCARED, rng)
	if Game.heat >= 3.0:
		return Lines.pick(Lines.WANTED, rng)
	var ctx := Dlg.context(crowd.person_position(i))
	if st == &"linger":
		if rng.randf() < 0.6:
			return Dlg.bark(ctx, rng)
		return Lines.pick(Lines.SHOP if crowd.last_stop_kind(i) != 2 else Lines.BUS, rng)
	if st == &"idle":
		if rng.randf() < 0.6:
			return Dlg.bark(ctx, rng)
		return Lines.pick(Lines.CHAT, rng)
	if rng.randf() < 0.4:
		var h := Dlg.hint(rng)
		if h != "":
			return h
	return Lines.PREFIX + _rumours[rng.randi() % _rumours.size()]


## The next line of a running exchange (dropped when the game is not playing or a mission message owns the HUD line).
func _speak_queue() -> void:
	if _queue.is_empty() or clock < _queue_t:
		return
	if not Game.is_playing() or clock < _ext_until:
		_queue.clear()
		return
	var line: String = _queue.pop_front()
	_queue_t = clock + EXCHANGE_GAP
	_say(line, 3.2)


func _on_game_message(text: String, seconds: float) -> void:
	if text == "VEHICLE COMMANDEERED":
		Dlg.note_theft()
		theft_seen += 1
	if text != last_line:
		_ext_until = clock + seconds


## An alien call from person `i` (same pitch every time for the same person). Capped by Sfx's single bark voice family.
func _voice(kind: StringName, i: int) -> void:
	barks += 1
	Sfx.bark(kind, crowd.person_position(i), 0.85 + 0.3 * float((i * 7919) % 100) / 100.0)


func _say(text: String, seconds: float) -> void:
	if clock < _ext_until:                  # never overwrite a mission / pickup / tutorial message with a bark
		return
	last_line = text
	lines_said += 1
	Game.say(text, seconds)


func stats() -> Dictionary:
	return {"actors": actors.size(), "calls": calls, "lines": lines_said, "reactions": reactions, "car_scares": car_scares, "blasts": blasts_seen, "barks": barks, "exchanges": exchanges}
