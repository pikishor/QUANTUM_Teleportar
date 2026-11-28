class_name HeliCockpit
extends CanvasLayer
## WAVE 125 (plan line 125; agent w125-pads): the HELICOPTER COCKPIT. The VIEW button of a helicopter cycles CHASE -> FAR -> COCKPIT (CameraRig.veh_view 2): the camera sits at the pilot's eye
## (eye(spec)), the machine's own model is hidden (the camera would be inside it) and this layer paints the cockpit around the view: the canopy FRAME (pillars, the roof bar, a centre post on
## the military and heavy families), the tinted GLASS of the eyebrow window, the SEAT bolsters in the lower corners and the INSTRUMENT PANEL with five working gauges: ALT (one turn per 100 m,
## digits), SPEED (km/h), HEADING (a turning compass card), ROTOR (rpm %, green band) and HULL (the damage: no fuel system exists in the game, the hull is the machine's life).
## Drawn on layer 8, under the touch buttons (9) and the HUD (10): the flight instruments, the sticks and the buttons stay on top and readable. The panel sits in the bottom band between the stick
## and the right button cluster and shrinks to keep clear of every visible button (panel_rect()); nothing is drawn across the middle of the view (wave 116 view rules: no rays or streaks).
## FAMILIES shared by every helicopter kind: light (white-grey, bubble canopy), military (olive, armoured frame, green needles), heavy (blue-grey, two-pane windscreen, overhead console).
## A kind picks its family with spec "cockpit"; otherwise by its roster role (HeliRoster.DEFS: attack, stealth, naval -> military; cargo, heavy lift, crane, tilt-rotor -> heavy), then:
## armed with a second weapon (arms2) -> military, 16 m or longer or 6+ seats -> heavy, else light.
##   active()  gauges()  panel_rect()  family_of(spec)

const FAMILIES := {
	&"light": {"panel": Color(0.15, 0.16, 0.18, 0.96), "frame": Color(0.2, 0.21, 0.23, 1.0), "face": Color(0.03, 0.035, 0.04, 1.0), "needle": Color(1.0, 1.0, 0.97), "accent": Color(0.35, 0.95, 1.0), "post": false, "pillar": 0.05},
	&"military": {"panel": Color(0.13, 0.15, 0.1, 0.97), "frame": Color(0.16, 0.18, 0.12, 1.0), "face": Color(0.02, 0.04, 0.02, 1.0), "needle": Color(0.62, 1.0, 0.45), "accent": Color(1.0, 0.75, 0.25), "post": true, "pillar": 0.075},
	&"heavy": {"panel": Color(0.12, 0.14, 0.17, 0.97), "frame": Color(0.21, 0.23, 0.26, 1.0), "face": Color(0.02, 0.03, 0.05, 1.0), "needle": Color(1.0, 0.92, 0.6), "accent": Color(0.55, 0.85, 1.0), "post": true, "pillar": 0.065},
}
const GLASS := Color(0.25, 0.55, 0.45, 0.22)
const RED := Color(1.0, 0.3, 0.25)
const GREEN := Color(0.35, 1.0, 0.45)

static var instance: HeliCockpit
var view: Control
var _hidden: Vehicle = null            ## the machine whose model is hidden while the cockpit shows
var _tc: Node = null
var shown_frames := 0                  ## frames the cockpit was painted (tests)


static func family_of(spec: Dictionary) -> StringName:
	var f: Variant = spec.get("cockpit")
	if f != null and FAMILIES.has(StringName(str(f))):
		return StringName(str(f))
	var role := _role(spec)
	if role in ["attack", "stealth", "naval"]:
		return &"military"
	if role in ["tandem-rotor cargo", "heavy lift", "crane", "tilt-rotor"]:
		return &"heavy"
	if bool(spec.get("arms2", false)):
		return &"military"
	if float(spec.get("len", 10.0)) >= 16.0 or int(spec.get("seats", 2)) >= 6:
		return &"heavy"
	return &"light"


