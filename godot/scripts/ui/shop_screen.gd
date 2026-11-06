class_name ShopScreen
extends RefCounted
## The upgrade shop of the pause menu (Hud draws it when `_shop_open`): seven rows (name, level pips, what the next level changes, a BUY button with the price after the
## reputation discount) and a BACK button. Buttons are ordinary Hud screen buttons: `buy_<id>`, `shop_back`; the purchase itself is Progress.buy(). Pure layout and drawing,
## no state of its own; every number comes from Upgrades and Progress.

const ROW_Y := 120.0                 ## base px of the first upgrade row (the HERO tab bar sits above, 8..72)
const ROW_STEP := 66.0               ## a 64 px BUY button per row
const ROW_W := 700.0
const BUY_W := 150.0
const SHOP_WEAPONS: Array[StringName] = [&"marksman", &"burst", &"revolver", &"akimbo", &"breacher", &"arc", &"lance", &"whip", &"rocket", &"minigun", &"grenade"]
const PER_ROW := 4
const PER_PAGE := 16                 ## four rows of four 64 px cells; page 0 is the upgrades, the weapons follow on pages 1..
const CELL_STEP := 92.0              ## a caption line over a 64 px BUY cell
const BACK_Y := 640.0                ## the BACK button (64 px) under either page
const GROUP_GAP := 10.0              ## extra space between the WEAPON, ABILITY and BODY groups
const TAB_W := 170.0
const TAB_GAP := 6.0
## The upgrades in display order with their group: what the weapon does, what the hero can do, what the hero survives.
const ORDER: Array[StringName] = [&"damage", &"mag", &"reload", &"blink", &"regen", &"decoy", &"armour"]
const GROUP := {&"damage": 0, &"mag": 0, &"reload": 0, &"blink": 1, &"regen": 1, &"decoy": 1, &"armour": 2}
const GROUP_NAMES: Array[String] = ["WEAPON", "ABILITY", "BODY"]

static var weapon_page := 0          ## 0 = the seven upgrades, 1.. = the weapon pages


static func page_weapons() -> Array[StringName]:
	weapon_page = clampi(weapon_page, 0, pages() - 1)
	var out: Array[StringName] = []
	if weapon_page == 0:
		return out
	var first := (weapon_page - 1) * PER_PAGE
	for i in range(first, mini(SHOP_WEAPONS.size(), first + PER_PAGE)):
		out.append(SHOP_WEAPONS[i])
	return out


static func pages() -> int:
	return 1 + maxi(1, (SHOP_WEAPONS.size() + PER_PAGE - 1) / PER_PAGE)


static func flip() -> void:
	weapon_page = (weapon_page + 1) % pages()


## Base y of upgrade row `i` of ORDER (a small gap opens between groups).
static func row_y(i: int) -> float:
	return ROW_Y + float(i) * ROW_STEP + float(GROUP[ORDER[i]]) * GROUP_GAP


## The HERO tab bar (8..72 base px): UPGRADES, WEAPONS, SKILLS, CRAFT. `active` is the id of the lit tab. Shared by the shop, skills and workbench screens.
static func tabs(hud: Hud, cx: float, s: float, active: StringName) -> void:
	var specs: Array = [[&"hero_tab_up", "UPGRADES"], [&"hero_tab_weapons", "WEAPONS"], [&"hero_tab_skills", "SKILLS"], [&"hero_tab_craft", "CRAFT"]]
	var total := 4.0 * TAB_W + 3.0 * TAB_GAP
	var k := minf(1.0, hud.get_viewport().get_visible_rect().size.x * 0.97 / (total * s))
	for i in specs.size():
		var tid: StringName = specs[i][0]
		var label: String = specs[i][1]
		if tid == &"hero_tab_skills" and SkillTree.points() > 0:
			label = "SKILLS  %d" % SkillTree.points()
		hud._add(tid, Rect2(cx + (-total * 0.5 + float(i) * (TAB_W + TAB_GAP)) * s * k, 8.0 * s, TAB_W * s * k, 64.0 * s), label, tid == active)


## Which tab is lit on the shop screen itself.
static func active_tab() -> StringName:
	return &"hero_tab_up" if weapon_page == 0 else &"hero_tab_weapons"


