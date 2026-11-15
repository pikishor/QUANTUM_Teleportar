class_name SnakeIcons
extends RefCounted
## The pictures of the SNAKE POWERS (wave 115, combat side): one drawn icon for each of the ten verbs and twelve bombs, painted with canvas primitives (resolution independent, no texture memory, no
## atlas page): a serpent in the colour of the power plus the one thing that says what the power does (a net, a shield, a bomb ball with a coil, a swarm, a snowflake, a cobra with a bolt ...).
## Used by the weapon wheel discs, the WEAPON button face, the HUD plate and the SNAKE screen: `SnakeIcons.draw(canvas, id, rect, colour)` fits the picture into `rect` (square, centred).
## `colour` only carries the opacity and a tint towards the power's own colour (the wheel dims a locked power with it).

const WHITE := Color(1.0, 1.0, 1.0)


static func handles(id: StringName) -> bool:
	return SnakeRows.has(id)


static func draw(c: CanvasItem, id: StringName, r: Rect2, col: Color) -> void:
	if not SnakeRows.has(id):
		return
	var s := minf(r.size.x, r.size.y)
	var box := Rect2(r.get_center() - Vector2(s, s) * 0.5, Vector2(s, s))
	var base: Color = SnakeRows.color_of(id)
	var main := Color(base.r, base.g, base.b, col.a)
	var light := Color(minf(base.r + 0.45, 1.0), minf(base.g + 0.45, 1.0), minf(base.b + 0.45, 1.0), col.a)
	var dark := Color(base.r * 0.35, base.g * 0.35, base.b * 0.35, col.a * 0.9)
	var ic := _Pen.new()
	ic.c = c
	ic.box = box
	ic.main = main
	ic.light = light
	ic.dark = dark
	ic.w = maxf(s * 0.055, 1.6)
	var icon := StringName(SnakeRows.row(id).get("icon", &"pull"))
	match icon:
		&"pull": _pull(ic)
		&"grab": _grab(ic)
		&"disarm": _disarm(ic)
		&"yank": _yank(ic)
		&"net": _net(ic)
		&"lash": _lash(ic)
		&"shield": _shield(ic)
		&"decoy": _decoy(ic)
		&"trap": _trap(ic)
		&"guard": _guard(ic)
		&"coil": _bomb(ic, &"coil")
		&"swarm": _swarm(ic)
		&"flare": _flare(ic)
		&"freeze": _freeze(ic)
		&"seeker": _seeker(ic)
		&"chain": _chain(ic)
		&"cluster": _cluster(ic)
		&"constrict": _constrict(ic)
		&"burrow": _burrow(ic)
		&"gravity": _gravity(ic)
		&"storm": _storm(ic)
		&"mega": _mega(ic)
		_: _serpent(ic, [Vector2(0.2, 0.7), Vector2(0.4, 0.4), Vector2(0.6, 0.7), Vector2(0.8, 0.35)], true)


class _Pen extends RefCounted:
	var c: CanvasItem
	var box: Rect2
	var main: Color
	var light: Color
	var dark: Color
	var w := 2.0

	func p(x: float, y: float) -> Vector2:
		return box.position + Vector2(x, y) * box.size

	func k(v: float) -> float:
		return v * box.size.x


## A serpent along the normalised points: a thick polyline, round ends, a head (a flat arrow with an eye) when `head`.
static func _serpent(ic: _Pen, pts: Array, head := true, width := 1.0, col := Color(0, 0, 0, 0)) -> void:
	var line := PackedVector2Array()
	for q: Vector2 in pts:
		line.append(ic.p(q.x, q.y))
	var m := col if col.a > 0.0 else ic.main
	ic.c.draw_polyline(line, ic.dark, ic.w * 2.6 * width, true)
	ic.c.draw_polyline(line, m, ic.w * 1.8 * width, true)
	ic.c.draw_polyline(line, ic.light, ic.w * 0.5 * width, true)
	if head and line.size() >= 2:
		var tip := line[line.size() - 1]
		var dir := (tip - line[line.size() - 2]).normalized()
		var side := Vector2(-dir.y, dir.x)
		var hl := ic.k(0.12) * width
		var hw := ic.k(0.065) * width
		ic.c.draw_colored_polygon(PackedVector2Array([tip + dir * hl, tip + side * hw, tip - dir * hl * 0.2, tip - side * hw]), ic.main if col.a <= 0.0 else col)
		ic.c.draw_circle(tip + dir * hl * 0.15 + side * hw * 0.35, maxf(ic.k(0.014), 0.8), WHITE)
		ic.c.draw_circle(tip + dir * hl * 0.15 - side * hw * 0.35, maxf(ic.k(0.014), 0.8), WHITE)


