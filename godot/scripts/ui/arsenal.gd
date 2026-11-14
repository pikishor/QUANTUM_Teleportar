class_name Arsenal
extends RefCounted
## THE ARSENAL (wave 114): one weapon screen behind both entry points, the pause menu's LOADOUT and the HERO hub's WEAPONS tab (LoadoutScreen / WeaponsScreen delegate to it; `mode` is
## &"loadout" or &"catalogue"). 200+ weapons are browsed, not paged: a scrolling grid of picture tiles (VIRTUALISED: only the rows on screen exist as tiles and buttons, a drag or a flick scrolls,
## the mouse wheel too), FILTER chips (ALL, OWNED, NEW, LOCKED, FAVS), a CLASS row (previous, next, the class name) and a SORT chip (class, name, damage, range, fire rate, price). The selected weapon
## is read on a CARD (scripts/ui/arsenal_card.gd): its picture on the class backdrop, seven stat bars with a compare marker against the weapon in hand, the range / blast rings to scale beside a
## person (scripts/ui/weapon_rings.gd), tabs STATS / PARTS (attachments with a live stat preview) / AMMO (ammo types), the action (EQUIP, BUY, IN HAND). The bottom bar holds BACK, the four
## LOADOUT SLOTS (LoadoutSlots: the quick swap walks them), the star (favourite) and the action. The catalogue also lists the throwables and gadgets of Gear as two more classes.
## Ids: tiles keep the old ones (`wheel_<id>` in the loadout, `wsel_<id>` in the catalogue; a tap SELECTS, it never equips), chips `ars_filter_<f>`, `ars_cls_prev` / `ars_cls_next`, `ars_sort`,
## `ars_tab_<t>`, `ars_view3d`, `ars_slot_<i>`, `ars_part_<id>` (parts), `ars_ammo_<i>`, `ars_slottab_<slot>`, `ars_equip`, `ars_bench`, `ars_star`; the catalogue's action keeps `buy_<id>` / `wequip_<id>` / `wgear_<id>`.
## State is static per mode (the filter, class, sort, tab and scroll survive closing the screen). Tests: tests/test_weapon_ui_v3.gd.

const W := 1240.0                       ## base px the layout spans (squeezed horizontally by k on a narrower screen)
const LIST_X := -620.0
const LIST_W := 572.0
const CARD_X := -30.0
const CARD_W := 650.0
const TOP := 78.0
const CHIP := 64.0
const LIST_Y := 214.0
const BOTTOM := 634.0
const TILE_W := 186.0
const TILE_H := 134.0
const TILE_GAP := 6.0
const COLS := 3
const ROW := TILE_H + TILE_GAP
const PIC_BIG := 240.0
const PIC_SMALL := 150.0
const ACTION_Y := 640.0

const FILTERS: Array = [[&"all", "ALL"], [&"owned", "OWNED"], [&"new", "NEW"], [&"locked", "LOCKED"], [&"fav", "FAVS"]]
const SORTS: Array = [[&"class", "CLASS"], [&"name", "NAME"], [&"damage", "DAMAGE"], [&"range", "RANGE"], [&"rate", "FIRE RATE"], [&"price", "PRICE"]]
const TABS: Array = [[&"stats", "STATS"], [&"parts", "PARTS"], [&"ammo", "AMMO"]]
const GEAR_CLASSES: Array[StringName] = [&"explosives", &"gadgets"]            ## the catalogue's two classes of Gear items
const CLASS_LABEL := {&"": "ALL", &"pistol": "PISTOL", &"smg": "SMG", &"rifle": "RIFLE", &"shotgun": "SHOTGUN", &"sniper": "SNIPER", &"heavy": "HEAVY", &"melee": "MELEE", &"quantum": "QUANTUM", &"energy": "ENERGY", &"blast": "BLAST", &"explosives": "EXPLOSIVES", &"gadgets": "GADGETS"}

static var _st := {}
static var view3d := false              ## the card's picture is the live 3D turntable (WeaponPreview) instead of the rendered picture
static var _gest := {}                  ## the finger on the list: {pos, last, moved, mode}
static var _list_cache_key := ""
static var _list_cache: Array[StringName] = []
static var _sort_vals := {}
static var sel_at := -100.0             ## Hud._t when the selection last changed (the card animates in)
static var taps := 0                    ## tile taps handled (tests wait on it)
static var list_rect := Rect2()         ## the list's area on screen after the last layout (the gesture tests it)
static var _disp := {}                  ## the bars as they are shown: key -> displayed value (they glide to the value of the selected weapon)
static var _disp_id: StringName = &""
static var drag_scrolls := 0            ## drags that scrolled the list (tests)
static var _active: StringName = &""    ## the mode whose screen is open (&"" none): a screen that opens again starts from its defaults


static func st(mode: StringName) -> Dictionary:
	if not _st.has(mode):
		_st[mode] = {"filter": &"owned" if mode == &"loadout" else &"all", "cls": &"", "sort": &"class", "tab": &"stats", "scroll": 0.0, "vel": 0.0, "slot": &"optic", "part": &"", "ammo": -1}
	return _st[mode]


## The state a screen opens with: the default filter of its mode, no class, the STATS tab, the list scrolled so that the selected weapon is in view.
static func open(mode: StringName, sel: StringName) -> void:
	var s := st(mode)
	s["filter"] = &"owned" if mode == &"loadout" else &"all"
	s["cls"] = &""
	s["tab"] = &"stats"
	s["part"] = &""
	s["ammo"] = -1
	s["vel"] = 0.0
	s["scroll"] = 0.0
	_list_cache_key = ""
	_disp.clear()
	if sel != &"":
		_scroll_to(mode, sel)


static func state_key(mode: StringName) -> String:
	var s := st(mode)
	return "%s%s%s%s%s%d%s%d" % [s["filter"], s["cls"], s["sort"], s["tab"], s["part"], int(float(s["scroll"])), view3d, s["ammo"]] + str(LoadoutSlots.slots.hash()) + str(LoadoutSlots.active)


# ---------------------------------------------------------------------------------------------------------------------------------- the list model

static func is_gear_class(cls: StringName) -> bool:
	return GEAR_CLASSES.has(cls)


