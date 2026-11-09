class_name UiKit
extends RefCounted
## The one UI kit of the menu screens (owner round 5: "much better, more detailed UI for menus, options and weapons"). Every screen builds its look from THESE pieces so the whole
## game reads as one design: a cut-corner PANEL with a soft vertical gradient, a CARD (icon, title, caption), a BUTTON, a TAB strip, a LIST ROW, a SLIDER row (track, ticks, handle, value),
## a TOGGLE switch row, a BADGE, a CHIP, a STAT BAR with a compare marker, the ICON set, the type scale, the colours, the 8 px spacing grid and the screen ENTER transition.
## Hud keeps the hit rects (`buttons`: {id, rect, label, on, ...}); this file only draws. Text goes through `Hud._text` (queued, never below BODY_MIN, wraps through the font fit), rectangles and
## polygons are drawn directly, so a panel is always UNDER the text of its own card. Tokens are base px at 720 p (multiply by the UI scale `s`).
## Test: tests/test_ui_kit_screens.gd (layout scan of every screen) and tests/bot_ui_kit_shots.gd (renders them).

# --- spacing grid (base px) ---------------------------------------------------------------------------------------------------------
const UNIT := 8.0                       ## the grid: gaps and paddings are multiples of 8 base px
const GAP := 8.0
const PAD := 16.0
const CUT := 10.0                       ## chamfer of the panel corners (top-left and bottom-right)

# --- type scale (base px at 720 p; Hud never prints a menu text below BODY_MIN) -------------------------------------------------------
const T_CAP := 15.0                     ## captions, badges, units
const T_BODY := 19.0                    ## descriptions, numbers
const T_LABEL := 22.0                   ## row names, button labels
const T_TITLE := 28.0                   ## card titles
const T_HERO := 44.0                    ## screen titles

# --- colours ------------------------------------------------------------------------------------------------------------------------
const INK := Color(0.02, 0.04, 0.07)
const SURFACE_TOP := Color(0.085, 0.11, 0.185, 0.97)
const SURFACE_BOT := Color(0.035, 0.045, 0.09, 0.97)
const SURFACE_LIT_TOP := Color(0.15, 0.21, 0.32, 0.98)
const SURFACE_LIT_BOT := Color(0.07, 0.10, 0.18, 0.98)
const LINE := Color(1, 1, 1, 0.16)
const TEXT := Color(1, 1, 1, 0.97)
const TEXT_DIM := Color(1, 1, 1, 0.66)
const GOOD := Color(0.4, 1.0, 0.6)
const BAD := Color(1.0, 0.36, 0.38)
## One accent per weapon class: the bar of a tile, the badge of the card, the tab of the loadout.
const CLASS_TINT := {
	&"pistol": Color(0.55, 0.85, 1.0), &"smg": Color(0.45, 0.95, 0.85), &"rifle": Color(1.0, 0.72, 0.25), &"shotgun": Color(1.0, 0.5, 0.3), &"sniper": Color(0.75, 0.6, 1.0),
	&"heavy": Color(1.0, 0.38, 0.38), &"melee": Color(0.9, 0.9, 0.95), &"quantum": Color(1.0, 0.25, 0.75), &"energy": Color(0.4, 1.0, 0.6), &"blast": Color(1.0, 0.55, 0.15),
}
## Screen title -> icon (Hud.header draws it beside the title).
const TITLE_ICON := {
	"LOADOUT": &"loadout", "OPTIONS": &"options", "MISSIONS": &"missions", "EXTRAS": &"more", "PAUSED": &"play", "UPGRADES": &"hero", "WEAPONS": &"weapon", "GEAR": &"gear",
	"SUIT": &"suit", "SAFEHOUSE": &"safehouse", "ACHIEVEMENTS": &"achievements", "CHAPTERS": &"chapters", "GARAGE": &"car", "SHOP": &"buy", "MAP": &"map", "SIDE JOBS": &"missions",
	"HEISTS": &"heists", "ARENA": &"arena", "CONTROLS": &"controls",
}
const ENTER_TIME := 0.20                ## seconds a screen takes to slide in (a cut between panels reads as clumsy)
const ENTER_SLIDE := 14.0               ## base px the content rises while it fades in


# --- helpers ------------------------------------------------------------------------------------------------------------------------

