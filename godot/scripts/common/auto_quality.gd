class_name AutoQuality
extends Node
## Adaptive graphics tier (composed by main.gd). Two jobs:
##  * on a touchscreen the default tier is LOW until the player picks one (the saved choice in user://settings.cfg, or a --quality flag, always wins);
##  * while playing, an average frame rate under LOW_FPS for LOW_FOR seconds drops ONE tier (never below LOW, at most once per MIN_GAP seconds) and shows a small
##    notice. It never raises the tier and never writes the player's saved choice.
## Frames are counted in real time (a death slow motion does not count as a slow game), only in the play state, and not during the first WARMUP seconds of play or
## after a tier change (shader compiles and mode switches are one-off hitches).

signal lowered(level: int)

const LOW_FPS := 30.0
const LOW_FOR := 4.0
const MIN_GAP := 10.0
const WARMUP := 5.0
const WINDOW := 0.5                  ## seconds per FPS sample
const NOTICE_TIME := 4.0

var enabled := true
var drops := 0
var notice_left := 0.0

var _win_t := 0.0
var _win_n := 0
var _low_t := 0.0
var _warm := WARMUP
var _since_drop := MIN_GAP
var _layer: CanvasLayer
var _label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.state_changed.connect(_on_state)
	Game.quality_changed.connect(func(_q: int) -> void: _reset_window(true))
	if wants_low_default():
		Game.set_quality(0)
	_build_notice()


## Touchscreen, no tool run, no --quality flag and no saved choice: the first launch starts on LOW.
static func wants_low_default(settings_path := UiSettings.DEFAULT_PATH) -> bool:
	if Game.autostart:
		return false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			return false
	if not (DisplayServer.is_touchscreen_available() or Game.force_touch):
		return false
	return UiSettings.new(settings_path).quality < 0


func _on_state(s: StringName) -> void:
	if s != &"play":
		_reset_window(false)
	else:
		_warm = maxf(_warm, 2.0)


func _reset_window(warm: bool) -> void:
	_win_t = 0.0
	_win_n = 0
	_low_t = 0.0
	if warm:
		_warm = WARMUP


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	_since_drop += real
	if notice_left > 0.0:
		notice_left -= real
		_label.visible = notice_left > 0.0
		if _label.visible:
			_place_notice()
	if not enabled or Game.state != &"play":
		return
	if _warm > 0.0:
		_warm -= real
		return
	_win_t += real
	_win_n += 1
	if _win_t >= WINDOW:
		tick(float(_win_n) / _win_t, _win_t)
		_win_t = 0.0
		_win_n = 0


## One frame-rate sample covering `dt` seconds (the tests feed it directly). Returns true when it lowered the tier.
func tick(avg_fps: float, dt: float) -> bool:
	if avg_fps >= LOW_FPS or Game.quality <= 0:             # nothing to lower at LOW: no slow time is banked either
		_low_t = 0.0
		return false
	_low_t += dt
	if _low_t < LOW_FOR or _since_drop < MIN_GAP:
		return false
	_low_t = 0.0
	_since_drop = 0.0
	drops += 1
	var level := Game.quality - 1
	Game.set_quality(level)
	_warm = WARMUP
	_show_notice("GRAPHICS LOWERED TO %s FOR SMOOTHER PLAY" % ["LOW", "MED", "HIGH"][level])
	lowered.emit(level)
	return true


func _build_notice() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 11
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)
	_label = Label.new()
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5, 0.95))
	_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override(&"outline_size", 4)
	_layer.add_child(_label)


func _show_notice(text: String) -> void:
	_label.text = text
	notice_left = NOTICE_TIME
	_label.visible = true
	_place_notice()


func _place_notice() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	_label.add_theme_font_size_override(&"font_size", int(15.0 * s))
	_label.size = Vector2(vp.x, 24.0 * s)
	_label.position = Vector2(0.0, 92.0 * s)           # under the objective line, clear of the bottom buttons and the dead screen's text
