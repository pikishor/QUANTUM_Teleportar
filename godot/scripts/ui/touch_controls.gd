class_name TouchControls
extends CanvasLayer
## On-screen controls for phones (shown on touchscreens, or with --touch): a floating move stick (full push = sprint), a look drag (also from the FIRE
## finger), buttons FIRE / AIM / JUMP / RELOAD, the quantum powers BLINK / LINK / SUPER and USE (each only when its module exists), a pause button and a
## perf readout (FPS, draws, tris, texture memory; tap it to cycle the graphics tier). It only presses the input actions the keyboard drives and calls
## CameraRig.add_look, so the Player needs no changes. The HUD (scripts/ui/hud.gd) owns everything else on screen and instances this node as a child.

signal pause_requested
signal wheel_requested              ## kept for the controller path (Hud.open_wheel); the touch WEAPON button opens its own radial wheel

const LOOK_SENS := 0.003            ## radians per canvas pixel of finger travel
const STICK_RADIUS := 100.0         ## canvas px at the 720 px base height
const STICK_DEAD := 0.12
const SPRINT_AT := 0.94             ## pushing the stick this far means sprint
const BASE_H := 720.0
const USE_REACH := 4.2              ## metres: a vehicle this close enables USE
## WAVE 118 (owner: "all controls come as options on screen like gta. It should not be cluttered but like 5 circle for driving etc."): ONE SMALL SET OF ROUND BUTTONS PER MODE.
## Every action of the mode the hero is in is a round button on screen; each mode shows only its own set. The slots (canvas px at the base height, from the bottom-right corner):
##   MAIN (150,165) the big one   UPPER (150,355)   LOW (340,110)   MID (305,270)   FAR (500,105)   OUT (465,250)   DOOR (150,500)
##   on foot      FIRE   ZIP      JUMP    SWING    -       -      ENTER / USE in reach, else BLAST    edge chips: CROUCH RELOAD ABILITY / FLY    top: PAUSE MORE WEAPON
##                (wave 119, owner "like 5 circle": exactly 5 round action buttons; AIM on the street = auto-aim (AimAssist while FIRE is held), the task's fallback; RELOAD a chip, the magazine also reloads by itself)
##                one SNAKE button for swing + zip + fly was tried on paper and dropped: the hold IS the rope (a held swing chains), so a hold cannot also be FLY, and tap-zip next to
##                tap-swing near an anchor is the wave 117 bug (SWING on the street zipped); SWING and ZIP stay two buttons, FLY = the chip or a held SWING with nothing to bite
##   snake flight FIRE   AIM      UP      BOOST    DOWN    -      LAND
##   car / boat   GAS    FIRE*    BRAKE   HANDBRAKE -      -      EXIT                          left row: HORN VIEW                  (* an armed car only)
##   tank         FIRE   2nd gun  BRAKE   -        -       -      EXIT                          left row: VIEW SHELL
##   heli / plane FIRE   ROCKET   UP      -        DOWN    -      EXIT                          left row: VIEW
##   indoors      FIRE   AIM      JUMP    USE      -       -      LEAVE
## The DOOR slot is the way out of the mode in every mode (ENTER / EXIT / LAND / LEAVE). The stick (left thumb) walks, steers and flies; a drag on the open screen looks around
## and turns a turret. MORE (top) holds only the rare extras (ALT, MELEE, THROW, GADGET, CALL CAR, RADIO, GARAGE, ally orders): nothing a mode needs is behind it.
## Fields: action, dx / dy (centre from the bottom-right corner; "side": &"left" = dx from the LEFT edge; "top": true = dy from the TOP edge), r, label, need.
const R_MAIN := 52.0                ## the least radius of a main action: 56 px across on an 844x390 phone
const R_SMALL := 41.0               ## the least radius of a secondary button: 44 px across
const PAUSE_R := 41.0
const BUTTONS := [
	{"action": &"fire", "dx": 150.0, "dy": 165.0, "r": 86.0, "fs": 32, "label": "FIRE", "need": &"fire"},
	{"action": &"fire", "dx": 150.0, "dy": 355.0, "r": 56.0, "fs": 26, "label": "FIRE", "need": &"car_fire"},       # an armed car: the big slot is the GAS pedal
	{"action": &"move_forward", "dx": 150.0, "dy": 165.0, "r": 86.0, "fs": 32, "label": "GAS", "need": &"pedals"},
	{"action": &"move_back", "dx": 340.0, "dy": 110.0, "r": 62.0, "fs": 24, "label": "BRAKE", "need": &"pedals"},      # brakes, then reverses
	{"action": &"aim", "dx": 150.0, "dy": 355.0, "r": 56.0, "label": "AIM", "need": &"aim_btn"},       # snake flight and indoors; on the street AIM is auto-aim (AimAssist while FIRE is held, wave 119: no AIM button there)
	{"action": &"aim", "dx": 150.0, "dy": 355.0, "r": 56.0, "fs": 22, "label": "ROCKET", "need": &"arms2"},       # a gunship, a jet, a tank: rockets / missiles / the second gun (VehicleWeapons.tick_alt)
	{"action": &"jump", "dx": 340.0, "dy": 110.0, "r": 62.0, "label": "JUMP", "need": &"jump"},
	{"action": &"jump", "dx": 305.0, "dy": 270.0, "r": 56.0, "fs": 20, "label": "HAND BRAKE", "need": &"handbrake"},
	{"action": &"snake", "dx": 305.0, "dy": 270.0, "r": 56.0, "fs": 26, "label": "SWING", "need": &"snake"},       # QUANTUM SNAKE (scripts/quantum/snake_traversal.gd): SWING on the street and in the air, CLIMB at a wall, LET GO on a rope, BOOST in flight
	{"action": &"snake_zip", "dx": 150.0, "dy": 355.0, "r": 52.0, "fs": 26, "label": "ZIP", "need": &"zip"},       # wave 119: the UPPER slot (AIM is a chip on the street)       # the snake zip line to what the crosshair is on: its own button (wave 117: SNAKE on the street zipped instead of swinging)
	{"action": &"fly", "dx": 62.0, "dy": 452.0, "r": 42.0, "fs": 18, "label": "FLY", "need": &"fly", "side": &"left", "chip": true},       # take off, from the ground too (wave 119: an edge chip; a held SWING with nothing to bite flies too)
	{"action": &"fly", "dx": 150.0, "dy": 500.0, "r": 52.0, "fs": 24, "label": "LAND", "need": &"land"},              # in snake flight: the way out sits in the DOOR slot
	{"action": &"crouch", "dx": 500.0, "dy": 105.0, "r": 52.0, "fs": 24, "label": "DOWN", "need": &"down"},       # snake flight, helicopter, plane: descend (the LOW slot reads UP)
	{"action": &"interact", "dx": 150.0, "dy": 500.0, "r": 52.0, "fs": 24, "label": "USE", "need": &"vehicle"},     # the DOOR slot: ENTER beside a vehicle, EXIT in one
	{"action": &"snake_blast", "dx": 150.0, "dy": 500.0, "r": 52.0, "fs": 22, "label": "BLAST", "need": &"blast"},     # wave 119: the context slot on the street when nothing is in reach: SNAKE BLAST (w119-blasts reads the action)
	{"action": &"leave_building", "dx": 150.0, "dy": 500.0, "r": 52.0, "fs": 22, "label": "LEAVE", "need": &"interior"},       # inside a building: out from anywhere (a job in progress asks to tap twice)
	{"action": &"interact", "dx": 305.0, "dy": 270.0, "r": 56.0, "fs": 24, "label": "USE", "need": &"use_in"},      # inside a building: TALK, CRACK, FREE ... at the spot that offers it
	{"action": &"swap", "dx": 268.0, "dy": 118.0, "r": 50.0, "fs": 22, "label": "WEAPON", "need": &"weapon", "top": true},
	{"action": &"more", "dx": 154.0, "dy": 118.0, "r": 41.0, "fs": 20, "label": "MORE", "need": &"more_btn", "fn": &"more", "top": true},
	{"action": &"crouch", "dx": 62.0, "dy": 352.0, "r": 42.0, "fs": 18, "label": "CROUCH", "need": &"foot_ground", "side": &"left", "chip": true},
	{"action": &"ability", "dx": 278.0, "dy": 352.0, "r": 42.0, "fs": 18, "label": "ABILITY", "need": &"quantum", "fn": &"wheel_ability", "side": &"left", "chip": true},
	{"action": &"reload", "dx": 172.0, "dy": 352.0, "r": 42.0, "fs": 18, "label": "RELOAD", "need": &"reload_chip", "side": &"left", "chip": true},       # wave 119: an edge chip (the magazine also reloads by itself when empty)
	{"action": &"horn", "dx": 62.0, "dy": 352.0, "r": 42.0, "fs": 20, "label": "HORN", "need": &"horn", "fn": &"horn", "side": &"left"},
	{"action": &"veh_view", "dx": 168.0, "dy": 352.0, "r": 42.0, "fs": 20, "label": "VIEW", "need": &"view_ground", "side": &"left"},     # driving camera: chase / far / hood
	{"action": &"veh_view", "dx": 305.0, "dy": 270.0, "r": 44.0, "fs": 20, "label": "VIEW", "need": &"view_air"},       # an aircraft: the flight instruments stand where the left row is
	{"action": &"ammo_type", "dx": 278.0, "dy": 352.0, "r": 42.0, "fs": 20, "label": "SHELL", "need": &"shell", "side": &"left"},     # a shell gun (tank, artillery): the next shell type
	{"action": &"altfire", "dx": 476.0, "dy": 222.0, "r": 41.0, "fs": 22, "label": "ALT", "need": &"more", "top": true},
	{"action": &"melee", "dx": 268.0, "dy": 222.0, "r": 46.0, "fs": 22, "label": "MELEE", "need": &"more", "top": true},
	{"action": &"throw_item", "dx": 372.0, "dy": 222.0, "r": 44.0, "fs": 20, "label": "THROW", "need": &"more", "top": true},
	{"action": &"gadget", "dx": 580.0, "dy": 250.0, "r": 44.0, "fs": 20, "label": "GADGET", "need": &"more_gadget", "top": true},
	{"action": &"ammo_type", "dx": 372.0, "dy": 322.0, "r": 44.0, "fs": 22, "label": "AMMO", "need": &"more_ammo", "top": true},          # the next ammo type of the weapon (incendiary, shock, piercing ...): only for a weapon that carries more than one
	{"action": &"garage_call", "dx": 268.0, "dy": 322.0, "r": 46.0, "fs": 20, "label": "CALL", "need": &"more_garage", "fn": &"summon", "top": true},
	{"action": &"charge_place", "dx": 476.0, "dy": 322.0, "r": 44.0, "fs": 22, "label": "C4", "need": &"more_c4", "top": true},
	{"action": &"ultimate", "dx": 588.0, "dy": 150.0, "r": 46.0, "fs": 20, "label": "ULT", "need": &"more_ult", "top": true},       # the hero's blast ultimate (BlastOps._poll_input): only once one is unlocked (skill level 5, or hero mode)
	{"action": &"detonate", "dx": 612.0, "dy": 110.0, "r": 50.0, "fs": 20, "label": "DETONATE", "need": &"detonate"},
	{"action": &"companion_hold", "dx": 380.0, "dy": 118.0, "r": 46.0, "fs": 22, "label": "HOLD", "need": &"more_companion", "fn": &"ally_hold", "top": true},
	{"action": &"companion_attack", "dx": 484.0, "dy": 118.0, "r": 46.0, "fs": 20, "label": "ATTACK", "need": &"more_companion", "fn": &"ally_attack", "top": true},
	{"action": &"grab", "dx": 620.0, "dy": 225.0, "r": 50.0, "fs": 22, "label": "GRAB", "need": &"grab"},
	{"action": &"takedown", "dx": 620.0, "dy": 345.0, "r": 50.0, "fs": 20, "label": "TAKEDOWN", "need": &"takedown"},
	{"action": &"garage_open", "dx": 372.0, "dy": 222.0, "r": 46.0, "fs": 22, "label": "GARAGE", "need": &"garage_open", "fn": &"garage", "top": true},      # driving: only while MORE is open
	{"action": &"skip_piece", "dx": 290.0, "dy": 78.0, "r": 46.0, "fs": 16, "label": "SKIP SET PIECE", "need": &"skip_piece", "fn": &"skip", "top": true, "side": &"left"},
	{"action": &"radio_next", "dx": 268.0, "dy": 222.0, "r": 46.0, "fs": 22, "label": "RADIO", "need": &"radio", "call": true, "top": true},
	{"action": &"look_back", "dx": 476.0, "dy": 222.0, "r": 46.0, "fs": 22, "label": "BACK", "need": &"drive_more", "top": true},       # held: look behind the car (MORE while driving)
]
## The modes a `need` can show in (the sets of the table above). Two buttons that share no mode are never on screen together and may share a slot.
const ALL_MODES: Array[StringName] = [&"foot", &"flight", &"interior", &"car", &"boat", &"tank", &"air"]
const ON_FOOT: Array[StringName] = [&"foot", &"flight", &"interior"]
const DRIVEN: Array[StringName] = [&"car", &"boat", &"tank", &"air"]
const NEED_MODES := {
	&"fire": [&"foot", &"flight", &"interior", &"tank", &"air"], &"car_fire": [&"car", &"boat"], &"pedals": [&"car", &"boat"], &"foot": ON_FOOT, &"aim_btn": [&"flight", &"interior"], &"reload_chip": [&"foot", &"interior"], &"blast": [&"foot"], &"arms2": [&"tank", &"air"],
	&"jump": [&"foot", &"flight", &"interior", &"tank", &"air"], &"handbrake": [&"car"], &"snake": [&"foot", &"flight"], &"zip": [&"foot"], &"fly": [&"foot"], &"land": [&"flight"],
	&"down": [&"flight", &"air"], &"vehicle": [&"foot", &"interior", &"car", &"boat", &"tank", &"air"], &"interior": [&"interior"], &"use_in": [&"interior"], &"weapon": ON_FOOT, &"quantum": ON_FOOT,
	&"foot_ground": [&"foot", &"interior"], &"horn": [&"car"], &"view_ground": [&"car", &"boat", &"tank"], &"view_air": [&"air"], &"shell": [&"tank"],
	&"more": ON_FOOT, &"more_gadget": ON_FOOT, &"more_ammo": ON_FOOT, &"more_c4": ON_FOOT, &"more_ult": ON_FOOT, &"more_companion": ON_FOOT, &"more_garage": [&"foot", &"flight"],
	&"grab": ON_FOOT, &"garage_open": DRIVEN, &"radio": DRIVEN, &"drive_more": DRIVEN,
}


