class_name HeistBoard
extends RefCounted
## The heist planning screen of the pause shop (Hud draws it when `_heist_open`, opened by the shop's HEISTS button): pick a heist (`heist_pick_<id>`), the approach (`heist_ap_<id>`:
## STEALTH / LOUD / QUANTUM), the crew (`heist_crew`, the Vael defector ally on or off), then LAUNCH (`heist_go`) or BACK (`heist_back`). Buttons are 64 px tall. Pure layout and drawing:
## the rules live in HeistScripts / HeistRunner, the tally in Progress.heist_done.

const COL_W := 260.0
const GAP := 20.0
const BTN_H := 64.0
const ROW_PICK := 120.0
const ROW_INFO := 196.0
const ROW_AP := 320.0
const ROW_GO := 400.0

static var sel: StringName = &"vault"
static var approach: StringName = &"stealth"
static var crew := false


static func _chapter() -> int:
	return int(Game.story.get("chapter")) if is_instance_valid(Game.story) else 0


static func runner() -> HeistRunner:
	return (Game.missions as Missions).heists if Game.missions is Missions else null


static func _col(cx: float, s: float, i: int) -> float:
	return cx + (-COL_W * 1.5 - GAP + i * (COL_W + GAP)) * s


## Credits of a run with the current plan (what the panel shows and the runner pays).
static func payout() -> int:
	var prog := Game.progress as Progress
	return HeistScripts.reward(sel, approach, _chapter(), prog.reputation if prog != null else 0, prog != null and int(prog.heist_done.get(sel, 0)) > 0)


static func layout(hud: Hud, cx: float, s: float) -> void:
	for i in HeistScripts.IDS.size():
		var hid: StringName = HeistScripts.IDS[i]
		hud._add(StringName("heist_pick_%s" % hid), Rect2(_col(cx, s, i), ROW_PICK * s, COL_W * s, BTN_H * s), HeistScripts.title(hid), hid == sel)
	for i in HeistScripts.APPROACHES.size():
		var ap: StringName = HeistScripts.APPROACHES[i]
		hud._add(StringName("heist_ap_%s" % ap), Rect2(_col(cx, s, i), ROW_AP * s, COL_W * s, BTN_H * s), HeistScripts.approach_title(ap), ap == approach)
	var r := runner()
	var ok := r != null and r.can_start(sel)
	hud._add(&"heist_crew", Rect2(_col(cx, s, 0), ROW_GO * s, COL_W * s, BTN_H * s), "CREW  ALLY" if crew else "CREW  SOLO", crew)
	hud._add(&"heist_go", Rect2(_col(cx, s, 1), ROW_GO * s, COL_W * s, BTN_H * s), "LAUNCH" if HeistScripts.unlocked(sel, _chapter()) else "LOCKED", ok)
	hud._add(&"heist_back", Rect2(_col(cx, s, 2), ROW_GO * s, COL_W * s, BTN_H * s), "BACK", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var prog := Game.progress as Progress
	hud.header(c, vp, s, font, "HEISTS")
	var d: Dictionary = HeistScripts.DEFS[sel]
	var open := HeistScripts.unlocked(sel, _chapter())
	var x := _col(cx, s, 0)
	var w := (COL_W * 3.0 + GAP * 2.0) * s
	hud._rect(c, Rect2(x, ROW_INFO * s, w, 112.0 * s), MenuKit.FILL)
	hud._text(c, font, Vector2(x + 10.0 * s, (ROW_INFO + 26.0) * s), String(d["brief"]), HORIZONTAL_ALIGNMENT_LEFT, w - 20.0 * s, int(UiUtil.BAR_LABEL * s), Color(1, 1, 1, 0.95 if open else 0.5), 1.0 * s)
	hud._text(c, font, Vector2(x + 10.0 * s, (ROW_INFO + 54.0) * s), String(d["stages"]), HORIZONTAL_ALIGNMENT_LEFT, w - 20.0 * s, int(18.0 * s), Color(UiUtil.CYAN, 0.9), 1.0 * s)
	var done := int(prog.heist_done.get(sel, 0)) if prog != null else 0
	var info := "NEEDS SECTOR %d" % (int(Economy.HEIST_CHAPTER[sel]) + 1) if not open else "%d CR%s   %s" % [payout(), "  (REPLAY)" if done > 0 else "", ("DONE x%d" % done) if done > 0 else "NEW"]
	hud._text(c, font, Vector2(x + 10.0 * s, (ROW_INFO + 82.0) * s), info, HORIZONTAL_ALIGNMENT_LEFT, w - 20.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.97 if open else 0.5), 1.0 * s)
	hud._text(c, font, Vector2(0.0, (ROW_AP - 10.0) * s), String(HeistScripts.APPROACH_DEFS[approach]["note"]), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(18.0 * s), Color(UiUtil.CYAN, 0.9), 1.0 * s)
