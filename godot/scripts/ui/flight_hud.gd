class_name FlightHud
extends RefCounted
## The flight instruments (wave 106), drawn by Hud._draw_hud_body over the world while the hero flies a plane or a helicopter: a small ARTIFICIAL HORIZON (the sky and the ground tilt with the bank, a
## fixed aircraft mark, the pitch ladder), the HEADING, the ALTITUDE above the ground with the VERTICAL SPEED (an arrow), the SPEED in knots-free plain km/h on the speedometer plate (Hud keeps it), a
## STALL warning and, on a plane within reach of the runway, the LANDING GUIDE: a box with a diamond that must sit on the centre cross (above the cross = too high, left of it = the runway is to the left),
## the runway number and the distance. Everything sits on the left edge, clear of the sticks and the buttons, and nothing is drawn on foot or in a car.
## `rows(veh)` returns the words of the instruments (the tests read them); `draw(c, font, vp, s, ins, veh)` paints them on the HUD's Control with direct draw calls.

const SKY := Color(0.28, 0.5, 0.82, 0.9)
const GROUND := Color(0.42, 0.3, 0.18, 0.9)
const CYAN := Color(0.35, 0.95, 1.0, 0.97)
const AMBER := Color(1.0, 0.75, 0.25, 0.97)
const GREEN := Color(0.4, 1.0, 0.5, 0.97)
const RED := Color(1.0, 0.3, 0.25, 0.97)
const PLATE := Color(0.0, 0.03, 0.05, 0.62)
const PITCH_PX := 150.0               ## horizon pixels per radian of pitch (at s = 1)


## The numbers of the instruments as words: ALT, V/S, HDG, SPEED (km/h) and the guide's line, for the HUD and the tests. Empty for anything that does not fly.
static func rows(veh: Object) -> Array[String]:
	var out: Array[String] = []
	if not (veh is Vehicle) or (veh as Vehicle).craft == null or not ((veh as Vehicle).cls == &"heli" or (veh as Vehicle).cls == &"plane"):
		return out
	var d := AircraftFlight.info(veh as Vehicle)
	out.append("ALT %d M" % roundi(float(d["agl"])))
	out.append("V/S %+d" % roundi(float(d["vspeed"])))
	out.append("HDG %03d" % compass(float(d["heading"])))
	out.append("SPEED %d KM/H" % roundi(float(d["speed"]) * 3.6))
	var g: Dictionary = d["guide"]
	if bool(g.get("on", false)):
		out.append("RWY %s  %d M" % [g["rwy"], roundi(float(g["dist"]))])
	if bool(d["stalled"]):
		out.append("STALL")
	return out


## A heading (Node3D yaw: 0 = north, + = turning left) as compass degrees 0..359.
static func compass(heading: float) -> int:
	return int(fposmod(roundf(-rad_to_deg(heading)), 360.0))


static var labels: Array[String] = []  ## w129-airdraws: the words of the labels painted in the last frame (tests read what was really drawn)
static var shown_frame := -100        ## wave 119: the last frame the instruments were drawn (the radio plate keeps to two short lines while they show)
static var flight_fix := true          ## w119-hud5: false = the old layout (the horizon at 0.47 of the height whatever stands above it)


## True while the instruments are on screen (drawn within the last few frames).
static func showing() -> bool:
	return Engine.get_process_frames() - shown_frame < 4


## The centre of the horizon disc: under the radio plate when a line shows (w119-hud5: the ORACLE card ran into the altimeter at 2400x1080), never lower than the speed plate allows.
static func ball_centre(vp: Vector2, s: float, ins: Vector2) -> Vector2:
	var r := 74.0 * s
	var y := vp.y * 0.47
	if flight_fix and is_instance_valid(Game.story) and Game.story.get(&"view") != null:
		var sub: Rect2 = (Game.story.get(&"view") as Object).call(&"subtitle_rect", vp)
		if sub.has_area():
			y = minf(maxf(y, sub.end.y + 8.0 * s + r + 4.0 * s), vp.y * 0.69 - r - 36.0 * s)
	return Vector2(ins.x + 26.0 * s + r + 4.0 * s, y)


