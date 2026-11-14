class_name ArsenalCard
extends RefCounted
## The card of the Arsenal (wave 114): the selected weapon (or throwable / gadget) read in three tabs.
##  - the PICTURE block: the weapon's rendered picture on its class backdrop (or the live 3D turntable), the name, the class badge, what the hero has with it, its first perk line;
##  - STATS: seven bars (damage, range, fire rate, accuracy, handling, magazine, blast radius) that glide to the weapon's numbers, each with its value and, against the weapon in hand, the +/- difference;
##    the range and blast rings to scale beside a person (WeaponRings); where to get it or what it is for;
##  - PARTS: the slot tabs, the parts of the open slot as cards (name, effect, FITTED / OWNED / price), a LIVE PREVIEW of the tapped part (every stat that changes, before and after, and the live 3D
##    weapon next to it), the action (FIT / TAKE OFF / BUY) in the bottom bar, the WORKBENCH button;
##  - AMMO: the ammo types the weapon fires as cards, the loaded one lit, what each does.
## Layout adds the buttons of the tab (`ars_slottab_*`, `ars_part_*`, `ars_ammo_*`, `ars_bench`); drawing reads Arsenal's state. Text goes through Hud._text.

const BAR_LAB := 132.0                     ## base px of the label column of a bar (122 let BLAST RADIUS touch its bar: wave 114 critic)
const BAR_VAL := 92.0
const BAR_DLT := 36.0
const PART_W := 211.0
const PART_H := 92.0
const PART_GAP := 8.0


static func active_slot(mode: StringName, sel: StringName) -> StringName:
	var slots := Attachments.slots_for_weapon(sel)
	if slots.is_empty():
		return &""
	var cur: StringName = Arsenal.st(mode)["slot"]
	return cur if slots.has(cur) else slots[0]


static func ammo_indices(sel: StringName) -> Array:
	var d := WeaponDefs.def(sel)
	if String(d["kind"]) != "hit":
		return []
	var l: Variant = d.get("ammo_types", null)
	if l is Array and not (l as Array).is_empty():
		return l
	return [0, 1, 2]


static func part_rect(content: Rect2, s: float, j: int) -> Rect2:
	var k := content.size.x / (3.0 * PART_W + 2.0 * PART_GAP) / s
	return Rect2(content.position.x + float(j % 3) * (PART_W + PART_GAP) * s * k, content.position.y + (64.0 + 6.0 + float(j / 3) * (PART_H + 6.0)) * s, PART_W * s * k, PART_H * s)


static func ammo_rect(content: Rect2, s: float, j: int) -> Rect2:
	var k := content.size.x / (3.0 * PART_W + 2.0 * PART_GAP) / s
	return Rect2(content.position.x + float(j % 3) * (PART_W + PART_GAP) * s * k, content.position.y + (4.0 + float(j / 3) * 82.0) * s, PART_W * s * k, 76.0 * s)


# ---------------------------------------------------------------------------------------------------------------------------------- layout

static func layout(hud: Hud, vp: Vector2, s: float, mode: StringName, sel: StringName, tab: StringName, cr: Dictionary) -> void:
	if WeaponsScreen.is_gear(sel) or not WeaponDefs.is_unlocked(sel):
		return
	var content: Rect2 = cr["content"]
	var stt := Arsenal.st(mode)
	if tab == &"parts":
		var slots := Attachments.slots_for_weapon(sel)
		if slots.is_empty():
			return
		var slot := active_slot(mode, sel)
		var n := slots.size()
		var gap := 6.0 * s
		var cw := (content.size.x - gap * float(n - 1)) / float(n)
		for i in n:
			hud.buttons.append({"id": StringName("ars_slottab_%s" % slots[i]), "rect": Rect2(content.position.x + float(i) * (cw + gap), content.position.y, cw, 64.0 * s), "label": Attachments.slot_label(slots[i]), "on": slots[i] == slot, "own": true})
		var parts := Attachments.parts_for_weapon(slot, sel)
		for j in mini(parts.size(), 6):
			var pj: StringName = parts[j]
			var pfx := String(AttachmentPartsV3.FX.get(pj, ""))
			if pfx == "":
				pfx = Attachments.effect_text(pj)
			var pst := "FITTED" if Attachments.part_in(sel, slot) == pj else ("OWNED" if Attachments.is_owned(pj) else "BUY")
			if pst == "OWNED" and MissionRewards.is_new(pj):
				pst = "NEW"                                                      # a mod just found or won: flagged until it is fitted
			hud.buttons.append({"id": StringName("ars_part_%s" % pj), "rect": part_rect(content, s, j), "label": "", "on": pj == stt["part"], "own": true, "pid": pj, "name": String(Attachments.PARTS[pj]["name"]), "fx": pfx, "status": pst})
		var by := content.position.y + (64.0 + 6.0 + 2.0 * (PART_H + 6.0)) * s
		if by + 64.0 * s <= content.end.y + 1.0:
			hud.buttons.append({"id": &"ars_bench", "rect": Rect2(content.position.x, by, 206.0 * s * (content.size.x / (650.0 * s)), 64.0 * s), "label": "WORKBENCH", "on": false, "own": true})
	elif tab == &"ammo":
		var idx := ammo_indices(sel)
		for j in mini(idx.size(), 9):
			hud.buttons.append({"id": StringName("ars_ammo_%d" % int(idx[j])), "rect": ammo_rect(content, s, j), "label": "", "on": int(idx[j]) == loaded_ammo(), "own": true})


