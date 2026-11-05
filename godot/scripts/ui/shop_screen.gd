class_name ShopScreen
extends RefCounted
## The upgrade shop of the pause menu (Hud draws it when `_shop_open`): seven rows (name, level pips, what the next level changes, a BUY button with the price after the
## reputation discount) and a BACK button. Buttons are ordinary Hud screen buttons: `buy_<id>`, `shop_back`; the purchase itself is Progress.buy(). Pure layout and drawing,
## no state of its own; every number comes from Upgrades and Progress.

const ROW_Y := 134.0                 ## base px of the first upgrade row
const ROW_STEP := 66.0               ## a 64 px BUY button per row
const ROW_W := 700.0
const BUY_W := 150.0
const SHOP_WEAPONS: Array[StringName] = [&"scatter", &"lance", &"grenade", &"burst", &"rail", &"flux", &"gravity", &"minigun", &"akimbo", &"arc", &"revolver", &"whip", &"blade"]
const PER_ROW := 4
const PER_PAGE := 16                 ## four rows of four 64 px cells; page 0 is the upgrades, the weapons follow on pages 1..
const CELL_STEP := 92.0              ## a caption line over a 64 px BUY cell
const NAV_Y := 608.0                 ## the navigation row (64 px) under either page

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


static func layout(hud: Hud, cx: float, s: float) -> void:
	var prog := Game.progress as Progress
	if weapon_page == 0:
		for i in Upgrades.IDS.size():
			var id: StringName = Upgrades.IDS[i]
			var y := (ROW_Y + i * ROW_STEP) * s
			var lvl := prog.level(id) if prog != null else 0
			var label := "MAX"
			var affordable := false
			if lvl < Upgrades.MAX_LEVEL:
				var price := prog.price(id) if prog != null else 0
				label = "BUY  %d" % price
				affordable = prog != null and prog.credits >= price
			hud._add(StringName("buy_%s" % id), Rect2(cx + (ROW_W * 0.5 - BUY_W) * s, y, BUY_W * s, 64.0 * s), label, affordable)
	var colw := ROW_W / PER_ROW
	var pw := page_weapons()
	for k in pw.size():
		var wid: StringName = pw[k]
		var owned := WeaponDefs.is_unlocked(wid)
		var wl := "OWNED" if owned else "BUY  %d" % (prog.weapon_price(wid) if prog != null else 0)
		var ry := (ROW_Y + 60.0 + (k / PER_ROW) * CELL_STEP) * s
		hud._add(StringName("buy_%s" % wid), Rect2(cx + (-ROW_W * 0.5 + (k % PER_ROW) * colw + 4.0) * s, ry, (colw - 8.0) * s, 64.0 * s), wl, prog != null and prog.can_buy_weapon(wid))
	var by := NAV_Y * s                                           # one row of eight 64 px buttons under either page
	var bw := 134.0
	var x0 := cx - (8.0 * bw + 7.0 * 8.0) * 0.5 * s
	var more := "WEAPONS" if weapon_page == 0 else ("MORE %d/%d" % [weapon_page, pages() - 1] if pages() > 2 else "UPGRADES")
	var specs: Array = [[&"skills_open", "SKILLS  %d" % SkillTree.points(), SkillTree.points() > 0], [&"loadout", "LOADOUT", false], [&"side_open", "MISSIONS", false], [&"look_open", "SUIT", false],
		[&"heist_open", "HEISTS", false], [&"cr_open", "CRAFT", false], [&"shop_wpage", more, false], [&"shop_back", "BACK", false]]
	for i in specs.size():
		hud._add(specs[i][0], Rect2(x0 + i * (bw + 8.0) * s, by, bw * s, 64.0 * s), specs[i][1], specs[i][2])


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var prog := Game.progress as Progress
	hud._text(c, font, Vector2(0.0, 86.0 * s), "UPGRADES" if weapon_page == 0 else "ALIEN WEAPONS", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(52.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
	if prog != null:
		var line := "CREDITS  %d      REPUTATION  %s" % [prog.credits, Progress.rep_name(prog.reputation)]
		hud._text(c, font, Vector2(0.0, 120.0 * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	var x0 := cx - ROW_W * 0.5 * s
	if weapon_page == 0:
		for i in Upgrades.IDS.size():
			var id: StringName = Upgrades.IDS[i]
			var y := (ROW_Y + i * ROW_STEP) * s
			var lvl := prog.level(id) if prog != null else 0
			hud._rect(c, Rect2(x0, y, ROW_W * s, 64.0 * s), Color(0.0, 0.03, 0.05, 0.55))
			hud._text(c, font, Vector2(x0 + 12.0 * s, y + 26.0 * s), Upgrades.title(id), HORIZONTAL_ALIGNMENT_LEFT, 260.0 * s, int(22.0 * s), Color(1, 1, 1, 0.97), 1.0 * s)
			for k in Upgrades.MAX_LEVEL:
				var pip := Rect2(x0 + (250.0 + k * 22.0) * s, y + 12.0 * s, 16.0 * s, 16.0 * s)
				hud._rect(c, pip, Color(UiUtil.AMBER, 0.95) if k < lvl else Color(1, 1, 1, 0.15))
			hud._text(c, font, Vector2(x0 + 12.0 * s, y + 52.0 * s), Upgrades.effect_text(id, lvl), HORIZONTAL_ALIGNMENT_LEFT, (ROW_W - BUY_W - 24.0) * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.9), 1.0 * s)
		return
	var colw := ROW_W / PER_ROW
	var pw := page_weapons()
	for k in pw.size():
		var wid: StringName = pw[k]
		var by := (ROW_Y + 60.0 + (k / PER_ROW) * CELL_STEP) * s
		hud._text(c, font, Vector2(x0 + ((k % PER_ROW) * colw + 6.0) * s, by - 6.0 * s), String(WeaponDefs.def(wid)["tag"]), HORIZONTAL_ALIGNMENT_LEFT, (colw - 8.0) * s, int(22.0 * s), Color(1, 1, 1, 0.97), 1.0 * s)
