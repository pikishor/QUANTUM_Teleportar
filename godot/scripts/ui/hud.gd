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
## Base-px baseline of the centre message: below the top stack and the radio subtitle lane, above the crosshair.
const MSG_Y := 262.0
const MINIMAP := 148.0              ## base px: the round minimap, top left
const BAR_W := 190.0                ## base px of an integrity / coherence / hull bar
const LABEL_W := 92.0               ## base px: the least width of the caption column left of the bars (it grows to fit the widest caption in the font in use)
const VALUE_W := 54.0
## Volume sliders of the settings rows: slider id -> the buses it sets (saved in settings.volumes). SFX also carries the ambience beds and the radio voice.
const SLIDERS := {&"vol_music": ["Music"], &"vol_sfx": ["SFX", "Ambient", "Voice"]}
const CONTROLS_DESKTOP := "WASD MOVE    MOUSE LOOK    LMB FIRE    RMB AIM    SHIFT SPRINT    SPACE JUMP    R RELOAD    Q QUANTUM TELEPORT    E ENTANGLE    G SUPERPOSE    F USE    ESC PAUSE"
const CONTROLS_TOUCH := "LEFT THUMB MOVE (PUSH FAR TO SPRINT)    RIGHT THUMB LOOK    HOLD FIRE TO SHOOT AND AIM AT ONCE"

@export var settings_path := UiSettings.DEFAULT_PATH
var settings: UiSettings
var minimap: Minimap
var touch: TouchControls
## Active screen buttons: {id: StringName, rect: Rect2, label: String, on: bool}. Rebuilt whenever the state or the viewport changes.
var buttons: Array[Dictionary] = []
var screen_age := 0.0               ## seconds since the current state began
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
var _look_open := false             ## G2: the pause shop shows the hero suit / colour screen (scripts/ui/look_screen.gd)
var _loadout_open := false          ## the pause screen shows the weapon wheel and attachment loadout
var _loadout_page := 0             ## 0 weapons and attachments, 1 GEAR (throwables, gadget, saved loadouts: scripts/ui/gear_screen.gd)
var _loadout_quick := false         ## opened from the wheel gesture: a pick resumes the game
var _loadout_w: StringName = &"carbine"  ## the weapon whose slots the loadout shows
var _ach_open := false             ## the pause screen shows the achievements (scripts/ui/achievements_screen.gd)
var _ach_page := 0
var _shop_open := false             ## the pause screen shows the upgrade shop instead of the settings
var _options_open := false          ## the title / pause screen shows the options (scripts/ui/options_screen.gd)
var _side_open := false             ## the pause shop shows the side-mission board (scripts/ui/side_board.gd)
var _chapters_open := false         ## the title / pause screen shows the chapter select (scripts/ui/chapter_select.gd)
var _camp_text := ""                ## the scripted campaign step's HUD line (CampaignRunner.hud_line), "" when none runs
var _has_save := false              ## a save file exists (the title offers CONTINUE)
var _hint_text := ""
var _text_t := 0.0
var _ammo_key := -1
var _ammo_text := ""
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
var _frames: Array = []
var _sprites: Array = []


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings = UiSettings.new(settings_path)
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
		Game.set_quality(settings.quality)


# ---------------------------------------------------------------------------------------------------------------------
# state, pause, best score, mouse
# ---------------------------------------------------------------------------------------------------------------------

func _on_state(s: StringName) -> void:
	screen_age = 0.0
	_hover = &""
	_shop_open = false
	_ach_open = false
	_side_open = false
	_loadout_open = false
	_loadout_page = 0
	_look_open = false
	_loadout_quick = false
	_chapters_open = false
	_options_open = false
	if s == &"menu":
		_has_save = Game.progress != null and bool(Game.progress.call(&"has_save"))
	if s == &"dead" or s == &"win":
		record_best()
	_hud.visible = s != &"menu" and s != &"cutscene"        # a cutscene (scripts/cinematics) owns the whole picture
	_screen.visible = s != &"play" and s != &"cutscene" and not InteriorGameplay.vendor_open      # the vendor window is its own layer
	minimap.visible = _hud.visible
	_layout_key = ""
	_apply_mouse()


## True when the HUD and screen layers show what the state asks for (HUD hidden only in the menu, the screen layer hidden only while playing).
func layers_consistent() -> bool:
	var cine := Game.state == &"cutscene"
	return _hud.visible == (Game.state != &"menu" and not cine) and _screen.visible == (Game.state != &"play" and not cine and not InteriorGameplay.vendor_open) and minimap.visible == _hud.visible


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