## `n` grid units in px at scale s.
static func sp(n: float, s: float) -> float:
	return n * UNIT * s


static func ease_out(t: float) -> float:
	var u := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - u * u * u


## How far (px) the screen content is still below its resting place `age` seconds after the screen opened (0 once settled).
static func enter_offset(age: float, s: float) -> float:
	return (1.0 - ease_out(age / ENTER_TIME)) * ENTER_SLIDE * s


static func class_tint(cls: StringName) -> Color:
	return CLASS_TINT.get(cls, UiUtil.CYAN)


## The chamfered rectangle: the top-left and bottom-right corners are cut by k px.
static func cut_poly(r: Rect2, k: float) -> PackedVector2Array:
	k = minf(k, minf(r.size.x, r.size.y) * 0.45)
	return PackedVector2Array([r.position + Vector2(k, 0.0), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y - k), r.end - Vector2(k, 0.0), Vector2(r.position.x, r.end.y), r.position + Vector2(0.0, k)])


static func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	out.append(poly[0])
	return out


## A panel: a cut-corner plate with a vertical gradient, a thin outline in `tint` and a short bright accent along its top-left edge. `lit` = the selected / hovered look.
static func panel(c: Control, r: Rect2, s: float, tint: Color = UiUtil.CYAN, lit := false, cut := CUT, strong := false) -> void:
	var poly := cut_poly(r, cut * s)
	var top := SURFACE_LIT_TOP if lit else SURFACE_TOP
	var bot := SURFACE_LIT_BOT if lit else SURFACE_BOT
	c.draw_polygon(poly, PackedColorArray([top, top, bot, bot, bot, top]))
	c.draw_polyline(_closed(poly), Color(tint, 1.0 if (lit or strong) else 0.5), (2.5 if (lit or strong) else 1.5) * s)
	var k := cut * s
	c.draw_line(r.position + Vector2(k + 2.0 * s, 1.0 * s), r.position + Vector2(k + 2.0 * s + minf(r.size.x * 0.3, 60.0 * s), 1.0 * s), Color(tint.lerp(Color.WHITE, 0.4), 0.95 if lit else 0.7), 2.0 * s)


## A flat dark plate (no cut): the backdrop of a group of rows.
static func plate(c: Control, r: Rect2, s: float, tint: Color = UiUtil.CYAN, alpha := 0.9) -> void:
	c.draw_rect(r, Color(0.03, 0.045, 0.085, alpha))
	c.draw_rect(r, Color(tint, 0.3), false, 1.5 * s)


## A section header: a short coloured bar, the caption in capitals and a hairline to the right edge of `r`.
static func section(hud: Hud, c: Control, r: Rect2, caption: String, tint: Color, s: float, font: Font) -> void:
	c.draw_rect(Rect2(r.position.x, r.position.y + 4.0 * s, 5.0 * s, r.size.y - 8.0 * s), tint)
	var sz := maxi(UiUtil.fit_size(font, caption, r.size.x * 0.6, int(T_LABEL * s)), int(Hud.BODY_MIN * s))
	var tw := hud._text_width(font, Tr.t(caption), sz)
	hud._text(c, font, Vector2(r.position.x + 14.0 * s, r.position.y + r.size.y * 0.5 + sz * 0.34), caption, HORIZONTAL_ALIGNMENT_LEFT, tw + 4.0, sz, Color(tint.lerp(Color.WHITE, 0.35), 0.98), 1.0 * s)
	var lx := r.position.x + 14.0 * s + tw + 14.0 * s
	if lx < r.end.x:
		c.draw_line(Vector2(lx, r.position.y + r.size.y * 0.5), Vector2(r.end.x, r.position.y + r.size.y * 0.5), Color(tint, 0.35), 1.5 * s)


## Word-wrap `text` into at most `max_lines` lines of `width` px at font size `size` (the last line keeps the rest and is cut with ... only when it still does not fit).
static func wrap_text(hud: Hud, font: Font, text: String, width: float, size: int, max_lines: int) -> Array[String]:
	var out: Array[String] = []
	var cur := ""
	for w in text.split(" ", false):
		var trial: String = w if cur == "" else cur + " " + w
		if hud._text_width(font, trial, size) <= width or cur == "":
			cur = trial
		else:
			out.append(cur)
			cur = w
	if cur != "":
		out.append(cur)
	if out.size() > max_lines:
		var rest := " ".join(out.slice(max_lines - 1))
		out = out.slice(0, max_lines - 1)
		out.append(rest)
	return out