## The roster role of a kind (w125-helis: HeliRoster.DEFS[kind].role, matched by the spec's "procedural" id), "" when none.
static var _roster: Variant = null
static func _role(spec: Dictionary) -> String:
	if _roster == null:
		_roster = load("res://scripts/vehicles/heli_roster.gd") if ResourceLoader.exists("res://scripts/vehicles/heli_roster.gd") else false
	if not (_roster is Script):
		return ""
	var defs: Dictionary = (_roster as Script).get_script_constant_map().get("DEFS", {})
	var d: Variant = defs.get(StringName(str(spec.get("procedural", ""))))
	return str((d as Dictionary).get("role", "")) if d is Dictionary else ""


## The pilot's eye for CameraRig._vehicle_params (view 2 of a helicopter): x = metres ahead of the centre, y = height over the machine's origin, z = field of view.
static func eye(spec: Dictionary) -> Vector3:
	var ln := float(spec.get("len", 11.0))
	var hg := float(spec.get("hgt", 4.0))
	return Vector3(ln * 0.27, hg * 0.48, 74.0)


## True when `spec` is a helicopter's and the cockpit is on (CameraRig asks).
static func applies(spec: Variant) -> bool:
	return Helipads.enabled and spec is Dictionary and str((spec as Dictionary).get("cls", "")) == "heli"


func _ready() -> void:
	instance = self
	layer = 8
	view = Control.new()
	view.name = "CockpitView"
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.draw.connect(_paint)
	add_child(view)


func _exit_tree() -> void:
	if instance == self:
		instance = null
	_show_model(null)


## The helicopter the hero flies in cockpit view, or null.
static func flown() -> Vehicle:
	var vm := Game.vehicles as VehicleManager
	if vm == null or vm.driven == null or not is_instance_valid(Game.player):
		return null
	var v := vm.driven
	if v.cls != &"heli" or v.craft == null or not Helipads.enabled:
		return null
	var rig: Variant = Game.player.get(&"camera_rig")
	if rig == null or int((rig as Object).get(&"veh_view")) != 2:
		return null
	return v


static func active() -> bool:
	return flown() != null and Game.state == &"play"


func _process(_dt: float) -> void:
	var v := flown()
	if v == null or Game.state != &"play":
		_show_model(null)
		view.visible = false
		return
	_show_model(v)
	view.visible = true
	view.queue_redraw()


func _show_model(v: Vehicle) -> void:
	if _hidden == v:
		return
	if is_instance_valid(_hidden) and _hidden.visual != null and is_instance_valid(_hidden.visual.model):
		_hidden.visual.model.visible = true
	_hidden = v
	if is_instance_valid(v) and v.visual != null and is_instance_valid(v.visual.model):
		v.visual.model.visible = false


# --- layout -------------------------------------------------------------------------------------------------------------------------------

func _touch() -> Node:
	if not is_instance_valid(_tc):
		var hud := get_tree().get_first_node_in_group(&"hud")
		_tc = hud.get(&"touch") if hud != null else null
	return _tc


## The circles of the touch buttons on screen now (centre, radius) in canvas px.
func button_circles() -> Array:
	var out: Array = []
	var tc := _touch()
	if tc == null or not tc.has_method(&"button_visible") or not bool(tc.get(&"controls_on")):
		return out
	var s := UiUtil.ui_scale(_vp())
	for b: Dictionary in TouchControls.BUTTONS:
		if bool(tc.call(&"button_visible", b)):
			out.append([tc.call(&"_button_center", b), float(b["r"]) * s])
	return out


func _vp() -> Vector2:
	return view.get_viewport_rect().size if view != null else Vector2(1280, 720)


## w129-airdraws: the move pad's circle (centre, radius + margin) in canvas px: where the thumb lands (the idle hint ring, or the live base while a finger is down).
## Nothing of the cockpit is painted over it (wave 128: the left pillar, the seat bolster and the dash crossed the pad). [] without the touch HUD or with AirDraws.old.
var pad_polys := 0                     ## polygons of the last frame that touched the pad (tests: must be 0)


