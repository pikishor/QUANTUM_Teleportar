class_name StoryView
extends Control
## Draws the story layer (cards, chapter banner, objective line, radio subtitle, death quote, chapter end card) for a Story. Thin-line HUD style, shares
## UiUtil (scale, safe-area insets, font, palette). Small flat rectangles and a few strings only: no full-screen overdraw (a card is one translucent band).
## Layout rules (phone readable, minimum 22 px at 720 p): the radio subtitle and the chapter objective sit in the TOP lane, on backing plates directly under the
## HUD's bar / objective stack (UiUtil.stack_bottom), so they never cover the hero or the crosshair and never collide with the HUD objective line; the centre
## message of the HUD starts below that lane (Hud.MSG_Y). While the chapter banner owns the top lane the subtitle drops to the bottom lane (above the ammo box,
## left of the touch buttons). The middle of the screen stays free except for the card band, which the player skips with a tap.

const SUB_BOTTOM := 130.0           ## base px above the bottom edge of the bottom-lane fallback: clears the ammo box and the power hints
const SUB_FONT := 22.0
const SUB_LINE := 28.0
const OBJ_H := 32.0                 ## base px: the chapter objective plate
const TOUCH_BUTTONS_W := 592.0      ## base px from the right edge covered by the touch buttons (touch_controls.gd BUTTONS)
const CARD_TOP := 0.40              ## the card band spans 40 % .. 70 % of the screen height: clear of the HUD bars (top) and the continue button (bottom)
const CARD_H := 0.30

var story: Story

var _q: Array = []
var _wrap_key := ""
var _wrap_lines := PackedStringArray()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


static func speaker_color(speaker: String) -> Color:
	match speaker:
		"ORACLE":
			return UiUtil.CYAN
		"KESTREL":
			return UiUtil.AMBER
	return UiUtil.RED


## Word-wraps `text` to `width` px at `size`, cached by (text, width, size) so a typed line does not re-flow while it grows.
func wrapped_lines(text: String, width: float, size: int) -> PackedStringArray:
	var key := "%s|%d|%d" % [text, int(width), size]
	if key == _wrap_key:
		return _wrap_lines
	_wrap_key = key
	_wrap_lines = wrap_text(UiUtil.font(), text, width, size)
	return _wrap_lines


static func wrap_text(font: Font, text: String, width: float, size: int) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		var trial := word if line == "" else line + " " + word
		if line != "" and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			out.append(line)
			line = word
		else:
			line = trial
	if line != "":
		out.append(line)
	return out


## Text is queued and flushed after every plate and shape, one font size at a time (glyph and plain draws alternating would break canvas batching).
func _shadow_text(font: Font, pos: Vector2, text: String, align: HorizontalAlignment, width: float, size: int, col: Color, s: float) -> void:
	_q.append([font, pos, text, align, width, size, col, 1.5 * s])


func _flush_text() -> void:
	var sizes := {}
	for q: Array in _q:
		sizes[q[5]] = true
	for sz: int in sizes.keys():
		for q: Array in _q:
			if q[5] == sz:
				draw_string(q[0], (q[1] as Vector2) + Vector2(q[7], q[7]), q[2], q[3], q[4], q[5], Color(0, 0, 0, (q[6] as Color).a * 0.85))
		for q: Array in _q:
			if q[5] == sz:
				draw_string(q[0], q[1], q[2], q[3], q[4], q[5], q[6])
	_q.clear()


func _draw() -> void:
	_draw_layer()
	_flush_text()


func _draw_layer() -> void:
	if story == null:
		return
	var vp := size
	var s := UiUtil.ui_scale(vp)
	var font := UiUtil.font()
	var ins := UiUtil.insets(vp)
	match Game.state:
		&"play":
			if story.cards_active():
				_draw_cards(vp, s, font)
			else:
				if story.banner_visible():
					_draw_banner(vp, s, font)
				elif is_instance_valid(Game.player):
					_draw_objective(vp, s, font)
				if story.line_visible():
					_draw_subtitle(vp, s, font, ins)
		&"dead":
			if not story.death_quote.is_empty():
				_draw_quote(vp, s, font)
		&"win":
			if story.cards_active():
				_draw_cards(vp, s, font)
			elif not story.end_card.is_empty():
				_draw_end_card(vp, s, font)