# --- cards, buttons, tabs, rows -----------------------------------------------------------------------------------------------------

## A card: panel, accent bar, icon disc, title and an optional caption. `primary` = the one filled action of a screen; `chev` adds a chevron (the card opens a screen).
static func card(hud: Hud, c: Control, r: Rect2, label: String, sub: String, icon: StringName, tint: Color, on: bool, hot: bool, primary: bool, s: float, font: Font, chev := false, rpad := 0.0) -> void:
	var lit := on or hot
	if primary:
		var poly := cut_poly(r, CUT * s)
		var a := Color(tint.r * 0.62, tint.g * 0.62, tint.b * 0.62, 0.99)
		var b := Color(tint.r * 0.30, tint.g * 0.30, tint.b * 0.30, 0.99)
		c.draw_polygon(poly, PackedColorArray([a, a, b, b, b, a]))
		c.draw_polyline(_closed(poly), Color(tint.lerp(Color.WHITE, 0.25), 1.0), 3.0 * s)
		c.draw_line(r.position + Vector2(CUT * s + 2.0 * s, 1.5 * s), r.position + Vector2(r.size.x * 0.5, 1.5 * s), Color(1, 1, 1, 0.55), 2.0 * s)
	else:
		panel(c, r, s, tint, lit)
	c.draw_rect(Rect2(r.position.x + 1.0 * s, r.position.y + CUT * s, 5.0 * s, maxf(r.size.y - 2.0 * CUT * s, 4.0 * s)), tint)
	var ir := minf(r.size.y * 0.3, 24.0 * s)
	var ic := Vector2(r.position.x + 20.0 * s + ir + 2.0 * s, r.position.y + r.size.y * 0.5)
	if icon != &"":
		c.draw_circle(ic, ir + 4.0 * s, Color(tint, 0.38 if primary else 0.22))
		c.draw_arc(ic, ir + 4.0 * s, 0.0, TAU, 28, Color(tint, 0.7 if (lit or primary) else 0.35), 1.5 * s)
		glyph(c, icon, ic, ir * 0.78, tint.lerp(Color.WHITE, 0.6 if primary else 0.3), s)
	var tx := ic.x + ir + 16.0 * s if icon != &"" else r.position.x + 18.0 * s
	var tw := r.end.x - tx - (34.0 * s if chev else 12.0 * s) - rpad
	var tsz := maxi(UiUtil.fit_size(font, label, tw, int(T_TITLE * s)), int(Hud.BODY_MIN * s))
	var col := Color(1, 1, 1, 0.98 if (primary or lit) else 0.92)
	if sub == "":
		hud._text(c, font, Vector2(tx, r.position.y + r.size.y * 0.5 + tsz * 0.34), label, HORIZONTAL_ALIGNMENT_LEFT, tw, tsz, col)
	else:
		var ssz := maxi(UiUtil.fit_size(font, sub, tw, int(T_BODY * s)), int(Hud.BODY_MIN * s))
		var lines: Array[String] = [Tr.t(sub)]
		if hud._text_width(font, Tr.t(sub), ssz) > tw:                          # a long caption wraps to two lines instead of running under the next element
			lines = wrap_text(hud, font, Tr.t(sub), tw, ssz, 2)
		var total := tsz * 0.8 + float(lines.size()) * ssz * 1.2
		var top := r.position.y + (r.size.y - total) * 0.5
		hud._text(c, font, Vector2(tx, top + tsz * 0.8), label, HORIZONTAL_ALIGNMENT_LEFT, tw, tsz, col)
		for li in lines.size():
			hud._text(c, font, Vector2(tx, top + tsz * 0.8 + ssz * 1.2 * float(li + 1)), lines[li], HORIZONTAL_ALIGNMENT_LEFT, tw, ssz, Color(tint.lerp(Color.WHITE, 0.5), 0.92))
	if chev:
		var p := Vector2(r.end.x - 20.0 * s, r.position.y + r.size.y * 0.5)
		c.draw_polyline(PackedVector2Array([p + Vector2(-5.0 * s, -9.0 * s), p + Vector2(4.0 * s, 0.0), p + Vector2(-5.0 * s, 9.0 * s)]), Color(1, 1, 1, 0.75), 2.5 * s)


