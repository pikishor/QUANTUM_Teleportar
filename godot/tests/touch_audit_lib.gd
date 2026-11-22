extends RefCounted
## THE TOUCH AUDIT (wave 116, owner round 7: "small silly errors. Are you even checking."). The shared engine of tests/test_touch_audit*.gd and tests/bot_touch_audit.gd:
## the real main scene, touch forced, the phone-only layers on (reward cards, hints), the window at 844x390, and a finger made of real InputEventScreenTouch /
## InputEventScreenDrag events sent through Input.parse_input_event in WINDOW coordinates. Nothing here calls a press function and nothing sends a mouse event.
##
## What it does: it lists every control that is on screen right now (the HUD's touch buttons, the drawn menu buttons of scripts/ui/hud.gd, every Godot Control a player
## could press, the cells of the screens that draw themselves), presses each one with the finger, and files one row per control: what changed (a screen, a value, a sound,
## nothing), how big the target is in real pixels at 844x390 and which neighbour it overlaps. `crawl()` walks the menu graph breadth first from a root (title, pause),
## so a screen nobody listed here is still found and pressed.
## Not a class_name on purpose (no import step needed): const Audit := preload("res://tests/touch_audit_lib.gd").

const PHONE := Vector2i(844, 390)
const MAIN_PX := 56.0                     ## wave 118: the least width of a MAIN action disc of the play HUD as drawn (real px at 844x390); every other disc is at least MIN_PX as drawn
const MAIN_IDS: Array[String] = ["fire", "aim", "jump", "snake", "snake_zip", "fly", "interact", "snake_blast", "leave_building", "move_forward", "move_back"]       # wave 119: a row with "chip" (edge chip) is a secondary target
const MIN_PX := 44.0                      ## the least side of a touch target in real pixels at 844x390 (the platform guideline the task names)
const HUD_FLAGS: Array[StringName] = [&"_gear_open", &"_hero_hub", &"_look_open", &"_loadout_open", &"_loadout_page", &"_loadout_quick", &"_skills_open", &"_ach_open", &"_shop_open",
	&"_options_open", &"_arena_open", &"_craft_open", &"_safe_open", &"_heist_open", &"_side_open", &"_board_open", &"_chapters_open"]

var host: Node
var tree: SceneTree
var root: Window
var main: Node
var hud: Hud
var tc: TouchControls
var rows: Array[Dictionary] = []          ## the table: {ctx, src, id, label, w, h, effect, to, note}
var findings: Array[String] = []          ## the rows that are a defect, as text
var old_size := Vector2i.ZERO
var was_touch := false
var shot_dir := ""                        ## the bot sets a folder: every screen visited is saved there as a PNG
var quiet := false


# ---------------------------------------------------------------------------------------------------------------------------------
# the scene and the finger
# ---------------------------------------------------------------------------------------------------------------------------------

func frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func pframes(n: int) -> void:
	for i in n:
		await tree.physics_frame


func until(cond: Callable, max_frames := 240) -> bool:
	var n := max_frames
	while n > 0 and not cond.call():
		await tree.process_frame
		n -= 1
	return cond.call()


## Boots the real main scene as a phone: touch forced, reward cards and hints allowed, user files of this test only, the window at 844x390.
func boot(h: Node, tag: String, fresh_main := true) -> bool:
	host = h
	tree = h.get_tree()
	root = tree.root
	was_touch = Game.force_touch
	Game.force_touch = true
	if fresh_main:
		for f in ["user://progress.cfg", "user://save.cfg", "user://save.cfg.bak", "user://map.cfg", "user://settings.cfg"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		TestMode.reset_toggles()
		main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		host.add_child(main)
		await frames(12)
	else:
		main = root.find_child("Main", true, false)
	hud = root.find_child("Hud", true, false) as Hud
	if hud == null or hud.touch == null or not is_instance_valid(Game.player) or Game.progress == null:
		return false
	tc = hud.touch
	var prog := Game.progress as Progress
	if fresh_main:
		prog.autosave_enabled = false
		prog.path = "user://touch_audit_%s.cfg" % tag
		hud.settings = UiSettings.new("user://touch_audit_%s_settings.cfg" % tag)
		hud.settings.publish(false)
		old_size = root.size
		root.size = PHONE
		await frames(4)
	CrateReveal._quiet = 0                                  # as on a phone: reward cards are allowed (they hid the round 7 bug from every test)
	tc.controls_on = true
	return true


func shutdown() -> void:
	release_all_fingers()
	CrateReveal._quiet = -1
	if old_size != Vector2i.ZERO:
		root.size = old_size
	Game.state = &"menu"
	Game.force_touch = was_touch
	if is_instance_valid(main):
		main.queue_free()
	await frames(3)
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("touch_audit_"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + f))