## True when buttons `a` and `b` (rows of BUTTONS) can never be on screen together.
static func exclusive(a: Dictionary, b: Dictionary) -> bool:
	if (a["need"] == &"vehicle" and b["need"] in [&"interior", &"blast"]) or (b["need"] == &"vehicle" and a["need"] in [&"interior", &"blast"]):
		return true                                  # wave 119: the context slot is ENTER / USE with something in reach, SNAKE BLAST without
	if (a["need"] == &"vehicle" and b["need"] == &"interior") or (a["need"] == &"interior" and b["need"] == &"vehicle"):
		return true                                  # the DOOR slot indoors: LEAVE (leave_building) everywhere but at the door, where USE says LEAVE
	var ma: Array = NEED_MODES.get(a["need"], ALL_MODES)
	for m: StringName in NEED_MODES.get(b["need"], ALL_MODES):
		if ma.has(m):
			return false
	return true


## The ABILITY wheel: the seven quantum verbs, plain names. `ui` indexes UiUtil.ABILITIES (the four classic verbs), `verb` is a QuantumVerbs id.
const WHEEL_ABILITIES := [
	{"id": &"blink", "label": "QUANTUM TELEPORT", "ui": 0},
	{"id": &"superpose", "label": "SUPERPOSITION", "ui": 2},
	{"id": &"entangle", "label": "ENTANGLE", "ui": 1},
	{"id": &"collapse", "label": "COLLAPSE", "ui": 3},
	{"id": &"shield", "label": "PHASE SHIELD", "verb": &"shield"},
	{"id": &"slip", "label": "TIME SLIP", "verb": &"slip"},
	{"id": &"arc", "label": "ARC", "verb": &"arc"},
]
## Wave 115: four more discs on the ABILITY wheel, quick casts of the snake powers (scripts/quantum/snake_ui.gd); they work with a gun in hand.
const SNAKE_ABILITIES := [
	{"id": &"snake_pull", "label": "SNAKE PULL", "snake": true},
	{"id": &"snake_net", "label": "SNAKE NET", "snake": true},
	{"id": &"snake_shield", "label": "SNAKE SHIELD", "snake": true},
	{"id": &"snake_kind", "label": "SNAKE TYPE", "snake": true},       # wave 119 (w119-blasts): picks the species of the SNAKE BLAST button (a ring of six); the old SNAKE BOMB quick cast threw blind (no ring) at a point in the air
]
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_forward", &"move_back", &"sprint"]
const TIER_NAMES: Array[String] = ["LOW", "MED", "HIGH"]
const LONG_PRESS := 0.6             ## seconds: holding the FPS box this long toggles the error panel (a short tap cycles the graphics tier)
const GRAB_SHOW := 6.0              ## metres: an enemy or a car this close in front shows GRAB
const GRAB_SHOW_PROP := 3.5
const PULSE := 0.14                ## seconds a wheel pick holds its action
const WHEEL_HOLD := 0.4             ## seconds SWAP is held before the wheel opens (a short tap cycles the weapon)
const ERROR_ROWS := 9               ## newest error lines shown in the panel

var horns := 0                      ## times the HORN button sounded (tests)
var more_open := false              ## the collapsed secondary cluster (ALT, MELEE, THROW, CROUCH, GADGET, CALL CAR, ally orders) is shown
var wheel := RadialWheel.new()      ## the ABILITY / WEAPON radial wheel
const SCRIM := 0.62                                 ## alpha of the dark scrim behind an open wheel ...
const SCRIM_WEAPON := 0.86                          ## ... and behind the weapon wheel, whose title box cuts the objective line in half (wave 114 critic): the line is all but gone
var controls_on := false            ## the touch controls are drawn and active
var touch_capable := false          ## the device has a touchscreen (controls_on while no controller is in use)
var perf_on := false                ## the perf readout is drawn (always with the controls, or with --perf)
var errors_on := false              ## the on-device error panel is shown (long-press the FPS box)
var perf_shown := false             ## the FPS readout is on screen: hidden by default, a long-press on its corner (under the minimap) shows it, long-press again opens the report panel, once more hides both

var _canvas: Control
var _last_state: StringName = &""
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_id := -1
var _held := {}                     ## finger index -> button dictionary
var _perf_text := ""
var _copied_t := 0.0                ## seconds the COPY REPORT button shows COPIED
var _perf_t := 0.0
var _win_t := 0.0
var _win_n := 0
var _win_worst := 0.0
var _avg_fps := 0.0
var _min_fps := 0.0
var _use_near := false
var _slot_enter := false           ## w119-critic: what the outdoor context slot shows (ENTER or SNAKE BLAST), settled: see _settle_slot
var _slot_t := 0.0
static var CRITIC_OLD := OS.get_environment("W119C_OLD") == "1"     ## w119-critic fixes off (the fail-first run of tests/test_w119_critic.gd)
const SLOT_SETTLE := 0.25           ## seconds a new ENTER / BLAST choice must hold before the slot changes (traffic in reach flipped it under the thumb: an ENTER tap threw a snake)
const SLOT_BLAST_KEEP := 2.5        ## seconds after a snake throw the slot stays SNAKE BLAST (a passing car took the button between two throws)
var _use_t := 0.0
var _swap_finger := -1              ## the finger on SWAP, or -1
var _swap_held := 0.0
var _swap_from := Vector2.ZERO
var _wheel_finger := -1             ## the finger dragging a wheel open from its button, or -1
var _wheel_held := 0.0
var _wheel_from_pos := Vector2.ZERO
var _wheel_moved := false
var _pulse_action: StringName = &""   ## the action a wheel pick holds pressed for PULSE seconds
var _pulse_t := 0.0
var _grab_near := false             ## something to GRAB is in front of the hero
var _grab_t := 0.0
var _swap_pulse := 0.0              ## seconds the swap action stays pressed after a tap
var _perf_finger := -1              ## the finger held on the FPS box, or -1
var _perf_held := 0.0
var _hot_finger := -1               ## the finger held on the hidden readout's corner (it still drives the stick or the look, the readout only listens)
var _hot_held := 0.0
var _hot_from := Vector2.ZERO
var _was_driving := false
var _perf_long := false             ## the current press already toggled the panel (so its release does not cycle the tier)
## Wave 116 touch audit: a tap that goes down and up inside ONE rendered frame (a quick thumb at the 13 to 30 FPS the owner measured: both events arrive in the same input flush)
## pressed and released its action before any physics tick ran, so everything that polls Input.is_action_pressed (SNAKE, FLY / LAND, FIRE, the vehicle weapons) never saw it:
## the button did nothing. The release of such a tap now waits until one physics tick and one process frame have seen the action down. false = the old behaviour (tests).
static var hold_fast_taps := true
var _chip_box := StyleBoxFlat.new()
static var door_air_fix := true               ## w118 critic: false = the old door label (EXIT while flying, where it cannot work)
var _press_at := {}                 ## finger index -> [physics frame, process frame] of the press
var _late := {}                     ## action -> [physics frame, process frame]: releases that wait for the game to see the press


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	controls_on = Game.force_touch or DisplayServer.is_touchscreen_available()
	touch_capable = controls_on
	perf_on = controls_on or OS.get_cmdline_user_args().has("--perf")
	perf_shown = OS.get_cmdline_user_args().has("--perf")
	for act: StringName in [&"snake_zip", &"horn", &"snake_blast"]:           # wave 118: buttons of their own (ZIP beside SWING, HORN); no key is bound here
		if not InputMap.has_action(act):
			InputMap.add_action(act)
	SnakeTraversal.split_buttons = controls_on
	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.draw.connect(_draw_ui)
	Game.state_changed.connect(func(_s: StringName) -> void: release_all())
	var ms := MapScreen.new()                       # H3: tracks discovered cells even while closed; opened by a minimap tap or key M
	ms.name = "MapScreen"
	add_child(ms)
	set_process(controls_on or perf_on)