static func layout(hud: Hud, cx: float, s: float) -> void:
	var prog := Game.progress as Progress
	if hud._hero_hub:
		tabs(hud, cx, s, active_tab())
	if weapon_page == 0:
		for i in ORDER.size():
			var id: StringName = ORDER[i]
			var lvl := prog.level(id) if prog != null else 0
			var label := "MAX"
			var affordable := false
			if lvl < Upgrades.MAX_LEVEL:
				var price := prog.price(id) if prog != null else 0
				label = "BUY  %d" % price
				affordable = prog != null and prog.credits >= price
			hud._add_row(StringName("buy_%s" % id), Rect2(cx - ROW_W * 0.5 * s, row_y(i) * s, ROW_W * s, 64.0 * s), label, affordable)     # the whole row is the button: one tap buys
	var colw := ROW_W / PER_ROW
	var pw := page_weapons()
	for k in pw.size():
		var wid: StringName = pw[k]
		var owned := WeaponDefs.is_unlocked(wid)
		var wl := "OWNED" if owned else "BUY  %d" % (prog.weapon_price(wid) if prog != null else 0)
		var ry := (ROW_Y + 36.0 + (k / PER_ROW) * CELL_STEP) * s
		hud._add(StringName("buy_%s" % wid), Rect2(cx + (-ROW_W * 0.5 + (k % PER_ROW) * colw + 4.0) * s, ry, (colw - 8.0) * s, 64.0 * s), wl, prog != null and prog.can_buy_weapon(wid))
	hud._add(&"shop_back", Rect2(cx - 110.0 * s, BACK_Y * s, 220.0 * s, 64.0 * s), "BACK", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var prog := Game.progress as Progress
	if prog != null:
		var line := "CREDITS  %d" % prog.credits
		hud._text(c, font, Vector2(0.0, (ROW_Y - 14.0) * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	var x0 := cx - ROW_W * 0.5 * s
	if weapon_page == 0:
		var gcol: Array[Color] = [Color(UiUtil.AMBER, 0.95), Color(UiUtil.CYAN, 0.95), Color(UiUtil.MAGENTA, 0.95)]
		for i in ORDER.size():
			var id: StringName = ORDER[i]
			var y := row_y(i) * s
			var lvl := prog.level(id) if prog != null else 0
			hud._rect(c, Rect2(x0, y, 6.0 * s, 64.0 * s), gcol[int(GROUP[id])])               # the group colour: weapon, ability, body
			hud._text(c, font, Vector2(x0 + 18.0 * s, y + 27.0 * s), Upgrades.title(id), HORIZONTAL_ALIGNMENT_LEFT, 250.0 * s, int(22.0 * s), Color(1, 1, 1, 0.97), 1.0 * s)
			for k in Upgrades.MAX_LEVEL:
				hud._rect(c, Rect2(x0 + (262.0 + k * 20.0) * s, y + 12.0 * s, 14.0 * s, 14.0 * s), Color(UiUtil.AMBER, 0.95) if k < lvl else Color(1, 1, 1, 0.18))
			var eff := Upgrades.effect_text(id, lvl)
			var ew := (ROW_W - BUY_W - 30.0) * s
			hud._text(c, font, Vector2(x0 + 18.0 * s, y + 53.0 * s), eff, HORIZONTAL_ALIGNMENT_LEFT, ew, UiUtil.fit_size(font, eff, ew, int(UiUtil.BAR_LABEL * s)), Color(UiUtil.CYAN, 0.9), 1.0 * s)
			var price := prog.price(id) if prog != null else 0
			var txt := "MAX"
			var col := Color(UiUtil.AMBER, 0.95)
			if lvl < Upgrades.MAX_LEVEL:
				var ok := prog != null and prog.credits >= price
				txt = "BUY  %d" % price if ok else "NEED  %d" % price
				col = Color(UiUtil.GREEN, 1.0) if ok else Color(1, 1, 1, 0.5)
			hud._text(c, font, Vector2(x0 + (ROW_W - BUY_W) * s, y + 40.0 * s), txt, HORIZONTAL_ALIGNMENT_CENTER, (BUY_W - 8.0) * s, int(24.0 * s), col, 1.0 * s)
		return
	var colw := ROW_W / PER_ROW
	var pw := page_weapons()
	for k in pw.size():
		var wid: StringName = pw[k]
		var by := (ROW_Y + 36.0 + (k / PER_ROW) * CELL_STEP) * s
		var cap := WeaponDefs.title(wid)
		hud._text(c, font, Vector2(x0 + ((k % PER_ROW) * colw + 6.0) * s, by - 6.0 * s), cap, HORIZONTAL_ALIGNMENT_LEFT, (colw - 8.0) * s, UiUtil.fit_size(font, cap, (colw - 8.0) * s, int(22.0 * s)), Color(1, 1, 1, 0.97), 1.0 * s)
