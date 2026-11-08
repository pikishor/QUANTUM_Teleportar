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
const PIC_H := 264.0
const BAR_Y := 480.0                      ## the four stat bars under the picture, two by two
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


## Weapons of the visible page (at most WeaponDefs.PAGE_SIZE).
static func page_items(sel: StringName) -> Array[StringName]:
	var ow := owned_weapons()
	if sel != _page_sel:
		_page_sel = sel
		if ow.has(sel):
			page = ow.find(sel) / WeaponDefs.PAGE_SIZE
	page = clampi(page, 0, WeaponDefs.pages_for(ow.size()) - 1)
	var out: Array[StringName] = []
	for i in range(page * WeaponDefs.PAGE_SIZE, mini(ow.size(), (page + 1) * WeaponDefs.PAGE_SIZE)):
		out.append(ow[i])
	return out


## Flip the page by dir (wraps). Returns true when there is more than one page.
static func flip(dir: int) -> bool:
	var n := WeaponDefs.pages_for(owned_weapons().size())
	if n < 2:
		return false
	page = posmod(page + dir, n)
	return true


static func reset_page() -> void:
	_page_sel = &""


static func layout(hud: Hud, cx: float, s: float, sel: StringName) -> void:
	var prog := Game.progress as Progress
	var k := k_of(hud.get_viewport().get_visible_rect().size.x, s)
	var items := page_items(sel)
	for i in items.size():                                         # the owned weapons as a column pair of tiles, each with its picture (the page flips with < >)
		var tp := Vector2(cx + (GRID_X + float(i % GRID_COLS) * (TILE.x + TILE_GAP)) * s * k, (GRID_Y + float(i / GRID_COLS) * (TILE.y + TILE_GAP)) * s)
		var ttl := WeaponDefs.title(items[i]).split(" ")
		hud.buttons.append({"id": StringName("wheel_%s" % items[i]), "rect": Rect2(tp, Vector2(TILE.x * k, TILE.y) * s), "label": String(WeaponDefs.def(items[i])["tag"]), "on": items[i] == sel, "cap": String(ttl[ttl.size() - 1])})
	if WeaponDefs.pages_for(owned_weapons().size()) > 1:
		var ar := arrow_rects(cx, s, k)
		hud._add(&"wheelpg_prev", ar[0], "<", false)
		hud._add(&"wheelpg_next", ar[1], ">", false)
	for si in Attachments.SLOTS.size():
		var parts := Attachments.parts_for(Attachments.SLOTS[si])
		for j in parts.size():
			var part := parts[j]
			var own := Attachments.part_in(sel, Attachments.SLOTS[si]) == part
			var label := "ON" if own else (("NEW  EQUIP" if MissionRewards.is_new(part) else "EQUIP") if Attachments.is_owned(part) else "BUY  %d" % (prog.part_price(part) if prog != null else 0))
			hud.buttons.append({"id": StringName("part_%s" % part), "rect": Rect2(cx + (SLOT_X + j * (PART_W + 8.0)) * s * k, (SLOT_Y + si * SLOT_STEP + 24.0) * s, PART_W * s * k, PART_H * s), "label": label, "on": own,
				"part": true, "name": String(Attachments.PARTS[part]["name"]), "fx": String(PART_FX.get(part, "")), "state": 2 if own else (1 if Attachments.is_owned(part) else 0)})
	var aw := (3.0 * PART_W + 2.0 * 8.0 - 8.0) * 0.5
	hud._add_card(&"loadout_gear", Rect2(cx + SLOT_X * s * k, ACTION_Y * s, aw * s * k, 64.0 * s), "GEAR", &"gear", "", false, UiUtil.MAGENTA)
	hud._add_card(&"loadout_info", Rect2(cx + (SLOT_X + aw + 8.0) * s * k, ACTION_Y * s, aw * s * k, 64.0 * s), "WEAPON INFO", &"weapon", "", false, UiUtil.CYAN)
	hud._add(&"loadout_back", Rect2(cx - 110.0 * s, 628.0 * s, 220.0 * s, 64.0 * s), "RESUME" if hud._loadout_quick else "BACK", false)


## The page arrows under the tile column: [previous, next].
static func arrow_rects(cx: float, s: float, k := 1.0) -> Array[Rect2]:
	var y := (GRID_Y + 4.0 * (TILE.y + TILE_GAP) + 4.0) * s
	var gw := (float(GRID_COLS) * TILE.x + float(GRID_COLS - 1) * TILE_GAP) * s * k
	return [Rect2(cx + GRID_X * s * k, y, 64.0 * s, 64.0 * s), Rect2(cx + GRID_X * s * k + gw - 64.0 * s, y, 64.0 * s, 64.0 * s)]