## A controller took over (true) or a finger / key came back (false): the touch overlay hides and shows itself (ControllerInput calls this).
func set_pad_mode(on: bool) -> void:
	controls_on = touch_capable and not on
	SnakeTraversal.split_buttons = controls_on            # a controller has ONE snake button again (contextual: zip at a target, else swing)
	if on:
		release_all()
	if _canvas != null:
		_canvas.queue_redraw()


## A held finger never survives losing the app (no touch-up event comes): everything is let go when the app is paused or loses focus.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()


func _exit_tree() -> void:
	release_all()
	SnakeTraversal.split_buttons = false


var _redraw_t := 0.0
var _fit_cache := {}                  ## button action -> [radius, scale, label, font size]: measuring a label is text shaping, it must not run for every button on every redraw


## The font size of a button label (fitted inside the disc), measured once per radius / scale / label.
func _label_size(b: Dictionary, font: Font, r: float, s: float) -> int:
	var label := _label_of(b)
	var e: Variant = _fit_cache.get(b["action"])
	if e != null and e[0] == r and e[1] == s and e[2] == label:
		return e[3]
	var fs := int(b.get("fs", 26))
	for word: String in (label.split(" ") if two_lines(label) else PackedStringArray([label])):
		fs = mini(fs, int(UiUtil.fit_size(font, word, r * 2.0 - 10.0 * s, int(float(fs) * s)) / s))
	_fit_cache[b["action"]] = [r, s, label, fs]
	return fs


## A label of exactly two words is drawn on two lines (HAND / BRAKE, CALL / CAR, LET / GO): each word as large as the disc allows instead of one line at half the size.
static func two_lines(label: String) -> bool:
	return label.count(" ") == 1


var _story_hidden := false


func _process(delta: float) -> void:
	if not _late.is_empty():
		_flush_late()
	if (layer > 9) != wheel.is_open:                                       # an open wheel (and its scrim) is drawn above every plate and prompt of the HUD layer (10): nothing shows over a disc
		layer = 11 if wheel.is_open else 9
	if wheel.is_open != _story_hidden:                                  # the chapter banner and the radio subtitles step aside while the wheel is up (director review 4, #4: the wheel opened under the CHAPTER 1 title)
		_story_hidden = wheel.is_open
		if is_instance_valid(Game.story) and Game.story.get(&"view") != null:
			(Game.story.get(&"view") as Control).visible = not _story_hidden
	if _swap_pulse > 0.0:
		_swap_pulse -= delta
		if _swap_pulse <= 0.0:
			Input.action_release(&"swap")
	if _swap_finger != -1:
		_swap_held += delta / maxf(Engine.time_scale, 0.05)
		if _swap_held >= WHEEL_HOLD:
			var f := _swap_finger
			_swap_finger = -1
			_open_wheel(&"weapon", f, _swap_from)
	if _wheel_finger != -1:
		_wheel_held += delta / maxf(Engine.time_scale, 0.05)
	if _pulse_t > 0.0:
		_pulse_t -= delta
		if _pulse_t <= 0.0 and _pulse_action != &"":
			Input.action_release(_pulse_action)
			_pulse_action = &""
	var drv := _driving()
	if drv != _was_driving:                          # getting in or out starts with the secondary cluster closed
		_was_driving = drv
		more_open = false
	_grab_t -= delta
	if _grab_t <= 0.0:
		_grab_t = 0.25
		_grab_near = _grab_in_front()
	if _hot_finger != -1:
		_hot_held += delta / maxf(Engine.time_scale, 0.05)
		if _hot_held >= LONG_PRESS and not perf_shown and Game.state == &"play":
			_hot_finger = -1
			show_perf(true)
	if _perf_finger != -1 and not _perf_long:
		_perf_held += delta / maxf(Engine.time_scale, 0.05)
		if _perf_held >= LONG_PRESS:
			_perf_long = true
			var menu := get_tree().get_first_node_in_group(&"test_menu") if TestMode.available() else null
			if errors_on:
				errors_on = false                        # the panel is open: this press closes it and the readout
				show_perf(false)
			elif menu != null:
				menu.call(&"open")                       # test mode: the TEST MENU (it has the error panel switch); a release build keeps the error panel
			else:
				errors_on = true
			_canvas.queue_redraw()
	_win_t += delta
	_win_n += 1
	_win_worst = maxf(_win_worst, delta)
	if _win_t >= 1.0:
		_avg_fps = _win_n / _win_t
		_min_fps = 1.0 / maxf(_win_worst, 0.0001)
		_win_t = 0.0
		_win_n = 0
		_win_worst = 0.0
	_copied_t = maxf(_copied_t - delta, 0.0)
	_perf_t -= delta
	if _perf_t <= 0.0:
		_perf_t = 0.5
		_refresh_perf()
	_use_t -= delta
	if _use_t <= 0.0:
		_use_t = 0.15
		_use_near = _vehicle_in_reach() or InteriorGameplay.prompt != "" or RideUse.prompt() != "" or ShopFronts.prompt() != ""       # w122-shops: BUY beside a shopkeeper
	_settle_slot(delta)
	_redraw_t -= delta
	if Game.state == &"play" or Game.state == &"paused" or _last_state == &"play" or _last_state == &"paused":
		if _redraw_t <= 0.0 or Game.state != _last_state:         # LOW redraws the touch layer 20 times a second, LOW+ 12; a state change always redraws
			_redraw_t = LowPlus.hud_interval()
			_canvas.queue_redraw()      # one extra redraw after leaving play, so the dead screen does not keep the dimmed buttons
	_last_state = Game.state


## w119-critic: the outdoor context slot (ENTER or SNAKE BLAST) turns to ENTER only when a car has stayed in reach SLOT_SETTLE seconds (back to BLAST at once), never under a finger on it, and stays SNAKE BLAST while
## aiming and SLOT_BLAST_KEEP seconds after a throw. A change redraws at once, so the word drawn is the action a finger gets (the old slot followed every car that came within reach).
func _settle_slot(delta: float) -> void:
	if CRITIC_OLD:
		_slot_enter = _use_near
		return
	var sbi := SnakeBlasts.instance
	var keep := is_instance_valid(sbi) and (sbi.aiming or sbi.since_throw < SLOT_BLAST_KEEP)
	var want := _use_near and not keep
	if want == _slot_enter:
		_slot_t = 0.0
		return
	_slot_t += delta
	if (_slot_t >= SLOT_SETTLE or not want) and not _action_held(&"snake_blast") and not _action_held(&"interact"):
		_slot_enter = want
		_slot_t = 0.0
		if _canvas != null:
			_canvas.queue_redraw()


## Lets go of every action this layer pressed (state changes, exit, tests).
func release_all() -> void:
	_swap_finger = -1
	for a: StringName in MOVE_ACTIONS:
		Input.action_release(a)
	for b: Dictionary in BUTTONS:
		if not b.get("call", false) and not b.has("fn"):   # call and fn buttons (RADIO) press no action, and its action only exists once a radio does
			Input.action_release(b["action"])
	if _pulse_action != &"":
		Input.action_release(_pulse_action)
		_pulse_action = &""
	wheel.close()
	_wheel_finger = -1
	_swap_pulse = 0.0
	_held.clear()
	_press_at.clear()
	_late.clear()
	_stick_id = -1
	_look_id = -1
	_perf_finger = -1
	_perf_long = false
	_hot_finger = -1


# ---------------------------------------------------------------------------------------------------------------------
# input
# ---------------------------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not controls_on and not perf_on:
		return
	if MapScreen.up and not (event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed):
		return                                                      # the open map owns the fingers (a lift still reaches touch_up so no finger stays held)
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			touch_down(t.index, t.position)
		else:
			touch_up(t.index, hold_fast_taps)                        # a real finger: a tap inside one frame is held until the game has seen it
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		touch_move(d.index, d.position, d.relative)


