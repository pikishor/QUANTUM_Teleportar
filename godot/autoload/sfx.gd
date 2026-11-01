extends Node
## All of the game's sound: effects, ambience, radio voice, vehicle loops, vitals and adaptive music. Contract: ARCHITECTURE.md "audio (as implemented)".
##
## Effects: Sfx.play(&"name", db, pitch) / Sfx.play_at(&"name", pos, db, pitch). A name resolves to res://assets/audio/<name>.wav (or .ogg) plus its variants
## <name>_0 .. <name>_15; one is picked at random, never the same twice in a row. Unknown names are ignored, so callers may ask for sounds that do not exist yet.
## Voices are pooled (POOL flat + POOL_3D positional, nothing is allocated while playing), every sound family has a priority, a voice cap and a minimum gap
## (FAMILIES): a family over its cap cuts its own oldest voice, a full pool steals the oldest voice of lower or equal priority and drops the sound when everything
## playing matters more. Positional sounds further than MAX_DIST (explosions: 2x) are not started.
## Buses (assets/audio/default_bus_layout.tres): Master (limiter) <- SFX (gentle compressor), Music (low-pass), Ambient (low-pass), Voice (the radio). Per-bus volume:
## set_bus_volume(bus, linear 0..1) / apply_volumes(dict) (the settings screen); `muted` mutes everything, music included.
## Ducking, sidechain style: explosions pull Music and Ambient down for about a second and release slowly, the radio holds them down while ORACLE babbles.
## Music: five looping stems (pad, pulse, bass, perc, lead) played sample-locked by one AudioStreamSynchronized and faded by game state (explore, alert, combat,
## driving, menu, death, win; stings on death and win). With auto_music the state follows Game (heat 1-3 alert, 3+ combat, a driven car, dead, win).
## Living sound, all simulated only while Game.is_playing(): footsteps from the hero's foot plants (Locomotion.footfalls), the player's car (RPM loop pair, tyre
## squeal, crashes), traffic hum on the three nearest moving cars, quantum loops, heartbeat and breath at low health, rain/wind/traffic/hum beds with thunder.
## Lifecycle signals (new_game, respawn, next_sector, player_died) reset every loop and timer.
## main.gd starts it for a real run (play_music() also starts the ambience); tools, tests and bots (Game.autostart) stay silent unless they call it.

const DIR := "res://assets/audio/"
const SFX_BUS := &"SFX"
const MUSIC_BUS := &"Music"
const AMBIENT_BUS := &"Ambient"
const VOICE_BUS := &"Voice"
const BUS_NAMES: Array[StringName] = [&"Master", &"SFX", &"Music", &"Ambient", &"Voice"]
const POOL := 20                  ## flat voices (rifle fire alone keeps about 8 busy)
const POOL_3D := 12               ## positional voices
const VOICE_POOL := 4             ## radio syllables
const ONESHOT_POOL := 4           ## thunder and other ambience one-shots (Ambient bus)
const MAX_DIST := 140.0
const MUSIC_NAME := &"music_ambient"
const MUSIC_DB := -5.0
const OFF_DB := -60.0
const TOP_SPEED := 30.0

## family prefix, priority (higher survives), voice cap, minimum seconds between two starts, random pitch jitter. The first matching prefix wins.
const FAMILIES: Array = [
	["step_", 0, 3, 0.10, 0.05], ["land_", 1, 2, 0.15, 0.04], ["impact_", 1, 6, 0.03, 0.06], ["ricochet", 1, 3, 0.08, 0.10], ["whizz", 1, 3, 0.09, 0.08],
	["shot_far", 1, 4, 0.05, 0.04], ["enemy_shot", 2, 5, 0.05, 0.04], ["shot", 2, 6, 0.04, 0.0], ["dry_fire", 2, 1, 0.10, 0.0], ["reload", 2, 1, 0.30, 0.0],
	["boom", 4, 3, 0.12, 0.03], ["explosion", 4, 3, 0.12, 0.03], ["distant_", 0, 2, 0.50, 0.05], ["thunder", 3, 2, 2.0, 0.03], ["siren", 0, 2, 1.0, 0.02],
	["trooper_", 2, 4, 0.10, 0.07], ["hero_", 3, 2, 0.20, 0.04], ["drone_", 1, 3, 0.10, 0.03], ["hit", 1, 5, 0.03, 0.0], ["hurt", 3, 2, 0.10, 0.0],
	["blink", 3, 2, 0.10, 0.0], ["link", 3, 2, 0.10, 0.0], ["superpos", 3, 2, 0.10, 0.0], ["quantum_", 3, 2, 0.10, 0.0], ["entangle", 3, 1, 0.10, 0.0],
	["car_", 2, 3, 0.10, 0.05], ["horn", 2, 1, 0.20, 0.02], ["engine_", 2, 2, 0.10, 0.0], ["tyre", 1, 1, 0.10, 0.0],
	["ui_", 4, 3, 0.03, 0.0], ["pickup", 3, 3, 0.05, 0.0], ["credit", 3, 2, 0.05, 0.0], ["mission_", 4, 1, 0.50, 0.0], ["objective", 3, 1, 0.30, 0.0], ["heat_", 3, 1, 0.50, 0.0],
	["heartbeat", 2, 2, 0.20, 0.0], ["breath", 1, 2, 0.30, 0.03], ["gasp", 2, 1, 0.50, 0.0], ["radio_", 3, 2, 0.05, 0.0], ["babble", 1, 3, 0.04, 0.0], ["core", 3, 2, 0.20, 0.0],
]
const DEFAULT_RULE: Array = ["", 1, 6, 0.0, 0.0]

const STEMS: Array[StringName] = [&"pad", &"pulse", &"bass", &"perc", &"lead"]
## stem levels (dB) per music state: pad, pulse, bass, perc, lead
const MUSIC_STATES := {
	&"menu": [0.0, -14.0, -60.0, -60.0, -8.0],
	&"explore": [0.0, -9.0, -16.0, -60.0, -60.0],
	&"alert": [-2.0, -3.0, -6.0, -12.0, -60.0],
	&"combat": [-4.0, 0.0, 0.0, 0.0, -3.0],
	&"driving": [-8.0, -2.0, -3.0, -4.0, -4.0],
	&"boss": [-3.0, 0.0, 0.0, 0.0, 0.0],
	&"death": [-18.0, -60.0, -60.0, -60.0, -60.0],
	&"win": [-3.0, -10.0, -60.0, -60.0, -2.0],
}
const STATE_TAU := 0.7            ## seconds of the stem crossfades
const MUSIC_MIN_HOLD := 6.0       ## a state is kept at least this long before the music drops back to a calmer one
const HEAT_ALERT := 1.0
const HEAT_COMBAT := 3.0

