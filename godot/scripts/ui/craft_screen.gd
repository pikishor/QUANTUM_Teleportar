class_name CraftScreen
extends RefCounted
## The WORKBENCH (weapon crafting, rules in Crafting): a full-screen pause panel Hud draws when `_craft_open`, reached from the safehouse screen (`sh_craft`), the UPGRADES shop (`cr_open`) and the
## DEMO menu. Three pages, all buttons 64 px tall: CRAFT (`cr_tab_0`: pick a known blueprint, BOOST, CRAFT), INVENTORY (`cr_tab_1`: pick an item, EQUIP / UNEQUIP, DISMANTLE) and SUPPLY
## (`cr_tab_2`: buy parts and blueprints). `cr_cell_<n>` are the 12 grid cells of the page (select or buy), `cr_prev` / `cr_next` page the grid, `cr_back` leaves.
## Layout and drawing only; Hud routes the presses to press().

const COL_W := 250.0
const GAP := 16.0
const BTN_H := 64.0
const ROW_TABS := 100.0
const ROW_PARTS := 190.0
const ROW_GRID := 214.0
const ROW_STEP := 72.0
const GRID_ROWS := 3
const COLS := 4
const PAGE_CELLS := GRID_ROWS * COLS
const ROW_INFO := 436.0
const ROW_ACT := 556.0
const TABS: Array[String] = ["CRAFT", "INVENTORY", "SUPPLY"]

static var page := 0                         ## 0 CRAFT, 1 INVENTORY, 2 SUPPLY
static var grid_page := 0
static var sel_bp: StringName = &"mod_arc"
static var sel_item := 0
static var last := ""                        ## the status line (what the last press did)


## Horizontal shrink (1 = none) so the four columns always fit a narrow viewport; heights never shrink (64 px touch targets).
static var _k := 1.0


static func _fit(hud: Hud, s: float) -> void:
	_k = minf(1.0, hud.get_viewport().get_visible_rect().size.x * 0.97 / ((COL_W * 4.0 + GAP * 3.0) * s))


static func _col(cx: float, s: float, i: int) -> float:
	return cx + (-COL_W * 2.0 - GAP * 1.5 + i * (COL_W + GAP)) * s * _k


static func _r(cx: float, s: float, i: int, y: float) -> Rect2:
	return Rect2(_col(cx, s, i), y * s, COL_W * s * _k, BTN_H * s)


static func reset_state() -> void:
	page = 0
	grid_page = 0
	sel_bp = &"mod_arc"
	sel_item = 0
	last = ""


## What the grid of the current page lists: blueprint ids (CRAFT), item uids (INVENTORY) or supply entries (SUPPLY: {"kind": "part"|"bp", "id": id}).
static func entries() -> Array:
	var out: Array = []
	match page:
		0:
			for id: StringName in Crafting.bp_ids():
				out.append(id)
		1:
			for it: Dictionary in Crafting.items:
				out.append(int(it["uid"]))
		_:
			for id: StringName in Crafting.PART_IDS:
				out.append({"kind": &"part", "id": id})
			for id: StringName in Crafting.unknown_bps():
				out.append({"kind": &"bp", "id": id})
	return out


static func pages() -> int:
	return maxi(1, ceili(float(entries().size()) / float(PAGE_CELLS)))


static func _clamp_page() -> void:
	grid_page = clampi(grid_page, 0, pages() - 1)


static func _cell_entry(n: int) -> Variant:
	var e := entries()
	var i := grid_page * PAGE_CELLS + n
	return e[i] if i >= 0 and i < e.size() else null


static func _cell_label(e: Variant, prog: Progress) -> String:
	match page:
		0:
			var bp := e as StringName
			return Crafting.bp_short(bp) if Crafting.knows(bp) else "?  %s" % Crafting.bp_short(bp)
		1:
			var it := Crafting.item(int(e))
			return ("E  " if Crafting.equipped_on(int(e)) != &"" else "") + Crafting.item_short(it)
		_:
			var d: Dictionary = e
			if d["kind"] == &"part":
				var id: StringName = d["id"]
				return "%d %s  %d" % [int(Economy.CRAFT_PART_BUNDLE[id]), String(Crafting.PART_NAME[id]).replace("QUANTUM ", ""), Crafting.part_price(id, prog)]
			return "%s  %d" % [Crafting.bp_short(d["id"] as StringName), Crafting.bp_price(d["id"] as StringName, prog)]