func touch_ui_on() -> bool:
	return touch != null and touch.controls_on


## Desktop: the mouse is captured while playing (mouse look), released in every other state. Never under tools/tests or with the touch overlay.
func wants_mouse_capture() -> bool:
	return Game.state == &"play" and not touch_ui_on() and not Game.autostart and DisplayServer.get_name() != "headless"


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
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			if k.is_action_pressed(&"pause"):
				if Game.state == &"play" or Game.state == &"paused":
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
	if SLIDERS.has(id) or (_options_open and OptionsScreen.is_slider(id)):
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
	if sid.begins_with("look_") and sid != "look_open":
		return _press_look(sid)
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
	if sid.begins_with("side_") and SideMissions.DEFS.has(StringName(sid.substr(5))):
		var sm := (Game.missions as Missions).sides if Game.missions is Missions else null
		if Game.state != &"paused" or not _side_open or sm == null or not sm.can_start(StringName(sid.substr(5))):
			Sfx.play(&"ui_deny")
			return false
		Game.state = &"play"                                           # _on_state closes the board; the job starts in the live city
		sm.start(StringName(sid.substr(5)))
		Sfx.play(&"ui_contract_accept")
		return true
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
	if OptionsScreen.is_option(id):
		if not _options_open or OptionsScreen.is_slider(id):
			return false
		Sfx.play(&"ui_tap")
		OptionsScreen.press(settings, id)
		apply_settings(false)
		settings.save()
		_layout_key = ""
		_screen.queue_redraw()
		return true
	match id:
		&"options":
			if Game.state != &"menu" and Game.state != &"paused":
				return false
			_options_open = true
			UiSettings.s_opt_page = 0
			Sfx.play(&"ui_confirm")
		&"options_back":
			if not _options_open:
				return false
			_options_open = false
			UiSettings.s_opt_page = 0
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
		&"shop":
			if Game.state != &"paused" or Game.progress == null:
				return false
			_shop_open = true
			Sfx.play(&"ui_confirm")
		&"loadout":
			if Game.state != &"paused" or Game.progress == null or not _shop_open:
				return false
			_loadout_open = true
			_loadout_quick = false
			_loadout_w = WeaponDefs.last_used
			LoadoutScreen.reset_page()
			Sfx.play(&"ui_confirm")
		&"look_open":
			if Game.state != &"paused" or Game.progress == null or not _shop_open:
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
			if Game.state != &"paused" or Game.progress == null or not _shop_open:
				return false
			_side_open = true
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
		&"q0", &"q1", &"q2":
			Sfx.play(&"ui_tap")
			settings.quality = int(String(id).substr(1))
			Game.set_quality(settings.quality)
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
			if OptionsScreen.is_slider(slider):
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
	message_text = text
	message_left = seconds
	_msg_total = maxf(seconds, 0.1)


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
	return k != null and bool(k.call(&"skip_set_piece"))


func skip_available() -> bool:
	var k := _campaign()
	return k != null and bool(k.call(&"in_optional_set_piece"))


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
		return key + InteriorGameplay.prompt
	if Game.player.get("vehicle") != null:
		return key + "EXIT VEHICLE"
	if Game.vehicles.has_method(&"nearest") and Game.vehicles.call(&"nearest", Game.player.global_position, REACH) != null:
		return key + "ENTER VEHICLE"
	return ""


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
	message_left = maxf(message_left - delta, 0.0)
	_text_t -= delta
	if _text_t <= 0.0:
		_text_t = 0.2
		_obj_text = objective_text()
		_shard_text = ("SHARDS  %d / %d" % [(Game.progress as Progress).collectibles.count() if Game.progress.get("collectibles") != null else 0, Collectibles.COUNT]) if Game.progress != null else ""
		_cred_text = "CREDITS  %d" % (int(Game.progress.get(&"credits")) if Game.progress != null else Game.score)
		_contract_text = _contract_line()
		_camp_text = _campaign_line()
		_hint_text = hint_text()
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
	_q.append([c, font, pos, tt, align, width, Tr.scaled_size(font, tt, width, size), col, shadow])


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
	_q.clear()


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


