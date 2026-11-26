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


## The instrument panel: a band low in the view, right of the flight instruments (FlightHud's horizon and readouts end near 360 px), above the buttons of the bottom row (DOWN, UP)
## and left of the right cluster; it keeps 8 px clear of every visible button circle. The dash below it reaches the bottom of the screen under the HUD's plates and the stick.
func panel_rect() -> Rect2:
	var vp := _vp()
	var s := UiUtil.ui_scale(vp)
	var ins := UiUtil.insets(vp)
	var x0 := ins.x + 370.0 * s
	var x1 := vp.x - ins.y - 290.0 * s
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

func _paint() -> void:
	var v := flown()
	if v == null:
		return
	shown_frames += 1
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
	c.draw_rect(Rect2(0.0, 0.0, vp.x, top), fc)
	c.draw_rect(Rect2(0.0, top, vp.x, 16.0 * s), GLASS)
	c.draw_line(Vector2(0.0, top + 16.0 * s), Vector2(vp.x, top + 16.0 * s), Color(fc, 1.0), 3.0 * s)
	var lx := pr.position.x - 40.0 * s
	var rx := pr.end.x + 40.0 * s
	c.draw_colored_polygon(PackedVector2Array([Vector2(0.0, top), Vector2(pw, top), Vector2(lx * 0.42 + pw, py), Vector2(lx * 0.42, py)]), fc)
	c.draw_colored_polygon(PackedVector2Array([Vector2(vp.x - pw, top), Vector2(vp.x, top), Vector2(vp.x - (vp.x - rx) * 0.42, py), Vector2(vp.x - (vp.x - rx) * 0.42 - pw, py)]), fc)
	c.draw_line(Vector2(pw, top), Vector2(lx * 0.42 + pw, py), Color(0.75, 0.9, 1.0, 0.35), 1.5 * s)     # the glass edge along the pillar
	c.draw_line(Vector2(vp.x - pw, top), Vector2(vp.x - (vp.x - rx) * 0.42 - pw, py), Color(0.75, 0.9, 1.0, 0.35), 1.5 * s)
	if bool(fam["post"]):
		var cx := pr.get_center().x
		c.draw_colored_polygon(PackedVector2Array([Vector2(cx - 5.0 * s, top), Vector2(cx + 5.0 * s, top), Vector2(cx + 8.0 * s, py), Vector2(cx - 8.0 * s, py)]), fc)
	if family_of(v.spec) == &"heavy":                                   # the overhead console: a row of switches on the roof bar
		for i in 9:
			var sx := vp.x * 0.5 + (float(i) - 4.0) * 26.0 * s
			c.draw_rect(Rect2(sx - 8.0 * s, 9.0 * s, 16.0 * s, 16.0 * s), Color(0.08, 0.09, 0.1))
			c.draw_rect(Rect2(sx - 2.0 * s, 11.0 * s, 4.0 * s, 8.0 * s), Color(fam["accent"], 0.9) if i % 3 != 1 else Color(0.6, 0.6, 0.6))
	# the seat bolsters in the lower corners, the dash shroud along the panel's top
	c.draw_colored_polygon(PackedVector2Array([Vector2(0.0, vp.y), Vector2(0.0, vp.y - 120.0 * s), Vector2(40.0 * s, vp.y - 150.0 * s), Vector2(120.0 * s, vp.y)]), Color(0.06, 0.06, 0.07, 0.95))
	c.draw_colored_polygon(PackedVector2Array([Vector2(vp.x, vp.y), Vector2(vp.x, vp.y - 120.0 * s), Vector2(vp.x - 40.0 * s, vp.y - 150.0 * s), Vector2(vp.x - 120.0 * s, vp.y)]), Color(0.06, 0.06, 0.07, 0.95))
	if pr.size.x < 120.0 * s:
		return
	c.draw_colored_polygon(PackedVector2Array([Vector2(pr.position.x - 60.0 * s, vp.y), Vector2(pr.position.x - 30.0 * s, py + 10.0 * s), Vector2(pr.position.x, py - 12.0 * s),
		Vector2(pr.end.x, py - 12.0 * s), Vector2(pr.end.x + 30.0 * s, py + 10.0 * s), Vector2(pr.end.x + 60.0 * s, vp.y)]), Color(fc, 0.9))
	c.draw_rect(pr, fam["panel"])
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
		c.draw_circle(ctr, gr + 3.0 * s, Color(0.4, 0.42, 0.45))
		c.draw_circle(ctr, gr, fam["face"])
		var acc: Color = fam["accent"]
		match i:
			0:
				for k in 10:
					var a := TAU * float(k) / 10.0
					c.draw_line(ctr + _dir(a) * gr * 0.78, ctr + _dir(a) * gr * 0.95, acc, 2.0 * s)
				_needle(c, ctr, float(g["alt_a"]), gr * 0.82, fam["needle"], s)
			1:
				_ticks(c, ctr, gr, acc, s)
				_needle(c, ctr, float(g["spd_a"]), gr * 0.82, fam["needle"], s)
			2:                                                           # the compass card turns, the lubber line stays at the top
				var hd := float(g["hdg_a"])
				for k in 12:
					var a2 := hd + TAU * float(k) / 12.0
					c.draw_line(ctr + _dir(a2) * gr * 0.8, ctr + _dir(a2) * gr * 0.95, acc if k % 3 == 0 else Color(acc, 0.5), 2.0 * s)
				var card := ["N", "E", "S", "W"]
				for k in 4:
					var a3 := hd + TAU * float(k) / 4.0
					var tp := ctr + _dir(a3) * gr * 0.58
					c.draw_string(font, tp + Vector2(-6.0 * s, 6.0 * s), card[k], HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(gr * 0.34), RED if k == 0 else Color(1, 1, 1))
				c.draw_colored_polygon(PackedVector2Array([ctr + Vector2(0.0, -gr * 0.98), ctr + Vector2(-5.0 * s, -gr * 0.78), ctr + Vector2(5.0 * s, -gr * 0.78)]), Color(1.0, 0.8, 0.2))
			3:
				_band(c, ctr, gr, 0.9, 1.0, GREEN, s)
				_ticks(c, ctr, gr, acc, s)
				_needle(c, ctr, float(g["rpm_a"]), gr * 0.82, fam["needle"], s)
			4:
				_band(c, ctr, gr, 0.0, 0.3, RED, s)
				_ticks(c, ctr, gr, acc, s)
				_needle(c, ctr, float(g["hull_a"]), gr * 0.82, RED if float(g["hull"]) < 30.0 else fam["needle"], s)
		c.draw_string(font, Vector2(ctr.x - cell * 0.5, ctr.y + gr + fs + 4.0 * s), texts[i], HORIZONTAL_ALIGNMENT_CENTER, cell, fs, Color(1, 1, 1))
		if i != 2:                                                       # the name in the dial's lower third, under the needle's hub (the compass names itself with its letters)
			c.draw_string(font, Vector2(ctr.x - cell * 0.5, ctr.y + gr * 0.62), labels[i], HORIZONTAL_ALIGNMENT_CENTER, cell, int(maxf(11.0 * s, gr * 0.22)), Color(acc, 0.85))


