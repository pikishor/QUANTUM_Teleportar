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


static func visible_for(veh: Object) -> bool:
	return veh is Vehicle and (veh as Vehicle).craft != null and ((veh as Vehicle).cls == &"heli" or (veh as Vehicle).cls == &"plane")


static func draw(c: Control, font: Font, vp: Vector2, s: float, ins: Vector2, veh: Object) -> void:
	if not visible_for(veh):
		return
	var v := veh as Vehicle
	var d := AircraftFlight.info(v)
	var r := 74.0 * s
	var centre := Vector2(ins.x + 26.0 * s + r + 4.0 * s, vp.y * 0.47)
	_horizon(c, centre, r, float(d["pitch"]), float(d["roll"]), s)
	# heading under the horizon, altitude and vertical speed beside it
	_label(c, font, Vector2(centre.x - 50.0 * s, centre.y + r + 8.0 * s), Vector2(100.0 * s, 28.0 * s), "HDG %03d" % compass(float(d["heading"])), CYAN, s)
	var ax := centre.x + r + 14.0 * s
	var agl := float(d["agl"])
	_label(c, font, Vector2(ax, centre.y - r), Vector2(150.0 * s, 40.0 * s), "%d M" % roundi(agl), CYAN if agl > 25.0 else AMBER, s, 26)
	var vs := float(d["vspeed"])
	_vs_arrow(c, Vector2(ax + 22.0 * s, centre.y - r + 74.0 * s), vs, s)
	_label(c, font, Vector2(ax + 46.0 * s, centre.y - r + 56.0 * s), Vector2(110.0 * s, 28.0 * s), "%+d" % roundi(vs), (AMBER if vs < -6.0 else CYAN), s)
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