## A plain labelled button (no icon): `state` 0 normal, 1 lit (selected / hovered), 2 primary. The label centres; a long one wraps to two lines at a readable size.
static func button(hud: Hud, c: Control, r: Rect2, label: String, tint: Color, state: int, s: float, font: Font, size_base := T_LABEL) -> void:
	if state == 2:
		var poly := cut_poly(r, CUT * 0.8 * s)
		var a := Color(tint.r * 0.6, tint.g * 0.6, tint.b * 0.6, 0.99)
		var b := Color(tint.r * 0.3, tint.g * 0.3, tint.b * 0.3, 0.99)
		c.draw_polygon(poly, PackedColorArray([a, a, b, b, b, a]))
		c.draw_polyline(_closed(poly), Color(tint.lerp(Color.WHITE, 0.2), 1.0), 2.5 * s)
	else:
		panel(c, r, s, tint, state == 1, CUT * 0.8)
	var bw := r.size.x - 16.0 * s
	var bsz := UiUtil.fit_size(font, label, bw, int(size_base * s))
	var col := Color(1, 1, 1, 0.98 if state > 0 else 0.88)
	if bsz < int(Hud.BODY_MIN * s) and label.contains(" "):
		var ln := Hud._split_label(label)
		var longer: String = ln[0] if hud._text_width(font, ln[0], 20) >= hud._text_width(font, ln[1], 20) else ln[1]
		var sz2 := maxi(UiUtil.fit_size(font, longer, bw, int(20.0 * s)), int(Hud.BODY_MIN * s))
		var top := r.position.y + (r.size.y - sz2 * 2.15) * 0.5
		hud._text(c, font, Vector2(r.position.x, top + sz2 * 0.9), ln[0], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, sz2, col)
		hud._text(c, font, Vector2(r.position.x, top + sz2 * 2.0), ln[1], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, sz2, col)
		return
	bsz = maxi(bsz, int(Hud.BODY_MIN * s))
	hud._text(c, font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + bsz * 0.34), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, bsz, col)


## A tab of a tab strip: an icon and a label; the open one is lit with a bar under it.
static func tab(hud: Hud, c: Control, r: Rect2, label: String, icon: StringName, on: bool, hot: bool, s: float, font: Font, tint: Color = UiUtil.CYAN) -> void:
	panel(c, r, s, tint, on or hot, 8.0)
	if on:
		c.draw_rect(Rect2(r.position.x + 8.0 * s, r.end.y - 6.0 * s, r.size.x - 16.0 * s, 4.0 * s), UiUtil.MAGENTA)
	var tsz := maxi(UiUtil.fit_size(font, label, r.size.x - 52.0 * s, int(T_LABEL * s)), int(Hud.BODY_MIN * s))
	var tw := hud._text_width(font, Tr.t(label), tsz)
	var x0 := r.position.x + (r.size.x - tw - (30.0 * s if icon != &"" else 0.0)) * 0.5
	if icon != &"":
		glyph(c, icon, Vector2(x0 + 11.0 * s, r.position.y + r.size.y * 0.5 - 2.0 * s), 10.0 * s, Color(1, 1, 1, 0.98 if on else 0.6), s)
	hud._text(c, font, Vector2(x0 + (30.0 * s if icon != &"" else 0.0), r.position.y + r.size.y * 0.5 + tsz * 0.3 - 2.0 * s), label, HORIZONTAL_ALIGNMENT_LEFT, tw + 4.0, tsz, Color(1, 1, 1, 0.98 if (on or hot) else 0.72))


