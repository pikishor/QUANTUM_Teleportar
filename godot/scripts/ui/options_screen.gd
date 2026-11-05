class_name OptionsScreen
extends RefCounted
## The options screen (Hud draws it when `_options_open`, opened by the OPTIONS button of the title and pause screens): every row is >= 64 px tall for touch. Sliders (look X / Y, ADS,
## HUD scale, button size) are `opt_*` buttons whose rect is the track; toggles and cycles (aim assist, auto fire, left-handed layout, vibration, subtitles, colour-blind safe
## markers, FPS cap, graphics tier) are plain presses. Pure layout and settings math, no state of its own: every value lives in UiSettings.

const ROW_H := 64.0
const PITCH := 70.0
const TOP := 118.0
const COL_W := 300.0
const GAP := 12.0
const BACK_Y := 612.0

## slider id -> [label, min, max, UiSettings field]
const SLIDERS := {
	&"opt_look_x": ["LOOK X", UiSettings.SENS_MIN, UiSettings.SENS_MAX, &"look_x"],
	&"opt_look_y": ["LOOK Y", UiSettings.SENS_MIN, UiSettings.SENS_MAX, &"look_y"],
	&"opt_ads": ["ADS", UiSettings.SENS_MIN, UiSettings.SENS_MAX, &"ads_sens"],
	&"opt_hud": ["HUD SIZE", UiSettings.HUD_MIN, UiSettings.HUD_MAX, &"hud_scale"],
	&"opt_btn": ["BUTTONS", UiSettings.BTN_MIN, UiSettings.BTN_MAX, &"button_size"],
}
const TOGGLES := {
	&"opt_aim": &"aim_assist", &"opt_auto": &"auto_fire", &"opt_left": &"left_hand",
	&"opt_vib": &"vibration", &"opt_subs": &"subtitles", &"opt_cb": &"cb_safe",
	&"opt_flash": &"reduce_flash", &"opt_motion": &"reduce_motion",
}
const TOGGLE_NAMES := {
	&"opt_aim": "AIM ASSIST", &"opt_auto": "AUTO FIRE", &"opt_left": "LEFT HAND",
	&"opt_vib": "VIBRATION", &"opt_subs": "SUBTITLES", &"opt_cb": "COLOUR SAFE",
	&"opt_flash": "REDUCE FLASH", &"opt_motion": "REDUCE MOTION",
}
## Page 1 (accessibility) ids; opt_page flips between the pages and sits in the last cell of both.
const PAGE2: Array[StringName] = [&"opt_lang", &"opt_text", &"opt_flash", &"opt_motion", &"opt_subsize", &"opt_subbg", &"opt_hints", &"opt_diff", &"opt_res", &"opt_haptic", &"opt_controls"]
const PAGE_CELL := 13
const SUB_BG_NAMES: Array[String] = ["SOFT", "", "SOLID"]
const CB_NAMES: Array[String] = ["DEUTAN", "TRITAN"]
const ORDER: Array[StringName] = [
	&"opt_look_x", &"opt_look_y", &"opt_ads", &"opt_hud", &"opt_btn", &"opt_tier",
	&"opt_aim", &"opt_auto", &"opt_left", &"opt_vib", &"opt_subs", &"opt_cb",
	&"opt_fps",
]


static func is_slider(id: StringName) -> bool:
	return SLIDERS.has(id)


static func is_option(id: StringName) -> bool:
	return SLIDERS.has(id) or TOGGLES.has(id) or id == &"opt_fps" or id == &"opt_tier" or id == &"opt_res" or id == &"opt_page" or PAGE2.has(id)


static func fraction(st: UiSettings, id: StringName) -> float:
	var d: Array = SLIDERS[id]
	return clampf((float(st.get(d[3])) - float(d[1])) / (float(d[2]) - float(d[1])), 0.0, 1.0)


## Sets a slider from a 0..1 fraction (snapped to 0.05 of the value); returns the value.
static func set_fraction(st: UiSettings, id: StringName, f: float) -> float:
	var d: Array = SLIDERS[id]
	var v := snappedf(lerpf(float(d[1]), float(d[2]), clampf(f, 0.0, 1.0)), 0.05)
	v = clampf(v, float(d[1]), float(d[2]))
	st.set(d[3], v)
	return v


static func label(st: UiSettings, id: StringName) -> String:
	if SLIDERS.has(id):
		return "%s  %d%%" % [Tr.t(SLIDERS[id][0]), roundi(float(st.get(SLIDERS[id][3])) * 100.0)]
	if TOGGLES.has(id):
		var on := bool(st.get(TOGGLES[id]))
		if id == &"opt_cb" and on:
			return "%s %s" % [Tr.t(TOGGLE_NAMES[id]), Tr.t(CB_NAMES[st.cb_variant])]
		return "%s %s" % [Tr.t(TOGGLE_NAMES[id]), Tr.t("ON" if on else "OFF")]
	if id == &"opt_fps":
		return Tr.t("FPS CAP") + "  " + (Tr.t("OFF") if st.fps_cap == 0 else str(st.fps_cap))
	if id == &"opt_tier":
		return Tr.t("GRAPHICS") + "  " + Tr.t(Hud.TIER_NAMES[clampi(Game.quality, 0, 2)])
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
	if id == &"opt_subbg":
		return Tr.t("SUBTITLE BG") + "  " + Tr.t(SUB_BG_NAMES[st.sub_bg] if st.sub_bg != 1 else "ON")
	return ""


static func is_on(st: UiSettings, id: StringName) -> bool:
	return TOGGLES.has(id) and bool(st.get(TOGGLES[id]))


## Flips a toggle or cycles FPS cap / graphics tier. Returns true when it changed something.
static func press(st: UiSettings, id: StringName) -> bool:
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
	if id == &"opt_fps":
		st.fps_cap = st.next_fps_cap()
		return true
	if id == &"opt_res":
		st.res_mode = RenderRes.next_mode()
		RenderRes.set_user(st.res_mode)
		return true
	if id == &"opt_tier":
		st.quality = (clampi(Game.quality, 0, 2) + 1) % 3
		Game.set_quality(st.quality)
		return true
	return false


static func cell_rect(i: int, cx: float, s: float) -> Rect2:
	var col := i % 2
	var row := i / 2
	return Rect2(cx - (COL_W + GAP * 0.5) * s + col * (COL_W + GAP) * s, (TOP + row * PITCH) * s, COL_W * s, ROW_H * s)


static func layout(hud: Hud, st: UiSettings, cx: float, s: float) -> void:
	if UiSettings.s_opt_page == 2:
		ControlsScreen.layout(hud, st, cx, s)
		return
	var ids: Array[StringName] = PAGE2 if UiSettings.s_opt_page == 1 else ORDER
	for i in ids.size():
		var id: StringName = ids[i]
		hud._add(id, cell_rect(i, cx, s), label(st, id), is_slider(id) or is_on(st, id))
	hud._add(&"opt_page", cell_rect(PAGE_CELL, cx, s), label(st, &"opt_page"), false)
	hud._add(&"options_back", Rect2(cx - 110.0 * s, BACK_Y * s, 220.0 * s, ROW_H * s), "BACK", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, _cx: float) -> void:
	if UiSettings.s_opt_page == 2:
		ControlsScreen.draw(hud, c, vp, s, font)
		return
	hud._text(c, font, Vector2(0.0, 84.0 * s), "OPTIONS", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(40.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
