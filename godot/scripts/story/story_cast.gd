class_name StoryCast
extends RefCounted
## The named characters of THE LONG TOMORROW (docs/STORY.md): who speaks, in which colour, and a simple portrait for each. Pure data and canvas drawing, no scene tree.
##
## A speaker id is the uppercase string the story layer already uses ("KESTREL", "ORACLE", "VAEL BROADCAST" plus RIVET, IRIS, BASALT, VOSS). `color()` is the subtitle colour
## (StoryView.speaker_color asks here first), `draw_portrait()` paints the bust into a rectangle of any canvas item: every human is the SAME base bust (neck, shoulders, head,
## ears, brows, eyes, mouth) varied by a `look` (skin, hair style and colour, suit, accent, one extra such as goggles or a scar), so the cast reads as one family of art at
## 48 px (the radio plate) and at 160 px (the briefing). ORACLE is a ring of light and the hive's voice has three eyes: they have no human bust.

const HERO := "KESTREL"                    ## the hero is replaceable: one id here, the look below
const ORACLE := "ORACLE"
const VAEL := "VAEL BROADCAST"

## id -> {name, role, color, look}. `look`: skin, hair, hair_style (short bob cap crop swept bald), suit, accent, extra (visor goggles glasses scar pin eyes3 ring), beard.
const CAST := {
	"KESTREL": {"name": "KESTREL", "role": "WARDEN OF LAST LIGHT", "color": Color(1.0, 0.72, 0.25),
		"look": {"skin": Color(0.78, 0.58, 0.46), "hair": Color(0.1, 0.09, 0.11), "hair_style": "short", "suit": Color(0.16, 0.17, 0.2), "accent": Color(1.0, 0.72, 0.25), "extra": "visor"}},
	"ORACLE": {"name": "ORACLE", "role": "THE RIG'S MIND", "color": Color(0.45, 0.95, 1.0),
		"look": {"skin": Color(0.45, 0.95, 1.0), "hair": Color(0.45, 0.95, 1.0), "hair_style": "bald", "suit": Color(0.05, 0.12, 0.16), "accent": Color(0.45, 0.95, 1.0), "extra": "ring"}},
	"RIVET": {"name": "RIVET", "role": "HARBOUR MECHANIC", "color": Color(1.0, 0.55, 0.2),
		"look": {"skin": Color(0.55, 0.38, 0.3), "hair": Color(0.2, 0.1, 0.06), "hair_style": "cap", "suit": Color(0.85, 0.4, 0.1), "accent": Color(0.95, 0.85, 0.3), "extra": "goggles"}},
	"IRIS": {"name": "DR. IRIS VANCE", "role": "PHYSICIST", "color": Color(0.72, 0.55, 1.0),
		"look": {"skin": Color(0.92, 0.76, 0.66), "hair": Color(0.78, 0.8, 0.86), "hair_style": "bob", "suit": Color(0.85, 0.86, 0.9), "accent": Color(0.72, 0.55, 1.0), "extra": "glasses"}},
	"BASALT": {"name": "CAPTAIN BASALT", "role": "EASTFIELD PILOT", "color": Color(0.45, 0.9, 0.55),
		"look": {"skin": Color(0.66, 0.47, 0.36), "hair": Color(0.6, 0.6, 0.62), "hair_style": "crop", "suit": Color(0.32, 0.36, 0.22), "accent": Color(0.45, 0.9, 0.55), "extra": "scar", "beard": true}},
	"VOSS": {"name": "DIRECTOR VOSS", "role": "MERIDIAN AUTHORITY", "color": Color(1.0, 0.3, 0.32),
		"look": {"skin": Color(0.9, 0.74, 0.64), "hair": Color(0.92, 0.92, 0.94), "hair_style": "swept", "suit": Color(0.3, 0.32, 0.36), "accent": Color(1.0, 0.3, 0.32), "extra": "pin"}},
	"VAEL BROADCAST": {"name": "THE HIVE", "role": "VAEL BROADCAST", "color": Color(1.0, 0.25, 0.75),
		"look": {"skin": Color(0.34, 0.16, 0.42), "hair": Color(1.0, 0.25, 0.75), "hair_style": "bald", "suit": Color(0.1, 0.05, 0.14), "accent": Color(1.0, 0.25, 0.75), "extra": "eyes3"}},
}
const ORDER: Array[String] = ["KESTREL", "ORACLE", "RIVET", "IRIS", "BASALT", "VOSS", "VAEL BROADCAST"]


