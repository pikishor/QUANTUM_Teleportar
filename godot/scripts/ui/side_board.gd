class_name SideBoard
extends RefCounted
## The side-mission board of the pause shop (Hud draws it when `_side_open`): ten jobs in two columns, each with title, reward, clock, completions and a START button
## (`side_<id>`; locked jobs show the sector they need), and BACK (`side_back`). Pure layout and drawing; the rules live in SideMissions, the tallies in Progress.

const ROW_Y := 130.0
const ROW_STEP := 62.0
const COL_W := 410.0
const GAP := 20.0
const BTN_W := 112.0


static func _origin(cx: float, s: float, i: int) -> Vector2:
	var col := i / 5
	return Vector2(cx + (-COL_W - GAP * 0.5 + col * (COL_W + GAP)) * s, (ROW_Y + (i % 5) * ROW_STEP) * s)


static func _chapter() -> int:
	return int(Game.story.get("chapter")) if is_instance_valid(Game.story) else 0


static func layout(hud: Hud, cx: float, s: float) -> void:
	var sm := _sides()
	for i in SideMissions.ORDER.size():
		var mid: StringName = SideMissions.ORDER[i]
		var o := _origin(cx, s, i)
		var ok := sm != null and sm.can_start(mid)
		hud._add(StringName("side_%s" % mid), Rect2(o.x + (COL_W - BTN_W) * s, o.y + 6.0 * s, BTN_W * s, 42.0 * s), "START" if SideMissions.unlocked(mid, _chapter()) else "LOCKED", ok)
	hud._add(&"side_back", Rect2(cx - 110.0 * s, (ROW_Y + 5.0 * ROW_STEP + 14.0) * s, 220.0 * s, 44.0 * s), "BACK", false)


static func _sides() -> SideMissions:
	return (Game.missions as Missions).sides if Game.missions is Missions else null


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var prog := Game.progress as Progress
	hud._text(c, font, Vector2(0.0, 84.0 * s), "SIDE MISSIONS", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(46.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
	if prog != null:
		hud._text(c, font, Vector2(0.0, 116.0 * s), "CREDITS  %d      DONE  %d / %d" % [prog.credits, prog.side_done.size(), SideMissions.ORDER.size()], HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	for i in SideMissions.ORDER.size():
		var mid: StringName = SideMissions.ORDER[i]
		var d := SideMissions.def(mid)
		var o := _origin(cx, s, i)
		var open := SideMissions.unlocked(mid, _chapter())
		hud._rect(c, Rect2(o.x, o.y, COL_W * s, 56.0 * s), Color(0.0, 0.03, 0.05, 0.55))
		hud._text(c, font, Vector2(o.x + 10.0 * s, o.y + 24.0 * s), String(d["title"]), HORIZONTAL_ALIGNMENT_LEFT, (COL_W - BTN_W - 20.0) * s, int(UiUtil.BAR_LABEL * s), Color(1, 1, 1, 0.97 if open else 0.45), 1.0 * s)
		var done := int(prog.side_done.get(mid, 0)) if prog != null else 0
		var info := "NEEDS SECTOR %d" % (int(d["chapter"]) + 1) if not open else "%d CR   REP +%d%s%s" % [int(d["pay"]), int(d["rep"]), ("   %d s" % int(d["limit"])) if float(d["limit"]) > 0.0 else "", ("   DONE x%d" % done) if done > 0 else ""]
		hud._text(c, font, Vector2(o.x + 10.0 * s, o.y + 48.0 * s), info, HORIZONTAL_ALIGNMENT_LEFT, (COL_W - BTN_W - 20.0) * s, int(18.0 * s), Color(UiUtil.CYAN, 0.9 if open else 0.4), 1.0 * s)
