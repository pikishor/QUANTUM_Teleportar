class_name CarRadio
extends Node
## The car radio: four synthesised stations that play while the player drives. A child of VehicleManager (`Game.vehicles.radio`).
##
## Switch: the `radio_next` action (key V, registered here when missing) cycles OFF -> NEON FM -> VAEL STATIC -> RIFT CLUB -> LOFI ORBIT -> OFF while driving; a touch button calls
## `Game.vehicles.radio.cycle()` the same way. The stations are rendered once, lazily, on a worker thread (a few seconds of 12 kHz mono, looped), so there is no
## hitch when the player first tunes in; nothing is shipped as a file and nothing is allocated per frame. Audio goes through the existing Music bus of `Sfx`
## (volume, mute and the in-car low-pass of Sfx apply); the adaptive score is stopped while the radio is audible and restarted when it is not.
## It is audible only while the player drives and the game is playing (paused: the stream pauses).

signal changed(on: bool, station: int)

const ACTION := &"radio_next"
const KEY := KEY_V
const RATE := 12000
const STATIONS: Array[Dictionary] = [
	{"name": "NEON FM", "bpm": 104.0, "bars": 4},
	{"name": "VAEL STATIC", "bpm": 70.0, "bars": 2},
	{"name": "RIFT CLUB", "bpm": 126.0, "bars": 4},
	{"name": "LOFI ORBIT", "bpm": 76.0, "bars": 4},
]
const VOLUME_DB := -7.0

var on := false
var station := 0
var _player: AudioStreamPlayer
var _streams: Array = [null, null, null, null]
var _tasks: Array[int] = [-1, -1, -1, -1]
var _data: Array = [null, null, null, null]
var _stopped_music := false
var _audible := false


func _ready() -> void:
	name = "Radio"
	ensure_action()
	_player = AudioStreamPlayer.new()
	_player.name = "RadioPlayer"
	_player.bus = Sfx.MUSIC_BUS if AudioServer.get_bus_index(Sfx.MUSIC_BUS) >= 0 else &"Master"
	_player.volume_db = VOLUME_DB
	add_child(_player)


func _exit_tree() -> void:
	for i in STATIONS.size():
		if _tasks[i] >= 0:
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks[i] = -1
	_set_audible(false)


static func ensure_action() -> void:
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY
		InputMap.action_add_event(ACTION, ev)


static func station_name(i: int) -> String:
	return String(STATIONS[clampi(i, 0, STATIONS.size() - 1)]["name"])


## OFF -> station 0 -> 1 -> 2 -> 3 -> OFF. Returns true when the radio is on afterwards.
func cycle() -> bool:
	if not on:
		set_station(0)
	elif station < STATIONS.size() - 1:
		set_station(station + 1)
	else:
		turn_off()
	return on


func set_station(i: int) -> void:
	station = clampi(i, 0, STATIONS.size() - 1)
	on = true
	_request(station)
	_apply_stream()
	Game.say("RADIO · %s" % station_name(station), 1.5)
	changed.emit(on, station)


func turn_off() -> void:
	on = false
	_player.stop()
	_set_audible(false)
	Game.say("RADIO OFF", 1.0)
	changed.emit(on, station)


## True while a station is actually sounding (on, rendered, driving, playing).
func is_audible() -> bool:
	return _audible


func is_ready(i: int) -> bool:
	return _streams[i] != null


func _process(_delta: float) -> void:
	_collect()
	var mgr := get_parent() as VehicleManager
	var driving := mgr != null and mgr.driven != null and is_instance_valid(mgr.driven)
	var want := on and driving and not Sfx.muted and _streams[station] != null
	if want and not _player.playing:
		_player.stream = _streams[station]
		_player.play()
	_player.stream_paused = not Game.is_playing()
	_set_audible(want and Game.is_playing())
	if not driving and _player.playing:
		_player.stop()


## Called by VehicleManager's physics tick while playing (like `interact`): the key cycles the stations while driving.
func poll_input() -> void:
	var mgr := get_parent() as VehicleManager
	if mgr != null and mgr.driven != null and Input.is_action_just_pressed(ACTION):
		cycle()


func _apply_stream() -> void:
	if _streams[station] == null:
		_player.stop()                            # the station is still being rendered: _process starts it when it is ready
		return
	_player.stream = _streams[station]
	if not _player.playing:
		_player.play()


func _set_audible(v: bool) -> void:
	if v == _audible:
		return
	_audible = v
	if v:
		if Sfx.is_music_playing():
			Sfx.stop_music()
			_stopped_music = true
	elif _stopped_music:
		_stopped_music = false
		if Game.state != &"menu" and Game.state != &"dead":
			Sfx.play_music()


# --- rendering ----------------------------------------------------------------------------------------------------------------

func _request(i: int) -> void:
	if _streams[i] != null or _tasks[i] >= 0:
		return
	_tasks[i] = WorkerThreadPool.add_task(_render_task.bind(i), false, "radio station %d" % i)


func _render_task(i: int) -> void:
	_data[i] = render(i)