## The ammo type that is loaded now (the saved choice, which the weapon in hand follows).
static func loaded_ammo() -> int:
	var p := Game.progress as Progress
	return int(p.ammo_type) if p != null else 0


# ---------------------------------------------------------------------------------------------------------------------------------- presses

## A tap on a part card: it becomes the PREVIEW (the picture block shows what it changes); the action button (FIT / TAKE OFF / BUY) applies it.
static func press_part(hud: Hud, mode: StringName, sel: StringName, part: StringName) -> bool:
	if not Attachments.PARTS.has(part) or not Attachments.fits(part, sel):
		return false
	Arsenal.st(mode)["part"] = part
	Sfx.play(&"ui_tap")
	hud._layout_key = ""
	hud._screen.queue_redraw()
	return true


## FIT, TAKE OFF or BUY of the previewed part. Returns true when something happened.
static func apply_part(hud: Hud, mode: StringName, sel: StringName) -> bool:
	var part: StringName = Arsenal.st(mode)["part"]
	var prog := Game.progress as Progress
	if prog == null or not Attachments.PARTS.has(part) or not Attachments.fits(part, sel):
		return false
	var slot := Attachments.slot_of(part)
	if Attachments.part_in(sel, slot) == part:
		prog.equip_part(sel, part)                                              # the same call toggles it off (Progress.equip_part -> Attachments.toggle)
		Sfx.play(&"ui_tap")
	else:
		if not Attachments.is_owned(part) and not prog.buy_part(part):
			Sfx.play(&"ui_deny")
			return false
		prog.equip_part(sel, part)
		Sfx.play(&"ui_purchase")
	hud._layout_key = ""
	hud._screen.queue_redraw()
	return true


static func press_ammo(hud: Hud, mode: StringName, sel: StringName, idx: int) -> bool:
	if not ammo_indices(sel).has(idx):
		return false
	var p := Game.progress as Progress
	if p != null:
		p.set_ammo_type(idx)
	var pl := Game.player
	if is_instance_valid(pl) and pl.get(&"weapon") is PlayerWeapon:
		(pl.get(&"weapon") as PlayerWeapon).ammo_type = idx
	Arsenal.st(mode)["ammo"] = idx
	Sfx.play(&"ui_confirm")
	hud._layout_key = ""
	hud._screen.queue_redraw()
	return true


# ---------------------------------------------------------------------------------------------------------------------------------- drawing

static func draw(hud: Hud, c: Control, vp: Vector2, s: float, font: Font, mode: StringName, sel: StringName, tint: Color) -> void:
	var stt := Arsenal.st(mode)
	var gear := WeaponsScreen.is_gear(sel)
	var owned := Gear.is_owned(sel) if gear else WeaponDefs.is_unlocked(sel)
	var tab: StringName = &"stats" if (gear or not owned) else stt["tab"]
	if tab == &"parts" and not Attachments.fits_any(sel):
		tab = &"stats"
	if tab == &"ammo" and ammo_indices(sel).size() < 2:
		tab = &"stats"
	var cr := Arsenal.card_rects(vp, s, tab)
	_picture(hud, c, s, font, mode, sel, tint, cr["pic"], tab, gear, owned)
	for b: Dictionary in hud.buttons:
		var id := String(b["id"])
		if id.begins_with("ars_tab_"):
			UiKit.tab(hud, c, b["rect"], String(b["label"]), &"", bool(b["on"]), hud._hover == b["id"], s, font, tint)
		elif id == "ars_view3d":
			UiKit.button(hud, c, b["rect"], String(b["label"]), UiUtil.CYAN, 1 if b["on"] else 0, s, font, UiKit.T_LABEL)
	if gear:
		_gear_content(hud, c, s, font, sel, tint, cr["content"])
		return
	match tab:
		&"parts":
			_parts(hud, c, s, font, mode, sel, tint, cr["content"])
		&"ammo":
			_ammo(hud, c, s, font, mode, sel, tint, cr["content"])
		_:
			_stats(hud, c, s, font, sel, tint, cr["content"], owned)


static func status_text(sel: StringName) -> String:
	if WeaponsScreen.is_gear(sel):
		return "OWNED" if Gear.is_owned(sel) else "NOT OWNED"
	if not WeaponDefs.is_unlocked(sel):
		return "NOT OWNED"
	var bits: Array[String] = ["OWNED"]
	if sel == WeaponDefs.last_used:
		bits.append("IN HAND")
	var sl := LoadoutSlots.slot_of(sel)
	if sl >= 0:
		bits.append("SLOT %d" % (sl + 1))
	return "  ".join(bits)