func _draw_hud(_ignored: Control = null) -> void:
	_draw_hud_body()
	_flush_text()


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
	# top centre, one compact stack: the bars on a plate, then ONE priority line (the active / offered contract, else the core objective) and its extras.
	var top := insv.x + 6.0 * s
	var stack_end := top
	if p != null:
		var bw := BAR_W * s
		_caption_width(font, s)
		var total := (_lw + 8.0 + VALUE_W + 8.0) * s + bw
		var bx := vp.x * 0.5 - total * 0.5 + (_lw + 8.0) * s
		var hp := UiUtil.num(p, &"hp", 100.0)
		var mhp := maxf(UiUtil.num(p, &"max_hp", 100.0), 1.0)
		var f := clampf(hp / mhp, 0.0, 1.0)
		var hp_col := Color(0.4, 1.0, 0.72, 0.95) if f > 0.35 else Color(1.0, 0.3, 0.3, 0.95)
		var has_hull := veh != null and UiUtil.num(veh, &"hp", -1.0) >= 0.0
		var rows := 3 if has_hull else 2
		var plate := Rect2(vp.x * 0.5 - total * 0.5 - 10.0 * s, top, total + 20.0 * s, (8.0 + 30.0 * (rows - 1) + 14.0 + 12.0) * s)
		_plate(c, plate, s)
		var y0 := top + 8.0 * s
		_bar(c, font, bx, y0, bw, 14.0 * s, f, hp_col, "INTEGRITY", str(ceili(hp)), s)
		var en := UiUtil.num(p, &"energy", 100.0)
		var men := maxf(UiUtil.num(p, &"max_energy", 100.0), 1.0)
		_bar(c, font, bx, y0 + 30.0 * s, bw, 14.0 * s, en / men, Color(0.35, 0.8, 1.0, 0.95), "COHERENCE", str(floori(en)), s)
		if has_hull:
			var vh := UiUtil.num(veh, &"hp", 0.0)
			_bar(c, font, bx, y0 + 60.0 * s, bw, 14.0 * s, vh / maxf(UiUtil.num(veh, &"max_hp", 100.0), 1.0), Color(1.0, 0.65, 0.25, 0.95), "HULL", str(ceili(vh)), s)
		stack_end = _draw_priority(c, vp, s, font, plate.end.y + 3.0 * s)
	if playing:
		stack_end = _draw_activity(c, vp, s, font, stack_end + 3.0 * s)
	UiUtil.stack_bottom = stack_end / s
	if playing and _camp_text != "":
		_draw_waypoint(c, vp, s, font, ins, insv)
	# top right: heat stars and credits on one plate
	_plate(c, Rect2(right - 196.0 * s, top, 204.0 * s, 84.0 * s), s)
	var heat := Game.heat
	for i in 5:
		var centre := Vector2(right - (4 - i) * 30.0 * s - 14.0 * s, top + 22.0 * s)
		var sr := Rect2(centre - Vector2(12.0, 12.0) * s, Vector2(24.0, 24.0) * s)
		_sprite(c, &"star", sr, Color(1, 1, 1, 0.16))
		var fill := clampf(heat - i, 0.0, 1.0)
		if fill > 0.0:
			var col := UiUtil.AMBER if heat < 3.0 else UiUtil.RED
			var pulse := 1.0 if heat < 3.0 else 0.8 + 0.2 * sin(_t * 8.0)
			_sprite(c, &"star", sr, Color(col, (0.35 + 0.65 * fill) * pulse))
	_text(c, font, Vector2(right - 192.0 * s, top + 72.0 * s), _cred_text + _clock_suffix(), HORIZONTAL_ALIGNMENT_RIGHT, 190.0 * s, int(UiUtil.TEXT_MIN * s), Color(1, 1, 1, 0.97), 1.5 * s)
	if _shard_text != "" and Game.state != &"menu":
		var sr := Rect2(right - 262.0 * s, top + 90.0 * s, 182.0 * s, 30.0 * s)     ## left of the weapon slot column (x = right - 76 s), inside the screen
		_plate(c, sr, s)
		_text(c, font, Vector2(sr.position.x + 4.0 * s, sr.position.y + 23.0 * s), _shard_text, HORIZONTAL_ALIGNMENT_CENTER, 174.0 * s, int(UiUtil.BAR_LABEL * s), Color(0.7, 0.55, 1.0, 0.97), 1.0 * s)
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
	_plate(c, ab, s)
	_text(c, font, Vector2(ab.position.x, ab.position.y + 50.0 * s), ammo_text(), HORIZONTAL_ALIGNMENT_CENTER, ab.size.x, int(48.0 * s), Color(1, 1, 1, 0.97) if p.get("reloading") != true else Color(UiUtil.AMBER, 0.97), 1.5 * s)
	if veh == null and weapon_text() != "":
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
		_draw_quantum_readout(c, vp, s, font)
		_draw_tutorial(c, vp, s, font)
		_draw_first_use(c, vp, s, font)
	if playing and veh == null:
		_draw_crosshair(c, p, vp, s, now)
	if playing and veh != null and radio_text() != "":
		var rt := radio_text()
		_plate_text(c, font, ab.get_center().x, ab.position.y - 42.0 * s, rt, int(UiUtil.BAR_LABEL * s), (UiUtil.CYAN if rt != "RADIO OFF" else Color(1, 1, 1, 0.6)), s)
	if playing and _hint_text != "":
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
	var box := Rect2(vp.x * 0.5 - w * 0.5, MSG_Y * s + 10.0 * s, w, 56.0 * s)
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


