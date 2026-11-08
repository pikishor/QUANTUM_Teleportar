class_name OptionsScreen
extends RefCounted
## The options screen (Hud draws it when `_options_open`, opened by the OPTIONS button of the title and pause screens): every row is >= 64 px tall for touch. Sliders (look X / Y, ADS,
## HUD scale, button size) are `opt_*` buttons whose rect is the track; toggles and cycles (aim assist, auto fire, left-handed layout, vibration, subtitles, colour-blind safe
## markers, FPS cap, graphics tier) are plain presses. Pure layout and settings math, no state of its own: every value lives in UiSettings.

const ROW_H := 64.0
const PITCH := 68.0                ## 7 rows of 64 px under the column captions, then the BACK row
const TOP := 126.0
const COL_W := 330.0
const GAP := 14.0
const BACK_Y := 620.0
const ROWS := 7

## slider id -> [label, min, max, UiSettings field]
const SLIDERS := {
	&"opt_look_x": ["LOOK X", UiSettings.SENS_MIN, UiSettings.SENS_MAX, &"look_x"],
	&"opt_look_y": ["LOOK Y", UiSettings.SENS_MIN, UiSettings.SENS_MAX, &"look_y"],
	&"opt_ads": ["ADS", UiSettings.SENS_MIN, UiSettings.SENS_MAX, &"ads_sens"],
	&"opt_hud": ["HUD SIZE", UiSettings.HUD_MIN, UiSettings.HUD_MAX, &"hud_scale"],
	&"opt_btn": ["BUTTONS", UiSettings.BTN_MIN, UiSettings.BTN_MAX, &"button_size"],
	&"opt_vol_music": ["MUSIC", 0.0, 1.0, &"vol:Music"],            # the two volumes are real sliders now (a field "vol:<bus>" reads and writes UiSettings.volumes)
	&"opt_vol_sfx": ["SFX", 0.0, 1.0, &"vol:SFX"],
}
const TOGGLES := {
	&"opt_aim": &"aim_assist", &"opt_auto": &"auto_fire", &"opt_left": &"left_hand",
	&"opt_vib": &"vibration", &"opt_subs": &"subtitles", &"opt_cb": &"cb_safe",
	&"opt_flash": &"reduce_flash", &"opt_motion": &"reduce_motion", &"opt_post": &"post", &"opt_cine": &"cutscenes", &"opt_civ": &"civilians", &"opt_dmg": &"dmg_numbers",
}
const TOGGLE_NAMES := {
	&"opt_aim": "AIM ASSIST", &"opt_auto": "AUTO FIRE", &"opt_left": "LEFT HAND",
	&"opt_vib": "VIBRATION", &"opt_subs": "SUBTITLES", &"opt_cb": "COLOUR SAFE",
	&"opt_flash": "REDUCE FLASH", &"opt_motion": "REDUCE MOTION", &"opt_post": "POST FX", &"opt_cine": "CUTSCENES", &"opt_civ": "CIVILIANS", &"opt_dmg": "DAMAGE NUMBERS",
}
## Page 1 (accessibility) ids; opt_page flips between the pages and sits in the last cell of both.
const PAGE2: Array[StringName] = [&"opt_lang", &"opt_text", &"opt_flash", &"opt_motion", &"opt_subsize", &"opt_subbg", &"opt_hints", &"opt_diff", &"opt_res", &"opt_haptic", &"opt_controls", &"opt_reset", &"opt_reset_demo", &"opt_chatter", &"opt_fpsbox", &"opt_civ"]
const PAGE_CELL := 20                ## three columns of seven rows: the MORE cell is the last (bottom right)
## The two pages as columns (caption, ids top to bottom): a column is one topic, so a player finds a row by its heading instead of scanning 19 buttons.
const COLS0 := [
	["CONTROLS", [&"opt_look_x", &"opt_look_y", &"opt_ads", &"opt_aim", &"opt_auto", &"opt_left", &"opt_vib"]],
	["DISPLAY", [&"opt_hud", &"opt_btn", &"opt_tier", &"opt_fps", &"opt_post", &"opt_subs", &"opt_cb"]],
	["SOUND AND MORE", [&"opt_vol_music", &"opt_vol_sfx", &"opt_mute", &"opt_cine", &"opt_bench", &"opt_dmg"]],
]
const COLS1 := [
	["LANGUAGE AND TEXT", [&"opt_lang", &"opt_text", &"opt_subsize", &"opt_subbg", &"opt_hints", &"opt_haptic", &"opt_controls"]],
	["PLAY", [&"opt_flash", &"opt_motion", &"opt_diff", &"opt_res", &"opt_chatter", &"opt_fpsbox", &"opt_civ"]],
	["SAVE DATA", [&"opt_reset", &"opt_reset_demo"]],
]
## RESET PROGRESS needs two presses: the first arms it (the label asks), the second wipes. Any other press, the page flip and BACK disarm it; only on the title screen.
static var reset_armed := false
## The demo slot has its own confirm (`opt_reset_demo`): press, then press again.
static var reset_demo_armed := false
const SUB_BG_NAMES: Array[String] = ["SOFT", "", "SOLID"]
const CB_NAMES: Array[String] = ["DEUTAN", "TRITAN"]
const ORDER: Array[StringName] = [
	&"opt_look_x", &"opt_look_y", &"opt_ads", &"opt_aim", &"opt_auto", &"opt_left", &"opt_vib",
	&"opt_hud", &"opt_btn", &"opt_tier", &"opt_fps", &"opt_post", &"opt_subs", &"opt_cb",
	&"opt_vol_music", &"opt_vol_sfx", &"opt_mute", &"opt_cine", &"opt_bench",
]
const VOLUME_STEPS: Array[float] = [1.0, 0.75, 0.5, 0.25, 0.0]
const VOLUME_BUSES := {&"opt_vol_music": ["Music"], &"opt_vol_sfx": ["SFX", "Ambient", "Voice"]}