func _collect() -> void:
	for i in STATIONS.size():
		if _tasks[i] >= 0 and WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks[i] = -1
			_streams[i] = make_stream(_data[i] as PackedByteArray)
			_data[i] = null


## Render every station now (tests, a warm-up); the result is cached like the lazy path.
func render_all_now() -> void:
	for i in STATIONS.size():
		if _tasks[i] >= 0:
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks[i] = -1
			_streams[i] = make_stream(_data[i] as PackedByteArray)
			_data[i] = null
		if _streams[i] == null:
			_streams[i] = make_stream(render(i))


static func make_stream(bytes: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = bytes.size() / 2
	return w


## 16-bit mono PCM of station `i` (seamless loop). Pure function of `i`: safe on a worker thread.
static func render(i: int) -> PackedByteArray:
	var cfg: Dictionary = STATIONS[clampi(i, 0, STATIONS.size() - 1)]
	var beat := 60.0 / float(cfg["bpm"])
	var n := int(beat * 4.0 * float(cfg["bars"]) * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + i
	match i:
		0:
			_neon(buf, beat, int(cfg["bars"]), rng)
		1:
			_static(buf, beat, int(cfg["bars"]), rng)
		2:
			_club(buf, beat, int(cfg["bars"]), rng)
		_:
			_lofi(buf, beat, int(cfg["bars"]), rng)
	return _to_pcm(buf)


static func _to_pcm(buf: PackedFloat32Array) -> PackedByteArray:
	var peak := 0.001
	for v in buf:
		peak = maxf(peak, absf(v))
	var g := 0.85 / peak
	var out := PackedByteArray()
	out.resize(buf.size() * 2)
	var lp := 0.0
	for k in buf.size():
		lp += (buf[k] * g - lp) * 0.62                   # a touch of band-limiting: it is a car radio
		out.encode_s16(k * 2, int(clampf(lp, -1.0, 1.0) * 30000.0))
	return out


static func _hz(semi: float) -> float:
	return 440.0 * pow(2.0, (semi - 69.0) / 12.0)


## One voice: `wave` 0 sine, 1 saw, 2 square, 3 triangle; exponential decay `decay` (1/s) with a 4 ms attack; wraps round the loop end.
static func _note(buf: PackedFloat32Array, t0: float, dur: float, freq: float, wave: int, amp: float, decay: float, vib := 0.0) -> void:
	var n := buf.size()
	var s0 := int(t0 * RATE)
	var count := int(dur * RATE)
	var ph := 0.0
	var inv := freq / float(RATE)
	for k in count:
		var t := float(k) / float(RATE)
		var env := minf(1.0, t / 0.004) * exp(-decay * t) * minf(1.0, (dur - t) / 0.02)
		ph += inv * (1.0 + vib * sin(t * 38.0))
		var f := ph - floorf(ph)
		var v: float
		match wave:
			0:
				v = sin(ph * TAU)
			1:
				v = 2.0 * f - 1.0
			2:
				v = 1.0 if f < 0.5 else -1.0
			_:
				v = 4.0 * absf(f - 0.5) - 1.0
		var idx := (s0 + k) % n
		buf[idx] += v * env * amp


static func _kick(buf: PackedFloat32Array, t0: float, amp: float) -> void:
	var n := buf.size()
	var s0 := int(t0 * RATE)
	var ph := 0.0
	for k in int(0.22 * RATE):
		var t := float(k) / float(RATE)
		ph += (46.0 + 110.0 * exp(-t * 28.0)) / float(RATE)
		buf[(s0 + k) % n] += sin(ph * TAU) * exp(-t * 11.0) * amp


static func _noise(buf: PackedFloat32Array, t0: float, dur: float, amp: float, decay: float, rng: RandomNumberGenerator, bright := 1.0) -> void:
	var n := buf.size()
	var s0 := int(t0 * RATE)
	var last := 0.0
	for k in int(dur * RATE):
		var t := float(k) / float(RATE)
		var w := rng.randf_range(-1.0, 1.0)
		last = lerpf(last, w, bright)                   # bright 1 = white, lower = duller
		buf[(s0 + k) % n] += last * exp(-decay * t) * amp


## NEON FM: synthwave in A minor, 4 bars Am F C G: saw bass pulse, triangle arpeggio, kick, snare, hats.
static func _neon(buf: PackedFloat32Array, beat: float, bars: int, rng: RandomNumberGenerator) -> void:
	var roots := [57, 53, 48, 55]
	var chords := [[0, 3, 7], [0, 4, 7], [0, 4, 7], [0, 4, 7]]
	for b in bars:
		var bt := float(b) * 4.0 * beat
		var root: int = roots[b % 4]
		var ch: Array = chords[b % 4]
		for q in 8:                                         # eighth-note bass
			_note(buf, bt + float(q) * beat * 0.5, beat * 0.46, _hz(root - 12), 1, 0.30, 5.0)
		for q in 16:                                        # sixteenth arpeggio, up and down
			var step: int = [0, 1, 2, 1][q % 4]
			_note(buf, bt + float(q) * beat * 0.25, beat * 0.2, _hz(root + 12 + int(ch[step % 3])), 3, 0.16, 9.0, 0.002)
		for q in 4:
			_kick(buf, bt + float(q) * beat, 0.65)
			_noise(buf, bt + (float(q) + 0.5) * beat, 0.04, 0.12, 60.0, rng)
		_noise(buf, bt + beat, 0.16, 0.34, 22.0, rng, 0.7)
		_noise(buf, bt + 3.0 * beat, 0.16, 0.34, 22.0, rng, 0.7)
		_note(buf, bt, beat * 4.0, _hz(root + 24 + int(ch[2])), 0, 0.07, 0.6, 0.004)       # a held pad note on top


## VAEL STATIC: a hive drone (low detuned sines, snapped to whole cycles so the loop is seamless), clicks and crackle, a slow whistle.
static func _static(buf: PackedFloat32Array, beat: float, bars: int, rng: RandomNumberGenerator) -> void:
	var n := buf.size()
	var secs := float(n) / float(RATE)
	for f0 in [55.0, 82.5, 110.0, 164.0]:
		var f: float = round(f0 * secs) / secs                # whole cycles in the loop
		var wob: float = round(0.3 * secs) / secs
		for k in n:
			var t := float(k) / float(RATE)
			buf[k] += sin(TAU * f * t + 1.6 * sin(TAU * wob * t)) * (0.22 if f0 < 100.0 else 0.1)
	var whistle: float = round(880.0 * secs) / secs
	var slow: float = round(1.0 * secs) / secs
	for k in n:                                                 # a whistle whose pitch breathes once per loop
		var t := float(k) / float(RATE)
		buf[k] += sin(TAU * whistle * t + 40.0 * sin(TAU * slow * t / 2.0)) * 0.035 * (0.5 + 0.5 * sin(TAU * slow * t))
	for c in 14:                                                # clicks of the hive (short band noise and ticks)
		var t0 := rng.randf() * secs
		_noise(buf, t0, 0.03, rng.randf_range(0.12, 0.3), 120.0, rng, rng.randf_range(0.2, 1.0))
		if rng.randf() < 0.5:
			_note(buf, t0, 0.08, rng.randf_range(900.0, 2400.0), 2, 0.05, 40.0)
	_noise(buf, 0.0, secs, 0.025, 0.0, rng, 0.35)             # a bed of static


## RIFT CLUB: four on the floor, off-beat hats, claps, an acid saw line that slides between A minor notes.
static func _club(buf: PackedFloat32Array, beat: float, bars: int, rng: RandomNumberGenerator) -> void:
	var line := [33, 33, 45, 33, 36, 33, 40, 33, 33, 45, 33, 36, 31, 33, 43, 40]
	for b in bars:
		var bt := float(b) * 4.0 * beat
		for q in 4:
			_kick(buf, bt + float(q) * beat, 0.75)
			_noise(buf, bt + (float(q) + 0.5) * beat, 0.09, 0.2, 38.0, rng, 0.9)           # open hat on the off-beat
		for q in 16:
			var semi: int = line[(q + (b % 2) * 3) % 16]
			_note(buf, bt + float(q) * beat * 0.25, beat * 0.22, _hz(semi), 1, 0.3, 10.0 + float(q % 4) * 3.0)
		_noise(buf, bt + beat, 0.12, 0.3, 28.0, rng, 0.6)
		_noise(buf, bt + 3.0 * beat, 0.12, 0.3, 28.0, rng, 0.6)
		if b % 2 == 1:
			_note(buf, bt + 2.0 * beat, beat * 2.0, _hz(69), 2, 0.05, 1.5, 0.003)           # a stab pad every other bar


## LOFI ORBIT: slow dusty keys (soft sine / triangle seventh chords Am7 Fmaj7 Cmaj7 G6), a lazy kick and snare, soft brushed hats and a high bell every other bar.
static func _lofi(buf: PackedFloat32Array, beat: float, bars: int, rng: RandomNumberGenerator) -> void:
	var roots := [57, 53, 48, 55]
	var chords := [[0, 3, 7, 10], [0, 4, 7, 11], [0, 4, 7, 11], [0, 4, 7, 9]]
	for b in bars:
		var bt := float(b) * 4.0 * beat
		var root: int = roots[b % 4]
		var ch: Array = chords[b % 4]
		for n in ch:                                         # the chord, held for the bar, a hair out of tune per voice
			_note(buf, bt, beat * 3.8, _hz(root + int(n)), 3, 0.09, 0.7, 0.003)
		_note(buf, bt, beat * 3.6, _hz(root - 12), 0, 0.26, 0.9)
		_kick(buf, bt, 0.5)
		_kick(buf, bt + 2.5 * beat, 0.4)
		_noise(buf, bt + beat, 0.14, 0.2, 26.0, rng, 0.45)
		_noise(buf, bt + 3.0 * beat, 0.14, 0.2, 26.0, rng, 0.45)
		for q in 8:
			_noise(buf, bt + float(q) * beat * 0.5, 0.03, 0.05, 90.0, rng, 1.0)
		if b % 2 == 0:
			_note(buf, bt + 1.5 * beat, beat * 1.2, _hz(root + 24 + int(ch[3 % ch.size()])), 0, 0.06, 3.0, 0.002)
