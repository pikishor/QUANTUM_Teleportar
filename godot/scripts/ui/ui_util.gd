class_name UiUtil
extends RefCounted
## Shared HUD helpers: layout scale and safe-area insets, the condensed UI font, palette, and ability state for the quantum powers.

const BASE_H := 720.0
const CYAN := Color(0.45, 0.95, 1.0)
const MAGENTA := Color(1.0, 0.25, 0.75)
const AMBER := Color(1.0, 0.72, 0.25)
const RED := Color(1.0, 0.3, 0.32)
const GREEN := Color(0.4, 1.0, 0.6)
const INK := Color(0.02, 0.05, 0.07)
## Quantum powers: action, label, key hint, energy cost and cooldown (seconds) as in the prototype / quantum contract.
const ABILITIES := [
	{"action": &"blink", "label": "BLINK", "key": "Q", "cost": 15.0, "cd": 0.3, "cd_prop": &"cd_blink"},
	{"action": &"entangle", "label": "LINK", "key": "E", "cost": 25.0, "cd": 0.8, "cd_prop": &"cd_link"},
	{"action": &"superpose", "label": "SUPER", "key": "G", "cost": 35.0, "cd": 1.5, "cd_prop": &"cd_super"},
]

static var _font: Font


static func ui_scale(vp: Vector2) -> float:
	return maxf(vp.y / BASE_H, 0.1)


## Notch and rounded-corner insets (left, right) in canvas px.
static func insets(vp: Vector2) -> Vector2:
	var win := DisplayServer.window_get_size()
	if win.x <= 0:
		return Vector2.ZERO
	var sa := DisplayServer.get_display_safe_area()
	if sa.size.x <= 0:
		return Vector2.ZERO
	var k := vp.x / float(win.x)
	return Vector2(maxf(sa.position.x, 0.0) * k, maxf(float(win.x - sa.end.x), 0.0) * k)


## Condensed, slightly tracked sans (system condensed faces first, then the engine fallback).
static func font() -> Font:
	if _font == null:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Roboto Condensed", "sans-serif-condensed", "Bahnschrift", "Arial Narrow", "DIN Condensed", "Oswald", "Inter", "Sans-Serif"])
		sys.font_weight = 600
		sys.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		var fv := FontVariation.new()
		fv.base_font = sys
		fv.spacing_glyph = 1
		_font = fv
	return _font


## Numeric property of an object, or `fallback` when it is missing or not a number (stand-in players, modules still loading).
static func num(o: Object, prop: StringName, fallback: float) -> float:
	if o == null:
		return fallback
	var v: Variant = o.get(prop)
	return float(v) if (v is float or v is int) else fallback


## State of one quantum power: {on: bool (the module exists), ready: bool, low: bool (not enough energy), active: bool, cd: 0..1 (cooldown left)}.
static func ability_state(player: Node, info: Dictionary) -> Dictionary:
	var q: Object = player.get("quantum") if is_instance_valid(player) else null
	if q == null:
		return {"on": false, "ready": false, "low": false, "active": false, "cd": 0.0}
	var energy := num(player, &"energy", 100.0)
	var left := num(q, info["cd_prop"], 0.0)
	var active := false
	match info["action"]:
		&"blink":
			active = q.get("has_beacon") == true
		&"entangle":
			var links: Variant = q.get("links")
			active = links is Array and not (links as Array).is_empty()
		&"superpose":
			active = is_instance_valid(q.get("clone") as Object)
	var low := energy < float(info["cost"]) and not active
	return {"on": true, "ready": left <= 0.0 and not low, "low": low, "active": active, "cd": clampf(left / float(info["cd"]), 0.0, 1.0)}