var _down := {}                           ## finger index -> canvas position


func _send(e: InputEvent) -> void:
	Input.parse_input_event(e)


## A finger goes down at canvas position `pos` (sent in window coordinates, as the screen sends it).
func finger_down(pos: Vector2, idx := 0) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = root.get_final_transform() * pos
	e.pressed = true
	_down[idx] = pos
	_send(e)


func finger_up(idx := 0) -> void:
	if not _down.has(idx):
		return
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = root.get_final_transform() * (_down[idx] as Vector2)
	e.pressed = false
	_down.erase(idx)
	_send(e)


func finger_move(to: Vector2, idx := 0) -> void:
	if not _down.has(idx):
		return
	var e := InputEventScreenDrag.new()
	var xf := root.get_final_transform()
	e.index = idx
	e.position = xf * to
	e.relative = xf.basis_xform(to - (_down[idx] as Vector2))
	_down[idx] = to
	_send(e)


func release_all_fingers() -> void:
	for idx: int in _down.keys():
		finger_up(idx)


## A tap: down, two frames, up, two frames.
func tap(pos: Vector2, idx := 0, hold_frames := 2) -> void:
	finger_down(pos, idx)
	await frames(hold_frames)
	finger_up(idx)
	await frames(2)


## A quick thumb on a slow frame: down and up arrive in the SAME input flush (at 13 to 30 FPS a 50 ms tap fits inside one frame).
func fast_tap(pos: Vector2, idx := 0) -> void:
	finger_down(pos, idx)
	finger_up(idx)


## A drag in `steps` moves, one a frame.
func drag(from: Vector2, to: Vector2, steps := 6, idx := 0) -> void:
	finger_down(from, idx)
	await frames(1)
	for i in steps:
		finger_move(from.lerp(to, float(i + 1) / float(steps)), idx)
		await frames(1)
	finger_up(idx)
	await frames(2)


