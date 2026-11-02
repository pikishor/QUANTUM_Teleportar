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
	{"action": &"blink", "label": "QUANTUM TELEPORT", "key": "Q", "cost": 15.0, "cd": 0.3, "cd_prop": &"cd_blink"},
	{"action": &"entangle", "label": "LINK", "key": "E", "cost": 25.0, "cd": 0.8, "cd_prop": &"cd_link"},
	{"action": &"superpose", "label": "SUPER", "key": "G", "cost": 35.0, "cd": 1.5, "cd_prop": &"cd_super"},
]

## Phone text sizes (base px at 720 p height; the layout scales them with the viewport height). Gameplay text is never below TEXT_MIN except the small bar captions.
const TEXT_MIN := 26
const BAR_LABEL := 22
const TOUCH_MIN := 64.0                  ## base px: no touch hit area is smaller than this across
const SAFE_WIDE := 24.0                 ## base px: side margin kept free on wide (20:9 and up) phones even without a reported notch
const PLATE := Color(0.0, 0.03, 0.05, 0.62)     ## backing plate behind every line of gameplay text: legible over bright neon and over cables

static var _font: Font
static var _sprites := {}
## Bottom of the HUD's top-centre stack (bars + objective plate) in base px: the story layer starts its own lines below it, so nothing collides.
static var stack_bottom := 100.0
## Bottom of the HUD's top-left column (minimap, then the perf readout on phones) in base px: the radio subtitle plate sits right under it.
static var left_bottom := 190.0


static func ui_scale(vp: Vector2) -> float:
	return maxf(vp.y / BASE_H, 0.1)


## Notch and rounded-corner insets (left, right) in canvas px.
static func insets(vp: Vector2) -> Vector2:
	var win := DisplayServer.window_get_size()
	if win.x <= 0:
		return _wide_floor(vp, Vector2.ZERO)
	var sa := DisplayServer.get_display_safe_area()
	if sa.size.x <= 0:
		return _wide_floor(vp, Vector2.ZERO)
	var k := vp.x / float(win.x)
	return _wide_floor(vp, Vector2(maxf(sa.position.x, 0.0) * k, maxf(float(win.x - sa.end.x), 0.0) * k))


## Wide screens (20:9, 21:9) curve and carry cameras at the sides: keep at least SAFE_WIDE base px clear on both even when the OS reports no inset.
static func _wide_floor(vp: Vector2, v: Vector2) -> Vector2:
	if vp.x / maxf(vp.y, 1.0) < 1.9:
		return v
	var f := SAFE_WIDE * ui_scale(vp)
	return Vector2(maxf(v.x, f), maxf(v.y, f))


## Small procedural white sprites (&"disc", &"ring", &"diamond", &"star", &"button": a dark translucent disc with a bright rim, tinted by modulate). Canvas rectangles that
## share a texture batch into one draw call, while draw_circle / draw_arc / draw_colored_polygon cost one draw call EACH: the HUD draws its round and star shapes with these.
static func sprite(kind: StringName) -> Texture2D:
	if _sprites.has(kind):
		return _sprites[kind]
	var n := 128 if kind == &"button" else 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var star := PackedVector2Array()
	if kind == &"star":
		for i in 10:
			var a := -PI * 0.5 + i * PI / 5.0
			star.append(Vector2(cos(a), sin(a)) * (1.0 if i % 2 == 0 else 0.45))
	var half := n * 0.5
	for y in n:
		for x in n:
			var p := (Vector2(x + 0.5, y + 0.5) - Vector2(half, half)) / half          # -1 .. 1
			var d := p.length()
			var col := Color(1, 1, 1, 0.0)
			match kind:
				&"disc":
					col.a = clampf((1.0 - d) * half + 0.5, 0.0, 1.0)
				&"ring":
					col.a = clampf((0.09 - absf(d - 0.91)) * half + 0.5, 0.0, 1.0)
				&"diamond":
					col.a = clampf((1.0 - (absf(p.x) + absf(p.y))) * half * 0.7 + 0.5, 0.0, 1.0)
				&"star":
					col.a = 1.0 if Geometry2D.is_point_in_polygon(p, star) else 0.0
				&"button":
					var edge := clampf((1.0 - d) * half + 0.5, 0.0, 1.0)
					var rim := clampf((0.032 - absf(d - 0.965)) * half + 0.5, 0.0, 1.0)
					col = Color(0.12, 0.2, 0.26, 0.55 * edge).lerp(Color(1, 1, 1, 1.0), rim)
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_sprites[kind] = tex
	return tex


## Notch / home-indicator insets (top, bottom) in canvas px, 0 on desktop.
static func insets_v(vp: Vector2) -> Vector2:
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return Vector2.ZERO
	var sa := DisplayServer.get_display_safe_area()
	if sa.size.y <= 0:
		return Vector2.ZERO
	var k := vp.y / float(win.y)
	return Vector2(maxf(sa.position.y, 0.0) * k, maxf(float(win.y - sa.end.y), 0.0) * k)


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


## State of one quantum power: {on: bool (the module exists), ready: bool, low: bool (not enough energy), active: bool, cd: 0..1 (cooldown left), left: seconds the active effect has left}.
static func ability_state(player: Node, info: Dictionary) -> Dictionary:
	var q: Object = player.get("quantum") if is_instance_valid(player) else null
	if q == null:
		return {"on": false, "ready": false, "low": false, "active": false, "cd": 0.0, "left": 0.0}
	var energy := num(player, &"energy", 100.0)
	var left := num(q, info["cd_prop"], 0.0)
	var active := false
	var remaining := 0.0
	match info["action"]:
		&"blink":
			active = q.get("has_beacon") == true
			remaining = num(q, &"beacon_left", 0.0)
		&"entangle":
			var links: Variant = q.get("links")
			active = links is Array and not (links as Array).is_empty()
			if active:
				for l: Variant in links as Array:
					remaining = maxf(remaining, float((l as Dictionary).get("t", 0.0)))
		&"superpose":
			active = is_instance_valid(q.get("clone") as Object)
			remaining = num(q, &"clone_left", 0.0)
	var low := energy < float(info["cost"]) and not active
	return {"on": true, "ready": left <= 0.0 and not low, "low": low, "active": active, "cd": clampf(left / float(info["cd"]), 0.0, 1.0), "left": remaining if active else 0.0}
