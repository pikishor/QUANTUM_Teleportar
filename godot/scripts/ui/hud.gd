class_name Hud
extends CanvasLayer
## The HUD and every screen around the game (ARCHITECTURE.md, hud / ui). Reads Game.* and Game.player only, never node paths.
## While playing: integrity / coherence / hull bars, ammo or km/h, heat stars, credits, objective with the distance to the nearest core, centre messages,
## vehicle hint, crosshair with the weapon spread, hit marker, damage vignette and direction, quantum power hints, the minimap and (on touchscreens) the
## touch controls (a TouchControls child). Screens: title/menu, pause, dead (DECOHERED), win (SECTOR STABILIZED). Settings and the best score persist
## through UiSettings (user://settings.cfg). Pausing sets Game.state = &"paused" only, never get_tree().paused.

const LOCK := 0.8                   ## seconds after dying / winning before a tap continues (a firing finger must not skip the screen)
const REACH := 4.2                  ## metres: a vehicle this close can be entered (interact)
const TIER_NAMES: Array[String] = ["LOW", "MED", "HIGH"]
const VIGNETTE_MAX := 0.35          ## hard cap of the one damage vignette's alpha: the world stays readable, never a screen fill
const HURT_TIME := 0.45             ## seconds the hit vignette lasts
const MARKER_TIME := 1.0            ## seconds the attacker marker lasts
const DEAD_DIM := 0.30              ## alpha of the DECOHERED / SECTOR STABILIZED dimming (never above 0.35)
const PAUSE_SETTINGS_Y := 448.0     ## base px: first settings row of the pause screen with progress (under the 64 px UPGRADES / CHAPTERS row)
## Centre message (toast) region: a plate directly under the top stack, between the radio subtitle column and the right-hand plates, so it never covers the hero (who
## stands in the middle of the screen) or the minimap. `msg_rect` is the plate; the quantum readout hangs under it. Same lane width as the chapter banner (story_view.gd).
const TITLE_SIZE := 64.0            ## base px: the game name on the title (narrow enough that the TEST badge and DEMO / ARENA never touch its letters)
const SUBSCREEN_DIM := 0.86          ## backdrop of the full-screen pause panels (skills, gear, look, shop...): the world and the HUD behind recede so the panel's labels never fight them
const MSG_H := 46.0                 ## base px: plate height
const MSG_GAP := 6.0                ## base px: below UiUtil.stack_bottom
const TAB_W := 180.0                ## base px: the DEMO / ARENA tabs top left of the title
const TAB_GAP := 14.0               ## base px between the tabs
const TITLE_PLATE_PAD := 16.0       ## base px the title block's backing plate extends past the text
const SUB_LANE := 320.0 + 34.0      ## base px of the radio subtitle column (StoryView.SUB_W) plus its margin
const MINIMAP := 148.0              ## base px: the round minimap, top left
const SLIM_W := 190.0               ## base px of a slim status bar (phone HUD: no captions, no numbers; the colour and the length say it)
const SLIM_H := 11.0
const SLIM_PITCH := 17.0
const BAR_W := 190.0                ## base px of an integrity / coherence / hull bar
const LABEL_W := 92.0               ## base px: the least width of the caption column left of the bars (it grows to fit the widest caption in the font in use)
const VALUE_W := 54.0
## Volume sliders of the settings rows: slider id -> the buses it sets (saved in settings.volumes). SFX also carries the ambience beds and the radio voice.
const SLIDERS := {&"vol_music": ["Music"], &"vol_sfx": ["SFX", "Ambient", "Voice"]}
const CONTROLS_DESKTOP := "WASD MOVE    MOUSE LOOK    LMB FIRE    RMB AIM    SHIFT SPRINT    SPACE JUMP    R RELOAD    Q QUANTUM TELEPORT    E ENTANGLE    G SUPERPOSE    F USE    ESC PAUSE"
const CONTROLS_PAD_PLAY := "LEFT STICK MOVE    RIGHT STICK LOOK    RT FIRE    LT AIM    A JUMP    X RELOAD    Y USE    RB TELEPORT    D-PAD ABILITIES    LB HELD: VERBS    START PAUSE"
const CONTROLS_PAD_MENU := "D-PAD MOVE    A SELECT    B BACK    LB RB ADJUST    START RESUME"
const CONTROLS_TOUCH := "LEFT THUMB MOVE (PUSH FAR TO SPRINT)    RIGHT THUMB LOOK    HOLD FIRE TO SHOOT AND AIM AT ONCE"

@export var settings_path := UiSettings.DEFAULT_PATH
var settings: UiSettings
var minimap: Minimap
var pad: ControllerInput            ## gamepad input (scripts/ui/controller_input.gd): play actions, menu focus, haptics, touch / pad scheme switch
var touch: TouchControls
## Active screen buttons: {id: StringName, rect: Rect2, label: String, on: bool}. Rebuilt whenever the state or the viewport changes.
var buttons: Array[Dictionary] = []
var screen_age := 0.0               ## seconds since the current state began
var toast := Toast.new()            ## the one toast channel (scripts/ui/toast.gd): message_text / message_left mirror it
var message_text := ""
var message_left := 0.0
var new_best := false

var _hud: Control
var _screen: Control
var _msg_total := 1.0
var _hover := &""
var _layout_key := ""
var _obj_text := ""
var _cred_text := ""
var _shard_text := ""               ## I2 tracker under the credits plate
var _contract_text := ""
var _gear_open := false            ## the MORE page of the title / pause screen is open (the name is historic: it was a gear drop-down)
var _hero_hub := false             ## the HERO hub (UPGRADES / WEAPONS / SKILLS / CRAFT tabs) is open: one tab bar over the shop, skills and workbench screens
var _look_open := false             ## G2: the pause shop shows the hero suit / colour screen (scripts/ui/look_screen.gd)
var _loadout_open := false          ## the pause screen shows the weapon wheel and attachment loadout
var _loadout_page := 0             ## 0 weapons and attachments, 1 GEAR (throwables, gadget, saved loadouts: scripts/ui/gear_screen.gd)
var _loadout_quick := false         ## opened from the wheel gesture: a pick resumes the game
var _loadout_w: StringName = &"carbine"  ## the weapon whose slots the loadout shows
var _skills_open := false          ## the pause screen shows the skill tree (scripts/ui/skill_screen.gd)
var _ach_open := false             ## the pause screen shows the achievements (scripts/ui/achievements_screen.gd)
var _ach_page := 0
var _shop_open := false             ## the pause screen shows the upgrade shop instead of the settings
var _options_open := false          ## the title / pause screen shows the options (scripts/ui/options_screen.gd)
var _arena_open := false            ## the boss rush / arena planning screen is open (title or pause; scripts/ui/arena_board.gd)
var _grabbing := false              ## a photo is being grabbed: the controls are hidden on purpose for a few frames
var photo: PhotoMode                ## PHOTO MODE (scripts/ui/photo_mode.gd): free camera while the game stays paused; controls in scripts/ui/photo_screen.gd
var _craft_open := false            ## the pause screen shows the workbench (scripts/ui/craft_screen.gd), over the shop, a safehouse or the DEMO menu
var _safe_open := false             ## the pause menu shows the safehouse screen (scripts/ui/safehouse_screen.gd)
var _heist_open := false            ## the pause shop shows the heist planning screen (scripts/ui/heist_board.gd)
var _side_open := false             ## the pause shop shows the side-mission board (scripts/ui/side_board.gd)
var _board_open := false            ## the Mission Board screen is open (scripts/ui/mission_board_screen.gd; opened from the pause menu, the map, the result card's NEXT)
var _chapters_open := false         ## the title / pause screen shows the chapter select (scripts/ui/chapter_select.gd)
var _camp_text := ""                ## the scripted campaign step's HUD line (CampaignRunner.hud_line), "" when none runs
var _has_save := false              ## a save file exists (the title offers CONTINUE)
var _hint_text := ""
var _text_t := 0.0
var _ammo_key := -1
var _radio_show := 0.0              ## seconds the car radio line stays up after a station change
var _radio_last := ""
var _ammo_text := ""
const WEAPON_POP_MS := 2200
var _star := PackedVector2Array()
var _vignette: GradientTexture2D
var _mouse_captured := false
var _lw := LABEL_W                  ## base px of the caption column, measured per scale (see _caption_width)
var _lw_key := -1
var _drag := &""                    ## the volume slider a finger / the mouse is dragging
var _t := 0.0
var _seen_hit := -100.0              ## last_hit_time already answered with a hit-confirm camera tick
var _q: Array = []                  ## queued draws (see _text): text, rectangles, sprites, outlines
var _fills: Array = []
var scan_text := false                ## tests/test_menus_map_quality.gd: record every queued text (text, rect, size) into scan_log while a screen draws
var scan_hud := false                  ## tests/test_mission_board.gd: scan_text also records the play HUD layer (the objective line, the toast), not only the menu layer
var scan_log: Array[Dictionary] = []
var _frames: Array = []
var _sprites: Array = []


func _ready() -> void:
	layer = 10
	add_to_group(&"hud")
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings = UiSettings.new(settings_path)
	photo = PhotoMode.new()
	photo.name = "Photo"
	add_child(photo)
	_hud = _make_canvas("Hud")
	_screen = _make_canvas("Screen")
	_hud.draw.connect(_draw_hud)
	_screen.draw.connect(_draw_screen)
	minimap = Minimap.new()
	minimap.name = "Minimap"
	_hud.add_child(minimap)
	touch = get_node_or_null("Touch") as TouchControls
	if touch != null:
		touch.pause_requested.connect(pause_game)
		touch.wheel_requested.connect(open_wheel)
	pad = ControllerInput.new()
	pad.name = "Pad"
	add_child(pad)
	var wd := ScreenWatchdog.new()
	add_child(wd)                                   # a BACK button after 5 s without progress on any closable screen (no screen can trap the player)
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		_star.append(Vector2(cos(a), sin(a)) * (1.0 if i % 2 == 0 else 0.45))
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.62, 1.0])        # clear in the middle 60 %, the colour gathers only at the very edge
	g.colors = PackedColorArray([Color(0.85, 0.02, 0.06, 0.0), Color(0.85, 0.02, 0.06, 1.0)])
	_vignette = GradientTexture2D.new()
	_vignette.gradient = g
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(1.0, 0.5)
	_vignette.width = 128
	_vignette.height = 128
	Game.message.connect(_on_message)
	Game.state_changed.connect(_on_state)
	Game.new_game.connect(func() -> void: new_best = false)
	var tool_quality := false
	for a in OS.get_cmdline_user_args():
		tool_quality = tool_quality or a.begins_with("--quality=")
	if not Game.autostart and not tool_quality and settings.quality >= 0:
		Game.quality = settings.quality             # main.gd applies it to the world and the atmosphere after composing the modules
		Game.low_plus = settings.low_plus and settings.quality == 0
	if not Game.autostart:
		apply_settings(false)
	_on_state(Game.state)


func _exit_tree() -> void:
	if _mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _make_canvas(node_name: String) -> Control:
	var c := Control.new()
	c.name = node_name
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


## Pushes the saved choices to the services that own them: post-process, mute, and (when `with_quality`) the graphics tier.
func apply_settings(with_quality := true) -> void:
	settings.publish()
	if is_instance_valid(Game.atmosphere):
		Game.atmosphere.set(&"enabled", settings.post)
	Sfx.muted = settings.muted
	Sfx.apply_volumes(settings.volumes)
	if with_quality and settings.quality >= 0:
		Game.set_tier_index(0 if (settings.quality == 0 and settings.low_plus) else settings.quality + 1)


# ---------------------------------------------------------------------------------------------------------------------
# state, pause, best score, mouse
# ---------------------------------------------------------------------------------------------------------------------

func _on_state(s: StringName) -> void:
	if photo != null and photo.active:
		photo.end()                                            # any state change (RESUME, death, a cutscene) leaves photo mode and restores the camera
	screen_age = 0.0
	_hover = &""
	_shop_open = false
	_ach_open = false
	_skills_open = false
	_side_open = false
	_board_open = false
	_heist_open = false
	_safe_open = false
	_craft_open = false
	_arena_open = false
	_loadout_open = false
	_loadout_page = 0
	_look_open = false
	_loadout_quick = false
	_chapters_open = false
	_options_open = false
	_gear_open = false
	_hero_hub = false
	if s == &"menu":
		_has_save = Game.progress != null and bool(Game.progress.call(&"has_save"))
	if s == &"dead" or s == &"win":
		record_best()
	_hud.visible = _hud_wanted()        # a cutscene (scripts/cinematics) owns the whole picture
	_screen.visible = s != &"play" and s != &"cutscene" and not InteriorGameplay.vendor_open and not MapScreen.up      # the vendor window and the open map are their own layers (no pause menu drawn under the map)
	minimap.visible = _hud.visible
	_layout_key = ""
	_apply_mouse()


## True while a full-screen pause panel (shop, skills, gear, look, boards, options...) is open: it owns the whole picture, the gameplay HUD and minimap are hidden behind it.
func panel_cover() -> bool:
	return Game.state == &"paused" and not photo_open()


## What the gameplay HUD layer (and the minimap on it) should show: not in the title, a cutscene, photo mode or behind a full-screen pause panel.
func _hud_wanted() -> bool:
	return Game.state != &"menu" and Game.state != &"cutscene" and not photo_open() and not panel_cover() and not MapScreen.up


## True while photo mode runs (the gameplay HUD is hidden, the photo controls are the screen).
func photo_open() -> bool:
	return photo != null and photo.active and Game.state == &"paused"


## Photo mode started / ended / toggled its UI: the gameplay HUD and minimap stay hidden, the screen layer follows `hide_ui` only while a photo is grabbed.
func photo_layers() -> void:
	var on := photo_open()
	_hud.visible = _hud_wanted()
	minimap.visible = _hud.visible
	_layout_key = ""
	_screen.queue_redraw()


## SHOT: the controls vanish for the grab (true), then come back (false).
## The map opened / closed: the pause screen under it is not drawn (the map is the screen), and comes back when the map closes over a pause menu.
func map_toggled(on: bool) -> void:
	_screen.visible = not on and Game.state != &"play" and Game.state != &"cutscene" and not InteriorGameplay.vendor_open and not _grabbing
	_hud.visible = _hud_wanted()
	minimap.visible = _hud.visible
	if not on:
		_layout_key = ""
		_screen.queue_redraw()


func photo_grab(on: bool) -> void:
	_grabbing = on                                                  # layers_consistent() lets the hidden controls be: the stability audit repairing them mid-grab ended photo mode (soak under a real renderer)
	_screen.visible = not on and Game.state != &"play" and Game.state != &"cutscene"


## True when the HUD and screen layers show what the state asks for (HUD hidden only in the menu, the screen layer hidden only while playing).
func layers_consistent() -> bool:
	if _grabbing:
		return true
	var cine := Game.state == &"cutscene"
	var base := Game.state != &"menu" and not cine and not photo_open() and not MapScreen.up
	var hud_ok := (_hud.visible == base) if not panel_cover() else (_hud.visible == base or not _hud.visible)      # a panel opening hides the HUD in the next _process: either state is fine until then
	return hud_ok and _screen.visible == (Game.state != &"play" and not cine and not InteriorGameplay.vendor_open and not MapScreen.up) and minimap.visible == _hud.visible


## Puts the layers back in line with the state (the stability audit calls it when they drifted).
func refresh_layers() -> void:
	_on_state(Game.state)


## True while the paused game shows the upgrade shop (the cinematics frame a close-up of the hero beside it).
func shop_open() -> bool:
	return _shop_open and Game.state == &"paused"


func record_best() -> void:
	if Game.score > settings.best:
		settings.best = Game.score
		new_best = true
		settings.save()


func pause_game() -> void:
	if Game.state == &"play":
		Game.state = &"paused"


## The weapon wheel: pauses (Game.state only) and shows the loadout screen; picking a weapon resumes.
func open_wheel() -> void:
	if Game.state != &"play" or Game.progress == null:
		return
	Game.state = &"paused"
	_loadout_open = true
	_loadout_quick = true
	_loadout_w = WeaponDefs.last_used
	LoadoutScreen.reset_page()
	_layout_key = ""


func loadout_open() -> bool:
	return _loadout_open and Game.state == &"paused"


func toggle_pause() -> void:
	if Game.state == &"play":
		Game.state = &"paused"
	elif Game.state == &"paused":
		Game.state = &"play"


## Every control and read-out of a play frame, by id (the declutter contract: at most 12 in a default frame, tests/test_hud_declutter.gd). Touch: the stick, the visible buttons
## (the ammo count rides on the WEAPON button) and pause; always: the minimap, the status bars and the one objective line; plus whatever is up right now (toast, subtitle,
## wanted stars, FPS box, boss bar).
func visible_controls() -> Array[StringName]:
	var out: Array[StringName] = []
	if Game.state != &"play" or not _hud.visible:
		return out
	if touch != null:
		out.append_array(touch.visible_ids())
	out.append_array([&"minimap", &"status", &"objective"])
	if not touch_ui_on():
		out.append(&"ammo")
	if Game.heat > 0.01:
		out.append(&"wanted")
	if message_left > 0.0 and message_text != "" and not banner_busy():
		out.append(&"toast")
	if is_instance_valid(Game.story) and Game.story.line_visible() and UiSettings.s_subtitles:
		out.append(&"subtitle")
	if touch != null and touch.perf_visible():
		out.append(&"fps")
	return out


func touch_ui_on() -> bool:
	return touch != null and touch.controls_on


## Desktop: the mouse is captured while playing (mouse look), released in every other state. Never under tools/tests or with the touch overlay.
func wants_mouse_capture() -> bool:
	return Game.state == &"play" and not touch_ui_on() and not ControllerInput.pad_ui and not Game.autostart and DisplayServer.get_name() != "headless"


func _apply_mouse() -> void:
	var want := wants_mouse_capture()
	if want != _mouse_captured:
		_mouse_captured = want
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if want else Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if (what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT) and not Game.autostart:
		pause_game()


# ---------------------------------------------------------------------------------------------------------------------
# input on the screens
# ---------------------------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if MapScreen.up:
		return                                                      # the open map owns every key and tap (Esc / back close it there); the pause menu under it must not react
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.is_action_pressed(&"pause"):
				if photo_open():
					photo.end()                                         # Esc leaves photo mode for the pause menu
					get_viewport().set_input_as_handled()
				elif Game.state == &"play" or Game.state == &"paused":
					toggle_pause()
					get_viewport().set_input_as_handled()
			elif k.keycode == KEY_K and Game.state == &"play" and skip_available():
				skip_set_piece()
			elif Game.state != &"play" and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_SPACE):
				_confirm()
	elif Game.state == &"play":
		return
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			tap(mb.position)
		elif not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			end_drag()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			tap(st.position)
		else:
			end_drag()
	elif event is InputEventScreenDrag and _drag != &"":
		slide(_drag, (event as InputEventScreenDrag).position.x)
	elif event is InputEventMouseMotion:
		if _drag != &"":
			slide(_drag, (event as InputEventMouseMotion).position.x)
			return
		var h := _button_at((event as InputEventMouseMotion).position)
		if h != _hover:
			_hover = h
			_screen.queue_redraw()


## Enter / Space on a screen: DEPLOY, RESUME, respawn, next sector.
func _confirm() -> void:
	match Game.state:
		&"menu": press_button(&"deploy")
		&"paused": press_button(&"resume")
		&"dead": press_button(&"respawn")
		&"win": press_button(&"next")


## A press (mouse or finger) on a screen. Returns true when it did something. On the dead and win screens a tap anywhere continues after LOCK seconds.
func tap(pos: Vector2) -> bool:
	if Game.state == &"play" or Game.state == &"cutscene":
		return false
	_ensure_layout()
	var id := _button_at(pos)
	if SLIDERS.has(id) or (_options_open and OptionsScreen.is_slider(id)) or (photo_open() and PhotoScreen.is_slider(id)):
		_drag = id
		slide(id, pos.x)
		return true
	if id != &"":
		return press_button(id)
	if Game.state == &"dead":
		return press_button(&"respawn")
	if Game.state == &"win":
		return press_button(&"next")
	return false


func _button_at(pos: Vector2) -> StringName:
	_ensure_layout()
	for b: Dictionary in buttons:
		if (b["rect"] as Rect2).grow(4.0).has_point(pos):
			return b["id"]
	return &""


## The suit screen's buttons (`look_*`): equip or buy a suit / scheme / accent hue; `look_back` returns to the shop.
func _press_look(sid: String) -> bool:
	if sid == "look_back":
		if not _look_open:
			return false
		_look_open = false
		Sfx.play(&"ui_back")
		_layout_key = ""
		_screen.queue_redraw()
		return true
	if Game.state != &"paused" or not _look_open or Game.progress == null:
		return false
	var prog := Game.progress as Progress
	var cos: Array = prog.achievements.cosmetics
	var key := ""
	var ok := false
	if sid.begins_with("look_suit_"):
		key = "suit:%s" % sid.substr(10)
		ok = prog.hero.is_unlocked(key, cos) or prog.buy_look(key)
		ok = ok and prog.hero.equip_suit(StringName(sid.substr(10)), cos)
	elif sid.begins_with("look_scheme_"):
		var i := int(sid.substr(12))
		key = "scheme:%d" % i
		ok = prog.hero.is_unlocked(key, cos) or prog.buy_look(key)
		ok = ok and prog.hero.equip_scheme(i, cos)
	elif sid.begins_with("look_person_"):
		ok = LookScreen.press_person(prog.hero, sid.substr(12))
	elif sid == "look_hue_buy":
		ok = prog.buy_look("accent")
	elif sid.begins_with("look_hue_"):
		ok = prog.hero.set_accent(int(sid.substr(9)))
	Sfx.play(&"ui_purchase" if ok else &"ui_deny")
	_layout_key = ""
	_screen.queue_redraw()
	return ok