func touch_down(id: int, pos: Vector2) -> void:
	if not perf_visible() and perf_on and controls_on and Game.state == &"play" and _perf_box().has_point(pos):
		_hot_finger = id                                # hidden readout: a long hold here shows it (the press is NOT taken, the finger keeps playing)
		_hot_held = 0.0
		_hot_from = pos
	if controls_on and Game.is_playing() and wheel.is_open and wheel.sticky:       # a wheel a tap left open: a disc picks, anything else closes it (and is not a stick or look touch)
		var wi := wheel.hit(pos)                                        # (before the FPS box: wave 118, the ring may stand over it and a tap on a disc cycled the graphics tier)
		if wi >= 0 and _wheel_pick(wi):
			return                                                      # a class ring (WeaponWheel.ring_items) took its place: the wheel stays open
		wheel.close()
		return
	if perf_visible() and errors_on and _copy_rect().has_point(pos):
		var po := get_tree().get_first_node_in_group(&"perf_overlay")      # COPY REPORT (debug panel): the device report to the clipboard and user://perf_log.txt
		if po != null:
			_copied_t = 2.0
			(po as PerfOverlay).copy_report()
		return
	if perf_visible() and _perf_box().has_point(pos):
		_perf_finger = id                               # decided on release: a tap cycles the tier, a long press toggles the error panel
		_perf_held = 0.0
		_perf_long = false
		return
	if not controls_on or not Game.is_playing():
		return
	if pos.distance_to(_pause_center()) <= PAUSE_R * _scale() * 1.3:
		pause_requested.emit()
		return
	var mm := _minimap_rect()
	if mm.has_point(pos):                                              # H3: a tap on the minimap opens the full map
		Sfx.play(&"ui_tap")
		open_map()
		return
	for b: Dictionary in BUTTONS:
		if button_visible(b) and not wheel.is_open and pos.distance_to(_button_center(b)) <= maxf(float(b["r"]) * UiSettings.s_button_size, UiUtil.TOUCH_MIN * 0.5) * _scale() * 1.15:
			if b.get("fn", &"") == &"wheel_ability":                   # ABILITY: press opens the wheel, drag and release picks, a quick tap leaves it open
				_open_wheel(&"ability", id, pos)
				return
			if b.has("fn"):                                            # CALL CAR / GARAGE / MORE: one tap, no action press
				if b["fn"] != &"horn":
					Sfx.play(&"ui_tap")
				if b["fn"] == &"skip":
					get_parent().call(&"skip_set_piece")
				elif b["fn"] == &"more":
					more_open = not more_open
				elif b["fn"] == &"horn":
					horn()
				elif b["fn"] == &"ally_hold":
					Companion.current.command(&"hold")
				elif b["fn"] == &"ally_attack":
					Companion.current.command(&"attack")
				elif b["fn"] == &"summon":
					CallIn.toggle()                          # wave 118 (w118-armour): the CALL-IN list: CAR (garage car or hover-bike, VehicleManager.summon_any), TANK, HELICOPTER, PLANE
				else:
					_open_garage()
				return
			if b.get("call", false):                                   # RADIO: one tap = Game.vehicles.radio.cycle() (no action press, so the key path cannot double-cycle)
				Game.vehicles.radio.cycle()
				Sfx.play(&"ui_tap")
				return
			if b["action"] == &"swap":                                 # a tap cycles (on release), a hold opens the wheel
				_swap_finger = id
				_swap_held = 0.0
				_swap_from = pos
				return
			_held[id] = b
			_press_at[id] = [Engine.get_physics_frames(), Engine.get_process_frames()]
			_late.erase(b["action"])
			Input.action_press(b["action"])
			if b["action"] == &"interact":
				Sfx.play(&"ui_tap")                                    # USE (enter / exit a car) answers with a soft tap
			return
	var stick_side := pos.x > _vp_size().x * 0.58 if UiSettings.s_left_hand else pos.x < _vp_size().x * 0.42
	if stick_side and _stick_id == -1:
		_stick_id = id
		_stick_origin = pos
		_stick_pos = pos
	elif _look_id == -1:
		_look_id = id


func touch_move(id: int, pos: Vector2, rel: Vector2) -> void:
	if id == _hot_finger and pos.distance_to(_hot_from) > 48.0 * _scale():
		_hot_finger = -1                                # a stick drag or a look swipe is not a long press
	if id == _wheel_finger:
		wheel.sel = wheel.wedge(wheel.centre + (pos - _wheel_from_pos))       # the drag is read from where the thumb went down (the ring may sit beside it: see _open_wheel)
		if pos.distance_to(_wheel_from_pos) > 24.0 * _scale():
			_wheel_moved = true
		return
	if id == _stick_id:
		_stick_pos = pos
		_apply_stick()
	elif id == _look_id or (_held.has(id) and (_held[id] as Dictionary)["action"] in [&"fire", &"snake", &"snake_zip", &"fly"]):       # the camera also turns from a finger that holds FIRE or SNAKE: swing and steer with one thumb
		_look(rel)


## `keep_fast` (the real input path): a press that no physics tick has seen yet is let go one tick later (see hold_fast_taps). A direct call lets go at once.
func touch_up(id: int, keep_fast := false) -> void:
	if id == _hot_finger:
		_hot_finger = -1
	if id == _wheel_finger:
		_wheel_finger = -1
		if wheel.is_open:
			if wheel.kind == &"ability" and _wheel_held < RadialWheel.TAP_TIME and not _wheel_moved:
				wheel.sticky = true                                    # a tap: the wheel stays, the next tap picks
				wheel.sel = -1
			else:
				if wheel.sel >= 0 and _wheel_pick(wheel.sel):
					return                                              # the pick opened a class ring: it stays until a tap picks a weapon or closes it
				wheel.close()
		return
	if id == _swap_finger:
		_swap_finger = -1
		Input.action_press(&"swap")
		_swap_pulse = 0.12
		return
	if id == _perf_finger:
		_perf_finger = -1
		if not _perf_long:
			Game.set_tier_index((Game.tier_index() + 1) % 4)
			_perf_t = 0.0
		_perf_long = false
		return
	if id == _stick_id:
		_stick_id = -1
		_stick_pos = _stick_origin
		_apply_stick()
	if id == _look_id:
		_look_id = -1
	if _held.has(id):
		var act: StringName = (_held[id] as Dictionary)["action"]
		var at: Array = _press_at.get(id, [-1, -1])
		_held.erase(id)
		_press_at.erase(id)
		if keep_fast and Game.state == &"play" and (Engine.get_physics_frames() <= int(at[0]) or Engine.get_process_frames() <= int(at[1])):
			_late[act] = at                              # nothing has seen this press yet: _flush_late lets it go one tick later
		elif not _action_held(act):
			Input.action_release(act)
			if act in MOVE_ACTIONS and _stick_id != -1:
				_apply_stick()                           # a pedal was let go while the stick is pushed: the stick has the action again


## True while another finger still holds a button of the same action.
func _action_held(act: StringName) -> bool:
	for b: Dictionary in _held.values():
		if b["action"] == act:
			return true
	return false


## Lets go of the fast taps (see hold_fast_taps) once a physics tick and a process frame have run with the action down.
func _flush_late() -> void:
	for act: StringName in _late.keys():
		var at: Array = _late[act]
		if Engine.get_physics_frames() > int(at[0]) and Engine.get_process_frames() > int(at[1]):
			_late.erase(act)
			if not _action_held(act):
				Input.action_release(act)
				if act in MOVE_ACTIONS and _stick_id != -1:
					_apply_stick()


func _apply_stick() -> void:
	var radius := STICK_RADIUS * _scale()
	var raw := _stick_pos - _stick_origin
	if raw.length() > radius:                       # a floating stick: the origin follows a finger that goes past the rim
		_stick_origin += raw.normalized() * (raw.length() - radius)
		raw = _stick_pos - _stick_origin
	var v := raw / radius
	if v.length() < STICK_DEAD:
		v = Vector2.ZERO
	_press(&"move_right", maxf(v.x, 0.0))
	_press(&"move_left", maxf(-v.x, 0.0))
	_press(&"move_back", maxf(v.y, 0.0))
	_press(&"move_forward", maxf(-v.y, 0.0))
	_press(&"sprint", 1.0 if v.length() >= SPRINT_AT else 0.0)


func _press(action: StringName, strength: float) -> void:
	if _action_held(action):                          # a pedal button (GAS / BRAKE) holds this action: the stick does not let it go
		Input.action_press(action, 1.0)
	elif strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _look(rel: Vector2) -> void:
	var p: Node = Game.player
	if not is_instance_valid(p) or not Game.is_playing():
		return
	var rig: Object = p.get("camera_rig")
	if rig != null and rig.has_method("add_look"):
		var ak := lerpf(1.0, UiSettings.s_ads, clampf(float(rig.call("get_ads_amount")), 0.0, 1.0)) if rig.has_method("get_ads_amount") else 1.0
		rig.call("add_look", rel.x * LOOK_SENS * UiSettings.s_look_x * ak, rel.y * LOOK_SENS * UiSettings.s_look_y * ak)


# ---------------------------------------------------------------------------------------------------------------------
# which buttons exist
# ---------------------------------------------------------------------------------------------------------------------