## Every id the filter and class admit, in the sort order (weapon ids, or Gear ids for the two gear classes).
static func list(mode: StringName) -> Array[StringName]:
	var s := st(mode)
	var key := "%s|%s|%s|%s|%d|%d|%d|%s|%d" % [mode, s["filter"], s["cls"], s["sort"], WeaponDefs.unlocked.size(), str(WeaponBrowser.favourites).hash(), WeaponBrowser._seen.size(), WeaponDefs.hero_mode, Gear.owned.size()]
	if key == _list_cache_key:
		return _list_cache
	var out: Array[StringName] = []
	var cls: StringName = s["cls"]
	if is_gear_class(cls):
		var gids: Array = (Gear.THROW_IDS + Gear.CHARGE_IDS) if cls == &"explosives" else Gear.GADGET_IDS
		for id: StringName in gids:
			if _passes(StringName(s["filter"]), id, true):
				out.append(id)
	else:
		for c: StringName in WeaponDefs.CLASS_ORDER:
			if cls != &"" and c != cls:
				continue
			for id: StringName in WeaponDefs.in_class(c):
				if _passes(StringName(s["filter"]), id, false):
					out.append(id)
		if mode == &"catalogue" and cls == &"" and StringName(s["filter"]) != &"fav" and StringName(s["filter"]) != &"new":
			pass                                                                # the "all classes" list is weapons only: the gear classes are one tap away
	_sort(out, StringName(s["sort"]))
	_list_cache_key = key
	_list_cache = out
	return out


static func _passes(filter: StringName, id: StringName, gear: bool) -> bool:
	var owned := Gear.is_owned(id) if gear else WeaponDefs.is_unlocked(id)
	match filter:
		&"owned":
			return owned
		&"locked":
			return not owned
		&"new":
			return (not gear) and WeaponBrowser.is_new(id)
		&"fav":
			return (not gear) and WeaponBrowser.is_favourite(id)
	return true


static func _sort(ids: Array[StringName], sort: StringName) -> void:
	if sort == &"class":
		return                                                                  # the order of the roster inside each class (the list is built in it)
	if sort == &"name":
		ids.sort_custom(func(a: StringName, b: StringName) -> bool: return _title(a) < _title(b))
		return
	if sort == &"price":
		ids.sort_custom(func(a: StringName, b: StringName) -> bool:
			var pa := _price(a)
			var pb := _price(b)
			return pa < pb if pa != pb else String(a) < String(b))
		return
	_ensure_sort_vals(ids)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var va := float((_sort_vals.get(a, {}) as Dictionary).get(sort, 0.0))
		var vb := float((_sort_vals.get(b, {}) as Dictionary).get(sort, 0.0))
		return va > vb if not is_equal_approx(va, vb) else String(a) < String(b))


static func _ensure_sort_vals(ids: Array[StringName]) -> void:
	for id in ids:
		if _sort_vals.has(id) or WeaponsScreen.is_gear(id) or not WeaponDefs.DEFS.has(id):
			continue
		var c := WeaponStats.card(id)
		_sort_vals[id] = {&"damage": float(c["damage_shot"]), &"range": float(c["range_eff"]) if not c["melee"] else float(c["reach"]), &"rate": float(c["rate"])}


static func _title(id: StringName) -> String:
	return String(Gear.def(id)["name"]) if WeaponsScreen.is_gear(id) else WeaponDefs.title(id)


static func _price(id: StringName) -> int:
	return Economy.gear_price(id) if WeaponsScreen.is_gear(id) else WeaponDefs.price(id)


## How many weapons pass `filter` in class `cls` (the number beside the class name).
static func count_in(filter: StringName, cls: StringName) -> int:
	var n := 0
	if is_gear_class(cls):
		for id: StringName in ((Gear.THROW_IDS + Gear.CHARGE_IDS) if cls == &"explosives" else Gear.GADGET_IDS):
			if _passes(filter, id, true):
				n += 1
		return n
	for id: StringName in WeaponDefs.all_ids():
		if (cls == &"" or WeaponDefs.class_of(id) == cls) and _passes(filter, id, false):
			n += 1
	return n


## The class ring of the class row: ALL, the ten weapon classes, and (catalogue) EXPLOSIVES and GADGETS.
static func class_ring(mode: StringName) -> Array[StringName]:
	var out: Array[StringName] = [&""]
	out.append_array(WeaponDefs.CLASS_ORDER)
	if mode == &"catalogue":
		out.append_array(GEAR_CLASSES)
	return out


## The next class (dir 1) or the previous one (dir -1) that has something under the filter (wraps through ALL).
static func next_class(mode: StringName, dir: int) -> StringName:
	var ring := class_ring(mode)
	var s := st(mode)
	var at := ring.find(s["cls"])
	for _i in ring.size():
		at = posmod(at + dir, ring.size())
		if ring[at] == &"" or count_in(StringName(s["filter"]), ring[at]) > 0:
			return ring[at]
	return &""


# ---------------------------------------------------------------------------------------------------------------------------------- selection and scrolling

static func selected(hud: Hud, mode: StringName) -> StringName:
	return hud._loadout_w if mode == &"loadout" else WeaponsScreen.sel


static func select(hud: Hud, mode: StringName, id: StringName) -> void:
	if mode == &"loadout":
		hud._loadout_w = id
	else:
		WeaponsScreen.sel = id
	sel_at = hud._t
	if WeaponDefs.DEFS.has(id):
		WeaponBrowser.mark_seen(id)
	var s := st(mode)
	s["part"] = &""
	s["ammo"] = -1
	if s["tab"] != &"stats" and (WeaponsScreen.is_gear(id) or not Attachments.fits_any(id)):
		s["tab"] = &"stats"
	_scroll_to(mode, id)                                                      # a weapon picked from elsewhere (a slot, the wheel, a test) is brought into view


static func _rows(mode: StringName) -> int:
	return (list(mode).size() + COLS - 1) / COLS


static func max_scroll(mode: StringName) -> float:
	return maxf(float(_rows(mode)) * ROW - TILE_GAP - (BOTTOM - LIST_Y), 0.0)


static func _scroll_to(mode: StringName, id: StringName) -> void:
	var at := list(mode).find(id)
	if at < 0:
		return
	var row := at / COLS
	var s := st(mode)
	var y := float(row) * ROW
	var view := BOTTOM - LIST_Y
	var cur := float(s["scroll"])
	if y < cur:
		cur = y
	elif y + TILE_H > cur + view:
		cur = y + TILE_H - view
	s["scroll"] = clampf(snappedf(cur, ROW), 0.0, max_scroll(mode)) if cur > 0.0 else 0.0


