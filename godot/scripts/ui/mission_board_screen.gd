class_name MissionBoardScreen
extends RefCounted
## The Mission Board screen (Hud draws it while `_board_open`, a pause-state panel like the map): the highlighted STORY card, THREE mission cards (title, pay, distance, one line) and a bottom
## row with the EASY / NORMAL / HARD switch, NEW OFFERS and FREE ROAM. While a board mission runs the three cards give way to the running mission, RETRY STEP and ABANDON.
## Buttons: `board_story`, `board_pick_0..2`, `board_diff_0..2`, `board_new`, `board_back`, `board_retry`, `board_abandon`, all 64 px or taller; the cards are MenuKit cards (the Hud draws
## them); this file lays them out and paints the header and the result line. Rules live in MissionBoard.

const CARD_W := 760.0
const CARD_H := 78.0
const GAP := 12.0
const TOP := 128.0
const BAR_H := 64.0

const ICON_OF := {
	&"patrol": &"arena", &"boss": &"arena", &"bounty": &"arena", &"arena": &"arena", &"defend": &"arena", &"vehicle": &"arena", &"demolition": &"arena",
	&"heist": &"heists", &"hack": &"heists", &"stealth": &"hero", &"rescue": &"hero", &"escort": &"hero",
	&"courier": &"map", &"hijack": &"map", &"chase": &"map", &"convoy": &"map", &"first": &"map", &"story": &"chapters",
}
const RED_TYPES: Array[StringName] = [&"patrol", &"boss", &"bounty", &"vehicle", &"rescue", &"first"]
const CYAN_TYPES: Array[StringName] = [&"arena", &"defend", &"hack", &"heist", &"demolition"]


static func board() -> MissionBoard:
	var m := Game.missions as Missions
	return m.board if m != null else null


## Cards of one screen: the key the Hud adds to its layout key (a new offer set, a running mission, the difficulty, the last result).
static func key() -> String:
	var b := board()
	if b == null:
		return "-"
	var ids := ""
	for o: Dictionary in b.offers:
		ids += "%d," % int(o["id"])
	return "%s|%s|%d|%s|%s" % [b.state, ids, Difficulty.current, str(b.last_result.get("title", "")), str(b.active.get("title", ""))]


static func tint_of(t: StringName) -> Color:
	if t == &"story":
		return UiUtil.MAGENTA
	if RED_TYPES.has(t):
		return UiUtil.RED
	if CYAN_TYPES.has(t):
		return UiUtil.CYAN
	return UiUtil.AMBER


## "CLEAR THE LOOKOUT" -> the card sub line: brief plus distance.
static func sub_of(b: MissionBoard, o: Dictionary) -> String:
	var d := b.distance_to(o)
	return "%s   %s" % [str(o["brief"]), ("%d M AWAY" % roundi(d)) if d > 0.0 else ""]


static func layout(hud: Hud, cx: float, s: float) -> void:
	var b := board()
	var x := cx - CARD_W * 0.5 * s
	var y := TOP
	if b == null:
		hud._add(&"board_back", Rect2(cx - 150.0 * s, 300.0 * s, 300.0 * s, BAR_H * s), "BACK", false)
		return
	if b.is_running() or b.state == &"story":
		var running := b.state == &"running"
		hud._add_card(&"board_active", Rect2(x, y * s, CARD_W * s, CARD_H * s), str(b.active.get("title", "MISSION")), ICON_OF.get(b.active.get("type", &""), &"missions"),
				_step_line(b), true, tint_of(StringName(b.active.get("type", &""))))
		y += CARD_H + GAP
		if running:
			hud._add_card(&"board_retry", Rect2(x, y * s, (CARD_W * 0.5 - GAP * 0.5) * s, BAR_H * s), "RETRY STEP", &"plus", "", false, UiUtil.CYAN)
			hud._add_card(&"board_abandon", Rect2(x + (CARD_W * 0.5 + GAP * 0.5) * s, y * s, (CARD_W * 0.5 - GAP * 0.5) * s, BAR_H * s), "ABANDON", &"abort", "", false, UiUtil.RED)
			y += BAR_H + GAP
		_bottom(hud, cx, s, y + 8.0, false)
		return
	var story := b.story_offer()
	if not story.is_empty():
		hud._add_card(&"board_story", Rect2(x, y * s, CARD_W * s, CARD_H * s), "STORY  " + str(story["title"]), &"chapters", "The next chapter. Longer, with a boss.", false, UiUtil.MAGENTA)
		y += CARD_H + GAP
	for i in b.offers.size():
		var o: Dictionary = b.offers[i]
		var t := StringName(o["type"])
		hud._add_card(StringName("board_pick_%d" % i), Rect2(x, y * s, CARD_W * s, CARD_H * s), "%s    %d CR" % [str(o["title"]), int(o["reward"])], ICON_OF.get(t, &"missions"), sub_of(b, o), i == 0 and story.is_empty(), tint_of(t))
		y += CARD_H + GAP
	_bottom(hud, cx, s, y + 8.0, true)


static func _step_line(b: MissionBoard) -> String:
	var k := b._campaign()
	var line := str(k.hud_line()) if k != null else ""
	return line if line != "" else str(b.active.get("brief", ""))


## The bottom row: EASY NORMAL HARD, NEW OFFERS, BACK (FREE ROAM). Three difficulty buttons of 120 px, the rest share the width.
static func _bottom(hud: Hud, cx: float, s: float, y: float, with_new: bool) -> void:
	var x := cx - CARD_W * 0.5 * s
	var bw := 112.0
	for i in 3:
		hud._add(StringName("board_diff_%d" % i), Rect2(x + (float(i) * (bw + 8.0)) * s, y * s, bw * s, BAR_H * s), ["EASY", "NORMAL", "HARD"][i], Difficulty.current == i)
	var rest_x := x + (3.0 * (bw + 8.0)) * s
	var rest_w := CARD_W * s - 3.0 * (bw + 8.0) * s
	if with_new:
		hud._add(&"board_new", Rect2(rest_x, y * s, (rest_w * 0.5 - 4.0 * s), BAR_H * s), "NEW OFFERS", false)
		hud._add(&"board_back", Rect2(rest_x + rest_w * 0.5 + 4.0 * s, y * s, rest_w * 0.5 - 4.0 * s, BAR_H * s), "FREE ROAM", false)
	else:
		hud._add(&"board_back", Rect2(rest_x, y * s, rest_w, BAR_H * s), "BACK TO THE GAME", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, _cx: float) -> void:
	var b := board()
	hud.header(c, vp, s, font, "MISSIONS")
	if b == null:
		return
	var prog := Game.progress as Progress
	var line := ""
	var col := Color(UiUtil.AMBER, 0.97)
	if not b.last_result.is_empty():
		var lr := b.last_result
		if bool(lr["ok"]):
			line = "%s COMPLETE   +%d CREDITS" % [str(lr["title"]), int(lr["reward"])]
			col = Color(UiUtil.GREEN, 0.98)
		else:
			line = ("%s ABANDONED" % str(lr["title"])) if str(lr["reason"]) == "ABANDONED" else ("%s DROPPED   %s" % [str(lr["title"]), str(lr["reason"])])
			col = Color(UiUtil.RED, 0.98)
	elif b.state == &"running":
		line = "MISSION IN PROGRESS"
	else:
		line = "PICK ONE   THE NEXT ARE ALWAYS HERE"
	if prog != null:
		line += "      CREDITS  %d" % prog.credits
	hud._text(c, font, Vector2(0.0, (HEAD_LINE_Y) * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * s), col, 1.0 * s)


const HEAD_LINE_Y := 112.0