func _draw_message(c: Control, vp: Vector2, s: float, font: Font) -> void:
	if message_left <= 0.0 or message_text == "" or Game.state != &"play":
		return
	var fade := clampf(minf(message_left / 0.4, (_msg_total - message_left) / 0.12 + 0.3), 0.0, 1.0)
	var size := int(30.0 * s)
	var w := minf(_text_width(font, message_text, size) + 40.0 * s, vp.x - 40.0 * s)
	var r := Rect2(vp.x * 0.5 - w * 0.5, (MSG_Y - 34.0) * s, w, 46.0 * s)
	_rect(c, r, Color(UiUtil.PLATE, UiUtil.PLATE.a * fade))
	_rect(c, Rect2(r.position.x, r.end.y - 2.0 * s, r.size.x, 2.0 * s), Color(UiUtil.CYAN, 0.5 * fade))
	_text(c, font, Vector2(r.position.x, MSG_Y * s), message_text, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(1, 1, 1, 0.98 * fade), 2.0 * s)


func _draw_crosshair(c: Control, p: Node3D, vp: Vector2, s: float, now: float) -> void:
	var mid := vp * 0.5
	var spread_px := float(p.call(&"spread_in_pixels", vp.y)) if p.has_method(&"spread_in_pixels") else 0.0
	var gap := maxf(7.0 * s, spread_px)
	var col := Color(1, 1, 1, 0.9)
	var assist := p.get_node_or_null("AimAssist") as AimAssist
	if assist != null and assist.on_target:
		col = Color(1.0, 0.82, 0.3, 0.95)                               # the crosshair is over an enemy
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
		var hc := Color(1.0, 0.3, 0.25, 0.4 + 0.6 * k) if strong else Color(1, 1, 1, 0.4 + 0.6 * k)
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


# ---------------------------------------------------------------------------------------------------------------------
# screens
# ---------------------------------------------------------------------------------------------------------------------