static func _picture(hud: Hud, c: Control, s: float, font: Font, mode: StringName, sel: StringName, tint: Color, pic: Rect2, tab: StringName, gear: bool, owned: bool) -> void:
	var age := hud._t - Arsenal.sel_at
	var k := UiKit.ease_out(age / 0.24)
	UiKit.panel(c, pic, s, tint, false, 12.0, true)
	var inner := pic.grow(-5.0 * s)
	var big := tab == &"stats"
	var pa := inner if big else Rect2(inner.position, Vector2(inner.size.x * 0.5, inner.size.y))
	var cls := WeaponDefs.class_of(sel) if not gear else &"melee"
	var drew3d := false
	if not gear and WeaponModels.has_model(sel) and (Arsenal.view3d or tab == &"parts") and owned:
		var pv := WeaponPreview.of(hud)
		if pv.show_weapon(sel):
			WeaponPics.draw_backdrop(c, pa, cls, hud._t, 1.0)
			pv.draw(c, pa)
			hud.preview_rect = pa
			UiKit.glyph(c, &"rotate", Vector2(pa.end.x - 16.0 * s, pa.end.y - 16.0 * s), 8.0 * s, Color(1, 1, 1, 0.6), s)
			drew3d = true
	if not drew3d:
		var sc := 0.93 + 0.07 * k
		var art := Rect2(pa.get_center() - pa.size * sc * 0.5, pa.size * sc)
		if gear:
			WeaponPics.draw_backdrop(c, art, &"pistol", hud._t, 1.0)
			ItemIcons.draw_tex(c, ItemIcons.gear(sel), art.grow(-14.0 * s), Color(1, 1, 1, k))
		else:
			WeaponPics.draw_backdrop(c, art, cls, hud._t, 0.55 if not owned else 1.0)
			var fit := Rect2(art.position + Vector2(art.size.x * 0.03, art.size.y * 0.25), Vector2(art.size.x * 0.94, art.size.y * 0.65))      # clear of the name and the status line above it
			WeaponPics.draw_fit(c, sel, fit, true, Color(1, 1, 1, 0.35 + 0.65 * k) if owned else Color(0.62, 0.66, 0.78, 0.95), 2.2)
	if big:
		_picture_text(hud, c, s, font, sel, tint, pa, gear, owned, cls)
	else:
		_picture_side(hud, c, s, font, mode, sel, tint, Rect2(inner.position + Vector2(inner.size.x * 0.5 + 12.0 * s, 0.0), Vector2(inner.size.x * 0.5 - 14.0 * s, inner.size.y)), tab)


## The name, the class badge, what the hero has with it and the perk line over the big picture.
static func _picture_text(hud: Hud, c: Control, s: float, font: Font, sel: StringName, tint: Color, pa: Rect2, gear: bool, owned: bool, cls: StringName) -> void:
	var strip := Rect2(pa.position, Vector2(pa.size.x, 62.0 * s))                        # a dark strip under the name keeps it readable over any picture
	c.draw_polygon(PackedVector2Array([strip.position, Vector2(strip.end.x, strip.position.y), strip.end, Vector2(strip.position.x, strip.end.y)]), PackedColorArray([Color(0, 0, 0, 0.62), Color(0, 0, 0, 0.62), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0)]))
	var nm := Arsenal._title(sel)
	var nw := pa.size.x * 0.62
	hud._text(c, font, Vector2(pa.position.x + 12.0 * s, pa.position.y + 30.0 * s), nm, HORIZONTAL_ALIGNMENT_LEFT, nw, UiUtil.fit_size(font, nm, nw, int(30.0 * s)), Color(1, 1, 1, 0.99), 1.0 * s)
	var cname := String(WeaponDefs.CLASS_NAMES.get(cls, "")) if not gear else ("GADGET" if Gear.is_gadget(sel) else ("CHARGE" if Gear.is_charge(sel) else "THROWABLE"))
	UiKit.badge(hud, c, Vector2(pa.end.x - 10.0 * s, pa.position.y + 24.0 * s), cname, tint, s, font, true, true)
	hud._text(c, font, Vector2(pa.position.x + 12.0 * s, pa.position.y + 52.0 * s), status_text(sel), HORIZONTAL_ALIGNMENT_LEFT, nw, int(Hud.BODY_MIN * 1.15 * s), Color(UiUtil.GREEN if owned else UiUtil.AMBER, 0.98))
	if not gear and WeaponBrowser.is_new(sel):
		UiKit.badge(hud, c, Vector2(pa.end.x - 10.0 * s, pa.position.y + 58.0 * s), "NEW", UiUtil.MAGENTA, s, font, true, true)
	if not gear:
		var perk := WeaponRoster.headline(sel)
		if perk != "":
			var ps := Rect2(pa.position.x, pa.end.y - 34.0 * s, pa.size.x, 34.0 * s)
			c.draw_polygon(PackedVector2Array([ps.position, Vector2(ps.end.x, ps.position.y), ps.end, Vector2(ps.position.x, ps.end.y)]), PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.66), Color(0, 0, 0, 0.66)]))
			hud._text(c, font, Vector2(ps.position.x + 12.0 * s, ps.end.y - 9.0 * s), perk, HORIZONTAL_ALIGNMENT_LEFT, ps.size.x - 24.0 * s, UiUtil.fit_size(font, perk, ps.size.x - 24.0 * s, int(UiKit.T_BODY * s)), Color(UiUtil.MAGENTA.lerp(Color.WHITE, 0.25), 0.99), 1.0 * s)


