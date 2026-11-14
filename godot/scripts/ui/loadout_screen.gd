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
const BAR_Y := 492.0                      ## the four stat bars under the picture, two by two (a compare caption sits between the numbers and the bars)
const INFO_Y := 580.0                     ## baseline of the first "where to get it" line
const SLOT_X := 160.0                     ## the three attachment slots (right column)
const SLOT_Y := 198.0                     ## (was 178: the OPTIC caption touched the NEXT line above it, director review 3 #12)
const SLOT_STEP := 114.0
const PART_W := 184.0
const PART_H := 80.0
const ACTION_Y := 542.0                   ## GEAR and INFO under the slots
const TAB_H := 64.0                       ## the slot tabs (OPTIC, MUZZLE, GRIP, MAGAZINE, LASER) above the part cards; one slot is open at a time
const PART_ROW_Y := 276.0                 ## the first row of part cards (three to a row, a second row for a slot with more than three parts)
const FITTED_Y := 482.0                   ## the line "FITTED  RED DOT  DAMPER ..." under the cards
const PART_CAPTION := 18.0                ## base px of the part names under the BUY / EQUIP buttons (was 14: unreadable on a phone)

## The paged wheel: WeaponDefs.PAGE_SIZE weapons per page, buttons `wheelpg_prev` / `wheelpg_next` flip it. The page follows the selected weapon until a flip.
static var page := 0
static var _page_sel: StringName = &""
static var slot_tab: StringName = &"optic"                          ## the open slot of the attachment column (`slot_<id>` buttons)


const WIDTH := 1454.0                     ## base px the three columns span (squeezed horizontally by `k` on a narrower, 16:9 screen)


## The horizontal squeeze that makes the screen fit the screen width (1 on a 16:9 phone and wider).
static func k_of(vp_x: float, s: float) -> float:
	return Arsenal.k_of(Vector2(vp_x, 0.0), s)                                    # wave 114: the Arsenal's squeeze (its three columns span 1240 base px)


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
	Arsenal.layout(hud, cx, s, &"loadout")                         # wave 114: the Arsenal draws this screen (scripts/ui/arsenal.gd); the tile geometry below is the old paged loadout
	return


## The open slot of the attachment column for weapon `sel`: the tab that was opened last when this weapon can wear something in it, else its first slot (&"" when it can wear nothing at all).
static func active_slot(sel: StringName) -> StringName:
	var slots := Attachments.slots_for_weapon(sel)
	if slots.is_empty():
		return &""
	return slot_tab if slots.has(slot_tab) else slots[0]


## The slot tabs: `n` equal tabs across the width of the three part columns.
static func tab_rects(cx: float, s: float, k: float, n: int) -> Array[Rect2]:
	var gap := 6.0
	var total := 3.0 * PART_W + 2.0 * 8.0
	var w := (total - gap * float(n - 1)) / float(maxi(n, 1))
	var out: Array[Rect2] = []
	for i in n:
		out.append(Rect2(cx + (SLOT_X + float(i) * (w + gap)) * s * k, SLOT_Y * s, w * s * k, TAB_H * s))
	return out


## The part card `j` of the open slot: three to a row.
static func part_rect(cx: float, s: float, k: float, j: int) -> Rect2:
	return Rect2(cx + (SLOT_X + float(j % 3) * (PART_W + 8.0)) * s * k, (PART_ROW_Y + float(j / 3) * (PART_H + 8.0)) * s, PART_W * s * k, PART_H * s)


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


## The caption of the class row: "SHOTGUN  12" (the tab and how many weapons it holds), else just "SHOTGUN", else its first letters, whichever fits between the two chips at the smallest
## menu size (the room is 5.9 em on a 16:9 screen and a wide device font needs more: Hud._text would let the box grow into the chips; wave 113 CI).
static func class_caption(font: Font, width: float, s: float) -> String:
	var floor_px := int(Hud.BODY_MIN * s)
	var named := Tr.t(page_name())
	for cand: String in ["%s  %d" % [named, tab_size()], named]:
		if font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1.0, floor_px).x <= width:
			return cand
	return UiUtil.fit_text(font, named, width, floor_px)


## The big card of the selected weapon: the picture plate (650 x 240 base px on the STATS tab; the atlas card picture is 512 x 256) under the name, the class and the key numbers.
static func picture_rect(cx: float, s: float, k := 1.0, tab: StringName = &"stats") -> Rect2:
	return Rect2(cx + Arsenal.CARD_X * s * k, Arsenal.TOP * s, Arsenal.CARD_W * s * k, Arsenal.pic_h(tab) * s)              # wave 114: the card of the Arsenal (the picture plate over the tabs)


## The weapon the player holds now, when it is not the selected one: the stat bars compare the selection against it (white marker and a +/- number).
static func compare_id(sel: StringName) -> StringName:
	var cur := WeaponDefs.last_used
	return cur if (cur != sel and WeaponDefs.DEFS.has(cur) and WeaponDefs.is_unlocked(cur)) else &""


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float, sel: StringName) -> void:
	Arsenal.draw(hud, c, vp, s, font, cx, &"loadout")
	return
