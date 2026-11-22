class_name CallIn
extends CanvasLayer
## WAVE 118: the CALL-IN list of the phone (owner round 7: "where are tanks and helicopters"). The CALL button of the MORE tray opens it; one tap on a row delivers that vehicle
## beside the hero: CAR (the garage car, or the free hover-bike: VehicleManager.summon_any), TANK, HELICOPTER, PLANE (ArmourSites.call_in, one cooldown each). A row that is
## recharging shows its seconds. The game keeps running under it; a pick, CLOSE, 10 s without a tap, a vehicle entered or any other screen closes it.
## Rows are plain Buttons: a finger reaches them through TouchButtons (scripts/ui/touch_buttons.gd), a mouse directly.
##   CallIn.toggle()   CallIn.is_open()   CallIn.close()   CallIn.picks (tests)

const ROWS: Array = [[&"car", "CAR"], [&"tank", "TANK"], [&"heli", "HELICOPTER"], [&"plane", "PLANE"]]
const ROW_W := 300.0
const ROW_H := 72.0
const IDLE_CLOSE := 10.0

static var instance: CallIn
static var picks := 0
static var enabled := true                    ## false: the old CALL CAR (old-behaviour trial of tests/test_armour_w118.gd)

var _btns := {}
var _box: Control
var _idle := 0.0


static func is_open() -> bool:
	return is_instance_valid(instance) and instance.visible


static func toggle() -> void:
	if not enabled:                              # the wave 117 button: the garage car or the hover-bike at once, nothing else to call
		if is_instance_valid(Game.vehicles):
			Game.vehicles.call(&"summon_any")
		return
	if is_open():
		close()
		return
	var tree := Engine.get_main_loop() as SceneTree
	if not is_instance_valid(instance):
		instance = CallIn.new()
		instance.name = "CallIn"
		tree.root.add_child(instance)
	instance._open()


static func close() -> void:
	if is_instance_valid(instance):
		instance.visible = false


func _ready() -> void:
	layer = 12                                   # over the touch HUD (9 / 11), under every full screen (map 30, menus 40)
	_box = Control.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_box)
	_box.draw.connect(_draw_box)
	for r: Array in ROWS:
		_btns[r[0]] = _row(String(r[1]), _pick.bind(r[0]))
	_btns[&"close"] = _row("CLOSE", close)


func _row(text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.name = "Call_" + text.capitalize().replace(" ", "")
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(fn)
	_box.add_child(b)
	return b


func _open() -> void:
	visible = true
	_idle = 0.0
	_layout()
	_refresh()


func _rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var n := float(ROWS.size() + 1)
	var w := ROW_W * s
	var h := (ROW_H + 8.0) * s * n + 44.0 * s
	return Rect2(Vector2(vp.x * 0.36 - w * 0.5, maxf(vp.y * 0.5 - h * 0.5, 8.0 * s)), Vector2(w, h))


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var r := _rect()
	var y := r.position.y + 44.0 * s
	for k: StringName in [&"car", &"tank", &"heli", &"plane", &"close"]:
		var b: Button = _btns[k]
		b.position = Vector2(r.position.x, y)
		b.size = Vector2(r.size.x, ROW_H * s)
		b.add_theme_font_size_override("font_size", int(26.0 * s))
		y += (ROW_H + 8.0) * s
	_box.queue_redraw()


func _draw_box() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var r := _rect().grow(10.0 * s)
	_box.draw_rect(r, Color(0.0, 0.02, 0.04, 0.9))
	_box.draw_rect(r, Color(UiUtil.CYAN, 0.5), false, 2.0 * s)
	_box.draw_string(UiUtil.font(), r.position + Vector2(12.0, 34.0) * s, "CALL IN", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(24.0 * s), UiUtil.CYAN)


func _refresh() -> void:
	for r: Array in ROWS:
		var k: StringName = r[0]
		var wait := 0.0
		if k != &"car":
			wait = ArmourSites.call_wait(k)
		(_btns[k] as Button).text = String(r[1]) if wait <= 0.0 else "%s  %d S" % [r[1], int(ceilf(wait))]


func _pick(kind: StringName) -> void:
	picks += 1
	_idle = 0.0
	var v: Vehicle = null
	if kind == &"car":
		v = (Game.vehicles as VehicleManager).summon_any() if is_instance_valid(Game.vehicles) else null
	else:
		v = ArmourSites.call_in(kind)
	if v != null:
		close()
	else:
		_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_idle += delta
	var driving := is_instance_valid(Game.player) and Game.player.get(&"vehicle") != null
	if _idle > IDLE_CLOSE or not Game.is_playing() or MapScreen.up or driving:
		close()
		return
	_refresh()