## The right half of the small picture block: the weapon's name, then what the tapped part changes (PARTS) or what the loaded ammo does (AMMO), as rows of label, before > after and the change.
static func _picture_side(hud: Hud, c: Control, s: float, font: Font, mode: StringName, sel: StringName, tint: Color, r: Rect2, tab: StringName) -> void:
	var stt := Arsenal.st(mode)
	var fs := int(Hud.BODY_MIN * 1.1 * s)
	var nm := Arsenal._title(sel)
	hud._text(c, font, Vector2(r.position.x, r.position.y + 20.0 * s), nm, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, UiUtil.fit_size(font, nm, r.size.x, int(UiKit.T_BODY * s)), Color(1, 1, 1, 0.75))
	var y0 := r.position.y + 46.0 * s
	var row := 22.0 * s
	if tab == &"parts":
		var part: StringName = stt["part"]
		if part == &"" or not Attachments.PARTS.has(part):
			hud._text(c, font, Vector2(r.position.x, y0), "TAP A PART TO SEE", HORIZONTAL_ALIGNMENT_LEFT, r.size.x, int(UiKit.T_BODY * s), Color(UiUtil.CYAN, 0.95))
			hud._text(c, font, Vector2(r.position.x, y0 + row), "WHAT IT CHANGES", HORIZONTAL_ALIGNMENT_LEFT, r.size.x, int(UiKit.T_BODY * s), Color(UiUtil.CYAN, 0.95))
			return
		var fitted := Attachments.part_in(sel, Attachments.slot_of(part)) == part
		var head := ("%s  FITTED" if fitted else "%s") % String(Attachments.PARTS[part]["name"])
		hud._text(c, font, Vector2(r.position.x, y0), head, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, UiUtil.fit_size(font, head, r.size.x, int(UiKit.T_LABEL * s)), Color(UiUtil.CYAN, 0.99), 1.0 * s)
		var rows := part_deltas(sel, part)
		if rows.is_empty():
			var fx := Attachments.effect_text(part)
			hud._text(c, font, Vector2(r.position.x, y0 + row * 1.2), fx if fx != "" else "NO CHANGE TO THE NUMBERS", HORIZONTAL_ALIGNMENT_LEFT, r.size.x, fs, Color(1, 1, 1, 0.85))
			return
		var lw := r.size.x * 0.38
		var vw := r.size.x * 0.36
		for i in mini(rows.size(), 4):
			var d: Dictionary = rows[i]
			var y := y0 + row * 1.15 + float(i) * row
			var col := UiKit.GOOD if bool(d["good"]) else UiKit.BAD
			var lfs := mini(fs, UiUtil.fit_size(font, String(d["label"]), lw - 8.0 * s, fs))                  # wave 114 critic: "AIM SPREAD" ran into its numbers ("AIM SPREAD0.24 > 0.12"): the label shrinks to its column
			hud._text(c, font, Vector2(r.position.x, y), String(d["label"]), HORIZONTAL_ALIGNMENT_LEFT, lw, lfs, Color(1, 1, 1, 0.9))
			hud._text(c, font, Vector2(r.position.x + lw, y), "%s > %s" % [d["from"], d["to"]], HORIZONTAL_ALIGNMENT_LEFT, vw, fs, Color(1, 1, 1, 0.92))
			hud._text(c, font, Vector2(r.end.x - r.size.x * 0.26, y), "%+d%%" % int(d["pct"]), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x * 0.26, fs, Color(col, 0.99))
	elif tab == &"ammo":
		var sel_i := loaded_ammo()
		if not ammo_indices(sel).has(sel_i):
			sel_i = int(ammo_indices(sel)[0])
		var a: Dictionary = WeaponDefs.AMMO_TYPES[sel_i]
		var head2 := "LOADED  %s" % String(a["name"])
		hud._text(c, font, Vector2(r.position.x, y0), head2, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, UiUtil.fit_size(font, head2, r.size.x, int(UiKit.T_LABEL * s)), Color(UiUtil.GREEN, 0.99), 1.0 * s)
		var bits := ammo_effects(sel_i)
		for i in mini(bits.size(), 4):
			hud._text(c, font, Vector2(r.position.x, y0 + row * 1.15 + float(i) * row), bits[i], HORIZONTAL_ALIGNMENT_LEFT, r.size.x, fs, Color(1, 1, 1, 0.92))


