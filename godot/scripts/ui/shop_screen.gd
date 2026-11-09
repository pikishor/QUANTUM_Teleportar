class_name ShopScreen
extends RefCounted
## The upgrade shop of the pause menu (Hud draws it when `_shop_open`): seven rows (name, level pips, what the next level changes, a BUY button with the price after the
## reputation discount) and a BACK button. Buttons are ordinary Hud screen buttons: `buy_<id>`, `shop_back`; the purchase itself is Progress.buy(). Pure layout and drawing,
## no state of its own; every number comes from Upgrades and Progress.

const ROW_Y := 120.0                 ## base px of the first upgrade row (the HERO tab bar sits above, 8..72)
const ROW_STEP := 66.0               ## a 64 px BUY button per row
const ROW_W := 700.0
const BUY_W := 150.0
const SHOP_WEAPONS: Array[StringName] = [&"marksman", &"burst", &"revolver", &"akimbo", &"breacher", &"arc", &"lance", &"whip", &"rocket", &"minigun", &"grenade", &"swarm", &"vector", &"battle", &"sawn", &"auto", &"bolt", &"dmr", &"knife", &"magnum", &"mpistol", &"stun", &"ranger", &"bullpup", &"lmg", &"amr", &"xbow", &"flame", &"katana", &"bat", &"qsuper", &"qlink", &"qcollapse", &"qblink", &"qphase", &"qstasis", &"eplasma", &"erepeat", &"espike", &"ebeam", &"eblade", &"emaul", &"epod", &"railgun", &"chaingun", &"cmissile", &"napalm", &"sing", &"orbital", &"seeker", &"tknife"]
const PER_ROW := 3
const PER_PAGE := 12                 ## four rows of three 64 px cells; page 0 is the upgrades, the weapons follow on pages 1..
const CELL_STEP := 92.0              ## a caption line over a 64 px BUY cell
const BACK_Y := 640.0                ## the BACK button (64 px) under either page
const GROUP_GAP := 10.0              ## extra space between the WEAPON, ABILITY and BODY groups
const TAB_W := 210.0
const TAB_GAP := 6.0
## The upgrades with their group colour: what the weapon does, what the hero can do, what the hero survives. The list itself is flat (`order()`: Upgrades.SIMPLE, the four advanced rows
## only while Upgrades.show_all is on); there is no gap between groups.
const GROUP := {&"damage": 0, &"mag": 0, &"reload": 0, &"blink": 1, &"regen": 1, &"decoy": 1, &"power": 1, &"armour": 2, &"health": 2}
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
	return 1 + WeaponsScreen.PAGES                          # the upgrades, then the three pages of the weapons catalogue (scripts/ui/weapons_screen.gd)


static func flip() -> void:
	weapon_page = (weapon_page + 1) % pages()


## The upgrade rows in display order (a flat list).
static func order() -> Array[StringName]:
	return Upgrades.shop_order()


## Base y of upgrade row `i` of order().
static func row_y(i: int) -> float:
	return ROW_Y + float(i) * ROW_STEP


## The HERO tab bar (8..72 base px): UPGRADES, WEAPONS, SKILLS, CRAFT. `active` is the id of the lit tab. Shared by the shop, skills and workbench screens.
static func tabs(hud: Hud, cx: float, s: float, active: StringName) -> void:
	var specs: Array = [[&"hero_tab_up", "UPGRADES", &"hero"], [&"hero_tab_weapons", "WEAPONS", &"weapon"]]
	if MenuFlags.show_cut():                                            # skill tree and workbench stay behind the flag (DESIGN.md cut list; MenuFlags)
		specs.append_array([[&"hero_tab_skills", "SKILLS", &"star"], [&"hero_tab_craft", "CRAFT", &"gear"]])
	var total := float(specs.size()) * TAB_W + float(specs.size() - 1) * TAB_GAP
	var k := minf(1.0, hud.get_viewport().get_visible_rect().size.x * 0.97 / (total * s))
	for i in specs.size():
		var tid: StringName = specs[i][0]
		var label: String = specs[i][1]
		if tid == &"hero_tab_skills" and SkillTree.points() > 0:
			label = "SKILLS  %d" % SkillTree.points()
		hud.buttons.append({"id": tid, "rect": Rect2(cx + (-total * 0.5 + float(i) * (TAB_W + TAB_GAP)) * s * k, 8.0 * s, TAB_W * s * k, 64.0 * s), "label": label, "on": tid == active, "tab": specs[i][2]})


## Which tab is lit on the shop screen itself.
static func active_tab() -> StringName:
	return &"hero_tab_up" if weapon_page == 0 else &"hero_tab_weapons"


const CARD_W := 300.0
const CARD_GAP := 14.0
const ICON_OF := {&"damage": &"damage", &"mag": &"rate", &"reload": &"reload", &"blink": &"bolt", &"regen": &"heart", &"armour": &"shield", &"decoy": &"star", &"health": &"heart", &"power": &"star"}
const GROUP_TINT: Array[Color] = [Color(1.0, 0.72, 0.25), Color(0.45, 0.95, 1.0), Color(0.4, 1.0, 0.6)]


