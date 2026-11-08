class_name MenuKit
extends RefCounted
## Shared look of the menu screens (director review round 2, defect 12: "menus are lists of small buttons"): a CARD is an opaque plate with a coloured accent bar, a round icon, a big
## title and an optional one-line caption; a PRIMARY card is the one action of a screen (filled). Every card is >= UiUtil.TOUCH_MIN tall, its text is never below BODY px (22 at 1080p).
## Hud keeps the hit rects (`buttons`: {id, rect, label, on, icon, sub, primary}); this file only draws: Hud calls `card` for a button that has an `icon`, and screens call `tab` / `row`.
## Icons are plain vector glyphs (no textures: no memory), named in ICONS.

const BODY := 15.0                    ## base px: smallest card text (22 px at 1080p)
const TITLE := 23.0                   ## base px: card title
const FILL := Color(0.045, 0.06, 0.11, 0.97)
const FILL_ON := Color(0.10, 0.16, 0.24, 0.98)
const ICONS: Array[StringName] = [&"play", &"map", &"loadout", &"options", &"more", &"hero", &"missions", &"heists", &"suit", &"safehouse", &"achievements", &"photo", &"arena",
	&"chapters", &"demo", &"plus", &"back", &"abort", &"test", &"sound", &"display", &"controls", &"gameplay", &"data", &"weapon", &"gear", &"buy", &"lock", &"check"]


## A card: plate, accent bar, icon disc, title and caption (the caption may be "").
static func card(hud: Hud, c: Control, r: Rect2, label: String, sub: String, icon: StringName, tint: Color, on: bool, hot: bool, primary: bool, s: float, font: Font) -> void:
	var fill := FILL_ON if (on or hot) else FILL
	if primary:
		fill = Color(tint.r * 0.42, tint.g * 0.42, tint.b * 0.42, 0.98)
	c.draw_rect(r, fill)
	c.draw_rect(r, Color(tint, 1.0 if (primary or on or hot) else 0.62), false, (3.0 if primary else 2.0) * s)
	c.draw_rect(Rect2(r.position.x, r.position.y, 6.0 * s, r.size.y), tint)
	var ir := minf(r.size.y * 0.3, 24.0 * s)
	var ic := Vector2(r.position.x + 18.0 * s + ir + 4.0 * s, r.position.y + r.size.y * 0.5)
	if icon != &"":
		c.draw_circle(ic, ir + 4.0 * s, Color(tint, 0.20 if not primary else 0.35))
		glyph(c, icon, ic, ir * 0.78, tint.lerp(Color.WHITE, 0.55 if primary else 0.25), s)
	var tx := ic.x + ir + 16.0 * s if icon != &"" else r.position.x + 16.0 * s
	var tw := r.end.x - tx - 10.0 * s
	var tsz := UiUtil.fit_size(font, label, tw, int(TITLE * s))
	tsz = maxi(tsz, int(BODY * s))
	var col := Color(1, 1, 1, 0.98 if (primary or on or hot) else 0.9)
	if sub == "":
		hud._text(c, font, Vector2(tx, r.position.y + r.size.y * 0.5 + tsz * 0.34), label, HORIZONTAL_ALIGNMENT_LEFT, tw, tsz, col)
	else:
		hud._text(c, font, Vector2(tx, r.position.y + r.size.y * 0.5 - 2.0 * s), label, HORIZONTAL_ALIGNMENT_LEFT, tw, tsz, col)
		var ssz := maxi(UiUtil.fit_size(font, sub, tw, int(BODY * s)), int(BODY * s))
		hud._text(c, font, Vector2(tx, r.position.y + r.size.y * 0.5 + ssz * 1.15), sub, HORIZONTAL_ALIGNMENT_LEFT, tw, ssz, Color(tint.lerp(Color.WHITE, 0.45), 0.9))