static func _cell_on(e: Variant) -> bool:
	match page:
		0: return (e as StringName) == sel_bp
		1: return int(e) == sel_item
	return false


static func layout(hud: Hud, cx: float, s: float) -> void:
	var prog := Game.progress as Progress
	_fit(hud, s)
	_clamp_page()
	for i in TABS.size():
		hud._add(StringName("cr_tab_%d" % i), _r(cx, s, i, ROW_TABS), TABS[i], page == i)
	hud._add(&"cr_back", _r(cx, s, 3, ROW_TABS), "BACK", false)
	for n in PAGE_CELLS:
		var e: Variant = _cell_entry(n)
		if e == null:
			break
		hud._add(StringName("cr_cell_%d" % n), _r(cx, s, n % COLS, ROW_GRID + float(floori(float(n) / float(COLS))) * ROW_STEP), _cell_label(e, prog), _cell_on(e))
	hud._add(&"cr_prev", _r(cx, s, 0, ROW_ACT), "PREV  %d/%d" % [grid_page + 1, pages()], false)
	hud._add(&"cr_next", _r(cx, s, 1, ROW_ACT), "NEXT", false)
	match page:
		0:
			hud._add(&"cr_boost", _r(cx, s, 2, ROW_ACT), "BOOST  %s" % ("ON" if Crafting.boost else "OFF"), Crafting.boost)
			var cost := Crafting.cost_of(sel_bp, Crafting.boost)
			hud._add(&"cr_make", _r(cx, s, 3, ROW_ACT), "CRAFT  %d CR" % int(cost["credits"]), Crafting.why_not(prog, sel_bp, Crafting.boost) == "")
		1:
			var it := Crafting.item(sel_item)
			var on := not it.is_empty() and Crafting.equipped_on(sel_item) != &""
			hud._add(&"cr_equip", _r(cx, s, 2, ROW_ACT), "UNEQUIP" if on else "EQUIP", not it.is_empty() and not on)
			hud._add(&"cr_dismantle", _r(cx, s, 3, ROW_ACT), "DISMANTLE", not it.is_empty())


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var prog := Game.progress as Progress
	_fit(hud, s)
	if not hud._hero_hub:
		hud._text(c, font, Vector2(0.0, 84.0 * s), "WORKBENCH", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(46.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
	var x := _col(cx, s, 0)
	var w := (COL_W * 4.0 + GAP * 3.0) * s * _k
	var line := "SCRAP %d    ALLOY %d    QUANTUM CORE %d    ITEMS %d/%d    CREDITS %d" % [Crafting.part_count(&"scrap"), Crafting.part_count(&"alloy"), Crafting.part_count(&"core"), Crafting.items.size(), Crafting.ITEM_CAP, prog.credits if prog != null else 0]
	hud._text(c, font, Vector2(x, (ROW_PARTS + 6.0) * s), line, HORIZONTAL_ALIGNMENT_LEFT, w, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)
	hud._rect(c, Rect2(x, ROW_INFO * s, w, 108.0 * s), Color(0.0, 0.03, 0.05, 0.6))
	var l1 := ""
	var l2 := ""
	var l3 := ""
	var col := Color(1, 1, 1, 0.95)
	match page:
		0:
			l1 = "%s%s" % [Crafting.bp_title(sel_bp), "" if Crafting.knows(sel_bp) else "   (NOT FOUND YET)"]
			var cost := Crafting.cost_of(sel_bp, Crafting.boost)
			l2 = "USES  %s    FEE  %d CR%s" % [Crafting.parts_text(cost["parts"] as Dictionary), int(cost["credits"]), "" if Crafting.bench_level() == 0 else "  (BENCH -%d%%)" % int(Economy.CRAFT_BENCH_DISCOUNT * 100.0 * Crafting.bench_level())]
			var perk := Crafting.bp_perk(sel_bp)
			var why := Crafting.why_not(prog, sel_bp, Crafting.boost)
			l3 = why if why != "" else (Crafting.perk_text(perk) if perk != &"" else "ROLLS RARITY, STATS AND SOMETIMES A PERK")
		1:
			var it := Crafting.item(sel_item)
			if it.is_empty():
				l1 = "NO ITEM SELECTED"
				l2 = "CRAFT A MOD OR VARIANT FIRST"
			else:
				l1 = Crafting.item_name(it)
				col = Crafting.RARITY_COLOR[int(it["rarity"])]
				l2 = Crafting.item_stats_text(it)
				var on := Crafting.equipped_on(sel_item)
				l3 = ("ON  %s    " % WeaponDefs.title(on) if on != &"" else "") + (Crafting.perk_text(it["perk"] as StringName) if it["perk"] != &"" else "NO PERK")
		_:
			l1 = "SUPPLY"
			l2 = "TAP A PART OR A BLUEPRINT TO BUY IT"
			l3 = "PARTS ALSO DROP FROM LOOT, KILLS AND JOBS"
	hud._text(c, font, Vector2(x + 10.0 * s, (ROW_INFO + 28.0) * s), l1, HORIZONTAL_ALIGNMENT_LEFT, w - 20.0 * s, int(UiUtil.BAR_LABEL * s), col, 1.0 * s)
	hud._text(c, font, Vector2(x + 10.0 * s, (ROW_INFO + 58.0) * s), l2, HORIZONTAL_ALIGNMENT_LEFT, w - 20.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	hud._text(c, font, Vector2(x + 10.0 * s, (ROW_INFO + 88.0) * s), l3, HORIZONTAL_ALIGNMENT_LEFT, w - 20.0 * s, int(18.0 * s), Color(1, 1, 1, 0.85), 1.0 * s)
	hud._text(c, font, Vector2(0.0, (ROW_ACT + BTN_H + 30.0) * s), last, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(20.0 * s), Color(UiUtil.AMBER, 0.9), 1.0 * s)


## One button press of the bench (ids `cr_*` except `cr_open`, which Hud handles). Returns whether it did something; `last` says what.
static func press(sid: String) -> bool:
	var prog := Game.progress as Progress
	if prog == null:
		return false
	if sid.begins_with("cr_tab_"):
		var t := int(sid.substr(7))
		if t < 0 or t >= TABS.size():
			return false
		page = t
		grid_page = 0
		last = ""
		return true
	if sid == "cr_prev" or sid == "cr_next":
		grid_page = clampi(grid_page + (-1 if sid == "cr_prev" else 1), 0, pages() - 1)
		return true
	if sid == "cr_boost":
		Crafting.boost = not Crafting.boost
		Crafting.rev += 1
		return true
	if sid == "cr_make":
		var why := Crafting.why_not(prog, sel_bp, Crafting.boost)
		if why != "":
			last = why
			return false
		var it := Crafting.craft(prog, sel_bp, Crafting.boost)
		last = "CRAFTED  %s" % Crafting.item_name(it) if not it.is_empty() else "CRAFT FAILED"
		if not it.is_empty():
			sel_item = int(it["uid"])
		return not it.is_empty()
	if sid == "cr_equip":
		var it := Crafting.item(sel_item)
		if it.is_empty():
			return false
		if Crafting.equipped_on(sel_item) != &"":
			Crafting.unequip(prog, sel_item)
			last = "UNEQUIPPED"
			return true
		var ok := Crafting.equip(prog, sel_item, WeaponDefs.last_used)
		last = "EQUIPPED  %s" % Crafting.item_name(it) if ok else "NEEDS THE WEAPON"
		return ok
	if sid == "cr_dismantle":
		var y := Crafting.dismantle(prog, sel_item)
		if y.is_empty():
			return false
		last = "DISMANTLED  %s" % Crafting.parts_text(y)
		sel_item = 0
		_clamp_page()
		return true
	if sid.begins_with("cr_cell_"):
		var e: Variant = _cell_entry(int(sid.substr(8)))
		if e == null:
			return false
		match page:
			0:
				sel_bp = e as StringName
				return true
			1:
				sel_item = int(e)
				return true
		var d: Dictionary = e
		var ok := Crafting.buy_part(prog, d["id"] as StringName) if d["kind"] == &"part" else Crafting.buy_blueprint(prog, d["id"] as StringName)
		last = "BOUGHT" if ok else "NOT ENOUGH CREDITS"
		_clamp_page()
		return ok
	return false
