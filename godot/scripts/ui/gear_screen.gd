class_name GearScreen
extends RefCounted
## The GEAR page of the loadout screen (Hud draws it on the pause screen when `_loadout_open` and `_loadout_page == 1`; the weapons page has a GEAR button, this page a WEAPONS one).
## Rows of 64 px high touch buttons: THROWABLES (5), GADGET (3 and NONE), the four saved LOADOUTS (tap = equip that set) and SAVE 1..4 (store the current weapon, throwable and gadget
## in the slot). Button ids: `gt_<id>` (throwable: BUY price / EQUIP / ON), `gg_<id>` (gadget, `gg_none` empties the slot), `ls_<i>`, `lsave_<i>`, `gear_weapons`.
## Numbers live in Gear and Economy, the wallet in Progress; Hud.press_button routes the ids here.

const BTN_H := 64.0
const TILE_H := 108.0                     ## a throwable / gadget tile: its picture, its name and what a tap does
const ROW_THROW_Y := 160.0
const ROW_GADGET_Y := 304.0
const ROW_LOAD_Y := 452.0
const ROW_SAVE_Y := 520.0
const BACK_Y := 630.0
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
		hud._add(StringName("%s%s" % [prefix, id]), Rect2(cx + (-total * 0.5 + float(i) * (w + GAP)) * s * k, y * s, w * s * k, TILE_H * s), _label(id), _is_on(id))
		hud.buttons[hud.buttons.size() - 1]["own"] = true                       # the tile (plate, picture, name, state) is painted by draw() below


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
	_row(hud, cx, s, g, ROW_GADGET_Y, "gg_", 170.0)
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
	for spec: Array in [["THROWABLES", Gear.THROW_IDS.size(), ROW_THROW_Y, 150.0], ["GADGETS", Gear.GADGET_IDS.size() + 1, ROW_GADGET_Y, 170.0]]:
		var w: float = spec[3]
		var total := float(spec[1]) * w + float(int(spec[1]) - 1) * GAP
		var k := fit(hud, s, total)
		out.append({"t": String(spec[0]), "x": cx + (-total * 0.5) * s * k, "y": (float(spec[2]) - 10.0) * s, "w": 300.0 * s, "center": false})
	var lw := 4.0 * 200.0 + 3.0 * GAP
	var lk := fit(hud, s, lw)
	out.append({"t": "LOADOUTS", "x": cx - lw * 0.5 * s * lk, "y": (ROW_LOAD_Y - 10.0) * s, "w": 300.0 * s, "center": false})
	return out


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var prog := Game.progress as Progress
	hud.header(c, vp, s, font, "GEAR")
	if prog != null:
		hud._text(c, font, Vector2(0.0, 134.0 * s), "CREDITS  %d" % prog.credits, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
		var cw := hud._text_width(font, "CREDITS  %d" % prog.credits, int(UiUtil.TEXT_MIN * s))
		UiKit.glyph(c, &"coin", Vector2(vp.x * 0.5 - cw * 0.5 - 22.0 * s, 124.0 * s), 11.0 * s, Color(UiUtil.AMBER, 0.95), s)
	for cp: Dictionary in captions(hud, cx, s):
		var r := Rect2(float(cp["x"]), float(cp["y"]) - 24.0 * s, float(cp["w"]), 32.0 * s)
		UiKit.section(hud, c, r, String(cp["t"]), UiUtil.AMBER, s, font)
	# the tiles: plate, picture, name, state
	for b: Dictionary in hud.buttons:
		var bid := String(b["id"])
		if not (bid.begins_with("gt_") or bid.begins_with("gg_")) or not b.get("own", false):
			continue
		var r: Rect2 = b["rect"]
		var raw := bid.substr(3)
		var id := &"" if raw == "none" else StringName(raw)
		var on: bool = b["on"]
		var own := id == &"" or Gear.is_owned(id)
		var tint := UiUtil.GREEN if on else (UiUtil.CYAN if own else UiUtil.AMBER)
		UiKit.panel(c, r, s, tint, on or hud._hover == b["id"], 10.0, on)
		var pic := Rect2(r.position.x + 8.0 * s, r.position.y + 6.0 * s, r.size.x - 16.0 * s, 56.0 * s)
		if id == &"":
			UiKit.glyph(c, &"abort", pic.get_center(), 16.0 * s, Color(1, 1, 1, 0.5), s)
		else:
			var tex := ItemIcons.gear(id)
			if tex != null:
				ItemIcons.draw_tex(c, tex, pic, Color(1, 1, 1, 1.0 if own else 0.6))
			else:
				UiKit.glyph(c, &"bomb", pic.get_center(), 16.0 * s, Color(tint, 0.9), s)
		var nm := "NONE" if id == &"" else String(Gear.def(id)["tag"])
		hud._text(c, font, Vector2(r.position.x, r.position.y + 82.0 * s), nm, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UiUtil.fit_size(font, nm, r.size.x - 10.0 * s, int(UiKit.T_BODY * s)), Color(1, 1, 1, 0.97 if own else 0.8), 1.0 * s)
		var st := String(b["label"]) if id != &"" else ("ON" if on else "EQUIP")
		hud._text(c, font, Vector2(r.position.x, r.position.y + r.size.y - 8.0 * s), st, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UiUtil.fit_size(font, st, r.size.x - 10.0 * s, int(Hud.BODY_MIN * s)), Color(tint.lerp(Color.WHITE, 0.4), 1.0))
	var cur := Gear.title(Gear.throwable) + ("  +  " + Gear.title(Gear.gadget) if Gear.gadget != &"" else "")
	var d := Gear.def(Gear.gadget if Gear.gadget != &"" else Gear.throwable)
	var line := "%s   %s" % [cur, String(d.get("desc", ""))]
	hud._text(c, font, Vector2(0.0, 612.0 * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x - 40.0 * s, UiUtil.fit_size(font, line, vp.x - 60.0 * s, int(UiUtil.BAR_LABEL * s)), Color(UiUtil.CYAN, 0.95), 0.0)


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