## A tab of a tab strip: a short opaque plate, the open one lit with a bar under it.
static func tab(hud: Hud, c: Control, r: Rect2, label: String, icon: StringName, on: bool, hot: bool, s: float, font: Font) -> void:
	var tint := UiUtil.CYAN
	c.draw_rect(r, FILL_ON if on else FILL)
	c.draw_rect(r, Color(tint, 0.95 if on else 0.4), false, (2.5 if on else 1.5) * s)
	if on:
		c.draw_rect(Rect2(r.position.x, r.end.y - 6.0 * s, r.size.x, 6.0 * s), UiUtil.MAGENTA)
	var tsz := maxi(UiUtil.fit_size(font, label, r.size.x - 46.0 * s, int(TITLE * s)), int(BODY * s))
	var tw := hud._text_width(font, label, tsz)
	var x0 := r.position.x + (r.size.x - tw - 30.0 * s) * 0.5
	if icon != &"":
		glyph(c, icon, Vector2(x0 + 11.0 * s, r.position.y + r.size.y * 0.5 - 2.0 * s), 10.0 * s, Color(1, 1, 1, 0.95 if on else 0.6), s)
	hud._text(c, font, Vector2(x0 + 30.0 * s, r.position.y + r.size.y * 0.5 + tsz * 0.3 - 2.0 * s), label, HORIZONTAL_ALIGNMENT_LEFT, tw + 4.0, tsz, Color(1, 1, 1, 0.98 if (on or hot) else 0.72))


## A settings row: the name on the left, the value on the right in a lit chip. A slider row (frac >= 0) gets its track along the bottom edge.
static func row(hud: Hud, c: Control, r: Rect2, name: String, value: String, on: bool, hot: bool, frac: float, s: float, font: Font) -> void:
	if frac >= 0.0:
		on = false                                          # a slider is not "on": its track says how much
	var tint := UiUtil.CYAN if not on else UiUtil.GREEN
	c.draw_rect(r, FILL_ON if hot else FILL)
	c.draw_rect(r, Color(tint, 0.9 if hot else 0.35), false, 1.5 * s)
	c.draw_rect(Rect2(r.position.x, r.position.y, 5.0 * s, r.size.y), tint if on else Color(tint, 0.35))
	var body := r if frac < 0.0 else Rect2(r.position, Vector2(r.size.x, r.size.y - 18.0 * s))
	var vsz := maxi(UiUtil.fit_size(font, value, r.size.x * 0.38, int(TITLE * s)), int(BODY * s))
	var vw := hud._text_width(font, value, vsz) + 28.0 * s if value != "" else 0.0
	var chip := Rect2(r.end.x - vw - 10.0 * s, body.position.y + body.size.y * 0.5 - 20.0 * s, vw, 40.0 * s)
	if value != "":
		c.draw_rect(chip, Color(tint, 0.30 if on else 0.14))
		c.draw_rect(chip, Color(tint, 0.8 if on else 0.4), false, 1.5 * s)
		hud._text(c, font, Vector2(chip.position.x, chip.position.y + chip.size.y * 0.5 + vsz * 0.34), value, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, vsz, Color(1, 1, 1, 0.98))
	var nw := (chip.position.x if value != "" else r.end.x) - r.position.x - 26.0 * s
	var nsz := maxi(UiUtil.fit_size(font, name, nw, int(TITLE * s)), int(BODY * s))
	hud._text(c, font, Vector2(r.position.x + 18.0 * s, body.position.y + body.size.y * 0.5 + nsz * 0.34), name, HORIZONTAL_ALIGNMENT_LEFT, nw, nsz, Color(1, 1, 1, 0.95))
	if frac >= 0.0:
		var tr := Rect2(r.position.x + 8.0, r.end.y - 16.0 * s, r.size.x - 16.0, 6.0 * s)       # the same 8 px inset the drag maths of Hud uses
		c.draw_rect(tr, Color(1, 1, 1, 0.14))
		c.draw_rect(Rect2(tr.position, Vector2(tr.size.x * frac, tr.size.y)), Color(UiUtil.MAGENTA, 0.95))
		c.draw_circle(Vector2(tr.position.x + tr.size.x * frac, tr.position.y + tr.size.y * 0.5), 9.0 * s, Color(1, 1, 1, 0.97))


