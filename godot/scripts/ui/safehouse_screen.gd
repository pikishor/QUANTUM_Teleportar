class_name SafehouseScreen
extends RefCounted
## The safehouse screen of the pause menu (Hud draws it when `_safe_open`, opened by the SAFEHOUSE button, ids `sh_*`, all buttons 64 px tall): pick one of the four houses (`sh_pick_<id>`),
## BUY it or CLAIM it free once its EARN goal is met; in an owned house WARDROBE (`sh_wardrobe`, the look screen), BENCH (`sh_bench`, the loadout), GARAGE (`sh_garage`), TROPHIES (`sh_trophy`,
## the achievements), REST (`sh_rest`), TIME (`sh_time`, the hour REST sets), SAVE (`sh_save`, the fast-save point), GO (`sh_go`, to the door) and the upgrades `sh_up_<bed|locker|bench>`.
## `sh_back` returns to the pause menu. Layout and drawing only: the rules are in Safehouses, the tally in Progress.

const COL_W := 250.0
const GAP := 16.0
const BTN_H := 64.0
const ROW_PICK := 110.0
const ROW_INFO := 184.0
const ROW_A := 318.0
const ROW_B := 394.0
const ROW_C := 470.0
const ROW_D := 546.0                 ## the WORKBENCH (sh_craft) and BACK of an owned house


static func _col(cx: float, s: float, i: int) -> float:
	return cx + (-COL_W * 2.0 - GAP * 1.5 + i * (COL_W + GAP)) * s


static func _r(cx: float, s: float, i: int, y: float) -> Rect2:
	return Rect2(_col(cx, s, i), y * s, COL_W * s, BTN_H * s)


static func layout(hud: Hud, cx: float, s: float) -> void:
	var prog := Game.progress as Progress
	var id := Safehouses.sel
	for i in Safehouses.IDS.size():
		var hid: StringName = Safehouses.IDS[i]
		hud._add(StringName("sh_pick_%s" % hid), _r(cx, s, i, ROW_PICK), Safehouses.title(hid) + ("" if Safehouses.is_owned(prog, hid) else "  LOCKED"), hid == id)
	if Safehouses.is_owned(prog, id):
		hud._add(&"sh_wardrobe", _r(cx, s, 0, ROW_A), "WARDROBE", false)
		hud._add(&"sh_bench", _r(cx, s, 1, ROW_A), "WEAPON BENCH", false)
		hud._add(&"sh_garage", _r(cx, s, 2, ROW_A), "GARAGE", false)
		hud._add(&"sh_trophy", _r(cx, s, 3, ROW_A), "TROPHIES", false)
		hud._add(&"sh_rest", _r(cx, s, 0, ROW_B), "REST", false)
		hud._add(&"sh_time", _r(cx, s, 1, ROW_B), "TO  %s" % Safehouses.REST_NAMES[Safehouses.rest_to], false)
		hud._add(&"sh_save", _r(cx, s, 2, ROW_B), "SAVE" + ("  HERE" if prog.safehouse_save == id else ""), prog.safehouse_save == id)
		hud._add(&"sh_go", _r(cx, s, 3, ROW_B), "GO TO DOOR", false)
		for i in Safehouses.UPS.size():
			var up: StringName = Safehouses.UPS[i]
			var pr := Safehouses.up_price(prog, id, up)
			hud._add(StringName("sh_up_%s" % up), _r(cx, s, i, ROW_C), "%s %d  %s" % [Safehouses.UP_TITLE[up], Safehouses.level(prog, id, up), "MAX" if pr < 0 else "%d CR" % pr], pr < 0)
	else:
		hud._add(&"sh_buy", _r(cx, s, 0, ROW_A), "BUY  %d CR" % int(Economy.SAFEHOUSE_PRICE[id]), Safehouses.can_buy(prog, id))
		var e := Safehouses.earn_progress(prog, id)
		hud._add(&"sh_claim", _r(cx, s, 1, ROW_A), "CLAIM FREE" if Safehouses.earned(prog, id) else "EARN  %d/%d" % [e.x, e.y], Safehouses.earned(prog, id))
	if Safehouses.is_owned(prog, id):
		hud._add(&"sh_craft", _r(cx, s, 0, ROW_D), "WORKBENCH", false)
	hud._add(&"sh_back", _r(cx, s, 3, ROW_D if Safehouses.is_owned(prog, id) else ROW_C), "BACK", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var prog := Game.progress as Progress
	var id := Safehouses.sel
	var d: Dictionary = Safehouses.DEFS[id]
	var owned := Safehouses.is_owned(prog, id)
	hud._text(c, font, Vector2(0.0, 84.0 * s), "SAFEHOUSES", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(46.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
	var x := _col(cx, s, 0)
	var w := (COL_W * 4.0 + GAP * 3.0) * s
	hud._rect(c, Rect2(x, ROW_INFO * s, w, 124.0 * s), Color(0.0, 0.03, 0.05, 0.55))
	hud._text(c, font, Vector2(x + 10.0 * s, (ROW_INFO + 26.0) * s), "%s   %s" % [d["title"], d["brief"]], HORIZONTAL_ALIGNMENT_LEFT, w - 20.0 * s, int(UiUtil.BAR_LABEL * s), Color(1, 1, 1, 0.95), 1.0 * s)
	var info := ""
	if owned:
		info = "OWNED   %d OF %d HOUSES" % [Safehouses.owned_count(prog), Safehouses.IDS.size()]
	else:
		info = "%d CR%s   %s" % [int(Economy.SAFEHOUSE_PRICE[id]), "" if Safehouses.chapter_ok(prog, id) else "  (NEEDS SECTOR %d)" % (int(Economy.SAFEHOUSE_CHAPTER[id]) + 1), d["earn_text"]]
	hud._text(c, font, Vector2(x + 10.0 * s, (ROW_INFO + 56.0) * s), info, HORIZONTAL_ALIGNMENT_LEFT, w - 20.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	hud._text(c, font, Vector2(x + 10.0 * s, (ROW_INFO + 84.0) * s), Safehouses.trophy_text(prog), HORIZONTAL_ALIGNMENT_LEFT, w - 20.0 * s, int(18.0 * s), Color(UiUtil.CYAN, 0.9), 1.0 * s)
	var note := Safehouses.last_rest if owned else ""
	hud._text(c, font, Vector2(x + 10.0 * s, (ROW_INFO + 110.0) * s), note, HORIZONTAL_ALIGNMENT_LEFT, w - 20.0 * s, int(18.0 * s), Color(1, 1, 1, 0.8), 1.0 * s)
	hud._text(c, font, Vector2(0.0, ((ROW_D if owned else ROW_C) + BTN_H + 36.0) * s), "CREDITS  %d" % (prog.credits if prog != null else 0), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(20.0 * s), Color(UiUtil.AMBER, 0.9), 1.0 * s)