static func is_slider(id: StringName) -> bool:
	return SLIDERS.has(id)


## The extra controls of the page bands: the four graphics chips, the sound test and the page reset.
static func is_extra(id: StringName) -> bool:
	return String(id).begins_with("opt_tierset_") or id == &"opt_sndtest" or id == &"opt_reset_tab"


static func is_option(id: StringName) -> bool:
	return is_extra(id) or SLIDERS.has(id) or TOGGLES.has(id) or id == &"opt_fps" or id == &"opt_bench" or VOLUME_BUSES.has(id) or id == &"opt_mute" or id == &"opt_tier" or id == &"opt_res" or id == &"opt_page" or is_tab(id) or PAGE2.has(id)


static func slider_value(st: UiSettings, id: StringName) -> float:
	var d: Array = SLIDERS[id]
	if String(d[3]).begins_with("vol:"):
		return volume(st, id)
	return float(st.get(d[3]))


static func fraction(st: UiSettings, id: StringName) -> float:
	var d: Array = SLIDERS[id]
	return clampf((slider_value(st, id) - float(d[1])) / (float(d[2]) - float(d[1])), 0.0, 1.0)


## Sets a slider from a 0..1 fraction (snapped to 0.05 of the value); returns the value.
static func set_fraction(st: UiSettings, id: StringName, f: float) -> float:
	var d: Array = SLIDERS[id]
	var v := snappedf(lerpf(float(d[1]), float(d[2]), clampf(f, 0.0, 1.0)), 0.05)
	v = clampf(v, float(d[1]), float(d[2]))
	if String(d[3]).begins_with("vol:"):
		for b: String in VOLUME_BUSES[id]:
			st.volumes[b] = v
		Sfx.apply_volumes(st.volumes)                          # heard at once, saved on release
		return v
	st.set(d[3], v)
	return v