## A settings row: the name left, the value in a lit chip right. A slider row (frac >= 0) gets a track along the bottom edge with ticks and a round handle.
static func row(hud: Hud, c: Control, r: Rect2, name: String, value: String, on: bool, hot: bool, frac: float, s: float, font: Font, hint := "") -> void:
	if frac >= 0.0:
		on = false
	var tint := UiUtil.CYAN if not on else UiUtil.GREEN
	panel(c, r, s, tint, hot, 7.0)
	var body := r if frac < 0.0 else Rect2(r.position, Vector2(r.size.x, r.size.y - 20.0 * s))
	var vsz := maxi(UiUtil.fit_size(font, value, r.size.x * 0.38, int(T_LABEL * s)), int(Hud.BODY_MIN * s))
	var vw := hud._text_width(font, Tr.t(value), vsz) + 28.0 * s if value != "" else 0.0
	var chip_r := Rect2(r.end.x - vw - 12.0 * s, body.position.y + body.size.y * 0.5 - 20.0 * s, vw, 40.0 * s)
	if value != "":
		c.draw_rect(chip_r, Color(tint, 0.30 if on else 0.14))
		c.draw_rect(chip_r, Color(tint, 0.8 if on else 0.4), false, 1.5 * s)
		hud._text(c, font, Vector2(chip_r.position.x, chip_r.position.y + chip_r.size.y * 0.5 + vsz * 0.34), value, HORIZONTAL_ALIGNMENT_CENTER, chip_r.size.x, vsz, Color(1, 1, 1, 0.98))
	var nw := (chip_r.position.x if value != "" else r.end.x) - r.position.x - 28.0 * s
	var nsz := maxi(UiUtil.fit_size(font, name, nw, int(T_LABEL * s)), int(Hud.BODY_MIN * s))
	_name_hint(hud, c, r.position.x + 20.0 * s, body.position.y + body.size.y * 0.5, name, hint if frac < 0.0 else "", nw, nsz, s, font)
	if frac >= 0.0:
		slider_track(c, Rect2(r.position.x + 8.0, r.end.y - 18.0 * s, r.size.x - 16.0, 8.0 * s), frac, s, hot)


## A row's name (and, under it, a dim one-line hint of what the option does) centred on `mid_y`.
static func _name_hint(hud: Hud, c: Control, x: float, mid_y: float, name: String, hint: String, w: float, nsz: int, s: float, font: Font) -> void:
	if hint == "":
		hud._text(c, font, Vector2(x, mid_y + nsz * 0.34), name, HORIZONTAL_ALIGNMENT_LEFT, w, nsz, Color(1, 1, 1, 0.96))
		return
	var hsz := int(Hud.BODY_MIN * s)
	hud._text(c, font, Vector2(x, mid_y - 2.0 * s), name, HORIZONTAL_ALIGNMENT_LEFT, w, nsz, Color(1, 1, 1, 0.96))
	hud._text(c, font, Vector2(x, mid_y + 2.0 * s + hsz * 1.05), hint, HORIZONTAL_ALIGNMENT_LEFT, w, hsz, Color(1, 1, 1, 0.55))


## The track of a slider: dark groove, ticks every tenth, the magenta fill and a round handle with a ring. The horizontal inset (8 px) is the one Hud.slide() uses.
static func slider_track(c: Control, tr: Rect2, frac: float, s: float, hot := false) -> void:
	c.draw_rect(tr, Color(1, 1, 1, 0.12))
	c.draw_rect(Rect2(tr.position, Vector2(tr.size.x * frac, tr.size.y)), Color(UiUtil.MAGENTA, 0.95))
	for i in range(1, 10):
		var x := tr.position.x + tr.size.x * float(i) / 10.0
		c.draw_line(Vector2(x, tr.position.y - 2.0 * s), Vector2(x, tr.end.y + 2.0 * s), Color(1, 1, 1, 0.16), 1.0 * s)
	var hp := Vector2(tr.position.x + tr.size.x * frac, tr.position.y + tr.size.y * 0.5)
	c.draw_circle(hp, 12.0 * s if hot else 10.0 * s, Color(UiUtil.MAGENTA, 0.35))
	c.draw_circle(hp, 8.0 * s, Color(1, 1, 1, 0.98))
	c.draw_arc(hp, 8.0 * s, 0.0, TAU, 18, Color(UiUtil.MAGENTA, 1.0), 2.0 * s)