## The artificial horizon: a disc split at the horizon line, which tilts opposite to the bank and slides with the pitch; a fixed aircraft mark and a short pitch ladder on top.
static func _horizon(c: Control, centre: Vector2, r: float, pitch: float, roll: float, s: float) -> void:
	c.draw_circle(centre, r + 4.0 * s, PLATE)
	c.draw_circle(centre, r, SKY)
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
		c.draw_colored_polygon(ground, GROUND)
	var half := r * 1.2
	var p0 := hc - along * half
	var p1 := hc + along * half
	var inside0 := (p0 - centre).length() < r
	if inside0 or (p1 - centre).length() < r or absf((hc - centre).dot(down)) < r:
		var seg := _clip_segment(p0, p1, centre, r)
		if seg.size() == 2:
			c.draw_line(seg[0], seg[1], Color(1, 1, 1, 0.95), 2.5 * s)
	for k in [-2, -1, 1, 2]:                                   # a ladder rung every 10 degrees
		var cen := hc + down * (-float(k) * 0.1745 * PITCH_PX * s)
		var wdt := (14.0 if absi(k) == 1 else 22.0) * s
		if (cen - centre).length() < r - 12.0 * s:
			c.draw_line(cen - along * wdt, cen + along * wdt, Color(1, 1, 1, 0.55), 1.5 * s)
	c.draw_arc(centre, r, 0.0, TAU, 40, Color(CYAN, 0.9), 3.0 * s)
	var w := r * 0.5                                           # the aircraft mark (fixed): a small W
	c.draw_line(centre + Vector2(-w, 0.0), centre + Vector2(-w * 0.35, 0.0), AMBER, 4.0 * s)
	c.draw_line(centre + Vector2(w, 0.0), centre + Vector2(w * 0.35, 0.0), AMBER, 4.0 * s)
	c.draw_line(centre + Vector2(-w * 0.35, 0.0), centre + Vector2(0.0, 9.0 * s), AMBER, 4.0 * s)
	c.draw_line(centre + Vector2(w * 0.35, 0.0), centre + Vector2(0.0, 9.0 * s), AMBER, 4.0 * s)
	c.draw_circle(centre, 3.0 * s, AMBER)


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
	c.draw_rect(Rect2(pos, size), PLATE)
	var fsz := int(float(fs) * s)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	while tw > size.x - 8.0 * s and fsz > 10:
		fsz -= 1
		tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	c.draw_string(font, Vector2(pos.x + (size.x - tw) * 0.5, pos.y + size.y * 0.5 + float(fsz) * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, col)


## An arrow for the vertical speed: up for a climb, down for a sink, longer the faster (capped), a flat bar when level.
static func _vs_arrow(c: Control, at: Vector2, vs: float, s: float) -> void:
	var k := clampf(vs / 12.0, -1.0, 1.0)
	var col := CYAN if vs >= -6.0 else AMBER
	if absf(vs) < 0.8:
		c.draw_line(at + Vector2(-12.0, 0.0) * s, at + Vector2(12.0, 0.0) * s, Color(col, 0.7), 3.0 * s)
		return
	var tip := at + Vector2(0.0, -k * 34.0 * s)
	var wing := 12.0 * s * (1.0 if k > 0.0 else -1.0)                  # the head's wings trail back from the tip
	c.draw_line(at, tip, col, 4.0 * s)
	c.draw_line(tip, tip + Vector2(-9.0 * s, wing), col, 4.0 * s)
	c.draw_line(tip, tip + Vector2(9.0 * s, wing), col, 4.0 * s)


## The throttle lever of a plane: a thin vertical bar beside the horizon.
static func _throttle(c: Control, bottom_left: Vector2, h: float, v: float, s: float) -> void:
	var w := 8.0 * s
	c.draw_rect(Rect2(bottom_left.x - w, bottom_left.y - h, w, h), PLATE)
	c.draw_rect(Rect2(bottom_left.x - w, bottom_left.y - h * v, w, h * v), Color(AMBER if v < 0.9 else RED, 0.95))


## The landing guide: a 200 px box with a cross at its centre; the diamond is the aircraft relative to the glide path and the runway axis (±40 m vertical, ±60 m lateral at the full box).
static func _guide(c: Control, font: Font, vp: Vector2, ins: Vector2, s: float, g: Dictionary, airborne: bool) -> void:
	var size := Vector2(190.0, 150.0) * s
	var pos := Vector2(ins.x + 26.0 * s + 2.0 * (74.0 * s + 4.0 * s) + 200.0 * s, vp.y * 0.47 - 74.0 * s)       # right of the altitude boxes, level with the horizon: clear of the sticks and the readout plate
	c.draw_rect(Rect2(pos, size), PLATE)
	c.draw_rect(Rect2(pos, size), Color(CYAN, 0.5), false, 2.0 * s)
	var cen := pos + size * 0.5
	c.draw_line(Vector2(pos.x + 8.0 * s, cen.y), Vector2(pos.x + size.x - 8.0 * s, cen.y), Color(1, 1, 1, 0.5), 1.5 * s)
	c.draw_line(Vector2(cen.x, pos.y + 8.0 * s), Vector2(cen.x, pos.y + size.y - 8.0 * s), Color(1, 1, 1, 0.5), 1.5 * s)
	var vert := clampf(float(g["vert"]) / 40.0, -1.0, 1.0)             # + = above the path: the diamond is HIGH in the box (steer down to centre it)
	var lat := clampf(float(g["lat"]) / 60.0, -1.0, 1.0)               # + = the runway is to the right: the diamond is to the right
	var dm := cen + Vector2(lat * (size.x * 0.5 - 14.0 * s), -vert * (size.y * 0.5 - 14.0 * s))
	var ok := absf(float(g["vert"])) < 8.0 and absf(float(g["lat"])) < 14.0
	var col := GREEN if ok else AMBER
	var dia := PackedVector2Array([dm + Vector2(0.0, -11.0 * s), dm + Vector2(11.0 * s, 0.0), dm + Vector2(0.0, 11.0 * s), dm + Vector2(-11.0 * s, 0.0)])
	c.draw_colored_polygon(dia, col)
	var txt := "RWY %s   %d M" % [g["rwy"], roundi(float(g["dist"]))]
	_label(c, font, Vector2(pos.x, pos.y - 32.0 * s), Vector2(size.x, 30.0 * s), txt, CYAN, s, 20)
	if airborne:
		var hint := "HIGH: NOSE DOWN" if float(g["vert"]) > 12.0 else ("LOW: NOSE UP" if float(g["vert"]) < -12.0 else "ON PATH")
		_label(c, font, Vector2(pos.x, pos.y + size.y + 2.0 * s), Vector2(size.x, 28.0 * s), hint, col, s, 18)