func _draw_objective(vp: Vector2, s: float, font: Font) -> void:
	var t := story.objective_text()
	if t != "":
		var size := int(UiUtil.TEXT_MIN * s)
		var line := "OBJ  " + t
		var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 32.0 * s
		var r := Rect2((vp.x - w) * 0.5, (UiUtil.stack_bottom + 4.0) * s, w, OBJ_H * s)
		draw_rect(r, UiUtil.PLATE)
		draw_rect(Rect2(r.position.x, r.end.y - 2.0 * s, r.size.x, 2.0 * s), Color(UiUtil.AMBER, 0.55))
		_shadow_text(font, Vector2(r.position.x, r.position.y + OBJ_H * 0.76 * s), line, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(1, 1, 1, 0.95), s)


## The banner is a block of centred lines under the HUD stack on one plate.
func _draw_banner(vp: Vector2, s: float, font: Font) -> void:
	var t := story.banner_t
	var a := clampf(minf(t / 0.4, (Story.BANNER_TIME - t) / 0.7), 0.0, 1.0)
	var d := story.chapter_data()
	var cx := vp.x * 0.5
	var y0 := (UiUtil.stack_bottom + 6.0) * s
	var bw := minf(vp.x * 0.62, 760.0 * s)
	draw_rect(Rect2(cx - bw * 0.5, y0, bw, 128.0 * s), Color(UiUtil.PLATE, UiUtil.PLATE.a * a))
	_shadow_text(font, Vector2(0.0, y0 + 24.0 * s), story.chapter_label(), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(20.0 * s), Color(UiUtil.CYAN, 0.95 * a), s)
	_shadow_text(font, Vector2(0.0, y0 + 64.0 * s), str(d["title"]), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(40.0 * s), Color(1, 1, 1, 0.97 * a), 2.0 * s)
	draw_line(Vector2(cx - 110.0 * s, y0 + 72.0 * s), Vector2(cx + 110.0 * s, y0 + 72.0 * s), Color(UiUtil.MAGENTA, 0.8 * a), 2.0 * s)
	_shadow_text(font, Vector2(0.0, y0 + 96.0 * s), str(d["sub"]), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(1, 1, 1, 0.88 * a), s)
	_shadow_text(font, Vector2(0.0, y0 + 120.0 * s), "OBJ  " + str(d["obj"]), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.95 * a), s)


## The subtitle block: speaker name over up to four typed lines on a plate. Top lane under the objective; bottom lane while the chapter banner shows.
func _draw_subtitle(vp: Vector2, s: float, font: Font, ins: Vector2) -> void:
	var top_lane := not story.banner_visible()
	var left := ins.x + 20.0 * s
	var right := vp.x - ins.y - 20.0 * s
	if top_lane:
		left = ins.x + 230.0 * s                    # clear of the minimap and the credits / heat plate
		right = vp.x - ins.y - 200.0 * s
	elif Game.force_touch or DisplayServer.is_touchscreen_available():
		right = minf(right, vp.x - ins.y - TOUCH_BUTTONS_W * s)
	right = maxf(right, left + 340.0 * s)
	var cx := (left + right) * 0.5
	if top_lane:
		cx = vp.x * 0.5                             # centred under the objective (the lane is symmetric apart from the notch insets)
	var width := minf(right - left, 700.0 * s)
	var fsize := int(SUB_FONT * s)
	var full := str(story.current.get("t", ""))
	var lines: PackedStringArray = wrapped_lines(full, width - 28.0 * s, fsize)
	var lh := SUB_LINE * s
	var h: float = (lines.size() * lh) + 36.0 * s
	var y_top := (UiUtil.stack_bottom + 4.0 + (OBJ_H + 4.0 if story.objective_text() != "" else 0.0)) * s
	if not top_lane:
		y_top = vp.y - UiUtil.insets_v(vp).y - SUB_BOTTOM * s - h
	var box := Rect2(cx - width * 0.5, y_top, width, h)
	var a := story.line_alpha()
	var speaker := str(story.current.get("s", ""))
	var col := speaker_color(speaker)
	draw_rect(box, Color(UiUtil.PLATE, 0.72 * a))
	draw_rect(Rect2(box.position, Vector2(3.0 * s, box.size.y)), Color(col, 0.9 * a))
	_shadow_text(font, box.position + Vector2(14.0 * s, 20.0 * s), speaker, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(18.0 * s), Color(col, 0.98 * a), s)
	var left_chars := int(story.typed)
	var y := box.position.y + 20.0 * s + lh
	for ln: String in lines:
		var part: String = ln.substr(0, left_chars)
		if part != "":
			_shadow_text(font, Vector2(box.position.x + 14.0 * s, y), part, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize, Color(1, 1, 1, 0.97 * a), s)
		left_chars -= ln.length() + 1
		y += lh
		if left_chars <= 0:
			break


