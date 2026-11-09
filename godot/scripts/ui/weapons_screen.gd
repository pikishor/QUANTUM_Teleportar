class_name WeaponsScreen
extends RefCounted
## The WEAPONS tab of the HERO hub (the weapon pages of the shop; Hud draws it through ShopScreen when `ShopScreen.weapon_page` >= 1). Every weapon, melee weapon, throwable and gadget of the
## game as a tile with its PICTURE, name and where to get it; tap a tile to select it and read its card on the right: picture, bars (damage, fire rate, range, accuracy, control, penetration),
## the numbers, a diagram (the spread circle on a person 20 m away, or the blast circle around a person), the range ruler (full damage, then falling off) and the BUY / EQUIP button.
## Eight pages of at most 12 tiles (wave 108): PISTOLS SMGS / RIFLES SHOTGUNS / SNIPERS HEAVY / MELEE QUANTUM / ENERGY WEAPONS / BLAST WEAPONS / EXPLOSIVES / GADGETS. Buttons: `wsel_<id>` (select), `wpg_prev` / `wpg_next`, `wequip_<id>`, `wgear_<id>`,
## `buy_<id>` (the shop's own id for a weapon), `shop_back`. Numbers come from WeaponStats / Gear, the pictures from ItemIcons; no state beyond the selection.

const COLS := 3
const ROWS := 4
const CELL := Vector2(188.0, 100.0)
const GAP := 8.0
const GRID_X := -610.0                   ## left edge of the tile grid, base px from the screen centre
const GRID_Y := 118.0
const PANEL_X := -14.0                   ## the card
const PANEL_W := 624.0
const WIDTH := 1220.0                    ## the whole layout in base px (squeezed horizontally on a narrower screen)
const PAGE_TITLES: Array[String] = ["PISTOLS  SMGS", "RIFLES  SHOTGUNS", "SNIPERS  HEAVY", "MELEE  QUANTUM", "ENERGY WEAPONS", "BLAST WEAPONS", "EXPLOSIVES", "GADGETS"]
const PAGES := 8
const PAGE_CLASSES: Array = [[&"pistol", &"smg"], [&"rifle", &"shotgun"], [&"sniper", &"heavy"], [&"melee", &"quantum"], [&"energy"], [&"blast"], [], []]
const PAGE_EXPLOSIVES := 6               ## throwables and the charge
const PAGE_GADGETS := 7

static var sel: StringName = &""             ## the selected item: a weapon id, a throwable id or a gadget id


