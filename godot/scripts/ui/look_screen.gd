class_name LookScreen
extends RefCounted
## G2 hero look screen (Hud draws it on the pause shop when `_look_open`; `_shop_open` stays true, so the cinematics keep their close-up of the hero beside the panel).
## Buttons: `look_suit_<id>`, `look_scheme_<i>`, `look_hue_<i>` (-1 = scheme accent is `look_hue_n`), `look_back`. Rows show EQUIP, ON, a BUY price or LOCKED (achievement reward).
## Numbers and rules come from HeroLook, purchases from Progress.buy_look().

const LEFT := -20.0                  ## panel starts right of the hero close-up (px offset from the centre)
const ROW_W := 120.0
const GAP := 8.0
const Y0 := 170.0
const ROW_STEP := 112.0


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


static func layout(hud: Hud, cx: float, s: float) -> void:
	var p := Game.progress as Progress
	if p == null:
		return
	var h := p.hero
	for i in HeroLook.SUIT_ORDER.size():
		var id := HeroLook.SUIT_ORDER[i]
		hud._add(StringName("look_suit_%s" % id), Rect2(cx + (LEFT + i * (ROW_W + GAP)) * s, (Y0 + 20.0) * s, ROW_W * s, 44.0 * s), label_for("suit:%s" % id, h.suit == id), h.suit == id)
	for i in HeroLook.SCHEMES.size():
		hud._add(StringName("look_scheme_%d" % i), Rect2(cx + (LEFT + (i % 4) * (ROW_W + GAP)) * s, (Y0 + ROW_STEP + 20.0 + (i / 4) * 54.0) * s, ROW_W * s, 44.0 * s), label_for("scheme:%d" % i, h.scheme == i and h.accent_hue < 0), h.scheme == i and h.accent_hue < 0)
	var ay := (Y0 + ROW_STEP + 150.0) * s
	for i in HeroLook.HUES:
		hud._add(StringName("look_hue_%d" % i), Rect2(cx + (LEFT + i * 40.0) * s, ay + 20.0 * s, 36.0 * s, 36.0 * s), "", h.accent_hue == i)
	hud._add(&"look_hue_buy", Rect2(cx + LEFT * s, ay + 62.0 * s, 200.0 * s, 40.0 * s), "ACCENT  OWNED" if h.owned.has("accent") else "ACCENT  BUY  %d" % HeroLook.ACCENT_PRICE, h.owned.has("accent"))
	hud._add(&"look_back", Rect2(cx + (LEFT + 300.0) * s, ay + 62.0 * s, 200.0 * s, 40.0 * s), "BACK", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var p := Game.progress as Progress
	hud._text(c, font, Vector2(0.0, 92.0 * s), "SUIT", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(52.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
	if p == null:
		return
	hud._text(c, font, Vector2(0.0, 128.0 * s), "CREDITS  %d" % p.credits, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	var x0 := cx + LEFT * s
	for i in HeroLook.SUIT_ORDER.size():
		hud._text(c, font, Vector2(x0 + i * (ROW_W + GAP) * s, (Y0 + 12.0) * s), String(HeroLook.SUITS[HeroLook.SUIT_ORDER[i]]["name"]), HORIZONTAL_ALIGNMENT_LEFT, ROW_W * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	for i in HeroLook.SCHEMES.size():
		var sw := Rect2(x0 + ((i % 4) * (ROW_W + GAP) + ROW_W - 14.0) * s, (Y0 + ROW_STEP + 8.0 + (i / 4) * 54.0) * s, 14.0 * s, 10.0 * s)
		hud._rect(c, sw, HeroLook.SCHEMES[i][2] as Color)
		hud._text(c, font, Vector2(x0 + (i % 4) * (ROW_W + GAP) * s, (Y0 + ROW_STEP + 16.0 + (i / 4) * 54.0) * s), String(HeroLook.SCHEMES[i][0]), HORIZONTAL_ALIGNMENT_LEFT, (ROW_W - 18.0) * s, int(UiUtil.BAR_LABEL * s), Color(1, 1, 1, 0.9), 1.0 * s)
	var ay := (Y0 + ROW_STEP + 150.0) * s
	for i in HeroLook.HUES:
		hud._rect(c, Rect2(x0 + i * 40.0 * s + 4.0 * s, ay + 24.0 * s, 28.0 * s, 28.0 * s), HeroLook.hue_color(i) if p.hero.owned.has("accent") else Color(HeroLook.hue_color(i), 0.3))
