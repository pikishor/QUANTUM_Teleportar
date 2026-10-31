class_name LoadingOverlay
extends CanvasLayer
## First-frame cover (composed by main.gd): the world, the atmosphere and the other modules are built after the first rendered frames, so the title never looks like
## a frozen black window. It draws "LOADING" with a sweeping bar, fades out in `finish()` and removes itself; if finish() is never called it goes away by itself after
## MAX_TIME seconds, so it can never stay up and hide the game.

const MAX_TIME := 15.0
const FADE := 0.35

var _c: Control
var _t := 0.0
var _fade := -1.0                    ## seconds into the fade, -1 while loading


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_c = Control.new()
	_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_c)
	_c.draw.connect(_draw_overlay)


func finish() -> void:
	if _fade < 0.0:
		_fade = 0.0


func is_finishing() -> bool:
	return _fade >= 0.0


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	_t += real
	if _fade >= 0.0:
		_fade += real
		if _fade >= FADE:
			queue_free()
			return
	elif _t >= MAX_TIME:
		finish()
	_c.queue_redraw()


func _draw_overlay() -> void:
	var vp := _c.size
	var s := UiUtil.ui_scale(vp)
	var a := 1.0 if _fade < 0.0 else 1.0 - clampf(_fade / FADE, 0.0, 1.0)
	_c.draw_rect(Rect2(Vector2.ZERO, vp), Color(UiUtil.INK, a))
	var font := UiUtil.font()
	_c.draw_string(font, Vector2(0.0, vp.y * 0.5 - 6.0 * s), "QUANTUM TELEPORTAR", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(46.0 * s), Color(1, 1, 1, 0.95 * a))
	_c.draw_string(font, Vector2(0.0, vp.y * 0.5 + 34.0 * s), "LOADING", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(20.0 * s), Color(UiUtil.CYAN, 0.9 * a))
	var w := 260.0 * s
	var x := vp.x * 0.5 - w * 0.5
	var y := vp.y * 0.5 + 54.0 * s
	_c.draw_rect(Rect2(x, y, w, 3.0 * s), Color(UiUtil.CYAN, 0.18 * a))
	var k := fmod(_t * 0.9, 1.0)
	var seg := w * 0.3
	var sx := x + (w + seg) * k - seg
	var x0 := maxf(sx, x)
	var x1 := minf(sx + seg, x + w)
	if x1 > x0:
		_c.draw_rect(Rect2(x0, y, x1 - x0, 3.0 * s), Color(UiUtil.MAGENTA, 0.95 * a))