static func label(st: UiSettings, id: StringName) -> String:
	if SLIDERS.has(id):
		return "%s  %d%%" % [Tr.t(SLIDERS[id][0]), roundi(slider_value(st, id) * 100.0)]
	if TOGGLES.has(id):
		var on := bool(st.get(TOGGLES[id]))
		if id == &"opt_cb" and on:
			return "%s %s" % [Tr.t(TOGGLE_NAMES[id]), Tr.t(CB_NAMES[st.cb_variant])]
		return "%s %s" % [Tr.t(TOGGLE_NAMES[id]), Tr.t("ON" if on else "OFF")]
	if VOLUME_BUSES.has(id):
		return Tr.t("MUSIC" if id == &"opt_vol_music" else "SFX") + "  %d%%" % roundi(volume(st, id) * 100.0)
	if id == &"opt_mute":
		return Tr.t("SOUND") + " " + Tr.t("OFF" if st.muted else "ON")
	if id == &"opt_fps":
		return Tr.t("FPS CAP") + "  " + (Tr.t("OFF") if st.fps_cap == 0 else str(st.fps_cap))
	if id == &"opt_bench":
		return Tr.t("RUN BENCHMARK")
	if id == &"opt_tier":
		return Tr.t("GRAPHICS") + "  " + Tr.t(Game.tier_label())
	if id == &"opt_res":
		return Tr.t("RESOLUTION") + "  " + Tr.t(RenderRes.mode_name(RenderRes.mode()))
	if id == &"opt_page":
		return Tr.t("MORE") + "  " + str(UiSettings.s_opt_page + 1) + "/2"
	if id == &"opt_lang":
		return Tr.t("LANGUAGE") + "  " + str(Tr.LANG_NAMES.get(st.language, st.language))
	if id == &"opt_text":
		return Tr.t("TEXT SIZE") + "  %d%%" % roundi(st.text_scale * 100.0)
	if id == &"opt_subsize":
		return Tr.t("SUBTITLE SIZE") + "  %d%%" % roundi(st.sub_size * 100.0)
	if id == &"opt_hints":
		return Tr.t("REPLAY HINTS")
	if id == &"opt_diff":
		return Tr.t("DIFFICULTY") + "  " + Tr.t(Difficulty.mode_name(st.difficulty))
	if id == &"opt_haptic":
		return Tr.t("HAPTICS") + "  " + Tr.t(UiSettings.HAPTIC_NAMES[clampi(st.haptic_level, 0, 2)])
	if id == &"opt_controls":
		return Tr.t("CONTROLS")
	if id == &"opt_reset":
		return Tr.t("TAP AGAIN: ERASE ALL" if reset_armed else "RESET PROGRESS")
	if id == &"opt_reset_demo":
		return Tr.t("TAP AGAIN: ERASE DEMO" if reset_demo_armed else "RESET DEMO SLOT")
	if id == &"opt_chatter":
		return Tr.t("STORY CHATTER") + "  " + Tr.t(UiSettings.CHATTER_NAMES[clampi(st.chatter, 0, 2)])
	if id == &"opt_fpsbox":
		return Tr.t("FPS DISPLAY") + "  " + Tr.t("ON" if _fps_on() else "OFF")
	if id == &"opt_subbg":
		return Tr.t("SUBTITLE BG") + "  " + Tr.t(SUB_BG_NAMES[st.sub_bg] if st.sub_bg != 1 else "ON")
	return ""


static func _touch() -> TouchControls:
	var hud := Game.get_tree().get_first_node_in_group(&"hud") if Game.is_inside_tree() else null
	return (hud as Hud).touch if hud is Hud else null


static func _fps_on() -> bool:
	var tc := _touch()
	return tc != null and tc.perf_shown


static func volume(st: UiSettings, id: StringName) -> float:
	return clampf(float(st.volumes.get(VOLUME_BUSES[id][0], 1.0)), 0.0, 1.0)


static func is_on(st: UiSettings, id: StringName) -> bool:
	if id == &"opt_mute":
		return not st.muted
	return TOGGLES.has(id) and bool(st.get(TOGGLES[id]))