## A button is shown only when what it needs exists: the quantum powers need `player.quantum`, USE needs the vehicle module and a car in reach (or being in one).
func button_visible(b: Dictionary) -> bool:
	match b["need"]:
		&"quantum":
			return is_instance_valid(Game.player) and Game.player.get("quantum") != null and not _driving()
		&"weapon":
			return is_instance_valid(Game.player) and not _driving()
		&"more":
			return more_open and is_instance_valid(Game.player) and not _driving()
		&"more_c4":
			return more_open and is_instance_valid(Game.player) and not _driving() and Charges.current != null
		&"more_ult":
			return more_open and is_instance_valid(Game.player) and not _driving() and BlastOps.ultimates_open()
		&"detonate":
			return Charges.current != null and Charges.current.armed()
		&"more_gadget":
			return more_open and is_instance_valid(Game.player) and not _driving() and Gear.gadget != &""
		&"more_ammo":
			var aw: Variant = Game.player.get("weapon") if is_instance_valid(Game.player) else null
			return more_open and not _driving() and aw is PlayerWeapon and String((aw as PlayerWeapon).def["kind"]) == "hit" and (aw as PlayerWeapon).mech.allowed_ammo().size() > 1
		&"more_garage":
			return more_open and is_instance_valid(Game.vehicles) and Game.vehicles.has_method(&"summon_any") and not _driving() and not InteriorGameplay.active
		&"more_companion":
			return more_open and not _driving() and Companion.controllable()
		&"grab":
			return is_instance_valid(Game.player) and not _driving() and ((_grab_near and not _use_near) or _grab_held())       # a car in ENTER reach shows ENTER alone: one contextual button, not two
		&"interior":         # the DOOR slot indoors: LEAVE from anywhere (at the door the USE button stands in the same slot with the same word: one button, not two)
			return InteriorGameplay.active and not InteriorGameplay.vendor_open and is_instance_valid(InteriorGameplay.instance) and not InteriorGameplay.instance.busy and not _driving() \
					and not InteriorGameplay.prompt.begins_with("LEAVE")
		&"use_in":           # indoors, at a spot that offers something (TALK, CRACK, FREE): the MID slot
			return InteriorGameplay.active and not _driving() and InteriorGameplay.prompt != "" and not InteriorGameplay.prompt.begins_with("LEAVE") and not InteriorGameplay.vendor_open
		&"vehicle":          # the DOOR slot outdoors: ENTER beside a vehicle (or a ride), EXIT in one
			if InteriorGameplay.active and not _driving():
				return is_instance_valid(Game.vehicles) and _use_near and InteriorGameplay.prompt.begins_with("LEAVE")       # indoors only at the door: LEAVE
			return is_instance_valid(Game.vehicles) and ((_slot_enter and not _flying()) or _driving())       # in snake flight the DOOR slot is LAND
		&"driving":
			return is_instance_valid(Game.vehicles) and _driving()
		&"view_ground":
			return is_instance_valid(Game.vehicles) and _driving() and not (_craft_class() in [&"heli", &"plane"])
		&"view_air":
			return is_instance_valid(Game.vehicles) and _driving() and _craft_class() in [&"heli", &"plane"]
		&"pedals":           # GAS and BRAKE: everything with wheels or a hull (a tank and the aircraft are driven by the stick alone)
			return is_instance_valid(Game.vehicles) and _driving() and not (_craft_class() in [&"heli", &"plane", &"tank"])
		&"handbrake":
			return is_instance_valid(Game.vehicles) and _driving() and not (_craft_class() in [&"heli", &"plane", &"tank", &"boat"])
		&"horn":
			return is_instance_valid(Game.vehicles) and _driving() and not (_craft_class() in [&"heli", &"plane", &"tank", &"boat"])
		&"jump":             # the LOW slot: JUMP on foot, UP in the air, BRAKE in a tank
			return not _driving() or _craft_class() in [&"heli", &"plane", &"tank"]
		&"shell":
			return _driving() and _car_armed() and BlastOps.is_shell_gun(Game.player.get("vehicle").get("kind")) and InputMap.has_action(&"ammo_type")
		&"arms2":            # the driven craft carries rockets, missiles or a second gun
			var dv: Object = Game.player.get("vehicle") if is_instance_valid(Game.player) else null
			return dv != null and dv.get("weapons") != null and bool(dv.get("weapons").call(&"has_alt")) and _craft_class() in [&"heli", &"plane", &"tank"]
		&"down":             # helicopter, plane, snake flight: the second vertical button
			return (is_instance_valid(Game.vehicles) and _driving() and _craft_class() in [&"heli", &"plane"]) or _flying()
		&"drive_more":       # the driving extras behind MORE: BACK, RADIO, GARAGE
			return more_open and is_instance_valid(Game.vehicles) and _driving()
		&"snake":
			return is_instance_valid(Game.player) and not _driving() and Game.player.get("snake") != null and (Game.player.get("snake") as SnakeTraversal).button_shown()
		&"zip":
			return is_instance_valid(Game.player) and not _driving() and not _flying() and Game.player.get("snake") != null and (Game.player.get("snake") as SnakeTraversal).button_shown()
		&"fly":              # FLY: on the ground and in the air, until the hero flies (then the DOOR slot reads LAND)
			return is_instance_valid(Game.player) and not _driving() and not _flying() and Game.player.get("snake") != null and (Game.player.get("snake") as SnakeTraversal).fly_button_shown()
		&"land":
			return _flying()
		&"fire":
			return not _driving() or (_car_armed() and _craft_class() in [&"heli", &"plane", &"tank"])
		&"car_fire":
			return _driving() and _car_armed() and not (_craft_class() in [&"heli", &"plane", &"tank"])
		&"more_btn":
			return is_instance_valid(Game.player)
		&"foot":
			return is_instance_valid(Game.player) and not _driving()
		&"aim_btn":          # the AIM circle: snake flight and indoors
			return is_instance_valid(Game.player) and not _driving() and (_flying() or InteriorGameplay.active)
		&"reload_chip":      # the RELOAD chip: on foot, not in snake flight
			return is_instance_valid(Game.player) and not _driving() and not _flying()
		&"blast":            # the context slot with nothing in reach: SNAKE BLAST
			return is_instance_valid(Game.player) and not _driving() and not _flying() and not _slot_enter and InputMap.has_action(&"snake_blast") \
					and Game.player.get("snake") != null and (Game.player.get("snake") as SnakeTraversal).button_shown()
		&"foot_ground":      # CROUCH: on foot and not in snake flight (there the same action is the DOWN button)
			return is_instance_valid(Game.player) and not _driving() and not _flying()
		&"takedown":
			var pc: Object = Game.player.get("cover") if is_instance_valid(Game.player) else null
			return pc != null and pc.get("target") != null and is_instance_valid(pc.get("target"))
		&"garage_open":      # GARAGE: while driving, behind MORE
			return more_open and is_instance_valid(Game.vehicles) and Game.vehicles.has_method(&"get_garage") and _driving()
		&"skip_piece":       # SKIP SET PIECE: only inside an optional set piece
			var hud := get_parent()
			return hud != null and hud.has_method(&"skip_available") and bool(hud.call(&"skip_available"))
		&"radio":
			return more_open and is_instance_valid(Game.vehicles) and Game.vehicles.get("radio") != null and _driving()
	return true


## The label a button shows: USE reads ENTER on foot and EXIT in a car.
func _label_of(b: Dictionary) -> String:
	if b["action"] == &"snake_blast":
		return SnakeBlasts.button_label()                          # wave 119 (w119-blasts): "FIRE 3", the species and the charges
	if b["action"] == &"interact":
		if not _driving() and InteriorGameplay.active and InteriorGameplay.prompt != "":
			return str(InteriorGameplay.prompt).split(" ")[0]         # inside a building the button says what it does: LEAVE, TALK, CRACK, FREE (not ENTER)
		if not _driving() and InteriorGameplay.active:
			return "USE"                                      # nothing to do at this spot: never ENTER (a street word) inside a room
		if not _driving() and ShopFronts.prompt() != "":
			return "BUY"                                      # w122-shops: beside the shopkeeper of a walk-in shop
		var ride := RideUse.prompt()
		if not _driving() and ride != "":
			return ride.split(" ")[0]                         # CLIMB, SIT, STAND, TAKE, MAN, LEAVE
		if door_air_fix and _driving():
			var dv := Game.player.get("vehicle") as Vehicle
			if dv != null and not VehicleCraft.can_exit(dv):
				return "LAND FIRST"                           # w118 critic: in the air the door said EXIT and a finger on it did nothing visible (243 m up)
		return "EXIT" if _driving() else "ENTER"
	if b["action"] == &"snake" and is_instance_valid(Game.player) and Game.player.get("snake") != null:
		return (Game.player.get("snake") as SnakeTraversal).button_label()
	if b["action"] == &"fly" and is_instance_valid(Game.player) and Game.player.get("snake") != null:
		var sfl := Game.player.get("snake") as SnakeTraversal
		return sfl.flight.button_label() if sfl.mode == SnakeTraversal.Mode.FLY else "FLY"       # LAND; FLY again once a landing can be called off (wave 116 critic)
	if b["action"] == &"snake_zip" and is_instance_valid(Game.player) and Game.player.get("snake") != null:
		var sz := Game.player.get("snake") as SnakeTraversal
		if sz.jam_t > 0.0:
			return "JAMMED"
		if sz.whiff_action == &"snake_zip" and SnakeFx.label_cue() != "":
			return SnakeFx.label_cue()                   # NO ANCHOR for a second after a ZIP that found nothing
	if b["action"] == &"jump" and not _driving() and is_instance_valid(Game.player) and Game.player.get("snake") != null and (Game.player.get("snake") as SnakeTraversal).mode == SnakeTraversal.Mode.FLY:
		return "UP"                                      # in snake flight the JUMP button climbs
	if b["action"] == &"jump" and _driving():
		var cc := _craft_class()
		if cc == &"heli" or cc == &"plane":
			return "UP"                                  # climb / nose up
		return "BRAKE" if cc == &"boat" or cc == &"tank" else "HAND BRAKE"
	if b["action"] == &"aim" and b.get("need", &"") == &"arms2" and is_instance_valid(Game.vehicles):           # the secondary weapon says what it is: ROCKET, MISSILE, COAX
		var dv: Object = Game.vehicles.get("driven")
		var wp: Object = dv.get("weapons") if dv != null else null
		if wp != null and wp.get("alt_def") is Dictionary:
			return String((wp.get("alt_def") as Dictionary).get("short", "ROCKET"))
	if b["action"] == &"skip_piece":
		var hud := get_parent()
		if hud != null and hud.has_method(&"step_skip_offered") and bool(hud.call(&"step_skip_offered")):
			return "SKIP STEP"
	return str(b["label"])


## True while the hero holds something (the GRAB button stays so it can be released).
func _grab_held() -> bool:
	var vb: Object = Game.player.get("verbs") if is_instance_valid(Game.player) else null
	return vb != null and vb.get("holding") == true


## Something the hero could GRAB is in front (polled 4 times a second: it scans the enemy, vehicle and prop groups).
func _grab_in_front() -> bool:
	if not controls_on or Game.state != &"play" or not is_instance_valid(Game.player) or _driving():
		return false
	var vb: Object = Game.player.get("verbs")
	if vb == null or not vb.has_method(&"find_target"):
		return false
	var t: Dictionary = vb.call(&"find_target")
	if t.is_empty():
		return false
	var d := ((t["pos"] as Vector3) - (Game.player as Node3D).global_position).length()
	return d <= (GRAB_SHOW if t["kind"] != &"prop" else GRAB_SHOW_PROP)           # a prop has to be close: the button must not sit on screen all the time


## Opens the radial wheel for `kind` while `finger` holds its button at `pos`. The wheel is laid out AROUND THE THUMB (the centre of the button that opened it) in the free
## arc that stays on the screen; every other button is hidden while it is open (scripts/ui/radial_wheel.gd, tests/test_menu_cut.gd).
func _open_wheel(kind: StringName, finger: int, pos: Vector2) -> void:
	var at := pos
	var want: StringName = &"swap" if kind == &"weapon" else &"ability"
	for b: Dictionary in BUTTONS:
		if b["action"] == want:
			at = _button_center(b)                                   # the thumb sits on its button: the wheel opens around it
	at = wheel_centre(at)
	wheel.open_at(kind, wheel_items(kind), at, _scale(), false, wheel_bounds())
	_wheel_finger = finger if wheel.is_open else -1
	_wheel_held = 0.0
	_wheel_moved = false
	_wheel_from_pos = pos
	Sfx.play(&"ui_tap")
	_canvas.queue_redraw()


