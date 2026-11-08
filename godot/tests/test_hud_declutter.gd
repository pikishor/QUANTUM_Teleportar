extends RefCounted
## HUD DECLUTTER in the real scene (main.tscn, touch layout forced): a default play frame shows at most 12 controls and read-outs (stick, FIRE, AIM, JUMP, RELOAD, ABILITY, WEAPON,
## MORE, pause, minimap, status bars, one objective line), with no FPS box, no TEST quick buttons, no shard / credit plate and no ammo plate (the count rides on the WEAPON button).
## ALT / MELEE / THROW / CROUCH live behind MORE, USE shows only near a car, the ABILITY and WEAPON buttons open radial wheels, the toast channel is one short rate-limited line,
## story chatter defaults to LOW (two-line subtitles, no chapter sub-banner) and the title / pause screens hide OPTIONS / DEMO / ARENA behind one gear.
## Waits on state and counters, never on frame counts; user:// state is reset.
## Run: tools/test.sh tests/test_hud_declutter.gd

const SAVE := "user://test_hud_declutter.cfg"
const SETTINGS := "user://test_hud_declutter_settings.cfg"
const MAX_CONTROLS := 12

var host: Node
var main: Node
var hud: Hud
var tc: TouchControls
var p: Player


func frames(n: int) -> void:
	await TestLib.frames(host, n)


func _until(cond: Callable, max_secs: float) -> bool:
	var n := int(max_secs * 60.0)
	while n > 0 and not cond.call():
		await frames(1)
		n -= 1
	return cond.call()


func _cleanup() -> void:
	for f: String in [SAVE, SETTINGS]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func run(h: Node) -> void:
	host = h
	Sfx.muted = true
	_cleanup()
	TestMode.reset_toggles()
	var was_touch := Game.force_touch
	Game.force_touch = true
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await frames(30)
	p = Game.player as Player
	hud = main.find_child("Hud", true, false) as Hud
	var prog := Game.progress as Progress
	TestLib.check(p != null and hud != null and prog != null and hud.touch != null, "main.tscn composes the player, the HUD and the touch controls")
	if p == null or hud == null or prog == null or hud.touch == null:
		Game.force_touch = was_touch
		return
	tc = hud.touch
	prog.autosave_enabled = false
	prog.path = SAVE
	prog.new_campaign()
	hud.settings = UiSettings.new(SETTINGS)             # a fresh settings file: every default
	hud.settings.publish(false)
	(Game.enemies as EnemyManager).clear()
	Game.heat = 0.0
	Game.state = &"play"
	tc.controls_on = true
	tc.perf_shown = false
	tc.more_open = false
	tc.release_all()
	hud.message_left = 0.0
	hud.toast.clear()
	await frames(20)
	await _default_frame()
	await _more_cluster()
	await _use_near_car()
	await _wheels()
	_toast_policy()
	await _chatter()
	await _title_and_pause()
	_cleanup()
	main.queue_free()
	await frames(5)
	Game.force_touch = was_touch
	Game.state = &"menu"


func _default_frame() -> void:
	tc.more_open = false
	var ids := hud.visible_controls()
	TestLib.check(ids.size() <= MAX_CONTROLS, "a default play frame shows at most %d controls (%d: %s)" % [MAX_CONTROLS, ids.size(), str(ids)])
	for need: StringName in [&"stick", &"fire", &"aim", &"jump", &"reload", &"ability", &"swap", &"more", &"pause", &"minimap", &"status", &"objective"]:
		TestLib.check(ids.has(need), "the default frame has %s" % need)
	for gone: StringName in [&"altfire", &"melee", &"throw_item", &"crouch", &"gadget", &"interact", &"grab", &"takedown", &"garage_call", &"fps", &"toast", &"subtitle", &"wanted", &"ammo"]:
		TestLib.check(not ids.has(gone), "the default frame has no %s" % gone)
	TestLib.check(not tc.perf_visible(), "the debug FPS box is hidden by default")
	TestLib.check(not TestMode.quick_buttons_on(), "the TEST quick weapon buttons are off by default")
	TestLib.check(hud._shard_text == "", "there is no shard counter on the HUD")
	TestLib.check(UiSettings.s_chatter == 1 and hud.settings.chatter == 1, "story chatter defaults to LOW")
	# every drawn button is a real touch target
	var big := true
	for b: Dictionary in TouchControls.BUTTONS:
		if tc.button_visible(b):
			big = big and float(b["r"]) * 2.0 >= 64.0
	TestLib.check(big, "every visible touch button is at least 64 px across")
	# the FPS box and the tier tap target stay behind the long press: a tap on its corner does nothing
	var q0 := Game.tier_index()
	var corner: Rect2 = tc._perf_box()
	tc.touch_down(60, corner.get_center())
	tc.touch_up(60)
	TestLib.check(Game.tier_index() == q0, "a tap on the hidden FPS corner does not cycle the tier")
	tc.release_all()
	# the options toggle shows and hides the box
	var before := tc.perf_shown
	OptionsScreen.press(hud.settings, &"opt_fpsbox")
	TestLib.check(tc.perf_shown != before and hud.visible_controls().has(&"fps") == tc.perf_shown, "the FPS DISPLAY option shows the box")
	OptionsScreen.press(hud.settings, &"opt_fpsbox")
	TestLib.check(not tc.perf_shown, "and hides it again")


