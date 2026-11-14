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


## A card: the kit's cut-corner panel with an accent bar, an icon disc, a title and a caption (the caption may be ""). Drawn by scripts/ui/ui_kit.gd.
static func card(hud: Hud, c: Control, r: Rect2, label: String, sub: String, icon: StringName, tint: Color, on: bool, hot: bool, primary: bool, s: float, font: Font) -> void:
	UiKit.card(hud, c, r, label, sub, icon, tint, on, hot, primary, s, font)


## A tab of a tab strip (UiKit.tab).
static func tab(hud: Hud, c: Control, r: Rect2, label: String, icon: StringName, on: bool, hot: bool, s: float, font: Font) -> void:
	UiKit.tab(hud, c, r, label, icon, on, hot, s, font)


## A settings row (UiKit.row): the name on the left, the value on the right in a lit chip; a slider row (frac >= 0) gets its track along the bottom edge.
static func row(hud: Hud, c: Control, r: Rect2, name: String, value: String, on: bool, hot: bool, frac: float, s: float, font: Font) -> void:
	UiKit.row(hud, c, r, name, value, on, hot, frac, s, font)


## An upgrade part card: its name, what it does and a status strip (ON / EQUIP / BUY price) along the bottom.
static func part(hud: Hud, c: Control, r: Rect2, name: String, fx: String, status: String, state: int, hot: bool, s: float, font: Font) -> void:
	var tint := UiUtil.GREEN if state == 2 else (UiUtil.CYAN if state == 1 else UiUtil.AMBER)
	UiKit.panel(c, r, s, tint, hot or state == 2, 8.0, state == 2)
	var strip := Rect2(r.position.x + 1.5 * s, r.end.y - 30.0 * s, r.size.x - 3.0 * s, 28.5 * s)
	var kk := 8.0 * s - 1.5 * s                                    # follows the chamfer of the panel's bottom-right corner
	c.draw_colored_polygon(PackedVector2Array([strip.position, Vector2(strip.end.x, strip.position.y), Vector2(strip.end.x, strip.end.y - kk), Vector2(strip.end.x - kk, strip.end.y), Vector2(strip.position.x, strip.end.y)]), Color(tint, 0.34 if state == 2 else 0.22))
	if font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(BODY * s)).x > r.size.x - 16.0 * s and name.ends_with(" CORE"):
		name = name.trim_suffix(" CORE")                       # a narrow card drops the generic word instead of overflowing into its neighbour
	var nsz := maxi(UiUtil.fit_size(font, name, r.size.x - 16.0 * s, int(17.0 * s)), int(BODY * s))
	name = UiUtil.fit_text(font, name, r.size.x - 16.0 * s, nsz)         # a line that still does not fit at the smallest size is cut (a wide device font), it does not run into the next card
	hud._text(c, font, Vector2(r.position.x + 10.0 * s, r.position.y + 24.0 * s), name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16.0 * s, nsz, Color(1, 1, 1, 0.98))
	var fsz := maxi(UiUtil.fit_size(font, fx, r.size.x - 16.0 * s, int(BODY * s)), int(BODY * s))
	fx = UiUtil.fit_text(font, fx, r.size.x - 16.0 * s, fsz)
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