static func has(id: String) -> bool:
	return CAST.has(id)


static func color(id: String) -> Color:
	return (CAST[id]["color"] as Color) if CAST.has(id) else Color(1.0, 0.3, 0.32)


static func name_of(id: String) -> String:
	return str(CAST[id]["name"]) if CAST.has(id) else id


static func role_of(id: String) -> String:
	return str(CAST[id]["role"]) if CAST.has(id) else ""


static func look_of(id: String) -> Dictionary:
	return CAST[id]["look"] if CAST.has(id) else {}


# --- portraits ---------------------------------------------------------------------------------------------------------------------

static func _ellipse(c: Vector2, rx: float, ry: float, n := 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	ci.draw_colored_polygon(pts, col)


## Paints the portrait of `id` into `r` (clipped by the plate it draws, no clip needed: everything stays inside). `t` animates ORACLE's ring and the hive's eyes (seconds); `alpha` fades it.
static func draw_portrait(ci: CanvasItem, r: Rect2, id: String, t := 0.0, alpha := 1.0) -> void:
	if not CAST.has(id):
		return
	var look: Dictionary = CAST[id]["look"]
	var col: Color = CAST[id]["color"]
	var s := minf(r.size.x, r.size.y)
	var c := r.position + r.size * 0.5
	# plate: dark, a vertical wash of the speaker's colour, a thin frame
	ci.draw_rect(r, Color(0.02, 0.04, 0.06, 0.92 * alpha))
	var wash := Color(col.r, col.g, col.b, 0.22 * alpha)
	ci.draw_rect(Rect2(r.position + Vector2(0.0, s * 0.45), Vector2(r.size.x, s * 0.55)), wash)
	var extra := str(look.get("extra", ""))
	if id == HERO and _draw_hero_render(ci, r, alpha):
		pass                                                 # the real hero, rendered from his kit (scripts/characters/hero_portrait.gd)
	elif extra == "ring":
		_draw_oracle(ci, c, s, col, t, alpha)
	elif extra == "eyes3":
		_draw_vael(ci, c, s, look, col, t, alpha)
	else:
		_draw_human(ci, r, c, s, look, extra, alpha)
	ci.draw_rect(r, Color(col.r, col.g, col.b, 0.9 * alpha), false, maxf(1.0, s * 0.03))


## The hero's portrait is a render of the hero in hand (wave 112): the committed picture for the default look, a live render of the player's own look in the menus. False when there is none
## yet (the drawn bust below is the fallback).
static func _draw_hero_render(ci: CanvasItem, r: Rect2, alpha: float) -> bool:
	var pr: Variant = Game.progress
	var tex := HeroPortrait.for_look(pr.get(&"hero") as HeroLook if pr != null else null, ci)
	if tex == null:
		return false
	HeroPortrait.draw_into(ci, tex, r, Color(1, 1, 1, alpha))
	return true


## The cheap form for the in-game radio subtitle (one draw call, the phone's draw budget): a disc in the speaker's colour. Cutscenes and the board card draw the full portrait.
static func draw_badge(ci: CanvasItem, r: Rect2, id: String, alpha := 1.0) -> void:
	if not CAST.has(id):
		return
	var col: Color = CAST[id]["color"]
	ci.draw_circle(r.position + r.size * 0.5, minf(r.size.x, r.size.y) * 0.36, Color(col.r, col.g, col.b, 0.8 * alpha))


static func _draw_human(ci: CanvasItem, r: Rect2, c: Vector2, s: float, look: Dictionary, extra: String, alpha: float) -> void:
	var skin: Color = look["skin"]
	var hair: Color = look["hair"]
	var suit: Color = look["suit"]
	var accent: Color = look["accent"]
	skin.a = alpha
	hair.a = alpha
	suit.a = alpha
	accent.a = alpha
	var shade := Color(skin.r * 0.72, skin.g * 0.7, skin.b * 0.7, alpha)
	var head_c := c + Vector2(0.0, -s * 0.07)
	var hx := s * 0.19
	var hy := s * 0.235
	# shoulders and collar (the suit), neck, then the head
	_poly(ci, PackedVector2Array([Vector2(r.position.x + s * 0.08, r.end.y), Vector2(r.position.x + s * 0.14, c.y + s * 0.3), Vector2(c.x - s * 0.17, c.y + s * 0.2),
			Vector2(c.x + s * 0.17, c.y + s * 0.2), Vector2(r.end.x - s * 0.14, c.y + s * 0.3), Vector2(r.end.x - s * 0.08, r.end.y)]), suit)
	ci.draw_rect(Rect2(c.x - s * 0.07, head_c.y + hy * 0.7, s * 0.14, s * 0.2), shade)
	_poly(ci, PackedVector2Array([Vector2(c.x - s * 0.17, c.y + s * 0.2), Vector2(c.x, c.y + s * 0.34), Vector2(c.x + s * 0.17, c.y + s * 0.2), Vector2(c.x + s * 0.07, c.y + s * 0.17),
			Vector2(c.x, c.y + s * 0.24), Vector2(c.x - s * 0.07, c.y + s * 0.17)]), accent)
	# hair behind the head (long styles), ears
	var style := str(look.get("hair_style", "short"))
	if style == "bob":
		_poly(ci, _ellipse(head_c + Vector2(0.0, s * 0.04), hx * 1.28, hy * 1.12), hair)
	ci.draw_circle(head_c + Vector2(-hx * 0.98, s * 0.015), s * 0.034, shade)
	ci.draw_circle(head_c + Vector2(hx * 0.98, s * 0.015), s * 0.034, shade)
	_poly(ci, _ellipse(head_c, hx, hy), skin)
	if bool(look.get("beard", false)):
		_poly(ci, PackedVector2Array([head_c + Vector2(-hx * 0.92, hy * 0.1), head_c + Vector2(-hx * 0.7, hy * 0.82), head_c + Vector2(0.0, hy * 1.04), head_c + Vector2(hx * 0.7, hy * 0.82),
				head_c + Vector2(hx * 0.92, hy * 0.1), head_c + Vector2(hx * 0.5, hy * 0.38), head_c + Vector2(0.0, hy * 0.32), head_c + Vector2(-hx * 0.5, hy * 0.38)]), hair.darkened(0.15))
	# hair on top
	match style:
		"short":
			_poly(ci, PackedVector2Array([head_c + Vector2(-hx * 1.0, -hy * 0.1), head_c + Vector2(-hx * 0.86, -hy * 0.78), head_c + Vector2(-hx * 0.2, -hy * 1.08),
					head_c + Vector2(hx * 0.6, -hy * 0.98), head_c + Vector2(hx * 1.0, -hy * 0.1), head_c + Vector2(hx * 0.62, -hy * 0.5), head_c + Vector2(-hx * 0.2, -hy * 0.62),
					head_c + Vector2(-hx * 0.7, -hy * 0.42)]), hair)
		"bob":
			_poly(ci, PackedVector2Array([head_c + Vector2(-hx * 1.18, hy * 0.5), head_c + Vector2(-hx * 1.1, -hy * 0.7), head_c + Vector2(0.0, -hy * 1.12), head_c + Vector2(hx * 1.1, -hy * 0.7),
					head_c + Vector2(hx * 1.18, hy * 0.5), head_c + Vector2(hx * 0.85, hy * 0.5), head_c + Vector2(hx * 0.85, -hy * 0.35), head_c + Vector2(-hx * 0.3, -hy * 0.58),
					head_c + Vector2(-hx * 0.85, -hy * 0.2), head_c + Vector2(-hx * 0.85, hy * 0.5)]), hair)
		"crop":
			_poly(ci, PackedVector2Array([head_c + Vector2(-hx * 0.98, -hy * 0.12), head_c + Vector2(-hx * 0.8, -hy * 0.86), head_c + Vector2(0.0, -hy * 0.98), head_c + Vector2(hx * 0.8, -hy * 0.86),
					head_c + Vector2(hx * 0.98, -hy * 0.12), head_c + Vector2(hx * 0.66, -hy * 0.58), head_c + Vector2(-hx * 0.66, -hy * 0.58)]), hair)
		"swept":
			_poly(ci, PackedVector2Array([head_c + Vector2(-hx * 1.0, -hy * 0.05), head_c + Vector2(-hx * 0.9, -hy * 0.82), head_c + Vector2(hx * 0.1, -hy * 1.16), head_c + Vector2(hx * 1.1, -hy * 0.92),
					head_c + Vector2(hx * 0.98, -hy * 0.1), head_c + Vector2(hx * 0.5, -hy * 0.56), head_c + Vector2(-hx * 0.3, -hy * 0.7), head_c + Vector2(-hx * 0.7, -hy * 0.38)]), hair)
		"cap":
			_poly(ci, PackedVector2Array([head_c + Vector2(-hx * 1.04, -hy * 0.2), head_c + Vector2(-hx * 0.9, -hy * 0.92), head_c + Vector2(0.0, -hy * 1.1), head_c + Vector2(hx * 0.9, -hy * 0.92),
					head_c + Vector2(hx * 1.04, -hy * 0.2)]), suit.lightened(0.05))
			ci.draw_rect(Rect2(head_c.x - hx * 1.05, head_c.y - hy * 0.3, hx * 2.5, hy * 0.16), suit.darkened(0.25))           # the brim, forward
	# face: brows, eyes, mouth
	var ey := head_c.y - hy * 0.04
	var eye_dx := hx * 0.42
	var white := Color(0.95, 0.96, 0.98, alpha)
	var dark := Color(0.06, 0.05, 0.07, alpha)
	for sx in [-1.0, 1.0]:
		var ex := head_c.x + float(sx) * eye_dx
		ci.draw_rect(Rect2(ex - s * 0.045, ey - s * 0.075, s * 0.09, s * 0.018), hair.darkened(0.3))        # brow
		ci.draw_rect(Rect2(ex - s * 0.04, ey - s * 0.02, s * 0.08, s * 0.036), white)
		ci.draw_circle(Vector2(ex, ey - s * 0.002), s * 0.017, dark)
	ci.draw_rect(Rect2(head_c.x - s * 0.05, head_c.y + hy * 0.5, s * 0.1, s * 0.014), Color(shade.r * 0.7, shade.g * 0.55, shade.b * 0.55, alpha))
	ci.draw_rect(Rect2(head_c.x - s * 0.012, ey + s * 0.03, s * 0.024, s * 0.07), shade)                     # nose
	match extra:
		"visor":
			ci.draw_rect(Rect2(head_c.x - hx * 0.98, ey - s * 0.05, hx * 1.96, s * 0.07), Color(accent.r, accent.g, accent.b, 0.8 * alpha))
		"goggles":
			for sx in [-1.0, 1.0]:
				ci.draw_circle(Vector2(head_c.x + float(sx) * eye_dx, ey - s * 0.07), s * 0.062, Color(0.1, 0.1, 0.12, alpha))
				ci.draw_circle(Vector2(head_c.x + float(sx) * eye_dx, ey - s * 0.07), s * 0.044, Color(accent.r, accent.g, accent.b, 0.85 * alpha))
			ci.draw_rect(Rect2(head_c.x - hx, ey - s * 0.085, hx * 2.0, s * 0.02), Color(0.1, 0.1, 0.12, alpha))
		"glasses":
			for sx in [-1.0, 1.0]:
				ci.draw_arc(Vector2(head_c.x + float(sx) * eye_dx, ey - s * 0.002), s * 0.06, 0.0, TAU, 14, Color(0.15, 0.15, 0.2, alpha), maxf(1.0, s * 0.014))
			ci.draw_line(Vector2(head_c.x - eye_dx + s * 0.06, ey), Vector2(head_c.x + eye_dx - s * 0.06, ey), Color(0.15, 0.15, 0.2, alpha), maxf(1.0, s * 0.014))
		"scar":
			ci.draw_line(head_c + Vector2(hx * 0.6, -hy * 0.35), head_c + Vector2(hx * 0.3, hy * 0.28), Color(0.85, 0.5, 0.45, alpha), maxf(1.0, s * 0.016))
		"pin":
			ci.draw_circle(Vector2(c.x + s * 0.17, c.y + s * 0.3), s * 0.024, Color(accent.r, accent.g, accent.b, alpha))


static func _draw_oracle(ci: CanvasItem, c: Vector2, s: float, col: Color, t: float, alpha: float) -> void:
	var pulse := 0.5 + 0.5 * sin(t * 2.4)
	for i in 4:
		var rad := s * (0.14 + 0.085 * float(i)) * (1.0 + 0.03 * pulse * float(i))
		ci.draw_arc(c, rad, 0.0, TAU, 40, Color(col.r, col.g, col.b, (0.95 - 0.2 * float(i)) * alpha), maxf(1.5, s * (0.036 - 0.006 * float(i))))
	ci.draw_circle(c, s * (0.07 + 0.012 * pulse), Color(col.r, col.g, col.b, 0.9 * alpha))
	ci.draw_circle(c, s * 0.03, Color(1, 1, 1, alpha))
	for k in 6:                                                                   # six sparks drifting round the ring
		var a := t * 0.9 + TAU * float(k) / 6.0
		ci.draw_circle(c + Vector2(cos(a), sin(a)) * s * 0.4, s * 0.016, Color(col.r, col.g, col.b, 0.8 * alpha))


static func _draw_vael(ci: CanvasItem, c: Vector2, s: float, look: Dictionary, col: Color, t: float, alpha: float) -> void:
	var skin: Color = look["skin"]
	skin.a = alpha
	var head_c := c + Vector2(0.0, -s * 0.04)
	_poly(ci, PackedVector2Array([head_c + Vector2(0.0, -s * 0.38), head_c + Vector2(s * 0.2, -s * 0.12), head_c + Vector2(s * 0.14, s * 0.22), head_c + Vector2(0.0, s * 0.36),
			head_c + Vector2(-s * 0.14, s * 0.22), head_c + Vector2(-s * 0.2, -s * 0.12)]), skin)
	for i in 3:
		var p := head_c + Vector2((float(i) - 1.0) * s * 0.11, -s * 0.06 + (0.0 if i == 1 else s * 0.04))
		var glow := 0.65 + 0.35 * sin(t * 3.0 + float(i) * 1.3)
		ci.draw_circle(p, s * 0.052, Color(col.r, col.g, col.b, 0.35 * alpha))
		ci.draw_circle(p, s * 0.03, Color(col.r, col.g, col.b, glow * alpha))
	ci.draw_line(head_c + Vector2(0.0, -s * 0.38), head_c + Vector2(0.0, -s * 0.24), Color(col.r, col.g, col.b, 0.8 * alpha), maxf(1.0, s * 0.02))