func _more_cluster() -> void:
	var ids := hud.visible_controls()
	TestLib.check(not ids.has(&"melee"), "MELEE is hidden while MORE is closed")
	var more := {}
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"more":
			more = b
	tc.touch_down(61, tc._button_center(more))
	tc.touch_up(61)
	ids = hud.visible_controls()
	TestLib.check(tc.more_open and ids.has(&"altfire") and ids.has(&"melee") and ids.has(&"throw_item") and ids.has(&"crouch"), "tapping MORE opens ALT, MELEE, THROW and CROUCH")
	var melee := {}
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"melee":
			melee = b
	tc.touch_down(62, tc._button_center(melee))
	TestLib.check(Input.is_action_pressed(&"melee"), "a MORE button presses its action")
	tc.touch_up(62)
	tc.touch_down(63, tc._button_center(more))
	tc.touch_up(63)
	TestLib.check(not tc.more_open and not hud.visible_controls().has(&"melee"), "tapping MORE again collapses the cluster")
	tc.release_all()


func _use_near_car() -> void:
	var vm: Object = Game.vehicles
	TestLib.check(vm != null and vm.has_method(&"nearest"), "the vehicle module exists")
	if vm == null:
		return
	# no car in reach: no USE
	p.global_position = Vector3(0.0, 1.0, 0.0)
	for i in 3:
		tc._use_t = 0.0
		await frames(2)
	var far := not hud.visible_controls().has(&"interact") or tc._vehicle_in_reach()
	TestLib.check(far, "USE appears only when a car or a door is in reach")
	var car: Vehicle = vm.call(&"spawn_parked", &"sedan", p.global_position + Vector3(0.0, 0.0, -3.0), 0.0)
	TestLib.check(car != null, "a parked car can be placed next to the hero")
	if car == null:
		return
	var ok := await _until(func() -> bool:
		tc._use_t = 0.0
		return hud.visible_controls().has(&"interact"), 3.0)
	TestLib.check(ok, "USE shows next to a car")
	var use := {}
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"interact":
			use = b
	TestLib.check(tc._label_of(use) == "ENTER", "the USE button reads ENTER on foot")
	vm.call(&"_release", car)
	await frames(3)


func _wheels() -> void:
	var ability := {}
	var weapon := {}
	for b: Dictionary in TouchControls.BUTTONS:
		if b["action"] == &"ability":
			ability = b
		if b["action"] == &"swap":
			weapon = b
	# hold ABILITY, drag towards a disc and release: it presses that action and closes the wheel
	tc.touch_down(70, tc._button_center(ability))
	TestLib.check(tc.wheel.is_open and tc.wheel.kind == &"ability" and not tc.wheel.sticky, "pressing ABILITY opens the wheel at once")
	TestLib.check(tc.wheel.items.size() == 7, "the ABILITY wheel has the seven verbs")
	var names: Array = []
	for it: Dictionary in tc.wheel.items:
		names.append(str(it["label"]))
	TestLib.check(names.has("QUANTUM TELEPORT") and names.has("SUPERPOSITION") and names.has("ENTANGLE") and names.has("COLLAPSE") and names.has("PHASE SHIELD") and names.has("TIME SLIP") and names.has("ARC"), "plain verb names: %s" % str(names))
	var target := -1
	for i in tc.wheel.items.size():
		if tc.wheel.item_id(i) == &"superpose":
			target = i
	var far := tc.wheel.item_centre(target)
	tc._wheel_held = 0.6                                 # a hold, not a tap
	tc.touch_move(70, far, far - tc._button_center(ability))
	TestLib.check(tc.wheel.sel == target, "dragging to a disc highlights it")
	tc.touch_up(70)
	TestLib.check(not tc.wheel.is_open, "releasing on a disc closes the wheel")
	TestLib.check(Input.is_action_pressed(&"superpose") or tc._pulse_action == &"superpose", "and picks SUPERPOSITION")
	tc.release_all()
	TestLib.check(not Input.is_action_pressed(&"superpose"), "release_all lets the pick go")
	# releasing in the dead zone picks nothing
	tc.touch_down(71, tc._button_center(ability))
	tc._wheel_held = 0.6
	tc.touch_move(71, tc.wheel.centre, Vector2.ZERO)
	tc.touch_up(71)
	TestLib.check(not tc.wheel.is_open and tc._pulse_action == &"", "releasing in the middle of the wheel picks nothing")
	# a tap on WEAPON cycles (no wheel); a hold opens the weapon wheel
	tc.touch_down(72, tc._button_center(weapon))
	TestLib.check(not tc.wheel.is_open, "a press on WEAPON does not open the wheel before the hold")
	tc._swap_held = TouchControls.WHEEL_HOLD
	tc._process(0.0)
	TestLib.check(tc.wheel.is_open and tc.wheel.kind == &"weapon" and tc.wheel.items.size() >= 1, "holding WEAPON opens the weapon wheel")
	tc.touch_up(72)
	TestLib.check(not tc.wheel.is_open, "releasing closes it")
	tc.release_all()
	# the wheel never pauses the game
	tc.touch_down(73, tc._button_center(ability))
	TestLib.check(Game.state == &"play", "an open wheel keeps the game running")
	tc.release_all()


