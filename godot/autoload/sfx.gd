extends Node
## Sound effects. Drop WAV files in res://assets/audio/<name>.wav and play them by name.
## Unknown names are silently ignored, so code can call Sfx.play() before the audio exists.

const DIR := "res://assets/audio/"
const POOL := 12

var _cache := {}
var _players: Array[AudioStreamPlayer] = []
var _players3d: Array[AudioStreamPlayer3D] = []
var _pi := 0
var _p3 := 0
var muted := false


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for i in 8:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 12.0
		add_child(p3)
		_players3d.append(p3)


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


func _get(sfx_name: StringName) -> AudioStream:
	if _cache.has(sfx_name):
		return _cache[sfx_name]
	var path := DIR + String(sfx_name) + ".wav"
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_cache[sfx_name] = s
	return s
