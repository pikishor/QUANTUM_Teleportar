class_name SnakeFx
extends Node
## Sound beds, speed lines and the anchor marker of the QUANTUM SNAKE traversal (a child of the Player, made by SnakeTraversal.bind).
##   hum   assets/audio/snk_hum.ogg   the energy hum of a snake state, louder with speed and in flight, a murmur on a wall
##   wind  assets/audio/snk_wind.ogg  air rush: volume and pitch follow the speed (swing, zip, flight, the speed a released swing keeps)
##   lines assets/shaders/snake_speed_lines.gdshader  a full-screen layer under the HUD, radial streaks at the screen edges (SnakeCamera.speed_lines 0..1); nothing is drawn below 0.02
##   marker assets/shaders/snake_marker.gdshader  a ring where the next swing would bite (SnakeTraversal.preview), only while the hero is in the air and no snake state runs; one billboard draw call
## One-shot sounds (fire, attach, strain, release, miss, zip, land, wings, boost, roll) are played by the states through Sfx.play (names snk_*), see tools/audio/make_snake.py.

var st: SnakeTraversal
var hum_db := -80.0                         ## current levels (tests read them)
var wind_db := -80.0
var marker_on := false
var lines_on := false
var _hum: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _layer: CanvasLayer
var _rect: ColorRect
var _lmat: ShaderMaterial
var _marker: MeshInstance3D
var _mmat: ShaderMaterial
var _t := 0.0
var _marker_pos := Vector3.ZERO
var _marker_a := 0.0


func _ready() -> void:
	name = "SnakeFx"
	process_priority = 120
	_hum = _player("snk_hum")
	_wind = _player("snk_wind")


## The speed-line layer and the anchor marker are made the first time they are needed: an idle hero carries no canvas layer, no hidden mesh (the perf gate counted two draws for them at MED).
func _ensure_lines() -> void:
	if _rect != null:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 8
	_layer.name = "SpeedLines"
	add_child(_layer)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lmat = ShaderMaterial.new()
	_lmat.shader = preload("res://assets/shaders/snake_speed_lines.gdshader")
	_rect.material = _lmat
	_rect.visible = false
	_layer.add_child(_rect)


func _ensure_marker() -> void:
	if _marker != null:
		return
	_marker = MeshInstance3D.new()
	_marker.name = "AnchorMarker"
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_marker.mesh = q
	_mmat = ShaderMaterial.new()
	_mmat.shader = preload("res://assets/shaders/snake_marker.gdshader")
	_marker.material_override = _mmat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.top_level = true
	_marker.visible = false
	_marker.extra_cull_margin = 4.0
	add_child(_marker)


func _player(sound: String) -> AudioStreamPlayer:
	var path := "res://assets/audio/%s.ogg" % sound
	if not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStreamOggVorbis
	if stream == null:
		return null
	stream.loop = true
	var pl := AudioStreamPlayer.new()
	pl.stream = stream
	pl.bus = &"SFX"
	pl.volume_db = -80.0
	add_child(pl)
	return pl


func _process(delta: float) -> void:
	if st == null or st.p == null:
		return
	var dt := minf(delta, 0.1)
	_t += dt
	var paused := Game.state == &"paused"
	var playing := Game.state == &"play"
	var sp := st.p.velocity.length() if playing else 0.0
	var hum_t := -80.0
	var wind_t := -80.0
	var hum_pitch := 1.0
	var wind_pitch := 1.0
	if playing and not Sfx.muted:
		match st.mode:
			SnakeTraversal.Mode.SWING:
				hum_t = -17.0 + clampf(sp * 0.12, 0.0, 6.0)
				wind_t = -34.0 + clampf((sp - 8.0) / 36.0, 0.0, 1.0) * 28.0
				hum_pitch = 0.85 + sp * 0.006
			SnakeTraversal.Mode.ZIP:
				hum_t = -15.0
				wind_t = -26.0
				hum_pitch = 1.2
			SnakeTraversal.Mode.CLIMB:
				hum_t = -26.0 + (4.0 if st.climb.move_speed > 0.5 else 0.0)
				hum_pitch = 0.7
			SnakeTraversal.Mode.FLY:
				hum_t = -13.0 + (5.0 if st.flight.boosting else 0.0)
				wind_t = -32.0 + clampf(sp / maxf(SnakePower.fly_boost(), 1.0), 0.0, 1.0) * 30.0
				hum_pitch = 0.9 + sp * 0.004
			_:
				if st.air_momentum > 0.0 and sp > 14.0:
					wind_t = -34.0 + clampf((sp - 10.0) / 36.0, 0.0, 1.0) * 24.0
		wind_pitch = 0.75 + clampf(sp / 60.0, 0.0, 1.0) * 0.7
	if not paused:
		hum_db = lerpf(hum_db, hum_t, 1.0 - exp(-7.0 * dt))
		wind_db = lerpf(wind_db, wind_t, 1.0 - exp(-5.0 * dt))
	_apply(_hum, hum_db, hum_pitch)
	_apply(_wind, wind_db, wind_pitch)
	# speed lines
	var amount := st.cam.speed_lines if playing else 0.0
	lines_on = amount > 0.02
	if lines_on:
		_ensure_lines()
	if _rect != null:
		_rect.visible = lines_on
	if lines_on:
		_lmat.set_shader_parameter("amount", amount)
		_lmat.set_shader_parameter("time_s", _t)
	# the anchor marker
	var want := false
	if playing and st.mode == SnakeTraversal.Mode.NONE and not st.preview.is_empty() and not st.p.is_dead() and (st.p.air_time > 0.25 or st.hint == &"zip") and not Game.player_in_vehicle():
		want = Game.quality > 0 or st.p.air_time > 0.25
	if want:
		_ensure_marker()
		var tp: Vector3 = (st.preview["pos"] as Vector3) + (st.preview["normal"] as Vector3) * 0.35
		if _marker_a <= 0.01:
			_marker_pos = tp
		_marker_pos = _marker_pos.lerp(tp, 1.0 - exp(-14.0 * dt))
		var cam := st.p.camera_rig.camera
		var dist := cam.global_position.distance_to(_marker_pos) if cam != null else 20.0
		_marker.global_position = _marker_pos
		var sc := clampf(dist * 0.07, 1.0, 4.0)
		_marker.scale = Vector3(sc, sc, sc)
		_marker_a = minf(_marker_a + dt * 5.0, 1.0)
		_mmat.set_shader_parameter("pulse", _t)
		_mmat.set_shader_parameter("alpha", 0.75 * _marker_a)
	else:
		_marker_a = maxf(_marker_a - dt * 8.0, 0.0)
		if _mmat != null:
			_mmat.set_shader_parameter("alpha", 0.75 * _marker_a)
	marker_on = want and _marker_a > 0.01
	if _marker != null:
		_marker.visible = marker_on or _marker_a > 0.01


func _apply(pl: AudioStreamPlayer, db: float, pitch: float) -> void:
	if pl == null:
		return
	if db < -58.0:
		if pl.playing:
			pl.stop()
		return
	if not pl.playing:
		pl.play()
	pl.volume_db = db
	pl.pitch_scale = pitch