## The lines of what an ammo type does ("DAMAGE +30%", "BURNS", "PIERCES COVER").
static func ammo_effects(i: int) -> Array[String]:
	var a: Dictionary = WeaponDefs.AMMO_TYPES[clampi(i, 0, WeaponDefs.AMMO_TYPES.size() - 1)]
	var out: Array[String] = []
	var dmg := float(a.get("dmg", 1.0))
	if absf(dmg - 1.0) > 0.01:
		out.append("DAMAGE %+d%%" % int(roundf((dmg - 1.0) * 100.0)))
	var rate := float(a.get("rate", 1.0))
	if absf(rate - 1.0) > 0.01:
		out.append("FIRE RATE %+d%%" % int(roundf((rate - 1.0) * 100.0)))
	if bool(a.get("pierce", false)):
		out.append("GOES THROUGH COVER")
	if a.has("burn"):
		out.append("BURNS  %d A SECOND" % int(a["burn"]))
	if a.has("zap"):
		out.append("SHOCKS AND CHAINS")
	if a.has("splash"):
		out.append("BLAST  %.1f M" % float(a["splash"]))
	if a.has("dissolve"):
		out.append("DISSOLVES TARGETS")
	if out.is_empty():
		out.append("PLAIN ROUNDS")
	return out


## What a part changes: [{label, from, to, pct, good}] for every number that moves by more than a third of a percent. A part that is not fitted: the weapon now against the weapon with the part in
## its slot (replacing what sits there). A fitted part: the weapon without it against the weapon now (what the part is doing for you).
static func part_deltas(sel: StringName, part: StringName) -> Array[Dictionary]:
	var slot := Attachments.slot_of(part)
	var fitted := Attachments.part_in(sel, slot) == part
	var before_d := Attachments.effective_with(sel, slot, &"") if fitted else Attachments.effective(sel)
	var after_d := Attachments.effective(sel) if fitted else Attachments.effective_with(sel, slot, part)
	var before := WeaponStats.card(sel, before_d)
	var after := WeaponStats.card(sel, after_d)
	var out: Array[Dictionary] = []
	var rows: Array = [
		["DAMAGE", "damage_shot", true, "%d"], ["RANGE", "range_eff", true, "%d M"], ["FIRE RATE", "rpm", true, "%d RPM"], ["AIM SPREAD", "spread_ads", false, "%.2f"],
		["HIP SPREAD", "spread_hip", false, "%.2f"], ["RECOIL", "recoil", false, "%.3f"], ["MAGAZINE", "mag", true, "%d"], ["RELOAD", "reload", false, "%.1f S"],
	]
	for r: Array in rows:
		var a := float(before[r[1]])
		var b := float(after[r[1]])
		if absf(b - a) <= maxf(absf(a), 0.0001) * 0.0033:
			continue
		var pct := (b - a) / maxf(absf(a), 0.0001) * 100.0
		var good: bool = (b > a) == bool(r[2])
		var fmt: String = r[3]
		out.append({"label": r[0], "from": fmt % (int(roundf(a)) if fmt.contains("%d") else a), "to": fmt % (int(roundf(b)) if fmt.contains("%d") else b), "pct": pct, "good": good})
	var za := float(after_d.get("zoom", 0.0))
	var zc := float(before_d.get("zoom", 0.0))
	if za > 0.0 and zc > 0.0 and absf(za - zc) > 0.5:
		out.append({"label": "ZOOM", "from": "x%.1f" % (60.0 / maxf(zc, 1.0)), "to": "x%.1f" % (60.0 / maxf(za, 1.0)), "pct": (zc / za - 1.0) * 100.0, "good": za < zc})
	return out


# ---------------------------------------------------------------------------------------------------------------------------------- STATS