func _ensure_layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var key := "%s|%d|%d|%d|%d|%s%s%s|%s%s%d|%s%s" % [Game.state, int(vp.x), int(vp.y), Game.quality, int(settings.quality), settings.post, settings.muted, settings.cutscenes, _shop_open, _has_save, _wallet(), _chapters_open, _chapters_ok()]
	key += "|%s" % _side_open
	key += "|a%s%d" % [_ach_open, _ach_page]
	key += "|%s%s%s%s%d%s%d" % [_look_open, str(Game.progress.hero.to_save()) if Game.progress != null and Game.progress.get("hero") != null else "", _loadout_open, _loadout_w, Attachments.owned.size(), str(Attachments.equipped).hash(), WeaponDefs.unlocked.size() * 10 + LoadoutScreen.page + ShopScreen.weapon_page * 100]
	key += "|g%d%s%s%d%d" % [_loadout_page, Gear.throwable, Gear.gadget, Gear.owned.size(), Gear.active_slot]
	key += "|%s%d" % [_options_open, int(settings.hud_scale * 100.0)]
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
			elif _chapters_open:
				ChapterSelect.layout(self, cx, s)
			elif _has_save:
				_add(&"continue", Rect2(cx - 170.0 * s, (318.0 + dy) * s, 340.0 * s, 64.0 * s), "CONTINUE", false)
				if _chapters_ok():                                    # NEW GAME and CHAPTERS share the row
					_add(&"deploy", Rect2(cx - 170.0 * s, (392.0 + dy) * s, 166.0 * s, UiUtil.TOUCH_MIN * s), "NEW GAME", false)
					_add(&"chapters", Rect2(cx + 4.0 * s, (392.0 + dy) * s, 166.0 * s, UiUtil.TOUCH_MIN * s), "CHAPTERS", false)
				else:
					_add(&"deploy", Rect2(cx - 170.0 * s, (392.0 + dy) * s, 340.0 * s, UiUtil.TOUCH_MIN * s), "NEW GAME", false)
				_settings_rows(cx, 484.0 + dy, s)
			elif _chapters_ok():                                      # no save, but chapters were unlocked on an earlier run
				_add(&"deploy", Rect2(cx - 170.0 * s, (318.0 + dy) * s, 340.0 * s, 64.0 * s), "DEPLOY", false)
				_add(&"chapters", Rect2(cx - 170.0 * s, (392.0 + dy) * s, 340.0 * s, UiUtil.TOUCH_MIN * s), "CHAPTERS", false)
				_settings_rows(cx, 484.0 + dy, s)
			else:
				_add(&"deploy", Rect2(cx - 170.0 * s, 318.0 * s, 340.0 * s, 64.0 * s), "DEPLOY", false)
				_settings_rows(cx, 430.0, s)
		&"paused":
			if _options_open:
				OptionsScreen.layout(self, settings, cx, s)
			elif _chapters_open:
				ChapterSelect.layout(self, cx, s)
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
			elif Game.progress != null:
				_add(&"resume", Rect2(cx - 170.0 * s, 232.0 * s, 340.0 * s, 64.0 * s), "RESUME", false)
				if _chapters_ok():
					_add(&"shop", Rect2(cx - 170.0 * s, 304.0 * s, 166.0 * s, UiUtil.TOUCH_MIN * s), "UPGRADES", false)
					_add(&"chapters", Rect2(cx + 4.0 * s, 304.0 * s, 166.0 * s, UiUtil.TOUCH_MIN * s), "CHAPTERS", false)
				else:
					_add(&"shop", Rect2(cx - 170.0 * s, 304.0 * s, 340.0 * s, UiUtil.TOUCH_MIN * s), "UPGRADES", false)
				_add(&"ach", Rect2(cx - 170.0 * s, 376.0 * s, 340.0 * s, UiUtil.TOUCH_MIN * s), "ACHIEVEMENTS", false)
				_settings_rows(cx, PAUSE_SETTINGS_Y, s)
				_add(&"menu", Rect2(cx - 154.0 * s, (PAUSE_SETTINGS_Y + 160.0) * s, 308.0 * s, 40.0 * s), "ABORT TO MENU", false)
			else:
				_add(&"resume", Rect2(cx - 170.0 * s, 238.0 * s, 340.0 * s, 64.0 * s), "RESUME", false)
				_settings_rows(cx, 350.0, s)
				_add(&"menu", Rect2(cx - 154.0 * s, 514.0 * s, 308.0 * s, 40.0 * s), "ABORT TO MENU", false)
		&"dead":
			_add(&"respawn", Rect2(cx - 170.0 * s, 560.0 * s, 340.0 * s, 64.0 * s), "RESPAWN", false)      # low on the screen: the middle stays free for the world
		&"win":
			_add(&"next", Rect2(cx - 170.0 * s, 560.0 * s, 340.0 * s, 64.0 * s), "NEXT SECTOR", false)
	if Game.state == &"menu" and not _options_open and not _chapters_open and Game.progress != null:
		_add(&"demo", Rect2(UiUtil.insets(vp).x + 16.0 * s, 6.0 * s, 180.0 * s, UiUtil.TOUCH_MIN * s), "DEMO", false)       # DEMO MODE: a sandbox profile with everything unlocked (scripts/demo/)
	if (Game.state == &"menu" or Game.state == &"paused") and not _options_open:
		_add(&"options", _options_btn(vp, s), "OPTIONS", false)       # last: screens index their own buttons from 0


## Vertical shift (base px) of the title block (name, rule, subtitle, tagline and the buttons under them) on the title screen: -20 when a second row of 64 px buttons (NEW GAME /
## CHAPTERS) needs the room, so the settings rows still end above the BEST line. 0 with the single DEPLOY button.
func _title_shift() -> float:
	return -20.0 if (_has_save or _chapters_ok()) else 0.0


## The OPTIONS button: top right of the title and pause screens, 64 px tall.
func _options_btn(vp: Vector2, s: float) -> Rect2:
	return Rect2(vp.x - UiUtil.insets(vp).y - 196.0 * s, 6.0 * s, 180.0 * s, UiUtil.TOUCH_MIN * s)


