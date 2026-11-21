class_name BackKey
extends Node
## The phone's BACK key (wave 116 touch audit). Android delivers it as a window "go back" request, not as a key. Nothing but the map listened to it, and the engine's default
## (`quit_on_go_back`) was still on: BACK anywhere, even over the open map, CLOSED THE GAME. This node turns the default off and makes BACK do what a player expects: it closes
## the top screen (benchmark, result card, DEMO / TEST menu, map, garage, fast-travel list, vendor, photo mode, a wheel, the MORE cluster), steps one screen back inside the pause
## menu and the title, resumes from the plain pause menu, pauses the running game, and leaves the app only from the plain title screen.
## It sits FIRST under the root, so it gets the request before the map's own handler (which then finds the map already closed).

static var enabled := true                ## false = the old behaviour: nothing but the map answers (tests)
static var handled := 0                   ## requests answered (tests)
static var last := &""                    ## what the last request did (tests): &"map", &"screen", &"resume", &"pause", &"quit" ...
static var quits := 0                     ## times BACK asked to leave the app from the title (the tests run with Game.autostart and never quit)


static func ensure(tree: SceneTree) -> void:
	if tree.root.get_node_or_null("BackKey") == null:
		var n := BackKey.new()
		n.name = "BackKey"
		n.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child.call_deferred(n)
		tree.root.move_child.call_deferred(n, 0)


func _ready() -> void:
	get_tree().quit_on_go_back = not enabled


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and enabled and is_inside_tree():
		last = go_back()
		handled += 1


func _first(group: StringName) -> Node:
	return get_tree().get_first_node_in_group(group)


func _find(type_name: String) -> Node:
	var l := get_tree().root.find_children("*", type_name, true, false)
	return l[0] if not l.is_empty() else null


## One step back. Returns what it did.
func go_back() -> StringName:
	var bn := _first(&"benchmark") as BenchmarkRun
	if bn != null and (bn.running or bn.panel_open):
		if bn.running:
			bn.cancel()
		else:
			bn.close_panel()
		return &"benchmark"
	var rc := _first(&"result_card") as ResultCard
	if rc != null and rc.is_open:
		rc.press_next()
		return &"result"
	var dp := _first(&"demo_panel") as DemoPanel
	if dp != null and dp.is_open:
		dp.close()
		return &"demo"
	var tm := _first(&"test_menu") as TestMenu
	if tm != null and tm.is_open:
		tm.close()
		return &"test"
	var hud := _first(&"hud") as Hud
	if hud == null:
		return &""
	var ms := (hud.touch.get_node_or_null("MapScreen") as MapScreen) if hud.touch != null else null
	if ms != null and ms.is_open():
		ms.close_screen()
		return &"map"
	var gs := (hud.touch.get_node_or_null("GarageScreen") as GarageScreen) if hud.touch != null else null
	if gs != null and gs.is_open():
		gs.close_screen()
		return &"garage"
	var rt := _find("RoamTravel") as RoamTravel
	if rt != null and rt.panel_open:
		rt.stay()
		return &"travel"
	var ig := InteriorGameplay.instance
	if InteriorGameplay.vendor_open and ig != null and ig.vendor_screen != null:
		ig.vendor_screen.close()
		InteriorGameplay.vendor_open = false
		return &"vendor"
	if hud.photo_open():
		hud.photo.end()
		Sfx.play(&"ui_back")
		return &"photo"
	match Game.state:
		&"paused", &"menu":
			if hud._main_screen() and not hud._gear_open:
				if Game.state == &"paused":
					Game.state = &"play"                       # the plain pause menu: BACK resumes
					return &"resume"
				quits += 1
				if not Game.autostart:
					get_tree().quit()                         # the plain title: BACK leaves the app, as every Android game does
				return &"quit"
			hud._ensure_layout()
			for b: Dictionary in hud.buttons:                # the screen's own BACK button, so BACK and the key always agree
				var id := String(b["id"])
				if id.ends_with("_back") and hud.press_button(b["id"]):
					return &"screen"
			hud._on_state(Game.state)                       # a screen without a BACK button: back to the plain menu
			hud._screen.queue_redraw()
			Sfx.play(&"ui_back")
			return &"screen"
		&"play":
			if hud.touch != null and hud.touch.wheel.is_open:
				hud.touch.release_all()
				return &"wheel"
			if hud.touch != null and hud.touch.more_open:
				hud.touch.more_open = false
				return &"more"
			hud.pause_game()
			return &"pause"
	return &""
