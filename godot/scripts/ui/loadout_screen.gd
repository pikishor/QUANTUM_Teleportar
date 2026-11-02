class_name LoadoutScreen
extends RefCounted
## Weapon wheel and attachment loadout (Hud draws it on the pause screen when `_loadout_open`). Left: a wheel of the owned weapons (buttons `wheel_<id>`, tap = swap to it;
## opened from a SWAP long-press it resumes the game at once). Right: the three slots (optic, barrel, core) of the selected weapon, three parts each (buttons `part_<id>`:
## BUY price, EQUIP, or ON to take it off). `loadout_back` returns. State lives in Hud (`_loadout_w`, `_loadout_quick`), numbers in Attachments and Progress.

const WHEEL_R := 150.0
const WHEEL_DX := -250.0
const WHEEL_Y := 380.0
const SLOT_Y := 190.0
const SLOT_STEP := 110.0
const PART_W := 150.0


static func owned_weapons() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in WeaponDefs.IDS:
		if WeaponDefs.is_unlocked(id):
			out.append(id)
	return out


static func layout(hud: Hud, cx: float, s: float, sel: StringName) -> void:
	var prog := Game.progress as Progress
	var ow := owned_weapons()
	for i in ow.size():
		var a := -PI * 0.5 + TAU * float(i) / float(ow.size())
		var ctr := Vector2(cx + (WHEEL_DX + cos(a) * WHEEL_R) * s, (WHEEL_Y + sin(a) * WHEEL_R) * s)
		hud._add(StringName("wheel_%s" % ow[i]), Rect2(ctr - Vector2(54.0, 24.0) * s, Vector2(108.0, 48.0) * s), String(WeaponDefs.def(ow[i])["tag"]), ow[i] == sel)
	for k in Attachments.SLOTS.size():
		var parts := Attachments.parts_for(Attachments.SLOTS[k])
		for j in parts.size():
			var part := parts[j]
			var label := "ON" if Attachments.part_in(sel, Attachments.SLOTS[k]) == part else ("EQUIP" if Attachments.is_owned(part) else "BUY  %d" % (prog.part_price(part) if prog != null else 0))
			var on := Attachments.part_in(sel, Attachments.SLOTS[k]) == part
			hud._add(StringName("part_%s" % part), Rect2(cx + (20.0 + j * (PART_W + 8.0)) * s, (SLOT_Y + k * SLOT_STEP + 26.0) * s, PART_W * s, 48.0 * s), label, on)
	hud._add(&"loadout_back", Rect2(cx - 110.0 * s, 640.0 * s, 220.0 * s, 44.0 * s), "RESUME" if hud._loadout_quick else "BACK", false)


static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, cx: float, sel: StringName) -> void:
	var prog := Game.progress as Progress
	hud._text(c, font, Vector2(0.0, 92.0 * s), "LOADOUT", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(52.0 * s), Color(1, 1, 1, 0.97), 3.0 * s)
	if prog != null:
		hud._text(c, font, Vector2(0.0, 134.0 * s), "CREDITS  %d" % prog.credits, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(UiUtil.AMBER, 0.97), 1.0 * s)
	hud._text(c, font, Vector2(cx + (WHEEL_DX - 120.0) * s, (WHEEL_Y - 6.0) * s), WeaponDefs.title(sel), HORIZONTAL_ALIGNMENT_CENTER, 240.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.CYAN, 0.95), 1.0 * s)
	var d := Attachments.effective(sel)
	hud._text(c, font, Vector2(cx + (WHEEL_DX - 120.0) * s, (WHEEL_Y + 20.0) * s), "DMG %d  MAG %d" % [int(roundf(float(d["damage"]))), int(d["mag"])], HORIZONTAL_ALIGNMENT_CENTER, 240.0 * s, int(UiUtil.BAR_LABEL * s), Color(1, 1, 1, 0.85), 1.0 * s)
	for k in Attachments.SLOTS.size():
		var y := (SLOT_Y + k * SLOT_STEP) * s
		hud._text(c, font, Vector2(cx + 20.0 * s, y + 14.0 * s), String(Attachments.SLOTS[k]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 200.0 * s, int(UiUtil.BAR_LABEL * s), Color(UiUtil.AMBER, 0.95), 1.0 * s)
		var parts := Attachments.parts_for(Attachments.SLOTS[k])
		for j in parts.size():
			hud._text(c, font, Vector2(cx + (20.0 + j * (PART_W + 8.0)) * s, y + 94.0 * s), String(Attachments.PARTS[parts[j]]["name"]), HORIZONTAL_ALIGNMENT_LEFT, PART_W * s, int(14.0 * s), Color(1, 1, 1, 0.9), 0.0)