## An upgrade part card: its name, what it does and a status strip (ON / EQUIP / BUY price) along the bottom.
static func part(hud: Hud, c: Control, r: Rect2, name: String, fx: String, status: String, state: int, hot: bool, s: float, font: Font) -> void:
	var tint := UiUtil.GREEN if state == 2 else (UiUtil.CYAN if state == 1 else UiUtil.AMBER)
	c.draw_rect(r, FILL_ON if (hot or state == 2) else FILL)
	c.draw_rect(r, Color(tint, 0.95 if state == 2 else 0.55), false, (3.0 if state == 2 else 1.5) * s)
	var strip := Rect2(r.position.x, r.end.y - 30.0 * s, r.size.x, 30.0 * s)
	c.draw_rect(strip, Color(tint, 0.34 if state == 2 else 0.22))
	if font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(BODY * s)).x > r.size.x - 16.0 * s and name.ends_with(" CORE"):
		name = name.trim_suffix(" CORE")                       # a narrow card drops the generic word instead of overflowing into its neighbour
	var nsz := maxi(UiUtil.fit_size(font, name, r.size.x - 16.0 * s, int(17.0 * s)), int(BODY * s))
	hud._text(c, font, Vector2(r.position.x + 10.0 * s, r.position.y + 24.0 * s), name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16.0 * s, nsz, Color(1, 1, 1, 0.98))
	var fsz := maxi(UiUtil.fit_size(font, fx, r.size.x - 16.0 * s, int(BODY * s)), int(BODY * s))
	hud._text(c, font, Vector2(r.position.x + 10.0 * s, r.position.y + 24.0 * s + fsz * 1.2), fx, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16.0 * s, fsz, Color(1, 1, 1, 0.65))
	var ssz := maxi(UiUtil.fit_size(font, status, r.size.x - 12.0 * s, int(TITLE * s)), int(BODY * s))
	hud._text(c, font, Vector2(strip.position.x, strip.position.y + strip.size.y * 0.5 + ssz * 0.34), status, HORIZONTAL_ALIGNMENT_CENTER, strip.size.x, ssz, Color(tint.lerp(Color.WHITE, 0.5), 1.0))