## Flips a toggle or cycles FPS cap / graphics tier. Returns true when it changed something.
static func press(st: UiSettings, id: StringName) -> bool:
	if is_tab(id):
		reset_armed = false
		reset_demo_armed = false
		UiSettings.s_opt_tab = clampi(String(id).substr(8).to_int(), 0, TABS.size() - 1)
		return true
	if id == &"opt_reset":
		reset_demo_armed = false
		var pr: Variant = Game.progress
		if Game.state != &"menu" or not is_instance_valid(pr):
			reset_armed = false
			return false
		if not reset_armed:
			reset_armed = true
			return true
		reset_armed = false
		(pr as Progress).reset_progress()
		Game.message.emit("PROGRESS RESET", 2.0)
		return true
	if id == &"opt_reset_demo":
		reset_armed = false
		if Game.state != &"menu" or DemoMode.active:
			reset_demo_armed = false
			return false
		if not reset_demo_armed:
			reset_demo_armed = true
			return true
		reset_demo_armed = false
		Progress.reset_demo_slot()
		Game.message.emit("DEMO SLOT RESET", 2.0)
		return true
	reset_armed = false
	reset_demo_armed = false
	if String(id).begins_with("opt_tierset_"):                  # a graphics chip: that tier, now
		var chip := clampi(String(id).substr(12).to_int(), 0, 3)
		st.quality = maxi(chip - 1, 0)
		st.low_plus = chip == 0
		Game.set_tier_index(chip)
		return true
	if id == &"opt_sndtest":
		Sfx.play(&"shot")
		return true
	if id == &"opt_reset_tab":
		reset_tab(st, UiSettings.s_opt_tab)
		Game.message.emit("PAGE RESET", 1.5)
		return true
	if id == &"opt_bench":                               # 30 s fixed route through the city on LOW, MED and HIGH (scripts/common/benchmark_run.gd); the HUD closes the screen when play starts
		var bn := Game.get_tree().get_first_node_in_group(&"benchmark") if Game.is_inside_tree() else null
		return bn != null and bool((bn as BenchmarkRun).start())
	if id == &"opt_cb":                                  # off -> deutan/protan -> tritan -> off
		if not st.cb_safe:
			st.cb_safe = true
			st.cb_variant = 0
		elif st.cb_variant == 0:
			st.cb_variant = 1
		else:
			st.cb_safe = false
			st.cb_variant = 0
		return true
	if id == &"opt_mute":
		st.muted = not st.muted
		return true
	if VOLUME_BUSES.has(id):                             # 100 -> 75 -> 50 -> 25 -> 0 -> 100 %
		var cur := volume(st, id)
		var nxt := VOLUME_STEPS[0]
		for i in VOLUME_STEPS.size() - 1:
			if cur <= VOLUME_STEPS[i] + 0.01 and cur > VOLUME_STEPS[i + 1] + 0.01:
				nxt = VOLUME_STEPS[i + 1]
		if cur <= VOLUME_STEPS[VOLUME_STEPS.size() - 1] + 0.01:
			nxt = 1.0
		for b: String in VOLUME_BUSES[id]:
			st.volumes[b] = nxt
		return true
	if TOGGLES.has(id):
		st.set(TOGGLES[id], not bool(st.get(TOGGLES[id])))
		return true
	if id == &"opt_page":
		UiSettings.s_opt_page = 1 - UiSettings.s_opt_page
		return true
	if id == &"opt_lang":
		st.language = Tr.next_lang(st.language)
		return true
	if id == &"opt_text":
		st.text_scale = Tr.next_scale(st.text_scale)
		return true
	if id == &"opt_subsize":
		st.sub_size = Tr.next_scale(st.sub_size)
		return true
	if id == &"opt_hints":
		var st_node: Variant = Game.story.get(&"first_use") if is_instance_valid(Game.story) else null
		if st_node != null:
			(st_node as Object).call(&"replay")
		return true
	if id == &"opt_diff":
		st.difficulty = Difficulty.next_mode(st.difficulty)
		Difficulty.set_mode(st.difficulty)
		return true
	if id == &"opt_haptic":
		st.haptic_level = (st.haptic_level + 1) % 3
		UiSettings.s_haptic = st.haptic_level
		UiSettings.buzz(60)                                  # a preview at the new strength
		return true
	if id == &"opt_controls":                                # page 2: the remap screen (scripts/ui/controls_screen.gd)
		UiSettings.s_opt_page = 2
		ControlsScreen.reset_state()
		return true
	if id == &"opt_subbg":
		st.sub_bg = (st.sub_bg + 1) % 3
		return true
	if id == &"opt_chatter":
		st.chatter = (st.chatter + 1) % 3
		UiSettings.s_chatter = st.chatter
		return true
	if id == &"opt_fpsbox":                              # the debug FPS box: hidden by default, also toggled by a long press under the minimap
		var tc := _touch()
		if tc != null:
			tc.show_perf(not tc.perf_shown)
		return true
	if id == &"opt_fps":
		st.fps_cap = st.next_fps_cap()
		return true
	if id == &"opt_res":
		st.res_mode = RenderRes.next_mode()
		RenderRes.set_user(st.res_mode)
		return true
	if id == &"opt_tier":
		var ti := (Game.tier_index() + 1) % 4                  # LOW+ -> LOW -> MED -> HIGH -> LOW+
		st.quality = maxi(ti - 1, 0)
		st.low_plus = ti == 0
		Game.set_tier_index(ti)
		return true
	return false


