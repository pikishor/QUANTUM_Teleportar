class_name LookScreen
extends RefCounted
## The SUIT screen (Hud draws it on the pause shop when `_look_open`; `_shop_open` stays true). Wave 112 layout: on the left the hero himself, live in 3D on a turntable (HeroShowcase: drag
## turns him, a tap swings him back to the front); on the right the six suit cards (a picture, the name, EQUIP / ON / BUY price / LOCKED and what unlocks it), the colour scheme chips, the
## twelve accent swatches and one row with the person (body, skin, hair, beard), the accent picker purchase and BACK.
## Buttons: `look_suit_<id>`, `look_scheme_<i>`, `look_hue_<i>` (`look_hue_buy` buys the picker), `look_person_<body|skin|hair|beard>`, `look_back`. Every suit card, scheme chip and swatch is
## painted by draw() itself (`own` buttons: the hud only adds the controller focus ring). Numbers and rules come from HeroLook, purchases from Progress.buy_look().

const BTN_H := 64.0
const GAP := 8.0
## the hero column (left) and the controls column (right): base px from the screen centre, the layout is 1248 px wide and needs the 16:9 width of 1280
const SHOW_X := -624.0
const SHOW_W := 312.0
const SHOW_Y := 148.0
const SHOW_H := 498.0
const RX := -296.0                  ## left edge of the controls column
const RW := 920.0                   ## its width (right edge 624)
const CARD_Y := 148.0               ## the suit cards: 3 columns x 2 rows
const CARD_H := 104.0
const CARD_COLS := 3
const SCHEME_CAP_Y := 390.0         ## baseline of the SCHEME caption
const SCHEME_Y := 396.0             ## the eight scheme chips
const HUE_CAP_Y := 484.0
const HUE_Y := 490.0                ## the twelve 64 px accent swatches
const HUE_SIZE := 64.0
const HUE_GAP := 8.0
const FOOT_CAP_Y := 578.0
const FOOT_Y := 582.0               ## person buttons, ACCENT BUY and BACK
## The person (HeroCharacter): four 64 px buttons that cycle the body, the skin tone, the hair style and the beard.
const PERSON: Array[String] = ["body", "skin", "hair", "beard"]
const PERSON_W := 140.0
const BUY_X := 592.0
const BUY_W := 170.0
const BACK_X := 770.0
const BACK_W := 150.0


static func _cos() -> Array:
	var p := Game.progress as Progress
	return p.achievements.cosmetics if p != null else []


static func label_for(key: String, equipped: bool) -> String:
	var p := Game.progress as Progress
	if p == null:
		return "-"
	if equipped:
		return "ON"
	if p.hero.is_unlocked(key, _cos()):
		return "EQUIP"
	if HeroLook.item_need(key) != "":
		return "LOCKED"
	return "BUY  %d" % HeroLook.item_price(key)


static func showcase_rect(cx: float, s: float) -> Rect2:
	return Rect2(cx + SHOW_X * s, SHOW_Y * s, SHOW_W * s, SHOW_H * s)


static func suit_rect(i: int, cx: float, s: float) -> Rect2:
	var w := (RW - float(CARD_COLS - 1) * GAP) / float(CARD_COLS)
	return Rect2(cx + (RX + float(i % CARD_COLS) * (w + GAP)) * s, (CARD_Y + float(i / CARD_COLS) * (CARD_H + GAP)) * s, w * s, CARD_H * s)


static func scheme_rect(i: int, cx: float, s: float) -> Rect2:
	var n := HeroLook.SCHEMES.size()
	var w := (RW - float(n - 1) * GAP) / float(n)
	return Rect2(cx + (RX + float(i) * (w + GAP)) * s, SCHEME_Y * s, w * s, BTN_H * s)


static func hue_rect(i: int, cx: float, s: float) -> Rect2:
	return Rect2(cx + (RX + float(i) * (HUE_SIZE + HUE_GAP)) * s, HUE_Y * s, HUE_SIZE * s, HUE_SIZE * s)


static func person_rect(i: int, cx: float, s: float) -> Rect2:
	return Rect2(cx + (RX + float(i) * (PERSON_W + GAP)) * s, FOOT_Y * s, PERSON_W * s, BTN_H * s)


