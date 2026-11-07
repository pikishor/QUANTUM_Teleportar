class_name LookScreen
extends RefCounted
## G2 hero look screen (Hud draws it on the pause shop when `_look_open`; `_shop_open` stays true, so the cinematics keep their close-up of the hero beside the panel).
## Buttons: `look_suit_<id>`, `look_scheme_<i>`, `look_hue_<i>` (-1 = scheme accent is `look_hue_n`), `look_back`. Rows show EQUIP, ON, a BUY price or LOCKED (achievement reward).
## Numbers and rules come from HeroLook, purchases from Progress.buy_look().

const LEFT := -20.0                  ## panel starts right of the hero close-up (px offset from the centre)
const ROW_W := 148.0
const GAP := 8.0
const SUIT_Y := 190.0               ## suit buttons (64 px high), their name captions sit in the 22 px above
const SCHEME_Y := 290.0             ## first scheme row; the second row is SCHEME_STEP lower
const SCHEME_STEP := 96.0
const HUE_Y := 490.0                ## the twelve 64 px accent swatches, one row across the whole screen
const HUE_SIZE := 64.0
const HUE_GAP := 8.0
const FOOT_Y := 574.0               ## ACCENT buy and BACK
const BTN_H := 64.0
## The person (HeroCharacter): four 64 px buttons that cycle the body, the skin tone, the hair style and the beard.
const PERSON: Array[String] = ["body", "skin", "hair", "beard"]
const PERSON_H := 64.0
const PERSON_X := -560.0            ## the person grid sits in the free area left of the suit panel (the hero close-up is on the right): 2 x 2 buttons of 250 x 64
const PERSON_W := 250.0
const PERSON_Y := 200.0
const PERSON_STEP := 104.0


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


static func person_rect(i: int, cx: float, s: float) -> Rect2:
	return Rect2(cx + (PERSON_X + (i % 2) * (PERSON_W + GAP)) * s, (PERSON_Y + (i / 2) * PERSON_STEP) * s, PERSON_W * s, PERSON_H * s)


static func person_label(h: HeroLook, what: String) -> String:
	match what:
		"body":
			return String(h.body).to_upper()
		"skin":
			return String(h.skin_tone).to_upper()
		"hair":
			return String(h.hair).to_upper()
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


static func hue_rect(i: int, cx: float, s: float) -> Rect2:
	var total := float(HeroLook.HUES) * HUE_SIZE + float(HeroLook.HUES - 1) * HUE_GAP
	return Rect2(cx + (-total * 0.5 + float(i) * (HUE_SIZE + HUE_GAP)) * s, HUE_Y * s, HUE_SIZE * s, HUE_SIZE * s)


static func layout(hud: Hud, cx: float, s: float) -> void:
	var p := Game.progress as Progress
	if p == null:
		return
	var h := p.hero
	for i in HeroLook.SUIT_ORDER.size():
		var id := HeroLook.SUIT_ORDER[i]
		hud._add(StringName("look_suit_%s" % id), Rect2(cx + (LEFT + i * (ROW_W + GAP)) * s, SUIT_Y * s, ROW_W * s, BTN_H * s), label_for("suit:%s" % id, h.suit == id), h.suit == id)
	for i in HeroLook.SCHEMES.size():
		hud._add(StringName("look_scheme_%d" % i), Rect2(cx + (LEFT + (i % 4) * (ROW_W + GAP)) * s, (SCHEME_Y + (i / 4) * SCHEME_STEP) * s, ROW_W * s, BTN_H * s), label_for("scheme:%d" % i, h.scheme == i and h.accent_hue < 0), h.scheme == i and h.accent_hue < 0)
	for i in HeroLook.HUES:
		hud._add(StringName("look_hue_%d" % i), hue_rect(i, cx, s), "", h.accent_hue == i)
	for i in PERSON.size():
		hud._add(StringName("look_person_%s" % PERSON[i]), person_rect(i, cx, s), person_label(h, PERSON[i]), PERSON[i] == "beard" and h.beard)
	hud._add(&"look_hue_buy", Rect2(cx - 330.0 * s, FOOT_Y * s, 320.0 * s, BTN_H * s), "ACCENT  OWNED" if h.owned.has("accent") else "ACCENT  BUY  %d" % Economy.accent_price(), h.owned.has("accent"))
	hud._add(&"look_back", Rect2(cx + 10.0 * s, FOOT_Y * s, 320.0 * s, BTN_H * s), "BACK", false)


## Every caption of the screen as {t, x, y (baseline), w}: each sits in the band above its own row, a test checks that none reaches a button (or another caption).
static func captions(cx: float, s: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var x0 := cx + LEFT * s
	for i in PERSON.size():
		var pr := person_rect(i, cx, s)
		out.append({"t": ["BODY", "SKIN", "HAIR", "BEARD"][i], "x": pr.position.x, "y": pr.position.y - 8.0 * s, "w": PERSON_W * s, "col": UiUtil.CYAN})
	for i in HeroLook.SUIT_ORDER.size():
		out.append({"t": String(HeroLook.SUITS[HeroLook.SUIT_ORDER[i]]["name"]), "x": x0 + i * (ROW_W + GAP) * s, "y": (SUIT_Y - 8.0) * s, "w": ROW_W * s, "col": UiUtil.CYAN})
	for i in HeroLook.SCHEMES.size():
		out.append({"t": String(HeroLook.SCHEMES[i][0]), "x": x0 + (i % 4) * (ROW_W + GAP) * s, "y": (SCHEME_Y + (i / 4) * SCHEME_STEP - 8.0) * s, "w": (ROW_W - 28.0) * s, "col": Color.WHITE})
	out.append({"t": "ACCENT", "x": hue_rect(0, cx, s).position.x, "y": (HUE_Y - 8.0) * s, "w": 300.0 * s, "col": UiUtil.CYAN})
	return out


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var p := Game.progress as Progress
	hud.header(c, vp, s, font, "SUIT")
	if p == null:
		return
	hud._text(c, font, Vector2(0.0, 128.0 * s), "CREDITS  %d" % p.credits, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	var x0 := cx + LEFT * s
	for cp: Dictionary in captions(cx, s):
		hud._text(c, font, Vector2(cp["x"], cp["y"]), String(cp["t"]), HORIZONTAL_ALIGNMENT_LEFT, cp["w"], int(UiUtil.BAR_LABEL * s), Color(cp["col"], 0.95), 1.0 * s)
	for i in HeroLook.SCHEMES.size():          # the scheme's colour chip sits at the right end of its caption band
		var ry := (SCHEME_Y + (i / 4) * SCHEME_STEP) * s
		hud._rect(c, Rect2(x0 + ((i % 4) * (ROW_W + GAP) + ROW_W - 22.0) * s, ry - 22.0 * s, 22.0 * s, 14.0 * s), HeroLook.SCHEMES[i][2] as Color)
	for i in HeroLook.HUES:
		var hr := hue_rect(i, cx, s).grow(-8.0 * s)
		hud._rect(c, hr, HeroLook.hue_color(i) if p.hero.owned.has("accent") else Color(HeroLook.hue_color(i), 0.3))