static func cell_rect(i: int, cx: float, s: float) -> Rect2:
	var col := i % 3
	var row := i / 3
	return Rect2(cx - (COL_W * 1.5 + GAP) * s + col * (COL_W + GAP) * s, (TOP + row * PITCH) * s, COL_W * s, ROW_H * s)


## The cell of column `col`, row `row` (the same grid as cell_rect).
static func col_rect(col: int, row: int, cx: float, s: float) -> Rect2:
	return cell_rect(row * 3 + col, cx, s)


## The settings are five TABS of at most eight rows, one topic each: a player finds a row by its tab instead of scanning 19 buttons. GRAPHICS, SOUND and ACCESS carry a PREVIEW BAND
## above their rows (a sample of the chosen graphics tier with four chips, a sound test, a sample of the subtitle text); every tab has RESET PAGE beside BACK.
const TABS := [
	[&"CONTROLS", &"controls", [&"opt_look_x", &"opt_look_y", &"opt_ads", &"opt_aim", &"opt_auto", &"opt_left", &"opt_vib", &"opt_controls"]],
	[&"GRAPHICS", &"display", [&"opt_tier", &"opt_res", &"opt_fps", &"opt_post", &"opt_hud", &"opt_btn", &"opt_fpsbox"]],
	[&"SOUND", &"sound", [&"opt_vol_music", &"opt_vol_sfx", &"opt_mute", &"opt_haptic", &"opt_cine"]],
	[&"ACCESS", &"gameplay", [&"opt_lang", &"opt_text", &"opt_subs", &"opt_subsize", &"opt_subbg", &"opt_cb", &"opt_flash", &"opt_motion"]],
	[&"GAME", &"data", [&"opt_diff", &"opt_hints", &"opt_chatter", &"opt_civ", &"opt_dmg", &"opt_bench", &"opt_reset", &"opt_reset_demo"]],
]
const TAB_Y := 100.0
const TAB_H := 64.0
const ROW_TOP := 190.0              ## rows of a tab without a band: four per column
const ROW_BOX := 84.0
const ROW_PITCH := 104.0
const BAND_TOP := 176.0
const BAND_H := 136.0
const BAND_ROW_TOP := 326.0         ## rows under a band
const BAND_ROW_BOX := 64.0
const BAND_ROW_PITCH := 72.0
const OPT_BACK_Y := 626.0
const BAND_TABS := [1, 3]
## Per graphics tier (LOW+, LOW, MED, HIGH): what it costs and what it shows (three [name, value] lines and a battery note).
const TIER_FACTS := [
	[["SHADOWS", "OFF"], ["SURFACES", "FLAT"], ["CROWD", "LIGHT"], "BEST BATTERY"],
	[["SHADOWS", "OFF"], ["SURFACES", "LIGHT SCANS"], ["CROWD", "LIGHT"], "LONG BATTERY"],
	[["SHADOWS", "NEAR"], ["SURFACES", "SCANNED"], ["CROWD", "FULL"], "BALANCED"],
	[["SHADOWS", "FAR"], ["SURFACES", "SHARP SCANS"], ["CROWD", "FULL"], "HEAVY"],
]
const TIER_SHOT := "res://assets/ui/tier_%d.jpg"
static var _tier_tex: Dictionary = {}


static func tab_id(i: int) -> StringName:
	return StringName("opt_tab_%d" % i)


static func is_tab(id: StringName) -> bool:
	return String(id).begins_with("opt_tab_")


## The tab that holds option `id` (0 when it is on none).
static func tab_of(id: StringName) -> int:
	for i in TABS.size():
		if (TABS[i][2] as Array).has(id):
			return i
	return 0


