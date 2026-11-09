class_name MissionBoardScreen
extends RefCounted
## The Mission Board screen (Hud draws it while `_board_open`, a pause-state panel like the map): the highlighted STORY card, THREE mission cards (title, pay, distance, one line) and a bottom
## row with the EASY / NORMAL / HARD switch, NEW OFFERS and FREE ROAM. While a board mission runs the three cards give way to the running mission, RETRY STEP and ABANDON.
## Buttons: `board_story`, `board_pick_0..2`, `board_diff_0..2`, `board_new`, `board_back`, `board_retry`, `board_abandon`, all 64 px or taller; the cards are MenuKit cards (the Hud draws
## them); this file lays them out and paints the header and the result line. Rules live in MissionBoard.

const CARD_W := 760.0               ## the narrowest board (a 4:3 tablet); wider screens get up to CARD_W_MAX (director review 5, defect 8: a column that filled 47 % of the phone)
const CARD_W_MAX := 1120.0
const CARD_H := 92.0
const GAP := 12.0
const CHIP_W := 190.0                ## base px of the pay chip at the right end of a card
const TOP := 128.0
const BAR_H := 64.0

const ICON_OF := {
	&"patrol": &"arena", &"boss": &"arena", &"bounty": &"arena", &"arena": &"arena", &"defend": &"arena", &"vehicle": &"arena", &"demolition": &"arena",
	&"heist": &"heists", &"hack": &"heists", &"stealth": &"hero", &"rescue": &"hero", &"escort": &"hero",
	&"courier": &"map", &"hijack": &"map", &"chase": &"map", &"convoy": &"map", &"first": &"map", &"story": &"chapters",
	&"airport_heist": &"heists", &"heli_extract": &"hero", &"mountain_pursuit": &"map", &"river_chase": &"map", &"air_race": &"map", &"plane_delivery": &"map",     # the big world (WorldMissions)
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


## The card width in base px for this screen: as wide as the phone allows (notch insets and a 40 px margin kept), never below CARD_W.
static func card_w(hud: Hud, s: float) -> float:
	var vp := hud._screen.size if hud != null and hud._screen != null else Vector2(1600.0 * s, 720.0 * s)
	var ins := UiUtil.insets(vp)
	return clampf((vp.x - 2.0 * (maxf(ins.x, ins.y) + 40.0 * s)) / s, CARD_W, CARD_W_MAX)


static func layout(hud: Hud, cx: float, s: float) -> void:
	var b := board()
	var cw := card_w(hud, s)
	var x := cx - cw * 0.5 * s
	var y := TOP
	if b == null:
		hud._add(&"board_back", Rect2(cx - 150.0 * s, 300.0 * s, 300.0 * s, BAR_H * s), "BACK", false)
		return
	if b.is_running() or b.state == &"story":
		var running := b.state == &"running"
		hud._add_card(&"board_active", Rect2(x, y * s, cw * s, CARD_H * s), str(b.active.get("title", "MISSION")), ICON_OF.get(b.active.get("type", &""), &"missions"),
				_step_line(b), true, tint_of(StringName(b.active.get("type", &""))))
		y += CARD_H + GAP
		if running:
			hud._add_card(&"board_retry", Rect2(x, y * s, (cw * 0.5 - GAP * 0.5) * s, BAR_H * s), "RETRY STEP", &"plus", "", false, UiUtil.CYAN)
			hud._add_card(&"board_abandon", Rect2(x + (cw * 0.5 + GAP * 0.5) * s, y * s, (cw * 0.5 - GAP * 0.5) * s, BAR_H * s), "ABANDON", &"abort", "", false, UiUtil.RED)
			y += BAR_H + GAP
		_bottom(hud, cx, s, y + 8.0, false, cw)
		return
	var story := b.story_offer()
	if not story.is_empty():
		hud._add_card(&"board_story", Rect2(x, y * s, cw * s, CARD_H * s), "STORY  " + str(story["title"]), &"chapters", "The next chapter. Longer, with a boss.", false, UiUtil.MAGENTA)
		y += CARD_H + GAP
	for i in b.offers.size():
		var o: Dictionary = b.offers[i]
		var t := StringName(o["type"])
		hud._add_card(StringName("board_pick_%d" % i), Rect2(x, y * s, cw * s, CARD_H * s), str(o["title"]), ICON_OF.get(t, &"missions"), sub_of(b, o), i == 0 and story.is_empty(), tint_of(t))
		hud.buttons[hud.buttons.size() - 1]["rpad"] = (CHIP_W + 26.0) * s                      # the text keeps clear of the pay chip
		y += CARD_H + GAP
	_bottom(hud, cx, s, y + 8.0, true, cw)


static func _step_line(b: MissionBoard) -> String:
	var k := b._campaign()
	var line := str(k.hud_line()) if k != null else ""
	return line if line != "" else str(b.active.get("brief", ""))


## The bottom row: EASY NORMAL HARD, NEW OFFERS, BACK (FREE ROAM). Three difficulty buttons of 120 px, the rest share the width.
static func _bottom(hud: Hud, cx: float, s: float, y: float, with_new: bool, cw: float) -> void:
	var x := cx - cw * 0.5 * s
	var bw := 150.0
	for i in 3:
		hud._add(StringName("board_diff_%d" % i), Rect2(x + (float(i) * (bw + 8.0)) * s, y * s, bw * s, BAR_H * s), ["EASY", "NORMAL", "HARD"][i], Difficulty.current == i)
	var rest_x := x + (3.0 * (bw + 8.0)) * s
	var rest_w := cw * s - 3.0 * (bw + 8.0) * s
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
	hud._text(c, font, Vector2(0.0, (HEAD_LINE_Y) * s), line, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.BAR_LABEL * 1.15 * s), col, 1.0 * s)
	_draw_pay(hud, c, s, font, b)