static func scroll_by(mode: StringName, dy: float) -> void:
	var s := st(mode)
	s["scroll"] = clampf(float(s["scroll"]) + dy, 0.0, max_scroll(mode))


static func _fix_selection(hud: Hud, mode: StringName) -> void:
	var cur := selected(hud, mode)
	if cur != &"" and (WeaponDefs.DEFS.has(cur) or WeaponsScreen.is_gear(cur)):
		return
	var ids := list(mode)
	var pick: StringName = WeaponDefs.last_used
	if not ids.has(pick) and not ids.is_empty():
		pick = ids[0]
	select(hud, mode, pick)


# ---------------------------------------------------------------------------------------------------------------------------------- geometry

## The horizontal squeeze that fits the layout into the screen width (1 on a 16:9 phone and wider, about 0.75 on a 4:3 tablet).
static func k_of(vp: Vector2, s: float) -> float:
	return clampf((vp.x / s - 24.0) / W, 0.5, 1.0)


## A rect in base px (x from the screen centre, widths squeezed by k, never narrower than `min_w` base px: a touch target) as screen px.
static func rect(vp: Vector2, s: float, bx: float, by: float, bw: float, bh: float, min_w := 0.0) -> Rect2:
	var k := k_of(vp, s)
	return Rect2(vp.x * 0.5 + bx * s * k, by * s, maxf(bw * k, min_w) * s, bh * s)


static func pic_h(tab: StringName) -> float:
	return PIC_BIG if tab == &"stats" else PIC_SMALL


static func card_rects(vp: Vector2, s: float, tab: StringName) -> Dictionary:
	var ph := pic_h(tab)
	var ty := TOP + ph + 6.0
	var out := {"pic": rect(vp, s, CARD_X, TOP, CARD_W, ph), "content": rect(vp, s, CARD_X, ty + CHIP + 6.0, CARD_W, BOTTOM - (ty + CHIP + 6.0)), "tabs": [], "view3d": rect(vp, s, CARD_X + 484.0, ty, 166.0, CHIP)}
	for i in TABS.size():
		(out["tabs"] as Array).append(rect(vp, s, CARD_X + float(i) * 160.0, ty, 154.0, CHIP))
	return out


## The bottom bar from the left: BACK, the four slots, GEAR (when there is room), and from the right: the action and the star. Every one is at least 64 base px across.
static func slot_rect(vp: Vector2, s: float, i: int) -> Rect2:
	var k := k_of(vp, s)
	var left := vp.x * 0.5 + LIST_X * k * s
	var w := maxf(96.0 * k, 64.0) * s
	var x0 := left + maxf(200.0 * k, 110.0) * s + 10.0 * s
	return Rect2(x0 + float(i) * (w + 4.0 * s), ACTION_Y * s, w, CHIP * s)


static func back_rect(vp: Vector2, s: float) -> Rect2:
	var k := k_of(vp, s)
	return Rect2(vp.x * 0.5 + LIST_X * k * s, ACTION_Y * s, maxf(200.0 * k, 110.0) * s, CHIP * s)


static func action_rect(vp: Vector2, s: float) -> Rect2:
	var k := k_of(vp, s)
	var w := maxf(330.0 * k, 150.0) * s
	return Rect2(vp.x * 0.5 + (CARD_X + CARD_W) * k * s - w, ACTION_Y * s, w, CHIP * s)


static func star_rect(vp: Vector2, s: float) -> Rect2:
	var a := action_rect(vp, s)
	return Rect2(a.position.x - 8.0 * s - CHIP * s, ACTION_Y * s, CHIP * s, CHIP * s)


## The GEAR chip between the last slot and the star: null-sized when there is no room for a 100 base px chip.
static func gear_rect(vp: Vector2, s: float) -> Rect2:
	var last := slot_rect(vp, s, LoadoutSlots.COUNT - 1)
	var x0 := last.end.x + 8.0 * s
	var x1 := star_rect(vp, s).position.x - 8.0 * s
	if x1 - x0 < 100.0 * s:
		return Rect2()
	return Rect2(x0, ACTION_Y * s, minf(x1 - x0, 210.0 * s), CHIP * s)


static func filter_rect(vp: Vector2, s: float, i: int) -> Rect2:
	var k := k_of(vp, s)
	var w := maxf(114.0 * k, 64.0) * s
	return Rect2(vp.x * 0.5 + LIST_X * k * s + float(i) * (w + 4.0 * s), TOP * s, w, CHIP * s)


## The class row: [previous, name, next, sort]; the arrows are 64 base px whatever the squeeze, the name and the sort chip share the rest.
static func class_rects(vp: Vector2, s: float) -> Array[Rect2]:
	var k := k_of(vp, s)
	var left := vp.x * 0.5 + LIST_X * k * s
	var total := LIST_W * k * s
	var y := (TOP + CHIP + 4.0) * s
	var gap := 4.0 * s
	var arrow := CHIP * s
	var rest := total - 2.0 * arrow - 3.0 * gap
	var lw := rest * 0.55
	var sw := rest - lw
	return [Rect2(left, y, arrow, CHIP * s), Rect2(left + arrow + gap, y, lw, CHIP * s), Rect2(left + arrow + gap + lw + gap, y, arrow, CHIP * s), Rect2(left + 2.0 * arrow + 3.0 * gap + lw, y, sw, CHIP * s)]


## The tile `idx` of the list at the current scroll: its rect (not clipped) in screen px.
static func tile_rect(vp: Vector2, s: float, idx: int, scroll: float) -> Rect2:
	var col := idx % COLS
	var row := idx / COLS
	return rect(vp, s, LIST_X + float(col) * (TILE_W + TILE_GAP), LIST_Y + float(row) * ROW - scroll, TILE_W, TILE_H)


# ---------------------------------------------------------------------------------------------------------------------------------- layout (the buttons)