## duck depths (dB) per bus: [Music, Ambient, SFX, Voice], attack seconds, default hold seconds, release seconds
const DUCKS := {
	&"explosion": {"depth": {&"Music": -9.0, &"Ambient": -11.0}, "attack": 0.04, "hold": 0.9, "release": 2.2},
	&"radio": {"depth": {&"Music": -7.0, &"Ambient": -9.0, &"SFX": -2.5}, "attack": 0.15, "hold": 0.4, "release": 0.9},
}

var _cache := {}                  ## name -> Array[AudioStream] (variants; empty when the sound does not exist)
var _rules := {}
var _last_pick := {}
var last_played: StringName = &""   ## the last flat sound that actually started (tests check UI cue wiring with it)
var _last_start := {}             ## family -> seconds of the last start
var _players: Array[AudioStreamPlayer] = []
var _players3d: Array[AudioStreamPlayer3D] = []
var _voices: Array[AudioStreamPlayer] = []
var _oneshots: Array[AudioStreamPlayer] = []
var _t_flat := PackedFloat64Array()
var _t_3d := PackedFloat64Array()
var _prio_flat := PackedInt32Array()
var _prio_3d := PackedInt32Array()
var _fam_flat: Array[String] = []
var _fam_3d: Array[String] = []
var _music: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _stems: AudioStreamSynchronized
var _stem_db := PackedFloat32Array([OFF_DB, OFF_DB, OFF_DB, OFF_DB, OFF_DB])
var _stem_target := PackedFloat32Array([OFF_DB, OFF_DB, OFF_DB, OFF_DB, OFF_DB])
var _stem_tau := STATE_TAU
var _legacy_music := false
var _vol_music := MUSIC_DB
var _user_db := {}                ## bus -> the player's volume choice in dB
var _duck_level := {&"explosion": 0.0, &"radio": 0.0}
var _duck_hold := {&"explosion": 0.0, &"radio": 0.0}
var _bus_db_applied := {}
var _lp_music: AudioEffectLowPassFilter
var _lp_ambient: AudioEffectLowPassFilter
var _muffle := 0.0                ## 0..1: how far the music / ambience low-pass is closed (low health, inside a car)
var _muffle_target := 0.0

## Mutes everything, music included (the settings screen toggles it).
var muted := false:
	set(v):
		muted = v
		var i := AudioServer.get_bus_index(&"Master")
		if i >= 0:
			AudioServer.set_bus_mute(i, v)
		if _music != null:
			_music.stream_paused = v
		if v:
			_silence_loops()

## When true the music state follows the game (heat, vehicle, death, win); tests and cutscenes may switch it off and call set_music_state themselves.
var auto_music := true
var music_state: StringName = &"explore"
## True while the Vael Overseer lives (Overseer sets it): the music state follows to `boss` (every stem up) until he falls or the contract ends.
var boss_active := false
var _state_since := 0.0
var _state_clock := 0.0
var _state_poll := 0.0

# --- ambience / loops
var _ambience_on := false
var _amb: Dictionary = {}         ## name -> AudioStreamPlayer (loops on the Ambient bus)
var _amb_vol := {}                ## name -> smoothed linear volume
var _loops: Dictionary = {}       ## name -> AudioStreamPlayer (quantum loops, engine, tyres on the SFX bus)
var _loop_gain := {}              ## name -> {db, target}
var _emitters: Array[AudioStreamPlayer3D] = []
var _emitter_car: Array = [null, null, null]
var _emit_poll := 0.0
var _hum_emitters: Array[AudioStreamPlayer3D] = []
var _hum_target: Array = [null, null]
var _en_state := {}               ## enemy instance id -> Vector4(aware, hp, dead, telegraph charge) of the last poll
var _en_poll := 0.0
var _thunder_in := 25.0
var _distant_in := 60.0
var _rain_surface := &"asphalt"

# --- gameplay hooks
var _last_footfalls := -1
var _prev_speed := 0.0
var _crash_cd := 0.0
var _rpm := 0.1
var _heart_t := 0.0
var _breath_t := 0.0
var _breath_in := true
var _driven = null                ## the player's car (untyped: it may be freed under us)
var _horn_cd := 0.0
var _was_air := 0.0

# --- delayed one-shots (whizz after a distant shot, ricochets): no allocation, fixed slots
const PENDING := 12
var _pend_t := PackedFloat32Array()
var _pend_name: Array[StringName] = []
var _pend_pos: Array[Vector3] = []
var _pend_db := PackedFloat32Array()
var _pend_pitch := PackedFloat32Array()

# --- radio
var _radio_active := false
var _radio_idle := 0.0
var _radio_len := 0
var _radio_seen := 0
var _radio_pending := 0
var _radio_gap := 0.0
var _radio_pitch := 1.0

var _warm_queue: Array[StringName] = []
var _connected := false
var _last_game_state: StringName = &"menu"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var sfx_bus: StringName = _bus_or_master(SFX_BUS)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = sfx_bus
		add_child(p)
		_players.append(p)
		_t_flat.append(0.0)
		_prio_flat.append(0)
		_fam_flat.append("")
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 12.0
		p3.max_distance = MAX_DIST * 1.5
		p3.bus = sfx_bus
		add_child(p3)
		_players3d.append(p3)
		_t_3d.append(0.0)
		_prio_3d.append(0)
		_fam_3d.append("")
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = _bus_or_master(MUSIC_BUS)
	_music.volume_db = MUSIC_DB
	_music.stream_paused = muted
	add_child(_music)
	var voices := Node.new()
	voices.name = "Voices"
	add_child(voices)
	_sting = AudioStreamPlayer.new()
	_sting.name = "Sting"
	_sting.bus = _bus_or_master(MUSIC_BUS)
	_sting.volume_db = -3.0
	voices.add_child(_sting)
	for i in VOICE_POOL:
		var v := AudioStreamPlayer.new()
		v.bus = _bus_or_master(VOICE_BUS)
		voices.add_child(v)
		_voices.append(v)
	var ones := Node.new()
	ones.name = "OneShots"
	add_child(ones)
	for i in ONESHOT_POOL:
		var o := AudioStreamPlayer.new()
		o.bus = _bus_or_master(AMBIENT_BUS)
		ones.add_child(o)
		_oneshots.append(o)
	for i in PENDING:
		_pend_t.append(-1.0)
		_pend_name.append(&"")
		_pend_pos.append(Vector3.ZERO)
		_pend_db.append(0.0)
		_pend_pitch.append(1.0)
	var amb_root := Node.new()
	amb_root.name = "Ambience"
	add_child(amb_root)
	for bed: StringName in BEDS:                                   # all nodes exist from the start (streams are loaded when the ambience starts)
		var bp := AudioStreamPlayer.new()
		bp.bus = _bus_or_master(AMBIENT_BUS)
		bp.volume_db = OFF_DB
		amb_root.add_child(bp)
		_amb[bed] = bp
		_amb_vol[bed] = 0.0
	for k in 3:
		var e := AudioStreamPlayer3D.new()
		e.unit_size = 9.0
		e.max_distance = 75.0
		e.bus = _bus_or_master(SFX_BUS)
		e.volume_db = OFF_DB
		amb_root.add_child(e)
		_emitters.append(e)
	for k in 2:
		var h := AudioStreamPlayer3D.new()
		h.unit_size = 7.0
		h.max_distance = 50.0
		h.bus = _bus_or_master(SFX_BUS)
		h.volume_db = OFF_DB
		amb_root.add_child(h)
		_hum_emitters.append(h)
	var loops_root := Node.new()
	loops_root.name = "Loops"
	add_child(loops_root)
	for ln: StringName in [&"engine_low", &"engine_high", &"tyre_squeal", &"superpos_loop", &"entangle_loop"]:
		var lpl := AudioStreamPlayer.new()
		lpl.bus = _bus_or_master(SFX_BUS)
		lpl.volume_db = OFF_DB
		loops_root.add_child(lpl)
		_loops[ln] = lpl
	for b in BUS_NAMES:
		_user_db[b] = 0.0
	_lp_music = _find_lowpass(MUSIC_BUS)
	_lp_ambient = _find_lowpass(AMBIENT_BUS)
	_vol_music = MUSIC_DB
	_connect_game()                                                # Game is an earlier autoload: its signals exist already