## The tiles of a page (0..2): {id, gear} in class order; page 2 closes with the throwables and the gadgets.
static func page_items(page: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cls: StringName in PAGE_CLASSES[clampi(page, 0, PAGES - 1)]:
		for id in WeaponDefs.in_class(cls):
			out.append({"id": id, "gear": false})
	if page == PAGE_EXPLOSIVES:
		for id: StringName in Gear.THROW_IDS:
			out.append({"id": id, "gear": true})
		for id: StringName in Gear.CHARGE_IDS:
			out.append({"id": id, "gear": true})
	elif page == PAGE_GADGETS:
		for id: StringName in Gear.GADGET_IDS:
			out.append({"id": id, "gear": true})
	return out


## Which page an item is on.
static func page_of(id: StringName) -> int:
	for p in PAGES:
		for it in page_items(p):
			if it["id"] == id:
				return p
	return 0


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
	var y_pg := (GRID_Y + float(ROWS) * (CELL.y + GAP) + 2.0) * s
	hud._add(&"wpg_prev", Rect2(cx + GRID_X * s * k, y_pg, 64.0 * s, 64.0 * s), "<", false)
	hud._add(&"wpg_next", Rect2(cx + (GRID_X + COLS * CELL.x + (COLS - 1) * GAP) * s * k - 64.0 * s, y_pg, 64.0 * s, 64.0 * s), ">", false)
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


## The name that fits `w` px at the smallest menu size: the whole name, else its last words ("SINGULARITY GRENADE" -> "GRENADE").
static func _fit_name(font: Font, nm: String, w: float, size: int) -> String:
	var words := nm.split(" ", false)
	var i := 0
	while i < words.size() - 1 and font.get_string_size(" ".join(words.slice(i)), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > w:
		i += 1
	return " ".join(words.slice(i))


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
	hud._text(c, font, Vector2(cx + (GRID_X + COLS * CELL.x + (COLS - 1) * GAP - 330.0) * s * k, 106.0 * s), PAGE_TITLES[page], HORIZONTAL_ALIGNMENT_RIGHT, 330.0 * s * k, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	var items := page_items(page)
	for i in items.size():
		var r := cell_rect(hud, cx, s, i)
		var id: StringName = items[i]["id"]
		var tw := r.size.x - 12.0 * s
		var nm := _fit_name(font, _name_of(id), tw, int(14.0 * s))             # words are dropped only when the name does not fit even at the smallest size
		var own := WeaponDefs.is_unlocked(id) or Gear.is_owned(id)
		hud._text(c, font, Vector2(r.position.x + 6.0 * s, r.position.y + 71.0 * s), nm, HORIZONTAL_ALIGNMENT_LEFT, tw, UiUtil.fit_size(font, nm, tw, int(19.0 * s)), Color(1, 1, 1, 0.97 if id == sel else 0.85))
		hud._text(c, font, Vector2(r.position.x + 6.0 * s, r.position.y + 91.0 * s), tile_status(id), HORIZONTAL_ALIGNMENT_LEFT, tw, int(16.0 * s), Color(UiUtil.GREEN if own else UiUtil.AMBER, 0.95))
	var np := PAGES
	hud._text(c, font, Vector2(cx + (GRID_X + 80.0) * s * k, (GRID_Y + float(ROWS) * (CELL.y + GAP) + 42.0) * s), "PAGE %d / %d" % [page + 1, np], HORIZONTAL_ALIGNMENT_LEFT, 200.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)
	_draw_card(hud, c, s, font, cx, k)


static func _draw_card(hud: Hud, c: Control, s: float, font: Font, cx: float, k: float) -> void:
	var px := cx + PANEL_X * s * k
	var pw := PANEL_W * s * k
	var py := GRID_Y * s
	c.draw_rect(Rect2(px - 6.0 * s, py - 4.0 * s, pw + 12.0 * s, (640.0 - GRID_Y) * s), Color(0.03, 0.045, 0.09, 0.9))
	c.draw_rect(Rect2(px - 6.0 * s, py - 4.0 * s, pw + 12.0 * s, (640.0 - GRID_Y) * s), Color(UiUtil.CYAN, 0.35), false, 1.5 * s)
	if is_gear(sel):
		_draw_gear_card(hud, c, s, font, px, pw, py, k)
		return
	var card := WeaponStats.card(sel, Attachments.effective(sel) if WeaponDefs.is_unlocked(sel) else {})
	# picture and heading
	var pic := Rect2(px + 4.0 * s, py + 2.0 * s, 270.0 * s * k, 112.0 * s)
	c.draw_rect(pic, Color(0.07, 0.1, 0.17, 1.0))
	c.draw_rect(pic, Color(UiUtil.CYAN, 0.3), false, 1.0 * s)
	ItemIcons.draw_weapon(c, sel, pic.grow(-4.0 * s), Color(1, 1, 1, 1.0))
	var tx := px + (284.0 * k) * s
	var tw := pw - (284.0 * k) * s - 6.0 * s
	var nm := String(card["name"])
	hud._text(c, font, Vector2(tx, py + 30.0 * s), nm, HORIZONTAL_ALIGNMENT_LEFT, tw, UiUtil.fit_size(font, nm, tw, int(26.0 * s)), Color(1, 1, 1, 0.98), 1.0 * s)
	var own := WeaponDefs.is_unlocked(sel)
	hud._text(c, font, Vector2(tx, py + 54.0 * s), "%s  %s" % [String(card["class"]), "OWNED" if own else "NOT OWNED"], HORIZONTAL_ALIGNMENT_LEFT, tw, int(17.0 * s), Color(UiUtil.GREEN if own else UiUtil.AMBER, 0.97))
	var wl := WeaponStats.where(sel)
	for i in wl.size():
		hud._text(c, font, Vector2(tx, py + (78.0 + 20.0 * float(i)) * s), ("WHERE  " if i == 0 else "OR  ") + wl[i], HORIZONTAL_ALIGNMENT_LEFT, tw, UiUtil.fit_size(font, wl[i], tw - 60.0 * s, int(16.0 * s)), Color(UiUtil.CYAN, 0.95))
	# bars
	var bx := px + 4.0 * s
	var by := py + 128.0 * s
	var labw := 138.0 * s * k
	var trk := 150.0 * s * k
	var bars: Dictionary = card["bars"]
	for i in WeaponStats.BARS.size():
		var key: StringName = WeaponStats.BARS[i]
		var y := by + float(i) * 29.0 * s
		var v := float(bars[key])
		var label: String = WeaponStats.BAR_NAMES[key]
		if bool(card["melee"]) and key == &"range":
			label = "REACH"
		hud._text(c, font, Vector2(bx, y + 17.0 * s), label, HORIZONTAL_ALIGNMENT_LEFT, labw, int(15.0 * s), Color(1, 1, 1, 0.85))
		var tr := Rect2(bx + labw, y + 4.0 * s, trk, 16.0 * s)
		c.draw_rect(tr, Color(1, 1, 1, 0.1))
		c.draw_rect(Rect2(tr.position, Vector2(tr.size.x * v, tr.size.y)), Color(UiUtil.CYAN, 0.92).lerp(Color(UiUtil.AMBER, 0.95), clampf((v - 0.55) * 2.0, 0.0, 1.0)))
		c.draw_rect(tr, Color(1, 1, 1, 0.25), false, 1.0 * s)
	# diagram: the spread (or the blast) around a person
	var dr := Rect2(bx + labw + trk + 14.0 * s * k, by - 2.0 * s, px + pw - (bx + labw + trk + 14.0 * s * k) - 2.0 * s, 178.0 * s)
	_draw_diagram(hud, c, s, font, dr, card)
	# numbers
	var ly := by + 6.0 * 29.0 * s + 22.0 * s
	var ls := WeaponStats.lines(card)
	for i in ls.size():
		hud._text(c, font, Vector2(bx, ly + float(i) * 20.0 * s), ls[i], HORIZONTAL_ALIGNMENT_LEFT, pw - 8.0 * s, UiUtil.fit_size(font, ls[i], pw - 8.0 * s, int(16.0 * s)), Color(1, 1, 1, 0.9))
	var trait_line := WeaponRoster.trait_text(sel)
	if trait_line != "":
		hud._text(c, font, Vector2(bx, ly + float(ls.size()) * 20.0 * s + (20.0 * s if bool(card["lock"]) else 0.0)), trait_line, HORIZONTAL_ALIGNMENT_LEFT, pw - 8.0 * s, UiUtil.fit_size(font, trait_line, pw - 8.0 * s, int(15.0 * s)), Color(UiUtil.MAGENTA, 0.95))
	if bool(card["lock"]):
		hud._text(c, font, Vector2(bx, ly + float(ls.size()) * 20.0 * s), "LOCKS ON TO THE TARGET UNDER THE CROSSHAIR", HORIZONTAL_ALIGNMENT_LEFT, pw - 8.0 * s, int(15.0 * s), Color(UiUtil.MAGENTA, 0.95))
	# the range ruler
	if not bool(card["melee"]):
		_draw_ruler(hud, c, s, font, Rect2(bx, py + 424.0 * s, pw - 330.0 * s * k, 24.0 * s), card)
	_draw_role(hud, c, s, font, Rect2(bx, py + 470.0 * s, pw - 330.0 * s * k, 60.0 * s), sel)


## What the item is FOR in the missions (WeaponRoster.role: two or three short clauses), one clause a line under a "USE FOR" tag; nothing for the older guns.
static func _draw_role(hud: Hud, c: Control, s: float, font: Font, r: Rect2, id: StringName) -> void:
	var role := WeaponRoster.role(id)
	if role == "":
		return
	var clauses := role.split("  ", false)
	hud._text(c, font, Vector2(r.position.x, r.position.y + 14.0 * s), "USE FOR", HORIZONTAL_ALIGNMENT_LEFT, r.size.x, int(14.0 * s), Color(UiUtil.CYAN, 0.9), 1.0 * s)
	for i in mini(clauses.size(), 3):
		var t := String(clauses[i])
		hud._text(c, font, Vector2(r.position.x + 74.0 * s, r.position.y + (14.0 + 19.0 * float(i)) * s), t, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 120.0 * s, UiUtil.fit_size(font, t, r.size.x - 120.0 * s, int(15.0 * s)), Color(1, 1, 1, 0.93))


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
	hud._text(c, font, Vector2(tx, py + 80.0 * s), desc, HORIZONTAL_ALIGNMENT_LEFT, tw, UiUtil.fit_size(font, desc, tw, int(16.0 * s)), Color(1, 1, 1, 0.9))
	hud._text(c, font, Vector2(tx, py + 104.0 * s), "WHERE  SHOP  %d" % Economy.gear_price(sel) if (not own and not Gear.is_charge(sel)) else "WHERE  YOU HAVE IT", HORIZONTAL_ALIGNMENT_LEFT, tw, int(16.0 * s), Color(UiUtil.CYAN, 0.95))
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
