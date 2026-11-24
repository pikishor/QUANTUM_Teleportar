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
## Wave 117 cues (critic 116 #5, #6; flight log #1, #5, #13). All of them are drawn by the touch HUD in its own pass (TouchControls calls hud_cues: rings, plates and words join the
## lists it draws anyway, no draw call is added) and can be read without a renderer:
##   zip_mark      the anchor a tap on ZIP WOULD take, while the hero stands and one is in reach: {pos, end (&"roof" he ends standing up there / &"drop" a wall with no ledge above), dist, top}
##   cue_text      "NO ANCHOR" for CUE_TIME after a press that found nothing to bite (the SNAKE button reads it, a crossed ring and a line show at the crosshair)
##   energy_warn   in SNAKE FLIGHT: 1 = low (ENERGY_LOW_S seconds left at the present burn), 2 = the last ENERGY_LAST_S seconds at the present burn; a line, a ring on LAND and a beep a second
static var cues_on := true                  ## false = no cue at all (wave 116: tests show the checks failing on it)
static var current: SnakeFx
const CUE_TIME := 1.1
const ENERGY_LOW_S := 7.0                   ## "low": this many seconds of flight left at the present burn (or under ENERGY_LOW_FRAC of the pool)
const ENERGY_LOW_FRAC := 0.2
const ENERGY_LAST_FRAC := 0.6               ## the countdown never starts above this share (a BOOST from a full pool is not an alarm)
const ENERGY_LAST_S := 3.0
var cue_text := ""
var cue_t := 0.0
var cues_shown := 0
var zip_mark := {}
var energy_warn := 0
var energy_warns := 0                       ## times a warning level was entered (counter)
var energy_left_s := 0.0
var _beep_t := 0.0
var _hooked := false
var _mark_key := Vector3.INF
var _mark_end: StringName = &"roof"
var _mark_top := 0.0
var _mark_reach := 0.0
var _warming := false                       ## SnakeWarm (the shader pre-warm) has made both visuals draw once: _process leaves them alone until warm_end


func _ready() -> void:
	name = "SnakeFx"
	process_priority = 120
	current = self
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
	_lines_old = -1
	_push_lines()


## The mask of the streaks (FlightView.lines_params: where they start, how faint they are). Pushed when the layer is made and again when the look switch changes.
const LINE_UNIFORMS: Array[StringName] = [&"metric", &"inner_base", &"inner_var", &"inner_amount", &"fade_width", &"alpha", &"width_base", &"width_var", &"on_base", &"on_amount"]
var _lines_old := -1


func _push_lines() -> void:
	var want := 1 if FlightView.old_look else 0
	if _lmat == null or want == _lines_old:
		return
	_lines_old = want
	var prm := FlightView.lines_params()
	for i in LINE_UNIFORMS.size():
		_lmat.set_shader_parameter(LINE_UNIFORMS[i], prm[i])


## The parameters the streak layer draws with now ([] while the layer does not exist): tests read them.
func lines_params_now() -> Array[float]:
	var out: Array[float] = []
	if _lmat == null:
		return out
	for u in LINE_UNIFORMS:
		out.append(float(_lmat.get_shader_parameter(u)))
	return out


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
	_cue_tick(dt)
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
	if _warming:
		return
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
		_push_lines()
	# the anchor marker
	var want := false
	if playing and st.mode == SnakeTraversal.Mode.NONE and not st.preview.is_empty() and not st.p.is_dead() and (st.p.air_time > 0.25 or (st.hint == &"zip" and zip_mark.is_empty())) and not Game.player_in_vehicle():      # wave 117: on the ground the HUD marks the ZIP anchor itself (zip_mark), not the swing anchor
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


## Pre-warm (SnakeWarm, run by ShaderWarmup behind the loading overlay): the speed-line layer and the anchor marker exist and draw once so their pipelines are compiled before the first swing.
func warm_begin(at: Vector3) -> void:
	_warming = true
	_ensure_lines()
	_rect.visible = true
	_lmat.set_shader_parameter("amount", 0.05)
	_lmat.set_shader_parameter("time_s", 0.0)
	_ensure_marker()
	_marker.global_position = at
	_mmat.set_shader_parameter("alpha", 0.05)
	_marker.visible = true


## ... and gone again: an idle hero carries no canvas layer and no hidden mesh (the perf gate counted two draws for them at MED).
func warm_end() -> void:
	_warming = false
	if _layer != null:
		_layer.queue_free()
	_layer = null
	_rect = null
	_lmat = null
	_lines_old = -1
	if _marker != null:
		_marker.queue_free()
	_marker = null
	_mmat = null
	_marker_a = 0.0
	lines_on = false
	marker_on = false


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


# --- wave 117: the cues ----------------------------------------------------------------------------------------------------------------

func _exit_tree() -> void:
	if current == self:
		current = null


