class_name PhotoScreen
extends RefCounted
## The PHOTO MODE controls (Hud draws them while `Hud.photo.active`, over the live world, with no dim): a row of 64 px buttons along the bottom (EXIT, SHOT, SHARE, HIDE UI, HIDE HERO,
## FILTER, POSE, ORBIT / PAN) and four sliders above it (FOV, BLUR, TIME, ZOOM). With the UI hidden only a SHOW UI button stays in the top corner. Pure layout and drawing: the rules
## live in PhotoMode. Button ids start with `photo_`; the sliders (`photo_fov`, `photo_dof`, `photo_time`, `photo_zoom`) are dragged through Hud.slide().

const BTN_H := 64.0
const ROW_BTN := 648.0
const ROW_SLIDER := 568.0
const GAP := 8.0
const SLIDERS: Array[StringName] = [&"photo_fov", &"photo_dof", &"photo_time", &"photo_zoom"]


static func is_slider(id: StringName) -> bool:
	return SLIDERS.has(id)


static func label(ph: PhotoMode, id: StringName) -> String:
	match id:
		&"photo_fov": return "FOV  %d" % roundi(ph.fov)
		&"photo_dof": return "BLUR  %d" % roundi(ph.dof * 100.0)
		&"photo_time": return "TIME  %s" % ph.hour_text()
		&"photo_zoom": return "ZOOM  %.1f" % ph.dist
	return ""


static func layout(hud: Hud, ph: PhotoMode, vp: Vector2, s: float) -> void:
	var ins := UiUtil.insets(vp)
	var left := maxf(ins.x, 12.0 * s)
	var right := vp.x - maxf(ins.y, 12.0 * s)
	if ph.hide_ui:
		hud._add(&"photo_ui", Rect2(right - 150.0 * s, 6.0 * s, 150.0 * s, BTN_H * s), "SHOW UI", false)
		return
	var n := 8
	var w := minf(150.0 * s, (right - left - GAP * s * (n - 1)) / n)
	var x0 := (left + right) * 0.5 - (w * n + GAP * s * (n - 1)) * 0.5
	var ids: Array = [
		[&"photo_exit", "EXIT", false],
		[&"photo_shot", "SHOT", true],
		[&"photo_share", "SHARE", false],
		[&"photo_ui", "HIDE UI", false],
		[&"photo_hero", "SHOW HERO" if ph.hide_hero else "HIDE HERO", ph.hide_hero],
		[&"photo_filter", ph.filter_name(), ph.filter_i != 0],
		[&"photo_pose", ph.pose_name(), ph.pose_i >= 0],
		[&"photo_mode", "PAN" if ph.pan_mode else "ORBIT", ph.pan_mode],
	]
	for i in n:
		var d: Array = ids[i]
		hud._add(d[0], Rect2(x0 + i * (w + GAP * s), ROW_BTN * s, w, BTN_H * s), d[1], d[2])
	var sw := minf(290.0 * s, (right - left - GAP * 1.5 * s * 3.0) / 4.0)
	var sx0 := (left + right) * 0.5 - (sw * 4.0 + GAP * 1.5 * s * 3.0) * 0.5
	for i in SLIDERS.size():
		hud._add(SLIDERS[i], Rect2(sx0 + i * (sw + GAP * 1.5 * s), ROW_SLIDER * s, sw, BTN_H * s), label(ph, SLIDERS[i]), true)


## Title, status line and the shutter flash (the buttons are drawn by the Hud's own button pass).
static func draw(hud: Hud, ph: PhotoMode, c: Control, vp: Vector2, s: float, font: Font) -> void:
	if ph.flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, vp), Color(1, 1, 1, 0.8 * ph.flash))
	if ph.hide_ui:
		return
	hud._text(c, font, Vector2(0.0, 40.0 * s), "PHOTO MODE", HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(UiUtil.TEXT_MIN * s), Color(1, 1, 1, 0.95), 2.0 * s)
	if ph.status_left > 0.0 and ph.status != "":
		hud._rect(c, Rect2(vp.x * 0.5 - 220.0 * s, 56.0 * s, 440.0 * s, 40.0 * s), Color(0.0, 0.03, 0.05, 0.62))
		hud._text(c, font, Vector2(0.0, 84.0 * s), ph.status, HORIZONTAL_ALIGNMENT_CENTER, vp.x, int(22.0 * s), Color(UiUtil.CYAN, 0.97), 1.0 * s)