## The phone's back key, as the platform delivers it: the window's go-back request (Android sends no key event for it).
func back_key() -> void:
	_window_notify(root, Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	if not tree.quit_on_go_back:
		root.go_back_requested.emit()                       # with the engine default on, this signal closes the game on the spot (the old behaviour: the test would end here)
	await frames(3)


## The engine's own walk for a window notification (Window::_propagate_window_notification): the node, then its children in index order, other windows left out.
func _window_notify(n: Node, what: int) -> void:
	n.notification(what)
	for c in n.get_children():
		if not (c is Window):
			_window_notify(c, what)


func vp() -> Vector2:
	return root.get_visible_rect().size


## Real pixels of a canvas length at the phone size.
func px(canvas_len: float) -> float:
	return canvas_len * float(root.size.y) / maxf(vp().y, 1.0)


# ---------------------------------------------------------------------------------------------------------------------------------
# what is on screen
# ---------------------------------------------------------------------------------------------------------------------------------

func map_screen() -> MapScreen:
	return tc.get_node_or_null("MapScreen") as MapScreen


func node_of(type_name: String) -> Node:
	var l := root.find_children("*", type_name, true, false)
	return l[0] if not l.is_empty() else null


static func layer_of(c: Node) -> int:
	var n := c
	while n != null:
		if n is CanvasLayer:
			return (n as CanvasLayer).layer
		n = n.get_parent()
	return 0


## Every Godot Control a finger could mean (buttons, sliders, text fields, option lists, check boxes) that is visible right now.
func node_controls() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not (c is BaseButton or c is Range or c is LineEdit or c is TextEdit or c is ItemList or c is Tree or c is TabBar):
			continue
		if c is ScrollBar and c.get_parent() is ScrollContainer:
			continue
		if not c.is_visible_in_tree() or c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		var r := c.get_global_rect()
		if r.size.x < 1.0 or r.size.y < 1.0 or not Rect2(Vector2.ZERO, vp()).intersects(r):
			continue
		var label := ""
		if c is Button:
			label = (c as Button).text
		out.append({"src": "node", "id": String(c.name), "label": label, "rect": r, "node": c, "layer": layer_of(c), "kind": c.get_class(),
			"disabled": c is BaseButton and (c as BaseButton).disabled})
	return out


## The drawn buttons of the menu layer (scripts/ui/hud.gd): only while that layer is the screen.
func hud_controls() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Game.state == &"play" or Game.state == &"cutscene" or not hud._screen.visible or MapScreen.up:
		return out
	hud._ensure_layout()
	for b: Dictionary in hud.buttons:
		out.append({"src": "hud", "id": String(b["id"]), "label": str(b.get("label", "")), "rect": b["rect"], "layer": hud.layer, "kind": "drawn"})
	return out


## The touch HUD of a play frame: every visible button (a disc), pause and the minimap; the discs of an open wheel instead while one is up.
func touch_controls() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Game.state != &"play" or not tc.controls_on or MapScreen.up:
		return out
	var s := tc._scale()
	if tc.wheel.is_open:
		var r := RadialWheel.ITEM_R * s * tc.wheel.disc_scale()
		for i in tc.wheel.items.size():
			var c := tc.wheel.item_centre(i)
			out.append({"src": "wheel", "id": String(tc.wheel.item_id(i)), "label": str((tc.wheel.items[i] as Dictionary).get("label", "")), "rect": Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0),
				"layer": tc.layer, "kind": "disc", "centre": c, "r": r})
		return out
	for b: Dictionary in TouchControls.BUTTONS:
		if not tc.button_visible(b):
			continue
		var c := tc._button_center(b)
		var r := float(b["r"]) * s * UiSettings.s_button_size                                    # what is drawn
		var hr := maxf(float(b["r"]) * UiSettings.s_button_size, UiUtil.TOUCH_MIN * 0.5) * s * 1.15   # what answers (touch_down)
		out.append({"src": "touch", "id": String(b["action"]), "label": tc._label_of(b), "rect": Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), "hit": Rect2(c - Vector2(hr, hr), Vector2(hr, hr) * 2.0),
			"layer": tc.layer, "kind": "disc", "centre": c, "r": r, "b": b})
	var pc := tc._pause_center()
	var pr := TouchControls.PAUSE_R * s
	out.append({"src": "touch", "id": "pause", "label": "PAUSE", "rect": Rect2(pc - Vector2(pr, pr), Vector2(pr, pr) * 2.0), "hit": Rect2(pc - Vector2(pr, pr) * 1.3, Vector2(pr, pr) * 2.6),
		"layer": tc.layer, "kind": "disc", "centre": pc, "r": pr})
	out.append({"src": "touch", "id": "minimap", "label": "MAP", "rect": tc._minimap_rect(), "layer": tc.layer, "kind": "rect"})
	return out


## Everything pressable on screen now.
func controls() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(hud_controls())
	out.append_array(touch_controls())
	out.append_array(node_controls())
	return out


## The area around a drawn menu button in which a press means THAT button: walked outwards from its centre in 2 px steps with the HUD's own hit test.
func hud_target(c: Dictionary) -> Rect2:
	var r: Rect2 = c["rect"]
	var ctr := r.get_center()
	var id := StringName(c["id"])
	var ext := [0.0, 0.0, 0.0, 0.0]                          # left, right, up, down
	var dirs := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	for k in 4:
		var d := 0.0
		while d < 400.0 and hud._button_at(ctr + (dirs[k] as Vector2) * (d + 1.0)) == id:
			d += 1.0
		ext[k] = d
	return Rect2(ctr.x - ext[0], ctr.y - ext[2], ext[0] + ext[1], ext[2] + ext[3])


func find(list: Array[Dictionary], id: String, src := "") -> Dictionary:
	for c: Dictionary in list:
		if c["id"] == id and (src == "" or c["src"] == src):
			return c
	return {}


func centre_of(c: Dictionary) -> Vector2:
	return (c["rect"] as Rect2).get_center()


# ---------------------------------------------------------------------------------------------------------------------------------
# what a press changed
# ---------------------------------------------------------------------------------------------------------------------------------

## The screen a player is on, as a short name: the state, the open sub screens, the layers over them. Paging and values do not change it.
func screen_key() -> String:
	var k := String(Game.state)
	for f: StringName in HUD_FLAGS:
		var v: Variant = hud.get(f)
		if (v is bool and v) or (v is int and int(v) != 0):
			k += "+" + String(f).trim_prefix("_").trim_suffix("_open") + (str(v) if v is int else "")
	if hud._options_open:
		k += "+tab%d.%d" % [UiSettings.s_opt_tab, UiSettings.s_opt_page]
	if hud._shop_open and not hud._skills_open and not hud._craft_open:
		k += "+wp%d" % mini(ShopScreen.weapon_page, 1)
	if hud.photo_open():
		k += "+photo"
	if MapScreen.up:
		k += "+MAP"
	if InteriorGameplay.vendor_open:
		k += "+VENDOR"
	for cls in ["TestMenu", "DemoPanel", "GarageScreen", "ResultCard"]:
		var n := node_of(cls)
		if n != null and _screen_open(n):
			k += "+" + cls.to_upper()
	if tc.wheel.is_open:
		k += "+wheel_" + String(tc.wheel.kind)
	if tc.more_open and Game.state == &"play":
		k += "+more"
	return k