## The SNAKE button's word while a cue runs ("" = none): SnakeTraversal.button_label asks first.
static func label_cue() -> String:
	if cues_on and is_instance_valid(current) and current.cue_t > 0.0:
		return current.cue_text
	return ""


func _on_event(id: StringName) -> void:
	if id == &"whiff" and cues_on:
		cue_text = "NO ANCHOR"
		cue_t = CUE_TIME
		cues_shown += 1


func _cue_tick(dt: float) -> void:
	if not _hooked:
		_hooked = true
		st.event.connect(_on_event)
	cue_t = maxf(0.0, cue_t - dt)
	var playing := Game.state == &"play"
	# the anchor a ZIP would take
	var z: Dictionary = st.zip_target
	if not cues_on or not playing or z.is_empty() or st.mode != SnakeTraversal.Mode.NONE or st.hint != &"zip" or st.p.air_time > 0.25 or st.p.is_dead() or Game.player_in_vehicle():
		zip_mark = {}
	else:
		var pos: Vector3 = z["pos"]
		var dest: Vector3 = z.get("dest", pos)
		if pos.distance_squared_to(_mark_key) > 0.09 or _mark_reach != SnakeZip.haul_max:
			_mark_key = pos
			_mark_reach = SnakeZip.haul_max
			_mark_end = &"roof"
			_mark_top = dest.y
			if StringName(z.get("kind", &"roof")) == &"wall" and SnakeZip.wall_end:
				var stand := st.zip.edge_above(st.p, z["normal"], dest)
				_mark_end = &"roof" if stand.is_finite() else &"drop"
				_mark_top = stand.y if stand.is_finite() else dest.y
			elif StringName(z.get("kind", &"roof")) == &"wall":
				_mark_end = &"wall"
		zip_mark = {"pos": pos, "end": _mark_end, "dist": pos.distance_to(st.p.global_position + Vector3(0.0, 1.5, 0.0)), "top": _mark_top}
	# flight energy
	var was := energy_warn
	energy_warn = 0
	if cues_on and playing and st.mode == SnakeTraversal.Mode.FLY and not SnakePower.unlimited() and st.flight.phase != &"landing" and st.flight.phase != &"glide":
		var k := 3.6 if st.flight.boosting else 1.0
		energy_left_s = st.energy / maxf(SnakePower.fly_cost_per_s() * k, 0.01)
		var frac := st.energy_fraction()
		if energy_left_s <= ENERGY_LAST_S and frac <= ENERGY_LAST_FRAC:
			energy_warn = 2
		elif (energy_left_s <= ENERGY_LOW_S and frac <= ENERGY_LAST_FRAC) or frac <= ENERGY_LOW_FRAC:
			energy_warn = 1
	if energy_warn > was:
		energy_warns += 1
		_beep_t = 0.0
		if not Game.force_touch and not DisplayServer.is_touchscreen_available():          # the phone HUD draws its own line and ring (hud_cues); a desktop gets the toast
			Game.say("SNAKE ENERGY LOW  LAND SOON" if energy_warn == 1 else "WINGS FAIL IN %d" % maxi(1, ceili(energy_left_s)), 1.6)
	if energy_warn > 0:
		_beep_t -= dt
		if _beep_t <= 0.0:
			_beep_t = 1.0 if energy_warn == 1 else 0.45
			Sfx.play(&"ui_deny", -8.0 if energy_warn == 1 else -4.0)