## A toggle row: the name left and a pill switch right (green with the knob right when on). A caption `hint` may sit under the name.
static func toggle_row(hud: Hud, c: Control, r: Rect2, name: String, on: bool, hot: bool, s: float, font: Font, state_word := "", hint := "") -> void:
	var tint := UiUtil.GREEN if on else UiUtil.CYAN
	panel(c, r, s, tint, hot, 7.0)
	var sw := Rect2(r.end.x - 84.0 * s, r.position.y + r.size.y * 0.5 - 15.0 * s, 64.0 * s, 30.0 * s)
	toggle_switch(c, sw, on, s)
	var word := state_word if state_word != "" else ("ON" if on else "OFF")
	var wsz := int(Hud.BODY_MIN * s)
	var ww := hud._text_width(font, Tr.t(word), wsz) + 8.0 * s
	hud._text(c, font, Vector2(sw.position.x - ww - 8.0 * s, r.position.y + r.size.y * 0.5 + wsz * 0.34), word, HORIZONTAL_ALIGNMENT_RIGHT, ww, wsz, Color(tint.lerp(Color.WHITE, 0.3), 0.95 if on else 0.65))
	var nw := sw.position.x - ww - 20.0 * s - r.position.x - 20.0 * s
	var nsz := maxi(UiUtil.fit_size(font, name, nw, int(T_LABEL * s)), int(Hud.BODY_MIN * s))
	_name_hint(hud, c, r.position.x + 20.0 * s, r.position.y + r.size.y * 0.5, name, hint, nw, nsz, s, font)


## The pill switch itself.
static func toggle_switch(c: Control, sw: Rect2, on: bool, s: float) -> void:
	var col := Color(UiUtil.GREEN, 0.9) if on else Color(1, 1, 1, 0.22)
	var rad := sw.size.y * 0.5
	c.draw_circle(sw.position + Vector2(rad, rad), rad, col)
	c.draw_circle(sw.position + Vector2(sw.size.x - rad, rad), rad, col)
	c.draw_rect(Rect2(sw.position.x + rad, sw.position.y, sw.size.x - 2.0 * rad, sw.size.y), col)
	var kx := sw.end.x - rad if on else sw.position.x + rad
	c.draw_circle(Vector2(kx, sw.position.y + rad), rad - 3.0 * s, Color(1, 1, 1, 0.98) if on else Color(1, 1, 1, 0.8))


## A small label chip on a dark plate; returns its rect. `pos` is the left-middle of the chip (the right-middle with `right_aligned`).
static func badge(hud: Hud, c: Control, pos: Vector2, text: String, tint: Color, s: float, font: Font, filled := false, right_aligned := false) -> Rect2:
	var sz := int(Hud.BODY_MIN * s)
	var tw := hud._text_width(font, Tr.t(text), sz)
	var r := Rect2(pos.x - (tw + 20.0 * s if right_aligned else 0.0), pos.y - 15.0 * s, tw + 20.0 * s, 30.0 * s)
	c.draw_rect(r, Color(tint, 0.5 if filled else 0.2))
	c.draw_rect(r, Color(tint, 0.95 if filled else 0.65), false, 1.5 * s)
	hud._text(c, font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + sz * 0.34), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, sz, Color(1, 1, 1, 0.97) if filled else Color(tint.lerp(Color.WHITE, 0.55), 0.98))
	return r