func _screen_open(n: Node) -> bool:
	if n.get("is_open") is bool:
		return bool(n.get("is_open"))
	if n.has_method(&"is_open"):
		return bool(n.call(&"is_open"))
	if n.get("_open") is bool:
		return bool(n.get("_open"))
	if n is CanvasLayer:
		return (n as CanvasLayer).visible
	return false


## Everything a press could change, as one string: the screen, the buttons and their labels, the settings, the wallet and the save, the hero's weapon, the map.
func signature() -> String:
	var s := screen_key() + "|" + hud._layout_key.md5_text()
	for b: Dictionary in hud.buttons:
		s += "%s:%s:%s," % [b["id"], b.get("label", ""), b.get("on", false)]
	var st := hud.settings
	var acc := ""
	for p: Dictionary in st.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			acc += str(st.get(p["name"]))
	s += "|S" + acc.md5_text()
	var prog := Game.progress as Progress
	s += "|P%d.%s" % [prog.credits, str(prog.snapshot()).md5_text()]
	var pl := Game.player
	if is_instance_valid(pl) and pl.get(&"weapon") is PlayerWeapon:
		s += "|W" + String((pl.get(&"weapon") as PlayerWeapon).current)
	var ms := map_screen()
	if ms != null:
		s += "|M%s%s%s" % [MapScreen.up, str(ms.get("selected")), str(ms.get("_zoom"))]
	for n in root.find_children("*", "BaseButton", true, false):
		var bb := n as BaseButton
		if bb.is_visible_in_tree():
			s += "%s=%s%s," % [bb.name, (bb as Button).text if bb is Button else "", bb.button_pressed]
	s += "|T%s%s%s" % [tc.more_open, tc.perf_shown, tc.errors_on]
	s += "|E%.2f|Q%d%s" % [Engine.time_scale, Game.tier_index(), Game.low_plus]
	s += "|X%s%s%s%s%s" % [TestMode.god, TestMode.infinite_ammo, TestMode.one_hit, TestMode.no_heat, TestMode.freeze]
	return s


func row(ctx: String, c: Dictionary, effect: String, to := "", note := "") -> Dictionary:
	var target: Rect2 = c.get("hit", c["rect"])
	var r := {"ctx": ctx, "src": c["src"], "id": c["id"], "label": c.get("label", ""), "w": px(target.size.x), "h": px(target.size.y), "effect": effect, "to": to, "note": note}
	rows.append(r)
	return r


func finding(text: String) -> void:
	if not findings.has(text):
		findings.append(text)
		if not quiet:
			print("FINDING: ", text)


## Size and neighbour checks of one screen's controls: every target at least MIN_PX across in real pixels, no two drawn shapes over each other, nothing off the screen.
func geometry(ctx: String, list: Array[Dictionary]) -> Array[String]:
	var bad: Array[String] = []
	var screen := Rect2(Vector2.ZERO, vp())
	for c: Dictionary in list:
		var target: Rect2 = c.get("hit", c["rect"])
		if c["src"] == "hud":
			target = hud_target(c)                                              # the area that really answers for this button (Hud._button_at), measured
			c["hit"] = target
		var w := px(target.size.x)
		var hgt := px(target.size.y)
		if minf(w, hgt) < MIN_PX - 0.5:
			bad.append("%s: %s '%s' is %.0f x %.0f px (under %d)" % [ctx, c["id"], c["label"], w, hgt, int(MIN_PX)])
		if c["src"] == "touch" and c["kind"] == "disc":                       # wave 118: the DRAWN disc of the play HUD: 56 px for a main action, 44 px for the rest
			var need := MAIN_PX if MAIN_IDS.has(String(c["id"])) and not bool((c.get("b", {}) as Dictionary).get("chip", false)) else MIN_PX
			if px(float(c["r"]) * 2.0) < need - 0.5:
				bad.append("%s: %s '%s' is drawn %.0f px across (under %d)" % [ctx, c["id"], c["label"], px(float(c["r"]) * 2.0), int(need)])
		var rr: Rect2 = c["rect"]
		if not screen.grow(1.0).encloses(rr):
			bad.append("%s: %s '%s' leaves the screen (%s)" % [ctx, c["id"], c["label"], str(rr)])
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: Dictionary = list[i]
			var b: Dictionary = list[j]
			if a["src"] == "node" and b["src"] == "node" and ((a["node"] as Node).is_ancestor_of(b["node"]) or (b["node"] as Node).is_ancestor_of(a["node"])):
				continue
			if a["src"] != b["src"] and a["layer"] != b["layer"]:
				continue                                                          # another layer over this one is the swallow check, not a neighbour
			var over := 0.0
			if a["kind"] == "disc" and b["kind"] == "disc":
				over = float(a["r"]) + float(b["r"]) - (a["centre"] as Vector2).distance_to(b["centre"])
			else:
				var x: Rect2 = (a["rect"] as Rect2).intersection(b["rect"])
				over = minf(x.size.x, x.size.y) if x.has_area() else 0.0
			if px(over) > 1.5:
				bad.append("%s: %s '%s' and %s '%s' overlap by %.0f px" % [ctx, a["id"], a["label"], b["id"], b["label"], px(over)])
	return bad