## Wave 118 (wave 116 list: eleven ability discs of 38 px): a wheel opened beside a screen edge fanned out over the free arc and its discs shrank to 62 %. The ring now
## opens where the whole circle fits (the point nearest the thumb), so the discs keep their size; the drag is read from where the thumb went down. false = the old place (tests).
static var wheel_fits := true


func wheel_centre(at: Vector2) -> Vector2:
	if not wheel_fits:
		return at
	var wb := wheel_bounds().grow(-RadialWheel.RADIUS * _scale() - 1.0)
	if wb.size.x <= 0.0 or wb.size.y <= 0.0:
		return at
	return Vector2(clampf(at.x, wb.position.x, wb.end.x), clampf(at.y, wb.position.y, wb.end.y))


## Where the centre of a wheel disc may sit (canvas px): the screen less the notch insets and an 8 px margin, less one disc radius.
func wheel_bounds() -> Rect2:
	var vp := _vp_size()
	var s := _scale()
	var m := (RadialWheel.ITEM_R + RadialWheel.EDGE) * s
	var ins := _insets()
	var top := UiUtil.insets_v(vp).x
	var bot := UiUtil.insets_v(vp).y
	return Rect2(Vector2(ins.x + m, top + m), Vector2(maxf(vp.x - ins.x - ins.y - 2.0 * m, 1.0), maxf(vp.y - top - bot - 2.0 * m, 1.0)))


## The discs of a wheel: {id, label, ready, active, cd, current}.
func wheel_items(kind: StringName) -> Array:
	var out: Array = []
	var p: Node = Game.player if is_instance_valid(Game.player) else null
	if p == null:
		return out
	if kind == &"weapon":
		return WeaponWheel.items() + SnakeUi.wheel_items()                 # the weapon classes, then the SNAKE and SNAKE BOMB wedges (wave 115)
	var qv: Object = p.get("qverbs")
	for d: Dictionary in WHEEL_ABILITIES + SNAKE_ABILITIES:
		var st := {"ready": true, "active": false, "cd": 0.0}
		if d.has("ui"):
			if p.get("quantum") == null:
				continue
			st = UiUtil.ability_state(p, UiUtil.ABILITIES[int(d["ui"])])
		elif d.has("snake"):
			st = SnakeUi.ability_state(d["id"])
		else:
			if qv == null:
				continue
			st = (qv as QuantumVerbs).ui_state(d["verb"])
		out.append({"id": d["id"], "type": &"snake" if d["id"] == SnakeBlasts.KIND_ACTION else &"ability", "label": SnakeUi.ability_label(d["id"]) if d.has("snake") else d["label"], "ready": bool(st["ready"]), "active": bool(st["active"]), "cd": float(st["cd"]), "current": false})
	return out


## A wheel pick: an ability holds its action for a moment (the same press the key makes), a weapon switches at once. Returns true when a class ring took the wheel's place (it stays open).
func _wheel_pick(i: int) -> bool:
	var id := wheel.item_id(i)
	if id == &"":
		return false
	if wheel.kind == &"weapon":
		var p: Node = Game.player if is_instance_valid(Game.player) else null
		if p != null and p.get("weapon") is PlayerWeapon:
			var pw := p.get("weapon") as PlayerWeapon
			var nxt := WeaponWheel.activate(wheel.items[i], pw)
			Sfx.play(&"ui_tap")
			if not nxt.is_empty():
				wheel.open_at(&"weapon", WeaponWheel.ring_items(StringName(nxt["tab"]), int(nxt["page"]), pw.current), wheel.centre, wheel.scale, true, wheel_bounds())
				return wheel.is_open
			return false
	else:
		var sbp := SnakeBlasts.wheel_pick(self, id)                  # wave 119: SNAKE TYPE opens the ring of species, a species disc picks it
		if sbp != 0:
			return sbp == 2
		if _pulse_action != &"":
			Input.action_release(_pulse_action)
		Input.action_press(id)
		_pulse_action = id
		_pulse_t = PULSE
	Sfx.play(&"ui_tap")
	return false


## The WEAPON button face: the weapon's silhouette and "30 / 30" (reload shows RELOADING) instead of a text label.
func _weapon_face(c: Control, font: Font, centre: Vector2, r: float, s: float, labels: Array) -> void:
	var p: Node = Game.player if is_instance_valid(Game.player) else null
	if p == null or not (p.get("weapon") is PlayerWeapon):
		return
	var hud := get_parent()
	var ammo := str(hud.call(&"ammo_text")) if hud != null and hud.has_method(&"ammo_text") else ""
	if ammo == "RELOADING":
		ammo = "RELOAD"                                  # "..." said nothing (director review 3, #10)
	WeaponIcons.draw(c, SnakeUi.shown((p.get("weapon") as PlayerWeapon).current), Rect2(centre.x - r * 0.8, centre.y - r * 0.78, r * 1.6, r * 0.8), Color(UiUtil.CYAN, 0.95))
	labels.append([centre + Vector2(-r, r * 0.62), ammo, r * 2.0, 1.0, int(18.0)])


## The radial wheel: a faint disc behind, one button sprite per item (name or weapon silhouette), the picked wedge bright.
func _draw_wheel(c: Control, font: Font, s: float) -> void:
	var n := wheel.items.size()
	c.draw_rect(Rect2(Vector2.ZERO, _vp_size()), Color(0.0, 0.02, 0.04, SCRIM_WEAPON if wheel.kind == &"weapon" else SCRIM))             # a scrim: the buttons and plates under the wheel step back instead of showing through the discs (the weapon wheel's title box covers the middle of the objective line: wave 114 critic, the line is all but gone behind it)
	var ring := RadialWheel.RADIUS * s
	c.draw_arc(wheel.centre, ring, 0.0, TAU, 64, Color(UiUtil.CYAN, 0.16), 3.0 * s, false)  # the track the discs sit on, and the thumb's own dot in the middle
	c.draw_texture_rect(UiUtil.sprite(&"disc"), Rect2(wheel.centre - Vector2.ONE * 30.0 * s, Vector2.ONE * 60.0 * s), false, Color(UiUtil.CYAN, 0.22))
	var r := RadialWheel.ITEM_R * s * wheel.disc_scale()                    # a dozen wedges or a narrow fan make the discs a little smaller so that they never overlap
	var texts: Array = []
	var cap := ""
	for i in n:
		var it: Dictionary = wheel.items[i]
		var ic := wheel.item_centre(i)
		var tint := UiUtil.CYAN
		var dim := 1.0
		if bool(it["active"]) or i == wheel.sel:
			tint = UiUtil.AMBER
		elif not bool(it["ready"]):
			dim = 0.45
		if i == wheel.sel:
			c.draw_texture_rect(UiUtil.sprite(&"disc"), Rect2(ic - Vector2.ONE * r * 1.12, Vector2.ONE * r * 2.24), false, Color(tint, 0.35))
		c.draw_texture_rect(UiUtil.sprite(&"disc"), Rect2(ic - Vector2.ONE * r * 0.98, Vector2.ONE * r * 1.96), false, Color(0.02, 0.05, 0.08, 0.97))      # opaque: RELOAD / ABILITY never show through a disc
		c.draw_texture_rect(UiUtil.sprite(&"button"), Rect2(ic - Vector2.ONE * r, Vector2.ONE * r * 2.0), false, Color(tint, 0.95 * dim))
		if float(it["cd"]) > 0.0:
			c.draw_arc(ic, r + 4.0 * s, -PI * 0.5, -PI * 0.5 + TAU * float(it["cd"]), 28, Color(tint, 0.9), 3.0 * s, false)
		if wheel.kind == &"weapon":
			# director review 5, defect 9: the picture fills the disc, the label is the class in full words (PISTOL, SHOTGUN), a badge counts the weapons owned in the class
			if StringName(it.get("type", &"")) == &"page":                          # the NEXT disc of a class ring: an arrow and the page
				var pc := ic + Vector2(0.0, -r * 0.18)
				c.draw_colored_polygon(PackedVector2Array([pc + Vector2(-r * 0.34, -r * 0.42), pc + Vector2(r * 0.42, 0.0), pc + Vector2(-r * 0.34, r * 0.42)]), Color(tint, 0.97))
			else:
				WeaponIcons.draw(c, StringName(it.get("icon", it["id"])), Rect2(ic.x - r * 0.92, ic.y - r * 0.86, r * 1.84, r * 1.1), Color(1, 1, 1, 0.97 * dim))
			texts.append([ic + Vector2(-r, r * 0.66), str(it.get("cname", it["label"])), r * 2.0, 17.0 if str(it.get("cname", "")).length() < 7 else (14.5 if str(it.get("cname", "")).length() < 10 else 12.5), dim])
			if bool(it.get("fav", false)):                                            # a starred weapon in a ring
				var sc := ic + Vector2(-r * 0.7, -r * 0.7)
				var spts := PackedVector2Array()
				for q in 10:
					var ang := -PI * 0.5 + TAU * float(q) / 10.0
					spts.append(sc + Vector2(cos(ang), sin(ang)) * (14.0 if q % 2 == 0 else 6.0) * s)
				c.draw_colored_polygon(spts, Color(UiUtil.AMBER, 0.97))
			if int(it.get("owned", 1)) > 1:
				var outward := (ic - wheel.centre).normalized() if ic.distance_to(wheel.centre) > 1.0 else Vector2(0.7, -0.7)
				var side := 1.0 if outward.x >= -0.15 else -1.0                           # the count sits at an upper corner of the disc: outside the ring for the discs of the upper half, inside it for the lower half,
				if outward.y > 0.2:                                                       # so that on a crowded ring it never covers the name of the disc next to it
					side = -side
				var bc := ic + Vector2(side * r * 0.8, -r * 0.8)
				var br := (13.0 if r < RadialWheel.ITEM_R * s * 0.9 else 15.0) * s
				c.draw_texture_rect(UiUtil.sprite(&"disc"), Rect2(bc - Vector2.ONE * br, Vector2.ONE * br * 2.0), false, Color(UiUtil.MAGENTA, 0.95))
				texts.append([bc + Vector2(-br, br * 0.47), str(int(it["owned"])), br * 2.0, 16.0, 1.0])
			if i == wheel.sel or (wheel.sel < 0 and bool(it.get("current", false))):
				cap = str(it.get("wname", "")) + (("    TAP: CHOOSE FROM %d" % int(it["owned"])) if int(it.get("owned", 1)) > 1 and bool(it.get("current", false)) else "")
		else:
			var words := str(it["label"]).split(" ")
			var fsz := 18.0
			for w: String in words:
				fsz = minf(fsz, float(UiUtil.fit_size(font, w, r * 2.0 - 10.0 * s, int(18.0 * s))) / s)
			var y0 := ic.y + fsz * s * 0.34 - (float(words.size() - 1) * fsz * s * 0.55)
			for k in words.size():
				texts.append([Vector2(ic.x - r, y0 + float(k) * fsz * s * 1.1), words[k], r * 2.0, fsz, dim])
	if cap != "":                                                           # the name of the weapon under the finger (or in the hand), large, at the top of the screen
		var csz := int(30.0 * s)
		var cw := minf(float(font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, csz).x) + 56.0 * s, _vp_size().x - 40.0 * s)
		var cr := Rect2((_vp_size().x - cw) * 0.5, UiUtil.insets_v(_vp_size()).x + 16.0 * s, cw, 56.0 * s)
		c.draw_rect(cr, Color(0.02, 0.05, 0.09, 0.96))
		c.draw_rect(cr, Color(UiUtil.AMBER, 0.95), false, 2.5 * s)
		c.draw_string(font, Vector2(cr.position.x, cr.position.y + 39.0 * s), cap, HORIZONTAL_ALIGNMENT_CENTER, cw, csz, Color(1, 1, 1, 0.98))
	for t: Array in texts:
		c.draw_string(font, (t[0] as Vector2) + Vector2(1.2, 1.2) * s, t[1], HORIZONTAL_ALIGNMENT_CENTER, t[2], int(float(t[3]) * s), Color(0, 0, 0, 0.8 * float(t[4])))
		c.draw_string(font, t[0], t[1], HORIZONTAL_ALIGNMENT_CENTER, t[2], int(float(t[3]) * s), Color(1, 1, 1, 0.97 * float(t[4])))