static func _wave(x0: float, y0: float, x1: float, y1: float, amp: float, turns: float, n := 14) -> Array:
	var out: Array = []
	var d := Vector2(x1 - x0, y1 - y0)
	var nrm := Vector2(-d.y, d.x).normalized()
	for i in n + 1:
		var u := float(i) / float(n)
		out.append(Vector2(x0, y0) + d * u + nrm * sin(u * TAU * turns) * amp * sin(u * PI))
	return out


static func _ring(ic: _Pen, cx: float, cy: float, r: float, col: Color, width := 1.0, a0 := 0.0, a1 := TAU) -> void:
	ic.c.draw_arc(ic.p(cx, cy), ic.k(r), a0, a1, 28, col, ic.w * width, true)


static func _dot(ic: _Pen, x: float, y: float, r: float, col: Color) -> void:
	ic.c.draw_circle(ic.p(x, y), ic.k(r), col)


static func _poly(ic: _Pen, pts: Array, col: Color) -> void:
	var line := PackedVector2Array()
	for q: Vector2 in pts:
		line.append(ic.p(q.x, q.y))
	ic.c.draw_colored_polygon(line, col)


static func _line(ic: _Pen, a: Vector2, b: Vector2, col: Color, width := 1.0) -> void:
	ic.c.draw_line(ic.p(a.x, a.y), ic.p(b.x, b.y), col, ic.w * width, true)


# --- the ten verbs ---------------------------------------------------------------------------------------------------------------------

static func _pull(ic: _Pen) -> void:
	_serpent(ic, _wave(0.1, 0.62, 0.62, 0.42, 0.1, 1.5), true)
	_poly(ic, [Vector2(0.9, 0.5), Vector2(0.76, 0.34), Vector2(0.76, 0.44), Vector2(0.62, 0.44), Vector2(0.62, 0.56), Vector2(0.76, 0.56), Vector2(0.76, 0.66)], ic.light)
	_dot(ic, 0.14, 0.62, 0.05, ic.light)


static func _grab(ic: _Pen) -> void:
	_poly(ic, [Vector2(0.38, 0.5), Vector2(0.62, 0.5), Vector2(0.62, 0.76), Vector2(0.38, 0.76)], ic.dark)
	_serpent(ic, [Vector2(0.28, 0.82), Vector2(0.72, 0.7), Vector2(0.3, 0.62), Vector2(0.7, 0.52), Vector2(0.34, 0.42), Vector2(0.58, 0.24)], true)
	_line(ic, Vector2(0.5, 0.1), Vector2(0.5, 0.26), ic.light, 0.8)


static func _disarm(ic: _Pen) -> void:
	_poly(ic, [Vector2(0.62, 0.44), Vector2(0.92, 0.44), Vector2(0.92, 0.56), Vector2(0.78, 0.56), Vector2(0.74, 0.72), Vector2(0.64, 0.72), Vector2(0.66, 0.56), Vector2(0.62, 0.56)], ic.light)
	_serpent(ic, _wave(0.08, 0.7, 0.64, 0.5, 0.12, 1.2), true)


static func _yank(ic: _Pen) -> void:
	_poly(ic, [Vector2(0.52, 0.28), Vector2(0.9, 0.28), Vector2(0.9, 0.7), Vector2(0.52, 0.7)], ic.dark)
	_line(ic, Vector2(0.52, 0.28), Vector2(0.9, 0.7), ic.main, 0.7)
	_serpent(ic, _wave(0.05, 0.76, 0.58, 0.46, 0.1, 1.0), true)
	_line(ic, Vector2(0.68, 0.14), Vector2(0.78, 0.22), ic.light, 0.7)
	_line(ic, Vector2(0.84, 0.12), Vector2(0.86, 0.22), ic.light, 0.7)


