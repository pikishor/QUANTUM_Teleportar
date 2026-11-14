class_name BlastCard
extends Control
## The blast of a weapon drawn TO SCALE for its card (wave 113: "weapon cards show the radius ring to scale beside a person silhouette"): a ground line, the dome of the blast at its true radius with the full
## damage core and the half way mark, a person 1.8 m tall standing at ground zero (red) and another one just outside the edge (white), so a player sees at once whether a frag, a mortar or a black hole
## reaches a man standing there. One Control, no textures, drawn by `_draw` (64 px high and 220 px wide at least, grows with its container).
##   BlastCard.for_weapon(weapon_id) -> BlastCard or null (null for a weapon with no blast)     BlastCard.for_entry(entry) -> BlastCard

const PERSON_H := 1.8
const PERSON_W := 0.5

var entry: Dictionary = {}
var _font: Font


static func for_weapon(id: StringName) -> BlastCard:
	var e := BlastPreview.entry_of(WeaponDefs.def(id), id)
	return null if e.is_empty() else for_entry(e)


static func for_entry(e: Dictionary) -> BlastCard:
	var c := BlastCard.new()
	c.entry = e
	c.custom_minimum_size = Vector2(220.0, 96.0)
	return c


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Pixels per metre for this size: the dome (2 x radius wide, radius high) and the person next to it fit.
func scale_px() -> float:
	return BlastCard.scale_for(entry, size)


static func scale_for(e: Dictionary, sz: Vector2) -> float:
	var r := float(e.get("radius", 5.0))
	var sw := (sz.x - 24.0) / (2.0 * r + 4.0)
	var sh := (sz.y - 24.0) / maxf(r, PERSON_H + 0.2)
	return maxf(minf(sw, sh), 0.5)


func _draw() -> void:
	draw_into(self, Rect2(Vector2.ZERO, size), entry, _font)


## Draws the card into any CanvasItem inside `rect` (the loadout and catalogue screens draw their cards by hand: they call this where the radius picture goes).
static func draw_into(ci: CanvasItem, rect: Rect2, e: Dictionary, font: Font) -> void:
	if e.is_empty():
		return
	var r := float(e["radius"])
	var core := float(e["core"])
	var element := StringName(e["element"])
	var col: Color = BlastElements.color(element, "ring")
	var mid: Color = BlastElements.color(element, "mid")
	var k := scale_for(e, rect.size)
	var o := rect.position
	var ground_y := o.y + rect.size.y - 14.0
	var cx := o.x + 12.0 + r * k + 2.0
	cx = maxf(cx, o.x + 12.0 + r * k)
	# the ground
	ci.draw_line(Vector2(o.x + 4.0, ground_y), Vector2(o.x + rect.size.x - 4.0, ground_y), Color(1.0, 1.0, 1.0, 0.35), 2.0)
	# the dome: a filled half disc, the core brighter, an arc at the radius and at the half
	var pts := PackedVector2Array()
	for i in 33:
		var a := PI * float(i) / 32.0
		pts.append(Vector2(cx - cos(a) * r * k, ground_y - sin(a) * r * k))
	ci.draw_colored_polygon(pts, Color(mid.r, mid.g, mid.b, 0.22))
	if core > 0.05:
		var cp := PackedVector2Array()
		for i in 25:
			var a2 := PI * float(i) / 24.0
			cp.append(Vector2(cx - cos(a2) * core * k, ground_y - sin(a2) * core * k))
		ci.draw_colored_polygon(cp, Color(1.0, 0.95, 0.8, 0.35))
	ci.draw_arc(Vector2(cx, ground_y), r * k, PI, TAU, 40, Color(col.r, col.g, col.b, 0.95), 2.0)
	ci.draw_arc(Vector2(cx, ground_y), r * k * 0.5, PI, TAU, 28, Color(col.r, col.g, col.b, 0.4), 1.0)
	# two people to the same scale: at ground zero and one metre and a half beyond the edge
	_person(ci, Vector2(cx, ground_y), k, Color(1.0, 0.4, 0.3))
	_person(ci, Vector2(cx + (r + 1.5) * k, ground_y), k, Color(0.95, 0.97, 1.0))
	if font != null:
		ci.draw_string(font, Vector2(o.x + 6.0, o.y + 15.0), "%.1f M" % r, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(1.0, 0.92, 0.75))
		ci.draw_string(font, Vector2(o.x + rect.size.x - 6.0, o.y + 15.0), "PERSON 1.8 M", HORIZONTAL_ALIGNMENT_RIGHT, -1.0, 11, Color(0.8, 0.85, 0.95, 0.8))


static func _person(ci: CanvasItem, foot: Vector2, k: float, col: Color) -> void:
	var h := PERSON_H * k
	var w := PERSON_W * k
	ci.draw_rect(Rect2(foot.x - w * 0.5, foot.y - h * 0.78, w, h * 0.78), col)                 # body and legs
	ci.draw_circle(Vector2(foot.x, foot.y - h * 0.9), maxf(h * 0.11, 1.5), col)                  # head