func stick_zone() -> Array:
	var tc := _touch()
	if tc == null or not bool(tc.get(&"controls_on")):
		return []
	var vp := _vp()
	var s := UiUtil.ui_scale(vp)
	var left := not UiSettings.s_left_hand
	var c := Vector2(190.0 * s + UiUtil.insets(vp).x if left else vp.x - 190.0 * s - UiUtil.insets(vp).y, vp.y - 170.0 * s - UiUtil.insets_v(vp).y)
	var r := TouchControls.STICK_RADIUS * s + 14.0 * s
	if int(tc.get(&"_stick_id")) != -1:
		var o: Vector2 = tc.get(&"_stick_origin")
		var span := (o - c).length()
		c = (c + o) * 0.5
		r += span * 0.5                                                 # one circle round both: the hint ring and where the thumb really is
	return [c, r]


## The frame's shapes for the current layout, as _paint draws them: left / right pillar, left / right seat bolster, the dash shroud (empty when the panel is too narrow).
## w129-airdraws: a pillar ends above the move pad, the dash's foot stops beside it, a bolster over it is left out (AirDraws.old: as wave 128).
func frame_shapes(v: Vehicle) -> Dictionary:
	var vp := _vp()
	var s := UiUtil.ui_scale(vp)
	var fam: Dictionary = FAMILIES[family_of(v.spec)]
	var pr := panel_rect()
	var py := pr.position.y
	var pw := vp.x * float(fam["pillar"])
	var top := 34.0 * s
	var lx := pr.position.x - 40.0 * s
	var rx := pr.end.x + 40.0 * s
	var out := {
		"pl": _clear_pillar(PackedVector2Array([Vector2(0.0, top), Vector2(pw, top), Vector2(lx * 0.42 + pw, py), Vector2(lx * 0.42, py)]), s),
		"pr": _clear_pillar(PackedVector2Array([Vector2(vp.x - pw, top), Vector2(vp.x, top), Vector2(vp.x - (vp.x - rx) * 0.42, py), Vector2(vp.x - (vp.x - rx) * 0.42 - pw, py)]), s),
		"bl": PackedVector2Array([Vector2(0.0, vp.y), Vector2(0.0, vp.y - 120.0 * s), Vector2(40.0 * s, vp.y - 150.0 * s), Vector2(120.0 * s, vp.y)]),
		"br": PackedVector2Array([Vector2(vp.x, vp.y), Vector2(vp.x, vp.y - 120.0 * s), Vector2(vp.x - 40.0 * s, vp.y - 150.0 * s), Vector2(vp.x - 120.0 * s, vp.y)]),
	}
	if not AirDraws.old:
		for k: String in ["bl", "br"]:
			if _hits_pad(out[k]):
				out.erase(k)
	if pr.size.x >= 120.0 * s:
		var fl := pr.position.x - 60.0 * s
		var fr := pr.end.x + 60.0 * s
		var z := stick_zone()
		if z.size() == 2 and not AirDraws.old:
			var zc: Vector2 = z[0]
			var zr: float = z[1]
			if zc.x < vp.x * 0.5:
				fl = minf(pr.position.x - 1.0, maxf(fl, zc.x + zr + 2.0 * s))
			else:
				fr = maxf(pr.end.x + 1.0, minf(fr, zc.x - zr - 2.0 * s))
		out["dash"] = PackedVector2Array([Vector2(fl, vp.y), Vector2(maxf(pr.position.x - 30.0 * s, fl), py + 10.0 * s), Vector2(pr.position.x, py - 12.0 * s),
			Vector2(pr.end.x, py - 12.0 * s), Vector2(minf(pr.end.x + 30.0 * s, fr), py + 10.0 * s), Vector2(fr, vp.y)])
	return out


## How many of the frame's shapes lie over the move pad (tests: 0 since w129-airdraws; the pillars and the dash are still there, shorter).
func pad_overlaps() -> int:
	var v := flown()
	if v == null:
		return 0
	var n := 0
	var sh := frame_shapes(v)
	for k: String in sh:
		if _hits_pad(sh[k]):
			n += 1
	return n


