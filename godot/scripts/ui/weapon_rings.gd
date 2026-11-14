class_name WeaponRings
extends RefCounted
## The range and the blast of a weapon drawn TO SCALE beside a 1.8 m person (wave 114: "range and blast radius must be better and shown"). One panel, three pictures chosen by the kind of weapon:
##  - an explosive or area weapon: its BLAST as a dome on the ground next to the person (the radius and the full-damage core to scale, the colour fading out the way the BlastTable falls off, a thin
##    danger edge), the labels RADIUS / CORE;
##  - a gun: the GROUP at 20 m (the person at 20 m drawn at the true size with the circle the shots land in when fired from the hip and when aimed, both to scale) and the RANGE ruler (0 m to the
##    maximum range, the full-damage stretch green, the fall-off stretch fading to red, round tick labels) under it;
##  - a melee weapon: the REACH arc around the person.
## Pure drawing; the numbers come from WeaponStats.card (the same dictionary the bars read). Text goes through Hud._text so the layout scan sees it.

const PERSON_H := 1.8


## A person silhouette (head, neck, shoulders, torso, arms, legs) standing with its feet at `feet`, `h` px tall, in `col`.
static func person(c: CanvasItem, feet: Vector2, h: float, col: Color) -> void:
	c.draw_circle(feet + Vector2(0.0, -0.925 * h), 0.068 * h, col)
	c.draw_colored_polygon(PackedVector2Array([feet + Vector2(-0.14 * h, -0.84 * h), feet + Vector2(0.14 * h, -0.84 * h), feet + Vector2(0.105 * h, -0.5 * h), feet + Vector2(-0.105 * h, -0.5 * h)]), col)
	c.draw_colored_polygon(PackedVector2Array([feet + Vector2(-0.105 * h, -0.5 * h), feet + Vector2(-0.012 * h, -0.5 * h), feet + Vector2(-0.03 * h, 0.0), feet + Vector2(-0.10 * h, 0.0)]), col)
	c.draw_colored_polygon(PackedVector2Array([feet + Vector2(0.012 * h, -0.5 * h), feet + Vector2(0.105 * h, -0.5 * h), feet + Vector2(0.10 * h, 0.0), feet + Vector2(0.03 * h, 0.0)]), col)
	var aw := maxf(1.5, 0.045 * h)
	c.draw_line(feet + Vector2(-0.15 * h, -0.82 * h), feet + Vector2(-0.19 * h, -0.5 * h), col, aw)
	c.draw_line(feet + Vector2(0.15 * h, -0.82 * h), feet + Vector2(0.19 * h, -0.5 * h), col, aw)


## A round number at or above `v` for the end of a ruler (25, 50, 100, 150, 250, 400, 600 ...).
static func nice_max(v: float) -> float:
	for m: float in [10.0, 25.0, 50.0, 100.0, 150.0, 250.0, 400.0, 600.0, 1000.0]:
		if v <= m:
			return m
	return ceilf(v / 500.0) * 500.0


## The whole panel inside `r` (the caller draws its plate): picks the picture by the card. `font` is the menu font.
static func draw(hud: Hud, c: Control, r: Rect2, s: float, font: Font, card: Dictionary, tint: Color) -> void:
	c.draw_rect(r, Color(0.035, 0.05, 0.09, 0.96))
	c.draw_rect(r, Color(tint, 0.45), false, 1.5 * s)
	var cap_h := 24.0 * s
	if bool(card["melee"]):
		_melee(hud, c, Rect2(r.position, Vector2(r.size.x, r.size.y)), s, font, card, tint)
	elif float(card["blast"]) > 0.0:
		_blast(hud, c, Rect2(r.position, Vector2(r.size.x, r.size.y)), s, font, card, tint)
	else:
		var top := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.58))
		_group(hud, c, top, s, font, card, tint)
		_ruler(hud, c, Rect2(r.position.x + 10.0 * s, top.end.y + 2.0 * s, r.size.x - 20.0 * s, r.size.y - top.size.y - 6.0 * s), s, font, card)
	var _unused := cap_h


# ---------------------------------------------------------------------------------------------------------------------------------- blast dome

