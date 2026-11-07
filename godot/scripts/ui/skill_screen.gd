class_name SkillScreen
extends RefCounted
## The SKILLS screen (Hud draws it on the pause screen when `_skills_open`, reached from the UPGRADES shop by the SKILLS button): four columns (QUANTUM TELEPORT, SUPERPOSITION,
## ENTANGLE, COLLAPSE) of five 64 px node buttons `sk_<node id>` (tap = spend a point on the next rank), RESPEC `sk_respec` (refunds every rank for credits) and BACK `sk_back`.
## Numbers live in SkillTree, the wallet and purchases in Progress. A tap on a node also selects it: its effect line is shown under the columns.

const BTN_H := 64.0
const COL_W := 290.0
const COL_GAP := 10.0
const ROW_Y := 184.0
const ROW_STEP := 70.0
const FOOT_Y := 624.0

static var selected: StringName = &""


static func _col_x(cx: float, s: float, k: float, v: int) -> float:
	var total := 4.0 * COL_W + 3.0 * COL_GAP
	return cx + (-total * 0.5 + float(v) * (COL_W + COL_GAP)) * s * k


static func _fit(hud: Hud, s: float) -> float:
	return minf(1.0, hud.get_viewport().get_visible_rect().size.x * 0.97 / ((4.0 * COL_W + 3.0 * COL_GAP) * s))


static func _label(id: StringName) -> String:
	var r := SkillTree.rank(id)
	var m := SkillTree.max_rank(id)
	return "%s  %d/%d" % [SkillTree.title(id), r, m] if SkillTree.unlocked(id) else "%s  LOCKED" % SkillTree.title(id)


static func layout(hud: Hud, cx: float, s: float) -> void:
	var k := _fit(hud, s)
	for v in SkillTree.VERBS.size():
		var nodes := SkillTree.verb_nodes(SkillTree.VERBS[v])
		for i in nodes.size():
			var id := nodes[i]
			hud._add(StringName("sk_%s" % id), Rect2(_col_x(cx, s, k, v), (ROW_Y + float(i) * ROW_STEP) * s, COL_W * s * k, BTN_H * s), _label(id), SkillTree.can_buy(id))
	var prog := Game.progress as Progress
	var price := SkillTree.respec_price()
	hud._add(&"sk_respec", Rect2(cx - 330.0 * s * k, FOOT_Y * s, 320.0 * s * k, BTN_H * s), "RESPEC  %d" % price, prog != null and SkillTree.spent() > 0 and prog.credits >= price)
	hud._add(&"sk_back", Rect2(cx + 10.0 * s * k, FOOT_Y * s, 320.0 * s * k, BTN_H * s), "BACK", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var prog := Game.progress as Progress
	var k := _fit(hud, s)
	if not hud._hero_hub:
		hud.header(c, vp, s, font, "SKILLS")
	var lp := SkillTree.level_progress()
	var xp_line := "MAX LEVEL" if int(lp[1]) == 0 else "XP  %d / %d" % [lp[0], lp[1]]
	var line := "LEVEL  %d      POINTS  %d      %s" % [SkillTree.level(), SkillTree.points(), xp_line]
	if prog != null:
		line += "      CREDITS  %d" % prog.credits
	hud._text(c, font, Vector2(0.0, 118.0 * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	for v in SkillTree.VERBS.size():
		var verb: StringName = SkillTree.VERBS[v]
		hud._text(c, font, Vector2(_col_x(cx, s, k, v), (ROW_Y - 12.0) * s), String(SkillTree.VERB_NAMES[verb]), HORIZONTAL_ALIGNMENT_LEFT, COL_W * s * k, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	var info := "TAP A NODE TO SPEND A POINT"
	if SkillTree.NODES.has(selected):
		info = "%s   %s   RANK %d/%d" % [SkillTree.title(selected), SkillTree.effect_text(selected), SkillTree.rank(selected), SkillTree.max_rank(selected)]
	hud._text(c, font, Vector2(0.0, (ROW_Y + 5.0 * ROW_STEP + 22.0) * s), info, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * s), Color(1, 1, 1, 0.9), 0.0)


static func press(sid: String) -> bool:
	var prog := Game.progress as Progress
	if prog == null:
		return false
	if sid == "sk_respec":
		var ok := prog.respec_skills()
		Sfx.play(&"ui_purchase" if ok else &"ui_deny")
		return ok
	var id := StringName(sid.substr(3))
	if not SkillTree.NODES.has(id):
		return false
	selected = id
	var ok2 := prog.buy_skill(id)
	Sfx.play(&"ui_purchase" if ok2 else &"ui_deny")
	return ok2
