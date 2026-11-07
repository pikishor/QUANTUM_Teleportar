class_name StoryView
extends Control
## Draws the story layer (cards, chapter banner, objective line, radio subtitle, death quote, chapter end card) for a Story. Thin-line HUD style, shares
## UiUtil (scale, safe-area insets, font, palette). Small flat rectangles and a few strings only: no full-screen overdraw (a card is one translucent band).
## Layout rules (phone readable, minimum 22 px at 720 p, 18 px when a long line must shrink): the HUD owns ONE priority line (contract, else core objective) under its
## bars; the story layer adds nothing to the top centre but the chapter banner. The radio subtitle is a narrow plate in the TOP-LEFT column right under the minimap
## (and the perf readout on phones, UiUtil.left_bottom): the text is measured and wrapped to the plate, shrinks to 18 px when it needs more than SUB_MAX_LINES lines, and
## shows whole words only, so a line is never cut mid-word. It never covers the hero, the crosshair or the touch buttons; the centre message of the HUD starts below the
## top stack (Hud.msg_top). The middle of the screen stays free except for the card band, which the player skips with a tap.

const SUB_W := 320.0                ## base px: the subtitle plate (narrow, top left)
const SUB_FONT := 22.0
const SUB_SMALL := 18.0             ## the font a long line shrinks to before the plate grows beyond SUB_MAX_LINES
const SUB_MAX_LINES := 5
const SUB_PLATE := [0.55, 0.84, 1.0]      ## plate opacity by the SUBTITLE BG setting (OFF-ish / DEFAULT / SOLID): never lighter than 0.55, so bright roofs and signs do not wash the text out
const TOUCH_BUTTONS_W := 700.0      ## base px from the right edge covered by the touch buttons (touch_controls.gd BUTTONS); the CALL CAR / ally column (need more_garage, more_companion) sits further out, only while MORE is open
const CARD_TOP := 0.40              ## the card band spans 40 % .. 70 % of the screen height: clear of the HUD bars (top) and the continue button (bottom)
const CARD_H := 0.30

var story: Story

var _q: Array = []
var _wrap_key := ""
var _wrap_lines := PackedStringArray()
var _fit_key := ""
var _fit_lines := PackedStringArray()
var _fit_size := 0


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


## Wraps `text` to `width`; when it needs more than `max_lines` lines at `big` it is re-wrapped at `small`. The chosen size is in `fit_size()`. Cached like wrapped_lines.
func fit_lines(text: String, width: float, big: int, small: int, max_lines: int) -> PackedStringArray:
	var key := "%s|%d|%d|%d|%d" % [text, int(width), big, small, max_lines]
	if key == _fit_key:
		return _fit_lines
	_fit_key = key
	_fit_size = big
	_fit_lines = wrap_text(UiUtil.font(), text, width, big)
	if _fit_lines.size() > max_lines and small < big:
		_fit_size = small
		_fit_lines = wrap_text(UiUtil.font(), text, width, small)
	return _fit_lines


## Wraps `text` at the text scale (Tr.text_scale) and shrinks the size, never below `floor_px`, until the block fits `max_h` tall: a long translated card or quote never runs off a 844x390 screen at 1.5x.
## Returns {size, step (line height px), lines}.
func scaled_block(text: String, width: float, base_px: float, floor_px: int, max_h: float) -> Dictionary:
	var size := maxi(int(round(base_px * Tr.text_scale)), floor_px)
	var lines := wrapped_lines(text, width, size)
	while size > floor_px and float(lines.size()) * float(size) * 1.36 > max_h:
		size -= 1
		lines = wrapped_lines(text, width, size)
	return {"size": size, "step": float(size) * 1.36, "lines": lines}


func fit_size() -> int:
	return _fit_size


## The largest font size from `size` down to `min_size` at which `text` fits `width` px (the smallest when none does).
static func fit_font(font: Font, text: String, width: float, size: int, min_size: int) -> int:
	while size > min_size and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		size -= 1
	return size