static func layout(hud: Hud, cx: float, s: float, mode: StringName) -> void:
	LoadoutSlots.ensure()
	var vp := hud.get_viewport().get_visible_rect().size
	var stt := st(mode)
	_fix_selection(hud, mode)
	var sel := selected(hud, mode)
	_ensure_active(hud, mode)
	list_rect = rect(vp, s, LIST_X, LIST_Y, LIST_W, BOTTOM - LIST_Y)
	# filter chips, the class row, the sort chip
	for i in FILTERS.size():
		var f: StringName = FILTERS[i][0]
		hud.buttons.append({"id": StringName("ars_filter_%s" % f), "rect": filter_rect(vp, s, i), "label": String(FILTERS[i][1]), "on": stt["filter"] == f, "own": true})
	var cr0 := class_rects(vp, s)
	hud.buttons.append({"id": &"ars_cls_prev", "rect": cr0[0], "label": "<", "on": false, "own": true})
	hud.buttons.append({"id": &"ars_cls_label", "rect": cr0[1], "label": String(CLASS_LABEL.get(stt["cls"], "ALL")), "on": stt["cls"] != &"", "own": true})
	hud.buttons.append({"id": &"ars_cls_next", "rect": cr0[2], "label": ">", "on": false, "own": true})
	hud.buttons.append({"id": &"ars_sort", "rect": cr0[3], "label": "SORT", "on": stt["sort"] != &"class", "own": true})
	# the visible tiles (virtualised): a tile is a button once at least 64 base px of it are on screen
	var ids := list(mode)
	var scroll := float(stt["scroll"])
	var first := maxi(int(floorf(scroll / ROW)), 0) * COLS
	var last := mini(ids.size(), int(ceilf((scroll + (BOTTOM - LIST_Y)) / ROW) + 1) * COLS)
	for i in range(first, last):
		var tr := tile_rect(vp, s, i, scroll)
		var vis := tr.intersection(list_rect)
		if vis.size.y < CHIP * s * 0.999 or vis.size.x < tr.size.x * 0.99:
			continue
		var pre := "wheel_" if mode == &"loadout" else "wsel_"
		hud.buttons.append({"id": StringName(pre + String(ids[i])), "rect": vis, "label": "", "on": ids[i] == sel, "own": true, "tile": ids[i]})
	# the card: tabs and, per tab, its buttons
	var tab: StringName = stt["tab"]
	var gear := WeaponsScreen.is_gear(sel)
	var owned := Gear.is_owned(sel) if gear else WeaponDefs.is_unlocked(sel)
	var cr := card_rects(vp, s, tab)
	if not gear:
		var tabs: Array = cr["tabs"]
		var slot := 0                                                           # wave 114 critic: a hidden PARTS tab (a launcher, a grenade) left a hole between STATS and AMMO: the tabs that exist sit side by side
		for i in TABS.size():
			var tid: StringName = TABS[i][0]
			if tid != &"stats" and not owned:
				continue
			if tid != &"stats" and not Attachments.fits_any(sel) and tid == &"parts":
				continue
			hud.buttons.append({"id": StringName("ars_tab_%s" % tid), "rect": tabs[slot], "label": String(TABS[i][1]), "on": tid == tab, "own": true})
			slot += 1
		if WeaponModels.has_model(sel) and tab != &"parts":                      # the PARTS tab always shows the live 3D weapon
			hud.buttons.append({"id": &"ars_view3d", "rect": cr["view3d"], "label": "3D VIEW", "on": view3d, "own": true})
	ArsenalCard.layout(hud, vp, s, mode, sel, tab, cr)
	# the bottom bar: BACK, the four slots, the star, the action
	hud.buttons.append({"id": &"loadout_back" if mode == &"loadout" else &"shop_back", "rect": back_rect(vp, s), "label": "RESUME" if (mode == &"loadout" and hud._loadout_quick) else "BACK", "on": false})
	if mode == &"loadout" or true:
		for i in LoadoutSlots.COUNT:
			hud.buttons.append({"id": StringName("ars_slot_%d" % i), "rect": slot_rect(vp, s, i), "label": "", "on": LoadoutSlots.active == i, "own": true})
	if not gear:
		hud.buttons.append({"id": &"ars_star", "rect": star_rect(vp, s), "label": "", "on": WeaponBrowser.is_favourite(sel), "own": true})
	if mode == &"loadout" and gear_rect(vp, s).has_area():
		hud._add_card(&"loadout_gear", gear_rect(vp, s), "GEAR", &"gear", "", false, UiUtil.MAGENTA)
	_action_button(hud, vp, s, mode, sel, owned, gear)


## The screen just opened: its defaults, the list scrolled to the weapon in hand. Layout and presses both call it, so a press that comes before the first layout (a test, a bot) is not undone by it.
static func _ensure_active(hud: Hud, mode: StringName) -> void:
	if _active != mode:
		_active = mode
		open(mode, selected(hud, mode))


static func _action_button(hud: Hud, vp: Vector2, s: float, mode: StringName, sel: StringName, owned: bool, gear: bool) -> void:
	var ar := action_rect(vp, s)
	var prog := Game.progress as Progress
	var stt := st(mode)
	if stt["tab"] == &"parts" and not gear and owned and stt["part"] != &"":
		var part: StringName = stt["part"]
		if Attachments.PARTS.has(part) and Attachments.fits(part, sel):
			var fitted := Attachments.part_in(sel, Attachments.slot_of(part)) == part
			var own_part := Attachments.is_owned(part)
			var price := prog.part_price(part) if prog != null else Attachments.price(part)
			hud.buttons.append({"id": &"ars_apply", "rect": ar, "label": "TAKE OFF" if fitted else ("FIT" if own_part else "BUY  %d" % price), "on": fitted, "own": true, "act": true,
					"afford": own_part or (prog != null and prog.credits >= price)})
			return
	if gear:
		if Gear.is_charge(sel):
			hud.buttons.append({"id": StringName("wgear_%s" % sel), "rect": ar, "label": "ALWAYS CARRIED", "on": true, "own": true, "act": true})
		else:
			var inuse := Gear.throwable == sel or Gear.gadget == sel
			var gl := "IN USE" if inuse else ("EQUIP" if Gear.is_owned(sel) else "BUY  %d" % (prog.gear_price(sel) if prog != null else Economy.gear_price(sel)))
			hud.buttons.append({"id": StringName("wgear_%s" % sel), "rect": ar, "label": gl, "on": inuse, "own": true, "act": true,
					"afford": Gear.is_owned(sel) or (prog != null and prog.credits >= prog.gear_price(sel))})
		return
	if owned:
		var in_hand := sel == WeaponDefs.last_used
		var slot := LoadoutSlots.active
		var in_slot := LoadoutSlots.slot_of(sel) == slot
		var label := "IN HAND" if (in_hand and in_slot) else ("TO SLOT %d" % (slot + 1) if in_hand else "EQUIP  SLOT %d" % (slot + 1))
		var aid := StringName("ars_equip") if mode == &"loadout" else StringName("wequip_%s" % sel)
		hud.buttons.append({"id": aid, "rect": ar, "label": label, "on": in_hand and in_slot, "own": true, "act": true})
	else:
		var price2 := prog.weapon_price(sel) if prog != null else WeaponDefs.price(sel)
		hud.buttons.append({"id": StringName("buy_%s" % sel), "rect": ar, "label": "BUY  %d" % price2, "on": false, "own": true, "act": true, "afford": prog != null and prog.can_buy_weapon(sel)})