func shot(name: String) -> void:
	if shot_dir == "":
		return
	await frames(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [shot_dir, name.validate_filename().replace("+", "_")])


func is_slider(id: String) -> bool:
	var sid := StringName(id)
	return Hud.SLIDERS.has(sid) or (hud._options_open and OptionsScreen.is_slider(sid)) or (hud.photo_open() and PhotoScreen.is_slider(sid))


## The settings as they are now (every script variable), to put back after a walk through the options.
func settings_snapshot() -> Dictionary:
	var d := {}
	for p: Dictionary in hud.settings.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v: Variant = hud.settings.get(p["name"])
			d[p["name"]] = (v as Dictionary).duplicate(true) if v is Dictionary else ((v as Array).duplicate(true) if v is Array else v)
	return d


func settings_restore(d: Dictionary) -> void:
	for k: String in d:
		var v: Variant = d[k]
		hud.settings.set(k, (v as Dictionary).duplicate(true) if v is Dictionary else ((v as Array).duplicate(true) if v is Array else v))
	hud.settings.publish(false)
	hud.apply_settings(false)
	var want := 0 if hud.settings.low_plus else int(hud.settings.quality) + 1
	if Game.tier_index() != want:
		Game.set_tier_index(want)
	hud._layout_key = ""


# ---------------------------------------------------------------------------------------------------------------------------------
# the menu crawler
# ---------------------------------------------------------------------------------------------------------------------------------

## Puts the game back on a root screen without a finger (this is the harness, not the thing under test): &"menu" = the title, &"paused" = the pause menu, &"play".
func to_root(state: StringName) -> void:
	release_all_fingers()
	var ms := map_screen()
	if ms != null and ms.is_open():
		ms.close_screen()
	for cls in ["TestMenu", "DemoPanel", "GarageScreen"]:
		var n := node_of(cls)
		if n != null and _screen_open(n) and n.has_method(&"close"):
			n.call(&"close")
	if hud.photo != null and hud.photo.active:
		hud.photo.end()
	if DemoMode.active:
		DemoMode.quit()
	var bn := tree.get_first_node_in_group(&"benchmark") as BenchmarkRun
	if bn != null and (bn.running or bn.panel_open):
		bn.cancel()
		bn.close_panel()
	CrateReveal._queue.clear()
	if Game.state == &"menu" and state != &"menu":
		Game.state = &"play"
	if Game.state == state:
		Game.state = &"play" if state != &"play" else &"paused"
	Game.state = state
	hud.screen_age = 5.0
	OptionsScreen.reset_armed = false
	OptionsScreen.reset_demo_armed = false
	tc.more_open = false
	await frames(2)


## Goes to a screen: the root, then the path of button ids, each pressed by the finger. False when a button of the path is not there.
func goto(state: StringName, path: Array) -> bool:
	await to_root(state)
	for id: String in path:
		var c := find(controls(), id)
		if c.is_empty():
			return false
		await tap(centre_of(c))
	return true