static func _dir(a: float) -> Vector2:
	return Vector2(sin(a), -cos(a))


static func _needle(c: Control, ctr: Vector2, a: float, ln: float, col: Color, s: float) -> void:
	c.draw_line(ctr - _dir(a) * ln * 0.18, ctr + _dir(a) * ln, col, 3.5 * s)
	c.draw_circle(ctr, 4.0 * s, col)


static func _ticks(c: Control, ctr: Vector2, gr: float, col: Color, s: float) -> void:
	for k in 7:
		var a := -PI * 0.75 + PI * 1.5 * float(k) / 6.0
		c.draw_line(ctr + _dir(a) * gr * 0.78, ctr + _dir(a) * gr * 0.95, col, 2.0 * s)


static func _band(c: Control, ctr: Vector2, gr: float, f0: float, f1: float, col: Color, s: float) -> void:
	var a0 := -PI * 0.75 + PI * 1.5 * f0
	var a1 := -PI * 0.75 + PI * 1.5 * f1
	# draw_arc: angle 0 = +x, growing clockwise on screen (y down); the gauges' 0 is up, hence the quarter turn
	c.draw_arc(ctr, gr * 0.88, a0 - PI * 0.5, a1 - PI * 0.5, 10, Color(col, 0.85), 5.0 * s, false)
