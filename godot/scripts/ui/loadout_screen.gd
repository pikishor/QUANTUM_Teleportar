class_name LoadoutScreen
extends RefCounted
## Weapon wheel and attachment loadout (Hud draws it on the pause screen when `_loadout_open`). Left: a wheel of the owned weapons (buttons `wheel_<id>`, tap = swap to it;
## opened from a SWAP long-press it resumes the game at once). Right: the three slots (optic, barrel, core) of the selected weapon, three parts each (buttons `part_<id>`:
## BUY price, EQUIP, or ON to take it off). `loadout_back` returns. State lives in Hud (`_loadout_w`, `_loadout_quick`), numbers in Attachments and Progress.

const GRID_X := -726.0                    ## left edge of the weapon tile column, base px from the screen centre (docs/DESIGN.md: a LARGE picture, bars, where to get it)
const GRID_Y := 176.0
const GRID_COLS := 2
const TILE := Vector2(132.0, 72.0)        ## a weapon tile (picture over its name), at least the 64 px touch minimum
const TILE_GAP := 8.0
const PIC_X := -438.0                     ## the big card of the selected weapon: picture, name, class, numbers (x from the centre, y, size in base px)
const PIC_Y := 176.0
const PIC_W := 580.0
const PIC_H := 248.0
const BAR_Y := 492.0                      ## the four stat bars under the picture, two by two (a compare caption sits between the numbers and the bars)
const INFO_Y := 580.0                     ## baseline of the first "where to get it" line
const SLOT_X := 160.0                     ## the three attachment slots (right column)
const SLOT_Y := 198.0                     ## (was 178: the OPTIC caption touched the NEXT line above it, director review 3 #12)
const SLOT_STEP := 114.0
const PART_W := 184.0
const PART_H := 80.0
const ACTION_Y := 542.0                   ## GEAR and INFO under the slots
const PART_FX := {&"reddot": "Steadier aim", &"scope": "Zoom, steady aim", &"halo": "Hip aim, crits", &"suppressor": "Quiet, less kick", &"longbarrel": "Longer range", &"compensator": "Less recoil",
	&"overcharge": "More damage", &"rapid": "Faster fire", &"extended": "Bigger magazine"}
const PART_CAPTION := 18.0                ## base px of the part names under the BUY / EQUIP buttons (was 14: unreadable on a phone)

## The paged wheel: WeaponDefs.PAGE_SIZE weapons per page, buttons `wheelpg_prev` / `wheelpg_next` flip it. The page follows the selected weapon until a flip.
static var page := 0
static var _page_sel: StringName = &""


const WIDTH := 1454.0                     ## base px the three columns span (squeezed horizontally by `k` on a narrower, 16:9 screen)


## The horizontal squeeze that makes the three columns fit the screen width (1 on a phone, about 0.85 on 16:9).
static func k_of(vp_x: float, s: float) -> float:
	return clampf((vp_x / s - 40.0) / WIDTH, 0.6, 1.0)


static func owned_weapons() -> Array[StringName]:
	return WeaponDefs.owned_ordered()


## The class tabs of the loadout: every weapon class the hero owns something in, in WeaponDefs.CLASS_ORDER (FAVOURITES and RECENT are tabs of the browser, not classes).
static func owned_classes() -> Array[StringName]:
	var out: Array[StringName] = []
	for cls: StringName in WeaponDefs.CLASS_ORDER:
		if not WeaponDefs.owned_in_class(cls).is_empty():
			out.append(cls)
	return out


## Every page of every tab (scripts/ui/weapon_browser.gd): FAVOURITES, RECENT, then each class eight weapons at a time. One page = at most the 2 x 4 tiles of the grid.
static func pages() -> Array[Dictionary]:
	return WeaponBrowser.pages(true, WeaponBrowser.PAGE)


static func page_count() -> int:
	return maxi(1, pages().size())


## Weapons of the visible page. The page follows the selected weapon (into its class tab) until a flip.
static func page_items(sel: StringName) -> Array[StringName]:
	var ps := pages()
	var out: Array[StringName] = []
	if ps.is_empty():
		return out
	if sel != _page_sel:
		_page_sel = sel
		var at := WeaponBrowser.page_of(sel)
		if at >= 0:
			page = at
	page = clampi(page, 0, ps.size() - 1)
	out.assign(ps[page]["ids"])
	return out


