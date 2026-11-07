class_name ChapterSelect
extends RefCounted
## The chapter select of the title and pause screens (Hud draws it when `_chapters_open`): a grid of one big touch cell per chapter (unlocked ones are buttons `chapter_<i>`, locked ones
## are dim plates), the chapter's title under its number, and a BACK button (`chapters_back`). Choosing a cell calls Progress.start_chapter(i), which keeps credits, upgrades and
## reputation and plays that chapter from its first step. Pure layout and drawing, no state of its own: every number comes from Progress and CampaignRunner.

const COLS := 4
const CELL_W := 170.0                 ## base px
const CELL_H := 84.0
const GAP := 12.0
const TOP := 190.0
const BACK_H := 64.0


static func cell_rect(i: int, cx: float, s: float) -> Rect2:
	var col := i % COLS
	var row := i / COLS
	var total_w := COLS * CELL_W + (COLS - 1) * GAP
	return Rect2(cx - total_w * 0.5 * s + col * (CELL_W + GAP) * s, (TOP + row * (CELL_H + GAP)) * s, CELL_W * s, CELL_H * s)


static func rows() -> int:
	return int(ceil(float(CampaignRunner.chapter_count()) / float(COLS)))


static func layout(hud: Hud, cx: float, s: float) -> void:
	var prog := Game.progress as Progress
	var open := prog.chapters_unlocked() if prog != null else 1
	var current := int(Game.story.get("chapter")) if is_instance_valid(Game.story) else -1
	for i in CampaignRunner.chapter_count():
		if i < open:
			hud._add(StringName("chapter_%d" % i), cell_rect(i, cx, s), "CH %d" % (i + 1), i == current and Game.state == &"paused")
	hud._add(&"chapters_back", Rect2(cx - 110.0 * s, (TOP + rows() * (CELL_H + GAP) + 18.0) * s, 220.0 * s, BACK_H * s), "BACK", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var prog := Game.progress as Progress
	var open := prog.chapters_unlocked() if prog != null else 1
	hud.header(c, vp, s, font, "CHAPTERS")
	var sub := "%d OF %d UNLOCKED   CREDITS AND UPGRADES KEPT" % [open, CampaignRunner.chapter_count()]
	hud._text(c, font, Vector2(0.0, 134.0 * s), sub, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	for i in CampaignRunner.chapter_count():
		var r := cell_rect(i, cx, s)
		var title := CampaignRunner.chapter_title(i)
		if i >= open:
			hud._rect(c, r, Color(0.0, 0.03, 0.05, 0.55))
			hud._frame(c, r, Color(1, 1, 1, 0.14), 1.0 * s)
			hud._text(c, font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 8.0 * s), "LOCKED", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(20.0 * s), Color(1, 1, 1, 0.3))
			continue
		var size := int(16.0 * s)
		while size > int(11.0 * s) and hud._text_width(font, title, size) > r.size.x - 10.0 * s:
			size -= 1
		hud._text(c, font, Vector2(r.position.x, r.end.y - 9.0 * s), title, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, Color(UiUtil.CYAN, 0.95), 1.0 * s)