static func _stats(hud: Hud, c: Control, s: float, font: Font, sel: StringName, tint: Color, content: Rect2, owned: bool) -> void:
	var card := WeaponStats.card(sel, Attachments.effective(sel) if owned else {})
	var cmp := LoadoutScreen.compare_id(sel)
	var cbars := {}
	if cmp != &"":
		cbars = WeaponStats.card(cmp, Attachments.effective(cmp))["bars"]
	var bar_w := content.size.x * 0.62
	var rows := WeaponStats.BARS7.size()
	var row_h := minf(34.0 * s, (content.size.y - 76.0 * s) / float(rows))
	var dt := hud.get_process_delta_time()
	if Arsenal._disp_id != sel:
		Arsenal._disp_id = sel
	var bars: Dictionary = card["bars"]
	for i in rows:
		var key: StringName = WeaponStats.BARS7[i]
		var target := float(bars[key])
		var shown := float(Arsenal._disp.get(key, target))
		shown = target if absf(shown - target) < 0.004 else lerpf(shown, target, clampf(dt * 12.0, 0.0, 1.0))
		Arsenal._disp[key] = shown
		var label := String(WeaponStats.BAR_NAMES[key])
		if bool(card["melee"]) and key == &"range":
			label = "REACH"
		_bar(hud, c, Rect2(content.position.x, content.position.y + float(i) * row_h, bar_w, row_h - 3.0 * s), s, font, label, shown, WeaponStats.bar_text(card, key), tint, float(cbars[key]) if (cmp != &"" and cbars.has(key)) else -1.0, target)
	var y := content.position.y + float(rows) * row_h + 4.0 * s
	var fs := int(Hud.BODY_MIN * 1.15 * s)
	if cmp != &"":
		var vs := "VS IN HAND  %s" % WeaponDefs.title(cmp)
		hud._text(c, font, Vector2(content.position.x, y + float(fs)), vs, HORIZONTAL_ALIGNMENT_LEFT, bar_w, UiUtil.fit_size(font, vs, bar_w, fs), Color(1, 1, 1, 0.78))
	else:
		hud._text(c, font, Vector2(content.position.x, y + float(fs)), "IN YOUR HAND" if sel == WeaponDefs.last_used else "ADD A WEAPON TO COMPARE", HORIZONTAL_ALIGNMENT_LEFT, bar_w, fs, Color(UiUtil.GREEN if sel == WeaponDefs.last_used else Color(1, 1, 1, 0.6), 0.85))
	var wl := WeaponStats.where(sel)
	if not owned and not wl.is_empty():
		var wtxt := "WHERE  " + wl[0]
		hud._text(c, font, Vector2(content.position.x, y + float(fs) * 2.3), wtxt, HORIZONTAL_ALIGNMENT_LEFT, bar_w, UiUtil.fit_size(font, wtxt, bar_w, fs), Color(UiUtil.CYAN, 0.97))
	elif owned:
		var info := "MAG %d  RELOAD %.1f S" % [int(card["mag"]), float(card["reload"])] if not bool(card["melee"]) else "%d DAMAGE A HIT" % int(roundf(float(card["damage"])))
		hud._text(c, font, Vector2(content.position.x, y + float(fs) * 2.3), info, HORIZONTAL_ALIGNMENT_LEFT, bar_w, UiUtil.fit_size(font, info, bar_w, fs), Color(1, 1, 1, 0.78))
		if not wl.is_empty():                                                          # an owned weapon still says where more of it come from (a crate, a shop, a reward)
			var wtxt2 := "WHERE  " + wl[0]
			hud._text(c, font, Vector2(content.position.x, y + float(fs) * 3.6), wtxt2, HORIZONTAL_ALIGNMENT_LEFT, bar_w, UiUtil.fit_size(font, wtxt2, bar_w, fs), Color(UiUtil.CYAN, 0.62))
	# the rings, to scale, beside a person
	var rr := Rect2(content.position.x + bar_w + 10.0 * s, content.position.y, content.size.x - bar_w - 10.0 * s, content.size.y)
	WeaponRings.draw(hud, c, rr, s, font, card, tint)


static func _bar(hud: Hud, c: Control, r: Rect2, s: float, font: Font, label: String, v: float, value: String, tint: Color, cmp: float, target: float) -> void:
	var lw := BAR_LAB * s
	var lsz := maxi(UiUtil.fit_size(font, label, lw - 4.0 * s, int(UiKit.T_CAP * s * 1.1)), int(Hud.BODY_MIN * s))
	hud._text(c, font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + lsz * 0.34), label, HORIZONTAL_ALIGNMENT_LEFT, lw, lsz, Color(1, 1, 1, 0.9 if value != "-" else 0.45))
	var vw := BAR_VAL * s
	var dw := BAR_DLT * s
	var tr := Rect2(r.position.x + lw, r.position.y + r.size.y * 0.5 - 7.0 * s, r.size.x - lw - vw - dw, 14.0 * s)
	if value == "-":                                                       # the weapon has nothing to show for this bar (a blade has no magazine): a quiet empty track, no compare
		c.draw_rect(tr, Color(1, 1, 1, 0.05))
		c.draw_rect(tr, Color(1, 1, 1, 0.12), false, 1.0 * s)
		hud._text(c, font, Vector2(tr.end.x + 6.0 * s, r.position.y + r.size.y * 0.5 + lsz * 0.34), "-", HORIZONTAL_ALIGNMENT_LEFT, vw - 6.0 * s, lsz, Color(1, 1, 1, 0.45))
		return
	c.draw_rect(tr, Color(1, 1, 1, 0.1))
	var col := Color(UiUtil.CYAN, 0.95).lerp(Color(UiUtil.AMBER, 0.97), clampf((v - 0.5) * 2.0, 0.0, 1.0))
	c.draw_rect(Rect2(tr.position, Vector2(tr.size.x * clampf(v, 0.0, 1.0), tr.size.y)), col)
	for i in range(1, 10):
		var x := tr.position.x + tr.size.x * float(i) / 10.0
		c.draw_line(Vector2(x, tr.position.y), Vector2(x, tr.end.y), Color(0, 0, 0, 0.32), 1.0 * s)
	c.draw_rect(tr, Color(1, 1, 1, 0.25), false, 1.0 * s)
	if cmp >= 0.0:
		var mx := tr.position.x + tr.size.x * clampf(cmp, 0.0, 1.0)
		c.draw_line(Vector2(mx, tr.position.y - 3.0 * s), Vector2(mx, tr.end.y + 3.0 * s), Color(1, 1, 1, 0.98), 2.5 * s)
	var vsz := maxi(UiUtil.fit_size(font, value, vw - 4.0 * s, int(UiKit.T_CAP * s * 1.1)), int(Hud.BODY_MIN * s))
	hud._text(c, font, Vector2(tr.end.x + 6.0 * s, r.position.y + r.size.y * 0.5 + vsz * 0.34), value, HORIZONTAL_ALIGNMENT_LEFT, vw - 6.0 * s, vsz, Color(1, 1, 1, 0.97))
	if cmp >= 0.0:
		var d := roundi((target - cmp) * 100.0)                                           # the number is the weapon's, not the glide's (a text that changes every frame is read as two overlapping texts)
		if d != 0:
			hud._text(c, font, Vector2(tr.end.x + vw + 2.0 * s, r.position.y + r.size.y * 0.5 + lsz * 0.34), ("+%d" % d) if d > 0 else ("%d" % d), HORIZONTAL_ALIGNMENT_LEFT, dw - 2.0 * s, int(Hud.BODY_MIN * s), Color(UiKit.GOOD if d > 0 else UiKit.BAD, 0.98))