## The effect of every screen button (the tests press them through here).
func press_button(id: StringName) -> bool:
	var sid := String(id)
	if sid.begins_with("photo_"):
		return _press_photo(sid)
	if sid.begins_with("look_") and sid != "look_open":
		return _press_look(sid)
	if sid == "loadout_info":                                           # the weapon of the loadout, opened as a card in the WEAPONS catalogue
		if Game.state != &"paused" or not _loadout_open or Game.progress == null:
			return false
		_loadout_open = false
		_loadout_page = 0
		_shop_open = true
		_hero_hub = true
		_skills_open = false
		_craft_open = false
		WeaponsScreen.select(_loadout_w)
		Sfx.play(&"ui_confirm")
		_layout_key = ""
		_screen.queue_redraw()
		return true
	if sid == "loadout_gear" or sid == "gear_weapons":
		if Game.state != &"paused" or not _loadout_open or Game.progress == null:
			return false
		_loadout_page = 1 if sid == "loadout_gear" else 0
		Sfx.play(&"ui_confirm")
		_layout_key = ""
		_screen.queue_redraw()
		return true
	if sid.begins_with("gt_") or sid.begins_with("gg_") or sid.begins_with("ls_") or sid.begins_with("lsave_"):
		if Game.state != &"paused" or not _loadout_open or _loadout_page != 1:
			return false
		var done := GearScreen.press(sid)
		_layout_key = ""
		_screen.queue_redraw()
		return done
	if sid.begins_with("sk_") and sid != "sk_back":
		if Game.state != &"paused" or not _skills_open:
			return false
		var sdone := SkillScreen.press(sid)
		_layout_key = ""
		_screen.queue_redraw()
		return sdone
	if sid.begins_with("wheel_") or sid.begins_with("part_"):
		if Game.state != &"paused" or not _loadout_open or Game.progress == null:
			return false
		var prog := Game.progress as Progress
		if sid.begins_with("wheel_"):
			var wid := StringName(sid.substr(6))
			if not WeaponDefs.is_unlocked(wid):
				return false
			_loadout_w = wid
			var pl := Game.player
			if is_instance_valid(pl) and pl.get(&"weapon") is PlayerWeapon:
				(pl.get(&"weapon") as PlayerWeapon).switch_to(wid)
			Sfx.play(&"ui_tap")
			if _loadout_quick:
				Game.state = &"play"
				return true
		else:
			var part := StringName(sid.substr(5))
			if not Attachments.PARTS.has(part):
				return false
			if not Attachments.is_owned(part) and not prog.buy_part(part):
				Sfx.play(&"ui_deny")
				return false
			if Attachments.part_in(_loadout_w, Attachments.slot_of(part)) != part or Attachments.is_owned(part):
				prog.equip_part(_loadout_w, part)
			Sfx.play(&"ui_purchase")
		_layout_key = ""
		_screen.queue_redraw()
		return true
	if sid.begins_with("sh_"):
		return _press_safehouse(sid)
	if sid.begins_with("cr_"):
		return _press_craft(sid)
	if sid.begins_with("board_"):
		return _press_board(sid)
	if sid.begins_with("heist_"):
		return _press_heist(sid)
	if sid.begins_with("arena_"):
		return _press_arena(sid)
	if sid.begins_with("side_") and SideMissions.DEFS.has(StringName(sid.substr(5))):
		var sm := (Game.missions as Missions).sides if Game.missions is Missions else null
		if Game.state != &"paused" or not _side_open or sm == null or not sm.can_start(StringName(sid.substr(5))):
			Sfx.play(&"ui_deny")
			return false
		Game.state = &"play"                                           # _on_state closes the board; the job starts in the live city
		sm.start(StringName(sid.substr(5)))
		Sfx.play(&"ui_contract_accept")
		return true
	if sid.begins_with("wsel_") or sid.begins_with("wpg_") or sid.begins_with("wequip_") or sid.begins_with("wgear_"):      # the WEAPONS catalogue (scripts/ui/weapons_screen.gd)
		if Game.state != &"paused" or not _shop_open or Game.progress == null or ShopScreen.weapon_page == 0:
			return false
		var wdone := WeaponsScreen.press(sid)
		_layout_key = ""
		_screen.queue_redraw()
		return wdone
	if sid.begins_with("buy_") and WeaponDefs.DEFS.has(StringName(sid.substr(4))):
		if Game.state != &"paused" or not _shop_open or Game.progress == null:
			return false
		if not bool(Game.progress.call(&"buy_weapon", StringName(sid.substr(4)))):
			Sfx.play(&"ui_deny")
			return false
		Sfx.play(&"ui_purchase")
		_layout_key = ""
		_screen.queue_redraw()
		return true
	if sid.begins_with("buy_"):
		if Game.state != &"paused" or not _shop_open or Game.progress == null:
			return false
		if not bool(Game.progress.call(&"buy", StringName(sid.substr(4)))):
			Sfx.play(&"ui_deny")                                       # not enough credits (or the upgrade is maxed)
			return false
		Sfx.play(&"ui_upgrade" if (Game.progress as Progress).level(StringName(sid.substr(4))) >= Upgrades.MAX_LEVEL else &"ui_purchase")
		_layout_key = ""
		_screen.queue_redraw()
		return true
	if sid.begins_with("chapter_") and sid != "chapters_back":
		if not _chapters_open or Game.progress == null:
			return false
		if not bool(Game.progress.call(&"start_chapter", sid.substr(8).to_int())):
			Sfx.play(&"ui_deny")
			return false
		Sfx.play(&"ui_confirm")
		_chapters_open = false
		_layout_key = ""
		_screen.queue_redraw()
		return true
	if ControlsScreen.is_id(id):                          # the CONTROLS remap screen (options page 2)
		if not _options_open or UiSettings.s_opt_page != 2:
			return false
		Sfx.play(&"ui_tap")
		var cok := ControlsScreen.press(settings, id)
		settings.publish(false)
		settings.save()
		_layout_key = ""
		_screen.queue_redraw()
		return cok
	if OptionsScreen.is_option(id):
		if not _options_open or OptionsScreen.is_slider(id):
			return false
		Sfx.play(&"ui_tap")
		OptionsScreen.press(settings, id)
		if Game.state == &"menu":                           # RESET PROGRESS removes the save: the title must stop offering CONTINUE
			_has_save = Game.progress != null and bool(Game.progress.call(&"has_save"))
		apply_settings(false)
		settings.save()
		_layout_key = ""
		_screen.queue_redraw()
		return true
	match id:
		&"menu_gear":                                                 # EXTRAS: opens the page of everything that is not on the main screen; a screen opened from it returns to it
			if (Game.state != &"menu" and Game.state != &"paused") or not _main_screen():
				return false
			_gear_open = not _gear_open
			Sfx.play(&"ui_confirm" if _gear_open else &"ui_back")
		&"more_back":
			if not _gear_open:
				return false
			_gear_open = false
			Sfx.play(&"ui_back")
		&"pause_map":
			if Game.state != &"paused" or Game.progress == null or touch == null or not _main_screen():
				return false
			Sfx.play(&"ui_confirm")
			touch.open_map()
		&"options":
			if Game.state != &"menu" and Game.state != &"paused":
				return false
			_options_open = true
			UiSettings.s_opt_page = 0
			UiSettings.s_opt_tab = 0
			Sfx.play(&"ui_confirm")
		&"options_back":
			if not _options_open:
				return false
			_options_open = false
			OptionsScreen.reset_armed = false
			OptionsScreen.reset_demo_armed = false
			UiSettings.s_opt_page = 0
			UiSettings.s_opt_tab = 0
			Sfx.play(&"ui_back")
		&"chapters":
			if (Game.state != &"menu" and Game.state != &"paused") or not _chapters_ok():
				return false
			_chapters_open = true
			Sfx.play(&"ui_confirm")
		&"chapters_back":
			if not _chapters_open:
				return false
			_chapters_open = false
			Sfx.play(&"ui_back")
		&"continue":
			if Game.state != &"menu" or Game.progress == null or not _has_save:
				return false
			if not bool(Game.progress.call(&"continue_game")):
				return false
			Sfx.play(&"ui_confirm")
		&"shop", &"hero_open":                                        # the HERO hub: UPGRADES / WEAPONS / SKILLS / CRAFT tabs over one screen
			if Game.state != &"paused" or Game.progress == null:
				return false
			_shop_open = true
			_hero_hub = true
			_skills_open = false
			_craft_open = false
			ShopScreen.weapon_page = 0                            # always the upgrades page first
			Sfx.play(&"ui_confirm")
		&"hero_tab_up", &"hero_tab_weapons", &"hero_tab_skills", &"hero_tab_craft":
			if Game.state != &"paused" or Game.progress == null or not _hero_hub:
				return false
			_shop_open = true
			_skills_open = id == &"hero_tab_skills"
			if id == &"hero_tab_craft":
				if not _craft_open:
					CraftScreen.reset_state()
				_craft_open = true
			else:
				_craft_open = false
			if id == &"hero_tab_up" or id == &"hero_tab_weapons":
				ShopScreen.weapon_page = 0 if id == &"hero_tab_up" else 1
			Sfx.play(&"ui_tap")
		&"loadout":
			if Game.state != &"paused" or Game.progress == null or _loadout_open:
				return false
			_loadout_open = true
			_loadout_quick = false
			_loadout_w = WeaponDefs.last_used
			LoadoutScreen.reset_page()
			Sfx.play(&"ui_confirm")
		&"skills_open":
			if Game.state != &"paused" or Game.progress == null or _skills_open:
				return false
			_skills_open = true
			Sfx.play(&"ui_confirm")
		&"sk_back":
			if Game.state != &"paused" or not _skills_open:
				return false
			_skills_open = false
			_close_hero()
			Sfx.play(&"ui_back")
		&"look_open":
			if Game.state != &"paused" or Game.progress == null or _look_open:
				return false
			_look_open = true
			Sfx.play(&"ui_confirm")
		&"wheelpg_prev", &"wheelpg_next":
			if Game.state != &"paused" or not _loadout_open or not LoadoutScreen.flip(-1 if id == &"wheelpg_prev" else 1):
				return false
			Sfx.play(&"ui_tap")
		&"shop_wpage":
			if Game.state != &"paused" or not _shop_open:
				return false
			ShopScreen.flip()
			Sfx.play(&"ui_tap")
		&"loadout_back":
			if Game.state != &"paused" or not _loadout_open:
				return false
			_loadout_open = false
			_loadout_page = 0
			Sfx.play(&"ui_back")
			if _loadout_quick:
				_loadout_quick = false
				Game.state = &"play"
				return true
		&"side_open":
			if Game.state != &"paused" or Game.progress == null or _side_open:
				return false
			_side_open = true
			SideBoard.page = 0
			Sfx.play(&"ui_confirm")
		&"side_page":
			if Game.state != &"paused" or not _side_open:
				return false
			SideBoard.page = (SideBoard.page + 1) % SideBoard.pages()
			Sfx.play(&"ui_confirm")
		&"side_back":
			if Game.state != &"paused" or not _side_open:
				return false
			_side_open = false
			Sfx.play(&"ui_back")
		&"ach":
			if Game.state != &"paused" or Game.progress == null:
				return false
			_ach_open = true
			_ach_page = 0
			Sfx.play(&"ui_confirm")
		&"ach_back":
			if not _ach_open:
				return false
			_ach_open = false
			Sfx.play(&"ui_back")
		&"ach_prev", &"ach_next":
			if not _ach_open:
				return false
			_ach_page = clampi(_ach_page + (1 if id == &"ach_next" else -1), 0, AchievementsScreen.pages() - 1)
			Sfx.play(&"ui_tap")
		&"shop_back":
			if Game.state != &"paused":
				return false
			_shop_open = false
			_hero_hub = false
			Sfx.play(&"ui_back")
		&"deploy":
			if Game.state != &"menu":
				return false
			Sfx.play(&"ui_confirm")
			Game.start_new_game()
		&"demo":
			if Game.state != &"menu" or not DemoMode.enter():
				return false
			Sfx.play(&"ui_confirm")
		&"resume":
			if Game.state != &"paused":
				return false
			Game.state = &"play"
		&"menu":
			if Game.state != &"paused":
				return false
			Sfx.play(&"ui_back")
			Game.state = &"menu"
		&"respawn":
			if Game.state != &"dead" or screen_age < LOCK:
				return false
			Sfx.play(&"ui_confirm")
			Game.do_respawn()
		&"next":
			if Game.state != &"win" or screen_age < LOCK:
				return false
			Sfx.play(&"ui_confirm")
			Game.do_next_sector()
		&"qlp":
			Sfx.play(&"ui_tap")
			settings.quality = 0
			settings.low_plus = true
			Game.set_low_plus(true)
			settings.save()
		&"q0", &"q1", &"q2":
			Sfx.play(&"ui_tap")
			settings.quality = int(String(id).substr(1))
			settings.low_plus = false
			Game.set_tier_index(settings.quality + 1)
			settings.save()
		&"post":
			Sfx.play(&"ui_tap")
			settings.post = not settings.post
			apply_settings(false)
			settings.save()
		&"cine":
			Sfx.play(&"ui_tap")
			settings.cutscenes = not settings.cutscenes
			settings.save()
		&"mute":
			settings.muted = not settings.muted
			apply_settings(false)
			settings.save()
			Sfx.play(&"ui_tap")                                         # silent when this press muted
		&"vol_music", &"vol_sfx":
			return false                                                # sliders act through slide() (tap / drag), not as presses
		_:
			return false
	_layout_key = ""
	_screen.queue_redraw()
	return true


## The saved volume 0..1 of a slider (`&"vol_music"` or `&"vol_sfx"`).
func volume_of(slider: StringName) -> float:
	return clampf(float(settings.volumes.get(SLIDERS[slider][0], 1.0)), 0.0, 1.0)


## Sets a slider's volume (snapped to 5 %), applies it at once to its buses and optionally saves it.
func set_volume(slider: StringName, v: float, save := true) -> void:
	if not SLIDERS.has(slider):
		return
	v = snappedf(clampf(v, 0.0, 1.0), 0.05)
	for bus: String in SLIDERS[slider]:
		settings.volumes[bus] = v
	Sfx.apply_volumes(settings.volumes)
	if save:
		settings.save()


## Moves a slider to the screen x of a finger (the track is the button's rect, a little inset); the new value is heard on every volume bus at once, saved on release.
func slide(slider: StringName, x: float) -> void:
	_ensure_layout()
	for b: Dictionary in buttons:
		if b["id"] == slider:
			var r: Rect2 = b["rect"]
			var inset := minf(8.0, r.size.x * 0.05)
			var f := (x - r.position.x - inset) / maxf(r.size.x - 2.0 * inset, 1.0)
			if PhotoScreen.is_slider(slider):
				if photo_open():
					photo.set_fraction(slider, f)
					b["label"] = PhotoScreen.label(photo, slider)
					_screen.queue_redraw()
			elif OptionsScreen.is_slider(slider):
				OptionsScreen.set_fraction(settings, slider, f)
				if slider != &"opt_hud":                               # the HUD scale re-lays the screen out under the finger: applied on release
					settings.publish(false)
				b["label"] = OptionsScreen.label(settings, slider)
				_screen.queue_redraw()
			else:
				set_volume(slider, f, false)
			return


## Ends a slider drag: the value is saved and a tap confirms it (a quiet sound, so the new SFX level is audible).
func end_drag() -> void:
	if _drag == &"":
		return
	_drag = &""
	settings.publish(false)
	settings.save()
	_layout_key = ""
	_screen.queue_redraw()
	Sfx.play(&"ui_tap")


# ---------------------------------------------------------------------------------------------------------------------
# data
# ---------------------------------------------------------------------------------------------------------------------

func _on_message(text: String, seconds: float) -> void:
	toast.left = message_left                                # the visible clock is the truth (screens and tests may clear it)
	if toast.offer(text, seconds):
		_sync_toast()


func _sync_toast() -> void:
	message_text = toast.text
	message_left = toast.left
	_msg_total = maxf(toast.total, 0.1)


## "QUANTUM CORES  2 / 6   NEAREST  143 M" with the horizontal distance to the nearest core (the Missions module may not exist).
func objective_text() -> String:
	var m: Object = Game.missions if is_instance_valid(Game.missions) else null
	if m == null:
		return "NO ACTIVE OBJECTIVE"
	var total := roundi(UiUtil.num(m, &"total", 0.0))
	if total <= 0:
		return "NO ACTIVE OBJECTIVE"
	var t := "QUANTUM CORES  %d / %d" % [roundi(UiUtil.num(m, &"got", 0.0)), total]
	if m.has_method(&"nearest_core") and is_instance_valid(Game.player):
		var n: Dictionary = m.call(&"nearest_core", Game.player.global_position)
		if not n.is_empty():
			t += "   NEAREST  %d M" % roundi(float(n.get("dist", 0.0)))
	return t