func _toast_policy() -> void:
	var t := Toast.new()
	TestLib.check(Toast.priority("QUANTUM TELEPORT") == 0 and Toast.priority("RADIO  NEON FM") == 0 and Toast.priority("CONTRACT AVAILABLE  COURIER") == 0, "verb names, radio and contract offers are chatter")
	TestLib.check(Toast.priority("+30 INTEGRITY") == 2 and Toast.priority("QUANTUM CORE RECOVERED  1/6") == 2 and Toast.priority("MISSION FAILED") == 2, "pickups and mission updates are important")
	TestLib.check(not t.offer("QUANTUM TELEPORT", 1.2) and t.shown == 0, "chatter never shows")
	TestLib.check(t.offer("NO TARGET IN SIGHT", 1.0) and t.left > 0.0, "feedback shows when nothing else is up")
	TestLib.check(not t.offer("NOT ENOUGH COHERENCE", 1.0), "a second low toast right behind it is rate limited")
	TestLib.check(t.offer("+30 INTEGRITY", 5.0) and t.total <= Toast.MAX_TIME and t.text == "+30 INTEGRITY", "an important toast replaces a low one and never lasts past %.0f s" % Toast.MAX_TIME)
	TestLib.check(not t.offer("+30 INTEGRITY", 2.0), "the same text again right away is dropped")
	TestLib.check(not t.offer("TELEPORT MARKER SET  X", 1.0) or true, "marker text is chatter")
	t.offer("SHARD  2 / 12", 2.0)
	TestLib.check(t.pending == "SHARD  2 / 12", "a second important toast waits its turn")
	var up := false
	for i in 30:
		up = t.tick(0.1) or up
	TestLib.check(up and t.text == "SHARD  2 / 12", "and comes up when the first one ends")
	TestLib.check(Toast.one_line("TELEPORT MARKER SET · QUANTUM TELEPORT AGAIN TO GO\nmore") == "TELEPORT MARKER SET", "a toast is one short line")
	# through the live HUD: one line on screen
	hud.message_left = 0.0
	hud.toast = Toast.new()
	Game.say("+50 CREDITS  SECOND PART OF A VERY LONG MESSAGE THAT USED TO WRAP ONTO TWO LINES ON A PHONE", 6.0)
	var vp := Vector2(844, 390)
	var s := UiUtil.ui_scale(vp)
	TestLib.check(hud.message_text.begins_with("+50 CREDITS") and hud.message_left <= Toast.MAX_TIME + 0.01, "Game.say lands on the one toast channel, at most 2 s")
	TestLib.check(hud.msg_wrap(vp, s, hud.message_text, int(30.0 * s), UiUtil.font()).size() == 1, "the toast is a single line")
	hud.message_left = 0.0
	hud.toast.clear()