func _connect_game() -> void:
	if _connected:
		return
	_connected = true
	Game.state_changed.connect(_on_state)
	Game.new_game.connect(reset_world)
	Game.respawn.connect(reset_world)
	Game.next_sector.connect(reset_world)
	Game.player_died.connect(_on_player_died)
	Game.sector_cleared.connect(func() -> void: play(&"mission_complete", -4.0))


# ---------------------------------------------------------------------------------------------------------------------
# effects
# ---------------------------------------------------------------------------------------------------------------------

func play(sfx_name: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	if muted:
		return
	var s := _pick(sfx_name)
	if s == null:
		return
	var rule := _rule(sfx_name)
	var fam: String = rule[0]
	var now := _now()
	if not _gap_ok(fam, float(rule[3]), now):
		return
	var i := _slot(_players, _fam_flat, _prio_flat, _t_flat, int(rule[1]), fam, int(rule[2]))
	if i < 0:
		return
	var p := _players[i]
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch * _jitter(float(rule[4]))
	_fam_flat[i] = fam
	_prio_flat[i] = int(rule[1])
	_t_flat[i] = now
	_last_start[fam] = now
	last_played = sfx_name
	p.play()
	_after_play(sfx_name)


func play_at(sfx_name: StringName, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if muted:
		return
	var rule := _rule(sfx_name)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var dist := 0.0
	if cam != null:
		dist = cam.global_position.distance_to(pos)
		if dist > MAX_DIST * (2.0 if int(rule[1]) >= 4 else 1.0):
			return
	var name_now := sfx_name
	if dist > 45.0 and (sfx_name == &"enemy_shot" or sfx_name == &"shot"):
		name_now = StringName(String(sfx_name) + "_far")                         # a far shot: dull body, late answer from the buildings
	var s := _pick(name_now)
	if s == null:
		s = _pick(sfx_name)
		if s == null:
			return
	var fam: String = rule[0]
	var now := _now()
	if not _gap_ok(fam, float(rule[3]), now):
		return
	var i := _slot(_players3d, _fam_3d, _prio_3d, _t_3d, int(rule[1]), fam, int(rule[2]))
	if i < 0:
		return
	var p := _players3d[i]
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * _jitter(float(rule[4]))
	_fam_3d[i] = fam
	_prio_3d[i] = int(rule[1])
	_t_3d[i] = now
	_last_start[fam] = now
	p.play()
	_after_play(sfx_name)
	if (sfx_name == &"enemy_shot") and dist > 6.0 and dist < 70.0 and randf() < 0.3 and cam != null:
		_later(&"whizz", cam.global_position + Vector3(randf_range(-1.4, 1.4), randf_range(-0.4, 1.0), randf_range(-1.4, 1.4)), -4.0, 1.0, dist / 340.0 + 0.02)


## A bullet landing: kind is &"asphalt", &"concrete", &"glass", &"metal" or &"flesh" (alien flesh and ichor). Metal and glancing concrete may ricochet.
func impact(kind: StringName, pos: Vector3, normal := Vector3.UP) -> void:
	play_at(StringName("impact_" + String(kind)), pos, -2.0)
	var glancing := absf(normal.y) < 0.6
	if (kind == &"metal" and randf() < 0.4) or (kind == &"concrete" and glancing and randf() < 0.12):
		_later(&"ricochet", pos, -5.0, randf_range(0.9, 1.15), 0.05)


## Empty magazine: the click, once per trigger pull.
func dry_fire() -> void:
	play(&"dry_fire", -4.0)


func horn() -> void:
	if _horn_cd <= 0.0:
		_horn_cd = 0.9
		play(&"horn", -3.0)


## True while a family's voices are busy (tests, debug).
func voices_in_use() -> int:
	var n := 0
	for p in _players:
		n += 1 if p.playing else 0
	for p3 in _players3d:
		n += 1 if p3.playing else 0
	return n


func _slot(players: Array, fams: Array[String], prios: PackedInt32Array, times: PackedFloat64Array, prio: int, fam: String, cap: int) -> int:
	var free := -1
	var oldest_same := -1
	var same := 0
	var victim := -1
	for i in players.size():
		if not players[i].playing:
			if free < 0:
				free = i
			continue
		if fams[i] == fam:
			same += 1
			if oldest_same < 0 or times[i] < times[oldest_same]:
				oldest_same = i
		if prios[i] <= prio and (victim < 0 or prios[i] < prios[victim] or (prios[i] == prios[victim] and times[i] < times[victim])):
			victim = i
	if same >= cap:
		return oldest_same
	if free >= 0:
		return free
	return victim


func _gap_ok(fam: String, gap: float, now: float) -> bool:
	return gap <= 0.0 or now - float(_last_start.get(fam, -100.0)) >= gap


func _jitter(amount: float) -> float:
	return 1.0 + randf_range(-amount, amount) if amount > 0.0 else 1.0


func _now() -> float:
	return Time.get_ticks_msec() * 0.001


func _rule(sfx_name: StringName) -> Array:
	if _rules.has(sfx_name):
		return _rules[sfx_name]
	var s := String(sfx_name)
	var r: Array = DEFAULT_RULE
	for f: Array in FAMILIES:
		if s.begins_with(f[0]):
			r = f
			break
	_rules[sfx_name] = r
	return r


func _after_play(sfx_name: StringName) -> void:
	var s := String(sfx_name)
	if s.begins_with("boom") or s.begins_with("explosion") or s.begins_with("car_crash"):
		duck(&"explosion")
	elif s == "hurt":
		play(&"hero_pain", -3.0)                                  # Kestrel's own grunt on top of the hit


func _later(sfx_name: StringName, pos: Vector3, volume_db: float, pitch: float, delay: float) -> void:
	for i in PENDING:
		if _pend_t[i] < 0.0:
			_pend_t[i] = delay
			_pend_name[i] = sfx_name
			_pend_pos[i] = pos
			_pend_db[i] = volume_db
			_pend_pitch[i] = pitch
			return


## All variants of a sound (the base file plus <name>_0 .. <name>_15, wav or ogg), loaded once. Empty array when none exists.
func variants_of(sfx_name: StringName) -> Array:
	if _cache.has(sfx_name):
		return _cache[sfx_name]
	var out: Array = []
	var base := DIR + String(sfx_name)
	for ext in ["wav", "ogg"]:
		if ResourceLoader.exists(base + "." + ext):
			out.append(load(base + "." + ext))
			break
	for k in 16:
		for ext in ["wav", "ogg"]:
			var p := "%s_%d.%s" % [base, k, ext]
			if ResourceLoader.exists(p):
				out.append(load(p))
				break
	_cache[sfx_name] = out
	return out


func _pick(sfx_name: StringName) -> AudioStream:
	var v := variants_of(sfx_name)
	if v.is_empty():
		return null
	if v.size() == 1:
		return v[0]
	var last: int = int(_last_pick.get(sfx_name, -1))
	var k := randi() % v.size()
	if k == last:
		k = (k + 1) % v.size()
	_last_pick[sfx_name] = k
	return v[k]


func _get(sfx_name: StringName) -> AudioStream:
	var v := variants_of(sfx_name)
	return v[0] if not v.is_empty() else null


func _loop_stream(sfx_name: StringName) -> AudioStream:
	var s := _get(sfx_name)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s


## Loads the frequent sounds a few at a time over the next frames (no hitch at the first shot or step).
func warm() -> void:
	for n in [&"shot", &"enemy_shot", &"hit", &"hurt", &"boom", &"step_asphalt", &"step_metal", &"step_stairs", &"impact_concrete", &"impact_metal", &"impact_glass",
			&"impact_flesh", &"impact_asphalt", &"trooper_alert", &"trooper_attack", &"trooper_pain", &"trooper_death", &"reload", &"dry_fire", &"blink", &"link",
			&"superpos", &"pickup", &"whizz", &"ricochet", &"babble", &"radio_open", &"heartbeat", &"drone_alert", &"engine_low", &"engine_high", &"tyre_squeal"]:
		_warm_queue.append(n)


# ---------------------------------------------------------------------------------------------------------------------
# buses, mute, volume, ducking
# ---------------------------------------------------------------------------------------------------------------------

func set_bus_volume(bus: StringName, linear: float) -> void:
	_user_db[bus] = linear_to_db(clampf(linear, 0.0, 1.0)) if linear > 0.001 else -80.0
	_apply_bus_volumes(true)


func bus_volume(bus: StringName) -> float:
	return db_to_linear(float(_user_db.get(bus, 0.0)))


## Saved settings: {bus name: linear volume}. Unknown or missing buses keep their value.
func apply_volumes(volumes: Dictionary) -> void:
	for k in volumes:
		if StringName(k) in BUS_NAMES:
			set_bus_volume(StringName(k), float(volumes[k]))


func volumes() -> Dictionary:
	var d := {}
	for b in BUS_NAMES:
		d[String(b)] = snappedf(bus_volume(b), 0.01)
	return d


## The dB a bus is set to right now (the player's volume plus the ducks); -1000 when there is no such bus.
func effective_bus_db(bus: StringName) -> float:
	return float(_user_db.get(bus, 0.0)) + _duck_db(bus)


func _duck_db(bus: StringName) -> float:
	var d := 0.0
	for k: StringName in DUCKS:
		var depth: Dictionary = DUCKS[k]["depth"]
		if depth.has(bus):
			d += float(depth[bus]) * float(_duck_level[k])
	return d


## Sidechain-style ducking: kind is &"explosion" or &"radio"; `hold` overrides the hold time (seconds).
func duck(kind: StringName, hold := -1.0) -> void:
	if not DUCKS.has(kind):
		return
	_duck_hold[kind] = maxf(float(_duck_hold[kind]), hold if hold >= 0.0 else float(DUCKS[kind]["hold"]))


func duck_amount(kind: StringName) -> float:
	return float(_duck_level.get(kind, 0.0))


func _step_ducks(delta: float) -> void:
	for k: StringName in DUCKS:
		var cfg: Dictionary = DUCKS[k]
		var lvl: float = _duck_level[k]
		if float(_duck_hold[k]) > 0.0:
			_duck_hold[k] = float(_duck_hold[k]) - delta
			lvl = minf(1.0, lvl + delta / float(cfg["attack"]))
		else:
			lvl = maxf(0.0, lvl - delta / float(cfg["release"]))
		_duck_level[k] = lvl
	_apply_bus_volumes(false)


func _apply_bus_volumes(force: bool) -> void:
	for b in BUS_NAMES:
		var i := AudioServer.get_bus_index(b)
		if i < 0:
			continue
		var db_now := effective_bus_db(b)
		if force or absf(float(_bus_db_applied.get(b, 999.0)) - db_now) > 0.05:
			_bus_db_applied[b] = db_now
			AudioServer.set_bus_volume_db(i, maxf(db_now, -80.0))


func _bus_or_master(bus: StringName) -> StringName:
	return bus if AudioServer.get_bus_index(bus) >= 0 else &"Master"


func _find_lowpass(bus: StringName) -> AudioEffectLowPassFilter:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return null
	for k in AudioServer.get_bus_effect_count(i):
		var e := AudioServer.get_bus_effect(i, k)
		if e is AudioEffectLowPassFilter:
			return e as AudioEffectLowPassFilter
	return null


func _set_muffle(amount: float) -> void:
	for pair: Array in [[MUSIC_BUS, _lp_music], [AMBIENT_BUS, _lp_ambient]]:
		var fx: AudioEffectLowPassFilter = pair[1]
		var i := AudioServer.get_bus_index(pair[0])
		if fx == null or i < 0:
			continue
		var on := amount > 0.02
		for k in AudioServer.get_bus_effect_count(i):
			if AudioServer.get_bus_effect(i, k) == fx:
				if AudioServer.is_bus_effect_enabled(i, k) != on:
					AudioServer.set_bus_effect_enabled(i, k, on)
		fx.cutoff_hz = lerpf(20500.0, 900.0, amount)


# ---------------------------------------------------------------------------------------------------------------------
# music
# ---------------------------------------------------------------------------------------------------------------------

## Starts the adaptive music and the ambience (a no-op when already playing). `music_name` is kept for old callers: &"music_ambient" plays the single legacy loop.
func play_music(music_name: StringName = &"", volume_db := MUSIC_DB) -> void:
	_vol_music = volume_db
	_music.volume_db = volume_db
	if _music.playing:
		return
	if music_name == MUSIC_NAME or not _build_stems():
		var s := _get(MUSIC_NAME)
		if s == null:
			return
		_legacy_music = true
		_music.stream = s
	else:
		_legacy_music = false
		_music.stream = _stems
	_music.play()
	set_music_state(&"menu" if Game.state == &"menu" else music_state, true)
	start_ambience()
	warm()


func stop_music() -> void:
	_music.stop()
	_sting.stop()


func is_music_playing() -> bool:
	return _music != null and _music.playing


func _build_stems() -> bool:
	if _stems != null:
		return true
	var streams: Array[AudioStream] = []
	for s in STEMS:
		var st := _loop_stream(StringName("music_" + String(s)))
		if st == null:
			return false
		streams.append(st)
	_stems = AudioStreamSynchronized.new()
	_stems.stream_count = streams.size()
	for i in streams.size():
		_stems.set_sync_stream(i, streams[i])
		_stems.set_sync_stream_volume(i, OFF_DB)
	return true


## Switches the music to one of MUSIC_STATES (menu, explore, alert, combat, driving, death, win). `snap` jumps instead of crossfading.
func set_music_state(state: StringName, snap := false) -> void:
	if not MUSIC_STATES.has(state):
		return
	var changed := state != music_state
	var old := music_state
	music_state = state
	_state_since = _state_clock
	var tgt: Array = MUSIC_STATES[state]
	for i in STEMS.size():
		_stem_target[i] = float(tgt[i])
		if snap:
			_stem_db[i] = float(tgt[i])
	_stem_tau = 0.25 if state == &"death" else (0.45 if state in [&"combat", &"boss"] else STATE_TAU)
	_push_stem_volumes()
	if changed and not muted:
		match state:
			&"death":
				_play_sting(&"sting_death")
			&"win":
				_play_sting(&"sting_win")
			&"alert", &"combat", &"boss":
				if old in [&"explore", &"driving", &"menu"]:
					play(&"heat_up", -6.0)
			&"explore":
				if old in [&"alert", &"combat"]:
					play(&"heat_down", -8.0)


func stem_db(i: int) -> float:
	return _stem_db[i]


func stem_target_db(i: int) -> float:
	return _stem_target[i]


func _play_sting(sting_name: StringName) -> void:
	var s := _get(sting_name)
	if s != null:
		_sting.stream = s
		_sting.play()


func _push_stem_volumes() -> void:
	if _stems == null:
		return
	for i in STEMS.size():
		_stems.set_sync_stream_volume(i, maxf(_stem_db[i], OFF_DB))


func _step_music(delta: float) -> void:
	var k := 1.0 - exp(-delta / maxf(_stem_tau, 0.01))
	var moved := false
	for i in STEMS.size():
		var diff := _stem_target[i] - _stem_db[i]
		if absf(diff) > 0.01:
			_stem_db[i] += diff * k
			moved = true
		elif diff != 0.0:
			_stem_db[i] = _stem_target[i]
			moved = true
	if moved:
		_push_stem_volumes()


## What the music state should be from the game's facts (heat, the car, death, win). Heat climbs at once and falls back only after MUSIC_MIN_HOLD seconds.
func wanted_music_state() -> StringName:
	match Game.state:
		&"menu":
			return &"menu"
		&"dead":
			return &"death"
		&"win":
			return &"win"
	if boss_active:
		return &"boss"
	var heat := Game.heat
	var driving := is_instance_valid(Game.vehicles) and Game.vehicles.get(&"driven") != null
	var base: StringName = &"driving" if driving else &"explore"
	var cur := music_state
	var calm_ok := _state_clock - _state_since >= MUSIC_MIN_HOLD
	if heat >= HEAT_COMBAT:
		return &"combat"
	if cur == &"combat":
		if heat >= HEAT_COMBAT - 0.6 or not calm_ok:
			return &"combat"
	if heat >= HEAT_ALERT:
		return &"alert"
	if cur == &"alert" and (heat >= HEAT_ALERT - 0.5 or not calm_ok):
		return &"alert"
	return base


func _poll_music_state() -> void:
	if not auto_music or not is_music_playing():
		return
	if Game.state == &"paused":
		return
	var want := wanted_music_state()
	if want != music_state:
		set_music_state(want)


# ---------------------------------------------------------------------------------------------------------------------
# ambience: rain on three surfaces, traffic, wind, the city's hum, thunder, distant fights
# ---------------------------------------------------------------------------------------------------------------------

const BEDS := {
	&"rain_asphalt": -3.0, &"rain_metal": -3.0, &"rain_awning": -4.0, &"traffic_far": -2.0, &"wind": -3.0, &"city_hum": 0.0,
}


func start_ambience() -> void:
	if _ambience_on:
		return
	var any := false
	for bed: StringName in _amb:
		var p: AudioStreamPlayer = _amb[bed]
		if p.stream == null:
			p.stream = _loop_stream(bed)
		if p.stream != null:
			p.play()
			any = true
	var ts := _loop_stream(&"traffic_loop")
	for e in _emitters:
		if e.stream == null and ts != null:
			e.stream = ts
	var hs := _loop_stream(&"drone_hum")
	for h in _hum_emitters:
		if h.stream == null and hs != null:
			h.stream = hs
	_ambience_on = any
	_thunder_in = randf_range(8.0, 25.0)
	_distant_in = randf_range(30.0, 80.0)


func stop_ambience() -> void:
	_ambience_on = false
	for bed: StringName in _amb:
		(_amb[bed] as AudioStreamPlayer).stop()
	for e in _emitters:
		e.stop()
		e.volume_db = OFF_DB


func is_ambience_on() -> bool:
	return _ambience_on


## Which surface the rain falls on around the listener: &"asphalt" (street), &"metal" (roofs, the inside of a car), &"awning". Normally decided from the hero's position.
func set_rain_surface(surface: StringName) -> void:
	_rain_surface = surface


func _rain_weights(surface: StringName) -> Array:
	match surface:
		&"metal":
			return [0.3, 1.0, 0.0]
		&"awning":
			return [0.25, 0.1, 1.0]
		_:
			return [1.0, 0.0, 0.3]


func _step_ambience(delta: float) -> void:
	if not _ambience_on:
		return
	var rain := 0.7
	if is_instance_valid(Game.atmosphere):
		rain = float(Game.atmosphere.get(&"rain_now"))
	var playing := Game.is_playing() or Game.state == &"paused" or Game.state == &"menu" or Game.state == &"cutscene"
	var w := _rain_weights(_rain_surface)
	var k := 1.0 - exp(-delta / 1.2)
	for bed: StringName in _amb:
		var goal := 0.0
		if playing:
			match bed:
				&"rain_asphalt":
					goal = float(w[0]) * rain
				&"rain_metal":
					goal = float(w[1]) * rain
				&"rain_awning":
					goal = float(w[2]) * rain
				&"traffic_far":
					goal = 0.75
				&"wind":
					goal = 0.4 + 0.5 * rain
				_:
					goal = 0.6
		var v: float = lerpf(float(_amb_vol[bed]), goal, k)
		_amb_vol[bed] = v
		(_amb[bed] as AudioStreamPlayer).volume_db = OFF_DB if v < 0.003 else float(BEDS[bed]) + linear_to_db(v)
	if not Game.is_playing():
		return
	_thunder_in -= delta
	if _thunder_in <= 0.0:
		_thunder_in = randf_range(18.0, 55.0)
		if rain > 0.3:
			_play_oneshot(&"thunder", -3.0 + 3.0 * rain)
			if randf() < 0.4:
				_later(&"distant_boom", Vector3.ZERO, -16.0, 1.0, randf_range(1.5, 4.0))
	_distant_in -= delta
	if _distant_in <= 0.0:
		_distant_in = randf_range(35.0, 110.0)
		_play_oneshot(&"distant_gunfire" if randf() < 0.6 else &"distant_boom", -10.0)


func _play_oneshot(sfx_name: StringName, volume_db: float) -> void:
	if muted:
		return
	var s := _pick(sfx_name)
	if s == null:
		return
	for p in _oneshots:
		if not p.playing:
			p.stream = s
			p.volume_db = volume_db
			p.pitch_scale = _jitter(0.04)
			p.play()
			return


## The traffic hum follows the three nearest moving cars that are not the hero's.
func _poll_emitters() -> void:
	if not is_instance_valid(Game.vehicles) or not is_instance_valid(Game.player):
		return
	var list: Array = Game.vehicles.get(&"list")
	var pp: Vector3 = Game.player.global_position
	var best: Array = [null, null, null]
	var bd: Array = [1e9, 1e9, 1e9]
	for v in list:
		if not is_instance_valid(v) or not v.active or v == _driven or absf(float(v.speed)) < 2.5:
			continue
		var d := (v as Node3D).global_position.distance_to(pp)
		if d > 60.0:
			continue
		for s in 3:
			if d < float(bd[s]):
				for t in range(2, s, -1):
					best[t] = best[t - 1]
					bd[t] = bd[t - 1]
				best[s] = v
				bd[s] = d
				break
	for s in 3:
		_emitter_car[s] = best[s]


func _step_emitters() -> void:
	for s in _emitters.size():
		var e := _emitters[s]
		var car = _emitter_car[s]
		if car == null or not is_instance_valid(car) or muted or not Game.is_playing():
			if e.playing:
				e.volume_db = OFF_DB
				e.stop()
			continue
		e.global_position = (car as Node3D).global_position
		var sp := clampf(absf(float(car.speed)) / TOP_SPEED, 0.0, 1.0)
		e.pitch_scale = 0.75 + 0.9 * sp
		e.volume_db = -14.0 + 7.0 * sp
		if not e.playing and e.stream != null:
			e.play()


# ---------------------------------------------------------------------------------------------------------------------
# loops on the SFX bus: quantum drones, the player's engine and tyres
# ---------------------------------------------------------------------------------------------------------------------

func _loop_player(loop_name: StringName) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = _loops.get(loop_name)
	if p != null and p.stream == null:
		p.stream = _loop_stream(loop_name)
	return p if p != null and p.stream != null else null


## Fades a loop toward `target_db` (OFF_DB = stop). Starts it when needed.
func _drive_loop(loop_name: StringName, target_db: float, delta: float, pitch := 1.0, rate := 40.0) -> void:
	var p: AudioStreamPlayer = _loops.get(loop_name)
	if p == null or (not p.playing and target_db <= -50.0):
		return
	if p.stream == null and _loop_player(loop_name) == null:
		return
	var cur := p.volume_db if p.playing else OFF_DB
	cur = move_toward(cur, target_db, rate * delta)
	if cur <= -50.0 and target_db <= -50.0:
		if p.playing:
			p.stop()
		return
	if not p.playing:
		p.play()
	p.volume_db = cur
	p.pitch_scale = pitch


func _silence_loops() -> void:
	for n in _loops:
		(_loops[n] as AudioStreamPlayer).stop()
		(_loops[n] as AudioStreamPlayer).volume_db = OFF_DB
	for e in _emitters:
		e.stop()


func _step_vehicle(delta: float) -> void:
	var v = null
	if is_instance_valid(Game.vehicles):
		v = Game.vehicles.get(&"driven")
		if v != null and not is_instance_valid(v):
			v = null
	if v != _driven:
		_driven = v
		_prev_speed = 0.0 if v == null else float(v.speed)
		if v != null:
			play(&"engine_start", -6.0)
			_rpm = 0.05
	_crash_cd -= delta
	_horn_cd -= delta
	if v == null or not Game.is_playing() or muted:
		_drive_loop(&"engine_low", OFF_DB, delta, 1.0, 60.0)
		_drive_loop(&"engine_high", OFF_DB, delta, 1.0, 60.0)
		_drive_loop(&"tyre_squeal", OFF_DB, delta, 1.0, 80.0)
		return
	var sp: float = float(v.speed)
	var asp := absf(sp)
	var r := clampf(asp / TOP_SPEED, 0.0, 1.0)
	var gear := mini(int(r * 4.0), 3)
	var rpm_goal := 0.22 + 0.78 * (r * 4.0 - float(gear)) if r > 0.02 else 0.05
	if Input.is_action_pressed(&"move_forward") and r < 0.05:
		rpm_goal = 0.35
	_rpm = lerpf(_rpm, rpm_goal, 1.0 - exp(-delta * 6.0))
	var blend := smoothstep(0.35, 0.7, _rpm)
	_drive_loop(&"engine_low", -8.0 + linear_to_db(maxf(1.0 - blend, 0.001)), delta, 0.75 + _rpm * 0.7, 60.0)
	_drive_loop(&"engine_high", -9.0 + linear_to_db(maxf(blend, 0.001)), delta, 0.7 + _rpm * 0.6, 60.0)
	var slip := absf(float(v.slip))
	var squeal := clampf((slip - 3.0) / 5.0, 0.0, 1.0) * clampf((asp - 6.0) / 10.0, 0.0, 1.0)
	_drive_loop(&"tyre_squeal", -22.0 + 22.0 * squeal if squeal > 0.02 else OFF_DB, delta, 0.85 + 0.4 * r, 80.0)
	var drop := _prev_speed - sp
	if drop > 7.0 and _crash_cd <= 0.0:
		_crash_cd = 0.5
		play_at(&"car_crash" if drop > 11.0 else &"car_bump", (v as Node3D).global_position, -2.0 if drop > 11.0 else -5.0)
	_prev_speed = sp
	if InputMap.has_action(&"horn") and Input.is_action_just_pressed(&"horn"):
		horn()


func _step_quantum(delta: float) -> void:
	var q: Node = null
	if Game.is_playing() and is_instance_valid(Game.player) and not muted:
		q = Game.player.get(&"quantum")
	var super_on := q != null and is_instance_valid(q.get(&"clone"))
	var lk = q.get(&"links") if q != null else null
	var links_on: bool = lk is Array and (lk as Array).size() > 0
	_drive_loop(&"superpos_loop", -6.0 if super_on else OFF_DB, delta, 1.0, 30.0)
	_drive_loop(&"entangle_loop", -6.0 if links_on else OFF_DB, delta, 1.0, 30.0)


# ---------------------------------------------------------------------------------------------------------------------
# hero: footsteps, heartbeat and breath at low health
# ---------------------------------------------------------------------------------------------------------------------

func _step_hero(delta: float) -> void:
	var pv = Game.player
	var p: Node3D = pv as Node3D if is_instance_valid(pv) else null
	if not Game.is_playing() or p == null or muted:
		_muffle_target = 0.0
		_last_footfalls = -1 if not Game.is_playing() else _last_footfalls
		return
	# footsteps: one per foot touchdown of the locomotion
	var loco = null
	var body = p.get(&"body")
	if body != null:
		loco = body.get(&"loco")
	if loco != null:
		var f: int = int(loco.footfalls)
		if _last_footfalls < 0 or f < _last_footfalls:
			_last_footfalls = f
		elif f > _last_footfalls:
			_last_footfalls = f
			_footstep(p)
	# jump effort and landing (air_time: seconds since the feet last touched the ground)
	var at = p.get(&"air_time")
	var air := float(at) if at != null else 0.0
	if _was_air > 0.3 and air <= 0.0:
		var surf := surface_under(p.global_position, false)
		play(StringName("land_" + ("metal" if surf == &"metal" else "asphalt")), -9.0 + minf(_was_air, 1.2) * 6.0)
		if _was_air > 0.9:
			play(&"hero_effort", -6.0)
	elif air > 0.0 and _was_air <= 0.0 and Vector3(p.get(&"velocity")).y > 3.0:
		play(&"hero_effort", -8.0)
	_was_air = air
	# low health: a heartbeat that speeds up and a laboured breath, the music and ambience muffle
	var mh = p.get(&"max_hp")
	var hpv = p.get(&"hp")
	if mh == null or hpv == null:
		_heart_t = 0.0
		_muffle_target = 0.0
		return
	var max_hp := maxf(float(mh), 1.0)
	var frac := clampf(float(hpv) / max_hp, 0.0, 1.0)
	if frac < 0.35 and frac > 0.0:
		var need := 1.0 - frac / 0.35
		_heart_t -= delta
		if _heart_t <= 0.0:
			_heart_t = lerpf(1.0, 0.55, need)
			play(&"heartbeat", -9.0 + 5.0 * need)
		_breath_t -= delta
		if _breath_t <= 0.0:
			_breath_t = lerpf(1.6, 0.85, need)
			play(&"breath_in" if _breath_in else &"breath_out", -6.0 + 4.0 * need)
			_breath_in = not _breath_in
		_muffle_target = clampf(need * 0.8, 0.0, 0.8)
	else:
		_heart_t = 0.0
		_breath_t = 0.4
		_muffle_target = 0.0
	if p.get(&"vehicle") != null:
		_muffle_target = maxf(_muffle_target, 0.3)


## The surface under the hero's feet from where he stands (the city is one static body): the street is wet asphalt, a curb or ledge rings like stairs, roofs are metal.
func surface_under(pos: Vector3, climbing: bool) -> StringName:
	if pos.y > 0.5:
		return &"metal"
	if climbing or pos.y > 0.12:
		return &"stairs"
	return &"asphalt"


func _footstep(p: Node3D) -> void:
	var vel: Vector3 = p.get(&"velocity")
	var spd := Vector2(vel.x, vel.z).length()
	if spd < 0.3 or p.get(&"vehicle") != null:
		return
	var surf := surface_under(p.global_position, vel.y > 1.2)
	_rain_surface = &"metal" if surf == &"metal" else &"asphalt"
	var loud := clampf(spd / 6.2, 0.0, 1.3)
	play(StringName("step_" + String(surf)), -9.0 + 9.0 * loud, 0.95 + 0.1 * loud)


# ---------------------------------------------------------------------------------------------------------------------
# enemies: voices of the Vael troopers, drone cues, a hum that follows the nearest drones (polled 10 times a second from EnemyManager.list, no edits in the enemy code)
# ---------------------------------------------------------------------------------------------------------------------

func _poll_enemies() -> void:
	if not is_instance_valid(Game.enemies) or not Game.is_playing():
		return
	var list = Game.enemies.get(&"list")
	if list == null:
		return
	var pp := Vector3.ZERO
	var have_pp := is_instance_valid(Game.player)
	if have_pp:
		pp = (Game.player as Node3D).global_position
	var n_hum := 0
	for e in list:
		if not is_instance_valid(e):
			continue
		var id: int = e.get_instance_id()
		var cur := Vector4(1.0 if e.aware else 0.0, float(e.hp), 1.0 if e.dead else 0.0, float(e.threat_charge()))
		var prev: Vector4 = _en_state.get(id, cur)
		_en_state[id] = cur
		var trooper: bool = e.type == &"operative"
		var pos: Vector3 = (e as Node3D).global_position + Vector3(0.0, 1.2, 0.0)
		if cur.z > 0.5:
			if prev.z < 0.5:
				play_at(&"trooper_death" if trooper else &"drone_death", pos, -1.0)
			continue
		if cur.x > 0.5 and prev.x < 0.5:
			play_at(&"trooper_alert" if trooper else &"drone_alert", pos, -2.0)
		if trooper and cur.y < prev.y - 0.5:
			play_at(&"trooper_pain", pos, -2.0)
		if cur.w >= 0.05 and prev.w < 0.05:                       # a telegraph began: the rifle or the drone's muzzle charges
			if trooper:
				if randf() < 0.5:
					play_at(&"trooper_attack", pos, -3.0)
			else:
				play_at(&"drone_charge", pos, -6.0)
		if not trooper and n_hum < _hum_emitters.size() and have_pp and pos.distance_to(pp) < 45.0:
			_hum_target[n_hum] = e
			n_hum += 1
	for k in range(n_hum, _hum_emitters.size()):
		_hum_target[k] = null


func _step_hum() -> void:
	for k in _hum_emitters.size():
		var em := _hum_emitters[k]
		var tgt = _hum_target[k]
		if tgt == null or not is_instance_valid(tgt) or muted or not Game.is_playing() or not _ambience_on:
			if em.playing:
				em.stop()
			continue
		em.global_position = (tgt as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
		em.pitch_scale = 0.8 if (tgt.type == &"heavy") else (1.25 if tgt.type == &"striker" else 1.0)
		em.volume_db = -12.0
		if not em.playing and em.stream != null:
			em.play()


# ---------------------------------------------------------------------------------------------------------------------
# radio: squelch, a speech-like babble tied to the typed text, ducking under it
# ---------------------------------------------------------------------------------------------------------------------

## A radio line starts typing (ORACLE, Kestrel, the Vael broadcast): the open squelch and the duck.
func radio_begin() -> void:
	_radio_active = true
	_radio_seen = 0
	_radio_pending = 0
	_radio_idle = 0.0
	_radio_gap = 0.0
	play(&"radio_open", -6.0)
	duck(&"radio", 0.6)


## Call while the text types: `typed` characters of `text` are visible. One syllable of babble is queued per vowel of the new characters, pitched by the letter, and the
## consonant-only stretches add a crackle. Calling it again every frame is fine.
func radio_type(text: String, typed: int) -> void:
	if not _radio_active:
		radio_begin()
	_radio_idle = 0.0
	duck(&"radio", 0.45)
	var to := mini(typed, text.length())
	while _radio_seen < to:
		var c := text.unicode_at(_radio_seen)
		var ch := String.chr(c).to_lower()
		_radio_seen += 1
		if ch in "aeiouy":
			_radio_pending = mini(_radio_pending + 1, 6)
			_radio_pitch = 0.85 + 0.09 * float("aeiouy".find(ch)) + 0.04 * float(c % 3)
		elif ch in ".!?":
			_radio_pending = mini(_radio_pending + 1, 6)
			_radio_pitch = 0.8
	_radio_len = text.length()


func radio_end() -> void:
	if _radio_active:
		_radio_active = false
		play(&"radio_close", -8.0)


func is_radio_active() -> bool:
	return _radio_active


func _step_radio(delta: float) -> void:
	if not _radio_active:
		return
	_radio_idle += delta
	if _radio_idle > 0.35 and _radio_pending == 0:
		radio_end()
		return
	_radio_gap -= delta
	if _radio_pending > 0 and _radio_gap <= 0.0 and not muted:
		_radio_pending -= 1
		_radio_gap = 0.065
		var s := _pick(&"babble")
		if s != null:
			for v in _voices:
				if not v.playing:
					v.stream = s
					v.pitch_scale = _radio_pitch * _jitter(0.06)
					v.volume_db = -2.0
					v.play()
					break
		if randf() < 0.08:
			play(&"radio_glitch", -6.0)


# ---------------------------------------------------------------------------------------------------------------------
# frame loop and lifecycle
# ---------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_state_clock += delta
	_step_ducks(delta)
	if _stems != null:
		_step_music(delta)
	_state_poll -= delta
	if _state_poll <= 0.0:
		_state_poll = 0.2
		_poll_music_state()
	for i in PENDING:
		if _pend_t[i] >= 0.0:
			_pend_t[i] -= delta
			if _pend_t[i] < 0.0:
				var n := _pend_name[i]
				if n == &"distant_boom":
					_play_oneshot(n, _pend_db[i])
				else:
					play_at(n, _pend_pos[i], _pend_db[i], _pend_pitch[i])
	for _k in mini(_warm_queue.size(), 4):
		variants_of(_warm_queue.pop_back())
	_step_radio(delta)
	_step_ambience(delta)
	_step_vehicle(delta)
	_step_quantum(delta)
	_step_hero(delta)
	_muffle = lerpf(_muffle, _muffle_target, 1.0 - exp(-delta * 2.5))
	if absf(_muffle - float(_bus_db_applied.get(&"_muffle", -1.0))) > 0.01:
		_bus_db_applied[&"_muffle"] = _muffle
		_set_muffle(_muffle)
	_emit_poll -= delta
	if _emit_poll <= 0.0:
		_emit_poll = 0.5
		if _ambience_on and Game.is_playing():
			_poll_emitters()
	_en_poll -= delta
	if _en_poll <= 0.0:
		_en_poll = 0.1
		_poll_enemies()
	if _ambience_on:
		_step_emitters()
		_step_hum()


func _on_state(state: StringName) -> void:
	if state == &"paused":
		play(&"ui_pause", -6.0)
	elif _last_game_state == &"paused" and state == &"play":
		play(&"ui_resume", -6.0)
	_last_game_state = state
	if state == &"dead" or state == &"win":
		_silence_gameplay_loops()
	if auto_music and is_music_playing() and state != &"paused":
		set_music_state(wanted_music_state())


func _on_player_died() -> void:
	_silence_gameplay_loops()
	if is_music_playing() and auto_music:
		set_music_state(&"death")
	play(&"hero_death", -2.0)


func _silence_gameplay_loops() -> void:
	for n in _loops:
		(_loops[n] as AudioStreamPlayer).stop()
	for e in _emitters:
		e.stop()
	for h in _hum_emitters:
		h.stop()
	_heart_t = 0.0
	_muffle_target = 0.0


## Back to a clean slate: every timer, loop and delayed sound of a run (new game, respawn, next sector).
func reset_world() -> void:
	_silence_gameplay_loops()
	for i in PENDING:
		_pend_t[i] = -1.0
	_radio_active = false
	_radio_pending = 0
	_last_footfalls = -1
	_was_air = 0.0
	_prev_speed = 0.0
	_driven = null
	_rpm = 0.1
	_crash_cd = 0.0
	for k: StringName in DUCKS:
		_duck_hold[k] = 0.0
		_duck_level[k] = 0.0
	_sting.stop()
	_emitter_car = [null, null, null]
	_hum_target = [null, null]
	_en_state.clear()
	if auto_music and is_music_playing():
		set_music_state(&"explore" if Game.state != &"menu" else &"menu")