## Walks every screen that can be reached from `state` by pressing drawn menu buttons and node buttons, breadth first, and presses every control of every screen.
## `skip` are ids that are pressed in a scripted check elsewhere (they leave the menus or change the save in a way the walk cannot undo).
## `restore` is called after every press that changed something without leaving the screen (the walk keeps the settings and the wallet as they were).
func crawl(state: StringName, name: String, skip: Array, max_depth := 4, restore := Callable()) -> Dictionary:
	var seen := {}                      # screen key -> path
	var queue: Array = [[]]
	var out := {"screens": 0, "pressed": 0, "dead": [], "trapped": [], "back_dead": [], "double": []}
	await to_root(state)
	seen[screen_key()] = []
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		if not await goto(state, path):
			finding("%s: the path %s cannot be walked again" % [name, str(path)])
			continue
		var here := screen_key()
		var ctx := "%s%s" % [name, ("/" + "/".join(path)) if not path.is_empty() else ""]
		var list := controls()
		out["screens"] += 1
		await shot(ctx.replace("/", "__"))
		for g in geometry(ctx, list):
			finding(g)
		var ids: Array[String] = []
		for c: Dictionary in list:
			ids.append(c["id"])
		var left := path.is_empty()                                        # a root screen needs no way out
		var tiles_done := {}
		for id in ids:
			if skip.has(id):
				rows.append({"ctx": ctx, "src": "-", "id": id, "label": "", "w": 0.0, "h": 0.0, "effect": "scripted", "to": "", "note": "pressed in a scripted check"})
				continue
			var c := find(controls(), id)
			if c.is_empty() or screen_key() != here:
				if not await goto(state, path):
					break
				c = find(controls(), id)
				if c.is_empty() and (id.begins_with("wheel_") or id.begins_with("wsel_")):
					for k: Dictionary in controls():                              # the weapon list scrolled to another row: press a tile that is in view now and was not pressed yet
						if String(k["id"]).begins_with(id.get_slice("_", 0) + "_") and not tiles_done.has(k["id"]):
							c = k
							break
				if c.is_empty():
					rows.append({"ctx": ctx, "src": "-", "id": id, "label": "", "w": 0.0, "h": 0.0, "effect": "gone", "to": "", "note": "an earlier press took it away"})
					continue
			tiles_done[c["id"]] = true
			if c.get("disabled", false):
				row(ctx, c, "disabled")
				continue
			var before := signature()
			Sfx.last_played = &""
			var tb0 := TouchButtons.presses
			if is_slider(id):
				var sr: Rect2 = c["rect"]
				await drag(sr.position + Vector2(sr.size.x * 0.82, sr.size.y * 0.5), sr.position + Vector2(sr.size.x * 0.6, sr.size.y * 0.5))      # a slider is dragged, not tapped
			else:
				await tap(centre_of(c))
			out["pressed"] += 1
			var after_key := screen_key()
			var sound := String(Sfx.last_played)
			var effect := "dead"
			if after_key != here:
				effect = "nav"
			elif signature() != before:
				effect = "state"
			elif sound != "":
				effect = "sound"
			var note := sound
			if c["src"] == "node" and c["node"] is BaseButton and TouchButtons.presses - tb0 != 1:
				note += " node presses %d" % (TouchButtons.presses - tb0)
				finding("%s: the Button %s '%s' fired %d times for one tap" % [ctx, id, c["label"], TouchButtons.presses - tb0])
				(out["double"] as Array).append("%s: %s" % [ctx, id])
			row(ctx, c, effect, after_key if effect == "nav" else "", note)
			if effect == "dead":
				(out["dead"] as Array).append("%s: %s '%s'" % [ctx, id, c["label"]])
			if effect == "nav":
				if not String(after_key).begins_with(String(state)) or (seen.has(after_key) and (seen[after_key] as Array).size() < path.size()):
					left = true                                                 # this control leaves the screen: to its parent, to the game, to another root
				if not seen.has(after_key) and path.size() < max_depth and String(after_key).begins_with(String(state)):
					seen[after_key] = path + [id]
					queue.append(path + [id])
			elif effect == "state" and restore.is_valid():
				restore.call()
		if not left:
			(out["trapped"] as Array).append(ctx)
			finding("%s: TRAPPED, no control on this screen leaves it by a finger" % ctx)
		if not path.is_empty() and await goto(state, path):               # the phone's BACK key leaves every screen too
			await back_key()
			var bk := screen_key()
			rows.append({"ctx": ctx, "src": "key", "id": "BACK KEY", "label": "", "w": 0.0, "h": 0.0, "effect": "nav" if bk != here else "dead", "to": bk, "note": String(BackKey.last)})
			if bk == here:
				(out["back_dead"] as Array).append(ctx)
				finding("%s: the BACK key does not leave this screen" % ctx)
	out["seen"] = seen
	return out


