class_name ControlsScreen
extends RefCounted
## The CONTROLS screen (options page 2, opened by the CONTROLS button of the accessibility page): remap the keyboard (KEYBOARD tab) or the controller (CONTROLLER tab).
## Press a row, then the key or the pad button (LB held first for the second layer): the action that used it swaps places. Every cell is >= 64 px. The left-handed touch
## layout stays in OPTIONS (LEFT HAND). Pure layout and settings math; the live capture comes from ControllerInput (keys, pad buttons).

const PER_PAGE := 12

static var tab := 0                       ## 0 keyboard, 1 controller
static var page := 0
static var listening: StringName = &""    ## the action waiting for its key / button


static func reset_state() -> void:
	tab = 1 if ControllerInput.pad_ui else 0
	page = 0
	listening = &""


static func actions() -> Array[StringName]:
	return ControlMap.KEY_ACTIONS if tab == 0 else ControlMap.PAD_ACTIONS


static func pages() -> int:
	return maxi(ceili(float(actions().size()) / float(PER_PAGE)), 1)


static func page_actions() -> Array[StringName]:
	var all := actions()
	var out: Array[StringName] = []
	for i in range(page * PER_PAGE, mini((page + 1) * PER_PAGE, all.size())):
		out.append(all[i])
	return out


static func binding_text(a: StringName) -> String:
	if tab == 0:
		return ControlMap.key_label(ControlMap.key_of(a))
	var slot := ControlMap.slot_of(ControlMap.pad_binds, a)
	return "-" if slot == "" else ControlMap.slot_label(slot)


static func row_label(a: StringName) -> String:
	if listening == a:
		return Tr.t("PRESS A KEY") if tab == 0 else Tr.t("PRESS A BUTTON")
	return "%s  %s" % [Tr.t(ControlMap.action_name(a)), binding_text(a)]


static func is_id(id: StringName) -> bool:
	return String(id).begins_with("ctl_")


static func layout(hud: Hud, _st: UiSettings, cx: float, s: float) -> void:
	hud._add(&"ctl_tab_key", OptionsScreen.cell_rect(0, cx, s), "KEYBOARD", tab == 0)
	hud._add(&"ctl_tab_pad", OptionsScreen.cell_rect(1, cx, s), "CONTROLLER", tab == 1)
	var acts := page_actions()
	for j in acts.size():
		hud._add(StringName("ctl_row_" + String(acts[j])), OptionsScreen.cell_rect(2 + j, cx, s), row_label(acts[j]), listening == acts[j])
	var w := (OptionsScreen.COL_W * 2.0 + OptionsScreen.GAP - 2.0 * OptionsScreen.GAP) / 3.0
	var x0 := cx - (OptionsScreen.COL_W + OptionsScreen.GAP * 0.5) * s
	var y := OptionsScreen.BACK_Y * s
	hud._add(&"ctl_page", Rect2(x0, y, w * s, OptionsScreen.ROW_H * s), "PAGE %d/%d" % [page + 1, pages()], false)
	hud._add(&"ctl_reset", Rect2(x0 + (w + OptionsScreen.GAP) * s, y, w * s, OptionsScreen.ROW_H * s), "RESET", false)
	hud._add(&"ctl_back", Rect2(x0 + (w + OptionsScreen.GAP) * 2.0 * s, y, w * s, OptionsScreen.ROW_H * s), "BACK", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font) -> void:
	var title := "CONTROLS"
	if listening != &"":
		title = "PRESS A KEY  (ESC CANCELS)" if tab == 0 else "PRESS A BUTTON  (LB FIRST FOR LB+)"
	hud._text(c, font, Vector2(0.0, 84.0 * s), title, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(36.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)


## Presses one of the screen's buttons. Returns true when it changed something.
static func press(st: UiSettings, id: StringName) -> bool:
	var sid := String(id)
	if sid == "ctl_tab_key" or sid == "ctl_tab_pad":
		tab = 0 if sid == "ctl_tab_key" else 1
		page = 0
		listening = &""
		return true
	if sid == "ctl_page":
		page = (page + 1) % pages()
		listening = &""
		return true
	if sid == "ctl_back":
		listening = &""
		UiSettings.s_opt_page = 0
		return true
	if sid == "ctl_reset":
		listening = &""
		if tab == 0:
			ControlMap.reset_keys()
			st.key_binds = {}
		else:
			st.pad_binds = ControlMap.default_pad()
			ControlMap.pad_binds = st.pad_binds.duplicate()
		return true
	if sid.begins_with("ctl_row_"):
		var a := StringName(sid.substr(8))
		if not actions().has(a):
			return false
		listening = &"" if listening == a else a
		return true
	return false


## A key arrived while a keyboard row waits. Returns true when it was used (ESC cancels).
static func capture_key(st: UiSettings, code: int) -> bool:
	if listening == &"" or tab != 0:
		return false
	if code == KEY_ESCAPE:
		listening = &""
		return true
	if ControlMap.RESERVED_KEYS.has(code):
		return true
	ControlMap.rebind_key(st.key_binds, listening, code)
	listening = &""
	return true


## A pad button arrived while a controller row waits: `slot` is "0:a" / "1:rt" style. Returns true when it was used.
static func capture_pad(st: UiSettings, slot: String) -> bool:
	if listening == &"" or tab != 1 or not ControlMap.slot_valid(slot):
		return false
	ControlMap.rebind_pad(st.pad_binds, listening, slot)
	ControlMap.pad_binds = st.pad_binds.duplicate()
	listening = &""
	return true