func _hits_pad(pts: PackedVector2Array) -> bool:
	var z := stick_zone()
	if z.size() != 2:
		return false
	var c: Vector2 = z[0]
	var r: float = z[1]
	if Geometry2D.is_point_in_polygon(c, pts):
		return true
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		if Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c) < r:
			return true
	return false


## w129-airdraws: a canopy pillar that would reach down into the move pad ends above it (its foot slides up along its edges).
func _clear_pillar(pts: PackedVector2Array, s: float) -> PackedVector2Array:
	var z := stick_zone()
	if AirDraws.old or z.size() != 2 or not _hits_pad(pts):
		return pts
	var zc: Vector2 = z[0]
	var zr: float = z[1]
	var lo := pts[0].y
	var hi := pts[2].y
	for i in 12:                                                        # the lowest foot height that keeps clear of the pad (bisection on y)
		var mid := (lo + hi) * 0.5
		var t := (mid - pts[0].y) / maxf(pts[3].y - pts[0].y, 1.0)
		var q := PackedVector2Array([pts[0], pts[1], pts[1].lerp(pts[2], t), pts[0].lerp(pts[3], t)])
		var hit := false
		for k in 4:
			if Geometry2D.get_closest_point_to_segment(zc, q[k], q[(k + 1) % 4]).distance_to(zc) < zr:
				hit = true
		if hit:
			hi = mid
		else:
			lo = mid
	var t2 := (lo - pts[0].y) / maxf(pts[3].y - pts[0].y, 1.0)
	return PackedVector2Array([pts[0], pts[1], pts[1].lerp(pts[2], t2), pts[0].lerp(pts[3], t2)])


## The instrument panel: a band low in the view, right of the flight instruments (FlightHud's horizon and readouts end near 360 px), above the buttons of the bottom row (DOWN, UP)
## and left of the right cluster; it keeps 8 px clear of every visible button circle. The dash below it reaches the bottom of the screen under the HUD's plates and the stick.
func panel_rect() -> Rect2:
	var vp := _vp()
	var s := UiUtil.ui_scale(vp)
	var ins := UiUtil.insets(vp)
	var x0 := ins.x + 370.0 * s
	var x1 := vp.x - ins.y - 290.0 * s
	var pad := stick_zone()                                              # w129-airdraws: the panel starts right of the move pad (left-handed: ends left of it)
	if pad.size() == 2 and not AirDraws.old:
		var pc: Vector2 = pad[0]
		var prr: float = pad[1]
		if pc.x < vp.x * 0.5:
			x0 = maxf(x0, pc.x + prr + 8.0 * s)
		else:
			x1 = minf(x1, pc.x - prr - 8.0 * s)
	var y1 := vp.y - UiUtil.insets_v(vp).y - 8.0 * s
	var circles := button_circles()
	for c: Array in circles:                                             # the bottom row under the panel's span lifts its bottom edge
		var p: Vector2 = c[0]
		var r: float = float(c[1]) + 8.0 * s
		if p.x + r > x0 and p.x - r < x1 and p.y > vp.y * 0.72:
			y1 = minf(y1, p.y - r)
	var h := clampf(150.0 * s, 80.0, vp.y * 0.22)
	var y0 := y1 - h
	for c: Array in circles:                                             # a button beside the band trims its right (or left) end
		var p2: Vector2 = c[0]
		var r2: float = float(c[1]) + 8.0 * s
		if p2.y + r2 < y0 or p2.y - r2 > y1:
			continue
		if p2.x > (x0 + x1) * 0.5:
			x1 = minf(x1, p2.x - r2)
		else:
			x0 = maxf(x0, p2.x + r2)
	return Rect2(x0, y0, maxf(x1 - x0, 0.0), h)


# --- the gauges -----------------------------------------------------------------------------------------------------------------------------

