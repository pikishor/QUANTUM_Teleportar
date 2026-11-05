class_name ControlMap
extends RefCounted
## Control bindings: the controller layout and the keyboard remap. Pure data and maths (the InputMap is touched only by apply_keys / set_primary).
## Controller: a physical input is a SLOT ("0:a" = A, "1:a" = LB held + A); LB is the layer modifier, START pauses, the sticks move and look. `pad_binds` maps slot -> action
## and is polled by ControllerInput (which presses the same actions the keyboard and the touch overlay drive). Keyboard: the primary key of an action in the InputMap.

## slot name -> [kind, index]: "b" a joypad button, "t" a trigger axis (pressed past TRIGGER_AT)
const SLOTS := {
	"a": ["b", JOY_BUTTON_A], "b": ["b", JOY_BUTTON_B], "x": ["b", JOY_BUTTON_X], "y": ["b", JOY_BUTTON_Y],
	"rb": ["b", JOY_BUTTON_RIGHT_SHOULDER], "ls": ["b", JOY_BUTTON_LEFT_STICK], "rs": ["b", JOY_BUTTON_RIGHT_STICK],
	"du": ["b", JOY_BUTTON_DPAD_UP], "dd": ["b", JOY_BUTTON_DPAD_DOWN], "dl": ["b", JOY_BUTTON_DPAD_LEFT], "dr": ["b", JOY_BUTTON_DPAD_RIGHT],
	"back": ["b", JOY_BUTTON_BACK], "lt": ["t", JOY_AXIS_TRIGGER_LEFT], "rt": ["t", JOY_AXIS_TRIGGER_RIGHT],
}
const SLOT_LABELS := {
	"a": "A", "b": "B", "x": "X", "y": "Y", "rb": "RB", "ls": "LS", "rs": "RS", "du": "UP", "dd": "DOWN", "dl": "LEFT", "dr": "RIGHT", "back": "BACK", "lt": "LT", "rt": "RT",
}
const SLOT_ORDER: Array[String] = ["a", "b", "x", "y", "rb", "ls", "rs", "du", "dd", "dl", "dr", "back", "lt", "rt"]
const TRIGGER_AT := 0.35

## slot -> action. Layer 0 is the plain layout, layer 1 is LB held (the second ring: ring verbs, takedown, gadgets).
const DEFAULT_PAD := {
	"0:a": &"jump", "0:b": &"crouch", "0:x": &"reload", "0:y": &"interact", "0:rb": &"blink", "0:ls": &"sprint", "0:rs": &"melee",
	"0:du": &"entangle", "0:dr": &"superpose", "0:dd": &"collapse", "0:dl": &"swap", "0:back": &"altfire", "0:lt": &"aim", "0:rt": &"fire",
	"1:a": &"shield", "1:b": &"slip", "1:x": &"arc", "1:y": &"takedown", "1:rb": &"radio_next", "1:ls": &"sprint", "1:rs": &"melee",
	"1:du": &"gadget", "1:dr": &"throw_item", "1:dd": &"grab", "1:dl": &"weapon_prev", "1:back": &"altfire", "1:lt": &"aim", "1:rt": &"fire",
}
## Actions the controller screen lists (fire and aim sit on the triggers and move with the slot swap).
const PAD_ACTIONS: Array[StringName] = [
	&"jump", &"crouch", &"reload", &"interact", &"sprint", &"melee", &"blink", &"entangle", &"superpose", &"collapse", &"swap", &"weapon_prev",
	&"altfire", &"throw_item", &"gadget", &"grab", &"takedown", &"shield", &"slip", &"arc", &"radio_next",
]
## Actions the keyboard screen lists (fire and aim are on the mouse).
const KEY_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"crouch", &"reload", &"interact", &"blink", &"entangle", &"superpose",
	&"collapse", &"takedown", &"swap", &"altfire", &"melee", &"throw_item", &"gadget", &"grab", &"shield", &"slip", &"arc",
]
const NAMES := {
	&"move_forward": "FORWARD", &"move_back": "BACK", &"move_left": "LEFT", &"move_right": "RIGHT", &"jump": "JUMP", &"sprint": "SPRINT", &"crouch": "CROUCH",
	&"reload": "RELOAD", &"interact": "USE", &"blink": "QUANTUM TELEPORT", &"entangle": "ENTANGLE", &"superpose": "SUPERPOSITION", &"collapse": "COLLAPSE",
	&"takedown": "TAKEDOWN", &"swap": "SWAP", &"weapon_prev": "PREV WEAPON", &"altfire": "ALT FIRE", &"melee": "MELEE", &"throw_item": "THROW", &"gadget": "GADGET",
	&"grab": "GRAB", &"shield": "SHIELD", &"slip": "SLIP", &"arc": "ARC", &"radio_next": "RADIO", &"fire": "FIRE", &"aim": "AIM",
}
const RESERVED_KEYS: Array[int] = [KEY_ESCAPE]

## The live controller bindings (UiSettings.publish copies its own here).
static var pad_binds: Dictionary = DEFAULT_PAD.duplicate()


static func default_pad() -> Dictionary:
	return DEFAULT_PAD.duplicate()


static func slot_name(slot: String) -> String:
	return slot.get_slice(":", 1)


static func slot_layer(slot: String) -> int:
	return 1 if slot.begins_with("1:") else 0