## Called by TouchControls while it collects what it draws. Everything here joins lists the touch HUD draws anyway, so a cue costs NO draw call: `sprites` rows are [rect, colour]
## drawn with the &"button" sprite (a dark translucent disc with a bright rim: a ring round a point, and stretched, the plate behind a line of words, which keeps white words
## readable against the sky); `labels` rows are [left point, text, width, alpha, font size] (only sizes the buttons use, 32 like FIRE and 22 like AIM: one glyph atlas each, already on screen).
static func hud_cues(tc: TouchControls, s: float, sprites: Array, labels: Array) -> void:
	if not cues_on or not is_instance_valid(current) or current.st == null or current.st.p == null or Game.state != &"play":
		return
	var me := current
	var vp: Vector2 = tc.get_viewport().get_visible_rect().size
	var mid: Vector2 = vp * 0.5
	if not me.zip_mark.is_empty() and me.st.button_shown():             # w121-critic: no "ZIP ROOF +16 M" mark under a tower's ceiling, where ZIP is off
		var cam := me.st.p.camera_rig.camera
		var wp: Vector3 = me.zip_mark["pos"]
		if cam != null and not cam.is_position_behind(wp):
			var at := cam.unproject_position(wp)
			if Rect2(Vector2.ZERO, vp).grow(-20.0 * s).has_point(at):
				var good: bool = me.zip_mark["end"] != &"drop"
				var col := Color(UiUtil.CYAN if good else UiUtil.AMBER, 0.95)
				var r := 21.0 * s * (1.0 + 0.12 * sin(me._t * 6.0))
				sprites.append(_ring(at, r, col))
				sprites.append(_ring(at, 5.0 * s, col))
				var up_m := float(me.zip_mark["top"]) - me.st.p.global_position.y
				var txt := "WALL  NO LEDGE"
				if good:
					txt = ("ZIP  ROOF +%d M" % roundi(up_m)) if up_m > 6.0 else ("ZIP  %d M" % roundi(float(me.zip_mark["dist"])))
				var tat := tag_at(tc, at, txt, 22, s)
				if tat.is_finite():
					_line(sprites, labels, tat, txt, 22, s, col, 0.95)
	if me.cue_t > 0.0:
		var a := clampf(me.cue_t / 0.25, 0.0, 1.0)
		var col2 := Color(UiUtil.MAGENTA, 0.95 * a)
		sprites.append(_ring(mid, 27.0 * s, col2))
		_line(sprites, labels, mid + Vector2(0.0, 66.0 * s), "NO ANCHOR IN REACH", 32, s, col2, a)
		for b: Dictionary in TouchControls.BUTTONS:
			if b["action"] == (me.st.whiff_action if SnakeTraversal.split_buttons else &"snake") and tc.button_visible(b):       # w118-controls: the button that was pressed (SWING or ZIP)
				sprites.append(_ring(tc._button_center(b), (float(b["r"]) * UiSettings.s_button_size + 9.0) * s, col2))
	if me.energy_warn > 0:
		var blink := 0.55 + 0.45 * sin(me._t * (9.0 if me.energy_warn == 1 else 18.0))
		var col3 := Color(UiUtil.MAGENTA, 0.55 + 0.45 * blink)
		_line(sprites, labels, Vector2(mid.x, vp.y * 0.29), "ENERGY LOW  LAND" if me.energy_warn == 1 else "WINGS FAIL IN %d" % maxi(1, ceili(me.energy_left_s)), 32, s, col3, 1.0)
		for b: Dictionary in TouchControls.BUTTONS:
			if b["action"] == &"fly" and tc.button_visible(b):
				sprites.append(_ring(tc._button_center(b), (float(b["r"]) * UiSettings.s_button_size + 9.0) * s, col3))


static var tag_dodge := true             ## w118 critic: false = the old place (46 px under the ring, even over a touch button: frame foot_844 had ZIP ROOF +81 M on ABILITY)
static var last_tag := Rect2()           ## the plate of the zip tag drawn last (tests)


## Where the zip tag's line goes: under the ring, or above / beside it when a touch button stands there.
static func tag_at(tc: TouchControls, at: Vector2, text: String, fs: int, s: float) -> Vector2:
	var w := (float(text.length()) * float(fs) * 0.66 + 44.0) * s
	var h := float(fs) * 1.75 * s
	var vp: Vector2 = tc.get_viewport().get_visible_rect().size
	var tries: Array[Vector2] = [Vector2(0.0, 46.0 * s)]
	if tag_dodge:
		tries.append_array([Vector2(0.0, -46.0 * s), Vector2(w * 0.5 + 30.0 * s, 0.0), Vector2(-w * 0.5 - 30.0 * s, 0.0), Vector2(0.0, 92.0 * s), Vector2(0.0, -92.0 * s)])
	var pick := at + tries[0] if not tag_dodge else Vector2.INF            # no free place: the ring alone (the words would hide a button)
	for off in tries:
		var c := at + off
		c.x = clampf(c.x, w * 0.5 + 4.0, vp.x - w * 0.5 - 4.0)
		var plate := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
		var hit := false
		for b: Dictionary in TouchControls.BUTTONS:
			if tc.button_visible(b):
				var r := float(b["r"]) * UiSettings.s_button_size * s
				var bc := tc._button_center(b)
				if plate.grow(r).has_point(bc) and Vector2(clampf(bc.x, plate.position.x, plate.end.x), clampf(bc.y, plate.position.y, plate.end.y)).distance_to(bc) < r:
					hit = true
					break
		if not hit:
			pick = c
			break
	last_tag = Rect2(pick - Vector2(w, h) * 0.5, Vector2(w, h)) if pick.is_finite() else Rect2(Vector2(-1, -1), Vector2(1, 1))
	return pick


static func _ring(at: Vector2, r: float, col: Color) -> Array:
	return [Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), col]


## One line of words centred on `at` on its plate.
static func _line(sprites: Array, labels: Array, at: Vector2, text: String, fs: int, s: float, rim: Color, alpha: float) -> void:
	var w := (float(text.length()) * float(fs) * 0.66 + 44.0) * s
	var h := float(fs) * 1.75 * s
	sprites.append([Rect2(at - Vector2(w, h) * 0.5, Vector2(w, h)), Color(rim, rim.a * 0.9)])
	labels.append([at + Vector2(-w * 0.5, float(fs) * 0.36 * s), text, w, alpha, fs])