## The pay chip at the right end of every offer card: a big amber number and the word CR, the answer to "what do I get" at a thumb's glance.
static func _draw_pay(hud: Hud, c: Control, s: float, font: Font, b: MissionBoard) -> void:
	for btn: Dictionary in hud.buttons:
		var id := String(btn["id"])
		if not id.begins_with("board_pick_"):
			continue
		var i := int(id.substr(11))
		if i < 0 or i >= b.offers.size():
			continue
		var r: Rect2 = btn["rect"]
		var chip := Rect2(r.end.x - (CHIP_W + 14.0) * s, r.position.y + 10.0 * s, CHIP_W * s, r.size.y - 20.0 * s)
		hud._rect(c, chip, Color(0.16, 0.11, 0.02, 0.96))                                              # queued, so it lands over the card's own plate
		hud._frame(c, chip, Color(UiUtil.AMBER, 0.9), 2.0 * s)
		var coin := Rect2(chip.position.x + 10.0 * s, chip.position.y + chip.size.y * 0.42 - 14.0 * s, 28.0 * s, 28.0 * s)
		hud._sprite(c, &"disc", coin, Color(UiUtil.AMBER, 0.95))
		hud._sprite(c, &"ring", coin.grow(-6.0 * s), Color(0.16, 0.11, 0.02, 1.0))
		var txt := "%d" % int(b.offers[i]["reward"])
		var sz := UiUtil.fit_size(font, txt, chip.size.x - 60.0 * s, int(34.0 * s))
		hud._text(c, font, Vector2(chip.position.x + 40.0 * s, chip.position.y + chip.size.y * 0.5 + 2.0 * s), txt, HORIZONTAL_ALIGNMENT_LEFT, chip.size.x - 50.0 * s, sz, Color(1.0, 0.92, 0.55, 1.0), 1.5 * s)
		hud._text(c, font, Vector2(chip.position.x, chip.end.y - 10.0 * s), "CREDITS", HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, int(Hud.BODY_MIN * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)


const HEAD_LINE_Y := 112.0
