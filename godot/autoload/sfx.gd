extends Node
## Sound effects and music. Drop WAV files in res://assets/audio/<name>.wav and play them by name.
## Unknown names are silently ignored, so code can call Sfx.play() before the audio exists.
##
## Buses (assets/audio/default_bus_layout.tres, registered in project.godot): Master (with a limiter, so a firefight never clips), SFX and Music. Every effect
## plays on SFX and the music on Music; without the layout (a stripped project, a test fixture) everything falls back to Master.
## Music: play_music() loops res://assets/audio/music_ambient.wav (the file carries its own loop points) on its own player, 9 dB below the effects.
## main.gd starts it for a real run; tools, tests and bots (Game.autostart) stay silent.

const DIR := "res://assets/audio/"
const POOL := 16                 ## sustained rifle fire alone keeps about 8 voices busy (a shot rings for 0.9 s at 9 rounds per second)
const SFX_BUS := &"SFX"
const MUSIC_BUS := &"Music"
const MUSIC_NAME := &"music_ambient"
const MUSIC_DB := -9.0

var _cache := {}
var _players: Array[AudioStreamPlayer] = []
var _players3d: Array[AudioStreamPlayer3D] = []
var _music: AudioStreamPlayer
var _pi := 0
var _p3 := 0
## Mutes everything, music included (the settings screen toggles it).
var muted := false:
	set(v):
		muted = v
		if _music != null:
			_music.stream_paused = v


func _ready() -> void:
	var sfx_bus: StringName = _bus_or_master(SFX_BUS)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = sfx_bus
		add_child(p)
		_players.append(p)
	for i in 8:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 12.0
		p3.bus = sfx_bus
		add_child(p3)
		_players3d.append(p3)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = _bus_or_master(MUSIC_BUS)
	_music.volume_db = MUSIC_DB
	_music.stream_paused = muted
	add_child(_music)


func play(sfx_name: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	var s := _get(sfx_name)
	if s == null or muted:
		return
	var p := _players[_pi]
	_pi = (_pi + 1) % _players.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func play_at(sfx_name: StringName, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var s := _get(sfx_name)
	if s == null or muted:
		return
	var p := _players3d[_p3]
	_p3 = (_p3 + 1) % _players3d.size()
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Start the looping music (a no-op when it is already playing). Unknown names are ignored like effects.
func play_music(music_name: StringName = MUSIC_NAME, volume_db := MUSIC_DB) -> void:
	var s := _get(music_name)
	if s == null:
		return
	if _music.stream == s and _music.playing:
		return
	_music.stream = s
	_music.volume_db = volume_db
	_music.play()


func stop_music() -> void:
	_music.stop()


func is_music_playing() -> bool:
	return _music != null and _music.playing


func _bus_or_master(bus: StringName) -> StringName:
	return bus if AudioServer.get_bus_index(bus) >= 0 else &"Master"


func _get(sfx_name: StringName) -> AudioStream:
	if _cache.has(sfx_name):
		return _cache[sfx_name]
	var path := DIR + String(sfx_name) + ".wav"
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_cache[sfx_name] = s
	return s