func _settings_rows(cx: float, y: float, s: float) -> void:
	for i in 3:
		_add(StringName("q%d" % i), Rect2(cx - 154.0 * s + i * 106.0 * s, y * s, 96.0 * s, 40.0 * s), TIER_NAMES[i], Game.quality == i)
	_add(&"post", Rect2(cx - 154.0 * s, (y + 50.0) * s, 100.0 * s, 40.0 * s), "POST " + ("ON" if settings.post else "OFF"), settings.post)
	_add(&"mute", Rect2(cx - 50.0 * s, (y + 50.0) * s, 100.0 * s, 40.0 * s), "SFX " + ("OFF" if settings.muted else "ON"), not settings.muted)
	_add(&"cine", Rect2(cx + 54.0 * s, (y + 50.0) * s, 100.0 * s, 40.0 * s), "CINE " + ("ON" if settings.cutscenes else "OFF"), settings.cutscenes)
	_add(&"vol_music", Rect2(cx - 154.0 * s, (y + 100.0) * s, 150.0 * s, 40.0 * s), "MUSIC", true)          # sliders: the rect is the track, the fill and value are drawn from settings
	_add(&"vol_sfx", Rect2(cx + 4.0 * s, (y + 100.0) * s, 150.0 * s, 40.0 * s), "SFX", true)


func _add(id: StringName, r: Rect2, label: String, on: bool) -> void:
	buttons.append({"id": id, "rect": r, "label": label, "on": on})


func _draw_screen(_ignored: Control = null) -> void:
	var c := _screen
	var vp := c.size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var cx := vp.x * 0.5
	_ensure_layout()
	_draw_screen_body(c, vp, s, font, cx)
	_flush_text()