# ---------------------------------------------------------------------------------------------------------------------------------
# the table
# ---------------------------------------------------------------------------------------------------------------------------------

func table() -> String:
	var t := ""
	for r: Dictionary in rows:
		t += "%s | %s | %s | %s | %dx%d | %s | %s | %s\n" % [r["ctx"], r["src"], r["id"], str(r["label"]).replace("\n", " "), int(r["w"]), int(r["h"]), r["effect"], r["to"], r["note"]]
	return t


func summary() -> String:
	var n := {}
	for r: Dictionary in rows:
		n[r["effect"]] = int(n.get(r["effect"], 0)) + 1
	return "%d controls: %s" % [rows.size(), str(n)]


# ---------------------------------------------------------------------------------------------------------------------------------
# the touch HUD of a play frame
# ---------------------------------------------------------------------------------------------------------------------------------

var checks: Array = []                    ## [ok, text]: the test feeds them to TestLib.check, the bot prints them


func ck(ok: bool, text: String) -> bool:
	checks.append([ok, text])
	if not ok:
		finding(text)
	return ok


## What a HUD press could change in the world, as one string.
func play_sig() -> String:
	var p := Game.player as Player
	var s := "%s|%s" % [screen_key(), Game.state]
	if p.weapon != null:
		s += "|w%s.%d.%d.%s.%d" % [p.weapon.current, p.weapon.mag, p.weapon.ammo, p.reloading, p.weapon.ammo_type]
	s += "|a%s|y%d|v%s" % [p.aiming, int(p.global_position.y * 4.0), p.vehicle != null]
	s += "|s%d|i%s|m%s" % [p.snake.mode, InteriorGameplay.active, tc.more_open]
	if p.vehicle != null and p.vehicle.get("weapons") != null:
		var vw: Object = p.vehicle.get("weapons")
		s += "|V%d.%d" % [int(vw.get("shots")), int(vw.get("alt_shots"))]
	s += "|c%d|h%.1f" % [p.camera_rig.veh_view, Game.heat]
	for f in ["crouching", "crouched", "is_crouching"]:
		if p.get(f) != null:
			s += "|k%s" % str(p.get(f))
	if Companion.current != null:
		s += "|C%d" % Companion.current.mode
	if is_instance_valid(Game.vehicles) and Game.vehicles.get("radio") != null:
		s += "|R%s" % str(Game.vehicles.get("radio").get("station"))
	if Charges.current != null:
		s += "|X%s" % str(Charges.current.armed())
	return s


## Holds every touch button of the frame once (a real finger, half a second of game frames) and files a row: was its action down while the finger was down and up after,
## did the world or the screen change. The scripted buttons (wheels, MORE, pause, map, the car door) are pressed by their own checks. Returns the ids it pressed.
func press_hud_frame(ctx: String, skip: Array = []) -> Array[String]:
	var pressed: Array[String] = []
	var list := touch_controls()
	for g in geometry(ctx, list):
		finding(g)
	await shot(ctx)
	var ids: Array[String] = []
	for c: Dictionary in list:
		ids.append(c["id"])
	for id in ids:
		if skip.has(id) or id in ["pause", "minimap", "more", "ability", "swap", "interact", "leave_building", "garage_open", "garage_call", "skip_piece"]:
			continue
		if Game.state != &"play":
			break
		var c := find(touch_controls(), id, "touch")
		if c.is_empty():
			continue
		var b: Dictionary = c["b"]
		var action: StringName = b["action"]
		var before := play_sig()
		Sfx.last_played = &""
		var uses_action: bool = not b.has("fn") and not bool(b.get("call", false))
		var box := [false]
		var watch := func() -> void:                                  # "down" = a physics tick saw the action pressed (the game may let it go by itself, as MELEE does)
			if Input.is_action_pressed(action):
				box[0] = true
		if uses_action:
			tree.physics_frame.connect(watch)
		finger_down(centre_of(c))
		await frames(2)
		await pframes(18)
		if uses_action:
			tree.physics_frame.disconnect(watch)
		var down_ok: bool = box[0] if uses_action else true
		var during := play_sig()
		finger_up()
		await frames(3)
		var up_ok: bool = (not Input.is_action_pressed(action)) if uses_action else true
		await pframes(6)
		var changed := during != before or play_sig() != before or Sfx.last_played != &""
		var effect := "dead"
		if uses_action and not down_ok:
			effect = "dead"
		elif changed:
			effect = "state"
		elif uses_action:
			effect = "action"                                          # the action went down and up; nothing visible changed in this situation
		row(ctx, c, effect, "", "%s%s" % ["" if up_ok else "STUCK DOWN ", String(Sfx.last_played)])
		ck(down_ok, "%s: a finger on %s '%s' presses %s" % [ctx, id, c["label"], action])
		ck(up_ok, "%s: lifting the finger from %s '%s' lets %s go" % [ctx, id, c["label"], action])
		pressed.append(id)
	return pressed