static func has_band(tab: int) -> bool:
	return BAND_TABS.has(tab)


static func _col_w(s: float) -> float:
	var vp_w := Game.get_viewport().get_visible_rect().size.x / s if Game.is_inside_tree() else 1600.0
	return minf(470.0, (vp_w - 80.0) * 0.5 - 8.0)


## Rect of row slot `row` (0 .. 7, column-major: four rows down the left column, then the right) of the open tab.
static func row_rect(row: int, cx: float, s: float, band := false) -> Rect2:
	var w := _col_w(s)
	var col := row / 4
	var top := BAND_ROW_TOP if band else ROW_TOP
	var pitch := BAND_ROW_PITCH if band else ROW_PITCH
	var box := BAND_ROW_BOX if band else ROW_BOX
	return Rect2(cx + (-w - 8.0 + float(col) * (w + 16.0)) * s, (top + float(row % 4) * pitch) * s, w * s, box * s)


## The band above the rows: the full width of the two columns.
static func band_rect(cx: float, s: float) -> Rect2:
	var w := _col_w(s)
	return Rect2(cx - (w + 8.0) * s, BAND_TOP * s, (2.0 * w + 16.0) * s, BAND_H * s)


## The tier card (left of the graphics band) and the four chips (right, two by two).
static func card_rect(cx: float, s: float) -> Rect2:
	var b := band_rect(cx, s)
	return Rect2(b.position, Vector2(b.size.x * 0.58, b.size.y))


static func chip_rect(i: int, cx: float, s: float) -> Rect2:
	var b := band_rect(cx, s)
	var x0 := b.position.x + b.size.x * 0.58 + 12.0 * s
	var cw := (b.end.x - x0 - 8.0 * s) * 0.5
	return Rect2(x0 + float(i % 2) * (cw + 8.0 * s), b.position.y + float(i / 2) * (64.0 + 8.0) * s, cw, 64.0 * s)


## Name and value halves of an option for the row look ("AIM ASSIST", "ON").
static func parts(st: UiSettings, id: StringName) -> Array:
	if TOGGLES.has(id):
		var l := label(st, id)
		var nm := Tr.t(TOGGLE_NAMES[id])
		return [nm, l.substr(nm.length() + 1)]
	if id == &"opt_mute":
		return [Tr.t("SOUND"), Tr.t("OFF" if st.muted else "ON")]
	if id == &"opt_bench":
		return [Tr.t("BENCHMARK"), Tr.t("RUN")]
	if id == &"opt_hints":
		return [Tr.t("REPLAY HINTS"), Tr.t("PLAY")]
	if id == &"opt_controls":
		return [Tr.t("BUTTON LAYOUT"), Tr.t("OPEN")]
	if id == &"opt_reset":
		return [Tr.t("RESET PROGRESS"), Tr.t("TAP AGAIN" if reset_armed else "ERASE")]
	if id == &"opt_reset_demo":
		return [Tr.t("RESET DEMO SLOT"), Tr.t("TAP AGAIN" if reset_demo_armed else "ERASE")]
	var lab := label(st, id)
	var k := lab.rfind("  ")
	if k > 0:
		return [lab.substr(0, k), lab.substr(k + 2)]
	return [lab, ""]


## RESET PAGE: the settings of tab `tab` back to their defaults (never progress, key binds, the language or the graphics tier the device chose).
static func reset_tab(st: UiSettings, tab: int) -> void:
	match tab:
		0:
			st.look_x = 1.0
			st.look_y = 1.0
			st.ads_sens = 1.0
			st.aim_assist = true
			st.auto_fire = false
			st.left_hand = false
			st.vibration = true
		1:
			st.res_mode = -1
			RenderRes.set_user(-1)
			st.fps_cap = 60
			st.post = true
			st.hud_scale = 1.0
			st.button_size = 1.0
			var tc := _touch()
			if tc != null:
				tc.show_perf(false)
		2:
			st.volumes = {"Music": 1.0, "SFX": 1.0, "Ambient": 1.0, "Voice": 1.0}       # explicit: Sfx.apply_volumes keeps a bus that is missing from the dictionary
			st.muted = false
			st.haptic_level = 1
			st.cutscenes = true
		3:
			st.text_scale = 1.0
			st.sub_size = 1.0
			st.sub_bg = 1
			st.subtitles = true
			st.cb_safe = false
			st.cb_variant = 0
			st.reduce_flash = false
			st.reduce_motion = false
		4:
			st.difficulty = Difficulty.default_mode()
			st.chatter = 1
			st.civilians = true
			st.dmg_numbers = true
			Difficulty.set_mode(Difficulty.default_mode())
	Sfx.apply_volumes(st.volumes)


