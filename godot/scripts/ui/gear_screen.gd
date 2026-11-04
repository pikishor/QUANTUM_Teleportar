class_name GearScreen
extends RefCounted
## The GEAR page of the loadout screen (Hud draws it on the pause screen when `_loadout_open` and `_loadout_page == 1`; the weapons page has a GEAR button, this page a WEAPONS one).
## Rows of 64 px high touch buttons: THROWABLES (5), GADGET (3 and NONE), the four saved LOADOUTS (tap = equip that set) and SAVE 1..4 (store the current weapon, throwable and gadget
## in the slot). Button ids: `gt_<id>` (throwable: BUY price / EQUIP / ON), `gg_<id>` (gadget, `gg_none` empties the slot), `ls_<i>`, `lsave_<i>`, `gear_weapons`.
## Numbers live in Gear and Economy, the wallet in Progress; Hud.press_button routes the ids here.

const BTN_H := 64.0
const ROW_THROW_Y := 192.0
const ROW_GADGET_Y := 294.0
const ROW_LOAD_Y := 400.0
const ROW_SAVE_Y := 472.0
const BACK_Y := 636.0
const GAP := 8.0


## Horizontal squeeze factor so a row of `total` base px fits a viewport that is narrower than the 16:9 layout (a square window).
static func fit(hud: Hud, s: float, total: float) -> float:
	return minf(1.0, hud.get_viewport().get_visible_rect().size.x * 0.96 / maxf(total * s, 1.0))


static func _row(hud: Hud, cx: float, s: float, ids: Array, y: float, prefix: String, w: float, count := 0) -> void:
	var n := maxi(count, ids.size())
	var total := float(n) * w + float(n - 1) * GAP
	var k := fit(hud, s, total)
	for i in ids.size():
		var id := StringName(ids[i])
		hud._add(StringName("%s%s" % [prefix, id]), Rect2(cx + (-total * 0.5 + float(i) * (w + GAP)) * s * k, y * s, w * s * k, BTN_H * s), _label(id), _is_on(id))


static func _is_on(id: StringName) -> bool:
	if id == &"none":
		return Gear.gadget == &""
	return Gear.throwable == id or Gear.gadget == id


static func _label(id: StringName) -> String:
	if id == &"none":
		return "NONE"
	var prog := Game.progress as Progress
	if _is_on(id):
		return "ON"
	if Gear.is_owned(id):
		return "EQUIP"
	return "BUY  %d" % (prog.gear_price(id) if prog != null else Economy.gear_price(id))


static func layout(hud: Hud, cx: float, s: float) -> void:
	_row(hud, cx, s, Gear.THROW_IDS, ROW_THROW_Y, "gt_", 150.0)
	var g: Array = Gear.GADGET_IDS.duplicate()
	g.append(&"none")
	_row(hud, cx, s, g, ROW_GADGET_Y, "gg_", 190.0)
	var ls := 4
	var w := 200.0
	var total := float(ls) * w + float(ls - 1) * GAP
	var k := fit(hud, s, total)
	for i in ls:
		var x := cx + (-total * 0.5 + float(i) * (w + GAP)) * s * k
		hud._add(StringName("ls_%d" % i), Rect2(x, ROW_LOAD_Y * s, w * s * k, BTN_H * s), "%d  %s" % [i + 1, Gear.loadout_label(i)], Gear.active_slot == i)
		hud._add(StringName("lsave_%d" % i), Rect2(x, ROW_SAVE_Y * s, w * s * k, BTN_H * s), "SAVE  %d" % [i + 1], false)
	var kb := fit(hud, s, 460.0)
	hud._add(&"gear_weapons", Rect2(cx - 230.0 * s * kb, BACK_Y * s, 220.0 * s * kb, BTN_H * s), "WEAPONS", false)
	hud._add(&"loadout_back", Rect2(cx + 10.0 * s * kb, BACK_Y * s, 220.0 * s * kb, BTN_H * s), "RESUME" if hud._loadout_quick else "BACK", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var prog := Game.progress as Progress
	hud._text(c, font, Vector2(0.0, 92.0 * s), "GEAR", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(52.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
	if prog != null:
		hud._text(c, font, Vector2(0.0, 134.0 * s), "CREDITS  %d" % prog.credits, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	_names(hud, c, s, font, cx, Gear.THROW_IDS, 5, ROW_THROW_Y, 150.0)
	_names(hud, c, s, font, cx, Gear.GADGET_IDS, 4, ROW_GADGET_Y, 190.0)
	hud._text(c, font, Vector2(cx - 400.0 * s, (ROW_LOAD_Y - 24.0) * s), "LOADOUTS", HORIZONTAL_ALIGNMENT_LEFT, 300.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)
	var cur := Gear.title(Gear.throwable) + ("  +  " + Gear.title(Gear.gadget) if Gear.gadget != &"" else "")
	hud._text(c, font, Vector2(0.0, 556.0 * s), cur, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	var d := Gear.def(Gear.gadget if Gear.gadget != &"" else Gear.throwable)
	hud._text(c, font, Vector2(0.0, 592.0 * s), String(d.get("desc", "")), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * s), Color(1, 1, 1, 0.8), 0.0)


static func _names(hud: Hud, c: Control, s: float, font: Font, cx: float, ids: Array, count: int, y: float, w: float) -> void:
	var total := float(count) * w + float(count - 1) * GAP
	var k := fit(hud, s, total)
	for i in ids.size():
		var id := StringName(ids[i])
		hud._text(c, font, Vector2(cx + (-total * 0.5 + float(i) * (w + GAP)) * s * k, (y - 28.0) * s), String(Gear.def(id)["tag"]), HORIZONTAL_ALIGNMENT_CENTER, w * s * k, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)


## Button effect for the ids of this page. Returns true when it handled the id (the caller redraws).
static func press(sid: String) -> bool:
	var prog := Game.progress as Progress
	if prog == null:
		return false
	if sid.begins_with("gt_") or sid.begins_with("gg_"):
		var raw := sid.substr(3)
		var id := &"" if raw == "none" else StringName(raw)
		var ok := prog.equip_gear(id)
		Sfx.play(&"ui_purchase" if ok else &"ui_deny")
		return ok
	if sid.begins_with("ls_"):
		Sfx.play(&"ui_tap")
		return prog.apply_loadout(sid.substr(3).to_int())
	if sid.begins_with("lsave_"):
		Sfx.play(&"ui_confirm")
		return prog.save_loadout(sid.substr(6).to_int())
	return false