## The touch controls on screen right now: the stick, every visible button (by action) and the pause button. Empty unless the controls are on and the game is playing.
func visible_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if not controls_on or Game.state != &"play":
		return out
	out.append(&"stick")
	for b: Dictionary in BUTTONS:
		if button_visible(b):
			out.append(b["action"])
	out.append(&"pause")
	return out


func _minimap_rect() -> Rect2:
	var vp := _vp_size()
	var s := _scale()
	return Rect2(Vector2(UiUtil.insets(vp).x + 16.0 * s, 14.0 * s + UiUtil.insets_v(vp).x), Vector2(Hud.MINIMAP, Hud.MINIMAP) * s)


func open_map() -> void:
	var ms := get_node_or_null("MapScreen") as MapScreen
	if ms == null:
		ms = MapScreen.new()
		ms.name = "MapScreen"
		add_child(ms)
	ms.open()


func _open_garage() -> void:
	var gs := get_node_or_null("GarageScreen") as GarageScreen
	if gs == null:
		gs = GarageScreen.new()
		gs.name = "GarageScreen"
		add_child(gs)
	gs.open()


func _driving() -> bool:
	return is_instance_valid(Game.player) and Game.player.get("vehicle") != null


## The hero is in snake flight.
func _flying() -> bool:
	return is_instance_valid(Game.player) and Game.player.get("vehicle") == null and Game.player.get("snake") != null and (Game.player.get("snake") as SnakeTraversal).mode == SnakeTraversal.Mode.FLY


## The mode whose set of buttons is on screen: &"foot", &"flight", &"interior", or the class of the driven vehicle (&"car", &"bike", &"hover", &"boat", &"tank", &"heli", &"plane").
func mode() -> StringName:
	if _driving():
		return _craft_class()
	if _flying():
		return &"flight"
	return &"interior" if InteriorGameplay.active else &"foot"


## The HORN button: the sound, and the traffic ahead hears it (VehicleManager.hear).
func horn() -> void:
	var v := Game.player.get("vehicle") as Node3D if is_instance_valid(Game.player) else null
	if v == null:
		return
	Sfx.play_at(&"horn", v.global_position, -2.0)
	Sfx.last_played = &"horn"
	horns += 1
	if is_instance_valid(Game.vehicles) and Game.vehicles.has_method(&"hear"):
		Game.vehicles.call(&"hear", v.global_position, &"horn")


## The driven car carries a mounted weapon (rail gun, cannon, bolt gun): only then the FIRE button stays in a car.
func _car_armed() -> bool:
	var v: Object = Game.player.get("vehicle") if is_instance_valid(Game.player) else null
	return v != null and v.get("kind") is StringName and VehicleWeapons.has_weapon(v.get("kind") as StringName)


## The handling class of the vehicle being driven (&"car" when on foot).
func _craft_class() -> StringName:
	var v: Object = Game.player.get("vehicle") if is_instance_valid(Game.player) else null
	return StringName(v.get("cls")) if v != null and v.get("cls") is StringName else &"car"


func _vehicle_in_reach() -> bool:
	if not is_instance_valid(Game.vehicles) or not is_instance_valid(Game.player) or not Game.vehicles.has_method(&"nearest"):
		return false
	if Game.vehicles.has_method(&"reach_car"):
		return Game.vehicles.call(&"reach_car", Game.player.global_position) != null
	return Game.vehicles.call(&"nearest", Game.player.global_position, USE_REACH) != null


# ---------------------------------------------------------------------------------------------------------------------
# layout
# ---------------------------------------------------------------------------------------------------------------------

func _vp_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _scale() -> float:
	return UiUtil.ui_scale(_vp_size())


func _insets() -> Vector2:
	return UiUtil.insets(_vp_size())


func _button_center(b: Dictionary) -> Vector2:
	return centre_at(b, _vp_size())


## Centre of button `b` on a screen of `vp` canvas px (a pure function of the table, the screen and the left-hand setting: the tests lay out other screens with it).
static func centre_at(b: Dictionary, vp: Vector2) -> Vector2:
	var s := UiUtil.ui_scale(vp)
	var ins := UiUtil.insets(vp)
	var x := vp.x - ins.y - float(b["dx"]) * s
	if UiSettings.s_left_hand != (b.get("side", &"") == &"left"):       # the left row (above the stick) mirrors with the stick
		x = ins.x + float(b["dx"]) * s
	if b.get("top", false):
		return Vector2(x, UiUtil.insets_v(vp).x + float(b["dy"]) * s)
	return Vector2(x, vp.y - UiUtil.insets_v(vp).y - float(b["dy"]) * s)


func _pause_center() -> Vector2:
	return pause_at(_vp_size())


static func pause_at(vp: Vector2) -> Vector2:
	var s := UiUtil.ui_scale(vp)
	return Vector2(vp.x - UiUtil.insets(vp).y - 52.0 * s, 120.0 * s + UiUtil.insets_v(vp).x)     # the right edge under the heat stars: the faction / wanted plate used to sit on the old spot (director review)


## The rows of BUTTONS that can show in `mode` (ALL_MODES): what a layout check compares with each other.
static func buttons_of(mode: StringName) -> Array:
	var out: Array = []
	for b: Dictionary in BUTTONS:
		if (NEED_MODES.get(b["need"], ALL_MODES) as Array).has(mode):
			out.append(b)
	return out


## The perf readout sits under the minimap and is only shown while playing or paused.
func perf_visible() -> bool:
	return perf_on and perf_shown and (Game.state == &"play" or Game.state == &"paused")


## Shows or hides the FPS readout (and with it the renderer's CPU / GPU frame timing, which costs a little).
func show_perf(on: bool) -> void:
	perf_shown = on
	if not on:
		errors_on = false
	var po := get_tree().get_first_node_in_group(&"perf_overlay") if is_inside_tree() else null
	if po != null:
		(po as PerfOverlay).set_measure(on)
	_perf_t = 0.0
	if _canvas != null:
		_canvas.queue_redraw()


func _perf_box() -> Rect2:
	var s := _scale()
	return Rect2(Vector2(16.0 * s + _insets().x, 168.0 * s + UiUtil.insets_v(_vp_size()).x), Vector2(360.0, 90.0) * s)


func _refresh_perf() -> void:
	var draws := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var tex_mb := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)) / 1048576
	_perf_text = "FPS %d  (avg %d  worst %d)\nDraws %d   Tris %dk   Tex %d MB\nTier %s - tap to change\n%s" % [
		roundi(Engine.get_frames_per_second()), roundi(_avg_fps), roundi(_min_fps), draws, prims / 1000, tex_mb, PerfOverlay.tier_label(), PerfTimers.top_line()]


# ---------------------------------------------------------------------------------------------------------------------
# drawing
# ---------------------------------------------------------------------------------------------------------------------

func _draw_ui() -> void:
	var t0 := PerfTimers.start()
	_draw_ui_body()
	PerfTimers.stop(PerfTimers.TOUCH, t0)


