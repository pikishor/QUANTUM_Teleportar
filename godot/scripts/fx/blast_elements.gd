class_name BlastElements
extends RefCounted
## The five blast elements and what makes each one look different (owner: "more colours in blasts"). An element is a palette and a set of habits, not a new effect:
##   fire      orange fireball, charcoal smoke and debris, soot scorch on the street
##   plasma    cyan fireball with a white-hot core, cyan embers, glowing cyan fluid
##   quantum   violet collapse (ripple ring, no smoke), pink-white motes, violet fluid
##   toxic     acid green fireball with a dark green cloud, thick green goo that pools
##   electric  blue-white flash, long sparks and forked arcs, blue fluid
## `of_color(color)` guesses the element from the colour a caller already passes to Game.explode / FX.blast (every old call site keeps working and now looks right);
## pass `element` in the Game.explode options to force one. Palettes (colours and gradients) are built once and cached.
## Used by scripts/fx/explosion_pool.gd (fireball, smoke, sparks, debris, light), scripts/fx/blast_marks.gd (scorch, liquid, cracks) and autoload/game.gd.

const FIRE := &"fire"
const PLASMA := &"plasma"
const QUANTUM := &"quantum"
const TOXIC := &"toxic"
const ELECTRIC := &"electric"
const ALL: Array[StringName] = [FIRE, PLASMA, QUANTUM, TOXIC, ELECTRIC]

## mid / hot / lo: fireball ramp. smoke: tint of the rising cloud. light: the flash. fluid: the liquid the blast leaves on the street (core colour; the shader adds the rim),
## glow: how much that fluid glows (0 = dark oil). arcs: forked lightning bolts. spark: 3 colours of the spark ramp. chunk: debris ramp (hot -> cold). shake: camera shake factor.
const DATA := {
	&"fire": {"mid": Color(1.0, 0.5, 0.12), "hot": Color(1.0, 0.93, 0.7), "lo": Color(0.3, 0.06, 0.02), "smoke": Color(0.5, 0.46, 0.44), "light": Color(1.0, 0.55, 0.2),
		"fluid": Color(0.07, 0.05, 0.05), "glow": 0.0, "arcs": 0, "shake": 1.0, "ring": Color(1.0, 0.62, 0.28),
		"spark": [Color(1.0, 0.97, 0.85), Color(1.0, 0.7, 0.3), Color(1.0, 0.35, 0.1)], "chunk": [Color(1.0, 0.55, 0.2), Color(0.6, 0.24, 0.08), Color(0.12, 0.1, 0.09)]},
	&"plasma": {"mid": Color(0.2, 0.9, 1.0), "hot": Color(0.85, 1.0, 1.0), "lo": Color(0.02, 0.2, 0.4), "smoke": Color(0.3, 0.5, 0.58), "light": Color(0.35, 0.9, 1.0),
		"fluid": Color(0.1, 0.85, 1.0), "glow": 1.0, "arcs": 0, "shake": 0.9, "ring": Color(0.45, 0.95, 1.0),
		"spark": [Color(0.9, 1.0, 1.0), Color(0.3, 0.9, 1.0), Color(0.05, 0.4, 1.0)], "chunk": [Color(0.4, 0.95, 1.0), Color(0.12, 0.4, 0.55), Color(0.05, 0.1, 0.14)]},
	&"quantum": {"mid": Color(0.62, 0.25, 1.0), "hot": Color(1.0, 0.85, 1.0), "lo": Color(0.3, 0.02, 0.55), "smoke": Color(0.4, 0.3, 0.55), "light": Color(0.7, 0.4, 1.0),
		"fluid": Color(0.62, 0.2, 1.0), "glow": 1.2, "arcs": 0, "shake": 1.0, "ring": Color(0.75, 0.4, 1.0),
		"spark": [Color(1.0, 0.92, 1.0), Color(0.85, 0.5, 1.0), Color(0.45, 0.1, 0.9)], "chunk": [Color(0.85, 0.5, 1.0), Color(0.35, 0.12, 0.55), Color(0.08, 0.04, 0.12)]},
	&"toxic": {"mid": Color(0.5, 1.0, 0.15), "hot": Color(0.95, 1.0, 0.6), "lo": Color(0.05, 0.25, 0.02), "smoke": Color(0.28, 0.42, 0.2), "light": Color(0.55, 1.0, 0.25),
		"fluid": Color(0.4, 0.95, 0.08), "glow": 0.8, "arcs": 0, "shake": 0.95, "ring": Color(0.65, 1.0, 0.3),
		"spark": [Color(0.95, 1.0, 0.7), Color(0.55, 1.0, 0.2), Color(0.15, 0.6, 0.05)], "chunk": [Color(0.6, 1.0, 0.25), Color(0.2, 0.42, 0.08), Color(0.06, 0.1, 0.05)]},
	&"electric": {"mid": Color(0.3, 0.55, 1.0), "hot": Color(0.9, 0.95, 1.0), "lo": Color(0.04, 0.08, 0.45), "smoke": Color(0.32, 0.36, 0.5), "light": Color(0.5, 0.7, 1.0),
		"fluid": Color(0.2, 0.45, 1.0), "glow": 1.1, "arcs": 4, "shake": 1.0, "ring": Color(0.6, 0.78, 1.0),
		"spark": [Color(1.0, 1.0, 1.0), Color(0.6, 0.8, 1.0), Color(0.2, 0.35, 1.0)], "chunk": [Color(0.7, 0.85, 1.0), Color(0.25, 0.3, 0.55), Color(0.06, 0.07, 0.12)]},
}