# ---------------------------------------------------------------------------------------------------------------------------------- presses

## The effect of the Arsenal's own ids; true when it handled `sid`.
static func press(hud: Hud, sid: String) -> bool:
	var mode: StringName = &"loadout" if hud._loadout_open else (&"catalogue" if (hud._shop_open and ShopScreen.weapon_page > 0) else &"")
	if mode == &"" or Game.state != &"paused" or Game.progress == null:
		return false
	_ensure_active(hud, mode)
	var stt := st(mode)
	var sel := selected(hud, mode)
	if sid.begins_with("wheel_") or sid.begins_with("wsel_"):
		var id := StringName(sid.substr(6 if sid.begins_with("wheel_") else 5))
		if not (WeaponDefs.DEFS.has(id) or WeaponsScreen.is_gear(id)):
			return false
		select(hud, mode, id)
		taps += 1
		Sfx.play(&"ui_tap")
		if mode == &"loadout" and hud._loadout_quick and WeaponDefs.is_unlocked(id):             # opened by the wheel gesture: one tap takes the weapon and goes back to the fight (the slots are not rewritten)
			return _equip(hud, mode, id, false)
	elif sid.begins_with("ars_filter_"):
		var f := StringName(sid.substr(11))
		stt["filter"] = f
		stt["scroll"] = 0.0
		_list_cache_key = ""
		if stt["cls"] != &"" and count_in(f, stt["cls"]) == 0:
			stt["cls"] = &""
		_keep_selection_visible(hud, mode)
		Sfx.play(&"ui_tap")
	elif sid == "ars_cls_prev" or sid == "ars_cls_next" or sid == "ars_cls_label":
		stt["cls"] = next_class(mode, -1 if sid == "ars_cls_prev" else 1)
		stt["scroll"] = 0.0
		_list_cache_key = ""
		_keep_selection_visible(hud, mode)
		Sfx.play(&"ui_tap")
	elif sid == "ars_sort":
		var at := 0
		for i in SORTS.size():
			if SORTS[i][0] == stt["sort"]:
				at = i
		stt["sort"] = SORTS[(at + 1) % SORTS.size()][0]
		stt["scroll"] = 0.0
		_list_cache_key = ""
		Sfx.play(&"ui_tap")
	elif sid.begins_with("ars_tab_"):
		stt["tab"] = StringName(sid.substr(8))
		stt["part"] = &""
		stt["ammo"] = -1
		Sfx.play(&"ui_tap")
	elif sid == "ars_view3d":
		view3d = not view3d
		Sfx.play(&"ui_toggle")
	elif sid.begins_with("ars_slot_"):
		var i := sid.substr(9).to_int()
		LoadoutSlots.active = clampi(i, 0, LoadoutSlots.COUNT - 1)
		var w := LoadoutSlots.get_slot(i)
		if w != &"":
			select(hud, mode, w)
			if not list(mode).has(w):
				stt["filter"] = &"all" if mode == &"catalogue" else &"owned"
				stt["cls"] = &""
				_list_cache_key = ""
			_scroll_to(mode, w)
		Sfx.play(&"ui_tap")
	elif sid == "ars_star":
		if WeaponBrowser.toggle_favourite(sel):
			Sfx.play(&"ui_confirm")
		else:
			Sfx.play(&"ui_tap")
		_list_cache_key = ""
	elif sid == "ars_equip":
		return _equip(hud, mode, sel)
	elif sid == "ars_apply":
		return ArsenalCard.apply_part(hud, mode, sel)
	elif sid == "ars_bench":
		hud._loadout_open = false
		hud._loadout_page = 0
		hud._shop_open = true
		hud._hero_hub = true
		hud._skills_open = false
		hud._craft_open = false
		CraftScreen.reset_state()
		hud._craft_open = true
		Sfx.play(&"ui_confirm")
	elif sid.begins_with("ars_slottab_"):
		stt["slot"] = StringName(sid.substr(12))
		stt["part"] = &""
		Sfx.play(&"ui_tap")
	elif sid.begins_with("ars_part_"):
		var part := StringName(sid.substr(9))
		return ArsenalCard.press_part(hud, mode, sel, part)
	elif sid.begins_with("ars_ammo_"):
		return ArsenalCard.press_ammo(hud, mode, sel, sid.substr(9).to_int())
	else:
		return false
	hud._layout_key = ""
	hud._screen.queue_redraw()
	return true


static func _keep_selection_visible(hud: Hud, mode: StringName) -> void:
	var ids := list(mode)
	var cur := selected(hud, mode)
	if not ids.is_empty() and not ids.has(cur):
		select(hud, mode, ids[0])
	elif ids.has(cur):
		_scroll_to(mode, cur)


## EQUIP (loadout): the selected weapon goes into the ACTIVE slot and into the hero's hands; opened from the wheel gesture it also resumes the game (a plain tile tap does that in quick mode, without touching the slots).
static func _equip(hud: Hud, mode: StringName, sel: StringName, assign := true) -> bool:
	if not WeaponDefs.is_unlocked(sel):
		return false
	if assign:
		LoadoutSlots.assign(LoadoutSlots.active, sel)
	var pl := Game.player
	if is_instance_valid(pl) and pl.get(&"weapon") is PlayerWeapon:
		(pl.get(&"weapon") as PlayerWeapon).switch_to(sel)
	WeaponDefs.last_used = sel
	Sfx.play(&"ui_confirm")
	hud._layout_key = ""
	hud._screen.queue_redraw()
	if mode == &"loadout" and hud._loadout_quick:
		Game.state = &"play"
	return true


