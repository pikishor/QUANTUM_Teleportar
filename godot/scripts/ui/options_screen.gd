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
}
const TOGGLE_NAMES := {
	&"opt_aim": "AIM ASSIST", &"opt_auto": "AUTO FIRE", &"opt_left": "LEFT HAND",
	&"opt_vib": "VIBRATION", &"opt_subs": "SUBTITLES", &"opt_cb": "COLOUR SAFE",
}
const ORDER: Array[StringName] = [
	&"opt_look_x", &"opt_look_y", &"opt_ads", &"opt_hud", &"opt_btn", &"opt_tier",
	&"opt_aim", &"opt_auto", &"opt_left", &"opt_vib", &"opt_subs", &"opt_cb",
	&"opt_fps",
]


static func is_slider(id: StringName) -> bool:
	return SLIDERS.has(id)


static func is_option(id: StringName) -> bool:
	return SLIDERS.has(id) or TOGGLES.has(id) or id == &"opt_fps" or id == &"opt_tier"


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
		return "%s  %d%%" % [SLIDERS[id][0], roundi(float(st.get(SLIDERS[id][3])) * 100.0)]
	if TOGGLES.has(id):
		return "%s %s" % [TOGGLE_NAMES[id], "ON" if bool(st.get(TOGGLES[id])) else "OFF"]
	if id == &"opt_fps":
		return "FPS CAP  " + ("OFF" if st.fps_cap == 0 else str(st.fps_cap))
	if id == &"opt_tier":
		return "GRAPHICS  " + Hud.TIER_NAMES[clampi(Game.quality, 0, 2)]
	return ""


static func is_on(st: UiSettings, id: StringName) -> bool:
	return TOGGLES.has(id) and bool(st.get(TOGGLES[id]))


## Flips a toggle or cycles FPS cap / graphics tier. Returns true when it changed something.
static func press(st: UiSettings, id: StringName) -> bool:
	if TOGGLES.has(id):
		st.set(TOGGLES[id], not bool(st.get(TOGGLES[id])))
		return true
	if id == &"opt_fps":
		st.fps_cap = st.next_fps_cap()
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
	for i in ORDER.size():
		var id: StringName = ORDER[i]
		hud._add(id, cell_rect(i, cx, s), label(st, id), is_slider(id) or is_on(st, id))
	hud._add(&"options_back", Rect2(cx - 110.0 * s, BACK_Y * s, 220.0 * s, ROW_H * s), "BACK", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, _cx: float) -> void:
	hud._text(c, font, Vector2(0.0, 84.0 * s), "OPTIONS", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(40.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