static var _ramps := {}


## The element a colour belongs to: red / orange / yellow / white = fire, green = toxic, cyan = plasma, blue = electric, violet / magenta = quantum.
static func of_color(c: Color) -> StringName:
	if c.s < 0.22:
		return FIRE
	var h := c.h
	if h < 0.17 or h >= 0.97:
		return FIRE
	if h < 0.43:
		return TOXIC
	if h < 0.545:
		return PLASMA
	if h < 0.70:
		return ELECTRIC
	return QUANTUM


static func valid(id: StringName) -> bool:
	return DATA.has(id)


static func data(id: StringName) -> Dictionary:
	return DATA.get(id, DATA[FIRE])


## Colour of one entry (mid, hot, lo, smoke, light, fluid, ring).
static func color(id: StringName, key: String) -> Color:
	return data(id)[key]


## Spark ramp of the element: near-white core, the element colour, then fading out.
static func spark_ramp(id: StringName) -> Gradient:
	return _ramp(id, &"spark")


## Debris ramp: glowing at the start, then cold and dark.
static func chunk_ramp(id: StringName) -> Gradient:
	return _ramp(id, &"chunk")


static func _ramp(id: StringName, key: StringName) -> Gradient:
	var k := StringName("%s_%s" % [id, key])
	if _ramps.has(k):
		return _ramps[k]
	var cols: Array = data(id)[String(key)]
	var g := Gradient.new()
	if key == &"spark":
		g.set_color(0, Color(cols[0].r, cols[0].g, cols[0].b, 1.0))
		g.add_point(0.3, Color(cols[1].r, cols[1].g, cols[1].b, 0.9))
		g.set_color(g.get_point_count() - 1, Color(cols[2].r, cols[2].g, cols[2].b, 0.0))
	else:
		g.set_color(0, Color(cols[0].r, cols[0].g, cols[0].b, 1.0))
		g.add_point(0.45, Color(cols[1].r, cols[1].g, cols[1].b, 1.0))
		g.add_point(0.8, Color(cols[2].r, cols[2].g, cols[2].b, 1.0))
		g.set_color(g.get_point_count() - 1, Color(cols[2].r * 0.4, cols[2].g * 0.4, cols[2].b * 0.4, 0.0))
	_ramps[k] = g
	return g
