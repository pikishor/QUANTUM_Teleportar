class_name WeaponsScreen
extends RefCounted
## The WEAPONS tab of the HERO hub (the weapon pages of the shop; Hud draws it through ShopScreen when `ShopScreen.weapon_page` >= 1). Every weapon, melee weapon, throwable and gadget of the
## game as a tile with its PICTURE, name and where to get it; tap a tile to select it and read its card on the right: picture, bars (damage, fire rate, range, accuracy, control, penetration),
## the numbers, a diagram (the spread circle on a person 20 m away, or the blast circle around a person), the range ruler (full damage, then falling off) and the BUY / EQUIP button.
## Eight pages of at most 12 tiles (wave 108): PISTOLS SMGS / RIFLES SHOTGUNS / SNIPERS HEAVY / MELEE QUANTUM / ENERGY WEAPONS / BLAST WEAPONS / EXPLOSIVES / GADGETS. Buttons: `wsel_<id>` (select), `wpg_prev` / `wpg_next`, `wequip_<id>`, `wgear_<id>`,
## `buy_<id>` (the shop's own id for a weapon), `shop_back`. Numbers come from WeaponStats / Gear, the pictures from ItemIcons; no state beyond the selection.

const COLS := 3
const ROWS := 3                          ## nine tiles a page: under them the CLASS row (< NAME >) and the PAGE row (< PAGE 2 / 3 >), 64 px high each
const PER_PAGE := COLS * ROWS
const CELL := Vector2(188.0, 100.0)
const GAP := 8.0
const GRID_X := -610.0                   ## left edge of the tile grid, base px from the screen centre
const GRID_Y := 118.0
const PANEL_X := -14.0                   ## the card
const PANEL_W := 624.0
const WIDTH := 1220.0                    ## the whole layout in base px (squeezed horizontally on a narrower screen)
const GEAR_TABS: Array = [[&"explosives", "EXPLOSIVES"], [&"gadgets", "GADGETS"]]

## Every page of the catalogue (wave 113, 200+ weapons): one tab per weapon class (WeaponBrowser), each cut into pages of at most PER_PAGE (balanced), then the EXPLOSIVES and GADGETS of Gear.
## Built on first use and kept (the roster does not change while the game runs; ownership does, and the catalogue shows everything). Not a static initialiser: the order in which scripts run theirs
## is not defined, and WeaponDefs may not be built yet. [{tab, name, title, ids, gear, sub, subs}]
static var _page_list: Array[Dictionary] = []
static var _titles: Array[String] = []
## The number of pages and their titles read like constants (`WeaponsScreen.PAGES`, `PAGE_TITLES[i]`).
static var PAGES: int:
	get:
		return page_list().size()
static var PAGE_TITLES: Array[String]:
	get:
		page_list()
		return _titles


static func page_list() -> Array[Dictionary]:
	if _page_list.is_empty():
		_page_list = _build_pages()
		_titles = []
		for pg in _page_list:
			_titles.append(String(pg["title"]))
	return _page_list

static var sel: StringName = &""             ## the selected item: a weapon id, a throwable id or a gadget id


static func _build_pages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pg in WeaponBrowser.pages(false, PER_PAGE, false):
		out.append({"tab": pg["tab"], "name": pg["name"], "ids": pg["ids"], "gear": false, "sub": pg["sub"], "subs": pg["subs"]})
	var gear_ids: Dictionary = {&"explosives": Gear.THROW_IDS + Gear.CHARGE_IDS, &"gadgets": Gear.GADGET_IDS}
	for gt: Array in GEAR_TABS:
		var ids: Array = gear_ids[gt[0]]
		var chunks := WeaponBrowser.split(ids, PER_PAGE)
		for sub in chunks.size():
			out.append({"tab": gt[0], "name": gt[1], "ids": chunks[sub], "gear": true, "sub": sub, "subs": chunks.size()})
	for pg: Dictionary in out:
		pg["title"] = String(pg["name"]) if int(pg["subs"]) < 2 else "%s  %d / %d" % [pg["name"], int(pg["sub"]) + 1, int(pg["subs"])]
	return out