static func _net(ic: _Pen) -> void:
	for i in 5:
		var u := 0.16 + 0.17 * float(i)
		_line(ic, Vector2(u, 0.2), Vector2(u, 0.8), ic.main, 0.55)
		_line(ic, Vector2(0.16, u + 0.04), Vector2(0.84, u + 0.04), ic.main, 0.55)
	_ring(ic, 0.5, 0.5, 0.4, ic.light, 0.9)
	_serpent(ic, [Vector2(0.14, 0.82), Vector2(0.3, 0.9), Vector2(0.5, 0.82), Vector2(0.7, 0.9), Vector2(0.86, 0.8)], true, 0.7)


static func _lash(ic: _Pen) -> void:
	_serpent(ic, [Vector2(0.1, 0.84), Vector2(0.3, 0.78), Vector2(0.5, 0.58), Vector2(0.66, 0.34), Vector2(0.9, 0.2)], true)
	_serpent(ic, [Vector2(0.18, 0.92), Vector2(0.4, 0.86), Vector2(0.58, 0.72), Vector2(0.8, 0.54)], false, 0.55, ic.light)
	_line(ic, Vector2(0.88, 0.1), Vector2(0.96, 0.18), WHITE, 0.7)
	_line(ic, Vector2(0.78, 0.08), Vector2(0.8, 0.18), WHITE, 0.7)


static func _shield(ic: _Pen) -> void:
	_poly(ic, [Vector2(0.5, 0.12), Vector2(0.84, 0.24), Vector2(0.8, 0.56), Vector2(0.5, 0.88), Vector2(0.2, 0.56), Vector2(0.16, 0.24)], ic.dark)
	_ring(ic, 0.5, 0.5, 0.34, ic.main, 0.9, -PI * 0.2, PI * 1.1)
	_ring(ic, 0.5, 0.5, 0.24, ic.light, 0.7, PI * 0.9, PI * 2.1)
	_dot(ic, 0.5, 0.5, 0.07, ic.light)


static func _decoy(ic: _Pen) -> void:
	_dot(ic, 0.62, 0.3, 0.1, ic.dark)
	_poly(ic, [Vector2(0.46, 0.42), Vector2(0.78, 0.42), Vector2(0.84, 0.82), Vector2(0.4, 0.82)], ic.dark)
	_dot(ic, 0.4, 0.34, 0.1, ic.main)
	_poly(ic, [Vector2(0.24, 0.46), Vector2(0.56, 0.46), Vector2(0.62, 0.86), Vector2(0.18, 0.86)], ic.main)
	_serpent(ic, [Vector2(0.3, 0.78), Vector2(0.5, 0.7), Vector2(0.3, 0.62), Vector2(0.5, 0.54)], false, 0.6, ic.light)


static func _trap(ic: _Pen) -> void:
	ic.c.draw_arc(ic.p(0.5, 0.66), ic.k(0.34), 0.0, TAU, 28, ic.dark, ic.w * 2.2, true)
	var pts: Array = []
	for i in 22:
		var u := float(i) / 21.0
		var a := u * TAU * 2.3
		var rr := 0.3 * (1.0 - u * 0.75)
		pts.append(Vector2(0.5 + cos(a) * rr, 0.66 + sin(a) * rr * 0.42))
	_serpent(ic, pts, true)
	_poly(ic, [Vector2(0.46, 0.2), Vector2(0.54, 0.2), Vector2(0.5, 0.4)], ic.light)


static func _guard(ic: _Pen) -> void:
	_serpent(ic, _wave(0.08, 0.3, 0.48, 0.2, 0.06, 1.2), true, 0.72)
	_serpent(ic, _wave(0.08, 0.56, 0.62, 0.5, 0.07, 1.3), true, 0.85)
	_serpent(ic, _wave(0.08, 0.82, 0.48, 0.78, 0.06, 1.2), true, 0.72)
	_ring(ic, 0.74, 0.5, 0.15, ic.light, 0.7)
	_dot(ic, 0.74, 0.5, 0.05, ic.light)


# --- the twelve bombs ----------------------------------------------------------------------------------------------------------------------

static func _ball(ic: _Pen, x: float, y: float, r: float) -> void:
	_dot(ic, x, y, r, ic.dark)
	_ring(ic, x, y, r, ic.main, 0.8)