## The card of upgrade `i` of `n`: one row of up to five tall cards (the whole page of the five default upgrades), two rows when the flag shows all nine.
static func card_rect(hud: Hud, cx: float, s: float, i: int, n: int) -> Rect2:
	var cols := mini(n, 5)
	var rows := (n + cols - 1) / cols
	var total := float(cols) * CARD_W + float(cols - 1) * CARD_GAP
	var k := minf(1.0, hud.get_viewport().get_visible_rect().size.x * 0.97 / (total * s))
	var h := 396.0 if rows == 1 else 218.0
	var cnt := mini(cols, n - (i / cols) * cols)                        # a short last row is centred
	var rowtotal := float(cnt) * CARD_W + float(cnt - 1) * CARD_GAP
	return Rect2(cx + (-rowtotal * 0.5 + float(i % cols) * (CARD_W + CARD_GAP)) * s * k, (ROW_Y + 8.0 + float(i / cols) * (h + CARD_GAP)) * s, CARD_W * s * k, h * s)


static func _draw_card(hud: Hud, c: Control, s: float, font: Font, id: StringName, r: Rect2, prog: Progress) -> void:
	var lvl := prog.level(id) if prog != null else 0
	var tint: Color = GROUP_TINT[int(GROUP[id])]
	var tall := r.size.y > 300.0 * s
	var maxed := lvl >= Upgrades.MAX_LEVEL
	UiKit.panel(c, r, s, tint, hud._hover == StringName("buy_%s" % id) or (prog != null and not maxed and prog.credits >= prog.price(id)), 14.0, false)
	var price := prog.price(id) if prog != null and not maxed else 0
	var ok := prog != null and not maxed and prog.credits >= price
	# icon disc
	var ir := 38.0 * s if tall else 26.0 * s
	var ic := Vector2(r.position.x + r.size.x * 0.5, r.position.y + (62.0 * s if tall else 40.0 * s)) if tall else Vector2(r.position.x + 44.0 * s, r.position.y + 48.0 * s)
	c.draw_circle(ic, ir + 6.0 * s, Color(tint, 0.2))
	c.draw_arc(ic, ir + 6.0 * s, 0.0, TAU, 32, Color(tint, 0.8), 2.0 * s)
	UiKit.glyph(c, ICON_OF.get(id, &"star"), ic, ir * 0.62, Color(tint.lerp(Color.WHITE, 0.5), 0.98), s)
	var nm := Upgrades.title(id)
	var nx := r.position.x + 8.0 * s if tall else r.position.x + 88.0 * s
	var nw := r.size.x - 16.0 * s if tall else r.size.x - 100.0 * s
	var ny := r.position.y + 150.0 * s if tall else r.position.y + 36.0 * s
	hud._text(c, font, Vector2(nx, ny), nm, HORIZONTAL_ALIGNMENT_CENTER if tall else HORIZONTAL_ALIGNMENT_LEFT, nw, UiUtil.fit_size(font, nm, nw, int(UiKit.T_LABEL * s)), Color(1, 1, 1, 0.98), 1.0 * s)
	# level pips: one segment per level
	var py0 := r.position.y + (176.0 * s if tall else 62.0 * s)
	var px0 := r.position.x + (20.0 * s if tall else 88.0 * s)
	var pw0 := r.size.x - (40.0 * s if tall else 100.0 * s)
	var seg := (pw0 - float(Upgrades.MAX_LEVEL - 1) * 5.0 * s) / float(Upgrades.MAX_LEVEL)
	for k in Upgrades.MAX_LEVEL:
		var sr := Rect2(px0 + float(k) * (seg + 5.0 * s), py0, seg, 12.0 * s)
		c.draw_rect(sr, Color(tint, 0.95) if k < lvl else Color(1, 1, 1, 0.14))
		if k == lvl and not maxed:
			c.draw_rect(sr, Color(tint, 0.7), false, 1.5 * s)
	# what it does now and after the next level
	var eff := Upgrades.effect_text(id, lvl)
	var parts := eff.split("  >  ")
	if tall:
		var cur := String(parts[0])
		hud._text(c, font, Vector2(r.position.x, r.position.y + 226.0 * s), cur, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UiUtil.fit_size(font, cur, r.size.x - 16.0 * s, int(UiKit.T_BODY * s)), Color(1, 1, 1, 0.78))
		if parts.size() > 1:
			var ap := Vector2(r.position.x + r.size.x * 0.5, r.position.y + 250.0 * s)           # a down arrow: from what you have to what the next level gives
			c.draw_colored_polygon(PackedVector2Array([ap + Vector2(-10.0, -7.0) * s, ap + Vector2(10.0, -7.0) * s, ap + Vector2(0.0, 8.0) * s]), Color(tint, 0.95))
			var nxt := String(parts[1])
			hud._text(c, font, Vector2(r.position.x, r.position.y + 292.0 * s), nxt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UiUtil.fit_size(font, nxt, r.size.x - 16.0 * s, int(UiKit.T_TITLE * s)), Color(tint.lerp(Color.WHITE, 0.45), 1.0), 1.0 * s)
		else:
			hud._text(c, font, Vector2(r.position.x, r.position.y + 292.0 * s), "MAXED OUT", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(UiKit.T_TITLE * s), Color(UiUtil.AMBER, 1.0), 1.0 * s)
	else:
		var ex := r.position.x + 88.0 * s
		var ew := r.size.x - 100.0 * s
		var shown := String(parts[parts.size() - 1])
		hud._text(c, font, Vector2(ex, r.position.y + 112.0 * s), shown, HORIZONTAL_ALIGNMENT_LEFT, ew, UiUtil.fit_size(font, shown, ew, int(UiKit.T_BODY * s)), Color(tint.lerp(Color.WHITE, 0.45), 0.98))
	# the BUY strip along the bottom
	var strip := Rect2(r.position.x + 10.0 * s, r.end.y - 62.0 * s, r.size.x - 20.0 * s, 52.0 * s)
	var scol := UiUtil.AMBER if maxed else (UiUtil.GREEN if ok else Color(1, 1, 1, 0.5))
	c.draw_rect(strip, Color(scol.r, scol.g, scol.b, 0.32 if (ok or maxed) else 0.12))
	c.draw_rect(strip, Color(scol.r, scol.g, scol.b, 0.9 if (ok or maxed) else 0.35), false, 2.0 * s)
	var txt := "MAX" if maxed else (("BUY  %d" % price) if ok else ("NEED  %d" % price))
	hud._text(c, font, Vector2(strip.position.x, strip.position.y + strip.size.y * 0.5 + 8.0 * s), txt, HORIZONTAL_ALIGNMENT_CENTER, strip.size.x, int(UiKit.T_TITLE * s), Color(scol.lerp(Color.WHITE, 0.35), 1.0), 1.0 * s)
	if tall and ok:
		UiKit.glyph(c, &"coin", Vector2(strip.position.x + 26.0 * s, strip.position.y + strip.size.y * 0.5), 10.0 * s, Color(UiUtil.AMBER, 0.95), s)