# ---------------------------------------------------------------------------------------------------------------------------------- PARTS

static func _parts(hud: Hud, c: Control, s: float, font: Font, mode: StringName, sel: StringName, tint: Color, content: Rect2) -> void:
	var stt := Arsenal.st(mode)
	for b: Dictionary in hud.buttons:
		var id := String(b["id"])
		if id.begins_with("ars_slottab_"):
			UiKit.tab(hud, c, b["rect"], String(b["label"]), &"", bool(b["on"]), hud._hover == b["id"], s, font, tint)
		elif id == "ars_bench":
			UiKit.button(hud, c, b["rect"], "WORKBENCH", UiUtil.MAGENTA, 0, s, font, UiKit.T_LABEL)
		elif id.begins_with("ars_part_") and b.has("pid"):
			_part_card(hud, c, s, font, sel, b["pid"], b["rect"], bool(b["on"]), hud._hover == b["id"], tint)
	var slot := active_slot(mode, sel)
	var parts := Attachments.parts_for_weapon(slot, sel)
	if parts.is_empty():
		hud._text(c, font, Vector2(content.position.x, content.position.y + 100.0 * s), "THIS WEAPON TAKES NO PARTS HERE", HORIZONTAL_ALIGNMENT_LEFT, content.size.x, int(UiKit.T_BODY * s), Color(1, 1, 1, 0.7))
	# what is fitted, next to the workbench button
	var fitted: PackedStringArray = []
	for sl in Attachments.slots_for_weapon(sel):
		var pf := Attachments.part_in(sel, sl)
		if pf != &"" and Attachments.PARTS.has(pf) and Attachments.fits(pf, sel):
			fitted.append(String(Attachments.PARTS[pf]["name"]))
	var fx := content.position.x + 214.0 * s * (content.size.x / (650.0 * s))
	var fw := content.end.x - fx
	var by := content.position.y + (64.0 + 6.0 + 2.0 * (PART_H + 6.0)) * s
	var ft := "FITTED  " + (" / ".join(fitted) if not fitted.is_empty() else "NOTHING YET")
	var fsz := int(Hud.BODY_MIN * 1.15 * s)
	var lines := UiKit.wrap_text(hud, font, ft, fw, fsz, 2)
	for i in lines.size():
		hud._text(c, font, Vector2(fx, by + 24.0 * s + float(i) * float(fsz) * 1.3), lines[i], HORIZONTAL_ALIGNMENT_LEFT, fw, fsz, Color(UiUtil.AMBER, 0.95))
	var _u := stt


static func _part_card(hud: Hud, c: Control, s: float, font: Font, sel: StringName, part: StringName, r: Rect2, lit: bool, hot: bool, tint: Color) -> void:
	var d: Dictionary = Attachments.PARTS[part]
	var fitted := Attachments.part_in(sel, Attachments.slot_of(part)) == part
	var owned := Attachments.is_owned(part)
	UiKit.panel(c, r, s, UiUtil.MAGENTA if lit else (UiUtil.GREEN if fitted else tint), lit or hot or fitted, 8.0, lit)
	var nsz := int(Hud.BODY_MIN * 1.3 * s)
	var pw := r.size.x - 16.0 * s
	hud._text(c, font, Vector2(r.position.x + 10.0 * s, r.position.y + 25.0 * s), String(d["name"]), HORIZONTAL_ALIGNMENT_LEFT, pw, UiUtil.fit_size(font, String(d["name"]), pw, nsz), Color(1, 1, 1, 0.98))
	var fx := String(AttachmentPartsV3.FX.get(part, ""))
	if fx == "":
		fx = Attachments.effect_text(part)
	var fxl := UiKit.wrap_text(hud, font, fx, pw, int(Hud.BODY_MIN * s), 2)
	for i in fxl.size():
		hud._text(c, font, Vector2(r.position.x + 10.0 * s, r.position.y + 46.0 * s + float(i) * 17.0 * s), fxl[i], HORIZONTAL_ALIGNMENT_LEFT, pw, int(Hud.BODY_MIN * s), Color(tint.lerp(Color.WHITE, 0.5), 0.9))
	var prog := Game.progress as Progress
	var st := "FITTED" if fitted else ("OWNED" if owned else "%d" % (prog.part_price(part) if prog != null else Attachments.price(part)))
	var scol := UiUtil.GREEN if fitted else (Color(1, 1, 1, 0.7) if owned else UiUtil.AMBER)
	if owned and not fitted and MissionRewards.is_new(part):
		st = "NEW  TAP TO FIT"
		scol = UiUtil.MAGENTA.lerp(Color.WHITE, 0.3)
	var sx := r.position.x + 10.0 * s
	if not fitted and not owned:
		UiKit.glyph(c, &"coin", Vector2(sx + 7.0 * s, r.end.y - 14.0 * s), 7.0 * s, Color(UiUtil.AMBER, 0.95), s)
		sx += 20.0 * s
	hud._text(c, font, Vector2(sx, r.end.y - 8.0 * s), st, HORIZONTAL_ALIGNMENT_LEFT, pw - (sx - r.position.x - 10.0 * s), int(Hud.BODY_MIN * s), Color(scol, 0.98))