static func layout(hud: Hud, st: UiSettings, cx: float, s: float) -> void:
	if UiSettings.s_opt_page == 2:
		ControlsScreen.layout(hud, st, cx, s)
		return
	var w := _col_w(s)
	var total := 2.0 * w + 16.0
	var tw := (total - 4.0 * 8.0) / float(TABS.size())
	for i in TABS.size():
		hud.buttons.append({"id": tab_id(i), "rect": Rect2(cx + (-total * 0.5 + float(i) * (tw + 8.0)) * s, TAB_Y * s, tw * s, TAB_H * s), "label": String(TABS[i][0]), "on": i == UiSettings.s_opt_tab, "tab": TABS[i][1]})
	var tab := clampi(UiSettings.s_opt_tab, 0, TABS.size() - 1)
	var band := has_band(tab)
	var ids: Array = TABS[tab][2]
	var slot := 0
	for row in ids.size():
		var id: StringName = ids[row]
		var pr := parts(st, id)
		if id == &"opt_tier":                                  # the tier card of the graphics band: a sample and what the tier costs; a tap cycles the tier
			hud.buttons.append({"id": id, "rect": card_rect(cx, s), "label": label(st, id), "on": true, "opt": true, "prev": true, "name": pr[0], "value": pr[1], "frac": -1.0})
			continue
		hud.buttons.append({"id": id, "rect": row_rect(slot, cx, s, band), "label": label(st, id), "on": is_slider(id) or is_on(st, id), "opt": true, "name": pr[0], "value": pr[1], "frac": fraction(st, id) if is_slider(id) else -1.0})
		slot += 1
	if tab == 1:
		for i in 4:
			hud.buttons.append({"id": StringName("opt_tierset_%d" % i), "rect": chip_rect(i, cx, s), "label": Game.TIER_LABELS[i], "on": Game.tier_index() == i})
	elif tab == 2:                                             # the sound test: a shot at the SFX volume, so the sliders can be judged by ear
		hud.buttons.append({"id": &"opt_sndtest", "rect": row_rect(slot, cx, s, band), "label": "TEST SOUND", "on": false})
	hud._add_card(&"opt_reset_tab", Rect2(cx + 14.0 * s, OPT_BACK_Y * s, 220.0 * s, UiUtil.TOUCH_MIN * s), "RESET PAGE", &"abort", "", false, UiUtil.MAGENTA)
	hud._add_card(&"options_back", Rect2(cx - 234.0 * s, OPT_BACK_Y * s, 220.0 * s, UiUtil.TOUCH_MIN * s), "BACK", &"back", "", false, UiUtil.AMBER)


static func _tier_texture(tier: int) -> Texture2D:
	if not _tier_tex.has(tier):
		var path := TIER_SHOT % tier
		_tier_tex[tier] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _tier_tex[tier]