## A stat bar: the label left (`lab_w` px), a segmented track with the value filled, and, when `cmp` >= 0, a white marker at the compared value plus a +/- delta in whole percent to
## the right of the track (green = better than the compared weapon, red = worse). Returns nothing; the track is `track`.
static func stat_bar(hud: Hud, c: Control, r: Rect2, label: String, v: float, s: float, font: Font, lab_w: float, cmp := -1.0, tint := Color(0, 0, 0, 0)) -> void:
	var lsz := maxi(UiUtil.fit_size(font, label, lab_w - 6.0 * s, int(T_CAP * s)), int(Hud.BODY_MIN * s))
	hud._text(c, font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + lsz * 0.34), label, HORIZONTAL_ALIGNMENT_LEFT, lab_w, lsz, Color(1, 1, 1, 0.9))
	var dw := 56.0 * s if cmp >= 0.0 else 0.0
	var tr := Rect2(r.position.x + lab_w, r.position.y + r.size.y * 0.5 - 8.0 * s, r.size.x - lab_w - dw, 16.0 * s)
	c.draw_rect(tr, Color(1, 1, 1, 0.1))
	var col := tint if tint.a > 0.0 else Color(UiUtil.CYAN, 0.95).lerp(Color(UiUtil.AMBER, 0.97), clampf((v - 0.55) * 2.0, 0.0, 1.0))
	c.draw_rect(Rect2(tr.position, Vector2(tr.size.x * clampf(v, 0.0, 1.0), tr.size.y)), col)
	for i in range(1, 10):
		var x := tr.position.x + tr.size.x * float(i) / 10.0
		c.draw_line(Vector2(x, tr.position.y), Vector2(x, tr.end.y), Color(0, 0, 0, 0.35), 1.0 * s)
	c.draw_rect(tr, Color(1, 1, 1, 0.25), false, 1.0 * s)
	if cmp >= 0.0:
		var mx := tr.position.x + tr.size.x * clampf(cmp, 0.0, 1.0)
		c.draw_line(Vector2(mx, tr.position.y - 4.0 * s), Vector2(mx, tr.end.y + 4.0 * s), Color(1, 1, 1, 0.98), 3.0 * s)
		var d := roundi((v - cmp) * 100.0)
		var dcol := GOOD if d > 0 else (BAD if d < 0 else TEXT_DIM)
		var dtxt := ("+%d" % d) if d > 0 else ("%d" % d if d < 0 else "=")
		hud._text(c, font, Vector2(tr.end.x + 6.0 * s, r.position.y + r.size.y * 0.5 + lsz * 0.34), dtxt, HORIZONTAL_ALIGNMENT_LEFT, dw - 8.0 * s, lsz, Color(dcol, 0.98))


## A pair of big number plates (a label over a number), used for the key figures of a card. Returns nothing.
static func figure(hud: Hud, c: Control, r: Rect2, label: String, value: String, tint: Color, s: float, font: Font) -> void:
	c.draw_rect(r, Color(0.03, 0.04, 0.08, 0.85))
	c.draw_rect(Rect2(r.position.x, r.end.y - 3.0 * s, r.size.x, 3.0 * s), Color(tint, 0.85))
	var vsz := maxi(UiUtil.fit_size(font, value, r.size.x - 12.0 * s, int(44.0 * s)), int(Hud.BODY_MIN * s))
	hud._text(c, font, Vector2(r.position.x, r.position.y + r.size.y * 0.52), value, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, vsz, Color(1, 1, 1, 0.98))
	var lsz := int(Hud.BODY_MIN * s)
	hud._text(c, font, Vector2(r.position.x, r.position.y + r.size.y - 9.0 * s), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, lsz, Color(tint.lerp(Color.WHITE, 0.4), 0.92))


## The screen backdrop of a full-screen pause panel: the dim, a soft vignette strip at the top and the bottom so titles and the BACK row sit on calm ground.
static func backdrop(c: Control, vp: Vector2, s: float, dim: float) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, vp), Color(INK, dim))
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, 120.0 * s), Vector2(0, 120.0 * s)]), PackedColorArray([Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0)]))
	c.draw_polygon(PackedVector2Array([Vector2(0, vp.y - 110.0 * s), Vector2(vp.x, vp.y - 110.0 * s), Vector2(vp.x, vp.y), Vector2(0, vp.y)]), PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.45)]))


# --- icons --------------------------------------------------------------------------------------------------------------------------