static func _blast(hud: Hud, c: Control, r: Rect2, s: float, font: Font, card: Dictionary, tint: Color) -> void:
	var rad := maxf(float(card["blast"]), 0.5)
	var core := clampf(float(card.get("blast_core", 0.0)), 0.0, rad)
	var edge := clampf(float(card.get("blast_edge", 0.4)), 0.0, 1.0)
	var utility := bool(card.get("utility", false))
	var col := UiUtil.CYAN if utility else Color(1.0, 0.5, 0.2)
	var ground := r.position.y + r.size.y * 0.66
	var left := r.position.x + 18.0 * s
	var person_h_px := 0.0
	# one pixels-per-metre for everything: the dome has to fit the width (the person stands left of it) and the height
	var avail_w := r.size.x - 36.0 * s
	var ppm := minf((avail_w - 26.0 * s) / (2.0 * rad), (ground - r.position.y - 30.0 * s) / rad)
	ppm = clampf(ppm, 0.6, 60.0)
	person_h_px = PERSON_H * ppm
	var cx := r.position.x + r.size.x * 0.5 + 12.0 * s
	cx = clampf(cx, left + 26.0 * s + rad * ppm, r.end.x - 14.0 * s - rad * ppm)
	# ground
	c.draw_line(Vector2(r.position.x + 8.0 * s, ground), Vector2(r.end.x - 8.0 * s, ground), Color(1, 1, 1, 0.35), 2.0 * s)
	# the dome: concentric half discs, the colour thins out the way the damage does (full in the core, `edge` at the radius)
	var steps := 8
	for i in range(steps, 0, -1):
		var f := float(i) / float(steps)
		var share := 1.0 if f * rad <= core else lerpf(1.0, edge, clampf((f * rad - core) / maxf(rad - core, 0.01), 0.0, 1.0))
		_half_disc(c, Vector2(cx, ground), rad * f * ppm, Color(col, 0.07 + 0.22 * share * (1.0 - f * 0.55)))
	c.draw_arc(Vector2(cx, ground), rad * ppm, PI, TAU, 40, Color(col, 0.98), 2.5 * s)
	if core > 0.3:
		c.draw_arc(Vector2(cx, ground), core * ppm, PI, TAU, 28, Color(1.0, 0.95, 0.75, 0.95), 1.8 * s)
	# danger edge: a dashed ground line past the radius
	var gx := cx + rad * ppm
	c.draw_line(Vector2(gx, ground - 5.0 * s), Vector2(gx, ground + 5.0 * s), Color(UiUtil.RED, 0.95), 2.5 * s)
	# a person beside it, at the true size, with his 1.8 m bracket
	var px := left + 8.0 * s
	person(c, Vector2(px, ground), maxf(person_h_px, 5.0), Color(1, 1, 1, 0.92))
	if person_h_px >= 14.0 * s:
		c.draw_line(Vector2(px + 0.3 * person_h_px, ground), Vector2(px + 0.3 * person_h_px, ground - person_h_px), Color(1, 1, 1, 0.5), 1.0 * s)
	var cap := ("EFFECT  %.1f M" % rad) if utility else ("RADIUS  %.1f M" % rad)
	hud._text(c, font, Vector2(r.position.x + 8.0 * s, r.position.y + 22.0 * s), cap, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16.0 * s, UiUtil.fit_size(font, cap, r.size.x - 16.0 * s, int(UiKit.T_BODY * s)), Color(col.lerp(Color.WHITE, 0.4), 0.98))
	var cap2 := "PERSON 1.8 M  TO SCALE"
	if core > 0.3 and not utility:
		cap2 = "FULL DAMAGE TO %.1f M" % core
	hud._text(c, font, Vector2(r.position.x + 8.0 * s, r.end.y - 10.0 * s), cap2, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16.0 * s, UiUtil.fit_size(font, cap2, r.size.x - 16.0 * s, int(Hud.BODY_MIN * s)), Color(1, 1, 1, 0.82))
	if float(card["well"]) > 0.0:
		c.draw_arc(Vector2(cx, ground), float(card["well"]) * ppm, PI, TAU, 36, Color(UiUtil.MAGENTA, 0.9), 1.6 * s)


