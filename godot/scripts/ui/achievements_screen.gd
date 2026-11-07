class_name AchievementsScreen
extends RefCounted
## The achievements screen of the pause menu (Hud draws it when `_ach_open`): the 25 achievements in pages of PER_PAGE rows (title, goal, progress, reward, a bar), the shard
## count on top, PREV / NEXT / BACK buttons (`ach_prev`, `ach_next`, `ach_back`, all at least TOUCH_MIN high). Pure layout and drawing; the page lives in Hud.

const PER_PAGE := 5
const ROW_Y := 140.0
const ROW_STEP := 74.0
const ROW_W := 820.0


static func pages() -> int:
	return (Achievements.count() + PER_PAGE - 1) / PER_PAGE


static func layout(hud: Hud, cx: float, s: float, page: int) -> void:
	var y := (ROW_Y + PER_PAGE * ROW_STEP + 6.0) * s
	hud._add(&"ach_prev", Rect2(cx - 350.0 * s, y, 200.0 * s, UiUtil.TOUCH_MIN * s), "PREV", page > 0)
	hud._add(&"ach_back", Rect2(cx - 100.0 * s, y, 200.0 * s, UiUtil.TOUCH_MIN * s), "BACK", false)
	hud._add(&"ach_next", Rect2(cx + 150.0 * s, y, 200.0 * s, UiUtil.TOUCH_MIN * s), "NEXT", page < pages() - 1)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float, page: int) -> void:
	var prog := Game.progress as Progress
	var ach: Achievements = prog.achievements if prog != null else null
	hud.header(c, vp, s, font, "ACHIEVEMENTS")
	if ach == null:
		return
	var shards := prog.collectibles.count()
	var line := "%d / %d UNLOCKED      SHARDS  %d / %d      PAGE %d / %d" % [ach.unlocked_count(), Achievements.count(), shards, Collectibles.COUNT, page + 1, pages()]
	hud._text(c, font, Vector2(0.0, 118.0 * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	var x0 := cx - ROW_W * 0.5 * s
	for k in PER_PAGE:
		var i := page * PER_PAGE + k
		if i >= Achievements.count():
			break
		var d: Array = Achievements.DEFS[i]
		var y := (ROW_Y + k * ROW_STEP) * s
		var got := ach.is_done(d[0])
		hud._rect(c, Rect2(x0, y, ROW_W * s, 68.0 * s), Color(0.0, 0.03, 0.05, 0.6))
		hud._rect(c, Rect2(x0, y, 5.0 * s, 68.0 * s), Color(UiUtil.AMBER, 0.95) if got else Color(1, 1, 1, 0.18))
		hud._text(c, font, Vector2(x0 + 16.0 * s, y + 26.0 * s), String(d[1]), HORIZONTAL_ALIGNMENT_LEFT, 360.0 * s, int(24.0 * s), Color(1, 1, 1, 0.97) if got else Color(1, 1, 1, 0.8), 1.0 * s)
		hud._text(c, font, Vector2(x0 + 16.0 * s, y + 50.0 * s), String(d[2]), HORIZONTAL_ALIGNMENT_LEFT, 400.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.9), 1.0 * s)
		hud._text(c, font, Vector2(x0 + (ROW_W - 316.0) * s, y + 26.0 * s), "DONE" if got else ach.progress_text(i), HORIZONTAL_ALIGNMENT_RIGHT, 300.0 * s, int(24.0 * s), Color(UiUtil.GREEN, 0.97) if got else Color(1, 1, 1, 0.85), 1.0 * s)
		hud._text(c, font, Vector2(x0 + (ROW_W - 316.0) * s, y + 50.0 * s), Achievements.reward_text(i), HORIZONTAL_ALIGNMENT_RIGHT, 300.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.9), 1.0 * s)
		if not got:
			var f := clampf(float(ach.value(i)) / float(d[4]), 0.0, 1.0)
			hud._rect(c, Rect2(x0 + 16.0 * s, y + 62.0 * s, (ROW_W - 32.0) * s * f, 3.0 * s), Color(UiUtil.CYAN, 0.8))
