class_name ScreenWatchdog
extends CanvasLayer
## No screen can trap the player (owner round 4: "it got stuck when I opened the map"). A global BACK button (a 64 px+ touch target, above every screen) appears after IDLE_SECONDS of
## real time without progress while a closable screen is up: the map, the photo camera, a pause sub-screen (options, loadout, shop, boards ...), the interior vendor window or the TEST menu.
## Progress is anything that changes the picture: the game state, a pan / zoom / tap on the map, a screen opening or closing. Taps that change nothing do NOT count (that is the trap).
## The plain pause menu and the title are never "trapped" (RESUME / DEPLOY are on them). Pressing BACK closes the top screen and hands the state back like the screen's own close does;
## Esc / the phone's back key do the same at any time (MapScreen, Hud and the vendor handle those themselves, the button is for the case where nothing else answers).
## Tests: `force_idle(secs)` fakes the idle time, `shown()` reads the button, `trapped()` names the screen, `press()` is the button.

const IDLE_SECONDS := 5.0

var idle := 0.0
var _sig := ""
var _btn: Button
var _hud: Hud


func _ready() -> void:
	name = "ScreenWatchdog"
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hud = get_parent() as Hud
	_btn = Button.new()
	_btn.name = "WatchdogBack"
	_btn.text = "BACK"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.visible = false
	_btn.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.12, 0.16, 0.96)
	sb.border_color = Color(UiUtil.CYAN, 0.9)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		_btn.add_theme_stylebox_override(st, sb)
	_btn.pressed.connect(press)
	add_child(_btn)


## The closable screen that is up right now, &"" when none.
func trapped() -> StringName:
	var ms := _map()
	if ms != null and ms.is_open():
		return &"map"
	if _hud != null:
		if _hud.photo_open():
			return &"photo"
		if Game.state == &"paused" and not _hud._main_screen():
			return &"screen"
	if InteriorGameplay.vendor_open:
		return &"vendor"
	var tm := _test_menu()
	if tm != null and tm.is_open:
		return &"test"
	return &""


func shown() -> bool:
	return _btn != null and _btn.visible


func force_idle(secs: float) -> void:
	idle = secs


func _map() -> MapScreen:
	if _hud != null and _hud.touch != null:
		return _hud.touch.get_node_or_null("MapScreen") as MapScreen
	return null


func _test_menu() -> TestMenu:
	return get_tree().root.find_child("TestMenu", true, false) as TestMenu


func _signature() -> String:
	var ms := _map()
	return "%s|%d|%s|%s|%s" % [Game.state, ms.activity if ms != null else 0, str(_hud._screen_sig) if _hud != null else "", InteriorGameplay.vendor_open, trapped()]


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	var sig := _signature()
	if sig != _sig:
		_sig = sig
		idle = 0.0
	var which := trapped()
	if which == &"":
		idle = 0.0
		_btn.visible = false
		return
	idle += real
	var on := idle >= IDLE_SECONDS
	if on != _btn.visible or on:
		_place()
	_btn.visible = on


func _place() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var ins := UiUtil.insets(vp)
	var w := 220.0 * s
	var h := maxf(72.0 * s, 64.0)
	_btn.size = Vector2(w, h)
	_btn.position = Vector2(vp.x * 0.5 - w * 0.5, vp.y - h - 12.0 * s - UiUtil.insets_v(vp).y)
	_btn.add_theme_font_size_override("font_size", int(26.0 * s))
	_btn.move_to_front()


## BACK: close the top screen. True when something was closed.
func press() -> bool:
	var which := trapped()
	idle = 0.0
	if _btn != null:
		_btn.visible = false
	match which:
		&"map":
			_map().close_screen()
		&"photo":
			_hud.photo.end()
		&"screen":
			_hud._on_state(Game.state)                       # every sub-screen flag is reset: back on the pause menu
			_hud._screen.queue_redraw()
		&"vendor":
			var ig := InteriorGameplay.instance
			if ig != null and ig.vendor_screen != null:
				ig.vendor_screen.close()
			InteriorGameplay.vendor_open = false
		&"test":
			_test_menu().close()
		_:
			return false
	Sfx.play(&"ui_back")
	return true