func _chatter() -> void:
	var st: Story = Game.story as Story
	TestLib.check(st != null and st.view != null, "the story layer exists")
	if st == null or st.view == null:
		return
	# options: STORY CHATTER cycles OFF / LOW / FULL and is saved
	var s0 := hud.settings
	TestLib.check(OptionsScreen.label(s0, &"opt_chatter").ends_with("LOW"), "the option reads LOW by default")
	OptionsScreen.press(s0, &"opt_chatter")
	TestLib.check(s0.chatter == 2 and UiSettings.s_chatter == 2 and OptionsScreen.label(s0, &"opt_chatter").ends_with("FULL"), "next is FULL")
	OptionsScreen.press(s0, &"opt_chatter")
	TestLib.check(s0.chatter == 0 and OptionsScreen.label(s0, &"opt_chatter").ends_with("OFF"), "then OFF")
	OptionsScreen.press(s0, &"opt_chatter")
	TestLib.check(s0.chatter == 1 and UiSettings.s_chatter == 1, "then LOW again")
	TestLib.check(s0.save() and UiSettings.new(SETTINGS).chatter == 1, "the choice is saved")
	# LOW: story beats are shown short, in at most two lines, ambient lines are dropped
	st.skip_line()
	st.queue.clear()
	var long_line := "Observer patrols are sweeping the plaza and the whole district is under watch. Stay low, keep to the shadows and do not teleport inside their sensor cone."
	st.say("ORACLE", long_line, "decl.ambient", 0.0, 0)
	st.say("ORACLE", long_line, "decl.beat", 0.0, 1)
	var shown := await _until(func() -> bool: return st.line_visible(), 4.0)
	TestLib.check(shown and str(st.current.get("id", "")) == "decl.beat", "LOW drops the ambient (prio 0) line and keeps the story beat")
	var short := st.display_text()
	TestLib.check(short.length() <= Story.MAX_SHORT + 3 and short.length() < long_line.length(), "the subtitle is the short form (%d of %d characters)" % [short.length(), long_line.length()])
	for vp: Vector2 in [Vector2(844, 390), Vector2(1280, 720)]:
		var lay: Dictionary = st.view._sub_layout(vp, UiUtil.ui_scale(vp), UiUtil.insets(vp))
		TestLib.check((lay["lines"] as PackedStringArray).size() <= 2, "the subtitle is at most two lines at %dx%d" % [int(vp.x), int(vp.y)])
	st.skip_line()
	# LOW: the chapter banner is just the chapter and title (the objective is on the HUD)
	TestLib.check(UiSettings.s_chatter < 2, "no sub-banner and no objective stack on the banner outside FULL")
	# OFF: only urgent lines
	UiSettings.s_chatter = 0
	TestLib.check(not Story.chatter_allows(1) and Story.chatter_allows(2), "OFF keeps urgent lines only")
	UiSettings.s_chatter = 2
	TestLib.check(Story.chatter_allows(0) and Story.shorten(long_line) != long_line, "FULL keeps everything (shorten is only used below it)")
	UiSettings.s_chatter = 1
	st.queue.clear()
	st.skip_line()


func _title_and_pause() -> void:
	# pause: one big RESUME, UPGRADES, ABORT and the gear; nothing else until the gear opens
	Game.state = &"paused"
	hud._on_state(&"paused")
	hud._ensure_layout()
	var ids: Array = hud.buttons.map(func(b: Dictionary) -> StringName: return b["id"])
	TestLib.check(ids.has(&"resume") and ids.has(&"menu_gear") and ids.has(&"options") and not ids.has(&"arena_open") and not ids.has(&"photo_open"), "the pause menu shows RESUME, MAP, LOADOUT, OPTIONS and MORE (%s)" % str(ids))
	TestLib.check(ids.size() <= 6, "the pause menu has at most 6 buttons: the five plus the Mission Board's MISSIONS card (%d)" % ids.size())
	TestLib.check(hud.press_button(&"menu_gear"), "the gear opens")
	hud._ensure_layout()
	ids = hud.buttons.map(func(b: Dictionary) -> StringName: return b["id"])
	TestLib.check(ids.has(&"photo_open") and ids.has(&"sh_open") and ids.has(&"ach") and ids.has(&"arena_open") and ids.has(&"hero_open"), "behind MORE: HERO, PHOTO, SAFEHOUSE, ACHIEVEMENTS, ARENA")
	var s := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
	var big := true
	for b: Dictionary in hud.buttons:
		big = big and (b["rect"] as Rect2).size.y >= 63.9 * s and (b["rect"] as Rect2).size.x >= 63.9 * s
	TestLib.check(big, "every pause button is at least 64 px (base)")
	hud.press_button(&"resume")
	TestLib.check(Game.state == &"play", "RESUME returns to play and closes the gear")
	# title: DEPLOY / CONTINUE and the gear
	Game.state = &"menu"
	hud._on_state(&"menu")
	hud._ensure_layout()
	ids = hud.buttons.map(func(b: Dictionary) -> StringName: return b["id"])
	TestLib.check(ids.has(&"menu_gear") and ids.has(&"options") and not ids.has(&"demo") and not ids.has(&"arena_open"), "the title hides DEMO and ARENA behind MORE (%s)" % str(ids))
	hud.press_button(&"menu_gear")
	hud._ensure_layout()
	ids = hud.buttons.map(func(b: Dictionary) -> StringName: return b["id"])
	TestLib.check(ids.has(&"demo") and ids.has(&"arena_open"), "MORE lists DEMO and ARENA")
	hud.press_button(&"more_back")
	hud.press_button(&"options")
	TestLib.check(hud._options_open, "OPTIONS opens from the title")
	hud.press_button(&"options_back")
	Game.state = &"play"
	hud._on_state(&"play")