# ---------------------------------------------------------------------------------------------------------------------------------- AMMO

static func _ammo(hud: Hud, c: Control, s: float, font: Font, mode: StringName, sel: StringName, tint: Color, content: Rect2) -> void:
	var idx := ammo_indices(sel)
	var loaded := loaded_ammo()
	if not idx.has(loaded):
		loaded = int(idx[0])
	for j in mini(idx.size(), 9):
		var r := ammo_rect(content, s, j)
		var i := int(idx[j])
		var a: Dictionary = WeaponDefs.AMMO_TYPES[i]
		var on := i == loaded
		UiKit.panel(c, r, s, UiUtil.GREEN if on else tint, on or hud._hover == StringName("ars_ammo_%d" % i), 8.0, on)
		var pw := r.size.x - 16.0 * s
		hud._text(c, font, Vector2(r.position.x + 10.0 * s, r.position.y + 26.0 * s), String(a["name"]), HORIZONTAL_ALIGNMENT_LEFT, pw, UiUtil.fit_size(font, String(a["name"]), pw, int(Hud.BODY_MIN * 1.3 * s)), Color(1, 1, 1, 0.98))
		var fx := ammo_effects(i)
		hud._text(c, font, Vector2(r.position.x + 10.0 * s, r.position.y + 47.0 * s), fx[0], HORIZONTAL_ALIGNMENT_LEFT, pw, UiUtil.fit_size(font, fx[0], pw, int(Hud.BODY_MIN * s)), Color(tint.lerp(Color.WHITE, 0.5), 0.92))
		hud._text(c, font, Vector2(r.position.x + 10.0 * s, r.end.y - 8.0 * s), "LOADED" if on else "TAP TO LOAD", HORIZONTAL_ALIGNMENT_LEFT, pw, int(Hud.BODY_MIN * s), Color(UiUtil.GREEN if on else Color(1, 1, 1, 0.6), 0.95))
	var _u := mode


# ---------------------------------------------------------------------------------------------------------------------------------- gear (the catalogue's throwables and gadgets)

static func _gear_content(hud: Hud, c: Control, s: float, font: Font, sel: StringName, tint: Color, content: Rect2) -> void:
	var d := Gear.def(sel)
	var bar_w := content.size.x * 0.62
	var fs := int(Hud.BODY_MIN * 1.2 * s)
	var desc := String(d.get("desc", ""))
	var lines := UiKit.wrap_text(hud, font, desc, bar_w, fs, 3)
	var y := content.position.y + float(fs)
	for l in lines:
		hud._text(c, font, Vector2(content.position.x, y), l, HORIZONTAL_ALIGNMENT_LEFT, bar_w, fs, Color(1, 1, 1, 0.9))
		y += float(fs) * 1.3
	y += 6.0 * s
	for l2 in WeaponsScreen.gear_lines(sel):
		hud._text(c, font, Vector2(content.position.x, y + float(fs)), l2, HORIZONTAL_ALIGNMENT_LEFT, bar_w, UiUtil.fit_size(font, l2, bar_w, fs), Color(UiUtil.CYAN, 0.95))
		y += float(fs) * 1.4
		if y > content.end.y - float(fs):
			break
	var radius := float(d.get("radius", d.get("lure", 0.0)))
	var rr := Rect2(content.position.x + bar_w + 10.0 * s, content.position.y, content.size.x - bar_w - 10.0 * s, content.size.y)
	if radius > 0.0:
		WeaponRings.draw(hud, c, rr, s, font, {"melee": false, "blast": radius, "blast_core": 0.0, "blast_edge": 0.4, "utility": false, "well": 0.0, "spread_hip": 0.0, "spread_ads": 0.0, "range_max": 0.0, "range_eff": 0.0, "falloff": false}, tint)
	else:
		c.draw_rect(rr, Color(0.035, 0.05, 0.09, 0.9))
		c.draw_rect(rr, Color(tint, 0.35), false, 1.5 * s)
		var role := WeaponRoster.role(sel)
		if role != "":
			var rl := UiKit.wrap_text(hud, font, role.replace("  ", ". "), rr.size.x - 16.0 * s, int(Hud.BODY_MIN * s), 7)
			for i in rl.size():
				hud._text(c, font, Vector2(rr.position.x + 8.0 * s, rr.position.y + 24.0 * s + float(i) * 20.0 * s), rl[i], HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 16.0 * s, int(Hud.BODY_MIN * s), Color(1, 1, 1, 0.9))