static func _half_disc(c: CanvasItem, center: Vector2, rad: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := PI + PI * float(i) / 24.0
		pts.append(center + Vector2(cos(a), sin(a)) * rad)
	c.draw_colored_polygon(pts, col)


# ---------------------------------------------------------------------------------------------------------------------------------- the group of a gun at 20 m

static func _group(hud: Hud, c: Control, r: Rect2, s: float, font: Font, card: Dictionary, tint: Color) -> void:
	var hip_m := tan(deg_to_rad(float(card["spread_hip"]))) * 20.0
	var ads_m := tan(deg_to_rad(float(card["spread_ads"]))) * 20.0
	var ground := r.end.y - 26.0 * s
	var ppm := minf((ground - r.position.y - 34.0 * s) / PERSON_H, (r.size.x * 0.3) / maxf(hip_m, 0.4))
	ppm = clampf(ppm, 6.0, 80.0)
	var px := r.position.x + r.size.x * 0.68
	var h := PERSON_H * ppm
	c.draw_line(Vector2(r.position.x + 8.0 * s, ground), Vector2(r.end.x - 8.0 * s, ground), Color(1, 1, 1, 0.3), 1.5 * s)
	var centre := Vector2(px, ground - h * 0.62)                                      # the aim point: the middle of the chest
	c.draw_circle(centre, hip_m * ppm, Color(UiUtil.AMBER, 0.14))
	c.draw_arc(centre, hip_m * ppm, 0.0, TAU, 40, Color(UiUtil.AMBER, 0.95), 2.0 * s)
	person(c, Vector2(px, ground), h, Color(1, 1, 1, 0.9))
	c.draw_circle(centre, ads_m * ppm, Color(UiUtil.CYAN, 0.16))
	c.draw_arc(centre, ads_m * ppm, 0.0, TAU, 32, Color(UiUtil.CYAN, 0.98), 2.0 * s)
	c.draw_line(centre + Vector2(-5.0 * s, 0.0), centre + Vector2(5.0 * s, 0.0), Color(0, 0, 0, 0.7), 1.0 * s)
	var cap := "SHOTS AT 20 M"
	hud._text(c, font, Vector2(r.position.x + 8.0 * s, r.position.y + 22.0 * s), cap, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16.0 * s, int(UiKit.T_BODY * s), Color(1, 1, 1, 0.9))
	var hip := "HIP  %.1f M" % (hip_m * 2.0)
	var ads := "AIMED  %.1f M" % (ads_m * 2.0)
	hud._text(c, font, Vector2(r.position.x + 8.0 * s, ground - 6.0 * s - Hud.BODY_MIN * s * 1.2), hip, HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.4, int(Hud.BODY_MIN * s), Color(UiUtil.AMBER, 0.98))
	hud._text(c, font, Vector2(r.position.x + 8.0 * s, ground - 6.0 * s), ads, HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.4, int(Hud.BODY_MIN * s), Color(UiUtil.CYAN, 0.98))
	var _u := tint


# ---------------------------------------------------------------------------------------------------------------------------------- the range ruler

static func _ruler(hud: Hud, c: Control, r: Rect2, s: float, font: Font, card: Dictionary) -> void:
	var mx := float(card["range_max"])
	var eff := float(card["range_eff"])
	var end_m := nice_max(mx)
	var bar := Rect2(r.position.x, r.position.y + 6.0 * s, r.size.x, 14.0 * s)
	c.draw_rect(bar, Color(1, 1, 1, 0.1))
	var full_w := bar.size.x * clampf(eff / end_m, 0.0, 1.0)
	c.draw_rect(Rect2(bar.position, Vector2(full_w, bar.size.y)), Color(UiUtil.GREEN, 0.9))
	var max_w := bar.size.x * clampf(mx / end_m, 0.0, 1.0)
	if bool(card["falloff"]) and max_w > full_w:
		var seg := 12
		for i in seg:
			var t := float(i) / float(seg)
			c.draw_rect(Rect2(bar.position.x + full_w + (max_w - full_w) * t, bar.position.y, (max_w - full_w) / float(seg) + 1.0, bar.size.y), Color(UiUtil.GREEN, 0.9).lerp(Color(UiUtil.RED, 0.85), t))
	for k in range(0, 5):                                                          # ticks at every quarter of the ruler, a person at the start
		var x := bar.position.x + bar.size.x * float(k) / 4.0
		c.draw_line(Vector2(x, bar.position.y + bar.size.y), Vector2(x, bar.position.y + bar.size.y + 5.0 * s), Color(1, 1, 1, 0.55), 1.5 * s)
	c.draw_rect(bar, Color(1, 1, 1, 0.3), false, 1.0 * s)
	var fs := int(Hud.BODY_MIN * s)
	var y := bar.end.y + 5.0 * s + float(fs) * 0.95
	hud._text(c, font, Vector2(r.position.x, y), "0", HORIZONTAL_ALIGNMENT_LEFT, 30.0 * s, fs, Color(1, 1, 1, 0.7))
	hud._text(c, font, Vector2(r.position.x + r.size.x * 0.5 - 40.0 * s, y), "%d M" % int(end_m * 0.5), HORIZONTAL_ALIGNMENT_CENTER, 80.0 * s, fs, Color(1, 1, 1, 0.7))
	hud._text(c, font, Vector2(r.end.x - 80.0 * s, y), "%d M" % int(end_m), HORIZONTAL_ALIGNMENT_RIGHT, 80.0 * s, fs, Color(1, 1, 1, 0.7))
	var cap := "FULL DAMAGE TO %d M" % int(roundf(eff)) if bool(card["falloff"]) else "FULL DAMAGE TO %d M" % int(roundf(mx))
	hud._text(c, font, Vector2(r.position.x, y + float(fs) * 1.25), cap, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, UiUtil.fit_size(font, cap, r.size.x, fs), Color(UiUtil.GREEN, 0.98))


# ---------------------------------------------------------------------------------------------------------------------------------- melee reach

static func _melee(hud: Hud, c: Control, r: Rect2, s: float, font: Font, card: Dictionary, tint: Color) -> void:
	var reach := maxf(float(card["reach"]), 0.5)
	var top := r.position.y + 54.0 * s
	var ground := r.end.y - 14.0 * s
	var ppm := minf((r.size.x * 0.66 - 12.0 * s) / reach, (ground - top) / maxf(PERSON_H * 0.62 + reach * 0.87, 1.0))
	ppm = clampf(ppm, 5.0, 60.0)
	var px := r.position.x + r.size.x * 0.2
	c.draw_line(Vector2(r.position.x + 8.0 * s, ground), Vector2(r.end.x - 8.0 * s, ground), Color(1, 1, 1, 0.3), 1.5 * s)
	var centre := Vector2(px, ground - PERSON_H * ppm * 0.62)
	var pts := PackedVector2Array([centre])
	for i in 17:
		var a := deg_to_rad(-60.0 + 120.0 * float(i) / 16.0)
		pts.append(centre + Vector2(cos(a), sin(a)) * reach * ppm)
	c.draw_colored_polygon(pts, Color(tint, 0.2))
	c.draw_arc(centre, reach * ppm, deg_to_rad(-60.0), deg_to_rad(60.0), 28, Color(tint.lerp(Color.WHITE, 0.3), 0.98), 2.5 * s)
	person(c, Vector2(px, ground), PERSON_H * ppm, Color(1, 1, 1, 0.92))
	hud._text(c, font, Vector2(r.position.x + 8.0 * s, r.position.y + 22.0 * s), "REACH  %.1f M" % reach, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16.0 * s, int(UiKit.T_BODY * s), Color(1, 1, 1, 0.92))
	var cap := "HITS EVERYONE IN THE ARC"
	hud._text(c, font, Vector2(r.position.x + 8.0 * s, r.position.y + 42.0 * s), cap, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16.0 * s, UiUtil.fit_size(font, cap, r.size.x - 16.0 * s, int(Hud.BODY_MIN * s)), Color(1, 1, 1, 0.8))