static func wrap_text(font: Font, text: String, width: float, size: int) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		while font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and word.length() > 1:      # one word wider than the plate: break it by characters
			var cut := word.length() - 1
			while cut > 1 and font.get_string_size(word.substr(0, cut), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
				cut -= 1
			if line != "":
				out.append(line)
				line = ""
			out.append(word.substr(0, cut))
			word = word.substr(cut)
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
				if story.banner_visible() and not _hud_has_step_line():       # the step line, compass and beacon already say what to do: a faded chapter banner under them was a pile (director review)
					_draw_banner(vp, s, font, ins)
				if story.line_visible():
					if UiSettings.s_subtitles:
						_draw_subtitle(vp, s, font, ins)
		&"dead":
			if not story.death_quote.is_empty():
				_draw_quote(vp, s, font)
		&"win":
			if story.cards_active():
				_draw_cards(vp, s, font)
			elif not story.end_card.is_empty():
				_draw_end_card(vp, s, font)


## True while the HUD shows a campaign step line (its plate would sit right where the chapter banner is drawn).
func _hud_has_step_line() -> bool:
	var h := get_tree().get_first_node_in_group(&"hud") as Hud
	return h != null and h.campaign_owns_goal() and h.has_step_line()


## The banner is a block of centred lines under the HUD stack on one plate, narrower than the screen by the subtitle column on each side; lines shrink to fit.
func _draw_banner(vp: Vector2, s: float, font: Font, ins: Vector2) -> void:
	var t := story.banner_t
	var a := clampf(minf(t / 0.4, (Story.BANNER_TIME - t) / 0.7), 0.0, 1.0)
	var d := story.chapter_data()
	var cx := vp.x * 0.5
	var y0 := (UiUtil.stack_bottom + 6.0) * s
	var bw := clampf(vp.x - 2.0 * (ins.x + (SUB_W + 34.0) * s), 300.0 * s, 760.0 * s)
	var x0 := cx - bw * 0.5
	var inner := bw - 24.0 * s
	var short := UiSettings.s_chatter < 2                          # LOW / OFF story chatter: chapter and title only (the objective line is on the HUD already)
	draw_rect(Rect2(x0, y0, bw, (80.0 if short else 128.0) * s), Color(UiUtil.PLATE, UiUtil.PLATE.a * a))
	_shadow_text(font, Vector2(x0, y0 + 24.0 * s), story.chapter_label(), HORIZONTAL_ALIGNMENT_CENTER, bw, int(20.0 * s), Color(UiUtil.CYAN, 0.95 * a), s)
	var title := Tr.t(str(d["title"]))
	_shadow_text(font, Vector2(x0, y0 + 64.0 * s), title, HORIZONTAL_ALIGNMENT_CENTER, bw, fit_font(font, title, inner, int(40.0 * s), int(24.0 * s)), Color(1, 1, 1, 0.97 * a), 2.0 * s)
	draw_line(Vector2(cx - 110.0 * s, y0 + 72.0 * s), Vector2(cx + 110.0 * s, y0 + 72.0 * s), Color(UiUtil.MAGENTA, 0.8 * a), 2.0 * s)
	if short:
		return
	var sub := Tr.t(str(d["sub"]))
	var obj := Tr.t("OBJ  ") + Tr.t(str(d["obj"]))
	_shadow_text(font, Vector2(x0, y0 + 96.0 * s), sub, HORIZONTAL_ALIGNMENT_CENTER, bw, fit_font(font, sub, inner, int(UiUtil.TEXT_MIN * s), int(15.0 * s)), Color(1, 1, 1, 0.88 * a), s)
	_shadow_text(font, Vector2(x0, y0 + 120.0 * s), obj, HORIZONTAL_ALIGNMENT_CENTER, bw, fit_font(font, obj, inner, int(UiUtil.TEXT_MIN * s), int(15.0 * s)), Color(UiUtil.AMBER, 0.95 * a), s)


## Where the radio subtitle plate sits and what it holds for the current line: {box, lines, fsize, lh}. The box starts under the HUD's top-left column (UiUtil.left_bottom:
## the minimap, the perf readout on phones), so it can never overlap the minimap.
func _sub_layout(vp: Vector2, s: float, ins: Vector2) -> Dictionary:
	var zoom := UiSettings.s_sub_size
	var width := minf(SUB_W * s * zoom, vp.x * (0.36 if zoom <= 1.0 else 0.5))
	var full := story.display_text()
	var lines: PackedStringArray = fit_lines(full, width - 26.0 * s, int(SUB_FONT * s * zoom * Tr.text_scale), int(SUB_SMALL * s * zoom), SUB_MAX_LINES if UiSettings.s_chatter >= 2 else 2)
	if UiSettings.s_chatter < 2 and lines.size() > 2:
		lines = lines.slice(0, 2)                                       # LOW / OFF story chatter: two lines at most (Story.shorten() keeps the line to one sentence of at most MAX_SHORT characters, which fits two lines at the small font)
	var fsize := _fit_size
	var lh := float(fsize) * 1.28
	var h: float = float(lines.size()) * lh + 32.0 * s
	return {"box": Rect2(ins.x + 16.0 * s, (UiUtil.left_bottom + 8.0) * s, width, h), "lines": lines, "fsize": fsize, "lh": lh}


## The plate rect of the current radio line for a viewport (Rect2() when no line shows). For layout tests.
func subtitle_rect(vp: Vector2) -> Rect2:
	if story == null or story.current.is_empty():
		return Rect2()
	var s := UiUtil.ui_scale(vp)
	return _sub_layout(vp, s, UiUtil.insets(vp))["box"]


## The radio subtitle: a narrow plate in the top-left column under the minimap, speaker name over the wrapped lines, whole words revealed as the line types.
func _draw_subtitle(vp: Vector2, s: float, font: Font, ins: Vector2) -> void:
	var lay := _sub_layout(vp, s, ins)
	var lines: PackedStringArray = lay["lines"]
	var fsize: int = lay["fsize"]
	var lh: float = lay["lh"]
	var zoom := UiSettings.s_sub_size
	var box: Rect2 = lay["box"]
	var a := story.line_alpha()
	var speaker := str(story.current.get("s", ""))
	var col := speaker_color(speaker)
	draw_rect(box.grow(5.0 * s), Color(UiUtil.PLATE, 0.28 * a))                  # a soft backing around the plate: a lit sign or a bright roof never touches the text
	draw_rect(box, Color(UiUtil.PLATE, SUB_PLATE[clampi(UiSettings.s_sub_bg, 0, 2)] * a))
	draw_rect(Rect2(box.position, Vector2(3.0 * s, box.size.y)), Color(col, 0.9 * a))
	_shadow_text(font, box.position + Vector2(14.0 * s, 20.0 * s), Tr.t(speaker), HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(18.0 * s * zoom), Color(col, 0.98 * a), s)
	var left_chars := int(story.typed)
	var y := box.position.y + 20.0 * s + lh
	for ln: String in lines:
		if left_chars <= 0:
			break
		var part := ln
		if left_chars < ln.length():
			var e := ln.find(" ", left_chars)                  # finish the word being typed: never a half word
			part = ln.substr(0, e if e >= 0 else ln.length())
		_shadow_text(font, Vector2(box.position.x + 14.0 * s, y), part, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize, Color(1, 1, 1, 0.97 * a), s)
		left_chars -= ln.length() + 1
		y += lh


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
	var blk := scaled_block(str(card["text"]), width, 22.0 * s, 11, h - 64.0 * s - 22.0 * s)
	var fsize: int = blk["size"]
	var step: float = blk["step"]
	var lines: PackedStringArray = blk["lines"]
	var left_chars := int(story.card_typed)
	var y := y0 + 64.0 * s
	for ln: String in lines:
		var part: String = ln.substr(0, left_chars)
		if part != "":
			_shadow_text(font, Vector2(x0, y), part, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsize, Color(1, 1, 1, 0.97), s)
		left_chars -= ln.length() + 1
		y += step
		if left_chars <= 0:
			break
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.005)
	var typing := story.card_typed < str(card["text"]).length()
	_shadow_text(font, Vector2(x0, band.end.y - 12.0 * s), Tr.t("TAP TO SKIP" if typing else "TAP TO CONTINUE"), HORIZONTAL_ALIGNMENT_RIGHT, width, int(12.0 * s), Color(1, 1, 1, pulse * 0.8), s)