## Put an owned weapon into the active slot from the catalogue's EQUIP (`wequip_<id>`, handled by WeaponsScreen.press): the slot follows.
static func note_equipped(id: StringName) -> void:
	if WeaponDefs.is_unlocked(id):
		LoadoutSlots.assign(LoadoutSlots.active, id)


# ---------------------------------------------------------------------------------------------------------------------------------- the list gesture (Hud routes the finger here)

static func dragging() -> bool:
	return not _gest.is_empty()


## A press at `pos` inside the list: remember it, decide at the release (a tap presses the tile under it, a drag scrolls). True when the press belongs to the list.
static func begin_drag(hud: Hud, pos: Vector2) -> bool:
	var mode := _mode_of(hud)
	if mode == &"" or not list_rect.has_point(pos):
		return false
	_gest = {"pos": pos, "last": pos, "moved": false, "mode": mode, "t": Time.get_ticks_msec(), "vy": 0.0}
	st(mode)["vel"] = 0.0
	return true


static func drag_to(hud: Hud, pos: Vector2) -> void:
	if _gest.is_empty():
		return
	var s := UiUtil.ui_scale(hud.get_viewport().get_visible_rect().size)
	var mode: StringName = _gest["mode"]
	if not bool(_gest["moved"]):
		if absf(pos.y - float((_gest["pos"] as Vector2).y)) < 12.0 * s and (pos - (_gest["pos"] as Vector2)).length() < 16.0 * s:
			return
		_gest["moved"] = true
		drag_scrolls += 1
	var dy := pos.y - float((_gest["last"] as Vector2).y)
	_gest["last"] = pos
	var base_dy := -dy / s                                                       # screen px to base px
	scroll_by(mode, base_dy)
	_gest["vy"] = lerpf(float(_gest["vy"]), base_dy, 0.5)
	hud._layout_key = ""
	hud._screen.queue_redraw()


static func end_drag(hud: Hud) -> void:
	if _gest.is_empty():
		return
	var g := _gest
	_gest = {}
	var mode: StringName = g["mode"]
	if not bool(g["moved"]):
		var id := hud._button_at(g["pos"])
		if id != &"":
			hud.press_button(id)
		return
	st(mode)["vel"] = clampf(float(g["vy"]) * 60.0, -3200.0, 3200.0)           # base px a second: a flick keeps going and slows down (tick)


## The pad walks the list (ControllerInput.move_focus): from a tile, up or down goes to the tile of the same column one row away and scrolls the list when that row is not in view. &"" when `focus`
## is no tile, the direction is sideways or there is no such row (the pad then goes on to the next button the usual way).
static func pad_step(hud: Hud, focus: StringName, dir: Vector2) -> StringName:
	var mode := _mode_of(hud)
	if mode == &"" or absf(dir.y) < 0.5:
		return &""
	var pre := "wheel_" if mode == &"loadout" else "wsel_"
	var fs := String(focus)
	if not fs.begins_with(pre):
		return &""
	var ids := list(mode)
	var at := ids.find(StringName(fs.substr(pre.length())))
	if at < 0:
		return &""
	var to := at + (COLS if dir.y > 0.0 else -COLS)
	if to < 0 or to >= ids.size():
		return &""
	_scroll_to(mode, ids[to])
	hud._layout_key = ""
	hud._ensure_layout()
	return StringName(pre + String(ids[to]))


## Mouse wheel over the list: one row a notch.
static func wheel(hud: Hud, pos: Vector2, dir: int) -> bool:
	var mode := _mode_of(hud)
	if mode == &"" or not list_rect.has_point(pos):
		return false
	scroll_by(mode, float(dir) * ROW)
	hud._layout_key = ""
	hud._screen.queue_redraw()
	return true


## Inertia of a flick and the snap to a whole row when it stops (Hud._process calls it while an Arsenal screen is open).
static func tick(hud: Hud, dt: float) -> void:
	var mode := _mode_of(hud)
	if mode == &"":
		_active = &""
		return
	if not _gest.is_empty():
		return
	var stt := st(mode)
	var v := float(stt["vel"])
	var scroll := float(stt["scroll"])
	if absf(v) > 30.0:
		scroll_by(mode, v * dt)
		stt["vel"] = v * pow(0.04, dt)                                           # ~96 % of the speed is gone after a second
		if float(stt["scroll"]) <= 0.0 or float(stt["scroll"]) >= max_scroll(mode):
			stt["vel"] = 0.0
	else:
		stt["vel"] = 0.0
		var snapped := clampf(roundf(scroll / ROW) * ROW, 0.0, max_scroll(mode))
		if not is_equal_approx(snapped, scroll):
			stt["scroll"] = move_toward(scroll, snapped, 900.0 * dt)
		else:
			return
	hud._layout_key = ""
	hud._screen.queue_redraw()


static func _mode_of(hud: Hud) -> StringName:
	if Game.state != &"paused":
		return &""
	if hud._loadout_open and hud._loadout_page == 0:
		return &"loadout"
	if hud._shop_open and ShopScreen.weapon_page > 0 and not hud._skills_open and not hud._craft_open:
		return &"catalogue"
	return &""


# ---------------------------------------------------------------------------------------------------------------------------------- drawing