func _draw_cards(vp: Vector2, s: float, font: Font) -> void:
	var y0 := vp.y * CARD_TOP
	var h := vp.y * CARD_H
	var band := Rect2(0.0, y0, vp.x, h)
	draw_rect(band, Color(0.0, 0.02, 0.04, 0.68))
	draw_line(band.position, band.position + Vector2(vp.x, 0.0), Color(UiUtil.CYAN, 0.45), 1.0 * s)
	draw_line(band.end - Vector2(vp.x, 0.0), band.end, Color(UiUtil.CYAN, 0.45), 1.0 * s)
	var card: Dictionary = story.cards[0]
	var width := minf(vp.x * 0.84, 880.0 * s)
	var x0 := (vp.x - width) * 0.5
	_shadow_text(font, Vector2(x0, y0 + 30.0 * s), str(card["head"]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(14.0 * s), Color(UiUtil.CYAN, 0.95), s)
	var fsize := int(22.0 * s)
	var lines: PackedStringArray = wrapped_lines(str(card["text"]), width, fsize)
	var left_chars := int(story.card_typed)
	var y := y0 + 64.0 * s
	for ln: String in lines:
		var part: String = ln.substr(0, left_chars)
		if part != "":
			_shadow_text(font, Vector2(x0, y), part, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize, Color(1, 1, 1, 0.97), s)
		left_chars -= ln.length() + 1
		y += 30.0 * s
		if left_chars <= 0:
			break
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.005)
	var typing := story.card_typed < str(card["text"]).length()
	_shadow_text(font, Vector2(x0, band.end.y - 12.0 * s), "TAP TO SKIP" if typing else "TAP TO CONTINUE", HORIZONTAL_ALIGNMENT_RIGHT, width, int(12.0 * s), Color(1, 1, 1, pulse * 0.8), s)


## Death quote on the DECOHERED screen: a thin band between the score lines and the RESPAWN button, the world stays visible around it.
func _draw_quote(vp: Vector2, s: float, font: Font) -> void:
	var a := clampf((story.death_age - Story.DEATH_DELAY) / 0.5, 0.0, 1.0)
	if a <= 0.0:
		return
	var q := story.death_quote
	var speaker := str(q["s"])
	var col := speaker_color(speaker)
	var width := minf(vp.x * 0.8, 760.0 * s)
	var fsize := int(20.0 * s)
	var lines: PackedStringArray = wrapped_lines("“" + str(q["t"]) + "”", width, fsize)
	var h: float = lines.size() * 28.0 * s + 40.0 * s
	var box := Rect2((vp.x - width) * 0.5 - 16.0 * s, 296.0 * s, width + 32.0 * s, h)
	draw_rect(box, Color(0.0, 0.0, 0.0, 0.42 * a))
	_shadow_text(font, Vector2(0.0, box.position.y + 22.0 * s), speaker, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(13.0 * s), Color(col, 0.95 * a), s)
	var y := box.position.y + 22.0 * s + 28.0 * s
	for ln: String in lines:
		_shadow_text(font, Vector2(0.0, y), ln, HORIZONTAL_ALIGNMENT_CENTER, vp.x, fsize, Color(1, 1, 1, 0.96 * a), s)
		y += 28.0 * s


## Chapter end card on the SECTOR STABILIZED screen, same band as the death quote.
func _draw_end_card(vp: Vector2, s: float, font: Font) -> void:
	var a := clampf(story.end_age / 0.5, 0.0, 1.0)
	var c := story.end_card
	var width := minf(vp.x * 0.8, 800.0 * s)
	var fsize := int(19.0 * s)
	var lines: PackedStringArray = wrapped_lines(str(c["text"]), width, fsize)
	var h: float = lines.size() * 27.0 * s + 40.0 * s
	var box := Rect2((vp.x - width) * 0.5 - 16.0 * s, 296.0 * s, width + 32.0 * s, h)
	draw_rect(box, Color(0.0, 0.0, 0.0, 0.42 * a))
	_shadow_text(font, Vector2(0.0, box.position.y + 22.0 * s), str(c["head"]), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(13.0 * s), Color(UiUtil.CYAN, 0.95 * a), s)
	var y := box.position.y + 22.0 * s + 27.0 * s
	for ln: String in lines:
		_shadow_text(font, Vector2(0.0, y), ln, HORIZONTAL_ALIGNMENT_CENTER, vp.x, fsize, Color(1, 1, 1, 0.96 * a), s)
		y += 27.0 * s