func _draw_screen_body(c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var st := Game.state
	var ink := UiUtil.INK
	match st:
		&"menu":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(ink, 0.4))            # light: the animated city behind the title (scripts/cinematics) shows through
			c.draw_rect(Rect2(vp.x * 0.5 - 250.0 * s, 0.0, 500.0 * s, vp.y), Color(ink, 0.26))     # a darker column behind the title and buttons keeps them readable
		&"paused":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(ink, 0.45 if (_shop_open or _ach_open or _side_open or _loadout_open or _look_open or _chapters_open or _options_open) else 0.7))
		&"dead":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.0, 0.02, DEAD_DIM * clampf(screen_age / 0.6, 0.0, 1.0)))      # a light dim fading in: the world stays visible
		&"win":
			c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.06, 0.08, DEAD_DIM * clampf(screen_age / 0.6, 0.0, 1.0)))
	# thin horizontal frame lines
	var frame_col := Color(UiUtil.CYAN, 0.35)
	c.draw_line(Vector2(0.0, 74.0 * s), Vector2(vp.x, 74.0 * s), Color(frame_col, 0.12), 1.0 * s)
	c.draw_line(Vector2(0.0, vp.y - 74.0 * s), Vector2(vp.x, vp.y - 74.0 * s), Color(frame_col, 0.12), 1.0 * s)
	match st:
		&"menu" when _options_open:
			OptionsScreen.draw(self, c, vp, s, font, cx)
		&"menu" when _chapters_open:
			ChapterSelect.draw(self, c, vp, s, font, cx)
		&"menu":
			var dy := _title_shift()
			_text(c, font, Vector2(0.0, (196.0 + dy) * s), "QUANTUM TELEPORTAR", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(76.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
			c.draw_line(Vector2(cx - 240.0 * s, (222.0 + dy) * s), Vector2(cx + 240.0 * s, (222.0 + dy) * s), Color(UiUtil.MAGENTA, 0.8), 2.0 * s)
			_text(c, font, Vector2(0.0, (258.0 + dy) * s), "OBSERVER CORP INCURSION  //  SECTOR 01", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
			if is_instance_valid(Game.story) and Game.story.has_method(&"tagline"):
				_text(c, font, Vector2(0.0, (294.0 + dy) * s), str(Game.story.call(&"tagline")), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(1, 1, 1, 0.85), 1.0 * s)
			_text(c, font, Vector2(0.0, (476.0 + dy if (_has_save or _chapters_ok()) else 424.0) * s), "GRAPHICS", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(18.0 * s), Color(UiUtil.CYAN, 0.9), 1.0 * s)
			_footer(c, vp, s, font)
		&"paused":
			if _options_open:
				OptionsScreen.draw(self, c, vp, s, font, cx)
			elif _chapters_open:
				ChapterSelect.draw(self, c, vp, s, font, cx)
			elif _ach_open:
				AchievementsScreen.draw(self, c, vp, s, font, cx, _ach_page)
			elif _side_open:
				SideBoard.draw(self, c, vp, s, font, cx)
			elif _look_open:
				LookScreen.draw(self, c, vp, s, font, cx)
			elif _loadout_open and _loadout_page == 1:
				GearScreen.draw(self, c, vp, s, font, cx)
			elif _loadout_open:
				LoadoutScreen.draw(self, c, vp, s, font, cx, _loadout_w)
			elif _shop_open:
				ShopScreen.draw(self, c, vp, s, font, cx)
			else:
				_text(c, font, Vector2(0.0, 190.0 * s), "PAUSED", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(64.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
				_text(c, font, Vector2(0.0, (PAUSE_SETTINGS_Y - 6.0 if Game.progress != null else 344.0) * s), "GRAPHICS", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(18.0 * s), Color(UiUtil.CYAN, 0.9), 1.0 * s)
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
	for b: Dictionary in buttons:
		var r: Rect2 = b["rect"]
		var big := r.size.y > 50.0 * s
		var on: bool = b["on"]
		var hot: bool = _hover == b["id"]
		var tint := UiUtil.MAGENTA if (big and b["id"] != &"next" and b["id"] != &"resume") else UiUtil.CYAN
		if SLIDERS.has(b["id"]) or OptionsScreen.is_slider(b["id"]):
			var vol := volume_of(b["id"]) if SLIDERS.has(b["id"]) else OptionsScreen.fraction(settings, b["id"])
			var inset := minf(8.0, r.size.x * 0.05)
			c.draw_rect(r, Color(tint, 0.10))
			c.draw_rect(Rect2(r.position.x + inset, r.position.y + r.size.y - 12.0 * s, (r.size.x - 2.0 * inset) * vol, 6.0 * s), Color(tint, 0.85))
			c.draw_rect(Rect2(r.position.x + inset + (r.size.x - 2.0 * inset) * vol - 2.0 * s, r.position.y + r.size.y - 19.0 * s, 4.0 * s, 14.0 * s), Color(1, 1, 1, 0.95))
			c.draw_rect(r, Color(tint, 0.95 if (hot or _drag == b["id"]) else 0.5), false, 1.5 * s)
			_text(c, font, Vector2(r.position.x, r.position.y + 21.0 * s), (b["label"] if OptionsScreen.is_slider(b["id"]) else "%s  %d" % [b["label"], roundi(vol * 100.0)]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(20.0 * s), Color(1, 1, 1, 0.95))
			continue
		c.draw_rect(r, Color(tint, 0.30 if (on or hot) else 0.10))
		c.draw_rect(r, Color(tint, 0.95 if (on or hot or big) else 0.5), false, 2.0 * s if big else 1.5 * s)
		if String(b["id"]).begins_with("wheel_") and WeaponIcons.has_icon(StringName(String(b["id"]).substr(6))):      # weapon wheel: icon over the tag
			WeaponIcons.draw(c, StringName(String(b["id"]).substr(6)), Rect2(r.position.x + r.size.x * 0.1, r.position.y + 3.0 * s, r.size.x * 0.8, r.size.y * 0.5), Color(1, 1, 1, 0.95 if (on or hot) else 0.8))
			_text(c, font, Vector2(r.position.x, r.position.y + r.size.y - 9.0 * s), b["label"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(17.0 * s), Color(1, 1, 1, 0.97 if (on or hot) else 0.75))
			continue
		_text(c, font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + (10.0 if big else 7.0) * s), b["label"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int((30.0 if big else 20.0) * s), Color(1, 1, 1, 0.97 if (on or hot or big) else 0.75))


func _score_lines(c: Control, vp: Vector2, s: float, font: Font, y: float) -> void:
	var line1 := "CREDITS  %d" % Game.score if Game.progress == null else "SCORE  %d      CREDITS  %d" % [Game.score, _wallet()]
	_text(c, font, Vector2(0.0, y * s), line1, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(30.0 * s), Color(1, 1, 1, 0.95), 1.5 * s)
	var line := "NEW BEST" if new_best else "BEST  %d" % settings.best
	_text(c, font, Vector2(0.0, (y + 36.0) * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(20.0 * s), Color(UiUtil.AMBER, 0.95))


func _footer(c: Control, vp: Vector2, s: float, font: Font) -> void:
	var line := CONTROLS_TOUCH if touch_ui_on() else CONTROLS_DESKTOP
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
	if InteriorGameplay.hud_line != "":
		return ""                                          # an interior mission's own line owns the plate inside
	var k := _campaign()
	return str(k.call(&"hud_line")) if k != null else ""


## True when the title / pause screen has chapters to choose from (Progress.can_select_chapter).
func _chapters_ok() -> bool:
	return Game.progress != null and Game.progress.has_method(&"can_select_chapter") and bool(Game.progress.call(&"can_select_chapter"))


## The contract line ("HACK NODE  62%  1:20") or "" when none is offered or running.
func _contract_line() -> String:
	if InteriorGameplay.hud_line != "":                     # an interior mission replaces the contract line while you are inside
		return InteriorGameplay.hud_line
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


func _draw_priority(c: Control, vp: Vector2, s: float, font: Font, y: float) -> float:
	var k := _contracts()
	var camp := _camp_text != "" and _campaign() != null
	if camp:
		k = _campaign()                                    # a scripted step takes the plate; its progress bar and boss bar use the same calls as a contract's
	var contract := camp or (_contract_text != "" and k != null)
	var text := _camp_text if camp else (_contract_text if contract else _obj_text)
	var col := Color(UiUtil.CYAN.lerp(Color.WHITE, 0.45), 1.0) if camp else (Color(UiUtil.AMBER.lerp(Color.WHITE, 0.35), 1.0) if contract else Color(UiUtil.MAGENTA.lerp(Color.WHITE, 0.45), 1.0))
	var accent := Color(UiUtil.CYAN, 0.8) if camp else (Color(UiUtil.AMBER, 0.7) if contract else Color(UiUtil.MAGENTA, 0.6))
	var size := int(UiUtil.TEXT_MIN * s)
	while size > int(16.0 * s) and _text_width(font, text, size) + 36.0 * s > vp.x * 0.5 - 20.0 * s:     # a long line shrinks instead of growing under the side plates
		size -= 1
	var r := _plate_text(c, font, vp.x * 0.5, y, text, size, col, s, accent, 260.0 * s)
	var end := r.end.y
	if camp and skip_available():
		var sr := _plate_text(c, font, vp.x * 0.5, end + 6.0 * s, "SKIP SET PIECE   K", int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), s, Color(UiUtil.AMBER, 0.6), 160.0 * s)
		end = sr.end.y
	if k == null:
		return end
	if contract:
		var pf := float(k.call(&"progress_fraction"))
		if pf >= 0.0:
			var bar := Rect2(r.position.x, r.end.y, r.size.x, 5.0 * s)
			_rect(c, bar, Color(0.0, 0.03, 0.05, 0.7))
			_rect(c, Rect2(bar.position, Vector2(bar.size.x * clampf(pf, 0.0, 1.0), bar.size.y)), Color(UiUtil.CYAN if camp else UiUtil.AMBER, 0.95))
			end = bar.end.y
	var boss: Dictionary = k.call(&"boss")
	if not boss.is_empty():
		var bw := 320.0 * s
		var by := end + 6.0 * s
		var br := Rect2(vp.x * 0.5 - bw * 0.5, by + 20.0 * s, bw, 10.0 * s)
		_text(c, font, Vector2(br.position.x, by + 16.0 * s), str(boss["name"]), HORIZONTAL_ALIGNMENT_CENTER, bw, int(UiUtil.BAR_LABEL * s), Color(UiUtil.RED, 0.97), 1.0 * s)
		_rect(c, br.grow(2.0 * s), Color(0.0, 0.03, 0.05, 0.7))
		_rect(c, Rect2(br.position, Vector2(bw * float(boss["frac"]), br.size.y)), Color(UiUtil.RED, 0.95))
		_frame(c, br, Color(UiUtil.RED, 0.8), 1.0 * s)
		end = br.end.y + 4.0 * s
	return end


## The scripted step's waypoint on the screen: a diamond over the goal with its distance, pinned to the edge of the safe area (pointing the way) when the goal is off screen or behind.
func _draw_waypoint(c: Control, vp: Vector2, s: float, font: Font, ins: Vector2, insv: Vector2) -> void:
	var k := _campaign()
	if k == null or not is_instance_valid(Game.camera):
		return
	var w: Dictionary = k.call(&"waypoint")
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
	if behind or not box.has_point(sp):
		var cc := box.get_center()
		var dir := sp - cc
		if behind:
			dir = -dir
		if dir.length() < 1.0:
			dir = Vector2(0.0, -1.0)
		var half := box.size * 0.5
		pt = cc + dir * minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var pulse := 0.8 + 0.2 * sin(_t * 5.0)
	var hs := 13.0 * s
	_sprite(c, &"diamond", Rect2(pt - Vector2(hs, hs), Vector2(hs, hs) * 2.0), Color(col, pulse))
	_sprite(c, &"ring", Rect2(pt - Vector2(hs, hs) * 1.6, Vector2(hs, hs) * 3.2), Color(col, 0.6 * pulse))
	_text(c, font, Vector2(pt.x - 60.0 * s, pt.y + hs * 2.6), "%d M" % roundi(float(k.call(&"distance_to_goal"))), HORIZONTAL_ALIGNMENT_CENTER, 120.0 * s, int(UiUtil.BAR_LABEL * s), Color(1, 1, 1, 0.95), 1.5 * s)


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
