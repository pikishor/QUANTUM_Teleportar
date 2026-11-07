class_name GearScreen
extends RefCounted
## The GEAR page of the loadout screen (Hud draws it on the pause screen when `_loadout_open` and `_loadout_page == 1`; the weapons page has a GEAR button, this page a WEAPONS one).
## Rows of 64 px high touch buttons: THROWABLES (5), GADGET (3 and NONE), the four saved LOADOUTS (tap = equip that set) and SAVE 1..4 (store the current weapon, throwable and gadget
## in the slot). Button ids: `gt_<id>` (throwable: BUY price / EQUIP / ON), `gg_<id>` (gadget, `gg_none` empties the slot), `ls_<i>`, `lsave_<i>`, `gear_weapons`.
## Numbers live in Gear and Economy, the wallet in Progress; Hud.press_button routes the ids here.

const BTN_H := 64.0
const ROW_THROW_Y := 176.0
const ROW_GADGET_Y := 272.0
const ROW_LOAD_Y := 368.0
const ROW_SAVE_Y := 440.0
const BACK_Y := 592.0
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


## Every caption above a row as {t, x, y (baseline), w}: the tag over each throwable / gadget button and LOADOUTS over the saved sets (a test checks none reaches a button).
static func captions(hud: Hud, cx: float, s: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spec: Array in [[Gear.THROW_IDS, 5, ROW_THROW_Y, 150.0], [Gear.GADGET_IDS, 4, ROW_GADGET_Y, 190.0]]:
		var ids: Array = spec[0]
		var w: float = spec[3]
		var total := float(spec[1]) * w + float(int(spec[1]) - 1) * GAP
		var k := fit(hud, s, total)
		for i in ids.size():
			out.append({"t": String(Gear.def(StringName(ids[i]))["tag"]), "x": cx + (-total * 0.5 + float(i) * (w + GAP)) * s * k, "y": (float(spec[2]) - 8.0) * s, "w": w * s * k, "center": true})
	out.append({"t": "LOADOUTS", "x": cx - 400.0 * s, "y": (ROW_LOAD_Y - 8.0) * s, "w": 300.0 * s, "center": false})
	return out


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var prog := Game.progress as Progress
	hud.header(c, vp, s, font, "GEAR")
	if prog != null:
		hud._text(c, font, Vector2(0.0, 134.0 * s), "CREDITS  %d" % prog.credits, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	for cp: Dictionary in captions(hud, cx, s):
		hud._text(c, font, Vector2(cp["x"], cp["y"]), String(cp["t"]), HORIZONTAL_ALIGNMENT_CENTER if cp["center"] else HORIZONTAL_ALIGNMENT_LEFT, cp["w"], int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)
	var cur := Gear.title(Gear.throwable) + ("  +  " + Gear.title(Gear.gadget) if Gear.gadget != &"" else "")
	hud._text(c, font, Vector2(0.0, 534.0 * s), cur, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	var d := Gear.def(Gear.gadget if Gear.gadget != &"" else Gear.throwable)
	hud._text(c, font, Vector2(0.0, 566.0 * s), String(d.get("desc", "")), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * s), Color(1, 1, 1, 0.8), 0.0)


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