## Show the page of weapon `id` now (the page stays until the selected weapon changes or a flip).
static func goto(id: StringName) -> void:
	var at := WeaponBrowser.page_of(id)
	if at >= 0:
		page = at


## The name of the visible tab ("RIFLE", "FAVOURITES").
static func page_name() -> String:
	var ps := pages()
	return String(ps[clampi(page, 0, ps.size() - 1)]["name"]) if not ps.is_empty() else ""


## How many weapons the visible tab holds in all (the caption of the class row).
static func tab_size() -> int:
	var ps := pages()
	if ps.is_empty():
		return 0
	var cur: Dictionary = ps[clampi(page, 0, ps.size() - 1)]
	var n := 0
	for p: Dictionary in ps:
		if p["tab"] == cur["tab"]:
			n += (p["ids"] as Array).size()
	return n


## "PAGE 2 / 4" of the visible tab ("" when the tab is a single page).
static func sub_caption() -> String:
	var ps := pages()
	if ps.is_empty():
		return ""
	var cur: Dictionary = ps[clampi(page, 0, ps.size() - 1)]
	return "PAGE %d / %d" % [int(cur["sub"]) + 1, int(cur["subs"])]


## Flip the page by dir through every page of every tab (wraps). Returns true when there is more than one page.
static func flip(dir: int) -> bool:
	var n := page_count()
	if n < 2:
		return false
	page = posmod(page + dir, n)
	return true


## Jump to the first page of the next (dir 1) or previous (dir -1) tab. Returns true when there is more than one tab.
static func flip_class(dir: int) -> bool:
	if tab_count() < 2:
		return false
	page = WeaponBrowser.tab_jump(page, dir)
	return true


static func tab_count() -> int:
	return WeaponBrowser.tabs(true).size()


static func reset_page() -> void:
	_page_sel = &""


static func layout(hud: Hud, cx: float, s: float, sel: StringName) -> void:
	var prog := Game.progress as Progress
	var k := k_of(hud.get_viewport().get_visible_rect().size.x, s)
	var items := page_items(sel)
	var lasts := {}                                                # the caption under a tile is the last word of the name ("CANNON"), the first word when that is ambiguous on this tab
	for id in items:
		var lw := String(WeaponDefs.title(id).split(" ")[-1])
		lasts[lw] = int(lasts.get(lw, 0)) + 1
	for i in items.size():                                         # the owned weapons as a column pair of tiles, each with its picture (the page flips with < >)
		var tp := Vector2(cx + (GRID_X + float(i % GRID_COLS) * (TILE.x + TILE_GAP)) * s * k, (GRID_Y + float(i / GRID_COLS) * (TILE.y + TILE_GAP)) * s)
		var ttl := WeaponDefs.title(items[i]).split(" ")
		hud.buttons.append({"id": StringName("wheel_%s" % items[i]), "rect": Rect2(tp, Vector2(TILE.x * k, TILE.y) * s), "label": String(WeaponDefs.def(items[i])["tag"]), "on": items[i] == sel, "cap": _caption(ttl, lasts, String(WeaponDefs.def(items[i])["tag"]))})
	if page_count() > 1:
		var ar := arrow_rects(cx, s, k)
		hud._add(&"wheelpg_prev", ar[0], "<", false)
		hud._add(&"wheelpg_next", ar[1], ">", false)
	if tab_count() > 1:                                            # the class row above the grid: jump to the next / previous class (FAVOURITES and RECENT first when they hold something)
		var cr := class_rects(cx, s, k)
		hud._add(&"wheelcls_prev", cr[0], "<", false)
		hud._add(&"wheelcls_next", cr[1], ">", false)
	hud.buttons.append({"id": &"fav_toggle", "rect": star_rect(cx, s, k), "label": "", "on": WeaponBrowser.is_favourite(sel), "own": true})
	for si in Attachments.SLOTS.size():
		var parts := Attachments.parts_for(Attachments.SLOTS[si])
		for j in parts.size():
			var part := parts[j]
			var own := Attachments.part_in(sel, Attachments.SLOTS[si]) == part
			var label := "ON" if own else (("NEW  EQUIP" if MissionRewards.is_new(part) else "EQUIP") if Attachments.is_owned(part) else "BUY  %d" % (prog.part_price(part) if prog != null else 0))
			hud.buttons.append({"id": StringName("part_%s" % part), "rect": Rect2(cx + (SLOT_X + j * (PART_W + 8.0)) * s * k, (SLOT_Y + si * SLOT_STEP + 24.0) * s, PART_W * s * k, PART_H * s), "label": label, "on": own,
				"part": true, "name": String(Attachments.PARTS[part]["name"]), "fx": String(PART_FX.get(part, "")), "state": 2 if own else (1 if Attachments.is_owned(part) else 0)})
	var aw := (3.0 * PART_W + 2.0 * 8.0 - 72.0 - 8.0) * 0.5              # GEAR and WEAPON INFO share the row with the 64 px star
	hud._add_card(&"loadout_gear", Rect2(cx + SLOT_X * s * k, ACTION_Y * s, aw * s * k, 64.0 * s), "GEAR", &"gear", "", false, UiUtil.MAGENTA)
	hud._add_card(&"loadout_info", Rect2(cx + (SLOT_X + aw + 8.0) * s * k, ACTION_Y * s, aw * s * k, 64.0 * s), "WEAPON INFO", &"weapon", "", false, UiUtil.CYAN)
	hud._add(&"loadout_back", Rect2(cx - 110.0 * s, 628.0 * s, 220.0 * s, 64.0 * s), "RESUME" if hud._loadout_quick else "BACK", false)