## The tiles of a page (0 .. PAGES - 1): {id, gear} in class order.
static func page_items(page: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pg: Dictionary = page_list()[clampi(page, 0, PAGES - 1)]
	for id: StringName in pg["ids"]:
		out.append({"id": id, "gear": bool(pg["gear"])})
	return out


## Which page an item is on (0 when it is nowhere).
static func page_of(id: StringName) -> int:
	for p in PAGES:
		if (page_list()[p]["ids"] as Array).has(id):
			return p
	return 0


## The first page of the tab after (dir 1) or before (dir -1) the tab that `page` belongs to (wraps).
static func tab_jump(page: int, dir: int) -> int:
	var starts: Array[int] = []
	for p in PAGES:
		if int(page_list()[p]["sub"]) == 0:
			starts.append(p)
	var cur := 0
	for k in starts.size():
		if starts[k] <= page:
			cur = k
	return starts[posmod(cur + dir, starts.size())]


## How many weapons (or gadgets) the tab of `page` holds in all, and how many of them the hero owns.
static func tab_counts(page: int) -> Vector2i:
	var tab: StringName = page_list()[clampi(page, 0, PAGES - 1)]["tab"]
	var total := 0
	var owned := 0
	for pg: Dictionary in page_list():
		if pg["tab"] != tab:
			continue
		for id: StringName in pg["ids"]:
			total += 1
			if WeaponDefs.is_unlocked(id) or Gear.is_owned(id):
				owned += 1
	return Vector2i(owned, total)


static func is_gear(id: StringName) -> bool:
	return Gear.THROWABLES.has(id) or Gear.GADGETS.has(id) or Gear.CHARGES.has(id)


## Select an item and show its page (a weapon of the loadout, the crate list or a test opens the screen on it).
static func select(id: StringName) -> void:
	sel = id
	ShopScreen.weapon_page = 1 + page_of(id)


## The selection must exist and be on the shown page: the weapon in hand, else the first tile.
static func ensure_sel() -> void:
	var page := clampi(ShopScreen.weapon_page - 1, 0, PAGES - 1)
	for it in page_items(page):
		if it["id"] == sel:
			return
	var items := page_items(page)
	sel = items[0]["id"]
	for it in items:
		if it["id"] == WeaponDefs.last_used:
			sel = it["id"]
			break


static func _k(hud: Hud, s: float) -> float:
	return minf(1.0, hud.get_viewport().get_visible_rect().size.x * 0.97 / (WIDTH * s))


static func cell_rect(hud: Hud, cx: float, s: float, i: int) -> Rect2:
	var k := _k(hud, s)
	return Rect2(cx + (GRID_X + float(i % COLS) * (CELL.x + GAP)) * s * k, (GRID_Y + float(i / COLS) * (CELL.y + GAP)) * s, CELL.x * s * k, CELL.y * s)


## The text under a tile: OWNED, or a short route (CRATE, MISSION, DROP, BOSS) with the price.
static func tile_status(id: StringName) -> String:
	if is_gear(id):
		return "OWNED" if Gear.is_owned(id) else "SHOP  %d" % Economy.gear_price(id)
	if WeaponDefs.is_unlocked(id):
		return "OWNED"
	var e := WeaponLadder.entry(id)
	if e.is_empty():
		return "SHOP  %d" % WeaponDefs.price(id)
	match StringName(e["route"]):
		WeaponLadder.CRATE:
			return "MAP CRATE  %d" % WeaponDefs.price(id)
		WeaponLadder.MISSION:
			return "CHAPTER %d  %d" % [int(e["arg"]) + 1, WeaponDefs.price(id)]
		WeaponLadder.BOSS:
			return "BOSS  %d" % WeaponDefs.price(id)
		WeaponLadder.DROP:
			return "DROP  %d" % WeaponDefs.price(id)
	return "SHOP  %d" % WeaponDefs.price(id)


## The two control rows under the tiles: [class prev, class next, page prev, page next] (64 px each): the first row jumps to the previous / next weapon class, the second flips the pages of the class.
static func row_rects(cx: float, s: float, k: float) -> Array[Rect2]:
	var gw := (COLS * CELL.x + (COLS - 1) * GAP) * s * k
	var y1 := (GRID_Y + float(ROWS) * (CELL.y + GAP) + 2.0) * s
	var y2 := y1 + 72.0 * s
	var x0 := cx + GRID_X * s * k
	return [Rect2(x0, y1, 64.0 * s, 64.0 * s), Rect2(x0 + gw - 64.0 * s, y1, 64.0 * s, 64.0 * s), Rect2(x0, y2, 64.0 * s, 64.0 * s), Rect2(x0 + gw - 64.0 * s, y2, 64.0 * s, 64.0 * s)]


static func layout(hud: Hud, cx: float, s: float) -> void:
	ensure_sel()
	var prog := Game.progress as Progress
	var k := _k(hud, s)
	var page := clampi(ShopScreen.weapon_page - 1, 0, PAGES - 1)
	var items := page_items(page)
	for i in items.size():
		var it: Dictionary = items[i]
		var id: StringName = it["id"]
		var r := cell_rect(hud, cx, s, i)
		hud.buttons.append({"id": StringName("wsel_%s" % id), "rect": r, "label": "", "on": id == sel, "flat": true,
				"pic": {"p": "g" if bool(it["gear"]) else "w", "id": id, "r": Rect2(r.position + Vector2(6.0, 4.0) * s, Vector2(r.size.x - 12.0 * s, 50.0 * s)), "a": 1.0 if (WeaponDefs.is_unlocked(id) or Gear.is_owned(id)) else 0.72},
				"name": _name_of(id), "status": tile_status(id)})
	var rr := row_rects(cx, s, k)
	hud._add(&"wcls_prev", rr[0], "<", false)
	hud._add(&"wcls_next", rr[1], ">", false)
	hud._add(&"wpg_prev", rr[2], "<", false)
	hud._add(&"wpg_next", rr[3], ">", false)
	hud._add(&"shop_back", Rect2(cx + GRID_X * s * k, 640.0 * s, 220.0 * s, 64.0 * s), "BACK", false)
	# the action button of the card
	var ar := Rect2(cx + (PANEL_X + PANEL_W - 300.0) * s * k, 572.0 * s, 300.0 * s * k, 64.0 * s)
	if Gear.is_charge(sel):
		hud._add(StringName("wgear_%s" % sel), ar, "ALWAYS CARRIED", true)
	elif is_gear(sel):
		var gl := "IN USE" if (Gear.throwable == sel or Gear.gadget == sel) else ("EQUIP" if Gear.is_owned(sel) else "BUY  %d" % (prog.gear_price(sel) if prog != null else Economy.gear_price(sel)))
		hud._add(StringName("wgear_%s" % sel), ar, gl, Gear.throwable == sel or Gear.gadget == sel)
	elif WeaponDefs.is_unlocked(sel):
		hud._add(StringName("wequip_%s" % sel), ar, "IN HAND" if sel == WeaponDefs.last_used else "EQUIP", sel == WeaponDefs.last_used)
	else:
		var price := prog.weapon_price(sel) if prog != null else WeaponDefs.price(sel)
		hud._add(StringName("buy_%s" % sel), ar, "BUY  %d" % price, prog != null and prog.can_buy_weapon(sel))


## The name that fits `w` px at the smallest menu size: the whole name, else it loses its last words until it does ("PILLAR ASSAULT RIFLE" -> "PILLAR ASSAULT" -> "PILLAR"): the first word is the one that names the weapon.
static func _fit_name(font: Font, nm: String, w: float, size: int) -> String:
	var words := nm.split(" ", false)
	var n := words.size()
	while n > 1 and font.get_string_size(" ".join(words.slice(0, n)), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > w:
		n -= 1
	return " ".join(words.slice(0, n))


static func _name_of(id: StringName) -> String:
	if is_gear(id):
		return String(Gear.def(id)["name"])
	return WeaponDefs.title(id)


## Draw the tiles' names and statuses, then the card of the selection. (The pictures of the tiles are drawn by Hud with the buttons, over their plates.)
static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	ensure_sel()
	var prog := Game.progress as Progress
	var k := _k(hud, s)
	var page := clampi(ShopScreen.weapon_page - 1, 0, PAGES - 1)
	if prog != null:
		hud._text(c, font, Vector2(cx + (GRID_X + 4.0) * s * k, 106.0 * s), "CREDITS  %d" % prog.credits, HORIZONTAL_ALIGNMENT_LEFT, 300.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	var cnt := tab_counts(page)
	var top := "%s  %d / %d" % ["OWNED" if not bool(page_list()[page]["gear"]) else "HAVE", cnt.x, cnt.y]
	hud._text(c, font, Vector2(cx + (GRID_X + COLS * CELL.x + (COLS - 1) * GAP - 330.0) * s * k, 106.0 * s), top, HORIZONTAL_ALIGNMENT_RIGHT, 330.0 * s * k, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	var items := page_items(page)
	for i in items.size():
		var r := cell_rect(hud, cx, s, i)
		var id: StringName = items[i]["id"]
		var tw := r.size.x - 12.0 * s
		var nm := _fit_name(font, _name_of(id), tw - 8.0 * s, int(14.0 * s))             # words are dropped only when the name does not fit even at the smallest size
		var own := WeaponDefs.is_unlocked(id) or Gear.is_owned(id)
		hud._text(c, font, Vector2(r.position.x + 6.0 * s, r.position.y + 71.0 * s), nm, HORIZONTAL_ALIGNMENT_LEFT, tw, UiUtil.fit_size(font, nm, tw, int(19.0 * s)), Color(1, 1, 1, 0.97 if id == sel else 0.85))
		hud._text(c, font, Vector2(r.position.x + 6.0 * s, r.position.y + 91.0 * s), tile_status(id), HORIZONTAL_ALIGNMENT_LEFT, tw, int(16.0 * s), Color(UiUtil.GREEN if own else UiUtil.AMBER, 0.95))
	var rr := row_rects(cx, s, k)
	var pgd: Dictionary = page_list()[page]
	var tint := UiKit.class_tint(StringName(pgd["tab"])) if not bool(pgd["gear"]) else UiUtil.CYAN
	var mid_w := rr[1].position.x - rr[0].end.x - 16.0 * s
	var cls_cap := "%s  %d" % [pgd["name"], cnt.y]
	hud._text(c, font, Vector2(rr[0].end.x + 8.0 * s, rr[0].position.y + 40.0 * s), cls_cap, HORIZONTAL_ALIGNMENT_CENTER, mid_w, UiUtil.fit_size(font, cls_cap, mid_w, int(UiUtil.BAR_LABEL * s)), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	var pg_cap := "PAGE %d / %d" % [int(pgd["sub"]) + 1, int(pgd["subs"])]
	hud._text(c, font, Vector2(rr[2].end.x + 8.0 * s, rr[2].position.y + 40.0 * s), pg_cap, HORIZONTAL_ALIGNMENT_CENTER, mid_w, int(UiUtil.BAR_LABEL * s), Color(tint.lerp(Color.WHITE, 0.3), 0.97), 1.0 * s)
	_draw_card(hud, c, s, font, cx, k)


static func _draw_card(hud: Hud, c: Control, s: float, font: Font, cx: float, k: float) -> void:
	var px := cx + PANEL_X * s * k
	var pw := PANEL_W * s * k
	var py := GRID_Y * s
	var tint0 := UiKit.class_tint(WeaponDefs.class_of(sel)) if not is_gear(sel) else UiUtil.CYAN
	UiKit.panel(c, Rect2(px - 6.0 * s, py - 4.0 * s, pw + 12.0 * s, (640.0 - GRID_Y) * s), s, tint0, false, 14.0, true)
	if is_gear(sel):
		_draw_gear_card(hud, c, s, font, px, pw, py, k)
		return
	var card := WeaponStats.card(sel, Attachments.effective(sel) if WeaponDefs.is_unlocked(sel) else {})
	# picture and heading
	var pic := Rect2(px + 4.0 * s, py + 6.0 * s, 290.0 * s * k, 138.0 * s)
	c.draw_rect(pic, Color(tint0, 0.08))
	c.draw_rect(pic, Color(tint0, 0.35), false, 1.0 * s)
	var pv := WeaponPreview.of(hud)
	if pv.show_weapon(sel):                                    # the real 3D model on a turntable (drag to turn, tap for the side view)
		pv.draw(c, pic.grow(-2.0 * s))
		hud.preview_rect = pic
		UiKit.glyph(c, &"rotate", pic.end - Vector2(16.0, 16.0) * s, 8.0 * s, Color(1, 1, 1, 0.55), s)
	else:
		ItemIcons.draw_weapon(c, sel, pic.grow(-4.0 * s), Color(1, 1, 1, 1.0))
	var tx := px + (304.0 * k) * s
	var tw := pw - (304.0 * k) * s - 6.0 * s
	var nm := String(card["name"])
	hud._text(c, font, Vector2(tx, py + 30.0 * s), nm, HORIZONTAL_ALIGNMENT_LEFT, tw, UiUtil.fit_size(font, nm, tw, int(26.0 * s)), Color(1, 1, 1, 0.98), 1.0 * s)
	var own := WeaponDefs.is_unlocked(sel)
	hud._text(c, font, Vector2(tx, py + 54.0 * s), "%s  %s" % [String(card["class"]), "OWNED" if own else "NOT OWNED"], HORIZONTAL_ALIGNMENT_LEFT, tw, int(17.0 * s), Color(UiUtil.GREEN if own else UiUtil.AMBER, 0.97))
	var wl := WeaponStats.where(sel)
	for i in wl.size():
		hud._text(c, font, Vector2(tx, py + (78.0 + 20.0 * float(i)) * s), ("WHERE  " if i == 0 else "OR  ") + wl[i], HORIZONTAL_ALIGNMENT_LEFT, tw, UiUtil.fit_size(font, wl[i], tw - 60.0 * s, int(16.0 * s)), Color(UiUtil.CYAN, 0.95))
	# bars (against the weapon in hand when it is another one: a white marker and a +/- number)
	var bx := px + 4.0 * s
	var by := py + 150.0 * s
	var labw := 128.0 * s * k
	var trk := 196.0 * s * k
	var bars: Dictionary = card["bars"]
	var cmp := LoadoutScreen.compare_id(sel)
	var cbars := {}
	if cmp != &"":
		cbars = WeaponStats.card(cmp, Attachments.effective(cmp))["bars"]
		var vs := "VS IN HAND  %s" % WeaponDefs.title(cmp)
		hud._text(c, font, Vector2(tx, py + 134.0 * s), vs, HORIZONTAL_ALIGNMENT_LEFT, tw, UiUtil.fit_size(font, vs, tw, int(Hud.BODY_MIN * s)), Color(1, 1, 1, 0.72))
	for i in WeaponStats.BARS.size():
		var key: StringName = WeaponStats.BARS[i]
		var label: String = WeaponStats.BAR_NAMES[key]
		if bool(card["melee"]) and key == &"range":
			label = "REACH"
		UiKit.stat_bar(hud, c, Rect2(bx, by + 4.0 * s + float(i) * 26.0 * s, labw + trk + 54.0 * s, 24.0 * s), label, float(bars[key]), s, font, labw, float(cbars[key]) if cmp != &"" else -1.0)
	# diagram: the spread (or the blast) around a person
	var dr := Rect2(bx + labw + trk + 64.0 * s, by - 2.0 * s, px + pw - (bx + labw + trk + 64.0 * s) - 2.0 * s, 166.0 * s)
	_draw_diagram(hud, c, s, font, dr, card)
	# numbers
	var ly := by + 6.0 * 26.0 * s + 18.0 * s
	var ls := WeaponStats.lines(card)
	var nw := dr.position.x - bx - 8.0 * s                                  # the numbers stay left of the role column under the diagram
	for i in ls.size():
		hud._text(c, font, Vector2(bx, ly + float(i) * 20.0 * s), ls[i], HORIZONTAL_ALIGNMENT_LEFT, nw, UiUtil.fit_size(font, ls[i], nw, int(16.0 * s)), Color(1, 1, 1, 0.9))
	var trait_line := WeaponRoster.trait_text(sel)
	if trait_line != "":
		hud._text(c, font, Vector2(bx, ly + float(ls.size()) * 20.0 * s + (20.0 * s if bool(card["lock"]) else 0.0)), trait_line, HORIZONTAL_ALIGNMENT_LEFT, nw, UiUtil.fit_size(font, trait_line, nw, int(15.0 * s)), Color(UiUtil.MAGENTA, 0.95))
	if bool(card["lock"]):
		hud._text(c, font, Vector2(bx, ly + float(ls.size()) * 20.0 * s), "LOCKS ON TO THE TARGET UNDER THE CROSSHAIR", HORIZONTAL_ALIGNMENT_LEFT, pw - 8.0 * s, int(15.0 * s), Color(UiUtil.MAGENTA, 0.95))
	# the range ruler
	if not bool(card["melee"]):
		_draw_ruler(hud, c, s, font, Rect2(bx, py + 424.0 * s, pw - 330.0 * s * k, 24.0 * s), card)
	_draw_role(hud, c, s, font, Rect2(dr.position.x, dr.end.y + 10.0 * s, dr.size.x, 572.0 * s - dr.end.y - 18.0 * s), sel)


## Draw `text` wrapped to `w` px in lines of `line_h` px from the baseline `y` (at most `max_lines`), a text never goes below the legible size so it is wrapped, not shrunk. Returns the baseline below the last line.
static func _wrap(hud: Hud, c: Control, font: Font, text: String, x: float, y: float, w: float, fs: int, col: Color, line_h: float, max_lines := 4) -> float:
	var line := ""
	var n := 0
	for word in text.split(" ", false):
		var t := String(word) if line == "" else line + " " + String(word)
		if line != "" and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
			hud._text(c, font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, w, fs, col)
			y += line_h
			n += 1
			line = String(word)
			if n >= max_lines:
				return y
		else:
			line = t
	if line != "":
		hud._text(c, font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, w, fs, col)
		y += line_h
	return y


## What the item is FOR in the missions (WeaponRoster.role: two or three short clauses): a "USE FOR" tag and every clause wrapped to the column under the diagram (the card has no free line elsewhere); nothing for the older guns.
static func _draw_role(hud: Hud, c: Control, s: float, font: Font, r: Rect2, id: StringName) -> void:
	var role := WeaponRoster.role(id)
	if role == "":
		return
	hud._text(c, font, Vector2(r.position.x, r.position.y + 14.0 * s), "USE FOR", HORIZONTAL_ALIGNMENT_LEFT, r.size.x, int(15.0 * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	var y := r.position.y + 14.0 * s + 22.0 * s
	for clause in role.split("  ", false):
		y = _wrap(hud, c, font, String(clause), r.position.x, y, r.size.x, int(16.0 * s), Color(1, 1, 1, 0.93), 19.0 * s, 3) + 4.0 * s
		if y > r.end.y:
			break


## Left: how far a shot flies at full damage and how it fades: a ruler from 0 to the maximum range, the full-damage stretch lit, the falling-off stretch dimmer.
static func _draw_ruler(hud: Hud, c: Control, s: float, font: Font, r: Rect2, card: Dictionary) -> void:
	if bool(card["melee"]):
		hud._text(c, font, Vector2(r.position.x, r.position.y + 16.0 * s), "REACH %.1f M  HITS EVERYONE IN THE ARC" % float(card["reach"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x, int(15.0 * s), Color(1, 1, 1, 0.9))
		return
	var mx := maxf(float(card["range_max"]), 1.0)
	var eff := float(card["range_eff"])
	c.draw_rect(Rect2(r.position.x, r.position.y + 4.0 * s, r.size.x, 14.0 * s), Color(1, 1, 1, 0.1))
	var full_w := r.size.x * clampf(eff / mx, 0.0, 1.0)
	c.draw_rect(Rect2(r.position.x, r.position.y + 4.0 * s, full_w, 14.0 * s), Color(UiUtil.GREEN, 0.85))
	if bool(card["falloff"]):
		var steps := 12
		for i in steps:
			var t := float(i) / float(steps)
			var x0 := r.position.x + full_w + (r.size.x - full_w) * t
			c.draw_rect(Rect2(x0, r.position.y + 4.0 * s, (r.size.x - full_w) / float(steps) + 1.0, 14.0 * s), Color(UiUtil.GREEN, 0.85).lerp(Color(UiUtil.RED, 0.8), t))
	c.draw_rect(Rect2(r.position.x, r.position.y + 4.0 * s, r.size.x, 14.0 * s), Color(1, 1, 1, 0.3), false, 1.0 * s)
	hud._text(c, font, Vector2(r.position.x, r.position.y + 38.0 * s), "0 M", HORIZONTAL_ALIGNMENT_LEFT, 60.0 * s, int(14.0 * s), Color(1, 1, 1, 0.7))
	hud._text(c, font, Vector2(r.position.x + r.size.x - 120.0 * s, r.position.y + 38.0 * s), "%d M" % int(roundf(mx)), HORIZONTAL_ALIGNMENT_RIGHT, 120.0 * s, int(14.0 * s), Color(1, 1, 1, 0.7))
	if bool(card["falloff"]):
		hud._text(c, font, Vector2(r.position.x + full_w - 60.0 * s, r.position.y + 38.0 * s), "%d M" % int(roundf(eff)), HORIZONTAL_ALIGNMENT_CENTER, 120.0 * s, int(14.0 * s), Color(UiUtil.GREEN, 0.95))


## Right of the bars: a person 1.8 m tall for scale. Explosives: the blast circle (and the well of the grenade) around him; guns: the circle the shots land in at 20 m (hip, and aimed inside it).
static func _draw_diagram(hud: Hud, c: Control, s: float, font: Font, r: Rect2, card: Dictionary) -> void:
	c.draw_rect(r, Color(0.05, 0.07, 0.12, 1.0))
	c.draw_rect(r, Color(1, 1, 1, 0.18), false, 1.0 * s)
	var blast := float(card["blast"])
	var cap := ""
	var radius_m := 0.0
	var inner_m := 0.0
	if bool(card["melee"]):
		radius_m = float(card["reach"])
		cap = "REACH  %.1f M" % radius_m
	elif blast > 0.0:
		radius_m = blast
		cap = "BLAST  %.1f M" % blast
	else:
		radius_m = tan(deg_to_rad(float(card["spread_hip"]))) * 20.0
		inner_m = tan(deg_to_rad(float(card["spread_ads"]))) * 20.0
		cap = "AT 20 M  HIP %.1f M" % (radius_m)
	var mid := Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.39)
	var avail := minf(r.size.x * 0.46, r.size.y * 0.3)
	var span_m := maxf(maxf(radius_m, 0.9), 0.5)
	var ppm := avail / span_m                                           # pixels per metre
	# the person: head and body, 1.8 m
	var ph := 1.8 * ppm
	var body := Rect2(mid.x - 0.25 * ppm, mid.y - ph * 0.5 + 0.3 * ppm, 0.5 * ppm, ph - 0.3 * ppm)
	var col_ring := Color(UiUtil.RED, 0.9) if blast > 0.0 else Color(UiUtil.AMBER, 0.95)
	if radius_m > 0.0:
		c.draw_circle(mid, radius_m * ppm, Color(col_ring, 0.16))
		c.draw_arc(mid, radius_m * ppm, 0.0, TAU, 48, col_ring, 2.0 * s)
		if blast > 0.0 and float(card.get("blast_core", 0.0)) > 0.3:       # the part of the blast that does full damage (the core of its BlastTable entry)
			c.draw_arc(mid, float(card["blast_core"]) * ppm, 0.0, TAU, 32, Color(1.0, 0.95, 0.75, 0.9), 1.5 * s)
	if inner_m > 0.0:
		c.draw_arc(mid, inner_m * ppm, 0.0, TAU, 32, Color(UiUtil.CYAN, 0.95), 2.0 * s)
	c.draw_rect(body, Color(1, 1, 1, 0.85))
	c.draw_circle(Vector2(mid.x, body.position.y - 0.17 * ppm), 0.17 * ppm, Color(1, 1, 1, 0.9))
	hud._text(c, font, Vector2(r.position.x + 4.0 * s, r.end.y - 22.0 * s), cap, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8.0 * s, UiUtil.fit_size(font, cap, r.size.x - 8.0 * s, int(15.0 * s)), Color(1, 1, 1, 0.92))
	if inner_m > 0.0:
		var cap2 := "AIMED %.1f M" % inner_m
		hud._text(c, font, Vector2(r.position.x + 4.0 * s, r.end.y - 5.0 * s), cap2, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8.0 * s, int(15.0 * s), Color(UiUtil.CYAN, 0.95))
	elif float(card["well"]) > 0.0:
		hud._text(c, font, Vector2(r.position.x + 4.0 * s, r.end.y - 5.0 * s), "PULL  %.0f M" % float(card["well"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 8.0 * s, int(15.0 * s), Color(UiUtil.MAGENTA, 0.95))


static func _draw_gear_card(hud: Hud, c: Control, s: float, font: Font, px: float, pw: float, py: float, k: float) -> void:
	var d := Gear.def(sel)
	var pic := Rect2(px + 4.0 * s, py + 2.0 * s, 270.0 * s * k, 150.0 * s)
	c.draw_rect(pic, Color(0.07, 0.1, 0.17, 1.0))
	c.draw_rect(pic, Color(UiUtil.CYAN, 0.3), false, 1.0 * s)
	ItemIcons.draw_tex(c, ItemIcons.gear(sel), pic.grow(-6.0 * s))
	var tx := px + (284.0 * k) * s
	var tw := pw - (284.0 * k) * s - 6.0 * s
	var nm := String(d["name"])
	hud._text(c, font, Vector2(tx, py + 30.0 * s), nm, HORIZONTAL_ALIGNMENT_LEFT, tw, UiUtil.fit_size(font, nm, tw, int(26.0 * s)), Color(1, 1, 1, 0.98), 1.0 * s)
	var kind := "GADGET" if Gear.is_gadget(sel) else ("CHARGE" if Gear.is_charge(sel) else "THROWABLE")
	var own := Gear.is_owned(sel)
	hud._text(c, font, Vector2(tx, py + 54.0 * s), "%s  %s" % [kind, "OWNED" if own else "NOT OWNED"], HORIZONTAL_ALIGNMENT_LEFT, tw, int(17.0 * s), Color(UiUtil.GREEN if own else UiUtil.AMBER, 0.97))
	var desc := String(d.get("desc", ""))
	var dy := _wrap(hud, c, font, desc, tx, py + 80.0 * s, tw, int(16.0 * s), Color(1, 1, 1, 0.9), 19.0 * s, 3)           # a long description wraps (the chain reaction line of the C4 was wider than its card)
	hud._text(c, font, Vector2(tx, maxf(py + 104.0 * s, dy + 4.0 * s)), "WHERE  SHOP  %d" % Economy.gear_price(sel) if (not own and not Gear.is_charge(sel)) else "WHERE  YOU HAVE IT", HORIZONTAL_ALIGNMENT_LEFT, tw, int(16.0 * s), Color(UiUtil.CYAN, 0.95))
	var lines := gear_lines(sel)
	for i in lines.size():
		hud._text(c, font, Vector2(px + 8.0 * s, py + (190.0 + 26.0 * float(i)) * s), lines[i], HORIZONTAL_ALIGNMENT_LEFT, pw - 12.0 * s, int(18.0 * s), Color(1, 1, 1, 0.92))
	_draw_role(hud, c, s, font, Rect2(px + 8.0 * s, py + (190.0 + 26.0 * float(lines.size()) + 8.0) * s, pw * 0.5, 60.0 * s), sel)
	# the blast / effect circle around a person
	var radius := float(d.get("radius", d.get("lure", 0.0)))
	if radius > 0.0:
		_draw_diagram(hud, c, s, font, Rect2(px + pw - 230.0 * s * k, py + 240.0 * s, 226.0 * s * k, 176.0 * s), {"melee": false, "blast": radius, "spread_hip": 0.0, "spread_ads": 0.0, "well": 0.0})


## The numbers of a throwable or a gadget as lines.
static func gear_lines(id: StringName) -> Array[String]:
	var d := Gear.def(id)
	var out: Array[String] = []
	if d.has("damage"):
		out.append("%d DAMAGE" % int(roundf(float(d["damage"]))))
	if d.has("radius"):
		out.append("RADIUS %.1f M" % float(d["radius"]))
	if d.has("fuse"):
		out.append("FUSE %.1f S" % float(d["fuse"]))
	if d.has("life"):
		out.append("LASTS %.0f S" % float(d["life"]))
	if d.has("cooldown"):
		out.append("COOLDOWN %.0f S" % float(d["cooldown"]))
	if d.has("range"):
		out.append("RANGE %.0f M" % float(d["range"]))
	if d.has("lure"):
		out.append("DRAWS FIRE WITHIN %.0f M" % float(d["lure"]))
	if d.has("spikes"):
		out.append("%d SPIKES  %d DAMAGE EACH" % [int(d["spikes"]), int(roundf(float(d["damage"])))])
	if d.has("absorb"):
		out.append("TAKES %d DAMAGE" % int(d["absorb"]))
	if d.has("lift"):
		out.append("CLIMBS ABOUT %d M" % int(roundf(float(d["lift"]) * float(d["life"]) * 0.5)))
	if d.has("max"):
		out.append("CARRY %d" % int(d["max"]))
	return out


## The effect of the card's buttons. Returns true when it handled the id.
static func press(sid: String) -> bool:
	if sid.begins_with("wsel_"):
		var id := StringName(sid.substr(5))
		if not (WeaponDefs.DEFS.has(id) or is_gear(id)):
			return false
		sel = id
		Sfx.play(&"ui_tap")
		return true
	if sid == "wpg_prev" or sid == "wpg_next":
		var p := clampi(ShopScreen.weapon_page - 1, 0, PAGES - 1)
		p = posmod(p + (-1 if sid == "wpg_prev" else 1), PAGES)
		ShopScreen.weapon_page = 1 + p
		sel = &""
		ensure_sel()
		Sfx.play(&"ui_tap")
		return true
	if sid == "wcls_prev" or sid == "wcls_next":                                   # the previous / next class (its first page)
		ShopScreen.weapon_page = 1 + tab_jump(clampi(ShopScreen.weapon_page - 1, 0, PAGES - 1), -1 if sid == "wcls_prev" else 1)
		sel = &""
		ensure_sel()
		Sfx.play(&"ui_tap")
		return true
	if sid.begins_with("wequip_"):
		var wid := StringName(sid.substr(7))
		if not WeaponDefs.is_unlocked(wid):
			return false
		var pl := Game.player
		if is_instance_valid(pl) and pl.get(&"weapon") is PlayerWeapon:
			(pl.get(&"weapon") as PlayerWeapon).switch_to(wid)
		WeaponDefs.last_used = wid
		Sfx.play(&"ui_confirm")
		return true
	if sid.begins_with("wgear_"):
		var prog := Game.progress as Progress
		var gid := StringName(sid.substr(6))
		if prog == null or not is_gear(gid):
			return false
		var ok := prog.equip_gear(gid)
		Sfx.play(&"ui_purchase" if ok else &"ui_deny")
		return ok
	return false