static func layout(hud: Hud, cx: float, s: float) -> void:
	var prog := Game.progress as Progress
	if hud._hero_hub:
		tabs(hud, cx, s, active_tab())
	if weapon_page == 0:
		var ord := order()
		for i in ord.size():
			var id: StringName = ord[i]
			var lvl := prog.level(id) if prog != null else 0
			var label := "MAX"
			var affordable := false
			if lvl < Upgrades.MAX_LEVEL:
				var price := prog.price(id) if prog != null else 0
				label = "BUY  %d" % price
				affordable = prog != null and prog.credits >= price
			hud._add_row(StringName("buy_%s" % id), card_rect(hud, cx, s, i, ord.size()), label, affordable)     # the whole card is the button: one tap buys
			hud.buttons[hud.buttons.size() - 1]["own"] = true                                                  # drawn by _draw_card below (plate and content in one pass)
	if weapon_page > 0:
		WeaponsScreen.layout(hud, cx, s)
		return
	var colw := ROW_W / PER_ROW
	var pw := page_weapons()
	for k in pw.size():
		var wid: StringName = pw[k]
		var owned := WeaponDefs.is_unlocked(wid)
		var wl := "OWNED" if owned else "BUY  %d" % (prog.weapon_price(wid) if prog != null else 0)
		var ry := (ROW_Y + 36.0 + (k / PER_ROW) * CELL_STEP) * s
		hud._add(StringName("buy_%s" % wid), Rect2(cx + (-ROW_W * 0.5 + (k % PER_ROW) * colw + 4.0) * s, ry, (colw - 8.0) * s, 64.0 * s), wl, prog != null and prog.can_buy_weapon(wid))
	hud._add(&"shop_back", Rect2(cx - 110.0 * s, BACK_Y * s, 220.0 * s, 64.0 * s), "BACK", false)       # the cards fill the width: BACK is always the one centred row under them


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var prog := Game.progress as Progress
	if prog != null and weapon_page == 0:
		var line := "CREDITS  %d" % prog.credits
		hud._text(c, font, Vector2(0.0, (ROW_Y - 14.0) * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	var x0 := cx - ROW_W * 0.5 * s
	if weapon_page == 0:
		var ord := order()
		for i in ord.size():
			_draw_card(hud, c, s, font, ord[i], card_rect(hud, cx, s, i, ord.size()), prog)
		return
	WeaponsScreen.draw(hud, c, vp, s, font, cx)
	return
	var colw := ROW_W / PER_ROW
	var pw := page_weapons()
	for k in pw.size():
		var wid: StringName = pw[k]
		var by := (ROW_Y + 36.0 + (k / PER_ROW) * CELL_STEP) * s
		var cap := WeaponDefs.title(wid)
		hud._text(c, font, Vector2(x0 + ((k % PER_ROW) * colw + 6.0) * s, by - 6.0 * s), cap, HORIZONTAL_ALIGNMENT_LEFT, (colw - 8.0) * s, UiUtil.fit_size(font, cap, (colw - 8.0) * s, int(22.0 * s)), Color(1, 1, 1, 0.97), 1.0 * s)