## The caption of a weapon tile: the last word of its name, unless another weapon on the tab ends the same way or it is a bare "GUN" (then the first word, or the tag when that is long).
static func _caption(words: PackedStringArray, lasts: Dictionary, tag: String) -> String:
	var last := String(words[words.size() - 1])
	if words.size() == 1 or (int(lasts.get(last, 0)) < 2 and last != "GUN"):
		return last
	var first := String(words[0])
	return first if first.length() <= 9 else tag


## The class chips above the tile column: [previous, next] (64 px each, the class name sits between them).
static func class_rects(cx: float, s: float, k := 1.0) -> Array[Rect2]:
	var y := 106.0 * s
	var gw := (float(GRID_COLS) * TILE.x + float(GRID_COLS - 1) * TILE_GAP) * s * k
	return [Rect2(cx + GRID_X * s * k, y, 64.0 * s, 64.0 * s), Rect2(cx + GRID_X * s * k + gw - 64.0 * s, y, 64.0 * s, 64.0 * s)]


## The star button of the selected weapon (favourite on / off): in the row of GEAR and WEAPON INFO.
static func star_rect(cx: float, s: float, k := 1.0) -> Rect2:
	return Rect2(cx + (SLOT_X + 3.0 * PART_W + 16.0 - 64.0) * s * k, ACTION_Y * s, 64.0 * s, 64.0 * s)


## The page arrows under the tile column: [previous, next].
static func arrow_rects(cx: float, s: float, k := 1.0) -> Array[Rect2]:
	var y := (GRID_Y + 4.0 * (TILE.y + TILE_GAP) + 4.0) * s
	var gw := (float(GRID_COLS) * TILE.x + float(GRID_COLS - 1) * TILE_GAP) * s * k
	return [Rect2(cx + GRID_X * s * k, y, 64.0 * s, 64.0 * s), Rect2(cx + GRID_X * s * k + gw - 64.0 * s, y, 64.0 * s, 64.0 * s)]


## The big card of the selected weapon: the picture (the 384 x 192 render `wl_<id>`, shown at 2 x its size on a phone) under the name, the class and the key numbers.
static func picture_rect(cx: float, s: float, k := 1.0) -> Rect2:
	return Rect2(cx + PIC_X * s * k, PIC_Y * s, PIC_W * s * k, PIC_H * s)