## The big card of the selected weapon: the picture (the 384 x 192 render `wl_<id>`, shown at 2 x its size on a phone) under the name, the class and the key numbers.
static func picture_rect(cx: float, s: float, k := 1.0) -> Rect2:
	return Rect2(cx + PIC_X * s * k, PIC_Y * s, PIC_W * s * k, PIC_H * s)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float, sel: StringName) -> void:
	var prog := Game.progress as Progress
	hud.header(c, vp, s, font, "LOADOUT")
	if prog != null:
		hud._text(c, font, Vector2(0.0, 134.0 * s), "CREDITS  %d" % prog.credits, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	var nx := WeaponLadder.next_line()
	if nx != "":
		hud._text(c, font, Vector2(0.0, 162.0 * s), nx, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	var d := Attachments.effective(sel)
	var card := WeaponStats.card(sel, d)
	var k := k_of(vp.x, s)
	# the big card: plate, name and class on top, the picture filling the rest, the numbers along the bottom
	var pic := picture_rect(cx, s, k)
	c.draw_rect(pic, Color(0.06, 0.085, 0.15, 1.0))
	c.draw_rect(pic, Color(UiUtil.CYAN, 0.45), false, 1.5 * s)
	var name := WeaponDefs.title(sel)
	var half := pic.size.x * 0.5
	hud._text(c, font, Vector2(pic.position.x + 14.0 * s, pic.position.y + 34.0 * s), name, HORIZONTAL_ALIGNMENT_LEFT, half + 40.0 * s, UiUtil.fit_size(font, name, half + 40.0 * s, int(30.0 * s)), Color(1, 1, 1, 0.98), 1.0 * s)
	hud._text(c, font, Vector2(pic.position.x + pic.size.x * 0.55, pic.position.y + 32.0 * s), String(card["class"]), HORIZONTAL_ALIGNMENT_RIGHT, pic.size.x * 0.45 - 14.0 * s, int(20.0 * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	var area := Rect2(pic.position.x + 6.0 * s, pic.position.y + 22.0 * s, pic.size.x - 12.0 * s, pic.size.y - 22.0 * s - 4.0 * s)
	ItemIcons.draw_weapon_large(c, sel, area, Color(1, 1, 1, 1.0))
	var ls := WeaponStats.lines(card)
	var nums := "   ".join(ls.slice(0, mini(3, ls.size())))
	hud._text(c, font, Vector2(pic.position.x, pic.end.y + 28.0 * s), nums, HORIZONTAL_ALIGNMENT_LEFT, pic.size.x, UiUtil.fit_size(font, nums, pic.size.x, int(UiUtil.BAR_LABEL * s)), Color(1, 1, 1, 0.92))
	# four stat bars, two by two
	var keys: Array[StringName] = [&"damage", &"rate", &"range", &"accuracy"]
	var colw := (pic.size.x - 12.0 * s) * 0.5
	for i in keys.size():
		var key: StringName = keys[i]
		var bx := pic.position.x + float(i % 2) * (colw + 12.0 * s)
		var by := (BAR_Y + float(i / 2) * 34.0) * s
		var lab: String = String(WeaponStats.BAR_NAMES[key]) if not (bool(card["melee"]) and key == &"range") else "REACH"
		hud._text(c, font, Vector2(bx, by + 20.0 * s), lab, HORIZONTAL_ALIGNMENT_LEFT, 120.0 * s, int(16.0 * s), Color(1, 1, 1, 0.9))
		var tr := Rect2(bx + 118.0 * s, by + 4.0 * s, colw - 118.0 * s, 18.0 * s)
		var v := float(card["bars"][key])
		c.draw_rect(tr, Color(1, 1, 1, 0.1))
		c.draw_rect(Rect2(tr.position, Vector2(tr.size.x * v, tr.size.y)), Color(UiUtil.CYAN, 0.92).lerp(Color(UiUtil.AMBER, 0.95), clampf((v - 0.55) * 2.0, 0.0, 1.0)))
		c.draw_rect(tr, Color(1, 1, 1, 0.25), false, 1.0 * s)
	# where to get it
	var wl := WeaponStats.where(sel)
	for i in mini(wl.size(), 2):
		var line := ("WHERE  " if i == 0 else "OR  ") + wl[i]
		hud._text(c, font, Vector2(pic.position.x, (INFO_Y + 30.0 * float(i)) * s), line, HORIZONTAL_ALIGNMENT_LEFT, pic.size.x, UiUtil.fit_size(font, line, pic.size.x, int(20.0 * s)), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	var np := WeaponDefs.pages_for(owned_weapons().size())
	if np > 1:
		var gw := (float(GRID_COLS) * TILE.x + float(GRID_COLS - 1) * TILE_GAP) * s * k
		hud._text(c, font, Vector2(cx + GRID_X * s * k, (GRID_Y + 4.0 * (TILE.y + TILE_GAP) + 4.0 + 40.0) * s), "PAGE %d / %d" % [page + 1, np], HORIZONTAL_ALIGNMENT_CENTER, gw, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)
	for si in Attachments.SLOTS.size():
		var y := (SLOT_Y + si * SLOT_STEP) * s
		hud._text(c, font, Vector2(cx + SLOT_X * s * k, y + 16.0 * s), String(Attachments.SLOTS[si]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 200.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)