## A vector glyph in a circle of radius r about p.
static func glyph(c: Control, id: StringName, p: Vector2, r: float, col: Color, s: float) -> void:
	var w := maxf(2.0 * s, r * 0.16)
	match id:
		&"play":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 0.6, -r), p + Vector2(r, 0), p + Vector2(-r * 0.6, r)]), col)
		&"map":
			c.draw_circle(p + Vector2(0, -r * 0.25), r * 0.6, col)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 0.5, 0), p + Vector2(r * 0.5, 0), p + Vector2(0, r)]), col)
			c.draw_circle(p + Vector2(0, -r * 0.25), r * 0.25, Color(0, 0, 0, 0.8))
		&"loadout", &"weapon":
			c.draw_rect(Rect2(p + Vector2(-r, -r * 0.35), Vector2(r * 2.0, r * 0.6)), col)
			c.draw_rect(Rect2(p + Vector2(-r * 0.5, r * 0.2), Vector2(r * 0.4, r * 0.8)), col)
			c.draw_rect(Rect2(p + Vector2(r * 0.4, -r * 0.6), Vector2(r * 0.5, r * 0.25)), col)
		&"options", &"controls":
			for i in 3:
				var y := (float(i) - 1.0) * r * 0.75
				c.draw_line(p + Vector2(-r, y), p + Vector2(r, y), col, w)
				c.draw_circle(p + Vector2((float((i * 5) % 3) - 1.0) * r * 0.5, y), r * 0.28, col)
		&"more":
			for i in 4:
				c.draw_rect(Rect2(p + Vector2((float(i % 2) - 1.0) * r * 0.95 + r * 0.1, (float(i / 2) - 1.0) * r * 0.95 + r * 0.1), Vector2(r * 0.8, r * 0.8)), col)
		&"hero":
			c.draw_circle(p + Vector2(0, -r * 0.55), r * 0.38, col)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 0.8, r), p + Vector2(-r * 0.5, -r * 0.05), p + Vector2(r * 0.5, -r * 0.05), p + Vector2(r * 0.8, r)]), col)
		&"missions":
			c.draw_line(p + Vector2(-r * 0.6, r), p + Vector2(-r * 0.6, -r), col, w)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 0.6, -r), p + Vector2(r * 0.9, -r * 0.45), p + Vector2(-r * 0.6, r * 0.1)]), col)
		&"heists", &"gear", &"buy":
			c.draw_rect(Rect2(p + Vector2(-r, -r * 0.4), Vector2(r * 2.0, r * 1.3)), col)
			c.draw_arc(p + Vector2(0, -r * 0.4), r * 0.4, PI, TAU, 12, col, w)
			c.draw_rect(Rect2(p + Vector2(-r * 0.15, 0), Vector2(r * 0.3, r * 0.3)), Color(0, 0, 0, 0.7))
		&"suit":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 0.4, -r), p + Vector2(r * 0.4, -r), p + Vector2(r, -r * 0.3), p + Vector2(r * 0.65, r * 0.1), p + Vector2(r * 0.45, -r * 0.05), p + Vector2(r * 0.45, r), p + Vector2(-r * 0.45, r), p + Vector2(-r * 0.45, -r * 0.05), p + Vector2(-r * 0.65, r * 0.1), p + Vector2(-r, -r * 0.3)]), col)
		&"safehouse":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-r, -r * 0.1), p + Vector2(0, -r), p + Vector2(r, -r * 0.1)]), col)
			c.draw_rect(Rect2(p + Vector2(-r * 0.7, -r * 0.1), Vector2(r * 1.4, r * 1.05)), col)
			c.draw_rect(Rect2(p + Vector2(-r * 0.2, r * 0.3), Vector2(r * 0.4, r * 0.65)), Color(0, 0, 0, 0.7))
		&"achievements":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + float(i) * PI / 5.0
				pts.append(p + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
			c.draw_colored_polygon(pts, col)
		&"photo":
			c.draw_rect(Rect2(p + Vector2(-r, -r * 0.55), Vector2(r * 2.0, r * 1.5)), col)
			c.draw_rect(Rect2(p + Vector2(-r * 0.4, -r * 0.9), Vector2(r * 0.8, r * 0.4)), col)
			c.draw_circle(p + Vector2(0, r * 0.2), r * 0.45, Color(0, 0, 0, 0.75))
		&"arena", &"demo":
			c.draw_arc(p, r, 0.0, TAU, 20, col, w)
			c.draw_arc(p, r * 0.5, 0.0, TAU, 14, col, w)
			c.draw_circle(p, r * 0.18, col)
		&"chapters":
			c.draw_rect(Rect2(p + Vector2(-r, -r * 0.8), Vector2(r * 0.95, r * 1.6)), col)
			c.draw_rect(Rect2(p + Vector2(r * 0.05, -r * 0.8), Vector2(r * 0.95, r * 1.6)), Color(col, 0.65))
		&"plus":
			c.draw_line(p + Vector2(-r, 0), p + Vector2(r, 0), col, w * 1.4)
			c.draw_line(p + Vector2(0, -r), p + Vector2(0, r), col, w * 1.4)
		&"back":
			c.draw_line(p + Vector2(r, 0), p + Vector2(-r, 0), col, w * 1.4)
			c.draw_polyline(PackedVector2Array([p + Vector2(-r * 0.2, -r * 0.8), p + Vector2(-r, 0), p + Vector2(-r * 0.2, r * 0.8)]), col, w * 1.4)
		&"abort":
			c.draw_line(p + Vector2(-r * 0.8, -r * 0.8), p + Vector2(r * 0.8, r * 0.8), col, w * 1.4)
			c.draw_line(p + Vector2(r * 0.8, -r * 0.8), p + Vector2(-r * 0.8, r * 0.8), col, w * 1.4)
		&"sound":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-r, -r * 0.35), p + Vector2(-r * 0.4, -r * 0.35), p + Vector2(r * 0.2, -r * 0.9), p + Vector2(r * 0.2, r * 0.9), p + Vector2(-r * 0.4, r * 0.35), p + Vector2(-r, r * 0.35)]), col)
			c.draw_arc(p, r * 0.8, -0.8, 0.8, 8, col, w)
		&"display":
			c.draw_rect(Rect2(p + Vector2(-r, -r * 0.7), Vector2(r * 2.0, r * 1.2)), col, false, w)
			c.draw_line(p + Vector2(-r * 0.4, r * 0.95), p + Vector2(r * 0.4, r * 0.95), col, w)
		&"gameplay":
			c.draw_circle(p, r, Color(col, 0.0))
			c.draw_rect(Rect2(p + Vector2(-r, -r * 0.5), Vector2(r * 2.0, r)), col)
			c.draw_circle(p + Vector2(-r * 0.4, 0), r * 0.22, Color(0, 0, 0, 0.75))
			c.draw_circle(p + Vector2(r * 0.4, 0), r * 0.22, Color(0, 0, 0, 0.75))
		&"data", &"lock":
			c.draw_rect(Rect2(p + Vector2(-r * 0.8, -r * 0.1), Vector2(r * 1.6, r * 1.1)), col)
			c.draw_arc(p + Vector2(0, -r * 0.1), r * 0.55, PI, TAU, 10, col, w)
		&"check":
			c.draw_polyline(PackedVector2Array([p + Vector2(-r, 0), p + Vector2(-r * 0.3, r * 0.7), p + Vector2(r, -r * 0.7)]), col, w * 1.5)
		&"test":
			c.draw_line(p + Vector2(-r, -r * 0.7), p + Vector2(r, -r * 0.7), col, w * 1.5)
			c.draw_line(p + Vector2(0, -r * 0.7), p + Vector2(0, r), col, w * 1.5)
		_:
			c.draw_circle(p, r * 0.6, col)