## The weapon the player holds now, when it is not the selected one: the stat bars compare the selection against it (white marker and a +/- number).
static func compare_id(sel: StringName) -> StringName:
	var cur := WeaponDefs.last_used
	return cur if (cur != sel and WeaponDefs.DEFS.has(cur) and WeaponDefs.is_unlocked(cur)) else &""


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float, sel: StringName) -> void:
	var prog := Game.progress as Progress
	hud.header(c, vp, s, font, "LOADOUT")
	if prog != null:
		hud._text(c, font, Vector2(0.0, 134.0 * s), "CREDITS  %d" % prog.credits, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
		var cw := hud._text_width(font, "CREDITS  %d" % prog.credits, int(UiUtil.TEXT_MIN * s))
		UiKit.glyph(c, &"coin", Vector2(vp.x * 0.5 - cw * 0.5 - 22.0 * s, 124.0 * s), 11.0 * s, Color(UiUtil.AMBER, 0.95), s)
	var nx := WeaponLadder.next_line()
	if nx != "":
		hud._text(c, font, Vector2(0.0, 162.0 * s), nx, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	var d := Attachments.effective(sel)
	var card := WeaponStats.card(sel, d)
	var k := k_of(vp.x, s)
	var tint := UiKit.class_tint(WeaponDefs.class_of(sel))
	# the big card: the 3D weapon on a turntable (drag to turn, tap for the side view), name and class on top, the numbers along the bottom
	var pic := picture_rect(cx, s, k)
	UiKit.panel(c, pic, s, tint, false, 12.0, true)
	var area := Rect2(pic.position.x + 8.0 * s, pic.position.y + 40.0 * s, pic.size.x - 16.0 * s, pic.size.y - 40.0 * s - 8.0 * s)
	var pv := WeaponPreview.of(hud)
	if pv.show_weapon(sel):
		c.draw_rect(area, Color(tint, 0.07))
		c.draw_line(Vector2(area.position.x + 20.0 * s, area.end.y - 22.0 * s), Vector2(area.end.x - 20.0 * s, area.end.y - 22.0 * s), Color(tint, 0.25), 2.0 * s)
		pv.draw(c, area)
		hud.preview_rect = area
		UiKit.glyph(c, &"rotate", Vector2(area.end.x - 18.0 * s, area.end.y - 18.0 * s), 9.0 * s, Color(1, 1, 1, 0.6), s)
	else:
		ItemIcons.draw_weapon_large(c, sel, area, Color(1, 1, 1, 1.0))
	var name := WeaponDefs.title(sel)
	var half := pic.size.x * 0.5
	hud._text(c, font, Vector2(pic.position.x + 18.0 * s, pic.position.y + 32.0 * s), name, HORIZONTAL_ALIGNMENT_LEFT, half + 40.0 * s, UiUtil.fit_size(font, name, half + 40.0 * s, int(30.0 * s)), Color(1, 1, 1, 0.98), 1.0 * s)
	UiKit.badge(hud, c, Vector2(pic.end.x - 12.0 * s, pic.position.y + 24.0 * s), String(card["class"]), tint, s, font, true, true)
	var ls := WeaponStats.lines(card)
	var nums := "   ".join(ls.slice(0, mini(3, ls.size())))
	var nmax := mini(3, ls.size())
	while nmax > 1 and font.get_string_size(nums, HORIZONTAL_ALIGNMENT_LEFT, -1, int(UiUtil.BAR_LABEL * s)).x > pic.size.x:
		nmax -= 1                                              # a narrow screen shows fewer numbers instead of running into the part cards
		nums = "   ".join(ls.slice(0, nmax))
	hud._text(c, font, Vector2(pic.position.x, pic.end.y + 28.0 * s), nums, HORIZONTAL_ALIGNMENT_LEFT, pic.size.x, UiUtil.fit_size(font, nums, pic.size.x, int(UiUtil.BAR_LABEL * s)), Color(1, 1, 1, 0.92))
	# four stat bars, two by two; against the weapon in hand when it is another one
	var cmp := compare_id(sel)
	var cbars := {}
	if cmp != &"":
		cbars = WeaponStats.card(cmp, Attachments.effective(cmp))["bars"]
		var cap := "VS IN HAND  %s" % WeaponDefs.title(cmp)
		hud._text(c, font, Vector2(pic.position.x, pic.end.y + 54.0 * s), cap, HORIZONTAL_ALIGNMENT_LEFT, pic.size.x, UiUtil.fit_size(font, cap, pic.size.x, int(Hud.BODY_MIN * s)), Color(1, 1, 1, 0.72))
	else:
		hud._text(c, font, Vector2(pic.position.x, pic.end.y + 54.0 * s), "IN YOUR HAND", HORIZONTAL_ALIGNMENT_LEFT, pic.size.x, int(Hud.BODY_MIN * s), Color(UiUtil.GREEN, 0.85))
	var keys: Array[StringName] = [&"damage", &"rate", &"range", &"accuracy"]
	var colw := (pic.size.x - 12.0 * s) * 0.5
	for i in keys.size():
		var key: StringName = keys[i]
		var bx := pic.position.x + float(i % 2) * (colw + 12.0 * s)
		var by := (BAR_Y + float(i / 2) * 36.0) * s
		var lab: String = String(WeaponStats.BAR_NAMES[key]) if not (bool(card["melee"]) and key == &"range") else "REACH"
		UiKit.stat_bar(hud, c, Rect2(bx, by, colw, 28.0 * s), lab, float(card["bars"][key]), s, font, 102.0 * s, float(cbars[key]) if cmp != &"" else -1.0)
	# where to get it
	var wl := WeaponStats.where(sel)
	for i in mini(wl.size(), 2):
		var wy := (INFO_Y + 34.0 * float(i)) * s
		var tag := UiKit.badge(hud, c, Vector2(pic.position.x, wy - 7.0 * s), "WHERE" if i == 0 else "OR", UiUtil.MAGENTA, s, font)
		var line: String = wl[i]
		var lw := pic.size.x - tag.size.x - 10.0 * s
		hud._text(c, font, Vector2(tag.end.x + 10.0 * s, wy), line, HORIZONTAL_ALIGNMENT_LEFT, lw, UiUtil.fit_size(font, line, lw, int(20.0 * s)), Color(UiUtil.CYAN, 0.97), 1.0 * s)
	var trait_line := WeaponRoster.trait_text(sel)
	if trait_line != "":
		hud._text(c, font, Vector2(pic.position.x + 18.0 * s, pic.position.y + pic.size.y - 14.0 * s), trait_line, HORIZONTAL_ALIGNMENT_LEFT, pic.size.x - 70.0 * s, UiUtil.fit_size(font, trait_line, pic.size.x - 70.0 * s, int(18.0 * s)), Color(UiUtil.MAGENTA, 0.97), 1.0 * s)
	var np := page_count()
	var gw := (float(GRID_COLS) * TILE.x + float(GRID_COLS - 1) * TILE_GAP) * s * k
	var tint_c := UiKit.class_tint(WeaponDefs.class_of(sel))
	if tab_count() > 1:                                                  # the class row: the tab name and how many weapons it holds, between the two chips
		var cap := "%s  %d" % [page_name(), tab_size()]
		var cwc := gw - 144.0 * s
		hud._text(c, font, Vector2(cx + GRID_X * s * k + 72.0 * s, 106.0 * s + 40.0 * s), cap, HORIZONTAL_ALIGNMENT_CENTER, cwc, UiUtil.fit_size(font, cap, cwc, int(UiUtil.BAR_LABEL * s)), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	else:
		hud._text(c, font, Vector2(cx + GRID_X * s * k, 106.0 * s + 40.0 * s), "%s  %d" % [page_name(), tab_size()], HORIZONTAL_ALIGNMENT_LEFT, gw, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	if np > 1:
		var cap2 := sub_caption()                                        # between the two page arrows
		var cw2 := gw - 136.0 * s
		hud._text(c, font, Vector2(cx + GRID_X * s * k + 68.0 * s, (GRID_Y + 4.0 * (TILE.y + TILE_GAP) + 4.0 + 40.0) * s), cap2, HORIZONTAL_ALIGNMENT_CENTER, cw2, UiUtil.fit_size(font, cap2, cw2, int(UiUtil.BAR_LABEL * s)), Color(tint_c.lerp(Color.WHITE, 0.3), 0.97), 1.0 * s)
	var sr := star_rect(cx, s, k)                                       # the star: a favourite is filled amber, else an outline
	var fav := WeaponBrowser.is_favourite(sel)
	UiKit.panel(c, sr, s, UiUtil.AMBER if fav else UiKit.class_tint(WeaponDefs.class_of(sel)), fav, 8.0, fav)
	var pts := PackedVector2Array()
	var sc := sr.get_center()
	for q in 10:
		var ang := -PI * 0.5 + TAU * float(q) / 10.0
		var rr := (22.0 if q % 2 == 0 else 9.0) * s
		pts.append(sc + Vector2(cos(ang), sin(ang)) * rr)
	if fav:
		c.draw_colored_polygon(pts, Color(UiUtil.AMBER, 0.97))
	else:
		pts.append(pts[0])
		c.draw_polyline(pts, Color(1, 1, 1, 0.8), 2.0 * s)
	for si in Attachments.SLOTS.size():
		var y := (SLOT_Y + si * SLOT_STEP) * s
		hud._text(c, font, Vector2(cx + SLOT_X * s * k, y + 16.0 * s), String(Attachments.SLOTS[si]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 200.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)
