class_name ShopScreen
extends RefCounted
## The upgrade shop of the pause menu (Hud draws it when `_shop_open`): seven rows (name, level pips, what the next level changes, a BUY button with the price after the
## reputation discount) and a BACK button. Buttons are ordinary Hud screen buttons: `buy_<id>`, `shop_back`; the purchase itself is Progress.buy(). Pure layout and drawing,
## no state of its own; every number comes from Upgrades and Progress.

const ROW_Y := 150.0                 ## base px of the first row
const ROW_STEP := 52.0
const ROW_W := 700.0
const BUY_W := 150.0
const SHOP_WEAPONS: Array[StringName] = [&"scatter", &"lance", &"grenade", &"burst", &"rail", &"flux", &"gravity", &"minigun", &"akimbo", &"arc", &"revolver", &"whip", &"blade"]
const PER_ROW := 4
const PER_PAGE := 8                  ## two rows; the MORE button flips the page

static var weapon_page := 0


static func page_weapons() -> Array[StringName]:
	weapon_page = clampi(weapon_page, 0, pages() - 1)
	var out: Array[StringName] = []
	for i in range(weapon_page * PER_PAGE, mini(SHOP_WEAPONS.size(), (weapon_page + 1) * PER_PAGE)):
		out.append(SHOP_WEAPONS[i])
	return out


static func pages() -> int:
	return maxi(1, (SHOP_WEAPONS.size() + PER_PAGE - 1) / PER_PAGE)


static func flip() -> void:
	weapon_page = (weapon_page + 1) % pages()


static func layout(hud: Hud, cx: float, s: float) -> void:
	var prog := Game.progress as Progress
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
		hud._add(StringName("buy_%s" % id), Rect2(cx + (ROW_W * 0.5 - BUY_W) * s, y + 4.0 * s, BUY_W * s, 42.0 * s), label, affordable)
	var wy := (ROW_Y + Upgrades.IDS.size() * ROW_STEP) * s
	var colw := ROW_W / PER_ROW
	var pw := page_weapons()
	for k in pw.size():
		var wid: StringName = pw[k]
		var owned := WeaponDefs.is_unlocked(wid)
		var wl := "OWNED" if owned else "BUY  %d" % (prog.weapon_price(wid) if prog != null else 0)
		var ry := wy + (k / PER_ROW) * 50.0 * s
		hud._add(StringName("buy_%s" % wid), Rect2(cx + (-ROW_W * 0.5 + (k % PER_ROW) * colw + 52.0) * s, ry + 26.0 * s, (colw - 58.0) * s, 40.0 * s), wl, prog != null and prog.can_buy_weapon(wid))
	hud._add(&"side_open", Rect2(cx - 170.0 * s, (ROW_Y + Upgrades.IDS.size() * ROW_STEP + 120.0) * s, 160.0 * s, 44.0 * s), "MISSIONS", false)
	hud._add(&"look_open", Rect2(cx + 10.0 * s, (ROW_Y + Upgrades.IDS.size() * ROW_STEP + 120.0) * s, 160.0 * s, 44.0 * s), "SUIT", false)
	hud._add(&"loadout", Rect2(cx - 340.0 * s, (ROW_Y + Upgrades.IDS.size() * ROW_STEP + 120.0) * s, 160.0 * s, 44.0 * s), "LOADOUT", false)
	hud._add(&"skills_open", Rect2(cx - 530.0 * s, (ROW_Y + Upgrades.IDS.size() * ROW_STEP + 100.0) * s, 180.0 * s, 64.0 * s), "SKILLS  %d" % SkillTree.points(), SkillTree.points() > 0)
	hud._add(&"shop_wpage", Rect2(cx + 350.0 * s, (ROW_Y + Upgrades.IDS.size() * ROW_STEP + 100.0) * s, 150.0 * s, 64.0 * s), "MORE %d/%d" % [weapon_page + 1, pages()], false)
	hud._add(&"shop_back", Rect2(cx + 180.0 * s, (ROW_Y + Upgrades.IDS.size() * ROW_STEP + 120.0) * s, 160.0 * s, 44.0 * s), "BACK", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var prog := Game.progress as Progress
	hud._text(c, font, Vector2(0.0, 92.0 * s), "UPGRADES", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(52.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
	if prog != null:
		var line := "CREDITS  %d      REPUTATION  %s" % [prog.credits, Progress.rep_name(prog.reputation)]
		hud._text(c, font, Vector2(0.0, 128.0 * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	var x0 := cx - ROW_W * 0.5 * s
	for i in Upgrades.IDS.size():
		var id: StringName = Upgrades.IDS[i]
		var y := (ROW_Y + i * ROW_STEP) * s
		var lvl := prog.level(id) if prog != null else 0
		hud._rect(c, Rect2(x0, y, ROW_W * s, 50.0 * s), Color(0.0, 0.03, 0.05, 0.55))
		hud._text(c, font, Vector2(x0 + 12.0 * s, y + 22.0 * s), Upgrades.title(id), HORIZONTAL_ALIGNMENT_LEFT, 260.0 * s, int(22.0 * s), Color(1, 1, 1, 0.97), 1.0 * s)
		for k in Upgrades.MAX_LEVEL:
			var pip := Rect2(x0 + (250.0 + k * 22.0) * s, y + 8.0 * s, 16.0 * s, 16.0 * s)
			hud._rect(c, pip, Color(UiUtil.AMBER, 0.95) if k < lvl else Color(1, 1, 1, 0.15))
		hud._text(c, font, Vector2(x0 + 12.0 * s, y + 44.0 * s), Upgrades.effect_text(id, lvl), HORIZONTAL_ALIGNMENT_LEFT, (ROW_W - BUY_W - 24.0) * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.9), 1.0 * s)
	var wy := (ROW_Y + Upgrades.IDS.size() * ROW_STEP) * s
	hud._text(c, font, Vector2(x0, wy + 18.0 * s), "ALIEN WEAPONS", HORIZONTAL_ALIGNMENT_LEFT, 300.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)
	var colw := ROW_W / PER_ROW
	var pw := page_weapons()
	for k in pw.size():
		var wid: StringName = pw[k]
		hud._text(c, font, Vector2(x0 + (k % PER_ROW) * colw * s, wy + (56.0 + (k / PER_ROW) * 50.0) * s), String(WeaponDefs.def(wid)["tag"]), HORIZONTAL_ALIGNMENT_LEFT, 80.0 * s, int(22.0 * s), Color(1, 1, 1, 0.97), 1.0 * s)