static func person_label(h: HeroLook, what: String) -> String:
	match what:
		"body":
			return "BODY  %s" % String(h.body).to_upper()
		"skin":
			return "SKIN  %s" % String(h.skin_tone).to_upper()
		"hair":
			return "HAIR  %s" % String(h.hair).to_upper()
		_:
			return "NO BEARD" if h.body == &"female" else ("BEARD  ON" if h.beard else "BEARD  OFF")


## A press of a person button: the next value of the option. False when it cannot change (the beard of the female body).
static func press_person(h: HeroLook, what: String) -> bool:
	match what:
		"body":
			return h.set_person("body", &"female" if h.body == &"male" else &"male")
		"skin":
			return h.set_person("skin", &"light" if h.skin_tone == &"dark" else &"dark")
		"hair":
			var i := HeroCharacter.HAIRS.find(h.hair)
			return h.set_person("hair", HeroCharacter.HAIRS[(i + 1) % HeroCharacter.HAIRS.size()])
		"beard":
			return h.set_person("beard")
	return false


static func layout(hud: Hud, cx: float, s: float) -> void:
	var p := Game.progress as Progress
	if p == null:
		return
	var h := p.hero
	for i in HeroLook.SUIT_ORDER.size():
		var id := HeroLook.SUIT_ORDER[i]
		hud._add(StringName("look_suit_%s" % id), suit_rect(i, cx, s), label_for("suit:%s" % id, h.suit == id), h.suit == id)
		hud.buttons[hud.buttons.size() - 1]["own"] = true                                  # the card is painted by draw() below
	for i in HeroLook.SCHEMES.size():
		var on := h.scheme == i and h.accent_hue < 0
		hud._add(StringName("look_scheme_%d" % i), scheme_rect(i, cx, s), label_for("scheme:%d" % i, on), on)
		hud.buttons[hud.buttons.size() - 1]["own"] = true
	for i in HeroLook.HUES:
		hud._add(StringName("look_hue_%d" % i), hue_rect(i, cx, s), "", h.accent_hue == i)
		hud.buttons[hud.buttons.size() - 1]["own"] = true
	for i in PERSON.size():
		hud._add(StringName("look_person_%s" % PERSON[i]), person_rect(i, cx, s), person_label(h, PERSON[i]), PERSON[i] == "beard" and h.beard)
	hud._add(&"look_hue_buy", Rect2(cx + (RX + BUY_X) * s, FOOT_Y * s, BUY_W * s, BTN_H * s), "ACCENT  OWNED" if h.owned.has("accent") else "ACCENT  BUY  %d" % Economy.accent_price(), h.owned.has("accent"))
	hud._add(&"look_back", Rect2(cx + (RX + BACK_X) * s, FOOT_Y * s, BACK_W * s, BTN_H * s), "BACK", false)


