class_name StoryView
extends Control
## Draws the story layer (cards, chapter banner, objective line, radio subtitle, death quote, chapter end card) for a Story. Thin-line HUD style, shares
## UiUtil (scale, safe-area insets, font, palette). Small flat rectangles and a few strings only: no full-screen overdraw (a card is one translucent band).
## Layout rules: the radio subtitle sits bottom centre above the ammo box and the ability hints, and on touchscreens stops left of the touch buttons;
## the middle of the screen (crosshair) stays free except for the card band, which the player skips with a tap.

const SUB_BOTTOM := 108.0           ## base px above the bottom edge: clears the ammo box and the power hints
const SUB_FONT := 17.0
const TOUCH_BUTTONS_W := 592.0      ## base px from the right edge covered by the touch buttons (touch_controls.gd BUTTONS)
const CARD_TOP := 0.40              ## the card band spans 40 % .. 70 % of the screen height: clear of the HUD bars (top) and the continue button (bottom)
const CARD_H := 0.30

var story: Story

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


func _shadow_text(font: Font, pos: Vector2, text: String, align: HorizontalAlignment, width: float, size: int, col: Color, s: float) -> void:
	draw_string(font, pos + Vector2(1.5, 1.5) * s, text, align, width, size, Color(0, 0, 0, col.a * 0.85))
	draw_string(font, pos, text, align, width, size, col)


func _draw() -> void:
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
		_shadow_text(font, Vector2(0.0, 112.0 * s), "OBJ  " + t, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(13.0 * s), Color(1, 1, 1, 0.7), s)


func _draw_banner(vp: Vector2, s: float, font: Font) -> void:
	var t := story.banner_t
	var a := clampf(minf(t / 0.4, (Story.BANNER_TIME - t) / 0.7), 0.0, 1.0)
	var d := story.chapter_data()
	var cx := vp.x * 0.5
	_shadow_text(font, Vector2(0.0, 138.0 * s), story.chapter_label(), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(14.0 * s), Color(UiUtil.CYAN, 0.9 * a), s)
	_shadow_text(font, Vector2(0.0, 172.0 * s), str(d["title"]), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(42.0 * s), Color(1, 1, 1, 0.97 * a), 2.0 * s)
	draw_line(Vector2(cx - 110.0 * s, 182.0 * s), Vector2(cx + 110.0 * s, 182.0 * s), Color(UiUtil.MAGENTA, 0.8 * a), 2.0 * s)
	_shadow_text(font, Vector2(0.0, 202.0 * s), str(d["sub"]), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(14.0 * s), Color(1, 1, 1, 0.8 * a), s)
	_shadow_text(font, Vector2(0.0, 224.0 * s), "OBJ  " + str(d["obj"]), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(15.0 * s), Color(UiUtil.AMBER, 0.9 * a), s)


## The subtitle block: speaker name over up to four typed lines, bottom centre.
func _draw_subtitle(vp: Vector2, s: float, font: Font, ins: Vector2) -> void:
	var left := ins.x + 20.0 * s
	var right := vp.x - ins.y - 20.0 * s
	if Game.force_touch or DisplayServer.is_touchscreen_available():
		right = minf(right, vp.x - ins.y - TOUCH_BUTTONS_W * s)
	right = maxf(right, left + 340.0 * s)
	var cx := (left + right) * 0.5
	var width := minf(right - left, 760.0 * s)
	var fsize := int(SUB_FONT * s)
	var full := str(story.current.get("t", ""))
	var lines: PackedStringArray = wrapped_lines(full, width - 24.0 * s, fsize)
	var lh := 22.0 * s
	var h: float = (lines.size() * lh) + 34.0 * s
	var box := Rect2(cx - width * 0.5, vp.y - SUB_BOTTOM * s - h, width, h)
	var a := story.line_alpha()
	var speaker := str(story.current.get("s", ""))
	var col := speaker_color(speaker)
	draw_rect(box, Color(0.0, 0.03, 0.05, 0.55 * a))
	draw_rect(Rect2(box.position, Vector2(3.0 * s, box.size.y)), Color(col, 0.9 * a))
	_shadow_text(font, box.position + Vector2(14.0 * s, 17.0 * s), speaker, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(12.0 * s), Color(col, 0.95 * a), s)
	var left_chars := int(story.typed)
	var y := box.position.y + 17.0 * s + lh
	for ln: String in lines:
		var part: String = ln.substr(0, left_chars)
		if part != "":
			_shadow_text(font, Vector2(box.position.x + 14.0 * s, y), part, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize, Color(1, 1, 1, 0.96 * a), s)
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