## The tier card (Hud draws the `prev` button through this): a frame of the real game at the current tier on the left, three facts and a battery note on the right.
static func draw_card(hud: Hud, c: Control, r: Rect2, hot: bool, s: float, font: Font) -> void:
	var tier := Game.tier_index()
	c.draw_rect(r, MenuKit.FILL_ON if hot else MenuKit.FILL)
	c.draw_rect(r, Color(UiUtil.CYAN, 0.9 if hot else 0.4), false, 1.5 * s)
	var pic := Rect2(r.position + Vector2(8.0, 8.0) * s, Vector2(r.size.x * 0.44, r.size.y - 16.0 * s))
	var tex := _tier_texture(tier)
	if tex != null:
		var ta := pic.size.x / pic.size.y
		var sz := tex.get_size()
		var src := Rect2(Vector2.ZERO, sz)
		if sz.x / sz.y > ta:
			src = Rect2(Vector2((sz.x - sz.y * ta) * 0.5, 0.0), Vector2(sz.y * ta, sz.y))
		else:
			src = Rect2(Vector2(0.0, (sz.y - sz.x / ta) * 0.5), Vector2(sz.x, sz.x / ta))
		c.draw_texture_rect_region(tex, pic, src)
	else:
		c.draw_rect(pic, Color(0.05, 0.08, 0.12, 1.0))
	c.draw_rect(pic, Color(UiUtil.CYAN, 0.5), false, 1.5 * s)
	var tag := Rect2(pic.position + Vector2(6.0, 6.0) * s, Vector2(70.0 * s, 28.0 * s))
	c.draw_rect(tag, Color(0.0, 0.0, 0.0, 0.7))
	hud._text(c, font, Vector2(tag.position.x, tag.position.y + 21.0 * s), Game.TIER_LABELS[tier], HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, int(20.0 * s), Color(UiUtil.CYAN, 1.0))
	var facts: Array = TIER_FACTS[tier]
	var x := pic.end.x + 14.0 * s
	var wd := r.end.x - x - 8.0 * s
	for i in 3:
		hud._text(c, font, Vector2(x, r.position.y + (31.0 + 31.0 * float(i)) * s), "%s  %s" % [Tr.t(String((facts[i] as Array)[0])), Tr.t(String((facts[i] as Array)[1]))], HORIZONTAL_ALIGNMENT_LEFT, wd, int(17.0 * s), Color(1, 1, 1, 0.95))
	hud._text(c, font, Vector2(x, r.position.y + (31.0 + 31.0 * 3.0) * s), String(facts[3]), HORIZONTAL_ALIGNMENT_LEFT, wd, int(17.0 * s), Color(UiUtil.AMBER, 0.95))


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float) -> void:
	if UiSettings.s_opt_page == 2:
		ControlsScreen.draw(hud, c, vp, s, font)
		return
	hud.header(c, vp, s, font, "OPTIONS")
	var tab := UiSettings.s_opt_tab
	if tab == 3:                                            # the access band: the subtitle plate and the marker colours as they are now
		var b2 := band_rect(cx, s)
		c.draw_rect(b2, MenuKit.FILL)
		c.draw_rect(b2, Color(UiUtil.CYAN, 0.4), false, 1.5 * s)
		var st2: UiSettings = hud.settings
		var plate := Rect2(b2.position + Vector2(14.0, 14.0) * s, Vector2(b2.size.x * 0.62, b2.size.y - 28.0 * s))
		var pa: float = [0.45, 0.72, 0.95][clampi(st2.sub_bg, 0, 2)]
		c.draw_rect(plate, Color(0.02, 0.03, 0.05, pa))
		var fsz := int(20.0 * s * st2.sub_size * st2.text_scale)
		hud._text(c, font, Vector2(plate.position.x + 14.0 * s, plate.position.y + 30.0 * s), "ORACLE" if st2.subtitles else "SUBTITLES OFF", HORIZONTAL_ALIGNMENT_LEFT, plate.size.x - 28.0 * s, int(17.0 * s), Color(UiUtil.CYAN, 0.9))
		if st2.subtitles:
			hud._text(c, font, Vector2(plate.position.x + 14.0 * s, plate.position.y + 30.0 * s + fsz * 1.35), "Cross the floor to the beacon.", HORIZONTAL_ALIGNMENT_LEFT, plate.size.x - 28.0 * s, fsz, Color(1, 1, 1, 0.97))
		var sx := plate.end.x + 18.0 * s
		var names := ["HOSTILE", "FRIEND", "GOAL"]
		var cols: Array[Color] = [UiUtil.hostile_col(), UiUtil.friend_col(), UiUtil.objective_col()]
		for k in 3:
			var sy := b2.position.y + (20.0 + 36.0 * float(k)) * s
			c.draw_circle(Vector2(sx + 14.0 * s, sy + 12.0 * s), 12.0 * s, cols[k])
			hud._text(c, font, Vector2(sx + 38.0 * s, sy + 22.0 * s), names[k], HORIZONTAL_ALIGNMENT_LEFT, b2.end.x - sx - 46.0 * s, int(18.0 * s), Color(1, 1, 1, 0.85))