## Death quote on the DECOHERED screen: a thin band between the score lines and the RESPAWN button, the world stays visible around it.
func _draw_quote(vp: Vector2, s: float, font: Font) -> void:
	var a := clampf((story.death_age - Story.DEATH_DELAY) / 0.5, 0.0, 1.0)
	if a <= 0.0:
		return
	var q := story.death_quote
	var speaker := str(q["s"])
	var col := speaker_color(speaker)
	var width := minf(vp.x * 0.8, 760.0 * s)
	var blk := scaled_block("“" + str(q["t"]) + "”", width, 20.0 * s, 11, vp.y - 296.0 * s - 40.0 * s - 8.0 * s)
	var fsize: int = blk["size"]
	var step: float = blk["step"]
	var lines: PackedStringArray = blk["lines"]
	var h: float = lines.size() * step + 40.0 * s
	var box := Rect2((vp.x - width) * 0.5 - 16.0 * s, 296.0 * s, width + 32.0 * s, h)
	draw_rect(box, Color(0.0, 0.0, 0.0, 0.42 * a))
	_shadow_text(font, Vector2(0.0, box.position.y + 22.0 * s), Tr.t(speaker), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(13.0 * s), Color(col, 0.95 * a), s)
	var y := box.position.y + 22.0 * s + step
	for ln: String in lines:
		_shadow_text(font, Vector2(0.0, y), ln, HORIZONTAL_ALIGNMENT_CENTER, vp.x, fsize, Color(1, 1, 1, 0.96 * a), s)
		y += step


## Chapter end card on the SECTOR STABILIZED screen, same band as the death quote.
func _draw_end_card(vp: Vector2, s: float, font: Font) -> void:
	var a := clampf(story.end_age / 0.5, 0.0, 1.0)
	var c := story.end_card
	var width := minf(vp.x * 0.8, 800.0 * s)
	var blk := scaled_block(str(c["text"]), width, 19.0 * s, 11, vp.y - 296.0 * s - 40.0 * s - 8.0 * s)
	var fsize: int = blk["size"]
	var step: float = blk["step"]
	var lines: PackedStringArray = blk["lines"]
	var h: float = lines.size() * step + 40.0 * s
	var box := Rect2((vp.x - width) * 0.5 - 16.0 * s, 296.0 * s, width + 32.0 * s, h)
	draw_rect(box, Color(0.0, 0.0, 0.0, 0.42 * a))
	_shadow_text(font, Vector2(0.0, box.position.y + 22.0 * s), str(c["head"]), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(13.0 * s), Color(UiUtil.CYAN, 0.95 * a), s)
	var y := box.position.y + 22.0 * s + step
	for ln: String in lines:
		_shadow_text(font, Vector2(0.0, y), ln, HORIZONTAL_ALIGNMENT_CENTER, vp.x, fsize, Color(1, 1, 1, 0.96 * a), s)
		y += step
