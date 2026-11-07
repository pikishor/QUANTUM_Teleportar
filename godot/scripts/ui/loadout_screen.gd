class_name LoadoutScreen
extends RefCounted
## Weapon wheel and attachment loadout (Hud draws it on the pause screen when `_loadout_open`). Left: a wheel of the owned weapons (buttons `wheel_<id>`, tap = swap to it;
## opened from a SWAP long-press it resumes the game at once). Right: the three slots (optic, barrel, core) of the selected weapon, three parts each (buttons `part_<id>`:
## BUY price, EQUIP, or ON to take it off). `loadout_back` returns. State lives in Hud (`_loadout_w`, `_loadout_quick`), numbers in Attachments and Progress.

const GRID_X := -560.0                    ## left edge of the weapon grid, base px from the screen centre
const GRID_Y := 196.0
const GRID_COLS := 4
const TILE := Vector2(124.0, 72.0)        ## a weapon tile (icon over its tag), at least the 64 px touch minimum
const TILE_GAP := 8.0
const INFO_Y := 396.0                     ## the selected weapon's name (the stats line and the page buttons follow)
const SLOT_Y := 178.0
const SLOT_STEP := 114.0
const PART_W := 190.0
const PART_H := 80.0
const PART_FX := {&"reddot": "Steadier aim", &"scope": "Zoom, steady aim", &"halo": "Hip aim, crits", &"suppressor": "Quiet, less kick", &"longbarrel": "Longer range", &"compensator": "Less recoil",
	&"overcharge": "More damage", &"rapid": "Faster fire", &"extended": "Bigger magazine"}
const PART_CAPTION := 18.0                ## base px of the part names under the BUY / EQUIP buttons (was 14: unreadable on a phone)

## The paged wheel: WeaponDefs.PAGE_SIZE weapons per page, buttons `wheelpg_prev` / `wheelpg_next` flip it. The page follows the selected weapon until a flip.
static var page := 0
static var _page_sel: StringName = &""


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
	var items := page_items(sel)
	for i in items.size():                                         # the owned weapons as a grid of tiles (the page flips with < >)
		var tp := Vector2(cx + (GRID_X + float(i % GRID_COLS) * (TILE.x + TILE_GAP)) * s, (GRID_Y + float(i / GRID_COLS) * (TILE.y + TILE_GAP)) * s)
		var ttl := WeaponDefs.title(items[i]).split(" ")
		hud.buttons.append({"id": StringName("wheel_%s" % items[i]), "rect": Rect2(tp, TILE * s), "label": String(WeaponDefs.def(items[i])["tag"]), "on": items[i] == sel, "cap": String(ttl[ttl.size() - 1])})
	if WeaponDefs.pages_for(owned_weapons().size()) > 1:
		hud._add(&"wheelpg_prev", Rect2(cx + GRID_X * s, (INFO_Y + 62.0) * s, 64.0 * s, 64.0 * s), "<", false)
		hud._add(&"wheelpg_next", Rect2(cx + (GRID_X + 4.0 * TILE.x + 3.0 * TILE_GAP - 64.0) * s, (INFO_Y + 62.0) * s, 64.0 * s, 64.0 * s), ">", false)
	for k in Attachments.SLOTS.size():
		var parts := Attachments.parts_for(Attachments.SLOTS[k])
		for j in parts.size():
			var part := parts[j]
			var own := Attachments.part_in(sel, Attachments.SLOTS[k]) == part
			var label := "ON" if own else ("EQUIP" if Attachments.is_owned(part) else "BUY  %d" % (prog.part_price(part) if prog != null else 0))
			hud.buttons.append({"id": StringName("part_%s" % part), "rect": Rect2(cx + (20.0 + j * (PART_W + 8.0)) * s, (SLOT_Y + k * SLOT_STEP + 24.0) * s, PART_W * s, PART_H * s), "label": label, "on": own,
				"part": true, "name": String(Attachments.PARTS[part]["name"]), "fx": String(PART_FX.get(part, "")), "state": 2 if own else (1 if Attachments.is_owned(part) else 0)})
	hud._add_card(&"loadout_gear", Rect2(cx + 20.0 * s, 536.0 * s, 240.0 * s, 64.0 * s), "GEAR", &"gear", "", false, UiUtil.MAGENTA)
	hud._add(&"loadout_back", Rect2(cx - 110.0 * s, 612.0 * s, 220.0 * s, 64.0 * s), "RESUME" if hud._loadout_quick else "BACK", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float, sel: StringName) -> void:
	var prog := Game.progress as Progress
	hud.header(c, vp, s, font, "LOADOUT")
	if prog != null:
		hud._text(c, font, Vector2(0.0, 134.0 * s), "CREDITS  %d" % prog.credits, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	var gw := (4.0 * TILE.x + 3.0 * TILE_GAP) * s
	hud._text(c, font, Vector2(cx + GRID_X * s, INFO_Y * s), WeaponDefs.title(sel), HORIZONTAL_ALIGNMENT_CENTER, gw, int(26.0 * s), Color(UiUtil.CYAN, 0.97), 1.0 * s)
	var np := WeaponDefs.pages_for(owned_weapons().size())
	if np > 1:
		hud._text(c, font, Vector2(cx + GRID_X * s, (INFO_Y + 104.0) * s), "PAGE %d / %d" % [page + 1, np], HORIZONTAL_ALIGNMENT_CENTER, gw, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)
	var nx := WeaponLadder.next_line()
	if nx != "":
		hud._text(c, font, Vector2(0.0, 166.0 * s), nx, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	var d := Attachments.effective(sel)
	hud._text(c, font, Vector2(cx + GRID_X * s, (INFO_Y + 34.0) * s), "DMG %d    MAG %d" % [int(roundf(float(d["damage"]))), int(d["mag"])], HORIZONTAL_ALIGNMENT_CENTER, gw, int(UiUtil.BAR_LABEL * s), Color(1, 1, 1, 0.9), 1.0 * s)
	for k in Attachments.SLOTS.size():
		var y := (SLOT_Y + k * SLOT_STEP) * s
		hud._text(c, font, Vector2(cx + 20.0 * s, y + 16.0 * s), String(Attachments.SLOTS[k]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 200.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)