func _draw_ui_body() -> void:
	var c := _canvas
	var size := _vp_size()
	var s := _scale()
	var font := UiUtil.font()
	if perf_visible():
		var box := _perf_box()
		c.draw_rect(box, Color(0, 0.03, 0.05, 0.6))
		c.draw_multiline_string(font, box.position + Vector2(8, 20) * s, _perf_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(15 * s), -1, Color(0.85, 1, 0.9, 0.95))
	if perf_visible() and errors_on:
		_draw_errors(c, font, s)
		_draw_report(c, font, s)
	if not controls_on or Game.state != &"play":
		return
	ScopeView.draw_mask(c, Game.player, size, s)             # wave 114 critic: the scope's surround is drawn UNDER the buttons (this canvas is below the HUD's): FIRE and RELOAD stay bright through the lens
	# move stick: a hint ring while idle, base and thumb while a finger is down
	if _stick_id == -1:
		c.draw_arc(Vector2(size.x - 190 * s - _insets().y if UiSettings.s_left_hand else 190 * s + _insets().x, size.y - 170 * s - UiUtil.insets_v(size).y), STICK_RADIUS * s, 0.0, TAU, 48, Color(1, 1, 1, 0.16), 2.0 * s, false)
	else:
		c.draw_circle(_stick_origin, STICK_RADIUS * s, Color(1, 1, 1, 0.07))
		c.draw_arc(_stick_origin, STICK_RADIUS * s, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0 * s, false)
		c.draw_circle(_stick_pos.limit_length(1e5), 38.0 * s, Color(0.5, 0.95, 1, 0.5))
	var labels: Array = []   # text is drawn after all shapes: glyph and plain draws alternating would break canvas batching
	var chips: Array = []    # wave 119: the edge chips (CROUCH, RELOAD, FLY, ABILITY): one StyleBoxFlat each
	var sprites: Array = []  # every button is ONE sprite (dark disc + bright rim): draw_circle + draw_arc per button cost two draw calls each, sprites of one texture batch
	var arcs: Array = []
	var glows: Array = []
	var down: Array = []
	for b: Dictionary in _held.values():
		down.append(b["action"])
	for b: Dictionary in BUTTONS:
		if not button_visible(b) or wheel.is_open:                 # an open wheel is the only thing on the thumb side: no button shows under or beside it
			continue
		var centre := _button_center(b)
		var r := float(b["r"]) * s * UiSettings.s_button_size
		var on := down.has(b["action"])
		var tint := UiUtil.CYAN
		var dim := 1.0
		if b["action"] == &"more":
			tint = UiUtil.AMBER if more_open else UiUtil.CYAN
		if b["action"] == &"ability":
			tint = UiUtil.AMBER if (wheel.is_open and wheel.kind == &"ability") else UiUtil.CYAN
		if (b["action"] == &"snake" or b["action"] == &"fly") and Game.player.get("snake") != null:
			var sn := Game.player.get("snake") as SnakeTraversal
			if sn.mode != SnakeTraversal.Mode.NONE:
				tint = UiUtil.AMBER                                 # a snake state is running
			if b["action"] == &"snake":
				var ef := sn.energy_fraction()
				if ef < 0.995:
					arcs.append([centre, r + 4.0 * s, -PI * 0.5 + TAU * ef, Color(UiUtil.MAGENTA if ef < 0.2 else tint, 0.9)])         # the snake energy is the ring around the button
		if b["action"] == &"snake_blast":
			SnakeBlasts.button_arcs(arcs, centre, r, s)               # wave 119 (w119-blasts): the species colour and the recharge arc
		if b.has("verb"):
			var vs := ((Game.player.get("qverbs") as QuantumVerbs).ui_state(b["verb"]) as Dictionary) if Game.player.get("qverbs") != null else {"active": false, "ready": true, "cd": 0.0}
			if vs["active"]:
				tint = UiUtil.AMBER
			elif not vs["ready"]:
				dim = 0.45
			if float(vs["cd"]) > 0.0:
				arcs.append([centre, r + 4.0 * s, -PI * 0.5 + TAU * float(vs["cd"]), Color(tint, 0.9)])
		if b.has("ability"):
			var st := UiUtil.ability_state(Game.player, UiUtil.ABILITIES[int(b["ability"])])
			if st["active"]:
				tint = UiUtil.AMBER
			elif not st["ready"]:
				dim = 0.45
			if float(st["cd"]) > 0.0:
				arcs.append([centre, r + 4.0 * s, -PI * 0.5 + TAU * float(st["cd"]), Color(tint, 0.9)])
		if b["action"] == &"companion_hold" and Companion.current != null and Companion.current.mode == Companion.Mode.HOLD:
			tint = UiUtil.AMBER
			on = true
		elif b["action"] == &"companion_attack" and Companion.current != null and Companion.current.mode == Companion.Mode.ATTACK:
			tint = UiUtil.AMBER
			on = true
		if on:
			glows.append([Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0), Color(tint, 0.35)])
		if b.get("chip", false):                        # wave 119: a small edge chip (rounded plate), not a round action button
			chips.append([Rect2(centre - Vector2(r * 1.12, r), Vector2(r * 2.24, r * 2.0)), Color(tint, (1.0 if on else 0.8) * dim), on])
		else:
			sprites.append([Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0), Color(tint, (1.0 if on else 0.85) * dim)])
		var fs := _label_size(b, font, r, s)
		if b["action"] == &"swap":                      # WEAPON: the weapon's silhouette over the ammo count (no separate ammo plate)
			_weapon_face(c, font, centre, r, s, labels)
			continue
		var lb := _label_of(b)
		if two_lines(lb):
			labels.append([centre + Vector2(-r, float(fs) * -0.2 * s), lb.get_slice(" ", 0), r * 2.0, dim, fs])
			labels.append([centre + Vector2(-r, float(fs) * 0.86 * s), lb.get_slice(" ", 1), r * 2.0, dim, fs])
			continue
		labels.append([centre + Vector2(-r, float(fs) * 0.36 * s), lb, r * 2.0, dim, fs])
	for g: Array in glows:
		c.draw_texture_rect(UiUtil.sprite(&"disc"), g[0], false, g[1])
	SnakeFx.hud_cues(self, s, sprites, labels)                 # w117-rope: the ZIP anchor marker, NO ANCHOR, the flight energy warning (rows of the two lists drawn below: no draw call more)
	for sp: Array in sprites:
		c.draw_texture_rect(UiUtil.sprite(&"button"), sp[0], false, sp[1])
	for ch: Array in chips:
		_chip_box.bg_color = Color(0.02, 0.05, 0.09, 0.62 if not ch[2] else 0.85)
		_chip_box.border_color = ch[1]
		_chip_box.set_border_width_all(maxi(1, int(2.0 * s)))
		_chip_box.set_corner_radius_all(int((ch[0] as Rect2).size.y * 0.32))
		c.draw_style_box(_chip_box, ch[0])
	for a: Array in arcs:
		c.draw_arc(a[0], a[1], -PI * 0.5, a[2], 32, a[3], 3.0 * s, false)
	var sizes := {}
	for l: Array in labels:
		sizes[l[4]] = true
	for fsz: int in sizes.keys():                       # shadows, then text, one size at a time (glyph atlases are per size)
		for l: Array in labels:
			if l[4] == fsz:
				c.draw_string(font, (l[0] as Vector2) + Vector2(1.5, 1.5) * s, l[1], HORIZONTAL_ALIGNMENT_CENTER, l[2], int(float(fsz) * s), Color(0, 0, 0, 0.8 * float(l[3])))
		for l: Array in labels:
			if l[4] == fsz:
				c.draw_string(font, l[0], l[1], HORIZONTAL_ALIGNMENT_CENTER, l[2], int(float(fsz) * s), Color(1, 1, 1, 0.97 * float(l[3])))
	if wheel.is_open:
		_draw_wheel(c, font, s)
	# pause
	var pc := _pause_center()
	var pr := PAUSE_R * s
	c.draw_arc(pc, pr, 0.0, TAU, 28, Color(1, 1, 1, 0.45), 2.0 * s, false)
	c.draw_rect(Rect2(pc + Vector2(-8, -10) * s, Vector2(5, 20) * s), Color(1, 1, 1, 0.8))
	c.draw_rect(Rect2(pc + Vector2(3, -10) * s, Vector2(5, 20) * s), Color(1, 1, 1, 0.8))


func _report_rect() -> Rect2:
	var box := _perf_box()
	var s := _scale()
	var top := box.end.y + 6.0 * s + (ERROR_ROWS * 15.0 + 22.0) * s + 6.0 * s
	return Rect2(Vector2(box.position.x, top), Vector2(minf(_vp_size().x - box.position.x - 12.0 * s, 620.0 * s), 150.0 * s))


func _copy_rect() -> Rect2:
	var r := _report_rect()
	var s := _scale()
	return Rect2(r.position + Vector2(r.size.x - 204.0 * s, 4.0 * s), Vector2(200.0, 64.0) * s)      # a 64 px touch target


## Debug panel part two: the live device report (same text the COPY REPORT button sends) and the button.
func _draw_report(c: Control, font: Font, s: float) -> void:
	var po := get_tree().get_first_node_in_group(&"perf_overlay")
	if po == null:
		return
	var r := _report_rect()
	c.draw_rect(r, Color(0.0, 0.04, 0.06, 0.7))
	c.draw_rect(r, Color(0.4, 0.9, 1.0, 0.6), false, 1.0 * s)
	var cr := _copy_rect()
	c.draw_rect(cr, Color(0.1, 0.35, 0.45, 0.9))
	c.draw_string(font, cr.position + Vector2(12, 42) * s, "COPIED" if _copied_t > 0.0 else "SEND REPORT", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(18.0 * s), Color(1, 1, 1, 0.95))
	var lines := (po as PerfOverlay).report().split("\n")
	for i in range(1, mini(lines.size(), 9)):
		c.draw_string(font, r.position + Vector2(6.0, 14.0 + (i - 1) * 16.0 + (30.0 if i > 5 else 0.0)) * s, lines[i], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12.0 * s, int(10.0 * s), Color(0.85, 1, 0.95, 0.95))


## The on-device error log (Dev.errors, also in user://last_errors.txt): the newest lines, small, under the perf readout.
func _draw_errors(c: Control, font: Font, s: float) -> void:
	var lines: PackedStringArray = Dev.error_lines()
	var box := _perf_box()
	var vp := _vp_size()
	var rect := Rect2(Vector2(box.position.x, box.end.y + 6.0 * s), Vector2(minf(vp.x - box.position.x - 12.0 * s, 620.0 * s), (ERROR_ROWS * 15.0 + 22.0) * s))
	c.draw_rect(rect, Color(0.05, 0.0, 0.0, 0.62))
	c.draw_rect(rect, Color(1.0, 0.35, 0.3, 0.6), false, 1.0 * s)
	var head := "ERRORS %d  (long-press FPS to hide, file: last_errors.txt)" % Dev.errors.total
	c.draw_string(font, rect.position + Vector2(6.0, 14.0) * s, head, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0 * s, int(11.0 * s), Color(1.0, 0.7, 0.6, 0.95))
	if lines.is_empty():
		c.draw_string(font, rect.position + Vector2(6.0, 32.0) * s, "no errors", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(11.0 * s), Color(0.6, 1.0, 0.7, 0.9))
		return
	var first := maxi(0, lines.size() - ERROR_ROWS)
	for i in range(first, lines.size()):
		c.draw_string(font, rect.position + Vector2(6.0, 30.0 + (i - first) * 15.0) * s, lines[i], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0 * s, int(10.0 * s), Color(1, 0.92, 0.88, 0.92))