## The driving readout (the one thing besides the objective that stays on screen in a car): the speed big, KM/H small, the gear and a thin rev bar along the bottom.
func _draw_speedometer(c: Control, font: Font, ab: Rect2, veh: Object, s: float) -> void:
	_plate(c, ab, s)
	var kmh := roundi(absf(UiUtil.num(veh, &"speed", 0.0)) * 3.6)
	_text(c, font, Vector2(ab.position.x + 8.0 * s, ab.position.y + 48.0 * s), str(kmh), HORIZONTAL_ALIGNMENT_RIGHT, ab.size.x * 0.52, int(54.0 * s), Color(1, 1, 1, 0.98), 1.5 * s)
	_text(c, font, Vector2(ab.position.x + ab.size.x * 0.52 + 14.0 * s, ab.position.y + 28.0 * s), "KM/H", HORIZONTAL_ALIGNMENT_LEFT, ab.size.x * 0.4, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	var gear := int(UiUtil.num(veh, &"gear", 1.0))
	var rev := UiUtil.num(veh, &"speed", 0.0) < -0.5
	var geared := veh.get("craft") == null                                # a helicopter, plane, boat or tank has no gearbox
	_text(c, font, Vector2(ab.position.x + ab.size.x * 0.52 + 14.0 * s, ab.position.y + 54.0 * s), ("R" if rev else ("GEAR %d" % gear)) if geared else ("REV" if rev else ""), HORIZONTAL_ALIGNMENT_LEFT, ab.size.x * 0.4, int(UiUtil.BAR_LABEL * s * 0.85), Color(1, 1, 1, 0.75), 1.0 * s)
	var rpm := clampf(UiUtil.num(veh, &"rpm", 0.0), 0.0, 1.0)
	var rb := Rect2(ab.position.x + 8.0 * s, ab.end.y - 8.0 * s, ab.size.x - 16.0 * s, 4.0 * s)
	_rect(c, rb, Color(0.0, 0.03, 0.05, 0.7))
	_rect(c, Rect2(rb.position, Vector2(rb.size.x * rpm, rb.size.y)), Color(UiUtil.AMBER if rpm < 0.86 else UiUtil.RED, 0.95))


## The little plate above the speedometer for the roster craft and armed vehicles (helicopter, plane, boat, tank, anything with a mounted gun): altitude and throttle of an aircraft, a plain hint
## for the next thing to do (take off, stall, land), and the gun with its rounds. Rows are built by `vehicle_rows`.
func _draw_vehicle_readout(c: Control, font: Font, ab: Rect2, veh: Object, s: float) -> void:
	var rows := vehicle_rows(veh)
	if rows.is_empty():
		return
	var rh := 30.0 * s
	var r := Rect2(ab.end.x + 10.0 * s, ab.end.y - rh * rows.size() - 6.0 * s, ab.size.x * 1.45, rh * rows.size() + 6.0 * s)       # beside the speedometer, on its baseline
	_plate(c, r, s)
	for i in rows.size():
		var row: Dictionary = rows[i]
		_text(c, font, Vector2(r.position.x + 10.0 * s, r.position.y + (i + 1) * rh - 4.0 * s), String(row["text"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0 * s,
			UiUtil.fit_size(font, String(row["text"]), r.size.x - 20.0 * s, int(UiUtil.BAR_LABEL * s * 1.05)), row["col"] as Color, 1.0 * s)


## What the readout says for a driven vehicle: [{text, col}]. Empty for a plain car. Public so the tests can read the words.
func vehicle_rows(veh: Object) -> Array:
	var rows: Array = []
	var cls: Variant = veh.get("cls")
	var craft: Object = veh.get("craft")
	if craft != null and (cls == &"heli" or cls == &"plane"):
		var alt := roundi(VehicleCraft.altitude(veh as Vehicle))
		var line := "ALT %d M" % alt
		if cls == &"plane":
			line += "    THROTTLE %d %%" % roundi(UiUtil.num(craft, &"lever", 0.0) * 100.0)
		rows.append({"text": line, "col": Color(UiUtil.CYAN, 0.97)})
		var air: bool = craft.get("airborne") == true
		var spd := absf(UiUtil.num(veh, &"speed", 0.0))
		var spec: Dictionary = veh.get("spec")
		var hint := ""
		if cls == &"plane":
			var stall := float(spec.get("stall", 24.0))
			if air and spd < stall * 0.8:
				hint = "STALLING  MORE THROTTLE"
			elif not air and UiUtil.num(craft, &"lever", 0.0) < 0.3:
				hint = "STICK UP FOR THROTTLE"
			elif not air and spd >= stall * 0.9:
				hint = "PULL UP TO TAKE OFF"
			elif not air:
				hint = "SPEED UP"
			elif alt < 25 and UiUtil.num(craft, &"vy", 0.0) < -2.0:
				hint = "LANDING  EASY"
		elif not air:
			hint = "HOLD UP TO LIFT OFF" if UiUtil.num(craft, &"spool", 0.0) >= VehicleCraft.SPOOL_READY else "ROTOR SPINNING UP"
		if hint != "":
			rows.append({"text": hint, "col": Color(UiUtil.AMBER, 0.97)})
	var w: Object = veh.get("weapons")
	if w != null and w.has_method(&"mounted") and w.call(&"mounted"):
		var d: Dictionary = w.get("def")
		var hot: bool = w.get("locked") == true
		rows.append({"text": "%s  %d%s" % [String(d.get("name", "GUN")), int(UiUtil.num(w, &"ammo", 0.0)), "  HOT" if hot else ""], "col": Color(UiUtil.RED if hot else Color(1, 1, 1), 0.97)})
	return rows


## "27 / 30", "RELOADING" on foot, "84 KM/H" in a vehicle (cached: rebuilt only when a number changes).
func ammo_text() -> String:
	var p: Object = Game.player if is_instance_valid(Game.player) else null
	if p == null:
		return ""
	var veh: Object = p.get("vehicle")
	var key: int
	if veh != null:
		key = 1 + roundi(absf(UiUtil.num(veh, &"speed", 0.0)) * 3.6) * 4
	elif p.get("reloading") == true:
		key = 2
	else:
		key = 3 + (roundi(UiUtil.num(p, &"ammo", 0.0)) * 100 + roundi(UiUtil.num(p, &"mag", 30.0))) * 4
	if key != _ammo_key:
		_ammo_key = key
		if veh != null:
			_ammo_text = "%d KM/H" % roundi(absf(UiUtil.num(veh, &"speed", 0.0)) * 3.6)
		elif p.get("reloading") == true:
			_ammo_text = "RELOADING"
		elif UiUtil.num(p, &"mag", 30.0) <= 1.0 and p.get("weapon") is PlayerWeapon and String((p.get("weapon") as PlayerWeapon).def["kind"]) == "melee":
			_ammo_text = "MELEE"
		else:
			_ammo_text = "%d / %d" % [roundi(UiUtil.num(p, &"ammo", 0.0)), roundi(UiUtil.num(p, &"mag", 30.0))]
	return _ammo_text


## "SHARD SCATTER  SCT   RESERVE 24": the weapon in hand and its spare rounds (the carbine's are unlimited). Empty without a weapon.
## The alt-fire / ammo type line above the weapon plate ("" without a weapon).
func alt_text() -> String:
	var p: Object = Game.player if is_instance_valid(Game.player) else null
	if p == null or not (p.get("weapon") is PlayerWeapon):
		return ""
	return (p.get("weapon") as PlayerWeapon).alt_text()


## True while an optional set piece can be skipped (the SKIP SET PIECE button and hint).
func skip_set_piece() -> bool:
	var k := _campaign()
	if k == null:
		return false
	if bool(k.call(&"skip_set_piece")):
		return true
	var g: Variant = k.get(&"guide")
	return g != null and (g as MissionGuide).skip_step()                # SKIP STEP: offered after a minute and a half without progress


func skip_available() -> bool:
	var k := _campaign()
	if k == null:
		return false
	if bool(k.call(&"in_optional_set_piece")):
		return true
	return step_skip_offered()


## True while the mission guide offers SKIP STEP (a step made no progress for a minute and a half).
func step_skip_offered() -> bool:
	var k := _campaign()
	var g: Variant = k.get(&"guide") if k != null else null
	return g != null and (g as MissionGuide).offering and MissionGuide.hud_on


## The weapon plate that pops up for a moment when the weapon in hand changes (a wheel pick, SWAP, a pickup, a crate, an empty gun): the weapon's own silhouette, its name, class,
## rounds and reserve, and the NEXT weapon of the unlock ladder with how to get it. Centre of the screen, under the crosshair, clear of every button.
var _wpop_id: StringName = &""
var _wpop_until := 0


func _draw_weapon_pop(c: Control, s: float, font: Font, vp: Vector2, p: Object) -> void:
	if not (p.get("weapon") is PlayerWeapon):
		return
	var w := p.get("weapon") as PlayerWeapon
	var now := Time.get_ticks_msec()
	if _wpop_id == &"":
		_wpop_id = w.current
	elif w.current != _wpop_id:
		_wpop_id = w.current
		_wpop_until = now + WEAPON_POP_MS
	if now >= _wpop_until:
		return
	var left := float(_wpop_until - now) / float(WEAPON_POP_MS)
	var a := clampf(left * 4.0, 0.0, 1.0)                            # fades out over the last quarter
	var cx := vp.x * 0.5
	if touch_ui_on():
		cx = minf(cx, vp.x - UiUtil.insets(vp).y - 600.0 * s - 215.0 * s - 10.0 * s)         # clear of the button cluster on a phone
	var nxt := WeaponLadder.next_target()
	var r := Rect2(cx - 200.0 * s, vp.y * 0.58, 400.0 * s, (112.0 if nxt == &"" else 148.0) * s)
	_plate(c, r, s)
	WeaponIcons.draw(c, w.current, Rect2(r.position.x + 8.0 * s, r.position.y + 8.0 * s, 130.0 * s, 70.0 * s), Color(UiUtil.CYAN, 0.95 * a))
	var pop_name := String(w.def["name"])                                # long roster names ("TITAN ANTI-MATERIAL RIFLE") go on two lines instead of being cut
	var nsize := int(UiUtil.BAR_LABEL * s)
	var lines: Array[String] = [pop_name]
	if font.get_string_size(pop_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, nsize).x > 250.0 * s:
		var words := pop_name.split(" ", false)
		var best := 1
		for k in range(1, words.size()):
			if font.get_string_size(" ".join(words.slice(0, k)), HORIZONTAL_ALIGNMENT_LEFT, -1.0, nsize).x <= 250.0 * s:
				best = k
		lines = [" ".join(words.slice(0, best)), " ".join(words.slice(best))]
	var ny := r.position.y + (36.0 if lines.size() == 1 else 28.0) * s
	for li in lines.size():
		_text(c, font, Vector2(r.position.x + 146.0 * s, ny + float(li) * 26.0 * s), lines[li], HORIZONTAL_ALIGNMENT_LEFT, 250.0 * s, UiUtil.fit_size(font, lines[li], 250.0 * s, nsize), Color(1, 1, 1, 0.97 * a), 1.0 * s)
	var cls := String(WeaponDefs.CLASS_NAMES.get(WeaponDefs.class_of(w.current), ""))
	var rounds := "MELEE" if String(w.def["kind"]) == "melee" else "%d / %d  %s" % [w.ammo, w.mag, "INF" if w.reserve < 0 else str(w.reserve)]
	_text(c, font, Vector2(r.position.x + 146.0 * s, r.position.y + (68.0 if lines.size() == 1 else 84.0) * s), "%s  %s" % [cls, rounds], HORIZONTAL_ALIGNMENT_LEFT, 250.0 * s, int(UiUtil.BAR_LABEL * s * 0.85), Color(UiUtil.AMBER, 0.95 * a), 1.0 * s)
	if nxt != &"":
		_text(c, font, Vector2(r.position.x + 10.0 * s, r.position.y + 104.0 * s), "NEXT  %s" % WeaponDefs.title(nxt), HORIZONTAL_ALIGNMENT_LEFT, 380.0 * s, int(18.0 * s), Color(UiUtil.CYAN, 0.95 * a), 0.5 * s)
		_text(c, font, Vector2(r.position.x + 10.0 * s, r.position.y + 132.0 * s), WeaponLadder.route_text(nxt), HORIZONTAL_ALIGNMENT_LEFT, 380.0 * s, int(18.0 * s), Color(1, 1, 1, 0.85 * a), 0.5 * s)


func weapon_text() -> String:
	var p: Object = Game.player if is_instance_valid(Game.player) else null
	if p == null or not (p.get("weapon") is PlayerWeapon):
		return ""
	var w := p.get("weapon") as PlayerWeapon
	var d := w.def
	return "%s  %s   %s" % [d["name"], d["tag"], "RESERVE INF" if w.reserve < 0 else "RESERVE %d" % w.reserve]


## 0..1 charge of the Pulse Lance (0 for the others).
func weapon_charge() -> float:
	var p: Object = Game.player if is_instance_valid(Game.player) else null
	if p == null or not (p.get("weapon") is PlayerWeapon):
		return 0.0
	return (p.get("weapon") as PlayerWeapon).gauge()


## The car radio line shown while driving: "RADIO  NEON FM", or "RADIO OFF"; "" when not driving or there is no radio.
func radio_text() -> String:
	if not is_instance_valid(Game.vehicles) or not is_instance_valid(Game.player) or Game.player.get("vehicle") == null:
		return ""
	var r: Object = Game.vehicles.get("radio")
	if r == null:
		return ""
	if not r.get("on"):
		return "RADIO OFF"
	return "RADIO  " + CarRadio.station_name(int(r.get("station")))


func hint_text() -> String:
	if not is_instance_valid(Game.vehicles) or not is_instance_valid(Game.player):
		return ""
	var key := "" if touch_ui_on() else "[F]  "
	if InteriorGameplay.prompt != "":                       # a door, a vendor or a mission object (scripts/interiors_gameplay/)
		return "" if InteriorPrompts.active_shown else key + InteriorGameplay.prompt          # the floating plate over the object says it already
	if InteriorGameplay.active:
		return ""                                           # inside a building: no street prompts (ENTER VEHICLE, jobs of the street)
	var jp := Freedom.job_prompt()                          # a job marker under the hero: street race, taxi fare, delivery, bounty (starts by itself)
	if jp != "":
		return jp
	if Game.player.get("vehicle") != null:
		return key + "EXIT VEHICLE"
	var vp := Freedom.vehicle_prompt()                      # HIJACK TAXI / ENTER BUS
	if vp != "":
		return key + vp
	if Game.vehicles.has_method(&"nearest") and Game.vehicles.call(&"nearest", Game.player.global_position, REACH) != null:
		return key + "ENTER VEHICLE"
	return ""


var _redraw_t := 0.0
var _screen_sig := ""
var _sub_t := 1.0
const MENU_FADE := 0.16                ## seconds a menu screen takes to fade in when it opens or switches


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)       # screens and locks count real seconds, so a slow-motion death never delays the respawn button
	_t += real
	if Game.state == &"play" and is_instance_valid(Game.player):                 # hit-confirm: a tiny camera tick (a bigger one on a kill) next to the crosshair X
		var lh := UiUtil.num(Game.player, &"last_hit_time", -100.0)
		if lh > _seen_hit:
			_seen_hit = lh
			if PlayerUtil.now() - lh < 0.25:
				FX.shake(0.16 if Game.player.get("last_hit_kill") == true else 0.07)
	screen_age += real
	var toast_dt := 0.0 if banner_busy() else delta           # one banner at a time: a toast waits (its clock is held) while the chapter banner or a story card is up
	message_left = maxf(message_left - toast_dt, 0.0)
	toast.left = message_left
	if toast.tick(toast_dt):
		_sync_toast()
	_text_t -= delta
	if _text_t <= 0.0:
		_text_t = 0.2
		_obj_text = objective_text()
		_shard_text = ""                                      # no shard counter on the HUD (the map and the pause screen keep it)
		_cred_text = "CREDITS  %d" % (int(Game.progress.get(&"credits")) if Game.progress != null else Game.score)
		_contract_text = _contract_line()
		_camp_text = _campaign_line()
		_hint_text = hint_text()
		var rt := radio_text()
		if rt != _radio_last:
			if _radio_last != "" and rt != "":
				_radio_show = 2.6
			_radio_last = rt
	_radio_show = maxf(_radio_show - real, 0.0)
	var want_hud := _hud_wanted()
	if _hud.visible != want_hud:
		_hud.visible = want_hud
		minimap.visible = want_hud
	var vp := get_viewport().get_visible_rect().size
	var s := UiUtil.ui_scale(vp)
	var ins := UiUtil.insets(vp)
	var side := MINIMAP * s
	minimap.position = Vector2(ins.x + 16.0 * s, 14.0 * s + UiUtil.insets_v(vp).x)
	minimap.size = Vector2(side, side)
	var col_bottom := minimap.position.y + side
	if touch != null and touch.perf_visible():
		col_bottom = maxf(col_bottom, (touch._perf_box() as Rect2).end.y)
	UiUtil.left_bottom = col_bottom / s
	var sig := "%s|%s%s%s%s%s%s%s%d%s%s%s%s%s%s%s%d" % [Game.state, _options_open, _gear_open, _hero_hub, _shop_open, _skills_open, _craft_open, _loadout_open, _loadout_page, _look_open, _side_open, _heist_open, _safe_open, _ach_open, _arena_open, _chapters_open, UiSettings.s_opt_page * 8 + UiSettings.s_opt_tab]
	if sig != _screen_sig:                                  # a screen opened or changed: it fades in over MENU_FADE (a cut between panels reads as clumsy)
		_screen_sig = sig
		_sub_t = 0.0
	_sub_t += real
	_screen.modulate.a = 1.0 if photo_open() else clampf(0.35 + 0.65 * _sub_t / MENU_FADE, 0.0, 1.0)
	_redraw_t -= real
	if _redraw_t <= 0.0:                                    # LOW redraws the HUD and the screens 20 times a second, LOW+ 12 (the draw is script work every frame otherwise)
		_redraw_t = LowPlus.hud_interval()
		if _hud.visible:
			_hud.queue_redraw()
		if _screen.visible:
			_screen.queue_redraw()


# ---------------------------------------------------------------------------------------------------------------------
# HUD drawing
# ---------------------------------------------------------------------------------------------------------------------

## Everything the HUD draws every frame is queued and flushed in batch-friendly order: plain rectangles, then sprites (grouped by texture), then outlines, then text
## (grouped by size). Canvas draws only batch when consecutive commands share their kind and texture, so the order of calls in the code is NOT the draw order.
## Clock rides on the credits line (same draw call, the tier-0 budget is tight).
func _clock_suffix() -> String:
	if is_instance_valid(Game.world) and Game.world.get("day_night") is DayNight:
		return "   " + DayNight.clock_text((Game.world.get("day_night") as DayNight).hour)
	return ""


func _text(c: Control, font: Font, pos: Vector2, text: String, align: HorizontalAlignment, width: float, size: int, col: Color, shadow := 0.0) -> void:
	var tt := Tr.t(text)
	if c == _screen and size < int(BODY_MIN * UiUtil.ui_scale(c.size)):
		size = int(BODY_MIN * UiUtil.ui_scale(c.size))                      # menus never print below BODY_MIN (22 px at 1080p): a longer text wraps or gets a wider box, it does not shrink
	var fsz := Tr.scaled_size(font, tt, width, size)
	if c == _screen and width > 0.0:
		var tw := font.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
		if tw > width:                                                      # the device font is wider than the box was drawn for: the box grows around the text, the size stays readable
			if align == HORIZONTAL_ALIGNMENT_CENTER:
				pos.x -= (tw - width) * 0.5
			elif align == HORIZONTAL_ALIGNMENT_RIGHT:
				pos.x -= tw - width
			width = tw
	_q.append([c, font, pos, tt, align, width, fsz, col, shadow])


func _rect(c: Control, r: Rect2, col: Color) -> void:
	_fills.append([c, r, col])


func _frame(c: Control, r: Rect2, col: Color, w: float) -> void:
	_frames.append([c, r, col, w])


func _sprite(c: Control, kind: StringName, r: Rect2, col: Color) -> void:
	_sprites.append([c, kind, r, col])


func _flush_text() -> void:
	for f: Array in _fills:
		(f[0] as Control).draw_rect(f[1], f[2])
	_fills.clear()
	if not _sprites.is_empty():
		var kinds := {}
		for sp: Array in _sprites:
			kinds[sp[1]] = true
		for k: StringName in kinds.keys():
			for sp: Array in _sprites:
				if sp[1] == k:
					(sp[0] as Control).draw_texture_rect(UiUtil.sprite(k), sp[2], false, sp[3])
		_sprites.clear()
	for f: Array in _frames:
		(f[0] as Control).draw_rect(f[1], f[2], false, f[3])
	_frames.clear()
	var sizes := {}
	for q: Array in _q:
		sizes[q[6]] = true
	for sz: int in sizes.keys():
		for q: Array in _q:
			if q[6] == sz and float(q[8]) > 0.0:
				var col: Color = q[7]
				(q[0] as Control).draw_string(q[1], (q[2] as Vector2) + Vector2(q[8], q[8]), q[3], q[4], q[5], q[6], Color(0, 0, 0, col.a * 0.85))
		for q: Array in _q:
			if q[6] == sz:
				(q[0] as Control).draw_string(q[1], q[2], q[3], q[4], q[5], q[6], q[7])
	if scan_text:
		for q2: Array in _q:
			if q2[0] == _screen or (scan_hud and q2[0] == _hud):                         # the menu layer only (the HUD behind a death screen has its own tests), or the HUD layer too when asked
				scan_log.append(_scan_entry(q2))
	_q.clear()


## One queued text as {text, rect (where the glyphs land), box (the width it was given), size, over (the text is wider than its box)} for the layout scan.
func _scan_entry(q: Array) -> Dictionary:
	var font := q[1] as Font
	var sz: int = q[6]
	var tw := font.get_string_size(str(q[3]), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var pos: Vector2 = q[2]
	var box: float = q[5]
	var x := pos.x
	if box > 0.0:
		if int(q[4]) == HORIZONTAL_ALIGNMENT_CENTER:
			x = pos.x + (box - tw) * 0.5
		elif int(q[4]) == HORIZONTAL_ALIGNMENT_RIGHT:
			x = pos.x + box - tw
	return {"text": str(q[3]), "rect": Rect2(x, pos.y - 0.78 * float(sz), tw, float(sz)), "box": box, "size": sz, "over": box > 0.0 and tw > box + 1.5}


## A backing plate (dark translucent rectangle with a thin accent line on its lower edge).
func _plate(c: Control, r: Rect2, s: float, accent := Color(UiUtil.CYAN, 0.45)) -> void:
	_rect(c, r, UiUtil.PLATE)
	_rect(c, Rect2(r.position.x, r.end.y - 2.0 * s, r.size.x, 2.0 * s), accent)


func _text_width(font: Font, text: String, size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## A centred line of text on its own plate; returns the plate.
func _plate_text(c: Control, font: Font, cx: float, y: float, text: String, size: int, col: Color, s: float, accent := Color(UiUtil.CYAN, 0.45), min_w := 0.0) -> Rect2:
	var w := maxf(_text_width(font, text, size) + 36.0 * s, min_w)
	var r := Rect2(cx - w * 0.5, y, w, float(size) * 1.45 + 6.0 * s)
	_plate(c, r, s, accent)
	_text(c, font, Vector2(r.position.x, y + float(size) * 1.1 + 2.0 * s), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, col, 1.5 * s)
	return r


## A slim status bar of the phone HUD: a dark track and the fill, nothing else.
func _bar_slim(c: Control, x: float, y: float, w: float, h: float, frac: float, col: Color, s: float) -> void:
	_rect(c, Rect2(x - 1.5 * s, y - 1.5 * s, w + 3.0 * s, h + 3.0 * s), Color(0.0, 0.03, 0.05, 0.7))
	_rect(c, Rect2(x, y, w * clampf(frac, 0.0, 1.0), h), col)
	_frame(c, Rect2(x, y, w, h), Color(col, 0.6), 1.0 * s)


func _bar(c: Control, font: Font, x: float, y: float, w: float, h: float, frac: float, col: Color, label: String, value: String, s: float) -> void:
	var r := Rect2(x, y, w, h)
	_rect(c, r.grow(2.0 * s), Color(0.0, 0.03, 0.05, 0.6))
	_rect(c, Rect2(x, y, w * clampf(frac, 0.0, 1.0), h), col)
	_frame(c, r, Color(col, 0.7), 1.0 * s)
	_text(c, font, Vector2(x - 8.0 * s - _lw * s, y + h + 2.0 * s), label, HORIZONTAL_ALIGNMENT_RIGHT, _lw * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	_text(c, font, Vector2(x + w + 8.0 * s, y + h + 3.0 * s), value, HORIZONTAL_ALIGNMENT_LEFT, VALUE_W * s, int(UiUtil.TEXT_MIN * s), Color(1, 1, 1, 0.95), 1.0 * s)


## Measures the widest bar caption once per UI scale (the font differs per device), so no caption is ever cut.
func _caption_width(font: Font, s: float) -> void:
	var key := int(s * 100.0)
	if key == _lw_key:
		return
	_lw_key = key
	var size := int(UiUtil.BAR_LABEL * s)
	var w := maxf(maxf(_text_width(font, "INTEGRITY", size), _text_width(font, "COHERENCE", size)), _text_width(font, "HULL", size))
	_lw = maxf(LABEL_W, w / s + 6.0)


## Wanted v2 / faction plate left of the heat plate (scripts/enemies/wanted.gd, factions.gd): line 1 the faction that holds the hero's ground and its standing (HOSTILE / NEUTRAL /
## ALLIED), line 2 while the heat burns the wanted state (SPOTTED, SEARCHING, HIDDEN, INSIDE, DISGUISED, DECOY) with the response level. In the gap between the bars and the heat plate.
func wanted_tag() -> Dictionary:
	var w := Wanted.current
	if w == null or Game.state == &"menu" or not is_instance_valid(Game.player):
		return {}
	var camp := Factions.at((Game.player as Node3D).global_position)
	var out := {"faction": "%s  %s" % [Factions.title(camp), Factions.status_name(Game.progress, camp)], "color": Factions.color(camp), "wanted": "", "wcolor": UiUtil.RED}
	if Game.heat > 0.0:
		out["wanted"] = "%s  L%d" % [w.state_label(), w.level()]
		out["wcolor"] = UiUtil.RED if w.hide_mode == &"" else UiUtil.CYAN
	return out


func wanted_rect(vp: Vector2, s: float, top: float) -> Rect2:
	var right := vp.x - UiUtil.insets(vp).y - 16.0 * s
	return Rect2(right - 196.0 * s - 8.0 * s - 176.0 * s, top, 176.0 * s, 44.0 * s)


func _draw_wanted_tag(c: Control, s: float, font: Font, vp: Vector2, top: float) -> void:
	var tag := wanted_tag()
	if tag.is_empty():
		return
	var r := wanted_rect(vp, s, top)
	var quiet := String(tag["wanted"]) == "" and Factions.status(Game.progress, Factions.at((Game.player as Node3D).global_position)) == Factions.Status.NEUTRAL
	if quiet and Game.player.get("vehicle") != null:       # in a car the quiet faction line is clutter: the speed and the objective are what the driver needs
		return
	if quiet:                                           # neutral ground and no heat: a small one-line state (a shorter plate, one text draw)
		r.size.y = 26.0 * s
		_rect(c, r, UiUtil.PLATE)
	else:
		_plate(c, r, s, Color(tag["color"], 0.55))
	var size := int(UiUtil.BAR_LABEL * s * 0.8)
	size = UiUtil.fit_size(font, Tr.t(String(tag["faction"])), r.size.x - 12.0 * s, size)       # the whole standing ("DRONES  NEUTRAL") fits the plate
	_text(c, font, Vector2(r.position.x + 6.0 * s, r.position.y + 19.0 * s), String(tag["faction"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 10.0 * s, size, Color(tag["color"], 0.97), 1.0 * s)
	if String(tag["wanted"]) != "":
		_text(c, font, Vector2(r.position.x + 6.0 * s, r.position.y + 38.0 * s), String(tag["wanted"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 10.0 * s, size, Color(tag["wcolor"], 0.97), 1.0 * s)


## The ally's plate (name, health bar, order) under the heat plate while the Vael defector is recruited (scripts/npc/companion.gd).
func _draw_ally(c: Control, s: float, font: Font, right: float, top: float) -> void:
	var ally := Companion.current
	if ally == null or not ally.active or Game.state == &"menu":
		return
	var r := Rect2(right - 262.0 * s, top + 50.0 * s, 182.0 * s, 44.0 * s)
	_plate(c, r, s, Color(0.3, 0.9, 1.0, 0.55))
	_text(c, font, Vector2(r.position.x + 6.0 * s, r.position.y + 20.0 * s), "ALLY  " + ally.mode_name(), HORIZONTAL_ALIGNMENT_LEFT, 170.0 * s, int(UiUtil.BAR_LABEL * s * 0.85), Color(0.3, 0.9, 1.0, 0.97), 1.0 * s)
	var f := ally.hp_fraction()
	_rect(c, Rect2(r.position.x + 6.0 * s, r.position.y + 28.0 * s, 170.0 * s, 8.0 * s), Color(0.0, 0.03, 0.05, 0.7))
	_rect(c, Rect2(r.position.x + 6.0 * s, r.position.y + 28.0 * s, 170.0 * s * f, 8.0 * s), Color(0.4, 1.0, 0.72, 0.95) if f > 0.35 else Color(1.0, 0.3, 0.3, 0.95))


func _draw_hud(_ignored: Control = null) -> void:
	var t0 := PerfTimers.start()
	_draw_hud_body()
	_flush_text()
	PerfTimers.stop(PerfTimers.HUD, t0)


func _draw_hud_body() -> void:
	var c := _hud
	var vp := c.size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var ins := UiUtil.insets(vp)
	var insv := UiUtil.insets_v(vp)
	var right := vp.x - ins.y - 16.0 * s
	var playing := Game.state == &"play"
	var p: Node3D = Game.player if is_instance_valid(Game.player) else null
	var veh: Object = p.get("vehicle") if p != null else null
	var now := PlayerUtil.now()
	# damage vignette first so everything else sits on top of it
	if p != null:
		var since_hurt := now - UiUtil.num(p, &"last_hurt_time", -100.0)
		if veh != null:
			since_hurt = maxf(since_hurt, 100.0) if UiUtil.num(veh, &"last_impact", 0.0) < 20.0 else since_hurt      # in a car only a hard impact (72 km/h and up) flashes red, a bump never does
		var hp_f := UiUtil.num(p, &"hp", 100.0) / maxf(UiUtil.num(p, &"max_hp", 100.0), 1.0)
		var a := vignette_alpha(since_hurt, hp_f, playing, _t)
		if a > 0.01:
			c.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, vp), false, Color(1, 1, 1, a))
		var rig_b: Object = p.get("camera_rig")
		var blur_a := float(rig_b.get("blur")) * 0.35 if rig_b != null and not UiSettings.s_reduce_motion and not UiSettings.s_reduce_flash else 0.0
		if blur_a > 0.01:
			c.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, vp), false, Color(0.75, 0.95, 1.0, blur_a))
		var qm: Object = p.get("quantum")
		if qm != null and playing:
			var fl := 0.0 if UiSettings.s_reduce_flash else float(qm.get("fx_flash"))
			var cf := float(qm.get("collapse_fx"))
			var qa := maxf(maxf(fl * 0.55, 0.3 if qm.get("aiming") == true else 0.0), cf * 0.7)
			if qa > 0.01:
				c.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, vp), false, Color(UiUtil.CYAN if fl < 0.5 else UiUtil.MAGENTA, qa))
				if fl > 0.0:
					c.draw_rect(Rect2(Vector2.ZERO, vp), Color(UiUtil.CYAN, fl * 0.18))
				if cf > 0.0:
					c.draw_rect(Rect2(Vector2.ZERO, vp), Color(UiUtil.MAGENTA, cf * 0.22))
		if since_hurt < MARKER_TIME and playing:
			_draw_hurt_direction(c, p, vp, s, 1.0 - since_hurt / MARKER_TIME)
		if playing and veh == null:
			_draw_threat_edges(c, vp, s)
	# top centre, one compact stack: the bars on a plate, then ONE priority line (the active / offered contract, else the core objective) and its extras.
	var top := insv.x + 6.0 * s
	var stack_end := top
	if p != null:
		var slim := touch_ui_on()                           # phone: two slim bars, no captions, no numbers (docs/DESIGN.md: health and energy small)
		var bw := (SLIM_W if slim else BAR_W) * s
		_caption_width(font, s)
		var total := bw if slim else (_lw + 8.0 + VALUE_W + 8.0) * s + bw
		var bx := vp.x * 0.5 - total * 0.5 + (0.0 if slim else (_lw + 8.0) * s)
		var hp := UiUtil.num(p, &"hp", 100.0)
		var mhp := maxf(UiUtil.num(p, &"max_hp", 100.0), 1.0)
		var f := clampf(hp / mhp, 0.0, 1.0)
		var hp_col := Color(0.4, 1.0, 0.72, 0.95) if f > 0.35 else Color(1.0, 0.3, 0.3, 0.95)
		var has_hull := veh != null and UiUtil.num(veh, &"hp", -1.0) >= 0.0
		var rows := 3 if has_hull else 2
		var driving_hud := veh != null and playing
		if driving_hud:                                     # in a car: the hull, and the hero's own health only when he is hurt (no COHERENCE bar, no clutter)
			rows = (1 if has_hull else 0) + (1 if f < 0.95 else 0)
		var plate := Rect2(vp.x * 0.5 - total * 0.5 - 10.0 * s, top, total + 20.0 * s, (8.0 + 30.0 * (rows - 1) + 14.0 + 12.0) * s) if rows > 0 else Rect2(vp.x * 0.5, top, 0.0, 0.0)
		if slim and rows > 0:
			plate = Rect2(vp.x * 0.5 - total * 0.5 - 8.0 * s, top, total + 16.0 * s, (6.0 + SLIM_PITCH * (rows - 1) + SLIM_H + 7.0) * s)
		if rows > 0:
			_plate(c, plate, s)
		var y0 := top + 8.0 * s
		if slim:
			y0 = top + 6.0 * s
			var yy := y0
			if driving_hud:
				if has_hull:
					var hf2 := UiUtil.num(veh, &"hp", 0.0) / maxf(UiUtil.num(veh, &"max_hp", 100.0), 1.0)
					_bar_slim(c, bx, yy, bw, SLIM_H * s, hf2, Color(1.0, 0.65, 0.25, 0.95) if hf2 > 0.4 else Color(1.0, 0.3, 0.3, 0.95), s)
					yy += SLIM_PITCH * s
				if f < 0.95:
					_bar_slim(c, bx, yy, bw, SLIM_H * s, f, hp_col, s)
			else:
				_bar_slim(c, bx, yy, bw, SLIM_H * s, f, hp_col, s)
				_bar_slim(c, bx, yy + SLIM_PITCH * s, bw, SLIM_H * s, UiUtil.num(p, &"energy", 100.0) / maxf(UiUtil.num(p, &"max_energy", 100.0), 1.0), Color(0.35, 0.8, 1.0, 0.95), s)
				if has_hull:
					var vh2 := UiUtil.num(veh, &"hp", 0.0)
					_bar_slim(c, bx, yy + 2.0 * SLIM_PITCH * s, bw, SLIM_H * s, vh2 / maxf(UiUtil.num(veh, &"max_hp", 100.0), 1.0), Color(1.0, 0.65, 0.25, 0.95), s)
		elif driving_hud:
			if has_hull:
				var vh0 := UiUtil.num(veh, &"hp", 0.0)
				var hf := vh0 / maxf(UiUtil.num(veh, &"max_hp", 100.0), 1.0)
				_bar(c, font, bx, y0, bw, 14.0 * s, hf, Color(1.0, 0.65, 0.25, 0.95) if hf > 0.4 else Color(1.0, 0.3, 0.3, 0.95), "HULL", "%d%%" % ceili(hf * 100.0), s)
				y0 += 30.0 * s
			if f < 0.95:
				_bar(c, font, bx, y0, bw, 14.0 * s, f, hp_col, "INTEGRITY", str(ceili(hp)), s)
		else:
			_bar(c, font, bx, y0, bw, 14.0 * s, f, hp_col, "INTEGRITY", str(ceili(hp)), s)
			var en := UiUtil.num(p, &"energy", 100.0)
			var men := maxf(UiUtil.num(p, &"max_energy", 100.0), 1.0)
			_bar(c, font, bx, y0 + 30.0 * s, bw, 14.0 * s, en / men, Color(0.35, 0.8, 1.0, 0.95), "COHERENCE", str(floori(en)), s)
			if has_hull:
				var vh := UiUtil.num(veh, &"hp", 0.0)
				_bar(c, font, bx, y0 + 60.0 * s, bw, 14.0 * s, vh / maxf(UiUtil.num(veh, &"max_hp", 100.0), 1.0), Color(1.0, 0.65, 0.25, 0.95), "HULL", str(ceili(vh)), s)
		stack_end = _draw_priority(c, vp, s, font, (plate.end.y if rows > 0 else top) + 3.0 * s) if Game.state != &"dead" else plate.end.y      # the dead screen has its own title: no mission line under DECOHERED
	if playing and _camp_text != "" and MissionGuide.hud_on and not (Game.missions is Missions and (Game.missions as Missions).board_mode):      # the board's objective is the line and the beacon marker; the compass strip said it a third time
		stack_end = _draw_compass(c, vp, s, font, stack_end + 2.0 * s)
	if playing:
		stack_end = _draw_stealth_meter(c, vp, s, font, stack_end + 3.0 * s)
		stack_end = _draw_activity(c, vp, s, font, stack_end + 3.0 * s)
	UiUtil.stack_bottom = stack_end / s
	if playing and _camp_text != "":
		_draw_waypoint(c, vp, s, font, ins, insv)
	# top right: the wanted stars, only while there is heat (credits are a toast on pickup and live in the pause screen; no shard counter, no faction plate on quiet ground)
	if Game.heat > 0.01 and Game.state != &"menu":
		var heat := Game.heat
		_plate(c, Rect2(right - 196.0 * s, top, 204.0 * s, 44.0 * s), s)
		for i in 5:
			var centre := Vector2(right - (4 - i) * 30.0 * s - 14.0 * s, top + 22.0 * s)
			var sr := Rect2(centre - Vector2(12.0, 12.0) * s, Vector2(24.0, 24.0) * s)
			_sprite(c, &"star", sr, Color(1, 1, 1, 0.16))
			var fill := clampf(heat - i, 0.0, 1.0)
			if fill > 0.0:
				var col := UiUtil.AMBER if heat < 3.0 else UiUtil.RED
				var pulse := 1.0 if heat < 3.0 else 0.8 + 0.2 * sin(_t * 8.0)
				_sprite(c, &"star", sr, Color(col, (0.35 + 0.65 * fill) * pulse))
		if not touch_ui_on():                                # the phone shows the stars only: the faction plate was a second block of words in the corner
			_draw_wanted_tag(c, s, font, vp, top)
	_draw_ally(c, s, font, right, top)
	if p == null:
		_draw_message(c, vp, s, font)
		return
	if not playing and Game.state != &"paused":                # dead and win: the middle and the bottom belong to the world and the screen's own button
		_draw_message(c, vp, s, font)
		return
	# bottom: ammo or speed (on phones left of the touch buttons), power hints (desktop), vehicle hint above the ammo
	var base_y := vp.y - insv.y
	var touch_on := touch_ui_on()
	var aw := 260.0 * s
	var ax := vp.x * 0.5
	if touch_on:
		ax = minf(ax, vp.x - ins.y - 600.0 * s - 215.0 * s - 10.0 * s)     # clear of the 430 px weapon plate above the ammo
	var ab := Rect2(ax - aw * 0.5, base_y - 82.0 * s, aw, 66.0 * s)
	var ammo_plate := not touch_on or veh != null           # on a phone the ammo count lives on the WEAPON button; the plate stays for the speed in a car
	if veh != null:
		if touch_on:                                        # the car fills the middle of the frame: the speed sits in the free bottom-left corner, away from the thumbs
			ab.position.x = ins.x + 24.0 * s
		_draw_speedometer(c, font, ab, veh, s)
		_draw_vehicle_readout(c, font, ab, veh, s)
	elif ammo_plate:
		_plate(c, ab, s)
		_text(c, font, Vector2(ab.position.x, ab.position.y + 50.0 * s), ammo_text(), HORIZONTAL_ALIGNMENT_CENTER, ab.size.x, UiUtil.fit_size(font, ammo_text(), ab.size.x - 8.0 * s, int(48.0 * s)), Color(1, 1, 1, 0.97) if p.get("reloading") != true else Color(UiUtil.AMBER, 0.97), 1.5 * s)
	if veh == null and not touch_on and weapon_text() != "":
		var wr := Rect2(ab.get_center().x - 215.0 * s, ab.position.y - 42.0 * s, 430.0 * s, 36.0 * s)
		_plate(c, wr, s)
		_text(c, font, Vector2(wr.position.x, wr.position.y + 27.0 * s), weapon_text(), HORIZONTAL_ALIGNMENT_CENTER, wr.size.x, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.97), 1.0 * s)
		if p.get("weapon") is PlayerWeapon:
			WeaponIcons.draw(c, (p.get("weapon") as PlayerWeapon).current, Rect2(wr.position.x + 6.0 * s, wr.position.y + 3.0 * s, 54.0 * s, 30.0 * s), Color(UiUtil.CYAN, 0.9))
		_text(c, font, Vector2(ab.end.x + 10.0 * s, ab.position.y + 40.0 * s), alt_text(), HORIZONTAL_ALIGNMENT_LEFT, 200.0 * s, int(UiUtil.BAR_LABEL * s * 0.8), Color(UiUtil.AMBER, 0.9), 1.0 * s)
		var wch := weapon_charge()
		if wch > 0.0:
			var hot := p.get("weapon") is PlayerWeapon and (p.get("weapon") as PlayerWeapon).def.has("heat_per")
			_rect(c, Rect2(wr.position.x, wr.position.y - 8.0 * s, wr.size.x * wch, 5.0 * s), Color(UiUtil.AMBER if hot else UiUtil.CYAN, 0.95) if wch < 0.999 or not hot else Color(1.0, 0.3, 0.2, 0.95))
	if veh == null:
		_draw_weapon_pop(c, s, font, vp, p)
	if touch_on and veh == null and weapon_charge() > 0.0:       # the Pulse Lance charge: a thin bar under the crosshair (the weapon plate is gone on phones)
		var cw := 140.0 * s
		_rect(c, Rect2(vp.x * 0.5 - cw * 0.5, vp.y * 0.5 + 58.0 * s, cw, 6.0 * s), Color(0.0, 0.03, 0.05, 0.7))
		_rect(c, Rect2(vp.x * 0.5 - cw * 0.5, vp.y * 0.5 + 58.0 * s, cw * weapon_charge(), 6.0 * s), Color(UiUtil.CYAN, 0.95))
	if p.get("quantum") != null and not touch_on:
		for i in UiUtil.ABILITIES.size():
			var info: Dictionary = UiUtil.ABILITIES[i]
			var st := UiUtil.ability_state(p, info)
			var r := Rect2(ax - 316.0 * s + i * 160.0 * s, base_y - 172.0 * s, 152.0 * s, 44.0 * s)
			var tint := UiUtil.AMBER if st["active"] else UiUtil.CYAN
			var dim := 1.0 if (st["ready"] or st["active"]) else 0.5
			_rect(c, r, UiUtil.PLATE)
			if float(st["cd"]) > 0.0:
				_rect(c, Rect2(r.position, Vector2(r.size.x * (1.0 - float(st["cd"])), r.size.y)), Color(tint, 0.25))
			elif st["active"]:
				_rect(c, r, Color(tint, 0.22))
			_frame(c, r, Color(tint, 0.8 * dim), 1.5 * s)
			var suffix := ""
			if st["active"]:
				suffix = "  %d" % ceili(float(st["left"]))
			elif info["action"] == &"blink" and float(UiUtil.num(p.get("quantum"), &"cd_blink", 0.0)) > 0.0:
				suffix = "  %.1f" % float(UiUtil.num(p.get("quantum"), &"cd_blink", 0.0))
			var label := UiUtil.ability_label(info, suffix, s)
			_text(c, font, Vector2(r.position.x, r.position.y + 32.0 * s), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UiUtil.fit_size(font, label, r.size.x - 8.0 * s, int(UiUtil.BAR_LABEL * s)), Color(1, 1, 1, 0.97 * dim), 1.0 * s)
	if playing:
		if UiSettings.s_chatter >= 2:
			_draw_quantum_readout(c, vp, s, font)
		_draw_tutorial(c, vp, s, font)
		if UiSettings.s_chatter >= 2 and veh == null:
			_draw_first_use(c, vp, s, font)
	if playing and veh == null:
		_draw_target_brackets(c, p, vp, s, font)
		_draw_crosshair(c, p, vp, s, now)
	if playing and veh != null and _radio_show > 0.0 and radio_text() != "":       # the station name shows for a moment after a change, then the screen is clear again
		var rt := radio_text()
		_plate_text(c, font, ab.get_center().x, ab.position.y - 42.0 * s, rt, int(UiUtil.BAR_LABEL * s), (UiUtil.CYAN if rt != "RADIO OFF" else Color(1, 1, 1, 0.6)), s)
	if playing and _hint_text != "" and veh == null:
		_plate_text(c, font, ab.get_center().x, ab.position.y - (92.0 * s if (p.get("quantum") == null or touch_on) else 152.0 * s), _hint_text, int(UiUtil.TEXT_MIN * s), Color(UiUtil.CYAN, 1.0), s)
	_draw_message(c, vp, s, font)


## THE damage vignette (the only full-screen hurt overlay in the game): a short red gathering at the screen edge after a hit, plus a slow faint pulse when
## health is low. Hard cap VIGNETTE_MAX, so it can never hide the world. `since_hurt` seconds since the last hit, `hp_f` health fraction 0..1.
static func vignette_alpha(since_hurt: float, hp_f: float, playing: bool, t: float) -> float:
	var a := clampf(1.0 - since_hurt / HURT_TIME, 0.0, 1.0) * 0.3
	if hp_f < 0.3 and playing:
		a = maxf(a, (0.3 - hp_f) / 0.3 * (0.14 + (0.0 if UiSettings.s_reduce_flash else 0.05 * sin(t * 5.0))))
	return minf(a, VIGNETTE_MAX)


## What the last blink told: Alice's two classical bits and the correction Bob applies. {visible, m0, m1, fix, alpha}; empty of meaning until a teleport.
func quantum_readout() -> Dictionary:
	var q: Object = Game.player.get("quantum") if is_instance_valid(Game.player) else null
	var left := UiUtil.num(q, &"bits_left", 0.0)
	return {
		"visible": q != null and left > 0.0,
		"m0": int(UiUtil.num(q, &"last_m0", 0.0)), "m1": int(UiUtil.num(q, &"last_m1", 0.0)),
		"fix": str(q.get("last_fix")) if q != null else "", "alpha": clampf(left / 0.8, 0.0, 1.0),
	}


## Thin-line teleport readout under the centre message: m1 -> X gate, m0 -> Z gate, a gate lights when Bob has to apply it.
func _draw_quantum_readout(c: Control, vp: Vector2, s: float, font: Font) -> void:
	var ro := quantum_readout()
	if not ro["visible"]:
		return
	var a: float = ro["alpha"]
	var w := 340.0 * s
	var box := Rect2(vp.x * 0.5 - w * 0.5, msg_top(s) + (MSG_H + 4.0) * s, w, 56.0 * s)
	_rect(c, box, Color(UiUtil.PLATE, UiUtil.PLATE.a * a))
	_frame(c, box, Color(UiUtil.CYAN, 0.55 * a), 1.0 * s)
	_text(c, font, Vector2(box.position.x, box.position.y + 18.0 * s), "QUANTUM TELEPORT", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, int(16.0 * s), Color(UiUtil.CYAN, 0.95 * a), 1.0 * s)
	for i in 2:
		var bit: int = ro["m1"] if i == 0 else ro["m0"]
		var gate := "X" if i == 0 else "Z"
		var x := box.position.x + 20.0 * s + i * 158.0 * s
		var y := box.position.y + 26.0 * s
		var on := bit == 1
		var rb := Rect2(x, y, 28.0 * s, 28.0 * s)
		_rect(c, rb, Color(UiUtil.CYAN, (0.3 if on else 0.08) * a))
		_frame(c, rb, Color(UiUtil.CYAN, 0.85 * a), 1.0 * s)
		_text(c, font, Vector2(rb.position.x, rb.position.y + 22.0 * s), str(bit), HORIZONTAL_ALIGNMENT_CENTER, rb.size.x, int(UiUtil.TEXT_MIN * s), Color(1, 1, 1, a), 1.0 * s)
		_text(c, font, Vector2(rb.end.x + 4.0 * s, rb.position.y + 21.0 * s), "m%d >" % (1 - i), HORIZONTAL_ALIGNMENT_LEFT, 44.0 * s, int(16.0 * s), Color(1, 1, 1, 0.85 * a), 1.0 * s)
		var rg := Rect2(x + 84.0 * s, y, 28.0 * s, 28.0 * s)
		_rect(c, rg, Color(UiUtil.MAGENTA, (0.5 if on else 0.06) * a))
		_frame(c, rg, Color(UiUtil.MAGENTA, (0.9 if on else 0.4) * a), 1.0 * s)
		_text(c, font, Vector2(rg.position.x, rg.position.y + 22.0 * s), gate, HORIZONTAL_ALIGNMENT_CENTER, rg.size.x, int(UiUtil.TEXT_MIN * s), Color(1, 1, 1, (1.0 if on else 0.5) * a), 1.0 * s)


## True while the chapter banner or a story card owns the top-centre: the toast is held back until it is gone (one banner at a time).
func banner_busy() -> bool:
	return is_instance_valid(Game.story) and (Game.story.banner_visible() or Game.story.cards_active())


## True when the toast `text` only repeats the campaign step line already on the plate ("1/3 CROSS THE TRADING FLOOR" and the toast CROSS THE TRADING FLOOR): the objective is said once (director review 3, #6).
func echoes_objective(text: String) -> bool:
	if _camp_text == "" or text == "":
		return false
	var a := Tr.t(text).strip_edges().to_upper()
	var b := _camp_text.strip_edges().to_upper()
	var sp := b.find(" ")
	if sp > 0 and sp <= 4 and b.substr(0, sp).contains("/"):      # the "1/3 " step counter in front
		b = b.substr(sp + 1).strip_edges()
	return a == b or a == Tr.t(b).to_upper() or b.begins_with(a) and a.length() >= 12


func _draw_message(c: Control, vp: Vector2, s: float, font: Font) -> void:
	if message_left <= 0.0 or message_text == "" or Game.state != &"play" or banner_busy() or echoes_objective(message_text):
		return
	var fade := clampf(minf(message_left / 0.4, (_msg_total - message_left) / 0.12 + 0.3), 0.0, 1.0)
	var size := int(30.0 * s)
	var r := msg_rect(vp, s, message_text, size, font)
	var lines := msg_wrap(vp, s, message_text, size, font)
	var line_h := float(size) * 1.15
	_rect(c, r, Color(UiUtil.PLATE, UiUtil.PLATE.a * fade))
	_rect(c, Rect2(r.position.x, r.end.y - 2.0 * s, r.size.x, 2.0 * s), Color(UiUtil.CYAN, 0.5 * fade))
	for i in lines.size():          # a long toast wraps onto a second line (never clipped at the plate edge); a line wider than the plate still shrinks to fit it
		var fs := UiUtil.fit_size(font, Tr.t(lines[i]), r.size.x - 16.0 * s, size)
		_text(c, font, Vector2(r.position.x, r.position.y + 34.0 * s + float(i) * line_h), lines[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color(1, 1, 1, 0.98 * fade), 2.0 * s)


## The toast text as lines: always exactly one (the toast channel allows a single line).
func msg_wrap(_vp: Vector2, _s: float, text: String, _size: int, _font: Font) -> Array[String]:
	return [text]                                            # ONE line always: a long one shrinks to the plate in _draw_message


## The widest a toast may be: the screen minus the subtitle column on each side (the chapter banner's lane).
func msg_max_width(vp: Vector2, s: float) -> float:
	return clampf(vp.x - 2.0 * (UiUtil.insets(vp).x + SUB_LANE * s), 300.0 * s, 760.0 * s)


## Top of the toast plate: under the top stack, and under the chapter banner while that one shows.
func msg_top(s: float) -> float:
	var y := (UiUtil.stack_bottom + MSG_GAP) * s
	if is_instance_valid(Game.story) and Game.story.has_method(&"banner_visible") and Game.story.call(&"banner_visible"):
		y += (134.0 if UiSettings.s_chatter >= 2 else 86.0) * s
	return y


## The toast plate for `text` (its text shrinks to the plate, see _text). Position rule: the plate never covers the hero's face (face_rect): when the default spot under the
## top stack would, it drops below the face (over the chest), else moves beside it, else sits as far from it as the lane allows.
func msg_rect(vp: Vector2, s: float, text: String, size: int, font: Font) -> Rect2:
	var lines := msg_wrap(vp, s, text, size, font)
	var widest := 0.0
	for ln in lines:
		widest = maxf(widest, _text_width(font, Tr.t(ln), size))
	var w := minf(widest + 40.0 * s, msg_max_width(vp, s))
	var r := Rect2(vp.x * 0.5 - w * 0.5, msg_top(s), w, MSG_H * s + float(lines.size() - 1) * float(size) * 1.15)
	var face := face_rect(vp, s)
	if face.size.x <= 0.0 or not r.intersects(face):
		return r
	var lane := Rect2(Vector2.ZERO, vp).grow(-8.0 * s)
	var low := Rect2(r.position.x, face.end.y + 6.0 * s, w, r.size.y)
	if lane.encloses(low) and low.end.y <= vp.y - UiUtil.insets_v(vp).y - 240.0 * s:       # keep clear of the bottom row of buttons and the ammo plate
		return low
	for x: float in [face.end.x + 6.0 * s, face.position.x - 6.0 * s - w]:
		var side := Rect2(x, r.position.y, w, r.size.y)
		if lane.encloses(side) and not side.intersects(face):
			return side
	return r


## Screen rectangle (px of the real viewport, scaled to `vp`) of the hero's face: head and chin projected through the live camera, padded. Empty (size 0) when the hero is not
## drawn there: in a vehicle, no camera, or behind it.
func face_rect(vp: Vector2, _s: float) -> Rect2:
	var p := Game.player as Node3D
	if p == null or not is_instance_valid(p) or not is_instance_valid(Game.camera) or p.get(&"vehicle") != null:
		return Rect2()
	var cam := Game.camera
	var right := cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var o := p.global_position
	var pts: Array[Vector3] = [o + Vector3(0.0, 1.86, 0.0), o + Vector3(0.0, 1.44, 0.0), o + Vector3(0.0, 1.65, 0.0) + right * 0.2, o + Vector3(0.0, 1.65, 0.0) - right * 0.2]
	var lo := Vector2(1.0e9, 1.0e9)
	var hi := Vector2(-1.0e9, -1.0e9)
	for pt in pts:
		if cam.is_position_behind(pt):
			return Rect2()
		var sp := cam.unproject_position(pt)
		lo = lo.min(sp)
		hi = hi.max(sp)
	var real := get_viewport().get_visible_rect().size
	var k := Vector2(vp.x / maxf(real.x, 1.0), vp.y / maxf(real.y, 1.0))
	return Rect2(lo * k, (hi - lo) * k).grow(10.0 * k.y)


## TARGET HIGHLIGHT: while a shot fired now would land on an enemy (AimAssist.on_target: its real shape, nothing in the way) four red corner brackets frame the enemy from feet to
## head, and the zone under the crosshair is named small under their feet (HEAD pays double). Nothing is drawn for an enemy the crosshair is merely near.
func _draw_target_brackets(c: Control, p: Node3D, vp: Vector2, s: float, font: Font) -> void:
	var assist := p.get_node_or_null("AimAssist") as AimAssist
	if assist == null or not assist.on_target or not is_instance_valid(assist.target) or not assist.target.has_method(&"body_box") or not is_instance_valid(Game.camera):
		return
	var cam := Game.camera
	var box: Array = assist.target.call(&"body_box")
	var lo_w: Vector3 = box[0]
	var hi_w: Vector3 = box[1]
	if cam.is_position_behind(lo_w) or cam.is_position_behind(hi_w):
		return
	var right := cam.global_transform.basis.x * float(box[2])
	var real := get_viewport().get_visible_rect().size
	var k := Vector2(vp.x / maxf(real.x, 1.0), vp.y / maxf(real.y, 1.0))
	var a := cam.unproject_position(lo_w) * k
	var b := cam.unproject_position(hi_w) * k
	var hw := maxf(absf((cam.unproject_position((lo_w + hi_w) * 0.5 + right) * k).x - (a.x + b.x) * 0.5), 6.0 * s)
	var r := Rect2(Vector2((a.x + b.x) * 0.5 - hw, minf(a.y, b.y)), Vector2(hw * 2.0, absf(a.y - b.y))).grow(4.0 * s)
	var arm := clampf(minf(r.size.x, r.size.y) * 0.28, 6.0 * s, 26.0 * s)
	var col := Color(1.0, 0.32, 0.26, 0.92)
	var w := 2.5 * s
	for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var o := r.position + r.size * corner
		var dx := Vector2(-1.0 if corner.x > 0.5 else 1.0, 0.0)
		var dy := Vector2(0.0, -1.0 if corner.y > 0.5 else 1.0)
		c.draw_line(o, o + dx * arm, Color(0, 0, 0, 0.55), w + 2.0 * s, false)
		c.draw_line(o, o + dy * arm, Color(0, 0, 0, 0.55), w + 2.0 * s, false)
		c.draw_line(o, o + dx * arm, col, w, false)
		c.draw_line(o, o + dy * arm, col, w, false)
	if assist.aim_zone == HitZones.HEAD and font != null:
		_plate_text(c, font, r.get_center().x, r.end.y + 4.0 * s, "HEAD", int(UiUtil.TEXT_MIN * s), Color(1.0, 0.85, 0.3), s)       # under the feet: above the box it sat on the crosshair


func _draw_crosshair(c: Control, p: Node3D, vp: Vector2, s: float, now: float) -> void:
	var mid := vp * 0.5
	var spread_px := float(p.call(&"spread_in_pixels", vp.y, vp.x)) if p.has_method(&"spread_in_pixels") else 0.0
	var gap := maxf(7.0 * s, spread_px)
	var col := Color(1, 1, 1, 0.9)
	var assist := p.get_node_or_null("AimAssist") as AimAssist
	if assist != null and assist.on_target:
		col = Color(1.0, 0.3, 0.25, 0.97) if assist.aim_zone != HitZones.HEAD else Color(1.0, 0.82, 0.3, 0.97)       # a shot would hit: red (gold on the head)
		gap *= 0.85
	var hit_age := now - UiUtil.num(p, &"last_hit_time", -100.0)
	if hit_age < 0.12:
		gap *= 0.7 + 0.3 * (hit_age / 0.12)                             # the arms snap inward on a hit, then relax
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:       # arms are axis-aligned rectangles (they batch with the plates), dark edge under white
		var a0 := mid + dir * gap
		var a1 := mid + dir * (gap + 11.0 * s)
		var arm := Rect2(Vector2(minf(a0.x, a1.x), minf(a0.y, a1.y)), Vector2(absf(a1.x - a0.x), absf(a1.y - a0.y)))
		arm = arm.grow_individual(0.0, 1.0 * s, 0.0, 1.0 * s) if dir.x != 0.0 else arm.grow_individual(1.0 * s, 0.0, 1.0 * s, 0.0)     # 2 px thick
		_rect(c, arm.grow(1.0 * s), Color(0, 0, 0, 0.5))
		_rect(c, arm, col)
	_sprite(c, &"disc", Rect2(mid - Vector2(1.6, 1.6) * s, Vector2(3.2, 3.2) * s), Color(1, 1, 1, 0.9))
	var since := now - UiUtil.num(p, &"last_hit_time", -100.0)
	if since < 0.28:
		var kill: bool = p.get("last_hit_kill") == true
		var strong: bool = kill or p.get("last_hit_crit") == true
		var k := 1.0 - since / 0.28                                     # 1 -> 0
		var hc := Color(1.0, 0.3, 0.25, 0.4 + 0.6 * k) if kill else (Color(1.0, 0.82, 0.3, 0.4 + 0.6 * k) if strong else Color(1, 1, 1, 0.4 + 0.6 * k))       # white hit, gold head shot, red kill
		var out := (22.0 + (8.0 if kill else 0.0) + 8.0 * (1.0 - k)) * s     # the X pops outward as it fades
		if kill:
			c.draw_arc(mid, (26.0 + 22.0 * (1.0 - k)) * s, 0.0, TAU, 24, Color(1.0, 0.3, 0.25, 0.8 * k), 2.5 * s, false)   # kill confirmation ring
		var inner := 10.0 * s
		var w := (4.5 if strong else 3.5) * s
		for d: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			c.draw_line(mid + d * inner, mid + d * out, Color(0, 0, 0, 0.55 * k), w + 2.0 * s, false)
			c.draw_line(mid + d * inner, mid + d * out, hc, w, false)


## A red arc around the crosshair that points at where the last hit came from (relative to the view direction).
func _draw_hurt_direction(c: Control, p: Node3D, vp: Vector2, s: float, alpha: float) -> void:
	var from: Variant = p.get("last_hurt_from")
	if not (from is Vector3) or (from as Vector3) == Vector3.ZERO or not is_instance_valid(Game.camera):
		return
	var d := (from as Vector3) - p.global_position
	var b := Game.camera.global_transform.basis
	var fwd := Vector2(-b.z.x, -b.z.z)
	if fwd.length() < 0.001 or Vector2(d.x, d.z).length() < 0.01:
		return
	fwd = fwd.normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var flat := Vector2(d.x, d.z)
	var ang := atan2(flat.dot(right), flat.dot(fwd)) - PI * 0.5
	var mid := vp * 0.5
	var rad := minf(vp.y * 0.30, 230.0 * s)                         # well clear of the crosshair and the target, readable at a glance on a phone
	c.draw_arc(mid, rad, ang - 0.42, ang + 0.42, 14, Color(0.0, 0.0, 0.0, 0.45 * alpha), 16.0 * s, true)
	c.draw_arc(mid, rad, ang - 0.38, ang + 0.38, 14, Color(1.0, 0.22, 0.18, 0.95 * alpha), 11.0 * s, true)
	var tip := mid + Vector2(cos(ang), sin(ang)) * (rad + 18.0 * s)    # chevron tip pointing at the attacker
	c.draw_line(tip, tip + Vector2(cos(ang + 2.6), sin(ang + 2.6)) * 22.0 * s, Color(1.0, 0.3, 0.25, alpha), 5.0 * s, true)
	c.draw_line(tip, tip + Vector2(cos(ang - 2.6), sin(ang - 2.6)) * 22.0 * s, Color(1.0, 0.3, 0.25, alpha), 5.0 * s, true)


## Red wedges on an oval round the crosshair, one per trooper of the patrol wave that is NOT on screen (beside the view or behind the hero): where to look. Nothing for a trooper the
## player can see (its own body says where it is) and nothing outside a wave. At most EDGE_MAX wedges, no allocation beyond the polygon points.
const EDGE_MAX := 8


## Screen angles (radians as drawn: 0 = right, y down) of the live wave's troopers that are off screen. At most EDGE_MAX. Empty outside a wave.
func threat_edge_angles() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var enc := Encounters.current
	if enc == null or enc.state != &"wave" or not is_instance_valid(Game.camera) or not is_instance_valid(Game.player):
		return out
	var cam := Game.camera
	var b := cam.global_transform.basis
	var fwd := Vector2(-b.z.x, -b.z.z)
	if fwd.length() < 0.001:
		return out
	fwd = fwd.normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var vp := get_viewport().get_visible_rect().size
	var view := Rect2(Vector2.ZERO, vp).grow(-36.0)
	var ppos := (Game.player as Node3D).global_position
	for d in enc.squad:
		if out.size() >= EDGE_MAX:
			break
		if not is_instance_valid(d) or d.dead or not d.active:
			continue
		var pos: Vector3 = d.global_position + Vector3(0.0, 1.2, 0.0)
		if not cam.is_position_behind(pos) and view.has_point(cam.unproject_position(pos)):
			continue
		var flat := Vector2(pos.x - ppos.x, pos.z - ppos.z)
		if flat.length() < 0.5:
			continue
		out.append(atan2(flat.dot(right), flat.dot(fwd)) - PI * 0.5)
	return out


func _draw_threat_edges(c: Control, vp: Vector2, s: float) -> void:
	var angles := threat_edge_angles()
	if angles.is_empty():
		return
	var mid := vp * 0.5
	var pulse := 0.65 + 0.3 * sin(_t * 7.0)
	for ang in angles:
		var dir := Vector2(cos(ang), sin(ang))
		var at := mid + Vector2(dir.x * (vp.x * 0.5 - 70.0 * s), dir.y * (vp.y * 0.5 - 70.0 * s))
		var side := Vector2(-dir.y, dir.x)
		var sz := 20.0 * s
		var tri := PackedVector2Array([at + dir * sz, at - dir * sz * 0.6 + side * sz * 0.8, at - dir * sz * 0.6 - side * sz * 0.8])
		var back := PackedVector2Array([at + dir * sz * 1.35, at - dir * sz * 0.85 + side * sz * 1.1, at - dir * sz * 0.85 - side * sz * 1.1])
		c.draw_colored_polygon(back, Color(0.0, 0.0, 0.0, 0.5))
		c.draw_colored_polygon(tri, Color(1.0, 0.25, 0.2, pulse))


# ---------------------------------------------------------------------------------------------------------------------
# screens
# ---------------------------------------------------------------------------------------------------------------------

func _ensure_layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var key := "%s|%d|%d|%d|%d|%s%s%s|%s%s%d|%s%s" % [Game.state, int(vp.x), int(vp.y), Game.tier_index(), int(settings.quality), settings.post, settings.muted, settings.cutscenes, _shop_open, _has_save, _wallet(), _chapters_open, _chapters_ok()]
	key += "|%s%d" % [_side_open, SideBoard.page]
	key += "|h%s%s%s%s" % [_heist_open, HeistBoard.sel, HeistBoard.approach, HeistBoard.crew]
	key += "|B%s%s" % [_board_open, MissionBoardScreen.key() if _board_open else ""]
	var shp := Game.progress as Progress
	var shlv := str(shp.safehouse_lv).hash() if shp != null else 0
	key += "|s%s%s%d%d%s" % [_safe_open, Safehouses.sel, Safehouses.rest_to, Safehouses.owned_count(shp), shlv]
	key += "|r%s%s%s%s" % [_arena_open, ArenaBoard.mode, ArenaBoard.diff, ArenaBoard.mods]
	key += "|k%s%d%d%d" % [_skills_open, SkillTree.xp, SkillTree.spent(), _wallet()]
	key += "|a%s%d" % [_ach_open, _ach_page]
	key += "|c%s%d%d%d%d%s%d" % [_craft_open, CraftScreen.page, CraftScreen.grid_page, Crafting.rev, CraftScreen.sel_item, CraftScreen.sel_bp, WeaponDefs.last_used.hash()]
	key += "|%s%s%s%s%d%s%d" % [_look_open, str(Game.progress.hero.to_save()) if Game.progress != null and Game.progress.get("hero") != null else "", _loadout_open, _loadout_w, Attachments.owned.size(), str(Attachments.equipped).hash(), WeaponDefs.unlocked.size() * 10 + LoadoutScreen.page + ShopScreen.weapon_page * 100 + str(WeaponsScreen.sel).hash() % 997 * 1000]
	key += "|g%d%s%s%d%d" % [_loadout_page, Gear.throwable, Gear.gadget, Gear.owned.size(), Gear.active_slot]
	key += "|G%s%s" % [_gear_open, _hero_hub]
	key += "|%s%d%d%d%d%d%s" % [_options_open, int(settings.hud_scale * 100.0), UiSettings.s_opt_page, UiSettings.s_opt_tab, ControlsScreen.tab, ControlsScreen.page, ControlsScreen.listening]
	if photo != null and photo.active:
		key += "|p%s%s%s%d%d%s%d%d%d%d" % [photo.hide_ui, photo.hide_hero, photo.pan_mode, photo.filter_i, photo.pose_i, photo.hour_text(), roundi(photo.fov), roundi(photo.dof * 100.0), roundi(photo.dist * 10.0), int(photo.status_left > 0.0)]
	if key == _layout_key:
		return
	_layout_key = key
	buttons.clear()
	var s := UiUtil.ui_scale(vp)
	var cx := vp.x * 0.5
	match Game.state:
		&"menu":
			var dy := _title_shift()                                       # the title block moves up when a second 64 px row joins the first
			if _options_open:
				OptionsScreen.layout(self, settings, cx, s)
			elif _arena_open:
				ArenaBoard.layout(self, cx, s)
			elif _chapters_open:
				ChapterSelect.layout(self, cx, s)
			elif _gear_open:
				_layout_more(vp, cx, s)
			else:                                                      # PLAY / CONTINUE, OPTIONS, MORE: nothing else on the title
				_add_card(&"continue" if _has_save else &"deploy", Rect2(cx - 204.0 * s, (310.0 + dy) * s, 408.0 * s, 76.0 * s), "CONTINUE" if _has_save else "PLAY", &"play", "", true)
				_add_card(&"options", Rect2(cx - 204.0 * s, (398.0 + dy) * s, 200.0 * s, 68.0 * s), "OPTIONS", &"options")
				_add_card(&"menu_gear", Rect2(cx + 4.0 * s, (398.0 + dy) * s, 200.0 * s, 68.0 * s), "EXTRAS", &"more")
		&"paused":
			if photo_open():
				PhotoScreen.layout(self, photo, vp, s)
			elif _board_open:
				MissionBoardScreen.layout(self, cx, s)
			elif _options_open:
				OptionsScreen.layout(self, settings, cx, s)
			elif _arena_open:
				ArenaBoard.layout(self, cx, s)
			elif _chapters_open:
				ChapterSelect.layout(self, cx, s)
			elif _craft_open:
				if _hero_hub:
					ShopScreen.tabs(self, cx, s, &"hero_tab_craft")
				CraftScreen.layout(self, cx, s)
			elif _skills_open:
				if _hero_hub:
					ShopScreen.tabs(self, cx, s, &"hero_tab_skills")
				SkillScreen.layout(self, cx, s)
			elif _heist_open:
				HeistBoard.layout(self, cx, s)
			elif _side_open:
				SideBoard.layout(self, cx, s)
			elif _look_open:
				LookScreen.layout(self, cx, s)
			elif _loadout_open and _loadout_page == 1:
				GearScreen.layout(self, cx, s)
			elif _loadout_open:
				LoadoutScreen.layout(self, cx, s, _loadout_w)
			elif _shop_open:
				ShopScreen.layout(self, cx, s)
			elif _ach_open:
				AchievementsScreen.layout(self, cx, s, _ach_page)
			elif _safe_open:
				SafehouseScreen.layout(self, cx, s)
			elif _gear_open:
				_layout_more(vp, cx, s)
			elif Game.progress != null:                                 # RESUME, MISSIONS, MAP, LOADOUT, UPGRADES, OPTIONS and EXTRAS: the whole pause menu
				var by := 0.0                                           # the MISSIONS card (the Mission Board) sits under RESUME when the board exists: one tap to the next job
				_add_card(&"resume", Rect2(cx - 232.0 * s, PAUSE_Y * s, 464.0 * s, 80.0 * s), "RESUME", &"play", "", true)
				if MissionBoardScreen.board() != null:
					_add_card(&"board_open", Rect2(cx - 232.0 * s, (PAUSE_Y + 96.0) * s, 464.0 * s, 72.0 * s), "MISSIONS", &"missions", "", false, UiUtil.AMBER)
					by = 80.0
				var py := PAUSE_Y + 96.0 + by                           # MAP LOADOUT / UPGRADES OPTIONS / EXTRAS (docs/DESIGN.md: the five screens of the default menu, the rest under EXTRAS)
				_add_card(&"pause_map", Rect2(cx - 232.0 * s, py * s, 228.0 * s, 72.0 * s), "MAP", &"map")
				_add_card(&"loadout", Rect2(cx + 4.0 * s, py * s, 228.0 * s, 72.0 * s), "LOADOUT", &"loadout")
				_add_card(&"hero_open", Rect2(cx - 232.0 * s, (py + 80.0) * s, 228.0 * s, 72.0 * s), "UPGRADES", &"hero")
				_add_card(&"options", Rect2(cx + 4.0 * s, (py + 80.0) * s, 228.0 * s, 72.0 * s), "OPTIONS", &"options")
				_add_card(&"menu_gear", Rect2(cx - 232.0 * s, (py + 160.0) * s, 464.0 * s, 64.0 * s), "EXTRAS", &"more")
			else:
				_add(&"resume", Rect2(cx - 170.0 * s, 238.0 * s, 340.0 * s, 64.0 * s), "RESUME", false)
				_add(&"menu", Rect2(cx - 154.0 * s, 314.0 * s, 308.0 * s, UiUtil.TOUCH_MIN * s), "ABORT TO MENU", false)
		&"dead":
			_add(&"respawn", Rect2(cx - 170.0 * s, 560.0 * s, 340.0 * s, 64.0 * s), "RESPAWN", false)      # low on the screen: the middle stays free for the world
		&"win":
			_add(&"next", Rect2(cx - 170.0 * s, 560.0 * s, 340.0 * s, 64.0 * s), "NEXT SECTOR", false)


## The entries of the EXTRAS page (button id, label) for the current screen. Default: the title lists NEW GAME, CHAPTERS and DEMO; the pause menu SUIT, PHOTO, CHAPTERS and ABORT TO
## MENU. The screens that the cut list hides (side jobs, heists, safehouse, achievements, boss rush) join them only while MenuFlags.show_cut() is on (Options > GAME > ALL EXTRAS, the DEMO).
func more_items() -> Array:
	var items: Array = []
	if Game.state == &"menu":
		if _has_save:
			items.append([&"deploy", "NEW GAME"])
		if _chapters_ok():
			items.append([&"chapters", "CHAPTERS"])
		if Game.progress != null:
			items.append([&"demo", "DEMO"])
			if MenuFlags.offered(&"arena_open"):
				items.append([&"arena_open", "ARENA"])
	else:
		items = [[&"look_open", "SUIT"], [&"photo_open", "PHOTO"]]
		if _chapters_ok():
			items.append([&"chapters", "CHAPTERS"])
		for cut: Array in [[&"side_open", "SIDE JOBS"], [&"heist_open", "HEISTS"], [&"sh_open", "SAFEHOUSE"], [&"ach", "ACHIEVEMENTS"], [&"arena_open", "ARENA"]]:
			if MenuFlags.offered(cut[0]):
				items.append(cut)
		items.append([&"menu", "ABORT TO MENU"])
	return items


const MORE_COLS := 3
const MORE_W := 276.0
const MORE_GAP := 10.0
const MORE_Y := 140.0
const MORE_H := 84.0
const MORE_PITCH := 94.0
## icon and one-line caption of every MORE card (id -> [icon, caption])
const MORE_META := {
	&"deploy": [&"plus", "Start over"], &"chapters": [&"chapters", "Pick a chapter"], &"demo": [&"demo", "Everything open"], &"arena_open": [&"arena", "Waves and bosses"],
	&"hero_open": [&"hero", "Upgrades and skills"], &"side_open": [&"missions", "Side jobs"], &"heist_open": [&"heists", "Big scores"], &"look_open": [&"suit", "Colours and looks"],
	&"sh_open": [&"safehouse", "Save points"], &"ach": [&"achievements", "Medals"], &"photo_open": [&"photo", "Photo mode"], &"menu": [&"abort", "Leave the game"],
}


## The cell `i` (row-major) of the MORE grid: three columns of 64 px buttons.
func more_cell(i: int, cx: float, s: float) -> Rect2:
	var w := minf(MORE_W, (get_viewport().get_visible_rect().size.x / s - 48.0) / float(MORE_COLS) - MORE_GAP)      # a narrow or square window shrinks the buttons instead of pushing the grid off screen
	return Rect2(cx + (-1.5 * w - MORE_GAP + float(i % MORE_COLS) * (w + MORE_GAP)) * s, (MORE_Y + float(i / MORE_COLS) * MORE_PITCH) * s, w * s, MORE_H * s)


## The reserved cell of the TEST button (test mode only; scripts/ui/test_menu.gd draws it): right after the last entry. Empty when the MORE page is closed.
func more_test_rect() -> Rect2:
	if not _gear_open or not (Game.state == &"menu" or Game.state == &"paused") or not _main_screen() or not TestMode.available():
		return Rect2()
	var vp := get_viewport().get_visible_rect().size
	return more_cell(more_items().size(), vp.x * 0.5, UiUtil.ui_scale(vp))


func _layout_more(vp: Vector2, cx: float, s: float) -> void:
	var items := more_items()
	for k in items.size():
		var meta: Array = MORE_META.get(items[k][0], [&"more", ""])
		_add_card(items[k][0], more_cell(k, cx, s), items[k][1], meta[0], meta[1], false, UiUtil.RED if items[k][0] == &"menu" else Color(0, 0, 0, 0))
	var n := items.size() + (1 if TestMode.available() else 0)
	_add_card(&"more_back", more_cell(n, cx, s), "BACK", &"back", "", false, UiUtil.AMBER)


## True on the plain title or pause screen (no sub screen open): the only place the gear shows.
func _main_screen() -> bool:
	if _options_open or _arena_open or _chapters_open or photo_open():
		return false
	if Game.state == &"paused":
		return not (_board_open or _craft_open or _skills_open or _heist_open or _side_open or _look_open or _loadout_open or _shop_open or _ach_open or _safe_open)
	return Game.state == &"menu"


## Vertical shift (base px) of the title block (name, rule, subtitle, tagline and the buttons under them) on the title screen: -20 when a second row of 64 px buttons (NEW GAME /
## CHAPTERS) needs the room, so the settings rows still end above the BEST line. 0 with the single DEPLOY button.
func _title_shift() -> float:
	return -20.0                                                   # the OPTIONS / MORE row always joins PLAY


## The plate behind the title block (name, rule, subtitle, tagline) on the title screen.
func title_plate(vp: Vector2, s: float) -> Rect2:
	var dy := _title_shift()
	var w := minf(vp.x - 2.0 * (UiUtil.insets(vp).x + 8.0 * s), 820.0 * s)
	var top := (196.0 + dy - TITLE_SIZE * 0.82 - TITLE_PLATE_PAD) * s
	return Rect2(vp.x * 0.5 - w * 0.5, top, w, (304.0 + dy) * s - top)


## The OPTIONS button: top right of the title and pause screens, 64 px tall.
func _options_btn(vp: Vector2, s: float) -> Rect2:
	return Rect2(vp.x - UiUtil.insets(vp).y - 196.0 * s, 6.0 * s, 180.0 * s, UiUtil.TOUCH_MIN * s)


func _add(id: StringName, r: Rect2, label: String, on: bool) -> void:
	buttons.append({"id": id, "rect": r, "label": label, "on": on})


## A menu card (scripts/ui/menu_kit.gd): an opaque plate with an icon, a title and an optional caption; `primary` is the one filled action of a screen.
func _add_card(id: StringName, r: Rect2, label: String, icon: StringName, sub := "", primary := false, tint := Color(0, 0, 0, 0)) -> void:
	var col := tint if tint.a > 0.0 else (UiUtil.CYAN if (id == &"resume" or id == &"next") else (UiUtil.MAGENTA if primary else UiUtil.CYAN))
	buttons.append({"id": id, "rect": r, "label": label, "on": false, "icon": icon, "sub": sub, "primary": primary, "tint": col})


## A whole-row button: its plate and frame are drawn, its label is not (the screen paints the row itself; the label stays for tests and the screen reader).
func _add_row(id: StringName, r: Rect2, label: String, on: bool) -> void:
	buttons.append({"id": id, "rect": r, "label": label, "on": on, "flat": true})


func _draw_screen(_ignored: Control = null) -> void:
	var c := _screen
	var vp := c.size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var cx := vp.x * 0.5
	var t0 := PerfTimers.start()
	_ensure_layout()
	_draw_screen_body(c, vp, s, font, cx)
	_flush_text()
	PerfTimers.stop(PerfTimers.SCREEN, t0)


func _draw_screen_body(c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var st := Game.state
	var ink := UiUtil.INK
	match st:
		&"menu":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(ink, 0.4))            # light: the animated city behind the title (scripts/cinematics) shows through
			c.draw_rect(Rect2(vp.x * 0.5 - 250.0 * s, 0.0, 500.0 * s, vp.y), Color(ink, 0.34))     # a darker column behind the title and buttons keeps them readable
			c.draw_rect(Rect2(vp.x * 0.5 - 330.0 * s, 0.0, 80.0 * s, vp.y), Color(ink, 0.12))      # soft shoulders: the column does not end in a hard edge
			c.draw_rect(Rect2(vp.x * 0.5 + 250.0 * s, 0.0, 80.0 * s, vp.y), Color(ink, 0.12))
		&"paused" when photo_open():
			PhotoScreen.draw(self, photo, c, vp, s, font)      # no dim: the live world is the picture
		&"paused":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(ink, SUBSCREEN_DIM if (_board_open or _shop_open or _ach_open or _skills_open or _side_open or _heist_open or _safe_open or _craft_open or _arena_open or _loadout_open or _look_open or _chapters_open or _options_open or _gear_open) else 0.7))
		&"dead":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.0, 0.02, DEAD_DIM * clampf(screen_age / 0.6, 0.0, 1.0)))      # a light dim fading in: the world stays visible
		&"win":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.06, 0.08, DEAD_DIM * clampf(screen_age / 0.6, 0.0, 1.0)))
	# no frame lines across the screen: they cut through the rows of every panel
	match st:
		&"menu" when _options_open:
			OptionsScreen.draw(self, c, vp, s, font, cx)
		&"menu" when _arena_open:
			ArenaBoard.draw(self, c, vp, s, font, cx)
		&"menu" when _chapters_open:
			ChapterSelect.draw(self, c, vp, s, font, cx)
		&"menu" when _gear_open:
			header(c, vp, s, font, "EXTRAS")
		&"menu":
			var dy := _title_shift()
			var tp := title_plate(vp, s)
			c.draw_rect(tp, Color(ink, 0.7))                           # a backing plate: the city's NEON / CLUB signs never show through the name, subtitle or tagline
			c.draw_rect(Rect2(tp.position, Vector2(tp.size.x, 2.0 * s)), Color(UiUtil.CYAN, 0.4))
			_text(c, font, Vector2(0.0, (196.0 + dy) * s), "QUANTUM TELEPORTAR", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(TITLE_SIZE * s), Color(1, 1, 1, 0.97), 3.0 * s)
			c.draw_line(Vector2(cx - 240.0 * s, (222.0 + dy) * s), Vector2(cx + 240.0 * s, (222.0 + dy) * s), Color(UiUtil.MAGENTA, 0.8), 2.0 * s)
			_text(c, font, Vector2(0.0, (258.0 + dy) * s), "OBSERVER CORP INCURSION  //  SECTOR 01", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
			if is_instance_valid(Game.story) and Game.story.has_method(&"tagline"):
				_text(c, font, Vector2(0.0, (294.0 + dy) * s), str(Game.story.call(&"tagline")), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(1, 1, 1, 0.85), 1.0 * s)
			if not touch_ui_on():
				_footer(c, vp, s, font)
		&"paused":
			if photo_open():
				pass                                               # drawn above (PhotoScreen.draw), buttons below
			elif _options_open:
				OptionsScreen.draw(self, c, vp, s, font, cx)
			elif _chapters_open:
				ChapterSelect.draw(self, c, vp, s, font, cx)
			elif _craft_open:
				CraftScreen.draw(self, c, vp, s, font, cx)
			elif _ach_open:
				AchievementsScreen.draw(self, c, vp, s, font, cx, _ach_page)
			elif _arena_open:
				ArenaBoard.draw(self, c, vp, s, font, cx)
			elif _skills_open:
				SkillScreen.draw(self, c, vp, s, font, cx)
			elif _board_open:
				MissionBoardScreen.draw(self, c, vp, s, font, cx)
			elif _heist_open:
				HeistBoard.draw(self, c, vp, s, font, cx)
			elif _side_open:
				SideBoard.draw(self, c, vp, s, font, cx)
			elif _look_open:
				LookScreen.draw(self, c, vp, s, font, cx)
			elif _loadout_open and _loadout_page == 1:
				GearScreen.draw(self, c, vp, s, font, cx)
			elif _loadout_open:
				LoadoutScreen.draw(self, c, vp, s, font, cx, _loadout_w)
			elif _safe_open:
				SafehouseScreen.draw(self, c, vp, s, font, cx)
			elif _shop_open:
				ShopScreen.draw(self, c, vp, s, font, cx)
			elif _gear_open:
				header(c, vp, s, font, "EXTRAS")
			else:
				_draw_pause_head(c, vp, s, font)
				if not touch_ui_on():
					_footer(c, vp, s, font)
		&"dead":
			_text(c, font, Vector2(0.0, 170.0 * s), "DECOHERED", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(84.0 * s), Color(UiUtil.RED, 0.97), 3.0 * s)
			_score_lines(c, vp, s, font, 226.0)
			var blink := 0.55 + 0.45 * sin(_t * 4.0) if screen_age >= LOCK else 0.25
			_text(c, font, Vector2(0.0, 664.0 * s), "TAP TO RESPAWN", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(24.0 * s), Color(1, 1, 1, blink))
		&"win":
			_text(c, font, Vector2(0.0, 170.0 * s), "SECTOR STABILIZED", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(76.0 * s), Color(UiUtil.CYAN, 0.97), 3.0 * s)
			_score_lines(c, vp, s, font, 226.0)
			var blink2 := 0.55 + 0.45 * sin(_t * 4.0) if screen_age >= LOCK else 0.25
			_text(c, font, Vector2(0.0, 664.0 * s), "TAP TO CONTINUE", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(24.0 * s), Color(1, 1, 1, blink2))
	var focus_ring := pad != null and pad.focus_visible()          # a controller is in use: the focused button gets a ring
	for b: Dictionary in buttons:
		var r: Rect2 = b["rect"]
		var big := r.size.y > 50.0 * s
		var on: bool = b["on"]
		var hot: bool = _hover == b["id"]
		var tint := UiUtil.MAGENTA if (big and b["id"] != &"next" and b["id"] != &"resume") else UiUtil.CYAN
		if b.has("tab"):                                       # a tab of a tab strip (menu_kit.gd)
			MenuKit.tab(self, c, r, Tr.t(str(b["label"])), b["tab"], on, hot, s, font)
			if focus_ring and b["id"] == pad.focus:
				c.draw_rect(r.grow(3.0 * s), Color(UiUtil.AMBER, 0.95), false, 2.0 * s)
			continue
		if b.has("prev"):                                      # the graphics tier card of the options screen (options_screen.gd)
			OptionsScreen.draw_card(self, c, r, hot, s, font)
			if focus_ring and b["id"] == pad.focus:
				c.draw_rect(r.grow(3.0 * s), Color(UiUtil.AMBER, 0.95), false, 2.0 * s)
			continue
		if b.has("opt"):                                       # an options row: name left, value chip right, slider track under it
			MenuKit.row(self, c, r, str(b["name"]), str(b["value"]), on, hot or _drag == b["id"], float(b["frac"]), s, font)
			if focus_ring and b["id"] == pad.focus:
				c.draw_rect(r.grow(3.0 * s), Color(UiUtil.AMBER, 0.95), false, 2.0 * s)
			continue
		if b.has("part"):                                      # a weapon part card (menu_kit.gd)
			MenuKit.part(self, c, r, Tr.t(str(b["name"])), Tr.t(str(b["fx"])), Tr.t(str(b["label"])), int(b["state"]), hot, s, font)
			if focus_ring and b["id"] == pad.focus:
				c.draw_rect(r.grow(3.0 * s), Color(UiUtil.AMBER, 0.95), false, 2.0 * s)
			continue
		if not b.has("icon") and not b.get("flat", false) and (str(b["id"]).ends_with("_back") and not str(b["id"]).begins_with("ctl_row")):      # every BACK is the same amber card with the arrow
			MenuKit.card(self, c, r, Tr.t(str(b["label"])), "", &"back", UiUtil.AMBER, on, hot, false, s, font)
			if focus_ring and b["id"] == pad.focus:
				c.draw_rect(r.grow(5.0 * s), Color(1, 1, 1, 0.5 + 0.4 * sin(_t * 6.0)), false, 3.0 * s)
				c.draw_rect(r.grow(2.0 * s), Color(UiUtil.AMBER, 0.95), false, 2.0 * s)
			continue
		if b.has("icon"):                                      # a card: opaque plate, icon, title and caption (menu_kit.gd)
			MenuKit.card(self, c, r, Tr.t(str(b["label"])), Tr.t(str(b["sub"])) if str(b["sub"]) != "" else "", b["icon"], b["tint"], on, hot, bool(b["primary"]), s, font)
			if focus_ring and b["id"] == pad.focus:
				c.draw_rect(r.grow(5.0 * s), Color(1, 1, 1, 0.5 + 0.4 * sin(_t * 6.0)), false, 3.0 * s)
				c.draw_rect(r.grow(2.0 * s), Color(UiUtil.AMBER, 0.95), false, 2.0 * s)
			continue
		if st == &"menu" or photo_open():
			c.draw_rect(r, Color(ink, 0.72))                  # a backing plate: a sign or a lit window behind a title button never shows through its label
		if SLIDERS.has(b["id"]) or OptionsScreen.is_slider(b["id"]) or PhotoScreen.is_slider(b["id"]):
			var vol := volume_of(b["id"]) if SLIDERS.has(b["id"]) else (photo.fraction(b["id"]) if PhotoScreen.is_slider(b["id"]) else OptionsScreen.fraction(settings, b["id"]))
			var inset := minf(8.0, r.size.x * 0.05)
			c.draw_rect(r, Color(tint, 0.10))
			c.draw_rect(Rect2(r.position.x + inset, r.position.y + r.size.y - 12.0 * s, (r.size.x - 2.0 * inset) * vol, 6.0 * s), Color(tint, 0.85))
			c.draw_rect(Rect2(r.position.x + inset + (r.size.x - 2.0 * inset) * vol - 2.0 * s, r.position.y + r.size.y - 19.0 * s, 4.0 * s, 14.0 * s), Color(1, 1, 1, 0.95))
			c.draw_rect(r, Color(tint, 0.95 if (hot or _drag == b["id"]) else 0.5), false, 1.5 * s)
			if focus_ring and b["id"] == pad.focus:
				c.draw_rect(r.grow(5.0 * s), Color(1, 1, 1, 0.5 + 0.4 * sin(_t * 6.0)), false, 3.0 * s)
				c.draw_rect(r.grow(2.0 * s), Color(UiUtil.AMBER, 0.95), false, 2.0 * s)
			_text(c, font, Vector2(r.position.x, r.position.y + 21.0 * s), (b["label"] if (OptionsScreen.is_slider(b["id"]) or PhotoScreen.is_slider(b["id"])) else "%s  %d" % [b["label"], roundi(vol * 100.0)]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(20.0 * s), Color(1, 1, 1, 0.95))
			continue
		if st != &"menu" and not photo_open():                 # an opaque plate under every plain screen button: the world never shows through a label
			c.draw_rect(r, MenuKit.FILL)
		c.draw_rect(r, Color(tint, 0.30 if (on or hot) else 0.10))
		c.draw_rect(r, Color(tint, 0.95 if (on or hot or big) else 0.5), false, 2.0 * s if big else 1.5 * s)
		if focus_ring and b["id"] == pad.focus:
			c.draw_rect(r.grow(5.0 * s), Color(1, 1, 1, 0.5 + 0.4 * sin(_t * 6.0)), false, 3.0 * s)
			c.draw_rect(r.grow(2.0 * s), Color(UiUtil.AMBER, 0.95), false, 2.0 * s)
		if b.has("pic"):                                       # a picture over the plate (ItemIcons: weapons, gear, vehicles, enemies)
			var pc: Dictionary = b["pic"]
			var ptex: Texture2D = ItemIcons.texture(str(pc["p"]), StringName(pc["id"]))
			if ptex != null:
				ItemIcons.draw_tex(c, ptex, pc["r"], Color(1, 1, 1, float(pc.get("a", 1.0))))
			elif str(pc["p"]) == "w":
				WeaponIcons.draw_flat(c, StringName(pc["id"]), pc["r"], Color(1, 1, 1, float(pc.get("a", 1.0))))
		if b.get("flat", false):
			continue
		if b.has("cap"):                                                                                         # a loadout tile: opaque plate, the weapon's own picture over its name
			var wid := StringName(String(b["id"]).substr(6))
			c.draw_rect(r, MenuKit.FILL_ON if (on or hot) else MenuKit.FILL)
			c.draw_rect(r, Color(UiUtil.MAGENTA if on else UiUtil.CYAN, 1.0 if on else 0.45), false, (3.0 if on else 1.5) * s)
			ItemIcons.draw_weapon(c, wid, Rect2(r.position.x + r.size.x * 0.06, r.position.y + 3.0 * s, r.size.x * 0.88, r.size.y * 0.56), Color(1, 1, 1, 1.0 if (on or hot) else 0.85))
			var csz := maxi(UiUtil.fit_size(font, str(b["cap"]), r.size.x - 8.0 * s, int(BODY_MIN * s)), int(BODY_MIN * s))
			_text(c, font, Vector2(r.position.x, r.position.y + r.size.y - 9.0 * s), str(b["cap"]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, csz, Color(1, 1, 1, 0.97 if (on or hot) else 0.78))
			continue
		if String(b["id"]).begins_with("wheel_") and WeaponIcons.has_icon(StringName(String(b["id"]).substr(6))):      # weapon wheel: icon over the tag
			WeaponIcons.draw(c, StringName(String(b["id"]).substr(6)), Rect2(r.position.x + r.size.x * 0.1, r.position.y + 3.0 * s, r.size.x * 0.8, r.size.y * 0.5), Color(1, 1, 1, 0.95 if (on or hot) else 0.8))
			_text(c, font, Vector2(r.position.x, r.position.y + r.size.y - 9.0 * s), b["label"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(17.0 * s), Color(1, 1, 1, 0.97 if (on or hot) else 0.75))
			continue
		var bl := Tr.t(str(b["label"]))
		var bcol := Color(1, 1, 1, 0.97 if (on or hot or big) else 0.8)
		var bw := r.size.x - 12.0 * s
		var bsz := UiUtil.fit_size(font, bl, bw, int((30.0 if big else 22.0) * s))
		if bsz < int(BODY_MIN * s) and bl.contains(" "):                  # too long for one line at a readable size: two lines (never a 10 px label)
			var ln := _split_label(bl)
			var longer: String = ln[0] if _text_width(font, ln[0], 20) >= _text_width(font, ln[1], 20) else ln[1]
			var sz2 := maxi(UiUtil.fit_size(font, longer, bw, int(20.0 * s)), int(BODY_MIN * s))
			var top := r.position.y + (r.size.y - sz2 * 2.15) * 0.5
			_text(c, font, Vector2(r.position.x, top + sz2 * 0.9), ln[0], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, sz2, bcol)
			_text(c, font, Vector2(r.position.x, top + sz2 * 2.0), ln[1], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, sz2, bcol)
			continue
		bsz = maxi(bsz, int(BODY_MIN * s))
		_text(c, font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + (10.0 if big else 7.0) * s), bl, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, bsz, bcol)


## A label split at the space nearest its middle (two lines of a button).
static func _split_label(label: String) -> Array[String]:
	var words := label.split(" ", false)
	if words.size() < 2:
		return [label, ""]
	var best := 1
	var best_d := 1 << 30
	for i in range(1, words.size()):
		var a := " ".join(words.slice(0, i)).length()
		var b := " ".join(words.slice(i)).length()
		if absi(a - b) < best_d:
			best_d = absi(a - b)
			best = i
	return [" ".join(words.slice(0, best)), " ".join(words.slice(best))]


## What the pause screen says to do now: the campaign step, else "CONTINUE THE STORY" while the story runs (never the old core counter next to it), else the core objective.
func pause_goal_line() -> String:
	var line := _campaign_line()
	if line == "":
		if Game.missions is Missions and (Game.missions as Missions).board_mode:
			line = "FREE ROAM   PICK A MISSION"                 # the Mission Board has no core counter ("NO ACTIVE OBJECTIVE" read as a dead game)
		else:
			line = "CONTINUE THE STORY" if campaign_owns_goal() else objective_text()
	return line


## The plain pause screen: the title, then what to do now (the one objective) and the wallet, so a returning player knows the next step before pressing RESUME.
func _draw_pause_head(c: Control, vp: Vector2, s: float, font: Font) -> void:
	header(c, vp, s, font, "PAUSED")
	var line := pause_goal_line()
	var shown := ("NOW  " + line.to_upper()) if line != "NO ACTIVE OBJECTIVE" else line
	var size := maxi(UiUtil.fit_size(font, shown, vp.x - 140.0 * s, int(UiUtil.BAR_LABEL * s)), int(BODY_MIN * s))
	var pr := _plate_text(c, font, vp.x * 0.5, 104.0 * s, shown, size, Color(UiUtil.CYAN, 1.0), s, Color(UiUtil.MAGENTA, 0.6), 320.0 * s)
	if Game.progress != null:
		_text(c, font, Vector2(0.0, pr.end.y + 32.0 * s), "CREDITS  %d" % _wallet(), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)


func _score_lines(c: Control, vp: Vector2, s: float, font: Font, y: float) -> void:
	var line1 := "CREDITS  %d" % Game.score if Game.progress == null else "SCORE  %d      CREDITS  %d" % [Game.score, _wallet()]
	_text(c, font, Vector2(0.0, y * s), line1, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(30.0 * s), Color(1, 1, 1, 0.95), 1.5 * s)
	var line := "NEW BEST" if new_best else "BEST  %d" % settings.best
	_text(c, font, Vector2(0.0, (y + 36.0) * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(20.0 * s), Color(UiUtil.AMBER, 0.95))


const PAUSE_Y := 214.0              ## base px: the RESUME button of the pause screen (the objective plate sits above it)
const HEAD_Y := 70.0                ## base px: baseline of the one title every pause / title sub screen shows (HEAD_SIZE tall)
const HEAD_SIZE := 44.0
const BODY_MIN := 15.0              ## base px: the smallest menu text (22 px at 1080p); anything smaller wraps or is cut from the design


## The title of a sub screen: one size, one place, a short accent rule under it (every screen asks for this instead of drawing its own).
func header(c: Control, vp: Vector2, s: float, font: Font, title: String, sub := "", sub_col := Color(UiUtil.AMBER, 0.97)) -> void:
	_text(c, font, Vector2(0.0, HEAD_Y * s), title, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(HEAD_SIZE * s), Color(1, 1, 1, 0.97), 3.0 * s)
	_rect(c, Rect2(vp.x * 0.5 - 56.0 * s, (HEAD_Y + 12.0) * s, 112.0 * s, 3.0 * s), Color(UiUtil.MAGENTA, 0.9))
	if sub != "":
		_text(c, font, Vector2(0.0, (HEAD_Y + 44.0) * s), sub, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * s), sub_col, 1.0 * s)


func _footer(c: Control, vp: Vector2, s: float, font: Font) -> void:
	var line := (CONTROLS_PAD_PLAY if Game.state == &"menu" else CONTROLS_PAD_MENU) if ControllerInput.pad_ui else (CONTROLS_TOUCH if touch_ui_on() else CONTROLS_DESKTOP)
	var size := int(18.0 * s)
	while size > int(12.0 * s) and _text_width(font, line, size) > vp.x - 40.0 * s:      # a wider fallback font must still fit the screen
		size -= 1
	_text(c, font, Vector2(0.0, vp.y - 44.0 * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, size, Color(1, 1, 1, 0.75), 1.0 * s)
	if Game.state == &"menu":
		_text(c, font, Vector2(0.0, vp.y - 90.0 * s), "BEST  %d" % settings.best, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)


# ---------------------------------------------------------------------------------------------------------------------
# contracts, boss bar, tutorial, wallet (gameplay depth)
# ---------------------------------------------------------------------------------------------------------------------

func _wallet() -> int:
	return int(Game.progress.get(&"credits")) if Game.progress != null else 0


func _contracts() -> Object:
	var m: Object = Game.missions if is_instance_valid(Game.missions) else null
	return m.get(&"contracts") if m != null else null


## The scripted campaign runner (Game.missions.campaign), null without one.
func _campaign() -> Object:
	var m: Object = Game.missions if is_instance_valid(Game.missions) else null
	return m.get(&"campaign") if m != null else null


## The campaign step line ("2/3  HACK THE LEDGER NODE  62%") or "" when no scripted step runs. It outranks the contract line and the core objective.
func _campaign_line() -> String:
	var k := _campaign()
	if InteriorGameplay.hud_line != "":
		return ""                                          # an interior mission's own line owns the plate inside: the player came in for it (the exit stays the compass target, and LEAVE THE BUILDING comes back the moment the job is done)
	if InteriorGameplay.active and k != null and k.get(&"guide") != null:
		var gl := str((k.get(&"guide") as MissionGuide).line())
		if gl.begins_with("LEAVE"):
			return gl                                      # the next step cannot start in here and the room has no job: the way out
	if InteriorGameplay.active and k != null:
		var kk := StringName(str(k.get(&"kind")))
		var wants_door := kk == &"enter_interior" and int(k.get(&"_phase")) == 1      # still going in: this is the wrong building, its distance is measured on the street
		if str(k.call(&"hud_line")) != "" and (wants_door or (kk != &"enter_interior" and kk != &"heist")):
			return "LEAVE THE BUILDING TO CONTINUE"         # a street step is running and the room has no job of its own: not "CROSS THE FLOOR  0 M"
	var line := str(k.call(&"hud_line")) if k != null else ""
	if line == "" and k != null and k.get(&"guide") != null:
		line = str((k.get(&"guide") as MissionGuide).line())          # between two steps: what comes next, or the way out of the building
	if line == "" and Game.missions is Missions and (Game.missions as Missions).chases != null:
		line = (Game.missions as Missions).chases.hud_line()      # a vehicle chase set piece (ChaseRunner)
	if line == "" and Game.missions is Missions and (Game.missions as Missions).stealth != null:
		line = (Game.missions as Missions).stealth.hud_line()     # a stealth mission (StealthRunner)
	if line == "" and Game.missions is Missions and (Game.missions as Missions).arena != null:
		line = (Game.missions as Missions).arena.hud_line()       # boss rush / arena (ArenaRunner)
	return line


## The safehouse screen's buttons (scripts/ui/safehouse_screen.gd): `sh_open` on the pause menu, then pick, buy / claim, the services of an owned house, upgrades, BACK.
func _press_safehouse(sid: String) -> bool:
	var prog := Game.progress as Progress
	if Game.state != &"paused" or prog == null:
		return false
	var id := Safehouses.sel
	var ok := true
	if sid == "sh_open":
		if _safe_open or photo_open() or _shop_open or _options_open or _chapters_open or _arena_open or _heist_open or _side_open or _skills_open or _look_open or _loadout_open or _ach_open or _craft_open:
			return false
		_safe_open = true
		Sfx.play(&"ui_confirm")
		_layout_key = ""
		_screen.queue_redraw()
		return true
	if not _safe_open or look_or_sub_open():
		return false
	if sid.begins_with("sh_pick_") and Safehouses.DEFS.has(StringName(sid.substr(8))):
		Safehouses.sel = StringName(sid.substr(8))
		Sfx.play(&"ui_tap")
	elif sid == "sh_back":
		_safe_open = false
		Sfx.play(&"ui_back")
	elif sid == "sh_buy":
		ok = Safehouses.buy(prog, id)
		Sfx.play(&"ui_purchase" if ok else &"ui_deny")
	elif sid == "sh_claim":
		ok = Safehouses.claim(prog, id)
		Sfx.play(&"ui_purchase" if ok else &"ui_deny")
	elif not Safehouses.is_owned(prog, id):
		return false
	elif sid == "sh_wardrobe":
		_look_open = true
		Sfx.play(&"ui_confirm")
	elif sid == "sh_bench":
		_loadout_open = true
		_loadout_quick = false
		_loadout_page = 0
		_loadout_w = WeaponDefs.last_used
		LoadoutScreen.reset_page()
		Sfx.play(&"ui_confirm")
	elif sid == "sh_craft":
		return _press_craft("cr_open")
	elif sid == "sh_trophy":
		_ach_open = true
		_ach_page = 0
		Sfx.play(&"ui_confirm")
	elif sid == "sh_garage":
		var tc: Array[Node] = get_tree().root.find_children("*", "TouchControls", true, false)
		if tc.is_empty():
			Sfx.play(&"ui_deny")
			return false
		(tc[0] as TouchControls)._open_garage()
		Sfx.play(&"ui_confirm")
	elif sid == "sh_rest":
		ok = Safehouses.rest(prog, id)
		Sfx.play(&"ui_confirm" if ok else &"ui_deny")
	elif sid == "sh_time":
		Safehouses.cycle_time()
		Sfx.play(&"ui_tap")
	elif sid == "sh_save":
		ok = Safehouses.fast_save(prog, id)
		Sfx.play(&"ui_confirm" if ok else &"ui_deny")
	elif sid == "sh_go":
		ok = Safehouses.travel(prog, id)
		Sfx.play(&"ui_confirm" if ok else &"ui_deny")
	elif sid.begins_with("sh_up_") and Safehouses.UPS.has(StringName(sid.substr(6))):
		ok = Safehouses.upgrade(prog, id, StringName(sid.substr(6)))
		Sfx.play(&"ui_upgrade" if ok else &"ui_deny")
	else:
		return false
	_layout_key = ""
	_screen.queue_redraw()
	return ok


## True while a sub-screen opened from the safehouse (look, loadout, achievements) is on top of it.
func look_or_sub_open() -> bool:
	return _look_open or _loadout_open or _ach_open or _craft_open


## Leaves the HERO hub when one of its tabs is backed out of (skills, workbench): the tab bar goes with it, the shop screen under it too.
func _close_hero() -> void:
	if _hero_hub:
		_hero_hub = false
		_shop_open = false
		_skills_open = false
		_craft_open = false


## The workbench (scripts/ui/craft_screen.gd): `cr_open` from the shop, a safehouse or the DEMO menu (the pause menu otherwise), then the screen's own buttons, `cr_back` returns.
func _press_craft(sid: String) -> bool:
	if Game.state != &"paused" or Game.progress == null or photo_open():
		return false
	if sid == "cr_open":
		if _craft_open or _options_open or _chapters_open or _arena_open or _heist_open or _side_open or _skills_open or _look_open or _loadout_open or _ach_open:
			return false
		_craft_open = true
		CraftScreen.reset_state()
		Sfx.play(&"ui_confirm")
		_layout_key = ""
		_screen.queue_redraw()
		return true
	if not _craft_open:
		return false
	var ok := true
	if sid == "cr_back":
		_craft_open = false
		_close_hero()
		Sfx.play(&"ui_back")
	else:
		ok = CraftScreen.press(sid)
		Sfx.play(&"ui_purchase" if ok and (sid == "cr_make" or sid.begins_with("cr_cell_")) else (&"ui_tap" if ok else &"ui_deny"))
	_layout_key = ""
	_screen.queue_redraw()
	return ok


## The heist planning screen's buttons (scripts/ui/heist_board.gd): open from the shop, pick, approach, crew, LAUNCH, BACK.
## Opens the Mission Board: from the game (the map's MISSIONS button, the result card's NEXT) the game pauses; FREE ROAM, a started mission and RESUME all return to play.
func open_board() -> bool:
	var board := MissionBoardScreen.board()
	if board == null or photo_open():
		return false
	if Game.state == &"play":
		Game.state = &"paused"                                          # _on_state clears every screen flag first, then the board opens below
	elif Game.state == &"paused":
		if not _board_open and not _main_screen():
			return false
	else:
		return false
	board.refresh_if_stale()
	_board_open = true
	Sfx.play(&"ui_confirm")
	_layout_key = ""
	_screen.queue_redraw()
	return true


## The Mission Board's buttons (scripts/ui/mission_board_screen.gd).
func _press_board(sid: String) -> bool:
	var board := MissionBoardScreen.board()
	if board == null:
		return false
	if sid == "board_open":
		return Game.state == &"paused" and not _board_open and open_board()
	if Game.state != &"paused" or not _board_open:
		return false
	if sid == "board_back":                                             # FREE ROAM: the game runs again, wherever the board was opened from
		Sfx.play(&"ui_back")
		Game.state = &"play"                                            # _on_state closes the board
		return true
	if sid.begins_with("board_diff_"):
		var m := clampi(int(sid.substr(11)), 0, 2)
		Difficulty.set_mode(m)
		settings.difficulty = m
		settings.save()
		Sfx.play(&"ui_tap")
	elif sid == "board_new":
		board.generate()
		Sfx.play(&"ui_tap")
	elif sid == "board_story" or sid.begins_with("board_pick_"):
		var idx := -1 if sid == "board_story" else int(sid.substr(11))
		if not board.can_start() or (idx >= 0 and idx >= board.offers.size()) or (idx < 0 and board.story_offer().is_empty()):
			Sfx.play(&"ui_deny")
			return false
		Game.state = &"play"                                            # _on_state closes the board; the mission starts in the live city
		if not board.accept(idx):
			return false
		Sfx.play(&"ui_contract_accept")
		return true
	elif sid == "board_retry":
		Game.state = &"play"
		if not board.retry_step():
			return false
		return true
	elif sid == "board_abandon":
		board.abandon("ABANDONED")
		Sfx.play(&"ui_back")
	else:
		return false
	_layout_key = ""
	_screen.queue_redraw()
	return true


func _press_heist(sid: String) -> bool:
	if Game.state != &"paused" or Game.progress == null:
		return false
	if sid == "heist_open":
		if _heist_open:
			return false
		_heist_open = true
		Sfx.play(&"ui_confirm")
	elif not _heist_open:
		return false
	elif sid == "heist_back":
		_heist_open = false
		Sfx.play(&"ui_back")
	elif sid.begins_with("heist_pick_") and HeistScripts.DEFS.has(StringName(sid.substr(11))):
		HeistBoard.sel = StringName(sid.substr(11))
		Sfx.play(&"ui_tap")
	elif sid.begins_with("heist_ap_") and HeistScripts.APPROACH_DEFS.has(StringName(sid.substr(9))):
		HeistBoard.approach = StringName(sid.substr(9))
		Sfx.play(&"ui_tap")
	elif sid == "heist_crew":
		HeistBoard.crew = not HeistBoard.crew
		Sfx.play(&"ui_tap")
	elif sid == "heist_go":
		var hr := HeistBoard.runner()
		if hr == null or not hr.can_start(HeistBoard.sel):
			Sfx.play(&"ui_deny")
			return false
		var hid := HeistBoard.sel
		Game.state = &"play"                                           # _on_state closes the screen; the heist starts in the live city
		if not hr.start(hid, HeistBoard.approach, HeistBoard.crew):
			return false
		Sfx.play(&"ui_contract_accept")
		return true
	else:
		return false
	_layout_key = ""
	_screen.queue_redraw()
	return true


## The photo mode buttons (scripts/ui/photo_screen.gd): `photo_open` on the pause menu, the rest only while photo mode runs. Sliders act through slide().
func _press_photo(sid: String) -> bool:
	if sid == "photo_open":
		if Game.state != &"paused" or photo_open() or _shop_open or _options_open or _chapters_open or _arena_open or _heist_open or _safe_open or _side_open or _skills_open or _look_open or _loadout_open or _ach_open or _craft_open:
			return false
		if not photo.begin():
			return false
		Sfx.play(&"ui_confirm")
		return true
	if not photo_open() or PhotoScreen.is_slider(StringName(sid)):
		return false
	match sid:
		"photo_exit": photo.end()
		"photo_shot": photo.capture()
		"photo_share": photo.share()
		"photo_ui": photo.toggle_ui()
		"photo_hero": photo.toggle_hero()
		"photo_filter": photo.set_filter(photo.filter_i + 1)
		"photo_pose": photo.set_pose(photo.pose_i + 1)
		"photo_mode": photo.toggle_pan_mode()
		_: return false
	Sfx.play(&"ui_tap")
	_layout_key = ""
	_screen.queue_redraw()
	return true


## The boss rush / arena screen's buttons (scripts/ui/arena_board.gd): open (title or pause), mode, difficulty, modifiers, LAUNCH, LEAVE, BACK.
func _press_arena(sid: String) -> bool:
	if Game.progress == null or (Game.state != &"menu" and Game.state != &"paused"):
		return false
	if sid == "arena_open":
		if _shop_open or _options_open or _chapters_open:
			return false
		_arena_open = true
		Sfx.play(&"ui_confirm")
	elif not _arena_open:
		return false
	elif sid == "arena_back":
		_arena_open = false
		Sfx.play(&"ui_back")
	elif sid == "arena_mode_rush" or sid == "arena_mode_endless":
		ArenaBoard.mode = StringName(sid.substr(11))
		Sfx.play(&"ui_tap")
	elif sid.begins_with("arena_d_") and ArenaScripts.DIFF_DEFS.has(StringName(sid.substr(8))):
		ArenaBoard.diff = StringName(sid.substr(8))
		Sfx.play(&"ui_tap")
	elif sid.begins_with("arena_m_") and ArenaScripts.MOD_DEFS.has(StringName(sid.substr(8))):
		ArenaBoard.toggle_mod(StringName(sid.substr(8)))
		Sfx.play(&"ui_tap")
	elif sid == "arena_leave":
		var ar := ArenaBoard.runner()
		if ar == null or not ar.is_running():
			return false
		ar.abort("LEFT")
		Sfx.play(&"ui_back")
	elif sid == "arena_go":
		var r := ArenaBoard.runner()
		if r == null:
			return false
		if Game.state == &"menu":
			Game.start_new_game()                                      # the title entry: deploy into the city first (like DEPLOY), then the run begins
		elif not r.can_start():
			Sfx.play(&"ui_deny")
			return false
		else:
			Game.state = &"play"
		if not r.start(ArenaBoard.mode, ArenaBoard.diff, ArenaBoard.mods):
			return false
		Sfx.play(&"ui_contract_accept")
		return true
	else:
		return false
	_layout_key = ""
	_screen.queue_redraw()
	return true


## True when the title / pause screen has chapters to choose from (Progress.can_select_chapter).
func _chapters_ok() -> bool:
	return Game.progress != null and Game.progress.has_method(&"can_select_chapter") and bool(Game.progress.call(&"can_select_chapter"))


## The contract line ("HACK NODE  62%  1:20") or "" when none is offered or running.
func _contract_line() -> String:
	if InteriorGameplay.hud_line != "":                     # an interior mission replaces the contract line while you are inside
		return InteriorGameplay.hud_line
	if InteriorGameplay.active and InteriorGameplay.status_line != "":
		return InteriorGameplay.status_line                 # the task status: the room has no job line, so the plate still says what there is to do (or that nothing is)
	var k := _contracts()
	return str(k.call(&"hud_line")) if k != null else ""


## The tutorial node of the story layer (null without a story).
func tutorial() -> Object:
	var st: Object = Game.story if is_instance_valid(Game.story) else null
	return st.get(&"tutorial") if st != null else null


## THE priority line under the bars: the contract line while one is offered or running (amber, with a thin progress bar), otherwise the core objective (magenta).
## The officer's boss bar hangs under it. Returns the new bottom of the stack (px).
## Side-activity plate (time, score, best) under the top stack; returns the new bottom of the stack.
func _draw_activity(c: Control, vp: Vector2, s: float, font: Font, y: float) -> float:
	var a := get_tree().get_first_node_in_group(&"activities")
	if a == null:
		return y - 3.0 * s
	var ro: Dictionary = a.call(&"readout")
	if not ro["visible"]:
		return y - 3.0 * s
	var text := "%s   %s   %s   %s" % [ro["title"], ro["time"], ro["score"], ro["best"]]
	var size := int(UiUtil.TEXT_MIN * s)
	while size > int(14.0 * s) and _text_width(font, text, size) + 36.0 * s > vp.x - 40.0 * s:
		size -= 1
	return _plate_text(c, font, vp.x * 0.5, y, text, size, Color(UiUtil.AMBER.lerp(Color.WHITE, 0.35), 1.0), s, Color(UiUtil.AMBER, 0.7)).end.y


## The stealth mission's alert meter under the priority plate: a bar that fills with the worst guard's suspicion and turns red when one is alerted. Returns the new stack end.
func _draw_stealth_meter(c: Control, vp: Vector2, s: float, font: Font, y: float) -> float:
	var st: StealthRunner = (Game.missions as Missions).stealth if Game.missions is Missions else null
	var mt: Dictionary = st.meter() if st != null else {}
	if mt.is_empty():
		return y - 3.0 * s
	var w := minf(260.0 * s, vp.x * 0.4)
	var frac := float(mt["frac"])
	var col := UiUtil.CYAN.lerp(UiUtil.AMBER, clampf(frac * 1.6, 0.0, 1.0)).lerp(UiUtil.RED, clampf((frac - 0.6) * 2.5, 0.0, 1.0))
	var plate := Rect2(vp.x * 0.5 - w * 0.5, y, w, 30.0 * s)
	_plate(c, plate, s, Color(col, 0.55))
	_text(c, font, Vector2(plate.position.x + 8.0 * s, plate.position.y + 15.0 * s), "ALERT  " + str(mt["label"]), HORIZONTAL_ALIGNMENT_LEFT, w - 16.0 * s, int(UiUtil.BAR_LABEL * s * 0.85), Color(col.lerp(Color.WHITE, 0.4), 0.97), 1.0 * s)
	var bar := Rect2(plate.position.x + 8.0 * s, plate.position.y + 20.0 * s, w - 16.0 * s, 6.0 * s)
	_rect(c, bar, Color(0.0, 0.03, 0.05, 0.7))
	_rect(c, Rect2(bar.position, Vector2(bar.size.x * clampf(frac, 0.0, 1.0), bar.size.y)), Color(col, 0.95))
	return plate.end.y + 3.0 * s


## True while the HUD shows a scripted step line (the plate is up).
func has_step_line() -> bool:
	return _camp_text != ""


## True while the scripted campaign is switched on and not finished: its step line, the compass and the beacon are then the only goal on screen (the old sector core counter stays out).
func campaign_owns_goal() -> bool:
	var k := _campaign()
	return k != null and bool(k.get(&"enabled")) and StringName(str(k.get(&"state"))) != &"done"


## True while the fallback "QUANTUM CORES 0 / 6  NEAREST 197 M" line must stay off: inside a building or in a car
## (director review 4, #4: the same goal said three ways, on top of the radio box and a toast).
func cores_line_hidden() -> bool:
	if InteriorGameplay.active:
		return true
	return is_instance_valid(Game.player) and Game.player.get(&"vehicle") != null


## Free roam under the Mission Board: one quiet line that says where the next mission is (the map's MISSIONS button). Returns the new bottom of the stack.
func _draw_free_roam(c: Control, vp: Vector2, s: float, font: Font, y: float) -> float:
	var b := (Game.missions as Missions).board
	if b == null or b.is_running() or b.first_pending or Game.state != &"play" or InteriorGameplay.active:
		return y
	var text := FREE_ROAM_LINE
	var size := int(UiUtil.BAR_LABEL * s)
	var r := _plate_text(c, font, vp.x * 0.5, y, text, size, Color(UiUtil.CYAN.lerp(Color.WHITE, 0.45), 0.95), s, Color(UiUtil.CYAN, 0.5), 220.0 * s)
	return r.end.y


const FREE_ROAM_LINE := "FREE ROAM   MAP > MISSIONS"


func _draw_priority(c: Control, vp: Vector2, s: float, font: Font, y: float) -> float:
	var k := _contracts()
	var camp := _camp_text != "" and _campaign() != null
	if camp:
		k = _campaign()                                    # a scripted step takes the plate; its progress bar and boss bar use the same calls as a contract's
	var contract := camp or (_contract_text != "" and k != null)
	if not contract and (campaign_owns_goal() or cores_line_hidden()):
		return y                                           # the story is running: no leftover "QUANTUM CORES 0 / 6" line next to it (director review)
	var board_mode := Game.missions is Missions and (Game.missions as Missions).board_mode
	if not contract and board_mode:                        # the Mission Board owns the goals: no core counter, ever; a free-roaming hero gets one short pointer to the board
		return _draw_free_roam(c, vp, s, font, y)
	var text := _camp_text if camp else (_contract_text if contract else _obj_text)
	if camp and MissionGuide.hud_on and _has_waypoint():
		text = strip_distance(text)                        # the distance lives on the beacon marker: the same sentence and number three times was a pile (director review 3, #6)
	var col := Color(UiUtil.CYAN.lerp(Color.WHITE, 0.45), 1.0) if camp else (Color(UiUtil.AMBER.lerp(Color.WHITE, 0.35), 1.0) if contract else Color(UiUtil.MAGENTA.lerp(Color.WHITE, 0.45), 1.0))
	var accent := Color(UiUtil.CYAN, 0.8) if camp else (Color(UiUtil.AMBER, 0.7) if contract else Color(UiUtil.MAGENTA, 0.6))
	var size := int(UiUtil.TEXT_MIN * s)
	while size > int(16.0 * s) and _text_width(font, text, size) + 36.0 * s > vp.x * 0.5 - 20.0 * s:     # a long line shrinks instead of growing under the side plates
		size -= 1
	var r := _plate_text(c, font, vp.x * 0.5, y, text, size, col, s, accent, 260.0 * s)
	var end := r.end.y
	if camp and skip_available():
		var sr := _plate_text(c, font, vp.x * 0.5, end + 6.0 * s, ("SKIP STEP   K" if step_skip_offered() else "SKIP SET PIECE   K"), int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), s, Color(UiUtil.AMBER, 0.6), 160.0 * s)
		end = sr.end.y
	if k == null:
		return end
	if contract:
		var pf := float(k.call(&"progress_fraction"))
		if pf >= 0.0:
			var bar := Rect2(r.position.x, r.end.y, r.size.x, 5.0 * s)
			_rect(c, bar, Color(0.0, 0.03, 0.05, 0.7))
			_rect(c, Rect2(bar.position, Vector2(bar.size.x * clampf(pf, 0.0, 1.0), bar.size.y)), Color(UiUtil.CYAN if camp else UiUtil.AMBER, 0.95))
			end = maxf(end, bar.end.y)                         # (the SKIP plate above may hang lower than the thin bar)
	var boss: Dictionary = k.call(&"boss")
	if boss.is_empty() and Game.missions is Missions and (Game.missions as Missions).arena != null:
		boss = (Game.missions as Missions).arena.boss()           # the boss rush / arena boss bar
	if not boss.is_empty():
		var named := not boss_name_shown(text, str(boss["name"]))       # the priority line above already names the boss: the bar carries no second copy
		var bp := boss_plate(vp, s, font, end, str(boss["name"]), named)
		if named:
			_text(c, font, Vector2((bp["name_rect"] as Rect2).position.x, bp["baseline"]), str(boss["name"]), HORIZONTAL_ALIGNMENT_CENTER, (bp["name_rect"] as Rect2).size.x, bp["size"], Color(UiUtil.RED, 0.97), 1.0 * s)
		var br: Rect2 = bp["bar"]
		_rect(c, br.grow(2.0 * s), Color(0.0, 0.03, 0.05, 0.7))
		_rect(c, Rect2(br.position, Vector2(br.size.x * float(boss["frac"]), br.size.y)), Color(UiUtil.RED, 0.95))
		_frame(c, br, Color(UiUtil.RED, 0.8), 1.0 * s)
		end = br.end.y + 4.0 * s
		var hint := str(boss.get("hint", ""))
		if hint != "":
			var now := hint == "SHOOT IT NOW"
			var hr := _plate_text(c, font, vp.x * 0.5, end, hint, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN if not now else UiUtil.AMBER, 1.0).lerp(Color.WHITE, 0.35), s, Color(UiUtil.AMBER if now else UiUtil.CYAN, 0.7), 150.0 * s)
			end = hr.end.y
	return end


## "1/3  CROSS THE FLOOR  131 M" -> "1/3  CROSS THE FLOOR": the trailing distance is dropped (a clock or a percentage in the line stays).
static func strip_distance(line: String) -> String:
	var re := RegEx.new()
	re.compile("\\s+\\d+ M$")
	return re.sub(line, "").strip_edges()


## True while the campaign step has a goal point (the compass and the beacon marker show it).
func _has_waypoint() -> bool:
	var k := _campaign()
	if k == null:
		return false
	var w: Dictionary = k.call(&"waypoint")
	if w.is_empty() and k.get(&"guide") != null:
		w = (k.get(&"guide") as MissionGuide).waypoint()
	return not w.is_empty()


## True when the priority line `line` already carries the boss's name (without its "PHASE n / 3" tail): the bar then shows no second name.
static func boss_name_shown(line: String, bname: String) -> bool:
	var base := bname.split("  PHASE")[0].strip_edges()
	return base != "" and Tr.t(line).contains(Tr.t(base))


## Geometry of the boss plate hung under the priority line at `end`: the name (text box, baseline, font size; the whole name and phase, centred over the bar, may be wider than the bar,
## never clipped) and the bar. The bar starts below the descenders of the name (the name used to touch it).
func boss_plate(vp: Vector2, s: float, font: Font, end: float, bname: String, named := true) -> Dictionary:
	var bw := 320.0 * s
	var by := end + 6.0 * s
	var bsz := UiUtil.fit_size(font, Tr.t(bname), bw + 120.0 * s, int(UiUtil.BAR_LABEL * s))
	var baseline := by + 20.0 * s
	var text_w := minf(font.get_string_size(Tr.t(bname), HORIZONTAL_ALIGNMENT_LEFT, -1.0, bsz).x, bw + 120.0 * s)
	var name_rect := Rect2(vp.x * 0.5 - (bw + 120.0 * s) * 0.5, baseline - font.get_ascent(bsz), bw + 120.0 * s, font.get_ascent(bsz) + font.get_descent(bsz))
	var bar := Rect2(vp.x * 0.5 - bw * 0.5, by + (34.0 if named else 4.0) * s, bw, 10.0 * s)       # 14 px under the name baseline: clear of the descenders
	return {"name_rect": name_rect, "text_w": text_w, "baseline": baseline, "size": bsz, "bar": bar}


## The compass strip under the objective: a thin line with ticks every 15 degrees, N / E / S / W, and a diamond where the goal lies (pinned to an end with an arrow when it is more than 90
## degrees off), with the distance. Returns the new bottom of the stack. Drawn only while a step has a goal.
func _draw_compass(c: Control, vp: Vector2, s: float, font: Font, y: float) -> float:
	var k := _campaign()
	if k == null or not is_instance_valid(Game.camera) or not is_instance_valid(Game.player):
		return y - 2.0 * s
	var w: Dictionary = k.call(&"waypoint")
	if w.is_empty() and k.get(&"guide") != null:
		w = (k.get(&"guide") as MissionGuide).waypoint()
	if w.is_empty():
		return y - 2.0 * s
	var from: Vector3 = Game.player.global_position
	var yaw := Game.camera.global_rotation.y
	var width := minf(340.0 * s, vp.x * 0.34)
	var x0 := vp.x * 0.5 - width * 0.5
	var half := PI * 0.5
	var base := y + 18.0 * s
	_rect(c, Rect2(x0 - 14.0 * s, y, width + 28.0 * s, 38.0 * s), Color(UiUtil.PLATE, 0.8))       # a plate behind it: shop signs must not eat the ticks
	_rect(c, Rect2(x0, base, width, 1.5 * s), Color(1, 1, 1, 0.45))
	for i in range(-6, 7):
		var a := float(i) * PI / 12.0                                        # 15 degree ticks over the +-90 degree window
		var tx := x0 + width * (0.5 + a / (2.0 * half))
		_rect(c, Rect2(tx - 1.0 * s, base - (8.0 if i % 3 == 0 else 5.0) * s, 2.0 * s, (8.0 if i % 3 == 0 else 5.0) * s), Color(1, 1, 1, 0.75))
	var letters := {"N": Vector3(0, 0, -1), "E": Vector3(1, 0, 0), "S": Vector3(0, 0, 1), "W": Vector3(-1, 0, 0)}
	var lsize := int(UiUtil.BAR_LABEL * s)
	for l: String in letters:
		var b := MissionGuide.compass_bearing(Vector3.ZERO, letters[l], yaw)
		if absf(b) < half:
			_text(c, font, Vector2(x0 + width * (0.5 + b / (2.0 * half)) - 10.0 * s, base - 9.0 * s), l, HORIZONTAL_ALIGNMENT_CENTER, 20.0 * s, lsize, Color(1, 1, 1, 0.95 if l == "N" else 0.7))
	var gb := MissionGuide.compass_bearing(from, w["pos"], yaw)
	var col: Color = w["color"]
	var pinned := absf(gb) > half
	var gx := x0 + width * (0.5 + clampf(gb, -half, half) / (2.0 * half))
	var hs := 8.0 * s
	var pulse := 0.8 + 0.2 * sin(_t * 5.0)
	_sprite(c, &"diamond", Rect2(Vector2(gx - hs, base - hs * 2.2), Vector2(hs, hs) * 2.0), Color(col, pulse))
	var dist := Vector2(w["pos"].x - from.x, w["pos"].z - from.z).length()
	var label := ("<  " if pinned and gb < 0.0 else "") + "%d M" % roundi(dist) + ("  >" if pinned and gb > 0.0 else "") if pinned else ""        # in the window the beacon marker has the number
	_text(c, font, Vector2(gx - 50.0 * s, base + 15.0 * s), label, HORIZONTAL_ALIGNMENT_CENTER, 100.0 * s, int(UiUtil.BAR_LABEL * s), Color(col.lerp(Color.WHITE, 0.5), 1.0), 1.0 * s)
	return base + 18.0 * s


## The scripted step's waypoint on the screen: a diamond over the goal with its distance, pinned to the edge of the safe area (pointing the way) when the goal is off screen or behind.
func _draw_waypoint(c: Control, vp: Vector2, s: float, font: Font, ins: Vector2, insv: Vector2) -> void:
	var k := _campaign()
	if k == null or not is_instance_valid(Game.camera):
		return
	var w: Dictionary = k.call(&"waypoint")
	if w.is_empty() and k.get(&"guide") != null:
		w = (k.get(&"guide") as MissionGuide).waypoint()               # armed: the next goal, or the exit of the building the player is in
	if w.is_empty():
		return
	var cam := Game.camera
	var head: Vector3 = (w["pos"] as Vector3) + Vector3(0.0, 5.0, 0.0)
	var col: Color = w["color"]
	var box := Rect2(Vector2(ins.x + 44.0 * s, UiUtil.stack_bottom * s + 36.0 * s), Vector2.ZERO)
	box.end = Vector2(vp.x - ins.y - 44.0 * s, vp.y - insv.y - 230.0 * s)
	if box.size.x < 40.0 * s or box.size.y < 40.0 * s:
		return
	var sp := cam.unproject_position(head)
	var behind := cam.is_position_behind(head)
	var pt := sp
	var edge_dir := 0.0
	if behind or not box.has_point(sp):
		var cc := box.get_center()
		var dir := sp - cc
		if behind:
			dir = -dir
		if dir.length() < 1.0:
			dir = Vector2(0.0, -1.0)
		var half := box.size * 0.5
		pt = cc + dir * minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		if behind:                                          # a goal behind the camera sits on the side edge it is turning toward, at mid height (it used to hang at the bottom, at the hero's feet, pointing nowhere)
			var bear := MissionGuide.compass_bearing(Game.player.global_position, w["pos"], cam.global_rotation.y) if is_instance_valid(Game.player) else 1.0
			pt = Vector2(box.position.x if bear < 0.0 else minf(box.end.x, vp.x - ins.y - 640.0 * s), cc.y)       # (the right side stops short of the button cluster)
			edge_dir = -1.0 if bear < 0.0 else 1.0
	var pulse := 0.8 + 0.2 * sin(_t * 5.0)
	var hs := 13.0 * s
	_sprite(c, &"diamond", Rect2(pt - Vector2(hs, hs), Vector2(hs, hs) * 2.0), Color(col, pulse))
	_sprite(c, &"ring", Rect2(pt - Vector2(hs, hs) * 1.6, Vector2(hs, hs) * 3.2), Color(col, 0.6 * pulse))
	if edge_dir != 0.0:
		_text(c, font, Vector2(pt.x + edge_dir * 30.0 * s - 20.0 * s, pt.y + hs * 0.6), "<" if edge_dir < 0.0 else ">", HORIZONTAL_ALIGNMENT_CENTER, 40.0 * s, int(UiUtil.BAR_LABEL * 1.3 * s), Color(col.lerp(Color.WHITE, 0.4), pulse), 1.5 * s)
	if MissionGuide.hud_on and is_instance_valid(Game.player) and absf(MissionGuide.compass_bearing(Game.player.global_position, w["pos"], cam.global_rotation.y)) > PI * 0.5:
		return                                              # the compass strip is pinned to its end and already says "< 130 M": the same number twice was a pile (director review 4, #4)
	_text(c, font, Vector2(pt.x - 60.0 * s, pt.y + hs * 2.6), "%d M" % roundi(Vector2(float(w["pos"].x) - Game.player.global_position.x, float(w["pos"].z) - Game.player.global_position.z).length() if is_instance_valid(Game.player) else float(k.call(&"distance_to_goal"))), HORIZONTAL_ALIGNMENT_CENTER, 120.0 * s, int(UiUtil.BAR_LABEL * s), Color(1, 1, 1, 0.95), 1.5 * s)


## First-use hint: an icon glyph and a short label on a small plate low in the middle (only while the tutorial is not showing).
func _draw_first_use(c: Control, vp: Vector2, s: float, font: Font) -> void:
	var st: Object = Game.story
	var fu: Object = st.get(&"first_use") if st != null else null
	if fu == null or fu.get(&"cur") < 0:
		return
	var t: Object = tutorial()
	if t != null and t.get(&"active") == true:
		return
	var text := str(fu.call(&"label"))
	var d: Dictionary = fu.call(&"current")
	var size := int(22.0 * s)
	var w := minf(_text_width(font, text, size) + 84.0 * s, vp.x - 120.0 * s)
	var h := 52.0 * s
	var r := Rect2((vp.x - w) * 0.5, vp.y - UiUtil.insets_v(vp).y - 218.0 * s, w, h)
	_plate(c, r, s, Color(UiUtil.CYAN, 0.7))
	var isz := 30.0 * s
	_sprite(c, d["icon"], Rect2(r.position.x + 12.0 * s, r.position.y + (h - isz) * 0.5, isz, isz), d["col"])
	_text(c, font, Vector2(r.position.x + 48.0 * s, r.position.y + h - 16.0 * s), text, HORIZONTAL_ALIGNMENT_CENTER, w - 52.0 * s, size, Color(1, 1, 1, 0.98), 1.5 * s)


## The training prompt: a plate low in the middle (between the stick and the buttons on phones) with a SKIP plate beside it.
func _draw_tutorial(c: Control, vp: Vector2, s: float, font: Font) -> void:
	var t: Object = tutorial()
	if t == null or t.get(&"active") != true:
		if t != null:
			t.set(&"skip_rect", Rect2())
		return
	var text := str(t.call(&"prompt"))
	if text == "":
		return
	var ins := UiUtil.insets(vp)
	var left := ins.x + 200.0 * s
	var right := vp.x - ins.y - 200.0 * s
	if touch_ui_on():
		right = minf(right, vp.x - ins.y - StoryView.TOUCH_BUTTONS_W * s)
	right = maxf(right, left + 340.0 * s)
	var skip_w := 96.0 * s
	var avail := right - left - skip_w - 12.0 * s
	var size := int(24.0 * s)
	while size > int(16.0 * s) and _text_width(font, text, size) + 32.0 * s > avail:
		size -= 1
	var w := minf(_text_width(font, text, size) + 32.0 * s, avail)
	var total := w + 12.0 * s + skip_w
	var x0 := (left + right) * 0.5 - total * 0.5
	var y0 := vp.y - UiUtil.insets_v(vp).y - 218.0 * s
	var h := 62.0 * s
	var main := Rect2(x0, y0, w, h)
	_plate(c, main, s, Color(UiUtil.AMBER, 0.8))
	_text(c, font, Vector2(main.position.x, y0 + 20.0 * s), str(t.call(&"counter_text")), HORIZONTAL_ALIGNMENT_CENTER, w, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)
	_text(c, font, Vector2(main.position.x, y0 + h - 12.0 * s), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(1, 1, 1, 0.98), 1.5 * s)
	var skip := Rect2(main.end.x + 12.0 * s, y0, skip_w, h)
	_plate(c, skip, s, Color(UiUtil.CYAN, 0.6))
	_text(c, font, Vector2(skip.position.x, y0 + h * 0.5 + 8.0 * s), str(t.call(&"skip_hint")), HORIZONTAL_ALIGNMENT_CENTER, skip.size.x, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.97), 1.0 * s)
	t.set(&"skip_rect", skip)