## What the five gauges show now: values and needle angles (radians, 0 = up, clockwise), for the painter and the tests.
static func gauges(v: Vehicle) -> Dictionary:
	var d := AircraftFlight.info(v)
	var agl := float(d["agl"])
	var kmh := absf(float(d["speed"])) * 3.6
	var vmax := float(v.spec.get("max", 50.0)) * 3.6
	var rpm := clampf(float(d["spool"]), 0.0, 1.0) * 100.0
	var hull := clampf(v.hp / maxf(v.max_hp, 1.0), 0.0, 1.0) * 100.0
	var hdg := FlightHud.compass(float(d["heading"]))
	return {
		"alt": agl, "alt_a": fposmod(agl, 100.0) / 100.0 * TAU,
		"spd": kmh, "spd_a": -PI * 0.75 + clampf(kmh / maxf(vmax * 1.1, 1.0), 0.0, 1.0) * PI * 1.5,
		"hdg": hdg, "hdg_a": -deg_to_rad(float(hdg)),
		"rpm": rpm, "rpm_a": -PI * 0.75 + rpm / 100.0 * PI * 1.5,
		"hull": hull, "hull_a": -PI * 0.75 + hull / 100.0 * PI * 1.5,
		"family": family_of(v.spec),
	}


# --- painting -------------------------------------------------------------------------------------------------------------------------------

# --- the pen: one draw for all the shapes (w125-critic) ----------------------------------------------------------------------------------------
## w125-critic (defect: the cockpit cost 30+ extra draw calls in flight, LOW 135 -> 169): every circle, polygon and arc on a canvas is its own draw, so the
## five gauges, the frame and the seats made one draw each. With batch_fix the shapes go into ONE triangle list (RenderingServer.canvas_item_add_triangle_array)
## in painting order and the text follows in one batch. W125C_OLD=1: the old one-draw-per-shape painting.
static var batch_fix := OS.get_environment("W125C_OLD") != "1"
var _pts := PackedVector2Array()
var _cols := PackedColorArray()
var _idx := PackedInt32Array()
var _texts: Array = []


func _tri_fan(pts: PackedVector2Array, col: Color) -> void:
	var b := _pts.size()
	for p in pts:
		_pts.append(p)
		_cols.append(col)
	for i in range(1, pts.size() - 1):
		_idx.append(b)
		_idx.append(b + i)
		_idx.append(b + i + 1)


func _rect(c: Control, r: Rect2, col: Color) -> void:
	if not batch_fix:
		c.draw_rect(r, col)
		return
	_tri_fan(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), col)


func _poly(c: Control, pts: PackedVector2Array, col: Color) -> void:
	if _hits_pad(pts):
		pad_polys += 1
	if not batch_fix:
		c.draw_colored_polygon(pts, col)
		return
	_tri_fan(pts, col)                                                  # every polygon of the cockpit is convex


func _line(c: Control, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	if not batch_fix:
		c.draw_line(a, b, col, w)
		return
	var d := (b - a).normalized().orthogonal() * w * 0.5
	_tri_fan(PackedVector2Array([a + d, b + d, b - d, a - d]), col)


func _circle(c: Control, ctr: Vector2, r: float, col: Color) -> void:
	if not batch_fix:
		c.draw_circle(ctr, r, col)
		return
	var pts := PackedVector2Array()
	var n := 28
	for i in n:
		pts.append(ctr + Vector2(cos(TAU * i / n), sin(TAU * i / n)) * r)
	_tri_fan(pts, col)


func _arc(c: Control, ctr: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w: float, aa: bool) -> void:
	if not batch_fix:
		c.draw_arc(ctr, r, a0, a1, n, col, w, aa)
		return
	for i in n:
		var p0 := ctr + Vector2(cos(lerpf(a0, a1, float(i) / n)), sin(lerpf(a0, a1, float(i) / n))) * r
		var p1 := ctr + Vector2(cos(lerpf(a0, a1, float(i + 1) / n)), sin(lerpf(a0, a1, float(i + 1) / n))) * r
		_line(c, p0, p1, col, w)


func _text(c: Control, font: Font, pos: Vector2, t: String, al: HorizontalAlignment, w: float, fs: int, col: Color) -> void:
	if not batch_fix:
		c.draw_string(font, pos, t, al, w, fs, col)
		return
	_texts.append([font, pos, t, al, w, fs, col])


func _flush(c: Control) -> void:
	if not batch_fix:
		return
	if not _idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), _idx, _pts, _cols)
	for t: Array in _texts:
		c.draw_string(t[0], t[1], t[2], t[3], t[4], t[5], t[6])
	_pts.clear()
	_cols.clear()
	_idx.clear()
	_texts.clear()