static func _bomb(ic: _Pen, kind: StringName) -> void:
	_ball(ic, 0.5, 0.58, 0.28)
	var pts: Array = []
	for i in 18:
		var u := float(i) / 17.0
		var a := u * TAU * 1.6 + 0.4
		pts.append(Vector2(0.5 + cos(a) * 0.3 * (0.4 + 0.6 * sin(u * PI)), 0.58 + sin(a) * 0.3 * (0.4 + 0.6 * sin(u * PI)) - u * 0.04))
	_serpent(ic, pts, true, 0.8)
	_line(ic, Vector2(0.5, 0.3), Vector2(0.58, 0.16), ic.light, 0.8)
	_dot(ic, 0.6, 0.14, 0.04, WHITE)


static func _swarm(ic: _Pen) -> void:
	_serpent(ic, _wave(0.06, 0.22, 0.52, 0.16, 0.05, 1.2), true, 0.55)
	_serpent(ic, _wave(0.1, 0.42, 0.7, 0.36, 0.06, 1.4), true, 0.55)
	_serpent(ic, _wave(0.06, 0.62, 0.6, 0.66, 0.06, 1.3), true, 0.55)
	_serpent(ic, _wave(0.1, 0.82, 0.8, 0.8, 0.05, 1.5), true, 0.55)
	_serpent(ic, _wave(0.4, 0.5, 0.94, 0.52, 0.06, 1.2), true, 0.55)
	_ball(ic, 0.1, 0.5, 0.07)


static func _flare(ic: _Pen) -> void:
	for i in 10:
		var a := TAU * float(i) / 10.0
		var l0 := 0.2
		var l1 := 0.44 if i % 2 == 0 else 0.34
		_line(ic, Vector2(0.5 + cos(a) * l0, 0.5 + sin(a) * l0), Vector2(0.5 + cos(a) * l1, 0.5 + sin(a) * l1), ic.light, 0.9)
	_dot(ic, 0.5, 0.5, 0.17, ic.main)
	_dot(ic, 0.5, 0.5, 0.09, WHITE)
	_serpent(ic, [Vector2(0.16, 0.86), Vector2(0.3, 0.78), Vector2(0.4, 0.68)], true, 0.6)


static func _freeze(ic: _Pen) -> void:
	for i in 3:
		var a := PI * float(i) / 3.0
		_line(ic, Vector2(0.5 + cos(a) * 0.4, 0.5 + sin(a) * 0.4), Vector2(0.5 - cos(a) * 0.4, 0.5 - sin(a) * 0.4), ic.light, 0.9)
		for s in [-1.0, 1.0]:
			var tip := Vector2(0.5 + cos(a) * 0.28 * s, 0.5 + sin(a) * 0.28 * s)
			_line(ic, tip, tip + Vector2(cos(a + 0.9 * s), sin(a + 0.9 * s)) * 0.1, ic.main, 0.7)
			_line(ic, tip, tip + Vector2(cos(a - 0.9 * s), sin(a - 0.9 * s)) * 0.1, ic.main, 0.7)
	_serpent(ic, _wave(0.1, 0.86, 0.9, 0.84, 0.05, 1.5), true, 0.55)


static func _seeker(ic: _Pen) -> void:
	_serpent(ic, _wave(0.06, 0.8, 0.6, 0.62, 0.1, 1.4), true)
	_ring(ic, 0.76, 0.34, 0.2, ic.light, 0.8)
	_ring(ic, 0.76, 0.34, 0.1, ic.main, 0.7)
	_line(ic, Vector2(0.76, 0.06), Vector2(0.76, 0.2), ic.light, 0.7)
	_line(ic, Vector2(0.76, 0.48), Vector2(0.76, 0.62), ic.light, 0.7)
	_line(ic, Vector2(0.48, 0.34), Vector2(0.62, 0.34), ic.light, 0.7)
	_line(ic, Vector2(0.9, 0.34), Vector2(1.0, 0.34), ic.light, 0.7)


static func _chain(ic: _Pen) -> void:
	_ball(ic, 0.16, 0.7, 0.1)
	_ball(ic, 0.5, 0.3, 0.1)
	_ball(ic, 0.84, 0.7, 0.1)
	_line(ic, Vector2(0.2, 0.62), Vector2(0.42, 0.38), ic.light, 1.0)
	_line(ic, Vector2(0.58, 0.38), Vector2(0.8, 0.62), ic.light, 1.0)
	_poly(ic, [Vector2(0.34, 0.6), Vector2(0.46, 0.48), Vector2(0.42, 0.62), Vector2(0.54, 0.5), Vector2(0.4, 0.8)], ic.main)
	_serpent(ic, _wave(0.2, 0.9, 0.8, 0.9, 0.04, 1.5), true, 0.5)