## The rect the horizon, its heading line and the altitude labels take (for layout tests).
static func instruments_rect(vp: Vector2, s: float, ins: Vector2) -> Rect2:
	var r := 74.0 * s
	var c := ball_centre(vp, s, ins)
	return Rect2(c.x - r - 4.0 * s, c.y - r - 4.0 * s, r * 2.0 + 14.0 * s + 150.0 * s, r * 2.0 + 44.0 * s)


static var badge_fix := OS.get_environment("W125C_OLD") != "1"


## w125-critic: the rect of the helicopter's name badge over the horizon (HeliRoster.draw_badge), Rect2() when it is not drawn. The badge sits in the gap between the
## radio plate and the horizon: while a radio line shows there is no room for it (the plate covered it), so it steps aside until the line is gone.
static func badge_rect(vp: Vector2, s: float, ins: Vector2, v: Object) -> Rect2:
	if not (v is Vehicle) or not HeliRoster.is_heli((v as Vehicle).kind):
		return Rect2()
	var r := 74.0 * s
	var centre := ball_centre(vp, s, ins)
	var font := UiUtil.font()
	var fs := int(18.0 * s)
	var w := 64.0 * s + font.get_string_size(VehicleSpecs.name_of((v as Vehicle).kind), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 18.0 * s
	var h := 38.0 * s
	var rect := Rect2(centre.x - w * 0.5, centre.y - r - 10.0 * s - h, w, h)
	if badge_fix and is_instance_valid(Game.story) and Game.story.get(&"view") != null:
		var sub: Rect2 = (Game.story.get(&"view") as Object).call(&"subtitle_rect", vp)
		if sub.has_area() and sub.grow(5.0 * s).intersects(rect):
			return Rect2()
	return rect


static func visible_for(veh: Object) -> bool:
	return veh is Vehicle and (veh as Vehicle).craft != null and ((veh as Vehicle).cls == &"heli" or (veh as Vehicle).cls == &"plane")


static var enabled := true             ## probes (dev_w129_airscan): false leaves the instruments out to read what they cost


static func draw(c: Control, font: Font, vp: Vector2, s: float, ins: Vector2, veh: Object) -> void:
	if not visible_for(veh) or not enabled:
		return
	var v := veh as Vehicle
	var d := AircraftFlight.info(v)
	var r := 74.0 * s
	shown_frame = Engine.get_process_frames()
	labels.clear()
	var centre := ball_centre(vp, s, ins)
	_horizon(c, centre, r, float(d["pitch"]), float(d["roll"]), s)
	# heading under the horizon, altitude and vertical speed beside it
	var gauges := AirDraws.cockpit_on()                        # w129-airdraws: the cockpit's ALT and HDG gauges show these: not twice
	if not gauges:
		_label(c, font, Vector2(centre.x - 50.0 * s, centre.y + r + 8.0 * s), Vector2(100.0 * s, 28.0 * s), "HDG %03d" % compass(float(d["heading"])), CYAN, s)
	var ax := centre.x + r + 14.0 * s
	var agl := float(d["agl"])
	if not gauges:
		_label(c, font, Vector2(ax, centre.y - r), Vector2(150.0 * s, 40.0 * s), "%d M" % roundi(agl), CYAN if agl > 25.0 else AMBER, s, 26)
	var vs := float(d["vspeed"])
	_vs_arrow(c, Vector2(ax + 22.0 * s, centre.y - r + 74.0 * s), vs, s)
	_label(c, font, Vector2(ax + 46.0 * s, centre.y - r + 56.0 * s), Vector2(110.0 * s, 28.0 * s), "%+d" % roundi(vs), (AMBER if vs < -6.0 else CYAN), s)
	if HeliRoster.is_heli(v.kind) and badge_rect(vp, s, ins, v).has_area():
		_flush(c)          # wave 125: which of the 23 helicopters this is (its icon and name over the horizon)
		HeliRoster.draw_badge(c, font, Vector2(centre.x, centre.y - r - 10.0 * s), s, v.kind)
	if bool(d["plane"]):
		_throttle(c, Vector2(centre.x - r - 12.0 * s, centre.y + r), r * 2.0, float(d["throttle"]), s)
	# the stall warning: centre top, flashing
	if bool(d["stalled"]):
		var on := int(Time.get_ticks_msec() / 220) % 2 == 0
		if on:
			_label(c, font, Vector2(vp.x * 0.5 - 110.0 * s, vp.y * 0.27), Vector2(220.0 * s, 44.0 * s), "STALL", RED, s, 30)
	# the landing guide
	var g: Dictionary = d["guide"]
	if bool(g.get("on", false)) and bool(d["plane"]):
		_guide(c, font, vp, ins, s, g, bool(d["airborne"]))
	_flush(c)
	AirArms.draw_hud(c, v, s)                                    # w126-air: the missile seeker box on the target, the bomb's landing ring


## The artificial horizon: a disc split at the horizon line, which tilts opposite to the bank and slides with the pitch; a fixed aircraft mark and a short pitch ladder on top.
static func _horizon(c: Control, centre: Vector2, r: float, pitch: float, roll: float, s: float) -> void:
	_circle(c, centre, r + 4.0 * s, PLATE)
	_circle(c, centre, r, SKY)
	# the model's roll is + = right wing up (Node3D.rotation.z): the horizon turns the other way round
	var along := Vector2(cos(roll), sin(roll))                 # the horizon line's direction on screen
	var down := Vector2(-sin(roll), cos(roll))                 # towards the ground
	var hc := centre + down * (pitch * PITCH_PX * s)           # nose up: the horizon slides down the disc
	var poly := PackedVector2Array()
	for i in 48:
		var a := TAU * float(i) / 48.0
		poly.append(centre + Vector2(cos(a), sin(a)) * r)
	var ground := _clip_half(poly, hc, down)
	if ground.size() >= 3:
		_poly(c, ground, GROUND)
	var half := r * 1.2
	var p0 := hc - along * half
	var p1 := hc + along * half
	var inside0 := (p0 - centre).length() < r
	if inside0 or (p1 - centre).length() < r or absf((hc - centre).dot(down)) < r:
		var seg := _clip_segment(p0, p1, centre, r)
		if seg.size() == 2:
			_line(c, seg[0], seg[1], Color(1, 1, 1, 0.95), 2.5 * s)
	for k in [-2, -1, 1, 2]:                                   # a ladder rung every 10 degrees
		var cen := hc + down * (-float(k) * 0.1745 * PITCH_PX * s)
		var wdt := (14.0 if absi(k) == 1 else 22.0) * s
		if (cen - centre).length() < r - 12.0 * s:
			_line(c, cen - along * wdt, cen + along * wdt, Color(1, 1, 1, 0.55), 1.5 * s)
	_arc(c, centre, r, 0.0, TAU, 40, Color(CYAN, 0.9), 3.0 * s)
	var w := r * 0.5                                           # the aircraft mark (fixed): a small W
	_line(c, centre + Vector2(-w, 0.0), centre + Vector2(-w * 0.35, 0.0), AMBER, 4.0 * s)
	_line(c, centre + Vector2(w, 0.0), centre + Vector2(w * 0.35, 0.0), AMBER, 4.0 * s)
	_line(c, centre + Vector2(-w * 0.35, 0.0), centre + Vector2(0.0, 9.0 * s), AMBER, 4.0 * s)
	_line(c, centre + Vector2(w * 0.35, 0.0), centre + Vector2(0.0, 9.0 * s), AMBER, 4.0 * s)
	_circle(c, centre, 3.0 * s, AMBER)


## The part of a polygon on the `normal` side of the line through `at` (Sutherland-Hodgman against one half plane).
static func _clip_half(poly: PackedVector2Array, at: Vector2, normal: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var da := (a - at).dot(normal)
		var db := (b - at).dot(normal)
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


## The part of the segment a-b inside the circle (centre, r): [] when it misses.
static func _clip_segment(a: Vector2, b: Vector2, centre: Vector2, r: float) -> PackedVector2Array:
	var d := b - a
	var f := a - centre
	var qa := d.dot(d)
	var qb := 2.0 * f.dot(d)
	var qc := f.dot(f) - r * r
	var disc := qb * qb - 4.0 * qa * qc
	if disc <= 0.0 or qa < 1.0e-6:
		return PackedVector2Array()
	var sq := sqrt(disc)
	var t0 := clampf((-qb - sq) / (2.0 * qa), 0.0, 1.0)
	var t1 := clampf((-qb + sq) / (2.0 * qa), 0.0, 1.0)
	return PackedVector2Array([a + d * t0, a + d * t1])


static func _label(c: Control, font: Font, pos: Vector2, size: Vector2, text: String, col: Color, s: float, fs := 20) -> void:
	labels.append(text)
	_rect(c, Rect2(pos, size), PLATE)
	var fsz := int(float(fs) * s)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	while tw > size.x - 8.0 * s and fsz > 10:
		fsz -= 1
		tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	_str(c, font, Vector2(pos.x + (size.x - tw) * 0.5, pos.y + size.y * 0.5 + float(fsz) * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, col)


## An arrow for the vertical speed: up for a climb, down for a sink, longer the faster (capped), a flat bar when level.
static func _vs_arrow(c: Control, at: Vector2, vs: float, s: float) -> void:
	var k := clampf(vs / 12.0, -1.0, 1.0)
	var col := CYAN if vs >= -6.0 else AMBER
	if absf(vs) < 0.8:
		_line(c, at + Vector2(-12.0, 0.0) * s, at + Vector2(12.0, 0.0) * s, Color(col, 0.7), 3.0 * s)
		return
	var tip := at + Vector2(0.0, -k * 34.0 * s)
	var wing := 12.0 * s * (1.0 if k > 0.0 else -1.0)                  # the head's wings trail back from the tip
	_line(c, at, tip, col, 4.0 * s)
	_line(c, tip, tip + Vector2(-9.0 * s, wing), col, 4.0 * s)
	_line(c, tip, tip + Vector2(9.0 * s, wing), col, 4.0 * s)


## The throttle lever of a plane: a thin vertical bar beside the horizon.
static func _throttle(c: Control, bottom_left: Vector2, h: float, v: float, s: float) -> void:
	var w := 8.0 * s
	_rect(c, Rect2(bottom_left.x - w, bottom_left.y - h, w, h), PLATE)
	_rect(c, Rect2(bottom_left.x - w, bottom_left.y - h * v, w, h * v), Color(AMBER if v < 0.9 else RED, 0.95))


## The landing guide: a 200 px box with a cross at its centre; the diamond is the aircraft relative to the glide path and the runway axis (±40 m vertical, ±60 m lateral at the full box).
## w126-critic: the rect of the landing guide with its RWY label above and its hint below (for layout tests and the radio portrait).
static func guide_rect(vp: Vector2, s: float, ins: Vector2) -> Rect2:
	var size := Vector2(190.0, 150.0) * s
	var pos := Vector2(ins.x + 26.0 * s + 2.0 * (74.0 * s + 4.0 * s) + 200.0 * s, vp.y * 0.47 - 74.0 * s)
	return Rect2(pos - Vector2(0.0, 32.0 * s), size + Vector2(0.0, 62.0 * s))


static func _guide(c: Control, font: Font, vp: Vector2, ins: Vector2, s: float, g: Dictionary, airborne: bool) -> void:
	var size := Vector2(190.0, 150.0) * s
	var pos := Vector2(ins.x + 26.0 * s + 2.0 * (74.0 * s + 4.0 * s) + 200.0 * s, vp.y * 0.47 - 74.0 * s)       # right of the altitude boxes, level with the horizon: clear of the sticks and the readout plate (guide_rect)
	_rect(c, Rect2(pos, size), PLATE)
	_rect(c, Rect2(pos, size), Color(CYAN, 0.5), false, 2.0 * s)
	var cen := pos + size * 0.5
	_line(c, Vector2(pos.x + 8.0 * s, cen.y), Vector2(pos.x + size.x - 8.0 * s, cen.y), Color(1, 1, 1, 0.5), 1.5 * s)
	_line(c, Vector2(cen.x, pos.y + 8.0 * s), Vector2(cen.x, pos.y + size.y - 8.0 * s), Color(1, 1, 1, 0.5), 1.5 * s)
	var vert := clampf(float(g["vert"]) / 40.0, -1.0, 1.0)             # + = above the path: the diamond is HIGH in the box (steer down to centre it)
	var lat := clampf(float(g["lat"]) / 60.0, -1.0, 1.0)               # + = the runway is to the right: the diamond is to the right
	var dm := cen + Vector2(lat * (size.x * 0.5 - 14.0 * s), -vert * (size.y * 0.5 - 14.0 * s))
	var ok := absf(float(g["vert"])) < 8.0 and absf(float(g["lat"])) < 14.0
	var col := GREEN if ok else AMBER
	var dia := PackedVector2Array([dm + Vector2(0.0, -11.0 * s), dm + Vector2(11.0 * s, 0.0), dm + Vector2(0.0, 11.0 * s), dm + Vector2(-11.0 * s, 0.0)])
	_poly(c, dia, col)
	var txt := "RWY %s   %d M" % [g["rwy"], roundi(float(g["dist"]))]
	_label(c, font, Vector2(pos.x, pos.y - 32.0 * s), Vector2(size.x, 30.0 * s), txt, CYAN, s, 20)
	if airborne:
		var hint := "HIGH: NOSE DOWN" if float(g["vert"]) > 12.0 else ("LOW: NOSE UP" if float(g["vert"]) < -12.0 else "ON PATH")
		_label(c, font, Vector2(pos.x, pos.y + size.y + 2.0 * s), Vector2(size.x, 28.0 * s), hint, col, s, 18)


# --- the pen (w129-airdraws): every shape of the instruments in ONE triangle list, the words after it ------------------------------------------
## Each circle, line, arc and plate was its own canvas draw and the words between them broke every batch: the flight instruments cost about 35 canvas draws a frame (LOW
## jet on the apron: 77 canvas draws in all). batch = false (AirDraws.old) paints them one by one as before.
static var batch := not AirDraws.old
static var _pts := PackedVector2Array()
static var _cols := PackedColorArray()
static var _idx := PackedInt32Array()
static var _texts: Array = []


static func _fan(pts: PackedVector2Array, col: Color) -> void:
	var b := _pts.size()
	for q in pts:
		_pts.append(q)
		_cols.append(col)
	for i in range(1, pts.size() - 1):
		_idx.append(b)
		_idx.append(b + i)
		_idx.append(b + i + 1)


static func _circle(c: Control, ctr: Vector2, r: float, col: Color) -> void:
	if not batch:
		c.draw_circle(ctr, r, col)
		return
	var pts := PackedVector2Array()
	var n := 32 if r > 12.0 else 12
	for i in n:
		pts.append(ctr + Vector2(cos(TAU * i / n), sin(TAU * i / n)) * r)
	_fan(pts, col)


static func _poly(c: Control, pts: PackedVector2Array, col: Color) -> void:
	if not batch:
		c.draw_colored_polygon(pts, col)
		return
	_fan(pts, col)                                                       # every polygon of the instruments is convex


static func _line(c: Control, a: Vector2, b: Vector2, col: Color, w := 1.0) -> void:
	if not batch:
		c.draw_line(a, b, col, w)
		return
	var d := (b - a).normalized().orthogonal() * w * 0.5
	_fan(PackedVector2Array([a + d, b + d, b - d, a - d]), col)


static func _arc(c: Control, ctr: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w := 1.0) -> void:
	if not batch:
		c.draw_arc(ctr, r, a0, a1, n, col, w)
		return
	for i in n:
		var t0 := lerpf(a0, a1, float(i) / float(n))
		var t1 := lerpf(a0, a1, float(i + 1) / float(n))
		var ri := r - w * 0.5
		var ro := r + w * 0.5
		_fan(PackedVector2Array([ctr + Vector2(cos(t0), sin(t0)) * ri, ctr + Vector2(cos(t0), sin(t0)) * ro, ctr + Vector2(cos(t1), sin(t1)) * ro, ctr + Vector2(cos(t1), sin(t1)) * ri]), col)


static func _rect(c: Control, r: Rect2, col: Color, filled := true, w := 1.0) -> void:
	if not batch:
		c.draw_rect(r, col, filled, w)
		return
	if filled:
		_fan(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), col)
		return
	var tl := r.position
	var br := r.end
	_line(c, tl, Vector2(br.x, tl.y), col, w)
	_line(c, Vector2(br.x, tl.y), br, col, w)
	_line(c, br, Vector2(tl.x, br.y), col, w)
	_line(c, Vector2(tl.x, br.y), tl, col, w)


static func _str(c: Control, font: Font, pos: Vector2, text: String, al: HorizontalAlignment, w: float, fs: int, col: Color) -> void:
	if not batch:
		c.draw_string(font, pos, text, al, w, fs, col)
		return
	_texts.append([font, pos, text, al, w, fs, col])


static func _flush(c: Control) -> void:
	if not _idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), _idx, _pts, _cols)
	for t: Array in _texts:
		c.draw_string(t[0], t[1], t[2], t[3], t[4], t[5], t[6])
	_pts.clear()
	_cols.clear()
	_idx.clear()
	_texts.clear()