func hud_ids() -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in touch_controls():
		out.append(c["id"])
	return out


func hud_button(id: String) -> Dictionary:
	return find(touch_controls(), id)


## Taps a HUD button by id; false when it is not on screen.
func tap_hud(id: String, hold_frames := 2) -> bool:
	var c := hud_button(id)
	if c.is_empty():
		return false
	await tap(centre_of(c), 0, hold_frames)
	return true


# ---------------------------------------------------------------------------------------------------------------------------------
# the screens that are not the HUD's menu layer
# ---------------------------------------------------------------------------------------------------------------------------------

## The cells of a menu that draws itself (TestMenu, DemoPanel: tabs, CLOSE, the rows in view) as controls.
func panel_controls(n: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if n == null or not bool(n.get("is_open")):
		return out
	n.call(&"layout")
	var lay := layer_of(n)
	var view := Rect2(Vector2.ZERO, vp())
	out.append({"src": "panel", "id": "close", "label": "CLOSE", "rect": n.call(&"_close_rect"), "layer": lay, "kind": "rect"})
	var tabs: Array = n.call(&"_tab_rects")
	var names: Array = n.get("TABS")
	for i in tabs.size():
		out.append({"src": "panel", "id": "tab_%d" % i, "label": str(names[i]) if i < names.size() else "", "rect": tabs[i], "layer": lay, "kind": "rect", "tab": i})
	var top := float(n.call(&"_top"))
	var scroll := float(n.get("scroll"))
	var items: Array = n.get("items")
	for i in items.size():
		var it: Dictionary = items[i]
		if it.get("head", false):
			continue
		var r: Rect2 = it["rect"]
		var sr := Rect2(r.position.x, r.position.y + top - scroll, r.size.x, r.size.y)
		if sr.position.y >= top and view.encloses(sr):
			out.append({"src": "panel", "id": "item_%d" % i, "label": str(it.get("label", "")), "rect": sr, "layer": lay, "kind": "rect", "item": it})
	return out


## Presses every enabled Godot control that is on screen once, reading the list again after every press (a press may enable or remove others). `extra` adds to the
## signature (what the screen changes that the common signature does not hold), `skip` holds node names left to a scripted check, `alive` must stay true (the screen is open).
func press_nodes(ctx: String, extra: Callable, skip: Array, alive: Callable) -> Dictionary:
	var out := {"pressed": 0, "dead": [], "double": []}
	var done := {}
	for g in geometry(ctx, node_controls()):
		finding(g)
	await shot(ctx)
	while alive.call():
		var c: Dictionary = {}
		for k: Dictionary in node_controls():
			if not done.has(k["id"]) and not k["disabled"] and not skip.has(k["id"]):
				c = k
				break
		if c.is_empty():
			break
		done[c["id"]] = true
		var before := signature() + str(extra.call())
		Sfx.last_played = &""
		var n0 := TouchButtons.presses
		if c["node"] is Range:
			var sr: Rect2 = c["rect"]
			await drag(sr.position + sr.size * Vector2(0.3, 0.5), sr.position + sr.size * Vector2(0.7, 0.5))
		else:
			await tap(centre_of(c))
		out["pressed"] += 1
		var eff := "state" if signature() + str(extra.call()) != before else ("sound" if Sfx.last_played != &"" else "dead")
		var fired := TouchButtons.presses - n0
		row(ctx, c, eff, "", "presses %d %s" % [fired, Sfx.last_played])
		if eff == "dead":
			(out["dead"] as Array).append("%s '%s'" % [c["id"], c["label"]])
			finding("%s: %s '%s' did nothing" % [ctx, c["id"], c["label"]])
		if c["node"] is BaseButton and fired != 1:
			(out["double"] as Array).append("%s x%d" % [c["id"], fired])
			finding("%s: one tap on %s '%s' fired %d presses" % [ctx, c["id"], c["label"], fired])
	for k: Dictionary in node_controls():
		if k["disabled"] and not done.has(k["id"]):
			row(ctx, k, "disabled")
	return out