static func _cluster(ic: _Pen) -> void:
	_ball(ic, 0.3, 0.32, 0.14)
	_ball(ic, 0.7, 0.32, 0.14)
	_ball(ic, 0.3, 0.72, 0.14)
	_ball(ic, 0.7, 0.72, 0.14)
	_ball(ic, 0.5, 0.52, 0.12)
	_serpent(ic, [Vector2(0.3, 0.5), Vector2(0.5, 0.42), Vector2(0.7, 0.5)], false, 0.5, ic.light)


static func _constrict(ic: _Pen) -> void:
	ic.c.draw_arc(ic.p(0.5, 0.58), ic.k(0.4), 0.0, TAU, 28, ic.dark, ic.w * 2.0, true)
	var pts: Array = []
	for i in 26:
		var u := float(i) / 25.0
		var a := u * TAU * 3.0
		var rr := 0.34 * (1.0 - u * 0.7)
		pts.append(Vector2(0.5 + cos(a) * rr, 0.58 + sin(a) * rr * 0.5))
	_serpent(ic, pts, true, 1.05)
	_line(ic, Vector2(0.5, 0.12), Vector2(0.5, 0.3), ic.light, 0.9)
	_poly(ic, [Vector2(0.4, 0.3), Vector2(0.6, 0.3), Vector2(0.5, 0.4)], ic.light)


static func _burrow(ic: _Pen) -> void:
	_poly(ic, [Vector2(0.06, 0.72), Vector2(0.24, 0.5), Vector2(0.4, 0.42), Vector2(0.6, 0.5), Vector2(0.78, 0.7), Vector2(0.96, 0.74), Vector2(0.96, 0.9), Vector2(0.06, 0.9)], ic.dark)
	_serpent(ic, [Vector2(0.16, 0.84), Vector2(0.3, 0.7), Vector2(0.44, 0.52), Vector2(0.56, 0.3)], true, 0.9)
	for q in [Vector2(0.7, 0.62), Vector2(0.82, 0.54), Vector2(0.88, 0.66)]:
		_dot(ic, q.x, q.y, 0.025, ic.light)


static func _gravity(ic: _Pen) -> void:
	var pts: Array = []
	for i in 30:
		var u := float(i) / 29.0
		var a := u * TAU * 2.4
		var rr := 0.44 * (1.0 - u * 0.85)
		pts.append(Vector2(0.5 + cos(a) * rr, 0.5 + sin(a) * rr))
	_serpent(ic, pts, true)
	_dot(ic, 0.5, 0.5, 0.06, WHITE)
	_poly(ic, [Vector2(0.9, 0.12), Vector2(0.94, 0.26), Vector2(0.8, 0.2)], ic.light)


static func _storm(ic: _Pen) -> void:
	_serpent(ic, [Vector2(0.4, 0.92), Vector2(0.42, 0.7), Vector2(0.32, 0.5), Vector2(0.42, 0.3)], true, 1.1)
	_poly(ic, [Vector2(0.24, 0.3), Vector2(0.42, 0.18), Vector2(0.6, 0.3), Vector2(0.42, 0.4)], ic.main)
	_poly(ic, [Vector2(0.7, 0.1), Vector2(0.56, 0.4), Vector2(0.68, 0.4), Vector2(0.6, 0.7), Vector2(0.84, 0.34), Vector2(0.72, 0.34), Vector2(0.82, 0.1)], WHITE)
	_line(ic, Vector2(0.18, 0.7), Vector2(0.1, 0.9), ic.light, 0.8)


static func _mega(ic: _Pen) -> void:
	_serpent(ic, [Vector2(0.1, 0.9), Vector2(0.16, 0.62), Vector2(0.32, 0.46), Vector2(0.52, 0.5), Vector2(0.64, 0.34), Vector2(0.62, 0.16)], true, 1.7)
	for i in 6:
		var a := TAU * float(i) / 6.0
		_line(ic, Vector2(0.5 + cos(a) * 0.4, 0.5 + sin(a) * 0.4), Vector2(0.5 + cos(a) * 0.48, 0.5 + sin(a) * 0.48), ic.light, 0.9)
	_ring(ic, 0.5, 0.5, 0.45, ic.light, 0.6)