static func slot_valid(slot: String) -> bool:
	return slot.contains(":") and slot_layer(slot) in [0, 1] and SLOTS.has(slot_name(slot))


## "A", "LB+A", "RT".
static func slot_label(slot: String) -> String:
	return ("LB+" if slot_layer(slot) == 1 else "") + String(SLOT_LABELS.get(slot_name(slot), "?"))


## The slots a polled device state presses: `buttons` {joy button -> bool}, `axes` {joy axis -> float}, `layer` 0 / 1. Returns slot names ("a", "rt", ...).
static func pressed_slots(buttons: Dictionary, axes: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for n: String in SLOT_ORDER:
		var d: Array = SLOTS[n]
		if d[0] == "b":
			if bool(buttons.get(d[1], false)):
				out.append(n)
		elif float(axes.get(d[1], 0.0)) > TRIGGER_AT:
			out.append(n)
	return out


## The actions (action -> strength 1) held by the pressed slots in a layer.
static func actions_for(binds: Dictionary, slots: Array[String], layer: int) -> Dictionary:
	var out := {}
	for n: String in slots:
		var a := StringName(str(binds.get("%d:%s" % [layer, n], &"")))
		if a != &"":
			out[a] = 1.0
	return out


## The first slot (layer 0 first) bound to an action, "" when none.
static func slot_of(binds: Dictionary, action: StringName) -> String:
	for layer in 2:
		for n: String in SLOT_ORDER:
			var k := "%d:%s" % [layer, n]
			if StringName(binds.get(k, &"")) == action:
				return k
	return ""


## Binds an action to a slot; the action that sat on the slot swaps to the slot this one left. Returns the (same) dictionary.
static func rebind_pad(binds: Dictionary, action: StringName, slot: String) -> Dictionary:
	if not slot_valid(slot):
		return binds
	var old := slot_of(binds, action)
	var prev: StringName = StringName(binds.get(slot, &""))
	if old == slot:
		return binds
	binds[slot] = action
	if old != "":
		if prev != &"":
			binds[old] = prev
		else:
			binds.erase(old)
	return binds


## A saved dictionary cleaned up: unknown slots and actions drop, the defaults fill the rest.
static func sanitize_pad(v: Variant) -> Dictionary:
	var out := default_pad()
	if v is Dictionary:
		var known: Array = PAD_ACTIONS.duplicate()
		known.append_array([&"fire", &"aim"])
		for k: Variant in (v as Dictionary):
			var a := StringName(str((v as Dictionary)[k]))
			if k is String and slot_valid(k) and known.has(a):
				out[k] = a
	return out


# ---------------------------------------------------------------------------------------------------------------------
# keyboard
# ---------------------------------------------------------------------------------------------------------------------

## The primary (first) physical key of an action, KEY_NONE when it has none.
static func key_of(action: StringName) -> int:
	if not InputMap.has_action(action):
		return KEY_NONE
	for e: InputEvent in InputMap.action_get_events(action):
		if e is InputEventKey:
			return int((e as InputEventKey).physical_keycode)
	return KEY_NONE


static func key_label(code: int) -> String:
	return "-" if code == KEY_NONE else OS.get_keycode_string(code as Key).to_upper()


## Replaces the primary key of an action in the InputMap (its other keys and mouse buttons stay).
static func set_primary(action: StringName, code: int) -> void:
	if not InputMap.has_action(action):
		return
	var ev := InputMap.action_get_events(action)
	InputMap.action_erase_events(action)
	var done := false
	for e: InputEvent in ev:
		if e is InputEventKey and not done:
			var k := InputEventKey.new()
			k.physical_keycode = code as Key
			InputMap.action_add_event(action, k)
			done = true
		else:
			InputMap.action_add_event(action, e)
	if not done:
		var k2 := InputEventKey.new()
		k2.physical_keycode = code as Key
		InputMap.action_add_event(action, k2)


## Gives an action a new primary key; the action that used it swaps to the key this one left. `binds` (action name -> keycode) records every change.
static func rebind_key(binds: Dictionary, action: StringName, code: int) -> Dictionary:
	if RESERVED_KEYS.has(code) or not KEY_ACTIONS.has(action):
		return binds
	var old := key_of(action)
	if old == code:
		return binds
	for other: StringName in KEY_ACTIONS:
		if other != action and key_of(other) == code:
			set_primary(other, old)
			binds[String(other)] = old
	set_primary(action, code)
	binds[String(action)] = code
	return binds


## Applies saved overrides to the InputMap.
static func apply_keys(binds: Dictionary) -> void:
	for k: Variant in binds:
		var a := StringName(str(k))
		if KEY_ACTIONS.has(a) and binds[k] is int and not RESERVED_KEYS.has(int(binds[k])):
			set_primary(a, int(binds[k]))


## Back to the default primary keys (Game.ACTION_KEYS).
static func reset_keys() -> void:
	for a: StringName in KEY_ACTIONS:
		var def: Array = Game.ACTION_KEYS.get(a, [])
		if not def.is_empty():
			set_primary(a, int(def[0]))


static func sanitize_keys(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k: Variant in (v as Dictionary):
			var val: Variant = (v as Dictionary)[k]
			if k is String and KEY_ACTIONS.has(StringName(k)) and (val is int) and int(val) > 0 and not RESERVED_KEYS.has(int(val)):
				out[k] = int(val)
	return out


static func action_name(a: StringName) -> String:
	return String(NAMES.get(a, String(a).to_upper()))