## The icon set: the MenuKit glyphs plus the stat and thing icons below. Drawn in a circle of radius r about p.
static func glyph(c: Control, id: StringName, p: Vector2, r: float, col: Color, s: float) -> void:
	var w := maxf(2.0 * s, r * 0.16)
	match id:
		&"damage":                                          # a burst
			var pts := PackedVector2Array()
			for i in 12:
				var a := float(i) * TAU / 12.0
				pts.append(p + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.5))
			c.draw_colored_polygon(pts, col)
		&"rate":                                            # three bullets
			for i in 3:
				c.draw_rect(Rect2(p + Vector2(-r + float(i) * r * 0.75, -r * 0.7), Vector2(r * 0.45, r * 1.4)), col)
		&"range":                                           # a target with an arrow out
			c.draw_arc(p, r * 0.8, 0.0, TAU, 20, col, w)
			c.draw_circle(p, r * 0.25, col)
		&"accuracy":                                        # crosshair
			c.draw_arc(p, r * 0.7, 0.0, TAU, 20, col, w)
			c.draw_line(p + Vector2(-r, 0), p + Vector2(-r * 0.35, 0), col, w)
			c.draw_line(p + Vector2(r, 0), p + Vector2(r * 0.35, 0), col, w)
			c.draw_line(p + Vector2(0, -r), p + Vector2(0, -r * 0.35), col, w)
			c.draw_line(p + Vector2(0, r), p + Vector2(0, r * 0.35), col, w)
		&"control":                                         # a steady line with a dot
			c.draw_line(p + Vector2(-r, r * 0.4), p + Vector2(r, r * 0.4), col, w)
			c.draw_circle(p + Vector2(0, -r * 0.3), r * 0.4, col)
		&"penetration":                                     # an arrow through a plate
			c.draw_rect(Rect2(p + Vector2(-r * 0.1, -r), Vector2(r * 0.3, r * 2.0)), Color(col, 0.6))
			c.draw_line(p + Vector2(-r, 0), p + Vector2(r, 0), col, w * 1.3)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(r, 0), p + Vector2(r * 0.4, -r * 0.5), p + Vector2(r * 0.4, r * 0.5)]), col)
		&"heart":
			c.draw_circle(p + Vector2(-r * 0.4, -r * 0.25), r * 0.5, col)
			c.draw_circle(p + Vector2(r * 0.4, -r * 0.25), r * 0.5, col)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 0.88, -r * 0.05), p + Vector2(r * 0.88, -r * 0.05), p + Vector2(0, r)]), col)
		&"shield":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 0.8, -r * 0.8), p + Vector2(r * 0.8, -r * 0.8), p + Vector2(r * 0.8, r * 0.1), p + Vector2(0, r), p + Vector2(-r * 0.8, r * 0.1)]), col)
		&"bolt":
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(r * 0.2, -r), p + Vector2(-r * 0.6, r * 0.15), p + Vector2(-r * 0.05, r * 0.15), p + Vector2(-r * 0.2, r), p + Vector2(r * 0.6, -r * 0.2), p + Vector2(r * 0.05, -r * 0.2)]), col)
		&"coin":
			c.draw_circle(p, r, col)
			c.draw_circle(p, r * 0.6, Color(0, 0, 0, 0.45))
			c.draw_circle(p, r * 0.3, col)
		&"car":
			c.draw_rect(Rect2(p + Vector2(-r, -r * 0.1), Vector2(r * 2.0, r * 0.6)), col)
			c.draw_rect(Rect2(p + Vector2(-r * 0.55, -r * 0.6), Vector2(r * 1.1, r * 0.55)), col)
			c.draw_circle(p + Vector2(-r * 0.5, r * 0.55), r * 0.28, Color(0, 0, 0, 0.8))
			c.draw_circle(p + Vector2(r * 0.5, r * 0.55), r * 0.28, Color(0, 0, 0, 0.8))
		&"bomb":
			c.draw_circle(p + Vector2(0, r * 0.15), r * 0.75, col)
			c.draw_line(p + Vector2(r * 0.3, -r * 0.4), p + Vector2(r * 0.7, -r * 0.9), col, w)
		&"reload":
			c.draw_arc(p, r * 0.75, -0.3, TAU - 0.9, 18, col, w * 1.2)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(r * 0.9, -r * 0.1), p + Vector2(r * 0.4, -r * 0.55), p + Vector2(r * 0.35, r * 0.1)]), col)
		&"star":
			var sp := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + float(i) * PI / 5.0
				sp.append(p + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
			c.draw_colored_polygon(sp, col)
		&"rotate":
			c.draw_arc(p, r * 0.8, 0.4, PI - 0.4, 12, col, w)
			c.draw_arc(p, r * 0.8, PI + 0.4, TAU - 0.4, 12, col, w)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(r * 0.85, r * 0.2), p + Vector2(r * 0.45, -r * 0.1), p + Vector2(r * 1.0, -r * 0.2)]), col)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(-r * 0.85, -r * 0.2), p + Vector2(-r * 0.45, r * 0.1), p + Vector2(-r * 1.0, r * 0.2)]), col)
		_:
			MenuKit.glyph(c, id, p, r, col, s)
