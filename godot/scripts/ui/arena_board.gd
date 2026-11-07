class_name ArenaBoard
extends RefCounted
## The BOSS RUSH / ARENA planning screen (Hud draws it when `_arena_open`: the pause menu ARENA button in the city, the title ARENA button): mode RUSH or ENDLESS (`arena_mode_<m>`), the rush
## difficulty (`arena_d_<id>`), the endless modifiers (`arena_m_<id>`, toggles), LAUNCH (`arena_go`), BACK (`arena_back`) and, while a run lasts, LEAVE (`arena_leave`). Buttons are 64 px tall.
## The leaderboard (five best rush times of the picked difficulty, best endless wave) is Progress.arena. Pure layout and drawing: the rules live in ArenaScripts / ArenaRunner.

const COL_W := 260.0
const GAP := 20.0
const BTN_H := 64.0
const ROW_MODE := 112.0
const ROW_OPT := 196.0
const ROW_INFO := 280.0
const ROW_GO := 540.0

static var mode: StringName = &"rush"
static var diff: StringName = &"normal"
static var mods: Array[StringName] = []


static func runner() -> ArenaRunner:
	return (Game.missions as Missions).arena if Game.missions is Missions else null


static func _col(cx: float, s: float, i: int) -> float:
	return cx + (-COL_W * 1.5 - GAP + i * (COL_W + GAP)) * s


static func toggle_mod(id: StringName) -> void:
	if mods.has(id):
		mods.erase(id)
	elif ArenaScripts.MOD_DEFS.has(id):
		mods.append(id)


## Why LAUNCH is off ("" when it can start). From the title the hero is not in the world yet: only the title state is accepted there.
static func can_launch() -> bool:
	var r := runner()
	return r != null and r.can_start()


static func layout(hud: Hud, cx: float, s: float) -> void:
	var r := runner()
	var running := r != null and r.is_running()
	for i in 2:
		var m: StringName = [&"rush", &"endless"][i]
		hud._add(StringName("arena_mode_%s" % m), Rect2(_col(cx, s, i), ROW_MODE * s, COL_W * s, BTN_H * s), "BOSS RUSH" if m == &"rush" else "ENDLESS ARENA", m == mode)
	if mode == &"rush":
		for i in ArenaScripts.DIFFS.size():
			var d: StringName = ArenaScripts.DIFFS[i]
			hud._add(StringName("arena_d_%s" % d), Rect2(_col(cx, s, i), ROW_OPT * s, COL_W * s, BTN_H * s), ArenaScripts.diff_title(d), d == diff)
	else:
		for i in ArenaScripts.MODS.size():
			var md: StringName = ArenaScripts.MODS[i]
			hud._add(StringName("arena_m_%s" % md), Rect2(_col(cx, s, i), ROW_OPT * s, COL_W * s, BTN_H * s), ArenaScripts.mod_title(md), mods.has(md))
	if running:
		hud._add(&"arena_leave", Rect2(_col(cx, s, 0), ROW_GO * s, COL_W * s, BTN_H * s), "LEAVE RUN", false)
	hud._add(&"arena_go", Rect2(_col(cx, s, 1), ROW_GO * s, COL_W * s, BTN_H * s), "LAUNCH", Game.state == &"menu" or can_launch())
	hud._add(&"arena_back", Rect2(_col(cx, s, 2), ROW_GO * s, COL_W * s, BTN_H * s), "BACK", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	var prog := Game.progress as Progress
	hud.header(c, vp, s, font, "BOSS RUSH  AND  ARENA")
	var x := _col(cx, s, 0)
	var w := (COL_W * 3.0 + GAP * 2.0) * s
	hud._rect(c, Rect2(x, ROW_INFO * s, w, 230.0 * s), MenuKit.FILL)
	var lines: Array[String] = []
	var tint := UiUtil.CYAN
	if mode == &"rush":
		lines.append("All %d bosses in a row, short breaks, one clock. A fall ends the run." % ArenaScripts.RUSH_ORDER.size())
		lines.append(String(ArenaScripts.DIFF_DEFS[diff]["note"]))
		lines.append("REWARD  %d CREDITS  +  %s" % [ArenaScripts.rush_reward(diff), _item_name(String(ArenaScripts.RUSH_COSMETIC[diff]))])
		var times: Array = prog.arena.get("rush_%s" % diff, []) if prog != null else []
		lines.append("BEST TIMES  " + ("   ".join(PackedStringArray(times.map(func(t: float) -> String: return ArenaScripts.clock_text(t)))) if not times.is_empty() else "NONE YET"))
		lines.append("CLEARS  %d" % (int(prog.arena.get("clear_%s" % diff, 0)) if prog != null else 0))
	else:
		lines.append("Waves of troops until you fall. Leave to bank the waves cleared.")
		var names: Array[String] = []
		for m: StringName in mods:
			names.append("%s (%s)" % [ArenaScripts.mod_title(m), String(ArenaScripts.MOD_DEFS[m]["note"])])
		lines.append("MODIFIERS  " + (", ".join(PackedStringArray(names)) if not names.is_empty() else "NONE"))
		lines.append("REWARD  %d CREDITS PER WAVE x %.1f  +  WAVE 4 / 8 COSMETICS" % [ArenaScripts.ENDLESS_WAVE_PAY, ArenaScripts.mod_mult(mods, "score")])
		lines.append("BEST WAVE  %d     BEST SCORE  %d" % [int(prog.arena.get("wave_best", 0)) if prog != null else 0, int(prog.arena.get("score_best", 0)) if prog != null else 0])
	var y := ROW_INFO + 30.0
	for ln: String in lines:
		hud._text(c, font, Vector2(x + 10.0 * s, y * s), ln, HORIZONTAL_ALIGNMENT_LEFT, w - 20.0 * s, int(UiUtil.BAR_LABEL * s), Color(tint, 0.95), 1.0 * s)
		y += 36.0
	var r := runner()
	if r != null and r.is_running():
		hud._text(c, font, Vector2(0.0, (ROW_GO - 12.0) * s), "RUN IN PROGRESS  " + r.hud_line(), HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(18.0 * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)


static func _item_name(key: String) -> String:
	if key.begins_with("suit:"):
		return "%s SUIT" % String(HeroLook.SUITS[StringName(key.substr(5))]["name"])
	var i := int(key.substr(7))
	return "%s SCHEME" % String(HeroLook.SCHEMES[i][0])