## Every caption of the screen as {t, x, y (baseline), w, col}: each sits in the band above its own row, a test checks that none reaches a button (or another caption).
static func captions(cx: float, s: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var x0 := cx + RX * s
	var p := Game.progress as Progress
	var sch := "SCHEME"
	if p != null and p.hero.accent_hue < 0:
		sch = "SCHEME  %s" % String(HeroLook.SCHEMES[p.hero.scheme][0])
	elif p != null:
		sch = "SCHEME  CUSTOM"
	out.append({"t": sch, "x": x0, "y": SCHEME_CAP_Y * s, "w": 440.0 * s, "col": UiUtil.CYAN})
	out.append({"t": "ACCENT", "x": x0, "y": HUE_CAP_Y * s, "w": 300.0 * s, "col": UiUtil.CYAN})
	out.append({"t": "PERSON", "x": x0, "y": FOOT_CAP_Y * s, "w": 300.0 * s, "col": UiUtil.CYAN})
	return out


# --- drawing ---------------------------------------------------------------------------------------------------------------------------

## The short line under a suit's name on its card.
static func suit_tag(id: StringName) -> String:
	return String(HeroLook.SUITS[id].get("tag", ""))


## What unlocks a locked item, without the achievement's title ("Reach chapter 5").
static func hint_of(key: String) -> String:
	var t := HeroLook.unlock_hint(key)
	var k := t.find(": ")
	return t.substr(k + 2) if k >= 0 else t


static func _state_color(label: String) -> Color:
	if label == "ON":
		return UiUtil.GREEN
	if label == "EQUIP":
		return UiUtil.CYAN
	if label == "LOCKED":
		return UiUtil.RED
	return UiUtil.AMBER


static func _lock(c: Control, at: Vector2, k: float, col: Color) -> void:
	c.draw_arc(at + Vector2(0.0, -4.0 * k), 5.0 * k, PI, TAU, 10, col, 2.0 * k)
	c.draw_rect(Rect2(at + Vector2(-7.0 * k, -4.0 * k), Vector2(14.0 * k, 11.0 * k)), col)


static func _draw_suit_card(hud: Hud, c: Control, r: Rect2, id: StringName, h: HeroLook, s: float, font: Font) -> void:
	var key := "suit:%s" % id
	var unlocked := h.is_unlocked(key, _cos())
	var on := h.suit == id
	var hot := hud._hover == StringName("look_suit_%s" % id)
	var label := label_for(key, on)
	var tint := UiUtil.GREEN if on else (UiUtil.CYAN if unlocked else (UiUtil.AMBER if HeroLook.item_need(key) == "" else Color(UiUtil.RED, 0.9)))
	UiKit.panel(c, r, s, tint, on or hot, 10.0, on)
	var th := Rect2(r.position.x + 7.0 * s, r.position.y + 7.0 * s, 78.0 * s, r.size.y - 14.0 * s)
	var tex := HeroPortrait.suit_thumb(id)
	if tex != null:
		HeroPortrait.draw_into(c, tex, th, Color(1, 1, 1, 1.0 if unlocked else 0.55))
	else:
		var pc: Color = HeroLook.SUITS[id]["plate"]
		c.draw_rect(th, Color(pc.r * 1.6, pc.g * 1.6, pc.b * 1.6, 1.0))
	c.draw_rect(th, Color(tint, 0.85 if (on or hot) else 0.45), false, 1.5 * s)
	var tx := th.end.x + 12.0 * s
	var tw := r.end.x - tx - 8.0 * s
	var nm := String(HeroLook.SUITS[id]["name"])
	var nsz := maxi(UiUtil.fit_size(font, nm, tw, int(UiKit.T_TITLE * s)), int(Hud.BODY_MIN * s))
	hud._text(c, font, Vector2(tx, r.position.y + 32.0 * s), nm, HORIZONTAL_ALIGNMENT_LEFT, tw, nsz, Color(1, 1, 1, 0.98 if (on or unlocked) else 0.7))
	var sz := int(Hud.BODY_MIN * s)
	var st_sz := maxi(UiUtil.fit_size(font, label, tw - (22.0 * s if label == "LOCKED" else 0.0), int(UiKit.T_LABEL * s)), sz)
	var st_x := tx + (22.0 * s if label == "LOCKED" else 0.0)
	if label == "LOCKED":
		_lock(c, Vector2(tx + 8.0 * s, r.position.y + 55.0 * s), s, Color(UiUtil.RED, 0.95))
	hud._text(c, font, Vector2(st_x, r.position.y + 60.0 * s), label, HORIZONTAL_ALIGNMENT_LEFT, tw, st_sz, Color(_state_color(label).lerp(Color.WHITE, 0.25), 1.0))
	if label == "LOCKED":
		var lines := UiKit.wrap_text(hud, font, Tr.t(hint_of(key)), tw, sz, 2)
		for li in lines.size():
			hud._text(c, font, Vector2(tx, r.position.y + (79.0 + 17.0 * float(li)) * s), lines[li], HORIZONTAL_ALIGNMENT_LEFT, tw, sz, Color(1, 1, 1, 0.72))
	else:
		hud._text(c, font, Vector2(tx, r.position.y + 86.0 * s), suit_tag(id), HORIZONTAL_ALIGNMENT_LEFT, tw, sz, Color(1, 1, 1, 0.66))


static func _draw_scheme_chip(hud: Hud, c: Control, r: Rect2, i: int, h: HeroLook, s: float, font: Font) -> void:
	var key := "scheme:%d" % i
	var on := h.scheme == i and h.accent_hue < 0
	var unlocked := h.is_unlocked(key, _cos())
	var hot := hud._hover == StringName("look_scheme_%d" % i)
	var label := label_for(key, on)
	var acc := HeroLook.SCHEMES[i][2] as Color
	var tint := UiUtil.GREEN if on else (UiUtil.CYAN if unlocked else UiUtil.AMBER)
	UiKit.panel(c, r, s, tint, on or hot, 8.0, on)
	c.draw_rect(Rect2(r.position.x + 5.0 * s, r.position.y + 10.0 * s, 12.0 * s, r.size.y - 20.0 * s), acc if unlocked else Color(acc, 0.45))
	var tx := r.position.x + 24.0 * s
	var tw := r.end.x - tx - 9.0 * s
	var nm := String(HeroLook.SCHEMES[i][0])
	hud._text(c, font, Vector2(tx, r.position.y + 28.0 * s), nm, HORIZONTAL_ALIGNMENT_LEFT, tw, maxi(UiUtil.fit_size(font, nm, tw, int(UiKit.T_BODY * s)), int(Hud.BODY_MIN * s)), Color(1, 1, 1, 0.97 if unlocked else 0.7))
	hud._text(c, font, Vector2(tx, r.position.y + 54.0 * s), label, HORIZONTAL_ALIGNMENT_LEFT, tw, int(Hud.BODY_MIN * s), Color(_state_color(label).lerp(Color.WHITE, 0.2), 1.0))


static func _draw_hue(hud: Hud, c: Control, r: Rect2, i: int, h: HeroLook, s: float) -> void:
	var owned := h.owned.has("accent")
	var on := h.accent_hue == i
	var hot := hud._hover == StringName("look_hue_%d" % i)
	UiKit.panel(c, r, s, UiUtil.GREEN if on else UiUtil.CYAN, on or hot, 8.0, on)
	var col := HeroLook.hue_color(i)
	c.draw_rect(r.grow(-9.0 * s), col if owned else Color(col, 0.3))
	if not owned:
		_lock(c, r.get_center(), s * 0.9, Color(1, 1, 1, 0.7))


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var p := Game.progress as Progress
	hud.header(c, vp, s, font, "SUIT")
	if p == null:
		return
	var h := p.hero
	hud._text(c, font, Vector2(0.0, 128.0 * s), "CREDITS  %d" % p.credits, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	for cp: Dictionary in captions(cx, s):
		hud._text(c, font, Vector2(cp["x"], cp["y"]), String(cp["t"]), HORIZONTAL_ALIGNMENT_LEFT, cp["w"], int(UiKit.T_BODY * s), Color(cp["col"], 0.95), 1.0 * s)
	# the hero: a lit plate, an accent halo behind him, the live 3D picture on top
	var sr := showcase_rect(cx, s)
	UiKit.panel(c, sr, s, UiUtil.CYAN, false, 12.0)
	var acc := h.accent()
	var mid := sr.get_center() + Vector2(0.0, -sr.size.y * 0.06)
	for k in 5:
		var f := 1.0 - float(k) * 0.17
		c.draw_circle(mid, sr.size.x * 0.62 * f, Color(acc.r, acc.g, acc.b, 0.05))
	var sc := HeroShowcase.of(hud)
	var shown := sc.show_look(h)
	if shown:
		hud.preview_rect = sc.draw(c, sr.grow(-3.0 * s))
		hud._text(c, font, Vector2(sr.position.x, sr.end.y - 10.0 * s), "DRAG TO TURN", HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, int(Hud.BODY_MIN * s), Color(1, 1, 1, 0.55))
	else:
		hud._text(c, font, Vector2(sr.position.x, sr.get_center().y), "NO PREVIEW", HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, int(UiKit.T_LABEL * s), Color(1, 1, 1, 0.5))
	# the cards, chips and swatches
	for b: Dictionary in hud.buttons:
		var bid := String(b["id"])
		if not b.get("own", false):
			continue
		var r: Rect2 = b["rect"]
		if bid.begins_with("look_suit_"):
			_draw_suit_card(hud, c, r, StringName(bid.substr(10)), h, s, font)
		elif bid.begins_with("look_scheme_"):
			_draw_scheme_chip(hud, c, r, int(bid.substr(12)), h, s, font)
		elif bid.begins_with("look_hue_") and bid != "look_hue_buy":
			_draw_hue(hud, c, r, int(bid.substr(9)), h, s)