static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float, mode: StringName) -> void:
	LoadoutSlots.ensure()
	_fix_selection(hud, mode)
	var stt := st(mode)
	var sel := selected(hud, mode)
	var prog := Game.progress as Progress
	var gear := WeaponsScreen.is_gear(sel)
	var tint := UiKit.class_tint(WeaponDefs.class_of(sel)) if not gear else UiUtil.CYAN
	# the top row: credits at the left, the title (loadout) in the middle (the catalogue has the HERO tabs there), the owned counter at the right
	var k := k_of(vp, s)
	if prog != null:
		var cr := "CREDITS  %d" % prog.credits
		hud._text(c, font, Vector2(rect(vp, s, LIST_X, 0, 1, 1).position.x + 30.0 * s, 46.0 * s), cr, HORIZONTAL_ALIGNMENT_LEFT, 280.0 * s * k, int(UiKit.T_LABEL * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
		UiKit.glyph(c, &"coin", Vector2(rect(vp, s, LIST_X, 0, 1, 1).position.x + 12.0 * s, 38.0 * s), 10.0 * s, Color(UiUtil.AMBER, 0.95), s)
	if mode == &"loadout":
		hud._text(c, font, Vector2(0.0, 52.0 * s), "LOADOUT", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiKit.T_HERO * 0.85 * s), Color(1, 1, 1, 0.97), 2.0 * s)
		c.draw_rect(Rect2(vp.x * 0.5 - 56.0 * s, 62.0 * s, 112.0 * s, 3.0 * s), Color(UiUtil.MAGENTA, 0.9))
	var owned_n := count_in(&"owned", &"")
	var rt := "OWNED  %d / %d" % [owned_n, WeaponDefs.all_ids().size()]
	var rr := rect(vp, s, CARD_X + CARD_W - 300.0, 0, 300.0, 1)
	hud._text(c, font, Vector2(rr.position.x, 46.0 * s), rt, HORIZONTAL_ALIGNMENT_RIGHT, rr.size.x, int(UiKit.T_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	# chips
	for b: Dictionary in hud.buttons:
		var id := String(b["id"])
		if id.begins_with("ars_filter_"):
			var f := StringName(id.substr(11))
			var label := String(b["label"])
			var st_i := 1 if b["on"] else 0
			if f == &"new" and WeaponBrowser.new_count() > 0 and not b["on"]:
				label = "NEW  %d" % WeaponBrowser.new_count()
			UiKit.button(hud, c, b["rect"], label, UiUtil.MAGENTA if f == &"new" else (UiUtil.AMBER if f == &"fav" else UiUtil.CYAN), st_i, s, font, UiKit.T_LABEL)
		elif id == "ars_cls_prev" or id == "ars_cls_next":
			UiKit.button(hud, c, b["rect"], String(b["label"]), UiUtil.CYAN, 0, s, font, 30.0)
		elif id == "ars_cls_label":
			var cls: StringName = stt["cls"]
			var count := count_in(StringName(stt["filter"]), cls)
			var cap := "%s  %d" % [CLASS_LABEL.get(cls, "ALL"), count]
			UiKit.button(hud, c, b["rect"], cap, UiKit.class_tint(cls) if cls != &"" and not is_gear_class(cls) else UiUtil.AMBER, 1, s, font, UiKit.T_LABEL)
		elif id == "ars_sort":
			var cur := "CLASS"
			for sr: Array in SORTS:
				if sr[0] == stt["sort"]:
					cur = String(sr[1])
			UiKit.button(hud, c, b["rect"], "SORT  " + cur, UiUtil.MAGENTA, 1 if b["on"] else 0, s, font, UiKit.T_LABEL)
	_draw_list(hud, c, vp, s, font, mode, sel)
	ArsenalCard.draw(hud, c, vp, s, font, mode, sel, tint)
	_draw_bottom(hud, c, vp, s, font, mode, sel, gear)


static func _draw_list(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, mode: StringName, sel: StringName) -> void:
	var stt := st(mode)
	var ids := list(mode)
	var scroll := float(stt["scroll"])
	var clip := list_rect
	if ids.is_empty():
		var msg := "NOTHING HERE YET"
		match StringName(stt["filter"]):
			&"fav":
				msg = "STAR A WEAPON ON ITS CARD TO FIND IT HERE"
			&"new":
				msg = "NO NEW WEAPONS"
			&"locked":
				msg = "YOU OWN EVERYTHING HERE"
			&"owned":
				msg = "YOU OWN NOTHING HERE YET"
		UiKit.panel(c, clip, s, UiUtil.CYAN, false, 12.0)
		hud._text(c, font, Vector2(clip.position.x, clip.get_center().y), msg, HORIZONTAL_ALIGNMENT_CENTER, clip.size.x, int(UiKit.T_BODY * s), Color(1, 1, 1, 0.75))
		return
	var first := maxi(int(floorf(scroll / ROW)), 0) * COLS
	var last := mini(ids.size(), int(ceilf((scroll + (BOTTOM - LIST_Y)) / ROW) + 1) * COLS)
	for i in range(first, last):
		var tr := tile_rect(vp, s, i, scroll)
		var vis := tr.intersection(clip)
		if vis.size.y <= 1.0:
			continue
		_tile(hud, c, tr, vis, s, font, ids[i], ids[i] == sel, mode)
	# the scrollbar and the row counter
	var ms := max_scroll(mode)
	if ms > 0.0:
		var tx := clip.end.x - 5.0 * s
		var th := clip.size.y
		c.draw_rect(Rect2(tx, clip.position.y, 4.0 * s, th), Color(1, 1, 1, 0.08))
		var frac := clampf(clip.size.y / (clip.size.y + ms * s), 0.1, 1.0)
		c.draw_rect(Rect2(tx, clip.position.y + (th - th * frac) * scroll / ms, 4.0 * s, th * frac), Color(UiUtil.CYAN, 0.7))


## One tile: the class backdrop, the weapon's thumb, its name and what the hero has with it (a status line); clipped to `vis` while a drag moves it across the edge of the list.
static func _tile(hud: Hud, c: Control, tr: Rect2, vis: Rect2, s: float, font: Font, id: StringName, lit: bool, mode: StringName) -> void:
	var gear := WeaponsScreen.is_gear(id)
	var cls := WeaponDefs.class_of(id) if not gear else &"melee"
	var tint := UiKit.class_tint(cls) if not gear else UiUtil.CYAN
	var owned := Gear.is_owned(id) if gear else WeaponDefs.is_unlocked(id)
	var full := vis.size.y >= tr.size.y - 1.0
	var hot := hud._hover == StringName(("wheel_" if mode == &"loadout" else "wsel_") + String(id))
	# the plate, clipped
	var top := Color(0.085, 0.11, 0.185, 0.97)
	var bot := Color(0.035, 0.045, 0.09, 0.97)
	var f0 := (vis.position.y - tr.position.y) / tr.size.y
	var f1 := (vis.end.y - tr.position.y) / tr.size.y
	var ct := top.lerp(bot, f0)
	var cb := top.lerp(bot, f1)
	c.draw_polygon(PackedVector2Array([vis.position, Vector2(vis.end.x, vis.position.y), vis.end, Vector2(vis.position.x, vis.end.y)]), PackedColorArray([ct, ct, cb, cb]))
	if full:
		var pic_r := Rect2(tr.position + Vector2(4.0, 4.0) * s, Vector2(TILE_W - 8.0, 92.0) * s * Vector2(clampf((vis.size.x / tr.size.x), 0.0, 1.0), 1.0))
		WeaponPics.draw_backdrop(c, pic_r, cls, 0.0, 0.7 if owned else 0.35)
		var fit := pic_r.grow_individual(-8.0 * s, -6.0 * s, -8.0 * s, -8.0 * s)
		if gear:
			ItemIcons.draw_tex(c, ItemIcons.gear(id), pic_r.grow(-8.0 * s), Color(1, 1, 1, 1.0 if owned else 0.55))
		else:
			WeaponPics.draw_fit(c, id, fit, false, Color(1, 1, 1, 1.0) if owned else Color(0.62, 0.66, 0.78, 0.95), 1.6)
		# badges on the picture
		if not gear and WeaponBrowser.is_new(id):
			UiKit.badge(hud, c, Vector2(tr.position.x + 8.0 * s, tr.position.y + 22.0 * s), "NEW", UiUtil.MAGENTA, s, font, true)
		var slot_i := LoadoutSlots.slot_of(id) if not gear else -1
		if slot_i >= 0:
			var sc := Vector2(tr.end.x - 20.0 * s, tr.position.y + 20.0 * s)
			c.draw_circle(sc, 13.0 * s, Color(UiUtil.CYAN, 0.85))
			hud._text(c, font, Vector2(sc.x - 12.0 * s, sc.y + 6.0 * s), str(slot_i + 1), HORIZONTAL_ALIGNMENT_CENTER, 24.0 * s, int(Hud.BODY_MIN * s), Color(0.02, 0.05, 0.08, 1.0))
		elif not gear and WeaponBrowser.is_favourite(id):
			var sc2 := Vector2(tr.end.x - 20.0 * s, tr.position.y + 20.0 * s)
			UiKit.glyph(c, &"star", sc2, 10.0 * s, Color(UiUtil.AMBER, 0.98), s)
		if not owned:
			var lk := Vector2(tr.end.x - 20.0 * s, tr.position.y + 72.0 * s)
			c.draw_circle(lk, 11.0 * s, Color(0, 0, 0, 0.6))
			c.draw_rect(Rect2(lk.x - 5.0 * s, lk.y - 1.0 * s, 10.0 * s, 8.0 * s), Color(1, 1, 1, 0.9))
			c.draw_arc(lk + Vector2(0, -1.0 * s), 4.5 * s, PI, TAU, 8, Color(1, 1, 1, 0.9), 1.8 * s)
		var nw := (TILE_W - 14.0) * s * (tr.size.x / (TILE_W * s))
		var nsz := int(Hud.BODY_MIN * 1.15 * s)
		var nm := _title(id)
		if font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nsz).x > nw and not gear:
			nm = WeaponBrowser.caption(id)                                     # the tile caption (11 letters at most, the same on every page)
		var shown := UiUtil.fit_text(font, nm, nw, nsz)
		var status := "IN HAND" if (not gear and id == WeaponDefs.last_used) else ""
		var scol := UiUtil.GREEN
		if status == "" and not owned:
			status = WeaponsScreen.tile_status(id)
			scol = UiUtil.AMBER
		var ny := 113.0 if status == "" else 111.0
		hud._text(c, font, Vector2(tr.position.x + 8.0 * s, tr.position.y + ny * s), shown, HORIZONTAL_ALIGNMENT_LEFT, nw, nsz, Color(1, 1, 1, 0.98 if (lit or owned) else 0.78))
		if status != "":
			hud._text(c, font, Vector2(tr.position.x + 8.0 * s, tr.position.y + 128.0 * s), UiUtil.fit_text(font, status, nw, int(Hud.BODY_MIN * s)), HORIZONTAL_ALIGNMENT_LEFT, nw, int(Hud.BODY_MIN * s), scol)
	# the frame
	var fc := UiUtil.MAGENTA if lit else Color(tint, 0.55 if hot else 0.32)
	c.draw_rect(vis, fc, false, (3.0 if lit else 1.5) * s)
	if lit:
		c.draw_rect(vis.grow(-3.0 * s), Color(1, 1, 1, 0.18), false, 1.0 * s)


static func _draw_bottom(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, mode: StringName, sel: StringName, gear: bool) -> void:
	# the four slots: a picture over its number; the active one is lit
	for i in LoadoutSlots.COUNT:
		var r := slot_rect(vp, s, i)
		var w := LoadoutSlots.get_slot(i)
		var act := LoadoutSlots.active == i
		UiKit.panel(c, r, s, UiUtil.CYAN if act else Color(0.5, 0.62, 0.8), act, 8.0, act)
		if w != &"":
			WeaponPics.draw_fit(c, w, Rect2(r.position + Vector2(14.0, 4.0) * s, Vector2(r.size.x - 18.0 * s, r.size.y - 20.0 * s)), false, Color(1, 1, 1, 1.0 if act else 0.82), 1.4)
		hud._text(c, font, Vector2(r.position.x + 5.0 * s, r.end.y - 6.0 * s), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, 20.0 * s, int(Hud.BODY_MIN * 1.2 * s), Color(UiUtil.CYAN if act else Color(1, 1, 1, 0.7)))
	# the star: a favourite is filled amber
	if not gear:
		var sr := star_rect(vp, s)
		var fav := WeaponBrowser.is_favourite(sel)
		UiKit.panel(c, sr, s, UiUtil.AMBER if fav else UiKit.class_tint(WeaponDefs.class_of(sel)), fav, 8.0, fav)
		var sc := sr.get_center()
		var pts := PackedVector2Array()
		for q in 10:
			var ang := -PI * 0.5 + TAU * float(q) / 10.0
			pts.append(sc + Vector2(cos(ang), sin(ang)) * (22.0 if q % 2 == 0 else 9.0) * s)
		if fav:
			c.draw_colored_polygon(pts, Color(UiUtil.AMBER, 0.97))
		else:
			pts.append(pts[0])
			c.draw_polyline(pts, Color(1, 1, 1, 0.8), 2.0 * s)
	var act_b := _find(hud)
	if act_b.is_empty():
		return
	var on := bool(act_b["on"])
	var ok := bool(act_b.get("afford", true))
	var primary := on or ok
	var col := UiUtil.GREEN if on else (UiUtil.AMBER if ok else Color(1, 1, 1, 0.5))
	UiKit.button(hud, c, act_b["rect"], String(act_b["label"]), col, 2 if primary else 0, s, font, UiKit.T_TITLE)


static func _find(hud: Hud) -> Dictionary:
	for b: Dictionary in hud.buttons:
		if bool(b.get("act", false)):
			return b
	return {}