func _paint() -> void:
	var v := flown()
	if v == null:
		return
	shown_frames += 1
	pad_polys = 0
	var c := view
	var vp := _vp()
	var s := UiUtil.ui_scale(vp)
	var fam: Dictionary = FAMILIES[family_of(v.spec)]
	var fc: Color = fam["frame"]
	var pr := panel_rect()
	var py := pr.position.y
	# the canopy frame: two side pillars from the panel's ends up to the roof bar, the roof bar, a centre post, the glass of the eyebrow window
	var pw := vp.x * float(fam["pillar"])
	var top := 34.0 * s
	_rect(c, Rect2(0.0, 0.0, vp.x, top), fc)
	_rect(c, Rect2(0.0, top, vp.x, 16.0 * s), GLASS)
	_line(c, Vector2(0.0, top + 16.0 * s), Vector2(vp.x, top + 16.0 * s), Color(fc, 1.0), 3.0 * s)
	var fs0 := frame_shapes(v)
	var lp: PackedVector2Array = fs0["pl"]
	var rp: PackedVector2Array = fs0["pr"]
	_poly(c, lp, fc)
	_poly(c, rp, fc)
	_line(c, lp[1], lp[2], Color(0.75, 0.9, 1.0, 0.35), 1.5 * s)     # the glass edge along the pillar
	_line(c, rp[0], rp[3], Color(0.75, 0.9, 1.0, 0.35), 1.5 * s)
	if bool(fam["post"]):
		var cx := pr.get_center().x
		_poly(c, PackedVector2Array([Vector2(cx - 5.0 * s, top), Vector2(cx + 5.0 * s, top), Vector2(cx + 8.0 * s, py), Vector2(cx - 8.0 * s, py)]), fc)
	if family_of(v.spec) == &"heavy":                                   # the overhead console: a row of switches on the roof bar
		for i in 9:
			var sx := vp.x * 0.5 + (float(i) - 4.0) * 26.0 * s
			_rect(c, Rect2(sx - 8.0 * s, 9.0 * s, 16.0 * s, 16.0 * s), Color(0.08, 0.09, 0.1))
			_rect(c, Rect2(sx - 2.0 * s, 11.0 * s, 4.0 * s, 8.0 * s), Color(fam["accent"], 0.9) if i % 3 != 1 else Color(0.6, 0.6, 0.6))
	# the seat bolsters in the lower corners, the dash shroud along the panel's top
	for k: String in ["bl", "br"]:
		if fs0.has(k):
			_poly(c, fs0[k], Color(0.06, 0.06, 0.07, 0.95))
	if not fs0.has("dash"):
		_flush(c)
		return
	_poly(c, fs0["dash"], Color(fc, 0.9))
	_rect(c, pr, fam["panel"])
	# five gauges in a row
	var g := gauges(v)
	var n := 5
	var cell := pr.size.x / float(n)
	var gr := minf(cell * 0.42, (pr.size.y - 34.0 * s) * 0.46)
	var font := UiUtil.font()
	var fs := int(maxf(15.0 * s, gr * 0.42))
	var labels := ["ALT", "SPEED", "HDG", "ROTOR", "HULL"]
	var texts := ["%d M" % roundi(float(g["alt"])), "%d" % roundi(float(g["spd"])), "%03d" % int(g["hdg"]), "%d%%" % roundi(float(g["rpm"])), "%d%%" % roundi(float(g["hull"]))]
	for i in n:
		var ctr := Vector2(pr.position.x + cell * (float(i) + 0.5), py + 8.0 * s + gr)
		_circle(c, ctr, gr + 3.0 * s, Color(0.4, 0.42, 0.45))
		_circle(c, ctr, gr, fam["face"])
		var acc: Color = fam["accent"]
		match i:
			0:
				for k in 10:
					var a := TAU * float(k) / 10.0
					_line(c, ctr + _dir(a) * gr * 0.78, ctr + _dir(a) * gr * 0.95, acc, 2.0 * s)
				_needle(c, ctr, float(g["alt_a"]), gr * 0.82, fam["needle"], s)
			1:
				_ticks(c, ctr, gr, acc, s)
				_needle(c, ctr, float(g["spd_a"]), gr * 0.82, fam["needle"], s)
			2:                                                           # the compass card turns, the lubber line stays at the top
				var hd := float(g["hdg_a"])
				for k in 12:
					var a2 := hd + TAU * float(k) / 12.0
					_line(c, ctr + _dir(a2) * gr * 0.8, ctr + _dir(a2) * gr * 0.95, acc if k % 3 == 0 else Color(acc, 0.5), 2.0 * s)
				var card := ["N", "E", "S", "W"]
				for k in 4:
					var a3 := hd + TAU * float(k) / 4.0
					var tp := ctr + _dir(a3) * gr * 0.58
					_text(c, font, tp + Vector2(-6.0 * s, 6.0 * s), card[k], HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(gr * 0.34), RED if k == 0 else Color(1, 1, 1))
				_poly(c, PackedVector2Array([ctr + Vector2(0.0, -gr * 0.98), ctr + Vector2(-5.0 * s, -gr * 0.78), ctr + Vector2(5.0 * s, -gr * 0.78)]), Color(1.0, 0.8, 0.2))
			3:
				_band(c, ctr, gr, 0.9, 1.0, GREEN, s)
				_ticks(c, ctr, gr, acc, s)
				_needle(c, ctr, float(g["rpm_a"]), gr * 0.82, fam["needle"], s)
			4:
				_band(c, ctr, gr, 0.0, 0.3, RED, s)
				_ticks(c, ctr, gr, acc, s)
				_needle(c, ctr, float(g["hull_a"]), gr * 0.82, RED if float(g["hull"]) < 30.0 else fam["needle"], s)
		_text(c, font, Vector2(ctr.x - cell * 0.5, ctr.y + gr + fs + 4.0 * s), texts[i], HORIZONTAL_ALIGNMENT_CENTER, cell, fs, Color(1, 1, 1))
		if i != 2:                                                       # the name in the dial's lower third, under the needle's hub (the compass names itself with its letters)
			_text(c, font, Vector2(ctr.x - cell * 0.5, ctr.y + gr * 0.62), labels[i], HORIZONTAL_ALIGNMENT_CENTER, cell, int(maxf(11.0 * s, gr * 0.22)), Color(acc, 0.85))

	_flush(c)


static func _dir(a: float) -> Vector2:
	return Vector2(sin(a), -cos(a))


func _needle(c: Control, ctr: Vector2, a: float, ln: float, col: Color, s: float) -> void:
	_line(c, ctr - _dir(a) * ln * 0.18, ctr + _dir(a) * ln, col, 3.5 * s)
	_circle(c, ctr, 4.0 * s, col)


func _ticks(c: Control, ctr: Vector2, gr: float, col: Color, s: float) -> void:
	for k in 7:
		var a := -PI * 0.75 + PI * 1.5 * float(k) / 6.0
		_line(c, ctr + _dir(a) * gr * 0.78, ctr + _dir(a) * gr * 0.95, col, 2.0 * s)


func _band(c: Control, ctr: Vector2, gr: float, f0: float, f1: float, col: Color, s: float) -> void:
	var a0 := -PI * 0.75 + PI * 1.5 * f0
	var a1 := -PI * 0.75 + PI * 1.5 * f1
	# draw_arc: angle 0 = +x, growing clockwise on screen (y down); the gauges' 0 is up, hence the quarter turn
	_arc(c, ctr, gr * 0.88, a0 - PI * 0.5, a1 - PI * 0.5, 10, Color(col, 0.85), 5.0 * s, false)
